---The single source of truth for the tool surface. `dap-mcp.tools()` returns
---this verbatim so the sidecar can advertise tools without redefining them.
local M = {}

---@class dapmcp.Tool
---@field name string
---@field description string
---@field schema table JSON Schema for the tool's input object
---@field handler fun(args: table): any Runs inside a coroutine; may yield on DAP requests

---@type table<string, dapmcp.Tool>
local tools = {}

---@type string[] Registration order, so `tools()` is stable
local order = {}

---Build a JSON Schema object. `properties` is emitted as a JSON object even
---when empty, which `{}` alone would not be.
---@param properties table<string, table>?
---@param required string[]?
---@return table
M.schema = function(properties, required)
    return {
        type = "object",
        properties = require("dap-mcp.util").object(properties),
        required = required or {},
        additionalProperties = false,
    }
end

---@param tool dapmcp.Tool
M.register = function(tool)
    assert(type(tool.name) == "string", "tool.name must be a string")
    assert(type(tool.description) == "string", "tool.description must be a string")
    assert(type(tool.handler) == "function", "tool.handler must be a function")

    if tools[tool.name] == nil then
        table.insert(order, tool.name)
    end

    tools[tool.name] = tool
end

---@param name string
---@return dapmcp.Tool?
M.get = function(name)
    return tools[name]
end

---The advertisable surface: name, description and input schema, no handlers.
---@return { name: string, description: string, input_schema: table }[]
M.list = function()
    local list = {}

    for _, name in ipairs(order) do
        local tool = tools[name]
        table.insert(list, {
            name = tool.name,
            description = tool.description,
            input_schema = tool.schema or M.schema(),
        })
    end

    return list
end

---Test seam; the tool modules re-register themselves on require.
M.reset = function()
    tools = {}
    order = {}
end

return M
