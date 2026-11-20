---Theme providers turn the active colorscheme into a small set of semantic roles,
---which `dap-view.highlight` maps onto every `NvimDapView*` group.
local api = vim.api

local M = {}

---@alias dapview.Color string|integer `"#rrggbb"`, a color name or a 24-bit integer

---@class dapview.ThemeRoles
---@field fg? dapview.Color Default text
---@field muted? dapview.Color Secondary text: separators, inactive controls, internal variables
---@field panel? dapview.Color Surface of the dap-view window, its winbar and controls
---@field selection? dapview.Color Background of the current frame
---@field accent? dapview.Color Step controls, file names, threads
---@field selected? {fg?: dapview.Color, bg?: dapview.Color} The selected winbar tab
---@field ok? dapview.Color
---@field warn? dapview.Color
---@field error? dapview.Color
---@field changed? dapview.Color Variables whose value changed since the last stop
---@field raw? dapview.Color The `raw` node of a decoded value
---@field decoded? dapview.Color The `decoded` node of a decoded value
---@field header? dapview.Color Scope headers
---@field string? dapview.Color
---@field number? dapview.Color
---@field float? dapview.Color
---@field boolean? dapview.Color
---@field constant? dapview.Color
---@field function? dapview.Color

---@class dapview.ThemeContext
---@field background "dark"|"light"
---@field colors_name? string
---@field transparent boolean Whether surfaces are drawn without a background
---@field get fun(group: string): {fg?: string, bg?: string, bold?: boolean} Resolved colors of a highlight group, with links followed and `reverse` applied

---@alias dapview.ThemeProvider fun(ctx: dapview.ThemeContext): dapview.ThemeRoles

---@type table<string, dapview.ThemeProvider>
local providers = {}

---@param name string
---@param provider dapview.ThemeProvider
M.register = function(name, provider)
    vim.validate("name", name, "string")
    vim.validate("provider", provider, "function")
    assert(name ~= "auto" and name ~= "links", "theme name is reserved: " .. name)

    providers[name] = provider

    if require("dap-view.setup").config.theme == name then
        require("dap-view.highlight").apply()
    end
end

---@param name string
---@return dapview.ThemeProvider?
M.get = function(name)
    return providers[name]
end

---@return string[]
M.list = function()
    local names = vim.tbl_keys(providers)
    table.sort(names)
    return names
end

---@param color dapview.Color?
---@return integer?
local to_int = function(color)
    if type(color) == "string" then
        return tonumber(color:gsub("^#", ""), 16)
    end
    return color
end

---@param color integer?
---@return string?
local to_hex = function(color)
    return color and ("#%06x"):format(color)
end

---@param c integer
local channels = function(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

---`t` of `a` over `b`
---@param a dapview.Color
---@param b dapview.Color
---@param t number
---@return integer
M.blend = function(a, b, t)
    local ar, ag, ab = channels(assert(to_int(a)))
    local br, bg, bb = channels(assert(to_int(b)))
    local mix = function(x, y)
        return math.floor(x * t + y * (1 - t) + 0.5)
    end
    return mix(ar, br) * 65536 + mix(ag, bg) * 256 + mix(ab, bb)
end

---WCAG contrast ratio, from 1 (identical) to 21
---@param a integer
---@param b integer
local contrast = function(a, b)
    local luminance = function(c)
        local r, g, bl = channels(c)
        local lin = function(v)
            v = v / 255
            return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
        end
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl)
    end
    local la, lb = luminance(a), luminance(b)
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

---@param group string
---@return {fg?: integer, bg?: integer, bold?: boolean}
local resolve = function(group)
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = group, link = false })
    if not ok then
        return {}
    end
    if hl.reverse then
        hl.fg, hl.bg = hl.bg, hl.fg
    end
    return { fg = hl.fg, bg = hl.bg, bold = hl.bold }
end

---First non-nil `field` among `groups`
---@param field "fg"|"bg"
---@param groups string[]
local first = function(field, groups)
    for _, group in ipairs(groups) do
        local color = resolve(group)[field]
        if color then
            return color
        end
    end
end

---@param transparent boolean|"auto"
---@return dapview.ThemeContext
M.context = function(transparent)
    if transparent == "auto" then
        transparent = resolve("Normal").bg == nil
    end
    return {
        background = vim.o.background,
        colors_name = vim.g.colors_name,
        transparent = transparent --[[@as boolean]],
        get = function(group)
            local hl = resolve(group)
            return { fg = to_hex(hl.fg), bg = to_hex(hl.bg), bold = hl.bold }
        end,
    }
end

---Roles derived from the active colorscheme's standard groups. Every role is set.
---@param ctx dapview.ThemeContext
---@return dapview.ThemeRoles
M.auto = function(ctx)
    local dark = ctx.background ~= "light"
    local normal = resolve("Normal")
    local fg = normal.fg or (dark and 0xd0d0d0 or 0x202020)
    local bg = normal.bg or (dark and 0x101010 or 0xf8f8f8)

    -- A candidate surface must stay close to the editor background and keep text readable,
    -- which rules out inverted status lines like habamax's or the default scheme's
    local panel
    for _, group in ipairs({ "StatusLine", "Pmenu", "NormalFloat" }) do
        local candidate = resolve(group).bg
        if candidate and contrast(candidate, bg) <= 1.6 and contrast(fg, candidate) >= 4.5 then
            panel = candidate
            break
        end
    end
    panel = panel or M.blend(fg, bg, 0.06)

    -- Foreground and background come from the same group, so the pair is known to be legible
    local selected
    for _, group in ipairs({ "TabLineSel", "PmenuSel", "Visual" }) do
        local hl = resolve(group)
        local chip_fg = hl.fg or fg
        if hl.bg and hl.bg ~= panel and contrast(chip_fg, hl.bg) >= 3 then
            selected = { fg = chip_fg, bg = hl.bg }
            break
        end
    end
    selected = selected or { fg = bg, bg = fg }

    local accent = first("fg", { "Function", "Identifier" }) or fg
    local muted = first("fg", { "Comment", "NonText" }) or M.blend(fg, bg, 0.5)
    local warn = first("fg", { "DiagnosticWarn", "WarningMsg" }) or accent
    local constant = first("fg", { "Constant" }) or accent
    local number = first("fg", { "Number" }) or constant

    ---@type dapview.ThemeRoles
    local roles = {
        fg = fg,
        muted = muted,
        panel = panel,
        selection = first("bg", { "Visual", "PmenuSel", "CursorLine" }) or M.blend(fg, bg, 0.2),
        accent = accent,
        selected = selected,
        ok = first("fg", { "DiagnosticOk", "String" }) or accent,
        warn = warn,
        error = first("fg", { "DiagnosticError", "Error", "ErrorMsg" }) or warn,
        changed = warn,
        raw = muted,
        decoded = accent,
        header = fg,
        string = first("fg", { "String" }) or fg,
        number = number,
        float = first("fg", { "Float" }) or number,
        boolean = first("fg", { "Boolean" }) or constant,
        constant = constant,
        ["function"] = first("fg", { "Function" }) or accent,
    }

    for role, color in pairs(roles) do
        if type(color) == "table" then
            roles[role] = { fg = to_hex(color.fg), bg = to_hex(color.bg) }
        else
            roles[role] = to_hex(color)
        end
    end

    return roles
end

local warned = {}

---@param message string
local warn_once = function(message)
    if not warned[message] then
        warned[message] = true
        vim.notify("nvim-dap-view: " .. message, vim.log.levels.WARN)
    end
end

---@param color any
---@return string? hex `nil` when `color` is not a color name, `"#rrggbb"` or a 24-bit integer
local normalize = function(color)
    if type(color) == "number" then
        return color >= 0 and color <= 0xffffff and color % 1 == 0 and to_hex(color) or nil
    end
    if type(color) == "string" then
        local value = api.nvim_get_color_by_name(color)
        return value ~= -1 and to_hex(value) or nil
    end
end

---Roles come from user config and third-party providers: an invalid value keeps the current one
---@param roles dapview.ThemeRoles
---@param layer table
---@param source string
local merge = function(roles, layer, source)
    for role, value in pairs(layer) do
        local current = roles[role]
        if current == nil then
            warn_once(("%s: unknown theme role '%s'"):format(source, tostring(role)))
        elseif role == "selected" and type(value) == "table" then
            for _, key in ipairs({ "fg", "bg" }) do
                if value[key] ~= nil then
                    local color = normalize(value[key])
                    if color then
                        current[key] = color
                    else
                        warn_once(
                            ("%s: invalid color for selected.%s: %s"):format(source, key, vim.inspect(value[key]))
                        )
                    end
                end
            end
        else
            local color = role ~= "selected" and normalize(value)
            if color then
                roles[role] = color
            else
                warn_once(("%s: invalid color for %s: %s"):format(source, role, vim.inspect(value)))
            end
        end
    end
end

---Roles for the configured theme: auto, then the provider, then the overrides for the active colorscheme
---@param config dapview.ConfigStrict
---@param ctx dapview.ThemeContext
---@return dapview.ThemeRoles
M.resolve = function(config, ctx)
    local roles = M.auto(ctx)

    local provider = config.theme
    if type(provider) == "string" and provider ~= "auto" then
        local name = provider
        provider = providers[name]
        if not provider then
            warn_once("unknown theme '" .. name .. "', using 'auto'")
        end
    end

    if type(provider) == "function" then
        local ok, result = pcall(provider, ctx)
        if ok and type(result) == "table" then
            merge(roles, result, "theme")
        else
            warn_once("theme provider failed: " .. tostring(result))
        end
    end

    local overrides = ctx.colors_name and (config.theme_overrides or {})[ctx.colors_name]
    if overrides then
        merge(roles, overrides, "theme_overrides." .. ctx.colors_name)
    end

    return roles
end

return M
