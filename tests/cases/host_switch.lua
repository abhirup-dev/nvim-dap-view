local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host = require("dap-view.host")
local start = os.getenv("HOST") or "tab"
H.setup({ host = { default = start } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)

H.group("host switching / start=" .. start)
require("dap-view").open()
H.pump(250)
local buf = state.bufnr
H.ok(host.get().is_open(), "opened under " .. start)

local other = start == "tab" and "split" or "tab"
vim.cmd("DapViewHost " .. other)
H.pump(250)
H.eq(host.name(), other, "switched host")
H.ok(host.get().is_open(), "open under " .. other)
H.eq(state.bufnr, buf, "the view buffer survived the switch")
H.eq(vim.api.nvim_win_get_buf(state.winnr), buf, "and is shown in the new window")
if other == "tab" then
    H.eq(#vim.api.nvim_list_tabpages(), 2, "tab host made its tabpage")
else
    H.eq(#vim.api.nvim_list_tabpages(), 1, "split host tore the tabpage down")
end

vim.cmd("DapViewHost " .. start)
H.pump(250)
H.eq(host.name(), start, "switched back")
H.ok(host.get().is_open(), "open again under " .. start)
H.eq(state.bufnr, buf, "buffer survived the round trip")

H.group("sections still work after the round trip")
require("dap-view").show_view("breakpoints")
H.pump(200)
H.eq(state.current_section, "breakpoints", "section switch works")
local maps = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(state.bufnr, "n")) do
    maps[m.lhs] = true
end
H.ok(maps["g?"] and maps["S"], "base and winbar keymaps survived")

H.group("unknown host")
local notified = {}
local orig = vim.notify
vim.notify = function(m)
    table.insert(notified, m)
end
vim.cmd("DapViewHost nope")
vim.notify = orig
H.ok(
    #notified == 1 and tostring(notified[1]):find("Unknown host"),
    "unknown host reported, nothing torn down",
    vim.inspect(notified)
)
H.ok(host.get().is_open(), "view still open after a failed switch")
H.eq(require("dap-view.complete").complete_hosts(""), { "remote", "split", "tab" }, "host completion")
H.done()
