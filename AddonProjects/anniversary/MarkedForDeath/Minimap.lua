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
        OnClick = function(anchor, button)
            -- Left click opens a menu of everything. Three hidden click
            -- targets were fine once you knew them and undiscoverable before
            -- that; the shortcuts stay for anyone who did learn them.
            if button == "RightButton" then
                MFD.UI.Rules:Toggle()
            elseif button == "MiddleButton" then
                MFD.UI.Assignments:Toggle()
            elseif IsShiftKeyDown and IsShiftKeyDown() then
                M.OpenMenu(anchor)
            else
                MFD.UI.Main:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Marked For Death")

            if not MFD.IsEnabled() then
                tt:AddLine("|cffff4444ADDON DISABLED|r")
            elseif not MFD.db.settings.isMarkingEnabled then
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
            tt:AddLine("|cff888888Left click: open the window|r")
            tt:AddLine("|cff888888Right click: straight to rules|r")
            tt:AddLine("|cff888888Middle click: assignment panel|r")
            tt:AddLine("|cff888888Shift click: quick menu|r")
        end,
    })

    MFD.db.settings.minimap = MFD.db.settings.minimap or {}
    Icon:Register("MarkedForDeath", obj, MFD.db.settings.minimap)

    M.obj = obj
    M.icon = Icon
end

-- The menu the minimap button opens. UIDropDownMenu needs a global frame name,
-- the documented exception to the one-global rule.
local menu

-- Entries are built fresh on each open so the quick toggles show their real
-- current state rather than whatever they were when the menu was created.
local function menuEntries()
    local settings = MFD.db.settings
    return {
        { title = true, text = "Marked For Death" },

        { text = "Open Marked For Death", open = function() MFD.UI.Main:Toggle() end },

        {
            text = "Addon enabled",
            checked = function() return MFD.IsEnabled() end,
            toggle = function() MFD.SetEnabled(not MFD.IsEnabled()) end,
        },

        { separator = true },

        -- The two floating heads-up panels. Everything else is a tab in the
        -- main window now, so listing tabs here would just be a worse copy of
        -- the tab strip.
        { text = "Assignment panel", open = function() MFD.UI.Assignments:Toggle() end },
        { text = "Buff board", open = function() MFD.UI.BuffBoard:Toggle() end },

        { separator = true },

        {
            text = "Place icons automatically",
            checked = function() return settings.isMarkingEnabled end,
            toggle = function() settings.isMarkingEnabled = not settings.isMarkingEnabled end,
        },
        {
            text = "Announce on the pull",
            checked = function() return settings.isAnnounceEnabled end,
            toggle = function() settings.isAnnounceEnabled = not settings.isAnnounceEnabled end,
        },

        -- The mid-pull actions, same definitions the panel buttons and the
        -- keybindings use. Reachable from the minimap too, because during a
        -- fight the fastest thing on screen is whatever is already under the
        -- cursor.
        {
            text = "Death calls: " .. MFD.Encounters.OVERRIDE_LABELS[settings.deaths.override],
            open = function() MFD.Actions.Run("deaths") end,
        },
        {
            text = "Announce the assignments",
            open = function() MFD.Actions.Run("announce") end,
        },
        {
            text = "Clear every icon",
            open = function() MFD.Actions.Run("clear") end,
        },

        { separator = true },

        { text = "Settings", open = function() MFD.UI.Settings:Toggle() end },
    }
end

-- Left click opens the one window; right click jumps to the rules tab; middle
-- click toggles the assignment panel. The menu is on shift-click for anyone
-- who wants the quick toggles without opening anything.

function M.OpenMenu(anchor)
    if not menu then
        menu = CreateFrame("Frame", "MarkedForDeathMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(menu, function()
        for _, entry in ipairs(menuEntries()) do
            local info = UIDropDownMenu_CreateInfo()

            if entry.title then
                info.text = entry.text
                info.isTitle = true
                info.notCheckable = true
            elseif entry.separator then
                info.text = ""
                info.disabled = true
                info.notCheckable = true
            elseif entry.toggle then
                info.text = entry.text
                info.checked = entry.checked()
                info.keepShownOnClick = true
                info.func = function()
                    entry.toggle()
                    if MFD.UI.Settings and MFD.UI.Settings.Refresh then
                        MFD.UI.Settings:Refresh()
                    end
                end
            else
                info.text = entry.text
                info.notCheckable = true
                info.func = function()
                    entry.open()
                    CloseDropDownMenus()
                end
            end

            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

-- Shows or hides the button without toggling, for the settings checkbox.
function M:SetShown(isShown)
    MFD.db.settings.minimap.hide = not isShown
    if not M.icon then
        return
    end
    if isShown then
        M.icon:Show("MarkedForDeath")
    else
        M.icon:Hide("MarkedForDeath")
    end
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
