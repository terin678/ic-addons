local addonName, ns = ...

--[[
The only file that reads or sets a console variable. Everything it decides, it asks the
model; everything the model needs from the client comes through here.

    Apply.Knobs()        -> the catalogue's knobs this client has and lets an addon set
    Apply.Limits()       -> { min, max } for the render scale
    Apply.Live()         -> { [cvar] = number } as the client has them now
    Apply.Defaults()     -> the same, for the client's defaults
    Apply.Run(plan)      -> how many were set, and the names of those that were refused
    Apply.Restart(need)  restarts what a change needs, where an addon can
]]

local Env = LibStub("LibICEnv-1.0")

local Catalog = ns.Catalog
local Model = ns.Model

local Apply = {}
ns.Apply = Apply

local knobs, limits

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

-- True when something was restarted. A change that needs the whole game restarted is
-- beyond an addon.
function Apply.Restart(need)
    if need == "gx" then
        RestartGx()
        return true
    elseif need == "window" then
        UpdateWindow()
        return true
    end
    return false
end
