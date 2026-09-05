local dap = require("dap")

local views = require("dap-view.views")
local state = require("dap-view.state")
local setup = require("dap-view.setup")
local util = require("dap-view.util")
local hl = require("dap-view.util.hl")
local fmt = require("dap-view.util.fmt")
local truncate = require("dap-view.util.truncate")

local M = {}

---@type dap.Session
local session

---Breadcrumb re-root, see `dap-view.tree.reroot`. Only strict descendants of `root_path` are
---rendered; its ancestors are still traversed, so every line indexed state stays valid.
---@type string?
local root_path

---Depth `root_path` was found at, so the subtree can be re-indented from the top
---@type integer?
local root_depth

---Names from the scope down to `root_path`, collected during the traversal
---@type string[]
local breadcrumb

---@param path string
---@return boolean is_root
---@return boolean is_ancestor
---@return boolean is_descendant
local function classify(path)
    if root_path == nil then
        return false, false, true
    end

    return path == root_path,
        root_path:sub(1, #path + 1) == path .. ".",
        path:sub(1, #root_path + 1) == root_path .. "."
end

---Redrawing is jittery if we set lines on the fly
---Prevent that by batching all buffer updates
---Also need to handle concurrent calls, by creating multiple instances
---@class dapview.Canvas
---@field contents string[]
---@field highlights [string, [integer,integer], [integer,integer], integer?, vim.hl.range.Opts?][][]

---@param variables_reference integer
---@param parent_path string
---@param line integer
---@param depth integer
---@param canvas dapview.Canvas
local function show_variables(variables_reference, parent_path, line, depth, canvas)
    local parent_line = line
    local err, response = session:request("variables", { variablesReference = variables_reference })

    if err then
        local err_content = string.rep("\t", math.max(depth + 1 - (root_depth or 0), 0)) .. fmt.dap_error(err)

        canvas.contents[#canvas.contents + 1] = err_content

        canvas.highlights[#canvas.highlights + 1] = { { "WatchError", { line, 0 }, { line, #err_content } } }

        line = line + 1

        return line
    end

    local variables = response and response.variables or {}

    local config = setup.config
    local sort_variables = config.render.sort_variables
    if sort_variables then
        table.sort(variables, sort_variables)
    end

    for _, variable in pairs(variables) do
        local variable_name = variable.name

        local path = parent_path .. "." .. variable.name

        local is_root, is_ancestor, is_descendant = classify(path)

        if is_root then
            root_depth = depth
        end

        if is_root or is_ancestor then
            breadcrumb[#breadcrumb + 1] = variable.name
        end

        local is_expanded = state.variable_path_is_expanded[path]
        local is_structured = variable.variablesReference > 0

        local prev_variable_value = state.variable_path_to_value[path]

        -- Use actual return from scopes to check if variable was updated
        -- Allows checking if `setExpression` with js-debug updated the value
        local updated = prev_variable_value and prev_variable_value ~= variable.value

        -- Workaround for https://github.com/microsoft/vscode-js-debug/issues/2320
        local value = state.variable_path_to_set_variables[path] and prev_variable_value or variable.value

        state.variable_path_to_value[path] = value
        state.variable_path_to_name[path] = variable.name
        state.variable_path_to_evaluate_name[path] = variable.evaluateName
        state.variable_path_to_parent_reference[path] = variables_reference
        state.variable_path_to_reference[path] = variable.variablesReference
        state.variable_path_to_depth[path] = depth

        -- Always descend towards the re-root target, even through nodes the user collapsed
        local descend = is_structured and (is_expanded or is_root or is_ancestor)

        if not is_descendant then
            if descend then
                line = show_variables(variable.variablesReference, path, line, depth + 1, canvas)
            end

            goto continue
        end

        local prefix = ""

        if is_structured then
            prefix = is_expanded and config.icons.expanded or config.icons.collapsed
        end

        local separator = #value > 0 and " = " or ""

        local indent = depth - (root_depth or 0)

        local display_value, is_truncated = truncate.format_value(value, {
            name_col = truncate.name_col(indent, prefix .. variable_name .. separator),
            variable = variable,
            path = path,
        })

        local indented_content = string.rep("\t", indent) .. prefix .. variable_name .. separator .. display_value

        canvas.contents[#canvas.contents + 1] = indented_content

        state.variable_path_to_parent_line[path] = parent_line

        local type_hl_group = (updated and "WatchUpdated") or hl.hl_from_variable(variable)

        local hl_start = indent + #prefix

        ---@type [string, [integer,integer], [integer,integer], integer?, vim.hl.range.Opts?][]
        local line_highlights = { { "WatchExpr", { line, hl_start }, { line, hl_start + #variable.name } } }

        if type_hl_group then
            line_highlights[#line_highlights + 1] =
                { type_hl_group, { line, hl_start + #variable_name + 3 }, { line, -1 } }
        end

        if is_truncated then
            line_highlights[#line_highlights + 1] =
                { "Truncated", { line, hl.ellipsis_col(indented_content) }, { line, -1 }, nil, hl.ELLIPSIS_OPTS }
        end

        canvas.highlights[#canvas.highlights + 1] = line_highlights

        line = line + 1

        state.line_to_variable_path[line] = path

        if descend then
            line = show_variables(variable.variablesReference, path, line, depth + 1, canvas)
        end

        ::continue::
    end

    return line
end

M.show = function()
    if util.is_buf_valid(state.bufnr) and util.is_win_valid(state.winnr) then
        local tmp_session = dap.session()

        if views.cleanup_view(tmp_session == nil, "No active session") then
            return
        end

        ---@cast tmp_session dap.Session

        session = tmp_session

        local current_frame = session.current_frame

        if views.cleanup_view(current_frame == nil, "Session not stopped") then
            return
        end

        ---@cast current_frame dap.StackFrame

        local frame_scopes = current_frame.scopes

        local is_empty = frame_scopes == nil or vim.tbl_isempty(frame_scopes)

        if views.cleanup_view(is_empty, "No scopes for the current frame") then
            return
        end

        ---@cast frame_scopes dap.Scope[]

        ---@type dap.Scope[]
        local filtered_scopes = {}
        for _, scope in ipairs(frame_scopes) do
            if not scope.expensive then
                table.insert(filtered_scopes, scope)
            end
        end

        if views.cleanup_view(vim.tbl_isempty(filtered_scopes), "No eligible scopes returned from adapter") then
            return
        end

        local all_scopes_collapsed = vim.iter(filtered_scopes):all(
            ---@param s dap.Scope
            function(s)
                return vim.iter(state.collapsed_scopes):find(function(s_)
                    return s_ == s.name
                end)
            end
        )

        -- If all scopes are manually collapsed,
        -- we can reasonably assume it's likely at least one of them has variables
        local has_variables = all_scopes_collapsed

        local line = 0

        for k, _ in pairs(state.line_to_scope_name) do
            state.line_to_scope_name[k] = nil
        end
        for k, _ in pairs(state.line_to_variable_path) do
            state.line_to_variable_path[k] = nil
        end

        root_path = state.tree_root_stack[#state.tree_root_stack]
        root_depth = nil
        breadcrumb = {}

        ---@type dapview.Canvas
        local canvas = { contents = {}, highlights = {} }

        if root_path then
            -- Placeholder: the breadcrumb is only known once the traversal reached the root
            canvas.contents[1] = ""
            canvas.highlights[1] = { { "Thread", { 0, 0 }, { 0, -1 } } }

            line = 1
        end

        for _, scope in ipairs(filtered_scopes) do
            local prev_line = line

            if root_path then
                -- Only the scope holding the re-root target is worth descending
                if root_path == scope.name or root_path:sub(1, #scope.name + 1) == scope.name .. "." then
                    breadcrumb[#breadcrumb + 1] = scope.name

                    line = show_variables(scope.variablesReference, scope.name, line, 1, canvas)
                end
            else
                canvas.contents[#canvas.contents + 1] = scope.name

                canvas.highlights[#canvas.highlights + 1] = { { "Thread", { line, 0 }, { line, -1 } } }

                line = line + 1

                state.line_to_scope_name[line] = scope.name

                prev_line = line

                if not vim.tbl_contains(state.collapsed_scopes, scope.name) then
                    line = show_variables(scope.variablesReference, scope.name, line, 1, canvas)
                end
            end

            if prev_line ~= line then
                has_variables = true
            end
        end

        if root_path then
            if root_depth == nil then
                -- The node is gone: the frame changed, or an ancestor no longer has it. Pop back up
                table.remove(state.tree_root_stack)

                vim.notify("Re-root target is no longer in the tree, popping one level up")

                return M.show()
            end

            canvas.contents[1] = table.concat(breadcrumb, " ▸ ")

            -- A subtree with no children is still worth showing, if only for its breadcrumb
            has_variables = true
        end

        -- Sometimes the JS debug adapter simply does not return any variables at all, in spite of
        -- returning the scopes themselves. This happens, for instance, when debugging firebase functions.
        -- Upon refreshing the scopes for a function that is no longer in execution.
        --
        -- This could be a bug in nvim-dap where it does not refresh the scopes, or a bug with the
        -- adapter itself, where it doesn't send the updated scopes (if there are none)
        --
        -- Either way, that's not much of a big deal
        --
        -- More concerning though, is the fact that if the user does not force a refresh,
        -- The scopes may show "outdated info" until a trigger to refresh is hit
        -- But I guess that's more of a feature instead of a bug?
        if views.cleanup_view(not has_variables, "No variables returned from adapter") then
            return
        end

        util.set_lines(state.bufnr, 0, line - 1, false, canvas.contents)

        for _, highlights in ipairs(canvas.highlights) do
            for _, highlight in ipairs(highlights) do
                hl.hl_range(highlight[1], highlight[2], highlight[3], highlight[4], highlight[5])
            end
        end

        util.set_lines(state.bufnr, line, -1, true, {})
    end
end

return M
