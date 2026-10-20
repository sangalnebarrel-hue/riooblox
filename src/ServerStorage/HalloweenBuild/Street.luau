-- THE DEAD YARD · Hollow Lane + the 7 Trick-or-Treat houses (ServerStorage.HalloweenBuild.Street, WP2).
-- Build-time only (hw/edits/deadyard.luau runs it through tools/sim.luau; the result is saved in the place).
-- Creates under ctx.Root:
--   Lane   (Model) : the cobbled street x 38..206, z 568..582 (top y 0.5), curbs, gutter, slabs, puddles, leaves, street sign.
--   Houses (Model) : House1..7 at Layout.Houses (footprint 16 x 14, doors at z 557 facing +Z), each one different.
-- Per house (WP10b's HouseFX/Houses rely on these):
--   Door model `Door` with attribute HwDoor = i (+ OpenAngle = 100, OpenSign = 1): PrimaryPart `DoorHinge` (invisible, on
--   the hinge line at the door's -X edge, mid-height) = the pivot; the door is CLOSED, every part non-collidable; it swings
--   inward (-Z) for pivot * CFrame.Angles(0, math.rad(OpenAngle) * OpenSign, 0). An invisible `DoorBlocker` collider keeps players out of the
--   doorway. `HouseInterior` (dark vestibule behind the door with a dim coloured PointLight `InteriorGlow` and watching eyes),
--   `CandyBowl` model (jack-o'-lantern bucket on the porch, Attachment `CandyPoint`), porch lantern (glass HwLantern +
--   PointLight), window glass with HwLantern (colour flicker; a few have a PointLight), CrowPerch attachments on roofs and
--   chimneys, FogPoint markers along the lane. House model attributes: HouseIndex, GlowColor.
local K = require(script.Parent.Kit)
local P = K.Palette
local C = K.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi
local Y = require(script.Parent.YardKit)
local Rng = Y.Rng
local solid = Y.Solid
local GLOW, GLOW_DIM = Y.GLOW, Y.GLOW_DIM

local DARK_GLASS = C(26, 22, 38)
local BRASS = C(196, 150, 70)

------------------------------------------------------------------------------------------------------------------
-- generic pieces
------------------------------------------------------------------------------------------------------------------

local gableTri = Y.GableTri
local cobweb = Y.Cobweb

-- gable roof in frame R: origin = centre of the wall-top plane, ridge along R.X, the two slopes fall toward +-Z.
-- returns { Ridge = part, Planes = {..}, Eave = {[s] = R-local eave point} }
local function gableRoof(m, R, len, span, rise, o, rng)
	local oh, ohe, t = o.Overhang or 1, o.GableOverhang or .7, o.Thick or .4
	local Lr = len + ohe * 2
	local slope = math.sqrt(span * span + rise * rise)
	local res = { Planes = {}, Eave = {} }
	for _, s in ipairs({ 1, -1 }) do
		local dirL = V3(0, -rise, s * span) / slope
		local nL = V3(0, span, s * rise) / slope
		local topL = V3(0, rise, 0) - dirL * .3 + nL * (t / 2)
		local eaveL = V3(0, 0, s * span) + dirL * oh + nL * (t / 2)
		res.Eave[s] = eaveL
		if o.Skip ~= s then
			local plane = K.Bar(m, "RoofDeck", R * topL, R * eaveL, Lr, t, o.Under or o.Color:Lerp(P.Ink, .55), M.WoodPlanks, solid())
			table.insert(res.Planes, plane)
			local pcf = plane.CFrame
			local Ls = (eaveL - topL).Magnitude
			local rows = o.Rows or 5
			local rowD = Ls / rows
			for r = 1, rows do
				local z = Ls / 2 - (r - .5) * rowD
				local segs = o.Segs or 2
				local x = -Lr / 2
				for k = 1, segs do
					local w = Lr / segs
					if k < segs and segs > 1 then
						w = w * rng:NextNumber(.75, 1.25)
					else
						w = Lr / 2 - x
					end
					local hole = o.Hole and o.Hole(s, r, k)
					if not hole and not (o.Damaged and rng:NextNumber() < o.Damaged) then
						local col = o.Color:Lerp(o.Color2 or P.Ink, rng:NextNumber(0, .35))
						K.Part(m, "Shingles", V3(w - .06, .2, rowD + .28), pcf * CF(x + w / 2, t / 2 + .09, z) * ANG(.06, 0, 0), col, M.Slate)
					end
					x += w
				end
			end
			-- eave fascia + gutter
			K.Part(m, "Fascia", V3(Lr, .45, .22), R * CF(eaveL + V3(0, -.12, s * .08)), o.Trim, M.Wood)
		end
	end
	res.Ridge = K.Part(m, "RidgeCap", V3(Lr + .2, .42, .95), R * CF(0, rise + t * .95, 0), o.RidgeColor or o.Trim:Lerp(P.Ink, .3), M.Slate)
	-- gable end walls + barge boards
	for _, e in ipairs({ -1, 1 }) do
		if o.Gables ~= false then
			gableTri(m, "GableWall", R * CF(e * (len / 2 - (o.WallT or .6) / 2), 0, 0), span * 2, rise, o.WallT or .6, o.Gable, o.GableMat or M.WoodPlanks, true)
		end
		if o.Barge ~= false then
			for _, s in ipairs({ 1, -1 }) do
				local eave = res.Eave[s]
				K.Bar(m, "BargeBoard", R * V3(e * (Lr / 2 - .12), rise + t * 1.1, 0), R * V3(e * (Lr / 2 - .12), eave.Y + t * .4, eave.Z),
					.26, .75, o.Trim, M.Wood)
			end
		end
	end
	return res
end

-- window on a wall. W = CFrame on the OUTER wall surface, LookVector = outward (local -Z is out).
local function window(m, W, w, h, st, rng)
	local trim = st.Trim
	K.Part(m, "WindowCasing", V3(w + .55, h + .55, .16), W * CF(0, 0, -.08), trim, M.Wood)
	local glow = st.Glow and (st.Dim and GLOW_DIM[st.Glow] or GLOW[st.Glow]) or DARK_GLASS
	local attrs = nil
	if st.Glow and st.Flicker then
		attrs = { HwLantern = st.Glow }
	end
	local pane
	if st.Round then
		pane = K.CylZ(m, "WindowGlass", .08, w, W * CF(0, 0, -.2), glow, st.Glow and M.Neon or M.Glass, { Attrs = attrs })
	else
		pane = K.Part(m, "WindowGlass", V3(w, h, .08), W * CF(0, 0, -.2), glow, st.Glow and M.Neon or M.Glass, { Attrs = attrs })
	end
	if st.Light and st.Glow then
		K.Light(pane, GLOW[st.Glow], st.Range or 11, st.Brightness or .5)
	end
	if not st.Round then
		if st.Mullion == true or (st.Mullion == nil and st.Glow and not st.Boards) then
			K.Part(m, "Mullion", V3(.16, h, .1), W * CF(0, 0, -.27), trim, M.Wood)
			K.Part(m, "Mullion", V3(w, .16, .1), W * CF(0, h * .12, -.27), trim, M.Wood)
		end
		if not st.NoSill then
			K.Part(m, "WindowSill", V3(w + .95, .22, .5), W * CF(0, -h / 2 - .32, -.25), trim:Lerp(P.Ink, .2), M.Wood)
		end
		if st.Glow or st.Head then
			K.Part(m, "WindowHead", V3(w + .85, .32, .32), W * CF(0, h / 2 + .38, -.16), trim, M.Wood)
		end
	else
		-- round window: four short frame bars as a cross
		K.Part(m, "Mullion", V3(.16, w, .1), W * CF(0, 0, -.28), trim, M.Wood)
		K.Part(m, "Mullion", V3(w, .16, .1), W * CF(0, 0, -.28), trim, M.Wood)
	end
	if st.Shutters then
		local sw = w * .5
		for _, sx in ipairs({ -1, 1 }) do
			local broken = st.Shutters == "broken" and sx == 1
			local cf = W * CF(sx * (w / 2 + .32 + sw / 2), 0, -.1)
			if broken then
				cf = W * CF(sx * (w / 2 + .32 + sw / 2) + .25, -.55, -.16) * ANG(0, 0, -.38)
			end
			K.Part(m, "Shutter", V3(sw, h + .3, .12), cf, st.ShutterColor or trim, M.WoodPlanks)
		end
	end
	if st.Boards then
		for b = 1, st.Boards do
			local yy = (b - (st.Boards + 1) / 2) * (h / (st.Boards + .4))
			K.Part(m, "Board", V3(w + .9, .42, .1), W * CF(rng:NextNumber(-.15, .15), yy, -.34) * ANG(0, 0, rng:NextNumber(-.32, .32)),
				P.WoodOld:Lerp(P.WoodDark, rng:NextNumber(0, .6)), M.WoodPlanks)
		end
	end
	if st.Silhouette then
		local sc = st.Silhouette == "witch" and 1 or .9
		local base = W * CF(st.SilX or w * .12, -h * .18, -.25)
		local ink = C(16, 10, 22)
		K.Part(m, "Silhouette", V3(.9 * sc, .8 * sc, .04), base, ink, M.SmoothPlastic)
		K.Part(m, "Silhouette", V3(.55 * sc, .36 * sc, .04), base * CF(-.6 * sc, -.18 * sc, 0), ink, M.SmoothPlastic)
		K.Wedge(m, "Silhouette", V3(.04, .45 * sc, .3 * sc), base * CF(.28 * sc, .55 * sc, 0) * ANG(0, PI / 2, 0), ink, M.SmoothPlastic)
		K.Part(m, "Silhouette", V3(1.2 * sc, .8 * sc, .04), base * CF(.15, -.75 * sc, 0), ink, M.SmoothPlastic)
		if st.Silhouette == "witch" then
			K.Wedge(m, "Silhouette", V3(.04, .9, .45), base * CF(-.1, .8, 0) * ANG(0, PI / 2, 0), ink, M.SmoothPlastic)
			K.Wedge(m, "Silhouette", V3(.04, .9, .45), base * CF(-.1, .8, 0) * ANG(0, -PI / 2, 0), ink, M.SmoothPlastic)
			K.Part(m, "Silhouette", V3(1.4, .1, .04), base * CF(-.1, .38, 0), ink, M.SmoothPlastic)
		end
	end
	if st.Web then
		cobweb(m, W * CF(-w / 2 - .1, h / 2 + .1, -.3), st.Web)
	end
	return pane
end

-- jack-o'-lantern candy bucket on a little crate (model `CandyBowl`)
local function candyBowl(parent, cf, i, rng, glow)
	local b = K.Model(parent, "CandyBowl")
	b:SetAttribute("HouseIndex", i)
	local crate = K.Part(b, "BowlCrate", V3(1.7, 1.3, 1.5), cf * CF(0, .65, 0), P.WoodOld, M.WoodPlanks, solid())
	K.Part(b, "BowlCrateBand", V3(1.76, .18, 1.56), cf * CF(0, .95, 0), P.WoodDark, M.Wood)
	local top = cf * CF(0, 1.3, 0)
	K.Ellipsoid(b, "BucketBody", V3(1.55, 1.25, 1.55), top * CF(0, .6, 0), P.Pumpkin, M.SmoothPlastic)
	K.CylY(b, "BucketRim", .16, 1.25, top * CF(0, 1.17, 0), P.PumpkinDark, M.SmoothPlastic)
	K.Wedge(b, "BucketEye", V3(.05, .26, .24), top * CF(-.27, .72, .76) * ANG(0, -PI / 2, 0), glow or C(30, 16, 10), M.Neon)
	K.Wedge(b, "BucketEye", V3(.05, .26, .24), top * CF(.27, .72, .76) * ANG(0, PI / 2, 0), glow or C(30, 16, 10), M.Neon)
	K.Part(b, "BucketMouth", V3(.62, .14, .05), top * CF(0, .42, .76), glow or C(30, 16, 10), M.Neon)
	-- handle arc
	K.Bar(b, "BucketHandle", (top * CF(-.66, 1.1, 0)).Position, (top * CF(.3, 1.85, 0)).Position, .09, .09, P.Ink, M.SmoothPlastic)
	local candy = { C(255, 92, 170), C(255, 220, 60), C(120, 230, 120), C(170, 100, 255) }
	for k = 1, 4 do
		local a = k / 4 * PI * 2 + rng:NextNumber(0, .5)
		local r = rng:NextNumber(.12, .42)
		K.Ball(b, "Candy", rng:NextNumber(.3, .4), top * CF(math.cos(a) * r, 1.27 + rng:NextNumber(0, .12), math.sin(a) * r), candy[k], M.SmoothPlastic)
	end
	-- a candy corn on the crate
	K.Wedge(b, "CandyCorn", V3(.22, .34, .2), cf * CF(.55, 1.47, .45), C(255, 170, 40), M.SmoothPlastic)
	K.Attach(crate, "CandyPoint", CF(0, 2.7, 0))
	return b
end

local function deadBush(m, cf, size, rng)
	K.Ellipsoid(m, "BushRoot", V3(size * .8, size * .3, size * .8), cf * CF(0, size * .1, 0), C(48, 38, 34), M.Wood)
	for k = 1, 4 do
		local a = k / 4 * PI * 2 + rng:NextNumber(-.4, .4)
		local tip = cf * V3(math.cos(a) * size * .55, size * rng:NextNumber(.7, 1.05), math.sin(a) * size * .55)
		K.Rod(m, "BushTwig", cf.Position + V3(0, .1, 0), tip, .14, C(58, 44, 40), M.Wood)
	end
end

------------------------------------------------------------------------------------------------------------------
-- fences along the front yards (z = house z + 16.6), runs x-11.5..-2.6 and 2.6..11.5
------------------------------------------------------------------------------------------------------------------
local function fenceRun(m, a, b, style, rng, colors)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local mid = (a + b) / 2
	local base = K.Look(mid, b) -- local -Z along the run, X across
	if style == "Picket" or style == "Broken" then
		local col = colors.FenceColor or colors.Trim:Lerp(C(180, 170, 160), .45)
		K.Part(m, "FenceRail", V3(.14, .22, len), base * CF(0, 1.05, 0), col:Lerp(P.Ink, .25), M.Wood)
		if style == "Picket" then
			K.Part(m, "FenceRail", V3(.14, .22, len), base * CF(0, 2.15, 0), col:Lerp(P.Ink, .25), M.Wood)
		end
		local n = math.floor(len / 1.25)
		for k = 0, n do
			local z = -len / 2 + .35 + k * (len - .7) / math.max(n, 1)
			local missing = rng:NextNumber() < (style == "Broken" and .35 or .1)
			if not missing then
				local h = rng:NextNumber(2.6, 3.1)
				local tilt = rng:NextNumber(-.1, .1) + (style == "Broken" and rng:NextNumber(-.25, .25) or 0)
				local p = K.Part(m, "Picket", V3(.12, h, .5), base * CF(.1, h / 2 - .05, z) * ANG(tilt, 0, 0), col:Lerp(P.Ink, rng:NextNumber(0, .3)), M.WoodPlanks, solid())
				K.Wedge(m, "PicketTip", V3(.12, .4, .5), p.CFrame * CF(0, h / 2 + .2, 0) * ANG(0, (k % 2) * PI, 0), col, M.WoodPlanks)
			end
		end
	elseif style == "Iron" then
		K.Part(m, "IronRail", V3(.14, .14, len), base * CF(0, .7, 0), P.Iron, M.CorrodedMetal)
		K.Part(m, "IronRail", V3(.14, .14, len), base * CF(0, 2.7, 0), P.Iron, M.CorrodedMetal)
		local n = math.floor(len / 1.25)
		for k = 0, n do
			local z = -len / 2 + .3 + k * (len - .6) / math.max(n, 1)
			local h = 3.1 + (k % 2) * .25
			K.Part(m, "IronBar", V3(.14, h, .14), base * CF(0, h / 2, z), P.Iron, M.CorrodedMetal, solid())
			if k % 2 == 0 then
				K.Ball(m, "IronFinial", .3, base * CF(0, h + .1, z), P.Iron, M.CorrodedMetal)
			end
		end
	elseif style == "Stone" then
		K.Part(m, "LowWall", V3(.9, 1.3, len), base * CF(0, .65, 0), P.StoneDark, M.Cobblestone, solid())
		K.Part(m, "LowWallCap", V3(1.15, .25, len + .2), base * CF(0, 1.42, 0), P.Stone, M.Slate)
		K.Part(m, "IronRail", V3(.12, .12, len), base * CF(0, 3.2, 0), P.Iron, M.CorrodedMetal)
		local n = math.floor(len / 1.1)
		for k = 0, n do
			local z = -len / 2 + .3 + k * (len - .6) / math.max(n, 1)
			K.Part(m, "IronBar", V3(.12, 2.1, .12), base * CF(0, 2.55, z), P.Iron, M.CorrodedMetal)
		end
	elseif style == "Bone" then
		K.Part(m, "FenceRail", V3(.16, .2, len), base * CF(0, 1, 0), P.WoodDark, M.Wood)
		K.Part(m, "FenceRail", V3(.16, .2, len), base * CF(0, 2.1, 0), P.WoodDark, M.Wood)
		local n = math.floor(len / 2.1)
		for k = 0, n do
			local z = -len / 2 + .35 + k * (len - .7) / math.max(n, 1)
			local h = rng:NextNumber(2.5, 2.9)
			local col = P.Bone:Lerp(P.BoneDark, rng:NextNumber(0, .5))
			K.CylY(m, "BonePicket", h, .3, base * CF(.12, h / 2, z) * ANG(rng:NextNumber(-.06, .06), 0, 0), col, M.SmoothPlastic, solid())
			K.Ball(m, "BoneKnob", .36, base * CF(.12, h, z - .15), col, M.SmoothPlastic)
			K.Ball(m, "BoneKnob", .36, base * CF(.12, h, z + .15), col, M.SmoothPlastic)
		end
	elseif style == "Chain" then
		local n = math.max(2, math.floor(len / 3.5))
		for k = 0, n do
			local z = -len / 2 + .2 + k * (len - .4) / n
			K.CylY(m, "ChainPost", 3.4, .22, base * CF(0, 1.7, z), P.Iron:Lerp(P.StoneLight, .3), M.DiamondPlate, solid())
		end
		K.Part(m, "ChainTopRail", V3(.16, .16, len), base * CF(0, 3.35, 0), P.Iron:Lerp(P.StoneLight, .3), M.DiamondPlate)
		K.Part(m, "ChainMesh", V3(.06, 3.1, len - .3), base * CF(0, 1.75, 0), C(120, 126, 130), M.DiamondPlate, { Transparency = .55, Solid = true })
		K.Part(m, "HazardTape", V3(.08, .3, len * .7), base * CF(-.06, 2.3, rng:NextNumber(-1, 1)) * ANG(rng:NextNumber(-.12, .12), 0, 0), C(240, 200, 40), M.SmoothPlastic)
	end
end

------------------------------------------------------------------------------------------------------------------
-- one house
------------------------------------------------------------------------------------------------------------------
local DECK = .8 -- local y of the porch deck / ground floor (world 1.0)

local function buildHouse(parent, i, lay, sp, rng)
	local m = K.Model(parent, "House" .. i)
	m:SetAttribute("HouseIndex", i)
	m:SetAttribute("GlowColor", sp.Glow)
	local H = CF(lay.Center.X, lay.Center.Y, lay.Center.Z)
	local function at(x, y, z)
		return H * CF(x, y, z)
	end
	local top = sp.WallTop
	local wallH = top - .75
	local wallMat = sp.WallMat or M.WoodPlanks
	local glow = GLOW[sp.Glow]

	-- foundation + walls ------------------------------------------------------------------------------------
	K.Part(m, "Foundation", V3(16.7, .75, 14.7), at(0, .375, 0), sp.Stone or C(74, 70, 82), M.Cobblestone, solid())
	K.Part(m, "FoundationCap", V3(16.9, .16, 14.9), at(0, .64, 0), (sp.Stone or C(74, 70, 82)):Lerp(P.StoneLight, .25), M.Slate)
	local U = sp.Upper -- optional upper-storey frame (jettied / leaning houses)
	local function wallSet(frame, y0, y1, out)
		local h = y1 - y0
		local yc = y0 + h / 2
		local z7 = 7 + (out or 0)
		K.Part(m, "Wall", V3(16, h, .6), frame * CF(0, yc, -6.7), sp.Wall, wallMat, solid())
		K.Part(m, "Wall", V3(.6, h, 13.4 + (out or 0)), frame * CF(-7.7, yc, (out or 0) / 2), sp.Wall, wallMat, solid())
		K.Part(m, "Wall", V3(.6, h, 13.4 + (out or 0)), frame * CF(7.7, yc, (out or 0) / 2), sp.Wall, wallMat, solid())
		return z7
	end
	local lowerTop = U and U.Y or top
	wallSet(H, .75, lowerTop)
	-- front wall with the door opening (door 3.4 x 6.6 from the deck)
	local lh = lowerTop - .75
	K.Part(m, "Wall", V3(6.3, lh, .6), at(-4.85, .75 + lh / 2, 6.7), sp.Wall, wallMat, solid())
	K.Part(m, "Wall", V3(6.3, lh, .6), at(4.85, .75 + lh / 2, 6.7), sp.Wall, wallMat, solid())
	K.Part(m, "Wall", V3(3.4, lowerTop - 7.4, .6), at(0, 7.4 + (lowerTop - 7.4) / 2, 6.7), sp.Wall, wallMat, solid())
	local frameUp = H
	if U then
		frameUp = H * CF(0, U.Y, 0) * ANG(0, 0, U.Lean or 0) * CF(0, -U.Y, 0)
		wallSet(frameUp, U.Y, top, U.Out)
		K.Part(m, "Wall", V3(16, top - U.Y, .6), frameUp * CF(0, U.Y + (top - U.Y) / 2, 6.7 + U.Out), sp.Wall2 or sp.Wall, wallMat, solid())
		K.Part(m, "Jetty", V3(16.4, .5, 14.2 + U.Out), frameUp * CF(0, U.Y - .1, U.Out / 2), sp.Trim, M.Wood)
	end
	-- corner boards + skirt
	for _, cx in ipairs({ -7.85, 7.85 }) do
		for _, cz in ipairs({ -6.85, 6.85 }) do
			K.Part(m, "CornerBoard", V3(.7, lowerTop - .75, .7), at(cx, .75 + (lowerTop - .75) / 2, cz), sp.Trim, M.Wood)
			if U then
				K.Part(m, "CornerBoard", V3(.7, top - U.Y, .7), frameUp * CF(cx, U.Y + (top - U.Y) / 2, cz + (cz > 0 and U.Out or 0)), sp.Trim, M.Wood)
			end
		end
	end
	K.Part(m, "Frieze", V3(16.5, .5, .3), frameUp * CF(0, top - .35, 7.05 + (U and U.Out or 0)), sp.Trim, M.Wood)
	if sp.Belt then
		K.Part(m, "BeltCourse", V3(16.4, .4, .3), at(0, sp.Belt, 7.08), sp.Trim, M.Wood)
		K.Part(m, "BeltCourse", V3(.3, .4, 14.2), at(-8.08, sp.Belt, 0), sp.Trim, M.Wood)
		K.Part(m, "BeltCourse", V3(.3, .4, 14.2), at(8.08, sp.Belt, 0), sp.Trim, M.Wood)
	end

	-- wall frames for windows: face F(+Z) B(-Z) L(-X) R(+X); u = coordinate along the wall
	local function W(face, u, y, frame)
		frame = frame or H
		local out = (frame ~= H and U) and U.Out or 0
		if face == "F" then
			return frame * CF(u, y, 7 + out) * ANG(0, PI, 0)
		elseif face == "B" then
			return frame * CF(u, y, -7)
		elseif face == "L" then
			return frame * CF(-8, y, u) * ANG(0, PI / 2, 0)
		else
			return frame * CF(8, y, u) * ANG(0, -PI / 2, 0)
		end
	end
	for _, wd in ipairs(sp.Windows) do
		local st = setmetatable({ Trim = wd.Trim or sp.WindowTrim or sp.Trim, ShutterColor = sp.Shutter, NoSill = wd[1] == "B" }, { __index = wd })
		window(m, W(wd[1], wd[2], wd[3], wd.Upper and frameUp or H), wd[4] or 2.4, wd[5] or 3.2, st, rng)
	end

	-- door frame, door model, number plate ------------------------------------------------------------------
	for _, sx in ipairs({ -1, 1 }) do
		K.Part(m, "DoorJamb", V3(.42, 6.95, .4), at(sx * 1.92, DECK + 3.47, 7.08), sp.Trim, M.Wood)
	end
	K.Part(m, "DoorHead", V3(4.5, .5, .5), at(0, DECK + 7.15, 7.12), sp.Trim, M.Wood)
	gableTri(m, "DoorPediment", at(0, DECK + 7.4, 7.15) * ANG(0, PI / 2, 0), 4.2, .75, .32, sp.Trim:Lerp(P.Ink, .2), M.Wood)
	local d = K.Model(m, "Door")
	d.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams as a whole: never on a client without its DoorHinge
	d:SetAttribute("HwDoor", i)
	d:SetAttribute("OpenAngle", 100)
	d:SetAttribute("OpenSign", 1)
	local dw, dh = 3.4, 6.6
	local hingeCF = at(-dw / 2, DECK, 6.86)
	-- the hinge part sits exactly on the hinge line: Roblox's GetPivot() = PrimaryPart.CFrame (WorldPivot set here does not
	-- survive the Lune place serialization, so the PrimaryPart is what defines the pivot in the saved place). The line is
	-- the slab's back hinge edge (z -.13), so the inward-swinging slab clears the wall reveal instead of cutting into it
	local hinge = K.Part(d, "DoorHinge", V3(.2, dh, .2), hingeCF * CF(0, dh / 2, -.13), P.Iron, M.CorrodedMetal, { Transparency = 1 })
	d.PrimaryPart = hinge
	d.WorldPivot = hinge.CFrame
	local dcol = sp.DoorColor or P.WoodDark
	K.Part(d, "DoorSlab", V3(dw - .08, dh - .04, .26), hingeCF * CF(dw / 2, dh / 2, 0), dcol, M.WoodPlanks)
	K.Part(d, "DoorPanel", V3(dw - 1, dh * .34, .1), hingeCF * CF(dw / 2, dh * .25, .16), dcol:Lerp(P.Ink, .3), M.Wood)
	K.Part(d, "DoorPanel", V3(dw - 1, dh * .3, .1), hingeCF * CF(dw / 2, dh * .68, .16), dcol:Lerp(P.Ink, .3), M.Wood)
	K.Part(d, "DoorPeephole", V3(.8, .95, .06), hingeCF * CF(dw / 2, dh * .72, .22), GLOW_DIM[sp.Glow], M.Neon)
	for _, yy in ipairs({ dh * .1, dh * .9 }) do
		K.Part(d, "DoorStrap", V3(dw * .62, .22, .06), hingeCF * CF(dw * .31, yy, .17), P.Iron, M.CorrodedMetal)
	end
	K.Ball(d, "DoorKnob", .36, hingeCF * CF(dw - .42, dh * .44, .26), BRASS, M.Metal)
	local kc = hingeCF * CF(dw / 2, dh * .5, .2)
	K.Ball(d, "KnockerSkull", .42, kc * CF(0, .32, .04), P.Bone, M.SmoothPlastic)
	K.Part(d, "KnockerJaw", V3(.26, .14, .14), kc * CF(0, .1, .1), P.BoneDark, M.SmoothPlastic)
	K.CylZ(d, "KnockerRing", .07, .78, kc * CF(0, -.32, .08), BRASS, M.Metal)
	K.CylZ(d, "KnockerRingHole", .07, .5, kc * CF(0, -.32, .1), dcol:Lerp(P.Ink, .4), M.Wood)
	K.Part(m, "DoorBlocker", V3(3.4, 6.7, .2), at(0, DECK + 3.35, 6.3), P.Ink, nil, { Transparency = 1, Solid = true, Shadow = false })
	local plate = K.Part(m, "HouseNumber", V3(1.15, 1.45, .1), at(2.95, DECK + 4.9, 7.06), BRASS, M.Metal)
	local g = K.Sign(plate, N.Back, tostring(i), C(40, 24, 18), { PixelsPerStud = 40, Stroke = false, W = .8, H = .86 })
	g:SetAttribute("NoTranslate", true)

	-- interior vestibule behind the door ----------------------------------------------------------------------
	local it = K.Model(m, "HouseInterior")
	local dark = C(34, 24, 42)
	local zf, zb = 6.4, .9
	local cz, dz = (zf + zb) / 2, zf - zb
	K.Part(it, "InteriorFloor", V3(5.6, .2, dz), at(0, DECK - .1, cz), C(30, 22, 26), M.WoodPlanks, solid())
	K.Part(it, "InteriorBack", V3(5.6, 7.9, .3), at(0, DECK + 3.95, zb - .15), dark, M.Fabric, solid())
	K.Part(it, "InteriorSide", V3(.3, 7.9, dz), at(-2.75, DECK + 3.95, cz), dark, M.Fabric, solid())
	K.Part(it, "InteriorSide", V3(.3, 7.9, dz), at(2.75, DECK + 3.95, cz), dark, M.Fabric, solid())
	K.Part(it, "InteriorCeiling", V3(5.6, .3, dz), at(0, DECK + 7.75, cz), dark, M.Fabric)
	K.Part(it, "InteriorRug", V3(3, .04, 3.8), at(0, DECK + .02, cz + .3), C(90, 26, 36), M.Fabric)
	K.Ball(it, "WatchingEye", .22, at(-.95, DECK + 4.7, zb + .05), glow, M.Neon)
	K.Ball(it, "WatchingEye", .22, at(-.35, DECK + 4.7, zb + .05), glow, M.Neon)
	local gl = K.Part(it, "InteriorGlow", V3(.3, .3, .3), at(0, DECK + 5.4, (zf + zb) / 2 - .6), glow, M.Neon, { Transparency = 1 })
	K.Light(gl, glow, 8, .55)

	-- porch -------------------------------------------------------------------------------------------------
	local pw = sp.PorchW or 11
	local px = sp.PorchX or 0
	local wood = sp.Deck or C(70, 52, 46)
	K.Part(m, "PorchDeck", V3(pw, .32, 4.3), at(px, DECK - .16, 9.15), wood, sp.DeckMat or M.WoodPlanks, solid())
	K.Part(m, "PorchSkirt", V3(pw - .2, .62, .2), at(px, .31, 11.2), C(32, 24, 32), M.WoodPlanks)
	K.Part(m, "PorchStep", V3(4.6, .53, .92), at(0, .265, 11.76), sp.StepColor or C(84, 78, 92), M.Slate, solid())
	K.Part(m, "PorchStep", V3(5.1, .27, .92), at(0, .135, 12.66), (sp.StepColor or C(84, 78, 92)):Lerp(P.Ink, .15), M.Slate, solid())
	local roofY0, roofY1 = DECK + 7.85, DECK + 7.1
	local postZ = 10.85
	local posts = sp.Posts or { px - pw / 2 + .4, px + pw / 2 - .4 }
	local py1 = roofY1 - (sp.Sag or 0)
	for k, xx in ipairs(posts) do
		local lean = (sp.BrokenPost == k) and .12 or 0
		K.Part(m, "PorchPost", V3(.52, py1 - DECK - .3, .52), at(xx, DECK + (py1 - DECK) / 2, postZ) * ANG(lean, 0, lean), sp.Post or sp.Trim:Lerp(P.Cream, .25), M.Wood, solid())
		K.Part(m, "PorchPostCap", V3(.8, .3, .8), at(xx, py1 - .3, postZ), sp.Trim, M.Wood)
		if sp.Brackets ~= false then
			K.Wedge(m, "PorchBracket", V3(.22, .9, .9), at(xx, py1 - .85, postZ - .5), sp.Trim, M.Wood)
		end
	end
	local sag = sp.Sag or 0
	local proof = K.Bar(m, "PorchRoof", (at(px, roofY0, 6.95) * CF(0, 0, 0)).Position, (at(px, roofY1 - sag, 11.95)).Position, pw + .7, .3, sp.Roof:Lerp(P.Ink, .3), M.Slate, solid())
	if sag ~= 0 then
		proof.CFrame = proof.CFrame * ANG(0, 0, sag * .08)
	end
	for r, z in ipairs({ 1.25, -1.15 }) do
		K.Part(m, "Shingles", V3(pw + .7, .18, 2.6), proof.CFrame * CF(0, .2, z) * ANG(.06, 0, 0), sp.Roof:Lerp(P.Ink, r * .12), M.Slate)
	end
	K.Part(m, "PorchFascia", V3(pw + .8, .5, .22), at(px, roofY1 - .2 - sag, 12), sp.Trim, M.Wood)
	-- rails: front runs on both sides of the steps, side runs back to the wall
	-- a, b are on the deck surface; offsets below are heights above the deck
	local function rail(a, b, balusters, broken, noBottom)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = K.Look(mid, b)
		if not broken then
			K.Part(m, "PorchRail", V3(.32, .2, len), cf * CF(0, 2.5, 0), sp.Trim, M.Wood, solid())
		else
			K.Part(m, "PorchRail", V3(.32, .2, len * .55), cf * CF(0, 2.2, len * .22) * ANG(.35, 0, 0), sp.Trim, M.Wood)
		end
		if not noBottom then
			K.Part(m, "PorchRail", V3(.26, .18, len), cf * CF(0, .45, 0), sp.Trim, M.Wood)
		end
		for k = 1, balusters do
			local z = -len / 2 + k * len / (balusters + 1)
			K.Part(m, "Baluster", V3(.22, 2.05, .22), cf * CF(0, 1.5, z), sp.Trim:Lerp(P.Cream, .15), M.Wood)
		end
	end
	local lx, rx = px - pw / 2 + .4, px + pw / 2 - .4
	if lx < -3.2 then
		rail(H * V3(lx, DECK, postZ), H * V3(-2.55, DECK, postZ), 2, sp.BrokenRail == "L")
	end
	if rx > 3.2 then
		rail(H * V3(2.55, DECK, postZ), H * V3(rx, DECK, postZ), 2, sp.BrokenRail == "R")
	end
	rail(H * V3(lx, DECK, 7.3), H * V3(lx, DECK, postZ - .4), 1, false, true)
	rail(H * V3(rx, DECK, 7.3), H * V3(rx, DECK, postZ - .4), 1, false, true)
	-- porch lantern hanging from the porch roof (left of the door)
	local lpos = at(-2.95, DECK + 5.2, 8.7)
	K.Part(m, "LanternHook", V3(.12, roofY0 - (DECK + 5.2) - 1.5, .12), lpos * CF(0, (roofY0 - (DECK + 5.2) - 1.5) / 2 + 1.25, 0), P.Iron, M.CorrodedMetal)
	K.Lantern(m, lpos, glow, sp.Glow, { Range = 15, Brightness = 1 })
	-- candy bowl right of the door
	candyBowl(m, at(3.9, DECK, 8.9), i, rng, glow)
	-- porch cobweb (top-left inner corner between post and roof)
	cobweb(m, at(lx + .35, roofY1 - .5 - (sp.Sag or 0), postZ), 1.6)

	-- path to the lane --------------------------------------------------------------------------------------
	for k, z in ipairs({ 14.3, 16.5 }) do
		K.Part(m, "PathStone", V3(2.9 + rng:NextNumber(-.3, .3), .3, 1.7), at(rng:NextNumber(-.3, .3), .14, z) * ANG(0, rng:NextNumber(-.18, .18), 0),
			C(86, 80, 92):Lerp(P.Ink, rng:NextNumber(0, .3)), M.Slate)
	end

	-- roof ---------------------------------------------------------------------------------------------------
	local roofRes
	if sp.RoofType == "Front" then
		local R = frameUp * CF(0, top, (U and U.Out or 0) / 2) * ANG(0, PI / 2, 0)
		roofRes = gableRoof(m, R, 14 + (U and U.Out or 0), 8, sp.Rise, { Color = sp.Roof, Trim = sp.Trim, Gable = sp.Wall2 or sp.Wall, Rows = sp.Rows or 6,
			Damaged = sp.Damaged, Hole = sp.Hole, Overhang = 1.1, Segs = 2 }, rng)
	elseif sp.RoofType == "Side" then
		local R = frameUp * CF(0, top, (U and U.Out or 0) / 2)
		roofRes = gableRoof(m, R, 16, 7 + (U and U.Out or 0) / 2, sp.Rise, { Color = sp.Roof, Trim = sp.Trim, Gable = sp.Wall2 or sp.Wall, Rows = sp.Rows or 4,
			Damaged = sp.Damaged, Hole = sp.Hole, Segs = 2 }, rng)
	end
	if roofRes then
		local rl = roofRes.Ridge.Size.X
		K.Attach(roofRes.Ridge, "CrowPerch", CF(-rl / 2 + .4, .35, 0))
		K.Attach(roofRes.Ridge, "CrowPerch", CF(rl / 2 - .4, .35, 0))
	end

	-- chimney -----------------------------------------------------------------------------------------------
	if sp.Chimney then
		local ch = sp.Chimney
		local x, z, y0, y1 = ch[1], ch[2], ch[3], ch[4]
		local cw = ch.W or 1.8
		local mat = ch.Mat or M.Brick
		local col = ch.Color or C(110, 70, 62)
		local tilt = ch.Tilt or 0
		local base = frameUp * CF(x, y0, z) * ANG(0, 0, tilt)
		K.Part(m, "Chimney", V3(cw, y1 - y0, cw), base * CF(0, (y1 - y0) / 2, 0), col, mat, solid())
		K.Part(m, "ChimneyBand", V3(cw + .3, .3, cw + .3), base * CF(0, y1 - y0 - .9, 0), col:Lerp(P.Ink, .3), M.Slate)
		local cap = K.Part(m, "ChimneyCap", V3(cw + .5, .35, cw + .5), base * CF(0, y1 - y0 + .1, 0), C(60, 56, 66), M.Slate)
		K.CylY(m, "ChimneyPot", .9, .6, base * CF(-cw * .2, y1 - y0 + .7, 0), C(140, 84, 60), M.SmoothPlastic)
		K.Attach(cap, "CrowPerch", CF(cw * .3, .3, -cw * .25))
		if ch.Wide then -- exterior stone chimney with a wide base
			K.Part(m, "ChimneyBreast", V3(cw + 1, y0 + ch.Wide, cw + .6), frameUp * CF(x, (y0 + ch.Wide) / 2, z), col:Lerp(P.Ink, .15), mat, solid())
			K.Wedge(m, "ChimneyShoulder", V3(cw + 1, 1, .5), frameUp * CF(x, y0 + ch.Wide + .5, z), col:Lerp(P.Ink, .15), mat)
		end
	end

	-- yard: fence runs + gate posts -------------------------------------------------------------------------
	local fz = 16.6
	if sp.Fence then
		fenceRun(m, H * V3(-11.4, 0, fz), H * V3(-2.7, 0, fz), sp.Fence, rng, sp)
		fenceRun(m, H * V3(2.7, 0, fz), H * V3(11.4, 0, fz), sp.Fence, rng, sp)
		if sp.Fence ~= "Chain" then
			for _, sx in ipairs({ -1, 1 }) do
				local gp = K.Part(m, "GatePost", V3(.8, 3.6, .8), at(sx * 2.25, 1.8, fz), sp.Fence == "Stone" and P.StoneDark or sp.Trim, sp.Fence == "Stone" and M.Cobblestone or M.Wood, solid())
				K.Part(m, "GatePostCap", V3(1.05, .3, 1.05), at(sx * 2.25, 3.75, fz), sp.Fence == "Stone" and P.Stone or sp.Trim:Lerp(P.Ink, .3), M.Slate)
				K.Attach(gp, "CrowPerch", CF(0, 2.2, 0))
			end
		end
	end

	-- cobwebs on the front corners of the facade
	cobweb(m, at(-7.5, lowerTop - .5, 7.25), 2)

	-- house-specific extras
	if sp.Extras then
		sp.Extras(m, at, H, frameUp, rng, sp)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------
-- house-specific extras
------------------------------------------------------------------------------------------------------------------
local pumpkin = Y.Pumpkin

-- a round attic window that is a carved jack-o'-lantern face (orange glow + ink face cut-outs)
local function pumpkinFaceWindow(m, cf, d)
	local ink = C(20, 10, 16)
	K.CylZ(m, "AtticFrame", .2, d + .6, cf * CF(0, 0, -.1), C(60, 40, 50), M.Wood)
	K.CylZ(m, "AtticGlass", .08, d, cf * CF(0, 0, -.22), GLOW.Orange, M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Wedge(m, "AtticFace", V3(.05, d * .22, d * .2), cf * CF(-d * .2, d * .1, -.28) * ANG(0, PI / 2, 0), ink, M.SmoothPlastic)
	K.Wedge(m, "AtticFace", V3(.05, d * .22, d * .2), cf * CF(d * .2, d * .1, -.28) * ANG(0, PI / 2, 0), ink, M.SmoothPlastic)
	K.Part(m, "AtticFace", V3(d * .55, d * .1, .05), cf * CF(0, -d * .18, -.28), ink, M.SmoothPlastic)
	K.Part(m, "AtticFace", V3(d * .1, d * .08, .05), cf * CF(-d * .1, -d * .12, -.29), ink, M.SmoothPlastic)
	K.Part(m, "AtticFace", V3(d * .1, d * .08, .05), cf * CF(d * .12, -d * .24, -.29), ink, M.SmoothPlastic)
end

local EXTRAS = {}

EXTRAS[1] = function(m, at, H, U, rng, sp)
	-- jack-o'-lantern attic window in the front gable
	pumpkinFaceWindow(m, at(0, sp.WallTop + 2.6, 7.05) * ANG(0, PI, 0), 3)
	-- pumpkins piled on the steps and the yard
	pumpkin(m, at(-2.1, .53, 11.7), 1.5)
	pumpkin(m, at(-3.4, DECK, 10.2) * ANG(0, -.4, 0), 1.3, { Face = false, Lobes = 4 })
	pumpkin(m, at(-6.3, 0, 13.4) * ANG(0, .5, 0), 2.1, { Face = true })
	pumpkin(m, at(6.2, 0, 13.6) * ANG(0, -.6, 0), 1.6, { Face = false, Lobes = 4 })
	-- vine across the yard
	K.Rod(m, "PumpkinVine", (at(-7.2, .25, 12.6)).Position, (at(-4.6, .25, 15.2)).Position, .18, P.Stem, M.Grass)
	K.Rod(m, "PumpkinVine", (at(-4.6, .25, 15.2)).Position, (at(-3.2, .25, 14.0)).Position, .16, P.Stem, M.Grass)
	-- hanging wooden sign on the porch post with a pumpkin
	local s = K.Part(m, "WelcomeBoard", V3(2.6, 1.1, .14), at(5.6, DECK + 4.8, 11.05), C(120, 86, 60), M.WoodPlanks)
	K.Ellipsoid(m, "BoardPumpkin", V3(.7, .55, .1), s.CFrame * CF(0, 0, .09), P.Pumpkin, M.SmoothPlastic)
	K.Part(m, "BoardRope", V3(.06, .9, .06), s.CFrame * CF(-1, .95, 0), C(150, 120, 80), M.Fabric)
	K.Part(m, "BoardRope", V3(.06, .9, .06), s.CFrame * CF(1, .95, 0), C(150, 120, 80), M.Fabric)
end

EXTRAS[2] = function(m, at, H, U, rng, sp)
	-- dormer on the front roof slope with a green lit window
	local top = sp.WallTop
	local dcf = U * CF(-3.2, top + 1.4, 5.3)
	K.Part(m, "Dormer", V3(3.2, 3, 3), dcf * CF(0, .9, -.6), sp.Wall2 or sp.Wall, M.WoodPlanks, solid())
	gableTri(m, "DormerGable", dcf * CF(0, 2.4, .9) * ANG(0, PI / 2, 0), 3.6, 1.6, .3, sp.Wall2 or sp.Wall, M.WoodPlanks)
	K.Bar(m, "DormerRoof", (dcf * CF(0, 4.15, -.3)).Position, (dcf * CF(-2.15, 2.25, -.3)).Position, 3.4, .22, sp.Roof, M.Slate)
	K.Bar(m, "DormerRoof", (dcf * CF(0, 4.15, -.3)).Position, (dcf * CF(2.15, 2.25, -.3)).Position, 3.4, .22, sp.Roof, M.Slate)
	window(m, dcf * CF(0, 1.1, .92) * ANG(0, PI, 0), 1.5, 1.6, { Trim = sp.Trim, Glow = "Green", Flicker = true }, rng)
	-- dead bushes + a tilted mailbox by the lane
	deadBush(m, at(-6.2, 0, 14.2), 2.2, rng)
	deadBush(m, at(6.6, 0, 13.4), 1.8, rng)
	pumpkin(m, at(2.15, .53, 11.75) * ANG(0, .35, 0), 1.35, { Glow = GLOW.Green })
	deadBush(m, at(9.6, 0, 15.6), 1.5, rng)
	local mb = at(-3.8, 0, 17.2) * ANG(0, 0, .14)
	K.Part(m, "MailPost", V3(.35, 3.2, .35), mb * CF(0, 1.6, 0), P.WoodDark, M.Wood, solid())
	K.Part(m, "Mailbox", V3(1, .9, 1.8), mb * CF(0, 3.4, 0), C(40, 50, 60), M.CorrodedMetal)
	K.CylZ(m, "MailboxTop", 1.8, 1, mb * CF(0, 3.85, 0), C(40, 50, 60), M.CorrodedMetal)
	K.Part(m, "MailFlag", V3(.08, .7, .3), mb * CF(.55, 3.7, -.4), P.Blood, M.SmoothPlastic)
	K.Part(m, "MailLetter", V3(.05, .5, .8), mb * CF(0, 3.5, .95) * ANG(.4, 0, 0), P.Cream, M.SmoothPlastic)
end

EXTRAS[3] = function(m, at, H, U, rng, sp)
	-- round witch tower on the front-right corner with a crooked stacked-cone hat
	local tx, tz = 6.3, 5.2
	local th = sp.WallTop + 6.4
	local tcol = C(96, 92, 116)
	local tower = K.CylY(m, "Tower", th - .75, 5.6, at(tx, .75 + (th - .75) / 2, tz), tcol, M.Cobblestone, solid())
	K.CylY(m, "TowerBase", .9, 6.2, at(tx, .45, tz), C(70, 66, 80), M.Cobblestone, solid())
	K.CylY(m, "TowerBand", .45, 6.0, at(tx, sp.WallTop - .2, tz), sp.Trim, M.Wood)
	K.CylY(m, "TowerEave", .4, 6.9, at(tx, th + .1, tz), sp.Trim, M.Wood)
	-- narrow arched windows facing the lane and the side
	for k, a in ipairs({ PI * .5, PI * .28, -PI * .05 }) do
		local dir = V3(math.cos(a), 0, math.sin(a))
		local y = k == 1 and th - 2.6 or 4.2 + (k - 2) * 4.6
		local p = (at(tx, y, tz)).Position + dir * 2.82
		local Wc = K.Look(p, p + dir)
		K.Part(m, "TowerWindowFrame", V3(1.5, 2.6, .2), Wc * CF(0, 0, .02), sp.Trim, M.Wood)
		K.Part(m, "TowerWindow", V3(1.05, 2.1, .1), Wc * CF(0, 0, -.06), GLOW.Purple, M.Neon,
			{ Attrs = k == 1 and { HwLantern = "Purple" } or nil })
		K.Part(m, "TowerSill", V3(1.6, .2, .4), Wc * CF(0, -1.25, -.15), sp.Trim, M.Wood)
	end
	-- hat: stacked shrinking discs, the tip bends over
	local y = th + .3
	local d = 7.2
	local off = V3(0, 0, 0)
	for k = 1, 8 do
		local hgt = 1.15
		d = d * .8
		off += V3(k > 5 and .22 or 0, 0, k > 5 and -.08 or 0)
		K.CylY(m, "TowerHat", hgt, d, at(tx, y + hgt / 2, tz) * CF(off), sp.Roof:Lerp(P.Ink, k * .03), M.Slate, k == 1 and solid() or nil)
		y += hgt * .9
	end
	local tip = K.Ball(m, "TowerHatTip", .5, at(tx, y + .1, tz) * CF(off + V3(.35, 0, -.1)), GLOW.Purple, M.Neon)
	K.Attach(tip, "CrowPerch", CF(0, .3, 0))
	K.Attach(tower, "BatRoost", CF((th - .75) / 2 - .3, 0, 0))
	-- witch broom leaning by the door + cauldron pot in the yard
	K.Rod(m, "BroomStick", (at(-3.2, DECK, 8.2)).Position, (at(-3.9, DECK + 4.2, 7.45)).Position, .18, C(110, 80, 50), M.Wood)
	K.CylY(m, "BroomBristles", 1.1, .7, at(-3.12, DECK + .5, 8.25) * ANG(.16, 0, -.1), C(170, 140, 80), M.Fabric)
	local pot = at(-5.6, 0, 13.6)
	K.CylY(m, "YardCauldron", 1.3, 2.1, pot * CF(0, .75, 0), C(30, 28, 36), M.CorrodedMetal, solid())
	K.CylY(m, "YardCauldronRim", .2, 2.3, pot * CF(0, 1.42, 0), C(44, 42, 50), M.CorrodedMetal)
	K.CylY(m, "YardCauldronBrew", .1, 1.8, pot * CF(0, 1.4, 0), GLOW.Purple, M.Neon)
	pumpkin(m, at(4.8, 0, 13.8) * ANG(0, -.3, 0), 1.6, { Light = false })
end

EXTRAS[4] = function(m, at, H, U, rng, sp)
	-- central cross gable over the porch with a great round "eye" window
	local top = sp.WallTop
	local R = H * CF(0, top, 3.9) * ANG(0, PI / 2, 0)
	local res = gableRoof(m, R, 6.6, 4.6, 5.4, { Color = sp.Roof, Trim = sp.Trim, Gable = sp.Wall, Rows = 4, Segs = 1, Overhang = .7, GableOverhang = .5 }, rng)
	local eye = at(0, top + 1.9, 7.25) * ANG(0, PI, 0)
	K.CylZ(m, "EyeFrame", .25, 3.2, eye * CF(0, 0, -.05), sp.Trim, M.Wood)
	K.CylZ(m, "EyeGlass", .1, 2.6, eye * CF(0, 0, -.2), GLOW.Orange, M.Neon, { Attrs = { HwLantern = "Orange" } })
	K.Ellipsoid(m, "EyePupil", V3(.7, 1.9, .06), eye * CF(.2, 0, -.27), C(30, 10, 10), M.SmoothPlastic)
	K.Attach(res.Ridge, "CrowPerch", CF(-res.Ridge.Size.X / 2 + .3, .35, 0))
	-- dog weathervane on the cross gable apex
	local wv = res.Ridge.CFrame * CF(-res.Ridge.Size.X / 2 + 1, .2, 0)
	K.Part(m, "VaneRod", V3(.12, 2.4, .12), wv * CF(0, 1.2, 0), P.Iron, M.CorrodedMetal)
	K.Part(m, "VaneArrow", V3(.08, .08, 2.2), wv * CF(0, 1.9, 0), P.Iron, M.CorrodedMetal)
	K.Part(m, "VaneDog", V3(.08, .5, 1.1), wv * CF(0, 2.5, 0), P.Iron, M.CorrodedMetal)
	K.Part(m, "VaneDog", V3(.08, .5, .5), wv * CF(0, 2.85, -.55), P.Iron, M.CorrodedMetal)
	K.Wedge(m, "VaneDog", V3(.08, .3, .2), wv * CF(0, 3.2, -.45), P.Iron, M.CorrodedMetal)
	-- urns with dead flowers on the stone gate posts + pumpkins on the steps
	for _, sx in ipairs({ -1, 1 }) do
		pumpkin(m, at(sx * 2.25, 3.9, 16.6) * ANG(0, sx * .3, 0), 1.3, { Light = false })
	end
end

EXTRAS[5] = function(m, at, H, U, rng, sp)
	-- exposed rafters in the roof hole (front slope, near the right end)
	local top, rise, span = sp.WallTop, sp.Rise, 7
	local slope = math.sqrt(rise * rise + span * span)
	local n = V3(0, span, rise) / slope
	local function onRoof(x, f, lift) -- f = 0 ridge .. 1 eave
		return (at(x, top + rise * (1 - f), span * f)).Position + n * lift
	end
	K.Bar(m, "HoleGlow", onRoof(6.4, .08, .43), onRoof(6.4, .8, .43), 4.4, .04, C(40, 90, 36), M.Neon)
	for k = 0, 3 do
		K.Bar(m, "Rafter", onRoof(4.9 + k * 1.15, 0, .7), onRoof(4.9 + k * 1.15, 1.05, .7), .3, .36, C(84, 62, 48), M.Wood)
	end
	K.Bar(m, "Purlin", onRoof(4.3, .45, .95), onRoof(8.6, .45, .95), .26, .3, C(70, 52, 42), M.Wood)
	-- fallen shingles + planks on the porch roof and the yard
	K.Part(m, "FallenPlank", V3(3.4, .15, .6), at(5.5, .3, 14.2) * ANG(0, .7, .15), P.WoodOld, M.WoodPlanks)
	K.Part(m, "FallenPlank", V3(2.6, .15, .5), at(6.6, .25, 13.1) * ANG(0, -.4, 0), P.WoodOld:Lerp(P.Ink, .3), M.WoodPlanks)
	K.Part(m, "FallenShingles", V3(1.6, .14, 1.1), at(3.6, .22, 15.1) * ANG(0, .3, .05), sp.Roof, M.Slate)
	-- KEEP OUT plank across the porch rail
	local ko = K.Part(m, "KeepOut", V3(3.6, .9, .12), at(-3.6, DECK + 2.3, 11.15) * ANG(0, 0, .12), P.WoodOld, M.WoodPlanks)
	K.Sign(ko, N.Back, "KEEP OUT", P.Blood, { PixelsPerStud = 30, Stroke = false })
	-- green light spilling from under the door
	K.Part(m, "DoorGlowSpill", V3(2.8, .04, .7), at(0, DECK + .02, 7.4), GLOW_DIM.Green, M.Neon)
	pumpkin(m, at(2.2, .53, 11.7) * ANG(0, .5, .2), 1.1, { Face = false })
	pumpkin(m, at(-6.5, 0, 13.9) * ANG(0, .2, 0), 1.7, { Glow = GLOW.Green, Light = false })
	deadBush(m, at(7.2, 0, 14.5), 2, rng)
end

EXTRAS[6] = function(m, at, H, U, rng, sp)
	-- oriel bay window over the porch roof
	local y = 10.4
	local base = at(0, y, 7)
	K.Part(m, "OrielBody", V3(4.6, 3.4, 1.4), base * CF(0, 0, .7), sp.Wall, M.WoodPlanks, solid())
	K.Part(m, "OrielRoof", V3(5.2, .35, 1.9), base * CF(0, 1.9, .75), sp.Roof, M.Slate)
	K.Wedge(m, "OrielRoofSlope", V3(5.2, .7, 1.9), base * CF(0, 2.4, .75) * ANG(0, PI, 0), sp.Roof:Lerp(P.Ink, .2), M.Slate)
	for k, xx in ipairs({ -1.4, 0, 1.4 }) do
		local Wc = base * CF(xx, .1, 1.42) * ANG(0, PI, 0)
		K.Part(m, "OrielGlass", V3(1.1, 2.2, .08), Wc * CF(0, 0, -.05), GLOW.Purple, M.Neon, { Attrs = k == 2 and { HwLantern = "Purple" } or nil })
		K.Part(m, "OrielMullion", V3(.16, 2.4, .12), Wc * CF(.62, 0, -.1), sp.Trim, M.Wood)
	end
	K.Part(m, "OrielMullion", V3(.16, 2.4, .12), base * CF(-2.05, .1, 1.5), sp.Trim, M.Wood)
	-- skull over the door + bone garland on the porch fascia
	local sk = at(0, DECK + 6.35, 12.15)
	K.Ball(m, "Skull", 1.05, sk, P.Bone, M.SmoothPlastic)
	K.Part(m, "SkullJaw", V3(.7, .35, .55), sk * CF(0, -.5, .18), P.BoneDark, M.SmoothPlastic)
	K.Ball(m, "SkullEye", .3, sk * CF(-.22, .05, .42), GLOW.Purple, M.Neon)
	K.Ball(m, "SkullEye", .3, sk * CF(.22, .05, .42), GLOW.Purple, M.Neon)
	for _, k in ipairs({ -1, 1 }) do
		K.Bone(m, at(k * 3, DECK + 6.65, 12.2) * ANG(0, 0, k * .12), 1.8, P.Bone)
	end
	K.Bone(m, at(-1.2, DECK + .2, 9.8) * ANG(0, .6, 0), 1.3, P.BoneDark)
	-- an empty dog bowl and a chewed bone in the yard
	K.CylY(m, "DogBowl", .45, 1.5, at(5.8, .4, 13.6), C(150, 40, 50), M.SmoothPlastic)
	K.CylY(m, "DogBowlIn", .1, 1.1, at(5.8, .6, 13.6), C(60, 20, 26), M.SmoothPlastic)
	K.Bone(m, at(6.9, .35, 14.4) * ANG(0, .9, 0), 1.2, P.Bone)
	pumpkin(m, at(-2.15, .53, 11.75) * ANG(0, -.25, 0), 1.35, { Glow = GLOW.Purple, Light = false })
end

EXTRAS[7] = function(m, at, H, U, rng, sp)
	local top = sp.WallTop
	-- flat roof with parapet, corrugated sheets, water tank on stilts, lightning rod with a tesla ball
	K.Part(m, "FlatRoof", V3(16.6, .5, 14.6), at(0, top + .25, 0), C(58, 58, 64), M.Slate, solid())
	for _, z in ipairs({ -7.05, 7.05 }) do
		K.Part(m, "Parapet", V3(16.8, 1.2, .5), at(0, top + 1, z), sp.Trim, M.Concrete)
	end
	for _, x in ipairs({ -8.15, 8.15 }) do
		K.Part(m, "Parapet", V3(.5, 1.2, 14.6), at(x, top + 1, 0), sp.Trim, M.Concrete)
	end
	for k = 0, 3 do
		K.Part(m, "Corrugated", V3(3.6, .14, 12.8), at(-5.6 + k * 3.7, top + .58, 0) * ANG(0, 0, (k % 2 == 0) and .03 or -.03),
			C(110, 112, 118):Lerp(P.Rust, k * .18), M.CorrodedMetal)
	end
	local tk = at(-3.6, top + .5, -2.4)
	for _, o in ipairs({ { -1.4, -1.4 }, { 1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, 1.4 } }) do
		K.Part(m, "TankLeg", V3(.3, 3.4, .3), tk * CF(o[1], 1.7, o[2]), P.Iron, M.CorrodedMetal)
	end
	K.CylY(m, "WaterTank", 3, 3.8, tk * CF(0, 4.9, 0), C(96, 84, 74), M.WoodPlanks, solid())
	for _, yy in ipairs({ 3.9, 5.9 }) do
		K.CylY(m, "TankHoop", .2, 3.95, tk * CF(0, yy, 0), P.Iron, M.CorrodedMetal)
	end
	local tkTop = K.CylY(m, "TankLid", .7, 4.1, tk * CF(0, 6.7, 0), C(70, 60, 56), M.Slate)
	K.Attach(tkTop, "CrowPerch", CF(.5, 0, 1.2) * ANG(0, 0, -PI / 2))
	local rod = at(4.6, top + .5, 2.4)
	K.CylY(m, "LightningRod", 7, .25, rod * CF(0, 3.5, 0), C(170, 120, 70), M.Metal)
	for k = 1, 3 do
		K.CylY(m, "CoilRing", .16, 1.4 - k * .25, rod * CF(0, 5 + k * .55, 0), C(200, 140, 70), M.Metal)
	end
	local ball = K.Ball(m, "TeslaBall", 1.2, rod * CF(0, 7.3, 0), GLOW.Green, M.Neon, { Attrs = { HwLantern = "Green" } })
	K.Attach(ball, "CrowPerch", CF(0, .6, 0))
	-- stove pipes
	for k, o in ipairs({ { 5.8, -4.5 }, { 2.6, -5.2 } }) do
		K.CylY(m, "StovePipe", 3 + k, .8, at(o[1], top + 1.5 + (3 + k) / 2, o[2]), C(80, 80, 88), M.CorrodedMetal)
		K.CylY(m, "StoveCap", .3, 1.25, at(o[1], top + 1.5 + 3 + k + .1, o[2]), C(60, 60, 66), M.CorrodedMetal)
	end
	-- corrugated patches + hazard stripes on the facade
	K.Part(m, "WallPatch", V3(3.2, 3.8, .12), at(-5.4, 7.6, 7.08) * ANG(0, 0, .04), C(120, 122, 126):Lerp(P.Rust, .4), M.CorrodedMetal)
	K.Part(m, "WallPatch", V3(.12, 4.2, 3.6), at(8.08, 5, -2.2), C(110, 112, 116):Lerp(P.Rust, .55), M.CorrodedMetal)
	for k = 0, 4 do
		K.Part(m, "HazardStripe", V3(.9, .1, 4.6), at(-1.8 + k * .9, .54, 11.76) * ANG(0, .5, 0), k % 2 == 0 and C(240, 196, 40) or C(26, 24, 30), M.SmoothPlastic)
	end
	-- cable from the tesla rod down the wall toward the broken lab (east)
	K.Rod(m, "Cable", (rod * CF(.2, 4.6, 0)).Position, (at(8.4, top - 1.6, 4)).Position, .16, C(30, 30, 34), M.Fabric)
	K.Rod(m, "Cable", (at(8.4, top - 1.6, 4)).Position, (at(8.4, .4, 9)).Position, .16, C(30, 30, 34), M.Fabric)
	-- barrel by the steps leaking green
	local br = at(-6, 0, 13.4)
	K.CylY(m, "ToxicBarrel", 2.2, 1.6, br * CF(0, 1.1, 0) * ANG(.08, 0, .06), C(70, 120, 60), M.CorrodedMetal, solid())
	K.CylY(m, "BarrelHoop", .14, 1.66, br * CF(0, .6, 0) * ANG(.08, 0, .06), C(40, 60, 36), M.CorrodedMetal)
	K.CylY(m, "BarrelHoop", .14, 1.66, br * CF(0, 1.7, 0) * ANG(.08, 0, .06), C(40, 60, 36), M.CorrodedMetal)
	K.Ellipsoid(m, "ToxicPuddle", V3(2.6, .06, 1.8), br * CF(1.4, .05, .8), GLOW.Green, M.Neon)
	pumpkin(m, at(-2.15, .53, 11.75) * ANG(0, -.3, 0), 1.35, { Glow = GLOW.Green })
end

------------------------------------------------------------------------------------------------------------------
-- the seven house specs (colours from the AttractionRefresh palette, darkened for the night)
------------------------------------------------------------------------------------------------------------------
local SPECS = {
	{ -- 1 · the pumpkin keeper's cottage (first house after the gate)
		Glow = "Orange", WallTop = 9.8, RoofType = "Front", Rise = 7.6, Rows = 5,
		Wall = C(118, 88, 112), Trim = C(62, 44, 62), Roof = C(88, 56, 112), Shutter = C(74, 104, 84),
		Chimney = { -8.9, -2.2, 6.0, 19.6, W = 2, Wide = 4.2, Mat = M.Cobblestone, Color = C(96, 90, 104) },
		Windows = {
			{ "F", -5, 4.4, 2.4, 3.2, Glow = "Orange", Shutters = "both", Flicker = true, Light = true, Silhouette = "dog" },
			{ "F", 5.2, 4.4, 2.4, 3.2, Glow = "Orange", Shutters = "broken", Web = 1.1 },
			{ "L", 3.4, 4.6, 2.2, 3 },
			{ "R", -2.5, 4.6, 2.2, 3, Glow = "Orange", Dim = true },
			{ "R", 3.2, 4.6, 2.2, 3, Glow = "Orange" },
			{ "B", -4, 4.6, 2.2, 3, Boards = 2 },
		},
		Fence = "Picket",
	},
	{ -- 2 · the leaning house (jettied upper storey that leans east)
		Glow = "Green", WallTop = 13.6, RoofType = "Side", Rise = 6.2, Belt = nil,
		Upper = { Y = 7.9, Out = .7, Lean = -.045 },
		Wall = C(80, 104, 108), Wall2 = C(92, 112, 104), Trim = C(42, 54, 58), Roof = C(58, 66, 84), Shutter = C(120, 60, 60),
		Chimney = { 5.6, -3.4, 12, 22.4, W = 1.7, Tilt = -.1 },
		PorchW = 9,
		Windows = {
			{ "F", -5, 4.4, 2.3, 3, Glow = "Green", Flicker = true },
			{ "F", 5, 4.4, 2.3, 3, Boards = 3 },
			{ "F", -4.6, 10.8, 2.2, 2.6, Glow = "Green", Dim = true, Shutters = "broken", Upper = true },
			{ "F", 4.6, 10.8, 2.2, 2.6, Shutters = "both", Upper = true, Web = 1 },
			{ "L", 2, 4.6, 2.2, 3, Glow = "Green" },
			{ "R", -1, 10.6, 2, 2.6, Glow = "Green", Upper = true },
			{ "B", 3, 4.6, 2.2, 3, Boards = 2 },
		},
	},
	{ -- 3 · the witch's tower house
		Glow = "Purple", WallTop = 11.2, RoofType = "Side", Rise = 6.2,
		Wall = C(70, 72, 112), Trim = C(34, 32, 56), Roof = C(54, 42, 82), Shutter = C(40, 40, 70),
		Chimney = { -5.2, -3.6, 12, 21.8, W = 1.6 },
		PorchW = 8.2, PorchX = -.8, Fence = "Iron",
		Windows = {
			{ "F", -5.2, 4.4, 2.4, 3.2, Glow = "Purple", Flicker = true, Silhouette = "witch", Shutters = "both" },
			{ "L", -1.5, 4.6, 2.2, 3, Glow = "Purple", Dim = true },
			{ "L", 3.5, 9.4, 1.8, 2.2 },
			{ "R", -3, 4.6, 2.2, 3, Boards = 2 },
			{ "B", 0, 4.6, 2.2, 3 },
		},
	},
	{ -- 4 · the grand manor (centre of the lane, faces the cauldron walk)
		Glow = "Orange", WallTop = 13, RoofType = "Side", Rise = 6.6, Belt = 9.6, PorchW = 15.2, Posts = { -7.2, -2.7, 2.7, 7.2 },
		Wall = C(104, 86, 96), Trim = C(48, 36, 50), Roof = C(70, 44, 74), Shutter = C(52, 40, 62), Stone = C(84, 80, 96),
		Chimney = { -6.4, -2.6, 13, 22.6, W = 1.8, Mat = M.Brick },
		Fence = "Stone", DoorColor = C(70, 30, 34),
		Windows = {
			{ "F", -5.2, 4.4, 2.4, 3.2, Glow = "Orange", Flicker = true, Light = true, Shutters = "both" },
			{ "F", 5.2, 4.4, 2.4, 3.2, Glow = "Orange", Shutters = "both" },
			{ "F", -5.6, 11.4, 2.2, 2.4, Glow = "Purple", Dim = true },
			{ "F", 5.6, 11.4, 2.2, 2.4, Glow = "Purple", Flicker = true, Web = 1 },
			{ "L", -2.5, 4.6, 2.2, 3, Glow = "Orange", Dim = true },
			{ "R", 2.5, 4.6, 2.2, 3, Glow = "Orange" },
			{ "R", -2.5, 11.2, 2, 2.4 },
			{ "B", -4, 4.6, 2.2, 3 },
		},
	},
	{ -- 5 · the boarded house (collapsed roof corner, KEEP OUT)
		Glow = "Green", WallTop = 10.6, RoofType = "Side", Rise = 6, Damaged = .18,
		Hole = function(s, r, k)
			return s == 1 and r <= 4 and k == 1
		end,
		Wall = C(112, 66, 56), Trim = C(56, 36, 32), Roof = C(66, 56, 64), Shutter = C(60, 70, 50),
		Chimney = { -5.6, -2.8, 9.6, 19.2, W = 1.6, Tilt = .08 },
		PorchW = 10.4, Sag = .55, BrokenPost = 2, BrokenRail = "R", Fence = "Broken",
		Windows = {
			{ "F", -5, 4.4, 2.4, 3.2, Glow = "Green", Boards = 3, Flicker = true },
			{ "F", 5, 4.4, 2.4, 3.2, Glow = "Green", Dim = true, Boards = 2, Shutters = "broken" },
			{ "L", 1, 4.6, 2.2, 3, Boards = 3 },
			{ "R", 0, 4.6, 2.2, 3, Glow = "Green", Dim = true, Boards = 2 },
			{ "B", 0, 4.6, 2.2, 3, Boards = 2 },
		},
	},
	{ -- 6 · the bone collector's house (oriel window, bone fence)
		Glow = "Purple", WallTop = 12.4, RoofType = "Front", Rise = 7.4, Rows = 5,
		Wall = C(132, 118, 98), Trim = C(66, 54, 48), Roof = C(80, 56, 60), Shutter = C(60, 40, 60),
		Chimney = { 5.4, -3.8, 12, 22.2, W = 1.7, Mat = M.Cobblestone, Color = C(100, 94, 104) },
		Fence = "Bone", DoorColor = C(44, 30, 50),
		Windows = {
			{ "F", -5.2, 4.4, 2.4, 3.2, Glow = "Purple", Flicker = true, Light = true, Shutters = "both", Silhouette = "dog", SilX = -.3 },
			{ "F", 5.2, 4.4, 2.4, 3.2, Glow = "Purple", Dim = true, Boards = 1 },
			{ "L", -2.6, 4.6, 2.2, 3, Glow = "Purple" },
			{ "L", 3, 9.6, 2, 2.4 },
			{ "R", 1.6, 4.6, 2.2, 3, Glow = "Purple", Dim = true },
			{ "B", 2, 4.6, 2.2, 3, Boards = 2 },
		},
	},
	{ -- 7 · the mad vet's house (flat roof, tesla rod, water tank; next to the broken lab)
		Glow = "Green", WallTop = 11.4, RoofType = "Flat",
		Wall = C(76, 90, 78), Trim = C(44, 50, 48), Roof = C(70, 70, 78), Shutter = C(50, 60, 54),
		Deck = C(90, 92, 98), DeckMat = M.DiamondPlate, Post = C(110, 112, 118), Brackets = false, Fence = "Chain",
		DoorColor = C(60, 70, 64), StepColor = C(90, 92, 98),
		Windows = {
			{ "F", -5, 4.4, 2.4, 3.2, Glow = "Green", Flicker = true, Boards = 2 },
			{ "F", 5.2, 4.4, 2.4, 3.2, Glow = "Green" },
			{ "F", 0, 10, 3.6, 1.6, Glow = "Green", Dim = true, Mullion = false },
			{ "L", 0, 4.6, 2.2, 3, Glow = "Green", Dim = true },
			{ "R", -2, 4.6, 2.4, 3, Glow = "Green", Flicker = true },
			{ "B", -3, 4.6, 2.2, 3, Boards = 2 },
		},
	},
}

------------------------------------------------------------------------------------------------------------------
-- Hollow Lane
------------------------------------------------------------------------------------------------------------------
local function buildLane(root, L, rng)
	local lane = K.Model(root, "Lane")
	local ln = L.Lane
	local y0, y1 = L.FloorY, L.LaneY
	local th = y1 - y0
	local zc = (ln.Z0 + ln.Z1) / 2
	-- base paving in segments (slight colour drift)
	local segs = 6
	local sl = (ln.X1 - ln.X0) / segs
	for k = 1, segs do
		local col = C(74, 68, 86):Lerp(C(60, 56, 72), rng:NextNumber(0, 1))
		K.Part(lane, "LanePaving", V3(sl + .02, th, ln.Z1 - ln.Z0 - 3.2), CF(ln.X0 + (k - .5) * sl, y0 + th / 2, zc), col, M.Cobblestone, solid())
	end
	-- gutters (slightly lower, wet) + curbs
	for _, gz in ipairs({ ln.Z0 + 1.2, ln.Z1 - 1.2 }) do
		K.Part(lane, "Gutter", V3(ln.X1 - ln.X0, th - .06, .7), CF((ln.X0 + ln.X1) / 2, y0 + (th - .06) / 2, gz), C(40, 38, 50), M.Slate, solid())
		K.Part(lane, "GutterWater", V3(ln.X1 - ln.X0 - 1, .03, .5), CF((ln.X0 + ln.X1) / 2, y1 - .045, gz), C(40, 46, 80), M.Glass,
			{ Transparency = .35, Reflectance = .25 })
	end
	local x = ln.X0
	while x < ln.X1 - .5 do
		local len = math.min(rng:NextNumber(11, 17), ln.X1 - x)
		for _, cz in ipairs({ ln.Z0 + .4, ln.Z1 - .4 }) do
			K.Part(lane, "Curb", V3(len - .12, th + .16, .8), CF(x + len / 2, y0 + (th + .16) / 2, cz) * ANG(0, rng:NextNumber(-.006, .006), 0),
				C(96, 92, 106):Lerp(C(70, 68, 80), rng:NextNumber(0, 1)), M.Slate, solid())
		end
		x += len
	end
	-- cracked slabs and worn patches
	for k = 1, 16 do
		local px = rng:NextNumber(ln.X0 + 2, ln.X1 - 2)
		local pz = rng:NextNumber(ln.Z0 + 2.4, ln.Z1 - 2.4)
		local w, d = rng:NextNumber(2.2, 4.4), rng:NextNumber(1.8, 3.2)
		local col = (k % 3 == 0) and C(88, 84, 100) or (k % 3 == 1 and C(56, 52, 66) or C(70, 60, 74))
		K.Part(lane, "LaneSlab", V3(w, .06, d), CF(px, y1 + .02, pz) * ANG(rng:NextNumber(-.01, .01), rng:NextNumber(-.15, .15), rng:NextNumber(-.01, .01)),
			col:Lerp(P.Ink, rng:NextNumber(0, .25)), (k % 2 == 0) and M.Slate or M.Cobblestone)
		if k % 5 == 0 then
			local a = V3(px - w * .4, y1 + .06, pz + rng:NextNumber(-d * .3, d * .3))
			local mid = V3(px + rng:NextNumber(-.3, .3), y1 + .06, pz + rng:NextNumber(-d * .4, d * .4))
			K.Bar(lane, "Crack", a, mid, .1, .02, C(22, 18, 28), M.SmoothPlastic)
			K.Bar(lane, "Crack", mid, V3(px + w * .4, y1 + .06, pz + rng:NextNumber(-d * .3, d * .3)), .08, .02, C(22, 18, 28), M.SmoothPlastic)
		end
	end
	-- puddles reflecting the lanterns
	for k = 1, 6 do
		local px = ln.X0 + 10 + (k - 1) * 28 + rng:NextNumber(-6, 6)
		K.Ellipsoid(lane, "Puddle", V3(rng:NextNumber(3, 5), .04, rng:NextNumber(1.8, 2.8)), CF(px, y1 + .03, rng:NextNumber(ln.Z0 + 3, ln.Z1 - 3)) * ANG(0, rng:NextNumber(0, PI), 0),
			C(46, 40, 86), M.Glass, { Transparency = .2, Reflectance = .35 })
	end
	-- drain grates in the gutter
	for k = 1, 4 do
		local gx = ln.X0 + 20 + (k - 1) * 44
		local gz = (k % 2 == 0) and ln.Z0 + 1.15 or ln.Z1 - 1.15
		K.Part(lane, "DrainGrate", V3(2.2, .08, .95), CF(gx, y1 + .01, gz), C(44, 44, 52), M.DiamondPlate)
	end
	-- fallen leaves, mostly along the curbs
	local leafCols = { C(196, 92, 30), C(160, 54, 34), C(120, 70, 40), C(214, 150, 50), C(90, 50, 36) }
	for k = 1, 18 do
		local nearCurb = k % 3 ~= 0
		local pz = nearCurb and ((k % 2 == 0) and rng:NextNumber(ln.Z0 + .2, ln.Z0 + 2.5) or rng:NextNumber(ln.Z1 - 2.5, ln.Z1 - .2))
			or rng:NextNumber(ln.Z0 + 3, ln.Z1 - 3)
		local px = rng:NextNumber(ln.X0 + 1, ln.X1 - 1)
		local yy = (pz < ln.Z0 + .8 or pz > ln.Z1 - .8) and y1 + .2 or y1 + .05
		K.Part(lane, "Leaf", V3(rng:NextNumber(.45, .7), .04, rng:NextNumber(.3, .45)), CF(px, yy, pz) * ANG(rng:NextNumber(-.2, .2), rng:NextNumber(0, PI * 2), rng:NextNumber(-.2, .2)),
			leafCols[rng:NextInteger(1, #leafCols)], M.SmoothPlastic)
	end
	-- the HOLLOW LANE street sign by house 1 (faces the gate / -X, second board faces the lane). x 48: the TRICK OR TREAT
	-- board stays clear of the left gate leaf's 100° swing (reach ~44.6); z on the strip between house 1's picket fence
	-- (z 566.45..566.95) and the curb (z 568); its pumpkin sits just behind the fence
	local sx, sz = ln.X0 + 10, ln.Z0 - .5
	local post = K.CylY(lane, "SignPost", 8.2, .45, CF(sx, y0 + 4.1, sz), P.Iron, M.CorrodedMetal, solid())
	K.CylY(lane, "SignPostFoot", .6, .9, CF(sx, y0 + .3, sz), P.Iron, M.CorrodedMetal)
	local b1 = K.Part(lane, "StreetSign", V3(5.2, 1.1, .16), CF(sx, y0 + 7.1, sz) * ANG(0, PI / 2, 0), C(36, 30, 52), M.SmoothPlastic)
	K.Part(lane, "StreetSignTrim", V3(5.5, 1.35, .1), b1.CFrame * CF(0, 0, .1), C(200, 160, 70), M.Metal)
	K.Sign(b1, N.Front, "HOLLOW LANE", P.Cream, { PixelsPerStud = 24, H = .78, StrokeColor = C(60, 20, 90) })
	local b2 = K.Part(lane, "StreetSign", V3(5.2, 1.1, .16), CF(sx, y0 + 5.7, sz) * ANG(0, PI, 0), C(70, 30, 20), M.SmoothPlastic)
	K.Part(lane, "StreetSignTrim", V3(5.5, 1.35, .1), b2.CFrame * CF(0, 0, .1), C(200, 160, 70), M.Metal)
	K.Sign(b2, N.Front, "TRICK OR TREAT", P.Pumpkin, { PixelsPerStud = 24, H = .78 })
	local cap = K.Ball(lane, "SignFinial", .7, CF(sx, y0 + 8.4, sz), P.Iron, M.CorrodedMetal)
	K.Attach(cap, "CrowPerch", CF(0, .35, 0))
	K.Attach(post, "BatRoost", CF(4, 0, 0))
	pumpkin(lane, CF(sx + .9, y0, sz - 2.2) * ANG(0, 2.4, 0), 1.6, { Light = false }) -- face toward the lane + gate
	-- fog along the lane (ground level)
	for k, fx in ipairs({ 44, 92, 140, 188 }) do
		K.Marker(lane, "FogPoint", V3(fx, y1 + .3, ln.Z0 + 2 + (k % 2) * 10))
	end
	return lane
end

return {
	Build = function(ctx)
		local L = ctx.Layout
		local rng = Rng(2026)
		buildLane(ctx.Root, L, rng)
		local houses = K.Model(ctx.Root, "Houses")
		for i, lay in ipairs(L.Houses) do
			local sp = SPECS[i]
			sp.Extras = EXTRAS[i]
			buildHouse(houses, i, lay, sp, Rng(700 + i * 31))
		end
	end,
}
