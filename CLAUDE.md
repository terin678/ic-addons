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
- Editing a `.toc` needs a client restart. `/reload` does not re-read it, and a client that has been running across `.toc` edits can stop restoring one addon's account-wide saved variables while still restoring the per-character ones. The fingerprint is `/x log` saying `SAVED VARIABLES WERE EMPTY` with the per-character table intact. Restart the client before reading a line of addon code.
- The plumbing every addon shares is `LibICCore-1.0` in ICLibs, installed by one
  `Core:Attach` call in `Core.lua`. Do not add a Print, a bootstrap, a Util or a test
  harness to an addon; `Docs/ICLibs.md` says what Attach installs.

## Verifying changes

Three things stand in for in-game verification, in order:

1. `python scripts/lint.py`. It parses every file and catches what has actually shipped
   broken: a local referenced inside its own assignment, a dead texture path, a `.toc` out
   of step with the files on disk, a version that moved in one place but not the others,
   and a quoted string running past its line -- which `luaparser` accepts and the client
   refuses to load.
2. The addon's own cases, in game. Six addons carry a `Tests.lua`: `/tm test`, `/cm test`,
   `/gr test`, `/ictpl test`, `/maw test`, `/mfd selftest`. Anything worth arguing about
   belongs in a pure function with a case here.
3. The `wow-ui-reviewer` agent on every UI file touched.

LuaJIT 2.1 (Lua 5.1 semantics, matching the client) is now installed on the maintainer's
machine, so an addon whose pure modules avoid the WoW API at file scope can also run its
cases outside the game: `scripts/run-tests.ps1 -Flavor <flavor> -Addon <Addon>`.
MarkedForDeath is built that way and its suite runs headlessly. A shell opened before the
install will not have `luajit` on PATH; the script falls back to the `LOCALAPPDATA` path.
Only modules that call no WoW API at file scope work this way -- caching a global into a
local is fine, calling one is not -- so anything that creates a frame or reads client
state does it in an init function registered from the addon's `Core.lua`.

Then deploy, `/reload`, run the commands, check BugSack. State plainly in the summary that
in-game checks were not run when that is the case.
