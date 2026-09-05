---Session lifecycle tools.
local registry = require("dap-mcp.registry")
local status = require("dap-mcp.status")
local util = require("dap-mcp.util")

---Every known configuration, with the raw config kept alongside the summary so
---`start_session` can hand it straight to `dap.run`.
---@return { summary: table, config: dap.Configuration }[]
local function collect()
    local dap = require("dap")
    local entries = {}

    for filetype, configs in pairs(dap.configurations) do
        for _, config in ipairs(configs) do
            table.insert(entries, {
                config = config,
                summary = {
                    name = config.name,
                    type = config.type,
                    request = config.request,
                    filetype = filetype,
                    source = "dap.configurations",
                },
            })
        end
    end

    local ok, vscode = pcall(require, "dap.ext.vscode")
    if ok and type(vscode.getconfigs) == "function" then
        local configs = vscode.getconfigs()
        for _, config in ipairs(configs or {}) do
            table.insert(entries, {
                config = config,
                summary = {
                    name = config.name,
                    type = config.type,
                    request = config.request,
                    source = "launch.json",
                },
            })
        end
    end

    -- `pairs` over filetypes is unordered; keep the surface deterministic.
    table.sort(entries, function(a, b)
        local left = tostring(a.summary.name) .. tostring(a.summary.source)
        local right = tostring(b.summary.name) .. tostring(b.summary.source)
        return left < right
    end)

    return entries
end

registry.register({
    name = "list_configurations",
    description = "List the debug configurations available in this Neovim: dap.configurations "
        .. "per filetype, plus any read from .vscode/launch.json.",
    schema = registry.schema(),
    handler = function()
        local configurations = {}
        for _, entry in ipairs(collect()) do
            table.insert(configurations, entry.summary)
        end

        return { configurations = configurations }
    end,
})

registry.register({
    name = "start_session",
    description = "Start a debug session. Give a config_name from list_configurations, or an "
        .. "inline config object. The session is shared with the human's Neovim UI. Startup is "
        .. "asynchronous: follow this with wait_for_pause.",
    schema = registry.schema({
        config_name = { type = "string", description = "Name of a configuration from list_configurations" },
        filetype = { type = "string", description = "Filetype to resolve the configuration against" },
        config = { type = "object", description = "Inline nvim-dap configuration, used instead of config_name" },
    }),
    handler = function(args)
        local dap = require("dap")
        local config = args.config

        if config == nil then
            if type(args.config_name) ~= "string" then
                util.fail("invalid_argument", "Provide either `config_name` or `config`")
            end

            for _, entry in ipairs(collect()) do
                local matches = entry.summary.name == args.config_name
                    and (
                        args.filetype == nil
                        or entry.summary.filetype == nil
                        or entry.summary.filetype == args.filetype
                    )
                if matches then
                    config = entry.config
                    break
                end
            end

            if config == nil then
                util.fail("unknown_configuration", "No configuration named %q", args.config_name)
            end
        end

        if type(config) ~= "table" or type(config.type) ~= "string" then
            util.fail("invalid_argument", "A configuration needs at least a `type` field")
        end

        dap.run(config, { filetype = args.filetype })

        return {
            started = true,
            config = { name = config.name, type = config.type, request = config.request },
        }
    end,
})

registry.register({
    name = "stop_session",
    description = "Terminate the active debug session.",
    schema = registry.schema(),
    handler = function()
        local dap = require("dap")

        -- `dap.terminate` silently returns without invoking its callback when
        -- there is no session (lua/dap.lua:860), so check first or we hang.
        util.need_session()

        local co = coroutine.running()
        local resumed = false

        dap.terminate(nil, nil, function()
            if resumed then
                return
            end
            resumed = true
            vim.schedule(function()
                coroutine.resume(co)
            end)
        end)

        coroutine.yield()

        return { stopped = true }
    end,
})

registry.register({
    name = "session_status",
    description = "One fat snapshot of the debugger: state, stop reason, current frame, source "
        .. "around it, the top of the stack and the current frame's locals. Values are clamped; "
        .. "clamped ones carry truncated=true and a full_value_ref for get_value.",
    schema = registry.schema(),
    handler = function()
        return status.compose()
    end,
})
