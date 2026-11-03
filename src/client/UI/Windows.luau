--!strict
-- Modal window manager. One centred window at a time, over a dimmed backdrop, sized from HudLayout.Modal.
--   Windows.Register("Shop", function(host) return { Frame = frame, OnOpen = fn(arg)?, OnClose = fn()? } end)
--   Windows.Open("Shop", "Boosts")   Windows.Toggle("Book")   Windows.Close()   Windows.Changed:Connect(fn(id?))
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local HudLayout = require(script.Parent:WaitForChild("HudLayout"))
local Create = require(script.Parent:WaitForChild("Components"):WaitForChild("Create"))

export type WindowDef = { Frame: GuiObject, OnOpen: ((arg: any) -> ())?, OnClose: (() -> ())? }

local Windows = {}
Windows.Changed = Signal.new()

local factories: { [string]: (host: Frame) -> WindowDef } = {}
local built: { [string]: WindowDef } = {}
local current: string? = nil
local gui: ScreenGui? = nil
local host: Frame? = nil
local backdrop: TextButton? = nil

local function ensureGui(): (ScreenGui, Frame, TextButton)
	if gui and host and backdrop then
		return gui, host, backdrop
	end
	local g: ScreenGui = Create.New("ScreenGui", { Name = "FetchModal", ResetOnSpawn = false, DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	local b: TextButton = Create.New("TextButton", { Name = "Backdrop", Text = "", AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.Backdrop, BackgroundTransparency = Theme.BackdropTransparency, BorderSizePixel = 0,
		Size = UDim2.new(1, 200, 1, 200), Position = UDim2.fromOffset(-100, -100), Visible = false, Parent = g })
	local h: Frame = Create.New("Frame", { Name = "Host", BackgroundTransparency = 1, Visible = false, Parent = g })
	local function relayout()
		local size = g.AbsoluteSize
		if size.X > 0 then
			HudLayout.Apply(h, HudLayout.Compute(size.X, size.Y).Modal)
		end
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	relayout()
	b.Activated:Connect(function()
		Windows.Close()
	end)
	gui, host, backdrop = g, h, b
	return g, h, b
end

function Windows.Register(id: string, factory: (host: Frame) -> WindowDef)
	factories[id] = factory
end

function Windows.Current(): string?
	return current
end

function Windows.IsOpen(id: string): boolean
	return current == id
end

function Windows.Close()
	if not current then
		return
	end
	local def = built[current]
	if def then
		def.Frame.Visible = false
		if def.OnClose then
			task.spawn(def.OnClose)
		end
	end
	current = nil
	local _, h, b = ensureGui()
	h.Visible = false
	b.Visible = false
	Windows.Changed:Fire(nil)
end

function Windows.Open(id: string, arg: any?)
	local factory = factories[id]
	if not factory then
		warn("[Windows] no window registered as " .. id)
		return
	end
	if current and current ~= id then
		Windows.Close()
	end
	local _, h, b = ensureGui()
	local def = built[id]
	if not def then
		def = factory(h)
		def.Frame.Parent = h
		built[id] = def
	end
	local d = def :: WindowDef
	current = id
	h.Visible = true
	b.Visible = true
	d.Frame.Visible = true
	if d.OnOpen then
		d.OnOpen(arg)
	end
	Windows.Changed:Fire(id)
end

function Windows.Toggle(id: string, arg: any?)
	if current == id and arg == nil then
		Windows.Close()
	else
		Windows.Open(id, arg)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if current and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
		Windows.Close()
		GuiService.SelectedObject = nil
	end
end)

return Windows
