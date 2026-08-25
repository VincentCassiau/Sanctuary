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

-- The accessibility rules this file is held to. They are rules, not taste,
-- and they apply to every screen -- a new widget that breaks one of them is a
-- defect even when it looks right on the developer's monitor.
--
--   1. Never a meaning carried by colour alone. A picked card has a filled ring
--      AND an accent border; a blocked verdict has a word; the protection state
--      has a sentence beside its dot. Someone who cannot tell the two greens
--      apart still reads the screen.
--   2. No visible face under 12 px. Descriptions are the smallest thing here and
--      they sit at FONT_BODY; the mock-up's 11.5 px was refused on that ground.
--   3. Secondary text is a notch lighter than the mock-up's #9A9AAA, which sits
--      at about 6.9:1 on this panel. `C.dim` is what carries it and it is the
--      colour every description, hint and note reads from.
--   4. A greyed-out control shows it TWICE: the fill dims (opacity) and a
--      sentence says why. Two questions of the home screen can go grey and both
--      carry their sentence: `Q2_COVERED` under question 2 in "everyone except
--      the people I block", `ANTISPAM_COVERED` under question 3 when the
--      channels are already all filtered. Small (12 px) and never italic --
--      decision 153, and the game has no italic face to embed -- and in the
--      orange of decision 162f, which is the one thing on a dead section that is
--      not grey: the sentence is what a section that has stopped answering is
--      read through, so it cannot be as quiet as what it explains.
--   5. Bound every FontString that can be longer than its column. One with no
--      width draws on one line as far as it needs, over whatever is beside it:
--      a card title folds, a tile's line is cut. French is the language that
--      overflows and it is the user's own.
--
-- Transposed from the validated mock-ups (maquettes/cible2.py). One appearance,
-- "Moderne": the dark palette the add-on already used.
local C = {
    panel      = { 0.051, 0.051, 0.102, 0.97 },
    -- `.veil { background: rgba(0,0,0,.45) }` -- what the mock-up dims the screen
    -- with while a side panel is open.
    veil       = { 0.000, 0.000, 0.000, 0.45 },
    header     = { 0.078, 0.078, 0.149, 1.00 },
    border     = { 0.302, 0.302, 0.400, 0.85 },
    -- `border-top: 1px dashed rgba(77,77,102,0.5)` -- the same edge, fainter,
    -- and it is drawn in ONE place: between the block that has gone out and the
    -- one box of question 2 that is still live (decision 163).
    dash       = { 0.302, 0.302, 0.400, 0.50 },
    ink        = { 1.000, 1.000, 1.000, 1.00 },
    -- Rule 3: the mock-up's #9A9AAA, one notch lighter. #B3B3C2 reads at about
    -- 9.3:1 on the panel where #9A9AAA read at 6.9 -- the same grey to look at,
    -- a different one to read on a screen that is not the developer's.
    dim        = { 0.702, 0.702, 0.761, 1.00 },
    soft       = { 0.800, 0.800, 0.847, 1.00 },
    accent     = { 0.400, 0.600, 1.000, 1.00 },
    accentBg   = { 0.400, 0.600, 1.000, 0.12 },
    -- `height:1px; background:rgba(102,153,255,0.32)` -- the rule between two
    -- questions of the home screen, and nowhere else (decision 139).
    rule       = { 0.400, 0.600, 1.000, 0.32 },
    -- The strip of tabs under the title bar (decision 140), and the tint the
    -- current one is filled with: `rgba(20,20,36,0.9)` and `rgba(102,153,255,.14)`.
    tabBar     = { 0.078, 0.078, 0.141, 0.90 },
    tabOn      = { 0.400, 0.600, 1.000, 0.14 },
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
    -- Rule 4: a greyed control dims as well as greys, so `disabled` is read
    -- through DISABLED_ALPHA and has to start light enough to survive it.
    disabled   = { 0.545, 0.545, 0.588, 1.00 },
}

-- Rule 4, the other half of it: what a disabled control is drawn at. Not so
-- faint that its label stops being readable -- a person has to be able to read
-- what they cannot click -- and not so close to 1 that the state is the colour
-- of the text and nothing else.
local DISABLED_ALPHA = 0.8

-- What a card of a DEAD question is drawn at (decision 163, option A). Lower
-- than DISABLED_ALPHA, and deliberately so: those two cards are no longer a
-- control somebody is being asked to read, they are the memory of an answer, and
-- what the section means is carried by the orange sentence over them. The
-- mock-up Vincent picked draws them at .55.
local WITNESS_ALPHA = 0.55

-- 15 / 14 / 13 / 12, the hierarchy Vincent asked for, thinned by one step at the
-- top: decision 141 asked the modal to gain room without losing its air, and a
-- question title reads as a title at 15 px just as well as at 16. Nothing here
-- goes under 12 -- rule 2 of the section head, which is why the mock-up's
-- 11.5 px descriptions were refused.
local FONT_TITLE, FONT_SECTION, FONT_DESC, FONT_BODY = 15, 14, 13, 12

-- The width the window opens at, and what the grip may take it to. Both axes
-- move now: the bounds are the brief's own, 500x380 to 900x700, measured on the
-- whole window. Nothing scrolls sideways -- what a wider window buys is wider
-- columns, not a wider canvas to pan over -- so every screen is laid out from
-- `innerWidth()` and never from the number it was built at.
local DEFAULT_WIDTH = 780
local MIN_FRAME_WIDTH, MAX_FRAME_WIDTH = 500, 900
-- The height the window ASKS for when it opens. The home screen is the tallest
-- thing here that never folds -- five questions, the tester and its answer --
-- and this is that screen measured at DEFAULT_WIDTH, which is the only width the
-- fitted mode ever has: a remembered width comes with a remembered height, and
-- that pair is applied instead of this one. Every screen opens in that same
-- window rather than the window jumping size from tab to tab.
--
-- Recalculated after the visual pass of 25/08 (decisions 162-163), and this time
-- it is the number the screen actually MEASURES rather than one with room to
-- spare in it: 24 px of air on each side of the four rules puts 96 px on, the
-- margin the screen used to keep for itself takes 18 off, and the tester row
-- stops at the bottom edge of its field for another 8. The screen that asked for
-- 740 asks for 776, and a floor above what the screen needs is exactly the empty
-- band under "Tester un pseudo" that constat 162d is about.
--
-- Only the OTHER screens are floored at it: the home screen is measured at every
-- refresh and opens at whatever it comes to on the client it is running on, so
-- what this number decides is that About and the Journal open in the same window
-- rather than shrinking around themselves.
--
-- What the window GETS is the screen's to decide, never this number: a Retail
-- client at the default UI scale measures 768 units, which leaves 748 px of
-- window for 840 asked, so the home screen still scrolls there and its bar says
-- so (decision 134 -- "on a jamais parle de rendre la page d'accueil non
-- scrollable"). The other screens are shorter than the window they are given and
-- do not scroll.
local MIN_HEIGHT, MAX_HEIGHT = 776, 900
-- The smallest window the grip may drag to, which is NOT the height above. The
-- content scrolls (decision 3), so a person may make the window smaller than
-- what is in it; and a floor set at the height the window OPENS at is a floor
-- that meets the ceiling on every screen with less room than that -- 954 units
-- and below, so every default Retail client -- leaving the grip no vertical
-- travel at all (decision 98: the horizontal adds itself to the vertical, it
-- does not replace it).
local GRIP_MIN_HEIGHT = 380
-- The window's own border, `border: 2px solid` in the mock-up. Named because the
-- title bar has to keep clear of it: a filled frame pinned to the very corner of
-- the window paints over the outline instead of sitting inside it.
local FRAME_EDGE = 2
local HEADER_HEIGHT = 40
-- The strip of tabs (decision 140): ONE bar, the full width of the window, held
-- between the title bar and the content, on every screen. `padding:8px 17px`
-- around a 13 px label is a 30 px bar. TAB_UNDERLINE is the mock-up's
-- `box-shadow: inset 0 -2px 0 accent` -- the accent line the current tab carries
-- along its BOTTOM edge, pointing at the content it opens.
--
-- The old strip hung below the frame, which is why so much of the sizing code
-- below used to reserve room outside the window: nothing hangs out of it now.
--
-- TAB_RULE is the hairline the strip carries along its top AND its bottom edge,
-- the same one pixel on both (decision 162b). Two things have to leave it alone
-- for the two lines to read as one pair: the title bar, which drew a hairline of
-- its own along its bottom edge and made the top line two pixels thick where the
-- bottom was one; and the tab buttons, which are children of the strip and so
-- draw OVER it -- a button as tall as the strip paints its own fill across both
-- rules and cuts them wherever a tab sits. So the buttons are inset by the rule
-- at each end, and what is left between the two lines is the row.
local TABBAR_HEIGHT, TAB_UNDERLINE, TAB_RULE = 30, 2, 1
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
-- The margin under the content, and the last thing between it and the bottom
-- edge of the window: `padding: 20px 18px 16px` on the mock-up's content column,
-- of which this is the 16.
--
-- It used to be 30 -- room booked so the undo strip, which is pinned to the
-- frame's bottom edge, could never sit over a line of content -- and the screens
-- kept a margin of their own on top of it. That is 48 px of nothing under
-- "Tester un pseudo" on a window that opens fitted, which is constat 162d. The
-- strip is an OVERLAY and it is up for six seconds at a time, after a gesture
-- made in a drawer that covers this screen anyway; a margin that is empty
-- always is the worse of the two.
local CONTENT_BOTTOM = 16
-- The undo strip, stated once because two layouts have to keep clear of it: it
-- is an overlay pinned this far above the bottom edge of the frame, and it sits
-- OVER the panels rather than inside them.
local UNDO_HEIGHT, UNDO_MARGIN = 22, 6
-- What the strip spends on anything that is not the sentence: the inset at each
-- end, the gap before the button, and the button itself. Stated once, because
-- the sentence gets exactly what is left of the row and nothing else.
local UNDO_INSET, UNDO_GAP, UNDO_BTN_WIDTH = 8, 12, 90
-- What the whole window may measure in height, header and bottom strip included.
-- Where the content area starts: under the title bar AND under the strip of
-- tabs, which is inside the window now. Written once, because five things hang
-- from it -- the scroll area, the veil, the drawers and both height passes --
-- and a screen anchored under one of the two alone is a screen with a tab strip
-- drawn over its first line.
local CONTENT_TOP = HEADER_HEIGHT + TABBAR_HEIGHT
local MIN_FRAME_HEIGHT = MIN_HEIGHT + CONTENT_TOP + CONTENT_BOTTOM
local MAX_FRAME_HEIGHT = MAX_HEIGHT + CONTENT_TOP + CONTENT_BOTTOM
local GRIP_MIN_FRAME_HEIGHT = GRIP_MIN_HEIGHT + CONTENT_TOP + CONTENT_BOTTOM
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
-- screen moves when one appears. ONE line, decision 167c: the labels start just
-- under the field they belong to, which is what two lines of reserved emptiness
-- were pushing them away from (constat 164.3). A sentence that folds over more
-- than that line -- the Battle.net refusal on the blocked names field is the
-- only one -- takes the room it actually draws, through `box:LabelsGap`, and
-- gives it back when it goes: the reserve is a floor, not a promise that every
-- answer fits it. The harness measures the sentences against this value.
local NOTE_ROOM_ONE_LINE = NOTE_GAP + NOTE_LINE
-- The one rule the three add fields share, and the whole of constat D.4: a field
-- row, then the room its refusal sentence needs, then the labels it feeds --
-- always below the field, always the same distance from it. Allowed used to draw
-- its labels ABOVE the field, blocked names put them at the bottom of the
-- section, and patterns left a wider gap than either: three fields, three
-- answers to the same question. The one-line room is taken everywhere, not only
-- where a sentence can appear, because "the same spacing" is what was asked for
-- and a field whose labels sit fifteen pixels higher than its neighbour's is the
-- difference that was noticed in the first place.
local LIST_INPUT_ROW = 34
local LIST_LABELS_GAP = LIST_INPUT_ROW + NOTE_ROOM_ONE_LINE
local LIST_REFRESH_SECONDS = 10
-- The three add fields, named once. Two sweeps walk them -- the one that takes
-- a sentence off when what it announced has left the list, and the one that
-- empties the fields when the window closes -- and a fourth field added to one
-- list alone would be a field the other sweep never visits.
local LIST_INPUT_KEYS = { "addInput", "nameInput", "patternInput" }

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

-- `name` is optional and almost never given: a FontString is read through the
-- table that holds it. The one exception is a sentence a check has to read back
-- by itself, which needs a global to reach.
local function newLabel(parent, text, size, color, justify, name)
    local label = parent:CreateFontString(name, "OVERLAY", "GameFontNormal")
    local fontFile = label:GetFont()
    label:SetFont(fontFile, size or FONT_BODY, "")
    label:SetTextColor(unpack(color or C.ink))
    label:SetText(text or "")
    label:SetJustifyH(justify or "LEFT")
    return label
end

-- The label of a box or a dot is part of the control, not a caption beside it:
-- "cliquer le texte d'une case a cocher doit cocher/decocher" (decision 135).
-- Every interface a person has used works that way, and an 18 px square is a
-- small target.
--
-- The hit area is anchored on the FontString itself at both corners, so it is
-- exactly the label's own box and nothing past it: the text while the label
-- sizes itself, the bound while a column bounds it (`FitLabel` below), and the
-- folded block when it folds. Never the width of the row -- a button given the
-- row's width would turn the empty half of the line into a switch nobody meant
-- to touch, and the row is the whole screen wide. It is a
-- child of the control rather than of the screen, so hiding the control hides
-- its second target with it; and it calls the OnClick handler rather than
-- `Click()`, which on a CheckButton would also flip the drawn state behind the
-- model's back.
local function makeLabelClickable(control)
    local hit = CreateFrame("Button", nil, control)
    hit:SetPoint("TOPLEFT", control.label, "TOPLEFT", 0, 2)
    hit:SetPoint("BOTTOMRIGHT", control.label, "BOTTOMRIGHT", 0, -2)
    hit:SetScript("OnClick", function()
        local onClick = control:GetScript("OnClick")
        if onClick then onClick(control) end
    end)
    control.labelHit = hit
    return hit
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

    -- Bounded to what its column leaves it, a label FOLDS instead of running
    -- over whatever sits beside it -- which on the home screen is the other
    -- column. Folding rather than truncating, because the block it is in
    -- measures its own height and the screen may scroll (decision 134): the
    -- second line has somewhere to go, which is the test the tile in the same
    -- file fails and this one passes.
    --
    -- It grows DOWNWARD. Anchored by its middle, as it is until this is called,
    -- a second line climbs as far above the box as it drops below it, and no row
    -- height can give that back to the row above. The first line stays centred on
    -- the box, so a label that fits is drawn exactly where it was.
    --
    -- Answers the height the control now takes, box included, so the caller can
    -- advance its row by what the fold actually measured.
    function frame:FitLabel(width)
        local label, box = self.label, self:GetHeight() or 0
        label:SetWordWrap(true)
        label:SetWidth(9999)
        local drop = math.max(0, (box - (label:GetStringHeight() or 0)) / 2)
        label:SetWidth(math.max(1, width))
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self, "TOPRIGHT", 8, -drop)
        return math.max(box, drop + (label:GetStringHeight() or 0))
    end

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
        -- Rule 4: greyed dims as well as greys. The label is a child of the
        -- SCREEN rather than of the box, so it has to be told separately or half
        -- the control fades and the other half does not.
        local alpha = self.enabled and 1 or DISABLED_ALPHA
        self:SetAlpha(alpha)
        self.label:SetAlpha(alpha)
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
    -- The label is the other half of the target, and it carries the same
    -- tooltip: a sentence a person reaches by hovering the box has to be
    -- reachable from the words that name it.
    setTooltip(makeLabelClickable(frame), tooltip)
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

    -- The same contract as the check's, on the same 18 px box: see `newCheck`
    -- for why it folds downward rather than truncating.
    function frame:FitLabel(width)
        local label, box = self.label, self:GetHeight() or 0
        label:SetWordWrap(true)
        label:SetWidth(9999)
        local drop = math.max(0, (box - (label:GetStringHeight() or 0)) / 2)
        label:SetWidth(math.max(1, width))
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self, "TOPRIGHT", 8, -drop)
        return math.max(box, drop + (label:GetStringHeight() or 0))
    end

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
        local alpha = self.enabled and 1 or DISABLED_ALPHA
        self:SetAlpha(alpha)
        self.label:SetAlpha(alpha)
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
    setTooltip(makeLabelClickable(frame), tooltip)
    return frame
end

-- What a card spends on anything that is not its own text. "Compact doux"
-- (decisions 141-142) is dense INSIDE a block and airy between blocks, so this
-- is the dense half: 11 px of side padding where there were 12, 8 above and
-- below where there were 10, and a title sitting 4 px off its description.
local CARD = { pad = 11, top = 8, bottom = 8, ring = 15, ringGap = 9,
    titleLine = 16, titleGap = 4 }

-- Card: an exclusive choice with a title and a description. Clicking anywhere
-- on it selects it -- the whole card is the target, not a 16-pixel dot.
--
-- Decision 143 gave it the dot as well, and made it a convention: round is an
-- exclusive choice, square is a switch, everywhere and without exception. What
-- was on screen carried the pick in the border and the title's colour and
-- nothing else, which is a meaning in a colour -- rule 1 of the section head,
-- and what "les maquettes C2 validees avaient des ronds" was pointing at. Three
-- discs, the same shape as a radio, so the two read as one family.
local function newCard(parent, name, titleText, descText, width, isOn, select)
    local card = CreateFrame("Button", name, parent, "BackdropTemplate")
    card.enabled = true

    -- The ring is a frame of its own so `newDisc` can centre its three textures
    -- AND their circular mask on it. A texture re-anchored away from its parent
    -- leaves the mask behind, and a mask left behind is a square dot.
    card.ringFrame = CreateFrame("Frame", nil, card)
    card.ringFrame:SetSize(CARD.ring, CARD.ring)
    card.ringFrame:SetPoint("TOPLEFT", card, "TOPLEFT", CARD.pad, -(CARD.top + 2))
    card.rim = newDisc(card.ringFrame, "BACKGROUND", CARD.ring, C.border)
    card.fill = newDisc(card.ringFrame, "BORDER", CARD.ring - 2, C.checkBg)
    card.mark = newDisc(card.ringFrame, "OVERLAY", CARD.ring - 8, C.checkOn)

    local textLeft = CARD.pad + CARD.ring + CARD.ringGap
    card.title = newLabel(card, titleText, FONT_DESC, C.ink)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", textLeft, -CARD.top)
    card.desc = newLabel(card, descText, FONT_BODY, C.dim)
    card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -CARD.titleGap)
    card.desc:SetJustifyH("LEFT")

    function card:Refresh()
        local on = isOn() and true or false
        if self.mark then
            if on then self.mark:Show() else self.mark:Hide() end
        end
        if not self.enabled then
            -- A card is only ever disabled on a question that has gone dead as a
            -- whole, and decision 163 (option A) says what it becomes there: a
            -- witness, not a control. It still shows which answer was given --
            -- the ring keeps its dot -- and everything else goes out: the fill
            -- loses its accent, the ring's dot with it, and the whole card drops
            -- to WITNESS_ALPHA. What carries the meaning is the orange sentence
            -- above the pair, so rule 1 is answered in words rather than by a
            -- card somebody has to be able to read at a glance.
            applyBackdrop(self, C.tile, C.border)
            self.rim:SetColorTexture(unpack(C.disabled))
            self.mark:SetColorTexture(unpack(C.disabled))
            self.title:SetTextColor(unpack(C.dim))
            self.desc:SetTextColor(unpack(C.disabled))
            self:SetAlpha(WITNESS_ALPHA)
            return
        end
        self:SetAlpha(1)
        -- Back from the witness state, which took the two of them out.
        self.mark:SetColorTexture(unpack(C.checkOn))
        applyBackdrop(self, on and C.accentBg or C.tile, on and C.accent or C.border)
        -- `.rd.on { border-color: accent }`: the rim answers too.
        self.rim:SetColorTexture(unpack(on and C.accent or C.border))
        self.title:SetTextColor(unpack(on and C.accent or C.ink))
        self.desc:SetTextColor(unpack(C.dim))
    end

    function card:SetEnabledState(enabled)
        self.enabled = enabled and true or false
        self:Refresh()
    end

    -- The card and the wrapping width of its two texts are one measurement, so
    -- they are set together: a card widened on its own leaves its own text
    -- folded to the width it was built at.
    --
    -- The TITLE is bounded like the description, and that is not symmetry for
    -- its own sake. A FontString with no width draws on one line as far as it
    -- needs, and the text column here is the card minus the ring: 181 px at the
    -- 500 px the grip goes down to, against the 190 px "Tout le monde, sauf ceux
    -- que je bloque" asks for at its very thinnest. French is the language that
    -- overflows, which is the user's own, and no width settles it -- it is the
    -- ratio between the two that does. So the title folds instead.
    function card:SetCardWidth(newWidth)
        self:SetWidth(newWidth)
        local column = newWidth - textLeft - CARD.pad
        self.title:SetWidth(column)
        self.desc:SetWidth(column)
    end

    -- What this card needs, at the width it is at RIGHT NOW.
    --
    -- Both texts wrap, and how many lines they take is the window's business
    -- rather than a constant's: the longest description is two lines at 900 px
    -- and four at 500, and the longest title is one line at 900 and two at 500.
    -- A flat height was room booked for the worst case on every screen and,
    -- once the ring took 24 px off the text column, text over the edge on the
    -- case nobody had measured.
    function card:NeededHeight()
        local title = math.max(CARD.titleLine, self.title:GetStringHeight() or CARD.titleLine)
        local desc = math.max(NOTE_LINE, self.desc:GetStringHeight() or NOTE_LINE)
        return CARD.top + title + CARD.titleGap + desc + CARD.bottom
    end

    card:SetScript("OnClick", function(self)
        if not self.enabled then return end
        select()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.refreshUI then ns.refreshUI() end
    end)
    card:SetCardWidth(width or 340)
    return card
end

-- The cards answering one question are a row: they take the tallest height any
-- of them needs, or two answers to the same question sit in boxes of different
-- sizes. Answers that height, which is what the screen below counts in.
local function sizeCardRow(cards, width)
    local tallest = 0
    for _, card in ipairs(cards) do
        card:SetCardWidth(width)
        tallest = math.max(tallest, card:NeededHeight())
    end
    for _, card in ipairs(cards) do card:SetHeight(tallest) end
    return tallest
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

    -- The line that answers the field. It starts at the box's left edge, so
    -- there is never a doubt which of the three fields is being answered, but it
    -- runs the panel's width rather than the box's: the box is 250 px and the
    -- sentences are up to 82 characters. The panels keep its room reserved
    -- whether it is showing or not -- a sentence that appears must not shove the
    -- list under it downwards, nor lie over it.
    --
    -- One line, two answers, decision 167c: orange when the entry was refused,
    -- green when it went in. Same place, same six seconds, so a person watches
    -- one spot rather than hunting for where the add-on replied.
    box.note = newLabel(box, "", FONT_BODY, C.orange)
    box.note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -NOTE_GAP)
    box.note:Hide()

    -- `noteWidth()` reads the window as it is now, and a field built at 780 kept
    -- the 500 px column it was given then for ever -- inside a window that can be
    -- 500 px wide in total. The panels ask on every redraw; the fields that live
    -- on a screen are asked by their screen's width pass.
    function box:RefreshNoteWidth() self.note:SetWidth(noteWidth()) end
    box:RefreshNoteWidth()

    -- The room the three panels leave under this field before the labels it
    -- feeds. One line is reserved whether a sentence is showing or not, so the
    -- ordinary answers move nothing; a sentence that folds over more than that
    -- line takes what it actually draws -- `GetStringHeight` is the height the
    -- client rendered, not a count of anything -- and gives it back when it
    -- clears. Reserving one line for a two-line sentence did not push the labels
    -- down, it wrote the sentence over them.
    function box:LabelsGap()
        if not self.note:IsShown() then return LIST_LABELS_GAP end
        local drawn = self.note:GetStringHeight() or 0
        return LIST_LABELS_GAP + math.max(0, drawn - NOTE_LINE)
    end

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
        local wasShown = self.note:IsShown()
        self.noteToken = nil
        self.noteKey, self.noteHolds = nil, nil
        self.note:SetText("")
        self.note:Hide()
        -- A sentence taller than the reserved line had pushed the labels down:
        -- they come back up here, on the same redraw that took the sentence off.
        if wasShown and ns.redrawOpenPanel then ns.redrawOpenPanel() end
    end

    -- The generation token the undo strip uses, and for the same reason: two
    -- answers a second apart leave two timers running, and the older one must
    -- not wipe the sentence the newer one has just put up. Same six seconds as
    -- the undo strip, from the same constant -- one duration on this screen.
    --
    -- The colour is set on every answer and never assumed: the label is one
    -- FontString reused by both, so a green line followed by a refusal would
    -- otherwise say no in the colour of yes.
    function box:Say(text, color, key, holds)
        local mine = {}
        self.noteToken = mine
        -- What the sentence is about, when it is about something: a yes names an
        -- entry, and `holds` is how to ask whether that entry is still listed. A
        -- refusal names nothing and passes neither, so nothing can cut its six
        -- seconds short.
        self.noteKey, self.noteHolds = key, holds
        self.note:SetTextColor(unpack(color))
        self.note:SetText(text)
        self.note:Show()
        -- The panel is laid out again with the sentence on it: a two-line
        -- refusal needs more room than the line kept for it, and what is under
        -- the field moves down for as long as it is showing.
        if ns.redrawOpenPanel then ns.redrawOpenPanel() end
        C_Timer.After(UNDO_SECONDS, function()
            if self.noteToken == mine then self:ClearNote() end
        end)
    end

    function box:SayNo(text) self:Say(text, C.orange) end
    function box:SayYes(text, key, holds) self:Say(text, C.green, key, holds) end

    -- "Ajouté : Kadaj-Ysondre." is true for exactly as long as Kadaj-Ysondre is
    -- on the list. There are six crosses that can take him back off, plus the
    -- right-click menu and Annuler, and a sentence still saying yes over an
    -- empty row is the screen lying about the one thing it is there to show. So
    -- the check is here, on the redraw every one of those gestures ends with,
    -- rather than a ClearNote at each of them -- the next gesture added would be
    -- the one nobody remembered. Removing ANOTHER label leaves this sentence
    -- alone: it is its own key that is looked up, not the state of the list.
    --
    -- Quiet on purpose: the caller is the redraw, and asking for another one
    -- from inside it lays the panel out twice.
    function box:ForgetStaleNote()
        if not self.noteKey then return end
        local holds = self.noteHolds
        if not holds or holds(self.noteKey) then return end
        self.noteToken = nil
        self.noteKey, self.noteHolds = nil, nil
        self.note:SetText("")
        self.note:Hide()
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

    -- A field narrower than its own text shows the END of it: `SetText` leaves
    -- the cursor after the last character and the client scrolls to follow it,
    -- so "SanctuaryTest" in a 90 px box read "ctuaryTest". At rest the beginning
    -- is what names the value, so the view goes back to it whenever nobody is
    -- typing in the field.
    function box:ShowFromStart()
        if self.SetCursorPosition then self:SetCursorPosition(0) end
        return self
    end
    box:SetScript("OnEditFocusLost", function(self) self:ShowFromStart() end)

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
-- The arrow in the field, DRAWN rather than written.
--
-- It used to be U+25BE, the small down-pointing triangle of the mock-up. Friz
-- Quadrata -- the face this whole window is set in -- has no glyph for it: WoW
-- draws a white rectangle instead, which is what "rectangle blanc dans le menu
-- des durees" is. The font covers Latin-1 and the Windows-1252 additions and
-- nothing else, so the geometric shapes block is out of reach whatever the
-- locale, and a glyph nobody can render is not a translation problem to be
-- fixed in one language.
--
-- Four bars, each two pixels tall, 8 px wide down to 2: a staircase that reads
-- as a triangle at this size and depends on no font, no atlas and no file.
local CARET_ROWS = 4
local function newCaret(parent, color)
    local caret = CreateFrame("Frame", nil, parent)
    caret:SetSize(CARET_ROWS * 2, CARET_ROWS * 2)
    caret.bars = {}
    for index = 1, CARET_ROWS do
        local bar = caret:CreateTexture(nil, "OVERLAY")
        bar:SetSize((CARET_ROWS - index + 1) * 2, 2)
        if index == 1 then
            bar:SetPoint("TOP", caret, "TOP", 0, 0)
        else
            bar:SetPoint("TOP", caret.bars[index - 1], "BOTTOM", 0, 0)
        end
        bar:SetColorTexture(unpack(color))
        caret.bars[index] = bar
    end
    -- One call for the four bars: the field greys its arrow with the rest of
    -- itself, and a triangle half in one colour is worse than no triangle.
    function caret:SetCaretColor(newColor)
        for _, bar in ipairs(self.bars) do bar:SetColorTexture(unpack(newColor)) end
    end
    return caret
end

local function newDropdown(parent, name, width, rows, get, set)
    local field = CreateFrame("Button", name, parent, "BackdropTemplate")
    field:SetSize(width or 140, 24)
    applyBackdrop(field, C.input, C.border)
    field.value = newLabel(field, "", FONT_BODY, C.ink)
    field.value:SetPoint("LEFT", field, "LEFT", 8, 0)
    field.caret = newCaret(field, C.dim)
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
        self.caret:SetCaretColor(self.enabled and C.dim or C.disabled)
        applyBackdrop(self, C.input, self.enabled and C.border or C.disabled)
        -- Rule 4. On the field itself, which carries the arrow with it -- the
        -- caret is a child, so dimming both would dim it twice.
        self:SetAlpha(self.enabled and 1 or DISABLED_ALPHA)
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

-- Scroll: a bar of our own, hidden when the content fits, and a wheel that
-- works whether or not the bar is there.
--
-- One notch of wheel, the width of the whole bar, and the shortest the thumb may
-- get on a very long screen. The bar is the one thing this window puts OVER the
-- right edge of a screen, so its width is bounded by the margin every layout
-- here keeps clear on that side -- ten pixels on the Journal rows, the
-- Diagnostics columns and the export box, eighteen on the home screen. Widen it
-- past that and it starts eating clicks meant for whatever is underneath.
local SCROLL_STEP, SCROLL_BAR_WIDTH, SCROLL_THUMB_MIN = 24, 8, 24

-- Where the content goes, from wherever it is asked: the wheel, the thumb being
-- pulled, a click in the track. One place, so `offset`, the frame's own vertical
-- scroll and the thumb can never end up saying three different things about the
-- same screen.
local function scrollTo(scroll, offset)
    local range = math.max(0, (scroll.child:GetHeight() or 0) - (scroll:GetHeight() or 0))
    scroll.offset = math.min(range, math.max(0, offset or 0))
    scroll:SetVerticalScroll(scroll.offset)
    scroll:RefreshBar()
end

-- Follows the mouse while the thumb is held. Counted from where the drag
-- started, not from where the bar is on screen: `GetCursorPosition` answers in
-- screen pixels and a frame's own coordinates are one scale away from them, so
-- the difference between two readings -- brought back through that scale -- is
-- the only measure that needs no absolute geometry at all, and the one that
-- cannot drift if the window is moved mid-drag.
local function dragScrollThumb(thumb)
    local scroll = thumb.scroll
    if not scroll or not thumb.dragCursorY then return end
    local _, cursorY = GetCursorPosition()
    if not cursorY then return end
    local scale = (thumb.GetEffectiveScale and thumb:GetEffectiveScale()) or 1
    if scale == 0 then scale = 1 end
    local travel = math.max(0, (scroll.bar:GetHeight() or 0) - (thumb:GetHeight() or 0))
    local range = math.max(0, (scroll.child:GetHeight() or 0) - (scroll:GetHeight() or 0))
    if travel <= 0 or range <= 0 then return end
    -- Screen Y grows upwards, so the thumb going DOWN the track is a drop, and
    -- a drop is a bigger offset: the content comes up as the thumb goes down.
    local dropped = (thumb.dragCursorY - cursorY) / scale
    scrollTo(scroll, (thumb.dragOffset or 0) + dropped * range / travel)
end

local function startScrollDrag(thumb)
    local _, cursorY = GetCursorPosition()
    thumb.dragCursorY = cursorY
    thumb.dragOffset = (thumb.scroll and thumb.scroll.offset) or 0
    thumb:SetScript("OnUpdate", dragScrollThumb)
end

local function stopScrollDrag(thumb)
    thumb:SetScript("OnUpdate", nil)
    thumb.dragCursorY = nil
end

local function newScroll(parent, name, width, height)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:SetSize(width, height)
    local child = CreateFrame("Frame", name and (name .. "Child") or nil, scroll)
    child:SetSize(width, height)
    scroll:SetScrollChild(child)
    scroll.child = child

    -- The track. Everything that takes the mouse here is a child of it, and it
    -- is hidden whenever the content fits, so a screen with nothing to scroll
    -- gives the mouse back to what is drawn under the bar.
    local bar = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    bar:SetSize(SCROLL_BAR_WIDTH, height)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    applyBackdrop(bar, C.tile, nil)
    bar:Hide()
    scroll.bar = bar

    -- The thumb. What stood here was one flat frame the height of the window:
    -- it said "there is more below" and nothing else -- not how much more, not
    -- where in the screen one had got to -- and it did not move the content when
    -- it was pulled. The wheel was the only way down.
    local thumb = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    thumb:SetSize(SCROLL_BAR_WIDTH, SCROLL_THUMB_MIN)
    thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    thumb:SetFrameLevel((bar:GetFrameLevel() or 0) + 1)
    applyBackdrop(thumb, C.border, nil)
    thumb.scroll = scroll
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    -- Both pairs, and both ends idempotent: the press is where a person expects
    -- the thumb to start following, and the drag stop is the release WoW
    -- guarantees wherever the mouse has got to by then -- a button let go beside
    -- the bar is not an OnMouseUp on it, and that is a thumb left stuck to the
    -- pointer for the rest of the session.
    thumb:SetScript("OnMouseDown", startScrollDrag)
    thumb:SetScript("OnMouseUp", stopScrollDrag)
    thumb:SetScript("OnDragStart", startScrollDrag)
    thumb:SetScript("OnDragStop", stopScrollDrag)
    thumb:SetScript("OnHide", stopScrollDrag)
    scroll.thumb = thumb
    bar.thumb = thumb

    -- Clicking the track pages. The two halves are frames anchored to the ends
    -- of the thumb rather than one frame and a cursor reading: "above" and
    -- "below" then need no geometry at all, and neither half exists -- nor takes
    -- a click -- when the thumb is already at that end of the track.
    local function newPageZone(direction)
        -- Both edges are anchored, so the zone is exactly as wide as the track
        -- and as tall as the room left beside the thumb: it has no size of its
        -- own to keep in step with anything.
        local zone = CreateFrame("Frame", nil, bar)
        zone:EnableMouse(true)
        zone:SetScript("OnMouseDown", function()
            -- A page, less one notch of wheel: a line of what was being read
            -- stays on the screen across the jump.
            local page = math.max(SCROLL_STEP, (scroll:GetHeight() or 0) - SCROLL_STEP)
            scrollTo(scroll, (scroll.offset or 0) + direction * page)
        end)
        return zone
    end
    bar.pageUp = newPageZone(-1)
    bar.pageUp:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.pageUp:SetPoint("BOTTOMRIGHT", thumb, "TOPRIGHT", 0, 0)
    bar.pageDown = newPageZone(1)
    bar.pageDown:SetPoint("TOPLEFT", thumb, "BOTTOMLEFT", 0, 0)
    bar.pageDown:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        scrollTo(self, (self.offset or 0) - delta * SCROLL_STEP)
    end)

    function scroll:RefreshBar()
        local range = (self.child:GetHeight() or 0) - (self:GetHeight() or 0)
        -- An offset the content no longer has is a view scrolled past its own
        -- end, showing nothing: a shorter screen, or a window dragged taller,
        -- both leave one behind.
        local reachable = math.max(0, range)
        if (self.offset or 0) > reachable then
            self.offset = reachable
            self:SetVerticalScroll(reachable)
        end
        if range > 1 then self.bar:Show() else self.bar:Hide() end

        -- The track is the window, and it is measured here rather than trusted
        -- from wherever the frame was last resized: the content area of the main
        -- window is resized with a plain `SetSize` on every pass of
        -- `applyViewport`, so the track kept the 820 px it was built at inside a
        -- viewport of 380 -- a piste running four hundred pixels below the
        -- bottom edge of the window (a ScrollFrame clips its scroll child, not
        -- its other children), and a thumb placed along it that would have left
        -- the window before reaching the end of the screen.
        local content = self.child:GetHeight() or 0
        local visible = self:GetHeight() or 0
        local track = visible
        self.bar:SetHeight(track)

        -- How much of the screen is on show, and where in it one is standing.
        -- A thumb as tall as its own track says "this is all of it", which is
        -- what the flat bar used to say at every offset of every screen.
        local thumbHeight = track
        if content > visible and content > 0 then thumbHeight = track * visible / content end
        thumbHeight = math.max(SCROLL_THUMB_MIN, math.min(track, thumbHeight))
        local travel = math.max(0, track - thumbHeight)
        local reached = 0
        if reachable > 0 then
            reached = travel * math.min(1, (self.offset or 0) / reachable)
        end
        self.thumb:SetHeight(thumbHeight)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, -reached)
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
        -- The track follows from `RefreshBar` and from nowhere else: half the
        -- frames here are resized through this method and half with a plain
        -- `SetSize`, and a track that only two of the five ever hear about is
        -- how one ended up twice the height of its own window.
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

local mainFrame, contentFrame, contentScroll, stateButton, resizeGrip, tabBar
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
-- And the same for the height, for the one screen whose content is not a stack
-- of rows but two columns that fill whatever room they are given. A screen tells
-- the refresh how tall it needs to be; this is the other direction -- the window
-- telling a screen how tall it has ended up.
local applyTabHeight = {}
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

-- Annuler's room is taken first, the sentence gets what is left. The strip is
-- the width of the screen and a qualified pseudo is as long as it likes, so with
-- the button anchored to the END of the sentence a name of any length pushed it
-- through the right border: at the 500 px bound "Ombrelune-ConseildesOmbres
-- retiré de « Toujours autorisés »" left half an Annuler on screen, and half a
-- button is a button nobody can click.
local function layoutUndoLine()
    if not undoLine then return end
    local room = (undoLine:GetWidth() or 0) - UNDO_INSET * 2 - UNDO_GAP - UNDO_BTN_WIDTH
    undoLine.label:SetWidth(math.max(40, room))
end

local function offerUndoLine(text, restore)
    undoState = { restore = restore, at = GetTime() }
    local mine = undoState
    if undoLine then
        undoLine.label:SetText(text)
        -- Cut at the right edge by the client, so the whole of it has to be
        -- readable somewhere: the list the name has just left is not it.
        setTooltip(undoLine, text)
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
        -- The green "Ajouté" under the field confirmed the very addition this
        -- takes back. Nothing to do about it here: the entry has just left its
        -- list, and the redraw Annuler ends with is where a sentence about an
        -- entry that is gone stops being shown.
    end)
end

-- ============================================================================
-- SECTION 5: Protection screen
-- ============================================================================

local protection = {}

-- The metrics of the "Compact doux v2" mock-up, named once and kept in one
-- table: the enclosing chunk is at Lua's ceiling of 200 registers, and this
-- screen is measured in a dozen numbers.
--
-- The shape decisions 141-142 asked for is dense inside a block, airy between
-- blocks: `titleRow` and the card metrics thinned by a step or two, and the
-- questions held apart by the air the mock-up leaves around its hairline.
--
-- `ruleGap` is that air, and it is 24 on EACH side of the rule (decision 162c --
-- "l'air entre separateur et sections n'est pas celui de la maquette"). The
-- validated screen stacks its blocks in a `gap:24px` column with the rule as one
-- more item of the stack, so the gap falls once above the line and once below
-- it; half of it on each side is what made the screen read as a "pate de
-- formulaire" next to the mock-up it came from.
--
--   titleRow   one row for a "N Question" at FONT_TITLE
--   gutter     `.cards { gap:10px }`, between two cards of the same row
--   blockGap   the gutter between the two columns of "I choose"
--   ruleGap    the air on each side of a rule between two questions
--   rowHeight  one row of a check or a radio
--   checkSize  a check is 18 px square, so a row leaves 6 between two of them
--   subIndent  `.cbr.sub { padding-left:26px }`, a box that belongs to a box
--   tile       a list tile: 20 px count, a title and its detail, thin
--   tileGap    what the tile row keeps under it before the tester
--   testField  the 24 px field, hung 4 px above the line its label sits on: the
--              bottom edge of the tester row, and of the screen with it
--   testGap    what that row keeps under itself before the answer, when there
--              is one -- the window is cut at the field otherwise
--   dash       one dash of the dotted rule, and `dashGap` the space after it.
--              Four and four reads as a dotted line at the one pixel the rule is
--              tall; a finer dash would be twice the textures for no more
--              meaning, and eight pixels of pitch is 108 of them across the
--              widest column the window has
local HOME = { titleRow = 22, gutter = 10, blockGap = 24, ruleGap = 24,
    rowHeight = 24, checkSize = 18, subIndent = 26,
    tile = 46, tileGap = 16, testField = 20, testGap = 8, dash = 4, dashGap = 4 }

-- The build MAKES the screen; `refreshTab.protection` PLACES it, all of it, from
-- the top down. Questions 1 and 2 used to be positioned here and never touched
-- again, because nothing above them ever folds -- but the cards measure their
-- own height now (the description wraps differently at every width), and a rule
-- has to be dropped between two questions whose heights are only known once
-- they have been measured. Two halves of one layout is how a screen ends up
-- agreeing with itself only until somebody edits one of them.
local function buildProtectionTab(parent)
    protection.frame = parent
    local width = innerWidth()

    -- `.qt` is two pieces, not one string: a small accent number and a 15 px
    -- white title, ten pixels apart. Three spaces in one accent-coloured
    -- 14 px string gave neither the hierarchy nor the air.
    local function stepTitle(text, number)
        local num = newLabel(parent, number, FONT_BODY, C.accent)
        local head = newLabel(parent, text, FONT_TITLE, C.ink)
        head:SetPoint("TOPLEFT", num, "TOPRIGHT", 10, 4)
        return head, num
    end

    -- Decision 139, "B en trait long": a hairline of accent between two
    -- questions of the home screen, the full width of it, and NOWHERE else in
    -- the interface. Four of them, one per join, made here and placed by the
    -- refresh -- which is the only pass that knows where a question ends.
    protection.rules = {}
    for index = 1, 4 do
        local rule = parent:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetColorTexture(unpack(C.rule))
        protection.rules[index] = rule
    end

    -- The dotted rule of decision 163, option A: what sets automatic trust --
    -- still live -- apart from the block that has just gone out above it.
    --
    -- A frame rather than a texture, because the client draws solid rectangles
    -- and nothing else: `border-top: 1px dashed` is drawn as dashes, a row of
    -- `dash`-wide segments every `dash + dashGap` pixels. They are made on demand
    -- and re-laid at every width, so the row is as long as the column is wide
    -- and no longer -- one texture per dash, kept and reused rather than made
    -- again on each pass.
    protection.dottedRule = CreateFrame("Frame", "SanctuaryTrustSeparator", parent)
    protection.dottedRule:SetHeight(1)
    protection.dottedRule.dashes = {}
    function protection.dottedRule:Layout(columnWidth)
        self:SetWidth(columnWidth)
        local pitch = HOME.dash + HOME.dashGap
        local wanted = math.max(1, math.floor((columnWidth + HOME.dashGap) / pitch))
        for index = 1, wanted do
            local dash = self.dashes[index]
            if not dash then
                dash = self:CreateTexture(nil, "ARTWORK")
                dash:SetHeight(1)
                dash:SetColorTexture(unpack(C.dash))
                self.dashes[index] = dash
            end
            -- The last one is cut to what is left rather than hanging over the
            -- edge of the column: a dash is a rectangle, and a rectangle drawn
            -- past the margin is a rectangle over whatever is beside it.
            local x = (index - 1) * pitch
            dash:SetWidth(math.min(HOME.dash, columnWidth - x))
            dash:ClearAllPoints()
            dash:SetPoint("LEFT", self, "LEFT", x, 0)
            dash:Show()
        end
        for index = wanted + 1, #self.dashes do self.dashes[index]:Hide() end
    end
    protection.dottedRule:Layout(width)
    protection.dottedRule:Hide()

    -- Question 1 ------------------------------------------------------------
    protection.q1Title, protection.q1Number = stepTitle(L["Q1_TITLE"], "1")
    local cardWidth = (width - HOME.gutter) / 2
    protection.q1Strangers = newCard(parent, "SanctuaryQ1_strangers",
        L["Q1_STRANGERS_TITLE"], L["Q1_STRANGERS_DESC"], cardWidth,
        function() return ns.getScope() == "strangers" end,
        function() setFilter("scope", "strangers") end)
    protection.q1Blocked = newCard(parent, "SanctuaryQ1_blockedOnly",
        L["Q1_BLOCKEDONLY_TITLE"], L["Q1_BLOCKEDONLY_DESC"], cardWidth,
        function() return ns.getScope() == "blockedOnly" end,
        function() setFilter("scope", "blockedOnly") end)

    -- Question 2 ------------------------------------------------------------
    protection.q2Title, protection.q2Number = stepTitle(L["Q2_TITLE"], "2")
    protection.q2All = newCard(parent, "SanctuaryQ2_all",
        L["Q2_ALL_TITLE"], L["Q2_ALL_DESC"], cardWidth,
        function() return ns.getPreset() == "all" end,
        function() setFilter("preset", "all") end)
    protection.q2Custom = newCard(parent, "SanctuaryQ2_custom",
        L["Q2_CUSTOM_TITLE"], L["Q2_CUSTOM_DESC"], cardWidth,
        function() return ns.getPreset() == "custom" end,
        function() setFilter("preset", "custom") end)
    -- Rule 4 of the section head, its other case: question 2 greyed out says so
    -- in words as well as in grey. The file stated the rule and applied it to
    -- question 3 alone -- somebody who cannot tell two greys apart read a screen
    -- that had stopped answering and nothing that said why.
    --
    -- Decision 153 settles how the two state notes are written: small (12 px)
    -- and never italic -- the game carries no italic face and embedding one for
    -- two sentences is weight nobody asked for. Decision 162f settles the
    -- colour: the same orange the patterns wear, not `C.dim`. Muted grey was
    -- "trop discret" set among a whole section of muted grey, and it is the ONE
    -- line on the screen that has to be read before the rest makes sense.
    protection.q2Note = newLabel(parent, "", FONT_BODY, C.orange, nil, "SanctuaryQ2Note")

    -- The enhanced-instance box is a single widget with two homes: under the two
    -- cards in "Everything", indented under "Block group invitations" in "I
    -- choose". Two widgets would mean two states to keep in step.
    --
    -- "(experimental)" is part of the label and not a mention beside it
    -- (decision 162e): set on the right of the row it read as a word belonging
    -- to the far edge of the window rather than to the box, and the row had to
    -- reserve room for it at every width.
    --
    -- Ticking it writes, like any other box (decision 170c): the warning of
    -- 167b is gone. What it does is on hover, in the tooltip, where the rest of
    -- the screen keeps its explanations.
    protection.strict = newCheck(parent, "SanctuaryStrictCheck",
        L["FILTER_STRICT_GROUP_INVITE_SYSTEM"], L["TIP_STRICT_GROUP_INVITE_SYSTEM"],
        function() return filterStored("strictGroupInviteSystemMessages") == true end,
        function(value) setFilter("strictGroupInviteSystemMessages", value) end)

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

    -- Named: it leaves the screen with the field it labels when the question
    -- goes dead, and a label left behind alone is the defect worth proving.
    protection.q3IntervalLabel = newLabel(parent, L["ANTISPAM_INTERVAL_LABEL"], FONT_BODY, C.soft,
        nil, "SanctuaryAntiSpamIntervalLabel")
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
    -- Only ever the "already covered" sentence now. Decision 142 struck the
    -- standing note ("Groupe, raid, amis Battle.net... comptees dans le
    -- Journal") off the home screen for saying twice what "un inconnu" already
    -- says, and the key went with it, out of both locales. Written like the
    -- note of question 2 above, and for the same reason: the two are one thing.
    -- Decision 162f, as above: the two state notes are one pair and wear one
    -- colour.
    protection.q3Note = newLabel(parent, "", FONT_BODY, C.orange, nil, "SanctuaryAntiSpamNote")

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

    -- Named, because it is the row directly under the guild line -- the one the
    -- longest label of the screen folds into -- and a check that cannot reach it
    -- cannot prove the fold is paid for in height.
    protection.channelsLabel = newLabel(choose, L["CHANNELS_LABEL"], FONT_BODY, C.soft,
        nil, "SanctuaryChannelsLabel")
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
        local colWidth = (innerWidth - HOME.blockGap) / 2
        local colX = { 0, colWidth + HOME.blockGap }
        local colY = { 0, 0 }
        -- The width a label gets is known HERE and nowhere else: a box does not
        -- learn which column it is in until it is laid out. Both columns are
        -- bounded by the same line -- the loop reads `colX[row.col]` against one
        -- `colWidth`, so telling the two apart would take a condition, and the
        -- left column overflowing runs over the boxes of the right one, which is
        -- worse than running out of the window.
        protection.checkLabelWidth = colWidth - (HOME.checkSize + 8)
        for _, row in ipairs(CHECK_ROWS) do
            local col = row.col
            local check = protection.checks[row.key]
            check:ClearAllPoints()
            check:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[col], colY[col])
            -- The row is as tall as the label turned out to be, never shorter
            -- than the row height the mock-up asks for.
            local rowHeight = math.max(HOME.rowHeight,
                check:FitLabel(protection.checkLabelWidth) + (HOME.rowHeight - HOME.checkSize))
            colY[col] = colY[col] - rowHeight
            if row.key == "groupInvite" then
                -- What the row of the parent box came to, for the child box that
                -- hangs under it: the child is placed by the refresh, against
                -- this number, so a folded parent label cannot end up under it.
                protection.groupInviteRow = rowHeight
                -- The row the strict box takes under its parent, kept clear
                -- whether the box is there or not. The box itself hangs from the
                -- parent check, not from this number: only the room is booked
                -- here, so the column below it does not climb over the child.
                colY[col] = colY[col] - HOME.rowHeight
            end
        end

        protection.channelsLabel:ClearAllPoints()
        protection.channelsLabel:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[2], colY[2] - 6)
        colY[2] = colY[2] - 28
        for _, row in ipairs(CHANNEL_ROWS) do
            local radio = protection.channelRadios[row.mode]
            radio:ClearAllPoints()
            radio:SetPoint("TOPLEFT", choose, "TOPLEFT", colX[2] + 16, colY[2])
            -- A channel row is indented by 16, so it has 16 px less to write in
            -- than a box of the same column.
            colY[2] = colY[2] - math.max(22,
                radio:FitLabel(protection.checkLabelWidth - 16) + (22 - HOME.checkSize))
        end

        protection.chooseHeight = -math.min(colY[1], colY[2])
        choose:SetSize(innerWidth, protection.chooseHeight)
        return protection.chooseHeight
    end
    protection.layoutChoose(width)

    -- Question 4 ------------------------------------------------------------
    -- Same two pieces as the questions above. The title rides on the number, so
    -- the refresh only ever moves one of the two.
    protection.q4Number = newLabel(parent, "4", FONT_BODY, C.accent)
    protection.q4Title = newLabel(parent, L["Q4_TITLE"], FONT_TITLE, C.ink)
    protection.q4Title:SetPoint("TOPLEFT", protection.q4Number, "TOPRIGHT", 10, 4)
    local thirdWidth = (width - HOME.gutter * 2) / 3
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

    -- The tile IS the button (decisions 142-143): the "Manage" button inside it
    -- is gone and the whole tile opens the drawer. A button sitting in a box
    -- that also reacts to a click is two targets for one destination, and the
    -- smaller of the two was the one that worked.
    --
    -- What replaces the button is what says the tile opens something: a chevron
    -- at the right edge, and the fill lightening under the pointer. Both are
    -- needed -- the chevron is a shape, so the affordance is not carried by a
    -- colour change alone (rule 1 of the section head), and the highlight is
    -- what answers the pointer.
    --
    -- Thin, and laid out along ONE line rather than stacked: a 20 px count, the
    -- name of the list beside it with its detail under it, the chevron at the
    -- far end. 84 px of tile became 46.
    local function newTile(name, titleText, onOpen)
        local tile = CreateFrame("Button", name, parent, "BackdropTemplate")
        tile:SetSize(cardWidth, HOME.tile)
        applyBackdrop(tile, C.tile, C.border)
        tile.count = newLabel(tile, "0", 20, C.accent)
        tile.count:SetPoint("LEFT", tile, "LEFT", 12, 0)
        -- The two lines of text ride on the count rather than on the tile, so a
        -- three-digit list pushes them along instead of running under them.
        tile.title = newLabel(tile, titleText, FONT_DESC, C.ink)
        tile.title:SetPoint("BOTTOMLEFT", tile.count, "RIGHT", 10, 1)
        tile.detail = newLabel(tile, "", FONT_BODY, C.dim)
        tile.detail:SetPoint("TOPLEFT", tile.title, "BOTTOMLEFT", 0, -2)
        -- U+203A, the single right angle quote. Windows-1252, so Friz Quadrata
        -- draws it -- unlike the geometric triangle the duration field used to
        -- ask for, which is why that one is drawn from bars instead.
        tile.chevron = newLabel(tile, "\226\128\186", FONT_SECTION, C.dim)
        tile.chevron:SetPoint("RIGHT", tile, "RIGHT", -12, 0)
        -- One line each, and BOUNDED. A FontString with no width of its own
        -- draws as far as it needs, and what is at the far end of this one is
        -- the chevron: "12 ajoutes / 5 amis Battle.net" runs under it at the
        -- 500 px the grip goes down to. Word wrap is off rather than on, unlike
        -- a card -- the tile is 46 px of exactly two lines, so a third has
        -- nowhere to go and the client cuts the sentence instead of the tile.
        tile.title:SetWordWrap(false)
        tile.detail:SetWordWrap(false)
        -- The room between the count and the chevron, measured rather than
        -- guessed: the count is one to four digits, the two lines ride on it,
        -- and what is left over changes with the size of the lists. 12 of
        -- margin, the count, 10 to the text, then the text, 8 of air, the
        -- chevron and its own 12 of margin.
        function tile:FitText()
            local room = math.max(20, (self:GetWidth() or 0) - 42
                - (self.count:GetStringWidth() or 0)
                - (self.chevron:GetStringWidth() or 0))
            self.title:SetWidth(room)
            self.detail:SetWidth(room)
        end
        tile:SetScript("OnEnter", function(self)
            applyBackdrop(self, C.accentBg, C.accent)
            self.chevron:SetTextColor(unpack(C.accent))
        end)
        tile:SetScript("OnLeave", function(self)
            applyBackdrop(self, C.tile, C.border)
            self.chevron:SetTextColor(unpack(C.dim))
        end)
        tile:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            onOpen()
        end)
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
        -- And the screen again, because the answer is what the bottom of it is
        -- measured from: a longer verdict has to be given its lines -- or the
        -- bar to reach them with -- rather than being written into a layout
        -- already fixed. The pass re-reads the same field, so this cannot come
        -- back round: nothing in it writes to the box.
        if ns.refreshUI then ns.refreshUI() end
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

-- Everything on this screen whose size comes from the window's width, and the
-- heights that fall out of it: a card's description wraps, so what a row of
-- cards measures is a consequence of the width and is settled here, in the one
-- pass that knows it. `protection.rowHeight` is what the refresh below counts in.
applyTabWidth.protection = function()
    -- The last widget the builder makes: the guard means "this screen is
    -- finished", not "it has been started".
    if not protection.testAnswer then return end
    local width = innerWidth()
    local cardWidth = (width - HOME.gutter) / 2
    protection.rowHeight = {
        q1 = sizeCardRow({ protection.q1Strangers, protection.q1Blocked }, cardWidth),
        q2 = sizeCardRow({ protection.q2All, protection.q2Custom }, cardWidth),
        q3 = sizeCardRow({ protection.q3Yes, protection.q3No }, cardWidth),
        q4 = sizeCardRow({ protection.q4.silent, protection.q4.minimal,
            protection.q4.verbose }, (width - HOME.gutter * 2) / 3),
    }
    -- The notes under questions 2 and 3 are sentences, not labels: they wrap, so
    -- they have to be told the width they wrap at.
    protection.q2Note:SetWidth(width)
    protection.q3Note:SetWidth(width)
    -- A tile's two lines are bounded by what the count and the chevron leave
    -- them, so the tile is widened and re-fitted in one go. The counts are the
    -- ones the last refresh wrote, which is what a resize needs: the lists do
    -- not change size because the window did.
    protection.tileAllowed:SetWidth(cardWidth)
    protection.tileAllowed:FitText()
    protection.tileBlocked:SetWidth(cardWidth)
    protection.tileBlocked:FitText()
    -- And the two columns of "I choose": `layoutChoose` is what shares the width
    -- between them, and it answers the height the fold needs, which the refresh
    -- below reads.
    protection.layoutChoose(width)
    -- The two boxes that sit at the screen's own margin instead of in a column.
    -- Automatic trust is the longest label of the home screen -- 86 characters in
    -- French against the 438 px the inner width leaves it at the narrowest
    -- window -- and it has never been in a column, so `layoutChoose` never saw
    -- it. Each is bounded here and each answers the row it needs.
    protection.rowHeight.trust = math.max(HOME.rowHeight,
        protection.trust:FitLabel(width - (HOME.checkSize + 8))
            + (HOME.rowHeight - HOME.checkSize))
    -- The strict box has two homes and therefore two widths: indented under its
    -- parent in the left column of "I choose", at the screen's own margin in
    -- "Everything", where its label runs the whole column -- nothing shares the
    -- row with it any more (decision 162e). The mode is asked here rather than
    -- in the refresh below, because a resize runs this pass AFTER the refresh
    -- has drawn -- a width posted in the refresh is a width the next drag
    -- overwrites.
    -- Indented only where the column it indents into is on screen: in the open
    -- mode the two columns are gone and the box sits at the margin whatever
    -- preset is remembered underneath, so the column's width is not its bound.
    local strictRoom = width - (HOME.checkSize + 8)
    if ns.getScope() ~= "blockedOnly" and ns.getPreset() == "custom" then
        strictRoom = protection.checkLabelWidth - HOME.subIndent
    end
    protection.rowHeight.strict = math.max(HOME.rowHeight,
        protection.strict:FitLabel(strictRoom) + (HOME.rowHeight - HOME.checkSize))
    -- The rules between the questions run the whole column, decision 139, and so
    -- does the dotted one -- which has to be re-dashed rather than stretched:
    -- its length is a number of dashes, not a width.
    for _, rule in ipairs(protection.rules) do rule:SetWidth(width) end
    protection.dottedRule:Layout(width)
    -- The tester's answer is a sentence under the field, not a label beside it:
    -- it runs the whole width, it wraps, and the height the screen is measured
    -- from comes out of this number.
    protection.testAnswer:SetWidth(width)
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
    -- "Enhanced filtering in instances" governs the system lines of ONE of the
    -- boxes beside it: every path it takes goes through `groupInvite`. So in "I
    -- choose", where that box is on screen, it answers to it -- unticking the
    -- parent greys the child and takes the click away from it, which is the
    -- whole of constat D.1. In "Everything" there is no parent to answer to and
    -- the preset blocks group invitations by definition. In the open mode there
    -- is no parent either, and the box is live all the same (decision 167): a
    -- person blocked by a pattern still spams the invite, and its system line
    -- in a locked-down instance is the one residue nothing else reaches.
    local strictParentOn = blockedOnly or (not custom) or filterStored("groupInvite") == true
    protection.strict:SetEnabledState(strictParentOn)
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

    -- One pass, from the top of the screen down. Questions 1 and 2 used to be
    -- placed once at build time and this pass started at question 3; a card
    -- measures its own height now, and a rule has to be dropped between two
    -- questions, so where anything sits is only known here.
    local frame, y = protection.frame, 0
    local function place(widget, offsetY)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y + (offsetY or 0))
    end
    -- A "N Question" row. The title rides on the number, so only one of the two
    -- is ever moved.
    local function stepRow(number)
        place(number, -4)
        y = y - HOME.titleRow
    end
    -- Decision 139: the rule sits exactly halfway through the air between two
    -- questions, so the same gap is left above and below it.
    local ruleIndex = 0
    local function separator()
        ruleIndex = ruleIndex + 1
        y = y - HOME.ruleGap
        place(protection.rules[ruleIndex])
        y = y - HOME.ruleGap
    end

    -- Question 1 ------------------------------------------------------------
    stepRow(protection.q1Number)
    place(protection.q1Strangers)
    protection.q1Blocked:ClearAllPoints()
    protection.q1Blocked:SetPoint("TOPLEFT", protection.q1Strangers, "TOPRIGHT", HOME.gutter, 0)
    y = y - protection.rowHeight.q1
    separator()

    -- Question 2 ------------------------------------------------------------
    stepRow(protection.q2Number)

    -- Decision 163, option A. A section nobody can act on any more shows the
    -- SAME thing whatever is remembered underneath it: the sentence that says
    -- why, the two cards left as witnesses of the answer that was given, and no
    -- detail at all -- not the two columns of boxes, not the sub-box, not the
    -- block of channels, even when the remembered mode is "I choose". The screen
    -- used to show one thing in "Everything" and another in "I choose" while
    -- both were equally dead, which is constat 162h.
    --
    -- The sentence comes FIRST, between the title and the witnesses: it is what
    -- the reader needs before the cards mean anything, and it is where the
    -- validated mock-up puts it.
    protection.q2Note:SetText(blockedOnly and L["Q2_COVERED"] or "")
    if blockedOnly then
        place(protection.q2Note)
        y = y - math.max(NOTE_LINE, protection.q2Note:GetStringHeight() or NOTE_LINE) - 8
    end

    place(protection.q2All)
    protection.q2Custom:ClearAllPoints()
    protection.q2Custom:SetPoint("TOPLEFT", protection.q2All, "TOPRIGHT", HOME.gutter, 0)
    protection.q2All:Refresh()
    protection.q2Custom:Refresh()
    y = y - protection.rowHeight.q2 - 14

    if blockedOnly then
        -- Every detail of question 2 is off screen: the two columns and the
        -- block of channels have nothing to filter here.
        protection.choose:Hide()
        -- What is NOT part of what died: the two boxes that answer question 1.
        -- Automatic trust decides who is allowed, enhanced instance filtering is
        -- the only answer to a blocked person's invitation line in a locked-down
        -- instance (decision 167). Both are set apart under a dotted rule for
        -- that reason -- left against the extinguished block they read as greyed
        -- out too, which is constat 162g -- and both are drawn in plain white.
        protection.dottedRule:Show()
        place(protection.dottedRule)
        -- `padding-top: 8px` under the line: the boxes below are set apart from
        -- the block above, not pushed away from it.
        y = y - protection.dottedRule:GetHeight() - 8
        protection.strict:Show()
        place(protection.strict)
        y = y - protection.rowHeight.strict
    elseif custom then
        protection.strict:Show()
        protection.dottedRule:Hide()
        protection.choose:Show()
        place(protection.choose)
        protection.strict:ClearAllPoints()
        -- Anchored on the very box it depends on rather than on the column plus
        -- a number: an indent written as an offset from somewhere else drifts
        -- away from its parent the day the columns move, and a child that no
        -- longer sits under its parent reads as a row of its own -- which is
        -- exactly how it was read in session.
        --
        -- What it drops by is the height the PARENT'S ROW came to, not the box's:
        -- the box is 18 px whatever its label does, and a parent label folded
        -- over two lines reaches further down than that. Its own x is the
        -- sub-row indent, which is where the parent's label starts, so a folded
        -- label and this box would otherwise share the same column of pixels.
        protection.strict:SetPoint("TOPLEFT", protection.checks.groupInvite,
            "BOTTOMLEFT", HOME.subIndent,
            -((protection.groupInviteRow or HOME.rowHeight) - HOME.checkSize))
        y = y - protection.chooseHeight - 4
    else
        protection.strict:Show()
        protection.dottedRule:Hide()
        protection.choose:Hide()
        place(protection.strict)
        y = y - protection.rowHeight.strict
    end
    protection.strict:Refresh()

    -- Under the strict box in all three modes: this line stays at the screen's
    -- own left margin whatever happens above it, because it answers question 1
    -- and not question 2.
    place(protection.trust)
    protection.trust:Refresh()
    y = y - protection.rowHeight.trust
    separator()

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

    stepRow(protection.q3Number)

    -- Option A again, and the same order: the sentence that says why, then the
    -- two cards as witnesses, then nothing. What disappears here is the delay --
    -- "un meme message ne reapparait qu'apres" is a detail of an answer that
    -- cannot be given while the channels are all filtered already.
    --
    -- Nothing is reserved for the sentence: it is on screen only while the
    -- answer is decided elsewhere, exactly like question 2's.
    protection.q3Note:SetText(covered and L["ANTISPAM_COVERED"] or "")
    if covered then
        place(protection.q3Note)
        -- Measured rather than assumed: the sentence wraps over one line at
        -- 900 px and over two at 500, and everything below it hangs from this.
        y = y - math.max(NOTE_LINE, protection.q3Note:GetStringHeight() or NOTE_LINE) - 8
    end

    place(protection.q3Yes)
    protection.q3No:ClearAllPoints()
    protection.q3No:SetPoint("TOPLEFT", protection.q3Yes, "TOPRIGHT", HOME.gutter, 0)
    protection.q3Yes:Refresh()
    protection.q3No:Refresh()
    y = y - protection.rowHeight.q3

    if covered then
        protection.q3IntervalLabel:Hide()
        protection.q3Interval:Hide()
    else
        protection.q3IntervalLabel:Show()
        protection.q3Interval:Show()
        y = y - 8
        -- The field rides on the right of its own label rather than at a fixed
        -- offset: the sentence is not the same length in the two locales, and a
        -- number picked for one of them cuts the other.
        place(protection.q3IntervalLabel, -6)
        protection.q3Interval:ClearAllPoints()
        protection.q3Interval:SetPoint("LEFT", protection.q3IntervalLabel, "RIGHT", 10, 0)
        protection.q3Interval:Refresh()
        y = y - HOME.rowHeight - 4
    end
    separator()

    stepRow(protection.q4Number)
    -- The first card is placed against the screen, the two others against the
    -- card before them -- the shape questions 1 and 2 already have. Placed at
    -- `PAD + index * (thirdWidth + gutter)` they carried a copy of the width
    -- inside their own position, so the width pass could not widen them without
    -- moving them too, and the same layout would have been written a second
    -- time. Chained, widening a card carries the next one along, and the width
    -- itself is `applyTabWidth.protection`'s, above, for every screen.
    local previous = nil
    for _, key in ipairs({ "silent", "minimal", "verbose" }) do
        local card = protection.q4[key]
        if previous then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", previous, "TOPRIGHT", HOME.gutter, 0)
        else
            place(card)
        end
        card:Refresh()
        previous = card
    end
    y = y - protection.rowHeight.q4
    separator()

    stepRow(protection.q5Number)
    place(protection.tileAllowed)
    protection.tileBlocked:ClearAllPoints()
    protection.tileBlocked:SetPoint("TOPLEFT", protection.tileAllowed, "TOPRIGHT", HOME.gutter, 0)

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
    -- After the counts and never before them: the two lines are bounded by what
    -- the count leaves them, and a list that has just grown from 9 to 10 pushes
    -- them one digit along.
    protection.tileAllowed:FitText()
    protection.tileBlocked:FitText()
    y = y - HOME.tile - HOME.tileGap

    place(protection.testLabel)
    protection.testInput:ClearAllPoints()
    protection.testInput:SetPoint("TOPLEFT", protection.frame, "TOPLEFT", PAD + 130, y + 4)

    -- Read again, from the name still in the field. The answer is a read of the
    -- two lists and this is the pass every write ends on -- adding a name,
    -- removing one, undoing, closing the drawer -- so a tested pseudo used to
    -- keep an answer the lists had stopped agreeing with, and the only way to
    -- see the new one was to add or remove a letter. Before the measurement
    -- below and never after it: a height taken from the sentence that was there
    -- a moment ago is the height of the wrong sentence.
    if protection.testInput and ns.RefreshTestAnswer then
        ns.RefreshTestAnswer(protection.testInput:GetText())
    end
    -- The field hangs 4 px above the line its label sits on and is 24 tall, so
    -- what the row really ends at is `testField` under `y` -- and that edge is
    -- the last thing on the screen while nobody has typed a name. The window is
    -- cut CONTENT_BOTTOM under it (decision 162d), so the eight pixels the row
    -- keeps for the answer are only spent when there IS an answer.
    y = y - HOME.testField

    -- The answer under the field, over the whole width, and MEASURED.
    --
    -- Beside the field it had `innerWidth() - 360` to wrap into -- 104 px at the
    -- smallest window, which does not hold "Pseudo-Royaume" on a line at all --
    -- and the row reserved a flat 40 px for a sentence that takes as many lines
    -- as the column leaves it. A blocked guild mate's verdict ran to seven lines
    -- there, and the screen answered the height it had not measured: the sentence
    -- fell off the bottom of a window whose content was exactly its own viewport,
    -- so there was no bar to reach it with either. Measured like the note under
    -- question 3, and nothing is reserved while the field is empty -- the answer
    -- only exists during a test, and A.2 asks the minimum height to hold the home
    -- screen, not a sentence that is not on it.
    place(protection.testAnswer, -HOME.testGap)
    if (protection.testAnswer:GetText() or "") ~= "" then
        y = y - HOME.testGap
            - math.max(NOTE_LINE, protection.testAnswer:GetStringHeight() or NOTE_LINE)
    end

    -- The height of what was DRAWN, and nothing more. The screen used to add a
    -- margin of its own on top of the one the window already keeps under the
    -- content, so the window opened on 48 px of nothing under the tester and a
    -- floor that had drifted above the screen's real need put another 34 on top
    -- of that (constat 162d). One margin, kept in one place, and it is the
    -- mock-up's.
    return -y
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

-- The order the tab is actually drawn in. Decision 166: it is decided when the
-- tab is opened and does not move again while it is on screen -- counts and
-- times go on living in place, and somebody who was not in the list yet comes
-- in at the top and stays where they came in. Sorting on every refresh is
-- constat 165.2: unfolding an entry rebuilds the list, and a spam still running
-- re-sorted it under the reader, so the line they had just clicked left from
-- under the cursor.
--
-- `journal.order` is the frozen order, and nil means "decide it now": opening
-- the tab and closing the window both clear it, which is what makes coming back
-- give a fresh order. Emptying the journal needs no clearing of its own: an
-- empty list writes an empty order on the way out, so whoever is blocked after
-- "Clear the journal" opens a fresh one rather than being slotted back into the
-- place of somebody who is no longer in the list.
local function orderedJournalGroups()
    local fresh = groupLogsByName()
    if journal.order then
        local rank = {}
        for index, name in ipairs(journal.order) do rank[name] = index end
        local kept, arrived = {}, {}
        for _, group in ipairs(fresh) do
            local into = rank[group.name] and kept or arrived
            into[#into + 1] = group
        end
        table.sort(kept, function(a, b) return rank[a.name] < rank[b.name] end)
        -- `fresh` is most recent first, so newcomers arrive in that order, ahead
        -- of everyone already listed. They are written into the frozen order on
        -- the way out: without that, the next newcomer would push this one back
        -- down, which is the movement the decision is about.
        for _, group in ipairs(kept) do arrived[#arrived + 1] = group end
        fresh = arrived
    end
    journal.order = {}
    for index, group in ipairs(fresh) do journal.order[index] = group.name end
    return fresh
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
-- The screen's own metrics, in one table for the same reason the home screen
-- keeps `HOME`: this chunk is at Lua's ceiling of 200 registers.
--
-- `listMin` is a FLOOR and not a height (constat 165.1). The list was built 300
-- px tall and the button row pinned 370 px down whatever the window measured,
-- so in a window twice as tall the Journal was a short list with the emptiness
-- spread out under the buttons. The list takes what is left between its own top
-- and the row of buttons now, and the buttons ride at its bottom edge, which
-- puts them at the bottom of the window and keeps them there through a drag.
local JOURNAL = {
    rowOne = -30, rowTwo = -52,
    listTop = -60, listMin = 120,
    buttonRow = 24, buttonGap = 12,
}
JOURNAL.rowDrop = JOURNAL.rowOne - JOURNAL.rowTwo

-- Where the list ends and where the buttons begin. One function, because two
-- passes change the answer and neither of them knows what the other did: how
-- far the list starts down is the width pass's business -- one row of boxes at
-- the top of the screen or two -- and how much room there is below is the
-- window's. The list is what is left between them, never less than its floor,
-- and the buttons hang from its bottom edge rather than from a number.
local function layoutJournalList()
    if not journal.scroll or not journal.frame then return end
    local top = -(JOURNAL.listTop - (journal.drop or 0))
    local height = math.max(JOURNAL.listMin,
        (journal.viewport or MIN_HEIGHT) - top - JOURNAL.buttonGap - JOURNAL.buttonRow - PAD)
    journal.scroll:ClearAllPoints()
    journal.scroll:SetPoint("TOPLEFT", journal.frame, "TOPLEFT", PAD, -top)
    journal.scroll:SetViewportSize(innerWidth(), height)
    journal.clearBtn:ClearAllPoints()
    journal.clearBtn:SetPoint("TOPLEFT", journal.scroll, "BOTTOMLEFT", 0, -JOURNAL.buttonGap)
end

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
    journal.enable:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, JOURNAL.rowOne)

    journal.showMsg = newCheck(parent, "SanctuaryJournalShowMessages", L["LOGS_SHOW_MSG"], nil,
        function() return SanctuaryDB and SanctuaryDB.uiSettings.showMessageColumn == true end,
        function(value) SanctuaryDB.uiSettings.showMessageColumn = value end)
    journal.showMsg:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + SHOW_MSG_X, JOURNAL.rowOne)

    journal.scroll = newScroll(parent, "SanctuaryJournalScroll", width, JOURNAL.listMin)
    journal.rows = {}
    journal.rowPool = {}

    -- Named, the two of them: one is the anchor the other two hang from, and
    -- "the buttons sit at the bottom of the window" is not a property a test can
    -- prove through a widget it cannot reach. The third rides on the second.
    journal.clearBtn = newButton(parent, "SanctuaryJournalClearBtn", L["LOGS_CLEAR_BTN"],
        140, JOURNAL.buttonRow, function()
            StaticPopup_Show("SANCTUARY_CLEAR_LOG")
        end, true)
    journal.copyBtn = newButton(parent, nil, L["LOGS_COPY_BTN"], 140, JOURNAL.buttonRow, function()
        ns.ShowTextWindow(L["LOGS_HEADER"], buildJournalText())
    end)
    journal.expandBtn = newButton(parent, "SanctuaryJournalExpandBtn", L["LOGS_EXPAND_ALL"],
        120, JOURNAL.buttonRow, function()
            allExpanded = not allExpanded
            wipe(expandedGroups)
            if ns.refreshUI then ns.refreshUI() end
        end)
    -- The row is built once and never moved again: the list is the only thing
    -- that changes height, and the three buttons hang from its bottom edge.
    journal.copyBtn:SetPoint("LEFT", journal.clearBtn, "RIGHT", 10, 0)
    journal.expandBtn:SetPoint("LEFT", journal.copyBtn, "RIGHT", 10, 0)
    layoutJournalList()
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
        sameRow and JOURNAL.rowOne or JOURNAL.rowTwo)
    -- What the second row takes, the list gives back: it starts lower AND ends
    -- at the same place, so the Clear / Copy / Expand row hanging under it stays
    -- where it is and the screen keeps the height it reports.
    journal.drop = sameRow and 0 or JOURNAL.rowDrop
    layoutJournalList()
    -- The pool as well as the live rows: a pooled row is handed out with the
    -- current width, but it is still a frame carrying a size, and leaving stale
    -- ones behind would make "no row is wider than the screen" true only for the
    -- rows that happen to be visible.
    for _, list in ipairs({ journal.rows, journal.rowPool }) do
        for _, row in ipairs(list) do row:SetWidth(width - 10) end
    end
end

-- The list fills whatever is left under it, so it is sized where the room is
-- known: the viewport is what the window measures and a screen does not. Same
-- rule as the diagnostics columns, and the same reason -- constat 165.1 is what
-- a list built at a fixed 300 px looks like in a window twice that tall.
applyTabHeight.journal = function(viewport)
    journal.viewport = viewport
    layoutJournalList()
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
    local groups = orderedJournalGroups()
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

    -- The list fills what it is given and the buttons ride at its bottom edge,
    -- so what this screen asks for is only its floor: the boxes above the list,
    -- the shortest list it may be squeezed to, and the row of buttons under it.
    -- `applyTabHeight` hands it everything beyond that.
    return -(JOURNAL.listTop - (journal.drop or 0))
        + JOURNAL.listMin + JOURNAL.buttonGap + JOURNAL.buttonRow
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
-- The header line and the three buttons above the two columns, and the shortest
-- a column is ever drawn. Everything below the buttons is the columns' room, so
-- these two numbers are the whole of "the screen uses the window" (constat C.1).
local DIAG_COLUMN_TOP, DIAG_MIN_COLUMN = 60, 120

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

    local listScroll = newScroll(parent, "SanctuaryDiagListScroll", 320, DIAG_MIN_COLUMN)
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -DIAG_COLUMN_TOP)
    diagnostics.listScroll = listScroll
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
            -- 90 px of field for "SanctuaryTest": what a person reads beside
            -- "Simuler une invitation" has to be the start of the value.
            input:ShowFromStart()
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

    local resultScroll = newScroll(parent, "SanctuaryDiagResultScroll", width - 340,
        DIAG_MIN_COLUMN)
    resultScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 330, -DIAG_COLUMN_TOP)
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

-- Both columns take the whole of what is left under the buttons. They were built
-- 300 px tall and nothing ever revisited that, so in a window twice as tall the
-- screen was a band of buttons and two half-height boxes with the rest of the
-- window empty under them -- "on doit scroll dans une demi modale" (constat
-- C.1). Sized here rather than in the refresh because the viewport is what the
-- window knows and a screen does not.
applyTabHeight.diagnostics = function(viewport)
    if not diagnostics.resultScroll or not diagnostics.listScroll then return end
    local height = math.max(DIAG_MIN_COLUMN,
        (viewport or DIAG_MIN_COLUMN) - DIAG_COLUMN_TOP - PAD)
    diagnostics.listScroll:SetViewportSize(320, height)
    diagnostics.resultScroll:SetViewportSize(innerWidth() - 340, height)
    resizeDiagnosticResults()
end

refreshTab.diagnostics = function()
    ns.RefreshStranded()
    -- The two columns fill whatever they are given, so what this screen asks for
    -- is its own floor -- the band of buttons above them and the shortest column
    -- it may be reduced to -- and `applyTabHeight` hands it the rest. Asking for
    -- the height the WINDOW opens at made the screen taller than the viewport on
    -- a client that cannot hold it, so the columns filled the window and a bar
    -- came up beside them at the same time.
    return DIAG_COLUMN_TOP + DIAG_MIN_COLUMN
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

-- Where to look to know whether the name a green sentence named is still
-- listed. Which list it went into is something the add function already says, so
-- the answer is worked out once, here, instead of being carried down from each
-- of the three field-and-button pairs.
local function entryStillListed(addFn)
    if addFn == ns.addAllowed then
        return function(key)
            return (SanctuaryDB and SanctuaryDB.manualWhitelist or {})[key] ~= nil
        end
    elseif addFn == ns.addBlocked then
        return function(key)
            return (SanctuaryDB and SanctuaryDB.blockedNames or {})[key] ~= nil
        end
    elseif addFn == ns.addPattern then
        return function(key)
            for _, existing in ipairs(SanctuaryDB and SanctuaryDB.keywords or {}) do
                if existing == key then return true end
            end
            return false
        end
    end
end

-- The one submission path for the three field-and-button pairs. There were six
-- bodies -- one on Enter and one on the button, per pair -- doing the same
-- things, which is this release's whole subject, in this file: two paths that
-- have to be corrected twice. Adding the refusal line to six of them is exactly
-- the mistake the release is about.
local function submitEntry(box, addFn)
    local text = box:GetText()
    box:SetText("")
    box:RefreshHint()
    local ok, key, data, refusal, displaced = addFn(text)
    local sentence = refusal and REFUSAL_TEXT[refusal]
    if sentence then
        box:SayNo(sentence())
    elseif ok then
        -- Decision 167c: the field says yes as well as no. The name it repeats
        -- is the one the chip will carry -- `qualifiedDisplayName`, the same
        -- reading the panels use -- so "Kadaj" typed and "Kadaj-Ysondre" listed
        -- is not a person wondering whether they added the right character. A
        -- pattern has no realm to add and comes back through it untouched.
        box:SayYes(string.format(L["ADDED_OK"],
            ns.qualifiedDisplayName(key, type(data) == "table" and data.displayName or nil)
                or tostring(key)), key, entryStillListed(addFn))
    else
        -- Refused with no sentence of its own -- an empty field, a duplicate --
        -- and the last answer goes rather than standing over a new gesture.
        box:ClearNote()
    end
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

-- Realm friends are not here, decision 127: WoW 12.1 has no way left to add a
-- friend who is not a Battle.net account, so the group was a header reading
-- "(0)" for everyone, and a heading nobody can ever fill is a question the
-- reader has to answer for themselves. The MECHANISM stays -- `C_FriendList`
-- still answers, and an old character friend left in an account's list keeps the
-- native behaviour and is still named by "Test a pseudo" -- only the group is
-- off the panel.
local AUTO_GROUP_LABELS = {
    bnet = "WL_SOURCE_BNET", guild = "WL_SOURCE_GUILD", trust = "WL_SOURCE_TRUST",
}
local AUTO_GROUP_ORDER = { "bnet", "guild", "trust" }

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

    -- The field first, its labels under it: the same order as the two fields of
    -- the blocked panel, and the same distance (`LIST_LABELS_GAP`). One line of
    -- room is kept under the field whether a sentence is showing or not, so the
    -- ordinary answers move nothing; a sentence that folds over more than that
    -- line takes the room it actually draws and gives it back when it clears.
    -- The reserve is a floor, not a promise that every answer fits it.
    local y = -40
    panel.addInput:ClearAllPoints()
    panel.addInput:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    panel.addBtn:ClearAllPoints()
    panel.addBtn:SetPoint("LEFT", panel.addInput, "RIGHT", 8, 0)
    y = y - panel.addInput:LabelsGap()

    y = layoutChips(child, manual, y, function(item)
        local ok, key, data = ns.removeAllowed(item.key)
        if not ok then return end
        offerUndo(item.label, function() ns.restoreAllowed(key, data) end)
        if ns.refreshUI then ns.refreshUI() end
    end)
    y = y - 10

    panel.autoSection:ClearAllPoints()
    panel.autoSection:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    -- Counts what the section shows, and only that: a total including a group
    -- that is not on the panel is a number nobody can add up.
    local autoTotal = 0
    for _, source in ipairs(AUTO_GROUP_ORDER) do
        autoTotal = autoTotal + (counts.allowed[source] or 0)
    end
    panel.autoSection.count:SetText("(" .. tostring(autoTotal) .. ")")
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

    for _, source in ipairs(AUTO_GROUP_ORDER) do
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
    -- One line of room, and more while a sentence needs more: this is the one
    -- field that can answer with the Battle.net refusal, which is longer than a
    -- line at the note width in both languages, and what sits below is the first
    -- row of labels, which a second line would otherwise lie over.
    y = y - panel.nameInput:LabelsGap()

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
    y = y - panel.patternInput:LabelsGap()

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
    -- Before the panels measure themselves, so a sentence taken off here gives
    -- its room back on this same pass rather than one redraw later.
    for _, panel in pairs(panels) do
        if type(panel) == "table" then
            for _, key in ipairs(LIST_INPUT_KEYS) do
                local box = panel[key]
                if box and box.ForgetStaleNote then box:ForgetStaleNote() end
            end
        end
    end
    if openPanel == "allowed" then
        refreshAllowedPanel(force)
    elseif openPanel == "blocked" then
        refreshBlockedPanel(force)
    end
end

-- What an add field calls when its sentence appears or goes: the room under the
-- field follows the sentence, so the panel has to be laid out again. It goes
-- through the namespace rather than a forward local because the fields are built
-- two sections above this one and this chunk is at Lua's ceiling of 200
-- registers.
function ns.redrawOpenPanel()
    refreshOpenPanel(true)
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
    -- Called from the window's own OnSizeChanged as well as from the refresh, so
    -- it has to survive being asked before the strip exists.
    if not tabBar then return end
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
    -- Decision 140, "2 barre en haut": the tabs sit INSIDE the window, in one
    -- strip that runs its whole width just under the title bar, on every screen.
    -- The current one is filled with the accent tint and underlined in accent
    -- along its bottom edge, towards the content it opens; the others are grey
    -- on the strip's own fill. No border, no corner: the strip IS the frame, and
    -- decision 140 refused the rounded segment for not being "fidele au reste".
    --
    -- `padding: 8px 17px` around a label measured in BYTES, which over-estimates
    -- an accented French word and never under-estimates it -- the safe direction
    -- for a width. Five tabs at that padding come to 522 px in French, more than
    -- the 500 px the window may be dragged down to, so the row is scaled to fit
    -- when it has to: a Diagnostics tab hanging off the right edge of the strip
    -- is a tab nobody can click, and there is nowhere for it to wrap to.
    --
    -- The strip is inset by the window's border, so what the row has to fit into
    -- is the strip and not the window: measured against the window, the last tab
    -- ran two pixels under the outline.
    local stripWidth = frameWidth - FRAME_EDGE * 2
    local widths, total = {}, 0
    for index, def in ipairs(visible) do
        widths[index] = math.max(70, (#L[def.labelKey] * 8) + 34)
        total = total + widths[index]
    end
    if total > stripWidth and total > 0 then
        for index = 1, #widths do
            widths[index] = math.floor(widths[index] * stripWidth / total)
        end
    end
    local x = 0
    for index, def in ipairs(visible) do
        local btn = tabButtons[def.key]
        local current = (def.key == activeTab)
        btn:SetSize(widths[index], TABBAR_HEIGHT - TAB_RULE * 2)
        btn:ClearAllPoints()
        -- Under the strip's top rule and above its bottom one, so neither is
        -- broken where a tab sits: the row is what lies BETWEEN the two lines.
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", x, -TAB_RULE)
        x = x + widths[index]
        -- A fill and nothing else: `applyBackdrop` given no border colour asks
        -- for no edge at all, so the strip stays one continuous bar with the
        -- current tab tinted inside it.
        applyBackdrop(btn, current and C.tabOn or C.tabBar)
        btn.label:SetTextColor(unpack(current and C.ink or C.dim))
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

-- The room the client actually has. The bounds above are the design's, measured
-- on the home screen; how many of those units a screen holds is decided by the
-- UI scale -- 768 on a default Retail setup, more when the scale is lowered --
-- and a window whose MINIMUM is taller than the screen is a window nobody can
-- reach the bottom of, whatever the grip allows. So the bounds are asked for and
-- the screen has the last word: where it cannot hold them, the content scrolls,
-- which is what the scroll area is for.
--
-- What has to be reserved is a breathing edge and nothing else, now that the
-- tabs are a strip INSIDE the window (decision 140). The old strip hung below
-- the frame's bottom edge and the window opens on SetPoint("CENTER") -- whatever
-- room is left over is split evenly above and below, so half of a reserve meant
-- for the bottom was spent on the top and the overhang had to be carried twice.
-- Nothing hangs out of the frame any more, and SetClampedToScreen covers the
-- rest, so what is kept is the edge itself, at both ends.
local SCREEN_EDGE = 10
local SCREEN_MARGIN, SCREEN_FLOOR = 2 * SCREEN_EDGE, 300
local function fitToScreen(frameHeight)
    local available = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(available) ~= "number" or available <= 0 then return frameHeight end
    return math.min(frameHeight, math.max(SCREEN_FLOOR, available - SCREEN_MARGIN))
end

-- What the grip is allowed to do, in height. The screen brings the CEILING down
-- to what it holds; the floor stays the design's, so there is always a travel
-- between the two. Applying the screen to BOTH bounds is what took the vertical
-- resize away: on any screen of 954 units or less the two collapsed onto the
-- same number and the grip only moved sideways. The floor follows the screen in
-- the one case where it would otherwise cross the ceiling -- a screen too short
-- to hold even the floor -- because bounds handed over inverted are bounds the
-- client is free to read either way round.
local function heightBounds()
    local maxHeight = fitToScreen(MAX_FRAME_HEIGHT)
    return math.min(GRIP_MIN_FRAME_HEIGHT, maxHeight), maxHeight
end

-- Posted again on every refresh, not once at build time: the bounds are read off
-- the screen, and the screen changes under the window when the UI scale does.
local function applyResizeBounds()
    if not mainFrame then return end
    local minHeight, maxHeight = heightBounds()
    -- Both axes, decision 98. Under pcall because SetResizeBounds is the Retail
    -- spelling and a missing method must not take the window down with it.
    pcall(mainFrame.SetResizeBounds, mainFrame,
        MIN_FRAME_WIDTH, minHeight, MAX_FRAME_WIDTH, maxHeight)
end

local function applyViewport(frameHeight, width)
    if not contentScroll or not contentFrame then return end
    -- The live width, taken before anything measures itself: `innerWidth` and
    -- `panelWidth` read it, and the whole point of the pass is that they answer
    -- for the window as it is now, not as it opened.
    frameWidth = math.min(MAX_FRAME_WIDTH,
        math.max(MIN_FRAME_WIDTH, width or frameWidth))
    local viewport = math.max(120, (frameHeight or MIN_FRAME_HEIGHT) - CONTENT_TOP - CONTENT_BOTTOM)
    contentScroll:SetSize(frameWidth, viewport)
    local contentHeight = math.max(fittedNeed, viewport)
    contentFrame:SetWidth(frameWidth)
    contentFrame:SetHeight(contentHeight)
    for _, frame in pairs(tabFrames) do frame:SetWidth(frameWidth) end
    local active = tabFrames[activeTab]
    if active then active:SetHeight(contentHeight) end
    if undoLine then
        undoLine:SetWidth(innerWidth())
        layoutUndoLine()
    end
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
    -- And what a screen can only know once the window has been measured: the
    -- viewport it actually has. Same rule as the widths -- every screen, not the
    -- one on show.
    for _, applyHeightOf in pairs(applyTabHeight) do applyHeightOf(viewport) end
    contentScroll:RefreshBar()
    -- And the strip of tabs, which shares the width with nothing else: five
    -- French labels at the mock-up's padding are wider than the narrowest window,
    -- so what the row does about that has to be redone on every pixel of a drag
    -- rather than only when the button is let go.
    layoutTabs()
    -- The panels are not inside the content area, so nothing above resizes them:
    -- they answer to the window itself, on the same pass.
    applyPanelViewport(frameHeight)
end

local function applyHeight(height)
    if not mainFrame then return end
    -- `resolveWidth` refreshes `manualSize` from SavedVariables on the way past,
    -- which is what the height below reads too.
    local width = resolveWidth()
    -- What the screen on show actually drew, which is what the content area has
    -- to be able to reach -- and nothing more. Floored at the height the window
    -- opens at, a screen shorter than its window was handed a content area
    -- taller than the viewport: About came up with a bar beside it and 190 px of
    -- nothing to scroll through (constat G.4, on a client where the window is
    -- cut down to the screen).
    fittedNeed = height or 0
    local needed = math.max(MIN_HEIGHT, fittedNeed)
    local frameHeight
    if manualSize then
        -- A settings file written before the bounds existed -- or before the
        -- width was ever applied -- can carry anything at all, so this is
        -- clamped exactly like the width, and to the bounds the GRIP has: a
        -- remembered size is where a person left the grip, and clamping it to
        -- the opening height would undo the drag on the next opening.
        frameHeight = manualSize[2] or GRIP_MIN_FRAME_HEIGHT
        frameHeight = math.min(MAX_FRAME_HEIGHT, math.max(GRIP_MIN_FRAME_HEIGHT, frameHeight))
    else
        local bounded = math.min(MAX_HEIGHT, needed)
        frameHeight = bounded + CONTENT_TOP + CONTENT_BOTTOM
    end
    frameHeight = fitToScreen(frameHeight)
    applyResizeBounds()
    mainFrame:SetSize(width, frameHeight)
    applyViewport(frameHeight, width)
end

local function selectTab(key)
    if not isTabVisible(tabDefByKey(key)) then return end
    -- An open list belongs to the screen it was opened on: it draws over
    -- everything, so leaving it up would float eight durations over the Journal.
    closeOpenDropdown()
    -- Changing screen closes the panel rather than being refused. The strip is
    -- inside the window now and the veil covers it, so this is not the path a
    -- click normally takes any more -- but a tab can still be selected from
    -- code (the debug tab disappearing is one), and a list of allowed names
    -- floating over the Journal is a state the design never had.
    ns.ClosePanel()
    -- Opening the Journal is what decides its order (decision 166): while the
    -- tab is on screen no line changes place, and coming back into it is the
    -- gesture that asks for a fresh one. Clicking the tab you are already on is
    -- not coming back into it -- nothing was ever left -- and re-sorting there
    -- is exactly the movement under the reader that constat 165.2 reported.
    if key == "journal" and activeTab ~= "journal" then journal.order = nil end
    activeTab = key
    -- The scroll frame is one frame for the five screens, so its offset belongs
    -- to none of them: a Journal read to the bottom left About showing its own
    -- bottom -- and About is shorter than the window, so there was no bar and no
    -- range to scroll back with (constat G.4). Every screen opens at its top.
    if contentScroll then
        contentScroll.offset = 0
        contentScroll:SetVerticalScroll(0)
    end
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
    -- The width first, before a single screen measures itself -- the strip of
    -- tabs included, which sizes its row against it. `applyHeight` applies it
    -- further down, but by then the screen has already been drawn.
    frameWidth = resolveWidth()
    layoutTabs()
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
            for _, key in ipairs(LIST_INPUT_KEYS) do
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
    -- Closing the window is leaving the Journal: reopening it on that tab is a
    -- fresh reading, and a fresh reading gets a fresh order.
    journal.order = nil
end

local function createMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "SanctuaryMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(frameWidth, fitToScreen(MIN_FRAME_HEIGHT))
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetResizable(true)
    applyResizeBounds()
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()
    applyBackdrop(mainFrame, C.panel, C.border, FRAME_EDGE)

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
    --
    -- A fill and no edge (decision 162b). The bar used to carry a border on all
    -- four of its sides, and the one along the BOTTOM landed against the strip
    -- of tabs' own top rule: two hairlines end to end, so the line above the
    -- tabs was twice the line below them. Dropping the edge takes the window's
    -- outline off the top of the bar with it, so the bar is inset by the
    -- window's own two-pixel border instead -- which is where the mock-up draws
    -- it, inside the frame rather than over it. It still ends at
    -- -HEADER_HEIGHT: the strip hangs from that number.
    local header = CreateFrame("Frame", "SanctuaryTitleBar", mainFrame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", FRAME_EDGE, -FRAME_EDGE)
    header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -FRAME_EDGE, -FRAME_EDGE)
    header:SetHeight(HEADER_HEIGHT - FRAME_EDGE)
    applyBackdrop(header, C.header, nil)

    -- The title bar carries the two window gestures, decision 136 -- "comme ca
    -- on garde un seul comportement sur le drag n drop". Dragging it moves the
    -- window, exactly as dragging the body does; double-clicking it puts the
    -- window back to the size it opens at, which is what the grip's own
    -- double-click used to do.
    --
    -- The move goes through RegisterForDrag rather than OnMouseDown, and that is
    -- what "sans declencher un deplacement au passage" rests on: the client
    -- fires OnDragStart only once the mouse has actually travelled, so neither
    -- click of a double-click starts a move.
    --
    -- The other side of that same delay is why the pair is counted on RELEASE.
    -- At the moment of the press, nobody knows yet whether it is a click or the
    -- beginning of a move, and deciding there once undid the size somebody had
    -- set as they took hold of the window again to move it.
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function(self)
        -- A drag is not half of a double-click, in either order. Marking the
        -- gesture keeps the release that ends it from arming a pair; clearing
        -- lastClick covers the other order, a flick of the window followed by a
        -- click inside the same 0.4 s -- which sent the window somebody had
        -- just placed back to its opening size.
        self.dragging = true
        self.lastClick = 0
        mainFrame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        local point, _, _, x, y = mainFrame:GetPoint()
        if SanctuaryDB then SanctuaryDB.uiPosition = { point = point, x = x, y = y } end
    end)
    header.lastClick = 0
    header.dragging = false
    header:SetScript("OnMouseDown", function(self, button)
        -- The press decides nothing; it only opens a gesture. The mark is
        -- cleared HERE rather than at the end of a move, because a press always
        -- comes before the release it belongs to -- whereas nothing says a move
        -- ends with a release this frame is told about.
        if button ~= "LeftButton" then return end
        self.dragging = false
    end)
    header:SetScript("OnMouseUp", function(self, button)
        -- The left button and nothing else: decision 136 gives this bar one
        -- gesture, and a right double-click is a menu somewhere else in the
        -- game, not a request to resize anything. The client always says which
        -- button it was, so an unnamed press is nobody's press.
        if button ~= "LeftButton" then return end
        if self.dragging then
            self.dragging = false
            self.lastClick = 0
            return
        end
        local now = GetTime()
        if now - (self.lastClick or 0) < 0.4 then
            self.lastClick = 0
            -- The SIZE only. Where the window sits is a separate gesture and a
            -- separate memory, and a person who has moved the window and wants
            -- it back at its normal size has not asked for it to jump to the
            -- middle of the screen.
            manualSize = nil
            if SanctuaryDB then SanctuaryDB.uiSize = nil end
            ns.refreshUI()
            return
        end
        self.lastClick = now
    end)

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

    -- The strip of tabs, between the title bar and the content (decision 140).
    -- Built before the content area so the buttons it holds are created before
    -- the first `layoutTabs`, and given the strip's own fill so an inactive tab
    -- -- which draws nothing of its own -- reads as part of one bar.
    tabBar = CreateFrame("Frame", "SanctuaryTabBar", mainFrame, "BackdropTemplate")
    tabBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", FRAME_EDGE, -HEADER_HEIGHT)
    tabBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -FRAME_EDGE, -HEADER_HEIGHT)
    tabBar:SetHeight(TABBAR_HEIGHT)
    -- A fill and no edge. A backdrop border would draw the two rules below AND a
    -- hairline down each side of the strip, just inside the window's own two
    -- pixels -- a second outline where the mock-up has one. The two lines the
    -- strip does carry are drawn as what they are, so both are the same pixel
    -- and both run the whole strip whatever the tabs do.
    applyBackdrop(tabBar, C.tabBar, nil)
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local rule = tabBar:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(TAB_RULE)
        rule:SetPoint(edge .. "LEFT", tabBar, edge .. "LEFT", 0, 0)
        rule:SetPoint(edge .. "RIGHT", tabBar, edge .. "RIGHT", 0, 0)
        rule:SetColorTexture(unpack(C.border))
        tabBar[edge == "TOP" and "topRule" or "bottomRule"] = rule
    end

    contentScroll = newScroll(mainFrame, "SanctuaryContentScroll", frameWidth, MIN_HEIGHT)
    contentScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -CONTENT_TOP)
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
    -- Silently: clicking beside the drawer is a way out of it, not the closing
    -- of a window. The "X" in the header keeps its sound -- that one does close
    -- the window, and it is the gesture the sound belongs to.
    panelVeil:SetScript("OnMouseDown", function()
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

        local btn = CreateFrame("Button", "SanctuaryTab_" .. def.key, tabBar, "BackdropTemplate")
        btn:SetSize(80, TABBAR_HEIGHT - TAB_RULE * 2)
        btn.label = newLabel(btn, L[def.labelKey], FONT_DESC, C.dim, "CENTER")
        -- Centred on what is left once the underline has taken its two pixels,
        -- so the word does not sit visibly low in the current tab.
        btn.label:SetPoint("CENTER", btn, "CENTER", 0, 1)
        btn.underline = btn:CreateTexture(nil, "OVERLAY")
        btn.underline:SetHeight(TAB_UNDERLINE)
        btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
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
    -- The strip takes the mouse for its own tooltip, which is where the whole of
    -- a cut sentence can be read.
    undoLine:EnableMouse(true)
    undoLine.label = newLabel(undoLine, "", FONT_BODY, C.soft)
    undoLine.label:SetPoint("LEFT", undoLine, "LEFT", UNDO_INSET, 0)
    -- One line, cut with an ellipsis at the width `layoutUndoLine` gives it.
    undoLine.label:SetWordWrap(false)
    undoLine.button = newButton(undoLine, nil, L["UNDO_BTN"], UNDO_BTN_WIDTH, 18, function()
        if undoState and undoState.restore then undoState.restore() end
        clearUndo()
        if ns.refreshUI then ns.refreshUI() end
    end)
    undoLine.button:SetPoint("RIGHT", undoLine, "RIGHT", -UNDO_INSET, 0)
    layoutUndoLine()
    undoLine:Hide()

    -- Grip: ONE gesture, and only one -- it drags, and that is all it does
    -- (decisions 135-136, "ca doit juste suivre ma souris et si je clique dessus
    -- sans rien bouger la fenetre ne doit pas etre redimensionnee"). The way
    -- back to the default size is a double-click on the title bar, above.
    --
    -- What made a click alone resize the window was not StartSizing -- the
    -- client moves nothing while the mouse does not -- but the release: it wrote
    -- the current size down unconditionally, which switched the window from the
    -- fitted mode to the manual one, and the manual mode is clamped to the
    -- grip's own floor rather than to the screen's. So a window that had been
    -- fitted to a short screen jumped to that floor on a click that moved
    -- nothing. The size at the press is kept and compared: no movement, no
    -- write, no refresh, nothing at all.
    resizeGrip = CreateFrame("Button", "SanctuaryResizeGrip", mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetFrameLevel(LEVEL_OVER_PANEL)
    resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetScript("OnMouseDown", function(self)
        self.fromWidth, self.fromHeight = mainFrame:GetWidth(), mainFrame:GetHeight()
        mainFrame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function(self)
        mainFrame:StopMovingOrSizing()
        local width, height = mainFrame:GetWidth(), mainFrame:GetHeight()
        -- A click that moved nothing is a click, not a drag.
        if width == self.fromWidth and height == self.fromHeight then return end
        manualSize = { width, height }
        if SanctuaryDB then SanctuaryDB.uiSize = { width, height } end
        -- Recording the size is not applying it. The content area keeps the
        -- height it was given by the last refresh until something hands it the
        -- new one, so a drag left the screen either floating in a taller window
        -- or spilling out under a shorter one, with no bar.
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

-- The geometry of a minimap button, which is Blizzard's and not ours: a 31 px
-- button wearing `MiniMap-TrackingBorder` at 53 px, corner to corner.
--
-- The ring is NOT centred in that 53 px square -- its circle is painted up and
-- to the left of it, which is exactly why the texture is anchored TOPLEFT
-- instead of CENTER. So the hole the icon has to fill is not in the middle of
-- the button either: it is 16.5 across and 15.5 down from the button's top-left
-- corner, a pixel to the right of the button's own centre, and about 20 px wide.
-- Constat 162a is what putting the icon in the middle of the button looks like;
-- constat 164 is the pixel that was left after it -- "presque centre mais pas
-- encore tout a fait", the shield reading high and left inside the ring. Measure
-- on a capture before touching these two numbers again: they are the position of
-- the drawing inside the ring and nothing else derives from them.
local MINIMAP = { size = 31, ring = 53, hole = 20, holeX = 16.5, holeY = -15.5 }

-- A failure here stays local to the button: /sanc must open the window on a
-- client where the minimap is not what we expect.
local function createMinimapButton()
    if minimapButton or type(Minimap) ~= "table" then return end
    local ok = pcall(function()
        local btn = CreateFrame("Button", "SanctuaryMinimapButton", Minimap)
        btn:SetSize(MINIMAP.size, MINIMAP.size)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(8)

        -- The logo, decision 155: one drawing for the whole add-on. The same
        -- file answers here and in the AddOns list, because `## IconTexture` in
        -- the manifest names this very path -- so the icon beside the name and
        -- the button on the minimap cannot drift into two different pictures.
        -- The invariant is the path: manifest, `SetTexture` and the file on
        -- disk are one asset, and the harness holds the three to it.
        --
        -- Written without an extension on purpose: the client resolves it to the
        -- .blp it prefers or the .tga we ship, and a path with the extension
        -- spelt out is a path that has to be edited the day the file is
        -- compiled.
        btn.icon = btn:CreateTexture(nil, "BACKGROUND")
        btn.icon:SetSize(MINIMAP.hole, MINIMAP.hole)
        -- On the centre of the RING'S HOLE, which is not the centre of the
        -- button. `MiniMap-TrackingBorder` paints its circle in the top-left of
        -- a square half as wide again as the button -- that is why the texture
        -- is anchored corner to corner instead of centred -- so an icon put in
        -- the middle of the button sits low in the hole it is meant to fill.
        -- The point below is where Blizzard's own minimap buttons put theirs.
        btn.icon:SetPoint("CENTER", btn, "TOPLEFT", MINIMAP.holeX, MINIMAP.holeY)
        btn.icon:SetTexture("Interface\\AddOns\\Sanctuary\\media\\logo")
        -- No TexCoord crop. The 8 % that used to come off each side was there to
        -- cut the border a Blizzard icon is painted with; this artwork has its
        -- own margin and a transparent background, so cropping it would only
        -- magnify it into the tracking ring.

        btn.border = btn:CreateTexture(nil, "OVERLAY")
        btn.border:SetSize(MINIMAP.ring, MINIMAP.ring)
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
