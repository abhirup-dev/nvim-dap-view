local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")

local state = require("dap-view.state")
H.setup({ host = { default = os.getenv("HOST") or "tab" } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)
require("dap-view").open()
H.pump(100)
state.current_section = "watches"
require("dap-view.util").set_lines(state.bufnr, 0, -1, false, { "other", "my_watch", "child", "synthetic" })
state.line_to_variable_path[2] = "Locals.a"
state.variable_path_to_evaluate_name["Locals.a"] = "unrelated"
state.expression_views_by_line = { [2] = { expression = "my_watch", view = {} } }
state.variable_views_by_line = {
    [3] = { view = { variable = { evaluateName = "my_watch.child" } } },
    [4] = { view = { variable = { name = "decoded" } } },
}
local function hover(line, explicit, expected)
    vim.api.nvim_set_current_win(state.winnr)
    vim.api.nvim_win_set_cursor(state.winnr, { line, 0 })
    fake.received = {}
    require("dap-view").hover(explicit, true)
    H.pump(100)
    local expression
    for _, r in ipairs(fake.received) do
        if r.command == "evaluate" then
            expression = r.arguments.expression
        end
    end
    H.eq(expression, expected, "hover dispatch line " .. line)
    if state.hover_winnr then
        vim.api.nvim_win_close(state.hover_winnr, true)
    end
    H.pump(20)
end
hover(2, nil, "my_watch")
hover(3, nil, "my_watch.child")
hover(4, nil, nil)
hover(2, "explicit + expr", "explicit + expr")
H.done()
