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

-- Returns a reusable row from pool, creating it only when the pool is short.
-- Shared by every list in the addon so no list churns frames on refresh.
-- Rows start this far below the top of their list. Exported because anything
-- that positions against the row grid has to use the same number: the drop
-- marker did not, and drew its line two thirds of the way into the row above
-- the gap it was meant to be in.
MFD.UI.ROW_TOP_PADDING = 8

function MFD.UI.AcquireRow(parent, pool, index, height)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(height)
        row:SetPoint("LEFT", parent, "LEFT", 8, 0)
        row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        pool[index] = row
    end
    row:SetPoint("TOP", parent, "TOP", 0, -((index - 1) * height) - MFD.UI.ROW_TOP_PADDING)
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
    row.cycle:SetScript("OnClick", function(button)
        local role = MFD.db.rolePlan[icon]
        openIntentMenu(button, role and role.intent, function(intent)
            MFD.db.rolePlan[icon] = MFD.db.rolePlan[icon] or { ordinal = 1 }
            MFD.db.rolePlan[icon].intent = intent
            Config:Refresh()
        end)
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
        MFD.db.rolePlan[icon] = MFD.db.rolePlan[icon] or { intent = "KILL", ordinal = 1 }
        MFD.db.rolePlan[icon].pin = text ~= "" and text or nil
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

    for index, icon in ipairs(ICON_ORDER) do
        local row = MFD.UI.AcquireRow(frame.body, rows, index, ROW_HEIGHT)
        buildRow(row, icon)

        local role = MFD.db.rolePlan[icon]
        SetRaidTargetIconTexture(row.texture, icon)

        if role then
            local label = MFD.Roles.INTENTS[role.intent] and MFD.Roles.INTENTS[role.intent].label or role.intent
            row.intentText:SetText(label .. " " .. role.ordinal)
        else
            row.intentText:SetText("|cff999999unbound|r")
        end

        if not row.pinBox:HasFocus() then
            row.pinBox:SetText(role and role.pin or "")
        end

        local record = resolved.byIcon[icon]
        if not record then
            row.ownerText:SetText("|cff999999no role|r")
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

-- Builds the role editor into a container the main window owns. The window
-- provides the border, the title and the dragging; this only fills the space.
function Config:BuildInto(container)
    frame = container

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -6)
    frame.header:SetText("icon      job                    change   order      pinned player          owner right now")

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -18)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

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

local RESULT_ROWS = 12     -- visible search results
local RULE_ROWS = 14       -- visible rules
local RULE_ROW_HEIGHT = 24 -- pixels

local rulesFrame
local resultRows = {}
local ruleRows = {}
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



local function buildResultRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    row.name:SetJustifyH("LEFT")

    row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.add:SetSize(44, 20)
    row.add:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.add:SetText("Add")
    row.add:SetScript("OnClick", function()
        if row.result then
            -- AddRule, not OpenFor: adding from search must file into the
            -- filtered zone so a list can be built from outside the instance.
            RulesUI:AddRule({ npcID = row.result.npcID, name = row.result.name })
        end
    end)
end

-- Which row is being dragged, and the highlight showing where it would land.
local dragIndex
local dropMarker

-- Turns the cursor position into a gap between rows: 0 is above the first row,
-- count is below the last. Rounding rather than flooring is what makes the drop
-- land where the line is drawn, because the line marks a boundary and the
-- cursor should pick the nearest one.
local function boundaryAtCursor(count)
    if not rulesFrame or count == 0 then
        return nil
    end

    local _, cursorY = GetCursorPosition()
    local scale = rulesFrame.ruleList:GetEffectiveScale()
    local top = rulesFrame.ruleList:GetTop()
    if not top then
        return nil
    end

    local offset = top - (cursorY / scale) - MFD.UI.ROW_TOP_PADDING
    local boundary = math.floor(offset / RULE_ROW_HEIGHT + 0.5)
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

local function buildRuleRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    -- The whole row is a drag handle, and the grip says so. Arrows stay for a
    -- one-place nudge; this is for moving something ten rows without ten clicks.
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")

    row.hoverTexture = row:CreateTexture(nil, "BACKGROUND")
    row.hoverTexture:SetAllPoints()
    row.hoverTexture:SetColorTexture(1, 1, 1, 0.07)
    row.hoverTexture:Hide()

    row.dragTexture = row:CreateTexture(nil, "BACKGROUND")
    row.dragTexture:SetAllPoints()
    row.dragTexture:SetColorTexture(1, 0.82, 0, 0.18)
    row.dragTexture:Hide()

    row.grip = addGripTo(row)

    row:SetScript("OnEnter", function(self)
        if self.rule and self.isMine and not dragIndex then
            self.hoverTexture:Show()
            self.grip:SetHighlighted(true)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hoverTexture:Hide()
        self.grip:SetHighlighted(false)
    end)

    row:SetScript("OnDragStart", function(self)
        if not self.rule or not self.isMine then
            return
        end
        dragIndex = self.index
        self.hoverTexture:Hide()
        self.dragTexture:Show()

        local ghost = ensureDragGhost()
        ghost.text:SetText(self.rule.name or ("npc " .. tostring(self.rule.npcID)))
        ghost:Show()
    end)

    row:SetScript("OnDragStop", function(self)
        self.dragTexture:Hide()
        self.grip:SetHighlighted(false)
        if dropMarker then
            dropMarker:Hide()
        end
        if dragGhost then
            dragGhost:Hide()
        end

        local from = dragIndex
        dragIndex = nil
        if not from or not self.instanceKey then
            return
        end

        local list = localList(self.instanceKey)
        local boundary = boundaryAtCursor(#list)
        if not boundary then
            return
        end

        local to = MFD.Rules.DropIndex(from, boundary)
        if to ~= from then
            MFD.Rules.MoveTo(list, from, to)
            commitRules()
        end
    end)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")

    row.intent = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.intent:SetSize(88, 20)
    row.intent:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.intent:SetScript("OnClick", function(button)
        if not row.rule then
            return
        end
        openIntentMenu(button, row.rule.intent, function(intent)
            local rule = ownedRule(row.instanceKey, row.rule)
            rule.intent = intent
            commitRules()
        end)
    end)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetSize(24, 20)
    row.up:SetPoint("LEFT", row.intent, "RIGHT", 4, 0)
    row.up:SetText("^")
    row.up:SetScript("OnClick", function()
        if not row.rule then
            return
        end
        local list = localList(row.instanceKey)
        local _, index = ownedRule(row.instanceKey, row.rule)
        MFD.Rules.Reorder(list, index, -1)
        commitRules()
    end)

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetSize(24, 20)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetText("v")
    row.down:SetScript("OnClick", function()
        if not row.rule then
            return
        end
        local list = localList(row.instanceKey)
        local _, index = ownedRule(row.instanceKey, row.rule)
        MFD.Rules.Reorder(list, index, 1)
        commitRules()
    end)

    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetSize(24, 20)
    row.delete:SetPoint("LEFT", row.down, "RIGHT", 6, 0)
    row.delete:SetText("X")
    row.delete:SetScript("OnClick", function()
        if not row.rule then
            return
        end
        local list = localList(row.instanceKey)
        local index = localIndexOf(list, row.rule)
        if index then
            table.remove(list, index)
            commitRules()
        end
    end)
end

local function paintResults()
    local bundled = MFD.Data and MFD.Data.Mobs or {}
    lastResults = MFD.Search(rulesFrame.search:GetText(), filterKey, bundled, MFD.db.learnedMobs)

    local shown = 0
    for index, result in ipairs(lastResults) do
        if index > RESULT_ROWS then
            break
        end
        local row = MFD.UI.AcquireRow(rulesFrame.results, resultRows, index, RULE_ROW_HEIGHT)
        buildResultRow(row)
        row.result = result
        local color = result.source == "learned" and "|cffffcc66" or ""
        row.name:SetText(color .. result.name .. "|r  |cff666666" .. result.npcID .. "|r")
        shown = index
    end

    MFD.UI.ReleaseRows(resultRows, shown + 1)

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
        rulesFrame.resultsNote:SetText(string.format("|cff999999showing %d of %d, keep typing|r", RESULT_ROWS, #lastResults))
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

    local shown = 0
    for index, rule in ipairs(ranked) do
        if index > RULE_ROWS then
            break
        end
        local row = MFD.UI.AcquireRow(rulesFrame.ruleList, ruleRows, index, RULE_ROW_HEIGHT)
        buildRuleRow(row)
        row.rule = rule
        row.instanceKey = key
        row.index = index

        local isMine = rule.owner == me or rule.owner == nil
        -- Only your own rules can be reordered; a merged rule belongs to
        -- whoever wrote it and dragging it here would achieve nothing.
        row.isMine = isMine
        local color = isMine and "" or "|cffffcc66"
        local suffix = isMine and "" or ("  (" .. tostring(rule.owner) .. ")")

        row.rank:SetText(tostring(rule.rank))
        row.name:SetText(color .. (rule.name or ("npc " .. rule.npcID)) .. suffix .. "|r")

        local label = MFD.Roles.INTENTS[rule.intent] and MFD.Roles.INTENTS[rule.intent].label or rule.intent
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
        row.intent:SetText((canApply and "" or "|cffff4444") .. label .. "|r")
        if not canApply then
            hasBadRule = true
        end

        -- Merged rules are read only until touched; touching one copies it
        -- into the local set. The arrows stay enabled for that reason, but
        -- delete only ever removes a local rule.
        row.delete:SetEnabled(isMine)

        shown = index
    end

    MFD.UI.ReleaseRows(ruleRows, shown + 1)

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
    rulesFrame.search = CreateFrame("EditBox", nil, rulesFrame, "InputBoxTemplate")
    rulesFrame.search:SetSize(200, 20)
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
    rulesFrame.typedAdd = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.typedAdd:SetSize(220, 20)
    rulesFrame.typedAdd:SetPoint("TOPLEFT", rulesFrame.search, "BOTTOMLEFT", 0, -4)
    rulesFrame.typedAdd:Hide()
    rulesFrame.typedAdd:SetScript("OnClick", function()
        local typed = string.match(rulesFrame.search:GetText() or "", "^%s*(.-)%s*$")
        if typed == "" then
            return
        end
        RulesUI:AddRule({ name = typed })
    end)

    rulesFrame.bulk = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.bulk:SetSize(90, 20)
    rulesFrame.bulk:SetPoint("BOTTOMLEFT", rulesFrame, "BOTTOMLEFT", 20, 10)
    rulesFrame.bulk:SetText("Paste list")
    rulesFrame.bulk:SetScript("OnClick", function()
        RulesUI:ShowTransferBox("", "bulk")
    end)

    rulesFrame.share = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.share:SetSize(70, 20)
    rulesFrame.share:SetPoint("LEFT", rulesFrame.bulk, "RIGHT", 8, 0)
    rulesFrame.share:SetText("Share")
    rulesFrame.share:SetScript("OnClick", function()
        RulesUI:ShowTransferBox(MFD.Rules.ToJSON(MFD.db.rules, {}), "exportjson")
    end)

    rulesFrame.load = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.load:SetSize(80, 20)
    rulesFrame.load:SetPoint("LEFT", rulesFrame.share, "RIGHT", 8, 0)
    rulesFrame.load:SetText("Load file")
    rulesFrame.load:SetScript("OnClick", function()
        RulesUI:ShowTransferBox("", "importjson")
    end)

    rulesFrame.format = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.format:SetSize(70, 20)
    rulesFrame.format:SetPoint("LEFT", rulesFrame.load, "RIGHT", 8, 0)
    rulesFrame.format:SetText("Format")
    rulesFrame.format:SetScript("OnClick", function()
        RulesUI:ShowTransferBox(FORMAT_HELP, "help")
    end)

    rulesFrame.filter = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.filter:SetSize(110, 20)
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

    -- Shows where a dragged rule would land. One marker for the whole list
    -- rather than a highlight per row.
    -- The insertion point, drawn in the gap the rule would land in. A frame
    -- rather than a bare texture so it can carry an end cap: a plain line
    -- across the list read as a strike-through of the row it crossed, which is
    -- exactly what it looked like before the row maths were fixed.
    dropMarker = CreateFrame("Frame", nil, rulesFrame.ruleList)
    dropMarker:SetHeight(10)
    dropMarker:SetFrameLevel(rulesFrame.ruleList:GetFrameLevel() + 10)
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

        local list = localList(RulesUI:TargetKey())
        local boundary = boundaryAtCursor(#list)
        if not boundary then
            dropMarker:Hide()
            return
        end

        dropMarker:ClearAllPoints()
        dropMarker:SetPoint("TOPLEFT", self, "TOPLEFT", 0,
            -(boundary * RULE_ROW_HEIGHT) - MFD.UI.ROW_TOP_PADDING + 5)
        dropMarker:SetPoint("RIGHT", self, "RIGHT", 0, 0)
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
    transferFrame = CreateFrame("Frame", "MarkedForDeathTransferFrame", UIParent, "BasicFrameTemplateWithInset")
    transferFrame:SetSize(460, 240)
    transferFrame:SetPoint("CENTER")
    transferFrame:SetMovable(true)
    transferFrame:EnableMouse(true)
    transferFrame:RegisterForDrag("LeftButton")
    transferFrame:SetScript("OnDragStart", transferFrame.StartMoving)
    transferFrame:SetScript("OnDragStop", transferFrame.StopMovingOrSizing)
    transferFrame:SetFrameStrata("DIALOG")
    transferFrame:SetFrameLevel(50)

    transferFrame.title = transferFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    transferFrame.title:SetPoint("TOP", transferFrame, "TOP", 0, -6)

    transferFrame.hint = transferFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    transferFrame.hint:SetPoint("TOPLEFT", transferFrame, "TOPLEFT", 14, -30)

    transferFrame.scroll = CreateFrame("ScrollFrame", nil, transferFrame, "UIPanelScrollFrameTemplate")
    transferFrame.scroll:SetPoint("TOPLEFT", transferFrame, "TOPLEFT", 14, -48)
    transferFrame.scroll:SetPoint("BOTTOMRIGHT", transferFrame, "BOTTOMRIGHT", -32, 40)

    transferFrame.edit = CreateFrame("EditBox", nil, transferFrame.scroll)
    transferFrame.edit:SetMultiLine(true)
    transferFrame.edit:SetAutoFocus(false)
    transferFrame.edit:SetFontObject(ChatFontNormal)
    transferFrame.edit:SetWidth(400)
    transferFrame.edit:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    transferFrame.scroll:SetScrollChild(transferFrame.edit)

    transferFrame.action = CreateFrame("Button", nil, transferFrame, "UIPanelButtonTemplate")
    transferFrame.action:SetSize(100, 22)
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
