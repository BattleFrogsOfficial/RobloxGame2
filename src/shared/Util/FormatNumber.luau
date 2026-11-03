--!strict
-- Compact number formatting: 999 -> "999", 1234 -> "1.2K", 3.4e6 -> "3.4M", ... up to Dc (1e33).
local FormatNumber = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(s: string): string
	-- "12.0" -> "12"
	local out = string.gsub(s, "%.0$", "")
	return out
end

function FormatNumber.Compact(n: number): string
	if n ~= n then
		return "0" -- NaN guard
	end
	local sign = if n < 0 then "-" else ""
	local a = math.abs(n)
	if a < 1000 then
		if a < 10 and a ~= math.floor(a) then
			return sign .. trim(string.format("%.1f", math.floor(a * 10) / 10))
		end
		return sign .. tostring(math.floor(a))
	end
	local tier = math.floor(math.log10(a) / 3)
	if tier >= #SUFFIXES then
		return sign .. string.format("%.2e", a)
	end
	local scaled = a / (1000 ^ tier)
	-- floor (not round) so 999.96K never displays as "1000K"
	local text
	if scaled < 100 then
		text = trim(string.format("%.1f", math.floor(scaled * 10) / 10))
	else
		text = tostring(math.floor(scaled))
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function FormatNumber.Money(n: number): string
	return "$" .. FormatNumber.Compact(n)
end

function FormatNumber.PerSecond(n: number): string
	return "$" .. FormatNumber.Compact(n) .. "/s"
end

function FormatNumber.Percent(p: number, decimals: number?): string
	local d = decimals or 1
	local s = string.format("%." .. d .. "f", p * 100)
	if d > 0 then
		s = string.gsub(s, "%.?0+$", "")
	end
	return s .. "%"
end

-- 3725 -> "1h 2m", 125 -> "2m 5s", 9 -> "9s"
function FormatNumber.Duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, sec)
	end
	return string.format("%ds", sec)
end

return FormatNumber
