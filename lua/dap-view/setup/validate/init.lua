local M = {}

---@param config dapview.ConfigStrict
function M.validate(config)
    require("dap-view.setup.validate.util").validate("config", {
        windows = { config.windows, "table" },
        winbar = { config.winbar, "table" },
        help = { config.help, "table" },
        hover = { config.hover, "table" },
        render = { config.render, "table" },
        switchbuf = { config.switchbuf, { "string", "function" } },
        keymaps = { config.keymaps, { "table" } },
        icons = { config.icons, "table" },
        virtual_text = { config.virtual_text, "table" },
        auto_toggle = { config.auto_toggle, { "boolean", "string" } },
        follow_tab = { config.follow_tab, { "boolean", "function" } },
        host = { config.host, "table" },
        tree = { config.tree, "table" },
        decoders = { config.decoders, "table", true },
        theme = { config.theme, { "string", "function" } },
        theme_overrides = { config.theme_overrides, "table" },
        transparent = { config.transparent, { "boolean", "string" } },
    }, config)

    if
        type(config.auto_toggle) == "string"
        and not vim.tbl_contains({ "keep_terminal", "open_term", "open" }, config.auto_toggle)
    then
        error("Unknown auto_toggle option: " .. config.auto_toggle)
    end

    if type(config.transparent) == "string" and config.transparent ~= "auto" then
        error("Unknown transparent option: " .. config.transparent)
    end

    for colors_name, roles in pairs(config.theme_overrides) do
        if type(roles) ~= "table" then
            error("theme_overrides." .. tostring(colors_name) .. ": expected a table of roles")
        end
    end

    require("dap-view.setup.validate.winbar").validate(config.winbar)
    require("dap-view.setup.validate.windows").validate(config.windows)
    require("dap-view.setup.validate.help").validate(config.help)
    require("dap-view.setup.validate.hover").validate(config.hover)
    require("dap-view.setup.validate.icons").validate(config.icons)
    require("dap-view.setup.validate.virtual-text").validate(config.virtual_text)
    require("dap-view.setup.validate.render").validate(config.render)
    require("dap-view.setup.validate.host").validate(config.host)
    require("dap-view.setup.validate.tree").validate(config.tree)
end

return M
