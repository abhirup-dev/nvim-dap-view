---Value clamping and the full-value store.
---
---dap-view's `format_value` is NOT reusable here: it resolves its budget from
---`dap-view.setup.config.tree.max_value_width` and, for "auto", from the
---dap-view window's geometry -- it clamps to a UI window, not to our
---`response.max_value_width`. So we reuse its pure primitives (`clamp`,
---`display_width`), which are exactly the interesting part, and supply our own
---budget. Without dap-view we fall back to a local clamp with the same shape.
local M = {}

local config = require("dap-mcp.config")

local ELLIPSIS = "..."
local LRU_CAPACITY = 200

---@return table? dap-view's truncate module, when it is usable
local function dapview_truncate()
    if not config.config.ui.integrate_dap_view then
        return nil
    end

    local ok, truncate = pcall(require, "dap-view.util.truncate")

    return ok and truncate or nil
end

---@param s string
---@return integer
local function display_width(s)
    local truncate = dapview_truncate()
    if truncate then
        return truncate.display_width(s)
    end

    -- `strdisplaywidth` throws E976 on embedded NUL bytes; the byte count is an
    -- upper bound for well formed UTF-8, so we clamp early rather than overflow.
    local ok, width = pcall(vim.fn.strdisplaywidth, s)

    return ok and width or #s
end

M.display_width = display_width

---Byte length of the UTF-8 sequence starting at `i`. Hand rolled, as dap-view
---does, because `vim.str_utf_end` stops at the first NUL byte.
---@param s string
---@param i integer
---@return integer
local function char_len(s, i)
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

---@param value string
---@param limit integer
---@return string clamped
---@return boolean truncated
local function fallback_clamp(value, limit)
    if limit <= 0 or display_width(value) <= limit then
        return value, false
    end

    local budget = math.max(limit - display_width(ELLIPSIS), 0)

    -- Walk codepoints so a multibyte character is never split in half.
    local acc = 0
    local i = 1
    while i <= #value do
        local len = char_len(value, i)
        local char = value:sub(i, i + len - 1)
        local width = display_width(char)

        if acc + width > budget then
            break
        end

        acc = acc + width
        i = i + len
    end

    return value:sub(1, i - 1) .. ELLIPSIS, true
end

---@param value string
---@param limit integer
---@return string clamped
---@return boolean truncated
M.clamp = function(value, limit)
    local truncate = dapview_truncate()
    if truncate then
        return truncate.clamp(value, limit, ELLIPSIS)
    end

    return fallback_clamp(value, limit)
end

---Bounded LRU of untruncated values, keyed by the ref handed to the client.
local store = {
    ---@type table<string, string>
    values = {},
    ---@type string[] Oldest first
    order = {},
    next_id = 0,
}

local function touch(ref)
    for i, existing in ipairs(store.order) do
        if existing == ref then
            table.remove(store.order, i)
            break
        end
    end

    table.insert(store.order, ref)
end

---@param value string The RAW value, before any flattening or clamping
---@return string ref
local function remember(value)
    store.next_id = store.next_id + 1
    local ref = ("val:%d"):format(store.next_id)

    store.values[ref] = value
    touch(ref)

    while #store.order > LRU_CAPACITY do
        local evicted = table.remove(store.order, 1)
        store.values[evicted] = nil
    end

    return ref
end

---@param ref string
---@return string? value
M.full_value = function(ref)
    local value = store.values[ref]
    if value ~= nil then
        touch(ref)
    end

    return value
end

M.reset = function()
    store.values = {}
    store.order = {}
    store.next_id = 0
end

---@class dapmcp.FormattedValue
---@field value string Display copy: linebreaks collapsed, clamped
---@field truncated boolean?
---@field full_value_ref string? Pass to `get_value` for the untruncated text

---Turn a raw DAP value into what we put on the wire. The full value is stored
---raw -- before the linebreak flatten -- so `get_value` can return it verbatim.
---@param value string?
---@param limit integer? Defaults to `response.max_value_width`
---@return dapmcp.FormattedValue
M.format = function(value, limit)
    value = value or ""
    limit = limit or config.config.response.max_value_width

    -- Collapse linebreaks for the display copy only.
    local flat = value:gsub("[\r\n]+", " ")
    local clamped, truncated = M.clamp(flat, limit)

    if not truncated then
        return { value = clamped }
    end

    return { value = clamped, truncated = true, full_value_ref = remember(value) }
end

return M
