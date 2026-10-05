-- OpcowsBuffReminder.lua
-- Author      : mcrane
--
-- WoW: Forever port. Buffs are read out of combat, when aura data is readable. In combat the
-- client turns aura data into secret values and the buff list can't be walked. Each group picks
-- how it's followed in combat:
-- * Cooldown Manager: each watched spell is asked about directly, which the game still answers
--   for spells it flags as never secret, then the Cooldown Manager's buff frames are read when
--   they track the buff. Otherwise the last snapshot is kept and expiry is predicted from the
--   expiration times recorded before the pull.
-- * Blizzard Auras: Blizzard's own aura button shows the buff over the group's icon for the
--   whole fight, with its exact time and stacks. Addon code can't read what it shows.
-- A buff you cast on yourself in combat is marked up right away, lasting as long as it did the
-- last time it was read. A full re-read happens after combat.

local ADDON_NAME = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local TICK = 1          -- seconds between status/timer checks
local ICON_SPACING = 2
local FONT_ICON_SIZE = 30   -- the icon size the game's number font looks right on

-- clients without secret values never have secrets
local issecretvalue = issecretvalue or function() return false end

OpcowsBuffReminder = {
    icons = {},             -- pooled icon frames
    groupState = {},        -- [group] = { present, expires (0 = permanent), duration, applications }
    castAt = {},            -- [group] = when its buff was last cast, for predicting cooldowns
    learnedIds = {},        -- [buff key] = spell id last seen on a matching aura, for combat lookups
    enchants = {},          -- [slot] = { present, expires, charges }
    scripts = {},           -- [group] = compiled condition script
    scriptRes = {},         -- [group] = last script result, true hides the icon
    alertScripts = {},      -- [alert] = compiled condition script of the alert
    alertScriptRes = {},    -- [alert] = last script result, true hides the icon
    scriptErrReported = {}, -- [function] = true once its runtime error has been printed
    enchantScripts = {},    -- [slot] = compiled condition script of the enchant group
    enchantScriptRes = {},  -- [slot] = last script result, true hides the icon
    shown = {},             -- icon keys shown by the last refresh, for the warning sound
    hideAll = false,
    needScan = true,
    elapsed = 0,
    status = {
        dead = false,
        instance = false,
        party = false,
        raid = false,
        resting = false,
        taxi = false,
        combat = false,
        mounted = false,
    },
}
local BR = OpcowsBuffReminder

BR.DefaultOptions = {
    ["version"] = "2.6",
    ["size"] = 30,
    ["warntime"] = 0,       -- seconds left when the icon starts showing, 0 only when the buff is gone
    ["alpha"] = 1.0,        -- opacity of an icon whose buff is missing
    ["warnalpha"] = 1.0,    -- and of one warning that the buff is running out or low on stacks
    ["glow"] = "none",      -- glow around icons whose buff is missing, see GLOWS
    ["overlay"] = "none",   -- colour washed over icons whose buff is missing, see OVERLAYS
    ["warnglow"] = "none",  -- and the same for icons warning it's running out or low on stacks
    ["warnoverlay"] = "none",
    ["clicktocast"] = true, -- clicking an icon casts its group's spell, each group picks the spell
    ["clickbutton"] = "1",  -- with this click, see ParseClick, "1" is a plain left click
    ["dismiss"] = true,     -- clicking an icon with dismissbutton hides it until the buff is put on again
    ["dismissbutton"] = "2", -- a plain right click
    ["combatbadge"] = false, -- crossed swords on the icons while you're in combat
    ["party"] = true,       -- party reminders, see Party.lua
    ["partywarn"] = false,  -- and their early warnings, using each group's warning time
    ["partydock"] = "auto", -- on the panel, or "right" / "left" / "above" / "below" Blizzard's party
                            -- frames, or "auto" to pick a side from how they're laid out
    ["script"] = "",
    ["minimap"] = {
        ["hide"] = false,
        ["angle"] = 225,
    },
    -- time text, cooldown swipe and stack count on the icons, priority picks which text shows when
    -- both apply: "time", "stacks" or "both"
    ["icontext"] = {
        ["time"] = true,
        ["swipe"] = true,
        ["stacks"] = true,
        ["priority"] = "both",
        -- "on", "above" or "below" the icon
        ["timepos"] = "on",
    },
    -- 0 = ignored, 1 = hide the icon while true, 2 = hide the icon while false
    -- always: 0 = use the other conditions, 1 = never show, 2 = always show
    ["conditions"] = {
        ["always"] = 0,
        ["dead"] = 1,
        ["instance"] = 0,
        ["party"] = 0,
        ["raid"] = 0,
        ["resting"] = 1,
        ["taxi"] = 1,
        ["combat"] = 0,
        ["mounted"] = 1,
    },
}
-- options that are valid but have no default value
local EXTRA_OPTIONS = { ["warnsound"] = true, ["position"] = true, ["bars"] = true, ["partypos"] = true }

local CONDITIONS = { "dead", "instance", "party", "raid", "resting", "taxi", "combat", "mounted" }
local ENCHANT_SLOTS = { main = 16, off = 17 }
local ENCHANT_NAMES = { main = "Main hand enchant", off = "Off hand enchant" }
local TEXT_PRIORITIES = { time = true, stacks = true, both = true }
local COMBAT_MODES = { cdm = "Cooldown Manager", blizzard = "Blizzard Auras" }
-- which hits you take use a buff group's charges in combat, see BR.OnHit
local HIT_USES = { auto = "Auto", off = "Off", hits = "Hits", physical = "Physical hits", absorbed = "Hits + absorbed" }
local HIT_USE_ORDER = { "auto", "off", "hits", "physical", "absorbed" }
-- what "auto" uses for buffs known to have charges, by the spell id of any rank: the hits that
-- use a charge and the cooldown, a little under the game's to allow for when hits arrive
local CHARGE_BUFFS = {
    [324] = { use = "hits", cd = 3.4 },       -- Lightning Shield, every 3.5 seconds
    [588] = { use = "physical", cd = 0 },     -- Inner Fire, every hit
    [18137] = { use = "absorbed", cd = 3.9 }, -- Shadowguard, every 4 seconds
}
-- how a group shows its time left, "default" follows the Options tab
local TIMERS = { default = "Default", text = "Text", swipe = "Swipe", both = "Text and swipe", none = "None" }
local TIMER_ORDER = { "default", "text", "swipe", "both", "none" }
-- how a group marks a missing buff, "default" follows the Options tab
local GLOWS = { default = "Default", none = "None", pulse = "Pulse", flash = "Flash", steady = "Steady",
    alert = "Spell alert" }
local GLOW_ORDER = { "default", "none", "pulse", "flash", "steady", "alert" }
local OVERLAYS = { default = "Default", none = "None", red = "Red", orange = "Orange", yellow = "Yellow",
    green = "Green", blue = "Blue", purple = "Purple", black = "Dark" }
local OVERLAY_ORDER = { "default", "none", "red", "orange", "yellow", "green", "blue", "purple", "black" }
local OVERLAY_COLORS = {
    red = { 1, 0, 0 }, orange = { 1, 0.5, 0 }, yellow = { 1, 1, 0 }, green = { 0, 1, 0 },
    blue = { 0.2, 0.4, 1 }, purple = { 0.7, 0.2, 1 }, black = { 0, 0, 0 },
}
local OVERLAY_ALPHA = 0.45
-- game sounds an alert can play as its aura is put on. The game plays them itself, which takes
-- sound files, not sound kits: these are file ids.
local ALERT_SOUNDS = {
    { "Rubber Ducky", 566121 }, { "Cartoon FX", 566543 }, { "Shing!", 566240 }, { "Wham!", 566946 },
    { "Simon Chime", 566076 }, { "War Drums", 567275 }, { "Cheer", 567283 }, { "Humm", 569518 },
    { "Short Circuit", 568975 }, { "Explosion", 566982 }, { "Fel Nova", 568582 },
}

-- time text and swipe for a group, or the global setting for default ones
local function TimerStyle(group)
    local m = group and group.timer
    if m == "text" then return true, false
    elseif m == "swipe" then return false, true
    elseif m == "both" then return true, true
    elseif m == "none" then return false, false
    end
    local t = OpcowsBuffReminderDB.Options.icontext
    return t.time, t.swipe
end

-- where the time left text goes: at the top of the icon, or just above or below it
local TIME_POSITIONS = { on = "On the icon", above = "Above the icon", below = "Below the icon" }
local TIME_POSITION_ORDER = { "on", "above", "below" }
local function PlaceTime(fs, icon)
    local pos = OpcowsBuffReminderDB.Options.icontext.timepos
    -- centred in a box a little wider than the icon on both sides, so the text stays centred however
    -- the game sizes it (the cooldown's countdown drifted as it went from 2 digits to 1)
    local PAD = 20
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:ClearAllPoints()
    if pos == "above" then
        fs:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", -PAD, 2)
        fs:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", PAD, 2)
    elseif pos == "below" then
        fs:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -PAD, -2)
        fs:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", PAD, -2)
    else
        fs:SetPoint("TOPLEFT", icon, "TOPLEFT", -PAD, -2)
        fs:SetPoint("TOPRIGHT", icon, "TOPRIGHT", PAD, -2)
    end
end

-- util functions ---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cfff4f9a7Opcow's Buff Reminder:|r " .. msg)
end

-- /obr debug, prints what casts and combat reads decide
BR.debug = false
local function Debug(msg)
    if BR.debug then Print("|cff999999" .. msg .. "|r") end
end

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return c
end

local function FormatTime(s)
    if s <= 0 then return "" end
    if s >= 3600 then return ("%dh"):format(math.ceil(s / 3600)) end
    if s >= 60 then return ("%dm"):format(math.ceil(s / 60)) end
    return ("%d"):format(math.ceil(s))
end

-- sound kit id from a number, or a SOUNDKIT name ("RAID_WARNING", "raidwarning")
local function ResolveSound(v)
    if v == nil then return nil end
    local n = tonumber(v)
    if n then return n end
    if type(v) ~= "string" or SOUNDKIT == nil then return nil end
    local want = v:upper():gsub("_", "")
    for name, id in pairs(SOUNDKIT) do
        if name:gsub("_", "") == want then return id end
    end
    return nil
end

local function SpellTexture(buff)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, tonumber(buff) or buff)
        if ok and tex and not issecretvalue(tex) then return tex end
    end
    return nil
end

-- buff keys are names (matched case-insensitively) or spell ids
local function BuffKey(buff)
    return tonumber(buff) or buff:lower()
end

-- true when entry a lasts longer than entry b, permanent buffs last forever
local function Outlasts(a, b)
    if b.expires == 0 then return false end
    if a.expires == 0 then return true end
    return a.expires > b.expires
end

local function IsSuppressed(conditions)
    if conditions.always == 2 then return false end
    if conditions.always == 1 then return true end
    for _, k in ipairs(CONDITIONS) do
        local v, c = BR.status[k], conditions[k]
        if (v and c == 1) or (not v and c == 2) then return true end
    end
    return false
end

-- reading auras ----------------------------------------------------------------------------
local function AurasSecret()
    return C_Secrets ~= nil and C_Secrets.ShouldAurasBeSecret ~= nil and C_Secrets.ShouldAurasBeSecret()
end

-- returns found[name or spellId] = longest lasting entry, plus a list of all helpful auras.
-- errors if any aura is secret, a partial read would make present buffs look missing.
local function ReadPlayerBuffs()
    local found, list = {}, {}
    local function keep(key, entry)
        if key ~= nil and (found[key] == nil or Outlasts(entry, found[key])) then
            found[key] = entry
        end
    end
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if aura == nil then break end
        if issecretvalue(aura) or issecretvalue(aura.name) or issecretvalue(aura.spellId)
            or issecretvalue(aura.icon) or issecretvalue(aura.duration) or issecretvalue(aura.expirationTime) then
            error("secret aura")
        end
        local entry = {
            name = aura.name,
            spellId = aura.spellId,
            icon = aura.icon,
            duration = aura.duration or 0,
            expires = aura.expirationTime or 0,
            applications = not issecretvalue(aura.applications) and aura.applications or 0,
        }
        table.insert(list, entry)
        keep(aura.name and aura.name:lower(), entry)
        keep(aura.spellId, entry)
    end
    return found, list
end

-- buffs had before, by lower case name, so they can be picked later and their duration is known
-- when they're cast in combat. The oldest are dropped.
local SEEN_MAX = 200
local function RememberSeen(list)
    local seen, t, added = OpcowsBuffReminderDB.Seen, time(), false
    for _, e in ipairs(list) do
        if type(e.name) == "string" then
            local key = e.name:lower()
            local old = seen[key]
            if not old then added = true end
            -- the most charges it's had, what a cast in combat starts with
            local charges = math.max(e.applications or 0, old and type(old.charges) == "number" and old.charges or 0)
            seen[key] = { name = e.name, id = e.spellId, icon = e.icon, duration = e.duration, t = t,
                charges = charges > 0 and charges or nil }
        end
    end
    if not added then return end
    local keys = {}
    for k in pairs(seen) do table.insert(keys, k) end
    if #keys <= SEEN_MAX then return end
    table.sort(keys, function(a, b) return seen[a].t > seen[b].t end)
    for i = SEEN_MAX + 1, #keys do seen[keys[i]] = nil end
end

-- snapshot the state of every group, returns false if auras couldn't be read
function BR.ScanAuras()
    if AurasSecret() then
        BR.LiveScan()
        return false
    end
    local ok, found, list = pcall(ReadPlayerBuffs)
    if not ok then
        if not BR.readFailed then Debug("buffs can't be read, but the game didn't say auras are secret") end
        BR.readFailed = true
        return false
    end
    BR.readFailed = nil
    RememberSeen(list)
    BR.groupState = {}
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        local best
        for buff in pairs(group.buffs) do
            local key = BuffKey(buff)
            local e = found[key]
            if e then
                BR.learnedIds[key] = e.spellId
                if best == nil or Outlasts(e, best) then best = e end
            end
        end
        if best then
            group.icon = best.icon or group.icon
            BR.groupState[g] = { present = true, expires = best.expires, duration = best.duration,
                applications = best.applications }
        else
            BR.groupState[g] = { present = false }
        end
    end
    -- an alert's icon and the ids of its aura's ranks, for following it in combat
    for aura, alert in pairs(OpcowsBuffReminderDB.Alerts) do
        local e = found[BuffKey(aura)]
        if e then
            alert.icon = e.icon or alert.icon
            if type(e.spellId) == "number" then alert.ids[e.spellId] = true end
        end
    end
    BR.needScan = false
    BR.auraScans = (BR.auraScans or 0) + 1
    BR.ComparePredictedCharges()
    return true
end

-- a number that isn't secret, or nil
local function Num(v)
    if not issecretvalue(v) and type(v) == "number" then return v end
end

local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and not issecretvalue(name) then return name end
end

-- CHARGE_BUFFS by name, so every rank matches, once all the names could be read
local chargeBuffNames
local function ChargeBuff(buff)
    if not chargeBuffNames then
        local names = {}
        for id, rule in pairs(CHARGE_BUFFS) do
            local name = SpellName(id)
            if not name then names = nil break end
            names[name] = rule
        end
        if not names then return nil end
        chargeBuffNames = names
    end
    return chargeBuffNames[tonumber(buff) and SpellName(tonumber(buff)) or buff]
end

-- which hits use a buff group's charges and their cooldown, "auto" looked up from its buffs
function BR.HitUse(group)
    if group.hituse ~= "auto" then return group.hituse, group.hitcd end
    for b in pairs(group.buffs) do
        local rule = ChargeBuff(b)
        if rule then return rule.use, rule.cd end
    end
    return "off", 0
end

-- /obr debug, after a fight the charges counted by hits against the real count, for tuning a
-- buff group's Cooldown
local predictedCharges
function BR.NotePredictedCharges()
    if not BR.debug then return end
    predictedCharges = {}
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        local st = BR.groupState[g]
        if BR.HitUse(group) ~= "off" and st then
            predictedCharges[g] = st.present and (Num(st.applications) or "?") or 0
        end
    end
end

function BR.ComparePredictedCharges()
    if not predictedCharges then return end
    for g, n in pairs(predictedCharges) do
        local st = BR.groupState[g]
        local real = st and st.present and (st.applications or 0) or 0
        local group = OpcowsBuffReminderDB.BuffGroups[g]
        local hint = ""
        if type(n) == "number" and n < real then
            hint = ", counted too many hits: raise its Cooldown"
        elseif type(n) == "number" and n > real then
            hint = group and select(2, BR.HitUse(group)) > 0 and ", missed hits: lower its Cooldown" or ", missed hits"
        end
        Debug(("after combat, %s: counted %s charges, really %d%s"):format(g, tostring(n), real, hint))
    end
    predictedCharges = nil
end

-- in-combat reads --------------------------------------------------------------------------
-- The buff list can't be walked in combat, but a single spell can still be looked up. The
-- answer is trusted for spells the game flags as never secret. Everything else falls back to
-- the Cooldown Manager's buff frames, then to the prediction from the last snapshot.
local function NeverSecret(id)
    if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum and Enum.SecrecyLevel) then return false end
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, id)
    return ok and not issecretvalue(level) and level == Enum.SecrecyLevel.NeverSecret
end

-- spell ids of every rank in the player's spellbook, by lower case name. Cleared when the
-- spellbook changes.
local function BookIds(name)
    if not BR.book then
        BR.book = {}
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
            pcall(function()
                local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
                for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                    local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
                    if info then
                        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                            local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                            local id, n = item and Num(item.spellID), item and item.name
                            if id and type(n) == "string" and not issecretvalue(n) then
                                n = n:lower()
                                BR.book[n] = BR.book[n] or {}
                                table.insert(BR.book[n], id)
                            end
                        end
                    end
                end
            end)
        end
    end
    return BR.book[name:lower()] or {}
end

-- spell ids to look a buff up by: the id itself, or for a name the id last seen on the aura,
-- the id of the player's own spell with that name and every rank of it in the spellbook
local function SpellIds(buff)
    local id = tonumber(buff)
    if id then return { id } end
    local ids, seen = {}, {}
    local function add(v)
        if v and not seen[v] then
            seen[v] = true
            table.insert(ids, v)
        end
    end
    add(BR.learnedIds[BuffKey(buff)])
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, buff)
        add(ok and type(info) == "table" and Num(info.spellID) or nil)
    end
    for _, v in ipairs(BookIds(buff)) do add(v) end
    return ids
end

-- cooldowns --------------------------------------------------------------------------------
-- A buff that's your own spell can't be put back while the spell is cooling down, ex:
-- Berserking, so its group isn't shown until it's ready.
local GCD = 1.5
-- shorter cooldowns are the global cooldown, which can read a little over 1.5
local MIN_COOLDOWN = 2

-- your own spell's id for a buff, the highest rank, or nil if it isn't a spell you have
local function OwnSpellId(buff)
    local name = buff
    if tonumber(buff) then
        if not (C_Spell and C_Spell.GetSpellName) then return nil end
        local ok, n = pcall(C_Spell.GetSpellName, tonumber(buff))
        if not ok or type(n) ~= "string" or issecretvalue(n) then return nil end
        name = n
    end
    local best
    for _, id in ipairs(BookIds(name)) do
        if not best or id > best then best = id end
    end
    return best
end

-- [spell id] = when its cooldown ends, from the last read. In combat the game hides cooldowns,
-- so one read before the pull is still known during it.
local coolEnds = {}

-- when the spell's cooldown ends, 0 when it's ready, nil when it can't be read
local function ReadCooldown(id)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
        if not ok or type(cd) ~= "table" or issecretvalue(cd) then return nil end
        start, dur = Num(cd.startTime), Num(cd.duration)
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if not ok then return nil end
        start, dur = Num(s), Num(d)
    end
    if not start or not dur then return nil end
    -- the global cooldown doesn't count
    if dur < MIN_COOLDOWN then return 0 end
    -- its length, for predicting it after a cast in combat
    if OpcowsBuffReminderDB and OpcowsBuffReminderDB.Cooldowns then OpcowsBuffReminderDB.Cooldowns[id] = dur end
    return start + dur
end

-- the cooldown's end as read, or from the last read while the game hides it
local function CooldownEnd(id)
    local ends = ReadCooldown(id)
    if ends then
        coolEnds[id] = ends
        return ends, true
    end
    return coolEnds[id], false
end

-- the game's base cooldown of a spell in seconds, nil when it has none or it can't be read
local function BaseCooldown(id)
    if not GetSpellBaseCooldown then return nil end
    local ok, b = pcall(GetSpellBaseCooldown, id)
    b = ok and Num(b)
    if b and b / 1000 >= MIN_COOLDOWN then return b / 1000 end
end

-- the spell's cooldown in seconds: the game's base cooldown, or the last one read
local function CooldownLength(id)
    local saved = OpcowsBuffReminderDB and OpcowsBuffReminderDB.Cooldowns
    local last = saved and saved[id]
    return BaseCooldown(id) or (last and last >= MIN_COOLDOWN and last or nil)
end

-- true when every buff in the group is your spell and none of them can be cast yet. A buff
-- that isn't your spell, like food, can always be had. When the cooldown can't be read, it's
-- predicted from when the buff was last cast and the spell's base cooldown.
-- /obr debug, what the cooldown check decides for a buff, printed when it changes
local coolSaid = {}
local function CoolDebug(buff, msg)
    if BR.debug and coolSaid[buff] ~= msg then
        coolSaid[buff] = msg
        Debug(("cooldown, %s: %s"):format(tostring(buff), msg))
    end
end

-- /obr debug turned on, every buff's cooldown line prints again
function BR.ClearCoolDebug()
    coolSaid = {}
end

local function GroupCooling(group, castAt, now)
    local any = false
    for buff in pairs(group.buffs) do
        local id = OwnSpellId(buff)
        if not id then
            CoolDebug(buff, "not your spell")
            return false
        end
        local ends, read = CooldownEnd(id)
        local length = CooldownLength(id)
        -- hidden: the later of the last read and a cast since
        if not read and castAt and length then ends = math.max(ends or 0, castAt + length) end
        CoolDebug(buff, ("spell %d, game says %s, cooldown %s, cast time %s: %s"):format(id,
            read and (ends > now and "cooling" or "ready") or "hidden",
            length and ("%gs"):format(length) or "unknown",
            castAt and "known" or "unknown",
            ends and ends > now and "hidden while cooling" or "shown"))
        if not ends or ends <= now then return false end
        any = true
    end
    return any
end

-- group state from aura data, filling unreadable fields from the previous state
local function LiveEntry(aura, prev)
    if not aura or issecretvalue(aura) then return nil end
    local was = prev and prev.present
    local stacks = Num(aura.applications)
    return {
        present = true,
        expires = Num(aura.expirationTime) or (was and prev.expires) or 0,
        duration = Num(aura.duration) or (was and prev.duration) or 0,
        applications = stacks or (was and prev.applications) or nil,
    }
end

-- returns a present entry, false when the buff is surely missing, or nil if unknown
local function LookupBuff(buff, prev)
    local ids = SpellIds(buff)
    local sure = #ids > 0
    for _, id in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, "player", id)
        if not ok then
            sure = false
        elseif aura then
            local e = LiveEntry(aura, prev)
            if e then return e end
            sure = false
        elseif not NeverSecret(id) then
            -- a secret aura answers nil just like a missing one
            sure = false
        end
    end
    -- by name catches other ranks of the spell
    if not tonumber(buff) and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", buff, "HELPFUL")
        local e = ok and LiveEntry(aura, prev)
        if e then return e end
    end
    if sure then return false end
    return nil
end

-- "missing" when this client or class has no Cooldown Manager, "off" when it's turned off
local function CDMState()
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return "missing" end
    if C_CooldownViewer.IsCooldownViewerAvailable then
        local ok, available = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
        if ok and available == false then return "missing" end
    end
    if C_CVar and C_CVar.GetCVarBool then
        local ok, on = pcall(C_CVar.GetCVarBool, "cooldownViewerEnabled")
        if ok and on == false then return "off" end
    end
    return "on"
end

-- spell id -> list of the Cooldown Manager's buff frames for it, empty when it's turned off
local function CDMFrames()
    local map = {}
    if CDMState() ~= "on" then return map end
    pcall(function()
        for _, name in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
            local viewer = _G[name]
            local pool = viewer and viewer.itemFramePool
            if pool and pool.EnumerateActive then
                for f in pool:EnumerateActive() do
                    local function add(id)
                        id = Num(id)
                        if id and id > 0 then
                            local list = map[id] or {}
                            map[id] = list
                            if list[#list] ~= f then list[#list + 1] = f end
                        end
                    end
                    local cid = Num(f.cooldownID)
                    local info = cid and C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
                    if type(info) == "table" then
                        add(info.spellID); add(info.overrideSpellID); add(info.linkedSpellID)
                        if type(info.linkedSpellIDs) == "table" then
                            for _, id in ipairs(info.linkedSpellIDs) do add(id) end
                        end
                    end
                    add(f.auraSpellID)
                end
            end
        end
    end)
    return map
end

-- /obr cdm, every buff frame of the Cooldown Manager with its spell ids and state
function BR.CDMDump()
    local function show(v)
        if issecretvalue(v) then return "secret" end
        return tostring(v)
    end
    Print("cooldown manager: " .. CDMState())
    for _, name in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        local viewer = _G[name]
        local pool = viewer and viewer.itemFramePool
        if not (pool and pool.EnumerateActive) then
            Print(name .. ": no frames")
        else
            local n = 0
            for f in pool:EnumerateActive() do
                n = n + 1
                local cid = f.cooldownID
                local ok, info = pcall(function()
                    return Num(cid) and C_CooldownViewer.GetCooldownViewerCooldownInfo(Num(cid))
                end)
                info = ok and type(info) == "table" and info or {}
                local linked = {}
                if type(info.linkedSpellIDs) == "table" then
                    for _, id in ipairs(info.linkedSpellIDs) do linked[#linked + 1] = show(id) end
                end
                local spell = Num(info.spellID)
                local nok, sname = pcall(function()
                    return spell and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
                end)
                sname = nok and sname or nil
                local sok, shown = pcall(f.IsShown, f)
                Print(("%s %d: %s, cooldown %s, spell %s, override %s, linked %s [%s], aura spell %s, shown %s, active %s, aura %s"):format(
                    name:sub(1, 7), n, show(sname), show(cid), show(info.spellID), show(info.overrideSpellID),
                    show(info.linkedSpellID), table.concat(linked, " "), show(f.auraSpellID),
                    sok and show(shown) or "?", show(f.isActive), show(f.auraInstanceID)))
            end
        end
    end
end

-- /obr debug, what a Cooldown Manager frame says about a buff, printed when it changes
local cdmSaid = {}
local function CDMDebug(buff, id, list, trusted)
    if not BR.debug then return end
    local function show(v)
        if issecretvalue(v) then return "secret" end
        return tostring(v)
    end
    local parts = {}
    for i, f in ipairs(list) do
        local ok, shown = pcall(f.IsShown, f)
        parts[i] = ("[aura %s, active %s, cached %s, shown %s, cooldown %s]"):format(
            show(f.auraInstanceID), show(f.isActive), f.auraDataCached and "yes" or "no",
            ok and show(shown) or "?", show(f.cooldownID))
    end
    local msg = ("cooldown manager, %s (spell %d), %d frames%s: %s"):format(tostring(buff), id, #list,
        trusted and "" or ", not seen up yet so predicted", table.concat(parts, " "))
    if cdmSaid[buff] ~= msg then
        cdmSaid[buff] = msg
        Debug(msg)
    end
end

-- what one Cooldown Manager frame says: an entry, false when it surely has no aura, nil when unknown
local function CDMFrameLookup(f, prev)
    local cached = LiveEntry(f.auraDataCached, prev)
    if cached then return cached end
    local inst, active = f.auraInstanceID, f.isActive
    if not issecretvalue(inst) and inst == nil then return false end
    if not issecretvalue(active) and type(active) == "boolean" then
        if not active then return false end
        local e = LiveEntry({}, prev)
        -- the manager's own timer for the aura, when its remaining time is readable
        if (issecretvalue(inst) or type(inst) == "number") and C_UnitAuras.GetAuraDuration then
            local ok, rem = pcall(function()
                return C_UnitAuras.GetAuraDuration("player", inst):GetRemainingDuration()
            end)
            rem = ok and Num(rem)
            if rem then e.expires = GetTime() + rem end
        end
        return e
    end
    return nil
end

-- buffs a Cooldown Manager frame has shown as up this session. Until then its frames saying
-- the buff is gone aren't believed, since the manager doesn't follow every buff it lists,
-- ex: Mark of the Wild while you have it
local cdmSeenUp = {}

-- same answers as LookupBuff, from the Cooldown Manager's buff frames. Any frame showing
-- the buff up wins
local function CDMLookup(frames, buff, prev)
    for _, id in ipairs(SpellIds(buff)) do
        local list = frames[id]
        if list then
            local gone = false
            for _, f in ipairs(list) do
                local e = CDMFrameLookup(f, prev)
                if e then
                    cdmSeenUp[buff] = true
                    CDMDebug(buff, id, list, true)
                    return e
                end
                if e == false then gone = true end
            end
            CDMDebug(buff, id, list, cdmSeenUp[buff])
            if gone and cdmSeenUp[buff] then return false end
        end
    end
    return nil
end

-- update the groups whose state can be read in combat, the rest keep their prediction. Right
-- after you cast one of a group's buffs the Cooldown Manager still shows it gone, which would
-- undo the cast, and its charges with it
local CAST_SETTLE = 1
function BR.LiveScan()
    if not C_UnitAuras.GetUnitAuraBySpellID then return end
    local frames
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        local prev = BR.groupState[g]
        local best, sure = nil, next(group.buffs) ~= nil
        for buff in pairs(group.buffs) do
            local e = LookupBuff(buff, prev)
            if e == nil then
                frames = frames or CDMFrames()
                e = CDMLookup(frames, buff, prev)
            end
            if e then
                if best == nil or Outlasts(e, best) then best = e end
            elseif e == nil then
                sure = false
            end
        end
        if best then
            BR.groupState[g] = best
        elseif sure and GetTime() - (BR.castAt[g] or 0) < CAST_SETTLE then
            -- just cast, the reads haven't caught up yet
        elseif sure then
            if prev and prev.present then
                Debug(("combat read: %s is gone (%s)"):format(g, frames and "cooldown manager" or "direct lookup"))
            end
            BR.groupState[g] = { present = false }
        end
    end
end

-- your casts -------------------------------------------------------------------------------
-- A buff you cast on yourself is up from the moment the cast lands, and lasts as long as it did
-- the last time it was read, so in combat its group doesn't wait for an aura that can't be read.
-- Out of combat the aura read that follows the cast replaces this with the exact state.
BR.sentSelf = {}        -- [spell id] = true when the last cast of it was on you, false when on someone else
BR.sentTarget = {}      -- [spell id] = the name the last cast of it was aimed at, when readable

local function Bool(v)
    if not issecretvalue(v) then return v and true or false end
end

-- true when the spell can only land on you or your party, ex: Ice Armor or Battle Shout
local function Untargeted(id)
    if not (C_Spell and C_Spell.SpellHasRange) then return false end
    local ok, r = pcall(C_Spell.SpellHasRange, id)
    return ok and not issecretvalue(r) and r == false
end

-- UNIT_SPELLCAST_SENT, works out whether the cast is on you so casts on other players can be
-- told apart. nil when it can't be told.
function BR.OnCastSent(target, id)
    id = Num(id)
    if not id then return end
    local onMe
    if type(target) == "string" and not issecretvalue(target) then
        -- nothing aimed at, or you. Forever gives your surname as UnitName's second value and
        -- adds it to the target after a space, ex: "Brillig Ironhoof".
        local name, surname = UnitName("player")
        local full = type(surname) == "string" and surname ~= "" and name .. " " .. surname or name
        onMe = target == "" or target == name or target == full
        BR.sentTarget[id] = target
    else
        BR.sentTarget[id] = nil
        -- the target is hidden: a helpful spell lands on you unless someone friendly is selected
        local ok1, isMe = pcall(UnitIsUnit, "target", "player")
        local ok2, assist = pcall(UnitCanAssist, "player", "target")
        isMe, assist = ok1 and Bool(isMe), ok2 and Bool(assist)
        if isMe ~= nil and assist ~= nil then onMe = isMe or not assist end
    end
    BR.sentSelf[id] = onMe
    Debug(("sent %d, target %s, on you: %s"):format(id,
        issecretvalue(target) and "hidden" or tostring(target), tostring(onMe)))
end

-- UNIT_SPELLCAST_SUCCEEDED, marks the groups of a buff you cast on yourself as up
function BR.OnCast(id)
    if not Num(id) then
        Debug("cast with a hidden spell id")
        return
    end
    local onMe, target = BR.sentSelf[id], BR.sentTarget[id]
    BR.sentSelf[id], BR.sentTarget[id] = nil, nil
    if not (C_Spell and C_Spell.GetSpellName) then return end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if not ok or type(name) ~= "string" or issecretvalue(name) then
        Debug(("cast %d, its name can't be read"):format(id))
        return
    end
    name = name:lower()

    local groups = {}
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        for buff in pairs(group.buffs) do
            local key = BuffKey(buff)
            local match = key == id or key == name
            if not match then
                for _, v in ipairs(SpellIds(buff)) do
                    if v == id then match = true end
                end
            end
            if match then
                table.insert(groups, g)
                break
            end
        end
    end
    if #groups == 0 then return end

    -- a buff given to a party member is remembered for their reminders
    if not onMe and target and BR.OnPartyCast then BR.OnPartyCast(groups, target) end
    if not (onMe or Untargeted(id)) then
        Debug(("cast %s, not on you (%s)"):format(name, tostring(onMe)))
        return
    end
    -- the cast starts the spell's cooldown, whether or not the buff's duration is known
    local now = GetTime()
    for _, g in ipairs(groups) do BR.castAt[g] = now end
    -- without a duration seen before, the time left isn't known
    local seen = OpcowsBuffReminderDB.Seen[name]
    local dur = seen and Num(seen.duration)
    if not dur then
        Debug(("cast %s, its duration hasn't been seen yet"):format(name))
        return
    end

    local e = { present = true, expires = dur > 0 and now + dur or 0, duration = dur }
    for _, g in ipairs(groups) do
        -- another buff of the group may still outlast it
        local prev = BR.groupState[g]
        if not (prev and prev.present and prev.expires and Outlasts(prev, e)) then
            -- hits count down from full charges
            local charges = BR.HitUse(OpcowsBuffReminderDB.BuffGroups[g]) ~= "off" and Num(seen.charges) or nil
            BR.groupState[g] = { present = true, expires = e.expires, duration = e.duration,
                applications = charges }
            Debug(("cast %s, %s is up for %ds%s"):format(name, g, dur,
                charges and (" with " .. charges .. " charges") or ""))
        end
    end
    BR.Refresh()
end

-- UNIT_COMBAT on you. In combat, a buff group whose charges are used by hits loses one for each
-- hit that lands at least its cooldown after the last charge was used: any hit (hituse "hits",
-- ex: Lightning Shield, every 3.5 seconds) or physical ones ("physical", ex: Inner Fire, every
-- hit). Dodges, parries and misses don't count, and neither do hits a shield fully absorbs, ex:
-- Power Word: Shield, which come as a WOUND of 0, except for "absorbed" (ex: Shadowguard, every
-- 4 seconds). The cooldown runs on through a recast, so when a charge was last used is kept
-- apart from the buff's state.
-- Out of combat the aura read is exact, but the hit that starts a fight can come just before
-- PLAYER_REGEN_DISABLED, with its charge gone only once the auras are secret. That hit is
-- counted when combat starts unless an aura read came after it.
local SCHOOL_PHYSICAL = 1
local HIT_BEFORE_COMBAT = 1
local hitBeforeCombat
local chargeAt = {}
local function CountHit(absorbed, physical)
    local now, changed = GetTime(), false
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        local st = BR.groupState[g]
        local use, cd = BR.HitUse(group)
        local counts = use == "absorbed"
            or not absorbed and (use == "hits" or use == "physical" and physical)
        local n = counts and st and st.present and Num(st.applications)
        if n and n > 0 and now - (chargeAt[g] or 0) >= cd then
            chargeAt[g] = now
            if n == 1 then
                BR.groupState[g] = { present = false }
            else
                st.applications = n - 1
            end
            Debug(("hit, %s down to %d charges"):format(g, n - 1))
            changed = true
        end
    end
    if changed then BR.Refresh() end
end

local lastHitAt
function BR.OnHit(action, descriptor, amount, school)
    if issecretvalue(action) or action ~= "WOUND" then return end
    local absorbed = Num(amount) == 0
    local physical = Num(school) == SCHOOL_PHYSICAL
    if BR.debug then
        local function show(v) return issecretvalue(v) and "secret" or tostring(v) end
        local now = GetTime()
        local since = lastHitAt and now - lastHitAt < 60 and (", %.1fs after the last"):format(now - lastHitAt) or ""
        lastHitAt = now
        Debug(("hit for %s (%s), school %s%s%s%s"):format(show(amount), show(descriptor), show(school),
            absorbed and ", fully absorbed" or "", BR.status.combat and "" or ", out of combat", since))
    end
    if BR.status.combat then
        CountHit(absorbed, physical)
    else
        hitBeforeCombat = { at = GetTime(), scans = BR.auraScans, absorbed = absorbed, physical = physical }
    end
end

function BR.OnCombatStart()
    local hit = hitBeforeCombat
    hitBeforeCombat = nil
    if not hit or GetTime() - hit.at > HIT_BEFORE_COMBAT then return end
    if hit.scans ~= BR.auraScans then
        Debug("hit just before combat, already read")
        return
    end
    Debug("hit just before combat, counting it")
    CountHit(hit.absorbed, hit.physical)
end

-- a hand's temporary enchant or imbue from C_Item.GetWeaponEnchantInfo, ignoring permanent enchants.
-- false when there's none, nil when it can't be read
local function ReadWeaponEnchant(hand)
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, hand)
    if not ok or issecretvalue(list) or type(list) ~= "table" then return nil end
    local types = Enum.ItemEnchantType
    local found = false
    for _, w in ipairs(list) do
        if issecretvalue(w) or issecretvalue(w.hasEnchant) or issecretvalue(w.enchantType) then return nil end
        if w.hasEnchant and (w.enchantType == types.Temporary or w.enchantType == types.Imbue) then
            if issecretvalue(w.timeLeft) or issecretvalue(w.charges) then return nil end
            found = w
        end
    end
    return found
end

-- What you last put on each hand is remembered for clicking its icon, in the hand's
-- OpcowsBuffReminderDB.Enchants[slot].last as { item = id } for a poison, oil or stone, or
-- { spell = id } for an imbue. Nothing says which item or spell an enchant came from, so a cast of
-- yours is matched to an enchant that shows up on a hand within a few seconds of it.
local ENCHANT_MATCH = 3     -- seconds
local enchantCast           -- { id, item or spell, t } of your last cast that could be one
local enchantSent           -- the same, sent but not yet succeeded
local enchantAt = {}        -- [slot] = when an enchant last showed up on the hand

-- the spell id an item casts when used
local function ItemSpellId(item)
    local get = C_Item and C_Item.GetItemSpell or GetItemSpell
    if not get then return nil end
    local ok, _, id = pcall(get, item)
    if ok and not issecretvalue(id) then return id end
end

-- the item in your bags that casts spell id
local function BagItemFor(id)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local item = C_Container.GetContainerItemID(bag, slot)
            if item and not issecretvalue(item) and ItemSpellId(item) == id then return item end
        end
    end
end

-- an enchant and a cast close enough together are what you put on that hand
local function MatchEnchant()
    if not enchantCast then return end
    for slot, at in pairs(enchantAt) do
        if math.abs(at - enchantCast.t) <= ENCHANT_MATCH then
            OpcowsBuffReminderDB.Enchants[slot].last = { item = enchantCast.item, spell = enchantCast.spell }
            Debug(("%s: remembered %s %d"):format(ENCHANT_NAMES[slot], enchantCast.item and "item" or "spell",
                enchantCast.item or enchantCast.spell))
            enchantAt[slot] = nil
        end
    end
end

-- UNIT_SPELLCAST_SENT, while the item used is still in your bags. Out of combat only, when
-- enchants are put on, since it searches the bags.
local function EnchantCastSent(id)
    enchantSent = nil
    if BR.status.combat then return end
    if IsPlayerSpell and IsPlayerSpell(id) then
        enchantSent = { id = id, spell = id }
    else
        local item = BagItemFor(id)
        if item then enchantSent = { id = id, item = item } end
    end
end

-- UNIT_SPELLCAST_SUCCEEDED
local function EnchantCastDone(id)
    if not (enchantSent and enchantSent.id == id) then return end
    enchantCast, enchantSent = enchantSent, nil
    enchantCast.t = GetTime()
    MatchEnchant()
end

function BR.ScanEnchants()
    local now = GetTime()
    local old = { main = BR.enchants.main, off = BR.enchants.off }
    -- the old GetWeaponEnchantInfo misses imbues like Flametongue Weapon on Forever
    if C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.ItemEnchantType and Enum.WeaponSlot then
        local main = ReadWeaponEnchant(Enum.WeaponSlot.MainHand)
        local off = ReadWeaponEnchant(Enum.WeaponSlot.OffHand)
        if main == nil or off == nil then return end
        local function entry(w)
            if not w then return { present = false } end
            return { present = true, expires = now + (w.timeLeft or 0) / 1000, charges = w.charges or 0 }
        end
        BR.enchants.main = entry(main)
        BR.enchants.off = entry(off)
    else
        local r = { pcall(GetWeaponEnchantInfo) }
        if not r[1] then return end
        for i = 2, 9 do
            if issecretvalue(r[i]) then return end
        end
        local function entry(has, ms, charges)
            if not has then return { present = false } end
            return { present = true, expires = now + (ms or 0) / 1000, charges = charges or 0 }
        end
        -- hasEnchant, expirationMs, charges, enchantId for each hand
        BR.enchants.main = entry(r[2], r[3], r[4])
        BR.enchants.off = entry(r[6], r[7], r[8])
    end
    -- one that's new, or put on again with more time
    for slot, o in pairs(old) do
        local e = BR.enchants[slot]
        if e.present and o and (not o.present or e.expires > o.expires + 5) then enchantAt[slot] = now end
    end
    MatchEnchant()
end

-- the name of what you last put on a hand, nil for nothing remembered
function BR.EnchantLastName(slot)
    local last = OpcowsBuffReminderDB.Enchants[slot].last
    if type(last) ~= "table" then return nil end
    local ok, name
    if last.item then
        local get = C_Item and C_Item.GetItemNameByID or GetItemInfo
        ok, name = pcall(get, last.item)
        if not ok or type(name) ~= "string" or issecretvalue(name) then name = "item " .. last.item end
    elseif last.spell then
        ok, name = pcall(C_Spell.GetSpellName, last.spell)
        if not ok or type(name) ~= "string" or issecretvalue(name) then name = "spell " .. last.spell end
    end
    return name
end

-- the mark in the corner of a hand's enchant icon, like an action button's: how many of the last
-- used item are in your bags, red at none, or "?" for nothing remembered, red when the remembered
-- spell isn't yours. Shown out of combat while the icon could be clicked, and the count all the time
-- when the hand's showcount is on. Returns text, r, g, b, or nil for no mark.
function BR.EnchantMark(slot)
    local eg = OpcowsBuffReminderDB.Enchants[slot]
    local last = eg.last
    local click = OpcowsBuffReminderDB.Options.clicktocast and eg.click ~= "off" and not BR.status.combat
    if not (click or eg.showcount) then return nil end
    if type(last) ~= "table" then
        if click then return "?", 0.8, 0.8, 0.8 end
        return nil
    end
    if last.item then
        local count = (C_Item and C_Item.GetItemCount or GetItemCount)(last.item)
        if issecretvalue(count) then return nil end
        count = count or 0
        if count == 0 then return "0", 1, 0.1, 0.1 end
        return tostring(count), 1, 1, 1
    end
    if click and not (IsPlayerSpell and IsPlayerSpell(last.spell)) then return "?", 1, 0.1, 0.1 end
    return nil
end

-- why a hand's enchant icon can't be clicked, nil when it can
function BR.EnchantClickProblem(slot)
    local eg = OpcowsBuffReminderDB.Enchants[slot]
    local last = eg.last
    if not OpcowsBuffReminderDB.Options.clicktocast then return "Click to cast is off on the Options tab." end
    if eg.click == "off" then return "Click to apply is off for this hand on the Buff groups tab." end
    if type(last) ~= "table" then
        return "Nothing remembered yet. Put a poison, oil, stone or imbue on this hand out of combat and it will be."
    end
    if last.item then
        local count = (C_Item and C_Item.GetItemCount or GetItemCount)(last.item)
        if not issecretvalue(count) and (count or 0) == 0 then return "None left in your bags." end
    elseif not (IsPlayerSpell and IsPlayerSpell(last.spell)) then
        return "That spell isn't one of yours."
    end
    if BR.status.combat then return "Icons can't be clicked in combat." end
    return nil
end

-- what clicking a hand's enchant icon does, nil for nothing: { item = "item:id" } or { spell =
-- name }, with label its name. An item needs to be in your bags and a spell to be yours.
function BR.EnchantAction(slot)
    local eg = OpcowsBuffReminderDB.Enchants[slot]
    local last = eg.last
    if not OpcowsBuffReminderDB.Options.clicktocast or eg.click == "off" or type(last) ~= "table" then return nil end
    local name = BR.EnchantLastName(slot)
    if last.item then
        local count = (C_Item and C_Item.GetItemCount or GetItemCount)(last.item)
        if issecretvalue(count) or (count or 0) == 0 then return nil end
        return { item = "item:" .. last.item, label = name }
    elseif last.spell then
        if not (IsPlayerSpell and IsPlayerSpell(last.spell)) or name:find("^spell ") then return nil end
        return { spell = name, label = name }
    end
end

local function Flag(v, prev)
    if issecretvalue(v) then return prev end
    return v and true or false
end

function BR.UpdateStatus()
    local s = BR.status
    s.dead = Flag(UnitIsDeadOrGhost("player"), s.dead)
    s.resting = Flag(IsResting(), s.resting)
    s.taxi = Flag(UnitOnTaxi("player"), s.taxi)
    s.mounted = Flag(IsMounted(), s.mounted)
    s.party = Flag(IsInGroup(), s.party)
    s.raid = Flag(IsInRaid(), s.raid)
    local _, instanceType = IsInInstance()
    if not issecretvalue(instanceType) then
        s.instance = (instanceType == "party")
    end
end

-- condition scripts ------------------------------------------------------------------------
local function Compile(code, label)
    if code == nil or code == "" then return nil end
    local fn, err = loadstring(code, "OpcowsBuffReminder " .. label)
    if not fn then Print("Script error in " .. label .. ": " .. err) end
    return fn
end

local function RunScript(fn, prev)
    if not fn then return false end
    local ok, res = pcall(fn)
    if not ok then
        if not BR.scriptErrReported[fn] then
            BR.scriptErrReported[fn] = true
            Print("Script error: " .. tostring(res))
        end
        return prev
    end
    -- a script that returns combat data may hand back a secret, keep the last known answer
    if issecretvalue(res) then return prev end
    return res and true or false
end

function BR.CompileScripts()
    BR.scripts = {}
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        BR.scripts[g] = Compile(group.script, g)
    end
    BR.enchantScripts = {}
    for slot, e in pairs(OpcowsBuffReminderDB.Enchants) do
        BR.enchantScripts[slot] = Compile(e.script, ENCHANT_NAMES[slot])
    end
    BR.alertScripts = {}
    for aura, alert in pairs(OpcowsBuffReminderDB.Alerts) do
        BR.alertScripts[aura] = Compile(alert.script, aura)
    end
end

function BR.RunScripts()
    for g in pairs(OpcowsBuffReminderDB.BuffGroups) do
        BR.scriptRes[g] = RunScript(BR.scripts[g], BR.scriptRes[g])
    end
    for slot in pairs(OpcowsBuffReminderDB.Enchants) do
        BR.enchantScriptRes[slot] = RunScript(BR.enchantScripts[slot], BR.enchantScriptRes[slot])
    end
    for aura in pairs(OpcowsBuffReminderDB.Alerts) do
        BR.alertScriptRes[aura] = RunScript(BR.alertScripts[aura], BR.alertScriptRes[aura])
    end
end

-- display ----------------------------------------------------------------------------------
-- the parent of everything, the icons are placed by their rows' anchors
local frame = CreateFrame("Frame", "OpcowsBuffReminderFrame", UIParent)
frame:SetSize(1, 1)
frame:SetPoint("CENTER")
frame:SetFrameStrata("LOW")
frame:EnableMouse(false)
BR.frame = frame

-- an icon's texture, swipe, glow, overlay and texts, shared by the icons and the options previews
local function NewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetHideCountdownNumbers(true)
    -- the action button border, lit up and pulsing, over the icon and past its edges
    f.glow = f:CreateTexture(nil, "ARTWORK", nil, 7)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:Hide()
    local pulse = f.glow.CreateAnimationGroup and f.glow:CreateAnimationGroup()
    if pulse then
        f.fade = pulse:CreateAnimation("Alpha")
        f.fade:SetFromAlpha(1)
        f.fade:SetToAlpha(0.3)
        f.fade:SetDuration(0.6)
        pulse:SetLooping("BOUNCE")
        f.pulse = pulse
    end
    -- a colour washed over the icon, under the glow
    f.overlay = f:CreateTexture(nil, "ARTWORK", nil, 6)
    f.overlay:SetAllPoints()
    f.overlay:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.text:SetPoint("TOP", 0, -2)
    f.text:SetJustifyH("CENTER")
    -- stack count where the default buff frame puts it
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- a weapon enchant's bag count, placed when it's shown
    f.bag = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    return f
end

local function AcquireIcon(i)
    local f = BR.icons[i]
    if not f then
        f = NewIcon(frame)
        -- takes the mouse while unlocked, or to be dismissed
        f:EnableMouse(false)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) BR.IconDragStart(self) end)
        f:SetScript("OnDragStop", function() BR.IconDragStop() end)
        f:SetScript("OnMouseUp", function(self, button)
            if BR.locked and self.key and BR.IsDismissClick(button) then BR.DismissIcon(self.key) end
        end)
        f:SetScript("OnEnter", function(self) BR.IconTooltip(self) end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- the combat badge, beside the icon rather than in it so it stays over Blizzard's button and
        -- keeps its own opacity, hidden with the icon
        f.badge = CreateFrame("Frame", nil, frame)
        f.badge:SetFrameLevel(frame:GetFrameLevel() + 40)
        f.badge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.badge:EnableMouse(false)
        f.badge:Hide()
        local swords = f.badge:CreateTexture(nil, "OVERLAY")
        swords:SetAllPoints()
        swords:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        swords:SetTexCoord(0.5, 1, 0, 0.484375)
        f:HookScript("OnHide", function(self) self.badge:Hide() end)
        BR.icons[i] = f
    end
    return f
end

-- Blizzard Auras ---------------------------------------------------------------------------
-- Addon code can't read a secret aura in combat, but Blizzard's own aura button can show it. A
-- group set to Blizzard Auras gets a CustomAuraContainer with one slot, which Blizzard fills while
-- one of the group's spells is on you, drawing its icon, time and stacks exactly. Nothing tells
-- the addon whether the button is showing, so in combat the group's icon is always shown under it
-- and shows through when the buff is gone. The container and its button refuse changes in combat
-- and while auras are secret, so they're made, filtered and styled only outside both.
local live = {}     -- [group] = { holder, container, button, cd, count, ids, style, err }
local LIVE_SLOT = "buff"
-- alerts use the same, with fx their glow and colour, see the alerts section
local alertFrames = {}  -- [alert] = { holder, container, button, cd, count, fx, ids, style, err }

-- a holder for l, hidden until it's placed, with a container whose one slot Blizzard fills while
-- one of ids is on you. init(l, button) sets up the button. False with l.err if the client can't.
local function MakeContainer(l, slot, ids, init)
    local size = OpcowsBuffReminderDB.Options.size
    l.holder = CreateFrame("Frame", nil, frame)
    l.holder:SetSize(size, size)
    l.holder:SetPoint("CENTER")
    l.holder:SetFrameLevel(frame:GetFrameLevel() + 10)
    l.holder:SetAlpha(0)
    local ok, err = pcall(function()
        local c = CreateFrame("AuraContainer", nil, l.holder, "CustomAuraContainerTemplate")
        c:SetPoint("CENTER")
        c:SetSize(size, size)
        c:SetFrameLevel(l.holder:GetFrameLevel() + 1)
        c:SetUnit("player")
        pcall(c.EnableMouse, c, false)
        l.container = c
        c:AddAuraSlot(slot, "HELPFUL", {
            candidateFilters = { includeSpellIDs = ids },
            initializeFrame = function(button) init(l, button) end,
        })
    end)
    if not ok then l.err = tostring(err) end
    return ok
end

local function LiveIds(group)
    local ids, list = {}, {}
    for buff in pairs(group.buffs) do
        for _, id in ipairs(SpellIds(buff)) do
            if not ids[id] then
                ids[id] = true
                table.insert(list, id)
            end
        end
    end
    table.sort(list)
    return ids, table.concat(list, ",")
end

-- count text from 2 up, like Blizzard's, none at 0 or 1 for auras without stacks, ex: Mark of the
-- Wild or Clearcasting. With a low stack warning, from 1 up and red at or under it.
local function CountFormatter(warn)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local ok, fm = pcall(function()
        local fm = C_StringUtil.CreateNumericRuleFormatter()
        local points = { { threshold = 0, format = "" }, { threshold = 2, format = "%d" } }
        if warn > 0 then
            points = { { threshold = 0, format = "" }, { threshold = 1, format = "|cffff3030%d|r" },
                { threshold = warn + 1, format = "%d" } }
        end
        fm:SetBreakpoints(points)
        -- Blizzard formats inside its aura update, make sure it can't fail there
        for n = 0, warn + 1 do
            local text = fm:FormatNumber(n)
            if type(text) ~= "string" or issecretvalue(text) or (n == 0 and text ~= "")
                or (warn == 0 and n == 1 and text ~= "") then
                error("formatted " .. n .. " as " .. tostring(text))
            end
        end
        return fm
    end)
    return ok and fm or nil
end

-- the number font scaled to an icon's size, so bigger icons get bigger text
local function ScaleFont(fs, size)
    local font = NumberFontNormal
    if not (font and font.GetFont) then return end
    local file, height, flags = font:GetFont()
    if not file or not height then return end
    fs:SetFont(file, math.max(6, math.floor(height * size / FONT_ICON_SIZE + 0.5)), flags)
end

-- called by Blizzard once, when it makes the slot's button
local function InitLiveButton(l, button)
    local size = OpcowsBuffReminderDB.Options.size
    button:SetSize(size, size)
    button:SetPoint("CENTER", button:GetParent(), "CENTER", 0, 0)
    pcall(button.EnableMouse, button, false)
    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    button:SetIcon(tex)
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    button:SetDurationCooldown(cd)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
    l.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    l.count:SetPoint("BOTTOMRIGHT", -2, 2)
    l.cd, l.button = cd, button
end

-- size, text and count colour, when they changed. warn is the low stack warning, extra(size) styles
-- anything more, with extraKey changing when it would.
local function StyleLive(l, group, warn, extraKey, extra)
    local opts = OpcowsBuffReminderDB.Options
    local size = type(group.size) == "number" and group.size or opts.size
    local t = opts.icontext
    local time, swipe = TimerStyle(group)
    local showTime = time and t.priority ~= "stacks"
    local showStacks = t.stacks and t.priority ~= "time"
    local key = table.concat({ size, tostring(showTime), tostring(showStacks), tostring(swipe),
        warn, t.timepos, extraKey or "" }, ":")
    if key == l.style then return end
    local ok = pcall(function()
        l.container:SetSize(size, size)
        l.button:SetSize(size, size)
        l.cd:SetHideCountdownNumbers(not showTime)
        l.cd:SetDrawSwipe(swipe)
        -- the cooldown's countdown placed like the time text on our icons, clear of the count
        local fs = l.cd.GetCountdownFontString and l.cd:GetCountdownFontString()
        if fs then
            fs:SetFontObject("NumberFontNormal")
            ScaleFont(fs, size)
            PlaceTime(fs, l.button)
        end
        ScaleFont(l.count, size)
        l.count:SetAlpha(showStacks and 1 or 0)
        local fm = CountFormatter(warn)
        l.button:SetApplicationCount(l.count, fm and { formatter = fm } or nil)
        if extra then extra(size) end
    end)
    if ok then l.style = key end
end

-- make, refilter and restyle the containers of Blizzard Auras groups, out of combat only
function BR.UpdateLive()
    if InCombatLockdown() or AurasSecret() then return end
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        local l = live[g]
        if group.combat == "blizzard" and not (l and l.err) then
            local ids, key = LiveIds(group)
            if not l and key ~= "" then
                l = {}
                live[g] = l
                if MakeContainer(l, LIVE_SLOT, ids, InitLiveButton) then l.ids = key end
            elseif l and l.container and key ~= "" and key ~= l.ids then
                if pcall(l.container.SetAuraSlotCandidateFilters, l.container, LIVE_SLOT, { includeSpellIDs = ids }) then
                    l.ids = key
                end
            end
            if l and l.button then StyleLive(l, group, group.warnstacks) end
        end
    end
end

local function LiveReady(g)
    local l = live[g]
    return l ~= nil and l.container ~= nil and not l.err
end

-- how a group in Cooldown Manager mode is followed in combat, and whether that's worth a warning
local function CDMStatus(group)
    local secret, unknown = {}, false
    for buff in pairs(group.buffs) do
        local ids = SpellIds(buff)
        if #ids == 0 then unknown = true end
        for _, id in ipairs(ids) do
            if not NeverSecret(id) then secret[buff] = ids end
        end
    end
    if not next(secret) then
        if unknown then return "Not seen yet, it's predicted in combat until it is.", false end
        return "The game shows this buff to addons, it's read live in combat.", false
    end
    local state = CDMState()
    if state == "missing" then return "The Cooldown Manager isn't available, it's predicted in combat.", true end
    if state == "off" then return "The Cooldown Manager is turned off, it's predicted in combat.", true end
    local frames = CDMFrames()
    for buff, ids in pairs(secret) do
        local tracked
        for _, id in ipairs(ids) do
            if frames[id] then tracked = tracked or id end
        end
        if not tracked then return "The Cooldown Manager doesn't track it, it's predicted in combat.", true end
        -- the manager follows only the rank it holds, ex: Mark of the Wild 5232 while you have
        -- 6756, and adding it again doesn't change that
        local mine = BR.learnedIds[BuffKey(buff)] or OwnSpellId(buff)
        if mine and not frames[mine] then
            return ("The Cooldown Manager only follows another rank (spell %d, yours is %d), it's predicted in combat. Blizzard Auras can follow it."):format(tracked, mine), true
        end
    end
    return "The Cooldown Manager tracks it, it's read live in combat.", false
end

-- how a group is followed in combat, and whether that's worth a warning
function BR.CombatStatus(g)
    local group = OpcowsBuffReminderDB.BuffGroups[g]
    if not next(group.buffs) then return "No buffs yet.", false end
    if group.combat == "blizzard" then
        local l = live[g]
        if l and l.err then return "Blizzard Auras don't work on this client, it's predicted in combat.", true end
        local _, key = LiveIds(group)
        if key == "" then return "Spell id not known yet. Have the buff once, or add it by spell id.", true end
        if not LiveReady(g) then return "Blizzard Auras are set up after combat.", false end
        return "Blizzard's aura button shows it all fight, with exact time and stacks.", false
    end
    local text, warn = CDMStatus(group)
    if warn and BR.HitUse(group) ~= "off" then
        return "Predicted in combat, with a charge used by each hit you take.", false
    end
    return text, warn
end

-- tell the user once about groups that are only predicted in combat
local noticed = {}
function BR.CombatNotices(only)
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        if (only == nil or only == g) and group.conditions.always ~= 1 then
            local text, warn = BR.CombatStatus(g)
            if warn and noticed[g] ~= text then
                noticed[g] = text
                local hint = ""
                if group.combat == "cdm" and not text:find("Blizzard Auras can", 1, true) then
                    hint = " Add it to the Cooldown Manager's buffs, or switch the buff group to Blizzard Auras on the Buff groups tab (/obr)."
                end
                Print(('"%s": %s%s'):format(g, text, hint))
            end
        end
    end
end

function BR.SetCombatMode(g, mode)
    OpcowsBuffReminderDB.BuffGroups[g].combat = mode
    noticed[g] = nil
    BR.UpdateLive()
    BR.CombatNotices(g)
end

-- icon placement -------------------------------------------------------------------------------
-- Icons snap together on a grid. OpcowsBuffReminderDB.Options.bars holds the sets of snapped icons,
-- { left, top, cells = { { key, c, r, ha, va }, ... } }: c counts columns to the right and r rows
-- down from the top left cell, which is always 0, 0, and left, top is the set's top left corner
-- from the screen center. Each column is as wide and each row as tall as its biggest icon, and a
-- smaller icon sits in its cell by ha (-1 left, 0 center, 1 right) and va (-1 top, 0 middle,
-- 1 bottom), picked by where it was dropped. A straight row or column closes up and centres the
-- icons it's showing, like the 1.x row did, any other shape keeps its gaps. Unlocked, every icon
-- shows so it can be placed: dragging moves the whole set, Shift-drag pulls one icon out, like
-- taking a button off an action bar, and a set dropped touching another snaps onto its grid.
-- Dropped into a row or column it pushes the rest along.
local anchors = {}      -- [set index] = frame covering the set, what's dragged
local dragging          -- the set being dragged

-- the default icon's size with its spacing
local function Pitch()
    return OpcowsBuffReminderDB.Options.size + ICON_SPACING * 2
end

-- the group behind an icon, a buff group, an enchant group or an alert
local function KeyGroup(key)
    local kind = key:sub(1, 1)
    if kind == "1" then return OpcowsBuffReminderDB.BuffGroups[key:sub(2)] end
    if kind == "3" then return OpcowsBuffReminderDB.Alerts[key:sub(2)] end
    return OpcowsBuffReminderDB.Enchants[key:sub(2)]
end

-- an icon's size, groups can have their own
local function KeySize(key)
    local group = KeyGroup(key)
    if group and type(group.size) == "number" then return group.size end
    return OpcowsBuffReminderDB.Options.size
end

local function KeyPitch(key)
    return KeySize(key) + ICON_SPACING * 2
end

-- every icon that can show: the buff groups, the alerts and the enchant groups that aren't turned off
local function PlaceableKeys()
    local keys = {}
    for g in pairs(OpcowsBuffReminderDB.BuffGroups) do keys["1" .. g] = true end
    for aura in pairs(OpcowsBuffReminderDB.Alerts) do keys["3" .. aura] = true end
    for slot, e in pairs(OpcowsBuffReminderDB.Enchants) do
        if e.conditions.always ~= 1 then keys["2" .. slot] = true end
    end
    return keys
end

-- columns and rows a set spans
local function Size(bar)
    local w, h = 0, 0
    for _, cell in ipairs(bar.cells) do
        w, h = math.max(w, cell.c + 1), math.max(h, cell.r + 1)
    end
    return w, h
end

-- "row", "column", "single" or nil for any other shape
local function Shape(bar)
    local w, h = Size(bar)
    if w <= 1 and h <= 1 then return "single" end
    if h == 1 and #bar.cells == w then return "row" end
    if w == 1 and #bar.cells == h then return "column" end
end

-- where each column and row starts and how big it is, and the size of the whole set
local function Geometry(bar)
    local w, h = Size(bar)
    local g = { cx = {}, cw = {}, ry = {}, rh = {} }
    for _, cell in ipairs(bar.cells) do
        local p = KeyPitch(cell.key)
        g.cw[cell.c] = math.max(g.cw[cell.c] or 0, p)
        g.rh[cell.r] = math.max(g.rh[cell.r] or 0, p)
    end
    local x, y = 0, 0
    for c = 0, w - 1 do
        g.cw[c] = g.cw[c] or Pitch()
        g.cx[c], x = x, x + g.cw[c]
    end
    for r = 0, h - 1 do
        g.rh[r] = g.rh[r] or Pitch()
        g.ry[r], y = y, y + g.rh[r]
    end
    g.w, g.h = math.max(x, Pitch()), math.max(y, Pitch())
    return g
end

-- an icon's centre from the screen centre, with every icon of its set showing
local function CellCenter(bar, g, cell)
    local p = KeyPitch(cell.key)
    local cw, rh = g.cw[cell.c], g.rh[cell.r]
    return bar.left + g.cx[cell.c] + cw / 2 + (cell.ha or 0) * (cw - p) / 2,
        bar.top - g.ry[cell.r] - rh / 2 - (cell.va or 0) * (rh - p) / 2
end

local function TopLeftCell(bar)
    local best
    for _, cell in ipairs(bar.cells) do
        if not best or cell.r < best.r or (cell.r == best.r and cell.c < best.c) then best = cell end
    end
    return best
end

-- remember where one of a set's icons is, so Normalize can keep it there
local function Pin(bar, cell)
    cell = cell or TopLeftCell(bar)
    if not cell then return end
    local x, y = CellCenter(bar, Geometry(bar), cell)
    return { cell = cell, x = x, y = y }
end

-- move the top left cell back to 0, 0, keeping the pinned icon where it was
local function Normalize(bar, pin)
    if #bar.cells == 0 then return end
    local c0, r0 = math.huge, math.huge
    for _, cell in ipairs(bar.cells) do
        c0, r0 = math.min(c0, cell.c), math.min(r0, cell.r)
    end
    for _, cell in ipairs(bar.cells) do
        cell.c, cell.r = cell.c - c0, cell.r - r0
    end
    if pin then
        local x, y = CellCenter(bar, Geometry(bar), pin.cell)
        bar.left, bar.top = bar.left + pin.x - x, bar.top + pin.y - y
    end
end

local function Occupied(bar)
    local used = {}
    for _, cell in ipairs(bar.cells) do used[cell.c .. "," .. cell.r] = true end
    return used
end

-- a free cell for a new icon: the end of a row or column, else the first gap, else a new row
local function FreeCell(bar)
    local w, h = Size(bar)
    local shape = Shape(bar)
    if #bar.cells == 0 then return 0, 0 end
    if shape == "row" or shape == "single" then return w, 0 end
    if shape == "column" then return 0, h end
    local used = Occupied(bar)
    for r = 0, h - 1 do
        for c = 0, w - 1 do
            if not used[c .. "," .. r] then return c, r end
        end
    end
    return 0, h
end

-- drop gone icons and empty sets, new icons join the first set, true when anything changed
local function SyncBars()
    local opts = OpcowsBuffReminderDB.Options
    if type(opts.bars) ~= "table" or #opts.bars == 0 then
        opts.bars = { { left = 0, top = 0, cells = {} } }
    end
    local bars, keys, changed = opts.bars, PlaceableKeys(), false
    for i = #bars, 1, -1 do
        local b = bars[i]
        local gone = {}
        for j = #b.cells, 1, -1 do
            local k = b.cells[j].key
            -- also drops a key that's placed twice
            if keys[k] then
                keys[k] = nil
            else
                gone[j] = true
            end
        end
        if next(gone) then
            changed = true
            local shape = Shape(b)
            local keep
            for j, cell in ipairs(b.cells) do
                if not gone[j] and (not keep or cell.r < keep.r or (cell.r == keep.r and cell.c < keep.c)) then
                    keep = cell
                end
            end
            local pin = keep and Pin(b, keep)
            for j = #b.cells, 1, -1 do
                if gone[j] then table.remove(b.cells, j) end
            end
            -- a row or column closes up
            if shape == "row" or shape == "column" then
                table.sort(b.cells, function(p, q) return p.c + p.r < q.c + q.r end)
                for n, cell in ipairs(b.cells) do
                    if shape == "row" then cell.c = n - 1 else cell.r = n - 1 end
                end
            end
            Normalize(b, pin)
        end
        if #b.cells == 0 and #bars > 1 then table.remove(bars, i) end
    end
    local new = {}
    for k in pairs(keys) do table.insert(new, k) end
    table.sort(new)
    local first = bars[1]
    local empty = #first.cells == 0
    for _, k in ipairs(new) do
        local c, r = FreeCell(first)
        -- lined up like the nearest icon in its row and in its column
        local inRow, inCol
        for _, cell in ipairs(first.cells) do
            if cell.r == r and (not inRow or math.abs(cell.c - c) < math.abs(inRow.c - c)) then inRow = cell end
            if cell.c == c and (not inCol or math.abs(cell.r - r) < math.abs(inCol.r - r)) then inCol = cell end
        end
        table.insert(first.cells, { key = k, c = c, r = r, va = inRow and inRow.va, ha = inCol and inCol.ha })
        changed = true
    end
    -- a new set starts centred on its position, like the old single row
    if empty and #new > 0 then
        local g = Geometry(first)
        first.left, first.top = first.left - g.w / 2, first.top + g.h / 2
    end
    return changed
end

function BR.ApplyLayout()
    local opts = OpcowsBuffReminderDB.Options
    SyncBars()
    for i, bar in ipairs(opts.bars) do
        local a = anchors[i]
        if not a then
            a = CreateFrame("Frame", nil, frame)
            a:SetMovable(true)
            a:SetClampedToScreen(true)
            anchors[i] = a
        end
        -- covers every cell, what's clamped to the screen while dragging
        local g = Geometry(bar)
        a:SetSize(g.w, g.h)
        a:ClearAllPoints()
        a:SetPoint("CENTER", UIParent, "CENTER", bar.left + g.w / 2, bar.top - g.h / 2)
        a:Show()
    end
    for i = #opts.bars + 1, #anchors do anchors[i]:Hide() end
end

local function BarIndex(bar)
    for i, b in ipairs(OpcowsBuffReminderDB.Options.bars) do
        if b == bar then return i end
    end
end

-- where each showing icon of a set goes, as offsets from its anchor's centre
local function PlaceIcons(bar, showing)
    local g = Geometry(bar)
    local shape = Shape(bar)
    local out = {}
    if shape == "row" or shape == "column" then
        local list, total = {}, 0
        for _, cell in ipairs(bar.cells) do
            if showing[cell.key] then
                table.insert(list, cell)
                total = total + KeyPitch(cell.key)
            end
        end
        table.sort(list, function(p, q) return p.c + p.r < q.c + q.r end)
        local pos = -total / 2
        for _, cell in ipairs(list) do
            local p = KeyPitch(cell.key)
            local d = pos + p / 2
            pos = pos + p
            if shape == "column" then
                table.insert(out, { key = cell.key, x = (cell.ha or 0) * (g.w - p) / 2, y = -d })
            else
                table.insert(out, { key = cell.key, x = d, y = -(cell.va or 0) * (g.h - p) / 2 })
            end
        end
    else
        local ox, oy = bar.left + g.w / 2, bar.top - g.h / 2
        for _, cell in ipairs(bar.cells) do
            if showing[cell.key] then
                local x, y = CellCenter(bar, g, cell)
                table.insert(out, { key = cell.key, x = x - ox, y = y - oy })
            end
        end
    end
    return out
end

-- does set d fit on t's grid moved by oc, or columns and rows, touching it without overlapping
local function Fits(t, d, oc, or_)
    local used = Occupied(t)
    local touches = false
    for _, cell in ipairs(d.cells) do
        local c, r = cell.c + oc, cell.r + or_
        if used[c .. "," .. r] then return false end
        if used[(c - 1) .. "," .. r] or used[(c + 1) .. "," .. r]
            or used[c .. "," .. (r - 1)] or used[c .. "," .. (r + 1)] then
            touches = true
        end
    end
    return touches
end

-- ways to line up icons of different sizes, false keeps what they had
local ALIGNS = { false, { 0, 0 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

local function SetAlign(cell, ha, va)
    cell.ha = ha ~= 0 and ha or nil
    cell.va = va ~= 0 and va or nil
end

-- t with d put in: kind "grid" moves d by a columns and b rows, "row" or "column" pushes it in at
-- a. align lines up d and the icons sharing its rows and columns. t's top left icon stays still.
-- Returns the new set and d's cells in it.
local function Merge(t, d, kind, a, b, align)
    local pin = Pin(t)
    local m = { left = t.left, top = t.top, cells = {} }
    local k = #d.cells
    local ref
    for _, cell in ipairs(t.cells) do
        local n = { key = cell.key, c = cell.c, r = cell.r, ha = cell.ha, va = cell.va }
        if kind == "row" and n.c >= a then n.c = n.c + k end
        if kind == "column" and n.r >= a then n.r = n.r + k end
        if cell == pin.cell then ref = n end
        table.insert(m.cells, n)
    end
    local sorted = {}
    for _, cell in ipairs(d.cells) do table.insert(sorted, cell) end
    table.sort(sorted, function(p, q) return p.c + p.r < q.c + q.r end)
    local added, cols, rows = {}, {}, {}
    for i, cell in ipairs(sorted) do
        local n = { key = cell.key, ha = cell.ha, va = cell.va }
        if kind == "grid" then
            n.c, n.r = cell.c + a, cell.r + b
        elseif kind == "row" then
            n.c, n.r = a + i - 1, 0
        else
            n.c, n.r = 0, a + i - 1
        end
        cols[n.c], rows[n.r] = true, true
        added[cell] = n
        table.insert(m.cells, n)
    end
    if align then
        for _, n in ipairs(m.cells) do
            local mine = false
            for _, v in pairs(added) do
                if v == n then mine = true end
            end
            if mine then
                SetAlign(n, align[1], align[2])
            else
                -- only the alignment across the line d joined
                SetAlign(n, cols[n.c] and align[1] or (n.ha or 0), rows[n.r] and align[2] or (n.va or 0))
            end
        end
    end
    Normalize(m, { cell = ref, x = pin.x, y = pin.y })
    return m, added
end

-- snap a dropped set onto the set, place and alignment that puts its icons nearest where they were
-- dropped, if that's within most of an icon
local function SnapBar(d)
    local bars = OpcowsBuffReminderDB.Options.bars
    local dg = Geometry(d)
    local drop = {}
    for _, cell in ipairs(d.cells) do drop[cell] = { CellCenter(d, dg, cell) } end
    local limit = 0.75 * KeyPitch(TopLeftCell(d).key)
    local dShape = Shape(d)
    local dw, dh = Size(d)
    local best, bestDist
    local function Try(t, kind, a, b)
        for _, align in ipairs(ALIGNS) do
            local m, added = Merge(t, d, kind, a, b, align)
            local mg = Geometry(m)
            local sum = 0
            for cell, n in pairs(added) do
                local x, y = CellCenter(m, mg, n)
                sum = sum + (x - drop[cell][1]) ^ 2 + (y - drop[cell][2]) ^ 2
            end
            local dist = math.sqrt(sum / #d.cells)
            if dist < limit and (not bestDist or dist < bestDist - 0.01) then
                best, bestDist = { t = t, m = m }, dist
            end
        end
    end
    for _, t in ipairs(bars) do
        if t ~= d and #t.cells > 0 then
            local tShape = Shape(t)
            local tw, th = Size(t)
            -- pushed in like a button onto an action bar
            if (tShape == "row" or tShape == "single") and (dShape == "row" or dShape == "single") then
                for at = 0, tw do Try(t, "row", at) end
            end
            if (tShape == "column" or tShape == "single") and (dShape == "column" or dShape == "single") then
                for at = 0, th do Try(t, "column", at) end
            end
            for oc = -dw, tw do
                for or_ = -dh, th do
                    if Fits(t, d, oc, or_) then Try(t, "grid", oc, or_) end
                end
            end
        end
    end
    if not best then return false end
    local t = best.t
    t.left, t.top, t.cells = best.m.left, best.m.top, best.m.cells
    table.remove(bars, BarIndex(d))
    return true
end

function BR.IconDragStart(f)
    if BR.locked or dragging or not f.bar then return end
    local bar = f.bar
    if IsShiftKeyDown() and #bar.cells > 1 then
        local idx
        for j, cell in ipairs(bar.cells) do
            if cell.key == f.key then idx = j end
        end
        if idx then
            local cell = bar.cells[idx]
            local x, y = CellCenter(bar, Geometry(bar), cell)
            local shape = Shape(bar)
            table.remove(bar.cells, idx)
            local pin = Pin(bar)
            -- a row or column closes up behind it, other shapes keep the gap
            if shape == "row" or shape == "column" then
                local along = shape == "row" and "c" or "r"
                for _, other in ipairs(bar.cells) do
                    if other[along] > cell[along] then other[along] = other[along] - 1 end
                end
            end
            Normalize(bar, pin)
            local half = KeyPitch(f.key) / 2
            bar = { left = x - half, top = y + half, cells = { { key = f.key, c = 0, r = 0 } } }
            table.insert(OpcowsBuffReminderDB.Options.bars, bar)
            BR.ApplyLayout()
            BR.Refresh()
        end
    end
    dragging = bar
    anchors[BarIndex(bar)]:StartMoving()
end

function BR.IconDragStop()
    local bar = dragging
    if not bar then return end
    dragging = nil
    local a = anchors[BarIndex(bar)]
    a:StopMovingOrSizing()
    local ax, ay = a:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if ax and ux then
        local g = Geometry(bar)
        bar.left, bar.top = ax - ux - g.w / 2, ay - uy + g.h / 2
    end
    SnapBar(bar)
    BR.ApplyLayout()
    BR.Refresh()
end

-- a locked enchant icon with no button over it: what you last put on the hand and why it can't be
-- clicked. Locked icons only take the mouse while click to dismiss is on.
local function EnchantTooltip(f, slot)
    local last = BR.EnchantLastName(slot)
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:SetText(ENCHANT_NAMES[slot])
    if last then GameTooltip:AddLine("Last used: " .. last, 1, 1, 1) end
    local problem = BR.EnchantClickProblem(slot)
    if problem then GameTooltip:AddLine(problem, 1, 0.5, 0.25, true) end
    local opts = OpcowsBuffReminderDB.Options
    if opts.dismiss then
        GameTooltip:AddLine(BR.ClickLabel(opts.dismissbutton) .. " to dismiss it.", 1, 1, 1)
    end
    GameTooltip:Show()
end

function BR.IconTooltip(f)
    if not f.key then return end
    if BR.locked then
        if f.key:sub(1, 1) == "2" then EnchantTooltip(f, f.key:sub(2)) end
        return
    end
    local name = f.key:sub(2)
    if f.key:sub(1, 1) == "2" then
        name = ENCHANT_NAMES[name]
    elseif f.key:sub(1, 1) == "3" then
        name = "Alert: " .. (tonumber(name) and SpellName(tonumber(name)) or name)
    end
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:SetText(name)
    GameTooltip:AddLine("Drag to move it with the icons it's snapped to.", 1, 1, 1)
    GameTooltip:AddLine("Shift-drag to pull it away on its own.", 1, 1, 1)
    GameTooltip:AddLine("Drop it touching other icons, on any side, to snap to them.", 1, 1, 1)
    GameTooltip:AddLine("Next to a bigger icon, it lines up with the top, middle or bottom (or left, center "
        .. "or right) edge you drop it nearest.", 1, 1, 1, true)
    GameTooltip:Show()
end

-- put every icon back in one row, where the first set is
function BR.JoinBars()
    local bars = OpcowsBuffReminderDB.Options.bars
    local cells = {}
    for _, b in ipairs(bars) do
        table.sort(b.cells, function(p, q) return p.r < q.r or (p.r == q.r and p.c < q.c) end)
        for _, cell in ipairs(b.cells) do
            table.insert(cells, { key = cell.key, c = #cells, r = 0 })
        end
    end
    OpcowsBuffReminderDB.Options.bars = { { left = bars[1].left, top = bars[1].top, cells = cells } }
    BR.ApplyLayout()
    BR.Refresh()
end

-- the 2.0 beta saved one frame's point, turn it into its centre's offset from the screen centre
local function PointOffset(point, w, h)
    local x, y = 0, 0
    if point:find("LEFT") then x = -w / 2 elseif point:find("RIGHT") then x = w / 2 end
    if point:find("TOP") then y = h / 2 elseif point:find("BOTTOM") then y = -h / 2 end
    return x, y
end

local function OldPosition(p, size)
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string" then return 0, 0 end
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if type(uw) ~= "number" or type(uh) ~= "number" then return 0, 0 end
    local rx, ry = PointOffset(p[2], uw, uh)
    local fx, fy = PointOffset(p[1], size, size)
    return rx + (tonumber(p[3]) or 0) - fx, ry + (tonumber(p[4]) or 0) - fy
end

-- a group's glow and overlay for a missing buff or a warning, or the Options tab's for default ones
local function IconStyle(group, missing)
    local opts = OpcowsBuffReminderDB.Options
    local glowKey, overlayKey = "glow", "overlay"
    if not missing then glowKey, overlayKey = "warnglow", "warnoverlay" end
    local glow, overlay = group and group[glowKey], group and group[overlayKey]
    if not GLOWS[glow] or glow == "default" then glow = opts[glowKey] end
    if not OVERLAYS[overlay] or overlay == "default" then overlay = opts[overlayKey] end
    return glow, overlay
end

-- a group's opacity for a missing buff or a warning, or the Options tab's when it has none
local function IconAlpha(group, missing)
    local opts = OpcowsBuffReminderDB.Options
    local own = group and group[missing and "alpha" or "warnalpha"]
    if type(own) == "number" then return own end
    return missing and opts.alpha or opts.warnalpha
end

-- the game's spell alert, the glow on an action button when a spell procs. It's made for action
-- buttons, so it's only tried, returns false when this client doesn't have it or it failed.
local function SpellAlert(f, show)
    local m = ActionButtonSpellAlertManager
    if m and m.ShowAlert and m.HideAlert then
        return (pcall(show and m.ShowAlert or m.HideAlert, m, f))
    end
    local fn = show and ActionButton_ShowOverlayGlow or ActionButton_HideOverlayGlow
    if fn then return (pcall(fn, f)) end
    return false
end

-- glow kind from GLOWS, nil for none
local function SetGlow(f, kind)
    if kind == "none" then kind = nil end
    -- the spell alert sets scripts on f, which a frame inside an aura button can't have
    if kind == "alert" and f.noSpellAlert then kind = "pulse" end
    if f.glowKind == kind then return end
    if f.glowKind == "alert" then SpellAlert(f, false) end
    f.glowKind = kind
    if f.pulse then f.pulse:Stop() end
    if kind == "alert" and SpellAlert(f, true) then kind = nil end
    if not kind then
        f.glow:Hide()
        return
    end
    -- pulse, flash, steady, or a spell alert this client can't show
    f.glow:SetAlpha(1)
    f.glow:Show()
    if f.pulse and kind ~= "steady" then
        f.fade:SetDuration(kind == "flash" and 0.2 or 0.6)
        f.pulse:Play()
    end
end

local function SetOverlay(f, key)
    local color = OVERLAY_COLORS[key]
    if f.overlayKey == key then return end
    f.overlayKey = key
    if color then
        f.overlay:SetColorTexture(color[1], color[2], color[3], OVERLAY_ALPHA)
        f.overlay:Show()
    else
        f.overlay:Hide()
    end
end

-- crossed swords in the icon's corner while you're in combat, at alpha
local function ShowBadge(f, item, size, alpha)
    if not f.badge then return end
    if OpcowsBuffReminderDB.Options.combatbadge and BR.status.combat and not item.placeholder and alpha > 0 then
        local s = math.max(10, math.floor(size * 0.4 + 0.5))
        f.badge:SetSize(s, s)
        f.badge:SetAlpha(alpha)
        f.badge:Show()
    else
        f.badge:Hide()
    end
end

-- draw one icon, f is already placed
local function ShowIcon(f, item, now, shown, liveShown)
    local opts = OpcowsBuffReminderDB.Options
    local size = KeySize(item.key)
    f:SetSize(size, size)
    if f.fontSize ~= size then
        f.fontSize = size
        ScaleFont(f.text, size)
        ScaleFont(f.count, size)
        ScaleFont(f.bag, size)
        -- the border's button fills 36 of its 64 pixels
        f.glow:SetSize(size * 64 / 36, size * 64 / 36)
        -- the spell alert is sized when it's shown
        if f.glowKind == "alert" then SetGlow(f, nil) end
    end
    if item.alert then
        -- Blizzard's button is the alert's icon, ours only keeps its place
        f:SetAlpha(0)
        SetGlow(f, nil)
        SetOverlay(f, nil)
        f:EnableMouse(false)
        f:Show()
        local holder = alertFrames[item.alert].holder
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", f, "CENTER")
        holder:SetSize(size, size)
        holder:SetAlpha(item.group.alpha)
        liveShown[item.key] = true
        -- nothing tells the addon whether the alert's aura is up, so its badge is on Blizzard's
        -- button instead, see AlertBadges
        if f.badge then f.badge:Hide() end
        return
    end
    -- a Blizzard Auras icon only shows from under Blizzard's button once the buff is gone
    local missing = item.missing or item.placeholder or item.live
    local alpha = IconAlpha(item.group, missing)
    f:SetAlpha(alpha)
    -- a Blizzard Auras icon is mostly under Blizzard's button, and a placeholder only for placing
    if item.missing or not (item.placeholder or item.live) then
        local glow, overlay = IconStyle(item.group, item.missing)
        SetGlow(f, glow)
        SetOverlay(f, overlay)
    else
        SetGlow(f, nil)
        SetOverlay(f, nil)
    end
    -- an invisible icon mustn't catch clicks meant for the world under it
    f:EnableMouse(not BR.locked or (opts.dismiss and not item.placeholder and alpha > 0))
    f.texture:SetTexture(item.icon or QUESTION_MARK)
    f.texture:SetDesaturated(item.placeholder or false)
    local time, swipe = TimerStyle(item.group)
    if swipe and item.expires and item.duration and item.duration > 0 then
        f.cooldown:SetCooldown(item.expires - item.duration, item.duration)
    else
        f.cooldown:Clear()
    end
    local timeText = time and item.expires and FormatTime(item.expires - now) or ""
    local stackText = opts.icontext.stacks and item.stacks and tostring(item.stacks) or ""
    if timeText ~= "" and stackText ~= "" then
        if opts.icontext.priority == "time" then stackText = "" end
        if opts.icontext.priority == "stacks" then timeText = "" end
    end
    if f.timePos ~= opts.icontext.timepos then
        f.timePos = opts.icontext.timepos
        PlaceTime(f.text, f)
    end
    f.text:SetText(timeText)
    f.count:SetText(stackText)
    -- how many of what a weapon enchant icon puts on are left
    local mark, r, g, b
    if BR.locked and not item.placeholder and item.key:sub(1, 1) == "2" then
        mark, r, g, b = BR.EnchantMark(item.key:sub(2))
    end
    f.bag:SetText(mark or "")
    if mark then
        f.bag:SetTextColor(r, g, b)
        -- the bottom right like an action button, unless the charges are there
        f.bag:ClearAllPoints()
        if stackText ~= "" then
            f.bag:SetPoint("BOTTOMLEFT", 2, 2)
        else
            f.bag:SetPoint("BOTTOMRIGHT", -2, 2)
        end
    end
    f:Show()
    if not item.placeholder then shown[item.key] = true end
    if item.live then
        local holder = live[item.live].holder
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", f, "CENTER")
        holder:SetSize(size, size)
        holder:SetAlpha(IconAlpha(item.group, false))
        liveShown[item.key] = true
    end
    -- a Blizzard Auras badge shows over Blizzard's button or ours, whichever is showing
    ShowBadge(f, item, size, item.live and math.max(alpha, IconAlpha(item.group, false)) or alpha)
end

-- an icon on the options window showing how a missing buff or a warning will look. It sits on a
-- faint square, so the spot still shows when the opacity makes the icon itself hard to see.
function BR.NewPreview(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p:EnableMouse(true)
    p.bg =p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(1, 1, 1, 0.08)
    local f = NewIcon(p)
    f:SetAllPoints()
    f.glow:SetSize(size * 64 / 36, size * 64 / 36)
    p.icon = f
    -- a pulse stops while the window is closed, start it again when it's opened
    f:SetScript("OnShow", function(self)
        local kind = self.glowKind
        SetGlow(self, nil)
        SetGlow(self, kind)
    end)
    return p
end

function BR.StylePreview(p, group, missing, texture)
    local f = p.icon
    f:SetAlpha(IconAlpha(group, missing))
    local glow, overlay = IconStyle(group, missing)
    SetGlow(f, glow)
    SetOverlay(f, overlay)
    f.texture:SetTexture(texture or QUESTION_MARK)
end

-- draw an icon that isn't one of the placed ones, ex: a party member's, with its group's look
function BR.DrawIcon(f, group, missing, texture, size, expires, duration, now)
    f:SetSize(size, size)
    if f.fontSize ~= size then
        f.fontSize = size
        ScaleFont(f.text, size)
        ScaleFont(f.count, size)
        f.glow:SetSize(size * 64 / 36, size * 64 / 36)
        if f.glowKind == "alert" then SetGlow(f, nil) end
    end
    f:SetAlpha(IconAlpha(group, missing))
    local glow, overlay = IconStyle(group, missing)
    SetGlow(f, glow)
    SetOverlay(f, overlay)
    f.texture:SetTexture(texture or QUESTION_MARK)
    local time, swipe = TimerStyle(group)
    if swipe and expires and duration and duration > 0 then
        f.cooldown:SetCooldown(expires - duration, duration)
    else
        f.cooldown:Clear()
    end
    f.text:SetText(time and expires and FormatTime(expires - now) or "")
    f.count:SetText("")
    f:Show()
end

-- alerts -----------------------------------------------------------------------------------
-- An alert shows an icon while an aura is on you, ex: Clearcasting. It's Blizzard Auras turned
-- round: Blizzard's button is the icon, shown by the game while the aura is up, in combat too,
-- and nothing is drawn while it's gone. The glow and colour are on a frame of ours over the
-- button, so they show and hide with it, and the sound is the game's own, played as the aura is
-- put on. Like the Blizzard Auras buttons they're made and styled only out of combat.
-- OpcowsBuffReminderDB.Alerts is keyed by the aura, a name (every rank) or a spell id.
local ALERT_SLOT = "aura"
local alertSounds = {}  -- [alert] = { key, ids = the game's sound registrations }

-- the spell ids an alert follows, as a set and as a key: the ones SpellIds finds, the ones seen on
-- it and the one the Seen list has for its name
local function AlertIds(aura, alert)
    local ids, list = {}, {}
    local function add(id)
        if id and not ids[id] then
            ids[id] = true
            table.insert(list, id)
        end
    end
    for _, id in ipairs(SpellIds(aura)) do add(id) end
    if not tonumber(aura) then
        for id in pairs(alert.ids) do add(id) end
        local seen = OpcowsBuffReminderDB.Seen[aura:lower()]
        add(seen and Num(seen.id))
    end
    table.sort(list)
    return ids, table.concat(list, ",")
end

-- whether the game can play a sound as an aura is put on
local function AuraSounds()
    return C_UnitAuras ~= nil and C_UnitAuras.AddAuraSound ~= nil and C_UnitAuras.RemoveAuraSound ~= nil
        and Enum ~= nil and Enum.UnitAuraSoundTrigger ~= nil and Enum.UnitAuraSoundTrigger.Added ~= nil
end

-- register the alert's sound with the game for each of its spell ids, again when either changed.
-- No alert or no sound takes it off.
local function SetAlertSound(aura, alert, ids, idKey)
    local s = alertSounds[aura] or { ids = {} }
    alertSounds[aura] = s
    local key = alert and alert.sound and (tostring(alert.sound) .. ":" .. idKey) or ""
    if key == s.key then return end
    for _, id in ipairs(s.ids) do pcall(C_UnitAuras.RemoveAuraSound, id) end
    s.ids, s.key = {}, key
    if key == "" or not AuraSounds() then return end
    local sound = alert.sound
    for id in pairs(ids) do
        local ok, reg = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, {
            unitToken = "player",
            spellID = id,
            soundFileName = type(sound) == "string" and sound or nil,
            soundFileID = type(sound) == "number" and sound or nil,
            outputChannel = "Master",
        })
        if ok and reg then table.insert(s.ids, reg) end
    end
    Debug(("alert %s: sound on %d of its spell ids"):format(aura, #s.ids))
end

-- called by Blizzard once, when it makes the slot's button: the live button and our glow frame,
-- over the swipe and under the texts. The game won't let scripts be set on frames in the button,
-- so there's no OnShow to start a pulse again, KeepPulses does it.
local function InitAlertButton(a, button)
    InitLiveButton(a, button)
    -- the aura is what's wanted, so it darkens as it runs out instead of lighting up
    pcall(a.cd.SetReverse, a.cd, true)
    local fx = NewIcon(button)
    fx:SetAllPoints()
    fx:SetFrameLevel(a.cd:GetFrameLevel() + 1)
    fx.texture:Hide()
    fx.cooldown:Hide()
    fx.noSpellAlert = true
    -- the combat badge, on Blizzard's button so it shows only while the aura is up
    fx.badge = fx:CreateTexture(nil, "OVERLAY", nil, 7)
    fx.badge:SetPoint("BOTTOMLEFT", 1, 1)
    fx.badge:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    fx.badge:SetTexCoord(0.5, 1, 0, 0.484375)
    fx.badge:Hide()
    a.fx = fx
end

-- show or hide the alerts' combat badges, in combat too like KeepPulses
local function AlertBadges()
    local opts = OpcowsBuffReminderDB.Options
    local on = opts.combatbadge and BR.status.combat and BR.locked
    for aura, a in pairs(alertFrames) do
        local alert = OpcowsBuffReminderDB.Alerts[aura]
        local badge = a.fx and a.fx.badge
        if badge and alert and not a.badgeErr and (on and true or false) ~= (a.badgeOn or false) then
            local size = type(alert.size) == "number" and alert.size or opts.size
            local s = math.max(10, math.floor(size * 0.4 + 0.5))
            local ok, err = pcall(function()
                badge:SetSize(s, s)
                badge:SetShown(on)
            end)
            if ok then
                a.badgeOn = on and true or false
            else
                a.badgeErr = true
                Debug("alert combat badge can't be changed: " .. tostring(err))
            end
        end
    end
end

-- hiding stops a pulse, and the button hides each time the aura goes, so play it again while it's
-- stopped. In combat too, it's our own frame; a failure is remembered so it isn't tried again.
local function KeepPulses()
    for _, a in pairs(alertFrames) do
        local fx = a.fx
        local kind = fx and fx.glowKind
        if kind and kind ~= "steady" and kind ~= "alert" and fx.pulse and not a.pulseErr then
            local ok, playing = pcall(fx.pulse.IsPlaying, fx.pulse)
            if not ok then
                a.pulseErr = true
                Debug("alert glow can't be read: " .. tostring(playing))
            elseif not playing then
                local played, err = pcall(fx.pulse.Play, fx.pulse)
                if not played then
                    a.pulseErr = true
                    Debug("alert glow can't be started: " .. tostring(err))
                end
            end
        end
    end
end

-- make, refilter and restyle the alerts' containers and sounds, out of combat only
function BR.UpdateAlerts()
    KeepPulses()
    AlertBadges()
    if InCombatLockdown() or AurasSecret() then return end
    local alerts = OpcowsBuffReminderDB.Alerts
    for aura in pairs(alertSounds) do
        if not alerts[aura] then SetAlertSound(aura, nil) end
    end
    for aura, alert in pairs(alerts) do
        local ids, key = AlertIds(aura, alert)
        SetAlertSound(aura, alert, ids, key)
        local a = alertFrames[aura]
        if not (a and a.err) and key ~= "" then
            if not a then
                a = {}
                alertFrames[aura] = a
                if MakeContainer(a, ALERT_SLOT, ids, InitAlertButton) then a.ids = key end
            elseif a.container and key ~= a.ids then
                if pcall(a.container.SetAuraSlotCandidateFilters, a.container, ALERT_SLOT, { includeSpellIDs = ids }) then
                    a.ids = key
                end
            end
            if a.button and a.fx then
                StyleLive(a, alert, 0, alert.glow .. ":" .. alert.overlay, function(size)
                    a.fx.glow:SetSize(size * 64 / 36, size * 64 / 36)
                    SetGlow(a.fx, nil)
                    SetGlow(a.fx, alert.glow)
                    SetOverlay(a.fx, alert.overlay)
                end)
            end
        end
    end
end

local function AlertReady(aura)
    local a = alertFrames[aura]
    return a ~= nil and a.container ~= nil and not a.err
end

-- how an alert works, and whether that's worth a warning
function BR.AlertStatus(aura)
    local alert = OpcowsBuffReminderDB.Alerts[aura]
    local a = alertFrames[aura]
    if a and a.err then return "Blizzard's aura buttons don't work on this client, so alerts can't show.", true end
    local _, key = AlertIds(aura, alert)
    if key == "" then
        return "Spell id not known yet. Have the aura once out of combat, or add it by spell id.", true
    end
    local text = "Shows while it's on you, in combat too (spell " .. key:gsub(",", ", ") .. ")."
    if not AlertReady(aura) then text = "Set up once you're out of combat." end
    if alert.sound and not AuraSounds() then
        return text .. " This client can't play a sound for it.", true
    end
    return text, false
end

-- click to cast ----------------------------------------------------------------------------
-- Clicking a buff group's icon casts the group's spell on you. Casting takes one of Blizzard's
-- secure buttons, which can't be made, moved, shown or hidden in combat, while the icons change
-- all fight. So the icons stay plain frames and an invisible secure button is laid over each one
-- out of combat. They're all hidden as combat starts, so a button left behind can't cast the
-- spell of an icon that moved, and put back when it ends.
local clickers = {}     -- pooled secure buttons

-- The click that casts is set on the Options tab by clicking with it, and saved the way the secure
-- template names it: the modifiers held, in the template's alt-ctrl-shift- order, and the mouse
-- button's number, ex: "shift-2" for Shift-right click. The type attribute for it is then
-- "shift-type2", which the template only uses with exactly those keys held.
local CLICK_BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
local CLICK_NAMES = { "Left click", "Right click", "Middle click", "Button 4", "Button 5" }
local CLICK_MODS = {}
for _, a in ipairs({ "", "alt-" }) do
    for _, c in ipairs({ "", "ctrl-" }) do
        for _, s in ipairs({ "", "shift-" }) do CLICK_MODS[a .. c .. s] = true end
    end
end

-- modifiers and button number of a saved click, nil for one that isn't valid
local function ParseClick(click)
    local mods, n = (type(click) == "string" and click or ""):match("^([%a%-]*)(%d)$")
    n = tonumber(n)
    if mods and CLICK_MODS[mods] and CLICK_BUTTONS[n] then return mods, n end
end

-- the click being made now, with button the name OnClick gets, nil for a button that can't be used
function BR.ClickFrom(button)
    local n
    for i, name in ipairs(CLICK_BUTTONS) do
        if name == button then n = i end
    end
    if not n then return nil end
    return (IsAltKeyDown() and "alt-" or "") .. (IsControlKeyDown() and "ctrl-" or "")
        .. (IsShiftKeyDown() and "shift-" or "") .. n
end

-- ex: "Shift-Right click"
function BR.ClickLabel(click)
    local mods, n = ParseClick(click)
    if not mods then return "?" end
    local keys = mods:gsub("(%a+)%-", function(m) return m:sub(1, 1):upper() .. m:sub(2) .. "-" end)
    return keys .. CLICK_NAMES[n]
end

-- your own spells among a group's buffs, one name each, sorted
function BR.ClickSpells(group)
    local list, seen = {}, {}
    if not (C_Spell and C_Spell.GetSpellName) then return list end
    for buff in pairs(group.buffs) do
        local id = OwnSpellId(buff)
        local ok, name = false, nil
        if id then ok, name = pcall(C_Spell.GetSpellName, id) end
        if ok and type(name) == "string" and not issecretvalue(name) and not seen[name] then
            seen[name] = true
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

-- the spell a click on the group's icon casts, nil for none. group.click is "auto" for the first
-- of your spells, "off", or a spell's name. A name that's no longer yours counts as auto. The
-- Options tab turns it off for every group.
function BR.ClickSpell(group)
    if not OpcowsBuffReminderDB.Options.clicktocast or group.click == "off" then return nil end
    local list = BR.ClickSpells(group)
    for _, name in ipairs(list) do
        if name == group.click then return name end
    end
    return list[1]
end

local function AcquireClicker(i)
    local b = clickers[i]
    if not b then
        b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        b:SetFrameStrata("LOW")
        -- over the icons and the Blizzard Auras buttons
        b:SetFrameLevel(frame:GetFrameLevel() + 20)
        b:SetAttribute("unit", "player")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.spell)
            if self.hand then
                GameTooltip:AddLine(BR.ClickLabel(self.click) .. " to put it on your "
                    .. (self.hand == "main" and "main hand" or "off hand") .. ".", 1, 1, 1)
            else
                GameTooltip:AddLine(BR.ClickLabel(self.click) .. " to cast it on " .. (self.who or "yourself") .. ".",
                    1, 1, 1)
            end
            local opts = OpcowsBuffReminderDB.Options
            if opts.dismiss then
                GameTooltip:AddLine(BR.ClickLabel(opts.dismissbutton) .. " to dismiss it.", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("PostClick", function(self, button, down)
            if BR.ClickFrom(button) == self.click then Debug(("clicked, casting %s"):format(self.spell)) end
            -- the button covers the icon, so its other clicks, like dismissing, go on to it
            if not down and self.icon then
                local h = self.icon:GetScript("OnMouseUp")
                if h then h(self.icon, button) end
            end
        end)
        clickers[i] = b
    end
    return b
end

-- lay the secure buttons over the icons that can be clicked, list = { { f, spell, unit, who }, ... },
-- unit and who for a party member's icon
local function UpdateClickers(list)
    -- combat is set as it starts, before the lockdown
    if InCombatLockdown() or BR.status.combat then return end
    local left, bottom = UIParent:GetLeft() or 0, UIParent:GetBottom() or 0
    local opts = OpcowsBuffReminderDB.Options
    local click = opts.clickbutton
    local mods, button = ParseClick(click)
    -- the dismiss click's mouse button, which the button takes too to pass it on
    local _, dismiss = ParseClick(opts.dismiss and opts.dismissbutton)
    local n = 0
    for _, c in ipairs(list) do
        local x, y = c.f:GetCenter()
        if x and y and mods then
            n = n + 1
            local b = AcquireClicker(n)
            if b.click ~= click or b.dismiss ~= dismiss then
                if b.attr then b:SetAttribute(b.attr, nil) end
                b.attr = mods .. "type" .. button
                -- the template casts on the press or the release, whichever the game is set to
                local name = CLICK_BUTTONS[button]
                local clicks = { name .. "Up", name .. "Down" }
                if dismiss and dismiss ~= button then table.insert(clicks, CLICK_BUTTONS[dismiss] .. "Up") end
                b:RegisterForClicks(unpack(clicks))
                b.click, b.dismiss = click, dismiss
            end
            b:ClearAllPoints()
            b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x - left, y - bottom)
            b:SetSize(c.f:GetWidth(), c.f:GetHeight())
            -- a spell, or for a weapon enchant maybe an item, then the hand it goes on
            b:SetAttribute(b.attr, c.item and "item" or "spell")
            b:SetAttribute("spell", c.spell)
            b:SetAttribute("item", c.item)
            b:SetAttribute("target-slot", c.slot)
            b:SetAttribute("unit", c.unit or "player")
            b.spell, b.who, b.hand, b.icon = c.label or c.spell, c.who, c.hand, c.f
            b:Show()
        end
    end
    for i = n + 1, #clickers do clickers[i]:Hide() end
end

-- as combat starts, the last moment they can be hidden
function BR.HideClickers()
    if InCombatLockdown() then return end
    for _, b in ipairs(clickers) do b:Hide() end
end

-- click to dismiss -------------------------------------------------------------------------
-- Another click, a right click to begin with, hides an icon until its buff is put on again. It
-- needs no secure button, so it works in combat too. Not saved.
local dismissed = {}    -- [icon key] = the buff's expiry when it was dismissed, false when it was gone

-- whether the click being made, with button the name OnClick gets, is the one that dismisses
function BR.IsDismissClick(button)
    local opts = OpcowsBuffReminderDB.Options
    return opts.dismiss and BR.ClickFrom(button) == opts.dismissbutton
end

-- the state a buff group or weapon enchant icon shows, { present, expires }
local function KeyState(key)
    if key:sub(1, 1) == "1" then return BR.groupState[key:sub(2)] end
    if key:sub(1, 1) == "2" then return BR.enchants[key:sub(2)] end
end

function BR.DismissIcon(key)
    local st = KeyState(key)
    dismissed[key] = st and st.present and st.expires or false
    Debug(("dismissed %s"):format(key:sub(2)))
    BR.Refresh()
end

-- true while a dismissed icon stays hidden: until the buff is up with a different expiry than
-- when it was dismissed, a second either way for a prediction corrected by a read
local function IsDismissed(key)
    local d = dismissed[key]
    if d == nil then return false end
    local st = KeyState(key)
    if st and st.present and (d == false or math.abs((st.expires or 0) - d) > 1) then
        dismissed[key] = nil
        return false
    end
    return true
end

-- work out which icons should be visible, using predicted expiry while auras are secret
function BR.Refresh()
    local opts = OpcowsBuffReminderDB.Options
    local now = GetTime()
    local list = {}

    if not BR.hideAll then
        local secret = AurasSecret()
        for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
            local st = BR.groupState[g]
            -- when the buff was cast, for predicting its spell's cooldown
            if st and st.present and (st.duration or 0) > 0 and st.expires > 0 then
                BR.castAt[g] = st.expires - st.duration
            end
            -- checked even while the group is hidden, ex: shown only in combat, so a cooldown
            -- read before the pull is known during it
            local cooling = GroupCooling(group, BR.castAt[g], now)
            if IsSuppressed(group.conditions) or BR.scriptRes[g] then
                -- hidden
            elseif secret and group.combat == "blizzard" and LiveReady(g) then
                -- Blizzard's button covers the icon while the buff is up
                table.insert(list, { key = "1" .. g, icon = group.icon, live = g, group = group })
            elseif st and cooling then
                -- can't be cast again yet
            elseif st then
                -- no state means auras haven't been readable yet, don't guess
                if not st.present or (st.expires > 0 and st.expires <= now) then
                    table.insert(list, { key = "1" .. g, icon = group.icon, group = group, missing = true })
                else
                    local expiring = st.expires > 0 and st.expires - now <= group.warntime
                    local stacks = st.applications
                    local low = group.warnstacks > 0 and stacks and stacks > 0 and stacks <= group.warnstacks
                    if expiring or low then
                        table.insert(list, { key = "1" .. g, icon = group.icon, group = group,
                            expires = expiring and st.expires or nil, duration = st.duration,
                            stacks = low and stacks or nil })
                    end
                end
            end
        end

        for slot, invSlot in pairs(ENCHANT_SLOTS) do
            local eg = OpcowsBuffReminderDB.Enchants[slot]
            local e = BR.enchants[slot]
            local tex = GetInventoryItemTexture("player", invSlot)
            if IsSuppressed(eg.conditions) or BR.enchantScriptRes[slot] or not e or not tex then
                -- hidden, or no weapon in the hand
            elseif not e.present or e.expires <= now then
                table.insert(list, { key = "2" .. slot, icon = tex, group = eg, missing = true })
            else
                local expiring = e.expires - now <= eg.warntime
                local low = eg.warnstacks > 0 and e.charges > 0 and e.charges <= eg.warnstacks
                if expiring or low then
                    table.insert(list, { key = "2" .. slot, icon = tex, group = eg,
                        expires = expiring and e.expires or nil, stacks = low and e.charges or nil })
                end
            end
        end

        -- an alert holds its place whether or not its aura is up, nothing tells the addon in combat.
        -- Unlocked it's a placeholder like the others.
        for aura, alert in pairs(OpcowsBuffReminderDB.Alerts) do
            if BR.locked and AlertReady(aura) and not IsSuppressed(alert.conditions)
                and not BR.alertScriptRes[aura] then
                table.insert(list, { key = "3" .. aura, icon = alert.icon, alert = aura, group = alert })
            end
        end
    end

    -- every dismissed icon, shown or not, so a recast is seen while the buff is up and not showing
    local hidden = {}
    for key in pairs(dismissed) do hidden[key] = IsDismissed(key) end
    local byKey = {}
    for _, item in ipairs(list) do
        if not hidden[item.key] then byKey[item.key] = item end
    end
    if not BR.locked and not BR.hideAll then
        -- unlocked, the icons that aren't needed show grey so they can be placed too
        for k in pairs(PlaceableKeys()) do
            if not byKey[k] then
                local icon
                if k:sub(1, 1) == "1" then
                    icon = OpcowsBuffReminderDB.BuffGroups[k:sub(2)].icon
                elseif k:sub(1, 1) == "3" then
                    icon = OpcowsBuffReminderDB.Alerts[k:sub(2)].icon
                else
                    icon = GetInventoryItemTexture("player", ENCHANT_SLOTS[k:sub(2)])
                end
                byKey[k] = { key = k, icon = icon, placeholder = true }
            end
        end
    end
    if SyncBars() then BR.ApplyLayout() end
    -- a drag whose icon went away never gets its OnDragStop
    if dragging and not IsMouseButtonDown("LeftButton") then BR.IconDragStop() end

    local shown, liveShown, newIcon, clicks = {}, {}, false, {}
    local i = 0
    for bi, bar in ipairs(opts.bars) do
        for _, p in ipairs(PlaceIcons(bar, byKey)) do
            local item = byKey[p.key]
            i = i + 1
            local f = AcquireIcon(i)
            f.key, f.bar = item.key, bar
            f:ClearAllPoints()
            f:SetPoint("CENTER", anchors[bi], "CENTER", p.x, p.y)
            ShowIcon(f, item, now, shown, liveShown)
            -- unlocked icons are for dragging
            if BR.locked and not item.placeholder and not item.live and not item.alert and f:GetAlpha() > 0 then
                if item.key:sub(1, 1) == "1" then
                    local spell = BR.ClickSpell(item.group)
                    if spell then table.insert(clicks, { f = f, spell = spell }) end
                else
                    -- what you last put on the hand, used on it
                    local hand = item.key:sub(2)
                    local a = BR.EnchantAction(hand)
                    if a then
                        table.insert(clicks, { f = f, spell = a.spell, item = a.item, label = a.label,
                            slot = ENCHANT_SLOTS[hand], hand = hand })
                    end
                end
            end
            if not item.live and not item.alert and not item.placeholder and not BR.shown[item.key] then
                -- a Blizzard Auras icon shows all fight, no sound for that, and an alert has its own
                newIcon = true
            end
        end
    end
    for k = i + 1, #BR.icons do
        BR.icons[k]:Hide()
    end
    for g, l in pairs(live) do
        if not liveShown["1" .. g] then l.holder:SetAlpha(0) end
    end
    for aura, a in pairs(alertFrames) do
        if not liveShown["3" .. aura] then a.holder:SetAlpha(0) end
    end
    -- the party panel adds its icons' clicks, true when one is new
    if BR.RefreshParty and BR.RefreshParty(clicks, now) then newIcon = true end
    UpdateClickers(clicks)
    BR.shown = shown

    if newIcon and opts.warnsound then
        PlaySound(opts.warnsound, "Master")
    end
end

function BR.Update()
    BR.ScanAuras()
    BR.Refresh()
end

function BR.SetLocked(locked)
    BR.locked = locked
    if locked then BR.IconDragStop() end
    if OpcowsBuffReminderDB then BR.Refresh() end
end

-- changes made in the options window ------------------------------------------------------
function BR.NewGroup(g)
    local opts = OpcowsBuffReminderDB.Options
    OpcowsBuffReminderDB.BuffGroups[g] = {
        ["conditions"] = DeepCopy(opts.conditions),
        ["warntime"] = opts.warntime,
        ["warnstacks"] = 0,
        ["combat"] = "cdm",
        ["hituse"] = "auto",
        ["hitcd"] = 0,
        ["timer"] = "default",
        ["glow"] = "default",
        ["overlay"] = "default",
        ["warnglow"] = "default",
        ["warnoverlay"] = "default",
        ["click"] = "auto",
        ["party"] = true,
        ["icon"] = QUESTION_MARK,
        ["script"] = opts.script,
        ["buffs"] = {},
    }
    BR.SetGroupScript(g, opts.script)
end

function BR.AddBuffToGroup(g, buff)
    if OpcowsBuffReminderDB.BuffGroups[g] == nil then BR.NewGroup(g) end
    local group = OpcowsBuffReminderDB.BuffGroups[g]
    if buff ~= nil then
        group.buffs[buff] = true
        if group.icon == QUESTION_MARK then
            group.icon = SpellTexture(buff) or QUESTION_MARK
        end
    end
end

function BR.RemoveGroup(g)
    OpcowsBuffReminderDB.BuffGroups[g] = nil
    BR.groupState[g] = nil
    BR.scripts[g] = nil
    BR.scriptRes[g] = nil
end

function BR.SetGroupScript(g, code)
    OpcowsBuffReminderDB.BuffGroups[g].script = code
    BR.scripts[g] = Compile(code, g)
    BR.scriptRes[g] = false
end

function BR.SetDefaultScript(code)
    if code ~= "" then Compile(code, "default") end
    OpcowsBuffReminderDB.Options.script = code
end

function BR.SetEnchantScript(slot, code)
    OpcowsBuffReminderDB.Enchants[slot].script = code
    BR.enchantScripts[slot] = Compile(code, ENCHANT_NAMES[slot])
    BR.enchantScriptRes[slot] = false
end

-- an alert for an aura, a name or a spell id, nothing if there's one for it already
function BR.NewAlert(aura)
    local alerts = OpcowsBuffReminderDB.Alerts
    if alerts[aura] then return end
    alerts[aura] = {
        ["conditions"] = DeepCopy(OpcowsBuffReminderDB.Options.conditions),
        ["timer"] = "default",
        ["glow"] = "none",
        ["overlay"] = "none",
        ["alpha"] = 1,
        ["icon"] = SpellTexture(aura) or QUESTION_MARK,
        ["ids"] = {},
        ["script"] = "",
    }
    local seen = not tonumber(aura) and OpcowsBuffReminderDB.Seen[aura:lower()]
    if seen and seen.icon then alerts[aura].icon = seen.icon end
    BR.alertScripts[aura] = nil
    BR.alertScriptRes[aura] = false
    BR.UpdateAlerts()
end

function BR.RemoveAlert(aura)
    OpcowsBuffReminderDB.Alerts[aura] = nil
    BR.alertScripts[aura] = nil
    BR.alertScriptRes[aura] = nil
    BR.UpdateAlerts()
end

function BR.SetAlertScript(aura, code)
    OpcowsBuffReminderDB.Alerts[aura].script = code
    BR.alertScripts[aura] = Compile(code, aura)
    BR.alertScriptRes[aura] = false
end

-- an alert's sound: a name from ALERT_SOUNDS, a sound file id or path, or nil / "none" for none.
-- Returns false for a name that isn't known.
function BR.SetAlertSoundChoice(aura, v)
    local alert = OpcowsBuffReminderDB.Alerts[aura]
    if v == nil or v == "" or tostring(v):lower() == "none" then
        alert.sound = nil
    elseif tonumber(v) then
        alert.sound = tonumber(v)
    elseif tostring(v):find("[\\/]") then
        alert.sound = v
    else
        local found
        for _, s in ipairs(ALERT_SOUNDS) do
            if s[1]:lower() == tostring(v):lower() then found = s[2] end
        end
        if not found then return false end
        alert.sound = found
    end
    if alert.sound then pcall(PlaySoundFile, alert.sound, "Master") end
    BR.UpdateAlerts()
    return true
end

-- the name of an alert sound, or its file id or path
function BR.AlertSoundName(sound)
    for _, s in ipairs(ALERT_SOUNDS) do
        if s[2] == sound then return s[1] end
    end
    return sound and tostring(sound)
end

-- an enchant group, turned off until it's wanted
local function NewEnchant()
    local opts = OpcowsBuffReminderDB.Options
    local conds = DeepCopy(opts.conditions)
    conds.always = 1
    return {
        ["conditions"] = conds,
        ["warntime"] = opts.warntime,
        ["warnstacks"] = 5,
        ["timer"] = "default",
        ["glow"] = "default",
        ["overlay"] = "default",
        ["warnglow"] = "default",
        ["warnoverlay"] = "default",
        ["script"] = "",
    }
end

-- nil or "none" turns the sound off, returns false for an unknown sound
function BR.SetSound(v)
    if v == nil or v == "" or tostring(v):lower() == "none" then
        OpcowsBuffReminderDB.Options.warnsound = nil
        return true
    end
    local id = ResolveSound(v)
    if not id then return false end
    OpcowsBuffReminderDB.Options.warnsound = id
    PlaySound(id, "Master")
    return true
end

function BR.ToggleHidden()
    BR.hideAll = not BR.hideAll
    Print(BR.hideAll and "Icons will not be shown." or "Icons will be shown.")
    BR.Refresh()
end

function BR.Reset()
    OpcowsBuffReminderDB.BuffGroups = {}
    OpcowsBuffReminderDB.Options = DeepCopy(BR.DefaultOptions)
    OpcowsBuffReminderDB.Enchants = { main = NewEnchant(), off = NewEnchant() }
    OpcowsBuffReminderDB.Alerts = {}
    BR.groupState = {}
    BR.scriptRes = {}
    BR.alertScriptRes = {}
    BR.CompileScripts()
    BR.ApplyLayout()
    BR.PlaceParty()
    BR.UpdateMinimap()
    BR.UpdateAlerts()
    BR.RememberCharacter()
end

-- other characters -----------------------------------------------------------------------
-- OpcowsBuffReminderAccount is saved for the whole account. Each character keeps its settings there, so
-- another character can copy them. The tables are this character's own, saved with it at logout.
local function CharacterKey()
    return ("%s - %s"):format(UnitName("player") or "?", GetRealmName() or "?")
end

function BR.RememberCharacter()
    local _, class = UnitClass("player")
    OpcowsBuffReminderAccount.chars[CharacterKey()] = {
        class = class,
        time = time(),
        BuffGroups = OpcowsBuffReminderDB.BuffGroups,
        Options = OpcowsBuffReminderDB.Options,
        Enchants = OpcowsBuffReminderDB.Enchants,
        Alerts = OpcowsBuffReminderDB.Alerts,
    }
end

-- the other characters, { key, class, groups }, newest first
function BR.GetCharacters()
    local list, me = {}, CharacterKey()
    for key, c in pairs(OpcowsBuffReminderAccount.chars) do
        if key ~= me then
            local n = 0
            for _ in pairs(c.BuffGroups) do n = n + 1 end
            table.insert(list, { key = key, class = c.class, groups = n, time = c.time })
        end
    end
    table.sort(list, function(a, b) return a.time > b.time end)
    return list
end

function BR.ForgetCharacter(key)
    OpcowsBuffReminderAccount.chars[key] = nil
end

-- replace this character's groups, enchants and options with a copy of c's
local function LoadSettings(c)
    OpcowsBuffReminderDB.BuffGroups = DeepCopy(c.BuffGroups)
    OpcowsBuffReminderDB.Options = DeepCopy(c.Options)
    OpcowsBuffReminderDB.Enchants = DeepCopy(c.Enchants)
    -- saves from before 2.6 have no alerts
    OpcowsBuffReminderDB.Alerts = DeepCopy(type(c.Alerts) == "table" and c.Alerts or {})
    BR.SanityCheck()
    BR.groupState = {}
    BR.scriptRes = {}
    BR.alertScriptRes = {}
    BR.castAt = {}
    BR.CompileScripts()
    BR.ApplyLayout()
    BR.PlaceParty()
    BR.UpdateMinimap()
    BR.UpdateLive()
    BR.UpdateAlerts()
    BR.RememberCharacter()
end

-- replace this character's settings with a copy of another's
function BR.CopyCharacter(key)
    local c = OpcowsBuffReminderAccount.chars[key]
    if not c then return false end
    LoadSettings(c)
    return true
end

-- named saves, account wide: a copy of the settings as they were when saved, for any character to load
function BR.SaveSettings(name)
    local _, class = UnitClass("player")
    OpcowsBuffReminderAccount.saves[name] = {
        class = class,
        by = CharacterKey(),
        time = time(),
        BuffGroups = DeepCopy(OpcowsBuffReminderDB.BuffGroups),
        Options = DeepCopy(OpcowsBuffReminderDB.Options),
        Enchants = DeepCopy(OpcowsBuffReminderDB.Enchants),
        Alerts = DeepCopy(OpcowsBuffReminderDB.Alerts),
    }
end

-- the saves, { name, class, by, groups, time }, by name
function BR.GetSaves()
    local list = {}
    for name, s in pairs(OpcowsBuffReminderAccount.saves) do
        local n = 0
        for _ in pairs(s.BuffGroups) do n = n + 1 end
        table.insert(list, { name = name, class = s.class, by = s.by, groups = n, time = s.time })
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

function BR.HasSave(name)
    return OpcowsBuffReminderAccount.saves[name] ~= nil
end

function BR.DeleteSave(name)
    OpcowsBuffReminderAccount.saves[name] = nil
end

function BR.LoadSave(name)
    local s = OpcowsBuffReminderAccount.saves[name]
    if not s then return false end
    LoadSettings(s)
    return true
end

-- current buffs for the config UI, nil while they can't be read
function BR.GetCurrentBuffs()
    if AurasSecret() then return nil end
    local ok, _, list = pcall(ReadPlayerBuffs)
    return ok and list or nil
end

-- buffs seen before, like GetCurrentBuffs' entries
function BR.GetSeenBuffs()
    local list = {}
    for _, e in pairs(OpcowsBuffReminderDB.Seen) do
        table.insert(list, { name = e.name, spellId = e.id, icon = e.icon })
    end
    return list
end

-- whether a spell reads like a buff: it lasts a while, or it's an aura or aspect kept up.
-- The game has no flag for this, so it goes by the tooltip text.
local function LooksLikeBuff(id, name)
    if C_Spell.IsSpellHarmful then
        local ok, harmful = pcall(C_Spell.IsSpellHarmful, id)
        if ok and harmful == true then return false end
    end
    local desc = ""
    if C_Spell.GetSpellDescription then
        local ok, d = pcall(C_Spell.GetSpellDescription, id)
        if ok and type(d) == "string" and not issecretvalue(d) then desc = d:lower() end
    end
    -- the text isn't there until the game has loaded the spell, ask for it and list it again then
    if desc == "" and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, id)
    end
    -- minutes and hours are buffs, seconds only when it's for that long: "every 3 sec" is a heal
    if desc:find("%d *min") or desc:find("%d *hour") or desc:find("%d *hr")
        or desc:find("for %d[%d%.]* *sec") or desc:find("lasts %d") then
        return true
    end
    name = name:lower()
    return name:find(" aura$") ~= nil or name:find("^aspect of") ~= nil
end

-- the player's spells that look like buffs, or every active spell, one entry per name with
-- the highest rank's id
function BR.GetSpellbookBuffs(all)
    local byName, list = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return list end
    pcall(function()
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    local id, n = item and Num(item.spellID), item and item.name
                    if id and type(n) == "string" and not issecretvalue(n) and not item.isPassive
                        and (spellType == nil or item.itemType == spellType) then
                        local e = byName[n]
                        if e then
                            if id > e.spellId then e.spellId = id end
                        elseif all or LooksLikeBuff(id, n) then
                            byName[n] = { name = n, spellId = id, icon = item.iconID }
                            table.insert(list, byName[n])
                        end
                    end
                end
            end
        end
    end)
    return list
end

-- sound kit names, and the name of a sound kit id
function BR.SoundNames()
    local names = {}
    for name, id in pairs(SOUNDKIT or {}) do
        if type(id) == "number" then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

function BR.SoundName(id)
    for name, v in pairs(SOUNDKIT or {}) do
        if v == id then return name end
    end
end

-- shared with Config.lua
BR.QUESTION_MARK = QUESTION_MARK
BR.MEDIA = MEDIA
BR.CONDITIONS = CONDITIONS
BR.COMBAT_MODES = COMBAT_MODES
BR.HIT_USES, BR.HIT_USE_ORDER = HIT_USES, HIT_USE_ORDER
BR.TIMERS, BR.TIMER_ORDER = TIMERS, TIMER_ORDER
BR.TIME_POSITIONS, BR.TIME_POSITION_ORDER = TIME_POSITIONS, TIME_POSITION_ORDER
BR.GLOWS, BR.GLOW_ORDER, BR.OVERLAYS, BR.OVERLAY_ORDER = GLOWS, GLOW_ORDER, OVERLAYS, OVERLAY_ORDER
BR.ENCHANT_SLOTS, BR.ENCHANT_NAMES = ENCHANT_SLOTS, ENCHANT_NAMES
BR.ALERT_SOUNDS = ALERT_SOUNDS
BR.Print = Print
BR.SpellTexture = SpellTexture
-- and Party.lua
BR.Debug, BR.BuffKey, BR.SpellIds = Debug, BuffKey, SpellIds
BR.IsSuppressed, BR.AurasSecret = IsSuppressed, AurasSecret
BR.NewIcon = NewIcon

-- /obr opens the options window, everything is set up there. /obr debug prints what casts and
-- combat reads decide.
SLASH_OpcowsBuffReminder1 = "/obr"
SlashCmdList.OpcowsBuffReminder = function(msg)
    if msg and msg:lower():match("^%s*debug%s*$") then
        BR.debug = not BR.debug
        Print("debug " .. (BR.debug and "on" or "off") .. ", auras secret now: " .. tostring(AurasSecret()))
        if BR.debug then
            BR.ClearCoolDebug()
            -- probe: can an alert mute the game's own sound for its aura
            Debug(("MuteSoundFile: %s, UnmuteSoundFile: %s"):format(type(MuteSoundFile), type(UnmuteSoundFile)))
        end
        return
    end
    if msg and msg:lower():match("^%s*cdm%s*$") then
        BR.CDMDump()
        return
    end
    BR.ToggleConfig()
end

-- saved variables --------------------------------------------------------------------------
-- fill in missing or mistyped options and upgrade 1.x settings
function BR.SanityCheck()
    local opts = OpcowsBuffReminderDB.Options
    -- other characters' settings, account wide
    if type(OpcowsBuffReminderAccount) ~= "table" then OpcowsBuffReminderAccount = {} end
    if type(OpcowsBuffReminderAccount.chars) ~= "table" then OpcowsBuffReminderAccount.chars = {} end
    for key, c in pairs(OpcowsBuffReminderAccount.chars) do
        if type(c) ~= "table" or type(c.BuffGroups) ~= "table" or type(c.Options) ~= "table"
            or type(c.Enchants) ~= "table" or type(c.time) ~= "number" then
            OpcowsBuffReminderAccount.chars[key] = nil
        end
    end
    -- named saves, account wide
    if type(OpcowsBuffReminderAccount.saves) ~= "table" then OpcowsBuffReminderAccount.saves = {} end
    for name, s in pairs(OpcowsBuffReminderAccount.saves) do
        if type(name) ~= "string" or type(s) ~= "table" or type(s.BuffGroups) ~= "table"
            or type(s.Options) ~= "table" or type(s.Enchants) ~= "table" or type(s.time) ~= "number" then
            OpcowsBuffReminderAccount.saves[name] = nil
        end
    end
    -- the glow was a switch
    if opts.glow == true then opts.glow = "pulse" elseif opts.glow == false then opts.glow = "none" end
    -- there was one opacity for every icon, keep it for warnings too
    if opts.warnalpha == nil and type(opts.alpha) == "number" then opts.warnalpha = opts.alpha end
    for k, v in pairs(BR.DefaultOptions) do
        if type(v) == "table" then
            if type(opts[k]) ~= "table" then opts[k] = {} end
            for k2, v2 in pairs(v) do
                if type(opts[k][k2]) ~= type(v2) then opts[k][k2] = v2 end
            end
        elseif type(opts[k]) ~= type(v) then
            opts[k] = v
        end
    end
    -- [spell id] = its cooldown in seconds, last read out of combat
    if type(OpcowsBuffReminderDB.Cooldowns) ~= "table" then OpcowsBuffReminderDB.Cooldowns = {} end
    for k, v in pairs(OpcowsBuffReminderDB.Cooldowns) do
        if type(k) ~= "number" or type(v) ~= "number" or v < MIN_COOLDOWN then OpcowsBuffReminderDB.Cooldowns[k] = nil end
    end
    if type(OpcowsBuffReminderDB.Seen) ~= "table" then OpcowsBuffReminderDB.Seen = {} end
    for k, e in pairs(OpcowsBuffReminderDB.Seen) do
        if type(e) ~= "table" or type(e.name) ~= "string" or type(e.t) ~= "number" then OpcowsBuffReminderDB.Seen[k] = nil end
    end
    -- 2.0 betas and 1.x had enchant switches and a charges warning, and enchants used the defaults
    if type(OpcowsBuffReminderDB.Enchants) ~= "table" then
        local old = type(opts.enchants) == "table" and opts.enchants or {}
        OpcowsBuffReminderDB.Enchants = {}
        for slot in pairs(ENCHANT_SLOTS) do
            local e = NewEnchant()
            if old[slot] == true then e.conditions.always = opts.conditions.always end
            if type(opts.warncharges) == "number" then e.warnstacks = opts.warncharges end
            if type(opts.script) == "string" then e.script = opts.script end
            if TIMERS[old.timer] then e.timer = old.timer end
            if type(old.size) == "number" and old.size > 0 then e.size = old.size end
            OpcowsBuffReminderDB.Enchants[slot] = e
        end
    end
    for k, v in pairs(opts) do
        local d = BR.DefaultOptions[k]
        if d == nil then
            if not EXTRA_OPTIONS[k] then opts[k] = nil end
        elseif type(d) == "table" then
            for k2 in pairs(v) do
                if d[k2] == nil then v[k2] = nil end
            end
        end
    end
    -- 1.x stored sound names, the modern PlaySound takes sound kit ids
    opts.warnsound = ResolveSound(opts.warnsound)
    -- icon placement: the 2.0 beta had one position for all the icons, then rows centred on x, y,
    -- then a grid with x, y the top left cell's centre, all with the one icon size
    local bars = {}
    local pitch = opts.size + ICON_SPACING * 2
    if type(opts.bars) == "table" then
        for _, b in ipairs(opts.bars) do
            if type(b) == "table" then
                local bar = { left = b.left, top = b.top, cells = {} }
                local used = {}
                if type(b.cells) == "table" then
                    for _, cell in ipairs(b.cells) do
                        if type(cell) == "table" and type(cell.key) == "string" and type(cell.c) == "number"
                            and type(cell.r) == "number" then
                            local c, r = math.floor(cell.c), math.floor(cell.r)
                            if not used[c .. "," .. r] then
                                used[c .. "," .. r] = true
                                local new = { key = cell.key, c = c, r = r }
                                if cell.ha == -1 or cell.ha == 1 then new.ha = cell.ha end
                                if cell.va == -1 or cell.va == 1 then new.va = cell.va end
                                table.insert(bar.cells, new)
                            end
                        end
                    end
                elseif type(b.keys) == "table" then
                    for _, k in ipairs(b.keys) do
                        if type(k) == "string" then table.insert(bar.cells, { key = k, c = #bar.cells, r = 0 }) end
                    end
                    if type(b.x) == "number" and type(b.y) == "number" then
                        bar.left, bar.top = b.x - #bar.cells * pitch / 2, b.y + pitch / 2
                    end
                end
                if type(bar.left) ~= "number" or type(bar.top) ~= "number" then
                    if type(b.x) == "number" and type(b.y) == "number" then
                        bar.left, bar.top = b.x - pitch / 2, b.y + pitch / 2
                    end
                end
                if type(bar.left) == "number" and type(bar.top) == "number" then
                    Normalize(bar)
                    table.insert(bars, bar)
                end
            end
        end
    end
    if #bars == 0 then
        -- an empty set is centred on its position when icons join it
        local x, y = OldPosition(opts.position, opts.size)
        bars = { { left = x, top = y, cells = {} } }
    end
    opts.bars = bars
    opts.position = nil
    if not TEXT_PRIORITIES[opts.icontext.priority] then opts.icontext.priority = "both" end
    if not TIME_POSITIONS[opts.icontext.timepos] then opts.icontext.timepos = "on" end
    if not GLOWS[opts.glow] or opts.glow == "default" then opts.glow = "none" end
    if not OVERLAYS[opts.overlay] or opts.overlay == "default" then opts.overlay = "none" end
    if not GLOWS[opts.warnglow] or opts.warnglow == "default" then opts.warnglow = "none" end
    if not OVERLAYS[opts.warnoverlay] or opts.warnoverlay == "default" then opts.warnoverlay = "none" end
    -- a test build picked the click from a list, with an "off" in it
    local OLD_CLICKS = { left = "1", right = "2", middle = "3", shift = "shift-1", ctrl = "ctrl-1", alt = "alt-1" }
    if opts.clickbutton == "off" then opts.clicktocast = false end
    opts.clickbutton = OLD_CLICKS[opts.clickbutton] or opts.clickbutton
    if type(opts.clicktocast) ~= "boolean" then opts.clicktocast = true end
    if not ParseClick(opts.clickbutton) then opts.clickbutton = "1" end
    if type(opts.dismiss) ~= "boolean" then opts.dismiss = true end
    if type(opts.combatbadge) ~= "boolean" then opts.combatbadge = false end
    if not ParseClick(opts.dismissbutton) then opts.dismissbutton = "2" end
    -- one click can't do both, casting keeps it
    if opts.dismissbutton == opts.clickbutton then
        opts.dismissbutton = opts.clickbutton == "2" and "shift-2" or "2"
    end
    local DOCKS = { panel = true, auto = true, right = true, left = true, above = true, below = true }
    if not DOCKS[opts.partydock] then opts.partydock = "auto" end

    -- what buff and enchant groups share
    local function CheckGroup(group)
        if type(group.conditions) ~= "table" then group.conditions = {} end
        for k, v in pairs(BR.DefaultOptions.conditions) do
            local c = group.conditions[k]
            -- 1.x slash commands stored booleans
            if c == true then c = 1 elseif c == false then c = 0 end
            if type(c) ~= "number" then c = v end
            group.conditions[k] = c
        end
        if type(group.warntime) ~= "number" then group.warntime = opts.warntime end
        if type(group.warnstacks) ~= "number" then group.warnstacks = 0 end
        if not TIMERS[group.timer] then group.timer = "default" end
        if not GLOWS[group.glow] then group.glow = "default" end
        if not OVERLAYS[group.overlay] then group.overlay = "default" end
        if not GLOWS[group.warnglow] then group.warnglow = "default" end
        if not OVERLAYS[group.warnoverlay] then group.warnoverlay = "default" end
        if type(group.size) ~= "number" or group.size < 10 or group.size > 400 then group.size = nil end
        -- its own opacities, none follows the Options tab
        for _, k in ipairs({ "alpha", "warnalpha" }) do
            if type(group[k]) ~= "number" or group[k] < 0 or group[k] > 1 then group[k] = nil end
        end
        if type(group.script) ~= "string" then group.script = "" end
    end
    local before26 = (tonumber(opts.version) or 0) < 2.6
    for g, group in pairs(OpcowsBuffReminderDB.BuffGroups) do
        if type(group) ~= "table" then
            OpcowsBuffReminderDB.BuffGroups[g] = nil
        else
            if type(group.buffs) ~= "table" then group.buffs = {} end
            -- 1.x cached icon paths here
            for b in pairs(group.buffs) do group.buffs[b] = true end
            CheckGroup(group)
            if not COMBAT_MODES[group.combat] then group.combat = "cdm" end
            if type(group.click) ~= "string" or group.click == "" then group.click = "auto" end
            if type(group.party) ~= "boolean" then group.party = true end
            if type(group.hitcd) ~= "number" or group.hitcd < 0 then group.hitcd = 0 end
            -- 2.4 had only the cooldown, set meant any hit
            if not HIT_USES[group.hituse] then group.hituse = group.hitcd > 0 and "hits" or "auto" end
            -- before 2.6 off was the default, auto changes nothing for buffs without charges
            if before26 and group.hituse == "off" then group.hituse = "auto" end
            if group.icon == nil then group.icon = QUESTION_MARK end
        end
    end
    for k in pairs(OpcowsBuffReminderDB.Enchants) do
        if not ENCHANT_SLOTS[k] then OpcowsBuffReminderDB.Enchants[k] = nil end
    end
    for slot in pairs(ENCHANT_SLOTS) do
        if type(OpcowsBuffReminderDB.Enchants[slot]) ~= "table" then OpcowsBuffReminderDB.Enchants[slot] = NewEnchant() end
        local eg = OpcowsBuffReminderDB.Enchants[slot]
        CheckGroup(eg)
        -- clicking uses what you last put on the hand
        if eg.click ~= "off" then eg.click = "auto" end
        if type(eg.showcount) ~= "boolean" then eg.showcount = false end
        local last = eg.last
        if type(last) ~= "table" or not (Num(last.item) or Num(last.spell)) then eg.last = nil end
    end
    -- alerts, new in 2.6
    if type(OpcowsBuffReminderDB.Alerts) ~= "table" then OpcowsBuffReminderDB.Alerts = {} end
    local alerts = OpcowsBuffReminderDB.Alerts
    for aura, alert in pairs(alerts) do
        if type(aura) ~= "string" or aura == "" or type(alert) ~= "table" then
            alerts[aura] = nil
        else
            CheckGroup(alert)
            -- what CheckGroup adds that alerts don't use
            alert.warntime, alert.warnstacks, alert.warnglow, alert.warnoverlay, alert.warnalpha = nil, nil, nil, nil, nil
            if alert.glow == "default" then alert.glow = "none" end
            -- the spell alert can't be shown on an alert, see SetGlow
            if alert.glow == "alert" then alert.glow = "pulse" end
            if alert.overlay == "default" then alert.overlay = "none" end
            if type(alert.alpha) ~= "number" then alert.alpha = 1 end
            if type(alert.ids) ~= "table" then alert.ids = {} end
            for id in pairs(alert.ids) do
                if type(id) ~= "number" then alert.ids[id] = nil else alert.ids[id] = true end
            end
            if type(alert.sound) ~= "number" and type(alert.sound) ~= "string" then alert.sound = nil end
            if alert.icon == nil then alert.icon = QUESTION_MARK end
        end
    end
    opts.version = BR.DefaultOptions.version
end

-- events -----------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    BR.elapsed = BR.elapsed + elapsed
    if BR.elapsed < TICK then return end
    BR.elapsed = 0
    BR.UpdateStatus()
    -- in combat this is the live lookup, a buff can drop without an aura event we can use
    if BR.needScan or AurasSecret() then BR.ScanAuras() end
    BR.UpdateLive()
    BR.UpdateAlerts()
    BR.ScanEnchants()
    BR.RunScripts()
    BR.Refresh()
end

function BR.Init()
    if type(OpcowsBuffReminderDB) ~= "table" then OpcowsBuffReminderDB = {} end
    if type(OpcowsBuffReminderDB.BuffGroups) ~= "table" then OpcowsBuffReminderDB.BuffGroups = {} end
    if type(OpcowsBuffReminderDB.Options) ~= "table" then OpcowsBuffReminderDB.Options = DeepCopy(BR.DefaultOptions) end
    BR.SanityCheck()
    BR.RememberCharacter()
    BR.CompileScripts()
    BR.ApplyLayout()
    BR.SetLocked(true)
    BR.UpdateMinimap()

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- hits taken, for buff groups whose charges hits use. Not every client has it.
    pcall(frame.RegisterUnitEvent, frame, "UNIT_COMBAT", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_LOGOUT")
    -- a spell's text loaded, for the buff picker. Not every client has it.
    pcall(frame.RegisterEvent, frame, "SPELL_DATA_LOAD_RESULT")
    frame:SetScript("OnUpdate", OnUpdate)

    Print("loaded. Type /obr for the options.")
end

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            self:UnregisterEvent("ADDON_LOADED")
            BR.Init()
        end
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target, cast GUID, spell id
        BR.OnCastSent(arg2, arg4)
        if Num(arg4) then EnchantCastSent(arg4) end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, cast GUID, spell id
        if Num(arg3) then EnchantCastDone(arg3) end
        BR.OnCast(arg3)
        return
    elseif event == "UNIT_COMBAT" then
        -- unit, action, descriptor, amount, school
        BR.OnHit(arg2, arg3, arg4, arg5)
        return
    end

    if event == "UNIT_AURA" then
        -- in combat this fails and waits for PLAYER_REGEN_ENABLED
        BR.needScan = true
        BR.ScanAuras()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        BR.ScanEnchants()
    elseif event == "PLAYER_REGEN_DISABLED" then
        BR.status.combat = true
        BR.HideClickers()
        BR.OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        BR.status.combat = false
        BR.NotePredictedCharges()
        BR.needScan = true
        BR.ScanAuras()
    elseif event == "SPELLS_CHANGED" then
        BR.book = nil
    elseif event == "PLAYER_LOGOUT" then
        -- the settings may be new tables since login
        BR.RememberCharacter()
        return
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- many load at once, list them again when they're done
        if BR.OnSpellData and not BR.spellDataDue and C_Timer then
            BR.spellDataDue = true
            C_Timer.After(0.3, function()
                BR.spellDataDue = nil
                BR.OnSpellData()
            end)
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        BR.status.combat = InCombatLockdown() and true or false
        BR.needScan = true
        BR.ScanAuras()
        BR.ScanEnchants()
        -- once the Cooldown Manager has made its frames
        if not BR.noticesDue and C_Timer then
            BR.noticesDue = true
            C_Timer.After(10, function() BR.CombatNotices() end)
        end
    end
    BR.UpdateStatus()
    BR.Refresh()
end)
frame:RegisterEvent("ADDON_LOADED")
