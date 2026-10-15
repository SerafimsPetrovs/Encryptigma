--!strict
-- Локальная шина событий внутри одного клиента: ShowRunner публикует кью,
-- CinemaMode и StageUI их слушают. Сеть здесь не участвует.

local ClientBus = {}

type Listener = (...any) -> ()

local listeners: { [string]: { Listener } } = {}

function ClientBus.on(topic: string, listener: Listener): () -> ()
	local bucket = listeners[topic]
	if not bucket then
		bucket = {}
		listeners[topic] = bucket
	end
	table.insert(bucket, listener)
	return function()
		local current = listeners[topic]
		if not current then
			return
		end
		local index = table.find(current, listener)
		if index then
			table.remove(current, index)
		end
	end
end

function ClientBus.emit(topic: string, ...: any)
	local bucket = listeners[topic]
	if not bucket then
		return
	end
	for _, listener in table.clone(bucket) do
		task.spawn(listener, ...)
	end
end

ClientBus.Topics = {
	CameraCue = "CameraCue",
	ShowStateChanged = "ShowStateChanged",
	StageStateChanged = "StageStateChanged",
	QueueStateChanged = "QueueStateChanged",
	CinemaToggled = "CinemaToggled",
	CrowdCue = "CrowdCue",
}

return ClientBus
