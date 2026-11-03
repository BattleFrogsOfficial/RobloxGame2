--!strict
-- The only client entry script. Starts, in order:
--   1. the UI (src/client/UI): HUD, panels, throw prompt + power meter, reveal card, spectator banner.
--      PlaceholderCutscene = false: the throw cutscene below drives the reveal and CutsceneFinished.
--   2. Cutscene (src/client/Cutscene): the local player's throw cutscene (wind-up -> ball POV -> landing ->
--      dog -> odds counter -> caught / missed -> Reveal card -> ui:FinishThrow), plus the CutsceneTestMode panel.
--      Other players' throws (avatar wind-up + ball) are animated by BallFlight.client.luau.
--   3. WorldController: local yard/runaway dog animation and shop-stand prompts.
-- Each start is isolated so one failure never takes the HUD down.
local Client = script.Parent
Client:SetAttribute("UIStartedElsewhere", true) -- legacy flag: nothing else may start a second UI

local UI = require(Client:WaitForChild("UI"))
local ui = UI.Start({ PlaceholderCutscene = false })
_G.ThrowABallUI = ui -- handy in Studio's command bar

local function start(name: string, module: Instance)
	local ok, controller = pcall(require, module)
	if not ok then
		warn(("[Client] %s failed to load: %s"):format(name, tostring(controller)))
		return nil
	end
	local c = controller :: any
	if type(c.Start) == "function" then
		local started, err = pcall(c.Start, ui)
		if not started then
			warn(("[Client] %s.Start failed: %s"):format(name, tostring(err)))
		end
	end
	return c
end

ui.Cutscene = start("Cutscene", Client:WaitForChild("Cutscene"))
start("WorldController", Client:WaitForChild("Controllers"):WaitForChild("WorldController"))
