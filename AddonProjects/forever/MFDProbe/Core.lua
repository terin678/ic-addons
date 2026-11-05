local addonName, ns = ...

--[[
MFDProbe: asks the Forever client, in and out of combat and in a group, each thing
MarkedForDeath needs from it, and writes down what came back.

The client hides some values from addons in combat (secret values) and refuses some
actions. Which ones decides what a Forever MarkedForDeath can be, so this is asked on the
client rather than assumed. It is a standalone addon rather than part of ICKit's probe:
the kit's probe asks what exists and never acts, while this one sets raid marks, sends
chat and inspects, and is thrown away once its answers are in Docs/client-reference.md.

    Report.lua   how a result is written down and read back, pure     (cases in Tests.lua)
    Listen.lua   the window in which events are heard                 (LibICEnv)
    Checks.lua   the questions                                        (LibICEnv)
    Core.lua     this file: saved table, commands, the pull capture   (LibICStore, LibICConsole)

Idle costs nothing: no event is registered until a command opens a window or arms a pull.
]]

local VERSION = "0.1.0"

local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")
local Util = LibStub("LibICUtil-1.0")

local out = Console.New("MFDProbe", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Wrap = Env.Wrap
ns.Tests = Test.New({ print = out.Print })

-- Runs kept in the saved table, newest last.
ns.KEEP_RUNS = 40

-- Seconds into a pull at which an armed probe runs, and whether that run is heavy.
ns.PULL_TICKS = { { at = 0, heavy = false }, { at = 3, heavy = true }, { at = 8, heavy = false } }
-- Seconds after combat ends for the last run, and before the pull window closes.
local AFTER_RUN = 2
local AFTER_CLOSE = 10
-- The longest an armed probe waits for a pull, in seconds.
local ARM_LIMIT = 900

--------------------------------------------------------------------------------
-- Shared helpers: the secret test, a call that never stringifies, a row
--------------------------------------------------------------------------------

-- The client's test for a secret value. False everywhere it does not exist.
function ns.IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
end

function ns.IsSecretTable(t)
    if type(issecrettable) ~= "function" then return false end
    local ok, secret = pcall(issecrettable, t)
    return ok and secret == true
end

function ns.InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Pack(ok, ...)
    return ok, select("#", ...), { ... }
end

-- Env.Try with nothing done to the values: Env.Try joins every return into text outside
-- its pcall, and a secret value may not be joined. { ok, n, values } or { ok = false, err }.
function ns.Call(fn, ...)
    if type(fn) ~= "function" then return { ok = false, err = "not a function" } end
    local ok, n, values = Pack(pcall(fn, ...))
    if not ok then return { ok = false, err = tostring(values[1]) } end
    return { ok = true, n = n, values = values }
end

function ns.AddRow(run, id, call)
    local row = ns.Report.Row(id, call, ns.InCombat(), ns.IsSecret, ns.IsSecretTable)
    run.rows[#run.rows + 1] = row
    return row
end

local currentRun
function ns.SetCurrentRun(run) currentRun = run end
function ns.CurrentRun() return currentRun end

--------------------------------------------------------------------------------
-- Saved table
--------------------------------------------------------------------------------

Store.Register(addonName, {
    account = "MFDProbeDB",
    schema = 1,
    defaults = {
        nextId = 1,
        runs = {},
        settings = { debug = false, chat = true },
    },
    onReady = Env.Wrap("MFDProbe saved variables", function(db, _, info)
        ns.db, ns.loadInfo = db, info
    end),
})

local function Ready()
    if ns.db then return true end
    out.Print("the saved table is not in hand yet.")
    return false
end

--------------------------------------------------------------------------------
-- The pull capture
--------------------------------------------------------------------------------

local pull = {}      -- { armed, token, listenRun, inCombat }
local frame = CreateFrame("Frame")

local function Disarm(reason)
    if not pull.armed then return end
    pull.armed = false
    pull.token = nil
    frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ns.Listen.Stop()
    if reason then out.Print(reason) end
end
ns.Disarm = Disarm

local function Arm()
    if pull.armed then
        out.Print("already armed. /mfdp disarm stops it.")
        return
    end
    if ns.InCombat() then
        out.Print("arm out of combat, before the pull.")
        return
    end
    pull.armed = true
    local token = {}
    pull.token = token
    pull.listenRun = ns.Checks.NewRun("pull events", "auto")
    ns.Listen.Ensure(pull.listenRun, ARM_LIMIT)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    out.Printf("armed for the next pull: runs at %s seconds into combat and %ds after it, then disarms. "
        .. "Waits %d minutes at most.", "0, 3 and 8", AFTER_RUN, ARM_LIMIT / 60)
    C_Timer.After(ARM_LIMIT, function()
        if pull.token == token then Disarm("no pull came; disarmed.") end
    end)
end

local function OnCombatStart()
    local token = pull.token
    frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, tick in ipairs(ns.PULL_TICKS) do
        local function Go()
            if pull.token ~= token then return end
            ns.Checks.Run(string.format("pull +%ds", tick.at), "auto", tick.heavy)
        end
        if tick.at == 0 then Go() else C_Timer.After(tick.at, Go) end
    end
end

local function OnCombatEnd()
    local token = pull.token
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.After(AFTER_RUN, function()
        if pull.token ~= token then return end
        ns.Checks.Run("after pull", "auto", false)
    end)
    C_Timer.After(AFTER_CLOSE, function()
        if pull.token ~= token then return end
        Disarm("pull captured. /mfdp report shows the results; /reload writes them to disk.")
    end)
end

frame:SetScript("OnEvent", Env.Wrap("MFDProbe events", function(_, event)
    if not pull.armed then return end
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end))

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "now", "run every check now (sends chat and marks, see /mfdp chat)" },
    { "arm", "capture the next pull: checks at 0, 3 and 8 seconds into combat and after it" },
    { "disarm", "stop waiting for a pull" },
    { "listen [seconds]", "hear events for a while (a ready check, a boss), 60 by default" },
    { "readycheck", "start a ready check and listen for its events" },
    { "report [text]", "what each check came to, out of combat and in it; text keeps matching ids" },
    { "runs", "every run kept, with where it was taken" },
    { "chat on | off", "whether runs send chat lines to the group" },
    { "clear", "forget every run" },
    { "test", "run the built-in checks" },
    { "help", "this list" },
}

local COMMANDS = {}

COMMANDS.now = function()
    if not Ready() then return end
    local run = ns.Checks.Run("now", "command", true)
    out.Printf("run %d taken: %s. Answers that take a moment come in over the next %d seconds.",
        run.id, ns.Report.ContextLabel(run.ctx), 5)
    C_Timer.After(6, function()
        for _, line in ipairs(ns.Report.RunLines(run)) do out.Print(line) end
    end)
end

COMMANDS.arm = function()
    if Ready() then Arm() end
end

COMMANDS.disarm = function()
    if not pull.armed then
        out.Print("not armed.")
        return
    end
    Disarm("disarmed.")
end

COMMANDS.listen = function(rest)
    if not Ready() then return end
    local seconds = Util.Clamp(tonumber(Util.Trim(rest)) or 60, 5, ns.Listen.MAX_SECONDS)
    local run = ns.Checks.NewRun("listen", "command")
    ns.Listen.Ensure(run, seconds)
    out.Printf("listening for %d seconds into run %d.", seconds, run.id)
end

COMMANDS.readycheck = function()
    if not Ready() then return end
    local run = ns.Checks.NewRun("ready check", "command")
    ns.Listen.Ensure(run, 45)
    ns.AddRow(run, "readycheck.DoReadyCheck", ns.Call(DoReadyCheck))
    out.Printf("ready check asked for; listening 45 seconds into run %d.", run.id)
end

COMMANDS.report = function(rest)
    if not Ready() then return end
    local runs = ns.db.runs
    if #runs == 0 then
        out.Print("no runs yet. /mfdp now, or /mfdp arm before a pull.")
        return
    end
    local filter = Util.Trim(rest)
    out.Printf("%d %s kept. Each check, out of combat and in combat:", #runs, Util.Plural(#runs, "run"))
    for _, line in ipairs(ns.Report.MatrixLines(ns.Report.Matrix(runs), filter)) do out.Print(line) end
    for _, line in ipairs(ns.Report.RunLines(runs[#runs])) do out.Print(line) end
end

COMMANDS.runs = function()
    if not Ready() then return end
    if #ns.db.runs == 0 then
        out.Print("no runs yet.")
        return
    end
    for _, run in ipairs(ns.db.runs) do
        for _, line in ipairs(ns.Report.RunLines(run)) do out.Print(line) end
    end
end

COMMANDS.chat = function(rest)
    if not Ready() then return end
    local word = Util.Trim(rest):lower()
    if word == "on" or word == "off" then ns.db.settings.chat = word == "on" end
    out.Printf("runs %s chat lines to the group.", ns.db.settings.chat and "send" or "do not send")
end

COMMANDS.clear = function()
    if not Ready() then return end
    ns.db.runs = {}
    out.Print("every run forgotten.")
end

COMMANDS.test = function()
    ns.Tests.Run()
end

local _, slashTaken = Console.Slash({
    key = "MFDPROBE", slash = { "/mfdp", "/mfdprobe" }, out = out, help = HELP, commands = COMMANDS,
})

-- The one thing said at login, and only once.
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    out.Printf("v%s loaded, %d %s kept. /mfdp help lists commands.", VERSION,
        ns.db and #ns.db.runs or 0, Util.Plural(ns.db and #ns.db.runs or 0, "run"))
    if slashTaken then out.Print("|cffff9900another addon already holds /mfdp.|r") end
end)
