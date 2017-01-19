brBuffGroups = {}
brOptions = {}
brDefaultOptions = {
    ["warntime"] = 60,
    ["warnsound"] = nil,
    ["disabled"] = false,
    ["size"] = 30
}

local lbrLastBuffList = {}
local lbrWarnIconFrames = {}
local lbrUpdateTime = 0
local lbrFirstRun = true
local lbrButtonSpc = 2
local lbrNameCache = {}

--------------------------------------------------------------------------------------------------
function BuffReminder_OnLoad(Frame)
    
    if brOptions.warntime == nil then brOptions = brDefaultOptions end
    this:RegisterForDrag("LeftButton")
    this:EnableMouse(false)
    
    -- tooltip frame for getting spell name
    lbrTooltipFrame = CreateFrame('GameTooltip', 'BrTooltip', UIParent, 'GameTooltipTemplate')
    lbrTooltipFrame:SetOwner(UIParent, 'ANCHOR_NONE')
    
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("BuffReminder AddOn loaded. Type '/br help' for config commands.")
        DEFAULT_CHAT_FRAME:AddMessage("BuffReminder AddOn loaded")
    end
    UIErrorsFrame:AddMessage("BuffReminder AddOn loaded", 1.0, 1.0, 1.0, 1.0, UIERRORS_HOLD_TIME)

end

function BuffReminder_OnUpdate(self)
    if GetTime() - lbrUpdateTime >= 1 then
        if brOptions.disabled then return end
        if BrChkBuffsExist() then
            BrClearIcons()
            if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
            
            for i in brBuffGroups do
                if brBuffGroups[i].show and brBuffGroups[i].enabled then
                    BrMakeIcon(brBuffGroups[i].icon)
                end
            end
            BrShowIcons()
        end
        lbrUpdateTime = GetTime()
    end
end
--------------------------------------------------------------------------------------------------
function GetPlayerBuffName(n)
    MyScanningTooltip:ClearLines()
    MyScanningTooltip:SetUnitBuff('player', n + 1)
    return MyScanningTooltipTextLeft1:GetText()
end


function BrTest()
    local list = BrGetPlayerBuffs()
    for i in list do
        DEFAULT_CHAT_FRAME:AddMessage(list[i].name)
    end
end


function BrGetPlayerBuffs()
    local blist = {}
    for i = 0, 15 do
        local buffIndex, untilCancelled = GetPlayerBuff(i, "HELPFUL")
        if buffIndex == -1 then break end
        local tex = GetPlayerBuffTexture(i)
        local name = GetPlayerBuffName(i)
        local time = GetPlayerBuffTimeLeft(i)
        blist[i] = {["icon"] = tex, ["name"] = name, ["time"] = time}
        
    end
    return blist
end

function BrChkBuffsExist()
    local iconChanged = false
    blist = BrGetPlayerBuffs()
    for i in brBuffGroups do
        local shown = brBuffGroups[i].show -- save previous state for sound logic
        brBuffGroups[i].show = true
        for j in blist do
            if brBuffGroups[i].buffs[blist[j].name] ~= nil then
                brBuffGroups[i].icon = blist[j].icon
                if blist[j].time > brOptions.warntime then
                    brBuffGroups[i].show = false
                    if shown then iconChanged = true end
                    break
                end
            end
        end
        if brBuffGroups[i].show and not shown then
            if brOptions.warnsound ~= nil then PlaySound(tostring(brOptions.warnsound), "master") end
            iconChanged = true
        end
    end
    return iconChanged or lbrFirstRun
end

function BrMakeIcon(icon)
    lbrWarnIconFrames[icon] = CreateFrame("Frame", nil, this)
    lbrWarnIconFrames[icon]:SetFrameStrata("BACKGROUND")
    lbrWarnIconFrames[icon]:SetWidth(brOptions.size)
    lbrWarnIconFrames[icon]:SetHeight(brOptions.size)
    local tex = lbrWarnIconFrames[icon]:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(icon)
    tex:SetAllPoints(lbrWarnIconFrames[icon])
    lbrWarnIconFrames[icon].texture = tex
end

function BrClearIcons()
    for i in lbrWarnIconFrames do
        lbrWarnIconFrames[i]:Hide()
    end
    lbrWarnIconFrames = {}
end

function BrShowIcons()
    local pitch = brOptions.size + lbrButtonSpc * 2
    local c = (pitch * (tablelength(lbrWarnIconFrames) - 1)) / 2
    for i in lbrWarnIconFrames do
        lbrWarnIconFrames[i]:SetPoint("CENTER", c, 0)
        lbrWarnIconFrames[i]:Show()
        c = c - pitch
    end
end

function BrListGroups()
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h** buff groups **")
    local n = 1
    for i in brBuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h" .. i)
        local t = brBuffGroups[i].buffs
        for j in t do
            DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h  [" .. n .. "] " .. t[j].name)
            n = n + 1
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h** end of buff groups **")
end

function BrGetArgs(m)
    
    local _, count = string.gsub(m, [["]], "")
    if math.mod(count, 2) ~= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Unfinished quote in command.")
        return nil, 0
    end
    
    
    for i in string.gfind(m, '(".-")') do
        m = string.gsub(m, i, string.gsub(string.gsub(i, "%s", "%%%%space%%%%"), '"', ""))
    end
    
    local args = {}
    local r
    local argc = 0
    for v in string.gfind(m, "(%S+)") do
        r, _ = string.gsub(v, "%%space%%", " ")
        table.insert(args, r)
        argc = argc + 1
    end
    return args, argc
end

function BrAddBuffToGroup(name, grp)
    if brBuffGroups[grp] == nil then
        brBuffGroups[grp] = {["icon"] = "Interface\\Icons\\INV_Misc_QuestionMark", ["enabled"] = true, ["warntime"] = brOptions.warntime, ["show"] = false, ["buffs"] = {}}
    end
    brBuffGroups[grp].buffs[name] = {}
    DEFAULT_CHAT_FRAME:AddMessage("Added " .. name .. " to ''" .. grp .. "'.")
end

function BrShowHelp()
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h ***** BuffReminder Help ***** ")
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124hBuffs you want to monitor must be added to buff groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124hMutually exclusive buffs should go into common groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br add <buff> <group> \124cff00ff00\- adds a buff to a group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br disable <group> \124cff00ff00\- temporarily disable a buff group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br enable <group> \124cff00ff00\- enable a previously disabled group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br list \124cff00ff00\- shows your configured groups and watched buffs.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br [lock|unlock] \124cff00ff00\- locks or unlocks the icon frame for user placement.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br NUKE \124cff00ff00\- clears all of your groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br remove buff <buff> \124cff00ff00\- removes a buff from being watched.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br remove group <group> \124cff00ff00\- removes a buff group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124h/br sound [sound name]\124cff00ff00\- sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning")
    DEFAULT_CHAT_FRAME:AddMessage("\124cff00ff00\124h ***** End of BuffReminder Help *****\124h\124r")
end

SLASH_BuffReminder1 = "/br" -- we add the slash commands
function SlashCmdList.BuffReminder(msg, editbox)-- we put the slash commands to work
    local handled = false
    local args, argc = BrGetArgs(msg)
    
    if argc == 1 then
        if args[1] == "test" then
            BrTest()
            handled = true
        elseif string.lower(args[1]) == "unlock" then
            BuffReminderFrame:EnableMouse(true)
            brtexture:SetTexture("Interface\\AddOns\\BuffReminder\\Media\\cross")
            handled = true
        elseif string.lower(args[1]) == "lock" then
            BuffReminderFrame:EnableMouse(false)
            brtexture:SetTexture(nil)
            handled = true
        elseif args[1] == "NUKE" then
            brBuffGroups = {}
            brOptions = brDefaultOptions
            handled = true
        elseif string.lower(args[1]) == "sound" then
            brOptions.warnsound = nil
            handled = true
        elseif string.lower(args[1]) == "list" then
            BrListGroups()
            handled = true
        elseif string.lower(args[1]) == "help" then
            BrShowHelp()
            handled = true
        end -- argc == 1
    elseif argc == 2 then
        if string.lower(args[1]) == "disable" then
            if brBuffGroups[args[2]] ~= nil then
                brBuffGroups[args[2]].enabled = false
                handled = true
            end
        elseif string.lower(args[1]) == "enable" then
            if brBuffGroups[args[2]] ~= nil then
                brBuffGroups[args[2]].enabled = true
                handled = true
            end
        elseif string.lower(args[1]) == "sound" then
            brOptions.warnsound = args[2]
            handled = true
        elseif string.lower(args[1]) == "size" then
            local n = brtonum(args[2])
            if n ~= nil and (n >= 10 and n <= 100) then
                brOptions.size = n
                handled = true
            end
        elseif string.lower(args[1]) == "time" then
            local n = brtonum(args[2])
            if n ~= nil then
                brOptions.warntime = n
                handled = true
            end
        end -- argc == 2
    elseif argc == 3 then
        if string.lower(args[1]) == "add" then
            --            local n = brtonum(args[2])
            --            if n ~= nil then
            BrAddBuffToGroup(args[2], args[3])
            handled = true
        --            end
        elseif string.lower(args[1]) == "remove" then
            if string.lower(args[2]) == "group" then
                brBuffGroups[args[3]] = nil
                handled = true
            elseif string.lower(args[2] == "buff") then
                for i in brBuffGroups do
                    brBuffGroups[i].buffs[args[3]] = nil
                end
                handled = true
            end
        end -- argc == 3
    end
    
    if not handled then
        DEFAULT_CHAT_FRAME:AddMessage("\124cffffff00\124hBuffReminder command error. Try /br help.")
    end
end

-- util functions
function tablelength(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function brtonum(n)
    local n = tonumber(n)
    if n == nil then DEFAULT_CHAT_FRAME:AddMessage("Invalid number given.") end
    return n
end
