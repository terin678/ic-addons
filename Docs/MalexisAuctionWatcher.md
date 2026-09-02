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

## History

Prices are kept in daily buckets for 180 days by default (`/maw retention <days>`,
minimum 7) plus a per-hour-of-day accumulator. Weekday and day-of-month views are derived
from the daily buckets. The summary line names the cheapest and priciest bucket and says
when there are fewer than 3 samples, which is too few to trust.

```
/maw history [item]    open the chart, optionally for one item
```

## Recipes

Profit per batch = product value after the 5% AH cut minus material cost, using each item's
latest price. Rows sort by profit. Hover a recipe for the full breakdown with sources.

- "Add Motes -> Primals": seven recipes, 10 motes to 1 primal.
- "Add Primal Might": the Alchemy transmute, one each of Earth, Water, Air, Fire, Mana.
- "Add Gem Cuts": picker for TBC Jewelcrafting. Click a raw gem to add all its cuts, or add
  a whole tier. 109 cuts across 18 raw gems; meta gems excluded.
- "Add Recipe": custom recipe, drag a product and up to five materials with counts.

Everything a recipe uses is tracked automatically. "Can make" counts bags plus bank; it does
not know about cooldowns or which patterns you have learned.

The refresh icon on a row scans that recipe's product and materials. "Scan Recipes" in the
control bar scans every item used by any recipe. "Refresh Table" recomputes the numbers
from the latest prices and your current bags and bank without scanning.

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
