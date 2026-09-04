-- The one window. Seats, rules, the raid check grid and settings live here as
-- tabs rather than as four separate windows you have to close and reopen.
--
-- Two things stay floating on purpose: the assignment panel and the buff
-- board. Those are glanceable during a pull, not things you sit and adjust,
-- and putting them in here would mean opening a config window mid-fight.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Main = MFD.UI.Main or {}
local Main = MFD.UI.Main

-- Sized for the widest panel, the raid check grid, so switching tabs never
-- resizes the window under the cursor.
local WIDTH, HEIGHT = 880, 600     -- pixels
local TAB_HEIGHT = 22              -- pixels
local CONTENT_TOP = 54             -- pixels below the window top

-- Declared up front so the tabs are always in this order, rather than in
-- whatever order the panels happened to be opened in.
local TABS = {
    { key = "seats",  label = "Seats",      owner = function() return MFD.UI.Config end },
    { key = "rules",  label = "Rules",      owner = function() return MFD.UI.Rules end },
    { key = "check",  label = "Raid check", owner = function() return MFD.UI.RaidCheck end },
    { key = "settings", label = "Settings", owner = function() return MFD.UI.Settings end },
}

local frame
local containers = {}
local buttons = {}
local currentKey

local function savePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    MFD.charDb.windows.main = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition()
    local saved = MFD.charDb.windows.main
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

local function paintTabs()
    for _, tab in ipairs(TABS) do
        local button = buttons[tab.key]
        if button then
            if tab.key == currentKey then
                button:SetNormalFontObject(GameFontHighlight)
                button:LockHighlight()
            else
                button:SetNormalFontObject(GameFontDisable)
                button:UnlockHighlight()
            end
        end
    end
end

local function build()
    frame = CreateFrame("Frame", "MarkedForDeathFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetFrameStrata("DIALOG")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.title:SetText("Marked For Death")

    local previous
    for _, tab in ipairs(TABS) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(100, TAB_HEIGHT)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -26)
        end
        button:SetText(tab.label)
        button:SetScript("OnClick", function()
            Main:Select(tab.key)
        end)
        buttons[tab.key] = button
        previous = button
    end

    for _, tab in ipairs(TABS) do
        local container = CreateFrame("Frame", nil, frame)
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -CONTENT_TOP)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
        container:Hide()
        containers[tab.key] = container
    end

    restorePosition()
    tinsert(UISpecialFrames, "MarkedForDeathFrame")
end

-- Shows one tab, building its panel the first time it is asked for. Each panel
-- exposes BuildInto(container) and Refresh(); nothing else is assumed.
function Main:Select(key)
    if not frame then
        build()
    end

    for _, tab in ipairs(TABS) do
        local container = containers[tab.key]
        if tab.key == key then
            local panel = tab.owner()
            if panel and not container.isBuilt then
                container.isBuilt = true
                local ok, err = pcall(panel.BuildInto, panel, container)
                if not ok then
                    container.isBuilt = false
                    MFD.Error("could not open the " .. tab.label .. " tab: " .. tostring(err))
                end
            end
            container:Show()
            if panel and panel.Refresh then
                pcall(panel.Refresh, panel)
            end
        else
            container:Hide()
        end
    end

    currentKey = key
    paintTabs()
end

-- Opens the window on a tab, or closes it if that tab is already showing.
function Main:Toggle(key)
    key = key or currentKey or TABS[1].key

    if frame and frame:IsShown() and currentKey == key then
        frame:Hide()
        return
    end

    Main:Select(key)
    frame:Show()
end

-- Shows the window without changing which tab is selected.
function Main:Open()
    if not frame then
        build()
        Main:Select(currentKey or TABS[1].key)
    end
    frame:Show()
end

function Main:IsShown()
    return frame and frame:IsShown()
end

-- Repaints the visible tab, for callers that change data underneath it.
function Main:Refresh()
    if not frame or not frame:IsShown() or not currentKey then
        return
    end
    for _, tab in ipairs(TABS) do
        if tab.key == currentKey then
            local panel = tab.owner()
            if panel and panel.Refresh then
                pcall(panel.Refresh, panel)
            end
        end
    end
end

_G.MarkedForDeath = MFD
