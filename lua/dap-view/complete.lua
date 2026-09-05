local setup = require("dap-view.setup")

local M = {}

---@param arg_lead string
---@return string[]
M.complete_sections = function(arg_lead)
    local sections = setup.config.winbar.sections
    return vim.iter(sections)
        :filter(function(section)
            return section:find(arg_lead or "") == 1
        end)
        :totable()
end

---@param arg_lead string
---@return string[]
M.complete_hosts = function(arg_lead)
    return vim.iter(require("dap-view.host").names)
        :filter(function(host)
            return host:find(arg_lead or "") == 1
        end)
        :totable()
end

return M
