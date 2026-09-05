---Execution control. Every action here is asynchronous at the DAP level: the
---adapter acknowledges the request and stops later. Follow any control call
---with wait_for_pause.
local registry = require("dap-mcp.registry")
local util = require("dap-mcp.util")

local ACTIONS = {
    step_over = true,
    step_into = true,
    step_out = true,
    resume = true,
    pause = true,
    run_to_line = true,
}

---Resolve a thread to pause. `Session:_pause(nil, cb)` opens an interactive
---picker when several threads exist (lua/dap/session.lua:1678), which an agent
---cannot answer, so we always pass an explicit id.
---@param session dap.Session
---@return integer?
local function pause_target(session)
    if session.stopped_thread_id then
        return session.stopped_thread_id
    end

    local ok, response = pcall(util.request, session, "threads", nil)
    if not ok then
        return nil
    end

    local thread = (response.threads or {})[1]

    return thread and thread.id or nil
end

---Continue until `bufnr:lnum`, then restore the user's breakpoints.
---
---Replicates `dap.run_to_cursor` (lua/dap.lua:1084), which reads the current
---buffer and cursor and so cannot be pointed at an arbitrary file:line. The
---only changes are the explicit target and our own listener keys -- reusing
---nvim-dap's `dap.run_to_cursor` key would clobber the human's restore hook.
---@param session dap.Session
---@param bufnr integer
---@param lnum integer
local function run_to_line(session, bufnr, lnum)
    local dap = require("dap")
    local breakpoints = require("dap.breakpoints")

    local before = breakpoints.get()
    breakpoints.clear()
    breakpoints.set({}, bufnr, lnum)

    local temporary = breakpoints.get(bufnr)
    for other, _ in pairs(before) do
        if other ~= bufnr then
            temporary[other] = {}
        end
    end
    if before[bufnr] == nil then
        before[bufnr] = {}
    end

    local restored = false
    local function restore()
        if restored then
            return
        end
        restored = true

        dap.listeners.before.event_stopped["dap-mcp.run_to_line"] = nil
        dap.listeners.before.event_terminated["dap-mcp.run_to_line"] = nil

        breakpoints.clear()
        for buf, buf_bps in pairs(before) do
            for _, bp in pairs(buf_bps) do
                breakpoints.set({
                    condition = bp.condition,
                    log_message = bp.logMessage,
                    hit_condition = bp.hitCondition,
                }, buf, bp.line)
            end
        end
        session:set_breakpoints(before, nil)
    end

    dap.listeners.before.event_stopped["dap-mcp.run_to_line"] = restore
    dap.listeners.before.event_terminated["dap-mcp.run_to_line"] = restore

    session:set_breakpoints(temporary, function()
        -- `_step('continue')` rather than `dap.continue()`: the latter re-enters
        -- configuration selection when it thinks no session is focused.
        session:_step("continue")
    end)
end

registry.register({
    name = "control",
    description = "Drive execution: step_over, step_into, step_out, resume, pause, or "
        .. "run_to_line (which needs file and line). Returns as soon as the request is sent; "
        .. "call wait_for_pause to learn where the program stopped.",
    schema = registry.schema({
        action = {
            type = "string",
            enum = { "step_over", "step_into", "step_out", "resume", "pause", "run_to_line" },
            description = "What to do",
        },
        file = { type = "string", description = "Target file for run_to_line" },
        line = { type = "integer", description = "Target 1-based line for run_to_line" },
    }, { "action" }),
    handler = function(args)
        local dap = require("dap")
        local action = args.action

        if not ACTIONS[action] then
            util.fail("invalid_argument", "Unknown action %q", tostring(action))
        end

        if action == "pause" then
            local session = util.need_session()
            local thread_id = pause_target(session)
            if not thread_id then
                util.fail("no_thread", "No thread available to pause")
            end

            session:_pause(thread_id)

            return { action = action, thread_id = thread_id }
        end

        if action == "run_to_line" then
            local session = util.need_stopped_session()
            if type(args.line) ~= "number" then
                util.fail("invalid_argument", "run_to_line needs a `line`")
            end

            local bufnr = util.bufnr_for(args.file or util.path_of(0))
            run_to_line(session, bufnr, math.floor(args.line))

            return { action = action, file = util.path_of(bufnr), line = math.floor(args.line) }
        end

        if action == "resume" then
            util.need_stopped_session()
            dap.continue()

            return { action = action }
        end

        util.need_stopped_session()

        local step = ({
            step_over = dap.step_over,
            step_into = dap.step_into,
            step_out = dap.step_out,
        })[action]
        step()

        return { action = action }
    end,
})
