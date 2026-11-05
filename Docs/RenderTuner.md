# RenderTuner

The one place to tune WoW Forever's graphics: upscaling and quality presets, a live control
for about 140 console variables, search, and a way back to what you had.

**Version 0.4.0 has the floating panel and the commands**, an Extreme quality preset with
the experimental extras, and a panel that can get out of the way of the world it tunes. The
page in the game's Options window and the side-by-side comparison come next.

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

Extract into `_forever_\Interface\AddOns` so you get `AddOns\RenderTuner\RenderTuner.toc`.
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
| Render format | Changes the precision the whole picture is drawn at, and restarts the graphics engine |
| Ray traced shadows | Needs a graphics card and driver that support ray tracing |
| Variable rate shading, VRS always on | Needs hardware support, and changes how the picture is shaded |

The mark shows beside the setting's name in the panel, in its tooltip and in `/tuner list`.

In the panel, turning an experimental setting on asks first. Turning one off never asks.

The first time you open the panel in a session, a warning says this and waits for
**I understand**. Tick **Do not show this again** and it stays away for good.

**Save a set that works before trying one**, so Revert has somewhere to return to. If the
game will not start afterwards, delete `WTF\Config.wtf` in the game folder
(`_forever_\WTF\Config.wtf`): the client starts with default settings and writes a new
one. That file holds machine-wide settings only, such as graphics and sound, not your
characters, keybinds or addons' data.

## The panel

`/tuner` opens it. So does a left-click on RenderTuner in the addon list beside the
minimap, and a key you bind under Options, Keybindings. A right-click in the addon list
offers the upscaling presets without opening anything. Drag the panel by its title bar;
Escape closes it. Its place is kept per character, and it starts toward the left edge, so
the middle of the screen stays clear.

**The title bar** shows the frame rate, measured twice a second while the panel is open, and
where things stand: "67% Quality, 2 unsaved".

**Getting out of the way.** The panel sits over the world you are tuning, so it can step aside:

- **Peek**, in the title bar, makes the panel nearly clear for as long as you hold the
  button. **Hold to see the world behind the panel** is also a key binding, under Options,
  Keybindings, AddOns: hold the key, look, let go.
- **Compact** folds the panel to the title bar and the two rows of presets. **Expand**
  brings it back. Which one you left it in is kept per character.
- **While a slider is held** the panel goes half clear, so you see what the thumb is doing.

**Two rows of presets** run across the top, from least to most, left to right. The one in
use in each is highlighted.

- **Upscaling** sets the render scale and the resample filter and nothing else. Each button
  shows the share of the screen's pixels it draws. "Quality" and "Performance" here are the
  names DLSS uses for render scales; they do not touch the quality levels.
- **Quality** sets the game's overall quality level, and the levels beneath it, and leaves
  upscaling alone. **Extreme**, at the right in orange, is Ultra and then some: it also
  turns on the experimental HDR output and a 16-bit float render format, after asking.
  Choosing a lower level puts those two back to the client's defaults.

Clicking a preset brings the group it changes into view, so you see what it did. The two
rows are independent: Potato upscaling with Ultra quality is a combination you can make.

**Save** keeps the settings as they are now. **Revert** puts everything back to the saved
set. **More...** has the client's defaults, the way back to before RenderTuner, and a
restart of the graphics engine.

**The search box** finds settings by name, by console variable, by what their help says or
by group, across every group at once: type `shadow` or `fps`. Escape clears it.

**Down the left** are the groups, in three clusters: Picture, Detail and Advanced. Advanced
is folded away until you open it (the line saying `Advanced +`), and says how many of its
settings changed while it is shut. **Changed**, at the top, lists everything that differs
from the saved set, whatever group it is in. A group with changes shows a count.

**The rows on the right** are the settings in view, and they scroll with the mouse wheel.
The line under them says what the setting under the pointer does.

- **Click a slider's number** to type a value instead of dragging: `67` for 67%, a level
  from 1, nits or frames as they read. Enter sets it; Escape or clicking away drops it.

- A change takes effect as you make it, with the world in view behind the panel.
- A setting that differs from saved is in the accent colour and gains an **undo** at the
  end of its row, which puts that one setting back. **Revert these**, in the heading,
  puts back everything in view.
- **Hover a setting's name** for what it does, its console variable, its saved value, the
  client's default and its range. **Click the name** to choose between the saved value
  and the client's default.
- **A greyed-out setting** is one this client will not change at the moment, such as ray
  traced shadows. Its tooltip gives the client's reason. In a dropdown, single choices
  the client refuses are greyed the same way.
- **Overall quality**, in Quality levels and in Raid profile, moves the levels beneath
  it, as the same slider does on the game's own graphics page.

**Restart graphics** appears when a change needs the graphics engine restarted before it
shows.

The render scale slider applies when you let go of it rather than on every step, because
each change rebuilds what the client draws into. Every other slider is live.

## Presets

**Upscaling:**

| Preset | Render scale | Resample filter |
| --- | --- | --- |
| `potato` | 33% (the client's floor) | FSR 1.0 |
| `performance` | 50% | FSR 1.0 |
| `balanced` | 58% | FSR 1.0 |
| `quality` | 67% | FSR 1.0 |
| `native` | 100% | left as it is |

`/tuner preset quality` uses one; the start of a name is enough (`/tuner preset perf`).
`/tuner off` goes to native and `/tuner on` returns to the last upscaling preset you used.
A preset does not touch the sharpening strength, so it stays where you set it.

**Quality:**

| Preset | Overall quality, of 10 |
| --- | --- |
| `low` | 1 |
| `fair` | 3 |
| `good` | 5 |
| `high` | 7 |
| `ultra` | 10 |
| `extreme` | 10, and HDR output on with a 16-bit float render format (experimental) |

`/tuner quality high` uses one. Each sets the overall level and asks the client what every
level beneath it should be at that level, which is what the slider on the game's own
graphics page does.

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
| `/tuner quality [name]` | Lists the overall quality presets, or uses one |
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
list of what is. A quality level is counted from 1, as the game shows it.

Two keys can be bound under Options, Keybindings, AddOns: one opens and closes the panel,
the other is Peek, held to see the world behind it. A new key binding needs a full client
restart to appear.

## The settings

About 140 console variables in sixteen groups. A variable this client does not have, or
will not let an addon set, is left out when the addon loads.

| Group | `/tuner list` name | What is in it |
| --- | --- | --- |
| Upscaling | `upscale` | Render scale, resample filter, sharpening, dynamic render scale |
| Anti-aliasing | `aa` | FXAA, CMAA, CMAA2 and its quality, multisampling |
| Latency and frame rate | `frame` | Reflex and XeLL, vertical sync, triple buffering, frame rate limits and target |
| Colour | `colour` | Gamma, brightness, contrast |
| HDR | `hdr` | HDR output, brightness and peak overrides, HDR factor, render format |
| Quality levels | `quality` | The overall level and the fifteen levels beneath it, from the game's own graphics page |
| Shadows | `shadow` | Shadow technique, resolution, cascades and range, ray traced shadows |
| Lighting and fog | `light` | Ambient occlusion, sun shafts, volumetric fog, bloom, specular, light distance |
| Ambient occlusion tuning | `ssao` | The contact-shadow shader's own controls: radius, strength, contrast, blur, fade |
| Textures | `texture` | Filtering, and resolution of world, terrain and character textures |
| View distance and detail | `world` | Far clip, fog, and how far terrain, buildings, objects and creatures keep their detail |
| Water and weather | `water` | Water detail and shading, ripples, reflections, weather density |
| Particles and spells | `particles` | Particle density, spell clutter, projected textures, thinning out crowds |
| Effects and camera | `effects` | Field of view, full-screen effects, outlines, variable rate shading, physics |
| Raid profile | `raid` | A second set of quality levels the game uses inside raids, and the switch for it |
| Cursor and screenshots | `misc` | Hardware cursor, cursor size, screenshot quality |

Three things are left out on purpose: the raw variables beneath the raid levels (the raid
levels themselves are there); variables that take text, such as the graphics API, the
adapter and the screenshot format; and the engine's threading, streaming and debugging
variables.

The ranges of the ambient occlusion tuning sliders come from the client's own help text.
Ranges elsewhere that the client does not state, in HDR and in View distance and detail,
are estimates: a value outside a slider's range is shown as it is and left alone until
you move the slider.

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
| `RenderTunerDB` | account | `saved`, `original`, `settings` (the last preset used, whether the warning is skipped), and for now `probe` and `capture` from the client questions |
| `RenderTunerCharDB` | character | `panel`: where the panel sits and the group it last showed |
