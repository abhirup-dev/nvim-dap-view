local M = {}

---`foldtext` for the nvim-dap-view window: the folded node's name plus how many
---direct children it hides. Set through `tree.fold`, see `views/options.lua`.
---@return string
M.foldtext = function()
    local foldstart = vim.v.foldstart
    local foldend = vim.v.foldend

    -- With `foldmethod=indent` a fold starts at the first *child*, so the node that owns the
    -- fold is the line right above it. At the top of the buffer there is none, so fall back
    -- to treating the fold's own first line as the head
    local head_line = foldstart > 1 and foldstart - 1 or foldstart

    local head = vim.api.nvim_buf_get_lines(0, head_line - 1, head_line, false)[1] or ""

    local indent = head:match("^\t*") or ""
    local body = head:sub(#indent + 1)

    local icons = require("dap-view.setup").config.icons

    for _, icon in ipairs({ icons.expanded, icons.collapsed }) do
        if #icon > 0 and body:sub(1, #icon) == icon then
            body = body:sub(#icon + 1)
            break
        end
    end

    -- Everything up to the separator is the name
    local name = body:match("^(.-) = ") or body

    -- Only direct children, i.e. lines exactly one level deeper than the head
    local child_indent = #indent + 1
    local children = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, foldstart - 1, foldend, false)) do
        if #(line:match("^\t*") or "") == child_indent then
            children = children + 1
        end
    end

    local label = children == 1 and " child" or " children"

    return string.rep(" ", #indent * vim.bo.tabstop) .. name .. "  ‹" .. children .. label .. "›"
end

return M
