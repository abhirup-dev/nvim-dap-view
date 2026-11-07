-- Isolated Lua debuggee; nvim --headless -u lua-target.lua --listen <socket>. 2026-11-07.
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/deps/osv")
local server = assert(
    require("osv").launch({ host = "127.0.0.1", port = 0, delay_frozen = 30, output = false, break_on_exception = true })
)
vim.fn.writefile({ vim.json.encode(server) }, "/tmp/nvim-dap-live-demo/lua-server.json")
