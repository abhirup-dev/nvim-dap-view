local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
H.setup({ host = { default = os.getenv("HOST") or "tab" }, winbar = { default_section = "scopes" } })
local dap = require("dap")
local state = require("dap-view.state")
local fake = H.new_fake_session()
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
H.install_session(fake)
local value, cached, scopes = "10", "10", 0
local original = fake.request
fake.request = function(self, command, args, callback)
    if command == "scopes" then
        scopes = scopes + 1
        cached = value
    elseif command == "variables" then
        local response = { variables = { { name = "x", value = cached, variablesReference = 0 } } }
        if callback then
            vim.schedule(function()
                callback(nil, response)
            end)
            return
        end
        local co = coroutine.running()
        vim.schedule(function()
            assert(coroutine.resume(co, nil, response))
        end)
        return coroutine.yield()
    end
    return original(self, command, args, callback)
end
local function rendered()
    return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n")
end
local function mutation(method, owner, err, args)
    dap.listeners.after[method]["dap-view"](owner or fake, err, {}, args or {})
end
require("dap-view").open()
H.pump(100)
H.ok(rendered():find("x = 10", 1, true), "initial scopes show adapter value")
value = "41"
mutation("setVariable")
H.pump(100)
H.ok(rendered():find("x = 41", 1, true), "external setVariable refreshes scopes without stepping")
H.eq(scopes, 1, "mutation obtains fresh scope references")
value = "42"
mutation("setExpression", fake, nil, { frameId = fake.current_frame.id })
H.pump(100)
H.ok(rendered():find("x = 42", 1, true), "external setExpression refreshes scopes")
local before = scopes
mutation("setVariable", fake, { message = "rejected" })
mutation("setVariable", H.new_fake_session())
mutation("setExpression", fake, nil, { frameId = 999 })
H.pump()
H.eq(scopes, before, "rejected edits and replies for other sessions or frames do not refresh")
mutation("setVariable")
local frame = fake.current_frame
fake.current_frame = { id = 12 }
H.pump()
H.eq(scopes, before, "frame changed before scheduled refresh is untouched")
fake.current_frame = frame
mutation("setVariable")
require("dap-view").show_view("breakpoints")
H.pump(100)
H.eq(state.current_section, "breakpoints", "accepted external edit preserves selected section")
-- The JS adapter workaround must obey the same ownership check as refresh.
fake.capabilities.supportsSetExpression = true
fake.config.type = "pwa-node"
local pending
fake.request = function()
    pending = coroutine.running()
    return coroutine.yield()
end
require("dap-view.views.set").set_expr("x", "9", "Locals.x")
state.variable_path_to_value["Locals.x"] = "NEW_SESSION"
state.variable_path_to_set_variables["Locals.x"] = nil
H.install_session(H.new_fake_session())
assert(coroutine.resume(pending, nil, { value = "OLD_SESSION" }))
H.pump()
H.eq(state.variable_path_to_value["Locals.x"], "NEW_SESSION", "old JS reply cannot overwrite new session cache")
H.eq(state.variable_path_to_set_variables["Locals.x"], nil, "old JS reply cannot set workaround flag")
H.done()
