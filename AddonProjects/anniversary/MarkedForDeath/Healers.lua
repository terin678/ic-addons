-- Healer death announcements.
--
-- Who counts as a healer comes from their spec, which this addon already
-- learns by inspection for the raid check grid, plus a list you type. There is
-- no healer role on this client's raid roster the way there is a main tank
-- flag, so spec is the honest source: a shadow priest is not a healer and no
-- amount of reading their class will say so.
local MFD = _G.MarkedForDeath or {}

MFD.Healers = MFD.Healers or {}
local Healers = MFD.Healers

-- Talent tab names that mean somebody heals. Unambiguous on TBC: Holy is
-- priest or paladin and both heal, Restoration is druid or shaman and both
-- heal, Discipline is priest only. No healing spec shares a name with a spec
-- that does not heal, so the class is not needed to read this.
Healers.HEALING_SPECS = {
    ["Holy"] = true,
    ["Discipline"] = true,
    ["Restoration"] = true,
}

-- Takes a player name, { [name] = spec } for the specs known, and the typed
-- list. Returns whether that player counts. Pure.
function Healers.IsHealer(name, specs, manual)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local needle = string.lower(name)
    for _, typed in ipairs(manual or {}) do
        if string.lower(typed) == needle then
            return true
        end
    end

    return Healers.HEALING_SPECS[(specs or {})[name]] == true
end

-- Everyone currently recognised as a healer, sorted. Pure. The settings panel
-- shows this, because "will this work tonight" is a question worth being able
-- to answer before the pull rather than after somebody dies unremarked.
function Healers.Known(specs, manual)
    local seen, names = {}, {}

    for name, spec in pairs(specs or {}) do
        if Healers.HEALING_SPECS[spec] and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    for _, typed in ipairs(manual or {}) do
        if not seen[typed] then
            seen[typed] = true
            names[#names + 1] = typed
        end
    end

    table.sort(names)
    return names
end

-- The line posted to the raid. Pure. Deliberately the same wording as a tank
-- death: the raid reads the name, not the grammar.
function Healers.FormatDeath(name)
    return name .. " has died"
end

-- ---------------------------------------------------------------- client --

local announced = {}

-- Specs the addon knows, from both sources it has: what other people running
-- this addon report about themselves, and what inspection learned. A client's
-- own report wins, being the only one that cannot be stale or out of range.
function Healers.KnownSpecs()
    local specs = {}
    local RC = MFD.RaidCheck

    for name, entry in pairs(RC.inspected or {}) do
        if entry.spec then
            specs[name] = entry.spec
        end
    end

    for name, report in pairs(RC.reports or {}) do
        if report.state and report.state.spec then
            specs[name] = report.state.spec
        end
    end

    return specs
end

function Healers.ManualList()
    return MFD.Tanks.ParseList(MFD.db.settings.deaths.healerNames)
end

-- Announces a healer's death once, from one client only, on the bosses you
-- picked. Same authority gate as marking, for the same reason: without it
-- twenty five people post the same line.
function Healers:OnDeath(name, now)
    if not MFD.IsEnabled() then
        return
    end
    if not (MFD.Comms and MFD.Comms:IsAuthority()) then
        return
    end
    if not MFD.Encounters.ShouldAnnounce(MFD.Encounters.ConfigFor("HEALER"), MFD.Encounters.active) then
        return
    end
    if not Healers.IsHealer(name, Healers.KnownSpecs(), Healers.ManualList()) then
        return
    end
    if not MFD.Tanks.ShouldAnnounce(name, announced, now, MFD.Tanks.REPEAT_SECONDS) then
        return
    end

    local canWarn = UnitIsGroupLeader("player")
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    local channel = (IsInRaid and IsInRaid() and canWarn and "RAID_WARNING")
        or (IsInRaid and IsInRaid() and "RAID")
        or (IsInGroup and IsInGroup() and "PARTY")
        or nil

    if not channel then
        return
    end

    pcall(SendChatMessage, Healers.FormatDeath(name), channel)
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            wipe(announced)
            return
        end

        local _, subEvent, _, _, _, _, _, _, destName = CombatLogGetCurrentEventInfo()
        if subEvent == "UNIT_DIED" and destName then
            local ok, err = pcall(Healers.OnDeath, Healers, destName, GetTime())
            if not ok then
                MFD.Error("healer death alert failed: " .. tostring(err))
            end
        end
    end)
end)

_G.MarkedForDeath = MFD
