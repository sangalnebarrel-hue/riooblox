-- HALLOWEEN CALENDAR · STAGE 2 · D-6 · CROOKED SPROUTS (ServerStorage.HalloweenCalendarBuild.Stage02, build-time only).
-- The first crooked trees with faces (eyes still shut: HalloweenClient.CalendarFX opens them from D-4), more crooked
-- trees, the first pumpkins (three of them lit), thorns and a wider ring of dead grass.
return {
	Stage = 2,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local patches = CK.Patches(ctx, 34, .45, { Leaves = .45 })
		local faces = CK.Trees(ctx, 3, { Height = { 15, 18 }, Thick = .16, Face = true, Name = "FaceTrees",
			Boxes = { "HubEast", "ParkEast", "WestLawn" } })
		local trees = CK.Trees(ctx, 3, { Height = { 11, 15 }, Thick = .11, Name = "CrookedTrees",
			Boxes = { "WestCliff", "ShelterEast", "CourtWest" } })
		local lit = 0
		local pumpkins = CK.Props(ctx, 5, 3.4, { Front = .55, Name = "Pumpkins", Y1 = 4,
			Boxes = { "HubEast", "SouthField", "WestLawnS", "EastLawn", "WestLawn" } }, function(m, s)
			lit += 1
			local face = ctx.Site:NearestWalk(s.X, s.Z, 50)
			CK.PumpkinCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, { Light = lit <= 3, Face = face })
		end)
		local thorns = CK.Props(ctx, 3, 1.8, { Front = .5, Name = "ThornBushes", Y1 = 3 }, function(m, s)
			CK.Thorns(m, V3(s.X, s.Top, s.Z), s.Top, rng)
		end)
		ctx.Note(string.format("patches %d, face trees %d, trees %d, pumpkins %d, thorns %d", patches, #faces, #trees, pumpkins, thorns))
	end,
}
