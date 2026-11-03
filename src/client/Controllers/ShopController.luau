--!strict
-- Shop window (tabs: Balls, Training, Boosts, Yard, Cosmetics, Robux) + ShopStand proximity prompts in
-- the plaza. Every purchase goes through ShopPurchase(itemId) and is validated by the server. Protection
-- items are bought here BEFOREHAND; nothing in the loss flow ever opens a Robux prompt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Balls = require(Config:WaitForChild("Balls"))
local Shop = require(Config:WaitForChild("Shop"))
local Training = require(Config:WaitForChild("Training"))
local Products = require(Config:WaitForChild("Products"))
local Timers = require(Config:WaitForChild("Timers"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Windows = require(UI:WaitForChild("Windows"))
local Window = require(UI:WaitForChild("Components"):WaitForChild("Window"))
local Tabs = require(UI:WaitForChild("Components"):WaitForChild("Tabs"))
local RowList = require(UI:WaitForChild("Components"):WaitForChild("RowList"))
local Create = require(UI:WaitForChild("Components"):WaitForChild("Create"))

local StateController = require(script.Parent:WaitForChild("StateController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local ShopController = {}

local TAB_NAMES = { "Balls", "Training", "Boosts", "Yard", "Cosmetics", "Robux" }
local STAND_TO_TAB = { Balls = "Balls", Boosts = "Boosts", Yard = "Yard", Cosmetics = "Cosmetics" }

local player = Players.LocalPlayer
local currentTab = "Balls"
local list: RowList.List? = nil
local busy = false

function ShopController.Purchase(itemId: string)
	if busy then
		return
	end
	busy = true
	local remote = Remotes.Get("ShopPurchase") :: RemoteFunction
	local ok, success, msg = pcall(function()
		return remote:InvokeServer(itemId)
	end)
	busy = false
	if not ok then
		NotificationController.Toast("Shop is busy, try again", "Error")
	elseif msg ~= "Prompted" then
		NotificationController.Toast(tostring(msg or (if success then "Done!" else "Can't buy that")), if success then "Purchase" else "Error")
	end
end

local function priceButton(price: number, cash: number): (string, Color3)
	return FormatNumber.Money(price), if cash >= price then Theme.Color.Accent else Theme.Color.PanelInset
end

local function render()
	local l = list
	if not l then
		return
	end
	l.Clear()
	local s = StateController.Get()
	if not s then
		l.Text("Loading...")
		return
	end
	local c = StateController.Computed()
	local prices = c.Prices or {}
	local cash = StateController.Live("Cash")

	if currentTab == "Balls" then
		l.Text("Balls are permanent. Better balls fly further and add luck to every throw.", 34)
		for _, id in Balls.Order do
			local b = Balls.ById[id]
			local owned = s.Balls and s.Balls[id] == true
			local equipped = s.EquippedBall == id
			local text, color
			if equipped then
				text, color = "Equipped", Theme.Color.Good
			elseif owned then
				text, color = "Equip", Theme.Color.Info
			else
				text, color = priceButton(b.Price, cash)
			end
			l.Row({
				Title = b.Name,
				Subtitle = ("Range x%.2f · Luck +%d%%"):format(b.RangeMult, math.floor(b.Luck * 100 + 0.5)),
				Color = b.Color,
				ButtonText = text,
				ButtonColor = color,
				OnClick = function()
					if equipped then
						return
					elseif owned then
						local equip = Remotes.Get("EquipBall") :: RemoteEvent
						equip:FireServer(id)
					else
						ShopController.Purchase("Ball:" .. id)
					end
				end,
			})
		end
	elseif currentTab == "Training" then
		local level = s.TrainingLevel or 0
		l.Text(("Train at the plaza stations to raise Throw Power (now %s / cap %s). Upgrades raise the cap and multiply every rep."):format(
			FormatNumber.Compact(s.ThrowPower or 0), FormatNumber.Compact(Training.PowerCap(level))), 34)
		if level < Training.Upgrades.MaxLevel then
			local cost = prices.Training or Training.UpgradeCost(level + 1)
			local text, color = priceButton(cost, cash)
			l.Row({
				Title = ("Training Upgrade Lv %d"):format(level + 1),
				Subtitle = ("Power cap %s -> %s · gains x%s -> x%s per rep"):format(
					FormatNumber.Compact(Training.PowerCap(level)), FormatNumber.Compact(Training.PowerCap(level + 1)),
					FormatNumber.Compact(Training.Mult(level)), FormatNumber.Compact(Training.Mult(level + 1))),
				Color = Theme.Color.Accent,
				SwatchText = "UP",
				ButtonText = text,
				ButtonColor = if s.TutorialDone ~= true then Theme.Color.Good else color,
				OnClick = function()
					ShopController.Purchase("Training")
				end,
			})
		else
			l.Row({ Title = "Training maxed!", Subtitle = ("Gains x%s per rep"):format(FormatNumber.Compact(Training.Mult(level))),
				Color = Theme.Color.Good })
		end
		for _, id in Training.StationOrder do
			local st = (Training.Stations :: any)[id]
			local cost = Training.RepCost(id, s.ThrowPower or 0)
			l.Row({
				Title = st.Name,
				Subtitle = ("+%s power/rep · %s%s"):format(FormatNumber.Compact(st.Gain * (c.TrainMult or 1)),
					if cost > 0 then FormatNumber.Money(cost) .. "/rep" else "free",
					if (s.ThrowPower or 0) < st.UnlockPower then (" · unlocks at %d power"):format(st.UnlockPower) else ""),
				Color = Theme.Color.Info,
				SwatchText = "TR",
			})
		end
	elseif currentTab == "Boosts" then
		local walkAvailable = s.LastDailyWalk ~= (StateController.ServerNow() // Timers.DayLength)
		l.Row({
			Title = "Daily Walk",
			Subtitle = ("Once a day: cash + %d Bones + %d free premium throw"):format(Shop.DailyWalk.Bones, Shop.DailyWalk.PremiumThrows),
			Color = Theme.Color.Good,
			SwatchText = "W",
			ButtonText = if walkAvailable then "Claim" else "Tomorrow",
			ButtonColor = if walkAvailable then Theme.Color.Good else Theme.Color.PanelInset,
			OnClick = function()
				local remote = Remotes.Get("ClaimDailyWalk") :: RemoteFunction
				local ok, success, msg = pcall(function()
					return remote:InvokeServer()
				end)
				NotificationController.Toast(if ok then tostring(msg) else "Try again", if ok and success then "Purchase" else "Error")
			end,
		})
		l.Header("Timed boosts")
		local now = StateController.ServerNow()
		for _, id in Shop.BoostOrder do
			local b = Shop.Boosts[id]
			local price = prices["Boost:" .. id] or b.BaseCost
			local exp = s.Boosts and s.Boosts[id]
			local active = type(exp) == "number" and exp > now
			local text, color = priceButton(price, cash)
			l.Row({
				Title = b.Name .. (if active then ("  (%s left)"):format(FormatNumber.Duration(exp - now)) else ""),
				Subtitle = ("%s +%d%% for %s%s"):format(if b.Kind == "Catch" then "Catch chance" else "Luck (breed roll)",
					math.floor(b.Amount * 100 + 0.5), FormatNumber.Duration(b.Duration), if active then " · buying adds time" else ""),
				Color = if b.Kind == "Catch" then Theme.Color.Info else Theme.Color.Good,
				SwatchText = if b.Kind == "Catch" then "C" else "L",
				ButtonText = text,
				ButtonColor = color,
				OnClick = function()
					ShopController.Purchase("Boost:" .. id)
				end,
			})
		end
		l.Header("Protection items")
		for _, id in Shop.ItemOrder do
			local it = (Shop.Items :: any)[id]
			local price = prices["Item:" .. id] or it.BaseCost
			local owned = s[it.Field] or 0
			local text, color = priceButton(price, cash)
			local desc = if id == "GoldenWhistle" then "Recalls a dog that ran off (used only if you choose)"
				else "A missed dog gets one second catch roll"
			l.Row({
				Title = ("%s  (own %d)"):format(it.Name, owned),
				Subtitle = desc,
				Color = if id == "GoldenWhistle" then Color3.fromRGB(255, 205, 60) else Color3.fromRGB(240, 150, 90),
				SwatchText = if id == "GoldenWhistle" then "GW" else "TP",
				ButtonText = text,
				ButtonColor = color,
				OnClick = function()
					ShopController.Purchase("Item:" .. id)
				end,
			})
		end
		local mode = (s.Settings and s.Settings.TreatPocketMode) or Shop.DefaultTreatPocketMode
		local idx = table.find(Shop.TreatPocketModes, mode) or 1
		local nextMode = Shop.TreatPocketModes[(idx % #Shop.TreatPocketModes) + 1]
		l.Row({
			Title = "Treat Pocket use: " .. mode,
			Subtitle = "Always / only Epic+ / Off",
			Color = Color3.fromRGB(240, 150, 90),
			SwatchText = "TP",
			ButtonText = "Switch",
			ButtonColor = Theme.Color.Info,
			OnClick = function()
				local remote = Remotes.Get("DogAction") :: RemoteFunction
				pcall(function()
					return remote:InvokeServer("SetTreatPocketMode", nextMode)
				end)
			end,
		})
	elseif currentTab == "Yard" then
		local slots = c.EffectiveSlots or s.SlotCount or Shop.Slots.Start
		l.Text(("Your yard holds %d earning dogs (%d earning now). Up to 12 roam; the rest live in the kennel."):format(slots,
			c.DogsEarning or 0), 34)
		if (s.SlotCount or 0) < Shop.Slots.Max then
			local cost = prices.Slots or Shop.SlotCost(s.SlotCount or Shop.Slots.Start)
			local text, color = priceButton(cost, cash)
			l.Row({
				Title = ("+%d Yard Slots"):format(Shop.Slots.Step),
				Subtitle = ("%d -> %d slots"):format(s.SlotCount or 0, (s.SlotCount or 0) + Shop.Slots.Step),
				Color = Theme.Color.Good,
				SwatchText = "+",
				ButtonText = text,
				ButtonColor = color,
				OnClick = function()
					ShopController.Purchase("Slots")
				end,
			})
		else
			l.Row({ Title = "Yard is at max size", Color = Theme.Color.Good })
		end
	elseif currentTab == "Cosmetics" then
		l.Text(("Cosmetics cost Bones (you have %s) and never give power."):format(FormatNumber.Compact(StateController.Live("Bones"))), 30)
		for _, id in Shop.CosmeticOrder do
			local cos = (Shop.Cosmetics :: any)[id]
			local owned = s.Cosmetics and s.Cosmetics[id] == true
			l.Row({
				Title = cos.Name,
				Subtitle = cos.Slot,
				Color = Theme.Color.Bones,
				SwatchText = "B",
				ButtonText = if owned then "Owned" else (cos.Bones .. " Bones"),
				ButtonColor = if owned then Theme.Color.Good elseif StateController.Live("Bones") >= cos.Bones then Theme.Color.Accent
					else Theme.Color.PanelInset,
				OnClick = function()
					if not owned then
						ShopController.Purchase("Cosmetic:" .. id)
					end
				end,
			})
		end
	elseif currentTab == "Robux" then
		local restricted = player:GetAttribute("PaidRandomItemsRestricted") == true
		l.Text("Robux items. Protection items work only when bought BEFORE a throw.", 30)
		local keys = {}
		for key in Products.DeveloperProducts do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local p = Products.DeveloperProducts[key]
			if key ~= "InstantGrow" and not (restricted and p.RandomInfluence) then
				l.Row({
					Title = p.Name,
					Subtitle = if p.Id == 0 then "Coming soon" else "Developer product",
					Color = Theme.Color.Info,
					SwatchText = "R$",
					ButtonText = if p.Id == 0 then "Soon" else "Buy",
					ButtonColor = if p.Id == 0 then Theme.Color.PanelInset else Theme.Color.Good,
					OnClick = function()
						if p.Id ~= 0 then
							ShopController.Purchase("Product:" .. key)
						end
					end,
				})
			end
		end
		local passKeys = {}
		for key in Products.GamePasses do
			table.insert(passKeys, key)
		end
		table.sort(passKeys)
		for _, key in passKeys do
			local gp = Products.GamePasses[key]
			local owned = s.Passes and s.Passes[key] == true
			if not (restricted and gp.RandomInfluence) then
				l.Row({
					Title = gp.Name,
					Subtitle = if owned then "Owned" elseif gp.Id == 0 then "Coming soon" else "Game pass",
					Color = Theme.Color.Purple,
					SwatchText = "GP",
					ButtonText = if owned then "Owned" elseif gp.Id == 0 then "Soon" else "Buy",
					ButtonColor = if owned then Theme.Color.Good elseif gp.Id == 0 then Theme.Color.PanelInset else Theme.Color.Good,
					OnClick = function()
						if not owned and gp.Id ~= 0 then
							ShopController.Purchase("Pass:" .. key)
						end
					end,
				})
			end
		end
	end
end

local function bindStandPrompt(inst: Instance)
	local shopId = inst:GetAttribute("ShopId")
	local tab = if type(shopId) == "string" then STAND_TO_TAB[shopId] else nil
	if not tab or not inst:IsA("BasePart") or inst:FindFirstChild("ShopPrompt") then
		return
	end
	local prompt = Create.New("ProximityPrompt", { Name = "ShopPrompt", ActionText = "Open " .. tab .. " Shop", ObjectText = "Shop",
		KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = 14, RequiresLineOfSight = false, Parent = inst })
	prompt.Triggered:Connect(function()
		Windows.Open("Shop", tab)
	end)
end

function ShopController.Start()
	Windows.Register("Shop", function(_host)
		local w = Window.new("Shop", Theme.Color.Accent, Windows.Close)
		w.Title.TextColor3 = Theme.Color.TextDark
		local t = Tabs.new(w.Body, TAB_NAMES, function(name)
			currentTab = name
			render()
		end)
		list = RowList.new(w.Body, UDim2.new(1, 0, 1, -40), UDim2.fromOffset(0, 40))
		return {
			Frame = w.Frame,
			OnOpen = function(arg: any)
				if type(arg) == "string" and table.find(TAB_NAMES, arg) then
					t.Select(arg)
				else
					render()
				end
			end,
		}
	end)
	StateController.Changed:Connect(function()
		if Windows.IsOpen("Shop") then
			render()
		end
	end)
	for _, inst in CollectionService:GetTagged("ShopStand") do
		bindStandPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal("ShopStand"):Connect(bindStandPrompt)
end

return ShopController
