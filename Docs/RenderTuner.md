# RenderTuner

A graphics tuner for WoW Forever: upscaling presets, a control for every graphics console
variable worth having, and a way to go back to what you had.

**Version 0.2.2 has the floating panel and the commands.** The page in the game's Options
window and the side-by-side comparison come next.

## What the client can and cannot do

The Forever client (1.60.1) has **no DLSS, DLAA, XeSS, or FSR 2 and later**. The client
binary holds none of them and no NVIDIA upscaler library ships with the game. The "DLSS 5"
videos of Forever use outside tools that inject into the game; an addon cannot do that, and
this one does not try.

What the client does have is a render scale with an FSR 1.0 upscale and a sharpening pass,
image and multisample anti-aliasing, low latency modes, HDR and colour correction, all
driven by console variables an addon may set. RenderTuner sets those and nothing else.

FSR 1.0 is a spatial upscaler: it sharpens a lower-resolution frame and has no memory of
earlier frames. A "Quality" preset built on it raises the frame rate the way a DLSS preset
does, and it does not look the same.

## Install

Extract into `_classic_beta_\Interface\AddOns` so you get `AddOns\RenderTuner\RenderTuner.toc`.
RenderTuner needs **ICKit**, which goes beside it (`AddOns\ICKit`). Restart the client after
installing; a `/reload` does not pick up a new addon.

## Some settings can crash the game

Settings marked **experimental** can crash the game or leave it unable to draw the world.
They depend on your graphics card and its driver, and the client itself calls some of them
beta features. The ones marked so far:

| Setting | Why |
| --- | --- |
| Dynamic render scale | The client's own help text calls it a beta feature, and it has crashed the 1.60.1 client |
| HDR output | Depends on the monitor and the render format, and restarts the graphics engine |
| Ray traced shadows | Needs a graphics card and driver that support ray tracing |
| Variable rate shading, VRS always on | Needs hardware support, and changes how the picture is shaded |

The mark shows beside the setting's name in the panel, in its tooltip and in `/tuner list`.

In the panel, turning an experimental setting on asks first. Turning one off never asks.

The first time you open the panel in a session, a warning says this and waits for
**I understand**. Tick **Do not show this again** and it stays away for good.

**Save a set that works before trying one**, so Revert has somewhere to return to. If the
game will not start afterwards, delete `WTF\Config.wtf` in the game folder
(`_classic_beta_\WTF\Config.wtf`): the client starts with default settings and writes a new
one. That file holds machine-wide settings only, such as graphics and sound, not your
characters, keybinds or addons' data.

## The panel

`/tuner` opens it, and so does a left-click on RenderTuner in the addon list beside the
minimap. A right-click there offers the presets without opening anything. Drag the panel
by its title bar; Escape closes it. Its place is kept per character.

- **Upscaling presets** run across the top. The one in use is highlighted. They set the
  render scale and the resample filter and nothing else, and clicking one brings the
  Upscaling group into view so you can see what it changed. "Quality" and "Performance"
  are the names DLSS uses for render scales; they do not touch the quality levels.
- **Save** keeps the settings as they are now. **Revert** puts everything back to the
  saved set. **More...** has the client's defaults, the way back to before RenderTuner,
  and a restart of the graphics engine.
- **Groups** are down the left, and the rows on the right are the settings of the one
  picked. A change takes effect as you make it, with the world in view behind the panel.
- A setting that differs from the saved set is in the accent colour, and its group shows
  a count. The title bar reads, for example, "67% Quality, 2 unsaved".
- **Hover a setting's name** for what it does, its console variable, and its saved value.
  **Click the name** to put that one setting back to its saved value or the client's default.
- **A greyed-out setting** is one this client will not change at the moment, such as
  ray traced shadows on a client or card without ray tracing. Its tooltip gives the
  client's reason. In a dropdown, single choices the client refuses are greyed the same way.
- **Overall quality**, in Quality levels, moves the levels beneath it, as the same slider
  does on the game's own graphics page.
- **Restart graphics** appears when a change needs the graphics engine restarted before
  it shows.

The render scale slider applies when you let go of it rather than on every step, because
each change rebuilds what the client draws into. Every other slider is live.

## Presets

| Preset | Render scale | Resample filter |
| --- | --- | --- |
| `native` | 100% | left as it is |
| `quality` | 67% | FSR 1.0 |
| `balanced` | 58% | FSR 1.0 |
| `performance` | 50% | FSR 1.0 |
| `ultra` | 33% (the client's floor) | FSR 1.0 |

`/tuner preset quality` uses one; the start of a name is enough (`/tuner preset perf`).
`/tuner off` goes to native and `/tuner on` returns to the last upscaling preset you used.
A preset does not touch the sharpening strength, so it stays where you set it.

## Saved, trial and original

The settings that are live in the game are the only copy that matters. RenderTuner keeps
two sets to go back to:

- **Saved** is what `/tuner save` last recorded. `/tuner revert` returns to it.
- **Original** is what was live the first time RenderTuner ran. `/tuner restore` returns
  to it, whatever you have saved since.

Anything you change is a trial until you save it. Trial changes survive a `/reload` and a
logout, because the client stores console variables itself; the login line tells you how
many settings differ from the saved set.

## Commands

`/tuner` or `/rendertuner`.

| Command | What it does |
| --- | --- |
| `/tuner` | Opens or closes the panel |
| `/tuner status` | The render scale, its preset, and how many settings differ from saved |
| `/tuner preset [name]` | Lists the presets, or uses one |
| `/tuner on`, `/tuner off` | Upscale with the last preset used, or go back to native |
| `/tuner list` | The groups, with how many settings each has and how many have changed |
| `/tuner list <group>` | Every setting in a group with its value, and the saved value where it differs |
| `/tuner list changed` | Only the settings that differ from saved |
| `/tuner set <variable> <value>` | Sets one console variable from the catalogue |
| `/tuner save` | Records the live settings as the saved set |
| `/tuner revert` | Goes back to the saved set |
| `/tuner defaults` | Sets everything to the client's defaults for this machine |
| `/tuner restore` | Goes back to how things were before RenderTuner first ran |
| `/tuner restart` | Restarts the graphics engine, for the few changes that need it |
| `/tuner test` | Runs the built-in checks |

`/tuner set` takes the value as `/tuner list` shows it: a number for a slider or a choice
(`/tuner set ffxAntiAliasingMode 4`), `on` or `off` for a toggle. A slider value is snapped
to its step and kept inside its range; a choice that is not offered is refused, with the
list of what is.

## The settings

About ninety console variables in nine groups. A variable this client does not have, or
will not let an addon set, is left out when the addon loads.

| Group | `/tuner list` name | What is in it |
| --- | --- | --- |
| Upscaling | `upscale` | Render scale, resample filter, sharpening, dynamic render scale |
| Anti-aliasing | `aa` | FXAA, CMAA, CMAA2 and its quality, multisampling |
| Latency and frame rate | `frame` | Reflex and XeLL, vertical sync, triple buffering, frame rate limits and target |
| Colour | `colour` | Gamma, brightness, contrast |
| HDR | `hdr` | HDR output, brightness and peak overrides, HDR factor |
| Quality levels | `quality` | The levels on the game's own graphics page |
| Shadows and lighting | `shadow` | Shadow technique and resolution, ray traced shadows, ambient occlusion, fog, bloom |
| World detail | `world` | Draw distances, level of detail, water, weather, texture filtering |
| Effects | `effects` | Field of view, full-screen effects, variable rate shading, physics |

Three things are left out on purpose: the client's second, raid-only copy of these
variables; variables that take text, such as the graphics API and the adapter; and the
engine's threading, streaming and debugging variables.

When several settings change at once, the quality levels are set first. The client moves
the variables beneath a level when the level changes, so they have to be set after it.

## The comparison view (coming)

The client draws the world once per frame with one set of console variables, so two
settings cannot be shown side by side live. What works instead: switch to the saved
settings for a moment, capture the world into a texture, switch back, and show the left
part of that capture over the live picture, with a divider to drag. The left side is a
still, right while the camera holds still.

The capture was tested in 0.0.1 and works: it is sharp, lines up with the live picture and
holds the world only, without the interface. `/tuner capture report` still shows it.

## Saved data

| Table | Scope | Holds |
| --- | --- | --- |
| `RenderTunerDB` | account | `saved`, `original`, `settings` (the last preset used), and for now `probe` and `capture` from the client questions |
| `RenderTunerCharDB` | character | nothing yet |
