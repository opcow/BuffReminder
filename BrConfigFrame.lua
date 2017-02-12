-- Author      : mcrane
-- Create Date : 1/6/2017 7:45:06 AM
local curGroupSel

function BuffReminder.GroupsConfigFrame_OnShow()
    BuffReminder.CheckSetState(DefConditionsAlwaysCheck, brOptions.conditions["always"])
    BuffReminder.CheckSetState(DefConditionsRestingCheck, brOptions.conditions["resting"])
    BuffReminder.CheckSetState(DefConditionsTaxiCheck, brOptions.conditions["taxi"])
    BuffReminder.CheckSetState(DefConditionsDeadCheck, brOptions.conditions["dead"])
    BuffReminder.CheckSetState(DefConditionsPartyCheck, brOptions.conditions["party"])
    BuffReminder.CheckSetState(DefConditionsRaidCheck, brOptions.conditions["raid"])
    BuffReminder.CheckSetState(DefConditionsInstanceCheck, brOptions.conditions["instance"])
    if brOptions.warntime == nil then
        BrDefTimeEdit:SetText(brDefaultOptions.warntime)
    else
        BrDefTimeEdit:SetText(brOptions.warntime)
    end
    if brOptions.warncharges == nil then
        BrChargesEdit:SetText(brDefaultOptions.warncharges)
    else
        BrChargesEdit:SetText(brOptions.warncharges)
    end
    if brOptions.warnsound ~= nil then
        BrSoundEdit:SetText(brOptions.warnsound)
    end
end

--- Group Section ---
function BuffReminder.GroupCfg_OnLoad()
    BRConfigLayoutAddGroupBtn:SetScript("OnClick", BuffReminder.AddGroupClicked)
    BRConfigLayoutAddBuffBtn:SetScript("OnClick", BuffReminder.AddBuffClicked)
end

function BuffReminder.AddGroupClicked()
    local txt = BRConfigLayoutGroupEdit:GetText()
    if txt ~= nil and txt ~= "" then
        BuffReminder.AddBuffToGroup(txt, nil)
        BRConfigLayoutGroupEdit:SetText("")
        BRConfigLayoutBuffEdit:SetText("")
        BuffReminder.DelBuffDropInit(txt)
        BuffReminder.GetSelected(txt)
        curGroupSel = txt
        BuffReminder.Update()
    end
end

function BuffReminder.AddBuffClicked()
    local txt = BRConfigLayoutBuffEdit:GetText()
    if txt ~= nil and txt ~= "" and curGroupSel ~= nil then
        BuffReminder.AddBuffToGroup(curGroupSel, txt)
        BRConfigLayoutBuffEdit:SetText("")
    end
end

function BuffReminder.SelGroupDropInit()
    local info = {}
    for i in brBuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, BuffReminder.SelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function BuffReminder.DelGroupDropInit()
    local info = {}
    for i in brBuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, BuffReminder.DelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function BuffReminder.DelBuffDropInit()
    local info = {}
    if brBuffGroups[curGroupSel] ~= nil then
        for i in brBuffGroups[curGroupSel].buffs do
            info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, false, false, i, BuffReminder.DelBuffDrop_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end
end

function BuffReminder.SelGroupDrop_OnClick(arg1)
    curGroupSel = arg1
    if brBuffGroups[arg1] ~= nil then
        BuffReminder.GetSelected(arg1)
        BuffReminder.DelBuffDropInit()
    else
        BuffReminder.DisableChecks()
    end
end

function BuffReminder.DelGroupDrop_OnClick(arg1)
    brBuffGroups[arg1] = nil
    BRConfigLayoutHeaderString:SetText("Buff Groups")
    BuffReminder.DisableChecks()
    curGroupSel = nil
    BuffReminder.Update()
end

function BuffReminder.DelBuffDrop_OnClick(arg1)
    if curGroupSel ~= nil then
        brBuffGroups[curGroupSel].buffs[arg1] = nil
    end
    BuffReminder.DelBuffDropInit()
    BuffReminder.Update()
end

function BuffReminder.GetSelected(group)
    BRConfigLayoutHeaderString:SetText(group)
    BuffReminder.EnableChecks()
    BuffReminder.CheckSetState(GConditionsAlwaysCheck, brBuffGroups[group].conditions["always"])
    BuffReminder.CheckSetState(GConditionsRestingCheck, brBuffGroups[group].conditions["resting"])
    BuffReminder.CheckSetState(GConditionsTaxiCheck, brBuffGroups[group].conditions["taxi"])
    BuffReminder.CheckSetState(GConditionsDeadCheck, brBuffGroups[group].conditions["dead"])
    BuffReminder.CheckSetState(GConditionsPartyCheck, brBuffGroups[group].conditions["party"])
    BuffReminder.CheckSetState(GConditionsRaidCheck, brBuffGroups[group].conditions["raid"])
    BuffReminder.CheckSetState(GConditionsInstanceCheck, brBuffGroups[group].conditions["instance"])
    BrTimeEdit:SetText(brBuffGroups[group].warntime)
end

function BuffReminder.DisableChecks()
    curGroupSel = nil
    GConditionsAlwaysCheck:Disable()
    GConditionsRestingCheck:Disable()
    GConditionsTaxiCheck:Disable()
    GConditionsDeadCheck:Disable()
    GConditionsPartyCheck:Disable()
    GConditionsRaidCheck:Disable()
    GConditionsInstanceCheck:Disable()
end

function BuffReminder.EnableChecks()
    GConditionsAlwaysCheck:Enable()
    GConditionsRestingCheck:Enable()
    GConditionsTaxiCheck:Enable()
    GConditionsDeadCheck:Enable()
    GConditionsPartyCheck:Enable()
    GConditionsRaidCheck:Enable()
    GConditionsInstanceCheck:Enable()
end

function BuffReminder.SetGroupWarnTime(t)
    if t ~= nil and t ~= "" then
        brBuffGroups[curGroupSel].warntime = tonumber(t)
    end
end

function BuffReminder.SetDefaultWarnTime(t)
    if t ~= nil and t ~= "" then
        brOptions.warntime = tonumber(t)
    end
end

function BuffReminder.SetWarnCharges(t)
    if t ~= nil and t ~= "" then
        brOptions.warncharges = tonumber(t)
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
    brBuffGroups[curGroupSel].conditions[string.lower(this:GetText())] = this.state
    BuffReminder.Update()
end

function BuffReminder.DefCheck_Clicked()
    if this.state == 2 then
        BuffReminder.CheckSetState(this, 0)
    else
        BuffReminder.CheckSetState(this, this.state + 1)
    end
    string.lower(this:GetText())
    brOptions.conditions[string.lower(this:GetText())] = this.state
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
        if BRConfig:IsShown() then
            BRConfig:Hide();
        else
            BRConfig:Show();
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
