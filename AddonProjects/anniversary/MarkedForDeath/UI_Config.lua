-- Role editor. Frames are built lazily on first Toggle and reused from a pool
-- on every refresh, never created and destroyed per row.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Config = MFD.UI.Config or {}
local Config = MFD.UI.Config

local ROW_HEIGHT = 24   -- pixels

-- Display order: kill icons first, then sheep, then banish, matching how the
-- raid reads a pack. Cosmetic only; the role plan itself is keyed by icon.
local ICON_ORDER = { 8, 7, 6, 2, 5, 1, 4, 3 }

-- Adds a resize grip to a window, and remembers the size per character.
--
-- onResize(frame, isFinal) runs on every change so the window never looks stale
-- while being dragged, and again with isFinal true when the corner is let go.
-- Anything expensive belongs behind that flag; anything cheap should run on
-- both, because a window that only reflows on release feels broken in the hand.
--
-- key names the saved-variable slot. Position is saved by the window's own drag
-- handler; this only owns the size.
function MFD.UI.MakeResizable(frame, key, minWidth, minHeight, onResize)
    frame:SetResizable(true)
    if frame.SetMinResize then
        frame:SetMinResize(minWidth, minHeight)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        MFD.charDb.windows[key] = MFD.charDb.windows[key] or {}
        MFD.charDb.windows[key].width = frame:GetWidth()
        MFD.charDb.windows[key].height = frame:GetHeight()
        if onResize then
            onResize(frame, true)
        end
    end)

    frame:SetScript("OnSizeChanged", function(self)
        if onResize then
            onResize(self, false)
        end
    end)

    local saved = MFD.charDb.windows[key]
    if saved and saved.width and saved.height then
        frame:SetSize(math.max(saved.width, minWidth), math.max(saved.height, minHeight))
    end

    frame.grip = grip
    return grip
end

-- Wraps a container in a scroll frame and returns the frame to build into.
--
-- The content frame is as wide as the view and as tall as it needs to be, which
-- is what stops a list outgrowing its window: the Settings tab grew past the
-- bottom edge and simply drew outside it, over whatever was behind. Scrolling
-- is the answer that keeps working as more settings are added, where a taller
-- window only moves the day it happens.
function MFD.UI.MakeScrollable(container)
    -- The library's scroll list, which already leaves the 26 pixels its
    -- scrollbar needs on the right.
    local scroll, content = MFD.UI.ScrollList(container, 0, 4)

    -- The child has to be told its width or its anchored children have nothing
    -- to lay out against; height is set by whoever fills it.
    local function fit()
        content:SetWidth(scroll:GetWidth())
    end
    scroll:SetScript("OnSizeChanged", fit)
    fit()

    container.scroll = scroll
    container.content = content
    return content
end

local frame

local function intentNames()
    local names = {}
    for intent in pairs(MFD.Roles.INTENTS) do
        names[#names + 1] = intent
    end
    table.sort(names)
    return names
end

-- Cycles an icon's intent to the next one alphabetically, keeping its ordinal.
-- The dropdown the intent pickers share. UIDropDownMenu requires a global
-- frame name, which is the documented exception to the one-global rule in
-- CODING_STANDARDS.md, the same as the named windows.
local intentMenu

-- Opens a menu of every intent anchored to a widget, ticking the current one
-- and calling onPick with the chosen intent.
--
-- Both pickers used to cycle on click. With fourteen intents, getting from
-- Kill to Sheep was thirteen clicks and a lap if you overshot.
local function openIntentMenu(anchor, current, onPick)
    if not intentMenu then
        intentMenu = CreateFrame("Frame", "MarkedForDeathIntentMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(intentMenu, function()
        for _, intent in ipairs(intentNames()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = MFD.Roles.INTENTS[intent].label
            info.checked = intent == current
            info.func = function()
                onPick(intent)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, intentMenu, anchor, 0, 0)
end

-- Moves an icon's ordinal within its intent. Ordinals are renumbered from 1 so
-- two roles of one intent never share a number.
local function shiftOrdinal(icon, delta)
    local plan = MFD.db.rolePlan
    local role = plan[icon]
    if not role then
        return
    end

    local siblings = {}
    for otherIcon, other in pairs(plan) do
        if other.intent == role.intent then
            siblings[#siblings + 1] = { icon = otherIcon, role = other }
        end
    end

    table.sort(siblings, function(a, b)
        if a.role.ordinal ~= b.role.ordinal then
            return a.role.ordinal < b.role.ordinal
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
        s.role.ordinal = i
    end
end

-- The intent picker. A custom cell rather than a trailing button because it
-- belongs in the middle of the row, beside the job it changes.
--
-- Every handler here reads row.item at click time rather than closing over the
-- icon this cell was first built for. Rows come back from a pool holding a
-- different icon each render, so a closure over the first one would edit the
-- wrong role from the second render onward.
local function makeIntentCell(row, col, x)
    local button = MFD.UI.Button(row, "Change", col.width - 4, row.rowHeight - 2)
    button:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    button:SetScript("OnClick", function(self)
        local icon = row.item
        local role = MFD.db.rolePlan[icon]
        openIntentMenu(self, role and role.intent, function(intent)
            MFD.db.rolePlan[icon] = MFD.db.rolePlan[icon] or { ordinal = 1 }
            MFD.db.rolePlan[icon].intent = intent
            Config:Refresh()
        end)
    end)
    return button
end

-- The two ordinal arrows, in one cell.
local function makeOrderCell(row, col, x)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetPoint("LEFT", row, "LEFT", x, 0)
    cell:SetSize(col.width, row.rowHeight)

    cell.up = MFD.UI.Button(cell, "^", 24, row.rowHeight - 2)
    cell.up:SetPoint("LEFT", cell, "LEFT", 2, 0)
    cell.up:SetScript("OnClick", function()
        shiftOrdinal(row.item, -1)
        Config:Refresh()
    end)

    cell.down = MFD.UI.Button(cell, "v", 24, row.rowHeight - 2)
    cell.down:SetPoint("LEFT", cell.up, "RIGHT", 2, 0)
    cell.down:SetScript("OnClick", function()
        shiftOrdinal(row.item, 1)
        Config:Refresh()
    end)

    return cell
end

-- The pinned player. Committed on Enter so a half-typed name is never saved.
local function makePinCell(row, col, x)
    local box = MFD.UI.EditBox(row, col.width - 6, row.rowHeight - 2)
    box:SetPoint("LEFT", row, "LEFT", x + 2, 0)

    box:SetScript("OnEnterPressed", function(self)
        local text = string.gsub(self:GetText(), "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        local icon = row.item
        MFD.db.rolePlan[icon] = MFD.db.rolePlan[icon] or { intent = "KILL", ordinal = 1 }
        MFD.db.rolePlan[icon].pin = text ~= "" and text or nil
        self:ClearFocus()
        Config:Refresh()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        Config:Refresh()
    end)

    return box
end

local ROLE_COLUMNS = {
    { key = "icon",   label = "",       width = 24, type = "texture" },
    { key = "job",    label = "Job",    width = 120 },
    { key = "change", label = "Change", width = 72, type = "custom", make = makeIntentCell },
    { key = "order",  label = "Order",  width = 56, type = "custom", make = makeOrderCell },
    { key = "pin",    label = "Pinned player", width = 120, type = "custom", make = makePinCell },
    { key = "owner",  label = "Owner right now", width = "flex" },
}

-- Repaints every row from the current role plan and the live roster, so the
-- Owner column shows who actually holds each role right now.
function Config:Refresh()
    -- The role plan is edited in place, so its table identity never changes and
    -- the marker's cache cannot notice on its own. Every editor in this file
    -- calls Refresh after mutating, so dropping the cache here covers all of
    -- them, including any added later.
    MFD.Marker.InvalidateRoster()

    if not frame or not frame:IsShown() then
        return
    end

    local resolved = MFD.Roles.Resolve(MFD.db.rolePlan, MFD.Marker.CurrentRoster())
    local t = frame.table

    t:Render(ICON_ORDER, function(row, icon)
        local role = MFD.db.rolePlan[icon]
        SetRaidTargetIconTexture(row.cells.icon, icon)

        if role then
            local def = MFD.Roles.INTENTS[role.intent]
            t:Set(row, "job", ((def and def.label) or role.intent) .. " " .. role.ordinal)
        else
            t:Set(row, "job", "unbound", { r = 0.6, g = 0.6, b = 0.6 })
        end

        if not row.cells.pin:HasFocus() then
            row.cells.pin:SetText(role and role.pin or "")
        end

        local record = resolved.byIcon[icon]
        if not record then
            t:Set(row, "owner", "no role", { r = 0.6, g = 0.6, b = 0.6 })
        elseif record.owner == true then
            t:Set(row, "owner", "always available", { r = 0.4, g = 1, b = 0.4 })
        elseif record.owner then
            t:Set(row, "owner", record.owner, { r = 0.4, g = 1, b = 0.4 })
        else
            t:Set(row, "owner", "nobody in the group can do this", { r = 1, g = 0.3, b = 0.3 })
        end
    end)
end

-- Builds the role editor into a container the main window owns. The window
-- provides the border, the title and the dragging; this only fills the space.
function Config:BuildInto(container)
    frame = container

    -- The header is the table's own, so the hand-spaced string of column names
    -- that used to sit above these rows is gone with it.
    frame.table = MFD.UI.Table(frame, {
        top = -6,
        bottom = 6,
        rowHeight = ROW_HEIGHT,
        columns = ROLE_COLUMNS,
    })

    -- The roster changes under an open window; repaint so the owner column
    -- stays truthful without the player needing to close and reopen it.
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function()
        Config:Refresh()
    end)
end

function Config:Toggle()
    MFD.UI.Main:Toggle("roles")
end

-- Rule editor and mob search. Left pane searches bundled and learned mobs and
-- adds them as rules; right pane lists the rules active for one instance with
-- their priority, intent and provenance.
MFD.UI.Rules = MFD.UI.Rules or {}
local RulesUI = MFD.UI.Rules

-- Both lists scroll now, so these are not "how many fit on screen" any more.
-- RESULT_ROWS is a ceiling on how many frames one search is worth building:
-- an empty search box matches every mob in the game and nobody scrolls three
-- hundred rows to find one, they type another letter. A zone's rule list is
-- never long enough to need a ceiling at all.
local RESULT_ROWS = 200    -- most search results worth building rows for
local RULE_ROW_HEIGHT = 24 -- pixels

local rulesFrame
local filterKey = nil
local lastResults = {}

-- Every mutation of the local rule set goes through here. Missing either call
-- leaves the raid out of sync, which is the single most likely bug in this
-- window, so there is exactly one place that can forget.
local function commitRules()
    MFD.Comms.Republish()
    MFD.Comms:AdvertiseRules()
    RulesUI:Refresh()
end

local function playerName()
    return UnitName("player")
end

local function localList(key)
    MFD.db.rules[key] = MFD.db.rules[key] or {}
    return MFD.db.rules[key]
end

-- Finds a rule by its merge key rather than its npcID, because a rule typed
-- by name has no id: matching on a nil npcID would return whichever name rule
-- happened to come first and quietly edit the wrong one.
local function localIndexOf(list, rule)
    local wanted = rule and MFD.Rules.MergeKey(rule)
    if not wanted then
        return nil
    end
    for i, candidate in ipairs(list) do
        if MFD.Rules.MergeKey(candidate) == wanted then
            return i
        end
    end
    return nil
end

-- Returns the local copy of a rule for editing, copying a merged rule from
-- another contributor into the local set first so their table is never
-- aliased. Under the merge rules the local copy then wins if this player is
-- the Raid Lead, and shows as a divergence otherwise.
local function ownedRule(key, merged)
    local list = localList(key)
    local index = localIndexOf(list, merged)
    if index then
        return list[index], index
    end

    local copy = MFD.H.DeepCopy(merged)
    copy.owner = nil
    copy.rank = MFD.Rules.NextRank(list)
    list[#list + 1] = copy
    return copy, #list
end

local function filterKeys()
    local keys = { false }
    local seen = {}
    for _, key in pairs(MFD.Rules.INSTANCE_KEYS) do
        if not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function cycleFilter()
    local keys = filterKeys()
    local index = 1
    for i, key in ipairs(keys) do
        if (key or nil) == filterKey then
            index = i
            break
        end
    end
    local nextKey = keys[(index % #keys) + 1]
    filterKey = nextKey or nil
end



-- Which row is being dragged, and the highlight showing where it would land.
local dragIndex
local dropMarker

-- Turns the cursor position into a gap between rows: 0 is above the first row,
-- count is below the last. Rounding rather than flooring is what makes the drop
-- land where the line is drawn, because the line marks a boundary and the
-- cursor should pick the nearest one.
--
-- Measured against the table's scroll content rather than the page, so the
-- answer stays right when the list is scrolled.
local function boundaryAtCursor(t, count)
    if not t or count == 0 then
        return nil
    end

    local _, cursorY = GetCursorPosition()
    local scale = t.content:GetEffectiveScale()
    local top = t.content:GetTop()
    if not top then
        return nil
    end

    local boundary = math.floor((top - (cursorY / scale)) / t.rowHeight + 0.5)
    if boundary < 0 then
        boundary = 0
    elseif boundary > count then
        boundary = count
    end
    return boundary
end

-- The label that follows the cursor while dragging, so it is obvious what is
-- being moved and not just that something is.
local dragGhost

local function ensureDragGhost()
    if dragGhost then
        return dragGhost
    end

    dragGhost = CreateFrame("Frame", nil, UIParent)
    dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:SetSize(180, 20)
    dragGhost:Hide()

    dragGhost.bg = dragGhost:CreateTexture(nil, "BACKGROUND")
    dragGhost.bg:SetAllPoints()
    dragGhost.bg:SetColorTexture(0, 0, 0, 0.8)

    dragGhost.text = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragGhost.text:SetPoint("LEFT", dragGhost, "LEFT", 6, 0)
    dragGhost.text:SetPoint("RIGHT", dragGhost, "RIGHT", -6, 0)
    dragGhost.text:SetJustifyH("LEFT")
    dragGhost.text:SetWordWrap(false)

    return dragGhost
end

-- Three short lines at the left of a row. Every list that can be reordered on
-- every other piece of software looks like this, which is the point: an arrow
-- pair says "click me", and nothing at all said the row could be picked up.
local function addGripTo(row)
    local grip = CreateFrame("Frame", nil, row)
    grip:SetSize(10, RULE_ROW_HEIGHT)
    grip:SetPoint("LEFT", row, "LEFT", 0, 0)

    grip.lines = {}
    for index = 1, 3 do
        local line = grip:CreateTexture(nil, "ARTWORK")
        line:SetSize(8, 1)
        line:SetPoint("CENTER", grip, "CENTER", 0, (2 - index) * 3)
        line:SetColorTexture(1, 1, 1, 0.35)
        grip.lines[index] = line
    end

    function grip:SetHighlighted(isOn)
        for _, line in ipairs(self.lines) do
            line:SetColorTexture(1, 1, 1, isOn and 0.9 or 0.35)
        end
    end

    return grip
end

-- The grip cell. Three short lines, which is what a reorderable list looks like
-- everywhere else; an arrow pair says "click me" and nothing said the row could
-- be picked up at all.
local function makeGripCell(row, col, x)
    local grip = CreateFrame("Frame", nil, row)
    grip:SetPoint("LEFT", row, "LEFT", x, 0)
    grip:SetSize(col.width, row.rowHeight)

    -- The grip is the handle, so it takes the mouse itself and covers the full
    -- height of its column. Relying on the row underneath to catch the drag
    -- meant hunting for the few pixels that worked, because the lines are drawn
    -- eight pixels tall in the middle of a twenty four pixel row and that is
    -- what the eye aims at.
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")

    grip.lines = {}
    for index = 1, 3 do
        local line = grip:CreateTexture(nil, "ARTWORK")
        line:SetSize(12, 1)
        line:SetPoint("CENTER", grip, "CENTER", 0, (2 - index) * 4)
        line:SetColorTexture(1, 1, 1, 0.35)
        grip.lines[index] = line
    end

    function grip:SetHighlighted(isOn)
        for _, line in ipairs(self.lines) do
            line:SetColorTexture(1, 1, 1, isOn and 0.9 or 0.35)
        end
    end

    return grip
end

local function makeRuleIntentCell(row, col, x)
    local button = MFD.UI.Button(row, "", col.width - 4, row.rowHeight - 2)
    button:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    button:SetScript("OnClick", function(self)
        local item = row.item
        if not item then
            return
        end
        openIntentMenu(self, item.rule.intent, function(intent)
            local rule = ownedRule(item.key, item.rule)
            rule.intent = intent
            commitRules()
        end)
    end)
    return button
end

local function makeRuleOrderCell(row, col, x)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetPoint("LEFT", row, "LEFT", x, 0)
    cell:SetSize(col.width, row.rowHeight)

    local function nudge(delta)
        return function()
            local item = row.item
            if not item then
                return
            end
            local list = localList(item.key)
            local _, index = ownedRule(item.key, item.rule)
            MFD.Rules.Reorder(list, index, delta)
            commitRules()
        end
    end

    cell.up = MFD.UI.Button(cell, "^", 24, row.rowHeight - 2)
    cell.up:SetPoint("LEFT", cell, "LEFT", 2, 0)
    cell.up:SetScript("OnClick", nudge(-1))

    cell.down = MFD.UI.Button(cell, "v", 24, row.rowHeight - 2)
    cell.down:SetPoint("LEFT", cell.up, "RIGHT", 2, 0)
    cell.down:SetScript("OnClick", nudge(1))

    return cell
end

local RULE_COLUMNS = {
    { key = "grip",   label = "",     width = 22, type = "custom", make = makeGripCell },
    { key = "rank",   label = "#",    width = 30, justify = "RIGHT" },
    { key = "name",   label = "Mob",  width = "flex" },
    { key = "intent", label = "Job",  width = 92, type = "custom", make = makeRuleIntentCell },
    { key = "order",  label = "Move", width = 56, type = "custom", make = makeRuleOrderCell },
}

local RULE_BUTTONS = {
    { key = "delete", label = "X", width = 24, kind = "danger" },
}

-- Gives a pooled row its drag behaviour, once. Everything it does reads
-- row.item at the moment of the drag rather than closing over whatever rule the
-- row held when it was built, because the pool hands the same frame a different
-- rule on every render.
local function wireDrag(t, row)
    if row.mfdDragWired then
        return
    end
    row.mfdDragWired = true

    row:RegisterForDrag("LeftButton")

    row.dragTexture = row:CreateTexture(nil, "BACKGROUND")
    row.dragTexture:SetAllPoints()
    row.dragTexture:SetColorTexture(1, 0.82, 0, 0.18)
    row.dragTexture:Hide()

    -- Hooked rather than set: the library's own OnEnter paints the hover, and
    -- replacing it would take that away.
    row:HookScript("OnEnter", function(self)
        if self.item and self.item.isMine and not dragIndex then
            self.cells.grip:SetHighlighted(true)
        end
    end)
    row:HookScript("OnLeave", function(self)
        self.cells.grip:SetHighlighted(false)
    end)

    local function startDrag()
        local item = row.item
        if not item or not item.isMine then
            return
        end
        dragIndex = item.index
        row.dragTexture:Show()

        local ghost = ensureDragGhost()
        ghost.text:SetText(item.rule.name or ("npc " .. tostring(item.rule.npcID)))
        ghost:Show()
    end

    row:SetScript("OnDragStart", startDrag)

    local function stopDrag(self)
        self = row
        self.dragTexture:Hide()
        self.cells.grip:SetHighlighted(false)
        if dropMarker then
            dropMarker:Hide()
        end
        if dragGhost then
            dragGhost:Hide()
        end

        local from = dragIndex
        dragIndex = nil
        local item = self.item
        if not from or not item then
            return
        end

        local list = localList(item.key)
        local boundary = boundaryAtCursor(t, #list)
        if not boundary then
            return
        end

        local to = MFD.Rules.DropIndex(from, boundary)
        if to ~= from then
            MFD.Rules.MoveTo(list, from, to)
            commitRules()
        end
    end

    row:SetScript("OnDragStop", stopDrag)

    -- The grip drags the same row, and lights up on its own hover so the
    -- target of the click is the thing that reacts to the cursor.
    local grip = row.cells.grip
    grip:SetScript("OnDragStart", startDrag)
    grip:SetScript("OnDragStop", stopDrag)
    grip:SetScript("OnEnter", function()
        if row.item and row.item.isMine and not dragIndex then
            grip:SetHighlighted(true)
        end
    end)
    grip:SetScript("OnLeave", function()
        grip:SetHighlighted(false)
    end)
end

local function paintResults()
    local bundled = MFD.Data and MFD.Data.Mobs or {}
    lastResults = MFD.Search(rulesFrame.search:GetText(), filterKey, bundled, MFD.db.learnedMobs)

    local shown = {}
    for index, result in ipairs(lastResults) do
        if index > RESULT_ROWS then
            break
        end
        shown[index] = result
    end


    rulesFrame.resultTable:Render(shown, function(row, result)
        -- Amber for a mob this client learned by seeing it, plain for one that
        -- shipped in the bundled table: the addon's colour for derived values.
        local color = result.source == "learned"
            and { r = 1, g = 0.8, b = 0.4 } or nil
        rulesFrame.resultTable:Set(row, "name", result.name, color)
        rulesFrame.resultTable:Set(row, "npcID", tostring(result.npcID),
            { r = 0.5, g = 0.5, b = 0.5 })

        row.buttons.add:SetScript("OnClick", function()
            -- AddRule, not OpenFor: adding from search must file into the
            -- filtered zone so a list can be built from outside the instance.
            RulesUI:AddRule({ npcID = result.npcID, name = result.name })
        end)
    end)

    -- A mob the addon has never seen is not in either table, which is the
    -- normal case when planning a raid you have not walked yet. Offer to make
    -- a rule from the typed name rather than dead-ending on "no mobs match".
    local typed = string.match(rulesFrame.search:GetText() or "", "^%s*(.-)%s*$")
    local hasExact = false
    for _, result in ipairs(lastResults) do
        if string.lower(result.name) == string.lower(typed) then
            hasExact = true
            break
        end
    end

    if typed ~= "" and not hasExact then
        rulesFrame.typedAdd:SetText('Add "' .. typed .. '"')
        rulesFrame.typedAdd:Show()
    else
        rulesFrame.typedAdd:Hide()
    end

    if #lastResults == 0 then
        rulesFrame.resultsNote:SetText("|cff999999not seen yet. Type the exact name and use the button above.|r")
    elseif #lastResults > RESULT_ROWS then
        rulesFrame.resultsNote:SetText(string.format(
            "|cff999999first %d of %d, keep typing to narrow it|r", RESULT_ROWS, #lastResults))
    else
        rulesFrame.resultsNote:SetText("")
    end
end

local function paintRules()
    local key = filterKey or MFD.Rules.currentInstanceKey
    rulesFrame.ruleHeader:SetText("Rules for " .. tostring(key or "no known zone"))

    local ranked = key and MFD.Rules.Ranked(MFD.Rules.merged[key] or {}) or {}
    local me = playerName()
    local hasBadRule = false
    local t = rulesFrame.ruleTable

    local list = {}
    for index, rule in ipairs(ranked) do
        -- Only your own rules can be reordered; a merged rule belongs to
        -- whoever wrote it and dragging it here would achieve nothing.
        list[index] = {
            rule = rule,
            key = key,
            index = index,
            isMine = rule.owner == me or rule.owner == nil,
        }
    end

    t:Render(list, function(row, item)
        wireDrag(t, row)

        local rule = item.rule
        local suffix = item.isMine and "" or ("  (" .. tostring(rule.owner) .. ")")

        -- The position in the list, not rule.rank. Ranks are stored in steps of
        -- ten so a rule can be inserted between two without renumbering every
        -- one below it; that spacing is storage and reads as nonsense in a
        -- column headed "#".
        t:Set(row, "rank", tostring(item.index), { r = 0.6, g = 0.6, b = 0.6 })
        t:Set(row, "name", (rule.name or ("npc " .. rule.npcID)) .. suffix,
            not item.isMine and { r = 1, g = 0.8, b = 0.4 } or nil)

        local def = MFD.Roles.INTENTS[rule.intent]
        local label = (def and def.label) or rule.intent

        -- A rule typed by name has no id to look up, so find the creature type
        -- by name instead; that is the whole population of pre-planned rules.
        local learned = rule.npcID and MFD.db.learnedMobs[rule.npcID] or nil
        if not learned and rule.name then
            for _, entry in pairs(MFD.db.learnedMobs) do
                if entry.name and string.lower(entry.name) == string.lower(rule.name) then
                    learned = entry
                    break
                end
            end
        end

        local canApply = MFD.Roles.CanIntentApply(rule.intent, learned and learned.creatureType)
        row.cells.intent:SetText((canApply and "" or "|cffff4444") .. label .. "|r")
        if not canApply then
            hasBadRule = true
        end

        -- Merged rules are read only until touched; touching one copies it into
        -- the local set. The arrows stay enabled for that reason, but delete
        -- only ever removes a local rule.
        row.buttons.delete:SetEnabled(item.isMine)
        row.buttons.delete:SetScript("OnClick", function()
            local rules = localList(item.key)
            local index = localIndexOf(rules, item.rule)
            if index then
                table.remove(rules, index)
                commitRules()
            end
        end)
    end)

    if hasBadRule and not rulesFrame.hasPlayedBadSound then
        rulesFrame.hasPlayedBadSound = true
        MFD.PlayBadMarkSound()
    elseif not hasBadRule then
        rulesFrame.hasPlayedBadSound = false
    end
end

function RulesUI:Refresh()
    if not rulesFrame or not rulesFrame:IsShown() then
        return
    end

    rulesFrame.filter:SetText(filterKey and filterKey or "this zone")
    paintResults()
    paintRules()
end

-- Shows the editor and makes sure a rule exists for npcID in the current
-- instance, adding it as a kill rule when absent. The add-target keybind and
-- the search results both land here. When a unit token is passed, the
-- creature type check runs against the live unit so the warning is immediate.
function RulesUI:OpenFor(npcID, name, unit)
    local key = MFD.Rules.currentInstanceKey
    if not key then
        MFD.Error("cannot tell what zone this is yet, try again in a moment")
        return
    end

    if not rulesFrame or not rulesFrame:IsShown() then
        RulesUI:Toggle()
    end

    filterKey = nil

    local list = localList(key)
    if not localIndexOf(list, { npcID = npcID, name = name }) then
        list[#list + 1] = {
            npcID = npcID,
            name = name,
            intent = "KILL",
            rank = MFD.Rules.NextRank(list),
        }
        MFD.Print(string.format("%s added as Kill, priority %d in %s. Click its intent to change it.",
            tostring(name), list[#list].rank, key))
    end

    commitRules()
end

-- Adds one rule to the zone the filter is pointing at, which may be nowhere
-- near the player. spec is { npcID } or { name } or both.
--
-- Separate from OpenFor because that one is the keybind path: it means "the
-- mob in front of me", so it clears the filter and files into the current
-- zone. This one means "the mob I just typed", and must not move the filter
-- out from under someone building a list for another instance.
function RulesUI:AddRule(spec)
    local key = RulesUI:TargetKey()
    if not key then
        MFD.Error("pick a zone with the filter button first, or walk into one")
        return
    end

    local list = localList(key)
    local wanted = MFD.Rules.MergeKey(spec)
    if not wanted then
        MFD.Error("that needs a name or an npc id")
        return
    end

    for _, rule in ipairs(list) do
        if MFD.Rules.MergeKey(rule) == wanted then
            MFD.Print(tostring(spec.name or spec.npcID) .. " is already in the " .. key .. " list")
            return
        end
    end

    list[#list + 1] = {
        npcID = spec.npcID,
        name = spec.name,
        intent = "KILL",
        rank = MFD.Rules.NextRank(list),
    }

    MFD.Print(string.format("%s added as Kill, priority %d in %s. Click its job to change it.",
        tostring(spec.name or spec.npcID), list[#list].rank, key))

    commitRules()
end

local function buildRulesFrame()
    -- Left pane: search.
    rulesFrame.search = MFD.UI.EditBox(rulesFrame, 200, 20)
    rulesFrame.search:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 20, -10)
    rulesFrame.search:SetAutoFocus(false)
    rulesFrame.search:SetScript("OnTextChanged", function()
        paintResults()
    end)
    rulesFrame.search:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)

    -- Adds a rule for a name the addon has never seen, which is the whole
    -- point of planning ahead. Matching happens on the name until an id is
    -- known, so the rule works the first time the raid walks past the mob.
    rulesFrame.typedAdd = MFD.UI.Button(rulesFrame, "", 220, 20)
    rulesFrame.typedAdd:SetPoint("TOPLEFT", rulesFrame.search, "BOTTOMLEFT", 0, -4)
    rulesFrame.typedAdd:Hide()
    rulesFrame.typedAdd:SetScript("OnClick", function()
        local typed = string.match(rulesFrame.search:GetText() or "", "^%s*(.-)%s*$")
        if typed == "" then
            return
        end
        RulesUI:AddRule({ name = typed })
    end)

    rulesFrame.bulk = MFD.UI.Button(rulesFrame, "", 90, 20)
    rulesFrame.bulk:SetPoint("BOTTOMLEFT", rulesFrame, "BOTTOMLEFT", 20, 10)
    rulesFrame.bulk:SetText("Paste list")
    rulesFrame.bulk:SetScript("OnClick", function()
        RulesUI:ShowTransferBox("", "bulk")
    end)

    rulesFrame.share = MFD.UI.Button(rulesFrame, "", 70, 20)
    rulesFrame.share:SetPoint("LEFT", rulesFrame.bulk, "RIGHT", 8, 0)
    rulesFrame.share:SetText("Share")
    rulesFrame.share:SetScript("OnClick", function()
        RulesUI:ShowTransferBox(MFD.Rules.ToJSON(MFD.db.rules, {}), "exportjson")
    end)

    rulesFrame.load = MFD.UI.Button(rulesFrame, "", 80, 20)
    rulesFrame.load:SetPoint("LEFT", rulesFrame.share, "RIGHT", 8, 0)
    rulesFrame.load:SetText("Load file")
    rulesFrame.load:SetScript("OnClick", function()
        RulesUI:ShowTransferBox("", "importjson")
    end)

    rulesFrame.format = MFD.UI.Button(rulesFrame, "", 70, 20)
    rulesFrame.format:SetPoint("LEFT", rulesFrame.load, "RIGHT", 8, 0)
    rulesFrame.format:SetText("Format")
    rulesFrame.format:SetScript("OnClick", function()
        RulesUI:ShowTransferBox(FORMAT_HELP, "help")
    end)

    rulesFrame.filter = MFD.UI.Button(rulesFrame, "", 110, 20)
    rulesFrame.filter:SetPoint("LEFT", rulesFrame.search, "RIGHT", 6, 0)
    rulesFrame.filter:SetScript("OnClick", function()
        cycleFilter()
        RulesUI:Refresh()
    end)

    rulesFrame.resultsNote = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rulesFrame.resultsNote:SetPoint("TOPLEFT", rulesFrame.search, "BOTTOMLEFT", 6, -30)
    rulesFrame.resultsNote:SetWidth(320)
    rulesFrame.resultsNote:SetJustifyH("LEFT")

    rulesFrame.results = CreateFrame("Frame", nil, rulesFrame)
    rulesFrame.results:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 6, -76)
    rulesFrame.results:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMLEFT", 336, 6)

    -- The Add button is a trailing button column rather than a widget the row
    -- builds for itself, which is what keeps every list in the addon the same
    -- shape.
    rulesFrame.resultTable = MFD.UI.Table(rulesFrame.results, {
        -- The pane is 330 wide and the library draws the scrollbar in the 26
        -- pixels past the table's own width, so 304 keeps the bar inside this
        -- pane instead of over the rule list next to it.
        width = 304,
        rowHeight = RULE_ROW_HEIGHT,
        columns = {
            { key = "name", label = "Mob", width = "flex" },
            { key = "npcID", label = "id", width = 54, justify = "RIGHT" },
        },
        buttons = {
            { key = "add", label = "Add", width = 44 },
        },
    })

    -- Right pane: rules.
    rulesFrame.ruleHeader = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rulesFrame.ruleHeader:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 350, -36)

    rulesFrame.ruleHint = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rulesFrame.ruleHint:SetPoint("TOPLEFT", rulesFrame.ruleHeader, "BOTTOMLEFT", 0, -2)
    rulesFrame.ruleHint:SetText("top = highest priority.  grab a row by the |cffffd100grip|r on its left to drag it anywhere.  "
        .. "amber = merged from another player")

    rulesFrame.ruleList = CreateFrame("Frame", nil, rulesFrame)
    rulesFrame.ruleList:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 342, -76)
    rulesFrame.ruleList:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMRIGHT", -6, 40)

    rulesFrame.ruleTable = MFD.UI.Table(rulesFrame.ruleList, {
        rowHeight = RULE_ROW_HEIGHT,
        columns = RULE_COLUMNS,
        buttons = RULE_BUTTONS,
    })

    -- The insertion point, drawn in the gap the rule would land in. A frame
    -- rather than a bare texture so it can carry an end cap: a plain line
    -- across the list read as a strike-through of the row it crossed.
    --
    -- Parented to the scroll content, so it travels with the rows instead of
    -- staying put while they move under it.
    dropMarker = CreateFrame("Frame", nil, rulesFrame.ruleTable.content)
    dropMarker:SetHeight(10)
    dropMarker:SetFrameLevel(rulesFrame.ruleTable.content:GetFrameLevel() + 10)
    dropMarker:Hide()

    dropMarker.line = dropMarker:CreateTexture(nil, "OVERLAY")
    dropMarker.line:SetHeight(3)
    dropMarker.line:SetPoint("LEFT", dropMarker, "LEFT", 8, 0)
    dropMarker.line:SetPoint("RIGHT", dropMarker, "RIGHT", -8, 0)
    dropMarker.line:SetColorTexture(1, 0.82, 0, 1)

    dropMarker.capLeft = dropMarker:CreateTexture(nil, "OVERLAY")
    dropMarker.capLeft:SetSize(3, 10)
    dropMarker.capLeft:SetPoint("CENTER", dropMarker.line, "LEFT", 0, 0)
    dropMarker.capLeft:SetColorTexture(1, 0.82, 0, 1)

    dropMarker.capRight = dropMarker:CreateTexture(nil, "OVERLAY")
    dropMarker.capRight:SetSize(3, 10)
    dropMarker.capRight:SetPoint("CENTER", dropMarker.line, "RIGHT", 0, 0)
    dropMarker.capRight:SetColorTexture(1, 0.82, 0, 1)

    -- One driver for the whole list rather than an OnUpdate on every row, which
    -- had each of them recomputing the same answer every frame.
    rulesFrame.ruleList:SetScript("OnUpdate", function(self)
        if not dragIndex then
            return
        end

        if dragGhost and dragGhost:IsShown() then
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            dragGhost:ClearAllPoints()
            dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 10)
        end

        local t = rulesFrame.ruleTable
        local list = localList(RulesUI:TargetKey())
        local boundary = boundaryAtCursor(t, #list)
        if not boundary then
            dropMarker:Hide()
            return
        end

        -- Rows sit at -(i - 1) * rowHeight from the top of the content, so gap
        -- N is exactly -N * rowHeight. No padding to account for any more,
        -- which is what the line was drawn wrong by before.
        dropMarker:ClearAllPoints()
        dropMarker:SetPoint("TOPLEFT", t.content, "TOPLEFT", 0,
            -(boundary * t.rowHeight) + 5)
        dropMarker:SetPoint("RIGHT", t.content, "RIGHT", 0, 0)
        dropMarker:Show()
    end)

    rulesFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rulesFrame:SetScript("OnEvent", function()
        RulesUI:Refresh()
    end)

end

-- Builds the rule editor into a container the main window owns. The window
-- supplies the border, title and dragging; this only fills the space.
function RulesUI:BuildInto(container)
    rulesFrame = container
    buildRulesFrame()
end

-- Import and export. One window, two modes. Export shows a selected read-only
-- string; import takes a pasted string and merges it into the local rules.
local transferFrame

local function runImport()
    local text = string.gsub(transferFrame.edit:GetText(), "%s+", "")
    local decoded = MFD.H.Base64Decode(text)
    if not decoded then
        MFD.Error("that is not a Marked For Death rule string")
        return
    end

    local parsed, err = MFD.Rules.Deserialize(decoded)
    if not parsed then
        MFD.Error("could not read the rule string: " .. tostring(err))
        return
    end

    local added, updated = MFD.Rules.MergeImport(MFD.db, parsed)
    commitRules()
    MFD.Print(string.format("imported %d new rules, updated %d", added, updated))
    transferFrame:Hide()
end

local function buildTransferFrame()
    transferFrame = MFD.UI.Window("MarkedForDeathTransferFrame", {
        width = 460,
        height = 240,
        title = "",
        status = false,
        strata = "DIALOG",
    })
    transferFrame:SetFrameLevel(50)

    transferFrame.hint = MFD.UI.Label(transferFrame, "", "GameFontDisableSmall")
    transferFrame.hint:SetPoint("TOPLEFT", transferFrame, "TOPLEFT", 14, -34)

    -- The library's multi-line area. It owns the scroll frame and the edit box,
    -- and knows the one thing that matters here: there is no clipboard API on
    -- this client, so the most a Copy button can do is select the text and let
    -- the player press Ctrl+C.
    transferFrame.box = MFD.UI.TextBox(transferFrame, 414, 150)
    transferFrame.box:SetPoint("TOPLEFT", transferFrame, "TOPLEFT", 14, -52)
    transferFrame.edit = transferFrame.box.edit

    transferFrame.action = MFD.UI.Button(transferFrame, "", 100, 22)
    transferFrame.action:SetPoint("BOTTOMRIGHT", transferFrame, "BOTTOMRIGHT", -14, 10)
    transferFrame.action:SetScript("OnClick", function()
        if transferFrame.mode == "import" then
            runImport()
        elseif transferFrame.mode == "bulk" then
            RulesUI:RunBulkAdd()
        elseif transferFrame.mode == "importjson" then
            RulesUI:RunJSONImport()
        elseif transferFrame.mode == "help" then
            transferFrame:Hide()
        else
            transferFrame:Hide()
        end
    end)

    tinsert(UISpecialFrames, "MarkedForDeathTransferFrame")
end

-- Shows the transfer window. mode is "export" (text is shown, selected, and
-- the button closes) or "import" (text is editable and the button imports).
-- The zone a rule typed right now would be filed under: the filter when one
-- is set, otherwise wherever the player is standing. This is what lets a whole
-- instance be planned from the bank in Shattrath.
function RulesUI:TargetKey()
    return filterKey or MFD.Rules.currentInstanceKey
end

-- Applies a pasted kill order to the targeted zone. Existing rules for the
-- same mob are replaced; rules not named in the paste are left alone, so a
-- paste can extend a list rather than only replace it.
function RulesUI:RunBulkAdd()
    local key = RulesUI:TargetKey()
    if not key then
        MFD.Error("pick a zone with the filter button first")
        return
    end

    local parsed, err = MFD.Rules.ParseBulk(transferFrame.edit:GetText())
    if not parsed then
        MFD.Error(err)
        return
    end

    MFD.db.rules[key] = MFD.db.rules[key] or {}
    local list = MFD.db.rules[key]

    local replaced, added = 0, 0
    for _, incoming in ipairs(parsed) do
        local incomingKey = MFD.Rules.MergeKey(incoming)
        local existing
        for _, rule in ipairs(list) do
            if MFD.Rules.MergeKey(rule) == incomingKey then
                existing = rule
                break
            end
        end

        if existing then
            existing.intent = incoming.intent
            existing.rank = incoming.rank
            replaced = replaced + 1
        else
            list[#list + 1] = incoming
            added = added + 1
        end
    end

    -- Anything already in the zone that the paste did not mention keeps its
    -- rule but sorts below the pasted order, so the paste reads as the plan.
    local pastedCount = #parsed
    for _, rule in ipairs(list) do
        local isPasted = false
        for _, incoming in ipairs(parsed) do
            if MFD.Rules.MergeKey(rule) == MFD.Rules.MergeKey(incoming) then
                isPasted = true
                break
            end
        end
        if not isPasted then
            rule.rank = rule.rank + pastedCount * MFD.Rules.RANK_STEP
        end
    end

    MFD.Rules.BumpVersion(MFD.db)
    MFD.Rules.RefreshLocal(MFD.db, UnitName("player"))
    if MFD.Comms and MFD.Comms.Republish then
        MFD.Comms.Republish()
    end

    transferFrame:Hide()
    MFD.Print(string.format("%s: %d added, %d updated", key, added, replaced))
    RulesUI:Refresh()
end

-- What the shared file looks like, shown by the Format button. Written as a
-- worked example rather than a specification, because the audience is a raid
-- leader who wants to post their Black Temple order, not a parser author.
local FORMAT_HELP = [[
{
  "addon": "MarkedForDeath",
  "formatVersion": 1,
  "note": "Black Temple kill order, Inner Circle",
  "rules": {
    "BLACKTEMPLE": [
      { "name": "Illidari Nightlord", "job": "SHEEP",  "priority": 10 },
      { "name": "Illidari Defiler",   "job": "BANISH", "priority": 20 },
      { "npc": 22880,                 "job": "KILL",   "priority": 30 }
    ],
    "HYJAL": [
      { "name": "Shadowy Necromancer", "job": "KILL", "priority": 10 }
    ]
  }
}

  note        optional, free text, travels with the file
  rules       one list per zone. Zone keys are the ones /mfd where prints:
              KARAZHAN GRUUL MAGTHERIDON SERPENTSHRINE TEMPESTKEEP
              HYJAL BLACKTEMPLE ZULAMAN SUNWELL

  name        the mob's name exactly as the game shows it. Works even for a
              mob the addon has never seen, which is the point: a list written
              from a guide marks correctly the first time you walk in.
  npc         an npc id instead of a name. More precise, but you need to have
              seen the mob to know it. Give one or the other; npc wins.
  job         KILL SHEEP BANISH TRAP SAP SHACKLE SEDUCE ENSLAVE FEAR
              HIBERNATE ROOTS MINDCONTROL REPENTANCE IGNORE
  priority    lower marks first. 10, 20, 30 leaves room to insert later.
  fallback    optional job to use when nobody present can do the first one.
  maxCount    optional cap on how many of that mob get marked at once.

Roles are deliberately not in the file. Which icon means which job, and who is
pinned to it, is your raid's business and differs between guilds. Import
somebody's kill order, then set your own roles on the Roles tab.
]]

function RulesUI:RunJSONImport()
    local incoming, err = MFD.Rules.FromJSON(transferFrame.edit:GetText())
    if not incoming then
        MFD.Error(err)
        return
    end

    local added, replaced, zones = 0, 0, 0
    for _, instanceKey in ipairs(MFD.H.SortedKeys(incoming)) do
        zones = zones + 1
        local list = localList(instanceKey)

        for _, rule in ipairs(incoming[instanceKey]) do
            local wanted = MFD.Rules.MergeKey(rule)
            local existing
            for _, mine in ipairs(list) do
                if MFD.Rules.MergeKey(mine) == wanted then
                    existing = mine
                    break
                end
            end

            if existing then
                existing.intent = rule.intent
                existing.rank = rule.rank
                existing.fallback = rule.fallback
                existing.maxCount = rule.maxCount
                replaced = replaced + 1
            else
                list[#list + 1] = rule
                added = added + 1
            end
        end
    end

    commitRules()
    transferFrame:Hide()
    MFD.Print(string.format("imported %d zones: %d rules added, %d updated. Set your own roles on the Roles tab.",
        zones, added, replaced))
end

function RulesUI:ShowTransferBox(text, mode)
    if not transferFrame then
        buildTransferFrame()
    end

    transferFrame.mode = mode
    transferFrame.edit:SetText(text or "")

    if mode == "exportjson" then
        transferFrame.title:SetText("Share rules")
        transferFrame.hint:SetText("Ctrl+C to copy, then paste it into a file or a forum post. Anyone can load it with Import file.")
        transferFrame.action:SetText("Close")
        transferFrame:Show()
        transferFrame.edit:SetFocus()
        transferFrame.edit:HighlightText()
        return
    end

    if mode == "importjson" then
        transferFrame.title:SetText("Import a shared rule file")
        transferFrame.hint:SetText("Paste a shared file below. It merges into your rules for the zones it names; nothing of yours is deleted. Format button explains the file.")
        transferFrame.action:SetText("Import")
        transferFrame:Show()
        transferFrame.edit:SetFocus()
        return
    end

    if mode == "help" then
        transferFrame.title:SetText("The shared rule file format")
        transferFrame.hint:SetText("Plain JSON. Edit it in any text editor, post it anywhere, hand it to a new raid leader.")
        transferFrame.action:SetText("Close")
        transferFrame:Show()
        return
    end

    if mode == "bulk" then
        transferFrame.title:SetText("Paste a kill order for " .. tostring(RulesUI:TargetKey() or "no zone"))
        transferFrame.hint:SetText("One mob per line, best target first. Add \"= sheep\", \"= banish\" and so on for jobs. -- comments and blank lines are ignored.")
        transferFrame.action:SetText("Add all")
        transferFrame:Show()
        transferFrame.edit:SetFocus()
        return
    end

    if mode == "import" then
        transferFrame.title:SetText("Import rules")
        transferFrame.hint:SetText("Paste a rule string below. It merges into your rules; nothing is deleted.")
        transferFrame.action:SetText("Import")
        transferFrame:Show()
        transferFrame.edit:SetFocus()
    else
        transferFrame.title:SetText("Export rules")
        transferFrame.hint:SetText("Ctrl+C to copy. Anyone can paste this with /mfd import.")
        transferFrame.action:SetText("Close")
        transferFrame:Show()
        transferFrame.edit:SetFocus()
        transferFrame.edit:HighlightText()
    end
end

function RulesUI:Toggle()
    MFD.UI.Main:Toggle("rules")
end

_G.MarkedForDeath = MFD
