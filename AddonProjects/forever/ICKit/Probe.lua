local addonName, ns = ...

--[[
The probe: what /ickit probe asks this client, and what it does with the answers.

Nobody has an interface source for the Forever client yet, so the layers above this one
are built on what the probe finds rather than on what another client had. The report is
saved to ICKitDB.probe, where it can be read off disk after a /reload.

    Probe.CHECKS      globals and functions that may or may not exist
    Probe.VALUES      questions with an answer worth keeping
    Probe.TEMPLATES   frame templates the widgets would like to use
    Probe.METHODS     methods on the objects the widgets are made of
    Probe.SCRIPTS     script handlers an edit box and a frame should accept

    Probe.Run()             -> report     asks the client; the only impure function here
    Probe.Summary(report)   -> lines      pure
]]

local Util = LibStub("LibICUtil-1.0")
local Env = LibStub("LibICEnv-1.0")

local Probe = {}
ns.Probe = Probe

Probe.CHECKS = {
    { "CreateFrame", "every widget" },
    { "UIParent", "every widget" },
    { "DEFAULT_CHAT_FRAME", "printing" },
    { "SlashCmdList", "commands" },
    { "C_AddOns.GetAddOnMetadata", "reading an addon's version, modern" },
    { "C_AddOns.IsAddOnLoaded", "optional dependencies, modern" },
    { "GetAddOnMetadata", "reading an addon's version, legacy" },
    { "C_Timer.After", "anything delayed" },
    { "C_Timer.NewTicker", "anything repeated" },
    { "GetServerTime", "timestamps" },
    { "BackdropTemplateMixin", "backdrops on frames" },
    { "MenuUtil.CreateContextMenu", "context menus, modern" },
    { "EasyMenu", "context menus, legacy" },
    { "UIDropDownMenu_Initialize", "dropdowns, legacy" },
    { "StaticPopup_Show", "confirm dialogs" },
    { "StaticPopupDialogs", "confirm dialogs" },
    { "Settings.RegisterCanvasLayoutCategory", "an options panel, modern" },
    { "InterfaceOptions_AddCategory", "an options panel, legacy" },
    { "EditModeManagerFrame", "Edit Mode" },
    { "AddonCompartmentFrame", "the addon button by the minimap" },
    { "GameTooltip", "tooltips" },
    { "UISpecialFrames", "closing a window with Escape" },
    { "InCombatLockdown", "leaving frames alone in combat" },
    { "hooksecurefunc", "watching Blizzard functions" },
    { "CreateFramePool", "pooled frames" },
    { "Mixin", "mixins" },
    { "GetPhysicalScreenSize", "placing notes on any screen" },
    { "GetCVar", "console variables, legacy" },
    { "C_CVar.GetCVar", "console variables, modern" },
    { "loadstring", "compiling text" },
    { "debugprofilestop", "timing a handler" },
    { "UpdateAddOnMemoryUsage", "memory per addon" },
    { "GetAddOnMemoryUsage", "memory per addon" },
    { "UpdateAddOnCPUUsage", "CPU per addon, legacy" },
    { "GetAddOnCPUUsage", "CPU per addon, legacy" },
    { "GetFunctionCPUUsage", "CPU per function, legacy" },
    { "C_AddOnProfiler.GetAddOnMetric", "CPU per addon, modern" },
    { "issecretvalue", "secret values in combat" },
    { "UnitFullName", "a character's name and realm" },
    { "GetNormalizedRealmName", "a realm key" },
    { "C_ChatInfo.SendAddonMessage", "sharing between players" },
    { "C_ChatInfo.RegisterAddonMessagePrefix", "sharing between players" },
    { "TooltipDataProcessor", "item tooltips, modern" },
    { "C_TooltipInfo", "item tooltips, modern" },
    { "C_Container.GetContainerNumSlots", "bags" },
    { "C_Item.GetItemInfo", "items, modern" },
    { "GetItemInfo", "items, legacy" },
    { "C_AuctionHouse", "the auction house, modern" },
    { "QueryAuctionItems", "the auction house, legacy" },
    { "WOW_PROJECT_ID", "which game this is" },
    { "GameFontNormal", "fonts" },
    { "GameFontNormalSmall", "fonts" },
    { "GameFontHighlight", "fonts" },
    { "GameFontHighlightSmall", "fonts" },
    { "GameFontDisableSmall", "fonts" },
}

Probe.VALUES = {
    { "GetBuildInfo", function() return GetBuildInfo() end },
    { "GetLocale", function() return GetLocale() end },
    { "UnitName player", function() return UnitName("player") end },
    { "UnitFullName player", function() return UnitFullName("player") end },
    { "GetRealmName", function() return GetRealmName() end },
    { "GetNormalizedRealmName", function() return GetNormalizedRealmName() end },
    { "UnitGUID player", function() return UnitGUID("player") end },
    { "UIParent width, height, effective scale", function()
        return UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale()
    end },
    { "GetPhysicalScreenSize", function() return GetPhysicalScreenSize() end },
    { "GetCVar scriptProfile", function() return GetCVar("scriptProfile") end },
    { "C_AddOns.GetAddOnMetadata ICKit Version", function()
        return C_AddOns.GetAddOnMetadata("ICKit", "Version")
    end },
}

-- { frame type, template }
Probe.TEMPLATES = {
    { "Frame", "BackdropTemplate" },
    { "Button", "UIPanelButtonTemplate" },
    { "CheckButton", "UICheckButtonTemplate" },
    { "EditBox", "InputBoxTemplate" },
    { "ScrollFrame", "UIPanelScrollFrameTemplate" },
    { "Frame", "BasicFrameTemplateWithInset" },
    { "Button", "UIPanelCloseButton" },
}

Probe.METHODS = {
    Frame = { "SetPoint", "SetSize", "SetMovable", "StartMoving", "StopMovingOrSizing", "RegisterForDrag",
        "SetClampedToScreen", "SetResizeBounds", "SetFrameStrata", "EnableMouse", "SetBackdrop",
        "SetUserPlaced", "SetScale", "GetEffectiveScale" },
    Texture = { "SetColorTexture", "SetTexture", "SetVertexColor", "SetAllPoints", "SetAtlas" },
    FontString = { "SetText", "SetWordWrap", "SetMaxLines", "SetJustifyH", "SetTextColor", "GetStringWidth" },
    EditBox = { "SetMaxBytes", "SetMaxLetters", "SetTextInsets", "SetAutoFocus", "SetFontObject", "ClearFocus",
        "HighlightText", "SetMultiLine" },
    CheckButton = { "SetChecked", "GetChecked", "SetNormalTexture", "SetCheckedTexture" },
}

-- { object, handler }
Probe.SCRIPTS = {
    { "Frame", "OnDragStart" }, { "Frame", "OnDragStop" }, { "Frame", "OnMouseDown" },
    { "Frame", "OnEnter" }, { "Frame", "OnEvent" },
    { "EditBox", "OnEnterPressed" }, { "EditBox", "OnEscapePressed" },
    { "EditBox", "OnEditFocusLost" }, { "EditBox", "OnTextChanged" },
    { "CheckButton", "OnClick" },
}

--------------------------------------------------------------------------------
-- Asking
--------------------------------------------------------------------------------

-- One of each object the widgets are made of, hidden. An object the client will not
-- build is left out and everything asked of it reads as missing.
local function BuildObjects()
    local objects = {}
    local made = Env.Try("Frame", function() return CreateFrame("Frame", nil, UIParent) end)
    if not made.ok then return objects end
    local frame = made.values[1]
    frame:Hide()
    objects.Frame = frame
    for kind, build in pairs({
        Texture = function() return frame:CreateTexture(nil, "BACKGROUND") end,
        FontString = function() return frame:CreateFontString(nil, "OVERLAY", "GameFontNormal") end,
        EditBox = function() return CreateFrame("EditBox", nil, frame) end,
        CheckButton = function() return CreateFrame("CheckButton", nil, frame) end,
    }) do
        local try = Env.Try(kind, build)
        if try.ok then objects[kind] = try.values[1] end
    end
    return objects
end

function Probe.Run()
    local report = {
        at = time(), kit = ns.VERSION, build = Env.Build(),
        has = {}, values = {}, templates = {}, methods = {}, scripts = {},
    }

    for _, row in ipairs(Env.Probe(Probe.CHECKS)) do
        report.has[row.path] = row.present and row.kind or false
    end

    for _, ask in ipairs(Probe.VALUES) do
        local try = Env.Try(ask[1], ask[2])
        report.values[ask[1]] = try.ok and try.text or ("ERROR " .. try.err)
    end
    -- Every WOW_PROJECT_ constant the client defines, whatever they are called here.
    local constants = Env.Try("constants", function()
        for key, value in pairs(_G) do
            if type(key) == "string" and key:find("^WOW_PROJECT_") then
                report.values[key] = tostring(value)
            end
        end
    end)
    if not constants.ok then report.values["WOW_PROJECT_*"] = "ERROR " .. constants.err end

    for _, pair in ipairs(Probe.TEMPLATES) do
        local try = Env.Try(pair[2], function()
            local f = CreateFrame(pair[1], nil, UIParent, pair[2])
            f:Hide()
        end)
        report.templates[pair[2]] = try.ok or try.err
    end

    local objects = BuildObjects()
    for kind, names in pairs(Probe.METHODS) do
        local object = objects[kind]
        for _, name in ipairs(names) do
            report.methods[kind .. "." .. name] = object ~= nil and type(object[name]) == "function"
        end
    end
    for _, pair in ipairs(Probe.SCRIPTS) do
        local object = objects[pair[1]]
        local try = Env.Try(pair[2], function() return object:HasScript(pair[2]) end)
        report.scripts[pair[1] .. "." .. pair[2]] = try.ok and try.values[1] == true
    end

    return report
end

--------------------------------------------------------------------------------
-- Pure: the report as a few lines
--------------------------------------------------------------------------------

-- The keys of t whose value is not exactly true, sorted. A template that failed holds
-- its error text, which is not true either.
local function NotTrue(t)
    local names = {}
    for _, key in ipairs(Util.SortedKeys(t or {})) do
        if t[key] ~= true then names[#names + 1] = key end
    end
    return names
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

    local missing = {}
    for _, path in ipairs(Util.SortedKeys(report.has or {})) do
        if not report.has[path] then missing[#missing + 1] = path end
    end
    local total = Count(report.has)
    lines[#lines + 1] = string.format("  %d of %d globals present.", total - #missing, total)
    if #missing > 0 then lines[#lines + 1] = "  |cffffcc00missing:|r " .. table.concat(missing, ", ") end

    local sections = {
        { "templates", report.templates, "refused" },
        { "methods", report.methods, "missing" },
        { "script handlers", report.scripts, "missing" },
    }
    for _, section in ipairs(sections) do
        local bad = NotTrue(section[2])
        local n = Count(section[2])
        lines[#lines + 1] = string.format("  %d of %d %s usable.", n - #bad, n, section[1])
        if #bad > 0 then
            lines[#lines + 1] = string.format("  |cffffcc00%s %s:|r %s", section[1], section[3], table.concat(bad, ", "))
        end
    end

    if report.events and #report.events > 0 then
        lines[#lines + 1] = "  load events, in order: " .. table.concat(report.events, ", ")
    end
    return lines
end
