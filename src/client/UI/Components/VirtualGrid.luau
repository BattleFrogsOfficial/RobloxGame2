--!strict
-- VIRTUALISED grid/list on a ScrollingFrame: only the cells inside the visible window (+1 row of slack)
-- exist; they are pooled and re-bound as you scroll. Used by the Kennel Book (1,400+ forms) and the Yard list.
--
--   local grid = VirtualGrid.new({
--       Parent = body, CellMinWidth = 96, CellAspect = 1.25 (h/w) | CellHeight = 64 (fixed, list mode),
--       MaxColumns = 8, Padding = 6,
--       CreateCell = function() return frame end,
--       Render = function(cell, index) ... end,
--   })
--   grid:SetCount(n)   grid:Refresh()   grid:ScrollToTop()   grid.Frame
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Create = require(script.Parent:WaitForChild("Create"))

local VirtualGrid = {}
VirtualGrid.__index = VirtualGrid

export type Props = {
	Parent: Instance,
	CellMinWidth: number,
	CellAspect: number?,
	CellHeight: number?,
	MaxColumns: number?,
	Padding: number?,
	Size: UDim2?,
	Position: UDim2?,
	CreateCell: () -> GuiObject,
	Render: (cell: GuiObject, index: number) -> (),
}

export type Grid = typeof(setmetatable({} :: {
	Frame: ScrollingFrame,
	Props: Props,
	Count: number,
	Columns: number,
	CellW: number,
	CellH: number,
	Pad: number,
	Active: { [number]: GuiObject },
	Pool: { GuiObject },
	Conns: { RBXScriptConnection },
}, VirtualGrid))

function VirtualGrid.new(props: Props): Grid
	local frame: ScrollingFrame = Create.New("ScrollingFrame", {
		Name = "VirtualGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Color.TextDim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Parent = props.Parent,
	})
	local self = setmetatable({
		Frame = frame,
		Props = props,
		Count = 0,
		Columns = 1,
		CellW = props.CellMinWidth,
		CellH = props.CellHeight or props.CellMinWidth,
		Pad = props.Padding or Theme.Spacing.S,
		Active = {},
		Pool = {},
		Conns = {},
	}, VirtualGrid)
	table.insert(self.Conns, frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_relayout()
	end))
	table.insert(self.Conns, frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_update(false)
	end))
	self:_relayout()
	return self
end

function VirtualGrid._relayout(self: Grid)
	local width = self.Frame.AbsoluteSize.X - 10 -- scrollbar room
	if width <= 0 then
		return
	end
	local p = self.Props
	local pad = self.Pad
	local cols = math.max(1, math.floor((width - pad) / (p.CellMinWidth + pad)))
	if p.MaxColumns then
		cols = math.min(cols, p.MaxColumns)
	end
	self.Columns = cols
	self.CellW = (width - pad * (cols + 1)) / cols
	self.CellH = p.CellHeight or self.CellW * (p.CellAspect or 1)
	self:_updateCanvas()
	-- every active cell needs a new size/position
	self:_update(true)
end

function VirtualGrid._updateCanvas(self: Grid)
	local rows = math.ceil(self.Count / self.Columns)
	self.Frame.CanvasSize = UDim2.fromOffset(0, rows * (self.CellH + self.Pad) + self.Pad)
end

function VirtualGrid._release(self: Grid, index: number)
	local cell = self.Active[index]
	if cell then
		self.Active[index] = nil
		cell.Visible = false
		table.insert(self.Pool, cell)
	end
end

function VirtualGrid._update(self: Grid, rebindAll: boolean)
	local rowH = self.CellH + self.Pad
	if rowH <= 0 then
		return
	end
	local top = self.Frame.CanvasPosition.Y
	local viewH = self.Frame.AbsoluteWindowSize.Y
	local firstRow = math.max(0, math.floor(top / rowH) - 1)
	local lastRow = math.floor((top + viewH) / rowH) + 1
	local first = firstRow * self.Columns + 1
	local last = math.min(self.Count, (lastRow + 1) * self.Columns)
	for index in self.Active do
		if index < first or index > last then
			self:_release(index)
		end
	end
	for index = first, last do
		local cell = self.Active[index]
		local fresh = false
		if not cell then
			cell = table.remove(self.Pool) or self.Props.CreateCell()
			cell.Parent = self.Frame
			self.Active[index] = cell
			fresh = true
		end
		local c = cell :: GuiObject
		local i0 = index - 1
		local col = i0 % self.Columns
		local row = i0 // self.Columns
		c.Size = UDim2.fromOffset(self.CellW, self.CellH)
		c.Position = UDim2.fromOffset(self.Pad + col * (self.CellW + self.Pad), self.Pad + row * rowH)
		c.Visible = true
		if fresh or rebindAll then
			self.Props.Render(c, index)
		end
	end
end

function VirtualGrid.SetCount(self: Grid, n: number)
	self.Count = math.max(0, n)
	self:_updateCanvas()
	-- drop cells beyond the new count, re-bind the rest
	for index in self.Active do
		if index > self.Count then
			self:_release(index)
		end
	end
	self:_update(true)
end

-- Change the cell sizing (e.g. compact layout on short screens) and re-flow.
function VirtualGrid.SetCellSize(self: Grid, cellMinWidth: number, cellAspect: number?)
	self.Props.CellMinWidth = cellMinWidth
	if cellAspect then
		self.Props.CellAspect = cellAspect
	end
	self:_relayout()
end

function VirtualGrid.Refresh(self: Grid)
	self:_update(true)
end

function VirtualGrid.ScrollToTop(self: Grid)
	self.Frame.CanvasPosition = Vector2.zero
end

function VirtualGrid.CellCount(self: Grid): number
	local n = #self.Pool
	for _ in self.Active do
		n += 1
	end
	return n
end

function VirtualGrid.Destroy(self: Grid)
	for _, c in self.Conns do
		c:Disconnect()
	end
	self.Frame:Destroy()
end

return VirtualGrid
