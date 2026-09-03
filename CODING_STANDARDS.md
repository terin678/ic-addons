# Coding standards

These apply to every addon in this repo. They exist so that anyone in the guild can open
any addon here and find the same shape.

## Layout of an addon

```
AddonName/
  AddonName.toc        Interface, Title, Version, SavedVariables, OptionalDeps, file list
  Core.lua             Namespace table, event frame, slash commands, load message
  <Feature>.lua        One file per concern (Database, Scanning, UI, ...)
  Helpers.lua          Pure functions with no frame or event dependencies
```

- The `.toc` file list is load order. Data and logic files load before UI files.
- Only the addon folder ships. No README, screenshots, or scripts inside it.
- One global per addon, named after the addon, holding everything the other files need.
  Files that need it start with `local MAW = _G.MalexisAuctionWatcher or {}` and end with
  `_G.MalexisAuctionWatcher = MAW`. Do not create other globals except frames that must be
  named for `UISpecialFrames` or templates.

## Lua style

- Four-space indentation. No tabs.
- `local` everything that is not deliberately exported. Cache library functions you call in
  hot paths at file scope.
- Functions on the addon table use colon syntax: `function MAW:DoThing()`. Pure helpers are
  `local function`.
- Name booleans as questions (`isScanning`, `hasData`), tables as plural nouns, constants
  in `UPPER_SNAKE` at the top of the file with a comment saying what unit they are in.
- Prefer early returns over nested `if` blocks.
- Comments say why, not what. A comment above a function states what it takes, what it
  returns, and any side effects the caller must know about.
- No trailing whitespace. Files end with a newline. Unix line endings.

## Client API rules

- Target one interface version per flavor and put it in the `.toc`. Check the version
  against an installed, up-to-date addon on that client rather than guessing.
- Guard every optional dependency: check the global exists and the function is a function
  before calling, and wrap unsupported internal APIs in `pcall`.
- Anything that waits on the client (auction queries, item info, bank contents) is a state
  machine with a timeout on every wait. Never loop on a condition that the client might
  never satisfy. Every stuck state must have a way out that does not need `/reload`.
- Use `C_Timer.After` for delays, never busy-wait in `OnUpdate`. Throttle `OnUpdate`
  handlers with an accumulator.
- Frame pools over frame churn: reuse widgets on refresh, hide extras.

## Saved variables

- One account-wide table and, if needed, one per-character table, declared in the `.toc`.
- Initialise every field with a default on `ADDON_LOADED`; never assume a key exists.
- When the schema changes, migrate in place and keep reading the old shape for one
  version. Never delete user data during a migration.
- Store timestamps as `time()` integers, money as copper integers, day buckets as
  `floor(time() / 86400)`.

## User-facing text

- Chat output is prefixed with the addon name. Errors also go to `UIErrorsFrame`.
- Every slash command is listed in `/<cmd> help` with a one-line description.
- Anything that can silently do nothing (a source with no data, an item not cached) prints
  a reason.
- Colors: green for good/cheap, red for bad/expensive, amber for external or derived
  values, grey for missing. Use the same meaning across the whole addon.

## Window layout

- Every list has a column header row, in a frame **above** the ScrollFrame, never inside the
  scroll child, so headers stay put while rows scroll.
- List rows are fixed height and single line. Cells use `SetWordWrap(false)` (plus
  `SetMaxLines(1)` where it exists) and truncate; the full text goes in a hover tooltip or a
  detail panel. Never let a row's text decide the row's height, and never measure wrapped
  text to lay out a list.
- Toolbars (add, search, sort, filters, bulk actions) sit in a row above the headers.
  Nothing is anchored over the scroll area: no bottom-anchored control sharing space with a
  list. Legends go in the toolbar or a header tooltip.
- A page never overflows its frame. Add up the vertical offsets when you edit a form; if the
  total exceeds the page height, put the form in a ScrollFrame.
- Prose above a list has explicit line breaks and a known line count, so the list's top
  offset is predictable.
- Timestamps in lists show relative age (12s, 5m, 3h, 2d). The exact time goes in the tooltip.
- A button that toggles something shows the current state in its label or colour, and the
  page refreshes after the click.
- Colours follow the User-facing text section: green good or on, red bad or off or vetoed,
  amber pending or derived, grey missing or finished. One meaning per colour per addon.
- Build lists with the shared widget library `LibICUI-1.0` (ICLibs) through the addon's own
  thin wrapper, not with hand-placed FontStrings per tab.

## Versioning and release

- Semantic-ish: bump patch for fixes, minor for features, major for saved-variable
  schema changes that are not backward compatible.
- The version appears in three places and must match: `## Version:` in the `.toc`, the
  load message in `Core.lua`, and the packaged zip name.
- Commit messages: imperative subject under 72 characters, a body that says what changed
  for the player and anything a maintainer must know (migrations, new commands).

## Review checklist

- Loads without errors on the target client with `Load out of date AddOns` off.
- Every new command is in `help`.
- Every new wait has a timeout and a visible failure message.
- No new globals (check with `/dump` or a globals-leak addon).
- Docs updated: the addon's guide in `Docs/` and this file if a convention changed.
