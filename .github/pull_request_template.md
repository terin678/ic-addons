## What changed

<!-- One paragraph for the player: what they will notice. Then anything a maintainer must know: migrations, new commands, new dependencies. -->

## Checklist

- [ ] Loads on the target client with "Load out of date AddOns" off, BugSack empty
- [ ] Every new command is in `/<cmd> help`
- [ ] Every new wait on the client has a timeout and a visible failure message
- [ ] Optional dependencies are guarded (global and function checked, internals in `pcall`)
- [ ] No new globals
- [ ] `## Version:` in the `.toc` and the load message in `Core.lua` bumped together
- [ ] `Docs/<Addon>.md` and `AddonProjects/<flavor>/README.md` updated

## In-game steps run

<!-- List the commands and clicks you tried and what happened. -->
