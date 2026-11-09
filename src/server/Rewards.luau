-- Playtime gifts (reset each session), the daily login streak, and Index
-- (collection book) rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Data = require(script.Parent.Data)
local Pens = require(script.Parent.Pens)
local Shop = require(script.Parent.Shop)

local Rewards = {}

local GREEN = Color3.fromRGB(120, 255, 120)

local function grant(player: Player, reward): string
	if reward.kind == "cash" then
		local amount = math.max(reward.cash, math.floor(Data.income(player) * (reward.incomeSeconds or 0)))
		Data.addCash(player, amount)
		return Format.cash(amount)
	elseif reward.kind == "egg" then
		Pens.addEgg(player, reward.egg, "Normal")
		return Config.EggById[reward.egg].name
	elseif reward.kind == "animal" then
		Pens.addAnimal(player, reward.animal, "Normal")
		return reward.animal
	end
	return "?"
end

function Rewards.claimPlaytime(player: Player, i: number): (boolean, string?)
	local s = Data.session(player)
	local reward = Config.Playtime[i]
	if not s or not reward then
		return false
	end
	if s.playtimeClaimed[tostring(i)] then
		return false, "Already claimed."
	end
	local elapsed = workspace:GetServerTimeNow() - s.sessionStart
	if elapsed < reward.minutes * 60 - 1 and not s.playtimeSkipped then
		return false, "Not ready yet!"
	end
	s.playtimeClaimed[tostring(i)] = true
	local what = grant(player, reward)
	Data.markDirty(player)
	return true, "Claimed " .. what .. "!"
end

function Rewards.skipPlaytime(player: Player)
	local s = Data.session(player)
	if not s then
		return
	end
	s.playtimeSkipped = true
	for i in Config.Playtime do
		if not s.playtimeClaimed[tostring(i)] then
			Rewards.claimPlaytime(player, i)
		end
	end
end

function Rewards.claimDaily(player: Player): (boolean, string?)
	local d = Data.get(player)
	if not d then
		return false
	end
	local today = math.floor(os.time() / 86400)
	if d.daily.last >= today then
		return false, "Come back tomorrow!"
	end
	if d.daily.last == today - 1 then
		d.daily.streak += 1
	else
		d.daily.streak = 1
	end
	d.daily.last = today
	local day = (d.daily.streak - 1) % #Config.Daily + 1
	local what = grant(player, Config.Daily[day])
	Data.markDirty(player)
	return true, "Day " .. d.daily.streak .. " reward: " .. what .. "!"
end

function Rewards.claimIndex(player: Player, animalId: string): (boolean, string?)
	local d = Data.get(player)
	local a = Config.AnimalById[animalId]
	if not d or not a or d.index[animalId] ~= 1 then
		return false
	end
	d.index[animalId] = 2
	local cash = a.income * Config.IndexRewardSeconds
	Data.addCash(player, cash)
	return true, "Index reward: " .. Format.cash(cash) .. "!"
end

function Rewards.init()
	Shop.callbacks.skipPlaytime = Rewards.skipPlaytime
	Data.Loaded.Event:Connect(function(player)
		local d = Data.get(player)
		if d and d.daily.last < math.floor(os.time() / 86400) then
			task.delay(6, function()
				if player.Parent then
					Data.notify(player, "Your daily reward is ready! 📅", GREEN)
				end
			end)
		end
	end)
end

return Rewards
