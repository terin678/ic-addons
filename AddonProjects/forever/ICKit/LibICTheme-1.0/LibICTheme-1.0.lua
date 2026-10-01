--[[
LibICTheme-1.0
Layer 1 of ICKit: the theme registry. A theme is a table of named roles, never a widget's
own colours: a widget asks for "ground" or "accent" and draws whatever the selected theme
says that is. Switching theme repaints everything that asked.

    local Theme = LibStub("LibICTheme-1.0")

    Theme.Register(name, def)   -> theme     missing roles are filled from the default
    Theme.Get(name)             -> theme or nil
    Theme.Current()             -> theme, name
    Theme.Select(name)          -> ok        runs every OnChange listener when it changes
    Theme.Find(text)            -> name      what a player typed, matched without case
    Theme.Names()               -> sorted list
    Theme.OnChange(fn)          fn(theme, name)
    Theme.Hex(color)            -> "|cffrrggbb"

theme = { name, label, logo, colors = { role = { r, g, b, a } }, fonts = { role = "FontObject" } }

Colour roles: ground (a panel), raised (a title bar), field (somewhere to type or tick),
edge, text, textDim, textDisabled, done (a finished line), accent, accentHover, accentText,
danger, dangerHover, dangerText, button, buttonHover, buttonText, hover, selected, check.
Font roles: body, title, small, button.

This library creates no frames and calls nothing in the client, so it is tested headless.
It ships three themes: "Impulse Control" (the default), "Plain" and "Paper".
]]

local MAJOR, MINOR = "LibICTheme-1.0", 1
local Theme = LibStub:NewLibrary(MAJOR, MINOR)
if not Theme then return end

Theme.DEFAULT = "Impulse Control"
Theme.themes = Theme.themes or {}
Theme.listeners = Theme.listeners or {}

local selected

local function C(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end

-- Every role a widget may ask for. A registered theme overrides what it wants to and
-- inherits the rest, so a new role added here never leaves an older theme without it.
local BASE = {
    label = "Impulse Control",
    logo = "Interface\\AddOns\\ICKit\\Textures\\ImpulseControl-64",
    colors = {
        ground = C(0.082, 0.137, 0.200, 0.96),      -- #152333 deep navy
        raised = C(0.098, 0.149, 0.216, 1),         -- #192637
        field = C(0.055, 0.094, 0.145, 1),
        edge = C(0.32, 0.42, 0.55, 0.9),
        text = C(0.957, 0.898, 0.757),              -- #F4E5C1 bone
        textDim = C(0.62, 0.66, 0.72),
        textDisabled = C(0.45, 0.47, 0.50),
        done = C(0.45, 0.50, 0.56),
        accent = C(0.875, 0.612, 0.200),            -- #DF9C33 gold
        accentHover = C(0.949, 0.702, 0.302),
        accentText = C(0.082, 0.137, 0.200),
        danger = C(0.765, 0.251, 0.184),            -- #C3402F flame
        dangerHover = C(0.851, 0.341, 0.271),
        dangerText = C(0.957, 0.898, 0.757),
        button = C(0.145, 0.208, 0.298),
        buttonHover = C(0.220, 0.302, 0.412),
        buttonText = C(0.957, 0.898, 0.757),
        hover = C(1, 1, 1, 0.07),
        selected = C(0.875, 0.612, 0.200, 0.25),
        check = C(0.875, 0.612, 0.200),
    },
    fonts = {
        body = "GameFontHighlightSmall",
        title = "GameFontNormal",
        small = "GameFontDisableSmall",
        button = "GameFontNormalSmall",
    },
}

local function CopyColor(c)
    return { r = c.r, g = c.g, b = c.b, a = c.a or 1 }
end

function Theme.Register(name, def)
    assert(type(name) == "string" and name ~= "", "LibICTheme: a theme needs a name")
    def = def or {}
    local theme = { name = name, label = def.label or name, colors = {}, fonts = {} }
    -- `logo = false` is a theme saying it has none; nil inherits the default mark.
    if def.logo == nil then theme.logo = BASE.logo else theme.logo = def.logo end
    for role, color in pairs(BASE.colors) do
        theme.colors[role] = CopyColor((def.colors and def.colors[role]) or color)
    end
    for role, font in pairs(BASE.fonts) do
        theme.fonts[role] = (def.fonts and def.fonts[role]) or font
    end
    Theme.themes[name] = theme
    return theme
end

function Theme.Get(name)
    return Theme.themes[name]
end

-- The selected theme, or the default when nothing valid is selected.
function Theme.Current()
    local name = (selected and Theme.themes[selected]) and selected or Theme.DEFAULT
    return Theme.themes[name], name
end

-- One listener failing must not leave the rest unpainted.
local function Fire(theme, name)
    for _, fn in ipairs(Theme.listeners) do
        local ok, err = pcall(fn, theme, name)
        if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
    end
end

-- Returns whether the name is a theme. Listeners run only when the theme changed.
function Theme.Select(name)
    if not Theme.themes[name] then return false end
    local _, before = Theme.Current()
    selected = name
    if before ~= name then Fire(Theme.themes[name], name) end
    return true
end

-- A theme name from what a player typed: exact without case, else the one name it starts.
function Theme.Find(text)
    local want = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if want == "" then return nil end
    local prefixed
    for _, name in ipairs(Theme.Names()) do
        local lower = name:lower()
        if lower == want then return name end
        if lower:sub(1, #want) == want then
            if prefixed then return nil end     -- two names start this way: say neither
            prefixed = name
        end
    end
    return prefixed
end

function Theme.Names()
    local names = {}
    for name in pairs(Theme.themes) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Returns a function that stops the listening.
function Theme.OnChange(fn)
    Theme.listeners[#Theme.listeners + 1] = fn
    return function()
        for i, listener in ipairs(Theme.listeners) do
            if listener == fn then
                table.remove(Theme.listeners, i)
                return
            end
        end
    end
end

-- "|cffdf9c33" for chat and for text that takes a colour code.
function Theme.Hex(color)
    return string.format("|cff%02x%02x%02x",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- The themes that ship
--------------------------------------------------------------------------------

Theme.Register("Impulse Control", {})

-- Neutral charcoal with the game's own yellow: for a player who wants no guild's colours.
Theme.Register("Plain", {
    logo = false,
    colors = {
        ground = C(0.07, 0.07, 0.08, 0.92),
        raised = C(0.13, 0.13, 0.15, 1),
        field = C(0.03, 0.03, 0.04, 1),
        edge = C(0.40, 0.40, 0.42, 0.9),
        text = C(0.92, 0.92, 0.92),
        textDim = C(0.65, 0.65, 0.65),
        textDisabled = C(0.45, 0.45, 0.45),
        done = C(0.50, 0.50, 0.50),
        accent = C(1, 0.82, 0),
        accentHover = C(1, 0.90, 0.35),
        accentText = C(0.08, 0.08, 0.08),
        danger = C(0.70, 0.20, 0.20),
        dangerHover = C(0.82, 0.30, 0.30),
        dangerText = C(0.95, 0.95, 0.95),
        button = C(0.20, 0.20, 0.22),
        buttonHover = C(0.30, 0.30, 0.33),
        buttonText = C(0.92, 0.92, 0.92),
        selected = C(1, 0.82, 0, 0.22),
        check = C(1, 0.82, 0),
    },
})

-- A yellow sticky note: dark ink on paper.
Theme.Register("Paper", {
    logo = false,
    colors = {
        ground = C(0.98, 0.93, 0.56, 0.97),
        raised = C(0.94, 0.86, 0.40, 1),
        field = C(1, 0.97, 0.76, 1),
        edge = C(0.70, 0.60, 0.22, 1),
        text = C(0.16, 0.14, 0.08),
        textDim = C(0.40, 0.36, 0.22),
        textDisabled = C(0.58, 0.54, 0.40),
        done = C(0.55, 0.50, 0.32),
        accent = C(0.80, 0.45, 0.10),
        accentHover = C(0.90, 0.55, 0.18),
        accentText = C(1, 0.98, 0.90),
        danger = C(0.72, 0.22, 0.16),
        dangerHover = C(0.82, 0.32, 0.24),
        dangerText = C(1, 0.96, 0.90),
        button = C(0.90, 0.82, 0.38),
        buttonHover = C(0.84, 0.74, 0.28),
        buttonText = C(0.16, 0.14, 0.08),
        hover = C(0, 0, 0, 0.07),
        selected = C(0.80, 0.45, 0.10, 0.25),
        check = C(0.45, 0.28, 0.05),
    },
})
