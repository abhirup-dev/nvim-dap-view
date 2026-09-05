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

        local session = util.session()
        if session and session.stopped_thread_id then
            local snapshot = status.compose()
            snapshot.event = "already_stopped"
            snapshot.timed_out = false

            return snapshot
        end

        local timeout = math.floor(tonumber(args.timeout_ms) or DEFAULT_TIMEOUT_MS)
        if timeout < 1 then
            util.fail("invalid_argument", "`timeout_ms` must be positive")
        end

        counter = counter + 1
        local key = ("dap-mcp.wait.%d"):format(counter)
        local co = coroutine.running()

        local settled = false
        local timer = nil

        ---First wins: the timeout and the event race each other.
        ---@param event string
        local function finish(event)
            if settled then
                return
            end
            settled = true

            dap.listeners.after.event_stopped[key] = nil
            dap.listeners.after.event_terminated[key] = nil
            dap.listeners.after.event_exited[key] = nil

            if timer then
                timer:stop()
                timer:close()
                timer = nil
            end

            -- Always defer: `finish` may be reached from a listener that
            -- nvim-dap invoked while this coroutine was still running.
            vim.schedule(function()
                coroutine.resume(co, event)
            end)
        end

        dap.listeners.after.event_stopped[key] = function()
            finish("stopped")
        end
        dap.listeners.after.event_terminated[key] = function()
            finish("terminated")
        end
        dap.listeners.after.event_exited[key] = function()
            finish("exited")
        end

        timer = vim.uv.new_timer()
        timer:start(timeout, 0, function()
            finish("timeout")
        end)

        local event = coroutine.yield()

        local snapshot = status.compose()
        snapshot.event = event
        snapshot.timed_out = event == "timeout"

        return snapshot
    end,
})
