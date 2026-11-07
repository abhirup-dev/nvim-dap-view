local state = require("dap-view.state")

local M = {}
local request_sequence = 0

---@alias dapview.EvaluateContext "watch" | "repl" | "hover" | "clipboard" | "variables" | string

---@class dapview.EvaluateOpts
---@field context dapview.EvaluateContext

---@param expression string
---@param context dapview.EvaluateContext?
M.evaluate_expression = function(expression, context)
    request_sequence = request_sequence + 1
    local sequence = request_sequence
    local session = assert(require("dap").session(), "has active session")

    local frame_id = session.current_frame and session.current_frame.id
    local stamp = require("dap-view.decoders").context(session, expression)

    context = context or session.capabilities.supportsEvaluateForHovers and "hover" or "repl"

    local err, response =
        session:request("evaluate", { expression = expression, context = context, frameId = frame_id })

    if
        sequence ~= request_sequence
        or state.hover ~= expression
        or not require("dap-view.decoders").is_current(stamp)
    then
        return
    end
    local expanded = not state.hovered_expression or state.hovered_expression.expanded

    state.hovered_expression = { response = response, err = err, expanded = expanded }
end

return M
