local addonName, ns = ...

ns.Minimap = ns.Minimap or {}
local M = ns.Minimap

--[[
The minimap launcher. LibICCore does the LibDataBroker and LibDBIcon work and
checks both are there first, which is the house rule for every optional
dependency.
]]

local ICON = "Interface\\AddOns\\JamminWithJam\\JamminWithJam.tga"

function M.Init()
    M.obj, M.icon = ns.Core:MinimapButton(ns, {
        name = "JamminWithJam",
        icon = ICON,
        onClick = function(button)
            if button == "MiddleButton" then
                ns.Tests.Run()
            else
                ns.UI.Toggle()
            end
        end,
        tooltip = function(tt)
            tt:AddLine("JamminWithJam " .. ns.VERSION)
            if not ns.Enabled() then tt:AddLine("|cffff4444DISABLED|r") end

            tt:AddLine(string.format("%d sounds, channel %s",
                #ns.Sounds.List(), ns.db.settings.channel))

            local run = ns.db.lastTestRun
            if run then
                tt:AddLine(string.format("tests: |cff44ff44%d passed|r, %s%d failed|r",
                    run.passed or 0,
                    (run.failed or 0) > 0 and "|cffff4444" or "|cff44ff44", run.failed or 0))
            end

            tt:AddLine(" ")
            tt:AddLine("|cff888888Left click: open the soundboard|r")
            tt:AddLine("|cff888888Middle click: run the tests|r")
        end,
    })
end
