-- A `stopped` event has to refresh the view even when the user is not looking at
-- it, which under the tab host means "from another tabpage".
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local dap = require("dap")
local host_name = os.getenv("HOST") or "tab"

if host_name ~= "tab" then
    -- The split host has no window on a foreign tabpage by design
    H.done()
    return
end

H.setup({
    host = { default = host_name },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
})

local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
fake.current_frame = {
    id = 11,
    name = "compute",
    line = 12,
    column = 3,
    source = { path = nil },
    scopes = { { name = "Locals", variablesReference = 100 } },
}
H.install_session(fake)

H.group("stop lands while the user is on their own tabpage")

local origin = vim.api.nvim_get_current_tabpage()

require("dap-view").open()
H.pump(200)

require("dap-view").show_view("scopes")
H.pump(300)

H.ok(#vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false) > 1, "scopes rendered")

vim.api.nvim_set_current_tabpage(origin)
H.pump(100)

require("dap-view.util").set_lines(state.bufnr, 0, -1, false, { "STALE" })

dap.listeners.after.scopes["dap-view"](fake)
H.pump(400)

local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
H.ok(lines[1] ~= "STALE", "the scopes view refreshed", vim.inspect(lines))

H.group("add_expr from another tabpage")

require("dap-view").add_expr("myvar", true)
H.pump(400)

H.eq(state.current_section, "watches", "add_expr switched to the watches view")
H.ok(state.watched_expressions["myvar"] ~= nil, "the expression was registered")

H.done()
