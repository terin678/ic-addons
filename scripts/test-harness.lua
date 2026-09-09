--[[
Headless runner for an addon's test cases, under LuaJIT.

    luajit scripts/test-harness.lua <path to addon folder>

Two kinds of addon live in this repo and both run here:

  * The ICLibs shape (every file opens `local addonName, ns = ...`, LibICCore attaches
    the harness). The addon's .toc is the load order; ICLibs' own .toc is loaded first;
    every file gets (addonName, ns); then ADDON_LOADED is delivered to every frame that
    asked for it, which is how LibICCore boots ns.db, and ns.Tests.Run() runs.
  * MarkedForDeath, which predates that shape: a fixed file list, a global table, and
    its own Tests.Run() returning a boolean. Kept as it was.

The client is a stub. A frame answers any method it is asked for with a no-op, records
the events it registers and the scripts it sets, and that is all the client the logic
modules need at file scope. Anything that calls a client function that is not stubbed
fails loudly with the name, which is the point: it is either a module doing client work
at file scope, which the standards say not to, or a stub to add here.
]]

local addonDir = ...
assert(addonDir, "usage: luajit scripts/test-harness.lua <addon dir>")
addonDir = addonDir:gsub("\\", "/"):gsub("/$", "")
local addonName = addonDir:match("([^/]+)$")
local flavorDir = addonDir:match("^(.*)/[^/]+$")

--------------------------------------------------------------------------------
-- The stub client
--------------------------------------------------------------------------------

_G.time = _G.time or os.time
_G.difftime = _G.difftime or os.difftime
_G.date = _G.date or os.date
_G.GetServerTime = function() return os.time() end
_G.GetTime = function() return os.clock() end
_G.wipe = _G.wipe or function(t)
    for key in pairs(t) do t[key] = nil end
    return t
end
_G.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.tinsert, _G.tremove = table.insert, table.remove
_G.format = string.format
-- The client's global aliases of the string and table libraries; LibStub uses strmatch.
_G.strmatch, _G.strfind, _G.strsub, _G.strlower, _G.strupper = string.match, string.find, string.sub, string.lower, string.upper
_G.strlen, _G.strrep, _G.strbyte, _G.strchar, _G.gsub, _G.gmatch = string.len, string.rep, string.byte, string.char, string.gsub, string.gmatch
_G.tconcat, _G.sort, _G.wipe = table.concat, table.sort, _G.wipe
_G.floor, _G.ceil, _G.abs, _G.max, _G.min = math.floor, math.ceil, math.abs, math.max, math.min
_G.geterrorhandler = function() return function(err) io.stderr:write(tostring(err) .. "\n") end end
_G.securecall = function(fn, ...) return fn(...) end
_G.issecurevariable = function() return false end
_G.tostringall = function(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return unpack(out)
end
_G.strsplit = function(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
end

local frames = {}

local function Stub(kind, name)
    local f = { _kind = kind, _name = name, _events = {}, _scripts = {}, _shown = false, _text = "" }
    setmetatable(f, { __index = function() return function() return nil end end })
    f.RegisterEvent = function(self, e) self._events[e] = true end
    f.UnregisterEvent = function(self, e) self._events[e] = nil end
    f.UnregisterAllEvents = function(self) self._events = {} end
    f.IsEventRegistered = function(self, e) return self._events[e] == true end
    f.SetScript = function(self, k, fn) self._scripts[k] = fn end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.HookScript = function(self, k, fn) self._scripts[k] = fn end
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.SetShown = function(self, on) self._shown = on and true or false end
    f.IsShown = function(self) return self._shown end
    f.IsVisible = function(self) return self._shown end
    f.GetName = function(self) return self._name end
    f.GetParent = function() return _G.UIParent end
    f.SetText = function(self, s) self._text = s end
    f.GetText = function(self) return self._text end
    f.GetChecked = function() return false end
    f.GetWidth = function() return 100 end
    f.GetHeight = function() return 20 end
    f.GetEffectiveScale = function() return 1 end
    f.GetScale = function() return 1 end
    f.GetNumPoints = function() return 0 end
    f.GetLeft = function() return 0 end
    f.GetTop = function() return 0 end
    f.GetBottom = function() return 0 end
    f.GetRight = function() return 0 end
    f.GetCenter = function() return 0, 0 end
    f.HasFocus = function() return false end
    f.CreateFontString = function() return Stub("FontString") end
    f.CreateTexture = function() return Stub("Texture") end
    f.GetFontString = function(self) return Stub("FontString") end
    f.GetObjectType = function(self) return self._kind end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

-- Tests that need a real client (a page drawing itself) read this and step aside.
_G.IC_HEADLESS = true
_G.CreateFrame = function(kind, name) return Stub(kind or "Frame", name) end
_G.UIParent = Stub("Frame", "UIParent")
_G.GameTooltip = Stub("GameTooltip", "GameTooltip")
_G.Minimap = Stub("Frame", "Minimap")
_G.WorldFrame = Stub("Frame", "WorldFrame")
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.SOUNDKIT = {}
_G.NUM_CHAT_WINDOWS = 10
_G.ERR_DECLINE_GROUP_S = "%s declines your group invitation."
_G.C_Timer = {
    After = function() end,
    NewTicker = function() return { Cancel = function() end } end,
    NewTimer = function() return { Cancel = function() end } end,
}
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.IsAddOnLoaded = function() return false end
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg)
        print((tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    end,
}
_G.UnitName = function() return "Tester" end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitInParty = function() return false end
_G.UnitInRaid = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.InCombatLockdown = function() return false end
_G.IsInInstance = function() return false end
_G.IsInGuild = function() return false end
_G.GetItemInfo = function() return nil end
_G.GetItemCount = function() return 0 end
_G.GetItemIcon = function() return nil end
_G.GetBuildInfo = function() return "2.5.6", "68184", "", 20506 end
_G.GetChannelList = function() return end
_G.GetChatWindowInfo = function() return nil end
_G.GetCursorPosition = function() return 0, 0 end
_G.PlaySound = function() end
_G.hooksecurefunc = function() end
_G.GetSpellInfo = function() return nil end
_G.IsSpellKnown = function() return false end
_G.GetLocale = function() return "enUS" end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

local function TocFiles(dir)
    local name = dir:match("([^/]+)$")
    local toc = io.open(dir .. "/" .. name .. ".toc", "r")
    if not toc then return nil end
    local files = {}
    for line in toc:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    toc:close()
    return files
end

local function LoadFile(path, ...)
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write("load error in " .. path .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    local ok, runErr = pcall(chunk, ...)
    if not ok then
        io.stderr:write("error running " .. path .. ": " .. tostring(runErr) .. "\n")
        os.exit(1)
    end
end

-- Delivers one event to every frame that registered it, in creation order, the way
-- the client does. ADDON_LOADED is what boots the saved variables.
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f._events[event] and f._scripts.OnEvent then
            local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
            if not ok then
                io.stderr:write("error in " .. event .. " handler: " .. tostring(err) .. "\n")
                os.exit(1)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- MarkedForDeath, as it was
--------------------------------------------------------------------------------

if addonName == "MarkedForDeath" then
    -- Core.lua cannot be loaded here because it creates a frame at file scope, but the
    -- logic modules register their client-side setup through RegisterInit at file scope.
    -- Seed a no-op so those calls succeed; the registered functions are never run
    -- headlessly, which is the point of keeping them out of file scope.
    _G.MarkedForDeath = { RegisterInit = function() end }
    local files = {
        "Helpers.lua", "JSON.lua", "Data_Mobs.lua", "Data_Auras.lua", "Data_Bosses.lua",
        "Log.lua", "Actions.lua", "Roles.lua", "Rules.lua", "Allocator.lua", "Candidates.lua",
        "Marker.lua", "Conflicts.lua", "Chatter.lua", "CombatLog.lua", "UI_ActionBar.lua",
        "Comms.lua", "RaidCheck.lua", "Encounters.lua", "Tanks.lua", "Healers.lua", "Tests.lua",
    }
    for _, name in ipairs(files) do
        local path = addonDir .. "/" .. name
        local f = io.open(path, "r")
        if f then
            f:close()
            LoadFile(path, "MarkedForDeath")
        end
    end
    local MFD = _G.MarkedForDeath
    if not (MFD and MFD.Tests) then
        io.stderr:write("no test registry found; did Tests.lua load?\n")
        os.exit(1)
    end
    os.exit(MFD.Tests.Run() and 0 or 1)
end

--------------------------------------------------------------------------------
-- The ICLibs shape
--------------------------------------------------------------------------------

-- ICLibs first, from its own .toc, so LibStub, LibICCore and LibICUI exist. The
-- third-party libraries load too; they are pure at file scope.
local libsDir = flavorDir .. "/ICLibs"
local libFiles = TocFiles(libsDir)
if not libFiles then
    io.stderr:write("no ICLibs.toc beside " .. addonDir .. "\n")
    os.exit(1)
end
local libNS = {}
for _, rel in ipairs(libFiles) do
    -- LibDBIcon builds minimap buttons, which is client work by design; every addon
    -- fetches it silently and does without, so headless does without too.
    if not rel:find("LibDBIcon", 1, true) then
        LoadFile(libsDir .. "/" .. rel, "ICLibs", libNS)
    end
end

local files = TocFiles(addonDir)
if not files then
    io.stderr:write("no " .. addonName .. ".toc in " .. addonDir .. "\n")
    os.exit(1)
end
local ns = {}
for _, rel in ipairs(files) do
    LoadFile(addonDir .. "/" .. rel, addonName, ns)
end

Fire("ADDON_LOADED", addonName)

-- MalexisAuctionWatcher predates the private namespace: LibICCore attached to its
-- global table, and that is where its Tests live.
if not (ns.Tests and ns.Tests.Run) and type(_G[addonName]) == "table" then
    ns = _G[addonName]
end

if not (ns.Tests and ns.Tests.Run) then
    io.stderr:write("no ns.Tests.Run; did LibICCore attach and Tests.lua load?\n")
    os.exit(1)
end

local pass, fail = ns.Tests.Run()
if type(pass) == "boolean" then os.exit(pass and 0 or 1) end
os.exit((fail or 0) == 0 and 0 or 1)
