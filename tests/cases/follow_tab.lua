local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"
H.setup({ host = { default = host_name }, follow_tab = true })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)
local host = require("dap-view.host")

H.group("follow_tab=true / host=" .. host_name)
require("dap-view").open()
H.pump(200)
local first_win = state.winnr
local tabs = #vim.api.nvim_list_tabpages()

vim.cmd("tabnew")
H.pump(200)
if host_name == "split" then
    H.ok(host.get().is_open(), "split follows the user into the new tab")
    H.ok(state.winnr ~= first_win, "a new split was opened in the new tab")
else
    H.eq(#vim.api.nvim_list_tabpages(), tabs + 1, "tab host did not churn tabpages on TabEnter")
    H.eq(state.winnr, first_win, "tab host kept its window")
end
H.done()
