# TradeMaster

A crafting business assistant for any profession. Learns your recipes by scanning your
own profession windows, finds customers in Trade chat, whispers, and party chat while
ignoring competing crafters, reminds you to bark on an interval, tracks orders with
quantities taken from the mats people actually hand you, fills the trade window, and
records what you earned. Built for TBC Anniversary (interface 20506).

TradeMaster is the profession-agnostic generalisation of [CutMaster](CutMaster.md).
CutMaster stays as it is; improvements there are ported here.

## Professions

Supported in this version: Jewelcrafting, Alchemy, Blacksmithing, Tailoring,
Leatherworking, Engineering, Cooking. Enchanting is not supported yet: it produces no
item and is applied to the customer's gear in the trade window, which needs its own model.

Every supported profession window you open is scanned into its own book. **One profession
is active at a time**: only the active one barks, invites, books orders, and fills trades.
The others are scanned, browsable, and one click from becoming active. The first
profession you scan becomes active automatically.

```
/tm prof            list scanned professions, active one in green
/tm prof alchemy    make one active (name, key, or abbreviation)
```

The **Professions** tab shows the same list with a Make Active button per row. The minimap
icon changes to the active profession's icon. Bark, filter, and invite settings are kept
per profession, so switching does not mix vocabularies or templates.

## Install

`.\scripts\deploy.ps1 -Flavor anniversary -Addon TradeMaster` links the folder into
`_anniversary_\Interface\AddOns`. Type `/tm` in game to open the window, or click the
icon on the minimap.

If you used CutMaster, TradeMaster imports its book, advertise choices, aliases, orders,
players, and income into the Jewelcrafting profession the first time it loads, and leaves
CutMasterDB untouched. Do not run both at once: each watches Trade chat and each would
invite. TradeMaster prints a warning at login if CutMaster is also loaded.

## Quick start

1. Open a profession window once. TradeMaster scans it silently and makes it active.
2. `/tm` opens the main window. The **Book** tab lists everything you know.
3. Pick what to advertise: the bulk buttons (Rare+, All, None; Epic too for
   Jewelcrafting) do it in bulk, or tick individual items.
4. Set a key for **Send bark to Trade** under Esc, Key Bindings, TradeMaster.
5. Check **Remind me when it's time to bark** in the Bark tab and set an interval.

## What it does

### Knows your recipes

Scanning reads every recipe in the open profession window with its reagents, how many it
makes per craft, item quality, and whether it is Bind on Pickup. Rescanning merges: your
advertise/match choices and custom aliases survive. It runs automatically on window open
when it could learn something (empty book, a skill gained, or the book over 6 hours old).
`/tm scan` forces one.

The Book tab shows one book at a time (the **Book:** button cycles through every scanned
profession). **Sort:** in the bottom-right corner cycles Category (the window's own
headers), Name, Quality (best first), and Advertised (ticked items first, then quality).
Hovering a row shows the item tooltip, the reagents it takes, how many it makes, and its
advertise/match state. Bind on Pickup recipes are not listed: they cannot be traded, and
TradeMaster never barks, matches, or trades them.

### Finds customers

Watches Trade chat, whispers, and party chat for the active profession. Matches an item
link, a full name, or a custom alias. For Jewelcrafting it also understands shorthand
("bold ruby" for Bold Living Ruby) and gem families; other professions match on full
names, since "haste" on its own is ordinary chat. Understands `LF JC`, `LF alch`,
`any blacksmith online?` and similar, where nobody names an item.

### Ignores competing crafters

Hard vetoes (`LFW`, `WTS`, `will cut`, `will brew`, ...) never invite. Beyond that, seller
signals (`all cuts`, `all potions`, a linked `Design:`/`Recipe:`/`Pattern:`/`Plans:`/
`Schematic:` item, three-plus links in one message) are weighed against buyer signals
(`WTB`, `need`, `have mats`, a trailing `?`) and the net decides. A player who posts the
same message twice inside the bark window is auto-flagged as a competitor. Every decision
is in the **Log** tab with the signals that fired. The whole vocabulary is editable per
profession in **Filter**.

### Talks to customers

| They say | TradeMaster replies |
| --- | --- |
| Names an item you have | Invites, whispers that it's on the way |
| `LF alch`, nothing named | Invites, asks what they need, waits |
| Names an item you lack | "Sorry, I don't have that potion." No alternatives pitched. |
| Names several, you have some | "I can do X, but I don't have Y." |
| Types half a gem name (Jewelcrafting) | "Did you mean one of these?" |
| Just chatting about prices | Nothing. Not a question. |

Every line is editable in **Invite**, per profession, with a Reset per field. Placeholders
are `{item}`, `{items}`, `{have}`, `{lack}`, `{player}`.

### Tracks orders

An order opens when someone asks and counts as *open* only once they join your group.
Quantities come from the mats they hand you, multiplied by how many the recipe makes per
craft, so a Major Protection Potion order counts in fives. If the mats fit two things
they asked for, TradeMaster asks you to set the split. If they hand over a reagent that
feeds several recipes you never discussed (a stack of Netherbloom, say), it does not
guess: the Orders tab lists the candidates and you pick one.

The **Tracker** (`/tm tracker`, or middle-click the minimap icon) is a slim window you can
leave on screen: open orders, a tick box per item, ticking the last one closes the order.

### Fills the trade window

Open a trade with someone who has an open order and TradeMaster loads their finished items
for you: only items on that order, never Bind on Pickup, and it re-checks the bag slot
immediately before adding.

### Records income

Gold from completed trades is logged per order and per customer, across professions.
**Income** shows all-time, 24h, 7d, average per item, and top customers. Gross.

### Annotations

For Jewelcrafting, gem names in the profession window are replaced with what they do
(`+8 Agility` instead of `Delicate Living Ruby`). Toggle with the icon on the window or
`/tm annotate`. Other professions have no annotator yet, so the button hides for them.

## What the client will not let it do

- **Barking can't fully automate.** `SendChatMessage` to a channel only works from a
  hardware event. The interval only reminds you (sound + print); the key binding, Bark
  Now, the minimap right-click, or `/tm send` do the actual sending.
- **It can't open your profession window itself**, hence scan-on-open.

## Commands

`/tm` or `/trademaster`. `/tm help` lists these in game.

| Command | Effect |
| --- | --- |
| `/tm` | Open/close the window |
| `/tm prof [name]` | List scanned professions, or make one active |
| `/tm disable` / `/tm enable` | Master switch |
| `/tm status` | Every toggle, active profession, book age, buffer counts |
| `/tm scan` | Scan the open profession window |
| `/tm adv epic\|rare\|all\|none` / `+text` / `-text` | Bulk-select what to advertise |
| `/tm annotate` | Toggle annotations in the profession window |
| `/tm bark <seconds>` / `/tm send` / `/tm preview` | Reminder interval, send now, preview |
| `/tm invite` | Toggle auto-invite from Trade chat |
| `/tm log` / `/tm clearflags` | Recent decisions; clear competitor flags |
| `/tm orders` / `/tm order add\|done\|cancel\|reopen <id>` | Manage orders |
| `/tm tracker` / `/tm income` | Tracker window; earnings summary |
| `/tm try <msg>` / `/tm trywhisper <msg>` / `/tm tryparty <msg>` | Test the classifier for the active profession. Sends nothing. |
| `/tm capture` | Record every Trade message and its verdict |
| `/tm test` | Run the built-in self test |

## Tuning it

Everything lives in `TradeMasterDB` per character, with per-profession settings under
`professions.<key>.settings`. The **Filter** tab edits vetoes, seller and buyer signals,
profession phrases, and craft verbs directly; Reset restores the profession's defaults.

## Disclaimer

You are responsible for the content and frequency of everything this sends in your name.
Automated advertising, invites, and whispers must comply with the game's ToS and Code of
Conduct. Defaults are conservative: barking off, 180s interval with a 30s floor,
per-player invite/whisper cooldowns, and a warning after 60 whispers in a session.
