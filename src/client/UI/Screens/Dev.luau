--!strict
-- Dev tools (only for players the server marks with the "DevTools" attribute; Config/Game.DevTools, server
-- DevService). A small purple "Dev" pill opens a kit Panel registered with the Router as "Dev":
--   power row:  +100  +1K  +10K  Max  Reset            (ThrowPower; dev power ignores the training caps)
--   zone grid:  Reach Backyard ... Reach Mythic Meadow  (power so a Good throw with the equipped ball lands mid-zone)
--   extras:     +$1M  +10 balls                        (cash, +10 throws of every consumable ball)
-- plus a live line: current ThrowPower and the zone a Good throw reaches with the equipped ball.
-- The pill sits where the CutsceneTestMode pill does (desktop: right edge mid-height; touch: left edge under the
-- side menu, above the thumbstick zone), next to it when that pill exists. Every button calls the DevCommand
-- remote (deps.Command); the server re-checks permission and pushes a StateUpdate.
--   Dev.new({ Parent, IsTouch, Router, Command = (cmd, arg?) -> (ok, msg), Toast, Player?, BesideTestPill? })
--   handle.Pill  handle:Open()  handle:Close()  handle:Refresh()  handle:SetHidden(on)  handle:SetBesideTestPill(on)
--   handle:Destroy()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Zones = require(Config:WaitForChild("Zones"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local DevTools = require(Util:WaitForChild("DevTools"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))
local Icon = require(Components:WaitForChild("Icon"))

local Dev = {}

export type Deps = {
	Parent: Instance,
	IsTouch: boolean,
	Router: any,
	Command: (command: string, arg: any) -> (boolean, string?),
	Toast: ((text: string, icon: string?, palette: string?) -> ())?,
	Player: Player?, -- whose "DevTools" attribute shows the pill (default: nobody -> always shown, tests)
	BesideTestPill: boolean?, -- the CutsceneTestMode pill exists: sit next to it
}

-- Test pill geometry (Cutscene/TestPanel): 170 x 44; desktop right edge, mid-height; touch under the side menu.
local TEST_W, PILL_H = 170, 44
local PILL_W = { Desktop = 96, Touch = 72 }

function Dev.new(deps: Deps)
	local touch = deps.IsTouch
	local E = if touch then Theme.Space.M else Theme.Space.Edge
	local handle = {} :: any
	local busy = false

	local function placement(beside: boolean): (UDim2, Vector2)
		if touch then
			local y = E + 58 + Theme.Space.S + 52 + Theme.Space.S -- under the side-menu row (same row as the test pill)
			local x = if beside then E + TEST_W + Theme.Space.S else E
			return UDim2.fromOffset(x, y), Vector2.new(0, 0)
		end
		local dy = if beside then PILL_H / 2 + Theme.Space.S else -PILL_H / 2
		return UDim2.new(1, -E, 0.5, dy), Vector2.new(1, 0)
	end
	local pos, anchor = placement(deps.BesideTestPill == true)
	local pill = Button.new({
		Name = "DevPill",
		Text = "Dev",
		Icon = if touch then nil else "bolt", -- touch: text only (the pill must stay narrow beside the test pill)
		IconSize = 16,
		Palette = "Purple",
		TextSize = Theme.Text.Body,
		Size = UDim2.fromOffset(if touch then PILL_W.Touch else PILL_W.Desktop, PILL_H),
		Position = pos,
		AnchorPoint = anchor,
		ZIndex = 44,
		Parent = deps.Parent,
	})
	handle.Pill = pill

	local panel = Panel.new({ Title = "Dev tools", Icon = "bolt", Parent = deps.Parent, Name = "DevPanel", Width = 720, Height = 560, OnClose = function()
		deps.Router.Close()
	end })
	handle.Panel = panel
	local scroll: ScrollingFrame = Make("ScrollingFrame", { Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Color.Ink, ZIndex = 53, Parent = panel.Body })
	Decor.List(scroll, Enum.FillDirection.Vertical, Theme.Space.M)
	Make("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = scroll })

	-- live status
	local status = Panel.Section(scroll, "Now", 1)
	local powerLine = Label.Body({ Name = "Power", Text = "", Font = Theme.Font.BodyBold, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, ZIndex = 55, Parent = status })
	local reachRow: Frame = Make("Frame", { Name = "Reach", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, ZIndex = 55, Parent = status })
	Decor.List(reachRow, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local reachIcon = Icon.new({ Name = "zone_backyard", Size = 16, LayoutOrder = 1, ZIndex = 56, Parent = reachRow })
	local reachLine = Label.Body({ Name = "ReachText", Text = "", Size = UDim2.new(1, -24, 1, 0), LayoutOrder = 2, ZIndex = 56, Parent = reachRow })

	local function run(command: string, arg: any)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, msg = deps.Command(command, arg)
			busy = false
			if deps.Toast then
				deps.Toast(msg or (if ok then "Done" else "Refused"), if ok then "bolt" else "close", if ok then "Purple" else "Danger")
			end
		end)
	end

	local function row(parent: Instance, name: string, order: number): Frame
		local r: Frame = Make("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, ZIndex = 55, Parent = parent })
		Decor.List(r, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		return r
	end

	-- power row
	local powerBox = Panel.Section(scroll, "Throw power (ignores the training caps)", 2)
	local powerRow = row(powerBox, "PowerButtons", 1)
	local powerButtons = {
		{ "+100", "AddPower", 100, "Grass" }, { "+1K", "AddPower", 1000, "Grass" }, { "+10K", "AddPower", 10000, "Grass" },
		{ "Max", "MaxPower", nil, "Cash" }, { "Reset", "ResetPower", nil, "Slate" },
	}
	for i, b in powerButtons do
		Button.new({ Name = "Power_" .. b[1], Text = b[1], Palette = b[4], TextSize = Theme.Text.Body, Size = UDim2.new(0.2, -7, 0, 44), Shadow = false, LayoutOrder = i, ZIndex = 56, Parent = powerRow, OnClick = function()
			run(b[2], b[3])
		end })
	end

	-- zone grid: 3 x 3
	local zoneBox = Panel.Section(scroll, "Good throw lands in (equipped ball)", 3)
	local grid: Frame = Make("Frame", { Name = "ZoneButtons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 3 * 44 + 2 * Theme.Space.S), LayoutOrder = 1, ZIndex = 55, Parent = zoneBox })
	Make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 44), CellPadding = UDim2.fromOffset(Theme.Space.S, Theme.Space.S), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, zone in Zones do
		Button.new({ Name = "Zone_" .. zone.Id, Text = "Reach " .. zone.Name, Icon = Icon.ForZone(zone.Id), IconSize = 16, Palette = "Sky", TextSize = Theme.Text.Caption, Shadow = false, LayoutOrder = i, ZIndex = 56, Parent = grid, OnClick = function()
			run("PowerForZone", zone.Id)
		end })
	end

	-- extras
	local extraBox = Panel.Section(scroll, "Test consumable balls", 4)
	local extraRow = row(extraBox, "ExtraButtons", 1)
	Button.new({ Name = "AddCash", Text = "+" .. FormatNumber.Money(DevTools.CashAmount), Icon = "cash", IconSize = 32, Palette = "Cash", TextSize = Theme.Text.Body, Size = UDim2.new(0.5, -4, 0, 44), Shadow = false, LayoutOrder = 1, ZIndex = 56, Parent = extraRow, OnClick = function()
		run("AddCash", nil)
	end })
	Button.new({ Name = "GiveBalls", Text = ("+%d balls"):format(DevTools.BallAmount), Icon = "ball_rubber", IconSize = 32, Palette = "Danger", TextSize = Theme.Text.Body, Size = UDim2.new(0.5, -4, 0, 44), Shadow = false, LayoutOrder = 2, ZIndex = 56, Parent = extraRow, OnClick = function()
		run("GiveBalls", nil)
	end })

	function handle.Refresh()
		local s = State.Get()
		local power = tonumber(s.ThrowPower) or 0
		local ball = PlayerStats.Ball(s)
		local _, zone = DevTools.GoodReach(power, ball.RangeMult)
		powerLine.Text = "ThrowPower " .. FormatNumber.Compact(power)
		reachLine.Text = ("Good throw: %s (%s)"):format(zone.Name, ball.Name)
		Icon.Set(reachIcon, Icon.ForZone(zone.Id))
	end
	handle.Refresh()
	local conn = State.Changed:Connect(function()
		handle.Refresh()
	end)

	-- shown only for players the server marked as devs
	local attrConn: RBXScriptConnection? = nil
	local function applyVisible()
		pill.Root.Visible = deps.Player == nil or deps.Player:GetAttribute("DevTools") == true
		if not pill.Root.Visible and deps.Router.Current() == "Dev" then
			deps.Router.Close()
		end
	end
	if deps.Player then
		attrConn = deps.Player:GetAttributeChangedSignal("DevTools"):Connect(applyVisible)
	end
	applyVisible()

	function handle.Open()
		handle.Refresh()
		panel:Open()
	end
	function handle.Close()
		panel:Close()
	end
	-- hide / show around the cutscene (Director)
	function handle.SetHidden(_, hidden: boolean)
		if hidden then
			pill.Root.Visible = false
		else
			applyVisible()
		end
	end
	-- the CutsceneTestMode pill appeared / went away: sit next to it or alone
	function handle.SetBesideTestPill(_, beside: boolean)
		local p, a = placement(beside)
		pill.Root.Position = p
		pill.Root.AnchorPoint = a
	end
	function handle.Destroy()
		conn:Disconnect()
		if attrConn then
			attrConn:Disconnect()
		end
		panel:Destroy()
		pill.Root:Destroy()
	end

	pill.Root.Activated:Connect(function()
		deps.Router.Open("Dev")
	end)
	deps.Router.Register("Dev", handle)
	return handle
end

return Dev
