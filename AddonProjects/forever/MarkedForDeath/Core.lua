local addonName, ns = ...

--[[
Marked For Death on WoW Forever: a raid's crowd control and kill order, the same every
night. The eight raid icons belong to seats (Kill 1 to 4, Sheep 1 and 2, Banish 1 and 2), a
mob rule names a job and never an icon, and the plan reaches the mobs through the player's
own keypress. The design is Docs/forever/specs/2026-11-05-mfd-forever-design.md.

Owned by lane S (the scaffold). This file is the plumbing every other module stands on,
so no other lane edits it:

    ns.AddCommand(name, desc, fn)   a /mfd command, added by the module that owns it
    ns.OnReady(label, fn)           a frame module's setup, run once at login
    ns.Events.On(event, key, fn)    one shared event frame; an event is registered only
    ns.Events.Off(event, key)       while something listens to it, so idle costs nothing

    Schema.lua   saved tables, schema and migrations      (LibICStore)
    Core.lua     this file: console, events, login         (LibICConsole, LibICEnv)
    Tests.lua    the case registry runner                  (LibICTest)

This file calls no client API beyond what Stickies already uses on this client:
CreateFrame, RegisterEvent, UnregisterEvent, SetScript and the slash command table.
]]

local VERSION = "0.1.0"

local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")

local out = Console.New("MarkedForDeath", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Tests = Test.New({ print = out.Print })

--------------------------------------------------------------------------------
-- Pure: what it says at login
--------------------------------------------------------------------------------

function ns.LoadLines(version, info)
    local lines = {
        string.format("v%s loaded. /mfd help lists commands.", version),
    }
    if info and info.lost then
        lines[#lines + 1] = "|cffff4444The account settings did not load.|r This character has used "
            .. "Marked For Death before, yet the account file came back empty. A client left running "
            .. "across .toc edits does this."
        lines[#lines + 1] = "|cffff4444Restart the client before you log out or reload|r, or the empty "
            .. "rules and plans are written over the file."
    end
    return lines
end

--------------------------------------------------------------------------------
-- Pure: the command set
--------------------------------------------------------------------------------

--[[
A help list and a command table that modules add to, so no lane edits a central table.
`head` rows come first, then every added command in load order, then `tail` rows.
Returns set with:
    set.help        the rows LibICConsole prints, kept in that order
    set.commands    name -> fn(rest, name)
    set.Add(name, desc, fn, usage)  -> true, or false and why
`usage` is what help shows in place of the bare name ("capture on|off").
]]
function ns.NewCommandSet(head, tail)
    local set = { help = {}, commands = {} }
    local tailRows = tail or {}
    for _, row in ipairs(head or {}) do set.help[#set.help + 1] = row end
    for _, row in ipairs(tailRows) do set.help[#set.help + 1] = row end

    local function Taken(name)
        if set.commands[name] then return true end
        for _, row in ipairs(set.help) do
            if (row[1]:match("^(%S*)") or "") == name then return true end
        end
        return false
    end

    function set.Add(name, desc, fn, usage)
        if type(name) ~= "string" or not name:match("^[%l%d]+$") then
            return false, "a command name is one lower-case word"
        end
        if type(fn) ~= "function" then
            return false, "command " .. name .. " has no function"
        end
        if Taken(name) then
            return false, "command " .. name .. " is already taken"
        end
        set.commands[name] = fn
        table.insert(set.help, #set.help - #tailRows + 1, { usage or name, tostring(desc or "") })
        return true
    end

    return set
end

--------------------------------------------------------------------------------
-- Pure: who listens to which event
--------------------------------------------------------------------------------

--[[
The bookkeeping half of the shared event frame. Handlers are keyed so a module can drop
its own without knowing anyone else's. Returns set with:
    set.On(event, key, fn)  -> true when this is the event's first listener (register it)
    set.Off(event, key)     -> true when that was its last listener (unregister it)
    set.Each(event)         -> the handlers, in key order, for one delivery
]]
function ns.NewEventSet()
    local set = { listeners = {} }

    function set.On(event, key, fn)
        assert(type(event) == "string" and type(key) == "string" and type(fn) == "function",
            "Events.On needs an event, a key and a function")
        local list = set.listeners[event]
        local first = list == nil
        if first then
            list = {}
            set.listeners[event] = list
        end
        list[key] = fn
        return first
    end

    function set.Off(event, key)
        local list = set.listeners[event]
        if not list or list[key] == nil then return false end
        list[key] = nil
        if next(list) == nil then
            set.listeners[event] = nil
            return true
        end
        return false
    end

    function set.Each(event)
        local list = set.listeners[event]
        local fns = {}
        if not list then return fns end
        local keys = {}
        for key in pairs(list) do keys[#keys + 1] = key end
        table.sort(keys)
        for i, key in ipairs(keys) do fns[i] = list[key] end
        return fns
    end

    return set
end

--------------------------------------------------------------------------------
-- Saved tables
--------------------------------------------------------------------------------

Store.Register(addonName, ns.Schema.Spec(Env.Wrap("MarkedForDeath saved variables", function(db, cdb, info)
    ns.db, ns.cdb, ns.loadInfo = db, cdb, info
end)))

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventSet = ns.NewEventSet()
local frame = CreateFrame("Frame")

ns.Events = {}

-- fn(event, ...) runs on every delivery of `event` while `key` is listening.
function ns.Events.On(event, key, fn)
    if eventSet.On(event, key, fn) and event ~= "PLAYER_LOGIN" then
        frame:RegisterEvent(event)
    end
end

function ns.Events.Off(event, key)
    if eventSet.Off(event, key) and event ~= "PLAYER_LOGIN" then
        frame:UnregisterEvent(event)
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local commandSet = ns.NewCommandSet(
    { { "", "this list" } },
    {
        { "debug", "turn debug lines on or off" },
        { "version", "the version running" },
        { "selftest", "run the built-in checks (also: test)" },
        { "help", "this list" },
    }
)
local COMMANDS = commandSet.commands

-- Adds a /mfd command from the module that owns it. A name already taken is refused
-- with a line in chat, so a clash between two lanes shows at login rather than silently.
function ns.AddCommand(name, desc, fn, usage)
    local ok, why = commandSet.Add(name, desc, fn, usage)
    if not ok then out.Print("|cffff4444" .. why .. ".|r") end
    return ok
end

local _, Help = Console.Dispatcher({ slash = { "/mfd" }, out = out, help = commandSet.help })
COMMANDS[""] = Help
COMMANDS.help = Help

COMMANDS.version = function()
    out.Printf("v%s.", VERSION)
end

COMMANDS.debug = function()
    if not ns.db then
        out.Print("the saved settings are not in hand yet.")
        return
    end
    ns.db.settings.debug = not ns.db.settings.debug
    out.Print(ns.db.settings.debug and "debug lines are on." or "debug lines are off.")
end

COMMANDS.selftest = function()
    ns.Tests.Run()
end
COMMANDS.test = COMMANDS.selftest

local _, slashTaken = Console.Slash({
    key = "MARKEDFORDEATH", slash = { "/mfd" }, out = out, help = commandSet.help, commands = COMMANDS,
})

--------------------------------------------------------------------------------
-- Login
--------------------------------------------------------------------------------

local readyHooks = {}

-- fn() runs once at PLAYER_LOGIN, when the saved tables are in hand and the screen has
-- its size. Frame modules create their frames here, never at file scope. A hook that
-- errors is reported and the rest still run.
function ns.OnReady(label, fn)
    readyHooks[#readyHooks + 1] = { label = label, fn = Env.Wrap("MarkedForDeath " .. label, fn) }
end

local function Login()
    for _, hook in ipairs(readyHooks) do
        local ok, err = pcall(hook.fn)
        if not ok then
            out.Printf("|cffff4444%s did not start:|r %s", hook.label, tostring(err))
        end
    end
    for _, line in ipairs(ns.LoadLines(VERSION, ns.loadInfo)) do out.Print(line) end
    if slashTaken then
        out.Print("|cffff9900another addon already registered the MARKEDFORDEATH slash key.|r "
            .. "One of you owns /mfd now.")
    end
end

eventSet.On("PLAYER_LOGIN", "core", Login)
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", Env.Wrap("MarkedForDeath events", function(_, event, ...)
    for _, fn in ipairs(eventSet.Each(event)) do fn(event, ...) end
    if event == "PLAYER_LOGIN" then
        eventSet.listeners.PLAYER_LOGIN = nil
        frame:UnregisterEvent("PLAYER_LOGIN")
    end
end))
