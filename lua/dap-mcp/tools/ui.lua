---dap-view integration. These tools only exist when `ui.integrate_dap_view` is
---set and dap-view is actually installed; otherwise every call answers with a
---`ui_unavailable` error rather than the tool vanishing from the surface, so
---the sidecar's advertised surface stays stable across editors.
local registry = require("dap-mcp.registry")
local config = require("dap-mcp.config")
local util = require("dap-mcp.util")

---@return table dap-view
local function dapview()
    if not config.config.ui.integrate_dap_view then
        util.fail("ui_unavailable", "dap-view integration is disabled (ui.integrate_dap_view = false)")
    end

    local ok, view = pcall(require, "dap-view")
    if not ok then
        util.fail("ui_unavailable", "dap-view is not installed")
    end

    return view
end

---@param name string
---@param description string
---@param method string
local function passthrough(name, description, method)
    registry.register({
        name = name,
        description = description,
        schema = registry.schema(),
        handler = function()
            local view = dapview()
            if type(view[method]) ~= "function" then
                util.fail("ui_unavailable", "This dap-view build has no %s()", method)
            end

            view[method]()

            return { ok = true }
        end,
    })
end

passthrough("ui_open", "Open the dap-view debugger window in the human's Neovim.", "open")
passthrough("ui_close", "Close the dap-view debugger window.", "close")
passthrough("ui_undock", "Undock dap-view into its external host, e.g. a tmux pane.", "undock")
passthrough("ui_dock", "Dock dap-view back into Neovim.", "dock")

registry.register({
    name = "ui_host",
    description = "Switch which host renders dap-view, e.g. 'split', 'tab' or 'remote'.",
    schema = registry.schema({
        name = { type = "string", description = "Host name registered with dap-view" },
    }, { "name" }),
    handler = function(args)
        local view = dapview()

        if type(args.name) ~= "string" or args.name == "" then
            util.fail("invalid_argument", "`name` must be a non-empty string")
        end

        if type(view.switch_host) ~= "function" then
            util.fail("ui_unavailable", "This dap-view build has no switch_host()")
        end

        view.switch_host(args.name)

        return { host = args.name }
    end,
})
