--!nocheck
-- Compile check over every cutscene file (luau.compile from @lune/luau): syntax errors fail the test.
--   lune run tools/tests/cutscene_compile.luau
-- Also checks the cutscene never reads anything that could change an outcome (no RemoteFunction invokes,
-- no FireServer outside ui:FinishThrow) and that the old placeholder contract is gone.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Loader = require("./loader")
local check = Loader.Check

local files = {}
local function walk(dir)
	if not fs.isDir(dir) then
		return
	end
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			walk(full)
		elseif string.match(entry, "%.luau$") then
			table.insert(files, full)
		end
	end
end
walk("src/client/Cutscene")
walk("src/shared/Cutscene")
walk("src/shared/Dog")
walk("src/client/UI")
for _, f in { "src/shared/Config/Cutscene.luau", "src/client/Main.client.luau", "src/client/BallFlight.client.luau",
	"tools/tests/cutscene.luau", "tools/tests/cutscene_counter.luau", "tools/tests/cutscene_path.luau",
	"tools/tests/cutscene_director.luau", "tools/uicheck/roblox.luau",
	"tools/uicheck/run.luau" } do
	table.insert(files, f)
end
table.sort(files)
for _, f in files do
	local src = fs.readFile(f)
	local ok, err = pcall(luau.compile, src, { debugName = f })
	check(ok, "compiles: " .. f, tostring(err))
end
print(("compiled %d files"):format(#files))

-- Outcome safety: cutscene code never talks to the server except through ui:FinishThrow (CutsceneFinished).
for _, f in files do
	if string.find(f, "src/client/Cutscene/", 1, true) or string.find(f, "src/shared/Cutscene/", 1, true) then
		local src = fs.readFile(f)
		check(not string.find(src, "FireServer", 1, true), "no FireServer in " .. f)
		check(not string.find(src, "InvokeServer", 1, true), "no InvokeServer in " .. f)
	end
end
check(not fs.isFile("src/shared/Cutscene/PlaceholderCutscene.luau"), "placeholder cutscene retired")
check(not fs.isFile("src/client/Controllers/CutsceneController.luau"), "old CutsceneController removed")
local init = fs.readFile("src/client/UI/init.luau")
check(string.find(init, 'fire("CutsceneFinished", throwId)', 1, true) ~= nil and string.find(init, "reported[throwId] = true", 1, true) ~= nil,
	"ui:FinishThrow sends CutsceneFinished exactly once")
local main = fs.readFile("src/client/Main.client.luau")
check(string.find(main, "PlaceholderCutscene = false", 1, true) ~= nil, "UI starts with PlaceholderCutscene = false")

process.exit(Loader.Done("cutscene_compile") > 0 and 1 or 0)
