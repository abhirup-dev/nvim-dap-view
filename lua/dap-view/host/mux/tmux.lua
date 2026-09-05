local mux = require("dap-view.host.mux")

---tmux adapter. `-P -F '#{pane_id}'` makes both `split-window` and `new-window`
---print the new pane id, which is the handle everything else takes.
---@type dapview.Mux
local M = {}

local DIRECTIONS = {
    right = { "-h" },
    down = { "-v" },
    left = { "-h", "-b" },
    up = { "-v", "-b" },
}

M.available = function()
    return vim.env.TMUX ~= nil and vim.fn.executable("tmux") == 1
end

---@param handle string
M.is_alive = function(handle)
    return mux.succeeds({ "tmux", "display", "-p", "-t", handle, "#{pane_id}" })
end

---@param size number
---@return string
local size_arg = function(size)
    return size < 1 and (math.floor(size * 100) .. "%") or tostring(math.floor(size))
end

---@param cmd string
---@param opts dapview.MuxSpawnOpts
---@return string
M.spawn = function(cmd, opts)
    local argv

    if opts.kind == "tab" then
        argv = { "tmux", "new-window", "-d", "-P", "-F", "#{pane_id}", "-n", opts.label, "-c", opts.cwd, cmd }
    else
        local flags = DIRECTIONS[opts.direction]

        if not flags then
            error("Unknown direction for tmux: " .. tostring(opts.direction))
        end

        argv = { "tmux", "split-window", "-d", "-P", "-F", "#{pane_id}" }

        vim.list_extend(argv, flags)
        vim.list_extend(argv, { "-l", size_arg(opts.size), "-c", opts.cwd, cmd })
    end

    local out, err = mux.run(argv)

    if not out then
        error("tmux " .. argv[2] .. " failed: " .. tostring(err))
    end

    return vim.trim(out)
end

---@param handle string
M.close = function(handle)
    mux.run({ "tmux", "kill-pane", "-t", handle })
end

return M
