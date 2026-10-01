local addonName, ns = ...

--[[
RenderTuner: the client's rendering knobs in one place. Upscaling presets, a control for
every graphics console variable, and a way to compare the saved settings with the ones
being tried.

The client has no DLSS, XeSS or FSR 2 and up. What it has is a render scale with an
FSR 1.0 upscale and a sharpening pass, image and multisample anti-aliasing, low latency
modes, HDR and colour correction, all driven by console variables. This addon sets those
and nothing else.

This build is step T0: it asks the client what it has, and builds nothing on the answers
yet.

    Probe.lua   the console variables the client lists, and whether an addon can capture
                the screen into a texture                               (LibICEnv)
    Core.lua    this file: saved tables, commands, login                (LibICStore, LibICConsole)
    Tests.lua   the cases                                               (LibICTest)
]]

local VERSION = "0.0.1"

local Test = LibStub("LibICTest-1.0")
local Env = LibStub("LibICEnv-1.0")
local Store = LibStub("LibICStore-1.0")
local Console = LibStub("LibICConsole-1.0")

local out = Console.New("RenderTuner", {
    debug = function() return ns.db ~= nil and ns.db.settings.debug == true end,
})

ns.VERSION = VERSION
ns.Print, ns.Printf, ns.Debug = out.Print, out.Printf, out.Debug
ns.Tests = Test.New({ print = out.Print })

--------------------------------------------------------------------------------
-- Pure: what it says at login
--------------------------------------------------------------------------------

function ns.LoadLines(version, probed)
    if probed then
        return { string.format("v%s loaded. The client has been probed; /tuner help lists commands.", version) }
    end
    return { string.format("v%s loaded. This build only asks the client questions: /tuner probe first.", version) }
end

--------------------------------------------------------------------------------
-- Saved tables
--------------------------------------------------------------------------------

Store.Register(addonName, {
    account = "RenderTunerDB",
    character = "RenderTunerCharDB",
    schema = 1,
    charSchema = 1,
    defaults = { settings = { debug = false } },
    charDefaults = {},
    onReady = Env.Wrap("RenderTuner saved variables", function(db, cdb, info)
        ns.db, ns.cdb, ns.loadInfo = db, cdb, info
    end),
})

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local HELP = {
    { "", "what has been asked so far" },
    { "probe", "list every console variable the client has, and save the answers" },
    { "capture report | photo", "try one way of capturing the screen into a picture" },
    { "capture view split | full", "show the capture on the left half, or whole and small" },
    { "capture clear", "take the capture off the screen" },
    { "test", "run the built-in checks" },
    { "help", "this list" },
}

local COMMANDS = {}

local function Ready()
    if ns.db then return true end
    out.Print("the saved settings are not in hand yet.")
    return false
end

COMMANDS[""] = function()
    if not Ready() then return end
    if not ns.db.probe then
        out.Print("nothing asked yet. /tuner probe lists the client's console variables.")
        return
    end
    for _, line in ipairs(ns.Probe.Summary(ns.db.probe)) do out.Print(line) end
    for _, line in ipairs(ns.Probe.CaptureLines(ns.db.capture)) do out.Print(line) end
end

COMMANDS.probe = function()
    if not Ready() then return end
    ns.db.probe = ns.Probe.Run()
    for _, line in ipairs(ns.Probe.Summary(ns.db.probe)) do out.Print(line) end
    out.Print("saved. /reload writes it to disk.")
end

COMMANDS.capture = function(rest)
    if not Ready() then return end
    local word, arg = Console.Parse(rest)
    arg = arg:lower()
    if word == "report" or word == "photo" then
        ns.db.capture = ns.db.capture or {}
        ns.Probe.Capture(word, ns.db.capture, out.Print)
    elseif word == "view" and (arg == "split" or arg == "full") then
        ns.Probe.CaptureView(arg)
        out.Printf("the capture is shown %s.", arg == "split" and "on the left half of the screen" or "whole, at half size")
    elseif word == "clear" then
        ns.Probe.CaptureClear()
        out.Print("the capture is off the screen.")
    else
        out.Print("capture report, capture photo, capture view split, capture view full, or capture clear.")
    end
end

COMMANDS.test = function()
    ns.Tests.Run()
end

local _, slashTaken = Console.Slash({
    key = "RENDERTUNER", slash = { "/tuner", "/rendertuner" }, out = out, help = HELP, commands = COMMANDS,
})

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", Env.Wrap("RenderTuner events", function()
    for _, line in ipairs(ns.LoadLines(VERSION, ns.db ~= nil and ns.db.probe ~= nil)) do out.Print(line) end
    if slashTaken then
        out.Print("|cffff9900another addon already registered the RENDERTUNER slash key.|r One of you owns /tuner now.")
    end
end))
