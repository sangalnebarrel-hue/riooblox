-- THE UNDERYARD · UNDERCRYPT (Seal IV: HOLLOW MINE) — ServerStorage.UnderyardBuild.Undercrypt, WP-H3.
-- Build-time builder (Order 51) run by tools/edits/40_underyard.luau; saved as the model 40_Underyard.Undercrypt
-- (attribute UyDistrict = "Undercrypt"). DESIGN §7, §8.4 item 4, §22.6. Coordinates: UnderyardLayout.Undercrypt /
-- MineNodes / Gates / ChoirPaths / Districts (never moved). The district is a crooked rock hill that swallowed a
-- catacomb: you walk from the gate over a forecourt into a skull-crowned mouth, down a timbered ramp, into a cavern
-- whose floor is the Hollow Mine.
--   * own ground: the forecourt + west strip (top y 0), the cavern floor (top Undercrypt.FloorY = -16, covering the
--     Undercrypt.Floor box), the hill (roof slabs, flanks, southern massif + crags) over and around the cavern.
--   * THE CATACOMB MOUTH at Undercrypt.Entrance: pointed arch of crooked voussoirs on bone-wrapped pillars, a giant dog
--     skull keystone (violet eyes), a raised portcullis, hanging skull lanterns; a short paved tunnel to
--     Undercrypt.RampTop, then the RAMP (12 wide) down to Undercrypt.RampBottom on the mine floor, under an inner arch.
--   * the cavern: rock walls with bone walls (ossuary rows of skulls + bone ends), crypt niches with skull lanterns,
--     timber supports, three rock pillars, a ROCK CEILING (underside y +2) with five LIGHT-SHAFT GAPS (moon-blue shafts +
--     SpotLights), violet ore seams with crystals, a mine-rail loop with carts, the RESPAWN ALCOVE at Undercrypt.Spawn
--     (rune circle under the spawn, shrine, bell) and a CRATER RING at every L.MineNodes point (the ore spawns at runtime;
--     nothing taller than 1 stud stands within r 6 of a node: tests/underyard_districts_h3.luau checks it).
--   * the surface: forecourt rails + cart, skull lantern posts, miners' graves, dead trees, a sealed side adit on the west
--     flank, and a crooked HEADFRAME (winding tower) over the central shaft as the district's silhouette.
-- Seal state (§7.3): the forecourt lanterns + the headframe lamp carry UyLightAtSeal = 4 (they light up when the player
-- clears Seal IV); the cavern stays lit for the run. Budgets: <= 3 200 parts, <= 30 lights (reported through ctx.Note).
local G = require(script.Parent.GothicProps)
local K, Y = G.K, G.Y
local COL = G.Col
local C = Color3.fromRGB
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local PI = math.pi

local SEAL = 4 -- HOLLOW MINE
local ROOF_Y = 2 -- cavern ceiling underside
local ROOF_T = 4.5 -- ceiling slab thickness
local NODE_CLEAR = 6 -- nothing taller than 1 stud within this radius of a mine node
local ROCK = { C(66, 60, 72), C(58, 52, 64), C(76, 70, 80), C(52, 48, 58), C(70, 62, 66) }
local FLOOR = C(50, 46, 56)
local EARTH = C(62, 52, 50)
local CRYSTAL = C(176, 110, 255)

local function districtBox(L, name)
	for _, d in ipairs(L.Districts) do
		if d.Name == name then
			return d
		end
	end
	error("UnderyardLayout.Districts has no " .. name)
end

return {
	Order = 51,
	Build = function(ctx)
		local L = ctx.Layout
		local U = L.Undercrypt
		local FY = U.FloorY
		local box = districtBox(L, "Undercrypt")
		local X0, X1, Z0, Z1 = box.Min.X, box.Max.X, box.Min.Z, box.Max.Z
		local FL = U.Floor
		local FX0, FX1, FZ0, FZ1 = FL.Min.X, FL.Max.X, FL.Min.Z, FL.Max.Z
		local E, RT, RB, SP = U.Entrance, U.RampTop, U.RampBottom, U.Spawn
		local rng = G.Rng(51923)

		local root = ctx.Model("Undercrypt")
		root:SetAttribute("UyDistrict", "Undercrypt")
		root:SetAttribute("Seal", SEAL)
		local function sub(name)
			return K.Model(root, name)
		end
		local ground, hill, cavern, mouth, mine, dressing, lamps, fxm =
			sub("Ground"), sub("Hill"), sub("Cavern"), sub("CatacombMouth"), sub("MineFloor"), sub("Dressing"), sub("Lamps"), nil
		fxm = G.FXModel(root, "CryptFX")

		local function at(x, y, z)
			return CF(x, y, z)
		end
		local function rockCol()
			return ROCK[rng:NextInteger(1, #ROCK)]
		end
		local function rock(parent, size: Vector3, cf: CFrame, color: Color3?)
			return K.Part(parent, "Rock", size, cf, color or rockCol(), M.Slate, G.Solid())
		end
		local nodes = L.MineNodes
		-- nearest node distance (flat) from a floor point
		local function nodeDist(p: Vector3): number
			local best = math.huge
			for _, n in ipairs(nodes) do
				best = math.min(best, G.Flat(p, n))
			end
			return best
		end
		local function clearOfNodes(p: Vector3, radius: number): boolean
			return nodeDist(p) > NODE_CLEAR + radius
		end

		local lights = 0
		local function seam(parent, a: Vector3, b: Vector3, n: Vector3, lit: boolean)
			local prev = a
			local segs = 5
			for k = 1, segs do
				local q = a:Lerp(b, k / segs) + V3(0, rng:NextNumber(-1.2, 1.2), 0) * (k < segs and 1 or 0)
				K.Bar(parent, "OreSeam", prev + n * .1, q + n * .1, .35, .35, CRYSTAL, M.Neon, { Transparency = .05 })
				prev = q
			end
			for k = 1, 3 do
				local p = a:Lerp(b, rng:NextNumber(.1, .9)) + n * .5
				local cf = K.Look(p, p + n) * ANG(-PI / 2 + rng:NextNumber(-.4, .4), 0, rng:NextNumber(-.4, .4))
				K.Wedge(parent, "OreCrystal", V3(.7, rng:NextNumber(1.2, 2.2), .7), cf * CF(0, .6, 0), CRYSTAL:Lerp(C(230, 200, 255), rng:NextNumber(0, .4)), M.Neon, { Transparency = .1 })
			end
			if lit then
				local holder = K.Part(parent, "SeamGlow", V3(.3, .3, .3), CF(a:Lerp(b, .5) + n * 1.2), CRYSTAL, nil, { Transparency = 1 })
				K.Light(holder, CRYSTAL, 16, .8):SetAttribute("HwBaseBrightness", .8)
				lights += 1
			end
		end

		-- corridor frames: tunnel E -> RT, ramp RT -> RB
		local t1 = V3(RT.X - E.X, 0, RT.Z - E.Z).Unit
		local rd = V3(RB.X - RT.X, 0, RB.Z - RT.Z)
		local rampLen = rd.Magnitude
		rd = rd.Unit
		local lat1 = V3(-t1.Z, 0, t1.X) -- tunnel left (west-ish)
		local latR = V3(-rd.Z, 0, rd.X)
		local RW = 12 -- ramp / tunnel width
		local CORR_Y = 9.7 -- tunnel / upper-ramp ceiling underside (just above the mouth's opening)
		local JT = .6 -- junction (inner arch) at this fraction down the ramp
		local J = RT:Lerp(RB, JT)

		--------------------------------------------------------------------------------------------- surface ground
		K.Part(ground, "ForecourtGround", V3(X1 - X0, 4, 24), at((X0 + X1) / 2, -2, Z0 + 12), EARTH, M.Ground, G.Solid())
		K.Part(ground, "WestStripGround", V3(22, 4, Z1 - Z0 - 24), at(X0 + 11, -2, (Z0 + 24 + Z1) / 2), EARTH:Lerp(COL.Slate, .2), M.Ground, G.Solid())
		-- worn cobble path from the gate to the mouth (flagstones, flush + .05)
		do
			local gate = L.Gates.Undercrypt.Position
			local g2m = V3(E.X - gate.X, 0, E.Z - gate.Z)
			local a, b = gate + g2m * ((X0 + 2 - gate.X) / g2m.X), V3(E.X, 0, E.Z) - t1 * 3 -- from the box edge to the mouth
			local len = G.Flat(a, b)
			local n = math.floor(len / 2.6)
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				for _, s in ipairs({ -1, 0, 1 }) do
					if rng:NextNumber() > .2 then
						local dir = V3(b.X - a.X, 0, b.Z - a.Z).Unit
						local side = V3(-dir.Z, 0, dir.X)
						local q = p + side * s * 2.6 + side * rng:NextNumber(-.4, .4)
						K.Part(ground, "PathFlag", V3(rng:NextNumber(1.8, 2.5), .12, rng:NextNumber(1.6, 2.3)), at(q.X, .04, q.Z) * ANG(0, rng:NextNumber(0, PI), 0),
							C(84, 78, 88):Lerp(C(60, 56, 64), rng:NextNumber(0, 1)), M.Slate)
					end
				end
			end
		end

		------------------------------------------------------------------------------------------------- cavern floor
		K.Part(cavern, "MineFloorSlab", V3(FX1 - FX0 + 12, 4, FZ1 - FZ0 + 12), at((FX0 + FX1) / 2, FY - 2, (FZ0 + FZ1) / 2), FLOOR, M.Slate, G.Solid())

		-- wall run along an inner-face line p -> q (n = unit normal into the cavern); returns face frames for dressing
		local function wallRun(parent, p: Vector3, q: Vector3, n: Vector3, y0: number, y1: number, opts)
			opts = opts or {}
			local len = G.Flat(p, q)
			local dir = V3(q.X - p.X, 0, q.Z - p.Z).Unit
			local nb = math.max(1, math.floor(len / (opts.Step or 11) + .5))
			for k = 0, nb - 1 do
				local s = (k + .5) / nb
				local c = p:Lerp(q, s)
				local inset = rng:NextNumber(-.3, opts.Bulge or .6)
				local depth = 6
				local centre = V3(c.X, (y0 + y1) / 2, c.Z) - n * (depth / 2 - inset)
				local cf = K.Look(centre, centre + n) * ANG(rng:NextNumber(-.04, .04), rng:NextNumber(-.06, .06), rng:NextNumber(-.03, .03))
				rock(parent, V3(len / nb + 1.6, y1 - y0 + rng:NextNumber(0, 1.2), depth), cf)
				-- a lumpy boulder at the foot of every other block (kept low, away from the nodes)
				if opts.Boulders and k % 2 == 0 then
					local bp = V3(c.X, y0, c.Z) + n * 1.2 + dir * rng:NextNumber(-3, 3)
					if clearOfNodes(bp, 2) then
						rock(parent, V3(rng:NextNumber(2.5, 4), rng:NextNumber(1.5, 3.2), rng:NextNumber(2, 3)),
							at(bp.X, y0 + 1, bp.Z) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3)))
					end
				end
			end
		end
		local function face(p: Vector3, n: Vector3, y: number): CFrame -- a frame on a wall face, -Z into the room
			return K.Look(V3(p.X, y, p.Z), V3(p.X, y, p.Z) + n)
		end

		-- the four cavern walls (the corridor + alcove take the north-west corner)
		local wallY0, wallY1 = FY - 1, ROOF_Y + 1.5
		local cornerE = RB + rd * 0 + latR * -(RW / 2 + 1) -- bottom-east corner of the ramp corridor
		wallRun(cavern, V3(cornerE.X + 2, 0, FZ0), V3(FX1, 0, FZ0), V3(0, 0, 1), wallY0, wallY1, { Boulders = true })
		wallRun(cavern, V3(FX1, 0, FZ0), V3(FX1, 0, FZ1), V3(-1, 0, 0), wallY0, wallY1, { Boulders = true })
		wallRun(cavern, V3(FX1, 0, FZ1), V3(FX0, 0, FZ1), V3(0, 0, -1), wallY0, wallY1, { Boulders = true })
		local ALC = { Z0 = 2524, Z1 = 2536, Back = FX0 - 5 } -- respawn alcove recess (west of the spawn)
		wallRun(cavern, V3(FX0, 0, FZ1), V3(FX0, 0, ALC.Z1 + 1), V3(1, 0, 0), wallY0, wallY1, { Boulders = true })
		wallRun(cavern, V3(ALC.Back, 0, ALC.Z1 + .5), V3(ALC.Back, 0, ALC.Z0 - 1), V3(1, 0, 0), wallY0, wallY1, { Bulge = .2, Step = 7 })
		rock(cavern, V3(FX0 - ALC.Back + 1, wallY1 - wallY0, 3), at((FX0 + ALC.Back) / 2, (wallY0 + wallY1) / 2, ALC.Z1 + 2), ROCK[2])

		----------------------------------------------------------------------------------------- corridor + the ramp
		-- tunnel floor (paved, +.05 over the forecourt), ramp wedge, corridor walls, corridor roof, inner-arch face
		do
			local tc = E:Lerp(RT, .5) - t1 * 1.5
			local tl = G.Flat(E, RT) + 5
			K.Part(mouth, "TunnelFloor", V3(RW + 1, 4, tl), K.Look(V3(tc.X, -1.95, tc.Z), V3(tc.X, -1.95, tc.Z) + t1), C(78, 72, 82), M.Cobblestone, G.Solid())
			local rc = RT:Lerp(RB, .5)
			-- the WedgePart's high edge is at its -Z: point -Z up-ramp
			K.Wedge(mouth, "Ramp", V3(RW, RT.Y - RB.Y, rampLen), K.Look(V3(rc.X, (RT.Y + RB.Y) / 2, rc.Z), V3(rc.X, (RT.Y + RB.Y) / 2, rc.Z) - rd),
				C(70, 64, 74), M.Cobblestone, G.Solid())
			-- timber edging + cross boards on the slope (decor, flush on the surface)
			local slope = (RB - RT).Unit
			for _, s in ipairs({ -1, 1 }) do
				local a = RT + latR * s * (RW / 2 - .4) + V3(0, .25, 0)
				local b = RB + latR * s * (RW / 2 - .4) + V3(0, .25, 0)
				K.Bar(mouth, "RampEdgeBeam", a, b, .7, .6, COL.TimberDark, M.Wood)
			end
			local nboards = 9
			for k = 1, nboards do
				local p = RT:Lerp(RB, (k - .5) / nboards) + V3(0, .12, 0)
				K.Part(mouth, "RampBoard", V3(RW - 1.4, .2, .9), K.Look(p, p + slope) * ANG(0, 0, 0), COL.Timber:Lerp(COL.TimberDark, rng:NextNumber(0, .6)), M.Wood)
			end
			-- corridor walls: tunnel pair (y -1..14) + ramp pair (upper: -17..14, lower: -17..ROOF_Y + 4.5)
			for _, s in ipairs({ -1, 1 }) do
				local off = RW / 2 + 3
				local a = E + lat1 * s * off + t1 * 1.6
				local b = RT + lat1 * s * off
				local mid = a:Lerp(b, .5)
				rock(mouth, V3(6, 15, G.Flat(a, b) + 2), K.Look(V3(mid.X, 6.5, mid.Z), V3(mid.X, 6.5, mid.Z) + t1) * ANG(0, rng:NextNumber(-.03, .03), 0))
				local r0 = RT + latR * s * off
				local rj = J + latR * s * off
				-- the west wall stops short of the foot: the respawn alcove opens there
				local r1 = s > 0 and RT:Lerp(RB, .82) + latR * s * off or RB + latR * s * off + rd * 2
				local m0, m1 = r0:Lerp(rj, .5), rj:Lerp(r1, .5)
				rock(mouth, V3(6, 31, G.Flat(r0, rj) + 2), K.Look(V3(m0.X, -1.5, m0.Z), V3(m0.X, -1.5, m0.Z) + rd))
				local ym = (ROOF_Y + 4.5 + FY - 1) / 2
				rock(mouth, V3(6, ROOF_Y + 4.5 - FY + 1, G.Flat(rj, r1) + 1), K.Look(V3(m1.X, ym, m1.Z), V3(m1.X, ym, m1.Z) + rd))
			end
			-- corridor roof (underside +12) from the mouth to the junction, and the inner-arch face closing it
			local ra, rb = E + t1 * .5, J
			local rmid = ra:Lerp(rb, .5)
			rock(hill, V3(RW + 14, 4.5, G.Flat(ra, rb) + 3), K.Look(V3(rmid.X, CORR_Y + 2.25, rmid.Z), V3(rmid.X, CORR_Y + 2.25, rmid.Z) + (rb - ra).Unit), ROCK[3])
			rock(hill, V3(RW + 12, CORR_Y + 4.5 - ROOF_Y, 2.5), K.Look(V3(J.X, (CORR_Y + 4.5 + ROOF_Y) / 2, J.Z), V3(J.X, (CORR_Y + 4.5 + ROOF_Y) / 2, J.Z) + rd), ROCK[1])
		end

		---------------------------------------------------------------------------------------------- roof + shafts
		local XE = { 104, 119, 134, 149, 164, 179, 194, 212 }
		local ZE = { 2511, 2525, 2539, 2553, 2567, 2581, 2595, 2609, 2622 }
		local GAPS = { -- {ix, iz, beam offset x, z}: cells left open as light shafts
			{ 3, 3, 0, 0 }, { 5, 3, -1, 0 }, { 2, 6, .5, -2 }, { 6, 6, 0, 0 }, { 4, 7, 0, 0 },
		}
		local function isGap(ix, iz)
			for _, g in ipairs(GAPS) do
				if g[1] == ix and g[2] == iz then
					return true
				end
			end
			return false
		end
		for ix = 1, #XE - 1 do
			for iz = 1, #ZE - 1 do
				if not isGap(ix, iz) then
					local cx, cz = (XE[ix] + XE[ix + 1]) / 2, (ZE[iz] + ZE[iz + 1]) / 2
					local w, d = XE[ix + 1] - XE[ix] + 2.2, ZE[iz + 1] - ZE[iz] + 2.2
					local extra = rng:NextNumber(0, 2.2)
					local y = ROOF_Y + (ROOF_T + extra) / 2 + rng:NextNumber(-.4, .5)
					rock(hill, V3(w, ROOF_T + extra, d), at(cx, y, cz) * ANG(rng:NextNumber(-.04, .04), rng:NextNumber(-.08, .08), rng:NextNumber(-.04, .04)))
					-- rock clusters on top: the hill top reads as a broken crust, not a floor
					local nlumps = rng:NextNumber() < .65 and rng:NextInteger(1, 2) or 0
					for _ = 1, nlumps do
						local lw, lh = rng:NextNumber(5, 10), rng:NextNumber(1.5, 4.5)
						rock(hill, V3(lw, lh, lw * rng:NextNumber(.5, 1)),
							at(cx + rng:NextNumber(-4.5, 4.5), ROOF_Y + ROOF_T + extra + lh * .3, cz + rng:NextNumber(-4.5, 4.5)) * ANG(rng:NextNumber(-.15, .15), rng:NextNumber(0, PI), rng:NextNumber(-.15, .15)))
					end
				end
			end
		end
		local shaftTops = {}
		for gi, g in ipairs(GAPS) do
			local x0, x1, z0, z1 = XE[g[1]], XE[g[1] + 1], ZE[g[2]], ZE[g[2] + 1]
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			-- jagged rims: broken chunks overhanging two edges of the hole
			for k = 1, 3 do
				local ex = k == 1 and x0 + 1.5 or (k == 2 and x1 - 1.5 or cx + rng:NextNumber(-3, 3))
				local ez = k == 3 and (gi % 2 == 0 and z0 + 1.2 or z1 - 1.2) or cz + rng:NextNumber(-4, 4)
				rock(hill, V3(rng:NextNumber(3, 5), rng:NextNumber(2.5, 4), rng:NextNumber(3, 5)),
					at(ex, ROOF_Y + 1.8, ez) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, PI), rng:NextNumber(-.4, .4)))
			end
			-- the light shaft: two translucent beams (tilted towards the moon), a floor glow and a SpotLight
			local bx, bz = cx + g[3], cz + g[4]
			local top = V3(bx - 1.2, ROOF_Y + ROOF_T + 2, bz - 1.6)
			local bot = V3(bx, FY + .05, bz)
			local beamW = 6
			K.Bar(cavern, "LightShaft", top, bot, beamW, beamW, COL.Moon, M.Neon, { Transparency = .9 })
			K.Bar(cavern, "LightShaftCore", top, bot, beamW * .55, beamW * .55, C(200, 225, 255), M.Neon, { Transparency = .86 })
			K.CylY(cavern, "ShaftGlow", .06, beamW + 2.5, at(bot.X, FY + .04, bot.Z), COL.Moon, M.Neon, { Transparency = .78 })
			local holder = K.Part(cavern, "ShaftLight", V3(.4, .4, .4), at(cx, ROOF_Y + .5, cz), COL.Moon, nil, { Transparency = 1 })
			local sl = K.Light(holder, COL.Moon, 34, 2.2, "SpotLight") :: SpotLight
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 70
			sl:SetAttribute("HwBaseBrightness", 2.2)
			lights += 1
			table.insert(shaftTops, V3(cx, ROOF_Y + ROOF_T, cz))
		end

		------------------------------------------------------------------------------------ hill flanks + south massif
		-- north face (east of the mouth): y 0 at z 2494 up to the roof top at the cavern's north edge
		do
			local zA, zB = Z0 + 24, ZE[1] + 1
			for k = 0, 3 do
				local xa, xb = 112 + k * 27.5, 112 + (k + 1) * 27.5
				local h = ROOF_Y + ROOF_T + rng:NextNumber(-.5, 1.5)
				K.Wedge(hill, "HillFace", V3(xb - xa + 1, h, zB - zA), at((xa + xb) / 2, h / 2, (zA + zB) / 2) * ANG(0, PI, 0) * ANG(0, rng:NextNumber(-.03, .03), 0),
					rockCol(), M.Slate, G.Solid())
			end
			-- west flank: y 0 at x 94 up to the roof at x 104
			for k = 0, 4 do
				local za, zb = 2505 + k * 23.4, 2505 + (k + 1) * 23.4
				local h = ROOF_Y + ROOF_T + rng:NextNumber(-.5, 1.2)
				K.Wedge(hill, "HillFlank", V3(zb - za + 1, h, 11), at(99, h / 2, (za + zb) / 2) * ANG(0, -PI / 2, 0), rockCol(), M.Slate, G.Solid())
			end
			-- east strip up to the boundary
			for k = 0, 5 do
				local za, zb = 2494 + k * 21.3, 2494 + (k + 1) * 21.3
				rock(hill, V3(X1 - 210, ROOF_Y + ROOF_T + 4 + k * .6, zb - za + 1), at((210 + X1) / 2, (ROOF_Y + ROOF_T + 4 + k * .6) / 2, (za + zb) / 2))
			end
			-- the southern massif: a heightfield of crooked blocks rising to the boundary (+ lumps), then crag spires
			local MX, MZ = 9, 7
			local mz0 = ZE[#ZE] - 3
			local tops = {}
			for ix = 0, MX - 1 do
				for iz = 0, MZ - 1 do
					local xa, xb = 96 + ix * (X1 - 96) / MX, 96 + (ix + 1) * (X1 - 96) / MX
					local za, zb = mz0 + iz * (Z1 - mz0) / MZ, mz0 + (iz + 1) * (Z1 - mz0) / MZ
					local cx, cz = (xa + xb) / 2, (za + zb) / 2
					local u = (cz - mz0) / (Z1 - mz0)
					local top = 7 + 14 * u ^ 1.3 + 3 * math.sin(cx * .09 + cz * .05) + rng:NextNumber(-1.5, 1.5) + (cx > 180 and 2.5 or 0)
					local yb = iz == 0 and FY - 1 or -4
					rock(hill, V3(xb - xa + 3, top - yb, zb - za + 3), at(cx, (top + yb) / 2, cz) * ANG(rng:NextNumber(-.05, .05), rng:NextNumber(-.18, .18), rng:NextNumber(-.05, .05)))
					if (ix + iz) % 2 == 1 and iz < MZ - 1 then -- scree slopes rising south between the blocks
						local sh = rng:NextNumber(3, 6)
						K.Wedge(hill, "Scree", V3(xb - xa, sh, (zb - za) * .8), at(cx + rng:NextNumber(-2, 2), top + sh / 2 - .3, cz + (zb - za) * .2) * ANG(0, PI + rng:NextNumber(-.25, .25), 0),
							rockCol(), M.Slate, G.Solid())
					end
					if rng:NextNumber() < .55 then
						local lw, lh = rng:NextNumber(5, 9), rng:NextNumber(2, 5)
						rock(hill, V3(lw, lh, lw * rng:NextNumber(.6, 1)), at(cx + rng:NextNumber(-3, 3), top + lh * .35, cz + rng:NextNumber(-3, 3))
							* ANG(rng:NextNumber(-.2, .2), rng:NextNumber(0, PI), rng:NextNumber(-.2, .2)))
					end
					table.insert(tops, { V3(cx, top, cz), xb - xa })
				end
			end
			-- crooked crag spires: three stacked, leaning, tapering stones each
			local spires = 0
			for i = 1, #tops do
				local t = tops[(i * 7) % #tops + 1]
				if spires < 9 and (i * 7) % 3 == 0 and t[1].Z > mz0 + 14 then
					spires += 1
					local base = at(t[1].X + rng:NextNumber(-3, 3), t[1].Y - 1, t[1].Z + rng:NextNumber(-3, 3)) * ANG(0, rng:NextNumber(0, PI), 0)
					local lean = ANG(rng:NextNumber(-.16, .16), 0, rng:NextNumber(-.16, .16))
					local h1, h2, h3 = rng:NextNumber(10, 14), rng:NextNumber(8, 12), rng:NextNumber(6, 9)
					local c1 = base * lean * CF(0, h1 / 2, 0)
					rock(hill, V3(5.6, h1, 4.8), c1)
					local c2 = c1 * CF(rng:NextNumber(-.6, .6), h1 / 2 + h2 / 2 - .4, rng:NextNumber(-.6, .6)) * lean * ANG(0, rng:NextNumber(-.5, .5), 0)
					rock(hill, V3(3.8, h2, 3.3), c2)
					Y.GableTri(hill, "CragTip", c2 * CF(0, h2 / 2 - .3, 0) * lean, 3.8, h3, 3.3, rockCol(), M.Slate)
					if spires % 3 == 1 then
						local sp = (c1 * CF(3.3, rng:NextNumber(-2, 2), 0)).Position
						seam(hill, sp - V3(0, 2.5, 0), sp + V3(0, 3, 0), (c1 - c1.Position).RightVector, false)
					end
				end
			end
			-- west flank of the massif + the mouth block (rock around and above the arch)
			K.Wedge(hill, "HillFlank", V3(Z1 - 2622, 10, 10), at(99, 5, (2622 + Z1) / 2) * ANG(0, -PI / 2, 0), rockCol(), M.Slate, G.Solid())
		end

		------------------------------------------------------------------------------------------ the catacomb mouth
		local ARCH_W, ARCH_H = 13, 9.5 -- opening width, springing height (pointed apex ARCH_H + 4.5; blind tympanum above the springing)
		do
			local mcf = K.Look(V3(E.X, 0, E.Z), V3(E.X, 0, E.Z) - t1) -- -Z faces out of the hill (towards the gate)
			local function amp(x, y, z)
				return mcf * CF(x, y, z)
			end
			local hw = ARCH_W / 2
			-- rock mass framing the mouth (the hill's north-west corner)
			for _, s in ipairs({ -1, 1 }) do
				rock(mouth, V3(9, 20, 9), amp(s * (hw + 7.7), 8, 4.5) * ANG(0, s * .1, s * .03))
				rock(mouth, V3(8, 13, 8), amp(s * (hw + 14), 4.5, 6.5) * ANG(0, s * .25, 0))
			end
			rock(mouth, V3(ARCH_W + 16, 7, 9), amp(0, ARCH_H + 8, 4.2) * ANG(.05, 0, .02))
			-- blind tympanum inside the pointed head of the arch, with a glowing rune
			local tym = K.Part(mouth, "ArchTympanum", V3(ARCH_W + 3, 5.4, .8), amp(0, ARCH_H + 2.6, 1.4), C(44, 38, 52), M.Slate, G.Solid())
			local _ = tym
			G.Rune(mouth, amp(0, ARCH_H + 2.2, .95), "Eye", 2.6, CRYSTAL, { Depth = .1, Name = "TympanumRune" })
			-- pillars: three stacked crooked blocks each + bone bundles
			for _, s in ipairs({ -1, 1 }) do
				local y = 0
				for k = 1, 3 do
					local h = ({ 5, 4.5, 4.5 })[k]
					K.Part(mouth, "ArchPillar", V3(3.2 - k * .2, h, 3.2 - k * .2), amp(s * (hw + 1.4) + rng:NextNumber(-.2, .2), y + h / 2, rng:NextNumber(-.2, .2)) * ANG(0, rng:NextNumber(-.15, .15), s * .02),
						COL.Stone:Lerp(COL.StoneDark, rng:NextNumber(0, .5)), M.Slate, G.Solid())
					y += h
				end
				K.Part(mouth, "ArchImpost", V3(4, .7, 4), amp(s * (hw + 1.4), ARCH_H + .2, 0), COL.StoneLight, M.Slate)
				for k = 1, 5 do
					G.Bone(mouth, amp(s * (hw + 1.4), 1.6 + k * 2.2, -1.75) * ANG(0, 0, rng:NextNumber(-.25, .25)), 2.8, COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .6)))
				end
				G.Skull(mouth, amp(s * (hw + 1.4), ARCH_H - 1.2, -1.9), 1.2, nil, COL.Bone)
			end
			-- pointed arch: each side a curve from its impost to the apex, the two meeting at an angle
			local AH = 4.5 -- rise of the pointed head above the springing
			local A1 = 1.2 -- end parameter: the sides meet at a point, not a round top
			for _, s in ipairs({ -1, 1 }) do
				local n = 5
				local function arc(t)
					local a = t * A1
					return V3(s * (hw + 1.1) * (math.cos(a) - math.cos(A1)) / (1 - math.cos(A1)), ARCH_H + .7 + AH * math.sin(a) / math.sin(A1), 0)
				end
				for k = 1, n do
					local p, q = arc((k - 1) / n), arc(k / n)
					local a, b = (mcf * CF(p)).Position, (mcf * CF(q)).Position
					local blk = K.Bar(mouth, "ArchVoussoir", a, b, 3.2, 2.2, COL.Stone:Lerp(COL.StoneLight, rng:NextNumber(0, .4)), M.Slate)
					blk.Size = V3(blk.Size.X, blk.Size.Y, blk.Size.Z + .8)
				end
			end
			-- the giant dog skull keystone, violet eyes (HwLantern)
			Y.GiantSkull(mouth, amp(0, ARCH_H + AH + .4, -1.2) * ANG(-.08, 0, 0), .78,
				{ Lite = true, Mound = false, Solid = false, Eye = CRYSTAL, EyeDim = COL.VioletDim, Light = 16, Brightness = 1.3, Lantern = "Purple", Name = "MouthSkull" })
			lights += 1
			-- raised portcullis inside the arch
			for k = -3, 3 do
				K.Part(mouth, "PortcullisBar", V3(.35, 2.6, .35), amp(k * 1.7, ARCH_H - 1.2, .6), COL.Iron, M.CorrodedMetal)
				K.Wedge(mouth, "PortcullisSpike", V3(.35, .9, .35), amp(k * 1.7, ARCH_H - 2.95, .6) * ANG(PI, 0, 0), COL.IronHi, M.CorrodedMetal)
			end
			K.Part(mouth, "PortcullisRail", V3(ARCH_W - .4, .35, .35), amp(0, ARCH_H - .3, .6), COL.Iron, M.CorrodedMetal)
			K.Part(mouth, "PortcullisRail", V3(ARCH_W - .4, .35, .35), amp(0, ARCH_H - 2.1, .6), COL.Iron, M.CorrodedMetal)
			-- two skull lanterns hanging on chains inside the arch
			for _, s in ipairs({ -1, 1 }) do
				local hook = amp(s * 4, ARCH_H - .2, 3).Position
				local hang = hook - V3(0, 2.2, 0)
				G.Chain(mouth, hook, hang + V3(0, .6, 0), 0, { Link = 1, Thick = .16, Width = .4 })
				G.SkullLantern(mouth, CF(hang) * (mcf - mcf.Position), 1.1, CRYSTAL, { Light = 18, Brightness = 1, Kind = "Purple" })
				lights += 1
			end
			-- bone walls flanking the mouth (ossuary face of the hill)
			local function boneWallAt(cf: CFrame, w: number, h: number)
				K.Part(mouth, "BoneWallBack", V3(w + .6, h + .6, 1), cf * CF(0, h / 2, .55), C(40, 34, 42), M.Slate, G.Solid())
				local rows = math.floor(h / 1.3)
				for r = 0, rows - 1 do
					local y = .7 + r * 1.3
					if r % 3 == 1 then
						local nsk = math.floor(w / 1.7)
						for k = 0, nsk - 1 do
							local x = -w / 2 + (k + .5) * w / nsk
							local sk = cf * CF(x, y, -.05)
							K.Ball(mouth, "WallSkull", 1.15, sk, COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .5)), M.SmoothPlastic)
							for _, ex in ipairs({ -.22, .22 }) do
								K.Ball(mouth, "WallSkullEye", .34, sk * CF(ex, .05, -.44), COL.Ink, M.SmoothPlastic)
							end
						end
					else
						K.Part(mouth, "BoneRow", V3(w, .9, .5), cf * CF(0, y, .1), COL.BoneDark:Lerp(C(150, 140, 120), rng:NextNumber(0, .4)), M.SmoothPlastic)
						local nk = math.floor(w / 1.1)
						for k = 0, nk - 1, 2 do
							local x = -w / 2 + (k + .5) * w / nk
							K.Ball(mouth, "BoneEnd", .62, cf * CF(x, y + rng:NextNumber(-.12, .12), -.2), COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .5)), M.SmoothPlastic)
						end
					end
				end
			end
			for _, s in ipairs({ -1, 1 }) do
				boneWallAt(amp(s * (hw + 7.7), 0, -1.1) * ANG(0, -s * .06, 0), 7, 9)
			end
			-- the crypt facade: a crooked gable over the hill face with a rose of runes, bone trim, two leaning spires
			local gy, gw, gh = ARCH_H + 10.5, 26, 10
			Y.GableTri(mouth, "FacadeGable", amp(0, gy, 2.2) * ANG(0, PI / 2, 0) * ANG(0, 0, .02), gw, gh, 3, C(54, 48, 62), M.Slate, true)
			K.Part(mouth, "FacadeCornice", V3(gw + 2, 1.2, 4), amp(0, gy - .2, 2.2), COL.StoneDark, M.Slate)
			for _, s in ipairs({ -1, 1 }) do
				local a0 = amp(s * (gw / 2 + .2), gy + .5, .45).Position
				local a1 = amp(0, gy + gh + .3, .45).Position
				K.Bar(mouth, "FacadeBoneTrim", a0, a1, .7, .7, COL.Bone, M.SmoothPlastic)
				G.Skull(mouth, amp(s * (gw / 2 - .6), gy + 1.2, .2), 1.3, CRYSTAL, COL.Bone)
			end
			K.Ball(mouth, "FacadeFinial", 1.4, amp(0, gy + gh + .6, .9), COL.Bone, M.SmoothPlastic)
			G.Ring(mouth, amp(0, gy + 4.2, .55) * ANG(PI / 2, 0, 0), 2.3, 10, .4, .2, CRYSTAL, M.Neon, { Fill = .72, Name = "FacadeRose" })
			K.Ball(mouth, "FacadeRoseEye", 1.3, amp(0, gy + 4.2, .55), CRYSTAL, M.Neon)
			for _, s in ipairs({ -1, 1 }) do
				local sb = amp(s * (hw + 12.2), 0, -1.4) * ANG(0, 0, -s * .05)
				K.Part(mouth, "SpirePlinth", V3(4.2, 3, 4.2), sb * CF(0, 1.5, 0), COL.StoneDark, M.Slate, G.Solid())
				K.Part(mouth, "SpireShaft", V3(2.6, 15, 2.6), sb * CF(0, 10.5, 0) * ANG(0, .1 * s, 0), COL.Stone, M.Slate, G.Solid())
				K.Part(mouth, "SpireBand", V3(2.9, .4, 2.9), sb * CF(0, 13.5, 0), CRYSTAL, M.Neon, { Transparency = .1 })
				Y.GableTri(mouth, "SpireTip", sb * CF(0, 18, 0) * ANG(0, PI / 2, 0), 2.6, 4.5, 2.6, COL.StoneLight, M.Slate)
				G.Skull(mouth, sb * CF(0, 3.9, -1.3), 1.4, nil, COL.Bone)
				K.Attach(K.Part(mouth, "SpirePerch", V3(.2, .2, .2), sb * CF(0, 22.7, 0), COL.Stone, nil, { Transparency = 1 }), "CrowPerch")
			end
			-- a dark veil of depth inside the tunnel mouth (fades the bright tunnel floor)
			K.Part(mouth, "MouthShadow", V3(ARCH_W - .5, .1, 6), amp(0, .12, 4), C(20, 16, 26), M.SmoothPlastic, { Transparency = .35 })
		end

		------------------------------------------------------------------------------------------ inner arch (junction)
		do
			local jcf = K.Look(V3(J.X, 0, J.Z), V3(J.X, 0, J.Z) - rd) -- -Z faces up the ramp
			for _, s in ipairs({ -1, 1 }) do
				K.Part(mouth, "InnerArchPost", V3(2.4, ROOF_Y - FY + 2, 2.4), jcf * CF(s * (RW / 2 + .2), (ROOF_Y + FY) / 2, .8), COL.Timber, M.Wood, G.Solid())
				K.Bar(mouth, "InnerArchBrace", (jcf * CF(s * (RW / 2), ROOF_Y - 4, .8)).Position, (jcf * CF(s * (RW / 2 - 3), ROOF_Y - .8, .8)).Position, .8, .8, COL.TimberDark, M.Wood)
			end
			K.Part(mouth, "InnerArchCap", V3(RW + 3, 1.6, 2.6), jcf * CF(0, ROOF_Y - .3, .8), COL.Timber, M.Wood)
			G.SkullLantern(mouth, jcf * CF(0, ROOF_Y - 1.9, -.6), 1.6, CRYSTAL, { Light = 20, Brightness = 1.1, Kind = "Purple" })
			lights += 1
			for k = -2, 2 do
				if k ~= 0 then
					G.Skull(mouth, jcf * CF(k * 2.3, ROOF_Y - .3, -.7), .85, nil, COL.Bone)
				end
			end
		end

		-------------------------------------------------------------------------------------- crypt niches + bone walls
		local function niche(parent, fcf: CFrame, lit: boolean)
			-- fcf: on the wall face, -Z into the room; niche bottom at fcf
			K.Part(parent, "NicheRecess", V3(2.8, 3.6, .3), fcf * CF(0, 1.8, -.05), C(18, 14, 22), M.SmoothPlastic)
			for _, s in ipairs({ -1, 1 }) do
				K.Part(parent, "NicheJamb", V3(.7, 3.8, .9), fcf * CF(s * 1.75, 1.9, -.3), COL.Stone, M.Slate)
				K.Wedge(parent, "NicheArch", V3(.9, 1.2, 1.75), fcf * CF(s * .875, 4.2, -.3) * ANG(0, s * PI / 2, 0), COL.Stone, M.Slate)
			end
			K.Part(parent, "NicheSill", V3(4.2, .4, 1.3), fcf * CF(0, -.1, -.5), COL.StoneLight, M.Slate)
			if lit then
				G.SkullLantern(parent, fcf * CF(0, .75, -.45), 1.1, COL.Candle, { Light = 16, Brightness = .9, Kind = "Orange" })
				lights += 1
			else
				G.Skull(parent, fcf * CF(0, .75, -.45), 1.1, nil, COL.Bone)
				K.Candles(parent, fcf * CF(1.1, .1, -.6), 2, rng, { Light = false, Spread = .25 })
			end
			Y.BonePile(parent, fcf * CF(-.9, .05, -.5), rng, 2, false)
		end
		local function boneWall(parent, fcf: CFrame, w: number, h: number)
			K.Part(parent, "BoneWallBack", V3(w + .6, h + .4, .8), fcf * CF(0, h / 2, .2), C(40, 34, 42), M.Slate)
			local rows = math.floor(h / 1.3)
			for r = 0, rows - 1 do
				local y = .7 + r * 1.3
				if r % 3 == 1 then
					local nsk = math.floor(w / 1.8)
					for k = 0, nsk - 1 do
						local x = -w / 2 + (k + .5) * w / nsk
						local sk = fcf * CF(x, y, -.4)
						K.Ball(parent, "WallSkull", 1.15, sk, COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .5)), M.SmoothPlastic)
						for _, ex in ipairs({ -.22, .22 }) do
							K.Ball(parent, "WallSkullEye", .34, sk * CF(ex, .05, -.44), COL.Ink, M.SmoothPlastic)
						end
					end
				else
					K.Part(parent, "BoneRow", V3(w, .9, .5), fcf * CF(0, y, -.2), COL.BoneDark:Lerp(C(150, 140, 120), rng:NextNumber(0, .4)), M.SmoothPlastic)
					local nk = math.floor(w / 1.1)
					for k = 0, nk - 1, 2 do
						local x = -w / 2 + (k + .5) * w / nk
						K.Ball(parent, "BoneEnd", .62, fcf * CF(x, y + rng:NextNumber(-.12, .12), -.5), COL.Bone:Lerp(COL.BoneDark, rng:NextNumber(0, .5)), M.SmoothPlastic)
					end
				end
			end
		end
		-- corridor (ramp walls, inner faces)
		for _, s in ipairs({ -1, 1 }) do
			for _, t in ipairs({ .3, .78 }) do
				local p = RT:Lerp(RB, t) + latR * s * (RW / 2 + .05)
				local fcf = face(p, -latR * s, p.Y)
				if t < .5 then
					niche(mouth, fcf * CF(0, 1.8, 0), s > 0)
				else
					boneWall(mouth, fcf * CF(0, .2, 0) * ANG(0, 0, 0), 7, 7.5)
				end
			end
		end
		-- cavern walls: niches + bone walls on the inner faces (y = floor)
		local NICHES = {
			{ V3(140, 0, FZ0), V3(0, 0, 1), true }, { V3(176, 0, FZ0), V3(0, 0, 1), false }, { V3(FX1, 0, 2540), V3(-1, 0, 0), true },
			{ V3(FX1, 0, 2580), V3(-1, 0, 0), false }, { V3(185, 0, FZ1), V3(0, 0, -1), true }, { V3(132, 0, FZ1), V3(0, 0, -1), false },
			{ V3(FX0, 0, 2552), V3(1, 0, 0), true }, { V3(FX0, 0, 2585), V3(1, 0, 0), false },
		}
		for _, n in ipairs(NICHES) do
			local p = n[1] + n[2] * .55
			niche(cavern, face(p, n[2], FY + 2.2), n[3])
		end
		boneWall(cavern, face(V3(158, 0, FZ0 + .9), V3(0, 0, 1), FY), 10, 9)
		boneWall(cavern, face(V3(FX1 - .9, 0, 2603), V3(-1, 0, 0), FY), 9, 8)
		boneWall(cavern, face(V3(160, 0, FZ1 - .9), V3(0, 0, -1), FY), 11, 9)
		boneWall(cavern, face(V3(FX0 + .9, 0, 2568), V3(1, 0, 0), FY), 8, 8)

		------------------------------------------------------------------------------------------- timber supports
		local function timberSet(parent, fcf: CFrame, h: number, w: number)
			-- fcf on the wall face at floor level, -Z into the room: two posts, a cap beam, knee braces
			for _, s in ipairs({ -1, 1 }) do
				K.Part(parent, "TimberPost", V3(1.1, h, 1.1), fcf * CF(s * w / 2, h / 2, -.8) * ANG(0, 0, s * rng:NextNumber(.01, .04)), COL.Timber:Lerp(COL.TimberDark, rng:NextNumber(0, .5)), M.Wood, G.Solid())
				K.Bar(parent, "TimberBrace", (fcf * CF(s * w / 2, h - 2.6, -.8)).Position, (fcf * CF(s * (w / 2 - 2.2), h - .5, -.8)).Position, .6, .6, COL.TimberDark, M.Wood)
			end
			K.Part(parent, "TimberCap", V3(w + 2, 1.1, 1.3), fcf * CF(0, h + .2, -.8) * ANG(0, 0, rng:NextNumber(-.03, .03)), COL.Timber, M.Wood)
		end
		local TH = ROOF_Y - FY - .3
		for _, seg in ipairs({
			{ V3(128, 0, FZ0), V3(FX1 - 6, 0, FZ0), V3(0, 0, 1) }, { V3(FX1, 0, FZ0 + 8), V3(FX1, 0, FZ1 - 6), V3(-1, 0, 0) },
			{ V3(FX1 - 8, 0, FZ1), V3(FX0 + 6, 0, FZ1), V3(0, 0, -1) }, { V3(FX0, 0, FZ1 - 8), V3(FX0, 0, 2540), V3(1, 0, 0) },
		}) do
			local len = G.Flat(seg[1], seg[2])
			local n = math.floor(len / 16)
			for k = 0, n do
				local p = seg[1]:Lerp(seg[2], k / math.max(n, 1))
				local skip = false
				for _, nn in ipairs(NICHES) do
					if G.Flat(p, nn[1]) < 4.5 then
						skip = true
					end
				end
				if not skip then
					timberSet(cavern, face(p - seg[3] * .1, seg[3], FY), TH, 6.5)
				end
			end
		end

		---------------------------------------------------------------------------------------------- rock pillars
		for _, pp in ipairs({ V3(140, 0, 2572), V3(186, 0, 2549), V3(172, 0, 2585) }) do
			local y = FY
			for k = 1, 4 do
				local h = (ROOF_Y - FY + 1) / 4
				rock(cavern, V3(5.4 - k * .35, h + .4, 5.2 - k * .3), at(pp.X + rng:NextNumber(-.4, .4), y + h / 2, pp.Z + rng:NextNumber(-.4, .4)) * ANG(0, k * .45 + rng:NextNumber(-.2, .2), rng:NextNumber(-.04, .04)))
				y += h
			end
			rock(cavern, V3(8, 2.5, 8), at(pp.X, ROOF_Y - .6, pp.Z) * ANG(0, rng:NextNumber(0, PI), 0))
			rock(cavern, V3(7, 1.6, 7), at(pp.X, FY + .6, pp.Z) * ANG(0, rng:NextNumber(0, PI), 0))
			for _, s in ipairs({ -1, 1 }) do
				K.Bar(cavern, "PillarProp", V3(pp.X + s * 4.4, FY, pp.Z + 1), V3(pp.X + s * 2.2, ROOF_Y - 3, pp.Z + 1), .8, .8, COL.Timber, M.Wood, G.Solid())
			end
			-- violet seam spiralling up the pillar
			local prev = V3(pp.X + 2.4, FY + 1.5, pp.Z)
			for k = 1, 4 do
				local a = k * 1.1
				local q = V3(pp.X + math.cos(a) * 2.3, FY + 1.5 + k * 3.4, pp.Z + math.sin(a) * 2.3)
				K.Bar(cavern, "OreSeam", prev, q, .3, .3, CRYSTAL, M.Neon, { Transparency = .1 })
				prev = q
			end
		end

		----------------------------------------------------------------------------------- stalactites + wall outcrops
		do
			local placed, tries = 0, 0
			while placed < 30 and tries < 500 do
				tries += 1
				local p = V3(rng:NextNumber(FX0 + 2, FX1 - 2), 0, rng:NextNumber(FZ0 + 2, FZ1 - 2))
				local ix, iz = 0, 0
				for k = 1, #XE - 1 do
					if p.X >= XE[k] and p.X < XE[k + 1] then
						ix = k
					end
				end
				for k = 1, #ZE - 1 do
					if p.Z >= ZE[k] and p.Z < ZE[k + 1] then
						iz = k
					end
				end
				if not isGap(ix, iz) and nodeDist(p) > NODE_CLEAR + 2 and G.Flat(p, RB) > 10 then
					placed += 1
					local len = rng:NextNumber(2.5, 6.5)
					local w = rng:NextNumber(1.2, 2.4)
					local top = at(p.X, ROOF_Y + .3, p.Z) * ANG(rng:NextNumber(-.08, .08), rng:NextNumber(0, PI), rng:NextNumber(-.08, .08))
					K.Part(cavern, "Stalactite", V3(w, len * .45, w), top * CF(0, -len * .22, 0), rockCol(), M.Slate)
					K.Part(cavern, "Stalactite", V3(w * .6, len * .35, w * .6), top * CF(0, -len * .6, 0), rockCol(), M.Slate)
					K.Wedge(cavern, "StalactiteTip", V3(w * .4, len * .3, w * .4), top * CF(0, -len * .9, 0) * ANG(PI, 0, 0), rockCol(), M.Slate)
				end
			end
			-- outcrops bulging from the walls at random heights
			for _, w in ipairs({
				{ V3(126, 0, FZ0), V3(FX1, 0, FZ0), V3(0, 0, 1) }, { V3(FX1, 0, FZ0), V3(FX1, 0, FZ1), V3(-1, 0, 0) },
				{ V3(FX1, 0, FZ1), V3(FX0, 0, FZ1), V3(0, 0, -1) }, { V3(FX0, 0, FZ1), V3(FX0, 0, 2538), V3(1, 0, 0) },
			}) do
				local len = G.Flat(w[1], w[2])
				for k = 1, math.floor(len / 9) do
					local p = w[1]:Lerp(w[2], (k - .5) / math.floor(len / 9)) + w[3] * rng:NextNumber(.2, .8)
					local y = rng:NextNumber(FY + 6, ROOF_Y - 2)
					rock(cavern, V3(rng:NextNumber(3, 6), rng:NextNumber(2.5, 5), rng:NextNumber(2, 3.5)),
						K.Look(V3(p.X, y, p.Z), V3(p.X, y, p.Z) + w[3]) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(-.3, .3), rng:NextNumber(-.4, .4)))
				end
			end
		end

		--------------------------------------------------------------------------------------- violet ore seams + crystals
		seam(cavern, V3(150, FY + 3, FZ0 + .3), V3(170, FY + 9, FZ0 + .3), V3(0, 0, 1), true)
		seam(cavern, V3(FX1 - .3, FY + 4, 2560), V3(FX1 - .3, FY + 11, 2575), V3(-1, 0, 0), false)
		seam(cavern, V3(120, FY + 5, FZ1 - .3), V3(145, FY + 2.5, FZ1 - .3), V3(0, 0, -1), true)
		seam(cavern, V3(FX0 + .3, FY + 9, 2595), V3(FX0 + .3, FY + 3, 2610), V3(1, 0, 0), false)
		seam(cavern, V3(194, FY + 2.5, FZ1 - .3), V3(203, FY + 10, FZ1 - .3), V3(0, 0, -1), true)
		-- on the hill outside (seen from Bell Square / the arena approach)
		seam(hill, V3(120, 1, Z0 + 24.6), V3(150, 4.5, 2507.5), V3(0, .5, -1).Unit, false)
		seam(hill, V3(170, .8, Z0 + 24.6), V3(196, 5, 2508), V3(0, .5, -1).Unit, true)
		seam(hill, V3(94.6, .6, 2560), V3(102, 5.6, 2585), V3(-1, .6, 0).Unit, false)

		------------------------------------------------------------------------------------------- the respawn alcove
		do
			-- rune circle under the spawn point (flush), the shrine in the recess, a little bell on a timber post
			Y.RuneRing(mine, at(SP.X, FY + .03, SP.Z), 2.6, 12, .22, CRYSTAL, { Fill = .7, H = .05, Name = "SpawnRune" })
			Y.RuneRing(mine, at(SP.X, FY + .03, SP.Z), 1.6, 6, .16, COL.Moon, { Fill = .5, H = .05, Phase = .3, Name = "SpawnRune" })
			local acf = K.Look(V3(ALC.Back + .2, FY, (ALC.Z0 + ALC.Z1) / 2), V3(ALC.Back + .2, FY, (ALC.Z0 + ALC.Z1) / 2) + V3(1, 0, 0))
			K.Part(mine, "AlcoveStep", V3(9, .6, 3), acf * CF(0, .3, -1.5), COL.StoneDark, M.Slate, G.Solid())
			K.Part(mine, "AlcoveAltar", V3(4, 2, 1.8), acf * CF(0, 1.6, -1.2), COL.Stone, M.Slate, G.Solid())
			G.SkullLantern(mine, acf * CF(0, 3.2, -1.2), 1.3, COL.Candle, { Light = 18, Brightness = 1, Kind = "Orange" })
			lights += 1
			K.Candles(mine, acf * CF(-1.4, 2.6, -1.2), 3, rng, { Light = false, Spread = .4 })
			K.Candles(mine, acf * CF(1.5, .6, -2.4), 4, rng, { Light = false, Spread = .6 })
			Y.BonePile(mine, acf * CF(3.6, 0, -1.4), rng, 4, true)
			Y.BonePile(mine, acf * CF(-3.4, 0, -1.6), rng, 3, false)
			-- arch over the recess
			K.Part(mine, "AlcoveLintel", V3(1.6, 1.4, ALC.Z1 - ALC.Z0 + 3), at(FX0 - .2, FY + 8.5, (ALC.Z0 + ALC.Z1) / 2), COL.Timber, M.Wood)
			for _, z in ipairs({ ALC.Z0 - .6, ALC.Z1 + .6 }) do
				K.Part(mine, "AlcovePost", V3(1.2, 8.6, 1.2), at(FX0 - .2, FY + 4.3, z), COL.Timber, M.Wood, G.Solid())
			end
			-- bell post (the "you are back" bell)
			local bp = at(FX0 - .2, FY + 8.5, (ALC.Z0 + ALC.Z1) / 2 + 3)
			K.Part(mine, "AlcoveBellYoke", V3(.4, .4, 1.6), bp * CF(.9, -.5, 0), COL.Iron, M.CorrodedMetal)
			K.CylY(mine, "AlcoveBell", 1.2, 1.3, bp * CF(1.2, -1.5, 0), COL.Bronze, M.Metal)
			K.Ball(mine, "AlcoveBellCrown", .9, bp * CF(1.2, -.9, 0), COL.BronzeDark, M.Metal)
		end

		------------------------------------------------------------------------------------------- crater rings at nodes
		for i, n in ipairs(nodes) do
			local cm = K.Model(mine, "Crater_" .. i)
			K.CylY(cm, "CraterBed", .08, 7.4, at(n.X, FY + .04, n.Z), C(34, 28, 40), M.Slate)
			K.CylY(cm, "CraterScorch", .06, 4.2, at(n.X, FY + .09, n.Z), C(24, 18, 30), M.Slate)
			for k = 1, 4 do
				local a = k / 4 * PI * 2 + rng:NextNumber(-.4, .4)
				local p0 = V3(n.X + math.cos(a) * 1.4, FY + .1, n.Z + math.sin(a) * 1.4)
				local p1 = V3(n.X + math.cos(a + .25) * 3.4, FY + .1, n.Z + math.sin(a + .25) * 3.4)
				K.Bar(cm, "CraterCrack", p0, p1, .18, .05, CRYSTAL, M.Neon, { Transparency = .25 })
			end
			for k = 1, 9 do
				local a = k / 9 * PI * 2 + rng:NextNumber(-.2, .2)
				local r = rng:NextNumber(4.2, 5.4)
				local s = rng:NextNumber(.9, 1.7)
				K.Part(cm, "CraterRubble", V3(s, rng:NextNumber(.45, .95), s * rng:NextNumber(.7, 1.2)),
					at(n.X + math.cos(a) * r, FY + .3, n.Z + math.sin(a) * r) * ANG(rng:NextNumber(-.15, .15), rng:NextNumber(0, PI), rng:NextNumber(-.15, .15)),
					rockCol():Lerp(EARTH, .3), M.Slate)
			end
		end

		------------------------------------------------------------------------------------------- rails, carts
		local function track(parent, pts: { Vector3 }, gauge: number, y: number)
			for i = 1, #pts - 1 do
				local a, b = V3(pts[i].X, y, pts[i].Z), V3(pts[i + 1].X, y, pts[i + 1].Z)
				local dir = V3(b.X - a.X, 0, b.Z - a.Z).Unit
				local side = V3(-dir.Z, 0, dir.X)
				for _, s in ipairs({ -1, 1 }) do
					K.Bar(parent, "Rail", a + side * s * gauge / 2 + V3(0, .33, 0), b + side * s * gauge / 2 + V3(0, .33, 0), .25, .22, C(88, 80, 84), M.Metal)
				end
				local len = G.Flat(a, b)
				local ns = math.floor(len / 3.4)
				for k = 0, ns - 1 do
					if rng:NextNumber() > .08 then
						local p = a:Lerp(b, (k + .5) / ns)
						K.Part(parent, "Sleeper", V3(gauge + 1.3, .2, .7), K.Look(p + V3(0, .12, 0), p + V3(0, .12, 0) + dir) * ANG(0, rng:NextNumber(-.06, .06), 0),
							COL.TimberDark, M.Wood)
					end
				end
			end
		end
		local loop = {
			V3(125, 0, 2522.5), V3(196.5, 0, 2522.5), V3(200.5, 0, 2526.5), V3(200.5, 0, 2605.5), V3(196.5, 0, 2609.5), V3(119, 0, 2609.5),
			V3(115, 0, 2605.5), V3(115, 0, 2540),
		}
		track(mine, loop, 3, FY)
		-- the forecourt line runs in through the mouth and down the ramp
		track(dressing, { V3(80, 0, 2479), E - t1 * 6, E, RT }, 3, 0)
		do
			local slope = (RB - RT).Unit
			local side = latR
			for _, s in ipairs({ -1, 1 }) do
				K.Bar(mouth, "Rail", RT + side * s * 1.5 + V3(0, .33, 0), RB + side * s * 1.5 + V3(0, .33, 0), .25, .22, C(88, 80, 84), M.Metal)
			end
			local _ = slope
		end
		local function cart(parent, cf: CFrame, opts)
			opts = opts or {}
			local m = K.Model(parent, "MineCart")
			local body = cf * CF(0, 1.55, 0)
			K.Part(m, "CartBody", V3(3.2, 1.8, 4.6), body, C(70, 52, 46), M.CorrodedMetal, G.Solid())
			for _, s in ipairs({ -1, 1 }) do
				K.Part(m, "CartLip", V3(.3, .35, 4.8), body * CF(s * 1.65, .95, 0), COL.Iron, M.CorrodedMetal)
				K.Part(m, "CartLip", V3(3.5, .35, .3), body * CF(0, .95, s * 2.35), COL.Iron, M.CorrodedMetal)
				for _, e in ipairs({ -1, 1 }) do
					K.CylX(m, "CartWheel", .35, 1.3, cf * CF(s * 1.55, .65, e * 1.5), COL.Iron, M.CorrodedMetal)
				end
				K.Part(m, "CartBand", V3(3.3, .25, .25), body * CF(0, s * .4, s * 1.2), COL.Rust, M.CorrodedMetal)
			end
			if opts.Ore ~= false then
				K.Part(m, "CartLoad", V3(2.8, .5, 4.2), body * CF(0, .8, 0), C(48, 42, 52), M.Slate)
				for k = 1, 3 do
					K.Wedge(m, "OreCrystal", V3(.6, 1.4, .6), body * CF(rng:NextNumber(-.9, .9), 1.5, rng:NextNumber(-1.4, 1.4)) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, PI), rng:NextNumber(-.4, .4)),
						CRYSTAL, M.Neon, { Transparency = .1 })
					local _ = k
				end
			end
			return m
		end
		cart(mine, at(142, FY, 2522.5) * ANG(0, PI / 2, 0), {})
		cart(mine, at(200.5, FY, 2578), {})
		cart(mine, at(166, FY, 2609.5) * ANG(0, PI / 2 + .05, 0), { Ore = false })
		cart(mine, at(110.5, FY - .2, 2578) * ANG(0, .3, 0) * ANG(0, 0, PI / 2 - .25), { Ore = false }) -- toppled
		cart(dressing, at(86, 0, 2480) * ANG(0, -.95, 0), {})

		-------------------------------------------------------------------------------------- floor scatter (low, clear)
		local scattered = 0
		local stries = 0
		while scattered < 26 and stries < 400 do
			stries += 1
			local p = V3(rng:NextNumber(FX0 + 3, FX1 - 3), 0, rng:NextNumber(FZ0 + 3, FZ1 - 3))
			if nodeDist(p) > NODE_CLEAR + 1.5 and G.Flat(p, SP) > 4 then
				scattered += 1
				if scattered % 5 == 0 then
					-- crate stack / ore sack (taller: stays well clear of the nodes)
					if nodeDist(p) > NODE_CLEAR + 4 then
						K.Part(mine, "MinerCrate", V3(2.4, 2.2, 2.4), at(p.X, FY + 1.1, p.Z) * ANG(0, rng:NextNumber(0, PI), 0), COL.Timber, M.WoodPlanks, G.Solid())
						K.Part(mine, "MinerCrate", V3(1.8, 1.6, 1.8), at(p.X + .3, FY + 3, p.Z - .2) * ANG(0, rng:NextNumber(0, PI), .05), COL.TimberDark, M.WoodPlanks)
					end
				elseif scattered % 5 == 1 then
					-- broken pickaxe
					local cf = at(p.X, FY + .15, p.Z) * ANG(0, rng:NextNumber(0, PI), 0)
					K.Part(mine, "PickHandle", V3(.25, .25, 3.2), cf, COL.Timber, M.Wood)
					K.Wedge(mine, "PickHead", V3(.3, .5, 1.6), cf * CF(0, 0, -1.6) * ANG(0, 0, PI / 2), COL.Iron, M.CorrodedMetal)
				else
					K.Part(mine, "FloorStone", V3(rng:NextNumber(1, 2.6), .25, rng:NextNumber(1, 2.4)), at(p.X, FY + .1, p.Z) * ANG(0, rng:NextNumber(0, PI), 0),
						rockCol():Lerp(FLOOR, .5), M.Slate)
				end
			end
		end
		-- dust lines / cracks across the floor (flush)
		for _ = 1, 10 do
			local a = V3(rng:NextNumber(FX0 + 4, FX1 - 4), FY + .03, rng:NextNumber(FZ0 + 4, FZ1 - 4))
			local b = a + V3(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
			K.Bar(mine, "FloorCrack", a, b, .22, .04, C(26, 22, 30), M.SmoothPlastic)
		end

		------------------------------------------------------------------------------------------- the headframe
		do
			local g = GAPS[5]
			local x0, x1, z0, z1 = XE[g[1]], XE[g[1] + 1], ZE[g[2]], ZE[g[2] + 1]
			local base = ROOF_Y + ROOF_T
			local top = base + 24
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local legs = {}
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local foot = V3(cx + sx * ((x1 - x0) / 2 + .5), base, cz + sz * ((z1 - z0) / 2 + .5))
					local head = V3(cx + sx * 2.6, top, cz + sz * 2.2)
					local knee = foot:Lerp(head, .5) + V3(sx * .8, 0, sz * .6)
					K.Rod(dressing, "HeadframeLeg", foot, knee, 1.2, COL.Timber, M.Wood, G.Solid())
					K.Rod(dressing, "HeadframeLeg", knee, head, 1.0, COL.Timber:Lerp(COL.TimberDark, .3), M.Wood)
					table.insert(legs, { foot, knee, head })
				end
			end
			-- braces between neighbouring legs at the knee
			for _, pr in ipairs({ { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 } }) do
				K.Rod(dressing, "HeadframeBrace", legs[pr[1]][2], legs[pr[2]][3]:Lerp(legs[pr[2]][2], .45), .55, COL.TimberDark, M.Wood)
			end
			K.Part(dressing, "HeadframeDeck", V3(7.2, .6, 6.4), at(cx, top + .3, cz), COL.TimberDark, M.WoodPlanks)
			-- sheave wheel (ring of bars + spokes + hub), along X
			local wc = at(cx, top + 4.2, cz) * ANG(0, PI / 2, 0)
			local R = 3.4
			for k = 0, 11 do
				local a0, a1 = k / 12 * PI * 2, (k + 1) / 12 * PI * 2
				K.Bar(dressing, "SheaveRim", (wc * CF(math.cos(a0) * R, math.sin(a0) * R, 0)).Position, (wc * CF(math.cos(a1) * R, math.sin(a1) * R, 0)).Position, .4, .5, COL.Iron, M.CorrodedMetal)
			end
			for k = 0, 3 do
				local a = k / 4 * PI
				K.Bar(dressing, "SheaveSpoke", (wc * CF(math.cos(a) * R, math.sin(a) * R, 0)).Position, (wc * CF(-math.cos(a) * R, -math.sin(a) * R, 0)).Position, .25, .25, COL.Iron, M.CorrodedMetal)
			end
			K.CylZ(dressing, "SheaveHub", 1.2, 1.1, at(cx, top + 4.2, cz), COL.Rust, M.CorrodedMetal)
			for _, s in ipairs({ -1, 1 }) do
				K.Part(dressing, "SheaveBearing", V3(.6, 4.4, .8), at(cx + s * .9, top + 2.3, cz), COL.TimberDark, M.Wood)
			end
			-- cable down the shaft to a hanging ore bucket (ends far above the floor)
			local cableTop = V3(cx, top + 4.2 - R, cz - .3)
			local cableBot = V3(cx + .4, FY + 12, cz - .3)
			K.Bar(dressing, "HeadframeCable", cableTop, cableBot, .14, .14, C(40, 36, 40), M.Metal)
			K.CylY(dressing, "OreBucket", 1.6, 1.9, CF(cableBot - V3(0, .9, 0)), COL.Rust, M.CorrodedMetal)
			K.Part(dressing, "OreBucketBail", V3(2.1, .15, .15), CF(cableBot + V3(0, .1, 0)), COL.Iron, M.CorrodedMetal)
			G.CageLantern(dressing, at(cx + 3.6, top + .1, cz - 2.6), COL.Candle, "Orange", { Light = 22, Brightness = 1.1, Attrs = { UyLightAtSeal = SEAL } })
			lights += 1
			K.Attach(K.Part(dressing, "HeadframePerch", V3(.2, .2, .2), at(cx, top + 4.2 + R + .3, cz), COL.Iron, nil, { Transparency = 1 }), "CrowPerch")
		end

		------------------------------------------------------------------------- hilltop: the catacomb breathes up here
		do
			-- a little miners' graveyard on a stone terrace over the north half of the cavern
			local gy = ROOF_Y + ROOF_T + 2.2
			local gcf = at(152, gy, 2522) * ANG(0, .12, 0)
			K.Part(dressing, "HilltopTerrace", V3(22, 1.2, 12), gcf * CF(0, -.6, 0), C(64, 58, 70), M.Cobblestone, G.Solid())
			for k = 0, 4 do
				Y.Tombstone(dressing, gcf * CF(-8 + k * 4, 0, -2 + (k % 2) * 3.5) * ANG(0, PI + rng:NextNumber(-.25, .25), 0), ({ 3, 7, 1, 6, 5 })[k + 1], rng, nil, { Color = COL.Stone })
			end
			Y.Tree(dressing, gcf * CF(9, 0, 3), 13, rng, { Branches = 3, Perches = 2, Lean = V3(.15, 0, -.1) })
			K.Candles(dressing, gcf * CF(-2, 0, 3.5), 3, rng, { Light = false, Spread = .5 })
			-- two vent kiosks: stone posts, a pointed roof, a grate over a violet glow
			for vi, vp in ipairs({ V3(122, 0, 2560), V3(192, 0, 2532) }) do
				local vcf = at(vp.X, gy, vp.Z) * ANG(0, vi * .7, 0)
				K.Part(dressing, "VentPlinth", V3(7, 1.4, 7), vcf * CF(0, -.5, 0), COL.StoneDark, M.Slate, G.Solid())
				K.Part(dressing, "VentGlow", V3(3.6, .1, 3.6), vcf * CF(0, .25, 0), CRYSTAL, M.Neon, { Transparency = .15 })
				for g = -1, 1 do
					K.Part(dressing, "VentGrate", V3(.25, .25, 3.8), vcf * CF(g * 1.2, .4, 0), COL.Iron, M.CorrodedMetal)
					K.Part(dressing, "VentGrate", V3(3.8, .25, .25), vcf * CF(0, .45, g * 1.2), COL.Iron, M.CorrodedMetal)
				end
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						K.Part(dressing, "VentPost", V3(.9, 5, .9), vcf * CF(sx * 2.6, 2.7, sz * 2.6), COL.Stone, M.Slate, G.Solid())
					end
				end
				K.Part(dressing, "VentCornice", V3(6.6, .6, 6.6), vcf * CF(0, 5.4, 0), COL.StoneLight, M.Slate)
				Y.GableTri(dressing, "VentRoof", vcf * CF(0, 5.7, 0) * ANG(0, PI / 2, 0), 6.6, 3.6, 6.6, C(52, 46, 60), M.Slate)
				G.Skull(dressing, vcf * CF(0, 7.8, -2.9), 1, CRYSTAL, COL.Bone)
				local host = G.EmitterPart(fxm, "VentBreath", V3(3, 1, 3), vcf * CF(0, 1, 0))
				G.Fog(host, { Color = C(170, 130, 255), Color2 = COL.VioletDim, Rate = 1.2, Size = { 3, 8 }, Lifetime = { 4, 7 }, Rise = .6, Transparency = .78 })
			end
		end

		------------------------------------------------------------------------- forecourt + west strip (surface dressing)
		local function lantern(p: Vector3, face: Vector3, h: number)
			local m = K.Model(lamps, "SkullLanternPost")
			local base = K.Look(p, p + face)
			K.Part(m, "PostFoot", V3(1.6, .6, 1.6), base * CF(0, .3, 0), COL.StoneDark, M.Slate, G.Solid())
			K.CylY(m, "Post", h, .5, base * CF(0, h / 2, 0), COL.TimberDark, M.Wood, G.Solid())
			K.Part(m, "PostArm", V3(.35, .35, 2.4), base * CF(0, h - .3, -1), COL.TimberDark, M.Wood)
			G.Chain(m, (base * CF(0, h - .45, -2)).Position, (base * CF(0, h - 1.5, -2)).Position, 0, { Link = .6, Thick = .12, Width = .32 })
			G.SkullLantern(m, base * CF(0, h - 2.3, -2), 1.1, COL.Candle, { Light = 18, Brightness = 1, Kind = "Orange", Attrs = { UyLightAtSeal = SEAL } })
			lights += 1
			return m
		end
		lantern(V3(84, 0, 2486), V3(1, 0, -.4).Unit, 8)
		lantern(E - t1 * 6 + lat1 * 8.5, -lat1, 7.5)
		lantern(E - t1 * 7 - lat1 * 8.5, lat1, 7.5)
		-- miners' graves on the west strip, dead trees, a bone fence along the arena side
		local graves = { V3(82, 0, 2520), V3(87, 0, 2531), V3(81, 0, 2546), V3(88, 0, 2612), V3(83, 0, 2640), V3(87, 0, 2668) }
		for i, gp in ipairs(graves) do
			Y.Tombstone(dressing, at(gp.X, 0, gp.Z) * ANG(0, PI / 2 + rng:NextNumber(-.3, .3), 0), ({ 7, 3, 1, 7, 6, 2 })[i], rng, nil, { Color = COL.Stone })
		end
		for _, tp in ipairs({ V3(90, 0, 2500), V3(84, 0, 2590), V3(90, 0, 2690), V3(214, 0, 2482) }) do
			Y.Tree(dressing, at(tp.X, 0, tp.Z), rng:NextNumber(11, 15), rng, { Branches = 3, Perches = 2, Bats = true })
		end
		for k = 0, 9 do
			local z0 = 2500 + k * 20
			local a, b = V3(X0 + 1.5, 0, z0), V3(X0 + 1.5, 0, z0 + 17)
			if k ~= 4 then
				for j = 0, 3 do
					local p = a:Lerp(b, j / 3)
					K.CylY(dressing, "BoneFencePost", 3.2, .5, at(p.X, 1.6, p.Z) * ANG(rng:NextNumber(-.06, .06), 0, rng:NextNumber(-.06, .06)), COL.BoneDark, M.SmoothPlastic, G.Solid())
					K.Ball(dressing, "BoneFenceKnob", .8, at(p.X, 3.3, p.Z), COL.Bone, M.SmoothPlastic)
				end
				K.Bar(dressing, "BoneFenceRail", a + V3(0, 2.4, 0), b + V3(0, 2.4, 0), .3, .3, COL.Bone, M.SmoothPlastic)
				K.Bar(dressing, "BoneFenceRail", a + V3(0, 1.2, 0), b + V3(0, 1.2, 0), .3, .3, COL.Bone, M.SmoothPlastic)
			end
		end
		-- sealed side adit on the west flank (timber frame, rubble plug, a warning skull)
		do
			local acf = K.Look(V3(96.5, 0, 2560), V3(96.5, 0, 2560) + V3(-1, 0, 0))
			for _, s in ipairs({ -1, 1 }) do
				K.Part(dressing, "AditPost", V3(1, 7, 1), acf * CF(s * 3.2, 3.5, 0), COL.Timber, M.Wood, G.Solid())
			end
			K.Part(dressing, "AditCap", V3(8.4, 1.1, 1.3), acf * CF(0, 7.3, 0), COL.Timber, M.Wood)
			K.Part(dressing, "AditDark", V3(5.4, 6.5, .3), acf * CF(0, 3.3, .6), C(16, 12, 20), M.SmoothPlastic)
			G.Rubble(dressing, acf * CF(0, 0, -.8), 3, 9, rng, 2.4, { Min = .9, Max = 2.4, Solid = true })
			for _, s in ipairs({ -1, 1 }) do
				K.Part(dressing, "AditPlank", V3(7.2, .5, .25), acf * CF(0, 3 + s * 1.4, -.4) * ANG(0, 0, s * .35), COL.TimberDark, M.Wood)
			end
			G.Skull(dressing, acf * CF(0, 7.3, -.9), 1.1, COL.Violet, COL.Bone)
			track(dressing, { V3(96, 0, 2560) + V3(-2, 0, 0), V3(80, 0, 2552) }, 3, 0)
		end
		-- ore heap + broken barrow + timber stack on the forecourt
		do
			local hp = V3(120, 0, 2481)
			for k = 1, 6 do
				rock(dressing, V3(rng:NextNumber(2, 3.5), rng:NextNumber(1.2, 2.2), rng:NextNumber(2, 3.5)),
					at(hp.X + rng:NextNumber(-2.5, 2.5), .7 + (k > 4 and 1.2 or 0), hp.Z + rng:NextNumber(-2, 2)) * ANG(rng:NextNumber(-.3, .3), rng:NextNumber(0, PI), rng:NextNumber(-.3, .3)), C(60, 50, 72))
			end
			for k = 1, 4 do
				K.Wedge(dressing, "OreCrystal", V3(.8, rng:NextNumber(1.4, 2.4), .8), at(hp.X + rng:NextNumber(-2, 2), 2.2, hp.Z + rng:NextNumber(-1.5, 1.5)) * ANG(rng:NextNumber(-.4, .4), rng:NextNumber(0, PI), rng:NextNumber(-.4, .4)),
					CRYSTAL, M.Neon, { Transparency = .1 })
				local _ = k
			end
			local tcf = at(140, 0, 2478) * ANG(0, .2, 0)
			for k = 0, 2 do
				for j = 0, 2 - k do
					K.CylX(dressing, "TimberStack", 7, 1, tcf * CF(0, .5 + k * .85, (j - (2 - k) / 2) * 1.05), COL.Timber:Lerp(COL.TimberDark, rng:NextNumber(0, .6)), M.Wood, j == 0 and G.Solid() or nil)
				end
			end
		end

		------------------------------------------------------------------------------------------------- FX emitters
		for _, t in ipairs(shaftTops) do
			local host = G.EmitterPart(fxm, "ShaftDust", V3(5, 10, 5), at(t.X, FY + 8, t.Z))
			G.Motes(host, { Color = COL.Moon, Rate = 2.5, Size = .25, Speed = .2 })
		end
		for _, p in ipairs({ V3(130, FY, 2550), V3(178, FY, 2590), V3(165, FY, 2530) }) do
			local host = G.EmitterPart(fxm, "MineHaze", V3(24, 1, 24), at(p.X, p.Y + .8, p.Z))
			G.Fog(host, { Color = C(130, 100, 200), Color2 = C(70, 50, 110), Rate = .8, Size = { 6, 12 }, Transparency = .86 })
		end
		local mh = G.EmitterPart(fxm, "MouthBreath", V3(10, 2, 3), CF(E + V3(0, 1, 0) + t1 * 3))
		G.Fog(mh, { Color = C(150, 120, 230), Color2 = COL.MoonDim, Rate = 1.4, Size = { 5, 10 }, Transparency = .82 })
		for _, p in ipairs({ V3(150, FY, 2570), V3(130, FY, 2530), V3(190, FY, 2600) }) do
			Y.Marker(fxm, "FogPoint", p + V3(0, .4, 0))
		end

		local parts, nl, emitters = G.Count(root)
		ctx.Note(string.format("Undercrypt: %d parts, %d lights, %d emitters (budget 3200 / 30)", parts, nl, emitters))
		local _ = lights
		return root
	end,
}
