-- Author      : mcrane
-- Create Date : 1/6/2017 7:45:06 AM
local curGroupSel
local curBuffSel

function BrGroupsConfigFrame_OnShow()
    DefConditionsAlwaysCheck:SetChecked(brOptions.conditions["always"])
    DefConditionsRestingCheck:SetChecked(brOptions.conditions["resting"])
    DefConditionsTaxiCheck:SetChecked(brOptions.conditions["taxi"])
    DefConditionsDeadCheck:SetChecked(brOptions.conditions["dead"])
    DefConditionsPartyCheck:SetChecked(brOptions.conditions["party"])
    DefConditionsRaidCheck:SetChecked(brOptions.conditions["raid"])
    DefConditionsInstanceCheck:SetChecked(brOptions.conditions["instance"])
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
    GroupSaveBtn:Disable()
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
        GConditionsAlwaysCheck:SetChecked(brBuffGroups[arg1].conditions["always"])
        GConditionsRestingCheck:SetChecked(brBuffGroups[arg1].conditions["resting"])
        GConditionsTaxiCheck:SetChecked(brBuffGroups[arg1].conditions["taxi"])
        GConditionsDeadCheck:SetChecked(brBuffGroups[arg1].conditions["dead"])
        GConditionsPartyCheck:SetChecked(brBuffGroups[arg1].conditions["party"])
        GConditionsRaidCheck:SetChecked(brBuffGroups[arg1].conditions["raid"])
        GConditionsInstanceCheck:SetChecked(brBuffGroups[arg1].conditions["instance"])
        BrTimeEdit:SetText(brBuffGroups[arg1].warntime)
        GroupSaveBtn:Enable()
    else
        GroupLayout_DisableChecks()
        GroupSaveBtn:Disable()
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

function BrSaveGroup()
    if brBuffGroups[curGroupSel] ~= nil then
        brBuffGroups[curGroupSel].conditions.always = (GConditionsAlwaysCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.resting = (GConditionsRestingCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.taxi = (GConditionsTaxiCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.dead = (GConditionsDeadCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.party = (GConditionsPartyCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.raid = (GConditionsRaidCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].conditions.instance = (GConditionsInstanceCheck:GetChecked() == 1)
        brBuffGroups[curGroupSel].warntime = tonumber(BrTimeEdit:GetText())
        brForceUpdate = true
    end
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

-- Check Buttons --
function BrCheck_Clicked()
    local n = string.lower(getglobal(this:GetName() .. "Text"):GetText())
    n = string.lower(this:GetText())
end

-- Defauts Section --
function BrSaveDefaults()
    brOptions.conditions.always = DefConditionsAlwaysCheck:GetChecked()
    brOptions.conditions.resting = DefConditionsRestingCheck:GetChecked()
    brOptions.conditions.taxi = DefConditionsTaxiCheck:GetChecked()
    brOptions.conditions.dead = DefConditionsDeadCheck:GetChecked()
    brOptions.conditions.party = DefConditionsPartyCheck:GetChecked()
    brOptions.conditions.raid = DefConditionsRaidCheck:GetChecked()
    brOptions.conditions.instance = DefConditionsInstanceCheck:GetChecked()
    brOptions.warnsound = BrSoundEdit:GetText()
    brOptions.warntime = tonumber(BrDefTimeEdit:GetText())
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
    GameTooltip:SetText("BuffReminder")-- This sets the top line of text, in gold.
    GameTooltip:AddLine("Click to configure.", 1, 1, 1)
    GameTooltip:AddLine("Shift-click to unlock the icon frame.", 1, 1, 1)
    GameTooltip:Show()
end

function BrGroupsConfigFrame_OnLeave()
    GameTooltip:Hide()
end
