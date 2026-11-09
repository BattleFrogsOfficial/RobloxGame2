-- Hatch cutscene: the egg shakes, flashes and reveals the animal.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Voxel = require(Shared.Voxel)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local State = require(script.Parent.Parent.State)
local Ocean = require(script.Parent.Parent.Ocean)

local Hatch = {}

local C = Ui.Colors
local gui: ScreenGui
local queue = {}
local playing = false
local newlyFound: { [string]: boolean } = {}
local skip = false

local function play(info)
	local overlay = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Parent = gui,
	})
	skip = false
	overlay.Activated:Connect(function()
		skip = true
	end)
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	local stage = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 380),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 61,
		Parent = overlay,
	})

	-- Egg shakes harder and harder.
	local egg = Voxel.egg(info.egg, info.variant, false)
	local vf = Viewport.show(stage, egg, { ZIndex = 61 })
	local base = egg:GetPivot()
	local t0 = os.clock()
	local shakeTime = 1.6
	Ocean.playSound("rbxasset://sounds/electronicpingshort.wav", 0.4, 0.6)
	while os.clock() - t0 < shakeTime and not skip do
		local k = (os.clock() - t0) / shakeTime
		local amp = 0.08 + k * 0.35
		egg:PivotTo(base * CFrame.Angles(0, 0, math.sin(os.clock() * (18 + k * 30)) * amp))
		RunService.RenderStepped:Wait()
	end
	vf:Destroy()

	-- Flash.
	local flash = Ui.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 62,
		Parent = overlay,
	})
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	Ocean.playSound("rbxasset://sounds/swoosh.wav", 0.7, 1.4)

	-- Reveal.
	local a = Config.AnimalById[info.animal]
	local animal = Voxel.animal(info.animal, info.variant)
	local avf = Viewport.show(stage, animal, { ZIndex = 61 })
	local abase = animal:GetPivot()
	local scale = Ui.new("UIScale", { Scale = 0.3, Parent = stage })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local texts = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(600, 170),
		Position = UDim2.new(0.5, 0, 0.45, 190),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 63,
		Parent = overlay,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = texts })
	local function line(text: string, color: Color3, h: number, order: number)
		Ui.text({ Text = text, Size = UDim2.new(1, 0, 0, h), TextColor3 = color, StrokeThickness = 3, LayoutOrder = order, ZIndex = 63, Parent = texts })
	end
	if newlyFound[info.animal] then
		newlyFound[info.animal] = nil
		line("NEW!", C.Yellow, 30, 0)
	end
	if info.variant ~= "Normal" then
		line(info.variant, Config.Variants[info.variant].color, 30, 1)
	end
	line(a.name, C.White, 56, 2)
	line(a.rarity, Config.Rarities[Config.RarityIndex[a.rarity]].color, 34, 3)
	line(Format.cash(Formulas.animalIncome(info.animal, info.variant)) .. "/s", C.Cash, 34, 4)

	skip = false
	local t1 = os.clock()
	while os.clock() - t1 < 2.6 and not skip do
		animal:PivotTo(abase * CFrame.Angles(0, (os.clock() - t1) * 1.4, 0))
		RunService.RenderStepped:Wait()
	end
	avf:Destroy()
	overlay:Destroy()
end

local function pump()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		play(table.remove(queue, 1))
	end
	playing = false
end

function Hatch.init()
	gui = Ui.screen("Hatch", 10)
	State.effect:Connect(function(kind, payload)
		if kind == "discover" then
			newlyFound[payload.animal] = true
		elseif kind == "hatch" then
			table.insert(queue, payload)
			task.spawn(pump)
		end
	end)
end

return Hatch
