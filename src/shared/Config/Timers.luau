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

-- Placeholder cutscene lengths by rarity (the Cutscene module may read these); the server waits
-- this long + CutscenePadding for CutsceneFinished before finishing the throw on its own.
Timers.Cutscene = { Common = 2, Uncommon = 3, Rare = 5, Epic = 8, Legendary = 11, Mythic = 15 }
Timers.CutscenePadding = 8
Timers.CommonSkippableAfter = 3 -- Common cutscenes become skippable after the player has seen this many

Timers.SquirrelInterval = 15 * 60
Timers.SquirrelFirstDelay = 15 * 60 -- delay after server start before the first squirrel
Timers.SquirrelDuration = 45
Timers.SquirrelCatchRadius = 7

Timers.RunawaySeconds = 60 -- runaway dog roams the plaza this long
Timers.WhistleWindow = 60 -- whistle usable from the miss until the runaway leaves (>= RunawaySeconds)

Timers.OfflineCapSeconds = 2 * 3600
Timers.OfflineRate = 1.0

Timers.AutosaveInterval = 60
Timers.SessionLockStale = 10 * 60
Timers.DupeKeepWindow = 20 -- seconds after the cutscene a dupe waits for "Keep" before auto-selling

Timers.DayLength = 86400 -- daily walk: one claim per UTC day number (os.time() // DayLength)

return Timers
