-- Real Delve + serialized protobuf, in an isolated process. Requires fixture generation/build.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local root = vim.fn.getcwd()
local fixture = root .. "/examples/decoders"
local D = require("dap-view.decoders")
local dap = require("dap")
local state = require("dap-view.state")
local python = vim.fn.exepath("python3")
H.setup({
    host = { default = os.getenv("HOST") or "split" },
    winbar = { default_section = "scopes" },
    decoders = {
        profile = "proto",
        commands = {
            person = {
                argv = {
                    python,
                    fixture .. "/decode.py",
                    "--descriptor",
                    fixture .. "/fixture.pb",
                    "--type",
                    "example.Person",
                },
            },
            missing = {
                argv = {
                    python,
                    fixture .. "/decode.py",
                    "--descriptor",
                    fixture .. "/missing.pb",
                    "--type",
                    "example.Person",
                },
            },
        },
        profiles = {
            {
                name = "proto",
                decoders = {
                    {
                        name = "Person",
                        kind = "command",
                        match = { type = "main.Envelope" },
                        command = "person",
                        source = { kind = "go_bytes", field = "Payload" },
                    },
                },
            },
            {
                name = "missing",
                decoders = {
                    {
                        name = "Missing",
                        kind = "command",
                        match = { type = "main.Envelope" },
                        command = "missing",
                        source = { kind = "go_bytes", field = "Payload" },
                    },
                },
            },
        },
    },
})
dap.adapters.go = {
    type = "server",
    port = "${port}",
    executable = { command = assert(vim.env.DLV, "set DLV"), args = { "dap", "-l", "127.0.0.1:${port}" } },
}
local source = fixture .. "/main.go"
vim.cmd.edit(source)
local stops = {}
for i, line in ipairs(vim.fn.readfile(source)) do
    if line:find("// BREAK", 1, true) then
        stops[#stops + 1] = i
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        dap.toggle_breakpoint()
    end
end
local stopped, failure = 0
-- Run assertions outside DAP listener callbacks so failures cannot be swallowed.
dap.listeners.after.scopes["decoder-test"] = function()
    stopped = stopped + 1
end
dap.run({
    type = "go",
    request = "launch",
    name = "decoder fixture",
    mode = "exec",
    program = fixture .. "/fixture",
    cwd = fixture,
})
local function wait_stop(n)
    assert(
        vim.wait(20000, function()
            return stopped >= n
        end, 20),
        "Delve stop timeout; inspect :DapShowLog"
    )
    assert(dap.session() and dap.session().current_frame, "missing stopped frame")
end
local function run(fn)
    local done, err = false, nil
    coroutine.wrap(function()
        local ok, result = pcall(fn)
        if not ok then
            err = result
        end
        done = true
    end)()
    assert(
        vim.wait(15000, function()
            return done
        end, 10),
        "async assertion timeout"
    )
    assert(not err, err)
end
local function text()
    return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n")
end
local function expand_scopes()
    state.variable_path_is_expanded["Locals.wrapper"] = true
    state.variable_path_is_expanded["Locals.wrapper.decoded"] = true
    state.variable_path_is_expanded["Locals.wrapper.decoded.address"] = true
    state.variable_path_is_expanded["Locals.wrapper.decoded.tags"] = true
    require("dap-view").show_view("scopes")
end
local function await_text(needle)
    assert(
        vim.wait(10000, function()
            return text():find(needle, 1, true) ~= nil
        end, 20),
        needle .. " missing: " .. text()
    )
end
wait_stop(1)
require("dap-view").open()
H.pump(100)
expand_scopes()
await_text("age = 37")
H.ok(text():find('city = "Kolkata"', 1, true), "Delve serialized nested protobuf")
H.ok(text():find('2 = "protobuf"', 1, true), "Delve serialized repeated protobuf")
H.ok(text():find("raw = ", 1, true), "Delve raw wrapper remains accessible")
-- Verify every binary byte, including NUL/0xff, past Delve's default 64-element load.
run(function()
    local s = dap.session()
    local err, r =
        s:request("evaluate", { expression = "wrapper.Payload", context = "watch", frameId = s.current_frame.id })
    assert(not err, vim.inspect(err))
    local var = {
        name = "Payload",
        type = r.type,
        value = r.result,
        variablesReference = r.variablesReference,
        evaluateName = "wrapper.Payload",
    }
    local bytes = D.read_payload(var, { kind = "go_bytes" }, D.context(s, "wrapper.Payload"))
    local file = assert(io.open(fixture .. "/person-37.bin", "rb"))
    local expected = file:read("*a")
    file:close()
    H.eq(bytes, expected, "every binary byte extracted, including NUL/0xff past first page")
    H.ok(#bytes > 600, "fixture exceeds adapter default load")
end)
state.variable_path_is_expanded["Locals.wrapper"] = false
require("dap-view").show_view("scopes")
H.pump(100)
H.ok(not text():find("age = 37", 1, true), "real fixture collapse")
expand_scopes()
await_text("age = 37")
run(function()
    require("dap-view.watches.eval").evaluate_expression("wrapper", true)
end)
H.pump(500)
local watch = state.watched_expressions.wrapper
assert(watch.children and watch.children[2], "watch decode missing")
watch.children[2].expanded = true
run(function()
    require("dap-view.watches.eval").evaluate_expression("wrapper", true)
end)
require("dap-view").show_view("watches")
await_text("age = 37")
H.ok(true, "real fixture decoded in watches")
state.hover = "wrapper"
run(function()
    require("dap-view.hover.eval").evaluate_expression("wrapper")
end)
state.hovered_expression.expanded = true
state.hover_path_is_expanded["wrapper.decoded"] = true
local buf = vim.api.nvim_create_buf(false, true)
run(function()
    require("dap-view.hover.view").show(buf)
end)
H.ok(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("age = 37", 1, true),
    "real fixture decoded in hover"
)
state.hover, state.hovered_expression = nil, nil
D.use("off")
expand_scopes()
H.pump(150)
H.ok(not text():find("decoded", 1, true), "real fixture profile off")
D.use("missing")
expand_scopes()
await_text("decode error")
H.ok(text():find("raw = ", 1, true), "missing schema retains raw")
D.use("proto")
expand_scopes()
await_text("age = 37")
-- Step to assignment, then next print; value must change while still in the same frame.
local before = stopped
dap.step_over()
wait_stop(before + 1)
before = stopped
dap.step_over()
wait_stop(before + 1)
expand_scopes()
await_text("age = 38")
H.ok(true, "stepping refreshed serialized bytes in same frame")
before = stopped
dap.continue()
wait_stop(before + 1)
expand_scopes()
await_text("decode error")
H.ok(text():find("raw = ", 1, true), "malformed protobuf fallback retains raw")
run(function()
    dap.session():request("disconnect", { terminateDebuggee = true })
end)
H.done()
