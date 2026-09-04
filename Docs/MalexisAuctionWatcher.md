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
| Stores | How many of each item you hold in bags, bank, and on the AH, and what it is worth. |
| History | Chart of one item, or one recipe, over time: 30 or 90 days, by weekday, by day of month, by hour. Highlights the cheapest and priciest bucket. |
| Recipes | Material to product conversions with cost, AH net, profit, margin, and how many batches you can make now. |
| Movers | What to act on right now: cheap materials to buy, profitable recipes you can make, products you hold at a good price. Each row has a Buy, Convert, or List button. |

The tabs run along the top as the navigation bar; the live one is gold. Under them sits
the control row: Scan AH, the per-tab scan, Sort, then the tab's option (Add Item or
Refresh) and the character-specific checkbox on the right. The window is one fixed size on
every tab, and how long ago you last scanned reads in the header beside the guild mark.

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

```
/maw sources                 show availability
/maw sources atr|tsm on|off  toggle a feed
/maw sources pull [atr|tsm]  pull now and print a per-item report
```

The History tab has "Pull Auctionator" and "Pull TSM" buttons that do the same.

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
buy and sell averages, vendor sell, and TSM crafting cost.

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
  bags plus bank. The Convert button casts the recipe, or uses the item for mote combines.
  One click makes one batch. The game only lets an addon cast from a real click, and only
  out of combat, so the button is disabled while fighting.
- **List**: any tracked item at or above 75% of its range that you hold, so spare
  materials get listed when they spike, not just products.
  The List button switches to the Auctions tab, puts your first bag stack in the sell
  slot, and fills start and buyout from today's price undercut by 1 copper per unit. You
  set the duration and press Create Auction.

Hover a name for the same tooltips as the other tabs. Buy and List need the auction house
open. "Refresh Table" recomputes without scanning.

```
/maw movers
```

## Other commands

```
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
