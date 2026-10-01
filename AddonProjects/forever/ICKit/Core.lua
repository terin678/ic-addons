local addonName, ns = ...

--[[
ICKit: the kit under the Impulse Control addons for WoW Forever.

It is built bottom-up, one layer at a time, and a layer is added only when an addon needs
it (Docs/forever/VISION.md has the rules and the order):

    layer 0   LibICUtil-1.0     pure helpers                      here now
              LibICTest-1.0     the case runner                   here now
    layer 1   LibICEnv-1.0      what this client offers, probed   next
              LibICStore-1.0    saved variables                   next
              LibICConsole-1.0  printing and slash commands       next
              LibICTheme-1.0    the theme registry
    layer 2   LibICWidgets-1.0  themed frames

This file is the addon around the libraries: its version, its one command and its own
cases. Until LibICConsole exists the command is registered by hand, which is also the
first thing this client is asked to prove it supports.
]]

local VERSION = "0.1.0"

local Util = LibStub("LibICUtil-1.0")
local Test = LibStub("LibICTest-1.0")

local PREFIX = "|cffdf9c33ICKit|r: "

local function Print(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(PREFIX .. tostring(msg))
    else
        print(PREFIX .. tostring(msg))
    end
end

ns.VERSION = VERSION
ns.Util = Util
ns.Print = Print
ns.Tests = Test.New({ print = Print })

-- Pure. GetBuildInfo's returns as one phrase: "1.60.1 (70124), interface 16001".
function ns.DescribeBuild(version, build, _, interface)
    return string.format("%s (%s), interface %s",
        tostring(version or "?"), tostring(build or "?"), tostring(interface or "?"))
end

SLASH_ICKIT1 = "/ickit"
SlashCmdList["ICKIT"] = function(input)
    local cmd = Util.Trim(input):lower()
    if cmd == "test" then
        ns.Tests.Run()
        return
    end
    Print("v" .. VERSION .. " on " .. ns.DescribeBuild(GetBuildInfo()))
    Print("/ickit test runs the built-in checks.")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    Print("v" .. VERSION .. " loaded. /ickit shows the client build, /ickit test runs the checks.")
end)
