--!strict
-- Pure camera maths for the cutscene shots (CFrame only; Lune-tested by tools/tests/cutscene_path.luau).
-- Roblox convention: a CFrame looks down its -Z (LookVector). `facing` = the thrower's flat forward.
--   Shots.Front(root, facing)                -> front shot: in front at chest height, low, looking at the face
--   Shots.Sweep(startCF, root, facing, a)    -> a in [0,1]: half circle from the default view to Front
--   Shots.Pov(ballPos, ballVel, reduced?)    -> just behind + above the ball, looking along its travel
--   Shots.Wide(landPos, forward)             -> high wide shot looking down at the landing spot
--   Shots.Toward(fromCF, target, share)      -> push-in: move `share` of the way toward `target`, keep looking at it
--   Shots.Follow(pos, travelDir)             -> behind a moving dog
--   Shots.Shake(t, seed, studs, degrees, length) -> decaying shake offset CFrame
--   Shots.QualityScale(quality)              -> release-shake multiplier (Impact.ShakeMinScale .. 1 at Perfect)
--   Shots.ImpactShake(t, seed, scale)        -> release shake: hard at t = 0, decays to zero over Impact.ShakeTime
--   Shots.SpeedShake(t, seed, speed)         -> low constant ball-POV shake scaled by the ball's speed
--   Shots.FovPunch(t)                        -> degrees added to the FOV after the release (0 -> peak -> 0)
--   Shots.BlurSize(speed, landing)           -> ball-POV BlurEffect.Size (clears as the ball slows / lands)
local Config = script.Parent.Parent:WaitForChild("Config")
local C = require(Config:WaitForChild("Cutscene"))

local Shots = {}

local UP = Vector3.new(0, 1, 0)

local function flat(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-6 then
		return fallback or Vector3.new(0, 0, 1)
	end
	return f.Unit
end
Shots.Flat = flat

-- CFrame looking from `pos` at `target` (same result as CFrame.lookAt, built with fromMatrix so the Lune test
-- runtime, whose lookAt differs, computes the same frames as Roblox).
local function lookAt(pos: Vector3, target: Vector3): CFrame
	local d = target - pos
	if d.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	local look = d.Unit
	local right = look:Cross(UP)
	if right.Magnitude < 1e-4 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local up = right:Cross(look)
	return CFrame.fromMatrix(pos, right, up, -look)
end
Shots.LookAt = lookAt

local function smooth(x: number): number
	local k = math.clamp(x, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Sine in-out, used for the sweep (gentle start and stop).
local function sine(x: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(x, 0, 1))
end
Shots.EaseInOut = sine

function Shots.Front(root: Vector3, facing: Vector3): CFrame
	local w = C.WindUp
	local fwd = flat(facing)
	local left = UP:Cross(fwd) -- facing +Z => left is +X... (player's left when looking along fwd)
	local pos = root + fwd * w.FrontDistance + left * w.FrontSide + UP * w.FrontHeight
	local face = root + UP * w.LookHeight
	return lookAt(pos, face)
end

local function yawOf(v: Vector3): number
	return math.atan2(v.X, v.Z)
end

-- Half circle around the player from startCF (the default camera, normally behind) to the front shot. The
-- angle travels from the camera's own yaw to the front's in SweepDirection (the other way if that would be
-- more than MaxSweepDegrees); radius, height and look target ease from the start values to the front's.
function Shots.SweepDelta(startYaw: number, endYaw: number): number
	local w = C.WindUp
	local twoPi = 2 * math.pi
	local d = (endYaw - startYaw) % twoPi -- 0..2pi, positive direction
	if w.SweepDirection < 0 then
		d -= twoPi -- -2pi..0
	end
	if math.abs(d) > math.rad(w.MaxSweepDegrees) then
		d = if d > 0 then d - twoPi else d + twoPi
	end
	return d
end

function Shots.Sweep(startCF: CFrame, root: Vector3, facing: Vector3, alpha: number): CFrame
	local w = C.WindUp
	local a = sine(alpha)
	local front = Shots.Front(root, facing)
	local startOff = startCF.Position - root
	local endOff = front.Position - root
	local r0 = math.max(2, Vector3.new(startOff.X, 0, startOff.Z).Magnitude)
	local r1 = Vector3.new(endOff.X, 0, endOff.Z).Magnitude
	local y0, y1 = startOff.Y, endOff.Y
	local yawStart = yawOf(flat(startOff, -flat(facing)))
	local yawEnd = yawOf(flat(endOff))
	local yaw = yawStart + Shots.SweepDelta(yawStart, yawEnd) * a
	local r = r0 + (r1 - r0) * a
	local pos = root + Vector3.new(math.sin(yaw) * r, y0 + (y1 - y0) * a, math.cos(yaw) * r)
	local startLook = startCF.Position + startCF.LookVector * math.max(4, startOff.Magnitude)
	local faceLook = root + UP * w.LookHeight
	local look = startLook:Lerp(faceLook, smooth(alpha * 1.6))
	if (look - pos).Magnitude < 1e-3 then
		look = faceLook
	end
	return lookAt(pos, look)
end

Shots.YawOf = yawOf

function Shots.Pov(ballPos: Vector3, ballVel: Vector3, fallbackDir: Vector3?): CFrame
	local f = C.Flight
	local dir = flat(ballVel, fallbackDir)
	local horiz = Vector3.new(ballVel.X, 0, ballVel.Z).Magnitude
	local pitch = math.atan2(ballVel.Y, math.max(1e-3, horiz)) * f.PovPitchFollow
	pitch = math.clamp(pitch, math.rad(f.PovPitchMin), math.rad(f.PovPitchMax))
	local look = dir * math.cos(pitch) + UP * math.sin(pitch)
	local pos = ballPos - dir * f.PovBack + UP * f.PovUp
	return lookAt(pos, pos + look)
end

function Shots.Wide(landPos: Vector3, forward: Vector3): CFrame
	local L = C.Landing
	local fwd = flat(forward)
	local side = UP:Cross(fwd)
	local pos = landPos - fwd * L.WideBack + UP * L.WideUp + side * L.WideSide
	return lookAt(pos, landPos + fwd * L.BounceRoll)
end

function Shots.Toward(fromCF: CFrame, target: Vector3, share: number): CFrame
	local pos = fromCF.Position:Lerp(target, math.clamp(share, 0, 0.95))
	return lookAt(pos, target)
end

function Shots.Follow(pos: Vector3, travelDir: Vector3): CFrame
	local o = C.Outcome
	local dir = flat(travelDir)
	local cam = pos - dir * o.FollowBack + UP * o.FollowUp
	return lookAt(cam, pos + dir * 4)
end

-- Deterministic decaying shake: zero at t <= 0 and t >= length.
function Shots.Shake(t: number, seed: number, studs: number, degrees: number, length: number): CFrame
	if t <= 0 or t >= length or length <= 0 then
		return CFrame.new()
	end
	local k = (1 - t / length) ^ 2
	local w = 47 + seed % 7
	local x = math.sin(t * w + seed) * studs * k
	local y = math.sin(t * w * 1.31 + seed * 2) * studs * k
	local rz = math.sin(t * w * 0.83 + seed * 3) * math.rad(degrees) * k
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, rz)
end

-- Release-shake strength for a meter quality (0.35 flub .. 1 Perfect): a Perfect throw shakes hardest.
function Shots.QualityScale(quality: number?): number
	local I = C.Impact
	local q = tonumber(quality) or I.QualityMin
	local k = math.clamp((q - I.QualityMin) / math.max(1e-6, 1 - I.QualityMin), 0, 1)
	return I.ShakeMinScale + (1 - I.ShakeMinScale) * k
end

-- Release impact shake: full amplitude (x scale) at t = 0, (1 - t / ShakeTime) ^ ShakeDecay after, zero from ShakeTime.
function Shots.ImpactShakeAmount(t: number, scale: number): number
	local I = C.Impact
	if t < 0 or t >= I.ShakeTime then
		return 0
	end
	return scale * (1 - t / I.ShakeTime) ^ I.ShakeDecay
end

function Shots.ImpactShake(t: number, seed: number, scale: number): CFrame
	local I = C.Impact
	local k = Shots.ImpactShakeAmount(t, scale)
	if k <= 0 then
		return CFrame.new()
	end
	local w = 2 * math.pi * I.ShakeHz
	local x = math.sin(t * w + seed) * I.ShakeStuds * k
	local y = math.cos(t * w * 1.27 + seed * 2) * I.ShakeStuds * k
	local rz = math.sin(t * w * 0.79 + seed * 3) * math.rad(I.ShakeDegrees) * k
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, rz)
end

-- Ball-POV shake share (0..1) for an on-screen ball speed.
function Shots.SpeedShakeAmount(speed: number): number
	return math.clamp(speed / math.max(1e-6, C.Flight.PovShakeSpeedForMax), 0, 1)
end

function Shots.SpeedShake(t: number, seed: number, speed: number): CFrame
	local f = C.Flight
	local k = Shots.SpeedShakeAmount(speed)
	if k <= 0 then
		return CFrame.new()
	end
	local w = 2 * math.pi * f.PovShakeHz
	local x = (math.sin(t * w + seed) + 0.5 * math.sin(t * w * 2.3 + seed * 1.7)) / 1.5 * f.PovShakeStuds * k
	local y = (math.sin(t * w * 1.13 + seed * 2) + 0.5 * math.sin(t * w * 1.9 + seed)) / 1.5 * f.PovShakeStuds * k
	local rz = math.sin(t * w * 0.71 + seed * 3) * math.rad(f.PovShakeDegrees) * k
	return CFrame.new(x, y, 0) * CFrame.Angles(0, 0, rz)
end

-- FOV punch after the release: 0 -> (FovPeak - FovFrom) at FovPeakAt x FovTime -> 0 at FovTime.
function Shots.FovPunch(t: number): number
	local I = C.Impact
	if t < 0 or t >= I.FovTime then
		return 0
	end
	local peak = I.FovPeak - I.FovFrom
	local u = t / I.FovTime
	if u < I.FovPeakAt then
		return peak * math.sin(0.5 * math.pi * u / I.FovPeakAt)
	end
	return peak * math.cos(0.5 * math.pi * (u - I.FovPeakAt) / (1 - I.FovPeakAt))
end

-- Ball-POV blur for an on-screen ball speed; `landing` (0..1) is the landing ease-out share: the blur clears with it.
function Shots.BlurSize(speed: number, landing: number): number
	local f = C.Flight
	local k = math.clamp(speed / math.max(1e-6, f.BlurSpeedForMax), 0, 1)
	return f.BlurSize * k * (1 - math.clamp(landing, 0, 1))
end

return Shots
