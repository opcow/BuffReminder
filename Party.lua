-- Opcow's Buff Reminder, party reminders
--
-- Party members missing a buff you gave them, beside their party frames or on a panel with one
-- row each: their name and the missing buffs' icons. Nothing is set up for a member ahead of time.
-- Once you're seen buffing them, by a cast aimed at them or a buff of yours on them, that buff's
-- group is remembered for them, and when it's gone from them its icon shows. The dismiss click on
-- an icon forgets that group for them until you buff them with it again. It's all forgotten when
-- they leave the party, or you do, and nothing is saved. Party auras are secret in combat, so the
-- icons hide for a fight.

local BR = OpcowsBuffReminder
local UNITS = { "party1", "party2", "party3", "party4" }
local ROW_GAP, ICON_GAP, NAME_WIDTH, ROW_MIN, ROLE_SIZE = 2, 2, 100, 18, 14
local BAR_SHADE = 0.6
local DOCK_GAP = 4      -- between a party frame and the icons beside it

-- [guid] = { groups = { [group name] = true }, dismissed = { [group name] = time } }. A buff of
-- yours on them counts as buffing them with its group if it landed after that group was dismissed.
local members = {}
BR.partyMembers = members
local shown = {}        -- [guid .. group] = true for the icons showing, to play the sound for new ones

local function Readable(...)
    for i = 1, select("#", ...) do
        if issecretvalue(select(i, ...)) then return false end
    end
    return true
end

local function Member(guid)
    local m = members[guid]
    if not m then
        m = { groups = {}, dismissed = {} }
        members[guid] = m
    end
    return m
end

-- the names a cast aimed at the unit can carry: Forever adds the surname after a space
local function UnitNames(unit)
    local name, surname = UnitName(unit)
    if type(name) ~= "string" or not Readable(name, surname) then return nil end
    local full = type(surname) == "string" and surname ~= "" and name .. " " .. surname or nil
    return name, full
end

-- [buff key or spell id] = { group names } for every buff group that reminds the party
local function GroupLookup()
    local map = {}
    local function add(key, g)
        map[key] = map[key] or {}
        table.insert(map[key], g)
    end
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        if group.party then
            for buff in pairs(group.buffs) do
                local key = BR.BuffKey(buff)
                add(key, g)
                if type(key) ~= "number" then
                    for _, id in ipairs(BR.SpellIds(buff)) do add(id, g) end
                end
            end
        end
    end
    return map
end

-- the groups the unit's buffs satisfy, [group name] = the longest lasting aura, and learns the
-- groups of buffs you cast on them. nil when an aura can't be read.
local function ReadUnit(unit, m, lookup)
    local present = {}
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if aura == nil then break end
        if not Readable(aura, aura.name, aura.spellId, aura.duration, aura.expirationTime, aura.sourceUnit) then
            return nil
        end
        local seen, keys = {}, {}
        if aura.spellId then table.insert(keys, aura.spellId) end
        if type(aura.name) == "string" then table.insert(keys, aura.name:lower()) end
        for _, key in ipairs(keys) do
            for _, g in ipairs(lookup[key] or {}) do
                if not seen[g] then
                    seen[g] = true
                    local prev = present[g]
                    local e = aura.expirationTime or 0
                    if not prev or (prev.expires ~= 0 and (e == 0 or e > prev.expires)) then
                        present[g] = { expires = e, duration = aura.duration or 0 }
                    end
                    -- yours, landed since the group was last dismissed for them
                    local mine = aura.sourceUnit ~= nil and UnitIsUnit(aura.sourceUnit, "player")
                    local since = m.dismissed[g]
                    local fresh = not since or ((aura.duration or 0) > 0 and e - aura.duration >= since)
                    if mine and fresh and not m.groups[g] then
                        m.groups[g] = true
                        m.dismissed[g] = nil
                        BR.Debug(("party: learned %s for %s from their aura"):format(g, UnitName(unit) or unit))
                    end
                end
            end
        end
    end
    return present
end

-- UNIT_SPELLCAST_SUCCEEDED of a cast aimed at someone else, groups are the ones the spell is in
function BR.OnPartyCast(groups, target)
    if not IsInGroup() then return end
    for _, unit in ipairs(UNITS) do
        local name, full = UnitNames(unit)
        if name and (target == name or target == full) then
            local guid = UnitGUID(unit)
            if not guid or issecretvalue(guid) then return end
            local m = Member(guid)
            for _, g in ipairs(groups) do
                local group = OpcowsBuffReminderDB.BuffGroups[g]
                if group and group.party and not m.groups[g] then
                    m.groups[g] = true
                    m.dismissed[g] = nil
                    BR.Debug(("party: learned %s for %s from a cast"):format(g, name))
                end
            end
            return
        end
    end
end

-- forget the members who left, or everyone when you did
local function Prune()
    if not IsInGroup() then
        wipe(members)
        return
    end
    local here = {}
    for _, unit in ipairs(UNITS) do
        local guid = UnitGUID(unit)
        if guid and not issecretvalue(guid) then here[guid] = true end
    end
    for guid in pairs(members) do
        if not here[guid] then members[guid] = nil end
    end
end

-- the panel ------------------------------------------------------------------------------------
-- a point the rows hang down from, with a handle above it for dragging while the icons are unlocked
local anchor = CreateFrame("Frame", "OpcowsBuffReminderParty", UIParent)
anchor:SetSize(1, 1)
anchor:SetFrameStrata("LOW")
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local handle = CreateFrame("Frame", nil, anchor)
handle:SetSize(140, 18)
handle:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
handle.bg = handle:CreateTexture(nil, "BACKGROUND")
handle.bg:SetAllPoints()
handle.bg:SetColorTexture(0, 0, 0, 0.6)
handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
handle.text:SetPoint("CENTER")
handle.text:SetText("Party reminders")
handle:EnableMouse(true)
handle:RegisterForDrag("LeftButton")
handle:SetScript("OnDragStart", function() anchor:StartMoving() end)
handle:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local left, top = anchor:GetLeft(), anchor:GetTop()
    if left and top then
        OpcowsBuffReminderDB.Options.partypos = { x = left, y = top }
        BR.PlaceParty()
    end
end)
handle:Hide()

function BR.PlaceParty()
    local pos = OpcowsBuffReminderDB.Options.partypos
    anchor:ClearAllPoints()
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        OpcowsBuffReminderDB.Options.partypos = nil
        anchor:SetPoint("TOPLEFT", UIParent, "CENTER", -150, -150)
    end
end

local rows = {}

local function AcquireRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, anchor)
    -- a bar in the member's class colour, with their role and name on it, like a unit frame
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetPoint("LEFT")
    r.bg:SetWidth(NAME_WIDTH)
    r.role = r:CreateTexture(nil, "ARTWORK")
    r.role:SetSize(ROLE_SIZE, ROLE_SIZE)
    r.role:SetPoint("LEFT", r.bg, "LEFT", 2, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.label:SetShadowColor(0, 0, 0, 1)
    r.label:SetShadowOffset(1, -1)
    r.icons = {}
    rows[i] = r
    return r
end

local function AcquireRowIcon(r, i)
    local f = r.icons[i]
    if f then return f end
    f = BR.NewIcon(r)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.groupName or "")
        GameTooltip:AddLine((self.missing and "Missing on " or "Running out on ") .. (r.who or ""), 1, 1, 1)
        local opts = OpcowsBuffReminderDB.Options
        if opts.dismiss and r.guid then
            GameTooltip:AddLine(BR.ClickLabel(opts.dismissbutton) .. " to dismiss it until you buff them with it again.",
                1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- forget the buff group for them until you're seen buffing them with it again
    f:SetScript("OnMouseUp", function(self, button)
        local m = r.guid and members[r.guid]
        if not (m and self.groupName and BR.IsDismissClick(button)) then return end
        m.groups[self.groupName] = nil
        m.dismissed[self.groupName] = GetTime()
        BR.Debug(("party: dismissed %s for %s"):format(self.groupName, r.who or "?"))
        BR.Refresh()
    end)
    r.icons[i] = f
    return f
end

-- the unit's class token and role ("TANK", "HEALER" or "DAMAGER"), nil when unknown or not set
local function ClassAndRole(unit)
    local _, class = UnitClass(unit)
    if type(class) ~= "string" or issecretvalue(class) then class = nil end
    local role
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, unit)
        if ok and type(r) == "string" and not issecretvalue(r) and r ~= "NONE" and r ~= "" then role = r end
    end
    return class, role
end

-- the small round role icons from the group finder: an atlas on newer clients, else the old texture
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local function SetRole(tex, role)
    if not ROLE_ATLAS[role] then
        tex:Hide()
        return false
    end
    local atlas = ROLE_ATLAS[role]
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        tex:SetTexCoord(unpack(ROLE_COORDS[role]))
    end
    tex:Show()
    return true
end

-- Blizzard's party frames that are showing, standard or raid-style, and its raid frames, [guid] =
-- frame. Each records the unit it shows. They're secure, so nothing is anchored to them: where they
-- are is read out of combat and the icons are placed there.
local function UnitFrames()
    local map = {}
    local function try(f, unit)
        if type(f) ~= "table" or not f.IsVisible or not f:IsVisible() then return end
        unit = f.displayedUnit or f.unit or unit
        if type(unit) ~= "string" or issecretvalue(unit) then return end
        local guid = UnitGUID(unit)
        if guid and not issecretvalue(guid) and not map[guid] then map[guid] = f end
    end
    if CompactPartyFrame and type(CompactPartyFrame.memberUnitFrames) == "table" then
        for _, f in ipairs(CompactPartyFrame.memberUnitFrames) do try(f) end
    end
    for i = 1, 5 do try(_G["CompactPartyFrameMember" .. i]) end
    -- the standard party frames: older clients name them, newer ones hang them off PartyFrame
    for i = 1, 4 do
        try(_G["PartyMemberFrame" .. i], "party" .. i)
        if type(PartyFrame) == "table" then try(PartyFrame["MemberFrame" .. i], "party" .. i) end
    end
    for i = 1, 40 do try(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for i = 1, 5 do try(_G["CompactRaidGroup" .. g .. "Member" .. i]) end
    end
    return map
end

-- the side for "auto", from where your party's frames are: beside them when they're stacked,
-- above or below when they're side by side, toward the middle of the screen so the icons fit.
-- Only your party's frames count, so in a raid it's your subgroup and not the groups beside it.
local function AutoSide(frames)
    local minX, maxX, minY, maxY, sumX, sumY, n = math.huge, -math.huge, math.huge, -math.huge, 0, 0, 0
    for _, unit in ipairs({ "player", unpack(UNITS) }) do
        local guid = UnitGUID(unit)
        local f = guid and not issecretvalue(guid) and frames[guid]
        local x, y
        if f then x, y = f:GetCenter() end
        if x and y and Readable(x, y) then
            local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = x * k, y * k
            minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
            sumX, sumY, n = sumX + x, sumY + y, n + 1
        end
    end
    -- one frame on its own counts as stacked
    if n > 1 and maxX - minX > maxY - minY then
        return sumY / n < UIParent:GetHeight() / 2 and "above" or "below"
    end
    return n > 0 and sumX / n > UIParent:GetWidth() / 2 and "left" or "right"
end

-- a row's icons, starting x along it from its LEFT going right (dir 1) or its RIGHT going left (-1)
local function DrawIcons(r, items, size, now, x, dir)
    local point = dir > 0 and "LEFT" or "RIGHT"
    for i, item in ipairs(items) do
        local f = AcquireRowIcon(r, i)
        f:ClearAllPoints()
        f:SetPoint(point, r, point, dir * (x + (i - 1) * (size + ICON_GAP)), 0)
        f.groupName, f.missing = item.g, item.missing
        BR.DrawIcon(f, item.group, item.missing, item.group and item.group.icon, size, item.expires,
            item.duration, now)
    end
    for i = #items + 1, #r.icons do r.icons[i]:Hide() end
end

-- lay out row n on the panel at y below the anchor with its name and icons, items = { { g, group,
-- missing, expires, duration }, ... }. Returns the row and its height.
local function DrawRow(n, y, name, class, role, items, size, now)
    local r = AcquireRow(n)
    r.who = name
    local h = math.max(size, ROW_MIN)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        -- darkened, so white names stay readable on light colours like a priest's
        r.bg:SetColorTexture(c.r * BAR_SHADE, c.g * BAR_SHADE, c.b * BAR_SHADE, 0.9)
    else
        r.bg:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    end
    r.bg:SetHeight(h)
    r.bg:Show()
    r.label:ClearAllPoints()
    if SetRole(r.role, role) then
        r.label:SetPoint("LEFT", r.role, "RIGHT", 2, 0)
    else
        r.label:SetPoint("LEFT", r.bg, "LEFT", 4, 0)
    end
    r.label:SetPoint("RIGHT", r.bg, "RIGHT", -2, 0)
    r.label:SetText(name)
    r.label:Show()
    r:SetSize(NAME_WIDTH + ICON_GAP + #items * (size + ICON_GAP), h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
    DrawIcons(r, items, size, now, NAME_WIDTH + ICON_GAP, 1)
    r:Show()
    return r, h
end

-- lay out row n by the unit frame uf: "right" or "left" of it, the icons going away from the
-- frame, or "above" or "below" it, centred, for frames laid out side by side. The frame already
-- shows who it is. nil when the frame's edges can't be read.
local function DrawDocked(n, uf, side, name, items, size, now)
    local left, right, bottom, top = uf:GetLeft(), uf:GetRight(), uf:GetBottom(), uf:GetTop()
    if not (left and right and bottom and top) or not Readable(left, right, bottom, top) then return nil end
    -- the frame's edges in UIParent's coordinates, which the rows use
    local k = uf:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local r = AcquireRow(n)
    r.who = name
    r.bg:Hide()
    r.role:Hide()
    r.label:Hide()
    r:SetSize(#items * (size + ICON_GAP) - ICON_GAP, size)
    r:ClearAllPoints()
    local cx, cy = (left + right) / 2 * k, (bottom + top) / 2 * k
    if side == "left" then
        r:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left * k - DOCK_GAP, cy)
    elseif side == "above" then
        r:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, top * k + DOCK_GAP)
    elseif side == "below" then
        r:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, bottom * k - DOCK_GAP)
    else
        r:SetPoint("LEFT", UIParent, "BOTTOMLEFT", right * k + DOCK_GAP, cy)
    end
    DrawIcons(r, items, size, now, 0, side == "left" and -1 or 1)
    r:Show()
    return r
end

-- while the icons are unlocked, made up icons show where the reminders go and how they look: beside
-- the party frames when docked and there are some, otherwise four made up members on the panel
local PREVIEW = { { "DRUID", "TANK" }, { "PRIEST", "HEALER" }, { "MAGE", "DAMAGER" }, { "PALADIN" } }

-- returns the number of rows and whether the panel has any
local function DrawPreview(size, now, frames, side)
    local list = {}
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        if group.party then table.insert(list, g) end
    end
    table.sort(list)
    local function Items(n)
        local items = {}
        if #list == 0 then
            items[1] = { g = "Your buff groups", missing = true }
        else
            -- a different number of icons on each line, up to three
            for i = 1, math.min(#list, (n - 1) % 3 + 1) do
                local g = list[(n + i - 2) % #list + 1]
                items[i] = { g = g, group = OpcowsBuffReminderDB.BuffGroups[g], missing = true }
            end
        end
        return items
    end
    local n = 0
    if frames then
        for i, unit in ipairs(UNITS) do
            local guid = UnitGUID(unit)
            local uf = guid and not issecretvalue(guid) and frames[guid]
            local r = uf and DrawDocked(n + 1, uf, side, UnitNames(unit) or unit, Items(i), size, now)
            if r then
                r.guid = nil
                n = n + 1
            end
        end
        if n > 0 then return n, false end
    end
    local y = 0
    for i = 1, #UNITS do
        local r, h = DrawRow(i, y, "Party " .. i, PREVIEW[i][1], PREVIEW[i][2], Items(i), size, now)
        r.guid = nil
        y = y + h + ROW_GAP
    end
    return #UNITS, true
end

-- called by BR.Refresh. Draws the rows and adds their icons' clicks to clicks, true when an icon
-- is new since the last refresh.
function BR.RefreshParty(clicks, now)
    local opts = OpcowsBuffReminderDB.Options
    local db = OpcowsBuffReminderDB.BuffGroups
    if not anchor.placed then
        anchor.placed = true
        anchor:SetFrameLevel(BR.frame:GetFrameLevel())
        BR.PlaceParty()
    end
    local preview = opts.party and not BR.locked and not BR.hideAll
    local on = opts.party and not BR.hideAll and not BR.status.combat and IsInGroup()
    -- by party frames, read only out of combat (the rows are hidden in it anyway). Each refresh
    -- reads them again, so the icons follow a frame that's moved.
    local docked = opts.partydock ~= "panel" and not BR.status.combat
    local frames = docked and UnitFrames() or nil
    local side = opts.partydock
    if side == "auto" and frames then side = AutoSide(frames) end
    local n, newIcon, nowShown, panelUsed = 0, false, {}, false
    if preview then
        n, panelUsed = DrawPreview(opts.size, now, frames, side)
        -- the real lines are back when the icons are locked, without the sound for ones already there
        nowShown = shown
    elseif on and not BR.AurasSecret() then
        local lookup = GroupLookup()
        local size = opts.size
        local y = 0
        for _, unit in ipairs(UNITS) do
            local guid = UnitExists(unit) and UnitGUID(unit)
            if guid and not issecretvalue(guid) then
                local m = Member(guid)
                local present = ReadUnit(unit, m, lookup)
                local skip = not present or not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit)
                    or not UnitIsVisible(unit)
                local items = {}
                for g in pairs(skip and {} or m.groups) do
                    local group = db[g]
                    local p = present[g]
                    if not group then
                        m.groups[g] = nil
                    elseif not group.party or BR.IsSuppressed(group.conditions) or BR.scriptRes[g] then
                        -- hidden
                    elseif not p or (p.expires > 0 and p.expires <= now) then
                        table.insert(items, { g = g, group = group, missing = true })
                    elseif opts.partywarn and p.expires > 0 and p.expires - now <= group.warntime then
                        table.insert(items, { g = g, group = group, expires = p.expires, duration = p.duration })
                    end
                end
                if #items > 0 then
                    table.sort(items, function(a, b) return a.g < b.g end)
                    n = n + 1
                    local name = UnitNames(unit) or unit
                    -- by their party frame, or on the panel when theirs isn't showing
                    local r = frames and frames[guid]
                        and DrawDocked(n, frames[guid], side, name, items, size, now)
                    if not r then
                        local class, role = ClassAndRole(unit)
                        local h
                        r, h = DrawRow(n, y, name, class, role, items, size, now)
                        y = y + h + ROW_GAP
                        panelUsed = true
                    end
                    r.guid = guid
                    for i, item in ipairs(items) do
                        local f = r.icons[i]
                        local key = guid .. item.g
                        nowShown[key] = true
                        if not shown[key] then newIcon = true end
                        if BR.locked and f:GetAlpha() > 0 then
                            local spell = BR.ClickSpell(item.group)
                            if spell then
                                table.insert(clicks, { f = f, spell = spell, unit = unit, who = name })
                            end
                        end
                    end
                end
            end
        end
    end
    -- the handle drags the panel, so when docked it's only there while the panel has rows
    handle:SetShown(preview and (opts.partydock == "panel" or panelUsed))
    for i = n + 1, #rows do rows[i]:Hide() end
    -- in combat keep what was showing, so the sound doesn't play again after it
    if not BR.status.combat then shown = nowShown end
    return newIcon
end

-- events ---------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "GROUP_LEFT")
events:SetScript("OnEvent", function()
    Prune()
    if OpcowsBuffReminderDB and OpcowsBuffReminderDB.Options then BR.Refresh() end
end)
