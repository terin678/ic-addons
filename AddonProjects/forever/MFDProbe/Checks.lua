local addonName, ns = ...

--[[
Checks: the questions MarkedForDeath needs answered on this client, asked in the moment.

Each check adds rows to a run. A row says what one call came to (ok, secret, none,
refused, error, absent) and whether the player was in combat when it was asked. Calls
that only show their result later (a raid mark taking, a chat line coming back, an
inspect answering) add their row when the answer comes or the wait runs out.

    Checks.Run(phase, trigger, heavy)  -> run    every light check, and the heavy ones when asked
    Checks.Context()                   -> ctx    where the player is, for the run's header

Light checks only read, or set and put back a raid mark. Heavy checks send chat and addon
messages, inspect a group member, switch combat logging and make a secure button: they
run on a typed command and once in a pull, not on every tick.
]]

local Checks = {}
ns.Checks = Checks

-- Raid target icons the probe sets, one per kind of unit so a reader can tell them apart:
-- 1 star, 2 circle, 3 diamond, 4 triangle, 6 square.
Checks.ICONS = { target = 1, mouseover = 2, plate = 3, plate2 = 4, player = 6 }

-- Seconds before an echo is given up on, an inspect is.
local ECHO_WAIT = 4
local INSPECT_WAIT = 5

-- Hostile nameplates asked about per run, and group members.
local PLATES = 2
local MEMBERS = 4

local PREFIX = "MFDProbe"

-- Chat channels tried, in order. MarkedForDeath announces to all of these.
Checks.CHANNELS = { "PARTY", "RAID", "INSTANCE_CHAT", "RAID_WARNING", "SAY" }
Checks.ADDON_CHANNELS = { "PARTY", "RAID", "INSTANCE_CHAT" }

-- The chat events a sent line comes back on, per channel.
local ECHO_EVENTS = {
    PARTY = { CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true },
    RAID = { CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true },
    INSTANCE_CHAT = { CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true },
    RAID_WARNING = { CHAT_MSG_RAID_WARNING = true },
    SAY = { CHAT_MSG_SAY = true },
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function Add(run, id, fn, ...)
    return ns.AddRow(run, id, ns.Call(fn, ...))
end

-- A row written by hand, for an answer that is not one call's return.
local function Note(run, id, outcome, text)
    local row = { id = id, outcome = outcome, v = text, combat = ns.InCombat() }
    run.rows[#run.rows + 1] = row
    return row
end

-- The first value a call returned, or nil when the call failed or the value is secret.
local function Plain(fn, ...)
    local call = ns.Call(fn, ...)
    if not call.ok or call.n == 0 then return nil end
    local v = call.values[1]
    if ns.IsSecret(v) then return nil end
    return v
end

local function Exists(unit)
    return Plain(UnitExists, unit) == true
end

-- The hostile units worth asking about now: what the player targets and points at, and
-- the first few hostile nameplates. Each is { unit, label }.
function Checks.HostileUnits()
    local units = {}
    for _, unit in ipairs({ "target", "mouseover" }) do
        if Exists(unit) and Plain(UnitIsPlayer, unit) ~= true then
            units[#units + 1] = { unit = unit, label = unit }
        end
    end
    local found = 0
    for i = 1, 40 do
        if found >= PLATES then break end
        local unit = "nameplate" .. i
        if Exists(unit) then
            local attackable = ns.Call(UnitCanAttack, "player", unit)
            local v = attackable.ok and attackable.values[1]
            -- A secret answer is kept: whether hostility itself is hidden is the question.
            if ns.IsSecret(v) or v == true then
                found = found + 1
                units[#units + 1] = { unit = unit, label = found == 1 and "plate" or "plate2" }
            end
        end
    end
    return units
end

-- The group members asked about: party1-4, or the first few raid members who are not the
-- player.
function Checks.Members()
    local units = {}
    local raid = Plain(IsInRaid) == true
    local n = Plain(GetNumGroupMembers) or 0
    for i = 1, raid and n or 4 do
        if #units >= MEMBERS then break end
        local unit = (raid and "raid" or "party") .. i
        if Exists(unit) and Plain(UnitIsUnit, unit, "player") ~= true then units[#units + 1] = unit end
    end
    return units
end

--------------------------------------------------------------------------------
-- Where the player is
--------------------------------------------------------------------------------

function Checks.Restrictions()
    local list = {}
    local types = Enum and Enum.AddOnRestrictionType
    if type(types) ~= "table" then return list end
    for name, value in pairs(types) do list[#list + 1] = { name = name, value = value } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Checks.Context()
    local ctx = { combat = ns.InCombat(), affecting = Plain(UnitAffectingCombat, "player") }
    local inInstance, instanceType = nil, nil
    local call = ns.Call(IsInInstance)
    if call.ok then inInstance, instanceType = call.values[1], call.values[2] end
    ctx.inInstance = not ns.IsSecret(inInstance) and inInstance or nil
    ctx.instanceType = not ns.IsSecret(instanceType) and instanceType or nil
    local info = ns.Call(GetInstanceInfo)
    if info.ok then
        local name, _, difficulty, instanceId = info.values[1], info.values[2], info.values[3], info.values[8]
        if not ns.IsSecret(name) then ctx.instanceName = name end
        if not ns.IsSecret(difficulty) then ctx.difficulty = difficulty end
        if not ns.IsSecret(instanceId) then ctx.instanceId = instanceId end
        ns.Collect("instances", instanceId, name)
    end
    ctx.chatLockdown = Plain(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
    if Plain(IsInRaid) then
        ctx.group = "raid"
    elseif Plain(IsInGroup) then
        ctx.group = "party"
    end
    ctx.instanceGroup = Plain(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) or nil
    ctx.size = Plain(GetNumGroupMembers) or 0
    ctx.leader = Plain(UnitIsGroupLeader, "player") or nil
    ctx.assist = Plain(UnitIsGroupAssistant, "player") or nil
    ctx.everyoneAssist = Plain(IsEveryoneAssistant) or nil
    ctx.restricted = {}
    local active = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    for _, kind in ipairs(Checks.Restrictions()) do
        if Plain(active, kind.value) == true then ctx.restricted[#ctx.restricted + 1] = kind.name end
    end
    return ctx
end

--------------------------------------------------------------------------------
-- Light checks
--------------------------------------------------------------------------------

-- Whether each of these is there at all. Presence only: nothing is called.
Checks.PRESENCE = {
    "SendChatMessage", "C_ChatInfo.SendChatMessage", "C_ChatInfo.InChatMessagingLockdown",
    "GetSpellInfo", "C_Spell.GetSpellInfo", "UnitAura", "UnitBuff", "UnitDebuff",
    "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetAuraDataBySpellName", "C_UnitAuras.GetPlayerAuraBySpellID",
    "GetTalentTabInfo", "GetNumTalentTabs", "C_ClassTalents", "C_Traits", "GetPartyAssignment",
    "GetRaidRosterInfo", "PlaySoundFile", "SetRaidTarget", "GetRaidTargetIndex", "SetRaidTargetIconTexture",
    "IsRaidMarkerActive", "CombatLogGetCurrentEventInfo", "C_CombatLog", "C_DeathRecap.GetRecapEvents",
    "C_PartyInfo.DoCountdown", "DoReadyCheck", "C_Secrets.ShouldSpellAuraBeSecret", "C_Secrets.GetSpellAuraSecrecy",
    "C_Item.GetWeaponEnchantInfo", "GetWeaponEnchantInfo", "UnitDetailedThreatSituation",
}

-- How this client spells the slash commands a marking macro needs.
Checks.SLASH = { "SLASH_TARGET_MARKER1", "SLASH_TARGET_MARKER2", "SLASH_TARGET_EXACT1", "SLASH_CLICK1",
    "SLASH_CLEAR_WORLD_MARKER1" }

local function CheckPresence(run)
    for _, name in ipairs(Checks.SLASH) do
        local word = _G[name]
        Note(run, "slash." .. name, type(word) == "string" and "ok" or "absent", tostring(word))
    end
    for _, row in ipairs(LibStub("LibICEnv-1.0").Probe(Checks.PRESENCE)) do
        Note(run, "has." .. row.path, row.present and "ok" or "absent", row.kind)
    end
end

local function CheckRestrictions(run)
    local ra = C_RestrictedActions or {}
    for _, kind in ipairs(Checks.Restrictions()) do
        Add(run, "restrict." .. kind.name .. ".active", ra.IsAddOnRestrictionActive, kind.value)
        Add(run, "restrict." .. kind.name .. ".state", ra.GetAddOnRestrictionState, kind.value)
    end
    local secrets = C_Secrets or {}
    for _, name in ipairs({ "ShouldAurasBeSecret", "ShouldCooldownsBeSecret", "ShouldUnitThreatValuesBeSecret" }) do
        Add(run, "secrets." .. name, secrets[name])
    end
    Add(run, "chat.C_ChatInfo.InChatMessagingLockdown", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
    Add(run, "combat.InCombatLockdown", InCombatLockdown)
    -- The group, as rows: the run's header cannot tell a false from a secret.
    Add(run, "group.IsInRaid", IsInRaid)
    Add(run, "group.IsInGroup", IsInGroup)
    Add(run, "group.GetNumGroupMembers", GetNumGroupMembers)
    Add(run, "group.UnitIsGroupLeader", UnitIsGroupLeader, "player")
    Add(run, "group.UnitIsGroupAssistant", UnitIsGroupAssistant, "player")
    Add(run, "group.IsEveryoneAssistant", IsEveryoneAssistant)
    Add(run, "encounter.C_InstanceEncounter.IsEncounterInProgress",
        C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress)
    Add(run, "encounter.IsEncounterInProgress", IsEncounterInProgress)
    Add(run, "readycheck.GetReadyCheckStatus", GetReadyCheckStatus, "player")
end

-- What MarkedForDeath reads about a mob to choose its mark and to see it die.
local UNIT_READS = {
    { "UnitExists", function(u) return UnitExists(u) end },
    { "UnitGUID", function(u) return UnitGUID(u) end },
    { "UnitName", function(u) return UnitName(u) end },
    { "UnitHealth", function(u) return UnitHealth(u) end },
    { "UnitHealthMax", function(u) return UnitHealthMax(u) end },
    { "UnitIsDead", function(u) return UnitIsDead(u) end },
    { "UnitClassification", function(u) return UnitClassification(u) end },
    { "UnitCreatureType", function(u) return UnitCreatureType(u) end },
    { "UnitCreatureFamily", function(u) return UnitCreatureFamily(u) end },
    { "UnitLevel", function(u) return UnitLevel(u) end },
    { "UnitCanAttack", function(u) return UnitCanAttack("player", u) end },
    { "UnitIsEnemy", function(u) return UnitIsEnemy("player", u) end },
    { "UnitAffectingCombat", function(u) return UnitAffectingCombat(u) end },
    { "UnitIsTapDenied", function(u) return UnitIsTapDenied(u) end },
    { "UnitIsUnit.target", function(u) return UnitIsUnit(u, "target") end },
    { "UnitThreatSituation", function(u) return UnitThreatSituation("player", u) end },
    { "C_Secrets.ShouldUnitIdentityBeSecret", function(u) return C_Secrets.ShouldUnitIdentityBeSecret(u) end },
}

-- What it reads about a group member: who they are, their role, whether they are alive.
local MEMBER_READS = {
    { "UnitGUID", function(u) return UnitGUID(u) end },
    { "UnitName", function(u) return UnitName(u) end },
    { "UnitClass", function(u) return UnitClass(u) end },
    { "UnitGroupRolesAssigned", function(u) return UnitGroupRolesAssigned(u) end },
    { "GetPartyAssignment.MAINTANK", function(u) return GetPartyAssignment("MAINTANK", u) end },
    { "UnitHealth", function(u) return UnitHealth(u) end },
    { "UnitIsDeadOrGhost", function(u) return UnitIsDeadOrGhost(u) end },
    { "UnitIsConnected", function(u) return UnitIsConnected(u) end },
    { "UnitIsVisible", function(u) return UnitIsVisible(u) end },
    { "UnitAffectingCombat", function(u) return UnitAffectingCombat(u) end },
    { "CanInspect", function(u) return CanInspect(u) end },
}

-- The first aura of a kind on a unit, and its fields one by one: crowd control on a mob
-- is a harmful aura, a buff check reads helpful ones.
local AURA_FIELDS = { "spellId", "name", "sourceUnit", "expirationTime", "duration", "applications",
    "auraInstanceID", "isFromPlayerOrPlayerPet", "dispelName" }

local function CheckAuras(run, unit, label, filter)
    local base = "aura." .. label .. "." .. filter:lower()
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local call = ns.Call(get, unit, 1, filter)
    ns.AddRow(run, base .. ".GetAuraDataByIndex", call)
    local aura = call.ok and call.values[1]
    if type(aura) ~= "table" or ns.IsSecretTable(aura) then return end
    for _, field in ipairs(AURA_FIELDS) do
        Add(run, base .. "." .. field, function() return aura[field] end)
    end
end

-- Buffs a raid check looks for by name, as the Forever raid frames do it.
Checks.BUFF_NAMES = { "Power Word: Fortitude", "Arcane Intellect", "Mark of the Wild", "Blessing of Kings",
    "Blessing of Might", "Well Fed" }

-- Spell ids whose aura secrecy decides the raid check and the crowd control calls: the
-- top rank and the first rank of each raid buff, Freezing Trap's effect, Well Fed.
Checks.SPELL_IDS = {
    { "Fortitude", 1243 }, { "Fortitude", 10938 }, { "ArcaneIntellect", 1459 }, { "ArcaneIntellect", 10157 },
    { "MarkOfTheWild", 1126 }, { "MarkOfTheWild", 9885 }, { "BlessingOfKings", 20217 },
    { "BlessingOfMight", 19740 }, { "BlessingOfMight", 25291 }, { "FreezingTrap", 3355 },
    { "FreezingTrap", 14309 }, { "WellFed", 19705 }, { "WellFed", 24799 },
}

local function CheckBuffsByName(run, unit, label)
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    for _, name in ipairs(Checks.BUFF_NAMES) do
        Add(run, "aurabyname." .. label .. "." .. name:gsub("[^%a]", ""), byName, unit, name, "HELPFUL")
    end
end

local function CheckSpellSecrecy(run)
    local secrets = C_Secrets or {}
    for _, spell in ipairs(Checks.SPELL_IDS) do
        local id = "spellsecret." .. spell[1] .. "." .. spell[2]
        Add(run, id .. ".ShouldSpellAuraBeSecret", secrets.ShouldSpellAuraBeSecret, spell[2])
        Add(run, id .. ".GetSpellAuraSecrecy", secrets.GetSpellAuraSecrecy, spell[2])
    end
    Add(run, "spellsecret.FreezingTrap.player.GetPlayerAuraBySpellID",
        C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, 3355)
end

-- Every aura id and name on a unit that reads plainly, into the capture table.
local function CaptureAuras(unit, filter)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local call = ns.Call(get, unit, i, filter)
        local aura = call.ok and call.values[1]
        if type(aura) ~= "table" or ns.IsSecretTable(aura) then return end
        local id, name
        pcall(function() id, name = aura.spellId, aura.name end)
        ns.Collect("auras", id, name)
    end
end

local iconHolder
-- A hidden texture to draw raid icons on, made the first time it is needed.
function Checks.IconTexture()
    if not iconHolder then
        iconHolder = CreateFrame("Frame", nil, UIParent)
        iconHolder:Hide()
        iconHolder.icon = iconHolder:CreateTexture(nil, "ARTWORK")
    end
    return iconHolder.icon
end

-- Reads the mark a unit carries, and draws it. Setting one from Lua is no longer tried:
-- SetRaidTarget is forbidden to addons here (client-reference.md), and each refusal opens
-- the blocked-action dialog.
local function SetMark(run, unit, label)
    local icon = Checks.ICONS[label]
    if not icon then return end
    local before = ns.Call(GetRaidTargetIndex, unit)
    ns.AddRow(run, "mark." .. label .. ".GetRaidTargetIndex", before)
    -- Whether an icon texture can be drawn from what came back, secret or not: the
    -- assignment panel draws the icon a mob carries.
    -- A nil (no mark) is left out: the client's own code rejects it.
    local index = before.ok and before.values[1]
    if before.ok and (ns.IsSecret(index) or type(index) == "number") then
        Add(run, "mark." .. label .. ".SetRaidTargetIconTexture", SetRaidTargetIconTexture, Checks.IconTexture(),
            before.values[1])
    end
end

local function CheckUnits(run)
    local hostile = Checks.HostileUnits()
    Note(run, "units.hostileSeen", "ok", tostring(#hostile))
    for _, entry in ipairs(hostile) do
        local label = entry.label == "plate2" and "plate" or entry.label
        for _, read in ipairs(UNIT_READS) do
            Add(run, "unit." .. label .. "." .. read[1], read[2], entry.unit)
        end
        CheckAuras(run, entry.unit, label, "HARMFUL")
        CaptureAuras(entry.unit, "HARMFUL")
        local guid, name = Plain(UnitGUID, entry.unit), Plain(UnitName, entry.unit)
        ns.Collect("npcs", ns.Report.NpcId(guid, ns.IsSecret), name)
        SetMark(run, entry.unit, entry.label)
    end
    SetMark(run, "player", "player")

    local members = Checks.Members()
    Note(run, "units.membersSeen", "ok", tostring(#members))
    for _, unit in ipairs(members) do
        for _, read in ipairs(MEMBER_READS) do
            Add(run, "member." .. read[1], read[2], unit)
        end
        CheckAuras(run, unit, "member", "HELPFUL")
        CheckBuffsByName(run, unit, "member")
    end
    CheckAuras(run, "player", "player", "HELPFUL")
    CheckBuffsByName(run, "player", "player")
    CaptureAuras("player", "HELPFUL")
    CheckSpellSecrecy(run)
end

local function CheckMeter(run)
    local dm = C_DamageMeter or {}
    Add(run, "meter.IsDamageMeterAvailable", dm.IsDamageMeterAvailable)
    Add(run, "meter.GetAvailableCombatSessions", dm.GetAvailableCombatSessions)
    local sessionTypes = Enum and Enum.DamageMeterSessionType
    local meterTypes = Enum and Enum.DamageMeterType
    if type(sessionTypes) ~= "table" or type(meterTypes) ~= "table" then
        Note(run, "meter.enums", "absent", "no Enum.DamageMeterSessionType or Enum.DamageMeterType")
        return
    end
    for _, meter in ipairs({ "DamageDone", "Deaths" }) do
        local id = "meter.Current." .. meter
        local call = ns.Call(dm.GetCombatSessionFromType, sessionTypes.Current, meterTypes[meter])
        ns.AddRow(run, id, call)
        local session = call.ok and call.values[1]
        if type(session) == "table" then
            for _, field in ipairs(ns.Report.Shape(session, ns.IsSecret, ns.IsSecretTable, 12)) do
                Note(run, id .. "." .. field.key, field.secret and "secret" or "ok", field.text)
                -- The first entry of a list inside, which is where a source's numbers sit.
                local inner = not field.secret and session[field.key]
                if type(inner) == "table" and not ns.IsSecretTable(inner) and type(inner[1]) == "table" then
                    for _, sub in ipairs(ns.Report.Shape(inner[1], ns.IsSecret, ns.IsSecretTable, 16)) do
                        Note(run, id .. "." .. field.key .. "[1]." .. sub.key, sub.secret and "secret" or "ok", sub.text)
                    end
                end
            end
        end
    end
end

local function CheckCombatLog(run)
    -- Registering the combat log is settled (forbidden) and not asked again.
    Add(run, "cleu.CombatLogGetCurrentEventInfo.outsideEvent", CombatLogGetCurrentEventInfo)
end

--------------------------------------------------------------------------------
-- Heavy checks
--------------------------------------------------------------------------------

local function CheckChat(run)
    if not ns.db.settings.chat then
        Note(run, "chat.skipped", "none", "/mfdp chat on to include chat")
        return
    end
    local sent = {}
    local function OnChat(event, text)
        for channel, events in pairs(ECHO_EVENTS) do
            local pending = sent[channel]
            if events[event] and pending and not pending.heard then
                -- A secret line cannot be matched to ours, so the first line on the
                -- channel after the send is taken as the echo and said to be secret.
                if ns.IsSecret(text) then
                    pending.heard = true
                    Note(run, "chat." .. channel .. ".echo", "secret", event)
                elseif type(text) == "string" and text:find(pending.tag, 1, true) then
                    pending.heard = true
                    Note(run, "chat." .. channel .. ".echo", "ok", event)
                end
            end
        end
    end
    local function OnSystem(_, text)
        Note(run, "chat.system", ns.IsSecret(text) and "secret" or "ok",
            (ns.Report.Describe(text, ns.IsSecret, ns.IsSecretTable)))
    end
    for _, events in pairs(ECHO_EVENTS) do
        for event in pairs(events) do ns.Listen.On(event, OnChat) end
    end
    ns.Listen.On("CHAT_MSG_SYSTEM", OnSystem)
    ns.Listen.Ensure(run, ECHO_WAIT + 1)

    -- The global where there is one, the namespaced call otherwise; which was used is a row.
    local send = type(SendChatMessage) == "function" and SendChatMessage
        or (C_ChatInfo and C_ChatInfo.SendChatMessage)
    Note(run, "chat.sender", send and "ok" or "absent",
        send == SendChatMessage and "SendChatMessage" or "C_ChatInfo.SendChatMessage")
    for _, channel in ipairs(Checks.CHANNELS) do
        local tag = string.format("MFDProbe %d.%s", run.id, channel)
        sent[channel] = { tag = tag }
        Add(run, "chat." .. channel .. ".send", send,
            string.format("%s: chat test (%s)", tag, ns.InCombat() and "in combat" or "out of combat"), channel)
    end
    C_Timer.After(ECHO_WAIT, function()
        for _, events in pairs(ECHO_EVENTS) do
            for event in pairs(events) do ns.Listen.Off(event, OnChat) end
        end
        ns.Listen.Off("CHAT_MSG_SYSTEM", OnSystem)
        for _, channel in ipairs(Checks.CHANNELS) do
            if not sent[channel].heard then
                Note(run, "chat." .. channel .. ".echo", "none", string.format("nothing back in %ds", ECHO_WAIT))
            end
        end
    end)
end

local function CheckAddonMessages(run)
    local ci = C_ChatInfo or {}
    Add(run, "addonmsg.RegisterAddonMessagePrefix", ci.RegisterAddonMessagePrefix, PREFIX)
    local heard = {}
    local function OnAddon(_, prefix, text, channel)
        if ns.IsSecret(prefix) then
            Note(run, "addonmsg.echo.secret", "secret", "prefix is secret")
            return
        end
        if prefix ~= PREFIX or ns.IsSecret(channel) or heard[channel] then return end
        heard[channel] = true
        Note(run, "addonmsg." .. tostring(channel) .. ".echo", ns.IsSecret(text) and "secret" or "ok",
            (ns.Report.Describe(text, ns.IsSecret, ns.IsSecretTable)))
    end
    ns.Listen.On("CHAT_MSG_ADDON", OnAddon)
    ns.Listen.Ensure(run, ECHO_WAIT + 1)
    for _, channel in ipairs(Checks.ADDON_CHANNELS) do
        Add(run, "addonmsg." .. channel .. ".send", ci.SendAddonMessage, PREFIX, "probe " .. run.id, channel)
    end
    C_Timer.After(ECHO_WAIT, function()
        ns.Listen.Off("CHAT_MSG_ADDON", OnAddon)
        for _, channel in ipairs(Checks.ADDON_CHANNELS) do
            if not heard[channel] then
                Note(run, "addonmsg." .. channel .. ".echo", "none", string.format("nothing back in %ds", ECHO_WAIT))
            end
        end
    end)
end

local inspecting = false

local function CheckInspect(run)
    Add(run, "talents.player.GetTalentTabInfo.1", GetTalentTabInfo, 1)
    Add(run, "talents.player.GetNumTalentTabs", GetNumTalentTabs)
    if inspecting then
        Note(run, "inspect.NotifyInspect", "none", "an inspect from an earlier run is still waiting")
        return
    end
    local target
    for _, unit in ipairs(Checks.Members()) do
        if Plain(UnitIsVisible, unit) and Plain(CanInspect, unit) then
            target = unit
            break
        end
    end
    if not target then
        Note(run, "inspect.NotifyInspect", "none", "no group member in range to inspect")
        return
    end
    local done = false
    local function OnReady()
        if done then return end
        done = true
        inspecting = false
        Note(run, "inspect.INSPECT_READY", "ok", "answered")
        Add(run, "inspect.GetNumTalentTabs", GetNumTalentTabs, true)
        for tab = 1, 3 do
            Add(run, "inspect.GetTalentTabInfo." .. tab, GetTalentTabInfo, tab, true)
        end
        Add(run, "inspect.GetInspectSpecialization", GetInspectSpecialization, target)
        pcall(ClearInspectPlayer)
    end
    ns.Listen.On("INSPECT_READY", OnReady)
    ns.Listen.Ensure(run, INSPECT_WAIT + 1)
    inspecting = true
    local call = ns.Call(NotifyInspect, target)
    ns.AddRow(run, "inspect.NotifyInspect", call)
    C_Timer.After(INSPECT_WAIT, function()
        ns.Listen.Off("INSPECT_READY", OnReady)
        if not done then
            done = true
            inspecting = false
            Note(run, "inspect.INSPECT_READY", "none", string.format("no answer in %ds", INSPECT_WAIT))
            pcall(ClearInspectPlayer)
        end
    end)
end

local function CheckLogging(run)
    local read = ns.Call(LoggingCombat)
    ns.AddRow(run, "log.LoggingCombat.read", read)
    if not read.ok or read.values[1] == true or ns.IsSecret(read.values[1]) then return end
    -- It was off: switch it on, read it, and put it back off.
    Add(run, "log.LoggingCombat.on", LoggingCombat, true)
    Add(run, "log.LoggingCombat.after", LoggingCombat)
    pcall(LoggingCombat, false)
end

-- The LibDurability prefix: an "R" asks everyone who runs it (inside BigWigs, DBM and MRT
-- on other clients) to answer with their durability.
local DURABILITY_PREFIX = "LibDRBLT"

-- P16: a raid warning drawn on this screen only, which sends nothing. Whether the line
-- shows during an encounter or a chat lockdown is for the player's eyes; the rows say
-- whether the call ran and whether the frame was showing straight after.
local function CheckNotice(run)
    local frameOk = type(RaidWarningFrame) == "table"
    Note(run, "notice.RaidWarningFrame", frameOk and "ok" or "absent", frameOk and "present" or "missing")
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or nil
    local text = string.format("MFDProbe notice %d (%s)", run.id, ns.InCombat() and "in combat" or "out of combat")
    Add(run, "notice.RaidNotice_AddMessage", RaidNotice_AddMessage, RaidWarningFrame, text, info)
    if frameOk then Add(run, "notice.RaidWarningFrame.IsShown", RaidWarningFrame.IsShown, RaidWarningFrame) end
end

local function CheckDurability(run)
    Add(run, "durability.head", GetInventoryItemDurability, 1)
    Add(run, "durability.chest", GetInventoryItemDurability, 5)

    local ci = C_ChatInfo or {}
    local channel = Plain(IsInRaid) and "RAID" or (Plain(IsInGroup) and "PARTY")
    if not channel then
        Note(run, "durability.LibDRBLT.request", "none", "not in a group")
        return
    end
    Add(run, "durability.LibDRBLT.register", ci.RegisterAddonMessagePrefix, DURABILITY_PREFIX)
    local answers = 0
    local function OnAddon(_, prefix, text)
        if ns.IsSecret(prefix) or prefix ~= DURABILITY_PREFIX then return end
        if ns.IsSecret(text) or text ~= "R" then answers = answers + 1 end
    end
    ns.Listen.On("CHAT_MSG_ADDON", OnAddon)
    ns.Listen.Ensure(run, ECHO_WAIT + 1)
    Add(run, "durability.LibDRBLT.request", ci.SendAddonMessage, DURABILITY_PREFIX, "R", channel)
    C_Timer.After(ECHO_WAIT, function()
        ns.Listen.Off("CHAT_MSG_ADDON", OnAddon)
        Note(run, "durability.LibDRBLT.answers", answers > 0 and "ok" or "none",
            string.format("%d in %ds", answers, ECHO_WAIT))
    end)
end

local function CheckSecureButton(run)
    local made = ns.Call(CreateFrame, "Button", nil, UIParent, "SecureActionButtonTemplate")
    ns.AddRow(run, "secure.CreateFrame", made)
    local button = made.ok and made.values[1]
    if type(button) ~= "table" then return end
    pcall(button.Hide, button)
    Add(run, "secure.SetAttribute", button.SetAttribute, button, "type", "macro")
    Add(run, "secure.RegisterForClicks", button.RegisterForClicks, button, "AnyUp", "AnyDown")
end

--------------------------------------------------------------------------------
-- A run
--------------------------------------------------------------------------------

-- Starts a run with no checks in it, for a window that only listens.
function Checks.NewRun(phase, trigger)
    local db = ns.db
    local run = { id = db.nextId, phase = phase, trigger = trigger, at = time(), rows = {}, events = {} }
    db.nextId = db.nextId + 1
    run.ctx = Checks.Context()
    db.runs[#db.runs + 1] = run
    db.runs = ns.Report.Trim(db.runs, ns.KEEP_RUNS)
    ns.SetCurrentRun(run)
    return run
end

local LIGHT = { CheckRestrictions, CheckUnits, CheckMeter, CheckCombatLog }
local HEAVY = { CheckPresence, CheckChat, CheckAddonMessages, CheckInspect, CheckLogging, CheckNotice, CheckDurability,
    CheckSecureButton }

-- One pass. Each check is fenced off, so one that throws loses its own rows and nothing
-- else.
function Checks.Run(phase, trigger, heavy)
    local run = Checks.NewRun(phase, trigger)
    -- A window for the client's own refusals, which arrive as events.
    ns.Listen.Ensure(run, 2)
    local list = { unpack(LIGHT) }
    if heavy then
        for _, check in ipairs(HEAVY) do list[#list + 1] = check end
    end
    for _, check in ipairs(list) do
        local ok, err = pcall(check, run)
        if not ok then Note(run, "probe.fault", "error", tostring(err)) end
    end
    return run
end
