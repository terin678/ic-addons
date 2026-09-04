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

-- Every place this panel is drawn: the floating window and, once opened, the
-- tab in the main window. Each view carries its own row pool, so the two can
-- be on screen at once without fighting over widgets.
local views = {}
local frame
local accumulator = 0

-- Each view owns a table of its own, because a table's column geometry is
-- computed once against the frame it is built in and the floating panel and the
-- tab are different widths.
local function addView(container, top)
    container.table = MFD.UI.Table(container, {
        top = top or 0,
        bottom = 0,
        rowHeight = ROW_HEIGHT,
        columns = {
            { key = "icon", label = "", width = 22, type = "texture" },
            { key = "job", label = "Job", width = 62 },
            { key = "mob", label = "Mob", width = "flex" },
            { key = "owner", label = "Who", width = 84 },
        },
    })
    views[#views + 1] = container
    return container
end

-- The published map as a list, in icon display order, so the panel reads the
-- same way every pull regardless of which mob was seen first. Pure.
local function assignmentList()
    local byIcon = {}
    for key, icon in pairs(MFD.Marker.published) do
        byIcon[icon] = key
    end

    local list = {}
    for _, icon in ipairs(ICON_ORDER) do
        local key = byIcon[icon]
        if key then
            local detail = MFD.Marker.publishedDetail[key] or {}
            local npcID = MFD.H.NpcIDFromKey(key)
            local learned = MFD.db.learnedMobs[npcID]
            local def = MFD.Roles.INTENTS[detail.intent]

            list[#list + 1] = {
                icon = icon,
                job = (def and def.label) or tostring(detail.intent),
                mob = learned and learned.name or ("npc " .. tostring(npcID)),
                owner = detail.owner,
            }
        end
    end

    return list
end

local function paint(view)
    local list = assignmentList()

    view.table:Render(list, function(row, item)
        SetRaidTargetIconTexture(row.cells.icon, item.icon)
        view.table:Set(row, "job", item.job)
        view.table:Set(row, "mob", item.mob, { r = 0.6, g = 0.6, b = 0.6 })
        view.table:Set(row, "owner", item.owner or "", { r = 0.4, g = 1, b = 0.4 })
    end)

    view.empty:SetText(#list == 0 and "|cff999999nothing assigned|r" or "")
end

-- Repaints every view that is actually on screen.
function Panel:Refresh()
    for _, view in ipairs(views) do
        if view:IsShown() then
            paint(view)
        end
    end
end

-- Builds the panel into a container the main window owns, alongside the
-- floating one rather than instead of it.
function Panel:BuildInto(container)
    container.empty = MFD.UI.Label(container, "")
    container.empty:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -24)

    addView(container, 0)
end

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    MFD.cdb.windows.assignments = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition()
    local saved = MFD.cdb.windows.assignments
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 100)
    end
end

local function build()
    -- The library's window: guild palette, the mark, a close button and the
    -- dragging, none of it painted here.
    frame = MFD.UI.Window("MarkedForDeathAssignmentsFrame", {
        width = 300,
        height = 30 + MAX_ROWS * ROW_HEIGHT + 16,
        title = "Assignments",
        status = false,
        strata = "FULLSCREEN_DIALOG",
        scalable = true,
        onScaleChanged = function(_, scale)
            MFD.cdb.windows.assignments = MFD.cdb.windows.assignments or {}
            MFD.cdb.windows.assignments.scale = scale
        end,
    })

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    frame.empty = MFD.UI.Label(frame, "")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -54)

    local saved = MFD.cdb.windows.assignments
    if frame.SetWindowScale and saved and saved.scale then
        frame:SetWindowScale(saved.scale, true)
    end

    restorePosition()
    -- Below the library's title bar, which owns the top of the window.
    addView(frame, -34)
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
    frame:Raise()
    Panel:Refresh()
end

-- One repaint driver for every view, rather than an OnUpdate on the floating
-- window. That script only ran while the floating window was open, so the tab
-- version of this panel went stale whenever it was the only one on screen, and
-- its rows would sit at whatever the last paint left. Paint is a cadence rather
-- than a response to each published message so a burst of republishes costs one
-- paint, and Refresh skips every view that is hidden.
MFD.RegisterInit(function()
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        accumulator = accumulator + elapsed
        if accumulator >= REFRESH_SECONDS then
            accumulator = 0
            Panel:Refresh()
        end
    end)
end)

_G.MarkedForDeath = MFD
