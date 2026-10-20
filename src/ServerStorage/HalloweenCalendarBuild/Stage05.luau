-- HALLOWEEN CALENDAR · STAGE 5 · D-3 · THE SWOLLEN MOON (ServerStorage.HalloweenCalendarBuild.Stage05, build-time only).
-- Lantern trees (a lit lantern hangs from a claw branch), ghost markers in the open fields (CalGhostPath: the client's
-- distant ghosts drift there at night), more graves and pumpkins, more than half of the island dead. The bigger moon, the
-- ground fog and the orange / violet lamps are client-side (CalendarFX).
return {
	Stage = 5,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local lanterns = CK.Trees(ctx, 2, { Height = { 16, 19 }, Thick = .14, Face = true, Lantern = Color3.fromRGB(255, 150, 54),
			Name = "LanternTrees", Branches = 4, Boxes = { "WestLawn", "EastLawn" } })
		local ghosts = CK.Props(ctx, 10, 6, { Front = 1.2, Name = "GhostMarkers", Y1 = 8, Margin = 1 }, function(m, s)
			CK.Marker(m, "CalGhostPath", V3(s.X, s.Top + 3, s.Z), { Radius = rng:NextNumber(10, 22), Height = rng:NextNumber(2.5, 5) })
		end)
		local graves = CK.Props(ctx, 3, 4.2, { Front = .85, Name = "SproutedGraves", Y1 = 5 }, function(m, s)
			CK.GraveCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, ctx.Site:NearestWalk(s.X, s.Z, 50))
		end)
		local lit = 0
		local pumpkins = CK.Props(ctx, 3, 3.4, { Front = .85, Name = "Pumpkins", Y1 = 4,
			Boxes = { "ParkEast", "ShelterEast", "CourtWest" } }, function(m, s)
			lit += 1
			CK.PumpkinCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, { Light = lit <= 2, Face = ctx.Site:NearestWalk(s.X, s.Z, 50) })
		end)
		local patches = CK.Patches(ctx, 30, .84, { Leaves = .3 })
		ctx.Note(string.format("lantern trees %d, ghost markers %d, graves %d, pumpkins %d, patches %d", #lanterns, ghosts, graves, pumpkins, patches))
	end,
}
