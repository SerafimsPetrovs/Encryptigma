--!strict
-- Открытая сцена: очередь, слоты, оплата, модерация.
-- Кредит списывается в момент выхода на сцену, а не при покупке: если игрок не дождался
-- очереди или шоу прервало слот, оплаченный выход остаётся у него на аккаунте.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicClock = require(Shared.MusicClock)
local Net = require(Shared.Net)
local ShowConfig = require(Shared.ShowConfig)

local Anchors = require(script.Parent.Anchors)
local Monetization = require(script.Parent.Monetization)
local Profiles = require(script.Parent.Profiles)
local SafeText = require(script.Parent.SafeText)
local ShowDirector = require(script.Parent.ShowDirector)

local stageState = Net.event(Net.Names.StageState)
local queueState = Net.event(Net.Names.QueueState)
local stageFx = Net.event(Net.Names.StageFx)
local toast = Net.event(Net.Names.Toast)
local crowdReaction = Net.unreliable(Net.Names.CrowdReaction)

local joinQueue = Net.event(Net.Names.JoinStageQueue)
local leaveQueue = Net.event(Net.Names.LeaveStageQueue)
local buySlot = Net.event(Net.Names.BuyStageSlot)
local setStageName = Net.event(Net.Names.SetStageName)
local performerFx = Net.event(Net.Names.PerformerFx)
local sendReaction = Net.unreliable(Net.Names.SendReaction)
local adminCommand = Net.event(Net.Names.AdminCommand)

local ALLOWED_FX = {
	spark = true,
	smoke = true,
	strobe = true,
	confetti = true,
	spotlight = true,
}

local StageQueue = {}

local queue: { number } = {}
local stageNames: { [number]: string } = {}
local performer: number? = nil
local slotEndsAt: number? = nil
local applause = 0
local fxBudget: { [number]: number } = {}
local priority: { [number]: boolean } = {}

local function indexOf(userId: number): number?
	for index, id in queue do
		if id == userId then
			return index
		end
	end
	return nil
end

local function broadcastStage()
	stageState:FireAllClients({
		performerUserId = performer,
		stageName = if performer then stageNames[performer] else nil,
		endsAt = slotEndsAt,
		queueSize = #queue,
		applause = applause,
		open = not ShowDirector.isLive(),
	})
end

local function pushQueueState(player: Player)
	local profile = Profiles.peek(player.UserId)
	queueState:FireClient(player, {
		position = indexOf(player.UserId),
		credits = profile.stageCredits,
		queueSize = #queue,
	})
end

local function pushQueueStateAll()
	for _, player in Players:GetPlayers() do
		pushQueueState(player)
	end
end

local function notify(player: Player, message: string)
	toast:FireClient(player, message)
end

local function endSlot(reason: string)
	local current = performer
	performer = nil
	slotEndsAt = nil

	if current then
		if applause > 0 then
			local earned = applause
			applause = 0
			task.spawn(Profiles.applyDelta, current, { applause = earned })
		end
		local player = Players:GetPlayerByUserId(current)
		if player then
			Anchors.teleport(player, "AudienceSpot", 12)
			notify(
				player,
				if reason == "moderated"
					then "Выступление остановлено модератором."
					else "Спасибо за выступление!"
			)
		end
	end

	broadcastStage()
	pushQueueStateAll()
end

local function startSlot(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	if not Profiles.consumeStageCredit(userId) then
		notify(player, "Не удалось списать выход на сцену, попробуй ещё раз.")
		pushQueueState(player)
		return
	end

	performer = userId
	applause = 0
	-- endsAt уходит на клиент, поэтому считаем по общим часам, а не по uptime сервера.
	slotEndsAt = MusicClock.now() + ShowConfig.Stage.slotSeconds
	Profiles.markSlotUsed(userId)

	if not Anchors.teleport(player, "PerformerSpot") then
		notify(player, "Сцена не настроена: нет точки PerformerSpot.")
	end

	broadcastStage()
	pushQueueStateAll()
end

local function requestJoin(player: Player)
	local userId = player.UserId

	if ShowDirector.isLive() then
		notify(player, "Сейчас идёт концерт. Открытая сцена откроется после шоу.")
		return
	end
	if performer == userId or indexOf(userId) then
		notify(player, "Ты уже в очереди.")
		return
	end
	if #queue >= ShowConfig.Stage.queueCap then
		notify(player, "Очередь заполнена, попробуй чуть позже.")
		return
	end
	local cooldownLeft = ShowConfig.Stage.slotCooldownSeconds - Profiles.secondsSinceSlot(userId)
	if cooldownLeft > 0 then
		notify(player, string.format("Следующий выход можно занять через %d сек.", math.ceil(cooldownLeft)))
		return
	end
	if Profiles.peek(userId).stageCredits <= 0 then
		Monetization.promptProduct(player, ShowConfig.Products.StageSlot)
		return
	end

	if StageQueue.hasPriority(userId) then
		table.insert(queue, 1, userId)
	else
		table.insert(queue, userId)
	end
	notify(player, string.format("Ты в очереди, место %d.", indexOf(userId) or #queue))
	broadcastStage()
	pushQueueStateAll()
end

local function requestLeave(player: Player)
	local index = indexOf(player.UserId)
	if index then
		table.remove(queue, index)
		notify(player, "Ты вышел из очереди, оплаченный выход остался на аккаунте.")
		broadcastStage()
		pushQueueStateAll()
	end
end

local function handleFx(player: Player, fxName: string)
	if performer ~= player.UserId then
		return
	end
	if typeof(fxName) ~= "string" or not ALLOWED_FX[fxName] then
		return
	end
	local now = os.clock()
	local windowStart = fxBudget[player.UserId] or 0
	local minInterval = 1 / ShowConfig.Stage.maxFxPerSecond
	if now - windowStart < minInterval then
		return
	end
	fxBudget[player.UserId] = now
	stageFx:FireAllClients(fxName)
end

local function handleStageName(player: Player, raw: string)
	task.spawn(function()
		local filtered = SafeText.forBroadcast(raw, player.UserId)
		if filtered then
			stageNames[player.UserId] = filtered
			broadcastStage()
		else
			notify(player, "Это имя не прошло фильтр, выбери другое.")
		end
	end)
end

local function handleAdmin(player: Player, command: string, argument: any)
	if not ShowConfig.Admins[player.UserId] then
		return
	end
	if command == "kickPerformer" then
		endSlot("moderated")
	elseif command == "startShow" and typeof(argument) == "string" then
		if performer then
			endSlot("show")
		end
		ShowDirector.startShow(argument)
	elseif command == "stopShow" then
		ShowDirector.stop()
	end
end

function StageQueue.start()
	joinQueue.OnServerEvent:Connect(requestJoin)
	leaveQueue.OnServerEvent:Connect(requestLeave)
	buySlot.OnServerEvent:Connect(function(player, bundle)
		local productId = if bundle == true then ShowConfig.Products.StageSlotBundle5 else ShowConfig.Products.StageSlot
		Monetization.promptProduct(player, productId)
	end)
	setStageName.OnServerEvent:Connect(handleStageName)
	performerFx.OnServerEvent:Connect(handleFx)
	adminCommand.OnServerEvent:Connect(handleAdmin)

	sendReaction.OnServerEvent:Connect(function(player, reactionId)
		if typeof(reactionId) ~= "string" or performer == nil or performer == player.UserId then
			return
		end
		applause += 1
		crowdReaction:FireAllClients(reactionId)
	end)

	-- Концерт всегда важнее открытой сцены: перформера мягко снимаем.
	ShowDirector.onChanged(function(state)
		if state.mode ~= "idle" and performer then
			endSlot("show")
		end
		broadcastStage()
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Ждём профиль из DataStore, иначе игрок увидит ноль оплаченных выходов.
		local deadline = os.clock() + 15
		while not Profiles.isLoaded(player.UserId) and os.clock() < deadline do
			task.wait(0.5)
		end
		if player.Parent then
			pushQueueState(player)
			broadcastStage()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local index = indexOf(player.UserId)
		if index then
			table.remove(queue, index)
		end
		stageNames[player.UserId] = nil
		fxBudget[player.UserId] = nil
		priority[player.UserId] = nil
		if performer == player.UserId then
			endSlot("left")
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if performer and slotEndsAt and MusicClock.now() >= slotEndsAt then
				endSlot("timeUp")
			end
			if not performer and not ShowDirector.isLive() and #queue > 0 then
				local nextUserId = table.remove(queue, 1)
				if nextUserId then
					startSlot(nextUserId)
				end
			end
		end
	end)
end

-- Чаевые нельзя передавать игроку в Robux: выручка идёт разработчику,
-- а перформер получает аплодисменты, то есть внутренний рейтинг.
function StageQueue.tipPerformer(fromUserId: number, amount: number)
	if not performer or performer == fromUserId then
		return
	end
	applause += amount
	broadcastStage()
end

function StageQueue.setPriority(userId: number)
	priority[userId] = true
end

-- Приоритет одноразовый: слот на разогреве не делает игрока вечно первым в очереди.
function StageQueue.hasPriority(userId: number): boolean
	if priority[userId] then
		priority[userId] = nil
		return true
	end
	return false
end

-- Вызывается из обработчика покупки: выдали кредит, сразу обновили UI.
function StageQueue.onCreditsGranted(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		pushQueueState(player)
		notify(player, "Выход на сцену добавлен. Нажми «В очередь».")
	end
end

return StageQueue
