-- Which boss the raid is fighting, and whether death announcements apply to it.
--
-- There is no ENCOUNTER_START on this client, so the fight is identified from
-- the mobs already on screen: the nameplate set the marker maintains anyway,
-- matched against the bundled boss table. That costs nothing extra and needs no
-- combat log parsing.
local MFD = _G.MarkedForDeath or {}

MFD.Encounters = MFD.Encounters or {}
local Encounters = MFD.Encounters

-- The three states of the mid-raid override. AUTO follows the per-boss list;
-- the other two ignore it in both directions, which is the whole point of
-- having them.
Encounters.OVERRIDE_AUTO = "AUTO"
Encounters.OVERRIDE_ON = "ON"
Encounters.OVERRIDE_OFF = "OFF"

Encounters.OVERRIDE_LABELS = {
    AUTO = "Per boss",
    ON = "On everywhere",
    OFF = "Off everywhere",
}

-- Builds { [npcID] = encounterName } from the boss table. Pure.
function Encounters.IndexByNpcID(bosses)
    local index = {}

    for _, boss in ipairs(bosses or {}) do
        for _, id in ipairs(boss.ids) do
            index[id] = boss.name
        end
    end

    return index
end

-- Groups the boss table by instance, preserving the order it is written in.
-- Returns an array of { instance, bosses = array }. Pure.
function Encounters.GroupByInstance(bosses)
    local groups, byKey = {}, {}

    for _, boss in ipairs(bosses or {}) do
        local group = byKey[boss.instance]
        if not group then
            group = { instance = boss.instance, bosses = {} }
            byKey[boss.instance] = group
            groups[#groups + 1] = group
        end
        group.bosses[#group.bosses + 1] = boss
    end

    return groups
end

-- Takes the candidate list the marker already keeps and the npcID index.
-- Returns the encounter name, or nil when nothing on screen is a boss.
--
-- A mob whose nameplate has gone is ignored: the fight you are in is the one
-- you can see. Ties are broken by name so two clients never disagree, though
-- two different bosses being up at once does not happen in practice.
function Encounters.Detect(candidates, index)
    local found

    for _, candidate in ipairs(candidates or {}) do
        local name = not candidate.isLost and index[candidate.npcID]
        if name and (not found or name < found) then
            found = name
        end
    end

    return found
end

-- Keeps the fight you are in once it has been identified.
--
-- Nameplates come and go: a raid leader healing from thirty five yards loses
-- the boss's plate constantly, and Reliquary of Souls despawns between its
-- essences. Forgetting the encounter on the first frame the plate is missing
-- would silently stop announcing halfway through a fight, which is worse than
-- not announcing at all because nobody would know it had stopped. Combat
-- ending is the only thing that clears it. Pure.
function Encounters.Resolve(detected, previous, isInCombat)
    if detected then
        return detected
    end

    if isInCombat then
        return previous
    end

    return nil
end

-- Reads a boss out of a combat log GUID. Returns the encounter name or nil.
--
-- The backstop for a boss whose nameplate this client never sees at all: it
-- swings, it casts, and either way its id is in the log. Pure.
function Encounters.FromGUID(guid, index)
    local npcID = MFD.H.SplitGUID(guid)
    if not npcID then
        return nil
    end

    return index[npcID]
end

-- Does the boss gate pass right now? Takes the override, the per-boss
-- selection and the encounter name or nil. Pure.
--
-- Trash never passes under any setting. Somebody dying on trash is not news,
-- and a raid night of it is how a feature gets turned off for good; the
-- override changes which bosses count, not whether trash does.
function Encounters.PassesBossGate(override, selected, encounterName)
    if override == Encounters.OVERRIDE_OFF then
        return false
    end

    if not encounterName then
        return false
    end

    if override == Encounters.OVERRIDE_ON then
        return true
    end

    return (selected or {})[encounterName] == true
end

-- Should a death of this kind be announced right now?
--
-- Takes { isEnabled, bossOnly, override, selected } and the encounter name or
-- nil. Pure. bossOnly is what separates the two announcers: healer deaths are
-- always boss gated because that is what they were asked for, and tank deaths
-- are not unless you say so, because they already announce everywhere and
-- quietly narrowing that would be a change nobody asked for.
function Encounters.ShouldAnnounce(config, encounterName)
    if not config.isEnabled then
        return false
    end

    if not config.bossOnly then
        return true
    end

    return Encounters.PassesBossGate(config.override, config.selected, encounterName)
end

-- Cycles the override for a one-click toggle. Pure.
function Encounters.NextOverride(current)
    if current == Encounters.OVERRIDE_AUTO then
        return Encounters.OVERRIDE_ON
    elseif current == Encounters.OVERRIDE_ON then
        return Encounters.OVERRIDE_OFF
    end
    return Encounters.OVERRIDE_AUTO
end

-- ---------------------------------------------------------------- client --

-- The encounter the raid is currently in, or nil. Read by the death
-- announcers; set from the marker's tick, which already has the candidates.
Encounters.active = nil

local index

-- Built once and kept, because the boss table never changes at runtime.
function Encounters.Index()
    index = index or Encounters.IndexByNpcID(MFD.Data.Bosses)
    return index
end

-- Whether anything actually consults the boss gate. Healer alerts always do;
-- tank alerts only when held to the boss list. With neither, the whole scan is
-- work whose result is discarded, five times a second, in a raid.
function Encounters.IsNeeded()
    local settings = MFD.db and MFD.db.settings.deaths
    if not settings then
        return false
    end

    return settings.isHealerAlertEnabled == true or settings.isTankBossOnly == true
end

-- Called from the marker tick with the candidate list it already computed.
function Encounters.Update(candidates)
    local detected = Encounters.Detect(candidates, Encounters.Index())
    local isInCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
    Encounters.active = Encounters.Resolve(detected, Encounters.active, isInCombat)
    return Encounters.active
end

-- Seconds between combat log checks while no boss is identified. The log
-- carries thousands of events a fight and parsing all of them to answer a
-- question that stops mattering the moment it is answered would be the most
-- expensive thing this addon does. A boss swings or casts several times a
-- second, so a quarter second sampling still finds it almost immediately.
Encounters.LOG_SAMPLE_SECONDS = 0.25

local lastSampleAt = 0

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Out of combat there is no fight to be in. The tick would work
            -- this out too, but only if this client happens to be marking.
            Encounters.active = nil
            return
        end

        -- Nothing to learn once the fight is known, and nothing worth learning
        -- if no setting reads it.
        if Encounters.active or not MFD.IsEnabled() or not Encounters.IsNeeded() then
            return
        end

        local now = GetTime()
        if (now - lastSampleAt) < Encounters.LOG_SAMPLE_SECONDS then
            return
        end
        lastSampleAt = now

        local _, _, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        local index = Encounters.Index()
        Encounters.active = Encounters.FromGUID(sourceGUID, index)
            or Encounters.FromGUID(destGUID, index)
    end)
end)

-- The config each announcer asks about, read from saved variables. Healers are
-- always boss gated; tanks only when asked.
function Encounters.ConfigFor(kind)
    local settings = MFD.db.settings.deaths
    return {
        isEnabled = (kind == "HEALER") and settings.isHealerAlertEnabled or settings.isTankAlertEnabled,
        bossOnly = (kind == "HEALER") and true or settings.isTankBossOnly,
        override = settings.override,
        selected = settings.bosses,
    }
end

_G.MarkedForDeath = MFD
