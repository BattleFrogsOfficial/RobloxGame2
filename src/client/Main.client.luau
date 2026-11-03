--!strict
-- The only client entry script. Starts, in order:
--   1. the UI (src/client/UI): HUD, panels, throw prompt + power meter, reveal card, spectator banner.
--      PlaceholderCutscene = false: the 3D cutscene below drives the reveal and CutsceneFinished.
--   2. CutsceneController: the thrower's cutscene (src/shared/Cutscene) -> Reveal card -> FinishThrow.
--   3. WorldController: local yard/runaway dog animation and shop-stand prompts.
-- Each controller start is isolated so one failure never takes the HUD down.
local Client = script.Parent
Client:SetAttribute("UIStartedElsewhere", true) -- legacy flag: nothing else may start a second UI

local UI = require(Client:WaitForChild("UI"))
local ui = UI.Start({ PlaceholderCutscene = false })
_G.ThrowABallUI = ui -- handy in Studio's command bar

local Controllers = Client:WaitForChild("Controllers")
for _, name in { "CutsceneController", "WorldController" } do
	local ok, controller = pcall(require, Controllers:WaitForChild(name))
	if not ok then
		warn(("[Client] %s failed to load: %s"):format(name, tostring(controller)))
		continue
	end
	local c = controller :: any
	if type(c.Start) == "function" then
		local started, err = pcall(c.Start, ui)
		if not started then
			warn(("[Client] %s.Start failed: %s"):format(name, tostring(err)))
		end
	end
end
