--!strict
-- Минимальный слой поверх RemoteEvent/RemoteFunction, чтобы не плодить ручное WaitForChild.
-- Сервер создаёт объекты, клиент их ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "ConcertNet"
local WAIT_TIMEOUT = 20

local Net = {}

local function root(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT) or ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(className: string, name: string): Instance
	local parent = root()
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
		return remote
	end
	return parent:WaitForChild(name)
end

function Net.event(name: string): RemoteEvent
	return get("RemoteEvent", name) :: RemoteEvent
end

-- Для косметики с высокой частотой (реакции зала, эмоции): дропнутый пакет не страшен.
function Net.unreliable(name: string): UnreliableRemoteEvent
	return get("UnreliableRemoteEvent", name) :: UnreliableRemoteEvent
end

function Net.fn(name: string): RemoteFunction
	return get("RemoteFunction", name) :: RemoteFunction
end

Net.Names = {
	-- сервер -> клиент
	TrackStarted = "TrackStarted", -- {songId, startTime, showId}
	TrackStopped = "TrackStopped",
	ShowState = "ShowState", -- RemoteFunction: состояние для подключившихся позже
	PreloadRequest = "PreloadRequest",
	StageState = "StageState", -- {performerUserId, stageName, endsAt, queueSize}
	StageFx = "StageFx", -- эффект, запущенный перформером
	QueueState = "QueueState", -- персонально: {position, credits}
	Toast = "Toast", -- короткое сообщение в UI
	CrowdReaction = "CrowdReaction", -- unreliable

	-- клиент -> сервер
	ClientReady = "ClientReady",
	BuyStageSlot = "BuyStageSlot",
	JoinStageQueue = "JoinStageQueue",
	LeaveStageQueue = "LeaveStageQueue",
	SetStageName = "SetStageName",
	PerformerFx = "PerformerFx",
	SendReaction = "SendReaction", -- unreliable
	RequestVip = "RequestVip",
	AdminCommand = "AdminCommand",
}

return Net
