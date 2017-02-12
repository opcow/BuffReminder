-- Author      : mcrane
-- Create Date : 1/6/2017 7:45:06 AM
local curGroupSel

function BrGroupsConfigFrame_OnShow()
    BrCheck_SetState(DefConditionsAlwaysCheck, brOptions.conditions["always"])
    BrCheck_SetState(DefConditionsRestingCheck, brOptions.conditions["resting"])
    BrCheck_SetState(DefConditionsTaxiCheck, brOptions.conditions["taxi"])
    BrCheck_SetState(DefConditionsDeadCheck, brOptions.conditions["dead"])
    BrCheck_SetState(DefConditionsPartyCheck, brOptions.conditions["party"])
    BrCheck_SetState(DefConditionsRaidCheck, brOptions.conditions["raid"])
    BrCheck_SetState(DefConditionsInstanceCheck, brOptions.conditions["instance"])
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
function BrGroupCfg_OnLoad()
    GroupLayoutAddGroupBtn:SetScript("OnClick", AddGroupClicked)
    GroupLayoutAddBuffBtn:SetScript("OnClick", AddBuffClicked)
end

function AddGroupClicked()
    local txt = GroupLayoutGroupEdit:GetText()
    if txt ~= nil and txt ~= "" then
        BuffReminder.AddBuffToGroup(txt, nil)
        GroupLayoutGroupEdit:SetText("")
        GroupLayoutBuffEdit:SetText("")
        DelBuffDropInit(txt)
        GroupLayout_GetSelected(txt)
        curGroupSel = txt
        BuffReminder.Update()
    end
end

function AddBuffClicked()
    local txt = GroupLayoutBuffEdit:GetText()
    if txt ~= nil and txt ~= "" and curGroupSel ~= nil then
        BuffReminder.AddBuffToGroup(curGroupSel, txt)
        GroupLayoutBuffEdit:SetText("")
    end
end

function SelGroupDropInit()
    local info = {}
    for i in brBuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, GroupLayoutSelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function DelGroupDropInit()
    local info = {}
    for i in brBuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, true, false, i, GroupLayoutDelGroupDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function DelBuffDropInit()
    local info = {}
    if brBuffGroups[curGroupSel] ~= nil then
        for i in brBuffGroups[curGroupSel].buffs do
            info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, false, false, i, GroupLayoutDelBuffDrop_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end
end

function GroupLayoutSelGroupDrop_OnClick(arg1)
    curGroupSel = arg1
    if brBuffGroups[arg1] ~= nil then
        GroupLayout_GetSelected(arg1)
        DelBuffDropInit()
    else
        GroupLayout_DisableChecks()
    end
end

function GroupLayoutDelGroupDrop_OnClick(arg1)
    brBuffGroups[arg1] = nil
    GroupLayoutHeaderString:SetText("Buff Groups")
    GroupLayout_DisableChecks()
    curGroupSel = nil
    BuffReminder.Update()
end

function GroupLayoutDelBuffDrop_OnClick(arg1)
    if curGroupSel ~= nil then
        brBuffGroups[curGroupSel].buffs[arg1] = nil
    end
    DelBuffDropInit()
    BuffReminder.Update()
end

function GroupLayout_GetSelected(group)
    GroupLayoutHeaderString:SetText(group)
    GroupLayout_EnableChecks()
    BrCheck_SetState(GConditionsAlwaysCheck, brBuffGroups[group].conditions["always"])
    BrCheck_SetState(GConditionsRestingCheck, brBuffGroups[group].conditions["resting"])
    BrCheck_SetState(GConditionsTaxiCheck, brBuffGroups[group].conditions["taxi"])
    BrCheck_SetState(GConditionsDeadCheck, brBuffGroups[group].conditions["dead"])
    BrCheck_SetState(GConditionsPartyCheck, brBuffGroups[group].conditions["party"])
    BrCheck_SetState(GConditionsRaidCheck, brBuffGroups[group].conditions["raid"])
    BrCheck_SetState(GConditionsInstanceCheck, brBuffGroups[group].conditions["instance"])
    BrTimeEdit:SetText(brBuffGroups[group].warntime)
end

function GroupLayout_DisableChecks()
    curGroupSel = nil
    GConditionsAlwaysCheck:Disable()
    GConditionsRestingCheck:Disable()
    GConditionsTaxiCheck:Disable()
    GConditionsDeadCheck:Disable()
    GConditionsPartyCheck:Disable()
    GConditionsRaidCheck:Disable()
    GConditionsInstanceCheck:Disable()
end

function GroupLayout_EnableChecks()
    GConditionsAlwaysCheck:Enable()
    GConditionsRestingCheck:Enable()
    GConditionsTaxiCheck:Enable()
    GConditionsDeadCheck:Enable()
    GConditionsPartyCheck:Enable()
    GConditionsRaidCheck:Enable()
    GConditionsInstanceCheck:Enable()
end

function BrSetGroupWarnTime(t)
    if t ~= nil and t ~= "" then
        brBuffGroups[curGroupSel].warntime = tonumber(t)
    end
end

function BrSetDefaultWarnTime(t)
    if t ~= nil and t ~= "" then
        brOptions.warntime = tonumber(t)
    end
end

function BrSetWarnCharges(t)
    if t ~= nil and t ~= "" then
        brOptions.warncharges = tonumber(t)
    end
end

-- Check Buttons --
function BrCheck_OnLoad()
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

function BrCheck_Clicked()
    if this.state == 2 then
        BrCheck_SetState(this, 0)
    else
        BrCheck_SetState(this, this.state + 1)
    end
    brBuffGroups[curGroupSel].conditions[string.lower(this:GetText())] = this.state
    BuffReminder.Update()
end

function BrDefCheck_Clicked()
    if this.state == 2 then
        BrCheck_SetState(this, 0)
    else
        BrCheck_SetState(this, this.state + 1)
    end
    string.lower(this:GetText())
    brOptions.conditions[string.lower(this:GetText())] = this.state
    BuffReminder.Update()
end

function BrCheck_SetState(check, state)
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
function BrGroupsConfigFrame_Toggle(mouseButton)
    if IsShiftKeyDown() then
        if BuffReminderFrame:IsMouseEnabled() then
            BuffReminderFrame:EnableMouse(false)
            brtexture:SetTexture(nil)
        else
            BuffReminderFrame:EnableMouse(true)
            brtexture:SetTexture("Interface\\AddOns\\BuffReminder\\Media\\cross")
        end
    elseif mouseButton == "LeftButton" then
        if BrGroupsConfigFrame:IsShown() then
            BrGroupsConfigFrame:Hide();
        else
            BrGroupsConfigFrame:Show();
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

function BrGroupsConfigFrame_OnEnter()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:SetText("BuffReminder")
    GameTooltip:AddLine("Left-click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to temporarily hide the icons.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock the icon frame.", 1, 1, 1)
    GameTooltip:Show()
end

function BrGroupsConfigFrame_OnLeave()
    GameTooltip:Hide()
end
