-- Client entry point.

local State = require(script.State)
local Ocean = require(script.Ocean)
local Ui = require(script.ui.Ui)
local Hud = require(script.ui.Hud)
local Inventory = require(script.ui.Inventory)
local Upgrades = require(script.ui.Upgrades)
local Store = require(script.ui.Store)
local Index = require(script.ui.Index)
local RewardsUi = require(script.ui.RewardsUi)
local Hatch = require(script.ui.Hatch)

State.init()
Ocean.init()
Hud.init()

local windows = Ui.screen("Windows", 5)
Inventory.init(windows)
Upgrades.init(windows)
Store.init(windows)
Index.init(windows)
RewardsUi.init(windows)
Hatch.init()
