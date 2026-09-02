# ic-addons

Guild World of Warcraft addons. Read `CODING_STANDARDS.md` before changing any Lua.

## Where things are

- Addons: `AddonProjects/<flavor>/<AddonName>/`. Flavors: `era`, `anniversary`, `retail`.
  The addon folder is exactly what ships.
- User docs: `Docs/<AddonName>.md`. Update it whenever a command or tab changes.
- Deploy and package: `scripts/deploy.ps1`, `scripts/package.ps1` (PowerShell 5.1).
- Skill for addon work: `.claude/skills/wow-addon-dev/SKILL.md`.

## Rules that matter most

- Interface versions: anniversary is 20506 (TBC). Verify against an installed addon on the
  client before changing; do not guess.
- Client API calls that wait on the game must have timeouts and a cancel path. See the
  scan state machine in `MalexisAuctionWatcher/Scanning.lua` for the pattern.
- Optional dependencies (Auctionator, TSM) are always guarded and never required.
- Bump the version in the `.toc` and `Core.lua` load message together.
- Never commit `WTF/`, saved variables, or zips.

## Verifying changes

There is no Lua interpreter on the maintainer's machine and no test suite. Verification is
in game: deploy, `/reload`, run the commands, check BugSack. State plainly in the summary
that in-game checks were not run when that is the case.
