--!nonstrict
-- Character movement: Game.WalkSpeed / Game.JumpPower (UseJumpPower = true) on spawn and after every respawn.
-- Respawns happen on the PlazaSpawn SpawnLocations, on the hub plateau (Layout.HubY). Fall rescue: the hub is a
-- plateau 40 studs above the field and the edge is walled off, but if a character ever ends up more than
-- Game.FallRescueDepth below Layout.HubY (glitched past the edge guard, flung by physics) it is put back on top of
-- a PlazaSpawn instead of being stranded on the field.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Game = require(Config:WaitForChild("Game"))
local Layout = require(Config:WaitForChild("Layout"))

local CharacterService = {}

local function applyHumanoid(humanoid: Humanoid)
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = Game.WalkSpeed
	humanoid.JumpPower = Game.JumpPower
end

local function onCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		applyHumanoid(humanoid)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Where a rescued character goes: on top of a PlazaSpawn (fallback: the plaza centre at HubY).
function CharacterService.RescuePosition(): Vector3
	local spawns = CollectionService:GetTagged("PlazaSpawn")
	local s = spawns[math.random(1, math.max(1, #spawns))]
	if s and s:IsA("BasePart") then
		return s.Position + Vector3.new(0, s.Size.Y / 2 + 3, 0)
	end
	local pl = Layout.Plaza
	return Vector3.new((pl.MinX + pl.MaxX) / 2, Layout.HubY + 3, pl.MinZ + 10)
end

local function rescueFallen()
	local limit = Layout.HubY - (Game.FallRescueDepth or 12)
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hrp:IsA("BasePart") and hum and hum.Health > 0 and hrp.Position.Y < limit then
			hrp.AssemblyLinearVelocity = Vector3.zero
			char:PivotTo(CFrame.new(CharacterService.RescuePosition()))
		end
	end
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(rescueFallen)
			if not ok then
				warn("[CharacterService] fall rescue: " .. tostring(err))
			end
		end
	end)
end

return CharacterService
