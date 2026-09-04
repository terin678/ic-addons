-- The one window. Roles, rules, the raid check grid and settings live here as
-- tabs rather than as four separate windows you have to close and reopen.
--
-- The assignment panel and the buff board are tabs here as well as floating
-- windows. They are the two you want visible during a pull without the rest of
-- the window in the way, so both homes exist and either can be used.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.Main = MFD.UI.Main or {}
local Main = MFD.UI.Main

-- Sized for the widest panel, the raid check grid, so switching tabs never
-- resizes the window under the cursor. The measurements live in UI.lua with
-- the rest of the shared ones.
--
-- Pixels below the window top: clear of the library's title bar and the tab
-- strip beneath it.
local CONTENT_TOP = 78

-- Declared up front so the tabs are always in this order, rather than in
-- whatever order the panels happened to be opened in.
local TABS = {
    { key = "roles",  label = "Roles",      owner = function() return MFD.UI.Config end },
    { key = "rules",  label = "Rules",      owner = function() return MFD.UI.Rules end },
    { key = "check",  label = "Raid check", owner = function() return MFD.UI.RaidCheck end },
    { key = "buffs",  label = "Buffs",      owner = function() return MFD.UI.BuffBoard end },
    { key = "assign", label = "Assignments", owner = function() return MFD.UI.Assignments end },
    { key = "deaths", label = "Deaths",   owner = function() return MFD.UI.Deaths end },
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

-- Paints the master switch so its current state is obvious at a glance.
function Main:PaintMaster()
    if not frame or not frame.master then
        return
    end

    if MFD.IsEnabled() then
        frame.master:SetText("Disable")
        frame.title:SetText("Marked For Death")
    else
        frame.master:SetText("Enable")
        frame.title:SetText("Marked For Death  |cffff4444(disabled)|r")
    end

    -- The library paints a button's own state rather than a colour code in the
    -- label, which is the rule for a toggle.
    if frame.master.SetActive then
        frame.master:SetActive(not MFD.IsEnabled())
    end
end

-- The library's tab buttons carry their own live state, so this only has to
-- say which one is live.
local function paintTabs()
    for _, tab in ipairs(TABS) do
        local button = buttons[tab.key]
        if button and button.SetActive then
            button:SetActive(tab.key == currentKey)
        end
    end
end

local function build()
    local UI = MFD.UI

    -- The window, the tab strip and every button on them come from the shared
    -- library, so this addon wears the guild palette by construction rather
    -- than by matching colours by hand at each call site.
    frame = UI.Window("MarkedForDeathFrame", {
        width = UI.WIDTH,
        height = UI.HEIGHT,
        title = "Marked For Death",
        status = false,
        scalable = true,
        onScaleChanged = function(_, scale)
            MFD.charDb.windows.main = MFD.charDb.windows.main or {}
            MFD.charDb.windows.main.scale = scale
        end,
    })

    -- Guarded like any optional dependency: an older ICLibs bundled by another
    -- addon can win the LibStub race, and that should cost the grip rather
    -- than the whole window.
    local saved = MFD.charDb.windows.main
    if frame.SetWindowScale and saved and saved.scale then
        frame:SetWindowScale(saved.scale, true)
    end

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    local names = {}
    for index, tab in ipairs(TABS) do
        names[index] = tab.label
    end

    frame.tabs = UI.TabStrip(frame, {
        names = names,
        top = -48,
        left = UI.PAGE_INSET,
        width = 96,
        height = UI.TAB_HEIGHT,
        onSelect = function(_, index)
            Main:Select(TABS[index].key)
        end,
    })
    for index, tab in ipairs(TABS) do
        buttons[tab.key] = frame.tabs.buttons[index]
    end

    -- The panic button. Sits beside the tabs rather than inside Settings,
    -- because the moment you want it you do not want to go looking for it.
    frame.master = UI.Button(frame, "Disable", 110, UI.TAB_HEIGHT, { kind = "danger" })
    frame.master:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -48)
    frame.master:SetScript("OnClick", function()
        MFD.SetEnabled(not MFD.IsEnabled())
        Main:PaintMaster()
    end)
    UI.Tooltip(frame.master, function()
        GameTooltip:AddLine("Disable everything", 1, 1, 1)
        GameTooltip:AddLine("Stops marking, announcements and warnings without unloading the "
            .. "addon or reloading. Your rules and roles are untouched.", 0.8, 0.8, 0.8, true)
    end)

    for _, tab in ipairs(TABS) do
        local container = CreateFrame("Frame", nil, frame)
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAGE_INSET, -CONTENT_TOP)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAGE_INSET, UI.PAGE_INSET)
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
    Main:PaintMaster()
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
