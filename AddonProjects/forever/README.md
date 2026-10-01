# WoW Forever addons

Target interface: 16001 (product `wow_classic_beta`, version 1.60.1). Client folder
`_classic_beta_` while the game is in beta; `scripts/flavors.psd1` is where that changes.

| Addon | Version | Guide |
| --- | --- | --- |
| ICKit | 0.1.0 | [Docs/ICKit.md](../../Docs/ICKit.md) |

`ICKit` is the library addon for this flavor. Addons here list it under `## Dependencies`,
so it must be installed alongside them; `scripts/package.ps1` bundles it into their zips
and `scripts/deploy.ps1` links it into the game folder with them.

This is a different code base from the Anniversary set. It is built bottom-up, one layer
at a time, and nothing is ported until the layers it needs exist: see
[Docs/forever/VISION.md](../../Docs/forever/VISION.md) before adding anything here.
