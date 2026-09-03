-- Minimap button. Uses the same LibDBIcon pattern as CutMaster.
local MFD = _G.MarkedForDeath or {}

MFD.Minimap = MFD.Minimap or {}
local M = MFD.Minimap

-- The skull raid target, which is both on-theme and already shipped by the
-- client, so the addon needs no texture file of its own.
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

function M.Init()
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local Icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDB or not Icon then
        return
    end

    local obj = LDB:NewDataObject("MarkedForDeath", {
        type = "launcher",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                MFD.UI.Rules:Toggle()
            elseif button == "MiddleButton" then
                MFD.UI.Assignments:Toggle()
            else
                MFD.UI.Config:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Marked For Death")

            if not MFD.db.settings.isMarkingEnabled then
                tt:AddLine("|cffff4444MARKING DISABLED|r")
            end

            local count = 0
            for _ in pairs(MFD.Rules.Active()) do
                count = count + 1
            end

            tt:AddLine(string.format("|cffffffff%d|r active rules in %s",
                count, tostring(MFD.Rules.currentInstanceKey or "no known zone")))

            local authority = MFD.Comms.authority
            if authority then
                tt:AddLine(string.format("marker: |cffffffff%s|r (%s)",
                    authority, MFD.Comms.authorityMode))
            else
                tt:AddLine("|cffff4444nobody can place icons|r")
            end

            -- Surfacing this on the tooltip matters: nameplates being off is
            -- the single most common reason marking silently does nothing.
            local cvarsOk, cvarMessage = MFD.Marker:CheckCvars()
            if not cvarsOk then
                tt:AddLine("|cffff4444" .. cvarMessage .. "|r")
            end

            tt:AddLine(" ")
            tt:AddLine("|cff888888Left click: seats and settings|r")
            tt:AddLine("|cff888888Right click: rules and mob search|r")
            tt:AddLine("|cff888888Middle click: assignment panel|r")
        end,
    })

    MFD.db.settings.minimap = MFD.db.settings.minimap or {}
    Icon:Register("MarkedForDeath", obj, MFD.db.settings.minimap)

    M.obj = obj
    M.icon = Icon
end

-- Shows or hides the button and remembers the choice.
function M:Toggle()
    if not M.icon then
        MFD.Error("minimap library not loaded")
        return
    end

    MFD.db.settings.minimap.hide = not MFD.db.settings.minimap.hide

    if MFD.db.settings.minimap.hide then
        M.icon:Hide("MarkedForDeath")
        MFD.Print("minimap button hidden. /mfd minimap to bring it back.")
    else
        M.icon:Show("MarkedForDeath")
        MFD.Print("minimap button shown")
    end
end

MFD.RegisterInit(function()
    local ok, err = pcall(M.Init)
    if not ok then
        MFD.Error("minimap button failed to load: " .. tostring(err))
    end
end)

_G.MarkedForDeath = MFD
