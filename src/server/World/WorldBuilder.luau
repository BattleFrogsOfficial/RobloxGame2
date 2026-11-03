--!strict
-- WORLD BUILDER (agent D). Builds the whole T-shaped map procedurally under workspace.Map, then runs
-- WorldCheck (warnings in the output). Headless twin: lune run tools/worldcheck/run.luau
-- Build() is idempotent: it destroys any previous workspace.Map, builds a fresh one detached,
-- then parents it in one go (so tag-added signals fire once everything exists).
-- Every coordinate comes from Config/Layout.luau (+ Zones.luau); colours from Config/WorldTheme.luau.
local Workspace = game:GetService("Workspace")

local World = script.Parent :: Instance
local Props = require(World:WaitForChild("Props")) :: any

local WorldBuilder = {}

-- Remove the default template Baseplate / SpawnLocation (they overlap the map at Y = 0).
WorldBuilder.RemoveTemplateParts = true

WorldBuilder.Steps = { "Outskirts", "Yards", "Street", "Plaza", "Platform", "ThrowLine", "Cliff", "Field", "Boundaries",
	"Walls" }
-- step names to skip (the headless checker uses this for --no-field)
WorldBuilder.SkipSteps = {} :: { [string]: boolean }
-- run WorldCheck after building and warn every violation
WorldBuilder.RunCheck = true

function WorldBuilder.Build(): Folder
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	if WorldBuilder.RemoveTemplateParts then
		for _, child in Workspace:GetChildren() do
			if (child.Name == "Baseplate" and child:IsA("BasePart")) or child.ClassName == "SpawnLocation" then
				child:Destroy()
			end
		end
	end

	Props.PartCount = 0
	local map = Instance.new("Folder")
	map.Name = "Map"

	for _, name in WorldBuilder.Steps do
		if WorldBuilder.SkipSteps[name] then
			continue
		end
		local ok, err = pcall(function()
			local mod = require(World:WaitForChild(name)) :: any
			mod.Build(map)
		end)
		if not ok then
			warn(("[WorldBuilder] %s failed: %s"):format(name, tostring(err)))
		end
	end

	local okLight, errLight = pcall(function()
		local lighting = require(World:WaitForChild("Lighting")) :: any
		lighting.Apply()
	end)
	if not okLight then
		warn("[WorldBuilder] Lighting failed: " .. tostring(errLight))
	end

	if WorldBuilder.RunCheck then
		local okCheck, result = pcall(function()
			local check = require(World:WaitForChild("WorldCheck")) :: any
			return check.Check(map)
		end)
		if not okCheck then
			warn("[WorldCheck] failed to run: " .. tostring(result))
		else
			for _, v in result :: { string } do
				warn("[WorldCheck] " .. v)
			end
			map:SetAttribute("WorldCheckViolations", #(result :: { string }))
			if #(result :: { string }) == 0 then
				print("[WorldCheck] OK: tags on their ground, spawns clear")
			end
		end
	end

	map:SetAttribute("PartCount", Props.PartCount)
	map.Parent = Workspace
	print(("[WorldBuilder] map built: %d parts"):format(Props.PartCount))
	return map
end

return WorldBuilder
