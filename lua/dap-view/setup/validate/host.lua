local M = {}

local validate = require("dap-view.setup.validate.util").validate

---@param config dapview.HostConfig
function M.validate(config)
    validate("host", {
        default = { config.default, "string" },
        split = { config.split, "table" },
        tab = { config.tab, "table" },
        remote = { config.remote, "table" },
    }, config)

    if not vim.tbl_contains({ "split", "tab", "remote" }, config.default) then
        error("Unknown host option: " .. config.default)
    end

    validate("host.split", {
        restore_layout = { config.split.restore_layout, "boolean" },
    }, config.split)

    validate("host.tab", {
        layout = { config.tab.layout, "string" },
        follow_frame = { config.tab.follow_frame, "boolean" },
        close_on_terminate = { config.tab.close_on_terminate, "boolean" },
    }, config.tab)

    if not vim.tbl_contains({ "code-right", "code-left", "full" }, config.tab.layout) then
        error("Unknown host.tab.layout option: " .. config.tab.layout)
    end

    validate("host.remote", {
        multiplexer = { config.remote.multiplexer, "string" },
        spawn = { config.remote.spawn, { "function", "nil" } },
        pane = { config.remote.pane, "table" },
        nvim_args = { config.remote.nvim_args, "table" },
        close = { config.remote.close, { "function", "nil" } },
        mirror_highlights = { config.remote.mirror_highlights, "boolean" },
        close_on_terminate = { config.remote.close_on_terminate, "boolean" },
    }, config.remote)

    if config.remote.multiplexer == "custom" and not config.remote.spawn then
        error("host.remote.multiplexer is 'custom' but host.remote.spawn is not set")
    end

    for _, arg in ipairs(config.remote.nvim_args) do
        if type(arg) ~= "string" then
            error("host.remote.nvim_args must be a list of strings, got " .. type(arg))
        end
    end

    if not vim.tbl_contains(require("dap-view.host.mux").names, config.remote.multiplexer) then
        error("Unknown host.remote.multiplexer option: " .. config.remote.multiplexer)
    end

    validate("host.remote.pane", {
        kind = { config.remote.pane.kind, "string" },
        direction = { config.remote.pane.direction, "string" },
        size = { config.remote.pane.size, "number" },
        label = { config.remote.pane.label, "string" },
    }, config.remote.pane)

    if not vim.tbl_contains({ "split", "tab" }, config.remote.pane.kind) then
        error("Unknown host.remote.pane.kind option: " .. config.remote.pane.kind)
    end

    if not vim.tbl_contains({ "right", "down", "left", "up" }, config.remote.pane.direction) then
        error("Unknown host.remote.pane.direction option: " .. config.remote.pane.direction)
    end

    if config.remote.pane.size <= 0 then
        error("host.remote.pane.size must be positive, got " .. config.remote.pane.size)
    end
end

return M
