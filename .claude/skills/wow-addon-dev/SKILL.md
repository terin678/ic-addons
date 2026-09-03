---
name: wow-addon-dev
description: Work on a World of Warcraft addon in this repo - edit Lua under AddonProjects/<flavor>/<Addon>, deploy it to the game client, bump versions, package a zip, and update the addon's guide. Use for any request about a WoW addon, Lua UI frames, TOC files, saved variables, auction house or item APIs, or Auctionator/TSM integration.
---

# WoW addon development in ic-addons

## Before editing

1. Read `CODING_STANDARDS.md` and the addon's guide in `Docs/<Addon>.md`.
2. Find the addon at `AddonProjects/<flavor>/<Addon>/`. Flavors: `era`, `anniversary`,
   `retail`. Interface versions are in `Docs/client-reference.md`.
3. Check whether the game folder already links to the repo:
   `Get-Item "<WowRoot>\<flavorFolder>\Interface\AddOns\<Addon>" -Force` shows a
   `ReparsePoint` attribute for a junction. If not linked, run
   `scripts/deploy.ps1 -Flavor <flavor> -Addon <Addon>`.

## TradeMaster and CutMaster

TradeMaster (`AddonProjects/anniversary/TradeMaster`) is a fork of a collaborator's
CutMaster (`AddonProjects/anniversary/CutMaster`) generalised to any profession. Never
edit CutMaster; it belongs to the collaborator. To port an upstream CutMaster change:
`git log --oneline -- AddonProjects/anniversary/CutMaster` to find it, `git show <sha>`
to read the diff, then apply the same change by hand to the TradeMaster module of the
same name (Stats.lua maps to Annotators.lua). Profession-specific strings and rules go
into `Professions.lua` profiles, not into the modules.

## While editing

- New file: add it to the `.toc` in load order (data and logic before UI).
- New wait on the client: give it a state, a timeout, and a cancel path. Copy the pattern
  in `MalexisAuctionWatcher/Scanning.lua`.
- New optional dependency call: guard the global and the function, `pcall` internals.
- New command: add it to the `help` output and to `Docs/<Addon>.md`.
- New saved field: default it in the `InitializeDB` path and migrate old data in place.
- Do not use the Bash heredoc trick for multi-line Lua edits from Claude Code on this
  machine; it fails on some content. Write a small Python script to a scratch file with the
  Write tool and run it, or use the Edit tool.

## Verifying

There is no Lua on the machine and no tests. Say so in the summary and give the player the
in-game steps: `/reload`, the commands to run, and to check BugSack. Prefer changes that
fail loudly in chat over ones that fail silently.

## Releasing

1. Bump `## Version:` in the `.toc` and the load message in `Core.lua` to the same value.
2. Update the version table in `AddonProjects/<flavor>/README.md`.
3. `scripts/package.ps1 -Flavor <flavor> -Addon <Addon>` writes `dist/<Addon>-<ver>-<flavor>.zip`.
4. Send the zip to the user with SendUserFile. `dist/` is git-ignored.
5. Commit on the feature branch with an imperative subject and a body listing
   player-visible changes, then push the branch. `main` only accepts pull requests:
   when the user wants it merged, `gh pr create --fill` and squash-merge after the
   in-game checklist in the PR template is done.
