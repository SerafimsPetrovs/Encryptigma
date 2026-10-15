--!strict
-- Единая точка конфигурации: сетлист, таймлайн кью, цены, параметры сцены.
-- Все нулевые id нужно заменить на реальные после загрузки ассетов и создания продуктов.

local ShowConfig = {}

ShowConfig.Products = {
	StageSlot = 0, -- 20 R$: один выход на открытую сцену
	StageSlotBundle5 = 0, -- 75 R$: пачка из 5 выходов
	PrimeTimeSlot = 0, -- 199 R$: слот на разогреве перед концертом
	FrontRowTicket = 0, -- 49 R$: первый ряд на конкретный концерт
	TipSmall = 0, -- 10 R$: чаевые перформеру (идут в рейтинг, не в Robux)
	TipLarge = 0, -- 100 R$
}

-- Цены дублируются здесь только для подписей в интерфейсе.
-- Реальная цена задаётся в настройках продукта на сайте Roblox.
ShowConfig.Prices = {
	stageSlot = 20,
	stageSlotBundle5 = 75,
	primeTimeSlot = 199,
	frontRowTicket = 49,
	vipPass = 299,
}

ShowConfig.Passes = {
	Vip = 0, -- постоянный доступ в VIP-ярус
}

-- userId тех, кто может снимать перформера со сцены и запускать шоу вручную.
ShowConfig.Admins = {} :: { [number]: boolean }

ShowConfig.Stage = {
	slotSeconds = 75,
	slotCooldownSeconds = 240,
	queueCap = 40,
	warnBeforeEndSeconds = 10,
	maxFxPerSecond = 3,
}

ShowConfig.Sync = {
	-- Запас между анонсом трека и его стартом: клиенты успевают догрузить ассет и выровнять часы.
	leadInSeconds = 6,
	preloadTimeoutSeconds = 12,
	-- Жёсткая перестановка TimePosition слышна как щелчок, поэтому только при крупном рассинхроне.
	hardResyncThreshold = 0.25,
	softResyncThreshold = 0.035,
	maxPlaybackSpeedTrim = 0.04,
	driftCheckInterval = 2,
}

export type Cue = {
	t: number, -- время внутри трека в секундах
	kind: string, -- lights | fog | pyro | screen | crowd | camera
	preset: string?,
	text: string?,
	power: number?,
}

export type Song = {
	name: string,
	soundId: string,
	bpm: number,
	duration: number,
	cues: { Cue },
}

export type Track = {
	songId: string,
	gapAfterSeconds: number,
}

export type Show = {
	name: string,
	tracks: { Track },
}

-- Пресеты света: ShowRunner читает их по имени из кью, арт меняется без правок кода.
ShowConfig.LightPresets = {
	house = { -- свет между песнями
		brightness = 2,
		ambient = Color3.fromRGB(70, 70, 80),
		beamColor = Color3.fromRGB(255, 240, 210),
		beamWidth = 2,
		fog = 120,
		tint = Color3.fromRGB(255, 255, 255),
		beatPulse = 0,
	},
	intro = {
		brightness = 0.4,
		ambient = Color3.fromRGB(20, 20, 40),
		beamColor = Color3.fromRGB(90, 140, 255),
		beamWidth = 1.5,
		fog = 60,
		tint = Color3.fromRGB(220, 230, 255),
		beatPulse = 0.25,
	},
	verse = {
		brightness = 1,
		ambient = Color3.fromRGB(30, 30, 45),
		beamColor = Color3.fromRGB(140, 120, 255),
		beamWidth = 2,
		fog = 80,
		tint = Color3.fromRGB(240, 240, 255),
		beatPulse = 0.4,
	},
	drop = {
		brightness = 3,
		ambient = Color3.fromRGB(60, 20, 60),
		beamColor = Color3.fromRGB(255, 80, 160),
		beamWidth = 4,
		fog = 40,
		tint = Color3.fromRGB(255, 230, 245),
		beatPulse = 1,
	},
	outro = {
		brightness = 0.8,
		ambient = Color3.fromRGB(25, 25, 35),
		beamColor = Color3.fromRGB(255, 200, 120),
		beamWidth = 2.5,
		fog = 100,
		tint = Color3.fromRGB(255, 245, 230),
		beatPulse = 0.15,
	},
}

-- Демо-таймлайн первой песни. Время кью проще всего снять в DAW по маркерам.
ShowConfig.Songs = {
	["single-01"] = {
		name = "Single 01 (rbx edit)",
		soundId = "rbxassetid://0",
		bpm = 124,
		duration = 192,
		cues = {
			{ t = 0, kind = "lights", preset = "intro" },
			{ t = 0, kind = "screen", text = "SINGLE 01" },
			{ t = 0.5, kind = "fog", power = 1 },
			{ t = 16, kind = "lights", preset = "verse" },
			{ t = 46, kind = "lights", preset = "drop" },
			{ t = 46, kind = "pyro", preset = "front-line", power = 1 },
			{ t = 46, kind = "crowd", preset = "jump" },
			{ t = 46, kind = "camera", preset = "crane-wide" },
			{ t = 78, kind = "lights", preset = "verse" },
			{ t = 108, kind = "lights", preset = "drop" },
			{ t = 108, kind = "pyro", preset = "tower-burst", power = 1 },
			{ t = 108, kind = "camera", preset = "orbit-close" },
			{ t = 170, kind = "lights", preset = "outro" },
			{ t = 170, kind = "screen", text = "SPOTIFY: SINGLE 01" },
		},
	} :: Song,
} :: { [string]: Song }

ShowConfig.Shows = {
	["sunday-live"] = {
		name = "Sunday Live",
		tracks = {
			{ songId = "single-01", gapAfterSeconds = 25 },
		},
	} :: Show,
} :: { [string]: Show }

-- wday как в os.date("*t"): 1 = воскресенье. Время в UTC, смещение задаётся отдельно.
ShowConfig.Schedule = {
	{ weekday = 1, hour = 18, minute = 0, showId = "sunday-live" },
}

ShowConfig.ScheduleOffsetHours = 0

function ShowConfig.getSong(songId: string): Song?
	return ShowConfig.Songs[songId]
end

function ShowConfig.getShow(showId: string): Show?
	return ShowConfig.Shows[showId]
end

function ShowConfig.isConfigured(): boolean
	for _, song in ShowConfig.Songs do
		if song.soundId == "rbxassetid://0" then
			return false
		end
	end
	return true
end

return ShowConfig
