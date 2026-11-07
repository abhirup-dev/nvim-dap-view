local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
H.setup({ host = { default = os.getenv("HOST") or "tab" }, winbar = { default_section = "scopes" } })
local fake = H.new_fake_session()
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
H.install_session(fake)
local value, cached_value, pending, input, reads = "42", "42", nil, nil, 0
local original_request = fake.request
fake.request = function(self, command, arguments, callback)
    if command == "setVariable" or command == "setExpression" then
        local co = coroutine.running()
        pending = function(err)
            if not err then
                value = arguments.value
            end
            assert(coroutine.resume(co, err, { value = value }))
        end
        return coroutine.yield()
    elseif command == "scopes" then
        cached_value = value
    elseif command == "variables" then
        reads = reads + 1
        local co = not callback and coroutine.running()
        vim.schedule(function()
            local response = { variables = { { name = "count", value = cached_value, variablesReference = 0 } } }
            if callback then
                callback(nil, response)
            else
                assert(coroutine.resume(co, nil, response))
            end
        end)
        if co then
            return coroutine.yield()
        end
        return
    end
    return original_request(self, command, arguments, callback)
end
vim.ui.input = function(_, callback)
    input = callback
end
local function rendered()
    return table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n")
end
local function edit(new_value)
    for line, text in ipairs(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)) do
        if text:find("count", 1, true) then
            require("dap-view.scopes.actions").set_value(line)
            input(new_value)
            return
        end
    end
    error("count not rendered")
end
require("dap-view").open()
H.pump(100)
H.ok(rendered():find("42", 1, true), "initial value rendered")
local before = reads
edit("99")
H.pump()
H.eq(reads, before, "no redraw before adapter accepts asynchronous edit")
pending(nil)
H.pump(100)
H.ok(rendered():find("99", 1, true), "accepted edit rendered without stepping")
before = reads
edit(nil)
H.pump()
H.eq(reads, before, "cancelled input does not refresh")
edit("invalid")
pending({ message = "invalid value" })
H.pump()
H.eq(reads, before, "failed edit does not refresh")
H.ok(rendered():find("99", 1, true), "failed edit preserves displayed value")
fake.capabilities.supportsSetExpression = true
require("dap-view.views.set").set_expr("count", "101")
pending(nil)
H.pump(100)
H.ok(rendered():find("101", 1, true), "setExpression also refreshes scopes")
edit("102")
require("dap-view").show_view("breakpoints")
pending(nil)
H.pump()
H.eq(state.current_section, "breakpoints", "late reply preserves newly selected view")
require("dap-view").show_view("scopes")
H.pump(100)
edit("103")
before = reads
fake.current_frame = { id = 12 }
pending(nil)
H.pump()
H.eq(reads, before, "late reply does not refresh a different frame")
H.done()
