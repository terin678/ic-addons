-- AHTab.lua - Adds a "Watcher" tab to the legacy auction house frame that docks the main window
local addonName = "MalexisAuctionWatcher"
local MAWAHTab = {}

local tab = nil
local hooked = false

local function Undock()
    if _G.MalexisAuctionWatcherUI then
        _G.MalexisAuctionWatcherUI:Undock()
    end
end

local function Dock()
    if _G.MalexisAuctionWatcherUI then
        _G.MalexisAuctionWatcherUI:Dock(AuctionFrame)
    end
end

function MAWAHTab.IsOurTab(button)
    return tab ~= nil and button == tab
end

-- Off by default: the current implementation docks the floating window over the AH frame
-- rather than rendering inside it like Blizzard's tabs. Kept for a future in-frame version.
function MAWAHTab.IsEnabled()
    local s = MalexisAuctionWatcherDB and MalexisAuctionWatcherDB.settings
    return s and s.ahTab == true
end

function MAWAHTab.Create()
    if not MAWAHTab.IsEnabled() then
        return
    end
    if tab or not AuctionFrame or not AuctionFrame.numTabs then
        return
    end

    local index = AuctionFrame.numTabs + 1
    tab = CreateFrame("Button", "AuctionFrameTab" .. index, AuctionFrame, "AuctionTabTemplate")
    tab:SetID(index)
    tab:SetText("Watcher")
    tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (index - 1)], "RIGHT", -15, 0)
    PanelTemplates_SetNumTabs(AuctionFrame, index)
    PanelTemplates_EnableTab(AuctionFrame, index)
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tab, 0, nil, 36)
    end

    if not hooked then
        hooked = true
        -- Blizzard hides its own panels for any tab index above 3; we show ours when it is our tab
        hooksecurefunc("AuctionFrameTab_OnClick", function(button)
            if button == tab then
                Dock()
            else
                Undock()
            end
        end)
        AuctionFrame:HookScript("OnHide", Undock)
    end
end

-- Select our tab programmatically (used by /maw show when the AH is open)
function MAWAHTab.Select()
    if MAWAHTab.IsEnabled() and tab and AuctionFrame and AuctionFrame:IsShown() then
        tab:Click()
        return true
    end
    return false
end

_G.MalexisAuctionWatcherAHTab = MAWAHTab
