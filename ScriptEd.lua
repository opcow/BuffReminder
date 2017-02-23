
-- ScriptEd.lua
-- Author      : mcrane
BuffReminder.edit_target = {}

function BuffReminder.BrScriptEditor_OnShow()
	this:SetText(BuffReminder.edit_target.script);
end

function BuffReminder.SaveScript()
    local text = BrScriptEditor:GetText()
    --DEFAULT_CHAT_FRAME:AddMessage(myfunc())
    if text ~= nil then
        BuffReminder.edit_target.script = text
        BuffReminder.load_target.script = loadstring(text)
    else
        BuffReminder.edit_target.script = ""
        BuffReminder.load_target.script = nil
    end
end