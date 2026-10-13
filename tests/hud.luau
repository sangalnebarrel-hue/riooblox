--!nolint
-- HUD layout maths (Modules.HUDLayout, applied by UITheme.LayoutHUD): every device class keeps the
-- rail, the currency bar and the cluster inside the safe area, apart from each other and clear of
-- the touch thumbstick and jump button; touch targets stay large enough. lune run tests/hud.luau
local HUD = require("../src/StarterGui/ScreenGui/Modules/HUDLayout")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

-- Safe areas as Roblox reports them (top bar, notch and home indicator excluded); the jump
-- button rule of UITheme.TouchReserve (70 px on small screens, 120 px otherwise).
local function device(name, sw, sh, touch, inset)
	inset = inset or {}
	local left, top = inset.Left or 0, inset.Top or 58
	local w = sw - left - (inset.Right or 0)
	local h = sh - top - (inset.Bottom or 0)
	local small = math.min(w, h) <= 500
	local size = small and 70 or 120
	return {
		Name = name,
		Left = left,
		Top = top,
		Width = w,
		Height = h,
		Touch = touch,
		JumpX = left + w - (size * 1.5 - 10),
		JumpY = top + h - (small and size + 20 or size * 1.75),
		Thumb = small and 100 or 170,
		Tiles = 8,
		Cluster = 4,
		Pills = { 4.6, 3, 3, 3.6 },
	}
end

local DEVICES = {
	device("desktop 1920x1080", 1920, 1080, false),
	device("desktop 1366x768", 1366, 768, false),
	device("desktop 1280x720", 1280, 720, false),
	device("desktop 1024x600", 1024, 600, false),
	device("desktop 800x600", 800, 600, false),
	device("phone portrait 360x640", 360, 640, true, { Top = 44 }),
	device("phone portrait 390x844", 390, 844, true, { Top = 47, Bottom = 34 }),
	device("phone landscape 812x375", 812, 375, true, { Left = 44, Right = 44, Top = 36, Bottom = 21 }),
	device("phone landscape 640x360", 640, 360, true, { Top = 36 }),
	device("phone landscape 812x375 tall topbar", 812, 375, true, { Left = 44, Right = 44, Top = 58, Bottom = 21 }),
	device("tablet 1024x768", 1024, 768, true),
	device("tablet portrait 768x1024", 768, 1024, true),
}

local function inside(r, d, what)
	truthy(r.X >= d.Left - 0.5 and r.Y >= d.Top - 0.5, what .. " starts outside the safe area")
	truthy(r.X + r.W <= d.Left + d.Width + 0.5 and r.Y + r.H <= d.Top + d.Height + 0.5, what .. " ends outside the safe area")
end

for _, d in ipairs(DEVICES) do
	test(d.Name, function()
		local out = HUD.Compute(d)
		local rects = HUD.Rects(out)
		truthy(#rects == 8 + 4 + 4, "rect count " .. #rects)
		for _, r in ipairs(rects) do
			inside(r, d, r.Name)
		end
		for a = 1, #rects do
			for b = a + 1, #rects do
				truthy(not HUD.Overlaps(rects[a], rects[b]), rects[a].Name .. " overlaps " .. rects[b].Name)
			end
		end
		-- Touch targets and readable labels.
		truthy(out.Rail.Size >= (d.Touch and 40 or 48), "rail button " .. out.Rail.Size .. " px")
		truthy(out.Cluster.Size >= (d.Touch and 40 or 36), "cluster button " .. out.Cluster.Size .. " px")
		truthy(out.Rail.LabelH >= 11, "label height")
		truthy(out.Bar.Height >= 28, "bar height")
		if d.Touch then
			local jump = { X = d.JumpX, Y = d.JumpY, W = d.Left + d.Width - d.JumpX, H = d.Top + d.Height - d.JumpY }
			local stick = { X = d.Left, Y = d.Top + d.Height - d.Thumb, W = math.floor(d.Width * 0.4), H = d.Thumb }
			for _, r in ipairs(rects) do
				truthy(not HUD.Overlaps(r, jump), r.Name .. " covers the jump button")
				truthy(not HUD.Overlaps(r, stick), r.Name .. " covers the thumbstick")
			end
			truthy(out.Buff.Bottom <= d.JumpY, "boosts reach the jump button")
		end
		-- The free zone exists and sits between the groups.
		truthy(out.Free.Right - out.Free.Left >= 40, "free zone width")
		truthy(out.Free.Left >= out.Rail.Right, "free zone left of the rail")
		truthy(out.Notice.W >= 150, "notice width")
		truthy(out.Chip.Y > out.Bar.Bottom, "income chip below the bar")
	end)
end

test("one column on big screens, more on landscape phones", function()
	local desk = HUD.Compute(DEVICES[1])
	truthy(desk.Rail.Columns == 1, "desktop columns " .. desk.Rail.Columns)
	truthy(desk.Rail.Size >= 64, "desktop button size " .. desk.Rail.Size)
	local land = HUD.Compute(DEVICES[8])
	truthy(land.Rail.Columns >= 2, "landscape phone columns " .. land.Rail.Columns)
	local portrait = HUD.Compute(DEVICES[6])
	truthy(portrait.Rail.Columns == 1, "portrait phone columns " .. portrait.Rail.Columns)
	truthy(portrait.Bar.Rows == 2, "portrait bar wraps into two rows")
	truthy(desk.Bar.Rows == 1, "desktop bar is one row")
end)

test("the leaderboard pushes the desktop cluster left", function()
	local d = table.clone(DEVICES[1])
	local plain = HUD.Compute(d)
	d.PlayerList = true
	local shifted = HUD.Compute(d)
	truthy(shifted.Cluster.Right <= plain.Cluster.Right - 190, "cluster moved")
end)

test("fewer pills and cluster buttons still lay out", function()
	local d = table.clone(DEVICES[6])
	d.Pills = { 4.6, 3.6 }
	d.Cluster = 3
	local out = HUD.Compute(d)
	truthy(#out.Bar.Cells == 2 and #out.Cluster.Cells == 3, "counts")
	for _, r in ipairs(HUD.Rects(out)) do
		inside(r, d, r.Name)
	end
end)

print(string.format("hud: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("hud tests failed")
end
