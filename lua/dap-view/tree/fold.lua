local M = {}

-- Remember closed folds by tree identity, since inserting descendants moves lines.
-- Open only newly created automatic indent folds; never reset every fold with zR.
M.capture = function(win, paths)
    if not vim.api.nvim_win_is_valid(win) or vim.wo[win].foldmethod ~= "indent" then
        return {}
    end
    return vim.api.nvim_win_call(win, function()
        local closed = {}
        for line, path in pairs(paths) do
            if vim.fn.foldclosed(line) == line then
                closed[path] = true
            end
        end
        return closed
    end)
end

M.restore = function(win, paths, closed)
    if not vim.api.nvim_win_is_valid(win) or vim.wo[win].foldmethod ~= "indent" then
        return
    end
    vim.api.nvim_win_call(win, function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        for line = 1, vim.api.nvim_buf_line_count(0) do
            local first = vim.fn.foldclosed(line)
            local remaining = vim.fn.foldlevel(line) + 1
            while first > 0 and not closed[paths[first]] and remaining > 0 do
                remaining = remaining - 1
                vim.api.nvim_win_set_cursor(win, { first, 0 })
                vim.cmd("silent! normal! zo")
                first = vim.fn.foldclosed(line)
            end
        end
        for line, path in pairs(paths) do
            if closed[path] and vim.fn.foldclosed(line) == -1 and vim.fn.foldlevel(line) > 0 then
                vim.api.nvim_win_set_cursor(win, { line, 0 })
                vim.cmd("silent! normal! zc")
            end
        end
        vim.api.nvim_win_set_cursor(win, cursor)
    end)
end

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
