--!strict
-- Starts the HUD/UI. If another client entry script owns the UI start (for example a Cutscene controller that
-- needs the handle), set the attribute "UIStartedElsewhere" = true on this script's parent before it runs,
-- or delete this script from the project.
if script.Parent:GetAttribute("UIStartedElsewhere") then
	return
end
local UI = require(script.Parent:WaitForChild("UI"))
local ui = UI.Start()
_G.ThrowABallUI = ui -- handy in Studio's command bar; the cutscene module should require UI and keep its own handle
