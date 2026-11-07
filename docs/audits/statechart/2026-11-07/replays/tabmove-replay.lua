-- Session writer/reader: tabmove -> save -> restore -> scheduled ownership cleanup.
local repo = assert(os.getenv("DAP_REPO"))
local H = dofile(repo .. "/tests/harness.lua")
local dir = os.getenv("AUDIT_OUTPUT") or vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local sessionfile = dir .. "/moved-session.vim"
local path = dir .. "/user-buffer.lua"
vim.fn.writefile({ "local user = true" }, path)
local writer = dir .. "/tabmove-writer.lua"
vim.fn.writefile(
    vim.split(
        ([[
local H=dofile(%q..'/tests/harness.lua');H.setup({host={default='tab'}})
vim.o.sessionoptions='buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds'
vim.cmd.edit(%q)
require('dap-view').open();H.pump(30)
vim.cmd('tabmove 0')
print('STEP 1 reorder actual='..vim.api.nvim_tabpage_get_number(vim.api.nvim_get_current_tabpage())..' marker='..vim.g.DapviewTabpage)
vim.cmd('mksession! '..%q)
print('STEP 2 saved stale marker')
vim.cmd('qa!')
]]):format(repo, path, sessionfile),
        "\n"
    ),
    writer
)
local r = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", writer }, { text = true }):wait()
assert(r.code == 0, r.stderr)
io.write(r.stderr or "")
H.setup({ host = { default = "tab" } })
-- Intercept scheduling only to expose the exact Restore and Close model steps.
local schedule = vim.schedule
local tasks = {}
vim.schedule = function(f)
    tasks[#tasks + 1] = f
end
vim.cmd("source " .. sessionfile)
vim.schedule = schedule
local pages = vim.api.nvim_list_tabpages()
assert(#pages == 2)
local user = pages[2]
print("STEP 3 restored tabs=" .. #pages .. " unrelated_user_tab=" .. user)
for _, f in ipairs(tasks) do
    f()
end
H.pump(100)
print("STEP 4 unrelated_user_tab_valid=" .. tostring(vim.api.nvim_tabpage_is_valid(user)))
assert(not vim.api.nvim_tabpage_is_valid(user), "expected user-tab loss did not reproduce")
vim.cmd("qa!")
