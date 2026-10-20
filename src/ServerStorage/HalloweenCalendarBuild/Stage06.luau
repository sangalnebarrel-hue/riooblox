-- HALLOWEEN CALENDAR · STAGE 6 · D-2 · CREEPING ROOTS (ServerStorage.HalloweenCalendarBuild.Stage06, build-time only).
-- Roots crawl out of the earlier calendar trees toward the nearest walk (stopping short of it), big face trees whose
-- branches sway (CalSway, client-side from today), more pumpkins, most of the island dead. Whispers are client-side.
return {
	Stage = 6,
	Build = function(ctx)
		local CK, rng = ctx.CK, ctx.Rng
		local V3 = Vector3.new
		local site = ctx.Site
		-- roots out of the trees planted so far (the largest first), then a few loose ones in the fields
		local roots = ctx.Model("CreepingRoots")
		local made = 0
		local trees = table.clone(site.Trees or {})
		table.sort(trees, function(a, b)
			return a.R > b.R
		end)
		for _, t in ipairs(trees) do
			if made >= 10 then
				break
			end
			local dir = site:NearestWalk(t.X, t.Z, 40)
			if dir then
				local start = V3(t.X, t.Top, t.Z) + dir * (t.R + .8)
				if CK.Roots(roots, site, start, t.Top, rng, rng:NextInteger(2, 3), dir) then
					made += 1
				end
			end
		end
		local loose = CK.Props(ctx, 4, 2, { Front = .95, Name = "RootKnots", Y1 = 2, Margin = 2 }, function(m, s)
			local dir = site:NearestWalk(s.X, s.Z, 40)
			CK.Roots(m, site, V3(s.X, s.Top, s.Z), s.Top, rng, 3, dir)
			CK.Thorns(m, V3(s.X, s.Top, s.Z), s.Top, rng, 1.4)
		end)
		local big = CK.Trees(ctx, 3, { Height = { 20, 24 }, Thick = .16, Face = true, Name = "AncientFaceTrees", Branches = 5,
			EyeColor = CK.GLOW.Green, Boxes = { "WestCliff", "WestLawnS", "CourtSouth" } })
		local lit = 0
		local pumpkins = CK.Props(ctx, 6, 3.4, { Front = 1, Name = "Pumpkins", Y1 = 4,
			Boxes = { "HubEast", "WestLawn", "EastLawn", "SouthField", "DogNorthW", "ParkEast" } }, function(m, s)
			lit += 1
			CK.PumpkinCluster(m, V3(s.X, s.Top, s.Z), s.Top, rng, { Light = lit <= 2, Face = site:NearestWalk(s.X, s.Z, 50) })
		end)
		local patches = CK.Patches(ctx, 26, .95, { Leaves = .25 })
		ctx.Note(string.format("root systems %d (+%d loose), ancient trees %d, pumpkins %d, patches %d", made, loose, #big, pumpkins, patches))
	end,
}
