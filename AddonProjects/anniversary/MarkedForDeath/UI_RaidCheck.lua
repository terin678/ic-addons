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
local GRID_WIDTH = 920    -- pixels

-- Column layout: key, header label, x offset from the row's left edge, width.
-- consumable names the requirement a column's header toggles, which is not
-- always the column itself: Flask, Battle and Guard are three views of the one
-- flask-or-both-elixirs requirement, so the Flask header governs all three.
local COLUMNS = {
    { key = "NAME",      label = "Name",      x = 0,   w = 110 },
    { key = "FOOD",      label = "Food",      x = 112, w = 44, consumable = "FOOD" },
    { key = "FLASK",     label = "Flask",     x = 158, w = 44, consumable = "ELIXIRS" },
    { key = "BATTLE",    label = "Battle",    x = 204, w = 44 },
    { key = "GUARDIAN",  label = "Guard",     x = 250, w = 44 },
    { key = "AI",        label = "Int",       x = 296, w = 40 },
    { key = "MOTW",      label = "MotW",      x = 338, w = 40 },
    { key = "FORT",      label = "Fort",      x = 380, w = 40 },
    { key = "SPIRIT",    label = "Spirit",    x = 422, w = 40 },
    { key = "SP",        label = "SProt",     x = 464, w = 40 },
    { key = "BLESSINGS", label = "Blessings", x = 506, w = 210 },
    { key = "DUR",       label = "Dur",       x = 718, w = 40 },
    { key = "SPEC",      label = "Spec",      x = 760, w = 80 },
    { key = "VER",       label = "Ver",       x = 842, w = 50 },
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

local ICON_SIZE = 14        -- pixels per buff icon
local ICON_GAP = 2          -- pixels between blessing icons

-- Paints one icon to say present, missing or unknown.
--
-- Colour carries the meaning, not the picture: full colour is present, a
-- desaturated red one is missing and worth fixing, a desaturated grey one is
-- absent but nobody's problem. The icon itself says which buff, which is the
-- thing a word column made you read.
local function paintIcon(texture, iconPath, value, isMissing)
    if not iconPath then
        texture:Hide()
        return false
    end

    texture:SetTexture(iconPath)
    texture:Show()

    if value == true then
        texture:SetDesaturated(false)
        texture:SetVertexColor(1, 1, 1)
    elseif value == false then
        texture:SetDesaturated(true)
        if isMissing then
            texture:SetVertexColor(1, 0.3, 0.3)
        else
            texture:SetVertexColor(0.45, 0.45, 0.45)
        end
    else
        -- Unknown. Dimmer than an absence, because "no data" is not "no buff".
        texture:SetDesaturated(true)
        texture:SetVertexColor(0.3, 0.3, 0.3)
    end

    return true
end

-- Returns the text for one cell of one player's entry.
local function cellText(column, entry)
    local state, missingSet = entry.row.state, entry.missingSet
    local hasFlask = state.flask ~= nil

    -- All three of these read the one flask-or-both-elixirs requirement, so an
    -- absence is only red when the requirement as a whole is unmet. Someone
    -- running both elixirs has an empty Flask cell and owes nothing.
    local isShort = missingSet.ELIXIRS

    if column == "FOOD" then
        return presence(state.food ~= nil, missingSet.FOOD)
    elseif column == "FLASK" then
        return presence(hasFlask, isShort)
    elseif column == "BATTLE" then
        if hasFlask and state.battle == nil then
            return GREEN .. "flask|r"
        end
        return presence(state.battle ~= nil, isShort)
    elseif column == "GUARDIAN" then
        if hasFlask and state.guardian == nil then
            return GREEN .. "flask|r"
        end
        return presence(state.guardian ~= nil, isShort)
    elseif MFD.Data.Auras.RAID_BUFFS[column] then
        return presence(state[column], missingSet[column])
    elseif column == "BLESSINGS" then
        -- The icons are drawn separately; this is only the shortfall count that
        -- rides alongside them, and the words for anyone whose blessing icons
        -- have not been seen yet.
        local short = entry.missingShort
        if short then
            return RED .. "(" .. short.have .. "/" .. short.expected .. ")|r"
        end
        return ""
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
            -- One line, always. A cell with a width wraps by default, and a
            -- second line has nowhere to go in an 18 pixel row: it would draw
            -- over the person below. Clipping is the honest failure here;
            -- overlapping two players' data is not.
            text:SetWordWrap(false)
            row.cells[column.key] = text

            -- Raid buffs get an icon in front of the text. The text stays as
            -- the fallback for a buff whose icon this client has not seen on
            -- anybody yet, so the column always says something.
            if MFD.Data.Auras.RAID_BUFFS[column.key] then
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ICON_SIZE, ICON_SIZE)
                icon:SetPoint("LEFT", row, "LEFT", column.x, 0)
                icon:Hide()
                row.icons = row.icons or {}
                row.icons[column.key] = icon
            end
        end
    end

    -- A pool of blessing icons, one per blessing anybody can hold.
    row.blessingIcons = {}
    for index = 1, 6 do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:Hide()
        row.blessingIcons[index] = icon
    end
end

-- Draws the blessings somebody holds as their own icons, left to right, with
-- the shortfall count following them. Returns the x offset the count should
-- start at, so it never lands on top of an icon.
local function paintBlessings(row, entry, column)
    local learned = MFD.db.learnedAuraIcons
    local state = entry.row.state
    local drawn = 0

    for _, label in ipairs(state.blessings) do
        -- The names in the aura table map to labels; find one that maps back to
        -- this label and whose icon has been seen.
        local iconPath
        for name, mapped in pairs(MFD.Data.Auras.BLESSINGS) do
            if mapped == label and learned[name] then
                iconPath = learned[name]
                break
            end
        end

        if iconPath and drawn < #row.blessingIcons then
            drawn = drawn + 1
            local icon = row.blessingIcons[drawn]
            icon:SetTexture(iconPath)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT",
                column.x + (drawn - 1) * (ICON_SIZE + ICON_GAP), 0)
            icon:SetDesaturated(false)
            icon:SetVertexColor(1, 1, 1)
            icon:Show()
        end
    end

    for index = drawn + 1, #row.blessingIcons do
        row.blessingIcons[index]:Hide()
    end

    return column.x + drawn * (ICON_SIZE + ICON_GAP), drawn
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
        entry.missingShort = nil
        for _, m in ipairs(entry.missing or {}) do
            if m.column == "BLESSING" then
                entry.missingShort = m
            end
        end

        local nameColor = entry.row.isReported and "" or AMBER
        row.cells.NAME.text:SetText(nameColor .. entry.name .. (nameColor ~= "" and "|r" or ""))

        local learned = MFD.db.learnedAuraIcons

        for _, column in ipairs(COLUMNS) do
            if column.key == "NAME" then
                -- Already painted above.
            elseif column.key == "BLESSINGS" then
                local countX = paintBlessings(row, entry, column)
                local cell = row.cells.BLESSINGS
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", countX + 2, 0)
                cell:SetWidth(column.w - (countX - column.x) - 2)
                cell:SetText(cellText(column.key, entry))
            else
                local buff = MFD.Data.Auras.RAID_BUFFS[column.key]
                local icon = row.icons and row.icons[column.key]
                local drewIcon = false

                if buff and icon then
                    drewIcon = paintIcon(icon, RC.IconFor(buff.names, learned),
                        entry.row.state[column.key], entry.missingSet[column.key])
                end

                -- The word only appears when the icon could not, so the column
                -- is never both at once and never empty.
                row.cells[column.key]:SetText(drewIcon and "" or cellText(column.key, entry))
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

    -- The consumable headers double as the expected-or-not toggle. Putting the
    -- control directly above the column it governs beats a settings screen, and
    -- it is the only way to change this without editing saved variables.
    local isConsumable = {}
    for _, key in ipairs(RC.CONSUMABLE_ORDER) do
        isConsumable[key] = true
    end

    frame.headerToggles = {}

    for _, column in ipairs(COLUMNS) do
        if column.consumable and isConsumable[column.consumable] then
            local button = CreateFrame("Button", nil, frame.header)
            button:SetSize(column.w, 16)
            button:SetPoint("LEFT", frame.header, "LEFT", column.x, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            button.text:SetAllPoints()
            button.text:SetJustifyH("LEFT")

            button:SetScript("OnClick", function()
                local expected = MFD.db.settings.raidCheck.expected
                expected[column.consumable] = not expected[column.consumable]
                RC:Scan()
                Grid:RefreshHeader()
            end)

            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:AddLine(column.label)
                GameTooltip:AddLine(MFD.db.settings.raidCheck.expected[column.consumable]
                    and "The raid expects this. Click to stop reporting it missing."
                    or "Not expected. Click to start reporting it missing.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            button.columnLabel = column.label
            frame.headerToggles[column.consumable] = button
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
    row.missing:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.missing:SetJustifyH("LEFT")

    -- One icon per thing they are missing, drawn before the words. A row of
    -- greyed-out icons reads faster than a comma list when you are scanning
    -- twenty five of them between pulls.
    row.missingIcons = {}
    for index = 1, 8 do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:Hide()
        row.missingIcons[index] = icon
    end
end

-- Draws an icon for each missing entry that has one and returns the words for
-- the rest, so nothing is lost when an icon has not been seen yet.
local function paintMissingIcons(row, entry, startX)
    local learned = MFD.db.learnedAuraIcons
    local buffs = MFD.Data.Auras.RAID_BUFFS
    local drawn, words = 0, {}

    for _, m in ipairs(entry.missing) do
        local buff = buffs[m.column]
        local iconPath = buff and RC.IconFor(buff.names, learned) or nil

        if iconPath and drawn < #row.missingIcons then
            drawn = drawn + 1
            local icon = row.missingIcons[drawn]
            icon:SetTexture(iconPath)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT", startX + (drawn - 1) * (ICON_SIZE + ICON_GAP), 0)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 0.3, 0.3)
            icon:Show()
        else
            -- Consumables, blessings and anything not yet seen keep their word.
            words[#words + 1] = m.label
        end
    end

    for index = drawn + 1, #row.missingIcons do
        row.missingIcons[index]:Hide()
    end

    return startX + drawn * (ICON_SIZE + ICON_GAP), words
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

            row.missing:ClearAllPoints()
            row.missing:SetPoint("RIGHT", row, "RIGHT", 0, 0)

            if hasMissing then
                local textX, words = paintMissingIcons(row, entry, 106)
                row.missing:SetPoint("LEFT", row, "LEFT", textX + 4, 0)
                row.missing:SetText(#words > 0 and (RED .. table.concat(words, ", ") .. "|r") or "")
            else
                for _, icon in ipairs(row.missingIcons) do
                    icon:Hide()
                end
                row.missing:SetPoint("LEFT", row, "LEFT", 106, 0)
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

    MFD.UI.MakeResizable(board, "buffBoard", 300, 140, function()
        Board:Refresh()
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
