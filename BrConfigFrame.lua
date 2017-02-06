-- Author      : mcrane
-- Create Date : 1/6/2017 7:45:06 AM
local curGroupSel
local curBuffSel

function BrGroupsConfigFrame_OnShow()
    BrCheck_SetState(DefConditionsAlwaysCheck, brOptions.conditions["always"])
    BrCheck_SetState(DefConditionsRestingCheck, brOptions.conditions["resting"])
    BrCheck_SetState(DefConditionsTaxiCheck, brOptions.conditions["taxi"])
    BrCheck_SetState(DefConditionsDeadCheck, brOptions.conditions["dead"])
    BrCheck_SetState(DefConditionsPartyCheck, brOptions.conditions["party"])
    BrCheck_SetState(DefConditionsRaidCheck, brOptions.conditions["raid"])
    BrCheck_SetState(DefConditionsInstanceCheck, brOptions.conditions["instance"])
    if brOptions.warntime == nil then
        BrDefTimeEdit:SetText("60")
    else
        BrDefTimeEdit:SetText(brOptions.warntime)
    end
    if brOptions.warnsound ~= nil then
        BrSoundEdit:SetText(brOptions.warnsound)
    end
end

-- Group Section --
function BrGroupCfg_OnLoad()
    GroupLayoutAddBtn:SetScript("OnClick", AddGroupClicked)
    GroupLayoutDelBtn:SetScript("OnClick", DelGroupClicked)
end

function AddGroupClicked()
    local txt = GroupLayoutEdit:GetText()
    if txt ~= nil and txt ~= "" then
        BuffReminder.AddBuffToGroup(txt, nil)
        GroupLayoutEdit:SetText("")
        UIDropDownMenu_ClearAll(GroupLayoutDrop)
        GroupLayout_DisableChecks()
    end
end

function DelGroupClicked()
    if curGroupSel ~= nill then
        brBuffGroups[curGroupSel] = nil
    end
    UIDropDownMenu_SetSelectedID(GroupLayoutDrop, 1)
    local n = UIDropDownMenu_GetSelectedName(GroupLayoutDrop)
    UIDropDownMenu_ClearAll(GroupLayoutDrop)
    GroupLayout_DisableChecks()
end

function GroupDropInit(level)
    local info = {}
    for i in brBuffGroups do
        info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, false, false, i, GroupLayoutDrop_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

function GroupLayoutDrop_OnClick(arg1)
    curGroupSel = arg1
    UIDropDownMenu_SetSelectedID(GroupLayoutDrop, this:GetID())
    if brBuffGroups[arg1] ~= nil then
        GroupLayout_EnableChecks()
        BrCheck_SetState(GConditionsAlwaysCheck, brBuffGroups[arg1].conditions["always"])
        BrCheck_SetState(GConditionsRestingCheck, brBuffGroups[arg1].conditions["resting"])
        BrCheck_SetState(GConditionsTaxiCheck, brBuffGroups[arg1].conditions["taxi"])
        BrCheck_SetState(GConditionsDeadCheck, brBuffGroups[arg1].conditions["dead"])
        BrCheck_SetState(GConditionsPartyCheck, brBuffGroups[arg1].conditions["party"])
        BrCheck_SetState(GConditionsRaidCheck, brBuffGroups[arg1].conditions["raid"])
        BrCheck_SetState(GConditionsInstanceCheck, brBuffGroups[arg1].conditions["instance"])
        BrTimeEdit:SetText(brBuffGroups[arg1].warntime)
    else
        GroupLayout_DisableChecks()
    end
end

function GroupLayout_DisableChecks()
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

-- Buff Section --
function BrBuffCfg_OnLoad()
    BuffLayoutAddBtn:SetScript("OnClick", AddBuffClicked)
    BuffLayoutDelBtn:SetScript("OnClick", DelBuffClicked)
end

function AddBuffClicked()
    local txt = BuffLayoutEdit:GetText()
    if txt ~= nil and txt ~= "" then
        BuffReminder.AddBuffToGroup(curGroupSel, txt)
        BuffLayoutEdit:SetText("")
        UIDropDownMenu_ClearAll(BuffLayoutDrop)
    end
end

function DelBuffClicked()
    if curBuffSel ~= nil then
        brBuffGroups[curGroupSel].buffs[curBuffSel] = nil
        UIDropDownMenu_ClearAll(BuffLayoutDrop)
    end
end

function BuffDropInit(level)
    local info = {}
    if brBuffGroups[curGroupSel] ~= nil then
        for i in brBuffGroups[curGroupSel].buffs do
            info.text, info.checked, info.notCheckable, info.keepShownOnClick, info.arg1, info.func = i, false, false, false, i, BuffLayoutDrop_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end
end

function BuffLayoutDrop_OnClick(arg1)
    curBuffSel = arg1
    UIDropDownMenu_SetSelectedID(BuffLayoutDrop, this:GetID())
end

function BrSetGroupWarnTime()
    brBuffGroups[curGroupSel].warntime = tonumber(BrTimeEdit:GetText())
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
    brForceUpdate = true
end

function BrDefCheck_Clicked()
    if this.state == 2 then
        BrCheck_SetState(this, 0)
    else
        BrCheck_SetState(this, this.state + 1)
    end
    string.lower(this:GetText())

    brOptions.conditions[string.lower(this:GetText())] = this.state
end

function BrCheck_GetState(check)
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

-- Config Button Section --
function BrGroupsConfigFrame_Toggle()
    
    if IsShiftKeyDown() then
        if BuffReminderFrame:IsMouseEnabled() then
            BuffReminderFrame:EnableMouse(false)
            brtexture:SetTexture(nil)
        else
            BuffReminderFrame:EnableMouse(true)
            brtexture:SetTexture("Interface\\AddOns\\BuffReminder\\Media\\cross")
        end
    elseif BrGroupsConfigFrame:IsShown() then
        BrGroupsConfigFrame:Hide();
    else
        BrGroupsConfigFrame:Show();
    end
end

function BrGroupsConfigFrame_OnEnter()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:SetText("BuffReminder")
    GameTooltip:AddLine("Click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock the icon frame.", 1, 1, 1)
    GameTooltip:Show()
end

function BrGroupsConfigFrame_OnLeave()
    GameTooltip:Hide()
end
