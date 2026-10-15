--!strict
-- Покупки. Два правила, которые нельзя нарушать:
-- 1) PurchaseGranted возвращаем только после успешной записи в DataStore, иначе NotProcessedYet;
-- 2) обработка идемпотентна по PurchaseId, повторная доставка того же чека не должна выдать товар дважды.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local receiptStore = DataStoreService:GetDataStore("ConcertReceipts_v1")

export type Handler = (userId: number, receiptInfo: any) -> boolean

local Monetization = {}

local handlers: { [number]: Handler } = {}
local passCache: { [string]: boolean } = {}

function Monetization.registerProduct(productId: number, handler: Handler)
	if productId == 0 then
		warn("[Monetization] продукт не сконфигурирован, id = 0")
		return
	end
	handlers[productId] = handler
end

local function receiptKey(purchaseId: string): string
	return "r_" .. tostring(purchaseId)
end

-- "claimed" - чек наш и ещё не обработан, "duplicate" - уже обработан, "error" - DataStore недоступен.
local function claimReceipt(info: any): string
	local duplicate = false
	local ok, err = pcall(function()
		receiptStore:UpdateAsync(receiptKey(info.PurchaseId), function(existing)
			if existing ~= nil then
				duplicate = true
				return nil -- nil отменяет запись
			end
			return { userId = info.PlayerId, productId = info.ProductId, at = os.time() }
		end)
	end)
	if not ok then
		warn("[Monetization] claimReceipt: " .. tostring(err))
		return "error"
	end
	return if duplicate then "duplicate" else "claimed"
end

local function releaseReceipt(info: any)
	pcall(function()
		receiptStore:RemoveAsync(receiptKey(info.PurchaseId))
	end)
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local status = claimReceipt(info)
	if status == "duplicate" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif status == "error" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = handlers[info.ProductId]
	if not handler then
		warn("[Monetization] неизвестный productId: " .. tostring(info.ProductId))
		releaseReceipt(info)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, info.PlayerId, info)
	if not ok or not granted then
		if not ok then
			warn("[Monetization] обработчик упал: " .. tostring(granted))
		end
		releaseReceipt(info)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.promptProduct(player: Player, productId: number)
	if productId == 0 then
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end

function Monetization.promptPass(player: Player, passId: number)
	if passId == 0 then
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, passId)
end

-- UserOwnsGamePassAsync — сетевой вызов, поэтому держим результат в кэше на время сессии.
function Monetization.ownsPass(player: Player, passId: number): boolean
	if passId == 0 then
		return false
	end
	local cacheKey = string.format("%d:%d", player.UserId, passId)
	local cached = passCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		warn("[Monetization] ownsPass: " .. tostring(owns))
		return false
	end
	passCache[cacheKey] = owns
	return owns
end

function Monetization.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if wasPurchased then
			passCache[string.format("%d:%d", player.UserId, passId)] = true
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local prefix = tostring(player.UserId) .. ":"
		for key in passCache do
			if string.sub(key, 1, #prefix) == prefix then
				passCache[key] = nil
			end
		end
	end)
end

return Monetization
