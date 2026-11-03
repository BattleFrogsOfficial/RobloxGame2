--!strict
-- Seedable RNG wrapper around Roblox Random. Same seed -> same sequence (used by RollService tests).
local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { _r: Random }, Rng))

function Rng.new(seed: number?): Rng
	local r = if seed ~= nil then Random.new(seed) else Random.new()
	return setmetatable({ _r = r }, Rng)
end

-- Uniform float in [0, 1).
function Rng.Float(self: Rng): number
	return self._r:NextNumber()
end

-- Uniform float in [min, max).
function Rng.Range(self: Rng, min: number, max: number): number
	return self._r:NextNumber(min, max)
end

-- Uniform integer in [min, max] inclusive.
function Rng.Int(self: Rng, min: number, max: number): number
	return self._r:NextInteger(min, max)
end

function Rng.Chance(self: Rng, p: number): boolean
	return self._r:NextNumber() < p
end

-- Pick a uniformly random element of a non-empty array.
function Rng.Pick<T>(self: Rng, list: { T }): T
	assert(#list > 0, "Rng:Pick on empty list")
	return list[self._r:NextInteger(1, #list)]
end

-- Weighted pick. `order` fixes iteration order so results are deterministic for a given seed.
function Rng.Weighted(self: Rng, order: { string }, weights: { [string]: number }): string?
	local total = 0
	for _, key in order do
		total += math.max(0, weights[key] or 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = self._r:NextNumber() * total
	local last: string? = nil
	for _, key in order do
		local w = math.max(0, weights[key] or 0)
		if w > 0 then
			last = key
			if roll < w then
				return key
			end
			roll -= w
		end
	end
	return last -- floating-point edge
end

return Rng
