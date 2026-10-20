-- HALLOWEEN CALENDAR · STAGE 7 · D-1 · ALMOST LOST (ServerStorage.HalloweenCalendarBuild.Stage07, build-time only).
-- Almost fully infected: a second crooked tree with green eyes on every sky island, more crooked trees (two with faces),
-- candles everywhere, spectral rune circles glowing in the grass, bat-roost trees, the last free grass dying. The heavy
-- fog, spectral wisps and the moon transformation are client-side (CalendarFX).
return {
	Stage = 7,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local sky = CK.SkyIslandTrees(ctx, 2, { 26, 34 })
		local faces = CK.Trees(ctx, 2, { Height = { 15, 19 }, Thick = .15, Face = true, Name = "FaceTrees", EyeColor = CK.GLOW.Violet,
			Boxes = { "ParkEast", "DogNorthW" } })
		local trees = CK.Trees(ctx, 2, { Height = { 12, 16 }, Thick = .11, Name = "CrookedTrees", Boxes = { "CourtWest", "ShelterEast" } })
		local roosts = CK.Trees(ctx, 2, { Height = { 15, 18 }, Thick = .1, Roost = true, Name = "BatRoostTrees", Branches = 4,
			Boxes = { "HubEast", "WestCliff" } })
		local n = 0
		local candles = CK.Props(ctx, 6, 1.6, { Name = "CandleStumps", Y1 = 3,
			Boxes = { "SouthField", "CourtSouth", "DogNorthE", "WestCliff", "HubEast", "WestLawnS" } }, function(m, s)
			n += 1
			CK.CandleStump(m, V3(s.X, s.Top, s.Z), s.Top, rng, n <= 4)
		end)
		local runes = CK.Props(ctx, 3, 5.2, { Name = "RuneCircles", Y1 = 3, Boxes = { "WestLawn", "EastLawn", "SouthField" } }, function(m, s)
			CK.RuneCircle(m, V3(s.X, s.Top, s.Z), s.Top, rng:NextNumber(2.6, 3.4), rng, rng:NextNumber() < .5 and CK.ROT or CK.GLOW.Green)
		end)
		local patches = CK.Patches(ctx, 26, 1.1, { Leaves = .2 })
		ctx.Note(string.format("sky trees %d, face trees %d, trees %d, roosts %d, candles %d, runes %d, patches %d", sky, #faces, #trees,
			#roosts, candles, runes, patches))
	end,
}
