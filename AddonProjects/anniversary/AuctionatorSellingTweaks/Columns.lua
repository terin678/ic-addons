local addonName, ns = ...

ns.Columns = ns.Columns or {}
local Columns = ns.Columns

--[[
Reorders the columns of Auctionator's Selling tab price list.

Auctionator's legacy-AH "current prices" list (the one shown while posting) defines its
columns in AuctionatorBuyAuctionsDataProviderMixin:GetTableLayout(). Time left exists
there but is hidden by default and sits after "You?". This wraps that function to return
the same columns with an "Expiry" column placed before "You?", shown by default, and
"You?" narrowed.

The legacy auction house only reports time left in bands: Short (< 30 min), Medium
(30 min - 2 h), Long (2 - 12 h), Very Long (12 - 48 h). Exact minutes are not available
on this client.
]]

local YOU_WIDTH = 44
local EXPIRY_WIDTH = 80

-- Pure. The same columns with Expiry before "You?" and "You?" narrowed; the original
-- when either is missing, so a renamed column leaves the layout alone.
function Columns.Rearranged(original)
    local result = {}
    local timeLeft, you
    for _, col in ipairs(original) do
        local params = col.headerParameters or {}
        if params[1] == "timeLeft" then
            timeLeft = col
        elseif params[1] == "isOwnedText" then
            you = col
        end
    end
    if not timeLeft or not you then
        return original
    end

    -- Copies so Auctionator's own table stays untouched
    local expiry = {}
    for k, v in pairs(timeLeft) do expiry[k] = v end
    expiry.headerText = "Expiry"
    expiry.width = EXPIRY_WIDTH
    expiry.defaultHide = nil

    local youNarrow = {}
    for k, v in pairs(you) do youNarrow[k] = v end
    youNarrow.width = YOU_WIDTH

    for _, col in ipairs(original) do
        if col == timeLeft then
            -- dropped here; re-added just before "You?"
        elseif col == you then
            table.insert(result, expiry)
            table.insert(result, youNarrow)
        else
            table.insert(result, col)
        end
    end
    return result
end

-- Returns whether the wrap is in place. Safe to call more than once.
function Columns.Install()
    local mixin = _G.AuctionatorBuyAuctionsDataProviderMixin
    if not mixin or type(mixin.GetTableLayout) ~= "function" then return false end
    if mixin.__sellingTweaksInstalled then return true end
    local originalGetTableLayout = mixin.GetTableLayout
    local cached
    mixin.GetTableLayout = function(self, ...)
        if not cached then
            cached = Columns.Rearranged(originalGetTableLayout(self, ...))
        end
        return cached
    end
    mixin.__sellingTweaksInstalled = true
    return true
end
