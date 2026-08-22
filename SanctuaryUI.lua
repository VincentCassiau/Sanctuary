-- ============================================================================
-- SanctuaryUI.lua -- the window, rebuilt around the four questions.
--
-- Pure Lua, no XML, no embedded library, and no Blizzard option template: every
-- checkbox, radio, scroll bar and tab below is drawn here. That is not taste --
-- the templates carry their own sizes and textures, and mixing them with this
-- layout is what made the previous window a patchwork.
--
-- The interface owns pixels and nothing else. Every decision, every list write
-- and the protection toggle itself live in Sanctuary.lua, so the harness can
-- prove them without a game client and this file can never hold a second
-- version of the rule.
-- ============================================================================

local ADDON_NAME, ns = ...
local L = ns.L

-- ============================================================================
-- SECTION 1: Palette, metrics, small helpers
-- ============================================================================

-- Transposed from the validated mock-ups (maquettes/cible2.py). One appearance,
-- "Moderne": the dark palette the add-on already used.
local C = {
    panel      = { 0.051, 0.051, 0.102, 0.97 },
    header     = { 0.078, 0.078, 0.149, 1.00 },
    border     = { 0.302, 0.302, 0.400, 0.85 },
    ink        = { 1.000, 1.000, 1.000, 1.00 },
    dim        = { 0.604, 0.604, 0.667, 1.00 },
    soft       = { 0.749, 0.749, 0.800, 1.00 },
    accent     = { 0.400, 0.600, 1.000, 1.00 },
    accentBg   = { 0.400, 0.600, 1.000, 0.12 },
    green      = { 0.400, 0.902, 0.400, 1.00 },
    greenBg    = { 0.157, 0.470, 0.157, 0.28 },
    red        = { 1.000, 0.420, 0.420, 1.00 },
    orange     = { 1.000, 0.600, 0.200, 1.00 },
    tile       = { 0.078, 0.078, 0.141, 0.60 },
    input      = { 0.102, 0.102, 0.149, 0.92 },
    button     = { 0.149, 0.149, 0.251, 1.00 },
    buttonHot  = { 0.220, 0.220, 0.345, 1.00 },
    tabOff     = { 0.047, 0.047, 0.086, 0.90 },
    disabled   = { 0.380, 0.380, 0.420, 1.00 },
}

-- 16 / 14 / 13 / 12, the hierarchy Vincent asked for.
local FONT_TITLE, FONT_SECTION, FONT_DESC, FONT_BODY = 16, 14, 13, 12

local FRAME_WIDTH = 780
local MIN_HEIGHT, MAX_HEIGHT = 380, 700
local HEADER_HEIGHT = 40
local TAB_HEIGHT = 22
local PAD = 18
local PANEL_WIDTH = 540
-- Room kept under the content for the tabs' own strip and the undo line, which
-- are anchored to the bottom of the frame.
local CONTENT_BOTTOM = 30
-- What the whole window may measure, header and bottom strip included. Only the
-- height is negotiable: the scroll area and every tab frame are built at
-- FRAME_WIDTH and nothing in the window scrolls sideways, so any other width
-- either truncates the content or leaves it floating in the void.
local MIN_FRAME_HEIGHT = MIN_HEIGHT + HEADER_HEIGHT + CONTENT_BOTTOM
local MAX_FRAME_HEIGHT = MAX_HEIGHT + HEADER_HEIGHT + CONTENT_BOTTOM
local UNDO_SECONDS = 6
local LIST_REFRESH_SECONDS = 10

local function applyBackdrop(frame, bg, border, edgeSize)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = border and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = edgeSize or 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if bg then frame:SetBackdropColor(unpack(bg)) end
    if border then frame:SetBackdropBorderColor(unpack(border)) end
end

local function newLabel(parent, text, size, color, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontFile = label:GetFont()
    label:SetFont(fontFile, size or FONT_BODY, "")
    label:SetTextColor(unpack(color or C.ink))
    label:SetText(text or "")
    label:SetJustifyH(justify or "LEFT")
    return label
end

local function setTooltip(frame, text)
    if not text or text == "" then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function formatDate(stamp)
    if not stamp then return "?" end
    local ok, text = pcall(date, L["DATE_TIME_FORMAT"], stamp)
    return ok and text or "?"
end

-- ============================================================================
-- SECTION 2: The component library
-- ============================================================================

-- Button, in two flavours: normal, and destructive (red border).
local function newButton(parent, name, text, width, height, onClick, destructive)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 24)
    local border = destructive and C.red or C.border
    applyBackdrop(btn, C.button, border)
    btn.label = newLabel(btn, text, FONT_BODY, destructive and C.red or C.ink, "CENTER")
    btn.label:SetPoint("CENTER")
    btn:SetScript("OnEnter", function(self) applyBackdrop(self, C.buttonHot, C.accent) end)
    btn:SetScript("OnLeave", function(self) applyBackdrop(self, C.button, border) end)
    if onClick then btn:SetScript("OnClick", onClick) end
    return btn
end

-- Check. The model is the source of truth, never the widget: the box is drawn
-- from `get()` on every refresh, so a value the core resolves differently from
-- what is stored (the recommended preset does exactly that) can never leave a
-- stale tick on screen.
local function newCheck(parent, name, text, tooltip, get, set)
    local frame = CreateFrame("CheckButton", name, parent)
    frame:SetSize(18, 18)
    applyBackdrop(frame, C.input, C.border)
    frame.mark = frame:CreateTexture(nil, "OVERLAY")
    frame.mark:SetPoint("CENTER")
    frame.mark:SetSize(10, 10)
    frame.mark:SetColorTexture(unpack(C.accent))

    frame.label = newLabel(parent, text, FONT_BODY, C.soft)
    frame.label:SetPoint("LEFT", frame, "RIGHT", 8, 0)

    frame.get, frame.set = get, set
    frame.enabled = true

    function frame:Refresh()
        local on = self.get and self.get() and true or false
        self:SetChecked(on)
        if self.mark then
            if on then self.mark:Show() else self.mark:Hide() end
        end
        self.label:SetTextColor(unpack(self.enabled and C.soft or C.disabled))
        applyBackdrop(self, C.input, self.enabled and C.border or C.disabled)
    end

    function frame:SetEnabledState(enabled)
        self.enabled = enabled and true or false
        self:Refresh()
    end

    frame:SetScript("OnClick", function(self)
        if not self.enabled then return end
        local current = self.get and self.get() and true or false
        if self.set then self.set(not current) end
        PlaySound(current and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.refreshUI then ns.refreshUI() end
    end)
    setTooltip(frame, tooltip)
    return frame
end

-- Radio, same contract as Check: drawn from the model, writes through `set`.
local function newRadio(parent, name, text, tooltip, isOn, select)
    local frame = CreateFrame("Button", name, parent)
    frame:SetSize(16, 16)
    applyBackdrop(frame, C.input, C.border)
    frame.mark = frame:CreateTexture(nil, "OVERLAY")
    frame.mark:SetPoint("CENTER")
    frame.mark:SetSize(8, 8)
    frame.mark:SetColorTexture(unpack(C.accent))

    frame.label = newLabel(parent, text, FONT_BODY, C.soft)
    frame.label:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    frame.enabled = true

    function frame:Refresh()
        local on = isOn() and true or false
        if self.mark then
            if on then self.mark:Show() else self.mark:Hide() end
        end
        self.label:SetTextColor(unpack(self.enabled and C.soft or C.disabled))
    end

    function frame:SetEnabledState(enabled)
        self.enabled = enabled and true or false
        self:Refresh()
    end

    frame:SetScript("OnClick", function(self)
        if not self.enabled then return end
        select()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.refreshUI then ns.refreshUI() end
    end)
    setTooltip(frame, tooltip)
    return frame
end

-- Card: an exclusive choice with a title and a description. Clicking anywhere
-- on it selects it -- the whole card is the target, not a 16-pixel dot.
local function newCard(parent, name, titleText, descText, width, isOn, select)
    local card = CreateFrame("Button", name, parent, "BackdropTemplate")
    card:SetSize(width or 340, 74)
    card.enabled = true

    card.title = newLabel(card, titleText, FONT_DESC, C.ink)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.desc = newLabel(card, descText, FONT_BODY, C.dim)
    card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.desc:SetWidth((width or 340) - 24)
    card.desc:SetJustifyH("LEFT")

    function card:Refresh()
        local on = isOn() and true or false
        if not self.enabled then
            applyBackdrop(self, C.tile, C.border)
            self.title:SetTextColor(unpack(C.disabled))
            self.desc:SetTextColor(unpack(C.disabled))
            return
        end
        applyBackdrop(self, on and C.accentBg or C.tile, on and C.accent or C.border)
        self.title:SetTextColor(unpack(on and C.accent or C.ink))
        self.desc:SetTextColor(unpack(C.dim))
    end

    function card:SetEnabledState(enabled)
        self.enabled = enabled and true or false
        self:Refresh()
    end

    card:SetScript("OnClick", function(self)
        if not self.enabled then return end
        select()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.refreshUI then ns.refreshUI() end
    end)
    return card
end

-- Input with a grey hint. The hint is a separate FontString rather than
-- pre-filled text: pre-filled text gets submitted by someone who does not read.
local function newInput(parent, name, width, hintText, onEnter)
    local box = CreateFrame("EditBox", name, parent, "BackdropTemplate")
    box:SetSize(width or 220, 24)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    applyBackdrop(box, C.input, C.border)

    box.hint = newLabel(box, hintText, FONT_BODY, C.dim)
    box.hint:SetPoint("LEFT", box, "LEFT", 7, 0)

    function box:RefreshHint()
        local text = self:GetText()
        if text and text ~= "" then self.hint:Hide() else self.hint:Show() end
    end

    box:SetScript("OnTextChanged", function(self) self:RefreshHint() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onEnter then
        box:SetScript("OnEnterPressed", function(self)
            onEnter(self:GetText())
            self:SetText("")
            self:RefreshHint()
        end)
    end
    return box
end

-- One pool per panel. A chip is reparented for free in the client, but keeping
-- pools apart also keeps a panel's redraw from borrowing widgets anchored in the
-- other one -- which is how a list ends up half-empty after a switch.
local chipPools = setmetatable({}, { __mode = "k" })

-- Chip: one name, a cross, a tooltip carrying the date and the origin. Pooled,
-- because a Battle.net list is fifty-six of them and a redraw must not allocate.
local function newChip(parent)
    local pool = chipPools[parent]
    if not pool then
        pool = {}
        chipPools[parent] = pool
    end
    local chip = table.remove(pool)
    if chip then
        chip:SetParent(parent)
        chip:Show()
        return chip
    end
    chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    chip:SetSize(120, 22)
    applyBackdrop(chip, C.tile, C.border)
    chip.label = newLabel(chip, "", FONT_BODY, C.soft)
    chip.label:SetPoint("LEFT", chip, "LEFT", 8, 0)
    chip.remove = CreateFrame("Button", nil, chip)
    chip.remove:SetSize(16, 16)
    chip.remove:SetPoint("RIGHT", chip, "RIGHT", -4, 0)
    chip.remove.label = newLabel(chip.remove, "x", FONT_BODY, C.dim, "CENTER")
    chip.remove.label:SetPoint("CENTER")
    return chip
end

-- Scroll: a thin bar of our own, hidden when the content fits, and a wheel that
-- works whether or not the bar is there.
local function newScroll(parent, name, width, height)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:SetSize(width, height)
    local child = CreateFrame("Frame", name and (name .. "Child") or nil, scroll)
    child:SetSize(width, height)
    scroll:SetScrollChild(child)
    scroll.child = child

    local bar = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    bar:SetSize(4, height)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    applyBackdrop(bar, C.border, nil)
    bar:Hide()
    scroll.bar = bar

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, (self.child:GetHeight() or 0) - (self:GetHeight() or 0))
        local offset = math.min(range, math.max(0, (self.offset or 0) - delta * 24))
        self.offset = offset
        self:SetVerticalScroll(offset)
    end)

    function scroll:RefreshBar()
        local range = (self.child:GetHeight() or 0) - (self:GetHeight() or 0)
        if range > 1 then self.bar:Show() else self.bar:Hide() end
    end
    return scroll
end

-- Section: a title, a count, a rule, and an optional description underneath.
local function newSection(parent, titleText, descText, width)
    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(width, 40)
    section.title = newLabel(section, titleText, FONT_SECTION, C.ink)
    section.title:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
    section.count = newLabel(section, "", FONT_BODY, C.dim)
    section.count:SetPoint("LEFT", section.title, "RIGHT", 8, 0)
    section.rule = section:CreateTexture(nil, "ARTWORK")
    section.rule:SetHeight(1)
    section.rule:SetPoint("TOPLEFT", section.title, "BOTTOMLEFT", 0, -6)
    section.rule:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -6)
    section.rule:SetColorTexture(unpack(C.border))
    if descText then
        section.desc = newLabel(section, descText, FONT_BODY, C.dim)
        section.desc:SetPoint("TOPLEFT", section.rule, "BOTTOMLEFT", 0, -6)
        section.desc:SetWidth(width)
    end
    return section
end

-- ============================================================================
-- SECTION 3: State shared by the screens
-- ============================================================================

local mainFrame, contentFrame, contentScroll, stateButton, resizeGrip
local tabFrames, tabButtons = {}, {}
local activeTab = "protection"
local manualSize = nil
local refreshTab = {}
local undoState = nil
local undoLine
local listTicker = nil
local openPanel = nil
local activeChips = {}
local diagnosticResults = {}
local strandedPopups = {}

local TAB_DEFS = {
    { key = "protection",  labelKey = "TAB_PROTECTION" },
    { key = "journal",     labelKey = "TAB_JOURNAL" },
    { key = "advanced",    labelKey = "TAB_ADVANCED" },
    { key = "about",       labelKey = "TAB_ABOUT" },
    { key = "diagnostics", labelKey = "TAB_DIAGNOSTICS", debugOnly = true },
}

local function isTabVisible(def)
    if not def or not def.debugOnly then return true end
    return (SanctuaryDB and SanctuaryDB.debugEnabled) and true or false
end

local function tabDefByKey(key)
    for _, def in ipairs(TAB_DEFS) do
        if def.key == key then return def end
    end
    return nil
end

local function setFilter(key, value)
    if not SanctuaryDB then return end
    SanctuaryDB.filters[key] = value
    if ns.refreshInviteSoundMuteState then ns.refreshInviteSoundMuteState() end
end

local function filterStored(key)
    return SanctuaryDB and SanctuaryDB.filters[key]
end

-- ============================================================================
-- SECTION 4: Undo line
-- ============================================================================

-- One pending removal at a time. A second removal replaces the first: two undo
-- offers stacked on one line would be ambiguous about which name they undo.
local function clearUndo()
    undoState = nil
    if undoLine then undoLine:Hide() end
end

local function offerUndo(labelText, restore)
    undoState = { restore = restore, at = GetTime() }
    local mine = undoState
    if undoLine then
        undoLine.label:SetText(string.format(L["UNDO_REMOVED"], labelText))
        undoLine:Show()
    end
    C_Timer.After(UNDO_SECONDS, function()
        if undoState == mine then clearUndo() end
    end)
end

-- ============================================================================
-- SECTION 5: Protection screen
-- ============================================================================

local protection = {}

local function buildProtectionTab(parent)
    protection.frame = parent
    local width = FRAME_WIDTH - PAD * 2
    local y = 0

    local function stepTitle(text, number)
        local head = newLabel(parent, number .. "   " .. text, FONT_SECTION, C.accent)
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        y = y - 24
        return head
    end

    -- Question 1 ------------------------------------------------------------
    stepTitle(L["Q1_TITLE"], "1")
    local cardWidth = (width - 16) / 2
    protection.q1Strangers = newCard(parent, "SanctuaryQ1_strangers",
        L["Q1_STRANGERS_TITLE"], L["Q1_STRANGERS_DESC"], cardWidth,
        function() return ns.getScope() == "strangers" end,
        function() setFilter("scope", "strangers") end)
    protection.q1Strangers:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    protection.q1Blocked = newCard(parent, "SanctuaryQ1_blockedOnly",
        L["Q1_BLOCKEDONLY_TITLE"], L["Q1_BLOCKEDONLY_DESC"], cardWidth,
        function() return ns.getScope() == "blockedOnly" end,
        function() setFilter("scope", "blockedOnly") end)
    protection.q1Blocked:SetPoint("TOPLEFT", protection.q1Strangers, "TOPRIGHT", 16, 0)
    y = y - 90

    -- Question 2 ------------------------------------------------------------
    protection.q2Title = stepTitle(L["Q2_TITLE"], "2")
    protection.q2All = newCard(parent, "SanctuaryQ2_all",
        L["Q2_ALL_TITLE"], L["Q2_ALL_DESC"], cardWidth,
        function() return ns.getPreset() == "all" end,
        function() setFilter("preset", "all") end)
    protection.q2All:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    protection.q2Custom = newCard(parent, "SanctuaryQ2_custom",
        L["Q2_CUSTOM_TITLE"], L["Q2_CUSTOM_DESC"], cardWidth,
        function() return ns.getPreset() == "custom" end,
        function() setFilter("preset", "custom") end)
    protection.q2Custom:SetPoint("TOPLEFT", protection.q2All, "TOPRIGHT", 16, 0)
    y = y - 84

    -- The enhanced-instance box is a single widget with two homes: under the two
    -- cards in "Everything", indented under "Block group invitations" in "I
    -- choose". Two widgets would mean two states to keep in step.
    protection.strict = newCheck(parent, "SanctuaryStrictCheck",
        L["FILTER_STRICT_GROUP_INVITE_SYSTEM"], L["TIP_STRICT_GROUP_INVITE_SYSTEM"],
        function() return filterStored("strictGroupInviteSystemMessages") == true end,
        function(value) setFilter("strictGroupInviteSystemMessages", value) end)
    protection.strictNote = newLabel(parent, L["STRICT_EXPERIMENTAL"], FONT_BODY, C.dim)

    -- The detailed boxes, folded away until "I choose" is picked.
    local choose = CreateFrame("Frame", "SanctuaryChoose", parent)
    choose:SetSize(width, 1)
    protection.choose = choose
    protection.checks = {}

    local CHECK_ROWS = {
        { key = "groupInvite", labelKey = "FILTER_GROUP_INVITE", tipKey = "TIP_GROUP_INVITE" },
        { key = "whisper",     labelKey = "FILTER_WHISPER",      tipKey = "TIP_WHISPER" },
        { key = "say",         labelKey = "FILTER_SAY",          tipKey = "TIP_SAY" },
        { key = "yell",        labelKey = "FILTER_YELL",         tipKey = "TIP_YELL" },
        { key = "emote",       labelKey = "FILTER_EMOTE",        tipKey = "TIP_EMOTE" },
        { key = "duel",        labelKey = "FILTER_DUEL",         tipKey = "TIP_DUEL" },
        { key = "trade",       labelKey = "FILTER_TRADE",        tipKey = "TIP_TRADE" },
        { key = "guildInvite", labelKey = "FILTER_GUILD_INVITE", tipKey = "TIP_GUILD_INVITE" },
    }
    local rowY = 0
    for _, row in ipairs(CHECK_ROWS) do
        local check = newCheck(choose, "SanctuaryFilter_" .. row.key,
            L[row.labelKey], L[row.tipKey],
            function() return filterStored(row.key) == true end,
            function(value) setFilter(row.key, value) end)
        check:SetPoint("TOPLEFT", choose, "TOPLEFT", 0, rowY)
        protection.checks[row.key] = check
        rowY = rowY - 24
        if row.key == "groupInvite" then
            -- The indented slot the strict box takes in this mode.
            protection.strictSlot = rowY
            rowY = rowY - 24
        end
    end

    protection.channelsLabel = newLabel(choose, L["CHANNELS_LABEL"], FONT_BODY, C.soft)
    protection.channelsLabel:SetPoint("TOPLEFT", choose, "TOPLEFT", 0, rowY - 6)
    rowY = rowY - 28
    protection.channelRadios = {}
    -- Written out rather than built from the mode name: a key that only exists
    -- as a concatenation cannot be found by searching for it, and an unreachable
    -- translation is one nobody will ever notice is missing.
    local CHANNEL_ROWS = {
        { mode = "none", labelKey = "CHANNEL_NONE", tipKey = "TIP_CHANNEL_NONE" },
        { mode = "keywords", labelKey = "CHANNEL_KEYWORDS", tipKey = "TIP_CHANNEL_KEYWORDS" },
        { mode = "all", labelKey = "CHANNEL_ALL", tipKey = "TIP_CHANNEL_ALL" },
    }
    for _, row in ipairs(CHANNEL_ROWS) do
        local mode = row.mode
        local radio = newRadio(choose, "SanctuaryChannel_" .. mode, L[row.labelKey], L[row.tipKey],
            function() return (filterStored("channelMode") or "none") == mode end,
            function() setFilter("channelMode", mode) end)
        radio:SetPoint("TOPLEFT", choose, "TOPLEFT", 16, rowY)
        protection.channelRadios[mode] = radio
        rowY = rowY - 22
    end
    -- Measured, never guessed: a wrong constant here is a screen that fits in
    -- the window on the developer's layout and is cut off on the real one.
    protection.chooseHeight = -rowY
    choose:SetHeight(protection.chooseHeight)

    -- Question 3 ------------------------------------------------------------
    protection.q3Anchor = CreateFrame("Frame", nil, parent)
    protection.q3Anchor:SetSize(width, 1)
    protection.q3Title = newLabel(parent, "3   " .. L["Q3_TITLE"], FONT_SECTION, C.accent)
    local thirdWidth = (width - 32) / 3
    protection.q3 = {}
    local Q3_ROWS = {
        { key = "silent",  titleKey = "Q3_SILENT_TITLE",  descKey = "Q3_SILENT_DESC" },
        { key = "minimal", titleKey = "Q3_MINIMAL_TITLE", descKey = "Q3_MINIMAL_DESC" },
        { key = "verbose", titleKey = "Q3_VERBOSE_TITLE", descKey = "Q3_VERBOSE_DESC" },
    }
    for _, row in ipairs(Q3_ROWS) do
        local card = newCard(parent, "SanctuaryQ3_" .. row.key,
            L[row.titleKey], L[row.descKey], thirdWidth,
            function() return SanctuaryDB and SanctuaryDB.notifications.mode == row.key end,
            function() SanctuaryDB.notifications.mode = row.key end)
        protection.q3[row.key] = card
    end

    -- Question 4 ------------------------------------------------------------
    protection.q4Title = newLabel(parent, "4   " .. L["Q4_TITLE"], FONT_SECTION, C.accent)

    local function newTile(name, titleText, onManage)
        local tile = CreateFrame("Frame", name, parent, "BackdropTemplate")
        tile:SetSize(cardWidth, 84)
        applyBackdrop(tile, C.tile, C.border)
        tile.title = newLabel(tile, titleText, FONT_DESC, C.ink)
        tile.title:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -10)
        tile.count = newLabel(tile, "0", FONT_TITLE, C.accent)
        tile.count:SetPoint("TOPLEFT", tile.title, "BOTTOMLEFT", 0, -4)
        tile.detail = newLabel(tile, "", FONT_BODY, C.dim)
        tile.detail:SetPoint("LEFT", tile.count, "RIGHT", 10, 0)
        tile.manage = newButton(tile, nil, L["MANAGE_BTN"], 80, 22, onManage)
        tile.manage:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -10, 10)
        return tile
    end

    protection.tileAllowed = newTile("SanctuaryTileAllowed", L["TILE_ALLOWED"], function()
        ns.OpenPanel("allowed")
    end)
    protection.tileBlocked = newTile("SanctuaryTileBlocked", L["TILE_BLOCKED"], function()
        ns.OpenPanel("blocked")
    end)

    protection.testLabel = newLabel(parent, L["TEST_LABEL"], FONT_DESC, C.soft)
    protection.testInput = newInput(parent, "SanctuaryTestInput", 220, L["TEST_LABEL"])
    protection.testAnswer = parent:CreateFontString("SanctuaryTestAnswer", "OVERLAY", "GameFontNormal")
    do
        local fontFile = protection.testAnswer:GetFont()
        protection.testAnswer:SetFont(fontFile, FONT_BODY, "")
        protection.testAnswer:SetJustifyH("LEFT")
    end
    protection.testInput:SetScript("OnTextChanged", function(self)
        self:RefreshHint()
        ns.RefreshTestAnswer(self:GetText())
    end)
end

-- The one sentence the tester answers with. It reads describeAccessDecision and
-- formats it; the verdict itself is never recomputed here.
function ns.RefreshTestAnswer(text)
    local answer = protection.testAnswer
    if not answer then return end
    local info = ns.describeAccessDecision and ns.describeAccessDecision(text or "")
    if not info or not info.valid then
        answer:SetText("")
        return
    end

    local LIST_KEYS = {
        manual = "LIST_MANUAL", trust = "LIST_TRUST", guild = "LIST_GUILD",
        friend = "LIST_FRIEND", group = "LIST_GROUP",
    }

    if info.verdict == "always_blocked" then
        local reason
        if info.list == "keyword" then
            reason = string.format(L["LIST_PATTERN"], tostring(info.detail or "?"))
        elseif info.overriddenList then
            local overKey = LIST_KEYS[info.overriddenList]
            local overText
            if info.overriddenList == "bnet" then
                overText = string.format(L["LIST_BNET"],
                    tostring(info.overriddenDetail or info.input))
            else
                overText = overKey and L[overKey] or tostring(info.overriddenList)
            end
            reason = string.format(L["LIST_BLOCKED_OVER"], overText)
        else
            reason = L["LIST_BLOCKED"]
        end
        answer:SetText(string.format(L["TEST_ALWAYS_BLOCKED"], info.input, reason))
        answer:SetTextColor(unpack(C.red))
        return
    end

    if info.verdict == "always_allowed" then
        local reason
        if info.list == "bnet" then
            reason = string.format(L["LIST_BNET"], tostring(info.detail or "?"))
        else
            local key = LIST_KEYS[info.list]
            reason = key and L[key] or tostring(info.list)
        end
        answer:SetText(string.format(L["TEST_ALWAYS_ALLOWED"], info.input, reason))
        answer:SetTextColor(unpack(C.green))
        return
    end

    if info.blockedNow then
        answer:SetText(string.format(L["TEST_UNKNOWN_BLOCKED"], info.input))
        answer:SetTextColor(unpack(C.orange))
    else
        answer:SetText(string.format(L["TEST_UNKNOWN_ALLOWED"], info.input))
        answer:SetTextColor(unpack(C.dim))
    end
end

-- Lays the screen out for the mode it is in, and returns the height it needs.
refreshTab.protection = function()
    local width = FRAME_WIDTH - PAD * 2
    local blockedOnly = ns.getScope() == "blockedOnly"
    local custom = ns.getPreset() == "custom"

    -- Question 2 is greyed out, never removed: the answers stay where they were
    -- and come back untouched when question 1 goes back to filtering strangers.
    for _, card in ipairs({ protection.q2All, protection.q2Custom }) do
        card:SetEnabledState(not blockedOnly)
    end
    protection.strict:SetEnabledState(not blockedOnly)
    protection.q1Strangers:Refresh()
    protection.q1Blocked:Refresh()

    for _, check in pairs(protection.checks) do
        check:SetEnabledState(not blockedOnly)
        check:Refresh()
    end
    for _, radio in pairs(protection.channelRadios) do
        radio:SetEnabledState(not blockedOnly)
        radio:Refresh()
    end
    protection.channelsLabel:SetTextColor(unpack(blockedOnly and C.disabled or C.soft))
    protection.q2Title:SetTextColor(unpack(blockedOnly and C.disabled or C.accent))

    -- Question 1 title, its two cards, question 2 title, its two cards. Written
    -- as the sum of what is above rather than as one number, so a change to any
    -- of the four is visible here.
    local y = -(24 + 90 + 24 + 84)
    if custom then
        protection.choose:Show()
        protection.choose:ClearAllPoints()
        protection.choose:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
        protection.strict:ClearAllPoints()
        protection.strict:SetPoint("TOPLEFT", protection.choose, "TOPLEFT", 16, protection.strictSlot)
        protection.strictNote:Hide()
        y = y - protection.chooseHeight
    else
        protection.choose:Hide()
        protection.strict:ClearAllPoints()
        protection.strict:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
        protection.strictNote:ClearAllPoints()
        protection.strictNote:SetPoint("LEFT", protection.strict.label, "RIGHT", 8, 0)
        protection.strictNote:Show()
        y = y - 30
    end
    protection.strict:Refresh()

    protection.q3Title:ClearAllPoints()
    protection.q3Title:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    y = y - 24
    local thirdWidth = (width - 32) / 3
    local index = 0
    for _, key in ipairs({ "silent", "minimal", "verbose" }) do
        local card = protection.q3[key]
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD + index * (thirdWidth + 16), y)
        card:Refresh()
        index = index + 1
    end
    y = y - 90

    protection.q4Title:ClearAllPoints()
    protection.q4Title:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    y = y - 24
    protection.tileAllowed:ClearAllPoints()
    protection.tileAllowed:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    protection.tileBlocked:ClearAllPoints()
    protection.tileBlocked:SetPoint("TOPLEFT", protection.tileAllowed, "TOPRIGHT", 16, 0)

    local counts = ns.getListCounts and ns.getListCounts()
        or { allowed = { total = 0, manual = 0, trust = 0, bnet = 0 }, blocked = { total = 0, names = 0, patterns = 0 } }
    protection.tileAllowed.count:SetText(tostring(counts.allowed.total))
    -- "Added by you" means typed by hand. Automatic trust entries live in the
    -- same table but nobody typed them, and the panel section under the same
    -- wording already counts only the manual ones: adding trust back in here
    -- made the home screen contradict the panel, on the more visible of the two.
    protection.tileAllowed.detail:SetText(string.format(L["TILE_ALLOWED_DETAIL"],
        tostring(counts.allowed.manual), tostring(counts.allowed.bnet)))
    protection.tileBlocked.count:SetText(tostring(counts.blocked.total))
    protection.tileBlocked.detail:SetText(string.format(L["TILE_BLOCKED_DETAIL"],
        tostring(counts.blocked.names), tostring(counts.blocked.patterns)))
    y = y - 100

    protection.testLabel:ClearAllPoints()
    protection.testLabel:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    protection.testInput:ClearAllPoints()
    protection.testInput:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD + 130, y + 4)
    protection.testAnswer:ClearAllPoints()
    protection.testAnswer:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD + 360, y)
    protection.testAnswer:SetWidth(width - 360)
    y = y - 40

    return -y + PAD
end

-- ============================================================================
-- SECTION 6: Journal screen
-- ============================================================================

local journal = {}
local expandedGroups = {}
local allExpanded = false

-- Grouped by name, most recent group first: "is this person still at it" is the
-- question the tab is opened for.
local function groupLogsByName()
    if not SanctuaryDB or not SanctuaryDB.log then return {} end
    local groups, order = {}, {}
    for _, entry in ipairs(SanctuaryDB.log) do
        local name = entry.name or "?"
        if entry.realm and entry.realm ~= "" then name = name .. "-" .. entry.realm end
        if not groups[name] then
            groups[name] = { entries = {}, lastTime = 0 }
            order[#order + 1] = name
        end
        local group = groups[name]
        group.entries[#group.entries + 1] = entry
        if entry.t and entry.t > group.lastTime then group.lastTime = entry.t end
    end
    local sorted = {}
    for _, name in ipairs(order) do
        sorted[#sorted + 1] = { name = name, data = groups[name] }
    end
    table.sort(sorted, function(a, b) return a.data.lastTime > b.data.lastTime end)
    return sorted
end

local function buildJournalText()
    local escape = ns.escapeExportText or tostring
    local lines = { L["EXPORT_HEADER"] }
    lines[#lines + 1] = string.format(L["EXPORT_DATE"], date(L["DATE_TIME_FORMAT"]))
    lines[#lines + 1] = string.format(L["EXPORT_TOTAL"], tostring(#SanctuaryDB.log))
    lines[#lines + 1] = L["EXPORT_COLUMNS"]
    lines[#lines + 1] = string.rep("-", 50)
    for _, entry in ipairs(SanctuaryDB.log) do
        local line = escape(entry.d or "?") .. " | " .. escape(ns.getLogEntryDisplayType(entry))
            .. " | " .. escape(entry.name or "?")
        if entry.realm and entry.realm ~= "" then line = line .. "-" .. escape(entry.realm) end
        if entry.msg and entry.msg ~= "" then line = line .. " | " .. escape(entry.msg) end
        if entry.keyword and entry.keyword ~= "" then
            line = line .. " " .. string.format(L["EXPORT_SUSPECT_TAG"], escape(entry.keyword))
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n") .. "\n"
end

local function buildJournalTab(parent)
    journal.frame = parent
    local width = FRAME_WIDTH - PAD * 2
    journal.header = newLabel(parent, L["LOGS_HEADER"], FONT_SECTION, C.ink)
    journal.header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, 0)
    journal.count = newLabel(parent, "", FONT_BODY, C.dim)
    journal.count:SetPoint("LEFT", journal.header, "RIGHT", 10, 0)

    journal.enable = newCheck(parent, "SanctuaryJournalEnable", L["LOGS_ENABLE"],
        L["TIP_LOGS_ENABLE"],
        function() return SanctuaryDB and SanctuaryDB.logging.enabled == true end,
        function(value) SanctuaryDB.logging.enabled = value end)
    journal.enable:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -30)

    journal.showMsg = newCheck(parent, "SanctuaryJournalShowMessages", L["LOGS_SHOW_MSG"], nil,
        function() return SanctuaryDB and SanctuaryDB.uiSettings.showMessageColumn == true end,
        function(value) SanctuaryDB.uiSettings.showMessageColumn = value end)
    journal.showMsg:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 320, -30)

    journal.scroll = newScroll(parent, "SanctuaryJournalScroll", width, 300)
    journal.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -60)
    journal.rows = {}
    journal.rowPool = {}

    journal.clearBtn = newButton(parent, nil, L["LOGS_CLEAR_BTN"], 140, 24, function()
        StaticPopup_Show("SANCTUARY_CLEAR_LOG")
    end, true)
    journal.copyBtn = newButton(parent, nil, L["LOGS_COPY_BTN"], 140, 24, function()
        ns.ShowTextWindow(L["LOGS_HEADER"], buildJournalText())
    end)
    journal.expandBtn = newButton(parent, nil, L["LOGS_EXPAND_ALL"], 120, 24, function()
        allExpanded = not allExpanded
        wipe(expandedGroups)
        if ns.refreshUI then ns.refreshUI() end
    end)
end

local function acquireJournalRow(parent)
    local row = table.remove(journal.rowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetSize(FRAME_WIDTH - PAD * 2 - 10, 18)
        row.label = newLabel(row, "", FONT_BODY, C.soft)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    row:SetParent(parent)
    row:Show()
    journal.rows[#journal.rows + 1] = row
    return row
end

refreshTab.journal = function()
    for _, row in ipairs(journal.rows) do
        row:Hide()
        row:SetScript("OnClick", nil)
        journal.rowPool[#journal.rowPool + 1] = row
    end
    journal.rows = {}

    local maxEntries = SanctuaryDB and SanctuaryDB.logging.maxEntries or 5000
    journal.count:SetText(string.format(L["LOGS_COUNT_FULL"],
        tostring(SanctuaryDB and #SanctuaryDB.log or 0), tostring(maxEntries)))
    journal.enable:Refresh()
    journal.showMsg:Refresh()
    journal.expandBtn.label:SetText(allExpanded and L["LOGS_COLLAPSE_ALL"] or L["LOGS_EXPAND_ALL"])

    local child = journal.scroll.child
    local groups = groupLogsByName()
    local y = 0

    if #groups == 0 then
        local row = acquireJournalRow(child)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        row.label:SetText(L["LOGS_EMPTY"])
        row.label:SetTextColor(unpack(C.dim))
        y = y - 20
    end

    local showMessages = SanctuaryDB and SanctuaryDB.uiSettings.showMessageColumn
    for _, group in ipairs(groups) do
        local expanded = allExpanded or expandedGroups[group.name]
        local row = acquireJournalRow(child)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        row.label:SetTextColor(unpack(C.ink))
        row.label:SetText((expanded and "v " or "> ")
            .. string.format(L["LOGS_GROUP_HEADER"], group.name, #group.data.entries)
            .. "  " .. string.format(L["LOGS_LAST_ACTIVITY"], formatDate(group.data.lastTime)))
        local groupName = group.name
        row:SetScript("OnClick", function()
            expandedGroups[groupName] = not expandedGroups[groupName]
            if ns.refreshUI then ns.refreshUI() end
        end)
        y = y - 20

        if expanded then
            for _, entry in ipairs(group.data.entries) do
                local line = acquireJournalRow(child)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
                local text = (entry.d or "?") .. "   " .. ns.getLogEntryDisplayType(entry)
                if showMessages and entry.msg and entry.msg ~= "" then
                    text = text .. "   " .. entry.msg
                end
                line.label:SetTextColor(unpack(C.dim))
                line.label:SetText(text)
                y = y - 18
            end
        end
    end

    child:SetHeight(math.max(1, -y))
    journal.scroll:RefreshBar()

    journal.clearBtn:ClearAllPoints()
    journal.clearBtn:SetPoint("TOPLEFT", journal.frame, "TOPLEFT", PAD, -370)
    journal.copyBtn:ClearAllPoints()
    journal.copyBtn:SetPoint("LEFT", journal.clearBtn, "RIGHT", 10, 0)
    journal.expandBtn:ClearAllPoints()
    journal.expandBtn:SetPoint("LEFT", journal.copyBtn, "RIGHT", 10, 0)

    return 410
end

-- ============================================================================
-- SECTION 7: Advanced screen
-- ============================================================================

local advanced = {}

local function buildAdvancedTab(parent)
    local width = FRAME_WIDTH - PAD * 2
    local y = 0

    advanced.trustSection = newSection(parent, L["ADV_TRUST_TITLE"], nil, width)
    advanced.trustSection:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 34
    advanced.trust = newCheck(parent, "SanctuaryAutoTrust", L["FILTER_AUTO_TRUST"], nil,
        function() return filterStored("autoTrust") == true end,
        function(value) setFilter("autoTrust", value) end)
    advanced.trust:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 24
    advanced.trustDesc = newLabel(parent, L["ADV_TRUST_DESC"], FONT_BODY, C.dim)
    advanced.trustDesc:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 26, y)
    advanced.trustDesc:SetWidth(width - 26)
    y = y - 40

    advanced.diagSection = newSection(parent, L["ADV_DIAG_TITLE"], nil, width)
    advanced.diagSection:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 34
    advanced.debug = newCheck(parent, "SanctuaryDebugCheck", L["DEBUG_ENABLE"], nil,
        function() return SanctuaryDB and SanctuaryDB.debugEnabled == true end,
        function(value)
            SanctuaryDB.debugEnabled = value and true or false
            if value then
                if ns.captureDebugSnapshot then ns.captureDebugSnapshot("debug_enable") end
                ns.printSuccess(L["DEBUG_ENABLED_MSG"])
            else
                ns.printMsg(L["DEBUG_DISABLED_MSG"])
            end
            if ns.refreshTabBar then ns.refreshTabBar() end
        end)
    advanced.debug:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 24
    advanced.debugDesc = newLabel(parent, L["ADV_DEBUG_DESC"], FONT_BODY, C.dim)
    advanced.debugDesc:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 26, y)
    advanced.debugDesc:SetWidth(width - 26)
    y = y - 46

    advanced.exportBtn = newButton(parent, nil, L["DEBUG_EXPORT_BTN"], 170, 24, function()
        ns.ShowTextWindow(L["DEBUG_EXPORT_TITLE"],
            ns.buildExportReportText and ns.buildExportReportText() or "")
    end)
    advanced.exportBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 26, y)
    advanced.clearDebugBtn = newButton(parent, nil, L["DEBUG_CLEAR_BTN"], 150, 24, function()
        StaticPopup_Show("SANCTUARY_CLEAR_DEBUG_LOG",
            SanctuaryDB and #(SanctuaryDB.debugLog or {}) or 0)
    end, true)
    advanced.clearDebugBtn:SetPoint("LEFT", advanced.exportBtn, "RIGHT", 10, 0)
    y = y - 44

    advanced.journalSection = newSection(parent, L["ADV_JOURNAL_TITLE"], nil, width)
    advanced.journalSection:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 34
    advanced.maxLabel = newLabel(parent, L["ADV_MAXENTRIES"], FONT_BODY, C.soft)
    advanced.maxLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    -- Bounded on write, not on display: a value typed outside the range is
    -- clamped and shown clamped, so nobody leaves thinking they set 50.
    advanced.maxInput = newInput(parent, "SanctuaryMaxEntriesInput", 90, "", function(text)
        local value = tonumber(text)
        if not value then return end
        value = math.floor(math.max(100, math.min(20000, value)))
        SanctuaryDB.logging.maxEntries = value
        if ns.refreshUI then ns.refreshUI() end
    end)
    advanced.maxInput:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 130, y + 4)
    advanced.maxUnit = newLabel(parent, L["ADV_ENTRIES"], FONT_BODY, C.dim)
    advanced.maxUnit:SetPoint("LEFT", advanced.maxInput, "RIGHT", 8, 0)
    y = y - 40

    advanced.minimapSection = newSection(parent, L["ADV_MINIMAP_TITLE"], nil, width)
    advanced.minimapSection:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 34
    advanced.minimap = newCheck(parent, "SanctuaryMinimapCheck", L["ADV_MINIMAP_SHOW"], nil,
        function() return SanctuaryDB and not SanctuaryDB.minimap.hide end,
        function(value)
            SanctuaryDB.minimap.hide = not value
            if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
        end)
    advanced.minimap:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 40

    advanced.status = newLabel(parent, "", FONT_BODY, C.dim)
    advanced.status:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    advanced.status:SetWidth(width)
    advanced.statusY = y
end

refreshTab.advanced = function()
    advanced.trust:Refresh()
    advanced.debug:Refresh()
    advanced.minimap:Refresh()
    advanced.maxInput:SetText(tostring(SanctuaryDB and SanctuaryDB.logging.maxEntries or 5000))
    advanced.maxInput:RefreshHint()

    local stats = SanctuaryCharDB and SanctuaryCharDB.sessionStats or { blockedCount = 0 }
    local manifest = SanctuaryDB and SanctuaryDB.reportManifest or {}
    advanced.status:SetText(string.format(L["ADV_STATUS"],
        tostring(stats.blockedCount or 0),
        tostring(SanctuaryDB and #SanctuaryDB.log or 0),
        tostring(SanctuaryDB and SanctuaryDB.logging.maxEntries or 0),
        (SanctuaryDB and SanctuaryDB.debugEnabled) and L["ADV_DEBUG_ON"] or L["ADV_DEBUG_OFF"],
        tostring(ns.BUILD_ID),
        tostring(manifest.addonInterface or manifest.addonMetaInterface or "?")))

    return -advanced.statusY + 30
end

-- ============================================================================
-- SECTION 8: About screen
-- ============================================================================

local about = {}

local function buildAboutTab(parent)
    local y = -30
    about.title = newLabel(parent, "Sanctuary", 22, C.accent, "CENTER")
    about.title:SetPoint("TOP", parent, "TOP", 0, y)
    y = y - 36
    about.version = newLabel(parent, string.format(L["ABOUT_VERSION"], ns.VERSION),
        FONT_DESC, C.dim, "CENTER")
    about.version:SetPoint("TOP", parent, "TOP", 0, y)
    y = y - 40
    about.desc = newLabel(parent, L["ABOUT_DESC"], FONT_BODY, C.ink, "CENTER")
    about.desc:SetPoint("TOP", parent, "TOP", 0, y)
    about.desc:SetWidth(460)
    y = y - 60
    about.author = newLabel(parent, string.format(L["ABOUT_AUTHOR"], "Zephos"),
        FONT_BODY, C.dim, "CENTER")
    about.author:SetPoint("TOP", parent, "TOP", 0, y)
    y = y - 24
    about.github = newLabel(parent,
        string.format(L["ABOUT_GITHUB"], "github.com/VincentCassiau/Sanctuary"),
        FONT_BODY, C.dim, "CENTER")
    about.github:SetPoint("TOP", parent, "TOP", 0, y)
end

refreshTab.about = function()
    return MIN_HEIGHT
end

-- ============================================================================
-- SECTION 9: Diagnostics screen
-- ============================================================================

local diagnostics = {}

local DIAG_RESULT_LINE_HEIGHT = 14

-- The result column is a single FontString that grows with every run. Its scroll
-- child was sized once at build time, so `RefreshBar` measured a range of zero,
-- the wheel scrolled nothing and the bar stayed hidden: everything past the
-- first screen of "Run everything" -- eight blocks -- was unreachable. The three
-- other scroll areas in this file resize their child after each write; this one
-- has to as well.
local function resizeDiagnosticResults()
    local scroll = diagnostics.resultScroll
    local text = diagnostics.resultText
    if not scroll or not scroll.child or not text then return end

    -- Two measures, the larger wins. Counting the lines needs no layout pass and
    -- is exact for the short lines a diagnostic emits; GetStringHeight adds
    -- whatever the wrapping of a long one actually produced.
    local content = text:GetText() or ""
    local lines = 1
    for _ in content:gmatch("\n") do lines = lines + 1 end
    local measured = (text.GetStringHeight and text:GetStringHeight()) or 0
    local height = math.max(lines * DIAG_RESULT_LINE_HEIGHT, measured)

    scroll.child:SetHeight(math.max(1, height))
    scroll:RefreshBar()
end

local function clearDiagnosticsPanel()
    diagnosticResults = {}
    if diagnostics.resultText then
        diagnostics.resultText:SetText(L["DIAG_RESULT_EMPTY"])
    end
    resizeDiagnosticResults()
    if ns.RefreshStranded then ns.RefreshStranded() end
end

-- A window a diagnostic could not close is invisible and clickable. It is read
-- back off the screen every time, never from a flag: clearing the results must
-- not take the way back away while the dialog is still up.
function ns.RefreshStranded()
    local stranded = false
    for which in pairs(strandedPopups) do
        if ns.isDiagnosticPopupVisible and ns.isDiagnosticPopupVisible(which) then
            stranded = true
        else
            strandedPopups[which] = nil
        end
    end
    if diagnostics.restoreBtn then
        if stranded then diagnostics.restoreBtn:Show() else diagnostics.restoreBtn:Hide() end
    end
    if stranded and diagnostics.resultText then
        local text = diagnostics.resultText:GetText() or ""
        if text:find(L["DIAG_LEFT_ON_SCREEN"], 1, true) == nil then
            diagnostics.resultText:SetText(text .. "\n" .. L["DIAG_LEFT_ON_SCREEN"])
            resizeDiagnosticResults()
        end
    end
end

local function appendDiagnosticResult(result)
    local entry = ns.getDiagnosticEntry(result.id)
    local label = entry and L[entry.labelKey] or tostring(result.id)
    diagnosticResults[#diagnosticResults + 1] = "|cFF88CCFF" .. label .. "|r\n" .. (result.text or "")
    if result.leftOnScreen and result.which then
        strandedPopups[result.which] = true
    end
    if diagnostics.resultText then
        diagnostics.resultText:SetText(table.concat(diagnosticResults, "\n\n"))
        resizeDiagnosticResults()
    end
    ns.RefreshStranded()
end

local function buildDiagnosticsTab(parent)
    local width = FRAME_WIDTH - PAD * 2
    diagnostics.header = newLabel(parent, L["DIAG_PANEL_HEADER"], FONT_SECTION, C.ink)
    diagnostics.header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, 0)

    diagnostics.runAllBtn = newButton(parent, nil, L["DIAG_RUN_ALL"], 260, 24, function()
        diagnosticResults = {}
        for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
            -- Skipped on a bulk run: the one that writes a real Battle.net name
            -- into the log, and the two sounds, which are checked one by one.
            if not entry.sensitive and not entry.manual then
                appendDiagnosticResult(ns.runDiagnosticById(entry.id, entry.argDefault))
            end
        end
    end)
    diagnostics.runAllBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -28)

    diagnostics.clearBtn = newButton(parent, nil, L["DIAG_CLEAR"], 100, 24, clearDiagnosticsPanel)
    diagnostics.clearBtn:SetPoint("LEFT", diagnostics.runAllBtn, "RIGHT", 10, 0)

    diagnostics.restoreBtn = newButton(parent, nil, L["DIAG_RESTORE_BTN"], 220, 24, function()
        ReloadUI()
    end, true)
    diagnostics.restoreBtn:SetPoint("LEFT", diagnostics.clearBtn, "RIGHT", 10, 0)
    diagnostics.restoreBtn:Hide()

    local listScroll = newScroll(parent, "SanctuaryDiagListScroll", 320, 300)
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -60)
    local listChild = listScroll.child
    local rowY = 0
    for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
        local row = CreateFrame("Frame", nil, listChild)
        row:SetSize(310, 26)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, rowY)
        local id = entry.id
        local input
        if entry.argKey then
            input = newInput(row, "SanctuaryDiagArg_" .. id, 90, L[entry.argKey])
            input:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            input:SetText(entry.argDefault or "")
            input:RefreshHint()
        end
        local btn = newButton(row, nil, L[entry.labelKey], input and 200 or 300, 22, function()
            appendDiagnosticResult(ns.runDiagnosticById(id, input and input:GetText() or entry.argDefault))
        end)
        btn:SetPoint("LEFT", row, "LEFT", 0, 0)
        local tip = entry.sensitive and L["DIAG_SENSITIVE"]
            or (entry.manual and L["DIAG_MANUAL"])
            or (entry.tipKey and L[entry.tipKey])
        setTooltip(btn, tip)
        rowY = rowY - 28
    end
    listChild:SetHeight(math.max(1, -rowY))

    local resultScroll = newScroll(parent, "SanctuaryDiagResultScroll", width - 340, 300)
    resultScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 330, -60)
    diagnostics.resultScroll = resultScroll
    diagnostics.resultText = newLabel(resultScroll.child, L["DIAG_RESULT_EMPTY"], FONT_BODY, C.soft)
    diagnostics.resultText:SetPoint("TOPLEFT", resultScroll.child, "TOPLEFT", 0, 0)
    diagnostics.resultText:SetWidth(width - 350)
    resizeDiagnosticResults()
end

refreshTab.diagnostics = function()
    ns.RefreshStranded()
    return 400
end

-- ============================================================================
-- SECTION 10: The two management panels
-- ============================================================================

local panels = {}

local function releaseChips()
    for _, chip in ipairs(activeChips) do
        chip:Hide()
        chip:SetScript("OnEnter", nil)
        chip:SetScript("OnLeave", nil)
        chip.remove:SetScript("OnClick", nil)
        local pool = chipPools[chip:GetParent()]
        if pool then pool[#pool + 1] = chip end
    end
    activeChips = {}
end

local function layoutChips(parent, entries, startY, onRemove)
    local x, y = 0, startY
    local maxWidth = PANEL_WIDTH - 40
    for _, item in ipairs(entries) do
        local chip = newChip(parent)
        activeChips[#activeChips + 1] = chip
        chip.label:SetText(item.label)
        local width = math.min(maxWidth, 24 + (#item.label * 7))
        chip:SetSize(width, 22)
        if x + width > maxWidth then
            x = 0
            y = y - 26
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        x = x + width + 6
        setTooltip(chip, item.tooltip)
        chip.remove:SetScript("OnClick", function() onRemove(item) end)
    end
    if #entries > 0 then y = y - 26 end
    return y
end

local function describeChipSource(data)
    local parts = {}
    if type(data) == "table" then
        if data.addedAt then
            parts[#parts + 1] = string.format(L["CHIP_ADDED_ON"], formatDate(data.addedAt))
        end
        if data.source == "trust" then
            parts[#parts + 1] = L["CHIP_SOURCE_TRUST"]
        elseif data.source == "menu" then
            parts[#parts + 1] = L["CHIP_SOURCE_MENU"]
        else
            parts[#parts + 1] = L["CHIP_SOURCE_MANUAL"]
        end
    end
    return table.concat(parts, "\n")
end

local function newPanelFrame(name, titleText)
    local panel = CreateFrame("Frame", name, mainFrame, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, 400)
    panel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, -HEADER_HEIGHT)
    panel:SetFrameLevel(200)
    applyBackdrop(panel, C.panel, C.border, 2)
    panel:Hide()

    panel.back = newButton(panel, nil, L["PANEL_BACK"], 90, 22, function() ns.ClosePanel() end)
    panel.back:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title = newLabel(panel, titleText, FONT_TITLE, C.ink)
    panel.title:SetPoint("LEFT", panel.back, "RIGHT", 12, 0)
    panel.count = newLabel(panel, "", FONT_DESC, C.accent)
    panel.count:SetPoint("LEFT", panel.title, "RIGHT", 10, 0)

    panel.scroll = newScroll(panel, name .. "Scroll", PANEL_WIDTH - 24, 320)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -44)
    return panel
end

-- The panel's model signature. Redrawing on every tick would fight the typing;
-- redrawing only when this string changes keeps a ten-second refresh invisible.
local function allowedSignature()
    ns.ensureWhitelist()
    local parts = {}
    for key in pairs(SanctuaryDB and SanctuaryDB.manualWhitelist or {}) do
        parts[#parts + 1] = key
    end
    table.sort(parts)
    local counts = ns.getListCounts()
    return table.concat(parts, ",") .. "|" .. counts.allowed.total .. "|"
        .. tostring(panels.allowedExpanded and next(panels.allowedExpanded) and
            table.concat((function()
                local open = {}
                for source, value in pairs(panels.allowedExpanded) do
                    if value then open[#open + 1] = source end
                end
                table.sort(open)
                return open
            end)(), ",") or "")
end

local function blockedSignature()
    local names, patterns = {}, {}
    for key in pairs(SanctuaryDB and SanctuaryDB.blockedNames or {}) do names[#names + 1] = key end
    for _, value in ipairs(SanctuaryDB and SanctuaryDB.keywords or {}) do patterns[#patterns + 1] = value end
    table.sort(names)
    table.sort(patterns)
    return table.concat(names, ",") .. "|" .. table.concat(patterns, ",")
end

local function buildAllowedPanel()
    local panel = newPanelFrame("SanctuaryPanelAllowed", L["TILE_ALLOWED"])
    panels.allowed = panel
    panels.allowedExpanded = {}

    local child = panel.scroll.child
    panel.addedSection = newSection(child, L["PANEL_ADDED_BY_YOU"], nil, PANEL_WIDTH - 40)
    panel.addedSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)

    panel.addInput = newInput(child, "SanctuaryAllowedAddInput", 250, L["PANEL_ADD_NAME_HINT"],
        function(text)
            if ns.addAllowed(text) and ns.refreshUI then ns.refreshUI() end
        end)
    panel.addBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        local text = panel.addInput:GetText()
        panel.addInput:SetText("")
        panel.addInput:RefreshHint()
        if ns.addAllowed(text) and ns.refreshUI then ns.refreshUI() end
    end)

    panel.autoSection = newSection(child, L["PANEL_AUTO_TITLE"], nil, PANEL_WIDTH - 40)
    panel.groupNote = newLabel(child, L["WL_GROUP_NOTE"], FONT_BODY, C.dim)
    panel.groupNote:SetWidth(PANEL_WIDTH - 40)
    panel.autoRows = {}
    panel.autoRowPool = {}
    panel.signature = nil
    return panel
end

local function acquireAutoRow(parent, panel)
    local row = table.remove(panel.autoRowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetSize(PANEL_WIDTH - 44, 18)
        row.label = newLabel(row, "", FONT_BODY, C.soft)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    row:SetParent(parent)
    row:Show()
    panel.autoRows[#panel.autoRows + 1] = row
    return row
end

local AUTO_GROUP_LABELS = {
    bnet = "WL_SOURCE_BNET", friend = "WL_SOURCE_FRIEND",
    guild = "WL_SOURCE_GUILD", trust = "WL_SOURCE_TRUST",
}

local function refreshAllowedPanel(force)
    local panel = panels.allowed
    if not panel or not panel:IsShown() then return end
    local signature = allowedSignature()
    if not force and signature == panel.signature then return end
    panel.signature = signature

    releaseChips()
    for _, row in ipairs(panel.autoRows) do
        row:Hide()
        row:SetScript("OnClick", nil)
        panel.autoRowPool[#panel.autoRowPool + 1] = row
    end
    panel.autoRows = {}

    local child = panel.scroll.child
    local counts = ns.getListCounts()
    panel.count:SetText(tostring(counts.allowed.total))

    -- "Added by you": the manual entries, as chips. Automatically trusted
    -- contacts sit in the same table with source = "trust" and get their own
    -- group further down, so they are excluded here: listing them twice would
    -- show the tester the same name in two places and count as typed by hand
    -- someone she never typed.
    local manual = {}
    for key, data in pairs(SanctuaryDB.manualWhitelist or {}) do
        if type(data) ~= "table" or data.source ~= "trust" then
            manual[#manual + 1] = {
                key = key,
                label = (type(data) == "table" and data.displayName) or key,
                tooltip = describeChipSource(data),
                data = data,
            }
        end
    end
    table.sort(manual, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    panel.addedSection.count:SetText("(" .. #manual .. ")")

    local y = -40
    y = layoutChips(child, manual, y, function(item)
        local ok, key, data = ns.removeAllowed(item.key)
        if not ok then return end
        offerUndo(item.label, function() ns.restoreAllowed(key, data) end)
        if ns.refreshUI then ns.refreshUI() end
    end)
    y = y - 6

    panel.addInput:ClearAllPoints()
    panel.addInput:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.addBtn:ClearAllPoints()
    panel.addBtn:SetPoint("LEFT", panel.addInput, "RIGHT", 8, 0)
    y = y - 40

    panel.autoSection:ClearAllPoints()
    panel.autoSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.autoSection.count:SetText("(" .. tostring(counts.allowed.bnet + counts.allowed.friend
        + counts.allowed.guild + counts.allowed.trust) .. ")")
    y = y - 34

    -- Automatic groups, folded by default: fifty-six Battle.net accounts are
    -- four count lines until somebody asks for them, and the window can be
    -- opened in public.
    local groups = ns.getAutoWhitelistGroups and ns.getAutoWhitelistGroups() or {}
    local bySource = {}
    for _, group in ipairs(groups) do bySource[group.source] = group end

    -- Automatically trusted contacts live in the manual table with source
    -- "trust"; they get their own group here rather than hiding among the names
    -- the person typed.
    local trustEntries = {}
    for key, data in pairs(SanctuaryDB.manualWhitelist or {}) do
        if type(data) == "table" and data.source == "trust" then
            trustEntries[#trustEntries + 1] = { key = key, label = data.displayName or key, data = data }
        end
    end
    table.sort(trustEntries, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)

    for _, source in ipairs({ "bnet", "friend", "guild", "trust" }) do
        local entries, total
        if source == "trust" then
            entries, total = trustEntries, #trustEntries
        else
            local group = bySource[source]
            entries = group and group.entries or {}
            total = group and group.total or 0
        end

        local expanded = panels.allowedExpanded[source]
        local head = acquireAutoRow(child, panel)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        head.label:SetTextColor(unpack(C.ink))
        head.label:SetText((expanded and "v " or "> ") .. L[AUTO_GROUP_LABELS[source]]
            .. " (" .. tostring(total) .. ")")
        local captured = source
        head:SetScript("OnClick", function()
            panels.allowedExpanded[captured] = not panels.allowedExpanded[captured]
            refreshAllowedPanel(true)
        end)
        y = y - 20

        if source == "trust" then
            local hint = acquireAutoRow(child, panel)
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
            hint.label:SetTextColor(unpack(C.dim))
            hint.label:SetText(L["WL_TRUST_HINT"])
            y = y - 20
        end

        if expanded then
            if source == "trust" then
                local chips = {}
                for _, item in ipairs(trustEntries) do
                    chips[#chips + 1] = {
                        key = item.key, label = item.label,
                        tooltip = describeChipSource(item.data), data = item.data,
                    }
                end
                y = layoutChips(child, chips, y, function(item)
                    local ok, key, data = ns.removeAllowed(item.key)
                    if not ok then return end
                    offerUndo(item.label, function() ns.restoreAllowed(key, data) end)
                    if ns.refreshUI then ns.refreshUI() end
                end)
            else
                for _, entry in ipairs(entries) do
                    local row = acquireAutoRow(child, panel)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
                    row.label:SetTextColor(unpack(C.soft))
                    if source == "bnet" then
                        if entry.character then
                            row.label:SetText(string.format(L["WL_BNET_ROW"],
                                entry.characterDisplay or entry.character,
                                entry.account or entry.label))
                        else
                            row.label:SetText(string.format(L["WL_BNET_OFFLINE"],
                                entry.account or entry.label))
                        end
                    else
                        row.label:SetText(entry.label)
                    end
                    y = y - 18
                end
            end
        end
        y = y - 6
    end

    panel.groupNote:ClearAllPoints()
    panel.groupNote:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 6)
    y = y - 40

    child:SetHeight(math.max(1, -y))
    panel.scroll:RefreshBar()
end

local function buildBlockedPanel()
    local panel = newPanelFrame("SanctuaryPanelBlocked", L["TILE_BLOCKED"])
    panels.blocked = panel

    local child = panel.scroll.child
    panel.desc = newLabel(child, L["PANEL_BLOCKED_DESC"], FONT_BODY, C.dim)
    panel.desc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    panel.desc:SetWidth(PANEL_WIDTH - 40)

    panel.namesSection = newSection(child, L["PANEL_BLOCKED_NAMES"], nil, PANEL_WIDTH - 40)
    panel.nameInput = newInput(child, "SanctuaryBlockedAddInput", 250, L["PANEL_ADD_NAME_HINT"],
        function(text)
            if ns.addBlocked(text) and ns.refreshUI then ns.refreshUI() end
        end)
    panel.nameBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        local text = panel.nameInput:GetText()
        panel.nameInput:SetText("")
        panel.nameInput:RefreshHint()
        if ns.addBlocked(text) and ns.refreshUI then ns.refreshUI() end
    end)

    panel.patternsSection = newSection(child, L["PANEL_BLOCKED_PATTERNS"],
        L["PANEL_PATTERNS_DESC"], PANEL_WIDTH - 40)
    panel.patternInput = newInput(child, "SanctuaryPatternAddInput", 250, L["PANEL_PATTERN_HINT"],
        function(text)
            if ns.addPattern(text) and ns.refreshUI then ns.refreshUI() end
        end)
    panel.patternBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        local text = panel.patternInput:GetText()
        panel.patternInput:SetText("")
        panel.patternInput:RefreshHint()
        if ns.addPattern(text) and ns.refreshUI then ns.refreshUI() end
    end)
    panel.signature = nil
    return panel
end

local function refreshBlockedPanel(force)
    local panel = panels.blocked
    if not panel or not panel:IsShown() then return end
    local signature = blockedSignature()
    if not force and signature == panel.signature then return end
    panel.signature = signature

    releaseChips()
    local child = panel.scroll.child
    local counts = ns.getListCounts()
    panel.count:SetText(tostring(counts.blocked.total))

    local y = -40
    panel.namesSection:ClearAllPoints()
    panel.namesSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.namesSection.count:SetText("(" .. tostring(counts.blocked.names) .. ")")
    y = y - 34

    panel.nameInput:ClearAllPoints()
    panel.nameInput:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.nameBtn:ClearAllPoints()
    panel.nameBtn:SetPoint("LEFT", panel.nameInput, "RIGHT", 8, 0)
    y = y - 34

    local names = {}
    for key, data in pairs(SanctuaryDB.blockedNames or {}) do
        names[#names + 1] = {
            key = key,
            label = (type(data) == "table" and data.displayName) or key,
            tooltip = describeChipSource(data),
        }
    end
    table.sort(names, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    y = layoutChips(child, names, y, function(item)
        local ok, key, data = ns.removeBlocked(item.key)
        if not ok then return end
        offerUndo(item.label, function() ns.restoreBlocked(key, data) end)
        if ns.refreshUI then ns.refreshUI() end
    end)
    y = y - 10

    panel.patternsSection:ClearAllPoints()
    panel.patternsSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.patternsSection.count:SetText("(" .. tostring(counts.blocked.patterns) .. ")")
    y = y - 62

    panel.patternInput:ClearAllPoints()
    panel.patternInput:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.patternBtn:ClearAllPoints()
    panel.patternBtn:SetPoint("LEFT", panel.patternInput, "RIGHT", 8, 0)
    y = y - 34

    local patterns = {}
    for _, value in ipairs(SanctuaryDB.keywords or {}) do
        patterns[#patterns + 1] = { key = value, label = value, pattern = true }
    end
    y = layoutChips(child, patterns, y, function(item)
        local ok = ns.removePattern(item.key)
        if not ok then return end
        local text = item.key
        offerUndo(item.label, function() ns.addPattern(text) end)
        if ns.refreshUI then ns.refreshUI() end
    end)

    child:SetHeight(math.max(1, -y + 20))
    panel.scroll:RefreshBar()
end

local function refreshOpenPanel(force)
    if openPanel == "allowed" then
        refreshAllowedPanel(force)
    elseif openPanel == "blocked" then
        refreshBlockedPanel(force)
    end
end

function ns.OpenPanel(which)
    if not mainFrame then return end
    ns.ClosePanel()
    openPanel = which
    local panel = panels[which]
    if not panel then return end
    panel:Show()
    panel.signature = nil
    refreshOpenPanel(true)
    -- Created on opening, cancelled on closing. A ticker that outlives its panel
    -- keeps rebuilding a list nobody is looking at, for the whole session.
    listTicker = C_Timer.NewTicker(LIST_REFRESH_SECONDS, function()
        refreshOpenPanel(false)
    end)
end

function ns.ClosePanel()
    if listTicker then
        listTicker:Cancel()
        listTicker = nil
    end
    for _, panel in pairs(panels) do
        if type(panel) == "table" and panel.Hide then panel:Hide() end
    end
    openPanel = nil
    releaseChips()
end

-- ============================================================================
-- SECTION 11: The copy window
-- ============================================================================

local exportFrame

local EXPORT_LINE_HEIGHT = 14

-- Same defect, and same fix, as the diagnostics result column: `newScroll`
-- sizes its child once at build time, so a child left at its build height
-- measures a scroll range of zero -- the wheel does nothing and the bar never
-- appears. Everything past the first screen of a long report was unreachable,
-- while the session asks the tester to read the header "then the log after it".
-- The EditBox is sized too, not just the child: it is what actually draws the
-- lines, and a box left at the height of the frame clips them.
local function resizeExportBox()
    if not exportFrame then return end
    local scroll, box = exportFrame.scroll, exportFrame.box
    if not scroll or not scroll.child or not box then return end

    -- Two measures, the larger wins -- counting the lines needs no layout pass,
    -- GetStringHeight adds whatever the wrapping of a long line produced.
    local content = box:GetText() or ""
    local lines = 1
    for _ in content:gmatch("\n") do lines = lines + 1 end
    local measured = (box.GetStringHeight and box:GetStringHeight()) or 0
    local height = math.max(1, math.max(lines * EXPORT_LINE_HEIGHT, measured))

    box:SetHeight(height)
    scroll.child:SetHeight(height)
    -- A new report starts at the top, whatever the last one was scrolled to.
    scroll.offset = 0
    scroll:SetVerticalScroll(0)
    scroll:RefreshBar()
end

function ns.ShowTextWindow(titleText, bodyText)
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "SanctuaryExportFrame", UIParent, "BackdropTemplate")
        exportFrame:SetSize(560, 420)
        exportFrame:SetPoint("CENTER")
        exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        exportFrame:EnableMouse(true)
        exportFrame:SetMovable(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        exportFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        applyBackdrop(exportFrame, C.panel, C.border, 2)

        exportFrame.title = newLabel(exportFrame, "", FONT_SECTION, C.ink, "CENTER")
        exportFrame.title:SetPoint("TOP", exportFrame, "TOP", 0, -12)
        exportFrame.hint = newLabel(exportFrame, L["EXPORT_INSTRUCTIONS"], FONT_BODY, C.dim, "CENTER")
        exportFrame.hint:SetPoint("TOP", exportFrame.title, "BOTTOM", 0, -4)

        local scroll = newScroll(exportFrame, "SanctuaryExportScroll", 520, 320)
        scroll:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 14, -52)
        exportFrame.scroll = scroll
        local box = CreateFrame("EditBox", nil, scroll.child)
        box:SetMultiLine(true)
        box:SetFontObject("ChatFontNormal")
        box:SetAutoFocus(true)
        box:SetWidth(510)
        box:SetTextInsets(4, 4, 4, 4)
        box:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, 0)
        box:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
        exportFrame.box = box

        exportFrame.close = newButton(exportFrame, nil, L["EXPORT_CLOSE"], 100, 24, function()
            exportFrame:Hide()
        end)
        exportFrame.close:SetPoint("BOTTOM", exportFrame, "BOTTOM", 0, 12)
    end

    exportFrame.title:SetText(titleText or "")
    local box = exportFrame.box
    box:SetText("")
    -- Inserted in 200-character slices: SetMaxLetters is unreliable on this
    -- client and a single SetText of a long report truncates silently.
    local chunkSize = 200
    bodyText = bodyText or ""
    if #bodyText <= chunkSize then
        box:SetText(bodyText)
    else
        box:SetText(bodyText:sub(1, chunkSize))
        for i = chunkSize + 1, #bodyText, chunkSize do
            box:Insert(bodyText:sub(i, math.min(i + chunkSize - 1, #bodyText)))
        end
    end
    resizeExportBox()
    box:SetCursorPosition(0)
    box:HighlightText()
    exportFrame:Show()
end

-- ============================================================================
-- SECTION 12: Confirmations
-- ============================================================================

StaticPopupDialogs["SANCTUARY_CLEAR_LOG"] = {
    text = L["LOGS_CLEAR_CONFIRM"],
    button1 = L["LOGS_CLEAR_YES"],
    button2 = L["LOGS_CLEAR_NO"],
    OnAccept = function()
        if not SanctuaryDB then return end
        wipe(SanctuaryDB.log)
        ns.printSuccess(L["LOG_CLEARED"])
        if ns.refreshUI then ns.refreshUI() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["SANCTUARY_CLEAR_DEBUG_LOG"] = {
    text = L["DEBUG_CLEAR_CONFIRM"],
    button1 = L["LOGS_CLEAR_YES"],
    button2 = L["LOGS_CLEAR_NO"],
    OnAccept = function()
        if ns.resetDebugLog then
            ns.resetDebugLog()
            ns.printSuccess(L["DEBUG_CLEARED_MSG"])
            if ns.refreshUI then ns.refreshUI() end
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ============================================================================
-- SECTION 13: Frame, header, tabs
-- ============================================================================

local function refreshStateButton()
    if not stateButton then return end
    local on = ns.isEnabled()
    stateButton.label:SetText(on and L["HEADER_STATE_ON"] or L["HEADER_STATE_OFF"])
    stateButton.label:SetTextColor(unpack(on and C.green or C.dim))
    applyBackdrop(stateButton, on and C.greenBg or C.tabOff, on and C.green or C.border)
end

local KIND_LABEL_KEYS = {
    groupInvite = "KIND_GROUP_INVITE", whisper = "KIND_WHISPER", duel = "KIND_DUEL",
    trade = "KIND_TRADE", guildInvite = "KIND_GUILD_INVITE",
}

local function stateTooltipText()
    local info = ns.describeProtection and ns.describeProtection()
        or { enabled = true, kinds = {}, allowedCount = 0 }
    local parts = {}
    for _, kind in ipairs(info.kinds) do
        local key = KIND_LABEL_KEYS[kind]
        if key then parts[#parts + 1] = L[key] end
    end
    local lines = {}
    lines[#lines + 1] = #parts > 0 and (table.concat(parts, ", ") .. ".") or L["HEADER_TIP_NOTHING"]
    lines[#lines + 1] = string.format(L["HEADER_TIP_ALLOWED"], tostring(info.allowedCount))
    lines[#lines + 1] = info.enabled and L["HEADER_TIP_CLICK_OFF"] or L["HEADER_TIP_CLICK_ON"]
    return table.concat(lines, "\n")
end

local function layoutTabs()
    local visible = {}
    for _, def in ipairs(TAB_DEFS) do
        local btn = tabButtons[def.key]
        if isTabVisible(def) then
            visible[#visible + 1] = def
            btn:Show()
        else
            btn:Hide()
        end
    end
    local x = 12
    for _, def in ipairs(visible) do
        local btn = tabButtons[def.key]
        local width = math.max(70, (#L[def.labelKey] * 8) + 20)
        btn:SetSize(width, TAB_HEIGHT)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", x, 0)
        x = x + width + 2
        local current = (def.key == activeTab)
        -- The current tab is flush with the frame: same fill, no top border, so
        -- it reads as part of the window rather than as a button under it.
        applyBackdrop(btn, current and C.panel or C.tabOff, C.border)
        btn.label:SetTextColor(unpack(current and C.accent or C.dim))
    end
end

-- Fitted by default: the window is as tall as the screen it shows, within its
-- bounds. Beyond them -- "I choose" unfolded is taller than 700 -- the content
-- scrolls rather than being cut off, which is also what the manual mode needs
-- when the person makes the window smaller than its content.
-- The height the active screen last asked for. `applyHeight` gets it from the
-- screen's own refresh; `applyViewport` fires on every pixel of a drag, has no
-- refresh to ask, and reuses the last answer.
local fittedNeed = MIN_HEIGHT

-- The content area is anchored on one point with an explicit size, so nothing
-- moves it on its own: whoever changes the window's height has to hand the new
-- height here. `applyHeight` does it after its own SetSize, and the window's
-- OnSizeChanged does it while the grip is being dragged. It never resizes the
-- window itself, so calling it from OnSizeChanged cannot loop.
local function applyViewport(frameHeight)
    if not contentScroll or not contentFrame then return end
    local viewport = math.max(120, (frameHeight or MIN_FRAME_HEIGHT) - HEADER_HEIGHT - CONTENT_BOTTOM)
    contentScroll:SetSize(FRAME_WIDTH, viewport)
    local contentHeight = math.max(fittedNeed, viewport)
    contentFrame:SetHeight(contentHeight)
    local active = tabFrames[activeTab]
    if active then active:SetHeight(contentHeight) end
    contentScroll:RefreshBar()
end

local function applyHeight(height)
    if not mainFrame then return end
    -- SavedVariables is the source of truth for the manual size, not a copy made
    -- at build time: the schema reset clears it, and a stale copy would keep
    -- applying a size the settings no longer hold.
    manualSize = SanctuaryDB and SanctuaryDB.uiSize or nil
    local needed = math.max(MIN_HEIGHT, height or MIN_HEIGHT)
    fittedNeed = needed
    local frameHeight
    if manualSize then
        -- The stored width is never read back. Slot 1 stays in the record for
        -- the shape's sake, and a settings file written before the bounds
        -- existed can carry any height at all, so it is clamped here too.
        frameHeight = manualSize[2] or MIN_FRAME_HEIGHT
        frameHeight = math.min(MAX_FRAME_HEIGHT, math.max(MIN_FRAME_HEIGHT, frameHeight))
    else
        local bounded = math.min(MAX_HEIGHT, needed)
        frameHeight = bounded + HEADER_HEIGHT + CONTENT_BOTTOM
    end
    mainFrame:SetSize(FRAME_WIDTH, frameHeight)
    applyViewport(frameHeight)
end

local function selectTab(key)
    if not isTabVisible(tabDefByKey(key)) then return end
    activeTab = key
    for _, def in ipairs(TAB_DEFS) do
        local frame = tabFrames[def.key]
        if frame then
            if def.key == key then frame:Show() else frame:Hide() end
        end
    end
    layoutTabs()
    if ns.refreshUI then ns.refreshUI() end
end

function ns.refreshTabBar()
    layoutTabs()
    -- Unticking debug mode while its own panel is open must not leave it on
    -- screen: fall back to a tab that still exists.
    if not isTabVisible(tabDefByKey(activeTab)) then
        selectTab("protection")
    end
end

function ns.refreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end
    refreshStateButton()
    layoutTabs()
    local height = MIN_HEIGHT
    local refresh = refreshTab[activeTab]
    if refresh then height = refresh() or MIN_HEIGHT end
    applyHeight(height)
    refreshOpenPanel(true)
end

local function clearTransientFields()
    if protection.testInput then
        protection.testInput:SetText("")
        protection.testInput:RefreshHint()
    end
    if protection.testAnswer then protection.testAnswer:SetText("") end
    for _, panel in pairs(panels) do
        if type(panel) == "table" then
            for _, key in ipairs({ "addInput", "nameInput", "patternInput" }) do
                local box = panel[key]
                if box and box.SetText then
                    box:SetText("")
                    box:RefreshHint()
                end
            end
        end
    end
    clearDiagnosticsPanel()
    clearUndo()
end

local function createMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "SanctuaryMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(FRAME_WIDTH, MIN_HEIGHT + HEADER_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    -- Same value on both sides for the width: the grip may only change the
    -- height. Under pcall because SetResizeBounds is the Retail spelling and a
    -- missing method must not take the window down with it.
    pcall(mainFrame.SetResizeBounds, mainFrame,
        FRAME_WIDTH, MIN_FRAME_HEIGHT, FRAME_WIDTH, MAX_FRAME_HEIGHT)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()
    applyBackdrop(mainFrame, C.panel, C.border, 2)

    if SanctuaryDB and SanctuaryDB.uiPosition then
        local pos = SanctuaryDB.uiPosition
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
    if SanctuaryDB and SanctuaryDB.uiSize then
        manualSize = { SanctuaryDB.uiSize[1], SanctuaryDB.uiSize[2] }
    end

    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if SanctuaryDB then SanctuaryDB.uiPosition = { point = point, x = x, y = y } end
    end)
    tinsert(UISpecialFrames, "SanctuaryMainFrame")

    -- Header: a title, one control, a cross. Nothing else.
    local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    applyBackdrop(header, C.header, C.border)

    local title = newLabel(header, "Sanctuary", 18, C.accent)
    title:SetPoint("LEFT", header, "LEFT", 16, 0)

    stateButton = CreateFrame("Button", "SanctuaryStateButton", header, "BackdropTemplate")
    stateButton:SetSize(180, 24)
    stateButton:SetPoint("RIGHT", header, "RIGHT", -46, 0)
    stateButton.label = newLabel(stateButton, "", FONT_DESC, C.green, "CENTER")
    stateButton.label:SetPoint("CENTER")
    stateButton:SetScript("OnClick", function()
        ns.setEnabled(not ns.isEnabled())
        if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
        ns.refreshUI()
    end)
    stateButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(stateTooltipText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    stateButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    closeBtn.label = newLabel(closeBtn, "X", FONT_SECTION, C.dim, "CENTER")
    closeBtn.label:SetPoint("CENTER")
    closeBtn:SetScript("OnEnter", function() closeBtn.label:SetTextColor(unpack(C.red)) end)
    closeBtn:SetScript("OnLeave", function() closeBtn.label:SetTextColor(unpack(C.dim)) end)
    closeBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        mainFrame:Hide()
    end)

    contentScroll = newScroll(mainFrame, "SanctuaryContentScroll", FRAME_WIDTH, MIN_HEIGHT)
    contentScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -HEADER_HEIGHT)
    contentFrame = contentScroll.child

    -- The content follows the window while the grip is being dragged, not only
    -- once it is released. `applyViewport` never resizes the window, so this
    -- cannot feed back into itself.
    mainFrame:SetScript("OnSizeChanged", function(self)
        applyViewport(self:GetHeight())
    end)

    for _, def in ipairs(TAB_DEFS) do
        local frame = CreateFrame("Frame", "SanctuaryTabContent_" .. def.key, contentFrame)
        frame:SetSize(FRAME_WIDTH, MIN_HEIGHT)
        frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
        frame:Hide()
        tabFrames[def.key] = frame

        local btn = CreateFrame("Button", "SanctuaryTab_" .. def.key, mainFrame, "BackdropTemplate")
        btn:SetSize(80, TAB_HEIGHT)
        btn.label = newLabel(btn, L[def.labelKey], FONT_BODY, C.dim, "CENTER")
        btn.label:SetPoint("CENTER")
        local key = def.key
        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(key)
        end)
        tabButtons[def.key] = btn
    end

    -- The undo line sits above the tabs so it is visible whichever screen is up.
    undoLine = CreateFrame("Frame", "SanctuaryUndoLine", mainFrame, "BackdropTemplate")
    undoLine:SetSize(FRAME_WIDTH - PAD * 2, 22)
    undoLine:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", PAD, 6)
    applyBackdrop(undoLine, C.tile, C.border)
    undoLine.label = newLabel(undoLine, "", FONT_BODY, C.soft)
    undoLine.label:SetPoint("LEFT", undoLine, "LEFT", 8, 0)
    undoLine.button = newButton(undoLine, nil, L["UNDO_BTN"], 90, 18, function()
        if undoState and undoState.restore then undoState.restore() end
        clearUndo()
        if ns.refreshUI then ns.refreshUI() end
    end)
    undoLine.button:SetPoint("LEFT", undoLine.label, "RIGHT", 12, 0)
    undoLine:Hide()

    -- Grip: dragging switches to manual sizing, double-clicking goes back to
    -- fitted. No numeric size setting -- decision 61.
    resizeGrip = CreateFrame("Button", "SanctuaryResizeGrip", mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip.lastClick = 0
    resizeGrip.sizing = false
    resizeGrip:SetScript("OnMouseDown", function()
        local now = GetTime()
        if now - (resizeGrip.lastClick or 0) < 0.4 then
            resizeGrip.lastClick = 0
            resizeGrip.sizing = false
            manualSize = nil
            if SanctuaryDB then SanctuaryDB.uiSize = nil end
            ns.refreshUI()
            return
        end
        resizeGrip.lastClick = now
        resizeGrip.sizing = true
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        -- The second click of a double-click never started a resize: it cleared
        -- the remembered size and went back to the fitted mode. Recording the
        -- current size here unconditionally put it straight back on the button
        -- release, so the way back to the fitted mode did not survive the click.
        if not resizeGrip.sizing then return end
        resizeGrip.sizing = false
        -- Height only: the width is fixed by the resize bounds and by every
        -- frame the window is built from.
        manualSize = { FRAME_WIDTH, mainFrame:GetHeight() }
        if SanctuaryDB then SanctuaryDB.uiSize = { manualSize[1], manualSize[2] } end
        -- Recording the size is not applying it. The content area keeps the
        -- height it was given by the last refresh until something hands it the
        -- new one, so a drag left the screen either floating in a taller window
        -- or spilling out under a shorter one, over the tab strip, with no bar.
        ns.refreshUI()
    end)

    buildProtectionTab(tabFrames.protection)
    buildJournalTab(tabFrames.journal)
    buildAdvancedTab(tabFrames.advanced)
    buildAboutTab(tabFrames.about)
    buildDiagnosticsTab(tabFrames.diagnostics)
    buildAllowedPanel()
    buildBlockedPanel()

    mainFrame:SetScript("OnShow", function()
        ns.refreshTabBar()
        ns.refreshUI()
    end)
    mainFrame:SetScript("OnHide", function()
        ns.ClosePanel()
        clearTransientFields()
    end)

    selectTab("protection")
    return mainFrame
end

function ns.ToggleUI()
    local frame = createMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ============================================================================
-- SECTION 14: Minimap button
-- ============================================================================

local minimapButton

-- Pure, so the harness can prove it without a mouse: cursor position and the
-- minimap centre in, angle out.
function ns.minimapAngleFromPosition(cx, cy, px, py)
    local dx, dy = px - cx, py - cy
    if dx == 0 and dy == 0 then return 0 end
    local angle = math.deg(math.atan(dy, dx))
    if angle < 0 then angle = angle + 360 end
    return angle
end

local function positionMinimapButton()
    if not minimapButton or not SanctuaryDB then return end
    local angle = math.rad(SanctuaryDB.minimap.angle or 220)
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.RefreshMinimapButton()
    if not minimapButton or not SanctuaryDB then return end
    if SanctuaryDB.minimap.hide then
        minimapButton:Hide()
        return
    end
    minimapButton:Show()
    positionMinimapButton()
    if minimapButton.icon and minimapButton.icon.SetDesaturated then
        minimapButton.icon:SetDesaturated(not ns.isEnabled())
    end
end

-- A failure here stays local to the button: /sanc must open the window on a
-- client where the minimap is not what we expect.
local function createMinimapButton()
    if minimapButton or type(Minimap) ~= "table" then return end
    local ok = pcall(function()
        local btn = CreateFrame("Button", "SanctuaryMinimapButton", Minimap)
        btn:SetSize(31, 31)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(8)

        -- The icon comes from the manifest rather than from a second copy of
        -- the path here: two places to change is one place to forget.
        local iconTexture = "Interface\\Icons\\inv_shield_06"
        local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
        if type(getMetadata) == "function" then
            local ok, declared = pcall(getMetadata, ADDON_NAME, "IconTexture")
            if ok and type(declared) == "string" and declared ~= "" then
                iconTexture = declared
            end
        end
        btn.icon = btn:CreateTexture(nil, "BACKGROUND")
        btn.icon:SetSize(20, 20)
        btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.icon:SetTexture(iconTexture)
        -- Cropped square so the round tracking border does not cut the artwork.
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.border = btn:CreateTexture(nil, "OVERLAY")
        btn.border:SetSize(53, 53)
        btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn:SetMovable(true)
        btn:SetScript("OnDragStart", function(self) self.dragging = true end)
        btn:SetScript("OnDragStop", function(self)
            self.dragging = false
            local cx, cy = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale() or 1
            if cx and cy and px and py then
                SanctuaryDB.minimap.angle = ns.minimapAngleFromPosition(cx, cy, px / scale, py / scale)
                positionMinimapButton()
            end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                ns.setEnabled(not ns.isEnabled())
                ns.RefreshMinimapButton()
                if mainFrame and mainFrame:IsShown() then ns.refreshUI() end
            else
                ns.ToggleUI()
            end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(string.format(L["MINIMAP_TIP_TITLE"],
                ns.isEnabled() and L["HEADER_STATE_ON"] or L["HEADER_STATE_OFF"]), 1, 1, 1)
            GameTooltip:AddLine(L["MINIMAP_TIP_LEFT"], 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["MINIMAP_TIP_RIGHT"], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        minimapButton = btn
    end)
    if ok then ns.RefreshMinimapButton() end
end

-- ============================================================================
-- SECTION 15: Right-click menu on a player
-- ============================================================================

-- Two entries, no protected call, no combat-state read: nothing here can taint
-- an execution path. When the API or the identity is missing, nothing is added
-- and nothing is said -- the panels are the universal fallback.
local MENU_TAGS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_FRIEND", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_CHAT_ROSTER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
}

local function resolveMenuName(contextData)
    if type(contextData) ~= "table" then return nil end
    local name = contextData.name
    if name == nil or name == "" then return nil end
    if ns.isRestrictedValue and ns.isRestrictedValue(name) then return nil end
    if type(C_Secrets) == "table" and type(C_Secrets.ShouldUnitIdentityBeSecret) == "function"
        and contextData.unit then
        local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, contextData.unit)
        if ok and secret then return nil end
    end
    local full = name
    if contextData.server and contextData.server ~= "" then
        full = name .. "-" .. contextData.server
    end
    if contextData.unit and UnitIsUnit and UnitIsUnit(contextData.unit, "player") then return nil end
    local playerName = UnitName and UnitName("player")
    if playerName and tostring(name):lower() == tostring(playerName):lower() then return nil end
    return full
end

function ns.buildPlayerMenuEntries(contextData)
    if InCombatLockdown and InCombatLockdown() then return {} end
    if type(C_ChatInfo) == "table" and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return {} end
    end
    local name = resolveMenuName(contextData)
    if not name then return {} end

    local allowedKey = ns.normalizeName and ns.normalizeName(name)
    local isAllowed = allowedKey and SanctuaryDB and SanctuaryDB.manualWhitelist
        and SanctuaryDB.manualWhitelist[allowedKey] ~= nil
    -- The same resolution the core uses to decide -- full "Name-Realm" key, then
    -- the bare name -- rather than an exact search on the full key. A name
    -- blocked bare from the panel blocks every realm, so an exact search missed
    -- it: the menu on "Bareprobe-Ysondre" offered to block someone already
    -- blocked, the click wrote a second key, and removing either of the two left
    -- the other one still blocking.
    local blockedKey = ns.findBlockedKey and ns.findBlockedKey(name)
    local isBlocked = blockedKey ~= nil

    return {
        {
            text = isAllowed and L["MENU_UNALLOW"] or L["MENU_ALLOW"],
            action = function()
                if isAllowed then ns.removeAllowed(allowedKey) else ns.addAllowed(name, "menu") end
                if ns.refreshUI then ns.refreshUI() end
            end,
        },
        {
            text = isBlocked and L["MENU_UNBLOCK"] or L["MENU_BLOCK"],
            action = function()
                if isBlocked then ns.removeBlocked(blockedKey) else ns.addBlocked(name, "menu") end
                if ns.refreshUI then ns.refreshUI() end
            end,
        },
    }
end

local function installPlayerMenu()
    if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then return end
    for _, tag in ipairs(MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, function(owner, rootDescription, contextData)
            local entries = ns.buildPlayerMenuEntries(contextData)
            if #entries == 0 then return end
            if rootDescription.CreateDivider then rootDescription:CreateDivider() end
            for _, entry in ipairs(entries) do
                if rootDescription.CreateButton then
                    rootDescription:CreateButton(entry.text, entry.action)
                end
            end
        end)
    end
end

-- ============================================================================
-- SECTION 16: Load
-- ============================================================================

-- Named rather than inlined in the event handler: the harness replaces
-- CreateFrame with a widget mock before loading this file, so its event frame is
-- not the one the core registered on. What the login does has to be reachable
-- by name, or none of it could be proved without a client.
function ns.InitializeUI()
    createMinimapButton()
    installPlayerMenu()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    ns.InitializeUI()
end)
