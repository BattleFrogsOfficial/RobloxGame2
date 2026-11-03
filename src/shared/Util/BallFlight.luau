--!strict
-- Ball flight from the raised throwing platform. Pure maths (only Vector3), shared by the server (flight
-- timing in ThrowService) and every client (src/client/BallFlight.client.luau renders the same arc).
--
-- The horizontal landing distance is decided by the throw maths (PlayerStats.ThrowDistance, measured from
-- Layout.ThrowLine.Z) and is NOT changed by the deck height: the arc simply starts at the deck
-- (Layout.ThrowLine.Y) and ends on the field (Y = 0) at that same horizontal point. The launch velocity is
-- solved for the drop, so the arc is a true ballistic parabola:
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
--   BallFlight.ForThrow(launchPos, landPos) -> Arc            (= Solve with the defaults; what the game uses)
--   BallFlight.Endpoints(throwSpot, deckY, throwLineZ, groundY, distance, landX) -> (launchPos, landPos)
--   Arc = { Launch, Land, Duration, Gravity, Velocity (initial), ApexHeight (above launch), Apex (Vector3),
--           Position: (t) -> Vector3, VelocityAt: (t) -> Vector3 }   (t is clamped to [0, Duration])
local BallFlight = {}

BallFlight.DefaultGravity = 196.2

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

-- Same pacing as the old flat throw line (CutsceneContract.FlightTime) so cutscene beats keep their timing.
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

function BallFlight.ForThrow(launchPos: Vector3, landPos: Vector3): Arc
	return BallFlight.Solve(launchPos, landPos, nil)
end

-- Launch = the thrower's spot at deck height; land = (landX, groundY, throwLineZ + distance). The distance is
-- horizontal and measured from the throw line, exactly as before the platform was raised.
function BallFlight.Endpoints(throwSpot: Vector3, deckY: number, throwLineZ: number, groundY: number,
	distance: number, landX: number): (Vector3, Vector3)
	return Vector3.new(throwSpot.X, deckY, throwSpot.Z), Vector3.new(landX, groundY, throwLineZ + distance)
end

return BallFlight
