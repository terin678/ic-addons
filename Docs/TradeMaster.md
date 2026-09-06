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
is active at a time** and owns the bark: its bark template, interval, and advertised list are
what gets sent. **Invites cover every scanned book.** A request in Trade, a whisper, or party
chat is matched against each book; the one with the most hits invites, whispers with its own
templates, and books the order, so its recipes fill the trade. Both switches sit in the window
header as **Bark: ON/OFF** (active profession) and **Invites: ON/OFF** (all books).
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

### Reads the market

Every line in Trade chat is counted as either a **seller** (a crafter advertising: "LW LFW",
"JC lfw, full book", "will cut anything") or a **buyer** (someone asking for a profession or
an item). Attribution is by the professions the line names, so a leatherworker's bark counts
for Leatherworking even while Jewelcrafting is your active profession. Only the Trade channel
is read, and nothing is counted while TradeMaster is disabled.

The **Market** tab shows distinct sellers and buyers per profession over the last 15 minutes,
hour and day, with a label:

| Label | When |
| --- | --- |
| quiet | at most one seller |
| crowded | three or more sellers, and at least twice as many sellers as buyers |
| balanced | anything else |

Alongside it sits a **suggested** bark interval: longer when the channel is crowded, shorter
when there is demand and nobody answering it. It is advice. Barking always uses the interval
you set on the Bark tab, and nothing changes it for you. The same one-line summary appears in
the window's status bar, the minimap tooltip, beside the Bark tab's interval slider, and from
`/tm market`.

Counting keeps a day of samples, capped at 2000, in your saved variables. Distinct players
are counted, not posts, so one crafter reposting every three minutes does not read as a
crowded market.

### Knows your recipes

Scanning reads every recipe in the open profession window with its reagents, how many it
makes per craft, item quality, and whether it is Bind on Pickup. Rescanning merges: your
advertise/match choices and custom aliases survive. It runs automatically on window open
when it could learn something (empty book, a skill gained, or the book over 6 hours old).
`/tm scan` forces one.
Reading the window is done by the shared `ICLibs` addon (LibICTradeSkill), which must be
installed alongside TradeMaster; the zip includes it.

A recipe that needs a **Bind on Pickup reagent** you don't hold (Primal Nether, Nether Vortex,
...) can't be made for a customer, so it is never barked, and a request for it gets the
"not enough ..." whisper instead of an invite. Bags and bank count; the bank is known once
you have opened it this session. The Book row shows "needs ..." in red for these.

### Fills the trade window

When a customer with an open order opens a trade, TradeMaster adds their finished items
from your bags one stack per tick, re-scanning the bags each time so nothing is skipped
after a slot shifts. Whole stacks move (the game has no partial move), so a stack bigger
than the order is flagged. The trade window holds six items; an order needing more fills
what fits and tells you what is left for a second trade. Order lookup ignores name case,
so a manually typed lowercase name still matches the live trade partner.

A whisper naming only a cut prefix ("looking for jagged") that could mean several
unrelated gems is shown to you locally with the candidates, never answered automatically.

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

Hard vetoes (`LFW`, `WTS`, `will cut`, `will brew`, and the giveaway phrases `anyone
want`, `who wants`, `giving away`, `for free`, ...) never invite. A trailing `?` counts
against a seller but never stands as the request on its own: `[item]?` in Trade is as
often an offer as an ask. Beyond that, seller
signals (`all cuts`, `all potions`, a linked `Design:`/`Recipe:`/`Pattern:`/`Plans:`/
`Schematic:` item, three-plus links in one message) are weighed against buyer signals
(`WTB`, `need`, `have mats`, a trailing `?`) and the net decides. A player who posts the
same message twice inside the bark window is auto-flagged as a competitor. Someone
buying a **material** you happen to be able to make -- `WTB 5 stacks [Thick Leather]`,
which a leatherworker's book holds because leather converts -- is shopping, not asking
for a craft, and is dropped as *buying materials* unless something in the line speaks
of crafting: a verb, a crafter, mats in hand, or the profession's name. What counts as a
product is the profile's item classes (armour and bags for leatherworking, gems for
jewelcrafting). Every decision
is in the **Log** tab with the signals that fired. The whole vocabulary is editable per
profession in **Filter**.

### Talks to customers

Every reply below answers a **whisper** (or a party line). A Trade post is never
replied to: it gets a group invite, with the invite's own one-line whisper saying why,
or nothing at all. Somebody posting `WTB [Belt of Deep Shadow]` in Trade has not spoken
to you, and "not enough Nether Vortex, sorry" arriving from a stranger reads as spam.

| They say | TradeMaster replies |
| --- | --- |
| Names an item you have | Invites, whispers that it's on the way |
| Names several you have | Names **all** of them, up to three |
| `LF alch`, nothing named | Invites, asks what they need, waits |
| Answers that with something you lack | Says so, drops them from the group, remembers |
| Names an item you lack | "Sorry, I don't have that potion." No alternatives pitched. |
| Names several, you have some | "I can do X, but I don't have Y." |
| Types half a gem name (Jewelcrafting) | "Did you mean one of these?" |
| Asks for a specialization you lack | Nothing. Not your customer. |
| Just chatting about prices | Nothing. Not a question. |

The reply is decided over **everything** they named, not the first thing that matched:
all of it, some of it, or none. Answering two linked recipes by naming one is what got
asked back "can u do both ur just the belt?".

Every line is editable in **Invite**, per profession, with a Reset per field. Placeholders
are `{item}`, `{items}`, `{have}`, `{lack}`, `{player}`.

#### The pattern comes back with the answer

If they linked the **item**, the reply carries the pattern link for each thing you can make,
so hovering it shows the reagents and they can gather before trading. If they linked the
**pattern**, nothing is attached: they already have that list open.

The pattern link is read off the profession window when you scan a book, so **rescan each
book after updating to 1.9.0** to pick it up. Until you do, and on any client that does not
provide it, the reply names the reagents as text instead. Run `/tm probe` with a profession
window open to see whether this client provides it.

A whisper is cut off at 255 characters once links expand, so the reply names as many items as
fit and attaches as many patterns as fit after that. Anything left off is reported to you in
chat rather than silently truncated on the wire.

### Tracks orders

An order opens when someone asks and counts as *open* only once they join your group.
It does not matter who moved first. A customer who whispers "any JC on?" without naming
anything gets an invite and an order, and someone who skips the conversation entirely and
just opens a trade gets one the moment they put mats in the window. Nothing has to be
matched in chat for the order book to pick a customer up.

Quantities come from the mats they hand you, multiplied by how many the recipe makes per
craft, so a Major Protection Potion order counts in fives. If the mats fit two things
they asked for, TradeMaster asks you to set the split. If they hand over a reagent that
feeds several recipes you never discussed (a stack of Netherbloom, say), it does not
guess: the Orders tab lists the candidates and you pick one.

The panel under the order list is where an order is edited. Type part of a recipe name (or
shift-click an item into the box) and **Add** puts it on the order; if the name matches
several the panel offers them as buttons rather than guessing. Each line has **+**, **-**
and an **x** to drop it. **paid** takes an amount the way people say it, `25g`, `25g50s` or
`250` for gold, and corrects the money: the difference is written to the ledger as its own
entry, so the Income tab agrees without counting the sale twice and the history still says
what happened.

Finished and cancelled orders are hidden by default, not deleted. The toolbar says how many
are hidden and the **Finished** button shows them; that choice is saved, so a reload leaves
the tab looking the way you left it. Nothing is ever removed until you press **Prune Old**,
which drops finished orders older than `keepDoneDays` (30 by default).

The **Tracker** (`/tm tracker`, or middle-click the minimap icon) is a slim window you can
leave on screen: open orders, a tick box per item, ticking the last one closes the order.
Right-click a **name** to cancel that order; right-click an **item** to drop just that line,
for something stale or wrongly matched that nobody asked for. Without that, one bad line left
an order unable to complete, because there was nothing to tick it off with.

Orders waiting on someone to join get their own rows too, right-clickable to cancel. They are
not counted as open work — they may never join — but a static "waiting for them to join" line
with nothing clickable on it left the full Orders tab as the only way to close one out.

### Gives up on a customer who never came

A pending order expires after five minutes if the customer never joins the group
(`settings.orders.pendingTimeoutSec`, 0 to switch it off), or immediately if they decline the
invite. Left alone, one sits in the queue forever looking like live work. Only *pending* is
touched: once someone has actually grouped up, a slow reply is a different problem and
cancelling it out from under them would be wrong.

The decline is read by turning the client's own `ERR_DECLINE_GROUP_S` into a pattern, so it
works on any locale rather than only on an English client.

### Answers the question it asked

`LF LW` on its own gets an invite and "what item do you need?". If the answer is something
your book does not have, TradeMaster used to say nothing at all: the customer sat in the group
and the only way to find out was to search the book by hand.

It now replies. Answering a question you asked is not the same as volunteering an opinion, so
this reply goes out whether or not "suggest alternatives" is on. If there is nothing close to
offer either, it also gives the group slot back — `UninviteUnit`, never in combat, off with
`invite.dropOnNoMatch` — and remembers the answer.

**Remembering** works two ways, because one of them is not enough on its own.

The **person** is left alone for a day (`invite.declinedCooldownSec`, 0 to switch it off).
This is the one that matters: someone told no goes back to Trade and reposts the bare
`LF LW`, without the item in it, several times over. Nothing in those lines says what they
still want, and they still want it, so only the clock can answer. The Log shows the invite
blocked as "told them no 4h ago".

The **item** is remembered for longer. Naming it again, in any channel and with any wrapping,
is blocked even after the day is up. Twelve items per player, oldest dropped first.

**Clear Flags** on the Log tab forgets both, for everyone. That is separate from **Never
invite**, which you set by hand, has no expiry, and nothing here touches.

### Knows which specialist you are

"LF transmute alchemist for primal might cooldown" matched Primal Might out of the book and
opened an order, because nothing read the four words in front of it. A potion master can
still brew the elixir; they cannot give the customer the proc they came for. So a request
naming a specialization you do not hold gets no invite, no order and no reply. It shows in
the Log as vetoed, with the specialization it wanted as the reason.

Covered: Alchemy (potion, elixir, transmutation), Blacksmithing (armorsmith, weaponsmith and
the three weapon masteries), Leatherworking (dragonscale, elemental, tribal), Tailoring
(spellfire, mooncloth, shadoweave), Engineering (gnomish, goblin).

The words are deliberately narrow. A bare "transmute" is an ordinary request any alchemist
can take; "transmute master" is not. Anything linked or matched against your book is cut out
of the line first, because "[Spellfire Belt]" is an item and "spellfire tailor" is a
specialization and the word is the same one — reading the whole line would refuse the
customer who wanted the item.

**Which one you are** is read from your spellbook on login and whenever it changes, so
retraining is picked up on its own. The **Spec** button on the Professions tab cycles it:

| State | Means |
| --- | --- |
| `auto: potion` | read from your spellbook; the name after the colon is what it found |
| `potion` | you say you hold this one, whatever the spellbook says |
| `none` | you hold none, so every specialization request is somebody else's |
| `off` | stop weighing specializations for this profession at all |

`/tm spec` reports it, `/tm spec auto|none|off|<name>` sets it for the active profession.
If the spellbook cannot be read on this client, set it by hand — the button says `auto: none`
when detection came back empty, which is the same thing as `none` and worth checking.

### Shows you the message first

"LF JC" on its own is answered at once: an invite and "what do you need?" is exactly right
when they named nothing. The problem is the line that names something we could not place —
answering *that* with the same question says nobody was listening.

So the line is stripped of the profession's own words, the phrases that only mean "I am
buying", and ordinary filler. If nothing is left, it was a bare request and it is answered
immediately. If anything survives, a small window shows their line, what could not be
placed, and the message you would send with the text editable. **Invite and send** does
both, **Whisper only** skips the invite, **Skip** does nothing, and **Never invite** flags
them.

The **Review** button on the Invite tab sets when this happens: `never` sends straight away,
`when unsure` (the default) is the behaviour above, and `always` reviews every message.
Requests older than three minutes are dropped rather than answered late, and anything queued
behind the one on screen is counted in its header.

A line that names something no book of yours answers gets no invite and no whisper at all.
Anything in square brackets counts as naming something: an item link, a recipe link, or a
name typed out by hand. Recipe links are the reason this is not simply an item check —
shift-clicking a recipe out of a profession window posts a `|Htrade:` link with no item id
in it, so "LF LW [Leatherworking: Bindings of Lightning Reflexes]" looked like a bare "LF
LW" to anything hunting for items, and got asked what item it needed.

If you *do* know the recipe they linked, the name inside the brackets matches your book as
usual and they get the normal invite naming what you can make. If they link several and you
know only some, the bracketed names you cannot place are quoted back too, so the answer is
"I can do X, but I don't have Y" rather than a reply that mentions only X.

### Sets up the craft

Open a profession window with an order waiting and TradeMaster selects the next thing that
order needs and types the number of crafts into the create box. Nothing is crafted: the
Create click stays yours, and the number is a starting point you can overtype. A recipe
that makes five per craft counts in crafts, not in items, and if you are short of mats it
enters what you can make and says how many the order actually wants.

The order selected on the Orders tab wins; otherwise it takes the oldest open order this
profession can serve. Ticking a line off in the Tracker moves the window on to the next
one. If the recipe is hidden by the window's own search box or filters it says so rather
than selecting something else. `/tm craft` does it again on demand, and
`orders.focusOnOpen` turns it off.

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
| `/tm invite` | Toggle invites for every scanned profession |
| `/tm craft` | Select the next item an order needs in the open profession window |
| `/tm capture` | Record every Trade line, not only the ones a decision was made about |
| `/tm spec [auto\|none\|off\|<name>]` | Which specialization you answer to for the active profession |
| `/tm probe` | Say which profession-window functions this client provides, and what each missing one costs |
| `/tm market` | Seller and buyer counts per profession, and the suggested bark interval |
| `/tm log` / `/tm clearflags` | Recent decisions; clear competitor flags |
| `/tm orders` / `/tm order add\|done\|cancel\|reopen <id>` | Manage orders |
| `/tm order removeitem <id> <item name>` | Drop one line from an order, matched on part of the name |
| `/tm tracker` / `/tm income` | Tracker window; earnings summary |
| `/tm try <msg>` / `/tm trywhisper <msg>` / `/tm tryparty <msg>` | Test the classifier for the active profession. Sends nothing. |
| `/tm capture` | Record every Trade message and its verdict |
| `/tm test` | Run the built-in self test |
| `/tm help` / `/tm version` | Every command with a line each; addon and library versions |

## Tuning it

Everything lives in `TradeMasterDB` per character, with per-profession settings under
`professions.<key>.settings`. The **Filter** tab edits vetoes, seller and buyer signals,
profession phrases, and craft verbs directly; Reset restores the profession's defaults.

## Disclaimer

You are responsible for the content and frequency of everything this sends in your name.
Automated advertising, invites, and whispers must comply with the game's ToS and Code of
Conduct. Defaults are conservative: barking off, 180s interval with a 30s floor,
per-player invite/whisper cooldowns, and a warning after 60 whispers in a session.
