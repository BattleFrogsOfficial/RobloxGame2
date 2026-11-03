--!strict
-- Cutscene sounds (2D, local only). Ids come from Config/Cutscene.SoundIds; State.Settings.Sfx = false mutes
-- everything. Every sound is parented to SoundService and handed to the caller's Janitor (or destroyed when it ends).
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Cutscene"))

local Sfx = {}

Sfx.Enabled = function(): boolean
	return true
end

export type Opts = { Volume: number?, Pitch: number?, Looped: boolean?, Janitor: any? }

-- Creates (and plays) a sound; returns it, or nil when muted / unknown.
function Sfx.Play(key: string, opts: Opts?): Sound?
	local o: Opts = opts or {}
	local id = (C.SoundIds :: any)[key]
	if type(id) ~= "string" or id == "" or not Sfx.Enabled() then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "Cutscene_" .. key
	s.SoundId = id
	s.Volume = o.Volume or 0.5
	s.PlaybackSpeed = o.Pitch or 1
	s.Looped = o.Looped == true
	s.Parent = SoundService
	if o.Janitor then
		o.Janitor:Add(s)
	end
	if not s.Looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
		task.delay(8, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
	s:Play()
	return s
end

return Sfx
