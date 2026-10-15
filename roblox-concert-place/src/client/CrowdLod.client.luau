--!strict
-- Массовка полностью клиентская: сервер о ней не знает, в сеть она не попадает.
-- Это главный приём, который позволяет показать «стадион на 20 тысяч» на 100 реальных игроках.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientBus = require(Shared.ClientBus)

local UPDATE_HZ = 15
local VISIBLE_RADIUS = 160
local NAME_DISTANCE = 40

local function deviceCap(): number
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if touchOnly then
		return 70
	end
	return 220
end

local template = ReplicatedStorage:FindFirstChild("Assets")
template = template and template:FindFirstChild("CrowdFan")

local folder = Instance.new("Folder")
folder.Name = "LocalCrowd"
folder.Parent = Workspace

type Fan = {
	part: BasePart,
	origin: CFrame,
	phase: number,
	amplitude: number,
}

local fans: { Fan } = {}
local jumpUntil = 0

local function randomPointIn(zone: BasePart): Vector3
	local size = zone.Size
	local offset = Vector3.new((math.random() - 0.5) * size.X, 0, (math.random() - 0.5) * size.Z)
	return (zone.CFrame * CFrame.new(offset)).Position + Vector3.new(0, size.Y / 2, 0)
end

-- Шаблон зрителя — одна BasePart (MeshPart-импостер): никаких скриптов,
-- Humanoid и физики внутри, иначе 200 зрителей съедят кадр.
local function spawnFan(position: Vector3)
	local instance: BasePart
	if template and template:IsA("BasePart") then
		instance = template:Clone()
	else
		-- Заглушка до появления арта, чтобы механика проверялась сразу.
		local block = Instance.new("Part")
		block.Size = Vector3.new(1.6, 4.4, 1)
		block.Color = Color3.fromRGB(40, 40, 55)
		block.Material = Enum.Material.SmoothPlastic
		instance = block
	end

	instance.Anchored = true
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	instance.CastShadow = false
	instance.Parent = folder

	local origin = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	instance.CFrame = origin
	table.insert(fans, {
		part = instance,
		origin = origin,
		phase = math.random() * math.pi * 2,
		amplitude = 0.25 + math.random() * 0.35,
	})
end

local function build()
	local zones = {}
	for _, zone in CollectionService:GetTagged("CrowdZone") do
		if zone:IsA("BasePart") then
			table.insert(zones, zone)
		end
	end
	if #zones == 0 then
		return
	end

	local cap = deviceCap()
	local perZone = math.max(1, math.floor(cap / #zones))
	for _, zone in zones do
		for _ = 1, perZone do
			spawnFan(randomPointIn(zone))
		end
		zone.Transparency = 1
		zone.CanCollide = false
	end
end

ClientBus.on(ClientBus.Topics.CrowdCue, function(preset)
	if preset == "jump" then
		jumpUntil = os.clock() + 2.5
	end
end)

-- Ники на расстоянии — заметная часть стоимости кадра на стадионе, поэтому прячем их.
local function tuneNameplates(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		humanoid.NameDisplayDistance = NAME_DISTANCE
		humanoid.HealthDisplayDistance = 0
	end
end

for _, other in Players:GetPlayers() do
	if other.Character then
		tuneNameplates(other.Character)
	end
	other.CharacterAdded:Connect(tuneNameplates)
end
Players.PlayerAdded:Connect(function(other)
	other.CharacterAdded:Connect(tuneNameplates)
end)

task.spawn(function()
	task.wait(2)
	build()

	while true do
		task.wait(1 / UPDATE_HZ)
		local camera = Workspace.CurrentCamera
		if camera then
			local cameraPosition = camera.CFrame.Position
			local now = os.clock()
			local jumping = now < jumpUntil
			for _, fan in fans do
				local distance = (fan.part.Position - cameraPosition).Magnitude
				-- Дальние зрители не шевелятся: вне плана разницы не видно.
				if distance <= VISIBLE_RADIUS then
					local wave = math.sin(now * (if jumping then 7 else 2.4) + fan.phase)
					local lift = if jumping then math.abs(wave) * 1.6 else wave * fan.amplitude
					fan.part.CFrame = fan.origin * CFrame.new(0, lift, 0) * CFrame.Angles(0, wave * 0.12, 0)
				end
			end
		end
	end
end)
