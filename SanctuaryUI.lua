-- ============================================================================
-- SanctuaryUI.lua — Configuration interface for Sanctuary anti-harassment addon
-- Pure Lua, no XML, no external libraries. WoW Midnight compatible (120001).
-- ============================================================================

local ADDON_NAME, ns = ...
local L = ns.L

-- ============================================================================
-- SECTION 1: Local References & Constants
-- ============================================================================

local FRAME_WIDTH = 620
local FRAME_HEIGHT = 480
local HEADER_HEIGHT = 36
local TAB_BAR_HEIGHT = 28
local STATUS_BAR_HEIGHT = 24
local CONTENT_PADDING = 12
local CHECKBOX_HEIGHT = 22
local CHECKBOX_SPACING = 4
local SECTION_SPACING = 14

-- Color constants (RGBA)
local BG_COLOR = { 0.05, 0.05, 0.1, 0.92 }
local BORDER_COLOR = { 0.3, 0.3, 0.4, 0.8 }
local TAB_ACTIVE_COLOR = { 0.15, 0.15, 0.25, 1.0 }
local TAB_INACTIVE_COLOR = { 0.08, 0.08, 0.14, 0.9 }
local TAB_HOVER_COLOR = { 0.12, 0.12, 0.2, 1.0 }
local ACCENT_BLUE = { 0.4, 0.6, 1.0, 1.0 }
local HIGHLIGHT_COLOR = { 1.0, 1.0, 1.0, 1.0 }
local DIM_COLOR = { 0.6, 0.6, 0.6, 1.0 }
local RED_COLOR = { 1.0, 0.27, 0.27, 1.0 }
local ENTRY_BG = { 0.08, 0.08, 0.14, 0.6 }
local BUTTON_NORMAL = { 0.15, 0.15, 0.25, 1.0 }
local BUTTON_HOVER = { 0.25, 0.25, 0.4, 1.0 }
local BUTTON_PRESSED = { 0.1, 0.1, 0.18, 1.0 }

-- Localized labels for filter checkboxes
local FILTER_LABELS = {
    groupInvite    = L["FILTER_GROUP_INVITE"],
    whisper        = L["FILTER_WHISPER"],
    say            = L["FILTER_SAY"],
    yell           = L["FILTER_YELL"],
    emote          = L["FILTER_EMOTE"],
    duel           = L["FILTER_DUEL"],
    trade          = L["FILTER_TRADE"],
    guildInvite    = L["FILTER_GUILD_INVITE"],
}

local FILTER_TOOLTIPS = {
    groupInvite    = L["TIP_GROUP_INVITE"],
    whisper        = L["TIP_WHISPER"],
    say            = L["TIP_SAY"],
    yell           = L["TIP_YELL"],
    emote          = L["TIP_EMOTE"],
    duel           = L["TIP_DUEL"],
    trade          = L["TIP_TRADE"],
    guildInvite    = L["TIP_GUILD_INVITE"],
}


-- Filter groups for the Filters tab
local FILTER_GROUPS = {
    {
        title = L["GROUP_MAIN_PROTECTION"],
        keys  = { "groupInvite" },
    },
    {
        title = L["GROUP_COMMUNICATION"],
        keys  = { "whisper", "say", "yell", "emote" },
    },
    {
        title = L["GROUP_INTERACTIONS"],
        keys  = { "duel", "trade", "guildInvite" },
    },
}

-- Tab definitions (name, builder function -- assigned later)
local TAB_DEFS = {
    { name = L["TAB_FILTERS"],   key = "filters"   },
    { name = L["TAB_SUSPECTS"],  key = "keywords"  },
    { name = L["TAB_WHITELIST"], key = "whitelist" },
    { name = L["TAB_LOGS"],      key = "logs"      },
}

-- ============================================================================
-- SECTION 2: Utility Helpers
-- ============================================================================

-- Apply backdrop to a frame using BackdropTemplate mixin
local function applyBackdrop(frame, bgColor, borderColor, edgeSize, insets)
    edgeSize = edgeSize or 1
    insets = insets or { left = 0, right = 0, top = 0, bottom = 0 }

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = edgeSize,
            insets   = insets,
        })
        if bgColor then
            frame:SetBackdropColor(unpack(bgColor))
        end
        if borderColor then
            frame:SetBackdropBorderColor(unpack(borderColor))
        end
    end
end

-- Create a simple text label
local function createLabel(parent, text, size, color, justifyH)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontFile = label:GetFont()
    label:SetFont(fontFile, size or 12, "")
    label:SetTextColor(unpack(color or HIGHLIGHT_COLOR))
    label:SetText(text or "")
    if justifyH then
        label:SetJustifyH(justifyH)
    end
    return label
end

-- Create a styled button
local function createButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 24)
    applyBackdrop(btn, BUTTON_NORMAL, BORDER_COLOR)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("CENTER")
    local fontFile = btn.label:GetFont()
    btn.label:SetFont(fontFile, 11, "")
    btn.label:SetTextColor(unpack(HIGHLIGHT_COLOR))
    btn.label:SetText(text or "")

    btn:SetScript("OnEnter", function(self)
        applyBackdrop(self, BUTTON_HOVER, ACCENT_BLUE)
    end)
    btn:SetScript("OnLeave", function(self)
        applyBackdrop(self, BUTTON_NORMAL, BORDER_COLOR)
    end)
    btn:SetScript("OnMouseDown", function(self)
        applyBackdrop(self, BUTTON_PRESSED, BORDER_COLOR)
    end)
    btn:SetScript("OnMouseUp", function(self)
        applyBackdrop(self, BUTTON_HOVER, ACCENT_BLUE)
    end)
    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

-- Create a checkbox with label
local function createCheckbox(parent, label, tooltip, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(CHECKBOX_HEIGHT)

    -- Try UICheckButtonTemplate first, fall back to manual
    local cb
    local ok = pcall(function()
        cb = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    end)
    if not ok or not cb then
        cb = CreateFrame("CheckButton", nil, container)
        cb:SetSize(20, 20)
        -- Manual checkbox textures
        local normal = cb:CreateTexture(nil, "ARTWORK")
        normal:SetAllPoints()
        normal:SetColorTexture(0.15, 0.15, 0.2, 1.0)
        cb:SetNormalTexture(normal)

        local checked = cb:CreateTexture(nil, "OVERLAY")
        checked:SetPoint("CENTER")
        checked:SetSize(12, 12)
        checked:SetColorTexture(0.3, 0.7, 1.0, 1.0)
        cb:SetCheckedTexture(checked)

        local highlight = cb:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1.0, 1.0, 1.0, 0.1)
        cb:SetHighlightTexture(highlight)
    end

    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", container, "LEFT", 0, 0)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontFile = text:GetFont()
    text:SetFont(fontFile, 11, "")
    text:SetTextColor(0.9, 0.9, 0.9, 1.0)
    text:SetText(label or "")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", container, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    container.checkbox = cb
    container.text = text

    -- Tooltip on hover
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    if onChange then
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            onChange(checked)
        end)
    end

    return container
end

-- ============================================================================
-- SECTION 3: Main Frame Construction
-- ============================================================================

local mainFrame = nil
local tabFrames = {}
local tabButtons = {}
local activeTab = nil
local statusBar = nil

-- All checkbox references for refresh
local filterCheckboxes = {}
-- Whitelist tab state
local whitelistEntries = {}
local whitelistEntryPool = {}
local whitelistScrollChild = nil
local whitelistCountLabel = nil

-- Log tab state
local logScrollChild = nil
local logCountLabel = nil
local expandedGroups = {}
local allExpanded = false

-- Keyword tab state
local keywordEntries = {}
local keywordEntryPool = {}
local keywordScrollChild = nil
local keywordCountLabel = nil

-- Notification radio state (Filters tab)
local notifCheckboxes = {}

-- Channel filtering radio state (Filters tab)
local channelCheckboxes = {}

-- Auto-trust checkbox reference (Filters tab)
local autoTrustCb = nil

-- Forward declarations for local functions
local selectTab, refreshTabContent, refreshToggle, refreshStatusBar
local buildFiltersTab, refreshFilterCheckboxes
local buildKeywordsTab, refreshKeywordEntries
local buildWhitelistTab, refreshWhitelistEntries
local buildLogsTab, refreshLogEntries

StaticPopupDialogs["SANCTUARY_CLEAR_LOG"] = {
    text = L["LOGS_CLEAR_CONFIRM"],
    button1 = L["LOGS_CLEAR_YES"],
    button2 = L["LOGS_CLEAR_NO"],
    OnAccept = function()
        if SanctuaryDB then
            wipe(SanctuaryDB.log)
            ns.printSuccess(L["LOG_CLEARED"])
            if refreshLogEntries then refreshLogEntries() end
            if refreshStatusBar then refreshStatusBar() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function createMainFrame()
    if mainFrame then return mainFrame end

    -- Main container frame
    mainFrame = CreateFrame("Frame", "SanctuaryMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetResizable(true)
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizeBounds(500, 380, 900, 700)
    elseif mainFrame.SetMinResize then
        mainFrame:SetMinResize(500, 380)
        mainFrame:SetMaxResize(900, 700)
    end
    mainFrame:Hide()

    applyBackdrop(mainFrame, BG_COLOR, BORDER_COLOR, 2)

    -- Restore saved position
    if SanctuaryDB and SanctuaryDB.uiPosition then
        local pos = SanctuaryDB.uiPosition
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
            pos.x or 0, pos.y or 0)
    end

    -- Restore saved size
    if SanctuaryDB and SanctuaryDB.uiSize then
        local size = SanctuaryDB.uiSize
        mainFrame:SetSize(size[1] or FRAME_WIDTH, size[2] or FRAME_HEIGHT)
    end

    -- Dragging
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        if SanctuaryDB then
            SanctuaryDB.uiPosition = { point = point, x = x, y = y }
        end
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "SanctuaryMainFrame")

    -- ========================================================================
    -- Header bar
    -- ========================================================================
    local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    applyBackdrop(header, { 0.08, 0.08, 0.15, 1.0 }, BORDER_COLOR)

    -- Title (addon name, not localized -- proper noun)
    local title = createLabel(header, "Sanctuary", 14, ACCENT_BLUE, "LEFT")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)

    -- Master toggle button
    local toggleBtn = createButton(header, "", 70, 22, function()
        if not SanctuaryCharDB then return end
        local current = ns.isEnabled()
        SanctuaryCharDB.overrides.enabled = not current
        if ns.isEnabled() then
            if ns.muteInviteSounds then ns.muteInviteSounds() end
            ns.printSuccess(L["SANCTUARY_ENABLED"])
        else
            if ns.unmuteInviteSounds then ns.unmuteInviteSounds() end
            ns.printMsg(ns.COLOR_OFF .. L["SANCTUARY_DISABLED"] .. ns.COLOR_RESET)
        end
        -- Refresh toggle visual and status bar
        refreshToggle()
        refreshStatusBar()
    end)
    toggleBtn:SetPoint("RIGHT", header, "RIGHT", -40, 0)
    mainFrame.toggleBtn = toggleBtn

    -- Close [X] button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(HEADER_HEIGHT - 8, HEADER_HEIGHT - 8)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -6, 0)

    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fontFile = closeLabel:GetFont()
    closeLabel:SetFont(fontFile, 16, "OUTLINE")
    closeLabel:SetTextColor(0.7, 0.7, 0.7, 1.0)
    closeLabel:SetText("X")
    closeLabel:SetPoint("CENTER")

    closeBtn:SetScript("OnEnter", function()
        closeLabel:SetTextColor(1.0, 0.3, 0.3, 1.0)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeLabel:SetTextColor(0.7, 0.7, 0.7, 1.0)
    end)
    closeBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        mainFrame:Hide()
    end)

    -- Resize grip (bottom-right corner)
    local resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        if SanctuaryDB then
            SanctuaryDB.uiSize = { mainFrame:GetWidth(), mainFrame:GetHeight() }
        end
    end)

    mainFrame:SetScript("OnSizeChanged", function(self, w, h)
        -- Recalculate tab button widths on resize
        local newTabWidth = w / #TAB_DEFS
        for i, def in ipairs(TAB_DEFS) do
            local tab = tabButtons[def.key]
            if tab then
                tab:SetSize(newTabWidth, TAB_BAR_HEIGHT)
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", tab:GetParent(), "TOPLEFT", (i - 1) * newTabWidth, 0)
            end
        end
        -- Refresh active tab content on resize
        C_Timer.After(0.05, function()
            if activeTab then
                refreshTabContent(activeTab)
            end
            refreshStatusBar()
        end)
    end)

    -- ========================================================================
    -- Tab bar
    -- ========================================================================
    local tabBar = CreateFrame("Frame", nil, mainFrame)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    tabBar:SetHeight(TAB_BAR_HEIGHT)

    local tabWidth = FRAME_WIDTH / #TAB_DEFS
    for i, def in ipairs(TAB_DEFS) do
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, TAB_BAR_HEIGHT)
        tab:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i - 1) * tabWidth, 0)
        applyBackdrop(tab, TAB_INACTIVE_COLOR, BORDER_COLOR)

        local tabLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local tf = tabLabel:GetFont()
        tabLabel:SetFont(tf, 11, "")
        tabLabel:SetTextColor(unpack(DIM_COLOR))
        tabLabel:SetText(def.name)
        tabLabel:SetPoint("CENTER")
        tab.label = tabLabel

        tab:SetScript("OnEnter", function(self)
            if activeTab ~= def.key then
                applyBackdrop(self, TAB_HOVER_COLOR, BORDER_COLOR)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if activeTab ~= def.key then
                applyBackdrop(self, TAB_INACTIVE_COLOR, BORDER_COLOR)
            end
        end)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(def.key)
        end)

        tabButtons[def.key] = tab
    end

    -- ========================================================================
    -- Content area (one frame per tab, shown/hidden)
    -- ========================================================================
    local contentTop = HEADER_HEIGHT + TAB_BAR_HEIGHT
    local contentHeight = FRAME_HEIGHT - contentTop - STATUS_BAR_HEIGHT

    for _, def in ipairs(TAB_DEFS) do
        local content = CreateFrame("Frame", nil, mainFrame)
        content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -contentTop)
        content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, STATUS_BAR_HEIGHT)
        content:Hide()
        tabFrames[def.key] = content
    end

    -- Build each tab content
    buildFiltersTab(tabFrames["filters"])
    buildKeywordsTab(tabFrames["keywords"])
    buildWhitelistTab(tabFrames["whitelist"])
    buildLogsTab(tabFrames["logs"])

    -- ========================================================================
    -- Status bar
    -- ========================================================================
    statusBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    statusBar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
    statusBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    statusBar:SetHeight(STATUS_BAR_HEIGHT)
    applyBackdrop(statusBar, { 0.06, 0.06, 0.12, 1.0 }, BORDER_COLOR)

    statusBar.text = createLabel(statusBar, "", 10, DIM_COLOR, "CENTER")
    statusBar.text:SetPoint("CENTER")

    -- ========================================================================
    -- On show/hide hooks
    -- ========================================================================
    mainFrame:SetScript("OnShow", function()
        refreshToggle()
        refreshStatusBar()
        -- Refresh active tab content
        if activeTab then
            refreshTabContent(activeTab)
        end
    end)

    -- Select default tab
    selectTab("filters")

    return mainFrame
end

-- ============================================================================
-- SECTION 4: Tab Selection & Refresh
-- ============================================================================

selectTab = function(key)
    -- Hide all tabs, show selected
    for tabKey, frame in pairs(tabFrames) do
        frame:Hide()
        local btn = tabButtons[tabKey]
        if btn then
            applyBackdrop(btn, TAB_INACTIVE_COLOR, BORDER_COLOR)
            btn.label:SetTextColor(unpack(DIM_COLOR))
            if btn.underline then
                btn.underline:Hide()
            end
        end
    end

    if tabFrames[key] then
        tabFrames[key]:Show()
    end
    if tabButtons[key] then
        local btn = tabButtons[key]
        applyBackdrop(btn, TAB_ACTIVE_COLOR, ACCENT_BLUE)
        btn.label:SetTextColor(unpack(HIGHLIGHT_COLOR))
        if not btn.underline then
            btn.underline = btn:CreateTexture(nil, "ARTWORK")
            btn.underline:SetHeight(2)
            btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, 0)
            btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 0)
        end
        btn.underline:SetColorTexture(0.4, 0.6, 1.0, 1.0) -- accent blue
        btn.underline:Show()
    end

    activeTab = key
    refreshTabContent(key)
end

refreshTabContent = function(key)
    if key == "filters" then
        refreshFilterCheckboxes()
    elseif key == "keywords" then
        refreshKeywordEntries()
    elseif key == "whitelist" then
        refreshWhitelistEntries()
    elseif key == "logs" then
        refreshLogEntries()
    end
end

refreshToggle = function()
    local btn = mainFrame and mainFrame.toggleBtn
    if not btn then return end
    local enabled = ns.isEnabled()
    if enabled then
        btn.label:SetText("|cFF00FF00" .. L["ON"] .. "|r")
        applyBackdrop(btn, { 0.0, 0.3, 0.0, 0.8 }, { 0.0, 0.8, 0.0, 0.8 })
    else
        btn.label:SetText("|cFFFF4444" .. L["OFF"] .. "|r")
        applyBackdrop(btn, { 0.3, 0.0, 0.0, 0.8 }, { 0.8, 0.0, 0.0, 0.8 })
    end
end

refreshStatusBar = function()
    if not statusBar or not SanctuaryDB or not SanctuaryCharDB then return end
    local blocked = SanctuaryCharDB.sessionStats.blockedCount or 0
    local logCount = #SanctuaryDB.log
    local maxLog = SanctuaryDB.logging.maxEntries or 5000

    local keywordCount = SanctuaryDB.keywords and #SanctuaryDB.keywords or 0
    local keywordPart = ""
    if keywordCount > 0 then
        keywordPart = "  |  " .. string.format(L["STATUSBAR_SUSPECTS"], keywordCount)
    end

    statusBar.text:SetText(
        string.format(L["STATUSBAR_SESSION"], blocked) .. "  |  "
        .. string.format(L["STATUSBAR_LOG"], logCount, maxLog)
        .. keywordPart
    )
end

-- ============================================================================
-- SECTION 4b: Styled Input Helper
-- ============================================================================

local function createStyledInput(parent, width, height)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(width or 200, height or 26)
    input:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    input:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    input:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.6)
    input:SetFontObject(GameFontHighlightSmall)
    input:SetTextInsets(6, 6, 2, 2)
    input:SetAutoFocus(false)
    input:SetMaxLetters(50)
    -- Highlight border on focus
    input:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.4, 0.6, 1.0, 0.8)
    end)
    input:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.6)
    end)
    return input
end

-- ============================================================================
-- SECTION 5: Filters Tab
-- ============================================================================

buildFiltersTab = function(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, CONTENT_PADDING)

    local child = CreateFrame("Frame", nil, scroll)
    local contentWidth = scroll:GetWidth()
    if not contentWidth or contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    child:SetWidth(contentWidth)
    scroll:SetScrollChild(child)

    local yOffset = 0

    for _, group in ipairs(FILTER_GROUPS) do
        -- Section header
        local header = createLabel(child, group.title, 13, ACCENT_BLUE, "LEFT")
        header:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
        yOffset = yOffset + 20

        -- Separator line
        local sep = child:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
        sep:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -yOffset)
        sep:SetColorTexture(0.3, 0.3, 0.4, 0.4)
        yOffset = yOffset + 6

        -- Checkboxes for this group
        for _, key in ipairs(group.keys) do
            local label = FILTER_LABELS[key] or key
            local tooltip = FILTER_TOOLTIPS[key]

            local cb = createCheckbox(child, label, tooltip, function(checked)
                if SanctuaryDB and SanctuaryDB.filters then
                    SanctuaryDB.filters[key] = checked
                    refreshStatusBar()
                end
            end)
            cb:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -yOffset)
            cb:SetPoint("RIGHT", child, "RIGHT", -8, 0)

            filterCheckboxes[key] = cb.checkbox
            yOffset = yOffset + CHECKBOX_HEIGHT + CHECKBOX_SPACING
        end

        yOffset = yOffset + SECTION_SPACING
    end

    -- Notifications section
    yOffset = yOffset + SECTION_SPACING + 4

    local notifHeader = createLabel(child, L["GROUP_NOTIFICATIONS"], 12, ACCENT_BLUE, "LEFT")
    notifHeader:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
    yOffset = yOffset + 18

    local notifModes = {
        { value = "silent",  label = L["NOTIF_SILENT"],  tooltip = L["TIP_NOTIF_SILENT"] },
        { value = "minimal", label = L["NOTIF_MINIMAL"], tooltip = L["TIP_NOTIF_MINIMAL"] },
        { value = "verbose", label = L["NOTIF_VERBOSE"], tooltip = L["TIP_NOTIF_VERBOSE"] },
    }

    -- Reset file-scope table
    wipe(notifCheckboxes)

    for _, mode in ipairs(notifModes) do
        local cb = createCheckbox(child, mode.label, mode.tooltip, function(checked)
            if not checked then
                -- Prevent deselection: re-check the current mode after a frame
                C_Timer.After(0, function()
                    local currentMode = (SanctuaryDB and SanctuaryDB.notifications and SanctuaryDB.notifications.mode) or "silent"
                    for _, otherCb in ipairs(notifCheckboxes) do
                        if otherCb.modeValue == currentMode and otherCb.checkbox then
                            otherCb.checkbox:SetChecked(true)
                        end
                    end
                end)
                return
            end
            if SanctuaryDB and SanctuaryDB.notifications then
                SanctuaryDB.notifications.mode = mode.value
                -- Uncheck the other radio buttons
                for _, otherCb in ipairs(notifCheckboxes) do
                    if otherCb.modeValue ~= mode.value and otherCb.checkbox then
                        otherCb.checkbox:SetChecked(false)
                    end
                end
            end
        end)
        cb:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
        cb:SetWidth(contentWidth - 8)
        cb.modeValue = mode.value

        -- Set initial state
        if cb.checkbox then
            local currentMode = (SanctuaryDB and SanctuaryDB.notifications and SanctuaryDB.notifications.mode) or "silent"
            cb.checkbox:SetChecked(currentMode == mode.value)
        end

        notifCheckboxes[#notifCheckboxes + 1] = cb
        yOffset = yOffset + CHECKBOX_HEIGHT + CHECKBOX_SPACING
    end

    -- Channel filtering section
    yOffset = yOffset + SECTION_SPACING + 4

    local channelHeader = createLabel(child, L["GROUP_CHANNELS"], 12, ACCENT_BLUE, "LEFT")
    channelHeader:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
    yOffset = yOffset + 18

    local channelModes = {
        { value = "none",     label = L["CHANNEL_NONE"],     tooltip = L["TIP_CHANNEL_NONE"] },
        { value = "keywords", label = L["CHANNEL_KEYWORDS"], tooltip = L["TIP_CHANNEL_KEYWORDS"] },
        { value = "all",      label = L["CHANNEL_ALL"],      tooltip = L["TIP_CHANNEL_ALL"] },
    }

    -- Reset file-scope table
    wipe(channelCheckboxes)

    for _, mode in ipairs(channelModes) do
        local cb = createCheckbox(child, mode.label, mode.tooltip, function(checked)
            if not checked then
                -- Prevent deselection: re-check the current mode after a frame
                C_Timer.After(0, function()
                    local currentMode = (SanctuaryDB and SanctuaryDB.filters and SanctuaryDB.filters.channelMode) or "none"
                    for _, otherCb in ipairs(channelCheckboxes) do
                        if otherCb.modeValue == currentMode and otherCb.checkbox then
                            otherCb.checkbox:SetChecked(true)
                        end
                    end
                end)
                return
            end
            if SanctuaryDB and SanctuaryDB.filters then
                SanctuaryDB.filters.channelMode = mode.value
                for _, otherCb in ipairs(channelCheckboxes) do
                    if otherCb.modeValue ~= mode.value and otherCb.checkbox then
                        otherCb.checkbox:SetChecked(false)
                    end
                end
            end
        end)
        cb:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
        cb:SetWidth(contentWidth - 8)
        cb.modeValue = mode.value

        if cb.checkbox then
            local currentMode = (SanctuaryDB and SanctuaryDB.filters and SanctuaryDB.filters.channelMode) or "none"
            cb.checkbox:SetChecked(currentMode == mode.value)
        end

        channelCheckboxes[#channelCheckboxes + 1] = cb
        yOffset = yOffset + CHECKBOX_HEIGHT + CHECKBOX_SPACING
    end

    -- Auto-trust section
    yOffset = yOffset + SECTION_SPACING + 4

    local trustHeader = createLabel(child, L["GROUP_AUTO_TRUST"] or "Auto-trust", 12, ACCENT_BLUE, "LEFT")
    trustHeader:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
    yOffset = yOffset + 18

    local trustCb = createCheckbox(child, L["FILTER_AUTO_TRUST"], L["TIP_AUTO_TRUST"], function(checked)
        if SanctuaryDB and SanctuaryDB.filters then
            SanctuaryDB.filters.autoTrust = checked
            ns.invalidateWhitelist()
        end
    end)
    trustCb:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -yOffset)
    trustCb:SetWidth(contentWidth - 8)
    if trustCb.checkbox and SanctuaryDB and SanctuaryDB.filters then
        trustCb.checkbox:SetChecked(SanctuaryDB.filters.autoTrust or false)
    end
    autoTrustCb = trustCb
    yOffset = yOffset + CHECKBOX_HEIGHT + CHECKBOX_SPACING

    -- Set scroll child height
    child:SetHeight(yOffset + CONTENT_PADDING)
end

refreshFilterCheckboxes = function()
    if not SanctuaryDB then return end
    for key, cb in pairs(filterCheckboxes) do
        local val = SanctuaryDB.filters and SanctuaryDB.filters[key]
        cb:SetChecked(val == true)
    end

    -- Refresh notification radio buttons
    local currentMode = (SanctuaryDB and SanctuaryDB.notifications and SanctuaryDB.notifications.mode) or "silent"
    for _, cb in ipairs(notifCheckboxes) do
        if cb.checkbox then
            cb.checkbox:SetChecked(currentMode == cb.modeValue)
        end
    end

    -- Refresh channel mode radio buttons
    local currentChannelMode = (SanctuaryDB and SanctuaryDB.filters and SanctuaryDB.filters.channelMode) or "none"
    for _, cb in ipairs(channelCheckboxes) do
        if cb.checkbox then
            cb.checkbox:SetChecked(currentChannelMode == cb.modeValue)
        end
    end

    -- Refresh auto-trust checkbox
    if autoTrustCb and autoTrustCb.checkbox and SanctuaryDB and SanctuaryDB.filters then
        autoTrustCb.checkbox:SetChecked(SanctuaryDB.filters.autoTrust or false)
    end
end

-- ============================================================================
-- SECTION 6: Keywords Tab
-- ============================================================================

buildKeywordsTab = function(parent)
    local header = createLabel(parent, L["SUSPECTS_HEADER"], 13, ACCENT_BLUE, "LEFT")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -CONTENT_PADDING)

    keywordCountLabel = createLabel(parent, "", 11, DIM_COLOR, "RIGHT")
    keywordCountLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PADDING - 4, -CONTENT_PADDING)

    local desc = createLabel(parent, L["SUSPECTS_DESC"], 10, DIM_COLOR, "LEFT")
    desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PADDING, 0)
    desc:SetWordWrap(true)

    -- Input + Add button at the top (after description)
    local inputBox = createStyledInput(parent, 200, 26)
    inputBox:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 52))
    inputBox:SetMaxLetters(30)

    local addBtn = createButton(parent, L["SUSPECTS_ADD_BTN"], 80, 24, function()
        local text = inputBox:GetText()
        if text and text ~= "" then
            text = text:lower():gsub("%s", "")
            if text ~= "" then
                if not SanctuaryDB then return end
                if not SanctuaryDB.keywords then SanctuaryDB.keywords = {} end
                for _, existing in ipairs(SanctuaryDB.keywords) do
                    if existing == text then
                        ns.printError(string.format(L["SUSPECT_DUPLICATE"], text))
                        return
                    end
                end
                table.insert(SanctuaryDB.keywords, text)
                ns.printSuccess(string.format(L["SUSPECT_ADDED"], text))
                inputBox:SetText("")
                refreshKeywordEntries()
                refreshStatusBar()
            end
        end
    end)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 6, 0)

    inputBox:SetScript("OnEnterPressed", function(self)
        addBtn:GetScript("OnClick")(addBtn)
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Scroll area (below input)
    local listTop = CONTENT_PADDING + 80
    local listBottom = CONTENT_PADDING

    local scrollFrame = CreateFrame("ScrollFrame", "SanctuaryKeywordScroll", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -listTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, listBottom)

    keywordScrollChild = CreateFrame("Frame", nil, scrollFrame)
    local contentWidth = scrollFrame:GetWidth()
    if not contentWidth or contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    keywordScrollChild:SetWidth(contentWidth)
    keywordScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(keywordScrollChild)
end

refreshKeywordEntries = function()
    if not keywordScrollChild or not SanctuaryDB or not SanctuaryDB.keywords then return end

    -- Recycle old entries
    for _, entry in ipairs(keywordEntries) do
        entry:Hide()
        table.insert(keywordEntryPool, entry)
    end
    wipe(keywordEntries)

    local keywords = SanctuaryDB.keywords
    local yOffset = 0
    local scrollParent = keywordScrollChild:GetParent()
    local contentWidth = scrollParent and scrollParent:GetWidth() or (FRAME_WIDTH - CONTENT_PADDING * 2 - 22)
    if contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    keywordScrollChild:SetWidth(contentWidth)
    local entryHeight = 24

    for i, keyword in ipairs(keywords) do
        local entry = table.remove(keywordEntryPool)
        if entry then
            entry:SetParent(keywordScrollChild)
            entry:Show()
        else
            entry = CreateFrame("Frame", nil, keywordScrollChild, "BackdropTemplate")
        end

        entry:SetHeight(entryHeight)
        entry:SetPoint("TOPLEFT", keywordScrollChild, "TOPLEFT", 0, -yOffset)
        entry:SetPoint("RIGHT", keywordScrollChild, "RIGHT", 0, 0)
        applyBackdrop(entry, ENTRY_BG, BORDER_COLOR)

        -- Keyword text
        if not entry.text then
            entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local fontFile = entry.text:GetFont()
            entry.text:SetFont(fontFile, 11, "")
            entry.text:SetPoint("LEFT", entry, "LEFT", 10, 0)
            entry.text:SetJustifyH("LEFT")
        end
        entry.text:SetText(keyword)
        entry.text:SetTextColor(1.0, 0.6, 0.2, 1.0)
        entry.text:Show()

        -- [X] delete button
        if not entry.deleteBtn then
            entry.deleteBtn = CreateFrame("Button", nil, entry)
            entry.deleteBtn:SetSize(20, 20)
            entry.deleteBtn:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
            entry.deleteBtn.label = entry.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local df = entry.deleteBtn.label:GetFont()
            entry.deleteBtn.label:SetFont(df, 12, "OUTLINE")
            entry.deleteBtn.label:SetText("X")
            entry.deleteBtn.label:SetPoint("CENTER")
            entry.deleteBtn.label:SetTextColor(0.6, 0.3, 0.3, 1.0)
            entry.deleteBtn:SetScript("OnEnter", function(self)
                self.label:SetTextColor(1.0, 0.3, 0.3, 1.0)
            end)
            entry.deleteBtn:SetScript("OnLeave", function(self)
                self.label:SetTextColor(0.6, 0.3, 0.3, 1.0)
            end)
        end
        local capturedKeyword = keyword
        entry.deleteBtn:SetScript("OnClick", function()
            if SanctuaryDB and SanctuaryDB.keywords then
                for j, kw in ipairs(SanctuaryDB.keywords) do
                    if kw == capturedKeyword then
                        table.remove(SanctuaryDB.keywords, j)
                        ns.printSuccess(string.format(L["SUSPECT_REMOVED"], capturedKeyword))
                        refreshKeywordEntries()
                        refreshStatusBar()
                        break
                    end
                end
            end
        end)
        entry.deleteBtn:Show()

        keywordEntries[#keywordEntries + 1] = entry
        yOffset = yOffset + entryHeight + 2
    end

    keywordScrollChild:SetHeight(math.max(1, yOffset))

    if keywordCountLabel then
        keywordCountLabel:SetText(string.format(L["SUSPECTS_COUNT"], #keywords))
    end
end

-- ============================================================================
-- SECTION 7: Whitelist Tab
-- ============================================================================

buildWhitelistTab = function(parent)
    -- Title + count
    local header = createLabel(parent, L["WL_HEADER"], 13, ACCENT_BLUE, "LEFT")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -CONTENT_PADDING)

    whitelistCountLabel = createLabel(parent, string.format("(%s)", string.format(L["WL_COUNT"], 0)), 11, DIM_COLOR, "RIGHT")
    whitelistCountLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PADDING - 4, -CONTENT_PADDING)

    -- Input + Add button at the top (after header)
    local inputBox = createStyledInput(parent, 200, 26)
    inputBox:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 22))
    inputBox:SetMaxLetters(64)

    local addBtn = createButton(parent, L["WL_ADD_BTN"], 80, 24, function()
        local text = inputBox:GetText()
        if not text or text == "" then return end
        local normalized = ns.normalizeName(text)
        if not normalized then
            ns.printError(L["WHITELIST_INVALID_NAME"])
            return
        end
        if SanctuaryDB then
            SanctuaryDB.manualWhitelist[normalized] = {
                displayName = text,
                addedAt = time(),
            }
            ns.invalidateWhitelist()
            ns.printSuccess(string.format(L["WHITELIST_ADDED"], text))
        end
        inputBox:SetText("")
        inputBox:ClearFocus()
        refreshWhitelistEntries()
        refreshStatusBar()
    end)
    addBtn:SetPoint("LEFT", inputBox, "RIGHT", 6, 0)

    inputBox:SetScript("OnEnterPressed", function(self)
        addBtn:GetScript("OnClick")(addBtn)
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Scroll area (below input)
    local listTop = CONTENT_PADDING + 50
    local listBottom = CONTENT_PADDING

    local scrollFrame = CreateFrame("ScrollFrame", "SanctuaryWhitelistScroll", parent,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -listTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, listBottom)

    whitelistScrollChild = CreateFrame("Frame", nil, scrollFrame)
    local contentWidth = scrollFrame:GetWidth()
    if not contentWidth or contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    whitelistScrollChild:SetWidth(contentWidth)
    whitelistScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(whitelistScrollChild)
end

refreshWhitelistEntries = function()
    if not whitelistScrollChild or not SanctuaryDB or not SanctuaryDB.manualWhitelist then return end

    -- Clear existing children
    for _, entry in ipairs(whitelistEntries) do
        entry:Hide()
        table.insert(whitelistEntryPool, entry)
    end
    wipe(whitelistEntries)

    -- Sort entries by display name
    local sorted = {}
    for key, data in pairs(SanctuaryDB.manualWhitelist) do
        table.insert(sorted, { key = key, data = data })
    end
    table.sort(sorted, function(a, b)
        local nameA = (a.data.displayName or a.key):lower()
        local nameB = (b.data.displayName or b.key):lower()
        return nameA < nameB
    end)

    local yOffset = 0
    local entryHeight = 24
    local scrollParent = whitelistScrollChild:GetParent()
    local contentWidth = scrollParent and scrollParent:GetWidth() or (FRAME_WIDTH - CONTENT_PADDING * 2 - 22)
    if contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    whitelistScrollChild:SetWidth(contentWidth)

    for i, item in ipairs(sorted) do
        local entry = table.remove(whitelistEntryPool)
        if entry then
            entry:SetParent(whitelistScrollChild)
            entry:Show()
        else
            entry = CreateFrame("Frame", nil, whitelistScrollChild, "BackdropTemplate")
        end
        entry:SetHeight(entryHeight)
        entry:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 0, -yOffset)
        entry:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
        applyBackdrop(entry, ENTRY_BG, BORDER_COLOR)

        -- Name
        if not entry.nameLabel then
            entry.nameLabel = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local nf = entry.nameLabel:GetFont()
            entry.nameLabel:SetFont(nf, 11, "")
            entry.nameLabel:SetPoint("LEFT", entry, "LEFT", 10, 0)
            entry.nameLabel:SetJustifyH("LEFT")
        end
        entry.nameLabel:SetTextColor(0.9, 0.9, 0.9, 1.0)
        entry.nameLabel:SetText(item.data.displayName or item.key)
        entry.nameLabel:Show()

        -- Date (before the X button)
        local dateStr = item.data.addedAt and date(L["DATE_FORMAT"], item.data.addedAt) or "?"
        if not entry.dateLabel then
            entry.dateLabel = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local nf = entry.dateLabel:GetFont()
            entry.dateLabel:SetFont(nf, 10, "")
            entry.dateLabel:SetJustifyH("RIGHT")
        end
        entry.dateLabel:ClearAllPoints()
        entry.dateLabel:SetPoint("RIGHT", entry, "RIGHT", -30, 0)
        entry.dateLabel:SetTextColor(unpack(DIM_COLOR))
        entry.dateLabel:SetText(string.format(L["WL_ADDED_ON"], dateStr))
        entry.dateLabel:Show()

        -- [X] delete button
        if not entry.deleteBtn then
            entry.deleteBtn = CreateFrame("Button", nil, entry)
            entry.deleteBtn:SetSize(20, 20)
            entry.deleteBtn:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
            entry.deleteBtn.label = entry.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local df = entry.deleteBtn.label:GetFont()
            entry.deleteBtn.label:SetFont(df, 12, "OUTLINE")
            entry.deleteBtn.label:SetText("X")
            entry.deleteBtn.label:SetPoint("CENTER")
            entry.deleteBtn.label:SetTextColor(0.6, 0.3, 0.3, 1.0)
            entry.deleteBtn:SetScript("OnEnter", function(self)
                self.label:SetTextColor(1.0, 0.3, 0.3, 1.0)
            end)
            entry.deleteBtn:SetScript("OnLeave", function(self)
                self.label:SetTextColor(0.6, 0.3, 0.3, 1.0)
            end)
        end
        local capturedKey = item.key
        local capturedName = item.data.displayName or item.key
        entry.deleteBtn:SetScript("OnClick", function()
            if SanctuaryDB then
                SanctuaryDB.manualWhitelist[capturedKey] = nil
                ns.invalidateWhitelist()
                refreshWhitelistEntries()
                refreshStatusBar()
            end
        end)
        entry.deleteBtn:Show()

        table.insert(whitelistEntries, entry)
        yOffset = yOffset + entryHeight + 2
    end

    whitelistScrollChild:SetHeight(math.max(yOffset + 10, 1))

    -- Update count label
    if whitelistCountLabel then
        local count = #sorted
        whitelistCountLabel:SetText("(" .. string.format(L["WL_COUNT"], count) .. ")")
    end
end

-- ============================================================================
-- SECTION 8: Logs Tab
-- ============================================================================

-- Log entry row pools (separate pools for headers and details to avoid FontString contamination)
local logHeaderPool = {}
local logDetailPool = {}
local logHeaderIdx = 0
local logDetailIdx = 0

local function getOrCreateHeader(parent)
    logHeaderIdx = logHeaderIdx + 1
    local row = logHeaderPool[logHeaderIdx]
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.expandText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.expandText:SetPoint("LEFT", 6, 0)
        row.expandText:SetWidth(16)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 24, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -150, 0)
        row.nameText:SetWordWrap(false)
        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.dateText:SetPoint("RIGHT", -6, 0)
        row.dateText:SetWidth(140)
        row.dateText:SetJustifyH("RIGHT")
        logHeaderPool[logHeaderIdx] = row
    end
    row:SetParent(parent)
    row:Show()
    return row
end

local function getOrCreateDetail(parent)
    logDetailIdx = logDetailIdx + 1
    local row = logDetailPool[logDetailIdx]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateText:SetPoint("LEFT", 24, 0)
        row.dateText:SetWidth(140)
        row.dateText:SetWordWrap(false)
        row.dateText:SetNonSpaceWrap(false)
        row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.typeText:SetPoint("LEFT", 170, 0)
        row.typeText:SetWidth(70)
        row.typeText:SetWordWrap(false)
        row.msgText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.msgText:SetPoint("LEFT", 250, 0)
        row.msgText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.msgText:SetWordWrap(false)
        row.msgText:SetNonSpaceWrap(false)
        logDetailPool[logDetailIdx] = row
    end
    row:SetParent(parent)
    row:Show()
    return row
end

local exportFrame = nil

local function showLogExport()
    if not SanctuaryDB or not SanctuaryDB.log then return end

    -- Destroy previous export frame if it exists (fresh each time)
    if exportFrame then
        exportFrame:Hide()
        exportFrame:SetParent(nil)
        exportFrame = nil
    end

    -- Create fresh frame
    exportFrame = CreateFrame("Frame", "SanctuaryExportFrame", UIParent, "BackdropTemplate")
    exportFrame:SetSize(550, 420)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    exportFrame:SetMovable(true)
    exportFrame:EnableMouse(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
    exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
    exportFrame:SetClampedToScreen(true)

    exportFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    exportFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    exportFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    -- Title
    local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(L["EXPORT_TITLE"])

    -- Instructions
    local instructions = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instructions:SetPoint("TOP", title, "BOTTOM", 0, -4)
    instructions:SetText(L["EXPORT_INSTRUCTIONS"])
    instructions:SetTextColor(0.6, 0.6, 0.6)

    -- Close button
    local closeBtn = createButton(exportFrame, L["EXPORT_CLOSE"], 80, 24, function()
        exportFrame:Hide()
    end)
    closeBtn:SetPoint("BOTTOM", 0, 10)

    -- ScrollFrame with EditBox inside (for scrollable large text)
    local sf = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 14, -48)
    sf:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -32, 40)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetAutoFocus(true)
    eb:SetWidth(490)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
    sf:SetScrollChild(eb)

    -- Build text
    local result = L["EXPORT_HEADER"] .. "\n"
    result = result .. string.format(L["EXPORT_DATE"], date(L["DATE_TIME_FORMAT"])) .. "\n"
    result = result .. string.format(L["EXPORT_TOTAL"], tostring(#SanctuaryDB.log)) .. "\n"
    result = result .. L["EXPORT_COLUMNS"] .. "\n"
    result = result .. string.rep("-", 50) .. "\n"
    for i, entry in ipairs(SanctuaryDB.log) do
        local line = tostring(entry.d or "?") .. " | " .. tostring(entry.type or "?") .. " | " .. tostring(entry.name or "?")
        if entry.realm and entry.realm ~= "" then
            line = line .. "-" .. entry.realm
        end
        if entry.msg and entry.msg ~= "" then
            line = line .. " | " .. tostring(entry.msg)
        end
        if entry.keyword and entry.keyword ~= "" then
            line = line .. " " .. string.format(L["EXPORT_SUSPECT_TAG"], entry.keyword)
        end
        result = result .. line .. "\n"
    end

    -- Insert text in small chunks (SetMaxLetters broken in Midnight)
    eb:SetText("")
    local chunkSize = 200
    if #result <= chunkSize then
        eb:SetText(result)
    else
        eb:SetText(result:sub(1, chunkSize))
        for i = chunkSize + 1, #result, chunkSize do
            eb:Insert(result:sub(i, math.min(i + chunkSize - 1, #result)))
        end
    end
    eb:SetCursorPosition(0)
    eb:HighlightText()

    exportFrame:Show()
end

-- Type display names and colors
local LOG_TYPE_DISPLAY = {
    groupInvite      = { label = L["LOG_TYPE_INVITE"],  color = { 1.0, 0.6, 0.2 } },
    whisper          = { label = L["LOG_TYPE_WHISPER"], color = { 0.8, 0.4, 0.9 } },
    duel             = { label = L["LOG_TYPE_DUEL"],    color = { 0.9, 0.3, 0.3 } },
    trade            = { label = L["LOG_TYPE_TRADE"],   color = { 0.3, 0.8, 0.3 } },
    guildInvite      = { label = L["LOG_TYPE_GUILD"],   color = { 0.3, 0.7, 0.9 } },
    say              = { label = L["LOG_TYPE_SAY"],     color = { 0.9, 0.9, 0.9 } },
    yell             = { label = L["LOG_TYPE_YELL"],    color = { 1.0, 0.3, 0.3 } },
    emote            = { label = L["LOG_TYPE_EMOTE"],   color = { 1.0, 0.6, 0.2 } },
    channel          = { label = L["LOG_TYPE_CHANNEL"], color = { 0.5, 0.7, 0.9 } },
}

-- Group log entries by source name, sorted by last activity (most recent first)
local function groupLogsByName()
    if not SanctuaryDB or not SanctuaryDB.log then return {} end
    local groups = {}
    local groupOrder = {}
    for _, entry in ipairs(SanctuaryDB.log) do
        local name = entry.name or "?"
        if not groups[name] then
            groups[name] = { entries = {}, lastTime = 0, count = 0 }
            groupOrder[#groupOrder + 1] = name
        end
        groups[name].entries[#groups[name].entries + 1] = entry
        groups[name].count = groups[name].count + 1
        if entry.t and entry.t > groups[name].lastTime then
            groups[name].lastTime = entry.t
        end
    end
    local sorted = {}
    for _, name in ipairs(groupOrder) do
        sorted[#sorted + 1] = { name = name, data = groups[name] }
    end
    table.sort(sorted, function(a, b) return a.data.lastTime > b.data.lastTime end)
    return sorted
end


buildLogsTab = function(parent)
    -- Title + count
    local header = createLabel(parent, L["LOGS_HEADER"], 13, ACCENT_BLUE, "LEFT")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -CONTENT_PADDING)

    -- Logging on/off checkbox
    local logToggle = createCheckbox(parent, L["LOGS_ENABLE"], nil,
        function(checked)
            if SanctuaryDB and SanctuaryDB.logging then
                SanctuaryDB.logging.enabled = checked
            end
        end)
    logToggle:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 18))
    logToggle:SetWidth(200)
    if SanctuaryDB and SanctuaryDB.logging and logToggle.checkbox then
        logToggle.checkbox:SetChecked(SanctuaryDB.logging.enabled)
    end

    local msgToggle = createCheckbox(parent, L["LOGS_SHOW_MSG"], nil, function(checked)
        if SanctuaryDB and SanctuaryDB.uiSettings then
            SanctuaryDB.uiSettings.showMessageColumn = checked
            refreshLogEntries()
        end
    end)
    msgToggle:SetPoint("LEFT", logToggle, "RIGHT", 160, 0)
    msgToggle:SetWidth(200)
    if SanctuaryDB and SanctuaryDB.uiSettings and msgToggle.checkbox then
        msgToggle.checkbox:SetChecked(SanctuaryDB.uiSettings.showMessageColumn ~= false)
    end

    logCountLabel = createLabel(parent, "", 11, DIM_COLOR, "RIGHT")
    logCountLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PADDING - 26, -CONTENT_PADDING)

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -(CONTENT_PADDING + 42))
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PADDING, -(CONTENT_PADDING + 42))
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.4)

    -- Scroll area (shifted down for checkboxes)
    local listTop = CONTENT_PADDING + 48
    local listBottom = 42

    local scrollFrame = CreateFrame("ScrollFrame", "SanctuaryLogScroll", parent,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -listTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, listBottom)

    logScrollChild = CreateFrame("Frame", nil, scrollFrame)
    local contentWidth = scrollFrame:GetWidth()
    if not contentWidth or contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    logScrollChild:SetWidth(contentWidth)
    logScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(logScrollChild)

    -- Bottom buttons
    local clearBtn = createButton(parent, L["LOGS_CLEAR_BTN"], 130, 24, function()
        StaticPopup_Show("SANCTUARY_CLEAR_LOG")
    end)
    clearBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", CONTENT_PADDING, 10)

    local exportBtn = createButton(parent, L["LOGS_EXPORT_BTN"], 100, 24, function()
        showLogExport()
    end)
    exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)

    local expandBtn = createButton(parent, L["LOGS_EXPAND_ALL"], 110, 24, function()
        allExpanded = not allExpanded
        if allExpanded then
            local groups = groupLogsByName()
            for _, group in ipairs(groups) do
                expandedGroups[group.name] = true
            end
        else
            wipe(expandedGroups)
        end
        refreshLogEntries()
    end)
    expandBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    parent.expandBtn = expandBtn
end

refreshLogEntries = function()
    if not logScrollChild or not SanctuaryDB or not SanctuaryDB.log then return end

    -- Hide all existing headers and details, reset indices
    for i = 1, #logHeaderPool do logHeaderPool[i]:Hide() end
    for i = 1, #logDetailPool do logDetailPool[i]:Hide() end
    logHeaderIdx = 0
    logDetailIdx = 0

    local groups = groupLogsByName()
    local yOffset = 0
    local scrollParent = logScrollChild:GetParent()
    local contentWidth = scrollParent and scrollParent:GetWidth() or (FRAME_WIDTH - CONTENT_PADDING * 2 - 22)
    if contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    logScrollChild:SetWidth(contentWidth)
    local showMsg = SanctuaryDB and SanctuaryDB.uiSettings and SanctuaryDB.uiSettings.showMessageColumn ~= false

    for _, group in ipairs(groups) do
        local name = group.name
        local data = group.data
        local isExpanded = expandedGroups[name] or false

        -- GROUP HEADER ROW
        local header = getOrCreateHeader(logScrollChild)
        header:SetSize(contentWidth, 24)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", logScrollChild, "TOPLEFT", 0, -yOffset)

        -- Header background
        header.bg:SetColorTexture(0.15, 0.15, 0.25, 0.8)
        header.bg:Show()

        -- Expand indicator
        header.expandText:SetText(isExpanded and "v" or ">")
        header.expandText:SetTextColor(0.6, 0.8, 1.0)

        -- Name + count
        header.nameText:SetText(string.format(L["LOGS_GROUP_HEADER"], name, data.count))
        header.nameText:SetTextColor(1, 1, 1)

        -- Last activity date
        local lastDate = data.lastTime > 0 and date(L["DATE_TIME_FORMAT"] or "%Y-%m-%d %H:%M", data.lastTime) or "?"
        header.dateText:SetText(string.format(L["LOGS_LAST_ACTIVITY"], lastDate))
        header.dateText:SetTextColor(0.5, 0.5, 0.5)

        -- Click to toggle expand
        local capturedName = name
        header:SetScript("OnClick", function()
            expandedGroups[capturedName] = not expandedGroups[capturedName]
            refreshLogEntries()
        end)

        yOffset = yOffset + 26

        -- DETAIL ROWS (if expanded)
        if isExpanded then
            for i = #data.entries, 1, -1 do
                local entry = data.entries[i]
                local row = getOrCreateDetail(logScrollChild)
                row:SetSize(contentWidth, 20)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", logScrollChild, "TOPLEFT", 0, -yOffset)

                -- Row background (alternate)
                row.bg:SetColorTexture(0.08, 0.08, 0.14, (i % 2 == 0) and 0.4 or 0.6)
                row.bg:Show()

                -- Date (indented)
                local entryDate = entry.t and date(L["DATE_TIME_FORMAT"] or "%Y-%m-%d %H:%M", entry.t) or (entry.d or "?")
                row.dateText:SetText(entryDate)
                row.dateText:SetTextColor(0.6, 0.6, 0.6)

                -- Type (colored)
                local typeDisplay = LOG_TYPE_DISPLAY[entry.type]
                if typeDisplay then
                    row.typeText:SetText(typeDisplay.label)
                    row.typeText:SetTextColor(unpack(typeDisplay.color))
                else
                    row.typeText:SetText(entry.type or "?")
                    row.typeText:SetTextColor(0.5, 0.5, 0.5)
                end

                -- Message
                if showMsg and entry.msg and entry.msg ~= "" then
                    local msgText = entry.msg
                    if #msgText > 60 then msgText = msgText:sub(1, 60) .. "..." end
                    row.msgText:SetText(msgText)
                    row.msgText:SetTextColor(0.7, 0.7, 0.7)
                    row.msgText:Show()
                else
                    row.msgText:SetText("")
                    row.msgText:Hide()
                end

                yOffset = yOffset + 20
            end
        end
    end

    logScrollChild:SetHeight(math.max(1, yOffset))

    -- Update count label
    if logCountLabel then
        local total = #SanctuaryDB.log
        local groupCount = #groups
        logCountLabel:SetText(string.format(L["LOGS_COUNT_FULL"], total, SanctuaryDB.logging.maxEntries or 5000))
    end

    -- Update expand/collapse button text
    local logsParent = tabFrames["logs"]
    if logsParent and logsParent.expandBtn then
        if allExpanded then
            logsParent.expandBtn.label:SetText(L["LOGS_COLLAPSE_ALL"])
        else
            logsParent.expandBtn.label:SetText(L["LOGS_EXPAND_ALL"])
        end
    end
end

-- ============================================================================
-- SECTION 10: Settings Panel Registration
-- ============================================================================

local function registerSettingsPanel()
    local ok = pcall(function()
        local settingsFrame = CreateFrame("Frame")
        settingsFrame:SetSize(400, 200)

        local desc = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        desc:SetPoint("TOP", 0, -30)
        desc:SetText(string.format(L["SETTINGS_TITLE"], ns.VERSION or "?"))

        local subdesc = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        subdesc:SetPoint("TOP", desc, "BOTTOM", 0, -10)
        subdesc:SetText(L["SETTINGS_DESC"])

        local btn = createButton(settingsFrame, L["SETTINGS_OPEN_BTN"], 200, 30, function()
            if ns.ToggleUI then ns.ToggleUI() end
            -- Close settings if possible
            pcall(function() SettingsPanel:Hide() end)
        end)
        btn:SetPoint("CENTER", 0, -20)

        local category = Settings.RegisterCanvasLayoutCategory(settingsFrame, "Sanctuary")
        Settings.RegisterAddOnCategory(category)
    end)
end

-- ============================================================================
-- SECTION 11: Toggle & Namespace Export
-- ============================================================================

local function toggleUI()
    local frame = createMainFrame()
    if frame:IsShown() then
        frame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    else
        frame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end
end

-- Export to namespace so Sanctuary.lua can call it from /sanc and /sanc ui
ns.ToggleUI = toggleUI

-- ============================================================================
-- SECTION 12: Initialization
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Ensure SavedVariables are loaded before we touch them
        C_Timer.After(0.5, function()
            registerSettingsPanel()
        end)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
