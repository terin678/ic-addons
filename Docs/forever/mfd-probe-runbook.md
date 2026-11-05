# MFD probe: what to do in game

MFDProbe asks the Forever client each thing MarkedForDeath needs (raid marks, mob and
group reads, the combat log, auras, inspect, chat, addon messages, combat logging,
durability, secure buttons, encounter and ready check events, the damage meter) and
records whether it worked, was hidden as a secret value, or was refused, out of combat and
in combat. It is a throwaway addon: once its answers are in
[client-reference.md](../client-reference.md) it goes.

It is deployed to `_forever_\Interface\AddOns\MFDProbe`, with `ICKit` beside it, as copies.

## Heads up for the group

Runs set raid marks for a second and put them back (star on your target, circle on your
mouseover, diamond and triangle on two hostile nameplates, square on yourself), and the
`now` run and one run in each pull send a test line to PARTY, RAID, INSTANCE_CHAT,
RAID_WARNING and SAY. Tell the group first. `/mfdp chat off` leaves chat out, but the chat
answers are part of what we need. A popup saying the addon was blocked from an action is
expected and is itself a result; close it.

## Steps

1. **Restart the client.** A new `.toc` is only read at start. Make sure `MFD Probe` and
   `ICKit` are ticked on the AddOns screen. At login it says `MFDProbe: v0.1.0 loaded`.
2. **Solo, out of combat.** Target a hostile mob, keep the mouse over another one, and
   type `/mfdp now`. Wait 6 seconds for its summary.
3. **In a dungeon group, out of combat, inside the instance.** Same again: target a mob in
   a pack, hover another, `/mfdp now`. Best done as party leader, then once more after
   passing lead to someone else (or before you take it).
4. **Pull a pack.** Just before the pull, `/mfdp arm`. It runs on its own at 0, 3 and 8
   seconds into combat and 2 seconds after. During the fight, also type `/mfdp now` once
   (this is the keypress case, which some chat channels need). Kill the pack; it says
   `pull captured` about 10 seconds after combat ends.
5. **A boss, if you get to one.** `/mfdp arm` before the pull, the same as step 4.
6. **A ready check (optional).** As leader, `/mfdp readycheck`, and have the group answer.
7. `/mfdp report` prints what each check came to, out of combat and in combat. Then
   **`/reload`** (or log out) so the results are written to disk.

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
| `/mfdp report [text]` | each check out of and in combat; text keeps ids containing it |
| `/mfdp runs` | every run kept, with where it was taken |
| `/mfdp chat on \| off` | whether runs send chat lines |
| `/mfdp clear` | forget every run |
| `/mfdp test` | the built-in cases (pure; sends nothing) |

Nothing is registered while idle: events are only listened to inside a run's window or
while armed.
