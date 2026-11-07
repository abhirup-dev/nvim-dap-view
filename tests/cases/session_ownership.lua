-- Real session round trips in fresh processes: ownership belongs to the saved
-- session, never to the host selected when it is sourced.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/harness.lua")
local api = vim.api
local role = vim.env.OWNERSHIP_ROLE
local scenario = vim.env.OWNERSHIP_SCENARIO
local dir = vim.env.OWNERSHIP_DIR
local saved = vim.env.OWNERSHIP_SAVED
local restored = vim.env.OWNERSHIP_RESTORED
local session = dir and (dir .. "/Session.vim")

if role then
    H.setup({
        host = { default = role == "write" and saved or restored },
        winbar = { sections = { "scopes", "repl" }, default_section = "scopes" },
    })
    if role == "write" then
        vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize"
        if scenario ~= "no_globals" then
            vim.opt.sessionoptions:append("globals")
        end
        vim.cmd.edit(dir .. "/source.lua")
        local source_page = api.nvim_get_current_tabpage()
        H.install_session(H.new_fake_session())
        require("dap-view").open()
        H.pump(100)
        if scenario ~= "move_first" and scenario ~= "move_last" then
            require("dap-view").show_view("repl")
        else
            vim.o.sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds"
        end
        H.pump(100)
        local debugger = api.nvim_get_current_tabpage()
        if scenario == "manual" then
            vim.cmd.tabclose({ bang = true })
            H.eq(vim.g.DapviewTabpage, nil, "manual tabclose clears ownership immediately")
        end
        -- A separate user tab with two distinct source buffers must survive,
        -- including after its tab number replaces a manually closed debugger.
        vim.cmd.tabnew(dir .. "/left.lua")
        vim.cmd.vsplit(dir .. "/right.lua")
        local layout = vim.fn.winlayout()
        local function names(node)
            if node[1] == "leaf" then
                return { "leaf", api.nvim_buf_get_name(api.nvim_win_get_buf(node[2])) }
            end
            return { node[1], vim.tbl_map(names, node[2]) }
        end
        vim.fn.writefile({ vim.json.encode(names(layout)) }, dir .. "/layout.json")
        vim.cmd.tabfirst()
        if scenario == "move_first" or scenario == "move_last" then
            api.nvim_set_current_tabpage(debugger)
            vim.cmd(scenario == "move_first" and "tabmove 0" or "tabmove $")
            vim.fn.writefile({ tostring(api.nvim_tabpage_get_number(source_page)) }, dir .. "/source-page")
            -- No TabEnter between the reorder and the actual session writer.
        end
        vim.cmd("mksession! " .. vim.fn.fnameescape(session))
        if scenario == "legacy" then
            local lines = vim.fn.readfile(session)
            lines = vim.tbl_filter(function(line)
                return not line:find("DapviewTabpage", 1, true)
            end, lines)
            vim.fn.writefile(lines, session)
        end
        H.done()
    else
        vim.cmd.source(session)
        local source_page
        if scenario == "move_first" or scenario == "move_last" then
            source_page = api.nvim_list_tabpages()[tonumber(vim.fn.readfile(dir .. "/source-page")[1])]
        end
        H.pump(300)
        if source_page then
            H.ok(api.nvim_tabpage_is_valid(source_page), "original source tab handle survives reordered restore")
        end
        local view_win = require("dap-view.state").winnr
        local view_page = restored == "tab"
            and view_win
            and api.nvim_win_is_valid(view_win)
            and api.nvim_win_get_tabpage(view_win)
        local source_pages, user_pages = 0, 0
        for _, page in ipairs(api.nvim_list_tabpages()) do
            local names = {}
            for _, win in ipairs(api.nvim_tabpage_list_wins(page)) do
                names[api.nvim_buf_get_name(api.nvim_win_get_buf(win))] = true
            end
            if names[dir .. "/source.lua"] and page ~= view_page then
                source_pages = source_pages + 1
            end
            if names[dir .. "/left.lua"] then
                user_pages = user_pages + 1
                api.nvim_set_current_tabpage(page)
                local function named(node)
                    if node[1] == "leaf" then
                        return { "leaf", api.nvim_buf_get_name(api.nvim_win_get_buf(node[2])) }
                    end
                    return { node[1], vim.tbl_map(named, node[2]) }
                end
                H.eq(
                    named(vim.fn.winlayout()),
                    vim.json.decode(vim.fn.readfile(dir .. "/layout.json")[1]),
                    "unrelated user tab keeps both buffers and split layout"
                )
            end
        end
        H.eq(user_pages, 1, "unrelated user tab survives exactly once")
        local unmarked = scenario == "legacy" or scenario == "no_globals"
        local expected_source = saved == "tab" and scenario ~= "manual" and unmarked and 2 or 1
        H.eq(source_pages, expected_source, "saved ownership determines which mixed tab survives")
        local expected_tabs = scenario == "manual" and 2 or (saved == "tab" and unmarked and 3 or 2)
        if scenario ~= "manual" and restored == "tab" then
            expected_tabs = expected_tabs + 1
        end
        H.eq(#api.nvim_list_tabpages(), expected_tabs, "only proven debugger tabpages are reclaimed")
        if scenario == "manual" or restored == "split" then
            H.eq(vim.g.DapviewTabpage, nil, "consumed or manually cleared marker does not linger")
        else
            local win = require("dap-view.state").winnr
            H.ok(win and api.nvim_win_is_valid(win), "debugger reopened")
            if win and api.nvim_win_is_valid(win) then
                H.eq(
                    vim.g.DapviewTabpage,
                    api.nvim_tabpage_get_number(api.nvim_win_get_tabpage(win)),
                    "marker belongs to newly opened debugger"
                )
            end
        end
        H.done()
    end
    return
end

local file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
for _, case in ipairs({
    { "manual", "tab", "tab" },
    { "move_first", "tab", "tab" },
    { "move_last", "tab", "tab" },
    { "move_first", "tab", "split" },
    { "move_last", "tab", "split" },
    { "normal", "tab", "tab" },
    { "normal", "tab", "split" },
    { "normal", "split", "tab" },
    { "normal", "split", "split" },
    { "no_globals", "tab", "tab" },
    { "no_globals", "split", "tab" },
    { "legacy", "tab", "split" },
    { "legacy", "split", "tab" },
    { "no_globals", "tab", "split" },
}) do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    root = assert(vim.uv.fs_realpath(root))
    for _, name in ipairs({ "source", "left", "right" }) do
        vim.fn.writefile({ "-- " .. name }, root .. "/" .. name .. ".lua")
    end
    for _, phase in ipairs({ "write", "read" }) do
        local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", file }, {
            text = true,
            env = {
                OWNERSHIP_ROLE = phase,
                OWNERSHIP_SCENARIO = case[1],
                OWNERSHIP_DIR = root,
                OWNERSHIP_SAVED = case[2],
                OWNERSHIP_RESTORED = case[3],
            },
        }):wait()
        H.eq(result.code, 0, table.concat(case, "/") .. "/" .. phase .. "\n" .. (result.stderr or ""))
    end
    vim.fn.delete(root, "rf")
end
H.done()
