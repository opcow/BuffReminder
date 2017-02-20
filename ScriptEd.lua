
-- ScriptEd.lua
-- Author      : mcrane

function BuffReminder.SaveScript()
    local text = BrScriptEditor:GetText()
    if BuffReminder.cur_group ~= nil then
        --myfunc = loadstring(text)
        --DEFAULT_CHAT_FRAME:AddMessage(myfunc())
        if text ~= nil then
            BRVars.BuffGroups[BuffReminder.cur_group].script = text
            BuffReminder.scripts[BuffReminder.cur_group] = loadstring(text)
        else
            BRVars.BuffGroups[BuffReminder.cur_group].script = ""
            BuffReminder.scripts[BuffReminder.cur_group] = nil
        end
    end
end