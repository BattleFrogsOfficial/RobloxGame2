--!nocheck
-- Cutscene motion maths (src/shared/Cutscene/Path.luau + Shots.luau).   lune run tools/tests/cutscene_path.luau
-- Proves: the time-scaled flight starts in the hand, blends into the server arc and lands EXACTLY on LandPos at
-- the on-screen duration; Z keeps moving forward; velocity matches the position's derivative; a mid-flight
-- retarget lands on the real LandPos; bounces decay and come to rest; the procedural pose starts and ends at
-- rest and swings the arm through the throw; the KeyframeSequence description (ThrowAnim) maps every joint per rig
-- type, keys at At x Duration, rest at both ends, Transform = the C0 path; camera shots sit where the spec says (front: in front, chest
-- height, low, framing the whole body; sweep: a half circle from behind to the front; POV: behind + above the
-- ball looking along its travel; wide: back + up looking down at the landing spot); shakes decay to zero.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local check = Loader.Check
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Shared = Loader.Mount("src/shared")
local C = Loader.Require(Shared.Config.Cutscene)
local Layout = Loader.Require(Shared.Config.Layout)
local Game = Loader.Require(Shared.Config.Game)
local BallFlight = Loader.Require(Shared.Util.BallFlight)
local Path = Loader.Require(Shared.Cutscene:WaitForChild("Path"))
local Shots = Loader.Require(Shared.Cutscene.Shots)
local Timeline = Loader.Require(Shared.Cutscene.Timeline)
local ThrowAnim = Loader.Require(Shared.Cutscene.ThrowAnim)

local EPS = 0.02 -- Vector3 is float32
local spot = Layout.Platform.ThrowSpot
local launchY = spot.Y + Game.Throw.LaunchHeight

-- 1. Flight path.
for _, d in { 5, 60, 250, 800, 1500, 3200 } do
	local launch, land = BallFlight.Endpoints(spot, launchY, Layout.ThrowLine.Z, Layout.GroundY, d, 12)
	local arc = BallFlight.ForThrow(launch, land)
	local seconds = Timeline.FlightSeconds(arc.Duration)
	local hand = launch + Vector3.new(-1.2, 1.5, -0.6)
	local fp = Path.Flight(arc, hand, seconds)
	check((fp.Position(0) - hand).Magnitude < EPS, "starts in the hand d=" .. d)
	check(fp.Position(seconds) == land, "lands exactly on LandPos d=" .. d)
	check(fp.Position(seconds + 1) == land, "stays on LandPos after the flight")
	local blendEnd = C.Flight.HandBlend
	check((fp.Position(blendEnd + 0.01) - arc.Position((blendEnd + 0.01) * arc.Duration / seconds)).Magnitude < EPS,
		"on the server arc after the hand blend d=" .. d)
	local prevZ = -math.huge
	local maxErr = 0
	for k = 0, 400 do
		local t = seconds * k / 400
		local p = fp.Position(t)
		if t > blendEnd then
			check(p.Z >= prevZ - EPS, "Z keeps moving forward")
			prevZ = p.Z
		end
		if k > 0 and k < 400 then
			local h = 1e-3
			local num = (fp.Position(t + h) - fp.Position(t - h)) / (2 * h)
			maxErr = math.max(maxErr, (num - fp.Velocity(t)).Magnitude / math.max(1, num.Magnitude))
		end
	end
	check(maxErr < 0.02, "velocity is the derivative of position d=" .. d, tostring(maxErr))
	-- time scaling: on-screen time T maps to arc time T * arc.Duration / seconds
	local mid = fp.Position(seconds / 2)
	check((mid - arc.Position(arc.Duration / 2)).Magnitude < EPS, "time-scaled arc (half way) d=" .. d)
end

-- 2. Retarget: an estimate replaced mid-flight still lands exactly on the real LandPos.
do
	local la, lb = BallFlight.Endpoints(spot, launchY, Layout.ThrowLine.Z, Layout.GroundY, 900, 0)
	local ra, rb = BallFlight.Endpoints(spot, launchY, Layout.ThrowLine.Z, Layout.GroundY, 930, 17)
	local est = Path.Flight(BallFlight.ForThrow(la, lb), la, 3)
	local real = Path.Flight(BallFlight.ForThrow(ra, rb), la, 3.1)
	for _, sw in { 0, 0.5, 2.0, 2.95 } do
		local fp = Path.Retarget(est, real, sw)
		check(fp.Position(fp.Duration) == rb, "retarget at " .. sw .. " lands on the real LandPos")
		check((fp.Position(math.max(0, sw - 0.01)) - est.Position(math.max(0, sw - 0.01))).Magnitude < EPS, "no jump at the switch " .. sw)
	end
end

-- 3. Bounces.
do
	local land = Vector3.new(4, 0, 900)
	local b = Path.Bounces(land, Vector3.new(0, 0, 1))
	check(#b.Hops == C.Landing.Bounces, "bounce count")
	check(Path.BounceAt(b, 0) == land, "bounces start at LandPos")
	for i = 2, #b.Hops do
		check(b.Hops[i].Height < b.Hops[i - 1].Height, "bounces decay")
		check(b.Hops[i].T1 - b.Hops[i].T0 < b.Hops[i - 1].T1 - b.Hops[i - 1].T0, "bounces get shorter")
		check(math.abs(b.Hops[i].T0 - b.Hops[i - 1].T1) < 1e-9, "bounces are back to back")
	end
	check(Path.BounceAt(b, b.Duration + 1) == b.Rest, "comes to rest")
	check(b.Rest.Z > land.Z and math.abs(b.Rest.Y - land.Y) < 1e-6, "rolls forward along the ground")
	local maxY = 0
	for k = 0, 100 do
		maxY = math.max(maxY, Path.BounceAt(b, b.Hops[1].T1 * k / 100).Y)
	end
	check(math.abs(maxY - C.Landing.BounceHeight) < 0.05, "first bounce height", tostring(maxY))
	check(b.Duration < C.Beats.Settle.Common + C.Beats.DogArrive.Common + 0.5, "bounces finish while the dog arrives")
end

-- 4. Procedural pose.
do
	local p0 = Path.Pose(0)
	local pEnd = Path.Pose(Path.PoseLength())
	for _, j in Path.Joints do
		check(p0[j].Magnitude < 1e-9, "pose starts at rest: " .. j)
		local e = pEnd[j]
		local cf = CFrame.Angles(e.X, e.Y, e.Z)
		check((cf.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-4 and (cf.UpVector - Vector3.new(0, 1, 0)).Magnitude < 1e-4,
			"pose ends at rest (C0 restores): " .. j)
	end
	check(math.abs(Path.PoseLength() - (C.WindUp.Duration + C.WindUp.Recover)) < 0.01, "pose length = Duration + Recover")
	-- the throwing arm is cocked up-and-back mid wind-up and points forward at the release frame
	local function armDir(t)
		local a = Path.Pose(t).RightShoulder
		return CFrame.Angles(a.X, a.Y, a.Z):VectorToWorldSpace(Vector3.new(0, -1, 0)) -- arm hangs down at rest
	end
	local cocked = armDir(0.55 * C.WindUp.Duration)
	check(cocked.Y > 0.5 and cocked.Z > 0, "arm cocked up and back", tostring(cocked))
	local release = armDir(C.WindUp.ReleaseAt)
	check(release.Z < -0.6, "arm forward at the release frame", tostring(release))
	local knee = Path.Pose(0.55 * C.WindUp.Duration).LeftHip
	check(knee.X > math.rad(45), "one knee up during the wind-up")
	local waist = Path.Pose(0.55 * C.WindUp.Duration).Waist
	check(waist.Y < -math.rad(30), "body turns during the wind-up")
	check(math.abs(C.WindUp.ReleaseAt / C.WindUp.Duration - C.Pose[5].At) < 0.02, "release key matches ReleaseAt")
end

-- 5. Camera shots.
do
	local root = Vector3.new(0, 43, 56)
	local facing = Vector3.new(0, 0, 1)
	local front = Shots.Front(root, facing)
	local rel = front.Position - root
	check(rel.Z > C.WindUp.FrontDistance - 0.01, "front shot is in front of the player")
	check(math.abs(rel.Y - C.WindUp.FrontHeight) < 1e-4 and rel.Y < C.WindUp.LookHeight, "front shot at chest height, below the face")
	local toFace = ((root + Vector3.new(0, C.WindUp.LookHeight, 0)) - front.Position).Unit
	check((front.LookVector - toFace).Magnitude < 1e-3, "front shot looks at the face")
	check(front.LookVector.Y > 0, "front shot looks slightly up (low angle)")
	-- whole body in frame: the raised throwing hand (~4.5 above the root) down to the feet (~3 below), plus the
	-- raised knee and the wound-back arm to the side, all inside the vertical FOV (Fov is vertical in Roblox)
	local half = math.rad(C.WindUp.Fov / 2)
	for _, off in { Vector3.new(0, 4.5, 0), Vector3.new(0, -3, 0), Vector3.new(-1.5, 3.5, 1.5), Vector3.new(0.5, -0.5, -1) } do
		local d = (root + off) - front.Position
		local localD = front:VectorToObjectSpace(d)
		local vert = math.atan2(localD.Y, -localD.Z)
		check(-localD.Z > 0 and math.abs(vert) < half * 0.92, "front shot frames the body point " .. tostring(off), tostring(math.deg(vert)))
	end
	-- default camera: behind and above
	local start = Shots.LookAt(root + Vector3.new(0, 5, -12), root + Vector3.new(0, 1.5, 0))
	local s0 = Shots.Sweep(start, root, facing, 0)
	local s1 = Shots.Sweep(start, root, facing, 1)
	check((s0.Position - start.Position).Magnitude < 0.01, "sweep starts at the default camera")
	check((s1.Position - front.Position).Magnitude < 0.01, "sweep ends at the front shot")
	local turned = 0
	local lastYaw = Shots.YawOf(Shots.Flat(s0.Position - root))
	for k = 1, 100 do
		local p = Shots.Sweep(start, root, facing, k / 100).Position - root
		local yaw = Shots.YawOf(Shots.Flat(p))
		local d = (yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
		turned += d
		lastYaw = yaw
		check(Vector3.new(p.X, 0, p.Z).Magnitude > 2, "sweep orbits the player")
	end
	check(math.abs(math.abs(turned) - math.pi) < math.rad(25), "sweep is about a half circle", tostring(math.deg(turned)))
	check((turned > 0) == (C.WindUp.SweepDirection > 0), "sweep goes the configured way round")
	-- POV
	local ballPos = Vector3.new(0, 120, 600)
	local vel = Vector3.new(0, 40, 300)
	local pov = Shots.Pov(ballPos, vel)
	check(pov.Position.Z < ballPos.Z and pov.Position.Y > ballPos.Y, "POV is behind and above the ball")
	check(math.abs((pov.Position - ballPos).Y - C.Flight.PovUp) < 1e-3, "POV a few studs above the ball")
	check(pov.LookVector.Z > 0.7, "POV looks along the ball's travel")
	local steep = Shots.Pov(ballPos, Vector3.new(0, -900, 100))
	check(math.deg(math.asin(steep.LookVector.Y)) >= C.Flight.PovPitchMin - 0.01, "POV pitch clamped")
	-- Wide
	local land = Vector3.new(10, 0, 900)
	local wide = Shots.Wide(land, Vector3.new(0, 0, 1))
	check(wide.Position.Y - land.Y >= C.Landing.WideUp - 1e-3 and wide.Position.Z < land.Z, "wide shot is up and back")
	check(wide.LookVector.Y < -0.3, "wide shot looks down at the landing spot")
	-- push-in keeps looking at the target and gets closer
	local dog = land + Vector3.new(3, 0, 2)
	local pushed = Shots.Toward(wide, dog, 0.45)
	check((pushed.Position - dog).Magnitude < (wide.Position - dog).Magnitude, "push-in gets closer")
	check((pushed.LookVector - (dog - pushed.Position).Unit).Magnitude < 1e-3, "push-in looks at the dog")
	-- follow
	local f = Shots.Follow(dog, Vector3.new(0, 0, -1))
	check(f.Position.Z > dog.Z and f.Position.Y > dog.Y, "follow camera behind + above the dog")
	-- shake
	check(Shots.Shake(0, 3, 1, 1, 0.3) == CFrame.new() and Shots.Shake(0.3, 3, 1, 1, 0.3) == CFrame.new(), "shake is zero at both ends")
	local a, b = Shots.Shake(0.02, 3, 1, 1, 0.3), Shots.Shake(0.25, 3, 1, 1, 0.3)
	check(a.Position.Magnitude <= 1.001 and b.Position.Magnitude < 0.1, "shake decays")
end

-- 7. Built-in throw as a KeyframeSequence (ThrowAnim): joint mapping per rig type, keyframes, rest pose, and the
-- Transform conversion equals what the C0 fallback shows.
do
	local function names(node, out)
		out[node.Name] = node
		for _, c in node.Children do
			names(c, out)
		end
		return out
	end
	local function parentOf(root, name)
		local found = nil
		local function walk(n)
			for _, c in n.Children do
				if c.Name == name then
					found = n.Name
				end
				walk(c)
			end
		end
		walk(root)
		return found
	end
	local expect = {
		R15 = { LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
			LeftUpperArm = "UpperTorso", LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", RightUpperLeg = "LowerTorso",
			RightLowerLeg = "RightUpperLeg" },
		R6 = { Torso = "HumanoidRootPart", ["Right Arm"] = "Torso", ["Left Arm"] = "Torso", ["Left Leg"] = "Torso", ["Right Leg"] = "Torso" },
	}
	local driven = { R15 = { "Waist", "RightShoulder", "RightElbow", "LeftShoulder", "LeftHip", "LeftKnee", "RightHip", "RightKnee" },
		R6 = { "Waist", "RightShoulder", "LeftShoulder", "LeftHip", "RightHip" } }
	-- R6 joints carry rotated C0s (shoulders / hips / RootJoint); R15 C0s are near identity
	local r6Rot = {
		Torso = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		["Right Arm"] = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) - Vector3.new(1, 0.5, 0),
		["Left Arm"] = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) - Vector3.new(-1, 0.5, 0),
		["Left Leg"] = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		["Right Leg"] = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	}
	for rigType, parents in expect do
		local rots = if rigType == "R6" then r6Rot else nil
		local spec = ThrowAnim.Build(rigType, rots)
		check(spec.RigType == rigType, rigType .. ": spec rig type")
		check(#spec.Keyframes == #C.Pose, rigType .. ": one keyframe per Config pose key", tostring(#spec.Keyframes))
		for i, k in spec.Keyframes do
			check(math.abs(k.Time - C.Pose[i].At * C.WindUp.Duration) < 1e-9, rigType .. ": keyframe time = At x Duration " .. i)
			check(k.Root.Name == "HumanoidRootPart", rigType .. ": pose tree rooted at the HumanoidRootPart " .. i)
			local all = names(k.Root, {})
			for part, parent in parents do
				check(all[part] ~= nil and parentOf(k.Root, part) == parent, ("%s: %s posed under %s (key %d)"):format(rigType, part, parent, i))
			end
		end
		check(math.abs(spec.Length - Path.PoseLength()) < 1e-9, rigType .. ": sequence length = Path.PoseLength")
		-- first and last keyframes = rest (identity transform on every joint)
		for _, k in { spec.Keyframes[1], spec.Keyframes[#spec.Keyframes] } do
			for _, node in names(k.Root, {}) do
				local cf = node.CFrame
				check((cf.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-4 and (cf.UpVector - Vector3.new(0, 1, 0)).Magnitude < 1e-4
					and cf.Position.Magnitude < 1e-6, rigType .. ": rest pose at the ends " .. node.Name)
			end
		end
		-- conversion: C0 * Transform == C0' of the fallback (T(p) * A * R) for every driven joint at every key
		local byJoint = {}
		for _, j in ThrowAnim.Rigs[rigType] do
			if j.Joint then
				byJoint[j.Joint] = j
			end
		end
		for _, jn in driven[rigType] do
			check(byJoint[jn] ~= nil, rigType .. ": joint mapped " .. jn)
		end
		for i, key in C.Pose do
			local all = names(spec.Keyframes[i].Root, {})
			for jn, j in byJoint do
				local v = key[jn]
				local a = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
				local R = (rots and rots[j.Part]) or CFrame.new()
				local c0 = CFrame.new(0.5, 1, 0) * R
				local viaAnim = c0 * all[j.Part].CFrame
				local viaC0 = CFrame.new(c0.Position) * a * R
				local err = (viaAnim.LookVector - viaC0.LookVector).Magnitude + (viaAnim.UpVector - viaC0.UpVector).Magnitude
					+ (viaAnim.Position - viaC0.Position).Magnitude
				check(err < 1e-4, ("%s: Transform matches the C0 path %s key %d"):format(rigType, jn, i), tostring(err))
			end
		end
	end
	-- consecutive keys < 180 degrees apart per axis (the animator slerps the shortest way)
	for i = 2, #C.Pose do
		for _, jn in Path.Joints do
			local a, b = C.Pose[i - 1][jn], C.Pose[i][jn]
			for ax = 1, 3 do
				check(math.abs(b[ax] - a[ax]) < 180, ("pose step < 180 deg: %s key %d axis %d"):format(jn, i, ax))
			end
		end
	end
	check(ThrowAnim.Signature("R15") ~= ThrowAnim.Signature("R6"), "cache key differs per rig type")
	check(ThrowAnim.Signature("R6", r6Rot) == ThrowAnim.Signature("R6", r6Rot), "cache key stable")
end

-- 6. Estimate (late ThrowResult): same distance formula, scatter 0.
do
	local launch, land = Path.Estimate(400, 1.25, 1.0, 0)
	check(math.abs(land.Z - (Layout.ThrowLine.Z + 500)) < EPS and land.Y == Layout.GroundY, "estimate lands at power x range x quality")
	check(math.abs(launch.Y - launchY) < 1e-6, "estimate launches at hand height")
	local _, far = Path.Estimate(1e6, 2, 1, 0)
	check(far.Z <= Layout.Field.MaxZ + EPS, "estimate clamped to the field")
end

process.exit(Loader.Done("cutscene_path") > 0 and 1 or 0)
