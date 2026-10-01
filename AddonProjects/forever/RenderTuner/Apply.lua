local addonName, ns = ...

--[[
The only file that reads or sets a console variable. Everything it decides, it asks the
model; everything the model needs from the client comes through here.

    Apply.Knobs()        -> the catalogue's knobs this client has and lets an addon set
    Apply.Limits()       -> { min, max } for the render scale
    Apply.Live()         -> { [cvar] = number } as the client has them now
    Apply.Defaults()     -> the same, for the client's defaults
    Apply.Run(plan)      -> how many were set, and the names of those that were refused
    Apply.Unsupported(cvar, value) -> why this client will not take that value, or nil
    Apply.LevelValues(level) -> what the overall quality level sets each level beneath it to
    Apply.Restart(need)  restarts what a change needs, where an addon can
]]

local Env = LibStub("LibICEnv-1.0")

local Catalog = ns.Catalog
local Model = ns.Model

local Apply = {}
ns.Apply = Apply

local knobs, limits

-- The messages IsGraphicsCVarValueSupported answers with, by number, in the order the
-- game's own graphics page lists them (Blizzard_SettingsDefinitions_Shared/Graphics.lua).
-- Each is the name of a global string.
local REASONS = {
    "VRN_ILLEGAL", "VRN_UNSUPPORTED", "VRN_GRAPHICS", "VRN_DUALCORE", "VRN_QUADCORE", "VRN_CPUMEM_2GB",
    "VRN_CPUMEM_4GB", "VRN_CPUMEM_8GB", "VRN_NEEDS_5_0", "VRN_NEEDS_6_0", "VRN_NEEDS_RT", "VRN_NEEDS_DX12",
    "VRN_NEEDS_DX12_VRS2", "VRN_NEEDS_APPLE_GPU", "VRN_NEEDS_AMD_GPU", "VRN_NEEDS_INTEL_GPU",
    "VRN_NEEDS_NVIDIA_GPU", "VRN_NEEDS_QUALCOMM_GPU", "VRN_NEEDS_MACOS_10_13", "VRN_NEEDS_MACOS_10_14",
    "VRN_NEEDS_MACOS_10_15", "VRN_NEEDS_MACOS_11_0", "VRN_NEEDS_MACOS_12_0", "VRN_NEEDS_MACOS_13_0",
    "VRN_NEEDS_WINDOWS_10", "VRN_NEEDS_WINDOWS_11", "VRN_MACOS_UNSUPPORTED", "VRN_WINDOWS_UNSUPPORTED",
    "VRN_LEGACY_UNSUPPORTED", "VRN_DX11_UNSUPPORTED", "VRN_DX12_WIN7_UNSUPPORTED",
    "VRN_REMOTE_DESKTOP_UNSUPPORTED", "VRN_WINE_UNSUPPORTED", "VRN_NVAPI_WINE_UNSUPPORTED",
    "VRN_APPLE_UNSUPPORTED", "VRN_AMD_UNSUPPORTED", "VRN_INTEL_UNSUPPORTED", "VRN_NVIDIA_UNSUPPORTED",
    "VRN_QUALCOMM_UNSUPPORTED", "VRN_GPU_DRIVER", "VRN_COMPAT_MODE",
}
local FALLBACK_REASON = "This client does not allow it at the moment."

-- The variables the check may be asked about: the catalogue's `validated` knobs.
local validated

-- "cvar=value" -> a reason, or false for a value that is fine. Kept until the graphics
-- engine restarts, since what is supported hangs on the card, the driver and the API.
local support = {}

local function Settable(cvar)
    local try = Env.Try(cvar, C_CVar.GetCVarInfo, cvar)
    if not try.ok or try.n == 0 or try.values[1] == nil then return false end
    local v = try.values
    -- locked from the user, secure, or read-only
    return not (v[5] == true or v[6] == true or v[7] == true)
end

function Apply.Limits()
    if not limits then
        local try = Env.Try("render scale", function() return GetMinRenderScale(), GetMaxRenderScale() end)
        limits = try.ok and Model.Limits(try.values[1], try.values[2]) or Model.Limits(nil, nil)
    end
    return limits
end

-- Built once, the first time it is asked for after login. Ranges that the client knows
-- better than the catalogue are taken from the client.
function Apply.Knobs()
    if knobs then return knobs end
    knobs = {}
    local scale = Apply.Limits()
    local fov = Env.Try("fov", function() return GetCameraFOVDefaults() end)
    for _, knob in ipairs(Catalog.KNOBS) do
        if Settable(knob.cvar) then
            local copy = {}
            for key, value in pairs(knob) do copy[key] = value end
            if knob.cvar == "RenderScale" then
                copy.min, copy.max = scale.min, scale.max
            elseif knob.cvar == "DynamicRenderScaleMin" then
                copy.min = scale.min
            elseif knob.cvar == "cameraFov" and fov.ok and tonumber(fov.values[2]) and tonumber(fov.values[3]) then
                copy.min, copy.max = tonumber(fov.values[2]), tonumber(fov.values[3])
            end
            knobs[#knobs + 1] = copy
        end
    end
    return knobs
end

function Apply.Get(cvar)
    return C_CVar.GetCVar(cvar)
end

function Apply.Live()
    return Model.Snapshot(Apply.Knobs(), Apply.Get)
end

function Apply.Defaults()
    return Model.Snapshot(Apply.Knobs(), function(cvar) return C_CVar.GetCVarDefault(cvar) end)
end

function Apply.Run(plan)
    local done, refused = 0, {}
    for _, step in ipairs(plan) do
        local try = Env.Try(step.cvar, C_CVar.SetCVar, step.cvar, step.value)
        if try.ok and try.values[1] ~= false then
            done = done + 1
        else
            refused[#refused + 1] = step.cvar
        end
    end
    return done, refused
end

-- Why this client will not take `value` for `cvar`, in the client's own words, or nil
-- when it will. This is the check the game's graphics page greys its options out with.
function Apply.Unsupported(cvar, value)
    if not validated then
        validated = {}
        for _, knob in ipairs(Catalog.KNOBS) do
            if knob.validated then validated[knob.cvar] = true end
        end
    end
    if not validated[cvar] then return nil end
    local key = cvar .. "=" .. tostring(value)
    if support[key] == nil then
        local reason = false
        if type(IsGraphicsCVarValueSupported) == "function" then
            local try = Env.Try(key, IsGraphicsCVarValueSupported, cvar, value)
            local code = try.ok and tonumber(try.values[1]) or 0
            if code ~= 0 then
                local text = REASONS[code] and _G[REASONS[code]]
                reason = type(text) == "string" and text ~= "" and text or FALLBACK_REASON
            end
        end
        support[key] = reason
    end
    return support[key] or nil
end

function Apply.ForgetSupport()
    support = {}
end

-- The client does not move the other quality levels when the overall one changes; the
-- game's graphics page does it in Lua, by asking the client what each level should be.
-- This asks the same question for every level in the catalogue.
function Apply.LevelValues(level)
    local values = {}
    if type(GetGraphicsCVarValueForQualityLevel) ~= "function" then return values end
    for _, knob in ipairs(Apply.Knobs()) do
        if knob.rank == 2 then
            local try = Env.Try(knob.cvar, GetGraphicsCVarValueForQualityLevel, knob.cvar, level, false)
            local value = try.ok and tonumber(try.values[1]) or nil
            if value then values[knob.cvar] = value end
        end
    end
    return values
end

-- True when something was restarted. A change that needs the whole game restarted is
-- beyond an addon.
function Apply.Restart(need)
    Apply.ForgetSupport()
    if need == "gx" then
        RestartGx()
        return true
    elseif need == "window" then
        UpdateWindow()
        return true
    end
    return false
end
