# Marked For Death on Forever: design

The design for rebuilding MarkedForDeath (Anniversary 1.29.0, interface 20506) as
`AddonProjects/forever/MarkedForDeath` for WoW Forever (interface 16001, client 1.60.1).
It stands on the static recon in
[2026-11-05-mfd-forever-recon.md](2026-11-05-mfd-forever-recon.md) and on the repo rules in
`CLAUDE.md`, `CODING_STANDARDS.md` and [VISION.md](../VISION.md). The Anniversary addon
stays exactly as it is; nothing here touches `AddonProjects/anniversary`.

No product code is in this document. Every verdict that waits on the in-game probe
(`feature/mfd-forever-probe`, `MFDProbe`) is marked **PENDING-PROBE Pn**, where Pn is the
question id in the recon's "Questions only the client can answer" (P1 to P12, P13 for the
globals, P14 for data capture). Three questions the current probe does not ask are added
here as P15 to P17 (section 15); they need a second probe pass.

## 1. Intent

Marked For Death exists so a raid's crowd control and kill order are the same every night:
the eight raid icons belong to **seats** (Kill 1 to 4, Sheep 1 and 2, Banish 1 and 2), a mob
rule names a job and never an icon, and a pure allocator hands each mob the lowest free seat
of its job. That idea carries over untouched.

What changes is how the plan reaches the mobs. On Forever an addon cannot place a raid icon
from its own code, cannot tell instance mobs apart while restricted, and gets no combat
log. So the Forever addon is a **planner with a trigger**: it works the plan out of combat,
writes it into a secure button, and the player's own keypress applies it. Everything that
was a reaction in Anniversary (defend a wiped icon, re-mark on a death, call a late crowd
control) is either gone or becomes a press.

Dillon's decisions this design follows:

- Build every feature that is still possible and pare back only what the restrictions block.
- The icon seat plan carries over unchanged: Skull, Cross, Square, Circle are Kill 1 to 4;
  Moon is Sheep 1; Star is Sheep 2; Triangle and Diamond are Banish 1 and 2. CC jobs are
  adapted to the vanilla class set only where they must be (section 4).
- Rebuild on ICKit, layers downward, pure logic apart from frames, no client API until it is
  confirmed in `Docs/client-reference.md`.

One change against the Anniversary defaults: Anniversary ships Sheep 1 pinned to
`Grimmtusk`. VISION principle 6 (general audience, no guild assumptions) says the Forever
addon ships with no pins. The icons and jobs are unchanged. **Decided 2026-11-05 by the
MFD Forever coordinator:** ship with no pin; principle 6 wins. A raid pins its own players
on the Roles tab.

## 2. What Forever allows, in one table

Condensed from the recon. "OOC" is out of combat.

| Need | Forever | Probe |
| --- | --- | --- |
| Place a raid icon from Lua | gone (`SetRaidTarget` protected) | P13 confirms |
| Place one from a hardware press on a secure button | allowed, in combat too; attributes set OOC only | P6, P7 |
| Clear all icons | secure `type=raidtarget`, `action=clear-all` | P6 |
| Read an icon on a mob (`GetRaidTargetIndex`) | secret in restricted content | P1 |
| Mob name and npc id inside an instance | secret; readable in the open world | P2 (OOC inside) |
| Combat log payload | gone | settled |
| `ENCOUNTER_START/END` | fire; arguments may be secret | P11 |
| `UNIT_DIED`, `UnitIsDead("raidN")` | fire / allowed; GUID may be secret | P11 |
| Chat to RAID, RAID_WARNING | refused in chat lockdown; scope of lockdown unknown | P4, P13 |
| Addon messages | refused in Encounter, ChallengeMode, Chat restriction | P4, P9 |
| Another member's auras | by spell id only, gated on `ShouldSpellAuraBeSecret` | P5, P8 |
| Specs | one per class; nothing to inspect | settled |
| Roles (`UnitGroupRolesAssigned`, `GetPartyAssignment`) | may be secret / unknown | P10 |
| `LoggingCombat` | callable; whether a file is written is unknown | P12 |

Forever is detected by the interface number from `GetBuildInfo()` (16000 to 19999), never
by `WOW_PROJECT_ID`. The `.toc` carries `## Interface: 16001`. Whether it also needs
`## AllowLoadGameType: camelot` is a build-lane check against an installed Forever addon.

## 3. Every Anniversary feature and its fate

**keep**: works as on Anniversary, ported onto ICKit. **keep changed**: the job survives,
the mechanism changes. **cut**: no route on this client. A verdict with a probe id can move
when the probe answers; the "if the probe says no" column is what ships then.

| Anniversary feature | Fate | Forever form | If the probe says no |
| --- | --- | --- | --- |
| Seat plan (icon to job, pins, reserved icons) | keep | Pure model, unchanged. | n/a |
| A plan per raid | keep changed | Keyed by Forever instance id (`select(8, GetInstanceInfo())`) instead of TBC zone names. Barrow Deeps, Hyjal, Onyxia ids come from capture (section 9). | n/a |
| Rules (kill order, jobs, fallback, maxCount, rank spaced by 10) | keep changed | Model unchanged. Match key is the **mob name** in instances, npc id as a second key where readable (open world, bundled data). | n/a |
| Bulk paste, add by name | keep | The main way to write rules inside instances. | n/a |
| `/mfd add` (rule what you target) | keep changed | Works where the target's name or GUID is readable. PENDING-PROBE P2 for instances. | open world only; inside, the command says "names are hidden here, use /mfd addname" |
| Share / load JSON, export / import, merge | keep changed | Format v2 (section 7.4). Reads Anniversary v1 files. | n/a |
| Learning layer, coverage, mob search | keep changed | Learns only where identity is readable; bundled Forever data plus capture replace most of it. PENDING-PROBE P2. | open world only |
| Candidates (live hostile set) | keep changed | OOC only, from nameplates, and only where identity is readable. Feeds "sighted" marking (section 5.2). PENDING-PROBE P2. | cut inside instances; marking runs "blind" |
| Allocator | keep changed | Same pure function. Input is the sighted candidate set or, blind, the instance's rules as pseudo-candidates. Mid-pull reallocation cut. | n/a |
| Automatic icon placement | keep changed | The **Mark pack** secure button and keybind (section 5). | n/a |
| Clear | keep changed | Secure clear-all button and keybind. PENDING-PROBE P6. | `/tm 0` on target only |
| Re-mark | keep changed | Clear-all then Mark pack. One press if `/click` chains from macrotext (PENDING-PROBE P17), else two presses. | two presses |
| Defend a wiped icon, back off after three | cut | Needs `SetRaidTarget` from Lua and readable icons. | n/a |
| Manual override (a hand mark wins) | keep changed | `/tm ~N` never overwrites a marked mob, which keeps the spirit. Reading hand marks into the plan OOC: PENDING-PROBE P1. | the `~` form only |
| Combat lock, release on mob death | cut | Nothing can re-mark in combat without a press, and mob deaths are invisible. | n/a |
| Coverage guard (nameplate CVars) and `/mfd fixcvars` | keep | `SetCVar` OOC only. Matters only in sighted mode. | n/a |
| Raid Lead designation | keep | Who sends pre-pull and death lines. | n/a |
| Election fallback | keep changed | OOC only, over LibICComm with its lockdown queue. PENDING-PROBE P9. | Raid Lead by designation only; else the raid leader |
| Rule merge over comms | keep changed | OOC only, queued. PENDING-PROBE P9. | share / load by file |
| Peer sightings, backup placement | cut | Backups cannot place icons from Lua either. Anyone with lead or assist presses the same button. | n/a |
| Published assignments | keep changed | The Raid Lead's plan is sent OOC so every client's assignment panel agrees. PENDING-PROBE P9. | each client computes its own (same inputs, same result) |
| Assignment panel | keep | Seat, icon, job, owner, mob name. Icons drawn from the seat plan, not read off mobs. | n/a |
| Pre-pull announce (button, `/mfd announce`) | keep changed | Built from the plan; sent only outside chat lockdown, else the button says why. PENDING-PROBE P4. | n/a |
| Pack announce as it is marked, add announcements | cut | Marking is a press, not a stream of sightings. | n/a |
| Late crowd control alert | cut | Needs in-combat sight of new mobs and in-combat chat. | n/a |
| Death calls per kind (tank, healer), trash yes/no, per boss ticks, overrides, one per person per fight | keep changed | Section 6. Boss from `ENCOUNTER_START`; death from `UNIT_DIED` or `UnitIsDead`; chat queued through lockdown. PENDING-PROBE P4, P10, P11. | local alert only during encounters |
| Tank detection | keep changed | Role icon, `GetPartyAssignment("MAINTANK")`, Extra tanks box. PENDING-PROBE P10. | Extra tanks box |
| Healer detection | keep changed | Role icon or Extra healers box. Spec inspect is gone (one spec per class). PENDING-PROBE P10. | Extra healers box |
| Raid check grid | keep changed | By spell id, OOC, at ready check or on demand. PENDING-PROBE P5, P8. | works only before zoning in, or cut |
| Consumables columns | keep changed | Id tables: classic aura ids plus the Forever "Endless" line; Well Fed from capture. | n/a |
| Class buffs, blessings, counts, "nobody can cast it" | keep changed | Forever buff family ids; casters from roster classes. | n/a |
| Spec column, inspect pump | cut | One spec per class. | n/a |
| Durability | keep changed | Own durability always. Others over LibDurability (`LibDRBLT`). PENDING-PROBE P9. | own only |
| Addon version column | keep | Over LibICComm, OOC. PENDING-PROBE P9. | blank |
| Buff board, `/mfd missing`, `/mfd callout`, `/mfd auras` | keep changed | Same views over the id-based model; callout queued through chat lockdown. | n/a |
| `/mfd readycheck` | keep | `DoReadyCheck` is allowed. | n/a |
| Combat logging | keep | `LoggingCombat` on entering a listed Forever raid. PENDING-PROBE P12 (does a file appear). | toggle kept, docs say the file may be empty |
| Conflicts | keep changed | New list: EllesmereUIQoL raid tools and auto logging, EllesmereUIQuickdraw marker slots, ForeverDungeonJournal map markers, MRT if present. Read their saved settings, touch nothing. | n/a |
| CC creature-type warning, bad-mark sound | keep changed | Where `UnitCreatureType` of the target is readable, else from bundled data. PENDING-PROBE P3. | bundled data only |
| ChatCue (sound on one word) | keep changed | Quiet while the message is secret (`issecretvalue`). | n/a |
| Action bar | keep changed | Secure buttons (Mark pack, Clear, Re-mark) beside plain ones (Announce, Tank calls, Healer calls, Marking on/off). Built OOC, refreshed OOC. | n/a |
| Keybinds | keep changed | `Bindings.xml` with `CLICK MFDMarkPack:LeftButton` style bindings for the secure ones. | n/a |
| Minimap button | keep changed | Addon Compartment first, ICKit rim button as the hideable extra (as Stickies and RenderTuner). | n/a |
| One window with tabs, resizable panels | keep | ICKit widgets (needs Tabs, List, Resize, TextArea: section 10). | n/a |
| `/mfd log`, `/mfd debug`, `/mfd off|on`, `/mfd out`, `/mfd scale`, `/mfd reset` | keep changed | Debug reasons change (section 5.6). | n/a |
| `/mfd candidates` | keep changed | Sighted mode only; blind it says why. | n/a |
| `/mfd where` | keep changed | Instance id and name, rules active, sighted or blind. | n/a |
| `/mfd coverage` | keep changed | Names seen by capture that no rule or bundled table lists. | n/a |
| New: `/mfd capture` | new | Section 9. | n/a |

## 4. Jobs on the vanilla class set

Forever runs vanilla classes. The seat plan is unchanged; the intent table is pared to what
those classes have.

| Intent | Classes | Forever spell ids (derived, section 8) | Note |
| --- | --- | --- | --- |
| KILL | any | none | always seated |
| SHEEP | MAGE | Polymorph 118, 12824, 12825, 12826; Pig 28272; Turtle 28271 PENDING-PROBE P14 | |
| TRAP | HUNTER | Freezing Trap 1499, 14310, 14311; Forever trap and arrow ids 1288845 to 1324502; **trap aura id PENDING-PROBE P14** | |
| BANISH | WARLOCK | 710, 18647 | |
| SEDUCE | WARLOCK | Seduction 6358 (pet spell); aura id PENDING-PROBE P14 | |
| ENSLAVE | WARLOCK | Enslave Demon, ids from WhatsTraining Camelot data | |
| FEAR | WARLOCK, PRIEST | 5782, 6213, 6215 | |
| SAP | ROGUE | 6770, 2070, 11297 | |
| SHACKLE | PRIEST | 9484, 9485, 10955 | |
| MINDCONTROL | PRIEST | 605, 10911, 10912 | |
| HIBERNATE | DRUID | 2637, 18657, 18658 | |
| ROOTS | DRUID | 339, 1062, 5195, 5196, 9852, 9853 | |
| REPENTANCE | PALADIN | none found on Forever | hidden from the job picker until P14 finds a spell id; a rule already holding it falls back |
| IGNORE | none | none | never marked |

The capability table is data (`Data_CC.lua`), so a class that gains a job on Forever is one
row. Spell ids are used by the CC creature-type warning and the raid check's "who can cast
it"; seat ownership only needs classes.

## 5. Marking

### 5.1 The flow

1. **Out of combat, continuously but only on change**, the addon recomputes the allocation
   and writes it into the secure **Mark pack** button. Triggers: entering an instance,
   roster change, a rule or plan edit, `PLAYER_REGEN_ENABLED`, and, in sighted mode, a
   nameplate added or removed (debounced to one rebuild per 0.5 s, no `OnUpdate`).
2. **The player presses Mark pack** (action bar button or keybind), in or out of combat.
   The macro targets each planned mob by name and marks it with its seat's icon, only if
   the mob is unmarked, then puts the player's target back.
3. **In combat nothing is rebuilt.** The button keeps the last plan written. A plan edit in
   combat is held and written on `PLAYER_REGEN_ENABLED`, and the bar shows a "stale" tint
   until then.

Pressing needs raid leader or assist in a raid (any member in a party). The addon cannot
stop a press from a player without rights; it greys the bar button and the Debug reasons
say why. The macro is the same on every client with the same inputs, so any lead or
assist with the addon can press it.

### 5.2 Sighted and blind

**Sighted** (PENDING-PROBE P2: instance mob identity readable OOC). The candidate set is
built OOC from `NAME_PLATE_UNIT_ADDED/REMOVED`, target and mouseover, as in Anniversary but
never in combat. The allocator sees the actual pack, so three copies of one mob can hold
three seats. Multi-copy marking still depends on how `/targetexact` picks between
same-named mobs (PENDING-PROBE P6); if it always takes the nearest, the macro uses one line
per distinct name and the extra copies wait for a second press after the first is marked
(`~` skips the marked one only if targeting cycles; P6 decides which).

**Blind** (identity secret inside instances, the expected case). There is no pack to see.
The allocator takes the instance's rules as pseudo-candidates, one per rule (maxCount is
ignored because one name marks one mob per press), and the macro lists them in rank order.
A press marks whichever of those names are in range; names not in range do nothing. The
player sees the plan on the assignment panel and the names on nameplates.

Which mode runs is decided per instance at runtime by `C_Secrets.ShouldUnitIdentityBeSecret`
and `issecretvalue` on a read, never by flavour, so a later client change switches it on
its own.

### 5.3 The macro

`MarkPlan.Build(assignments, limit)` is pure and returns `text, dropped`:

```
/targetexact Scarlet Sorcerer
/tm ~8
/targetexact Scarlet Monk
/tm ~7
...
/targetlasttarget
```

- One `/targetexact` + `/tm ~<icon>` pair per seat, in seat-then-rank order so Skull is
  always written first.
- The text is cut at `limit` bytes on a whole pair; `dropped` lists the seats that did not
  fit and the Debug reasons print them. `limit` is 255 until PENDING-PROBE P7 says longer
  macrotext runs.
- If P7 says longer text is refused, the plan splits over two chained buttons, the first
  ending in `/click MFDMarkPack2` (PENDING-PROBE P17).
- `/targetlasttarget` at the end, restoring the player's target. Whether it restores
  correctly after several retargets is PENDING-PROBE P6.
- Names are matched exactly; the rule stores the name as the game shows it. Names with
  quotes or semicolons are refused at rule entry.
- Conditional forms (`/tm [@mouseover,exists] ~8`, `/tm [@nameplate1,exists] ~7`) are
  PENDING-PROBE P7. If they work, see 5.4.

### 5.4 Mark mouseover (optional, PENDING-PROBE P7 and P15)

A second secure button, **Mark mouseover**, marks the mob under the pointer with the next
free seat of the KILL intent. It needs `/tm [@mouseover,harm,nodead] ~N` (P7) and a secure
snippet that advances N inside the restricted environment between presses, in combat
(P15). If either fails, the button is not built. This is the one route to marking mobs
that have no rule, which blind mode otherwise cannot touch.

### 5.5 Clear and re-mark

- **Clear**: secure button, `type=raidtarget`, `action=clear-all`. PENDING-PROBE P6 (the
  probe's "Clear all" click). If refused, the button becomes `/tm 0` on the target and the
  label says "Clear target".
- **Re-mark**: Clear then Mark pack. One button whose macrotext is `/click MFDClear` then the
  Mark pack lines if P17 says `/click` works there; otherwise two presses and the button is
  not built.

### 5.6 Debug reasons, most fundamental first

`Debug.WhyNot(state)` is pure and returns an ordered list: addon off; not in a group (fine,
marks work solo); no lead or assist in a raid; in combat and the plan changed since the
pull (stale); no rules for this instance; blind mode (names hidden here, rules by name
only); macro too long, N seats dropped; secure button not built yet (first OOC moment after
login); conflicting marker addon active.

## 6. Death calls

### 6.1 What dies

`DeathWatch.lua` registers events only while a death setting asks for them (idle means zero
work). Sources, in order of preference:

1. `UNIT_DIED(guid)` where the GUID is not secret and maps to a raid unit through
   `UnitGUID("raidN")` taken OOC (PENDING-PROBE P11).
2. Otherwise `UnitIsDead("raidN")` read on `UNIT_HEALTH` and `UNIT_FLAGS` for raid units
   only, edge-triggered (alive to dead) per unit (PENDING-PROBE P11: does it flip in combat).

Who is a tank or healer is fixed OOC at the pull from the roster snapshot (role icon,
Main Tank, Extra boxes; PENDING-PROBE P10), so nothing secret is read in combat.

### 6.2 Which fight

`ENCOUNTER_START(encounterID, name, difficulty, size)` gives the boss. The encounter id is
the key for the per-boss ticks; the name is display only and is taken from `Data_Instances`
when the event's name is secret. PENDING-PROBE P11 (is the id a plain number). If the id is
secret, every encounter counts as "boss, unknown" and only the trash/boss split and the
overrides apply. Trash is everything in combat outside an encounter. One warning per person
per fight, reset at `PLAYER_REGEN_DISABLED` or `ENCOUNTER_START`, as in Anniversary.

### 6.3 Saying it

`Deaths.Decide(event, state)` is pure and returns a plan: say / queue / local-only / skip,
with the reason (the Anniversary `Decide`/`Act` shape). Only the Raid Lead's client says
anything.

- Chat open: RAID_WARNING (PENDING-PROBE P13: does RAID_WARNING send), else RAID.
- Chat locked (`C_ChatInfo.InChatMessagingLockdown()`): queued in LibICChat with a time to
  live of 10 seconds (setting). If the lockdown lifts within it, the line goes; otherwise it
  is dropped and logged. Whether trash fights lock chat at all is PENDING-PROBE P4; if chat
  is locked for every raid map, death calls are never sent to chat inside raids.
- Always, when enabled: a **local alert** on the Raid Lead's screen (the client's raid
  warning frame via `RaidNotice_AddMessage`, PENDING-PROBE P16; else an ICKit label flash)
  plus the death sound. This is what survives a locked encounter.

### 6.4 Pre-pull announce and callouts

`Announce.Lines(plan, roster)` is pure. The Announce button, `/mfd announce` and the raid
check callout send through the same LibICChat path; in chat lockdown they are refused (not
queued: a pre-pull line after the pull is wrong) and the button says "chat is locked here".
PENDING-PROBE P4.

## 7. Rules, plans and data model

### 7.1 Keys

- Instance key: `"i:<instanceID>"` for an instance, `"open"` for the open world.
- Rule key: `"n:<name as shown>"` by default; `"id:<npcID>"` when only the id is known
  (bundled data, open world). A rule may carry both; the name is what the macro uses, so a
  rule with only an id is shown in amber as "no name yet" and is skipped by the macro.

### 7.2 Rule

```lua
{ name = "Scarlet Sorcerer", npcID = 4294, intent = "SHEEP", rank = 20,
  fallback = "KILL", maxCount = 2, from = "me", updated = 1793836800 }
```

### 7.3 Seat plan

Unchanged from Anniversary: keyed by icon 1 to 8, `{ intent, ordinal, pin, reserved }`.
Default plan as in section 1, no pins. Plans per instance key; an instance follows
`default` until its first edit copies it.

### 7.4 Share format v2

JSON, sorted and indented, plain words (`job`, `priority`, `npc`, `name`) as in
Anniversary, with `formatVersion = 2` and instance keys as above. The reader accepts v1
(Anniversary) files: rules move across with their names and npc ids, zone-name keys become
`"legacy:<zone>"` and are listed as "not a Forever instance" until the player moves them.
A newer version, an unknown job or a non-MFD file is refused whole.

## 8. Data sources and licences

Ids and names are facts and may be derived from anything below. **No code, file or table
layout is copied** from any of them; the data files are written fresh, by hand or by a repo
script that emits our own format.

| Data | Source | Licence | How used |
| --- | --- | --- | --- |
| CC spell ids by rank | `WhatsTraining/Classes/Camelot/*.lua` | MIT | ids only, typed into `Data_CC.lua` |
| Raid buff families, Forever-only ids (Mark 1291335, 1310503; Kings 1213408), flasks, elixirs, protection potions, healthstones | `EllesmereUI/EllesmereUI_BuffPresets.lua` | all rights reserved | ids only, typed into `Data_Auras.lua` |
| Forever consumables (Endless line, e.g. aura 1327736, 1327754) | client hotfix cache `_forever_\Cache\ADB\enUS\DBCache.bin` | game data | ids and names |
| Dispel and always/never-secret spell lists | `VuhDo/Flavors/Forever/*` | all rights reserved | cross-check of `ShouldSpellAuraBeSecret` expectations only |
| Forever dungeon bosses, instance ids | `ForeverDungeonJournal/Data/Dungeons.lua` | none stated: treated as all rights reserved | ids and names only |
| Encounter ids | DBCache `DungeonEncounter` rows, `_forever_\Logs\Hotfix.log` | game data | ids and names |
| Forever npc names and zones | QuestieDB Camelot build | GPLv3 for new work, inherited content all rights reserved | ids and names only; never vendor the database |
| Anything not on disk | `ENCOUNTER_START`, `GetInstanceInfo`, readable `UnitGUID` in game (capture mode) | own observation | primary source for the raids |

**Ids needing in-game capture (PENDING-PROBE P14 and the first Dec 9 raids):** instance ids
of Barrow Deeps, Forever Hyjal Summit (20) and Forever Onyxia's Lair (40); their encounter
ids and boss names; boss and trash npc ids and names wherever identity is readable; the
Freezing Trap aura id; Seduction aura id; Well Fed aura ids; classic scroll auras; weapon oil
and stone enchant ids; Trueshot Aura; Repentance and Polymorph: Turtle (do they exist).

## 9. Capture mode

`/mfd capture on|off|show|export|clear`. Off by default; while off nothing is registered.
While on:

- `GetInstanceInfo` on every zone change: instance id, name, type, size.
- `ENCOUNTER_START/END`: encounter id, name (where not secret), instance id, kill or wipe.
- Target, mouseover and nameplates OOC: npc id and name **only when not secret**, with the
  instance id. Secret reads are counted, not stored, so the coverage line can say "42 mobs
  seen, names hidden".
- Own auras OOC (open world, or where `ShouldAurasBeSecret()` is false): spell id and name,
  to catch Well Fed, scrolls and weapon enchants. The trap aura sits on a mob, which this
  cannot read, so a hunter's capture records the spell id of their own trap cast from
  `UNIT_SPELLCAST_SUCCEEDED` on `"player"` instead.
- Raid icons the player places by hand are not captured (P1).

`Capture.Merge(store, observation, now)` is pure and caps the store (2,000 npcs, 200
encounters, 500 auras, oldest dropped). `/mfd capture export` prints a JSON string in a copy
box. A repo script, `scripts/mfd-forever-capture.lua`, merges any number of exports into the
`Data_Instances.lua` and `Data_Mobs.lua` source the addon ships, so the guild's first Dec 9
raids fill Barrow Deeps, Hyjal and Onyxia in one pass. The script is pure Lua under LuaJIT
and has its own cases.

## 10. ICKit: what exists and what is needed

Existing (ICKit 0.3.0): `LibICUtil` (L0), `LibICTest` (L0), `LibICEnv` (L1), `LibICStore`
(L1), `LibICConsole` (L1), `LibICTheme` (L1), `LibICWidgets` (L2, incl. Compartment and
MinimapButton). MFD uses all seven.

Needed, each its own ICKit change (branch, MINOR bump, `Docs/ICKit.md` row, cases, the
VISION layer table), in this order because each depends only downward:

| # | Change | Layer | What | Depends on |
| --- | --- | --- | --- | --- |
| K1 | `LibICEnv` fix | 1 | `Env.Try` builds its text inside the `pcall` and marks secret returns instead of concatenating them (the probe lane's finding). | n/a |
| K2 | `LibICJSON-1.0` | 0 | Encode (sorted, indented) and decode, pure. Lifted from Anniversary MFD `JSON.lua`, which is ours. | n/a |
| K3 | `LibICRestrict-1.0` | 1 | `IsSecret(v)`, `Readable(v)`; restriction state (`Active(kind)`, `ChatLocked()`, `InCombat()`) over `C_RestrictedActions`, `C_ChatInfo.InChatMessagingLockdown` and `InCombatLockdown`; `OnChange(fn)` over `ADDON_RESTRICTION_STATE_CHANGED` plus `PLAYER_REGEN_*` (the "only activating fires" quirk). Pure decision half `Restrict.State(rows)`. | Env |
| K4 | `LibICGroup-1.0` | 1 | Roster snapshot OOC: name, class, rank, online, role, Main Tank, each guarded for secrets; lead/assist; `Group.Snapshot(rows)` pure half. | Restrict |
| K5 | `LibICChat-1.0` | 1 | Outgoing chat: per-channel budget, refusal reasons, lockdown queue with time to live, flush on lift. Pure `Chat.Decide(line, state)`. | Restrict |
| K6 | `LibICComm-1.0` | 1 | Addon messages: prefix, chunking, own-echo drop, version hello, `AddOnMessageLockdown` queue and flush. Pure framing half. | Restrict |
| K7 | `LibICSecure-1.0` | 2 | Secure buttons: `Secure.MacroButton(name, opts)`, `Secure.ClearAllButton(name)`, `SetMacro(button, text)` deferred to `PLAYER_REGEN_ENABLED` while locked, binding names. Pure `Secure.Fit(lines, limit)`. | Restrict |
| K8 | `LibICWidgets` additions | 2 | `W.Tabs`, `W.List` (fixed header row above a scroll, fixed-height single-line rows, pooled), `W.Resize` grip, `W.TextArea` (multi-line paste box), `W.RaidIcon(parent, index)` (texcoords pure). One commit per widget. | Theme |

K1 to K3 block the most work and go first. K2 is independent and can go any time. MFD may
not call any of these until its change has merged.

## 11. Saved variables, schema v1

Account table `MarkedForDeathDB`, character table `MarkedForDeathCharDB` (same names as
Anniversary is fine: different client, different `WTF`). Registered through LibICStore
with `schema = 1`, `charSchema = 1`, `migrations = {}` and `charMigrations = {}` from the
first build, and a case that boots an empty table, a v1 fixture and a fixture missing every
optional field.

```lua
MarkedForDeathDB = {
    schema = 1,
    settings = {
        enabled = true, debug = false, sound = true,
        raidLead = nil,                       -- name, or nil for the raid leader
        announce = { prepull = true, channel = "RAID" },
        marking = { mouseover = false, rebuildDebounce = 0.5 },
        chat = { deathTTL = 10 },
        logCombat = { enabled = true, instances = {} },   -- [instanceKey] = true
        capture = false,
        cue = { enabled = false, word = "", sound = "" },
        minimap = { hidden = false, angle = 200 },
    },
    plans = {
        default = { [8] = { intent = "KILL", ordinal = 1 }, ... },   -- section 1
        -- ["i:<id>"] = { ... } once edited
    },
    rules = {
        -- ["i:<id>" | "open" | "legacy:<zone>"] = { ["n:<name>" | "id:<npc>"] = rule }
    },
    deaths = {
        tank   = { on = true,  trash = true,  override = "auto", extra = {}, bosses = {} },
        healer = { on = false, trash = false, override = "auto", extra = {}, bosses = {} },
        -- bosses: [encounterID] = true
    },
    check = {
        columns = { flask = true, food = true, buffs = true, durability = true, version = true },
        minDurability = 50,
    },
    learned = {},     -- ["i:<id>"|"open"] = { [npcID] = { name, seen } }, readable sightings only
    capture = { instances = {}, encounters = {}, npcs = {}, auras = {}, hidden = 0 },
    log = { head = 0, entries = {} },   -- ring of 500
}

MarkedForDeathCharDB = {
    schema = 1,
    windows = { main = { fx, fy, w, h, tab }, assignments = {}, board = {} },
    bar = { shown = true, locked = false, outsideRaid = false, fx, fy, w, h },
    planEditing = "default",
}
```

Rules for later versions: a field with a default needs no step; a change that reads the old
shape adds `migrations[1]` and moves `schema` to 2 in the same commit, with a case that
boots the v1 fixture. Steps never delete player data.

## 12. Modules

Every module opens `local addonName, ns = ...` and claims `ns.<Name>`. Pure modules call no
client API ever; frame modules call the client only inside functions registered from
`Core.lua`'s ready hook. Each lane writes its own `Tests_<Lane>.lua`; `Tests.lua` only runs
the registry.

| Module | Kind | Job | Headless cases it needs |
| --- | --- | --- | --- |
| `Core.lua` | frame | Store, Console, event frame, `ns.AddCommand(name, desc, fn)` so no lane edits a central table, ready hook list | load lines; a lost account table prints the red warning |
| `Schema.lua` | pure | defaults, schema, migrations (section 11) | boot empty; boot v1 fixture; missing optional fields filled; stored `false` kept |
| `Data_CC.lua` | pure | intents, capable classes, CC spell ids | every intent has a class list; REPENTANCE flagged hidden |
| `Data_Auras.lua` | pure | buff families, consumables by spell id | no id in two families; Forever-only ids present |
| `Data_Instances.lua` | pure | instance ids, encounter ids, boss names | lookups by id; unknown id returns nil not error |
| `Data_Mobs.lua` | pure | npc id to name per instance (generated) | generated file parses; no duplicate keys |
| `Seats.lua` | pure | ownership resolution | pin present; pin offline; pin wrong class; zero capable class; one warlock holds banish and fear; name-ascending order |
| `Rules.lua` | pure | keys, rank, merge, share v2, read v1 | key by name and by id; merge keeps mine; v1 file imports with legacy keys; newer version refused; unknown job refused; quotes in a name refused |
| `Allocator.lua` | pure | allocation | three copies; more rules than icons; reserved icon not lent; fallback when no owner; maxCount; rank tie broken by key; blind pseudo-candidates |
| `MarkPlan.lua` | pure | assignments to macro text, fit to limit, split, clear and re-mark text | Skull first; cut on a whole pair; dropped list; 255 and 1023 limits; chain split; empty plan gives empty text |
| `Debug.lua` | pure | `WhyNot(state)` ordered reasons | each reason alone; order when several hold |
| `Deaths.lua` | pure | `Decide(event, state)` | tank on trash; healer off on trash; per-boss tick; override on/off; once per person per fight; reset on pull; chat locked queues; TTL expiry drops; not Raid Lead says nothing |
| `Announce.lua` | pure | pre-pull lines, callout lines | empty plan; lines under 255; locked chat refuses |
| `RaidCheckModel.lua` | pure | aura answers to grid, missing list, callout groups | flask or two elixirs; nobody can cast; secret answer shows grey "unknown", not "missing" |
| `Conflicts.lua` | pure | other addons' settings to findings | each known addon on and off; absent addon |
| `Capture.lua` | pure | merge observations, caps, export JSON | caps drop oldest; secret reads counted only; export round-trips |
| `Lead.lua` | pure | Raid Lead and election from roster and hellos | designated wins; leader fallback; election tie by name |
| `Log.lua` | pure | ring buffer | wrap at 500; filter by kind |
| `Sense.lua` | frame | instance, roster via LibICGroup, sighted candidates OOC | headless: returns early on `IC_HEADLESS` |
| `MarkButtons.lua` | frame | secure Mark pack, Clear, Re-mark, Mark mouseover via LibICSecure; rebuild on triggers | stale flag logic is in `MarkPlan`; frame half returns early |
| `DeathWatch.lua` | frame | events in 6.1 and 6.2, calls `Deaths.Decide`, acts | returns early |
| `RaidCheck.lua` | frame | asks auras by id per member OOC, ready check, durability | returns early |
| `Comms.lua` | frame | LibICComm wiring: hello, rules merge, published plan | returns early |
| `CombatLog.lua` | frame | `LoggingCombat` on listed instances | decision is a pure `ShouldLog(instanceKey, settings)` in the same file with a case |
| `CaptureWatch.lua` | frame | capture events while on | returns early |
| `ChatCue.lua` | frame | sound on one word, quiet on secret | pure `Matches(text, word)` case |
| `UI_Main.lua` | frame | window, tabs, `ns.UI.AddTab(key, label, build)` | returns early |
| `UI_Roles.lua`, `UI_Rules.lua`, `UI_Assignments.lua`, `UI_Settings.lua` | frame | pages and the assignment panel | return early; all logic they show comes from pure modules |
| `UI_RaidCheck.lua` | frame | grid and buff board | returns early |
| `UI_Deaths.lua` | frame | deaths tab | returns early |
| `UI_Bar.lua` | frame | action bar: secure buttons from `MarkButtons`, plain ones | returns early |
| `Launcher.lua` | frame | compartment entry and rim button | returns early |
| `Bindings.xml` | n/a | keybinds incl. `CLICK MFDMarkPack:LeftButton` | lint: never in the `.toc` |

Load order in the `.toc`: Core, Schema, Data_*, pure modules, frame modules, UI_Main, UI
pages, UI_Bar, Launcher, Tests_*, Tests.

## 13. Build order and lanes

Lanes run in parallel, each on its own branch and worktree. **No two lanes touch the same
file.** The scaffold lane writes the `.toc` with every file listed and an empty stub for
each, so later lanes only fill files they own.

| Lane | Owns (only these files) | Needs first | Probe answers it waits for |
| --- | --- | --- | --- |
| **K: ICKit** (one lane, K1 to K8 as separate PRs in order) | everything under `AddonProjects/forever/ICKit/`, `Docs/ICKit.md`, the layer table in `Docs/forever/VISION.md` | n/a | K3 and K7 confirm against P4, P6, P7, P9 before merge |
| **S: Scaffold** | `MarkedForDeath.toc`, `Core.lua`, `Schema.lua`, `Tests.lua`, every module stub, the row in `AddonProjects/forever/README.md` | K1 | none |
| **A: Model** | `Data_CC.lua`, `Seats.lua`, `Rules.lua`, `Allocator.lua`, `MarkPlan.lua`, `Debug.lua`, `Log.lua`, `Tests_Model.lua` | S, K2 | P6, P7 set MarkPlan's limit and split, both behind constants |
| **B: Marking runtime** | `Sense.lua`, `MarkButtons.lua`, `UI_Bar.lua`, `Bindings.xml`, `Tests_Marking.lua` | S, A, K3, K4, K7 | P1, P2, P6, P7, P15, P17 |
| **C: Raid check** | `Data_Auras.lua`, `RaidCheckModel.lua`, `RaidCheck.lua`, `UI_RaidCheck.lua`, `Tests_RaidCheck.lua` | S, K3, K4, K6, K8 | P5, P8, P9 |
| **D: Deaths and chat** | `Deaths.lua`, `Announce.lua`, `DeathWatch.lua`, `ChatCue.lua`, `UI_Deaths.lua`, `Tests_Deaths.lua` | S, K3, K4, K5, K8 | P4, P10, P11, P13, P16 |
| **E: Data and capture** | `Data_Instances.lua`, `Data_Mobs.lua`, `Capture.lua`, `CaptureWatch.lua`, `scripts/mfd-forever-capture.lua`, `Tests_Capture.lua` | S, K2, K3 | P2, P11, P14; the Dec 9 raids |
| **F: Comms and lead** | `Lead.lua`, `Comms.lua`, `Tests_Comms.lua` | S, K6 | P9 |
| **G: Window and config** | `UI_Main.lua`, `UI_Roles.lua`, `UI_Rules.lua`, `UI_Assignments.lua`, `UI_Settings.lua`, `Launcher.lua`, `Tests_UI.lua` | S, A, K8 | P1 (icons on the panel) |
| **H: Ops** | `CombatLog.lua`, `Conflicts.lua`, `Tests_Ops.lua` | S, K3 | P12 |
| **P: Probe results** | `Docs/client-reference.md`, this spec's PENDING-PROBE marks | the probe run | all |
| **W: User guide** (last) | `Docs/forever/MarkedForDeath.md` | A to H merged | none |

Settings a lane needs that are not in section 11 go to the coordinator, who has the S lane
owner add them to `Schema.lua`; no other lane edits it. Commands are added with
`ns.AddCommand` from the owning module, so `Core.lua` stays with S.

Order: K1 and K2 now; S as soon as K1 merges; A, E (pure halves) and H straight after S,
since they need no probe answer; K3 to K8 in order; then B, C, D, F, G as their ICKit pieces
land and the probe answers arrive. The first build worth putting in front of the raid is
S + A + B + G: the plan, the Mark pack button and the window.

## 14. Errors and limits

- Every secure attribute change goes through LibICSecure, which defers while locked and
  never throws.
- Every read that may be secret goes through LibICRestrict; a secret answer is "unknown"
  in the model (grey), never "missing" (red).
- Waits (raid check answers, comms hello, durability) are state machines with timeouts, as
  `CLAUDE.md` asks.
- Idle cost is zero: sighted candidates, death watch and capture register their events only
  while in use. `Env.Wrap` counts every handler, so `/ickit profile` covers MFD.

## 15. PENDING-PROBE list

| Id | Question (short) | Decides |
| --- | --- | --- |
| P1 | `GetRaidTargetIndex` on instance mobs in and out of combat; `SetRaidTargetIconTexture` with a secret index | manual override OOC; reading hand marks into the plan |
| P2 | Instance mob `UnitGUID`/`UnitName` OOC; `ShouldUnitIdentityBeSecret` | sighted vs blind; `/mfd add`; learning; capture of npc ids |
| P3 | `UnitCreatureType`, `UnitClassification` on instance mobs | CC creature-type warning |
| P4 | Chat and addon-message lockdown scope in a raid: map, combat, or encounter | pre-pull announce, death calls, callouts, comms |
| P5 | Another member's auras by index and by name, OOC, open world and in a raid | raid check |
| P6 | One press marks several names; nearest of two same-named; clear-all; `/targetlasttarget` | Mark pack, Clear, multi-copy marking |
| P7 | Longest macrotext; `@mouseover` / `@nameplateN` conditionals | MarkPlan limit; Mark mouseover |
| P8 | `ShouldAurasBeSecret`, `ShouldSpellAuraBeSecret` for buff and consumable ids in a raid OOC | raid check |
| P9 | Addon messages in a raid OOC; LibDurability answers | comms, election, version, durability |
| P10 | `UnitGroupRolesAssigned`, `GetPartyAssignment("MAINTANK")` | tank and healer detection |
| P11 | `ENCOUNTER_START` arguments; `UNIT_DIED` GUID; `UnitIsDead("raidN")` in combat | death calls, boss ticks, capture of encounters |
| P12 | `LoggingCombat` writes a usable file | combat logging |
| P13 | Globals present (`SendChatMessage`, `GetSpellInfo`, `UnitAura`, `GetPartyAssignment`, `PlaySoundFile`); RAID_WARNING sends | chat path, sounds |
| P14 | Capture: raid instance and encounter ids, npc ids, trap / Well Fed / scroll / enchant / Trueshot / Repentance / Turtle ids | data files, REPENTANCE and Turtle |
| P15 | **New, not in the current probe:** a secure snippet changing a button's macrotext between presses in combat | Mark mouseover |
| P16 | **New:** `RaidNotice_AddMessage` on `RaidWarningFrame` from addon code in an encounter | local death alert |
| P17 | **New:** `/click <SecureButton>` inside a secure button's macrotext | Re-mark as one press; long plans split over two buttons |

When the probe results are in, lane P rewrites each PENDING-PROBE mark above to the
answer, moves the "if the probe says no" column into the feature table where it applies,
and records every confirmed API in `Docs/client-reference.md`.
