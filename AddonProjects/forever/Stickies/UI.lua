local addonName, ns = ...

--[[
The notes on screen. One small panel per note, built from ICKit's widgets and drawn from
what Notes.lua says: this file decides nothing about a note, it shows one and passes on
what the player did to it.

    +--------------------------------+
    | Raid prep           2/5  -  ... |   title bar: drag it; right-click or ... for the menu
    | [x] flasks                    x |   a line: tick it, click the text to edit, x removes
    | [ ] food                      x |
    | [ Add a line               ]    |   type and press Enter
    +--------------------------------+

A panel is reused when its note goes, and a row is reused as lines come and go, so a busy
evening of ticking and adding creates no new frames. A note's place is this character's,
kept as fractions of the screen (W.GetPlace), for shared notes as well as their own.
]]

local Theme = LibStub("LibICTheme-1.0")
local W = LibStub("LibICWidgets-1.0")

local Notes = ns.Notes

local UI = {}
ns.UI = UI

local WIDTH = 230
local BAR_H = 22
local ROW_H = 18
local PAD = 6
local ADD_H = 20
local PROGRESS_W = 54

local stickies = {}     -- note id -> panel
local spare = {}        -- panels whose note is gone, ready for the next one

local function NoteOf(s)
    return Notes.Find(ns.db, ns.cdb, s.noteId)
end

--------------------------------------------------------------------------------
-- Editing a line or the title in place
--------------------------------------------------------------------------------

-- One edit box per panel, moved over whatever is being changed. s.editing is false,
-- "title", or the index of a line.
local function CancelEdit(s)
    if s.editing == false then return end
    s.editing = false
    s.editor:Hide()
end

local function CommitEdit(s, text)
    local note = NoteOf(s)
    local what = s.editing
    s.editing = false
    s.editor:Hide()
    s.editor:ClearFocus()
    if not note or what == false then return end
    if what == "title" then
        Notes.Rename(note, text)
    else
        Notes.EditLine(note, what, text)
    end
    UI.Layout(s)
end

local function BeginEdit(s, what, over, text, maxBytes)
    s.editing = what
    s.editor:ClearAllPoints()
    s.editor:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
    s.editor:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 0, 0)
    s.editor:SetMaxBytes(maxBytes + 1)
    s.editor:SetText(text or "")
    s.editor:Show()
    s.editor:SetFocus()
    s.editor:HighlightText()
end

--------------------------------------------------------------------------------
-- What the player does
--------------------------------------------------------------------------------

local function Toggle(s, index)
    local note = NoteOf(s)
    if note and Notes.ToggleLine(note, index) then UI.Layout(s) end
end

local function RemoveLine(s, index)
    local note = NoteOf(s)
    CancelEdit(s)
    if note and Notes.RemoveLine(note, index) then UI.Layout(s) end
end

local function EditLine(s, index)
    local note = NoteOf(s)
    local line = note and note.lines[index]
    if line then BeginEdit(s, index, s.rows[index].text, line.text, Notes.LIMITS.line) end
end

local function AddLine(s, text, box)
    local note = NoteOf(s)
    if not note then return end
    local ok, why = Notes.AddLine(note, text)
    if ok then
        box:SetText("")
        UI.Layout(s)
    elseif why then
        ns.Print(why)
    end
end

local function Rename(s)
    local note = NoteOf(s)
    if note then BeginEdit(s, "title", s.titleArea, note.title, Notes.LIMITS.title) end
end

--------------------------------------------------------------------------------
-- Tab and Shift-Tab: down and up the note
--------------------------------------------------------------------------------

-- Puts the cursor at a stop: a line to edit, or the box for adding one.
local function FocusStop(s, stop)
    local note = NoteOf(s)
    if not note then return end
    if stop > #note.lines then
        s.add:SetFocus()
    else
        EditLine(s, stop)
    end
end

-- Tab while editing a line or the title: keep what was typed, move to the next stop.
local function TabFromEditor(s, text, backwards)
    local what = s.editing
    CommitEdit(s, text)
    local note = NoteOf(s)
    if not note or what == false then return end
    local current = (what == "title") and 0 or what
    FocusStop(s, Notes.TabTarget(current, #note.lines, backwards))
end

-- Tab in the add box: anything typed becomes a line first, then on round the note.
local function TabFromAdd(s, box, backwards)
    local note = NoteOf(s)
    if not note then return end
    if (box:GetText() or ""):find("%S") then AddLine(s, box:GetText(), box) end
    local count = #note.lines
    if count == 0 then return end
    box:ClearFocus()
    FocusStop(s, Notes.TabTarget(count + 1, count, backwards))
end

--------------------------------------------------------------------------------
-- Drag a line to another place in the note
--------------------------------------------------------------------------------

-- The line the pointer is over, or the nearest end of the list.
local function PointerRow(s, count)
    local _, y = GetCursorPosition()
    local scale, top = s:GetEffectiveScale(), s:GetTop()
    if type(y) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
    return Notes.RowAt(top - (BAR_H + PAD) - y / scale, ROW_H, count)
end

-- A line across the note where the dragged line would land: above the target when it is
-- moving up, below it when moving down, nowhere when it would not move.
local function ShowDrop(s, from, to)
    if not to or to == from then
        s.dropLine:Hide()
        return
    end
    local edge = (to < from) and (to - 1) or to
    local y = -(BAR_H + PAD + edge * ROW_H) + 1
    s.dropLine:ClearAllPoints()
    s.dropLine:SetPoint("TOPLEFT", s, "TOPLEFT", PAD, y)
    s.dropLine:SetPoint("TOPRIGHT", s, "TOPRIGHT", -PAD, y)
    s.dropLine:Show()
end

local function FollowDrag(s)
    local note = NoteOf(s)
    if note and s.dragFrom ~= false then ShowDrop(s, s.dragFrom, PointerRow(s, #note.lines)) end
end

local function BeginDrag(s, index)
    local note = NoteOf(s)
    if not note or #note.lines < 2 or not s.rows[index] then return end
    CancelEdit(s)
    s.dragFrom = index
    s.rows[index].text:SetAlpha(0.4)
    s.rows[index].box:SetAlpha(0.4)
    local accent = Theme.Current().colors.accent
    s.dropLine:SetColorTexture(accent.r, accent.g, accent.b, 1)
    -- Runs only while a line is in the air.
    s:SetScript("OnUpdate", FollowDrag)
end

local function EndDrag(s)
    local from = s.dragFrom
    if from == false then return end
    s.dragFrom = false
    s:SetScript("OnUpdate", nil)
    s.dropLine:Hide()
    local note = NoteOf(s)
    if note then
        local to = PointerRow(s, #note.lines)
        if to then Notes.MoveLine(note, from, to) end
    end
    UI.Layout(s)
end

local function ToggleFold(s)
    local view = Notes.View(ns.cdb, s.noteId)
    CancelEdit(s)
    view.collapsed = not view.collapsed
    UI.Layout(s)
end

local function ClearDone(s)
    local note = NoteOf(s)
    if note and Notes.ClearDone(note) > 0 then UI.Layout(s) end
end

local function HideNote(s)
    local note = NoteOf(s)
    if not note then return end
    Notes.View(ns.cdb, s.noteId).hidden = true
    UI.Refresh()
    ns.Printf("#%d %s is hidden. /sticky show %d brings it back.", note.id, note.title, note.id)
end

local function ToggleShare(s)
    local note, scope = NoteOf(s)
    if not note then return end
    if scope == "character" then
        Notes.SetScope(ns.db, ns.cdb, note.id, "account")
        UI.Refresh()
        ns.Printf("#%d %s is now on every character.", note.id, note.title)
        return
    end
    -- Unsharing takes the note away from every other character, so it asks first.
    local id = note.id
    W.Confirm(string.format("Keep \"%s\" on this character only?\n\nIt will disappear from your other characters.",
        note.title), function()
        if Notes.SetScope(ns.db, ns.cdb, id, "character") then
            UI.Refresh()
            ns.Printf("#%d is now this character's alone.", id)
        end
    end)
end

local function DeleteNote(s)
    local note, scope = NoteOf(s)
    if not note then return end
    local id = note.id
    W.Confirm(string.format("Delete \"%s\"?%s\n\n/sticky restore brings back the last note deleted.", note.title,
        scope == "account" and "\n\nIt is shared, so it goes from every character." or ""), function()
        if Notes.Delete(ns.db, ns.cdb, id, time()) then UI.Refresh() end
    end)
end

local function OpenMenu(s)
    local note, scope = NoteOf(s)
    if not note then return end
    local done = Notes.Progress(note)
    local shown = W.Menu(s.bar, {
        { title = note.title },
        { text = "Rename", onClick = function() Rename(s) end },
        { text = scope == "account" and "Keep on this character only" or "Share with all characters",
          onClick = function() ToggleShare(s) end },
        { text = done > 0 and string.format("Clear completed (%d)", done) or "Clear completed",
          onClick = function() ClearDone(s) end },
        { text = "Hide", onClick = function() HideNote(s) end },
        { divider = true },
        { text = "Lock every note in place",
          checked = function() return ns.db.settings.locked == true end,
          onClick = function()
              ns.db.settings.locked = not ns.db.settings.locked
              UI.Refresh()
          end },
        { divider = true },
        { text = "Delete", onClick = function() DeleteNote(s) end },
    })
    if not shown then ns.Print("this client has no context menu; use the /sticky commands.") end
end

-- The panel was dropped somewhere: keep the place, and pin it by its top-left again so a
-- later change of height grows downwards from where the player put it.
local function Moved(s)
    local fx, fy = W.GetPlace(s)
    if not fx then return end
    local view = Notes.View(ns.cdb, s.noteId)
    view.x, view.y = fx, fy
    W.SetPlace(s, fx, fy)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function CreateSticky()
    local s = W.Panel(UIParent, { width = WIDTH, height = 60, movable = true, strata = "MEDIUM", onMoved = Moved })
    s:SetToplevel(true)
    s.noteId = 0
    s.rows = {}
    s.editing = false
    s.dragFrom = false
    s.dropLine = s:CreateTexture(nil, "OVERLAY")
    s.dropLine:SetHeight(2)
    s.dropLine:Hide()

    s.bar = W.Panel(s, { role = "raised", edge = false, height = BAR_H })
    s.bar:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    s.bar:SetPoint("TOPRIGHT", s, "TOPRIGHT", -1, -1)
    W.DragHandle(s.bar, s, { onRightClick = function() OpenMenu(s) end })
    W.Tooltip(s.bar, function(tip)
        local note, scope = NoteOf(s)
        if not note then return end
        tip:AddLine(note.title)
        tip:AddLine(scope == "account" and "Shared with every character" or "This character's", 0.8, 0.8, 0.8)
        tip:AddLine("Drag to move. Right-click for the menu.", 0.6, 0.6, 0.6)
    end)

    s.menuButton = W.Button(s.bar, "...", 20, 16, { kind = "flat", onClick = function() OpenMenu(s) end })
    s.menuButton:SetPoint("RIGHT", s.bar, "RIGHT", -2, 0)
    s.fold = W.Button(s.bar, "-", 16, 16, { kind = "flat", onClick = function() ToggleFold(s) end })
    s.fold:SetPoint("RIGHT", s.menuButton, "LEFT", -1, 0)
    s.progress = W.Label(s.bar, "", { font = "small", color = "textDim", justify = "RIGHT" })
    s.progress:SetWidth(PROGRESS_W)
    s.progress:SetPoint("RIGHT", s.fold, "LEFT", -4, 0)

    -- Where the title sits, and what the rename box covers: the bar, less the controls
    -- on its right (menu 20, fold 16, progress, and the gaps between them).
    s.titleArea = CreateFrame("Frame", nil, s.bar)
    s.titleArea:SetPoint("TOPLEFT", s.bar, "TOPLEFT", 4, -2)
    s.titleArea:SetPoint("BOTTOMRIGHT", s.bar, "BOTTOMRIGHT", -(2 + 20 + 1 + 16 + 4 + PROGRESS_W + 4), 2)
    s.title = W.Label(s.bar, "", { font = "button", color = "accent" })
    s.title:SetPoint("LEFT", s.titleArea, "LEFT", 4, 0)
    s.title:SetPoint("RIGHT", s.titleArea, "RIGHT", 0, 0)

    s.add = W.EditBox(s, WIDTH - 2 * PAD, ADD_H, {
        maxBytes = Notes.LIMITS.line,
        placeholder = "Add a line",
        onEnter = function(text, box) AddLine(s, text, box) end,
        onTab = function(box, backwards) TabFromAdd(s, box, backwards) end,
    })

    s.editor = W.EditBox(s, 100, ROW_H, {
        onEnter = function(text) CommitEdit(s, text) end,
        onEscape = function() CancelEdit(s) end,
        onFocusLost = function() CancelEdit(s) end,
        onTab = function(box, backwards) TabFromEditor(s, box:GetText() or "", backwards) end,
    })
    s.editor:SetFrameLevel((s:GetFrameLevel() or 0) + 10)
    s.editor:Hide()
    return s
end

-- Row i of a panel, built the first time a note has that many lines.
local function Row(s, i)
    local row = s.rows[i]
    if row then return row end
    row = { index = i, full = "" }
    local y = -(BAR_H + PAD + (i - 1) * ROW_H)

    row.box = W.CheckBox(s, { size = 13, onClick = function() Toggle(s, row.index) end })
    row.box:SetPoint("TOPLEFT", s, "TOPLEFT", PAD + 2, y - 2)

    row.remove = W.Button(s, "x", 16, 16, { kind = "flat", onClick = function() RemoveLine(s, row.index) end })
    row.remove:SetPoint("TOPRIGHT", s, "TOPRIGHT", -4, y - 1)
    W.Tooltip(row.remove, function(tip) tip:AddLine("Remove this line") end)

    row.text = W.Button(s, "", 100, ROW_H, {
        kind = "flat", justify = "LEFT", font = "body", textRole = "text",
        onClick = function() EditLine(s, row.index) end,
        onDragStart = function() BeginDrag(s, row.index) end,
        onDragStop = function() EndDrag(s) end,
    })
    -- Two opposite corners, so its height is the row's and nothing else's.
    row.text:SetPoint("TOPLEFT", s, "TOPLEFT", PAD + 20, y)
    row.text:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -22, y - ROW_H)
    W.Tooltip(row.text, function(tip)
        tip:AddLine(row.full, 1, 1, 1, true)
        tip:AddLine("Click to change it. Drag it to another place.", 0.6, 0.6, 0.6)
    end)

    s.rows[i] = row
    return row
end

local function ShowRow(row, shown)
    -- A row that was dimmed while it was being dragged comes back whole.
    row.box:SetAlpha(1)
    row.text:SetAlpha(1)
    if shown then
        row.box:Show()
        row.text:Show()
        row.remove:Show()
    else
        row.box:Hide()
        row.text:Hide()
        row.remove:Hide()
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- One panel from its note: title, progress, lines, height.
function UI.Layout(s)
    local note, scope = NoteOf(s)
    if not note then return end
    local view = Notes.View(ns.cdb, note.id)
    local done, total = Notes.Progress(note)

    s.title:SetText(note.title)
    s.progress:SetText((scope == "account" and "all  " or "") .. (total > 0 and (done .. "/" .. total) or ""))
    s.fold:SetLabel(view.collapsed and "+" or "-")
    s:SetLocked(ns.db.settings.locked == true)

    local shown = view.collapsed and 0 or #note.lines
    for i = 1, shown do
        local row, line = Row(s, i), note.lines[i]
        row.full = line.text
        row.box:SetChecked(line.done)
        row.text:SetLabel(line.text)
        row.text:SetTextRole(line.done and "done" or "text")
        ShowRow(row, true)
    end
    for i = shown + 1, #s.rows do ShowRow(s.rows[i], false) end

    if view.collapsed then
        s.add:Hide()
        s:SetHeight(BAR_H + 2)
    else
        local top = BAR_H + PAD + shown * ROW_H + 2
        s.add:ClearAllPoints()
        s.add:SetPoint("TOPLEFT", s, "TOPLEFT", PAD, -top)
        s.add:Show()
        s:SetHeight(top + ADD_H + PAD)
    end
end

-- Every note this character sees gets a panel; a panel whose note is gone is put aside.
function UI.Refresh()
    if not (ns.db and ns.cdb) then return end
    local seen = {}
    for index, entry in ipairs(Notes.All(ns.db, ns.cdb)) do
        local id = entry.note.id
        local s = stickies[id]
        if not s then
            s = table.remove(spare) or CreateSticky()
            s.noteId = id
            stickies[id] = s
        end
        seen[id] = true

        local view = Notes.View(ns.cdb, id)
        if view.x == nil or view.y == nil then view.x, view.y = Notes.Cascade(index) end
        UI.Layout(s)
        W.SetPlace(s, view.x, view.y)
        if view.hidden then s:Hide() else s:Show() end
    end
    for id, s in pairs(stickies) do
        if not seen[id] then
            CancelEdit(s)
            s:Hide()
            stickies[id] = nil
            spare[#spare + 1] = s
        end
    end
end

-- Puts the cursor in a note's add box, for a note that was just made.
function UI.FocusAdd(id)
    local s = stickies[id]
    if s and s:IsShown() then s.add:SetFocus() end
end

-- Gives the keyboard back: every box loses focus and an edit in progress is dropped.
function UI.DropFocus()
    for _, s in pairs(stickies) do
        CancelEdit(s)
        s.add:ClearFocus()
        s.editor:ClearFocus()
    end
end

-- A note's panel, for the cases.
function UI.PanelOf(id)
    return stickies[id]
end

-- How many panels are in use and how many are waiting, for the cases.
function UI.Counts()
    local live = 0
    for _ in pairs(stickies) do live = live + 1 end
    return live, #spare
end
