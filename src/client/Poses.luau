-- Procedural limb animation for every player, on every client.
--
-- Two moves: raising the Sea Staff to part the sea, and barbell reps on the
-- training pad. The server only publishes timing as player attributes
-- (CastStart, Training, RepStart, WeightTier); each client turns that into
-- joint rotations here, so the motion works on both R6 and R15 avatars and
-- is seen by everyone.
--
-- Joints are posed by rotating each Motor6D's C0 (its resting offset) from
-- the value it had when the move began, and putting that value back when the
-- move ends. The engine's Animator never writes C0 (it writes Transform), so
-- nothing overrides the pose; whatever default animation is playing (idle,
-- holding a tool) simply layers on top.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voxel = require(Shared.Voxel)

local Poses = {}

local rad = math.rad

local folder: Folder
local barbells: { [Player]: { model: Model, tier: number } } = {}

----------------------------------------------------------------------------
-- Rig access
----------------------------------------------------------------------------
local R15_JOINTS = {
	rShoulder = { "RightUpperArm", "RightShoulder" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	rHip = { "RightUpperLeg", "RightHip" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	waist = { "UpperTorso", "Waist" },
	root = { "LowerTorso", "Root" },
}
local R6_JOINTS = {
	rShoulder = { "Torso", "Right Shoulder" },
	lShoulder = { "Torso", "Left Shoulder" },
	rHip = { "Torso", "Right Hip" },
	lHip = { "Torso", "Left Hip" },
}

local function isR6(char: Model): boolean
	return char:FindFirstChild("Torso") ~= nil and char:FindFirstChild("UpperTorso") == nil
end

local function motor(char: Model, r6: boolean, key: string): Motor6D?
	local def = (r6 and R6_JOINTS or R15_JOINTS)[key]
	if not def then
		return nil
	end
	local part = char:FindFirstChild(def[1])
	local m = part and part:FindFirstChild(def[2])
	if m and m:IsA("Motor6D") then
		return m
	end
	return nil
end

-- Rotation that swings a limb forward/up by `degrees` from hanging straight
-- down. R15 joints share the limb's axes; R6 shoulder and hip joints are
-- turned sideways, mirrored between left and right.
local function swing(r6: boolean, left: boolean, degrees: number): CFrame
	if r6 then
		return CFrame.Angles(0, 0, rad(left and -degrees or degrees))
	end
	return CFrame.Angles(rad(degrees), 0, 0)
end

-- What we are currently posing: per player, the character and each posed
-- motor's original C0.
local posed: { [Player]: { char: Model, move: string, base: { [Motor6D]: CFrame } } } = {}

local function release(player: Player)
	local state = posed[player]
	if not state then
		return
	end
	posed[player] = nil
	for m, c0 in state.base do
		if m.Parent then
			m.C0 = c0
		end
	end
end

-- Apply a pose: joint key -> degrees (limbs) or CFrame (root / waist).
local function apply(player: Player, char: Model, move: string, pose: { [string]: any })
	local state = posed[player]
	if state and (state.char ~= char or state.move ~= move) then
		release(player)
		state = nil
	end
	local r6 = isR6(char)
	if not state then
		state = { char = char, move = move, base = {} }
		posed[player] = state
		-- One line in the Output window per move, to make problems visible.
		local found = 0
		for key in pose do
			if motor(char, r6, key) then
				found += 1
			end
		end
		print(string.format("[Poses] %s: %s on a %s rig, %d joints", player.Name, move, r6 and "R6" or "R15", found))
	end
	for key, value in pose do
		local m = motor(char, r6, key)
		if m then
			if not state.base[m] then
				state.base[m] = m.C0
			end
			local offset = if typeof(value) == "CFrame" then value else swing(r6, string.sub(key, 1, 1) == "l", value)
			m.C0 = state.base[m] * offset
		end
	end
end

----------------------------------------------------------------------------
-- Keyframe helper: value at time k along { {time, value}, ... }
----------------------------------------------------------------------------
local function track(k: number, keys: { { number } }): number
	if k <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if k <= b[1] then
			local u = (k - a[1]) / (b[1] - a[1])
			u = u * u * (3 - 2 * u)
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return keys[#keys][2]
end

----------------------------------------------------------------------------
-- The moves
----------------------------------------------------------------------------

-- Parting the sea: wind the staff back, thrust it overhead, hold it there
-- trembling while the sea tears open, then lower it. Angles are added on
-- top of the default tool-holding pose, which already has the staff arm
-- raised about 90 degrees in front of the body.
function Poses.cast(k: number, clock: number): { [string]: any }
	local tremble = (k > 0.3 and k < 0.86) and math.sin(clock * 38) * 3 or 0
	local crouch = track(k, { { 0, 0 }, { 0.14, 22 }, { 0.26, 6 }, { 0.86, 10 }, { 1, 0 } })
	return {
		rShoulder = track(k, { { 0, 0 }, { 0.14, -120 }, { 0.26, 88 }, { 0.86, 84 }, { 1, 0 } }) + tremble,
		rElbow = track(k, { { 0, 0 }, { 0.14, 50 }, { 0.26, 0 }, { 0.86, 0 }, { 1, 0 } }),
		lShoulder = track(k, { { 0, 0 }, { 0.14, 30 }, { 0.26, 95 }, { 0.86, 85 }, { 1, 0 } }) - tremble,
		lElbow = track(k, { { 0, 0 }, { 0.14, 40 }, { 0.26, 10 }, { 0.86, 15 }, { 1, 0 } }),
		rHip = crouch,
		lHip = crouch * 0.4,
		rKnee = -crouch * 1.6,
		lKnee = -crouch * 0.8,
		waist = CFrame.Angles(rad(track(k, { { 0, 0 }, { 0.14, 14 }, { 0.26, -12 }, { 0.86, -8 }, { 1, 0 } })), 0, 0),
		root = CFrame.new(0, -crouch * 0.012, 0),
	}
end

-- A barbell rep: `lift` goes 0 (bar at the chest, knees bent) to 1 (bar
-- locked out overhead, standing tall) and back.
function Poses.rep(lift: number, r6: boolean): { [string]: any }
	if r6 then
		-- No elbows on R6: straight arms from chest height to overhead.
		return {
			rShoulder = 100 + 76 * lift,
			lShoulder = 100 + 76 * lift,
			rHip = 12 * (1 - lift),
			lHip = 12 * (1 - lift),
		}
	end
	local dip = 1 - lift
	return {
		rShoulder = 38 + 134 * lift,
		lShoulder = 38 + 134 * lift,
		rElbow = 132 * dip + 4,
		lElbow = 132 * dip + 4,
		rHip = 26 * dip,
		lHip = 26 * dip,
		rKnee = -52 * dip,
		lKnee = -52 * dip,
		root = CFrame.new(0, -0.32 * dip, 0),
	}
end

----------------------------------------------------------------------------
-- Barbell: held in the hands, wherever the arms actually are
----------------------------------------------------------------------------
local function handPosition(char: Model, r6: boolean, side: string): Vector3?
	if r6 then
		local arm = char:FindFirstChild(side .. " Arm") :: BasePart?
		return arm and (arm.CFrame * CFrame.new(0, -0.9, 0)).Position
	end
	local hand = (char:FindFirstChild(side .. "Hand") or char:FindFirstChild(side .. "LowerArm") or char:FindFirstChild(side .. "UpperArm")) :: BasePart?
	return hand and hand.Position
end

local function dropBarbell(player: Player)
	local held = barbells[player]
	if held then
		held.model:Destroy()
		barbells[player] = nil
	end
end

local function holdBarbell(player: Player, char: Model)
	local r6 = isR6(char)
	local right = handPosition(char, r6, "Right")
	local left = handPosition(char, r6, "Left")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not right or not left or not root then
		dropBarbell(player)
		return
	end
	local tier = player:GetAttribute("WeightTier") or 1
	local held = barbells[player]
	if not held or held.tier ~= tier then
		dropBarbell(player)
		local model = Voxel.barbell(tier)
		model.Name = "TrainingBarbell"
		Voxel.weld(model, true) -- move the whole bar by its root
		model.Parent = folder
		held = { model = model, tier = tier }
		barbells[player] = held
	end
	-- The bar runs hand to hand (it's built along its X axis).
	local across = right - left
	local axis = across.Magnitude > 0.2 and across.Unit or root.CFrame.RightVector
	held.model.PrimaryPart.CFrame = CFrame.fromMatrix((right + left) / 2, axis, root.CFrame.UpVector)
end

----------------------------------------------------------------------------
-- Per-frame
----------------------------------------------------------------------------
local function liftPhase(player: Player, now: number): number
	local start = player:GetAttribute("RepStart") or now
	local phase = ((now - start) / Config.Training.RepTime) % 1
	return 0.5 - 0.5 * math.cos(phase * math.pi * 2)
end

-- Every frame: pose whoever is casting or training, release everyone else.
local function poseAll()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local active = false
		if char and char:FindFirstChild("HumanoidRootPart") then
			if player:GetAttribute("Training") then
				apply(player, char, "workout", Poses.rep(liftPhase(player, now), isR6(char)))
				active = true
			else
				local castStart = player:GetAttribute("CastStart")
				if castStart then
					local k = (now - castStart) / Config.Ocean.OpenAnim
					if k >= 0 and k < 1 then
						apply(player, char, "cast", Poses.cast(k, clock))
						active = true
					end
				end
			end
		end
		if not active and posed[player] then
			release(player)
		end
	end
end

-- Each rendered frame: keep every training player's barbell in their hands.
local function carryBarbells()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and player:GetAttribute("Training") then
			holdBarbell(player, char)
		elseif barbells[player] then
			dropBarbell(player)
		end
	end
	for player in barbells do
		if not player.Parent then
			dropBarbell(player)
		end
	end
end

function Poses.init()
	folder = Instance.new("Folder")
	folder.Name = "Poses"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(function()
		poseAll()
		carryBarbells()
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		dropBarbell(player)
	end)
end

return Poses
