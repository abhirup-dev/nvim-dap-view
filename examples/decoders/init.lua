-- Standalone test editor. Set NVIM_DAP_PATH, NVIM_NIO_PATH and DLV first.
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.runtimepath:prepend(directory .. "/../..")
vim.opt.runtimepath:prepend(assert(vim.env.NVIM_DAP_PATH, "set NVIM_DAP_PATH"))
vim.opt.runtimepath:prepend(assert(vim.env.NVIM_NIO_PATH, "set NVIM_NIO_PATH"))
require("dap-view").setup({
    decoders = dofile(directory .. "/profiles.lua"),
    host = { default = "split" },
    winbar = { default_section = "scopes" },
})
local dap = require("dap")
dap.adapters.go = {
    type = "server",
    port = "${port}",
    executable = {
        command = vim.env.DLV or "dlv",
        args = { "dap", "-l", "127.0.0.1:${port}" },
    },
}
dap.configurations.go = {
    {
        type = "go",
        request = "launch",
        name = "Serialized protobuf",
        mode = "exec",
        program = directory .. "/fixture",
        cwd = directory,
    },
}
vim.keymap.set("n", "<F5>", dap.continue)
vim.keymap.set("n", "<F10>", dap.step_over)
vim.keymap.set("n", "<F9>", dap.toggle_breakpoint)
