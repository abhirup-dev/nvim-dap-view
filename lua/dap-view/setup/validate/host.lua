local M = {}

local validate = require("dap-view.setup.validate.util").validate

---@param config dapview.HostConfig
function M.validate(config)
    validate("host", {
        default = { config.default, "string" },
        split = { config.split, "table" },
    }, config)

    if not vim.tbl_contains({ "split" }, config.default) then
        error("Unknown host option: " .. config.default)
    end

    validate("host.split", {
        restore_layout = { config.split.restore_layout, "boolean" },
    }, config.split)
end

return M
