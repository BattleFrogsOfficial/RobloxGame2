--!strict
-- Pure motion maths for the cutscene (Vector3 / CFrame only; Lune-tested by tools/tests/cutscene_path.luau).
--   Path.Flight(arc, handPos, seconds) -> FlightPath   ball position / velocity over the on-screen flight:
--       the server arc (Util/BallFlight) time-scaled to `seconds`, starting in the hand and blended into the
--       arc over Flight.HandBlend; Position(seconds) == arc.Land (== result.LandPos) exactly.
--   Path.Retarget(from, to, switchAt) -> FlightPath   blend an estimated flight into the real one
--   Path.Bounces(landPos, forward) -> Bounces         2-3 decaying hops after touchdown (Landing.*)
--   Path.BounceAt(bounces, t) -> Vector3
--   Path.Pose(t) -> { [joint]: Vector3 (radians) }   procedural throw pose (Config Pose keyframes)
--   Path.Estimate(state, elapsed, tutorial) -> (launch, land)   best guess while the ThrowResult is late
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local C = require(Config:WaitForChild("Cutscene"))
local Layout = require(Config:WaitForChild("Layout"))
local Game = require(Config:WaitForChild("Game"))
local BallFlight = require(Util:WaitForChild("BallFlight"))

local Path = {}

function Path.Smooth(x: number): number
	local k = math.clamp(x, 0, 1)
	return k * k * (3 - 2 * k)
end
local smooth = Path.Smooth

export type FlightPath = {
	Duration: number,
	Land: Vector3,
	Position: (t: number) -> Vector3,
	Velocity: (t: number) -> Vector3,
}

function Path.Flight(arc: BallFlight.Arc, handPos: Vector3?, seconds: number): FlightPath
	local dur = math.max(1e-3, seconds)
	local scale = arc.Duration / dur
	local offset = if handPos then handPos - arc.Launch else Vector3.zero
	local blend = math.clamp(C.Flight.HandBlend, 1e-3, dur)
	local function position(t: number): Vector3
		local tt = math.clamp(t, 0, dur)
		if tt >= dur then
			return arc.Land
		end
		return arc.Position(tt * scale) + offset * (1 - smooth(tt / blend))
	end
	local function velocity(t: number): Vector3
		local tt = math.clamp(t, 0, dur)
		local v = arc.VelocityAt(tt * scale) * scale
		if tt < blend then
			-- d/dt of offset * (1 - smooth(t / blend))
			local x = tt / blend
			v -= offset * (6 * x * (1 - x) / blend)
		end
		return v
	end
	return { Duration = dur, Land = arc.Land, Position = position, Velocity = velocity }
end

-- From `from` to `to`, blending over Flight.RetargetBlend starting at `switchAt` (clamped so it is complete
-- by the end of the flight). Duration and landing are `to`'s.
function Path.Retarget(from: FlightPath, to: FlightPath, switchAt: number): FlightPath
	local dur = to.Duration
	local span = math.max(1e-3, math.min(C.Flight.RetargetBlend, dur - switchAt))
	local function w(t: number): number
		if t >= dur then
			return 1
		end
		return smooth((t - switchAt) / span)
	end
	local function position(t: number): Vector3
		local k = w(t)
		if k >= 1 then
			return to.Position(t)
		end
		return from.Position(t):Lerp(to.Position(t), k)
	end
	local function velocity(t: number): Vector3
		local k = w(t)
		return from.Velocity(t):Lerp(to.Velocity(t), k)
	end
	return { Duration = dur, Land = to.Land, Position = position, Velocity = velocity }
end

export type Hop = { T0: number, T1: number, From: Vector3, To: Vector3, Height: number }
export type Bounces = { Hops: { Hop }, Duration: number, Rest: Vector3 }

function Path.Bounces(landPos: Vector3, forward: Vector3): Bounces
	local L = C.Landing
	local flat = Vector3.new(forward.X, 0, forward.Z)
	local dir = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, 1)
	local hops: { Hop } = {}
	local t, pos = 0, landPos
	for i = 1, math.max(0, L.Bounces) do
		local h = L.BounceHeight * L.BounceDecay ^ (i - 1)
		local len = L.BounceTime * math.sqrt(L.BounceDecay) ^ (i - 1)
		local roll = L.BounceRoll * L.BounceDecay ^ (i - 1)
		local nextPos = pos + dir * roll
		table.insert(hops, { T0 = t, T1 = t + len, From = pos, To = nextPos, Height = h })
		t += len
		pos = nextPos
	end
	return { Hops = hops, Duration = t, Rest = pos }
end

function Path.BounceAt(b: Bounces, t: number): Vector3
	for _, hop in b.Hops do
		if t < hop.T1 then
			local k = math.clamp((t - hop.T0) / (hop.T1 - hop.T0), 0, 1)
			return hop.From:Lerp(hop.To, k) + Vector3.new(0, 4 * hop.Height * k * (1 - k), 0)
		end
	end
	return b.Rest
end

-- Procedural throw pose at t seconds after the meter release (Config Pose keyframes, smoothstep between keys).
Path.Joints = { "Waist", "RightShoulder", "RightElbow", "LeftShoulder", "LeftHip", "LeftKnee", "RightHip", "RightKnee" }
function Path.PoseLength(): number
	local keys = C.Pose
	return keys[#keys].At * C.WindUp.Duration
end

function Path.Pose(t: number): { [string]: Vector3 }
	local keys = C.Pose
	local x = t / C.WindUp.Duration
	local a, b = keys[1], keys[#keys]
	if x <= keys[1].At then
		b = keys[1]
	elseif x >= keys[#keys].At then
		a = keys[#keys]
	else
		for i = 1, #keys - 1 do
			if x >= keys[i].At and x < keys[i + 1].At then
				a, b = keys[i], keys[i + 1]
				break
			end
		end
	end
	local k = if b.At > a.At then smooth((x - a.At) / (b.At - a.At)) else 1
	local out: { [string]: Vector3 } = {}
	for _, j in Path.Joints do
		local va = (a :: any)[j] or { 0, 0, 0 }
		local vb = (b :: any)[j] or { 0, 0, 0 }
		out[j] = Vector3.new(
			math.rad(va[1] + (vb[1] - va[1]) * k),
			math.rad(va[2] + (vb[2] - va[2]) * k),
			math.rad(va[3] + (vb[3] - va[3]) * k)
		)
	end
	return out
end

-- Best-guess endpoints while the ThrowResult is late: the server's own distance formula without scatter
-- (PlayerStats.ThrowDistance with the meter Quality for `elapsed`). Display only; never sent anywhere.
function Path.Estimate(throwPower: number, rangeMult: number, quality: number, throwerX: number): (Vector3, Vector3)
	local maxD = Layout.Field.MaxZ - Layout.ThrowLine.Z
	local d = math.clamp(throwPower * rangeMult * quality, Game.Throw.MinDistance, maxD)
	local spot = Layout.Platform.ThrowSpot
	local cx = (Layout.Field.MinX + Layout.Field.MaxX) / 2
	local landX = cx + (throwerX - cx) * C.Fallback.EstimateLaneX
	return BallFlight.Endpoints(spot, spot.Y + Game.Throw.LaunchHeight, Layout.ThrowLine.Z, Layout.GroundY, d, landX)
end

-- Endpoints for a ThrowResult (falls back to the layout when an older server sends no LaunchPos / LandPos).
function Path.Endpoints(result: any): (Vector3, Vector3)
	local launch, land = result.LaunchPos, result.LandPos
	local spot = Layout.Platform.ThrowSpot
	if typeof(launch) ~= "Vector3" then
		launch = Vector3.new(spot.X, spot.Y + Game.Throw.LaunchHeight, spot.Z)
	end
	if typeof(land) ~= "Vector3" then
		land = Vector3.new(launch.X, Layout.GroundY, Layout.DistanceToZ(tonumber(result.Distance) or 0))
	end
	return launch, land
end

return Path
