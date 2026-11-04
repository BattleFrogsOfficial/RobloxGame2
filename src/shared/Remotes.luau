--!strict
-- SHARED NETWORK CONTRACT. The server creates every remote under ReplicatedStorage.Remotes at startup
-- (call Remotes.Init() once from the server). Clients call Remotes.Get(name), which WaitForChild's it.
-- All payloads are plain tables. Every client->server remote is rate-limited and validated on the server.
--
-- ChargeBegin        RemoteEvent    C->S ()                       ONE TAP throwing, no turns. Fired the moment the meter bar appears
--                                   (entering the throw zone, or when your finished throw unlocks while you are still in it): the
--                                   server timestamps the sweep start. Fired again while charging to RESTART the sweep (the client
--                                   restarts on a period boundary before MaxChargeSeconds runs out): the timestamp resets, accepted
--                                   once Game.Throw.MinRestartSeconds have passed since the last (re)start. Requires InThrowZone,
--                                   no throw of yours in flight, and MinSecondsBetweenThrows since your last release.
-- ChargeRelease      RemoteEvent    C->S ()                       the tap: server derives the meter position from now - (re)start.
--                                   Requires InThrowZone (outside it the charge is dropped). No release within
--                                   Game.Throw.MaxChargeSeconds of the (re)start: the charge is CANCELLED silently (no auto-throw)
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
-- DevCommand         RemoteFunction C->S (command, arg?) -> (ok, msg)   dev tools (DevService; refused unless
--                                   Game.DevTools allows the player: Studio, or a listed UserId). Commands:
--                                   "AddPower" (100|1000|10000), "PowerForZone" (zoneId), "MaxPower", "ResetPower",
--                                   "AddCash", "GiveBalls"; each pushes a StateUpdate
-- Broadcast          RemoteEvent    S->C ({Kind, Text, Rarity?, Variant?, Global: boolean})
-- EventState         RemoteEvent    S->All ({Kind: "Squirrel"|"RunawayDog"|"DailyWalk", Active, EndsAt, Data})
--
-- type ThrowResult = { ThrowId, ThrowerUserId, PadIndex (always 1: the one throw zone), Distance, ZoneId, DogId,
--   Rarity, Variant: string?, Caught, CatchChance, Boosts: {string}, LuckyStreakTriggered, TreatPocketUsed,
--   WhistleOwned, WhistleCount, IsTutorial, BallId, BallsLeft: number? (consumable throws left after this one),
--   LaunchPos: Vector3 (the cliff edge in front of the thrower: (root X clamped into Layout.ThrowZone,
--              Layout.HubY + Game.Throw.LaunchHeight = 44, Layout.ThrowLine.Z)),
--   LandPos: Vector3 (on the field: Y = Layout.GroundY = 0, Z = ThrowLine.Z + Distance),
--   FlightTime: number (= Util/BallFlight.ForThrow(LaunchPos, LandPos).Duration: includes the 44-stud drop), ... }
--   Fired to all clients the moment the throw is released, before any toast, StateUpdate or world display.
-- type PlayerState = { Cash, Bones, ThrowPower,
--   Balls: {[ballId]: number}  -- remaining throws of each CONSUMABLE ball (> 0; absent = 0). The Tennis Ball is
--                                 never stored: it is free, unlimited and always available. (Save schema v2;
--                                 v1 saves held {[ballId]: true} and migrate to 0 throws.)
--   EquippedBall,               -- falls back to "Tennis" when the equipped consumable runs out
--   SlotCount, Dogs: { {Uid, DogId, Variant?, BornAt, GrownAt, Displayed} }, Book: {[DogId]: {Variants}},
--   BookRewards, Boosts: {[boostId]: expiresAt}, Whistles, TreatPockets, LuckyStreak, LastDailyWalk, TutorialDone,
--   Computed = PlayerStats.Compute(...) incl. BallCounts, BallId (ball the next throw uses), Prices["Ball:<id>"] }
-- Player attributes set by the server: Cash, Bones, ThrowPower, IncomePerSec, PadIndex (yard index),
--   DevTools (true for players the dev tools allow; absent otherwise),
--   InThrowZone (boolean, ~4x/s: HumanoidRootPart XZ inside Layout.ThrowZone + Game.ThrowZone.EdgeMargin and
--     Y >= HubY - Game.ThrowZone.YTolerance; everyone in the zone can throw at once),
--   DEPRECATED (kept for one release, remove after): OnPlatform (= InThrowZone), ThrowQueuePos (1 in the zone, 0 otherwise;
--     there is no queue any more).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Events = { "ChargeBegin", "ChargeRelease", "ThrowResult", "CutsceneFinished", "StateUpdate", "EquipBall",
	"Train", "Broadcast", "EventState" }
Remotes.Functions = { "UseWhistle", "RequestState", "ShopPurchase", "DogAction", "ClaimDailyWalk", "ClaimBookReward",
	"DevCommand" }

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
