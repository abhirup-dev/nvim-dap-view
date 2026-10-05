local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local D = require("dap-view.decoders")
local state = require("dap-view.state")
local calls = 0
H.setup({
    host = { default = os.getenv("HOST") or "tab" },
    winbar = { default_section = "scopes" },
    decoders = {
        profile = "json",
        profiles = {
            {
                name = "json",
                decoders = {
                    {
                        name = "JSON",
                        kind = "lua",
                        match = { name = "payload" },
                        decode = function(var)
                            calls = calls + 1
                            return D.from_json(vim.json.decode(var.value))
                        end,
                    },
                },
            },
            {
                name = "rules",
                decoders = {
                    {
                        name = "fields",
                        kind = "rules",
                        match = { name = "wrapper" },
                        hide = { "secret" },
                        rename = { a = "renamed" },
                        order = { "z", "renamed" },
                    },
                },
            },
        },
    },
})
local fake = H.new_fake_session()
fake.current_frame = { id = 11, scopes = { { name = "Locals", variablesReference = 100 } } }
local raw = '{"age":37,"address":{"city":"Kolkata"},"tags":["a","b"]}'
local function respond(command, args)
    assert(not args.variablesReference or args.variablesReference >= 0, "synthetic reference sent to adapter")
    if command == "evaluate" then
        return { result = raw, variablesReference = 0, type = "string" }
    end
    if args.variablesReference == 100 then
        return {
            variables = {
                { name = "payload", value = raw, variablesReference = 0, type = "string", evaluateName = "payload" },
                { name = "plain", value = "42", variablesReference = 0, type = "int", evaluateName = "plain" },
                { name = "wrapper", value = "{}", variablesReference = 101, type = "struct" },
            },
        }
    end
    return {
        variables = {
            { name = "a", value = "1", variablesReference = 0 },
            { name = "secret", value = "2", variablesReference = 0 },
            { name = "z", value = "3", variablesReference = 0 },
        },
    }
end
fake.request = function(_, cmd, args, cb)
    fake.received[#fake.received + 1] = { command = cmd, arguments = args }
    local r = respond(cmd, args)
    if cb then
        vim.schedule(function()
            cb(nil, r)
        end)
        return
    end
    return nil, r
end
H.install_session(fake)
local function lines()
    return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n")
end
local function render()
    require("dap-view").show_view("scopes")
    H.pump(100)
end
require("dap-view").open()
render()
H.eq(calls, 0, "decode lazy until expansion")
H.ok(state.variable_path_to_reference["Locals.payload"] < 0, "matched scalar gets expansion affordance")
H.ok(lines():find("plain = 42", 1, true), "unmatched variable unchanged")
state.variable_path_is_expanded["Locals.payload"] = true
state.variable_path_is_expanded["Locals.payload.decoded"] = true
state.variable_path_is_expanded["Locals.payload.decoded.address"] = true
state.variable_path_is_expanded["Locals.payload.decoded.tags"] = true
render()
H.ok(lines():find("age = 37", 1, true), "decoded scalar in scopes")
H.ok(lines():find('city = "Kolkata"', 1, true), "nested decoded field")
H.ok(lines():find('2 = "b"', 1, true), "repeated decoded field")
H.ok(lines():find("raw = ", 1, true), "raw sibling available")
H.eq(calls, 1, "cached between renders")
-- A real second Neovim mirrors rendered text and forwards keypresses to the owner.
local remote_config = require("dap-view.setup").config.host.remote
remote_config.multiplexer = "custom"
remote_config.nvim_args = { "--headless", "--clean" }
remote_config.spawn = function(cmd)
    return vim.fn.jobstart(cmd)
end
remote_config.close = function(job)
    pcall(vim.fn.jobstop, tonumber(job))
end
require("dap-view.host").switch("remote")
H.pump(250)
local remote = require("dap-view.host.remote")
local channel = assert(remote.status().chan)
local function remote_text()
    return table.concat(
        vim.rpcrequest(
            channel,
            "nvim_exec_lua",
            "return vim.api.nvim_buf_get_lines(dapview_viewer.buf, 0, -1, false)",
            {}
        ),
        "\n"
    )
end
H.ok(remote_text():find("age = 37", 1, true), "detached viewer receives decoded tree")
local payload_line
for line, path in pairs(state.line_to_variable_path) do
    if path == "Locals.payload" then
        payload_line = line
    end
end
vim.rpcrequest(
    channel,
    "nvim_exec_lua",
    [[
    local line = ...
    vim.api.nvim_win_set_cursor(dapview_viewer.win, {line, 0})
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(dapview_viewer.buf, "n")) do
        if map.lhs == "<CR>" then map.callback(); return true end
    end
    error("viewer toggle mapping missing")
]],
    { payload_line }
)
H.pump(250)
H.ok(not remote_text():find("age = 37", 1, true), "viewer keypress collapses owner synthetic tree")
require("dap-view.host").switch(os.getenv("HOST") or "tab")
state.variable_path_is_expanded["Locals.payload"] = true
render()

state.variable_path_is_expanded["Locals.payload"] = false
render()
H.ok(not lines():find("age = 37", 1, true), "collapse hides decoded subtree")
state.variable_path_is_expanded["Locals.payload"] = true
render()
local count = #fake.received
require("dap-view.views.set").set_value(
    state.variable_path_to_parent_reference["Locals.payload.decoded.age"],
    "age",
    "90",
    nil
)
H.eq(#fake.received, count, "synthetic mutation blocked")
require("dap-view.views.set").set_value(100, "plain", "90", "plain")
H.eq(fake.received[#fake.received].command, "setVariable", "original edits still reach adapter")
D.use("rules")
render()
H.ok(not lines():find("JSON", 1, true), "runtime profile switching removes JSON decoder")
state.variable_path_is_expanded["Locals.wrapper"] = true
state.variable_path_is_expanded["Locals.wrapper.decoded"] = true
render()
local text = lines()
H.ok(text:find("renamed = 1", 1, true), "rule rename")
H.ok(not text:find("secret", 1, true), "rule hide")
H.ok(text:find("z = 3", 1, true) < text:find("renamed = 1", 1, true), "rule ordering preserved")
D.use("json")
raw = raw:gsub("37", "38")
D.invalidate()
render()
H.ok(lines():find("age = 38", 1, true), "changed stop invalidates cache")
raw = "{invalid"
D.invalidate()
render()
H.ok(lines():find("decode error", 1, true), "malformed fallback visible")
H.ok(lines():find("raw = {invalid", 1, true), "raw survives failure")
raw = '{"age":39}'
D.invalidate()
coroutine.wrap(function()
    require("dap-view.watches.eval").evaluate_expression("payload", true)
end)()
H.pump(150)
local watch = state.watched_expressions.payload
H.ok(watch and watch.children and watch.children[1].variable.name == "raw", "watch has raw node")
watch.children[2].expanded = true
coroutine.wrap(function()
    require("dap-view.watches.eval").evaluate_expression("payload", true)
end)()
require("dap-view").show_view("watches")
H.pump(100)
H.ok(lines():find("age = 39", 1, true), "watch decoded subtree")
state.hover = "payload"
state.hovered_expression = { response = { result = raw, variablesReference = 0, type = "string" }, expanded = true }
state.hover_path_is_expanded["payload.decoded"] = true
local buf = vim.api.nvim_create_buf(false, true)
coroutine.wrap(function()
    require("dap-view.hover.view").show(buf)
end)()
H.pump(100)
local hover = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
H.ok(hover:find("age = 39", 1, true) and hover:find("raw = ", 1, true), "hover raw and decoded tree")
state.hover, state.hovered_expression = nil, nil
H.group("runtime validation")
local function rejected(decoder, label)
    H.ok(not pcall(D.register_decoder_profile, { name = "unsafe", decoders = { decoder } }), label)
end
rejected({ name = "x", kind = "lua", match = { name = "x" }, decode = function() end }, "runtime Lua rejected")
rejected({
    name = "x",
    kind = "rules",
    match = function()
        return true
    end,
}, "runtime match code rejected")
rejected(
    { name = "x", kind = "command", match = { name = "x" }, command = "/bin/sh", source = { kind = "value" } },
    "unlisted command rejected"
)
rejected(
    { name = "x", kind = "evaluate", match = { name = "x" }, expression = "call x()" },
    "runtime evaluate rejected"
)
rejected(
    { name = "x", kind = "rules", match = { name = "x" }, computed = { x = "call x()" } },
    "runtime computed eval rejected"
)
rejected(
    { name = "x", kind = "rules", match = { name = "x" }, rename = { x = function() end } },
    "function nested in rules rejected"
)
H.ok(
    pcall(
        D.register_decoder_profile,
        { name = "safe", decoders = { { name = "x", kind = "rules", match = { name = "x" }, hide = { "secret" } } } }
    ),
    "data-only rules accepted"
)
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/nvim-dap-mcp")
require("dap-mcp.config").config.ui.integrate_dap_view = true
require("dap-mcp.tools.ui")
local registry = require("dap-mcp.registry")
local register = registry.get("register_decoder_profile").handler
H.ok(
    pcall(
        register,
        { profile = { name = "mcp", decoders = { { name = "fields", kind = "rules", match = { name = "wrapper" } } } } }
    ),
    "MCP registers safe profile"
)
H.ok(not pcall(register, {
    profile = {
        name = "mcp-unsafe",
        decoders = { { name = "eval", kind = "evaluate", match = { name = "wrapper" }, expression = "call x()" } },
    },
}), "MCP rejects target evaluation")
H.eq(registry.get("use_decoder_profile").handler({ name = "mcp" }), { name = "mcp" }, "MCP switches profile")
D.use("off")
render()
H.ok(not lines():find("decoded", 1, true), "off restores raw rendering")
H.done()
