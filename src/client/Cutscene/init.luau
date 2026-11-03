--!strict
-- THE THROW CUTSCENE: client controller (docs/DESIGN.md §20). Started once by Main.client.luau:
--   Cutscene.Start(ui)
-- For the LOCAL player's throws it runs Director sessions:
--   * the meter release (ui.ThrowReleased) starts the wind-up at once; the ThrowResult is buffered into the
--     running session whenever it arrives (or starts a session if no local release was seen);
--   * on arrival it asks the server to stream the landing zone in (RequestStreamAroundAsync(LandPos));
--   * a result that arrives after the session gave up ("the ball rolled away") just shows the end card.
-- Other players' throws are animated by Cutscene/Spectator (from BallFlight.client.luau), never here.
-- Config/Game.CutsceneTestMode adds the test panel (Cutscene/TestPanel) that plays local fakes.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Config:WaitForChild("Game"))
local C = require(Config:WaitForChild("Cutscene"))
local CutsceneShared = Shared:WaitForChild("Cutscene")
local Timeline = require(CutsceneShared:WaitForChild("Timeline"))
local FakeResult = require(CutsceneShared:WaitForChild("FakeResult"))
local Path = require(CutsceneShared:WaitForChild("Path"))

local Director = require(script:WaitForChild("Director"))
local Sfx = require(script:WaitForChild("Sfx"))

local Cutscene = {}

local player = Players.LocalPlayer
local ui: any = nil
local current: any = nil -- the running Director session
local queue: { any } = {} -- results that arrived while another session was playing
local gaveUpAt = -math.huge -- when a session last gave up on an unanswered throw
local LATE_WINDOW = 30 -- a result this soon after giving up belongs to that throw: end card only
local looping = false
local rng = Random.new()

local function snapshotLuck(): (number, number)
	local okL, luck = pcall(function()
		return (ui.State.Luck())
	end)
	local okC, bonus = pcall(function()
		return ui.State.CatchBonus()
	end)
	return (if okL and type(luck) == "number" then luck else 0), (if okC and type(bonus) == "number" then bonus else 0)
end

local function ballId(): string
	local ok, id = pcall(function()
		return ui.State.Ball().Id
	end)
	return if ok and type(id) == "string" then id else "Tennis"
end

local startSession: (opts: { Result: any?, Elapsed: number?, Tutorial: boolean? }) -> ()
local playFake: (spec: any) -> ()

local function onSessionDone()
	local s = current
	current = nil
	if s and s.GaveUp then
		-- an unanswered throw: a very late result for it only shows the end card
		gaveUpAt = os.clock()
	end
	local nextResult = table.remove(queue, 1)
	if nextResult then
		startSession({ Result = nextResult })
	elseif looping then
		task.delay(C.Test.LoopGap, function()
			if looping and current == nil then
				playFake({})
			end
		end)
	end
end

function startSession(opts: { Result: any?, Elapsed: number?, Tutorial: boolean? })
	local luck, bonus = snapshotLuck()
	local s = Director.new({
		Ui = ui,
		Result = opts.Result,
		Luck = luck,
		CatchBonus = bonus,
		BallId = (opts.Result and opts.Result.BallId) or ballId(),
		Elapsed = opts.Elapsed,
		Tutorial = opts.Tutorial,
		OnDone = onSessionDone,
	})
	current = s
	task.spawn(function()
		s:Run()
	end)
end

local function streamAround(result: any)
	local _, land = Path.Endpoints(result)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(land)
		end)
	end)
end

local function onThrowResult(result: any)
	if type(result) ~= "table" or result.ThrowerUserId ~= player.UserId then
		return
	end
	local ok, r = Timeline.Validate(result)
	if not ok then
		warn("[Cutscene] " .. tostring(r))
		task.defer(function()
			ui:FinishThrow(result.ThrowId)
		end)
		return
	end
	streamAround(r)
	if current and not current.Result and not current.Done and not current.GaveUp then
		current:SetResult(r) -- buffered into the running wind-up / flight / hold
	elseif current then
		table.insert(queue, r)
	elseif os.clock() - gaveUpAt < LATE_WINDOW then
		-- the cutscene already showed "the ball rolled away" for this throw: just show the outcome card
		gaveUpAt = -math.huge
		ui:ShowReveal(r, { OnClose = function()
			ui:FinishThrow(r.ThrowId)
		end })
	else
		startSession({ Result = r })
	end
end

local function onReleased(info: any)
	if current then
		return
	end
	startSession({ Elapsed = info and info.Elapsed, Tutorial = info and info.Tutorial })
end

function playFake(spec: any)
	if current then
		return
	end
	local s = table.clone(spec or {})
	s.UserId = player.UserId
	s.BallId = ballId()
	local fake = FakeResult.Make(rng, s)
	startSession({ Result = fake })
end

function Cutscene.Start(uiHandle: any)
	ui = uiHandle
	ui.Config.PlaceholderCutscene = false
	ui.Config.ReleaseSafetySeconds = Timeline.SafetySeconds()
	Sfx.Enabled = function(): boolean
		return ui.State.Settings.Sfx ~= false
	end
	if ui.ThrowReleased then
		ui.ThrowReleased:Connect(onReleased)
	end
	local remote = Remotes.Get("ThrowResult") :: RemoteEvent
	remote.OnClientEvent:Connect(function(result)
		local ok, err = pcall(onThrowResult, result)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
		end
	end)
	if (Game :: any).CutsceneTestMode == true then
		local TestPanel = require(script:WaitForChild("TestPanel"))
		ui.CutsceneTest = TestPanel.new({
			Parent = ui.Root,
			IsTouch = ui.IsTouch == true,
			Router = ui.Router,
			OnPlay = playFake,
			OnLoop = function(on: boolean)
				looping = on
			end,
		})
	end
end

-- Plays a local fake outcome (what the test panel buttons call). Never reaches the server.
--   _G.ThrowABallUI.Cutscene.PlayFake({ Rarity = "Mythic", Caught = false, Variant = "Rainbow" })
function Cutscene.PlayFake(spec: any)
	playFake(spec)
end

-- For the Studio command bar: _G.ThrowABallUI.Cutscene.Skip()
function Cutscene.Skip()
	if current then
		current:Skip()
	end
end

function Cutscene.Current(): any
	return current
end

return Cutscene
