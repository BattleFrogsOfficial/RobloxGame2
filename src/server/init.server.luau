-- Server entry point: builds the world, starts every system, and routes UI
-- actions from the client (all validated here, never trusted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local World = require(script.World)
local Data = require(script.Data)
local Pens = require(script.Pens)
local Split = require(script.Split)
local Training = require(script.Training)
local Shop = require(script.Shop)
local Rewards = require(script.Rewards)

World.build()
Split.makeStaff()
Pens.init()
Split.init()
Training.init()
Shop.init()
Rewards.init()
Data.init() -- last: starts loading players once every listener is hooked up

local actions = {
	BuyLuck = function(player, times)
		return Shop.buyLuck(player, if type(times) == "number" then times else 1)
	end,
	BuyWeight = function(player)
		return Training.buyWeight(player)
	end,
	UpgradeBase = function(player)
		return Pens.upgradeBase(player)
	end,
	PlaceEgg = function(player, index)
		if type(index) ~= "number" then
			return false
		end
		return Pens.placeStoredEgg(player, index)
	end,
	SellEgg = function(player, index)
		if type(index) ~= "number" then
			return false
		end
		return Pens.sellStoredEgg(player, index)
	end,
	PlaceAnimal = function(player, uid)
		if type(uid) ~= "number" then
			return false
		end
		return Pens.placeStoredAnimal(player, uid)
	end,
	StoreAnimal = function(player, key)
		if type(key) ~= "string" then
			return false
		end
		return Pens.storeAnimal(player, key)
	end,
	SellAnimal = function(player, where, id)
		if where ~= "pen" and where ~= "storage" then
			return false
		end
		return Pens.sellAnimal(player, where, id)
	end,
	PlaceBest = function(player)
		return Pens.placeBest(player)
	end,
	SellAllStored = function(player)
		return Pens.sellAllStored(player)
	end,
	HatchAll = function(player)
		local n = Pens.hatchAllReady(player)
		return n > 0
	end,
	ClaimPlaytime = function(player, i)
		if type(i) ~= "number" then
			return false
		end
		return Rewards.claimPlaytime(player, i)
	end,
	ClaimDaily = function(player)
		return Rewards.claimDaily(player)
	end,
	ClaimIndex = function(player, animalId)
		if type(animalId) ~= "string" then
			return false
		end
		return Rewards.claimIndex(player, animalId)
	end,
	TeleportHome = function(player)
		Pens.teleportHome(player)
		return true
	end,
	TeleportShore = function(player)
		local char = player.Character
		local pen = Pens.get(player)
		if char and pen then
			local x = pen.cf.Position.X
			local side = pen.side
			local pos = Vector3.new(x, 4, side * 122)
			char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, -side)))
		end
		return true
	end,
	StudioGrant = function(player, kind, key)
		if type(kind) ~= "string" or type(key) ~= "string" then
			return false
		end
		return Shop.studioGrant(player, kind, key)
	end,
}

local lastAction: { [Player]: number } = {}

Remotes.get("Action").OnServerInvoke = function(player: Player, name: any, ...)
	if type(name) ~= "string" or not actions[name] or not Data.get(player) then
		return false
	end
	local t = os.clock()
	if lastAction[player] and t - lastAction[player] < 0.08 then
		return false
	end
	lastAction[player] = t
	local ok, result, msg = pcall(actions[name], player, ...)
	if not ok then
		warn("[Action] " .. name .. " failed:", result)
		return false
	end
	return result, msg
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)
