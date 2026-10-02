-- Config.lua
-- Author      : mcrane
--
-- Options window, script editor, addon compartment and minimap buttons. Everything is built in Lua on
-- first use, none of it is protected so it works in combat.

local BR = OpcowsBuffReminder
local ROW_HEIGHT = 20

local COND_LABELS = {
    dead = "Dead", instance = "Instance", party = "Party", raid = "Raid",
    resting = "Resting", taxi = "Taxi", combat = "Combat", mounted = "Mounted",
}
local COND_DESC = {
    dead = "dead", instance = "in a dungeon", party = "in a party", raid = "in a raid",
    resting = "resting", taxi = "on a flight path", combat = "in combat", mounted = "mounted",
}
local ALWAYS_LABELS = { [0] = "Normal", [1] = "Never", [2] = "Always" }
local ALWAYS_TIPS = {
    [0] = "The icon shows when the buff is missing, unless a condition above hides it.",
    [1] = "The icon is never shown.",
    [2] = "The icon always shows when the buff is missing, the conditions above are ignored.",
}

local config        -- main window, created on first open
local editor        -- script editor, created on first use

local function Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function Changed()
    BR.Update()
    BR.RefreshConfig()
end

-- the value after cur in order, going round, skipping "default" when noDefault
local function NextIn(order, cur, noDefault)
    local n = #order
    for i, v in ipairs(order) do
        if v == cur then
            local nxt = order[i % n + 1]
            if noDefault and nxt == "default" then nxt = order[(i + 1) % n + 1] end
            return nxt
        end
    end
    return order[noDefault and 2 or 1]
end

-- widget helpers ---------------------------------------------------------------------------
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- text can be a function of the widget, for tooltips that describe the current state
local function Tooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        local t = type(text) == "function" and text(self) or text
        if t then GameTooltip:AddLine(t, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EditBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    return e
end

-- edit box bound to a value, saved on enter or when it loses focus, escape reverts
local function ValueBox(parent, width, get, set)
    local e = EditBox(parent, width)
    function e:Load()
        if not self:HasFocus() then
            self:SetText(tostring(get() or ""))
            self:SetTextColor(1, 1, 1)
        end
    end
    -- yellow until saved, so it's clear the edit hasn't taken effect yet
    e:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetTextColor(1, 0.82, 0) end
    end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self)
        self.revert = true
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if not self.revert then set(Trim(self:GetText())) end
        self.revert = nil
        Changed()
        self:Load()
    end)
    return e
end

-- setter that ignores anything that isn't a number in range
local function NumberSetter(min, max, apply)
    return function(text)
        local n = tonumber(text)
        if n and n >= min and n <= max then apply(n) end
    end
end

local function Check(parent, text, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = Label(c, text, "GameFontHighlightSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 0, 1)
    c:SetHitRectInsets(0, -70, 0, 0)
    if onClick then
        c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    end
    return c
end

local function Box(parent, bg)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({
        bgFile = bg or "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if not bg then b:SetBackdropColor(0, 0, 0, 0.5) end
    b:SetBackdropBorderColor(0.6, 0.6, 0.6)
    return b
end

-- scrolling list of rows with an icon, text and an optional remove button
local function ScrollList(parent, width, height)
    local box = Box(parent)
    box:SetSize(width, height)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width - 30, 1)
    sf:SetScrollChild(child)
    box.rows = {}

    local function NewRow(i)
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.25)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(20, 20)
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetScript("OnClick", function() row.item.onRemove() end)
        Tooltip(row.remove, "Remove")
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.item.onClick then self.item.onClick() end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.item.spell then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.item.spell)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.rows[i] = row
        return row
    end

    -- items = { { text, icon, selected, onClick, onRemove, spell }, ... }
    function box:SetItems(items)
        for i, item in ipairs(items) do
            local row = self.rows[i] or NewRow(i)
            row.item = item
            row.icon:SetTexture(item.icon)
            row.text:SetText(item.text)
            row.sel:SetShown(item.selected and true or false)
            row.remove:SetShown(item.onRemove ~= nil)
            row:Show()
        end
        for i = #items + 1, #self.rows do
            self.rows[i]:Hide()
        end
        child:SetHeight(math.max(1, #items * ROW_HEIGHT))
    end

    return box
end

-- searchable popup list. Its source returns every row, each with a name to search by; top
-- leaves room under the search box for the caller's own widgets.
local PICKER_ROWS = 200
local function Picker(parent, title, width, height, top)
    local p = Box(parent, "Interface\\DialogFrame\\UI-DialogBox-Background")
    p:SetSize(width, height)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:Hide()
    local titleText = Label(p, title)
    titleText:SetPoint("TOPLEFT", 10, -9)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() p:Hide() end)
    local searchLabel = Label(p, "Search:", "GameFontHighlightSmall")
    searchLabel:SetPoint("TOPLEFT", 12, -34)
    p.search = EditBox(p, width - 76)
    p.search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    p.search:SetScript("OnTextChanged", function() p:Update() end)
    p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local listTop = 54 + (top or 0)
    p.list = ScrollList(p, width - 16, height - listTop - 8)
    p.list:SetPoint("TOPLEFT", 8, -listTop)

    -- fetch the rows again, then filter them
    function p:Reload()
        self.rows = self.source()
        self:Update()
    end

    function p:Update()
        if not self.rows then return end
        local filter = Trim(self.search:GetText()):lower()
        local items = {}
        for _, row in ipairs(self.rows) do
            if row.name == nil or filter == "" or row.name:lower():find(filter, 1, true) then
                table.insert(items, row)
            end
        end
        local more = #items - PICKER_ROWS
        if more > 0 then
            for i = #items, PICKER_ROWS + 1, -1 do items[i] = nil end
            table.insert(items, { text = ("|cff808080%d more, search to narrow the list|r"):format(more) })
        end
        self.list:SetItems(items)
    end

    function p:Open(anchor, source)
        self.source = source
        self.search:SetText("")
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
        self:Show()
        self:Reload()
    end

    return p
end

-- conditions, warning time and script, shared by groups and defaults ------------------------
-- target = { name, conds, getWarn, setWarn, getScript, setScript }
local function ConditionsPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(386, 110)

    local title = Label(p, "Hide the icon while:")
    title:SetPoint("TOPLEFT", 0, 0)
    local hint = Label(p, "click to cycle: off, while true, |cffff4040while false|r", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 8, 0)

    p.checks = {}
    for i, key in ipairs(BR.CONDITIONS) do
        local c = Check(p, COND_LABELS[key])
        c:SetPoint("TOPLEFT", ((i - 1) % 4) * 96, -16 - math.floor((i - 1) / 4) * 24)
        function c:SetState(s)
            self.state = s
            self:SetChecked(s ~= 0)
            local red = s == 2
            self:GetCheckedTexture():SetVertexColor(1, red and 0.2 or 1, red and 0.2 or 1)
            self.label:SetText(red and ("|cffff4040Not|r " .. COND_LABELS[key]) or COND_LABELS[key])
        end
        c:SetScript("OnClick", function(self)
            local conds = p.target.conds
            conds[key] = (conds[key] + 1) % 3
            Changed()
        end)
        Tooltip(c, COND_LABELS[key], function(self)
            local s = self.state
            local text = s == 0 and "Ignored."
                or ("Hide the icon while " .. (s == 2 and "not " or "") .. COND_DESC[key] .. ".")
            return text .. "\n|cff808080Click to change.|r"
        end)
        p.checks[key] = c
    end

    local showLabel = Label(p, "Show:")
    showLabel:SetPoint("TOPLEFT", 0, -74)
    p.always = Button(p, "", 70, function()
        local conds = p.target.conds
        conds.always = (conds.always + 1) % 3
        Changed()
    end)
    p.always:SetPoint("LEFT", showLabel, "RIGHT", 6, 0)
    Tooltip(p.always, "Show", function() return ALWAYS_TIPS[p.target.conds.always] .. "\n|cff808080Click to change.|r" end)

    local warnLabel = Label(p, "Early warning:")
    warnLabel:SetPoint("LEFT", p.always, "RIGHT", 16, 0)
    p.warn = ValueBox(p, 44,
        function() return p.target.getWarn() end,
        NumberSetter(0, 86400, function(n) p.target.setWarn(n) end))
    p.warn:SetPoint("LEFT", warnLabel, "RIGHT", 10, 0)
    local secs = Label(p, "sec", "GameFontHighlightSmall")
    secs:SetPoint("LEFT", p.warn, "RIGHT", 4, 0)
    Tooltip(p.warn, "Early warning", "Show the icon with a countdown when the buff has this many seconds left. 0 shows it only once the buff is gone.")

    p.script = Button(p, "Script", 70, function() BR.EditScript(p.target) end)
    p.script:SetPoint("TOPRIGHT", 0, -70)
    Tooltip(p.script, "Script", "Lua code that hides the icon while it returns true.")

    function p:Load(target)
        self.target = target
        local conds = target.conds
        for key, c in pairs(self.checks) do
            c:SetState(conds[key])
            c:SetEnabled(conds.always == 0)
            c.label:SetFontObject(conds.always == 0 and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
        self.always:SetText(ALWAYS_LABELS[conds.always])
        self.warn:Load()
        self.script:SetText(target.getScript() ~= "" and "Script |cff00ff00*|r" or "Script")
    end

    return p
end

local function GroupTarget(g)
    local group = OpcowsBuffReminderDB.BuffGroups[g]
    return {
        name = g,
        conds = group.conditions,
        getWarn = function() return group.warntime end,
        setWarn = function(n) group.warntime = n end,
        getScript = function() return group.script end,
        setScript = function(code) BR.SetGroupScript(g, code) end,
    }
end

local function EnchantTarget(slot)
    local e = OpcowsBuffReminderDB.Enchants[slot]
    return {
        name = BR.ENCHANT_NAMES[slot],
        conds = e.conditions,
        getWarn = function() return e.warntime end,
        setWarn = function(n) e.warntime = n end,
        getScript = function() return e.script end,
        setScript = function(code) BR.SetEnchantScript(slot, code) end,
    }
end

-- the weapon's icon, or a stand-in when the hand is empty
local ENCHANT_ICONS = { main = "Interface\\Icons\\INV_Sword_04", off = "Interface\\Icons\\INV_Shield_04" }
local function EnchantIcon(slot)
    return GetInventoryItemTexture("player", BR.ENCHANT_SLOTS[slot]) or ENCHANT_ICONS[slot]
end

-- what's on the weapon right now
local function EnchantNow(slot)
    if not GetInventoryItemTexture("player", BR.ENCHANT_SLOTS[slot]) then return "No weapon in this hand." end
    local e = BR.enchants[slot]
    if not e or not e.present then return "No temporary enchant on the weapon right now." end
    local left = math.max(0, e.expires - GetTime())
    local text = left >= 60 and ("%d min"):format(math.floor(left / 60 + 0.5)) or ("%d sec"):format(left)
    text = "Enchanted, " .. text .. " left"
    if e.charges > 0 then text = text .. (", %d charge%s"):format(e.charges, e.charges == 1 and "" or "s") end
    return text .. "."
end

local function DefaultTarget()
    local opts = OpcowsBuffReminderDB.Options
    return {
        name = "defaults",
        conds = opts.conditions,
        getWarn = function() return opts.warntime end,
        setWarn = function(n) opts.warntime = n end,
        getScript = function() return opts.script end,
        setScript = BR.SetDefaultScript,
    }
end

local function BuffText(b)
    local id = tonumber(b)
    if id and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name then return ("%s |cff808080(%d)|r"):format(name, id) end
    end
    return b
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return keys
end

StaticPopupDialogs["OPCOWSBUFFREMINDER_DELETE_GROUP"] = {
    text = 'Delete the buff group "%s"?',
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        BR.RemoveGroup(data)
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["OPCOWSBUFFREMINDER_COPY"] = {
    text = "Replace this character's Buff Reminder settings with %s's? This deletes this character's buff groups.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if BR.CopyCharacter(data) then BR.Print("Settings copied from " .. data .. ".") end
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["OPCOWSBUFFREMINDER_LOAD_SAVE"] = {
    text = 'Replace this character\'s Buff Reminder settings with the save "%s"? This deletes this character\'s buff groups.',
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if BR.LoadSave(data) then BR.Print('Settings loaded from "' .. data .. '".') end
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["OPCOWSBUFFREMINDER_OVERWRITE_SAVE"] = {
    text = 'Replace the save "%s" with this character\'s settings?',
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        BR.SaveSettings(data)
        BR.Print('Settings saved as "' .. data .. '".')
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["OPCOWSBUFFREMINDER_DELETE_SAVE"] = {
    text = 'Delete the save "%s"?',
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        BR.DeleteSave(data)
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["OPCOWSBUFFREMINDER_RESET"] = {
    text = "Clear all Buff Reminder settings? This deletes all of your buff groups.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        BR.Reset()
        BR.Print("All settings cleared.")
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- glow and color buttons marking a missing buff or a warning, and a preview icon. target() is the
-- table holding glowKey and overlayKey, group rows have a Default that follows the Options tab.
-- texture() is the preview's icon.
local STYLE_WHEN = {
    missing = { "When missing:", "missing", "while the buff is missing, not while it's only running out" },
    warning = { "When warning:", "warning", "while the buff is running out (early warning time) or low on stacks, not once it's gone" },
}
local function StyleRow(parent, when, target, glowKey, overlayKey, isGroup, texture)
    local w = STYLE_WHEN[when]
    local row = {}
    local label = Label(parent, w[1])
    row.label = label
    local glowLabel = Label(parent, "Glow", "GameFontHighlightSmall")
    -- a fixed column, so the missing and warning rows line up whatever their labels' widths
    glowLabel:SetPoint("LEFT", label, "LEFT", 100, 0)
    row.glow = Button(parent, "", 80, function()
        local t = target()
        t[glowKey] = NextIn(BR.GLOW_ORDER, t[glowKey], not isGroup)
        Changed()
    end)
    row.glow:SetPoint("LEFT", glowLabel, "RIGHT", 6, 0)
    local others = isGroup and "\n\n" or " Buff groups can have their own on the Buff groups tab.\n\n"
    local default = isGroup and "|cffffd100Default:|r follows the Options tab.\n" or ""
    Tooltip(row.glow, "Glow when " .. w[2],
        "A glow around the icon " .. w[3] .. "." .. others
        .. default
        .. "|cffffd100Pulse:|r a glow that fades in and out.\n"
        .. "|cffffd100Flash:|r the same, fast.\n"
        .. "|cffffd100Steady:|r a glow that stays lit.\n"
        .. "|cffffd100Spell alert:|r the game's proc glow, like an action button's. A pulse if the game won't show it.\n"
        .. "|cff808080Click to change.|r")
    local overlayLabel = Label(parent, "Color", "GameFontHighlightSmall")
    overlayLabel:SetPoint("LEFT", row.glow, "RIGHT", 10, 0)
    row.overlay = Button(parent, "", 70, function()
        local t = target()
        t[overlayKey] = NextIn(BR.OVERLAY_ORDER, t[overlayKey], not isGroup)
        Changed()
    end)
    row.overlay:SetPoint("LEFT", overlayLabel, "RIGHT", 6, 0)
    Tooltip(row.overlay, "Color when " .. w[2],
        "A color washed over the icon " .. w[3] .. ", ex: red." .. others
        .. default .. "|cff808080Click to change.|r")
    row.preview = BR.NewPreview(parent, 22)
    row.preview:SetPoint("LEFT", row.overlay, "RIGHT", 16, 0)
    Tooltip(row.preview, "Preview", "How the icon looks when " .. w[2] .. ", with its glow, color and opacity.")
    function row:Load()
        local t = target()
        self.glow:SetText(BR.GLOWS[t[glowKey]])
        self.overlay:SetText(BR.OVERLAYS[t[overlayKey]])
        BR.StylePreview(self.preview, t, when == "missing", texture and texture())
    end
    return row
end

-- groups page ------------------------------------------------------------------------------
local function CreateGroupsPage(page)
    -- a buff group's name, or an enchant group's slot
    local selected, selectedSlot

    -- the selected buff or enchant group
    local function Current()
        if selectedSlot then return OpcowsBuffReminderDB.Enchants[selectedSlot] end
        return OpcowsBuffReminderDB.BuffGroups[selected]
    end

    local groupsLabel = Label(page, "Buff groups")
    groupsLabel:SetPoint("TOPLEFT", 0, 0)
    local groups = ScrollList(page, 176, 300)
    groups:SetPoint("TOPLEFT", 0, -16)

    local newLabel = Label(page, "New buff group:", "GameFontHighlightSmall")
    newLabel:SetPoint("TOPLEFT", groups, "BOTTOMLEFT", 2, -8)
    local newEdit = EditBox(page, 116)
    newEdit:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 4, -2)
    local function NewGroup()
        local g = Trim(newEdit:GetText())
        if g == "" then return end
        if not OpcowsBuffReminderDB.BuffGroups[g] then BR.AddBuffToGroup(g, nil) end
        selected, selectedSlot = g, nil
        newEdit:SetText("")
        newEdit:ClearFocus()
        Changed()
    end
    newEdit:SetScript("OnEnterPressed", NewGroup)
    local newBtn = Button(page, "Add", 50, NewGroup)
    newBtn:SetPoint("LEFT", newEdit, "RIGHT", 4, 0)

    local empty = Label(page, "Create a buff group to get started.\nPut buffs that replace each other,\nlike different food buffs, in the same buff group.", "GameFontHighlight")
    empty:SetJustifyH("CENTER")
    empty:SetPoint("CENTER", page, "CENTER", 95, 40)

    -- selected group details
    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPLEFT", 190, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)

    local icon = detail:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 0, 0)
    local name = Label(detail, "", "GameFontNormalLarge")
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", detail, "RIGHT", -80, 0)
    name:SetWordWrap(false)
    local delete = Button(detail, "Delete", 70, function()
        StaticPopup_Show("OPCOWSBUFFREMINDER_DELETE_GROUP", selected, nil, selected)
    end)
    delete:SetPoint("TOPRIGHT", 0, -3)

    local buffsLabel = Label(detail, "Buffs")
    buffsLabel:SetPoint("TOPLEFT", 0, -38)
    local buffsHint = Label(detail, "any one of these counts, by name or spell id", "GameFontDisableSmall")
    buffsHint:SetPoint("LEFT", buffsLabel, "RIGHT", 8, 0)
    local buffs = ScrollList(detail, 386, 94)
    buffs:SetPoint("TOPLEFT", 0, -54)

    -- enchant groups have the weapon instead of buffs
    local enchNow = Label(detail, "", "GameFontHighlight")
    enchNow:SetPoint("TOPLEFT", 0, -60)
    enchNow:SetPoint("RIGHT", detail, "RIGHT")
    local enchHint = Label(detail, "Poisons, oils, sharpening stones and shaman weapon imbues. "
        .. "Set Show to Normal to use this reminder.", "GameFontDisableSmall")
    enchHint:SetPoint("TOPLEFT", enchNow, "BOTTOMLEFT", 0, -8)
    enchHint:SetPoint("RIGHT", detail, "RIGHT")
    enchHint:SetJustifyH("LEFT")

    local buffEdit = EditBox(detail, 180)
    buffEdit:SetPoint("TOPLEFT", buffs, "BOTTOMLEFT", 6, -6)
    local function AddBuff(buff)
        buff = Trim(buff)
        if buff == "" or not selected then return end
        BR.AddBuffToGroup(selected, buff)
        buffEdit:SetText("")
        buffEdit:ClearFocus()
        Changed()
    end
    buffEdit:SetScript("OnEnterPressed", function(self) AddBuff(self:GetText()) end)
    local addBtn = Button(detail, "Add", 50, function() AddBuff(buffEdit:GetText()) end)
    addBtn:SetPoint("LEFT", buffEdit, "RIGHT", 4, 0)

    -- picker listing your buff spells, the buffs you have now and the ones you've had
    local picker = Picker(detail, "Add a buff", 300, 340, 28)
    local pickTab = "spells"
    local allSpells = Check(picker, "Show all spells", function() picker:Reload() end)
    allSpells:SetPoint("BOTTOMLEFT", 8, 6)
    Tooltip(allSpells, "Show all spells", "Buffs are picked out of your spellbook by their description. "
        .. "If one is missing, show every spell.")
    local tabs = {}
    local function PickTab(tab)
        pickTab = tab
        for key, b in pairs(tabs) do
            if key == tab then b:LockHighlight() else b:UnlockHighlight() end
        end
        allSpells:SetShown(tab == "spells")
        picker.list:SetHeight(tab == "spells" and 222 or 250)
        picker:Reload()
    end
    for i, t in ipairs({ { "spells", "My spells" }, { "active", "Active now" }, { "seen", "Seen before" } }) do
        tabs[t[1]] = Button(picker, t[2], 92, function() PickTab(t[1]) end)
        tabs[t[1]]:SetPoint("TOPLEFT", 8 + (i - 1) * 95, -56)
    end
    Tooltip(tabs.spells, "My spells", "Spells in your spellbook that look like buffs, added by name so every rank counts.")
    Tooltip(tabs.active, "Active now", "The buffs you have right now.")
    Tooltip(tabs.seen, "Seen before", "Buffs you've had, including food, elixirs and buffs other players cast on you.")

    local function BuffRows()
        local list
        if pickTab == "spells" then
            list = BR.GetSpellbookBuffs(allSpells:GetChecked())
        elseif pickTab == "active" then
            list = BR.GetCurrentBuffs()
            if not list then return { { text = "|cff808080Buffs can't be read in combat.|r" } } end
        else
            list = BR.GetSeenBuffs()
        end
        -- the group each buff is in already
        local used = {}
        for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
            for b in pairs(group.buffs) do used[tostring(b):lower()] = g end
        end
        table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
        local rows, seen = {}, {}
        for _, e in ipairs(list) do
            local name = e.name
            if type(name) == "string" and not seen[name] then
                seen[name] = true
                local g = used[name:lower()] or (e.spellId and used[tostring(e.spellId)])
                table.insert(rows, {
                    name = name,
                    text = g and ("|cff808080%s (in %s)|r"):format(name, g) or name,
                    icon = e.icon or BR.QUESTION_MARK,
                    spell = e.spellId,
                    onClick = function()
                        AddBuff(name)
                        picker:Reload()
                    end,
                })
            end
        end
        if #rows == 0 then
            rows[1] = { text = pickTab == "seen" and "|cff808080None yet.|r" or "|cff808080None found.|r" }
        end
        return rows
    end

    local pickBtn = Button(detail, "Browse...", 90, function(self)
        if picker:IsShown() then picker:Hide() return end
        picker:Open(self, BuffRows)
        PickTab(pickTab)
    end)
    pickBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    Tooltip(pickBtn, "Browse buffs", "Pick from your buff spells, the buffs you have now or ones you've had before.")
    -- spell text the game loaded late can turn up more buffs
    BR.OnSpellData = function()
        if picker:IsShown() and pickTab == "spells" then picker:Reload() end
    end
    page:SetScript("OnHide", function() picker:Hide() end)

    local conds = ConditionsPanel(detail)
    conds:SetPoint("TOPLEFT", 0, -186)

    local stacksLabel = Label(detail, "Warn at stacks:")
    stacksLabel:SetPoint("TOPLEFT", 0, -306)
    local stacks = ValueBox(detail, 36,
        function() return Current().warnstacks end,
        NumberSetter(0, 1000, function(n) Current().warnstacks = n end))
    stacks:SetPoint("LEFT", stacksLabel, "RIGHT", 10, 0)
    Tooltip(stacks, "Low stack warning", function()
        if selectedSlot then
            return "Show the icon with the charge count when the enchant is down to this many charges. 0 turns it off."
        end
        return "Show the icon with the stack count when the buff is down to this many stacks or charges, "
            .. "ex: 3 for Inner Fire. 0 turns it off."
    end)

    local timerLabel = Label(detail, "Time left:")
    timerLabel:SetPoint("LEFT", stacks, "RIGHT", 20, 0)
    local timer = Button(detail, "", 110, function()
        local group = Current()
        local order = BR.TIMER_ORDER
        for i, m in ipairs(order) do
            if m == group.timer then
                group.timer = order[i % #order + 1]
                break
            end
        end
        Changed()
    end)
    timer:SetPoint("LEFT", timerLabel, "RIGHT", 10, 0)
    Tooltip(timer, "Time left",
        "How this icon shows the time left.\n\n"
        .. "|cffffd100Default:|r follows the Icons show setting on the Options tab.\n"
        .. "|cffffd100Text:|r time left as text at the top.\n"
        .. "|cffffd100Swipe:|r a cooldown swipe over the icon.\n"
        .. "|cffffd100Text and swipe:|r both.\n"
        .. "|cffffd100None:|r neither.\n"
        .. "|cff808080Click to change.|r")

    local alphaLabel = Label(detail, "Opacity:")
    alphaLabel:SetPoint("TOPLEFT", 0, -336)
    local alphaMissingLabel = Label(detail, "missing", "GameFontHighlightSmall")
    alphaMissingLabel:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
    -- the group's own opacity, empty follows the Options tab
    local function AlphaBox(key)
        return ValueBox(detail, 36,
            function() return Current()[key] end,
            function(text)
                local n = tonumber(text)
                if text == "" or text:lower() == "default" then
                    Current()[key] = nil
                elseif n and n >= 0 and n <= 1 then
                    Current()[key] = n
                end
            end)
    end
    local alphaMissing = AlphaBox("alpha")
    alphaMissing:SetPoint("LEFT", alphaMissingLabel, "RIGHT", 6, 0)
    Tooltip(alphaMissing, "Opacity when missing",
        "This icon's opacity while the buff is gone, 0 (invisible) to 1 (solid). Empty uses the Options tab's.")
    local alphaWarnLabel = Label(detail, "warning", "GameFontHighlightSmall")
    alphaWarnLabel:SetPoint("LEFT", alphaMissing, "RIGHT", 10, 0)
    local alphaWarn = AlphaBox("warnalpha")
    alphaWarn:SetPoint("LEFT", alphaWarnLabel, "RIGHT", 6, 0)
    Tooltip(alphaWarn, "Opacity when warning",
        "This icon's opacity while the buff is still up but running out (early warning time) or low on stacks, "
        .. "0 (invisible) to 1 (solid). Empty uses the Options tab's.")

    local sizeLabel = Label(detail, "Icon size:")
    sizeLabel:SetPoint("LEFT", alphaWarn, "RIGHT", 20, 0)
    local size = ValueBox(detail, 40,
        function() return Current().size end,
        function(text)
            local group = Current()
            local n = tonumber(text)
            if text == "" or text:lower() == "default" then
                group.size = nil
            elseif n and n >= 10 and n <= 400 then
                group.size = n
            else
                return
            end
            BR.ApplyLayout()
        end)
    size:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    Tooltip(size, "Icon size", "This icon's own size, 10 to 400. Empty uses the size on the Options tab.")

    local function GroupIcon()
        return selectedSlot and EnchantIcon(selectedSlot) or Current().icon
    end
    local missingStyle = StyleRow(detail, "missing", Current, "glow", "overlay", true, GroupIcon)
    missingStyle.label:SetPoint("TOPLEFT", 0, -366)
    local warnStyle = StyleRow(detail, "warning", Current, "warnglow", "warnoverlay", true, GroupIcon)
    warnStyle.label:SetPoint("TOPLEFT", 0, -396)

    -- "auto", "off", or one of the group's spells that's yours, a spell no longer yours is auto
    local function ClickValue(group, spells)
        if group.click == "off" then return "off" end
        for _, name in ipairs(spells) do
            if name == group.click then return name end
        end
        return "auto"
    end
    local clickLabel = Label(detail, "Click to cast:")
    clickLabel:SetPoint("TOPLEFT", 0, -426)
    local click = Button(detail, "", 180, function()
        local group = Current()
        -- a hand's enchant uses what you last put on it, or nothing
        if selectedSlot then
            group.click = group.click == "off" and "auto" or "off"
            Changed()
            return
        end
        local spells = BR.ClickSpells(group)
        local order = { "auto" }
        for _, name in ipairs(spells) do table.insert(order, name) end
        table.insert(order, "off")
        group.click = NextIn(order, ClickValue(group, spells))
        Changed()
    end)
    click:SetPoint("LEFT", clickLabel, "RIGHT", 10, 0)
    local CLICK_LIMITS = "Icons can't be clicked in combat, since the game doesn't let addons move them there, "
        .. "or while they're unlocked for moving.\n"
    Tooltip(click, "Click to cast", function()
        if selectedSlot then
            return "Clicking the icon puts what you last put on this hand on it again: a poison, oil or "
                .. "sharpening stone from your bags, or an imbue spell. It's remembered when you put one on "
                .. "out of combat. The icon can't be clicked when none are left in your bags.\n\n"
                .. CLICK_LIMITS .. "|cff808080Click to turn it on or off.|r"
        end
        return "Clicking the icon casts this spell on you.\n\n"
            .. "|cffffd100Auto:|r the first of your own spells in the buff group.\n"
            .. "|cffffd100Off:|r the icon can't be clicked.\n\n"
            .. CLICK_LIMITS .. "|cff808080Click to change.|r"
    end)
    local party = Check(detail, "Party", function(v)
        Current().party = v
        Changed()
    end)
    party:SetPoint("LEFT", click, "RIGHT", 8, -1)
    -- in the party check's place for a hand's enchant
    local showCount = Check(detail, "Count", function(v)
        Current().showcount = v
        Changed()
    end)
    showCount:SetPoint("LEFT", click, "RIGHT", 8, -1)
    Tooltip(showCount, "Always show count",
        "Show how many of the last used poison, oil or stone are in your bags on the icon all the time, in combat too, "
        .. "in red at 0. Unchecked, it only shows out of combat while the icon can be clicked.")
    Tooltip(party, "Remind party",
        "Once you've given this buff to a party member, a line for them on the party panel shows it when it's gone. "
        .. "Uncheck it for buffs you only keep on yourself.")

    local combatLabel = Label(detail, "In combat:")
    combatLabel:SetPoint("TOPLEFT", 0, -456)
    local combat = Button(detail, "", 130, function()
        local group = OpcowsBuffReminderDB.BuffGroups[selected]
        BR.SetCombatMode(selected, group.combat == "cdm" and "blizzard" or "cdm")
        Changed()
    end)
    combat:SetPoint("LEFT", combatLabel, "RIGHT", 10, 0)
    Tooltip(combat, "In combat",
        "The game hides most buffs from addons in combat.\n\n"
        .. "|cffffd100Cooldown Manager:|r read live when the game allows it or when the Cooldown Manager tracks the buff. "
        .. "Otherwise the time it had when the fight started counts down, and changes show after combat.\n\n"
        .. "|cffffd100Blizzard Auras:|r for buffs the Cooldown Manager can't track. Blizzard's own aura button shows the buff "
        .. "over the icon for the whole fight with its exact time and stacks, low stacks in red. When the buff drops the icon shows through.\n"
        .. "|cff808080Click to change.|r")
    -- seconds between charges hits can use, 0 or empty is off
    local hitsLabel = Label(detail, "Hit cooldown:")
    hitsLabel:SetPoint("LEFT", combat, "RIGHT", 16, 0)
    local hits = ValueBox(detail, 36,
        function()
            local cd = Current().hitcd or 0
            return cd > 0 and cd or nil
        end,
        function(text)
            if text == "" then Current().hitcd = 0 return end
            local n = tonumber(text)
            if n and n >= 0 and n <= 60 then Current().hitcd = n end
        end)
    hits:SetPoint("LEFT", hitsLabel, "RIGHT", 8, 0)
    local hitsUnit = Label(detail, "sec", "GameFontHighlightSmall")
    hitsUnit:SetPoint("LEFT", hits, "RIGHT", 4, 0)
    Tooltip(hits, "Charges used by hits",
        "For buffs whose charges are used up by hits you take, like Lightning Shield. Neither the buff nor its "
        .. "charges can be read in combat, but hits you take can, so the charges are counted down from the pull: "
        .. "one for each hit that lands at least this many seconds after the last charge was used. "
        .. "Dodges, parries and misses don't count. At 0 charges the icon shows the buff as gone, and "
        .. "Warn at stacks warns before that. Casting the buff again in combat starts over with full charges.\n\n"
        .. "Enter how often a charge can be used, ex: 3 for Lightning Shield. Empty turns it off. "
        .. "It's corrected when combat ends.\n\n"
        .. "Only for Cooldown Manager, Blizzard Auras show the exact charges.")    local combatStatus = Label(detail, "", "GameFontHighlightSmall")
    combatStatus:SetPoint("TOPLEFT", combatLabel, "BOTTOMLEFT", 0, -10)
    combatStatus:SetPoint("RIGHT", detail, "RIGHT")

    function page:Refresh()
        if selected and not OpcowsBuffReminderDB.BuffGroups[selected] then selected = nil end
        local names = SortedKeys(OpcowsBuffReminderDB.BuffGroups)
        if not selected and not selectedSlot then
            selected = names[1]
            if not selected then selectedSlot = "main" end
        end

        local items = {}
        for _, slot in ipairs({ "main", "off" }) do
            table.insert(items, {
                text = BR.ENCHANT_NAMES[slot],
                icon = EnchantIcon(slot),
                selected = slot == selectedSlot,
                onClick = function()
                    selected, selectedSlot = nil, slot
                    picker:Hide()
                    BR.RefreshConfig()
                end,
            })
        end
        for _, g in ipairs(names) do
            table.insert(items, {
                text = g,
                icon = OpcowsBuffReminderDB.BuffGroups[g].icon,
                selected = g == selected,
                onClick = function()
                    selected, selectedSlot = g, nil
                    picker:Hide()
                    BR.RefreshConfig()
                end,
            })
        end
        groups:SetItems(items)

        empty:Hide()
        local ench = selectedSlot ~= nil
        -- enchants have no party or combat setting
        for _, w in ipairs({ delete, buffsLabel, buffsHint, buffs, buffEdit, addBtn, pickBtn,
            party, combatLabel, combat, combatStatus, hitsLabel, hits, hitsUnit }) do
            w:SetShown(not ench)
        end
        showCount:SetShown(ench)
        clickLabel:SetText(ench and "Click to apply:" or "Click to cast:")
        local clickOn = OpcowsBuffReminderDB.Options.clicktocast
        enchNow:SetShown(ench)
        enchHint:SetShown(ench)
        stacksLabel:SetText(ench and "Warn at charges:" or "Warn at stacks:")

        local group = Current()
        stacks:Load()
        timer:SetText(BR.TIMERS[group.timer])
        missingStyle:Load()
        warnStyle:Load()
        alphaMissing:Load()
        alphaWarn:Load()
        size:Load()
        if ench then
            icon:SetTexture(EnchantIcon(selectedSlot))
            name:SetText(BR.ENCHANT_NAMES[selectedSlot])
            enchNow:SetText(EnchantNow(selectedSlot))
            conds:Load(EnchantTarget(selectedSlot))
            showCount:SetChecked(group.showcount)
            local last = BR.EnchantLastName(selectedSlot)
            click:SetEnabled(clickOn)
            if not clickOn then
                click:SetText("Off on Options tab")
            elseif group.click == "off" then
                click:SetText("Off")
            else
                click:SetText(last and ("Last used: " .. last) or "None used yet")
            end
            return
        end

        icon:SetTexture(group.icon)
        name:SetText(selected)
        local bitems = {}
        for _, b in ipairs(SortedKeys(group.buffs)) do
            table.insert(bitems, {
                text = BuffText(b),
                icon = BR.SpellTexture(b) or BR.QUESTION_MARK,
                onRemove = function()
                    group.buffs[b] = nil
                    Changed()
                end,
            })
        end
        buffs:SetItems(bitems)
        conds:Load(GroupTarget(selected))
        party:SetChecked(group.party)
        local spells = BR.ClickSpells(group)
        local cv = ClickValue(group, spells)
        click:SetEnabled(clickOn and #spells > 0)
        if not clickOn then
            click:SetText("Off on Options tab")
        elseif #spells == 0 then
            click:SetText("None of your spells")
        elseif cv == "auto" then
            click:SetText("Auto: " .. spells[1])
        else
            click:SetText(cv == "off" and "Off" or cv)
        end
        combat:SetText(BR.COMBAT_MODES[group.combat])
        -- Blizzard's button shows the exact charges
        local cdm = group.combat == "cdm"
        hitsLabel:SetShown(cdm)
        hits:SetShown(cdm)
        hitsUnit:SetShown(cdm)
        hits:Load()
        local status, warn = BR.CombatStatus(selected)
        combatStatus:SetText(status)
        if warn then
            combatStatus:SetTextColor(1, 0.5, 0.25)
        else
            combatStatus:SetTextColor(0.6, 0.8, 0.6)
        end
    end
end

-- options page -----------------------------------------------------------------------------
local function CreateOptionsPage(page)
    local header = Label(page, "Defaults", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, 0)
    local note = Label(page, "Copied to new buff groups.", "GameFontHighlightSmall")
    note:SetPoint("LEFT", header, "RIGHT", 10, -1)
    local conds = ConditionsPanel(page)
    conds:SetPoint("TOPLEFT", 0, -28)

    local dispHeader = Label(page, "Display", "GameFontNormalLarge")
    dispHeader:SetPoint("TOPLEFT", 0, -150)

    local sizeLabel = Label(page, "Icon size:")
    sizeLabel:SetPoint("TOPLEFT", 0, -177)
    local size = ValueBox(page, 40,
        function() return OpcowsBuffReminderDB.Options.size end,
        NumberSetter(10, 400, function(n)
            OpcowsBuffReminderDB.Options.size = n
            BR.ApplyLayout()
        end))
    size:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    Tooltip(size, "Icon size", "10 to 400. Buff groups can have their own size on the Buff groups tab.")

    local alphaLabel = Label(page, "Opacity:")
    alphaLabel:SetPoint("LEFT", size, "RIGHT", 20, 0)
    local missingLabel = Label(page, "missing", "GameFontHighlightSmall")
    missingLabel:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
    local alpha = ValueBox(page, 36,
        function() return OpcowsBuffReminderDB.Options.alpha end,
        NumberSetter(0, 1, function(n) OpcowsBuffReminderDB.Options.alpha = n end))
    alpha:SetPoint("LEFT", missingLabel, "RIGHT", 6, 0)
    Tooltip(alpha, "Opacity when missing", "Icons whose buff is gone. 0 (invisible) to 1 (solid). "
        .. "Buff groups can have their own on the Buff groups tab.")
    local warnLabel = Label(page, "warning", "GameFontHighlightSmall")
    warnLabel:SetPoint("LEFT", alpha, "RIGHT", 10, 0)
    local warnAlpha = ValueBox(page, 36,
        function() return OpcowsBuffReminderDB.Options.warnalpha end,
        NumberSetter(0, 1, function(n) OpcowsBuffReminderDB.Options.warnalpha = n end))
    warnAlpha:SetPoint("LEFT", warnLabel, "RIGHT", 6, 0)
    Tooltip(warnAlpha, "Opacity when warning",
        "Icons whose buff is still up but running out (early warning time) or low on stacks. 0 (invisible) to 1 (solid). "
        .. "Buff groups can have their own on the Buff groups tab.")

    local soundLabel = Label(page, "Warning sound:")
    soundLabel:SetPoint("TOPLEFT", 0, -207)
    local sound = ValueBox(page, 150,
        function()
            local id = OpcowsBuffReminderDB.Options.warnsound
            return id and (BR.SoundName(id) or id)
        end,
        function(text)
            if not BR.SetSound(text) then BR.Print("Unknown sound " .. text .. ".") end
        end)
    sound:SetPoint("LEFT", soundLabel, "RIGHT", 10, 0)
    Tooltip(sound, "Warning sound", "Played when a new icon appears. A sound kit id or a SOUNDKIT name like RAID_WARNING. Leave empty for no sound.")
    local test = Button(page, "Test", 50, function()
        if OpcowsBuffReminderDB.Options.warnsound then PlaySound(OpcowsBuffReminderDB.Options.warnsound, "Master") end
    end)
    test:SetPoint("LEFT", sound, "RIGHT", 6, 0)

    local soundPicker = Picker(page, "Warning sound", 300, 340)
    local function SoundRows()
        local current = OpcowsBuffReminderDB.Options.warnsound
        local rows = { {
            name = "none",
            text = "|cff808080None|r",
            selected = current == nil,
            onClick = function()
                BR.SetSound(nil)
                Changed()
                soundPicker:Reload()
            end,
        } }
        for _, name in ipairs(BR.SoundNames()) do
            table.insert(rows, {
                name = name,
                text = name,
                selected = SOUNDKIT[name] == current,
                onClick = function()
                    BR.SetSound(name)
                    Changed()
                    soundPicker:Reload()
                end,
            })
        end
        return rows
    end
    local browse = Button(page, "Browse...", 80, function(self)
        if soundPicker:IsShown() then soundPicker:Hide() return end
        soundPicker:Open(self, SoundRows)
    end)
    browse:SetPoint("LEFT", test, "RIGHT", 4, 0)
    Tooltip(browse, "Browse sounds", "The game's sounds. Click one to use it and hear it.")
    page:SetScript("OnHide", function()
        soundPicker:Hide()
        if page.copyPicker then page.copyPicker:Hide() end
    end)

    local unlock = Check(page, "Unlock icons to move them", function(v) BR.SetLocked(not v) end)
    unlock:SetPoint("TOPLEFT", 0, -232)
    Tooltip(unlock, "Unlock icons",
        "Shows every icon so it can be placed, grey when it isn't needed right now.\n\n"
        .. "Drag an icon to move it with the icons snapped to it. Shift-drag pulls it away on its own. "
        .. "Drop it touching other icons, on any side, to snap it to them: rows, columns or squares. "
        .. "Dropped into a row or column it pushes the rest along.")
    local hide = Check(page, "Hide all icons", function() BR.ToggleHidden() end)
    hide:SetPoint("TOPLEFT", 200, -232)
    local minimap = Check(page, "Minimap button", function(v)
        OpcowsBuffReminderDB.Options.minimap.hide = not v
        BR.UpdateMinimap()
    end)
    minimap:SetPoint("TOPLEFT", 360, -232)

    local textLabel = Label(page, "Icons show:")
    textLabel:SetPoint("TOPLEFT", 0, -263)
    local showTime = Check(page, "Time left", function(v) OpcowsBuffReminderDB.Options.icontext.time = v; Changed() end)
    showTime:SetPoint("LEFT", textLabel, "RIGHT", 8, -1)
    Tooltip(showTime, "Time left", "The time left as text at the top of the icon. Buff groups can override this on the Buff groups tab.")
    local showSwipe = Check(page, "Swipe", function(v) OpcowsBuffReminderDB.Options.icontext.swipe = v; Changed() end)
    showSwipe:SetPoint("LEFT", showTime, "RIGHT", 70, 0)
    Tooltip(showSwipe, "Swipe", "The time left as a clock swipe darkening the icon. Buff groups can override this on the Buff groups tab.")
    local showStacks = Check(page, "Stack count", function(v) OpcowsBuffReminderDB.Options.icontext.stacks = v; Changed() end)
    showStacks:SetPoint("LEFT", showSwipe, "RIGHT", 56, 0)
    local bothLabel = Label(page, "When both:")
    bothLabel:SetPoint("LEFT", showStacks, "RIGHT", 84, 1)
    local PRIORITY_NEXT = { both = "time", time = "stacks", stacks = "both" }
    local PRIORITY_LABELS = { both = "Show both", time = "Time only", stacks = "Stacks only" }
    local priority = Button(page, "", 100, function()
        local t = OpcowsBuffReminderDB.Options.icontext
        t.priority = PRIORITY_NEXT[t.priority]
        Changed()
    end)
    priority:SetPoint("LEFT", bothLabel, "RIGHT", 6, 0)
    Tooltip(priority, "When both apply",
        "An icon can show time left text (top) and a stack count (bottom right) at once. On small icons they can crowd it, pick one to show only that.\n|cff808080Click to change.|r")

    local function Opts() return OpcowsBuffReminderDB.Options end
    -- a sample buff for the previews, Mark of the Wild
    local function SampleIcon() return "Interface\\Icons\\Spell_Nature_Regeneration" end
    local missingStyle = StyleRow(page, "missing", Opts, "glow", "overlay", false, SampleIcon)
    missingStyle.label:SetPoint("TOPLEFT", 0, -293)
    local warnStyle = StyleRow(page, "warning", Opts, "warnglow", "warnoverlay", false, SampleIcon)
    warnStyle.label:SetPoint("TOPLEFT", 0, -323)

    local clickLabel = Label(page, "Click to cast:")
    clickLabel:SetPoint("TOPLEFT", 0, -355)
    local clickOn = Check(page, "", function(v)
        OpcowsBuffReminderDB.Options.clicktocast = v
        Changed()
    end)
    clickOn:SetHitRectInsets(0, 0, 0, 0)
    clickOn:SetPoint("LEFT", clickLabel, "RIGHT", 6, -1)
    Tooltip(clickOn, "Click to cast",
        "Clicking a buff group's icon casts its spell on you, out of combat. "
        .. "Each buff group picks its spell or turns it off on the Buff groups tab. Unchecked, no icon can be clicked.")
    -- shows the click saved in Options[key]: click it once, then again with the button and keys to
    -- use. It can't be the click saved in Options[other], which is used to do what.
    local function ClickCapture(key, other, what)
        local b = Button(page, "", 170, nil)
        b:RegisterForClicks("AnyUp")
        b:SetScript("OnClick", function(self, button)
            if not self.listening then
                self.listening = true
                self:SetText("|cff00ff00Click here with it|r")
                return
            end
            local opts = OpcowsBuffReminderDB.Options
            local click = BR.ClickFrom(button)
            if click and click == opts[other] then
                self:SetText("|cffff4040Used to " .. what .. ", try another|r")
                return
            end
            self.listening = nil
            if click then opts[key] = click end
            Changed()
        end)
        b:SetScript("OnHide", function(self) self.listening = nil end)
        return b
    end
    local clickButton = ClickCapture("clickbutton", "dismissbutton", "dismiss")
    clickButton:SetPoint("LEFT", clickOn, "RIGHT", 4, 1)
    Tooltip(clickButton, "Click to cast with",
        "The click that casts: any mouse button, with Shift, Ctrl or Alt held if you like. "
        .. "One with a key held leaves a plain click free, so an icon can't be cast by accident.\n\n"
        .. "|cff808080Click this, then click it again the way you want to cast.|r")

    local dismissLabel = Label(page, "Click to dismiss:")
    dismissLabel:SetPoint("TOPLEFT", 0, -385)
    local dismissOn = Check(page, "", function(v)
        OpcowsBuffReminderDB.Options.dismiss = v
        Changed()
    end)
    dismissOn:SetHitRectInsets(0, 0, 0, 0)
    dismissOn:SetPoint("LEFT", dismissLabel, "RIGHT", 6, -1)
    Tooltip(dismissOn, "Click to dismiss",
        "Clicking an icon this way hides it until the buff is put on again, yours or a party member's. "
        .. "It works in combat too, so while it's on your icons catch clicks, the same as action buttons do.")
    local dismissButton = ClickCapture("dismissbutton", "clickbutton", "cast")
    dismissButton:SetPoint("LEFT", dismissOn, "RIGHT", 4, 1)
    Tooltip(dismissButton, "Click to dismiss with",
        "The click that dismisses an icon: any mouse button, with Shift, Ctrl or Alt held if you like. "
        .. "It can't be the click that casts.\n\n"
        .. "|cff808080Click this, then click it again the way you want to dismiss.|r")

    local partyLabel = Label(page, "Party:")
    partyLabel:SetPoint("TOPLEFT", 0, -415)
    local partyOn = Check(page, "Remind party members", function(v)
        OpcowsBuffReminderDB.Options.party = v
        Changed()
    end)
    partyOn:SetPoint("LEFT", partyLabel, "RIGHT", 6, -1)
    Tooltip(partyOn, "Party reminders",
        "Once you've given a party member a buff from one of your buff groups, its icon shows by their party frame, or on a panel, when it's gone. "
        .. "Only buffs you've been seen giving them count. The dismiss click on an icon hides it until you buff them with it again.\n\n"
        .. "Hidden in combat. Unlock the icons to move the panel. Buff groups can opt out on the Buff groups tab.")
    local partyWarn = Check(page, "Early warning", function(v)
        OpcowsBuffReminderDB.Options.partywarn = v
        Changed()
    end)
    partyWarn:SetPoint("LEFT", partyOn, "RIGHT", 150, 0)
    Tooltip(partyWarn, "Party early warning",
        "Also show a party member's buff before it runs out, using the buff group's early warning time.")
    local DOCKS = { "auto", "right", "left", "above", "below", "panel" }
    local DOCK_LABELS = { panel = "On the panel", auto = "By party frames", right = "Right of party frames",
        left = "Left of party frames", above = "Above party frames", below = "Below party frames" }
    local partyDock = Button(page, "", 140, function(self)
        local opts = OpcowsBuffReminderDB.Options
        opts.partydock = NextIn(DOCKS, opts.partydock)
        self:SetText(DOCK_LABELS[opts.partydock])
        Changed()
    end)
    partyDock:SetPoint("LEFT", partyWarn, "RIGHT", 90, 0)
    Tooltip(partyDock, "Where party reminders show",
        "By each member's frame in Blizzard's party frames, standard or raid-style, or on the panel. "
        .. "\"By party frames\" picks the side from where the frames are: beside them when they're stacked, "
        .. "above or below when they're side by side, toward the middle of the screen. "
        .. "Or pick a side yourself. The icons follow the frames when they're moved. "
        .. "Members whose frame isn't showing, or with frames from another addon, go on the panel.\n\n"
        .. "|cff808080Click to switch.|r")

    local reset = Button(page, "Reset all settings", 140, function()
        StaticPopup_Show("OPCOWSBUFFREMINDER_RESET")
    end)
    reset:SetPoint("BOTTOMRIGHT", 0, 0)
    local join = Button(page, "Icons in one row", 120, function() BR.JoinBars() end)
    join:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    Tooltip(join, "Icons in one row", "Puts every icon back in one row, where the first set of icons is.")

    local copyPicker = Picker(page, "Saved settings", 340, 380, 30)
    -- save these settings by name, at the top of the picker
    local saveLabel = Label(copyPicker, "Save as:", "GameFontHighlightSmall")
    saveLabel:SetPoint("TOPLEFT", 12, -60)
    local saveName = EditBox(copyPicker, 196)
    saveName:SetPoint("LEFT", saveLabel, "RIGHT", 8, 0)
    local function Save()
        local name = Trim(saveName:GetText())
        if name == "" then return end
        saveName:ClearFocus()
        if BR.HasSave(name) then
            StaticPopup_Show("OPCOWSBUFFREMINDER_OVERWRITE_SAVE", name, nil, name)
            return
        end
        BR.SaveSettings(name)
        BR.Print('Settings saved as "' .. name .. '".')
        saveName:SetText("")
        copyPicker:Reload()
    end
    local saveButton = Button(copyPicker, "Save", 60, Save)
    saveButton:SetPoint("LEFT", saveName, "RIGHT", 6, 0)
    saveName:SetScript("OnEnterPressed", Save)
    saveName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Tooltip(saveButton, "Save settings",
        "Saves a copy of this character's buff groups, weapon enchants, options and icon placement under this name. "
        .. "Every character on the account can load it. Later changes here don't change the save; save again to update it.")

    local function Header(text)
        return { text = "|cffffd100" .. text .. "|r" }
    end
    local function CharacterRows()
        local rows = { Header("Saved") }
        local saves = BR.GetSaves()
        for _, s in ipairs(saves) do
            local color = s.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[s.class]
            local label = color and ("|c%s%s|r"):format(color.colorStr, s.name) or s.name
            table.insert(rows, {
                name = s.name,
                text = ("%s |cff808080(%d buff group%s, %s)|r"):format(label, s.groups, s.groups == 1 and "" or "s",
                    date("%Y-%m-%d", s.time)),
                onClick = function()
                    copyPicker:Hide()
                    StaticPopup_Show("OPCOWSBUFFREMINDER_LOAD_SAVE", s.name, nil, s.name)
                end,
                onRemove = function()
                    StaticPopup_Show("OPCOWSBUFFREMINDER_DELETE_SAVE", s.name, nil, s.name)
                end,
            })
        end
        if #saves == 0 then
            table.insert(rows, { text = "|cff808080Nothing saved yet.|r" })
        end
        table.insert(rows, Header("Characters"))
        local n = #rows
        for _, c in ipairs(BR.GetCharacters()) do
            local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
            local label = color and ("|c%s%s|r"):format(color.colorStr, c.key) or c.key
            table.insert(rows, {
                name = c.key,
                text = ("%s |cff808080(%d buff group%s)|r"):format(label, c.groups, c.groups == 1 and "" or "s"),
                onClick = function()
                    copyPicker:Hide()
                    StaticPopup_Show("OPCOWSBUFFREMINDER_COPY", c.key, nil, c.key)
                end,
                onRemove = function()
                    BR.ForgetCharacter(c.key)
                    copyPicker:Reload()
                end,
            })
        end
        if #rows == n then
            table.insert(rows, { text = "|cff808080No other characters yet. Log in on one with Buff Reminder and it's listed here.|r" })
        end
        return rows
    end
    local copy = Button(page, "Save / load...", 100, function(self)
        if copyPicker:IsShown() then copyPicker:Hide() return end
        saveName:SetText("")
        copyPicker:Open(self, CharacterRows)
    end)
    copy:SetPoint("RIGHT", join, "LEFT", -8, 0)
    page.copyPicker = copyPicker
    Tooltip(copy, "Save and load settings",
        "Save these settings by name for any character on the account to load, or load a save or another "
        .. "character's settings in place of this character's buff groups, weapon enchants, options and icon placement.\n\n"
        .. "Characters are listed once they've logged in with Buff Reminder. The X deletes a save or forgets a character.")

    function page:Refresh()
        -- a save was made or deleted from a popup
        if copyPicker:IsShown() then copyPicker:Reload() end
        conds:Load(DefaultTarget())
        size:Load()
        alpha:Load()
        warnAlpha:Load()
        missingStyle:Load()
        warnStyle:Load()
        sound:Load()
        unlock:SetChecked(not BR.locked)
        hide:SetChecked(BR.hideAll)
        minimap:SetChecked(not OpcowsBuffReminderDB.Options.minimap.hide)
        clickOn:SetChecked(OpcowsBuffReminderDB.Options.clicktocast)
        clickButton.listening = nil
        clickButton:SetText(BR.ClickLabel(OpcowsBuffReminderDB.Options.clickbutton))
        dismissOn:SetChecked(OpcowsBuffReminderDB.Options.dismiss)
        dismissButton.listening = nil
        dismissButton:SetText(BR.ClickLabel(OpcowsBuffReminderDB.Options.dismissbutton))
        partyOn:SetChecked(OpcowsBuffReminderDB.Options.party)
        partyWarn:SetChecked(OpcowsBuffReminderDB.Options.partywarn)
        partyWarn:SetEnabled(OpcowsBuffReminderDB.Options.party)
        partyDock:SetText(DOCK_LABELS[OpcowsBuffReminderDB.Options.partydock])
        partyDock:SetEnabled(OpcowsBuffReminderDB.Options.party)
        local t = OpcowsBuffReminderDB.Options.icontext
        showTime:SetChecked(t.time)
        showSwipe:SetChecked(t.swipe)
        showStacks:SetChecked(t.stacks)
        priority:SetText(PRIORITY_LABELS[t.priority])
    end
end

-- main window ------------------------------------------------------------------------------
local function CreateConfig()
    local f = CreateFrame("Frame", "OpcowsBuffReminderConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 610)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    table.insert(UISpecialFrames, "OpcowsBuffReminderConfig")

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Opcow's Buff Reminder")

    -- the game's tabs hanging under the window, like the character window's. Plain buttons along
    -- the top if the template is missing.
    f.tabs = {}
    local panelTabs = PanelTemplates_SetTab and PanelTemplates_SetNumTabs
    local function SelectTab(index)
        for i, tab in ipairs(f.tabs) do
            tab.page:SetShown(i == index)
            if not panelTabs then
                if i == index then tab:LockHighlight() else tab:UnlockHighlight() end
            end
        end
        if panelTabs then PanelTemplates_SetTab(f, index) end
        BR.RefreshConfig()
    end
    local pages = { { "Buff groups", CreateGroupsPage }, { "Options", CreateOptionsPage } }
    for i, info in ipairs(pages) do
        local tab
        if panelTabs then
            local ok, t = pcall(CreateFrame, "Button", "OpcowsBuffReminderConfigTab" .. i, f, "PanelTabButtonTemplate")
            if ok and t then tab = t else panelTabs = nil end
        end
        if tab then
            tab:SetText(info[1])
            tab:SetScript("OnClick", function()
                PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
                SelectTab(i)
            end)
            if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
            if i == 1 then
                tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
            else
                tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", -15, 0)
            end
        else
            tab = Button(f, info[1], 110, function() SelectTab(i) end)
            tab:SetPoint("TOPLEFT", 12 + (i - 1) * 114, -30)
        end
        f.tabs[i] = tab
    end
    -- a template that failed partway leaves earlier tabs made from it, so go back to buttons for all
    if not panelTabs then
        for i, tab in ipairs(f.tabs) do
            if tab:GetObjectType() == "Button" and tab:GetName() then
                tab:Hide()
                f.tabs[i] = Button(f, pages[i][1], 110, function() SelectTab(i) end)
                f.tabs[i]:SetPoint("TOPLEFT", 12 + (i - 1) * 114, -30)
            end
        end
    end
    -- tabs underneath give the pages the room the buttons took
    local top = panelTabs and -30 or -62
    for i, tab in ipairs(f.tabs) do
        tab.page = CreateFrame("Frame", nil, f)
        tab.page:SetPoint("TOPLEFT", 14, top)
        tab.page:SetPoint("BOTTOMRIGHT", -14, 32)
        pages[i][2](tab.page)
    end
    if panelTabs then
        f.Tabs = f.tabs
        PanelTemplates_SetNumTabs(f, #f.tabs)
        f:SetHeight(f:GetHeight() - (62 + top))
        -- keep the tabs on screen too
        f:SetClampRectInsets(0, 0, 0, -32)
    end
    SelectTab(1)

    local footer = Label(f, "Text fields: press |cffffffffEnter|r to save, |cffffffffEscape|r to undo. |cffffd100Yellow|r text isn't saved yet.", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 12)

    f:SetScript("OnShow", BR.RefreshConfig)
    return f
end

function BR.RefreshConfig()
    if not config or not config:IsShown() then return end
    for _, tab in ipairs(config.tabs) do
        if tab.page:IsShown() then tab.page:Refresh() end
    end
end

function BR.ToggleConfig()
    config = config or CreateConfig()
    config:SetShown(not config:IsShown())
end

-- script editor ----------------------------------------------------------------------------
local function CreateEditor()
    local e = CreateFrame("Frame", "OpcowsBuffReminderScriptEditor", UIParent, "BasicFrameTemplateWithInset")
    e:SetSize(500, 320)
    e:SetPoint("CENTER", 0, 40)
    e:SetFrameStrata("DIALOG")
    e:SetToplevel(true)
    e:SetMovable(true)
    e:SetClampedToScreen(true)
    e:EnableMouse(true)
    e:RegisterForDrag("LeftButton")
    e:SetScript("OnDragStart", e.StartMoving)
    e:SetScript("OnDragStop", e.StopMovingOrSizing)
    e:Hide()
    table.insert(UISpecialFrames, "OpcowsBuffReminderScriptEditor")

    e.title = e.TitleText
    if not e.title then
        e.title = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        e.title:SetPoint("TOP", 0, -5)
    end

    local help = Label(e, 'Lua code. The icon is hidden while the script returns true.\nExample: return UnitPower("player") < 2000', "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, -32)

    local box = Box(e)
    box:SetPoint("TOPLEFT", 12, -64)
    box:SetPoint("BOTTOMRIGHT", -12, 44)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -28, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(440)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    if ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, sf) end)
    end
    sf:SetScrollChild(eb)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    e.edit = eb

    e.err = Label(e, "", "GameFontRedSmall")
    e.err:SetPoint("BOTTOMLEFT", 16, 18)
    e.err:SetPoint("RIGHT", e, "RIGHT", -190, 0)
    e.err:SetWordWrap(false)

    local save = Button(e, "Save", 80, function()
        local code = Trim(eb:GetText())
        if code ~= "" then
            local fn, err = loadstring(code, "script")
            if not fn then
                e.err:SetText(err)
                return
            end
        end
        e.target.setScript(code)
        e:Hide()
        Changed()
    end)
    save:SetPoint("BOTTOMRIGHT", -12, 12)
    local cancel = Button(e, "Cancel", 80, function() e:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -4, 0)

    return e
end

function BR.EditScript(target)
    editor = editor or CreateEditor()
    editor.target = target
    editor.title:SetText("Script: " .. target.name)
    editor.edit:SetText(target.getScript() or "")
    editor.err:SetText("")
    editor:Show()
    editor.edit:SetFocus()
end

-- addon compartment (the addons button by the minimap) --------------------------------------
function OpcowsBuffReminder_OnAddonCompartmentClick(addonName, buttonName)
    if IsShiftKeyDown() then
        BR.SetLocked(not BR.locked)
        BR.Print(BR.locked and "Icons locked." or "Icons unlocked. Drag an icon to move it with the icons snapped to it, Shift-drag to pull it away on its own.")
    elseif buttonName == "RightButton" then
        BR.ToggleHidden()
    else
        BR.ToggleConfig()
    end
    BR.RefreshConfig()
end

function OpcowsBuffReminder_OnAddonCompartmentEnter(addonName, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Opcow's Buff Reminder")
    GameTooltip:AddLine("Left-click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to hide or show the icons.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock or lock the icons.", 1, 1, 1)
    GameTooltip:Show()
end

function OpcowsBuffReminder_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- minimap button, same clicks as the compartment, drag to move it around the minimap ---------
local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(OpcowsBuffReminderDB.Options.minimap.angle)
    -- on the edge of the minimap, whatever size it is
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "OpcowsBuffReminderMinimapButton", Minimap)
    -- same layout as LibDBIcon so it matches other addons' buttons
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")
    -- the BR coin from the 1.12 config button, cropped inside its dark rim
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetTexture(BR.MEDIA .. "cbutton")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(self, button)
        OpcowsBuffReminder_OnAddonCompartmentClick("OpcowsBuffReminder", button)
    end)
    b:SetScript("OnEnter", function(self) OpcowsBuffReminder_OnAddonCompartmentEnter("OpcowsBuffReminder", self) end)
    b:SetScript("OnLeave", OpcowsBuffReminder_OnAddonCompartmentLeave)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            OpcowsBuffReminderDB.Options.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

function BR.UpdateMinimap()
    if not Minimap then return end
    local hide = OpcowsBuffReminderDB.Options.minimap.hide
    if hide and not minimapButton then return end
    minimapButton = minimapButton or CreateMinimapButton()
    PlaceMinimapButton()
    minimapButton:SetShown(not hide)
end
