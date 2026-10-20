-- HALLOWEEN CALENDAR · STAGE 3 · D-5 · THE FOG ROLLS IN (ServerStorage.HalloweenCalendarBuild.Stage03, build-time only).
-- Candles burn on cut stumps beside the walks, bat-roost trees (CalBatRoost: the client's rare bats circle them),
-- small dog graves sprouting crooked, and the dead grass reaches the middle of the island. The fog and the strange night
-- sounds are client-side (CalendarFX).
return {
	Stage = 3,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local patches = CK.Patches(ctx, 32, .6, { Leaves = .35 })
		local n = 0
		local candles = CK.Props(ctx, 7, 1.6, { Name = "CandleStumps", Y1 = 3,
			Boxes = { "HubEast", "ParkEast", "WestLawn", "WestLawnS", "EastLawn", "CourtWest", "ShelterEast" } }, function(m, s)
			n += 1
			CK.CandleStump(m, V3(s.X, s.Top, s.Z), s.Top, rng, n <= 5)
		end)
		local roosts = CK.Trees(ctx, 3, { Height = { 14, 18 }, Thick = .1, Roost = true, Name = "BatRoostTrees", Branches = 4,
			Boxes = { "EastLawn", "WestLawnS", "SouthField" } })
		local graves = CK.Props(ctx, 3, 4.2, { Front = .6, Name = "SproutedGraves", Y1 = 5 }, function(m, s)
			CK.GraveCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, ctx.Site:NearestWalk(s.X, s.Z, 50))
		end)
		ctx.Note(string.format("patches %d, candle stumps %d, roost trees %d, graves %d", patches, candles, #roosts, graves))
	end,
}
