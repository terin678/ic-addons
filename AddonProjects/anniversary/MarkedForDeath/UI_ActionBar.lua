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
local TITLE_HEIGHT = 14        -- pixels for the drag strip
local REFRESH_SECONDS = 0.5    -- how often the stateful buttons repaint

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
    frame = CreateFrame("Frame", "MarkedForDeathActionBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.55)

    -- A thin strip along the top to grab, so dragging never means clicking a
    -- button by accident. The whole bar is draggable too when it is unlocked,
    -- but the strip is the part that is always safe.
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -2)
    frame.title:SetText("Marked For Death")

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

    local isLocked = settings().isLocked
    frame.grip:SetShown(not isLocked)
    frame.title:SetText(isLocked and "" or "Marked For Death")
    frame.bg:SetColorTexture(0, 0, 0, isLocked and 0.3 or 0.55)
end

function Bar:SetShown(isShown)
    settings().isShown = isShown and true or false

    if isShown then
        if not frame then
            build()
        end
        frame:Show()
    elseif frame then
        frame:Hide()
    end
end

function Bar:Toggle()
    Bar:SetShown(not settings().isShown)
    MFD.Print("action bar " .. (settings().isShown and "shown" or "hidden"))
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
    if settings().isShown then
        Bar:SetShown(true)
    end
end)

_G.MarkedForDeath = MFD
