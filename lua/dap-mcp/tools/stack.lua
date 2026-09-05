---Stack and thread tools.
local registry = require("dap-mcp.registry")
local util = require("dap-mcp.util")

---@param frame dap.StackFrame
---@return table
local function render(frame)
    return {
        id = frame.id,
        name = frame.name,
        file = frame.source and frame.source.path or nil,
        line = frame.line,
        column = frame.column,
        presentation_hint = frame.presentationHint,
    }
end

registry.register({
    name = "get_stack",
    description = "The call stack of a stopped thread. Defaults to the thread that is currently "
        .. "stopped. Frame ids feed select_frame and evaluate.",
    schema = registry.schema({
        thread_id = { type = "integer", description = "Thread to inspect; defaults to the stopped one" },
        levels = { type = "integer", description = "Maximum frames to return. 0 or omitted means all." },
    }),
    handler = function(args)
        local session = util.need_stopped_session()
        local thread_id = args.thread_id or session.stopped_thread_id

        local response = util.request(session, "stackTrace", {
            threadId = thread_id,
            startFrame = 0,
            levels = args.levels and math.floor(args.levels) or nil,
        })

        local frames = {}
        for _, frame in ipairs(response.stackFrames or {}) do
            table.insert(frames, render(frame))
        end

        return {
            thread_id = thread_id,
            total_frames = response.totalFrames or #frames,
            frames = frames,
        }
    end,
})

registry.register({
    name = "select_frame",
    description = "Focus a stack frame by id, so later evaluate and variable calls default to it. "
        .. "The human's Neovim jumps to that frame too.",
    schema = registry.schema({
        frame_id = { type = "integer", description = "Frame id from get_stack" },
    }, { "frame_id" }),
    handler = function(args)
        local session = util.need_stopped_session()
        if type(args.frame_id) ~= "number" then
            util.fail("invalid_argument", "`frame_id` must be a number")
        end
        local frame_id = math.floor(args.frame_id)

        ---@type dap.StackFrame?
        local target = nil

        local thread = session.threads[session.stopped_thread_id]
        for _, frame in ipairs((thread or {}).frames or {}) do
            if frame.id == frame_id then
                target = frame
                break
            end
        end

        if not target then
            local response = util.request(session, "stackTrace", {
                threadId = session.stopped_thread_id,
                startFrame = 0,
            })
            for _, frame in ipairs(response.stackFrames or {}) do
                if frame.id == frame_id then
                    target = frame
                    break
                end
            end
        end

        if not target then
            util.fail("unknown_frame", "No frame with id %d on the stopped thread", frame_id)
        end

        -- `dap.focus_frame` only re-focuses the frame that is already current;
        -- `_frame_set` is what it calls underneath (lua/dap.lua:694) and is the
        -- only way to select a different frame.
        session:_frame_set(target)

        return { frame = render(target) }
    end,
})

registry.register({
    name = "list_threads",
    description = "All threads known to the adapter, flagging which one is stopped.",
    schema = registry.schema(),
    handler = function()
        local session = util.need_session()
        local response = util.request(session, "threads", nil)

        local threads = {}
        for _, thread in ipairs(response.threads or {}) do
            table.insert(threads, {
                id = thread.id,
                name = thread.name,
                stopped = thread.id == session.stopped_thread_id,
            })
        end

        return { threads = threads, stopped_thread_id = session.stopped_thread_id }
    end,
})
