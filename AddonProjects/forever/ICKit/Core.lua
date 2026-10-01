local addonName, ns = ...

--[[
ICKit: the kit under the Impulse Control addons for WoW Forever.

It is built bottom-up, one layer at a time, and a layer is added only when an addon needs
it (Docs/forever/VISION.md has the rules and the order):

    layer 0   LibICUtil-1.0     pure helpers
              LibICTest-1.0     the case runner
    layer 1   LibICEnv-1.0      what this client offers, and what the addons cost it
              LibICStore-1.0    saved variables
              LibICConsole-1.0  printing and slash commands
              LibICTheme-1.0    the theme registry                next
    layer 2   LibICWidgets-1.0  themed frames                     next

This file is the addon around the libraries: its version, its saved tables, its commands.
The libraries never print; what the kit says, it says here.

    Probe.lua   the checklist /ickit probe runs against this client
    Tests.lua   the kit's own cases
]]

local VERSION = "0.2.0"

local Util = LibStub("LibICUtil-1.0")
local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")

local out = Console.New("ICKit", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Util, ns.Env = Util, Env
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Tests = Test.New({
    print = out.Print,
    onDone = function(result)
        if ns.db then
            ns.db.lastTestRun = { at = time(), passed = result.passed, failed = result.failed }
        end
    end,
})

--------------------------------------------------------------------------------
-- Pure: what the kit says
--------------------------------------------------------------------------------

-- Env.Build's table as one phrase: "1.60.1 (70124), interface 16001".
function ns.DescribeBuild(build)
    build = build or {}
    return string.format("%s (%s), interface %s",
        tostring(build.version or "?"), tostring(build.build or "?"), tostring(build.interface or "?"))
end

-- The lines printed at login. A lost account file is the one thing said in red: the
-- player can still save it by not logging out.
function ns.LoadLines(version, build, info)
    local lines = {
        string.format("v%s on %s. /ickit help lists commands.", version, ns.DescribeBuild(build)),
    }
    if not info then
        lines[#lines + 1] = "|cffff4444The saved tables never arrived.|r The client did not report this addon as loaded."
    elseif info.lost then
        lines[#lines + 1] = "|cffff4444The saved settings did not load.|r This character has run ICKit before, "
            .. "yet the account file came back empty. A client left running across .toc edits does this."
        lines[#lines + 1] = "|cffff4444Restart the client before you log out or reload|r, or the empty table is "
            .. "written over the file."
    elseif info.firstRun then
        lines[#lines + 1] = "first run on this account."
    end
    return lines
end

-- /ickit profile, as lines. rows are Env.Counters(); the two client figures may be nil.
function ns.ProfileLines(rows, memoryKB, cpuMs, cpuSource)
    local lines = { "handlers, costliest first:" }
    if #rows == 0 then lines[#lines + 1] = "  nothing has run yet." end
    for _, row in ipairs(rows) do
        lines[#lines + 1] = string.format("  %s: %d %s, %.2f ms in total, %.2f ms at worst",
            row.label, row.calls, Util.Plural(row.calls, "call"), row.total, row.max)
    end
    lines[#lines + 1] = memoryKB and string.format("memory: %.0f KB", memoryKB)
        or "memory: this client does not say."
    lines[#lines + 1] = cpuMs
        and string.format("client CPU figure: %.1f ms (%s; it counts only while that console variable is on)", cpuMs, cpuSource)
        or "client CPU figure: unavailable."
    return lines
end

--------------------------------------------------------------------------------
-- Saved tables
--------------------------------------------------------------------------------

-- The order the client delivers its load events in, and whether the saved tables were in
-- hand by then. The probe saves it: later layers lean on this order.
ns.events = {}

local function Saw(event)
    ns.events[#ns.events + 1] = ns.db and event or (event .. " (before the saved tables)")
end

Store.Register(addonName, {
    account = "ICKitDB",
    character = "ICKitCharDB",
    schema = 1,
    charSchema = 1,
    -- loads counts how often each table has come back from disk: the proof, on a client
    -- nobody has tested, that both kinds of saved variable survive a reload and a relog.
    defaults = { settings = { debug = false }, loads = 0 },
    charDefaults = { loads = 0 },
    onReady = Env.Wrap("ICKit saved variables", function(db, cdb, info)
        ns.db, ns.cdb, ns.loadInfo = db, cdb, info
        db.loads = db.loads + 1
        cdb.loads = cdb.loads + 1
        Saw("ADDON_LOADED")
    end),
})

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "the kit's version, the client build, and how often the saved tables have loaded" },
    { "probe", "check what this client offers and save the answers" },
    { "profile [reset]", "what the kit's handlers have cost: calls, time, memory" },
    { "test", "run the built-in checks" },
    { "debug on | off", "maintainer lines in chat" },
    { "help", "this list" },
}

local COMMANDS = {}

local function Status()
    out.Printf("v%s on %s.", VERSION, ns.DescribeBuild(Env.Build()))
    if ns.db and ns.cdb then
        out.Printf("saved tables: the account's has loaded %d %s, this character's %d.",
            ns.db.loads, Util.Plural(ns.db.loads, "time"), ns.cdb.loads)
    else
        out.Print("|cffff4444saved tables: not in hand.|r")
    end
end
COMMANDS[""] = Status
COMMANDS.version = Status

COMMANDS.test = function()
    ns.Tests.Run()
end

COMMANDS.probe = function()
    local report = ns.Probe.Run()
    report.events = Util.DeepCopy(ns.events)
    if ns.db and ns.cdb then
        report.loads = { account = ns.db.loads, character = ns.cdb.loads }
        ns.db.probe = report
    end
    for _, line in ipairs(ns.Probe.Summary(report)) do out.Print(line) end
    if ns.db then
        out.Print("saved. A /reload writes it to WTF\\Account\\<account>\\SavedVariables\\ICKit.lua.")
    end
end

COMMANDS.profile = function(rest)
    if Util.Trim(rest):lower() == "reset" then
        Env.ResetCounters()
        out.Print("counters reset.")
        return
    end
    local cpu, source = Env.Cpu(addonName)
    for _, line in ipairs(ns.ProfileLines(Env.Counters(), Env.Memory(addonName), cpu, source)) do
        out.Print(line)
    end
end

COMMANDS.debug = function(rest)
    local state = Util.Trim(rest):lower()
    if ns.db and (state == "on" or state == "off") then
        ns.db.settings.debug = (state == "on")
    end
    out.Printf("debug lines are %s.", (ns.db and ns.db.settings.debug) and "on" or "off")
end

local _, slashTaken = Console.Slash({
    key = "ICKIT", slash = { "/ickit" }, out = out, help = HELP, commands = COMMANDS,
})

--------------------------------------------------------------------------------
-- Login
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", Env.Wrap("ICKit events", function(self, event)
    Saw(event)
    if event == "PLAYER_LOGIN" then
        for _, line in ipairs(ns.LoadLines(VERSION, Env.Build(), ns.loadInfo)) do out.Print(line) end
        if slashTaken then
            out.Print("|cffff9900another addon already registered the ICKIT slash key.|r One of you owns /ickit now.")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Once is enough to learn the order; an idle kit listens to nothing it does not need.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end))
