# Stickies

Sticky notes that stay on your screen in WoW Forever. Each note is a title and a checklist:
tick lines off as you do them, add more as you think of them. A note belongs to one
character, or to every character on your account.

## Install

Extract into `_classic_beta_\Interface\AddOns` so you get `AddOns\Stickies\Stickies.toc`.
Stickies needs **ICKit**, which goes beside it (`AddOns\ICKit`). Restart the client after
installing; a `/reload` does not pick up a new addon.

The first time you log in there is one note on screen, "Welcome", and its four lines are
the instructions.

## Using a note

| To | Do this |
| --- | --- |
| Tick a line off | Click its box. Click again to untick. |
| Add a line | Type in the box at the bottom of the note and press Enter. The cursor stays there, so you can add several. |
| Change a line | Click its text, edit, press Enter. Escape leaves it as it was. |
| Remove a line | Click the **x** at the end of it. |
| Move the note | Drag its title bar. |
| Fold it away | Click **-** in the title bar; **+** opens it again. |
| Rename, share, clear, hide, delete | Right-click the title bar, or click **...** |

The title bar shows how far along you are ("2/5"). A shared note says "all" beside it.

A line holds up to 120 characters and a note up to 20 lines; you can have 20 notes. Lines
are plain text: colour codes and item links are stripped to their words.

## Sharing a note between characters

A new note is this character's. **Share with all characters** in the menu puts it on every
character on the account: a shopping list, say. Each character keeps its own place for a
shared note, and can fold or hide it without affecting the others.

**Keep on this character only** takes a shared note away from your other characters, so it
asks first.

## The menu

| Item | What it does |
| --- | --- |
| Rename | Edit the title in place. |
| Share with all characters / Keep on this character only | Move the note between this character and the account. |
| Clear completed | Remove every ticked line. |
| Hide | Take the note off screen. `/sticky show` brings it back. |
| Lock every note in place | Stop notes being dragged, so a click in a fight never moves one. |
| Delete | Delete the note, after asking. `/sticky restore` brings back the last one deleted. |

## Commands

```
/sticky                show every note, or hide them all if none is hidden
/sticky new [title]    start a note on this character
/sticky list           every note with its number
/sticky show [note]    show one note, by number or the start of its title, or all of them
/sticky hide [note]    hide one note, or all of them
/sticky lock           pin every note where it is; /sticky unlock frees them
/sticky reset          put every note back at its starting place
/sticky restore        bring back the last note deleted (the last ten are kept)
/sticky test           run the built-in checks
/sticky help
```

`/stickies` works too.

## How it looks

Stickies is drawn in ICKit's theme, which is the account's: **Forever** by default, the
game's own colours. `/ickit theme paper` turns every note into a yellow sticky note, and
`/ickit theme impulse` gives guild members the Impulse Control colours. See
[ICKit](ICKit.md).

## In combat

When a fight starts, any box you were typing in lets go of the keyboard, so your movement
keys work. What you had typed into an unfinished edit is dropped; a line you were adding
stays in its box. Notes do nothing while the game is idle: no timers, no per-frame work.

## Data

Shared notes and the trash are in the account's `SavedVariables\Stickies.lua`; a
character's own notes, and where it keeps every note it sees, are in that character's
`SavedVariables\Stickies.lua`. A note's place is stored as a fraction of the screen, so it
survives a change of resolution or interface scale.
