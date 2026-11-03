--!strict
-- Permanent ball tiers. Distance = ThrowPower x RangeMult x Quality. Luck adds to the tier roll.
export type Ball = { Id: string, Name: string, Order: number, RangeMult: number, Luck: number, Price: number, Color: Color3 }

local Balls = {}

Balls.Order = { "Tennis", "Rubber", "FlyingDisc", "Glow", "Golden" }

Balls.ById = {
	Tennis = { Id = "Tennis", Name = "Tennis Ball", Order = 1, RangeMult = 1.00, Luck = 0.00, Price = 0,
		Color = Color3.fromRGB(210, 230, 60) },
	Rubber = { Id = "Rubber", Name = "Rubber Ball", Order = 2, RangeMult = 1.25, Luck = 0.10, Price = 500,
		Color = Color3.fromRGB(230, 70, 70) },
	FlyingDisc = { Id = "FlyingDisc", Name = "Flying Disc", Order = 3, RangeMult = 1.50, Luck = 0.20, Price = 50_000,
		Color = Color3.fromRGB(60, 140, 240) },
	Glow = { Id = "Glow", Name = "Glow Ball", Order = 4, RangeMult = 1.75, Luck = 0.35, Price = 5_000_000,
		Color = Color3.fromRGB(120, 255, 200) },
	Golden = { Id = "Golden", Name = "Golden Ball", Order = 5, RangeMult = 2.00, Luck = 0.50, Price = 3_000_000_000,
		Color = Color3.fromRGB(255, 205, 60) },
} :: { [string]: Ball }

Balls.Default = "Tennis"

return Balls
