-- A restored vim session must not leave the debugger's tabpage behind as a husk
-- next to the one `load_session_hook` then opens.
--
-- The round trip is real, not synthesised: a child Neovim opens the host and
-- writes a session file, and this one sources it so `SessionLoadPost` fires.
-- Worth noting what `:mksession` actually records -- the dap-view buffer is
-- unlisted and `nofile`, so it is *not* in the session file at all; what brings
-- the hook to life is the repl buffer, restored by name via `file \[dap-repl-N]`.
local harness = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua"
local H = dofile(harness)
local globals = require("dap-view.globals")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"

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
vim.cmd.edit(%q)
H.install_session(H.new_fake_session({ term_buf = H.make_term_buf() }))
require("dap-view").open()
H.pump(200)
require("dap-view").show_view("repl")
H.pump(300)
vim.cmd("mksession! " .. %q)
vim.cmd("qa!")
]]):format(harness, host_name, path, session_file),
        "\n"
    ),
    writer
)

local res = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", writer }, { text = true }):wait()

H.group("write the session / host=" .. host_name)
H.ok(vim.fn.filereadable(session_file) == 1, "child Neovim wrote a session file", res.stderr)

local recorded = table.concat(vim.fn.readfile(session_file), "\n")
H.ok(recorded:find("dap%-repl") ~= nil, "the session records the repl buffer, which is what triggers the hook")
H.ok(
    recorded:find(globals.MAIN_BUF_NAME, 1, true) == nil,
    "the session does not record the dap-view buffer (unlisted + nofile)"
)

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

H.ok(state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr), "the hook reopened the view", tostring(state.winnr))
H.ok(vim.api.nvim_tabpage_is_valid(vim.api.nvim_get_current_tabpage()), "we are on a valid tabpage")

if host_name == "tab" then
    -- Origin tabpage plus the one the hook just opened. The third -- the
    -- debugger tabpage the restore rebuilt, code window and all -- is reclaimed
    H.eq(#vim.api.nvim_list_tabpages(), 2, "no husk left next to the reopened debugger tabpage")
    H.eq(#husks(), 1, "exactly one tabpage without a dap-view window: the user's own")
    H.eq(
        vim.api.nvim_win_get_tabpage(state.winnr),
        vim.api.nvim_get_current_tabpage(),
        "the tab host landed us in its own tabpage"
    )
else
    -- Upstream: the split's tabpage is the user's, and it still holds the user's
    -- own code window, so the narrow rule leaves it alone. The session recorded
    -- a single tabpage and a single tabpage is what we get back
    H.eq(#vim.api.nvim_list_tabpages(), 1, "split host restored into one tabpage, untouched")
    H.eq(#husks(), 0, "the dap-view window is in it")
end

H.done()
