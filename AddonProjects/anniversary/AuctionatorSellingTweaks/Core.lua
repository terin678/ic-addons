-- AuctionatorSellingTweaks - reorder the columns of Auctionator's Selling tab price list
--
-- Auctionator's legacy-AH "current prices" list (the one shown while posting) defines its
-- columns in AuctionatorBuyAuctionsDataProviderMixin:GetTableLayout(). Time left exists
-- there but is hidden by default and sits after "You?". This addon wraps that function to
-- return the same columns with an "Expiry" column placed before "You?", shown by default,
-- and "You?" narrowed. Nothing in Auctionator's files is changed, so updates keep working.
--
-- The legacy auction house only reports time left in bands: Short (< 30 min),
-- Medium (30 min - 2 h), Long (2 - 12 h), Very Long (12 - 48 h). Exact minutes are not
-- available on this client.
local addonName = "AuctionatorSellingTweaks"

local YOU_WIDTH = 44
local EXPIRY_WIDTH = 80

local function Rearranged(original)
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

local function Install()
    local mixin = _G.AuctionatorBuyAuctionsDataProviderMixin
    if not mixin or type(mixin.GetTableLayout) ~= "function" or mixin.__sellingTweaksInstalled then
        return false
    end
    local originalGetTableLayout = mixin.GetTableLayout
    local cached
    mixin.GetTableLayout = function(self, ...)
        if not cached then
            cached = Rearranged(originalGetTableLayout(self, ...))
        end
        return cached
    end
    mixin.__sellingTweaksInstalled = true
    return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and (arg1 == addonName or arg1 == "Auctionator") then
        Install()
    elseif event == "PLAYER_LOGIN" then
        if not Install() and not (_G.AuctionatorBuyAuctionsDataProviderMixin and _G.AuctionatorBuyAuctionsDataProviderMixin.__sellingTweaksInstalled) then
            print(addonName .. ": Auctionator's selling price list was not found; nothing changed")
        end
    end
end)
