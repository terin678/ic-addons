local addonName, ns = ...

--[[
CombatLog: switches the client's own combat log file on inside the instances the player
listed, and off again on the way out, so there is a file to upload after a raid.

Owned by lane H (ops). Pure half first (ShouldLog, Decide, WhenToCheck, Command,
StatusLines), each with a case in Tests_Ops.lua; the client half runs only from the
OnReady hook at the bottom and returns early on IC_HEADLESS.

Off by default, and on purpose. LoggingCombat(true) works from Lua on this client and the
file is written, but late: on the probe of 2026-11-05 it read 0 bytes through a pull and a
reload, then held the fight a few minutes later (Docs/client-reference.md, "The combat
log"). So the schema's switch is on while its instance list is empty: nothing is logged
until a player lists an instance with /mfd combatlog here, and the status line says the
file fills late. LoggingCombat() with no argument reads a plain boolean, in combat too
(probe rows log.LoggingCombat.read); View() hands that and the session state to the
settings tab.

Never registers the combat log event (CLEU): on this client the registration itself is
ADDON_ACTION_FORBIDDEN. Nothing here reads the log; it only opens and closes the file.

Kept from Anniversary: decide two seconds after a zone event, because the instance is not
reliable the instant a loading screen ends; only ever close a log where this would have
opened one, so a log somebody keeps by hand is never touched; look again at every pull,
since another addon can switch logging off mid-raid.

New here: the pull is seen through LibICRestrict, whose combat flag turns on at
PLAYER_REGEN_DISABLED, about three seconds before the Combat restriction and lockdown.
That gap is when the pull check runs. If the client refuses LoggingCombat at that moment,
the check waits for the end of combat and tries once more, and the status line says so.
]]

ns.CombatLog = ns.CombatLog or {}
local CombatLog = ns.CombatLog

CombatLog.SETTLE_SECONDS = 2   -- seconds after a zone event before asking where we are
CombatLog.OPEN_WORLD = "open"  -- the instance key outside any instance (spec 7.1)

-- Shown with the status while anything is listed: an empty file right after a pull is
-- normal on this client, not a failure.
CombatLog.CAVEAT = "The client writes the log file late: it can stay empty through a pull "
    .. "and fill a few minutes later, so upload it after the session."

-- Events that start the settle timer. Both confirmed on this client by Stickies and the
-- probe (zone changes, loading screens).
CombatLog.ZONE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

--------------------------------------------------------------------------------
-- Pure: the decisions
--------------------------------------------------------------------------------

-- The instance key for what GetInstanceInfo reported: "i:<id>" inside an instance,
-- OPEN_WORLD outside, nil when the answer is not readable (a secret or a missing value),
-- in which case nothing is decided.
function CombatLog.InstanceKey(instanceType, instanceID)
    if type(instanceType) ~= "string" then return nil end
    if instanceType == "none" then return CombatLog.OPEN_WORLD end
    if type(instanceID) ~= "number" then return nil end
    return "i:" .. instanceID
end

-- Should the file be open here? settings is db.settings.logCombat. Only a listed
-- instance logs; the open world never does, listed or not.
function CombatLog.ShouldLog(instanceKey, settings)
    if type(settings) ~= "table" or settings.enabled ~= true then return false end
    if type(instanceKey) ~= "string" or instanceKey == CombatLog.OPEN_WORLD then return false end
    return type(settings.instances) == "table" and settings.instances[instanceKey] == true
end

-- Whether there is anywhere to log at all; when there is not, nothing listens.
function CombatLog.HasWork(settings)
    if type(settings) ~= "table" or settings.enabled ~= true then return false end
    for key, on in pairs(type(settings.instances) == "table" and settings.instances or {}) do
        if on == true and key ~= CombatLog.OPEN_WORLD then return true end
    end
    return false
end

--[[
What to do, from whether we should log, whether the client is logging, and whether the
running log is ours to close. Returns "start", "adopt", "stop" or nil.
"adopt" is the reload case: the claim is not saved, so after a reload inside a listed
instance the running log is taken over, which is safe exactly where this would have
started it. Where we should not log, a log nobody claimed is left alone.
]]
function CombatLog.Decide(shouldLog, isLogging, isOurs)
    if shouldLog and not isLogging then return "start" end
    if shouldLog and isLogging and not isOurs then return "adopt" end
    if not shouldLog and isLogging and isOurs then return "stop" end
    return nil
end

--[[
When a restriction change means look again. previous and now are LibICRestrict states
(previous nil before the first one). isWaiting is true when a check was refused in combat.
Returns "pull" when combat has just begun (the regen event, before the lock), "after"
when combat ended with a check waiting, else nil.
]]
function CombatLog.WhenToCheck(previous, now, isWaiting)
    if type(now) ~= "table" then return nil end
    local was = type(previous) == "table" and previous.combat == true
    if now.combat == true and not was then return "pull" end
    if now.combat ~= true and was and isWaiting then return "after" end
    return nil
end

--[[
Parses "/mfd combatlog <rest>". view: { key = current instance key or nil,
settings = db.settings.logCombat }. Returns a plan:
    { action = "status" }
    { action = "enable" } / { action = "disable" }
    { action = "add", key = k } / { action = "remove", key = k }
    { action = "refuse", why = text }
]]
function CombatLog.Command(rest, view)
    local word = (type(rest) == "string" and rest or ""):lower():match("^%s*(%S*)") or ""
    view = view or {}
    if word == "" or word == "status" then return { action = "status" } end
    if word == "on" then return { action = "enable" } end
    if word == "off" then return { action = "disable" } end
    if word == "here" then
        local key = view.key
        if key == nil then
            return { action = "refuse", why = "where you are is not readable yet; try again in a moment" }
        end
        if key == CombatLog.OPEN_WORLD then
            return { action = "refuse", why = "the open world is never logged; go inside the instance first" }
        end
        local listed = type(view.settings) == "table" and type(view.settings.instances) == "table"
            and view.settings.instances[key] == true
        return { action = listed and "remove" or "add", key = key }
    end
    return { action = "refuse", why = "use /mfd combatlog, /mfd combatlog here, on or off" }
end

local GREEN, GREY, AMBER, RED, CLOSE = "|cff66ff66", "|cff999999", "|cffffcc00", "|cffff4444", "|r"

-- How many instances are listed.
local function Listed(settings)
    local n = 0
    for key, on in pairs(type(settings) == "table" and type(settings.instances) == "table"
        and settings.instances or {}) do
        if on == true and key ~= CombatLog.OPEN_WORLD then n = n + 1 end
    end
    return n
end

--[[
The status, as lines. view:
    settings   db.settings.logCombat
    key        the current instance key, or nil when unknown
    name       the instance's name, optional
    isLogging  the client's answer, or nil when unknown
    isOurs     whether this addon opened (or adopted) the running log
    waiting    a check was refused in combat and runs again when it ends
Every line says what is true and, where something is off, what turns it on.
]]
function CombatLog.StatusLines(view)
    view = view or {}
    local settings = view.settings
    local lines = {}
    local count = Listed(settings)

    if type(settings) ~= "table" or settings.enabled ~= true then
        lines[1] = GREY .. "combat logging is off." .. CLOSE .. " /mfd combatlog on turns it on."
    elseif count == 0 then
        lines[1] = GREY .. "combat logging: no instance listed, so nothing is logged." .. CLOSE
            .. " Inside one, /mfd combatlog here adds it."
    else
        lines[1] = string.format("combat logging: %d instance%s listed.", count, count == 1 and "" or "s")
    end

    local here
    if view.key == nil then
        here = GREY .. "here: not known yet." .. CLOSE
    elseif view.key == CombatLog.OPEN_WORLD then
        here = "here: the open world, never logged."
    else
        local label = view.name and (view.name .. ", " .. view.key) or view.key
        local should = CombatLog.ShouldLog(view.key, settings)
        here = "here (" .. label .. "): " .. (should and "listed" or "not listed")
    end

    if view.isLogging == true then
        here = here .. "; the client is " .. GREEN .. "logging" .. CLOSE
            .. (view.isOurs and " (opened by MFD)." or " (opened by someone else; left alone).")
    elseif view.isLogging == false then
        here = here .. "; the client is not logging."
    elseif view.key ~= nil then
        here = here .. "; whether the client is logging is not readable."
    end
    lines[#lines + 1] = here

    if view.waiting then
        lines[#lines + 1] = AMBER .. "the client refused the switch in combat; it is tried again when combat ends."
            .. CLOSE
    end
    if count > 0 and settings.enabled == true then
        lines[#lines + 1] = AMBER .. CombatLog.CAVEAT .. CLOSE
    end
    return lines
end

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

-- Session state. isOurs is deliberately not saved: a reload does not know what it
-- inherited, and the first check after it works that out again (the "adopt" case).
CombatLog.isOurs = false
CombatLog.waiting = false

local Restrict = LibStub("LibICRestrict-1.0")

local function Settings()
    return ns.db and ns.db.settings and ns.db.settings.logCombat
end

-- The current instance: key, name. Both nil when unreadable.
local function Where()
    local ok, name, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok then return nil, nil end
    instanceType = Restrict.Readable(instanceType)
    instanceID = Restrict.Readable(instanceID)
    name = Restrict.Readable(name)
    return CombatLog.InstanceKey(instanceType, instanceID), type(name) == "string" and name or nil
end

-- Whether the client is logging: true, false, or nil when it will not say.
local function IsLogging()
    local ok, on = pcall(LoggingCombat)
    if not ok or Restrict.IsSecret(on) then return nil end
    return on and true or false
end

--[[
What only the client half knows, for a status view: the settings tab (lane G) merges it
into the view it passes to StatusLines.
    isLogging  the client's answer, or nil when it will not say
    isOurs     whether this addon opened (or adopted) the running log
    waiting    a check was refused in combat and runs again when it ends
read, for a test, stands in for the client read; it defaults to IsLogging.
]]
function CombatLog.View(read)
    local isLogging = (read or IsLogging)()
    if isLogging ~= nil then isLogging = isLogging == true end
    return {
        isLogging = isLogging,
        isOurs = CombatLog.isOurs == true,
        waiting = CombatLog.waiting == true,
    }
end

-- Switches the file. Returns true when the client took the call.
local function Switch(on)
    local ok = pcall(LoggingCombat, on)
    return ok
end

-- Looks at where we are and acts. reason, when given, ends the debug line.
function CombatLog.Check(reason)
    local settings = Settings()
    if not settings then return end
    local key, name = Where()
    if key == nil then
        ns.Debug("combat log: instance not readable, nothing decided")
        return
    end
    local isLogging = IsLogging()
    if isLogging == nil then
        ns.Debug("combat log: LoggingCombat() did not answer, nothing decided")
        return
    end

    local action = CombatLog.Decide(CombatLog.ShouldLog(key, settings), isLogging, CombatLog.isOurs)
    local where = name or key
    if action == "start" then
        if not Switch(true) then
            CombatLog.waiting = Restrict.Now().combat == true
            ns.Print(RED .. "combat logging could not be switched on" .. CLOSE .. " in " .. where
                .. (CombatLog.waiting and "; it is tried again when combat ends." or "."))
            return
        end
        CombatLog.isOurs, CombatLog.waiting = true, false
        ns.Print(GREEN .. "combat logging on" .. CLOSE .. " in " .. where
            .. ". The file is Logs\\WoWCombatLog in the game folder.")
        ns.Print(AMBER .. CombatLog.CAVEAT .. CLOSE)
        ns.Debug("combat log: started in " .. key .. (reason and (", " .. reason) or ""))
    elseif action == "adopt" then
        CombatLog.isOurs = true
        ns.Debug("combat log: already on in " .. key .. ", taken over so it stops on the way out")
    elseif action == "stop" then
        if not Switch(false) then
            CombatLog.waiting = Restrict.Now().combat == true
            ns.Debug("combat log: the switch off was refused" .. (CombatLog.waiting and ", waiting for combat to end" or ""))
            return
        end
        CombatLog.isOurs, CombatLog.waiting = false, false
        ns.Print(GREY .. "combat logging off" .. CLOSE .. ", out of the listed instance.")
    else
        CombatLog.waiting = false
    end
end

local function CheckSafely(reason)
    local ok, err = pcall(CombatLog.Check, reason)
    if not ok then ns.Print(RED .. "the combat logging check failed:" .. CLOSE .. " " .. tostring(err)) end
    CombatLog.Sync()
end

-- One timer for the burst of zone events a loading screen produces.
local settling = false
local function Settle()
    if settling then return end
    settling = true
    C_Timer.After(CombatLog.SETTLE_SECONDS, function()
        settling = false
        CheckSafely()
    end)
end

local stopRestrict
local function OnRestriction(now, previous)
    local when = CombatLog.WhenToCheck(previous, now, CombatLog.waiting)
    if when == "pull" then
        CheckSafely("at a pull")
    elseif when == "after" then
        CheckSafely("after combat, a refused switch tried again")
    end
end

-- Listens only while there is somewhere to log, or a log of ours to close; idle costs
-- nothing. Called at login and after every settings change.
function CombatLog.Sync()
    local want = CombatLog.HasWork(Settings()) or CombatLog.isOurs
    local listening = stopRestrict ~= nil
    if want and not listening then
        for _, event in ipairs(CombatLog.ZONE_EVENTS) do ns.Events.On(event, "combatlog", Settle) end
        stopRestrict = Restrict.OnChange(OnRestriction)
    elseif not want and listening then
        for _, event in ipairs(CombatLog.ZONE_EVENTS) do ns.Events.Off(event, "combatlog") end
        stopRestrict()
        stopRestrict = nil
    end
end

local function PrintStatus()
    local view = CombatLog.View()
    view.settings = Settings()
    view.key, view.name = Where()
    for _, line in ipairs(CombatLog.StatusLines(view)) do
        ns.Print(line)
    end
end

ns.AddCommand("combatlog", "combat logging: status; here lists or unlists this instance; on or off",
    function(rest)
        local settings = Settings()
        if not settings then
            ns.Print("the saved settings are not in hand yet.")
            return
        end
        local plan = CombatLog.Command(rest, { key = (Where()), settings = settings })
        if plan.action == "refuse" then
            ns.Print(plan.why .. ".")
            return
        elseif plan.action == "enable" then
            settings.enabled = true
        elseif plan.action == "disable" then
            settings.enabled = false
        elseif plan.action == "add" then
            if type(settings.instances) ~= "table" then settings.instances = {} end
            settings.instances[plan.key] = true
        elseif plan.action == "remove" then
            settings.instances[plan.key] = nil
        end
        if plan.action ~= "status" then CheckSafely("settings changed") end
        PrintStatus()
    end, "combatlog [here|on|off]")

ns.OnReady("combatlog", function()
    if IC_HEADLESS then return end
    CombatLog.Sync()
    if stopRestrict then Settle() end
end)
