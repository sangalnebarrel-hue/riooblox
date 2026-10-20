-- THE DEAD YARD · the dog graveyard (ServerStorage.HalloweenBuild.Graveyard, WP2). Build-time only.
-- Model `Graveyard` under ctx.Root, field x 40..94, z 590..742 (west of the pit, seen from the boulevard over the fence).
-- Every Layout.DigPoints position stays clear (no solid part, no tall prop within 4.5 studs): each point gets a subtle,
-- non-solid patch of turned earth and (when it lies in the field) a headstone 5.9 studs south of it facing the lane, so
-- the Blood Moon dig spots read as graves. Markers: FogPoint (>= 10), GhostPath_1..6 (a loop through the field),
-- CrowPerch / BatRoost on the trees and the entrance arch, HwLantern on the arch lanterns, HwCandle on candle flames.
local K = require(script.Parent.Kit)
local Y = require(script.Parent.YardKit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi

local NAMES = { "REX", "BUDDY", "MAX", "LUNA", "BISCUIT", "SPOT", "BARON", "PICKLES", "FIDO", "COOKIE", "BONES", "ROVER", "DUKE",
	"PEANUT", "WAFFLES", "MOCHI", "BEAN", "NUGGET", "SIR WOOF", "LADY", "OREO", "TOFU", "BANJO", "ZIGGY", "PRETZEL", "MUFFIN" }
local PHRASES = { "GOOD BOY", "GOOD GIRL", "DUG TOO DEEP" } -- world strings that need RU (listed in the WP2 report)

return {
	Build = function(ctx)
		local L = ctx.Layout
		local G = L.Graveyard
		local y0 = L.FloorY
		local rng = Y.Rng(4401)
		local clear = Y.Keepout(L)
		local m = K.Model(ctx.Root, "Graveyard")
		local placed = {} -- {pos, radius} of solid props (spacing)
		local function free(pos, r)
			if not clear(pos, r + 4.6) then
				return false
			end
			for _, q in ipairs(placed) do
				local d = V3(pos.X - q[1].X, 0, pos.Z - q[1].Z).Magnitude
				if d < r + q[2] then
					return false
				end
			end
			return true
		end
		local function claim(pos, r)
			table.insert(placed, { pos, r })
		end
		local nameIdx = 0
		local function nextText()
			nameIdx += 1
			local r = rng:NextNumber()
			if r < .14 then
				return PHRASES[rng:NextInteger(1, #PHRASES)], false
			elseif r < .3 then
				return "R.I.P.", true
			end
			local n = NAMES[(nameIdx - 1) % #NAMES + 1]
			return n .. "\nR.I.P.", true
		end
		local function grave(cf, style)
			local text, noTr = nextText()
			local tm, top = Y.Tombstone(m, cf, style, rng, text, { NoTranslate = noTr })
			return tm, top
		end
		local function styleRoll()
			local r = rng:NextNumber()
			if r < .22 then
				return 1
			elseif r < .34 then
				return 2
			elseif r < .5 then
				return 3
			elseif r < .6 then
				return 4
			elseif r < .67 then
				return 5
			elseif r < .77 then
				return 6
			elseif r < .86 then
				return 7
			elseif r < .93 then
				return 8
			end
			return 9
		end

		-- 1. dig points: turned earth (non-solid) + a headstone south of each grave --------------------------
		local earth = K.Model(m, "DigGraves")
		for i, p in ipairs(L.DigPoints) do
			K.Ellipsoid(earth, "TurnedEarth", V3(5.4, .16, 3.6), CF(p.X, y0 + .03, p.Z) * ANG(0, rng:NextNumber(-.25, .25), 0), C(60, 45, 40), M.Mud)
			K.Ellipsoid(earth, "TurnedEarth", V3(3.4, .2, 2.2), CF(p.X + rng:NextNumber(-.6, .6), y0 + .05, p.Z + rng:NextNumber(-.4, .4)) * ANG(0, rng:NextNumber(0, PI), 0),
				C(72, 55, 46), M.Ground)
			for _ = 1, 3 do
				K.Ball(earth, "DirtClump", rng:NextNumber(.35, .6), CF(p.X + rng:NextNumber(-2.2, 2.2), y0 + .12, p.Z + rng:NextNumber(-1.3, 1.3)), C(78, 60, 50), M.Ground)
			end
			claim(p, 4.6)
			if i ~= 6 and i ~= 16 then -- D6 lies at the mausoleum steps, D16 next to ore node 10
				local hs = V3(p.X, y0, p.Z + 5.9)
				local cf = CF(hs) * ANG(0, rng:NextNumber(-.12, .12), 0) -- engraving faces -Z (the lane and the grave)
				grave(cf, ({ 1, 3, 1, 8, 3, 1, 5, 1, 3, 6, 1, 8, 3, 1, 9, 3 })[i])
				claim(hs, 1.8)
				if i % 3 == 1 then
					K.Candles(m, CF(hs + V3(i % 2 == 0 and 2.2 or -2.2, 0, .3)), 3, rng, { Light = i == 4 or i == 10, Spread = .5 })
				elseif i % 3 == 2 then
					-- dead flowers on the grave
					local fc = CF(hs + V3(i % 2 == 0 and -2 or 2, 0, .2))
					for f = 1, 3 do
						local tip = fc * V3((f - 2) * .25, .9 + f * .1, rng:NextNumber(-.15, .15))
						K.Bar(m, "FlowerStem", fc.Position, tip, .06, .06, C(70, 80, 50), M.SmoothPlastic)
						K.Ball(m, "DeadFlower", .32, CF(tip), ({ C(150, 70, 190), C(200, 90, 40), C(120, 40, 60) })[f], M.SmoothPlastic)
					end
				end
			end
		end

		-- 2. hero pieces: mourning dog statue + benches, iron family plots, open graves -----------------------------
		local function statue(base)
			local s = K.Model(m, "MourningDogStatue")
			local stone = C(176, 174, 188)
			local dark = C(120, 118, 134)
			K.Part(s, "StatueBase", V3(4.6, .6, 4.6), base * CF(0, .3, 0), C(80, 78, 92), M.Slate, Y.Solid())
			local die = K.Part(s, "StatueDie", V3(3.4, 2.4, 3.4), base * CF(0, 1.8, 0), dark, M.Slate, Y.Solid())
			K.Part(s, "StatueCap", V3(4, .45, 4), base * CF(0, 3.2, 0), C(150, 148, 162), M.Slate)
			local g = K.Sign(die, N.Front, "FOREVER A GOOD BOY", C(52, 48, 62), { PixelsPerStud = 24, Stroke = false, H = .4, W = .86, LightInfluence = .8 })
			local _ = g
			local t = base * CF(0, 3.42, 0)
			Y.DogStatue(s, t, { Bowed = true, Name = "MourningDog" })
			-- moss streaks + wreath at the plinth
			K.Part(s, "StatueMoss", V3(3.5, .14, .5), base * CF(.2, 3.45, -1.8), P.Moss, M.Grass)
			local wr = base * CF(0, 1.5, -1.76)
			K.CylZ(s, "Wreath", .3, 1.9, wr, C(46, 70, 44), M.Grass)
			K.CylZ(s, "WreathHole", .32, 1.1, wr, dark, M.Slate)
			for f = 0, 3 do
				local a = f / 4 * PI * 2 + .4
				K.Ball(s, "WreathFlower", .4, wr * CF(math.cos(a) * .72, math.sin(a) * .72, -.15), f % 2 == 0 and C(160, 80, 220) or C(255, 140, 50), M.SmoothPlastic)
			end
			K.Candles(s, base * CF(-1.6, .6, -1.6), 3, rng, { Light = true, Spread = .5 })
			K.Candles(s, base * CF(1.7, .6, -1.5), 2, rng, { Light = false, Spread = .4 })
			Y.AttachAt(die, "CrowPerch", (t * CF(.2, 5.1, .4)).Position)
			return s
		end
		local SP = V3(77, y0, 652)
		statue(CF(SP) * ANG(0, .36, 0))
		claim(SP, 3.6)
		for _, bz in ipairs({ -6, 6 }) do
			local bcf = CF(SP + V3(bz * .2, 0, bz)) * ANG(0, bz > 0 and 0 or PI, 0)
			K.Part(m, "BenchSeat", V3(4.4, .4, 1.4), bcf * CF(0, 1.05, 0), C(120, 118, 132), M.Slate, Y.Solid())
			for _, lx in ipairs({ -1.6, 1.6 }) do
				K.Part(m, "BenchLeg", V3(.6, .85, 1.2), bcf * CF(lx, .43, 0), C(90, 88, 102), M.Slate, Y.Solid())
			end
			K.Part(m, "BenchMoss", V3(1.2, .1, .8), bcf * CF(rng:NextNumber(-1, 1), 1.27, 0), P.Moss, M.Grass)
			claim(SP + V3(bz * .2, 0, bz), 2.4)
		end

		local function plot(cx, cz, w, d, gstyle)
			local c = V3(cx, y0, cz)
			local corners = { V3(cx - w / 2, y0, cz - d / 2), V3(cx + w / 2, y0, cz - d / 2), V3(cx + w / 2, y0, cz + d / 2), V3(cx - w / 2, y0, cz + d / 2) }
			for k = 1, 4 do
				local a, b = corners[k], corners[k % 4 + 1]
				if k == 1 then -- gate gap on the -Z side
					local mid = (a + b) / 2
					Y.IronFence(m, a, mid - V3(.8, 0, 0), { Height = 1.7, Spacing = 1.2, Finials = false }, rng)
					Y.IronFence(m, mid + V3(.8, 0, 0), b, { Height = 1.7, Spacing = 1.2, Finials = false }, rng)
				else
					Y.IronFence(m, a, b, { Height = 1.7, Spacing = 1.25, Finials = false }, rng)
				end
				K.Part(m, "PlotPost", V3(.32, 2.1, .32), CF(a + V3(0, 1.05, 0)), P.Iron, M.CorrodedMetal, Y.Solid())
				K.Ball(m, "PlotFinial", .42, CF(a + V3(0, 2.25, 0)), P.Iron, M.CorrodedMetal)
			end
			K.Part(m, "PlotGravel", V3(w - .3, .08, d - .3), CF(c + V3(0, .03, 0)), C(84, 80, 90), M.Pebble)
			grave(CF(c + V3(0, 0, d / 2 - 1.3)), gstyle)
			Y.Pumpkin(m, CF(c + V3(-w / 2 + .9, 0, -d / 2 + 1)) * ANG(0, .3, 0), 1.1, { Face = false, Lobes = 4 })
			claim(c, math.max(w, d) / 2 + .6)
		end
		plot(44, 616, 5.4, 6.4, 5)
		plot(77, 700, 5.4, 6.4, 2)

		local function openGrave(cx, cz, yaw)
			local cf = CF(cx, y0, cz) * ANG(0, yaw, 0)
			K.Part(m, "GraveHole", V3(2.6, .05, 4.6), cf * CF(0, .03, 0), C(12, 22, 14), M.Neon)
			for _, sx in ipairs({ -1, 1 }) do
				K.Part(m, "GraveLip", V3(.5, .3, 5.4), cf * CF(sx * 1.55, .13, 0), C(66, 50, 42), M.Ground)
				K.Part(m, "GraveLip", V3(3.6, .3, .5), cf * CF(0, .13, sx * 2.55), C(66, 50, 42), M.Ground)
			end
			K.Ellipsoid(m, "DirtMound", V3(3, 1.6, 4.6), cf * CF(3.1, .35, 0), C(74, 56, 46), M.Mud, Y.Solid())
			K.Rod(m, "ShovelHandle", (cf * CF(3.2, 1.2, .8)).Position, (cf * CF(3.6, 4.4, 1.2)).Position, .16, C(110, 80, 50), M.Wood)
			K.Part(m, "ShovelGrip", V3(.7, .16, .16), cf * CF(3.62, 4.45, 1.22), C(90, 64, 40), M.Wood)
			K.Part(m, "ShovelBlade", V3(.8, 1, .1), cf * CF(3.12, .9, .72) * ANG(0, .2, -.12), C(110, 108, 116), M.CorrodedMetal)
			K.Part(m, "CoffinLid", V3(1.7, .22, 4.4), cf * CF(-2.4, 1, 0) * ANG(0, 0, -1.15), C(70, 46, 40), M.WoodPlanks)
			K.Part(m, "CoffinCross", V3(.2, .1, 1.6), cf * CF(-2.33, 1.05, -.6) * ANG(0, 0, -1.15) * CF(0, .14, 0), P.Gold, M.Metal)
			Y.Marker(m, "FogPoint", (cf * CF(0, .4, 0)).Position)
			claim(V3(cx, y0, cz), 4)
		end
		openGrave(59, 646, .1)
		openGrave(44, 664, -.15)
		openGrave(74, 727, .2)

		-- 3. dead trees (well away from the dig spots so no branch hangs over them) --------------------------------
		local trees = {
			{ 41, 592, 14, true }, { 40.5, 640, 12.5 }, { 40.5, 690, 15, true }, { 59, 740.5, 13 },
			{ 79, 592, 12 }, { 93, 640, 13.5, true }, { 77, 677, 14 },
		}
		for k, t in ipairs(trees) do
			local pos = V3(t[1], y0, t[2])
			Y.Tree(m, CF(pos), t[3], Y.Rng(900 + k * 17), { Hollow = t[4], HollowDir = V3(1, 0, -1), HollowColor = k % 2 == 0 and Y.GLOW.Green or Y.GLOW.Orange,
				Perches = 2, Spread = 6.2 })
			claim(pos, 2.6)
		end

		-- 4. entrance arch from Hollow Lane (x 59, z 588.5) + iron fences either side ------------------------------
		local ax, az = 59, 588.6
		local arch = K.Model(m, "CemeteryArch")
		for _, sx in ipairs({ -1, 1 }) do
			local px = ax + sx * 4.4
			K.Part(arch, "ArchPillarFoot", V3(2, .7, 2), CF(px, y0 + .35, az), C(76, 72, 86), M.Cobblestone, Y.Solid())
			K.Part(arch, "ArchPillar", V3(1.5, 6.8, 1.5), CF(px, y0 + .7 + 3.4, az), C(96, 92, 108), M.Cobblestone, Y.Solid())
			local cap = K.Part(arch, "ArchPillarCap", V3(2, .5, 2), CF(px, y0 + 7.35, az), C(120, 116, 132), M.Slate)
			Y.Skull(arch, CF(px, y0 + 8.05, az - .1), .95, sx < 0 and Y.GLOW.Green or Y.GLOW.Purple)
			K.Attach(cap, "CrowPerch", CF(.6, .35, .5))
			-- lantern hanging on the lane side of each pillar
			local lcf = CF(px, y0 + 5.2, az - 1.35)
			K.Part(arch, "LanternBracket", V3(.2, .2, 1.2), CF(px, y0 + 6.8, az - .9), P.Iron, M.CorrodedMetal)
			K.Part(arch, "LanternHook", V3(.1, .6, .1), CF(px, y0 + 6.45, az - 1.35), P.Iron, M.CorrodedMetal)
			K.Lantern(arch, lcf, sx < 0 and Y.GLOW.Green or Y.GLOW.Purple, sx < 0 and "Green" or "Purple", { Range = 14, Brightness = .9 })
			-- the gate leaf, left open
			local hinge = CF(px - sx * .75, y0, az) * ANG(0, sx * 1.25, 0)
			local leafW = 3.6
			for _, yy in ipairs({ .5, 3.4, 5.1 }) do
				K.Part(arch, "GateRail", V3(leafW, .14, .14), hinge * CF(-sx * leafW / 2, yy, 0), P.Iron, M.CorrodedMetal)
			end
			for b = 0, 4 do
				local bx = -sx * (.25 + b * (leafW - .5) / 4)
				K.Part(arch, "GateBar", V3(.12, 5 + (b % 2) * .4, .12), hinge * CF(bx, 2.6 + (b % 2) * .2, 0), P.Iron, M.CorrodedMetal)
			end
			claim(V3(px, y0, az), 1.4)
		end
		-- the iron arch over the opening (two concentric arcs with a moon plate in the middle)
		local R1, R2 = 4.4, 3.7
		local prev1, prev2
		for k = 0, 6 do
			local a = PI - k / 6 * PI
			local p1 = V3(ax + math.cos(a) * R1, y0 + 7.5 + math.sin(a) * 2.6, az)
			local p2 = V3(ax + math.cos(a) * R2, y0 + 7.5 + math.sin(a) * 2.1, az)
			if prev1 then
				K.Bar(arch, "ArchIron", prev1, p1, .2, .2, P.Iron, M.CorrodedMetal)
				if k % 2 == 0 then
					K.Bar(arch, "ArchIron", prev2, p2, .14, .14, P.Iron, M.CorrodedMetal)
				end
			end
			prev1, prev2 = p1, p2
		end
		local plate = K.Part(arch, "ArchPlate", V3(4.6, 1.15, .14), CF(ax, y0 + 8.75, az - .05), C(40, 30, 56), M.Metal)
		K.Part(arch, "ArchPlateTrim", V3(4.9, 1.4, .1), CF(ax, y0 + 8.75, az + .07), P.Iron, M.CorrodedMetal)
		K.Sign(plate, N.Front, "CEMETERY", P.Bone, { PixelsPerStud = 24, H = .74, StrokeColor = C(70, 30, 110) })
		-- crescent moon on top of the arch
		K.CylZ(arch, "ArchMoon", .16, 1.8, CF(ax, y0 + 10.7, az), C(230, 220, 160), M.Neon)
		K.CylZ(arch, "ArchMoonCut", .2, 1.55, CF(ax + .45, y0 + 10.85, az), C(30, 24, 40), M.SmoothPlastic)
		-- fences either side of the arch
		Y.IronFence(m, V3(43.5, y0, az), V3(53.3, y0, az), { Height = 2.8, Spacing = 1.35, Solid = true }, rng)
		Y.IronFence(m, V3(64.7, y0, az), V3(74.5, y0, az), { Height = 2.8, Spacing = 1.35, Solid = true, Broken = .15 }, rng)
		for _, fx in ipairs({ 43.5, 74.5 }) do
			K.Part(m, "FencePier", V3(1.2, 3.4, 1.2), CF(fx, y0 + 1.7, az), C(90, 86, 100), M.Cobblestone, Y.Solid())
			Y.Pumpkin(m, CF(fx, y0 + 3.4, az) * ANG(0, .3, 0), 1.2, { Lobes = 4 })
		end

		-- 5. low broken wall on the pit side + scattered stones ---------------------------------------------------
		for _, seg in ipairs({ { 596, 620 }, { 634, 658 }, { 684, 702 } }) do
			local z = seg[1]
			while z < seg[2] - .5 do
				local len = math.min(rng:NextNumber(3.5, 6), seg[2] - z)
				local h = rng:NextNumber(.9, 1.7)
				K.Part(m, "LowWall", V3(1.1, h, len - .15), CF(93.5 + rng:NextNumber(-.08, .08), y0 + h / 2, z + len / 2), C(84, 80, 94):Lerp(P.Ink, rng:NextNumber(0, .25)), M.Cobblestone, Y.Solid())
				if rng:NextNumber() < .5 then
					K.Part(m, "LowWallCap", V3(1.35, .22, len * .7), CF(93.5, y0 + h + .1, z + len / 2) * ANG(0, 0, rng:NextNumber(-.06, .06)), C(116, 112, 126), M.Slate)
				end
				z += len
			end
			K.Part(m, "FallenStone", V3(1, .7, 1.4), CF(91.6, y0 + .3, seg[2] + 1.2) * ANG(.2, .6, .1), C(84, 80, 94), M.Cobblestone)
		end

		-- 6. more tombstones in loose rows between the grave columns -------------------------------------------
		local rows = { 42.5, 58.5, 60.5, 76.5, 78.5, 90.5 }
		local count = 0
		for _, rx in ipairs(rows) do
			local z = G.Z0 + 6 + rng:NextNumber(0, 6)
			while z < G.Z1 - 4 do
				local pos = V3(rx + rng:NextNumber(-.8, .8), y0, z)
				if count < 28 and free(pos, 2.1) then
					local yaw = rng:NextNumber(-.3, .3) -- engravings face the lane (-Z)
					if rx < 45 then
						yaw = PI / 2 + rng:NextNumber(-.25, .25) -- the west row faces the boulevard (-X)
					end
					grave(CF(pos) * ANG(0, yaw, 0), styleRoll())
					claim(pos, 2.1)
					count += 1
					if rng:NextNumber() < .22 then
						K.Mushrooms(m, CF(pos + V3(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(.8, 1.5))), 3,
							rng, rng:NextNumber() < .5 and C(120, 255, 140) or C(170, 110, 255))
					end
				end
				z += rng:NextNumber(9, 14)
			end
		end
		m:SetAttribute("Tombstones", count + #L.DigPoints - 1 + 2)

		-- 7. candles + glowing mushrooms + bone scatter -----------------------------------------------------------
		for k, c in ipairs({ { 47, 640 }, { 63, 676 }, { 82, 616 }, { 61, 705 }, { 88, 690 } }) do
			local pos = V3(c[1], y0, c[2])
			if clear(pos, 5) then
				K.Candles(m, CF(pos), 4, rng, { Light = k == 2, Spread = .8 })
			end
		end
		for _, c in ipairs({ { 45, 604 }, { 56, 690 }, { 82, 660 }, { 89, 734 }, { 62, 600 }, { 73, 742 } }) do
			local pos = V3(c[1], y0, c[2])
			if clear(pos, 5) then
				K.Mushrooms(m, CF(pos), 4, rng, rng:NextNumber() < .6 and C(120, 255, 140) or C(170, 110, 255))
			end
		end
		Y.BonePile(m, CF(56.5, y0, 731), rng, 3, true)
		Y.BonePile(m, CF(85.5, y0, 676), rng, 2, false)

		-- 8. fog + ghost paths ------------------------------------------------------------------------------------
		for _, f in ipairs({ { 46, 598 }, { 59, 616 }, { 46, 676 }, { 59, 700 }, { 77, 610 }, { 86, 646 }, { 77, 690 }, { 90, 712 },
			{ 46, 730 }, { 66, 734 }, { 59, 662 } }) do
			Y.Marker(m, "FogPoint", V3(f[1], y0 + .4, f[2]))
		end
		for i, g in ipairs({ { 59, 600 }, { 43, 646 }, { 59, 696 }, { 76, 734 }, { 92, 690 }, { 82, 622 } }) do
			Y.Marker(m, "GhostPath_" .. i, V3(g[1], y0 + 3.2, g[2]))
		end
	end,
}
