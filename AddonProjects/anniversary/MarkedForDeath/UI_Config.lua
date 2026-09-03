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

local function localIndexOf(list, npcID)
    for i, rule in ipairs(list) do
        if rule.npcID == npcID then
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
    local index = localIndexOf(list, merged.npcID)
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

local function intentNamesSorted()
    local names = {}
    for intent in pairs(MFD.Seats.INTENTS) do
        names[#names + 1] = intent
    end
    table.sort(names)
    return names
end

local function nextIntent(current)
    local names = intentNamesSorted()
    for i, name in ipairs(names) do
        if name == current then
            return names[(i % #names) + 1]
        end
    end
    return names[1]
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
            RulesUI:OpenFor(row.result.npcID, row.result.name)
        end
    end)
end

local function buildRuleRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")

    row.intent = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.intent:SetSize(88, 20)
    row.intent:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.intent:SetScript("OnClick", function()
        if not row.rule then
            return
        end
        local rule = ownedRule(row.instanceKey, row.rule)
        rule.intent = nextIntent(rule.intent)
        commitRules()
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
        local index = localIndexOf(list, row.rule.npcID)
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

    if #lastResults == 0 then
        rulesFrame.resultsNote:SetText("|cff999999no mobs match. Target one and press the add key.|r")
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

        local isMine = rule.owner == me or rule.owner == nil
        local color = isMine and "" or "|cffffcc66"
        local suffix = isMine and "" or ("  (" .. tostring(rule.owner) .. ")")

        row.rank:SetText(tostring(rule.rank))
        row.name:SetText(color .. (rule.name or ("npc " .. rule.npcID)) .. suffix .. "|r")

        local label = MFD.Seats.INTENTS[rule.intent] and MFD.Seats.INTENTS[rule.intent].label or rule.intent
        local learned = MFD.db.learnedMobs[rule.npcID]
        local canApply = MFD.Seats.CanIntentApply(rule.intent, learned and learned.creatureType)
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
    if not localIndexOf(list, npcID) then
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

local function buildRulesFrame()
    rulesFrame = CreateFrame("Frame", "MarkedForDeathRulesFrame", UIParent, "BasicFrameTemplateWithInset")
    rulesFrame:SetSize(720, 440)
    rulesFrame:SetPoint("CENTER")
    rulesFrame:SetMovable(true)
    rulesFrame:EnableMouse(true)
    rulesFrame:RegisterForDrag("LeftButton")
    rulesFrame:SetScript("OnDragStart", rulesFrame.StartMoving)
    rulesFrame:SetScript("OnDragStop", rulesFrame.StopMovingOrSizing)
    rulesFrame:SetFrameStrata("DIALOG")

    rulesFrame.title = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rulesFrame.title:SetPoint("TOP", rulesFrame, "TOP", 0, -6)
    rulesFrame.title:SetText("Marked For Death: rules")

    -- Left pane: search.
    rulesFrame.search = CreateFrame("EditBox", nil, rulesFrame, "InputBoxTemplate")
    rulesFrame.search:SetSize(200, 20)
    rulesFrame.search:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 20, -34)
    rulesFrame.search:SetAutoFocus(false)
    rulesFrame.search:SetScript("OnTextChanged", function()
        paintResults()
    end)
    rulesFrame.search:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)

    rulesFrame.filter = CreateFrame("Button", nil, rulesFrame, "UIPanelButtonTemplate")
    rulesFrame.filter:SetSize(110, 20)
    rulesFrame.filter:SetPoint("LEFT", rulesFrame.search, "RIGHT", 6, 0)
    rulesFrame.filter:SetScript("OnClick", function()
        cycleFilter()
        RulesUI:Refresh()
    end)

    rulesFrame.resultsNote = rulesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rulesFrame.resultsNote:SetPoint("TOPLEFT", rulesFrame.search, "BOTTOMLEFT", 0, -4)
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
    rulesFrame.ruleHint:SetText("top = highest priority.  amber = merged from another player")

    rulesFrame.ruleList = CreateFrame("Frame", nil, rulesFrame)
    rulesFrame.ruleList:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 342, -76)
    rulesFrame.ruleList:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMRIGHT", -6, 6)

    rulesFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rulesFrame:SetScript("OnEvent", function()
        RulesUI:Refresh()
    end)

    tinsert(UISpecialFrames, "MarkedForDeathRulesFrame")
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
        else
            transferFrame:Hide()
        end
    end)

    tinsert(UISpecialFrames, "MarkedForDeathTransferFrame")
end

-- Shows the transfer window. mode is "export" (text is shown, selected, and
-- the button closes) or "import" (text is editable and the button imports).
function RulesUI:ShowTransferBox(text, mode)
    if not transferFrame then
        buildTransferFrame()
    end

    transferFrame.mode = mode
    transferFrame.edit:SetText(text or "")

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
    if not rulesFrame then
        buildRulesFrame()
    end

    if rulesFrame:IsShown() then
        rulesFrame:Hide()
        return
    end

    filterKey = nil
    rulesFrame:Show()
    RulesUI:Refresh()
end

_G.MarkedForDeath = MFD
