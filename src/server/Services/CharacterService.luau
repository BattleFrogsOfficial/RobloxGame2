--!nonstrict
-- Character movement: Game.WalkSpeed / Game.JumpPower (UseJumpPower = true) on spawn and after every respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Game"))

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

function CharacterService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return CharacterService
