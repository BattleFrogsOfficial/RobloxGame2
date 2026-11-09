--!nocheck
-- Builds a Roblox place file from src/ without Rojo, using the same layout as
-- default.project.json.
--
-- Run from the repo root:   lune run tools/build-place.luau [output.rbxl]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local Instance = roblox.Instance
local output = process.args[1] or "SplitTheOceanForEggs.rbxl"

-- Mirror a folder the way Rojo does: init.server.luau / init.client.luau /
-- init.luau turn the folder itself into a script; other .luau files become
-- ModuleScripts; sub-folders recurse.
local function mount(dir: string, name: string, parent)
	local node
	local scripts = {
		{ file = "init.server.luau", class = "Script" },
		{ file = "init.client.luau", class = "LocalScript" },
		{ file = "init.luau", class = "ModuleScript" },
	}
	for _, s in scripts do
		if fs.isFile(dir .. "/" .. s.file) then
			node = Instance.new(s.class)
			node.Source = fs.readFile(dir .. "/" .. s.file)
			break
		end
	end
	node = node or Instance.new("Folder")
	node.Name = name
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			mount(path, entry, node)
		elseif entry:match("%.luau$") and not entry:match("^init%.") then
			local module = Instance.new("ModuleScript")
			module.Name = (entry:gsub("%.luau$", ""))
			module.Source = fs.readFile(path)
			module.Parent = node
		end
	end
	node.Parent = parent
	return node
end

local game = Instance.new("DataModel")
mount("src/shared", "Shared", game:GetService("ReplicatedStorage"))
mount("src/server", "Server", game:GetService("ServerScriptService"))
local starterScripts = Instance.new("StarterPlayerScripts")
starterScripts.Parent = game:GetService("StarterPlayer")
mount("src/client", "Client", starterScripts)

-- Services the game uses, so they exist in the saved place.
for _, service in { "Workspace", "Lighting", "StarterPack", "StarterGui", "SoundService", "Players" } do
	game:GetService(service)
end

fs.writeFile(output, roblox.serializePlace(game))

-- Read it back to prove the file is valid and complete.
local check = roblox.deserializePlace(fs.readFile(output))
local scripts = 0
for _, d in check:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		assert(#d.Source > 0, "empty script: " .. d:GetFullName())
		scripts += 1
	end
end
print(string.format("Wrote %s (%d scripts, %.0f KB)", output, scripts, #fs.readFile(output) / 1024))
