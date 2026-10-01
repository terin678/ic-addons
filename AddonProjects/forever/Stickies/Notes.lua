local addonName, ns = ...

--[[
The notes model. Pure: every function takes the tables it works on and touches nothing
else, so each has a headless case and the window only draws what this file decides.

    db   the account's saved table       { nextId, notes = { note }, trash = { entry }, settings }
    cdb  this character's saved table    { notes = { note }, view = { [id] = view } }

    note  = { id, title, created, lines = { { text, done }, ... } }
    view  = { x, y, collapsed, hidden }      where this character keeps a note, shared or not
    entry = { note, scope, at }              a deleted note, most recent first

A note's scope is where it lives: in db.notes it is shared with every character, in
cdb.notes it is this character's. There is no scope field to disagree with that. Ids come
from one counter on the account, never reused, so a note keeps its id when it changes scope
and a character's view of it stays attached.

Every operation that can be refused returns ok, reason. A nil reason means there is
nothing worth saying (a blank line was typed).
]]

local Util = LibStub("LibICUtil-1.0")

local Notes = {}
ns.Notes = Notes

Notes.LIMITS = { notes = 20, lines = 20, title = 40, line = 120, trash = 10 }
Notes.UNTITLED = "Note"

local LIMITS = Notes.LIMITS

--------------------------------------------------------------------------------
-- Finding
--------------------------------------------------------------------------------

-- note, scope ("character" or "account"), index in its list; nil when there is none.
function Notes.Find(db, cdb, id)
    for i, note in ipairs(cdb.notes) do
        if note.id == id then return note, "character", i end
    end
    for i, note in ipairs(db.notes) do
        if note.id == id then return note, "account", i end
    end
    return nil
end

-- Every note this character sees, as { note, scope }, oldest first.
function Notes.All(db, cdb)
    local out = {}
    for _, note in ipairs(db.notes) do out[#out + 1] = { note = note, scope = "account" } end
    for _, note in ipairs(cdb.notes) do out[#out + 1] = { note = note, scope = "character" } end
    table.sort(out, function(a, b) return a.note.id < b.note.id end)
    return out
end

function Notes.Count(db, cdb)
    return #db.notes + #cdb.notes
end

-- A note from what a player typed after a command: its number, or the start of its
-- title in any case. Returns note, scope, or nil and why not.
function Notes.Match(db, cdb, text)
    local want = Util.Trim(text):lower():gsub("^#", "")
    if want == "" then return nil, nil, "which note? Give its number or the start of its title." end
    local id = tonumber(want)
    if id then
        local note, scope = Notes.Find(db, cdb, id)
        if note then return note, scope end
    end
    local found, foundScope, matches = nil, nil, 0
    for _, entry in ipairs(Notes.All(db, cdb)) do
        if entry.note.title:lower():sub(1, #want) == want then
            found, foundScope, matches = found or entry.note, foundScope or entry.scope, matches + 1
        end
    end
    if matches == 1 then return found, foundScope end
    if matches > 1 then
        return nil, nil, string.format("%d notes start with \"%s\"; use the number.", matches, want)
    end
    return nil, nil, string.format("no note matches \"%s\".", want)
end

--------------------------------------------------------------------------------
-- Load time
--------------------------------------------------------------------------------

local function MaxId(db, cdb)
    local max = 0
    local function see(id)
        if type(id) == "number" and id > max then max = id end
    end
    for _, note in ipairs(db.notes) do see(note.id) end
    for _, note in ipairs(cdb.notes) do see(note.id) end
    for _, entry in ipairs(db.trash) do see(entry.note and entry.note.id) end
    for id in pairs(cdb.view) do see(id) end
    return max
end

--[[
Run once when the saved tables arrive. Raises the id counter past every id either table
has seen, so an account file that came back empty beside a character that kept its notes
cannot hand an old id to a new note; then drops this character's views of notes that no
longer exist. Returns how many views it dropped.
]]
function Notes.Reconcile(db, cdb)
    db.notes, db.trash = db.notes or {}, db.trash or {}
    cdb.notes, cdb.view = cdb.notes or {}, cdb.view or {}
    local max = MaxId(db, cdb)
    if (tonumber(db.nextId) or 1) <= max then db.nextId = max + 1 end
    local dropped = 0
    for id in pairs(cdb.view) do
        if not Notes.Find(db, cdb, id) then
            cdb.view[id] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

--------------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------------

local function TakeId(db)
    local id = tonumber(db.nextId) or 1
    db.nextId = id + 1
    return id
end

local function CleanTitle(title)
    local clean = Util.Clean(title, LIMITS.title)
    if clean == "" then return Notes.UNTITLED end
    return clean
end

-- A new, empty note. scope is "account" to share it; anything else is this character's.
function Notes.New(db, cdb, title, scope, now)
    if Notes.Count(db, cdb) >= LIMITS.notes then
        return nil, string.format("that is %d notes already; delete one first.", LIMITS.notes)
    end
    local note = { id = TakeId(db), title = CleanTitle(title), created = now or 0, lines = {} }
    local list = (scope == "account") and db.notes or cdb.notes
    list[#list + 1] = note
    return note
end

-- A blank title keeps the old one.
function Notes.Rename(note, title)
    local clean = Util.Clean(title, LIMITS.title)
    if clean == "" then return false end
    note.title = clean
    return true
end

--[[
Moves a note between this character and the whole account. It is the same note with the
same id, so this character's view of it carries over. Unsharing takes it away from every
other character, which the menu says before it does it.
]]
function Notes.SetScope(db, cdb, id, scope)
    local note, current, index = Notes.Find(db, cdb, id)
    if not note then return false, "that note is gone." end
    scope = (scope == "account") and "account" or "character"
    if current == scope then return true end
    table.remove(current == "account" and db.notes or cdb.notes, index)
    local target = (scope == "account") and db.notes or cdb.notes
    target[#target + 1] = note
    return true
end

-- Deleted notes go to a short trash on the account, most recent first, so one slip can
-- be undone. This character's view of the note goes with it.
function Notes.Delete(db, cdb, id, now)
    local note, scope, index = Notes.Find(db, cdb, id)
    if not note then return false, "that note is gone." end
    table.remove(scope == "account" and db.notes or cdb.notes, index)
    table.insert(db.trash, 1, { note = note, scope = scope, at = now or 0 })
    while #db.trash > LIMITS.trash do table.remove(db.trash) end
    cdb.view[id] = nil
    return true, note
end

-- Brings back the most recently deleted note, to the scope it had. Returns the note.
function Notes.Restore(db, cdb)
    local entry = db.trash[1]
    if not entry then return nil, "nothing has been deleted." end
    if Notes.Count(db, cdb) >= LIMITS.notes then
        return nil, string.format("that is %d notes already; delete one first.", LIMITS.notes)
    end
    table.remove(db.trash, 1)
    local note = entry.note
    -- An id cannot normally be in use again, but a note is never brought back on top of
    -- another: it takes a new one instead.
    if Notes.Find(db, cdb, note.id) then note.id = TakeId(db) end
    local list = (entry.scope == "account") and db.notes or cdb.notes
    list[#list + 1] = note
    return note, entry.scope
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

function Notes.AddLine(note, text)
    local clean = Util.Clean(text, LIMITS.line)
    if clean == "" then return false end
    if #note.lines >= LIMITS.lines then
        return false, string.format("a note holds %d lines; clear the finished ones first.", LIMITS.lines)
    end
    note.lines[#note.lines + 1] = { text = clean, done = false }
    return true
end

-- Returns ok, and whether the line is now done.
function Notes.ToggleLine(note, index)
    local line = note.lines[index]
    if not line then return false end
    line.done = not line.done
    return true, line.done
end

-- A blank edit keeps the old text.
function Notes.EditLine(note, index, text)
    local line = note.lines[index]
    if not line then return false end
    local clean = Util.Clean(text, LIMITS.line)
    if clean == "" then return false end
    line.text = clean
    return true
end

function Notes.RemoveLine(note, index)
    if not note.lines[index] then return false end
    table.remove(note.lines, index)
    return true
end

function Notes.MoveLine(note, from, to)
    return Util.Move(note.lines, from, to)
end

-- Drops every finished line, keeping the rest in order. Returns how many went.
function Notes.ClearDone(note)
    local kept = {}
    for _, line in ipairs(note.lines) do
        if not line.done then kept[#kept + 1] = line end
    end
    local removed = #note.lines - #kept
    note.lines = kept
    return removed
end

-- done, total
function Notes.Progress(note)
    local done = 0
    for _, line in ipairs(note.lines) do
        if line.done then done = done + 1 end
    end
    return done, #note.lines
end

--------------------------------------------------------------------------------
-- Where a character keeps a note
--------------------------------------------------------------------------------

function Notes.View(cdb, id)
    local view = cdb.view[id]
    if not view then
        view = { collapsed = false, hidden = false }
        cdb.view[id] = view
    end
    return view
end

-- Where the nth note goes when this character has not placed it: a short diagonal, as
-- fractions of the screen, that starts again after eight so nothing walks off the edge.
function Notes.Cascade(index)
    local step = ((tonumber(index) or 1) - 1) % 8
    return 0.30 + step * 0.025, 0.18 + step * 0.035
end

-- The bare command: if any note is hidden, show them all; otherwise hide them all.
-- Returns "shown", "hidden", or "none" when there is nothing to toggle.
function Notes.ToggleAll(db, cdb)
    local all = Notes.All(db, cdb)
    if #all == 0 then return "none" end
    local anyHidden = false
    for _, entry in ipairs(all) do
        if Notes.View(cdb, entry.note.id).hidden then anyHidden = true end
    end
    for _, entry in ipairs(all) do
        Notes.View(cdb, entry.note.id).hidden = not anyHidden
    end
    return anyHidden and "shown" or "hidden"
end

-- Forgets where this character put every note, so each goes back to its starting place.
function Notes.ResetPlaces(cdb)
    for _, view in pairs(cdb.view) do
        view.x, view.y = nil, nil
    end
end

--------------------------------------------------------------------------------
-- Saying
--------------------------------------------------------------------------------

-- One note as a line of /sticky list: "#3 Raid prep  2/5, shared, hidden".
function Notes.Describe(note, scope, view)
    local done, total = Notes.Progress(note)
    local text = string.format("#%d %s", note.id, note.title)
    if total > 0 then text = text .. string.format("  %d/%d", done, total) end
    if scope == "account" then text = text .. ", shared" end
    if view and view.hidden then text = text .. ", hidden" end
    if view and view.collapsed then text = text .. ", folded" end
    return text
end

-- The note a first run starts with, which is also the instructions.
function Notes.Welcome(db, cdb, now)
    local note = Notes.New(db, cdb, "Welcome", "character", now)
    if not note then return nil end
    Notes.AddLine(note, "Tick a line off with its box")
    Notes.AddLine(note, "Click a line to change it")
    Notes.AddLine(note, "Type below and press Enter to add one")
    Notes.AddLine(note, "Drag the title; right-click it for more")
    return note
end
