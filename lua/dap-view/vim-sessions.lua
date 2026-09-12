local globals = require("dap-view.globals")
local setup = require("dap-view.setup")
local state = require("dap-view.state")

local M = {}

local api = vim.api

-- From :h 'sessionoptions', only globals starting with an uppercase letter
-- (and containing at least a single lowercase letter) are restored
-- By using 'Dapview' (instead of 'DapView') we avoid potential conflicts with DAP
local SESSION_VARIABLES = {
    section = "DapviewSection",
    expr_count = "DapviewExprCount",
    watches = "DapviewWatches",
    tabpage = "DapviewTabpage",
}

---The tab host keeps `tabpage` up to date while it owns one; nothing else here
---writes it, and `load_session_hook` is what consumes it
M.SESSION_VARIABLES = SESSION_VARIABLES

M.save_state = function()
    vim.g[SESSION_VARIABLES["section"]] = state.current_section

    -- We have to restore the `expr_count` so we can properly append new expressions
    -- (since the expression count is always incremented)
    vim.g[SESSION_VARIABLES["expr_count"]] = state.expr_count

    -- From :h 'sessionoptions', only string and number variables are stored
    -- No bother, converting to a string and back seems fine
    vim.g[SESSION_VARIABLES["watches"]] = vim.json.encode(state.watched_expressions)
end

-- This could be exposed, so people could force restoring the state
M.restore_state = function()
    state.current_section = vim.g[SESSION_VARIABLES["section"]]

    -- If config changes, the old session may no longer be enabled
    if not vim.tbl_contains(setup.config.winbar.sections, state.current_section) then
        state.current_section = setup.config.winbar.default_section
    end

    state.expr_count = vim.g[SESSION_VARIABLES["expr_count"]] or 0

    state.watched_expressions = vim.json.decode(vim.g[SESSION_VARIABLES["watches"]] or "{}") or {}
end

---Tabpages the restored session left behind for us.
---
---A host that owns a whole tabpage owns everything in it, the code window
---included, so a restored tabpage that held *any* of the buffers we are about to
---delete is the debugger's and goes whole. A host that lives in the user's own
---tabpage only gets to reclaim a tabpage whose *every* window held one of them.
---@param doomed integer[]
---@return integer[]
local stale_tabpages = function(doomed)
    local owns_tabpage = require("dap-view.host").get().owns_tabpage

    local stale = {}

    for _, page in ipairs(api.nvim_list_tabpages()) do
        local wins = api.nvim_tabpage_list_wins(page)

        local held = false
        local only = #wins > 0

        for _, win in ipairs(wins) do
            if vim.tbl_contains(doomed, api.nvim_win_get_buf(win)) then
                held = true
            else
                only = false
            end
        end

        if (owns_tabpage and held) or only then
            table.insert(stale, page)
        end
    end

    return stale
end

---@param pages integer[]
local close_tabpages = function(pages)
    if #pages == 0 then
        return
    end

    local current = api.nvim_get_current_tabpage()

    for _, page in ipairs(pages) do
        -- Never take Neovim down with the last tabpage. The number is recomputed
        -- each time on purpose: closing one shifts every tabpage after it
        if #api.nvim_list_tabpages() > 1 and api.nvim_tabpage_is_valid(page) then
            -- `:tabclose` takes a range, not a count
            pcall(vim.cmd.tabclose, { range = { api.nvim_tabpage_get_number(page) }, bang = true })
        end
    end

    -- Land where the restore left the user, or on the first tabpage when that is
    -- one of the ones we just closed
    local target = api.nvim_tabpage_is_valid(current) and current or api.nvim_list_tabpages()[1]

    pcall(api.nvim_set_current_tabpage, target)
end

---The tabpage the tab host marked before the session was written, if the restore
---brought the marker back and it still resolves to something.
---
---Session files address tabpages by number, so the value is an index into the
---restored tabpage list rather than a handle. Always consumed, even when it is
---not ours to act on: a marker left over from a session written under the tab
---host must not outlive this restore under another one
---@return integer?
local marked_tabpage = function()
    local number = vim.g[SESSION_VARIABLES["tabpage"]]

    vim.g[SESSION_VARIABLES["tabpage"]] = nil

    if type(number) ~= "number" or not require("dap-view.host").get().owns_tabpage then
        return
    end

    return api.nvim_list_tabpages()[number]
end

M.load_session_hook = function()
    ---Buffers the restore brought back that we have to drop: the filetype
    ---information for the REPL may have been lost, and likewise for the terminal
    ---@type integer[]
    local doomed = {}

    for _, buf in ipairs(api.nvim_list_bufs()) do
        local name = api.nvim_buf_get_name(buf)

        if name == globals.MAIN_BUF_NAME or name:match("%[dap%-repl%-%d+%]$") or name:match("%[dap%-terminal%] ") then
            table.insert(doomed, buf)
        end
    end

    -- The buffer rule alone is not enough to notice a restored debugger: with a
    -- 'sessionoptions' of `buffers,curdir,tabpages,winsize,help,globals,skiprtp,
    -- folds`, `:mksession` writes none of the buffers above -- `buffers` only
    -- saves *listed* ones, and all of ours are unlisted -- so `doomed` comes out
    -- empty even though the tabpage came back, husk and all
    local marked = marked_tabpage()

    if #doomed == 0 and not marked then
        return
    end

    -- Computed before the deletion: once the buffers are gone, their windows show
    -- a fresh empty buffer instead and nothing points back at the debugger
    local stale = stale_tabpages(doomed)

    if marked and not vim.tbl_contains(stale, marked) then
        table.insert(stale, marked)
    end

    for _, buf in ipairs(doomed) do
        api.nvim_buf_delete(buf, { force = true })
    end

    M.restore_state()

    -- Must schedule to properly restore breakpoints
    -- Otherwise might restore before the signs load
    -- NOTE: restoring the actual breakpoints is done by another plugin
    --
    -- The tabpages must wait for the schedule too: `SessionLoadPost` is fired by
    -- `doautoall`, and closing a tabpage from inside it is refused with an error
    -- that Neovim (0.12.4) then re-throws forever, wedging the editor
    vim.schedule(function()
        -- Otherwise the restored debugger tabpage lingers as a husk and the
        -- `open` below adds a second one next to it
        close_tabpages(stale)

        require("dap-view.actions").open()
    end)
end

return M
