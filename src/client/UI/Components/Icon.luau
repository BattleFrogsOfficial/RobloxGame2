--!strict
-- Pixel icon renderer. Draws from Shared/UI/PixelIcons (grid of Frames, horizontal runs merged) until an
-- asset id exists in Config/Icons, then uses an ImageLabel with pixelated resampling. Sizes snap to integer
-- multiples of 16 so pixels stay crisp.
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
}

function Icon.Snap(px: number?): number
	local want = px or 32
	local mult = math.max(1, math.floor(want / PixelIcons.Size))
	return mult * PixelIcons.Size
end

local function tint(c: Color3, t: Color3?): Color3
	if not t then
		return c
	end
	return Color3.new(c.R * t.R, c.G * t.G, c.B * t.B)
end

local function drawPixels(root: Frame, name: string, px: number, tintColor: Color3?, transparency: number)
	local rows = PixelIcons.Icons[name]
	if not rows then
		rows = PixelIcons.Icons.info
	end
	local unit = px / PixelIcons.Size
	local z = root.ZIndex + 1
	for y, row in rows do
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			if ch == "." then
				x += 1
			else
				local runEnd = x
				while runEnd + 1 <= #row and string.sub(row, runEnd + 1, runEnd + 1) == ch do
					runEnd += 1
				end
				local color = PixelIcons.Palette[ch] or Theme.Color.Ink
				Make("Frame", {
					Name = "px",
					BackgroundColor3 = tint(color, tintColor),
					BackgroundTransparency = transparency,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset((x - 1) * unit, (y - 1) * unit),
					Size = UDim2.fromOffset((runEnd - x + 1) * unit, unit),
					ZIndex = z,
					Parent = root,
				})
				x = runEnd + 1
			end
		end
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
		drawPixels(root, props.Name, px, props.Tint, props.Transparency or 0)
	end
	if props.Parent then
		root.Parent = props.Parent
	end
	return root
end

-- Swap the drawn icon in place (same size).
function Icon.Set(root: Frame, name: string)
	if root:GetAttribute("IconName") == name then
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
		drawPixels(root, name, px, nil, 0)
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

return Icon
