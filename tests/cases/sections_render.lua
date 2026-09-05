local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
local host_name = os.getenv("HOST") or "tab"

local custom_buf
H.setup({
    host = { default = host_name },
    winbar = {
        sections = {
            "scopes",
            "watches",
            "breakpoints",
            "threads",
            "exceptions",
            "sessions",
            "repl",
            "console",
            "notes",
        },
        default_section = "scopes",
        custom_sections = {
            notes = {
                label = "Notes",
                keymap = "N",
                action = function() end,
                buffer = function()
                    custom_buf = vim.api.nvim_create_buf(false, true)
                    vim.api.nvim_buf_set_lines(custom_buf, 0, -1, false, { "custom" })
                    return custom_buf
                end,
            },
        },
        controls = { enabled = true, position = "right" },
    },
})
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
H.install_session(fake)

H.group("every configured section renders / host=" .. host_name)
require("dap-view").open()
H.pump(250)

for _, s in ipairs({
    "scopes",
    "watches",
    "breakpoints",
    "threads",
    "exceptions",
    "sessions",
    "console",
    "repl",
    "notes",
}) do
    local ok, err = pcall(function()
        require("dap-view").show_view(s)
    end)
    H.pump(200)
    H.ok(
        ok and state.current_section == s,
        "section " .. s,
        tostring(err) .. " current=" .. tostring(state.current_section)
    )
end

H.group("custom section")
require("dap-view").show_view("notes")
H.pump(150)
H.eq(vim.api.nvim_win_get_buf(state.winnr), custom_buf, "custom section buffer is shown")

H.group("register_view at runtime")
require("dap-view").register_view("extra", {
    label = "Extra",
    keymap = "X",
    action = function() end,
    buffer = function()
        return vim.api.nvim_create_buf(false, true)
    end,
})
H.ok(require("dap-view.setup").config.winbar.custom_sections.extra ~= nil, "register_view added the section")

H.group("winbar / controls")
require("dap-view").show_view("scopes")
H.pump(200)
local wb = vim.wo[state.winnr][0].winbar
H.ok(wb and wb ~= "", "winbar is set")
H.ok(wb:find("Scopes") ~= nil, "winbar lists sections")
H.ok(wb:find("%%=") ~= nil, "controls rendered on the right")

H.group("navigate")
require("dap-view").show_view("scopes")
H.pump(150)
require("dap-view").navigate({ wrap = true, count = 1 })
H.pump(200)
H.eq(state.current_section, "watches", "navigate(+1) moved to the next section")
require("dap-view").navigate({ wrap = true, count = -1 })
H.pump(200)
H.eq(state.current_section, "scopes", "navigate(-1) moved back")

H.group("base keymaps on the view buffer")
local maps = {}
for _, m in ipairs(vim.api.nvim_buf_get_keymap(state.bufnr, "n")) do
    maps[m.lhs] = true
end
for _, k in ipairs({ "]v", "[v", "[V", "]V", "g?", "S", "W", "B", "T", "E", "K", "R", "C", "N" }) do
    H.ok(maps[k], "keymap " .. k .. " on the view buffer")
end

H.group("help float")
require("dap-view.views.keymaps.help").show_help()
H.pump(150)
local floats = 0
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
        floats = floats + 1
    end
end
H.ok(floats > 0, "help float opened")
H.done()
