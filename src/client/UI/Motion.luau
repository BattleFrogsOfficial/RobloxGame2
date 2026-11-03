--!strict
-- Every UI tween lives here (style guide section 7). ReducedMotion swaps all of them for short fades.
local TweenService = game:GetService("TweenService")

local Motion = {}

Motion.ReducedMotion = false

local function info(t: number, style: Enum.EasingStyle, dir: Enum.EasingDirection?): TweenInfo
	if Motion.ReducedMotion then
		return TweenInfo.new(0.05, Enum.EasingStyle.Linear)
	end
	return TweenInfo.new(t, style, dir or Enum.EasingDirection.Out)
end

function Motion.Tween(instance: Instance, props: { [string]: any }, t: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(instance, info(t, style or Enum.EasingStyle.Quad, dir), props)
	tw:Play()
	return tw
end

-- Scale pop for a UIScale child (created if missing).
local function scaleOf(frame: GuiObject): UIScale
	local s = frame:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "MotionScale"
		s.Parent = frame
	end
	return s :: UIScale
end

function Motion.PanelOpen(frame: GuiObject)
	local s = scaleOf(frame)
	s.Scale = 0.85
	frame.Visible = true
	Motion.Tween(s, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
end

function Motion.PanelClose(frame: GuiObject, onDone: (() -> ())?)
	local s = scaleOf(frame)
	local tw = Motion.Tween(s, { Scale = 0.9 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw.Completed:Once(function()
		frame.Visible = false
		s.Scale = 1
		if onDone then
			onDone()
		end
	end)
end

function Motion.Press(frame: GuiObject)
	local s = scaleOf(frame)
	Motion.Tween(s, { Scale = 0.94 }, 0.06).Completed:Once(function()
		Motion.Tween(s, { Scale = 1 }, 0.08, Enum.EasingStyle.Back)
	end)
end

function Motion.Hover(frame: GuiObject, on: boolean)
	Motion.Tween(scaleOf(frame), { Scale = if on then 1.04 else 1 }, 0.08)
end

function Motion.Pulse(frame: GuiObject, amount: number?)
	local s = scaleOf(frame)
	Motion.Tween(s, { Scale = amount or 1.08 }, 0.1).Completed:Once(function()
		Motion.Tween(s, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
	end)
end

function Motion.Shake(frame: GuiObject, px: number?)
	if Motion.ReducedMotion then
		return
	end
	local base = frame.Position
	local d = px or 4
	task.spawn(function()
		for i = 1, 4 do
			local sign = if i % 2 == 0 then 1 else -1
			local tw = Motion.Tween(frame, { Position = base + UDim2.fromOffset(sign * d, 0) }, 0.04)
			tw.Completed:Wait()
		end
		Motion.Tween(frame, { Position = base }, 0.05)
	end)
end

-- Counts a number label from `from` to `to` over `t` seconds using `fmt` for display.
function Motion.CountUp(label: TextLabel, from: number, to: number, fmt: (number) -> string, t: number?)
	local dur = if Motion.ReducedMotion then 0 else (t or 0.4)
	if dur <= 0 or from == to then
		label.Text = fmt(to)
		return
	end
	local start = os.clock()
	task.spawn(function()
		while true do
			local a = math.min(1, (os.clock() - start) / dur)
			local eased = 1 - (1 - a) * (1 - a)
			label.Text = fmt(from + (to - from) * eased)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

return Motion
