--!strict
-- Музыкальное время как единственный тактовый генератор шоу.
-- Сервер шлёт только startTime (общие часы Workspace:GetServerTimeNow), всё остальное считается локально.

local Workspace = game:GetService("Workspace")

local MusicClock = {}

function MusicClock.now(): number
	return Workspace:GetServerTimeNow()
end

-- Сколько секунд трека уже прошло. Отрицательное значение = отсчёт до старта.
function MusicClock.positionFor(startTime: number): number
	return Workspace:GetServerTimeNow() - startTime
end

-- Доля текущей доли такта в диапазоне [0, 1): основа для пульсации света без анализа спектра.
function MusicClock.beatPhase(musicTime: number, bpm: number): number
	if bpm <= 0 then
		return 0
	end
	local beats = musicTime * (bpm / 60)
	return beats % 1
end

function MusicClock.beatIndex(musicTime: number, bpm: number): number
	if bpm <= 0 then
		return 0
	end
	return math.floor(musicTime * (bpm / 60))
end

-- Затухание на каждой доле: 1 на удар, 0 к концу доли. Используется как множитель яркости.
function MusicClock.beatEnvelope(musicTime: number, bpm: number, sharpness: number?): number
	local phase = MusicClock.beatPhase(musicTime, bpm)
	return (1 - phase) ^ (sharpness or 3)
end

return MusicClock
