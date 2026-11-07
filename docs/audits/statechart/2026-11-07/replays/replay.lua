-- Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
local repo = assert(os.getenv("DAP_REPO"))
local H = dofile(repo .. "/tests/harness.lua")
vim.opt.runtimepath:prepend(repo .. "/nvim-dap-mcp")
H.setup({ host = { default = "split" } })
local fake = H.new_fake_session()
H.install_session(fake)
local state = require("dap-view.state")
local dec = require("dap-view.decoders")
local function run(f)
    local co = coroutine.create(f)
    assert(coroutine.resume(co))
    return co
end
local function resume(co, r)
    local ok, e = coroutine.resume(co, nil, r)
    assert(ok, e)
end
fake.request = function()
    return coroutine.yield()
end
-- Replies.CurrentContext: Begin -> ContextChanges -> Reply (JS adapter workaround).
fake.capabilities.supportsSetExpression = true
fake.config.type = "pwa-node"
local co
-- set_expr starts its own coroutine; capture the yielded adapter request.
local editco
fake.request = function()
    editco = coroutine.running()
    return coroutine.yield()
end
require("dap-view.views.set").set_expr("x", "9", "Locals.x")
H.install_session(H.new_fake_session())
dec.invalidate()
resume(editco, { value = "OLD_SESSION" })
assert(state.variable_path_to_value["Locals.x"] == "OLD_SESSION")
print("REPLAY CurrentContext stale_js_value=" .. tostring(state.variable_path_to_value["Locals.x"]))
H.install_session(fake)
fake.request = function()
    return coroutine.yield()
end
-- Replies.RequestedHover: Begin -> RequestChanges -> Reply.
state.hover = "old"
state.hovered_expression = nil
co = run(function()
    require("dap-view.hover.eval").evaluate_expression("old")
end)
state.hover = "new"
resume(co, { result = "OLD_HOVER", variablesReference = 0 })
assert(state.hover == "new" and state.hovered_expression.response.result == "OLD_HOVER")
print("REPLAY RequestedHover requested=" .. state.hover .. " published=" .. state.hovered_expression.response.result)
-- Replies.RemovedWatchStaysRemoved: Begin -> RemoveWatch -> Reply.
state.watched_expressions.x = { id = 1, expanded = false, response = { result = "before" } }
state.expression_views_by_line[1] = { expression = "x", view = state.watched_expressions.x }
co = run(function()
    require("dap-view.watches.eval").evaluate_expression("x", false)
end)
require("dap-view.watches.actions").remove_watch_expr(1)
assert(state.watched_expressions.x == nil)
resume(co, { result = "REINSERTED", variablesReference = 0 })
assert(state.watched_expressions.x.response.result == "REINSERTED")
print("REPLAY RemovedWatchStaysRemoved published=" .. state.watched_expressions.x.response.result)
-- Remote: Ready -> QueueKey -> Dock -> RunKey. Isolated local host stands
-- for ready mirror; no transport is used because the race starts at on_key.
fake.request = H.new_fake_session().request
H.install_session(nil)
require("dap-view").open()
H.pump(30)
local remote = require("dap-view.host.remote")
local hits = 0
vim.keymap.set("n", "X", function()
    hits = hits + 1
end, { buffer = state.bufnr })
local queue = {}
local schedule = vim.schedule
vim.schedule = function(f)
    queue[#queue + 1] = f
end
remote.on_key("X", 1)
require("dap-view.host").switch("tab")
vim.schedule = schedule
for _, f in ipairs(queue) do
    f()
end
print("REPLAY NoOldCallback host=" .. require("dap-view.host").name() .. " key_hits=" .. hits)
-- Negative decoder refs must never reach adapter mutations.
local calls = {}
H.install_session(fake)
fake.request = function(_, method, args)
    calls[#calls + 1] = { method, args }
    return nil, { value = "bad" }
end
require("dap-mcp.tools.variables")
dec.setup({
    profile = "probe",
    profiles = {
        {
            name = "probe",
            decoders = { {
                name = "probe",
                kind = "lua",
                match = { name = "x" },
                decode = function()
                    return { value = "preview" }
                end,
            } },
        },
    },
})
local preview = dec.prepare({ name = "x", value = "raw", variablesReference = 100 }, "Locals.x", fake)
assert(preview.variablesReference < 0)
local r = require("dap-mcp.dispatch").call(
    "set_variable",
    { variables_reference = preview.variablesReference, name = "decoded", value = "9" }
)
assert(r.ok and calls[#calls][2].variablesReference == preview.variablesReference)
print(
    "REPLAY PreviewReadOnly ok="
        .. tostring(r.ok)
        .. " adapter_reference="
        .. tostring(calls[#calls][2].variablesReference)
)
-- Source-discovered watch value tooltip mismatch.
state.current_section = "watches"
state.variable_views_by_line[2] = { view = { variable = { name = "child", value = "42" } } }
local ok, e = pcall(require("dap-view.tree.value").value_at, 2)
assert(not ok and tostring(e):find("variable"))
print("REPLAY WatchTooltip ok=" .. tostring(ok) .. " error=" .. tostring(e))
vim.cmd("qa!")
