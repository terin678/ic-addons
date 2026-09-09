# Malexis Auction Watcher

Tracks auction house prices for items you choose, keeps a long-term history, charts
periodic highs and lows, and works out the profit of converting materials into products.
Built for TBC Anniversary (interface 20506). Optional feeds from Auctionator and
TradeSkillMaster.

## Install

Extract the zip into `_anniversary_\Interface\AddOns` so you get
`AddOns\MalexisAuctionWatcher\MalexisAuctionWatcher.toc`. Type `/maw show` in game or
click the coin icon on the minimap.


## Window tabs

| Tab | What it shows |
| --- | --- |
| Materials | Items you buy. Today, low, average, high per unit. Green is cheap, amber is mid-range, red is expensive; cyan is under your low bound and magenta is over your high one. |
| Products | Items you sell. Same columns, colors inverted so high is green. |
| Stores | How many of each item you hold in bags, bank, and on the AH, what it is worth, and from the Schedule when it is next expected to sell dear and to be cheap to buy. |
| History | Chart of one item, or one recipe, over time: 30 or 90 days, by weekday, by day of month, by hour. Highlights the cheapest and priciest bucket. |
| Recipes | Material to product conversions with cost, AH net, profit, margin, and how many batches you can make now. |
| Movers | What to act on right now: cheap materials to buy, profitable recipes you can make, products you hold at a good price. Each row has a Buy, Convert, or List button. |
| Schedule | This week as a plan: which items are expected cheap or dear in which 4-hour block, from the last weeks' scans, and whether the blocks already behind you held. Behind a toggle, one item's whole week as a grid. |
| Settings | Every setting on one tab: the price feeds, the auction house cut, the Movers thresholds, and the Schedule's clock, hit rule and floors. |

The tabs run along the top as the navigation bar; the live one is gold. Under them sits
the control row: Scan AH, the per-tab scan, Sort, then the tab's option (Add Item or
Refresh) and the character-specific checkbox on the right. The window is one fixed size on
every tab, and how long ago you last scanned reads in the header beside the guild mark.

**Sorting.** Every list sorts by a column when you click its header, and a second click
turns the order round; an arrow marks the column. Rows with nothing in that column go
last either way, and a list with sections (Stores, Movers, the Schedule) sorts inside
each section. The choice is kept per tab until you change it. On Materials and Products
the Sort button then reads "Sort: Column" and clicking it goes back to the Movers or
manual order; elsewhere the tab's own order (Recipes by best margin, say) is what you get
before you click a header.

Every list is built from the shared widget library (see [ICLibs](ICLibs.md)): the column
headers stay put while the rows scroll, a row is one line that truncates rather than
wrapping, and the full text is in the hover tooltip. Rows are reused as you refresh
instead of being rebuilt, so a long list no longer grows the frame count every scan.

### Window size

The window is 1024x700, which is what the Recipes tab needs to show both TSM profit columns
at once. On a smaller monitor that covers most of the screen, so the window scales:

- **Drag the grip in the bottom-right corner.** The corner you are holding stays put and the
  window grows or shrinks away from it. Anything between 50% and 125% is allowed.
- **`/maw scale 75`** sets it exactly. `/maw scale` on its own reports the current size.

Whichever you use is saved for the account, so the window opens the same way next time. The
first time you ever open it, it shrinks itself far enough to fit your screen rather than
opening with its edges past the sides.

This scales rather than resizes: everything gets smaller together, text included, and the
columns keep their proportions. Docked in the auction house the window follows that frame's
size instead, so the grip is hidden there and `/maw scale` says why.

## Adding items

- Click "Add Item" on Materials or Products, or drag an item onto the drop row at the
  bottom of any list to add it with defaults.
- Click the low or high cell to set a custom bound. Custom bounds show a `*`. When you
  have not set one, the bound comes from TSM's averages (the lower of 60d and 14d for low,
  the higher for high) and shows a `~`; with no TSM data it falls back to the min and max
  of your scans. The same bounds drive every color grade, the Stores values, and the
  Movers tab, and the set-price dialog starts from them.
- Rows sort by mover position by default: Materials cheapest-in-range first, Products
  highest-in-range first, items with no range at the bottom. The "Sort" button in the
  control bar switches to the manual order you set with the arrows, and back.
- Arrows reorder rows (manual order), the refresh icon scans one item, X removes it.

## Scanning

At the auction house click "Scan AH" or type `/maw scan`. The button shows progress and
becomes a Cancel button while running. Starting another scan while one runs adds the new
items to the queue. Closing the auction house cancels the scan.

Expect about 3 seconds per item. The game client allows one auction query roughly every
3 seconds and the addon needs one exact-match query per item; nothing in the addon can
shorten that. Keep scans small with the per-tab and per-row scans below, and let
Auctionator's full scan feed prices in bulk.

The second button scans only what the current tab shows: "Scan Materials", "Scan
Products", "Scan All" on Stores, "Scan Recipes" for every item any recipe uses, and "Scan
Item" on History for the selected item. Each Materials, Products, and Recipes row also has
a refresh icon that scans just that row's items.

```
/maw scan            start, or add items to the running scan
/maw scan stop       cancel
/maw scan status     show state
```

## Where prices come from

Every price shows its source and time. Hover the Today cell, the item name on Stores, or a
chart bar.

| Source | Marking | Notes |
| --- | --- | --- |
| Your scans | no tag, blue bars | Exact-name queries at the AH |
| Auctionator | `[A]`, amber bars | Current price and up to 21 days of daily history for items Auctionator has scanned or searched |
| TSM | `[T]`, amber bars | Snapshot only. Its 14 day and 60 day averages appear as reference lines on the chart |

External prices become the Today value only if your last scan of that item is more than an
hour old; otherwise they go into history only.

Pulls happen on their own: at login, when you start tracking an item, when the auction
house opens and closes, and after every scan. TSM's AuctionDB figures load once per session
from the desktop app's file, so they change only at login; its Accounting figures move as
you buy and sell, which is why closing the auction house pulls again. A pull that finds
nothing keeps the last one that did, and the tooltip says so.

```
/maw sources                 show availability
/maw sources atr|tsm on|off  toggle a feed
/maw sources pull [atr|tsm]  pull now and print a per-item report
```

The History tab has "Pull Auctionator" and "Pull TSM" buttons that do the same.

**TSM stands in where nothing was scanned.** A recipe used to show `?` for its cost while a
single material had no scan. Now, when an item has no scan and no bound of your own, its
price is taken from TSM: for a material, the vendor's price if a vendor sells it, then the
14-day market value, then TSM's own material cost, then its crafting cost, then the 60-day
average; for a product, the market value then the 60-day average. A cost that leans on any
of these carries `~` on the Recipes tab and the tooltip names the items. Movers never act
on a stood-in price: an item nobody has scanned cannot become a Buy for being cheap
against its own average.

When TSM is loaded and enabled, Materials, Products, and Stores gain two columns right
after the item name: "TSM 60d" (historical) then "TSM 14d" (market value), followed by
Today, so a row reads long-term, recent, now. They are colored against your own low and
high bounds with the same gradient as Today, so a green TSM 14d on a material means the
wider market is cheaper than your recent scans. Hover a cell for the value, when it was
pulled, and your bounds. A dash means TSM has no data for that item yet.

On realms where TSM lacks realm-level Market Value or Historical, the columns fall back to
the region figures (region market average, region historical, then region sale average),
and the tooltip names which TSM field was used. The tooltip also lists everything else TSM
reported for the item: min buyout, region sale rate and sold per day, your own Accounting
buy and sell averages, sale rate and expires, vendor buy and sell, and TSM's material and
crafting costs.

Two more columns follow them. **Paid** on Materials is what the copies you hold cost you,
by TSM's Accounting (newest purchases first while you hold any; your all-time average when
you hold none). **Sold** on Products is what you sold it for on average. Both are `-` until
TSM has a purchase or sale of yours on record.

**Sale %** is the share of region-wide auctions of the item that actually sell. Green at
30% or better, amber above the Convert floor, red below it, and `-` when TSM recorded no
sales at all, which is the worst answer, not a missing one. Hover it for sold per day, the
region sale average, your own 180-day sale rate and how many of yours expired since you
last sold one. Region figures are for the whole region (Fresh-US here), not your realm.

## History

Days are your local calendar days, so a scan after midnight counts toward the new day and
the Today marker matches. Buckets recorded before 1.10.6 were keyed by UTC day, so evening
scans from that period may sit one day late; they age out with retention.

Prices are kept in daily buckets for 180 days by default (`/maw retention <days>`,
minimum 7) plus a per-hour-of-day accumulator. Weekday and day-of-month views are derived
from the daily buckets. The summary line names the cheapest and priciest bucket and says
when there are fewer than 3 samples, which is too few to trust.

### Picking what to watch

The dropdown groups tracked items by auction house category, the same headings the auction
house itself uses, because the class comes from the client rather than from a table here.
An item this client has never cached has no category to report, so it sits under **Other**
and moves to its real one the next time you open the menu: asking for the category is also
what asks the server for it. A category holding more than 24 items splits into alphabetical
chunks, since a classic dropdown does not scroll and would otherwise run off the screen.

The last entry is **Tracked Recipes**. What you are looking at, and which period, are saved:
the tab comes back where you left it.

### The recipe view

One recipe, three kinds of line:

- **Green**, bold: what one batch of the product sells for, after the auction house cut.
- **Red**, bold: what its materials cost, all of them together.
- **Thin**: each material on its own, priced times however many the recipe needs, so you can
  see which one moved.

Flat pale lines are each piece's **TSM 14-day average**, drawn in a washed-out version of
that piece's own colour so it reads as "that piece, elsewhere in time" rather than as another
series to work out. They are levels, not history: TSM keeps no daily record, so there is
nothing to plot over time. Each is scaled the way its line is, a batch after the auction house
cut and a material times how many the recipe needs, so they sit on the same axis. The batch
cost gets one only when every material you buy has TSM data, the same rule the cost line
follows. Hover any slot for both the 14-day and the 60-day figure per piece.

The gap between the two bold lines is the margin. Hover any slot for every line's value plus
the margin, which is listed but not drawn: it has its own scale and would flatten the two
lines it is the distance between.

A **break in a line** is a slot with no price for that item. The cost line breaks whenever
any material does, because a cost that is missing a material is not a cost — drawn as zero it
would read as a free craft. Vendor materials are folded into the cost at their fixed price
rather than drawn, since a fixed price is a flat line.

Prices here are daily averages, so the numbers sit close to the Recipes tab rather than equal
to it: that tab uses each item's latest observation. **Scan Tab** on a recipe scans the
product and every non-vendor material, not just one item.

```
/maw history [item or recipe]    open the chart, optionally on something specific
```

## Recipes

Profit per batch = product value after the auction house cut minus material cost, using
each item's latest price. Rows sort by margin, best first. Hover a recipe for the full
breakdown with sources.

A material that is bind on pickup, such as Primal Nether or Nether Vortex, is never on
the auction house, so it has no price to find. The recipe prices without it: the row is
marked **BoP**, the material cost is everything else, and the tooltip names what you have
to bring yourself. "Can make" counts it only if it is in your bags or bank. The History
chart leaves it out of the cost line the same way. Recipes imported before this had the
reagent as an ordinary material; they are re-read the first time they are priced.

The cut defaults to 5%, the faction auction house rate in the capitals. The neutral
auction houses in Gadgetzan, Booty Bay, and Everlook take 15%; set that with
`/maw ahcut 15` if you sell there. The "AH net" headers on Recipes and Stores show the
rate in use.

The "Presets..." menu offers:

- Motes -> Primals: seven recipes, 10 motes to 1 primal.
- Transmute: Primal Might: one each of Primal Earth, Water, Air, Fire, Mana.
- Alchemy: every TBC recipe with a tradeable product, by category (potions, elixirs,
  flasks, transmutes) or all at once. Reagents and batch sizes come from Wowhead's TBC
  Classic data and item names from Questie's database, so counts such as 2 Terocone for a
  Haste Potion or 5 vials for a batch of 5 Major Protection Potions are exact. Transmutes
  carry a note about the shared daily cooldown.
- Gem cuts: picker for TBC Jewelcrafting. Click a raw gem to add all its cuts, or add a
  whole tier. 123 cuts across 20 raw gems including the Earthstorm and Skyfire meta
  diamonds. Jewelcrafter-only bind-on-pickup gems are excluded.
- From your recipe book: every profession window you open is scanned into a per-character
  book (through the shared ICLibs library, the same reader TradeMaster uses), so this dialog
  works with the window closed. Pick a book, search, hover a row for the item tooltip and
  reagents, add one or all shown. Reagents and batch sizes come straight from the client,
  so this is the reliable way to get any profession's recipes in. "Scan open window"
  refreshes the book on demand. Enchanting is not supported since enchants are not items.
- Flipping guide watchlist: tracks the herbs, primals, gems, shards, and old-world
  consumables a TBC flipping guide singles out, without adding recipes.

"Add Recipe" builds a custom recipe: drag a product and up to five materials with counts.
The E button on a row opens the same dialog pre-filled so you can change the product,
batch size, or materials; Save replaces the recipe in place and keeps its name and notes.
Typing a vial name as a material prices it at vendor cost automatically.

Vials (Imbued, Crystal, Leaded, Empty) are priced at their vendor cost automatically, are
not tracked, and do not count toward "Can make".

Everything a recipe uses is tracked automatically. "Can make" counts bags plus bank; it does
not know about cooldowns or which patterns you have learned.

The refresh icon on a row scans that recipe's product and materials. "Scan Recipes" in the
control bar scans every item used by any recipe. "Refresh Table" recomputes the numbers
from the latest prices and your current bags and bank without scanning.

When TSM is loaded, two extra columns, "Profit 60d" and "Profit 14d", sit before Profit
and show what the batch would make if every item were priced at its TSM historical or
market average. Read left to right they give long-term, recent, then now.

The "Prices:" button switches the whole table between three price bases: Latest (each
item's most recent price from any source), TSM 14d, and TSM 60d. Under a TSM basis, items
TSM has no data for fall back to Latest. Hovering a recipe shows its profit under all three
bases side by side, so you can see whether a conversion is only profitable right now or
holds up against the longer averages. The button is disabled when TSM is not loaded.

With TSM on, a **Sells** column grades the product the way Sale % does on Products, and a
Mat cost with `~` was priced from TSM where nothing was scanned (see "Where prices come
from"). A recipe whose product does not sell is still listed here; it is Movers that
declines to suggest it.

```
/maw recipes
```

## Movers

Three lists, each built from the data on the other tabs:

- **Buy**: any tracked item, material or product, whose Today price is at or below 25% of
  the way from its low to its high. Cheap materials are for crafting; cheap products, such
  as raid consumables, are for stocking up. The Buy button opens the auction house Browse tab with an exact search for
  the item. It never buys on its own; you pick the listing.
- **Convert**: recipes with at least 10% margin and materials for at least one batch in
  bags plus bank. With TSM on, the product also has to sell: its region sale rate must be
  at least 10% (`/maw minsale <percent>`; 0 turns the gate off). A product TSM has recorded
  no sales of fails; one TSM has never been asked about passes, with "sale rate unknown" in
  the reason. The Convert button casts the recipe, or uses the item for mote combines.
  One click makes one batch. The game only lets an addon cast from a real click, and only
  out of combat, so the button is disabled while fighting.
- **List**: any tracked item at or above 75% of its range that you hold, so spare
  materials get listed when they spike, not just products. With TSM on, the reason adds
  how well it sells and how many of yours expired since your last sale.
  The List button switches to the Auctions tab, puts your first bag stack in the sell
  slot, and fills start and buyout from today's price undercut by 1 copper per unit. You
  set the duration and press Create Auction.

**Matures** is the other side of each trade, borrowed from the Schedule tab: for a Buy or
a Convert, the item's or product's next block expected to sell dear, with its hour, target,
the gain from today's price to that target, and how far off it is ("in 3d 16h"); for a
List, the next block expected cheap enough to buy back. A row reads "no block on the
schedule yet" until the item has a week profile.

Hover a name for the same tooltips as the other tabs. Buy and List need the auction house
open. "Refresh Table" recomputes without scanning.

```
/maw movers
```

## Schedule

Prices on a realm move with the week. Raids reset on Tuesday, so consumables climb Monday
night; materials sag mid-week; weekends bring more players and more listings. The
Schedule tab turns the last weeks of scans into a plan for this one.

**The grid.** Seven days by six 4-hour blocks. An item's expected price in a block is the
mean of that block's **weekly** means over the last 8 weeks (Settings), so a week in
which you scanned five times one evening counts once. A block needs 2 complete weeks
before it carries that expectation.

**Until then it is modelled** from the history the History tab already draws: the
weekday's average times the block's share of the day, read off the weekday and hour
views (a weekday or a block needs 3 samples to count; a block nobody scans takes the day's
average). So an item with months of scans has a full grid on day one, marked `~`, and each
block trades the model for its own weeks as they complete. A block with one week and no
model shows that week with `?`.

**The plan** reads as instructions: in this block, check the item's price and buy at or
under the target, or list at or over it. The target is the block's expected price; the
From column says whether it came from weeks of scans or the model.

From the item's own week profile, the blocks in the bottom quarter of its range are buys
and the top quarter sells, the same quarters Movers uses. A week whose spread is under 5%
is flat and schedules nothing. The plan shows one day at a time: a row of day tabs from
the week's first day, and under the chosen day a row of block tabs, all day or one of the
six. It opens on today, all day, and a `*` marks the current day and block. Each row has
the target, this week's actual once a scan has landed in it, and a status: ahead, now,
hit, miss, or no scan. A hit is an actual within 10% of the target (Settings).

Beside the block, the row names the **hour** inside it at which the item is usually
cheapest (for a buy) or dearest (for a sell), from its scans in that block, or from the
hour view until it has some; rows sort by that hour, and inside an hour by the margin in
the row's favour, best first. **Off by** is how far the actual sits from the target as the
price moved (under is negative), green when that favours the row and red when it does
not. The actual turns green or red the same way, and **Rows: On target** hides everything
else, so a long evening block shrinks to what you can act on now.

The **Then** column is the other half of the trade: for a buy, the item's next sell block
(day, block, hour, target) and the gain between the two targets before the auction house
cut; for a sell, the next buy block, so you know when to restock. "next" means the block
falls in the following week. Where a row's number came from (weeks of scans, or the
History model) is in its tooltip.

**Does the pattern hold?** Each block also judges its past weeks against each other, by
the same rule, and an item's pattern is the record over its scheduled blocks: "held 3 of
4 weeks". After three judged weeks, an item that held under the floor (50%, Settings) is
**set aside**: it drops off the plan, with the number that put it there, and comes back
when the record climbs. The grid still shows it.

**The clock.** The week runs on server time by default, because raid resets and most
players' evenings follow the realm's clock whoever is looking. Switch to your local clock
on the tab or in Settings; nothing is re-recorded, the grid is simply read under the other
clock. The week starts on Tuesday; Settings moves that.

Scans are what feed it: the tab's Scan button scans the items on this week's plan. The
store keeps each item's raw scans for the last nine weeks (a few hundred at most), so the
tab fills in over its first weeks and is not something to judge on day one.

```
/maw schedule
```

## Item tooltips

Hover a tracked item anywhere, in your bags, the bank, the auction house or a chat link,
and the tooltip ends with a short block from MAW: **Sell when** and **Buy when**, the
item's next dear and cheap blocks with their target price, how far off they are, and how
the target compares with today's price ("12% over now" for a sell, "15% under now" for a
buy). They are the same answers as the Stores tab's two columns, so an item needs a week
profile on the Schedule before either line appears; until then the block says "not enough
weeks yet", and an item whose week is flat says so. Items MAW is not tracking are left
alone. Auctionator's and TSM's own tooltip lines are untouched; MAW's come after them.

**Is it worth converting?** When the item is a material in a recipe MAW knows, one more
line per recipe says whether the batch is worth more as the product than sold as it is:
"Convert to Primal Life: +20% over selling as is" in green when the gain clears the
Movers margin, in gold with "barely worth the batch" when it is over nothing but under
that margin, and in red with "sell as is" when converting loses. The comparison is the
product's net after the house cut against the materials' own net after the cut, at
today's prices. A product gets the mirror line, "From 10 Mote of Life: +20% over its
materials", so a stack of primals says whether the motes would have fetched more. A
recipe missing a price says which one. At most three recipes are listed, the best
first, so which mote is worth turning into a primal is on the tooltip rather than in
your memory.

Switch it off on the Settings tab or with the command.

```
/maw tooltip on|off
```

## Settings

One tab for what used to be a list of slash commands: the Auctionator and TSM feeds; the
auction house cut, scan-on-open and days of history; the Movers buy and list percentages,
minimum margin and sale rate; and the Schedule's clock, first day of the week, hit
tolerance, weeks of expectation, weeks a block needs, the set-aside floor, and whether item
tooltips carry the next sell and buy blocks. Numbers
apply on Enter and say what they did; the commands keep working and write the same
settings.

```
/maw settings
```

## Other commands

```
/maw minsale <percent>    TSM sale rate a product needs before Movers suggests converting
/maw tooltip on|off       the next sell and buy blocks on item tooltips
/maw list                 list tracked items
/maw prices <item>        last 10 entries for an item
/maw add <name or link>   track an item (materials tab)
/maw remove <name>        stop tracking
/maw minimap              show or hide the minimap button
/maw scale <percent>      window size, 50 to 125
/maw debug                verbose chat output
/maw test                 run the built-in checks
/maw version              addon and library versions
/maw help
```

Right-click the minimap button to start or cancel a scan. Drag it to move it.

## Data

Account-wide by default. Tick "Character-Specific Data" to keep a separate list per
character; you are offered a copy of the account data the first time.

Each item keeps its recent prices, the daily and hourly history buckets, and since 1.23.0
`history.obs`, the raw scans of the last nine weeks that the Schedule tab reads.
