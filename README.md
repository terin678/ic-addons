<p align="center">
  <img src="Docs/assets/impulse-control.png" width="160" alt="Impulse Control">
</p>

# ic-addons

World of Warcraft addons maintained for **Impulse Control** — that is what the `ic-` is —
organised by game flavor. They share one library, one palette and one heading in the
in-game AddOns list, so they read as one set rather than a pile of unrelated addons.

```
ic-addons/
  Docs/                  User guides and design notes, one file per addon plus shared references
    assets/              The guild mark, as the master image the game textures come from
  AddonProjects/
    era/                 Classic Era (interface 115xx)
    anniversary/         TBC Anniversary (interface 20506)
    retail/              Retail (interface 12xxxx)
  scripts/               Scaffold, deploy, package (PowerShell) and lint (Python)
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
   Most addons also have their own checks: `/maw test`, `/tm test`, `/gr test`, `/ictpl test`.
3. Bump `## Version:` in the `.toc`, the `local VERSION` load message where the addon has
   one, and the row in `AddonProjects/<flavor>/README.md`. The linter checks all three.
4. Lint before packaging. There is no Lua on this machine, so this is what stands in for a
   compiler:

   ```bash
   python scripts/lint.py
   ```

5. Package for sharing:

   ```powershell
   .\scripts\package.ps1 -Flavor anniversary -Addon MalexisAuctionWatcher
   ```

   The zip lands in `dist/` (ignored by git).

## Starting a new addon

Copy [ICTemplate](AddonProjects/anniversary/ICTemplate) — a working addon whose window is a
live gallery of every shared widget beside the source that built it. The script does the
copy, the rename, the three registration rows and the lint run:

```powershell
.\scripts\new-addon.ps1 -Name MyAddon -Slash myaddon -Title "My Addon" -Minimal
```

[Docs/ICTemplate.md](Docs/ICTemplate.md) covers what to keep, what to throw away, and how to
do the rename by hand.

## Branching

`main` is protected: no direct pushes, no force pushes, changes land only through a pull
request. Development happens on branches:

- `feature/<topic>` for new work, `fix/<topic>` for bug fixes. One addon or concern per branch.
- Commit early and often on the branch; push it so others can see it.
- When it is ready, open a PR (`gh pr create` fills in the template), run the in-game
  checklist, then merge with a merge commit (`gh pr merge --merge`). Delete the branch
  after merging. Commits are written to be read one at a time, so `main` keeps them:
  a squash turns a branch's worth of separate, revertable changes into one entry that
  says less than any of them did.
- Long-running addon work stays on its feature branch between releases, for example
  `feature/auction-watcher`; rebase it on `main` after each merge.

## Addons

| Flavor | Addon | Notes |
| --- | --- | --- |
| anniversary | [MalexisAuctionWatcher](AddonProjects/anniversary/MalexisAuctionWatcher) | Price tracking, history charts, recipe profit, Auctionator/TSM feeds. Guide: [Docs/MalexisAuctionWatcher.md](Docs/MalexisAuctionWatcher.md) |
| anniversary | [CutMaster](AddonProjects/anniversary/CutMaster) | Jewelcrafting book scanning, trade chat/whisper customer detection, order tracking, income. Guide: [Docs/CutMaster.md](Docs/CutMaster.md) |
| anniversary | [AuctionatorSellingTweaks](AddonProjects/anniversary/AuctionatorSellingTweaks) | Expiry column before "You?" in Auctionator's Selling price list. Guide: [Docs/AuctionatorSellingTweaks.md](Docs/AuctionatorSellingTweaks.md) |
| anniversary | [TradeMaster](AddonProjects/anniversary/TradeMaster) | Crafting business assistant for any profession, generalised from CutMaster. Guide: [Docs/TradeMaster.md](Docs/TradeMaster.md) |
| anniversary | [ICLibs](AddonProjects/anniversary/ICLibs) | Shared libraries (LibStub, LibICTradeSkill, LibICUI) required by MalexisAuctionWatcher, TradeMaster, ICTemplate and GuildRecruitment. Guide: [Docs/ICLibs.md](Docs/ICLibs.md) |
| anniversary | [ICTemplate](AddonProjects/anniversary/ICTemplate) | The worked example: every LibICUI widget on screen beside the source it was built from. Copy it to start a new addon. Guide: [Docs/ICTemplate.md](Docs/ICTemplate.md) |
| anniversary | [GuildRecruitment](AddonProjects/anniversary/GuildRecruitment) | One recruitment message the raid leaders set and every officer sends, kept in step across the guild, with a log of who barked when. Guide: [Docs/GuildRecruitment.md](Docs/GuildRecruitment.md) |

## Client paths on the maintainer's machine

| Flavor | AddOns folder |
| --- | --- |
| era | `D:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns` |
| anniversary | `D:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns` |
| retail | `D:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns` |

Override with `-WowRoot` on the scripts if your install is elsewhere.
