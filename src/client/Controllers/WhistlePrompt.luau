--!strict
-- "Use Golden Whistle? (N left)" — shown ONLY if the player already owns whistles, after the thrower's
-- miss cutscene, during the whistle window (until the runaway leaves the plaza). Never a Robux prompt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Timers = require(Shared:WaitForChild("Config"):WaitForChild("Timers"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local HudLayout = require(UI:WaitForChild("HudLayout"))
local Create = require(UI:WaitForChild("Components"):WaitForChild("Create"))
local Button = require(UI:WaitForChild("Components"):WaitForChild("Button"))
local ProgressBar = require(UI:WaitForChild("Components"):WaitForChild("ProgressBar"))

local StateController = require(script.Parent:WaitForChild("StateController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local WhistlePrompt = {}

local gui: ScreenGui? = nil
local activeThrowId: string? = nil
local closeCurrent: (() -> ())? = nil

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g: ScreenGui = Create.New("ScreenGui", { Name = "WhistlePrompt", ResetOnSpawn = false, DisplayOrder = 25,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	gui = g
	return g
end

function WhistlePrompt.Hide(throwId: string?)
	if closeCurrent and (throwId == nil or throwId == activeThrowId) then
		closeCurrent()
	end
end

function WhistlePrompt.Show(result: any)
	local state = StateController.Get()
	local count = if state then (state.Whistles or 0) else (tonumber(result.WhistleCount) or 0)
	if count <= 0 or result.Caught then
		return
	end
	WhistlePrompt.Hide()
	local g = ensureGui()
	local card = Create.Panel({ Name = "Card", BackgroundColor3 = Theme.Color.Panel, Parent = g }, { Create.Padding(10) })
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Color.Accent
	end
	local function layout()
		local size = g.AbsoluteSize
		if size.X > 0 then
			HudLayout.Apply(card, HudLayout.Compute(size.X, size.Y).Whistle)
		end
	end
	local sizeConn = g:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	Create.Label({ Text = ("Use Golden Whistle? (%d left)"):format(count), TextColor3 = Theme.Color.Accent,
		Size = UDim2.fromScale(1, 0.3), Parent = card }, Theme.TextMax.Big)
	Create.Label({ Text = ('<font color="#%s">%s</font> %s ran off. Recall it before it leaves the plaza!'):format(
		Theme.Rarity(result.Rarity):ToHex(), string.upper(tostring(result.Rarity)), tostring(result.DogName or "your dog")),
		RichText = true, Font = Theme.Font.Body, Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.3), Parent = card },
		Theme.TextMax.Small)
	local bar = ProgressBar.new(card, Theme.Color.Accent, { Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.54) })
	local deadline = os.clock() + Timers.RunawaySeconds
	local closed = false
	local hb: RBXScriptConnection? = nil
	local function close()
		if closed then
			return
		end
		closed = true
		if hb then
			hb:Disconnect()
		end
		sizeConn:Disconnect()
		card:Destroy()
		if activeThrowId == result.ThrowId then
			activeThrowId = nil
			closeCurrent = nil
		end
	end
	activeThrowId = result.ThrowId
	closeCurrent = close
	local useButton = Button.new({ Text = ("Use (%d left)"):format(count), Color = Theme.Color.Accent, TextMax = 20,
		Size = UDim2.fromScale(0.48, 0.28), Position = UDim2.fromScale(0, 0.72), Parent = card })
	Button.new({ Text = "Let it go", Color = Theme.Color.PanelLight, TextMax = 20, Size = UDim2.fromScale(0.48, 0.28),
		Position = UDim2.fromScale(1, 0.72), AnchorPoint = Vector2.new(1, 0), Parent = card, OnClick = close })
	useButton.Activated:Connect(function()
		if closed then
			return
		end
		if result.IsTest then
			NotificationController.Toast("(test) Whistle would be used here", "Notice")
			close()
			return
		end
		useButton.Text = "..."
		local remote = Remotes.Get("UseWhistle") :: RemoteFunction
		local ok, success, msg = pcall(function()
			return remote:InvokeServer(result.ThrowId)
		end)
		NotificationController.Toast(if ok then tostring(msg) else "Whistle failed, try again", if ok and success then "Purchase" else "Error")
		close()
	end)
	hb = RunService.Heartbeat:Connect(function()
		local left = deadline - os.clock()
		bar.Set(left / Timers.RunawaySeconds, ("%ds"):format(math.max(0, math.ceil(left))))
		if left <= 0 then
			close()
		end
	end)
end

function WhistlePrompt.Start()
	local eventState = Remotes.Get("EventState") :: RemoteEvent
	eventState.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.Kind == "RunawayDog" and payload.Active == false and type(payload.Data) == "table" then
			WhistlePrompt.Hide(payload.Data.ThrowId)
		end
	end)
end

return WhistlePrompt
