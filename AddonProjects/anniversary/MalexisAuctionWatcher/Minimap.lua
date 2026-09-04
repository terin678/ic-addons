-- Minimap.lua - the minimap launcher, on LibDBIcon through LibICCore
local MAW = _G.MalexisAuctionWatcher or {}

MAW.Minimap = MAW.Minimap or {}
local M = MAW.Minimap

local NAME = "MalexisAuctionWatcher"
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

function M.Init()
    M.obj, M.icon = MAW.Core:MinimapButton(MAW, {
        name = NAME,
        icon = ICON,
        onClick = function(button)
            if button == "RightButton" then
                if MAW:IsScanning() then
                    MAW:CancelScan("stopped by user")
                else
                    MAW:ScanAuctionHouse()
                end
            elseif button == "LeftButton" then
                if MalexisAuctionWatcherUI then MalexisAuctionWatcherUI:Toggle() end
            end
        end,
        tooltip = function(tt)
            tt:AddLine("Malexis Auction Watcher " .. MAW.VERSION)
            tt:AddLine("Left-click: toggle window", 1, 1, 1)
            if MAW:IsScanning() then
                tt:AddLine("Right-click: cancel scan (" .. MAW:ScanStatusText() .. ")", 1, 1, 1)
            else
                tt:AddLine("Right-click: scan auction house", 1, 1, 1)
            end
            tt:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        end,
    })
end

-- /maw minimap. The hide flag lives in settings.minimap, which is LibDBIcon's own table.
function M.Toggle()
    if not M.icon then
        MAW.Print("the minimap button needs LibDBIcon, which ICLibs provides.")
        return
    end
    local s = MAW.db.settings.minimap
    s.hide = not s.hide
    if s.hide then
        M.icon:Hide(NAME)
        MAW.Print("Minimap button hidden. Use /maw minimap to show it again.")
    else
        M.icon:Show(NAME)
    end
end

_G.MalexisAuctionWatcher = MAW
