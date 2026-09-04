# Client reference

Facts about the game clients that addons here depend on. Verify against an installed,
recently updated addon's `.toc` before relying on a number; Blizzard bumps these with
patches.

## Interface versions

| Flavor | Folder | Interface | Notes |
| --- | --- | --- | --- |
| era | `_classic_era_` | 11508 / 11509 | Classic Era and Hardcore |
| anniversary | `_anniversary_` | 20506 | TBC Anniversary. Legacy auction house API (`QueryAuctionItems`, `GetAuctionItemInfo`, `CanSendAuctionQuery`) |
| retail | `_retail_` | 120100 | Modern auction house API (`C_AuctionHouse`) |

An addon whose `.toc` interface is lower than the client's is flagged out of date and
will not load unless the player ticks "Load out of date AddOns".

## APIs known to work on anniversary (20506)

- `C_Container.GetContainerNumSlots` / `GetContainerItemInfo` (returns a table)
- `Enum.BagIndex.Bank`, `NUM_BAG_SLOTS`, `NUM_BANKBAGSLOTS` (7 bank bags)
- `TradeSkillFrame` for most professions, `CraftFrame` for Enchanting
- `Mixin`, `C_Timer.After`, `UIDropDownMenuTemplate`, `BasicFrameTemplateWithInset`
- Legacy auction API. Exact-match name queries: `QueryAuctionItems(name, nil, nil, 0,
  false, nil, false, true, nil)`. Results arrive on `AUCTION_ITEM_LIST_UPDATE`; rows may
  be unpopulated on the first event, so re-read after a short delay.

## Optional dependency APIs

### Auctionator (Legacy AH tree on era/anniversary)

- Supported: `Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` (copper per
  unit), `GetAuctionAgeByItemID` (days since seen), `RegisterForDBUpdate(callerID, fn)`.
- Internal but stable: `Auctionator.Database:GetPriceHistory(tostring(itemID))` returns
  rows `{date, rawDay, minSeen, maxSeen, available}` newest first. `rawDay` counts from
  `time({year=2020, month=1, day=1, hour=0})`. Default retention 21 days.
- Only records prices for items seen in a Full Scan or a Shopping tab search.

### TradeSkillMaster

- `TSM_API.ToItemString(link)` then `TSM_API.GetCustomPriceValue(source, itemString)`.
  Call with `.` not `:`. Sources: `DBMinBuyout`, `DBMarket` (14 day), `DBHistorical`
  (60 day), `DBRecent`, `DBRegionMarketAvg`.
- No per-day history and no update callback. Data is a snapshot from the desktop app;
  on Classic realms it is often empty.

## Client folders

Saved variables: `<flavor>\WTF\Account\<ACCOUNT>\SavedVariables\<Addon>.lua`, written on
logout and `/reload` only. Lua errors: BugSack in game or `<flavor>\Errors\`.

## The AddOns list

The list has exactly **two levels**, confirmed in game:

- **`## Category:`** is the top-level heading. It is free text, and every addon sharing a
  string collapses under it. The guild addons all use `## Category: Impulse Control`.
- **One level of nesting inside it.** A nested addon is drawn indented under the row of the
  addon that heads its cluster; there is no separate label row for the cluster itself, so
  the heading you read is the head addon's `## Title`.

Two mechanisms produce that nesting, and an addon needs only one of them:

- **`## Group:`**, used by AtlasLoot, Bagnon, GatherMate2 and AtlasBIStooltips (the last
  being TBC-only, so written for this client). In all four the value is an existing addon
  folder name.
- **A shared folder-name prefix**, which is what Guild Roster Manager relies on:
  `Guild_Roster_Manager_Group_Info` nests under `Guild_Roster_Manager` with no `## Group:`
  line anywhere in either .toc. WeakAuras has no `## Group:` either.

**Do not put a texture in `## Title` if the addon also has an `## IconTexture`.** Both
draw, so every row gets two icons side by side. AtlasLoot does this and it looks like a
mistake; GRM does not, and looks right.

Category values already in use on this client include Action Bars, Attunements, Auctions,
Bags & Inventory, Combat, Development Tools, Gambling, Guild, Libraries, Loot, Map, Quests,
UI Overhaul, Unit Frames and User Interface, plus a localized `## Category-enUS:` form.
Reusing one of those files an addon in with everyone else's; inventing one, as the guild
addons do with `Impulse Control`, gives it a heading of its own. Which you want depends on
whether the addon is meant to be found among its peers or among its siblings.

A `## Title` can carry an inline texture --
`|TInterface\AddOns\ICLibs\Textures\ImpulseControl-64:16|t Name` -- and the escape takes
the path **without** a file extension while `## IconTexture` takes it with one. Worth
knowing, but see the warning above: use one or the other, never both.
