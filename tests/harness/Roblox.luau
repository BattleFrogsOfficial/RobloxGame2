--!nocheck
-- A small fake Roblox engine for running the real game code under Lune.
--
-- Lune's `roblox` library gives us real Instances backed by the Roblox API
-- database, so wrong property names, wrong value types and enum items that
-- don't exist all throw, exactly like in Studio. This file adds what Lune
-- leaves out: events, a virtual-time task scheduler, remotes that deliver
-- between "server" and "client", tweens, DataStores, and a few methods.
--
-- Nothing here is game specific. See tests/game.spec.luau for the scenarios.

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Harness = {}
Harness.__index = Harness

local current -- the active harness (class-level mocks route through it)

----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {}, waiters = {} }, Signal)
end

function Signal:Connect(fn)
	local conn = { Connected = true }
	local handlers = self.handlers
	table.insert(handlers, { conn = conn, fn = fn })
	-- Roblox queues remote events fired before anything is listening.
	if self.queued and #self.queued > 0 then
		local queued = self.queued
		self.queued = {}
		for _, args in queued do
			current.task.defer(fn, table.unpack(args, 1, args.n))
		end
	end
	function conn.Disconnect()
		conn.Connected = false
		for i, h in handlers do
			if h.conn == conn then
				table.remove(handlers, i)
				break
			end
		end
	end
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	table.insert(self.waiters, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	if self.queued and #self.handlers == 0 then
		table.insert(self.queued, table.pack(...))
		return
	end
	for _, h in table.clone(self.handlers) do
		if h.conn.Connected then
			current.task.spawn(h.fn, ...)
		end
	end
	local waiters = self.waiters
	self.waiters = {}
	for _, co in waiters do
		current:_resume(co, ...)
	end
end

local function signalOf(inst, name)
	local map = current.signals[inst]
	if not map then
		map = {}
		current.signals[inst] = map
	end
	if not map[name] then
		map[name] = Signal.new()
	end
	return map[name]
end

----------------------------------------------------------------------------
-- Remote argument validation: Roblox drops or mangles tables that mix array
-- and dictionary keys, have holes, or use non-string dictionary keys.
----------------------------------------------------------------------------
local function validateRemoteValue(v, path)
	if type(v) ~= "table" then
		return
	end
	local n = 0
	local stringKeys, numberKeys = 0, 0
	for k, child in v do
		n += 1
		if type(k) == "string" then
			stringKeys += 1
		elseif type(k) == "number" then
			numberKeys += 1
		else
			error("remote table at " .. path .. " has a non-string, non-number key", 0)
		end
		validateRemoteValue(child, path .. "." .. tostring(k))
	end
	if stringKeys > 0 and numberKeys > 0 then
		error("remote table at " .. path .. " mixes array and dictionary keys", 0)
	end
	if numberKeys > 0 and #v ~= n then
		error("remote table at " .. path .. " is a sparse array (has holes)", 0)
	end
end

local function validateArgs(what, ...)
	for i = 1, select("#", ...) do
		validateRemoteValue((select(i, ...)), what .. " arg " .. i)
	end
end

-- Deep copy so the receiver can't share tables with the sender (as in Roblox).
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, child in v do
		t[k] = copy(child)
	end
	return t
end

local function copyArgs(...)
	local out = table.pack(...)
	for i = 1, out.n do
		out[i] = copy(out[i])
	end
	return table.unpack(out, 1, out.n)
end

----------------------------------------------------------------------------
-- Class-level mocks (registered once per process)
----------------------------------------------------------------------------
local EVENTS = {
	RunService = { "Heartbeat", "RenderStepped", "Stepped" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	ProximityPrompt = { "Triggered" },
	GuiObject = { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" },
	GuiButton = { "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged" },
	Sound = { "Ended" },
	Instance = { "DescendantAdded", "ChildAdded", "ChildRemoved", "AncestryChanged", "Destroying" },
	MarketplaceService = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished" },
	Humanoid = { "Died" },
}

local function setCFrame(part, cf)
	part.CFrame = cf
	part.Position = cf.Position
end

local function partsOf(model)
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function pivotOf(model)
	local primary = model.PrimaryPart
	if primary then
		return primary.CFrame
	end
	return current.pivots[model] or roblox.CFrame.new()
end

local registered = false
local function registerMocks()
	if registered then
		return
	end
	registered = true

	for class, names in EVENTS do
		for _, name in names do
			roblox.implementProperty(class, name, function(self)
				return signalOf(self, name)
			end)
		end
	end

	local function method(class, name, fn)
		roblox.implementMethod(class, name, fn)
	end

	-- Instance
	method("Instance", "WaitForChild", function(self, name)
		local child = self:FindFirstChild(name)
		if not child then
			error("WaitForChild would wait forever: " .. self:GetFullName() .. "." .. tostring(name), 2)
		end
		return child
	end)
	method("Instance", "GetPropertyChangedSignal", function(self, prop)
		return signalOf(self, "prop:" .. prop)
	end)
	method("Instance", "GetAttributeChangedSignal", function(self, attr)
		return signalOf(self, "attr:" .. attr)
	end)

	-- Models
	method("Model", "GetPivot", function(self)
		return pivotOf(self)
	end)
	method("Model", "PivotTo", function(self, cf)
		assert(typeof(cf) == "CFrame", "PivotTo expects a CFrame")
		local delta = cf * pivotOf(self):Inverse()
		for _, p in partsOf(self) do
			setCFrame(p, delta * p.CFrame)
		end
		current.pivots[self] = cf
	end)
	method("Model", "GetBoundingBox", function(self)
		local minV, maxV
		for _, p in partsOf(self) do
			local c, h = p.CFrame.Position, p.Size / 2
			local lo = roblox.Vector3.new(c.X - h.X, c.Y - h.Y, c.Z - h.Z)
			local hi = roblox.Vector3.new(c.X + h.X, c.Y + h.Y, c.Z + h.Z)
			if not minV then
				minV, maxV = lo, hi
			else
				minV = roblox.Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z))
				maxV = roblox.Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z))
			end
		end
		if not minV then
			return roblox.CFrame.new(), roblox.Vector3.new()
		end
		return roblox.CFrame.new((minV + maxV) / 2), maxV - minV
	end)
	method("Model", "ScaleTo", function(self, scale)
		assert(type(scale) == "number" and scale > 0, "ScaleTo expects a positive number")
		local pivot = pivotOf(self)
		for _, p in partsOf(self) do
			local rel = pivot:ToObjectSpace(p.CFrame)
			p.Size = p.Size * scale
			setCFrame(p, pivot * (rel.Rotation + rel.Position * scale))
		end
	end)

	-- Services
	method("Players", "GetPlayers", function(self)
		local list = {}
		for _, c in self:GetChildren() do
			if c:IsA("Player") then
				table.insert(list, c)
			end
		end
		return list
	end)
	method("Players", "GetPlayerByUserId", function(self, id)
		for _, c in self:GetChildren() do
			if c:IsA("Player") and c.UserId == id then
				return c
			end
		end
		return nil
	end)
	method("Players", "GetUserThumbnailAsync", function(_, id)
		return "rbxthumb://type=AvatarHeadShot&id=" .. id .. "&w=150&h=150", true
	end)
	method("RunService", "IsServer", function()
		return current.context == "server"
	end)
	method("RunService", "IsClient", function()
		return current.context == "client"
	end)
	method("RunService", "IsStudio", function()
		return current.studio
	end)
	method("Workspace", "GetServerTimeNow", function()
		return current.epoch + current.clock
	end)
	method("Debris", "AddItem", function(_, inst, life)
		current.task.delay(life or 10, function()
			inst:Destroy()
		end)
	end)
	method("DataModel", "BindToClose", function(_, fn)
		table.insert(current.closers, fn)
	end)
	method("StarterGui", "SetCoreGuiEnabled", function(_, kind, enabled)
		assert(typeof(kind) == "EnumItem" and type(enabled) == "boolean", "SetCoreGuiEnabled(CoreGuiType, boolean)")
		current.coreGui[kind.Name] = enabled
	end)
	method("GuiService", "IsTenFootInterface", function()
		return false
	end)

	method("TweenService", "Create", function(_, inst, info, goals)
		assert(typeof(inst) == "Instance", "TweenService:Create needs an Instance")
		assert(type(info) == "table" and info.__tweenInfo, "TweenService:Create needs a TweenInfo")
		local tween = { Completed = Signal.new(), PlaybackState = "Begin" }
		function tween:Play()
			-- Apply the goal right away: this validates every property name
			-- and type. Completed fires after the tween's duration.
			for prop, value in goals do
				inst[prop] = value
				if prop == "CFrame" then
					inst.Position = value.Position
				end
			end
			current.task.delay(info.Time, function()
				tween.PlaybackState = "Completed"
				tween.Completed:Fire("Completed")
			end)
		end
		function tween:Cancel() end
		function tween:Pause() end
		return tween
	end)

	-- Remotes
	method("RemoteEvent", "FireClient", function(self, player, ...)
		assert(typeof(player) == "Instance" and player:IsA("Player"), "FireClient needs a Player")
		validateArgs(self.Name .. ":FireClient", ...)
		-- Only one client is simulated; it may not have connected yet.
		if current.localPlayer == nil or player == current.localPlayer then
			local signal = signalOf(self, "OnClientEvent")
			signal.queued = signal.queued or {}
			current.task.defer(function(...)
				signal:Fire(...)
			end, copyArgs(...))
		end
	end)
	method("RemoteEvent", "FireAllClients", function(self, ...)
		validateArgs(self.Name .. ":FireAllClients", ...)
		current.task.defer(function(...)
			signalOf(self, "OnClientEvent"):Fire(...)
		end, copyArgs(...))
	end)
	method("RemoteEvent", "FireServer", function(self, ...)
		validateArgs(self.Name .. ":FireServer", ...)
		local player = current.localPlayer
		current.task.defer(function(...)
			signalOf(self, "OnServerEvent"):Fire(player, ...)
		end, copyArgs(...))
	end)
	roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self)
		return current.callbacks[self]
	end, function(self, fn)
		current.callbacks[self] = fn
	end)
	method("RemoteFunction", "InvokeServer", function(self, ...)
		validateArgs(self.Name .. ":InvokeServer", ...)
		local fn = current.callbacks[self]
		assert(fn, "InvokeServer: no OnServerInvoke set on " .. self.Name)
		local results = table.pack(fn(current.localPlayer, copyArgs(...)))
		validateArgs(self.Name .. " return", table.unpack(results, 1, results.n))
		return copyArgs(table.unpack(results, 1, results.n))
	end)
	method("BindableEvent", "Fire", function(self, ...)
		signalOf(self, "Event"):Fire(...)
	end)

	-- Marketplace
	roblox.implementProperty("MarketplaceService", "ProcessReceipt", function()
		return current.processReceipt
	end, function(_, fn)
		current.processReceipt = fn
	end)
	method("MarketplaceService", "UserOwnsGamePassAsync", function()
		return false
	end)
	method("MarketplaceService", "PromptGamePassPurchase", function(_, _, id)
		table.insert(current.prompts, { kind = "pass", id = id })
	end)
	method("MarketplaceService", "PromptProductPurchase", function(_, _, id)
		table.insert(current.prompts, { kind = "product", id = id })
	end)

	-- DataStores (in memory, JSON round-tripped like the real thing)
	method("DataStoreService", "GetDataStore", function(_, name)
		if current.dataStoreFails then
			error("DataStore unavailable (simulated)", 0)
		end
		local bucket = current.dataStores[name]
		if not bucket then
			bucket = {}
			current.dataStores[name] = bucket
		end
		local store = {}
		function store:GetAsync(key)
			local raw = bucket[key]
			return raw and serde.decode("json", raw) or nil
		end
		function store:SetAsync(key, value)
			validateRemoteValue(value, "DataStore[" .. key .. "]")
			bucket[key] = serde.encode("json", value)
		end
		function store:UpdateAsync(key, fn)
			local new = fn(self:GetAsync(key))
			if new ~= nil then
				self:SetAsync(key, new)
			end
			return new
		end
		return store
	end)

	method("DataStoreService", "GetOrderedDataStore", function(_, name)
		if current.dataStoreFails then
			error("DataStore unavailable (simulated)", 0)
		end
		local bucket = current.orderedStores[name]
		if not bucket then
			bucket = {}
			current.orderedStores[name] = bucket
		end
		local store = {}
		function store:SetAsync(key, value)
			assert(type(key) == "string", "OrderedDataStore keys are strings")
			assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore values must be integers")
			bucket[key] = value
		end
		function store:GetSortedAsync(ascending, pageSize)
			local list = {}
			for key, value in bucket do
				table.insert(list, { key = key, value = value })
			end
			table.sort(list, function(a, b)
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end)
			local page = {}
			for i = 1, math.min(pageSize, #list) do
				page[i] = list[i]
			end
			return {
				GetCurrentPage = function()
					return page
				end,
			}
		end
		return store
	end)
	method("Players", "GetNameFromUserIdAsync", function(_, id)
		return "User" .. id
	end)
	method("Humanoid", "ChangeState", function(_, state)
		assert(typeof(state) == "EnumItem", "ChangeState expects an Enum.HumanoidStateType")
	end)

	-- Misc
	method("Humanoid", "EquipTool", function(self, tool)
		tool.Parent = self.Parent
	end)
	method("Humanoid", "UnequipTools", function(self)
		local player = current.Players:GetPlayerFromCharacter(self.Parent)
		for _, c in self.Parent:GetChildren() do
			if c:IsA("Tool") and player then
				c.Parent = player:FindFirstChild("Backpack")
			end
		end
	end)
	method("Players", "GetPlayerFromCharacter", function(self, char)
		for _, p in self:GetChildren() do
			if p:IsA("Player") and p.Character == char then
				return p
			end
		end
		return nil
	end)
	method("ParticleEmitter", "Emit", function(_, n)
		assert(type(n) == "number", "Emit expects a count")
	end)
	method("Sound", "Play", function() end)
	method("Sound", "Stop", function() end)
end

----------------------------------------------------------------------------
-- Harness
----------------------------------------------------------------------------
local BASE_PART_CLASSES = { Part = true, WedgePart = true, SpawnLocation = true, MeshPart = true, Seat = true }

function Harness.new(options)
	registerMocks()
	options = options or {}
	local self = setmetatable({}, Harness)
	current = self

	self.clock = 100 -- os.clock()
	self.epoch = options.epoch or 1_700_000_000 -- os.time() = epoch + clock
	self.context = "server"
	self.studio = options.studio ~= false
	-- Strong keys on purpose: Lune hands out a fresh userdata for an Instance
	-- once the old one is collected, so weak keys would drop connections.
	self.signals = {}
	self.pivots = {}
	self.callbacks = {}
	self.closers = {}
	self.prompts = {}
	self.dataStores = options.dataStores or {}
	self.orderedStores = options.orderedStores or {}
	self.coreGui = {}
	self.dataStoreFails = options.dataStoreFails or false
	self.errors = {}
	self.warnings = {}
	self.timers = {}
	self.moduleCache = { server = {}, client = {} }
	self.sources = {}

	self:_buildScheduler()
	self:_buildDataModel()
	return self
end

function Harness:use()
	current = self
end

-- Scheduler ---------------------------------------------------------------
function Harness:_resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(self.errors, debug.traceback(co, tostring(err)))
	end
end

function Harness:_buildScheduler()
	local h = self
	local seq = 0
	local function schedule(at, co, args)
		seq += 1
		table.insert(h.timers, { at = at, seq = seq, co = co, args = args })
	end
	local task = {}
	function task.spawn(f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		h:_resume(co, ...)
		return co
	end
	function task.defer(f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		schedule(h.clock, co, table.pack(...))
		return co
	end
	function task.delay(t, f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		schedule(h.clock + math.max(t or 0, 0), co, table.pack(...))
		return co
	end
	function task.wait(t)
		local start = h.clock
		schedule(h.clock + math.max(t or 0, 1 / 240), coroutine.running(), nil)
		coroutine.yield()
		return h.clock - start
	end
	function task.cancel(co)
		for i, timer in h.timers do
			if timer.co == co then
				table.remove(h.timers, i)
				break
			end
		end
	end
	self.task = task
end

-- Run every timer that is due (including ones queued while running).
function Harness:_runDue()
	for _ = 1, 1000 do
		local due = {}
		local rest = {}
		for _, timer in self.timers do
			if timer.at <= self.clock then
				table.insert(due, timer)
			else
				table.insert(rest, timer)
			end
		end
		if #due == 0 then
			return
		end
		self.timers = rest
		table.sort(due, function(a, b)
			if a.at ~= b.at then
				return a.at < b.at
			end
			return a.seq < b.seq
		end)
		for _, timer in due do
			if timer.args then
				self:_resume(timer.co, table.unpack(timer.args, 1, timer.args.n))
			else
				self:_resume(timer.co)
			end
		end
	end
	error("scheduler did not settle (a task re-queues itself with no delay)")
end

-- Advance one frame.
function Harness:step(dt)
	dt = dt or 1 / 30
	self.clock += dt
	self:_runDue()
	local run = self.RunService
	signalOf(run, "Stepped"):Fire(self.clock, dt)
	signalOf(run, "Heartbeat"):Fire(dt)
	signalOf(run, "RenderStepped"):Fire(dt)
	self:_runDue()
end

function Harness:advance(seconds, dt)
	dt = dt or 1 / 30
	local frames = math.ceil(seconds / dt - 1e-9)
	for _ = 1, frames do
		self:step(dt)
	end
end

-- Data model ----------------------------------------------------------------
function Harness:_buildDataModel()
	local I = roblox.Instance
	local game = I.new("DataModel")
	self.game = game
	self.workspace = game:GetService("Workspace")
	self.Players = game:GetService("Players")
	self.RunService = game:GetService("RunService")
	self.ReplicatedStorage = game:GetService("ReplicatedStorage")

	self.workspace.Gravity = 196.2
	local camera = I.new("Camera")
	camera.Parent = self.workspace
	self.workspace.CurrentCamera = camera
	pcall(function()
		camera.ViewportSize = roblox.Vector2.new(1280, 720)
	end)
	local uis = game:GetService("UserInputService")
	pcall(function()
		uis.TouchEnabled = false
		uis.MouseEnabled = true
		uis.KeyboardEnabled = true
	end)

	-- A Baseplate + SpawnLocation like the Studio template.
	local baseplate = I.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Parent = self.workspace
	local templateSpawn = I.new("SpawnLocation")
	templateSpawn.Parent = self.workspace
end

-- Mirror a source folder into the data model the way Rojo does.
-- Returns the Instance for the folder (or the script, if it has an init file).
function Harness:mount(dir, name, parent)
	local I = roblox.Instance
	local initServer = dir .. "/init.server.luau"
	local initClient = dir .. "/init.client.luau"
	local initModule = dir .. "/init.luau"
	local node
	if fs.isFile(initServer) then
		node = I.new("Script")
		self.sources[node] = { path = initServer, text = fs.readFile(initServer) }
	elseif fs.isFile(initClient) then
		node = I.new("LocalScript")
		self.sources[node] = { path = initClient, text = fs.readFile(initClient) }
	elseif fs.isFile(initModule) then
		node = I.new("ModuleScript")
		self.sources[node] = { path = initModule, text = fs.readFile(initModule) }
	else
		node = I.new("Folder")
	end
	node.Name = name
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			self:mount(path, entry, node)
		elseif not entry:match("^init%.") and entry:match("%.luau$") then
			local module = I.new("ModuleScript")
			module.Name = entry:gsub("%.luau$", "")
			module.Parent = node
			self.sources[module] = { path = path, text = fs.readFile(path) }
		end
	end
	node.Parent = parent
	return node
end

function Harness:_environment(scriptInstance, context)
	local h = self
	local I = roblox.Instance
	local env = {
		script = scriptInstance,
		game = self.game,
		workspace = self.workspace,
		task = self.task,
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Font = roblox.Font,
	}
	env.Instance = {
		new = function(class, parent)
			local inst = I.new(class)
			if BASE_PART_CLASSES[class] then
				inst.Position = roblox.Vector3.new(0, 0, 0)
			end
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	}
	env.TweenInfo = {
		new = function(time, style, direction)
			if style ~= nil then
				assert(typeof(style) == "EnumItem", "TweenInfo style must be an Enum.EasingStyle")
			end
			if direction ~= nil then
				assert(typeof(direction) == "EnumItem", "TweenInfo direction must be an Enum.EasingDirection")
			end
			return { __tweenInfo = true, Time = time or 1 }
		end,
	}
	env.Random = {
		new = function(seed)
			local state = (seed or 12345) % 2147483648
			local r = {}
			function r:NextNumber(a, b)
				state = (state * 1103515245 + 12345) % 2147483648
				local x = state / 2147483648
				if a then
					return a + (b - a) * x
				end
				return x
			end
			function r:NextInteger(a, b)
				return math.floor(r:NextNumber(a, b + 1))
			end
			return r
		end,
	}
	env.os = {
		clock = function()
			return h.clock
		end,
		time = function()
			return math.floor(h.epoch + h.clock)
		end,
		date = os.date,
	}
	env.tick = function()
		return h.epoch + h.clock
	end
	env.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(h.warnings, table.concat(parts, " "))
	end
	env.print = function() end
	env.require = function(target)
		return h:require(target, context)
	end
	return env
end

function Harness:_load(scriptInstance, context)
	local source = self.sources[scriptInstance]
	assert(source, "no source for " .. tostring(scriptInstance))
	local fn = luau.load(source.text, {
		debugName = source.path,
		environment = self:_environment(scriptInstance, context),
	})
	return fn
end

function Harness:require(moduleInstance, context)
	context = context or self.context
	local cache = self.moduleCache[context]
	if cache[moduleInstance] ~= nil then
		return cache[moduleInstance]
	end
	local previous = self.context
	self.context = context
	local result = self:_load(moduleInstance, context)()
	self.context = previous
	assert(result ~= nil, "module returned nil: " .. self.sources[moduleInstance].path)
	cache[moduleInstance] = result
	return result
end

-- Run a Script / LocalScript as its own thread.
function Harness:run(scriptInstance, context)
	local fn = self:_load(scriptInstance, context)
	local previous = self.context
	self.context = context
	self.task.spawn(fn)
	self.context = previous
end

-- Players -------------------------------------------------------------------
function Harness:addPlayer(userId, name)
	local I = roblox.Instance
	local player = I.new("Player")
	player.Name = name
	player.UserId = userId
	player.DisplayName = name
	I.new("Backpack").Parent = player
	I.new("PlayerGui").Parent = player
	player.Parent = self.Players
	self.context = "server"
	signalOf(self.Players, "PlayerAdded"):Fire(player)
	return player
end

-- A minimal R15-shaped character standing at `position`.
function Harness:spawnCharacter(player, position)
	local I = roblox.Instance
	local char = I.new("Model")
	char.Name = player.Name
	local function part(name, size, offset)
		local p = I.new("Part")
		p.Name = name
		p.Size = size
		setCFrame(p, roblox.CFrame.new(position + offset))
		p.Parent = char
		return p
	end
	local root = part("HumanoidRootPart", roblox.Vector3.new(2, 2, 1), roblox.Vector3.new(0, 0, 0))
	part("Head", roblox.Vector3.new(1.2, 1.2, 1.2), roblox.Vector3.new(0, 1.6, 0))
	local upperTorso = part("UpperTorso", roblox.Vector3.new(2, 1.6, 1), roblox.Vector3.new(0, 0.4, 0))
	local lowerTorso = part("LowerTorso", roblox.Vector3.new(2, 0.4, 1), roblox.Vector3.new(0, -0.6, 0))
	local function motorIn(parent, name)
		local joint = I.new("Motor6D")
		joint.Name = name
		joint.Parent = parent
	end
	motorIn(lowerTorso, "Root")
	motorIn(upperTorso, "Waist")
	for _, side in { "Right", "Left" } do
		local x = side == "Right" and 0.5 or -0.5
		motorIn(part(side .. "UpperLeg", roblox.Vector3.new(1, 1, 1), roblox.Vector3.new(x, -1.3, 0)), side .. "Hip")
		motorIn(part(side .. "LowerLeg", roblox.Vector3.new(1, 1, 1), roblox.Vector3.new(x, -2.2, 0)), side .. "Knee")
	end
	for _, side in { "Right", "Left" } do
		local x = side == "Right" and 1.5 or -1.5
		local pieces = {
			{ "UpperArm", "Shoulder", roblox.Vector3.new(x, 0.4, 0) },
			{ "LowerArm", "Elbow", roblox.Vector3.new(x, -0.6, 0) },
			{ "Hand", "Wrist", roblox.Vector3.new(x, -1.3, 0) },
		}
		for _, piece in pieces do
			local limb = part(side .. piece[1], roblox.Vector3.new(1, 1, 1), piece[3])
			if side == "Right" then
				-- Classic joint.
				local joint = I.new("Motor6D")
				joint.Name = side .. piece[2]
				joint.Parent = limb
			else
				-- Newer "avatar joint upgrade" joint: an AnimationConstraint
				-- between two attachments.
				local a0 = I.new("Attachment")
				a0.Name = side .. piece[2] .. "RigAttachment"
				a0.Parent = char:FindFirstChild("UpperTorso")
				local a1 = I.new("Attachment")
				a1.Name = side .. piece[2] .. "RigAttachment"
				a1.Parent = limb
				local joint = I.new("AnimationConstraint")
				joint.Name = side .. piece[2]
				joint.Attachment0 = a0
				joint.Attachment1 = a1
				joint.Parent = limb
			end
		end
	end
	local humanoid = I.new("Humanoid")
	humanoid.CameraOffset = roblox.Vector3.new(0, 0, 0)
	humanoid.RigType = roblox.Enum.HumanoidRigType.R15
	humanoid.WalkSpeed = 16
	humanoid.JumpPower = 50
	humanoid.JumpHeight = 7.2
	humanoid.Parent = char
	char.PrimaryPart = root
	char.Parent = self.workspace
	player.Character = char

	-- StarterPack tools are copied into the Backpack on spawn.
	local backpack = player:FindFirstChild("Backpack")
	backpack:ClearAllChildren()
	for _, tool in self.game:GetService("StarterPack"):GetChildren() do
		tool:Clone().Parent = backpack
	end
	signalOf(player, "CharacterAdded"):Fire(char)
	return char
end

function Harness:removePlayer(player)
	signalOf(self.Players, "PlayerRemoving"):Fire(player)
	self:_runDue()
	if player.Character then
		player.Character:Destroy()
	end
	-- Unparent rather than Destroy: the simulated client's GUI lives under
	-- the player, and its background loops are still running in this VM.
	player.Parent = nil
end

function Harness:moveTo(player, position)
	local char = player.Character
	char:PivotTo(roblox.CFrame.new(position))
end

function Harness:positionOf(player)
	return player.Character.PrimaryPart.CFrame.Position
end

function Harness:shutdown()
	for _, fn in self.closers do
		self.task.spawn(fn)
	end
	self:advance(1)
end

-- Fire an event on an Instance by name (e.g. a button's Activated).
function Harness:fire(inst, eventName, ...)
	signalOf(inst, eventName):Fire(...)
	self:_runDue()
end

-- Stop the simulated client's per-frame and input handlers (it "left").
function Harness:stopClient()
	for _, name in { "RenderStepped" } do
		signalOf(self.RunService, name).handlers = {}
	end
	local uis = self.game:GetService("UserInputService")
	signalOf(uis, "InputBegan").handlers = {}
	signalOf(uis, "InputEnded").handlers = {}
	self.localPlayer = nil
end

function Harness:takeErrors()
	local errs = self.errors
	self.errors = {}
	return errs
end

Harness.roblox = roblox
Harness.Signal = Signal

return Harness
