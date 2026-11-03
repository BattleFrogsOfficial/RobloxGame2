--!strict
-- In-game (cash / Bones) shop items, prices and effects. Robux ids live in Products.luau.
-- Prices of timed boosts and consumables scale with income so they stay meaningful:
--   price = max(BaseCost, ceil(IncomePerSec * IncomeSeconds))
local Shop = {}

-- ShopPurchase itemIds handled by ShopService (strings, validated server-side):
--   "Ball:<BallId>"         buy Uses more throws of a consumable ball (repeatable) and equip it; "Ball:Tennis" equips
--   "Training"              next training upgrade level
--   "Slots"                 +Slots.Step yard slots
--   "Boost:<BoostId>"       timed boost (cash)
--   "Item:<ItemId>"         consumable (cash)
--   "Cosmetic:<CosmeticId>" cosmetic (Bones)
--   "Product:<ProductKey>[:<dogUid>]"  Robux developer product prompt (InstantGrow takes a dog uid)
--   "Pass:<PassKey>"        Robux gamepass prompt

Shop.Slots = {
	Start = 10,
	Step = 5,
	Max = 100, -- purchasable cap (gamepass slots come on top)
	BaseCost = 250,
	CostGrowth = 4.5, -- cost = BaseCost * CostGrowth ^ purchasesSoFar
}

function Shop.SlotCost(currentSlotCount: number): number
	local bought = math.max(0, (currentSlotCount - Shop.Slots.Start) // Shop.Slots.Step)
	return math.floor(Shop.Slots.BaseCost * Shop.Slots.CostGrowth ^ bought)
end

export type Boost = { Id: string, Name: string, Kind: "Luck" | "Catch", Amount: number, Duration: number,
	BaseCost: number, IncomeSeconds: number }

Shop.Boosts = {
	StickyBall = { Id = "StickyBall", Name = "Sticky Ball", Kind = "Catch", Amount = 0.10, Duration = 15 * 60,
		BaseCost = 150, IncomeSeconds = 180 },
	LuckyBiscuit = { Id = "LuckyBiscuit", Name = "Lucky Biscuit", Kind = "Luck", Amount = 0.5, Duration = 15 * 60,
		BaseCost = 200, IncomeSeconds = 240 },
} :: { [string]: Boost }
Shop.BoostOrder = { "StickyBall", "LuckyBiscuit" }

Shop.Items = {
	GoldenWhistle = { Id = "GoldenWhistle", Name = "Golden Whistle", Field = "Whistles", Amount = 1,
		BaseCost = 500, IncomeSeconds = 300, Max = 99 },
	TreatPocket = { Id = "TreatPocket", Name = "Treat Pocket", Field = "TreatPockets", Amount = 1,
		BaseCost = 300, IncomeSeconds = 120, Max = 99 },
}
Shop.ItemOrder = { "GoldenWhistle", "TreatPocket" }

function Shop.DynamicPrice(baseCost: number, incomeSeconds: number, incomePerSec: number): number
	return math.max(baseCost, math.ceil(incomePerSec * incomeSeconds))
end

-- Dupes auto-sell (and manual DogAction "Sell" pays) this many seconds of the dog's ADULT income.
Shop.SellIncomeSeconds = 120
-- Default per-rarity "keep dupes" setting (true = never auto-sell dupes of that rarity).
Shop.DefaultKeepDupes = { Common = false, Uncommon = false, Rare = false, Epic = false, Legendary = true, Mythic = true }
-- Treat Pocket auto-use modes (Settings.TreatPocketMode).
Shop.TreatPocketModes = { "Always", "EpicPlus", "Off" }
Shop.DefaultTreatPocketMode = "EpicPlus" -- balance pass: "Always" burned pockets on Commons

-- Daily walk (ClaimDailyWalk): cash = max(MinCash, IncomePerSec * IncomeSeconds) + Bones + premium throws.
Shop.DailyWalk = { IncomeSeconds = 600, MinCash = 100, Bones = 10, PremiumThrows = 1 }
-- A premium throw counts as a Golden-ball luck shift plus Sticky Ball for that one throw.
Shop.PremiumThrow = { LuckAsBall = "Golden", CatchBonus = 0.10 }

-- Squirrel event Bones.
Shop.Squirrel = { WinnerBones = 25, BonesPerPlayer = 5, ConsolationBones = 3 }

-- Kennel Book milestone rewards (percent of the zone's base dogs).
Shop.BookMilestones = { 25, 50, 75, 100 }
Shop.BookRewards = {
	[25] = { Kind = "Cash", ZoneIncomeSeconds = 6000, Bones = 10 }, -- 100 min of one zone Common ($/s = BaseIncome)
	[50] = { Kind = "Luck", Luck = 0.02, Bones = 20 }, -- permanent, stacks across zones
	[75] = { Kind = "Trophy", Bones = 30 }, -- yard trophy statue at TrophySpot
	[100] = { Kind = "Title", Bones = 50 }, -- "<Zone Name> Legend"
} :: { [number]: { [string]: any } }

-- Cosmetics are Bones-only and never give power. (Equip/visuals are a client TODO.)
Shop.Cosmetics = {
	RedCollar = { Id = "RedCollar", Name = "Red Collar", Slot = "Collar", Bones = 25 },
	StarCollar = { Id = "StarCollar", Name = "Star Collar", Slot = "Collar", Bones = 150 },
	PartyHat = { Id = "PartyHat", Name = "Party Hat", Slot = "Hat", Bones = 75 },
	PirateHat = { Id = "PirateHat", Name = "Tiny Pirate Hat", Slot = "Hat", Bones = 300 },
	Flowerbed = { Id = "Flowerbed", Name = "Flowerbed", Slot = "YardDecor", Bones = 200 },
	DogHouseDeluxe = { Id = "DogHouseDeluxe", Name = "Deluxe Dog House", Slot = "YardDecor", Bones = 600 },
	PawTrail = { Id = "PawTrail", Name = "Paw-Print Pad Trail", Slot = "PadTrail", Bones = 400 },
}
Shop.CosmeticOrder = { "RedCollar", "PartyHat", "StarCollar", "Flowerbed", "PirateHat", "PawTrail", "DogHouseDeluxe" }

return Shop
