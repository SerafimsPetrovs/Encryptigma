--!strict
-- Режиссёр шоу. Сервер не проигрывает музыку и не двигает свет: он только объявляет,
-- какой трек стартует и в какой момент общих часов. Вся картинка собирается на клиенте.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicClock = require(Shared.MusicClock)
local Net = require(Shared.Net)
local ShowConfig = require(Shared.ShowConfig)

local trackStarted = Net.event(Net.Names.TrackStarted)
local trackStopped = Net.event(Net.Names.TrackStopped)
local preloadRequest = Net.event(Net.Names.PreloadRequest)
local clientReady = Net.event(Net.Names.ClientReady)
local showState = Net.fn(Net.Names.ShowState)

export type State = {
	mode: string, -- idle | preshow | live
	showId: string?,
	showName: string?,
	songId: string?,
	startTime: number?,
	trackIndex: number,
	nextShowAt: number?,
}

local ShowDirector = {}

local state: State = { mode = "idle", trackIndex = 0 }
local readyAcks: { [number]: boolean } = {}
local listeners: { (State) -> () } = {}
local showThread: thread? = nil

function ShowDirector.onChanged(fn: (State) -> ())
	table.insert(listeners, fn)
end

local function notify()
	for _, fn in listeners do
		task.spawn(fn, state)
	end
end

function ShowDirector.getState(): State
	return state
end

function ShowDirector.isLive(): boolean
	return state.mode ~= "idle"
end

-- Следующий слот расписания в абсолютном времени (os.time, UTC).
-- Если ScheduleOffsetHours переносит время через полночь, weekday нужно задавать уже в UTC.
local function nextOccurrence(entry: any, fromTime: number): number
	local target = ((entry.hour - ShowConfig.ScheduleOffsetHours) * 3600 + entry.minute * 60) % 86400
	local now = os.date("!*t", fromTime)
	local nowSeconds = now.hour * 3600 + now.min * 60 + now.sec
	local dayDelta = (entry.weekday - now.wday) % 7
	local candidate = fromTime - nowSeconds + dayDelta * 86400 + target
	if candidate <= fromTime then
		candidate += 7 * 86400
	end
	return candidate
end

function ShowDirector.nextScheduled(): (number?, string?)
	local bestAt: number? = nil
	local bestShow: string? = nil
	local now = os.time()
	for _, entry in ShowConfig.Schedule do
		local at = nextOccurrence(entry, now)
		if bestAt == nil or at < bestAt then
			bestAt = at
			bestShow = entry.showId
		end
	end
	return bestAt, bestShow
end

local lastTriggered: { [string]: number } = {}

-- Шоу считается «пора начинать», если его время наступило не раньше, чем graceSeconds назад:
-- так опоздание планировщика или рестарт сервера не съедают концерт целиком.
function ShowDirector.dueShow(graceSeconds: number): string?
	local now = os.time()
	for _, entry in ShowConfig.Schedule do
		local at = nextOccurrence(entry, now - graceSeconds)
		if at <= now then
			local key = entry.showId .. "@" .. tostring(at)
			if not lastTriggered[key] then
				lastTriggered[key] = now
				return entry.showId
			end
		end
	end
	return nil
end

-- Просим клиентов прогреть ассеты и ждём подтверждений, но не дольше таймаута:
-- один залипший клиент не должен задерживать концерт.
local function waitForPreload(soundIds: { string })
	table.clear(readyAcks)
	preloadRequest:FireAllClients(soundIds)

	local deadline = os.clock() + ShowConfig.Sync.preloadTimeoutSeconds
	while os.clock() < deadline do
		local total = #Players:GetPlayers()
		if total == 0 then
			break
		end
		local acked = 0
		for _, player in Players:GetPlayers() do
			if readyAcks[player.UserId] then
				acked += 1
			end
		end
		if acked >= math.max(1, math.floor(total * 0.8)) then
			break
		end
		task.wait(0.25)
	end
end

local function broadcastTrack(showId: string, songId: string, song: ShowConfig.Song, index: number)
	local startTime = MusicClock.now() + ShowConfig.Sync.leadInSeconds
	state.mode = "live"
	state.showId = showId
	state.songId = songId
	state.startTime = startTime
	state.trackIndex = index
	notify()

	trackStarted:FireAllClients({
		showId = showId,
		songId = songId,
		startTime = startTime,
		bpm = song.bpm,
		duration = song.duration,
	})
end

local function runShow(showId: string)
	local show = ShowConfig.getShow(showId)
	if not show then
		warn("[ShowDirector] неизвестное шоу: " .. showId)
		return
	end

	state.mode = "preshow"
	state.showId = showId
	state.showName = show.name
	notify()

	local soundIds = {}
	for _, track in show.tracks do
		local song = ShowConfig.getSong(track.songId)
		if song then
			table.insert(soundIds, song.soundId)
		end
	end
	waitForPreload(soundIds)

	for index, track in show.tracks do
		local song = ShowConfig.getSong(track.songId)
		if song then
			broadcastTrack(showId, track.songId, song, index)
			task.wait(ShowConfig.Sync.leadInSeconds + song.duration)
			trackStopped:FireAllClients(track.songId)
			if track.gapAfterSeconds > 0 then
				task.wait(track.gapAfterSeconds)
			end
		end
	end

	ShowDirector.stop()
end

function ShowDirector.startShow(showId: string): boolean
	if ShowDirector.isLive() then
		return false
	end
	showThread = task.spawn(runShow, showId)
	return true
end

function ShowDirector.stop()
	if showThread then
		local thread = showThread
		showThread = nil
		if coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	end
	if state.songId then
		trackStopped:FireAllClients(state.songId)
	end
	state.mode = "idle"
	state.songId = nil
	state.startTime = nil
	state.trackIndex = 0
	state.nextShowAt = select(1, ShowDirector.nextScheduled())
	notify()
end

function ShowDirector.start()
	state.nextShowAt = select(1, ShowDirector.nextScheduled())

	clientReady.OnServerEvent:Connect(function(player)
		readyAcks[player.UserId] = true
	end)

	showState.OnServerInvoke = function(_player)
		return {
			mode = state.mode,
			showId = state.showId,
			showName = state.showName,
			songId = state.songId,
			startTime = state.startTime,
			trackIndex = state.trackIndex,
			nextShowAt = state.nextShowAt,
			serverNow = MusicClock.now(),
			-- Часы игрока могут быть сбиты, поэтому отдаём и os.time сервера:
			-- клиент считает по нему разницу и показывает честный отсчёт до концерта.
			serverOsTime = os.time(),
		}
	end

	Players.PlayerRemoving:Connect(function(player)
		readyAcks[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			if not ShowDirector.isLive() then
				state.nextShowAt = select(1, ShowDirector.nextScheduled())
				local due = ShowDirector.dueShow(180)
				if due then
					ShowDirector.startShow(due)
				end
			end
		end
	end)
end

return ShowDirector
