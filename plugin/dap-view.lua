local api = vim.api

local command = api.nvim_create_user_command

command("DapViewOpen", function()
    require("dap-view").open()
end, {})
command("DapViewClose", function(opts)
    require("dap-view").close(opts.bang)
end, { bang = true })
command("DapViewHover", function(opts)
    local expr = nil
    if opts.range > 0 then
        expr = require("dap-view.util.exprs").get_trimmed_selection()
    elseif #opts.fargs > 0 then
        expr = table.concat(opts.fargs, " ")
    end
    require("dap-view").hover(expr, opts.bang)
end, { bang = true, nargs = "*" })
command("DapViewToggle", function(opts)
    require("dap-view").toggle(opts.bang)
end, { bang = true })
command("DapViewVirtualTextEnable", function()
    return require("dap-view").virtual_text_enable()
end, {})
command("DapViewVirtualTextDisable", function()
    return require("dap-view").virtual_text_disable()
end, {})
command("DapViewVirtualTextToggle", function()
    return require("dap-view").virtual_text_toggle()
end, {})
command("DapViewWatch", function(opts)
    local expr = nil
    if opts.range > 0 then
        expr = require("dap-view.util.exprs").get_trimmed_selection()
    elseif #opts.fargs > 0 then
        expr = table.concat(opts.fargs, " ")
    end
    require("dap-view").add_expr(expr)
end, {
    nargs = "*",
    range = true,
})
command("DapViewJump", function(opts)
    require("dap-view").jump_to_view(opts.fargs[1])
end, {
    nargs = 1,
    ---@param arg_lead string
    complete = function(arg_lead)
        return require("dap-view.complete").complete_sections(arg_lead)
    end,
})
command("DapViewShow", function(opts)
    require("dap-view").show_view(opts.fargs[1])
end, {
    nargs = 1,
    ---@param arg_lead string
    complete = function(arg_lead)
        return require("dap-view.complete").complete_sections(arg_lead)
    end,
})
command("DapViewHost", function(opts)
    local ok, err = pcall(require("dap-view.host").switch, opts.fargs[1])
    if not ok then
        -- Strip the "file:line: " prefix, this is a user facing message
        vim.notify((tostring(err):gsub("^.-:%d+: ", "")), vim.log.levels.ERROR)
    end
end, {
    nargs = 1,
    ---@param arg_lead string
    complete = function(arg_lead)
        return require("dap-view.complete").complete_hosts(arg_lead)
    end,
})
---Host switches are user driven and can fail for environmental reasons (no
---multiplexer, no socket), so report instead of throwing
---@param fn fun()
local protected = function(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            -- Strip the "file:line: " prefix, this is a user facing message
            vim.notify((tostring(err):gsub("^.-:%d+: ", "")), vim.log.levels.ERROR)
        end
    end
end

command(
    "DapViewUndock",
    protected(function()
        require("dap-view").undock()
    end),
    {}
)
command(
    "DapViewDock",
    protected(function()
        require("dap-view").dock()
    end),
    {}
)
command("DapViewNavigate", function(opts)
    require("dap-view").navigate({ wrap = opts.bang, count = tonumber(opts.fargs[1]) or 1 })
end, {
    nargs = 1,
    bang = true,
})

api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
        require("dap-view.vim-sessions").load_session_hook()
    end,
})
