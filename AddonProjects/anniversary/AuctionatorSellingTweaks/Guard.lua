local addonName, ns = ...

ns.Guard = ns.Guard or {}
local Guard = ns.Guard

--[[
A confirmation before posting an item far under the market.

Auctionator asks before an "unusually low" price, but only for stackable items, only
against the fifth listing, and only while its own option is on. A piece of gear posted
at a tenth of the cheapest listing goes straight through, which is how a good deal of
gold went missing one evening.

This wraps the two functions Auctionator's Post button consults --
AuctionatorSaleItemMixin:RequiresConfirmationState and :GetConfirmationMessage -- so
Auctionator's own confirm dialog, Skip button and all, shows this message first. The
reference is the cheapest listing on the auction house right now; with none, the last
price Auctionator has for the item. The floor is /ast floor.

Judge and ClampFloor are pure and have cases. Everything that reads a frame is below.
]]

local MIN_FLOOR, MAX_FLOOR = 1, 90

-- Pure.
function Guard.ClampFloor(pct)
    pct = math.floor(tonumber(pct) or 40)
    return math.max(MIN_FLOOR, math.min(MAX_FLOOR, pct))
end

--[[
Pure. Whether a unit price is far enough under the reference to ask about. Returns
nil, or { unit, ref, underPct } with how far under it is, in whole percent.

Nothing to compare against is nothing to ask about: a zero or missing reference, or a
price that is not positive (Auctionator refuses those itself), gives nil.
]]
function Guard.Judge(unitPrice, reference, floorPct)
    unitPrice, reference = tonumber(unitPrice) or 0, tonumber(reference) or 0
    if unitPrice <= 0 or reference <= 0 then return nil end
    local under = (reference - unitPrice) / reference
    if under * 100 <= (floorPct or 40) then return nil end
    return { unit = unitPrice, ref = reference, underPct = math.floor(under * 100 + 0.5) }
end

-- Pure. The dialog runs its text through a format call, so a bare % in "88% under"
-- reads as a directive and errors. Doubled, it prints as itself.
function Guard.ForDialog(text)
    return (tostring(text or ""):gsub("%%", "%%%%"))
end

--------------------------------------------------------------------------------
-- Reading Auctionator's selling frame
--------------------------------------------------------------------------------

-- The unit price the Post button would use: the unit box, or with bid-only posting
-- the bid spread over the stack, the way Auctionator's own check reads it.
local function EffectiveUnitPrice(frame)
    local unit = frame.UnitPrice and frame.UnitPrice:GetAmount() or 0
    local A = _G.Auctionator
    if unit == 0 and A and A.Config and A.Config.Get(A.Config.Options.SHOW_SELLING_BID_PRICE)
        and frame.BidPrice and frame.GetStackSize then
        local stack = frame:GetStackSize()
        if stack and stack > 0 then unit = math.ceil(frame.BidPrice:GetAmount() / stack) end
    end
    return unit
end

-- The cheapest unit price in the current-prices list Auctionator has already fetched
-- for this item, then Auctionator's last known price. Returns price, what it was.
local function Reference(frame)
    local A = _G.Auctionator
    local parent = frame.GetParent and frame:GetParent()
    local provider = parent and parent.BuyFrame and parent.BuyFrame.CurrentPrices
        and parent.BuyFrame.CurrentPrices.SearchDataProvider
    local lowest
    for _, auction in ipairs(provider and provider.allAuctions or {}) do
        local ok, unit = pcall(A.Utilities.ToUnitPrice, auction)
        if ok and unit and unit > 0 and (not lowest or unit < lowest) then lowest = unit end
    end
    if lowest then return lowest, "the cheapest listing right now" end

    local link = frame.itemInfo and frame.itemInfo.itemLink
    if link and A.Utilities.BasicDBKeyFromLink and A.Database and A.Database.GetPrice then
        local ok, price = pcall(function()
            return A.Database:GetPrice(A.Utilities.BasicDBKeyFromLink(link))
        end)
        if ok and price and price > 0 then return price, "Auctionator's last price for it" end
    end
    return nil
end

-- The message, or nil when there is nothing to ask. Read by both wraps, so what
-- decides to ask and what is asked can never disagree.
function Guard.Check(frame)
    local s = ns.db and ns.db.settings.guard
    if not s or not s.enabled or not ns.Enabled() or not frame.itemInfo then return nil end
    local ref, what = Reference(frame)
    local verdict = Guard.Judge(EffectiveUnitPrice(frame), ref, s.floorPct)
    if not verdict then return nil end
    local name = frame.itemInfo.itemLink or "this item"
    return Guard.ForDialog(string.format("|cffff4444Hold on.|r You are posting %s at %s each. %s is %s, so this is "
        .. "|cffff4444%d%% under|r it.\n\nPost anyway?", name, GetMoneyString(verdict.unit, true),
        what:sub(1, 1):upper() .. what:sub(2), GetMoneyString(verdict.ref, true), verdict.underPct))
end

-- Returns whether the wraps are in place. Safe to call more than once.
function Guard.Install()
    local mixin = _G.AuctionatorSaleItemMixin
    if not mixin or type(mixin.GetConfirmationMessage) ~= "function"
        or type(mixin.RequiresConfirmationState) ~= "function" then
        return false
    end
    if mixin.__icGuardInstalled then return true end

    local originalMessage = mixin.GetConfirmationMessage
    local originalRequires = mixin.RequiresConfirmationState
    -- Ours first: it is the more specific warning. A failure inside the check must
    -- never stop Auctionator's own, so it is caught and falls through.
    mixin.GetConfirmationMessage = function(self, ...)
        local ok, text = pcall(Guard.Check, self)
        if ok and text then return text end
        if not ok then ns.Debug("guard check failed: %s", tostring(text)) end
        return originalMessage(self, ...)
    end
    mixin.RequiresConfirmationState = function(self, ...)
        local ok, text = pcall(Guard.Check, self)
        if ok and text then return true end
        return originalRequires(self, ...)
    end
    mixin.__icGuardInstalled = true
    return true
end
