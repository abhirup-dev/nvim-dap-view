---nvim-dap-mcp: an agent-facing tool surface over nvim-dap.
---
---THE SIDECAR CONTRACT (read this one paragraph before writing phase 5b)
---
---There is exactly one entry point: `require("dap-mcp").call(tool_name, args)`.
---It always returns a JSON-encodable table, either
---
---    { ok = true,  result = <anything JSON-encodable> }
---    { ok = false, error = { code = "<stable string>", message = "<human text>" } }
---
---Most tools need a DAP round-trip, which is asynchronous, while
---`nvim_exec_lua` is synchronous. So `call` may instead return
---
---    { ok = true, result = { pending = true, ticket = <integer> } }
---
---meaning "accepted, not finished". Call
---`require("dap-mcp").poll(ticket)` until it returns something whose
---`result.pending` is not set; that is the real result, delivered once and then
---forgotten. A ~25 ms sleep between polls is plenty. Tickets expire after five
---minutes; polling an unknown, collected or expired one yields
---`error.code == "unknown_ticket"`. Purely local tools (`tools`,
---`list_configurations`, `list_breakpoints`, `control`, `ui_*`) answer on the
---first call and never hand out a ticket, so the sidecar needs one code path:
---"if result.pending then poll".
---
---Nothing here ever blocks Neovim's main loop. In particular `wait_for_pause`
---suspends its coroutine on nvim-dap listeners and resolves its ticket later.
---
---`require("dap-mcp").tools()` returns the registry -- name, description and
---JSON Schema per tool -- so the sidecar advertises the surface without
---duplicating any definition.
local M = {}

local config = require("dap-mcp.config")
local dispatch = require("dap-mcp.dispatch")
local registry = require("dap-mcp.registry")

local loaded = false

---Register every tool module. Idempotent.
local function load_tools()
    if loaded then
        return
    end
    loaded = true

    require("dap-mcp.tools.session")
    require("dap-mcp.tools.control")
    require("dap-mcp.tools.wait")
    require("dap-mcp.tools.breakpoints")
    require("dap-mcp.tools.stack")
    require("dap-mcp.tools.variables")
    require("dap-mcp.tools.ui")
end

---@param opts dapmcp.Config?
---@return dapmcp.Config
M.setup = function(opts)
    local resolved = config.setup(opts)

    load_tools()
    require("dap-mcp.status").attach()
    require("dap-mcp.sidecar").attach()

    return resolved
end

---Lifecycle for the Go sidecar: `start()`, `stop()`, `status()`. Also driven
---by `:DapMcp start|stop|status`.
M.sidecar = function()
    return require("dap-mcp.sidecar")
end

---Run a tool. See the contract at the top of this file.
---@param name string
---@param args table?
---@return dapmcp.Result
M.call = function(name, args)
    load_tools()

    return dispatch.call(name, args)
end

---Run a tool, delivering the result to a callback. For in-process callers; the
---sidecar cannot use this because `nvim_exec_lua` returns immediately.
---@param name string
---@param args table?
---@param on_done fun(result: dapmcp.Result)
M.call_async = function(name, args, on_done)
    load_tools()

    dispatch.call_async(name, args, on_done)
end

---Collect the result of a ticket handed out by `call`.
---@param ticket integer
---@return dapmcp.Result
M.poll = function(ticket)
    return dispatch.poll(ticket)
end

---The advertisable tool surface.
---@return { name: string, description: string, input_schema: table }[]
M.tools = function()
    load_tools()

    return registry.list()
end

return M
