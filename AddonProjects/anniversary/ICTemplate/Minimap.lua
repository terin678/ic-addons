local addonName, ns = ...

ns.Minimap = ns.Minimap or {}
local M = ns.Minimap

--[[
The minimap launcher. LibICCore does the LibDataBroker and LibDBIcon work and checks
both are there first, which is the house rule for every optional dependency.

The right click is here for the same reason the key binding is: it is a hardware
event, so it is one of the few places a protected send is allowed.
]]

local ICON = "Interface\\AddOns\\ICTemplate\\ICTemplate.tga"

function M.Init()
    M.obj, M.icon = ns.Core:MinimapButton(ns, {
        name = "ICTemplate",
        icon = ICON,
        onClick = function(button)
            if button == "RightButton" then
                local ok, info = ns.Pulse.Fire(true)
                if not ok then ns.Print("pulse skipped: " .. tostring(info)) end
            elseif button == "MiddleButton" then
                ns.Tests.Run()
            else
                ns.UI.Toggle()
            end
        end,
        tooltip = function(tt)
            local s = ns.db.settings.pulse
            tt:AddLine("ICTemplate " .. ns.VERSION)
            if not ns.Enabled() then tt:AddLine("|cffff4444DISABLED|r") end

            local blocked = ns.Pulse.BlockReason(ns.Pulse.ReadState())
            tt:AddLine(string.format("pulse %s, every %ds",
                s.enabled and "|cff44ff44on|r" or "|cffff4444off|r", s.intervalSec))
            if ns.Pulse.pending then
                tt:AddLine("|cffffcc00A pulse is ready. Right click to send.|r")
            elseif blocked then
                tt:AddLine("|cffffcc00will not send: " .. blocked .. "|r")
            end

            if ns.Demos then
                tt:AddLine(string.format("|cffffffff%d|r demos", #ns.Demos.list))
            end
            local run = ns.db.lastTestRun
            if run then
                tt:AddLine(string.format("tests: |cff44ff44%d passed|r, %s%d failed|r",
                    run.passed or 0,
                    (run.failed or 0) > 0 and "|cffff4444" or "|cff44ff44", run.failed or 0))
            end

            tt:AddLine(" ")
            tt:AddLine("|cff888888Left click: open the window|r")
            tt:AddLine("|cff888888Right click: send the pulse|r")
            tt:AddLine("|cff888888Middle click: run the tests|r")
        end,
    })
end
