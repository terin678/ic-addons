# ICTemplate

The worked example. It is a real addon that loads, runs and can be clicked around, and it
is also the folder you copy when you start a new one.

Two jobs, and they hold each other honest:

- Every LibICUI widget is on screen with the source it was built from next to it, so
  "how do I make a table with a flex column" is a click rather than a grep.
- Every one of those demos is compiled from that same source at load. Change ICLibs,
  `/reload`, and anything that broke turns red. It is the library's smoke test.

## Install

Copy `AddonProjects/anniversary/ICTemplate` and `AddonProjects/anniversary/ICLibs` into
`_anniversary_\Interface\AddOns`, or from the repo root:

```powershell
.\scripts\deploy.ps1 -Flavor anniversary -Addon ICTemplate
```

That links ICLibs alongside it, because ICTemplate lists it under `## Dependencies`.

## The window

`/ictpl` opens it. Five tabs.

**Gallery** is the point of the addon. The list on the left is grouped by kind; picking one
runs it in the pane on the right and shows its source underneath. **Copy source** selects
the text so you can press Ctrl+C — no addon on this client can reach the clipboard itself.
**Rebuild** throws the demo's widgets away and compiles it again, which is what you press
after editing ICLibs and reloading.

**Table** is every feature of `UI:Table` at once, at the size a real page uses it: icon,
check and custom columns, a flex column, a cell with its own hit frame, row buttons, group
headings, a tinted totals row, sorting by header click, and filters that survive a reload.

**Pulse** is the arm-and-fire pattern. A timer on this client cannot send to a public
channel; it can only arm, and a keypress or a click sends. The line above the button says
which reason is stopping it when it will not go. The demo sends an `EMOTE`, so running the
template cannot spam anyone, and an emote is protected in exactly the same way — it proves
the path works.

**Log** is the two-ring-buffer pattern: 100 decisions and 500 observations, merged into a
300-entry window, filtered, and 100 drawn. The count line says how many rows the filters
are holding back, so a short list explains itself.

**About** reports the addon on itself, and runs `/ictpl probe`: which client APIs this
build actually has, and what needs each one.

## Commands

| Command | Effect |
| --- | --- |
| `/ictpl` | Open or close the window |
| `/ictpl demo <id>` | Jump to one demo |
| `/ictpl list` | Print every demo id |
| `/ictpl pulse [secs]` | Toggle the timer, or set its interval |
| `/ictpl send` | Send the pulse now |
| `/ictpl preview` | Print what the next pulse would say |
| `/ictpl log [n]` | Print the last n log lines |
| `/ictpl probe` | Report which client APIs this build has |
| `/ictpl status` | One line per part of the addon |
| `/ictpl test` | Run the test suite |
| `/ictpl enable` / `disable` | Master switch |
| `/ictpl out [n]` | Print to ChatFrame n |
| `/ictpl reset [settings\|log\|all]` | Restore defaults |
| `/ictpl version` | Addon and library versions |

Two key bindings under **ICTemplate** in the key bindings panel: send the pulse, and open
the window.

## Starting a new addon from it

```powershell
.\scripts\new-addon.ps1 -Name GuildRecruitment -Slash gr -Title "Guild Recruitment" `
    -Notes "Shared recruitment message and a log of who barked when" -Minimal -Deploy
```

`-Minimal` leaves out the gallery — `Demos.lua`, `Snippet.lua`, `UI_Gallery.lua`,
`UI_Table.lua` and their tests — which is what you want for anything that is not itself a
widget catalogue. Drop it if you want the gallery to keep around while you work.

The script refuses to run if the folder exists, if the name is not PascalCase, or if the
slash command collides with one already in the repo. It finishes by running
`scripts/lint.py` on what it made, so a copy is proven before you ever load it.

### Renaming by hand

Three tokens, and only three. They are listed at the top of `Core.lua` as well.

| Token | Where it is |
| --- | --- |
| `ICTemplate` | the `.toc` filename and `## Title`, the `## IconTexture` path, `ICTemplateDB` and `ICTemplateCharDB`, the `prefix`, `db` and `cdb` handed to `Core:Attach`, the window frame name, the LibDataBroker object name, the two globals a key binding calls, and `ICTemplate.tga` |
| `ICTEMPLATE` | `SLASH_ICTEMPLATE1/2`, `SlashCmdList["ICTEMPLATE"]`, the `BINDING_*` globals, and the `<Binding name=...>` attributes in `Bindings.xml` |
| `ictpl` | the `/ictpl` slash string, and every mention of it in help text |

Everything else is namespaced: every file opens with `local addonName, ns = ...`, so no
other file has to know what the addon is called.

Two lines in the `.toc` are deliberately **not** tokens and must survive a rename:
`## Category: Impulse Control`, which is the heading every guild addon collapses under in
the in-game AddOns list, and `## Group: ICLibs`, which nests it under the Core area. A
group's value must be an addon that exists; a made-up one silently ungroups it. The script
carries `## Group:` over untouched and defaults `## Category:` to the guild heading, so the
command above is enough — but `-Category` overrides it, and any other value takes the new
addon out from under the heading. A hand rename has to remember both.
`Docs/client-reference.md` has how the list actually behaves, including the rule that an
addon uses either a title texture or an `## IconTexture`, never both.

## What to keep and what to throw away

Keep, always:

- The shape of `Core.lua`: `VERSION`, `SCHEMA`, `Migrations`, `Defaults`, `CharDefaults`,
  `HELP`, `COMMANDS` and the `Core:Attach` call at the end. There is nothing in it to copy
  unread any more; the plumbing it used to carry is LibICCore's, and `Docs/ICLibs.md`
  says what Attach installs. `Util.lua`, `Log.lua` and the test harness are gone from the
  template for the same reason -- `ns.Util`, `ns.Log` and `ns.Tests` arrive with Attach,
  and an addon's own pure helpers go in a `Util.lua` of its own only when it has some.
- The library wrapper block at the top of `UI.lua`, lines 1 to about 90. It is the whole of
  the addon's contact with LibICUI.
- `T.With` in the cases that use it: it swaps a made-up database in, which is the only way
  the impure half of an addon gets tested at all.
- The **"every page draws without erroring"** case. It builds the window and calls each
  page's refresher under `pcall`. A refresher is not pure, so nothing else in the file
  reaches one, and the bug it exists for -- reading a settings field at the wrong depth --
  is invisible to the linter and to every other case.

Throw away as soon as it is in the way: `Demos.lua`, `Snippet.lua`, `UI_Gallery.lua`,
`UI_Table.lua`, and `Pulse.lua` if your addon never says anything on a timer.

**If you delete `Pulse.lua`, its key binding goes with it.** `Bindings.xml` is not in the
`.toc` and the script does not touch it beyond renaming the tokens, so a binding pointing at
`<Addon>_PulseNow()` survives the deletion and errors the first time somebody presses the
key. Building GuildRecruitment found this the hard way. Delete or repoint the `<Binding>`,
its `BINDING_NAME_*` global in `Core.lua`, and the global function it calls, together.

## Rules it is demonstrating

These come from `CODING_STANDARDS.md`, and the template is where they are all in one place.

- **A filter is saved state, not session state.** Kept on a Lua table it resets on reload,
  and a list that comes back empty reads as lost data. Every toggle in the window writes to
  `ICTemplateDB`.
- **A short list says why it is short.** `Log.Filter` returns what it hid as well as what
  it kept, and the count line reports both.
- **Rows come out of a pool.** Every script is set inside `Render`, never once at build
  time, or a row fires the previous item's handler.
- **A gate is a pure predicate plus a separate reading of the world.**
  `Pulse.BlockReason(state)` can be tested; `Pulse.ReadState()` is the only function that
  looks at the game. The order of the reasons is the contract, because the UI shows the
  first one.
- **Migrate before you default.** A migration that runs after `ApplyDefaults` cannot tell a
  field the player never had from one the defaults just invented.
- **Anything unverified gets probed, not guessed.** `/ictpl probe` and then a line in
  `.claude/skills/wow-addon-dev/client-api.md`.

## What the client will not let it do

`SendChatMessage` to a public channel needs a hardware event, which is why the pulse arms
and waits rather than sending on its own. There is no clipboard API, so **Copy source**
can only select the text for you. `loadstring` is what compiles the demos; `/ictpl probe`
says whether this build has it, and the gallery says so plainly if it does not.
