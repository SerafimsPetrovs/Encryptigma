--!strict
-- Точка входа серверной части. Здесь же собраны обработчики покупок,
-- чтобы все платные механики были видны в одном месте.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShowConfig = require(Shared.ShowConfig)

local modules = script.Parent:WaitForChild("modules")
local Monetization = require(modules.Monetization)
local Profiles = require(modules.Profiles)
local ShowDirector = require(modules.ShowDirector)
local StageQueue = require(modules.StageQueue)
local VipAccess = require(modules.VipAccess)

local function grantStageSlots(userId: number, amount: number): boolean
	if not Profiles.grantStageCredits(userId, amount) then
		return false
	end
	StageQueue.onCreditsGranted(userId)
	return true
end

Monetization.registerProduct(ShowConfig.Products.StageSlot, function(userId)
	return grantStageSlots(userId, 1)
end)

Monetization.registerProduct(ShowConfig.Products.StageSlotBundle5, function(userId)
	return grantStageSlots(userId, 5)
end)

Monetization.registerProduct(ShowConfig.Products.PrimeTimeSlot, function(userId)
	if not grantStageSlots(userId, 1) then
		return false
	end
	StageQueue.setPriority(userId)
	return true
end)

Monetization.registerProduct(ShowConfig.Products.FrontRowTicket, function(userId)
	return Profiles.applyDelta(userId, { frontRowTickets = 1 }) ~= nil
end)

Monetization.registerProduct(ShowConfig.Products.TipSmall, function(userId)
	StageQueue.tipPerformer(userId, 10)
	return true
end)

Monetization.registerProduct(ShowConfig.Products.TipLarge, function(userId)
	StageQueue.tipPerformer(userId, 100)
	return true
end)

Profiles.start()
ShowDirector.start()
StageQueue.start()
VipAccess.start()
Monetization.start()

if not ShowConfig.isConfigured() then
	warn("[Concert] soundId не заданы в ShowConfig.Songs — шоу запустится без звука")
end
