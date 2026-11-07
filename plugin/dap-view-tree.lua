local command = vim.api.nvim_create_user_command

command("DapViewReroot", function()
    require("dap-view").reroot()
end, {})
command("DapViewRootUp", function()
    require("dap-view").root_up()
end, {})
