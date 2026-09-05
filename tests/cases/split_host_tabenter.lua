local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")

H.setup({ host = { default = "split" } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)

H.group("split host keeps upstream TabEnter semantics")
require("dap-view").open()
H.pump(120)
H.ok(state.winnr ~= nil, "split opened in the current tab")
H.eq(#vim.api.nvim_list_tabpages(), 1, "split did not create a tabpage")

vim.cmd("tabnew")
H.pump(60)
H.ok(state.winnr == nil, "winnr is nil'd on a tab without a dap-view window (upstream behaviour)")

vim.cmd("tabclose")
H.pump(60)
H.ok(state.winnr ~= nil, "winnr is retracked when returning to the dap-view tab")
H.done()
