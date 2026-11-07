local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local state = require("dap-view.state")
H.setup({ host = { default = os.getenv("HOST") or "tab" }, winbar = { default_section = "scopes" } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
local base = fake.request
fake.request = function(self, cmd, args, cb)
    if cmd ~= "variables" then
        return base(self, cmd, args, cb)
    end
    local ref = args.variablesReference
    local vars
    if ref == 100 then
        vars = {
            { name = "a", value = "{}", variablesReference = 101 },
            { name = "other", value = "{}", variablesReference = 104 },
        }
    elseif ref == 104 then
        vars = {
            { name = "kept", value = "1", variablesReference = 0 },
            { name = "also", value = "2", variablesReference = 0 },
        }
    else
        vars = {
            {
                name = ref == 103 and "leaf" or "nested",
                value = "{}",
                variablesReference = ref == 103 and 0 or ref + 1,
            },
        }
    end
    local co = coroutine.running()
    vim.schedule(function()
        if cb then
            cb(nil, { variables = vars })
        else
            assert(coroutine.resume(co, nil, { variables = vars }))
        end
    end)
    if not cb then
        return coroutine.yield()
    end
end
H.install_session(fake)
state.variable_path_is_expanded["Locals.a"] = true
state.variable_path_is_expanded["Locals.other"] = true
require("dap-view").open()
H.pump(100)
local function render()
    coroutine.wrap(require("dap-view.scopes.view").show)()
    H.pump(80)
end
local function line(path)
    for l, p in pairs(state.line_to_variable_path) do
        if p == path then
            return l
        end
    end
end
vim.api.nvim_set_current_win(state.winnr)
-- Deliberately close the unrelated branch.
vim.api.nvim_win_set_cursor(state.winnr, { line("Locals.other.kept"), 0 })
vim.cmd("normal! zc")
H.ok(vim.fn.foldclosed(line("Locals.other.kept")) > 0, "manual fold established")
local label = vim.fn.foldtextresult(line("Locals.other.kept"))
H.ok(label:find("other", 1, true) and label:find("2 children", 1, true), "fold uses tree name and child count", label)
require("dap-view.scopes.actions").expand_or_collapse(line("Locals.a.nested"))
render()
require("dap-view.scopes.actions").expand_or_collapse(line("Locals.a.nested.nested"))
render()
H.eq(vim.fn.foldclosed(line("Locals.a.nested.nested.leaf")), -1, "new descendants visible past default fold level")
H.ok(vim.fn.foldclosed(line("Locals.other.kept")) > 0, "unrelated manual fold survives expansion")
render()
H.ok(vim.fn.foldclosed(line("Locals.other.kept")) > 0, "manual fold survives refresh")
H.eq(vim.fn.foldclosed(line("Locals.a.nested.nested.leaf")), -1, "expanded descendants survive refresh")

H.group("watch decoder-shaped synthetic descendants")
local function node(name, path, reference, children)
    return {
        variable = { name = name, value = "{}", variablesReference = reference },
        path = path,
        expanded = true,
        children = children,
        reference = reference,
    }
end
local deep = node("decoded", "watch.raw.decoded", -42, {
    node("item", "watch.raw.decoded.item", 0),
    node("item2", "watch.raw.decoded.item2", 0),
})
deep.expanded = false
state.watched_expressions = {
    watch = {
        id = 1,
        expanded = true,
        response = { result = "{}", variablesReference = -40 },
        children = {
            node("raw", "watch.raw", -41, { deep }),
            node("other", "watch.other", -43, {
                node("kept", "watch.other.kept", 0),
                node("also", "watch.other.also", 0),
            }),
        },
    },
}
state.current_section = "watches"
require("dap-view.watches.view").show()
local function watch_line(path)
    for l, entry in pairs(state.variable_views_by_line) do
        if entry.view.path == path then
            return l
        end
    end
end
vim.api.nvim_win_set_cursor(state.winnr, { watch_line("watch.other.kept"), 0 })
vim.cmd("normal! zc")
deep.expanded = true
require("dap-view.watches.view").show()
H.ok(vim.fn.foldclosed(watch_line("watch.other.kept")) > 0, "watch manual fold survives synthetic expansion")
local item_line
for l, entry in pairs(state.variable_views_by_line) do
    if entry.view.path == "watch.raw.decoded.item" then
        item_line = l
    end
end
H.ok(item_line ~= nil, "synthetic descendants indexed")
H.eq(vim.fn.foldclosed(item_line), -1, "new watch synthetic descendants visible")
H.done()
