# RenderTuner

A graphics tuner for WoW Forever: upscaling presets, a control for every graphics console
variable, and a way to compare the saved settings with the ones being tried.

**Version 0.0.1 only asks the client questions.** It changes no setting. The presets, the
panel and the options page are built on what it finds.

## What the client can and cannot do

The Forever client (1.60.1) has **no DLSS, DLAA, XeSS, or FSR 2 and later**. The client
binary holds none of them and no NVIDIA upscaler library ships with the game. The "DLSS 5"
videos of Forever use outside tools that inject into the game; an addon cannot do that, and
this one does not try.

What the client does have, all driven by console variables an addon may set:

| Area | Console variables |
| --- | --- |
| Upscaling | `RenderScale`, `ResampleQuality` (point, bilinear, bicubic, FSR 1.0), `ResampleSharpness`, `ResampleAlwaysSharpen` |
| Dynamic resolution | `DynamicRenderScale`, `DynamicRenderScaleMin`, `targetFPS` |
| Anti-aliasing | `ffxAntiAliasingMode` (FXAA, CMAA, CMAA2), `MSAAQuality`, `CMAA2Quality`, `CMAA2ExtraSharpness` |
| Latency | `LowLatencyMode` (NVIDIA Reflex, Intel XeLL) |
| HDR | `HDROutput`, `HDRBrightness`, `HDRPeakBrightness`, `HDRFactor` |
| Colour | `Gamma`, `Brightness`, `Contrast` |

FSR 1.0 is a spatial upscaler: it sharpens a lower-resolution frame and has no memory of
earlier frames. A "Quality" preset built on it raises the frame rate the way a DLSS preset
does, and it does not look the same.

## Install

Extract into `_classic_beta_\Interface\AddOns` so you get `AddOns\RenderTuner\RenderTuner.toc`.
RenderTuner needs **ICKit**, which goes beside it (`AddOns\ICKit`). Restart the client after
installing; a `/reload` does not pick up a new addon.

## Commands

`/tuner` or `/rendertuner`.

| Command | What it does |
| --- | --- |
| `/tuner` | What has been asked so far |
| `/tuner probe` | Lists every console variable the client has, with its value, default and help text, and saves the list |
| `/tuner capture report` | Tries capturing the screen into a picture the way the report window does |
| `/tuner capture photo` | Tries it the way the photo sharing window does |
| `/tuner capture view split` | Shows the capture on the left half of the screen, lined up with the live picture |
| `/tuner capture view full` | Shows the capture whole, at half size |
| `/tuner capture clear` | Takes the capture off the screen |
| `/tuner test` | Runs the built-in checks |

## Why it captures the screen

The client draws the world once per frame with one set of console variables, so an addon
cannot show two settings side by side live. A split view is still possible if the screen
can be captured into a texture: switch to the saved settings for a moment, capture, switch
back, and show the left part of the capture over the live picture. The left side is then a
still, right while the camera holds still.

Two calls in the exported interface source might give that capture. Neither is proven for
addons, which is what `/tuner capture` finds out. If neither works, the comparison is a
full-screen flip between the two sets of settings instead.

## Saved data

| Table | Scope | Holds |
| --- | --- | --- |
| `RenderTunerDB` | account | `settings`, `probe` (the last `/tuner probe`), `capture` (what each capture attempt came to) |
| `RenderTunerCharDB` | character | nothing yet |

The probe list is large, a row for each of the client's console variables. It is there to
be read off disk while the addon is being built and goes away once the catalogue of knobs
is written.
