# Marked For Death: design

Status: approved design, not yet implemented
Flavor: anniversary (TBC 2.5.6, Interface 20506)
Addon folder: `AddonProjects/anniversary/MarkedForDeath/`
Guide: `Docs/MarkedForDeath.md`

## 1. Purpose

Automatically place raid target icons on trash mobs as a raid approaches them, so that
kill order and crowd control assignments are visible before the pull rather than called
out verbally during it. Secondarily, audit raid buffs and consumables so the raid leader
can see who is missing what without a full ready check.

Both halves ship in one addon at the user's direction. The scope risk of combining two
independent subsystems was raised and the user chose to combine them anyway.

## 2. Why the existing tools fail

Method Raid Tools is the incumbent. Its automarker lives in `MRT/MarksSimple.lua` and
works like this: mob names are lowercased and looked up in a flat table, each name
carries an allowed-icon priority string, and icons are drawn from one global `marksUsed`
pool that is only released on `UNIT_DIED` or `ENCOUNTER_END`. Placement is triggered
per unit from `NAME_PLATE_UNIT_ADDED`, `UNIT_TARGET`, `UPDATE_MOUSEOVER_UNIT` and
`UNIT_NAME_UPDATE`.

Three structural consequences, which match the two failures the user reports:

1. **Icons go out in sighting order, not priority order.** Because each unit is handled
   in isolation as it is seen, the first mob whose nameplate loads takes the first free
   icon. Nameplate load order depends on camera facing and pathing, so the same pack
   produces different marks on different pulls. This is not a bug that can be fixed
   inside a per-unit design.
2. **Coverage is capped at one player's nameplates.** A mob outside the marker's
   nameplate range or behind them is never seen and never marked.
3. **Marks are fire and forget.** Once placed, a cleared or overwritten icon is never
   restored.

Marked For Death addresses each one directly: whole-pack allocation instead of per-unit
reaction, a merged candidate set across every addon user instead of one player's view,
and an actively defended mark map.

No MRT code is used. MRT ships with no license file, so it is all rights reserved by
default. The functionality described here is reimplemented from scratch against public
game APIs.

## 3. Core concept: icons belong to seats, not to mobs

The central idea, and the thing that makes assignments stable across raid nights.

A **seat** is one durable job in the raid: "sheep number one", "kill target number two".
Each of the eight raid icons is permanently bound to exactly one seat. A **mob rule**
never names an icon. It only declares an intent, such as "this mob should be sheeped".
The allocator hands a matching mob the lowest free seat of that intent, and the seat
supplies the icon.

The payoff is that a pinned player keeps their icon forever. Grimmtusk is pinned to sheep
seat one, so Grimmtusk is always Moon. A second mage inherits sheep seat two and is always
Triangle. Nobody renegotiates, and the assignment does not depend on which mob the raid
happens to be looking at.

### Default seat plan

| Icon | Index | Intent | Ordinal |
| --- | --- | --- | --- |
| Skull | 8 | KILL | 1 |
| Cross | 7 | KILL | 2 |
| Square | 6 | KILL | 3 |
| Star | 1 | KILL | 4 |
| Moon | 5 | SHEEP | 1 |
| Triangle | 4 | SHEEP | 2 |
| Diamond | 3 | BANISH | 1 |
| Circle | 2 | BANISH | 2 |

Sheep seat 1 ships pinned to `Grimmtusk`. Every binding is editable.

This plan spends all eight icons on kill, sheep and banish. TRAP, SAP, SHACKLE and the
other intents therefore have no seat by default. They remain selectable in the rule
editor, and a mob assigned to a seatless intent resolves through its `fallback` rather
than silently disappearing. Binding an icon to TRAP in the seat screen activates every
existing trap rule at once.

### Intents and capable classes

| Intent | Classes that can own a seat |
| --- | --- |
| KILL | any, no owner required |
| SHEEP | MAGE |
| TRAP | HUNTER |
| BANISH | WARLOCK |
| SEDUCE | WARLOCK |
| ENSLAVE | WARLOCK |
| FEAR | WARLOCK, PRIEST |
| SAP | ROGUE |
| SHACKLE | PRIEST |
| MINDCONTROL | PRIEST |
| HIBERNATE | DRUID |
| ROOTS | DRUID |
| REPENTANCE | PALADIN |
| IGNORE | none, never marked |

### Seat ownership resolution

For each intent, walk its seats in ordinal order:

1. If the seat has a `pin` and that player is in the raid, the pin owns the seat.
2. Otherwise the seat takes the next eligible class member not already holding a seat of
   that intent, ordered by player name ascending.
3. If no eligible member remains, the seat is **unowned**.

A player owns at most one seat per intent, but may own seats across different intents.
One warlock in the raid therefore holds banish seat 1 and fear seat 1 at the same time,
which is correct: those are different jobs on different mobs, not a double booking.

Name-ascending ordering is used because it is identical on every client without any
negotiation, which keeps backup markers in agreement.

A CC intent whose seats are all unowned is skipped entirely, and its mobs resolve through
`fallback`. Zero mages in the raid means sheep rules quietly become kill rules instead of
producing icons nobody will honor. KILL seats need no owner and are always available.

## 4. Architecture

```
MarkedForDeath/
    MarkedForDeath.toc
    Bindings.xml
    Core.lua              namespace, version, event frame, saved vars, slash router
    Helpers.lua           pure functions, no frames or events
    Data_Mobs.lua         compiled TBC raid NPC table
    Data_Auras.lua        buff and consumable spell id tables
    Seats.lua             seat plan, intent table, ownership resolution
    Rules.lua             rule store, per-instance activation, npcID index
    Allocator.lua         pure allocation function
    Candidates.lua        live hostile unit set
    Marker.lua            diff application, defense, combat lock, release
    Comms.lua             addon channel, election, sighting merge, rule sync
    RaidCheck.lua         buff and consumable audit logic
    UI_Config.lua         seat editor, rule editor, mob search
    UI_Assignments.lua    shared assignment panel
    UI_RaidCheck.lua      full grid and quick buff board
    Tests.lua             in-game test runner
```

Load order is the `.toc` order above: data and logic before UI, per the coding standards.

Namespace follows the standard rather than the `ns` shape seen in CutMaster. Every file
opens with `local MFD = _G.MarkedForDeath or {}` and closes with
`_G.MarkedForDeath = MFD`. No other globals except frames that must be named for
`UISpecialFrames`.

`Helpers.lua`, `Seats.lua`, `Rules.lua` and `Allocator.lua` call no WoW API. That is a
hard rule, not a preference: it is what makes the hard part testable outside the game and
what lets a backup marker provably agree with the authority.

## 5. Data model

```lua
-- Seat plan. Keyed by icon index 1..8. Every icon has at most one seat.
seatPlan = {
    [8] = { intent = "KILL",  ordinal = 1 },
    [5] = { intent = "SHEEP", ordinal = 1, pin = "Grimmtusk" },
}

-- Mob rule. Position in its instance list is its priority; index 1 is highest.
-- npcID is the match key. name is for display and as a fallback match.
{
    npcID    = 22890,
    name     = "Illidari Nightlord",
    intent   = "SHEEP",
    fallback = "KILL",      -- optional, used when intent has no owned seat
    maxCount = 3,           -- optional cap on simultaneous marks for this npcID
}

-- Candidate, one per observable hostile unit.
{
    guid    = "Creature-0-...",
    key     = "22890:1A2B3C",   -- compact wire identity, npcID:spawnUID
    npcID   = 22890,
    name    = "Illidari Nightlord",
    unit    = "nameplate3",     -- nil if only known from a peer sighting
    seenAt  = 12345.67,
    source  = "local",          -- or "peer"
}

-- Assignment, the allocator's output.
{
    key    = "22890:1A2B3C",
    icon   = 5,
    intent = "SHEEP",
    owner  = "Grimmtusk",       -- nil for KILL
}
```

## 6. Allocation

`Allocator.Compute(candidates, rules, seatPlan, roster, locked)` is pure. Same inputs
always produce the same output table, with no reliance on table iteration order.

1. Resolve seat ownership from `seatPlan` and `roster` (section 3).
2. Drop candidates with no matching rule, and candidates whose rule intent is `IGNORE`.
   Mobs without a rule are never marked. The addon does not guess.
3. Apply `locked` first. Locked assignments keep their icon and consume their seat, so a
   combat lock survives re-optimization.
4. Sort the remaining candidates by `(rule priority, key ascending)`. The key tiebreak is
   what removes sighting order from the result.
5. For each candidate in order, take the lowest free owned seat of its intent. If no owned
   seat is free, retry once with `fallback`. If that also fails, leave it unmarked.
   Respect `maxCount` per npcID.
6. Return the assignment list.

Explicitly tested edge cases: three copies of one mob, more ruled mobs than icons, a
pinned player who is offline, zero capable classes for an intent, a locked assignment that
would otherwise lose its seat, and two mobs whose rules tie on priority.

## 7. Marking runtime

**Candidate set.** Keyed by GUID. Local sources are `NAME_PLATE_UNIT_ADDED` /
`NAME_PLATE_UNIT_REMOVED`, `UNIT_TARGET`, `UPDATE_MOUSEOVER_UNIT`, and the combat log.
Entries survive nameplate removal for a 3 second grace period so a flickering nameplate
does not churn the pack. Peer sightings (section 8) are merged into the same set.

**Tick.** A 0.2 second accumulator on a single `OnUpdate`, never a raw per-frame handler.
Each tick computes the allocation, diffs it against live `GetRaidTargetIndex`, and applies
at most 4 `SetRaidTarget` calls so a large pull does not burst.

**Defense.** If an icon the addon placed is cleared or moved by anything else, it is
re-applied. Capped at 3 re-applications per GUID per 5 seconds, after which the addon
yields that GUID and prints the reason. An addon that will not stop fighting a human is
worse than one that concedes.

**Combat lock.** On `PLAYER_REGEN_DISABLED` the current assignment map is frozen to GUIDs
and passed to the allocator as `locked` from then on. Before combat the allocator may
re-optimize freely, so a high priority mob that walks into range late can still take Skull
off a lesser mob. After the pull nothing moves except by death.

**Release.** `UNIT_DIED` on a tracked GUID frees its seat immediately for the next mob of
that intent.

**Permission.** All placement is gated on `UnitIsGroupLeader` or `UnitIsGroupAssistant`
(or being solo or in an unled party). Losing assist mid-raid stops placement and prints
why rather than failing silently.

**Coverage guard.** On `PLAYER_ENTERING_WORLD` inside a raid instance, check
`nameplateShowEnemies` and the nameplate distance CVar. If either would prevent marking,
print a warning naming the exact `/mfd fixcvars` command. CVars are never changed without
the user asking.

## 8. Authority and coverage merging

**Election.** Every client broadcasts `HELLO` on load and on roster change. Authority
score is leader (1000) over assistant (500) over neither (0), ties broken by name
ascending. The winner broadcasts `ELECT` and then a `BEAT` heartbeat every 5 seconds.
Peers re-elect after 15 seconds of silence. Every wait has a timeout.

**Sighting merge, and the reason coverage improves.** The candidate set differs per
client, because nameplate visibility differs per client. Backups therefore do not
allocate independently, which would let them disagree with the authority. Instead each
backup reports mobs it can see that match a rule, batched at most once per 0.5 seconds,
new keys only. The authority merges every peer's sightings into its own candidate set,
allocates over the union, and publishes the result as `ASSIGN`.

Coverage becomes the union of every addon user's nameplates rather than one player's.
This is the direct fix for "marks never land".

**Backup placement.** A backup that can see a unit for a key the authority has published
but has not managed to apply within 1.5 seconds places the icon itself and broadcasts
`CLAIM`. This covers the case where the authority knows about a mob from a sighting but
has no unit token of its own to act on.

## 9. Comms protocol

Prefix `MFD`, registered via `C_ChatInfo.RegisterAddonMessagePrefix`, guarded and
`pcall`ed. Channel RAID, falling back to PARTY.

| Type | Direction | Payload |
| --- | --- | --- |
| `H` | all | addon version, canMark, score, rules version |
| `E` | winner | authority claim |
| `B` | authority | heartbeat sequence |
| `S` | backups | batched sightings, `key:npcID` pairs |
| `A` | authority | assignments, `key:icon:intent:owner` |
| `C` | backups | key applied by a backup |
| `RV` `RQ` `RD` | authority / peers | rules version, request, chunked data |
| `PC` | all | raid check self-report |

Wire identity is the compact `npcID:spawnUID` key rather than a full GUID, derived
identically on both sides, because full GUIDs waste most of a 240 byte message.

**Rate limiting is mandatory, not defensive.** The addon message channel is throttled
server side and that budget is shared with every other addon the player runs. All sends
go through one queue capped at 8 messages per second with priority ordering: `B` and `A`
first, then `S`, then `PC`, then `RD` last. Rule transfers are chunked at 240 bytes and
carry a transfer timeout with a visible failure message.

Rule sync is gated on a version counter plus a content hash, so a transfer only happens
when rules actually changed.

## 10. Mob database and search

**Bundled.** `Data_Mobs.lua` holds `[npcID] = { name, instanceKey }` for the nine TBC
raids: Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, Tempest Keep,
Hyjal Summit, Black Temple, Zul'Aman, Sunwell Plateau. Roughly 500 to 700 entries, well
under 100KB. Compiled at build time from a public TBC creature dataset cross-checked
against per-instance NPC listings.

This is the single highest external-data risk in the project, which is why it is built
last and why the learning layer exists.

**Learned.** Every observed mob is recorded as `[npcID] = { name, zone, seenAt }` in
saved variables and appears in search alongside bundled entries, rendered in amber (the
standards' color for external or derived values). Anything the dataset misses becomes
searchable the first time the raid walks past it.

**Matching** is npcID first, parsed from the GUID. Name matching is the fallback only,
for learned entries lacking a clean ID. Name-first matching is what makes MRT fragile
across locales and renamed spawns.

**Search UI.** Incremental filter as you type, an instance dropdown, and a "seen in this
zone" toggle that collapses the list to what is physically nearby. Rows come from a frame
pool.

**The primary workflow is not search.** A keybind adds whatever you are targeting or
mousing over as a rule, opening the editor pre-filled with the exact npcID and name.
Search exists for planning at a desk. The keybind is for planning in the instance, and it
is the real answer to names being hard to find.

**Rule editing.** Per instance, an ordered list. Priority is list position with up and
down arrows and automatic renumbering, because hand-editing rank integers is miserable.
Each row sets intent, optional fallback, optional max count.

**Sharing.** A hand-rolled compact serializer plus base64, no external library. The repo
does vendor libraries elsewhere (CutMaster ships LibStub and LibDBIcon), so this is a
preference rather than a constraint: rule sets are small enough that compression is not
worth the dependency. The same payload rides the comms channel chunked.

Rules ship **empty**. Only the seat plan is preconfigured. The addon never guesses a
guild's kill order, because a confidently wrong mark is worse than no mark.

## 11. Assignment panel and announcements

**Shared panel** (`UI_Assignments.lua`). A small window listing the current pack's icon,
intent and owner, driven by the authority's `A` messages so every addon user sees the same
thing. Frame pooled rows.

**Chat announcement.** On combat lock, or on demand, the authority posts one compact line
to raid chat covering the pack, for the benefit of people not running the addon. Throttled
to at most one announcement per 5 seconds, authority only.

Per-player on-screen callouts and click-to-target buttons were considered and declined by
the user.

## 12. Raid check

**Two data paths.** A local `UnitAura` sweep covers players without the addon. Every
client running the addon **self-reports its own state authoritatively** over `PC`. Both
are needed: temporary weapon enchants have no cross-unit API on 2.5.6, and durability and
spec exist only on the owning client. Self-report also closes out-of-range aura gaps. The
grid shows which path each cell came from.

**Columns.** Food, Flask, Battle Elixir, Guardian Elixir, Weapon Enchant, Arcane
Intellect, Mark of the Wild, Fortitude, Shadow Protection, Blessings held, Durability,
Spec, Addon Version. Rows grouped by raid group, frame pooled.

**Colors** follow the repo standard: green good, red missing, amber derived (scanned
rather than self-reported, so its confidence is visibly lower), grey unknown.

**Blessings are shown, not judged.** The grid lists which blessings each player actually
holds rather than asserting which they should have, because that call depends on the
night's composition and the raid leader is the one making it.

**Roster aware, same principle as seats.** A buff nobody present can cast is an absence,
not a failure. With no mage in the raid, Arcane Intellect is not reported missing on 24
people. Flagging unfixable gaps trains the reader to ignore the grid.

**Three surfaces over one data layer:**

1. **Full grid.** Automatic on `READY_CHECK`, plus manual refresh and `/mfd check`. All
   columns.
2. **Quick buff board.** Keybind or `/mfd buffs`. Buff columns only, so it needs no comms
   at all and works in a pug where nobody else has the addon. Defaults to missing-only,
   grouped by fix, with a toggle for the full roster. If everyone is buffed it says so in
   one line.
3. **Chat callout.** Click any red cell to whisper that player a templated line, or use
   the callout button to post a compact raid-chat summary grouped by fix
   ("No flask: Dave, Sue"), length capped, chunked across at most a few lines, throttled.

**Update policy.** While either window is open, `UNIT_AURA` is registered for the raid and
individual cells repaint as buffs land, so the board can be watched going green during a
buff phase. While both are closed, updates happen only on ready check, manual refresh, and
a 60 second self-report heartbeat. No aura processing for a window nobody is looking at.

Self-reports fire on change (`UNIT_INVENTORY_CHANGED`, `UPDATE_INVENTORY_DURABILITY`) but
are debounced 1 to 2 seconds and coalesced through the send queue, because 25 clients
broadcasting simultaneously during a mass rebuff would drop messages, including rule sync.

Bag stock auditing was considered and declined by the user.

## 13. Saved variables

`MarkedForDeathDB`, account wide:

```lua
{
    schemaVersion = 1,
    seatPlan      = {},   -- [icon] = { intent, ordinal, pin }
    rules         = {},   -- [instanceKey] = ordered list of rules
    rulesVersion  = { counter = 0, hash = "", owner = "" },
    learnedMobs   = {},   -- [npcID] = { name, zone, seenAt }
    settings      = {},
    lastTestRun   = {},
}
```

`MarkedForDeathCharDB`, per character: window positions and open/closed UI state.

Every field is defaulted on `ADDON_LOADED` through an `ApplyDefaults` walk. Schema changes
migrate in place, keep reading the previous shape for one version, and never delete user
data. Timestamps are `time()` integers.

## 14. Commands and keybinds

Every command appears in `/mfd help` with a one line description.

| Command | Effect |
| --- | --- |
| `/mfd help` | list commands |
| `/mfd config` | seat plan and settings |
| `/mfd rules` | rule editor and mob search |
| `/mfd add` | add current target or mouseover as a rule |
| `/mfd mark` | force a full re-mark of the visible pack |
| `/mfd clear` | clear all icons the addon placed |
| `/mfd buffs` | quick buff board |
| `/mfd check` | full raid check |
| `/mfd status` | authority, peers, rules version, coverage diagnosis |
| `/mfd fixcvars` | set the nameplate CVars needed for marking |
| `/mfd export` / `/mfd import` | rule set string |
| `/mfd selftest` | run the test suite in game |

`Bindings.xml`: re-mark pack, add target as rule, toggle buff board, toggle assignment
panel.

## 15. Error handling

- Optional dependencies checked for both global existence and function type before call.
- `pcall` around version-variant APIs, specifically the `UnitAura` return signature and
  `C_ChatInfo.SendAddonMessage`, both of which differ across the flavors this repo targets.
- Every wait is a state machine with a timeout and a visible failure message: rule
  transfer, election, self-report request.
- Anything that can silently do nothing prints why: no assist, nameplates disabled, no
  rules for this instance, no seat owner for an intent, all icons consumed.
- Errors also go to `UIErrorsFrame` per the standards.

## 16. Testing

`Tests.lua` follows the existing CutMaster pattern: `T.Case` registration, `T.Eq`
assertions, results written to saved variables so failures survive a `/reload` and can be
read off disk rather than retyped out of the chat frame.

Because `Helpers`, `Seats`, `Rules` and `Allocator` touch no WoW API, the same cases run
outside the game. Lua 5.1 is installed on the dev machine as part of phase 1, and
`scripts/run-tests.ps1` loads those four files with `loadfile(path)(addonName)` and runs
the suite headless. This gives a fast
loop for the allocation logic, which is where the user's duplicate and priority bugs live.
The in-game `/mfd selftest` ships regardless so correctness is checkable on the live
client.

In-game verification per the repo rule: deploy, `/reload`, run the commands, check
BugSack, and state explicitly in the PR whether in-game testing actually happened.

Note for deployment: `scripts/deploy.ps1` defaults `-WowRoot` to `D:\Program Files (x86)`
but this client is on `C:\`, so deploys need the override.

## 17. Build order

1. `Core`, `Helpers`, `Seats`, `Rules`, `Allocator`, `Tests`. Pure, fully unit tested, no
   game needed.
2. `Candidates`, `Marker`. Marking works single player.
3. `Comms`. Election, sighting merge, rule sync.
4. `UI_Config`. Seat editor, rule editor, search, add-target keybind.
5. `UI_Assignments` and announcements.
6. `Data_Auras`, `RaidCheck`, `UI_RaidCheck`. Grid, buff board, callouts.
7. `Data_Mobs`. Compiled last, because it carries the external-data risk and nothing else
   should block on it.

## 18. Known risks

- **Mob dataset accuracy.** Mitigated by the learning layer and by building it last.
- **Addon message throughput** with 25 users. Mitigated by the priority queue, sighting
  batching, new-keys-only reporting, and rule sync version gating. Needs real raid
  measurement, not just theory.
- **`UnitAura` signature variance** across client versions. Mitigated by `pcall` and a
  name-matching fallback.
- **Marking requires leader or assist.** Cannot be worked around, only reported clearly.
- **Nameplate distance cap** still bounds the union of coverage. More users widens it but
  does not remove it.
- **Combined scope.** Marking and raid check are independent subsystems in one addon at
  the user's explicit direction. The file layout keeps them separable if that is ever
  revisited.
