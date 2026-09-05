-- The dap-view window must stay reachable while the user is on another tabpage
-- (tab host), while the split host keeps upstream's nil-and-retrack behaviour.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"

H.setup({
    host = { default = host_name },
    winbar = {
        sections = { "scopes", "watches", "breakpoints", "threads", "exceptions", "repl", "console" },
        default_section = "scopes",
    },
})

local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)

H.group("leaving the dap-view tabpage / host=" .. host_name)

local origin = vim.api.nvim_get_current_tabpage()

require("dap-view").open()
H.pump(200)

H.ok(state.winnr ~= nil, "winnr set right after open")

if host_name == "tab" then
    vim.api.nvim_set_current_tabpage(origin)
else
    vim.cmd("tabnew")
end
H.pump(100)

if host_name == "tab" then
    H.ok(state.winnr ~= nil, "winnr survives leaving the dap-view tabpage", tostring(state.winnr))
    H.ok(require("dap-view.host").get().is_open(), "the host still reports open")

    H.group("callers that need state.winnr from another tabpage")

    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
        table.insert(notified, msg)
    end

    require("dap-view").jump_to_view("watches")
    H.pump(100)
    require("dap-view").show_view("threads")
    H.pump(100)
    require("dap-view").navigate({ wrap = true, count = 1 })
    H.pump(100)

    vim.notify = orig_notify

    H.eq(notified, {}, "no 'couldn't find the window' notifications")
else
    -- Upstream nils `state.winnr` on a tabpage without a dap-view window, and
    -- relies on that to clean up the leftover split. Do not "fix" this
    H.ok(state.winnr == nil, "winnr is nil'd on a foreign tab (upstream behaviour)")

    vim.cmd("tabclose")
    H.pump(100)

    H.ok(state.winnr ~= nil, "winnr is retracked on return")
end

H.done()
