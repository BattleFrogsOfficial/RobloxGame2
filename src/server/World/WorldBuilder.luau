--!strict
-- WORLD BUILDER (agent D). Builds the whole T-shaped map procedurally under workspace.Map.
-- Build() is idempotent: it destroys any previous workspace.Map, builds a fresh one detached,
-- then parents it in one go (so tag-added signals fire once everything exists).
-- Every coordinate comes from Config/Layout.luau (+ Zones.luau); colours from Config/WorldTheme.luau.
local Workspace = game:GetService("Workspace")

local World = script.Parent :: Instance
local Props = require(World:WaitForChild("Props")) :: any

local WorldBuilder = {}

-- Remove the default template Baseplate / SpawnLocation (they overlap the map at Y = 0).
WorldBuilder.RemoveTemplateParts = true

local STEPS = { "Outskirts", "Yards", "Street", "Plaza", "ThrowLine", "Field", "Boundaries" }

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

	for _, name in STEPS do
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

	map:SetAttribute("PartCount", Props.PartCount)
	map.Parent = Workspace
	print(("[WorldBuilder] map built: %d parts"):format(Props.PartCount))
	return map
end

return WorldBuilder
