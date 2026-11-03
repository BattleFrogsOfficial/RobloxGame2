--!strict
-- The cutscene dog: the real DogId's model (DogFactory + VariantFX, Rainbow bound on the client), animated by
-- DogAnimator, moved by root motion along the ground. Local only; everything goes in the caller's Janitor.
--   local dog = DogActor.new(dogId, variant?, janitor)
--   dog:Place(pos, lookAt)   dog:Ground(x, z) -> y   dog:Position()   dog:HeadCFrame()   dog.Anim (DogAnimator)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DogCatalog = require(Shared:WaitForChild("Util"):WaitForChild("DogCatalog"))
local DogFolder = Shared:WaitForChild("Dog")
local DogFactory = require(DogFolder:WaitForChild("DogFactory"))
local DogAnimator = require(DogFolder:WaitForChild("DogAnimator"))
local VariantFX = require(DogFolder:WaitForChild("VariantFX"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local DogActor = {}
DogActor.__index = DogActor

local function folder(): Instance
	return workspace:FindFirstChild("CutsceneBalls") or workspace
end

export type Actor = typeof(setmetatable({} :: {
	Model: Model,
	Anim: any,
	Head: BasePart?,
	_lift: number,
	_yaw: number,
	_pos: Vector3,
}, DogActor))

function DogActor.new(dogId: string, variant: string?, janitor: any): Actor?
	local def = DogCatalog.Get(dogId)
	if not def then
		return nil
	end
	local ok, model = pcall(DogFactory.Build, def, { Variant = variant })
	if not ok or not model then
		warn("[Cutscene.Dog] build failed: " .. tostring(model))
		return nil
	end
	local m = model :: Model
	m.Name = "CutsceneDog"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m:PivotTo(CFrame.new(0, 0, 0))
	local cf, size = m:GetBoundingBox()
	local lift = -(cf.Position.Y - size.Y / 2) -- pivot height above the model's lowest point
	janitor:Add(m)
	m.Parent = folder()
	if variant then
		local unbind = VariantFX.Bind(m, variant)
		if unbind then
			janitor:Add(unbind)
		end
	end
	local anim = DogAnimator.new(m, { AlwaysAnimate = true })
	janitor:Add(function()
		anim:Destroy()
	end)
	local head = m:FindFirstChild("Head", true)
	local self = setmetatable({
		Model = m,
		Anim = anim,
		Head = if head and head:IsA("BasePart") then head else nil,
		_lift = lift,
		_yaw = 0,
		_pos = Vector3.zero,
	}, DogActor)
	return self
end

function DogActor.Ground(self: Actor, x: number, z: number, nearY: number): number
	return Effects.GroundY(Vector3.new(x, nearY, z), { self.Model })
end

-- Stand at `pos` (on the ground: pos.Y is the ground height) facing `look` (a point or nil to keep the yaw).
function DogActor.Place(self: Actor, pos: Vector3, look: Vector3?)
	if look then
		local d = Vector3.new(look.X - pos.X, 0, look.Z - pos.Z)
		if d.Magnitude > 1e-3 then
			self._yaw = math.atan2(-d.X, -d.Z) -- the rig's forward is -Z
		end
	end
	self._pos = pos
	self.Model:PivotTo(CFrame.new(pos + Vector3.new(0, self._lift, 0)) * CFrame.Angles(0, self._yaw, 0))
end

function DogActor.SetYaw(self: Actor, yaw: number)
	self._yaw = yaw
	self:Place(self._pos, nil)
end

function DogActor.Yaw(self: Actor): number
	return self._yaw
end

function DogActor.Position(self: Actor): Vector3
	return self._pos
end

function DogActor.Height(self: Actor): number
	local _, size = self.Model:GetBoundingBox()
	return size.Y
end

-- Where a carried ball sits: just in front of the head.
function DogActor.MouthCFrame(self: Actor): CFrame
	local h = self.Head
	if h and h.Parent then
		return h.CFrame * CFrame.new(0, -h.Size.Y * 0.2, -h.Size.Z * 0.6)
	end
	return CFrame.new(self._pos + Vector3.new(0, 1.5, 0))
end

return DogActor
