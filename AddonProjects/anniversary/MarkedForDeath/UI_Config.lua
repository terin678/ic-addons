-- Seat editor. Frames are built lazily on first Toggle and reused from a pool
-- on every refresh, never created and destroyed per row.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Config = MFD.UI.Config or {}
local Config = MFD.UI.Config

local ROW_HEIGHT = 24   -- pixels

-- Display order: kill icons first, then sheep, then banish, matching how the
-- raid reads a pack. Cosmetic only; the seat plan itself is keyed by icon.
local ICON_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

-- Returns a reusable row from pool, creating it only when the pool is short.
-- Shared by every list in the addon so no list churns frames on refresh.
function MFD.UI.AcquireRow(parent, pool, index, height)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(height)
        row:SetPoint("LEFT", parent, "LEFT", 8, 0)
        row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        pool[index] = row
    end
    row:SetPoint("TOP", parent, "TOP", 0, -((index - 1) * height) - 8)
    row:Show()
    return row
end

-- Hides every pooled row from index onward, so a shorter refresh does not leave
-- stale rows on screen.
function MFD.UI.ReleaseRows(pool, fromIndex)
    for i = fromIndex, #pool do
        if pool[i] then
            pool[i]:Hide()
        end
    end
end

local frame
local rows = {}

local function intentNames()
    local names = {}
    for intent in pairs(MFD.Seats.INTENTS) do
        names[#names + 1] = intent
    end
    table.sort(names)
    return names
end

-- Cycles an icon's intent to the next one alphabetically, keeping its ordinal.
local function cycleIntent(icon)
    local names = intentNames()
    local seat = MFD.db.seatPlan[icon]
    local current = seat and seat.intent
    local nextIndex = 1

    for i, name in ipairs(names) do
        if name == current then
            nextIndex = (i % #names) + 1
            break
        end
    end

    MFD.db.seatPlan[icon] = MFD.db.seatPlan[icon] or { ordinal = 1 }
    MFD.db.seatPlan[icon].intent = names[nextIndex]
end

-- Moves an icon's ordinal within its intent. Ordinals are renumbered from 1 so
-- two seats of one intent never share a number.
local function shiftOrdinal(icon, delta)
    local plan = MFD.db.seatPlan
    local seat = plan[icon]
    if not seat then
        return
    end

    local siblings = {}
    for otherIcon, other in pairs(plan) do
        if other.intent == seat.intent then
            siblings[#siblings + 1] = { icon = otherIcon, seat = other }
        end
    end

    table.sort(siblings, function(a, b)
        if a.seat.ordinal ~= b.seat.ordinal then
            return a.seat.ordinal < b.seat.ordinal
        end
        return a.icon < b.icon
    end)

    local index
    for i, s in ipairs(siblings) do
        if s.icon == icon then
            index = i
            break
        end
    end

    local target = index + delta
    if target < 1 or target > #siblings then
        return
    end

    siblings[index], siblings[target] = siblings[target], siblings[index]

    for i, s in ipairs(siblings) do
        s.seat.ordinal = i
    end
end

local function buildRow(row, icon)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.texture = row:CreateTexture(nil, "ARTWORK")
    row.texture:SetSize(18, 18)
    row.texture:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

    row.intentText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.intentText:SetPoint("LEFT", row.texture, "RIGHT", 8, 0)
    row.intentText:SetWidth(120)
    row.intentText:SetJustifyH("LEFT")

    row.cycle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.cycle:SetSize(64, 20)
    row.cycle:SetPoint("LEFT", row.intentText, "RIGHT", 4, 0)
    row.cycle:SetText("Intent")
    row.cycle:SetScript("OnClick", function()
        cycleIntent(icon)
        Config:Refresh()
    end)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetSize(24, 20)
    row.up:SetPoint("LEFT", row.cycle, "RIGHT", 4, 0)
    row.up:SetText("^")
    row.up:SetScript("OnClick", function()
        shiftOrdinal(icon, -1)
        Config:Refresh()
    end)

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetSize(24, 20)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetText("v")
    row.down:SetScript("OnClick", function()
        shiftOrdinal(icon, 1)
        Config:Refresh()
    end)

    row.pinBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.pinBox:SetSize(110, 20)
    row.pinBox:SetPoint("LEFT", row.down, "RIGHT", 14, 0)
    row.pinBox:SetAutoFocus(false)
    row.pinBox:SetScript("OnEnterPressed", function(box)
        local text = string.gsub(box:GetText(), "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        MFD.db.seatPlan[icon] = MFD.db.seatPlan[icon] or { intent = "KILL", ordinal = 1 }
        MFD.db.seatPlan[icon].pin = text ~= "" and text or nil
        box:ClearFocus()
        Config:Refresh()
    end)
    row.pinBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        Config:Refresh()
    end)

    row.ownerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ownerText:SetPoint("LEFT", row.pinBox, "RIGHT", 10, 0)
    row.ownerText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.ownerText:SetJustifyH("LEFT")
end

-- Repaints every row from the current seat plan and the live roster, so the
-- Owner column shows who actually holds each seat right now.
function Config:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    local resolved = MFD.Seats.Resolve(MFD.db.seatPlan, MFD.Marker.CurrentRoster())

    for index, icon in ipairs(ICON_ORDER) do
        local row = MFD.UI.AcquireRow(frame.body, rows, index, ROW_HEIGHT)
        buildRow(row, icon)

        local seat = MFD.db.seatPlan[icon]
        SetRaidTargetIconTexture(row.texture, icon)

        if seat then
            local label = MFD.Seats.INTENTS[seat.intent] and MFD.Seats.INTENTS[seat.intent].label or seat.intent
            row.intentText:SetText(label .. " " .. seat.ordinal)
        else
            row.intentText:SetText("|cff999999unbound|r")
        end

        if not row.pinBox:HasFocus() then
            row.pinBox:SetText(seat and seat.pin or "")
        end

        local record = resolved.byIcon[icon]
        if not record then
            row.ownerText:SetText("|cff999999no seat|r")
        elseif record.owner == true then
            row.ownerText:SetText("|cff66ff66always available|r")
        elseif record.owner then
            row.ownerText:SetText("|cff66ff66" .. record.owner .. "|r")
        else
            row.ownerText:SetText("|cffff4444nobody in the group can do this|r")
        end
    end

    MFD.UI.ReleaseRows(rows, #ICON_ORDER + 1)
end

local function build()
    frame = CreateFrame("Frame", "MarkedForDeathConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 260)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.title:SetText("Marked For Death: seats")

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -30)
    frame.header:SetText("icon      job                    change   order      pinned player          owner right now")

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -42)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

    -- The roster changes under an open window; repaint so the owner column
    -- stays truthful without the player needing to close and reopen it.
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function()
        Config:Refresh()
    end)

    tinsert(UISpecialFrames, "MarkedForDeathConfigFrame")
end

function Config:Toggle()
    if not frame then
        build()
    end

    if frame:IsShown() then
        frame:Hide()
        return
    end

    frame:Show()
    Config:Refresh()
end

_G.MarkedForDeath = MFD
