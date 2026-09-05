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
        mirror_highlights = { config.remote.mirror_highlights, "boolean" },
    }, config.remote)

    if not vim.tbl_contains({ "tmux", "herdr", "custom" }, config.remote.multiplexer) then
        error("Unknown host.remote.multiplexer option: " .. config.remote.multiplexer)
    end

    validate("host.remote.pane", {
        direction = { config.remote.pane.direction, "string" },
        size = { config.remote.pane.size, "number" },
    }, config.remote.pane)
end

return M
