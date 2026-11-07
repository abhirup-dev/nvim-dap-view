local M = {}

local fn = vim.fn
local api = vim.api

---Never let `"auto"` squeeze the value segment below this many cells
local MIN_AUTO_WIDTH = 10

---@class dapview.FormatValueOpts
---@field name_col integer Display cells already taken by the indent, the icon, the name and `" = "`
---@field variable? dap.Variable|dap.EvaluateResponse Node the value belongs to, for future formatters
---@field path? string Variable path of the node, for future formatters

---`strdisplaywidth` throws (E976) on embedded NUL bytes. Fall back to the byte count, which is an
---upper bound for well formed UTF-8 (so we clamp a bit early instead of overflowing the window).
---@param s string
---@return integer
M.display_width = function(s)
    local ok, w = pcall(fn.strdisplaywidth, s)
    return ok and w or #s
end

---Byte length of the UTF-8 sequence starting at `i`.
---Hand rolled because `vim.str_utf_pos` stops at the first NUL byte.
---@param s string
---@param i integer
---@return integer
local char_len = function(s, i)
    local b = s:byte(i)

    local len = 1
    if b == nil or b < 0xC0 then
        len = 1
    elseif b < 0xE0 then
        len = 2
    elseif b < 0xF0 then
        len = 3
    else
        len = 4
    end

    return math.min(len, #s - i + 1)
end

---@param ch string A single character
---@return integer
local char_width = function(ch)
    local b = ch:byte(1)

    -- Control characters render as `^X`
    if b < 0x20 or b == 0x7F then
        return 2
    elseif b < 0x80 then
        return 1
    end

    local ok, w = pcall(api.nvim_strwidth, ch)

    return ok and w or 1
end

---Display cells taken by an indented prefix, using the view buffer's `tabstop`
---@param depth integer Number of leading tabs
---@param text string
---@return integer
M.name_col = function(depth, text)
    local state = require("dap-view.state")
    local tabstop = require("dap-view.util").is_buf_valid(state.bufnr) and vim.bo[state.bufnr].tabstop or vim.o.tabstop

    return depth * tabstop + M.display_width(text)
end

---`getwininfo().textoff` is 0 for a window that has never been drawn, which is
---exactly the case for the first render after a stop: the tab host focuses the
---code window, so the dap-view window is not current when the tree is first
---built, and every line ends up measured against the full window width. Derive
---the offset from the options instead, rounding up rather than down, so a stale
---guess clamps early instead of overflowing.
---@param winnr integer
---@return integer
M.textoff_from_options = function(winnr)
    local wo = vim.wo[winnr][0]
    local offset = 0

    local signcolumn = wo.signcolumn

    -- `number` merges the signs into the number column, so it costs nothing
    if signcolumn ~= "no" and signcolumn ~= "number" then
        -- `yes:N` and `auto:N` cap at N columns of two cells; a bare `yes` or
        -- `auto` is one column
        offset = offset + 2 * (tonumber(signcolumn:match(":(%d+)$")) or 1)
    end

    if wo.number or wo.relativenumber then
        offset = offset + math.max(wo.numberwidth, 1)
    end

    offset = offset + (tonumber(wo.foldcolumn:match("(%d+)$")) or 0)

    return offset
end

---Display cells `winnr` has for text: its width less the sign, number and fold
---columns, which `nvim_win_get_width` includes but no text ever reaches
---@param winnr integer
---@return integer?
M.text_width = function(winnr)
    local ok, win_width = pcall(api.nvim_win_get_width, winnr)

    if not ok then
        return nil
    end

    local wininfo = fn.getwininfo(winnr)[1]
    local textoff = wininfo and wininfo.textoff or 0

    if textoff == 0 then
        textoff = M.textoff_from_options(winnr)
    end

    return win_width - textoff
end

---Resolve `tree.max_value_width` for a value starting at `name_col`
---@param name_col integer
---@return integer|false
M.limit = function(name_col)
    local max_value_width = require("dap-view.setup").config.tree.max_value_width

    if max_value_width == false then
        return false
    end

    if max_value_width == "auto" then
        local state = require("dap-view.state")
        local winnr = require("dap-view.util").is_win_valid(state.winnr) and state.winnr or api.nvim_get_current_win()

        local text_width = M.text_width(winnr)

        if not text_width then
            return false
        end

        return math.max(text_width - name_col, MIN_AUTO_WIDTH)
    end

    return max_value_width
end

---Clamp `value` to `limit` display cells, appending `ellipsis`. Never splits a multibyte character.
---@param value string
---@param limit integer|false
---@param ellipsis string
---@return string clamped
---@return boolean truncated
M.clamp = function(value, limit, ellipsis)
    if not limit or limit <= 0 or M.display_width(value) <= limit then
        return value, false
    end

    local budget = math.max(limit - M.display_width(ellipsis), 0)

    local acc = 0
    local i = 1

    while i <= #value do
        local len = char_len(value, i)
        local width = char_width(value:sub(i, i + len - 1))

        if acc + width > budget then
            break
        end

        acc = acc + width
        i = i + len
    end

    return value:sub(1, i - 1) .. ellipsis, true
end

---Single entry point for turning a raw DAP value into what a tree line shows:
---linebreaks collapsed (`nvim_buf_set_lines` rejects them) and the value segment clamped
---@param value string
---@param opts dapview.FormatValueOpts
---@return string display
---@return boolean truncated
M.format_value = function(value, opts)
    local tree = require("dap-view.setup").config.tree

    -- Can't have linebreaks with nvim_buf_set_lines
    local flat = value:gsub("[\r\n]+", " ")

    return M.clamp(flat, M.limit(opts.name_col), tree.ellipsis)
end

---Split a raw DAP value on its original linebreaks, for the full value float
---@param value string
---@return string[]
M.split = function(value)
    local normalized = value:gsub("\r\n", "\n"):gsub("\r", "\n")

    return vim.split(normalized, "\n", { plain = true })
end

return M
