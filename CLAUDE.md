# ic-addons

Guild World of Warcraft addons. Read `CODING_STANDARDS.md` before changing any Lua.

## Where things are

- Addons: `AddonProjects/<flavor>/<AddonName>/`. Flavors: `era`, `anniversary`, `retail`.
  The addon folder is exactly what ships.
- User docs: `Docs/<AddonName>.md`. Update it whenever a command or tab changes.
- Scripts: `scripts/new-addon.ps1` (scaffold from ICTemplate), `scripts/deploy.ps1`,
  `scripts/package.ps1` (PowerShell 5.1), `scripts/lint.py` (Python).
- Skill for addon work: `.claude/skills/wow-addon-dev/SKILL.md`, and
  `client-api.md` beside it — the client contracts that have already shipped broken here.
  Read it before calling into the game.

## Git workflow

- Never commit on `main`; it is protected and only accepts pull requests. Check
  `git branch --show-current` before committing. If on `main`, create `feature/<topic>`
  or `fix/<topic>` first.
- Commit on the feature branch and push it. Open a PR with `gh pr create` when the user
  asks for a merge; the template in `.github/` is the review checklist.
- Merge with a merge commit (`gh pr merge --merge`), never a squash: each commit here is
  written to stand on its own, and `main` keeps them so a single change can be found and
  reverted on its own.

## Rules that matter most

- Interface versions: anniversary is 20506 (TBC). Verify against an installed addon on the
  client before changing; do not guess.
- Client API calls that wait on the game must have timeouts and a cancel path. See the
  scan state machine in `MalexisAuctionWatcher/Scanning.lua` for the pattern.
- Optional dependencies (Auctionator, TSM) are always guarded and never required.
- Bump the version in the `.toc`, the `Core.lua` load message and the row in
  `AddonProjects/<flavor>/README.md` together. `lint.py` fails on any two disagreeing.
- Never edit `CutMaster`; it belongs to a collaborator. Port upstream changes by hand into
  TradeMaster instead — `SKILL.md` has the procedure.
- Never commit `WTF/`, saved variables, or zips.

## Verifying changes

There is no Lua interpreter on the maintainer's machine, so nothing here runs outside the
game. Three things stand in for one, in order:

1. `python scripts/lint.py`. It parses every file and catches what has actually shipped
   broken: a local referenced inside its own assignment, a dead texture path, a `.toc` out
   of step with the files on disk, a version that moved in one place but not the others,
   and a quoted string running past its line -- which `luaparser` accepts and the client
   refuses to load.
2. The addon's own cases, in game. Five addons carry a `Tests.lua`: `/tm test`,
   `/cm test`, `/gr test`, `/ictpl test`, `/maw test`. Anything worth arguing about
   belongs in a pure function with a case here.
3. The `wow-ui-reviewer` agent on every UI file touched.

Then deploy, `/reload`, run the commands, check BugSack. State plainly in the summary that
in-game checks were not run when that is the case.
