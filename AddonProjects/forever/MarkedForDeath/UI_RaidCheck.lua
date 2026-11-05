local addonName, ns = ...

--[[
UI_RaidCheck: the raid check grid and buff board.
Owned by lane C (raid check). Frame module: builds nothing at file scope; the windows are
made the first time they are shown, which is never before the ns.OnReady hook below, and
that hook returns early on IC_HEADLESS. Everything shown comes from RaidCheck's snapshot,
which RaidCheckModel built; this file only draws it.

    The grid    a window: toolbar, a header row above the scroll, one fixed-height row per
                member and one cell per column. /mfd check.
    The board   a small movable panel listing only the members missing something, its
                place saved per character (windows.board). /mfd check board.

Colours mean one thing each: green has it, red missing, grey could not be read (never
red), amber an older version, dim nothing expected.

TODO(lane G, K8): when UI_Main offers ns.UI.AddTab, BuildGrid moves into a "Raid check" tab
and the standalone grid window goes; until then it opens centred and is not remembered.
When LibICWidgets has List (K8), the hand-pooled rows below move onto it.
]]

ns.RaidCheckUI = ns.RaidCheckUI or {}
local UI = ns.RaidCheckUI
local RC = ns.RaidCheck
local Model = ns.RaidCheckModel

local W = LibStub("LibICWidgets-1.0")

local GRID_NAME = "MarkedForDeathRaidCheck"     -- named for UISpecialFrames (Escape closes)
local BOARD_NAME = "MarkedForDeathBuffBoard"
local ROW_H = 18                                -- pixels, every list row
local HEAD_H = 18                               -- the header row
local TITLE_H = 24
local TOOLBAR_H = 26
local PAD = 8
local NAME_W = 120
local GRID_ROWS = 20                            -- rows visible before the list scrolls
local BOARD_W, BOARD_ROWS = 300, 10
local BOARD_NAME_W = 110
local TOOLBAR_W = 386                           -- the grid toolbar's buttons and gaps
local TICK = 10                                 -- seconds between redraws of the read's age

-- Cell widths by column kind, in pixels.
local KIND_W = { buff = 40, blessing = 84, flask = 104, food = 40, durability = 44, version = 48 }

-- Status colours, the same meaning on every surface (CODING_STANDARDS, User-facing text).
local STATUS_HEX = {
    ok = "ff44ff44", missing = "ffff4444", unknown = "ff999999", old = "ffffcc66", none = "ff666666",
}

local function Paint(status, text)
    return "|c" .. (STATUS_HEX[status] or STATUS_HEX.unknown) .. tostring(text or "") .. "|r"
end

local function Age(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

-- A single-line cell: cut, never wrapped.
local function Cell(parent, width, justify)
    local fs = W.Label(parent, "", { font = "small", justify = justify or "CENTER" })
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    return fs
end

-- The words above the list: when the snapshot was read and why, and whether it is held.
local function StatusLine(snap)
    if not snap then return "Not read yet. Scan reads everyone's buffs out of combat." end
    local line = string.format("Read %s ago (%s), %d members.", Age(time() - snap.at), snap.reason, #snap.rows)
    if snap.held then line = line .. " " .. Paint("old", "Held: " .. snap.held .. ".") end
    return line
end

-- The tooltip for one member: what is missing, and which cells could not be read.
local function RowTooltip(tip, row, columns)
    tip:AddLine(row.name)
    local line = Model.MissingLine(row)
    tip:AddLine(line and ("Missing: " .. line) or "Nothing missing.", 1, 1, 1, true)
    for _, column in ipairs(columns) do
        local cell = row.cells[column.key]
        if cell then tip:AddDoubleLine(column.label, Paint(cell.status, cell.text)) end
    end
    if row.state and not row.state.readable then
        tip:AddLine("Could not be read: " .. tostring(row.state.why) .. ".", 0.6, 0.6, 0.6, true)
    elseif row.state and row.state.partial then
        tip:AddLine("Some buffs were hidden, so an absence is not proof.", 0.6, 0.6, 0.6, true)
    end
    tip:Show()
end

--------------------------------------------------------------------------------
-- A window shell: panel, title bar that drags it, a close button
--------------------------------------------------------------------------------

-- `escape = false` keeps Escape from closing it: the board stays up through a raid.
local function Shell(name, title, width, height, onMoved, escape)
    local panel = W.Panel(UIParent, {
        name = name, width = width, height = height, strata = "MEDIUM", movable = true, onMoved = onMoved,
    })
    panel:SetPoint("CENTER")
    panel:SetToplevel(true)
    local bar = W.Panel(panel, { height = TITLE_H, role = "raised", edge = false })
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    W.DragHandle(bar, panel)
    local label = W.Label(bar, title, { font = "title" })
    label:SetPoint("LEFT", bar, "LEFT", PAD, 0)
    local close = W.Button(bar, "x", 20, 18, { kind = "flat", onClick = function() panel:Hide() end })
    close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    W.Tooltip(close, function(tip) tip:AddLine("Close") tip:Show() end)
    if escape ~= false then tinsert(UISpecialFrames, name) end
    panel:Hide()
    return panel
end

--------------------------------------------------------------------------------
-- The grid
--------------------------------------------------------------------------------

local grid

local function GridColumns()
    local snap = RC.Snapshot()
    if snap then return snap.ctx.columns end
    return Model.Columns(ns.db and ns.db.check and ns.db.check.columns)
end

local function ColumnsWidth(columns)
    local w = NAME_W
    for _, c in ipairs(columns) do w = w + (KIND_W[c.kind] or 40) end
    return w
end

-- One pooled row: a name and a cell per column, rebuilt when the columns change.
local function GridRow(content, index)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:EnableMouse(true)
    row.name = Cell(row, NAME_W - 4, "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.cells = {}
    W.Tooltip(row, function(tip, self)
        if self.icRow then RowTooltip(tip, self.icRow, grid.columns) end
    end)
    return row
end

local function LayoutCells(row, columns)
    for _, fs in pairs(row.cells) do fs:Hide() end
    local x = NAME_W
    for _, c in ipairs(columns) do
        local w = KIND_W[c.kind] or 40
        local fs = row.cells[c.key]
        if not fs then
            local justify = (c.kind == "blessing" or c.kind == "flask") and "LEFT" or "CENTER"
            fs = Cell(row, w - 4, justify)
            row.cells[c.key] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
        fs:Show()
        x = x + w
    end
end

-- Sizes the window, the list and the header to the columns, never narrower than the
-- toolbar, so a column switched on later never runs past the edge.
local function SizeGrid(columns)
    local listW = ColumnsWidth(columns) + 16      -- room for the scroll bar
    grid:SetWidth(math.max(listW, TOOLBAR_W) + PAD * 2)
    grid.scroll:SetWidth(listW)
    grid.scroll.content:SetWidth(listW - 12)
    grid.header:SetWidth(listW - 12)
end

local function BuildHeader(columns)
    for _, fs in pairs(grid.heads) do fs:Hide() end
    local x = NAME_W
    for _, c in ipairs(columns) do
        local w = KIND_W[c.kind] or 40
        local fs = grid.heads[c.key]
        if not fs then
            fs = Cell(grid.header, w - 4, "CENTER")
            fs:SetRole("textDim")
            grid.heads[c.key] = fs
        end
        fs:SetText(c.label)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", grid.header, "LEFT", x + 2, 0)
        fs:Show()
        x = x + w
    end
end

local function RefreshGrid()
    if not grid or not grid:IsShown() then return end
    local snap = RC.Snapshot()
    local columns = GridColumns()
    local key = {}
    for _, c in ipairs(columns) do key[#key + 1] = c.key end
    key = table.concat(key, ",")
    if key ~= grid.columnKey then
        grid.columnKey = key
        grid.columns = columns
        SizeGrid(columns)
        BuildHeader(columns)
        for _, row in ipairs(grid.rows) do LayoutCells(row, columns) end
    end
    grid.status:SetText(StatusLine(snap))

    local rows = snap and snap.rows or {}
    for i, data in ipairs(rows) do
        local row = grid.rows[i]
        if not row then
            row = GridRow(grid.scroll.content, i)
            LayoutCells(row, grid.columns)
            grid.rows[i] = row
        end
        row.icRow = data
        local nameStatus = #data.missing > 0 and "missing" or (data.unknown > 0 and "unknown" or "ok")
        row.name:SetText(Paint(nameStatus == "ok" and "ok" or nameStatus, data.name))
        for _, c in ipairs(grid.columns) do
            local cell = data.cells[c.key]
            row.cells[c.key]:SetText(cell and Paint(cell.status, cell.text) or "")
        end
        row:Show()
    end
    for i = #rows + 1, #grid.rows do
        grid.rows[i].icRow = nil
        grid.rows[i]:Hide()
    end
    grid.scroll:SetContentHeight(#rows * ROW_H)
end

-- Lays the buttons left to right; returns them by `key`.
local function Toolbar(parent, buttons)
    local x, made = 0, {}
    for _, b in ipairs(buttons) do
        local button = W.Button(parent, b.text, b.width, 20, { kind = b.kind, onClick = b.onClick })
        button:SetPoint("LEFT", parent, "LEFT", x, 0)
        W.Tooltip(button, function(tip) tip:AddLine(b.text) tip:AddLine(b.tip, 1, 1, 1, true) tip:Show() end)
        x = x + b.width + 4
        if b.key then made[b.key] = button end
    end
    return made
end

-- The Board button says whether the board is open.
local function BoardLabel()
    if grid and grid.boardButton then
        grid.boardButton:SetLabel(UI.BoardShown() and "Hide board" or "Board")
    end
end

-- While a window is shown its "read Ns ago" is redrawn every TICK seconds; a quiet group
-- sends no event that would. The ticker stops when the window hides.
local function Tick(frame, redraw)
    frame:HookScript("OnShow", function(self)
        if self.icTicker or not (C_Timer and C_Timer.NewTicker) then return end
        self.icTicker = C_Timer.NewTicker(TICK, redraw)
    end)
    frame:HookScript("OnHide", function(self)
        if self.icTicker then self.icTicker:Cancel() end
        self.icTicker = nil
    end)
end

local function Scan()
    local ok, why = RC.Scan("scan")
    if not ok then ns.Printf("not read: %s.", why) end
end

local function BuildGrid()
    local columns = GridColumns()
    local listW = ColumnsWidth(columns) + 16      -- room for the scroll bar
    local width = math.max(listW, TOOLBAR_W) + PAD * 2
    local statusH = 14
    local height = TITLE_H + PAD + TOOLBAR_H + statusH + 4 + HEAD_H + GRID_ROWS * ROW_H + PAD
    grid = Shell(GRID_NAME, "Raid check", width, height)
    grid.rows, grid.heads = {}, {}

    local toolbar = CreateFrame("Frame", nil, grid)
    toolbar:SetHeight(TOOLBAR_H)
    toolbar:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD, -(TITLE_H + PAD))
    toolbar:SetPoint("RIGHT", grid, "RIGHT", -PAD, 0)
    local made = Toolbar(toolbar, {
        { text = "Scan", width = 60, kind = "accent", onClick = Scan,
          tip = "Read everyone's buffs now. Out of combat only." },
        { text = "Callout", width = 70, onClick = function() RC.Callout() end,
          tip = "Say who is missing what in group chat, one line per fix. Grey cells are never named." },
        { text = "Missing", width = 70, onClick = function() RC.Missing() end,
          tip = "Print who is missing what, for you only." },
        { text = "Ready check", width = 90, onClick = function() RC.ReadyCheck() end,
          tip = "Start the game's ready check (leader or assistant)." },
        { key = "board", text = "Hide board", width = 80, kind = "flat", onClick = function() UI.ToggleBoard() end,
          tip = "The small board: only the members missing something." },
    })
    grid.boardButton = made.board
    BoardLabel()

    grid.status = W.Label(grid, "", { font = "small", color = "textDim" })
    grid.status:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    grid.status:SetPoint("RIGHT", grid, "RIGHT", -PAD, 0)
    grid.status:SetWordWrap(false)
    grid.status:SetHeight(statusH)

    -- The header row sits above the scroll, so it stays put while rows scroll.
    grid.header = CreateFrame("Frame", nil, grid)
    grid.header:SetHeight(HEAD_H)
    grid.header:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -(statusH + 4))
    grid.header:SetWidth(listW - 12)
    local nameHead = Cell(grid.header, NAME_W - 4, "LEFT")
    nameHead:SetRole("textDim")
    nameHead:SetText("Name")
    nameHead:SetPoint("LEFT", grid.header, "LEFT", 4, 0)

    grid.scroll = W.Scroll(grid, listW, GRID_ROWS * ROW_H, { step = ROW_H * 3 })
    grid.scroll:SetPoint("TOPLEFT", grid.header, "BOTTOMLEFT", 0, 0)

    grid:HookScript("OnShow", function()
        RC.Live("grid", true)
        RefreshGrid()
    end)
    grid:HookScript("OnHide", function() RC.Live("grid", false) end)
    Tick(grid, function() grid.status:SetText(StatusLine(RC.Snapshot())) end)
end

--------------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------------

local board

local function SaveBoard(panel)
    if not ns.cdb then return end
    local fx, fy = W.GetPlace(panel)
    ns.cdb.windows.board.fx, ns.cdb.windows.board.fy = fx, fy
end

local function RefreshBoard()
    if not board or not board:IsShown() then return end
    local snap = RC.Snapshot()
    local shown, unknown = {}, 0
    for _, row in ipairs(snap and snap.rows or {}) do
        if #row.missing > 0 then shown[#shown + 1] = row end
        if row.unknown > 0 and #row.missing == 0 then unknown = unknown + 1 end
    end
    local line = snap and string.format("%d missing something, read %s ago.", #shown, Age(time() - snap.at))
        or "Not read yet."
    if unknown > 0 then line = line .. " " .. Paint("unknown", unknown .. " not read in full.") end
    board.status:SetText(line)
    for i, data in ipairs(shown) do
        local row = board.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, board.scroll.content)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", board.scroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetPoint("RIGHT", board.scroll.content, "RIGHT", 0, 0)
            row:EnableMouse(true)
            row.name = Cell(row, BOARD_NAME_W - 4, "LEFT")
            row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.what = Cell(row, BOARD_W - BOARD_NAME_W - PAD * 2 - 20, "LEFT")
            row.what:SetPoint("LEFT", row, "LEFT", BOARD_NAME_W, 0)
            W.Tooltip(row, function(tip, self)
                local now = RC.Snapshot()
                if self.icRow then RowTooltip(tip, self.icRow, now and now.ctx.columns or {}) end
            end)
            board.rows[i] = row
        end
        row.icRow = data
        row.name:SetText(data.name)
        row.what:SetText(Paint("missing", Model.MissingLine(data)))
        row:Show()
    end
    for i = #shown + 1, #board.rows do
        board.rows[i].icRow = nil
        board.rows[i]:Hide()
    end
    board.scroll:SetContentHeight(#shown * ROW_H)
end

local function BuildBoard()
    local listW = BOARD_W - PAD * 2
    local statusH = 14
    local height = TITLE_H + PAD + statusH + 4 + HEAD_H + BOARD_ROWS * ROW_H + PAD
    board = Shell(BOARD_NAME, "Buff board", BOARD_W, height, SaveBoard, false)
    board.rows = {}
    local place = ns.cdb and ns.cdb.windows.board
    if place and place.fx and place.fy then
        board:ClearAllPoints()
        W.SetPlace(board, place.fx, place.fy)
    end

    board.status = W.Label(board, "", { font = "small", color = "textDim" })
    board.status:SetPoint("TOPLEFT", board, "TOPLEFT", PAD, -(TITLE_H + PAD))
    board.status:SetPoint("RIGHT", board, "RIGHT", -PAD, 0)
    board.status:SetWordWrap(false)
    board.status:SetHeight(statusH)

    local header = CreateFrame("Frame", nil, board)
    header:SetHeight(HEAD_H)
    header:SetPoint("TOPLEFT", board.status, "BOTTOMLEFT", 0, -4)
    header:SetPoint("RIGHT", board, "RIGHT", -PAD, 0)
    local h1 = Cell(header, BOARD_NAME_W - 4, "LEFT")
    h1:SetRole("textDim")
    h1:SetText("Name")
    h1:SetPoint("LEFT", header, "LEFT", 4, 0)
    local h2 = Cell(header, listW - BOARD_NAME_W - 20, "LEFT")
    h2:SetRole("textDim")
    h2:SetText("Missing")
    h2:SetPoint("LEFT", header, "LEFT", BOARD_NAME_W, 0)

    board.scroll = W.Scroll(board, listW, BOARD_ROWS * ROW_H, { step = ROW_H * 3 })
    board.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)

    -- Open or closed is kept per character, so a board left up comes back after a reload.
    board:HookScript("OnShow", function()
        RC.Live("board", true)
        if ns.cdb then ns.cdb.windows.board.shown = true end
        BoardLabel()
        RefreshBoard()
    end)
    board:HookScript("OnHide", function()
        RC.Live("board", false)
        if ns.cdb then ns.cdb.windows.board.shown = false end
        BoardLabel()
    end)
    Tick(board, RefreshBoard)
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

function UI.ShowGrid()
    if not grid then BuildGrid() end
    if not RC.Snapshot() then RC.Scan("opened") end
    grid:Show()
end

function UI.ToggleGrid()
    if grid and grid:IsShown() then
        grid:Hide()
        return
    end
    UI.ShowGrid()
end

function UI.BoardShown()
    return board ~= nil and board:IsShown()
end

function UI.ToggleBoard()
    if board and board:IsShown() then
        board:Hide()
        return
    end
    if not board then BuildBoard() end
    if not RC.Snapshot() then RC.Scan("opened") end
    board:Show()
end

ns.OnReady("raidcheck window", function()
    if IC_HEADLESS then return end
    RC.OnChange("ui", function()
        RefreshGrid()
        RefreshBoard()
    end)
    if ns.cdb and ns.cdb.windows.board.shown then UI.ToggleBoard() end
end)
