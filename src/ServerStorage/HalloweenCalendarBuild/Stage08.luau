-- HALLOWEEN CALENDAR · STAGE 8 · OCTOBER 31 · HALLOWEEN NIGHT (ServerStorage.HalloweenCalendarBuild.Stage08).
-- Build-time only. The full transformation set pieces. Their ground is CLAIMED before any stage scatters anything
-- (Claim runs first, see tools/edits/41_calendar.luau), each on the largest open grass the site measured:
--   THE PUMPKIN PATCH (behind DOG-O-MATIC): a giant jack-o'-lantern on a mound, the scarecrow dog, pumpkin clusters,
--     a broken picket fence;
--   THE HOLLOW OAK (the west lawn): a giant crooked tree with a glowing carved face and three hanging lanterns;
--   THE GHOST DOG SEANCE (east of the boulevard): five spectral dogs sitting round a floating ghost lantern;
--   THE WITCHES' RING (east of the Dog Shelter): a rune circle, a bubbling cauldron, candle stumps around it;
--   two "HAPPY HALLOWEEN!" signposts beside the walks (English lettering, NoTranslate; CalendarFX localizes it),
--   the last pumpkins, ghost markers and dead grass.
local OAK_H, OAK_THICK = 31, .17

return {
	Stage = 8,
	Claim = function(ctx)
		local site, rng = ctx.Site, ctx.Rng
		site:Claim("PumpkinPatch", rng, "SouthField", 12, 10)
		site:Claim("HollowOak", rng, "WestLawn", OAK_H * OAK_THICK * 1.45, OAK_H + 2, { Tree = { Spread = OAK_H * .32, Height = OAK_H + 2 } })
		site:Claim("GhostRing", rng, "HubEast", 9, 7)
		site:Claim("WitchesRing", rng, "ShelterEast", 8.5, 6)
		for _, name in ipairs({ "PumpkinPatch", "HollowOak", "GhostRing", "WitchesRing" }) do
			if not (site.Claims and site.Claims[name]) then
				ctx.Note("no ground for " .. name)
			end
		end
	end,
	Build = function(ctx)
		local CK, rng, site = ctx.CK, ctx.Rng, ctx.Site
		local K = ctx.Kit
		local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
		local C = Color3.fromRGB
		local PI, TAU = math.pi, math.pi * 2
		local claims = site.Claims or {}
		local notes = {}

		-- a front (-Z) looking at the nearest walk
		local function facing(x: number, z: number): CFrame
			local d = site:NearestWalk(x, z, 70) or V3(0, 0, -1)
			return K.Look(V3(0, 0, 0), d)
		end
		-- a spot inside a claim (grass checked, the claim is ours): ring between rMin and rMax, `r` clear of what we placed
		local function inside(claim, rMin: number, rMax: number, r: number, taken: { { number } })
			for _ = 1, 80 do
				local a, d = rng:NextNumber(0, TAU), rng:NextNumber(rMin, rMax)
				local x, z = claim.X + math.cos(a) * d, claim.Z + math.sin(a) * d
				local top = site:GrassTop(x, z)
				local ok = top ~= nil and math.abs(top - claim.Top) < .3
				for _, t in ipairs(taken) do
					if ok and (x - t[1]) ^ 2 + (z - t[2]) ^ 2 < (r + t[3]) ^ 2 then
						ok = false
					end
				end
				if ok then
					table.insert(taken, { x, z, r })
					return { X = x, Z = z, Top = top }
				end
			end
			return nil
		end

		-- 1. THE PUMPKIN PATCH ------------------------------------------------------------------------------------
		local pc = claims.PumpkinPatch
		if pc then
			local patch = ctx.Model("PumpkinPatch")
			local taken = { { pc.X, pc.Z, 5.4 } }
			local rot = facing(pc.X, pc.Z)
			CK.GiantJack(patch, CF(pc.X, pc.Top, pc.Z) * rot, 7)
			local sc = inside(pc, 6.5, 9, 1.8, taken)
			if sc then
				CK.Scarecrow(patch, CF(sc.X, sc.Top, sc.Z) * facing(sc.X, sc.Z), rng)
			end
			for k = 1, 6 do
				local s = inside(pc, 5.5, pc.R - 2.4, 2.4, taken)
				if s then
					CK.PumpkinCluster(patch, V3(s.X, s.Top, s.Z), s.Top, rng, { Light = k <= 2, Face = site:NearestWalk(s.X, s.Z, 50),
						Count = k % 3 == 0 and 2 or 3 })
				end
			end
			-- broken picket fence pieces along the rim
			for _ = 1, 3 do
				local s = inside(pc, pc.R - 2.2, pc.R - 1.6, 1.9, taken)
				if s then
					local a = math.atan2(s.Z - pc.Z, s.X - pc.X)
					local base = CF(s.X, s.Top, s.Z) * ANG(0, -a + PI / 2, 0)
					local wood = C(96, 72, 52):Lerp(C(58, 40, 32), rng:NextNumber(0, .5))
					local fence = K.Model(patch, "PicketFence")
					for k = -1, 1 do
						if not (k == 1 and rng:NextNumber() < .4) then
							local hgt = 2.4 + rng:NextNumber(-.4, .3)
							K.Part(fence, "PicketPost", V3(.35, hgt, .3), base * CF(k * 1.5, hgt / 2 - .1, 0) * ANG(0, 0, rng:NextNumber(-.12, .12)),
								wood, Enum.Material.WoodPlanks)
						end
					end
					K.Part(fence, "PicketRail", V3(3.6, .26, .16), base * CF(0, 1.6, .2) * ANG(0, 0, rng:NextNumber(-.1, .1)), wood, Enum.Material.WoodPlanks)
					K.Part(fence, "PicketRail", V3(3.2, .26, .16), base * CF(.2, .8, .2) * ANG(0, 0, rng:NextNumber(-.18, .18)), wood, Enum.Material.WoodPlanks)
				end
			end
			-- leaf litter on the patch floor
			for _ = 1, 4 do
				local s = inside(pc, 2, pc.R - 2.5, 1.2, {})
				if s then
					CK.DeadPatch(patch, V3(s.X, s.Top, s.Z), s.Top, rng:NextNumber(1.6, 2.4), rng, { Leaves = 4, Tufts = 2, Layers = 1 })
				end
			end
			table.insert(notes, string.format("pumpkin patch (%.0f, %.0f)", pc.X, pc.Z))
		end

		-- 2. THE HOLLOW OAK ---------------------------------------------------------------------------------------
		local oc = claims.HollowOak
		if oc then
			local oakModel = ctx.Model("HollowOak")
			local d = site:NearestWalk(oc.X, oc.Z, 90)
			local m, info = CK.CrookedTree(oakModel, V3(oc.X, oc.Top, oc.Z), OAK_H, rng, { Thick = OAK_THICK, Face = true, FaceDir = d,
				MouthGlow = C(255, 150, 50), EyeColor = C(255, 170, 60), Lantern = C(255, 150, 54), Lanterns = 3, Branches = 5, Name = "HollowOak",
				Roost = true })
			m:SetAttribute("SetPiece", "HollowOak")
			site.Trees = site.Trees or {}
			table.insert(site.Trees, { X = oc.X, Z = oc.Z, Top = oc.Top, R = oc.R, Model = m, Face = true })
			-- a ring of candles in the roots and two pumpkins at its feet
			local taken = { { oc.X, oc.Z, oc.R * .62 } }
			for k = 1, 2 do
				local s = inside(oc, oc.R * .7, oc.R - 1.4, 1.6, taken)
				if s then
					CK.PumpkinCluster(oakModel, V3(s.X, s.Top, s.Z), s.Top, rng, { Count = 1, Size = 2, Light = false, Face = d })
				end
				local _ = k
			end
			local _ = info
			table.insert(notes, string.format("hollow oak (%.0f, %.0f)", oc.X, oc.Z))
		end

		-- 3. THE GHOST DOG SEANCE -------------------------------------------------------------------------------------
		local gc = claims.GhostRing
		if gc then
			local ring = ctx.Model("GhostDogSeance")
			local r = 5.8
			CK.RuneCircle(ring, V3(gc.X, gc.Top, gc.Z), gc.Top, 3.4, rng, C(150, 220, 255))
			for k = 1, 5 do
				local a = k / 5 * TAU
				local at = V3(gc.X + math.cos(a) * r, gc.Top + ((k % 2 == 0) and .45 or .8), gc.Z + math.sin(a) * r)
				-- sitting round the lantern, facing it, floating a little
				CK.GhostDog(ring, K.Look(at, V3(gc.X, at.Y, gc.Z)), rng:NextNumber(.9, 1.02))
				-- a candle between each pair of dogs
				local ca = a + TAU / 10
				K.Candles(ring, CF(gc.X + math.cos(ca) * (r - .4), gc.Top, gc.Z + math.sin(ca) * (r - .4)), 2, rng, { Spread = .3, Light = false })
			end
			-- the ghost lantern they chase: a floating lantern over a little stone plinth
			K.CylY(ring, "GhostPlinth", .8, 2.2, CF(gc.X, gc.Top + .4, gc.Z), C(92, 96, 112), Enum.Material.Slate)
			CK.HangingLantern(ring, V3(gc.X, gc.Top + 5.2, gc.Z), 1.6, C(150, 220, 255), true)
			CK.Marker(ring, "CalGhostPath", V3(gc.X, gc.Top + 3.5, gc.Z), { Radius = 14, Height = 4 })
			table.insert(notes, string.format("ghost dog ring (%.0f, %.0f)", gc.X, gc.Z))
		end

		-- 4. THE WITCHES' RING -------------------------------------------------------------------------------------
		local wc = claims.WitchesRing
		if wc then
			local ring = ctx.Model("WitchesRing")
			CK.RuneCircle(ring, V3(wc.X, wc.Top, wc.Z), wc.Top, 4.2, rng, CK.GLOW.Green)
			local cfc = CF(wc.X, wc.Top, wc.Z)
			local pot = K.Model(ring, "WitchCauldron")
			for k = 1, 3 do
				local a = k / 3 * TAU
				K.Rod(pot, "CauldronLeg", (cfc * CF(math.cos(a) * 1.05, 1.2, math.sin(a) * 1.05)).Position,
					(cfc * CF(math.cos(a) * 1.45, 0, math.sin(a) * 1.45)).Position, .25, K.Palette.Iron, Enum.Material.CorrodedMetal)
			end
			K.Ellipsoid(pot, "CauldronPot", V3(3.2, 2.4, 3.2), cfc * CF(0, 1.9, 0), C(36, 34, 42), Enum.Material.CorrodedMetal)
			K.CylY(pot, "CauldronRim", .3, 2.7, cfc * CF(0, 2.95, 0), C(52, 50, 60), Enum.Material.CorrodedMetal)
			local brew = K.CylY(pot, "CauldronBrew", .12, 2.3, cfc * CF(0, 3.0, 0), C(120, 255, 90), Enum.Material.Neon)
			K.Light(brew, C(120, 255, 90), 16, 1)
			for _ = 1, 3 do
				K.Ball(pot, "BrewBubble", rng:NextNumber(.3, .5), cfc * CF(rng:NextNumber(-.6, .6), 3.12, rng:NextNumber(-.6, .6)), C(170, 255, 140),
					Enum.Material.Neon)
			end
			K.Rod(pot, "CauldronLadle", (cfc * CF(.5, 2.7, .2)).Position, (cfc * CF(1.2, 4.4, .5)).Position, .14, C(96, 72, 52), Enum.Material.Wood)
			local taken = { { wc.X, wc.Z, 5.2 } }
			for k = 1, 6 do
				local a = k / 6 * TAU + .3
				local x, z = wc.X + math.cos(a) * 6.3, wc.Z + math.sin(a) * 6.3
				local top = site:GrassTop(x, z)
				if top and math.abs(top - wc.Top) < .3 then
					table.insert(taken, { x, z, 1.1 })
					CK.CandleStump(ring, V3(x, top, z), top, rng, k <= 2)
				end
			end
			table.insert(notes, string.format("witches' ring (%.0f, %.0f)", wc.X, wc.Z))
		end

		-- 5. HAPPY HALLOWEEN signposts beside the walks ------------------------------------------------------------
		local signs = 0
		for _, region in ipairs({ "ParkEast", "HubEast" }) do
			local s = site:Scatter(rng, 1, 2.6, { Box = CK.Regions[region], Y1 = 7, Margin = 1.8, Tries = 900, Reserve = { Y0 = 0, Y1 = 7 } })[1]
			if s then
				local d = site:NearestWalk(s.X, s.Z, 40) or V3(0, 0, -1)
				local at = V3(s.X, s.Top, s.Z)
				-- the board hangs on the post's +X side; turn the post so the board's front faces the walk
				CK.Signpost(ctx.Model("HalloweenSign"), K.Look(at, at + d) * CF(-1.9, 0, 0), "HAPPY HALLOWEEN!", rng)
				signs += 1
			end
		end
		table.insert(notes, "signs " .. signs)

		-- 6. the last pumpkins, ghosts and dead grass ------------------------------------------------------------------
		local lit = 0
		local pumpkins = CK.Props(ctx, 5, 3.2, { Name = "Pumpkins", Y1 = 4,
			Boxes = { "DogNorthE", "WestCliff", "CourtSouth", "EastLawn", "DogNorthW" } }, function(m, s)
			lit += 1
			CK.PumpkinCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, { Light = lit <= 2, Face = site:NearestWalk(s.X, s.Z, 50) })
		end)
		local ghosts = CK.Props(ctx, 4, 5, { Front = 1.3, Name = "GhostMarkers", Y1 = 8, Margin = 1 }, function(m, s)
			CK.Marker(m, "CalGhostPath", V3(s.X, s.Top + 3, s.Z), { Radius = rng:NextNumber(10, 20), Height = rng:NextNumber(2.5, 5) })
		end)
		local patches = CK.Patches(ctx, 20, 1.3, { Leaves = .5 })
		ctx.Note(string.format("%s; pumpkins %d, ghost markers %d, patches %d", table.concat(notes, ", "), pumpkins, ghosts, patches))
	end,
}
