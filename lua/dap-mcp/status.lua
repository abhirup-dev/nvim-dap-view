---The status composer shared by `session_status` and `wait_for_pause`.
---
---Minimal for now: state, reason and thread id. Source context, the stack and
---the frame's locals land once the stack and variable tools exist.
local M = {}

local util = require("dap-mcp.util")

---Why the session last stopped, and whether it has since ended. nvim-dap drops
---a terminated session from `dap.sessions()`, so "terminated" and "never
---started" are otherwise indistinguishable.
local last = {
    ---@type string?
    reason = nil,
    ---@type string?
    description = nil,
    terminated = false,
}

local attached = false

---Install the listeners that keep `last` current. Idempotent.
M.attach = function()
    if attached then
        return
    end
    attached = true

    local dap = require("dap")

    dap.listeners.after.event_stopped["dap-mcp.status"] = function(_, body)
        last.reason = body and body.reason or nil
        last.description = body and body.description or nil
        last.terminated = false
    end

    local function ended()
        last.terminated = true
        last.reason = nil
        last.description = nil
    end

    dap.listeners.after.event_terminated["dap-mcp.status"] = ended
    dap.listeners.after.event_exited["dap-mcp.status"] = ended

    dap.listeners.after.event_initialized["dap-mcp.status"] = function()
        last.terminated = false
    end
end

---Test seam.
M.reset = function()
    last = { reason = nil, description = nil, terminated = false }
end

---@param frame dap.StackFrame
---@return table
local function render_frame(frame)
    return {
        id = frame.id,
        name = frame.name,
        file = frame.source and frame.source.path or nil,
        line = frame.line,
        column = frame.column,
    }
end

---Compose the status object. Must run inside a coroutine: it will issue DAP
---requests once it is enriched.
---@return table
M.compose = function()
    local session = util.session()

    if not session then
        return {
            state = last.terminated and "terminated" or "none",
            stack = {},
        }
    end

    local thread_id = session.stopped_thread_id
    if not thread_id then
        return {
            state = "running",
            stack = {},
        }
    end

    local frame = session.current_frame

    return {
        state = "stopped",
        reason = last.reason,
        description = last.description,
        thread_id = thread_id,
        frame = frame and render_frame(frame) or nil,
        stack = {},
    }
end

return M
