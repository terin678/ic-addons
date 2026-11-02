local addonName, ns = ...

--[[
The catalogue: every knob the addon offers, as data. Nothing here runs.

It was written from the client's own list (/tuner probe on 1.60.1, 1,807 console
variables) and from the ranges in Blizzard_SettingsDefinitions_Shared/Graphics.lua. A knob
whose variable this client does not have, or will not let an addon set, is dropped when
the addon loads, so a row here is an offer, not a promise.

    knob = {
        cvar    the console variable
        label   what the user reads
        group   one of Catalog.GROUPS
        kind    "slider", "toggle" or "choice"
        min, max, step      for a slider, in the variable's own numbers
        choices             for a choice: { { value, label }, ... }
        format  how a slider's value reads: "percent" (a fraction), "percent100", "fps",
                "nits", "level" (a quality level, counted from 1 as the game shows it),
                or nil for the number
        reversed  the variable runs backwards: shown and set as max - value
        experimental  it can crash the game or leave it unable to draw: the client calls
                it a beta feature, or it leans on hardware and driver support that not
                every machine has. Marked wherever the knob is shown
        validated  the client can say which of its values this machine supports
                (IsGraphicsCVarValueSupported). Only the variables the game's own graphics
                page asks about are marked: what the call says of any other is unknown
        settle  a slider that is applied when the thumb is let go, not on every step:
                the change rebuilds the client's render targets
        restart   what a change needs before it shows: "gx", "window" or "client"
        rank    1 and 2 are set before the rest: they are Blizzard's quality levels, and
                the client moves other variables when they change
        raid    it belongs to the client's second set of levels, used inside raids
        help    one sentence
    }

Left out on purpose: the raw RAID* copies of the variables beneath the raid levels,
variables that take text (the graphics API, the adapter, the screenshot format), and the
engine's threading, streaming and debugging variables.
]]

local Catalog = {}
ns.Catalog = Catalog

Catalog.GROUPS = {
    { key = "upscale", label = "Upscaling", note = "Render scale, the upscaling filter and sharpening" },
    { key = "aa", label = "Anti-aliasing", note = "Smoothing of jagged edges" },
    { key = "frame", label = "Latency and frame rate", note = "Input delay, sync and frame rate limits" },
    { key = "colour", label = "Colour", note = "Gamma, brightness and contrast" },
    { key = "hdr", label = "HDR", note = "High dynamic range output" },
    { key = "quality", label = "Quality levels", note = "The levels on the game's own graphics page" },
    { key = "shadow", label = "Shadows", note = "Shadow technique, resolution and range" },
    { key = "light", label = "Lighting and fog", note = "Ambient occlusion, fog, bloom and lights" },
    { key = "ssao", label = "Ambient occlusion tuning", note = "The fine controls of the contact shadows" },
    { key = "texture", label = "Textures", note = "Texture resolution and filtering" },
    { key = "world", label = "View distance and detail", note = "How far things are drawn, and how detailed" },
    { key = "water", label = "Water and weather", note = "Liquids, reflections, rain and snow" },
    { key = "particles", label = "Particles and spells", note = "Spell effects, particles and crowds" },
    { key = "effects", label = "Effects and camera", note = "Field of view, full-screen effects, outlines" },
    { key = "raid", label = "Raid profile", note = "A second set of quality levels the game uses inside raids" },
    { key = "misc", label = "Cursor and screenshots", note = "The pointer and saved screenshots" },
}

-- The upscaling presets. Each sets the render scale; the ones below 100% also switch the
-- resample filter to FSR 1.0. Sharpening is left where the user put it, and so is
-- everything else: these are presets for upscaling, not for overall quality. The lowest
-- is the client's floor and is named for how it looks, not after DLSS's "Ultra
-- Performance", which promised more than a third of the pixels can give.
Catalog.PRESETS = {
    { key = "native", label = "Native", scale = 1 },
    { key = "quality", label = "Quality", scale = 0.67 },
    { key = "balanced", label = "Balanced", scale = 0.58 },
    { key = "performance", label = "Performance", scale = 0.5 },
    { key = "potato", label = "Potato", scale = 0.3334 },
}
Catalog.FSR = 3

-- The overall quality presets: points on the game's own 1 to 10 quality slider. Each
-- sets that level and the levels beneath it, and leaves upscaling alone. `level` is the
-- variable's value, which counts from 0.
Catalog.LEVELS = {
    { key = "low", label = "Low", level = 0 },
    { key = "fair", label = "Fair", level = 2 },
    { key = "good", label = "Good", level = 4 },
    { key = "high", label = "High", level = 6 },
    { key = "ultra", label = "Ultra", level = 9 },
}

local OFF_LOW_MED_HIGH_ULTRA = { { 0, "Off" }, { 1, "Low" }, { 2, "Medium" }, { 3, "High" }, { 4, "Ultra" } }

-- The quality levels, once for the world and once for raids.
local LEVELS = {
    { "ViewDistance", "View distance", 9, "How far the world is drawn." },
    { "EnvironmentDetail", "Environment detail", 9, "How far objects are drawn." },
    { "GroundClutter", "Ground clutter", 9, "Density and distance of grass and small ground detail." },
    { "ShadowQuality", "Shadow quality", 5, "From blob shadows to high-resolution soft shadows." },
    { "LiquidDetail", "Liquid detail", 3, "Water and lava quality." },
    { "PBRLiquidDetail", "Liquid shading", 2, "Physically based water quality." },
    { "ParticleDensity", "Particle density", 5, "How many particles spells and effects use." },
    { "SSAO", "Ambient occlusion", 4, "Contact shadows in corners and creases." },
    { "DepthEffects", "Depth effects", 3, "Effects that read scene depth, such as soft particles." },
    { "ComputeEffects", "Compute effects", 4, "Volumetric fog and other compute-shader effects." },
    { "OutlineMode", "Outline mode", 2, "Outlines on selected and hovered units." },
    { "TextureResolution", "Texture resolution", 2, "World and character texture size." },
    { "SpellDensity", "Spell density", 2, "How many of other players' spell effects are drawn." },
    { "ProjectedTextures", "Projected textures", 1, "Ground effects projected onto terrain." },
    { "LightMode", "Lighting quality", 2, "How many lights are drawn, and how well." },
}

local function Level(prefix, group, row, raid)
    return { cvar = prefix .. row[1], label = row[2], group = group, kind = "slider", min = 0, max = row[3],
        step = 1, format = "level", rank = 2, raid = raid, help = row[4] }
end

Catalog.KNOBS = {
    -- Upscaling
    { cvar = "RenderScale", label = "Render scale", group = "upscale", kind = "slider",
      min = 0.3334, max = 2, step = 0.01, format = "percent", settle = true,
      help = "The size the world is drawn at, as a share of the screen. Below 100% is upscaled, above is supersampled." },
    { cvar = "ResampleQuality", label = "Resample filter", group = "upscale", kind = "choice",
      choices = { { 0, "Point" }, { 1, "Bilinear" }, { 2, "Bicubic" }, { 3, "FSR 1.0" } },
      help = "How the drawn picture is stretched to the screen." },
    { cvar = "ResampleSharpness", label = "Sharpening", group = "upscale", kind = "slider",
      min = 0, max = 2, step = 0.1, reversed = true,
      help = "Strength of the sharpening pass after an FSR upscale. 2 is strongest." },
    { cvar = "ResampleAlwaysSharpen", label = "Sharpen without upscaling", group = "upscale", kind = "toggle",
      help = "Runs the sharpening pass even at 100% render scale." },
    { cvar = "DynamicRenderScale", label = "Dynamic render scale", group = "upscale", kind = "toggle",
      experimental = true,
      help = "Lowers the render scale by itself to hold the target frame rate. The client calls this a beta feature, and it has crashed the 1.60.1 client." },
    { cvar = "DynamicRenderScaleMin", label = "Dynamic floor", group = "upscale", kind = "slider",
      min = 0.3334, max = 1, step = 0.01, format = "percent",
      help = "The lowest render scale the dynamic mode may use." },

    -- Anti-aliasing
    { cvar = "ffxAntiAliasingMode", label = "Image anti-aliasing", group = "aa", kind = "choice",
      choices = { { 0, "None" }, { 1, "FXAA Low" }, { 2, "FXAA High" }, { 3, "CMAA" }, { 4, "CMAA2" } },
      help = "Smooths edges on the finished picture. Cheap, and softens a little." },
    { cvar = "CMAA2Quality", label = "CMAA2 quality", group = "aa", kind = "choice",
      choices = { { 0, "Low" }, { 1, "Medium" }, { 2, "High" }, { 3, "Ultra" } },
      help = "How hard CMAA2 works. Only matters when image anti-aliasing is CMAA2." },
    { cvar = "CMAA2ExtraSharpness", label = "CMAA2 extra sharpness", group = "aa", kind = "toggle",
      help = "Keeps text and fine shapes crisper, with less smoothing." },
    { cvar = "MSAAQuality", label = "Multisample anti-aliasing", group = "aa", kind = "choice",
      choices = { { 0, "None" }, { 1, "2x" }, { 2, "4x" }, { 3, "8x" } },
      help = "Smooths the edges of geometry as it is drawn. Sharper than image anti-aliasing, and costs more." },
    { cvar = "MSAAAlphaTest", label = "Multisample alpha test", group = "aa", kind = "toggle", validated = true,
      help = "Extends multisampling to cut-out textures such as leaves and fences." },

    -- Latency and frame rate
    { cvar = "LowLatencyMode", label = "Low latency mode", group = "frame", kind = "choice", validated = true,
      choices = { { 0, "Auto" }, { 1, "Off" }, { 2, "Built-in" }, { 3, "NVIDIA Reflex" }, { 4, "Reflex + Boost" },
          { 5, "Intel XeLL" } },
      help = "Cuts the delay between input and picture. It does not add frames." },
    { cvar = "vsync", label = "Vertical sync", group = "frame", kind = "toggle", restart = "window",
      help = "Ties frames to the monitor's refresh, removing tearing." },
    { cvar = "GxMaxFrameLatency", label = "Triple buffering", group = "frame", kind = "choice",
      choices = { { 2, "Off" }, { 3, "On" } }, restart = "gx",
      help = "How many frames the CPU may run ahead of the GPU." },
    { cvar = "useMaxFPS", label = "Limit frame rate", group = "frame", kind = "toggle",
      help = "Turns the foreground frame rate limit on." },
    { cvar = "maxFPS", label = "Frame rate limit", group = "frame", kind = "slider",
      min = 8, max = 200, step = 1, format = "fps", help = "The foreground limit." },
    { cvar = "useMaxFPSBk", label = "Limit background frame rate", group = "frame", kind = "toggle",
      help = "Turns the limit on for when the game is not the active window." },
    { cvar = "maxFPSBk", label = "Background limit", group = "frame", kind = "slider",
      min = 8, max = 200, step = 1, format = "fps", help = "The background limit." },
    { cvar = "useTargetFPS", label = "Use a target frame rate", group = "frame", kind = "toggle",
      help = "Lets the client lower detail by itself when the frame rate falls under the target." },
    { cvar = "targetFPS", label = "Target frame rate", group = "frame", kind = "slider",
      min = 8, max = 200, step = 1, format = "fps",
      help = "What the dynamic render scale and the client's own adjustments aim for." },

    -- Colour
    { cvar = "Gamma", label = "Gamma", group = "colour", kind = "slider", min = 0.3, max = 2.8, step = 0.1,
      help = "Gamma correction." },
    { cvar = "Brightness", label = "Brightness", group = "colour", kind = "slider", min = 0, max = 100, step = 1,
      help = "Brightness. 50 is neutral." },
    { cvar = "Contrast", label = "Contrast", group = "colour", kind = "slider", min = 0, max = 100, step = 1,
      help = "Contrast. 50 is neutral." },

    -- HDR
    { cvar = "HDROutput", label = "HDR output", group = "hdr", kind = "toggle", restart = "gx",
      experimental = true,
      help = "Sends an HDR picture when the monitor and the render settings allow it." },
    { cvar = "useHDRBrightness", label = "Override brightness", group = "hdr", kind = "toggle",
      help = "Uses the brightness below in place of the level the monitor reports." },
    { cvar = "HDRBrightness", label = "Brightness", group = "hdr", kind = "slider",
      min = 80, max = 1000, step = 1, format = "nits",
      help = "Brightness of the interface and standard-range content, in nits." },
    { cvar = "useHDRPeakBrightness", label = "Override peak brightness", group = "hdr", kind = "toggle",
      help = "Uses the peak below in place of the one the monitor reports." },
    { cvar = "HDRPeakBrightness", label = "Peak brightness", group = "hdr", kind = "slider",
      min = 200, max = 4000, step = 10, format = "nits",
      help = "The brightest the monitor can show, in nits." },
    { cvar = "HDRFactor", label = "HDR factor", group = "hdr", kind = "slider", min = 1, max = 8, step = 0.1,
      help = "How far above standard range HDR lighting may push. Capped by the peak brightness." },
    { cvar = "RenderFormat", label = "Render format", group = "hdr", kind = "choice", restart = "gx",
      experimental = true,
      choices = { { 0, "8-bit" }, { 1, "10-bit" }, { 2, "16-bit float" }, { 3, "32-bit float" } },
      help = "The precision the world is drawn at. HDR and smooth gradients need 16-bit float; lower saves memory." },

    -- Quality levels: Blizzard's own, set before the variables beneath them.
    { cvar = "graphicsQuality", label = "Overall quality", group = "quality", kind = "slider",
      min = 0, max = 9, step = 1, format = "level", rank = 1,
      help = "The master level on the game's own graphics page. Moving it moves the levels beneath it." },
    Level("graphics", "quality", LEVELS[1]), Level("graphics", "quality", LEVELS[2]),
    Level("graphics", "quality", LEVELS[3]), Level("graphics", "quality", LEVELS[4]),
    Level("graphics", "quality", LEVELS[5]), Level("graphics", "quality", LEVELS[6]),
    Level("graphics", "quality", LEVELS[7]), Level("graphics", "quality", LEVELS[8]),
    Level("graphics", "quality", LEVELS[9]), Level("graphics", "quality", LEVELS[10]),
    Level("graphics", "quality", LEVELS[11]), Level("graphics", "quality", LEVELS[12]),
    Level("graphics", "quality", LEVELS[13]), Level("graphics", "quality", LEVELS[14]),
    Level("graphics", "quality", LEVELS[15]),

    -- Shadows
    { cvar = "shadowMode", label = "Shadow mode", group = "shadow", kind = "slider", min = 0, max = 4, step = 1,
      help = "The shadow technique, from simplest to best." },
    { cvar = "shadowSoft", label = "Soft shadows", group = "shadow", kind = "toggle",
      help = "Blurs shadow edges." },
    { cvar = "shadowTextureSize", label = "Shadow resolution", group = "shadow", kind = "choice",
      choices = { { 1024, "1024" }, { 2048, "2048" } }, help = "The size of the shadow maps." },
    { cvar = "shadowNumCascades", label = "Shadow cascades", group = "shadow", kind = "slider",
      min = 1, max = 4, step = 1, help = "How many distance bands shadows are split into." },
    { cvar = "shadowBlendCascades", label = "Blend cascades", group = "shadow", kind = "toggle",
      help = "Hides the seam between shadow bands." },
    { cvar = "entityShadowFadeScale", label = "Creature shadow range", group = "shadow", kind = "slider",
      min = 10, max = 100, step = 5, help = "How far away creatures and players stop casting shadows." },
    { cvar = "shadowRt", label = "Ray traced shadows", group = "shadow", kind = "choice", experimental = true,
      validated = true,
      choices = { { 0, "Off" }, { 1, "Fair" }, { 2, "Medium" }, { 3, "High" } },
      help = "Ray traced shadows, where the graphics card supports them." },

    -- Lighting and fog
    { cvar = "SSAO", label = "Ambient occlusion", group = "light", kind = "choice",
      choices = OFF_LOW_MED_HIGH_ULTRA, help = "Contact shadows in corners and creases." },
    { cvar = "sunShafts", label = "Sun shafts", group = "light", kind = "choice",
      choices = { { 0, "Off" }, { 1, "Low" }, { 2, "High" } }, help = "Light rays around the sun." },
    { cvar = "volumeFog", label = "Volumetric fog", group = "light", kind = "toggle",
      help = "Fog that takes light and shadow." },
    { cvar = "volumeFogLevel", label = "Volumetric fog quality", group = "light", kind = "slider",
      min = 0, max = 4, step = 1, help = "Resolution of the volumetric fog." },
    { cvar = "volumeFogInterior", label = "Volumetric fog indoors", group = "light", kind = "toggle",
      help = "Volumetric fog inside buildings and caves." },
    { cvar = "bloomEnable", label = "Bloom", group = "light", kind = "toggle",
      help = "Glow around bright areas." },
    { cvar = "bloomUserMult", label = "Bloom strength", group = "light", kind = "slider",
      min = 0, max = 2, step = 0.1, help = "Multiplier on the bloom." },
    { cvar = "specular", label = "Specular lighting", group = "light", kind = "slider",
      min = 0, max = 1, step = 0.05, help = "Strength of specular highlights." },
    { cvar = "maxLightDist", label = "Light distance", group = "light", kind = "slider",
      min = 256, max = 4096, step = 64, help = "The farthest a light is drawn from." },
    { cvar = "clusteredShading", label = "Lit transparent surfaces", group = "light", kind = "toggle",
      help = "Lets lights fall on glass, water and other see-through surfaces." },

    -- Ambient occlusion tuning: the ASSAO shader's own controls, ranges from its help text.
    { cvar = "assaoRadius", label = "Radius", group = "ssao", kind = "slider", min = 0.1, max = 10, step = 0.05,
      help = "The size of the area each point looks at for occluders. Larger gives broader, softer shading." },
    { cvar = "assaoShadowMult", label = "Strength", group = "ssao", kind = "slider", min = 0, max = 5, step = 0.1,
      help = "A straight multiplier on the darkening." },
    { cvar = "assaoShadowPower", label = "Contrast", group = "ssao", kind = "slider", min = 0.5, max = 5, step = 0.02,
      help = "Raises the darkening to a power: higher deepens the darkest creases." },
    { cvar = "assaoShadowClamp", label = "Darkest allowed", group = "ssao", kind = "slider",
      min = 0, max = 1, step = 0.01, help = "The cap on how dark the effect may make a point." },
    { cvar = "assaoDetailShadowStrength", label = "Fine detail", group = "ssao", kind = "slider",
      min = 0, max = 5, step = 0.1,
      help = "Adds small-scale shading from neighbouring pixels. More detail, and more shimmer in motion." },
    { cvar = "assaoSharpness", label = "Edge sharpness", group = "ssao", kind = "slider",
      min = 0, max = 1, step = 0.01, help = "How strictly the blur keeps to edges. 1 does not bleed across them at all." },
    { cvar = "assaoBlurPassCount", label = "Blur passes", group = "ssao", kind = "slider",
      min = 0, max = 6, step = 1, help = "How many smoothing passes run over the result." },
    { cvar = "assaoHorizonAngleThresh", label = "Self-shadow limit", group = "ssao", kind = "slider",
      min = 0, max = 0.5, step = 0.01, help = "Stops flat surfaces from shading themselves." },
    { cvar = "assaoFadeOutFrom", label = "Fade starts at", group = "ssao", kind = "slider",
      min = 0, max = 300, step = 5, help = "The distance at which the effect begins to fade." },
    { cvar = "assaoFadeOutTo", label = "Fade ends at", group = "ssao", kind = "slider",
      min = 0, max = 1000, step = 10, help = "The distance at which the effect is gone." },
    { cvar = "assaoAdaptiveQualityLimit", label = "Adaptive quality limit", group = "ssao", kind = "slider",
      min = 0, max = 1, step = 0.05, help = "How much extra sampling the highest ambient occlusion level may spend." },
    { cvar = "assaoNormals", label = "Use surface normals", group = "ssao", kind = "toggle",
      help = "Uses the direction surfaces face, for more accurate shading." },
    { cvar = "ssaoMagicNormals", label = "Blend normal sources", group = "ssao", kind = "toggle",
      help = "Mixes two sources of surface direction, as a compromise between buildings, foliage and characters." },

    -- Textures
    { cvar = "textureFilteringMode", label = "Texture filtering", group = "texture", kind = "choice",
      validated = true,
      choices = { { 0, "Bilinear" }, { 1, "Trilinear" }, { 2, "2x anisotropic" }, { 3, "4x anisotropic" },
          { 4, "8x anisotropic" }, { 5, "16x anisotropic" } },
      help = "How textures are sharpened at a slant." },
    { cvar = "worldBaseMip", label = "World texture reduction", group = "texture", kind = "slider",
      min = 0, max = 2, step = 1, help = "Halves world texture resolution for each step. 0 is full detail." },
    { cvar = "terrainMipLevel", label = "Terrain texture reduction", group = "texture", kind = "slider",
      min = 0, max = 1, step = 1, help = "Lowers the resolution of terrain blending. 0 is full detail." },
    { cvar = "componentTextureLevel", label = "Character texture reduction", group = "texture", kind = "slider",
      min = 0, max = 2, step = 1, help = "Halves character texture resolution for each step. 0 is full detail." },
    { cvar = "useHighResTextures", label = "Prefer upscaled textures", group = "texture", kind = "toggle",
      help = "Uses the higher-resolution versions of textures where the game has them." },

    -- View distance and detail
    { cvar = "farclip", label = "Far clip", group = "world", kind = "slider", min = 500, max = 10000, step = 100,
      help = "The farthest distance anything is drawn at." },
    { cvar = "horizonStart", label = "Fog start", group = "world", kind = "slider", min = 400, max = 4000, step = 100,
      help = "Where distance fog begins." },
    { cvar = "horizonClip", label = "Horizon clip", group = "world", kind = "slider",
      min = 1000, max = 10000, step = 100, help = "How far the simplified horizon terrain is drawn." },
    { cvar = "terrainLodDist", label = "Terrain detail distance", group = "world", kind = "slider",
      min = 200, max = 650, step = 10, help = "How far terrain keeps its full detail." },
    { cvar = "wmoLodDist", label = "Building detail distance", group = "world", kind = "slider",
      min = 100, max = 650, step = 10, help = "How far buildings keep their full detail." },
    { cvar = "wmoDoodadDist", label = "Building props distance", group = "world", kind = "slider",
      min = 500, max = 2000, step = 100, help = "How far away the props inside and on buildings are loaded." },
    { cvar = "doodadLodScale", label = "Object detail scale", group = "world", kind = "slider",
      min = 50, max = 200, step = 5, help = "How far trees, rocks and props keep their full detail." },
    { cvar = "entityLodDist", label = "Creature detail distance", group = "world", kind = "slider",
      min = 5, max = 30, step = 1, help = "How far creatures and players keep their full detail." },
    { cvar = "lodObjectCullSize", label = "Small object culling", group = "world", kind = "slider",
      min = 10, max = 40, step = 1, help = "Objects smaller than this on screen are not drawn. Lower draws more." },
    { cvar = "lodObjectCullDist", label = "Culling starts at", group = "world", kind = "slider",
      min = 10, max = 100, step = 5, help = "The nearest distance at which small objects may be dropped." },
    { cvar = "lodObjectMinSize", label = "Smallest object kept", group = "world", kind = "slider",
      min = 0, max = 40, step = 1, help = "The size under which an object is always dropped at range." },
    { cvar = "lodObjectFadeScale", label = "Object fade scale", group = "world", kind = "slider",
      min = 50, max = 200, step = 5, help = "How far away objects fade out." },
    { cvar = "groundEffectFade", label = "Ground clutter fade", group = "world", kind = "slider",
      min = 30, max = 500, step = 10, help = "How far away grass fades out." },

    -- Water and weather
    { cvar = "waterDetail", label = "Water detail", group = "water", kind = "slider",
      min = 0, max = 3, step = 1, help = "Water surface quality." },
    { cvar = "pbrLiquidDetail", label = "Water shading", group = "water", kind = "slider",
      min = 0, max = 2, step = 1, help = "Physically based water quality." },
    { cvar = "rippleDetail", label = "Ripple detail", group = "water", kind = "slider",
      min = 0, max = 2, step = 1, help = "Ripples on water surfaces." },
    { cvar = "reflectionMode", label = "Reflections", group = "water", kind = "slider",
      min = 0, max = 3, step = 1, help = "What water reflects, from nothing to everything." },
    { cvar = "reflectionDownscale", label = "Reflection reduction", group = "water", kind = "slider",
      min = 0, max = 2, step = 1, help = "Halves the resolution of reflections for each step. 0 is full detail." },
    { cvar = "weatherDensity", label = "Weather density", group = "water", kind = "slider",
      min = 0, max = 3, step = 1, help = "How heavy rain, snow and sandstorms are." },

    -- Particles and spells
    { cvar = "particleDensity", label = "Particle density", group = "particles", kind = "slider",
      min = 10, max = 100, step = 5, format = "percent100", help = "Share of particles drawn." },
    { cvar = "particleMTDensity", label = "Layered particle density", group = "particles", kind = "slider",
      min = 10, max = 100, step = 5, format = "percent100", help = "Share of multi-textured particles drawn." },
    { cvar = "particulatesEnabled", label = "Particulates", group = "particles", kind = "toggle",
      help = "Dust and motes drifting in the air." },
    { cvar = "showfootprintparticles", label = "Footprint puffs", group = "particles", kind = "toggle",
      help = "The puffs of dust and snow kicked up by feet." },
    { cvar = "spellClutter", label = "Spell clutter", group = "particles", kind = "slider",
      min = 0, max = 4, step = 1, help = "How many of other players' spell effects are drawn." },
    { cvar = "projectedTextures", label = "Projected textures", group = "particles", kind = "toggle",
      help = "Ground effects projected onto terrain." },
    { cvar = "DepthBasedOpacity", label = "Soft edges", group = "particles", kind = "toggle",
      help = "Fades particles and water where they meet solid surfaces." },
    { cvar = "unitClutter", label = "Thin out crowds", group = "particles", kind = "toggle",
      help = "Draws fewer of other players' effects when many players are close." },
    { cvar = "unitClutterInstancesOnly", label = "Only in instances", group = "particles", kind = "toggle",
      help = "Thins crowds out only inside dungeons and raids." },
    { cvar = "unitClutterPlayerThreshold", label = "Crowd size", group = "particles", kind = "slider",
      min = 1, max = 40, step = 1, help = "How many players must be near before crowds are thinned out." },

    -- Effects and camera
    { cvar = "cameraFov", label = "Field of view", group = "effects", kind = "slider", min = 50, max = 90, step = 5,
      help = "The camera's field of view, in degrees." },
    { cvar = "ffxGlow", label = "Full-screen glow", group = "effects", kind = "toggle",
      help = "The soft glow over the whole picture." },
    { cvar = "ffxDeath", label = "Death effect", group = "effects", kind = "toggle",
      help = "The grey wash while dead." },
    { cvar = "ffxNether", label = "Nether effect", group = "effects", kind = "toggle",
      help = "The full-screen effect in the nether." },
    { cvar = "OutlineEngineMode", label = "Outlines", group = "effects", kind = "choice",
      choices = { { 0, "Off" }, { 1, "Medium" }, { 2, "High" } }, help = "Outlines on selected and hovered units." },
    { cvar = "vrsValar", label = "Variable rate shading", group = "effects", kind = "choice",
      experimental = true, validated = true,
      choices = { { 0, "Off" }, { 1, "Standard" }, { 2, "Aggressive" } },
      help = "Shades flat parts of the picture at lower detail to save GPU time." },
    { cvar = "vrsValarAlwaysOn", label = "VRS always on", group = "effects", kind = "toggle", experimental = true,
      help = "Uses variable rate shading even when the GPU is not the limit." },
    { cvar = "physicsLevel", label = "Physics interaction", group = "effects", kind = "choice",
      choices = { { 0, "None" }, { 1, "Player only" }, { 2, "Player and NPCs" } }, restart = "client",
      help = "Which characters move cloth and foliage." },

    -- Raid profile: the same levels again, used inside raids when the switch is on.
    { cvar = "RAIDsettingsEnabled", label = "Use raid levels in raids", group = "raid", kind = "toggle",
      help = "Switches to the levels below inside raids, and back outside them." },
    { cvar = "RAIDgraphicsQuality", label = "Overall quality", group = "raid", kind = "slider",
      min = 0, max = 9, step = 1, format = "level", rank = 1, raid = true,
      help = "The master level for raids. Moving it moves the raid levels beneath it." },
    Level("raidGraphics", "raid", LEVELS[1], true), Level("raidGraphics", "raid", LEVELS[2], true),
    Level("raidGraphics", "raid", LEVELS[3], true), Level("raidGraphics", "raid", LEVELS[4], true),
    Level("raidGraphics", "raid", LEVELS[5], true), Level("raidGraphics", "raid", LEVELS[6], true),
    Level("raidGraphics", "raid", LEVELS[7], true), Level("raidGraphics", "raid", LEVELS[8], true),
    Level("raidGraphics", "raid", LEVELS[9], true), Level("raidGraphics", "raid", LEVELS[10], true),
    Level("raidGraphics", "raid", LEVELS[11], true), Level("raidGraphics", "raid", LEVELS[12], true),
    Level("raidGraphics", "raid", LEVELS[13], true), Level("raidGraphics", "raid", LEVELS[14], true),
    Level("raidGraphics", "raid", LEVELS[15], true),

    -- Cursor and screenshots
    { cvar = "HardwareCursor", label = "Hardware cursor", group = "misc", kind = "toggle",
      help = "Lets the system draw the pointer. Off draws it in the game, which lags a little and shows in screenshots." },
    { cvar = "cursorSizePreferred", label = "Cursor size", group = "misc", kind = "choice",
      choices = { { -1, "Automatic" }, { 0, "32" }, { 1, "48" }, { 2, "64" }, { 3, "96" }, { 4, "128" } },
      help = "The size of the pointer, in pixels." },
    { cvar = "screenshotQuality", label = "Screenshot quality", group = "misc", kind = "slider",
      min = 1, max = 10, step = 1, help = "The quality of saved screenshots." },
}
