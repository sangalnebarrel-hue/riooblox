-- THE UNDERYARD · ambient FX markers (ServerStorage.UnderyardBuild.FXMarkers, WP-G, Order 90). Build-time only:
-- tools/edits/40_underyard.luau runs it through tools/sim.luau; saved as 40_Underyard.FXMarkers. No visuals: invisible
-- holder parts (1 x 1 x 1, no collide / query / touch) carrying Attachments that the client (UnderyardFX, WP-H2)
-- turns into quality-scaled ambience. Names and attributes (all positions are the attachments' WorldPosition):
--   * MothSwarm_n   - moth clouds round lamps and flower planters of Bell Square and the roads.
--                     Radius (studs), Count (suggested moths at High quality).
--   * FogPoint_n    - low fog banks: plaza rim, bridge ends, the abyss under the bridges and chasms (Abyss = true
--                     marks the deep ones at y ~ -36), Radius, Density (0..1).
--   * WispPath_n    - ordered loops for wandering wisps: Path ("Ring" round the ring road, "Approach" down the arena
--                     bridge, "Square" round the tower), Index (order in its path), Loop (bool: wraps around).
--   * GhostResident_n - spots where a ghost resident idles (bench sitters, mourners at graves, a ghost at the toll box,
--                     a tailor's customer): Pose ("Sit" | "Mourn" | "Wander" | "Wait"), Facing (unit Vector3).
-- Every marker keeps clear of the gameplay anchors (UKit.Space) except where it is meant to frame a set piece.
local U = require(script.Parent.UKit)
local K = U.K
local V3, CF = Vector3.new, CFrame.new
local PI = math.pi

local FXMarkers = { Order = 90 }

function FXMarkers.Build(ctx)
	local L = ctx.Layout
	local c = L.Centre
	local SQ = L.Square
	local root = ctx.Model("FXMarkers")
	root:SetAttribute("SelfManagedFX", true)
	local function holder(name: string, pos: Vector3): BasePart
		return K.Part(root, name, V3(1, 1, 1), CF(pos), U.P.Violet, Enum.Material.SmoothPlastic, { Transparency = 1 })
	end
	local counts = {}
	local function marker(h: BasePart, kind: string, pos: Vector3, attrs: { [string]: any }): Attachment
		counts[kind] = (counts[kind] or 0) + 1
		return U.Y.AttachAt(h, kind .. "_" .. counts[kind], pos, attrs)
	end

	-- moths: round the plaza lamps (r 52) and planters, the arch, the shrine candles, ring lamps
	local moths = holder("MothMarkers", V3(c.X, 4, c.Z))
	for k = 0, 7 do
		local a = (k + .5) / 8 * PI * 2
		marker(moths, "MothSwarm", U.Polar(c, 52, a, 9.5), { Radius = 3.5, Count = 10 })
	end
	marker(moths, "MothSwarm", V3(L.ArrivalArch.X, 12, L.ArrivalArch.Z - 2), { Radius = 5, Count = 14 })
	marker(moths, "MothSwarm", (SQ.CoffinShrine * CF(0, 5.5, 0)).Position, { Radius = 4, Count = 12 })
	marker(moths, "MothSwarm", (SQ.Tailor * CF(0, 7, 6)).Position, { Radius = 3, Count = 8 })
	for k = 0, 3 do
		local a = (k + .5) / 4 * PI * 2 + PI / 16
		marker(moths, "MothSwarm", U.Polar(c, 85.6, a, 11.5), { Radius = 3, Count = 8 })
	end

	-- fog: plaza rim, bridge ends, abyss pools (deep, under the bridges and in the chasms), the approach curl
	local fog = holder("FogMarkers", V3(c.X, 1, c.Z))
	for k = 0, 11 do
		local a = (k + .25) / 12 * PI * 2
		marker(fog, "FogPoint", U.Polar(c, 90, a, .8), { Radius = 12, Density = .55 })
	end
	for name, g in pairs(L.Gates) do
		local u = V3(g.Position.X - c.X, 0, g.Position.Z - c.Z).Unit
		marker(fog, "FogPoint", g.Position + u * 6 + V3(0, .8, 0), { Radius = 9, Density = .7, Gate = name })
		marker(fog, "FogPoint", g.Position + u * 6 + V3(0, -36, 0), { Radius = 18, Density = .9, Abyss = true })
	end
	for _, p in ipairs({ V3(0, -36, 2240), V3(-150, -36, 2400), V3(150, -36, 2400), V3(-30, -36, 2530), V3(40, -36, 2530), V3(0, -36, 2700),
		V3(-75, -36, 2290), V3(75, -36, 2290), V3(-72, -36, 2600), V3(72, -36, 2620) }) do
		marker(fog, "FogPoint", p, { Radius = 26, Density = .95, Abyss = true })
	end
	marker(fog, "FogPoint", V3(SQ.PracticeRing.Centre.X, .6, SQ.PracticeRing.Centre.Z), { Radius = 8, Density = .4 })

	-- wisp paths: round the ring road (24, a loop), down the arena approach (from the gate to the arena), round the tower
	local wisps = holder("WispMarkers", V3(c.X, 3, c.Z))
	local rMid = (SQ.RingRoad.Inner + SQ.RingRoad.Outer) / 2
	for k = 1, 24 do
		local a = (k - 1) / 24 * PI * 2
		marker(wisps, "WispPath", U.Polar(c, rMid + math.sin(k * 1.7) * 3, a, 3 + (k % 3) * .8), { Path = "Ring", Index = k, Loop = true })
	end
	local roads = script.Parent:FindFirstChild("Roads")
	local ok, R = pcall(function()
		return roads and require(roads) or nil
	end)
	if ok and R and R.ApproachPath then
		local samples = U.Sample(R.ApproachPath(L), 12, 2)
		for k, smp in ipairs(samples) do
			marker(wisps, "WispPath", smp.Pos + V3(0, 7, 0), { Path = "Approach", Index = k, Loop = false })
		end
	end
	for k = 1, 10 do
		local a = (k - 1) / 10 * PI * 2
		marker(wisps, "WispPath", U.Polar(c, 27, a, 5 + (k % 2) * 2), { Path = "Square", Index = k, Loop = true })
	end

	-- ghost residents: benches, graves, the toll box queue, the tailor's customer, the shrine mourner, the arch
	local ghosts = holder("GhostMarkers", V3(c.X, 2, c.Z))
	local space = U.Space(L)
	local placed = 0
	for _, d in ipairs(ctx.Root:GetDescendants()) do
		if d:IsA("Model") and (d.Name == "Bench" or d.Name == "Tombstone") and placed < 9 then
			-- (the seat / the grave base marks where the prop stands; Model pivots are not used offline)
			local key = d:FindFirstChild(d.Name == "Bench" and "BenchSeat" or "GraveBase") or d:FindFirstChildWhichIsA("BasePart")
			local pos = key and (key :: BasePart).CFrame.Position or V3(c.X, 0, c.Z)
			local flat = V3(pos.X, 0, pos.Z)
			if (flat - V3(c.X, 0, c.Z)).Magnitude < 64 then
				local toward = V3(c.X - pos.X, 0, c.Z - pos.Z).Unit
				local spot = flat + toward * (d.Name == "Bench" and .2 or 1.8)
				if space:Free(spot, 1) then
					placed += 1
					marker(ghosts, "GhostResident", spot + V3(0, 2.6, 0), { Pose = d.Name == "Bench" and "Sit" or "Mourn",
						Facing = d.Name == "Bench" and toward or -toward })
				end
			end
		end
	end
	local function ghost(pos: Vector3, pose: string, facing: Vector3)
		marker(ghosts, "GhostResident", pos + V3(0, 2.6, 0), { Pose = pose, Facing = facing.Unit })
	end
	ghost((SQ.TollBox * CF(-3.2, 0, -1.5)).Position, "Wait", SQ.TollBox.LookVector * -1)
	ghost((SQ.Tailor * CF(2.8, 0, 1.6)).Position, "Wait", SQ.Tailor.LookVector * -1)
	ghost((SQ.CoffinShrine * CF(4.6, 0, -6.2)).Position, "Mourn", SQ.CoffinShrine.LookVector * -1)
	ghost(V3(L.ArrivalArch.X + 9, 0, L.ArrivalArch.Z + 6), "Wander", V3(0, 0, 1))
	ghost(U.Polar(c, 72, PI * .62, 0), "Wander", V3(1, 0, 0))
	ghost(U.Polar(c, 72, PI * 1.38, 0), "Wander", V3(-1, 0, 0))

	root:SetAttribute("Markers", (counts.MothSwarm or 0) + (counts.FogPoint or 0) + (counts.WispPath or 0) + (counts.GhostResident or 0))
	if ctx.Note then
		ctx.Note(string.format("FXMarkers: MothSwarm %d, FogPoint %d, WispPath %d, GhostResident %d", counts.MothSwarm or 0, counts.FogPoint or 0,
			counts.WispPath or 0, counts.GhostResident or 0))
	end
end

return FXMarkers
