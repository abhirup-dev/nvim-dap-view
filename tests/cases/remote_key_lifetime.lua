-- Real owned PTY viewers, with only key dispatch scheduling held at the race.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local jobs = {}
local remote = require("dap-view.host.remote")
local host = require("dap-view.host")
local state = require("dap-view.state")
local schedule = vim.schedule
local win_call = vim.api.nvim_win_call
local function queued_key()
    local callback
    vim.schedule = function(fn)
        assert(not callback, "one key dispatch")
        callback = fn
    end
    remote.on_key("X", 1)
    vim.schedule = schedule
    return assert(callback)
end
local ok, err = xpcall(function()
    H.setup({
        host = {
            default = os.getenv("HOST") or "split",
            remote = {
                multiplexer = "custom",
                spawn = function(cmd)
                    local job = vim.fn.jobstart(cmd, { pty = true, width = 100, height = 30 })
                    assert(job > 0)
                    jobs[#jobs + 1] = job
                    return tostring(job)
                end,
                close = function(handle)
                    pcall(vim.fn.jobstop, tonumber(handle))
                end,
            },
        },
    })
    H.install_session(nil)
    require("dap-view").open()
    H.pump(30)
    host.switch("remote")
    assert(remote.is_open(), "real viewer attached")
    local hits = 0
    vim.keymap.set("n", "X", function()
        hits = hits + 1
    end, { buffer = state.bufnr })
    queued_key()()
    H.eq(hits, 1, "current viewer forwards mapped key")
    local old = queued_key()
    host.switch("tab")
    old()
    H.eq(hits, 1, "queued remote key cannot execute in docked tab")
    host.switch("remote")
    local closed = queued_key()
    remote.close()
    closed()
    H.eq(hits, 1, "queued key after close has no side effect")
    -- Reopen the same host and buffer: old and new callbacks must diverge.
    host.switch("remote", { reopen = true })
    assert(remote.is_open(), "replacement viewer attached")
    local current = queued_key()
    closed()
    current()
    H.eq(hits, 2, "old key rejected and new key accepted after reopen")
    -- Simulate channel/window identity reuse without relying on OS allocator
    -- timing. A lifetime token must still reject the callback from before close.
    local function upvalue(fn, name)
        for i = 1, 100 do
            local key, value = debug.getupvalue(fn, i)
            if not key then
                break
            end
            if key == name then
                return i, value
            end
        end
        error("missing captured identity: " .. name)
    end
    local reused = queued_key()
    local _, old_guard = upvalue(reused, "valid")
    host.switch("remote")
    local fresh = queued_key()
    local _, new_guard = upvalue(fresh, "valid")
    -- Simulate the allocator reusing every numeric/resource identity, while
    -- retaining the old lifetime. The live resources stay intact for cleanup.
    for _, name in ipairs({ "channel", "window", "peer" }) do
        local index = upvalue(old_guard, name)
        local _, value = upvalue(new_guard, name)
        debug.setupvalue(old_guard, index, value)
    end
    reused()
    H.eq(hits, 2, "reused channel/window/peer identity does not revive old key")
    queued_key()()
    H.eq(hits, 3, "new key remains usable after identity reuse probe")
    local interrupted = queued_key()
    vim.api.nvim_win_call = function(_, callback)
        vim.api.nvim_win_call = win_call
        host.switch("tab")
        callback()
    end
    interrupted()
    H.eq(hits, 3, "host replacement at mapping invocation rejects old key")
    host.switch("remote")
    queued_key()()
    H.eq(hits, 4, "replacement accepts fresh keys after interrupted dispatch")
end, debug.traceback)
vim.schedule = schedule
vim.api.nvim_win_call = win_call
pcall(remote.close)
pcall(function()
    host.get().close(true)
end)
for _, job in ipairs(jobs) do
    pcall(vim.fn.jobstop, job)
end
if not ok then
    H.ok(false, "fixture completed", err)
end
H.done()
