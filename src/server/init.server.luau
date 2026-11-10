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
local Leaderboards = require(script.Leaderboards)

-- Start each system on its own so one failure can't stop the rest; any
-- error shows in the Output window with the system's name.
local function start(name: string, fn: () -> ())
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn("[Startup] " .. name .. " failed:\n" .. tostring(err))
	end
end

start("Sea Staff", Split.makeStaff)
start("World", World.build)
start("Pens", Pens.init)
start("Split", Split.init)
start("Training", Training.init)
start("Shop", Shop.init)
start("Rewards", Rewards.init)
start("Leaderboards", Leaderboards.init)
start("Data", Data.init) -- last: starts loading players once every listener is hooked up

local actions = {
	BuyLuck = function(player, times)
		return Shop.buyLuck(player, if type(times) == "number" then times else 1)
	end,
	BuySpeed = function(player)
		return Shop.buySpeed(player)
	end,
	TeleportShop = function(player)
		local char = player.Character
		if char then
			char:PivotTo(World.ShopSpot)
		end
		return true
	end,
	BuyWeight = function(player)
		return Training.buyWeight(player)
	end,
	UpgradeBase = function(player)
		return Pens.upgradeBase(player)
	end,
	PlaceEgg = function(player, index, pos)
		if type(index) ~= "number" or typeof(pos) ~= "Vector3" or pos ~= pos then
			return false
		end
		return Pens.placeStoredEgg(player, index, pos)
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
	TeleportHome = function(player)
		Pens.teleportHome(player)
		return true
	end,
	TeleportShore = function(player)
		local char = player.Character
		local pen = Pens.get(player)
		if char and pen then
			local pos = Vector3.new(pen.cf.Position.X, 4, 10)
			char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
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
