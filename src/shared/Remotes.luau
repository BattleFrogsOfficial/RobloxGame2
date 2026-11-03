--!strict
-- SHARED NETWORK CONTRACT. The server creates every remote under ReplicatedStorage.Remotes at startup
-- (call Remotes.Init() once from the server). Clients call Remotes.Get(name), which WaitForChild's it.
-- All payloads are plain tables. Every client->server remote is rate-limited and validated on the server.
--
-- ChargeBegin        RemoteEvent    C->S ()                       player pressed throw; server timestamps it
-- ChargeRelease      RemoteEvent    C->S ()                       player released; server derives meter position from elapsed time
-- ThrowResult        RemoteEvent    S->All (ThrowResult)          one per throw, sent to every client (thrower + spectators)
-- CutsceneFinished   RemoteEvent    C->S (throwId: string)        thrower's cutscene ended (server also times out on its own)
-- UseWhistle         RemoteFunction C->S (throwId) -> (ok, msg)   only valid for a missed throw, within the whistle window
-- RequestState       RemoteFunction C->S () -> PlayerState        initial snapshot
-- StateUpdate        RemoteEvent    S->C (PlayerState)            full snapshot after any change
-- ShopPurchase       RemoteFunction C->S (itemId) -> (ok, msg)
-- EquipBall          RemoteEvent    C->S (ballId)
-- Train              RemoteEvent    C->S (stationId)              one training rep
-- DogAction          RemoteFunction C->S (action: "Keep"|"Sell"|"Display"|"Kennel", dogUid) -> (ok, msg)
-- ClaimDailyWalk     RemoteFunction C->S () -> (ok, msg)
-- ClaimBookReward    RemoteFunction C->S (zoneId, milestone) -> (ok, msg)
-- Broadcast          RemoteEvent    S->C ({Kind, Text, Rarity?, Variant?, Global: boolean})
-- EventState         RemoteEvent    S->All ({Kind: "Squirrel"|"RunawayDog"|"DailyWalk", Active, EndsAt, Data})
--
-- type ThrowResult = { ThrowId, ThrowerUserId, PadIndex, Distance, ZoneId, DogId, Rarity, Variant: string?,
--   Caught, CatchChance, Boosts: {string}, LuckyStreakTriggered, WhistleOwned, WhistleCount, IsTutorial }
-- type PlayerState = { Cash, Bones, ThrowPower, Balls: {[ballId]: true}, EquippedBall, SlotCount,
--   Dogs: { {Uid, DogId, Variant?, BornAt, GrownAt, Displayed} }, Book: {[DogId]: {Variants}},
--   BookRewards, Boosts: {[boostId]: expiresAt}, Whistles, TreatPockets, LuckyStreak, LastDailyWalk, TutorialDone }
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
