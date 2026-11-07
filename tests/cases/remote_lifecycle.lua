local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h') .. '/harness.lua')
local root = vim.fn.getcwd()
local wrapper = vim.fn.tempname() .. '.lua'
local viewer = root .. '/lua/dap-view/host/viewer.lua'
vim.fn.writefile({('vim.defer_fn(function() dofile(%q) end, 600)'):format(viewer)}, wrapper)
local job
local mux = require('dap-view.host.mux')
local adapter = {
    available = function() return true end,
    spawn = function(cmd)
        cmd = cmd:gsub(vim.pesc(vim.fn.shellescape(viewer)), function() return vim.fn.shellescape(wrapper) end)
        job = vim.fn.jobstart(cmd, { pty = true, width = 100, height = 30 })
        assert(job > 0)
        return tostring(job)
    end,
    is_alive = function() return job and vim.fn.jobwait({job}, 0)[1] == -1 end,
    close = function() if job then pcall(vim.fn.jobstop, job) end end,
}
local remote = require('dap-view.host.remote')
local host = require('dap-view.host')
local state = require('dap-view.state')
local ok, err = xpcall(function()
    H.setup({ host = { default = 'split', remote = { multiplexer = 'custom', spawn = adapter.spawn, close = adapter.close } } })
    H.install_session(H.new_fake_session({ term_buf = H.make_term_buf() }))
    require('dap-view').open()
    H.pump(100)
    local start = vim.uv.hrtime()
    host.switch('remote')
    H.ok(remote.is_open(), 'delayed real PTY viewer attaches')
    H.ok((vim.uv.hrtime() - start) / 1e6 >= 450, 'attach waited for delayed module')
    local status = remote.status()
    H.ok(vim.wait(1500, function()
        local lines = vim.rpcrequest(status.chan, 'nvim_buf_get_lines', 0, 0, -1, false)
        return vim.deep_equal(lines, vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false))
    end, 30), 'viewer mirrors contents')
    vim.rpcrequest(status.chan, 'nvim_input', 'W')
    H.ok(vim.wait(1500, function() return state.current_section == 'watches' end, 30), 'viewer forwards section action')
    vim.fn.jobstop(job)
    H.ok(vim.wait(3000, function() return host.name() == 'split' end, 30), 'dead viewer falls back')
    H.ok(not remote.is_active() and not vim.uv.fs_stat(status.sock), 'fallback cleans remote resources')
    vim.fn.writefile({"vim.g.never_ready = true"}, wrapper)
    local notices = {}
    local notify = vim.notify
    vim.notify = function(message) notices[#notices + 1] = tostring(message) end
    local before = vim.uv.hrtime()
    host.switch('remote')
    vim.notify = notify
    local elapsed = (vim.uv.hrtime() - before) / 1e9
    H.ok(elapsed >= 9 and elapsed < 13, 'never-ready viewer fails within startup deadline', elapsed)
    H.ok(host.name() == 'split' and not remote.is_active(), 'failed attach restores host and cleans resources')
    H.ok(table.concat(notices):find('did not become ready', 1, true), 'startup timeout explains failure')
end, debug.traceback)
pcall(remote.close)
if job then pcall(vim.fn.jobstop, job) end
vim.fn.delete(wrapper)
if not ok then H.ok(false, 'fixture completed', err) end
H.done()
