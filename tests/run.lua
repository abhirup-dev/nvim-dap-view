-- Headless test suite: nvim --headless -u NONE -l tests/run.lua
--
-- No real adapter is started. `dap-mcp.util.session` is stubbed with a fake
-- session that answers stackTrace/scopes/variables/evaluate/threads/setVariable
-- from fixtures.

local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(repo)
vim.opt.runtimepath:prepend(vim.fn.expand("~/.local/share/nvim/lazy/nvim-dap"))

local passed, failed = 0, 0
local failures = {}

local function ok(condition, name, detail)
    if condition then
        passed = passed + 1
        print(("  ok   %s"):format(name))
    else
        failed = failed + 1
        local line = ("  FAIL %s%s"):format(name, detail and (" -- " .. tostring(detail)) or "")
        print(line)
        table.insert(failures, line)
    end
end

local function eq(actual, expected, name)
    ok(
        vim.deep_equal(actual, expected),
        name,
        ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual))
    )
end

local function group(name)
    print("\n" .. name)
end

--------------------------------------------------------------------------------
-- Fake session
--------------------------------------------------------------------------------

local LONG_VALUE = ("x"):rep(500) .. "\nsecond line\nthird line"

local fixtures = {
    threads = {
        threads = {
            { id = 1, name = "main" },
            { id = 2, name = "worker" },
        },
    },
    stackTrace = {
        totalFrames = 2,
        stackFrames = {
            { id = 11, name = "compute", line = 12, column = 3, source = { path = nil } },
            { id = 12, name = "main", line = 40, column = 1, source = { path = nil } },
        },
    },
    scopes = {
        scopes = {
            { name = "Locals", variablesReference = 100 },
            { name = "Globals", variablesReference = 200 },
        },
    },
}

-- Twelve children so paging has something to page.
local children = {}
for i = 1, 12 do
    table.insert(children, {
        name = ("var%02d"):format(i),
        value = ("value-%d"):format(i),
        type = "int",
        variablesReference = 0,
    })
end
children[1].value = LONG_VALUE

---A fake `dap.Session`.
---
---`request` defers its callback through `vim.schedule`, exactly as a real
---adapter would: the callback nvim-dap installs is `coresume(co)`, and resuming
---a coroutine that is still running raises. Do NOT "simplify" this to a
---synchronous callback -- it would both mask that bug class and diverge from
---production, where every response arrives on a later tick.
local function new_fake_session()
    local session
    session = {
        id = 1,
        stopped_thread_id = 1,
        capabilities = { supportsSetVariable = true },
        threads = { [1] = { id = 1, name = "main", frames = fixtures.stackTrace.stackFrames } },
        current_frame = fixtures.stackTrace.stackFrames[1],
        received = {},
        frame_set = nil,
        request = function(_, command, arguments, on_result)
            table.insert(session.received, { command = command, arguments = arguments })

            -- Mirror Session:request exactly: only take over the coroutine when
            -- the caller did NOT pass a callback (lua/dap/session.lua:1887).
            local co, is_main
            if not on_result then
                co, is_main = coroutine.running()
                if co and not is_main then
                    on_result = function(...)
                        coroutine.resume(co, ...)
                    end
                else
                    co = nil
                    on_result = function() end
                end
            end

            local response
            if command == "variables" then
                response = { variables = arguments.variablesReference == 100 and children or {} }
            elseif command == "setVariable" then
                response = { value = arguments.value, type = "int", variablesReference = 0 }
            elseif command == "evaluate" then
                response = { result = "evaluated:" .. arguments.expression, type = "int", variablesReference = 0 }
            else
                response = fixtures[command] or {}
            end

            vim.schedule(function()
                on_result(nil, response)
            end)

            if co then
                return coroutine.yield()
            end
        end,
        evaluate = function(self, args, fn)
            args.frameId = args.frameId or (self.current_frame or {}).id
            return self:request("evaluate", args, fn)
        end,
        _frame_set = function(_, frame)
            session.frame_set = frame
        end,
        set_breakpoints = function(_, bps)
            table.insert(session.received, { command = "setBreakpoints", arguments = vim.deepcopy(bps) })
        end,
        _step = function() end,
        _pause = function() end,
    }

    return session
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local dapmcp = require("dap-mcp")
local util = require("dap-mcp.util")
local dispatch = require("dap-mcp.dispatch")

dapmcp.setup({})

local fake = new_fake_session()
util.session = function()
    return fake
end
-- `for_each_session` walks `dap.sessions()`, which is empty headless; point it
-- at the fake so breakpoint broadcasts are observable.
util.for_each_session = function(fn)
    fn(fake)
end

---Run a tool to completion, driving the event loop the way the Go sidecar's
---poll loop will. Tests may block; production must not.
---@return table result
local function run(name, args)
    local result = dapmcp.call(name, args)

    if not (result.ok and type(result.result) == "table" and result.result.pending) then
        return result
    end

    local ticket = result.result.ticket
    local final
    vim.wait(2000, function()
        local polled = dispatch.poll(ticket)
        if polled.ok and type(polled.result) == "table" and polled.result.pending then
            return false
        end
        final = polled
        return true
    end, 5)

    return final or { ok = false, error = { code = "test_timeout", message = "ticket never resolved: " .. name } }
end

---@return boolean encodable
local function encodable(value)
    return (pcall(vim.json.encode, value))
end

--------------------------------------------------------------------------------

group("registry")

local tools = dapmcp.tools()
local by_name = {}
for _, tool in ipairs(tools) do
    by_name[tool.name] = tool
end

local expected_tools = {
    "list_configurations",
    "start_session",
    "stop_session",
    "session_status",
    "control",
    "wait_for_pause",
    "list_breakpoints",
    "set_breakpoint",
    "remove_breakpoint",
    "get_stack",
    "select_frame",
    "list_threads",
    "get_variables",
    "get_value",
    "set_variable",
    "evaluate",
    "ui_open",
    "ui_close",
    "ui_undock",
    "ui_dock",
    "ui_host",
}

for _, name in ipairs(expected_tools) do
    local tool = by_name[name]
    ok(tool ~= nil, "tool registered: " .. name)
    if tool then
        ok(type(tool.description) == "string" and #tool.description > 0, "has a description: " .. name)
        ok(type(tool.input_schema) == "table" and tool.input_schema.type == "object", "has an object schema: " .. name)
    end
end

eq(#tools, #expected_tools, "registry holds exactly the expected tools")
ok(encodable(tools), "tools() is JSON encodable")

local encoded = vim.json.encode(tools)
ok(encoded:find('"properties":{}', 1, true) ~= nil, "empty schema properties encode as a JSON object, not an array")

group("dispatch contract")

local unknown = dapmcp.call("no_such_tool", {})
eq(unknown.ok, false, "unknown tool fails")
eq(unknown.error.code, "unknown_tool", "unknown tool has a stable error code")

local local_only = dapmcp.call("list_breakpoints", {})
ok(local_only.result.pending == nil, "a purely local tool answers without a ticket")

local bad_ticket = dapmcp.poll(999999)
eq(bad_ticket.error.code, "unknown_ticket", "polling an unknown ticket is a structured error")

group("session_status composer")

-- A real file on disk so the source window has something to read.
local source_path = vim.fn.tempname() .. ".py"
local source_lines = {}
for i = 1, 40 do
    table.insert(source_lines, ("line %d"):format(i))
end
vim.fn.writefile(source_lines, source_path)
fake.current_frame = { id = 11, name = "compute", line = 12, column = 3, source = { path = source_path } }
fake.threads[1].frames = { fake.current_frame, fixtures.stackTrace.stackFrames[2] }
fixtures.stackTrace.stackFrames[1].source = { path = source_path }

local status = run("session_status", {})
ok(status.ok, "session_status succeeds", status.ok and "" or vim.inspect(status.error))

local body = status.result
eq(body.state, "stopped", "state is stopped")
eq(body.thread_id, 1, "reports the stopped thread")
eq(body.frame.name, "compute", "reports the current frame")
eq(body.frame.file, source_path, "frame carries the source path")
eq(body.frame.line, 12, "frame carries the line")

ok(body.source ~= nil, "source context is present")
eq(body.source.start_line, 2, "source starts source_context lines above the frame")
eq(#body.source.lines, 21, "source spans source_context lines either side")
eq(body.source.lines[1], "line 2", "source lines come from the file")

eq(#body.stack, 2, "stack is present")
eq(body.stack[1].name, "compute", "top of stack is the current frame")

ok(body.locals ~= nil, "locals are present")
eq(body.locals.scope, "Locals", "locals come from the first scope")
eq(body.locals.total, 12, "locals report the total child count")
eq(#body.locals.variables, 12, "default page holds max_children entries")

local first = body.locals.variables[1]
eq(first.truncated, true, "an oversized value is flagged truncated")
ok(#first.value < 260, "the clamped value respects max_value_width", ("width %d"):format(#first.value))
ok(first.value:find("\n") == nil, "the clamped value has no linebreaks")
ok(type(first.full_value_ref) == "string", "a truncated value carries a full_value_ref")
eq(body.locals.variables[2].truncated, nil, "a short value is not flagged")

ok(encodable(body), "session_status is JSON encodable")

group("get_value")

local full = run("get_value", { ref = first.full_value_ref })
ok(full.ok, "get_value succeeds")
eq(full.result.value, LONG_VALUE, "get_value returns the raw, unflattened text")

local missing = run("get_value", { ref = "val:does-not-exist" })
eq(missing.ok, false, "get_value on an unknown ref fails")
eq(missing.error.code, "unknown_ref", "unknown ref has a stable error code")

group("get_variables paging")

local page1 = run("get_variables", { variables_reference = 100, page = 1, page_size = 5 })
ok(page1.ok, "page 1 succeeds")
eq(#page1.result.variables, 5, "page 1 holds page_size entries")
eq(page1.result.variables[1].name, "var01", "page 1 starts at the first child")
eq(page1.result.has_more, true, "page 1 reports more to come")
eq(page1.result.total, 12, "page 1 reports the total")

local page3 = run("get_variables", { variables_reference = 100, page = 3, page_size = 5 })
eq(#page3.result.variables, 2, "the last page holds the remainder")
eq(page3.result.variables[1].name, "var11", "the last page starts where page 2 ended")
eq(page3.result.has_more, false, "the last page reports no more")

local page9 = run("get_variables", { variables_reference = 100, page = 9, page_size = 5 })
eq(#page9.result.variables, 0, "a page past the end is empty, not an error")
ok(encodable(page9.result), "an empty page is JSON encodable")

group("evaluate side-effect guard")

local refused_assign = run("evaluate", { expression = "x = 1" })
eq(refused_assign.ok, false, "assignment is refused by default")
eq(refused_assign.error.code, "side_effects_refused", "refusal has a stable error code")

local refused_call = run("evaluate", { expression = "foo()" })
eq(refused_call.ok, false, "a call is refused by default")

local allowed_comparison = run("evaluate", { expression = "a == b" })
ok(allowed_comparison.ok, "== is not mistaken for an assignment")

for _, expression in ipairs({ "a != b", "a <= b", "a >= b" }) do
    ok(run("evaluate", { expression = expression }).ok, "comparison is allowed: " .. expression)
end

for _, expression in ipairs({ "x += 1", "i++", "--i" }) do
    eq(run("evaluate", { expression = expression }).ok, false, "mutation is refused: " .. expression)
end

local plain = run("evaluate", { expression = "counter" })
ok(plain.ok, "a plain expression evaluates")
eq(plain.result.value, "evaluated:counter", "the adapter's result comes back")

require("dap-mcp.config").config.evaluate.allow_side_effects = true
ok(run("evaluate", { expression = "x = 1" }).ok, "assignment is allowed with allow_side_effects")
ok(run("evaluate", { expression = "foo()" }).ok, "a call is allowed with allow_side_effects")
require("dap-mcp.config").config.evaluate.allow_side_effects = false

group("stack and threads")

local stack = run("get_stack", {})
ok(stack.ok, "get_stack succeeds")
eq(#stack.result.frames, 2, "get_stack returns every frame")
eq(stack.result.frames[2].id, 12, "frame ids survive")

local selected = run("select_frame", { frame_id = 12 })
ok(selected.ok, "select_frame succeeds")
eq(fake.frame_set.id, 12, "select_frame reaches Session:_frame_set")

local no_frame = run("select_frame", { frame_id = 999 })
eq(no_frame.error.code, "unknown_frame", "selecting a missing frame is a structured error")

local threads = run("list_threads", {})
eq(#threads.result.threads, 2, "list_threads returns every thread")
eq(threads.result.threads[1].stopped, true, "the stopped thread is flagged")

group("set_variable")

local set = run("set_variable", { variables_reference = 100, name = "var02", value = "42" })
ok(set.ok, "set_variable succeeds")
eq(set.result.value, "42", "set_variable echoes the new value")

group("breakpoints round-trip")

local bp_path = vim.fn.tempname() .. ".py"
vim.fn.writefile({ "one", "two", "three", "four" }, bp_path)

local before = run("list_breakpoints", {})
eq(#before.result.breakpoints, 0, "no breakpoints to start with")

local set_bp = run("set_breakpoint", { file = bp_path, line = 3, condition = "i > 2" })
ok(set_bp.ok, "set_breakpoint succeeds", set_bp.ok and "" or vim.inspect(set_bp.error))

local listed = run("list_breakpoints", {}).result.breakpoints
eq(#listed, 1, "the breakpoint is listed")
eq(listed[1].line, 3, "listed at the right line")
-- Compare against what set_breakpoint reported, not the raw temp path: nvim
-- resolves symlinks when naming a buffer (/var -> /private/var on macOS).
eq(listed[1].file, set_bp.result.file, "listed against the same file set_breakpoint reported")
ok(listed[1].file:match("%.py$") ~= nil, "listed against a real path")
eq(listed[1].condition, "i > 2", "the condition round-trips")

local broadcast = nil
for _, message in ipairs(fake.received) do
    if message.command == "setBreakpoints" then
        broadcast = message.arguments
    end
end
ok(broadcast ~= nil, "setting a breakpoint broadcasts to the session")

local removed = run("remove_breakpoint", { file = bp_path, line = 3 })
eq(removed.result.removed, true, "remove_breakpoint reports the removal")
eq(#run("list_breakpoints", {}).result.breakpoints, 0, "the breakpoint is gone")

-- breakpoints.get() returns {} for a buffer with no signs left, so a naive
-- broadcast would never mention the source and the adapter would keep the
-- breakpoint alive. Assert the empty list actually reaches the session.
local last_broadcast = nil
for _, message in ipairs(fake.received) do
    if message.command == "setBreakpoints" then
        last_broadcast = message.arguments
    end
end
local bufnr = vim.fn.bufnr(vim.fn.fnamemodify(bp_path, ":p"))
ok(
    last_broadcast ~= nil and last_broadcast[bufnr] ~= nil and #last_broadcast[bufnr] == 0,
    "removing the last breakpoint broadcasts an explicit empty list for that source",
    vim.inspect(last_broadcast)
)

group("wait_for_pause")

-- Already stopped: answers without waiting.
local immediate = run("wait_for_pause", { timeout_ms = 1000 })
ok(immediate.ok, "wait_for_pause answers immediately when already stopped")
eq(immediate.result.event, "already_stopped", "and says so")

-- Running: must hand out a ticket and resolve only when the event fires.
fake.stopped_thread_id = nil

local pending = dapmcp.call("wait_for_pause", { timeout_ms = 5000 })
ok(pending.ok and pending.result.pending == true, "wait_for_pause returns pending while running")
local ticket = pending.result.ticket
ok(type(ticket) == "number", "and hands out a ticket")

eq(dispatch.poll(ticket).result.pending, true, "the ticket is still pending before the event")

local dap = require("dap")
local wait_keys = {}
for key, _ in pairs(dap.listeners.after.event_stopped) do
    if key:match("^dap%-mcp%.wait%.") then
        table.insert(wait_keys, key)
    end
end
eq(#wait_keys, 1, "exactly one wait listener is registered")

fake.stopped_thread_id = 1
dap.listeners.after.event_stopped[wait_keys[1]](fake, { reason = "breakpoint" })

local resolved
vim.wait(2000, function()
    local polled = dispatch.poll(ticket)
    if polled.ok and type(polled.result) == "table" and polled.result.pending then
        return false
    end
    resolved = polled
    return true
end, 5)

ok(resolved ~= nil and resolved.ok, "the ticket resolves once event_stopped fires")
if resolved and resolved.ok then
    eq(resolved.result.event, "stopped", "the snapshot names the event")
    eq(resolved.result.state, "stopped", "the snapshot is a full status")
    ok(resolved.result.stack ~= nil, "the snapshot carries the stack")
    ok(encodable(resolved.result), "the snapshot is JSON encodable")
end

eq(dap.listeners.after.event_stopped[wait_keys[1]], nil, "the wait listener is unregistered on resolve")
eq(dispatch.poll(ticket).error.code, "unknown_ticket", "a collected ticket is forgotten")

-- The timeout branch runs from a uv timer callback, i.e. a different execution
-- context than the event branch above. It is the only path in this tool that
-- resolves without nvim-dap involvement, so exercise it explicitly.
fake.stopped_thread_id = nil

local timing_out = dapmcp.call("wait_for_pause", { timeout_ms = 1 })
ok(timing_out.ok and timing_out.result.pending == true, "a doomed wait still returns pending")

local timed_out
vim.wait(2000, function()
    local polled = dispatch.poll(timing_out.result.ticket)
    if polled.ok and type(polled.result) == "table" and polled.result.pending then
        return false
    end
    timed_out = polled
    return true
end, 5)

ok(timed_out ~= nil and timed_out.ok, "the wait resolves when the timeout fires")
if timed_out and timed_out.ok then
    eq(timed_out.result.event, "timeout", "the snapshot names the timeout")
    eq(timed_out.result.timed_out, true, "the snapshot flags timed_out")
    eq(timed_out.result.state, "running", "a timeout still reports the live state")
    ok(encodable(timed_out.result), "a timed-out snapshot is JSON encodable")
end

local surviving = {}
for _, event in ipairs({ "event_stopped", "event_terminated", "event_exited" }) do
    for key, _ in pairs(dap.listeners.after[event]) do
        if key:match("^dap%-mcp%.wait%.") then
            table.insert(surviving, event .. "/" .. key)
        end
    end
end
eq(#surviving, 0, "a timeout unregisters every wait listener", vim.inspect(surviving))

fake.stopped_thread_id = 1

group("every tool's output is JSON encodable")

for _, name in ipairs(expected_tools) do
    local result = run(name, {
        variables_reference = 100,
        ref = first.full_value_ref,
        name = "var01",
        value = "1",
        expression = "counter",
        frame_id = 11,
        action = "step_over",
        file = bp_path,
        line = 2,
        config_name = "nope",
        timeout_ms = 1,
    })
    ok(encodable(result), "JSON encodable: " .. name, vim.inspect(result))
end

--------------------------------------------------------------------------------
-- Sidecar lifecycle
--
-- The binary itself is never launched here; what is checked is the wiring
-- around it -- path resolution, the status shape and the autostart modes.
--------------------------------------------------------------------------------

group("sidecar lifecycle")

local sidecar = require("dap-mcp.sidecar")

require("dap-mcp").setup({})
ok(sidecar.binary():match("bin/nvim%-dap%-mcp$") ~= nil, "default binary path sits under the plugin's bin/")
ok(sidecar.binary():sub(1, #repo) == repo, "default binary path is inside the plugin root")

require("dap-mcp").setup({ sidecar = { bin = "/tmp/somewhere/nvim-dap-mcp" } })
eq(sidecar.binary(), "/tmp/somewhere/nvim-dap-mcp", "sidecar.bin overrides the default path")

local sidecar_status = sidecar.status()
eq(sidecar_status.running, false, "the sidecar is not running before start()")
eq(sidecar_status.pid, nil, "no pid before start()")
eq(sidecar_status.url, nil, "no url before start()")
eq(sidecar_status.autostart, "on_session", "status reports the configured autostart mode")

-- A missing binary is reported, not raised: `:DapMcp start` must not throw in
-- a repo where `make build` has not been run.
eq(sidecar.start({ silent = true }), false, "start() refuses when the binary is missing")
ok(sidecar.status().last_error ~= nil, "the missing binary is recorded as last_error")
eq(sidecar.stop(), false, "stop() is a no-op when nothing is running")

local dap = require("dap")
local LISTENER_KEY = "dap-mcp.sidecar.autostart"

require("dap-mcp").setup({ autostart = "on_session" })
ok(dap.listeners.after.event_initialized[LISTENER_KEY] ~= nil, "autostart=on_session subscribes to event_initialized")

require("dap-mcp").setup({ autostart = "on_session" })
local subscriptions = 0
for key in pairs(dap.listeners.after.event_initialized) do
    if key == LISTENER_KEY then
        subscriptions = subscriptions + 1
    end
end
eq(subscriptions, 1, "a second setup() replaces its subscription instead of stacking one")

require("dap-mcp").setup({ autostart = "never" })
eq(
    dap.listeners.after.event_initialized[LISTENER_KEY],
    nil,
    "autostart=never removes the event_initialized subscription"
)

--------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, failed))

if failed > 0 then
    print("\nFailures:")
    for _, line in ipairs(failures) do
        print(line)
    end
    vim.cmd("cquit 1")
end

vim.cmd("qall!")
