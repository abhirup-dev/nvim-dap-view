local setup = require("dap-view.setup")

local M = {}

---A multiplexer adapter knows how to put a shell command somewhere visible and
---how to take it away again. It knows nothing about dap-view, Neovim or RPC: the
---remote host hands it a command string and keeps the opaque handle it returns.
---
---`is_alive` is a *secondary* signal. The remote host learns about a dead viewer
---from its RPC channel, which costs nothing; asking the multiplexer means
---spawning a process, so it is only used where being wrong is expensive.
---@class dapview.Mux
---@field available fun(): boolean Binary present and, where it matters, we are inside it
---@field spawn fun(cmd: string, opts: dapview.MuxSpawnOpts): string|nil Opaque handle, usually a pane id
---@field close fun(handle: string)
---@field is_alive fun(handle: string): boolean

---@class dapview.MuxSpawnOpts
---@field kind "split"|"tab"
---@field direction "right"|"down"|"left"|"up"
---@field size number Fraction of the parent when below 1, cells otherwise
---@field cwd string
---@field label string

---@alias dapview.MuxName "herdr"|"tmux"|"custom"

---@type table<string, string>
local modules = {
    herdr = "dap-view.host.mux.herdr",
    tmux = "dap-view.host.mux.tmux",
    custom = "dap-view.host.mux.custom",
}

---@type dapview.MuxName[]
M.names = vim.tbl_keys(modules)

table.sort(M.names)

---@param name string
---@return dapview.Mux
M.resolve = function(name)
    if not modules[name] then
        error("Unknown multiplexer: " .. tostring(name))
    end

    return require(modules[name])
end

---@return dapview.Mux
M.get = function()
    return M.resolve(setup.config.host.remote.multiplexer)
end

---Spawn options for the configured pane, resolved against the current editor
---@return dapview.MuxSpawnOpts
M.spawn_opts = function()
    local pane = setup.config.host.remote.pane

    return {
        kind = pane.kind,
        direction = pane.direction,
        size = pane.size,
        cwd = vim.fn.getcwd(),
        label = pane.label,
    }
end

---@param cmd string[]
---@return string? stdout, string? err
M.run = function(cmd)
    local ok, result = pcall(function()
        return vim.system(cmd, { text = true }):wait()
    end)

    if not ok then
        return nil, tostring(result)
    end

    if result.code ~= 0 then
        local err = (result.stderr ~= "" and result.stderr) or result.stdout or ""
        return nil, vim.trim(err) ~= "" and vim.trim(err) or ("exit code " .. result.code)
    end

    return result.stdout
end

---@param cmd string[]
---@return boolean
M.succeeds = function(cmd)
    return (select(1, M.run(cmd))) ~= nil
end

return M
