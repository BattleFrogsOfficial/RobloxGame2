--!strict
-- Robux product / gamepass / badge ids. ALL 0 = placeholder (not configured): purchases of a 0 id are
-- refused with "not available yet" and badges with id 0 are recorded in data but not awarded.
-- RandomInfluence = true products are hidden/disabled where PolicyService says paid random items
-- are restricted (ArePaidRandomItemsRestricted).
local Products = {}

export type DevProduct = { Id: number, Name: string, Grant: { [string]: any }, RandomInfluence: boolean? }

Products.DeveloperProducts = {
	StickyBall = { Id = 0, Name = "Sticky Ball (15 min)", Grant = { Boost = "StickyBall" }, RandomInfluence = true },
	LuckyBiscuit = { Id = 0, Name = "Lucky Biscuit (15 min)", Grant = { Boost = "LuckyBiscuit" }, RandomInfluence = true },
	GoldenWhistle1 = { Id = 0, Name = "Golden Whistle x1", Grant = { Whistles = 1 } },
	GoldenWhistle3 = { Id = 0, Name = "Golden Whistle x3", Grant = { Whistles = 3 } },
	TreatPocket3 = { Id = 0, Name = "Treat Pocket x3", Grant = { TreatPockets = 3 }, RandomInfluence = true },
	InstantGrow = { Id = 0, Name = "Instant Grow", Grant = { InstantGrow = true } },
	CashSmall = { Id = 0, Name = "Cash Pack (30 min)", Grant = { CashIncomeSeconds = 1800, MinCash = 1000 } },
	CashLarge = { Id = 0, Name = "Cash Pack (4 h)", Grant = { CashIncomeSeconds = 4 * 3600, MinCash = 10000 } },
	ServerLuck = { Id = 0, Name = "Server Luck (15 min)", Grant = { ServerLuck = 0.25, Duration = 15 * 60 },
		RandomInfluence = true },
} :: { [string]: DevProduct }

-- Robux packs of consumable balls (the purple button on each Shop ball card). One purchase grants `Throws` throws
-- of that ball (PlayerState.Balls[id] += Throws, capped at Balls.MaxOwned). ProductId 0 = not configured yet: the
-- client shows "Not available yet" instead of prompting. The server grants on ProcessReceipt (ShopService).
export type BallProduct = { ProductId: number, Robux: number, Throws: number }

Products.Balls = {
	Rubber = { ProductId = 0, Robux = 5, Throws = 10 }, -- 0.5 R$ a throw: the cheap first Robux taste ($500 of cash)
	FlyingDisc = { ProductId = 0, Robux = 15, Throws = 10 }, -- 1.5 R$ a throw ($5K of cash at the cash price)
	Glow = { ProductId = 0, Robux = 35, Throws = 10 }, -- 3.5 R$ a throw ($100K of cash)
	Golden = { ProductId = 0, Robux = 75, Throws = 10 }, -- 7.5 R$ a throw ($2.5M of cash): the late-game skip
} :: { [string]: BallProduct }

-- The ball key a Products.Balls ProductId belongs to (receipt handling), or nil.
function Products.FindBallKey(productId: number): string?
	if productId == 0 then
		return nil
	end
	for key, p in Products.Balls do
		if p.ProductId == productId then
			return key
		end
	end
	return nil
end

export type GamePass = { Id: number, Name: string, RandomInfluence: boolean?, IncomeMult: number?, Slots: number?,
	GrowthSpeed: number?, BonesMult: number?, Luck: number? }

Products.GamePasses = {
	DoubleCash = { Id = 0, Name = "2x Cash", IncomeMult = 2 },
	ExtraSlots = { Id = 0, Name = "Extra Yard Slots", Slots = 10 },
	FastGrowth = { Id = 0, Name = "Fast Growth", GrowthSpeed = 2 },
	VIP = { Id = 0, Name = "VIP", BonesMult = 1.1 },
	LuckyPaw = { Id = 0, Name = "Lucky Paw", Luck = 0.25, RandomInfluence = true },
} :: { [string]: GamePass }

-- Variant completion badges: one per zone per variant (catch every non-Common of the zone in that variant).
Products.Badges = {
	Variant = {
		Backyard = { Gold = 0, Shadow = 0, Rainbow = 0 },
		Park = { Gold = 0, Shadow = 0, Rainbow = 0 },
		Beach = { Gold = 0, Shadow = 0, Rainbow = 0 },
		Farm = { Gold = 0, Shadow = 0, Rainbow = 0 },
		Forest = { Gold = 0, Shadow = 0, Rainbow = 0 },
		SnowyPeaks = { Gold = 0, Shadow = 0, Rainbow = 0 },
		CityRooftops = { Gold = 0, Shadow = 0, Rainbow = 0 },
		SpaceStation = { Gold = 0, Shadow = 0, Rainbow = 0 },
		MythicMeadow = { Gold = 0, Shadow = 0, Rainbow = 0 },
	} :: { [string]: { [string]: number } },
	AllRainbows = 0,
}

function Products.FindProductKey(productId: number): string?
	if productId == 0 then
		return nil
	end
	for key, p in Products.DeveloperProducts do
		if p.Id == productId then
			return key
		end
	end
	return nil
end

function Products.FindPassKey(passId: number): string?
	if passId == 0 then
		return nil
	end
	for key, p in Products.GamePasses do
		if p.Id == passId then
			return key
		end
	end
	return nil
end

return Products
