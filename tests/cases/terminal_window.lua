local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"
-- No "console" section, so the terminal gets a window of its own, placed by
-- `windows.terminal.position`. This is upstream's default
local sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl" }

H.setup({
    host = { default = host_name },
    winbar = { sections = sections, default_section = "scopes" },
    windows = { size = 0.3, position = "below", terminal = { position = "right", size = 0.4 } },
})

local term_buf = H.make_term_buf()
local fake = H.new_fake_session({ term_buf = term_buf })
H.install_session(fake)

H.group(("host=%s console-section=%s"):format(host_name, tostring(sections[#sections] == "console")))
require("dap-view").open()
H.pump(200)

local has_console = vim.tbl_contains(sections, "console")
if has_console then
    H.ok(state.term_winnr == nil, "no separate terminal window when 'console' is a section", tostring(state.term_winnr))
else
    H.ok(
        state.term_winnr ~= nil and vim.api.nvim_win_is_valid(state.term_winnr),
        "separate terminal window opened",
        tostring(state.term_winnr)
    )
    if state.term_winnr then
        H.ok(
            vim.api.nvim_win_get_tabpage(state.term_winnr) == vim.api.nvim_win_get_tabpage(state.winnr),
            "terminal shares the dap-view tabpage"
        )
        local dv = vim.api.nvim_win_get_position(state.winnr)
        local tw = vim.api.nvim_win_get_position(state.term_winnr)
        H.ok(
            tw[2] > dv[2],
            "terminal sits to the right of the view (windows.terminal.position)",
            ("view col %d, term col %d"):format(dv[2], tw[2])
        )
    end
end

if has_console then
    H.group("console section")
    require("dap-view").show_view("console")
    H.pump(200)
    H.eq(state.current_section, "console", "current section is console")
    H.eq(vim.api.nvim_win_get_buf(state.winnr), term_buf, "console switched the view window into the term buffer")

    H.group("jump_to_view('console')")
    require("dap-view").jump_to_view("console")
    H.pump(150)
    H.ok(vim.api.nvim_get_current_win() == state.winnr, "console jump focuses the view window")
end

H.group("repl section")
require("dap-view").show_view("repl")
H.pump(250)
H.eq(state.current_section, "repl", "current section is repl")
local repl_buf = vim.api.nvim_win_get_buf(state.winnr)
H.ok(
    vim.api.nvim_buf_get_name(repl_buf):find("dap%-repl") ~= nil,
    "repl buffer is in the view window",
    vim.api.nvim_buf_get_name(repl_buf)
)

H.group("jump_to_view('repl')")
vim.api.nvim_set_current_win(vim.api.nvim_tabpage_list_wins(0)[1])
require("dap-view").jump_to_view("repl")
H.pump(200)
H.ok(
    vim.api.nvim_get_current_win() == state.winnr,
    "repl jump focuses the view window",
    ("cur=%s winnr=%s"):format(vim.api.nvim_get_current_win(), tostring(state.winnr))
)

H.group("close with hide_terminal")
require("dap-view").close(true)
H.pump(200)
H.ok(not state.winnr or not vim.api.nvim_win_is_valid(state.winnr), "view window gone")
H.ok(not state.term_winnr or not vim.api.nvim_win_is_valid(state.term_winnr), "terminal window gone")
H.ok(vim.api.nvim_buf_is_valid(term_buf), "terminal buffer survives")
if host_name == "tab" then
    H.eq(#vim.api.nvim_list_tabpages(), 1, "tab host tore its tabpage down")
end
H.done()
