--!strict
-- World-side client behaviour that is not UI:
--   * LOCAL animation of every dog model in the world (tags YardDog / RunawayDog): yard dogs wander around
--     their spot, runaway dogs run; Rainbow / Gold / Shadow dogs get their VariantFX. Client-side only
--     (procedural DogAnimator + local PivotTo).
--   * ShopStand proximity prompts in the plaza open the Shop panel on the matching tab.
-- Every dog animated here lives on the hub plateau (yards, runaway lawn): they walk at their server-placed
-- height, never lower than the plateau surface Layout.HubY (the field 40 studs below is scenery).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DogFolder = Shared:WaitForChild("Dog")
local DogAnimator = require(DogFolder:WaitForChild("DogAnimator"))
local VariantFX = require(DogFolder:WaitForChild("VariantFX"))
local Layout = require(Shared:WaitForChild("Config"):WaitForChild("Layout"))

local WorldController = {}

----------------------------------------------------------------------------------------------------
-- World dog animation
----------------------------------------------------------------------------------------------------
type Live = {
	Model: Model,
	Anim: DogAnimator.Animator,
	Unbind: () -> (),
	Roams: boolean,
	Home: Vector3,
	Radius: number,
	Y: number,
	Target: Vector3?,
	IdleUntil: number,
	Speed: number,
}
local live: { [Model]: Live } = {}
local ROAM_DISTANCE = 200 -- only dogs this close to the camera wander

local function track(inst: Instance, roams: boolean)
	if not inst:IsA("Model") or live[inst :: Model] then
		return
	end
	local model = inst :: Model
	-- with streaming the rig's parts may arrive a moment after the model
	if not model:FindFirstChild("Torso") then
		task.spawn(function()
			if model:WaitForChild("Torso", 5) and model.Parent and not live[model] then
				track(model, roams)
			end
		end)
		return
	end
	local ok, anim = pcall(DogAnimator.new, model)
	if not ok then
		return
	end
	local pivot = model:GetPivot()
	-- walking height: as placed, but the paws never below the plateau surface
	local bbCf, bbSize = model:GetBoundingBox()
	local lift = math.max(0, Layout.HubY - (bbCf.Position.Y - bbSize.Y / 2))
	if lift > 0 then
		pivot += Vector3.new(0, lift, 0)
		model:PivotTo(pivot)
	end
	local home = model:GetAttribute("HomePosition")
	local variant = model:GetAttribute("Variant")
	local unbind = VariantFX.Bind(model, if type(variant) == "string" and variant ~= "" then variant else nil)
	live[model] = {
		Model = model,
		Anim = anim,
		Unbind = unbind,
		Roams = roams,
		Home = if typeof(home) == "Vector3" then Vector3.new(home.X, pivot.Y, home.Z) else pivot.Position,
		Radius = tonumber(model:GetAttribute("RoamRadius")) or 6,
		Y = pivot.Y,
		Target = nil,
		IdleUntil = os.clock() + math.random() * 4,
		Speed = 4 * model:GetScale(),
	}
	if not roams then
		anim:Play("run")
	end
end

local function untrack(inst: Instance)
	local l = live[inst :: Model]
	if l then
		live[inst :: Model] = nil
		l.Anim:Destroy()
		l.Unbind()
	end
end

local function stepRoam(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, l in live do
		if model.Parent == nil then
			untrack(model)
			continue
		end
		if not l.Roams then
			continue
		end
		local pivot = model:GetPivot()
		if (pivot.Position - camPos).Magnitude > ROAM_DISTANCE then
			continue
		end
		if not l.Target then
			if now >= l.IdleUntil then
				local a = math.random() * math.pi * 2
				local r = math.random() * l.Radius
				l.Target = l.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				l.Anim:Play("run")
				l.Anim.Speed = 0.55
			end
		else
			local target = l.Target :: Vector3
			local pos = Vector3.new(pivot.X, l.Y, pivot.Z)
			local delta = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if delta.Magnitude < 0.4 then
				l.Target = nil
				l.IdleUntil = now + 2 + math.random() * 5
				l.Anim:Play(if math.random() < 0.25 then "sit" else "idle")
				l.Anim.Speed = 1
			else
				local step = math.min(delta.Magnitude, l.Speed * dt)
				local dir = delta.Unit
				local newPos = pos + dir * step
				-- turn smoothly toward the walking direction (LookVector = dog's forward)
				local desired = CFrame.lookAt(newPos, newPos + dir)
				local current = CFrame.new(newPos) * (pivot - pivot.Position)
				model:PivotTo(current:Lerp(desired, math.min(1, dt * 6)))
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Shop stands
----------------------------------------------------------------------------------------------------
local STAND_TO_TAB = { Balls = "Balls", Boosts = "Boosts", Yard = "Yard", Cosmetics = "Cosmetics" }

local function bindStandPrompt(inst: Instance, openShop: (tab: string) -> ())
	local shopId = inst:GetAttribute("ShopId")
	local tab = if type(shopId) == "string" then (STAND_TO_TAB :: any)[shopId] else nil
	if not tab or not inst:IsA("BasePart") or inst:FindFirstChild("ShopPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open " .. tab .. " Shop"
	prompt.ObjectText = "Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = inst
	prompt.Triggered:Connect(function()
		openShop(tab)
	end)
end

function WorldController.Start(ui: any)
	for _, m in CollectionService:GetTagged("YardDog") do
		track(m, true)
	end
	for _, m in CollectionService:GetTagged("RunawayDog") do
		track(m, false)
	end
	CollectionService:GetInstanceAddedSignal("YardDog"):Connect(function(m)
		track(m, true)
	end)
	CollectionService:GetInstanceAddedSignal("RunawayDog"):Connect(function(m)
		track(m, false)
	end)
	CollectionService:GetInstanceRemovedSignal("YardDog"):Connect(untrack)
	CollectionService:GetInstanceRemovedSignal("RunawayDog"):Connect(untrack)
	RunService.Heartbeat:Connect(stepRoam)

	local function openShop(tab: string)
		if ui.Router.Current() ~= "Shop" then
			ui.Router.Open("Shop", tab)
		end
	end
	for _, inst in CollectionService:GetTagged("ShopStand") do
		bindStandPrompt(inst, openShop)
	end
	CollectionService:GetInstanceAddedSignal("ShopStand"):Connect(function(inst)
		bindStandPrompt(inst, openShop)
	end)
end

return WorldController
