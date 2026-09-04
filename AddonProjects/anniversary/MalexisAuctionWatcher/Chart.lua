-- Chart.lua - Minimal texture-based range bar chart
local MAWChart = {}

local COLOR_NEUTRAL = { 0.55, 0.65, 0.85 }
local COLOR_BEST = { 0.35, 0.9, 0.35 }
local COLOR_WORST = { 0.95, 0.35, 0.35 }
local COLOR_EMPTY = { 0.3, 0.3, 0.3 }
local COLOR_EXTERNAL = { 0.8, 0.7, 0.4 }

local LEFT_MARGIN = 78
local BOTTOM_MARGIN = 18
local TOP_MARGIN = 8
local RIGHT_MARGIN = 8
local GRIDLINES = 4

-- The coin API refuses a negative, and the recipe view's margin is negative
-- whenever a craft loses money, so the sign is carried here rather than by every
-- caller.
local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    if _G.MalexisAuctionWatcherHelpers then
        return sign .. _G.MalexisAuctionWatcherHelpers.FormatMoney(copper)
    end
    return sign .. tostring(math.floor(copper))
end

local ChartMixin = {}

function ChartMixin:AcquireBar(index)
    local bar = self.bars[index]
    if bar then
        return bar
    end

    bar = CreateFrame("Button", nil, self.plot)
    bar.range = bar:CreateTexture(nil, "ARTWORK")
    bar.avg = bar:CreateTexture(nil, "OVERLAY")
    bar.avg:SetColorTexture(1, 1, 1, 0.9)
    bar.avg:SetHeight(2)

    bar:SetScript("OnEnter", function(b)
        local p = b.point
        if not p then return end
        -- Anchor to the visible candle, not the full-height hit area
        GameTooltip:SetOwner(b, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        -- Anchor to the visible candle, or to the slot itself when there is none
        GameTooltip:SetPoint("BOTTOM", b.noBars and b or b.range, "TOP", 0, 6)
        GameTooltip:AddLine(b.tooltipTitle or p.label)
        if not b.noBars then
            if p.n and p.n > 0 then
                GameTooltip:AddDoubleLine("Low", FormatMoney(p.low), 1, 1, 1, 0.5, 1, 0.5)
                GameTooltip:AddDoubleLine("Average", FormatMoney(p.avg), 1, 1, 1, 1, 1, 0.5)
                GameTooltip:AddDoubleLine("High", FormatMoney(p.high), 1, 1, 1, 1, 0.5, 0.5)
                GameTooltip:AddDoubleLine("Samples", tostring(p.n), 1, 1, 1, 0.8, 0.8, 0.8)
                if p.src then
                    local MAW = _G.MalexisAuctionWatcher
                    local name = (MAW and MAW.SourceLabel) and MAW:SourceLabel(p.src) or p.src
                    GameTooltip:AddDoubleLine("Source", name, 1, 1, 1, 0.9, 0.7, 0.4)
                end
            else
                GameTooltip:AddLine("No data", 0.6, 0.6, 0.6)
            end
        end
        -- Every line's value for this slot, including the ones that are listed but
        -- not drawn (the margin), so hovering answers the whole question.
        if b.lines and #b.lines > 0 then
            GameTooltip:AddLine(" ")
            for _, line in ipairs(b.lines) do
                local v = line.values and line.values[b.slot]
                local c = line.color or { 1, 1, 1 }
                GameTooltip:AddDoubleLine(line.label or "", v and FormatMoney(v) or "no data",
                    1, 1, 1, c[1], c[2], c[3])
            end
        end
        -- Levels rather than series: a TSM average is one number for the whole
        -- chart, so it belongs in every slot's tooltip and in none of the lines.
        if b.tooltipRows and #b.tooltipRows > 0 then
            GameTooltip:AddLine(" ")
            for _, r in ipairs(b.tooltipRows) do
                local c = r.color or { 0.8, 0.8, 0.8 }
                GameTooltip:AddDoubleLine(r.label or "", r.value and FormatMoney(r.value) or "-",
                    0.7, 0.7, 0.7, c[1], c[2], c[3])
            end
        end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.bars[index] = bar
    return bar
end

-- A line is drawn as steps: a flat run across each slot, and an upright joining
-- one run to the next. Every piece is axis-aligned, because the only way to slope
-- a texture here is to supply artwork that is already sloped -- SetRotation turns
-- the picture inside the rectangle, and a rectangle filled with one colour looks
-- exactly the same turned. Steps also say the right thing: a value holds for the
-- whole bucket, it is not a reading taken at one instant inside it.
function ChartMixin:AcquireSegment(index)
    local seg = self.segments[index]
    if seg then return seg end
    seg = self.plot:CreateTexture(nil, "OVERLAY")
    self.segments[index] = seg
    return seg
end

function ChartMixin:AcquireLabel(index)
    local label = self.xLabels[index]
    if label then
        return label
    end
    label = self.plot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetTextColor(0.7, 0.7, 0.7)
    self.xLabels[index] = label
    return label
end

-- points: { {label, low, avg, high, n, src}, ... }
-- opts: { highlight = { best = i, worst = i }, maxLabels = n, tooltipTitle = fn(point),
--         refLines = { {value, label, color} }, markerIndex, markerLabel,
--         noBars = true,   -- keep the slots and their hover targets, draw no candles
--         lines = { { label, color, width, values = { [slot] = value }, plot } },
--         tooltipRows = { { label, value, color } } }
-- A reference line with subtle = true is drawn thin and unlabelled across the
-- plot only: one per piece of a recipe would otherwise be a wall of captions.
-- Lines are drawn as steps: a value holds across its whole slot.
-- A line's values may have holes; plot = false lists it in the tooltip without
-- drawing it, which is how the margin is shown without inventing a scale for it.
function ChartMixin:SetData(points, opts)
    opts = opts or {}
    local plotW = self:GetWidth() - LEFT_MARGIN - RIGHT_MARGIN
    local plotH = self:GetHeight() - TOP_MARGIN - BOTTOM_MARGIN
    self.plot:SetSize(math.max(plotW, 1), math.max(plotH, 1))

    -- Value range
    local minV, maxV
    for _, p in ipairs(points) do
        if p.n and p.n > 0 then
            if not minV or p.low < minV then minV = p.low end
            if not maxV or p.high > maxV then maxV = p.high end
        end
    end
    -- Lines carry their own values, and a lines-only chart has no bars to take a
    -- scale from. Counted as data, unlike reference lines, because they are data.
    for _, line in ipairs(opts.lines or {}) do
        if line.plot ~= false then
            for _, v in pairs(line.values or {}) do
                if not minV or v < minV then minV = v end
                if not maxV or v > maxV then maxV = v end
            end
        end
    end
    local hasData = minV ~= nil
    -- Reference lines widen the range so they are drawn at their real value
    for _, ref in ipairs(opts.refLines or {}) do
        if ref.value and ref.value > 0 then
            if not minV or ref.value < minV then minV = ref.value end
            if not maxV or ref.value > maxV then maxV = ref.value end
        end
    end
    if not minV then
        minV, maxV = 0, 1
    end
    -- Pad the range so bars don't touch the edges, and never start below zero
    local pad = (maxV - minV) * 0.1
    if pad == 0 then pad = math.max(maxV * 0.1, 1) end
    minV = math.max(0, minV - pad)
    maxV = maxV + pad
    local range = maxV - minV

    local function YFor(value)
        return ((value - minV) / range) * plotH
    end

    -- Gridlines and y labels
    for i = 0, GRIDLINES do
        local line = self.grid[i]
        local text = self.yLabels[i]
        local frac = i / GRIDLINES
        local y = frac * plotH
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
        line:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)
        text:ClearAllPoints()
        text:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -4, y)
        text:SetText(hasData and FormatMoney(minV + frac * range) or "")
    end

    -- Bars
    local count = #points
    local slotW = count > 0 and (plotW / count) or plotW
    local barW = math.max(2, math.floor(slotW * 0.7))
    local maxLabels = opts.maxLabels or count
    local labelEvery = math.max(1, math.ceil(count / maxLabels))
    local highlight = opts.highlight or {}

    for i, p in ipairs(points) do
        local bar = self:AcquireBar(i)
        bar.point = p
        bar.tooltipTitle = opts.tooltipTitle and opts.tooltipTitle(p) or nil
        local x = (i - 1) * slotW + (slotW - barW) / 2
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
        bar:SetSize(barW, plotH)

        bar.noBars = opts.noBars
        bar.lines = opts.lines
        bar.tooltipRows = opts.tooltipRows
        bar.slot = i

        bar.range:ClearAllPoints()
        bar.avg:ClearAllPoints()
        if opts.noBars then
            bar.range:Hide()
            bar.avg:Hide()
        elseif p.n and p.n > 0 then
            local yLow = YFor(p.low)
            local yHigh = YFor(p.high)
            local h = math.max(2, yHigh - yLow)
            bar.range:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, yLow)
            bar.range:SetSize(barW, h)

            local c = COLOR_NEUTRAL
            if highlight.best == i then
                c = COLOR_BEST
            elseif highlight.worst == i then
                c = COLOR_WORST
            elseif p.src and p.src ~= "scan" then
                c = COLOR_EXTERNAL
            end
            bar.range:SetColorTexture(c[1], c[2], c[3], 0.85)

            bar.avg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, YFor(p.avg) - 1)
            bar.avg:SetWidth(barW)
            bar.avg:Show()
            bar.range:Show()
        else
            bar.range:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            bar.range:SetSize(barW, 2)
            bar.range:SetColorTexture(COLOR_EMPTY[1], COLOR_EMPTY[2], COLOR_EMPTY[3], 0.6)
            bar.range:Show()
            bar.avg:Hide()
        end
        bar:Show()

        local label = self:AcquireLabel(i)
        label:ClearAllPoints()
        label:SetPoint("TOP", bar, "BOTTOM", 0, -2)
        if (i - 1) % labelEvery == 0 then
            label:SetText(p.label or "")
            label:Show()
        else
            label:Hide()
        end
    end

    -- Hide leftovers from a previous, larger data set
    for i = count + 1, #self.bars do
        self.bars[i]:Hide()
        if self.xLabels[i] then self.xLabels[i]:Hide() end
    end

    -- Lines. A slot with no value draws nothing and joins to nothing, so a gap in
    -- the data stays a gap rather than a line running confidently through it.
    local usedSegments = 0
    local function Piece(x, y, w, h, color, sublevel)
        usedSegments = usedSegments + 1
        local seg = self:AcquireSegment(usedSegments)
        seg:SetDrawLayer("OVERLAY", sublevel)
        seg:SetColorTexture(color[1], color[2], color[3], 0.95)
        seg:SetSize(math.max(w, 1), math.max(h, 1))
        seg:ClearAllPoints()
        seg:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, y)
        seg:Show()
    end

    for li, line in ipairs(opts.lines or {}) do
        if line.plot ~= false then
            local color = line.color or COLOR_NEUTRAL
            local width = line.width or 1
            -- Later lines sit on top: the caller passes the thin material lines
            -- first and the two bold ones last.
            local sublevel = math.min(7, li)
            local prevY
            for i = 1, count do
                local v = line.values and line.values[i]
                if v then
                    local y = YFor(v)
                    local left = (i - 1) * slotW
                    Piece(left, y - width / 2, slotW, width, color, sublevel)
                    if prevY then
                        -- The upright joining the two runs, on the slot boundary.
                        local lo, hi = math.min(prevY, y), math.max(prevY, y)
                        Piece(left - width / 2, lo, width, hi - lo, color, sublevel)
                    end
                    prevY = y
                else
                    prevY = nil
                end
            end
        end
    end
    for i = usedSegments + 1, #self.segments do
        self.segments[i]:Hide()
    end

    -- Reference lines (horizontal, e.g. TSM averages)
    local refs = opts.refLines or {}
    local LABEL_H = 12
    local placedLabelYs = {}
    -- The highest line gets its label above; every other line's label goes below its line
    local topValue
    for _, ref in ipairs(refs) do
        if ref.value and ref.value > 0 and (not topValue or ref.value > topValue) then
            topValue = ref.value
        end
    end
    local function LabelCollides(y)
        for _, other in ipairs(placedLabelYs) do
            if math.abs(other - y) < LABEL_H then
                return true
            end
        end
        return false
    end

    for i, ref in ipairs(refs) do
        local line = self.refLines[i]
        if not line then
            line = {}
            line.tex = self.plot:CreateTexture(nil, "OVERLAY")
            line.tex:SetHeight(1)
            line.text = self.plot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            self.refLines[i] = line
        end
        local c = ref.color or { 0.9, 0.6, 0.9 }
        line.tex:SetColorTexture(c[1], c[2], c[3], ref.subtle and 0.55 or 0.9)
        line.text:SetTextColor(c[1], c[2], c[3])

        if ref.value and ref.value > 0 and ref.subtle then
            local y = math.max(0, math.min(plotH, YFor(ref.value)))
            line.tex:ClearAllPoints()
            line.tex:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, y)
            line.tex:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)
            line.tex:Show()
            line.text:Hide()
        elseif ref.value and ref.value > 0 then
            local y = math.max(0, math.min(plotH, YFor(ref.value)))
            -- Span the full chart width, through the y-axis margin, so the line reads as a level
            line.tex:ClearAllPoints()
            line.tex:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 2, BOTTOM_MARGIN + y)
            line.tex:SetPoint("BOTTOMRIGHT", self.plot, "BOTTOMRIGHT", 0, y)

            -- Highest line: label above. Others: label below, stepping down if it collides.
            local labelY
            if ref.value == topValue and y + 1 + LABEL_H <= plotH and not LabelCollides(y + 1) then
                labelY = y + 1
            else
                labelY = y - LABEL_H
                while LabelCollides(labelY) and labelY > 0 do
                    labelY = labelY - LABEL_H
                end
            end
            table.insert(placedLabelYs, labelY)

            line.text:ClearAllPoints()
            line.text:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 4, BOTTOM_MARGIN + labelY)
            line.text:SetText((ref.label or "") .. " " .. FormatMoney(ref.value))
            line.tex:Show()
            line.text:Show()
        else
            line.tex:Hide()
            line.text:Hide()
        end
    end
    for i = #refs + 1, #self.refLines do
        self.refLines[i].tex:Hide()
        self.refLines[i].text:Hide()
    end

    -- Today marker. One line on the wrap edge left it ambiguous which of the two
    -- buckets either side of it was the current one, so the bucket is bracketed:
    -- a line down each edge with a faint band between them. The band sits on
    -- BORDER, under the bars, so it tints the slot without dimming the data.
    if opts.markerIndex and opts.markerIndex >= 1 and opts.markerIndex <= count then
        local right = opts.markerIndex * slotW
        local left = math.max(0, right - slotW)

        self.marker:ClearAllPoints()
        self.marker:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", right - 1, 0)
        self.marker:SetHeight(plotH)
        self.marker:Show()

        self.markerStart:ClearAllPoints()
        self.markerStart:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", left, 0)
        self.markerStart:SetHeight(plotH)
        self.markerStart:Show()

        self.markerBand:ClearAllPoints()
        self.markerBand:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", left, 0)
        self.markerBand:SetSize(math.max(1, right - left), plotH)
        self.markerBand:Show()

        self.markerText:ClearAllPoints()
        -- The label goes outside the bracket, on whichever side has room.
        if opts.markerIndex > count / 2 then
            self.markerText:SetPoint("TOPRIGHT", self.plot, "BOTTOMLEFT", left - 3, plotH - 2)
        else
            self.markerText:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", right + 3, plotH - 2)
        end
        self.markerText:SetText(opts.markerLabel or "Today")
        self.markerText:Show()
    else
        self.marker:Hide()
        self.markerStart:Hide()
        self.markerBand:Hide()
        self.markerText:Hide()
    end

    self.emptyText:SetShown(not hasData)
end

function MAWChart.Create(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    Mixin(frame, ChartMixin)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.8)

    frame.plot = CreateFrame("Frame", nil, frame)
    frame.plot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_MARGIN, BOTTOM_MARGIN)

    frame.grid = {}
    frame.yLabels = {}
    for i = 0, GRIDLINES do
        local line = frame.plot:CreateTexture(nil, "BORDER")
        line:SetColorTexture(0.35, 0.35, 0.4, 0.5)
        line:SetHeight(1)
        frame.grid[i] = line
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetTextColor(0.7, 0.7, 0.7)
        frame.yLabels[i] = text
    end

    frame.refLines = {}

    -- Vertical "Today" marker for cyclic views (day of month, weekday, hour).
    -- Two lines and a band, so the current bucket is the one between them.
    frame.marker = frame.plot:CreateTexture(nil, "OVERLAY")
    frame.marker:SetWidth(2)
    frame.marker:SetColorTexture(1, 0.85, 0.3, 0.9)
    frame.marker:Hide()
    frame.markerStart = frame.plot:CreateTexture(nil, "OVERLAY")
    frame.markerStart:SetWidth(2)
    frame.markerStart:SetColorTexture(1, 0.85, 0.3, 0.9)
    frame.markerStart:Hide()
    frame.markerBand = frame.plot:CreateTexture(nil, "BORDER")
    frame.markerBand:SetColorTexture(1, 0.85, 0.3, 0.10)
    frame.markerBand:Hide()
    frame.markerText = frame.plot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.markerText:SetTextColor(1, 0.85, 0.3)
    frame.markerText:Hide()

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.emptyText:SetPoint("CENTER")
    frame.emptyText:SetText("No price history yet")
    frame.emptyText:SetTextColor(0.6, 0.6, 0.6)
    frame.emptyText:Hide()

    frame.bars = {}
    frame.xLabels = {}
    frame.segments = {}

    return frame
end

_G.MalexisAuctionWatcherChart = MAWChart
