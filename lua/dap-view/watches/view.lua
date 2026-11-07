local state = require("dap-view.state")
local views = require("dap-view.views")
local setup = require("dap-view.setup")
local util = require("dap-view.util")
local hl = require("dap-view.util.hl")
local fmt = require("dap-view.util.fmt")
local truncate = require("dap-view.util.truncate")

local M = {}

---@param children dapview.VariableView[]
---@param reference number
---@param line integer
---@param depth integer
---@return integer
local function show_variables(children, reference, line, depth, parent_highlight)
    local parent_line = line

    for _, child in ipairs(children) do
        local variable = child.variable
        local variable_highlight = hl.variable_highlight(variable, {
            session = require("dap").session(),
            path = child.path or variable.name,
            parent_highlight = parent_highlight,
        })

        local prefix = ""

        local icons = setup.config.icons
        if variable.variablesReference ~= 0 then
            prefix = child.expanded and icons.expanded or icons.collapsed
        end

        local value = require("dap-view.decoders").format_value(
            variable,
            child.path or variable.name,
            { session = require("dap").session() }
        )

        local separator = #value > 0 and " = " or ""

        local display_value, is_truncated = truncate.format_value(value, {
            name_col = truncate.name_col(depth, prefix .. variable.name .. separator),
            variable = variable,
        })

        local indented_content = string.rep("\t", depth) .. prefix .. variable.name .. separator .. display_value

        util.set_lines(state.bufnr, line, line, true, { indented_content })

        local hl_start = depth + #prefix
        hl.hl_range(
            variable_highlight or "WatchExpr",
            { line, variable_highlight and depth or hl_start },
            { line, hl_start + #variable.name }
        )

        local hl_group = (child.updated and "WatchUpdated") or variable_highlight or hl.hl_from_variable(variable)

        if hl_group and #value > 0 then
            hl.hl_range(hl_group, { line, hl_start + #variable.name + 3 }, { line, -1 })
        end

        if is_truncated then
            hl.hl_range("Truncated", { line, hl.ellipsis_col(indented_content) }, { line, -1 }, nil, hl.ELLIPSIS_OPTS)
        end

        line = line + 1

        state.variable_views_by_line[line] =
            { parent_reference = reference, parent_line = parent_line, variable = variable, view = child }

        if child.err then
            local err_content = string.rep("\t", depth + 1) .. fmt.dap_error(child.err)

            util.set_lines(state.bufnr, line, line, true, { err_content })

            hl.hl_range("WatchError", { line, 0 }, { line, #err_content })

            line = line + 1
        end

        if child.expanded and child.children ~= nil then
            line = show_variables(child.children, child.reference, line, depth + 1, variable_highlight)
        end
    end
    return line
end

local function fold_paths()
    local paths = {}
    for line, entry in pairs(state.variable_views_by_line) do
        paths[line] = entry.view.path
    end
    for line, entry in pairs(state.expression_views_by_line) do
        paths[line] = entry.expression
    end
    return paths
end

M.show = function()
    local folds = require("dap-view.tree.fold")
    local closed = state.winnr and folds.capture(state.winnr, fold_paths()) or {}
    -- New expressions may prepended
    -- And lines may be no longer valid if a variable changes (e.g., array's size changes)
    -- Hence, lines may change unexpectedly
    -- To handle that, always clear the storage table
    for k, _ in pairs(state.expression_views_by_line) do
        state.expression_views_by_line[k] = nil
    end
    -- Also clear variables for the same reason
    for k, _ in pairs(state.variable_views_by_line) do
        state.variable_views_by_line[k] = nil
    end

    -- We have to check if the win is valid, since this function may be triggered by an event when the window is closed
    if util.is_buf_valid(state.bufnr) and util.is_win_valid(state.winnr) then
        -- Ensure buf is valid before calling `cleanup_view`
        if views.cleanup_view(vim.tbl_isempty(state.watched_expressions), "No expressions") then
            return
        end

        local line = 0

        -- Sort expressions to keep a "stable" experience
        ---@type [string, dapview.ExpressionView][]
        local expressions = vim.iter(state.watched_expressions)
            :map(function(k, v)
                return { k, v }
            end)
            :totable()

        table.sort(
            expressions,
            ---@param lhs [string, dapview.ExpressionView]
            ---@param rhs [string, dapview.ExpressionView]
            function(lhs, rhs)
                return lhs[2].id < rhs[2].id
            end
        )

        for _, expression_view in ipairs(expressions) do
            local expression, view = unpack(expression_view)
            local response = view.response
            local err = view.err

            local result = response and response.result or err and fmt.dap_error(err)
            local variable_highlight = response
                and hl.variable_highlight(response, {
                    session = require("dap").session(),
                    path = expression,
                })

            local prefix = ""

            local icons = setup.config.icons
            if response and response.variablesReference ~= 0 then
                prefix = view.expanded and icons.expanded or icons.collapsed
            end

            local display_result, is_truncated = truncate.format_value(result, {
                name_col = truncate.name_col(0, prefix .. expression .. " = "),
                variable = response,
            })

            local content = prefix .. expression .. " = " .. display_result

            util.set_lines(state.bufnr, line, line, true, { content })

            hl.hl_range(
                variable_highlight or "WatchExpr",
                { line, variable_highlight and 0 or #prefix },
                { line, #prefix + #expression }
            )

            local hl_group = err and "WatchError"
                or view.updated and "WatchUpdated"
                or variable_highlight
                or response and hl.hl_from_variable(response)

            if hl_group and result and #result > 0 then
                local hl_start = #prefix + #expression + 3
                hl.hl_range(hl_group, { line, hl_start }, { line, -1 })
            end

            if is_truncated then
                hl.hl_range("Truncated", { line, hl.ellipsis_col(content) }, { line, -1 }, nil, hl.ELLIPSIS_OPTS)
            end

            line = line + 1

            state.expression_views_by_line[line] = { expression = expression, view = view }

            if err == nil and view.children ~= nil and view.expanded and response ~= nil then
                line = show_variables(view.children, response.variablesReference, line, 1, variable_highlight)
            end
        end

        util.set_lines(state.bufnr, line, -1, true, {})
        folds.restore(state.winnr, fold_paths(), closed)
    end
end

return M
