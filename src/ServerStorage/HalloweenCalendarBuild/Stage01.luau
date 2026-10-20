-- HALLOWEEN CALENDAR · STAGE 1 · D-7 · THE FIRST ROT (ServerStorage.HalloweenCalendarBuild.Stage01, build-time only).
-- The rot leaks out of THE DEAD YARD: the first dead-grass patches with fallen leaves around its fences, a few young
-- crooked trees (one on the walk north of the spawn plaza so everybody notices), thorn bushes and violet rot mushrooms.
-- Run by tools/edits/41_calendar.luau into ServerStorage.HalloweenCalendar.Stage01 (see CalendarKit for the ctx).
return {
	Stage = 1,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3, CF = Vector3.new, CFrame.new
		local patches = CK.Patches(ctx, 34, .3, { Leaves = .6 })
		local trees = CK.Trees(ctx, 4, { Height = { 9, 12.5 }, Thick = .11, Lite = true, Branches = 3, Name = "YoungCrookedTrees",
			Boxes = { "HubEast", "SouthField", "CourtSouth", "SouthField" } })
		local thorns = CK.Props(ctx, 4, 1.8, { Front = .38, Name = "ThornBushes", Y1 = 3 }, function(m, s)
			CK.Thorns(m, V3(s.X, s.Top, s.Z), s.Top, rng)
		end)
		local shrooms = CK.Props(ctx, 3, 1.2, { Front = .3, Name = "RotMushrooms", Y1 = 2 }, function(m, s)
			CK.K.Mushrooms(m, CF(s.X, s.Top, s.Z), 5, rng, CK.ROT)
		end)
		ctx.Note(string.format("patches %d, trees %d, thorns %d, mushrooms %d", patches, #trees, thorns, shrooms))
	end,
}
