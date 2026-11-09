-- Shows a voxel model inside a ViewportFrame, framed to fit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Voxel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Voxel"))

local Viewport = {}

function Viewport.show(parent: Instance, model: Model, props: { [string]: any }?): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.fromScale(1, 1)
	vf.Ambient = Color3.fromRGB(190, 190, 200)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.6, -1, -0.8)
	for k, v in props or {} do
		(vf :: any)[k] = v
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	cam.Parent = vf
	vf.CurrentCamera = cam
	model.Parent = vf
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.0
	-- Models face -Z, so look at them from the front-left, a little above.
	local dir = Vector3.new(-0.55, 0.35, -1).Unit
	cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
	vf.Parent = parent
	return vf
end

function Viewport.animal(parent: Instance, animalId: string, variant: string?, silhouette: boolean?, props: { [string]: any }?)
	local m = Voxel.animal(animalId, variant)
	if silhouette then
		Voxel.silhouette(m)
	end
	return Viewport.show(parent, m, props)
end

function Viewport.egg(parent: Instance, eggId: string, variant: string?, props: { [string]: any }?)
	return Viewport.show(parent, Voxel.egg(eggId, variant, true), props)
end

return Viewport
