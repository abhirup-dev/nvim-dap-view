local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")

H.setup({
    host = { default = "tab" },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
})
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)

H.group("tab host: leaving the debugger tab")
local origin = vim.api.nvim_get_current_tabpage()
require("dap-view").open()
H.pump(120)
local dv_tab = vim.api.nvim_get_current_tabpage()
H.ok(state.winnr ~= nil, "winnr set right after open")

-- Go back to the user's tab, exactly as they would
vim.api.nvim_set_current_tabpage(origin)
H.pump(60)
H.ok(state.winnr ~= nil, "winnr survives leaving the debugger tab", "state.winnr=" .. tostring(state.winnr))

H.group("callers that need state.winnr from another tab")
local notified = {}
local orig_notify = vim.notify
vim.notify = function(msg)
    table.insert(notified, msg)
end

require("dap-view").jump_to_view("watches")
H.pump(60)
require("dap-view").show_view("threads")
H.pump(60)
require("dap-view").navigate({ wrap = true, count = 1 })
H.pump(60)
require("dap-view").add_expr("foo", true)
H.pump(120)
vim.notify = orig_notify

H.eq(notified, {}, "no 'couldn't find the window' notifications from tab 1")

H.group("host.is_open from another tab")
local host = require("dap-view.host")
H.ok(host.get().is_open(), "tab host reports open from tab 1")
H.done()
