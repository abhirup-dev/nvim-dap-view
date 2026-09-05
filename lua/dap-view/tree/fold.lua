local M = {}

---`foldtext` for the nvim-dap-view window: the folded node's name plus how many
---direct children it hides. Set through `tree.fold`, see `views/options.lua`.
---@return string
M.foldtext = function()
    local foldstart = vim.v.foldstart
    local foldend = vim.v.foldend

    local lines = vim.api.nvim_buf_get_lines(0, foldstart - 1, foldend, false)

    local head = lines[1] or ""

    local indent = head:match("^\t*") or ""
    local body = head:sub(#indent + 1)

    -- Everything up to the separator is the icon and the name
    local name = body:match("^(.-) = ") or body

    -- Only direct children, i.e. lines exactly one level deeper than the fold's first line
    local child_indent = #indent + 1
    local children = 0
    for i = 2, #lines do
        if #(lines[i]:match("^\t*") or "") == child_indent then
            children = children + 1
        end
    end

    local label = children == 1 and " child" or " children"

    return string.rep(" ", #indent * vim.bo.tabstop) .. name .. "  ‹" .. children .. label .. "›"
end

return M
