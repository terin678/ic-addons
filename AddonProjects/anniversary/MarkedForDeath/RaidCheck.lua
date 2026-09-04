-- Raid buff and consumable check.
--
-- The functions above the "client" marker are pure and tested. Everything
-- below it touches the client and runs from RegisterInit or a command.
local MFD = _G.MarkedForDeath or {}

MFD.RaidCheck = MFD.RaidCheck or {}
local RC = MFD.RaidCheck

-- Takes an array of aura names on one unit. Returns that unit's buff state.
-- Unknown names are ignored. Booleans are explicit false when absent so a
-- cell can be painted red rather than grey.
function RC.Classify(auraNames)
    local A = MFD.Data.Auras
    local state = {
        food = nil, flask = nil, battle = nil, guardian = nil, unclassifiedElixir = nil,
        blessings = {},
    }
    for column in pairs(A.RAID_BUFFS) do
        state[column] = false
    end

    local nameSet = {}
    for _, name in ipairs(auraNames) do
        if type(name) == "string" and name ~= "" then
            nameSet[name] = true
        end
    end

    for column, def in pairs(A.RAID_BUFFS) do
        for _, name in ipairs(def.names) do
            if nameSet[name] then
                state[column] = true
            end
        end
    end

    local blessingSeen = {}
    for name in pairs(nameSet) do
        if A.FOOD[name] then
            state.food = name
        elseif string.sub(name, 1, #A.FLASK_PREFIX) == A.FLASK_PREFIX then
            state.flask = name
        elseif A.BATTLE_ELIXIRS[name] then
            state.battle = name
        elseif A.GUARDIAN_ELIXIRS[name] then
            state.guardian = name
        elseif string.find(name, A.ELIXIR_PATTERN, 1, true) then
            state.unclassifiedElixir = name
        elseif A.BLESSINGS[name] then
            blessingSeen[A.BLESSINGS[name]] = true
        end
    end

    for label in pairs(blessingSeen) do
        state.blessings[#state.blessings + 1] = label
    end
    table.sort(state.blessings)

    return state
end

-- What the raid can be asked to bring. Flask and the two elixirs are one
-- requirement, not three: a flask fills both elixir slots, so nobody can hold a
-- flask and an elixir at once. Asking for all three separately would report
-- half the raid missing something they physically cannot have.
RC.CONSUMABLE_ORDER = { "FOOD", "ELIXIRS" }
RC.CONSUMABLE_LABELS = {
    FOOD = "Food", ELIXIRS = "Flask or elixirs",
}

-- Takes the roster ({ name, class } array). Returns { [column] = bool } saying
-- whether anyone present can cast each raid buff. Pure.
function RC.Providers(roster)
    local classesPresent, classCounts = {}, {}
    for _, member in ipairs(roster or {}) do
        classesPresent[member.class] = true
        classCounts[member.class] = (classCounts[member.class] or 0) + 1
    end

    local providers = {}
    for column, def in pairs(MFD.Data.Auras.RAID_BUFFS) do
        providers[column] = false
        for _, class in ipairs(def.classes) do
            if classesPresent[class] then
                providers[column] = true
            end
        end
    end

    -- Not a boolean: how many blessings somebody should be carrying is however
    -- many paladins are in the raid, one each, and that changes week to week.
    providers.BLESSING_COUNT = 0
    for _, class in ipairs(MFD.Data.Auras.BLESSING_CLASSES) do
        providers.BLESSING_COUNT = providers.BLESSING_COUNT + (classCounts[class] or 0)
    end
    providers.BLESSING = providers.BLESSING_COUNT > 0

    return providers
end

-- Takes a player's state, the providers table and { [consumable] = true } for
-- the consumables the raid expects. Returns an array of { column, label } in a
-- fixed order: raid buffs first, then consumables. Pure.
--
-- A raid buff is missing only when absent AND someone present can cast it.
-- A consumable is missing only when expected AND known to be absent; unknown
-- (no self-report yet) is never reported, because "no data" is not "no flask".
function RC.Missing(state, providers, expected)
    local A = MFD.Data.Auras
    local missing = {}

    for _, column in ipairs(A.RAID_BUFF_ORDER) do
        if providers[column] and state[column] == false then
            missing[#missing + 1] = { column = column, label = A.RAID_BUFFS[column].label }
        end
    end

    -- One blessing per paladin present. Which blessings those should be is
    -- still the raid leader's call, so only the shortfall is reported; the
    -- grid shows exactly which ones somebody is actually carrying.
    --
    -- The label stays plain so everybody short a blessing groups onto one
    -- callout line; the counts ride alongside for the grid to show.
    local expectedBlessings = providers.BLESSING_COUNT or 0
    if expectedBlessings > 0 and #state.blessings < expectedBlessings then
        missing[#missing + 1] = {
            column = "BLESSING",
            label = "Blessing",
            have = #state.blessings,
            expected = expectedBlessings,
        }
    end

    -- Two ways to meet the elixir requirement and they are exclusive in the
    -- game: a flask, or a battle elixir and a guardian elixir together. One
    -- elixir on its own is half the job and is reported.
    local present = {
        FOOD = state.food ~= nil,
        ELIXIRS = state.flask ~= nil or (state.battle ~= nil and state.guardian ~= nil),
    }

    for _, column in ipairs(RC.CONSUMABLE_ORDER) do
        if expected[column] and present[column] == false then
            missing[#missing + 1] = { column = column, label = RC.CONSUMABLE_LABELS[column] }
        end
    end

    return missing
end

local REPORT_ONLY = { "durability", "spec", "version" }
local FLAG_ONLY = { "AI", "MOTW", "FORT", "SP" }

-- Takes a scanned state, a reported state (or nil) and a durability percent
-- learned through the shared LibDurability protocol (or nil). Returns
-- { state, isReported }. Pure.
--
-- The owning client is the authority on its own flags, so a non-nil reported
-- flag overrides the scan. Names come only from the scan because the wire
-- carries flags, not names. Spec and version come only from the
-- report because nothing else can see them. Durability prefers the report and
-- falls back to LibDurability, which most raiders answer through BigWigs, DBM
-- or MRT whether or not they run this addon.
function RC.MergeRow(scanned, reported, libDurability, inspectedSpec, brokenItems)
    local state = {}
    for k, v in pairs(scanned) do
        state[k] = v
    end

    -- Broken gear only ever comes from the shared durability protocol. Kept
    -- separate from the percent because 40% with a broken weapon is a
    -- different problem from 40% spread evenly across everything.
    state.brokenItems = brokenItems

    if not reported then
        state.durability = libDurability
        state.spec = inspectedSpec
        return { state = state, isReported = false }
    end

    for _, key in ipairs(FLAG_ONLY) do
        if reported[key] ~= nil then
            state[key] = reported[key]
        end
    end

    for _, key in ipairs(REPORT_ONLY) do
        state[key] = reported[key]
    end

    if state.durability == nil then
        state.durability = libDurability
    end
    if state.spec == nil then
        state.spec = inspectedSpec
    end

    return { state = state, isReported = true }
end

-- Reads one GetTalentTabInfo result. Returns the tab name and points spent,
-- or nil when the returns are not a talent tab. Pure.
--
-- The API has two shapes across client builds:
--   name, iconTexture, pointsSpent, ...
--   id, name, description, iconTexture, pointsSpent, ...
-- Anniversary uses the second. Reading it as the first put the description
-- string where the points number belonged, and comparing that string to a
-- number threw inside GatherSelf, which aborted the whole raid check scan and
-- left the grid reading "nobody in the group". Points are coerced so a
-- surprise value can never reach a comparison again.
function RC.ParseTalentTab(a, b, c, d, e)
    local name, points
    if type(a) == "string" then
        name, points = a, c
    elseif type(b) == "string" then
        name, points = b, e
    else
        return nil
    end

    if type(name) ~= "string" or name == "" then
        return nil
    end

    return name, tonumber(points) or 0
end

-- Takes an array of { name, points } talent tabs. Returns the name of the tab
-- with the most points, or nil when none are spent. Ties go to the first tab
-- so the answer is stable. Pure.
function RC.SpecFromTabs(tabs)
    local bestName, bestPoints = nil, 0
    for _, tab in ipairs(tabs or {}) do
        if (tab.points or 0) > bestPoints then
            bestName, bestPoints = tab.name, tab.points
        end
    end
    return bestName
end

-- Takes row entries, the inspected cache ({ [name] = { spec, at } }), the time
-- and a ttl. Returns the name of the first player, by name, whose spec is not
-- self-reported and whose inspection is missing or older than ttl, or nil.
-- Pure. Self-reported specs are never inspected: the owning client is the
-- authority, and inspecting costs a request each.
function RC.NextInspectTarget(entries, inspected, now, ttl)
    local sorted = {}
    for _, entry in ipairs(entries or {}) do
        sorted[#sorted + 1] = entry
    end
    table.sort(sorted, function(a, b)
        return a.name < b.name
    end)

    for _, entry in ipairs(sorted) do
        local isSelfReported = entry.row and entry.row.isReported and entry.row.state.spec ~= nil
        local cached = inspected[entry.name]
        local isFresh = cached and (now - cached.at) < ttl
        if not isSelfReported and not isFresh then
            return entry.name
        end
    end

    return nil
end

-- Takes a LibDurability message. Returns percent and broken-item count for a
-- response, or nil for a request or anything else. The protocol is one line:
-- "R" asks, "percent,broken" answers. Pure.
function RC.ParseDurabilityMessage(msg)
    if type(msg) ~= "string" then
        return nil
    end
    local percent, broken = string.match(msg, "^(%d+),(%d+)$")
    if not percent then
        return nil
    end
    return tonumber(percent), tonumber(broken)
end

RC.CALLOUT_THROTTLE_SECONDS = 10  -- minimum gap between raid-chat callouts
RC.CALLOUT_MAX_LINES = 4          -- lines per callout
RC.CALLOUT_LINE_BYTES = 200       -- bytes per line, under the chat cap

-- Takes row entries ({ name, missing }). Returns chat lines grouped by fix,
-- in the order fixes first appear, names sorted, capped and truncated. Pure.
-- Grouping by fix rather than by player is what makes it actionable: the
-- paladin reads the Kings line, the mage reads the Int line.
function RC.FormatCallout(entries)
    local byFix, order = {}, {}
    for _, entry in ipairs(entries) do
        for _, m in ipairs(entry.missing or {}) do
            if not byFix[m.label] then
                byFix[m.label] = {}
                order[#order + 1] = m.label
            end
            table.insert(byFix[m.label], entry.name)
        end
    end

    local lines = {}
    for i, label in ipairs(order) do
        if i > RC.CALLOUT_MAX_LINES then
            -- Never silently exceed the cap: the last kept line says how many
            -- fixes were left out.
            lines[#lines] = lines[#lines] .. " (and " .. (#order - RC.CALLOUT_MAX_LINES) .. " more)"
            break
        end
        local names = byFix[label]
        table.sort(names)
        local line = label .. ": " .. table.concat(names, ", ")
        if #line > RC.CALLOUT_LINE_BYTES then
            line = string.sub(line, 1, RC.CALLOUT_LINE_BYTES - 3) .. "..."
        end
        lines[#lines + 1] = line
    end

    return lines
end

-- Takes one row entry. Returns a whisper line, or nil when there is nothing
-- to say. Pure.
function RC.FormatWhisper(entry)
    if not entry.missing or #entry.missing == 0 then
        return nil
    end
    local labels = {}
    for _, m in ipairs(entry.missing) do
        labels[#labels + 1] = m.label
    end
    return "You are missing: " .. table.concat(labels, ", ")
end

RC.REPORT_HEARTBEAT_SECONDS = 60   -- periodic self-report while in a group
RC.REPORT_DEBOUNCE_SECONDS = 2     -- coalesce bursts of change into one report

-- Tri-state flags on the wire: 1 true, 0 false, ? unknown. Unknown must stay
-- distinct from false, because "no data" is not "no flask".
local FLAG_ORDER = { "AI", "MOTW", "FORT", "SP", "food", "flask", "battle", "guardian" }

local function flagChar(v)
    if v == true then
        return "1"
    end
    if v == false then
        return "0"
    end
    return "?"
end

local function charFlag(c)
    if c == "1" then
        return true
    end
    if c == "0" then
        return false
    end
    return nil
end

-- Takes a state. Returns the fields array for a PC message:
-- { version, flags, durability, spec }. Pure.
function RC.EncodeReport(state)
    local flags = {}
    for i, key in ipairs(FLAG_ORDER) do
        flags[i] = flagChar(state[key])
    end
    return {
        state.version or "?",
        table.concat(flags),
        state.durability and tostring(math.floor(state.durability)) or "?",
        state.spec or "?",
    }
end

-- Takes the fields array from a PC message. Returns a state, or nil when the
-- fields are not a report. Pure.
function RC.DecodeReport(fields)
    if type(fields) ~= "table" or #fields < 4 then
        return nil
    end
    local flags = fields[2]
    if type(flags) ~= "string" or #flags ~= #FLAG_ORDER then
        return nil
    end

    local state = { version = fields[1] ~= "?" and fields[1] or nil }
    for i, key in ipairs(FLAG_ORDER) do
        state[key] = charFlag(string.sub(flags, i, i))
    end
    state.durability = tonumber(fields[3])
    state.spec = fields[4] ~= "?" and fields[4] or nil
    return state
end

-- ---------------------------------------------------------------- client --
-- Everything below touches the client. Nothing here runs at file scope
-- beyond caching globals, so the harness can still load this file.

local UnitAura = UnitAura
local GetInventoryItemDurability = GetInventoryItemDurability
local GetTalentTabInfo = GetTalentTabInfo

-- Reports received from other clients, { [playerName] = { state, at } }.
RC.reports = {}

-- Returns an array of aura names on unit. Reads only the first return of
-- UnitAura, which is the name on every client build. Wrapped because the
-- return signature differs across the flavors this repo targets.
function RC.AuraNames(unit)
    local names = {}
    if not UnitAura then
        return names
    end
    for i = 1, 40 do
        local ok, name = pcall(UnitAura, unit, i, "HELPFUL")
        if not ok or not name then
            break
        end
        names[#names + 1] = name
    end
    return names
end

-- Equipped item slots that have durability: head, shoulder, chest, waist,
-- legs, feet, wrist, hands, main hand, off hand, ranged. Same slots the
-- repair vendor totals.
local DURABILITY_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- Returns the overall durability percent and how many equipped items are at
-- zero, or nil when nothing is equipped. The broken count is reported
-- separately because a broken weapon matters more than a low average.
local function durabilityPercent()
    if not GetInventoryItemDurability then
        return nil
    end
    local current, maximum, broken = 0, 0, 0
    for _, slot in ipairs(DURABILITY_SLOTS) do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and cur and max and max > 0 then
            current = current + cur
            maximum = maximum + max
            if cur == 0 then
                broken = broken + 1
            end
        end
    end
    if maximum == 0 then
        return nil
    end
    return math.floor(current / maximum * 100), broken
end

local function specName()
    if not GetTalentTabInfo then
        return nil
    end

    local tabs = {}
    for tab = 1, 3 do
        local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
        if ok then
            local name, points = RC.ParseTalentTab(a, b, c, d, e)
            if name then
                tabs[#tabs + 1] = { name = name, points = points }
            end
        end
    end

    return RC.SpecFromTabs(tabs)
end

-- Reads this client's own state. The only place durability and spec can be
-- learned from directly, which is why they are self-reported.
function RC:GatherSelf()
    local state = RC.Classify(RC.AuraNames("player"))
    state.version = MFD.VERSION
    state.durability = durabilityPercent()
    state.spec = specName()

    -- Flatten names to flags for the wire; a receiver in range has the names
    -- from its own scan, and names for twenty five people do not fit.
    state.food = state.food ~= nil
    state.flask = state.flask ~= nil
    state.battle = state.battle ~= nil
    state.guardian = state.guardian ~= nil
    return state
end

local isReportPending = false

-- Sends a self-report, debounced so a mass rebuff produces one message per
-- client rather than one per buff. Nothing is sent when solo.
function RC:SendReport()
    if isReportPending then
        return
    end
    isReportPending = true
    C_Timer.After(RC.REPORT_DEBOUNCE_SECONDS, function()
        isReportPending = false
        if not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
            return
        end
        MFD.Comms:Send("PC", RC.EncodeReport(RC:GatherSelf()))
    end)
end

-- Called by Comms when a PC message arrives.
function RC:ReceiveReport(sender, fields)
    local state = RC.DecodeReport(fields)
    if not state then
        return
    end
    RC.reports[sender] = { state = state, at = GetTime() }
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- One entry per group member, { [name] = { name, class, unit, row, missing,
-- scannedAt } }, rebuilt by Scan and patched by ScanUnit.
RC.rows = {}
RC.providers = {}

-- Returns the unit tokens for everyone in the group, self included.
function RC.GroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
        return units
    end
    units[1] = "player"
    if IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

local function expectedConsumables()
    return MFD.db.settings.raidCheck.expected
end

-- Rebuilds one player's row from a live unit token. Providers must already
-- be current; Scan sets them, and a single-unit rescan reuses them.
function RC:ScanUnit(unit)
    local name = UnitName(unit)
    if not name or name == "" then
        return
    end
    local _, class = UnitClass(unit)
    local scanned = RC.Classify(RC.AuraNames(unit))
    -- The local player is their own authority: a client never receives its
    -- own report, so without this the own row would read as scan-only.
    local reported
    if name == UnitName("player") then
        -- Wrapped because everything in here reads a client API whose shape
        -- can differ by build, and one of them blanking the entire grid is
        -- exactly the failure this addon already shipped once.
        local ok, gathered = pcall(RC.GatherSelf, RC)
        reported = ok and gathered or nil
        if not ok then
            MFD.Error("could not read your own buffs: " .. tostring(gathered))
        end
    else
        reported = RC.reports[name] and RC.reports[name].state or nil
    end
    local libDurability = RC.durability[name] and RC.durability[name].percent or nil
    local brokenItems = RC.durability[name] and RC.durability[name].broken or nil
    local inspectedSpec = RC.inspected[name] and RC.inspected[name].spec or nil
    local row = RC.MergeRow(scanned, reported, libDurability, inspectedSpec, brokenItems)
    RC.rows[name] = {
        name = name,
        class = class,
        unit = unit,
        row = row,
        missing = RC.Missing(row.state, RC.providers, expectedConsumables()),
        scannedAt = GetTime(),
    }
end

-- Rebuilds every row. Providers first, because Missing depends on them.
function RC:Scan()
    RC:RequestDurability()
    RC.providers = RC.Providers(MFD.Marker.CurrentRoster())
    wipe(RC.rows)
    for _, unit in ipairs(RC.GroupUnits()) do
        RC:ScanUnit(unit)
    end
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- Returns the rows as an array sorted by name, so every surface lists people
-- in the same order.
function RC:SortedRows()
    local list = {}
    for _, entry in pairs(RC.rows) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

local lastCalloutAt = 0

-- Posts the callout to raid or party chat, throttled so a second click a
-- moment later does not double post.
-- Starts a real ready check. This is the native one: everybody gets Blizzard's
-- window, and our own READY_CHECK handler then opens the grid and asks the
-- group for durability. Needs leader or assistant, like the raid frame button.
function RC:StartReadyCheck()
    if not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup()) then
        MFD.Error("not in a group")
        return
    end

    local canStart = UnitIsGroupLeader("player")
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    if not canStart then
        MFD.Error("you need to be raid leader or an assistant to start a ready check")
        return
    end

    if type(DoReadyCheck) ~= "function" then
        MFD.Error("this client has no ready check function")
        return
    end

    pcall(DoReadyCheck)
end

function RC:PostCallout()
    if not MFD.IsEnabled() then
        MFD.Print("the addon is switched off. /mfd on to resume.")
        return
    end

    local now = GetTime()
    if (now - lastCalloutAt) < RC.CALLOUT_THROTTLE_SECONDS then
        MFD.Print("callout throttled, try again in a few seconds")
        return
    end

    local target = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
    if not target then
        MFD.Error("not in a group")
        return
    end

    RC:Scan()
    local lines = RC.FormatCallout(RC:SortedRows())
    if #lines == 0 then
        MFD.Print("nothing to call out")
        return
    end

    lastCalloutAt = now
    for _, line in ipairs(lines) do
        pcall(SendChatMessage, "[MFD] " .. line, target)
    end
end

-- Whispers one player what they are missing.
function RC:Whisper(name)
    local entry = RC.rows[name]
    local text = entry and RC.FormatWhisper(entry)
    if not text then
        MFD.Print(tostring(name) .. " is not missing anything")
        return
    end
    pcall(SendChatMessage, "[MFD] " .. text, "WHISPER", nil, name)
end

-- Durability learned through LibDurability, { [name] = { percent, broken, at } }.
-- The library is embedded by BigWigs, DBM and MRT among others, so nearly
-- every raider answers its request regardless of what else they run. It is
-- used through LibStub when any loaded addon provides it, and the same
-- one-line protocol is spoken directly when none does.
RC.durability = {}
RC.DURABILITY_PREFIX = "LibDRBLT"
RC.DURABILITY_REQUEST_SECONDS = 10   -- minimum gap between our own requests
RC.DURABILITY_RESPOND_SECONDS = 4    -- matches the library's own response throttle

local libDurability
local isDurabilityHooked = false
local lastDurabilityRequestAt = 0
local lastDurabilityResponseAt = 0
local durabilityFrame

local function durabilityChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function recordDurability(percent, broken, sender)
    local name = string.match(sender or "", "^([^%-]+)") or sender
    if not name or name == "" then
        return
    end
    RC.durability[name] = { percent = percent, broken = broken, at = GetTime() }
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

-- Sends our own durability in the shared format, throttled the way the
-- library throttles itself, so a client with no other addon providing the
-- library still answers everyone else's requests.
local function respondDurability(channel)
    local now = GetTime()
    if (now - lastDurabilityResponseAt) < RC.DURABILITY_RESPOND_SECONDS then
        return
    end
    lastDurabilityResponseAt = now
    local percent, broken = durabilityPercent()
    if not percent then
        return
    end
    local sendFn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(sendFn) == "function" then
        pcall(sendFn, RC.DURABILITY_PREFIX, string.format("%d,%d", percent, broken or 0), channel)
    end
end

-- Hooks into the durability source once: the library if present, else our
-- own listener on its prefix. Guarded on every side per the repo standard.
local function hookDurability()
    if isDurabilityHooked then
        return
    end
    isDurabilityHooked = true

    if LibStub and type(LibStub.GetLibrary) == "function" then
        local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibDurability", true)
        if ok and lib and type(lib.Register) == "function" then
            libDurability = lib
            pcall(lib.Register, lib, "MarkedForDeath", function(percent, broken, sender)
                recordDurability(percent, broken, sender)
            end)
            return
        end
    end

    -- No library anywhere in the client: speak the protocol directly.
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, RC.DURABILITY_PREFIX)
    end
    durabilityFrame = CreateFrame("Frame")
    durabilityFrame:RegisterEvent("CHAT_MSG_ADDON")
    durabilityFrame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix ~= RC.DURABILITY_PREFIX then
            return
        end
        if msg == "R" then
            respondDurability(channel)
            return
        end
        local percent, broken = RC.ParseDurabilityMessage(msg)
        if percent then
            recordDurability(percent, broken, sender)
        end
    end)
end

-- Asks the group for durability. Nothing is sent when solo, and requests are
-- throttled because the answers arrive from everyone at once.
function RC:RequestDurability()
    hookDurability()

    local channel = durabilityChannel()
    if not channel then
        return
    end

    local now = GetTime()
    if (now - lastDurabilityRequestAt) < RC.DURABILITY_REQUEST_SECONDS then
        return
    end
    lastDurabilityRequestAt = now

    if libDurability then
        pcall(libDurability.RequestDurability, libDurability, channel)
        return
    end

    local sendFn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(sendFn) == "function" then
        pcall(sendFn, RC.DURABILITY_PREFIX, "R", channel)
    end
end

-- Spec by inspection. Works on anyone within inspect range running nothing at
-- all, which is more than any addon-to-addon protocol on this client can
-- offer: LibSpecialization has no TBC branch, and MRT does not send spec.
-- One request in flight at a time, throttled, cached, skipped in combat, and
-- every wait times out.
RC.INSPECT_TTL_SECONDS = 60             -- how long an inspected spec is trusted
RC.INSPECT_INTERVAL_SECONDS = 1.5       -- gap between inspect requests
RC.INSPECT_TIMEOUT_SECONDS = 3          -- give up waiting for INSPECT_READY
RC.INSPECT_RETRY_SECONDS = 10           -- wait before retrying an out-of-range player
RC.INSPECT_READY_CHECK_SECONDS = 20     -- keep inspecting this long after a ready check

RC.inspected = {}        -- [name] = { spec, at }
RC.inspectWanted = 0     -- surfaces currently shown that want specs
RC.inspectUntil = 0      -- inspect regardless until this time

local NotifyInspect = NotifyInspect
local CanInspect = CanInspect
local CheckInteractDistance = CheckInteractDistance
local InCombatLockdown = InCombatLockdown
local GetNumTalents = GetNumTalents
local GetTalentInfo = GetTalentInfo

local pendingGuid, pendingName, pendingAt

-- Reads the inspected unit's talent tabs. Prefers the tab totals; if the
-- client reports none, sums the ranks of every talent in the tab instead,
-- which is how the Classic inspect libraries do it.
local function readInspectedTabs()
    local tabs = {}
    for tab = 1, 3 do
        local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab, true)
        local name, points
        if ok then
            name, points = RC.ParseTalentTab(a, b, c, d, e)
        end
        if name then
            local total = points or 0
            if total == 0 and GetNumTalents and GetTalentInfo then
                local okCount, count = pcall(GetNumTalents, tab, true)
                for i = 1, (okCount and tonumber(count)) or 0 do
                    local okTalent, _, _, _, _, rank = pcall(GetTalentInfo, tab, i, true)
                    if okTalent then
                        total = total + (tonumber(rank) or 0)
                    end
                end
            end
            tabs[#tabs + 1] = { name = name, points = total }
        end
    end
    return tabs
end

-- Stamps a player so the pump moves on rather than spinning on someone out
-- of range, keeping any spec already known.
local function deferInspect(name, now)
    local previous = RC.inspected[name]
    RC.inspected[name] = {
        spec = previous and previous.spec or nil,
        at = now - RC.INSPECT_TTL_SECONDS + RC.INSPECT_RETRY_SECONDS,
    }
end

-- Issues at most one inspect request per call, and only when a surface wants
-- specs or a ready check recently happened.
function RC:PumpInspect(now)
    if pendingGuid and (now - pendingAt) > RC.INSPECT_TIMEOUT_SECONDS then
        deferInspect(pendingName, now)
        pendingGuid = nil
    end
    if pendingGuid then
        return
    end
    if RC.inspectWanted <= 0 and now > RC.inspectUntil then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if not NotifyInspect or not CanInspect then
        return
    end

    local name = RC.NextInspectTarget(RC:SortedRows(), RC.inspected, now, RC.INSPECT_TTL_SECONDS)
    if not name then
        return
    end

    local entry = RC.rows[name]
    local unit = entry and entry.unit
    if not unit or name == UnitName("player") then
        deferInspect(name, now)
        return
    end

    local okRange, isInRange = pcall(CheckInteractDistance, unit, 1)
    local okCan, canInspect = pcall(CanInspect, unit, false)
    if not (okRange and isInRange and okCan and canInspect) then
        deferInspect(name, now)
        return
    end

    pendingGuid, pendingName, pendingAt = UnitGUID(unit), name, now
    pcall(NotifyInspect, unit)
end

local function onInspectReady(guid)
    if not pendingGuid or guid ~= pendingGuid then
        return
    end
    local name = pendingName
    pendingGuid = nil
    RC.inspected[name] = { spec = RC.SpecFromTabs(readInspectedTabs()), at = GetTime() }

    local entry = RC.rows[name]
    if entry and entry.unit then
        RC:ScanUnit(entry.unit)
    end
    if RC.OnDataChanged then
        RC.OnDataChanged()
    end
end

local inspectAccumulator = 0

local heartbeat = 0

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("INSPECT_READY")

    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "INSPECT_READY" then
            onInspectReady(unit)
            return
        end
        if (event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_AURA") and unit ~= "player" then
            return
        end
        RC:SendReport()
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        heartbeat = heartbeat + elapsed
        if heartbeat >= RC.REPORT_HEARTBEAT_SECONDS then
            heartbeat = 0
            RC:SendReport()
        end

        inspectAccumulator = inspectAccumulator + elapsed
        if inspectAccumulator >= RC.INSPECT_INTERVAL_SECONDS then
            inspectAccumulator = 0
            local ok, err = pcall(RC.PumpInspect, RC, GetTime())
            if not ok then
                MFD.Error("inspect failed: " .. tostring(err))
            end
        end
    end)
end)

_G.MarkedForDeath = MFD
