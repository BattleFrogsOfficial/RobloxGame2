--!strict
-- ThrowPower training. Gain per rep = station.Gain x TrainMult(level). TrainMult = Upgrades.MultBase ^ level.
local Training = {}

Training.MaxThrowPower = 2000 -- 2000 x Golden 2.0 = 4000 > field length, so this is never the binding cap

Training.Stations = {
	PullUpBar = {
		Id = "PullUpBar", Name = "Pull-Up Bar", Gain = 0.5, Cooldown = 0.5, UnlockPower = 0,
		CashPerRepMin = 0, CashPerRepPerPower = 0, -- free
	},
	ThrowingMachine = {
		Id = "ThrowingMachine", Name = "Throwing Machine", Gain = 3, Cooldown = 1.0, UnlockPower = 120,
		-- cash per rep = max(CashPerRepMin, ThrowPower * CashPerRepPerPower)
		CashPerRepMin = 5, CashPerRepPerPower = 0.1,
	},
	Sprint = {
		Id = "Sprint", Name = "Sprint Track", Gain = 12, Cooldown = 10, UnlockPower = 0, CashPerRepMin = 0, CashPerRepPerPower = 0,
		-- A "lap": the player must have moved MinLapStuds (server-sampled path length) since their
		-- last Sprint rep and at least MinLapSeconds must have passed.
		MinLapStuds = 220, MinLapSeconds = 10,
	},
}
Training.StationOrder = { "PullUpBar", "ThrowingMachine", "Sprint" }
Training.InteractRange = 14 -- studs from a TrainingStation part for the Train remote / prompt

-- Upgrades bought in the shop (itemId "Training"). Level 0 = no upgrades.
-- Each level does two things: raises the power cap (the gate to the next zone) and multiplies rep gains.
Training.Upgrades = {
	MaxLevel = 29, -- = #Caps - 1
	MultBase = 1.03, -- TrainMult = MultBase ^ level (keeps the "fill to the cap" grind ~20-70 s of pull-ups per level)
	BaseCost = 50, -- level 1 costs $50 (= starter cash: first training purchase in the FTUE)
	CostGrowth = 2.6, -- cost(level) = BaseCost * CostGrowth ^ (level - 1)
	-- Power cap (balance pass, docs/qa/BALANCE.md): training reps cannot raise ThrowPower above
	-- Caps[level + 1]. Without a cap ThrowPower grew linearly with play time (zone distances are linear
	-- too), so free pull-ups alone cleared the whole field within minutes. With the cap, cash (= dogs)
	-- gates each zone and reps are the short grind that fills the cap. Comments: zone reached by a
	-- median (~0.72 quality) throw at that cap with the ball a typical player owns by then.
	Caps = {
		100, 115, 130, 145, -- L0-3   Backyard -> Park at L3 (Tennis)
		165, 185, 205, 230, 255, 280, -- L4-9   Beach at L9 (Rubber)
		320, 370, 420, -- L10-12 Farm at L12 (Flying Disc)
		520, 600, -- L13-14 Forest at L14 (Flying Disc / Glow)
		650, 700, 750, 800, -- L15-18 Snowy Peaks at L18 (Glow)
		900, 1000, -- L19-20 City Rooftops at L20 (Golden)
		1100, 1200, 1320, -- L21-23 Space Station at L23 (Golden)
		1430, 1540, 1650, 1750, -- L24-27 Mythic Meadow at L27 (Golden)
		1880, 2000, -- L28-29 overflow (deeper into Mythic Meadow)
	},
}

function Training.Mult(level: number): number
	return Training.Upgrades.MultBase ^ level
end

-- Highest ThrowPower that training reps can reach at this upgrade level.
function Training.PowerCap(level: number): number
	local caps = Training.Upgrades.Caps
	local i = math.clamp(math.floor(level) + 1, 1, #caps)
	return math.min(Training.MaxThrowPower, caps[i])
end

function Training.UpgradeCost(nextLevel: number): number
	return math.floor(Training.Upgrades.BaseCost * Training.Upgrades.CostGrowth ^ (nextLevel - 1))
end

function Training.RepCost(stationId: string, throwPower: number): number
	local st = (Training.Stations :: any)[stationId]
	if not st or st.CashPerRepPerPower <= 0 then
		return 0
	end
	return math.floor(math.max(st.CashPerRepMin, throwPower * st.CashPerRepPerPower))
end

return Training
