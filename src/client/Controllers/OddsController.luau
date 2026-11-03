--!strict
-- Odds panel: every number is pulled live from config + the player's computed state, so what is posted
-- is exactly what the server rolls with (Util/Odds is shared by RollService and this panel).
--   tier odds (base and yours), catch chances (base and yours), variant chances, current luck/catch
--   sources, Lucky Streak rule + progress, zone distance bands and per-tier dog counts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local Game = require(Config:WaitForChild("Game"))
local Odds = require(Util:WaitForChild("Odds"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Windows = require(UI:WaitForChild("Windows"))
local Window = require(UI:WaitForChild("Components"):WaitForChild("Window"))
local RowList = require(UI:WaitForChild("Components"):WaitForChild("RowList"))

local StateController = require(script.Parent:WaitForChild("StateController"))

local OddsController = {}

local list: RowList.List? = nil

local function pct(p: number): string
	if p > 0 and p < 0.001 then
		return string.format("%.3f%%", p * 100)
	elseif p < 0.01 then
		return string.format("%.2f%%", p * 100)
	end
	return FormatNumber.Percent(p, 1)
end

local function render()
	local l = list
	if not l then
		return
	end
	l.Clear()
	local state = StateController.Get()
	local c = StateController.Computed()
	local luck = tonumber(c.Luck) or 0
	local yourOdds = c.TierOdds or Odds.TierOdds(luck)
	local base = Odds.TierOdds(0)
	local catchBonus = tonumber(c.CatchBonus) or 0
	local armed = c.LuckyStreakArmed == true

	l.Header("Rarity odds (where the ball lands sets the zone)")
	l.Text(("Luck +%d%% raises every non-Common tier (Common never drops below %d%%). Within a tier every dog of the zone is equally likely.")
		:format(math.floor(luck * 100 + 0.5), math.floor(Game.Luck.MinCommonOdds * 100 + 0.5)), 34)
	for _, tier in Rarities.Order do
		local t = (Rarities.Tiers :: any)[tier]
		local legendaryPlus = Odds.IsLegendaryPlus(tier)
		local yourCatch = if armed and legendaryPlus then 1 else Odds.CatchChance(tier, catchBonus)
		l.Row({
			Title = ('<font color="#%s">%s</font>  %s  <font color="#B9B4D7">(base %s)</font>'):format(t.Color:ToHex(), tier,
				pct(yourOdds[tier] or 0), pct(base[tier] or 0)),
			Subtitle = ("Catch %s (base %s) · income x%s%s"):format(pct(yourCatch), pct(t.Catch), FormatNumber.Compact(t.IncomeMult),
				if armed and legendaryPlus then " · LUCKY STREAK: guaranteed" else ""),
			RichText = true,
			Color = t.Color,
			Height = 50,
		})
	end

	l.Header("Variant forms (non-Common dogs only)")
	local vc = Odds.VariantChances()
	for _, v in Rarities.VariantOrder do
		local def = (Rarities.Variants :: any)[v]
		l.Row({
			Title = ("%s  %s"):format(v, pct(vc[v] or def.Chance)),
			Subtitle = ("Income x%s · shown as a badge"):format(FormatNumber.Compact(def.IncomeMult)),
			Color = if v == "Gold" then Color3.fromRGB(255, 205, 60) elseif v == "Shadow" then Color3.fromRGB(110, 60, 170)
				else Color3.fromRGB(255, 120, 200),
			Height = 46,
		})
	end

	l.Header("Your boosts")
	local sources = {}
	for _, s in (c.LuckSources or {}) do
		table.insert(sources, ("Luck +%d%% from %s"):format(math.floor(s.Amount * 100 + 0.5), s.Name))
	end
	for _, s in (c.CatchSources or {}) do
		table.insert(sources, ("Catch +%d%% from %s"):format(math.floor(s.Amount * 100 + 0.5), s.Name))
	end
	if #sources == 0 then
		table.insert(sources, "No active boosts. Better balls add luck; Sticky Ball adds catch chance.")
	end
	l.Text(table.concat(sources, "\n"), 18 * #sources + 6)

	l.Header("Lucky Streak")
	local streak = if state then (state.LuckyStreak or 0) else 0
	l.Text(("Miss %d Legendary+ dogs in a row and your NEXT Legendary+ is a guaranteed catch. Progress: %d/%d%s"):format(
		Rarities.LuckyStreakMisses, math.min(streak, Rarities.LuckyStreakMisses), Rarities.LuckyStreakMisses,
		if armed then " (ARMED!)" else ""), 34)

	l.Header("Zones")
	for _, z in Zones do
		local counts = {}
		for _, tier in Rarities.Order do
			local n = #DogCatalog.ZoneTierList(z.Id, tier)
			if n > 0 then
				table.insert(counts, ("%d %s"):format(n, string.sub(tier, 1, 1)))
			end
		end
		l.Row({
			Title = ("%s  %d-%d studs"):format(z.Name, z.MinDistance, z.MaxDistance),
			Subtitle = ("Base %s · dogs: %s"):format(FormatNumber.PerSecond(z.BaseIncome), table.concat(counts, " ")),
			Color = z.Theme.Ground,
			Height = 46,
		})
	end
end

function OddsController.Start()
	Windows.Register("Odds", function(_host)
		local w = Window.new("Odds & Rules", Color3.fromRGB(240, 130, 70), Windows.Close)
		list = RowList.new(w.Body)
		return {
			Frame = w.Frame,
			OnOpen = function(_arg: any)
				render()
			end,
		}
	end)
	StateController.Changed:Connect(function()
		if Windows.IsOpen("Odds") then
			render()
		end
	end)
end

return OddsController
