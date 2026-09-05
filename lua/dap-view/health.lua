local health = vim.health

local M = {}

---@param cmd string[]
---@return string?
local version_of = function(cmd)
    local out = require("dap-view.host.mux").run(cmd)

    return out and vim.trim(vim.split(out, "\n", { plain = true })[1] or "") or nil
end

local check_core = function()
    health.start("dap-view: core")

    local v = vim.version()
    local version = string.format("%d.%d.%d", v.major, v.minor, v.patch)

    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim " .. version)
    else
        health.error("Neovim " .. version .. " is too old, dap-view needs 0.10 or newer")
    end

    if pcall(require, "dap") then
        health.ok("nvim-dap is installed")
    else
        health.error("nvim-dap is not on the runtimepath", "Install mfussenegger/nvim-dap")
    end
end

local check_config = function()
    local config = require("dap-view.setup").config
    local host = require("dap-view.host")

    health.start("dap-view: configuration")

    if vim.tbl_contains(host.names, config.host.default) then
        health.ok("host.default = " .. config.host.default)
    else
        health.error("host.default = " .. vim.inspect(config.host.default) .. " is not a known host")
    end

    health.info("hosts implemented: " .. table.concat(host.names, ", "))

    local width = config.tree.max_value_width

    if width == "auto" then
        health.ok("tree.max_value_width = 'auto' (window width minus the name column)")
    elseif width == false then
        health.ok("tree.max_value_width = false (values are never clamped)")
    elseif type(width) == "number" and width > 0 then
        health.ok("tree.max_value_width = " .. width .. " cells")
    else
        health.error("tree.max_value_width = " .. vim.inspect(width) .. ", expected a positive number, 'auto' or false")
    end

    local indent = config.tree.indent_width

    if indent == false then
        health.ok("tree.indent_width = false ('tabstop' is left alone)")
    elseif type(indent) == "number" and indent > 0 then
        health.ok("tree.indent_width = " .. indent)
    else
        health.error("tree.indent_width = " .. vim.inspect(indent) .. ", expected a positive number or false")
    end
end

local check_multiplexers = function()
    local mux = require("dap-view.host.mux")
    local configured = require("dap-view.setup").config.host.remote.multiplexer

    health.start("dap-view: multiplexers")

    for _, name in ipairs(mux.names) do
        local ok, available = pcall(function()
            return mux.resolve(name).available()
        end)

        local label = name .. (name == configured and " (configured)" or "")

        if ok and available then
            health.ok(label .. ": available")
        elseif not ok then
            health.error(label .. ": available() failed: " .. tostring(available))
        elseif name == configured then
            health.warn(label .. ": not available", "The remote host cannot spawn a viewer until this is fixed")
        else
            health.info(label .. ": not available")
        end
    end

    for _, var in ipairs({ "HERDR_ENV", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID" }) do
        health.info(var .. " = " .. (vim.env[var] or "unset"))
    end

    if vim.fn.executable("herdr") == 1 then
        health.info("herdr --version: " .. (version_of({ "herdr", "--version" }) or "failed to run"))
    else
        health.info("herdr: not on $PATH")
    end

    health.info("$TMUX = " .. (vim.env.TMUX or "unset"))

    if vim.fn.executable("tmux") == 1 then
        health.info("tmux -V: " .. (version_of({ "tmux", "-V" }) or "failed to run"))
    else
        health.info("tmux: not on $PATH")
    end
end

local check_remote = function()
    local host = require("dap-view.host")

    if host.name() ~= "remote" then
        return
    end

    health.start("dap-view: remote host")

    local status = require("dap-view.host.remote").status()

    if status.is_open then
        health.ok(("viewer is open (%dx%d)"):format(status.width or 0, status.height or 0))
    else
        health.info("viewer is not open")
    end

    health.info("channel: " .. (status.chan and tostring(status.chan) or "none"))
    health.info("socket: " .. (status.sock or "none"))
    health.info("pane handle: " .. (status.handle or "none"))
end

M.check = function()
    check_core()
    check_config()
    check_multiplexers()
    check_remote()
end

return M
