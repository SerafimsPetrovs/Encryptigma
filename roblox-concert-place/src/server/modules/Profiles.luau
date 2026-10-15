--!strict
-- Хранение прогресса игрока. Все изменения идут через UpdateAsync-дельты:
-- так покупка, выданная на другом сервере (или когда игрок уже вышел), не затирается.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local store = DataStoreService:GetDataStore("ConcertProfiles_v1")

export type Profile = {
	stageCredits: number, -- оплаченные, но ещё не использованные выходы на сцену
	performances: number,
	applause: number, -- аплодисменты/чаевые как внутренний рейтинг
	frontRowTickets: number,
}

local DEFAULT: Profile = {
	stageCredits = 0,
	performances = 0,
	applause = 0,
	frontRowTickets = 0,
}

local Profiles = {}

local cache: { [number]: Profile } = {}
local lastSlotAt: { [number]: number } = {}

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function copyDefault(): Profile
	return {
		stageCredits = DEFAULT.stageCredits,
		performances = DEFAULT.performances,
		applause = DEFAULT.applause,
		frontRowTickets = DEFAULT.frontRowTickets,
	}
end

local function numberOr(value: any, fallback: number): number
	return if typeof(value) == "number" then value else fallback
end

local function normalize(raw: any): Profile
	local source: any = if typeof(raw) == "table" then raw else {}
	return {
		stageCredits = numberOr(source.stageCredits, DEFAULT.stageCredits),
		performances = numberOr(source.performances, DEFAULT.performances),
		applause = numberOr(source.applause, DEFAULT.applause),
		frontRowTickets = numberOr(source.frontRowTickets, DEFAULT.frontRowTickets),
	}
end

local function retry<T>(label: string, fn: () -> T): T?
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return result
		end
		warn(string.format("[Profiles] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		task.wait(2 ^ attempt)
	end
	return nil
end

function Profiles.load(userId: number): Profile
	local raw = retry("load", function()
		return store:GetAsync(keyFor(userId))
	end)
	local profile = normalize(raw)
	cache[userId] = profile
	return profile
end

function Profiles.isLoaded(userId: number): boolean
	return cache[userId] ~= nil
end

function Profiles.peek(userId: number): Profile
	return cache[userId] or copyDefault()
end

-- Единственный способ менять данные: применяем числовые дельты атомарно.
function Profiles.applyDelta(userId: number, delta: { [string]: number }): Profile?
	local updated = retry("applyDelta", function()
		return store:UpdateAsync(keyFor(userId), function(raw)
			local profile: any = normalize(raw)
			for field, amount in delta do
				profile[field] = math.max(0, numberOr(profile[field], 0) + amount)
			end
			return profile
		end)
	end)
	if updated == nil then
		return nil
	end
	local profile = normalize(updated)
	if cache[userId] then
		cache[userId] = profile
	end
	return profile
end

function Profiles.grantStageCredits(userId: number, amount: number): boolean
	return Profiles.applyDelta(userId, { stageCredits = amount }) ~= nil
end

function Profiles.consumeStageCredit(userId: number): boolean
	local profile = Profiles.peek(userId)
	if profile.stageCredits <= 0 then
		return false
	end
	local updated = Profiles.applyDelta(userId, { stageCredits = -1, performances = 1 })
	return updated ~= nil
end

-- Кулдаун живёт только в памяти сервера: он нужен против спама в текущей сессии.
function Profiles.markSlotUsed(userId: number)
	lastSlotAt[userId] = os.clock()
end

function Profiles.secondsSinceSlot(userId: number): number
	local at = lastSlotAt[userId]
	if not at then
		return math.huge
	end
	return os.clock() - at
end

function Profiles.start()
	local function onJoin(player: Player)
		task.spawn(Profiles.load, player.UserId)
	end

	for _, player in Players:GetPlayers() do
		onJoin(player)
	end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		cache[player.UserId] = nil
		lastSlotAt[player.UserId] = nil
	end)
end

return Profiles
