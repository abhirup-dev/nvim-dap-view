local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")

local state = require("dap-view.state")
H.setup({ host = { default = os.getenv("HOST") or "tab" }, winbar = { default_section = "scopes" } })
local fake = H.new_fake_session({ term_buf = H.make_term_buf() })
fake.current_frame.scopes = { { name = "Locals", variablesReference = 100 } }
local delay, missing = 20, false
local base = fake.request
fake.request = function(self, cmd, args, cb)
    if cmd ~= "variables" then
        return base(self, cmd, args, cb)
    end
    local vars = args.variablesReference == 100
            and (missing and {} or {
                { name = "a", value = "{}", evaluateName = "a", variablesReference = 101 },
            })
        or { { name = "child", value = "1", evaluateName = "a.child", variablesReference = 0 } }
    local co = coroutine.running()
    vim.defer_fn(function()
        if cb then
            cb(nil, { variables = vars })
        else
            assert(coroutine.resume(co, nil, { variables = vars }))
        end
    end, delay)
    if not cb then
        return coroutine.yield()
    end
end
H.install_session(fake)
require("dap-view").open()
H.pump(150)
local function render()
    coroutine.wrap(require("dap-view.scopes.view").show)()
end
state.tree_root_stack = { "Locals.a" }
render()
H.eq(state.line_to_variable_path[2], "Locals.a", "pending render leaves published indices intact")
H.pump(30)
render()
H.pump(130)
H.eq(state.tree_root_stack, { "Locals.a" }, "overlapping renders preserve reroot")
H.eq(vim.api.nvim_buf_get_lines(state.bufnr, 0, 1, false), { "Locals ▸ a" }, "isolated breadcrumb")
H.eq(state.line_to_variable_path[2], "Locals.a.child", "published indices match subtree")
-- Width refreshes use the same isolated traversal.
render()
vim.api.nvim_win_set_width(state.winnr, 35)
H.pump(30)
render()
H.pump(100)
H.eq(state.tree_root_stack, { "Locals.a" }, "width refresh preserves root")
-- Changing the root during a request invalidates the previous publication.
render()
H.pump(5)
state.tree_root_stack = {}
render()
H.pump(100)
H.eq(vim.api.nvim_buf_get_lines(state.bufnr, 0, 1, false), { "Locals" }, "root change publishes current tree")
state.tree_root_stack = { "Locals.a" }
render()
H.pump(100)
-- A stale missing-target response must not pop the replacement root or clear its canvas.
missing = true
render()
H.pump(5)
missing = false
state.tree_root_stack = { "Locals.a", "Locals.a" }
render()
H.pump(130)
H.eq(state.tree_root_stack, { "Locals.a", "Locals.a" }, "stale missing target cannot pop current stack")
-- Publication belongs to the section, buffer and window captured by this render.
local published = vim.deepcopy(state.line_to_variable_path)
local target_buf, target_win = state.bufnr, state.winnr
for _, target in ipairs({ "section", "buffer", "window" }) do
    missing = true
    render()
    if target == "section" then
        state.current_section = "watches"
    elseif target == "buffer" then
        state.bufnr = vim.api.nvim_create_buf(false, true)
    else
        state.winnr = nil
    end
    H.pump(100)
    H.eq(state.line_to_variable_path, published, target .. " change rejects stale index publication")
    H.eq(state.tree_root_stack, { "Locals.a", "Locals.a" }, target .. " change rejects stale root cleanup")
    if target == "buffer" then
        vim.api.nvim_buf_delete(state.bufnr, { force = true })
    end
    state.current_section, state.bufnr, state.winnr = "scopes", target_buf, target_win
end
missing = false
-- Frame and session changes invalidate a pending result before any cleanup/publication.
local before = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
missing = true
render()
fake.current_frame = vim.tbl_extend("force", fake.current_frame, { id = 12 })
H.pump(100)
H.eq(state.tree_root_stack, { "Locals.a", "Locals.a" }, "old frame cannot pop root")
H.eq(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), before, "old frame cannot publish")
render()
H.install_session(H.new_fake_session())
H.pump(100)
H.eq(state.tree_root_stack, { "Locals.a", "Locals.a" }, "old session cannot pop root")
H.done()
