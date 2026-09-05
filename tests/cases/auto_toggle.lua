local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local dap = require("dap")
local host_name = os.getenv("HOST") or "tab"
-- One value per process, since `setup` is not re-entrant. `true` is what the
-- user runs with and exercises both the open and the close half
local at = true

H.setup({
    host = { default = host_name },
    auto_toggle = at,
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
})

local term_buf = H.make_term_buf()
local fake = H.new_fake_session({ term_buf = term_buf })
H.install_session(fake)
local host = require("dap-view.host")

H.group(("auto_toggle=%s host=%s"):format(tostring(at), host_name))
local tabs_before = #vim.api.nvim_list_tabpages()

-- launch
dap.listeners.before.launch["dap-view"](fake, {})
H.pump(250)
local should_open = at and at ~= "open_term"
H.eq(host.get().is_open(), should_open and true or false, "view open after launch")
if host_name == "tab" and should_open then
    H.eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "tab host created its tabpage on launch")
end

-- terminate
dap.listeners.before.event_terminated["dap-view"](fake, {})
H.pump(150)
local should_close = at and at ~= "open_term" and at ~= "open"
if should_open then
    H.eq(host.get().is_open(), not should_close, "view state after terminate")
end
if host_name == "tab" and should_open and should_close then
    H.eq(#vim.api.nvim_list_tabpages(), tabs_before, "tab host tore its tabpage down on terminate")
end
-- The tab host's own close_on_terminate runs on the `after` listener
if dap.listeners.after.event_terminated["dap-view-host-tab"] then
    dap.listeners.after.event_terminated["dap-view-host-tab"](fake, {})
    H.pump(150)
    H.ok(not host.get().is_open(), "tab host closed on terminate (host.tab.close_on_terminate)")
end

H.ok(
    vim.api.nvim_buf_is_valid(term_buf) == (at == "keep_terminal" or not should_close or true),
    "terminal buffer survives"
)
H.done()
