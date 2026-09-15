---The coroutine driver and the ticket table.
---
---Every handler runs inside a coroutine, because every interesting tool needs a
---DAP round-trip and `Session:request` (nvim-dap `lua/dap/session.lua:1887`)
---yields when called without a callback. A handler therefore reads as
---straight-line code and simply returns its result.
---
---Note the completion is delivered through `resolve`, never through the
---coroutine's return value: once a handler has yielded, the final
---`coroutine.resume` happens inside nvim-dap's own `coresume`, which discards
---whatever the coroutine returns.
local M = {}

local registry = require("dap-mcp.registry")
local util = require("dap-mcp.util")

---Pending results live this long before being garbage collected, so a ticket
---nobody polls does not leak.
local TICKET_TTL_MS = 5 * 60 * 1000

---@class dapmcp.Ticket
---@field created integer
---@field done boolean
---@field result dapmcp.Result?

---@type table<integer, dapmcp.Ticket>
local tickets = {}
local next_ticket = 0

---@class dapmcp.Result
---@field ok boolean
---@field result any? Present when `ok`
---@field error dapmcp.Error? Present when not `ok`

---@param code string
---@param message string
---@return dapmcp.Result
local function failure(code, message)
    return { ok = false, error = { code = code, message = message } }
end

local function gc()
    local now = vim.uv.now()

    for id, ticket in pairs(tickets) do
        if now - ticket.created > TICKET_TTL_MS then
            tickets[id] = nil
        end
    end
end

---Run a tool and deliver its result to `on_done`, possibly on a later tick.
---@param name string
---@param args table?
---@param on_done fun(result: dapmcp.Result)
M.call_async = function(name, args, on_done)
    local tool = registry.get(name)
    if not tool then
        on_done(failure("unknown_tool", ("No such tool: %s"):format(tostring(name))))
        return
    end

    -- First writer wins: a handler that resolves and then errors, or a timeout
    -- racing an event, must not deliver twice.
    local settled = false
    local function resolve(ok, value)
        if settled then
            return
        end
        settled = true

        if ok then
            on_done({ ok = true, result = value })
        else
            on_done({ ok = false, error = util.as_error(value) })
        end
    end

    local co = coroutine.create(function()
        local ok, value = pcall(tool.handler, args or {})
        resolve(ok, value)
    end)

    local resumed, err = coroutine.resume(co)
    if not resumed then
        resolve(false, err)
    end
end

---Synchronous entry point for the sidecar.
---
---Returns the real result when the handler finished without yielding; otherwise
---returns `{ ok = true, result = { pending = true, ticket = N } }` and the
---caller polls. See `M.poll`.
---@param name string
---@param args table?
---@return dapmcp.Result
M.call = function(name, args)
    gc()

    next_ticket = next_ticket + 1
    local id = next_ticket

    local immediate = nil
    local returned = false

    M.call_async(name, args, function(result)
        if returned then
            tickets[id] = { created = vim.uv.now(), done = true, result = result }
        else
            immediate = result
        end
    end)
    returned = true

    if immediate then
        return immediate
    end

    tickets[id] = { created = vim.uv.now(), done = false }

    return { ok = true, result = { pending = true, ticket = id } }
end

---Collect a pending result. Still-pending tickets echo the pending envelope;
---a ready ticket is returned once and then dropped.
---@param ticket integer
---@return dapmcp.Result
M.poll = function(ticket)
    gc()

    local entry = tickets[ticket]
    if not entry then
        return failure(
            "unknown_ticket",
            ("No such ticket (unknown, already collected or expired): %s"):format(tostring(ticket))
        )
    end

    if not entry.done then
        return { ok = true, result = { pending = true, ticket = ticket } }
    end

    tickets[ticket] = nil

    return entry.result
end

M.reset = function()
    tickets = {}
    next_ticket = 0
end

return M
