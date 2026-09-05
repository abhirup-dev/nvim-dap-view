local setup = require("dap-view.setup")
local state = require("dap-view.state")
local term = require("dap-view.console.view")
local util = require("dap-view.util")

---Split host: a split in the current tabpage. This is the upstream layout, moved
---here verbatim from `dap-view.actions`, plus an optional window layout snapshot.
---@type dapview.Host
local M = {}

local api = vim.api

---@type {tabpage: integer, layout: any, restcmd: string}?
local snapshot

local take_snapshot = function()
    snapshot = nil

    if not setup.config.host.split.restore_layout then
        return
    end

    snapshot = {
        tabpage = api.nvim_get_current_tabpage(),
        layout = vim.fn.winlayout(),
        restcmd = vim.fn.winrestcmd(),
    }
end

---Restore the window sizes captured before opening.
---
---`winlayout()` and `winrestcmd()` are both relative to the current tabpage, and
---`winrestcmd()` addresses windows by their (tabpage local) number. Replaying it
---is therefore only safe once the layout tree is identical to the snapshot again,
---which is exactly what we check. `winlayout()` carries no sizes, so the check
---never makes the restore redundant.
---
---When the terminal window is deliberately left open (`hide_terminal` is falsy)
---the tree legitimately differs and we skip the restore.
local restore_snapshot = function()
    local snap = snapshot
    snapshot = nil

    if not snap or api.nvim_get_current_tabpage() ~= snap.tabpage then
        return
    end

    if not vim.deep_equal(vim.fn.winlayout(), snap.layout) then
        return
    end

    pcall(vim.cmd, snap.restcmd)
end

---@param bufnr integer
---@param hide_terminal? boolean
---@return integer
M.open = function(bufnr, hide_terminal)
    -- Force closing leftover terminal when reopening, even when not hiding term explicitly
    -- Prevents opening multiple terminal windows
    if not hide_terminal and state.last_term_winnr ~= state.term_winnr and util.is_win_valid(state.last_term_winnr) then
        api.nvim_win_close(state.last_term_winnr, true)
    end

    take_snapshot()

    local separate_term_win = not vim.tbl_contains(setup.config.winbar.sections, "console")
    local term_winnr = separate_term_win and term.open_term_buf_win()

    local is_term_win_valid = util.is_win_valid(term_winnr)

    local windows_config = setup.config.windows
    local term_config = windows_config.terminal

    local position = windows_config.position
    local win_pos = (type(position) == "function" and position(state.win_pos))
        or (type(position) == "string" and position)

    ---@cast win_pos dapview.Position

    local term_position_ = term_config.position
    local term_win_pos = (type(term_position_) == "function" and term_position_(win_pos))
        or (type(term_position_) == "string" and term_position_)

    ---@cast term_win_pos dapview.Position

    local inv_term_position = util.inverted_directions[term_win_pos]

    local anchor_win = windows_config.anchor and windows_config.anchor()
    local is_anchor_win_valid = util.is_win_valid(anchor_win)
    state.anchor_winnr = anchor_win

    local is_vertical = win_pos == "above" or win_pos == "below"

    local term_is_vertical = term_win_pos == "above" or term_win_pos == "below"

    local is_win_valid = is_anchor_win_valid or is_term_win_valid

    local shared_split = term_is_vertical == is_vertical

    local winfix_setting = is_vertical and "winfixheight" or "winfixwidth"

    -- Temporarily disable fixed size
    -- If the window exists, it's using the space of both
    -- Do not touch anchor because we don't own it
    if is_term_win_valid and shared_split then
        vim.wo[state.term_winnr][winfix_setting] = false
    end

    local height, width = require("dap-view.util.size").size()

    state.og_height = height
    state.og_width = width

    local winnr = api.nvim_open_win(bufnr, false, {
        split = is_win_valid and inv_term_position or win_pos,
        win = is_anchor_win_valid and anchor_win or is_term_win_valid and term_winnr or -1,
        height = height,
        width = width,
    })

    -- Assign state only after calling size, for idempotency
    state.win_pos = win_pos

    -- Restore fixed size
    if is_term_win_valid and shared_split then
        vim.wo[state.term_winnr][winfix_setting] = true
    end

    return winnr
end

---@param hide_terminal? boolean
M.close = function(hide_terminal)
    if util.is_win_valid(state.winnr) then
        -- Avoid "E444: Cannot close last window"
        pcall(api.nvim_win_close, state.winnr, true)
    end

    state.winnr = nil

    -- Close leftover terminal (if left open in another tab)
    -- Might not be considered leftover, though. Let the caller decide
    if hide_terminal and state.last_term_winnr ~= state.term_winnr and util.is_win_valid(state.last_term_winnr) then
        api.nvim_win_close(state.last_term_winnr, true)
    end

    if hide_terminal then
        term.hide_term_buf_win()
    end

    restore_snapshot()
end

M.is_open = function()
    return util.is_win_valid(state.winnr) and true or false
end

---Our split can be in a tabpage the user is not looking at, in which case
---upstream's `TabEnter` handler has already nil'd `state.winnr`. The window is
---still ours, so find it again and put it back where `close` can reach it
M.is_active = function()
    if M.is_open() then
        return true
    end

    local winnr = require("dap-view.util.window").fetch_window()

    if winnr then
        state.winnr = winnr
        return true
    end

    return false
end

return M
