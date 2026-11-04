--!strict
-- Every real-time timer in the game, in seconds.
local Timers = {}

Timers.Growth = { -- puppy -> adult
	Common = 5 * 60,
	Uncommon = 15 * 60,
	Rare = 45 * 60,
	Epic = 2 * 3600,
	Legendary = 6 * 3600,
	Mythic = 12 * 3600,
}
Timers.PuppyIncomeFraction = 0.2

-- SERVER cutscene timeout by rarity, computed from Config/Cutscene.luau (never edit numbers here): the longest
-- a real client cutscene can run after the release = Budget (release -> end card at ReferenceFlight)
-- + (Flight.Max - ReferenceFlight) (the longest on-screen flight) + Fallback.HoldMax (a late ThrowResult)
-- + EndCard.AutoClose (the Reveal card closes itself) + Return.Time. ThrowService finishes the throw at
-- release + FlightTime + Timers.Cutscene + CutscenePadding when no CutsceneFinished arrives.
-- Values: Common 20.05, Uncommon 22.0, Rare 23.95, Epic 26.15, Legendary 28.35, Mythic 30.75 (s; Budget = the caught
-- timeline, the longer one, since the catch celebration; was 16.75 .. 28.25).
local CutsceneConfig = require(script.Parent:WaitForChild("Cutscene"))
Timers.Cutscene = {} :: { [string]: number }
for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
	local c = CutsceneConfig
	Timers.Cutscene[rarity] = (c.Budget :: any)[rarity]
		+ (c.Flight.Max - c.Budget.ReferenceFlight)
		+ c.Fallback.HoldMax
		+ (c.EndCard.AutoClose :: any)[rarity]
		+ c.Return.Time
end
Timers.CutscenePadding = 5 -- s on top of the timeout: network latency, streaming stalls, frame hitches
Timers.CommonSkippableAfter = 3 -- Common cutscenes become skippable after the player has seen this many

Timers.SquirrelInterval = 15 * 60
Timers.SquirrelFirstDelay = 15 * 60 -- delay after server start before the first squirrel
Timers.SquirrelDuration = 45
Timers.SquirrelCatchRadius = 7

Timers.RunawaySeconds = 60 -- runaway dog roams the plaza this long
Timers.WhistleWindow = 60 -- whistle usable from the miss until the runaway leaves (>= RunawaySeconds)

Timers.OfflineCapSeconds = 2 * 3600
Timers.OfflineRate = 0.5

Timers.AutosaveInterval = 60
Timers.SessionLockStale = 10 * 60
Timers.DupeKeepWindow = 20 -- seconds after the cutscene a dupe waits for "Keep" before auto-selling

Timers.DayLength = 86400 -- daily walk: one claim per UTC day number (os.time() // DayLength)

return Timers
