--!strict
-- Server bootstrap: remotes -> world (agent D) -> services in dependency order.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes")) :: any
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game")) :: any

Remotes.Init()

-- 1. Build the world FIRST so every tagged part exists before services look for them.
local worldFolder = script.Parent:FindFirstChild("World")
local builder = worldFolder and worldFolder:FindFirstChild("WorldBuilder")
if builder and builder:IsA("ModuleScript") then
	local ok, err = pcall(function()
		local worldBuilder = require(builder) :: any
		worldBuilder.Build()
	end)
	if not ok then
		warn("[Main] WorldBuilder.Build() failed — the map may be incomplete: " .. tostring(err))
	end
else
	warn("[Main] ServerScriptService.Server.World.WorldBuilder is missing — no map will be built. "
		.. "Services fall back to Layout.luau coordinates.")
end

-- 2. Services. Order matters only for Start(); requires are acyclic.
local Services = script.Parent:WaitForChild("Services")
local ORDER = {
	"DataService",
	"CharacterService",
	"BroadcastService",
	"DogService",
	"BookService",
	"EventService",
	"ThrowService",
	"ShopService",
	"TrainingService",
	"LeaderboardService",
}
for _, name in ORDER do
	local mod = Services:FindFirstChild(name)
	if not mod then
		warn("[Main] missing service " .. name)
		continue
	end
	local ok, err = pcall(function()
		local service = require(mod) :: any
		if type(service.Start) == "function" then
			service.Start()
		end
	end)
	if not ok then
		warn(("[Main] %s failed to start: %s"):format(name, tostring(err)))
	end
end

print(("[%s] server started"):format(Game.Name))
