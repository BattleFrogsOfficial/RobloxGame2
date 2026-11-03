--!strict
-- Per-zone lighting ambience. Blends Lighting (ClockTime / Ambient / OutdoorAmbient), the global Atmosphere
-- colour and a dedicated ColorCorrectionEffect ("ZoneAmbienceCC") toward a preset for the fetch-field zone the
-- CAMERA is in (the throw cutscene camera flies into the zones), with TweenService transitions. On the
-- platform / plaza / yards (and in the Backyard) it restores the global defaults captured at start-up from
-- whatever the server's World/Lighting set. Purely cosmetic and client-local.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local Zones = require(Config:WaitForChild("Zones")) :: any

local rgb = Color3.fromRGB

type Preset = {
	ClockTime: number?,
	Ambient: Color3?,
	OutdoorAmbient: Color3?,
	Tint: Color3?,
	Saturation: number?,
	Contrast: number?,
	Brightness: number?,
	AtmoColor: Color3?,
	AtmoDecay: Color3?,
	AtmoDensity: number?,
	AtmoHaze: number?,
}

-- Missing fields fall back to the captured defaults. Backyard = home look (no override).
local PRESETS: { [string]: Preset } = {
	Backyard = {},
	Park = { ClockTime = 13.6, Tint = rgb(255, 252, 238), Saturation = 0.05 },
	Beach = { ClockTime = 13, Tint = rgb(255, 248, 226), Saturation = 0.12, Brightness = 0.03,
		AtmoColor = rgb(215, 238, 255), AtmoHaze = 0.3 },
	Farm = { ClockTime = 16.3, OutdoorAmbient = rgb(175, 155, 120), Tint = rgb(255, 236, 200), Saturation = 0.08,
		AtmoColor = rgb(255, 225, 180), AtmoDecay = rgb(220, 160, 110) },
	Forest = { ClockTime = 15.2, Ambient = rgb(90, 112, 90), OutdoorAmbient = rgb(100, 132, 100), Tint = rgb(225, 255, 228),
		Brightness = -0.03, AtmoColor = rgb(170, 210, 170), AtmoDecay = rgb(90, 130, 90), AtmoDensity = 0.32 },
	SnowyPeaks = { ClockTime = 11, OutdoorAmbient = rgb(185, 200, 225), Tint = rgb(236, 246, 255), Saturation = -0.05,
		Brightness = 0.05, AtmoColor = rgb(228, 238, 252), AtmoDecay = rgb(180, 200, 235), AtmoDensity = 0.36, AtmoHaze = 1.4 },
	CityRooftops = { ClockTime = 17.7, OutdoorAmbient = rgb(175, 135, 125), Tint = rgb(255, 222, 196), Contrast = 0.1,
		AtmoColor = rgb(255, 196, 160), AtmoDecay = rgb(200, 120, 130) },
	SpaceStation = { ClockTime = 23.4, Ambient = rgb(80, 90, 130), OutdoorAmbient = rgb(70, 82, 130), Tint = rgb(205, 218, 255),
		Contrast = 0.1, AtmoColor = rgb(40, 50, 90), AtmoDecay = rgb(20, 20, 50), AtmoDensity = 0.08, AtmoHaze = 0 },
	MythicMeadow = { ClockTime = 18.3, Ambient = rgb(145, 115, 175), OutdoorAmbient = rgb(195, 155, 225), Tint = rgb(255, 228, 250),
		Saturation = 0.15, AtmoColor = rgb(232, 196, 255), AtmoDecay = rgb(180, 120, 220) },
}

local TWEEN = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local FIELD_HALF_X = 260 -- the camera counts as "in the field" out to the scenery walls

-- our own colour correction, layered on top of the server's (neutral when no zone is active)
local cc = Lighting:FindFirstChild("ZoneAmbienceCC") :: ColorCorrectionEffect?
if cc == nil then
	local new = Instance.new("ColorCorrectionEffect")
	new.Name = "ZoneAmbienceCC"
	new.Parent = Lighting
	cc = new
end
local zoneCC = cc :: ColorCorrectionEffect

-- defaults: whatever the server set (captured once; the server applies Lighting before players join)
task.wait(1)
local defaults = {
	ClockTime = Lighting.ClockTime,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
}
local atmo: Atmosphere? = Lighting:FindFirstChildOfClass("Atmosphere")
local atmoDefaults = if atmo
	then { Color = atmo.Color, Decay = atmo.Decay, Density = atmo.Density, Haze = atmo.Haze }
	else nil
Lighting.ChildAdded:Connect(function(child)
	if atmo == nil and child:IsA("Atmosphere") then
		atmo = child
		atmoDefaults = { Color = child.Color, Decay = child.Decay, Density = child.Density, Haze = child.Haze }
	end
end)

local active: { Tween } = {}
local function play(inst: Instance, goal: { [string]: any })
	local t = TweenService:Create(inst, TWEEN, goal)
	table.insert(active, t)
	t:Play()
end

local function apply(zoneId: string?)
	for _, t in active do
		t:Cancel()
	end
	table.clear(active)
	local p: Preset = if zoneId then PRESETS[zoneId] or {} else {}
	play(Lighting, {
		ClockTime = p.ClockTime or defaults.ClockTime,
		Ambient = p.Ambient or defaults.Ambient,
		OutdoorAmbient = p.OutdoorAmbient or defaults.OutdoorAmbient,
	})
	play(zoneCC, {
		TintColor = p.Tint or Color3.new(1, 1, 1),
		Saturation = p.Saturation or 0,
		Contrast = p.Contrast or 0,
		Brightness = p.Brightness or 0,
	})
	local a, d = atmo, atmoDefaults
	if a and d then
		play(a, {
			Color = p.AtmoColor or d.Color,
			Decay = p.AtmoDecay or d.Decay,
			Density = p.AtmoDensity or d.Density,
			Haze = p.AtmoHaze or d.Haze,
		})
	end
end

local function zoneAt(pos: Vector3): string?
	if math.abs(pos.X - (Layout.Field.MinX + Layout.Field.MaxX) / 2) > FIELD_HALF_X then
		return nil
	end
	local distance = pos.Z - Layout.ThrowLine.Z
	if distance < 0 then
		return nil -- platform, plaza, street, yards
	end
	for _, z in Zones do
		if distance >= z.MinDistance and distance < z.MaxDistance then
			return z.Id
		end
	end
	if pos.Z <= Layout.Field.MaxZ + 300 then
		return Zones[#Zones].Id -- past the last band (end backdrop): stay in the last zone
	end
	return nil
end

local current: string? = "__init"
local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum < 0.2 then
		return
	end
	accum = 0
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local id = zoneAt(cam.CFrame.Position)
	if id == "Backyard" then
		id = nil -- home look
	end
	if id ~= current then
		current = id
		apply(id)
	end
end)
