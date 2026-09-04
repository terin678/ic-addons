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

-- The same three for a button face, where the label is prefixed by which kind
-- it governs and the whole thing has to fit in one. "Tank: On everywhere" did
-- not, and spilled across the button beside it.
Encounters.OVERRIDE_SHORT = {
    AUTO = "per boss",
    ON = "all",
    OFF = "off",
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

-- Should a death of this kind be announced right now?
--
-- Takes one kind's block, { isEnabled, onTrash, override, bosses }, and the
-- encounter name or nil. Pure.
--
-- Bosses are picked one at a time because they are individually worth or not
-- worth a callout. Trash is one yes or no, because nobody wants to tick five
-- hundred mobs and no raid leader thinks about trash that way: either deaths
-- there are worth hearing about or they are not.
--
-- The two kinds each have their own block and never read each other's, so tank
-- calls can run everywhere while healer calls sit on three bosses in Black
-- Temple.
function Encounters.ShouldAnnounce(config, encounterName)
    if not config or not config.isEnabled then
        return false
    end

    if config.override == Encounters.OVERRIDE_OFF then
        return false
    end

    if config.override == Encounters.OVERRIDE_ON then
        return true
    end

    if encounterName then
        return (config.bosses or {})[encounterName] == true
    end

    return config.onTrash == true
end

-- The two kinds, in the order every surface lists them. tank first because it
-- is the one that has always been on.
Encounters.KINDS = { "tank", "healer" }

Encounters.KIND_LABELS = { tank = "Tank", healer = "Healer" }

-- One kind's block out of the deaths settings, or nil if it is not there.
-- Pure, so the gate can be exercised without a saved variable table.
function Encounters.ConfigFor(deaths, kind)
    return deaths and deaths[kind] or nil
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

-- Whether knowing the fight changes any answer. It does for any kind that is
-- switched on and whose override is following the ticks, since the ticks are
-- read per boss. With none, the whole scan is work whose result is discarded,
-- five times a second, in a raid.
function Encounters.IsNeeded()
    local deaths = MFD.db and MFD.db.settings.deaths
    if not deaths then
        return false
    end

    for _, kind in ipairs(Encounters.KINDS) do
        local config = Encounters.ConfigFor(deaths, kind)
        if config and config.isEnabled and config.override == Encounters.OVERRIDE_AUTO then
            return true
        end
    end

    return false
end

-- How many rows each column needs so that a list of groups, none of which may
-- be split, packs into at most maxColumns columns. Pure.
--
-- The obvious answer, the total divided by the columns, is wrong: a group that
-- does not fit in what is left of a column starts a new one, so the packing
-- wastes the tail of every column and can need one more than the average
-- suggests. Boss lists are small, so this walks up from that average until the
-- packing actually fits rather than trying to be clever about it.
function Encounters.PackColumns(sizes, maxColumns)
    if maxColumns < 1 then
        maxColumns = 1
    end

    -- The largest group is a floor on the column height all by itself: a group
    -- is never split, so a column has to be at least as tall as the tallest one.
    local total, largest = 0, 0
    for _, size in ipairs(sizes) do
        total = total + size
        if size > largest then
            largest = size
        end
    end

    local rows = math.max(largest, math.ceil(total / maxColumns))

    while rows <= total do
        local columns, used = 1, 0
        for _, size in ipairs(sizes) do
            if used > 0 and used + size > rows then
                columns = columns + 1
                used = 0
            end
            used = used + size
        end

        if columns <= maxColumns then
            return rows, columns
        end
        rows = rows + 1
    end

    return total, 1
end

-- Ticks every boss for tanks the first time this block exists, so the shipped
-- default announces tank deaths everywhere, which is what it has always done.
--
-- Guarded by a flag rather than by "is the list empty", because an empty list
-- is also what you get after deliberately unticking the last boss, and
-- re-ticking all forty three on the next login would be maddening. Pure apart
-- from writing to the block it is given.
function Encounters.SeedDefaults(deaths, bosses)
    if not deaths or deaths.isSeeded then
        return false
    end

    deaths.isSeeded = true
    for _, boss in ipairs(bosses or {}) do
        deaths.tank.bosses[boss.name] = true
    end

    return true
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

-- One kind's live block from saved variables.
function Encounters.Settings(kind)
    return Encounters.ConfigFor(MFD.db.settings.deaths, kind)
end

_G.MarkedForDeath = MFD
