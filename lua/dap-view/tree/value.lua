local state = require("dap-view.state")
local setup = require("dap-view.setup")
local util = require("dap-view.util")
local truncate = require("dap-view.util.truncate")

local M = {}

local api = vim.api

local keymap = require("dap-view.views.keymaps.util").keymap

---Full, untruncated value shown on `line` of the main buffer.
---Sections share the buffer but only clear their own line indexed tables, so this has to
---dispatch on the current section instead of probing all of them.
---@param line integer 1 indexed
---@return string? value
---@return string? name
M.value_at = function(line)
    local section = state.current_section

    if section == "scopes" then
        local path = state.line_to_variable_path[line]

        if path then
            return state.variable_path_to_value[path], state.variable_path_to_name[path]
        end
    elseif section == "watches" then
        local variable_view = state.variable_views_by_line[line]

        if variable_view then
            return variable_view.variable.value, variable_view.variable.name
        end

        local expression_view = state.expression_views_by_line[line]

        if expression_view then
            local view = expression_view.view

            local value = (view.response and view.response.result)
                or (view.err and require("dap-view.util.fmt").dap_error(view.err))

            return value, expression_view.expression
        end
    end
end

---@param lines string[]
---@return integer height
---@return integer width
local dimensions = function(lines)
    local max_width = math.floor(vim.go.columns * 0.8)
    local max_height = math.floor(vim.go.lines * 0.5)

    local width = 1
    for _, l in ipairs(lines) do
        width = math.max(width, truncate.display_width(l))
    end
    width = math.min(width, max_width)

    -- The float wraps, so a long line takes more than one row
    local height = 0
    for _, l in ipairs(lines) do
        height = height + math.max(math.ceil(truncate.display_width(l) / width), 1)
    end

    return math.max(math.min(height, max_height), 1), width
end

---Show the full value of the node under the cursor in a float, untruncated and
---split back on the linebreaks the tree line had to collapse
---@param line integer 1 indexed
M.show = function(line)
    if util.is_win_valid(state.hover_winnr) then
        api.nvim_set_current_win(state.hover_winnr)
        return
    end

    local value, name = M.value_at(line)

    if value == nil then
        vim.notify("No value under the cursor")
        return
    end

    local lines = truncate.split(value)

    local bufnr = api.nvim_create_buf(false, true)

    state.hover_bufnr = bufnr

    -- NUL bytes are not valid buffer text
    local sanitized = vim.tbl_map(function(l)
        return (l:gsub("%z", "^@"))
    end, lines)

    util.set_lines(bufnr, 0, -1, false, sanitized)

    local height, width = dimensions(sanitized)

    local anchor_y, anchor_x = require("dap-view.util.float").get_anchor(width)

    local winnr = api.nvim_open_win(bufnr, true, {
        border = setup.config.hover.border,
        relative = "cursor",
        row = anchor_y == "N" and 1 or 0,
        col = anchor_x == "E" and 1 or 0,
        anchor = anchor_y .. anchor_x,
        width = width,
        height = height,
        title = name,
    })

    state.hover_winnr = winnr

    require("dap-view.hover").set_win_options(winnr)
    require("dap-view.hover").set_buf_options(bufnr)
    require("dap-view.hover").set_autocmds(bufnr)

    vim.wo[winnr][0].wrap = true

    keymap(setup.config.keymaps.hover.quit, "<C-w>q", { buffer = bufnr, desc = "close" })
end

return M
