local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"
H.setup({
    host = { default = host_name },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
    tree = { max_value_width = "auto", indent_width = 2 },
})

local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
-- One very long value, so clamping is observable
local base = fake.request
fake.request = function(self, cmd, args, cb)
    if cmd == "variables" and args.variablesReference == 100 then
        local vars = {
            { name = "long", value = ("y"):rep(400), type = "string", variablesReference = 0 },
            { name = "nested", value = "<struct>", type = "table", variablesReference = 101 },
        }
        local co = coroutine.running()
        if not cb then
            vim.schedule(function()
                coroutine.resume(co, nil, { variables = vars })
            end)
            return coroutine.yield()
        end
        vim.schedule(function()
            cb(nil, { variables = vars })
        end)
        return
    end
    if cmd == "variables" and args.variablesReference == 101 then
        local vars = { { name = "deep", value = ("z"):rep(200), type = "string", variablesReference = 0 } }
        local co = coroutine.running()
        if not cb then
            vim.schedule(function()
                coroutine.resume(co, nil, { variables = vars })
            end)
            return coroutine.yield()
        end
        vim.schedule(function()
            cb(nil, { variables = vars })
        end)
        return
    end
    return base(self, cmd, args, cb)
end
fake.current_frame = {
    id = 11,
    name = "compute",
    line = 12,
    column = 3,
    source = { path = nil },
    scopes = { { name = "Locals", variablesReference = 100 } },
}
H.install_session(fake)

H.group("scopes tree with max_value_width='auto' / host=" .. host_name)
require("dap-view").open()
H.pump(300)
require("dap-view").show_view("scopes")
H.pump(400)
local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
print("    " .. vim.inspect(lines))
H.ok(#lines >= 2, "scopes rendered")
local width = vim.api.nvim_win_get_width(state.winnr)
-- Measure inside the window, so the buffer local `tabstop` applies to the indent
local longest = vim.api.nvim_win_call(state.winnr, function()
    local max = 0
    for i = 1, vim.api.nvim_buf_line_count(state.bufnr) do
        max = math.max(max, vim.fn.virtcol({ i, "$" }) - 1)
    end
    return max
end)
local textoff = require("dap-view.util.truncate").text_width(state.winnr)
-- `"auto"` never squeezes the value below `MIN_AUTO_WIDTH` (10 cells), so in a
-- window this narrow a short value can still push past the text area. Assert the
-- clamp is doing its job, not that nothing can ever overflow the floor
H.ok(
    longest <= math.max(textoff, 22),
    "clamped lines stay near the text area",
    ("longest=%d text_width=%d win_width=%d"):format(longest, textoff, width)
)
H.ok(
    vim.tbl_contains(
        vim.tbl_map(function(l)
            return l:find("…") ~= nil
        end, lines),
        true
    ),
    "a value was clamped with the ellipsis"
)

H.group("buffer-local tree options")
H.eq(vim.bo[state.bufnr].tabstop, 2, "tree.indent_width set tabstop")
H.eq(vim.wo[state.winnr][0].foldmethod, "indent", "tree.fold set foldmethod")

H.group("show_value float (K)")
vim.api.nvim_set_current_win(state.winnr)
vim.api.nvim_win_set_cursor(state.winnr, { math.min(2, vim.api.nvim_buf_line_count(state.bufnr)), 0 })
local ok, err = pcall(function()
    require("dap-view.tree.value").show(2)
end)
H.pump(200)
H.ok(ok, "show_value did not throw", err)
local floats = {}
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
        table.insert(floats, w)
    end
end
H.ok(#floats > 0, "show_value opened a float")
if #floats > 0 then
    local fl = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(floats[1]), 0, -1, false)
    H.ok(table.concat(fl, ""):find("yyyy") ~= nil, "float shows the untruncated value", vim.inspect(fl):sub(1, 80))
    vim.api.nvim_win_close(floats[1], true)
end

H.group("reroot")
vim.api.nvim_set_current_win(state.winnr)
vim.api.nvim_win_set_cursor(state.winnr, { 1, 0 })
local ok2, err2 = pcall(function()
    require("dap-view").reroot(1)
end)
H.pump(300)
H.ok(ok2, "reroot did not throw", err2)
local ok3, err3 = pcall(function()
    require("dap-view").root_up()
end)
H.pump(300)
H.ok(ok3, "root_up did not throw", err3)
H.done()
