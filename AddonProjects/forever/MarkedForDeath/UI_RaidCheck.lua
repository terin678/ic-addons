local addonName, ns = ...

--[[
UI_RaidCheck: the raid check grid and buff board.
Owned by lane C (raid check). Frame module: builds nothing at file scope; the tab is
registered and the board made in the ns.OnReady hook below, which returns early on
IC_HEADLESS. Everything shown comes from RaidCheck's snapshot, which RaidCheckModel built;
this file only draws it.

    The grid    the main window's "Raid check" tab (lane G's ns.UI.AddTab): toolbar, status
                line, then a W.List with one row per member and one cell per column.
                /mfd check opens the window on it.
    The board   a small movable panel listing only the members missing something, its
                place saved per character (windows.board). /mfd check board.

Colours mean one thing each: green has it, red missing, grey could not be read (never
red), amber an older version, dim nothing expected. In the grid they are theme roles
(good, bad, textDim, warn, textDisabled); the board and tooltips use the fixed codes.
]]

ns.RaidCheckUI = ns.RaidCheckUI or {}
local UI = ns.RaidCheckUI
local RC = ns.RaidCheck
local Model = ns.RaidCheckModel

local W = LibStub("LibICWidgets-1.0")
local Theme = LibStub("LibICTheme-1.0")

local BOARD_NAME = "MarkedForDeathBuffBoard"
local ROW_H = 18                                -- pixels, every list row
local HEAD_H = 18                               -- the header row
local TITLE_H = 24
local TOOLBAR_H = 26
local STATUS_H = 14                             -- the status line under the toolbar
local PAD = 8
local BOARD_W, BOARD_ROWS = 300, 10
local BOARD_NAME_W = 110
local TICK = 10                                 -- seconds between redraws of the read's age

-- Cell widths by column kind, in pixels.
local KIND_W = { buff = 40, blessing = 84, flask = 104, food = 40, durability = 44, version = 48 }

-- Status colours, the same meaning on every surface (CODING_STANDARDS, User-facing text).
local STATUS_HEX = {
    ok = "ff44ff44", missing = "ffff4444", unknown = "ff999999", old = "ffffcc66", none = "ff666666",
}

-- The same meanings as theme colour roles, for the grid's cells.
local STATUS_ROLE = {
    ok = "good", missing = "bad", unknown = "textDim", old = "warn", none = "textDisabled",
}

-- For GameTooltip, which is dark on every theme.
local function Paint(status, text)
    return "|c" .. (STATUS_HEX[status] or STATUS_HEX.unknown) .. tostring(text or "") .. "|r"
end

-- For text on our own panels: the theme's colour for the status, so it reads on a light
-- theme too.
local function ThemePaint(status, text)
    local color = Theme.Current().colors[STATUS_ROLE[status] or STATUS_ROLE.unknown]
    return Theme.Hex(color) .. tostring(text or "") .. "|r"
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
    if snap.held then line = line .. " " .. ThemePaint("old", "Held: " .. snap.held .. ".") end
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

-- Not in UISpecialFrames: Escape leaves the board up through a raid.
local function Shell(name, title, width, height, onMoved)
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
    panel:Hide()
    return panel
end

--------------------------------------------------------------------------------
-- The grid (the main window's "check" tab, on W.List)
--------------------------------------------------------------------------------

local grid      -- { page, toolbar, status, list, lists, columns, columnKey, boardButton }

local function GridColumns()
    local snap = RC.Snapshot()
    if snap then return snap.ctx.columns end
    return Model.Columns(ns.db and ns.db.check and ns.db.check.columns)
end

-- Below the toolbar and the status line, the list takes the rest of the page.
local function ListHeight(pageH)
    return math.max(ROW_H * 3, pageH - TOOLBAR_H - STATUS_H - 4)
end

-- Pure. The List's columns from the model's: the name fills what the cells leave.
function UI.ListColumns(columns)
    local out = { { key = "name", label = "Name" } }
    for _, c in ipairs(columns) do
        out[#out + 1] = { key = c.key, label = c.label, width = KIND_W[c.kind] or 40,
            justify = (c.kind == "blessing" or c.kind == "flask") and "LEFT" or "CENTER" }
    end
    return out
end

local function NameRole(row)
    if #row.missing > 0 then return STATUS_ROLE.missing end
    if row.unknown > 0 then return STATUS_ROLE.unknown end
    return STATUS_ROLE.ok
end

-- Pure. A grid cell's text and theme role. Grey (textDim) is never red: an unknown or a
-- status the grid does not know is drawn as unknown.
function UI.GridCell(row, column)
    if column.key == "name" then return row.name, NameRole(row) end
    local cell = row.cells[column.key]
    if not cell then return "", nil end
    return cell.text or "", STATUS_ROLE[cell.status] or STATUS_ROLE.unknown
end

-- The List's columns are fixed when it is made, so each set of columns (a setting) has its
-- own, kept by column key and shown in turn; switching back reuses the one already made.
local function UseList(key, columns)
    if grid.list then grid.list:Hide() end
    local page = grid.page
    local made = grid.lists[key]
    if made then
        made:Resize(page:GetWidth(), ListHeight(page:GetHeight()))
        made:Show()
        grid.list = made
        return
    end
    grid.list = W.List(page, page:GetWidth(), ListHeight(page:GetHeight()), {
        columns = UI.ListColumns(columns),
        rowHeight = ROW_H,
        cell = UI.GridCell,
        tooltip = function(tip, row) RowTooltip(tip, row, grid.columns) end,
        empty = "Nobody read yet. Scan reads the group out of combat.",
    })
    grid.list:SetPoint("TOPLEFT", grid.status, "BOTTOMLEFT", 0, -4)
    grid.lists[key] = grid.list
end

local function RefreshGrid()
    if not grid or not grid.page:IsVisible() then return end
    local snap = RC.Snapshot()
    local columns = GridColumns()
    local key = {}
    for _, c in ipairs(columns) do key[#key + 1] = c.key end
    key = table.concat(key, ",")
    if key ~= grid.columnKey then
        grid.columnKey = key
        grid.columns = columns
        UseList(key, columns)
    end
    grid.status:SetText(StatusLine(snap))
    grid.list:SetItems(snap and snap.rows or {})
end

-- Lays the buttons left to right; returns them by `key`.
local function Toolbar(parent, buttons)
    local x, made = 0, {}
    for _, b in ipairs(buttons) do
        local button = W.Button(parent, b.text, b.width, 20, { kind = b.kind, onClick = b.onClick })
        button:SetPoint("LEFT", parent, "LEFT", x, 0)
        W.Tooltip(button, function(tip) tip:AddLine(b.text) tip:AddLine(b.tip, 1, 1, 1, true) end)
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

-- While a page or window is shown its "read Ns ago" is redrawn every TICK seconds; a
-- quiet group sends no event that would. The ticker stops when it hides.
-- Returns the start function, for a frame already showing when the hooks go on.
local function Tick(frame, redraw)
    local function Start(self)
        if self.icTicker or not (C_Timer and C_Timer.NewTicker) then return end
        self.icTicker = C_Timer.NewTicker(TICK, redraw)
    end
    frame:HookScript("OnShow", Start)
    frame:HookScript("OnHide", function(self)
        if self.icTicker then self.icTicker:Cancel() end
        self.icTicker = nil
    end)
    return Start
end

local function Scan()
    local ok, why = RC.Scan("scan")
    if not ok then ns.Printf("not read: %s.", why) end
end

-- UI_Main hands over the page the first time the tab shows, already sized.
local function BuildGridInto(page)
    grid = { page = page, lists = {} }

    grid.toolbar = CreateFrame("Frame", nil, page)
    grid.toolbar:SetHeight(TOOLBAR_H)
    grid.toolbar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    grid.toolbar:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    local made = Toolbar(grid.toolbar, {
        { text = "Scan", width = 60, kind = "accent", onClick = Scan,
          tip = "Read everyone's buffs now. Out of combat only." },
        { text = "Callout", width = 70, onClick = function() RC.Callout() end,
          tip = "Say who is missing what in the announce channel, one line per fix (Raid Lead only). Grey cells are never named." },
        { text = "Missing", width = 70, onClick = function() RC.Missing() end,
          tip = "Print who is missing what, for you only." },
        { text = "Ready check", width = 90, onClick = function() RC.ReadyCheck() end,
          tip = "Start the game's ready check (leader or assistant)." },
        { key = "board", text = "Hide board", width = 80, kind = "flat", onClick = function() UI.ToggleBoard() end,
          tip = "The small board: only the members missing something. It stays up when this window closes." },
    })
    grid.boardButton = made.board
    BoardLabel()

    grid.status = W.Label(page, "", { font = "small", color = "textDim" })
    grid.status:SetPoint("TOPLEFT", grid.toolbar, "BOTTOMLEFT", 0, 0)
    grid.status:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    grid.status:SetHeight(STATUS_H)
    grid.status:SetWordWrap(false)
    if grid.status.SetMaxLines then grid.status:SetMaxLines(1) end

    -- The page shows and hides with the tab and with the window, so the live events are
    -- on exactly while somebody can see the grid.
    local function Shown()
        RC.Live("grid", true)
        RefreshGrid()
    end
    page:HookScript("OnShow", Shown)
    page:HookScript("OnHide", function() RC.Live("grid", false) end)
    local startTick = Tick(page, function() grid.status:SetText(StatusLine(RC.Snapshot())) end)

    -- A tab click, or opening on the saved tab, shows the page before it is built, so
    -- that first OnShow has already gone by: do its work now.
    if page:IsVisible() then
        Shown()
        startTick(page)
    end
end

local function ResizeGrid(w, h)
    if grid and grid.list then grid.list:Resize(w, ListHeight(h)) end
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
    if unknown > 0 then line = line .. " " .. ThemePaint("unknown", unknown .. " not read in full.") end
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
        row.what:SetText(ThemePaint("missing", Model.MissingLine(data)))
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
    board = Shell(BOARD_NAME, "Buff board", BOARD_W, height, SaveBoard)
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

-- Opens the main window on the Raid check tab.
function UI.ShowGrid()
    if not (ns.UI and ns.UI.Open) then return end
    if not RC.Snapshot() then RC.Scan("opened") end
    ns.UI.Open("check")
end

-- Opens it, or closes the window when the Raid check tab is the one showing.
function UI.ToggleGrid()
    if not (ns.UI and ns.UI.Toggle) then return end
    if not RC.Snapshot() then RC.Scan("opened") end
    ns.UI.Toggle("check")
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
    -- Takes the "check" tab from UI_Main's placeholder (whichever ready hook runs first).
    if ns.UI and ns.UI.AddTab then
        local ok, why = ns.UI.AddTab("check", "Raid check", BuildGridInto,
            { refresh = RefreshGrid, onResize = ResizeGrid })
        if not ok then ns.Printf("the raid check tab was not added: %s.", tostring(why)) end
    end
    RC.OnChange("ui", function()
        RefreshGrid()
        RefreshBoard()
    end)
    if ns.cdb and ns.cdb.windows.board.shown then UI.ToggleBoard() end
end)
