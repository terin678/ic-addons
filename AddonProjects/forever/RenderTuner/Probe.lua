local addonName, ns = ...

--[[
The probe: what /tuner probe and /tuner capture ask this client.

Two questions decide what the addon can be, and neither is answered by the exported
interface source:

    which console variables exist      the catalogue of knobs is built from this list, not
                                       from what another client had
    can an addon capture the screen    a split view needs a still of the saved settings to
    into a texture                     set beside the live picture; two calls might give one

The answers are saved to RenderTunerDB.probe and RenderTunerDB.capture, where they can be
read off disk after a /reload.

    Probe.Rows(commands, info)      -> rows      pure
    Probe.Summary(report)           -> lines     pure
    Probe.CaptureLines(capture)     -> lines     pure
    Probe.Run()                     -> report    asks the client
    Probe.Capture(route, log, say)               asks the client, shows the picture
    Probe.CaptureView(mode), Probe.CaptureClear()
]]

local Util = LibStub("LibICUtil-1.0")
local Env = LibStub("LibICEnv-1.0")

local Probe = {}
ns.Probe = Probe

-- Enum.ConsoleCommandType.Cvar and Enum.ConsoleCategory, as the exported source has them.
local TYPE_CVAR = 0
Probe.CATEGORIES = {
    [0] = "Debug", [1] = "Graphics", [2] = "Console", [3] = "Combat", [4] = "Game", [5] = "Default",
    [6] = "Net", [7] = "Sound", [8] = "Gm", [9] = "Reveal", [10] = "None",
}

Probe.CHECKS = {
    { "ConsoleGetAllCommands", "listing console variables" },
    { "C_Console.GetAllCommands", "listing console variables, namespaced" },
    { "C_CVar.GetCVarInfo", "a variable's value, default and locks" },
    { "C_CVar.GetCVarDefault", "a variable's default" },
    { "C_CVar.SetCVar", "setting a variable" },
    { "GetMinRenderScale", "the render scale's floor" },
    { "GetMaxRenderScale", "the render scale's ceiling" },
    { "AntiAliasingSupported", "which image anti-aliasing modes work" },
    { "MultiSampleAntiAliasingSupported", "which multisample modes work" },
    { "GetCurrentGraphicsAPI", "the graphics API in use" },
    { "RestartGx", "restarting the graphics engine" },
    { "Screenshot", "a screenshot to disk" },
    { "C_ReportSystem.TakeReportScreenshot", "capture, the report way" },
    { "C_ReportSystem.SetScreenshotPreviewTexture", "capture, the report way" },
    { "C_PhotoSharing.TakePhoto", "capture, the photo way" },
    { "C_PhotoSharing.SetScreenshotPreviewTexture", "capture, the photo way" },
    { "C_PhotoSharing.IsEnabled", "capture, the photo way" },
    { "C_PhotoSharing.GetCropRatio", "capture, the photo way" },
    { "PhotoSharingFrame", "Blizzard's own photo preview" },
    { "ReportFrame", "Blizzard's own report window" },
    { "Settings.RegisterVerticalLayoutCategory", "an options page" },
    { "Settings.RegisterVerticalLayoutSubcategory", "an options page" },
    { "Settings.RegisterProxySetting", "an options page" },
    { "Settings.RegisterAddOnCategory", "an options page" },
    { "Settings.CreateSlider", "an options page" },
    { "Settings.CreateCheckbox", "an options page" },
    { "Settings.CreateDropdown", "an options page" },
    { "Settings.CreateSliderOptions", "an options page" },
    { "Settings.CreateControlTextContainer", "an options page" },
    { "MinimalSliderWithSteppersMixin", "sliders" },
}

Probe.VALUES = {
    { "GetMinRenderScale", function() return GetMinRenderScale() end },
    { "GetMaxRenderScale", function() return GetMaxRenderScale() end },
    { "AntiAliasingSupported", function() return AntiAliasingSupported() end },
    { "MultiSampleAntiAliasingSupported", function() return MultiSampleAntiAliasingSupported() end },
    { "GetCurrentGraphicsAPI", function() return GetCurrentGraphicsAPI() end },
    { "GetPhysicalScreenSize", function() return GetPhysicalScreenSize() end },
    { "C_PhotoSharing.IsEnabled", function() return C_PhotoSharing.IsEnabled() end },
    { "C_PhotoSharing.GetCropRatio", function() return C_PhotoSharing.GetCropRatio() end },
}

-- { frame type, template }
Probe.TEMPLATES = {
    { "Frame", "MinimalSliderWithSteppersTemplate" },
    { "Slider", "MinimalSliderTemplate" },
    { "OffScreenFrame", nil },
}

--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

-- One row per console variable in the client's list, sorted by name. `info(name)` gives
-- { value, default, locked, secure, readOnly } or nil when the variable cannot be read.
-- A flag is kept only when it is set, so the saved file stays small.
function Probe.Rows(commands, info)
    local rows = {}
    for _, command in ipairs(commands or {}) do
        if command.commandType == TYPE_CVAR and type(command.command) == "string" then
            local row = { name = command.command, category = command.category }
            if command.help and command.help ~= "" then row.help = command.help end
            local got = info and info(command.command)
            if got then
                row.value, row.default = got.value, got.default
                if got.locked then row.locked = true end
                if got.secure then row.secure = true end
                if got.readOnly then row.readOnly = true end
            else
                row.unreadable = true
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        local la, lb = a.name:lower(), b.name:lower()
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return rows
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function Probe.Summary(report)
    local build = report.build or {}
    local lines = { string.format("client probe on %s (%s), interface %s:",
        tostring(build.version or "?"), tostring(build.build or "?"), tostring(build.interface or "?")) }

    local rows = report.cvars or {}
    if report.listError then
        lines[#lines + 1] = "  |cffff4444the list of console variables could not be read:|r " .. report.listError
    else
        local perCategory, closed, changed = {}, 0, 0
        for _, row in ipairs(rows) do
            local name = Probe.CATEGORIES[row.category] or tostring(row.category)
            perCategory[name] = (perCategory[name] or 0) + 1
            if row.locked or row.secure or row.readOnly or row.unreadable then closed = closed + 1 end
            if row.value ~= nil and row.value ~= row.default then changed = changed + 1 end
        end
        lines[#lines + 1] = string.format("  %d console %s: %d in Graphics, %d an addon may not set, %d off their default.",
            #rows, Util.Plural(#rows, "variable"), perCategory.Graphics or 0, closed, changed)
        local parts = {}
        for _, name in ipairs(Util.SortedKeys(perCategory)) do
            parts[#parts + 1] = string.format("%s %d", name, perCategory[name])
        end
        if #parts > 0 then lines[#lines + 1] = "  by category: " .. table.concat(parts, ", ") end
    end

    local missing = {}
    for _, path in ipairs(Util.SortedKeys(report.has or {})) do
        if not report.has[path] then missing[#missing + 1] = path end
    end
    local total = Count(report.has)
    lines[#lines + 1] = string.format("  %d of %d functions present.", total - #missing, total)
    if #missing > 0 then lines[#lines + 1] = "  |cffffcc00missing:|r " .. table.concat(missing, ", ") end

    local refused = {}
    for _, name in ipairs(Util.SortedKeys(report.templates or {})) do
        if report.templates[name] ~= true then refused[#refused + 1] = name end
    end
    if #refused > 0 then lines[#lines + 1] = "  |cffffcc00frames refused:|r " .. table.concat(refused, ", ") end

    local values = report.values or {}
    if values.GetMinRenderScale or values.GetMaxRenderScale then
        lines[#lines + 1] = string.format("  render scale runs from %s to %s.",
            tostring(values.GetMinRenderScale), tostring(values.GetMaxRenderScale))
    end
    return lines
end

-- What each capture attempt came to. `capture` is { [route] = attempt }.
function Probe.CaptureLines(capture)
    local lines = {}
    for _, route in ipairs(Util.SortedKeys(capture or {})) do
        local attempt = capture[route]
        local text
        if attempt.forbidden then
            text = "the client refused the call to addons (" .. tostring(attempt.forbidden) .. ")"
        elseif attempt.callError then
            text = "the call failed: " .. attempt.callError
        elseif not attempt.ready then
            text = "the call ran, and no picture came back"
        elseif attempt.applyError then
            text = "a picture was taken, and it could not be put on a texture: " .. attempt.applyError
        else
            text = string.format("a picture came back in %.2fs and is on a texture", attempt.seconds or 0)
        end
        lines[#lines + 1] = string.format("  capture, the %s way: %s.", route, text)
    end
    return lines
end

--------------------------------------------------------------------------------
-- Asking: the console variables
--------------------------------------------------------------------------------

local function Info(name)
    local try = Env.Try(name, C_CVar.GetCVarInfo, name)
    if not try.ok or try.n == 0 or try.values[1] == nil then return nil end
    local v = try.values
    return { value = v[1], default = v[2], locked = v[5] == true, secure = v[6] == true, readOnly = v[7] == true }
end

function Probe.Run()
    local report = {
        at = time(), tuner = ns.VERSION, build = Env.Build(),
        has = {}, values = {}, templates = {}, cvars = {},
    }

    for _, row in ipairs(Env.Probe(Probe.CHECKS)) do
        report.has[row.path] = row.present and row.kind or false
    end

    for _, ask in ipairs(Probe.VALUES) do
        local try = Env.Try(ask[1], ask[2])
        report.values[ask[1]] = try.ok and try.text or ("ERROR " .. try.err)
    end

    for _, pair in ipairs(Probe.TEMPLATES) do
        local try = Env.Try(pair[1], function()
            local f = CreateFrame(pair[1], nil, UIParent, pair[2])
            f:Hide()
        end)
        report.templates[pair[2] or pair[1]] = try.ok or try.err
    end

    local list = Env.Resolve("ConsoleGetAllCommands") or Env.Resolve("C_Console.GetAllCommands")
    local try = Env.Try("commands", list)
    if try.ok and type(try.values[1]) == "table" then
        report.cvars = Probe.Rows(try.values[1], Info)
    else
        report.listError = try.err or "the call returned no list"
    end
    return report
end

--------------------------------------------------------------------------------
-- Asking: a capture of the screen
--------------------------------------------------------------------------------

local ROUTES = {
    report = {
        event = "REPORT_SCREENSHOT_READY",
        take = function() C_ReportSystem.TakeReportScreenshot() end,
        apply = function(texture) C_ReportSystem.SetScreenshotPreviewTexture(texture) end,
    },
    photo = {
        event = "PHOTO_SHARING_SCREENSHOT_READY",
        take = function() C_PhotoSharing.TakePhoto() end,
        apply = function(texture) C_PhotoSharing.SetScreenshotPreviewTexture(texture) end,
    },
}

-- How long to wait for the picture before saying none came.
local PATIENCE = 3

local shot           -- the frame the capture is shown on, made on first use
local pending        -- { route, attempt, asked, say } while a picture is awaited
local view = "split"

local function Place()
    shot.picture:ClearAllPoints()
    shot.line:ClearAllPoints()
    if view == "full" then
        -- Whole and at half size, so it is plain whether the interface is in the picture
        -- and whether it has been cropped.
        shot.picture:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        shot.picture:SetSize(UIParent:GetWidth() / 2, UIParent:GetHeight() / 2)
        shot.picture:SetTexCoord(0, 1, 0, 1)
        shot.line:Hide()
    else
        -- The left half of the picture over the left half of the screen: where it lines
        -- up with the live picture, the capture is the size of the screen.
        shot.picture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        shot.picture:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", 0, 0)
        shot.picture:SetTexCoord(0, 0.5, 0, 1)
        shot.line:SetPoint("TOP", UIParent, "TOP", 0, 0)
        shot.line:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
        shot.line:SetWidth(2)
        shot.line:Show()
    end
end

local function OnEvent(_, event, ...)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local who, what = ...
        if pending and who == addonName then pending.attempt.forbidden = tostring(what) end
        return
    end
    if not pending or ROUTES[pending.route].event ~= event then return end

    local attempt, say = pending.attempt, pending.say
    attempt.ready = true
    attempt.seconds = GetTime() - pending.asked
    local try = Env.Try("apply", ROUTES[pending.route].apply, shot.picture)
    if try.ok then
        local size = Env.Try("size", function() return shot.picture:GetSize() end)
        attempt.textureSize = size.ok and size.text or nil
        local file = Env.Try("file", function() return shot.picture:GetTexture() end)
        attempt.texture = file.ok and file.text or nil
        Place()
        shot:Show()
        say(string.format("the %s capture came back in %.2fs and is on the left half of the screen. "
            .. "/tuner capture view full shows it whole; /tuner capture clear removes it.", pending.route, attempt.seconds))
    else
        attempt.applyError = try.err
        say("a picture was taken, and it could not be put on a texture: " .. try.err)
    end
    pending = nil
end

local function Build()
    if shot then return end
    shot = CreateFrame("Frame", nil, UIParent)
    shot:SetAllPoints(UIParent)
    shot:SetFrameStrata("BACKGROUND")
    shot:Hide()
    shot.picture = shot:CreateTexture(nil, "BACKGROUND")
    shot.line = shot:CreateTexture(nil, "ARTWORK")
    shot.line:SetColorTexture(1, 0.82, 0, 1)
    shot:RegisterEvent("REPORT_SCREENSHOT_READY")
    shot:RegisterEvent("PHOTO_SHARING_SCREENSHOT_READY")
    shot:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    shot:RegisterEvent("ADDON_ACTION_BLOCKED")
    shot:SetScript("OnEvent", Env.Wrap("RenderTuner capture", OnEvent))
end

-- Tries one way of capturing the screen. What happened is written into log[route], and
-- said through `say` as it happens.
function Probe.Capture(route, log, say)
    local way = ROUTES[route]
    if not way then return end
    Build()
    shot:Hide()

    local attempt = { at = time() }
    log[route] = attempt
    pending = { route = route, attempt = attempt, asked = GetTime(), say = say }

    local try = Env.Try("take", way.take)
    if not try.ok then
        attempt.callError = try.err
        pending = nil
        say("the call failed: " .. try.err)
        return
    end
    say(string.format("asked for a capture the %s way.", route))
    C_Timer.After(PATIENCE, function()
        if pending and pending.attempt == attempt then
            pending = nil
            say(attempt.forbidden and ("the client refused the call to addons: " .. attempt.forbidden)
                or string.format("no picture came back in %d seconds.", PATIENCE))
        end
        -- Blizzard's own photo preview listens for the same picture and opens itself.
        local theirs = Env.Resolve("PhotoSharingFrame")
        if route == "photo" and theirs then
            local shown = Env.Try("shown", function() return theirs:IsShown() end)
            attempt.blizzardPreviewOpened = shown.ok and shown.values[1] == true
        end
    end)
end

function Probe.CaptureView(mode)
    view = mode
    if shot then Place() end
end

function Probe.CaptureClear()
    if shot then shot:Hide() end
end
