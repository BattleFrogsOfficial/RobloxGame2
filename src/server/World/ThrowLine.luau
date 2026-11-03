--!strict
-- Throw line: the white line at Layout.ThrowLine.Z, six numbered ThrowPads (pad i = yard i's colour),
-- a rope fence + low invisible wall at Z = ThrowLine.Z + 8 so nobody walks into the fetch field.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local ThrowLine = {}

local Y = Layout.GroundY
local T = WorldTheme.ThrowLine
local TL = Layout.ThrowLine

ThrowLine.WallOffset = 8 -- brief: low wall at ThrowLine.Z + 8
ThrowLine.WallHeight = 12 -- taller than a default jump (~7.2 studs)

function ThrowLine.Build(parent: Instance)
	local folder = Props.Folder(parent, "ThrowLine")
	local minX, maxX = Layout.Field.MinX, Layout.Field.MaxX

	Props.Slab(folder, "Line", minX, maxX, TL.Z - 0.75, TL.Z + 0.75, Y + 0.06, 0.06, T.Line,
		WorldTheme.AccentMaterial, false)

	local size: Vector3 = TL.PadSize
	for i, x in TL.PadsX do
		local m = Props.Model(folder, "Pad" .. i)
		local color: Color3 = WorldTheme.YardColors[i]
		-- rotated 180° so the Top-face number reads upright for a player walking in from the plaza (+Z)
		local pad = Props.Part({ Parent = m, Name = "ThrowPad", Size = size,
			CFrame = CFrame.new(x, Y + size.Y / 2, TL.Z) * CFrame.Angles(0, math.pi, 0), Color = T.Pad, Collide = true })
		Props.Tag(pad, "ThrowPad", { PadIndex = i })
		Props.Label(pad, tostring(i), { Face = Enum.NormalId.Top, PixelsPerStud = 10, TextColor = color })
		m.PrimaryPart = pad
		Props.Slab(m, "PadRing", x - size.X / 2 - 0.6, x + size.X / 2 + 0.6, TL.Z - size.Z / 2 - 0.6, TL.Z + size.Z / 2 + 0.6,
			Y + 0.6, 0.6, color, WorldTheme.AccentMaterial, false)
		-- upright number board standing on the pad's field-side edge, facing the thrower
		local bp = Vector3.new(x, Y + size.Y + 1.8, TL.Z + size.Z / 2 - 0.5)
		local board = Props.Part({ Parent = m, Name = "PadNumber", Size = Vector3.new(7, 3.6, 0.6),
			CFrame = CFrame.lookAt(bp, bp - Vector3.new(0, 0, 1)), Color = color })
		Props.Label(board, "PAD " .. i, { PixelsPerStud = 24, TextColor = Color3.new(1, 1, 1) })
	end

	-- rope fence marking the edge (decor) + the invisible wall that actually blocks players
	local wz = TL.Z + ThrowLine.WallOffset
	Props.FenceLine(folder, Vector3.new(minX + 1, Y, wz - 0.4), Vector3.new(maxX - 1, Y, wz - 0.4), 12, 2.6,
		WorldTheme.YardColors[3], false)
	Props.Wall(folder, "FieldWall", minX, maxX, wz - 0.5, wz + 0.5, Y, ThrowLine.WallHeight)
end

return ThrowLine
