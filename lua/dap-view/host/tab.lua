local dap = require("dap")

local setup = require("dap-view.setup")
local state = require("dap-view.state")
local term = require("dap-view.console.view")
local util = require("dap-view.util")

---Tab host: the dap-view window, the terminal window and a code window live in a
---dedicated tabpage, so opening and closing the debugger never touches the
---layout of the tabpage the user came from.
---
---Verified on Neovim 0.12.4 (headless, `-u NONE`):
---
---  nvim_open_win(buf, false, { split = "below", win = <win in another tabpage> })
---
---does create the split in that other tabpage, and leaves the current tabpage
---alone (probe: tab 1 kept `{ 1000 }`, tab 2 became `{ 1001, 1002 }`, current
---tabpage stayed 1). With `enter = true` the same call also *moves* the current
---tabpage. So no patch to `actions.lua` is needed to target a foreign tabpage;
---we open with `enter = false` and take focus explicitly where we want it.
---@type dapview.Host
local M = {}

local api = vim.api

---Upstream already owns the "dap-view" subscription id (see `listeners.lua`);
---reusing it here would silently unregister its handlers
local SUBSCRIPTION_ID = "dap-view-host-tab"

---@type integer?
local tabpage
---@type integer?
local code_winnr
---@type integer?
local origin_tabpage

---Run `fn` with the autocmds that react to layout changes muted.
---
---`tabnew`/`tabclose` would otherwise fire dap-view's own `TabEnter` handler in
---the middle of an open (which reenters `actions.open` when `follow_tab` is set,
---and clobbers `state.last_term_winnr` regardless) plus the `WinNew`/`WinClosed`
---resize handler.
---@param fn fun()
local without_layout_autocmds = function(fn)
    local eventignore = vim.o.eventignore

    vim.o.eventignore = "TabEnter,TabLeave,TabNew,TabNewEntered,TabClosed,WinNew,WinEnter,WinLeave,WinClosed"

    local ok, err = pcall(fn)

    vim.o.eventignore = eventignore

    if not ok then
        error(err, 0)
    end
end

---@return integer
local dapview_width = function()
    local size = setup.config.windows.size
    local size_ = (type(size) == "function" and size(state.win_pos)) or size

    ---@cast size_ number

    return math.floor(size_ < 1 and vim.go.columns * size_ or size_)
end

---The code window, when the layout has one and the host is open
---@return integer?
local get_code_winnr = function()
    if M.is_open() and util.is_win_valid(code_winnr) then
        return code_winnr
    end
end

---@param bufnr integer
---@param _ boolean? hide_terminal, unused: the terminal lives in the tabpage we close
---@return integer
M.open = function(bufnr, _)
    local layout = setup.config.host.tab.layout

    local origin_bufnr = api.nvim_get_current_buf()

    origin_tabpage = api.nvim_get_current_tabpage()

    without_layout_autocmds(function()
        vim.cmd.tabnew()

        tabpage = api.nvim_get_current_tabpage()
        code_winnr = api.nvim_get_current_win()

        -- Show whatever the user was looking at, rather than an empty buffer
        local scratch = api.nvim_win_get_buf(code_winnr)
        if util.is_buf_valid(origin_bufnr) and vim.bo[origin_bufnr].buftype == "" then
            api.nvim_win_set_buf(code_winnr, origin_bufnr)

            if api.nvim_buf_get_name(scratch) == "" and not vim.bo[scratch].modified then
                pcall(api.nvim_buf_delete, scratch, { force = true })
            end
        end

        -- The terminal belongs to our tabpage. Any leftover term window is
        -- necessarily somewhere else, since this tabpage was just created
        for _, winnr in ipairs({ state.last_term_winnr, state.term_winnr }) do
            if util.is_win_valid(winnr) then
                pcall(api.nvim_win_close, winnr, true)
            end
        end

        state.last_term_winnr = nil
        state.term_winnr = nil
    end)

    ---@cast code_winnr integer

    local winnr

    if layout == "full" then
        -- The dap-view window *is* the tabpage: there's no code window
        api.nvim_win_set_buf(code_winnr, bufnr)
        winnr = code_winnr
        code_winnr = nil
    else
        state.win_pos = layout == "code-right" and "left" or "right"

        winnr = api.nvim_open_win(bufnr, false, {
            split = state.win_pos,
            win = code_winnr,
            width = dapview_width(),
        })
    end

    -- `attach_window` sets this too, but `open_term_buf_win` needs it right now
    state.winnr = winnr

    -- We own the whole tabpage, so there's nothing for the `WinNew`/`WinClosed`
    -- handler in `autocmds.lua` to keep at a fixed size
    state.og_height = nil
    state.og_width = nil

    if not vim.tbl_contains(setup.config.winbar.sections, "console") then
        term.open_term_buf_win()
    end

    return winnr
end

---@param hide_terminal? boolean
M.close = function(hide_terminal)
    local target = tabpage

    tabpage = nil
    code_winnr = nil

    if target and api.nvim_tabpage_is_valid(target) then
        without_layout_autocmds(function()
            if #api.nvim_list_tabpages() > 1 then
                if api.nvim_get_current_tabpage() == target and origin_tabpage then
                    if api.nvim_tabpage_is_valid(origin_tabpage) then
                        -- Land back where the user came from
                        api.nvim_set_current_tabpage(origin_tabpage)
                    end
                end

                -- `:tabclose` takes a range, not a count
                pcall(vim.cmd.tabclose, { range = { api.nvim_tabpage_get_number(target) }, bang = true })
            elseif util.is_win_valid(state.winnr) then
                -- Only tabpage left: closing it would take Neovim down with it
                pcall(api.nvim_win_close, state.winnr, true)
            end
        end)
    end

    origin_tabpage = nil

    state.winnr = nil
    state.term_winnr = nil
    state.last_term_winnr = nil

    if hide_terminal then
        term.hide_term_buf_win()
    end
end

M.is_open = function()
    return (tabpage ~= nil and api.nvim_tabpage_is_valid(tabpage) and util.is_win_valid(state.winnr)) and true or false
end

---nvim-dap jumps to the stopped frame itself, from whatever window happens to be
---current when the `stackTrace` response lands (`jump_to_location` in nvim-dap's
---`session.lua` captures `nvim_get_current_win()`). Focusing the tab's code
---window up front is therefore what keeps the source out of the user's original
---tabpage; the `after.scopes` hook below only backstops `switchbuf` values that
---wander off (`usetab` will follow the buffer into another tabpage).
dap.listeners.before.event_stopped[SUBSCRIPTION_ID] = function()
    if not setup.config.host.tab.follow_frame then
        return
    end

    local code_win = get_code_winnr()

    if not code_win then
        return
    end

    api.nvim_set_current_tabpage(tabpage)
    api.nvim_set_current_win(code_win)
end

---@param session dap.Session
dap.listeners.after.scopes[SUBSCRIPTION_ID] = function(session)
    if not setup.config.host.tab.follow_frame then
        return
    end

    local code_win = get_code_winnr()

    if not code_win then
        return
    end

    local frame = session.current_frame

    if not frame or not require("dap-view.util.source").source_exists(frame) then
        return
    end

    local path = vim.fn.fnamemodify(frame.source.path, ":p")

    -- `jump_to_location` reports missing files. Frames backed by a source
    -- request have no file on disk and were handled by the pre-positioning above
    if not vim.uv.fs_stat(path) then
        return
    end

    local frame_bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))

    if api.nvim_get_current_tabpage() == tabpage and api.nvim_win_get_buf(code_win) == frame_bufnr then
        -- nvim-dap already landed where we want it
        return
    end

    api.nvim_set_current_tabpage(tabpage)

    -- Reuse upstream's jump machinery, pinning the target window through the
    -- `switchbuffun` hook it already supports
    require("dap-view.views.util").jump_to_location(path, frame.line, nil, function()
        return code_win
    end)
end

local close_on_terminate = { "event_terminated", "disconnect" }

for _, listener in ipairs(close_on_terminate) do
    dap.listeners.after[listener][SUBSCRIPTION_ID] = function()
        if not setup.config.host.tab.close_on_terminate or not M.is_open() then
            return
        end

        -- Same reasoning as upstream's `auto_toggle`: don't tear the tabpage down
        -- while other sessions are still running
        if vim.tbl_count(dap.sessions()) > 1 then
            return
        end

        require("dap-view.actions").close()
    end
end

return M
