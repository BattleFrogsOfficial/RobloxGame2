--!strict
-- Pixel icon renderer. Draws from Shared/UI/PixelIcons (grid of Frames; same-colour runs merged into rectangles,
-- cached per icon) until an asset id exists in Config/Icons, then uses an ImageLabel with pixelated resampling.
-- Icons are 16 x 16 or 32 x 32 grids (the hero icons); sizes snap to multiples of 16 px.
-- Recolor = { ["1"] = Color3, ... } swaps palette letters (the dog's coat letters 1-5) on the Frame renderer.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PixelIcons = require(Shared:WaitForChild("UI"):WaitForChild("PixelIcons"))
local IconIds = require(Shared:WaitForChild("Config"):WaitForChild("Icons"))
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local Icon = {}

export type IconProps = {
	Name: string,
	Size: number?, -- requested px; snapped down to a multiple of 16 (min 16)
	Parent: Instance?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Tint: Color3?, -- multiplies every pixel (used for disabled / silhouette states)
	Transparency: number?,
	Recolor: { [string]: Color3 }?, -- palette letter -> colour (Frame renderer only)
}

type Run = { X: number, Y: number, W: number, H: number, Ch: string }
local rectCache: { [string]: { Run } } = {}

-- Same-colour horizontal runs, then runs stacked vertically with identical x/width merge into one rectangle.
local function rectsFor(name: string): { Run }
	local cached = rectCache[name]
	if cached then
		return cached
	end
	local rows = PixelIcons.Icons[name] or PixelIcons.Icons.info
	local out: { Run } = {}
	local open: { [string]: Run } = {} -- key "x:w:ch" -> rect still growing downward
	for y, row in rows do
		local nextOpen: { [string]: Run } = {}
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			if ch == "." then
				x += 1
			else
				local e = x
				while e + 1 <= #row and string.sub(row, e + 1, e + 1) == ch do
					e += 1
				end
				local key = x .. ":" .. (e - x + 1) .. ":" .. ch
				local r = open[key]
				if r and r.Y + r.H == y - 1 then
					r.H += 1
				else
					r = { X = x - 1, Y = y - 1, W = e - x + 1, H = 1, Ch = ch }
					table.insert(out, r)
				end
				nextOpen[key] = r
				x = e + 1
			end
		end
		open = nextOpen
	end
	rectCache[name] = out
	return out
end

function Icon.Snap(px: number?): number
	local want = px or 32
	local mult = math.max(1, math.floor(want / 16))
	return mult * 16
end

local function tint(c: Color3, t: Color3?): Color3
	if not t then
		return c
	end
	return Color3.new(c.R * t.R, c.G * t.G, c.B * t.B)
end

local function drawPixels(root: Frame, name: string, px: number, tintColor: Color3?, transparency: number, recolor: { [string]: Color3 }?)
	local grid = PixelIcons.GridSize(if PixelIcons.Icons[name] then name else "info")
	local unit = px / grid
	local z = root.ZIndex + 1
	for _, r in rectsFor(name) do
		local color = (recolor and recolor[r.Ch]) or PixelIcons.Palette[r.Ch] or Theme.Color.Ink
		Make("Frame", {
			Name = "px",
			BackgroundColor3 = tint(color, tintColor),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(r.X * unit, r.Y * unit),
			Size = UDim2.fromOffset(r.W * unit, r.H * unit),
			ZIndex = z,
			Parent = root,
		})
	end
end

function Icon.new(props: IconProps): Frame
	local px = Icon.Snap(props.Size)
	local root = Make("Frame", {
		Name = "Icon_" .. props.Name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px, px),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	root:SetAttribute("IconName", props.Name)
	local assetId = IconIds.Get(props.Name)
	if assetId > 0 then
		Make("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. assetId,
			ImageColor3 = props.Tint or Color3.new(1, 1, 1),
			ImageTransparency = props.Transparency or 0,
			ResampleMode = Enum.ResamplerMode.Pixelated,
			Size = UDim2.fromScale(1, 1),
			ZIndex = root.ZIndex + 1,
			Parent = root,
		})
	else
		drawPixels(root, props.Name, px, props.Tint, props.Transparency or 0, props.Recolor)
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- Swap the drawn icon in place (same size). Recolor / Tint as in Icon.new (a recolour always redraws).
function Icon.Set(root: Frame, name: string, recolor: { [string]: Color3 }?, tintColor: Color3?)
	if root:GetAttribute("IconName") == name and recolor == nil and tintColor == nil then
		return
	end
	for _, c in root:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	root:SetAttribute("IconName", name)
	root.Name = "Icon_" .. name
	local px = root.Size.X.Offset
	local assetId = IconIds.Get(name)
	if assetId > 0 then
		Make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. assetId,
			ResampleMode = Enum.ResamplerMode.Pixelated,
			Size = UDim2.fromScale(1, 1),
			ZIndex = root.ZIndex + 1,
			Parent = root,
		})
	else
		drawPixels(root, name, px, tintColor, 0, recolor)
	end
end

function Icon.ForZone(zoneId: string): string
	return PixelIcons.ZoneIcon[zoneId] or "info"
end

function Icon.ForBall(ballId: string): string
	return PixelIcons.BallIcon[ballId] or "ball_tennis"
end

function Icon.ForVariant(variant: string?): string?
	if variant == "Gold" then
		return "variant_gold"
	elseif variant == "Shadow" then
		return "variant_shadow"
	elseif variant == "Rainbow" then
		return "variant_rainbow"
	end
	return nil
end

-- Coat colours for the recolourable `dog` icon from a roster entry (CoatPrimary / CoatSecondary hex strings).
function Icon.DogColors(def: any): { [string]: Color3 }?
	if type(def) ~= "table" then
		return nil
	end
	local function hex(v: any): Color3?
		if type(v) ~= "string" then
			return nil
		end
		local ok, c = pcall(Color3.fromHex, v)
		return if ok then c else nil
	end
	local p, s2 = hex(def.CoatPrimary), hex(def.CoatSecondary)
	if not p then
		return nil
	end
	local sec = s2 or p:Lerp(Color3.new(1, 1, 1), 0.6)
	local black = Color3.new(0, 0, 0)
	local white = Color3.new(1, 1, 1)
	return {
		["1"] = p,
		["5"] = p:Lerp(white, 0.3),
		["2"] = p:Lerp(black, 0.32),
		["3"] = sec,
		["4"] = sec:Lerp(black, 0.18),
	}
end

return Icon
