local addonName, ns = ...

--[[
Sense: what the client lets MarkedForDeath read about mobs and marks, and when.

Owned by lane B (marking runtime). A frame module: nothing here runs at file scope, and
every call into the client is guarded, so a missing or throwing API reads as "nothing".

    Sense.Facts(unit)       { guid, name } of a unit, each only if plain; nil if neither is
    Sense.Marked(unit)      marked, icon: true and the icon out of combat; true and nil in
                            combat (the icon is secret); false when plainly unmarked;
                            nil when the unit is not there
    Sense.Reads()           out of combat only: { { guid, name, icon } } for every marked
                            unit in reach (target, focus, mouseover, nameplates, the
                            group's targets); {} in combat
    Sense.Blind()           true: blind mode (rules by name) is the only mode built yet

The rule this file exists to keep (spec 5.8, 14): in combat GetRaidTargetIndex on a marked
mob is secret. The value is asked "secret or not" first (Restrict.IsSecret), and a secret
one is never compared, indexed, stored, joined or passed to SetRaidTargetIconTexture. Only
a plain value is tested against nil.
]]

ns.Sense = ns.Sense or {}
local Sense = ns.Sense

local Restrict = LibStub("LibICRestrict-1.0")

local NAMEPLATES = 40        -- nameplate1 .. nameplate40
local RAID, PARTY = 40, 4

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function Plain(v)
    if Restrict.IsSecret(v) then return nil end
    return v
end

local function Exists(unit)
    local yes = Call(UnitExists, unit)
    return Plain(yes) == true
end

function Sense.Facts(unit)
    if IC_HEADLESS or not Exists(unit) then return nil end
    local guid = Plain(Call(UnitGUID, unit))
    local name = Plain(Call(UnitName, unit))
    if type(guid) ~= "string" then guid = nil end
    if type(name) ~= "string" or name == "" then name = nil end
    if not guid and not name then return nil end
    return { guid = guid, name = name }
end

function Sense.Marked(unit)
    if IC_HEADLESS or not Exists(unit) then return nil end
    local v = Call(GetRaidTargetIndex, unit)
    if Restrict.IsSecret(v) then return true, nil end   -- marked, icon hidden: nothing more
    if v == nil then return false end
    if Restrict.InCombat() then return true, nil end     -- plain, but in combat show only planned
    if type(v) == "number" then return true, v end
    return nil
end

local function Units()
    local units = { "target", "focus", "mouseover" }
    for i = 1, NAMEPLATES do units[#units + 1] = "nameplate" .. i end
    local inRaid = Plain(Call(IsInRaid)) == true
    if inRaid then
        for i = 1, RAID do units[#units + 1] = "raid" .. i .. "target" end
    else
        units[#units + 1] = "playertarget"
        for i = 1, PARTY do units[#units + 1] = "party" .. i .. "target" end
    end
    return units
end

function Sense.Reads()
    if IC_HEADLESS or Restrict.InCombat() then return {} end
    local reads, seen = {}, {}
    for _, unit in ipairs(Units()) do
        local marked, icon = Sense.Marked(unit)
        if marked and icon then
            local facts = Sense.Facts(unit)
            local id = facts and (facts.guid or facts.name)
            if id and not seen[id] then
                seen[id] = true
                reads[#reads + 1] = { guid = facts.guid, name = facts.name, icon = icon }
            end
        end
    end
    return reads
end

function Sense.Blind()
    return true
end
