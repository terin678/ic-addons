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
        min, max, step      for a slider
        choices             for a choice: { { value, label }, ... }
        format  how a slider's value reads: "percent" (a fraction), "percent100", "fps", "nits", or nil for the number
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
        help    one sentence
    }

Left out on purpose: the RAID* copies of these variables (the client's second profile for
raids), variables that take text (the graphics API, the adapter), and the engine's
threading, streaming and debugging variables.
]]

local Catalog = {}
ns.Catalog = Catalog

Catalog.GROUPS = {
    { key = "upscale", label = "Upscaling" },
    { key = "aa", label = "Anti-aliasing" },
    { key = "frame", label = "Latency and frame rate" },
    { key = "colour", label = "Colour" },
    { key = "hdr", label = "HDR" },
    { key = "quality", label = "Quality levels" },
    { key = "shadow", label = "Shadows and lighting" },
    { key = "world", label = "World detail" },
    { key = "effects", label = "Effects" },
}

-- The upscaling presets. Each sets the render scale; the ones below 100% also switch the
-- resample filter to FSR 1.0. Sharpening is left where the user put it, and so is
-- everything else: these are presets for upscaling, not for overall quality. The lowest
-- is the client's floor and is named for how it looks, not after DLSS's "Ultra
-- Performance", which promised more than a third of the pixels can give. `short` is
-- the name on a button too narrow for the label.
Catalog.PRESETS = {
    { key = "native", label = "Native", scale = 1 },
    { key = "quality", label = "Quality", scale = 0.67 },
    { key = "balanced", label = "Balanced", scale = 0.58 },
    { key = "performance", label = "Performance", scale = 0.5 },
    { key = "potato", label = "Potato", scale = 0.3334 },
}
Catalog.FSR = 3

local OFF_LOW_MED_HIGH_ULTRA = { { 0, "Off" }, { 1, "Low" }, { 2, "Medium" }, { 3, "High" }, { 4, "Ultra" } }

local function Level(cvar, label, max, help)
    return { cvar = cvar, label = label, group = "quality", kind = "slider", min = 0, max = max, step = 1,
        rank = 2, help = help }
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

    -- Quality levels: Blizzard's own, set before the variables beneath them.
    { cvar = "graphicsQuality", label = "Overall quality", group = "quality", kind = "slider",
      min = 0, max = 9, step = 1, rank = 1, help = "The master level in the game's own graphics page, shown there as 1 to 10." },
    Level("graphicsViewDistance", "View distance", 9, "How far the world is drawn."),
    Level("graphicsEnvironmentDetail", "Environment detail", 9, "How far objects are drawn."),
    Level("graphicsGroundClutter", "Ground clutter", 9, "Density and distance of grass and small ground detail."),
    Level("graphicsShadowQuality", "Shadow quality", 5, "From blob shadows to high-resolution soft shadows."),
    Level("graphicsLiquidDetail", "Liquid detail", 3, "Water and lava quality."),
    Level("graphicsPBRLiquidDetail", "Liquid shading", 2, "Physically based water quality."),
    Level("graphicsParticleDensity", "Particle density", 5, "How many particles spells and effects use."),
    Level("graphicsSSAO", "Ambient occlusion", 4, "Contact shadows in corners and creases."),
    Level("graphicsDepthEffects", "Depth effects", 3, "Effects that read scene depth, such as soft particles."),
    Level("graphicsComputeEffects", "Compute effects", 4, "Volumetric fog and other compute-shader effects."),
    Level("graphicsOutlineMode", "Outline mode", 2, "Outlines on selected and hovered units."),
    Level("graphicsTextureResolution", "Texture resolution", 2, "World and character texture size."),
    Level("graphicsSpellDensity", "Spell density", 2, "How many of other players' spell effects are drawn."),
    Level("graphicsProjectedTextures", "Projected textures", 1, "Ground effects projected onto terrain."),
    Level("graphicsLightMode", "Lighting quality", 2, "How many lights are drawn, and how well."),

    -- Shadows and lighting
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
    { cvar = "shadowRt", label = "Ray traced shadows", group = "shadow", kind = "choice", experimental = true,
      validated = true,
      choices = { { 0, "Off" }, { 1, "Fair" }, { 2, "Medium" }, { 3, "High" } },
      help = "Ray traced shadows, where the graphics card supports them." },
    { cvar = "SSAO", label = "Ambient occlusion", group = "shadow", kind = "choice",
      choices = OFF_LOW_MED_HIGH_ULTRA, help = "Contact shadows in corners and creases." },
    { cvar = "sunShafts", label = "Sun shafts", group = "shadow", kind = "choice",
      choices = { { 0, "Off" }, { 1, "Low" }, { 2, "High" } }, help = "Light rays around the sun." },
    { cvar = "volumeFog", label = "Volumetric fog", group = "shadow", kind = "toggle",
      help = "Fog that takes light and shadow." },
    { cvar = "volumeFogLevel", label = "Volumetric fog quality", group = "shadow", kind = "slider",
      min = 0, max = 4, step = 1, help = "Resolution of the volumetric fog." },
    { cvar = "volumeFogInterior", label = "Volumetric fog indoors", group = "shadow", kind = "toggle",
      help = "Volumetric fog inside buildings and caves." },
    { cvar = "bloomEnable", label = "Bloom", group = "shadow", kind = "toggle",
      help = "Glow around bright areas." },
    { cvar = "bloomUserMult", label = "Bloom strength", group = "shadow", kind = "slider",
      min = 0, max = 2, step = 0.1, help = "Multiplier on the bloom." },
    { cvar = "specular", label = "Specular lighting", group = "shadow", kind = "slider",
      min = 0, max = 1, step = 0.05, help = "Strength of specular highlights." },
    { cvar = "reflectionMode", label = "Reflections", group = "shadow", kind = "slider",
      min = 0, max = 3, step = 1, help = "What water reflects, from nothing to everything." },

    -- World detail
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
    { cvar = "doodadLodScale", label = "Object detail scale", group = "world", kind = "slider",
      min = 50, max = 200, step = 5, help = "How far trees, rocks and props keep their full detail." },
    { cvar = "entityLodDist", label = "Creature detail distance", group = "world", kind = "slider",
      min = 5, max = 30, step = 1, help = "How far creatures and players keep their full detail." },
    { cvar = "lodObjectCullSize", label = "Small object culling", group = "world", kind = "slider",
      min = 10, max = 40, step = 1, help = "Objects smaller than this on screen are not drawn. Lower draws more." },
    { cvar = "lodObjectFadeScale", label = "Object fade scale", group = "world", kind = "slider",
      min = 50, max = 200, step = 5, help = "How far away objects fade out." },
    { cvar = "groundEffectFade", label = "Ground clutter fade", group = "world", kind = "slider",
      min = 30, max = 500, step = 10, help = "How far away grass fades out." },
    { cvar = "weatherDensity", label = "Weather density", group = "world", kind = "slider",
      min = 0, max = 3, step = 1, help = "How heavy rain, snow and sandstorms are." },
    { cvar = "particleDensity", label = "Particle density", group = "world", kind = "slider",
      min = 10, max = 100, step = 5, format = "percent100", help = "Share of particles drawn." },
    { cvar = "waterDetail", label = "Water detail", group = "world", kind = "slider",
      min = 0, max = 3, step = 1, help = "Water surface quality." },
    { cvar = "pbrLiquidDetail", label = "Water shading", group = "world", kind = "slider",
      min = 0, max = 2, step = 1, help = "Physically based water quality." },
    { cvar = "rippleDetail", label = "Ripple detail", group = "world", kind = "slider",
      min = 0, max = 2, step = 1, help = "Ripples on water surfaces." },
    { cvar = "textureFilteringMode", label = "Texture filtering", group = "world", kind = "choice",
      validated = true,
      choices = { { 0, "Bilinear" }, { 1, "Trilinear" }, { 2, "2x anisotropic" }, { 3, "4x anisotropic" },
          { 4, "8x anisotropic" }, { 5, "16x anisotropic" } },
      help = "How textures are sharpened at a slant." },
    { cvar = "projectedTextures", label = "Projected textures", group = "world", kind = "toggle",
      help = "Ground effects projected onto terrain." },
    { cvar = "DepthBasedOpacity", label = "Soft edges", group = "world", kind = "toggle",
      help = "Fades particles and water where they meet solid surfaces." },
    { cvar = "particulatesEnabled", label = "Particulates", group = "world", kind = "toggle",
      help = "Dust and motes drifting in the air." },
    { cvar = "OutlineEngineMode", label = "Outlines", group = "world", kind = "choice",
      choices = { { 0, "Off" }, { 1, "Medium" }, { 2, "High" } }, help = "Outlines on selected and hovered units." },
    { cvar = "spellClutter", label = "Spell clutter", group = "world", kind = "slider",
      min = 0, max = 4, step = 1, help = "How many of other players' spell effects are drawn." },

    -- Effects
    { cvar = "cameraFov", label = "Field of view", group = "effects", kind = "slider", min = 50, max = 90, step = 5,
      help = "The camera's field of view, in degrees." },
    { cvar = "ffxGlow", label = "Full-screen glow", group = "effects", kind = "toggle",
      help = "The soft glow over the whole picture." },
    { cvar = "ffxDeath", label = "Death effect", group = "effects", kind = "toggle",
      help = "The grey wash while dead." },
    { cvar = "ffxNether", label = "Nether effect", group = "effects", kind = "toggle",
      help = "The full-screen effect in the nether." },
    { cvar = "vrsValar", label = "Variable rate shading", group = "effects", kind = "choice",
      experimental = true, validated = true,
      choices = { { 0, "Off" }, { 1, "Standard" }, { 2, "Aggressive" } },
      help = "Shades flat parts of the picture at lower detail to save GPU time." },
    { cvar = "vrsValarAlwaysOn", label = "VRS always on", group = "effects", kind = "toggle", experimental = true,
      help = "Uses variable rate shading even when the GPU is not the limit." },
    { cvar = "physicsLevel", label = "Physics interaction", group = "effects", kind = "choice",
      choices = { { 0, "None" }, { 1, "Player only" }, { 2, "Player and NPCs" } }, restart = "client",
      help = "Which characters move cloth and foliage." },
}
