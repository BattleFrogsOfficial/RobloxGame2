--!strict
-- Client bootstrap: starts every controller in dependency order. Each Start is isolated so one failing
-- controller never takes the rest of the HUD down.
local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"StateController", -- state cache first; everything reads it
	"HudController", -- HUD regions (HudLayout) other controllers fill
	"NotificationController", -- feed + toasts
	"ThrowController", -- meter + input + ball flight
	"WhistlePrompt",
	"CutsceneController", -- ThrowResult -> cutscene / spectator banner
	"ShopController",
	"BookController",
	"YardController",
	"OddsController",
}

for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	local ok, controller = pcall(require, module)
	if not ok then
		warn(("[Client] %s failed to load: %s"):format(name, tostring(controller)))
		continue
	end
	local c = controller :: any
	if type(c.Start) == "function" then
		local started, err = pcall(c.Start)
		if not started then
			warn(("[Client] %s.Start failed: %s"):format(name, tostring(err)))
		end
	end
end
