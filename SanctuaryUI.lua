-- ============================================================================
-- SanctuaryUI.lua — Configuration interface for Sanctuary anti-harassment addon
-- Pure Lua, no XML, no external libraries. WoW Midnight compatible (120007).
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
    strictGroupInviteSystemMessages = L["FILTER_STRICT_GROUP_INVITE_SYSTEM"],
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
    strictGroupInviteSystemMessages = L["TIP_STRICT_GROUP_INVITE_SYSTEM"],
}


-- Filter groups for the Filters tab
local FILTER_GROUPS = {
    {
        title = L["GROUP_MAIN_PROTECTION"],
        keys  = { "groupInvite", "strictGroupInviteSystemMessages" },
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
    { name = L["TAB_ABOUT"],     key = "about"     },
    -- Debug-only. Both the tab button and its content frame stay hidden while
    -- debug mode is off, so no diagnostic is reachable -- let alone fireable by
    -- accident -- from the normal interface.
    { name = L["TAB_DIAGNOSTICS"], key = "diagnostics", debugOnly = true },
}

local function isTabVisible(def)
    if not def or not def.debugOnly then return true end
    return (SanctuaryDB and SanctuaryDB.debugEnabled) and true or false
end

local function visibleTabDefs()
    local defs = {}
    for _, def in ipairs(TAB_DEFS) do
        if isTabVisible(def) then defs[#defs + 1] = def end
    end
    return defs
end

local function tabDefByKey(key)
    for _, def in ipairs(TAB_DEFS) do
        if def.key == key then return def end
    end
    return nil
end

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
local whitelistRowPool = {}
local whitelistRows = {}
local whitelistScrollChild = nil
local whitelistCountLabel = nil
local whitelistSearchBox = nil
local whitelistCheckBox = nil
local whitelistCheckResult = nil
-- Collapsed by default. It answers the volume problem -- 56 Battle.net accounts
-- are four count lines until asked for -- and it keeps a window that can be
-- opened in public from listing a friends list nobody asked to see.
local whitelistExpanded = {}

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
local layoutTabBar, refreshTabBar
local buildFiltersTab, refreshFilterCheckboxes
local buildKeywordsTab, refreshKeywordEntries
local buildWhitelistTab, refreshWhitelistEntries, runWhitelistCheck
local buildLogsTab, refreshLogEntries
local buildAboutTab
local buildDiagnosticsTab, refreshDiagnosticsPanel

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

-- Clearing the debug log is the only way to lose a recording, so it asks first
-- and says how many entries are at stake.
StaticPopupDialogs["SANCTUARY_CLEAR_DEBUG_LOG"] = {
    text = L["DEBUG_CLEAR_CONFIRM"],
    button1 = L["LOGS_CLEAR_YES"],
    button2 = L["LOGS_CLEAR_NO"],
    OnAccept = function()
        if ns.resetDebugLog then
            ns.resetDebugLog()
            ns.printSuccess(L["DEBUG_CLEARED_MSG"])
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
        local newState = ns.isEnabled()
        -- Debug: log addon enable/disable
        if ns.debugLog then
            ns.debugLog("TOGGLE", { enabled = newState })
        end
        if ns.refreshInviteSoundMuteState then
            ns.refreshInviteSoundMuteState()
        end
        if newState then
            ns.printSuccess(L["SANCTUARY_ENABLED"])
        else
            if ns.clearPendingPopupDecision then
                ns.clearPendingPopupDecision("PARTY_INVITE")
                ns.clearPendingPopupDecision("DUEL_REQUESTED")
            end
            if ns.clearPendingGuildInviteFrameDecision then
                ns.clearPendingGuildInviteFrameDecision()
            end
            if ns.unmaskAllInteractionPopups then
                ns.unmaskAllInteractionPopups()
            end
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
        -- Recalculate tab button widths on resize. Hidden tabs must not reserve
        -- a slot, so the layout is shared with the debug-mode refresh.
        layoutTabBar()
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

    local tabWidth = mainFrame:GetWidth() / #TAB_DEFS
    for _, def in ipairs(TAB_DEFS) do
        local tab = CreateFrame("Button", "SanctuaryTab_" .. def.key, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, TAB_BAR_HEIGHT)
        tab:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 0, 0)
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
    layoutTabBar()

    -- ========================================================================
    -- Content area (one frame per tab, shown/hidden)
    -- ========================================================================
    local contentTop = HEADER_HEIGHT + TAB_BAR_HEIGHT
    local contentHeight = FRAME_HEIGHT - contentTop - STATUS_BAR_HEIGHT

    for _, def in ipairs(TAB_DEFS) do
        local content = CreateFrame("Frame", "SanctuaryTabContent_" .. def.key, mainFrame)
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
    buildAboutTab(tabFrames["about"])
    buildDiagnosticsTab(tabFrames["diagnostics"])

    -- ========================================================================
    -- Status bar
    -- ========================================================================
    statusBar = CreateFrame("Frame", "SanctuaryStatusBar", mainFrame, "BackdropTemplate")
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
        refreshTabBar()
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

layoutTabBar = function()
    if not mainFrame then return end
    local defs = visibleTabDefs()
    for _, def in ipairs(TAB_DEFS) do
        local tab = tabButtons[def.key]
        if tab then tab:Hide() end
    end
    local width = mainFrame:GetWidth() / math.max(1, #defs)
    for i, def in ipairs(defs) do
        local tab = tabButtons[def.key]
        if tab then
            tab:SetSize(width, TAB_BAR_HEIGHT)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", tab:GetParent(), "TOPLEFT", (i - 1) * width, 0)
            tab:Show()
        end
    end
end

-- Called whenever the debug checkbox may have changed, and on every show.
refreshTabBar = function()
    layoutTabBar()
    -- Turning debug mode off while its own tab is open must not leave the panel
    -- on screen: fall back to the first tab rather than to a frame nothing can
    -- reach any more.
    if activeTab and not isTabVisible(tabDefByKey(activeTab)) then
        selectTab(TAB_DEFS[1].key)
    end
end

selectTab = function(key)
    -- A hidden tab is not selectable: this is the second lock on the debug
    -- panel, so a stale reference cannot open it while debug mode is off.
    if not isTabVisible(tabDefByKey(key)) then return end

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
    elseif key == "diagnostics" then
        refreshDiagnosticsPanel()
    -- "about" tab is static, no refresh needed
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

    local debugPart = ""
    if SanctuaryDB.debugEnabled and SanctuaryDB.debugLog then
        debugPart = "  |  " .. string.format(L["DEBUG_COUNT"], #SanctuaryDB.debugLog)
    end

    statusBar.text:SetText(
        string.format(L["STATUSBAR_SESSION"], blocked) .. "  |  "
        .. string.format(L["STATUSBAR_LOG"], logCount, maxLog)
        .. keywordPart
        .. debugPart
    )
end

-- ============================================================================
-- SECTION 4b: Styled Input Helper
-- ============================================================================

local function createStyledInput(parent, width, height, name)
    local input = CreateFrame("EditBox", name, parent, "BackdropTemplate")
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

            local filterKey = key
            local cb = createCheckbox(child, label, tooltip, function(checked)
                if SanctuaryDB and SanctuaryDB.filters then
                    SanctuaryDB.filters[filterKey] = checked

                    if filterKey == "groupInvite" or filterKey == "duel" or filterKey == "guildInvite" then
                        if ns.refreshInviteSoundMuteState then
                            ns.refreshInviteSoundMuteState()
                        end
                    end

                    if filterKey == "groupInvite" then
                        if not checked then
                            if ns.clearPendingPopupDecision then
                                ns.clearPendingPopupDecision("PARTY_INVITE")
                            end
                            if ns.unmaskVisiblePopup then
                                ns.unmaskVisiblePopup("PARTY_INVITE")
                            end
                        end
                    elseif filterKey == "duel" and not checked then
                        if ns.clearPendingPopupDecision then
                            ns.clearPendingPopupDecision("DUEL_REQUESTED")
                        end
                        if ns.unmaskVisiblePopup then
                            ns.unmaskVisiblePopup("DUEL_REQUESTED")
                        end
                    elseif filterKey == "guildInvite" and not checked then
                        if ns.clearPendingGuildInviteFrameDecision then
                            ns.clearPendingGuildInviteFrameDecision()
                        end
                        if ns.unmaskGuildInviteFrame then
                            ns.unmaskGuildInviteFrame()
                        end
                    end

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
            if ns.refreshGroupTracker then
                ns.refreshGroupTracker()
            else
                ns.invalidateWhitelist()
            end
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
    local inputBox = createStyledInput(parent, 200, 26, "SanctuaryWhitelistAddInput")
    inputBox:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 22))
    inputBox:SetMaxLetters(64)

    local addBtn
    addBtn = createButton(parent, L["WL_ADD_BTN"], 80, 24, function()
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
                source = "manual",
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

    -- Search box, on the same row: it filters the automatic section below, which
    -- is the only one large enough to need it.
    local searchLabel = createLabel(parent, L["WL_SEARCH_LABEL"], 11, DIM_COLOR, "RIGHT")
    searchLabel:SetPoint("LEFT", addBtn, "RIGHT", 12, 0)
    searchLabel:SetWidth(80)

    whitelistSearchBox = createStyledInput(parent, 150, 26, "SanctuaryWhitelistSearchInput")
    whitelistSearchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    whitelistSearchBox:SetMaxLetters(64)
    whitelistSearchBox:SetScript("OnTextChanged", function()
        refreshWhitelistEntries()
    end)
    whitelistSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- "Does this person get through?" -- pinned to the bottom so the answer is
    -- reachable without scrolling whatever the lists above are showing.
    whitelistCheckResult = createLabel(parent, "", 11, DIM_COLOR, "LEFT")
    whitelistCheckResult:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", CONTENT_PADDING + 4, 10)
    whitelistCheckResult:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PADDING, 0)
    whitelistCheckResult:SetWordWrap(true)

    local checkLabel = createLabel(parent, L["WL_CHECK_LABEL"], 11, ACCENT_BLUE, "LEFT")
    checkLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", CONTENT_PADDING + 4, 34)
    checkLabel:SetWidth(190)

    whitelistCheckBox = createStyledInput(parent, 180, 24, "SanctuaryWhitelistCheckInput")
    whitelistCheckBox:SetPoint("LEFT", checkLabel, "RIGHT", 8, 0)
    whitelistCheckBox:SetMaxLetters(64)

    local checkBtn = createButton(parent, L["WL_CHECK_BTN"], 90, 24, function()
        runWhitelistCheck(whitelistCheckBox:GetText())
    end)
    checkBtn:SetPoint("LEFT", whitelistCheckBox, "RIGHT", 6, 0)

    whitelistCheckBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        runWhitelistCheck(self:GetText())
    end)
    whitelistCheckBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Scroll area (below input). Both sections share it: the manual list keeps
    -- the space it had, and the automatic groups extend it instead of splitting
    -- the tab into two cramped panes.
    local listTop = CONTENT_PADDING + 50
    local listBottom = 62

    local scrollFrame = CreateFrame("ScrollFrame", "SanctuaryWhitelistScroll", parent,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -listTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, listBottom)

    whitelistScrollChild = CreateFrame("Frame", "SanctuaryWhitelistScrollChild", scrollFrame)
    local contentWidth = scrollFrame:GetWidth()
    if not contentWidth or contentWidth < 100 then contentWidth = FRAME_WIDTH - CONTENT_PADDING * 2 - 22 end
    whitelistScrollChild:SetWidth(contentWidth)
    whitelistScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(whitelistScrollChild)
end

-- Plain one-line rows, pooled separately from the manual entries: those carry a
-- date and a delete button, these are read-only text.
local function acquireWhitelistRow(height)
    local row = table.remove(whitelistRowPool)
    if row then
        row:SetParent(whitelistScrollChild)
        row:Show()
    else
        row = CreateFrame("Button", nil, whitelistScrollChild, "BackdropTemplate")
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
    end
    row:SetHeight(height)
    row:SetScript("OnClick", nil)
    row:EnableMouse(false)
    -- Rows come back from the pool carrying whatever the previous caller gave
    -- them: a group header keeps its frame, a name row must not inherit it.
    if row.SetBackdrop then row:SetBackdrop(nil) end
    row:ClearAllPoints()
    local font = row.label:GetFont()
    row.label:SetFont(font, 11, "")
    return row
end

local WL_SOURCE_LABEL_KEYS = {
    guild  = "WL_SOURCE_GUILD",
    friend = "WL_SOURCE_FRIEND",
    bnet   = "WL_SOURCE_BNET",
    group  = "WL_SOURCE_GROUP",
}

local WL_REASON_KEYS = {
    manual = "WL_REASON_MANUAL",
    trust  = "WL_REASON_TRUST",
    guild  = "WL_REASON_GUILD",
    friend = "WL_REASON_FRIEND",
    bnet   = "WL_REASON_BNET",
    group  = "WL_REASON_GROUP",
}

local function describeWhitelistReason(info)
    if info.reason == "keyword" then
        return string.format(L["WL_REASON_KEYWORD"], tostring(info.keyword or "?"))
    end
    if info.reason == "not_whitelisted" then
        return L["WL_REASON_NOT_WHITELISTED"]
    end
    return L[WL_REASON_KEYS[info.source or "manual"] or "WL_REASON_MANUAL"]
end

runWhitelistCheck = function(text)
    if not whitelistCheckResult then return end
    local info = ns.describeAccessDecision and ns.describeAccessDecision(text or "")
    if not info or not info.valid then
        whitelistCheckResult:SetTextColor(unpack(DIM_COLOR))
        whitelistCheckResult:SetText(info and info.reason == "empty" and "" or L["WL_CHECK_INVALID"])
        return
    end

    if info.blocked then
        local message = string.format(L["WL_CHECK_BLOCK"], info.input, describeWhitelistReason(info))
        -- A Battle.net friend whose current character is unknown is filtered on
        -- character name and allowed on Battle.net whispers. Reporting only the
        -- first half would read as a bug to someone who knows they get through.
        if info.bnetSource then
            message = message .. string.format(L["WL_CHECK_BNET_ONLY"],
                L[WL_REASON_KEYS[info.bnetSource] or "WL_REASON_BNET"])
        end
        whitelistCheckResult:SetTextColor(unpack(RED_COLOR))
        whitelistCheckResult:SetText(message)
    else
        whitelistCheckResult:SetTextColor(0.4, 0.9, 0.4, 1.0)
        whitelistCheckResult:SetText(string.format(L["WL_CHECK_PASS"], info.input,
            describeWhitelistReason(info)))
    end
end

refreshWhitelistEntries = function()
    if not whitelistScrollChild or not SanctuaryDB or not SanctuaryDB.manualWhitelist then return end

    for _, row in ipairs(whitelistRows) do
        row:Hide()
        table.insert(whitelistRowPool, row)
    end
    wipe(whitelistRows)

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

    -- ------------------------------------------------------------------
    -- Automatically trusted contacts (read-only)
    -- ------------------------------------------------------------------
    -- No refresh button, no timer, and no live redraw while the tab is open.
    -- getAutoWhitelistGroups rebuilds the cache if anything invalidated it, so
    -- opening the tab -- or coming back to it -- is what makes the list current.
    -- BN_FRIEND_INFO_CHANGED fires around twenty times in half an hour purely
    -- because friends log in and out, which never changes who is authorized;
    -- redrawing on it would reorder a list of names under the reader's eyes for
    -- nothing. What a stale list could cost is covered by the check field
    -- below, which asks the decision itself and therefore always answers live.
    local filter = whitelistSearchBox and whitelistSearchBox:GetText() or ""
    local searching = filter ~= nil and filter:gsub("%s", "") ~= ""
    local groups = ns.getAutoWhitelistGroups and ns.getAutoWhitelistGroups(filter) or {}

    yOffset = yOffset + 8
    local sectionRow = acquireWhitelistRow(22)
    sectionRow:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 0, -yOffset)
    sectionRow:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
    sectionRow.label:SetTextColor(unpack(ACCENT_BLUE))
    sectionRow.label:SetText(L["WL_AUTO_HEADER"] .. "  |cFF888888" .. L["WL_AUTO_HINT"] .. "|r")
    table.insert(whitelistRows, sectionRow)
    yOffset = yOffset + 24

    local autoTotal = 0
    for _, group in ipairs(groups) do
        autoTotal = autoTotal + group.total
    end

    if autoTotal == 0 then
        local emptyRow = acquireWhitelistRow(20)
        emptyRow:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 0, -yOffset)
        emptyRow:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
        emptyRow.label:SetTextColor(unpack(DIM_COLOR))
        emptyRow.label:SetText(L["WL_AUTO_EMPTY"])
        table.insert(whitelistRows, emptyRow)
        yOffset = yOffset + 22
    end

    for _, group in ipairs(groups) do
        if group.total > 0 then
            -- A search forces its groups open: hiding the matches behind a
            -- second click would defeat the point of typing.
            local expanded = searching or whitelistExpanded[group.source] == true
            local groupRow = acquireWhitelistRow(22)
            groupRow:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 0, -yOffset)
            groupRow:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
            applyBackdrop(groupRow, ENTRY_BG, BORDER_COLOR)
            groupRow.label:SetTextColor(0.9, 0.9, 0.9, 1.0)

            local name = L[WL_SOURCE_LABEL_KEYS[group.source] or "WL_SOURCE_GUILD"]
            local text
            if searching then
                text = string.format(L["WL_GROUP_ROW_FILTERED"], name, #group.entries, group.total)
            else
                text = string.format(L["WL_GROUP_ROW"], name, group.total)
            end
            groupRow.label:SetText((expanded and "- " or "+ ") .. text)

            if not searching then
                local capturedSource = group.source
                groupRow:EnableMouse(true)
                groupRow:SetScript("OnClick", function()
                    whitelistExpanded[capturedSource] = not whitelistExpanded[capturedSource]
                    refreshWhitelistEntries()
                end)
            end
            table.insert(whitelistRows, groupRow)
            yOffset = yOffset + 24

            if expanded then
                if #group.entries == 0 then
                    local noneRow = acquireWhitelistRow(20)
                    noneRow:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 16, -yOffset)
                    noneRow:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
                    noneRow.label:SetTextColor(unpack(DIM_COLOR))
                    noneRow.label:SetText(L["WL_AUTO_NO_MATCH"])
                    table.insert(whitelistRows, noneRow)
                    yOffset = yOffset + 22
                end
                for _, item in ipairs(group.entries) do
                    local nameRow = acquireWhitelistRow(20)
                    nameRow:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 16, -yOffset)
                    nameRow:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", 0, 0)
                    nameRow.label:SetTextColor(0.75, 0.75, 0.8, 1.0)
                    nameRow.label:SetText(tostring(item.label))
                    table.insert(whitelistRows, nameRow)
                    yOffset = yOffset + 21
                end
            end
        end
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
    -- Same escaping rule as the debug report: a logged name or message can carry
    -- "|" escape sequences (item links, name substitutions) which the EditBox
    -- would interpret, eating the neighbouring text of the copied export.
    local escape = ns.escapeExportText or tostring
    for i, entry in ipairs(SanctuaryDB.log) do
        local line = escape(entry.d or "?") .. " | " .. escape(entry.type or "?")
            .. " | " .. escape(entry.name or "?")
        if entry.realm and entry.realm ~= "" then
            line = line .. "-" .. escape(entry.realm)
        end
        if entry.msg and entry.msg ~= "" then
            line = line .. " | " .. escape(entry.msg)
        end
        if entry.keyword and entry.keyword ~= "" then
            line = line .. " " .. string.format(L["EXPORT_SUSPECT_TAG"], escape(entry.keyword))
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

-- ========================================================================
-- Debug export modal
-- ========================================================================

local debugExportFrame = nil

-- One window, two contents. What changed with this lot is which one is the
-- official record: the settings file the game writes on exit is, and this
-- window is a check. The summary is what opens by default -- short enough that
-- a rendering defect cannot hide inside it, and carrying no data to lose. The
-- full report stays reachable for on-screen reading, labelled as such.
local function showReportWindow(titleText, instructionsText, bodyText, warningText)
    if not SanctuaryDB then return end

    -- The snapshot used to be captured only when the debug checkbox was ticked,
    -- so refreshing it meant unticking and reticking -- a gesture that also wiped
    -- the log. Opening either report captures it instead (see the two callers
    -- below), and does so even when debug mode is off: since the log now
    -- survives unticking, "play, untick, export later" is a normal path, and it
    -- would otherwise report a state dating back to the activation. The entry is
    -- marked `trigger=export` and carries `debugEnabled`, so a reader can see
    -- the report added it.
    if debugExportFrame then
        debugExportFrame:Hide()
        debugExportFrame:SetParent(nil)
        debugExportFrame = nil
    end

    debugExportFrame = CreateFrame("Frame", "SanctuaryDebugExportFrame", UIParent, "BackdropTemplate")
    debugExportFrame:SetSize(650, 500)
    debugExportFrame:SetPoint("CENTER")
    debugExportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    debugExportFrame:SetMovable(true)
    debugExportFrame:EnableMouse(true)
    debugExportFrame:RegisterForDrag("LeftButton")
    debugExportFrame:SetScript("OnDragStart", debugExportFrame.StartMoving)
    debugExportFrame:SetScript("OnDragStop", debugExportFrame.StopMovingOrSizing)
    debugExportFrame:SetClampedToScreen(true)

    debugExportFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    debugExportFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    debugExportFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    local title = debugExportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText(titleText)

    local instructions = debugExportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instructions:SetPoint("TOP", title, "BOTTOM", 0, -4)
    instructions:SetText(instructionsText)
    instructions:SetTextColor(0.6, 0.6, 0.6)

    if warningText then
        local warning = debugExportFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        warning:SetPoint("BOTTOM", debugExportFrame, "BOTTOM", 0, 36)
        warning:SetText(warningText)
        warning:SetTextColor(1.0, 0.8, 0.3)
    end

    local closeBtn = createButton(debugExportFrame, L["EXPORT_CLOSE"], 80, 24, function()
        debugExportFrame:Hide()
    end)
    closeBtn:SetPoint("BOTTOM", 0, 10)

    local sf = CreateFrame("ScrollFrame", nil, debugExportFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", debugExportFrame, "TOPLEFT", 14, -48)
    sf:SetPoint("BOTTOMRIGHT", debugExportFrame, "BOTTOMRIGHT", -32, 40)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetAutoFocus(true)
    eb:SetWidth(590)
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetScript("OnEscapePressed", function() debugExportFrame:Hide() end)
    sf:SetScrollChild(eb)

    local result = bodyText or ""

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

    debugExportFrame:Show()
end

-- Default surface: build identity plus the three values that decide whether a
-- recording session is exploitable, in a block that fits on screen.
local function showDebugSummary()
    if ns.captureDebugSnapshot then
        ns.captureDebugSnapshot("export")
    end
    showReportWindow(L["DEBUG_SUMMARY_TITLE"], L["DEBUG_SUMMARY_INSTRUCTIONS"],
        ns.buildDebugSummaryText and ns.buildDebugSummaryText() or "")
end

-- Secondary surface: the whole recording, for reading in game. The report text
-- is built by the core file so the escaping and the retention accounting stay
-- testable outside the game client.
local function showDebugExport()
    if ns.captureDebugSnapshot then
        ns.captureDebugSnapshot("export")
    end
    showReportWindow(L["DEBUG_EXPORT_TITLE"], L["DEBUG_EXPORT_INSTRUCTIONS"],
        ns.buildDebugReportText and ns.buildDebugReportText() or "",
        L["DEBUG_FULL_WARNING"])
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


-- ========================================================================
-- About tab (static content)
-- ========================================================================

buildAboutTab = function(parent)
    -- Container centered vertically and horizontally in the tab
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(440, 380)
    container:SetPoint("CENTER", parent, "CENTER", 0, 30)

    local yOffset = 0

    -- Addon name (large)
    local title = createLabel(container, "Sanctuary", 22, ACCENT_BLUE, "CENTER")
    title:SetPoint("TOP", container, "TOP", 0, yOffset)
    yOffset = yOffset - 36

    -- Version
    local version = createLabel(container, string.format(L["ABOUT_VERSION"], ns.VERSION), 13, DIM_COLOR, "CENTER")
    version:SetPoint("TOP", container, "TOP", 0, yOffset)
    yOffset = yOffset - 34

    -- Description
    local desc = createLabel(container, L["ABOUT_DESC"], 12, HIGHLIGHT_COLOR, "CENTER")
    desc:SetPoint("TOP", container, "TOP", 0, yOffset)
    desc:SetWidth(440)
    yOffset = yOffset - 44

    -- Author
    local author = createLabel(container, string.format(L["ABOUT_AUTHOR"], "Zephos"), 12, DIM_COLOR, "CENTER")
    author:SetPoint("TOP", container, "TOP", 0, yOffset)
    yOffset = yOffset - 28

    -- GitHub
    local github = createLabel(container, string.format(L["ABOUT_GITHUB"], "github.com/VincentCassiau/Sanctuary"), 12, DIM_COLOR, "CENTER")
    github:SetPoint("TOP", container, "TOP", 0, yOffset)
    yOffset = yOffset - 40

    -- Thanks
    local thanks = createLabel(container, string.format(L["ABOUT_THANKS"], "Hearlcash"), 11, DIM_COLOR, "CENTER")
    thanks:SetPoint("TOP", container, "TOP", 0, yOffset)
    yOffset = yOffset - 40

    -- ====================================================================
    -- Diagnostics section
    -- ====================================================================

    local diagSep = container:CreateTexture(nil, "ARTWORK")
    diagSep:SetHeight(1)
    diagSep:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOffset)
    diagSep:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, yOffset)
    diagSep:SetColorTexture(0.3, 0.3, 0.4, 0.4)
    yOffset = yOffset - 12

    local diagHeader = createLabel(container, L["GROUP_DEBUG"], 13, ACCENT_BLUE, "LEFT")
    diagHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 24

    -- Debug toggle checkbox. Toggling debug mode no longer touches the log:
    -- erasing a recording that may be hours old is a destructive action, and it
    -- must not be the side effect of a gesture whose purpose is something else.
    -- Clearing is now its own button, below, with a confirmation.
    local debugCb = createCheckbox(container, L["DEBUG_ENABLE"], L["TIP_DEBUG"], function(checked)
        if SanctuaryDB then
            SanctuaryDB.debugEnabled = checked
            if checked then
                if ns.captureDebugSnapshot then
                    ns.captureDebugSnapshot()
                end
                ns.printSuccess(L["DEBUG_ENABLED_MSG"])
            else
                ns.printMsg(L["DEBUG_DISABLED_MSG"])
            end
            refreshTabBar()
            refreshStatusBar()
        end
    end)
    debugCb:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOffset)
    debugCb:SetWidth(440)
    if debugCb.checkbox and SanctuaryDB then
        debugCb.checkbox:SetChecked(SanctuaryDB.debugEnabled or false)
    end
    yOffset = yOffset - 30

    -- Report summary: the in-game check on the build and the instrumentation.
    -- The record itself is the settings file, so this button no longer carries
    -- anything that has to survive a copy-paste.
    local debugSummaryBtn = createButton(container, L["DEBUG_SUMMARY_BTN"], 170, 24, function()
        showDebugSummary()
    end)
    debugSummaryBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, yOffset)

    local debugExportBtn = createButton(container, L["DEBUG_FULL_BTN"], 140, 24, function()
        showDebugExport()
    end)
    debugExportBtn:SetPoint("LEFT", debugSummaryBtn, "RIGHT", 8, 0)

    local debugClearBtn = createButton(container, L["DEBUG_CLEAR_BTN"], 90, 24, function()
        -- text_arg1 rather than a formatted OnShow: it is the substitution
        -- StaticPopup itself performs, whatever the client's dialog template.
        local kept = (SanctuaryDB and SanctuaryDB.debugLog and #SanctuaryDB.debugLog) or 0
        StaticPopup_Show("SANCTUARY_CLEAR_DEBUG_LOG", tostring(kept))
    end)
    debugClearBtn:SetPoint("LEFT", debugExportBtn, "RIGHT", 8, 0)
end

-- ========================================================================
-- Diagnostics tab (debug mode only)
-- ========================================================================

-- The catalogue itself lives in Sanctuary.lua, next to the diagnostics it
-- describes. This tab only renders it: one button per entry, the result shown
-- where it was asked for instead of scrolled back to in the chat.
local diagResultLines = {}
local diagResultText = nil
local diagResultScroll = nil
local diagResultChild = nil
local diagRestoreBtn = nil
local diagInputs = {}
local diagScreenDirty = false

local DIAG_MAX_RESULT_BLOCKS = 30

local function renderDiagnosticResults()
    if not diagResultText then return end
    if #diagResultLines == 0 then
        diagResultText:SetText(L["DIAG_RESULT_EMPTY"])
    else
        diagResultText:SetText(table.concat(diagResultLines, "\n\n"))
    end
    local height = diagResultText:GetStringHeight() or 1
    if diagResultChild then
        diagResultChild:SetHeight(math.max(height + 8, 1))
    end
    if diagRestoreBtn then
        if diagScreenDirty then
            diagRestoreBtn:Show()
        else
            diagRestoreBtn:Hide()
        end
    end
end

local function appendDiagnosticResult(label, text)
    diagResultLines[#diagResultLines + 1] = "|cFF88CCFF" .. tostring(label) .. "|r\n" .. tostring(text)
    while #diagResultLines > DIAG_MAX_RESULT_BLOCKS do
        table.remove(diagResultLines, 1)
    end
end

local function runCatalogEntry(entry)
    local argText = nil
    local input = diagInputs[entry.id]
    if input then
        argText = input:GetText()
    end
    if (not argText or argText == "") and entry.argDefault then
        argText = entry.argDefault
    end

    local result = ns.runDiagnosticById(entry.id, argText)
    appendDiagnosticResult(L[entry.labelKey] or entry.id, result.text)
    if result.leftOnScreen then
        -- A popup that could not be hidden is invisible and still clickable.
        -- Saying so here, with the way back one click away, is the whole point:
        -- the checklist used to leave that rule to memory.
        appendDiagnosticResult(L[entry.labelKey] or entry.id,
            "|cFFFF4444" .. L["DIAG_LEFT_ON_SCREEN"] .. "|r")
        diagScreenDirty = true
    end
    renderDiagnosticResults()
end

buildDiagnosticsTab = function(parent)
    local header = createLabel(parent, L["DIAG_PANEL_HEADER"], 13, ACCENT_BLUE, "LEFT")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -CONTENT_PADDING)

    local intro = createLabel(parent, L["DIAG_PANEL_INTRO"], 11, DIM_COLOR, "LEFT")
    intro:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 20))
    intro:SetWidth(FRAME_WIDTH - CONTENT_PADDING * 2 - 8)
    intro:SetWordWrap(true)

    local runAllBtn = createButton(parent, L["DIAG_RUN_ALL"], 220, 24, function()
        for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG or {}) do
            -- The one entry that writes a real Battle.net account name into the
            -- log stays on its own button: a bulk run must never be the thing
            -- that puts a friend's tag in a report.
            if not entry.sensitive then
                runCatalogEntry(entry)
            end
        end
    end)
    runAllBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING + 4, -(CONTENT_PADDING + 52))

    local clearBtn = createButton(parent, L["DIAG_CLEAR"], 90, 24, function()
        wipe(diagResultLines)
        diagScreenDirty = false
        renderDiagnosticResults()
    end)
    clearBtn:SetPoint("LEFT", runAllBtn, "RIGHT", 8, 0)

    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -(CONTENT_PADDING + 84))
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CONTENT_PADDING, -(CONTENT_PADDING + 84))
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.4)

    -- Button list (top) and result area (bottom, fixed height, anchored to the
    -- bottom so a resize grows the button list rather than the results).
    local RESULT_HEIGHT = 150

    local listScroll = CreateFrame("ScrollFrame", "SanctuaryDiagListScroll", parent,
        "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, -(CONTENT_PADDING + 92))
    listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22,
        RESULT_HEIGHT + 44)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(FRAME_WIDTH - CONTENT_PADDING * 2 - 22)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)

    local yOffset = 0
    for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG or {}) do
        local row = CreateFrame("Frame", nil, listChild)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

        local btn = createButton(row, L[entry.labelKey] or entry.id, 230, 22, function()
            runCatalogEntry(entry)
        end)
        btn:SetPoint("LEFT", row, "LEFT", 4, 0)

        local anchor = btn
        if entry.argKey then
            local input = createStyledInput(row, 90, 22)
            input:SetPoint("LEFT", btn, "RIGHT", 6, 0)
            input:SetMaxLetters(64)
            if entry.argDefault and entry.argDefault ~= "" then
                input:SetText(entry.argDefault)
            end
            input:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                runCatalogEntry(entry)
            end)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            diagInputs[entry.id] = input
            anchor = input
        end

        local tipText = entry.tipKey and L[entry.tipKey] or nil
        if entry.sensitive then
            tipText = L["DIAG_SENSITIVE"]
        end
        if tipText then
            local tip = createLabel(row, tipText, 10,
                entry.sensitive and { 1.0, 0.8, 0.3, 1.0 } or DIM_COLOR, "LEFT")
            tip:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
            tip:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            tip:SetWordWrap(false)
        end

        yOffset = yOffset + 26
    end
    listChild:SetHeight(math.max(yOffset + 6, 1))

    diagResultScroll = CreateFrame("ScrollFrame", "SanctuaryDiagResultScroll", parent,
        "UIPanelScrollFrameTemplate")
    diagResultScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_PADDING - 22, 36)
    diagResultScroll:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", CONTENT_PADDING,
        RESULT_HEIGHT + 36)

    diagResultChild = CreateFrame("Frame", nil, diagResultScroll)
    diagResultChild:SetWidth(FRAME_WIDTH - CONTENT_PADDING * 2 - 22)
    diagResultChild:SetHeight(1)
    diagResultScroll:SetScrollChild(diagResultChild)

    diagResultText = createLabel(diagResultChild, "", 11, HIGHLIGHT_COLOR, "LEFT")
    diagResultText:SetPoint("TOPLEFT", diagResultChild, "TOPLEFT", 4, -2)
    diagResultText:SetWidth(FRAME_WIDTH - CONTENT_PADDING * 2 - 32)
    diagResultText:SetWordWrap(true)

    diagRestoreBtn = createButton(parent, L["DIAG_RESTORE_BTN"], 260, 24, function()
        if type(ReloadUI) == "function" then
            ReloadUI()
        end
    end)
    diagRestoreBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", CONTENT_PADDING, 6)
    diagRestoreBtn:Hide()

    renderDiagnosticResults()
end

refreshDiagnosticsPanel = function()
    renderDiagnosticResults()
end

-- ========================================================================
-- Logs tab
-- ========================================================================

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
