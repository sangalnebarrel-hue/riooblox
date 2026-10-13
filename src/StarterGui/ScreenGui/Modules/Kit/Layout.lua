-- Responsive layout maths shared by Window and VirtualGrid. Pure: no services, tested by
-- tests/uikit.luau.
local Layout = {}

-- Same thresholds as UITheme.ApplyStandalone (CompactMenus): below them a window becomes a
-- full-screen sheet.
Layout.CompactWidth = 700
Layout.CompactHeight = 560

export type Info = {
	Width: number,
	Height: number,
	Phone: boolean,
	Landscape: boolean,
	Touch: boolean,
}

-- Classifies the usable (safe) screen area.
-- 1920x1080 -> desktop; 812x375 -> phone landscape; 390x844 -> phone portrait.
function Layout.Classify(width: number, height: number, touch: boolean?): Info
	local phone = width < Layout.CompactWidth or height < Layout.CompactHeight
	return {
		Width = width,
		Height = height,
		Phone = phone,
		Landscape = phone and width > height * 1.25,
		Touch = touch == true,
	}
end

-- Window rectangle inside the safe area: a centred card limited to maxW x maxH with a margin on
-- desktop, the whole safe area on phones. Returns x, y, w, h in pixels.
function Layout.WindowRect(
	safeX: number,
	safeY: number,
	safeW: number,
	safeH: number,
	phone: boolean,
	maxW: number,
	maxH: number,
	margin: number?
): (number, number, number, number)
	if phone then
		return math.floor(safeX), math.floor(safeY), math.max(1, math.floor(safeW)), math.max(1, math.floor(safeH))
	end
	local m = margin or 28
	local w = math.max(1, math.floor(math.min(maxW, safeW - m * 2)))
	local h = math.max(1, math.floor(math.min(maxH, safeH - m * 2)))
	return math.floor(safeX + (safeW - w) / 2), math.floor(safeY + (safeH - h) / 2), w, h
end

-- How many columns of at least minCell pixels fit in width (with gaps and side padding), and the
-- resulting cell width. maxColumns caps the count.
function Layout.Columns(width: number, minCell: number, gap: number, padding: number, maxColumns: number?): (number, number)
	local inner = math.max(1, width - padding * 2)
	local columns = math.max(1, math.floor((inner + gap) / (math.max(1, minCell) + gap)))
	if maxColumns and maxColumns >= 1 then
		columns = math.min(columns, math.floor(maxColumns))
	end
	local cell = math.max(1, math.floor((inner - gap * (columns - 1)) / columns))
	return columns, cell
end

function Layout.Rows(count: number, columns: number): number
	if count <= 0 then
		return 0
	end
	return math.ceil(count / math.max(1, columns))
end

-- Height of the scrolling canvas for count cells.
function Layout.CanvasHeight(count: number, columns: number, rowH: number, gap: number, padding: number): number
	local rows = Layout.Rows(count, columns)
	if rows == 0 then
		return 0
	end
	return padding * 2 + rows * rowH + (rows - 1) * gap
end

-- Top-left of cell `index` (1-based) inside the canvas.
function Layout.CellPosition(index: number, columns: number, cellW: number, rowH: number, gap: number, padding: number): (number, number)
	local i = index - 1
	local col, row = i % columns, i // columns
	return padding + col * (cellW + gap), padding + row * (rowH + gap)
end

-- First and last cell index (1-based, inclusive) intersecting the viewport [scrollY, scrollY+viewH],
-- widened by `overscan` rows on both sides. Returns 1, 0 when nothing is visible.
function Layout.VisibleRange(
	scrollY: number,
	viewH: number,
	count: number,
	columns: number,
	rowH: number,
	gap: number,
	padding: number,
	overscan: number?
): (number, number)
	if count <= 0 or viewH <= 0 or rowH <= 0 then
		return 1, 0
	end
	local rows = Layout.Rows(count, columns)
	local stride = rowH + gap
	-- Row r spans [padding + r*stride, padding + r*stride + rowH].
	local firstRow = math.floor((scrollY - padding - rowH) / stride) + 1
	local lastRow = math.ceil((scrollY + viewH - padding) / stride) - 1
	local extra = overscan or 0
	firstRow = math.max(0, firstRow - extra)
	lastRow = math.min(rows - 1, lastRow + extra)
	if lastRow < firstRow then
		return 1, 0
	end
	return firstRow * columns + 1, math.min(count, (lastRow + 1) * columns)
end

-- Upper bound of cells a viewport can bind at once (used by tests and the cell pool).
function Layout.MaxCells(viewH: number, columns: number, rowH: number, gap: number, overscan: number?): number
	local stride = math.max(1, rowH + gap)
	return (math.ceil(viewH / stride) + 1 + 2 * (overscan or 0)) * columns
end

function Layout.ClampScroll(scrollY: number, canvasH: number, viewH: number): number
	return math.clamp(scrollY, 0, math.max(0, canvasH - viewH))
end

-- Scroll offset that brings cell `index` into view (minimal movement).
function Layout.ScrollToReveal(
	index: number,
	scrollY: number,
	viewH: number,
	columns: number,
	rowH: number,
	gap: number,
	padding: number
): number
	local _, top = Layout.CellPosition(index, columns, 1, rowH, gap, padding)
	if top < scrollY then
		return math.max(0, top - padding)
	elseif top + rowH > scrollY + viewH then
		return top + rowH + padding - viewH
	end
	return scrollY
end

return Layout
