---The status composer shared by `session_status` and `wait_for_pause`.
local M = {}

local config = require("dap-mcp.config")
local util = require("dap-mcp.util")
local vars = require("dap-mcp.vars")

local MAX_STACK_FRAMES = 10

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

---@return string? path, integer? line
local function frame_location(frame)
    if not frame then
        return nil, nil
    end

    return frame.source and frame.source.path or nil, frame.line
end

---`response.source_context` lines either side of `line`, from the buffer when
---it is loaded (so unsaved edits are what the agent sees, matching the human's
---view) and from disk otherwise.
---@param path string?
---@param line integer?
---@return table? { lines: string[], start_line: integer }
local function read_source(path, line)
    if not path or not line then
        return nil
    end

    local context = config.config.response.source_context
    local start_line = math.max(line - context, 1)
    local end_line = line + context

    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
        return { lines = lines, start_line = start_line }
    end

    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end

    local ok, all = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end

    local lines = {}
    for i = start_line, math.min(end_line, #all) do
        table.insert(lines, all[i])
    end

    return { lines = lines, start_line = start_line }
end

---@param frame dap.StackFrame
---@return table
local function render_frame(frame)
    local path, line = frame_location(frame)

    return {
        id = frame.id,
        name = frame.name,
        file = path,
        line = line,
        column = frame.column,
    }
end

---@param session dap.Session
---@param thread_id integer
---@return table[]
local function top_frames(session, thread_id)
    local ok, response = pcall(util.request, session, "stackTrace", {
        threadId = thread_id,
        startFrame = 0,
        levels = MAX_STACK_FRAMES,
    })

    if not ok then
        return {}
    end

    local frames = {}
    for i, frame in ipairs(response.stackFrames or {}) do
        if i > MAX_STACK_FRAMES then
            break
        end
        table.insert(frames, render_frame(frame))
    end

    return frames
end

---First scope of the current frame, clamped and paged like any other variable
---listing. Returns nil rather than erroring: a status response is best-effort.
---@param session dap.Session
---@param frame dap.StackFrame?
---@return table?
local function first_scope_locals(session, frame)
    if not frame or not frame.id then
        return nil
    end

    local ok, response = pcall(util.request, session, "scopes", { frameId = frame.id })
    if not ok then
        return nil
    end

    local scope = (response.scopes or {})[1]
    if not scope or not scope.variablesReference or scope.variablesReference == 0 then
        return nil
    end

    local paged
    ok, paged = pcall(vars.page, session, scope.variablesReference)
    if not ok then
        return nil
    end

    paged.scope = scope.name

    return paged
end

---Compose the fat status object. Must run inside a coroutine: it issues DAP
---requests when the session is stopped.
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
        source = read_source(frame_location(frame)),
        stack = top_frames(session, thread_id),
        locals = first_scope_locals(session, frame),
    }
end

return M
