--!strict
-- Listens to ThrowResult for EVERY throw in the server:
--   * everyone sees the ball flight (ThrowController.PlayBallFlight)
--   * the thrower gets the full cutscene via CutsceneContract (placeholder implementation for v1),
--     with the HUD hidden and movement disabled, then fires CutsceneFinished(throwId)
--   * everyone else gets the small spectator banner (never takes the camera)
-- After the thrower's cutscene: whistle prompt on a miss (if owned), Keep button for a pending dupe.
-- Config/Game.CutsceneTestMode adds a debug button that plays random fake outcomes locally.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))
local DogCatalog = require(Shared:WaitForChild("Util"):WaitForChild("DogCatalog"))
local CutsceneContract = require(Shared:WaitForChild("Cutscene"):WaitForChild("CutsceneContract"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Button = require(UI:WaitForChild("Components"):WaitForChild("Button"))

local HudController = require(script.Parent:WaitForChild("HudController"))
local ThrowController = require(script.Parent:WaitForChild("ThrowController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))
local WhistlePrompt = require(script.Parent:WaitForChild("WhistlePrompt"))

local CutsceneController = {}

local player = Players.LocalPlayer
local queue: { any } = {}
local playing = false
local controls: any = nil

local function setControls(enabled: boolean)
	if controls == nil then
		local ok, result = pcall(function()
			local ps = player:WaitForChild("PlayerScripts")
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

local function afterThrower(result: any)
	if not result.Caught then
		WhistlePrompt.Show(result)
	elseif result.Status == "PendingSale" and result.DogUid and not result.IsTest then
		NotificationController.Toast(("Duplicate %s: keep it?"):format(tostring(result.DogName)), "Dupe", {
			Name = "DupeKeep_" .. result.DogUid,
			Duration = 18,
			Buttons = { {
				Text = "Keep",
				Color = Theme.Color.Good,
				OnClick = function()
					local remote = Remotes.Get("DogAction") :: RemoteFunction
					local ok, success, msg = pcall(function()
						return remote:InvokeServer("Keep", result.DogUid)
					end)
					NotificationController.Toast(if ok then tostring(msg) else "Try again", if ok and success then "Purchase" else "Error")
				end,
			} },
		})
	end
end

local function playThrower(result: any)
	playing = true
	ThrowController.SetCutsceneActive(true)
	HudController.SetCutsceneMode(true)
	setControls(false)
	local ok, err = pcall(function()
		local handle = CutsceneContract.Play(result, { IsThrower = true, IsSpectator = false })
		handle:Await()
	end)
	if not ok then
		warn("[CutsceneController] " .. tostring(err))
	end
	if not result.IsTest then
		local finished = Remotes.Get("CutsceneFinished") :: RemoteEvent
		finished:FireServer(result.ThrowId)
	end
	HudController.SetCutsceneMode(false)
	setControls(true)
	ThrowController.SetCutsceneActive(false)
	playing = false
	afterThrower(result)
	local nextResult = table.remove(queue, 1)
	if nextResult then
		task.spawn(playThrower, nextResult)
	end
end

local function onThrowResult(result: any)
	if type(result) ~= "table" then
		return
	end
	local okFlight, flightErr = pcall(ThrowController.PlayBallFlight, result)
	if not okFlight then
		warn("[CutsceneController] ball flight: " .. tostring(flightErr))
	end
	if result.ThrowerUserId == player.UserId then
		if playing then
			table.insert(queue, result)
		else
			task.spawn(playThrower, result)
		end
	else
		CutsceneContract.Play(result, { IsThrower = false, IsSpectator = true, BannerParent = NotificationController.Messages() })
	end
end

local function buildTestButton()
	local region = HudController.Region("Debug")
	region.Visible = true
	Button.new({ Name = "CutsceneTest", Text = "Test Cutscene", Color = Theme.Color.Purple, TextMax = 16, Parent = region,
		OnClick = function()
			local spectator = math.random() < 0.3
			local fake = CutsceneContract.MakeTestResult(DogCatalog, player.UserId, spectator)
			if spectator then
				fake.ThrowerName = "TestPlayer"
			end
			onThrowResult(fake)
		end })
end

function CutsceneController.Start()
	local remote = Remotes.Get("ThrowResult") :: RemoteEvent
	remote.OnClientEvent:Connect(onThrowResult)
	if Game.CutsceneTestMode then
		buildTestButton()
	end
end

return CutsceneController
