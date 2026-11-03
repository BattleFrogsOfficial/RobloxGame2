--!strict
-- ThrowPower training. Gain per rep = station.Gain x TrainMult(level). TrainMult = Upgrades.MultBase ^ level.
local Training = {}

Training.MaxThrowPower = 2000 -- 2000 x Golden 2.0 = 4000 > field length, so this is never the binding cap

Training.Stations = {
	PullUpBar = {
		Id = "PullUpBar", Name = "Pull-Up Bar", Gain = 1, Cooldown = 0.5, UnlockPower = 0,
		CashPerRepMin = 0, CashPerRepPerPower = 0, -- free
	},
	ThrowingMachine = {
		Id = "ThrowingMachine", Name = "Throwing Machine", Gain = 4, Cooldown = 1.0, UnlockPower = 120,
		-- cash per rep = max(CashPerRepMin, ThrowPower * CashPerRepPerPower)
		CashPerRepMin = 5, CashPerRepPerPower = 0.25,
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
Training.Upgrades = {
	MaxLevel = 40,
	MultBase = 1.5, -- TrainMult = 1.5 ^ level
	BaseCost = 50, -- level 1 costs $50 (= starter cash: first training purchase in the FTUE)
	CostGrowth = 3.2, -- cost(level) = BaseCost * CostGrowth ^ (level - 1)
}

function Training.Mult(level: number): number
	return Training.Upgrades.MultBase ^ level
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
