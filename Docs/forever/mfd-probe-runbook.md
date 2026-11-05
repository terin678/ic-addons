# MFD probe: what to do in game

MFDProbe asks the Forever client each thing MarkedForDeath needs (raid marks, mob and
group reads, the combat log, auras, inspect, chat, addon messages, combat logging,
durability, secure marking buttons, encounter and ready check events, the damage meter) and
records whether it worked, was hidden as a secret value, or was refused, out of combat and
in combat. It is a throwaway addon: once its answers are in
[client-reference.md](../client-reference.md) it goes.

It is deployed to `_forever_\Interface\AddOns\MFDProbe`, with `ICKit` beside it, as copies.

## Heads up for the group

The marking buttons set real marks (skull, cross, square, moon on the target; marks on
the mouseover; star and circle on you) until `Clear all` is pressed. `/mfdp now` and one
run in each pull send a test line to PARTY, RAID, INSTANCE_CHAT, RAID_WARNING and SAY, ask
the group's addons for durability, and flash a raid warning reading `MFDProbe notice <n>`
on your own screen only. Tell the group first. The probe no longer tries the calls the
client forbids, so the "blocked from an action" popup should not appear; if it does, it
is a result, so close it and mention it.

## Open world, right now (a /reload is enough after 0.2.0 was loaded once)

1. `/reload`. Out of combat, target a hostile mob and type `/mfdp buttons`. The second
   line says how this client spells `/tm`, `/targetexact` and `/click`: note it.
2. `/mfdp keys`. From now on CTRL-1 to CTRL-0 press the ten buttons in panel order:
   1 Literal /tm 8, 2 Global tm 7, 3 Secure set 6, 4 Literal exact 5, 5 Mark by name,
   6 Conditionals, 7 Snippet: mouseover, 8 Long macro, 9 Click chain, 0 Clear all.
3. **The control, out of combat**, with the mob still targeted, one at a time, watching
   the mob's mark, and CTRL-0 (Clear all) after each: CTRL-1, CTRL-2, CTRL-3, CTRL-4. Then
   CTRL-5 (Mark by name; say how many mobs got a mark), CTRL-0.
4. **Pointer on a mob, out of combat:** rest the mouse pointer on a mob's body (not the
   panel) and press CTRL-6, then CTRL-7 twice (square, then diamond on that mob), CTRL-0.
   Then CTRL-8 (circle on you), CTRL-0, CTRL-9 (star on you), CTRL-0.
5. **In combat:** `/mfdp arm`, target a mob and pull it. While fighting, type `/mfdp now`
   once, then press CTRL-1, CTRL-2, CTRL-3 with the mob targeted, CTRL-6 and CTRL-7 with
   the pointer on a mob, CTRL-8, CTRL-9. After the fight: CTRL-0.
6. `/mfdp keys off`, `/mfdp buttons hide`, `/mfdp report button`, then `/reload` so it is
   written to disk. Say which buttons visibly put a mark on something.

## Steps for a dungeon or raid

1. **Restart the client** if MFD Probe has never been loaded since 0.2.0. Make sure
   `MFD Probe` and `ICKit` are ticked on the AddOns screen. At login it says
   `MFDProbe: v0.2.0 loaded`.
2. **Inside the instance, out of combat.** Target a mob in a pack, hover another,
   `/mfdp now`. Once as party leader, then once more not as leader.
3. **The buttons inside, out of combat.** Target a mob, `/mfdp buttons` (if the instance
   hides names, type the ones on the nameplates: `/mfdp buttons Defias Pillager, Defias
   Evoker`), `/mfdp keys`, then steps 3 and 4 of the open-world block.
4. **Pull that pack.** `/mfdp arm` just before. In combat, step 5 of the open-world block.
   After the fight, CTRL-0.
5. **A boss, if you get to one.** `/mfdp arm` before the pull, and `/mfdp now` once during
   the fight. Watch the middle of the screen and say whether the `MFDProbe notice` raid
   warning showed during the boss (it is the one answer the file cannot hold). Arming
   leaves combat logging on until the pull is captured, so the log file can be checked.
6. **A raid instance, if you are in one** (Onyxia's Lair, or any raid map). Out of combat
   and away from a boss: `/mfdp now`, then `/mfdp arm` before a trash pull. This answers
   whether chat is locked for the whole raid map or only during an encounter.
7. **A ready check (optional).** As leader, `/mfdp readycheck`, and have the group answer.
8. `/mfdp keys off`, `/mfdp report`, `/mfdp capture`, then **`/reload`** (or log out) so
   the results are written to disk.

If anything throws a Lua error, BugSack has it; mention it.

## Where the results land

`C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\84083208#1\SavedVariables\MFDProbe.lua`

It holds the last 40 runs: each with where it was taken (combat, instance type and name,
group type and size, leader or assist, which addon restrictions were on), a row per check
(`ok`, `secret`, `none`, `refused`, `error`, `blocked`, `absent`) and the events heard with
a few payloads.

## Commands

| Command | What it does |
| --- | --- |
| `/mfdp now` | every check now, including chat, inspect, logging, a secure button |
| `/mfdp arm` | capture the next pull, then disarm (gives up after 15 minutes) |
| `/mfdp disarm` | stop waiting for a pull |
| `/mfdp listen [seconds]` | hear events for a while, 60 by default |
| `/mfdp readycheck` | start a ready check and listen 45 seconds |
| `/mfdp buttons [name, name]` | out of combat: the ten marking buttons, for these mobs or the ones in view |
| `/mfdp buttons hide` | out of combat: put them away |
| `/mfdp keys [off]` | out of combat: CTRL-1 to CTRL-0 press the ten buttons |
| `/mfdp capture` | the instance, encounter, npc and aura ids read so far |
| `/mfdp report [text]` | each check out of and in combat; text keeps ids containing it |
| `/mfdp runs` | every run kept, with where it was taken |
| `/mfdp chat on \| off` | whether runs send chat lines |
| `/mfdp clear` | forget every run |
| `/mfdp test` | the built-in cases (pure; sends nothing) |

Nothing is registered while idle: events are only listened to inside a run's window or
while armed.
