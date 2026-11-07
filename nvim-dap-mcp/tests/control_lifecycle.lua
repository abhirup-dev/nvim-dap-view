local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local H = dofile(repo .. "/../tests/harness.lua")
vim.opt.runtimepath:prepend(repo)
H.setup({ host = { default = "split" } })
local dap = require("dap")
local breakpoints = require("dap.breakpoints")
local dispatch = require("dap-mcp.dispatch")
require("dap-mcp.tools.control")
local key = "dap-mcp.run_to_line"
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
dir = assert(vim.uv.fs_realpath(dir))
local file = dir .. "/main.lua"
vim.fn.writefile(vim.fn["repeat"]({ "-- fixture" }, 40), file)
local buf = vim.fn.bufadd(file)
vim.fn.bufload(buf)
local session, stepped, fail_install, fail_step
local function new_session()
    local fake = H.new_fake_session()
    fake.on_close = {}
    fake.set_breakpoints = function(_, _, callback)
        if fail_install then
            error("install failed")
        end
        if callback then
            vim.schedule(callback)
        end
    end
    fake._step = function()
        if fail_step then
            error("continue failed")
        end
        stepped = stepped + 1
    end
    session = fake
    H.install_session(fake)
    return fake
end
local function original()
    fail_install, fail_step, stepped = false, false, 0
    breakpoints.clear()
    breakpoints.set({ condition = "x == 1", log_message = "x={x}", hit_condition = "2" }, buf, 7)
    breakpoints.set({}, buf, 8)
    return vim.deepcopy(breakpoints.get())
end
local function run(line)
    return dispatch.call("control", { action = "run_to_line", file = file, line = line or 11 })
end
local function no_hooks(owner)
    return not owner.on_close[key]
        and not dap.listeners.before.event_stopped[key]
        and not dap.listeners.before.event_terminated[key]
        and not dap.listeners.before.setBreakpoints[key]
        and not dap.listeners.before.continue[key]
end
local function event(name, owner, err)
    local listener = dap.listeners.before[name][key]
    if listener then
        listener(owner, err)
    end
end
new_session()
local before = original()
H.ok(run().ok, "run-to-line starts")
H.pump()
H.eq(stepped, 1, "installed target resumes owning session")
event("event_stopped", {})
H.eq(breakpoints.get()[buf][1].line, 11, "unrelated session event cannot restore breakpoints")
event("event_stopped", session)
H.eq(breakpoints.get(), before, "normal stop restores original conditions, log and hit metadata")
H.ok(no_hooks(session), "normal stop removes every ownership hook")
for _, ending in ipairs({ "event_terminated", "close", "continue_error", "breakpoint_error" }) do
    new_session()
    before = original()
    run()
    H.pump()
    if ending == "close" then
        local close = session.on_close[key]
        H.ok(type(close) == "function", "abrupt adapter close has a restoration hook")
        session.closed = true
        if close then
            close(session)
        end
        H.pump()
    elseif ending == "continue_error" then
        event("continue", session, { message = "rejected" })
    elseif ending == "breakpoint_error" then
        event("setBreakpoints", session, { message = "rejected" })
    else
        event(ending, session)
    end
    H.eq(breakpoints.get(), before, ending .. " restores user breakpoints")
    H.ok(no_hooks(session), ending .. " removes hooks")
end
new_session()
before = original()
run()
H.pump()
breakpoints.set({ condition = "new user condition" }, buf, 11)
breakpoints.set({}, buf, 20)
event("event_stopped", session)
local current = breakpoints.get()[buf]
local by_line = {}
for _, bp in ipairs(current) do
    by_line[bp.line] = bp
end
H.ok(by_line[7] and by_line[8] and by_line[20], "restoration preserves new user breakpoints")
H.eq(by_line[11] and by_line[11].condition, "new user condition", "user replacement of temporary target survives")
new_session()
before = original()
run(11)
H.pump()
local old_close = session.on_close[key]
run(12)
H.pump()
if old_close then
    old_close(session)
end
H.pump()
H.eq(breakpoints.get()[buf][1].line, 12, "obsolete close callback cannot clear replacement run")
event("event_stopped", session)
H.eq(breakpoints.get(), before, "repeated run restores original breakpoints")
new_session()
before = original()
fail_install = true
H.ok(not run().ok, "synchronous install error is returned")
H.eq(breakpoints.get(), before, "synchronous failure restores local state")
H.ok(no_hooks(session), "synchronous failure removes hooks")
fail_install = false
new_session()
before = original()
fail_step = true
run()
H.pump()
H.eq(breakpoints.get(), before, "synchronous resume failure restores local state")
H.ok(no_hooks(session), "resume failure removes hooks")
fail_step = false
new_session()
before = original()
run()
H.pump()
local close = session.on_close[key]
session.closed = true
if close then
    close(session)
end
H.pump()
new_session()
breakpoints.clear()
breakpoints.set({}, buf, 30)
event("event_stopped", session)
H.eq(breakpoints.get()[buf][1].line, 30, "next session stop cannot resurrect previous session breakpoints")
H.eq(#breakpoints.get()[buf], 1, "next session has no leaked restoration listener")
breakpoints.clear()
vim.fn.delete(dir, "rf")
H.done()
