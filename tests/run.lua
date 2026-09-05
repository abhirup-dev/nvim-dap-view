-- Runs every case under `tests/cases` in its own headless Neovim, once per host.
--
--     nvim --headless -u NONE -l tests/run.lua
--
-- Each case reads `$HOST` (`tab` or `split`) and asserts the behaviour expected
-- of that host, so parity is checked by construction rather than by remembering
-- to write the second case. Exits non-zero if any case fails.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local cases = vim.fn.globpath(root .. "/tests/cases", "*.lua", false, true)
table.sort(cases)

local failed = 0

local hosts = { "tab", "split" }
local total = 0

for _, case in ipairs(cases) do
    local name = vim.fn.fnamemodify(case, ":t:r")

    for _, host in ipairs(hosts) do
        total = total + 1

        print(("### %s [host=%s]"):format(name, host))

        local res = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", case }, {
            text = true,
            env = { HOST = host },
        }):wait()

        io.write(res.stdout or "")
        io.write(res.stderr or "")

        if res.code ~= 0 then
            failed = failed + 1
        end
    end
end

print(("\n%d/%d runs passed"):format(total - failed, total))

vim.cmd(failed > 0 and "cq!" or "qa!")
