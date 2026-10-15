--!strict
-- Весь HUD собирается кодом, чтобы макет жил в репозитории, а не только внутри .rbxl.
-- Кнопки ничего не решают сами: они отправляют запрос, решение всегда за сервером.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClientBus = require(Shared.ClientBus)
local MusicClock = require(Shared.MusicClock)
local Net = require(Shared.Net)
local ShowConfig = require(Shared.ShowConfig)

local player = Players.LocalPlayer

local joinQueue = Net.event(Net.Names.JoinStageQueue)
local leaveQueue = Net.event(Net.Names.LeaveStageQueue)
local buySlot = Net.event(Net.Names.BuyStageSlot)
local setStageName = Net.event(Net.Names.SetStageName)
local performerFx = Net.event(Net.Names.PerformerFx)
local sendReaction = Net.unreliable(Net.Names.SendReaction)
local requestVip = Net.event(Net.Names.RequestVip)
local stageState = Net.event(Net.Names.StageState)
local queueState = Net.event(Net.Names.QueueState)
local toast = Net.event(Net.Names.Toast)
local showStateFn = Net.fn(Net.Names.ShowState)

local ACCENT = Color3.fromRGB(255, 80, 160)
local PANEL = Color3.fromRGB(18, 18, 24)

local gui = Instance.new("ScreenGui")
gui.Name = "ConcertHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function panel(name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui
	corner(frame, 10)
	return frame
end

local function label(parent: Instance, text: string, size: UDim2, textSize: number): TextLabel
	local instance = Instance.new("TextLabel")
	instance.BackgroundTransparency = 1
	instance.Size = size
	instance.Font = Enum.Font.GothamMedium
	instance.TextSize = textSize
	instance.TextColor3 = Color3.fromRGB(240, 240, 245)
	instance.TextXAlignment = Enum.TextXAlignment.Left
	instance.Text = text
	instance.Parent = parent
	return instance
end

local function button(parent: Instance, text: string, callback: () -> ()): TextButton
	local instance = Instance.new("TextButton")
	instance.Size = UDim2.new(1, 0, 0, 34)
	instance.BackgroundColor3 = ACCENT
	instance.BackgroundTransparency = 0.15
	instance.BorderSizePixel = 0
	instance.AutoButtonColor = true
	instance.Font = Enum.Font.GothamBold
	instance.TextSize = 14
	instance.TextColor3 = Color3.new(1, 1, 1)
	instance.Text = text
	instance.Parent = parent
	corner(instance, 8)
	instance.Activated:Connect(callback)
	return instance
end

-- Инфопанель сверху: до концерта — отсчёт, во время — что играет, вне шоу — кто на сцене.
local info = panel("Info", UDim2.new(0, 280, 0, 72), UDim2.new(0, 12, 0, 12), Vector2.new(0, 0))
local infoTitle = label(info, "Загрузка…", UDim2.new(1, -20, 0, 24), 16)
infoTitle.Position = UDim2.new(0, 10, 0, 8)
infoTitle.Font = Enum.Font.GothamBold
local infoSub = label(info, "", UDim2.new(1, -20, 0, 36), 13)
infoSub.Position = UDim2.new(0, 10, 0, 30)
infoSub.TextWrapped = true
infoSub.TextTransparency = 0.25

local actions = panel("Actions", UDim2.new(0, 200, 0, 190), UDim2.new(1, -12, 1, -12), Vector2.new(1, 1))
local actionsLayout = Instance.new("UIListLayout")
actionsLayout.Padding = UDim.new(0, 6)
actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionsLayout.Parent = actions
local actionsPadding = Instance.new("UIPadding")
actionsPadding.PaddingTop = UDim.new(0, 8)
actionsPadding.PaddingLeft = UDim.new(0, 8)
actionsPadding.PaddingRight = UDim.new(0, 8)
actionsPadding.Parent = actions

local stageSlotLabel = string.format("На сцену — %d R$", ShowConfig.Prices.stageSlot)

local stageButton = button(actions, stageSlotLabel, function()
	joinQueue:FireServer()
end)
stageButton.LayoutOrder = 1

local leaveButton = button(actions, "Выйти из очереди", function()
	leaveQueue:FireServer()
end)
leaveButton.LayoutOrder = 2
leaveButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
leaveButton.Visible = false

local vipButton = button(actions, "VIP-ярус", function()
	requestVip:FireServer("vip")
end)
vipButton.LayoutOrder = 3
vipButton.BackgroundColor3 = Color3.fromRGB(230, 180, 60)

local frontRowLabel = string.format("Первый ряд — %d R$", ShowConfig.Prices.frontRowTicket)

local frontRowButton = button(actions, frontRowLabel, function()
	requestVip:FireServer("frontRow")
end)
frontRowButton.LayoutOrder = 4
frontRowButton.BackgroundColor3 = Color3.fromRGB(80, 120, 230)

local cinemaButton = button(actions, "Режим съёмки (C)", function()
	ClientBus.emit("CinemaRequest", true)
end)
cinemaButton.LayoutOrder = 5
cinemaButton.BackgroundColor3 = Color3.fromRGB(40, 40, 50)

-- Реакции зала: единственный канал, где клиент стреляет часто,
-- поэтому он идёт через UnreliableRemoteEvent.
local reactions = panel("Reactions", UDim2.new(0, 200, 0, 40), UDim2.new(1, -12, 1, -212), Vector2.new(1, 1))
local reactionsLayout = Instance.new("UIListLayout")
reactionsLayout.FillDirection = Enum.FillDirection.Horizontal
reactionsLayout.Padding = UDim.new(0, 6)
reactionsLayout.Parent = reactions
local reactionsPadding = Instance.new("UIPadding")
reactionsPadding.PaddingTop = UDim.new(0, 6)
reactionsPadding.PaddingLeft = UDim.new(0, 6)
reactionsPadding.Parent = reactions

local REACTIONS = {
	{ id = "clap", text = "Хлопать" },
	{ id = "fire", text = "Огонь" },
	{ id = "heart", text = "Сердце" },
}

for _, reaction in REACTIONS do
	local instance = button(reactions, reaction.text, function()
		sendReaction:FireServer(reaction.id)
	end)
	instance.Size = UDim2.new(0, 60, 0, 28)
	instance.TextSize = 12
	instance.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
end

local performerPanel = panel("Performer", UDim2.new(0, 230, 0, 160), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1))
performerPanel.Visible = false
local performerTitle = label(performerPanel, "Ты на сцене", UDim2.new(1, -16, 0, 22), 15)
performerTitle.Position = UDim2.new(0, 8, 0, 6)
performerTitle.Font = Enum.Font.GothamBold

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -16, 0, 28)
nameBox.Position = UDim2.new(0, 8, 0, 30)
nameBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.GothamMedium
nameBox.TextSize = 13
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.PlaceholderText = "Имя на экране"
nameBox.Text = ""
nameBox.ClearTextOnFocus = false
nameBox.Parent = performerPanel
corner(nameBox, 6)
nameBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and #nameBox.Text > 0 then
		setStageName:FireServer(nameBox.Text)
	end
end)

local fxHolder = Instance.new("Frame")
fxHolder.BackgroundTransparency = 1
fxHolder.Size = UDim2.new(1, -16, 0, 90)
fxHolder.Position = UDim2.new(0, 8, 0, 64)
fxHolder.Parent = performerPanel
local fxLayout = Instance.new("UIGridLayout")
fxLayout.CellSize = UDim2.new(0, 66, 0, 26)
fxLayout.CellPadding = UDim2.new(0, 6, 0, 6)
fxLayout.Parent = fxHolder

local FX_BUTTONS = {
	{ id = "spark", text = "Искры" },
	{ id = "smoke", text = "Дым" },
	{ id = "strobe", text = "Строб" },
	{ id = "confetti", text = "Конфетти" },
	{ id = "spotlight", text = "Свет" },
}

for _, fx in FX_BUTTONS do
	local instance = button(fxHolder, fx.text, function()
		performerFx:FireServer(fx.id)
	end)
	instance.Size = UDim2.new(0, 66, 0, 26)
	instance.TextSize = 12
	instance.BackgroundColor3 = Color3.fromRGB(70, 60, 110)
end

local toastLabel = label(gui, "", UDim2.new(0, 420, 0, 28), 15)
toastLabel.Position = UDim2.new(0.5, 0, 0, 96)
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.TextXAlignment = Enum.TextXAlignment.Center
toastLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
toastLabel.Visible = false

local toastToken = 0
toast.OnClientEvent:Connect(function(message)
	if typeof(message) ~= "string" then
		return
	end
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message
	toastLabel.Visible = true
	task.delay(4, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end)

local credits = 0
local queuePosition: number? = nil
local performerUserId: number? = nil
local slotEndsAt: number? = nil
local nextShowAt: number? = nil
local clockOffset = 0
local showMode = "idle"
local showName: string? = nil
local stageOpen = true

local function refreshActions()
	leaveButton.Visible = queuePosition ~= nil
	if performerUserId == player.UserId then
		stageButton.Text = "Ты на сцене"
	elseif queuePosition then
		stageButton.Text = string.format("В очереди: %d", queuePosition)
	elseif not stageOpen then
		stageButton.Text = "Сцена занята шоу"
	elseif credits > 0 then
		stageButton.Text = string.format("В очередь (выходов: %d)", credits)
	else
		stageButton.Text = stageSlotLabel
	end
	performerPanel.Visible = performerUserId == player.UserId
end

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	if days > 0 then
		return string.format("%dд %dч", days, hours)
	elseif hours > 0 then
		return string.format("%dч %dмин", hours, minutes)
	end
	return string.format("%d:%02d", minutes, seconds % 60)
end

local function refreshInfo()
	if showMode == "live" then
		infoTitle.Text = "LIVE: " .. (showName or "концерт")
		infoSub.Text = "Включи режим съёмки (C) и снимай вертикальное видео"
	elseif performerUserId then
		local remaining = if slotEndsAt then slotEndsAt - MusicClock.now() else 0
		infoTitle.Text = "Открытая сцена"
		infoSub.Text = string.format("Выступает: %s · осталось %s", "игрок", formatDuration(remaining))
	elseif nextShowAt then
		local remaining = nextShowAt - (os.time() + clockOffset)
		infoTitle.Text = "Следующий концерт"
		infoSub.Text = "через " .. formatDuration(remaining)
	else
		infoTitle.Text = "Сцена свободна"
		infoSub.Text = "Выйди на сцену и устрой свой перформанс"
	end
end

stageState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	performerUserId = payload.performerUserId
	slotEndsAt = payload.endsAt
	stageOpen = payload.open ~= false
	if payload.stageName and performerUserId then
		infoSub.Text = "Выступает: " .. tostring(payload.stageName)
	end
	refreshActions()
	refreshInfo()
	ClientBus.emit(ClientBus.Topics.StageStateChanged, payload)
end)

queueState.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	credits = payload.credits or 0
	queuePosition = payload.position
	refreshActions()
	ClientBus.emit(ClientBus.Topics.QueueStateChanged, payload)
end)

ClientBus.on(ClientBus.Topics.CinemaToggled, function(state)
	gui.Enabled = state ~= true
end)

local function pullShowState()
	local ok, state = pcall(function()
		return showStateFn:InvokeServer()
	end)
	if ok and typeof(state) == "table" then
		showMode = state.mode or "idle"
		showName = state.showName
		nextShowAt = state.nextShowAt
		if typeof(state.serverOsTime) == "number" then
			clockOffset = state.serverOsTime - os.time()
		end
	end
	refreshInfo()
end

-- ShowRunner узнаёт о старте трека первым, поэтому HUD реагирует на него,
-- а не ждёт следующего опроса состояния.
ClientBus.on(ClientBus.Topics.ShowStateChanged, function(payload)
	if typeof(payload) == "table" and typeof(payload.mode) == "string" then
		showMode = payload.mode
		refreshInfo()
		task.spawn(pullShowState)
	end
end)

task.spawn(function()
	while true do
		pullShowState()
		task.wait(30)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		refreshInfo()
	end
end)

refreshActions()
