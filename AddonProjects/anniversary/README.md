# TBC Anniversary addons

Target interface: 20506. Client folder `_anniversary_`.

| Addon | Version | Guide |
| --- | --- | --- |
| MalexisAuctionWatcher | 1.18.0 | [Docs/MalexisAuctionWatcher.md](../../Docs/MalexisAuctionWatcher.md) |
| AuctionatorSellingTweaks | 1.0.0 | [Docs/AuctionatorSellingTweaks.md](../../Docs/AuctionatorSellingTweaks.md) |
| TradeMaster | 1.13.1 | [Docs/TradeMaster.md](../../Docs/TradeMaster.md) |
| CutMaster | 1.2.0 | [Docs/CutMaster.md](../../Docs/CutMaster.md) |
| ICLibs | 1.4.0 | [Docs/ICLibs.md](../../Docs/ICLibs.md) |

`ICLibs` is a library addon. MalexisAuctionWatcher and TradeMaster list it under
`## Dependencies`, so it must be installed alongside them; `scripts/package.ps1` bundles it
into their zips and `scripts/deploy.ps1` links it into the game folder with them.
