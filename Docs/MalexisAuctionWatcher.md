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
| Materials | Items you buy. Today, low, average, high per unit. Green is cheap, red is expensive. |
| Products | Items you sell. Same columns, colors inverted so high is green. |
| Stores | How many of each item you hold in bags, bank, and on the AH, and what it is worth. |
| History | Chart of one item over time: 30 or 90 days, by weekday, by day of month, by hour. Highlights the cheapest and priciest bucket. |
| Recipes | Material to product conversions with cost, AH net, profit, margin, and how many batches you can make now. |

The window grows taller on the History tab.

## Adding items

- Click "Add Item" on Materials or Products, or drag an item onto the drop row at the
  bottom of any list to add it with defaults.
- Click the low or high cell to set a custom bound. Custom bounds show a `*`.
- Arrows reorder rows, the refresh icon scans one item, X removes it.

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

Prices are kept in daily buckets for 180 days by default (`/maw retention <days>`,
minimum 7) plus a per-hour-of-day accumulator. Weekday and day-of-month views are derived
from the daily buckets. The summary line names the cheapest and priciest bucket and says
when there are fewer than 3 samples, which is too few to trust.

```
/maw history [item]    open the chart, optionally for one item
```

## Recipes

Profit per batch = product value after the auction house cut minus material cost, using
each item's latest price. Rows sort by margin, best first. Hover a recipe for the full
breakdown with sources.

The cut defaults to 15%, the neutral auction house rate, so anything green clears the
worst case. Faction auction houses take 5%. Change it with `/maw ahcut <percent>`; the
"AH net" headers on Recipes and Stores show the rate in use.

The "Presets..." menu offers:

- Motes -> Primals: seven recipes, 10 motes to 1 primal.
- Transmute: Primal Might: one each of Primal Earth, Water, Air, Fire, Mana.
- Alchemy consumables: Haste Potion, Destruction Potion, Super Mana Potion, Super Healing
  Potion, Elixir of Major Mageblood, Flask of Fortification, Flask of Mighty Restoration.
  Reagents are built in; the recipe note reminds you to check them against your book.
- Gem cuts: picker for TBC Jewelcrafting. Click a raw gem to add all its cuts, or add a
  whole tier. 109 cuts across 18 raw gems; meta gems excluded.
- Import from open profession window: lists every recipe in the profession window you have
  open, with reagents and counts read straight from the client. Add one or all. This is the
  reliable way to get any profession's recipes in, Alchemy included. Enchanting is not
  supported since enchants are not items.
- Flipping guide watchlist: tracks the herbs, primals, gems, shards, and old-world
  consumables a TBC flipping guide singles out, without adding recipes.

"Add Recipe" builds a custom recipe: drag a product and up to five materials with counts.

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

## Other commands

```
/maw list                 list tracked items
/maw prices <item>        last 10 entries for an item
/maw add <name or link>   track an item (materials tab)
/maw remove <name>        stop tracking
/maw minimap              show or hide the minimap button
/maw debug                verbose chat output
/maw help
```

Right-click the minimap button to start or cancel a scan. Drag it to move it.

## Data

Account-wide by default. Tick "Character-Specific Data" to keep a separate list per
character; you are offered a copy of the account data the first time.
