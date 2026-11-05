local addonName, ns = ...

--[[
UI_Assignments: the assignment panel. Which icon goes on which mob and who holds the seat,
as a tab in the window and as a small floating panel to keep on screen through a pull
(/mfd assign). Both are drawn from the same rows; the pure helpers have cases in
Tests_UI.lua.

Owned by lane G (window and config). Frames are made only inside Build and the floating
panel's first showing; the ready hook returns early on IC_HEADLESS.

Where the plan comes from, first that answers:
    1. Lane B's provider (ns.UI.SetMarking): exactly what the Mark pack button holds.
    2. The Raid Lead's published plan (ns.Comms.Published), when that is someone else, so
       every panel in the raid agrees.
    3. A preview worked out here from the rules and seats of this instance, blind (each
       rule stands for one mob, as a press marks by name), with no icons lent.

THE MARKING SLOT (lane B). The tab's toolbar keeps a bar on the left for the Mark pack,
Clear and Re-mark buttons, and a one-line guide row under it for the Mark guide. Until
lane B hands a provider with BuildSlot to ns.UI.SetMarking, both say what they are for.

    UIAssignments.IconText(index, size)      a raid icon as an inline texture, or ""
    UIAssignments.Preview(plan, merged, members)  steps and the allocation, blind
    UIAssignments.Source(view)               which plan to show, and the words for it
    UIAssignments.Rows(steps)                list rows
    UIAssignments.Toggle()                   the floating panel
    UIAssignments.MarkingChanged()           ns.UI.SetMarking calls it

Layout of the tab, px from the page top: toolbar 0 (24 high: the marking bar, then
Announce and Float on the right), guide row 28 (18), source line 50, the list (header
above its scroll) from 70 to the page's bottom.
]]

ns.UIAssignments = ns.UIAssignments or {}
local UIA = ns.UIAssignments
local Seats, Allocator, MarkPlan = ns.Seats, ns.Allocator, ns.MarkPlan

local W = LibStub("LibICWidgets-1.0")
local Util = LibStub("LibICUtil-1.0")

local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"   -- the kit's own icon sheet
local ICON_SHEET = 256        -- px, that texture's side
local TOP_GUIDE, TOP_SOURCE, TOP_LIST = 28, 50, 70   -- px from the tab's top
local FLOAT_NAME = "MarkedForDeathAssignments"   -- named for UISpecialFrames
local FLOAT_W, FLOAT_TITLE, FLOAT_ROWS, ROW_H = 320, 24, 8, 18   -- px, rows
local AGE_TICK = 10           -- seconds between redraws of a published plan's age

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

function UIA.IconText(index, size)
    local l, r, t, b = W.RaidIconCoords(index)
    if not l then return "" end
    size = size or 14
    return string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t", RAID_ICONS, size, size, ICON_SHEET, ICON_SHEET,
        l * ICON_SHEET, r * ICON_SHEET, t * ICON_SHEET, b * ICON_SHEET)
end

-- plan: a seat plan; merged: the rule set in force; members: a roster's members.
-- Returns steps (MarkPlan.Steps) and the allocation (its unmet and skipped lists).
function UIA.Preview(plan, merged, members)
    local seats = Seats.Resolve(plan or {}, members or {})
    local alloc = Allocator.Blind(merged or {}, seats, { lend = false })
    return (MarkPlan.Steps(alloc)), alloc
end

--[[
view = {
    provided    steps from lane B, or nil
    providedText  its own words for them, or nil
    published   ns.Comms.Published(key): { from, at, steps }, or nil
    me          the player's name as Published names the sender
    now         time()
    preview     steps worked out here
    unmet       crowd control rules the preview could not seat (a count)
}
Returns steps, text, role.
]]
function UIA.Source(view)
    view = view or {}
    if type(view.provided) == "table" then
        return view.provided, view.providedText or "What Mark pack will place.", "good"
    end
    local pub = view.published
    if type(pub) == "table" and type(pub.steps) == "table" and pub.from ~= nil and pub.from ~= view.me then
        local age = (view.now and pub.at) and (", " .. ns.UI.Age(view.now - pub.at) .. " ago") or ""
        return pub.steps, "The Raid Lead's plan, from " .. tostring(pub.from) .. age .. ".", "good"
    end
    local text = "A preview from the rules here: Mark pack is not built yet."
    if (view.unmet or 0) > 0 then
        text = text .. " " .. view.unmet .. " crowd control " .. Util.Plural(view.unmet, "rule") .. " got no seat."
    end
    return view.preview or {}, text, "warn"
end

-- Returns { icon, seat, seatRole, mob, who, whoRole } per step, in step order.
function UIA.Rows(steps)
    local out = {}
    for i, step in ipairs(steps or {}) do
        local seat, seatRole = step.seatLabel or "", "text"
        if step.borrowed then seat, seatRole = "lent: Kill", "warn" end
        local who, whoRole
        if type(step.owner) == "string" then
            who, whoRole = step.owner, "good"
        elseif step.owner == false then
            who, whoRole = "nobody can", "bad"
        else
            who, whoRole = "anyone", "textDim"
        end
        out[i] = {
            icon = step.icon, iconName = step.iconName or Seats.ICON_NAMES[step.icon], seat = seat,
            seatRole = seatRole, mob = step.name or "", who = who, whoRole = whoRole,
        }
    end
    return out
end

--------------------------------------------------------------------------------
-- The data, gathered from the client
--------------------------------------------------------------------------------

local function Current()
    local key = ns.UI.Here()
    local merged = {}
    if ns.Comms and ns.Comms.ActiveRules then
        local ok, set = pcall(ns.Comms.ActiveRules, key)
        if ok and type(set) == "table" then merged = set end
    elseif ns.db and type(ns.db.rules[key]) == "table" then
        merged = ns.db.rules[key]
    end
    local roster = ns.UI.Roster()
    local preview, alloc = UIA.Preview((Seats.PlanFor(ns.db, key)), merged, roster and roster.members)

    local provided, providedText
    local provider = ns.UI.Marking()
    if provider and type(provider.Steps) == "function" then
        local ok, steps, _, text = pcall(provider.Steps)
        if ok and type(steps) == "table" then provided, providedText = steps, text end
    end
    local published, me
    if ns.Comms and ns.Comms.Published then
        local ok, pub = pcall(ns.Comms.Published, key)
        if ok then published = pub end
        me = ns.Comms.Me and ns.Comms.Me() or nil
    end
    local steps, text, role = UIA.Source({
        provided = provided, providedText = providedText, published = published, me = me, now = time(),
        preview = preview, unmet = #(alloc.unmet or {}),
    })
    return UIA.Rows(steps), text, role
end

local COLUMNS = {
    { key = "icon", label = "", width = 20, text = function(item) return UIA.IconText(item.icon) end },
    { key = "seat", label = "Seat", width = 70, text = function(item) return item.seat, item.seatRole end },
    { key = "mob", label = "Mob" },
    { key = "who", label = "Who", width = 110, tip = "The player holding the seat's job",
        text = function(item) return item.who, item.whoRole end },
}

local function RowTip(tip, item)
    tip:AddLine(item.iconName .. ": " .. item.mob)
    tip:AddLine(item.seat ~= "" and item.seat or "no seat", 1, 1, 1)
    tip:AddLine("Held by " .. item.who, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

local page
local controls = {}
local slotBuilt = false

local function Tip(frame, title, ...)
    local lines = { ... }
    W.Tooltip(frame, function(tip)
        tip:AddLine(title)
        for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
    end)
end

-- Hands lane B its two frames once, when both the provider and the tab exist.
function UIA.MarkingChanged()
    if not page or slotBuilt then
        UIA.Refresh()
        return
    end
    local provider = ns.UI.Marking()
    if provider and type(provider.BuildSlot) == "function" then
        slotBuilt = true
        controls.barNote:Hide()
        controls.guideNote:Hide()
        local ok, err = pcall(provider.BuildSlot, controls.bar, controls.guide)
        if not ok then ns.Print("|cffff5555the marking buttons did not build:|r " .. tostring(err)) end
    end
    UIA.Refresh()
end

local function Paint(list, source)
    local rows, text, role = Current()
    list:SetItems(rows)
    source:SetText(text)
    source:SetRole(role)
end

function UIA.Refresh()
    if page and page:IsShown() then Paint(controls.list, controls.source) end
    if controls.float and controls.float:IsShown() then Paint(controls.floatList, controls.floatSource) end
end

local function BuildTab(parent)
    if page then return page end
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)
    local width, height = parent:GetWidth(), parent:GetHeight()

    local float = W.Button(page, "Float", 60, 22, { onClick = function() UIA.Toggle() end })
    float:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    Tip(float, "Float", "This list in a small panel of its own, to keep on screen through a pull.",
        "Same as /mfd assign. Its place is kept per character.")
    local announce = W.Button(page, "Announce", 84, 22, {
        onClick = function()
            if not (ns.DeathWatch and ns.DeathWatch.Announce) then return end
            local plan = ns.DeathWatch.Announce()
            if plan and plan.action ~= "send" then ns.Print("nothing announced: " .. tostring(plan.reason) .. ".") end
        end,
    })
    announce:SetPoint("RIGHT", float, "LEFT", -6, 0)
    Tip(announce, "Announce", "Posts the seat plan to the group now. Only the Raid Lead's press posts.",
        "Same as the Deaths tab's Announce and /mfd announce.")

    -- Lane B's bar: everything left of Announce on the toolbar row.
    controls.bar = CreateFrame("Frame", nil, page)
    controls.bar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    controls.bar:SetPoint("RIGHT", announce, "LEFT", -10, 0)
    controls.bar:SetHeight(24)
    controls.barNote = W.Label(controls.bar, "Mark pack, Clear and Re-mark go here once the marking test passes.",
        { color = "textDim" })
    controls.barNote:SetPoint("LEFT", controls.bar, "LEFT", 0, 0)
    controls.barNote:SetPoint("RIGHT", controls.bar, "RIGHT", 0, 0)
    controls.barNote:SetWordWrap(false)

    -- Lane B's guide row.
    controls.guide = CreateFrame("Frame", nil, page)
    controls.guide:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_GUIDE)
    controls.guide:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    controls.guide:SetHeight(18)
    controls.guideNote = W.Label(controls.guide, "The Mark guide (which icon your target wants) shows here.",
        { font = "small", color = "textDim" })
    controls.guideNote:SetPoint("LEFT", controls.guide, "LEFT", 0, 0)

    controls.source = W.Label(page, "")
    controls.source:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_SOURCE)
    controls.source:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    controls.source:SetWordWrap(false)
    if controls.source.SetMaxLines then controls.source:SetMaxLines(1) end

    controls.list = W.List(page, width, math.max(60, height - TOP_LIST), {
        columns = COLUMNS, tooltip = RowTip, empty = "Nothing to mark: no rules here, or no seats with an owner",
    })
    controls.list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_LIST)

    page:SetScript("OnShow", UIA.Refresh)
    if ns.UI.Marking() then UIA.MarkingChanged() end
    Paint(controls.list, controls.source)
    return page
end

--------------------------------------------------------------------------------
-- The floating panel
--------------------------------------------------------------------------------

local ticker

local function SavedFloat()
    local cdb = ns.cdb
    if type(cdb.windows) ~= "table" then cdb.windows = {} end
    if type(cdb.windows.assignments) ~= "table" then cdb.windows.assignments = {} end
    return cdb.windows.assignments
end

local function FloatEvents(on)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
        if on then
            ns.Events.On(event, "ui_assign", function()
                ns.UI.ReadRoster()
                UIA.Refresh()
            end)
        else
            ns.Events.Off(event, "ui_assign")
        end
    end
    if ns.Comms and ns.Comms.Listen then
        if on then ns.Comms.Listen("ui_assign", UIA.Refresh) else ns.Comms.Unlisten("ui_assign") end
    end
end

local function BuildFloat()
    local listH = 20 + FLOAT_ROWS * ROW_H + 2
    local h = FLOAT_TITLE + 22 + listH + 8
    local p = W.Panel(UIParent, {
        name = FLOAT_NAME, width = FLOAT_W, height = h, strata = "MEDIUM", movable = true,
        onMoved = function(self)
            local fx, fy = W.GetPlace(self)
            if fx then
                local saved = SavedFloat()
                saved.fx, saved.fy, saved.shown = fx, fy, true
            end
        end,
    })
    p:SetToplevel(true)
    p:Hide()
    local bar = W.Panel(p, { height = FLOAT_TITLE, role = "raised", edge = false })
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, p)
    local title = W.Label(bar, "Assignments", { font = "title", color = "accent" })
    title:SetPoint("LEFT", bar, "LEFT", 8, 0)
    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() UIA.Toggle() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") end)

    controls.floatSource = W.Label(p, "", { font = "small" })
    controls.floatSource:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -(FLOAT_TITLE + 6))
    controls.floatSource:SetPoint("RIGHT", p, "RIGHT", -8, 0)
    controls.floatSource:SetWordWrap(false)
    if controls.floatSource.SetMaxLines then controls.floatSource:SetMaxLines(1) end

    controls.floatList = W.List(p, FLOAT_W - 16, listH, {
        columns = COLUMNS, tooltip = RowTip, rowHeight = ROW_H, empty = "Nothing to mark here",
    })
    controls.floatList:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -(FLOAT_TITLE + 22))

    p:SetScript("OnShow", function()
        FloatEvents(true)
        UIA.Refresh()
        if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(AGE_TICK, UIA.Refresh) end
    end)
    p:SetScript("OnHide", function()
        FloatEvents(false)
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
    controls.float = p
    local saved = SavedFloat()
    W.SetPlace(p, saved.fx or 0.62, saved.fy or 0.2)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = FLOAT_NAME end
end

-- Shows or hides the floating panel. Whether it is up is kept, so it comes back after a
-- reload as it was left.
function UIA.Toggle()
    if not ns.db then return end
    if not controls.float then BuildFloat() end
    local show = not controls.float:IsShown()
    controls.float:SetShown(show)
    SavedFloat().shown = show
end

ns.AddCommand("assign", "show or hide the floating assignment panel", function() UIA.Toggle() end)

ns.OnReady("ui_assignments", function()
    if IC_HEADLESS then return end
    ns.UI.AddTab("assign", "Assignments", BuildTab, { refresh = UIA.Refresh,
        onResize = function(w, h) if controls.list then controls.list:Resize(w, math.max(60, h - TOP_LIST)) end end,
    })
    ns.UI.OnChange("ui_assign", function(kind)
        if kind == "plan" or kind == "rules" then UIA.Refresh() end
    end)
    if SavedFloat().shown then UIA.Toggle() end
end)
