-- The addon's whole contact with LibICUI.
--
-- Every other UI file goes through these wrappers, so the guild style is set
-- once here rather than at each of the several hundred call sites. That is the
-- point of the thin wrapper the standards ask for: when the palette or the row
-- height changes, one file changes.
--
-- This addon predates the private-namespace rule and still uses the single _G
-- table, deliberately and by agreement. Everything else here follows the
-- current shape.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
local UI = MFD.UI

local ICUI = LibStub("LibICUI-1.0")
UI.Lib = ICUI

-- The window opens at this size. Both are pixels.
UI.WIDTH, UI.HEIGHT = 940, 600
UI.PAGE_INSET = 10          -- pixels between the window edge and a page
UI.TAB_HEIGHT = 22          -- pixels
UI.ROW_HEIGHT = 18          -- pixels per list row

-- Registered once. Anything that wants the plain Blizzard look would set
-- theme = false here rather than painting a control by hand at its call site.
UI.Style = ICUI:Style("MarkedForDeath", {
    rowHeight = UI.ROW_HEIGHT,
    headerHeight = 18,
    font = "GameFontHighlightSmall",
    headerFont = "GameFontDisableSmall",
    pageWidth = UI.WIDTH - UI.PAGE_INSET * 2,
})

UI.PAGE_W = UI.WIDTH - UI.PAGE_INSET * 2

-- Each of these is the library call with this addon's style already attached,
-- so no caller has to remember to pass it and none of them can disagree.
local function withStyle(opts)
    opts = opts or {}
    opts.style = UI.Style
    return opts
end

function UI.Button(parent, text, w, h, opts)
    return ICUI:Button(parent, text, w, h, withStyle(opts))
end

function UI.EditBox(parent, w, h, opts)
    return ICUI:EditBox(parent, w, h, withStyle(opts))
end

function UI.TextBox(parent, w, h, opts)
    return ICUI:TextBox(parent, w, h, withStyle(opts))
end

function UI.CheckBox(parent, label, opts)
    return ICUI:CheckBox(parent, label, withStyle(opts))
end

function UI.Table(parent, opts)
    return ICUI:Table(parent, withStyle(opts))
end

function UI.Toolbar(parent, opts)
    return ICUI:Toolbar(parent, withStyle(opts))
end

function UI.Panel(parent, opts)
    return ICUI:Panel(parent, withStyle(opts))
end

function UI.Window(name, opts)
    return ICUI:Window(name, withStyle(opts))
end

function UI.TabStrip(parent, opts)
    return ICUI:TabStrip(parent, withStyle(opts))
end

function UI.ScrollList(parent, top, bottom, right)
    return ICUI:ScrollList(parent, top, bottom, right)
end

function UI.Tooltip(widget, builder)
    return ICUI:Tooltip(widget, builder)
end

function UI.Age(seconds)
    return ICUI:Age(seconds)
end

function UI.Hex(color)
    return ICUI:Hex(color)
end

-- A plain label. Not a library call, but every page wants one and each writing
-- its own three lines is how fonts drift apart.
function UI.Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

_G.MarkedForDeath = MFD
