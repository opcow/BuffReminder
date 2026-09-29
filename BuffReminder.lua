-- BuffReminder.lua
-- Author      : mcrane
--
-- WoW: Forever port. Buffs are read out of combat, when aura data is readable. In combat the
-- client turns aura data into secret values, so the addon keeps the last snapshot and predicts
-- expiry from the expiration times it recorded before the pull, then re-reads after combat.

local ADDON_NAME = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local TICK = 1          -- seconds between status/timer checks
local ICON_SPACING = 2

-- clients without secret values never have secrets
local issecretvalue = issecretvalue or function() return false end

BuffReminder = {
    icons = {},             -- pooled icon frames
    groupState = {},        -- [group] = { present, expires (0 = permanent), duration } from the last readable scan
    enchants = {},          -- [slot] = { present, expires, charges }
    scripts = {},           -- [group] = compiled condition script
    scriptRes = {},         -- [group] = last script result, true hides the icon
    scriptErrReported = {}, -- [function] = true once its runtime error has been printed
    defaultScript = nil,
    defaultScriptRes = false,
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
local BR = BuffReminder

BR.DefaultOptions = {
    ["version"] = "2.0",
    ["size"] = 30,
    ["warntime"] = 60,
    ["warncharges"] = 5,
    ["alpha"] = 1.0,
    ["script"] = "",
    ["enchants"] = {
        ["main"] = false,
        ["off"] = false,
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
local EXTRA_OPTIONS = { ["warnsound"] = true, ["position"] = true }

local CONDITIONS = { "dead", "instance", "party", "raid", "resting", "taxi", "combat", "mounted" }
local STATE_TEXT = { [0] = "ignored", [1] = "hide if true", [2] = "hide if false" }
local ALWAYS_TEXT = { [0] = "normal", [1] = "disabled", [2] = "always shown" }
local ENCHANT_SLOTS = { main = 16, off = 17 }

-- util functions ---------------------------------------------------------------------------
local function Echo(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcbeb1c" .. msg .. "|r")
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cfff4f9a7BuffReminder:|r " .. msg)
end

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return c
end

-- split a command line into words, "quoted text" counts as one word
local function GetArgs(msg)
    local args = {}
    local pos = 1
    while true do
        local s = msg:find("%S", pos)
        if not s then break end
        local e
        if msg:sub(s, s) == '"' then
            e = msg:find('"', s + 1, true)
            if not e then
                Print("Unfinished quote in command.")
                return nil
            end
            table.insert(args, msg:sub(s + 1, e - 1))
        else
            e = (msg:find("%s", s) or #msg + 1) - 1
            table.insert(args, msg:sub(s, e))
        end
        pos = e + 1
    end
    local largs = {}
    for i, a in ipairs(args) do largs[i] = a:lower() end
    return args, largs
end

-- raw text following the word "script", so Lua code keeps its quotes and spacing
local function ScriptText(msg)
    local _, e = msg:lower():find("%sscript%f[%s%z]")
    if not e then
        _, e = msg:lower():find("^%s*script%f[%s%z]")
    end
    return e and msg:sub(e + 1):match("^%s*(.-)%s*$") or ""
end

local function ToNum(n)
    local v = tonumber(n)
    if v == nil then Print("Invalid number given.") end
    return v
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
        }
        table.insert(list, entry)
        keep(aura.name and aura.name:lower(), entry)
        keep(aura.spellId, entry)
    end
    return found, list
end

-- snapshot the state of every group, returns false if auras couldn't be read
function BR.ScanAuras()
    if AurasSecret() then return false end
    local ok, found = pcall(ReadPlayerBuffs)
    if not ok then return false end
    BR.groupState = {}
    for g, group in pairs(BRVars.BuffGroups) do
        local best
        for buff in pairs(group.buffs) do
            local e = found[BuffKey(buff)]
            if e and (best == nil or Outlasts(e, best)) then best = e end
        end
        if best then
            group.icon = best.icon or group.icon
            BR.groupState[g] = { present = true, expires = best.expires, duration = best.duration }
        else
            BR.groupState[g] = { present = false }
        end
    end
    BR.needScan = false
    return true
end

function BR.ScanEnchants()
    local r = { pcall(GetWeaponEnchantInfo) }
    if not r[1] then return end
    for i = 2, 9 do
        if issecretvalue(r[i]) then return end
    end
    local now = GetTime()
    local function entry(has, ms, charges)
        if not has then return { present = false } end
        return { present = true, expires = now + (ms or 0) / 1000, charges = charges or 0 }
    end
    -- hasEnchant, expirationMs, charges, enchantId for each hand
    BR.enchants.main = entry(r[2], r[3], r[4])
    BR.enchants.off = entry(r[6], r[7], r[8])
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
    local fn, err = loadstring(code, "BuffReminder " .. label)
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
    for g, group in pairs(BRVars.BuffGroups) do
        BR.scripts[g] = Compile(group.script, g)
    end
    BR.defaultScript = Compile(BRVars.Options.script, "default")
end

function BR.RunScripts()
    for g in pairs(BRVars.BuffGroups) do
        BR.scriptRes[g] = RunScript(BR.scripts[g], BR.scriptRes[g])
    end
    BR.defaultScriptRes = RunScript(BR.defaultScript, BR.defaultScriptRes)
end

-- display ----------------------------------------------------------------------------------
local frame = CreateFrame("Frame", "BuffReminderFrame", UIParent)
frame:SetSize(34, 34)
frame:SetFrameStrata("LOW")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(false)
frame:RegisterForDrag("LeftButton")
frame.cross = frame:CreateTexture(nil, "BACKGROUND")
frame.cross:SetAllPoints()
BR.frame = frame

local function AcquireIcon(i)
    local f = BR.icons[i]
    if not f then
        f = CreateFrame("Frame", nil, frame)
        f.texture = f:CreateTexture(nil, "ARTWORK")
        f.texture:SetAllPoints()
        f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cooldown:SetAllPoints()
        f.cooldown:SetDrawEdge(false)
        f.cooldown:SetHideCountdownNumbers(true)
        f.text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        f.text:SetPoint("BOTTOM", 0, 2)
        BR.icons[i] = f
    end
    return f
end

-- work out which icons should be visible, using predicted expiry while auras are secret
function BR.Refresh()
    local opts = BRVars.Options
    local now = GetTime()
    local list = {}

    if not BR.hideAll then
        for g, group in pairs(BRVars.BuffGroups) do
            local st = BR.groupState[g]
            -- no state means auras haven't been readable yet, don't guess
            if st and not IsSuppressed(group.conditions) and not BR.scriptRes[g] then
                if not st.present or (st.expires > 0 and st.expires <= now) then
                    table.insert(list, { key = "1" .. g, icon = group.icon })
                elseif st.expires > 0 and st.expires - now <= group.warntime then
                    table.insert(list, { key = "1" .. g, icon = group.icon, expires = st.expires, duration = st.duration })
                end
            end
        end

        if not IsSuppressed(opts.conditions) and not BR.defaultScriptRes then
            for slot, invSlot in pairs(ENCHANT_SLOTS) do
                local e = BR.enchants[slot]
                local tex = GetInventoryItemTexture("player", invSlot)
                if opts.enchants[slot] and e and tex then
                    if not e.present or e.expires <= now then
                        table.insert(list, { key = "2" .. slot, icon = tex })
                    elseif e.expires - now <= opts.warntime or (e.charges > 0 and e.charges <= opts.warncharges) then
                        table.insert(list, { key = "2" .. slot, icon = tex, expires = e.expires })
                    end
                end
            end
        end
    end

    -- groups come out of pairs in random order, sort so icons don't jump around
    table.sort(list, function(a, b) return a.key < b.key end)

    local pitch = opts.size + ICON_SPACING * 2
    local offset = (#list - 1) * pitch / 2
    local shown, newIcon = {}, false
    for i, item in ipairs(list) do
        local f = AcquireIcon(i)
        f:SetSize(opts.size, opts.size)
        f:SetAlpha(opts.alpha)
        f:ClearAllPoints()
        f:SetPoint("CENTER", frame, "CENTER", (i - 1) * pitch - offset, 0)
        f.texture:SetTexture(item.icon or QUESTION_MARK)
        if item.expires and item.duration and item.duration > 0 then
            f.cooldown:SetCooldown(item.expires - item.duration, item.duration)
        else
            f.cooldown:Clear()
        end
        f.text:SetText(item.expires and FormatTime(item.expires - now) or "")
        f:Show()
        shown[item.key] = true
        if not BR.shown[item.key] then newIcon = true end
    end
    for i = #list + 1, #BR.icons do
        BR.icons[i]:Hide()
    end
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
    frame:EnableMouse(not locked)
    if locked then
        frame.cross:SetTexture(nil)
    else
        frame.cross:SetTexture(MEDIA .. "cross")
    end
end

function BR.ApplyLayout()
    local opts = BRVars.Options
    frame:SetSize(opts.size, opts.size)
    frame:ClearAllPoints()
    local p = opts.position
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER")
    end
end

frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    BRVars.Options.position = { point, relPoint, x, y }
end)

-- slash command functions ------------------------------------------------------------------
function BR.GroupExists(group)
    if BRVars.BuffGroups[group] == nil then
        Print('Group "' .. tostring(group) .. '" does not exist.')
        BR.PrintAllGroups()
        return false
    end
    return true
end

function BR.FindBuffGroup(buff)
    local key = BuffKey(buff)
    for g, group in pairs(BRVars.BuffGroups) do
        for b in pairs(group.buffs) do
            if BuffKey(b) == key then return g, b end
        end
    end
    return nil
end

function BR.PrintAllGroups()
    Echo("Your buff groups:")
    for g in pairs(BRVars.BuffGroups) do
        Echo("   " .. g)
    end
end

function BR.PrintBuffs()
    for g, group in pairs(BRVars.BuffGroups) do
        Echo("Group: " .. g)
        for b in pairs(group.buffs) do
            Echo("   " .. b)
        end
    end
end

local function PrintConditions(conds)
    Echo("   always: " .. ALWAYS_TEXT[conds.always])
    for _, k in ipairs(CONDITIONS) do
        Echo(("   %s: %s"):format(k, STATE_TEXT[conds[k]]))
    end
end

function BR.PrintGroup(g)
    local group = BRVars.BuffGroups[g]
    Echo("Group: " .. g)
    for b in pairs(group.buffs) do
        Echo("   buff: " .. b)
    end
    PrintConditions(group.conditions)
    Echo("   early warning time: " .. group.warntime)
    if group.script ~= "" then Echo("   script: " .. group.script) end
end

function BR.PrintDefaults()
    local opts = BRVars.Options
    Echo("Default conditions (weapon enchants and new groups):")
    PrintConditions(opts.conditions)
    Echo("   early warning time: " .. opts.warntime)
    Echo("   enchant charges warning: " .. opts.warncharges)
    Echo("   main hand enchant: " .. (opts.enchants.main and "on" or "off"))
    Echo("   off hand enchant: " .. (opts.enchants.off and "on" or "off"))
    if opts.script ~= "" then Echo("   script: " .. opts.script) end
end

function BR.PrintAuras()
    if AurasSecret() then
        Print("Buffs can't be read right now (in combat).")
        return
    end
    local ok, _, list = pcall(ReadPlayerBuffs)
    if not ok then
        Print("Buffs can't be read right now (in combat).")
        return
    end
    local now = GetTime()
    Echo("Your current buffs:")
    for _, e in ipairs(list) do
        local left = e.expires > 0 and FormatTime(e.expires - now) or "permanent"
        Echo(("   %s (%s) %s"):format(tostring(e.name), tostring(e.spellId), left))
    end
end

function BR.NewGroup(g)
    local opts = BRVars.Options
    BRVars.BuffGroups[g] = {
        ["conditions"] = DeepCopy(opts.conditions),
        ["warntime"] = opts.warntime,
        ["icon"] = QUESTION_MARK,
        ["script"] = "",
        ["buffs"] = {},
    }
end

function BR.AddBuffToGroup(g, buff)
    if BRVars.BuffGroups[g] == nil then BR.NewGroup(g) end
    local group = BRVars.BuffGroups[g]
    if buff ~= nil then
        group.buffs[buff] = true
        if group.icon == QUESTION_MARK then
            group.icon = SpellTexture(buff) or QUESTION_MARK
        end
    end
    BR.PrintGroup(g)
end

function BR.RemoveBuff(buff)
    local key = BuffKey(buff)
    for _, group in pairs(BRVars.BuffGroups) do
        for b in pairs(group.buffs) do
            if BuffKey(b) == key then group.buffs[b] = nil end
        end
    end
    Print("Removed " .. buff .. " from all buff groups.")
end

-- reset the icons to unknown state, they're relearned from the next scan
function BR.ClearIcons()
    for _, group in pairs(BRVars.BuffGroups) do
        group.icon = QUESTION_MARK
        for b in pairs(group.buffs) do
            group.icon = SpellTexture(b) or group.icon
        end
    end
end

-- cycle a tri-state condition, returns false if it isn't a condition
local function CycleCondition(conds, name)
    if conds[name] == nil then return false end
    conds[name] = (conds[name] + 1) % 3
    return true
end

-- group and default share the enable/disable/condition/number/script subcommands
local function ConditionCommand(conds, word, msg, onNumber, onScript)
    if word == "disable" then
        conds.always = 1
    elseif word == "enable" then
        conds.always = 0
    elseif word == "script" then
        onScript(ScriptText(msg))
    elseif CycleCondition(conds, word) then
        -- cycled
    elseif tonumber(word) then
        onNumber(tonumber(word))
    else
        return false
    end
    return true
end

function BR.ShowHelp()
    Echo("***** BuffReminder Help *****")
    Echo("Buffs you want to monitor must be added to buff groups. Mutually exclusive buffs should go into common groups.")
    Echo("Buffs can be given by name or spell id, see /br auras.")
    Echo("Group commands:")
    Echo("  /br group <group> add <buff> - adds a buff, creating the group if needed")
    Echo("  /br group <group> remove - removes the group")
    Echo("  /br group <group> disable | enable - stops or allows the group's icon from showing")
    Echo("  /br group <group> <always|dead|instance|party|raid|resting|taxi|combat|mounted> - cycles a condition")
    Echo("  /br group <group> <number> - sets the early warning time in seconds")
    Echo("  /br group <group> script [lua] - icon is hidden while the script returns true, no lua clears it")
    Echo("  /br group [group] - lists your groups or shows one group")
    Echo("Buff commands:")
    Echo("  /br buff <buff> remove - stops monitoring a buff")
    Echo("  /br buff [buff] - lists watched buffs or shows the group a buff belongs to")
    Echo("  /br auras - lists your current buffs with their spell ids")
    Echo("Weapon enchants and defaults:")
    Echo("  /br enchant <main|off> - toggles the weapon enchant reminder")
    Echo("  /br default [condition|disable|enable|<number>|script [lua]] - default conditions, also used by new groups")
    Echo("  /br charges <number> - warns when an enchant has this many charges left")
    Echo("General options:")
    Echo("  /br alpha <number> - icon transparency (0.0 to 1.0)")
    Echo("  /br size <number> - icon size (10 to 400)")
    Echo("  /br lock | unlock - locks or unlocks the icon frame for placement")
    Echo("  /br hide - temporarily hides or shows the icons")
    Echo("  /br sound [id|name] - warning sound for new icons, ex: /br sound RAID_WARNING, none turns it off")
    Echo("  /br reseticons - clears the icon cache")
    Echo("  /br NUKE - clears all of your settings")
end

SLASH_BuffReminder1 = "/br"
SLASH_BuffReminder2 = "/buffreminder"
SlashCmdList.BuffReminder = function(msg)
    local args, largs = GetArgs(msg)
    if args == nil then return end
    local cmd = largs[1]
    local opts = BRVars.Options
    local handled = true

    if cmd == nil or cmd == "help" then
        BR.ShowHelp()
        return
    elseif cmd == "group" then
        local g = args[2]
        if g == nil then
            BR.PrintAllGroups()
        elseif largs[3] == "add" then
            BR.AddBuffToGroup(g, args[4])
        elseif BR.GroupExists(g) then
            local group = BRVars.BuffGroups[g]
            if largs[3] == "remove" then
                BRVars.BuffGroups[g] = nil
                BR.groupState[g] = nil
                BR.scripts[g] = nil
                Print("Removed group " .. g .. ".")
            elseif largs[3] == nil or ConditionCommand(group.conditions, largs[3], msg,
                function(n) group.warntime = n end,
                function(code)
                    group.script = code
                    BR.scripts[g] = Compile(code, g)
                    BR.scriptRes[g] = false
                end) then
                BR.PrintGroup(g)
            else
                handled = false
            end
        end
    elseif cmd == "default" then
        if largs[2] == nil or ConditionCommand(opts.conditions, largs[2], msg,
            function(n) opts.warntime = n end,
            function(code)
                opts.script = code
                BR.defaultScript = Compile(code, "default")
                BR.defaultScriptRes = false
            end) then
            BR.PrintDefaults()
        else
            handled = false
        end
    elseif cmd == "buff" then
        if args[2] == nil then
            BR.PrintBuffs()
        elseif largs[3] == "remove" then
            BR.RemoveBuff(args[2])
        else
            local g = BR.FindBuffGroup(args[2])
            if g == nil then
                Print("Buff " .. args[2] .. " does not exist in any buff groups.")
            else
                BR.PrintGroup(g)
            end
        end
    elseif cmd == "auras" then
        BR.PrintAuras()
    elseif cmd == "enchant" then
        if largs[2] == "main" or largs[2] == "off" then
            opts.enchants[largs[2]] = not opts.enchants[largs[2]]
            BR.PrintDefaults()
        else
            handled = false
        end
    elseif cmd == "unlock" then
        BR.SetLocked(false)
    elseif cmd == "lock" then
        BR.SetLocked(true)
    elseif cmd == "hide" then
        BR.hideAll = not BR.hideAll
        Print(BR.hideAll and "Icons will not be shown." or "Icons will be shown.")
    elseif args[1] == "NUKE" then
        BRVars.BuffGroups = {}
        BRVars.Options = DeepCopy(BR.DefaultOptions)
        BR.groupState = {}
        BR.CompileScripts()
        BR.ApplyLayout()
        Print("All settings cleared.")
    elseif cmd == "sound" then
        if args[2] == nil or largs[2] == "none" then
            opts.warnsound = nil
        else
            local id = ResolveSound(args[2])
            if id then
                opts.warnsound = id
                PlaySound(id, "Master")
            else
                Print("Unknown sound " .. args[2] .. ".")
            end
        end
    elseif cmd == "size" then
        local n = ToNum(args[2])
        handled = n ~= nil and n >= 10 and n <= 400
        if handled then
            opts.size = n
            frame:SetSize(n, n)
        end
    elseif cmd == "alpha" then
        local n = ToNum(args[2])
        handled = n ~= nil and n >= 0 and n <= 1.0
        if handled then opts.alpha = n end
    elseif cmd == "time" then
        local n = ToNum(args[2])
        handled = n ~= nil
        if handled then opts.warntime = n end
    elseif cmd == "charges" then
        local n = ToNum(args[2])
        handled = n ~= nil
        if handled then opts.warncharges = n end
    elseif cmd == "reseticons" then
        BR.ClearIcons()
    elseif cmd == "config" then
        Print("The config dialog hasn't been ported yet, use /br help for commands.")
    else
        handled = false
    end

    BR.Update()

    if not handled then
        Print("Command error. Try /br help.")
    end
end

-- saved variables --------------------------------------------------------------------------
-- fill in missing or mistyped options and upgrade 1.x settings
function BR.SanityCheck()
    local opts = BRVars.Options
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
    if type(opts.position) ~= "table" then opts.position = nil end

    for g, group in pairs(BRVars.BuffGroups) do
        if type(group) ~= "table" then
            BRVars.BuffGroups[g] = nil
        else
            if type(group.buffs) ~= "table" then group.buffs = {} end
            -- 1.x cached icon paths here
            for b in pairs(group.buffs) do group.buffs[b] = true end
            if type(group.conditions) ~= "table" then group.conditions = {} end
            for k, v in pairs(BR.DefaultOptions.conditions) do
                local c = group.conditions[k]
                -- 1.x slash commands stored booleans
                if c == true then c = 1 elseif c == false then c = 0 end
                if type(c) ~= "number" then c = v end
                group.conditions[k] = c
            end
            if type(group.warntime) ~= "number" then group.warntime = opts.warntime end
            if type(group.script) ~= "string" then group.script = "" end
            if group.icon == nil then group.icon = QUESTION_MARK end
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
    if BR.needScan then BR.ScanAuras() end
    BR.ScanEnchants()
    BR.RunScripts()
    BR.Refresh()
end

function BR.Init()
    if type(BRVars) ~= "table" then BRVars = {} end
    if type(BRVars.BuffGroups) ~= "table" then BRVars.BuffGroups = {} end
    if type(BRVars.Options) ~= "table" then BRVars.Options = DeepCopy(BR.DefaultOptions) end
    BR.SanityCheck()
    BR.CompileScripts()
    BR.ApplyLayout()
    BR.SetLocked(true)

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnUpdate", OnUpdate)

    Print("loaded. Type /br help for commands.")
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            self:UnregisterEvent("ADDON_LOADED")
            BR.Init()
        end
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        BR.status.combat = false
        BR.needScan = true
        BR.ScanAuras()
    elseif event == "PLAYER_ENTERING_WORLD" then
        BR.status.combat = InCombatLockdown() and true or false
        BR.needScan = true
        BR.ScanAuras()
        BR.ScanEnchants()
    end
    BR.UpdateStatus()
    BR.Refresh()
end)
frame:RegisterEvent("ADDON_LOADED")
