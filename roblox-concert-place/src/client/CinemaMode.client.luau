--!strict
-- Режим съёмки под TikTok: вертикальная рамка 9:16, выключенный интерфейс,
-- набор операторских движений и кнопка скриншота. Всё локально, на других игроков не влияет.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientBus = require(Shared.ClientBus)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
while not camera do
	task.wait()
	camera = Workspace.CurrentCamera
end
assert(camera, "нет CurrentCamera")

local PRESET_ORDER = { "crane-wide", "orbit-close", "dolly-in", "low-hero", "front-row" }

local dof = Lighting:FindFirstChild("CinemaDof") :: DepthOfFieldEffect?
if not dof then
	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "CinemaDof"
	dof.FarIntensity = 0.35
	dof.NearIntensity = 0
	dof.FocusDistance = 40
	dof.InFocusRadius = 25
	dof.Enabled = false
	dof.Parent = Lighting
end

local gui = Instance.new("ScreenGui")
gui.Name = "CinemaFrame"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function bar(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return frame
end

local leftBar = bar("Left")
leftBar.AnchorPoint = Vector2.new(0, 0)
leftBar.Position = UDim2.fromScale(0, 0)

local rightBar = bar("Right")
rightBar.AnchorPoint = Vector2.new(1, 0)
rightBar.Position = UDim2.fromScale(1, 0)

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, 0, 0, 24)
hint.Position = UDim2.new(0, 0, 1, -34)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(230, 230, 230)
hint.TextTransparency = 0.35
hint.Text = "C — выйти · ◀ ▶ — ракурс · P — скриншот"
hint.Parent = gui

-- Боковые полосы считаем от реального разрешения: центр всегда ровно 9:16.
local function layoutBars()
	local viewport = camera.ViewportSize
	local targetWidth = viewport.Y * 9 / 16
	local side = math.max(0, (viewport.X - targetWidth) / 2)
	leftBar.Size = UDim2.new(0, side, 1, 0)
	rightBar.Size = UDim2.new(0, side, 1, 0)
end

local active = false
local presetIndex = 1
local presetStartedAt = 0
local savedCameraType = camera.CameraType

local function targetCFrame(): CFrame
	local anchors = Workspace:FindFirstChild("StageAnchors")
	local spot = anchors and anchors:FindFirstChild("PerformerSpot")

	-- Если на сцене кто-то есть, снимаем его, иначе — центр сцены.
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and spot and spot:IsA("BasePart") then
			if (root.Position - spot.Position).Magnitude < 25 then
				return root.CFrame
			end
		end
	end

	if spot and spot:IsA("BasePart") then
		return spot.CFrame
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame
	end
	return CFrame.new(0, 10, 0)
end

type Shot = (target: CFrame, elapsed: number) -> CFrame

local shots: { [string]: Shot } = {
	["crane-wide"] = function(target, elapsed)
		local height = 22 - math.min(elapsed * 1.2, 12)
		local distance = 48 - math.min(elapsed * 1.5, 16)
		local position = target.Position + Vector3.new(0, height, 0) + target.LookVector * -distance
		return CFrame.lookAt(position, target.Position + Vector3.new(0, 4, 0))
	end,
	["orbit-close"] = function(target, elapsed)
		local angle = elapsed * 0.35
		local offset = Vector3.new(math.cos(angle) * 12, 4.5, math.sin(angle) * 12)
		return CFrame.lookAt(target.Position + offset, target.Position + Vector3.new(0, 3, 0))
	end,
	["dolly-in"] = function(target, elapsed)
		local distance = math.max(6, 26 - elapsed * 2.2)
		local position = target.Position + target.LookVector * -distance + Vector3.new(0, 5, 0)
		return CFrame.lookAt(position, target.Position + Vector3.new(0, 3.5, 0))
	end,
	["low-hero"] = function(target, elapsed)
		local sway = math.sin(elapsed * 0.6) * 3
		local position = target.Position + target.LookVector * -7 + Vector3.new(sway, 1.2, 0)
		return CFrame.lookAt(position, target.Position + Vector3.new(0, 6, 0))
	end,
	["front-row"] = function(target, elapsed)
		local sway = math.sin(elapsed * 1.6) * 0.4
		local position = target.Position + target.LookVector * -18 + Vector3.new(sway, 3 + sway * 0.2, 0)
		return CFrame.lookAt(position, target.Position + Vector3.new(0, 5, 0))
	end,
}

local function setPreset(name: string)
	local index = table.find(PRESET_ORDER, name)
	if index then
		presetIndex = index
	end
	presetStartedAt = os.clock()
end

local function setActive(state: boolean)
	if active == state then
		return
	end
	active = state
	gui.Enabled = state
	if dof then
		dof.Enabled = state
	end

	if state then
		layoutBars()
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		presetStartedAt = os.clock()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
	else
		camera.CameraType = savedCameraType
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
	end
	ClientBus.emit(ClientBus.Topics.CinemaToggled, state)
end

-- CaptureService даёт нативный шаринг скриншота на телефоне.
-- Обёрнуто в pcall: на старых клиентах часть методов может отсутствовать.
local function share()
	local ok, service = pcall(function()
		return game:GetService("CaptureService")
	end)
	if not ok or not service then
		return
	end
	local capture = service :: any
	pcall(function()
		capture:CaptureScreenshot(function(contentId: string)
			pcall(function()
				capture:PromptShareCapture(contentId, { source = "cinema" }, function() end)
			end)
		end)
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		setActive(not active)
	elseif active and input.KeyCode == Enum.KeyCode.P then
		share()
	elseif active and (input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.E) then
		presetIndex = presetIndex % #PRESET_ORDER + 1
		presetStartedAt = os.clock()
	elseif active and (input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Q) then
		presetIndex = (presetIndex - 2) % #PRESET_ORDER + 1
		presetStartedAt = os.clock()
	end
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutBars)

-- Кью «camera» из таймлайна шоу переключает ракурс автоматически:
-- любой игрок в режиме съёмки получает смену плана ровно на нужном такте.
ClientBus.on(ClientBus.Topics.CameraCue, function(preset)
	if active and typeof(preset) == "string" and shots[preset] then
		setPreset(preset)
	end
end)

ClientBus.on("CinemaRequest", function(state)
	setActive(state == true)
end)

ClientBus.on("CinemaShare", function()
	if active then
		share()
	end
end)

ClientBus.on("CinemaNextShot", function()
	if active then
		presetIndex = presetIndex % #PRESET_ORDER + 1
		presetStartedAt = os.clock()
	end
end)

RunService:BindToRenderStep("CinemaCamera", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
	if not active then
		return
	end
	local shot = shots[PRESET_ORDER[presetIndex]]
	if not shot then
		return
	end
	local goal = shot(targetCFrame(), os.clock() - presetStartedAt)
	-- Экспоненциальное сглаживание: движение не зависит от текущего FPS.
	local alpha = 1 - math.exp(-deltaTime * 4)
	camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end)
