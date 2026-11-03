--!nonstrict
-- Server-wide announcements via the Broadcast remote, plus cross-server relays (MessagingService)
-- for Legendary+ events. Publishes are throttled (one per MinPublishInterval) and queued messages
-- older than QueueDropAfter are dropped. Payload: {Kind, Text, Rarity?, Variant?, Global}.
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local BroadcastService = {}

local queue: { { Payload: any, At: number } } = {}
local lastPublish = 0
local subscribed = false

local function fireAll(payload: any)
	Remotes.Get("Broadcast"):FireAllClients(payload)
end

-- kind: "Catch" | "Miss" | "Squirrel" | "Recall" | "ServerLuck" | ...
function BroadcastService.Send(kind: string, text: string, rarity: string?, variant: string?, global: boolean?)
	local payload = { Kind = kind, Text = text, Rarity = rarity, Variant = variant, Global = false }
	fireAll(payload)
	if global and subscribed then
		table.insert(queue, { Payload = { Kind = kind, Text = text, Rarity = rarity, Variant = variant,
			JobId = game.JobId }, At = os.clock() })
	end
end

-- Personal notice to one player (Kind "Notice" unless given).
function BroadcastService.Notify(player: Player, text: string, kind: string?)
	Remotes.Get("Broadcast"):FireClient(player, { Kind = kind or "Notice", Text = text, Global = false })
end

local function pumpQueue()
	while true do
		task.wait(0.5)
		local now = os.clock()
		while #queue > 0 and now - queue[1].At > Game.Broadcast.QueueDropAfter do
			table.remove(queue, 1)
		end
		if #queue > 0 and now - lastPublish >= Game.Broadcast.MinPublishInterval then
			local item = table.remove(queue, 1)
			lastPublish = now
			local ok, err = pcall(function()
				MessagingService:PublishAsync(Game.Broadcast.Topic, item.Payload)
			end)
			if not ok then
				warn("[BroadcastService] publish failed: " .. tostring(err))
			end
		end
	end
end

function BroadcastService.Start()
	-- MessagingService only works in published places; in Studio the subscribe fails harmlessly.
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Game.Broadcast.Topic, function(message)
				local data = message.Data
				if type(data) ~= "table" or data.JobId == game.JobId then
					return
				end
				if type(data.Text) ~= "string" or #data.Text > 200 then
					return
				end
				fireAll({
					Kind = if type(data.Kind) == "string" then data.Kind else "Catch",
					Text = data.Text,
					Rarity = if type(data.Rarity) == "string" then data.Rarity else nil,
					Variant = if type(data.Variant) == "string" then data.Variant else nil,
					Global = true,
				})
			end)
		end)
		if ok then
			subscribed = true
		else
			warn("[BroadcastService] cross-server broadcasts disabled: " .. tostring(err))
		end
	end)
	task.spawn(pumpQueue)
end

return BroadcastService
