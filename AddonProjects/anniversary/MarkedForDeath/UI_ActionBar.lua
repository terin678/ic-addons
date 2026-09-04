-- The action bar: the mid-pull controls as a bar you park where you want.
--
-- Separate from every other window on purpose. This is the one surface meant to
-- be on screen with a boss on you, so it drags anywhere, resizes to whatever
-- shape fits your layout, and reflows its buttons to match: one long row along
-- the bottom, a block above your action bars, a vertical strip down the side.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.ActionBar = MFD.UI.ActionBar or {}
local Bar = MFD.UI.ActionBar

local PADDING = 8              -- pixels around the buttons
local TITLE_HEIGHT = 16        -- pixels for the drag strip
local REFRESH_SECONDS = 0.5    -- how often the stateful buttons repaint

-- Should the bar be on screen? Takes the settings and what GetInstanceInfo
-- reports for the zone. Pure.
--
-- These are buttons for running a raid. Outside one they are a box sitting on
-- the screen while you post auctions, so by default the bar goes away with the
-- job it is for and comes back when you zone in.
function Bar.ShouldShow(settings, zoneType)
    if not settings or not settings.isShown then
        return false
    end

    if not settings.onlyInRaid then
        return true
    end

    return zoneType == "raid"
end

local frame

local function settings()
    return MFD.db.settings.actionBar
end

local function saveGeometry()
    local point, _, relativePoint, x, y = frame:GetPoint()
    MFD.charDb.windows.actionBar = {
        point = point, relativePoint = relativePoint, x = x, y = y,
        width = frame:GetWidth(), height = frame:GetHeight(),
    }
end

-- Places the buttons for the current width and, when the bar is not being
-- dragged by its corner, snaps the height to exactly what they need. Resizing
-- is how you choose the shape: narrow it and the buttons wrap into more rows.
local function relayout(snapHeight)
    local width = frame:GetWidth() - PADDING * 2
    local needed = MFD.Actions.LayoutBar(frame, width, PADDING, -(PADDING + TITLE_HEIGHT))

    if snapHeight then
        frame:SetHeight(needed + PADDING * 2 + TITLE_HEIGHT)
    end
end

local function build()
    frame = CreateFrame("Frame", "MarkedForDeathActionBar", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)

    -- The window ground and border from the guild palette, not a black
    -- rectangle at half alpha. This bar sits beside the addon's windows and
    -- should look like it came from the same place.
    local style = MFD.UI.Style
    MFD.UI.Lib:Skin(frame, style.windowBg, style.windowBorder)

    -- The guild mark, small, so the bar is identifiable at a glance among a
    -- screen full of other addons' furniture.
    -- Everything on the strip hangs off one centre line rather than each
    -- guessing its own offset from the top, which is what left the mark riding
    -- the border and the text sitting below it.
    local strip = -(TITLE_HEIGHT / 2) - 3

    frame.mark = MFD.UI.Lib:Logo(frame, 12)
    frame.mark:SetPoint("LEFT", frame, "TOPLEFT", PADDING, strip)

    -- A thin strip along the top to grab, so dragging never means clicking a
    -- button by accident. The whole bar is draggable too when it is unlocked,
    -- but the strip is the part that is always safe.
    frame.title = MFD.UI.Label(frame, "Marked For Death", "GameFontNormalSmall")
    frame.title:SetPoint("LEFT", frame.mark, "RIGHT", 5, 0)
    frame.title:SetTextColor(style.buttonText.r, style.buttonText.g, style.buttonText.b)

    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetMinResize then
        frame:SetMinResize(MFD.Actions.BUTTON_WIDTH + PADDING * 2,
            MFD.Actions.BUTTON_HEIGHT + PADDING * 2 + TITLE_HEIGHT)
    end

    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not settings().isLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveGeometry()
    end)

    -- A way to dismiss it from the bar itself. There were already four ways to
    -- hide this thing and not one of them was on the thing, which is the first
    -- place anybody looks.
    -- The same X the library puts on a window, so the bar closes the way every
    -- other surface in the addon does.
    frame.close = MFD.UI.Button(frame, "X", 16, 14, { kind = "danger" })
    frame.close:SetPoint("RIGHT", frame, "TOPRIGHT", -PADDING, strip)

    frame.close:SetScript("OnClick", function()
        Bar:SetShown(false)
        -- Say how to get it back in the same breath. A window that vanishes
        -- with no way back visible is a window you have lost.
        MFD.Print("action bar hidden. |cffffd100/mfd bar|r brings it back, "
            .. "or the minimap menu, or its keybind.")
    end)

    frame.close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Hide the action bar")
        GameTooltip:AddLine("/mfd bar brings it back, as does the minimap shift-click menu "
            .. "and its keybind under Key Bindings, Marked For Death.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.close:SetScript("OnLeave", function() GameTooltip:Hide() end)

    MFD.Actions.BuildBar(frame)

    -- The resize grip. Dragging it sets the width; the buttons rewrap to suit
    -- and the height follows them, so the bar cannot end up with a row of
    -- buttons hanging outside it.
    frame.grip = CreateFrame("Button", nil, frame)
    frame.grip:SetSize(16, 16)
    frame.grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    frame.grip:SetScript("OnMouseDown", function()
        if not settings().isLocked then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    frame.grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        relayout(true)
        saveGeometry()
    end)

    -- While the corner is being dragged the height follows the mouse, so the
    -- buttons are only re-placed, not snapped; the snap happens on release.
    frame:SetScript("OnSizeChanged", function()
        relayout(false)
    end)

    local accumulator = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        accumulator = accumulator + elapsed
        if accumulator >= REFRESH_SECONDS then
            accumulator = 0
            MFD.Actions.RefreshBar(frame)
        end
    end)

    local saved = MFD.charDb.windows.actionBar
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        -- Above where action bars usually sit, near the middle, so it is
        -- somewhere obvious the first time rather than somewhere to hunt for.
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end

    -- Wide enough for three across by default: visible without being a wall.
    frame:SetWidth((saved and saved.width)
        or (MFD.Actions.BUTTON_WIDTH * 3 + MFD.Actions.BUTTON_GAP * 2 + PADDING * 2))
    relayout(true)
    if saved and saved.height then
        frame:SetHeight(saved.height)
    end

    Bar:UpdateLock()
end

-- Locking hides the grip and refuses drags, so a bar you have positioned cannot
-- be shoved across the screen by a stray click mid-fight.
function Bar:UpdateLock()
    if not frame then
        return
    end

    -- Locked means the bar is furniture: nothing on its chrome can be clicked
    -- by accident mid-fight, the close button included. The command still works
    -- either way, so locking can never strand it on screen.
    local isLocked = settings().isLocked
    frame.grip:SetShown(not isLocked)
    frame.close:SetShown(not isLocked)
    frame.mark:SetShown(not isLocked)
    frame.title:SetShown(not isLocked)

    -- Locked, the bar recedes: same palette, less of it, so it reads as part of
    -- the UI rather than a window sitting on top of it.
    local style = MFD.UI.Style
    local ground = style.windowBg
    frame:SetBackdropColor(ground.r, ground.g, ground.b, isLocked and 0.55 or 0.96)
    local border = style.windowBorder
    frame:SetBackdropBorderColor(border.r, border.g, border.b, isLocked and 0.35 or 0.9)
end

-- Puts the bar on screen or takes it off, from whatever the settings and the
-- current zone say. Everything that could change the answer calls this.
function Bar:Evaluate()
    if not MFD.db then
        return
    end

    local ok, zoneType = pcall(function()
        local _, kind = GetInstanceInfo()
        return kind
    end)

    local wanted = Bar.ShouldShow(settings(), ok and zoneType or nil)

    if wanted then
        if not frame then
            build()
        end
        frame:Show()
    elseif frame then
        frame:Hide()
    end

    return wanted
end

function Bar:SetShown(isShown)
    settings().isShown = isShown and true or false
    Bar:Evaluate()
end

function Bar:Toggle()
    Bar:SetShown(not settings().isShown)

    if not settings().isShown then
        MFD.Print("action bar hidden")
        return
    end

    -- Turning it on outside a raid otherwise looks like the button did nothing.
    if not Bar:Evaluate() then
        MFD.Print("action bar shown, but it is set to raids only so it stays hidden until you zone in")
    else
        MFD.Print("action bar shown")
    end
end

-- Puts the bar back in the middle of the screen at its default size, for when
-- it has been dragged somewhere unreachable or off a monitor that is gone.
function Bar:Reset()
    MFD.charDb.windows.actionBar = nil
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
        frame:SetWidth(MFD.Actions.BUTTON_WIDTH * 3 + MFD.Actions.BUTTON_GAP * 2 + PADDING * 2)
        relayout(true)
        saveGeometry()
    end
    MFD.Print("action bar moved back to the middle")
end

MFD.RegisterInit(function()
    -- The same zone events and the same settle delay the combat log toggle
    -- uses, for the same reason: GetInstanceInfo is not reliable the instant a
    -- loading screen ends.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    local pending = false
    watcher:SetScript("OnEvent", function()
        if pending or not C_Timer then
            return
        end
        pending = true
        C_Timer.After(MFD.CombatLog.SETTLE_SECONDS, function()
            pending = false
            pcall(Bar.Evaluate, Bar)
        end)
    end)

    Bar:Evaluate()
end)

_G.MarkedForDeath = MFD
