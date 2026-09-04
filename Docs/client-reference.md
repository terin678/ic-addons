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

`## Group:` collects several addons under one collapsible heading in the in-game AddOns
list. It is verified in use on 20506 by four installed families — AtlasLoot, Bagnon,
GatherMate2, and AtlasBIStooltips, which is TBC-only and so was written for this client.
In every one of them the value is **an existing addon folder name** that heads the group,
never an invented label. The guild addons all use `## Group: ICLibs`, which is the one
every other guild addon depends on and therefore the one that is always installed.

WeakAuras is the counter-example worth knowing about: five folders, no `## Group:` at all.
It leans on a shared `## IconTexture`, a common title prefix, and `## Dependencies` on its
core instead.

`## Category:` is free text and drives the list's category filter. Values already in use on
this client include Action Bars, Attunements, Auctions, Bags & Inventory, Combat,
Development Tools, Gambling, Guild, Libraries, Loot, Map, Quests, UI Overhaul, Unit Frames
and User Interface. There is also a `## Category-enUS:` localized form; both work, and
picking a string nobody else uses just creates a category of one.

A title may carry an inline texture, which is how the guild mark gets in front of every
addon's name: `## Title: |TInterface\AddOns\ICLibs\Textures\ImpulseControl-64:16|t Name`.
The escape takes the path **without** a file extension; `## IconTexture` takes it with one.
