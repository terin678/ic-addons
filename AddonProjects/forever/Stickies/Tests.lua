local addonName, ns = ...

-- The cases: headless with scripts/run-tests.ps1 -Flavor forever -Addon Stickies, and in
-- game with /sticky test. Every one builds its own tables; none touches the saved notes.

local T = ns.Tests
local Notes = ns.Notes

-- A fresh pair of saved tables, as the store hands them over on a first run.
local function Book()
    local db = { nextId = 1, notes = {}, trash = {}, settings = { debug = false, locked = false } }
    local cdb = { notes = {}, view = {} }
    return db, cdb
end

local function Texts(note)
    local out = {}
    for i, line in ipairs(note.lines) do out[i] = line.text .. (line.done and "*" or "") end
    return table.concat(out, "|")
end

--------------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------------

T.Case("Notes.New: takes the account's counter, lands on the character, cleans the title", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "  |cffff0000Raid|r   prep ", "character", 100)
    T.Eq(note.id, 1, "the first id")
    T.Eq(db.nextId, 2, "and the counter moves on")
    T.Eq(note.title, "Raid prep", "colour off, spaces squeezed")
    T.Eq(note.created, 100, "stamped")
    T.Eq(#cdb.notes, 1, "it is this character's")
    T.Eq(#db.notes, 0, "not the account's")

    local shared = Notes.New(db, cdb, "", "account", 100)
    T.Eq(shared.id, 2, "ids never repeat across the two tables")
    T.Eq(shared.title, "Note", "a blank title gets a plain one")
    T.Eq(#db.notes, 1, "a shared note lives on the account")

    local long = Notes.New(db, cdb, string.rep("a", 80), "character", 100)
    T.Eq(#long.title, 40, "a title is cut to its limit")
end)

T.Case("Notes.New: refused at the limit, with a reason", function()
    local db, cdb = Book()
    for i = 1, Notes.LIMITS.notes do Notes.New(db, cdb, "n" .. i, i % 2 == 0 and "account" or "character", 0) end
    local note, why = Notes.New(db, cdb, "one too many", "character", 0)
    T.Eq(note, nil, "no twenty-first note")
    T.True(why:find("20 notes already", 1, true), "and it says why")
    T.Eq(db.nextId, Notes.LIMITS.notes + 1, "without spending an id on it")
end)

T.Case("Notes.Reconcile: the counter clears every id seen, orphan views go", function()
    -- The account file came back empty; the character kept its notes and a view of a
    -- shared note that is gone. A new note must not be handed an id already in use.
    local db = { notes = {}, trash = {}, settings = {} }
    local cdb = {
        notes = { { id = 5, title = "a", lines = {} }, { id = 7, title = "b", lines = {} } },
        view = { [5] = { x = 0.1, y = 0.1 }, [9] = { x = 0.2, y = 0.2 } },
    }
    local dropped = Notes.Reconcile(db, cdb)
    T.Eq(db.nextId, 10, "past the notes and past the orphan view")
    T.Eq(dropped, 1, "the view of a note that no longer exists is dropped")
    T.Eq(cdb.view[9], nil, "gone")
    T.True(cdb.view[5] ~= nil, "a live one is kept")

    local db2, cdb2 = Book()
    db2.nextId = 50
    Notes.New(db2, cdb2, "x", "character", 0)
    Notes.Reconcile(db2, cdb2)
    T.Eq(db2.nextId, 51, "a counter already ahead is left alone")

    local db3 = { notes = {}, trash = { { note = { id = 12, title = "t", lines = {} }, scope = "character" } }, settings = {} }
    local cdb3 = { notes = {}, view = {} }
    Notes.Reconcile(db3, cdb3)
    T.Eq(db3.nextId, 13, "a deleted note's id is not handed out either")
end)

T.Case("Notes.Find, All and Match: by id, in order, by what was typed", function()
    local db, cdb = Book()
    local a = Notes.New(db, cdb, "Raid prep", "character", 0)
    local b = Notes.New(db, cdb, "Shopping", "account", 0)
    local c = Notes.New(db, cdb, "Raid loot", "character", 0)

    local note, scope = Notes.Find(db, cdb, b.id)
    T.Eq(note, b, "found")
    T.Eq(scope, "account", "with where it lives")
    T.Eq(Notes.Find(db, cdb, 99), nil, "an id nobody has")

    local all = Notes.All(db, cdb)
    T.Eq(#all, 3, "both tables together")
    T.Eq(all[1].note.id .. all[2].note.id .. all[3].note.id, "123", "oldest first, whatever the scope")

    T.Eq(Notes.Match(db, cdb, "2"), b, "by number")
    T.Eq(Notes.Match(db, cdb, "#3"), c, "a hash in front is fine")
    T.Eq(Notes.Match(db, cdb, "shop"), b, "by the start of the title, any case")
    local none, _, why = Notes.Match(db, cdb, "raid")
    T.Eq(none, nil, "two titles start that way")
    T.True(why:find("2 notes start with", 1, true), "so it asks for the number")
    none, _, why = Notes.Match(db, cdb, "zzz")
    T.True(why:find("no note matches", 1, true), "and one that matches nothing says so")
    none, _, why = Notes.Match(db, cdb, "  ")
    T.True(why:find("which note", 1, true), "as does nothing typed")
    T.Eq(a.id, 1, "the first note is still the first")
end)

T.Case("Notes.Rename: cleaned and cut, a blank keeps the old title", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "Old", "character", 0)
    T.Eq(Notes.Rename(note, "  New |cff00ff00name|r "), true, "renamed")
    T.Eq(note.title, "New name", "cleaned")
    T.Eq(Notes.Rename(note, "   "), false, "a blank is refused")
    T.Eq(note.title, "New name", "and the title stays")
end)

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

T.Case("Notes.AddLine: trims, strips pipes, refuses blank, stops at the cap", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "n", "character", 0)
    T.Eq(Notes.AddLine(note, "  buy |cffff0000flasks|r | now "), true, "added")
    T.Eq(note.lines[1].text, "buy flasks now", "colour and the stray pipe gone")
    T.Eq(note.lines[1].done, false, "not done yet")

    local ok, why = Notes.AddLine(note, "   ")
    T.Eq(ok, false, "a blank line is refused")
    T.Eq(why, nil, "with nothing worth saying")

    Notes.AddLine(note, string.rep("x", 300))
    T.Eq(#note.lines[2].text, 120, "a long line is cut to its limit")

    for _ = 3, Notes.LIMITS.lines do Notes.AddLine(note, "filler") end
    ok, why = Notes.AddLine(note, "one too many")
    T.Eq(ok, false, "no twenty-first line")
    T.True(why:find("holds 20 lines", 1, true), "and it says why")
    T.Eq(#note.lines, Notes.LIMITS.lines, "the note is unchanged")
end)

T.Case("Notes.ToggleLine and Progress: ticks, unticks, and counts", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "n", "character", 0)
    local done, total = Notes.Progress(note)
    T.Eq(done .. "/" .. total, "0/0", "an empty note")

    Notes.AddLine(note, "a")
    Notes.AddLine(note, "b")
    local ok, now = Notes.ToggleLine(note, 2)
    T.Eq(ok, true, "ticked")
    T.Eq(now, true, "and it says the line is done")
    done, total = Notes.Progress(note)
    T.Eq(done .. "/" .. total, "1/2", "one of two")
    ok, now = Notes.ToggleLine(note, 2)
    T.Eq(now, false, "unticked again")
    T.Eq(Notes.ToggleLine(note, 9), false, "a line that is not there")
end)

T.Case("Notes.EditLine: changes the text, a blank or a bad index changes nothing", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "n", "character", 0)
    Notes.AddLine(note, "first")
    Notes.ToggleLine(note, 1)
    T.Eq(Notes.EditLine(note, 1, " second "), true, "edited")
    T.Eq(note.lines[1].text, "second", "cleaned")
    T.Eq(note.lines[1].done, true, "its tick is kept")
    T.Eq(Notes.EditLine(note, 1, ""), false, "a blank edit is refused")
    T.Eq(note.lines[1].text, "second", "and the old text stays")
    T.Eq(Notes.EditLine(note, 5, "x"), false, "no such line")
end)

T.Case("Notes.RemoveLine and MoveLine: at both ends", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "n", "character", 0)
    for _, text in ipairs({ "a", "b", "c", "d" }) do Notes.AddLine(note, text) end

    T.Eq(Notes.MoveLine(note, 1, 4), true, "first to last")
    T.Eq(Texts(note), "b|c|d|a", "the rest shift up")
    T.Eq(Notes.MoveLine(note, 4, 1), true, "and back")
    T.Eq(Texts(note), "a|b|c|d", "as it was")
    T.Eq(Notes.MoveLine(note, 0, 2), false, "off the front")
    T.Eq(Notes.MoveLine(note, 2, 5), false, "off the end")

    T.Eq(Notes.RemoveLine(note, 1), true, "the first goes")
    T.Eq(Notes.RemoveLine(note, 3), true, "and the last")
    T.Eq(Texts(note), "b|c", "leaving the middle")
    T.Eq(Notes.RemoveLine(note, 3), false, "nothing there now")
end)

T.Case("Notes.RowAt: the line under the pointer, or the nearest end", function()
    T.Eq(Notes.RowAt(0, 18, 4), 1, "the top of the list is the first line")
    T.Eq(Notes.RowAt(17.9, 18, 4), 1, "still the first, just above its bottom edge")
    T.Eq(Notes.RowAt(18, 18, 4), 2, "the second starts where the first ends")
    T.Eq(Notes.RowAt(60, 18, 4), 4, "the last")
    T.Eq(Notes.RowAt(-30, 18, 4), 1, "above the list lands at the top")
    T.Eq(Notes.RowAt(500, 18, 4), 4, "below it lands at the bottom")
    T.Eq(Notes.RowAt(10, 18, 0), nil, "no lines, no line")
    T.Eq(Notes.RowAt(nil, 18, 3), 1, "a pointer nobody could find is the top")
end)

T.Case("Notes.TabTarget: down the lines, into the add box, and round again", function()
    T.Eq(Notes.TabTarget(1, 3, false), 2, "Tab goes down a line")
    T.Eq(Notes.TabTarget(3, 3, false), 4, "from the last line into the add box")
    T.Eq(Notes.TabTarget(4, 3, false), 1, "and from the add box back to the top")
    T.Eq(Notes.TabTarget(2, 3, true), 1, "Shift-Tab goes up a line")
    T.Eq(Notes.TabTarget(1, 3, true), 4, "from the first line round to the add box")
    T.Eq(Notes.TabTarget(4, 3, true), 3, "and from the add box up to the last line")
    T.Eq(Notes.TabTarget(0, 3, false), 1, "the title is before the first line")
    T.Eq(Notes.TabTarget(0, 3, true), 4, "and after the add box, going backwards")
    T.Eq(Notes.TabTarget(0, 0, false), 1, "a note with no lines has only the add box")
end)

T.Case("Notes.ClearDone: the finished lines go, the rest keep their order", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "n", "character", 0)
    for _, text in ipairs({ "a", "b", "c", "d" }) do Notes.AddLine(note, text) end
    Notes.ToggleLine(note, 1)
    Notes.ToggleLine(note, 3)
    T.Eq(Notes.ClearDone(note), 2, "two were done")
    T.Eq(Texts(note), "b|d", "the others stay, in order")
    T.Eq(Notes.ClearDone(note), 0, "nothing more to clear")
end)

--------------------------------------------------------------------------------
-- Scope, deleting, places
--------------------------------------------------------------------------------

T.Case("Notes.SetScope: the same note with the same id, there and back", function()
    local db, cdb = Book()
    local note = Notes.New(db, cdb, "Shopping", "character", 0)
    Notes.AddLine(note, "herbs")
    local view = Notes.View(cdb, note.id)
    view.x, view.y = 0.4, 0.5

    T.Eq(Notes.SetScope(db, cdb, note.id, "account"), true, "shared")
    T.Eq(#cdb.notes, 0, "it left the character")
    T.Eq(db.notes[1], note, "and the very same table is on the account")
    T.Eq(note.id, 1, "with its id")
    T.Eq(cdb.view[1].x, 0.4, "and this character's place for it")
    T.Eq(Notes.SetScope(db, cdb, note.id, "account"), true, "sharing it again changes nothing")
    T.Eq(#db.notes, 1, "still one copy")

    T.Eq(Notes.SetScope(db, cdb, note.id, "character"), true, "kept on this character again")
    T.Eq(#db.notes, 0, "gone from the account")
    T.Eq(cdb.notes[1], note, "back where it started")
    local ok, why = Notes.SetScope(db, cdb, 99, "account")
    T.Eq(ok, false, "a note that is gone cannot be moved")
    T.True(why:find("gone", 1, true), "and it says so")
end)

T.Case("Notes.Delete and Restore: one slip can be undone, the trash is short", function()
    local db, cdb = Book()
    local a = Notes.New(db, cdb, "Keep", "character", 0)
    local b = Notes.New(db, cdb, "Slip", "account", 0)
    Notes.View(cdb, b.id).x = 0.3

    local ok = Notes.Delete(db, cdb, b.id, 500)
    T.Eq(ok, true, "deleted")
    T.Eq(#db.notes, 0, "gone from the account")
    T.Eq(cdb.view[b.id], nil, "and this character's view of it with it")
    T.Eq(db.trash[1].note, b, "kept in the trash")
    T.Eq(db.trash[1].scope, "account", "with where it lived")
    T.Eq(Notes.Delete(db, cdb, b.id, 500), false, "it cannot be deleted twice")

    local back, scope = Notes.Restore(db, cdb)
    T.Eq(back, b, "restored")
    T.Eq(scope, "account", "to the scope it had")
    T.Eq(db.notes[1], b, "on the account again")
    T.Eq(#db.trash, 0, "and out of the trash")
    local none, why = Notes.Restore(db, cdb)
    T.Eq(none, nil, "nothing left to restore")
    T.True(why:find("nothing has been deleted", 1, true), "said plainly")

    for i = 1, Notes.LIMITS.trash + 3 do
        local n = Notes.New(db, cdb, "t" .. i, "character", 0)
        Notes.Delete(db, cdb, n.id, i)
    end
    T.Eq(#db.trash, Notes.LIMITS.trash, "the trash keeps only the last few")
    T.Eq(db.trash[1].note.title, "t" .. (Notes.LIMITS.trash + 3), "most recent first")
    T.Eq(a.title, "Keep", "and a note nobody deleted is untouched")
end)

T.Case("Notes.View, Cascade, ToggleAll and ResetPlaces: where a character keeps its notes", function()
    local db, cdb = Book()
    local a = Notes.New(db, cdb, "a", "character", 0)
    local b = Notes.New(db, cdb, "b", "account", 0)

    local view = Notes.View(cdb, a.id)
    T.Eq(view.hidden, false, "a note starts shown")
    T.Eq(view.collapsed, false, "and open")
    T.Eq(Notes.View(cdb, a.id), view, "the same view every time")

    local x1, y1 = Notes.Cascade(1)
    local x2, y2 = Notes.Cascade(2)
    local x9 = Notes.Cascade(9)
    T.True(x2 > x1 and y2 > y1, "each new note steps down and right")
    T.Near(x9, x1, "and the ninth starts again rather than walk off the screen")
    T.True(x1 > 0 and x1 < 1 and y1 > 0 and y1 < 1, "all inside the screen")

    T.Eq(Notes.ToggleAll(db, cdb), "hidden", "nothing hidden: the bare command hides them all")
    T.Eq(Notes.View(cdb, b.id).hidden, true, "shared notes included, for this character")
    Notes.View(cdb, a.id).hidden = false
    T.Eq(Notes.ToggleAll(db, cdb), "shown", "one hidden: it shows them all")
    T.Eq(Notes.View(cdb, b.id).hidden, false, "every one")
    local edb, ecdb = Book()
    T.Eq(Notes.ToggleAll(edb, ecdb), "none", "and with no notes there is nothing to toggle")

    view.x, view.y = 0.4, 0.6
    Notes.ResetPlaces(cdb)
    T.Eq(view.x, nil, "a reset forgets the place")
    T.Eq(view.hidden, false, "and nothing else")
end)

T.Case("Notes.Describe and Welcome: a note as a line, and the note a first run starts with", function()
    local db, cdb = Book()
    local note = Notes.Welcome(db, cdb, 0)
    T.Eq(note.title, "Welcome", "the starter note")
    T.Eq(#note.lines, 4, "four lines of instructions")
    Notes.ToggleLine(note, 1)
    T.Eq(Notes.Describe(note, "character", nil), "#1 Welcome  1/4", "number, title, progress")
    T.Eq(Notes.Describe(note, "account", { hidden = true, collapsed = true }), "#1 Welcome  1/4, shared, hidden, folded",
        "and what else is true of it")
    local empty = Notes.New(db, cdb, "Empty", "character", 0)
    T.Eq(Notes.Describe(empty, "character", {}), "#2 Empty", "an empty note has no progress to show")
end)

T.Case("Core: the login lines", function()
    local lines = ns.LoadLines("0.1.0", 1, { sawFile = true })
    T.Eq(#lines, 1, "an ordinary load is one line")
    T.Eq(lines[1], "v0.1.0 loaded with 1 note. /sticky new starts one, /sticky help lists commands.", "singular")
    T.True(ns.LoadLines("0.1.0", 3, {})[1]:find("3 notes", 1, true), "plural")
    lines = ns.LoadLines("0.1.0", 0, { lost = true })
    T.Eq(#lines, 3, "a lost file is said twice over")
    T.True(lines[2]:find("did not load", 1, true), "what happened")
    T.True(lines[3]:find("Restart the client", 1, true), "and what to do first")
end)

T.Case("Launcher: the tooltip says how many notes there are", function()
    T.Eq(ns.Launcher.Summary(0, 0), "no notes yet", "none")
    T.Eq(ns.Launcher.Summary(1, 0), "1 note", "one")
    T.Eq(ns.Launcher.Summary(3, 1), "3 notes, 1 hidden", "some of them hidden")
    T.True(ns.Launcher.ICON:find("INV_Misc_Note", 1, true), "and its icon is a note")
end)

T.Case("Launcher: a left-click shows or hides, it never makes a note", function()
    T.Eq(ns.Launcher.ClickHint(3, 1), "Left-click to show all notes", "any hidden: a click shows them all")
    T.Eq(ns.Launcher.ClickHint(3, 0), "Left-click to hide all notes", "all showing: a click hides them")
    T.Eq(ns.Launcher.ClickHint(0, 0), "Right-click to make a note", "none yet: the menu is where one is made")

    -- The hint and the click follow one rule: what Notes.ToggleAll does.
    local db, cdb = Book()
    local a = Notes.New(db, cdb, "a", "character", 0)
    Notes.New(db, cdb, "b", "character", 0)
    Notes.View(cdb, a.id).hidden = true
    T.Eq(Notes.ToggleAll(db, cdb), "shown", "one hidden, and the click shows them all")
    T.Eq(Notes.ToggleAll(db, cdb), "hidden", "all showing, and the click hides them")
    T.Eq(Notes.Count(db, cdb), 2, "and neither made a note")
end)

--------------------------------------------------------------------------------
-- The panels, headless only
--------------------------------------------------------------------------------

-- In game this would draw made-up notes over the player's own, so it runs only under the
-- harness, where the frames are stubs. It catches a script error in the layout code,
-- which is all a stub can catch; how it looks is for a person.
if IC_HEADLESS then
    T.Case("UI: every note gets a panel, a deleted note gives its panel back", function()
        local realDB, realCDB = ns.db, ns.cdb
        local db, cdb = Book()
        ns.db, ns.cdb = db, cdb
        local ok, err = pcall(function()
            local a = Notes.New(db, cdb, "Raid prep", "character", 0)
            local b = Notes.New(db, cdb, "Shopping", "account", 0)
            Notes.AddLine(a, "flasks")
            Notes.AddLine(a, "food")
            Notes.ToggleLine(a, 1)
            ns.UI.Refresh()
            local live, waiting = ns.UI.Counts()
            T.Eq(live, 2, "a panel each")
            T.True(cdb.view[a.id].x ~= nil, "and each was given a starting place")

            -- Tab keeps what was typed and moves on; the last line hands over to the add box
            local s = ns.UI.PanelOf(a.id)
            local first = s.rows[1].text
            first:GetScript("OnClick")(first)
            T.Eq(s.editing, 1, "a click on a line edits it")
            s.editor:SetText("flasks and oil")
            s.editor:GetScript("OnTabPressed")(s.editor)
            T.Eq(a.lines[1].text, "flasks and oil", "Tab keeps what was typed")
            T.Eq(s.editing, 2, "and moves to the next line")
            s.editor:GetScript("OnTabPressed")(s.editor)
            T.Eq(s.editing, false, "Tab from the last line leaves for the add box")

            -- A line picked up and put down where the pointer cannot be found stays put
            first:GetScript("OnDragStart")(first)
            T.Eq(s.dragFrom, 1, "a line is picked up")
            first:GetScript("OnDragStop")(first)
            T.Eq(s.dragFrom, false, "and put down")
            T.Eq(Texts(a), "flasks and oil*|food", "with nothing moved")

            Notes.View(cdb, a.id).collapsed = true
            Notes.View(cdb, b.id).hidden = true
            ns.UI.Refresh()
            ns.UI.DropFocus()

            Notes.Delete(db, cdb, b.id, 0)
            ns.UI.Refresh()
            live, waiting = ns.UI.Counts()
            T.Eq(live, 1, "the deleted note's panel is no longer in use")
            T.Eq(waiting, 1, "and waits for the next note")

            Notes.New(db, cdb, "Another", "character", 0)
            ns.UI.Refresh()
            live, waiting = ns.UI.Counts()
            T.Eq(live, 2, "which takes the waiting panel")
            T.Eq(waiting, 0, "rather than building a new one")

            -- Leave no panel behind for the next case
            for _, entry in ipairs(Notes.All(db, cdb)) do Notes.Delete(db, cdb, entry.note.id, 0) end
            ns.UI.Refresh()
        end)
        ns.db, ns.cdb = realDB, realCDB
        if not ok then error(err, 0) end
    end)

    T.Case("Launcher: the minimap button is built once and can be hidden", function()
        ns.Launcher.Create()
        ns.Launcher.Create()
        T.Eq(ns.db.settings.minimap.hide, false, "it starts shown")
        T.Eq(ns.db.settings.minimap.angle, 215, "at its default place on the rim")
        ns.Launcher.SetShown(false)
        T.Eq(ns.db.settings.minimap.hide, true, "hiding it is remembered")
        ns.Launcher.SetShown(true)
        T.Eq(ns.db.settings.minimap.hide, false, "and so is showing it again")
    end)
end
