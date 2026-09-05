local M = {}

---@param config dapview.TreeConfig
function M.validate(config)
    local validate = require("dap-view.setup.validate.util").validate

    validate("tree", {
        max_value_width = { config.max_value_width, { "number", "string", "boolean" } },
        ellipsis = { config.ellipsis, "string" },
        fold = { config.fold, "boolean" },
        fold_level = { config.fold_level, "number" },
        reroot_depth = { config.reroot_depth, { "number", "boolean" } },
    }, config)

    local max_value_width = config.max_value_width
    if type(max_value_width) == "string" and max_value_width ~= "auto" then
        error('tree.max_value_width: expected an integer, "auto" or false, got ' .. max_value_width)
    end
    if max_value_width == true then
        error('tree.max_value_width: expected an integer, "auto" or false, got true')
    end
    if type(max_value_width) == "number" and (max_value_width < 1 or max_value_width % 1 ~= 0) then
        error("tree.max_value_width: expected a positive integer, got " .. max_value_width)
    end

    if config.fold_level < 0 or config.fold_level % 1 ~= 0 then
        error("tree.fold_level: expected a non negative integer, got " .. config.fold_level)
    end

    local reroot_depth = config.reroot_depth
    if reroot_depth == true then
        error("tree.reroot_depth: expected an integer or false, got true")
    end
    if type(reroot_depth) == "number" and (reroot_depth < 1 or reroot_depth % 1 ~= 0) then
        error("tree.reroot_depth: expected a positive integer, got " .. reroot_depth)
    end
end

return M
