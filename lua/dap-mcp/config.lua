---Configuration for nvim-dap-mcp.
---
---`port`, `bind`, `token` and `autostart` are stored here for the Go sidecar
---(phase 5b) to read; nothing in the Lua core acts on them yet.
local M = {}

---@class dapmcp.ResponseConfig
---@field source_context integer Lines of source shown around the stopped frame, each side
---@field max_value_width integer Display cells a variable value may occupy before it is clamped
---@field max_children integer Default page size for `get_variables`

---@class dapmcp.EvaluateConfig
---@field allow_side_effects boolean Permit expressions that look like assignments or calls

---@class dapmcp.UiConfig
---@field integrate_dap_view boolean Reuse dap-view's truncation and expose the `ui_*` tools

---@class dapmcp.Config
---@field port integer
---@field bind string
---@field token string? nil means the sidecar generates one per start
---@field autostart "never"|"on_session"|"always"
---@field response dapmcp.ResponseConfig
---@field evaluate dapmcp.EvaluateConfig
---@field ui dapmcp.UiConfig

---@type dapmcp.Config
M.defaults = {
    port = 28911,
    bind = "127.0.0.1",
    token = nil,
    autostart = "on_session",
    response = {
        source_context = 10,
        max_value_width = 200,
        max_children = 50,
    },
    evaluate = {
        allow_side_effects = false,
    },
    ui = {
        integrate_dap_view = true,
    },
}

---@type dapmcp.Config
M.config = vim.deepcopy(M.defaults)

local AUTOSTART = { never = true, on_session = true, always = true }

---@param config dapmcp.Config
local function validate(config)
    vim.validate("port", config.port, function(v)
        return type(v) == "number" and v == math.floor(v) and v > 0 and v < 65536
    end, "a port number between 1 and 65535")
    vim.validate("bind", config.bind, "string")
    vim.validate("token", config.token, "string", true)
    vim.validate("autostart", config.autostart, function(v)
        return AUTOSTART[v] ~= nil
    end, "one of 'never', 'on_session', 'always'")

    vim.validate("response", config.response, "table")
    vim.validate("response.source_context", config.response.source_context, "number")
    vim.validate("response.max_value_width", config.response.max_value_width, "number")
    vim.validate("response.max_children", config.response.max_children, "number")

    vim.validate("evaluate", config.evaluate, "table")
    vim.validate("evaluate.allow_side_effects", config.evaluate.allow_side_effects, "boolean")

    vim.validate("ui", config.ui, "table")
    vim.validate("ui.integrate_dap_view", config.ui.integrate_dap_view, "boolean")
end

---@param opts dapmcp.Config?
---@return dapmcp.Config
M.setup = function(opts)
    vim.validate("opts", opts, "table", true)

    local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    validate(config)
    M.config = config

    return config
end

return M
