-- HALLOWEEN CALENDAR · STAGE 4 · D-4 · THE TREES ARE WATCHING (ServerStorage.HalloweenCalendarBuild.Stage04).
-- Build-time only. Big face trees where players walk (their CalEyes open and blink client-side from today), a crooked
-- silhouette tree with glowing eyes on every sky island (23_DistrictPolish.Horizon_Islands), more rot. The blinking
-- museum / shelter windows are client-side (CalendarFX).
return {
	Stage = 4,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local faces = CK.Trees(ctx, 4, { Height = { 16, 21 }, Thick = .16, Face = true, Name = "WatchingTrees", Branches = 4,
			Boxes = { "HubEast", "ShelterEast", "CourtWest", "DogNorthE" } })
		local sky = CK.SkyIslandTrees(ctx, 1, { 32, 44 })
		local patches = CK.Patches(ctx, 30, .72, { Leaves = .3 })
		local thorns = CK.Props(ctx, 3, 1.8, { Front = .75, Name = "ThornBushes", Y1 = 3 }, function(m, s)
			CK.Thorns(m, V3(s.X, s.Top, s.Z), s.Top, rng)
		end)
		ctx.Note(string.format("face trees %d, sky island trees %d, patches %d, thorns %d", #faces, sky, patches, thorns))
	end,
}
