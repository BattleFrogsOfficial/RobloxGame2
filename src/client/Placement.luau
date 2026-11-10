-- Placing an egg from your inventory anywhere in your own plot.
--
-- A see-through copy of the egg follows the mouse over the plot (on touch
-- and gamepad it sits in front of you until you tap a spot). Click, tap or
-- press the right trigger to put it down. The server checks the spot again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Voxel = require(Shared.Voxel)

local State = require(script.Parent.State)
local Ocean = require(script.Parent.Ocean)

local Placement = {}

Placement.active = false
Placement.ok = false -- can the egg go down where the preview is?
Placement.hint = "" -- shown on the HUD while placing

local player = Players.LocalPlayer
local P = Config.Pen
local GOOD, BAD = Color3.fromRGB(110, 255, 120), Color3.fromRGB(255, 90, 80)

local index = 1
local ghost: Model? = nil
local ghostSig = ""
local ring: Part? = nil
local spot: Vector3? = nil -- pen-space point under the preview
local busy = false

local function myPen(): Model?
	local pens = workspace:FindFirstChild("Pens")
	for _, m in pens and pens:GetChildren() or {} do
		if m:GetAttribute("OwnerId") == player.UserId then
			return m :: Model
		end
	end
	return nil
end

local function frameOf(pen: Model): CFrame
	return pen:GetAttribute("Frame") :: CFrame
end

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function penUsed(d): number
	local n = 0
	for _ in d.pen do
		n += 1
	end
	return n
end

local function clampToPlot(p: Vector3): Vector3
	local mx, mz = P.Width / 2 - P.PlaceMargin, P.Depth / 2 - P.PlaceMargin
	return Vector3.new(math.clamp(p.X, -mx, mx), 0, math.clamp(p.Z, -mz, mz))
end

-- Pen-space point on the plot floor under a screen position.
local function underScreenPoint(frame: CFrame, screen: Vector2): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	if ray.Direction.Y > -0.01 then
		return nil
	end
	local t = (frame.Position.Y - ray.Origin.Y) / ray.Direction.Y
	return clampToPlot(frame:PointToObjectSpace(ray.Origin + ray.Direction * t))
end

local function inFrontOfMe(frame: CFrame): Vector3?
	local root = rootPart()
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
	return clampToPlot(frame:PointToObjectSpace(root.Position + flat * 6))
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if ring then
		ring:Destroy()
		ring = nil
	end
	ghostSig = ""
end

local function buildGhost(egg: string, variant: string)
	clearGhost()
	ghostSig = egg .. ":" .. variant
	local model = Voxel.egg(egg, variant, true)
	model.Name = "EggPreview"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Transparency = 0.45
		end
	end
	model.Parent = workspace
	ghost = model
	local r = Instance.new("Part")
	r.Name = "EggPreviewRing"
	r.Shape = Enum.PartType.Cylinder
	r.Size = Vector3.new(0.15, P.EggGap, P.EggGap)
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.Material = Enum.Material.Neon
	r.Transparency = 0.35
	r.Parent = workspace
	ring = r
end

function Placement.cancel()
	Placement.active = false
	Placement.ok = false
	spot = nil
	clearGhost()
end

-- Start placing stored egg number i (its place in State.data.eggs).
function Placement.start(i: number)
	local d = State.data
	local pen = myPen()
	if not d or not d.eggs[i] then
		return
	end
	if not pen then
		State.toast:Fire("You need a base to place eggs.", BAD)
		return
	end
	if penUsed(d) >= d.baseSlots then
		State.toast:Fire("Your base is full! Upgrade it for more slots.", BAD)
		return
	end
	index = i
	Placement.active = true
	-- Not in your plot? Go there.
	local root = rootPart()
	local here = root and frameOf(pen):PointToObjectSpace(root.Position)
	if not here or math.abs(here.X) > P.Width / 2 or math.abs(here.Z) > P.Depth / 2 then
		task.spawn(State.action, "TeleportHome")
	end
end

-- Put the egg down at a pen-space point (defaults to where the preview is).
function Placement.confirm(at: Vector3?)
	local d = State.data
	local pen = myPen()
	local p = at or spot
	if not Placement.active or busy or not d or not pen or not p then
		return
	end
	local ok, why = Formulas.canPlaceEgg(d.pen, p.X, p.Z)
	if not ok then
		State.toast:Fire(why :: string, BAD)
		return
	end
	busy = true
	task.spawn(function()
		State.action("PlaceEgg", index, frameOf(pen):PointToWorldSpace(Vector3.new(p.X, 0, p.Z)))
		busy = false
	end)
end

-- Keep going with the next egg while there are eggs and room for them.
local function onState(d)
	if not Placement.active then
		return
	end
	if #d.eggs == 0 or penUsed(d) >= d.baseSlots then
		Placement.cancel()
	else
		index = math.min(index, #d.eggs)
	end
end

local function update()
	if not Placement.active then
		return
	end
	local d = State.data
	local pen = myPen()
	local egg = d and d.eggs[index]
	if not pen or not egg or Ocean.inZone then
		Placement.cancel()
		return
	end
	local sig = egg.egg .. ":" .. egg.variant
	if sig ~= ghostSig then
		buildGhost(egg.egg, egg.variant)
	end
	local frame = frameOf(pen)
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local p = not touch and underScreenPoint(frame, UserInputService:GetMouseLocation()) or inFrontOfMe(frame)
	spot = p
	if not p or not ghost or not ring then
		return
	end
	local ok, why = Formulas.canPlaceEgg(d.pen, p.X, p.Z)
	Placement.ok = ok
	Placement.hint = ok and (touch and "Tap a spot in your plot" or "Click a spot in your plot") or why :: string
	ghost:PivotTo(frame * CFrame.new(p) * CFrame.Angles(0, math.pi, 0))
	ring.CFrame = frame * CFrame.new(p.X, 0.3, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = ok and GOOD or BAD
end

function Placement.init()
	State.changed:Connect(onState)
	RunService.RenderStepped:Connect(update)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Placement.active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			Placement.confirm()
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			Placement.cancel()
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(screen: Vector2, processed: boolean)
		local pen = myPen()
		if processed or not Placement.active or not pen then
			return
		end
		local p = underScreenPoint(frameOf(pen), screen)
		if p then
			Placement.confirm(p)
		end
	end)
end

return Placement
