--!nonstrict
-- Dev tools (Config/Game.DevTools; maths and rules in Shared/Util/DevTools). The DevCommand RemoteFunction is
-- refused unless DevTools.IsAllowed: Enabled and (Studio, or StudioOnly = false and the UserId listed), so a
-- published game has none of this unless a UserId is explicitly allowed. Allowed players get the "DevTools" player
-- attribute (the client shows its Dev pill only then). Dev power deliberately bypasses the training caps;
-- TrainingService never clamps it back down (Config/Training.ApplyRep), it just stops adding past the cap.
-- Every command is rate-limited, validated, logged to the output and followed by a StateUpdate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Config:WaitForChild("Game"))
local Balls = require(Config:WaitForChild("Balls"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local DevTools = require(Util:WaitForChild("DevTools"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local DevService = {}

local limiter = RateLimiter.new(Game.RateLimits.DevCommand[1], Game.RateLimits.DevCommand[2])

function DevService.IsAllowed(player: Player): boolean
	return DevTools.IsAllowed(Game.DevTools, RunService:IsStudio(), player.UserId)
end

local function setPower(state: any, power: number)
	state.ThrowPower = math.clamp(math.floor(power + 0.5), 1, DevTools.MaxStoredPower)
end

-- Runs one validated command. Returns ok, message.
function DevService.Run(player: Player, command: any, arg: any): (boolean, string)
	if not DevService.IsAllowed(player) then
		return false, "Dev tools are not available here"
	end
	local valid, err = DevTools.Validate(command, arg)
	if not valid then
		return false, err or "Bad dev command"
	end
	local state = DataService.Get(player)
	if not state then
		return false, "Data not loaded yet"
	end
	local msg: string
	if command == "AddPower" then
		setPower(state, state.ThrowPower + arg)
		msg = ("+%s ThrowPower"):format(FormatNumber.Compact(arg))
	elseif command == "PowerForZone" then
		local zone = DevTools.ZoneById(arg)
		local ball = PlayerStats.Ball(state)
		setPower(state, DevTools.PowerForZone(zone, ball.RangeMult))
		msg = ("A Good %s throw now lands in %s"):format(ball.Name, zone.Name)
	elseif command == "MaxPower" then
		setPower(state, DevTools.MaxPower())
		msg = "Max ThrowPower: a Perfect throw reaches the end of the field"
	elseif command == "ResetPower" then
		setPower(state, Game.StartingThrowPower)
		msg = "ThrowPower reset"
	elseif command == "AddCash" then
		state.Cash += DevTools.CashAmount
		msg = "+" .. FormatNumber.Money(DevTools.CashAmount)
	elseif command == "GiveBalls" then
		state.Balls = state.Balls or {}
		for _, id in Balls.Order do
			local ball = Balls.ById[id]
			if ball.Consumable then
				state.Balls[id] = math.min(Balls.MaxOwned, PlayerStats.BallCount(state, id) + DevTools.BallAmount)
			end
		end
		msg = ("+%d of every ball"):format(DevTools.BallAmount)
	else
		return false, "Unknown dev command"
	end
	print(("[DevService] %s (%d) %s %s -> ThrowPower %s, Cash %s"):format(player.Name, player.UserId, tostring(command),
		if arg ~= nil then tostring(arg) else "", tostring(state.ThrowPower), tostring(state.Cash)))
	DataService.Push(player)
	return true, msg
end

local function markPlayer(player: Player)
	if DevService.IsAllowed(player) then
		player:SetAttribute("DevTools", true)
	else
		player:SetAttribute("DevTools", nil)
	end
end

function DevService.Start()
	local remote = Remotes.Get("DevCommand") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, command: any, arg: any)
		if not DevService.IsAllowed(player) then
			return false, "Dev tools are not available here"
		end
		if not limiter:Check(player) then
			return false, "Slow down"
		end
		local ok, okRun, msg = pcall(DevService.Run, player, command, arg)
		if not ok then
			warn("[DevService] " .. tostring(okRun))
			return false, "Dev command failed"
		end
		return okRun, msg
	end
	Players.PlayerAdded:Connect(markPlayer)
	for _, player in Players:GetPlayers() do
		markPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:Clear(player)
	end)
	if RunService:IsStudio() and Game.DevTools.Enabled then
		print("[DevService] dev tools on (Studio): open the Dev pill on the HUD")
	end
end

return DevService
