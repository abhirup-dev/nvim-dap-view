local setup = require("dap-view.setup")

---Escape hatch adapter: whatever the user configured under `host.remote`.
---
---`spawn` is the only required half. A `spawn` that manages its own process and
---has nothing to hand back may return nothing, in which case `close` and
---`is_alive` have nothing to work with and the remote host falls back to the RPC
---channel alone, which is all it really needs.
---@type dapview.Mux
local M = {}

M.available = function()
    return setup.config.host.remote.spawn ~= nil
end

---@param cmd string
---@param opts dapview.MuxSpawnOpts
---@return string?
M.spawn = function(cmd, opts)
    local spawn = setup.config.host.remote.spawn

    if not spawn then
        error("host.remote.multiplexer is 'custom' but host.remote.spawn is not set")
    end

    local handle = spawn(cmd, opts)

    return handle ~= nil and tostring(handle) or nil
end

---@param handle string
M.close = function(handle)
    local close = setup.config.host.remote.close

    if close then
        close(handle)
    end
end

---Without a user supplied `close` there is nothing to ask, so claim liveness and
---let the channel be the judge
---@param _ string
M.is_alive = function(_)
    return true
end

return M
