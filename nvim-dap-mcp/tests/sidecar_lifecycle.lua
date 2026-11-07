local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local config = require('dap-mcp.config')
local sidecar = require('dap-mcp.sidecar')
local binary = assert(vim.env.DAP_MCP_TEST_BINARY)
local listener = assert(vim.uv.new_tcp())
assert(listener:bind('127.0.0.1', 0))
assert(listener:listen(16, function() end))
local port = listener:getsockname().port
local function check(value, message) assert(value, message) print('  ok ' .. message) end
local ok, err = xpcall(function()
    config.setup({ port = port, autostart = 'never', sidecar = { bin = binary } })
    check(not sidecar.start({ silent = true }), 'occupied port fails')
    local status = sidecar.status()
    check(not status.running and not status.url and not status.pid, 'failed startup claims no process or URL')
    check(status.last_error and status.last_error:find('address already in use', 1, true), 'reports bind error: ' .. tostring(status.last_error))
    listener:close()
    check(sidecar.start({ silent = true }), 'starts after port released')
    check(sidecar.stop(), 'stops')
    check(sidecar.start({ silent = true }), 'immediate restart succeeds')
    local pid = sidecar.status().pid
    vim.wait(200)
    check(sidecar.running() and sidecar.status().pid == pid, 'old callback preserves new process')
    sidecar.stop()
    config.config.sidecar.bin = '/bin/false'
    local start = vim.uv.hrtime()
    check(not sidecar.start({ silent = true }), 'early exit fails')
    check((vim.uv.hrtime() - start) / 1e9 < 4, 'early exit is bounded')
end, debug.traceback)
sidecar.stop()
if not listener:is_closing() then listener:close() end
if not ok then error(err) end
vim.cmd('qa!')
