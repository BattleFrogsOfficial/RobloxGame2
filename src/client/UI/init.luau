--!strict
-- Client UI entry. UI.Start(deps?) builds the ScreenGui, the HUD, every panel, and wires the remotes.
-- Another client module (the cutscene) can take over parts of the flow through the returned handle:
--   ui.Config.PlaceholderCutscene = false   -- the cutscene module calls ui:ShowReveal and ui:FinishThrow
--   ui.Config.ReleaseSafetySeconds = n      -- how long the HUD stays locked waiting for a ThrowResult (default 6)
--   ui.ThrowReleased:Connect(fn({ Clock, Elapsed, Tutorial }))   -- the meter was released (wind-up starts here)
--   ui:FinishThrow(throwId)                 -- unlocks the HUD and sends CutsceneFinished(throwId) EXACTLY ONCE
--                                              for a throw the server sent; nil / fakes only unlock
--   ui.HUD:SetCharging(true, startClock)   -- if it owns throw input (pass OwnsThrowInput = false)
-- Started by Main.client.luau (the only client entry), which passes PlaceholderCutscene = false and starts
-- src/client/Cutscene (the throw cutscene).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Config:WaitForChild("Game"))
local Timers = require(Config:WaitForChild("Timers"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Make = require(script:WaitForChild("Make"))
local Theme = require(script:WaitForChild("Theme"))
local Motion = require(script:WaitForChild("Motion"))
local State = require(script:WaitForChild("State"))
local Router = require(script:WaitForChild("Router"))
local Screens = script:WaitForChild("Screens")
local HUD = require(Screens:WaitForChild("HUD"))
local Shop = require(Screens:WaitForChild("Shop"))
local Dogs = require(Screens:WaitForChild("Dogs"))
local Book = require(Screens:WaitForChild("Book"))
local Odds = require(Screens:WaitForChild("Odds"))
local Settings = require(Screens:WaitForChild("Settings"))
local Reveal = require(Screens:WaitForChild("Reveal"))
local Spectator = require(Screens:WaitForChild("Spectator"))

local UI = {}

export type StartDeps = {
	Parent: Instance?, -- defaults to PlayerGui
	OwnsThrowInput: boolean?, -- default true
	PlaceholderCutscene: boolean?, -- default true: show the end card after Timers.Cutscene[rarity] seconds
	Remotes: { [string]: Instance }?, -- test injection; defaults to Remotes.Get
	IsTouch: boolean?, -- test injection
	Viewport: Vector2?, -- test injection
}

local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

function UI.Start(deps: StartDeps?)
	local d: StartDeps = deps or {}
	local player = Players.LocalPlayer
	local parent = d.Parent or (player and player:WaitForChild("PlayerGui"))
	local isTouch = if d.IsTouch ~= nil then d.IsTouch :: boolean else isTouchDevice()

	local gui: ScreenGui = Make("ScreenGui", {
		Name = "ThrowABallUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	-- Scaled root: UIScale multiplies offsets; the root is enlarged by 1/scale so it still fills the screen.
	local root: Frame = Make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local uiScale: UIScale = Make("UIScale", { Scale = 1, Parent = root })

	local function viewport(): Vector2
		if d.Viewport then
			return d.Viewport
		end
		local cam = workspace.CurrentCamera
		return if cam then cam.ViewportSize else Theme.Canvas
	end
	local function applyScale()
		local vp = viewport()
		local inset = 0
		pcall(function()
			local topLeft = GuiService:GetGuiInset()
			inset = topLeft.Y
		end)
		local usable = Vector2.new(vp.X, math.max(1, vp.Y - inset))
		local s = math.clamp(math.min(usable.X / Theme.Canvas.X, usable.Y / Theme.Canvas.Y), Theme.ScaleMin, Theme.ScaleMax)
		-- Phones: never go below the touch-target floor relative to physical size.
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	applyScale()
	local cam = workspace.CurrentCamera
	if cam and not d.Viewport then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	-- Remotes (injectable)
	local function remote(name: string): any
		if d.Remotes then
			return d.Remotes[name]
		end
		return Remotes.Get(name)
	end
	local function invoke(name: string, ...: any): (boolean, string?)
		local r = remote(name)
		if not r or not r:IsA("RemoteFunction") then
			return false, "Not available"
		end
		local ok, res, msg = pcall(r.InvokeServer, r, ...)
		if not ok then
			return false, "Network error"
		end
		if type(res) == "boolean" then
			return res, msg
		end
		return true, nil
	end
	local function fire(name: string, ...: any)
		local r = remote(name)
		if r and r:IsA("RemoteEvent") then
			r:FireServer(...)
		end
	end

	local ui = { Gui = gui, Root = root, Config = { PlaceholderCutscene = d.PlaceholderCutscene ~= false, ReleaseSafetySeconds = 6 },
		ThrowReleased = Signal.new() } :: any
	local toast = function(text: string, icon: string?, palette: string?)
		ui.HUD.Toasts:Show(text, icon, palette)
	end

	-- HUD
	local throwInFlight: string? = nil
	local chargeClock = 0
	local chargeTutorial = false
	local serverThrows: { [string]: boolean } = {} -- ThrowIds the server sent us (only these get CutsceneFinished)
	local reported: { [string]: boolean } = {} -- ThrowIds CutsceneFinished was already sent for
	ui.HUD = HUD.new({
		Parent = root,
		IsTouch = isTouch,
		Open = function(screen)
			Router.Open(screen)
		end,
		OwnsThrowInput = d.OwnsThrowInput,
		ClaimDailyWalk = function()
			task.spawn(function()
				local ok, msg = invoke("ClaimDailyWalk")
				toast(msg or (if ok then "Daily walk claimed!" else "Not ready yet"), "walk", if ok then "Cash" else "Danger")
			end)
		end,
		OnChargeBegin = function()
			if throwInFlight then
				return
			end
			fire("ChargeBegin")
			-- Same period the server uses (ThrowService: tutorial until TutorialThrowDone).
			local tutorial = Game.Tutorial.Enabled and State.Get().TutorialThrowDone ~= true
			chargeClock = os.clock()
			chargeTutorial = tutorial
			ui.HUD:SetCharging(true, chargeClock, tutorial)
		end,
		OnChargeRelease = function()
			if not ui.HUD:IsCharging() then
				return
			end
			fire("ChargeRelease")
			ui.HUD:SetCharging(false)
			ui.HUD:SetThrowLocked(true, "Fetching...")
			throwInFlight = "pending"
			ui.ThrowReleased:Fire({ Clock = os.clock(), Elapsed = os.clock() - chargeClock, Tutorial = chargeTutorial })
			-- Safety: unlock if the server refused the throw and no ThrowResult arrives.
			task.delay(ui.Config.ReleaseSafetySeconds or 6, function()
				if throwInFlight == "pending" then
					throwInFlight = nil
					ui.HUD:SetThrowLocked(false)
				end
			end)
		end,
	})

	-- Panels
	ui.Shop = Shop.new({ Parent = root, Purchase = function(itemId)
		return invoke("ShopPurchase", itemId)
	end, EquipBall = function(ballId)
		fire("EquipBall", ballId)
	end, Toast = toast, OnClose = Router.Close })
	ui.Dogs = Dogs.new({ Parent = root, DogAction = function(action, uid)
		return invoke("DogAction", action, uid)
	end, Toast = toast, OnClose = Router.Close })
	ui.Book = Book.new({ Parent = root, ClaimReward = function(zoneId, m)
		return invoke("ClaimBookReward", zoneId, m)
	end, Toast = toast, OnClose = Router.Close })
	ui.Odds = Odds.new({ Parent = root, OnClose = Router.Close })
	-- Server-side settings go through the existing DogAction remote (DogService handles SetTreatPocketMode and
	-- SetKeepDupes "<Rarity>=true|false"); the next StateUpdate echoes them back into State.Settings.
	ui.Settings = Settings.new({ Parent = root, OnClose = Router.Close, SetServerSetting = function(key, value)
		task.spawn(function()
			if key == "TreatPocketMode" and type(value) == "string" then
				invoke("DogAction", "SetTreatPocketMode", value)
			elseif key == "KeepDupes" and type(value) == "table" then
				local server = (State.Get().Settings or {}).KeepDupes or {}
				for tier, keep in value do
					if (server[tier] == true) ~= (keep == true) then
						invoke("DogAction", "SetKeepDupes", ("%s=%s"):format(tostring(tier), tostring(keep == true)))
					end
				end
			end
		end)
	end })
	ui.Reveal = Reveal.new(root)
	ui.Spectator = Spectator.new(root, isTouch)
	Router.Register("Shop", ui.Shop)
	Router.Register("Dogs", ui.Dogs)
	Router.Register("Book", ui.Book)
	Router.Register("Odds", ui.Odds)
	Router.Register("Settings", ui.Settings)

	-- While a modal is open the throw prompt/meter hide and clicks never start a throw.
	Router.OnChange(function(name)
		ui.HUD:SetSuppressed(name ~= nil)
	end)

	-- Reveal helper used by the cutscene module too.
	function ui.ShowReveal(_, result: any, opts: Reveal.RevealOpts?)
		local o = opts or {}
		local wrapped: Reveal.RevealOpts = {
			Spectator = o.Spectator,
			IsDupe = o.IsDupe,
			AutoCloseSeconds = o.AutoCloseSeconds,
			OnKeep = o.OnKeep or function()
				-- Keep is a DogAction on the newest dog; the server resolves "newest" by uid list order.
				local newest = State.Dogs()[#State.Dogs()]
				if newest then
					invoke("DogAction", "Keep", newest.Uid)
				end
			end,
			OnWhistle = o.OnWhistle or function()
				local ok, msg = invoke("UseWhistle", result.ThrowId)
				toast(if ok then "Whistle! The dog came back" else (msg or "Too late"), "whistle", if ok then "Cash" else "Danger")
			end,
			OnClose = function()
				if o.OnClose then
					o.OnClose()
				end
			end,
		}
		ui.Reveal:Show(result, wrapped)
	end

	-- Remote listeners
	local localId = if player then player.UserId else 0
	local function onThrowResult(result: any)
		if type(result) ~= "table" then
			return
		end
		local mine = result.ThrowerUserId == localId
		if mine then
			throwInFlight = result.ThrowId
			if type(result.ThrowId) == "string" then
				serverThrows[result.ThrowId] = true
			end
			local rarity = result.Rarity or "Common"
			local wait = (Timers.Cutscene :: any)[rarity] or 2
			if ui.Config.PlaceholderCutscene then
				local hideCommon = State.Settings.HideCommonReveals and rarity == "Common"
				task.delay(if hideCommon then 0.5 else wait, function()
					local function finish()
						ui:FinishThrow(result.ThrowId)
					end
					if hideCommon then
						finish()
					else
						ui:ShowReveal(result, { OnClose = finish })
					end
				end)
			end
			if result.LuckyStreakTriggered and ui.Config.PlaceholderCutscene then
				toast("Lucky Streak!", "bolt", "Cash") -- the real cutscene shows its own flourish
			end
		else
			local idx = table.find(Rarities.Order, result.Rarity or "Common") or 1
			if idx >= 3 then
				local who = Players:GetPlayerByUserId(result.ThrowerUserId)
				ui.Spectator:Show(if who then who.DisplayName else "Someone", result)
			end
		end
	end
	-- Ends a throw: unlocks the HUD and tells the server CutsceneFinished(throwId) exactly once, and only for a
	-- throw the server actually sent (CutsceneTestMode fakes and nil never reach the server).
	function ui.FinishThrow(_, throwId: string?)
		if throwId == nil or throwInFlight == throwId then
			throwInFlight = nil
			ui.HUD:SetThrowLocked(false)
		end
		if type(throwId) == "string" and serverThrows[throwId] and not reported[throwId] then
			reported[throwId] = true
			fire("CutsceneFinished", throwId)
		end
	end

	local function connect(name: string, fn: (...any) -> ())
		local r = remote(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(fn)
		end
	end
	connect("StateUpdate", function(snapshot)
		State.Set(snapshot)
	end)
	connect("Broadcast", function(payload)
		ui.HUD:Broadcast(payload)
	end)
	connect("EventState", function(payload)
		if type(payload) == "table" then
			State.SetEvent(payload.Kind, payload)
			if payload.Kind == "Squirrel" and payload.Active then
				toast("Squirrel! Everyone to the park", "squirrel", "Purple")
			elseif payload.Kind == "DailyWalk" and payload.Active then
				ui.HUD:SetBadge("Dogs", true)
			end
		end
	end)
	connect("ThrowResult", onThrowResult)

	-- Initial snapshot
	task.spawn(function()
		local r = remote("RequestState")
		if r and r:IsA("RemoteFunction") then
			local ok, snap = pcall(r.InvokeServer, r)
			if ok and type(snap) == "table" then
				State.Set(snap)
			end
		end
	end)

	-- Tear everything down (tests, or a full UI rebuild). Disconnects screen listeners before destroying.
	function ui.Destroy()
		for _, key in { "Shop", "Dogs", "Book", "Odds", "Settings" } do
			local s = ui[key]
			if s and s.Destroy then
				s:Destroy()
			end
		end
		ui.HUD:Destroy()
		Router.Reset()
		gui:Destroy()
	end

	Motion.ReducedMotion = State.Settings.ReducedMotion
	gui.Parent = parent
	ui.Router = Router
	ui.State = State
	ui.IsTouch = isTouch
	return ui
end

return UI
