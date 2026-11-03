--!nocheck
-- Minimal Rojo-tree module loader for Lune tests: real Roblox datatypes from @lune/roblox (Vector3, CFrame,
-- Color3, ...) and a `script` object per module whose Parent / WaitForChild / FindFirstChild walk the source
-- folders, so pure shared/server modules run unmodified. Usage (from the repo root):
--   local Loader = require("./loader")
--   local Shared = Loader.Mount("src/shared")      -- folder node
--   local Meter = Loader.Require(Shared.Util.Meter)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local cache = {}

-- The tree is built eagerly (fs calls yield, which a metamethod may not do).
local Node = {}
Node.__index = Node
function Node:WaitForChild(name)
	local c = self.Children[name]
	assert(c, ("WaitForChild: %s has no child %s"):format(tostring(self.Path), name))
	return c
end
function Node:FindFirstChild(name)
	return self.Children[name]
end
function Node:IsA(cls)
	return cls == "Instance" or cls == (if self.File then "ModuleScript" else "Folder")
end

local function build(path, name, parent)
	local node = setmetatable({ Name = name, Parent = parent, Path = path, Children = {}, File = nil }, Node)
	if fs.isFile(path) then
		node.File = path
		return node
	end
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			node.Children[entry] = build(full, entry, node)
		elseif entry == "init.luau" then
			node.File = full
		else
			local base = entry:match("^(.-)%.luau$") or entry:match("^(.-)%.lua$")
			if base then
				base = base:gsub("%.server$", ""):gsub("%.client$", "")
				node.Children[base] = build(full, base, node)
			end
		end
	end
	-- children readable as fields too (Shared.Config.Game)
	for k, v in node.Children do
		if Node[k] == nil and rawget(node, k) == nil then
			rawset(node, k, v)
		end
	end
	return node
end

function Loader.Mount(dirPath: string)
	assert(fs.isDir(dirPath), "no such dir " .. dirPath)
	return build(dirPath, dirPath:match("[^/]+$"), nil)
end

local fakeGame = {
	GetService = function(_, name)
		error("tests: game:GetService(" .. tostring(name) .. ") is not available to pure modules")
	end,
}

function Loader.Require(node)
	local file = node.File
	assert(file, "not a module: " .. tostring(node.Path))
	if cache[file] ~= nil then
		return cache[file]
	end
	local env = setmetatable({
		script = node,
		require = Loader.Require,
		game = fakeGame,
		workspace = nil,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Random = roblox.Random,
		typeof = roblox.typeof or typeof,
	}, { __index = _G })
	local fn = luau.load(fs.readFile(file), { debugName = file, environment = env })
	local result = fn()
	cache[file] = result
	return result
end

-- Tiny assertion helpers shared by the tests.
local passed, failed = 0, 0
function Loader.Check(ok: boolean, label: string, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. label .. (if detail then ("  (" .. detail .. ")") else ""))
	end
end
function Loader.Done(name: string): number
	print(("%s: %d passed, %d failed"):format(name, passed, failed))
	return failed
end

return Loader
