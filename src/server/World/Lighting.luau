--!strict
-- Bright, saturated afternoon look: high sun, soft atmosphere that keeps the far zones readable as
-- silhouettes, light bloom + saturation boost. Idempotent: reuses existing effect instances.
local LightingService = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldTheme = require(Shared:WaitForChild("Config"):WaitForChild("WorldTheme")) :: any

local Lighting = {}

local function getOrCreate(className: string, name: string): Instance
	local existing = LightingService:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local byClass = LightingService:FindFirstChildOfClass(className)
	if byClass then
		byClass.Name = name
		return byClass
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = LightingService
	return inst
end

function Lighting.Apply()
	local L = WorldTheme.Lighting
	LightingService.ClockTime = L.ClockTime
	LightingService.GeographicLatitude = 35
	LightingService.Brightness = L.Brightness
	LightingService.Ambient = L.Ambient
	LightingService.OutdoorAmbient = L.OutdoorAmbient
	LightingService.ColorShift_Top = L.ColorShiftTop
	LightingService.ExposureCompensation = L.ExposureCompensation
	LightingService.GlobalShadows = true
	LightingService.ShadowSoftness = 0.4
	LightingService.EnvironmentDiffuseScale = 0.6
	LightingService.EnvironmentSpecularScale = 0.3
	LightingService.FogEnd = 100000

	local atmo = getOrCreate("Atmosphere", "WorldAtmosphere") :: Atmosphere
	atmo.Density = L.Atmosphere.Density
	atmo.Offset = L.Atmosphere.Offset
	atmo.Color = L.Atmosphere.Color
	atmo.Decay = L.Atmosphere.Decay
	atmo.Glare = L.Atmosphere.Glare
	atmo.Haze = L.Atmosphere.Haze

	local sky = getOrCreate("Sky", "WorldSky") :: Sky
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.StarCount = 1500

	local bloom = getOrCreate("BloomEffect", "WorldBloom") :: BloomEffect
	bloom.Intensity = L.Bloom.Intensity
	bloom.Size = L.Bloom.Size
	bloom.Threshold = L.Bloom.Threshold

	local cc = getOrCreate("ColorCorrectionEffect", "WorldColor") :: ColorCorrectionEffect
	cc.Saturation = L.ColorCorrection.Saturation
	cc.Contrast = L.ColorCorrection.Contrast
	cc.Brightness = L.ColorCorrection.Brightness
	cc.TintColor = L.ColorCorrection.TintColor

	local rays = getOrCreate("SunRaysEffect", "WorldSunRays") :: SunRaysEffect
	rays.Intensity = L.SunRays.Intensity
	rays.Spread = L.SunRays.Spread
end

return Lighting
