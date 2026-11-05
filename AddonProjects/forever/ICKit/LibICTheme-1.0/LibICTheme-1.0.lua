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
    Theme.OnChange(fn)          -> stop()    fn(theme, name)
    Theme.Hex(color)            -> "|cffrrggbb"

theme = { name, label, logo, colors = { role = { r, g, b, a } }, fonts = { role = "FontObject" } }

Colour roles: ground (a panel), raised (a title bar), field (somewhere to type or tick),
edge, text, textDim, textDisabled, done (a finished line), accent, accentHover, accentText,
danger, dangerHover, dangerText, button, buttonHover, buttonText, hover, selected, check, and
the status text roles good, warn and bad (green, amber, red, each readable as text on the
theme's ground: danger is a button fill and is not).
Font roles: body, title, small, button.

This library creates no frames and calls nothing in the client, so it is tested headless.
It ships three themes:

    Forever           the default: the game's own look, near-black panels, bronze edges, gold
    Impulse Control   the guild's navy, gold and bone, for members who want it
    Paper             dark ink on a yellow sticky note
]]

local MAJOR, MINOR = "LibICTheme-1.0", 2
local Theme = LibStub:NewLibrary(MAJOR, MINOR)
if not Theme then return end

Theme.DEFAULT = "Forever"
Theme.themes = Theme.themes or {}
Theme.listeners = Theme.listeners or {}

local selected

local function C(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end

--[[
The default theme, and every role a widget may ask for. A registered theme overrides what
it wants to and inherits the rest, so a role added here never leaves an older theme
without it.

The colours are modelled on the game's own interface rather than on any guild's: the warm
near-black of its panels, the bronze of its frame edges, and its gold (1, 0.82, 0), which
is the client's NORMAL_FONT_COLOR. They are written out here, not read from the client,
because this library calls nothing in it.
]]
local BASE = {
    label = "Forever",
    logo = false,
    colors = {
        ground = C(0.055, 0.047, 0.039, 0.93),
        raised = C(0.165, 0.122, 0.071, 1),
        field = C(0.020, 0.018, 0.016, 1),
        edge = C(0.560, 0.450, 0.250, 0.90),
        text = C(0.960, 0.940, 0.880),
        textDim = C(0.680, 0.640, 0.560),
        textDisabled = C(0.500, 0.500, 0.500),
        done = C(0.520, 0.490, 0.420),
        accent = C(1, 0.82, 0),
        accentHover = C(1, 0.90, 0.36),
        accentText = C(0.100, 0.070, 0.020),
        danger = C(0.600, 0.110, 0.080),
        dangerHover = C(0.760, 0.170, 0.120),
        dangerText = C(1, 0.920, 0.760),
        button = C(0.215, 0.165, 0.105),
        buttonHover = C(0.320, 0.245, 0.150),
        buttonText = C(1, 0.82, 0),
        hover = C(1, 0.82, 0, 0.10),
        selected = C(1, 0.82, 0, 0.22),
        check = C(1, 0.82, 0),
        good = C(0.400, 0.860, 0.400),
        warn = C(1, 0.600, 0.200),
        bad = C(1, 0.380, 0.320),
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
    -- A theme with a mark of its own names its texture; the rest have none.
    theme.logo = def.logo or false
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

-- "|cffffd100" for chat and for text that takes a colour code.
function Theme.Hex(color)
    return string.format("|cff%02x%02x%02x",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- The themes that ship
--------------------------------------------------------------------------------

Theme.Register("Forever", {})

-- The guild's colours, sampled from its mark: for members who want their addons to
-- look like the Anniversary set.
Theme.Register("Impulse Control", {
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
        good = C(0.470, 0.850, 0.470),
        warn = C(1, 0.560, 0.160),
        bad = C(1, 0.420, 0.360),
    },
})

-- A yellow sticky note: dark ink on paper.
Theme.Register("Paper", {
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
        good = C(0.100, 0.440, 0.120),
        warn = C(0.640, 0.300, 0),
        bad = C(0.700, 0.100, 0.080),
        selected = C(0.80, 0.45, 0.10, 0.25),
        check = C(0.45, 0.28, 0.05),
    },
})
