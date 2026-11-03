--!strict
-- Virtualised grid: only the visible rows (plus one buffer row) exist as instances. Needed for the
-- 1,422-form Kennel Book. Cells are pooled and re-rendered via props.Render(cell, index).
local Make = require(script.Parent.Parent:WaitForChild("Make"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Decor = require(script.Parent:WaitForChild("Decor"))

local VirtualGrid = {}

export type GridProps = {
	Parent: Instance,
	Size: UDim2?,
	Position: UDim2?,
	LayoutOrder: number?,
	ZIndex: number?,
	CellSize: Vector2,
	Gap: number?,
	Count: number,
	Create: () -> GuiObject, -- builds an empty cell
	Render: (cell: GuiObject, index: number) -> (), -- fills a cell for an item index
}

export type GridHandle = {
	Root: ScrollingFrame,
	SetCount: (self: GridHandle, n: number) -> (),
	Refresh: (self: GridHandle) -> (),
	ScrollTo: (self: GridHandle, index: number) -> (),
}

function VirtualGrid.new(props: GridProps): GridHandle
	local gap = props.Gap or Theme.Space.S
	local cw, ch = props.CellSize.X, props.CellSize.Y
	local root: ScrollingFrame = Make("ScrollingFrame", {
		Name = "VirtualGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 53,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Ink,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
	})
	local canvas: Frame = Make("Frame", { Name = "Canvas", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = root.ZIndex, Parent = root })

	local count = props.Count
	local pool: { GuiObject } = {}
	local assigned: { [GuiObject]: number } = {}
	local columns = 1

	local function layout()
		-- AbsoluteSize and CanvasPosition are in screen pixels; cell sizes are pre-UIScale offsets.
		local es = Decor.EffectiveScale(root)
		local width = math.max(cw, root.AbsoluteSize.X / es - 8)
		columns = math.max(1, math.floor((width + gap) / (cw + gap)))
		local rows = math.ceil(count / columns)
		root.CanvasSize = UDim2.fromOffset(0, rows * (ch + gap))
		local viewH = root.AbsoluteSize.Y / es
		local scrollY = root.CanvasPosition.Y / es
		local firstRow = math.max(0, math.floor(scrollY / (ch + gap)) - 1)
		local lastRow = math.min(rows - 1, math.ceil((scrollY + viewH) / (ch + gap)) + 1)
		local needed = {}
		for r = firstRow, lastRow do
			for c = 0, columns - 1 do
				local idx = r * columns + c + 1
				if idx <= count then
					table.insert(needed, idx)
				end
			end
		end
		-- Free cells no longer needed
		local neededSet: { [number]: boolean } = {}
		for _, i in needed do
			neededSet[i] = true
		end
		local free: { GuiObject } = {}
		for cell, idx in assigned do
			if not neededSet[idx] then
				assigned[cell] = nil
				table.insert(free, cell)
			end
		end
		local inUse: { [number]: boolean } = {}
		for _, idx in assigned do
			inUse[idx] = true
		end
		for _, idx in needed do
			if not inUse[idx] then
				local cell = table.remove(free)
				if not cell then
					cell = props.Create()
					cell.ZIndex = root.ZIndex + 1
					cell.Parent = canvas
					table.insert(pool, cell)
				end
				local c = cell :: GuiObject
				local r = (idx - 1) // columns
				local col = (idx - 1) % columns
				c.Position = UDim2.fromOffset(col * (cw + gap), r * (ch + gap))
				c.Size = UDim2.fromOffset(cw, ch)
				c.Visible = true
				assigned[c] = idx
				props.Render(c, idx)
			end
		end
		for _, cell in free do
			cell.Visible = false
		end
		-- Columns can change with the viewport: re-place every live cell, not only the new ones.
		for cell, idx in assigned do
			local r = (idx - 1) // columns
			local col = (idx - 1) % columns
			cell.Position = UDim2.fromOffset(col * (cw + gap), r * (ch + gap))
		end
	end

	root:GetPropertyChangedSignal("CanvasPosition"):Connect(layout)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local handle = { Root = root } :: any
	function handle.SetCount(_, n: number)
		count = n
		for cell in assigned do
			assigned[cell] = nil
			cell.Visible = false
		end
		root.CanvasPosition = Vector2.new()
		layout()
	end
	function handle.Refresh()
		for cell, idx in assigned do
			if cell.Parent then
				props.Render(cell, idx)
			end
		end
	end
	function handle.ScrollTo(_, index: number)
		local r = (index - 1) // columns
		root.CanvasPosition = Vector2.new(0, r * (ch + gap) * Decor.EffectiveScale(root))
	end
	root.Parent = props.Parent
	task.defer(layout)
	return handle :: GridHandle
end

return VirtualGrid
