--!strict
-- Dev tools maths + rules (pure; used by server/Services/DevService.luau, the client Dev panel and
-- tools/tests/devservice.luau). Config: Game.DevTools. docs/DESIGN.md §21.5.
--   DevTools.IsAllowed(cfg, isStudio, userId) -> boolean    the one permission gate
--   DevTools.GoodQuality() -> number                         the middle of the meter's Good band
--   DevTools.PowerForZone(zone, rangeMult) -> number         ThrowPower whose Good throw lands mid-zone
--   DevTools.MaxPower() -> number                            a Perfect Tennis throw reaches the field's end
--   DevTools.GoodReach(throwPower, rangeMult) -> (distance, zone)   what a Good throw reaches (no scatter)
--   DevTools.Validate(command, arg) -> (ok, err?)            argument checks for the DevCommand remote
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Game = require(Config:WaitForChild("Game"))
local Zones = require(Config:WaitForChild("Zones"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local DevTools = {}

DevTools.PowerSteps = { 100, 1000, 10000 } -- AddPower amounts the remote accepts
DevTools.CashAmount = 1_000_000 -- AddCash
DevTools.BallAmount = 10 -- GiveBalls: throws of each consumable ball
DevTools.MaxStoredPower = 1_000_000 -- sanity cap on repeated AddPower
DevTools.Commands = { AddPower = true, PowerForZone = true, MaxPower = true, ResetPower = true, AddCash = true, GiveBalls = true }

-- Enabled and (Studio, or a live server with StudioOnly = false and the UserId listed). In Studio everyone is a
-- dev; a live server never has dev tools unless StudioOnly is off AND the player's UserId is in cfg.UserIds.
function DevTools.IsAllowed(cfg: any, isStudio: boolean, userId: number): boolean
	if type(cfg) ~= "table" or cfg.Enabled ~= true then
		return false
	end
	if isStudio then
		return true
	end
	if cfg.StudioOnly ~= false or type(cfg.UserIds) ~= "table" then
		return false
	end
	for _, id in cfg.UserIds do
		if type(id) == "number" and id == userId and userId > 0 then
			return true
		end
	end
	return false
end

function DevTools.GoodQuality(): number
	local m = Game.Meter
	return (m.GoodQualityMin + m.GoodQualityMax) / 2
end

function DevTools.ZoneById(zoneId: any): any
	for _, z in Zones do
		if z.Id == zoneId then
			return z
		end
	end
	return nil
end

-- Distance = ThrowPower x RangeMult x Quality x (1 + scatter) (PlayerStats.ThrowDistance), so the power whose
-- mid-Good, no-scatter throw lands on the zone's middle is mid / (RangeMult x GoodQuality). Every Good release
-- (quality GoodQualityMin..Max, scatter +-Game.Throw.Scatter) then still lands inside the zone (devservice test).
function DevTools.PowerForZone(zone: any, rangeMult: number): number
	local maxD = PlayerStats.MaxFieldDistance()
	local mid = (zone.MinDistance + math.min(zone.MaxDistance, maxD)) / 2
	return math.floor(mid / (math.max(1e-6, rangeMult) * DevTools.GoodQuality()) + 0.5)
end

-- A Perfect (quality 1) Tennis throw (RangeMult 1) at the worst scatter still reaches the end of the field.
function DevTools.MaxPower(): number
	return math.ceil(PlayerStats.MaxFieldDistance() / (1 - Game.Throw.Scatter))
end

function DevTools.GoodReach(throwPower: number, rangeMult: number): (number, any)
	local d = PlayerStats.ThrowDistance(throwPower, rangeMult, DevTools.GoodQuality(), 0, Game.Throw.MinDistance)
	return d, PlayerStats.ZoneForDistance(d)
end

function DevTools.Validate(command: any, arg: any): (boolean, string?)
	if type(command) ~= "string" or not DevTools.Commands[command] then
		return false, "Unknown dev command"
	end
	if command == "AddPower" then
		if type(arg) ~= "number" or not table.find(DevTools.PowerSteps, arg) then
			return false, "AddPower takes 100, 1000 or 10000"
		end
	elseif command == "PowerForZone" then
		if type(arg) ~= "string" or #arg > 32 or DevTools.ZoneById(arg) == nil then
			return false, "Unknown zone"
		end
	elseif arg ~= nil then
		return false, command .. " takes no argument"
	end
	return true, nil
end

return DevTools
