local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local H = dofile(root .. "/tests/harness.lua")
H.setup({ host = { default = vim.env.HOST } })
local session = H.new_fake_session()
H.install_session(session)
local state = require("dap-view.state")
session.request = function()
    return coroutine.yield()
end
local function start(fn)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co)
    assert(ok, err)
    return co
end
local function reply(co, response)
    local ok, err = coroutine.resume(co, nil, response)
    assert(ok, err)
end
local function result(value, ref)
    return { result = value, variablesReference = ref or 0 }
end
local hover = require("dap-view.hover.eval")
state.hover = "old"
local old = start(function()
    hover.evaluate_expression("old")
end)
state.hover = "new"
reply(old, result("old"))
H.eq(state.hovered_expression, nil, "changed hover rejects old reply")
local a = start(function()
    hover.evaluate_expression("new")
end)
local b = start(function()
    hover.evaluate_expression("new")
end)
reply(b, result("newer"))
reply(a, result("older"))
H.eq(state.hovered_expression.response.result, "newer", "latest hover request wins")
local eval = require("dap-view.watches.eval")
local actions = require("dap-view.watches.actions")
state.watched_expressions.x = { id = 1, expanded = false }
state.expression_views_by_line[1] = { expression = "x", view = state.watched_expressions.x }
old = start(function()
    eval.evaluate_expression("x", false)
end)
actions.remove_watch_expr(1)
reply(old, result("stale"))
H.eq(state.watched_expressions.x, nil, "removed watch stays removed")
old = start(function()
    eval.evaluate_expression("x", false)
end)
-- An actual removal invalidates even a pending first-add evaluation.
state.watched_expressions.x = { id = 2, expanded = false }
state.expression_views_by_line[1] = { expression = "x", view = state.watched_expressions.x }
actions.remove_watch_expr(1)
a = start(function()
    eval.evaluate_expression("x", false)
end)
reply(a, result("readded"))
reply(old, result("stale"))
H.eq(state.watched_expressions.x.response.result, "readded", "old registration cannot overwrite re-add")
a = start(function()
    eval.evaluate_expression("y", false)
end)
b = start(function()
    eval.evaluate_expression("y", false)
end)
reply(a, result("first"))
reply(b, result("second"))
H.eq(state.watched_expressions.y.response.result, "second", "simultaneous first evaluations publish")
state.watched_expressions.z = { id = 3, expanded = true }
state.expression_views_by_line[1] = { expression = "z", view = state.watched_expressions.z }
a = start(function()
    eval.evaluate_expression("z", true)
end)
reply(a, result("expand", 42))
actions.remove_watch_expr(1)
reply(a, { variables = {} })
H.eq(state.watched_expressions.z, nil, "removal during child expansion stays removed")
state.current_section = "watches"
state.variable_views_by_line[2] = { view = { variable = { name = "child", value = "full\nvalue" } } }
local ok, value, name = pcall(require("dap-view.tree.value").value_at, 2)
H.ok(ok, "indexed child value does not crash")
H.eq({ value, name }, { "full\nvalue", "child" }, "indexed child returns full value")
H.done()
