--!strict
-- THE THROW ZONE rules, pure (no Roblox services) so the server, the client and the Lune tests share them.
-- docs/DESIGN.md §2 / §4. Geometry: Layout.ThrowZone (a brown strip at the cliff edge, MaxZ = the throw line).
--
--   ThrowZone.Contains(pos)          HumanoidRootPart position inside the zone? (XZ inside the rectangle grown by
--                                    Game.ThrowZone.EdgeMargin, and Y >= Layout.ThrowZone.Y - Game.ThrowZone.YTolerance)
--   ThrowZone.LaunchPos(rootPos)     where the ball leaves: (root X clamped into the zone, Y + LaunchHeight, ThrowLine.Z),
--                                    i.e. the cliff edge right in front of the thrower
--   ThrowZone.LandX(throwerX, u)     landing X for scatter u in [-1, 1]: half the thrower's offset from the field
--                                    centre + u * LateralScatter / 2, clamped to the middle half of the field (|x| <= 56)
--   ThrowZone.Begin(c) / Release(c) / Expired(c)   the charge rules (no turns: everyone in the zone throws at once)
local Config = script.Parent.Parent:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local Game = require(Config:WaitForChild("Game")) :: any

local ThrowZone = {}

function ThrowZone.Rect(): (number, number, number, number)
	local z = Layout.ThrowZone
	return z.MinX, z.MaxX, z.MinZ, z.MaxZ
end

function ThrowZone.Center(): Vector3
	local z = Layout.ThrowZone
	return Vector3.new((z.MinX + z.MaxX) / 2, z.Y, (z.MinZ + z.MaxZ) / 2)
end

function ThrowZone.Contains(pos: Vector3, margin: number?): boolean
	local z = Layout.ThrowZone
	local m = margin or Game.ThrowZone.EdgeMargin
	if pos.Y < z.Y - Game.ThrowZone.YTolerance then
		return false
	end
	return pos.X >= z.MinX - m and pos.X <= z.MaxX + m and pos.Z >= z.MinZ - m and pos.Z <= z.MaxZ + m
end

function ThrowZone.LaunchX(x: number): number
	local z = Layout.ThrowZone
	return math.clamp(x, z.MinX, z.MaxX)
end

function ThrowZone.LaunchPos(rootPos: Vector3): Vector3
	return Vector3.new(ThrowZone.LaunchX(rootPos.X), Layout.ThrowZone.Y + Game.Throw.LaunchHeight, Layout.ThrowLine.Z)
end

ThrowZone.LaneHalf = (Layout.Field.MaxX - Layout.Field.MinX) * 0.25 - 4 -- 56

function ThrowZone.LandX(throwerX: number, u: number): number
	local cx = (Layout.Field.MinX + Layout.Field.MaxX) / 2
	local half = ThrowZone.LaneHalf
	return math.clamp(cx + (throwerX - cx) * 0.5 + u * Game.Throw.LateralScatter * 0.5, cx - half, cx + half)
end

----------------------------------------------------------------------------------------------------
-- Charge rules. c = { InZone: boolean, Loaded: boolean, InFlight: boolean, ChargeStart: number?,
--   LastRelease: number?, Now: number }
-- Begin -> "start" | "restart" | nil, reason      (restart = the sweep restarts from 0: the charge timestamp resets)
-- Release -> "throw" | "cancel" | nil             (cancel = drop the charge, nothing is thrown)
-- Expired -> true when MaxChargeSeconds passed with no release (the server cancels silently, no auto-throw)
----------------------------------------------------------------------------------------------------
export type ChargeCtx = { InZone: boolean, Loaded: boolean?, InFlight: boolean?, ChargeStart: number?,
	LastRelease: number?, Now: number }

function ThrowZone.Begin(c: ChargeCtx): (string?, string)
	if c.Loaded == false then
		return nil, "loading"
	end
	if not c.InZone then
		return nil, "not in the throw zone"
	end
	if c.InFlight then
		return nil, "a throw is in flight"
	end
	if c.ChargeStart ~= nil then
		if c.Now - c.ChargeStart < Game.Throw.MinRestartSeconds then
			return nil, "restart too soon"
		end
		return "restart", "sweep restarted"
	end
	if c.Now - (c.LastRelease or -math.huge) < Game.Throw.MinSecondsBetweenThrows then
		return nil, "cooldown"
	end
	return "start", "charging"
end

function ThrowZone.Release(c: ChargeCtx): string?
	if c.ChargeStart == nil then
		return nil
	end
	if not c.InZone then
		return "cancel"
	end
	return "throw"
end

function ThrowZone.Expired(chargeStart: number, now: number): boolean
	return now - chargeStart >= Game.Throw.MaxChargeSeconds
end

return ThrowZone
