--!strict
-- Bright, saturated afternoon look: high sun, soft atmosphere that keeps the far zones readable as
-- silhouettes, light bloom + saturation boost. Idempotent: reuses existing effect instances.
local LightingService = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldTheme = require(Shared:WaitForChild("Config"):WaitForChild("WorldTheme")) :: any

local Lighting = {}

-- Studio's default names for these effects. An effect with one of these names (e.g. placed by hand in Studio)
-- is adopted; anything else (in particular the client's "ZoneAmbienceCC" from ZoneAmbience.client.luau) is
-- never renamed or reconfigured.
local STUDIO_DEFAULT_NAMES: { [string]: string } = {
	Atmosphere = "Atmosphere",
	Sky = "Sky",
	BloomEffect = "Bloom",
	ColorCorrectionEffect = "ColorCorrection",
	SunRaysEffect = "SunRays",
}

local function getOrCreate(className: string, name: string): Instance
	local existing = LightingService:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local default = STUDIO_DEFAULT_NAMES[className]
	local adopt = default and LightingService:FindFirstChild(default)
	if adopt and adopt.ClassName == className then
		adopt.Name = name
		return adopt
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = LightingService
	return inst
end

-- SERVER ONLY (called by WorldBuilder). The client never runs this; ZoneAmbience.client.luau layers its own
-- ZoneAmbienceCC on top of what the server set.
function Lighting.Apply()
	if not RunService:IsServer() then
		warn("[Lighting] Apply is server-only; ignored on the client")
		return
	end
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
