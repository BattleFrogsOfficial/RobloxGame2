-- Three physical leaderboards standing against the back wall: Most Cash
-- Earned, Strongest and Most Eggs. Rankings are global (OrderedDataStores),
-- merged with the live numbers of everyone in this server so the boards
-- move while you play. Without DataStore access they rank this server only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Data = require(script.Parent.Data)
local World = require(script.Parent.World)

local Leaderboards = {}

local ROWS = 10
local REFRESH_SECONDS = 60
local MAX_VALUE = 9e15 -- OrderedDataStores hold integers

local BOARDS = {
	{
		key = "Cash",
		title = "MOST CASH EARNED",
		color = Color3.fromRGB(95, 215, 75),
		value = function(d)
			return d.stats.totalEarned
		end,
		format = Format.cash,
	},
	{
		key = "Strength",
		title = "STRONGEST",
		color = Color3.fromRGB(255, 205, 55),
		value = function(d)
			return d.strength
		end,
		format = Format.short,
	},
	{
		key = "Eggs",
		title = "MOST EGGS",
		color = Color3.fromRGB(70, 195, 235),
		value = function(d)
			return d.stats.eggsCollected
		end,
		format = Format.short,
	},
}

local names: { [number]: string } = {}
local refreshQueued = false

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and name or ("Player " .. userId)
	return names[userId]
end

local function text(parent: Instance, props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	for k, v in props do
		(label :: any)[k] = v
	end
	label.Parent = parent
	return label
end

local function buildBoard(board, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Leaderboard" .. board.key

	local function part(size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local dark = Color3.fromRGB(45, 48, 60)
	for _, x in { -13.5, 13.5 } do
		part(Vector3.new(2, 44, 2), CFrame.new(x, 22, 0), dark)
	end
	part(Vector3.new(30, 2.4, 2.4), CFrame.new(0, 44, 0), board.color)
	local face = part(Vector3.new(25, 34, 1), CFrame.new(0, 25, 0), Color3.fromRGB(30, 32, 40))
	face.Name = "Face"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- the board's front faces the ocean
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = face

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0.13, 0)
	header.BackgroundColor3 = board.color
	header.BorderSizePixel = 0
	header.Parent = gui
	text(header, { Size = UDim2.new(1, -20, 0.8, 0), Position = UDim2.new(0, 10, 0.1, 0), Text = board.title })

	board.rows = {}
	for i = 1, ROWS do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0.087, 0)
		row.Position = UDim2.new(0, 0, 0.13 + (i - 1) * 0.087, 0)
		row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(38, 41, 52) or Color3.fromRGB(30, 32, 40)
		row.BorderSizePixel = 0
		row.Parent = gui
		local rankColor = i == 1 and Color3.fromRGB(255, 215, 70) or i == 2 and Color3.fromRGB(215, 220, 230) or i == 3 and Color3.fromRGB(230, 150, 90) or Color3.new(1, 1, 1)
		text(row, { Size = UDim2.new(0.12, 0, 0.8, 0), Position = UDim2.new(0.02, 0, 0.1, 0), Text = tostring(i), TextColor3 = rankColor })
		local name = text(row, { Size = UDim2.new(0.5, 0, 0.7, 0), Position = UDim2.new(0.16, 0, 0.15, 0), Text = "-", TextXAlignment = Enum.TextXAlignment.Left })
		local value = text(row, { Size = UDim2.new(0.3, 0, 0.7, 0), Position = UDim2.new(0.68, 0, 0.15, 0), Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = board.color })
		board.rows[i] = { name = name, value = value }
	end

	model.Parent = workspace:FindFirstChild("Map") or workspace
end

local function refreshBoard(board)
	local scores: { [number]: number } = {}

	-- Global standings.
	if board.store then
		local ok, entries = pcall(function()
			return board.store:GetSortedAsync(false, ROWS):GetCurrentPage()
		end)
		if ok then
			for _, entry in entries do
				local userId = tonumber(entry.key)
				if userId then
					scores[userId] = entry.value
				end
			end
		end
	end

	-- Everyone here, live (and saved for the global board).
	for _, player in Players:GetPlayers() do
		local d = Data.get(player)
		if d then
			local value = math.floor(math.clamp(board.value(d), 0, MAX_VALUE))
			scores[player.UserId] = math.max(scores[player.UserId] or 0, value)
			local session = Data.session(player)
			if board.store and session and session.canSave and value > 0 then
				pcall(function()
					board.store:SetAsync(tostring(player.UserId), value)
				end)
			end
		end
	end

	local list = {}
	for userId, value in scores do
		if value > 0 then
			table.insert(list, { userId = userId, value = value })
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	for i, row in board.rows do
		local entry = list[i]
		row.name.Text = entry and nameOf(entry.userId) or "-"
		row.value.Text = entry and board.format(entry.value) or ""
	end
end

function Leaderboards.refresh()
	for _, board in BOARDS do
		refreshBoard(board)
	end
end

-- Refresh soon (batched), e.g. after someone joins.
function Leaderboards.refreshSoon()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(4, function()
		refreshQueued = false
		Leaderboards.refresh()
	end)
end

function Leaderboards.init()
	for i, board in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("SplitTheOcean_Top" .. board.key .. "_v1")
		end)
		board.store = ok and store or nil
		buildBoard(board, World.BoardSpots[i])
	end
	Data.Loaded.Event:Connect(Leaderboards.refreshSoon)
	task.spawn(function()
		while true do
			Leaderboards.refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return Leaderboards
