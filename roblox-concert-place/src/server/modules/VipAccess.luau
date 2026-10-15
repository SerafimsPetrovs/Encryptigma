--!strict
-- Доступ в платные зоны. Проверка всегда на сервере: клиент только просит,
-- телепортирует сервер. Иначе зону открывает любой эксплойт.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local ShowConfig = require(Shared.ShowConfig)

local Anchors = require(script.Parent.Anchors)
local Monetization = require(script.Parent.Monetization)
local Profiles = require(script.Parent.Profiles)
local ShowDirector = require(script.Parent.ShowDirector)

local requestVip = Net.event(Net.Names.RequestVip)
local toast = Net.event(Net.Names.Toast)

local VipAccess = {}

local touchDebounce: { [number]: number } = {}
local frontRowUsedFor: { [number]: string } = {}

local function admit(player: Player, zone: string)
	if zone == "vip" then
		if Monetization.ownsPass(player, ShowConfig.Passes.Vip) then
			Anchors.teleport(player, "VipSpot", 8)
		else
			Monetization.promptPass(player, ShowConfig.Passes.Vip)
		end
		return
	end

	if zone == "frontRow" then
		local state = ShowDirector.getState()
		local showKey = (state.showId or "open") .. ":" .. tostring(state.trackIndex > 0)
		if frontRowUsedFor[player.UserId] == showKey then
			Anchors.teleport(player, "FrontRowSpot", 6)
			return
		end
		if Profiles.peek(player.UserId).frontRowTickets > 0 then
			if Profiles.applyDelta(player.UserId, { frontRowTickets = -1 }) then
				frontRowUsedFor[player.UserId] = showKey
				Anchors.teleport(player, "FrontRowSpot", 6)
				toast:FireClient(player, "Билет в первый ряд активирован.")
			else
				toast:FireClient(player, "Не удалось активировать билет, попробуй ещё раз.")
			end
		else
			Monetization.promptProduct(player, ShowConfig.Products.FrontRowTicket)
		end
	end
end

function VipAccess.start()
	requestVip.OnServerEvent:Connect(function(player, zone)
		if typeof(zone) ~= "string" then
			return
		end
		admit(player, zone)
	end)

	-- Физические турникеты: Part с тегом VipGate или FrontRowGate.
	local function hookGate(part: Instance, zone: string)
		if not part:IsA("BasePart") then
			return
		end
		part.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			local now = os.clock()
			if now - (touchDebounce[player.UserId] or 0) < 2 then
				return
			end
			touchDebounce[player.UserId] = now
			admit(player, zone)
		end)
	end

	for _, part in CollectionService:GetTagged("VipGate") do
		hookGate(part, "vip")
	end
	for _, part in CollectionService:GetTagged("FrontRowGate") do
		hookGate(part, "frontRow")
	end
	CollectionService:GetInstanceAddedSignal("VipGate"):Connect(function(part)
		hookGate(part, "vip")
	end)
	CollectionService:GetInstanceAddedSignal("FrontRowGate"):Connect(function(part)
		hookGate(part, "frontRow")
	end)

	Players.PlayerRemoving:Connect(function(player)
		touchDebounce[player.UserId] = nil
		frontRowUsedFor[player.UserId] = nil
	end)
end

return VipAccess
