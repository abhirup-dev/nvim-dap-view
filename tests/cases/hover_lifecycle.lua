local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"
H.setup({ host = { default = host_name } })

-- Session whose `evaluate` returns an expandable value
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
local base_request = fake.request
fake.request = function(self, cmd, args, cb)
    if cmd == "evaluate" then
        local co = coroutine.running()
        local resp = { result = "<struct>", type = "table", variablesReference = 100 }
        if not cb then
            vim.schedule(function()
                coroutine.resume(co, nil, resp)
            end)
            return coroutine.yield()
        end
        vim.schedule(function()
            cb(nil, resp)
        end)
        return
    end
    return base_request(self, cmd, args, cb)
end
H.install_session(fake)

local code = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(code, 0, -1, false, { "local myvar = 1", "print(myvar)" })

require("dap-view").open()
H.pump(150)

local code_win
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= state.winnr and not vim.wo[w].winfixbuf then
        code_win = w
    end
end
if not code_win then
    -- The split host opened beside the only window; make one to hover from
    code_win = vim.api.nvim_open_win(code, false, { split = "above", win = state.winnr })
end
vim.api.nvim_win_set_buf(code_win, code)
vim.api.nvim_set_current_win(code_win)
vim.api.nvim_win_set_cursor(code_win, { 1, 6 })

H.group("hover normal mode / host=" .. host_name)
require("dap-view").hover(nil, true)
H.pump(300)
H.ok(state.hover_winnr and vim.api.nvim_win_is_valid(state.hover_winnr), "float open")
H.eq(state.hover, "myvar", "evaluated the cexpr under the cursor")
local lines = vim.api.nvim_buf_get_lines(state.hover_bufnr, 0, -1, false)
print("    " .. vim.inspect(lines))
H.ok(#lines > 1, "expandable hover renders children by default", vim.inspect(lines))

H.group("hover keymaps")
local hb = state.hover_bufnr
local maps = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(hb, "n")) do
    maps[m.lhs] = true
end
for _, k in ipairs({ "q", "<CR>", "[[", "s" }) do
    H.ok(maps[k], "hover keymap " .. k .. " is set")
end

H.group("leaving the float cleans up")
vim.api.nvim_set_current_win(code_win)
H.pump(100)
H.ok(state.hover_winnr == nil, "BufLeave cleared hover state", "hover_winnr=" .. tostring(state.hover_winnr))

H.group("hover with an explicit expression and no session")
H.install_session(nil)
require("dap-view").hover("whatever", true)
H.pump(200)
H.ok(state.hover_winnr and vim.api.nvim_win_is_valid(state.hover_winnr), "no-session float open")
H.eq(vim.api.nvim_buf_get_lines(state.hover_bufnr, 0, -1, false), { "No active session" }, "no-session message")
H.done()
