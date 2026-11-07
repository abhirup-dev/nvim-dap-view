---`wait_for_pause`: the one tool whose whole point is to take a long time.
---
---It must never block Neovim's main loop, so it suspends its coroutine on
---one-shot nvim-dap listeners and a timer. The dispatcher has already handed
---the caller a ticket by then; the resume below is what fills it in.
local registry = require("dap-mcp.registry")
local status = require("dap-mcp.status")
local util = require("dap-mcp.util")

local DEFAULT_TIMEOUT_MS = 30000

local counter = 0

registry.register({
    name = "wait_for_pause",
    description = "Block until the debuggee stops, terminates or exits, then return the same fat "
        .. "snapshot as session_status plus the event that ended the wait. Returns immediately if "
        .. "the session is already stopped. Always call this after a control action instead of polling.",
    schema = registry.schema({
        timeout_ms = {
            type = "integer",
            description = "How long to wait before giving up. Default 30000.",
            minimum = 1,
        },
    }),
    handler = function(args)
        local dap = require("dap")

        local pause = require("dap-mcp.pause")
        pause.attach()
        local session = util.session()
        local timeout = math.floor(tonumber(args.timeout_ms) or DEFAULT_TIMEOUT_MS)
        if timeout < 1 then
            util.fail("invalid_argument", "`timeout_ms` must be positive")
        end

        counter = counter + 1
        local key = ("dap-mcp.wait.%d"):format(counter)
        local co = coroutine.running()
        local settled, composing = false, false
        local event = session and session.stopped_thread_id and "already_stopped" or "stopped"
        local timer, deadline

        local function finish(ending, snapshot)
            if settled then
                return
            end
            settled = true
            for _, name in ipairs({ "event_stopped", "event_terminated", "event_exited" }) do
                dap.listeners.after[name][key] = nil
            end
            if session and session.on_close then
                session.on_close[key] = nil
            end
            for _, handle in ipairs({ timer, deadline }) do
                handle:stop()
                handle:close()
            end
            snapshot = snapshot or { state = ending == "timeout" and "running" or "terminated", stack = {} }
            snapshot.event = ending
            snapshot.timed_out = ending == "timeout"
            vim.schedule(function()
                coroutine.resume(co, snapshot)
            end)
        end

        local function belongs(candidate)
            if not session and candidate == util.session() then
                session = candidate
            end
            return session ~= nil and candidate == session
        end

        local function check()
            if settled then
                return
            end
            local focused = util.session()
            if not session then
                session = focused
            elseif focused ~= session then
                finish("disconnected")
                return
            end
            if not session then
                return
            end
            if session.on_close then
                session.on_close[key] = function()
                    -- Normal termination closes before its after-event listeners.
                    vim.schedule(function()
                        finish("disconnected")
                    end)
                end
            end
            local thread_id = session.stopped_thread_id
            local thread = (session.threads or {})[thread_id]
            local frame = session.current_frame
            local token = pause.token(session)
            -- event_stopped yields while nvim-dap fetches threads/stackTrace.
            -- Only compose after its selected frame belongs to the loaded stack.
            local ready = false
            for _, candidate in ipairs(thread and thread.frames or {}) do
                if
                    frame
                    and candidate.id == frame.id
                    and (frame ~= token.previous_frame or thread.frames ~= token.previous_frames)
                then
                    ready = true
                    break
                end
            end
            if composing or not ready then
                return
            end
            composing = true
            coroutine.wrap(function()
                local ok, snapshot = pcall(status.compose)
                composing = false
                if
                    not settled
                    and ok
                    and util.session() == session
                    and pause.token(session) == token
                    and session.stopped_thread_id == thread_id
                    and session.current_frame == frame
                then
                    finish(event, snapshot)
                end
            end)()
        end

        dap.listeners.after.event_stopped[key] = function(candidate)
            if belongs(candidate) then
                event = "stopped"
                vim.schedule(check)
            end
        end
        for _, name in ipairs({ "terminated", "exited" }) do
            dap.listeners.after["event_" .. name][key] = function(candidate)
                if belongs(candidate) then
                    finish(name)
                end
            end
        end

        if session and session.on_close then
            session.on_close[key] = function()
                vim.schedule(function()
                    finish("disconnected")
                end)
            end
        end
        timer = vim.uv.new_timer()
        deadline = vim.uv.new_timer()
        timer:start(0, 10, vim.schedule_wrap(check))
        deadline:start(timeout, 0, function()
            -- Never issue adapter RPCs on the deadline path: they may never reply.
            local current = util.session()
            if session and current ~= session then
                finish("disconnected")
            elseif not current then
                finish("timeout", status.compose()) -- No session means no adapter RPCs.
            else
                finish("timeout", { state = current.stopped_thread_id and "stopped" or "running", stack = {} })
            end
        end)

        return coroutine.yield()
    end,
})
