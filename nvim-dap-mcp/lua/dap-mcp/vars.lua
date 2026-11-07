---Shared variable fetching, used by both the `variables` tools and the status
---composer, so paging and clamping behave identically wherever they appear.
local M = {}

local config = require("dap-mcp.config")
local truncate = require("dap-mcp.truncate")
local util = require("dap-mcp.util")

---@param variable dap.Variable
---@return table JSON-encodable variable
M.render = function(variable)
    local formatted = truncate.format(variable.value)

    return {
        name = variable.name,
        value = formatted.value,
        truncated = formatted.truncated,
        full_value_ref = formatted.full_value_ref,
        type = variable.type,
        variables_reference = variable.variablesReference or 0,
        has_children = (variable.variablesReference or 0) > 0,
        named_variables = variable.namedVariables,
        indexed_variables = variable.indexedVariables,
    }
end

---Fetch one page of children.
---
---We ask the adapter for everything and slice locally rather than sending
---`start`/`count`: DAP only honours those when `supportsVariablePaging` is set,
---and most adapters return the full list regardless.
---@param session dap.Session
---@param reference integer
---@param page integer? 1-based, defaults to 1
---@param page_size integer? Defaults to `response.max_children`
---@return table
M.page = function(session, reference, page, page_size)
    page = math.max(math.floor(page or 1), 1)
    page_size = math.max(math.floor(page_size or config.config.response.max_children), 1)

    local response = util.request(session, "variables", { variablesReference = reference })
    local all = response.variables or {}

    local first = (page - 1) * page_size + 1
    local last = math.min(first + page_size - 1, #all)

    local variables = {}
    for i = first, last do
        table.insert(variables, M.render(all[i]))
    end

    return {
        variables_reference = reference,
        page = page,
        page_size = page_size,
        total = #all,
        has_more = last < #all,
        variables = variables,
    }
end

return M
