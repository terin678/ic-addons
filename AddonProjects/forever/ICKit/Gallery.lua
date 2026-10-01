local addonName, ns = ...

--[[
/ickit gallery: one of every widget, on screen, in the current theme.

It exists to be looked at. The cases can say a widget constructs and keeps its state; only
a person can say it looks right, drags properly and takes keys the way an edit box should.
It is also the first worked example of the widgets: a movable panel with a title bar that
drags it, a position saved per character as fractions of the screen, a menu, a confirm.
]]

local Util = LibStub("LibICUtil-1.0")
local Theme = LibStub("LibICTheme-1.0")
local W = LibStub("LibICWidgets-1.0")

local Gallery = {}
ns.Gallery = Gallery

local WIDTH, HEIGHT = 300, 262
local frame

local function TitleText()
    local _, name = Theme.Current()
    return "ICKit widgets: " .. name
end

-- One tick box per theme; picking one selects and saves it.
local function ThemeItems()
    local items = { { title = "Theme" } }
    for _, name in ipairs(Theme.Names()) do
        items[#items + 1] = {
            text = name,
            checked = function() return select(2, Theme.Current()) == name end,
            onClick = function() ns.SetTheme(name) end,
        }
    end
    return items
end

local function Build()
    local p = W.Panel(UIParent, {
        width = WIDTH, height = HEIGHT, movable = true, strata = "MEDIUM",
        onMoved = function(self)
            local fx, fy = W.GetPlace(self)
            if fx and ns.cdb then ns.cdb.gallery = { x = fx, y = fy } end
        end,
    })

    local bar = W.Panel(p, { role = "raised", edge = false, height = 24 })
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, p)

    p.title = W.Label(bar, TitleText(), { font = "title", color = "accent" })
    p.title:SetPoint("LEFT", bar, "LEFT", 8, 0)

    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() p:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    -- The three button kinds
    local x = 12
    for _, pair in ipairs({ { "Normal", "normal" }, { "Accent", "accent" }, { "Danger", "danger" } }) do
        local b = W.Button(p, pair[1], 86, 22, {
            kind = pair[2],
            onClick = function() ns.Print(pair[1] .. " button clicked.") end,
        })
        b:SetPoint("TOPLEFT", p, "TOPLEFT", x, -36)
        x = x + 95
    end

    -- A line to tick off: the label dims when the box is ticked
    local line
    local box = W.CheckBox(p, {
        onClick = function(checked) line:SetRole(checked and "done" or "text") end,
    })
    box:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -72)
    line = W.Label(p, "A line you can tick off")
    line:SetPoint("LEFT", box, "RIGHT", 8, 0)
    W.Tooltip(box, function(tip) tip:AddLine("Tick it") end)

    local edit = W.EditBox(p, WIDTH - 24, 20, {
        maxBytes = 120,
        placeholder = "Type here and press Enter",
        onEnter = function(text, self)
            ns.Print("you typed: " .. Util.Clean(text, 120))
            self:SetText("")
            self:ClearFocus()
        end,
    })
    edit:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -100)

    local themeButton = W.Button(p, "Theme...", 86, 22, {
        onClick = function(self)
            if not W.Menu(self, ThemeItems()) then ns.Print("this client has no context menu.") end
        end,
    })
    themeButton:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -134)

    local confirm = W.Button(p, "Confirm...", 86, 22, {
        onClick = function()
            W.Confirm("Delete this note?\n\n(Nothing is deleted. This is the gallery.)",
                function() ns.Print("confirmed.") end)
        end,
    })
    confirm:SetPoint("LEFT", themeButton, "RIGHT", 9, 0)

    -- A slider, and a choice picked from a menu
    local slider = W.Slider(p, {
        width = WIDTH - 24, min = 0.3334, max = 2, step = 0.01, value = 1,
        format = function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end,
        onChange = function(value) ns.Debug("slider at " .. value) end,
    })
    slider:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -166)

    local choice = W.Choice(p, 140, 22, {
        choices = { { 0, "None" }, { 1, "Low" }, { 2, "Medium" }, { 3, "High" } }, value = 2,
        onChange = function(value) ns.Print("choice " .. value .. " picked.") end,
    })
    choice:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -194)

    local foot = W.Label(p, "Drag the title bar. The position is kept per character.", { font = "small", color = "textDim" })
    foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 10)

    Theme.OnChange(function() p.title:SetText(TitleText()) end)
    return p
end

function Gallery.Toggle()
    if not frame then
        frame = Build()
        local place = ns.cdb and ns.cdb.gallery
        W.SetPlace(frame, place and place.x or 0.36, place and place.y or 0.28)
        frame:Show()
        return true
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
    return frame:IsShown()
end
