-- Regression: `follow_frame` must reveal the stopped line's fold.
--
-- nvim-dap runs `normal! zv` in the window *it* jumped (`session.lua`), which
-- under the tab host is not necessarily the tab's code window. Without the
-- fork's own `reveal()` the frame sits inside a closed fold, and a visual
-- selection over it spans the whole fold.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local dap = require("dap")
local host_name = os.getenv("HOST") or "tab"

H.setup({
    host = { default = host_name, tab = { layout = "code-right", follow_frame = true } },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
})

-- A real file on disk: the listener stats the path before jumping
local path = vim.fn.resolve(vim.fn.tempname() .. ".lua")
local lines = {}
for i = 1, 30 do
    table.insert(lines, ("line %d"):format(i))
end
vim.fn.writefile(lines, path)
path = vim.fn.fnamemodify(path, ":p")

local STOP_LINE = 12
local FOLD_START, FOLD_END = 10, 15

local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
fake.current_frame = { id = 11, name = "compute", line = STOP_LINE, column = 1, source = { path = path } }
fake.threads = { [1] = { id = 1, name = "main", frames = { fake.current_frame } } }
H.install_session(fake)

-- Opened before the host, so the tab host carries this buffer into its code window
vim.cmd.edit(path)
local file_buf = vim.api.nvim_get_current_buf()

require("dap-view").open()
H.pump(250)

---The window showing the source file, i.e. the tab's code window under the tab host
---@return integer?
local code_win = function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(state.winnr))) do
        if vim.api.nvim_win_get_buf(win) == file_buf then
            return win
        end
    end
end

local cw = code_win()

H.group("closed fold over the stopped line / host=" .. host_name)
H.ok(cw ~= nil, "found the window showing the source", tostring(cw))

---@param win integer
---@param line integer
local foldclosed = function(win, line)
    return vim.api.nvim_win_call(win, function()
        return vim.fn.foldclosed(line)
    end)
end

---@cast cw integer
vim.api.nvim_win_call(cw, function()
    vim.wo[cw].foldenable = true
    vim.wo[cw].foldmethod = "manual"
    vim.cmd(("%d,%dfold"):format(FOLD_START, FOLD_END))
end)

-- Negative control: without this the case could pass vacuously, since a manual
-- fold is window local and disappears if the jump lands in a different window
H.eq(foldclosed(cw, STOP_LINE), FOLD_START, "the stopped line starts inside a closed fold")

-- nvim-dap has already put the cursor on the stopped line by the time
-- `after.scopes` runs; what it has *not* necessarily done is reveal it here
vim.api.nvim_win_set_cursor(cw, { STOP_LINE, 0 })

H.group("follow_frame listeners fire / host=" .. host_name)
local before = dap.listeners.before.event_stopped["dap-view-host-tab"]
local after = dap.listeners.after.scopes["dap-view-host-tab"]

if host_name ~= "tab" then
    -- `host/tab.lua` is never `require`d under the split host, so its listeners
    -- are not even registered: revealing the fold stays nvim-dap's job, in the
    -- window it jumped itself. Nothing here drives a real `stopped`, so the fold
    -- is simply left as it was -- upstream behaviour, unchanged by the fork
    H.eq(before, nil, "the tab host's follow_frame listeners are not registered")
    H.eq(after, nil, "the tab host's scopes listener is not registered")
    H.eq(foldclosed(cw, STOP_LINE), FOLD_START, "split host left the fold alone")
    H.done()
    return
end

H.ok(before ~= nil and after ~= nil, "the tab host registered its follow_frame listeners")

local ok_before = pcall(before)
H.pump(100)
local ok_after = pcall(after, fake)
H.pump(300)

H.ok(ok_before and ok_after, "listeners ran without error")

H.eq(foldclosed(cw, STOP_LINE), -1, "the fold over the stopped line was opened")
H.eq(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(state.winnr), "stayed in the debugger tab")

H.done()
