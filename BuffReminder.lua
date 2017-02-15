BuffReminder = {
    ["hide_all"] = false,
    ["button_space"] = 2,
    ["current_buffs"] = {},
    ["new_buffs"] = {},
    ["watched_buffs"] = {},
    ["missing_buffs"] = {},
    ["missing_groups"] = {},
    ["icons"] = {},
    ["enchants"] = {},
    ["player_status"] = {
        ["dead"] = false,
        ["instance"] = false,
        ["party"] = false,
        ["raid"] = false,
        ["resting"] = true,
        ["taxi"] = true,
        ["combat"] = false,
    },
    ["update_time"] = 0,
    ["scripts"] = {},
    ["script_res"] = {},
}

BRVars = {}
BRVars.BuffGroups = {}
BRVars.Options = {}

BuffReminder.DefaultOptions = {
    ["version"] = "1.2",
    ["warnsound"] = nil,
    ["size"] = 30,
    ["warntime"] = 60,
    ["warncharges"] = 5,
    ["alpha"] = 1.0,
    ["enchants"] = {
        ["main"] = false,
        ["off"] = false,
    },
    ["conditions"] = {
        ["always"] = 0,
        ["dead"] = 1,
        ["instance"] = 0,
        ["party"] = 0,
        ["raid"] = 0,
        ["resting"] = 1,
        ["taxi"] = 1,
        ["combat"] = 0,
    },
}
-- util functions
local function getArgs(m)
    local _, count = string.gsub(m, [["]], "")
    if math.mod(count, 2) ~= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Unfinished quote in command.")
        return nil, 0
    end
    
    for i in string.gfind(m, '(".-")') do
        m = string.gsub(m, i, string.gsub(string.gsub(i, "%s", "%%%%space%%%%"), '"', ""))
    end
    
    local args = {}
    local largs = {}
    local r
    local argc = 0
    for v in string.gfind(m, "(%S+)") do
        r, _ = string.gsub(v, "%%space%%", " ")
        table.insert(args, r)
        table.insert(largs, string.lower(r))
        argc = argc + 1
    end
    return args, largs, argc
end


local function tableLen(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function toNum(n)
    local n = tonumber(n)
    if n == nil then DEFAULT_CHAT_FRAME:AddMessage("Invalid number given.") end
    return n
end
-------------------------------------------------------------------------------
function BuffReminder.MakeIcon(index, texture)
    BuffReminder.icons[index] = CreateFrame("Frame", nil, BuffReminderFrame)
    BuffReminder.icons[index]:SetFrameStrata("BACKGROUND")
    BuffReminder.icons[index]:SetWidth(BRVars.Options.size)
    BuffReminder.icons[index]:SetHeight(BRVars.Options.size)

    tex = BuffReminder.icons[index]:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(texture)
    tex:SetAlpha(BRVars.Options.alpha)
    tex:SetAllPoints(BuffReminder.icons[index])
    BuffReminder.icons[index].texture = tex
end

function BuffReminder.MakeIcons()
    for i in BuffReminder.icons do
        BuffReminder.icons[i]:Hide()
    end
    local index = 1
    for i in BuffReminder.missing_groups do
        local skipIcon = false
        for k, v in pairs(BuffReminder.player_status) do
            if (BRVars.BuffGroups[i].conditions.always ~= 2) and ((BRVars.BuffGroups[i].conditions.always == 1) or (v and
                (BRVars.BuffGroups[i].conditions[k] == 1)) or (not v and BRVars.BuffGroups[i].conditions[k] == 2)) then
                skipIcon = true
                break
            end
        end
        if not skipIcon and not BuffReminder.script_res[i] then
            BuffReminder.MakeIcon(index, BuffReminder.missing_groups[i])
            index = index + 1
        end
    end
    skipIcon = false
    for k, v in pairs(BuffReminder.player_status) do
        if (BRVars.Options.conditions.always ~= 2) and ((BRVars.Options.conditions.always == 1) or (v and
            (BRVars.Options.conditions[k] == 1)) or (not v and BRVars.Options.conditions[k] == 2)) then
            skipIcon = true
            break
        end
    end
    if not skipIcon then
        if BRVars.Options.enchants.main and (not BuffReminder.enchants.main) then
            local t = GetInventoryItemTexture("player", 16)
            if t ~= nil then
                BuffReminder.MakeIcon(index, t)
                index = index + 1
            end
        end
        if BRVars.Options.enchants.off and (not BuffReminder.enchants.off) then
            local t = GetInventoryItemTexture("player", 17)
            if t ~= nil then
                BuffReminder.MakeIcon(index, t)
                index = index + 1
            end
        end
    end

    local count = index - 1
    local pitch = BRVars.Options.size + BuffReminder.button_space * 2
    local c = (pitch * (count - 1)) / 2
    for i = count, 1, -1 do
        BuffReminder.icons[i]:SetPoint("CENTER", c, 0)
        BuffReminder.icons[i]:Show()
        c = c - pitch
    end
end

-- search groups for matching buff name
function BuffReminder.FindBuffGroupByName(buff)
    for i in BRVars.BuffGroups do
        if BRVars.BuffGroups[i].buffs[buff] ~= nil then
            return i
        end
    end
    return nil
end

-- search groups for matching buff icon
function BuffReminder.FindGroupByIcon(icon, n)
    for i in BRVars.BuffGroups do
        for j in BRVars.BuffGroups[i].buffs do
            -- if this buff has no icon caches then cache t if matched
            if BRVars.BuffGroups[i].buffs[j] == "" then
                local name = BuffReminder.GetPlayerBuffName(n)
                if name == j then
                    BRVars.BuffGroups[i].buffs[j] = icon
                    return i, j
                end
            elseif BRVars.BuffGroups[i].buffs[j] == icon then
                return i, j
            end
        end
    end
    return nil
end

-- check if buffs have changd since last update
function BuffReminder.BuffsUpdated(buffs)
    for i in BuffReminder.current_buffs do
        if buffs[i] == nil then -- lost a buff
            return true
        end
    end
    for i in buffs do
        if BuffReminder.current_buffs[i] == nil then -- gained a buff
            return true
        end
    end
    return false
end

-- creates a list of current buffs which are also watched buffs
function BuffReminder.GetBuffs()
    BuffReminder.new_buffs = {}
    for i = 0, 15 do
        local buffIndex, untilCancelled = GetPlayerBuff(i, "HELPFUL")
        if buffIndex == -1 then break end
        local time = GetPlayerBuffTimeLeft(i)
        local icon = GetPlayerBuffTexture(i)
        local group, name = BuffReminder.FindGroupByIcon(icon, i)

        -- if the buff isn't found in the buff groups or time is low then don't add it
        if group ~= nil and (time > BRVars.BuffGroups[group].warntime or time == 0) then
            BuffReminder.new_buffs[name] = icon
            BRVars.BuffGroups[group].icon = icon
        end
    end
    local updated = BuffReminder.BuffsUpdated(BuffReminder.new_buffs)
    BuffReminder.current_buffs = BuffReminder.new_buffs
    return updated
end

function BuffReminder.GetMissinGroups()
    BuffReminder.missing_groups = {}
    -- first add all groups then remove any not found
    for i in BRVars.BuffGroups do
        BuffReminder.missing_groups[i] = BRVars.BuffGroups[i].icon
    end
    for i in BuffReminder.watched_buffs do
        if BuffReminder.current_buffs[i] ~= nil then
            local group = BuffReminder.FindBuffGroupByName(i)
            BuffReminder.missing_groups[group] = nil
        end
    end
end

function BuffReminder.GetMissinBuffs()
    BuffReminder.missing_buffs = {}
    for i in BuffReminder.watched_buffs do
        if BuffReminder.current_buffs[i] == nil then
            BuffReminder.missing_buffs[i] = BuffReminder.FindBuffGroup(i)
        end
    end
end

-- get a table of all watched buffs
function BuffReminder.GetWatchedBuffs()
    BuffReminder.watched_buffs = {}
    for i in BRVars.BuffGroups do
        for j in BRVars.BuffGroups[i].buffs do
            BuffReminder.watched_buffs[j] = BRVars.BuffGroups[i].buffs[j]
        end
    end
end

function BuffReminder.GetPlayerBuffName(n)
    TooltipScanner:ClearLines()
    TooltipScanner:SetPlayerBuff(n)
    return TooltipScannerTextLeft1:GetText()
end

function BuffReminder.GetEnchants()
    local changed = false
    if BRVars.Options.enchants.main or BRVars.Options.enchants.off then
        local hasMainHandEnchant, mainHandExpiration, mainHandCharges, hasOffHandEnchant, offHandExpiration, offHandCharges = GetWeaponEnchantInfo();
        if (BuffReminder.enchants.main ~= hasMainHandEnchant) or (hasOffHandEnchant ~= BuffReminder.enchants.off) then
            changed = true
        end
        BuffReminder.enchants.main = (hasMainHandEnchant == 1) and (mainHandExpiration > BRVars.Options.warntime * 1000) and ((mainHandCharges == 0) or (mainHandCharges > BRVars.Options.warncharges))
        BuffReminder.enchants.off = (hasOffHandEnchant == 1) and (offHandExpiration > BRVars.Options.warntime * 1000) and ((offHandCharges == 0) or (offHandCharges > BRVars.Options.warncharges))
    end
    return changed
end

function BuffReminder.GetScriptResults()
    local res
    local changed = false
    for k, v in pairs(BuffReminder.scripts) do
        res = v()
        if BuffReminder.script_res[k] ~= res then
            BuffReminder.script_res[k] = res
            changed = true
        end
    end
    return changed
end
-- slash command functions ------------------------------------------------------------------
function BuffReminder.ClearIcons()
    for i in BRVars.BuffGroups do
        BRVars.BuffGroups[i].icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        for j in BRVars.BuffGroups[i].buffs do
            BRVars.BuffGroups[i].buffs[j] = ""
        end
    end
    BuffReminder.Update()
end

function BuffReminder.GroupExists(group)
    if BRVars.BuffGroups[group] == nil then
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup "' .. tostring(group) .. '" does not exist.')
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hYour groups are:')
        for i in BRVars.BuffGroups do
            DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124h  ' .. i)
        end
        return false
    end
    return true
end

function BuffReminder.PrintBuffs()
    for i in BRVars.BuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup: ' .. tostring(i))
        for j in BRVars.BuffGroups[i].buffs do
            DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  " .. j)
        end
    end
end

function BuffReminder.PrintAllGroups()
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h** buff groups **")
    for i in BRVars.BuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h   " .. i)
        local t = BRVars.BuffGroups[i].buffs
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h** end of buff groups **")
end

function BuffReminder.PrintGroup(group)
    DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup: ' .. tostring(group))
    for i in BRVars.BuffGroups[group].buffs do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  " .. i)
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  ---")
    for i in BRVars.BuffGroups[group].conditions do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  hide condition " .. i .. ": \124cff80ff00\124h" .. tostring(BRVars.BuffGroups[group].conditions[i]))
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  early warning time: \124cff80ff00\124h" .. tostring(BRVars.BuffGroups[group].warntime))
end

function BuffReminder.AddBuffToGroup(grp, name, print)
    if BRVars.BuffGroups[grp] == nil then
        BRVars.BuffGroups[grp] = {["conditions"] = {}, ["warntime"] = BRVars.Options.warntime, ["icon"] = "Interface\\Icons\\INV_Misc_QuestionMark", ["buffs"] = {}}
        for i in BRVars.Options.conditions do
            BRVars.BuffGroups[grp].conditions[i] = BRVars.Options.conditions[i]
        end
    end
    if name ~= nil then
        BRVars.BuffGroups[grp].buffs[name] = ""
    end
    if print then BuffReminder.PrintGroup(grp) end
    BuffReminder.Update()
end

function BuffReminder.ShowHelp()
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124h ***** BuffReminder Help ***** ")
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hBuffs you want to monitor must be added to buff groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hMutually exclusive buffs should go into common groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hUntil a buff is seen by the addon it will have a '?' icon.")
    
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hGroup commands:")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group <groupname> add <buffname>")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Adds a buff to a group. If the group doesn't exist it will be created.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group <groupname> remove")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Removes the buff group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group <groupname> disable")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Prevents the group's icon from being displayed when one of it's buffs are missing.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group <groupname> enable")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Allows the group's icon to be displayed when one of it's buffs are missing.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group <number>")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Sets the early warning timer for the group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group [dead|instance|party|raid|resting|taxi]")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Toggles the given conditional for the group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br group")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    Prints a listing of your buff groups.")
    
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hBuff commands:")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br buff <buffname> remove")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    removes a buff from being monitored.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br buff <buffname>")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    prints the group info of the group a buff belongs to.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h  /br buff")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h    prints a list of your watched buffs.")
    
    DEFAULT_CHAT_FRAME:AddMessage("\124cfff4f9a7\124hGeneral options:")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br alpha <number> \124cffabb7ff\- changes the icon transparency (min 0.0, max 1.0).")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br config \124cffabb7ff\- opens the configuration dialog.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br [lock|unlock] \124cffabb7ff\- locks or unlocks the icon frame for user placement.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br NUKE \124cffabb7ff\- clears all of your settings.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br reseticons \124cffabb7ff\- clears the icon cache.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br size <number> \124cffabb7ff\- changes the icon size (min 10, max 400).")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br sound [sound name]\124cffabb7ff\- sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br time <number> \124cffabb7ff\- sets the default early warning time setting for new buff groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h ***** End of BuffReminder Help *****\124h\124r")
end
-- end slash command functions --------------------------------------------------------------
SLASH_BuffReminder1 = "/br"
SLASH_BuffReminder2 = "/buffreminder"
function SlashCmdList.BuffReminder(msg)
    local handled = false
    local args, largs, argc = getArgs(msg)
    
    if argc == 0 or largs[1] == "help" then
        BuffReminder.ShowHelp()
        return
    end
    -- group command and subcommands
    if largs[1] == "group" then
        if argc == 1 then
            BuffReminder.PrintAllGroups()
        else
            if largs[3] == "add" then
                BuffReminder.AddBuffToGroup(args[2], args[4], true)
            else
                if not BuffReminder.GroupExists(args[2]) then return end
                if argc >= 3 then
                    if largs[3] == "disable" then
                        BRVars.BuffGroups[args[2]].conditions.always = true
                    elseif largs[3] == "enable" then
                        BRVars.BuffGroups[args[2]].conditions.always = false
                    elseif BRVars.BuffGroups[args[2]].conditions[args[3]] ~= nil then
                        BRVars.BuffGroups[args[2]].conditions[args[3]] = not BRVars.BuffGroups[args[2]].conditions[args[3]]
                    elseif largs[3] == "remove" then
                        BRVars.BuffGroups[args[2]] = nil
                    else
                        local n = toNum(args[3])
                        if n ~= nil then
                            BRVars.BuffGroups[args[2]].warntime = n
                        end
                    end
                end
            end
            BuffReminder.PrintGroup(args[2])
        end
        handled = true
    -- buff command and subcommands
    elseif largs[1] == "buff" then
        if argc == 1 then
            BuffReminder.PrintBuffs()
        elseif argc == 2 then
            local g = BuffReminder.FindBuffGroup(args[2])
            if g == nil then
                DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124hBuff " .. args[2] .. " does not exist in any buff groups.")
            else
                BuffReminder.PrintGroup(g)
            end
        elseif largs[3] == "remove" then
            for i in BRVars.BuffGroups do
                BRVars.BuffGroups[i].buffs[args[2]] = nil
            end
            DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124hRemoved " .. args[2] .. " from all buff groups.")
        end
        handled = true
    else
        if largs[1] == "unlock" then
            BuffReminderFrame:EnableMouse(true)
            brtexture:SetTexture("Interface\\AddOns\\BuffReminder\\Media\\cross")
            handled = true
        elseif largs[1] == "lock" then
            BuffReminderFrame:EnableMouse(false)
            brtexture:SetTexture(nil)
            handled = true
        elseif args[1] == "NUKE" then
            BRVars.BuffGroups = {}
            BRVars.Options = BuffReminder.DefaultOptions
            handled = true
        elseif largs[1] == "sound" then
            if argc == 1 then
                BRVars.Options.warnsound = nil
            else
                BRVars.Options.warnsound = args[2]
                PlaySound(tostring(BRVars.Options.warnsound), "master")
            end
            handled = true
        elseif largs[1] == "size" then
            local n = toNum(args[2])
            if n ~= nil and (n >= 10 and n <= 400) then
                BRVars.Options.size = n
                handled = true
            end
        elseif largs[1] == "alpha" then
            local n = toNum(args[2])
            if n ~= nil and (n >= 0 and n <= 1.0) then
                BRVars.Options.alpha = n
                handled = true
            end
        elseif largs[1] == "time" then
            local n = toNum(args[2])
            if n ~= nil then
                BRVars.Options.warntime = n
                handled = true
            end
        elseif largs[1] == "reseticons" then
            BuffReminder.ClearIcons()
        elseif largs[1] == "config" then
            BrGroupsConfigFrame:Show()
        end
    end
    
    BuffReminder.Update()
    
    if not handled then
        DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124hBuffReminder command error. Try /br help.")
    end
end

--------------------------------------------------------------------------------------------------
function BuffReminder_OnLoad()
    this:RegisterForDrag("LeftButton")
    this:EnableMouse(false)
    -- this:RegisterEvent("PLAYER_ALIVE")
    this:RegisterEvent("PLAYER_DEAD")
    this:RegisterEvent("PLAYER_UNGHOST")
    this:RegisterEvent("PLAYER_AURAS_CHANGED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("UNIT_FLAGS")
    this:RegisterEvent("PLAYER_UPDATE_RESTING")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("PARTY_MEMBERS_CHANGED")
    this:RegisterEvent("RAID_ROSTER_UPDATE")
    this:RegisterEvent("UNIT_INVENTORY_CHANGED")
    this:RegisterEvent("PLAYER_REGEN_ENABLED")
    this:RegisterEvent("PLAYER_REGEN_DISABLED")
    this:RegisterEvent("ADDON_LOADED")
    -- this:RegisterAllEvents()
    -- tooltip frame for getting spell name
    lbrTooltipFrame = CreateFrame('GameTooltip', 'BrTooltip', UIParent, 'GameTooltipTemplate')
    lbrTooltipFrame:SetOwner(UIParent, 'ANCHOR_NONE')
    
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("BuffReminder AddOn loaded. Type '/br help' for config commands.")
    end
    UIErrorsFrame:AddMessage("BuffReminder AddOn loaded", 1.0, 1.0, 1.0, 1.0, UIERRORS_HOLD_TIME)
end
--------------------------------------------------------------------------------------------------
function BuffReminder_OnUpdate(elapsed)
    BuffReminder.update_time = BuffReminder.update_time + elapsed
    if BuffReminder.update_time >= 0.5 then
        BuffReminder.update_time = 0
        local resChanged = BuffReminder.GetScriptResults()
        local buffsChanged = BuffReminder.GetBuffs()
        local enchantsChanged = BuffReminder.GetEnchants()
        if resChanged or buffsChanged or enchantsChanged then
            BuffReminder.Update()
        end
    end
end

function BuffReminder.Update()
    if BuffReminder.hide_all then return end
    BuffReminder.GetWatchedBuffs()
    BuffReminder.GetMissinGroups()
    BuffReminder.MakeIcons()
end

function BuffReminder_OnEvent(event, arg1)
    if event == "UNIT_FLAGS" and arg1 == "player" then
        if UnitOnTaxi("player") == 1 then
            BuffReminder.player_status.taxi = true
        else
            BuffReminder.player_status.taxi = false
        end
    -- elseif event == "PLAYER_AURAS_CHANGED" then
    --     BuffReminder.Update()
    elseif event == "PARTY_MEMBERS_CHANGED" then
        BuffReminder.player_status.party = (GetNumPartyMembers() > 0)
    elseif event == "RAID_ROSTER_UPDATE" then
        BuffReminder.player_status.raid = (GetNumRaidMembers() > 0)
    elseif event == "PLAYER_DEAD" then
        BuffReminder.player_status.dead = true
    elseif event == "PLAYER_UNGHOST" then
        BuffReminder.player_status.dead = false
    elseif event == "PLAYER_UPDATE_RESTING" then
        BuffReminder.player_status.resting = (IsResting() == 1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        BuffReminder.player_status.combat = false
    elseif event == "PLAYER_REGEN_DISABLED" then
        BuffReminder.player_status.combat = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        BuffReminder.player_status.resting = (IsResting() == 1)
        BuffReminder.player_status.dead = (UnitIsDeadOrGhost("player") == 1)
        BuffReminder.player_status.taxi = (UnitOnTaxi("player") == 1)
        BuffReminder.player_status.party = (GetNumPartyMembers() > 0)
        BuffReminder.player_status.raid = (GetNumRaidMembers() > 0)
        BuffReminder.player_status.combat = false
        local isInstance, instanceType = (IsInInstance() == 1)
        BuffReminder.player_status.instance = isInstance
    elseif event == "ADDON_LOADED" then
        if arg1 == "BuffReminder" then
            if BRVars.Options.version == nil or BRVars.Options.version ~= BuffReminder.DefaultOptions.version then
                BRVars.Options = BuffReminder.DefaultOptions
            else
                BuffReminder.SanityCheck()
            end
            BuffReminderFrame:SetWidth(BRVars.Options.size)
            BuffReminderFrame:SetHeight(BRVars.Options.size)
            for k, v in pairs(BRVars.BuffGroups) do
                if v.script ~= "" then
                    BuffReminder.scripts[k] = loadstring(v.script)
                end
                BuffReminder.script_res[k] = false
            end
        end
    end
    BuffReminder.Update() -- force icon update
end
--------------------------------------------------------------------------------------------------
local function printOptions(opts)
    for k, v in pairs(opts) do
        if type(v) ~= "table" then
            DEFAULT_CHAT_FRAME:AddMessage(k .. " = " .. v)
        else
            DEFAULT_CHAT_FRAME:AddMessage(k .. " = ")
            for k2, v2 in pairs(v) do
                DEFAULT_CHAT_FRAME:AddMessage("   " .. k2 .. " = " .. tostring(v2))
            end
        end
    end
end

-- copy missing or mistyped options from defaults
function BuffReminder.CopyOptions(cpy)
    for k1, v1 in pairs(BuffReminder.DefaultOptions) do
        if type(v1) ~= "table" then
            if cpy[k1] == nil or type(cpy[k1]) ~= type(v1) then
                cpy[k1] = v1
            end
        else
            if type(cpy[k1]) ~= table then cpy[k1] = {} end
            for k2, v2 in pairs(v1) do
                if cpy[k1][k2] == nil or type(cpy[k1][k2]) ~= type(v2) then
                    cpy[k1][k2] = v2
                end
            end
        end
    end
end

-- remove unused options
function BuffReminder.CleanOptions(opts)
    for k1, v1 in pairs(opts) do
        if BuffReminder.DefaultOptions[k1] == nil then
            opts[k1] = nil
        elseif type(v1) == "table" then
            for k2, v2 in pairs(v1) do
                if BuffReminder.DefaultOptions[k1][k2] == nil then opts[k1][k2] = nil end
            end
        end
    end
end

function BuffReminder.SanityCheck()
    BuffReminder.CopyOptions(BRVars.Options)
    BuffReminder.CleanOptions(BRVars.Options)
    for i in BRVars.BuffGroups do
        if BRVars.BuffGroups[i].conditions == nil then BRVars.BuffGroups[i].conditions = {} end
        for j in BuffReminder.DefaultOptions.conditions do
            if BRVars.BuffGroups[i].conditions[j] == nil then BRVars.BuffGroups[i].conditions[j] = BuffReminder.DefaultOptions.conditions[j] end
        end
        if BRVars.BuffGroups[i].script == nil then BRVars.BuffGroups[i].script = "" end
        -- fixup old config for new buff/icon key/value
        for j in BRVars.BuffGroups[i].buffs do
            if type(BRVars.BuffGroups[i].buffs[j]) == "table" then
                BRVars.BuffGroups[i].buffs[j] = ""
            end
        end
    end
    BRVars.Options.version = BuffReminder.DefaultOptions.version
end
