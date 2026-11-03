--!nonstrict
-- leaderstats (Income $/s, Cash) for the Roblox player list. There is no in-world board; global boards are
-- a v1.1 TODO.

local DataService = require(script.Parent:WaitForChild("DataService"))
local DogService = require(script.Parent:WaitForChild("DogService"))

local LeaderboardService = {}

local function makeStats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local inc = Instance.new("NumberValue")
	inc.Name = "$/s"
	inc.Parent = folder
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Parent = folder
	folder.Parent = player
end

local function updateStats()
	for _, player in DataService.Players() do
		local state = DataService.Get(player)
		local ls = player:FindFirstChild("leaderstats")
		if state and ls then
			local inc = ls:FindFirstChild("$/s") :: NumberValue
			local cash = ls:FindFirstChild("Cash") :: NumberValue
			if inc then
				inc.Value = math.floor(DogService.CurrentIncome(player))
			end
			if cash then
				cash.Value = math.floor(state.Cash)
			end
		end
	end
end

function LeaderboardService.Start()
	DataService.OnLoaded(function(player: Player)
		makeStats(player)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(updateStats)
			if not ok then
				warn("[LeaderboardService] " .. tostring(err))
			end
		end
	end)
end

return LeaderboardService
