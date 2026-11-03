--!strict
-- One modal at a time. Router.Open("Shop") closes whatever is open first; Escape / gamepad B closes.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Router = {}

local screens: { [string]: any } = {}
local current: string? = nil
local listeners: { (string?) -> () } = {}

function Router.Register(name: string, screen: any)
	screens[name] = screen
end

function Router.Current(): string?
	return current
end

function Router.OnChange(fn: (string?) -> ())
	table.insert(listeners, fn)
end

local function notify()
	for _, fn in listeners do
		fn(current)
	end
end

function Router.Close()
	if current and screens[current] then
		screens[current]:Close()
	end
	current = nil
	notify()
end

function Router.Open(name: string, ...: any)
	if current == name then
		Router.Close()
		return
	end
	if current then
		local prev = screens[current]
		if prev then
			prev:Close()
		end
	end
	local s = screens[name]
	if not s then
		warn("Router: no screen named " .. name)
		current = nil
		notify()
		return
	end
	current = name
	s:Open(...)
	GuiService.SelectedObject = nil
	notify()
end

function Router.Toggle(name: string, ...: any)
	Router.Open(name, ...)
end

-- Forget every registered screen and listener (used when the UI is torn down and rebuilt).
function Router.Reset()
	screens = {}
	current = nil
	listeners = {}
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if current then
			Router.Close()
		end
	end
end)

return Router
