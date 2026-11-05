# Marked For Death (WoW Forever)

Marked For Death keeps a raid's crowd control and kill order the same every night. The
eight raid icons belong to seats (Kill 1 to 4, Sheep 1 and 2, Banish 1 and 2), a mob rule
names a job and never an icon, and the plan reaches the mobs through your own keypress.

This is the guide for the WoW Forever addon (interface 16001) in
`AddonProjects/forever/MarkedForDeath`. The Anniversary addon has its own guide,
[Docs/MarkedForDeath.md](../MarkedForDeath.md). The design is
`Docs/forever/specs/2026-11-05-mfd-forever-design.md`.

**Status: 0.1.0 is the scaffold.** It loads, keeps its saved settings and answers `/mfd`.
Marking, rules, the raid check and death calls arrive with the feature lanes; this guide is
written in full once they have landed (lane W).

## Installing

Install `ICKit` alongside it: Marked For Death lists it under `## Dependencies` and does not
load without it. Restart the client after installing or updating, since a `.toc` change is
not read on `/reload`.

## Commands

| Command | What it does |
| --- | --- |
| `/mfd`, `/mfd help` | Lists every command |
| `/mfd version` | The version running |
| `/mfd debug` | Turns debug lines on or off |
| `/mfd selftest` (or `/mfd test`) | Runs the built-in checks |

Each feature adds its own commands to `/mfd help` as it lands.

## The seat plan

A new install starts with this plan, with no players pinned:

| Icon | Seat |
| --- | --- |
| Skull | Kill 1 |
| Cross | Kill 2 |
| Square | Kill 3 |
| Circle | Kill 4 |
| Moon | Sheep 1 |
| Star | Sheep 2 |
| Triangle | Banish 1 |
| Diamond | Banish 2 |

## Marking

*To come (lanes A and B).*

## Rules

*To come (lanes A and G).*

## Raid check

*To come (lane C).*

## Death calls and chat

*To come (lane D).*

## Capture mode

*To come (lane E).*

## Saved settings

Account-wide settings are in `MarkedForDeathDB`, per-character ones (window places, the bar)
in `MarkedForDeathCharDB`. If the addon says at login that the account settings did not
load, restart the client before you log out or reload, or the empty settings are written
over the file.
