# ic-addons

World of Warcraft addons maintained for the guild, organised by game flavor.

```
ic-addons/
  Docs/                  User guides and design notes, one file per addon plus shared references
  AddonProjects/
    era/                 Classic Era (interface 115xx)
    anniversary/         TBC Anniversary (interface 20506)
    retail/              Retail (interface 12xxxx)
  scripts/               Deploy and packaging helpers (PowerShell)
  .claude/skills/        Claude Code skills for working in this repo
  CODING_STANDARDS.md    Lua and addon conventions everyone follows here
  CLAUDE.md              Entry point Claude Code reads on every session
```

Each addon lives at `AddonProjects/<flavor>/<AddonName>/` and that folder is exactly what
ships: its `.toc` and Lua files, nothing else. Packaging zips that folder so the archive
extracts straight into `Interface\AddOns`.

## Working on an addon

1. Link or copy the addon folder into the game client. `scripts/deploy.ps1` creates a
   directory junction so the game loads files straight from this repo:

   ```powershell
   .\scripts\deploy.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher
   ```

2. Edit, then `/reload` in game. Check BugSack or the `Errors` folder for Lua errors.
3. Bump `## Version:` in the `.toc` and the load message when behaviour changes.
4. Package for sharing:

   ```powershell
   .\scripts\package.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher
   ```

   The zip lands in `dist/` (ignored by git).

## Branching

`main` is protected: no direct pushes, no force pushes, changes land only through a pull
request. Development happens on branches:

- `feature/<topic>` for new work, `fix/<topic>` for bug fixes. One addon or concern per branch.
- Commit early and often on the branch; push it so others can see it.
- When it is ready, open a PR (`gh pr create` fills in the template), run the in-game
  checklist, then squash-merge. Delete the branch after merging.
- Long-running addon work stays on its feature branch between releases, for example
  `feature/auction-watcher`; rebase it on `main` after each merge.

## Addons

| Flavor | Addon | Notes |
| --- | --- | --- |
| anniversary | [MalexisAuctionWatcher](AddonProjects/anniversary/MalexisAuctionWatcher) | Price tracking, history charts, recipe profit, Auctionator/TSM feeds. Guide: [Docs/MalexisAuctionWatcher.md](Docs/MalexisAuctionWatcher.md) |
| anniversary | [CutMaster](AddonProjects/anniversary/CutMaster) | Jewelcrafting book scanning, trade chat/whisper customer detection, order tracking, income. Guide: [Docs/CutMaster.md](Docs/CutMaster.md) |
| anniversary | [AuctionatorSellingTweaks](AddonProjects/anniversary/AuctionatorSellingTweaks) | Expiry column before "You?" in Auctionator's Selling price list. Guide: [Docs/AuctionatorSellingTweaks.md](Docs/AuctionatorSellingTweaks.md) |

## Client paths on the maintainer's machine

| Flavor | AddOns folder |
| --- | --- |
| era | `D:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns` |
| anniversary | `D:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns` |
| retail | `D:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns` |

Override with `-WowRoot` on the scripts if your install is elsewhere.
