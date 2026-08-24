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
    -- `.veil { background: rgba(0,0,0,.45) }` -- what the mock-up dims the screen
    -- with while a side panel is open.
    veil       = { 0.000, 0.000, 0.000, 0.45 },
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
    -- `cbBg` / `cbOn` of the mock-up, and they are NOT the input colours: a box
    -- drawn in `input` on a panel drawn in `panel` is 0.05 of grey apart from
    -- its background, which is exactly what "on ne voit pas les cases à cocher,
    -- ça fait sombre sur sombre" describes. #262633 sits above both fills.
    checkBg    = { 0.149, 0.149, 0.200, 1.00 },
    checkOn    = { 0.302, 0.702, 1.000, 1.00 },
    button     = { 0.149, 0.149, 0.251, 1.00 },
    buttonHot  = { 0.220, 0.220, 0.345, 1.00 },
    tabOff     = { 0.047, 0.047, 0.086, 0.90 },
    disabled   = { 0.380, 0.380, 0.420, 1.00 },
}

-- 16 / 14 / 13 / 12, the hierarchy Vincent asked for.
local FONT_TITLE, FONT_SECTION, FONT_DESC, FONT_BODY = 16, 14, 13, 12

-- The width the window opens at, and what the grip may take it to. Both axes
-- move now: the bounds are the brief's own, 500x380 to 900x700, measured on the
-- whole window. Nothing scrolls sideways -- what a wider window buys is wider
-- columns, not a wider canvas to pan over -- so every screen is laid out from
-- `innerWidth()` and never from the number it was built at.
local DEFAULT_WIDTH = 780
local MIN_FRAME_WIDTH, MAX_FRAME_WIDTH = 500, 900
local MIN_HEIGHT, MAX_HEIGHT = 380, 700
local HEADER_HEIGHT = 40
local TAB_HEIGHT = 22
-- How far the current tab climbs into the frame, and how thick its underline is
-- -- `margin-top:-2px` and `inset 0 -2px 0` of the mock-up, which are the same
-- two pixels.
local TAB_LIFT = 2
local PAD = 18
local PANEL_WIDTH = 540
-- The stacking order the modal panel needs, stated once. The content area nests
-- a handful of frames deep and stays near the window's own level, so the veil
-- clears it by a wide margin; the panel sits over the veil. Two things sit over
-- the PANEL: the resize grip, which is window chrome and not a setting -- the
-- close button is above the veil for the same reason, by being in the header --
-- and the undo strip, whose only four callers are the panels themselves. Burying
-- either under the veil would take away a control the panel needs.
local LEVEL_VEIL, LEVEL_PANEL, LEVEL_OVER_PANEL = 180, 200, 220
-- Room kept under the content for the tabs' own strip and the undo line, which
-- are anchored to the bottom of the frame.
local CONTENT_BOTTOM = 30
-- The undo strip, stated once because two layouts have to keep clear of it: it
-- is an overlay pinned this far above the bottom edge of the frame, and it sits
-- OVER the panels rather than inside them.
local UNDO_HEIGHT, UNDO_MARGIN = 22, 6
-- What the whole window may measure in height, header and bottom strip included.
local MIN_FRAME_HEIGHT = MIN_HEIGHT + HEADER_HEIGHT + CONTENT_BOTTOM
local MAX_FRAME_HEIGHT = MAX_HEIGHT + HEADER_HEIGHT + CONTENT_BOTTOM
local UNDO_SECONDS = 6
-- The sentence a refused entry gets. It answers for the panel, not for the box,
-- so it runs the panel's own text width -- the one the descriptions above it
-- already use -- and not the 250 px of the field: the Battle.net sentence is 82
-- characters in French, which no latin face fits into 250 px at FONT_BODY, so at
-- the box's width it would fold onto three lines and lie over the first row of
-- chips.
-- The width the window is at right now, and what everything measures itself
-- against. `DEFAULT_WIDTH` is only where the window opens; a screen or a panel
-- that reads it instead of these is a screen that stops following the grip.
local frameWidth = DEFAULT_WIDTH
local function innerWidth() return frameWidth - PAD * 2 end
-- The drawer keeps the mock-up's 540 px while there is room for it, and never
-- takes so much that nothing of the window is left beside it: the strip of veil
-- next to the panel is what a person clicks to close it.
local function panelWidth() return math.min(PANEL_WIDTH, frameWidth - 60) end
-- The sentence under an add field runs the drawer's text column. Bounded by the
-- window as well, and not by the drawer alone: the drawer is the one thing here
-- allowed to be wider than the screen behind it, and a sentence is not.
local function noteWidth() return math.min(panelWidth() - 40, innerWidth()) end
local NOTE_GAP = 4
-- One line of FONT_BODY, rounded up: the client draws a 12 px face on about
-- 14 px of line.
local NOTE_LINE = 15
-- Room kept under an add field for its sentence, showing or not, so nothing on
-- screen moves when one appears. One line covers the two name sentences and the
-- pattern one at the note width; the blocked names field is the only one that can
-- answer with the Battle.net sentence, which still takes two lines there, so it
-- keeps two. The harness measures the six strings against these two values.
local NOTE_ROOM = NOTE_GAP + NOTE_LINE
local NOTE_ROOM_TWO_LINES = NOTE_GAP + 2 * NOTE_LINE
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

-- The mask Retail ships for exactly this: a circle that scales to whatever size
-- the texture is given. The radios of the mock-up are round (`border-radius:50%`)
-- and the add-on draws every widget itself, so the shape has to come from
-- somewhere; a mask is the one way to round a solid colour.
local CIRCLE_MASK = "Interface\\Masks\\CircleMaskScalable"

-- A filled disc of `color`, centred on `frame`. Should the mask fail to load,
-- what is left is the same disc as a square -- still the right colour, still the
-- right size, still visible, which is the property A1 is actually about.
local function newDisc(frame, layer, size, color)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetSize(size, size)
    tex:SetPoint("CENTER")
    tex:SetColorTexture(unpack(color))
    local mask = frame.CreateMaskTexture and frame:CreateMaskTexture()
    if mask and tex.AddMaskTexture then
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(size, size)
        mask:SetPoint("CENTER")
        tex:AddMaskTexture(mask)
    end
    return tex
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
-- "BackdropTemplate" is the whole of the empty-box defect, and it was invisible
-- from here: `applyBackdrop` gives up in silence on a frame with no `SetBackdrop`
-- (`if not frame.SetBackdrop then return end`), and in Retail a bare CheckButton
-- has none -- the mixin is what adds it. So the fill and the border were never
-- drawn, an unticked box was nothing at all and a ticked one was the bare 10 px
-- mark: "une case décochée n'a aucun rendu, une case cochée est un simple carré
-- bleu", word for word. The harness cannot see this: its widgets answer every
-- capitalised method, `SetBackdrop` included, whatever the template says.
local function newCheck(parent, name, text, tooltip, get, set)
    local frame = CreateFrame("CheckButton", name, parent, "BackdropTemplate")
    frame:SetSize(18, 18)
    applyBackdrop(frame, C.checkBg, C.border)
    frame.mark = frame:CreateTexture(nil, "OVERLAY")
    frame.mark:SetPoint("CENTER")
    frame.mark:SetSize(10, 10)
    frame.mark:SetColorTexture(unpack(C.checkOn))

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
        applyBackdrop(self, C.checkBg, self.enabled and C.border or C.disabled)
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
-- Round rather than square, and the same 18 px as the check so the two read as
-- one family: three discs stacked -- the rim, the fill, the dot -- rather than a
-- backdrop, because a backdrop has corners and `border-radius:50%` does not.
local function newRadio(parent, name, text, tooltip, isOn, select)
    local frame = CreateFrame("Button", name, parent)
    frame:SetSize(18, 18)
    frame.rim = newDisc(frame, "BACKGROUND", 18, C.border)
    frame.fill = newDisc(frame, "BORDER", 16, C.checkBg)
    frame.mark = newDisc(frame, "OVERLAY", 8, C.checkOn)

    frame.label = newLabel(parent, text, FONT_BODY, C.soft)
    frame.label:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    frame.enabled = true

    function frame:Refresh()
        local on = isOn() and true or false
        if self.mark then
            if on then self.mark:Show() else self.mark:Hide() end
        end
        -- `.rd.on { border-color: accent }`: the rim answers too, so a picked
        -- channel reads even at a glance that stops short of the 8 px dot.
        if self.rim then
            local rim = (not self.enabled) and C.disabled or (on and C.accent or C.border)
            self.rim:SetColorTexture(unpack(rim))
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

    -- The card and the wrapping width of its description are one measurement,
    -- so they are set together: a card widened on its own leaves its own text
    -- folded to the width it was built at.
    function card:SetCardWidth(newWidth)
        self:SetWidth(newWidth)
        self.desc:SetWidth(newWidth - 24)
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
-- `keepText`: this box carries a setting rather than feeding a list. A list box
-- clears on Enter, ready for the next name; a setting box must keep showing the
-- value, which `onEnter` has just written and redrawn.
local function newInput(parent, name, width, hintText, onEnter, keepText)
    local box = CreateFrame("EditBox", name, parent, "BackdropTemplate")
    box:SetSize(width or 220, 24)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    applyBackdrop(box, C.input, C.border)

    box.hint = newLabel(box, hintText, FONT_BODY, C.dim)
    box.hint:SetPoint("LEFT", box, "LEFT", 7, 0)
    -- Cut at the field's own edge, never past it. The hint used to be a
    -- FontString with no width at all: "Texte à chercher dans les pseudos,
    -- ex. « test »" ran out of the box and under the Add button, which is what
    -- "le placeholder de patterns dépasse" describes. One line, and the wording
    -- itself is short enough to fit -- a hint nobody can read whole says nothing.
    box.hint:SetWidth((width or 220) - 14)
    box.hint:SetWordWrap(false)

    -- The line that says why an entry was refused. It starts at the box's left
    -- edge, so there is never a doubt which of the three fields is being
    -- answered, but it runs the panel's width rather than the box's: the box is
    -- 250 px and the sentences are up to 82 characters. The panels keep its room
    -- reserved whether it is showing or not -- a sentence that appears must not
    -- shove the list under it downwards, nor lie over it.
    box.note = newLabel(box, "", FONT_BODY, C.orange)
    box.note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -NOTE_GAP)
    box.note:Hide()

    -- `noteWidth()` reads the window as it is now, and a field built at 780 kept
    -- the 500 px column it was given then for ever -- inside a window that can be
    -- 500 px wide in total. The panels ask on every redraw; the fields that live
    -- on a screen are asked by their screen's width pass.
    function box:RefreshNoteWidth() self.note:SetWidth(noteWidth()) end
    box:RefreshNoteWidth()

    function box:RefreshHint()
        local text = self:GetText()
        local empty = (text == nil or text == "")
        if empty then self.hint:Show() else self.hint:Hide() end
        -- The cross answers to the same thing the hint does: there is nothing to
        -- clear in an empty field, and a cross offering to do it says otherwise.
        if self.clear then
            if empty then self.clear:Hide() else self.clear:Show() end
        end
    end

    function box:ClearNote()
        self.noteToken = nil
        self.note:SetText("")
        self.note:Hide()
    end

    -- The generation token the undo strip uses, and for the same reason: two
    -- refusals a second apart leave two timers running, and the older one must
    -- not wipe the sentence the newer one has just put up. Same six seconds as
    -- the undo strip, from the same constant -- one duration on this screen.
    function box:SayNo(text)
        local mine = {}
        self.noteToken = mine
        self.note:SetText(text)
        self.note:Show()
        C_Timer.After(UNDO_SECONDS, function()
            if self.noteToken == mine then self:ClearNote() end
        end)
    end

    -- An opt-in cross inside the field, for the one box that carries a question
    -- rather than an entry: the tester. It is a read of the lists, so emptying
    -- it is the way out of it, and re-typing over a name to be rid of an answer
    -- is not a way out. Opt-in because the three list fields empty themselves on
    -- Enter and a cross there would answer a question nobody asked.
    function box:MakeClearable()
        if self.clear then return self end
        -- Room for the cross taken off the text itself, so a long name is
        -- scrolled by the client rather than written under the button.
        self:SetTextInsets(6, 22, 0, 0)
        self.hint:SetWidth((width or 220) - 30)
        local clear = CreateFrame("Button", nil, self)
        clear:SetSize(16, 16)
        clear:SetPoint("RIGHT", self, "RIGHT", -4, 0)
        clear.label = newLabel(clear, "x", FONT_BODY, C.dim, "CENTER")
        clear.label:SetPoint("CENTER")
        clear:SetScript("OnEnter", function() clear.label:SetTextColor(unpack(C.ink)) end)
        clear:SetScript("OnLeave", function() clear.label:SetTextColor(unpack(C.dim)) end)
        clear:SetScript("OnClick", function()
            self:SetText("")
            self:RefreshHint()
            self:ClearFocus()
            -- Emptying the field is a text change like any other, and what it
            -- means for this box is the box's own business. Called rather than
            -- left to the client's own OnTextChanged: the cross must clear the
            -- answer under it, not hope something else notices.
            local changed = self:GetScript("OnTextChanged")
            if changed then changed(self) end
        end)
        clear:Hide()
        self.clear = clear
        return self
    end

    box:SetScript("OnTextChanged", function(self) self:RefreshHint() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onEnter then
        box:SetScript("OnEnterPressed", function(self)
            onEnter(self:GetText())
            if not keepText then self:SetText("") end
            self:RefreshHint()
        end)
    end
    return box
end

-- A drop-down of our own, and one for the whole add-on: at most one list can be
-- open at a time, so the open one is held here rather than on each field.
--
-- `UIDropDownMenu` and its family are deliberately not used. They come with
-- their own look, which is not the one the mock-ups draw, and they are the
-- classic way for an add-on to taint the interface. What is needed here is a
-- field showing the chosen value and a list of eight rows over the screen --
-- which is a button, a frame, and eight buttons.
local openDropdown

local function closeOpenDropdown()
    local current = openDropdown
    openDropdown = nil
    if current and current.list then current.list:Hide() end
end

local DROPDOWN_ROW_HEIGHT = 22
-- U+25BE, the small down-pointing triangle the mock-up draws in the field. A
-- glyph, not a sentence: there is nothing here for a translator to say.
local DROPDOWN_CARET = "\226\150\190"

local function newDropdown(parent, name, width, rows, get, set)
    local field = CreateFrame("Button", name, parent, "BackdropTemplate")
    field:SetSize(width or 140, 24)
    applyBackdrop(field, C.input, C.border)
    field.value = newLabel(field, "", FONT_BODY, C.ink)
    field.value:SetPoint("LEFT", field, "LEFT", 8, 0)
    field.caret = newLabel(field, DROPDOWN_CARET, FONT_BODY, C.dim)
    field.caret:SetPoint("RIGHT", field, "RIGHT", -8, 0)
    field.enabled = true

    -- NOT a child of the screen, and that is load-bearing: the five screens live
    -- inside a ScrollFrame, which clips what it holds. A list opening near the
    -- bottom of the visible area would be cut at the viewport's edge, with no
    -- way to reach the rows below it. Anchored to the field all the same, so it
    -- follows the window and the scrolling.
    local list = CreateFrame("Frame", name and (name .. "List") or nil,
        UIParent or parent, "BackdropTemplate")
    list:SetSize(width or 140, #rows * DROPDOWN_ROW_HEIGHT + 8)
    -- Over the window itself, which sits at DIALOG.
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    applyBackdrop(list, C.panel, C.accent)
    list:Hide()
    list:SetScript("OnHide", function()
        -- The list is registered in UISpecialFrames below, so it can be hidden
        -- without going through `closeOpenDropdown` -- by Escape, or by anything
        -- else that hides it. The record of what is open is cleared here so it
        -- is right whichever way the list went away.
        if openDropdown == field then openDropdown = nil end
    end)
    field.list = list
    field.rows = {}

    for index, row in ipairs(rows) do
        local option = CreateFrame("Button", nil, list, "BackdropTemplate")
        option:SetSize((width or 140) - 8, DROPDOWN_ROW_HEIGHT)
        option:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (index - 1) * DROPDOWN_ROW_HEIGHT)
        applyBackdrop(option, C.tile, C.tile)
        option.label = newLabel(option, row.text, FONT_BODY, C.soft)
        option.label:SetPoint("LEFT", option, "LEFT", 8, 0)
        option:SetScript("OnEnter", function(self) applyBackdrop(self, C.accentBg, C.accent) end)
        option:SetScript("OnLeave", function(self) applyBackdrop(self, C.tile, C.tile) end)
        option:SetScript("OnClick", function()
            closeOpenDropdown()
            set(row.value)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if ns.refreshUI then ns.refreshUI() end
        end)
        field.rows[index] = option
    end

    -- Drawn from the model like every other component here: the field shows what
    -- the core answers, never what the last click wrote.
    function field:Refresh()
        local current = get()
        local text = ""
        for _, row in ipairs(rows) do
            if row.value == current then text = row.text end
        end
        self.value:SetText(text)
        self.value:SetTextColor(unpack(self.enabled and C.ink or C.disabled))
        self.caret:SetTextColor(unpack(self.enabled and C.dim or C.disabled))
        applyBackdrop(self, C.input, self.enabled and C.border or C.disabled)
    end

    function field:SetEnabledState(enabled)
        self.enabled = enabled and true or false
        if not self.enabled then closeOpenDropdown() end
        self:Refresh()
    end

    field:SetScript("OnClick", function(self)
        if not self.enabled then return end
        local wasOpen = openDropdown == self
        closeOpenDropdown()
        if wasOpen then return end
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        list:Show()
        openDropdown = self
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    if name and UISpecialFrames then
        -- Registered so that Escape closes the list. Whether the same Escape
        -- also closes the main window, which is registered here too, has not
        -- been observed in a client and is not assumed: both OnHide handlers
        -- clear `openDropdown`, so either outcome leaves a coherent state.
        tinsert(UISpecialFrames, name .. "List")
    end

    field:Refresh()
    return field
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
    -- One line, cut at the width `layoutChips` gives it. A name too long for the
    -- row used to be written past the end of its own chip, under the cross.
    chip.label:SetWordWrap(false)
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

    -- A viewport that follows its container, on both axes: nothing in this
    -- window scrolls sideways, so a narrower window is a narrower viewport and
    -- not a canvas to pan over. The track is resized with it rather than keeping
    -- the size it was born with.
    function scroll:SetViewportSize(newWidth, newHeight)
        local boundedWidth = math.max(120, newWidth or width)
        local boundedHeight = math.max(40, newHeight or height)
        self:SetSize(boundedWidth, boundedHeight)
        self.child:SetWidth(boundedWidth)
        self.bar:SetHeight(boundedHeight)
        self:RefreshBar()
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
    -- The rule spans the section, so widening the section widens the rule; the
    -- description has to be told separately.
    function section:SetSectionWidth(newWidth)
        self:SetWidth(newWidth)
        if self.desc then self.desc:SetWidth(newWidth) end
    end
    return section
end

-- ============================================================================
-- SECTION 3: State shared by the screens
-- ============================================================================

local mainFrame, contentFrame, contentScroll, stateButton, resizeGrip
-- The sheet of nothing that makes the side panels modal: it covers the frame
-- from the bottom of the header down and eats every click, so the screen behind
-- an open panel can be read but not touched.
local panelVeil
-- Declared here because the panels have to refresh it when they open and close,
-- and they are written further up the file than the header is.
local refreshStateButton
local tabFrames, tabButtons = {}, {}
local activeTab = "protection"
local manualSize = nil
local refreshTab = {}
-- What each screen has to redo when the window changes width, and nothing else.
--
-- A screen derives a dozen widths from `innerWidth()` while it is being built,
-- at whatever the window measured then, and a frame keeps a posted width for
-- ever. `applyViewport` handed the new width to the frame, the content area, the
-- five screens, the drawer and the undo strip -- and stopped there, so
-- everything INSIDE a screen still measured 780's 744: at 500 px a section rule,
-- a paragraph and a Journal row hung two hundred and eighty pixels outside a
-- window that has no horizontal scrolling by design, and at 900 they left the
-- room they had been given empty. A6 asks the columns to share the width between
-- 500x380 and 900x700.
--
-- One entry per screen, called on every pass -- not only for the screen on show:
-- a hidden screen is one tab click away and nothing else would ever tell it.
-- Each entry guards itself, because `applyViewport` runs from the window's own
-- OnSizeChanged, which is installed before the screens are built.
local applyTabWidth = {}
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

local function offerUndoLine(text, restore)
    undoState = { restore = restore, at = GetTime() }
    local mine = undoState
    if undoLine then
        undoLine.label:SetText(text)
        undoLine:Show()
    end
    C_Timer.After(UNDO_SECONDS, function()
        if undoState == mine then clearUndo() end
    end)
end

local function offerUndo(labelText, restore)
    offerUndoLine(string.format(L["UNDO_REMOVED"], labelText), restore)
end

-- The two lists are exclusive, so a name written into one leaves the other, and
-- that is a removal nobody asked for out loud: it gets the same strip, naming
-- the list it left. Annuler puts the WHOLE gesture back -- this entry out, that
-- one in -- because undoing half of it would leave the name in both lists again,
-- which is the state decision 104 exists to end.
local DISPLACED_UNDO = {
    allowed = { titleKey = "TILE_ALLOWED", remove = "removeBlocked", restore = "restoreAllowed" },
    blocked = { titleKey = "TILE_BLOCKED", remove = "removeAllowed", restore = "restoreBlocked" },
}

local function offerDisplacedUndo(addedKey, displaced)
    if type(displaced) ~= "table" then return end
    local spec = DISPLACED_UNDO[displaced.list]
    if not spec or not addedKey then return end
    local label = ns.qualifiedDisplayName(displaced.key,
        type(displaced.data) == "table" and displaced.data.displayName or nil)
        or displaced.key
    offerUndoLine(string.format(L["UNDO_MOVED"], label, L[spec.titleKey]), function()
        ns[spec.remove](addedKey)
        ns[spec.restore](displaced.key, displaced.data)
    end)
end

-- ============================================================================
-- SECTION 5: Protection screen
-- ============================================================================

local protection = {}

-- The mock-up's own metrics, named once. `.content { padding:18px; gap:20px }`,
-- `.cards { gap:10px }`, and one row for a `.qt` at 16 px. Written here rather
-- than as numbers at the two places that need them: the build lays the screen
-- out top-down and the refresh re-lays it from question 3, so a height spelt out
-- twice is a screen that agrees with itself only until somebody edits one half.
local Q_TITLE_ROW, CARD_HEIGHT, CARD_GUTTER, BLOCK_GAP = 26, 74, 10, 20
-- Where the block under question 2 begins, written as the sum of the two
-- question blocks above it rather than as one number so a change to any of them
-- is visible here.
local CHOOSE_TOP = -(Q_TITLE_ROW + CARD_HEIGHT + BLOCK_GAP
    + Q_TITLE_ROW + CARD_HEIGHT + 14)
-- One row of a check or a radio, and the extra a wrapped sub-line takes.
local ROW_HEIGHT = 24

local function buildProtectionTab(parent)
    protection.frame = parent
    local width = innerWidth()
    local y = 0

    -- `.qt` is two pieces, not one string: a small accent number and a 16 px
    -- white title, ten pixels apart. Three spaces in one accent-coloured
    -- 14 px string gave neither the hierarchy nor the air.
    local function stepTitle(text, number)
        local num = newLabel(parent, number, FONT_BODY, C.accent)
        num:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - 4)
        local head = newLabel(parent, text, FONT_TITLE, C.ink)
        head:SetPoint("TOPLEFT", num, "TOPRIGHT", 10, 4)
        y = y - Q_TITLE_ROW
        return head, num
    end

    -- Question 1 ------------------------------------------------------------
    stepTitle(L["Q1_TITLE"], "1")
    local cardWidth = (width - CARD_GUTTER) / 2
    protection.q1Strangers = newCard(parent, "SanctuaryQ1_strangers",
        L["Q1_STRANGERS_TITLE"], L["Q1_STRANGERS_DESC"], cardWidth,
        function() return ns.getScope() == "strangers" end,
        function() setFilter("scope", "strangers") end)
    protection.q1Strangers:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    protection.q1Blocked = newCard(parent, "SanctuaryQ1_blockedOnly",
        L["Q1_BLOCKEDONLY_TITLE"], L["Q1_BLOCKEDONLY_DESC"], cardWidth,
        function() return ns.getScope() == "blockedOnly" end,
        function() setFilter("scope", "blockedOnly") end)
    protection.q1Blocked:SetPoint("TOPLEFT", protection.q1Strangers, "TOPRIGHT", CARD_GUTTER, 0)
    y = y - CARD_HEIGHT - BLOCK_GAP

    -- Question 2 ------------------------------------------------------------
    protection.q2Title, protection.q2Number = stepTitle(L["Q2_TITLE"], "2")
    protection.q2All = newCard(parent, "SanctuaryQ2_all",
        L["Q2_ALL_TITLE"], L["Q2_ALL_DESC"], cardWidth,
        function() return ns.getPreset() == "all" end,
        function() setFilter("preset", "all") end)
    protection.q2All:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    protection.q2Custom = newCard(parent, "SanctuaryQ2_custom",
        L["Q2_CUSTOM_TITLE"], L["Q2_CUSTOM_DESC"], cardWidth,
        function() return ns.getPreset() == "custom" end,
        function() setFilter("preset", "custom") end)
    protection.q2Custom:SetPoint("TOPLEFT", protection.q2All, "TOPRIGHT", CARD_GUTTER, 0)
    y = y - CARD_HEIGHT - 14

    -- The enhanced-instance box is a single widget with two homes: under the two
    -- cards in "Everything", indented under "Block group invitations" in "I
    -- choose". Two widgets would mean two states to keep in step.
    protection.strict = newCheck(parent, "SanctuaryStrictCheck",
        L["FILTER_STRICT_GROUP_INVITE_SYSTEM"], L["TIP_STRICT_GROUP_INVITE_SYSTEM"],
        function() return filterStored("strictGroupInviteSystemMessages") == true end,
        function(value) setFilter("strictGroupInviteSystemMessages", value) end)
    protection.strictNote = newLabel(parent, L["STRICT_EXPERIMENTAL"], FONT_BODY, C.dim)

    -- Automatic trust used to live at the bottom of Advanced, three sections
    -- down, with its sentence spelt out underneath. It decides who is allowed --
    -- the same question the whole screen is about -- so it belongs here, on the
    -- row under the strict box, in the same shape as every other line: a box, a
    -- label, and the sentence on hover rather than a paragraph on screen.
    protection.trust = newCheck(parent, "SanctuaryAutoTrust",
        L["FILTER_AUTO_TRUST"], L["ADV_TRUST_DESC"],
        function() return filterStored("autoTrust") == true end,
        function(value) setFilter("autoTrust", value) end)

    -- Question 3 ------------------------------------------------------------
    -- The same two cards every other question is made of (decision 131: "si on
    -- met des designs différents selon les étapes on s'y perd"), with the
    -- window and the note underneath them.
    protection.q3Number = newLabel(parent, "3", FONT_BODY, C.accent)
    protection.q3Title = newLabel(parent, L["ANTISPAM_Q_TITLE"], FONT_TITLE, C.ink)
    protection.q3Title:SetPoint("TOPLEFT", protection.q3Number, "TOPRIGHT", 10, 4)
    protection.q3Yes = newCard(parent, "SanctuaryQ3_yes",
        L["ANTISPAM_YES_TITLE"], L["ANTISPAM_YES_DESC"], cardWidth,
        function() return ns.isAntiSpamEnabled() end,
        function() ns.setAntiSpamEnabled(true) end)
    protection.q3No = newCard(parent, "SanctuaryQ3_no",
        L["ANTISPAM_NO_TITLE"], L["ANTISPAM_NO_DESC"], cardWidth,
        function() return not ns.isAntiSpamEnabled() end,
        function() ns.setAntiSpamEnabled(false) end)

    protection.q3IntervalLabel = newLabel(parent, L["ANTISPAM_INTERVAL_LABEL"], FONT_BODY, C.soft)
    -- Written out rather than built from the number of seconds: a key that only
    -- exists as a concatenation cannot be found by searching for it, and an
    -- unreachable translation is one nobody will ever notice is missing.
    local DURATION_ROWS = {
        { value = 300,   labelKey = "ANTISPAM_D_5M" },
        { value = 600,   labelKey = "ANTISPAM_D_10M" },
        { value = 1800,  labelKey = "ANTISPAM_D_30M" },
        { value = 3600,  labelKey = "ANTISPAM_D_1H" },
        { value = 7200,  labelKey = "ANTISPAM_D_2H" },
        { value = 14400, labelKey = "ANTISPAM_D_4H" },
        { value = 43200, labelKey = "ANTISPAM_D_12H" },
        { value = 86400, labelKey = "ANTISPAM_D_24H" },
    }
    local durationRows = {}
    for index, row in ipairs(DURATION_ROWS) do
        durationRows[index] = { value = row.value, text = L[row.labelKey] }
    end
    protection.q3Interval = newDropdown(parent, "SanctuaryAntiSpamInterval", 130, durationRows,
        function() return ns.getAntiSpamInterval() end,
        function(value) ns.setAntiSpamInterval(value) end)
    protection.q3Note = newLabel(parent, L["ANTISPAM_NOTE"], FONT_BODY, C.dim)

    -- The detailed boxes, folded away until "I choose" is picked.
    local choose = CreateFrame("Frame", "SanctuaryChoose", parent)
    choose:SetSize(width, 1)
    protection.choose = choose
    protection.checks = {}

    -- Two columns, and which row goes in which is the mock-up's own split
    -- (`C2Choisis`, `.cols`): everything that is chat or an invitation on the
    -- left, everything that is an action plus the public channels on the right.
    -- One column made the screen taller than the window on its own, which is
    -- what "ça allonge la fenêtre" is about -- and the fold is what a person
    -- reads first, so it is data here rather than an order of creation.
    local CHECK_ROWS = {
        { key = "groupInvite", labelKey = "FILTER_GROUP_INVITE", tipKey = "TIP_GROUP_INVITE", col = 1 },
        { key = "whisper",     labelKey = "FILTER_WHISPER",      tipKey = "TIP_WHISPER",      col = 1 },
        { key = "say",         labelKey = "FILTER_SAY",          tipKey = "TIP_SAY",          col = 1 },
        { key = "yell",        labelKey = "FILTER_YELL",         tipKey = "TIP_YELL",         col = 1 },
        { key = "emote",       labelKey = "FILTER_EMOTE",        tipKey = "TIP_EMOTE",        col = 1 },
        { key = "duel",        labelKey = "FILTER_DUEL",         tipKey = "TIP_DUEL",         col = 2 },
        { key = "trade",       labelKey = "FILTER_TRADE",        tipKey = "TIP_TRADE",        col = 2 },
        { key = "guildInvite", labelKey = "FILTER_GUILD_INVITE", tipKey = "TIP_GUILD_INVITE", col = 2 },
    }
    for _, row in ipairs(CHECK_ROWS) do
        local check = newCheck(choose, "SanctuaryFilter_" .. row.key,
            L[row.labelKey], L[row.tipKey],
            function() return filterStored(row.key) == true end,
            function(value) setFilter(row.key, value) end)
        protection.checks[row.key] = check
    end

    protection.channelsLabel = newLabel(choose, L["CHANNELS_LABEL"], FONT_BODY, C.soft)
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
        protection.channelRadios[mode] = radio
    end

    -- Laid out from a width rather than at a fixed one: the window resizes on
    -- both axes now, and the two columns are the only thing on this screen that
    -- has to share the extra pixels. Measured on the way through and never
    -- guessed -- a wrong constant here is a screen that fits on the developer's
    -- layout and is cut off on the real one.
    function protection.layoutChoose(innerWidth)
        local colWidth = (innerWidth - BLOCK_GAP) / 2
        local colX = { 0, colWidth + BLOCK_GAP }
        local colY = { 0, 0 }
        for _, row in ipairs(CHECK_ROWS) do
            local col = row.col
            local check = protection.checks[row.key]
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[col], colY[col])
            colY[col] = colY[col] - ROW_HEIGHT
            if row.key == "groupInvite" then
                -- `.cbr.sub { padding-left:26px }` -- the indented slot the
                -- strict box takes in this mode, kept clear whether it is
                -- there or not.
                protection.strictSlot = colY[col]
                colY[col] = colY[col] - ROW_HEIGHT
            end
        end

        protection.channelsLabel:ClearAllPoints()
        protection.channelsLabel:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[2], colY[2] - 6)
        colY[2] = colY[2] - 28
        for _, row in ipairs(CHANNEL_ROWS) do
            local radio = protection.channelRadios[row.mode]
            radio:ClearAllPoints()
            radio:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[2] + 16, colY[2])
            colY[2] = colY[2] - 22
        end

        protection.chooseHeight = -math.min(colY[1], colY[2])
        choose:SetSize(innerWidth, protection.chooseHeight)
        return protection.chooseHeight
    end
    protection.layoutChoose(width)

    -- Question 4 ------------------------------------------------------------
    protection.q4Anchor = CreateFrame("Frame", nil, parent)
    protection.q4Anchor:SetSize(width, 1)
    -- Same two pieces as the questions above, but placed by the refresh rather
    -- than here: what sits over them folds and unfolds. The title rides on the
    -- number, so the refresh only ever moves one of the two.
    protection.q4Number = newLabel(parent, "4", FONT_BODY, C.accent)
    protection.q4Title = newLabel(parent, L["Q4_TITLE"], FONT_TITLE, C.ink)
    protection.q4Title:SetPoint("TOPLEFT", protection.q4Number, "TOPRIGHT", 10, 4)
    local thirdWidth = (width - CARD_GUTTER * 2) / 3
    protection.q4 = {}
    local Q4_ROWS = {
        { key = "silent",  titleKey = "Q4_SILENT_TITLE",  descKey = "Q4_SILENT_DESC" },
        { key = "minimal", titleKey = "Q4_MINIMAL_TITLE", descKey = "Q4_MINIMAL_DESC" },
        { key = "verbose", titleKey = "Q4_VERBOSE_TITLE", descKey = "Q4_VERBOSE_DESC" },
    }
    for _, row in ipairs(Q4_ROWS) do
        local card = newCard(parent, "SanctuaryQ4_" .. row.key,
            L[row.titleKey], L[row.descKey], thirdWidth,
            function() return SanctuaryDB and SanctuaryDB.notifications.mode == row.key end,
            function() SanctuaryDB.notifications.mode = row.key end)
        protection.q4[row.key] = card
    end

    -- Question 5 ------------------------------------------------------------
    protection.q5Number = newLabel(parent, "5", FONT_BODY, C.accent)
    protection.q5Title = newLabel(parent, L["Q5_TITLE"], FONT_TITLE, C.ink)
    protection.q5Title:SetPoint("TOPLEFT", protection.q5Number, "TOPRIGHT", 10, 4)

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
    protection.testInput:MakeClearable()
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
            -- A guild mate, a realm friend, somebody in the group. Never
            -- Battle.net: `describeAccessDecision` stopped answering that, and
            -- the branch that formatted it went with it -- it is the sentence
            -- decision 100 called false, and leaving it here would keep it one
            -- edit away from coming back.
            local overKey = LIST_KEYS[info.overriddenList]
            reason = string.format(L["LIST_BLOCKED_OVER"],
                overKey and L[overKey] or tostring(info.overriddenList))
        else
            reason = L["LIST_BLOCKED"]
        end
        answer:SetText(string.format(L["TEST_ALWAYS_BLOCKED"], info.display, reason))
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
        answer:SetText(string.format(L["TEST_ALWAYS_ALLOWED"], info.display, reason))
        answer:SetTextColor(unpack(C.green))
        return
    end

    if info.blockedNow then
        answer:SetText(string.format(L["TEST_UNKNOWN_BLOCKED"], info.display))
        answer:SetTextColor(unpack(C.orange))
    else
        answer:SetText(string.format(L["TEST_UNKNOWN_ALLOWED"], info.display))
        answer:SetTextColor(unpack(C.dim))
    end
end

-- Everything on this screen whose size comes from the window's width. Questions
-- 1, 2, 3 and 4 and the two tiles are laid out at build time -- what sits above
-- them never folds -- and the fold itself is measured from the same number, so
-- all of it has to be handed the live width again whenever the window changes.
applyTabWidth.protection = function()
    -- The last widget the builder makes: the guard means "this screen is
    -- finished", not "it has been started".
    if not protection.testAnswer then return end
    local width = innerWidth()
    local cardWidth = (width - CARD_GUTTER) / 2
    for _, card in ipairs({ protection.q1Strangers, protection.q1Blocked,
        protection.q2All, protection.q2Custom,
        protection.q3Yes, protection.q3No }) do
        card:SetCardWidth(cardWidth)
    end
    -- The note under question 3 is a sentence, not a label: it wraps, so it is
    -- the one thing on this screen that has to be told the width it wraps at.
    protection.q3Note:SetWidth(width)
    protection.tileAllowed:SetWidth(cardWidth)
    protection.tileBlocked:SetWidth(cardWidth)
    local thirdWidth = (width - CARD_GUTTER * 2) / 3
    for _, key in ipairs({ "silent", "minimal", "verbose" }) do
        protection.q4[key]:SetCardWidth(thirdWidth)
    end
    -- The invisible frame question 4 hangs from, and the two columns of "I
    -- choose": `layoutChoose` is what shares the width between them, and it
    -- answers the height the fold needs, which the refresh below reads.
    protection.q4Anchor:SetWidth(width)
    protection.layoutChoose(width)
    -- The tester's sentence starts at PAD + 360 and runs to the right margin.
    protection.testAnswer:SetWidth(math.max(60, width - 360))
    protection.testInput:RefreshNoteWidth()
end

-- Lays the screen out for the mode it is in, and returns the height it needs.
refreshTab.protection = function()
    local blockedOnly = ns.getScope() == "blockedOnly"
    local custom = ns.getPreset() == "custom"

    -- Question 2 is greyed out, never removed: the answers stay where they were
    -- and come back untouched when question 1 goes back to filtering strangers.
    for _, card in ipairs({ protection.q2All, protection.q2Custom }) do
        card:SetEnabledState(not blockedOnly)
    end
    protection.strict:SetEnabledState(not blockedOnly)
    -- The widths first, and through the one function that knows them: a screen
    -- laid out against a width it no longer has is the whole of this defect.
    applyTabWidth.protection()
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
    protection.q2Title:SetTextColor(unpack(blockedOnly and C.disabled or C.ink))
    protection.q2Number:SetTextColor(unpack(blockedOnly and C.disabled or C.accent))

    local y = CHOOSE_TOP
    if custom then
        protection.choose:Show()
        protection.choose:ClearAllPoints()
        protection.choose:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
        protection.strict:ClearAllPoints()
        protection.strict:SetPoint("TOPLEFT", protection.choose, "TOPLEFT", 26, protection.strictSlot)
        protection.strictNote:Hide()
        y = y - protection.chooseHeight - 4
    else
        protection.choose:Hide()
        protection.strict:ClearAllPoints()
        protection.strict:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
        protection.strictNote:ClearAllPoints()
        protection.strictNote:SetPoint("LEFT", protection.strict.label, "RIGHT", 8, 0)
        protection.strictNote:Show()
        y = y - ROW_HEIGHT
    end
    protection.strict:Refresh()

    -- Under the strict box in both modes: in "I choose" the strict box has gone
    -- into the left column, and this line stays at the screen's own left margin
    -- because it answers question 1, not question 2.
    protection.trust:ClearAllPoints()
    protection.trust:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    protection.trust:Refresh()
    y = y - ROW_HEIGHT - BLOCK_GAP

    -- Question 3 -- the anti-spam of the public channels.
    --
    -- Greyed out, never removed, and the settings underneath are not touched:
    -- somebody who filters every channel has nothing left for this to hide, and
    -- when they go back the answers they gave are still there. Same shape as
    -- question 2 greyed out in "Everyone except the people I block", one line
    -- above -- and the one question asked is `isChannelSpamCovered`, so the
    -- greying and the decision cannot disagree.
    local covered = ns.isChannelSpamCovered()
    local antiSpamOn = ns.isAntiSpamEnabled()
    protection.q3Yes:SetEnabledState(not covered)
    protection.q3No:SetEnabledState(not covered)
    -- The window is a detail of "Yes": on "No" there is nothing to delay.
    protection.q3Interval:SetEnabledState(not covered and antiSpamOn)
    protection.q3IntervalLabel:SetTextColor(unpack(
        (covered or not antiSpamOn) and C.disabled or C.soft))
    protection.q3Title:SetTextColor(unpack(covered and C.disabled or C.ink))
    protection.q3Number:SetTextColor(unpack(covered and C.disabled or C.accent))

    protection.q3Number:ClearAllPoints()
    protection.q3Number:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y - 4)
    y = y - Q_TITLE_ROW
    protection.q3Yes:ClearAllPoints()
    protection.q3Yes:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    protection.q3No:ClearAllPoints()
    protection.q3No:SetPoint("TOPLEFT", protection.q3Yes, "TOPRIGHT", CARD_GUTTER, 0)
    protection.q3Yes:Refresh()
    protection.q3No:Refresh()
    y = y - CARD_HEIGHT - 8

    -- The field rides on the right of its own label rather than at a fixed
    -- offset: the sentence is not the same length in the two locales, and a
    -- number picked for one of them cuts the other.
    protection.q3IntervalLabel:ClearAllPoints()
    protection.q3IntervalLabel:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y - 6)
    protection.q3Interval:ClearAllPoints()
    protection.q3Interval:SetPoint("LEFT", protection.q3IntervalLabel, "RIGHT", 10, 0)
    protection.q3Interval:Refresh()
    y = y - ROW_HEIGHT - 4

    protection.q3Note:SetText(covered and L["ANTISPAM_COVERED"] or L["ANTISPAM_NOTE"])
    protection.q3Note:SetTextColor(unpack(covered and C.orange or C.dim))
    protection.q3Note:ClearAllPoints()
    protection.q3Note:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    -- Measured rather than assumed: the note wraps over one line at 900 px and
    -- over three at 500, and everything below it hangs from this number.
    y = y - math.max(16, protection.q3Note:GetStringHeight() or 16) - BLOCK_GAP

    protection.q4Number:ClearAllPoints()
    protection.q4Number:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y - 4)
    y = y - Q_TITLE_ROW
    -- The first card is placed against the screen, the two others against the
    -- card before them -- the shape questions 1 and 2 already have. Placed at
    -- `PAD + index * (thirdWidth + CARD_GUTTER)` they carried a copy of the
    -- width inside their own position, so the width pass could not widen them
    -- without moving them too, and the same layout would have been written a
    -- second time. Chained, widening a card carries the next one along, and the
    -- width itself is `applyTabWidth.protection`'s, above, for every screen.
    local previous = nil
    for _, key in ipairs({ "silent", "minimal", "verbose" }) do
        local card = protection.q4[key]
        card:ClearAllPoints()
        if previous then
            card:SetPoint("TOPLEFT", previous, "TOPRIGHT", CARD_GUTTER, 0)
        else
            card:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
        end
        card:Refresh()
        previous = card
    end
    y = y - CARD_HEIGHT - BLOCK_GAP

    protection.q5Number:ClearAllPoints()
    protection.q5Number:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y - 4)
    y = y - Q_TITLE_ROW
    protection.tileAllowed:ClearAllPoints()
    protection.tileAllowed:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD, y)
    protection.tileBlocked:ClearAllPoints()
    protection.tileBlocked:SetPoint("TOPLEFT", protection.tileAllowed, "TOPRIGHT", CARD_GUTTER, 0)

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
    y = y - 40

    -- Read again, from the name still in the field. The answer is a read of the
    -- two lists and this is the pass every write ends on -- adding a name,
    -- removing one, undoing, closing the drawer -- so a tested pseudo used to
    -- keep an answer the lists had stopped agreeing with, and the only way to
    -- see the new one was to add or remove a letter.
    if protection.testInput and ns.RefreshTestAnswer then
        ns.RefreshTestAnswer(protection.testInput:GetText())
    end

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
        -- A folded entry is as recent as its LAST occurrence, not as its first:
        -- sorted on `t` alone, somebody who repeated the same line all evening
        -- sank to the bottom of the list while they were still at it.
        local last = math.max(entry.t or 0, entry.t2 or 0)
        if last > group.lastTime then group.lastTime = last end
        group.occurrences = (group.occurrences or 0) + (tonumber(entry.count) or 1)
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
        local line = escape(ns.getLogEntryDisplayDate(entry))
            .. " | " .. escape(ns.getLogEntryDisplayType(entry))
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

-- The Journal's two boxes, and where the second one goes. `showMsg` sat at a
-- fixed PAD + 320 whatever the window measured, and `newCheck` gives a label no
-- width of its own: at the 500 px bound the room is 464, the box starts 320 in
-- and its label 346 in, which leaves 118 px for a sentence that needs some two
-- hundred and seventy. The right half simply left the ScrollFrame, which cut it
-- -- and nothing here scrolls sideways to go and read it. So the row is decided
-- from the width the window has NOW, in `applyTabWidth.journal`, and the list
-- below gives back what the second row takes so the three buttons under it never
-- move.
local SHOW_MSG_X = 320
-- The box, then the gap `newCheck` leaves between a box and its label.
local CHECK_LABEL_GAP = 18 + 8
local JOURNAL_ROW_ONE, JOURNAL_ROW_TWO = -30, -52
local JOURNAL_LIST_TOP, JOURNAL_LIST_HEIGHT = -60, 300
local JOURNAL_ROW_DROP = JOURNAL_ROW_ONE - JOURNAL_ROW_TWO

local function buildJournalTab(parent)
    journal.frame = parent
    local width = innerWidth()
    journal.header = newLabel(parent, L["LOGS_HEADER"], FONT_SECTION, C.ink)
    journal.header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, 0)
    journal.count = newLabel(parent, "", FONT_BODY, C.dim)
    journal.count:SetPoint("LEFT", journal.header, "RIGHT", 10, 0)

    journal.enable = newCheck(parent, "SanctuaryJournalEnable", L["LOGS_ENABLE"],
        L["TIP_LOGS_ENABLE"],
        function() return SanctuaryDB and SanctuaryDB.logging.enabled == true end,
        function(value) SanctuaryDB.logging.enabled = value end)
    journal.enable:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, JOURNAL_ROW_ONE)

    journal.showMsg = newCheck(parent, "SanctuaryJournalShowMessages", L["LOGS_SHOW_MSG"], nil,
        function() return SanctuaryDB and SanctuaryDB.uiSettings.showMessageColumn == true end,
        function(value) SanctuaryDB.uiSettings.showMessageColumn = value end)
    journal.showMsg:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + SHOW_MSG_X, JOURNAL_ROW_ONE)

    journal.scroll = newScroll(parent, "SanctuaryJournalScroll", width, JOURNAL_LIST_HEIGHT)
    journal.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, JOURNAL_LIST_TOP)
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
        row.label = newLabel(row, "", FONT_BODY, C.soft)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    -- On every acquisition, not only on creation: a pooled row kept the width of
    -- the window it was first drawn in, so after a resize the clickable strip of
    -- a group header was the old width -- too short to click at the right of a
    -- widened window, and sticking out of a narrowed one.
    row:SetSize(innerWidth() - 10, 18)
    row:SetParent(parent)
    row:Show()
    journal.rows[#journal.rows + 1] = row
    return row
end

-- The list and the rows already drawn in it. `acquireJournalRow` covers the rows
-- the factory hands out AFTER a resize; the ones already on screen are the ones
-- a person is looking at while the grip moves, and they kept the width of the
-- window they were drawn in -- 734 px of clickable strip inside a 464 px screen.
applyTabWidth.journal = function()
    if not journal.scroll then return end
    local width = innerWidth()
    -- One row or two, from the room there is. The label is measured rather than
    -- guessed: the two locales do not write the same sentence, and the bound
    -- that matters is the one the window is at.
    local labelWidth = journal.showMsg.label:GetStringWidth() or 0
    local sameRow = SHOW_MSG_X + CHECK_LABEL_GAP + labelWidth <= width
    journal.showMsg:ClearAllPoints()
    journal.showMsg:SetPoint("TOPLEFT", journal.frame, "TOPLEFT",
        sameRow and (PAD + SHOW_MSG_X) or PAD,
        sameRow and JOURNAL_ROW_ONE or JOURNAL_ROW_TWO)
    -- What the second row takes, the list gives back: it starts lower AND ends
    -- at the same place, so the Clear / Copy / Expand row anchored under it stays
    -- where it is and the screen keeps the height it reports.
    local drop = sameRow and 0 or JOURNAL_ROW_DROP
    journal.scroll:ClearAllPoints()
    journal.scroll:SetPoint("TOPLEFT", journal.frame, "TOPLEFT", PAD, JOURNAL_LIST_TOP - drop)
    journal.scroll:SetViewportSize(width, JOURNAL_LIST_HEIGHT - drop)
    -- The pool as well as the live rows: a pooled row is handed out with the
    -- current width, but it is still a frame carrying a size, and leaving stale
    -- ones behind would make "no row is wider than the screen" true only for the
    -- rows that happen to be visible.
    for _, list in ipairs({ journal.rows, journal.rowPool }) do
        for _, row in ipairs(list) do row:SetWidth(width - 10) end
    end
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
        -- What the header counts is how many times this person was blocked, not
        -- how many lines the list holds: a folded entry stands for several.
        row.label:SetText((expanded and "v " or "> ")
            .. string.format(L["LOGS_GROUP_HEADER"], group.name,
                group.data.occurrences or #group.data.entries)
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
                local text = ns.getLogEntryDisplayDate(entry) .. "   "
                    .. ns.getLogEntryDisplayType(entry)
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

-- Advanced keeps what a person only ever opens on purpose: diagnostics, the
-- journal's size, the minimap button and the technical line. Automatic trust
-- left for the home screen -- it says who is allowed, which is the one question
-- the first screen exists to answer.
local function buildAdvancedTab(parent)
    local width = innerWidth()
    local y = 0

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
        if value then
            SanctuaryDB.logging.maxEntries =
                math.floor(math.max(100, math.min(20000, value)))
        end
        -- Rewritten from what is stored, whether the number was taken or
        -- refused. The field reports a setting: left empty it reads as "no
        -- limit", and left holding a refused number it reports a limit nobody
        -- saved.
        advanced.maxInput:SetText(tostring(SanctuaryDB.logging.maxEntries or 5000))
        advanced.maxInput:RefreshHint()
        if ns.refreshUI then ns.refreshUI() end
    end, true)
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

-- The three section rules, the debug paragraph and the technical line: all five
-- were measured once, at build time, against a 780 px window. A section rule is
-- the widest thing on the screen and the paragraph is the one that wraps, so at
-- 500 px they were what hung outside the window, and at 900 what left a strip of
-- it empty. The 26 px indent is the debug paragraph's own -- it sits under the
-- checkbox's label, not at the margin.
applyTabWidth.advanced = function()
    if not advanced.status then return end
    local width = innerWidth()
    for _, section in ipairs({ advanced.diagSection, advanced.journalSection,
        advanced.minimapSection }) do
        section:SetSectionWidth(width)
    end
    advanced.debugDesc:SetWidth(math.max(60, width - 26))
    advanced.status:SetWidth(width)
    advanced.maxInput:RefreshNoteWidth()
end

refreshTab.advanced = function()
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

-- The column the presentation paragraph is set in, centred. It is a reading
-- width and not a share of the window -- a centred sentence running the whole of
-- a 900 px window reads worse, not better -- so it is a constant, capped by
-- whatever the window actually has: at the narrowest width the two are four
-- pixels apart, and nothing but the cap says which of them wins.
local ABOUT_TEXT_WIDTH = 460

local function aboutTextWidth() return math.min(ABOUT_TEXT_WIDTH, innerWidth()) end

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
    about.desc:SetWidth(aboutTextWidth())
    y = y - 60
    about.author = newLabel(parent, string.format(L["ABOUT_AUTHOR"], "Zephos"),
        FONT_BODY, C.dim, "CENTER")
    about.author:SetPoint("TOP", parent, "TOP", 0, y)
    y = y - 24
    about.github = newLabel(parent,
        string.format(L["ABOUT_GITHUB"], "github.com/VincentCassiau/Sanctuary"),
        FONT_BODY, C.dim, "CENTER")
    about.github:SetPoint("TOP", parent, "TOP", 0, y)
    about.height = -y + 24
end

applyTabWidth.about = function()
    if not about.desc then return end
    about.desc:SetWidth(aboutTextWidth())
end

-- What it drew, like every other screen, rather than the floor: the floor is
-- `applyHeight`'s job and applying it here as well hid the top padding's cost
-- inside a number that was already too big.
refreshTab.about = function()
    return about.height or MIN_HEIGHT
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
    local width = innerWidth()
    diagnostics.argInputs = {}
    diagnostics.header = newLabel(parent, L["DIAG_PANEL_HEADER"], FONT_SECTION, C.ink)
    diagnostics.header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, 0)

    diagnostics.runAllBtn = newButton(parent, nil, L["DIAG_RUN_ALL"], 260, 24, function()
        diagnosticResults = {}
        for _, entry in ipairs(ns.DIAGNOSTIC_CATALOG) do
            -- Skipped on a bulk run: the one that writes a real Battle.net name
            -- into the log, the two sounds, which are checked one by one, and the
            -- spam probe, whose shown copy is printed into the chat -- the batch
            -- must leave nothing on screen and nothing in the ear.
            if ns.isBulkDiagnostic(entry) then
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
            -- Kept so the width pass can reach them: they are made in a loop and
            -- nothing else on the screen holds a reference.
            diagnostics.argInputs[#diagnostics.argInputs + 1] = input
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

-- The results column keeps its distance from the list beside it: the list starts
-- at PAD and is 320 wide, the column at PAD + 330, so the column gets the inner
-- width less 340, and the text inside it 10 less again -- the same two numbers
-- the screen was built with.
applyTabWidth.diagnostics = function()
    if not diagnostics.resultScroll then return end
    local width = innerWidth()
    diagnostics.resultScroll:SetViewportSize(width - 340,
        diagnostics.resultScroll:GetHeight())
    if diagnostics.resultText then
        diagnostics.resultText:SetWidth(math.max(60, width - 350))
    end
    for _, input in ipairs(diagnostics.argInputs or {}) do input:RefreshNoteWidth() end
    -- What the child measured was measured against the old width: a result that
    -- wrapped over two lines at 540 wraps over four at 124, and the bar and the
    -- wheel read that height.
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

-- What a chip spends on anything that is not its name: 8 px of left inset, a
-- 4 px gap, the 16 px cross and its 4 px margin. The label gets what is left,
-- and never a pixel of it.
local CHIP_CHROME = 32

local function layoutChips(parent, entries, startY, onRemove)
    local x, y = 0, startY
    local maxWidth = panelWidth() - 40
    for _, item in ipairs(entries) do
        local chip = newChip(parent)
        activeChips[#activeChips + 1] = chip
        -- Measured, not counted. The width used to be `24 + #label * 7`: a byte
        -- count on a UTF-8 string, at a made-up seven pixels a character, then
        -- clamped to the row -- so a long pseudo got a chip too narrow for its
        -- own text and the cross, pinned to the right edge, sat on the letters.
        -- Asking the FontString how wide it renders is the only measure that
        -- cannot disagree with what is drawn; the cross keeps its room whatever
        -- the answer, and the label is cut to what is left.
        chip.label:SetWidth(0)
        chip.label:SetText(item.label)
        local textWidth = math.ceil(chip.label:GetStringWidth() or 0)
        local roomForText = math.max(20, maxWidth - CHIP_CHROME)
        local shown = math.min(textWidth, roomForText)
        chip.label:SetWidth(shown)
        local width = shown + CHIP_CHROME
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

-- The name first, then where it came from. A chip is cut to the width of its
-- row, and since decision 119 every character on one carries its realm as well
-- -- the two together are what runs past the edge. The tooltip is where the
-- whole of it can be read, so it says the name in full before saying anything
-- about it. No sentence to translate: a name is a name in both languages.
local function describeChipSource(data, label)
    local parts = {}
    if type(label) == "string" and label ~= "" then parts[#parts + 1] = label end
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

-- What the panel keeps for its own heading, above and below the list.
-- The list inside a panel stops clear of the undo strip instead of running under
-- it. The strip only shows for six seconds after a removal, so reclaiming those
-- pixels the rest of the time would mean re-laying out the list every time a
-- name is taken out -- and a list that jumps under the cursor is a worse trade
-- than a list one row shorter. Derived from the strip rather than copied, so
-- moving the strip cannot leave the panel quietly overlapping it again.
local PANEL_SCROLL_TOP = 44
local PANEL_SCROLL_BOTTOM = UNDO_HEIGHT + UNDO_MARGIN + 6

-- The panels and their veil are as tall as the frame under its header, whatever
-- the window currently measures. The anchors say so to the client, which follows
-- the grip pixel by pixel; the explicit height says the same number out loud, so
-- the list inside knows how much room it has been given -- and so a check can
-- read it back without a screenshot.
local function applyPanelViewport(frameHeight)
    local height = math.max(120, (frameHeight or MIN_FRAME_HEIGHT) - HEADER_HEIGHT)
    if panelVeil then panelVeil:SetSize(frameWidth, height) end
    for _, panel in pairs(panels) do
        if type(panel) == "table" and panel.SetHeight then
            panel:SetHeight(height)
            panel:SetWidth(panelWidth())
            if panel.scroll and panel.scroll.SetViewportSize then
                panel.scroll:SetViewportSize(panelWidth() - 24,
                    height - PANEL_SCROLL_TOP - PANEL_SCROLL_BOTTOM)
            end
            -- What the panel drew was measured against the old width. Forcing a
            -- redraw is the whole of the width change for a list: the chips
            -- rewrap, the sentences rewrap, and the signature is what would
            -- otherwise decide nothing had happened.
            panel.signature = nil
        end
    end
end

local function newPanelFrame(name, titleText)
    local panel = CreateFrame("Frame", name, mainFrame, "BackdropTemplate")
    panel:SetWidth(panelWidth())
    panel:SetHeight(MIN_FRAME_HEIGHT - HEADER_HEIGHT)
    -- Two anchors, not a size: the panel runs from the bottom of the header to
    -- the bottom of the frame. Anchored on the top corner alone it kept the 400
    -- pixels it was built with, and the rest of the window stayed uncovered --
    -- and clickable -- underneath it.
    panel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, -HEADER_HEIGHT)
    panel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    panel:SetFrameLevel(LEVEL_PANEL)
    -- The panel has to eat its own clicks now that the veil closes on one:
    -- without this, a click on any empty part of the drawer falls through to the
    -- veil below it and shuts the very list the person is reading.
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    applyBackdrop(panel, C.panel, C.border, 2)
    panel:Hide()

    panel.back = newButton(panel, nil, L["PANEL_BACK"], 90, 22, function() ns.ClosePanel() end)
    panel.back:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title = newLabel(panel, titleText, FONT_TITLE, C.ink)
    panel.title:SetPoint("LEFT", panel.back, "RIGHT", 12, 0)
    panel.count = newLabel(panel, "", FONT_DESC, C.accent)
    panel.count:SetPoint("LEFT", panel.title, "RIGHT", 10, 0)

    panel.scroll = newScroll(panel, name .. "Scroll", panelWidth() - 24,
        MIN_FRAME_HEIGHT - HEADER_HEIGHT - PANEL_SCROLL_TOP - PANEL_SCROLL_BOTTOM)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -PANEL_SCROLL_TOP)
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

    -- The automatic groups go in by identity, not by headcount. A guild member
    -- replaced at constant strength, or a Battle.net friend who logs in and
    -- changes the character half of his line, moves nothing the totals can see,
    -- so a signature built on counts alone leaves the panel showing a roster
    -- that no longer exists. Reading the very groups the panel draws is what
    -- keeps them in step.
    local auto = {}
    for _, group in ipairs(ns.getAutoWhitelistGroups()) do
        auto[#auto + 1] = group.source .. ":" .. group.total
        for _, entry in ipairs(group.entries) do
            auto[#auto + 1] = entry.character and (entry.key .. "/" .. entry.character)
                or entry.key
        end
    end
    parts[#parts + 1] = table.concat(auto, ",")

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

-- Which sentence answers which refusal. The interface picks a wording from the
-- code the writers hand back; it never decides on its own what is refusable, so
-- a rule can only ever change in one place.
-- The Battle.net sentence has two halves and two audiences. Where somebody is
-- being told they cannot block an account, both are said: the second half is the
-- way out, and a refusal with no way out is half an answer. Where the list of
-- Battle.net friends is merely being labelled -- the allowed panel -- the first
-- half is the whole of it: "vu que c'est pas pour bloquer ici", decision 102.
-- One wording, split at the sentence, rather than two strings to keep in step.
local function bnetNotBlockedFull()
    return L["BNET_NOT_BLOCKED"] .. " " .. L["BNET_NOT_BLOCKED_HOW"]
end

local REFUSAL_TEXT = {
    name = function() return L["REFUSED_NAME"] end,
    account = bnetNotBlockedFull,
    pattern = function() return L["REFUSED_PATTERN"] end,
}

-- The one submission path for the three field-and-button pairs. There were six
-- bodies -- one on Enter and one on the button, per pair -- doing the same
-- things, which is this release's whole subject, in this file: two paths that
-- have to be corrected twice. Adding the refusal line to six of them is exactly
-- the mistake the release is about.
local function submitEntry(box, addFn)
    local text = box:GetText()
    box:SetText("")
    box:RefreshHint()
    local ok, key, _, refusal, displaced = addFn(text)
    local sentence = refusal and REFUSAL_TEXT[refusal]
    if sentence then box:SayNo(sentence()) else box:ClearNote() end
    if ok then offerDisplacedUndo(key, displaced) end
    if ok and ns.refreshUI then ns.refreshUI() end
end

local function buildAllowedPanel()
    local panel = newPanelFrame("SanctuaryPanelAllowed", L["TILE_ALLOWED"])
    panels.allowed = panel
    panels.allowedExpanded = {}

    local child = panel.scroll.child
    panel.addedSection = newSection(child, L["PANEL_ADDED_BY_YOU"], nil, panelWidth() - 40)
    panel.addedSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)

    panel.addInput = newInput(child, "SanctuaryAllowedAddInput", 250, L["PANEL_ADD_NAME_HINT"],
        function() submitEntry(panel.addInput, ns.addAllowed) end)
    panel.addBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        submitEntry(panel.addInput, ns.addAllowed)
    end)

    panel.autoSection = newSection(child, L["PANEL_AUTO_TITLE"], nil, panelWidth() - 40)
    panel.groupNote = newLabel(child, L["WL_GROUP_NOTE"], FONT_BODY, C.dim)
    panel.groupNote:SetWidth(panelWidth() - 40)
    panel.autoRows = {}
    panel.autoRowPool = {}
    panel.signature = nil
    return panel
end

local function acquireAutoRow(parent, panel)
    local row = table.remove(panel.autoRowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetSize(panelWidth() - 44, 18)
        row.label = newLabel(row, "", FONT_BODY, C.soft)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    row:SetParent(parent)
    -- Rows are pooled and a hint row leaves a wrapping width behind it. Reset
    -- both here, once, rather than at every call site: a header that inherited a
    -- width would wrap its own name.
    row:SetHeight(18)
    row.label:SetWidth(0)
    row:Show()
    panel.autoRows[#panel.autoRows + 1] = row
    return row
end

local AUTO_GROUP_LABELS = {
    bnet = "WL_SOURCE_BNET", friend = "WL_SOURCE_FRIEND",
    guild = "WL_SOURCE_GUILD", trust = "WL_SOURCE_TRUST",
}

-- One line under the group header, for the two groups whose rule is not obvious
-- from their name: automatic trust has a condition, and Battle.net has a limit
-- that has to be said where somebody would go looking to block one of them.
-- Shown only while the group is unfolded, decision 102: four headers with two
-- paragraphs wedged between them is not a list of four counts, which is what the
-- folded state exists to be. The Battle.net one is the short half of the
-- sentence here -- nothing on this panel blocks anybody.
local AUTO_GROUP_HINTS = {
    trust = "WL_TRUST_HINT",
    bnet = "BNET_NOT_BLOCKED",
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

    -- The drawer follows the window, so everything measured against it is handed
    -- the current width on every redraw. Built once at the opening width, the
    -- rules and the wrapped sentences kept it.
    panel.addedSection:SetSectionWidth(panelWidth() - 40)
    panel.autoSection:SetSectionWidth(panelWidth() - 40)
    panel.groupNote:SetWidth(panelWidth() - 40)
    panel.addInput:RefreshNoteWidth()

    -- "Added by you": the manual entries, as chips. Automatically trusted
    -- contacts sit in the same table with source = "trust" and get their own
    -- group further down, so they are excluded here: listing them twice would
    -- show the tester the same name in two places and count as typed by hand
    -- someone she never typed.
    local manual = {}
    for key, data in pairs(SanctuaryDB.manualWhitelist or {}) do
        if type(data) ~= "table" or data.source ~= "trust" then
            -- Read off the key, never off what was typed: the key is what the
            -- decision matches on, so a chip saying "Kadaj" where the entry only
            -- covers Kadaj-Ysondre would be the panel telling the reader
            -- something the add-on does not do (decision 119).
            local label = ns.qualifiedDisplayName(key,
                type(data) == "table" and data.displayName or nil) or key
            manual[#manual + 1] = {
                key = key,
                label = label,
                tooltip = describeChipSource(data, label),
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
    -- NOTE_ROOM is kept whether a sentence is showing or not, the same choice the
    -- undo strip made: a line that appears must not push the list down under the
    -- fingers of somebody about to click a cross. One line here: this field only
    -- ever answers REFUSED_NAME, which fits a line at the note width in both
    -- languages.
    y = y - 40 - NOTE_ROOM

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
            trustEntries[#trustEntries + 1] = {
                key = key,
                label = ns.qualifiedDisplayName(key, data.displayName) or key,
                data = data,
            }
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

        local hintKey = expanded and AUTO_GROUP_HINTS[source]
        if hintKey then
            local hint = acquireAutoRow(child, panel)
            hint:ClearAllPoints()
            hint:SetPoint("TOPLEFT", child, "TOPLEFT", 16, y)
            hint.label:SetTextColor(unpack(C.dim))
            -- Wrapped, then measured. Both hints ran past the right edge of the
            -- panel on one line, in French first, so they wrap; how many lines
            -- that takes is the client's answer and not a constant here -- the
            -- Battle.net one is a single sentence now and the trust one is not.
            hint.label:SetWidth(panelWidth() - 76)
            hint.label:SetText(L[hintKey])
            local hintHeight = math.max(18, math.ceil(hint.label:GetStringHeight() or 18))
            hint:SetHeight(hintHeight)
            y = y - hintHeight - 6
        end

        if expanded then
            if source == "trust" then
                local chips = {}
                for _, item in ipairs(trustEntries) do
                    chips[#chips + 1] = {
                        key = item.key, label = item.label,
                        tooltip = describeChipSource(item.data, item.label),
                        data = item.data,
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
                            -- The add-on's own "active" green, the one the
                            -- header wears when protection is on: these are the
                            -- friends who are there right now.
                            row.label:SetTextColor(unpack(C.green))
                            row.label:SetText(string.format(L["WL_BNET_ROW"],
                                entry.characterDisplay or entry.character,
                                entry.account or entry.label))
                        else
                            row.label:SetTextColor(unpack(C.dim))
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
    panel.desc:SetWidth(panelWidth() - 40)

    -- Said here, where somebody types a name in: the blocked list holds WoW
    -- characters, and Battle.net is cut in Battle.net. Without the line the only
    -- way to learn it is to add a friend's account and watch nothing happen.
    panel.bnetNote = newLabel(child, bnetNotBlockedFull(), FONT_BODY, C.dim)
    panel.bnetNote:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -32)
    panel.bnetNote:SetWidth(panelWidth() - 40)

    panel.namesSection = newSection(child, L["PANEL_BLOCKED_NAMES"], nil, panelWidth() - 40)
    panel.nameInput = newInput(child, "SanctuaryBlockedAddInput", 250, L["PANEL_ADD_NAME_HINT"],
        function() submitEntry(panel.nameInput, ns.addBlocked) end)
    panel.nameBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        submitEntry(panel.nameInput, ns.addBlocked)
    end)

    panel.patternsSection = newSection(child, L["PANEL_BLOCKED_PATTERNS"],
        L["PANEL_PATTERNS_DESC"], panelWidth() - 40)
    panel.patternInput = newInput(child, "SanctuaryPatternAddInput", 250, L["PANEL_PATTERN_HINT"],
        function() submitEntry(panel.patternInput, ns.addPattern) end)
    panel.patternBtn = newButton(child, nil, L["PANEL_ADD_BTN"], 90, 24, function()
        submitEntry(panel.patternInput, ns.addPattern)
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

    panel.desc:SetWidth(panelWidth() - 40)
    panel.bnetNote:SetWidth(panelWidth() - 40)
    panel.namesSection:SetSectionWidth(panelWidth() - 40)
    panel.patternsSection:SetSectionWidth(panelWidth() - 40)
    panel.nameInput:RefreshNoteWidth()
    panel.patternInput:RefreshNoteWidth()

    -- -40 before the Battle.net line was added under the description.
    local y = -72
    panel.namesSection:ClearAllPoints()
    panel.namesSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.namesSection.count:SetText("(" .. tostring(counts.blocked.names) .. ")")
    y = y - 34

    panel.nameInput:ClearAllPoints()
    panel.nameInput:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.nameBtn:ClearAllPoints()
    panel.nameBtn:SetPoint("LEFT", panel.nameInput, "RIGHT", 8, 0)
    -- Two lines here, and only here: this is the one field that can answer with
    -- the Battle.net sentence, which is longer than a line at the note width in both
    -- languages. What sits at the y below is the first row of chips, which a
    -- second line would lie over.
    y = y - 34 - NOTE_ROOM_TWO_LINES

    local names = {}
    for key, data in pairs(SanctuaryDB.blockedNames or {}) do
        -- Same rule as the allowed panel: the realm has been in the key since
        -- 1.0.0, and showing the bare pseudo let a person read "Toto" on the
        -- list while the entry only ever blocked the Toto of one realm.
        local label = ns.qualifiedDisplayName(key,
            type(data) == "table" and data.displayName or nil) or key
        names[#names + 1] = {
            key = key,
            label = label,
            tooltip = describeChipSource(data, label),
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
    -- One line: this field only ever answers REFUSED_PATTERN, a BattleTag pasted
    -- here included, and that sentence fits a line at the note width in both
    -- languages.
    y = y - 34 - NOTE_ROOM

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
    closeOpenDropdown()
    ns.ClosePanel()
    openPanel = which
    local panel = panels[which]
    if not panel then return end
    -- The window may have been resized while no panel was open: take its height
    -- now rather than trusting the one left over from the last opening.
    applyPanelViewport(mainFrame:GetHeight())
    if panelVeil then panelVeil:Show() end
    panel:Show()
    panel.signature = nil
    if refreshStateButton then refreshStateButton() end
    refreshOpenPanel(true)
    -- Created on opening, cancelled on closing. A ticker that outlives its panel
    -- keeps rebuilding a list nobody is looking at, for the whole session.
    listTicker = C_Timer.NewTicker(LIST_REFRESH_SECONDS, function()
        refreshOpenPanel(false)
    end)
end

function ns.ClosePanel()
    local wasOpen = openPanel ~= nil
    if listTicker then
        listTicker:Cancel()
        listTicker = nil
    end
    for _, panel in pairs(panels) do
        if type(panel) == "table" and panel.Hide then panel:Hide() end
    end
    if panelVeil then panelVeil:Hide() end
    openPanel = nil
    if refreshStateButton then refreshStateButton() end
    releaseChips()
    -- The screen underneath has just had its lists changed under it: the tiles
    -- count, and the tester answers, from what the drawer left behind.
    if wasOpen and ns.refreshUI then ns.refreshUI() end
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
        -- Through the core, never `wipe` from here: what the Journal merges on
        -- is an index the core keeps, and emptying the list without it would
        -- leave entries nobody can reach still collecting occurrences.
        ns.clearJournal()
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

function refreshStateButton()
    if not stateButton then return end
    local on = ns.isEnabled()
    stateButton.label:SetText(on and L["HEADER_STATE_ON"] or L["HEADER_STATE_OFF"])
    stateButton.label:SetTextColor(unpack(on and C.green or C.dim))
    applyBackdrop(stateButton, on and C.greenBg or C.tabOff, on and C.green or C.border)
    -- The veil starts under the header, so that the close cross stays reachable
    -- while a panel is open. That left the one control up there reachable too,
    -- and it is not a small one: a click turns the whole protection off, from
    -- behind a panel that goes on listing names as if it were still on. The
    -- click is refused below; the dimming is what says so before the click.
    stateButton:SetAlpha(openPanel and 0.35 or 1)
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
        local current = (def.key == activeTab)
        -- `.tab.on { margin-top:-2px; padding-top:6px }`: the current tab starts
        -- TAB_LIFT higher and is that much taller, so both rows keep the same
        -- bottom edge and the current one alone climbs over the frame's border.
        -- That overlap is what "fusionne avec le cadre" is made of; every tab
        -- was drawn at the same y before, so the strip read as four buttons
        -- under the window and told nobody where they were.
        btn:SetSize(width, current and (TAB_HEIGHT + TAB_LIFT) or TAB_HEIGHT)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", x, current and TAB_LIFT or 0)
        x = x + width + 2
        applyBackdrop(btn, current and C.panel or C.tabOff, C.border)
        btn.label:SetTextColor(unpack(current and C.ink or C.dim))
        -- `border-top:0` on both, drawn rather than removed: a backdrop has four
        -- sides. The current tab hides its top edge under the panel's own fill,
        -- which is the same colour as the window above it, so the two meet with
        -- no line between them.
        if current then btn.merge:Show() else btn.merge:Hide() end
        -- `box-shadow: inset 0 -2px 0 accent`.
        if current then btn.underline:Show() else btn.underline:Hide() end
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
-- The width the window should be at right now: the remembered one or the design
-- default, clamped to the bounds. Resolved on its own, and BEFORE anything
-- measures itself against it -- a screen laid out before the window has taken
-- its new width is a screen laid out at the old one, which then floats in a
-- wider frame or spills out of a narrower one.
--
-- SavedVariables is the source of truth, not a copy made at build time: the
-- schema reset clears it, and a stale copy would keep applying a size the
-- settings no longer hold.
local function resolveWidth()
    manualSize = SanctuaryDB and SanctuaryDB.uiSize or nil
    local width = (manualSize and manualSize[1]) or DEFAULT_WIDTH
    return math.min(MAX_FRAME_WIDTH, math.max(MIN_FRAME_WIDTH, width))
end

local function applyViewport(frameHeight, width)
    if not contentScroll or not contentFrame then return end
    -- The live width, taken before anything measures itself: `innerWidth` and
    -- `panelWidth` read it, and the whole point of the pass is that they answer
    -- for the window as it is now, not as it opened.
    frameWidth = math.min(MAX_FRAME_WIDTH,
        math.max(MIN_FRAME_WIDTH, width or frameWidth))
    local viewport = math.max(120, (frameHeight or MIN_FRAME_HEIGHT) - HEADER_HEIGHT - CONTENT_BOTTOM)
    contentScroll:SetSize(frameWidth, viewport)
    local contentHeight = math.max(fittedNeed, viewport)
    contentFrame:SetWidth(frameWidth)
    contentFrame:SetHeight(contentHeight)
    for _, frame in pairs(tabFrames) do frame:SetWidth(frameWidth) end
    local active = tabFrames[activeTab]
    if active then active:SetHeight(contentHeight) end
    if undoLine then undoLine:SetWidth(innerWidth()) end
    -- And what lives INSIDE a screen. Nothing above reaches it: this pass hands
    -- the live width to the frame, the content area, the five screens, the
    -- drawer and the undo strip, and stopped there -- so every width a screen
    -- derived at build time stayed at the 744 px of a 780 px window. Dragged
    -- down to 500, a section rule, a paragraph, a Journal row and the results
    -- column hung up to two hundred and eighty pixels outside the window, with
    -- nothing to scroll sideways to reach them (there is no horizontal scrolling
    -- here, by design); dragged out to 900, they left the room they had been
    -- given empty. A6 asks the columns to share the width between 500x380 and
    -- 900x700.
    --
    -- Every screen, not the one on show: a hidden screen is one tab click away,
    -- and neither a tab change nor a refresh would have caught it -- the widths
    -- below are posted once, at build time, and nothing else ever revisits them.
    for _, applyWidth in pairs(applyTabWidth) do applyWidth() end
    contentScroll:RefreshBar()
    -- The panels are not inside the content area, so nothing above resizes them:
    -- they answer to the window itself, on the same pass.
    applyPanelViewport(frameHeight)
end

local function applyHeight(height)
    if not mainFrame then return end
    -- `resolveWidth` refreshes `manualSize` from SavedVariables on the way past,
    -- which is what the height below reads too.
    local width = resolveWidth()
    local needed = math.max(MIN_HEIGHT, height or MIN_HEIGHT)
    fittedNeed = needed
    local frameHeight
    if manualSize then
        -- A settings file written before the bounds existed -- or before the
        -- width was ever applied -- can carry anything at all, so this is
        -- clamped exactly like the width.
        frameHeight = manualSize[2] or MIN_FRAME_HEIGHT
        frameHeight = math.min(MAX_FRAME_HEIGHT, math.max(MIN_FRAME_HEIGHT, frameHeight))
    else
        local bounded = math.min(MAX_HEIGHT, needed)
        frameHeight = bounded + HEADER_HEIGHT + CONTENT_BOTTOM
    end
    mainFrame:SetSize(width, frameHeight)
    applyViewport(frameHeight, width)
end

local function selectTab(key)
    if not isTabVisible(tabDefByKey(key)) then return end
    -- An open list belongs to the screen it was opened on: it draws over
    -- everything, so leaving it up would float eight durations over the Journal.
    closeOpenDropdown()
    -- Changing screen closes the panel rather than being refused: the tab strip
    -- hangs below the frame, so the veil cannot cover it, and of the two ways out
    -- of that -- close, or ignore the click -- closing is the one that never
    -- leaves a person clicking a live button that does nothing. A list of
    -- allowed names floating over the Journal is a state the design never had.
    ns.ClosePanel()
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
    -- The width first, before a single screen measures itself: `applyHeight`
    -- applies it further down, but by then the screen has already been drawn.
    frameWidth = resolveWidth()
    local height = MIN_HEIGHT
    local refresh = refreshTab[activeTab]
    if refresh then height = refresh() or MIN_HEIGHT end
    -- A screen answers with the height of what it drew, measured from its own
    -- top edge; the top padding the tab frames are offset by is not theirs to
    -- know about, and is added here, once.
    applyHeight(height + PAD)
    refreshOpenPanel(true)
end

local function clearTransientFields()
    closeOpenDropdown()
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
                    -- The sentence goes with the text it was about: reopening the
                    -- window on a refusal from a minute ago explains nothing.
                    if box.ClearNote then box:ClearNote() end
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
    mainFrame:SetSize(frameWidth, MIN_HEIGHT + HEADER_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    -- Both axes now, decision 98. Under pcall because SetResizeBounds is the
    -- Retail spelling and a missing method must not take the window down with it.
    pcall(mainFrame.SetResizeBounds, mainFrame,
        MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT, MAX_FRAME_WIDTH, MAX_FRAME_HEIGHT)
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
        -- Modal means modal. See refreshStateButton.
        if openPanel then return end
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

    contentScroll = newScroll(mainFrame, "SanctuaryContentScroll", frameWidth, MIN_HEIGHT)
    contentScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -HEADER_HEIGHT)
    contentFrame = contentScroll.child

    -- The content follows the window while the grip is being dragged, not only
    -- once it is released. `applyViewport` never resizes the window, so this
    -- cannot feed back into itself.
    mainFrame:SetScript("OnSizeChanged", function(self)
        applyViewport(self:GetHeight(), self:GetWidth())
    end)

    -- The veil takes the mouse and the wheel: the Cards and Checks behind an
    -- open panel must not be settings a person changes without seeing what they
    -- are doing. What it does with a click is close the panel -- decision 101,
    -- "fermer le drawer en cliquant sur l'ui principal" -- which is the one
    -- gesture everything else about a modal overlay already promises.
    panelVeil = CreateFrame("Frame", "SanctuaryPanelVeil", mainFrame, "BackdropTemplate")
    panelVeil:SetSize(frameWidth, MIN_FRAME_HEIGHT - HEADER_HEIGHT)
    panelVeil:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -HEADER_HEIGHT)
    panelVeil:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    panelVeil:SetFrameLevel(LEVEL_VEIL)
    applyBackdrop(panelVeil, C.veil, nil)
    panelVeil:EnableMouse(true)
    panelVeil:EnableMouseWheel(true)
    panelVeil:SetScript("OnMouseDown", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        ns.ClosePanel()
    end)
    panelVeil:SetScript("OnMouseUp", function() end)
    panelVeil:SetScript("OnMouseWheel", function() end)
    panelVeil:Hide()

    for _, def in ipairs(TAB_DEFS) do
        local frame = CreateFrame("Frame", "SanctuaryTabContent_" .. def.key, contentFrame)
        frame:SetSize(frameWidth, MIN_HEIGHT)
        -- `.content { padding:18px }`, once, for the five screens. Every screen
        -- used to start at the very top of the content area, so the first line
        -- of each -- "1 Qui peut vous contacter ?" among them -- was glued to
        -- the title bar with nothing between the two. Put here rather than in
        -- each build so no screen can be forgotten, and paid for once in
        -- `ns.refreshUI`, which is the only place that knows what a screen asked
        -- for.
        frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -PAD)
        frame:Hide()
        tabFrames[def.key] = frame

        local btn = CreateFrame("Button", "SanctuaryTab_" .. def.key, mainFrame, "BackdropTemplate")
        btn:SetSize(80, TAB_HEIGHT)
        btn.label = newLabel(btn, L[def.labelKey], FONT_DESC, C.dim, "CENTER")
        -- Centred on what is left once the underline has taken its two pixels,
        -- so the word does not sit visibly low in the current tab.
        btn.label:SetPoint("CENTER", btn, "CENTER", 0, 1)
        btn.merge = btn:CreateTexture(nil, "ARTWORK")
        btn.merge:SetHeight(TAB_LIFT)
        btn.merge:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, 0)
        btn.merge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, 0)
        btn.merge:SetColorTexture(unpack(C.panel))
        btn.merge:Hide()
        btn.underline = btn:CreateTexture(nil, "OVERLAY")
        btn.underline:SetHeight(TAB_LIFT)
        btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
        btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.underline:SetColorTexture(unpack(C.accent))
        btn.underline:Hide()
        local key = def.key
        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(key)
        end)
        tabButtons[def.key] = btn
    end

    -- The undo line sits above the tabs so it is visible whichever screen is up.
    undoLine = CreateFrame("Frame", "SanctuaryUndoLine", mainFrame, "BackdropTemplate")
    undoLine:SetSize(innerWidth(), UNDO_HEIGHT)
    undoLine:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", PAD, UNDO_MARGIN)
    undoLine:SetFrameLevel(LEVEL_OVER_PANEL)
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
    resizeGrip:SetFrameLevel(LEVEL_OVER_PANEL)
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
        manualSize = { mainFrame:GetWidth(), mainFrame:GetHeight() }
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

-- WoW runs Lua 5.1, where `math.atan` takes ONE argument: `math.atan(dy, dx)`
-- drops dx without a word and answers only the half circle atan covers, which is
-- why the button could be dragged through the right-hand side of the ring and no
-- further. `math.atan2` is the 5.1 spelling of the two-argument form; the
-- harness's modern Lua removed it and put the second argument back on
-- `math.atan`, so both spellings have to be reachable from here.
local atan2 = math.atan2 or math.atan

-- Pure, so the harness can prove it without a mouse: cursor position and the
-- minimap centre in, angle out.
function ns.minimapAngleFromPosition(cx, cy, px, py)
    local dx, dy = px - cx, py - cy
    if dx == 0 and dy == 0 then return 0 end
    local angle = math.deg(atan2(dy, dx))
    if angle < 0 then angle = angle + 360 end
    return angle
end

-- The default minimap is 140 wide, so its ring is 70 out from the centre.
local MINIMAP_DEFAULT_WIDTH, MINIMAP_MARGIN = 140, 10

-- Pure as well, and measured rather than assumed: the radius used to be a flat
-- 80, which is the default minimap's own 70 plus a margin. Edit Mode scales the
-- minimap, and on any minimap larger than the default 80 falls INSIDE the map --
-- the button sat over the terrain instead of around the ring, which is what the
-- session reported.
function ns.minimapRadius(minimapWidth)
    local width = tonumber(minimapWidth)
    if not width or width <= 0 then width = MINIMAP_DEFAULT_WIDTH end
    return width / 2 + MINIMAP_MARGIN
end

local function positionMinimapButton()
    if not minimapButton or not SanctuaryDB then return end
    local angle = math.rad(SanctuaryDB.minimap.angle or 220)
    local radius = ns.minimapRadius(Minimap and Minimap.GetWidth and Minimap:GetWidth())
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Where the cursor is, in minimap terms, written and applied at once. Called on
-- every frame while the button is dragged and once more at the release: the
-- button has to follow the cursor around the ring, not sit still and jump when
-- the mouse is let go.
local function dragMinimapButton()
    if not minimapButton or not SanctuaryDB or not Minimap then return end
    local cx, cy = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    -- The minimap's scale, not UIParent's. `GetCenter` answers in the minimap's
    -- own coordinates and `GetCursorPosition` answers in screen pixels, so the
    -- cursor has to come back through the scale of the frame it is compared to.
    -- The two are equal until the minimap is resized in Edit Mode, which is
    -- exactly when the button starts drifting away from the cursor mid-drag.
    local scale = Minimap:GetEffectiveScale() or 1
    if not (cx and cy and px and py) or scale == 0 then return end
    SanctuaryDB.minimap.angle = ns.minimapAngleFromPosition(cx, cy, px / scale, py / scale)
    positionMinimapButton()
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
        -- The handler installed on the drag IS the state: the flag that used to
        -- stand here was read by nothing, which is exactly why the button sat
        -- still until the mouse was let go.
        btn:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", dragMinimapButton)
        end)
        btn:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            dragMinimapButton()
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
    -- A player, or nothing. Right-clicking a shopkeeper offered "Sanctuary :
    -- toujours autoriser / toujours bloquer" about a name no invitation, no
    -- whisper and no duel can ever carry -- two entries that would write a dead
    -- record into a list and count it in a tile. Decision 113.
    --
    -- Only asked when there IS a unit: a name right-clicked in the chat or in a
    -- roster has no unit token and is a player by construction. Under pcall like
    -- the secret check above it, and failing open, because a menu entry that
    -- does not appear is worth less than an error in somebody's right-click.
    if contextData.unit and UnitIsPlayer then
        local ok, isPlayer = pcall(UnitIsPlayer, contextData.unit)
        if ok and not isPlayer then return nil end
    end
    local full = name
    if contextData.server and contextData.server ~= "" then
        full = name .. "-" .. contextData.server
    end
    if contextData.unit and UnitIsUnit and UnitIsUnit(contextData.unit, "player") then return nil end
    -- "Is this me" asked of the core, on the full name, realm included. The menu
    -- used to compare the bare pseudo under a fold of its own, which answered
    -- yes about anybody who happened to share the player's name on another
    -- realm: a real stranger, and the two entries the menu exists for were the
    -- ones missing from their right-click. That fold also covered A-Z and
    -- nothing more, so it missed an accented pseudo in the other direction.
    if ns.isSelf and ns.isSelf(full) then return nil end
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

    -- The key `ns.addAllowed` would write for this name, asked of the core --
    -- the same move the blocked half makes just below. The bare-pseudo rule this
    -- used to call is only half of it: an account allowed by hand is keyed
    -- whole, so a BattleTag looked up under its first word alone read as "not
    -- allowed", and the menu offered to allow somebody who already was.
    local allowedKey = ns.findAllowedKey and ns.findAllowedKey(name)
    local isAllowed = allowedKey and SanctuaryDB and SanctuaryDB.manualWhitelist
        and SanctuaryDB.manualWhitelist[allowedKey] ~= nil
    -- The core's own resolution, asked rather than reimplemented: whatever key
    -- shape the blocked list uses, the menu reads the same verdict the filters
    -- read. A second search written here once said "block" about somebody the
    -- core already held blocked, the click wrote a second key, and removing
    -- either of the two left the other one blocking.
    local blockedKey = ns.findBlockedKey and ns.findBlockedKey(name)
    local isBlocked = blockedKey ~= nil

    return {
        {
            text = isAllowed and L["MENU_UNALLOW"] or L["MENU_ALLOW"],
            action = function()
                if isAllowed then
                    ns.removeAllowed(allowedKey)
                else
                    -- The menu writes through the same two functions the panels
                    -- do, so it inherits the exclusivity rule and the Battle.net
                    -- refusal without a second copy of either. What it has to do
                    -- of its own is say what happened: there is no field here to
                    -- put a sentence under.
                    local ok, key, _, refusal, displaced = ns.addAllowed(name, "menu")
                    if ok then offerDisplacedUndo(key, displaced) end
                    if refusal == "account" then ns.printMsg(bnetNotBlockedFull()) end
                end
                if ns.refreshUI then ns.refreshUI() end
            end,
        },
        {
            text = isBlocked and L["MENU_UNBLOCK"] or L["MENU_BLOCK"],
            action = function()
                if isBlocked then
                    ns.removeBlocked(blockedKey)
                else
                    local ok, key, _, refusal, displaced = ns.addBlocked(name, "menu")
                    if ok then offerDisplacedUndo(key, displaced) end
                    if refusal == "account" then ns.printMsg(bnetNotBlockedFull()) end
                end
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
