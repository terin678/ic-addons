# ic-addons

Guild World of Warcraft addons. Read `CODING_STANDARDS.md` before changing any Lua.

## Where things are

- Addons: `AddonProjects/<flavor>/<AddonName>/`. Flavors: `era`, `anniversary`, `retail`.
  The addon folder is exactly what ships.
- User docs: `Docs/<AddonName>.md`. Update it whenever a command or tab changes.
- Deploy and package: `scripts/deploy.ps1`, `scripts/package.ps1` (PowerShell 5.1).
- Skill for addon work: `.claude/skills/wow-addon-dev/SKILL.md`.

## Git workflow

- Never commit on `main`; it is protected and only accepts pull requests. Check
  `git branch --show-current` before committing. If on `main`, create `feature/<topic>`
  or `fix/<topic>` first.
- Commit on the feature branch and push it. Open a PR with `gh pr create` when the user
  asks for a merge; the template in `.github/` is the review checklist. Squash-merge.

## Rules that matter most

- Interface versions: anniversary is 20506 (TBC). Verify against an installed addon on the
  client before changing; do not guess.
- Client API calls that wait on the game must have timeouts and a cancel path. See the
  scan state machine in `MalexisAuctionWatcher/Scanning.lua` for the pattern.
- Optional dependencies (Auctionator, TSM) are always guarded and never required.
- Bump the version in the `.toc` and `Core.lua` load message together.
- Never commit `WTF/`, saved variables, or zips.

## Verifying changes

Verification is in game: deploy, `/reload`, run the commands, check BugSack. State plainly
in the summary that in-game checks were not run when that is the case.

Some addons also have a headless test suite. LuaJIT 2.1 (Lua 5.1 semantics, matching the
client) is installed on the maintainer's machine, and `scripts/run-tests.ps1 -Flavor
<flavor> -Addon <Addon>` runs an addon's pure modules outside the game. A shell opened
before the install will not have `luajit` on PATH; the script falls back to the
`LOCALAPPDATA` install path.

Only modules that call no WoW API at file scope can be tested this way. Caching a global
into a local at file scope is fine; calling one is not. Anything that creates a frame or
reads client state does it in an init function registered from the addon's `Core.lua`.
Headless tests never replace in-game verification, they just catch logic errors first.
