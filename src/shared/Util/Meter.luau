--!strict
-- Throw meter maths, shared by server (authority) and client (animation). docs/DESIGN.md §4.
local Config = script.Parent.Parent:WaitForChild("Config")
local Game = require(Config:WaitForChild("Game"))

local Meter = {}

export type Band = "Perfect" | "Good" | "OK" | "Flub"

function Meter.Period(isTutorial: boolean?): number
	if isTutorial then
		return Game.Meter.Period / Game.Tutorial.MeterSpeedMult
	end
	return Game.Meter.Period
end

-- Triangle wave: 0 at t=0, 1 at t=P/2, 0 at t=P.
function Meter.Position(elapsed: number, period: number?): number
	local p = period or Game.Meter.Period
	local phase = (math.max(0, elapsed) % p) / p
	return 1 - math.abs(2 * phase - 1)
end

-- Quality multiplier and band for a meter position.
function Meter.QualityForPosition(pos: number): (number, Band)
	local m = Game.Meter
	if pos >= m.PerfectMin then
		return 1, "Perfect"
	elseif pos >= m.GoodMin then
		local a = (pos - m.GoodMin) / (m.PerfectMin - m.GoodMin)
		return m.GoodQualityMin + (m.GoodQualityMax - m.GoodQualityMin) * a, "Good"
	end
	return m.OkQualityMin + m.OkQualitySpan * (pos / m.GoodMin), "OK"
end

-- Full evaluation from elapsed hold time. Releases before MinChargeSeconds are a flub.
function Meter.Evaluate(elapsed: number, isTutorial: boolean?): (number, number, Band)
	local pos = Meter.Position(elapsed, Meter.Period(isTutorial))
	if elapsed < Game.Throw.MinChargeSeconds then
		return pos, Game.Meter.FlubQuality, "Flub"
	end
	local q, band = Meter.QualityForPosition(pos)
	return pos, q, band
end

return Meter
