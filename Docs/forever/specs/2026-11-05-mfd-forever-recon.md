# Marked For Death on Forever: static recon

Research for rebuilding MarkedForDeath (anniversary 1.29.0, interface 20506) on WoW
Forever (interface 16001, client 1.60.1, game type `camelot`). Static only: the
Anniversary source, the repo docs, every addon installed in `_forever_\Interface\AddOns`,
the Forever client's hotfix cache and BugGrabber's saved errors. Nothing here was run in
game. The probe lane (`feature/mfd-forever-probe`, `MFDProbe`) answers the questions at
the end.

Paths under "Evidence" are relative to `_forever_\Interface\AddOns` unless they start
with `MFD/` (that is `AddonProjects/anniversary/MarkedForDeath`). The full scans this was
condensed from are in the session notes folder as `recon-restrictions-scan.md` and
`recon-data-sources.md`.

## The short answer

MarkedForDeath as built cannot run on Forever. Three of its foundations are closed:

1. **An addon cannot place a raid icon.** `SetRaidTarget` is protected on this client and
   refuses any call from addon Lua with `ADDON_ACTION_FORBIDDEN`. The only legal route is
   a player's own click or keypress on a secure button that runs a `/tm` macro.
   Automatic marking ("walk up to a pack and it is marked") is gone.
2. **Inside instances, an addon cannot tell which mob is which.** `UnitGUID` and
   `UnitName` of instance units come back as secret strings. No npc id, no name, so no
   rule matching, no learning, no candidate set. The open world is readable, even in
   combat.
3. **There is no combat log for addons.** `COMBAT_LOG_EVENT_UNFILTERED` delivers no
   payload on Forever. Deaths, boss detection and mob-death cleanup all read it today.

What survives is everything that is a plan rather than a reaction: the seat plan, the
rules, the allocator as a pure function, the assignment panel, announcing before the pull
(if chat is open then), the raid check out of combat, combat logging, the action bar as
secure buttons, the minimap button. Marking turns into **one keypress that applies the
plan**: out of combat the addon writes a secure macro of `/targetexact <name>` and
`/tm ~<icon>` lines from the rules, and the player presses it. Whether that is good
enough depends on the probe answers below, chiefly whether instance mobs and raid icons
are readable out of combat inside a Forever raid.

Two smaller facts that change design: **Forever has one spec per class**, so spec
inspection buys nothing; and **chat and addon messages lock down during encounters** (and
possibly on every raid map), so anything said to the raid has to be said before the pull
or queued.

## How Forever is detected

Branch on the interface number from `GetBuildInfo()`: 16000 to 19999. Never on
`WOW_PROJECT_ID`, which reads `WOW_PROJECT_MAINLINE` here.
Evidence: `Decursive/Dcr_DIAG.lua:700-715`, `EllesmereUI/EllesmereUI_ClientGate.lua:22-31`,
`EllesmereUI/EllesmereUI_Lite.lua:14-18`. A `.toc` may also carry
`## AllowLoadGameType: camelot` (`VuhDo/VuhDo_Camelot.toc:2`).

The Blizzard interface export the repo docs point at (`_classic_beta_\BlizzardInterfaceCode`)
**is no longer on disk**; `_classic_beta_` holds only an AddOns folder. Re-export it
(`-console`, `ExportInterfaceFiles code` at the login screen) before the build lane relies
on Blizzard's documentation files (`*Documentation.lua` carry the `SecretInChatMessagingLockdown`
and `AllowedWhenUntainted` flags several addons quote).

## Restriction machinery on this client

| Mechanism | Status | Evidence |
| --- | --- | --- |
| `issecretvalue`, `issecrettable`, `canaccessvalue`, `canaccesstable` | present | repo `Docs/client-reference.md` (issecretvalue probed); `Decursive/Dcr_DebuffsFrame.lua:88`; used by ~30 installed addons |
| `C_Secrets.*` (`ShouldAurasBeSecret`, `ShouldSpellAuraBeSecret`, `ShouldUnitIdentityBeSecret`, `CanCompareUnitTokens`, `ShouldUnitThreatValuesBeSecret`, `GetSpellAuraSecrecy`) | present | `Decursive/Dcr_opt.lua:2262,2802`; `EllesmereUI/EllesmereUI_Colors.lua:553-556` |
| `C_RestrictedActions.IsAddOnRestrictionActive`, `GetAddOnRestrictionState`, event `ADDON_RESTRICTION_STATE_CHANGED`, `Enum.AddOnRestrictionType` {Combat, Encounter, ChallengeMode, PvPMatch, Chat, and a map type} | present | `Decursive/Dcr_Events.lua:380-438`; `EllesmereUISimpleLootCouncil/Core/Restrictions.lua:17-56` |
| Quirk: only the "activating" state fires; the queried state goes active after dispatch | noted | `Decursive/Dcr_Events.lua:383-386` |
| Quirk: secret values lag the end of combat (source GUIDs declassify late) | noted | `EllesmereUIDamageMeters/EUI_DamageMeters_Format.lua:316-322`, `_Lifecycle.lua:367` |
| Live proof on this install: comparing a `UNIT_COMBAT` damage argument threw "attempt to compare ... a secret number value" | observed | `_forever_\WTF\Account\84083208#1\SavedVariables\!BugGrabber.lua`, from `AutoBiographer/Main.lua` (since guarded at `:1514`) |

ICKit caution from the probe lane: `Env.Try` concatenates return values outside its
`pcall`, which throws on a secret. Anything that may return a secret needs its own wrapper.

## What MFD calls today, by module

| Module | Client APIs and events | Feature it serves |
| --- | --- | --- |
| Candidates | `NAME_PLATE_UNIT_ADDED/REMOVED`, `UNIT_TARGET`, `UPDATE_MOUSEOVER_UNIT`, `PLAYER_TARGET_CHANGED`; `UnitGUID` (npc id parse via `MFD/Helpers.lua:18` `SplitGUID`), `UnitName`, `UnitIsEnemy`, `UnitIsDead`, `UnitPlayerControlled`, `UnitCreatureType`, `GetRealZoneText` | the set of visible hostile mobs; learning layer |
| Marker | `SetRaidTarget` (`MFD/Marker.lua:372,716,764`), `GetRaidTargetIndex` (`:498`, reads back icons to detect hand marks and wipes), `GetCVar` nameplate checks, `UnitAffectingCombat`, `UnitClass`, `GetRaidRosterInfo`, `IsInRaid/IsInGroup`, `UnitIsGroupLeader/Assistant`, `PLAYER_REGEN_*`, `GROUP_ROSTER_UPDATE`, CLEU `UNIT_DIED` (`:909-920`) | placing icons, hold/defend, manual override, mob-death cleanup, late CC alert, pack announce |
| Allocator, Rules, Roles, Log, JSON, Helpers | none (pure) | seats, rules, allocation, share/import, log |
| Comms | `C_ChatInfo.SendAddonMessage/RegisterAddonMessagePrefix`, `CHAT_MSG_ADDON`, `GROUP_ROSTER_UPDATE`, `UnitName` | lead election, rule merge, sightings, published assignments, backup placement |
| Chatter | `SendChatMessage` (RAID, RAID_WARNING, WHISPER), `IsInRaid`, `UnitIsGroupLeader/Assistant` | the one rate limiter for everything said |
| Encounters | CLEU (sampled, boss npc id from GUID), `PLAYER_REGEN_*`, `UnitAffectingCombat`; boss from nameplate set; comment: "no ENCOUNTER_START on this client" (TBC) | which boss for death calls |
| Tanks, Healers | CLEU `UNIT_DIED` (dest name), `GetPartyAssignment("MAINTANK")`, `UnitGroupRolesAssigned`, `GetNumGroupMembers`, spec from RaidCheck | death announcements per kind |
| RaidCheck | `UnitAura(unit, i, "HELPFUL")` by name, `NotifyInspect`/`CanInspect`/`INSPECT_READY`, `GetTalentTabInfo`/`GetNumTalents`/`GetTalentInfo`, `GetInventoryItemDurability`, LibDurability over `CHAT_MSG_ADDON`, `DoReadyCheck`, `READY_CHECK`, `UNIT_AURA`, `UNIT_INVENTORY_CHANGED`, `UPDATE_INVENTORY_DURABILITY`, `InCombatLockdown`, `UnitExists/UnitIsVisible` | raid check grid, buff board, callouts, spec, durability |
| CombatLog | `LoggingCombat`, `GetInstanceInfo`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED`, `C_Timer.After` | auto combat logging |
| Conflicts | reads `VMRT` (MRT) settings; `UIErrorsFrame` | conflicting addons |
| ChatCue | `CHAT_MSG_RAID/_LEADER`, `CHAT_MSG_PARTY/_LEADER` message text, `PlaySoundFile` | plays a sound on one word |
| Core | `SetCVar` (nameplate fix), `PlaySoundFile`, `UnitCreatureType` (CC-type warning), `READY_CHECK`, `ZONE_CHANGED_NEW_AREA` | commands, bad-mark sound, fixcvars |
| UI_* | `CreateFrame`, `SetRaidTargetIconTexture`, `UISpecialFrames`, `GetCursorPosition`, `InterfaceOptions_AddCategory` / `Settings.RegisterAddOnCategory`, `C_Timer.After` | windows, action bar, settings |
| Minimap | LibDataBroker + LibDBIcon via LibStub | minimap button |

## Verdict per API on Forever

Verdicts: **allowed**, **OOC only** (out of combat), **secret** (readable only outside a
restriction; which restrictions in brackets), **gone**, **probe** (no or conflicting
evidence). Confidence follows the evidence: Forever-only code (ForeverDungeonJournal,
EllesmereUIForeverEssentials, `IsForever` branches) is strongest; shared 12.x code is
likely but not proven.

### Raid icons

| API | Verdict | Evidence |
| --- | --- | --- |
| `SetRaidTarget` from addon Lua | **gone** (protected, `ADDON_ACTION_FORBIDDEN`) | `EllesmereUIQuickdraw/EUI_Quickdraw_Actions.lua:440-455` ("protected, and refuses any call an addon makes from its own Lua", "documented AllowedWhenUntainted"); `EllesmereUI/EllesmereUI_MenuFallbacks.lua:10-12` |
| `/tm N`, `/tm !N` (toggle), `/tm ~N` (only if unmarked), `/tm 0` from a `SecureActionButtonTemplate` with `type=macro`, `macrotext` | **allowed, in combat too**, on a hardware click; attributes set OOC | `EllesmereUIQoL/EllesmereUIQoL_RaidTools.lua:575-640`; Forever-only `ForeverDungeonJournal/Systems/MapMarkers.lua:152-175` (`/targetexact <npc>` then `/tm ~N`, deferred while `InCombatLockdown`) |
| `type=raidtarget`, `action=clear-all` (RemoveRaidTargets) | allowed (secure path, lead or assist) | `EUI_Quickdraw_Actions.lua:449-466` |
| `GetRaidTargetIndex` | **secret** (in dungeons and restricted content; only `type(idx)` is safe) | Forever-only `MapMarkers.lua:161-170`; `EllesmereUINameplates/EUI_Nameplates_Name.lua:510-519`; `Decursive/Dcr_DebuffsFrame.lua:1755` |
| `RAID_TARGET_UPDATE` | allowed (fires) | `EllesmereUIRaidFrames/EUI_RaidFrames_Events.lua:575` |
| `SetRaidTargetIconTexture` with a secret index | **probe** (two EllesmereUI comments disagree) | `EUI_MythicTimer_KickBars.lua:330-333` vs `EUI_MythicTimer_TargetedSpellBars.lua:495-497` |
| `IsRaidMarkerActive` | secret during chat lockdown | `EllesmereUIQuickdraw/EUI_Quickdraw_Paint.lua:552-560` |
| World markers `/wm`, `type=worldmarker` | allowed via secure button; per-marker cooldown | `EllesmereUIQoL_RaidTools.lua:604-643`; `EUI_Quickdraw_Actions.lua:468-504` |

### Combat log and its replacements

| API | Verdict | Evidence |
| --- | --- | --- |
| `COMBAT_LOG_EVENT_UNFILTERED`, `CombatLogGetCurrentEventInfo` | **gone** (no payload) | Forever-aware `AutoBiographer/Main.lua:727-730`; `Decursive/DCR_init.lua:1244-1248` registers CLEU only when auras are unrestricted, never on Forever |
| `UNIT_DIED(unitGuid)` | allowed; GUID may be secret | Forever-only `AutoBiographer/Main.lua:1546-1550`, `:2626-2627` |
| `PARTY_KILL(attackerGuid, targetGuid)` | allowed; GUIDs may be secret | `AutoBiographer/Main.lua:982-988` |
| `ENCOUNTER_START/END`, `BOSS_KILL` | allowed; name and success may be secret | `AutoBiographer/Main.lua:884-887`; `ForeverDungeonJournal/Systems/RPGMode.lua:810-820` |
| `C_DamageMeter.*` (incl. a Deaths session) | allowed; source GUIDs and names secret until after combat, `specIconID` always secret on 1.60.1 | `AutoBiographer/Api.lua:67-125`; `EllesmereUIDamageMeters/EUI_DamageMeters_Window.lua:1647,1832`, `_State.lua:383` |
| `C_DeathRecap.GetRecapEvents` | allowed (own death) | `AutoBiographer/Api.lua:130-134` |
| `C_CombatLog` | **probe** (no addon uses it) | none |
| `LoggingCombat` | allowed from Lua | `EllesmereUIQoL/EllesmereUIQoL_AutoLogging.lua:161-173`; whether a file is written: **probe** (no `WoWCombatLog*.txt` in `_forever_\Logs`) |

### Units and nameplates

| API | Verdict | Evidence |
| --- | --- | --- |
| `UnitGUID`, `UnitName` of mobs | **secret inside Forever instances**; readable in the open world, in combat too | Forever-only `ForeverDungeonJournal/Core/Journal.lua:2344-2347`; `Questie/Modules/Tooltips/Tooltip.lua:650-656`; `Questie/Modules/QuestieNameplate.lua:22,31-38` skips plates in Forever instances. Out of combat inside a raid: **probe** |
| npc id from GUID | allowed only after `issecretvalue` says no | `AutoBiographer/HelperFunctions.lua:7-15`; FDJ `RPGMode.lua:799-800` |
| `UnitIsDead`, `UnitExists`, `UnitAffectingCombat` | allowed | `EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Refresh.lua:706` |
| `UnitIsUnit` | secret under identity restriction (only `"player"` answers) | `EllesmereUI/EllesmereUI_Colors.lua:491-496` |
| `UnitHealth/Max` | secret in restricted combat | `VuhDo/VuhDo.lua:481-484` |
| `UnitClassification`, `UnitCreatureType` on instance mobs | **probe** (guarded in some places, unguarded in others) | `EUI_UnitFrames_StockStyles.lua:1233`; `VuhDo/VuhDo.lua:598` |
| `UnitGroupRolesAssigned` | can be secret | `EllesmereUI/EllesmereUI.lua:2108`; `EllesmereUIRaidFrames/EUI_RaidFrames_ForeverMissingBuffs.lua:48` |
| `GetPartyAssignment` | **probe** (no addon uses it) | none |
| `GetRaidRosterInfo` names and ranks | allowed, guarded as possibly secret | `EllesmereUISimpleLootCouncil/Core/Roster.lua:88-89,449-450` |
| `NAME_PLATE_UNIT_ADDED`, `nameplateN` tokens | event and tokens allowed; plate frames protected in instances; identity secret in instances | `EllesmereUINameplatesFriendly.lua:2024-2028`; Questie as above |
| Nameplate CVars via `SetCVar` | OOC only | `EllesmereUINameplatesFriendly.lua:2024-2028` |
| Threat (`UnitDetailedThreatSituation` etc.) | allowed, not secret on Forever | Forever-only `EllesmereUIForeverEssentials/..._ThreatData.lua:9-18` |

### Auras

| API | Verdict | Evidence |
| --- | --- | --- |
| Global `UnitAura/UnitBuff/UnitDebuff` | deprecated shims; presence **probe**; avoid | `Decursive/Decursive.lua:424-445`; `Questie/Modules/QuestieCompat.lua:533-543` |
| `C_UnitAuras.GetAuraDataByIndex` | allowed when unrestricted; **throws** (not just secret) while auras are restricted, which includes out of combat in instances | `EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Auras.lua:58,107,193`; `EllesmereUI/EllesmereUI_AuraKit.lua:2348-2360` |
| `C_UnitAuras.GetPlayerAuraBySpellID`, `GetAuraDataBySpellName`, gated on `C_Secrets.ShouldSpellAuraBeSecret(id) == false` | allowed; the Forever pattern for "does this person have buff X" | Forever-only `EllesmereUIRaidFrames/EUI_RaidFrames_ForeverMissingBuffs.lua:33-40,205-222`; `EUI_Nameplates_Colors.lua:141-152` |
| `UNIT_AURA` updateInfo | fires; can be wholly secret in restricted combat | `EUI_AuraBuffReminders_Auras.lua:610-614`; `Decursive/Dcr_Events.lua:616-634` |
| Spell id, name, source, expiry while restricted | secret (per-spell whitelist) | `VuhDo/Flavors/Forever/VuhDoSecretSpells.lua`; `EUI_ActionBars_Events.lua:1695` |
| Snapshot at `PLAYER_REGEN_DISABLED` | the workaround used | `EUI_AuraBuffReminders_Auras.lua:25-60`; `_Refresh.lua:305-309` |

### Inspect, talents, durability

| API | Verdict | Evidence |
| --- | --- | --- |
| Specs | **one per class on Forever**; nothing to inspect for | `EllesmereUI/EllesmereUI_Presets.lua:170-182`; `EllesmereUI/EllesmereUI.lua:2112` |
| `NotifyInspect`, `INSPECT_READY` | allowed OOC (shared code) | `EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipSkin.lua:480-503`; VuhDo skips inspect on Forever (`VuhDo/Flavors/Forever/VuhDoFlavorRules.lua:2`) |
| Talents | `C_ClassTalents` + `C_Traits` trees for the player; other players: **probe** | Forever-only `AutoBiographer/Api.lua:425-450` |
| `GetTalentTabInfo` | **probe** (no Forever evidence) | none |
| `GetInventoryItemDurability` | allowed | `EllesmereUIDataBars/Blocks/Stats.lua:543-547` |
| LibDurability over addon messages | depends on addon-message lockdown (below); whether BigWigs/DBM answer it on Forever: **probe** | MFD `RaidCheck.lua:819-835` |
| Weapon enchants (self) | `C_Item.GetWeaponEnchantInfo`; the global is a shim | Forever-only `EllesmereUIUnitFrames/EUI_UnitFrames_ForeverImbues.lua:3-31` |

### Chat and addon messages

| API | Verdict | Evidence |
| --- | --- | --- |
| `C_ChatInfo.InChatMessagingLockdown()` | present; true in encounters and keystones, and per Quickdraw on every dungeon and raid map | `EllesmereUIQuestTracker/EllesmereUIQuestTracker_Forever.lua:703-713`; `EUI_Quickdraw_Paint.lua:552-560` |
| `C_ChatInfo.SendChatMessage` / `SendChatMessage` to PARTY, RAID | allowed outside chat lockdown; refused inside it | `EllesmereUIQuestTracker_Forever.lua:703-713`; `EUI_AuraBuffReminders_Icons.lua:960-969` |
| RAID_WARNING | **probe** (no addon sends it) | none |
| SAY, YELL | need a hardware event | Forever `AutoBiographer/CampfireSharing.lua:752-753` |
| WHISPER | allowed; names have no realm part | `EllesmereUISimpleLootCouncil/Core/Player.lua:418-436`, `Core/Whisper.lua:282` |
| `C_ChatInfo.SendAddonMessage` | allowed; returns `AddOnMessageLockdown` during Encounter, ChallengeMode or Chat restriction | `EllesmereUISimpleLootCouncil/Core/Restrictions.lua:17-56`, `Core/Comms.lua:519-560` (queues and flushes on lift) |
| `CHAT_MSG_*` text and sender | secret during chat lockdown | `EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_ChatBubbles.lua:924-930` |
| `C_PartyInfo.DoCountdown` | refused in chat lockdown | `EllesmereUIQoL_RaidTools.lua:820-856` |
| `DoReadyCheck`, `READY_CHECK` | allowed | `EllesmereUIRaidFrames/EUI_RaidFrames_Lifecycle.lua:338-340`; `EllesmereUIQoL_RaidTools.lua:1056,1383` |

### Other

| API | Verdict | Evidence |
| --- | --- | --- |
| `SecureActionButtonTemplate`, `SecureHandler*` | allowed; attributes OOC only | `ForeverDungeonJournal/Systems/MapMarkers.lua:172-175` |
| LibDBIcon, `AddonCompartmentFrame` / `## AddonCompartmentFunc` | allowed | `ForeverDungeonJournal/ForeverDungeonJournal.toc:7-9`; repo `client-reference.md` |
| `C_Spell.GetSpellInfo`, `C_Item.*`, `C_SpellBook.IsSpellKnown` | allowed; global `GetSpellInfo` **probe** | `WhatsTraining/DataBuilder.lua:142`; `Decursive/DCR_init.lua:63` |
| `GetInstanceInfo`, `IsInInstance`, `InCombatLockdown`, `GetNumGroupMembers`, `IsInRaid`, `UnitIsGroupLeader/Assistant` | allowed | Questie Forever gates `QuestieXP.lua:45,134`; `EllesmereUIQoL_RaidTools.lua:710-746` |
| `PlaySoundFile`, `C_Timer`, `Settings.RegisterCanvasLayoutCategory`, `UISpecialFrames` | allowed | repo `client-reference.md` (probed), except `PlaySoundFile`: no Forever evidence read, low risk |

## Data sources for Forever ids

**Forever reuses the classic id for every piece of vanilla content** (Polymorph 118,
Arcane Brilliance 23028, Flask of the Titans aura 17626, Onyxia 10184). **New Forever
content has new high ids**: npcs about 244000 to 279000, items about 250000 to 290000,
spells about 1210000 to 1330000, instance (map) ids 2791 to 3109, encounter ids about
3300 to 3480. Ids are facts and may be derived from any of these; no code is copied.

| Need | Where | Format | Forever-specific? | License |
| --- | --- | --- | --- | --- |
| Raid buff families (Fortitude, Mark, Spirit, Thorns, every Blessing and Greater Blessing, Intellect, Battle Shout) with every rank and the extra ids that apply them | `EllesmereUI/EllesmereUI_BuffPresets.lua:558-610` (`FOREVER_BUFF_FAMILIES`) | Lua tables `names`, `single`, `group`, `ids` | yes, incl. Forever-only ids (Mark 1291335, 1310503; Kings 1213408) | all rights reserved; ids only |
| Flask, elixir, protection potion aura ids | `EllesmereUI/EllesmereUI_BuffPresets.lua:130-158`; healthstones `:719-731` | Lua lists | classic ids, active under `IS_FOREVER` | as above |
| New Forever consumables (Elixir of Endless Intellect item 289082 / aura 1327736, Scroll of Endless Fortitude 289088 / 1327754, and more) and new items with classic names (stones, oils, potions in 2879xx) | `_forever_\Cache\ADB\enUS\DBCache.bin` (hotfix cache, `XFTH` records) | binary; only hotfixed rows, so absence proves nothing | yes | game data |
| CC spells by rank (Polymorph 118/12824/12825/12826, Pig 28272, Shackle 9484/9485/10955, Mind Control, Sap, Gouge, Blind 2094, Fear 5782/6213/6215, Banish 710/18647, Roots, Hibernate, Freezing Trap 1499/14310/14311, Seduction 6358) | `WhatsTraining/Classes/Camelot/*.lua` | `{ id =, cost =, requiredIds = }` per level | yes (Forever trainer data) | **MIT** |
| New Freezing Trap / Freezing Arrow spells (1288849, 1324500 and others) | DBCache `SpellName` rows | binary | yes; **which id the trap aura carries needs the probe** | game data |
| Dispel and buff spells | `VuhDo/Flavors/Forever/VuhDoConstSpells.lua`, `VuhDoDebuffData.lua`, `VuhDoSecretSpells.lua` (always/never-secret lists) | Lua | Forever flavor, classic ids | all rights reserved unless stated |
| Forever dungeon bosses by npc id (Hall of Thanes 261306, 261311, 261319; Ruins of Lordaeron 250660, 250483, 250631, 256097, 250657, 256035; Dalaran and Wetlands) and instance ids (3065 Hall of Thanes, 2999 Ruins, 2959 Dalaran, 2998 Wetlands) | `ForeverDungeonJournal/Data/Dungeons.lua`, `Core/Journal.lua:1090-1096` | Lua tables `bosses = { { name, npcID, aliases, loot } }`, keyed by `select(8, GetInstanceInfo())` | yes | none stated, treat as all rights reserved |
| Encounter ids with map (Shade of the Archmage 3303 / 2959, Rath'mael 3354 / 2999, Viktor the Vile 3411 / 2999, Min'loth the Serpent 3479 / unknown map 2970) | DBCache `DungeonEncounter` rows; `_forever_\Logs\Hotfix.log` | binary | yes | game data |
| 28.5k npcs, 3,192 Forever-range, with names and zones; Forever instance-to-area table | `QuestieDB/QuestieDB_Camelot.toc` (`## X-Npc-<id>-<field>:` base64 CBOR lines); `QuestieDB/support/Forever/Zones/instanceIdToAreaId.lua:125-140` | CBOR in toc metadata | yes | GPLv3 for new work, inherited content all rights reserved |

**Not on disk anywhere:** Barrow Deeps, the Forever Hyjal Summit (20) and Forever
Onyxia's Lair (40): no boss names, npc ids, encounter ids or instance ids. Onyxia appears
only with classic data (10184, area 2159) plus unzoned Forever npcs "Onyxia Prime" 268401
and "Onyxian Lair Guard" 267197. Also missing: Well Fed auras, classic scroll auras,
weapon oil and stone enchant ids, Trueshot Aura, Repentance, Polymorph: Turtle. These come
from capture in game (`ENCOUNTER_START`, `GetInstanceInfo`, `UnitGUID` in the open world
and wherever the probe says it is readable) or an outside database (ForeverDungeonJournal's
`SOURCES.txt` cites wowforevertalents.com, foreverchanges.pro, wowf.io, wowsrc.com).

Consequence for the raid check: Anniversary MFD recognises buffs **by name**
(`MFD/Data_Auras.lua`). On Forever, recognise them **by spell id**, because the restricted
aura calls are id-gated (`ShouldSpellAuraBeSecret(id)`), and because new Forever
consumables share classic names with new ids.

## Feature by feature

Keep: works as on Anniversary with only a port. Keep with change: the job survives, the
mechanism changes. Cut: no route on this client. Several verdicts hang on a probe answer,
named in brackets as P1 to P12 from the list below.

| Feature | Verdict | What it becomes on Forever |
| --- | --- | --- |
| Marking seats (icon to job plan, pinned players, reserved icons, plan per raid) | **keep** | Pure model, unchanged. Plans per Forever raid (Barrow Deeps, Hyjal, Onyxia) instead of TBC raids. |
| Rules (per zone, kill order, jobs, bulk paste, share/load JSON, merge) | **keep with change** | Model unchanged. Match key becomes the **mob name** inside instances, because the npc id cannot be read there (P2). Npc id stays as an extra key for the open world and for bundled data. Zone key from `GetInstanceInfo` instance id rather than zone text. |
| Learning layer (mobs seen, coverage, search) | **keep with change** | Learn only where `UnitGUID` is not secret (open world; instances only if P2 says out of combat is readable). Bundled data replaces most of it: Forever npc ids from the sources above, raid trash captured in game. |
| Candidates (visible hostile set) | **cut inside instances, keep outside** (P2, P3) | Nameplate units still arrive, but with secret identity in instances the set cannot be matched to rules. If P2 says readable out of combat, keep it as an OOC-only input to the plan. |
| Allocator | **keep with change** | Same pure function. Its input becomes the rule list for the zone or pack (names), not live candidates, and its output feeds the mark macro. Mid-pull reallocation (death frees a seat) is cut: nothing in combat can see the death of a given mob and nothing can re-mark without a press. |
| Placing icons | **keep with change** | One secure button ("Mark pack") whose `macrotext` is written OOC from the allocation: `/targetexact <name>` + `/tm ~<icon>` per seat, then `/targetlasttarget`. Bound to a key and on the action bar. A press marks what is in range. Limits: one mob per name per press (`/targetexact` takes one; P6), macro length (P7), it moves the presser's target. Must be lead or assist in a raid. |
| Clear | **keep with change** | Secure button, `type=raidtarget`, `action=clear-all`. |
| Re-mark | **keep with change** | Clear-all then the mark macro, as one button or two presses. |
| Hold / defend (put back a wiped icon, back off after three) | **cut** | Needs `SetRaidTarget` from Lua and a readable `GetRaidTargetIndex`. |
| Manual override (hand mark wins) | **cut, or OOC only** (P1) | Needs to read icons on mobs. If P1 says `GetRaidTargetIndex` is readable out of combat in raids, the plan can be rebuilt around hand marks before the pull. The `/tm ~N` form already never overwrites a hand mark, which keeps the spirit of it. |
| Lead election, backups, sightings, published assignments (Comms) | **keep with change** (P4) | Election and rule merge OOC only, queued through the addon-message lockdown with `ADDON_RESTRICTION_STATE_CHANGED`. Sightings and backup placement cut: backups cannot place icons from Lua either. Every raider with lead or assist and the addon can press the same macro, so coverage becomes "whoever presses". |
| Conflicts | **keep with change** | Same idea, different list: EllesmereUIQoL raid tools and auto logging, Quickdraw marker slots, ForeverDungeonJournal map markers. Read their saved settings only; touch nothing. |
| Raid check grid | **keep with change** (P5, P8) | Run at ready check or on demand, out of combat. Per person and per buff, ask by spell id through `GetAuraDataBySpellName` / id-gated calls, never index scans (they throw when restricted). If P8 says raid members' auras are secret inside a raid instance even OOC, the grid only works before zoning in or not at all. |
| Consumables (flask or both elixirs, food, toggles per column) | **keep with change** | Id-based tables: classic aura ids plus the Forever Endless line. Food (Well Fed) ids must be captured. |
| Class buffs and blessings with counts | **keep with change** | Ids from the Forever buff families above. "Nobody here can cast it" still works from `GetRaidRosterInfo` classes. |
| Durability | **keep with change** (P9) | Own durability fine. Other people via LibDurability only if addon messages flow at the ready check and if Forever BigWigs/DBM embed LibDurability. |
| Spec inspect | **cut** | One spec per class. Healers come from the role icon (may be secret, P10) or the Extra healers box. |
| Addon version column | **keep** | Over addon messages, OOC. |
| Death announcements per kind (tank, healer) and per boss | **keep with change** (P4, P11, P12) | Death from `UNIT_DIED` (if raid-member GUIDs are readable), else from `UnitIsDead` on raid units watched on `UNIT_HEALTH`/`UNIT_FLAGS` (combat safe). Boss from `ENCOUNTER_START` encounter id (P11), replacing nameplates and the combat log. Announcing needs chat: if chat is locked for the whole encounter, the raid warning cannot be sent during the fight it is about, and this feature is cut in boss fights. Trash deaths depend on P4 too. |
| Tank detection | **keep with change** (P10) | Role icon (`UnitGroupRolesAssigned`, may be secret), `GetPartyAssignment` (no evidence), Extra tanks box. |
| Late crowd control alert | **cut** | Needs in-combat sight of new mobs and in-combat chat. |
| Pack announce as it is marked, add announcements | **cut** | Marking is now a press, not a stream of sightings. |
| Pre-pull announce (Announce button, `/mfd announce`) | **keep with change** (P4) | Same line, from the plan rather than live icons. Sent only when `InChatMessagingLockdown()` is false; otherwise the button says why. |
| Chatter rate limiter | **keep with change** | Same budget, plus a lockdown gate: hold or drop on `InChatMessagingLockdown`, flush on lift. Whisper path kept. |
| Combat logging | **keep** (P12) | `LoggingCombat` from Lua is allowed. Use `GetInstanceInfo` instance ids for the Forever raids. Whether the client writes a usable file is a probe question. |
| Action bar | **keep with change** | Buttons become secure (`SecureActionButtonTemplate`), built OOC; the macro text refreshes on `PLAYER_REGEN_ENABLED` and zone change. Non-secure buttons (toggles, announce) stay plain. Bindings through `Bindings.xml` with `CLICK <button>:LeftButton`. |
| Minimap button | **keep with change** | Addon Compartment first (modern first), LibDBIcon as the legacy extra, once ICKit has a launcher layer (Stickies has one). |
| Assignments panel | **keep** | Shows the plan: seat, job, owner, mob name. |
| CC creature-type warning | **keep with change** (P3) | Works where `UnitCreatureType` of the target is readable; else from bundled data. |
| `fixcvars` | **keep** | `SetCVar` OOC only. Nameplates matter less now (no candidate set in instances). |
| Bad-mark sound, `/mfd log`, `/mfd debug`, `/mfd off` | **keep** | Debug reasons change: no assist, in combat (macro stale), chat locked, no rules for this instance. |
| ChatCue | **keep with change** | Message text is secret during chat lockdown; check `issecretvalue(message)` and stay quiet then. |

## Questions only the client can answer

For the probe lane. Each names the feature it decides.

1. **P1** `GetRaidTargetIndex(unit)` on mobs in a Forever dungeon and raid, in and out of
   combat: secret or a number? Also `SetRaidTargetIconTexture` with a secret index.
   (Manual override, assignments panel icons.)
2. **P2** `UnitGUID` and `UnitName` of a targeted, moused-over and `nameplateN` mob inside
   a Forever dungeon or raid **out of combat**. And `C_Secrets.ShouldUnitIdentityBeSecret`
   for those tokens. (Rules by npc id, learning, candidates.)
3. **P3** `UnitClassification`, `UnitCreatureType`, `UnitLevel`, `UnitIsEnemy` on instance
   mobs, in and out of combat. (CC warning, filtering.)
4. **P4** When `InChatMessagingLockdown()` and the Chat / Encounter addon restrictions are
   on inside a Forever raid: the whole map, only in combat, or only in an encounter?
   (Pre-pull announce, death calls, comms, durability.)
5. **P5** `C_UnitAuras.GetAuraDataByIndex` and `GetAuraDataBySpellName` on another raid
   member, out of combat, in the open world and inside a raid instance: data, secret, or
   an error? (Raid check.)
6. **P6** A secure `macrotext` of `/targetexact <name>` + `/tm ~N` repeated for several
   names: does one press mark several mobs? Does `/targetexact` pick the nearest of two
   same-named mobs, and can `/targetexact` reach a mob with no nameplate? (Mark pack.)
7. **P7** The longest `macrotext` a secure button accepts and runs (255 or more), and
   whether `/tm [@nameplate3] 8` or `/tm [@mouseover] 8` conditionals work. (Mark pack.)
8. **P8** `C_Secrets.ShouldAurasBeSecret()` and `ShouldSpellAuraBeSecret` for the raid
   buff and consumable ids, inside a raid instance out of combat. (Raid check.)
9. **P9** Does `C_ChatInfo.SendAddonMessage` return Success inside a raid instance out of
   combat? Does anyone answer the `LibDRBLT` durability request? (Comms, durability.)
10. **P10** `UnitGroupRolesAssigned` and `GetPartyAssignment("MAINTANK", unit)` on raid
    members, in and out of combat. (Tank and healer calls.)
11. **P11** `ENCOUNTER_START` arguments on a Forever boss: is the encounter id a plain
    number, and are the name, difficulty and group size secret? Then `UNIT_DIED` with a
    raid member's death: is the GUID readable, and does `UnitIsDead("raidN")` flip in
    combat? (Death calls, boss identification.)
12. **P12** `LoggingCombat(true)` inside a Forever instance: is a `WoWCombatLog*.txt`
    written to `_forever_\Logs`, and does it hold full events? (Combat logging.)
13. Presence on 16001 of the globals `SendChatMessage`, `GetSpellInfo`, `UnitAura`,
    `GetTalentTabInfo`, `GetPartyAssignment`, `PlaySoundFile`. And whether `RAID_WARNING`
    sends work at all.
14. Data capture while there: Barrow Deeps, Hyjal Summit and Onyxia's Lair instance ids
    (`select(8, GetInstanceInfo())`), encounter ids, boss and trash npc ids wherever
    readable; the Freezing Trap aura id; Well Fed aura ids.
