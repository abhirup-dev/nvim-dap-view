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

---@class dapmcp.PauseRead
---@field session dap.Session
---@field token table
---@field thread_id integer?
---@field frame dap.StackFrame?

---Capture pause ownership before a read that may yield. Selection is recorded
---separately: a stack response survives selection changes within the same pause.
---@param session dap.Session
---@return dapmcp.PauseRead
M.capture = function(session)
    return {
        session = session,
        token = M.token(session),
        thread_id = session.stopped_thread_id,
        frame = session.current_frame,
    }
end

---@param read dapmcp.PauseRead
---@return boolean
M.is_current = function(read)
    return require("dap-mcp.util").session() == read.session
        and M.token(read.session) == read.token
        and read.session.stopped_thread_id == read.thread_id
end

---Status composition additionally belongs to the exact selected frame object.
---@param read dapmcp.PauseRead
---@return boolean
M.is_selected = function(read)
    return M.is_current(read) and read.session.current_frame == read.frame
end

---A stopped event yields while nvim-dap loads threads/stackTrace, retaining
---the previous pause's frame and stack. A retained advertised frame is also
---ready: Delve can allocate IDs outside nvim-dap's original thread cache.
---@param read dapmcp.PauseRead
---@return dap.StackFrame?
M.ready_frame = function(read)
    local frame = read.frame
    if not frame then
        return nil
    end
    if M.frame(read.session, read.thread_id, frame.id) == frame then
        return frame
    end
    local thread = (read.session.threads or {})[read.thread_id]
    for _, candidate in ipairs(thread and thread.frames or {}) do
        if
            candidate.id == frame.id
            and (frame ~= read.token.previous_frame or thread.frames ~= read.token.previous_frames)
        then
            return frame
        end
    end
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
