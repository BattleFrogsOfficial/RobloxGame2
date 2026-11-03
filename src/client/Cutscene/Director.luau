--!strict
-- The thrower's cutscene (local player only). One Session per throw, created at the meter release (or when a
-- ThrowResult arrives without one) and fed the ThrowResult whenever it arrives. It only DISPLAYS the server's
-- outcome; the counter target is display-only. Beats (docs/DESIGN.md §20, timings in Config/Cutscene.luau):
--   1 wind-up + camera sweep   2 release, ball POV   3 landing ease-out + bounces + impact FX
--   4 the dog arrives + push-in   5 the odds counter   6 caught / missed   end card   7 return
-- Rules: skippable from the counter on (never Legendary / Mythic); Settings.HideCommonReveals = short Common;
-- ReducedMotion = hard cuts; a late ThrowResult holds the landing shot up to Fallback.HoldMax, then "the ball
-- rolled away" (no CutsceneFinished). The whole sequence is pcall-wrapped: any error, skip, death or
-- character removal cleans every instance / connection / sound / tween and restores the camera + HUD.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local CutsceneShared = Shared:WaitForChild("Cutscene")
local C = require(Config:WaitForChild("Cutscene"))
local Layout = require(Config:WaitForChild("Layout"))
local Rarities = require(Config:WaitForChild("Rarities"))
local BallFlight = require(Util:WaitForChild("BallFlight"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local Timeline = require(CutsceneShared:WaitForChild("Timeline"))
local OddsCounter = require(CutsceneShared:WaitForChild("OddsCounter"))
local Path = require(CutsceneShared:WaitForChild("Path"))
local Shots = require(CutsceneShared:WaitForChild("Shots"))

local Here = script.Parent
local Janitor = require(Here:WaitForChild("Janitor"))
local Sfx = require(Here:WaitForChild("Sfx"))
local Ball = require(Here:WaitForChild("Ball"))
local Rig = require(Here:WaitForChild("Rig"))
local Effects = require(Here:WaitForChild("Effects"))
local DogActor = require(Here:WaitForChild("DogActor"))
local Overlay = require(Here:WaitForChild("Overlay"))

local Director = {}
Director.__index = Director

local SKIP = "__cutscene_skip__"
local ABORT = "__cutscene_abort__"
local STEP = "ThrowCutsceneCamera"
local UP = Vector3.new(0, 1, 0)

export type Start = {
	Ui: any,
	Result: any?, -- ThrowResult (or a CutsceneTestMode fake) if already known
	Luck: number, -- State.Luck() at the release (the counter's luck; display only)
	CatchBonus: number,
	BallId: string, -- ball used for this throw (shown in the hand before the result arrives)
	Elapsed: number?, -- meter time at the release (estimate for a late result)
	Tutorial: boolean?,
	OnDone: (() -> ())?,
}

local function isSkipOrAbort(err: any): boolean
	local s = tostring(err)
	return string.find(s, SKIP, 1, true) ~= nil or string.find(s, ABORT, 1, true) ~= nil
end

function Director.new(start: Start)
	local self = setmetatable({}, Director) :: any
	self.Ui = start.Ui
	self.Result = nil
	self.Luck = start.Luck
	self.CatchBonus = start.CatchBonus
	self.BallId = start.BallId
	self.Elapsed = start.Elapsed
	self.Tutorial = start.Tutorial == true
	self.OnDone = start.OnDone
	self.Reduced = self.Ui.State.Settings.ReducedMotion == true
	self.Session = Janitor.new() -- lives until the camera is back
	self.Scene = Janitor.new() -- ball, dog, overlay contents, sounds: cleaned before the end card
	self.Phase = "WindUp"
	self.Done = false
	self.GaveUp = false
	self._skip = false
	self._abort = nil :: string?
	self._resultAt = nil :: number?
	self.CameraFn = nil :: ((now: number, dt: number) -> CFrame?)?
	self.Fov = C.WindUp.Fov
	if start.Result then
		self:SetResult(start.Result)
	end
	return self
end

function Director.SetResult(self: any, result: any)
	if self.Result or self.Done then
		return
	end
	local ok, r = Timeline.Validate(result)
	if not ok then
		warn("[Cutscene] bad ThrowResult: " .. tostring(r))
		return
	end
	self.Result = r
	self._resultAt = os.clock()
	if r.BallId then
		self.BallId = r.BallId
	end
end

function Director.IsTest(self: any): boolean
	return self.Result ~= nil and self.Result.IsTest == true
end

function Director.CanSkip(self: any): boolean
	return self.Result ~= nil and Timeline.CanSkip(self.Result.Rarity, self.Phase)
end

function Director.Skip(self: any)
	if self:CanSkip() then
		self._skip = true
	end
end

function Director.Abort(self: any, reason: string)
	self._abort = reason
end

-- Frame-stepped wait that unwinds on skip (only while skippable) or abort.
function Director._wait(self: any, seconds: number)
	local deadline = os.clock() + math.max(0, seconds)
	repeat
		if self._abort then
			error(ABORT, 0)
		end
		if self._skip and self:CanSkip() then
			error(SKIP, 0)
		end
		RunService.RenderStepped:Wait()
	until os.clock() >= deadline
	if self._abort then
		error(ABORT, 0)
	end
end

function Director._waitFor(self: any, cond: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not cond() do
		if os.clock() >= deadline then
			return false
		end
		self:_wait(0)
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- Lock / unlock: HUD, controls, camera
----------------------------------------------------------------------------------------------------
local controls: any = nil
local function setControls(enabled: boolean)
	if controls == nil then
		local ok, result = pcall(function()
			local ps = Players.LocalPlayer:WaitForChild("PlayerScripts")
			local pm = require(ps:WaitForChild("PlayerModule", 5) :: ModuleScript) :: any
			return pm:GetControls()
		end)
		controls = if ok then result else false
	end
	if controls then
		pcall(function()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

function Director._lock(self: any)
	local ui = self.Ui
	pcall(function()
		ui.Router.Close()
	end)
	ui.HUD.Root.Visible = false
	if ui.CutsceneTest and not ui.CutsceneTest:IsLooping() then
		ui.CutsceneTest.Pill.Root.Visible = false
	end
	setControls(false)
	local cam = workspace.CurrentCamera
	self.Saved = { CameraType = cam.CameraType, Subject = cam.CameraSubject, Fov = cam.FieldOfView, CFrame = cam.CFrame }
	cam.CameraType = Enum.CameraType.Scriptable
	local player = Players.LocalPlayer
	local char = player.Character
	self.Character = char
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	self.Humanoid = humanoid
	self.Root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid then
		self.SavedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		self.Session:Add(humanoid.Died:Connect(function()
			self:Abort("died")
		end))
	end
	self.Session:Add(player.CharacterRemoving:Connect(function()
		self:Abort("character removed")
	end))
	self.Overlay = Overlay.new(ui.Root, ui.IsTouch == true)
	self.Session:Add(self.Overlay)
	-- One camera step for the whole cutscene; beats swap self.CameraFn.
	local last = os.clock()
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		local dt = now - last
		last = now
		local fn = self.CameraFn
		if not fn then
			return
		end
		local ok, cf = pcall(fn, now, dt)
		if not ok then
			warn("[Cutscene] camera: " .. tostring(cf))
			self.CameraFn = nil
			self:Abort("error")
			return
		end
		if cf then
			cam.CFrame = cf
		end
		cam.FieldOfView = self.Fov
	end)
	self.Session:Add(function()
		pcall(function()
			RunService:UnbindFromRenderStep(STEP)
		end)
	end)
end

function Director._restoreCamera(self: any, tween: boolean)
	self.CameraFn = nil
	pcall(function()
		RunService:UnbindFromRenderStep(STEP)
	end)
	local cam = workspace.CurrentCamera
	local saved = self.Saved
	if not saved then
		return
	end
	if tween and not self.Reduced and not self._abort then
		local from = cam.CFrame
		local target = saved.CFrame
		local root = self.Root
		if root and root.Parent then
			-- the player did not move (controls off); aim back at the saved default view
			target = saved.CFrame
		end
		local t0 = os.clock()
		local fov0 = cam.FieldOfView
		while os.clock() - t0 < C.Return.Time do
			local k = Shots.EaseInOut((os.clock() - t0) / C.Return.Time)
			cam.CFrame = from:Lerp(target, k)
			cam.FieldOfView = fov0 + (saved.Fov - fov0) * k
			RunService.RenderStepped:Wait()
		end
		cam.CFrame = target
	end
	cam.FieldOfView = saved.Fov
	cam.CameraType = if saved.CameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.CameraType
	local char = Players.LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject = humanoid or saved.Subject
end

function Director._unlock(self: any)
	local ui = self.Ui
	if self.Humanoid and self.Humanoid.Parent and self.SavedAutoRotate ~= nil then
		self.Humanoid.AutoRotate = self.SavedAutoRotate
	end
	setControls(true)
	ui.HUD.Root.Visible = true
	if ui.CutsceneTest then
		ui.CutsceneTest.Pill.Root.Visible = true
	end
	pcall(function()
		ui.HUD:RefreshThrow()
	end)
end

----------------------------------------------------------------------------------------------------
-- Run: the whole sequence, wrapped
----------------------------------------------------------------------------------------------------
function Director.Run(self: any)
	local okLock, lockErr = pcall(self._lock, self)
	if not okLock then
		warn("[Cutscene] lock failed: " .. tostring(lockErr))
	end
	local ok, err = true, nil
	if okLock then
		ok, err = pcall(self._beats, self)
	end
	if not ok and not isSkipOrAbort(err) then
		warn("[Cutscene] " .. tostring(err))
	end
	if self.Rig then
		self.Rig:Stop()
	end
	self.Scene:Clean()
	self.CameraFn = nil
	if self.Overlay then
		pcall(function()
			self.Overlay:Hide()
		end)
	end
	local aborted = self._abort ~= nil
	if aborted then
		-- death / character removal / runtime error: give the camera back right away
		pcall(self._restoreCamera, self, false)
	end
	local result = self.Result
	if result and not self.GaveUp then
		self.Phase = "EndCard"
		local okCard, cardErr = pcall(self._endCard, self)
		if not okCard then
			warn("[Cutscene] end card: " .. tostring(cardErr))
		end
	end
	if not aborted then
		local okRet, retErr = pcall(self._restoreCamera, self, true)
		if not okRet then
			warn("[Cutscene] return: " .. tostring(retErr))
			pcall(self._restoreCamera, self, false)
		end
	end
	self.Session:Clean()
	pcall(self._unlock, self)
	self.Done = true
	-- RETURN: the throw is over. A real, answered throw sends CutsceneFinished exactly once (ui:FinishThrow);
	-- a fake never does; an unanswered throw only unlocks the HUD.
	if result and not self.GaveUp and not result.IsTest then
		self.Ui:FinishThrow(result.ThrowId)
	elseif not result then
		self.Ui:FinishThrow(nil)
	end
	if self.OnDone then
		task.spawn(self.OnDone)
	end
end

function Director._endCard(self: any)
	local result = self.Result
	local ui = self.Ui
	local closed = false
	local test = result.IsTest == true
	local opts: any = {
		IsDupe = (not test) and result.Status == "PendingSale" and result.DogUid ~= nil,
		OnClose = function()
			closed = true
		end,
	}
	if test then
		opts.OnWhistle = function()
			ui.HUD.Toasts:Show("Test outcome: nothing sent", "whistle", "Purple")
		end
		opts.OnKeep = function() end
		if ui.CutsceneTest and ui.CutsceneTest:IsLooping() then
			opts.AutoCloseSeconds = C.Test.LoopEndCard
		end
	end
	ui:ShowReveal(result, opts)
	-- The Reveal card always closes (OK, whistle, keep or its own timer); 30 s is a last-resort guard.
	local deadline = os.clock() + 30
	while not closed and os.clock() < deadline do
		RunService.RenderStepped:Wait()
	end
end

----------------------------------------------------------------------------------------------------
-- Beats
----------------------------------------------------------------------------------------------------
function Director._beats(self: any)
	local cam = workspace.CurrentCamera
	local root: BasePart? = self.Root
	local rootPos = if root then root.Position else Layout.Platform.ThrowSpot + Vector3.new(0, 3, 0)
	local facing = Vector3.new(0, 0, 1) -- the field runs +Z from the throw line
	if root then
		-- face the field (the local character replicates its own pivot)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
	end
	local startCF = cam.CFrame
	local released = os.clock()

	-- 1. WIND-UP ---------------------------------------------------------------------------------
	local ball = Ball.Make(self.BallId)
	self.Scene:Add(ball)
	local fallbackHand = rootPos + Vector3.new(-1.5, 1.2, 0)
	self.Rig = Rig.Play(self.Character, ball, fallbackHand, { Assets = true })
	self.Scene:Add(function()
		self.Rig:Stop()
	end)
	local front = Shots.Front(rootPos, facing)
	self.Fov = C.WindUp.Fov
	if self.Reduced then
		self.CameraFn = function()
			return front
		end
	else
		self.CameraFn = function(now)
			return Shots.Sweep(startCF, rootPos, facing, (now - released) / C.WindUp.SweepTime)
		end
	end
	self.Phase = "WindUp"
	self:_wait(C.WindUp.ReleaseAt)

	-- 2. LAUNCH + BALL POV ------------------------------------------------------------------------
	local hand = self.Rig:HandPosition()
	self.Rig:Release()
	Ball.SetTrail(ball, true)
	Sfx.Play("Whoosh", { Volume = 0.6, Janitor = self.Scene })
	local wind = Sfx.Play("Wind", { Volume = C.Flight.WindMinVolume, Pitch = C.Flight.WindMinPitch, Looped = true, Janitor = self.Scene })

	local function realFlight(): any
		local launch, land = Path.Endpoints(self.Result)
		local arc = BallFlight.ForThrow(launch, land)
		local seconds = Timeline.FlightSeconds(tonumber(self.Result.FlightTime) or arc.Duration)
		return Path.Flight(arc, hand, seconds)
	end
	local flight: any
	local estimated = false
	if self.Result then
		flight = realFlight()
	else
		estimated = true
		local state = self.Ui.State
		local power = state.ThrowPower()
		local ballDef = Ball.Def(self.BallId)
		local Meter = require(Util:WaitForChild("Meter"))
		local quality = Meter.Evaluate(self.Elapsed or 0.8, self.Tutorial)
		local launch, land = Path.Estimate(power, ballDef.RangeMult, quality, rootPos.X)
		local arc = BallFlight.ForThrow(launch, land)
		flight = Path.Flight(arc, hand, Timeline.FlightSeconds(arc.Duration))
	end
	local flightStart = os.clock()
	local function flightT(): number
		return os.clock() - flightStart
	end
	local frontAtRelease = if self.Reduced then front else cam.CFrame
	local shakeSeed = math.random(1, 1000)
	local L = C.Landing
	self.Phase = "Flight"
	local function pov(t: number): CFrame
		return Shots.Pov(flight.Position(t), flight.Velocity(t), facing)
	end
	self.CameraFn = function(now, _dt)
		local t = now - flightStart
		-- a ThrowResult that arrived mid-flight: blend the estimate into the real arc
		if estimated and self.Result then
			estimated = false
			flight = Path.Retarget(flight, realFlight(), t)
		end
		local p = flight.Position(t)
		local v = flight.Velocity(t)
		ball.CFrame = if v.Magnitude > 1e-3 then CFrame.lookAt(p, p + v) else CFrame.new(p)
		if wind then
			local k = math.clamp(v.Magnitude / C.Flight.WindSpeedForMax, 0, 1)
			wind.Volume = C.Flight.WindMinVolume + (C.Flight.WindMaxVolume - C.Flight.WindMinVolume) * k
			wind.PlaybackSpeed = C.Flight.WindMinPitch + (C.Flight.WindMaxPitch - C.Flight.WindMinPitch) * k
		end
		local dur = flight.Duration
		local landStart = dur * (1 - L.Share)
		local cf: CFrame
		local wide = Shots.Wide(flight.Land, facing)
		if self.Reduced then
			cf = if t < landStart then pov(t) else wide
			self.Fov = if t < landStart then C.ReducedMotion.PovFov else L.WideFov
		else
			if t < landStart then
				cf = pov(t)
				local w = math.clamp(t / C.Flight.WhipTime, 0, 1)
				if w < 1 then
					cf = frontAtRelease:Lerp(cf, Shots.EaseInOut(w))
				end
				self.Fov = C.WindUp.Fov + (C.Flight.PovFov - C.WindUp.Fov) * w
				cf *= Shots.Shake(t, shakeSeed, C.Flight.ShakeStuds, C.Flight.ShakeDegrees, C.Flight.ShakeTime)
			else
				-- LANDING: drift up and behind, gaining height + distance, to the wide shot at touchdown
				local k = Shots.EaseInOut((t - landStart) / math.max(1e-3, dur - landStart))
				cf = pov(t):Lerp(wide, k)
				self.Fov = C.Flight.PovFov + (L.WideFov - C.Flight.PovFov) * k
			end
		end
		return cf
	end
	while flightT() < flight.Duration do
		self:_wait(0)
	end
	if wind then
		wind:Stop()
	end
	local landPos = flight.Land
	local wideCF = Shots.Wide(landPos, facing)
	self.CameraFn = function()
		return wideCF
	end
	ball.CFrame = CFrame.new(landPos)

	-- 3. LANDING: late result? hold up to Fallback.HoldMax, else "the ball rolled away" -------------
	if not self.Result then
		self.Phase = "Hold"
		local arrived = self:_waitFor(function()
			return self.Result ~= nil
		end, C.Fallback.HoldMax)
		if not arrived then
			self.GaveUp = true
			self.Overlay:ShowMessage(C.Fallback.Text)
			self:_wait(C.Fallback.ShowFor)
			self.Overlay:Hide()
			return
		end
		-- the real landing spot: roll the ball there from the guess
		local _, realLand = Path.Endpoints(self.Result)
		local from = landPos
		local t0 = os.clock()
		local realWide = Shots.Wide(realLand, facing)
		local fromWide = wideCF
		self.CameraFn = function(now)
			local k = Shots.EaseInOut((now - t0) / C.Fallback.RollTime)
			ball.CFrame = CFrame.new(from:Lerp(realLand, k) + Vector3.new(0, C.Flight.BallSize / 2, 0))
			return fromWide:Lerp(realWide, k)
		end
		self:_wait(C.Fallback.RollTime)
		landPos = realLand
		wideCF = realWide
	end
	local result = self.Result
	local rarity = result.Rarity
	local plan = Timeline.Build(rarity, flight.Duration, { Short = Timeline.IsShort(rarity, self.Ui.State.Settings.HideCommonReveals) })
	self.Plan = plan

	-- touchdown: impact + bounces
	Effects.Impact(result.ZoneId, landPos, self.Scene)
	local bounces = Path.Bounces(landPos, facing)
	local lift = Vector3.new(0, C.Flight.BallSize / 2, 0)
	local touch = os.clock()
	local bumpSeed = math.random(1, 1000)
	local bounceSound = 1
	local ballFollowsDog: any = nil
	self.Scene:Add(RunService.RenderStepped:Connect(function()
		if ballFollowsDog then
			ball.CFrame = ballFollowsDog()
			return
		end
		local t = os.clock() - touch
		ball.CFrame = CFrame.new(Path.BounceAt(bounces, t) + lift)
		local hop = bounces.Hops[bounceSound + 1]
		if hop and t >= hop.T0 then
			bounceSound += 1
			Sfx.Play("Bounce", { Volume = 0.35 * C.Landing.BounceDecay ^ (bounceSound - 1), Janitor = self.Scene })
		end
	end))
	self.CameraFn = function(now)
		if self.Reduced and C.ReducedMotion.NoShake then
			return wideCF
		end
		return wideCF * Shots.Shake(now - touch, bumpSeed, C.Landing.ImpactShakeStuds, 0.3, 0.25)
	end
	self.Fov = L.WideFov
	self.Phase = "Settle"
	self:_wait(plan.ByName.Settle.Length)
	if plan.Short then
		return
	end

	-- 4. THE DOG ARRIVES --------------------------------------------------------------------------
	self.Phase = "DogArrive"
	local rest = bounces.Rest
	local dog = DogActor.new(result.DogId, result.Variant, self.Scene)
	local camRight = Shots.Flat(wideCF.RightVector)
	local fieldCX = (Layout.Field.MinX + Layout.Field.MaxX) / 2
	-- come in from the side with more room (toward the middle of the field)
	local side = if rest.X > fieldCX then -camRight else camRight
	if side.X * (rest.X - fieldCX) > 0 then
		side = -side
	end
	local minX, maxX = Layout.Field.MinX + C.Dog.EdgeMargin, Layout.Field.MaxX - C.Dog.EdgeMargin
	local function clampX(p: Vector3): Vector3
		return Vector3.new(math.clamp(p.X, minX, maxX), p.Y, p.Z)
	end
	local stopPos = clampX(rest + side * C.Dog.StopOffset)
	local startPos = clampX(rest + side * C.Dog.StartMax)
	do
		local d = C.Dog.StartMin
		while d <= C.Dog.StartMax do
			local cand = clampX(rest + side * d)
			local _, onScreen = cam:WorldToViewportPoint(cand + UP * 2)
			startPos = cand
			if not onScreen then
				break
			end
			d += 3
		end
	end
	local arrive = plan.ByName.DogArrive.Length
	local dogFocus = stopPos + UP * 1.5
	if dog then
		dog.Anim.HopRate = C.Dog.HopRate
		dog.Anim:Play("hop")
		local gStart = dog:Ground(startPos.X, startPos.Z, landPos.Y)
		local gStop = dog:Ground(stopPos.X, stopPos.Z, landPos.Y)
		startPos = Vector3.new(startPos.X, gStart, startPos.Z)
		stopPos = Vector3.new(stopPos.X, gStop, stopPos.Z)
		dog:Place(startPos, stopPos)
		dogFocus = stopPos + UP * math.min(3, dog:Height() * 0.5)
	end
	local a0 = os.clock()
	local pushTarget = dogFocus
	self.CameraFn = function(now)
		local k = math.clamp((now - a0) / math.max(1e-3, arrive), 0, 1)
		if dog then
			local e = 1 - (1 - k) ^ 2 -- ease out: slows to a stop beside the ball
			dog:Place(startPos:Lerp(stopPos, e), stopPos + (stopPos - startPos).Unit * 2)
		end
		if self.Reduced then
			return wideCF
		end
		local hold = C.Dog.HoldShare
		local p = math.clamp((k - hold) / math.max(1e-3, 1 - hold), 0, 1)
		local e = Shots.EaseInOut(p)
		self.Fov = L.WideFov + (C.Dog.PushFov - L.WideFov) * e
		return wideCF:Lerp(Shots.Toward(wideCF, pushTarget, C.Dog.PushIn), e)
	end
	self:_wait(arrive)
	if dog then
		dog:Place(stopPos, rest)
		dog.Anim:Play("idle")
	end
	local pushedCF = Shots.Toward(wideCF, pushTarget, C.Dog.PushIn)
	if self.Reduced then
		self.Fov = C.Dog.PushFov -- reduced motion: hard cut to the closer shot
	end

	-- 5. THE ODDS COUNTER -------------------------------------------------------------------------
	self.Phase = "Counter"
	local counterLen = plan.ByName.Counter.Length
	local target = OddsCounter.Target(result.ZoneId, rarity, self.Luck, self.CatchBonus)
	local thresholds = OddsCounter.Thresholds(result.ZoneId, self.Luck, self.CatchBonus)
	local schedule = OddsCounter.Schedule(target, counterLen)
	local overlay = self.Overlay
	overlay:ShowCounter()
	if Timeline.CanSkip(rarity, "Counter") then
		overlay:SetSkip(true, function()
			self:Skip()
		end)
	end
	local c0 = os.clock()
	local lastIdx = 0
	local lastClick = 0
	local lastTier: string? = nil
	local m = #schedule.Values
	self.CameraFn = function(now)
		local t = now - c0
		local idx = OddsCounter.IndexAt(schedule, t)
		if idx ~= lastIdx then
			lastIdx = idx
			local v = schedule.Values[idx]
			local tier = OddsCounter.TierAt(v, thresholds, rarity)
			local climbed = tier ~= lastTier
			lastTier = tier
			overlay:SetCount(v, tier, climbed)
			if climbed and tier then
				Sfx.Play("Punch", { Volume = 0.4, Pitch = 0.8 + 0.1 * (table.find(Rarities.Order, tier) or 1), Janitor = self.Scene })
			elseif now - lastClick >= C.Counter.ClickMinGap then
				lastClick = now
				Sfx.Play("Click", { Volume = C.Counter.ClickVolume, Pitch = OddsCounter.ClickPitch(idx, m), Janitor = self.Scene })
			end
		end
		if self.Reduced then
			return pushedCF
		end
		local k = Shots.EaseInOut(t / math.max(1e-3, counterLen + plan.ByName.CounterHold.Length))
		return Shots.Toward(pushedCF, pushTarget, C.Dog.CounterDrift * k)
	end
	self:_wait(counterLen)
	overlay:SetCount(target, rarity, lastTier ~= rarity)
	local def = DogCatalog.Get(result.DogId)
	overlay:SetStopped(if def then def.Name else tostring(result.DogName or result.DogId), rarity, result.Variant)
	Sfx.Play("Stop", { Volume = 0.6, Pitch = 1.2, Janitor = self.Scene })
	self.Phase = "CounterHold"
	self:_wait(plan.ByName.CounterHold.Length)
	local holdCF = cam.CFrame
	self.CameraFn = function()
		return holdCF
	end

	-- 6. OUTCOME ----------------------------------------------------------------------------------
	self.Phase = "Outcome"
	local O = plan.ByName.Outcome.Length
	local o = C.Outcome
	local flourish: string? = nil
	if result.Caught and result.LuckyStreakTriggered then
		flourish = o.FlourishLucky
	elseif result.Caught and result.TreatPocketUsed then
		flourish = o.FlourishTreat
	end
	if flourish then
		task.delay(o.FlourishTime, function()
			if not self.Done and self.Phase == "Outcome" then
				overlay:SetFlourish(flourish)
				Effects.Sparkle(stopPos + UP * 2, (Rarities.Tiers :: any)[rarity].Color, self.Scene)
			end
		end)
	end
	if not dog then
		self:_wait(O)
		return
	end
	local dogActor = dog :: any
	if result.Caught then
		-- pick up the ball, turn to the hub, hop away; the camera follows from behind
		local pick = O * o.PickUpShare
		dogActor.Anim:StartOnce("pickup", pick)
		self:_wait(pick * 0.5)
		ballFollowsDog = function()
			return dogActor:MouthCFrame()
		end
		self:_wait(pick * 0.5)
		Sfx.Play("Happy", { Volume = 0.5, Janitor = self.Scene })
		local hub = Vector3.new(Layout.Platform.ThrowSpot.X, stopPos.Y, Layout.ThrowLine.Z)
		local dir = Shots.Flat(hub - stopPos, Vector3.new(0, 0, -1))
		local yaw0 = dogActor:Yaw()
		local yaw1 = math.atan2(-dir.X, -dir.Z)
		local dyaw = (yaw1 - yaw0 + math.pi) % (2 * math.pi) - math.pi
		local turn = O * o.TurnShare
		local tt0 = os.clock()
		self.CameraFn = function(now)
			dogActor:SetYaw(yaw0 + dyaw * Shots.EaseInOut((now - tt0) / math.max(1e-3, turn)))
			return holdCF
		end
		self:_wait(turn)
		dogActor:SetYaw(yaw1)
		dogActor.Anim:Play("hop")
		local h0 = os.clock()
		local from = holdCF
		local start = stopPos
		self.CameraFn = function(now)
			local t = now - h0
			local pos = start + dir * (o.HopSpeed * t)
			dogActor:Place(Vector3.new(pos.X, start.Y, pos.Z), nil)
			if self.Reduced then
				return from
			end
			local follower = start + dir * (o.HopSpeed * o.FollowLag * t)
			local want = Shots.Follow(follower, dir)
			local cf = Shots.LookAt(want.Position, pos + UP * 1.5)
			return from:Lerp(cf, Shots.EaseInOut(t / 0.35))
		end
		self:_wait(O - pick - turn)
	else
		-- sniff the ball, look at the camera, bolt out of frame; sad sting
		local sniff = O * o.SniffShare
		dogActor.Anim:StartOnce("sniff", sniff)
		self:_wait(sniff)
		local look = O * o.LookShare
		local pivot = dogActor.Model:GetPivot()
		local rel = pivot:PointToObjectSpace(cam.CFrame.Position)
		dogActor.Anim.LookYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.2, 1.2)
		dogActor.Anim.LookPitch = math.clamp(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.2, 0.7)
		dogActor.Anim:StartOnce("look", look)
		self:_wait(look)
		Sfx.Play("Sting", { Volume = o.StingVolume, Janitor = self.Scene })
		local away = Shots.Flat(-side * 0.85 + Shots.Flat(holdCF.LookVector) * 0.5)
		-- bolt toward whichever side keeps the dog in the field longest
		if (stopPos + away * 30).X < minX or (stopPos + away * 30).X > maxX then
			away = Shots.Flat(Vector3.new(-away.X, 0, away.Z))
		end
		dogActor:SetYaw(math.atan2(-away.X, -away.Z))
		dogActor.Anim:Play("bolt")
		local b0 = os.clock()
		local start = stopPos
		self.CameraFn = function(now)
			local pos = start + away * (o.BoltSpeed * (now - b0))
			dogActor:Place(Vector3.new(pos.X, start.Y, pos.Z), nil)
			return holdCF
		end
		self:_wait(O - sniff - look)
	end
end

return Director
