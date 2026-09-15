---Variable inspection, mutation and expression evaluation.
local config = require("dap-mcp.config")
local registry = require("dap-mcp.registry")
local truncate = require("dap-mcp.truncate")
local util = require("dap-mcp.util")
local vars = require("dap-mcp.vars")

---Does this expression look like it would change program state?
---
---Deliberately a heuristic, and a blunt one: we have no parser for the
---debuggee's language, so we reject anything containing a call, an assignment
---or an increment. It over-rejects (`len(xs)` is harmless, `a[i] == b` is fine
---but `map["k="]` is not) and it under-rejects (a property getter with side
---effects reads as a plain name). It is a guard rail against an agent casually
---mutating a live process, not a security boundary. Set
---`evaluate.allow_side_effects = true` to turn it off.
---@param expression string
---@return string? reason
local function side_effect_reason(expression)
    if expression:find("%(") then
        return "it contains a call"
    end

    if expression:find("%+%+") or expression:find("%-%-") then
        return "it contains an increment or decrement"
    end

    for i = 1, #expression do
        if expression:sub(i, i) == "=" then
            local previous = expression:sub(i - 1, i - 1)
            local following = expression:sub(i + 1, i + 1)

            local comparison = previous == "="
                or following == "="
                or previous == "!"
                or previous == "<"
                or previous == ">"
            if not comparison then
                return "it looks like an assignment"
            end
        end
    end

    return nil
end

registry.register({
    name = "get_variables",
    description = "Children of a variables_reference, one page at a time. Values are clamped to "
        .. "the configured width; a clamped value carries truncated=true and a full_value_ref you "
        .. "can pass to get_value.",
    schema = registry.schema({
        variables_reference = { type = "integer", description = "Reference from a scope, variable or evaluate result" },
        page = { type = "integer", description = "1-based page number. Default 1.", minimum = 1 },
        page_size = {
            type = "integer",
            description = "Children per page. Defaults to response.max_children.",
            minimum = 1,
        },
    }, { "variables_reference" }),
    handler = function(args)
        local session = util.need_session()

        if type(args.variables_reference) ~= "number" or args.variables_reference <= 0 then
            util.fail("invalid_argument", "`variables_reference` must be a positive number")
        end

        return vars.page(session, math.floor(args.variables_reference), args.page, args.page_size)
    end,
})

registry.register({
    name = "get_value",
    description = "The untruncated text behind a full_value_ref returned by any clamped value. "
        .. "Refs are kept in a bounded cache and eventually expire.",
    schema = registry.schema({
        ref = { type = "string", description = "A full_value_ref from an earlier response" },
    }, { "ref" }),
    handler = function(args)
        if type(args.ref) ~= "string" then
            util.fail("invalid_argument", "`ref` must be a string")
        end

        local value = truncate.full_value(args.ref)
        if value == nil then
            util.fail("unknown_ref", "No cached value for ref %q; it expired or never existed", args.ref)
        end

        return { ref = args.ref, value = value }
    end,
})

registry.register({
    name = "set_variable",
    description = "Change a variable's value in the running program.",
    schema = registry.schema({
        variables_reference = { type = "integer", description = "Reference of the container holding the variable" },
        name = { type = "string", description = "Variable name within that container" },
        value = { type = "string", description = "New value, as the debuggee's language would write it" },
    }, { "variables_reference", "name", "value" }),
    handler = function(args)
        local session = util.need_session()

        if type(args.variables_reference) ~= "number" then
            util.fail("invalid_argument", "`variables_reference` must be a number")
        end
        if type(args.name) ~= "string" or type(args.value) ~= "string" then
            util.fail("invalid_argument", "`name` and `value` must be strings")
        end

        local response = util.request(session, "setVariable", {
            variablesReference = math.floor(args.variables_reference),
            name = args.name,
            value = args.value,
        })

        local formatted = truncate.format(response.value)

        return {
            name = args.name,
            value = formatted.value,
            truncated = formatted.truncated,
            full_value_ref = formatted.full_value_ref,
            type = response.type,
            variables_reference = response.variablesReference or 0,
        }
    end,
})

registry.register({
    name = "evaluate",
    description = "Evaluate an expression in the debuggee. Defaults to the selected frame. "
        .. "Expressions that look like assignments or calls are refused unless "
        .. "evaluate.allow_side_effects is configured true; the check is a best-effort heuristic, "
        .. "not a parser.",
    schema = registry.schema({
        expression = { type = "string", description = "Expression in the debuggee's language" },
        frame_id = { type = "integer", description = "Frame to evaluate in; defaults to the selected frame" },
        context = {
            type = "string",
            enum = { "watch", "repl", "hover", "clipboard", "variables" },
            description = "DAP evaluate context. Default 'repl'.",
        },
    }, { "expression" }),
    handler = function(args)
        local session = util.need_session()

        if type(args.expression) ~= "string" or args.expression == "" then
            util.fail("invalid_argument", "`expression` must be a non-empty string")
        end

        if not config.config.evaluate.allow_side_effects then
            local reason = side_effect_reason(args.expression)
            if reason then
                util.fail(
                    "side_effects_refused",
                    "Refusing to evaluate %q because %s. Set evaluate.allow_side_effects = true to permit it.",
                    args.expression,
                    reason
                )
            end
        end

        local co = coroutine.running()
        local resumed = false

        session:evaluate({
            expression = args.expression,
            frameId = args.frame_id and math.floor(args.frame_id) or nil,
            context = args.context or "repl",
        }, function(err, response)
            if resumed then
                return
            end
            resumed = true
            vim.schedule(function()
                coroutine.resume(co, err, response)
            end)
        end)

        local err, response = coroutine.yield()
        if err then
            util.fail("dap_error", "evaluate failed: %s", err.message or vim.inspect(err))
        end

        response = response or {}
        local formatted = truncate.format(response.result)

        return {
            expression = args.expression,
            value = formatted.value,
            truncated = formatted.truncated,
            full_value_ref = formatted.full_value_ref,
            type = response.type,
            variables_reference = response.variablesReference or 0,
            has_children = (response.variablesReference or 0) > 0,
        }
    end,
})
