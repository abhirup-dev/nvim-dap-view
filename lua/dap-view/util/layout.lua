local M = {}

local api = vim.api

---The window sizes of one tabpage, captured so they can be handed back.
---
---`winlayout()` and `winrestcmd()` are both relative to the current tabpage, and
---`winrestcmd()` addresses windows by their (tabpage local) number. Replaying it
---is therefore only safe once the layout tree is identical to the snapshot again,
---which is exactly what `restore` checks. `winlayout()` carries no sizes, so the
---check never makes the restore redundant -- and it subsumes a window count
---comparison, since its leaves are `{ "leaf", <winid> }`: a tabpage that lost one
---window and gained another is caught here and would not be by a count
---@class dapview.LayoutSnapshot
---@field tabpage integer
---@field layout any
---@field restcmd string

---Run `fn` with `page` as the current tabpage and return what it returns.
---
---`nvim_tabpage_call` does not exist on 0.12.4 (probed). Entering one of the
---tabpage's windows is the same thing here: both `winlayout()` and `winrestcmd()`
---are tabpage scoped, and `nvim_win_call` puts the previous window -- and
---therefore the previous tabpage -- back afterwards
---@generic T
---@param page integer
---@param fn fun(): T
---@return T?
local in_tabpage = function(page, fn)
    local ok, win = pcall(api.nvim_tabpage_get_win, page)

    if not ok or not win or not api.nvim_win_is_valid(win) then
        return
    end

    local out

    api.nvim_win_call(win, function()
        out = fn()
    end)

    return out
end

---@param page? integer Defaults to the current tabpage
---@return dapview.LayoutSnapshot?
M.snapshot = function(page)
    page = page or api.nvim_get_current_tabpage()

    if not api.nvim_tabpage_is_valid(page) then
        return
    end

    return in_tabpage(page, function()
        return {
            tabpage = page,
            layout = vim.fn.winlayout(),
            restcmd = vim.fn.winrestcmd(),
        }
    end)
end

---Put the captured sizes back, if the tabpage is still shaped the way it was.
---Never an error: a snapshot that no longer applies is simply dropped
---@param snap dapview.LayoutSnapshot?
---@return boolean restored
M.restore = function(snap)
    if not snap or not api.nvim_tabpage_is_valid(snap.tabpage) then
        return false
    end

    local restored = in_tabpage(snap.tabpage, function()
        if not vim.deep_equal(vim.fn.winlayout(), snap.layout) then
            return false
        end

        return (pcall(vim.cmd, snap.restcmd))
    end)

    return restored or false
end

return M
