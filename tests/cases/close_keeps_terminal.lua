-- `:DapViewClose` (no bang) keeps the terminal window visible; `:DapViewClose!`
-- hides it. The tab host used to be unable to honour the first, because closing
-- its tabpage took the terminal window with it.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"

-- No "console" section, so the terminal gets a window of its own
H.setup({
    host = { default = host_name },
    winbar = {
        sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl" },
        default_section = "scopes",
    },
    windows = { size = 0.3, position = "below", terminal = { position = "right", size = 0.4 } },
})

local term_buf = H.make_term_buf()
H.install_session(H.new_fake_session({ term_buf = term_buf }))

---Every window showing `term_buf`, across every tabpage
---@return integer[]
local term_wins = function()
    local found = {}
    for _, page in ipairs(vim.api.nvim_list_tabpages()) do
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(page)) do
            if vim.api.nvim_win_get_buf(win) == term_buf then
                table.insert(found, win)
            end
        end
    end
    return found
end

H.group("close(false) / host=" .. host_name)
local origin = vim.api.nvim_get_current_tabpage()
require("dap-view").open()
H.pump(200)
H.ok(state.term_winnr ~= nil and vim.api.nvim_win_is_valid(state.term_winnr), "terminal window opened")

local cap = math.floor(vim.go.lines * 0.4)

require("dap-view").close(false)
H.pump(200)

H.ok(not state.winnr or not vim.api.nvim_win_is_valid(state.winnr), "view window gone")
H.eq(#term_wins(), 1, "exactly one window still shows the terminal buffer")
H.ok(
    state.term_winnr ~= nil and vim.api.nvim_win_is_valid(state.term_winnr),
    "the surviving terminal window is tracked",
    tostring(state.term_winnr)
)

if host_name == "tab" then
    H.eq(#vim.api.nvim_list_tabpages(), 1, "the debugger tabpage is gone")
    H.eq(vim.api.nvim_win_get_tabpage(state.term_winnr), origin, "terminal moved to the origin tabpage")
    local h = vim.api.nvim_win_get_height(state.term_winnr)
    H.ok(h >= 1 and h <= cap, ("relocated height %d is within 1..%d (40%% of the tabpage)"):format(h, cap))
else
    -- Upstream: the split host never closed the terminal window in the first
    -- place, so it is still exactly where `open_term_buf_win` put it
    H.eq(state.term_winnr, term_wins()[1], "split host left the terminal window untouched")
end

H.group("reopen adopts rather than duplicates")
require("dap-view").open()
H.pump(200)
H.eq(#term_wins(), 1, "still exactly one terminal window after reopening")
if host_name == "tab" then
    H.eq(
        vim.api.nvim_win_get_tabpage(state.term_winnr),
        vim.api.nvim_win_get_tabpage(state.winnr),
        "the terminal is back in the debugger tabpage"
    )
end

H.group("close(true) hides it everywhere")
require("dap-view").close(true)
H.pump(200)
H.eq(#term_wins(), 0, "no window shows the terminal buffer")
H.ok(vim.api.nvim_buf_is_valid(term_buf), "terminal buffer survives")
H.ok(not state.term_winnr or not vim.api.nvim_win_is_valid(state.term_winnr), "no terminal window is tracked")
if host_name == "tab" then
    H.eq(#vim.api.nvim_list_tabpages(), 1, "tab host tore its tabpage down")
end

H.done()
