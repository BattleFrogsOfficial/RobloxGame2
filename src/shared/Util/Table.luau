--!strict
-- Small table helpers.
local Table = {}

function Table.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[Table.DeepCopy(k)] = Table.DeepCopy(v)
	end
	return (out :: any) :: T
end

-- Fill missing keys of `target` from `template` (deep). Existing values are kept. Returns target.
function Table.Reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for k, v in template do
		if target[k] == nil then
			target[k] = Table.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			Table.Reconcile(target[k], v)
		end
	end
	return target
end

function Table.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Table.Keys<K>(t: { [K]: any }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

function Table.Map<T, U>(list: { T }, fn: (T, number) -> U): { U }
	local out = table.create(#list)
	for i, v in list do
		out[i] = fn(v, i)
	end
	return out
end

function Table.Filter<T>(list: { T }, fn: (T) -> boolean): { T }
	local out = {}
	for _, v in list do
		if fn(v) then
			table.insert(out, v)
		end
	end
	return out
end

function Table.Shallow<T>(t: T): T
	return table.clone(t :: any) :: any
end

return Table
