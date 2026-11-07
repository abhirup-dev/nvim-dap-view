-- A restored vim session must not leave the debugger's tabpage behind as a husk
-- next to the one `load_session_hook` then opens.
--
-- This case mirrors a real 'sessionoptions' -- the one QA reproduced against:
--
--     buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds
--
-- Under it `:mksession` records *no* dap buffer at all. `buffers` only saves
-- listed buffers, and dap-view://main, dap-repl and dap-terminal are all
-- unlisted; the dap-view window is showing the (nofile) main buffer rather than
-- the repl, so the window layout does not name one either. The buffer-based rule
-- in `load_session_hook` therefore has nothing to fire on -- which is why the tab
-- host leaves a marker in `g:DapviewTabpage`, restored because `globals` is in
-- the list. `session_restore_buffers.lua` covers the fallback.
local harness = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua"
local H = dofile(harness)
local globals = require("dap-view.globals")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"

local SESSIONOPTIONS = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds"

local path = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.tempname() .. ".lua"), ":p")
vim.fn.writefile({ "line one", "line two", "line three" }, path)

local session_file = vim.fn.tempname() .. ".vim"
local writer = vim.fn.tempname() .. ".lua"

vim.fn.writefile(
    vim.split(
        ([[
local H = dofile(%q)
H.setup({
    host = { default = %q },
    winbar = { sections = { "scopes", "repl" }, default_section = "scopes" },
})
vim.o.sessionoptions = %q
vim.cmd.edit(%q)
H.install_session(H.new_fake_session({ term_buf = H.make_term_buf() }))
require("dap-view").open()
H.pump(300)
vim.cmd("mksession! " .. %q)
vim.cmd("qa!")
]]):format(harness, host_name, SESSIONOPTIONS, path, session_file),
        "\n"
    ),
    writer
)

local res = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", writer }, { text = true }):wait()

H.group("write the session / host=" .. host_name)
H.ok(vim.fn.filereadable(session_file) == 1, "child Neovim wrote a session file", res.stderr)

local recorded = table.concat(vim.fn.readfile(session_file), "\n")

H.ok(recorded:find("dap%-repl") == nil, "the session records no repl buffer")
H.ok(recorded:find("dap%-terminal") == nil, "the session records no terminal buffer")
H.ok(
    recorded:find(globals.MAIN_BUF_NAME, 1, true) == nil,
    "the session does not record the dap-view buffer (unlisted + nofile)"
)

if host_name == "tab" then
    H.ok(recorded:find("DapviewTabpage") ~= nil, "the session records the tab host's marker global", recorded)
else
    H.ok(recorded:find("DapviewTabpage") == nil, "the split host owns no tabpage, so it leaves no marker")
end

vim.o.sessionoptions = SESSIONOPTIONS

H.setup({
    host = { default = host_name },
    winbar = { sections = { "scopes", "repl" }, default_section = "scopes" },
})

H.group("restore / host=" .. host_name)
vim.cmd("source " .. session_file)
H.pump(500)

---@return integer[]
local husks = function()
    local found = {}
    for _, page in ipairs(vim.api.nvim_list_tabpages()) do
        local has_view = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(page)) do
            if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == globals.MAIN_BUF_NAME then
                has_view = true
            end
        end
        if not has_view then
            table.insert(found, page)
        end
    end
    return found
end

H.ok(vim.api.nvim_tabpage_is_valid(vim.api.nvim_get_current_tabpage()), "we are on a valid tabpage")

if host_name == "tab" then
    H.ok(
        state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr),
        "the marker brought the hook to life and it reopened the view",
        tostring(state.winnr)
    )

    -- Origin tabpage plus the one the hook just opened. The third -- the
    -- debugger tabpage the restore rebuilt, code window and all -- is reclaimed
    H.eq(#vim.api.nvim_list_tabpages(), 2, "no husk left next to the reopened debugger tabpage")
    H.eq(#husks(), 1, "exactly one tabpage without a dap-view window: the user's own")
    local view_tabpage = state.winnr
        and vim.api.nvim_win_is_valid(state.winnr)
        and vim.api.nvim_win_get_tabpage(state.winnr)

    H.eq(view_tabpage, vim.api.nvim_get_current_tabpage(), "the tab host landed us in its own tabpage")

    -- Consumed by the hook, then re-set by the `open` it scheduled: what must not
    -- survive is the *restored* number, which by now points at a tabpage that is
    -- gone. It has to describe the tabpage that is there now
    H.eq(
        vim.g.DapviewTabpage,
        view_tabpage and vim.api.nvim_tabpage_get_number(view_tabpage),
        "the marker describes the tabpage the hook opened, not the one it reclaimed"
    )
else
    -- The split host's rule is the buffer-based one and this 'sessionoptions'
    -- records no dap buffer, so there is nothing for it to reclaim or reopen.
    -- `session_restore_buffers.lua` covers the case where there is
    H.eq(#vim.api.nvim_list_tabpages(), 1, "split host restored into one tabpage, untouched")
    H.ok(
        state.winnr == nil or not vim.api.nvim_win_is_valid(state.winnr),
        "nothing in the session points at the debugger, so the hook stays out of it"
    )
end

H.done()
