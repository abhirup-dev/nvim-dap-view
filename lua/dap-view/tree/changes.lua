local M = {}
local sessions = setmetatable({}, { __mode = "k" })

local function frame_key(session, frame_id)
    local frame = session.current_frame
    local path = frame and frame.source and frame.source.path
    local thread = session.threads and session.threads[session.stopped_thread_id]
    if path and frame.name and thread then
        for index, candidate in ipairs(thread.frames or {}) do
            if candidate.id == frame_id then
                return table.concat({ path, frame.name, tostring(index) }, "\0")
            end
        end
    end
    return frame_id
end

---Compare against the previous refresh generation, not the previous paint.
---Decoder completions may repaint a stop several times; those paints must not
---consume a change marker or compare a loading summary with the raw value.
---@param surface string
---@param path string
---@param variable dap.Variable|dap.EvaluateResponse
---@param stamp table
---@return boolean
function M.observe(surface, path, variable, stamp)
    local decoders = require("dap-view.decoders")
    if not require("dap-view.context").is_current(stamp) then
        return false
    end
    local session = stamp.session
    sessions[session] = sessions[session] or {}
    local record = sessions[session][surface]
    local key = frame_key(session, stamp.frame_id)
    if not record or record.frame_key ~= key or record.thread_id ~= session.stopped_thread_id then
        record = { frame_key = key, thread_id = session.stopped_thread_id, latest = {} }
        sessions[session][surface] = record
    end
    if record.epoch ~= stamp.epoch then
        record.baseline, record.latest = record.latest, {}
        record.epoch = stamp.epoch
    end
    local value = decoders.original_value(variable.variablesReference, variable.value or variable.result)
    record.latest[path] = value
    return record.baseline[path] ~= nil and record.baseline[path] ~= value
end

return M
