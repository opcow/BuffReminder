brBuffGroups = {}
brOptions = {}
brDefaultOptions = {
    ["conditions"] = {
        ["resting"] = true,
        ["taxi"] = true,
        ["dead"] = true,
        ["instance"] = false,
        ["group"] = false,
    },
    ["disabled"] = false,
    ["warnsound"] = nil,
    ["size"] = 30,
    ["warntime"] = 60,
    ["alpha"] = 1.0,
}

local lbrLastBuffList = {}
local lbrWarnIconFrames = {}
local lbrUpdateTime = 0
local lbrForceUpdate = true
local lbrButtonSpc = 2
local lbrPlayerDead = false
local lbrPlayerOnTaxi = false
local lbrPlayerResting = false
local lbrPlayerInInstance = false
--------------------------------------------------------------------------------------------------
function BuffReminder_OnLoad(Frame)
    
    if brOptions == nil then brOptions = brDefaultOptions end
    this:RegisterForDrag("LeftButton")
    this:EnableMouse(false)
    -- this:RegisterEvent("PLAYER_ALIVE")
    this:RegisterEvent("PLAYER_DEAD")
    this:RegisterEvent("PLAYER_UNGHOST")
    this:RegisterEvent("PLAYER_AURAS_CHANGED")
    -- this:RegisterEvent("PLAYER_CONTROL_LOST")
    -- this:RegisterEvent("PLAYER_CONTROL_GAINED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("UNIT_FLAGS")
    this:RegisterEvent("PLAYER_UPDATE_RESTING")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    --    this:RegisterAllEvents()
    -- tooltip frame for getting spell name
    lbrTooltipFrame = CreateFrame('GameTooltip', 'BrTooltip', UIParent, 'GameTooltipTemplate')
    lbrTooltipFrame:SetOwner(UIParent, 'ANCHOR_NONE')
    
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage("BuffReminder AddOn loaded. Type '/br help' for config commands.")
    end
    UIErrorsFrame:AddMessage("BuffReminder AddOn loaded", 1.0, 1.0, 1.0, 1.0, UIERRORS_HOLD_TIME)

end

function BuffReminder_OnUpdate(self)
    if GetTime() - lbrUpdateTime >= 1 then
        if brOptions.disabled then return end
        if lbrForceUpdate then
            BrChkBuffsExist()
            lbrForceUpdate = false
            BrDrawIcons()
        elseif BrChkBuffsExist() then
            BrDrawIcons()
        end
        lbrUpdateTime = GetTime()
    end
end

function BuffReminder_OnEvent(event, arg1)
    if event == "UNIT_FLAGS" and arg1 == "player" then
        if UnitOnTaxi("player") == 1 then
            lbrPlayerOnTaxi = true
        else
            lbrPlayerOnTaxi = false
        end
    elseif event == "PLAYER_DEAD" then
        lbrPlayerDead = true
    elseif event == "PLAYER_UNGHOST" then
        lbrPlayerDead = false
    elseif event == "PLAYER_UPDATE_RESTING" then
        lbrPlayerResting = IsResting()
    elseif event == "PLAYER_ENTERING_WORLD" then
        lbrPlayerResting = IsResting()
        lbrPlayerDead = UnitIsDeadOrGhost("player")
        lbrPlayerOnTaxi = UnitOnTaxi("player") == 1
        local isInstance, instanceType = IsInInstance()
        lbrPlayerInInstance = isInstance
    end
    
    
    lbrForceUpdate = true -- force icon update
end
--------------------------------------------------------------------------------------------------
function BrClearIcons()
    for i in lbrWarnIconFrames do
        lbrWarnIconFrames[i]:Hide()
    end
    lbrWarnIconFrames = {}
end

function BrDrawIcons()
    BrClearIcons()

    --if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    for i in brBuffGroups do
        if (brBuffGroups[i].show and brBuffGroups[i].enabled) and not 
        (lbrPlayerResting and brBuffGroups[i].conditions.resting) and not
        (lbrPlayerInInstance and brBuffGroups[i].conditions.instance) and not
        (lbrPlayerOnTaxi and brBuffGroups[i].conditions.taxi) then
            BrMakeIcon(brBuffGroups[i].icon)
        end
    end
    BrShowIcons()
end

function GetPlayerBuffName(n)
    TooltipScanner:ClearLines()
    TooltipScanner:SetPlayerBuff(n)
    return TooltipScannerTextLeft1:GetText()
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
                if blist[j].time > brBuffGroups[i].warntime then
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
    return iconChanged
end

function BrMakeIcon(icon)
    lbrWarnIconFrames[icon] = CreateFrame("Frame", nil, this)
    lbrWarnIconFrames[icon]:SetFrameStrata("BACKGROUND")
    lbrWarnIconFrames[icon]:SetWidth(brOptions.size)
    lbrWarnIconFrames[icon]:SetHeight(brOptions.size)
    local tex = lbrWarnIconFrames[icon]:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(icon)
    -- if lbrPlayerDead or lbrPlayerOnTaxi or lbrPlayerResting then
    --     tex:SetAlpha(1.0)
    -- else
        tex:SetAlpha(brOptions.alpha)
    -- end
    tex:SetAllPoints(lbrWarnIconFrames[icon])
    lbrWarnIconFrames[icon].texture = tex
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
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h** buff groups **")
    for i in brBuffGroups do
        DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h" .. i)
        local t = brBuffGroups[i].buffs
        for j in t do
            --            DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h  [" .. n .. "] " .. t[j].name)
            end
    end
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h** end of buff groups **")
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
        brBuffGroups[grp] = {["conditions"] = brOptions.conditions, ["warntime"] = brOptions.warntime, ["icon"] = "Interface\\Icons\\INV_Misc_QuestionMark", ["enabled"] = true, ["show"] = false, ["buffs"] = {}}
    end
    brBuffGroups[grp].buffs[name] = {}
    DEFAULT_CHAT_FRAME:AddMessage('Added "' .. name .. '" to "' .. grp .. '."')
end

function BrShowHelp()
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h ***** BuffReminder Help ***** ")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124hBuffs you want to monitor must be added to buff groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124hMutually exclusive buffs should go into common groups.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br add <buff> <group> \124cffafe7e9\- adds a buff to a group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br alpha <number> \124cffafe7e9\- change the icon transparency (min 0.0, max 1.0).")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br disable <group> \124cffafe7e9\- temporarily disable a buff group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br enable <group> \124cffafe7e9\- enable a previously disabled group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br list \124cffafe7e9\- shows your configured groups and watched buffs.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br [lock|unlock] \124cffafe7e9\- locks or unlocks the icon frame for user placement.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br NUKE \124cffafe7e9\- clears all of your settings.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br remove buff <buff> \124cffafe7e9\- removes a buff from being watched.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br remove group <group> \124cffafe7e9\- removes a buff group.")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br size <number> \124cffafe7e9\- change the icon size (min 10, max 400).")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124h/br sound [sound name]\124cffafe7e9\- sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning")
    DEFAULT_CHAT_FRAME:AddMessage("\124cffafe7e9\124h ***** End of BuffReminder Help *****\124h\124r")
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
            PlaySound(tostring(brOptions.warnsound), "master")
            handled = true
        elseif string.lower(args[1]) == "size" then
            local n = brtonum(args[2])
            if n ~= nil and (n >= 10 and n <= 400) then
                brOptions.size = n
                handled = true
            end
        elseif string.lower(args[1]) == "alpha" then
            local n = brtonum(args[2])
            if n ~= nil and (n >= 0 and n <= 1.0) then
                brOptions.alpha = n
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
        elseif string.lower(args[1]) == "gtime" then
            if brBuffGroups[args[2]] == nil then
                DEFAULT_CHAT_FRAME:AddMessage('Group "' .. tostring(args[2]) .. '" does not exist.')
                return
            end
            local n = brtonum(args[3])
            if n ~= nil then
                brBuffGroups[args[2]].warntime = n
                handled = true
            end
        end -- argc == 3
    end
    
    lbrForceUpdate = true
    
    if not handled then
        DEFAULT_CHAT_FRAME:AddMessage("\124cffbfb56f\124hBuffReminder command error. Try /br help.")
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
