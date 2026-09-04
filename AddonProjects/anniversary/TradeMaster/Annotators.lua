local addonName, ns = ...

-- Row annotators replace a recipe's name in the profession window with what
-- the product actually does ("+8 Agility" instead of "Delicate Living Ruby").
-- Which annotator applies is a profile choice; professions without one get
-- nothing, and the toggle button stays hidden for them.

ns.Annotators = ns.Annotators or {}
local A = ns.Annotators

local scanTip = CreateFrame("GameTooltip", "TradeMasterScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

--------------------------------------------------------------------------------
-- Gem stats annotator (from CutMaster)
--------------------------------------------------------------------------------

local gemCache = {}

-- Works in any locale: "+8 Agility" always starts with a plus and a digit,
-- green is the game's universal colour for an equip effect, and a white line
-- with a percentage is a proc description.
local function IsStatLine(text, r, g, b)
    if not text or text == "" then return false end
    if text:match("^%+%d") then return true end
    if g > 0.9 and r < 0.2 and b < 0.2 then return true end
    if text:find("%%") and r > 0.9 and g > 0.9 and b > 0.9 then return true end
    return false
end

local function GemStats(link)
    if not link then return nil end
    local itemID = link:match("|Hitem:(%d+)")
    if not itemID then return nil end
    if gemCache[itemID] ~= nil then return gemCache[itemID] or nil end

    local classID = select(12, GetItemInfo(link))
    if classID ~= 3 then
        gemCache[itemID] = false
        return nil
    end

    scanTip:ClearLines()
    scanTip:SetHyperlink(link)

    local lines, firstLine = {}, nil
    for i = 2, scanTip:NumLines() do
        local left = _G["TradeMasterScanTipTextLeft" .. i]
        local text = left and left:GetText()
        if text then
            text = strtrim(text)
            if text ~= "" then
                firstLine = firstLine or text
                local r, g, b = left:GetTextColor()
                if IsStatLine(text, r, g, b) and not text:find("Requires at least", 1, true) then
                    lines[#lines + 1] = text
                end
            end
        end
    end
    if #lines == 0 and firstLine then lines[1] = firstLine end

    local result = #lines > 0 and table.concat(lines, ", ") or false
    gemCache[itemID] = result
    return result or nil
end

A.Registry = {
    gems = { name = "gem stats", For = GemStats },
}

local function AnnotatorFor(profile)
    return profile and profile.annotator and A.Registry[profile.annotator] or nil
end

-- Fill in annotations for a whole book. Cheap: the tooltip scan is cached.
function A.Annotate(profile, book)
    local an = AnnotatorFor(profile)
    if not an then return 0 end
    local n = 0
    for _, e in pairs(book) do
        if e.link and not e.stats then
            local s = an.For(e.link)
            if s then e.stats = s; n = n + 1 end
        end
    end
    return n
end

--------------------------------------------------------------------------------
-- Tradeskill window
--------------------------------------------------------------------------------

local hooked = false

local function Repaint()
    if not ns.db.settings.annotate then return end
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    local an = AnnotatorFor(ns.Prof.OpenWindow())
    if not an then return end

    local offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame) or 0
    local numSkills = GetNumTradeSkills() or 0
    local shown = TRADE_SKILLS_DISPLAYED or 8

    for i = 1, shown do
        local idx = i + offset
        local button = _G["TradeSkillSkill" .. i]
        if button and idx <= numSkills then
            local _, skillType = GetTradeSkillInfo(idx)
            if skillType ~= "header" then
                local text = an.For(GetTradeSkillItemLink(idx))
                if text then button:SetText(text) end
            end
        end
    end
end

function A.Hook()
    if hooked then return end
    if type(TradeSkillFrame_Update) ~= "function" then return end
    hooksecurefunc("TradeSkillFrame_Update", Repaint)
    hooked = true
end

local function UpdateButton()
    local b = A.button
    if not b then return end
    local on = ns.db.settings.annotate
    local tex = b:GetNormalTexture()
    if tex then
        tex:SetDesaturated(not on)
        tex:SetAlpha(on and 1 or 0.5)
    end
end

function A.Toggle()
    ns.db.settings.annotate = not ns.db.settings.annotate
    A.Hook()
    UpdateButton()
    if TradeSkillFrame_Update and TradeSkillFrame and TradeSkillFrame:IsShown() then
        TradeSkillFrame_Update()
    end
    local an = AnnotatorFor(ns.Prof.OpenWindow()) or AnnotatorFor(ns.Prof.Current())
    ns.Print((an and an.name or "annotations") .. " in the profession window "
        .. (ns.db.settings.annotate and "|cff44ff44on|r" or "|cffff4444off|r"))
end

function A.CreateButton()
    if A.button or not TradeSkillFrame then return end

    local b = CreateFrame("Button", "TradeMasterAnnotateToggle", TradeSkillFrame)
    b:SetSize(26, 26)
    b:SetPoint("TOPRIGHT", TradeSkillFrame, "TOPRIGHT", -52, -12)
    b:SetNormalTexture("Interface\\AddOns\\TradeMaster\\TradeMaster.tga")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b:SetScript("OnClick", A.Toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TradeMaster")
        local an = AnnotatorFor(ns.Prof.OpenWindow())
        GameTooltip:AddLine(ns.db.settings.annotate
            and ("|cff44ff44Showing " .. (an and an.name or "annotations") .. "|r")
            or "|cffff4444Showing names|r")
        GameTooltip:AddLine("|cff888888Click to switch|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    A.button = b
    UpdateButton()
end

function A.OnTradeSkillShow()
    A.Hook()
    A.CreateButton()
    if A.button then
        A.button:SetShown(AnnotatorFor(ns.Prof.OpenWindow()) ~= nil)
        UpdateButton()
    end
end
