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

## Shared code: ICLibs

Code more than one addon needs lives in the library addon
`AddonProjects/anniversary/ICLibs` as LibStub libraries. Three of ours, plus the
third-party ones (LibStub, CallbackHandler, LibDataBroker, LibDBIcon) loaded once there
so no addon bundles a copy:

- `LibICCore-1.0` (MINOR 1) is the plumbing. One `Core:Attach(ns, opts)` in `Core.lua`
  installs Print, the saved-variable bootstrap and its load check, Util, Log, the test
  harness, the slash dispatcher and reset; `Core:MinimapButton`, `Core:Probe` and
  `Core:Bindings` do the rest. Every addon with saved variables attaches, and `lint.py`
  fails one that does not.
- `LibICTradeSkill-1.0` (MINOR 2) reads a profession window into a book.
- `LibICUI-1.0` (MINOR 6) is the window, tab, list and widget toolkit in the guild
  palette, and carries the brand itself. Four addons depend on it.

Addons list `## Dependencies: ICLibs` in their TOC and fetch a library with
`LibStub("LibICUI-1.0")`. Bump the library's MINOR when its API changes, and record the
new number in `Docs/ICLibs.md`; `lint.py` fails when the two disagree.
`scripts/package.ps1` bundles required addons into the zip and `scripts/deploy.ps1` links
them; do not copy library files into an addon's own folder.

## Starting a new addon

`scripts/new-addon.ps1 -Name <Name> -Slash <slash> -Title "<Title>" [-Minimal]` copies
ICTemplate, rewrites its three tokens, adds the three registration rows and lints the
result. It defaults `## Category:` to the guild heading; pass `-Category` only for an addon
that genuinely belongs elsewhere in the AddOns list. `Docs/ICTemplate.md` has the by-hand
version and says what to throw away.

## While editing

- New file: add it to the `.toc` in load order (data and logic before UI).
- `Bindings.xml` ships but is never listed in the `.toc`: the client loads it by filename,
  and listing it loads every binding twice. The linter fails on it.
- New wait on the client: give it a state, a timeout, and a cancel path. Copy the pattern
  in `MalexisAuctionWatcher/Scanning.lua`.
- New optional dependency call: guard the global and the function, `pcall` internals.
- New command: a row in `HELP` and a function in `COMMANDS` in `Core.lua`, and a row in
  `Docs/<Addon>.md`. The dispatcher's built-ins are already there.
- New saved field: default it in the `Defaults` table in `Core.lua`; `ApplyDefaults` fills
  it in on load. A shape change is a `Migrations` step keyed by the schema it upgrades
  from, with `SCHEMA` bumped.
- Editing a `.toc` needs a client restart. `/reload` does not re-read it, and a client that has been running across `.toc` edits can stop restoring one addon's account-wide saved variables while still restoring the per-character ones. The fingerprint is `/x log` saying `SAVED VARIABLES WERE EMPTY` with the per-character table intact. Restart the client before reading a line of addon code.
- New or edited window: follow "Window layout" in `CODING_STANDARDS.md`. Lists get a header
  row outside the scroll child, fixed single-line rows, a toolbar above the headers, no
  controls over the scroll area, and the page must fit (TradeMaster pages are 700x478) or
  scroll. Build them with `LibStub("LibICUI-1.0")` through the addon's wrapper: the same
  library supplies the window, the tabs and every button in the guild palette, so never
  hand-roll a control or paint one with literal colours.
- After editing any UI file, run the `wow-ui-reviewer` agent on it before packaging.
- Calling into the client: read `client-api.md` next to this file first. It is the list of
  contracts that have already shipped broken here, symptom first, and it is shorter than
  the time one of them costs. Add to it whenever the game teaches you something new.
- A function written inside a constructor cannot see the local being assigned:
  `local t = UI.Table(page, { onClick = function() t:... end })` reads a nil global,
  because `t` only exists after the assignment finishes. Declare it on its own line
  first, or use the table the library hands the callback as its last argument.
- Do not use the Bash heredoc trick for multi-line Lua edits from Claude Code on this
  machine; it fails on some content. Write a small Python script to a scratch file with the
  Write tool and run it, or use the Edit tool.

## Verifying

There is no Lua interpreter on the machine, so nothing here runs outside the game. Three
things stand in for that, in order:

1. `python scripts/lint.py` before packaging. It parses every file, and catches the
   mistakes that have shipped: a local referenced inside its own assignment, a texture path
   that does not resolve, a `.toc` out of step with the files on disk, a version that moved
   in one of its three places but not the others, `Bindings.xml` listed in a `.toc` (the
   client loads it by filename, so listing it loads the bindings twice), and a quoted
   string that runs past the end of its line -- `luaparser` accepts that one and the client
   refuses to load the file, so it is checked separately. Fix everything it prints.
2. The addon's own cases, in game. Five addons carry a `Tests.lua`, loaded last:

   | Command | Cases |
   | --- | --- |
   | `/tm test` (TradeMaster) | 128 |
   | `/cm test` (CutMaster) | 135 |
   | `/gr test` (GuildRecruitment) | 50 |
   | `/ictpl test` (ICTemplate) | 27 |
   | `/maw test` (MalexisAuctionWatcher) | 9 |

   Any decision worth arguing about belongs in a pure function with a case here, and a case
   that asserts an ordering must have that ordering worked out rather than assumed.
3. The `wow-ui-reviewer` agent on every UI file touched.

Then say plainly in the summary that nothing was run in the client, and give the player the
in-game steps: `/reload`, the commands to run, and to check BugSack. Prefer changes that
fail loudly in chat over ones that fail silently.

## Releasing

1. Bump `## Version:` in the `.toc` and the load message in `Core.lua` to the same value.
2. Update the version table in `AddonProjects/<flavor>/README.md`.
3. `scripts/package.ps1 -Flavor <flavor> -Addon <Addon>` writes `dist/<Addon>-<ver>-<flavor>.zip`.
4. Send the zip to the user with SendUserFile. `dist/` is git-ignored.
5. Commit on the feature branch with an imperative subject and a body listing
   player-visible changes, then push the branch. `main` only accepts pull requests:
   when the user wants it merged, `gh pr create --fill`, then `gh pr merge --merge`
   once the in-game checklist in the PR template is done. Never squash: each commit
   here is written to stand on its own so a single change can be found and reverted
   on its own, and a squash throws that away.
