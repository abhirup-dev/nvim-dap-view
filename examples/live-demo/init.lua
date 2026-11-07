-- Live Python/Go demos of nvim-dap-view, custom JSON decoding and conditional breakpoints.
-- Run with DEMO_LANG=python|go nvim -u <this-file>; uses local Mason adapters. 2026-11-07.
local directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(directory, ":h:h")
local H = dofile(root .. "/tests/harness.lua")
local language = vim.env.DEMO_LANG or "python"
local dap, view = require("dap"), require("dap-view")
vim.opt.number = true
vim.opt.signcolumn = "yes:2"
vim.opt.mouse = "a"
vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.laststatus = 3
vim.opt.showmode = false
vim.opt.shortmess:append("I")
vim.g.mapleader = " "
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
vim.cmd.colorscheme("habamax")
vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn" })
vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "Visual" })
H.setup({
    host = { default = "split" },
    auto_toggle = false,
    windows = { position = "right", size = 0.48, terminal = { hide = true } },
    winbar = {
        sections = { "scopes", "watches", "threads", "breakpoints", "repl" },
        default_section = "scopes",
        controls = { enabled = true, buttons = { "play", "step_into", "step_over", "step_out", "terminate" } },
    },
    tree = {
        max_value_width = 85,
        variable_highlight = function(variable, ctx)
            -- Explicit debugpy compatibility override: these groups have no DAP virtual hint.
            if
                ctx.session
                and ctx.session.config.type == "python"
                and variable.type == ""
                and variable.value == ""
                and (variable.variablesReference or 0) > 0
                and (
                    variable.name == "special variables"
                    or variable.name == "function variables"
                    or variable.name == "class variables"
                )
            then
                return "VariableInternal"
            end
            -- Delve also omits hints for compiler-generated unnamed return slots.
            if
                ctx.session
                and ctx.session.config.type == "go"
                and not variable.evaluateName
                and variable.name
                and variable.name:match("^~r%d+$")
            then
                return "VariableInternal"
            end
            -- nil preserves the protocol-based default for every adapter.
        end,
    },
    decoders = {
        profile = "json",
        profiles = {
            {
                name = "json",
                decoders = {
                    {
                        name = "Cart JSON",
                        kind = "lua",
                        match = { name = "payload" },
                        decode = function(variable)
                            local value = vim.json.decode(variable.value)
                            if type(value) == "string" then
                                value = vim.json.decode(value)
                            end
                            return require("dap-view.decoders").from_json(value)
                        end,
                    },
                },
            },
        },
    },
})
local python = vim.fn.expand("~/.local/share/nvim/mason/packages/debugpy/venv/bin/python")
dap.adapters.python = { type = "executable", command = python, args = { "-m", "debugpy.adapter" } }
dap.adapters.go = {
    type = "server",
    port = "${port}",
    executable = {
        command = vim.fn.expand("~/.local/share/nvim/mason/packages/delve/dlv"),
        args = { "dap", "-l", "127.0.0.1:${port}" },
    },
}
local source = directory .. (language == "go" and "/main.go" or "/cart.py")
local condition = language == "go" and "item.Quantity > 1" or 'item["quantity"] > 1'
local configuration = language == "go"
        and {
            type = "go",
            request = "launch",
            name = "Go conditional + decoder",
            mode = "exec",
            program = directory .. "/cart-go",
            cwd = directory,
        }
    or {
        type = "python",
        request = "launch",
        name = "Python conditional + decoder",
        program = source,
        pythonPath = python,
        cwd = directory,
        console = "internalConsole",
        justMyCode = true,
    }
_G.demo = { stops = 0, language = language, condition = condition, configuration = configuration, history = {} }
function demo.focus_source()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == demo.source then
            vim.api.nvim_set_current_win(win)
            return
        end
    end
end
function demo.section(name)
    view.show_view(name)
    local win = require("dap-view.state").winnr
    if win then
        vim.api.nvim_set_current_win(win)
    end
end
function demo.start()
    demo.focus_source()
    dap.run(configuration)
end
function demo.inspect()
    local result, done = {}, false
    coroutine.wrap(function()
        local session = assert(dap.session())
        result.supportsConditionalBreakpoints = session.capabilities.supportsConditionalBreakpoints
        result.line = session.current_frame.line
        result.stops = demo.stops
        for name, expression in pairs({
            item = language == "go" and "item.Name" or 'item["name"]',
            total = "total",
            payload = "payload",
        }) do
            local err, body = session:request(
                "evaluate",
                { expression = expression, context = "watch", frameId = session.current_frame.id }
            )
            result[name] = err and vim.inspect(err) or body.result
        end
        done = true
    end)()
    assert(
        vim.wait(10000, function()
            return done
        end, 10),
        "inspect timed out"
    )
    return result
end
dap.listeners.after.scopes["live-demo"] = function()
    demo.stops = demo.stops + 1
    vim.schedule(function()
        local state = require("dap-view.state")
        state.variable_path_is_expanded["Locals.payload"] = true
        state.variable_path_is_expanded["Locals.payload.decoded"] = true
        if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
            view.open()
        elseif state.current_section == "scopes" then
            view.show_view("scopes")
        end
    end)
end
local maps = {
    ["<F5>"] = dap.continue,
    ["<F10>"] = dap.step_over,
    ["<F11>"] = dap.step_into,
    ["<F12>"] = dap.step_out,
    ["<F9>"] = dap.toggle_breakpoint,
    ["<leader>dn"] = dap.step_over,
    ["<leader>dc"] = dap.continue,
    ["<leader>di"] = dap.step_into,
    ["<leader>do"] = dap.step_out,
    ["<leader>ds"] = function()
        demo.section("scopes")
    end,
    ["<leader>dw"] = function()
        demo.section("watches")
    end,
    ["<leader>db"] = function()
        demo.section("breakpoints")
    end,
    ["<leader>dt"] = function()
        demo.section("threads")
    end,
    ["<leader>dh"] = function()
        view.hover(nil, true)
    end,
    ["<leader>dd"] = function()
        local D = require("dap-view.decoders")
        demo.decoder_off = not demo.decoder_off
        D.use(demo.decoder_off and "off" or "json")
    end,
}
for key, action in pairs(maps) do
    vim.keymap.set("n", key, action, { silent = true })
end
vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        vim.cmd.edit(source)
        demo.source = vim.api.nvim_get_current_buf()
        for line, text in ipairs(vim.api.nvim_buf_get_lines(demo.source, 0, -1, false)) do
            if text:find("CONDITIONAL:", 1, true) then
                vim.api.nvim_win_set_cursor(0, { line, 0 })
                dap.set_breakpoint(condition)
                break
            end
        end
        vim.schedule(function()
            vim.o.statusline = " "
                .. language:upper()
                .. " DEMO | condition: "
                .. condition
                .. " | Space dd: decoder on/off %=%f %l:%c "
        end)
    end,
})
