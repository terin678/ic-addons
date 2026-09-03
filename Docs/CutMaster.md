# CutMaster

A Jewelcrafting business assistant. Learns your cuts by scanning your own Jewelcrafting
book (no static gem data to go stale between patches), finds customers in Trade chat,
whispers, and party chat while ignoring competing jewelcrafters, reminds you to bark on
an interval, tracks orders with quantities derived from the mats people actually hand
you, and records what you earned. Built for TBC Anniversary (interface 20506).

## Install

`.\scripts\deploy.ps1 -Flavor anniversary -Addon CutMaster` links the folder into
`_anniversary_\Interface\AddOns`. Type `/cm` in game to open the window, or click the
gem icon on the minimap.

## Quick start

1. Open your Jewelcrafting window once. CutMaster scans it silently.
2. `/cm` opens the main window. The **Book** tab lists everything you know.
3. Pick what to advertise: the **Epic**, **Rare+**, **All**, and **None** buttons do it
   in bulk, or tick individual gems.
4. Set a key for **Send bark to Trade** under Esc, Key Bindings, CutMaster.
5. Check **Remind me when it's time to bark** in the Bark tab and set an interval.

## What it does

### Knows your cuts

Scanning reads every recipe in your Jewelcrafting window along with its reagents, item
quality, and whether it is Bind on Pickup. Rescanning merges: your advertise/match
choices and any custom aliases survive. It runs automatically on window open, but only
when it could learn something (empty book, a skill gained, or the book over 6 hours
old), and it restores your filter selections afterward. `/cm scan` forces one.

### Finds customers

Watches Trade chat, whispers, and party chat. Matches an item link, a full name,
shorthand ("bold ruby" for Bold Living Ruby), or a custom alias. Understands `LF JC`
and similar, where nobody names a gem at all.

### Ignores competing jewelcrafters

Hard vetoes (`LFW`, `WTS`, `will cut`, ...) never invite. Beyond that, seller signals
(`all cuts`, price-per-cut patterns, three-plus links in one message, a linked
`Design:` recipe) are weighed against buyer signals (`WTB`, `need`, `have mats`, a
trailing `?`) and the **net** decides the verdict, so a real customer can outweigh a
phrase that merely looks like an ad. A player who posts the same gem message twice
inside the bark window is auto-flagged as a competitor. Every decision is in the **Log**
tab with the signals that fired; everything is tunable in **Filter**.

### Talks to customers

| They say | CutMaster replies |
| --- | --- |
| Names a cut you have | Invites, whispers that it's on the way |
| `LF JC`, nothing named | Invites, asks what they need, waits |
| Names a cut you lack | "Sorry, I don't have that cut." No alternatives pitched. |
| Names several, you have some | "I can do X, but I don't have Y." |
| Types half a gem name | "Did you mean one of these?" |
| Just chatting about prices | Nothing. Not a question. |

Every line is editable in **Invite**, with a Reset per field. An empty line sends
nothing for that case.

### Tracks orders

An order opens when someone asks and counts as *open* only once they actually join
your group. Quantities come from the mats they hand you, not what they typed, because
people say "bold living ruby" and then trade three. If the mats fit two cuts they
asked for, CutMaster refuses to guess and asks you to set the split in **Orders**.

The **Tracker** (`/cm tracker`, or middle-click the minimap icon) is a slim window you
can leave on screen: open orders, a tick box per gem, ticking the last one closes the
order, right-click a name to cancel.

### Fills the trade window

Open a trade with someone who has an open order and CutMaster loads their finished cuts
for you: only gems on that order, never Bind on Pickup, and it re-checks the bag slot
immediately before adding.

### Records income

Gold from completed trades is logged per order and per customer. **Income** shows
all-time, 24h, 7d, average per gem, and top customers. Gross, mat costs not deducted.

### Gem stats

In the Jewelcrafting window, gem names are replaced with what they do (`+8 Agility`
instead of `Delicate Living Ruby`). Toggle with the gem icon on the window itself, or
`/cm stats`.

## What the client will not let it do

Two things here are protected-function limits, not bugs:

- **Barking can't fully automate.** `SendChatMessage` to a channel only works from a
  hardware event; a timer can't call it. So the interval only reminds you (sound +
  print), and the key binding, Bark Now, the minimap right-click, or `/cm send` do the
  actual sending.
- **CutMaster can't open your Jewelcrafting window itself** (`CastSpellByName` is
  protected too), hence scan-on-open rather than scan-on-demand.

Trade completion is also inferred rather than a real event: contents are snapshotted
when both sides have accepted, committed on close. Everything it applies is editable,
and closing an order is prompted rather than automatic.

## Commands

`/cm` or `/cutmaster`. `/cm help` lists these in game.

| Command | Effect |
| --- | --- |
| `/cm` | Open/close the window |
| `/cm disable` / `/cm enable` | Master switch: no invites, whispers, barks, order creation, or trade filling until re-enabled. Everything else (UI, scanning, `/cm try`) still works. |
| `/cm status` | Every toggle, book age, buffer counts |
| `/cm scan` | Scan the open Jewelcrafting window |
| `/cm adv epic\|rare\|all\|none` | Bulk-select what to advertise |
| `/cm adv +text` / `/cm adv -text` | Add/remove by name match |
| `/cm stats` | Toggle gem stats in the JC window |
| `/cm bark <seconds>` | Set the reminder interval (30-600) and enable |
| `/cm send` | Send a bark now |
| `/cm preview` | Preview the next bark without sending |
| `/cm invite` | Toggle auto-invite from Trade chat |
| `/cm log` | Recent decisions with score breakdowns |
| `/cm clearflags` | Clear the auto competitor flag from everyone |
| `/cm orders` / `/cm order add\|done\|cancel\|reopen <id>` | Manage orders |
| `/cm tracker` | Toggle the slim tracker window |
| `/cm income` | Earnings summary |
| `/cm match <text>` / `/cm try <msg>` / `/cm trywhisper <msg>` / `/cm tryparty <msg>` | Test the matcher/classifier. Sends nothing. |
| `/cm capture` | Record every Trade message and its verdict, for tuning |
| `/cm test` | Run the built-in self test |

## Tuning it

Everything lives in `CutMasterDB` per character. If it invites someone it shouldn't,
check **Log** for the signals that fired and add a word to the veto list in **Filter**.
If it misses a real customer, `/cm capture` records every Trade message including the
ones it ignored.

`filter.requireBuyerSignal` (default on) means a Trade message needs a buying signal,
not just a gem name. `invite.whisper.autoSuggest` (default off) offers alternatives
when you lack a cut; off because it reads as a sales pitch when nobody asked for one.

## Disclaimer

You are responsible for the content and frequency of everything this sends in your
name. Automated advertising, invites, and whispers must comply with the game's ToS and
Code of Conduct; excessive Trade chat use or unsolicited whispers can draw penalties.
Defaults are conservative: barking off, 180s interval with a 30s floor, per-player
invite/whisper cooldowns, and a warning after 60 whispers in a session.
