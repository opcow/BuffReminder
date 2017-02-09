BuffReminder = {
    ["hide_all"] = false,
    ["update"] = true,
    ["button_space"] = 2,
    ["current_buffs"] = {},
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
    },
    ["update_time"] = 0
}

brBuffGroups = {}
brOptions = {}
brDefaultOptions = {
    ["version"] = "1.0",
    ["warnsound"] = nil,
    ["size"] = 30,
    ["warntime"] = 60,
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
    BuffReminder.icons[index]:SetWidth(brOptions.size)
    BuffReminder.icons[index]:SetHeight(brOptions.size)

    tex = BuffReminder.icons[index]:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(texture)
    tex:SetAlpha(brOptions.alpha)
    tex:SetAllPoints(BuffReminder.icons[index])
    BuffReminder.icons[index].texture = tex
end

function BuffReminder.MakeIcons()
    for i in BuffReminder.icons do
        BuffReminder.icons[i]:Hide()
    end
    local count = 1
    local skipIcon = false
    for i in BuffReminder.missing_groups do
        for j in BuffReminder.player_status do
            if (brBuffGroups[i].conditions.always ~= 2) and ((brBuffGroups[i].conditions.always == 1) or (BuffReminder.player_status[j] and
                (brBuffGroups[i].conditions[j] == 1)) or (not BuffReminder.player_status[j] and brBuffGroups[i].conditions[j] == 2)) then
                skipIcon = true
                break
            end
        end
        if not skipIcon then
            BuffReminder.MakeIcon(count, BuffReminder.missing_groups[i])
            count = count + 1
        end
    end
    skipIcon = false
    for i in BuffReminder.player_status do
        if (brOptions.conditions.always ~= 2) and ((brOptions.conditions.always == 1) or (BuffReminder.player_status[i] and (brOptions.conditions[i] == 1)) or (not BuffReminder.player_status[i] and brOptions.conditions[i] == 2)) then
            skipIcon = true
            break
        end
    end
    if not skipIcon then
        if brOptions.enchants.main and (not BuffReminder.enchants.main) then
            local t = GetInventoryItemTexture("player", 16)
            if t ~= nil then
                BuffReminder.MakeIcon(count, t)
                count = count + 1
            end
        end
        if brOptions.enchants.off and (not BuffReminder.enchants.off) then
            local t = GetInventoryItemTexture("player", 17)
            if t ~= nil then
                BuffReminder.MakeIcon(count, t)
                count = count + 1
            end
        end
    end


    local pitch = brOptions.size + BuffReminder.button_space * 2
    local c = (pitch * (tableLen(BuffReminder.icons) - 1)) / 2
    for i=(count - 1), 1, -1 do
        BuffReminder.icons[i]:SetPoint("CENTER", c, 0)
        BuffReminder.icons[i]:Show()
        c = c - pitch
    end
end

function BuffReminder.FindBuffGroup(buff)
    for i in brBuffGroups do
        if brBuffGroups[i].buffs[buff] ~= nil then
            return i
        end
    end
    return nil
end

function BuffReminder.UpdateBuffStatus(buffs)
    for i in BuffReminder.current_buffs do
        if buffs[i] == nil then -- lost a buff
            BuffReminder.update = true
            return
        end
    end
    for i in buffs do
        if BuffReminder.current_buffs[i] == nil then -- gained a buff
            BuffReminder.update = true
            return
        end
    end
end

-- creates a list of current buffs which are also watched buffs
function BuffReminder.GetBuffs()
    local current_buffs = {}
    for i = 0, 15 do
        local buffIndex, untilCancelled = GetPlayerBuff(i, "HELPFUL")
        if buffIndex == -1 then break end
        local name = BuffReminder.GetPlayerBuffName(i)
        local time = GetPlayerBuffTimeLeft(i)
        local tex = GetPlayerBuffTexture(i)
        local group = BuffReminder.FindBuffGroup(name)
        -- if the buff isn't found in the buff groups or time is low then don't add it
        if group ~= nil and time > brBuffGroups[group].warntime then
            current_buffs[name] = GetPlayerBuffTexture(i)
            brBuffGroups[group].icon = tex
        end
    end
    BuffReminder.UpdateBuffStatus(current_buffs)
    BuffReminder.current_buffs = current_buffs
end

function BuffReminder.GetMissinGroups()
    missing_groups = {}
    for i in brBuffGroups do
        missing_groups[i] = brBuffGroups[i].icon
    end
    for i in BuffReminder.watched_buffs do
        if BuffReminder.current_buffs[i] ~= nil then
            local group = BuffReminder.FindBuffGroup(i)
            missing_groups[group] = nil
        end
    end
    BuffReminder.missing_groups = missing_groups
end

function BuffReminder.GetMissinBuffs()
    BuffReminder.missing_buffs = {}
    for i in BuffReminder.watched_buffs do
        if BuffReminder.current_buffs[i] == nil then
            BuffReminder.missing_buffs[i] = BuffReminder.FindBuffGroup(i)
        end
    end
end

function BuffReminder.GetWatchedBuffs()
    BuffReminder.watched_buffs = {}
    for i in brBuffGroups do
        for j in brBuffGroups[i].buffs do
            BuffReminder.watched_buffs[j] = {}
        end
    end
end
--------------------------------------------------------------------------------

function BuffReminder.GetPlayerBuffName(n)
    TooltipScanner:ClearLines()
    TooltipScanner:SetPlayerBuff(n)
    return TooltipScannerTextLeft1:GetText()
end

local function CheckWeaponEnchants()
    local changed = false
    if (brOptions.enchants.main == true) or (brOptions.enchants.off == true) then
        local hasMainHandEnchant, mainHandExpiration, mainHandCharges, hasOffHandEnchant, offHandExpiration, offHandCharges = GetWeaponEnchantInfo();
        if (BuffReminder.enchants.main ~= hasMainHandEnchant) or (hasOffHandEnchant ~= BuffReminder.enchants.off) then
            changed = true
        end
        BuffReminder.enchants.main = (hasMainHandEnchant == 1) and (mainHandExpiration > brOptions.warntime * 1000)
        BuffReminder.enchants.off = (hasOffHandEnchant == 1) and (offHandExpiration > brOptions.warntime * 1000)
    end
    return changed
end

-- slash command functions ------------------------------------------------------------------
local function GroupExists(group)
    if brBuffGroups[group] == nil then
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup "' .. tostring(group) .. '" does not exist.')
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hYour groups are:')
        for i in brBuffGroups do
            DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124h  ' .. i)
        end
        return false
    end
    return true
end

local function FindBuff(buff)
    for i in brBuffGroups do
        if brBuffGroups[i].buffs[buff] ~= nil then return i end
    end
    return nil
end

local function PrintBuffs()
    for i in brBuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup: ' .. tostring(i))
        for j in brBuffGroups[i].buffs do
            DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  " .. j)
        end
    end
end

function BuffReminder.PrintAllGroups()
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h** buff groups **")
    for i in brBuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h   " .. i)
        local t = brBuffGroups[i].buffs
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h** end of buff groups **")
end

function BuffReminder.PrintGroup(group)
    DEFAULT_CHAT_FRAME:AddMessage('\124cffffff00\124hGroup: ' .. tostring(group))
    for i in brBuffGroups[group].buffs do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  " .. i)
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  ---")
    for i in brBuffGroups[group].conditions do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  hide condition " .. i .. ": \124cff80ff00\124h" .. tostring(brBuffGroups[group].conditions[i]))
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h  early warning time: \124cff80ff00\124h" .. tostring(brBuffGroups[group].warntime))
end

function BuffReminder.AddBuffToGroup(grp, name, print)
    if brBuffGroups[grp] == nil then
        brBuffGroups[grp] = {["conditions"] = brOptions.conditions, ["warntime"] = brOptions.warntime, ["icon"] = "Interface\\Icons\\INV_Misc_QuestionMark", ["buffs"] = {}}
    end
    if name ~= nil then
        brBuffGroups[grp].buffs[name] = {}
    end
    if print then BuffReminder.PrintGroup(grp) end
    BuffReminder.update = true
end

local function ShowHelp()
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
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br size <number> \124cffabb7ff\- changes the icon size (min 10, max 400).")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br sound [sound name]\124cffabb7ff\- sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffcbeb1c\124h/br time <number> \124cffabb7ff\- sets the default early warning time setting for new buff groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124h ***** End of BuffReminder Help *****\124h\124r")
end
-- end slash command functions --------------------------------------------------------------
SLASH_BuffReminder1 = "/br"
SLASH_BuffReminder2 = "/buffreminder"
function SlashCmdList.BuffReminder(msg)-- we put the slash commands to work
    local handled = false
    local args, largs, argc = getArgs(msg)
    
    if argc == 0 or largs[1] == "help" then
        ShowHelp()
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
                if not GroupExists(args[2]) then return end
                if argc >= 3 then
                    if largs[3] == "disable" then
                        brBuffGroups[args[2]].conditions.always = true
                    elseif largs[3] == "enable" then
                        brBuffGroups[args[2]].conditions.always = false
                    elseif brBuffGroups[args[2]].conditions[args[3]] ~= nil then
                        brBuffGroups[args[2]].conditions[args[3]] = not brBuffGroups[args[2]].conditions[args[3]]
                    elseif largs[3] == "remove" then
                        brBuffGroups[args[2]] = nil
                    else
                        local n = toNum(args[3])
                        if n ~= nil then
                            brBuffGroups[args[2]].warntime = n
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
            PrintBuffs()
        elseif argc == 2 then
            local g = FindBuff(args[2])
            if g == nil then
                DEFAULT_CHAT_FRAME:AddMessage("\124cffabb7ff\124hBuff " .. args[2] .. " does not exist in any buff groups.")
            else
                BuffReminder.PrintGroup(g)
            end
        elseif largs[3] == "remove" then
            for i in brBuffGroups do
                brBuffGroups[i].buffs[args[2]] = nil
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
            brBuffGroups = {}
            brOptions = brDefaultOptions
            handled = true
        elseif largs[1] == "sound" then
            if argc == 1 then
                brOptions.warnsound = nil
            else
                brOptions.warnsound = args[2]
                PlaySound(tostring(brOptions.warnsound), "master")
            end
            handled = true
        elseif largs[1] == "size" then
            local n = toNum(args[2])
            if n ~= nil and (n >= 10 and n <= 400) then
                brOptions.size = n
                handled = true
            end
        elseif largs[1] == "alpha" then
            local n = toNum(args[2])
            if n ~= nil and (n >= 0 and n <= 1.0) then
                brOptions.alpha = n
                handled = true
            end
        elseif largs[1] == "time" then
            local n = toNum(args[2])
            if n ~= nil then
                brOptions.warntime = n
                handled = true
            end
        elseif largs[1] == "config" then
            BrGroupsConfigFrame:Show()
        end
    end
    
    BuffReminder.update = true
    
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
    this:RegisterEvent("ADDON_LOADED")
    this:RegisterEvent("UNIT_INVENTORY_CHANGED")
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
        if BuffReminder.hide_all then return end
        BuffReminder.Update()
    end
end

function BuffReminder.Update()
    BuffReminder.GetBuffs()
    CheckWeaponEnchants()
    if BuffReminder.update then
        BuffReminder.update = false
        BuffReminder.GetWatchedBuffs()
        BuffReminder.GetMissinGroups()
        BuffReminder.MakeIcons()
    end
end

function BuffReminder_OnEvent(event, arg1)
    if event == "UNIT_FLAGS" and arg1 == "player" then
        if UnitOnTaxi("player") == 1 then
            BuffReminder.player_status.taxi = true
        else
            BuffReminder.player_status.taxi = false
        end
    -- elseif event == "PLAYER_AURAS_CHANGED" then
    --     BuffReminder.update = true
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        BuffReminder.player_status.resting = (IsResting() == 1)
        BuffReminder.player_status.dead = (UnitIsDeadOrGhost("player") == 1)
        BuffReminder.player_status.taxi = (UnitOnTaxi("player") == 1)
        BuffReminder.player_status.party = (GetNumPartyMembers() > 0)
        BuffReminder.player_status.raid = (GetNumRaidMembers() > 0)
        local isInstance, instanceType = (IsInInstance() == 1)
        BuffReminder.player_status.instance = isInstance
    elseif event == "ADDON_LOADED" then
    -- fix old config for tristate conditions or other issues
        if arg1 == "BuffReminder" then
            if brOptions == nil or brOptions.version ~= "1.0" then brOptions = brDefaultOptions end
            if brOptions.enchants == nil then
                brOptions.enchants = brDefaultOptions.enchants
           end
            BuffReminderFrame:SetWidth(brOptions.size)
            BuffReminderFrame:SetHeight(brOptions.size)
            if brOptions.version == nil then brOptions.version = "1.0" end
            if brOptions.conditions == nil then
                brOptions.conditions = brDefaultOptions.conditions
            end
            for i in brOptions.conditions do
                if brOptions.conditions[i] == false then
                    brOptions.conditions[i] = 0
                elseif brOptions.conditions[i] == true then
                    brOptions.conditions[i] = 1
                end
            end
            for i in brBuffGroups do
                DEFAULT_CHAT_FRAME:AddMessage(i)
                for j in brBuffGroups[i].conditions do
                    if brBuffGroups[i].conditions[j] == false then
                        brBuffGroups[i].conditions[j] = 0
                    elseif brBuffGroups[i].conditions[j] == true then
                        brBuffGroups[i].conditions[j] = 1
                    end
                end
            end
        end
    end
    -- fix old config
    BuffReminder.update = true -- force icon update
end
--------------------------------------------------------------------------------------------------