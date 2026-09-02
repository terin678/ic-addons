-- Minimap.lua - Minimap button that toggles the main window
local addonName = "MalexisAuctionWatcher"
local MAWMinimap = {}

local BUTTON_RADIUS = 80  -- distance from minimap center
local DEFAULT_ANGLE = 220 -- degrees, lower-left of the minimap

local button = nil

local function GetSettings()
    if not MalexisAuctionWatcherDB then
        return nil
    end
    MalexisAuctionWatcherDB.settings = MalexisAuctionWatcherDB.settings or {}
    local s = MalexisAuctionWatcherDB.settings
    if s.minimapAngle == nil then
        s.minimapAngle = DEFAULT_ANGLE
    end
    if s.minimapHidden == nil then
        s.minimapHidden = false
    end
    return s
end

-- Place the button on the minimap rim at the saved angle
local function UpdatePosition()
    if not button then return end
    local s = GetSettings()
    local angle = math.rad((s and s.minimapAngle) or DEFAULT_ANGLE)
    local x = math.cos(angle) * BUTTON_RADIUS
    local y = math.sin(angle) * BUTTON_RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging, follow the cursor around the rim and save the angle
local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    local s = GetSettings()
    if s then
        s.minimapAngle = angle
    end
    UpdatePosition()
end

function MAWMinimap:Create()
    if button then return button end

    button = CreateFrame("Button", "MalexisAuctionWatcherMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\Minimap\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- Icon
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexture("Interface\Icons\INV_Misc_Coin_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    -- Standard round border used by most minimap buttons
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\Minimap\MiniMap-TrackingBorder")
    button.border = border

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            if _G.MalexisAuctionWatcherUI then
                _G.MalexisAuctionWatcherUI:Toggle()
            end
        elseif mouseButton == "RightButton" then
            local MAW = _G.MalexisAuctionWatcher
            if MAW then
                if MAW:IsScanning() then
                    MAW:CancelScan("stopped by user")
                else
                    MAW:ScanAuctionHouse()
                end
            end
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdatePosition()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Malexis Auction Watcher")
        GameTooltip:AddLine("Left-click: toggle window", 1, 1, 1)
        local MAW = _G.MalexisAuctionWatcher
        if MAW and MAW:IsScanning() then
            GameTooltip:AddLine("Right-click: cancel scan (" .. MAW:ScanStatusText() .. ")", 1, 1, 1)
        else
            GameTooltip:AddLine("Right-click: scan auction house", 1, 1, 1)
        end
        GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition()

    local s = GetSettings()
    if s and s.minimapHidden then
        button:Hide()
    end

    return button
end

function MAWMinimap:Toggle()
    if not button then
        self:Create()
    end
    local s = GetSettings()
    if button:IsShown() then
        button:Hide()
        if s then s.minimapHidden = true end
        print(addonName .. ": Minimap button hidden. Use /maw minimap to show it again.")
    else
        button:Show()
        if s then s.minimapHidden = false end
    end
end

_G.MalexisAuctionWatcherMinimap = MAWMinimap
