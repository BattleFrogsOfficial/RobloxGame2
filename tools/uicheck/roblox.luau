--!nocheck
-- A small Roblox environment emulator for Lune, good enough to construct and lay out the client UI headlessly.
-- It is NOT a general Roblox emulator: it implements the data types, Instance tree, signals, services and
-- the layout rules (UDim2 / AnchorPoint / UIPadding / UIListLayout / UIGridLayout / UIScale /
-- UISizeConstraint / AutomaticSize) that the UI code uses. See run.luau for the checks built on top.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local LuneRoblox = require("@lune/roblox") -- real Vector3 / CFrame for the 3D pieces (ViewportFrame dog models)

local R = {}

-- ----------------------------------------------------------------------------------------- data types
local function newType(name, mt)
	mt.__type = name
	mt.__index = mt.__index or mt
	return mt
end

local Vector2 = {}
Vector2.__index = Vector2
newType("Vector2", Vector2)
function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end
Vector2.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2.__div = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X / b, a.Y / b)
	end
	return Vector2.new(a.X / b.X, a.Y / b.Y)
end
Vector2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2.__tostring = function(v)
	return string.format("%g, %g", v.X, v.Y)
end
Vector2.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y)
	end
	return Vector2[k]
end

local Vector3 = {}
newType("Vector3", Vector3)
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

local UDim = {}
newType("UDim", UDim)
function UDim.new(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDim)
end
UDim.__add = function(a, b)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDim.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end

local UDim2 = {}
newType("UDim2", UDim2)
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then -- UDim2.new(UDim, UDim)
		return setmetatable({ X = xs, Y = xo }, UDim2)
	end
	return setmetatable({ X = UDim.new(xs or 0, xo or 0), Y = UDim.new(ys or 0, yo or 0) }, UDim2)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
UDim2.__add = function(a, b)
	return UDim2.new(a.X + b.X, a.Y + b.Y)
end
UDim2.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UDim2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2.__tostring = function(u)
	return string.format("{%g, %g}, {%g, %g}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
UDim2.__index = function(t, k)
	if k == "Width" then
		return t.X
	elseif k == "Height" then
		return t.Y
	end
	return UDim2[k]
end

local Color3 = {}
newType("Color3", Color3)
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return Color3.new(v, t, p)
	elseif m == 1 then
		return Color3.new(q, v, p)
	elseif m == 2 then
		return Color3.new(p, v, t)
	elseif m == 3 then
		return Color3.new(p, q, v)
	elseif m == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3:Lerp(other, a)
	return Color3.new(self.R + (other.R - self.R) * a, self.G + (other.G - self.G) * a, self.B + (other.B - self.B) * a)
end
function Color3:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end
function Color3:ToHex()
	return string.format("%02X%02X%02X", math.floor(self.R * 255 + 0.5), math.floor(self.G * 255 + 0.5), math.floor(self.B * 255 + 0.5))
end
Color3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end

local ColorSequenceKeypoint = {}
newType("ColorSequenceKeypoint", ColorSequenceKeypoint)
function ColorSequenceKeypoint.new(t, c)
	return setmetatable({ Time = t, Value = c }, ColorSequenceKeypoint)
end
local ColorSequence = {}
newType("ColorSequence", ColorSequence)
function ColorSequence.new(a, b)
	if type(a) == "table" and a[1] then
		return setmetatable({ Keypoints = a }, ColorSequence)
	end
	return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, ColorSequence)
end
local NumberSequenceKeypoint = {}
newType("NumberSequenceKeypoint", NumberSequenceKeypoint)
function NumberSequenceKeypoint.new(t, v, e)
	return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NumberSequenceKeypoint)
end
local NumberSequence = {}
newType("NumberSequence", NumberSequence)
function NumberSequence.new(a, b)
	if type(a) == "table" and a[1] then
		return setmetatable({ Keypoints = a }, NumberSequence)
	end
	return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, NumberSequence)
end
local NumberRange = {}
newType("NumberRange", NumberRange)
function NumberRange.new(a, b)
	return setmetatable({ Min = a, Max = b or a }, NumberRange)
end

local TweenInfo = {}
newType("TweenInfo", TweenInfo)
function TweenInfo.new(t, style, dir, rep, rev, delay)
	return setmetatable({ Time = t or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }, TweenInfo)
end

local CFrame = {}
newType("CFrame", CFrame)
function CFrame.new(x, y, z)
	return setmetatable({ Position = Vector3.new(x, y, z) }, CFrame)
end

-- The UI only ever needed Vector3 / CFrame as data; the reveal card's ViewportFrame builds real dog models
-- (DogFactory: CFrame maths, joints, ScaleTo, bounding boxes), so use Lune's real implementations.
Vector3 = LuneRoblox.Vector3
-- Lune 0.8.9's CFrame.lookAt faces AWAY from the target; Roblox faces toward it. Patch it (same signature).
CFrame = setmetatable({
	lookAt = function(at, target, up)
		local look = (target - at).Unit
		local right = look:Cross(up or Vector3.new(0, 1, 0))
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(0, 0, 1))
		end
		right = right.Unit
		return LuneRoblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
	end,
}, { __index = LuneRoblox.CFrame })

local Random = {}
newType("Random", Random)
function Random.new(seed)
	local state = seed or os.clock() * 1000
	local self = setmetatable({}, Random)
	function self:NextNumber(a, b)
		state = (state * 9301 + 49297) % 233280
		local r = state / 233280
		if a then
			return a + (b - a) * r
		end
		return r
	end
	function self:NextInteger(a, b)
		return math.floor(self:NextNumber(a, b + 1))
	end
	return self
end

-- Enum: lazy, cached items. Enum.Font.FredokaOne -> { Name = "FredokaOne", Value = n, EnumType = ... }
local enumItems = {}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = enumItems[enumName]
		if not items then
			items = setmetatable({}, {
				__index = function(t, itemName)
					local item = setmetatable({ Name = itemName, Value = 0, EnumType = enumName }, { __type = "EnumItem", __tostring = function(i)
						return "Enum." .. enumName .. "." .. i.Name
					end })
					rawset(t, itemName, item)
					return item
				end,
			})
			enumItems[enumName] = items
		end
		return items
	end,
})

-- ----------------------------------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
newType("RBXScriptSignal", Signal)
function Signal.new()
	return setmetatable({ _c = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true }
	conn.fn = fn
	function conn.Disconnect(c)
		c.Connected = false
		local i = table.find(self._c, c)
		if i then
			table.remove(self._c, i)
		end
	end
	setmetatable(conn, { __type = "RBXScriptConnection", __index = conn })
	table.insert(self._c, conn)
	return conn
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, c in table.clone(self._c) do
		if c.Connected then
			task.spawn(c.fn, ...)
		end
	end
end
R.Signal = Signal

-- ----------------------------------------------------------------------------------------- instances
local HIERARCHY = {
	Instance = {},
	GuiBase2d = { "Instance" },
	GuiObject = { "GuiBase2d" },
	Frame = { "GuiObject" },
	ScrollingFrame = { "GuiObject" },
	TextLabel = { "GuiObject" },
	TextButton = { "GuiObject" },
	TextBox = { "GuiObject" },
	ImageLabel = { "GuiObject" },
	ImageButton = { "GuiObject" },
	ViewportFrame = { "GuiObject" },
	WorldModel = { "Model" },
	CanvasGroup = { "GuiObject" },
	LayerCollector = { "GuiBase2d" },
	ScreenGui = { "LayerCollector" },
	UIComponent = { "Instance" },
	UILayout = { "UIComponent" },
	UIGridStyleLayout = { "UILayout" },
	UIListLayout = { "UIGridStyleLayout" },
	UIGridLayout = { "UIGridStyleLayout" },
	UIConstraint = { "UIComponent" },
	UISizeConstraint = { "UIConstraint" },
	UIAspectRatioConstraint = { "UIConstraint" },
	UITextSizeConstraint = { "UIConstraint" },
	UIPadding = { "UIComponent" },
	UIScale = { "UIComponent" },
	UICorner = { "UIComponent" },
	UIStroke = { "UIComponent" },
	UIGradient = { "UIComponent" },
	UIShadow = { "UIComponent" },
	Folder = { "Instance" },
	LuaSourceContainer = { "Instance" },
	BaseScript = { "LuaSourceContainer" },
	Script = { "BaseScript" },
	LocalScript = { "BaseScript" },
	ModuleScript = { "LuaSourceContainer" },
	RemoteEvent = { "Instance" },
	RemoteFunction = { "Instance" },
	BindableEvent = { "Instance" },
	Player = { "Instance" },
	PlayerGui = { "Instance" },
	Camera = { "Instance" },
	Sound = { "Instance" },
	Configuration = { "Instance" },
	Attachment = { "Instance" },
	BasePart = { "Instance" },
	Part = { "BasePart" },
	MeshPart = { "BasePart" },
	WedgePart = { "BasePart" },
	CornerWedgePart = { "BasePart" },
	TrussPart = { "BasePart" },
	Model = { "Instance" },
	-- 3D pieces the cutscene harness (tools/tests/cutscene_director.luau) creates
	JointInstance = { "Instance" },
	Motor6D = { "JointInstance" },
	Weld = { "JointInstance" },
	WeldConstraint = { "Instance" },
	Humanoid = { "Instance" },
	Animator = { "Instance" },
	Trail = { "Instance" },
	ParticleEmitter = { "Instance" },
	PointLight = { "Instance" },
	Light = { "Instance" },
	SpotLight = { "Instance" },
	Highlight = { "Instance" },
	Decal = { "Instance" },
	Texture = { "Decal" },
	SpecialMesh = { "Instance" },
	Tween = { "Instance" },
}
local function isA(className, target)
	if className == target then
		return true
	end
	local bases = HIERARCHY[className]
	if not bases then
		return target == "Instance"
	end
	for _, b in bases do
		if isA(b, target) then
			return true
		end
	end
	return false
end

local GUI_DEFAULTS = {
	Size = function()
		return UDim2.new(0, 100, 0, 100)
	end,
	Position = function()
		return UDim2.new()
	end,
	AnchorPoint = function()
		return Vector2.new()
	end,
	Visible = true,
	ZIndex = 1,
	LayoutOrder = 0,
	BackgroundTransparency = 0,
	BackgroundColor3 = function()
		return Color3.fromRGB(163, 162, 165)
	end,
	BorderSizePixel = 1,
	ClipsDescendants = false,
	Active = false,
	AutomaticSize = Enum.AutomaticSize.None,
	Rotation = 0,
	Selectable = false,
}
local TEXT_DEFAULTS = {
	Text = "Label",
	TextSize = 14,
	TextColor3 = function()
		return Color3.fromRGB(27, 42, 53)
	end,
	TextTransparency = 0,
	TextWrapped = false,
	TextScaled = false,
	TextTruncate = Enum.TextTruncate.None,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Font = Enum.Font.Legacy,
	RichText = false,
	AutoButtonColor = true,
	TextStrokeTransparency = 1,
}
local CLASS_DEFAULTS = {
	UIListLayout = { Padding = function()
		return UDim.new()
	end, FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top, SortOrder = Enum.SortOrder.LayoutOrder, Wraps = false },
	UIGridLayout = { CellSize = function()
		return UDim2.new(0, 100, 0, 100)
	end, CellPadding = function()
		return UDim2.new(0, 5, 0, 5)
	end, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top, SortOrder = Enum.SortOrder.LayoutOrder, FillDirectionMaxCells = 0 },
	UIPadding = { PaddingTop = function()
		return UDim.new()
	end, PaddingBottom = function()
		return UDim.new()
	end, PaddingLeft = function()
		return UDim.new()
	end, PaddingRight = function()
		return UDim.new()
	end },
	UIScale = { Scale = 1 },
	UISizeConstraint = { MaxSize = function()
		return Vector2.new(math.huge, math.huge)
	end, MinSize = function()
		return Vector2.new()
	end },
	UIAspectRatioConstraint = { AspectRatio = 1 },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	UICorner = { CornerRadius = function()
		return UDim.new(0, 8)
	end },
	UIStroke = { Thickness = 1, Color = function()
		return Color3.new()
	end, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round, Enabled = true },
	UIGradient = { Rotation = 0, Enabled = true },
	UIShadow = {},
	ScrollingFrame = { CanvasPosition = function()
		return Vector2.new()
	end, CanvasSize = function()
		return UDim2.new(0, 0, 2, 0)
	end, AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollBarThickness = 12, ScrollingDirection = Enum.ScrollingDirection.XY, ScrollingEnabled = true },
	ScreenGui = { Enabled = true, DisplayOrder = 0, IgnoreGuiInset = false, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets },
	ImageLabel = { Image = "", ImageColor3 = function()
		return Color3.new(1, 1, 1)
	end, ImageTransparency = 0, ScaleType = Enum.ScaleType.Stretch, ResampleMode = Enum.ResamplerMode.Default },
	ImageButton = { Image = "", ImageTransparency = 0 },
	-- ViewportFrame lighting (Roblox defaults) and the 3D classes the reveal card's dog viewport builds
	ViewportFrame = { Ambient = function()
		return Color3.fromRGB(200, 200, 200)
	end, LightColor = function()
		return Color3.fromRGB(140, 140, 140)
	end, LightDirection = function()
		return Vector3.new(-1, -1, -1)
	end, ImageColor3 = function()
		return Color3.new(1, 1, 1)
	end, ImageTransparency = 0 },
	Camera = { CFrame = function()
		return CFrame.new()
	end, FieldOfView = 70 },
	Model = { WorldPivot = function()
		return CFrame.new()
	end },
	WorldModel = { WorldPivot = function()
		return CFrame.new()
	end },
	Attachment = { CFrame = function()
		return CFrame.new()
	end },
}
local PART_DEFAULTS = { CFrame = function()
	return CFrame.new()
end, Size = function()
	return Vector3.new(4, 1, 2)
end, Color = function()
	return Color3.fromRGB(163, 162, 165)
end, Transparency = 0, Reflectance = 0, Anchored = false, CanCollide = true, CastShadow = true, Massless = false, Shape = Enum.PartType.Block, Material = Enum.Material.Plastic }
local JOINT_DEFAULTS = { C0 = function()
	return CFrame.new()
end, C1 = function()
	return CFrame.new()
end, Transform = function()
	return CFrame.new()
end, Enabled = true }
-- Reference properties that may legitimately read as nil (an unset Part0 is not "not a valid member").
local NILABLE = { Part0 = true, Part1 = true, PrimaryPart = true, CurrentCamera = true, Attachment0 = true, Attachment1 = true, Adornee = true, CameraSubject = true }

local Instance = {}
local instanceMeta = {}
instanceMeta.__type = "Instance"
R.AllInstances = setmetatable({}, { __mode = "k" })

local function raw(self)
	return rawget(self, "__raw")
end

local function resolveDefault(d)
	if type(d) == "function" then
		return d()
	end
	return d
end

local methods = {}
function methods.GetChildren(self)
	return table.clone(raw(self).children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(inst)
		for _, c in raw(inst).children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in raw(self).children do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in raw(self).children do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	local c = self:FindFirstChild(name)
	if c then
		return c
	end
	-- Give deferred construction a chance, then fail loudly: a hang here would be useless in CI.
	for _ = 1, 3 do
		task.wait()
		c = self:FindFirstChild(name)
		if c then
			return c
		end
	end
	if timeout then
		return nil
	end
	error(string.format("WaitForChild: %s has no child named %q (mock never resolves missing children)", self:GetFullName(), name), 2)
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in raw(self).children do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls, recursive)
	for _, c in raw(self).children do
		if c:IsA(cls) then
			return c
		end
	end
	if recursive then
		for _, c in raw(self).children do
			local f = c:FindFirstChildWhichIsA(cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, cls)
	local p = self.Parent
	while p do
		if p:IsA(cls) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, cls)
	local p = self.Parent
	while p do
		if p.ClassName == cls then
			return p
		end
		p = p.Parent
	end
	return nil
end
function methods.IsA(self, cls)
	return isA(self.ClassName, cls)
end
function methods.IsDescendantOf(self, other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end
function methods.GetFullName(self)
	local parts = { self.Name }
	local p = self.Parent
	while p do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return table.concat(parts, ".")
end
function methods.Destroy(self)
	local r = raw(self)
	if r.destroyed then
		return
	end
	if r.signals.Destroying then
		r.signals.Destroying:Fire()
	end
	for _, c in table.clone(r.children) do
		c:Destroy()
	end
	self.Parent = nil
	r.destroyed = true
end
function methods.ClearAllChildren(self)
	for _, c in table.clone(raw(self).children) do
		c:Destroy()
	end
end
function methods.GetPropertyChangedSignal(self, prop)
	local r = raw(self)
	r.propSignals[prop] = r.propSignals[prop] or Signal.new()
	return r.propSignals[prop]
end
function methods.GetAttribute(self, name)
	return raw(self).attributes[name]
end
function methods.SetAttribute(self, name, value)
	raw(self).attributes[name] = value
	local r = raw(self)
	if r.attrSignals[name] then
		r.attrSignals[name]:Fire()
	end
end
function methods.GetAttributeChangedSignal(self, name)
	local r = raw(self)
	r.attrSignals[name] = r.attrSignals[name] or Signal.new()
	return r.attrSignals[name]
end
function methods.GetAttributes(self)
	return table.clone(raw(self).attributes)
end
function methods.Clone(self)
	local copy = Instance.new(self.ClassName)
	for k, v in raw(self).props do
		if k ~= "Parent" then
			raw(copy).props[k] = v
		end
	end
	for _, c in raw(self).children do
		c:Clone().Parent = copy
	end
	return copy
end
function methods.AddTag(self, tag)
	raw(self).tags[tag] = true
end
function methods.HasTag(self, tag)
	return raw(self).tags[tag] == true
end
function methods.GetTags(self)
	local t = {}
	for k in raw(self).tags do
		table.insert(t, k)
	end
	return t
end
-- 3D: Model / BasePart pivots, bounding boxes and ScaleTo (what DogFactory and the reveal card's viewport use).
-- No physics: joints are not solved, parts keep the CFrames their builder gave them.
local function baseParts(self)
	local out = {}
	if self:IsA("BasePart") then
		table.insert(out, self)
	end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
function methods.GetPivot(self)
	if self:IsA("BasePart") then
		return self.CFrame
	end
	local pp = raw(self).props.PrimaryPart
	if pp then
		return pp.CFrame
	end
	return raw(self).props.WorldPivot or CFrame.new()
end
function methods.PivotTo(self, cf)
	local delta = cf * methods.GetPivot(self):Inverse()
	for _, p in baseParts(self) do
		p.CFrame = delta * p.CFrame
	end
	if not self:IsA("BasePart") then
		raw(self).props.WorldPivot = delta * (raw(self).props.WorldPivot or CFrame.new())
	end
end
function methods.GetBoundingBox(self)
	local lo, hi = nil, nil
	for _, p in baseParts(self) do
		local h = p.Size * 0.5
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					lo = if lo then lo:Min(w) else w
					hi = if hi then hi:Max(w) else w
				end
			end
		end
	end
	if not lo then
		return methods.GetPivot(self), Vector3.zero
	end
	return CFrame.new((lo + hi) * 0.5), hi - lo
end
function methods.GetExtentsSize(self)
	local _, size = methods.GetBoundingBox(self)
	return size
end
function methods.GetScale(self)
	return raw(self).scale or 1
end
function methods.ScaleTo(self, s)
	local k = s / (raw(self).scale or 1)
	local pivot = methods.GetPivot(self)
	for _, p in baseParts(self) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		p.Size = p.Size * k
		p.CFrame = pivot * (CFrame.new(rel.Position * k) * rel.Rotation)
	end
	for _, d in self:GetDescendants() do
		if d:IsA("JointInstance") then
			d.C0 = CFrame.new(d.C0.Position * k) * d.C0.Rotation
			d.C1 = CFrame.new(d.C1.Position * k) * d.C1.Rotation
		elseif d:IsA("Attachment") then
			d.CFrame = CFrame.new(d.CFrame.Position * k) * d.CFrame.Rotation
		end
	end
	raw(self).scale = s
end

-- RemoteEvent / RemoteFunction client side
function methods.FireServer(self, ...)
	raw(self).log = raw(self).log or {}
	table.insert(raw(self).log, { ... })
	if raw(self).onServer then
		raw(self).onServer(...)
	end
end
function methods.InvokeServer(self, ...)
	local handler = raw(self).handler
	if handler then
		return handler(...)
	end
	return true
end
function methods.Fire(self, ...)
	raw(self).signals.Event:Fire(...)
end

local SIGNAL_NAMES = { Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton2Click = true, MouseEnter = true, MouseLeave = true, InputBegan = true, InputEnded = true, InputChanged = true, Changed = true, Destroying = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, AncestryChanged = true, OnClientEvent = true, Event = true, Heartbeat = true, RenderStepped = true, Stepped = true, Completed = true, PlayerAdded = true, PlayerRemoving = true, TouchTap = true, TouchTapInWorld = true, SelectionGained = true, SelectionLost = true, FocusLost = true, Focused = true, CharacterAdded = true, CharacterRemoving = true, Ended = true, Died = true, PreSimulation = true }

instanceMeta.__index = function(self, key)
	local r = rawget(self, "__raw")
	if key == "ClassName" then
		return r.className
	end
	if key == "Parent" then
		return r.parent
	end
	local m = methods[key]
	if m then
		return m
	end
	local v = r.props[key]
	if v ~= nil then
		return v
	end
	if SIGNAL_NAMES[key] then
		r.signals[key] = r.signals[key] or Signal.new()
		return r.signals[key]
	end
	-- Children by name (Roblox allows instance.ChildName)
	for _, c in r.children do
		if c.Name == key then
			return c
		end
	end
	-- 3D parts: Position is derived from CFrame (the cutscene harness sets CFrame)
	if key == "Position" and r.props.CFrame ~= nil then
		return r.props.CFrame.Position
	end
	if key == "AbsoluteSize" or key == "AbsolutePosition" then
		return r.layout and r.layout[key] or Vector2.new()
	end
	if key == "AbsoluteCanvasSize" then
		return Vector2.new()
	end
	if key == "TextBounds" then
		return R.TextBounds(self)
	end
	if key == "TextFits" then
		return true
	end
	if key == "ContentText" then
		return r.props.Text or ""
	end
	if key == "AbsoluteContentSize" then
		return Vector2.new()
	end
	if NILABLE[key] then
		return nil
	end
	error(string.format("%s is not a valid member of %s %q", tostring(key), r.className, self:GetFullName()), 2)
end

instanceMeta.__newindex = function(self, key, value)
	local r = rawget(self, "__raw")
	if key == "Parent" then
		if r.parent == value then
			return
		end
		if r.parent then
			local sib = raw(r.parent).children
			local i = table.find(sib, self)
			if i then
				table.remove(sib, i)
			end
			if raw(r.parent).signals.ChildRemoved then
				raw(r.parent).signals.ChildRemoved:Fire(self)
			end
		end
		r.parent = value
		if value then
			table.insert(raw(value).children, self)
			if raw(value).signals.ChildAdded then
				raw(value).signals.ChildAdded:Fire(self)
			end
			local p = value
			while p do
				if raw(p).signals.DescendantAdded then
					raw(p).signals.DescendantAdded:Fire(self)
				end
				p = p.Parent
			end
		end
		if r.signals.AncestryChanged then
			r.signals.AncestryChanged:Fire(self, value)
		end
		return
	end
	if SIGNAL_NAMES[key] then
		error("Cannot assign to event " .. key, 2)
	end
	local old = r.props[key]
	r.props[key] = value
	if old ~= value then
		local s = r.propSignals[key]
		if s then
			s:Fire()
		end
		if r.signals.Changed then
			r.signals.Changed:Fire(key)
		end
	end
end
instanceMeta.__tostring = function(self)
	return self.Name
end
instanceMeta.__eq = function(a, b)
	return rawequal(a, b)
end

function Instance.new(className, parent)
	local props = { Name = className }
	if isA(className, "GuiObject") then
		for k, v in GUI_DEFAULTS do
			props[k] = resolveDefault(v)
		end
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		for k, v in TEXT_DEFAULTS do
			props[k] = resolveDefault(v)
		end
		if className == "TextLabel" then
			props.Text = "Label"
		elseif className == "TextButton" then
			props.Text = "Button"
			props.Active = true
		else
			props.Text = ""
		end
	end
	if isA(className, "BasePart") then
		for k, v in PART_DEFAULTS do
			props[k] = resolveDefault(v)
		end
	elseif isA(className, "JointInstance") then
		for k, v in JOINT_DEFAULTS do
			props[k] = resolveDefault(v)
		end
	end
	local cd = CLASS_DEFAULTS[className]
	if cd then
		for k, v in cd do
			props[k] = resolveDefault(v)
		end
	end
	local self = setmetatable({
		__raw = {
			className = className,
			props = props,
			children = {},
			parent = nil,
			signals = {},
			propSignals = {},
			attributes = {},
			attrSignals = {},
			tags = {},
		},
	}, instanceMeta)
	R.AllInstances[self] = true
	if parent then
		self.Parent = parent
	end
	return self
end
R.Instance = Instance

-- ----------------------------------------------------------------------------------------- text metrics
local FONT_K = { FredokaOne = 0.56, LuckiestGuy = 0.6, GothamMedium = 0.62, GothamBold = 0.66, GothamBlack = 0.7, Gotham = 0.6, Arcade = 1.0, PressStart2P = 1.0, SourceSans = 0.5, SourceSansBold = 0.54, Legacy = 0.5, BuilderSans = 0.55 }
function R.TextWidth(text, size, font)
	local name = font and font.Name or "Legacy"
	local k = FONT_K[name] or 0.58
	local w = 0
	for _, cp in utf8.codes(text) do
		local ch = utf8.char(cp)
		if ch == " " then
			w += size * k * 0.5
		elseif string.match(ch, "[iljtfI.,:;'|!]") then
			w += size * k * 0.55
		elseif string.match(ch, "[mwMW]") then
			w += size * k * 1.35
		elseif string.match(ch, "%u") or string.match(ch, "%d") then
			w += size * k * 1.08
		else
			w += size * k
		end
	end
	return w
end
function R.TextBounds(label)
	local text = label.Text or ""
	local size = label.TextSize or 14
	local w = R.TextWidth(text, size, label.Font)
	local lines = 1
	if label.TextWrapped and label.__raw.layout then
		local avail = label.__raw.layout.AbsoluteSize.X
		if avail > 0 then
			lines = math.max(1, math.ceil(w / avail))
			w = math.min(w, avail)
		end
	end
	return Vector2.new(w, size * 1.2 * lines)
end

-- ----------------------------------------------------------------------------------------- services
local game = Instance.new("DataModel")
game.Name = "game"
local services = {}
local function service(name, className)
	local s = Instance.new(className or name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
local ReplicatedStorage = service("ReplicatedStorage")
local Players = service("Players")
local UserInputService = service("UserInputService")
local GuiService = service("GuiService")
local RunService = service("RunService")
local TweenService = service("TweenService")
local StarterGui = service("StarterGui")
local SoundService = service("SoundService")
local ContentProvider = service("ContentProvider")
local MarketplaceService = service("MarketplaceService")
local PolicyService = service("PolicyService")
local Workspace = service("Workspace")
local TextService = service("TextService")
local HttpService = service("HttpService")
local Lighting = service("Lighting")
local CollectionService = service("CollectionService")

local localPlayer = Instance.new("Player")
localPlayer.Name = "Tester"
localPlayer.DisplayName = "Tester"
localPlayer.UserId = 1
localPlayer.Parent = Players
local playerGui = Instance.new("PlayerGui", localPlayer)
playerGui.Name = "PlayerGui"
Players.LocalPlayer = localPlayer
R.LocalPlayer = localPlayer
R.PlayerGui = playerGui
methods.GetPlayerByUserId = function(_, id)
	if id == 1 then
		return localPlayer
	end
	return nil
end
methods.GetPlayers = function()
	return { localPlayer }
end

UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
UserInputService.MouseEnabled = true
UserInputService.GamepadEnabled = false
methods.GetLastInputType = function()
	return Enum.UserInputType.MouseMovement
end
methods.IsKeyDown = function()
	return false
end

R.GuiInset = Vector2.new(0, 58)
methods.GetGuiInset = function()
	return R.GuiInset, Vector2.new()
end
GuiService.SelectedObject = nil
GuiService.MenuIsOpen = false

methods.IsServer = function()
	return false
end
methods.IsClient = function()
	return true
end
methods.IsStudio = function()
	return true
end
methods.IsRunning = function()
	return true
end
methods.BindToRenderStep = function() end
methods.UnbindFromRenderStep = function() end

-- Tweens apply instantly (or on Play) so layout reflects the final state.
methods.Create = function(_, inst, info, props)
	local tween = { Completed = Signal.new(), PlaybackState = Enum.PlaybackState.Begin }
	function tween.Play()
		for k, v in props do
			inst[k] = v
		end
		task.defer(function()
			tween.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel() end
	function tween.Pause() end
	function tween.Destroy() end
	return setmetatable(tween, { __type = "Tween", __index = function(_, k)
		if k == "Play" then
			return function(self2) return tween.Play() end
		end
		return rawget(tween, k)
	end })
end
methods.GetTextSize = function(_, text, size, font, frame)
	local b = R.TextWidth(text, size, font)
	return Vector2.new(math.min(b, frame and frame.X or math.huge), size * 1.2)
end
methods.GetPolicyInfoForPlayerAsync = function()
	return { ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {}, IsSubjectToChinaPolicies = false }
end
methods.PreloadAsync = function() end
methods.GenerateGUID = function()
	return string.format("%08x-%04x", math.random(0, 0xffffffff), math.random(0, 0xffff))
end
methods.JSONEncode = function(_, t)
	return require("@lune/serde").encode("json", t)
end
methods.GetTagged = function()
	return {}
end
methods.SetCore = function() end
methods.SetCoreGuiEnabled = function() end
methods.GetService = function(_, name)
	local s = services[name]
	if not s then
		s = service(name)
	end
	return s
end
methods.FindService = methods.GetService

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.ViewportSize = Vector2.new(1280, 720)
camera.Parent = Workspace
Workspace.CurrentCamera = camera
R.Camera = camera

-- ----------------------------------------------------------------------------------------- module loading
R.Game = game
R.ReplicatedStorage = ReplicatedStorage
R.Enum = Enum
R.Types = { Vector2 = Vector2, Vector3 = Vector3, UDim = UDim, UDim2 = UDim2, Color3 = Color3, ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint, NumberRange = NumberRange, TweenInfo = TweenInfo, CFrame = CFrame, Random = Random }

local moduleCache = {}
local function luauTypeof(v)
	local mt = getmetatable(v)
	if type(v) == "table" and mt and mt.__type then
		return mt.__type
	end
	return typeof(v)
end
R.typeof = luauTypeof

local baseEnv
local function makeEnv(scriptInstance)
	local env = {}
	for k, v in baseEnv do
		env[k] = v
	end
	env.script = scriptInstance
	env.require = function(target)
		if luauTypeof(target) == "Instance" then
			return R.Require(target)
		end
		return require(target)
	end
	return env
end

function R.Require(moduleInstance)
	local cached = moduleCache[moduleInstance]
	if cached ~= nil then
		if cached == "loading" then
			error("Cyclic require of " .. moduleInstance:GetFullName())
		end
		return cached
	end
	local path = raw(moduleInstance).path
	if not path then
		error("Module has no source: " .. moduleInstance:GetFullName())
	end
	moduleCache[moduleInstance] = "loading"
	local source = fs.readFile(path)
	local fn = luau.load(source, { debugName = path, environment = makeEnv(moduleInstance), injectGlobals = true })
	local ok, result = pcall(fn)
	if not ok then
		moduleCache[moduleInstance] = nil
		error(string.format("Error while loading %s:\n%s", path, tostring(result)), 0)
	end
	moduleCache[moduleInstance] = result
	return result
end

-- Build Folders/ModuleScripts from a Rojo-style source tree.
function R.MountTree(dirPath, parentInstance, nameOverride)
	local name = nameOverride or string.match(dirPath, "([^/]+)$")
	local initPath = nil
	for _, candidate in { "init.luau", "init.lua" } do
		if fs.isFile(dirPath .. "/" .. candidate) then
			initPath = dirPath .. "/" .. candidate
		end
	end
	local container
	if initPath then
		container = Instance.new("ModuleScript")
		raw(container).path = initPath
	else
		container = Instance.new("Folder")
	end
	container.Name = name
	container.Parent = parentInstance
	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			R.MountTree(full, container)
		elseif entry ~= "init.luau" and entry ~= "init.lua" then
			local base, kind = string.match(entry, "^(.-)%.(%a+)%.luau$")
			if not base then
				base, kind = string.match(entry, "^(.-)%.(%a+)%.lua$")
			end
			local plain = string.match(entry, "^(.-)%.luau$") or string.match(entry, "^(.-)%.lua$")
			if base and (kind == "client" or kind == "server") then
				local s = Instance.new(if kind == "client" then "LocalScript" else "Script")
				s.Name = base
				raw(s).path = full
				s.Parent = container
			elseif plain then
				local m = Instance.new("ModuleScript")
				m.Name = plain
				raw(m).path = full
				m.Parent = container
			end
		end
	end
	return container
end

-- Mock remotes under ReplicatedStorage.Remotes
function R.MakeRemotes(events, functions)
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, n in events do
		local e = Instance.new("RemoteEvent")
		e.Name = n
		e.Parent = folder
	end
	for _, n in functions do
		local f = Instance.new("RemoteFunction")
		f.Name = n
		f.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end
function R.SetRemoteHandler(remote, fn)
	raw(remote).handler = fn
end
function R.RemoteLog(remote)
	return raw(remote).log or {}
end

-- ----------------------------------------------------------------------------------------- layout engine
-- Computes AbsolutePosition / AbsoluteSize for every GuiObject under a ScreenGui. Scale is applied as a
-- multiplier on offsets (UIScale). Returns a flat list of records for the checks and the renderer.
local function udimPx(u, parentLen, scale)
	return u.Scale * parentLen + u.Offset * scale
end

function R.Layout(screenGui, viewport, inset)
	local records = {}
	local topInset = inset or (screenGui.IgnoreGuiInset and 0 or R.GuiInset.Y)
	local screen = { x = 0, y = topInset, w = viewport.X, h = viewport.Y - topInset }
	raw(screenGui).layout = { AbsolutePosition = Vector2.new(0, topInset), AbsoluteSize = Vector2.new(screen.w, screen.h) }

	local function childrenOf(inst)
		return raw(inst).children
	end

	local function visibleGui(inst)
		return inst:IsA("GuiObject") and inst.Visible
	end

	local function sorted(list, sortOrder)
		local copy = table.clone(list)
		table.sort(copy, function(a, b)
			if sortOrder == Enum.SortOrder.Name then
				return a.Name < b.Name
			end
			if a.LayoutOrder ~= b.LayoutOrder then
				return a.LayoutOrder < b.LayoutOrder
			end
			return (raw(a).seq or 0) < (raw(b).seq or 0)
		end)
		return copy
	end

	-- Size of an element given its parent's content box (before layout placement).
	local measure
	local place

	local function contentBox(inst, rect, scale)
		local pad = inst:FindFirstChildOfClass("UIPadding")
		if not pad then
			return rect
		end
		local l = udimPx(pad.PaddingLeft, rect.w, scale)
		local r = udimPx(pad.PaddingRight, rect.w, scale)
		local t = udimPx(pad.PaddingTop, rect.h, scale)
		local b = udimPx(pad.PaddingBottom, rect.h, scale)
		return { x = rect.x + l, y = rect.y + t, w = math.max(0, rect.w - l - r), h = math.max(0, rect.h - t - b) }
	end

	local function textSize(inst, scale, availW)
		local w = R.TextWidth(inst.Text or "", (inst.TextSize or 14) * scale, inst.Font)
		local lineH = (inst.TextSize or 14) * scale * 1.2
		if inst.TextWrapped and availW and availW > 0 and w > availW then
			local lines = math.ceil(w / availW)
			return Vector2.new(availW, lineH * lines), lines
		end
		return Vector2.new(w, lineH), 1
	end

	-- Measure returns the element's size in px given the parent's content box, honouring AutomaticSize
	-- (text or children bounding box) and UISizeConstraint.
	measure = function(inst, parentBox, scale)
		local size = inst.Size
		local w = udimPx(size.X, parentBox.w, scale)
		local h = udimPx(size.Y, parentBox.h, scale)
		local auto = inst.AutomaticSize
		if auto ~= Enum.AutomaticSize.None then
			local cw, ch = 0, 0
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				local b = textSize(inst, scale, if auto == Enum.AutomaticSize.Y then w else nil)
				cw, ch = b.X, b.Y
			end
			-- children bounding box
			local box = contentBox(inst, { x = 0, y = 0, w = w, h = h }, scale)
			local list = inst:FindFirstChildOfClass("UIListLayout")
			local pad = inst:FindFirstChildOfClass("UIPadding")
			local padX, padY = 0, 0
			if pad then
				padX = udimPx(pad.PaddingLeft, w, scale) + udimPx(pad.PaddingRight, w, scale)
				padY = udimPx(pad.PaddingTop, h, scale) + udimPx(pad.PaddingBottom, h, scale)
			end
			local maxX, maxY = 0, 0
			local kids = {}
			for _, c in childrenOf(inst) do
				if visibleGui(c) then
					table.insert(kids, c)
				end
			end
			if list then
				local gap = udimPx(list.Padding, if list.FillDirection == Enum.FillDirection.Vertical then box.h else box.w, scale)
				local acc = 0
				for i, c in sorted(kids, list.SortOrder) do
					local cs = measure(c, box, scale)
					if list.FillDirection == Enum.FillDirection.Vertical then
						acc += cs.Y + (if i > 1 then gap else 0)
						maxX = math.max(maxX, cs.X)
					else
						acc += cs.X + (if i > 1 then gap else 0)
						maxY = math.max(maxY, cs.Y)
					end
				end
				if list.FillDirection == Enum.FillDirection.Vertical then
					maxY = acc
				else
					maxX = acc
				end
			else
				for _, c in kids do
					local cs = measure(c, box, scale)
					local px = udimPx(c.Position.X, box.w, scale) - c.AnchorPoint.X * cs.X
					local py = udimPx(c.Position.Y, box.h, scale) - c.AnchorPoint.Y * cs.Y
					maxX = math.max(maxX, px + cs.X)
					maxY = math.max(maxY, py + cs.Y)
				end
			end
			cw = math.max(cw, maxX + padX)
			ch = math.max(ch, maxY + padY)
			if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
				w = math.max(w, cw)
			end
			if auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY then
				h = math.max(h, ch)
			end
		end
		local sc = inst:FindFirstChildOfClass("UISizeConstraint")
		if sc then
			w = math.clamp(w, sc.MinSize.X * scale, sc.MaxSize.X * scale)
			h = math.clamp(h, sc.MinSize.Y * scale, sc.MaxSize.Y * scale)
		end
		local ar = inst:FindFirstChildOfClass("UIAspectRatioConstraint")
		if ar then
			local ratio = ar.AspectRatio
			if w / h > ratio then
				w = h * ratio
			else
				h = w / ratio
			end
		end
		return Vector2.new(w, h)
	end

	local seq = 0
	-- Place lays out inst at (x, y, w, h) in absolute px and recurses into its children.
	place = function(inst, rect, scale, clip, visible, depth)
		seq += 1
		local mySeq = seq
		raw(inst).seq = raw(inst).seq or seq
		local r = raw(inst)
		r.layout = { AbsolutePosition = Vector2.new(rect.x, rect.y), AbsoluteSize = Vector2.new(rect.w, rect.h) }
		local isVisible = visible and inst.Visible
		local myRecord = { inst = inst, rect = rect, clip = clip, visible = isVisible, scale = scale, depth = depth }
		table.insert(records, myRecord)
		local startIdx = #records
		-- UIScale: the subtree (this element included) is laid out in its own units, then multiplied about
		-- this element's top-left, exactly like Roblox's render transform.
		local us = inst:FindFirstChildOfClass("UIScale")
		local scaleFactor = if us then us.Scale else 1
		local childScale = scale
		local box = contentBox(inst, rect, childScale)
		local childClip = clip
		if inst.ClipsDescendants or inst:IsA("ScrollingFrame") then
			childClip = R.Intersect(clip, rect) or { x = rect.x, y = rect.y, w = 0, h = 0 }
			childClip.seq = seq
		end
		local kids = {}
		for _, c in childrenOf(inst) do
			if c:IsA("GuiObject") then
				table.insert(kids, c)
			end
		end
		local list = inst:FindFirstChildOfClass("UIListLayout")
		local grid = inst:FindFirstChildOfClass("UIGridLayout")
		if inst:IsA("ScrollingFrame") then
			box = { x = box.x - inst.CanvasPosition.X, y = box.y - inst.CanvasPosition.Y, w = box.w, h = box.h }
		end
		if list then
			local vertical = list.FillDirection == Enum.FillDirection.Vertical
			local gap = udimPx(list.Padding, if vertical then box.h else box.w, childScale)
			local ordered = {}
			for _, c in sorted(kids, list.SortOrder) do
				if c.Visible then
					table.insert(ordered, c)
				end
			end
			local sizes = {}
			local total = 0
			for i, c in ordered do
				local s = measure(c, box, childScale)
				sizes[i] = s
				total += (if vertical then s.Y else s.X) + (if i > 1 then gap else 0)
			end
			local mainLen = if vertical then box.h else box.w
			local start = 0
			local mainAlign = if vertical then list.VerticalAlignment else list.HorizontalAlignment
			if mainAlign == Enum.VerticalAlignment.Center or mainAlign == Enum.HorizontalAlignment.Center then
				start = (mainLen - total) / 2
			elseif mainAlign == Enum.VerticalAlignment.Bottom or mainAlign == Enum.HorizontalAlignment.Right then
				start = mainLen - total
			end
			local cursor = start
			for i, c in ordered do
				local s = sizes[i]
				local cx, cy
				if vertical then
					cy = box.y + cursor
					local cross = list.HorizontalAlignment
					cx = box.x + (if cross == Enum.HorizontalAlignment.Center then (box.w - s.X) / 2 elseif cross == Enum.HorizontalAlignment.Right then box.w - s.X else 0)
					cursor += s.Y + gap
				else
					cx = box.x + cursor
					local cross = list.VerticalAlignment
					cy = box.y + (if cross == Enum.VerticalAlignment.Center then (box.h - s.Y) / 2 elseif cross == Enum.VerticalAlignment.Bottom then box.h - s.Y else 0)
					cursor += s.X + gap
				end
				place(c, { x = cx, y = cy, w = s.X, h = s.Y }, childScale, childClip, isVisible, depth + 1)
			end
			for _, c in kids do
				if not c.Visible then
					place(c, { x = box.x, y = box.y, w = 0, h = 0 }, childScale, childClip, false, depth + 1)
				end
			end
		elseif grid then
			local cw = udimPx(grid.CellSize.X, box.w, childScale)
			local chh = udimPx(grid.CellSize.Y, box.h, childScale)
			local gx = udimPx(grid.CellPadding.X, box.w, childScale)
			local gy = udimPx(grid.CellPadding.Y, box.h, childScale)
			local perRow = math.max(1, math.floor((box.w + gx) / (cw + gx)))
			local i = 0
			for _, c in sorted(kids, grid.SortOrder) do
				if c.Visible then
					local col = i % perRow
					local row = i // perRow
					place(c, { x = box.x + col * (cw + gx), y = box.y + row * (chh + gy), w = cw, h = chh }, childScale, childClip, isVisible, depth + 1)
					i += 1
				else
					place(c, { x = box.x, y = box.y, w = 0, h = 0 }, childScale, childClip, false, depth + 1)
				end
			end
		else
			for _, c in kids do
				local s = measure(c, box, childScale)
				local px = box.x + udimPx(c.Position.X, box.w, childScale) - c.AnchorPoint.X * s.X
				local py = box.y + udimPx(c.Position.Y, box.h, childScale) - c.AnchorPoint.Y * s.Y
				place(c, { x = px, y = py, w = s.X, h = s.Y }, childScale, childClip, isVisible, depth + 1)
			end
		end
		if scaleFactor ~= 1 then
			local ox, oy = rect.x, rect.y
			for i = startIdx, #records do
				local rec = records[i]
				local rr = rec.rect
				rec.rect = { x = ox + (rr.x - ox) * scaleFactor, y = oy + (rr.y - oy) * scaleFactor, w = rr.w * scaleFactor, h = rr.h * scaleFactor }
				rec.scale = rec.scale * scaleFactor
				raw(rec.inst).layout = { AbsolutePosition = Vector2.new(rec.rect.x, rec.rect.y), AbsoluteSize = Vector2.new(rec.rect.w, rec.rect.h) }
			end
		end
	end

	local previous = {}
	for _, c in screenGui:GetDescendants() do
		if raw(c).layout then
			previous[c] = raw(c).layout.AbsoluteSize
		end
	end
	for _, c in childrenOf(screenGui) do
		if c:IsA("GuiObject") then
			local s = measure(c, screen, 1)
			local px = screen.x + udimPx(c.Position.X, screen.w, 1) - c.AnchorPoint.X * s.X
			local py = screen.y + udimPx(c.Position.Y, screen.h, 1) - c.AnchorPoint.Y * s.Y
			place(c, { x = px, y = py, w = s.X, h = s.Y }, 1, screen, screenGui.Enabled, 1)
		end
	end
	-- Clips: recomputed from the final rects (after UIScale transforms) by walking the ancestors.
	local recOf = {}
	for _, rec in records do
		recOf[rec.inst] = rec
	end
	for _, rec in records do
		local c = { x = screen.x, y = screen.y, w = screen.w, h = screen.h }
		local p = rec.inst.Parent
		while p and p ~= screenGui do
			local pr = recOf[p]
			if pr and (p.ClipsDescendants or p:IsA("ScrollingFrame")) then
				c = R.Intersect(c, pr.rect) or { x = pr.rect.x, y = pr.rect.y, w = 0, h = 0 }
			end
			p = p.Parent
		end
		rec.clip = c
	end
	-- Fire AbsoluteSize changed signals like the engine does, so size-driven code (virtual grids) reflows.
	for _, rec in records do
		local r = raw(rec.inst)
		local before = previous[rec.inst]
		local after = r.layout.AbsoluteSize
		if r.propSignals.AbsoluteSize and (not before or before.X ~= after.X or before.Y ~= after.Y) then
			r.propSignals.AbsoluteSize:Fire()
		end
	end
	return records, screen
end

function R.Intersect(a, b)
	if not a or not b then
		return nil
	end
	local x1, y1 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x2, y2 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	if x2 <= x1 or y2 <= y1 then
		return nil
	end
	return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

-- ----------------------------------------------------------------------------------------- environment
baseEnv = {
	game = game,
	workspace = Workspace,
	Instance = Instance,
	Enum = Enum,
	Vector2 = Vector2,
	Vector3 = Vector3,
	UDim = UDim,
	UDim2 = UDim2,
	Color3 = Color3,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	NumberRange = NumberRange,
	TweenInfo = TweenInfo,
	CFrame = CFrame,
	Random = Random,
	typeof = luauTypeof,
	task = task,
	warn = function(...)
		local parts = {}
		for _, v in { ... } do
			table.insert(parts, tostring(v))
		end
		R.Warnings = R.Warnings or {}
		table.insert(R.Warnings, table.concat(parts, " "))
	end,
	tick = os.clock,
	elapsedTime = os.clock,
	wait = task.wait,
	spawn = task.spawn,
	delay = task.delay,
	_G = {},
	shared = {},
	newproxy = newproxy,
}

R.Services = services
-- Exposed for tools/tests/cutscene_director.luau, which adds 3D stubs (PivotTo, Raycast, ...) and a virtual clock.
R.Methods = methods
R.BaseEnv = baseEnv
return R
