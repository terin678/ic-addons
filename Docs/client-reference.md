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
| forever | `_classic_beta_` | 16001 | WoW Forever, in beta as product `wow_classic_beta` (1.60.1). Modern client base; see below |

An addon whose `.toc` interface is lower than the client's is flagged out of date and
will not load unless the player ticks "Load out of date AddOns".

## What is known about forever (16001)

The flavor name to folder, interface and library mapping is `scripts/flavors.psd1`. The
client installs as `_classic_beta_` and runs as `WowB.exe`; `.build.info` lists it as
`wow_classic_beta`. Everything below was confirmed on build 1.60.1 (70124) on 2026-09-30,
either by `/ickit probe` running in the client (the report is saved to `ICKitDB.probe`) or
by reading the exported interface source.

**It is the modern client base.** `WOW_PROJECT_ID` is 1, the same value as
`WOW_PROJECT_MAINLINE` (`WOW_PROJECT_CLASSIC` is 2), so a check for "is this Classic" by
project id says no. Branch on the interface number or on whether an API exists, never on
the project id.

Present: `C_AddOns.GetAddOnMetadata` and `IsAddOnLoaded`, `C_Timer.After` and `NewTicker`,
`C_Item.GetItemInfo`, `C_Container`, `C_AuctionHouse`, `C_TooltipInfo` with
`TooltipDataProcessor`, `C_ChatInfo.SendAddonMessage` and `RegisterAddonMessagePrefix`,
`MenuUtil.CreateContextMenu`, `Settings.RegisterCanvasLayoutCategory`, `StaticPopup_Show`
with `StaticPopupDialogs`, `EditModeManagerFrame`, `AddonCompartmentFrame`,
`CreateFramePool`, `Mixin`, `hooksecurefunc`, `issecretvalue`, `debugprofilestop`,
`C_AddOnProfiler.GetAddOnMetric`, `UpdateAddOnMemoryUsage` and `GetAddOnMemoryUsage`,
`UpdateAddOnCPUUsage`, `GetAddOnCPUUsage` and `GetFunctionCPUUsage`, `GetCVar` and
`C_CVar.GetCVar`, `GetServerTime`, `GetPhysicalScreenSize`, `UISpecialFrames`,
`UIDropDownMenu_Initialize`, and the font objects `GameFontNormal`, `GameFontNormalSmall`,
`GameFontHighlight`, `GameFontHighlightSmall`, `GameFontDisableSmall`.

Absent: the globals `GetAddOnMetadata` and `GetItemInfo`, `EasyMenu`,
`InterfaceOptions_AddCategory`, and the legacy auction call `QueryAuctionItems`. Anything
written for the Anniversary client that uses these does not run here.

Frame templates that create without error: `BackdropTemplate`, `UIPanelButtonTemplate`,
`UICheckButtonTemplate`, `InputBoxTemplate`, `UIPanelScrollFrameTemplate`,
`BasicFrameTemplateWithInset`, `UIPanelCloseButton`. The modern scroll pieces
(`WowScrollBoxList`, `MinimalScrollBar`) are in the source too.

Methods: `Texture:SetColorTexture` exists, and a frame made without `BackdropTemplate` has
no `SetBackdrop`. Draw fills and edges with colour textures and a widget needs no template
at all. The moving, clamping, edit-box and check-button methods the widgets use are all
present, as are the script handlers `OnDragStart`, `OnDragStop`, `OnMouseDown`, `OnEnter`,
`OnEnterPressed`, `OnEscapePressed`, `OnEditFocusLost`, `OnTextChanged` and `OnClick`.

**Character names are two-part.** `UnitName("player")` and `UnitFullName("player")` both
return two values that are the character's two names (a first and a second name), not a
name and a realm. `GetRealmName()` is "Classic Beta PvE 2" and `GetNormalizedRealmName()` is
"ClassicBetaPvE2". Never build a "Name-Realm" key by hand; use the per-character saved
table, or `UnitGUID` when a key is needed.

Load order is `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, and both the
account and the per-character saved tables are in hand at `ADDON_LOADED`. Both are written
on `/reload`.

`GetBuildInfo()` returns six values here: version, build, date, interface, then two empty
strings. `UIParent` on a 3840 by 2160 screen was 1923 by 1082 at an effective scale of
0.71, so positions are stored as fractions of `UIParent`, not as pixels.

The interface source is exported at `_classic_beta_\BlizzardInterfaceCode` (launch with
`-console`, then `ExportInterfaceFiles code` at the login screen; it cannot be run in
game). Grep it before using an API the probe did not cover, and re-export after a patch.

## APIs known to work on anniversary (20506)

- `C_Container.GetContainerNumSlots` / `GetContainerItemInfo` (returns a table)
- `Enum.BagIndex.Bank`, `NUM_BAG_SLOTS`, `NUM_BANKBAGSLOTS` (7 bank bags)
- `TradeSkillFrame` for most professions, `CraftFrame` for Enchanting
- `Mixin`, `C_Timer.After`, `UIDropDownMenuTemplate`, `BasicFrameTemplateWithInset`
- Legacy auction API. Exact-match name queries: `QueryAuctionItems(name, nil, nil, 0,
  false, nil, false, true, nil)`. Results arrive on `AUCTION_ITEM_LIST_UPDATE`; rows may
  be unpopulated on the first event, so re-read after a short delay.
- `FontString:SetWordWrap(false)`. A font string with a set width wraps by default, which
  in a fixed-height row draws over the row below. Used in MalexisAuctionWatcher and
  MarkedForDeath.
- `NotifyInspect(unit)` then `INSPECT_READY`, then `GetTalentTabInfo(tab)`. Works on
  anyone within about 28 yards with no addon on their end, and is the only way to learn
  another player's spec on this client. Never call it in combat, and rate limit it: one
  unit at a time with a timeout, because a request that never answers otherwise wedges
  the queue.

## API signatures that differ from what you would expect

- **`GetTalentTabInfo(tab)` returns `id, name, description, icon, pointsSpent`** on
  anniversary, not `name, icon, pointsSpent`. Reading it as the shorter form puts the
  description string where the points number belongs, and the first `points > best`
  comparison throws "attempt to compare string with number". This cost a day: the error
  surfaced as an unrelated feature going silently empty, because the throw aborted the
  caller. Parse defensively and coerce with `tonumber`.

## Libraries that do not work here

- **LibSpecialization**: returns at load before registering anything. Line 5 gates on the
  client build (`if wowID ~= 1 and wowID ~= cataWowID and wowID ~= mistsWowID then
  return end`), and anniversary is none of those. Do not embed it; inspect instead.
- **LibDurability** (`LibDRBLT` addon message prefix) does work, and is embedded in
  BigWigs, DBM and MRT, so most of a raid answers it without running your addon. This is
  the only cross-player data channel in this repo that does not require your own addon on
  both ends.
- **Method Raid Tools raid check interop**: not usable on Classic. It sends only `DUR`,
  and its oil and enchant fields are gated behind `not ExRT.isClassic`.

## Things no API can tell you

- **Another player's weapon enchant.** There is no cross-unit API for it on any client
  version. `GetWeaponEnchantInfo` reads the player only. MRT has the same limitation
  despite appearing not to; do not spend time looking for a way around it.

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
logout and `/reload` only; the previous write survives as `.lua.bak` until the next one.
Lua errors: BugSack in game or `<flavor>\Errors\`.

`.toc` files are read once, at client start. Editing a `.toc` needs a client restart. `/reload` does not re-read it, and a client that has been running across `.toc` edits can stop restoring one addon's account-wide saved variables while still restoring the per-character ones. The fingerprint is `/x log` saying `SAVED VARIABLES WERE EMPTY` with the per-character table intact. Restart the client before reading a line of addon code. Seen on 2026-09-04:
GuildRecruitment's account-wide table came back empty on every `/reload` for two hours
while the file on disk was written correctly each time and the per-character table loaded;
the client's own logs said nothing; a restart fixed it outright. `AddOns.txt` is not
evidence either way: it is rewritten only from the AddOns screen and does not list addons
left at their default enabled state.

## The AddOns list

The list has exactly **two levels**, confirmed in game:

- **`## Category:`** is the top-level heading. It is free text, and a string nobody else
  uses gets a heading of its own -- confirmed: the guild addons all say
  `## Category: Impulse Control` and the list grew an Impulse Control heading between
  Guild and Loot.
- **One level of nesting inside it.** A nested addon is drawn indented under the row of the
  addon that heads its cluster; there is no separate label row for the cluster itself, so
  the heading you read is the head addon's `## Title`.

Two mechanisms produce that nesting, and an addon needs only one of them:

- **`## Group:`**, used by AtlasLoot, Bagnon, GatherMate2 and AtlasBIStooltips (the last
  being TBC-only, so written for this client). **The value must be an addon folder that
  exists**, and the head names itself: GatherMate2's own .toc says `## Group: GatherMate2`.
  Tried with a free-text value -- `Core`, `Auction` -- the client does not fall back to
  using it as a label; it drops the addon out of grouping altogether and leaves it flat in
  the alphabetical list. There is no way to give a cluster a name of its own, so the
  heading you read is always the head addon's `## Title`.
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

What the guild addons end up rendering as, for reference:

```
> Guild
v Impulse Control                      ## Category: Impulse Control
    [mark] Impulse Control Core        ICLibs          ## Group: ICLibs
      [mark] Guild Recruitment         GuildRecruitment
      [mark] ICTemplate                ICTemplate
    [mark] Malexis Auction Watcher     MAW             ## Group: MalexisAuctionWatcher
      [mark] Auctionator Selling ...   AST
    [gem]  TradeMaster                 TradeMaster     ## Group: TradeMaster
> Loot
```

One icon per row, because no title carries a texture. Members sort alphabetically inside a
cluster; the head is drawn first whatever its name.
