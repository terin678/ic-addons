local addonName, ns = ...

ns.Crafter = ns.Crafter or {}
local Crafter = ns.Crafter

--[[
Opening a profession window with an order waiting used to leave you scrolling for
the recipe and counting on your fingers. This puts the window's selection on the
next thing the order needs and types the number of crafts into the create box.

Nothing is crafted here. The Create click stays yours, and the count is a starting
point you can overtype: the recipe may make several per craft, and the player may
want to make fewer.
]]

--------------------------------------------------------------------------------
-- Decisions (pure)
--------------------------------------------------------------------------------

-- The next item an order still needs, or nil when every line is ticked off.
function Crafter.NextItem(order)
    for _, it in ipairs(order and order.items or {}) do
        if not it.cut then return it end
    end
    return nil
end

-- Someone whose mats are already in your bags is ahead of someone standing in the
-- group, who is ahead of someone who only asked. Ties go to the older order, so the
-- queue stays fair.
local STATUS_RANK = { mats = 1, grouped = 2, pending = 3 }

-- Which open order a profession window should serve: one of its own book's orders
-- that is still waiting on a craft.
function Crafter.PickOrder(orders, profKey)
    local best, bestRank
    for _, o in ipairs(orders or {}) do
        if (o.profession or profKey) == profKey and Crafter.NextItem(o) then
            local rank = STATUS_RANK[o.status] or 4
            if not best or rank < bestRank
                or (rank == bestRank and (o.createdAt or 0) < (best.createdAt or 0)) then
                best, bestRank = o, rank
            end
        end
    end
    return best
end

-- How many times to press Create. A recipe that makes five per craft needs one
-- craft for an order of five, and there is no point offering more crafts than the
-- mats on hand allow. Returns what to enter and what the order actually wants.
function Crafter.CraftCount(qty, numMade, available)
    local per = (numMade and numMade > 0) and numMade or 1
    local wanted = math.ceil((qty or 1) / per)
    if available and available > 0 and available < wanted then
        return available, wanted
    end
    return wanted, wanted
end

--------------------------------------------------------------------------------
-- The open window
--------------------------------------------------------------------------------

local function Walk(itemID)
    for i = 1, GetNumTradeSkills() do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType and skillType ~= "header" then
            local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
            local id = link and tonumber(link:match("|Hitem:(%d+)"))
            if id == itemID then return i end
        end
    end
    return nil
end

-- Where a product sits in the OPEN window, under whatever filters the player has
-- set. Nil means the recipe is not on screen: filtered out, or a different book.
--
-- The window only counts the children of expanded headers, so a recipe under a
-- collapsed category is missing rather than filtered. That is worth opening the
-- categories for, but only after looking without disturbing them.
function Crafter.FindIndex(itemID)
    if not itemID or not GetNumTradeSkills then return nil end
    local index = Walk(itemID)
    if index or not ExpandTradeSkillSubClass then return index end
    ExpandTradeSkillSubClass(0)
    return Walk(itemID)
end

-- Moves the window's selection. TradeSkillFrame_SetSelection is the FrameXML
-- function that also updates the detail pane; SelectTradeSkill alone would leave
-- the panel showing the previous recipe.
local function Select(index)
    if TradeSkillFrame_SetSelection and pcall(TradeSkillFrame_SetSelection, index) then
        if TradeSkillFrame_Update then pcall(TradeSkillFrame_Update) end
        return true
    end
    if SelectTradeSkill then
        return pcall(SelectTradeSkill, index)
    end
    return false
end

-- Selecting a recipe updates the detail pane but leaves the list where it was, so
-- the highlighted row can sit off-screen. Moving the scrollbar is what scrolls the
-- list: the faux scroll frame redraws from its value.
local function ScrollTo(index)
    local list = _G.TradeSkillListScrollFrame
    if not list or not FauxScrollFrame_SetOffset then return end
    -- A few rows of lead-in, so the selection is not jammed against the top edge.
    local offset = math.max(0, index - 4)
    pcall(FauxScrollFrame_SetOffset, list, offset)
    local bar = _G.TradeSkillListScrollFrameScrollBar
    if bar and bar.SetValue then
        pcall(bar.SetValue, bar, offset * (TRADE_SKILL_HEIGHT or 16))
    elseif TradeSkillFrame_Update then
        pcall(TradeSkillFrame_Update)
    end
end

-- Types the count into the create box, when this client has one.
local function SetCount(n)
    local box = _G.TradeSkillInputBox
    if box and box.HasFocus and box:HasFocus() then return false end
    if box and box.SetNumber then
        box:SetNumber(n)
        if box.ClearFocus then box:ClearFocus() end
        return true
    end
    return false
end

--[[
opts.manual   the player asked for this, so say something either way
opts.order    serve this order rather than picking one
]]
function Crafter.Focus(opts)
    opts = opts or {}
    if not ns.db or not ns.Enabled() then return end
    if ns.db.settings.orders.focusOnOpen == false and not opts.manual then return end

    local profile = ns.Prof.OpenWindow()
    if not profile then
        if opts.manual then ns.Print("open a profession window first.") end
        return
    end

    -- The order you are looking at in the Orders tab wins, as long as this window
    -- can actually make something on it.
    local order = opts.order
    if not order and ns.UI and ns.UI.selectedOrderID then
        local sel = ns.Orders.ByID(ns.UI.selectedOrderID)
        if sel and (sel.profession or profile.key) == profile.key and Crafter.NextItem(sel) then
            order = sel
        end
    end
    order = order or Crafter.PickOrder(ns.Orders.ActiveList(), profile.key)

    if not order then
        if opts.manual then
            ns.Print("no open order is waiting on " .. profile.name .. ".")
        end
        return
    end

    local it = Crafter.NextItem(order)
    local book = ns.Orders.BookFor(order)
    local entry = book[it.itemID] or {}

    local index = Crafter.FindIndex(it.itemID)
    if not index then
        ns.Print(string.format(
            "|cffffcc00order #%d needs %s|r, which is not in this window. Clear its search "
            .. "box or filters, then /tm craft.",
            order.id, entry.link or entry.name or ("item " .. tostring(it.itemID))))
        return
    end

    -- A recipe learned since the last scan is not in the book yet, so the open
    -- window is the better source for both the name and the batch size.
    local name = entry.link or entry.name
    local numMade = entry.numMade
    if not name and GetTradeSkillItemLink then name = GetTradeSkillItemLink(index) end
    if not numMade and GetTradeSkillNumMade then numMade = GetTradeSkillNumMade(index) end
    name = name or ("item " .. tostring(it.itemID))

    local _, _, available = GetTradeSkillInfo(index)
    local crafts, wanted = Crafter.CraftCount(it.qty, numMade, available)

    Select(index)
    ScrollTo(index)
    local typed = SetCount(crafts)

    local left = 0
    for _, other in ipairs(order.items) do
        if not other.cut then left = left + 1 end
    end

    ns.Print(string.format("|cff44ff44order #%d|r for %s: %s x%d, %s%s%s",
        order.id, order.player, name, it.qty or 1,
        typed and (crafts .. " to make") or ("make " .. crafts),
        crafts < wanted and string.format(" |cffff9900(mats for %d of %d)|r", crafts, wanted) or "",
        left > 1 and string.format("  |cff888888%d more on this order|r", left - 1) or ""))
end

--------------------------------------------------------------------------------
-- What this client actually provides
--------------------------------------------------------------------------------

-- Every call into the profession window is guarded, so a missing global makes the
-- helper do less rather than error. That is the right behaviour and a terrible way
-- to find out: /tm probe says which pieces are here and what each one costs when
-- it is not, with the window open.
local PROBE = {
    { "GetNumTradeSkills", "reading the list at all" },
    { "GetTradeSkillInfo", "recipe names and how many you can make" },
    { "GetTradeSkillItemLink", "matching a row to an order's item" },
    { "GetTradeSkillRecipeLink", "handing a customer the pattern with its reagents" },
    { "GetTradeSkillNumMade", "batch size for a recipe not in your book yet" },
    { "ExpandTradeSkillSubClass", "finding a recipe under a collapsed category" },
    { "TradeSkillFrame_SetSelection", "selecting the recipe" },
    { "TradeSkillFrame_Update", "redrawing after the selection" },
    { "SelectTradeSkill", "selecting the recipe (fallback)" },
    { "TradeSkillInputBox", "typing the craft count in for you" },
    { "TradeSkillListScrollFrame", "scrolling the list to the selection" },
    { "FauxScrollFrame_SetOffset", "scrolling the list to the selection" },
}

function Crafter.Probe()
    local missing = 0
    for _, row in ipairs(PROBE) do
        local name, why = row[1], row[2]
        local value = _G[name]
        if value then
            ns.Print(string.format("|cff44ff44yes|r  %s", name))
        else
            missing = missing + 1
            ns.Print(string.format("|cffff4444no |r  %s  |cff888888%s|r", name, why))
        end
    end

    local open = GetNumTradeSkills and GetNumTradeSkills() or 0
    if open > 0 then
        ns.Print(string.format("open window: %d rows, %s", open,
            GetTradeSkillLine and GetTradeSkillLine() or "?"))
        local box = _G.TradeSkillInputBox
        if box and box.GetNumber then
            ns.Print("create count box currently reads " .. tostring(box:GetNumber()))
        end
    else
        ns.Print("|cff888888open a profession window and run this again to test the list|r")
    end

    if missing == 0 then
        ns.Print("|cff44ff44everything the crafting helper uses is here.|r")
    end
end
