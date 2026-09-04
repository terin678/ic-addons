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

-- Column layout for the library's table. consumable names the requirement a
-- column's header toggles, which is not always the column itself: Flask, Battle
-- and Guard are three views of the one flask-or-both-elixirs requirement, so the
-- Flask header governs all three.
--
-- A raid buff column is "custom": it draws the buff's own icon, and falls back
-- to a word for a buff whose icon this client has not seen on anybody yet.
local COLUMNS

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
-- Six is every blessing there is, so no cell ever needs a seventh.
local MAX_BLESSINGS = 6

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

-- A raid buff cell: the icon, with a word behind it for when there is no icon
-- yet. Both live in a frame, which is the shape Render can blank safely.
local function makeBuffCell(row, col, x, style)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetPoint("LEFT", row, "LEFT", x, 0)
    cell:SetSize(col.width, row.rowHeight)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(ICON_SIZE, ICON_SIZE)
    cell.icon:SetPoint("LEFT", cell, "LEFT", 2, 0)
    cell.icon:Hide()

    cell.text = cell:CreateFontString(nil, "OVERLAY", style.font)
    cell.text:SetPoint("LEFT", cell, "LEFT", 2, 0)
    cell.text:SetWidth(col.width - 4)
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)

    return cell
end

-- The blessings cell: the icons somebody holds, then how far short they are.
local function makeBlessingCell(row, col, x, style)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetPoint("LEFT", row, "LEFT", x, 0)
    cell:SetSize(col.width, row.rowHeight)

    cell.icons = {}
    for index = 1, MAX_BLESSINGS do
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", cell, "LEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)
        icon:Hide()
        cell.icons[index] = icon
    end

    cell.text = cell:CreateFontString(nil, "OVERLAY", style.font)
    cell.text:SetPoint("LEFT", cell, "LEFT", MAX_BLESSINGS * (ICON_SIZE + ICON_GAP) + 4, 0)
    cell.text:SetWidth(col.width - MAX_BLESSINGS * (ICON_SIZE + ICON_GAP) - 6)
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)

    return cell
end

COLUMNS = {
    { key = "NAME",      label = "Name",      width = 110, hit = true },
    { key = "FOOD",      label = "Food",      width = 44, consumable = "FOOD" },
    { key = "FLASK",     label = "Flask",     width = 44, consumable = "ELIXIRS" },
    { key = "BATTLE",    label = "Battle",    width = 44 },
    { key = "GUARDIAN",  label = "Guard",     width = 44 },
    { key = "AI",        label = "Int",       width = 42, type = "custom", make = makeBuffCell },
    { key = "MOTW",      label = "MotW",      width = 42, type = "custom", make = makeBuffCell },
    { key = "FORT",      label = "Fort",      width = 42, type = "custom", make = makeBuffCell },
    { key = "SPIRIT",    label = "Spirit",    width = 42, type = "custom", make = makeBuffCell },
    { key = "SP",        label = "SProt",     width = 42, type = "custom", make = makeBuffCell },
    { key = "BLESSINGS", label = "Blessings", width = 210, type = "custom", make = makeBlessingCell },
    { key = "DUR",       label = "Dur",       width = 46 },
    { key = "SPEC",      label = "Spec",      width = 82 },
    { key = "VER",       label = "Ver",       width = 54 },
}

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
local eventFrame

-- Draws the blessings somebody holds as their own icons, left to right.
-- The shortfall count that follows them is set by the caller.
local function paintBlessings(cell, entry)
    local learned = MFD.db.learnedAuraIcons
    local drawn = 0

    for _, label in ipairs(entry.row.state.blessings) do
        -- The aura table maps names to labels; find a name that maps back to
        -- this label and whose icon has been seen on somebody.
        local iconPath
        for name, mapped in pairs(MFD.Data.Auras.BLESSINGS) do
            if mapped == label and learned[name] then
                iconPath = learned[name]
                break
            end
        end

        if iconPath and drawn < MAX_BLESSINGS then
            drawn = drawn + 1
            local icon = cell.icons[drawn]
            icon:SetTexture(iconPath)
            icon:SetDesaturated(false)
            icon:SetVertexColor(1, 1, 1)
            icon:Show()
        end
    end

    for index = drawn + 1, MAX_BLESSINGS do
        cell.icons[index]:Hide()
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
    if not frame or not frame.table then
        return
    end

    for _, column in ipairs(COLUMNS) do
        if column.consumable then
            local label = frame.table.header.labels[column.key]
            local isExpected = MFD.db.settings.raidCheck.expected[column.consumable]
            if label then
                label:SetText((isExpected and "" or GREY) .. column.label .. (isExpected and "" or "|r"))
            end
        end
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

    local list = {}
    for _, entry in ipairs(RC:SortedRows()) do
        if #list >= MAX_ROWS then
            break
        end
        list[#list + 1] = entry
    end

    local learned = MFD.db.learnedAuraIcons
    local t = frame.table

    t:Render(list, function(row, entry)
        entry.missingSet = missingSetFor(entry)
        entry.missingShort = nil
        for _, m in ipairs(entry.missing or {}) do
            if m.column == "BLESSING" then
                entry.missingShort = m
            end
        end

        -- Amber for somebody only scanned rather than heard from: this addon's
        -- colour for a derived value.
        t:Set(row, "NAME", entry.name, not entry.row.isReported
            and { r = 1, g = 0.8, b = 0.4 } or nil)
        row.hit.NAME:SetScript("OnClick", function()
            RC:Whisper(entry.name)
        end)

        for _, column in ipairs(COLUMNS) do
            local buff = MFD.Data.Auras.RAID_BUFFS[column.key]

            if buff then
                local cell = row.cells[column.key]
                local drew = paintIcon(cell.icon, RC.IconFor(buff.names, learned),
                    entry.row.state[column.key], entry.missingSet[column.key])
                -- The word only appears when the icon could not, so a column is
                -- never both at once and never empty.
                cell.text:SetText(drew and "" or cellText(column.key, entry))
            elseif column.key == "BLESSINGS" then
                paintBlessings(row.cells.BLESSINGS, entry)
                row.cells.BLESSINGS.text:SetText(cellText(column.key, entry))
            elseif column.key ~= "NAME" then
                t:Set(row, column.key, cellText(column.key, entry))
            end
        end
    end)

    frame.empty:SetText(#list == 0 and (GREY .. "nobody in the group|r") or "")
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

    -- The header is the library's, so it sits outside the scroll child and
    -- stays put while the rows scroll. Clicking a consumable's header toggles
    -- whether the raid expects it: the control directly above the column it
    -- governs beats a settings screen, and it is the only way to change this
    -- without editing saved variables.
    frame.table = MFD.UI.Table(frame, {
        top = -6,
        bottom = 40,
        rowHeight = ROW_HEIGHT,
        columns = COLUMNS,
        onHeaderClick = function(col)
            local column
            for _, c in ipairs(COLUMNS) do
                if c.key == col.key then
                    column = c
                end
            end
            if not column or not column.consumable then
                return
            end

            local expected = MFD.db.settings.raidCheck.expected
            expected[column.consumable] = not expected[column.consumable]
            RC:Scan()
            Grid:RefreshHeader()
        end,
    })

    frame.empty = MFD.UI.Label(frame, "")
    frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)

    frame.refresh = MFD.UI.Button(frame, "", 90, 22)
    frame.refresh:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function()
        RC:Scan()
    end)

    frame.ready = MFD.UI.Button(frame, "", 110, 22)
    frame.ready:SetPoint("LEFT", frame.refresh, "RIGHT", 8, 0)
    frame.ready:SetText("Ready check")
    frame.ready:SetScript("OnClick", function()
        RC:StartReadyCheck()
    end)

    frame.callout = MFD.UI.Button(frame, "", 90, 22)
    frame.callout:SetPoint("LEFT", frame.ready, "RIGHT", 8, 0)
    frame.callout:SetText("Call out")
    frame.callout:SetScript("OnClick", function()
        RC:PostCallout()
    end)

    frame.auto = MFD.UI.CheckBox(frame, "Open on ready check (leader and assist)")
    frame.auto:SetPoint("LEFT", frame.callout, "RIGHT", 16, 0)
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

-- One icon per thing somebody is missing. A strip of greyed icons reads faster
-- than a comma list when you are scanning twenty five people between pulls.
local MAX_MISSING_ICONS = 8

-- The custom cell: a frame holding the strip. A frame is the safe shape here
-- because Render blanks a cell by calling SetText, SetTexture and SetChecked on
-- it, and a frame has none of them to be caught by.
local function makeIconStrip(row, col, x)
    local strip = CreateFrame("Frame", nil, row)
    strip:SetPoint("LEFT", row, "LEFT", x, 0)
    strip:SetSize(col.width, row.rowHeight)

    strip.icons = {}
    for index = 1, MAX_MISSING_ICONS do
        local icon = strip:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", strip, "LEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)
        icon:Hide()
        strip.icons[index] = icon
    end

    return strip
end

local function addBoardView(container, top, bottom)
    container.table = MFD.UI.Table(container, {
        top = top or 0,
        bottom = bottom or 0,
        rowHeight = BOARD_ROW_HEIGHT,
        columns = {
            { key = "name", label = "Name", width = 100, hit = true },
            { key = "icons", label = "Missing", width = MAX_MISSING_ICONS * (ICON_SIZE + ICON_GAP),
              type = "custom", make = makeIconStrip },
            { key = "words", label = "", width = "flex" },
        },
    })
    boardViews[#boardViews + 1] = container
    return container
end

-- Fills the strip and returns the labels that had no icon to draw, so nothing
-- is lost when an icon has not been seen on anybody yet.
local function paintMissingIcons(strip, entry)
    local learned = MFD.db.learnedAuraIcons
    local buffs = MFD.Data.Auras.RAID_BUFFS
    local drawn, words = 0, {}

    for _, m in ipairs(entry.missing) do
        local buff = buffs[m.column]
        local iconPath = buff and RC.IconFor(buff.names, learned) or nil

        if iconPath and drawn < MAX_MISSING_ICONS then
            drawn = drawn + 1
            local icon = strip.icons[drawn]
            icon:SetTexture(iconPath)
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 0.3, 0.3)
            icon:Show()
        else
            -- Consumables, blessings and anything not yet seen keep their word.
            words[#words + 1] = m.label
        end
    end

    for index = drawn + 1, MAX_MISSING_ICONS do
        strip.icons[index]:Hide()
    end

    return words
end

local function paintBoard(view)
    local list = {}
    for _, entry in ipairs(RC:SortedRows()) do
        if #list >= BOARD_MAX_ROWS then
            break
        end
        if #entry.missing > 0 or isShowingAll then
            list[#list + 1] = entry
        end
    end

    view.table:Render(list, function(row, entry)
        -- Amber for somebody the addon has only scanned rather than heard from,
        -- which is the colour this addon uses for a derived value everywhere.
        local nameColor = entry.row.isReported and nil or { r = 1, g = 0.8, b = 0.4 }
        view.table:Set(row, "name", entry.name, nameColor)

        row.hit.name:SetScript("OnClick", function()
            RC:Whisper(entry.name)
        end)

        if #entry.missing == 0 then
            for _, icon in ipairs(row.cells.icons.icons) do
                icon:Hide()
            end
            view.table:Set(row, "words", "ok", { r = 0.4, g = 1, b = 0.4 })
            return
        end

        local words = paintMissingIcons(row.cells.icons, entry)
        view.table:Set(row, "words", table.concat(words, ", "), { r = 1, g = 0.3, b = 0.3 })
    end)

    if #list == 0 then
        view.empty:SetText(next(RC.rows) and (GREEN .. "everyone is buffed|r")
            or (GREY .. "nobody in the group|r"))
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
    container.empty = MFD.UI.Label(container, "")
    container.empty:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -26)

    local callout = MFD.UI.Button(container, "Call out", 80, 22)
    callout:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 14, 6)
    callout:SetScript("OnClick", function() RC:PostCallout() end)

    local all = MFD.UI.CheckBox(container, "Show all")
    all:SetPoint("LEFT", callout, "RIGHT", 12, 0)
    all:SetChecked(isShowingAll)
    all:SetScript("OnClick", function(box)
        isShowingAll = box:GetChecked() and true or false
        Board:Refresh()
    end)

    container:SetScript("OnShow", function()
        RC:Scan()
    end)

    -- The toolbar sits along the bottom, so the list stops short of it.
    addBoardView(container, 0, 34)
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
    board = MFD.UI.Window("MarkedForDeathBuffBoardFrame", {
        width = BOARD_WIDTH,
        height = 30 + BOARD_MAX_ROWS * BOARD_ROW_HEIGHT + 40,
        title = "Buffs",
        status = false,
        strata = "FULLSCREEN_DIALOG",
        scalable = true,
        onScaleChanged = function(_, scale)
            MFD.charDb.windows.buffBoard = MFD.charDb.windows.buffBoard or {}
            MFD.charDb.windows.buffBoard.scale = scale
        end,
    })

    board:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveBoardPosition()
    end)

    -- The library's body starts under the title bar; the toolbar along the
    -- bottom is this board's own, so the list stops short of it.
    board.empty = MFD.UI.Label(board, "")
    board.empty:SetPoint("TOPLEFT", board, "TOPLEFT", 14, -56)

    board.callout = MFD.UI.Button(board, "Call out", 80, 22)
    board.callout:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", 14, 10)
    board.callout:SetScript("OnClick", function()
        RC:PostCallout()
    end)

    board.all = MFD.UI.CheckBox(board, "Show all")
    board.all:SetPoint("LEFT", board.callout, "RIGHT", 12, 0)
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

    local saved = MFD.charDb.windows.buffBoard
    if board.SetWindowScale and saved and saved.scale then
        board:SetWindowScale(saved.scale, true)
    end

    restoreBoardPosition()
    -- Below the library's title bar, and clear of the toolbar at the bottom.
    addBoardView(board, -34, 40)
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
