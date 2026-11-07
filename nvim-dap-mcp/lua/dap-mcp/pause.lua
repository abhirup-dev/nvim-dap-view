---Pause identity shared by asynchronous MCP operations. Session objects, not
---numeric session/frame IDs, are the ownership boundary.
local M = {}
local states = setmetatable({}, { __mode = "k" })

local function invalidate(session)
    states[session] = {}
end

local attach
M.token = function(session)
    attach()
    if not states[session] then
        states[session] = {}
    end
    if session.on_close then
        session.on_close["dap-mcp.pause"] = invalidate
    end
    return states[session]
end

local attached = false
attach = function()
    if attached then
        return
    end
    attached = true
    local dap = require("dap")
    for _, event in ipairs({
        "event_continued",
        "event_terminated",
        "event_exited",
        "continue",
        "next",
        "stepIn",
        "stepOut",
        "stepBack",
        "reverseContinue",
        "restart",
        "disconnect",
        "terminate",
    }) do
        dap.listeners.before[event]["dap-mcp.pause"] = invalidate
    end
    dap.listeners.before.event_stopped["dap-mcp.pause"] = function(session, body)
        local thread = (session.threads or {})[(body or {}).threadId or session.stopped_thread_id]
        states[session] = { previous_frame = session.current_frame, previous_frames = thread and thread.frames }
    end
    dap.listeners.before.event_invalidated["dap-mcp.pause"] = function(session, body)
        local areas = body and body.areas or { "all" }
        for _, area in ipairs(areas) do
            if area == "all" or area == "stacks" or area == "threads" then
                invalidate(session)
                return
            end
        end
    end
end

M.attach = function()
    attach()
end

M.remember = function(session, token, thread_id, frames)
    if M.token(session) ~= token or not session.stopped_thread_id then
        return false
    end
    token.frames = token.frames or {}
    token.frames[thread_id] = token.frames[thread_id] or {}
    for _, frame in ipairs(frames) do
        token.frames[thread_id][frame.id] = frame
    end
    return true
end

M.frame = function(session, thread_id, frame_id)
    local token = M.token(session)
    return token.frames and token.frames[thread_id] and token.frames[thread_id][frame_id]
end

return M
