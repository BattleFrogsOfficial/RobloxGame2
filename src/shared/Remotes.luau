--!strict
-- SHARED NETWORK CONTRACT. The server creates every remote under ReplicatedStorage.Remotes at startup
-- (call Remotes.Init() once from the server). Clients call Remotes.Get(name), which WaitForChild's it.
-- All payloads are plain tables. Every client->server remote is rate-limited and validated on the server.
--
-- ChargeBegin        RemoteEvent    C->S ()                       first click: starts the meter; server timestamps it. Only valid
--                                                                  for the player at ThrowQueuePos 1 who is OnPlatform (one throw per turn)
-- ChargeRelease      RemoteEvent    C->S ()                       second click: release; server derives meter position from elapsed
--                                                                  time (auto-release after Game.Throw.MaxChargeSeconds)
-- ThrowResult        RemoteEvent    S->All (ThrowResult)          one per throw, sent to every client (thrower + spectators)
-- CutsceneFinished   RemoteEvent    C->S (throwId: string)        thrower's cutscene ended (server also times out on its own)
-- UseWhistle         RemoteFunction C->S (throwId) -> (ok, msg)   only valid for a missed throw, within the whistle window
-- RequestState       RemoteFunction C->S () -> PlayerState        initial snapshot
-- StateUpdate        RemoteEvent    S->C (PlayerState)            full snapshot after any change
-- ShopPurchase       RemoteFunction C->S (itemId) -> (ok, msg)
-- EquipBall          RemoteEvent    C->S (ballId)                 refused for a consumable ball with 0 throws left
-- Train              RemoteEvent    C->S (stationId)              one training rep; the only station is "Main"
-- DogAction          RemoteFunction C->S (action: "Keep"|"Sell"|"Display"|"Kennel"|"Auto"|"Lock", dogUid) -> (ok, msg)
--                                   also the server-side settings: ("SetTreatPocketMode", "Always"|"EpicPlus"|"Off"),
--                                   ("SetKeepDupes", "<Rarity>=true|false"); echoed back in PlayerState.Settings
-- ClaimDailyWalk     RemoteFunction C->S () -> (ok, msg)          the HUD's "Claim daily walk" banner
-- ClaimBookReward    RemoteFunction C->S (zoneId, milestone) -> (ok, msg)
-- Broadcast          RemoteEvent    S->C ({Kind, Text, Rarity?, Variant?, Global: boolean})
-- EventState         RemoteEvent    S->All ({Kind: "Squirrel"|"RunawayDog"|"DailyWalk", Active, EndsAt, Data})
--
-- type ThrowResult = { ThrowId, ThrowerUserId, PadIndex (always 1: the one platform), Distance, ZoneId, DogId,
--   Rarity, Variant: string?, Caught, CatchChance, Boosts: {string}, LuckyStreakTriggered, WhistleOwned,
--   WhistleCount, IsTutorial, BallId, BallsLeft: number? (consumable throws left after this one),
--   LaunchPos: Vector3 (ThrowSpot + (0, Game.Throw.LaunchHeight, 0): Y = 44), LandPos: Vector3 (Y = 0, Z = ThrowLine.Z + Distance),
--   FlightTime: number (= Util/BallFlight.ForThrow(LaunchPos, LandPos).Duration), ... }
-- type PlayerState = { Cash, Bones, ThrowPower,
--   Balls: {[ballId]: number}  -- remaining throws of each CONSUMABLE ball (> 0; absent = 0). The Tennis Ball is
--                                 never stored: it is free, unlimited and always available. (Save schema v2;
--                                 v1 saves held {[ballId]: true} and migrate to 0 throws.)
--   EquippedBall,               -- falls back to "Tennis" when the equipped consumable runs out
--   SlotCount, Dogs: { {Uid, DogId, Variant?, BornAt, GrownAt, Displayed} }, Book: {[DogId]: {Variants}},
--   BookRewards, Boosts: {[boostId]: expiresAt}, Whistles, TreatPockets, LuckyStreak, LastDailyWalk, TutorialDone,
--   Computed = PlayerStats.Compute(...) incl. BallCounts, BallId (ball the next throw uses), Prices["Ball:<id>"] }
-- Player attributes set by the server: Cash, Bones, ThrowPower, IncomePerSec, PadIndex (yard index),
--   OnPlatform (boolean), ThrowQueuePos (0 = not queued, 1 = your turn, 2+ = waiting: your place in line).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Events = { "ChargeBegin", "ChargeRelease", "ThrowResult", "CutsceneFinished", "StateUpdate", "EquipBall",
	"Train", "Broadcast", "EventState" }
Remotes.Functions = { "UseWhistle", "RequestState", "ShopPurchase", "DogAction", "ClaimDailyWalk", "ClaimBookReward" }

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init is server-only")
	local folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in Remotes.Events do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = folder
		end
	end
	for _, name in Remotes.Functions do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.Get(name: string): Instance
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name)
end

return Remotes
