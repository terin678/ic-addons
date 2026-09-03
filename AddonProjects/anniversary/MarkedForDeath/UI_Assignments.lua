-- The shared assignment panel: the current pack's icon, job and owner, driven
-- by the authority's published map so every addon user sees the same thing.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Assignments = MFD.UI.Assignments or {}
local Panel = MFD.UI.Assignments

local ROW_HEIGHT = 20            -- pixels
local MAX_ROWS = 8               -- one per icon
local REFRESH_SECONDS = 0.5      -- repaint cadence while shown

-- Kill icons first, matching how the raid reads a pack. Cosmetic only.
local ICON_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

local frame
local rows = {}
local accumulator = 0

local function buildRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.texture = row:CreateTexture(nil, "ARTWORK")
    row.texture:SetSize(16, 16)
    row.texture:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.texture, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.text:SetJustifyH("LEFT")
end

-- Repaints from the published map. Sorted by icon display order, so the
-- panel reads the same way every pull regardless of which mob was seen first.
function Panel:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    local byIcon = {}
    for key, icon in pairs(MFD.Marker.published) do
        byIcon[icon] = key
    end

    local index = 0
    for _, icon in ipairs(ICON_ORDER) do
        local key = byIcon[icon]
        if key then
            index = index + 1
            local row = MFD.UI.AcquireRow(frame.body, rows, index, ROW_HEIGHT)
            buildRow(row)
            SetRaidTargetIconTexture(row.texture, icon)

            local detail = MFD.Marker.publishedDetail[key] or {}
            local label = MFD.Seats.INTENTS[detail.intent] and MFD.Seats.INTENTS[detail.intent].label or tostring(detail.intent)
            local learned = MFD.db.learnedMobs[MFD.H.NpcIDFromKey(key)]
            local mobName = learned and learned.name or ("npc " .. tostring(MFD.H.NpcIDFromKey(key)))

            row.text:SetText(string.format("%s  |cff999999%s|r%s",
                label, mobName, detail.owner and ("  |cff66ff66" .. detail.owner .. "|r") or ""))
        end
    end

    MFD.UI.ReleaseRows(rows, index + 1)

    if index == 0 then
        frame.empty:SetText("|cff999999nothing assigned|r")
    else
        frame.empty:SetText("")
    end
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    MFD.charDb.windows.assignments = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition()
    local saved = MFD.charDb.windows.assignments
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 100)
    end
end

local function build()
    frame = CreateFrame("Frame", "MarkedForDeathAssignmentsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 30 + MAX_ROWS * ROW_HEIGHT + 16)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetFrameStrata("MEDIUM")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.title:SetText("Assignments")

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -26)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.empty:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 8, -8)

    -- Repaint on a cadence rather than per published message, so a burst of
    -- republishes costs one paint. Only runs while shown.
    frame:SetScript("OnUpdate", function(_, elapsed)
        accumulator = accumulator + elapsed
        if accumulator >= REFRESH_SECONDS then
            accumulator = 0
            Panel:Refresh()
        end
    end)

    restorePosition()
    tinsert(UISpecialFrames, "MarkedForDeathAssignmentsFrame")
end

function Panel:Toggle()
    if not frame then
        build()
    end

    if frame:IsShown() then
        frame:Hide()
        return
    end

    frame:Show()
    Panel:Refresh()
end

_G.MarkedForDeath = MFD
