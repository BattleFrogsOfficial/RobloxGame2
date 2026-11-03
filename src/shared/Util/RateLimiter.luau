--!strict
-- Token-bucket rate limiter keyed by any value (usually a Player). Keys are weak so players are GC'd.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { Tokens: number, Last: number }

export type RateLimiter = typeof(setmetatable({} :: {
	Rate: number,
	Burst: number,
	Buckets: { [any]: Bucket },
	Rejections: { [any]: number },
}, RateLimiter))

-- rate = tokens refilled per second, burst = bucket size.
function RateLimiter.new(rate: number, burst: number?): RateLimiter
	local self = {
		Rate = rate,
		Burst = burst or math.max(1, rate),
		Buckets = setmetatable({}, { __mode = "k" }) :: any,
		Rejections = setmetatable({}, { __mode = "k" }) :: any,
	}
	return setmetatable(self, RateLimiter)
end

-- Returns true and consumes a token if allowed.
function RateLimiter.Check(self: RateLimiter, key: any, cost: number?): boolean
	local now = os.clock()
	local c = cost or 1
	local b = self.Buckets[key]
	if not b then
		b = { Tokens = self.Burst, Last = now }
		self.Buckets[key] = b
	end
	b.Tokens = math.min(self.Burst, b.Tokens + (now - b.Last) * self.Rate)
	b.Last = now
	if b.Tokens >= c then
		b.Tokens -= c
		return true
	end
	self.Rejections[key] = (self.Rejections[key] or 0) + 1
	return false
end

function RateLimiter.Clear(self: RateLimiter, key: any)
	self.Buckets[key] = nil
	self.Rejections[key] = nil
end

return RateLimiter
