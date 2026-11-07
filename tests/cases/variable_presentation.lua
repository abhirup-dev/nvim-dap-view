local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local view = require("dap-view")
local state = require("dap-view.state")
local setup = require("dap-view.setup")
local ns = require("dap-view.globals").NAMESPACE
H.setup({ host = { default = os.getenv("HOST") or "split" }, winbar = { default_section = "scopes" } })
local fake = H.new_fake_session()
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
local values = {
    {
        name = "internal_member",
        value = "11",
        type = "int",
        variablesReference = 0,
        presentationHint = { visibility = "internal" },
    },
    { name = "count", value = "7", type = "int", variablesReference = 0 },
    { name = "special variables", value = "user data", type = "str", variablesReference = 0 },
    { name = "generated", value = "", variablesReference = 200, presentationHint = { kind = "virtual" } },
    {
        name = "readonly",
        value = "9",
        type = "int",
        variablesReference = 0,
        presentationHint = { attributes = { "readOnly" } },
    },
    {
        name = "private",
        value = "10",
        type = "int",
        variablesReference = 0,
        presentationHint = { visibility = "private" },
    },
    { name = "method", value = "fn", variablesReference = 0, presentationHint = { kind = "method" } },
}
local original = fake.request
local child_value = "42"
fake.request = function(self, command, args, callback)
    local response
    if command == "variables" then
        response = {
            variables = args.variablesReference == 100 and vim.deepcopy(values)
                or { { name = "child", value = child_value, type = "int", variablesReference = 0 } },
        }
    elseif command == "evaluate" then
        response = { result = "object", variablesReference = 100 }
        if args.expression == "virtual_result" then
            response.presentationHint = { kind = "virtual" }
        end
    else
        return original(self, command, args, callback)
    end
    local co = not callback and coroutine.running()
    vim.schedule(function()
        if callback then
            callback(nil, response)
        else
            assert(coroutine.resume(co, nil, response))
        end
    end)
    if co then
        return coroutine.yield()
    end
end
H.install_session(fake)

local function row(buf, needle)
    for line, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if text:find(needle, 1, true) then
            return line
        end
    end
    error("missing rendered row: " .. needle)
end
local function styled(buf, needle, group)
    local line = row(buf, needle) - 1
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { line, 0 }, { line, -1 }, { details = true })) do
        if mark[4].hl_group == "NvimDapView" .. group then
            return true
        end
    end
    return false
end
local function scopes()
    view.show_view("scopes")
    H.pump(80)
end
view.open()
state.variable_path_is_expanded["Locals.generated"] = true
H.group("protocol hints are independent of adapter names")
for _, adapter in ipairs({ "python", "go", "unknown-adapter" }) do
    fake.config.type = adapter
    scopes()
    H.ok(styled(state.bufnr, "generated", "VariableInternal"), adapter .. " synthetic group is subdued")
    H.ok(styled(state.bufnr, "internal_member", "VariableInternal"), adapter .. " internal visibility is subdued")
    H.ok(styled(state.bufnr, "child", "VariableInternal"), adapter .. " descendants inherit style")
    for _, name in ipairs({ "count", "special variables", "readonly", "private", "method" }) do
        H.ok(not styled(state.bufnr, name, "VariableInternal"), adapter .. " user data remains normal: " .. name)
    end
end
child_value = "43"
require("dap-view.decoders").invalidate()
scopes()
H.ok(styled(state.bufnr, "child", "WatchUpdated"), "updated internal value retains change emphasis")

H.group("watches and hover use the same protocol styling")
view.add_expr("object", true)
H.pump(80)
H.ok(styled(state.bufnr, "generated", "VariableInternal"), "watch children honor virtual hint")
view.add_expr("virtual_result", true)
H.pump(80)
H.ok(styled(state.bufnr, "virtual_result", "VariableInternal"), "evaluate response hint styles watch root")
local code = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(code, 0, -1, false, { "object" })
local code_win = vim.api.nvim_open_win(code, true, { split = "above", win = state.winnr })
view.hover("virtual_result", true)
H.pump(80)
H.ok(styled(state.hover_bufnr, "virtual_result", "VariableInternal"), "evaluate response hint styles hover root")
H.ok(styled(state.hover_bufnr, "count", "VariableInternal"), "hover children inherit root style")
vim.api.nvim_set_current_win(code_win)
H.pump(30)

H.group("config overrides and disabling")
setup.config.tree.variable_highlight = function(variable, ctx)
    if variable.name == "generated" then
        return false
    end
    if variable.name == "count" and ctx.session.config.type == "unknown-adapter" and ctx.path == "Locals.count" then
        return "VariableInternal"
    end
end
scopes()
H.ok(styled(state.bufnr, "count", "VariableInternal"), "callback sees adapter and path")
H.ok(not styled(state.bufnr, "generated", "VariableInternal"), "false overrides protocol hint")
H.ok(not styled(state.bufnr, "child", "VariableInternal"), "override resets inheritance")
setup.config.tree.variable_highlight = false
scopes()
H.ok(not styled(state.bufnr, "generated", "VariableInternal"), "styling can be disabled")
H.ok(not styled(state.bufnr, "child", "VariableInternal"), "disabling also resets descendants")
H.eq(
    vim.api.nvim_get_hl(0, { name = "NvimDapViewVariableInternal", link = true }).link,
    "Comment",
    "theme supplies subdued color"
)
H.done()
