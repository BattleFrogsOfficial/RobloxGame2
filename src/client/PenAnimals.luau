-- Animates the animals in every pen. The server publishes each walk as
-- attributes on the animal model (WalkFrom, WalkTo, WalkStart, WalkDuration);
-- this hops the model along that line locally so it looks smooth.

local RunService = game:GetService("RunService")

local PenAnimals = {}

local HOP_LENGTH = 3.2 -- studs per hop
local HOP_HEIGHT = 1.1

local animals: { Model } = {}
local lastScan = 0

local function scan()
	table.clear(animals)
	local pens = workspace:FindFirstChild("Pens")
	if not pens then
		return
	end
	for _, pen in pens:GetChildren() do
		local contents = pen:FindFirstChild("Contents")
		if contents then
			for _, m in contents:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("Animal") and m.PrimaryPart then
					table.insert(animals, m)
				end
			end
		end
	end
end

local function update()
	local clock = os.clock()
	if clock - lastScan > 0.5 then
		lastScan = clock
		scan()
	end
	local now = workspace:GetServerTimeNow()
	for _, model in animals do
		-- Skip animals sold or stored since the last scan.
		local alive = model.Parent ~= nil
		local start = alive and model:GetAttribute("WalkStart")
		local duration = alive and model:GetAttribute("WalkDuration")
		local root = alive and model.PrimaryPart
		if start and duration and root then
			local alpha = (now - start) / duration
			if alpha >= 0 and alpha < 1 then
				local from = model:GetAttribute("WalkFrom") :: Vector3
				local to = model:GetAttribute("WalkTo") :: Vector3
				local span = to - from
				local dist = span.Magnitude
				if dist > 0.1 then
					local hops = math.max(1, math.floor(dist / HOP_LENGTH + 0.5))
					local lift = math.abs(math.sin(alpha * hops * math.pi)) * HOP_HEIGHT
					local pos = from + span * alpha + Vector3.new(0, lift, 0)
					root.CFrame = CFrame.lookAt(pos, pos + span.Unit)
				end
			end
		end
	end
end

function PenAnimals.init()
	RunService.RenderStepped:Connect(update)
end

return PenAnimals
