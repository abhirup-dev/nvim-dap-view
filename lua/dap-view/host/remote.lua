local dap = require("dap")

local globals = require("dap-view.globals")
local mirror = require("dap-view.util.mirror")
local mux = require("dap-view.host.mux")
local setup = require("dap-view.setup")
local state = require("dap-view.state")
local util = require("dap-view.util")

---Remote host: the dap-view *buffer* is mirrored into a bare Neovim ("the
---viewer") running in a multiplexer pane. The DAP session, every listener and
---all of `dap-view.state` stay in this Neovim ("the owner"); the viewer holds no
---state at all and only forwards keypresses back as `(lhs, line)` pairs, which
---the owner resolves through its line indexed state.
---
---Two things about Neovim's RPC shape the design:
---
---  * Neovim dispatches incoming RPC methods against the API function table
---    only, so a custom `dapview_remote` method is *not* deliverable (probed on
---    0.12.4: the notification is dropped). Keypresses therefore arrive as
---    `nvim_exec_lua("require('dap-view.host.remote').on_key(...)", {lhs, line})`,
---    with the payload as arguments rather than interpolated code.
---  * There is no `ChanClosed` event, but `nvim_get_chan_info` returns an empty
---    dict once the peer is gone, which is cheap enough to poll.
---
---`is_open`/`attach_window` want a window *in the owner*, and so does everything
---downstream: `winbar.set_winbar_opt` writes `vim.wo[state.winnr].winbar`, the
---keymap dispatch below needs an `nvim_win_call` target so `line(".")` reads the
---mirrored cursor, and `set_options` configures folds per window. Rather than
---special casing all of that, the host opens a real but *hidden* float
---(`hide = true`, `focusable = false`) sized to the viewer's actual pane. It is
---never drawn, so the user's layout is untouched, yet it behaves like a normal
---window: verified on 0.12.4 that width/height, `nvim_win_set_cursor`,
---`vim.wo[win].winbar` and `nvim_win_call` (`line(".")`) all work on it.
---@type dapview.Host
local M = {}

local api = vim.api

---Upstream owns the "dap-view" subscription id
local SUBSCRIPTION_ID = "dap-view-host-remote"

---Full buffer snapshots are debounced by this much
local DEBOUNCE_MS = 30

---How often the viewer is checked for liveness
local WATCHDOG_MS = 1000

---How long the viewer gets to create its socket. A cold `nvim --clean` in a pane
---the multiplexer still has to draw is comfortably slower than it sounds
local SOCKET_WAIT_MS = 10000

---Base groups the viewer needs on top of every `NvimDapView*` one, because the
---rendered lines and the winbar link into them
local BASE_HL_GROUPS = {
    "Normal",
    "NormalNC",
    "CursorLine",
    "Comment",
    "TabLine",
    "TabLineSel",
    "TabLineFill",
    "Boolean",
    "String",
    "Number",
    "Float",
    "Function",
    "Constant",
    "Identifier",
    "Conditional",
    "Tag",
    "NonText",
    "DiagnosticError",
    "DiagnosticOk",
    "DiagnosticVirtualTextWarn",
    "qfFileName",
    "qfLineNr",
    "DapBreakpoint",
}

---@class dapview.RemoteViewer
---@field buf integer Mirror buffer, in the viewer
---@field win integer Window showing it, in the viewer
---@field ns integer Extmark namespace, in the viewer
---@field width integer
---@field height integer

---@type integer? RPC channel to the viewer
local chan
---@type string? Socket the viewer listens on
local sock
---@type dapview.RemoteViewer?
local viewer
---@type integer? Hidden float standing in for the remote window
local placeholder
---@type string? Opaque multiplexer handle for the pane the viewer runs in
local handle

---@type uv.uv_timer_t?
local debounce
---@type uv.uv_timer_t?
local watchdog
local flush_pending = false

---@type string?
local mirrored_winbar
---@type dapview.Section?
local mirrored_section

local viewer_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/viewer.lua"

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

---@param args string[]
---@return string
local shell_join = function(args)
    return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end

---The command that brings the viewer up, as a shell string, because every
---multiplexer takes the child as one argument
---@return string
local viewer_command = function()
    local args = { vim.v.progpath }

    vim.list_extend(args, setup.config.host.remote.nvim_args)
    vim.list_extend(args, { "--listen", sock, "-u", viewer_path })

    return shell_join(args)
end

local spawn = function()
    local adapter = mux.get()

    if not adapter.available() then
        error(
            "Multiplexer '"
                .. setup.config.host.remote.multiplexer
                .. "' is not available here. Are you running inside it?"
        )
    end

    handle = adapter.spawn(viewer_command(), mux.spawn_opts())
end

---@return integer
local connect = function()
    local listening = vim.wait(SOCKET_WAIT_MS, function()
        return sock ~= nil and vim.uv.fs_stat(sock) ~= nil
    end, 50)

    if not listening then
        local message = "The remote viewer did not come up within %ds (socket: %s). "
            .. "The pane may still be starting; retry with :DapViewUndock"

        error(message:format(SOCKET_WAIT_MS / 1000, tostring(sock)), 0)
    end

    local connected

    -- The socket file exists a moment before the server accepts on it
    vim.wait(5000, function()
        local ok, result = pcall(vim.fn.sockconnect, "pipe", sock, { rpc = true })

        if ok and result ~= 0 then
            connected = result
            return true
        end

        return false
    end, 50)

    if not connected then
        error("Could not connect to the viewer socket: " .. tostring(sock) .. ". Retry with :DapViewUndock", 0)
    end

    return connected
end

--------------------------------------------------------------------------------
-- Handshake
--------------------------------------------------------------------------------

---Everything the viewer must be able to react to. The viewer knows nothing about
---what a key means, it only needs the set of left hand sides
---@return string[]
local forwarded_keymaps = function()
    local config = setup.config
    local seen = {}
    local lhss = {}

    local add = function(lhs)
        for _, key in ipairs(type(lhs) == "table" and lhs or { lhs }) do
            if type(key) == "string" and not seen[key] then
                seen[key] = true
                lhss[#lhss + 1] = key
            end
        end
    end

    for _, section in ipairs({ "base", "scopes", "watches", "threads", "breakpoints", "exceptions", "sessions" }) do
        for _, lhs in pairs(config.keymaps[section] or {}) do
            add(lhs)
        end
    end

    -- Section letters from the winbar, so `S`/`W`/`B`… switch views from the pane
    for _, view in pairs(config.winbar.sections) do
        local section = config.winbar.custom_sections[view] or config.winbar.base_sections[view]

        if section then
            add(section.keymap)
        end
    end

    return lhss
end

---Resolved attributes for every group the rendered buffer can reference, so a
---`--clean` viewer with no colorscheme still looks like the owner
---@return table<string, vim.api.keyset.highlight>
local highlights = function()
    local hls = {}

    local resolve = function(name)
        local ok, attrs = pcall(api.nvim_get_hl, 0, { name = name, link = false })

        if ok and not vim.tbl_isempty(attrs) then
            hls[name] = attrs
        end
    end

    for name in pairs(api.nvim_get_hl(0, {})) do
        if vim.startswith(name, globals.HL_PREFIX) then
            resolve(name)
        end
    end

    for _, name in ipairs(BASE_HL_GROUPS) do
        resolve(name)
    end

    return hls
end

---@return dapview.RemoteViewer
local attach_viewer = function()
    local tree = setup.config.tree

    vim.rpcrequest(chan, "nvim_set_client_info", "dap-view-owner", {}, "remote", vim.empty_dict(), vim.empty_dict())

    local result = vim.rpcrequest(chan, "nvim_exec_lua", "return _G.dapview_viewer.attach(...)", {
        {
            keymaps = forwarded_keymaps(),
            tabstop = tree.indent_width or nil,
            shiftwidth = tree.fold and 0 or nil,
            fold = tree.fold,
            fold_level = tree.fold_level,
            background = vim.o.background,
            highlights = setup.config.host.remote.mirror_highlights and highlights() or nil,
        },
    })

    return result
end

--------------------------------------------------------------------------------
-- Mirroring
--------------------------------------------------------------------------------

---The buffer currently shown in the dap-view window. Usually `state.bufnr`, but
---the repl and custom sections swap another buffer in
---@return integer?
local mirrored_bufnr = function()
    if util.is_win_valid(state.winnr) then
        return api.nvim_win_get_buf(state.winnr)
    end

    return util.is_buf_valid(state.bufnr) and state.bufnr or nil
end

local fallback

---Push one snapshot of the dap-view buffer to the viewer.
---
---A snapshot rather than a replay of the individual `set_lines` calls: the same
---single atomic batch, but it also picks up the extmarks written directly by the
---threads, breakpoints and alignment renderers, which never go through
---`hl_range`. At a screenful of lines per render this costs less than tracking
---incremental ranges would.
local flush = function()
    flush_pending = false

    if not M.is_open() then
        return fallback()
    end

    local bufnr = mirrored_bufnr()

    if not bufnr then
        return
    end

    ---@cast viewer dapview.RemoteViewer

    local calls = {
        { "nvim_set_option_value", { "modifiable", true, { buf = viewer.buf } } },
        { "nvim_buf_set_lines", { viewer.buf, 0, -1, false, api.nvim_buf_get_lines(bufnr, 0, -1, false) } },
        { "nvim_set_option_value", { "modifiable", false, { buf = viewer.buf } } },
        { "nvim_buf_clear_namespace", { viewer.buf, viewer.ns, 0, -1 } },
    }

    for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, globals.NAMESPACE, 0, -1, { details = true })) do
        local row, col, details = mark[2], mark[3], mark[4]

        -- `details` is otherwise already shaped like `nvim_buf_set_extmark` opts
        details.ns_id = nil
        details.strict = false

        calls[#calls + 1] = { "nvim_buf_set_extmark", { viewer.buf, viewer.ns, row, col, details } }
    end

    local winbar = util.is_win_valid(state.winnr) and vim.wo[state.winnr][0].winbar or nil

    if winbar ~= mirrored_winbar then
        mirrored_winbar = winbar
        calls[#calls + 1] = { "nvim_set_option_value", { "winbar", winbar or "", { win = viewer.win } } }
    end

    -- Following the cursor on every render would fight the viewer's own
    -- movement; a section switch is the one moment the owner knows better
    if state.current_section ~= mirrored_section then
        mirrored_section = state.current_section

        if util.is_win_valid(state.winnr) then
            local line = api.nvim_win_get_cursor(state.winnr)[1]
            calls[#calls + 1] = { "nvim_win_set_cursor", { viewer.win, { line, 0 } } }
        end
    end

    if not pcall(vim.rpcnotify, chan, "nvim_call_atomic", calls) then
        fallback()
    end
end

---Debounced dirty flag. One flush per window at most, always with a trailing
---one, so a burst of renders costs a single round trip
local schedule_flush = function()
    if flush_pending or not chan then
        return
    end

    flush_pending = true

    debounce = debounce or assert(vim.uv.new_timer())

    debounce:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local stop_timers = function()
    for _, timer in ipairs({ debounce, watchdog }) do
        if timer and not timer:is_closing() then
            timer:stop()
            timer:close()
        end
    end

    debounce = nil
    watchdog = nil
    flush_pending = false
end

---The viewer died on its own (pane closed, `:qa` in the pane). Go back to
---whatever host was in charge before undocking
fallback = function()
    if not chan then
        return
    end

    local host = require("dap-view.host")

    if host.name() ~= "remote" then
        return
    end

    local previous = host.previous()

    -- Tear ourselves down first. Nothing here can succeed any more, and leaving
    -- the channel, the socket, the pane handle or the placeholder float behind
    -- would keep the watchdog and every future flush aimed at a dead viewer
    M.close()

    vim.notify("dap-view: remote viewer is gone, falling back to the '" .. previous .. "' host", vim.log.levels.WARN)

    -- `close` just dropped everything `is_active` looks at, so the reopen has to
    -- be asked for explicitly
    host.switch(previous, { reopen = true })
end

local start_watchdog = function()
    watchdog = assert(vim.uv.new_timer())

    watchdog:start(
        WATCHDOG_MS,
        WATCHDOG_MS,
        vim.schedule_wrap(function()
            if not chan then
                return
            end

            if not M.is_open() then
                return fallback()
            end

            -- The repl and custom sections write to a buffer nobody hooks, so
            -- resync them on the watchdog rather than leaving the pane stale
            if mirrored_bufnr() ~= state.bufnr then
                schedule_flush()
            end
        end)
    )
end

---@param bufnr integer
---@param _ boolean? hide_terminal, unused: the remote host owns no local window
---@return integer
M.open = function(bufnr, _)
    M.close()

    sock = vim.fn.tempname() .. ".dap-view.sock"

    local ok, err = pcall(function()
        spawn()
        chan = connect()
        viewer = attach_viewer()
    end)

    if not ok then
        M.close()
        error(err, 0)
    end

    ---@cast viewer dapview.RemoteViewer

    -- A real window, so winbar/cursor/folds behave, but never drawn, so the
    -- user's layout is untouched. Sized to the viewer's actual pane, which is
    -- what makes width dependent rendering (`tree.max_value_width = "auto"`,
    -- winbar labels) match what the pane shows
    placeholder = api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = math.max(viewer.width, 1),
        height = math.max(viewer.height, 1),
        focusable = false,
        zindex = 1,
        hide = true,
        style = "minimal",
    })

    -- We own no split, so there is nothing for the resize handler to keep fixed
    state.og_height = nil
    state.og_width = nil

    mirrored_winbar = nil
    mirrored_section = nil

    mirror.on_render = schedule_flush

    start_watchdog()

    schedule_flush()

    return placeholder
end

---The viewer usually exits on its own `qa!`, taking a shell-less pane with it.
---Asking the multiplexer first keeps us from killing a pane somebody reused
local close_pane = function()
    if not handle then
        return
    end

    local adapter = mux.get()

    if pcall(adapter.is_alive, handle) and adapter.is_alive(handle) then
        pcall(adapter.close, handle)
    end

    handle = nil
end

M.close = function()
    mirror.on_render = nil

    stop_timers()

    if chan then
        pcall(vim.rpcnotify, chan, "nvim_command", "qa!")
        pcall(vim.fn.chanclose, chan)
    end

    chan = nil
    viewer = nil

    close_pane()

    if sock then
        pcall(os.remove, sock)
        sock = nil
    end

    if util.is_win_valid(placeholder) then
        pcall(api.nvim_win_close, placeholder, true)
    end

    placeholder = nil
    state.winnr = nil

    mirrored_winbar = nil
    mirrored_section = nil
end

---Channel liveness is the whole story: `nvim_get_chan_info` empties out as soon
---as the peer is gone, without a round trip
M.is_open = function()
    if not chan or not util.is_win_valid(placeholder) then
        return false
    end

    return not vim.tbl_isempty(api.nvim_get_chan_info(chan))
end

---A dead viewer is still ours to clean up: the channel, the socket file, the
---pane handle and the placeholder float all outlive it
M.is_active = function()
    return (util.is_win_valid(placeholder) or chan ~= nil or handle ~= nil or sock ~= nil) and true or false
end

---Live view of the remote host, for `:checkhealth dap-view`. Read only: the
---fields below are module locals everything else in here mutates
---@return { is_open: boolean, chan: integer?, sock: string?, handle: string?, width: integer?, height: integer? }
M.status = function()
    return {
        is_open = M.is_open(),
        chan = chan,
        sock = sock,
        handle = handle,
        width = viewer and viewer.width or nil,
        height = viewer and viewer.height or nil,
    }
end

--------------------------------------------------------------------------------
-- Action dispatch
--------------------------------------------------------------------------------

---A keypress in the viewer. The viewer has no idea what it means; the owner
---places its cursor on `line` and runs whatever the dap-view buffer maps `lhs`
---to, exactly as if the user had pressed it in a local window
---The viewer's pane changed size. The placeholder is what every width dependent
---renderer measures against (`tree.max_value_width = "auto"`, winbar labels), so
---it has to follow the pane, and the re-render has to be asked for: floats emit
---no `WinResized` (probed on 0.12.4, hidden or not), which is why `autocmds.lua`
---exports its refresh
---@param width integer
---@param height integer
M.on_resize = function(width, height)
    vim.schedule(function()
        if not viewer then
            return
        end

        width = math.max(width or 0, 1)
        height = math.max(height or 0, 1)

        if width == viewer.width and height == viewer.height then
            return
        end

        viewer.width = width
        viewer.height = height

        if util.is_win_valid(placeholder) then
            -- A partial config keeps `hide`, `focusable` and the position
            pcall(api.nvim_win_set_config, placeholder, { width = width, height = height })
        end

        require("dap-view.autocmds").refresh_auto_width()

        -- The winbar and anything else laid out against the window width are
        -- stale even when the tree is not
        schedule_flush()
    end)
end

---@param lhs string
---@param line integer
M.on_key = function(lhs, line)
    vim.schedule(function()
        if not util.is_win_valid(state.winnr) or not util.is_buf_valid(state.bufnr) then
            return
        end

        local bufnr = mirrored_bufnr()

        if not bufnr then
            return
        end

        local target = math.max(1, math.min(line, api.nvim_buf_line_count(bufnr)))

        pcall(api.nvim_win_set_cursor, state.winnr, { target, 0 })

        local keys = api.nvim_replace_termcodes(lhs, true, true, true)

        ---@type table?
        local map

        for _, candidate in ipairs(api.nvim_buf_get_keymap(bufnr, "n")) do
            if api.nvim_replace_termcodes(candidate.lhs, true, true, true) == keys then
                map = candidate
                break
            end
        end

        if not map then
            return
        end

        -- `nvim_win_call` so `line(".")` inside upstream actions reads the
        -- window we just positioned
        api.nvim_win_call(state.winnr, function()
            if map.callback then
                map.callback()
            elseif map.rhs and map.rhs ~= "" then
                api.nvim_feedkeys(api.nvim_replace_termcodes(map.rhs, true, true, true), "n", false)
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Session and editor lifecycle
--------------------------------------------------------------------------------

api.nvim_create_autocmd("VimLeavePre", {
    group = api.nvim_create_augroup("dap-view-host-remote", { clear = true }),
    callback = function()
        M.close()
    end,
})

for _, listener in ipairs({ "event_terminated", "disconnect" }) do
    dap.listeners.after[listener][SUBSCRIPTION_ID] = function()
        if not setup.config.host.remote.close_on_terminate or not M.is_open() then
            return
        end

        -- Same reasoning as upstream's `auto_toggle`: leave the pane alone while
        -- other sessions are still running
        if vim.tbl_count(dap.sessions()) > 1 then
            return
        end

        require("dap-view.actions").close()
    end
end

return M
