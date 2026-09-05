local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"
H.setup({
    host = { default = host_name },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
    switchbuf = "usetab,uselast",
})

-- A real file on disk, since jump_to_location stats the path
local path = vim.fn.resolve(vim.fn.tempname() .. ".lua")
vim.fn.writefile({ "line one", "line two", "line three", "line four" }, path)
path = vim.fn.fnamemodify(path, ":p")

local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
fake.current_frame = { id = 11, name = "compute", line = 3, column = 1, source = { path = path } }
fake.threads = { [1] = { id = 1, name = "main", frames = { fake.current_frame } } }
H.install_session(fake)

vim.cmd.edit(path)
vim.cmd("vsplit")
require("dap-view").open()
H.pump(250)

H.group("breakpoint jump respects switchbuf / host=" .. host_name)
require("dap").toggle_breakpoint(nil, nil, nil, true)
H.pump(150)
require("dap-view").show_view("breakpoints")
H.pump(250)
local blines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
print("    breakpoints: " .. vim.inspect(blines))
H.ok(blines[1] and blines[1] ~= "" and not blines[1]:find("No breakpoints"), "breakpoints view lists the breakpoint")

vim.api.nvim_set_current_win(state.winnr)
vim.api.nvim_win_set_cursor(state.winnr, { 1, 0 })
local before_win = state.winnr
require("dap-view.breakpoints.actions").jump(1)
H.pump(250)
local cur = vim.api.nvim_get_current_win()
H.ok(cur ~= before_win, "jump left the dap-view window", ("cur=%s view=%s"):format(cur, tostring(before_win)))
H.ok(
    vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cur)) == path,
    "landed in the source buffer",
    vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cur))
)
H.ok(vim.wo[cur].winfixbuf ~= true, "target window is not winfixbuf")
if host_name == "tab" then
    H.eq(
        vim.api.nvim_win_get_tabpage(cur),
        vim.api.nvim_win_get_tabpage(state.winnr),
        "tab host jumped inside its own tabpage"
    )
end

H.group("thread/frame jump")
require("dap-view").show_view("threads")
H.pump(250)
local tlines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
print("    threads: " .. vim.inspect(tlines))
H.ok(#tlines > 1, "threads view lists frames")
H.done()
