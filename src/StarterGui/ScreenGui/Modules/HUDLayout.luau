-- Pure maths of the HUD layout (UITheme.LayoutHUD applies it). No services: tests/hud.luau runs it
-- for phones (portrait / landscape), tablets and desktops.
--
--   * Rail: the 8 menu buttons (round squares with a tiny label under the icon), pinned to the
--     left safe edge and vertically centred: one column when it fits at a comfortable size,
--     otherwise two (or three) columns. On touch screens it ends above the thumbstick.
--   * Bar: the currency pills (coins, bones, stone, level) at the top centre; wraps into two
--     rows when the space between the rail and the cluster is too narrow.
--   * Cluster: the small round buttons (NAVIGATE, TITLES, HIDE UI, SETTINGS) at the top-right:
--     a row on desktops, a column at the right edge on touch screens (above the jump button).
--   * Free zone: what is left between them (notices, boosts, toasts, the map marker button).
-- All numbers are ScreenGui pixels (x right, y down); rectangles are {X, Y, W, H}.
local L = {}

export type Input = {
	Left: number,
	Top: number,
	Width: number,
	Height: number, -- the Core UI safe area
	Touch: boolean,
	JumpX: number?,
	JumpY: number?, -- top-left of the touch jump button (touch screens)
	Thumb: number?, -- height kept free for the thumbstick at the bottom-left (touch)
	Tiles: number?, -- rail buttons (8)
	Cluster: number?, -- cluster buttons (4)
	PlayerList: boolean?, -- the Roblox leaderboard is shown at the top-right
	Pills: { number }?, -- width of each currency pill in bar heights (e.g. {4.6, 3, 3.6})
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- Rail button size B that fits `count` tiles in `cols` columns into `avail` pixels of height.
-- A slot is B tall plus the label that pokes out under the button (LABEL_OUT x B).
local LABEL_OUT = 0.14
local function railFit(count: number, cols: number, avail: number, gap: number): (number, number)
	local rows = math.ceil(count / cols)
	local size = math.floor((avail - (rows - 1) * gap) / (rows * (1 + LABEL_OUT)))
	return size, rows
end

function L.Compute(i: Input): any
	local left, top, w, h = i.Left, i.Top, math.max(1, i.Width), math.max(1, i.Height)
	local right, bottom = left + w, top + h
	local touch = i.Touch == true
	local small = math.min(w, h) <= 500
	local s = math.clamp(math.min(w / 1100, h / 620), 0.55, 1)
	local margin = touch and 8 or 14
	local thumb = i.Thumb or (touch and (small and 100 or 170) or 0)
	local jumpX = i.JumpX or (right - (small and 95 or 170))
	local jumpY = i.JumpY or (bottom - (small and 90 or 210))
	local out: any = { Scale = s, Touch = touch, Small = small }

	-- CLUSTER ---------------------------------------------------------------------------------
	local nC = i.Cluster or 4
	local C = touch and math.clamp(round(44 * math.max(s, 0.9)), 40, 46) or math.clamp(round(44 * s), 36, 46)
	local cg = touch and 6 or 8
	local clusterRight = right - margin - ((i.PlayerList and not touch) and 196 or 0)
	local cluster: any = { Size = C, Gap = cg, Cells = {}, Vertical = touch }
	if touch then
		-- One column at the right edge; two when it would reach the jump button.
		local cols = 1
		local rowsC = nC
		if top + margin + nC * C + (nC - 1) * cg > jumpY - 10 then
			cols = 2
			rowsC = math.ceil(nC / 2)
		end
		for k = 1, nC do
			local col = (k - 1) % cols
			local row = math.floor((k - 1) / cols)
			cluster.Cells[k] = {
				X = clusterRight - C - (cols - 1 - col) * (C + cg),
				Y = top + margin + row * (C + cg),
			}
		end
		cluster.Left = clusterRight - cols * C - (cols - 1) * cg
		cluster.Bottom = top + margin + rowsC * C + (rowsC - 1) * cg
		cluster.Columns = cols
	else
		for k = 1, nC do
			cluster.Cells[k] = { X = clusterRight - nC * C - (nC - 1) * cg + (k - 1) * (C + cg), Y = top + 10 }
		end
		cluster.Left = clusterRight - nC * C - (nC - 1) * cg
		cluster.Bottom = top + 10 + C
		cluster.Columns = nC
	end
	cluster.Right = clusterRight
	cluster.Top = touch and top + margin or top + 10
	out.Cluster = cluster

	-- RAIL ------------------------------------------------------------------------------------
	local nT = i.Tiles or 8
	local bandTop = top + (touch and 6 or 12)
	local bandBottom = touch and (bottom - thumb) or (bottom - 12)
	local avail = math.max(60, bandBottom - bandTop)
	local maxB = touch and (small and 56 or 66) or math.clamp(round(70 * s), 56, 72)
	local comfy = touch and 46 or 54
	local gap = touch and 6 or math.clamp(round(10 * s), 6, 10)
	local B, rows = railFit(nT, 1, avail, gap)
	local cols = 1
	-- One column when its buttons are comfortable and it does not fill the whole height (a
	-- full-height column is fine in portrait, where width is the scarce side).
	local single = math.min(B, maxB)
	local singleH = nT * round(single * (1 + LABEL_OUT)) + (nT - 1) * gap
	local portrait = h > w
	if B < comfy or (not portrait and singleH > avail * 0.88) then
		cols = 2
		B, rows = railFit(nT, 2, avail, gap)
		-- Three short columns before buttons get smaller than a fingertip.
		if B < (touch and 42 or 36) then
			cols = 3
			B, rows = railFit(nT, 3, avail, gap)
		end
	end
	B = math.max(32, math.min(B, maxB))
	local slotH = round(B * (1 + LABEL_OUT))
	local railH = rows * slotH + (rows - 1) * gap
	local railW = cols * B + (cols - 1) * gap
	local railX = left + margin
	local railY
	if touch then
		railY = bandTop + math.max(0, math.floor((avail - railH) / 2))
	else
		railY = math.floor(math.clamp(top + (h - railH) / 2, bandTop, math.max(bandTop, bandBottom - railH)))
	end
	local rail: any = { Size = B, Gap = gap, Columns = cols, Rows = rows, SlotH = slotH, Cells = {} }
	for k = 1, nT do
		local col = (k - 1) % cols
		local row = math.floor((k - 1) / cols)
		rail.Cells[k] = { X = railX + col * (B + gap), Y = railY + row * (slotH + gap) }
	end
	rail.Left, rail.Top, rail.Right, rail.Bottom = railX, railY, railX + railW, railY + railH
	rail.LabelH = math.clamp(round(B * 0.26), 11, 17)
	out.Rail = rail

	-- BAR -------------------------------------------------------------------------------------
	local barH = touch and math.clamp(round(34 * s), 28, 34) or math.clamp(round(40 * s), 32, 42)
	local pg = touch and 6 or 8
	local barY = top + (touch and 6 or 10)
	local pills = i.Pills or { 4.6, 3.6 }
	local function zone(rowsUsed: number): (number, number)
		local barBottom = barY + rowsUsed * barH + (rowsUsed - 1) * pg
		local zl = left + margin
		if rail.Top < barBottom + 6 then
			zl = rail.Right + 10
		end
		local zr = right - margin
		if cluster.Top < barBottom + 6 then
			zr = cluster.Left - 10
		end
		return zl, zr
	end
	local function widths(scale: number): { number }
		local list = {}
		for k, units in ipairs(pills) do
			list[k] = math.floor(units * barH * scale)
		end
		return list
	end
	local function rowWidth(list: { number }, from: number, to: number): number
		local total = 0
		for k = from, to do
			total += list[k]
		end
		return total + math.max(0, to - from) * pg
	end
	local list = widths(1)
	local n = #list
	local split = n -- pills 1..split on the first row
	local zl, zr = zone(1)
	local scale = 1
	if n > 0 and rowWidth(list, 1, n) > zr - zl then
		split = math.ceil(n / 2)
		zl, zr = zone(2)
		local widest = math.max(rowWidth(list, 1, split), rowWidth(list, split + 1, n))
		if widest > zr - zl then
			scale = math.max(0.6, (zr - zl) / widest)
			list = widths(scale)
		end
	end
	local bar: any = { Height = barH, Gap = pg, Cells = {}, Rows = split < n and 2 or 1, Scale = scale }
	local centre = left + w / 2
	local function placeRow(from: number, to: number, y: number)
		local width = rowWidth(list, from, to)
		local x = centre - width / 2
		x = math.clamp(x, zl, math.max(zl, zr - width))
		x = math.floor(x)
		for k = from, to do
			bar.Cells[k] = { X = x, Y = y, W = list[k] }
			x += list[k] + pg
		end
	end
	if n > 0 then
		placeRow(1, split, barY)
		if split < n then
			placeRow(split + 1, n, barY + barH + pg)
		end
	end
	bar.Top = barY
	bar.Bottom = barY + bar.Rows * barH + (bar.Rows - 1) * pg
	bar.Left, bar.Right = zl, zr
	bar.Unit = barH / 46 -- UIScale of the 46 px-tall money / level widgets
	out.Bar = bar

	-- FREE ZONE -------------------------------------------------------------------------------
	local freeL = rail.Right + 10
	local freeR = touch and (cluster.Left - 10) or (right - margin)
	local chipBottom = bar.Bottom + 4 + round(32 * bar.Unit)
	local freeTop = chipBottom + 4
	local freeBottom = touch and math.min(bottom - thumb, jumpY - 8) or (bottom - margin)
	if freeBottom < freeTop + 40 then
		freeBottom = math.min(bottom - margin, freeTop + 40)
	end
	out.Free = { Left = freeL, Right = math.max(freeL + 40, freeR), Top = freeTop, Bottom = freeBottom }
	local freeW = out.Free.Right - out.Free.Left
	local firstPill = bar.Cells[1]
	out.Chip = { X = firstPill and firstPill.X or freeL, Y = chipBottom, Scale = bar.Unit }
	out.Notice = {
		X = round((out.Free.Left + out.Free.Right) / 2),
		Y = freeTop + 2,
		W = math.max(150, math.min(touch and 264 or 320, freeW)),
		H = touch and 48 or 54,
	}
	if touch then
		out.Buff = { Right = cluster.Left - 8, Top = freeTop + 2, Bottom = jumpY - 8 }
	else
		out.Buff = { Right = right - margin, Top = cluster.Bottom + 12, Bottom = bottom - margin }
	end
	out.Clear = { X = out.Free.Left, Y = math.max(freeTop, freeBottom - 32) }
	out.Toast = {
		X = round((out.Free.Left + out.Free.Right) / 2),
		Y = freeTop + math.floor(math.max(0, freeBottom - freeTop) * 0.12),
		W = math.max(120, math.min(math.floor(w * 0.42), freeW - 16)),
		H = math.max(34, math.floor(h * 0.07)),
	}
	out.JumpX, out.JumpY, out.ThumbH = jumpX, jumpY, thumb
	return out
end

-- Axis-aligned overlap of two {X, Y, W, H} rectangles (tests).
function L.Overlaps(a: any, b: any): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

-- Every rectangle the layout places (tests and the Studio debug overlay).
function L.Rects(out: any): { any }
	local list = {}
	for k, cell in ipairs(out.Rail.Cells) do
		table.insert(list, { Name = "Rail" .. k, X = cell.X, Y = cell.Y, W = out.Rail.Size, H = out.Rail.SlotH })
	end
	for k, cell in ipairs(out.Cluster.Cells) do
		table.insert(list, { Name = "Cluster" .. k, X = cell.X, Y = cell.Y, W = out.Cluster.Size, H = out.Cluster.Size })
	end
	for k, cell in ipairs(out.Bar.Cells) do
		table.insert(list, { Name = "Pill" .. k, X = cell.X, Y = cell.Y, W = cell.W, H = out.Bar.Height })
	end
	return list
end

return L
