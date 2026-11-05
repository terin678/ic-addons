local addonName, ns = ...

--[[
CaptureWatch: /mfd capture, and the events capture mode listens to while it is on.

Owned by lane E (data and capture). Frame module: it reads the client only inside the
functions below, which run from the /mfd capture command or the ns.OnReady hook, and the
hook returns early on IC_HEADLESS. While capture is off nothing is registered.

While on, it records (spec section 9):
  - the instance on every zone change: GetInstanceInfo's id, name, type, difficulty, size
  - ENCOUNTER_START and ENCOUNTER_END: id, name, difficulty, size, kill or wipe
  - target, mouseover and new nameplates, out of combat only: npc id and name when the
    client lets an addon read them; a secret read is counted, never stored
  - the player's own auras out of combat when auras are not secret, and the player's own
    successful casts by spell id (a hunter's Freezing Trap)
It never registers COMBAT_LOG_EVENT_UNFILTERED and never calls SetRaidTarget; both raise
ADDON_ACTION_FORBIDDEN on this client. Every value that may be secret goes through
LibICRestrict before Capture.Merge sees it.
]]

ns.CaptureWatch = ns.CaptureWatch or {}
local Watch = ns.CaptureWatch

local Restrict = LibStub("LibICRestrict-1.0")
local W = LibStub("LibICWidgets-1.0")
local Capture = ns.Capture

local KEY = "capture"           -- this module's key on the shared event frame
local AURA_SETTLE = 1           -- seconds: a burst of UNIT_AURA on the player reads once
local MAX_AURAS = 40            -- helpful aura slots read per pass
local COPY_FRAME = "MarkedForDeathCaptureCopy"

local Readable = Restrict.Readable

local running = false
local fighting = false          -- between PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED
local here = 0                  -- the current instance id, 0 in the open world
local auraPending = false
local copyBox

local function Store()
    return ns.db and ns.db.capture
end

local function Merge(obs)
    local store = Store()
    if not store or not obs then return end
    local result, why = Capture.Merge(store, obs, time())
    if not result then ns.Debug("capture skipped: " .. tostring(why)) end
end

local function InCombat()
    return fighting or Restrict.InCombat()
end

-- A client function, called guarded: nil when it is missing or throws.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function ReadInstance()
    local name, kind, diff, diffName, size, dyn, isDyn, id = Ask(GetInstanceInfo)
    id = Readable(id)
    here = type(id) == "number" and id or 0
    Merge(Capture.InstanceObservation(Readable(name), Readable(kind), Readable(diff),
        Readable(diffName), Readable(size), dyn, isDyn, id))
end

local function ReadUnit(unit)
    if InCombat() then return end
    if not Ask(UnitExists, unit) then return end
    local secrets = C_Secrets
    if secrets and Ask(secrets.ShouldUnitIdentityBeSecret, unit) == true then
        Merge({ kind = "npc", secret = true })
        return
    end
    local guid = Ask(UnitGUID, unit)
    if Restrict.IsSecret(guid) then
        Merge({ kind = "npc", secret = true })
        return
    end
    local id = Capture.NpcID(guid)
    if not id then return end   -- a player, a pet, an object: not a mob
    local name = Ask(UnitName, unit)   -- one value: Readable's second argument is its fallback
    name = Readable(name)
    if not name then
        Merge({ kind = "npc", secret = true })
        return
    end
    Merge({
        kind = "npc", id = id, name = name, instance = here,
        creature = Readable(Ask(UnitCreatureType, unit)),
        classification = Readable(Ask(UnitClassification, unit)),
    })
end

local function ReadAuras()
    auraPending = false
    if not running or InCombat() then return end
    local secrets = C_Secrets
    if secrets and Ask(secrets.ShouldAurasBeSecret) ~= false then return end
    local auras = C_UnitAuras
    if not auras then return end
    for i = 1, MAX_AURAS do
        local data = Ask(auras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if type(data) ~= "table" then break end
        local id = Readable(data.spellId)
        if type(id) == "number" then
            Merge({ kind = "aura", id = id, name = Readable(data.name), source = "aura" })
        end
    end
end

local function ReadCast(spellID)
    spellID = Readable(spellID)
    if type(spellID) ~= "number" then return end
    local spell = C_Spell
    local name = spell and Readable(Ask(spell.GetSpellName, spellID)) or nil
    Merge({ kind = "aura", id = spellID, name = name, source = "cast" })
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local HANDLERS = {}

HANDLERS.PLAYER_ENTERING_WORLD = ReadInstance
HANDLERS.ZONE_CHANGED_NEW_AREA = ReadInstance

HANDLERS.PLAYER_REGEN_DISABLED = function() fighting = true end
HANDLERS.PLAYER_REGEN_ENABLED = function() fighting = false end

HANDLERS.ENCOUNTER_START = function(_, encounterID, name, difficulty, size)
    Merge({ kind = "encounter", id = Readable(encounterID), name = Readable(name), instance = here,
        difficulty = Readable(difficulty), size = Readable(size), result = "start" })
end

HANDLERS.ENCOUNTER_END = function(_, encounterID, name, difficulty, size, success)
    success = Readable(success)
    local result
    if success == 1 or success == true then result = "kill" elseif success == 0 or success == false then result = "wipe" end
    if not result then return end   -- the outcome is secret: the pull was already counted
    Merge({ kind = "encounter", id = Readable(encounterID), name = Readable(name), instance = here,
        difficulty = Readable(difficulty), size = Readable(size), result = result })
end

HANDLERS.PLAYER_TARGET_CHANGED = function() ReadUnit("target") end
HANDLERS.UPDATE_MOUSEOVER_UNIT = function() ReadUnit("mouseover") end
HANDLERS.NAME_PLATE_UNIT_ADDED = function(_, unit)
    if type(unit) == "string" and not Restrict.IsSecret(unit) then ReadUnit(unit) end
end

HANDLERS.UNIT_AURA = function(_, unit)
    if unit ~= "player" or auraPending then return end
    auraPending = true
    C_Timer.After(AURA_SETTLE, ReadAuras)
end

HANDLERS.UNIT_SPELLCAST_SUCCEEDED = function(_, unit, _, spellID)
    if unit == "player" then ReadCast(spellID) end
end

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
}

-- Registers every capture event. An event this client does not know is reported once and
-- the rest still register.
local function Start()
    if running then return end
    running = true
    fighting = Ask(InCombatLockdown) == true
    for _, event in ipairs(EVENTS) do
        local ok = pcall(ns.Events.On, event, KEY, HANDLERS[event])
        if not ok then
            pcall(ns.Events.Off, event, KEY)
            ns.Printf("|cffff9900capture cannot listen to %s on this client.|r", event)
        end
    end
    ReadInstance()
    if not InCombat() then ReadAuras() end
end

local function Stop()
    if not running then return end
    running = false
    for _, event in ipairs(EVENTS) do ns.Events.Off(event, KEY) end
end

function Watch.IsRunning()
    return running
end

--------------------------------------------------------------------------------
-- The export box
--------------------------------------------------------------------------------

-- One movable panel with the export text selected, ready for Ctrl+C. Built on first use.
local function ShowCopy(text)
    if not copyBox then
        local panel = W.Panel(UIParent, { name = COPY_FRAME, width = 460, height = 96,
            strata = "DIALOG", movable = true, role = "raised" })
        panel:SetPoint("CENTER")
        local title = W.Label(panel, "Capture export: Ctrl+C to copy, then paste it for the raid lead.",
            { font = "small" })
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
        local box = W.EditBox(panel, 440, 22, {
            onEscape = function() panel:Hide() end,
        })
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -32)
        local close = W.Button(panel, "Close", 80, 22, { onClick = function() panel:Hide() end })
        close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)
        panel.box = box
        tinsert(UISpecialFrames, COPY_FRAME)
        copyBox = panel
    end
    copyBox.box:SetText(text)
    copyBox:Show()
    copyBox.box:SetFocus()
    copyBox.box:HighlightText()
end

--------------------------------------------------------------------------------
-- The command
--------------------------------------------------------------------------------

local function Status()
    ns.Print(running and "capture is |cff44ff44on|r." or "capture is |cffff4444off|r.")
end

local SUB = {}

SUB.on = function()
    ns.db.settings.capture = true
    Start()
    ns.Print("capture is |cff44ff44on|r: instance, encounter and mob ids are recorded until /mfd capture off.")
end

SUB.off = function()
    ns.db.settings.capture = false
    Stop()
    ns.Print("capture is |cffff4444off|r. /mfd capture show lists what it kept.")
end

SUB.show = function()
    Status()
    for _, line in ipairs(Capture.Summary(Store(), function(id) return ns.Instances.Name(id) end)) do
        ns.Print(line)
    end
end

SUB.export = function()
    local text, why = Capture.Export(Store(), {
        version = ns.VERSION,
        build = (select(2, Ask(GetBuildInfo))),
        now = time(),
    })
    if not text then
        ns.Print("|cffff4444the capture could not be exported:|r " .. tostring(why))
        return
    end
    ShowCopy(text)
    ns.Printf("the export is %d characters, in the box on screen.", #text)
end

SUB.clear = function()
    local shown = W.Confirm("Forget everything capture has recorded?", function()
        Capture.Clear(Store())
        ns.Print("capture store cleared.")
    end)
    if not shown then
        Capture.Clear(Store())
        ns.Print("capture store cleared.")
    end
end

local function Command(rest)
    if not ns.db then
        ns.Print("the saved settings are not in hand yet.")
        return
    end
    local word = (rest or ""):match("^%s*(%S*)"):lower()
    local fn = SUB[word]
    if fn then
        fn()
        return
    end
    Status()
    ns.Print("/mfd capture on|off|show|export|clear")
end

ns.AddCommand("capture", "record instance, encounter and mob ids for the data files", Command,
    "capture on|off|show|export|clear")

ns.OnReady("capture", function()
    if IC_HEADLESS then return end
    if ns.db and ns.db.settings.capture then Start() end
end)
