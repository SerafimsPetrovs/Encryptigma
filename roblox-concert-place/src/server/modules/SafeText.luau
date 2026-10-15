--!strict
-- Любая строка от игрока, которую увидят другие (имя на экране, название перформанса),
-- обязана пройти через TextService. Без этого плейс не пройдёт модерацию Roblox.

local TextService = game:GetService("TextService")

local SafeText = {}

local MAX_LENGTH = 20

function SafeText.forBroadcast(raw: string, fromUserId: number): string?
	if typeof(raw) ~= "string" then
		return nil
	end
	local trimmed = string.sub(string.gsub(raw, "[%c]", ""), 1, MAX_LENGTH)
	if #trimmed == 0 then
		return nil
	end

	local ok, result = pcall(function()
		return TextService:FilterStringAsync(trimmed, fromUserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or result == nil then
		warn("[SafeText] FilterStringAsync: " .. tostring(result))
		return nil
	end

	local okBroadcast, filtered = pcall(function()
		return (result :: TextFilterResult):GetNonChatStringForBroadcastAsync()
	end)
	if not okBroadcast then
		warn("[SafeText] GetNonChatStringForBroadcastAsync: " .. tostring(filtered))
		return nil
	end
	return filtered
end

return SafeText
