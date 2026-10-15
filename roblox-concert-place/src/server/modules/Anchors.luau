--!strict
-- Точки телепортации на карте. Ожидаемая структура:
-- Workspace/StageAnchors/{PerformerSpot, AudienceSpot, VipSpot, FrontRowSpot}
-- Любая из них — обычная Part с Anchored = true и Transparency = 1.

local Workspace = game:GetService("Workspace")

local Anchors = {}

local warned: { [string]: boolean } = {}

function Anchors.get(name: string): BasePart?
	local folder = Workspace:FindFirstChild("StageAnchors")
	local part = folder and folder:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	if not warned[name] then
		warned[name] = true
		warn(string.format("[Anchors] не найден StageAnchors/%s", name))
	end
	return nil
end

function Anchors.teleport(player: Player, anchorName: string, spread: number?): boolean
	local anchor = Anchors.get(anchorName)
	local character = player.Character
	if not anchor or not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	local radius = spread or 0
	local offset = Vector3.new((math.random() - 0.5) * 2 * radius, 3, (math.random() - 0.5) * 2 * radius)
	character:PivotTo(anchor.CFrame + offset)
	return true
end

return Anchors
