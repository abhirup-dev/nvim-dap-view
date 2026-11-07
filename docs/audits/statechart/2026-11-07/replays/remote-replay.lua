-- Bounded nvim-dap-view lifecycle audit; 2026-11-07. Run Statechart with matching cfg/view; Lua probes require DAP_REPO and headless Neovim. No VPN.
local repo = assert(os.getenv("DAP_REPO"))
local H = dofile(repo .. "/tests/harness.lua")
local job
H.setup({
    host = {
        default = "split",
        remote = {
            multiplexer = "custom",
            spawn = function(cmd)
                job = vim.fn.jobstart(cmd, { pty = true, width = 100, height = 30 })
                assert(job > 0)
                return tostring(job)
            end,
            close = function()
                if job then
                    vim.fn.jobstop(job)
                end
            end,
        },
    },
})
H.install_session(nil)
require("dap-view").open()
H.pump(30)
local host = require("dap-view.host")
local remote = require("dap-view.host.remote")
local state = require("dap-view.state")
host.switch("remote")
assert(remote.is_open(), "ready real viewer")
print("STEP 1 real PTY viewer ready")
local hits = 0
vim.keymap.set("n", "X", function()
    hits = hits + 1
end, { buffer = state.bufnr })
-- Queue the actual owner's notification handler, then dock before its schedule.
remote.on_key("X", 1)
print("STEP 2 real handler queued")
host.switch("tab")
print("STEP 3 docked host=" .. host.name())
H.pump(100)
assert(hits == 1, "old callback did not run")
print("STEP 4 stale key applied to new tab host; hits=" .. hits)
remote.close()
host.get().close(true)
if job then
    pcall(vim.fn.jobstop, job)
end
vim.cmd("qa!")
