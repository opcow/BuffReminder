-- Author      : mcrane
-- Create Date : 1/6/2017 7:45:06 AM
function BuffReminder.GroupsConfigFrame_OnShow()
    BuffReminder.CheckSetState(DefConditionsAlwaysCheck, BRVars.Options.conditions["always"])
    BuffReminder.CheckSetState(DefConditionsRestingCheck, BRVars.Options.conditions["resting"])
    BuffReminder.CheckSetState(DefConditionsTaxiCheck, BRVars.Options.conditions["taxi"])
    BuffReminder.CheckSetState(DefConditionsDeadCheck, BRVars.Options.conditions["dead"])
    BuffReminder.CheckSetState(DefConditionsPartyCheck, BRVars.Options.conditions["party"])
    BuffReminder.CheckSetState(DefConditionsRaidCheck, BRVars.Options.conditions["raid"])
    BuffReminder.CheckSetState(DefConditionsInstanceCheck, BRVars.Options.conditions["instance"])
    if BRVars.Options.warntime == nil then
        BrDefTimeEdit:SetText(brDefaultOptions.warntime)
    else
        BrDefTimeEdit:SetText(BRVars.Options.warntime)
    end
    if BRVars.Options.warncharges == nil then
        BrChargesEdit:SetText(brDefaultOptions.warncharges)
    else
        BrChargesEdit:SetText(BRVars.Options.warncharges)
    end
    if BRVars.Options.warnsound ~= nil then
        BrSoundEdit:SetText(BRVars.Options.warnsound)
    end
end

function BuffReminder.AddGroupClicked()
    local txt = BRConfigFrameLayoutGroupEdit:GetText()
    if txt ~= nil and txt ~= "" then
        BuffReminder.AddBuffToGroup(txt, nil)
        BRConfigFrameLayoutGroupEdit:SetText("")
        BRConfigFrameLayoutGroupEdit:SetText("")
        BuffReminder.SetOptions(txt)
        BuffReminder.cur_group = txt
    end
end

function BuffReminder.AddBuffClicked()
    local txt = BRConfigFrameLayoutGroupEdit:GetText()
    if txt ~= nil and txt ~= "" and BuffReminder.cur_group ~= nil then
        BuffReminder.AddBuffToGroup(BuffReminder.cur_group, txt)
        BRConfigFrameLayoutGroupEdit:SetText("")
    end
end

function BuffReminder.SelGroupDropInit()
    local info = {}
    for i in BRVars.BuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, BuffReminder.SelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function BuffReminder.DelGroupDropInit()
    local info = {}
    for i in BRVars.BuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, BuffReminder.DelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function BuffReminder.DelBuffDropInit()
    local info = {}
    if BRVars.BuffGroups[BuffReminder.cur_group] ~= nil then
        for i in BRVars.BuffGroups[BuffReminder.cur_group].buffs do
            info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, false, false, i, BuffReminder.DelBuffDrop_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end
end

function BuffReminder.SelGroupDrop_OnClick(arg1)
    BuffReminder.cur_group = arg1
    if BRVars.BuffGroups[arg1] ~= nil then
        BuffReminder.SetOptions(arg1)
        BuffReminder.DelBuffDropInit()
    else
        BuffReminder.DisableChecks()
    end
end

function BuffReminder.DelGroupDrop_OnClick(arg1)
    BRVars.BuffGroups[arg1] = nil
    BRConfigFrameLayoutHeaderString:SetText("Buff Groups")
    BuffReminder.DisableChecks()
    BuffReminder.cur_group = nil
    BuffReminder.Update()
end

function BuffReminder.DelBuffDrop_OnClick(arg1)
    if BuffReminder.cur_group ~= nil then
        BRVars.BuffGroups[BuffReminder.cur_group].buffs[arg1] = nil
    end
    BuffReminder.DelBuffDropInit()
    BuffReminder.Update()
end

function BuffReminder.SetOptions(group)
    BRConfigFrameLayoutHeaderString:SetText(group)
    BuffReminder.CheckSetState(GConditionsAlwaysCheck, BRVars.BuffGroups[group].conditions["always"])
    BuffReminder.CheckSetState(GConditionsRestingCheck, BRVars.BuffGroups[group].conditions["resting"])
    BuffReminder.CheckSetState(GConditionsTaxiCheck, BRVars.BuffGroups[group].conditions["taxi"])
    BuffReminder.CheckSetState(GConditionsDeadCheck, BRVars.BuffGroups[group].conditions["dead"])
    BuffReminder.CheckSetState(GConditionsPartyCheck, BRVars.BuffGroups[group].conditions["party"])
    BuffReminder.CheckSetState(GConditionsRaidCheck, BRVars.BuffGroups[group].conditions["raid"])
    BuffReminder.CheckSetState(GConditionsCombatCheck, BRVars.BuffGroups[group].conditions["combat"])
    BuffReminder.CheckSetState(GConditionsInstanceCheck, BRVars.BuffGroups[group].conditions["instance"])
    BrTimeEdit:SetText(BRVars.BuffGroups[group].warntime)
    BuffReminder.EnableChecks()
end

function BuffReminder.DisableChecks()
    BuffReminder.cur_group = nil
    GConditionsAlwaysCheck:Disable()
    GConditionsRestingCheck:Disable()
    GConditionsTaxiCheck:Disable()
    GConditionsDeadCheck:Disable()
    GConditionsPartyCheck:Disable()
    GConditionsRaidCheck:Disable()
    GConditionsCombatCheck:Disable()
    GConditionsInstanceCheck:Disable()
    GConditionsScriptButton:Disable()
end

function BuffReminder.EnableChecks()
    GConditionsAlwaysCheck:Enable()
    GConditionsRestingCheck:Enable()
    GConditionsTaxiCheck:Enable()
    GConditionsDeadCheck:Enable()
    GConditionsPartyCheck:Enable()
    GConditionsRaidCheck:Enable()
    GConditionsCombatCheck:Enable()
    GConditionsInstanceCheck:Enable()
    GConditionsScriptButton:Enable()
end

function BuffReminder.SetGroupWarnTime(t)
    if t ~= nil then
        BRVars.BuffGroups[BuffReminder.cur_group].warntime = t
    end
end

function BuffReminder.SetDefaultWarnTime(t)
    if t ~= nil then
        BRVars.Options.warntime = t
    end
end

function BuffReminder.SetWarnCharges(t)
    if t ~= nil then
        BRVars.Options.warncharges = t
    end
end

-- Check Buttons --
function BuffReminder.Check_OnLoad()
    this.state = 0
    getglobal(this:GetName() .. "Text"):SetText(this:GetText())
    local cbtex = this:CreateTexture("inverted", "BACKGROUND")
    cbtex:SetTexture(1, 0, 0, 1)
    cbtex:SetAllPoints(this)
    cbtex:SetPoint("TOPLEFT", 6, -7)
    cbtex:SetPoint("BOTTOMRIGHT", -6, 8)
    this.texture = cbtex
    this.texture:SetAlpha(0)
end

function BuffReminder.Check_Clicked()
    if this.state == 2 then
        BuffReminder.CheckSetState(this, 0)
    else
        BuffReminder.CheckSetState(this, this.state + 1)
    end
    BRVars.BuffGroups[BuffReminder.cur_group].conditions[string.lower(this:GetText())] = this.state
    BuffReminder.Update()
end

function BuffReminder.DefCheck_Clicked()
    if this.state == 2 then
        BuffReminder.CheckSetState(this, 0)
    else
        BuffReminder.CheckSetState(this, this.state + 1)
    end
    string.lower(this:GetText())
    BRVars.Options.conditions[string.lower(this:GetText())] = this.state
    BuffReminder.Update()
end

function BuffReminder.CheckSetState(check, state)
    check.state = state
    if state == 0 then
        check:SetChecked(false)
        check.texture:SetAlpha(0)
    elseif state == 1 then
        check.texture:SetAlpha(0)
        check:SetChecked(true)
    else
        check.texture:SetAlpha(1)
        check:SetChecked(true)
    end
end

-- Config Button --
function BuffReminder.GroupsConfigFrame_Toggle(mouseButton)
    if IsShiftKeyDown() then
        if BuffReminderFrame:IsMouseEnabled() then
            BuffReminderFrame:EnableMouse(false)
            brtexture:SetTexture(nil)
        else
            BuffReminderFrame:EnableMouse(true)
            brtexture:SetTexture("Interface\\AddOns\\BuffReminder\\Media\\cross")
        end
    elseif mouseButton == "LeftButton" then
        if BRConfigFrame:IsShown() then
            BRConfigFrame:Hide();
        else
            BRConfigFrame:Show();
        end
    else
        BuffReminder.hide_all = not BuffReminder.hide_all
        for i in BuffReminder.icons do
            BuffReminder.icons[i]:Hide()
        end
        if BuffReminder.hide_all then
            DEFAULT_CHAT_FRAME:AddMessage("Buff reminder icons will not be shown.")
        else
            BuffReminder.Update()
            DEFAULT_CHAT_FRAME:AddMessage("Buff reminder icons will be shown.")
        end
    end
end

function BuffReminder.GroupsConfigFrame_OnEnter()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:SetText("BuffReminder")
    GameTooltip:AddLine("Left-click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to temporarily hide the icons.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock the icon frame.", 1, 1, 1)
    GameTooltip:Show()
end

function BuffReminder.GroupsConfigFrame_OnLeave()
    GameTooltip:Hide()
end
