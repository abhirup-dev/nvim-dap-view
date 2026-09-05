---Lifecycle for the Go sidecar.
---
---The binary is a child of this Neovim, connected back to it over the RPC
---socket in `v:servername`. That is the whole trick: the sidecar drives the
---very session the user is looking at, and dies with the editor.
---
---`autostart` decides when it comes up:
---  "never"       nothing happens; `:DapMcp start` still works
---  "on_session"  the first `event_initialized` starts it (the default)
---  "always"      `setup()` starts it
local M = {}

local config = require("dap-mcp.config")

---The nvim-dap listener key. Unique so a re-`setup()` replaces its own
---subscription instead of stacking a second one.
local LISTENER_KEY = "dap-mcp.sidecar.autostart"

---@class dapmcp.SidecarState
---@field handle vim.SystemObj?
---@field pid integer?
---@field url string?
---@field started_at integer?
---@field last_error string?
local state = {}

---The plugin root, three directories up from this file.
---@return string
local function plugin_root()
    local source = debug.getinfo(1, "S").source:sub(2)

    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

---Where the binary lives: `sidecar.bin` if the user set one, otherwise the
---path `make build` writes to.
---@return string
M.binary = function()
    local sidecar = config.config.sidecar or {}
    if sidecar.bin and sidecar.bin ~= "" then
        return vim.fn.expand(sidecar.bin)
    end

    return vim.fs.joinpath(plugin_root(), "bin", "nvim-dap-mcp")
end

---The RPC socket to hand the sidecar. Starting a server is harmless when one
---is already listening, but `v:servername` is empty under `nvim --headless`
---without `--listen`, and then we have to make one.
---@return string?, string? socket, error
local function servername()
    if vim.v.servername ~= nil and vim.v.servername ~= "" then
        return vim.v.servername
    end

    local ok, socket = pcall(vim.fn.serverstart)
    if not ok or socket == nil or socket == "" then
        return nil, "could not start an RPC server for the sidecar to connect to"
    end

    return socket
end

---@return boolean
M.running = function()
    return state.handle ~= nil
end

---Start the sidecar. Idempotent: a second call while one is running is a
---no-op, so `on_session` autostart survives restarting the debuggee.
---@param opts { silent: boolean? }?
---@return boolean started
M.start = function(opts)
    opts = opts or {}

    local function notify(message, level)
        if not opts.silent then
            vim.notify("dap-mcp: " .. message, level)
        end
    end

    if M.running() then
        return true
    end

    local binary = M.binary()
    if vim.fn.executable(binary) ~= 1 then
        state.last_error = ("sidecar binary not found or not executable: %s (run `make build`)"):format(binary)
        notify(state.last_error, vim.log.levels.ERROR)
        return false
    end

    local socket, err = servername()
    if not socket then
        state.last_error = err
        notify(err, vim.log.levels.ERROR)
        return false
    end

    local conf = config.config
    local cmd = {
        binary,
        "--socket",
        socket,
        "--port",
        tostring(conf.port),
        "--bind",
        conf.bind,
    }
    if conf.token and conf.token ~= "" then
        table.insert(cmd, "--token")
        table.insert(cmd, conf.token)
    end

    local started_pid = nil

    local handle = vim.system(cmd, { stderr = true }, function(result)
        vim.schedule(function()
            -- Only clear the state if this is still the process we started;
            -- a stop-then-start race must not wipe the new handle.
            if state.pid == started_pid then
                state.handle = nil
                state.pid = nil
                state.url = nil
            end

            if result.code ~= 0 and result.code ~= nil then
                state.last_error = ("sidecar exited with code %d: %s"):format(
                    result.code,
                    vim.trim(result.stderr or "")
                )
                vim.notify("dap-mcp: " .. state.last_error, vim.log.levels.WARN)
            end
        end)
    end)

    started_pid = handle.pid

    state.handle = handle
    state.pid = handle.pid
    state.url = ("http://%s:%d/mcp"):format(conf.bind, conf.port)
    state.started_at = vim.uv.now()
    state.last_error = nil

    notify(("sidecar listening on %s (pid %d)"):format(state.url, handle.pid), vim.log.levels.INFO)

    return true
end

---Stop the sidecar. SIGTERM, which the binary handles: it drains in-flight
---requests before exiting.
---@return boolean stopped
M.stop = function()
    if not M.running() then
        return false
    end

    local handle = state.handle
    state.handle = nil
    state.pid = nil
    state.url = nil

    pcall(function()
        handle:kill("sigterm")
    end)

    return true
end

---@class dapmcp.SidecarStatus
---@field running boolean
---@field pid integer?
---@field url string?
---@field binary string
---@field autostart string
---@field last_error string?

---@return dapmcp.SidecarStatus
M.status = function()
    return {
        running = M.running(),
        pid = state.pid,
        url = state.url,
        binary = M.binary(),
        autostart = config.config.autostart,
        last_error = state.last_error,
    }
end

---Wire up autostart and the shutdown hook. Called from `setup()`.
M.attach = function()
    local autostart = config.config.autostart

    local group = vim.api.nvim_create_augroup("dap-mcp.sidecar", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        desc = "Stop the nvim-dap-mcp sidecar with Neovim",
        callback = function()
            M.stop()
        end,
    })

    local ok, dap = pcall(require, "dap")
    if ok then
        -- Always clear first: a second `setup()` must replace this
        -- subscription rather than leave a stale one behind.
        dap.listeners.after.event_initialized[LISTENER_KEY] = nil

        if autostart == "on_session" then
            dap.listeners.after.event_initialized[LISTENER_KEY] = function()
                M.start({ silent = true })
            end
        end
    end

    if autostart == "always" then
        M.start({ silent = true })
    end
end

return M
