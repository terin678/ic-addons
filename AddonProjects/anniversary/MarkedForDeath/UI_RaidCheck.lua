-- The raid check surfaces: the full grid here, the quick buff board below it.
-- Both paint from RaidCheck.rows and never read the client directly, so the
-- data they show is exactly what /mfd missing and the callout would report.
local MFD = _G.MarkedForDeath or {}

MFD.UI = MFD.UI or {}
MFD.UI.RaidCheck = MFD.UI.RaidCheck or {}
local Grid = MFD.UI.RaidCheck
local RC = MFD.RaidCheck

local ROW_HEIGHT = 18     -- pixels
local MAX_ROWS = 26       -- a full raid plus one
local GRID_WIDTH = 860    -- pixels

-- Column layout: key, header label, x offset from the row's left edge, width.
local COLUMNS = {
    { key = "NAME",      label = "Name",      x = 0,   w = 110 },
    { key = "FOOD",      label = "Food",      x = 112, w = 44 },
    { key = "FLASK",     label = "Flask",     x = 158, w = 44 },
    { key = "BATTLE",    label = "Battle",    x = 204, w = 44 },
    { key = "GUARDIAN",  label = "Guard",     x = 250, w = 44 },
    { key = "WEAPON",    label = "Weapon",    x = 296, w = 44 },
    { key = "AI",        label = "Int",       x = 342, w = 40 },
    { key = "MOTW",      label = "MotW",      x = 384, w = 40 },
    { key = "FORT",      label = "Fort",      x = 426, w = 40 },
    { key = "SP",        label = "SProt",     x = 468, w = 40 },
    { key = "BLESSINGS", label = "Blessings", x = 510, w = 120 },
    { key = "DUR",       label = "Dur",       x = 632, w = 40 },
    { key = "SPEC",      label = "Spec",      x = 674, w = 80 },
    { key = "VER",       label = "Ver",       x = 756, w = 50 },
}

local GREEN, RED, GREY, AMBER = "|cff66ff66", "|cffff4444", "|cff999999", "|cffffcc66"

-- Formats a yes/no/unknown cell. isMissing decides whether an absence is a
-- problem (red) or merely an absence (grey).
local function presence(value, isMissing)
    if value == nil then
        return GREY .. "?|r"
    end
    if value == false then
        return (isMissing and RED or GREY) .. "no|r"
    end
    return GREEN .. "yes|r"
end

-- Returns the text for one cell of one player's entry.
local function cellText(column, entry)
    local state, missingSet = entry.row.state, entry.missingSet
    local hasFlask = state.flask ~= nil

    if column == "FOOD" then
        return presence(state.food ~= nil, missingSet.FOOD)
    elseif column == "FLASK" then
        return presence(hasFlask, missingSet.FLASK)
    elseif column == "BATTLE" then
        if hasFlask and state.battle == nil then
            return GREEN .. "flask|r"
        end
        return presence(state.battle ~= nil, missingSet.BATTLE)
    elseif column == "GUARDIAN" then
        if hasFlask and state.guardian == nil then
            return GREEN .. "flask|r"
        end
        return presence(state.guardian ~= nil, missingSet.GUARDIAN)
    elseif column == "WEAPON" then
        return presence(state.weapon, missingSet.WEAPON)
    elseif column == "AI" or column == "MOTW" or column == "FORT" or column == "SP" then
        return presence(state[column], missingSet[column])
    elseif column == "BLESSINGS" then
        if #state.blessings == 0 then
            return GREY .. "none|r"
        end
        return table.concat(state.blessings, " ")
    elseif column == "DUR" then
        local d = state.durability
        if d == nil then
            return GREY .. "?|r"
        end
        -- Anything broken is red regardless of the percent: a broken weapon at
        -- 70% overall matters more than 40% with everything still working.
        if (state.brokenItems or 0) > 0 then
            return RED .. d .. "% !" .. state.brokenItems .. "|r"
        end
        local color = (d < 30 and RED) or (d < 60 and AMBER) or ""
        return color .. d .. "%" .. (color ~= "" and "|r" or "")
    elseif column == "SPEC" then
        return state.spec or (GREY .. "?|r")
    elseif column == "VER" then
        if not state.version then
            return GREY .. "?|r"
        end
        if state.version ~= MFD.VERSION then
            return RED .. state.version .. "|r"
        end
        return state.version
    end
    return ""
end

local frame
local rows = {}
local eventFrame

local function buildRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true
    row.cells = {}

    for _, column in ipairs(COLUMNS) do
        if column.key == "NAME" then
            -- The name is a button: click to whisper that player their list.
            local button = CreateFrame("Button", nil, row)
            button:SetSize(column.w, ROW_HEIGHT)
            button:SetPoint("LEFT", row, "LEFT", column.x, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetAllPoints()
            button.text:SetJustifyH("LEFT")
            button:SetScript("OnClick", function()
                if row.entry then
                    RC:Whisper(row.entry.name)
                end
            end)
            row.cells.NAME = button
        else
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", row, "LEFT", column.x, 0)
            text:SetWidth(column.w)
            text:SetJustifyH("LEFT")
            row.cells[column.key] = text
        end
    end
end

local function missingSetFor(entry)
    local set = {}
    for _, m in ipairs(entry.missing or {}) do
        set[m.column] = true
    end
    return set
end

-- Paints the consumable headers: white when the raid expects that consumable,
-- grey when it does not and its absences are therefore ignored.
function Grid:RefreshHeader()
    if not frame or not frame.headerToggles then
        return
    end

    for key, button in pairs(frame.headerToggles) do
        local isExpected = MFD.db.settings.raidCheck.expected[key]
        button.text:SetText((isExpected and "" or GREY) .. button.columnLabel .. (isExpected and "" or "|r"))
    end
end

function Grid:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    if frame.auto then
        frame.auto:SetChecked(MFD.db.settings.raidCheck.isAutoOpenEnabled)
    end
    Grid:RefreshHeader()

    local index = 0
    for _, entry in ipairs(RC:SortedRows()) do
        if index >= MAX_ROWS then
            break
        end
        index = index + 1
        local row = MFD.UI.AcquireRow(frame.body, rows, index, ROW_HEIGHT)
        buildRow(row)
        row.entry = entry
        entry.missingSet = missingSetFor(entry)

        local nameColor = entry.row.isReported and "" or AMBER
        row.cells.NAME.text:SetText(nameColor .. entry.name .. (nameColor ~= "" and "|r" or ""))

        for _, column in ipairs(COLUMNS) do
            if column.key ~= "NAME" then
                row.cells[column.key]:SetText(cellText(column.key, entry))
            end
        end
    end

    MFD.UI.ReleaseRows(rows, index + 1)
    frame.empty:SetText(index == 0 and (GREY .. "nobody in the group|r") or "")
end

local function isGroupUnit(unit)
    return unit == "player" or string.find(unit or "", "^raid%d+$") or string.find(unit or "", "^party%d+$")
end

-- Live while shown: a buff landing on anyone repaints. Registered on show and
-- dropped on hide so a closed window costs nothing.
local function setLive(isLive)
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_AURA" then
                if isGroupUnit(unit) then
                    RC:ScanUnit(unit)
                    Grid:Refresh()
                end
            else
                RC:Scan()
            end
        end)
    end
    if isLive then
        eventFrame:RegisterEvent("UNIT_AURA")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        RC.inspectWanted = RC.inspectWanted + 1
    else
        eventFrame:UnregisterAllEvents()
        RC.inspectWanted = math.max(0, RC.inspectWanted - 1)
    end
end

-- Builds the grid into a container the main window owns. The window supplies
-- the border, the title and the dragging; this only fills the space.
function Grid:BuildInto(container)
    frame = container

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -6)
    frame.header:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    frame.header:SetHeight(16)

    -- The five consumable headers double as the expected-or-not toggle. Putting
    -- the control directly above the column it governs beats a settings screen,
    -- and it is the only way to change this without editing saved variables.
    local isConsumable = {}
    for _, key in ipairs(RC.CONSUMABLE_ORDER) do
        isConsumable[key] = true
    end

    frame.headerToggles = {}

    for _, column in ipairs(COLUMNS) do
        if isConsumable[column.key] then
            local button = CreateFrame("Button", nil, frame.header)
            button:SetSize(column.w, 16)
            button:SetPoint("LEFT", frame.header, "LEFT", column.x, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            button.text:SetAllPoints()
            button.text:SetJustifyH("LEFT")

            button:SetScript("OnClick", function()
                local expected = MFD.db.settings.raidCheck.expected
                expected[column.key] = not expected[column.key]
                RC:Scan()
                Grid:RefreshHeader()
            end)

            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:AddLine(column.label)
                GameTooltip:AddLine(MFD.db.settings.raidCheck.expected[column.key]
                    and "The raid expects this. Click to stop reporting it missing."
                    or "Not expected. Click to start reporting it missing.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            button.columnLabel = column.label
            frame.headerToggles[column.key] = button
        else
            local label = frame.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetPoint("LEFT", frame.header, "LEFT", column.x, 0)
            label:SetText(column.label)
        end
    end

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -24)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 40)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.empty:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 8, -8)

    frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refresh:SetSize(90, 22)
    frame.refresh:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function()
        RC:Scan()
    end)

    frame.ready = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.ready:SetSize(110, 22)
    frame.ready:SetPoint("LEFT", frame.refresh, "RIGHT", 8, 0)
    frame.ready:SetText("Ready check")
    frame.ready:SetScript("OnClick", function()
        RC:StartReadyCheck()
    end)

    frame.callout = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.callout:SetSize(90, 22)
    frame.callout:SetPoint("LEFT", frame.ready, "RIGHT", 8, 0)
    frame.callout:SetText("Call out")
    frame.callout:SetScript("OnClick", function()
        RC:PostCallout()
    end)

    frame.auto = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.auto:SetSize(24, 24)
    frame.auto:SetPoint("LEFT", frame.callout, "RIGHT", 16, 0)
    frame.auto.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.auto.label:SetPoint("LEFT", frame.auto, "RIGHT", 2, 0)
    frame.auto.label:SetText("Open on ready check (leader and assist)")
    frame.auto:SetScript("OnClick", function(box)
        MFD.db.settings.raidCheck.isAutoOpenEnabled = box:GetChecked() and true or false
    end)

    frame:SetScript("OnShow", function()
        setLive(true)
        -- Scan on open. Without this the tab painted whatever the last scan
        -- left behind, which on a fresh login is nothing at all, so the grid
        -- read "nobody in the group" in a full raid and Call out had nothing
        -- to say.
        RC:Scan()
    end)
    frame:SetScript("OnHide", function()
        setLive(false)
    end)

end

-- Repaint whichever raid check surface is open when data changes underneath
-- it: a report arriving, or a scan finishing.
RC.OnDataChanged = function()
    Grid:Refresh()
    if MFD.UI.BuffBoard and MFD.UI.BuffBoard.Refresh then
        MFD.UI.BuffBoard:Refresh()
    end
end

function Grid:Show()
    MFD.UI.Main:Select("check")
    MFD.UI.Main:Open()
    RC:Scan()
end

function Grid:Toggle()
    MFD.UI.Main:Toggle("check")
end

-- The quick buff board. Missing-only by default, buff columns only, and it
-- reads nothing but RaidCheck.rows, which the scan fills without any report.
-- That is what makes it work in a pug where nobody else has the addon: the
-- reports only add columns this board does not show.
MFD.UI.BuffBoard = MFD.UI.BuffBoard or {}
local Board = MFD.UI.BuffBoard

local BOARD_WIDTH = 360        -- pixels
local BOARD_ROW_HEIGHT = 18    -- pixels
local BOARD_MAX_ROWS = 26

-- Same two-homes arrangement as the assignment panel: a floating board and a
-- tab, each with its own row pool.
local boardViews = {}
local board
local boardEvents
local isShowingAll = false

local function addBoardView(container)
    container.rows = container.rows or {}
    boardViews[#boardViews + 1] = container
    return container
end

local function buildBoardRow(row)
    if row.isBuilt then
        return
    end
    row.isBuilt = true

    row.button = CreateFrame("Button", nil, row)
    row.button:SetSize(100, BOARD_ROW_HEIGHT)
    row.button:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.button.text = row.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.button.text:SetAllPoints()
    row.button.text:SetJustifyH("LEFT")
    row.button:SetScript("OnClick", function()
        if row.entry then
            RC:Whisper(row.entry.name)
        end
    end)

    row.missing = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.missing:SetPoint("LEFT", row.button, "RIGHT", 6, 0)
    row.missing:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.missing:SetJustifyH("LEFT")
end

local function paintBoard(view)
    local index = 0
    for _, entry in ipairs(RC:SortedRows()) do
        if index >= BOARD_MAX_ROWS then
            break
        end
        local hasMissing = #entry.missing > 0
        if hasMissing or isShowingAll then
            index = index + 1
            local row = MFD.UI.AcquireRow(view.body, view.rows, index, BOARD_ROW_HEIGHT)
            buildBoardRow(row)
            row.entry = entry

            local nameColor = entry.row.isReported and "" or AMBER
            row.button.text:SetText(nameColor .. entry.name .. (nameColor ~= "" and "|r" or ""))

            if hasMissing then
                local labels = {}
                for _, m in ipairs(entry.missing) do
                    labels[#labels + 1] = m.label
                end
                row.missing:SetText(RED .. table.concat(labels, ", ") .. "|r")
            else
                row.missing:SetText(GREEN .. "ok|r")
            end
        end
    end

    MFD.UI.ReleaseRows(view.rows, index + 1)

    if index == 0 then
        view.empty:SetText(next(RC.rows) and (GREEN .. "everyone is buffed|r") or (GREY .. "nobody in the group|r"))
    else
        view.empty:SetText("")
    end
end

function Board:Refresh()
    for _, view in ipairs(boardViews) do
        if view:IsShown() then
            paintBoard(view)
        end
    end
end

-- Builds the board into a container the main window owns, alongside the
-- floating one rather than instead of it.
function Board:BuildInto(container)
    container.body = CreateFrame("Frame", nil, container)
    container.body:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -6)
    container.body:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 34)

    container.empty = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    container.empty:SetPoint("TOPLEFT", container.body, "TOPLEFT", 8, -8)

    local callout = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    callout:SetSize(80, 22)
    callout:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 14, 6)
    callout:SetText("Call out")
    callout:SetScript("OnClick", function() RC:PostCallout() end)

    local all = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    all:SetSize(24, 24)
    all:SetPoint("LEFT", callout, "RIGHT", 12, 0)
    all:SetChecked(isShowingAll)
    local allLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    allLabel:SetPoint("LEFT", all, "RIGHT", 2, 0)
    allLabel:SetText("Show all")
    all:SetScript("OnClick", function(box)
        isShowingAll = box:GetChecked() and true or false
        Board:Refresh()
    end)

    container:SetScript("OnShow", function()
        RC:Scan()
    end)

    addBoardView(container)
end

local function saveBoardPosition()
    local point, _, relativePoint, x, y = board:GetPoint()
    MFD.charDb.windows.buffBoard = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restoreBoardPosition()
    local saved = MFD.charDb.windows.buffBoard
    board:ClearAllPoints()
    if saved and saved.point then
        board:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        board:SetPoint("CENTER", UIParent, "CENTER", -300, 100)
    end
end

local function setBoardLive(isLive)
    if not boardEvents then
        boardEvents = CreateFrame("Frame")
        boardEvents:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_AURA" then
                if isGroupUnit(unit) then
                    RC:ScanUnit(unit)
                    Board:Refresh()
                end
            else
                RC:Scan()
            end
        end)
    end
    if isLive then
        boardEvents:RegisterEvent("UNIT_AURA")
        boardEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
        RC.inspectWanted = RC.inspectWanted + 1
    else
        boardEvents:UnregisterAllEvents()
        RC.inspectWanted = math.max(0, RC.inspectWanted - 1)
    end
end

local function buildBoard()
    board = CreateFrame("Frame", "MarkedForDeathBuffBoardFrame", UIParent, "BasicFrameTemplateWithInset")
    board:SetSize(BOARD_WIDTH, 30 + BOARD_MAX_ROWS * BOARD_ROW_HEIGHT + 40)
    board:SetMovable(true)
    board:EnableMouse(true)
    board:RegisterForDrag("LeftButton")
    board:SetScript("OnDragStart", board.StartMoving)
    board:SetScript("OnDragStop", function()
        board:StopMovingOrSizing()
        saveBoardPosition()
    end)
    board:SetFrameStrata("FULLSCREEN_DIALOG")

    board.title = board:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    board.title:SetPoint("TOP", board, "TOP", 0, -6)
    board.title:SetText("Buffs")

    board.body = CreateFrame("Frame", nil, board)
    board.body:SetPoint("TOPLEFT", board, "TOPLEFT", 6, -26)
    board.body:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -6, 40)

    board.empty = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    board.empty:SetPoint("TOPLEFT", board.body, "TOPLEFT", 8, -8)

    board.callout = CreateFrame("Button", nil, board, "UIPanelButtonTemplate")
    board.callout:SetSize(80, 22)
    board.callout:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", 14, 10)
    board.callout:SetText("Call out")
    board.callout:SetScript("OnClick", function()
        RC:PostCallout()
    end)

    board.all = CreateFrame("CheckButton", nil, board, "UICheckButtonTemplate")
    board.all:SetSize(24, 24)
    board.all:SetPoint("LEFT", board.callout, "RIGHT", 12, 0)
    board.all.label = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    board.all.label:SetPoint("LEFT", board.all, "RIGHT", 2, 0)
    board.all.label:SetText("Show all")
    board.all:SetScript("OnClick", function(box)
        isShowingAll = box:GetChecked() and true or false
        Board:Refresh()
    end)

    board:SetScript("OnShow", function()
        setBoardLive(true)
    end)
    board:SetScript("OnHide", function()
        setBoardLive(false)
    end)

    restoreBoardPosition()
    addBoardView(board)
    tinsert(UISpecialFrames, "MarkedForDeathBuffBoardFrame")
end

function Board:Toggle()
    if not board then
        buildBoard()
    end

    if board:IsShown() then
        board:Hide()
        return
    end

    board:Show()
    board:Raise()
    RC:Scan()
end

_G.MarkedForDeath = MFD
