local state = require("dap-view.state")

local M = {}

---@param expression string
---@param default_expanded boolean
---@param id? integer
M.evaluate_expression = function(expression, default_expanded, id)
    local session = assert(require("dap").session(), "has active session")

    local frame_id = session.current_frame and session.current_frame.id
    local stamp = require("dap-view.decoders").context(session, expression)

    local err, response =
        session:request("evaluate", { expression = expression, context = "watch", frameId = frame_id })

    if not require("dap-view.decoders").is_current(stamp) then
        return
    end
    if response then
        local variable = require("dap-view.decoders").prepare({
            name = expression,
            value = response.result,
            type = response.type,
            evaluateName = expression,
            variablesReference = response.variablesReference or 0,
            memoryReference = response.memoryReference,
        }, expression, session)
        response = vim.tbl_extend(
            "force",
            response,
            { result = variable.value, variablesReference = variable.variablesReference }
        )
    end

    local previous_expression_view = state.watched_expressions[expression]
        and vim.deepcopy(state.watched_expressions[expression])

    local previous_result = previous_expression_view
        and previous_expression_view.response
        and previous_expression_view.response.result

    if previous_expression_view and response then
        previous_expression_view.updated = previous_result ~= response.result
    end

    if previous_expression_view and err then
        previous_expression_view.children = nil
        previous_expression_view.updated = false
        previous_expression_view.expanded = false
    end

    ---@type dapview.ExpressionView
    local default_expression_view = {
        id = id or state.expr_count,
        response = response,
        err = err,
        updated = false,
        expanded = default_expanded,
        children = nil,
    }

    if previous_expression_view then
        previous_expression_view.response = response
        previous_expression_view.err = err
    end

    ---@type dapview.ExpressionView
    local new_expression_view = previous_expression_view or default_expression_view

    if new_expression_view.expanded then
        local variables_reference = response and response.variablesReference

        if variables_reference and variables_reference ~= 0 then
            new_expression_view.children =
                M.expand_variable(variables_reference, new_expression_view.children, expression)
        else
            new_expression_view.children = nil
        end
    end

    if require("dap-view.decoders").is_current(stamp) then
        state.watched_expressions[expression] = new_expression_view
    end
end

---@param expr string
M.copy_expr = function(expr)
    local session = assert(require("dap").session(), "has active session")

    if session.capabilities.supportsClipboardContext then
        coroutine.wrap(function()
            local frame_id = session.current_frame and session.current_frame.id

            local err, result =
                session:request("evaluate", { expression = expr, context = "clipboard", frameId = frame_id })

            if err == nil and result then
                -- TODO uses system clipboard, could be a parameter instead
                vim.fn.setreg("+", result.result)

                vim.notify("Variable " .. expr .. " copied to clipboard")
            end
        end)()
    else
        vim.notify("Adapter doesn't support clipboard evaluation")
    end
end

---@param variables_reference number
---@param previous_expansion_result dapview.VariableView[]?
M.expand_variable = function(variables_reference, previous_expansion_result, path)
    local session = assert(require("dap").session(), "has active session")

    local frame_id = session.current_frame and session.current_frame.id

    path = path or tostring(variables_reference)
    local err, response = require("dap-view.decoders").resolve_children(
        variables_reference,
        path,
        { session = session, variables_args = { context = "watch", frameId = frame_id } }
    )

    local response_variables = response and response.variables

    ---@type dapview.VariableView[]
    local varible_views = {}

    for k, variable in ipairs(response_variables or {}) do
        ---@type dapview.VariableView?
        local previous_variable_view = vim.iter(previous_expansion_result or {}):find(
            ---@param v dapview.VariableView
            function(v)
                if v.variable.name == variable.name then
                    return true
                end
                if v.variable.evaluateName then
                    return v.variable.evaluateName == variable.evaluateName
                end
                if v.variable.variablesReference ~= 0 then
                    return v.variable.variablesReference == variable.variablesReference
                end
            end
        )

        if previous_variable_view then
            if err then
                previous_variable_view.children = nil
                previous_variable_view.expanded = false
                previous_variable_view.updated = false
            else
                previous_variable_view.updated = previous_variable_view.variable.value ~= variable.value

                previous_variable_view.variable = variable
            end
        end

        ---@type dapview.VariableView
        local default_variable_view = {
            variable = variable,
            updated = false,
            expanded = false,
            children = nil,
            reference = variable.variablesReference,
            path = path .. "." .. variable.name,
        }

        ---@type dapview.VariableView
        local new_variable_view = previous_variable_view or default_variable_view

        new_variable_view.reference = variable.variablesReference
        local variables_reference_ = variable.variablesReference

        if new_variable_view.expanded then
            if variables_reference_ ~= 0 then
                new_variable_view.children, new_variable_view.err =
                    M.expand_variable(variables_reference_, new_variable_view.children, path .. "." .. variable.name)
            else
                -- We have to reset the children if the variable is no longer valid, otherwise it retains the old value indefinitely
                new_variable_view.children = nil
            end
        end

        varible_views[k] = new_variable_view
    end

    return #varible_views > 0 and varible_views or nil, err
end

return M
