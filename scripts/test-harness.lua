-- Headless loader for an ic-addons addon's logic modules.
-- Usage: luajit scripts/test-harness.lua <path to addon folder>
--
-- Only modules that call no WoW API at file scope can be loaded here. Caching a
-- nil global into a local is harmless; calling one is not. See the addon's plan.
local addonDir = ...
assert(addonDir, "usage: luajit scripts/test-harness.lua <addon dir>")

-- The few client globals the logic modules and the runner touch.
_G.time = _G.time or os.time
_G.GetServerTime = function() return os.time() end

local files = {
    "Helpers.lua",
    "Seats.lua",
    "Rules.lua",
    "Allocator.lua",
    "Candidates.lua",
    "Marker.lua",
    "Comms.lua",
    "Tests.lua",
}

for _, name in ipairs(files) do
    local path = addonDir .. "/" .. name
    local f = io.open(path, "r")
    if f then
        f:close()
        local chunk, err = loadfile(path)
        if not chunk then
            io.stderr:write("load error in " .. name .. ": " .. tostring(err) .. "\n")
            os.exit(1)
        end
        chunk("MarkedForDeath")
    end
end

local MFD = _G.MarkedForDeath
if not (MFD and MFD.Tests) then
    io.stderr:write("no test registry found; did Tests.lua load?\n")
    os.exit(1)
end

os.exit(MFD.Tests.Run() and 0 or 1)
