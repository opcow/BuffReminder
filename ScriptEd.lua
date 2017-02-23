
-- ScriptEd.lua
-- Author      : mcrane
BuffReminder.edit_target = {}

function BuffReminder.BrScriptEditor_OnShow()
	this:SetText(BuffReminder.edit_target.script);
end

function BuffReminder.SaveScript()
    local text = BrScriptEditor:GetText()
    if BuffReminder.cur_group ~= nil then
        --DEFAULT_CHAT_FRAME:AddMessage(myfunc())
        if text ~= nil then
            BuffReminder.edit_target.script = text
            BuffReminder.scripts[BuffReminder.load_target]  = loadstring(text)
        else
            BuffReminder.edit_target.script = ""
            BuffReminder.scripts[BuffReminder.load_target] = nil
        end
    end
end