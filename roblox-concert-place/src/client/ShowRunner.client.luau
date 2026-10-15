--!strict
-- Клиентский проигрыватель шоу. Мастер-часы — позиция внутри трека:
-- свет, пиро и экраны привязаны к Sound.TimePosition, а не к сигналам с сервера,
-- поэтому картинка не может уехать от музыки.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientBus = require(Shared.ClientBus)
local MusicClock = require(Shared.MusicClock)
local Net = require(Shared.Net)
local ShowConfig = require(Shared.ShowConfig)

local trackStarted = Net.event(Net.Names.TrackStarted)
local trackStopped = Net.event(Net.Names.TrackStopped)
local preloadRequest = Net.event(Net.Names.PreloadRequest)
local clientReady = Net.event(Net.Names.ClientReady)
local showStateFn = Net.fn(Net.Names.ShowState)
local stageFx = Net.event(Net.Names.StageFx)

local BASE_VOLUME = 0.65

-- Sound в SoundService звучит как 2D: громкость не зависит от того, где стоит игрок.
local music = Instance.new("Sound")
music.Name = "ShowMusic"
music.Volume = BASE_VOLUME
music.Looped = false
music.Parent = SoundService

local colorCorrection = Lighting:FindFirstChild("ShowColorCorrection") :: ColorCorrectionEffect?
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "ShowColorCorrection"
	colorCorrection.Parent = Lighting
end

type Current = {
	songId: string,
	startTime: number,
	bpm: number,
	duration: number,
	cues: { ShowConfig.Cue },
}

local current: Current? = nil
local cueIndex = 1
local activePreset = ShowConfig.LightPresets.house
local lightBase: { [Instance]: number } = {}

local function taggedLights(): { Instance }
	return CollectionService:GetTagged("StageLight")
end

local function applyPreset(name: string?)
	local preset = ShowConfig.LightPresets[name or "house"]
	if not preset then
		return
	end
	activePreset = preset

	local tween = TweenInfo.new(0.4, Enum.EasingStyle.Quad)
	TweenService:Create(Lighting, tween, {
		Brightness = preset.brightness,
		OutdoorAmbient = preset.ambient,
	}):Play()
	if colorCorrection then
		TweenService:Create(colorCorrection, tween, { TintColor = preset.tint }):Play()
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, tween, { Haze = math.clamp(preset.fog / 20, 0, 10) }):Play()
	else
		TweenService:Create(Lighting, tween, { FogEnd = preset.fog * 4 }):Play()
	end

	for _, instance in taggedLights() do
		local gain = instance:GetAttribute("Gain")
		local multiplier = if typeof(gain) == "number" then gain else 1
		if instance:IsA("Light") then
			lightBase[instance] = preset.brightness * multiplier
			instance.Color = preset.beamColor
		elseif instance:IsA("Beam") then
			lightBase[instance] = multiplier
			instance.Color = ColorSequence.new(preset.beamColor)
			instance.Width0 = preset.beamWidth * multiplier
			instance.Width1 = preset.beamWidth * 2 * multiplier
		end
	end
end

CollectionService:GetInstanceRemovedSignal("StageLight"):Connect(function(instance)
	lightBase[instance] = nil
end)

local function fireScreen(text: string?)
	for _, instance in CollectionService:GetTagged("StageScreen") do
		if instance:IsA("TextLabel") then
			instance.Text = text or ""
		else
			for _, label in instance:GetDescendants() do
				if label:IsA("TextLabel") then
					label.Text = text or ""
				end
			end
		end
	end
end

local function firePyro(preset: string?, power: number?)
	local amount = math.clamp(math.floor((power or 1) * 40), 1, 200)
	for _, instance in CollectionService:GetTagged("StagePyro") do
		if instance:IsA("ParticleEmitter") then
			local tag = instance:GetAttribute("Preset")
			if preset == nil or tag == nil or tag == preset then
				instance:Emit(amount)
			end
		end
	end
end

local function fireFog(power: number?)
	for _, instance in CollectionService:GetTagged("StageFog") do
		if instance:IsA("ParticleEmitter") then
			instance.Rate = math.clamp((power or 1) * 25, 0, 200)
		end
	end
end

local cueHandlers: { [string]: (ShowConfig.Cue) -> () } = {
	lights = function(cue)
		applyPreset(cue.preset)
	end,
	screen = function(cue)
		fireScreen(cue.text)
	end,
	pyro = function(cue)
		firePyro(cue.preset, cue.power)
	end,
	fog = function(cue)
		fireFog(cue.power)
	end,
	crowd = function(cue)
		ClientBus.emit(ClientBus.Topics.CrowdCue, cue.preset)
	end,
	camera = function(cue)
		ClientBus.emit(ClientBus.Topics.CameraCue, cue.preset)
	end,
}

local function resetCueIndex(musicTime: number)
	cueIndex = 1
	local track = current
	if not track then
		return
	end
	-- При подключении посреди песни пропущенные кью не проигрываем,
	-- но последний световой пресет догоняем, чтобы сцена выглядела правильно.
	local lastPreset: string? = nil
	while cueIndex <= #track.cues and track.cues[cueIndex].t <= musicTime do
		local cue = track.cues[cueIndex]
		if cue.kind == "lights" then
			lastPreset = cue.preset
		end
		cueIndex += 1
	end
	if lastPreset then
		applyPreset(lastPreset)
	end
end

local function runCues(musicTime: number)
	local track = current
	if not track then
		return
	end
	while cueIndex <= #track.cues and track.cues[cueIndex].t <= musicTime do
		local cue = track.cues[cueIndex]
		cueIndex += 1
		local handler = cueHandlers[cue.kind]
		if handler then
			local ok, err = pcall(handler, cue)
			if not ok then
				warn("[ShowRunner] кью " .. cue.kind .. ": " .. tostring(err))
			end
		end
	end
end

local function stopTrack(fade: number?)
	current = nil
	cueIndex = 1
	local tween = TweenService:Create(music, TweenInfo.new(fade or 1.5), { Volume = 0 })
	tween.Completed:Connect(function()
		music:Stop()
		music.Volume = BASE_VOLUME
		music.PlaybackSpeed = 1
	end)
	tween:Play()
	applyPreset("house")
	fireScreen("")
	fireFog(0)
end

local function startTrack(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.songId) ~= "string" then
		return
	end
	local song = ShowConfig.getSong(payload.songId)
	if not song then
		warn("[ShowRunner] нет песни " .. tostring(payload.songId) .. " в ShowConfig")
		return
	end

	music:Stop()
	music.Volume = BASE_VOLUME
	music.PlaybackSpeed = 1
	music.SoundId = song.soundId
	pcall(function()
		ContentProvider:PreloadAsync({ music })
	end)

	current = {
		songId = payload.songId,
		startTime = payload.startTime,
		bpm = payload.bpm or song.bpm,
		duration = payload.duration or song.duration,
		cues = song.cues,
	}

	local offset = MusicClock.positionFor(payload.startTime)
	if offset < -0.05 then
		task.wait(-offset)
		offset = MusicClock.positionFor(payload.startTime)
	end
	if current == nil or current.songId ~= payload.songId then
		return
	end
	if offset >= song.duration then
		return
	end

	music:Play()
	music.TimePosition = math.max(0, offset)
	resetCueIndex(math.max(0, offset))
	ClientBus.emit(ClientBus.Topics.ShowStateChanged, { mode = "live", songId = payload.songId })
end

local function resync()
	local track = current
	if not track or not music.IsPlaying then
		return
	end
	local expected = MusicClock.positionFor(track.startTime)
	if expected < 0 or expected > track.duration then
		return
	end
	local drift = expected - music.TimePosition
	local magnitude = math.abs(drift)
	if magnitude > ShowConfig.Sync.hardResyncThreshold then
		music.TimePosition = expected
		music.PlaybackSpeed = 1
		resetCueIndex(expected)
	elseif magnitude > ShowConfig.Sync.softResyncThreshold then
		-- Мягкая подтяжка скоростью: слышится как едва заметный питч, щелчка нет.
		local maxTrim = ShowConfig.Sync.maxPlaybackSpeedTrim
		local trim = math.clamp(drift * 0.5, -maxTrim, maxTrim)
		music.PlaybackSpeed = 1 + trim
	else
		music.PlaybackSpeed = 1
	end
end

trackStarted.OnClientEvent:Connect(function(payload)
	task.spawn(startTrack, payload)
end)

trackStopped.OnClientEvent:Connect(function()
	stopTrack(1.5)
end)

preloadRequest.OnClientEvent:Connect(function(soundIds)
	task.spawn(function()
		if typeof(soundIds) == "table" then
			local probes = {}
			for _, id in soundIds do
				if typeof(id) == "string" then
					local probe = Instance.new("Sound")
					probe.SoundId = id
					probe.Parent = SoundService
					table.insert(probes, probe)
				end
			end
			pcall(function()
				ContentProvider:PreloadAsync(probes)
			end)
			for _, probe in probes do
				probe:Destroy()
			end
		end
		clientReady:FireServer()
	end)
end)

stageFx.OnClientEvent:Connect(function(fxName)
	if fxName == "spark" or fxName == "confetti" then
		firePyro(fxName, 0.5)
	elseif fxName == "smoke" then
		fireFog(1)
		task.delay(6, function()
			fireFog(0.2)
		end)
	elseif fxName == "strobe" then
		applyPreset("drop")
		task.delay(4, function()
			if not current then
				applyPreset("house")
			end
		end)
	elseif fxName == "spotlight" then
		applyPreset("intro")
	end
end)

RunService.RenderStepped:Connect(function()
	local track = current
	if not track or not music.IsPlaying then
		return
	end
	local musicTime = music.TimePosition
	runCues(musicTime)

	local pulse = activePreset.beatPulse
	if pulse > 0 then
		local envelope = MusicClock.beatEnvelope(musicTime, track.bpm, 3)
		local factor = 1 + pulse * envelope
		for instance, base in lightBase do
			if instance:IsA("Light") then
				instance.Brightness = base * factor
			elseif instance:IsA("Beam") then
				instance.Transparency = NumberSequence.new(math.clamp(1 - base * factor * 0.5, 0, 1))
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(ShowConfig.Sync.driftCheckInterval)
		resync()
	end
end)

task.spawn(function()
	applyPreset("house")
	local ok, state = pcall(function()
		return showStateFn:InvokeServer()
	end)
	if ok and typeof(state) == "table" then
		ClientBus.emit(ClientBus.Topics.ShowStateChanged, state)
		if state.mode == "live" and state.songId and state.startTime then
			startTrack({
				songId = state.songId,
				startTime = state.startTime,
			})
		end
	end
end)
