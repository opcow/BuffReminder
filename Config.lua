-- Config.lua
-- Author      : mcrane
--
-- Options window, script editor, addon compartment and minimap buttons. Everything is built in Lua on
-- first use, none of it is protected so it works in combat.

local BR = BuffReminder
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
    local group = BRVars.BuffGroups[g]
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
    local e = BRVars.Enchants[slot]
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
    local opts = BRVars.Options
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

StaticPopupDialogs["BUFFREMINDER_DELETE_GROUP"] = {
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

StaticPopupDialogs["BUFFREMINDER_COPY"] = {
    text = "Replace this character's BuffReminder settings with %s's? This deletes this character's buff groups.",
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

StaticPopupDialogs["BUFFREMINDER_RESET"] = {
    text = "Clear all BuffReminder settings? This deletes all of your buff groups.",
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

-- groups page ------------------------------------------------------------------------------
local function CreateGroupsPage(page)
    -- a buff group's name, or an enchant group's slot
    local selected, selectedSlot

    -- the selected buff or enchant group
    local function Current()
        if selectedSlot then return BRVars.Enchants[selectedSlot] end
        return BRVars.BuffGroups[selected]
    end

    local groupsLabel = Label(page, "Buff groups")
    groupsLabel:SetPoint("TOPLEFT", 0, 0)
    local groups = ScrollList(page, 176, 300)
    groups:SetPoint("TOPLEFT", 0, -16)

    local newLabel = Label(page, "New group:", "GameFontHighlightSmall")
    newLabel:SetPoint("TOPLEFT", groups, "BOTTOMLEFT", 2, -8)
    local newEdit = EditBox(page, 116)
    newEdit:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 4, -2)
    local function NewGroup()
        local g = Trim(newEdit:GetText())
        if g == "" then return end
        if not BRVars.BuffGroups[g] then BR.AddBuffToGroup(g, nil) end
        selected, selectedSlot = g, nil
        newEdit:SetText("")
        newEdit:ClearFocus()
        Changed()
    end
    newEdit:SetScript("OnEnterPressed", NewGroup)
    local newBtn = Button(page, "Add", 50, NewGroup)
    newBtn:SetPoint("LEFT", newEdit, "RIGHT", 4, 0)

    local empty = Label(page, "Create a buff group to get started.\nPut buffs that replace each other,\nlike different food buffs, in the same group.", "GameFontHighlight")
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
        StaticPopup_Show("BUFFREMINDER_DELETE_GROUP", selected, nil, selected)
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
        for g, group in pairs(BRVars.BuffGroups) do
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

    local missingLabel = Label(detail, "When missing:")
    missingLabel:SetPoint("TOPLEFT", 0, -336)
    local glowLabel = Label(detail, "Glow", "GameFontHighlightSmall")
    glowLabel:SetPoint("LEFT", missingLabel, "RIGHT", 10, 0)
    local glow = Button(detail, "", 90, function()
        local group = Current()
        group.glow = NextIn(BR.GLOW_ORDER, group.glow)
        Changed()
    end)
    glow:SetPoint("LEFT", glowLabel, "RIGHT", 6, 0)
    Tooltip(glow, "Glow when missing",
        "A glow around the icon while the buff is missing, not while it's only running out.\n\n"
        .. "|cffffd100Default:|r follows the Options tab.\n"
        .. "|cffffd100Pulse:|r a glow that fades in and out.\n"
        .. "|cffffd100Flash:|r the same, fast.\n"
        .. "|cffffd100Steady:|r a glow that stays lit.\n"
        .. "|cffffd100Spell alert:|r the game's proc glow, like an action button's. A pulse if the game won't show it.\n"
        .. "|cff808080Click to change.|r")
    local overlayLabel = Label(detail, "Color", "GameFontHighlightSmall")
    overlayLabel:SetPoint("LEFT", glow, "RIGHT", 12, 0)
    local overlay = Button(detail, "", 80, function()
        local group = Current()
        group.overlay = NextIn(BR.OVERLAY_ORDER, group.overlay)
        Changed()
    end)
    overlay:SetPoint("LEFT", overlayLabel, "RIGHT", 6, 0)
    Tooltip(overlay, "Color when missing",
        "A color washed over the icon while the buff is missing, ex: red.\n\n"
        .. "|cffffd100Default:|r follows the Options tab.\n"
        .. "|cff808080Click to change.|r")

    local combatLabel = Label(detail, "In combat:")
    combatLabel:SetPoint("TOPLEFT", 0, -366)
    local combat = Button(detail, "", 130, function()
        local group = BRVars.BuffGroups[selected]
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
    local sizeLabel = Label(detail, "Icon size:")
    sizeLabel:SetPoint("LEFT", combat, "RIGHT", 20, 0)
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
    local combatStatus = Label(detail, "", "GameFontHighlightSmall")
    combatStatus:SetPoint("TOPLEFT", combatLabel, "BOTTOMLEFT", 0, -10)
    combatStatus:SetPoint("RIGHT", detail, "RIGHT")

    function page:Refresh()
        if selected and not BRVars.BuffGroups[selected] then selected = nil end
        local names = SortedKeys(BRVars.BuffGroups)
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
                icon = BRVars.BuffGroups[g].icon,
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
        for _, w in ipairs({ delete, buffsLabel, buffsHint, buffs, buffEdit, addBtn, pickBtn, combatLabel, combat, combatStatus }) do
            w:SetShown(not ench)
        end
        enchNow:SetShown(ench)
        enchHint:SetShown(ench)
        stacksLabel:SetText(ench and "Warn at charges:" or "Warn at stacks:")
        -- enchants have no combat setting, the size takes its place
        sizeLabel:ClearAllPoints()
        if ench then
            sizeLabel:SetPoint("TOPLEFT", 0, -366)
        else
            sizeLabel:SetPoint("LEFT", combat, "RIGHT", 20, 0)
        end

        local group = Current()
        stacks:Load()
        timer:SetText(BR.TIMERS[group.timer])
        glow:SetText(BR.GLOWS[group.glow])
        overlay:SetText(BR.OVERLAYS[group.overlay])
        size:Load()
        if ench then
            icon:SetTexture(EnchantIcon(selectedSlot))
            name:SetText(BR.ENCHANT_NAMES[selectedSlot])
            enchNow:SetText(EnchantNow(selectedSlot))
            conds:Load(EnchantTarget(selectedSlot))
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
        combat:SetText(BR.COMBAT_MODES[group.combat])
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
    local note = Label(page, "Copied to new groups.", "GameFontHighlightSmall")
    note:SetPoint("LEFT", header, "RIGHT", 10, -1)
    local conds = ConditionsPanel(page)
    conds:SetPoint("TOPLEFT", 0, -28)

    local dispHeader = Label(page, "Display", "GameFontNormalLarge")
    dispHeader:SetPoint("TOPLEFT", 0, -150)

    local sizeLabel = Label(page, "Icon size:")
    sizeLabel:SetPoint("TOPLEFT", 0, -177)
    local size = ValueBox(page, 40,
        function() return BRVars.Options.size end,
        NumberSetter(10, 400, function(n)
            BRVars.Options.size = n
            BR.ApplyLayout()
        end))
    size:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
    Tooltip(size, "Icon size", "10 to 400. Groups can have their own size on the Buff groups tab.")

    local alphaLabel = Label(page, "Opacity:")
    alphaLabel:SetPoint("LEFT", size, "RIGHT", 20, 0)
    local missingLabel = Label(page, "missing", "GameFontHighlightSmall")
    missingLabel:SetPoint("LEFT", alphaLabel, "RIGHT", 8, 0)
    local alpha = ValueBox(page, 36,
        function() return BRVars.Options.alpha end,
        NumberSetter(0, 1, function(n) BRVars.Options.alpha = n end))
    alpha:SetPoint("LEFT", missingLabel, "RIGHT", 6, 0)
    Tooltip(alpha, "Opacity when missing", "Icons whose buff is gone. 0 (invisible) to 1 (solid).")
    local warnLabel = Label(page, "warning", "GameFontHighlightSmall")
    warnLabel:SetPoint("LEFT", alpha, "RIGHT", 10, 0)
    local warnAlpha = ValueBox(page, 36,
        function() return BRVars.Options.warnalpha end,
        NumberSetter(0, 1, function(n) BRVars.Options.warnalpha = n end))
    warnAlpha:SetPoint("LEFT", warnLabel, "RIGHT", 6, 0)
    Tooltip(warnAlpha, "Opacity when warning",
        "Icons whose buff is still up but running out (early warning time) or low on stacks. 0 (invisible) to 1 (solid).")

    local soundLabel = Label(page, "Warning sound:")
    soundLabel:SetPoint("TOPLEFT", 0, -207)
    local sound = ValueBox(page, 150,
        function()
            local id = BRVars.Options.warnsound
            return id and (BR.SoundName(id) or id)
        end,
        function(text)
            if not BR.SetSound(text) then BR.Print("Unknown sound " .. text .. ".") end
        end)
    sound:SetPoint("LEFT", soundLabel, "RIGHT", 10, 0)
    Tooltip(sound, "Warning sound", "Played when a new icon appears. A sound kit id or a SOUNDKIT name like RAID_WARNING. Leave empty for no sound.")
    local test = Button(page, "Test", 50, function()
        if BRVars.Options.warnsound then PlaySound(BRVars.Options.warnsound, "Master") end
    end)
    test:SetPoint("LEFT", sound, "RIGHT", 6, 0)

    local soundPicker = Picker(page, "Warning sound", 300, 340)
    local function SoundRows()
        local current = BRVars.Options.warnsound
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
        BRVars.Options.minimap.hide = not v
        BR.UpdateMinimap()
    end)
    minimap:SetPoint("TOPLEFT", 360, -232)

    local textLabel = Label(page, "Icons show:")
    textLabel:SetPoint("TOPLEFT", 0, -263)
    local showTime = Check(page, "Time left", function(v) BRVars.Options.icontext.time = v; Changed() end)
    showTime:SetPoint("LEFT", textLabel, "RIGHT", 8, -1)
    Tooltip(showTime, "Time left", "The time left as text at the top of the icon. Groups can override this on the Buff groups tab.")
    local showSwipe = Check(page, "Swipe", function(v) BRVars.Options.icontext.swipe = v; Changed() end)
    showSwipe:SetPoint("LEFT", showTime, "RIGHT", 70, 0)
    Tooltip(showSwipe, "Swipe", "The time left as a clock swipe darkening the icon. Groups can override this on the Buff groups tab.")
    local showStacks = Check(page, "Stack count", function(v) BRVars.Options.icontext.stacks = v; Changed() end)
    showStacks:SetPoint("LEFT", showSwipe, "RIGHT", 56, 0)
    local bothLabel = Label(page, "When both:")
    bothLabel:SetPoint("LEFT", showStacks, "RIGHT", 84, 1)
    local PRIORITY_NEXT = { both = "time", time = "stacks", stacks = "both" }
    local PRIORITY_LABELS = { both = "Show both", time = "Time only", stacks = "Stacks only" }
    local priority = Button(page, "", 100, function()
        local t = BRVars.Options.icontext
        t.priority = PRIORITY_NEXT[t.priority]
        Changed()
    end)
    priority:SetPoint("LEFT", bothLabel, "RIGHT", 6, 0)
    Tooltip(priority, "When both apply",
        "An icon can show time left text (top) and a stack count (bottom right) at once. On small icons they can crowd it, pick one to show only that.\n|cff808080Click to change.|r")

    local missingLabel = Label(page, "When missing:")
    missingLabel:SetPoint("TOPLEFT", 0, -293)
    local glowLabel = Label(page, "Glow", "GameFontHighlightSmall")
    glowLabel:SetPoint("LEFT", missingLabel, "RIGHT", 10, 0)
    local glow = Button(page, "", 90, function()
        BRVars.Options.glow = NextIn(BR.GLOW_ORDER, BRVars.Options.glow, true)
        Changed()
    end)
    glow:SetPoint("LEFT", glowLabel, "RIGHT", 6, 0)
    Tooltip(glow, "Glow when missing",
        "A glow around icons while their buff is missing, not while it's only running out. "
        .. "Groups can have their own on the Buff groups tab.\n\n"
        .. "|cffffd100Pulse:|r a glow that fades in and out.\n"
        .. "|cffffd100Flash:|r the same, fast.\n"
        .. "|cffffd100Steady:|r a glow that stays lit.\n"
        .. "|cffffd100Spell alert:|r the game's proc glow, like an action button's. A pulse if the game won't show it.\n"
        .. "|cff808080Click to change.|r")
    local overlayLabel = Label(page, "Color", "GameFontHighlightSmall")
    overlayLabel:SetPoint("LEFT", glow, "RIGHT", 12, 0)
    local overlay = Button(page, "", 80, function()
        BRVars.Options.overlay = NextIn(BR.OVERLAY_ORDER, BRVars.Options.overlay, true)
        Changed()
    end)
    overlay:SetPoint("LEFT", overlayLabel, "RIGHT", 6, 0)
    Tooltip(overlay, "Color when missing",
        "A color washed over icons while their buff is missing, ex: red. "
        .. "Groups can have their own on the Buff groups tab.\n|cff808080Click to change.|r")

    local reset = Button(page, "Reset all settings", 140, function()
        StaticPopup_Show("BUFFREMINDER_RESET")
    end)
    reset:SetPoint("BOTTOMRIGHT", 0, 0)
    local join = Button(page, "Icons in one row", 120, function() BR.JoinBars() end)
    join:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    Tooltip(join, "Icons in one row", "Puts every icon back in one row, where the first set of icons is.")

    local copyPicker = Picker(page, "Copy settings from", 300, 300)
    local function CharacterRows()
        local rows = {}
        for _, c in ipairs(BR.GetCharacters()) do
            local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
            local label = color and ("|c%s%s|r"):format(color.colorStr, c.key) or c.key
            table.insert(rows, {
                name = c.key,
                text = ("%s |cff808080(%d group%s)|r"):format(label, c.groups, c.groups == 1 and "" or "s"),
                onClick = function()
                    copyPicker:Hide()
                    StaticPopup_Show("BUFFREMINDER_COPY", c.key, nil, c.key)
                end,
                onRemove = function()
                    BR.ForgetCharacter(c.key)
                    copyPicker:Reload()
                end,
            })
        end
        if #rows == 0 then
            rows[1] = { text = "|cff808080No other characters yet. Log in on one with BuffReminder and it's listed here.|r" }
        end
        return rows
    end
    local copy = Button(page, "Copy from...", 100, function(self)
        if copyPicker:IsShown() then copyPicker:Hide() return end
        copyPicker:Open(self, CharacterRows)
    end)
    copy:SetPoint("RIGHT", join, "LEFT", -8, 0)
    page.copyPicker = copyPicker
    Tooltip(copy, "Copy from another character",
        "Replace this character's buff groups, weapon enchants, options and icon placement with another character's. "
        .. "Characters are listed once they've logged in with BuffReminder. The X forgets one.")

    function page:Refresh()
        conds:Load(DefaultTarget())
        size:Load()
        alpha:Load()
        warnAlpha:Load()
        glow:SetText(BR.GLOWS[BRVars.Options.glow])
        overlay:SetText(BR.OVERLAYS[BRVars.Options.overlay])
        sound:Load()
        unlock:SetChecked(not BR.locked)
        hide:SetChecked(BR.hideAll)
        minimap:SetChecked(not BRVars.Options.minimap.hide)
        local t = BRVars.Options.icontext
        showTime:SetChecked(t.time)
        showSwipe:SetChecked(t.swipe)
        showStacks:SetChecked(t.stacks)
        priority:SetText(PRIORITY_LABELS[t.priority])
    end
end

-- main window ------------------------------------------------------------------------------
local function CreateConfig()
    local f = CreateFrame("Frame", "BuffReminderConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(600, 520)
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
    table.insert(UISpecialFrames, "BuffReminderConfig")

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("BuffReminder")

    f.tabs = {}
    local function SelectTab(index)
        for i, tab in ipairs(f.tabs) do
            tab.page:SetShown(i == index)
            if i == index then tab:LockHighlight() else tab:UnlockHighlight() end
        end
        BR.RefreshConfig()
    end
    for i, info in ipairs({ { "Buff groups", CreateGroupsPage }, { "Options", CreateOptionsPage } }) do
        local tab = Button(f, info[1], 110, function() SelectTab(i) end)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 114, -30)
        tab.page = CreateFrame("Frame", nil, f)
        tab.page:SetPoint("TOPLEFT", 14, -62)
        tab.page:SetPoint("BOTTOMRIGHT", -14, 32)
        info[2](tab.page)
        f.tabs[i] = tab
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
    local e = CreateFrame("Frame", "BuffReminderScriptEditor", UIParent, "BasicFrameTemplateWithInset")
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
    table.insert(UISpecialFrames, "BuffReminderScriptEditor")

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
function BuffReminder_OnAddonCompartmentClick(addonName, buttonName)
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

function BuffReminder_OnAddonCompartmentEnter(addonName, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("BuffReminder")
    GameTooltip:AddLine("Left-click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to hide or show the icons.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock or lock the icons.", 1, 1, 1)
    GameTooltip:Show()
end

function BuffReminder_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- minimap button, same clicks as the compartment, drag to move it around the minimap ---------
local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(BRVars.Options.minimap.angle)
    -- on the edge of the minimap, whatever size it is
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "BuffReminderMinimapButton", Minimap)
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
        BuffReminder_OnAddonCompartmentClick("BuffReminder", button)
    end)
    b:SetScript("OnEnter", function(self) BuffReminder_OnAddonCompartmentEnter("BuffReminder", self) end)
    b:SetScript("OnLeave", BuffReminder_OnAddonCompartmentLeave)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            BRVars.Options.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

function BR.UpdateMinimap()
    if not Minimap then return end
    local hide = BRVars.Options.minimap.hide
    if hide and not minimapButton then return end
    minimapButton = minimapButton or CreateMinimapButton()
    PlaceMinimapButton()
    minimapButton:SetShown(not hide)
end
