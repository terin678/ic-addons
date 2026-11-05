# MFD probe: what to do in game

MFDProbe asks the Forever client each thing MarkedForDeath needs (raid marks, mob and
group reads, the combat log, auras, inspect, chat, addon messages, combat logging,
durability, secure marking buttons, encounter and ready check events, the damage meter) and
records whether it worked, was hidden as a secret value, or was refused, out of combat and
in combat. It is a throwaway addon: once its answers are in
[client-reference.md](../client-reference.md) it goes.

It is deployed to `_forever_\Interface\AddOns\MFDProbe`, with `ICKit` beside it, as copies.

## Heads up for the group

Typed runs (`/mfdp now`) try to set a raid mark from addon code on your target and on
yourself. The client is expected to refuse this, and each refusal opens a popup saying the
addon was blocked from an action. That popup is a result: close it. The marking buttons
(step 5) do set real marks on mobs (skull, cross, square and down by name, skull and cross
by mouseover and first nameplate, the moon on you, square or diamond on the mouseover from
`Snippet: mouseover`, the triangle on you from `Click chain`) and `Clear all` removes every
mark. Typed runs and one run per pull also flash a raid warning reading `MFDProbe notice
<n>` on your own screen only; it sends nothing.
`/mfdp now` and one run in each pull send a test line to PARTY, RAID, INSTANCE_CHAT,
RAID_WARNING and SAY, and ask the group's addons for durability. Tell the group first.
`/mfdp chat off` leaves the chat lines out, but those answers are part of what we need.

## Steps

1. **Restart the client.** A new `.toc` is only read at start. Make sure `MFD Probe` and
   `ICKit` are ticked on the AddOns screen. At login it says `MFDProbe: v0.2.0 loaded`.
2. **Open world, solo, out of combat.** Target a hostile mob, keep the mouse over another
   one, and type `/mfdp now`. Wait 6 seconds for its summary.
3. **Open world, in combat.** `/mfdp arm`, pull that mob, and type `/mfdp now` once while
   fighting. It says `pull captured` about 10 seconds after combat ends.
4. **In a dungeon group, inside the instance, out of combat.** Target a mob in a pack,
   hover another, `/mfdp now`. Once as party leader, then once more not as leader.
5. **The marking buttons, inside the instance, out of combat.** Type `/mfdp buttons`. A
   small panel appears near the top of the screen. If the instance hides mob names, it
   says so: then type the names you see on the nameplates instead, for example
   `/mfdp buttons Defias Pillager, Defias Evoker`. With a pack in view and the mouse over
   one of its mobs, click each button once, waiting a second between clicks:
   `Mark by name`, `Conditionals`, `Long macro`, `Snippet: mouseover` (mouse over a mob),
   `Click chain`, then `Clear all`. Each click says `click ... recorded`. The marking
   buttons work in the open world too, so this step and the next can be done there first.
6. **Pull that pack with the buttons up.** `/mfdp arm` just before the pull. In combat,
   click `Mark by name`, `Conditionals`, `Long macro`, `Snippet: mouseover` twice (mouse
   over a different mob each time) and `Click chain`, and type `/mfdp now` once. After the
   fight, click `Clear all`, then `/mfdp buttons hide`.
7. **A boss, if you get to one.** `/mfdp arm` before the pull, and type `/mfdp now` once
   during the fight. Watch the middle of the screen: say whether the `MFDProbe notice`
   raid warning showed during the boss (it is the only answer the file cannot hold).
   Arming leaves combat logging on until the pull is captured, so the log file can be
   checked afterwards.
8. **A raid instance, if you are in one** (Onyxia's Lair, or any raid map). Out of combat
   and away from a boss: `/mfdp now`, then `/mfdp arm` before a trash pull. This answers
   whether chat is locked for the whole raid map or only during an encounter.
9. **A ready check (optional).** As leader, `/mfdp readycheck`, and have the group answer.
10. `/mfdp report` prints what each check came to, out of combat and in combat, and
    `/mfdp capture` the instance, encounter, npc and aura ids read. Then **`/reload`** (or
    log out) so the results are written to disk.

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
| `/mfdp buttons [name, name]` | out of combat: the four marking buttons, for these mobs or the ones in view |
| `/mfdp buttons hide` | out of combat: put them away |
| `/mfdp capture` | the instance, encounter, npc and aura ids read so far |
| `/mfdp report [text]` | each check out of and in combat; text keeps ids containing it |
| `/mfdp runs` | every run kept, with where it was taken |
| `/mfdp chat on \| off` | whether runs send chat lines |
| `/mfdp clear` | forget every run |
| `/mfdp test` | the built-in cases (pure; sends nothing) |

Nothing is registered while idle: events are only listened to inside a run's window or
while armed.
