-- Healer death announcements.
--
-- Who counts as a healer comes from three places: the healer role icon on the
-- raid roster, their spec, which this addon already learns by inspection for
-- the raid check grid, and a list you type. The role icon is live on this
-- client, the same one tank warnings read, and it answers for healers the
-- inspect pump has not reached yet. Spec still counts on its own because a raid
-- rarely sets every role, and it is spec, not class, that says a shadow priest
-- is not a healer.
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

-- Whether a raid role, as UnitGroupRolesAssigned reports it, is the healer
-- icon. Pure. nil and "NONE" are a role nobody chose, not a claim either way.
function Healers.CountsAsHealer(role)
    return role == "HEALER"
end

-- Takes a player name, { [name] = spec } for the specs known, the typed list,
-- and { [name] = true } for everyone wearing the healer role icon. Returns
-- whether that player counts. Pure.
function Healers.IsHealer(name, specs, manual, roles)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local needle = string.lower(name)
    for _, typed in ipairs(manual or {}) do
        if string.lower(typed) == needle then
            return true
        end
    end

    if (roles or {})[name] then
        return true
    end

    return Healers.HEALING_SPECS[(specs or {})[name]] == true
end

-- Everyone currently recognised as a healer, sorted. Pure. The settings panel
-- shows this, because "will this work tonight" is a question worth being able
-- to answer before the pull rather than after somebody dies unremarked.
function Healers.Known(specs, manual, roles)
    local seen, names = {}, {}

    for name, spec in pairs(specs or {}) do
        if Healers.HEALING_SPECS[spec] and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    for name in pairs(roles or {}) do
        if not seen[name] then
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

-- The tank announcer's table, not a second one. See the comment on it: a
-- healer left flagged Main Tank matches both, and one line is enough.
Healers.announced = MFD.Tanks.announced
local announced = Healers.announced

local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitName = UnitName
local IsInRaid = IsInRaid

-- Returns { [name] = true } for everyone in the raid wearing the healer role
-- icon. Each unit is read inside pcall, as the tank reader does, so a client
-- without the API reads nobody rather than erroring.
function Healers.RoleHealers()
    local healers = {}
    if not (UnitGroupRolesAssigned and IsInRaid and IsInRaid()) then
        return healers
    end

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        if ok and Healers.CountsAsHealer(role) then
            local name = UnitName(unit)
            if name then
                healers[name] = true
            end
        end
    end

    return healers
end

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
    return MFD.Tanks.ParseList(MFD.db.settings.deaths.healer.names)
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
    if not MFD.Encounters.ShouldAnnounce(MFD.Encounters.Settings("healer"), MFD.Encounters.active) then
        return
    end
    if not Healers.IsHealer(name, Healers.KnownSpecs(), Healers.ManualList(), Healers.RoleHealers()) then
        return
    end
    if not MFD.Tanks.ShouldAnnounce(name, announced, now, MFD.Tanks.REPEAT_SECONDS) then
        return
    end

    local channel = MFD.Chatter.GroupChannel(true)
    if not channel then
        return
    end

    -- One warning per person per fight. Asked last of all, after every other
    -- gate has said yes, so a death that was going to be filtered out anyway
    -- never spends this person's call for the fight.
    if not MFD.Encounters.TakeDeathCall(MFD.Encounters.deaths, name) then
        MFD.Log.Add(MFD.Log.KINDS.HELD,
            "healer death not called: " .. name .. " was already called this fight")
        return
    end

    -- Forced: rare, already guarded per name, and the one line nobody can
    -- afford to lose to an announcement about a trash pack.
    MFD.Log.Add(MFD.Log.KINDS.DEATH, "healer death called: " .. name)
    MFD.Chatter.Say(Healers.FormatDeath(name), channel, nil, true)
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
