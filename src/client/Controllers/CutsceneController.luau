--!strict
-- The local thrower's 3D cutscene. The UI (src/client/UI) is started with PlaceholderCutscene = false, so on
-- every ThrowResult for the local player this module:
--   1. hides the HUD and disables movement,
--   2. plays the cutscene through CutsceneContract (PlaceholderCutscene for v1) without its own end card,
--   3. shows the UI's Reveal end card (ui:ShowReveal), and when that closes
--   4. calls ui:FinishThrow(throwId) and fires CutsceneFinished(throwId) exactly once.
-- Other players' throws are not handled here: the UI shows its Spectator banner for them.
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

local CutsceneController = {}

local player = Players.LocalPlayer
local ui: any = nil
local queue: { any } = {}
local playing = false
local controls: any = nil
local reported: { [string]: boolean } = {}

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

-- Ends the throw once: unlocks the HUD and tells the server (never for CutsceneTestMode fakes).
local function finishThrow(result: any)
	local id = tostring(result.ThrowId)
	if reported[id] then
		return
	end
	reported[id] = true
	ui:FinishThrow(result.ThrowId)
	if not result.IsTest then
		local finished = Remotes.Get("CutsceneFinished") :: RemoteEvent
		finished:FireServer(result.ThrowId)
	end
end

local playThrower: (result: any) -> ()

local function playNext()
	local nextResult = table.remove(queue, 1)
	if nextResult then
		task.spawn(playThrower, nextResult)
	end
end

function playThrower(result: any)
	playing = true
	ui.HUD.Root.Visible = false
	setControls(false)
	local ok, err = pcall(function()
		local handle = CutsceneContract.Play(result, { IsThrower = true, IsSpectator = false, EndCard = false })
		handle:Await()
	end)
	if not ok then
		warn("[CutsceneController] " .. tostring(err))
	end
	setControls(true)
	ui.HUD.Root.Visible = true
	playing = false

	local rarity = result.Rarity or "Common"
	if ui.State.Settings.HideCommonReveals and rarity == "Common" then
		finishThrow(result)
		playNext()
		return
	end
	local closed = false
	ui:ShowReveal(result, {
		IsDupe = result.Status == "PendingSale" and result.DogUid ~= nil and not result.IsTest,
		OnClose = function()
			if closed then
				return
			end
			closed = true
			finishThrow(result)
			playNext()
		end,
	})
end

local function onThrowResult(result: any)
	if type(result) ~= "table" or result.ThrowerUserId ~= player.UserId then
		return
	end
	if playing then
		table.insert(queue, result)
	else
		task.spawn(playThrower, result)
	end
end

local function buildTestButton()
	local E = if ui.IsTouch then Theme.Space.M else Theme.Space.Edge
	Button.new({
		Name = "CutsceneTest",
		Text = "Test Cutscene",
		Palette = "Purple",
		TextSize = Theme.Text.Body,
		Size = UDim2.fromOffset(150, 44),
		Position = UDim2.new(1, -E, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 5,
		Parent = ui.Root,
		OnClick = function()
			local spectator = math.random() < 0.3
			local fake = CutsceneContract.MakeTestResult(DogCatalog, player.UserId, spectator)
			if spectator then
				ui.Spectator:Show(fake.ThrowerName or "TestPlayer", fake)
			else
				onThrowResult(fake)
			end
		end,
	})
end

function CutsceneController.Start(uiHandle: any)
	ui = uiHandle
	ui.Config.PlaceholderCutscene = false
	local remote = Remotes.Get("ThrowResult") :: RemoteEvent
	remote.OnClientEvent:Connect(onThrowResult)
	if Game.CutsceneTestMode then
		buildTestButton()
	end
end

return CutsceneController
