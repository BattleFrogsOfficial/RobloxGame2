--!strict
-- Tiny declarative instance factory. Make("Frame", { Size = ..., Parent = ..., [Make.Children] = { ... },
-- Activated = function() end }) -> Frame. Event names (keys whose value is a function and that name an
-- event on the instance) are connected. Children are parented after properties so layouts resolve once.
local Make = {}

Make.Children = setmetatable({}, { __tostring = function() return "Make.Children" end }) :: any
Make.Ref = setmetatable({}, { __tostring = function() return "Make.Ref" end }) :: any -- { Ref = table } receives the instance at table[1]

local function isEventName(instance: Instance, key: string): boolean
	local ok, value = pcall(function()
		return (instance :: any)[key]
	end)
	return ok and typeof(value) == "RBXScriptSignal"
end

local function apply(instance: Instance, props: { [any]: any })
	local parent: Instance? = nil
	local children: { Instance }? = nil
	for key, value in props do
		if key == "Parent" then
			parent = value
		elseif key == Make.Children then
			children = value
		elseif key == Make.Ref then
			value[1] = instance
		elseif type(key) == "string" then
			if type(value) == "function" and isEventName(instance, key) then
				((instance :: any)[key] :: RBXScriptSignal):Connect(value)
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			if child then
				child.Parent = instance
			end
		end
	end
	if parent then
		instance.Parent = parent
	end
end

local callable = setmetatable(Make, {
	__call = function(_, className: string, props: { [any]: any }?): any
		local instance = Instance.new(className)
		if props then
			apply(instance, props)
		end
		return instance
	end,
})

-- Make.Update(instance, props): same semantics on an existing instance.
function Make.Update(instance: Instance, props: { [any]: any })
	apply(instance, props)
end

return (callable :: any) :: ((className: string, props: { [any]: any }?) -> any) & typeof(Make)
