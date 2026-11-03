--!strict
-- Ball flight from the platform on the hub plateau down onto the field. Pure maths (only Vector3), shared by the
-- server (FlightTime in ThrowService's ThrowResult) and every client (src/client/BallFlight.client.luau and the
-- cutscene solve the SAME arc with ForThrow(LaunchPos, LandPos), so its Duration is exactly ThrowResult.FlightTime).
--
-- The horizontal landing distance is decided by the throw maths (PlayerStats.ThrowDistance, measured from
-- Layout.ThrowLine.Z) and is NOT changed by the height of the plateau: the arc starts at hand height on the deck
-- (Layout.ThrowLine.Y + Game.Throw.LaunchHeight = 44) and ends on the field (Layout.GroundY = 0) at that same
-- horizontal point. ForThrow keeps the throw itself as it was on flat ground (the same launch speed upward and the
-- same gravity as a hand-height throw over flat ground, BallFlight.ReferenceDrop, with the old pacing
-- DefaultFlightTime / DefaultApex) and ADDS THE DROP: the ball keeps falling past the hand height down the cliff,
-- so it stays in the air longer (and moves a little slower horizontally); it does not travel further.
-- The arc is a true ballistic parabola:
--   P(t) = Launch + Velocity * t - (0, Gravity * t^2 / 2, 0),   0 <= t <= Duration,   P(Duration) = Land
-- Horizontal speed is constant, so X and Z are linear (monotone) in t.
--
-- API
--   BallFlight.Solve(launchPos, landPos, params?) -> Arc
--     params = { ApexHeight: number?, FlightTime: number?, Gravity: number? }   (all optional)
--       ApexHeight + FlightTime  -> gravity is derived (both honoured exactly)
--       ApexHeight only          -> Gravity (default BallFlight.DefaultGravity), duration derived
--       FlightTime only          -> Gravity (default), launch angle derived
--       neither                  -> BallFlight.DefaultFlightTime(d) + BallFlight.DefaultApex(d), d = horizontal distance
--   BallFlight.ForThrow(launchPos, landPos) -> Arc            what the game uses (see FlatGravity: reference throw +
--                                                              the extra drop; Duration > DefaultFlightTime when dropping)
--   BallFlight.Endpoints(throwSpot, launchY, throwLineZ, groundY, distance, landX) -> (launchPos, landPos)
--     (the game passes launchY = Layout.ThrowLine.Y + Game.Throw.LaunchHeight = 44, groundY = Layout.GroundY = 0)
--   Arc = { Launch, Land, Duration, Gravity, Velocity (initial), ApexHeight (above launch), Apex (Vector3),
--           Position: (t) -> Vector3, VelocityAt: (t) -> Vector3 }   (t is clamped to [0, Duration])
local BallFlight = {}

BallFlight.DefaultGravity = 196.2
-- The flat-ground reference throw leaves the hand this far above where it lands (Game.Throw.LaunchHeight).
BallFlight.ReferenceDrop = 4

export type Params = { ApexHeight: number?, FlightTime: number?, Gravity: number? }
export type Arc = {
	Launch: Vector3,
	Land: Vector3,
	Duration: number,
	Gravity: number,
	Velocity: Vector3,
	ApexHeight: number,
	Apex: Vector3,
	Position: (t: number) -> Vector3,
	VelocityAt: (t: number) -> Vector3,
}

-- Base pacing by horizontal distance (0.7 s + d / 1800, 0.7..2.2 s); ForThrow adds the plateau -> field drop. The
-- cutscene remaps the resulting FlightTime into its on-screen flight (Config/Cutscene.luau Flight.ServerMin..Max).
function BallFlight.DefaultFlightTime(horizontalDistance: number): number
	return math.clamp(0.7 + horizontalDistance / 1800, 0.7, 2.2)
end

function BallFlight.DefaultApex(horizontalDistance: number): number
	return math.clamp(horizontalDistance * 0.22, 15, 260)
end

function BallFlight.Solve(launchPos: Vector3, landPos: Vector3, params: Params?): Arc
	local p: Params = params or {}
	local dx, dz = landPos.X - launchPos.X, landPos.Z - launchPos.Z
	local horiz = math.sqrt(dx * dx + dz * dz)
	local drop = launchPos.Y - landPos.Y -- 40 for the deck -> field
	local apexH = p.ApexHeight
	local T = p.FlightTime
	local g = p.Gravity or BallFlight.DefaultGravity
	if apexH == nil and T == nil then
		apexH = BallFlight.DefaultApex(horiz)
		T = BallFlight.DefaultFlightTime(horiz)
	end
	local vy: number
	if apexH ~= nil and T ~= nil then
		-- Both given: (T^2/2) s^2 - sqrt(2H) T s - D = 0 with s = sqrt(g)
		local H = math.max(apexH, -drop + 1e-3, 1e-3)
		local dur = math.max(T, 1e-3)
		local s = (math.sqrt(2 * H) + math.sqrt(2 * H + 2 * drop)) / dur
		g = s * s
		vy = math.sqrt(2 * g * H)
		apexH, T = H, dur
	elseif apexH ~= nil then
		local H = math.max(apexH, -drop + 1e-3, 0)
		vy = math.sqrt(2 * g * H)
		T = (vy + math.sqrt(math.max(0, vy * vy + 2 * g * drop))) / g
		apexH = H
	else
		local dur = math.max(T :: number, 1e-3)
		vy = (0.5 * g * dur * dur - drop) / dur
		apexH = if vy > 0 then vy * vy / (2 * g) else 0
		T = dur
	end
	local duration = T :: number
	local velocity = Vector3.new(dx / duration, vy, dz / duration)
	local gravity = g
	local function position(t: number): Vector3
		local tt = math.clamp(t, 0, duration)
		if tt >= duration then
			return landPos
		end
		return Vector3.new(
			launchPos.X + velocity.X * tt,
			launchPos.Y + velocity.Y * tt - 0.5 * gravity * tt * tt,
			launchPos.Z + velocity.Z * tt
		)
	end
	local function velocityAt(t: number): Vector3
		local tt = math.clamp(t, 0, duration)
		return Vector3.new(velocity.X, velocity.Y - gravity * tt, velocity.Z)
	end
	local tApex = math.clamp(vy / gravity, 0, duration)
	return {
		Launch = launchPos,
		Land = landPos,
		Duration = duration,
		Gravity = gravity,
		Velocity = velocity,
		ApexHeight = apexH :: number,
		Apex = position(tApex),
		Position = position,
		VelocityAt = velocityAt,
	}
end

-- Gravity of the flat-ground reference throw: the parabola that rises DefaultApex(d) above the hand and comes down
-- ReferenceDrop below it in exactly DefaultFlightTime(d).
function BallFlight.FlatGravity(horizontalDistance: number): number
	local H = BallFlight.DefaultApex(horizontalDistance)
	local T = BallFlight.DefaultFlightTime(horizontalDistance)
	local s = (math.sqrt(2 * H) + math.sqrt(2 * H + 2 * BallFlight.ReferenceDrop)) / T
	return s * s
end

-- The game's arc: the reference throw (same apex above the hand, same gravity) with the real drop from launchPos.Y
-- to landPos.Y. A drop of ReferenceDrop gives exactly DefaultFlightTime; a bigger drop (the cliff) a longer one.
function BallFlight.ForThrow(launchPos: Vector3, landPos: Vector3): Arc
	local dx, dz = landPos.X - launchPos.X, landPos.Z - launchPos.Z
	local horiz = math.sqrt(dx * dx + dz * dz)
	return BallFlight.Solve(launchPos, landPos, {
		ApexHeight = BallFlight.DefaultApex(horiz),
		Gravity = BallFlight.FlatGravity(horiz),
	})
end

-- Launch = the thrower's spot at launchY (hand height on the deck); land = (landX, groundY, throwLineZ + distance). The distance is
-- horizontal and measured from the throw line, exactly as before the platform was raised.
function BallFlight.Endpoints(throwSpot: Vector3, launchY: number, throwLineZ: number, groundY: number,
	distance: number, landX: number): (Vector3, Vector3)
	return Vector3.new(throwSpot.X, launchY, throwSpot.Z), Vector3.new(landX, groundY, throwLineZ + distance)
end

return BallFlight
