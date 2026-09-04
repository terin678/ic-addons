-- Main tank death announcements.
--
-- Who counts as a tank comes from two places: the raid's own main tank
-- assignment, and a list you type. Either is enough. With neither, nothing is
-- announced, because a raid where the addon guessed at tanks would spam.
local MFD = _G.MarkedForDeath or {}

MFD.Tanks = MFD.Tanks or {}
local Tanks = MFD.Tanks

-- Seconds before the same tank's death can be announced again. Long enough to
-- swallow duplicate combat log lines, short enough that a wipe-rez-wipe still
-- reports both.
Tanks.REPEAT_SECONDS = 10

-- Takes a typed list. Returns an array of names, split on commas and
-- newlines, trimmed, with empties dropped. Pure.
function Tanks.ParseList(text)
    local names = {}
    if type(text) ~= "string" then
        return names
    end

    for chunk in string.gmatch(text, "[^,\n]+") do
        local name = string.match(chunk, "^%s*(.-)%s*$")
        if name ~= "" then
            names[#names + 1] = name
        end
    end

    return names
end

-- Takes a player name, the set of names the raid has assigned as main tanks,
-- and the manually typed list. Returns whether that player counts. Pure.
function Tanks.IsTank(name, assigned, manual)
    if type(name) ~= "string" or name == "" then
        return false
    end

    if assigned[name] then
        return true
    end

    local needle = string.lower(name)
    for _, typed in ipairs(manual or {}) do
        if string.lower(typed) == needle then
            return true
        end
    end

    return false
end

-- Records a death and says whether it is worth announcing. Mutates announced.
-- Pure apart from that. A death within REPEAT_SECONDS of the last one for the
-- same tank is a duplicate combat log line, not a second death.
function Tanks.ShouldAnnounce(name, announced, now, repeatSeconds)
    local last = announced[name]
    if last and (now - last) < repeatSeconds then
        return false
    end

    announced[name] = now
    return true
end

-- The line posted to the raid. Pure.
function Tanks.FormatDeath(name)
    return name .. " has died"
end

-- ---------------------------------------------------------------- client --

local GetPartyAssignment = GetPartyAssignment
local UnitName = UnitName
local IsInRaid = IsInRaid

-- Shared with the healer announcer, deliberately. Somebody can satisfy both
-- definitions at once, most easily a healer still flagged Main Tank from a
-- previous night, and two announcers with private tables would each post the
-- same line at the raid. Whichever gets there first claims the name.
Tanks.announced = {}
local announced = Tanks.announced

-- Returns { [name] = true } for everyone the raid has flagged as a main tank.
function Tanks.AssignedTanks()
    local assigned = {}
    if not (IsInRaid and IsInRaid() and GetPartyAssignment) then
        return assigned
    end

    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local ok, isMainTank = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and isMainTank then
            local name = UnitName(unit)
            if name then
                assigned[name] = true
            end
        end
    end

    return assigned
end

-- Announces a main tank's death once, from one client only.
--
-- Gated on being the marking authority for the same reason marking is: without
-- it, twenty five people would each post the same line. Uses a raid warning
-- when the announcer can, because a tank dying is the one thing everybody
-- needs to see immediately, and plain raid chat otherwise.
function Tanks:OnDeath(name, now)
    if not MFD.IsEnabled() then
        return
    end
    if not (MFD.Comms and MFD.Comms:IsAuthority()) then
        return
    end
    -- Tanks have their own trash setting, own boss list and own override, and
    -- read none of the healer ones.
    if not MFD.Encounters.ShouldAnnounce(MFD.Encounters.Settings("tank"), MFD.Encounters.active) then
        return
    end
    if not Tanks.IsTank(name, Tanks.AssignedTanks(), Tanks.ParseList(MFD.db.settings.deaths.tank.names)) then
        return
    end
    if not Tanks.ShouldAnnounce(name, announced, now, Tanks.REPEAT_SECONDS) then
        return
    end

    local channel = MFD.Chatter.GroupChannel(true)
    if not channel then
        return
    end

    -- Forced: rare, already guarded per name, and the one line nobody can
    -- afford to lose to an announcement about a trash pack.
    MFD.Log.Add(MFD.Log.KINDS.DEATH, "tank death called: " .. name)
    MFD.Chatter.Say(Tanks.FormatDeath(name), channel, true)
end

MFD.RegisterInit(function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            -- Between pulls the suppression window is meaningless, and keeping
            -- it would swallow the first death of the next attempt.
            wipe(announced)
            return
        end

        local _, subEvent, _, _, _, _, _, _, destName = CombatLogGetCurrentEventInfo()
        if subEvent == "UNIT_DIED" and destName then
            local ok, err = pcall(Tanks.OnDeath, Tanks, destName, GetTime())
            if not ok then
                MFD.Error("tank death alert failed: " .. tostring(err))
            end
        end
    end)
end)

_G.MarkedForDeath = MFD
