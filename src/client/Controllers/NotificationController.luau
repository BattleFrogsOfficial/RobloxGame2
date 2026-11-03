--!strict
-- Broadcast feed (top-centre: "X caught a LEGENDARY ...", "A LEGENDARY ran off from X", global relays) and
-- the personal toast stack (Messages region, shared with spectator cutscene banners and trimmed to fit).
--   NotificationController.Feed(text, rarity?, global?)
--   NotificationController.Toast(text, kind?, { Duration?, Buttons = {{Text, Color?, OnClick}} }?) -> Frame
--   NotificationController.Messages() -> Frame   (spectator banners are parented here too)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local HudLayout = require(UI:WaitForChild("HudLayout"))
local Create = require(UI:WaitForChild("Components"):WaitForChild("Create"))
local Button = require(UI:WaitForChild("Components"):WaitForChild("Button"))

local HudController = require(script.Parent:WaitForChild("HudController"))

local NotificationController = {}

local FEED_KINDS = { Catch = true, Miss = true, Recall = true, Squirrel = true, ServerLuck = true, Global = true }
local TOAST_COLORS: { [string]: Color3 } = {
	Notice = Theme.Color.Info,
	Hint = Theme.Color.Accent,
	Dupe = Theme.Color.Purple,
	YardFull = Theme.Color.Bad,
	AutoSell = Theme.Color.Good,
	Offline = Theme.Color.Good,
	Purchase = Theme.Color.Good,
	Badge = Theme.Color.Accent,
	Error = Theme.Color.Bad,
	Event = Color3.fromRGB(240, 130, 70),
}
local FEED_SECONDS = 7
local TOAST_SECONDS = 4.5

local feedFrame: Frame = nil :: any
local messages: Frame = nil :: any
local feedLine = 22
local order = 0

local function nextOrder(): number
	order += 1
	return order
end

local function fadeOut(frame: GuiObject, after: number)
	task.delay(after, function()
		if frame.Parent == nil then
			return
		end
		for _, d in frame:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.32)
		frame:Destroy()
	end)
end

----------------------------------------------------------------------------------------------------
-- Feed
----------------------------------------------------------------------------------------------------
function NotificationController.Feed(text: string, rarity: string?, global: boolean?)
	if not feedFrame then
		return
	end
	local color = if rarity then Theme.Rarity(rarity) else Theme.Color.Text
	local line = Create.New("Frame", { Name = "FeedLine", BackgroundColor3 = Theme.Color.Panel, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, feedLine), LayoutOrder = nextOrder(), Parent = feedFrame },
		{ Create.Corner(Theme.CornerSmall), Create.Stroke(color, 2) })
	local prefix = if global then '<font color="#FFD25A">[GLOBAL]</font> ' else ""
	Create.Label({ Text = prefix .. text, RichText = true, Font = Theme.Font.Body, TextColor3 = color,
		TextStrokeTransparency = 0.5, TextWrapped = false, Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2), Parent = line },
		Theme.TextMax.Small)
	-- keep at most HudLayout.Feed.Lines lines
	local lines = {}
	for _, c in feedFrame:GetChildren() do
		if c:IsA("Frame") then
			table.insert(lines, c)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #lines > HudLayout.Feed.Lines do
		table.remove(lines, 1):Destroy()
	end
	fadeOut(line, FEED_SECONDS)
end

----------------------------------------------------------------------------------------------------
-- Toasts (Messages region; oldest entries are dropped when the stack would overflow)
----------------------------------------------------------------------------------------------------
local function trimMessages()
	local list = messages:FindFirstChildOfClass("UIListLayout")
	if not list then
		return
	end
	local guard = 0
	while list.AbsoluteContentSize.Y > messages.AbsoluteSize.Y + 1 and guard < 20 do
		guard += 1
		-- prefer dropping the oldest toast; never drop a toast with buttons while a plain one exists
		local oldest: GuiObject? = nil
		for _, c in messages:GetChildren() do
			if c:IsA("GuiObject") and c.Visible and not c:GetAttribute("Sticky") then
				if not oldest or c.LayoutOrder < (oldest :: GuiObject).LayoutOrder then
					oldest = c
				end
			end
		end
		if not oldest then
			break
		end
		local victim = oldest :: GuiObject
		victim:Destroy()
		task.wait() -- let the list recompute
	end
end

export type ToastButton = { Text: string, Color: Color3?, OnClick: () -> () }
export type ToastOpts = { Duration: number?, Buttons: { ToastButton }?, Sticky: boolean?, Name: string? }

function NotificationController.Toast(text: string, kind: string?, opts: ToastOpts?): Frame?
	if not messages then
		return nil
	end
	local o: ToastOpts = opts or {}
	local color = TOAST_COLORS[kind or "Notice"] or Theme.Color.Info
	local h = math.max(HudLayout.Toast.MinH, math.floor(HudLayout.Toast.H * ((HudController.Layout and HudController.Layout.Scale) or 1)))
	if o.Name then
		local existing = messages:FindFirstChild(o.Name)
		if existing then
			existing:Destroy()
		end
	end
	local toast = Create.New("Frame", { Name = o.Name or "Toast", BackgroundColor3 = Theme.Color.Panel, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, h), LayoutOrder = nextOrder(), Parent = messages },
		{ Create.Corner(Theme.CornerSmall), Create.Stroke(color, 2) })
	if o.Sticky then
		toast:SetAttribute("Sticky", true)
	end
	local buttons = o.Buttons or {}
	local btnW = 0
	if #buttons > 0 then
		btnW = math.floor(h * 2.4)
	end
	Create.Label({ Text = text, Font = Theme.Font.Body, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1,
		Size = UDim2.new(1, -(16 + #buttons * (btnW + 4)), 1, -6), Position = UDim2.fromOffset(8, 3), Parent = toast }, Theme.TextMax.Small)
	for i, bdef in buttons do
		Button.new({ Text = bdef.Text, Color = bdef.Color or Theme.Color.Accent, TextMax = 16,
			Size = UDim2.new(0, btnW, 1, -8), Position = UDim2.new(1, -4 - (i - 1) * (btnW + 4), 0, 4), AnchorPoint = Vector2.new(1, 0),
			Parent = toast, OnClick = function()
				bdef.OnClick()
				toast:Destroy()
			end })
	end
	local scale = Create.New("UIScale", { Scale = 0.6, Parent = toast })
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.defer(trimMessages)
	if not o.Sticky or o.Duration then
		fadeOut(toast, o.Duration or (if #buttons > 0 then TOAST_SECONDS * 2 else TOAST_SECONDS))
	end
	return toast
end

function NotificationController.Messages(): Frame
	return messages
end

----------------------------------------------------------------------------------------------------
local function onBroadcast(payload: any)
	if type(payload) ~= "table" or type(payload.Text) ~= "string" then
		return
	end
	local kind = tostring(payload.Kind or "Notice")
	if FEED_KINDS[kind] or payload.Global == true then
		NotificationController.Feed(payload.Text, payload.Rarity, payload.Global == true)
	else
		NotificationController.Toast(payload.Text, kind)
	end
end

local function onEventState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "Squirrel" then
		if payload.Active then
			NotificationController.Toast("A squirrel is loose in the plaza! Chase it to win Bones!", "Event", { Name = "SquirrelToast" })
		end
	elseif payload.Kind == "DailyWalk" then
		local data = payload.Data or {}
		if payload.Active and data.Available ~= false then
			NotificationController.Toast("Your daily walk is ready!", "Event", {
				Name = "DailyWalkToast",
				Sticky = true,
				Duration = 60,
				Buttons = { {
					Text = "Claim",
					Color = Theme.Color.Good,
					OnClick = function()
						local remote = Remotes.Get("ClaimDailyWalk") :: RemoteFunction
						local ok, success, msg = pcall(function()
							return remote:InvokeServer()
						end)
						NotificationController.Toast(if ok then tostring(msg or (if success then "Claimed!" else "Not yet")) else "Try again",
							if ok and success then "Purchase" else "Error")
					end,
				} },
			})
		end
	end
end

function NotificationController.Start()
	feedFrame = HudController.Region("Feed")
	messages = HudController.Region("Messages")
	Create.List(Enum.FillDirection.Vertical, HudLayout.Feed.Gap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent = feedFrame
	Create.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent = messages
	HudController.LayoutChanged:Connect(function(layout: HudLayout.Layout)
		feedLine = layout.FeedLine
		for _, c in feedFrame:GetChildren() do
			if c:IsA("Frame") then
				c.Size = UDim2.new(1, 0, 0, feedLine)
			end
		end
		task.defer(trimMessages)
	end)
	if HudController.Layout then
		feedLine = HudController.Layout.FeedLine
	end
	messages.ChildAdded:Connect(function()
		task.defer(trimMessages)
	end)
	local broadcast = Remotes.Get("Broadcast") :: RemoteEvent
	broadcast.OnClientEvent:Connect(onBroadcast)
	local eventState = Remotes.Get("EventState") :: RemoteEvent
	eventState.OnClientEvent:Connect(onEventState)
end

return NotificationController
