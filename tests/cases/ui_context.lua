-- Characterize validity through callers, including the intentionally ID-based frame check.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
H.setup({ host = { default = vim.env.HOST or "tab" } })
local state = require("dap-view.state")
local dap = require("dap")
local decoders = require("dap-view.decoders")
local hover = require("dap-view.hover.eval")
local watches = require("dap-view.watches.eval")
local function check(label, change, accepted)
    local session = H.new_fake_session()
    H.install_session(session)
    session.request = function()
        return coroutine.yield()
    end
    state.hover, state.hovered_expression = "x", nil
    state.watched_expressions = {}
    local h = coroutine.create(function()
        hover.evaluate_expression("x")
    end)
    local w = coroutine.create(function()
        watches.evaluate_expression("x", false)
    end)
    assert(coroutine.resume(h))
    assert(coroutine.resume(w))
    change(session)
    assert(coroutine.resume(h, nil, { result = label, variablesReference = 0 }))
    assert(coroutine.resume(w, nil, { result = label, variablesReference = 0 }))
    H.eq(state.hovered_expression ~= nil, accepted, label .. " (hover cache)")
    H.eq(state.watched_expressions.x ~= nil, accepted, label .. " (watch cache)")
end
check("same-ID frame object replacement accepted", function(s)
    s.current_frame = { id = s.current_frame.id }
end, true)
check("stopped flag alone is not checked", function(s)
    s.stopped_thread_id = nil
end, true)
check("different frame ID rejected", function(s)
    s.current_frame = { id = 999 }
end, false)
check("session replacement with reused IDs rejected", function()
    H.install_session(H.new_fake_session())
end, false)
check("unobserved frame ID ABA remains accepted", function(s)
    local frame = s.current_frame
    s.current_frame = { id = 999 }
    s.current_frame = frame
end, true)
check("continue and re-stop with reused frame ID rejected", function(s)
    dap.listeners.before.event_continued["dap-view-decoders"]()
    s.current_frame = { id = s.current_frame.id }
    dap.listeners.before.event_stopped["dap-view-decoders"]()
end, false)
for _, event in ipairs({
    "event_continued",
    "continue",
    "next",
    "stepIn",
    "stepOut",
    "event_stopped",
    "scopes",
    "event_terminated",
    "disconnect",
    "setVariable",
    "setExpression",
    "restart",
}) do
    check(event .. " invalidates pending UI work", function()
        dap.listeners.before[event]["dap-view-decoders"]()
    end, false)
end
check("profile off invalidates pending UI work", function()
    decoders.use("off")
end, false)
check("runtime profile registration invalidates pending UI work", function()
    decoders.register_decoder_profile({ name = "empty", decoders = {} })
end, false)
check("decoder setup invalidates pending UI work", function()
    decoders.setup({})
end, false)
-- Scheduled decoder refreshes must not start a fake suspended request at teardown.
H.install_session(nil)
H.done()
