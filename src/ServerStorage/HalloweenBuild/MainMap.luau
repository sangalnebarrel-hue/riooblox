-- NIGHT OF THE BURIED MOON — main-map Halloween layer builder (ServerStorage.HalloweenBuild.MainMap, WP3).
-- Run offline by hw/edits/deadyard.luau with ctx.Layer = Workspace.DOGROTS_District.39_HalloweenLayer; the output is
-- saved in the place. Everything new lives in the layer (World.Disable destroys it); the only EXISTING parts it touches
-- are the 102 lamp glasses + their PointLights (note 08 §10), recoloured after K.Remember (Color only — never
-- Brightness/Range/Enabled), tagged `Halloween_MapLamp = true` + `Halloween_EventColor` so the client toggle
-- (HalloweenClient.MainMapLayer, player attribute HwMapDecor == false) can restore / re-apply them locally.
-- Decorations are non-collidable (players are never blocked), anchored, shadowless, and snap onto the real roof /
-- ground tops measured from the place at build time. Budget: <= 900 parts, <= 12 new PointLights (Shadows off).
-- Light attribute `HwBaseBrightness` = the build brightness (the client flickers Brightness only, never Enabled).
-- Part names avoid MapArtDirection keywords (note 08 §8).
local K = require(script.Parent.Kit)
local C = K.C
local P = K.Palette

local M = {}

local ORANGE, VIOLET, GREEN = C(255, 140, 40), C(176, 92, 240), C(120, 255, 90)
M.LampCycle = { ORANGE, VIOLET, ORANGE, GREEN }
local LAMP_KINDS = { Lantern_street = true, Lantern_bollard = true, PromenadeLantern = true, StreetLamp = true, Streetlamp = true }
local LAMP_GLASS = { WarmGlass = true, WarmLens = true, AmberGlass = true }

local CLOTH = C(54, 22, 84) -- deep moon purple
local CLOTH_INK = C(26, 16, 38)
local BONE = P.Bone
local GOLD = C(226, 178, 74)
local IRON = C(40, 40, 48)
local HAT = C(50, 24, 78)

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles

-- deterministic RNG with Random's NextNumber / NextInteger (Lune's roblox lib has no Random)
local function newRng(seed: number)
	local s = math.floor(seed) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	local r = {}
	function r:NextNumber(a: number?, b: number?): number
		s = (s * 16807) % 2147483647
		local u = s / 2147483647
		if a == nil then
			return u
		end
		return a + ((b :: number) - a) * u
	end
	function r:NextInteger(a: number, b: number): number
		return math.min(b, a + math.floor(self:NextNumber() * (b - a + 1)))
	end
	return r
end

------------------------------------------------------------------------------------------------------------------
-- Surface probe: highest top surface of the existing map at (x, z) near an expected height (AABB footprint test).
------------------------------------------------------------------------------------------------------------------
local Probe = {}
Probe.__index = Probe

function Probe.new(district: Instance, skip: { [Instance]: boolean })
	local list = {}
	local function walk(inst: Instance)
		for _, c in ipairs(inst:GetChildren()) do
			if not skip[c] then
				if c:IsA("BasePart") and c.Transparency < .95 then
					local cf, s = c.CFrame, c.Size
					local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
					local ex = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) / 2
					local ey = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2
					local ez = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) / 2
					table.insert(list, { x - ex, x + ex, z - ez, z + ez, y + ey })
				end
				walk(c)
			end
		end
	end
	walk(district)
	return setmetatable({ List = list, Misses = 0 }, Probe)
end

-- top y at (x, z) within [hint - tol, hint + tol]; falls back to hint (counted as a miss)
function Probe:Top(x: number, z: number, hint: number, tol: number?): number
	tol = tol or 1.5
	local best = nil
	for _, e in ipairs(self.List) do
		if x >= e[1] and x <= e[2] and z >= e[3] and z <= e[4] then
			local t = e[5]
			if t >= hint - tol and t <= hint + tol and (best == nil or t > best) then
				best = t
			end
		end
	end
	if best == nil then
		self.Misses += 1
		return hint
	end
	return best
end

------------------------------------------------------------------------------------------------------------------
-- Geometry helpers
------------------------------------------------------------------------------------------------------------------
-- any triangle as 1–2 WedgeParts (split at the foot of the altitude; a right triangle stays one wedge)
local function wedgeRight(parent, name, x: Vector3, f: Vector3, r: Vector3, thick, color, mat, props)
	-- right angle at f; legs f-x (wedge depth) and r-f (wedge height)
	local leg1, leg2 = f - x, r - f
	if leg1.Magnitude <= .02 or leg2.Magnitude <= .02 then
		return nil
	end
	local zA, yA = leg1.Unit, leg2.Unit
	return K.Part(parent, name, V3(thick, leg2.Magnitude, leg1.Magnitude), CFrame.fromMatrix((x + r) / 2, yA:Cross(zA), yA, zA), color, mat,
		{ Class = "WedgePart", Transparency = props and props.Transparency })
end

local function tri(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, thick: number, color: Color3, mat: Enum.Material?, props: any?)
	local pts = { a, b, c }
	for i = 1, 3 do -- a right triangle is a single wedge
		local v, u, w = pts[i], pts[i % 3 + 1], pts[(i + 1) % 3 + 1]
		local e1, e2 = u - v, w - v
		if math.abs(e1:Dot(e2)) < 1e-3 * e1.Magnitude * e2.Magnitude then
			return { wedgeRight(parent, name, u, v, w, thick, color, mat, props) }
		end
	end
	local best, bi = -1, 1
	for i = 1, 3 do
		local d = (pts[i % 3 + 1] - pts[i]).Magnitude
		if d > best then
			best, bi = d, i
		end
	end
	local p, q, r = pts[bi], pts[bi % 3 + 1], pts[(bi + 1) % 3 + 1]
	local pq = q - p
	local f = p + pq * ((r - p):Dot(pq) / pq:Dot(pq))
	local out = {}
	for _, x in ipairs({ p, q }) do
		local w = wedgeRight(parent, name, x, f, r, thick, color, mat, props)
		if w then
			table.insert(out, w)
		end
	end
	return out
end

-- jack-o'-lantern (Kit look) standing at `pos`, face turned toward `faceTo` (horizontal) with a small yaw jitter
local function pumpkin(parent: Instance, pos: Vector3, size: number, faceTo: Vector3, opts: any?, yaw: number?)
	opts = opts or {}
	local target = V3(faceTo.X, pos.Y, faceTo.Z)
	local cf = ((target - pos).Magnitude > .01 and K.Look(pos, target) or CF(pos)) * ANG(0, yaw or 0, 0)
	if opts.Tilt then
		cf = cf * ANG(opts.Tilt.X or 0, 0, opts.Tilt.Z or 0)
	end
	local m = K.Pumpkin(parent, cf, size, opts)
	if opts.Teeth == false then
		for _, c in ipairs(m:GetChildren()) do
			if c.Name == "PumpkinTooth" then
				c:Destroy()
			end
		end
	end
	return m
end

local function plain(parent, pos, size, color, rng, lobes)
	return pumpkin(parent, pos, size, pos + V3(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)),
		{ Face = false, Light = false, Lobes = lobes or 5, Color = color, Name = "Gourd" }, 0)
end

-- crescent moon disc pair in frame F (local -Z = front). two = passes through a thin cloth (seen from both sides)
local function moon(parent: Instance, F: CFrame, d: number, behind: Color3, two: boolean?, glow: boolean?)
	local t = two and .24 or .08
	local z = two and 0 or -.11
	if glow and not two then
		K.CylZ(parent, "MoonHalo", .05, d * 1.18, F * CF(0, 0, -.08), VIOLET, Enum.Material.Neon)
	end
	K.CylZ(parent, "MoonDisc", t, d, F * CF(0, 0, z), BONE, Enum.Material.SmoothPlastic)
	K.CylZ(parent, "MoonBite", t + .03, d * .8, F * CF(d * .26, d * .16, z - (two and 0 or .02)), behind, Enum.Material.Fabric)
end

-- flat pumpkin emblem in frame F (local -Z = front): disc, ribs, stem, glowing carved face
local function pumpkinEmblem(parent: Instance, F: CFrame, d: number, two: boolean?, face: boolean?)
	local t = two and .24 or .08
	local z = two and 0 or -.11
	K.CylZ(parent, "EmblemPumpkin", t, d, F * CF(0, 0, z), P.Pumpkin, Enum.Material.SmoothPlastic)
	K.Part(parent, "EmblemStem", V3(d * .16, d * .26, t + .02), F * CF(d * .03, d * .55, z) * ANG(0, 0, -.25), P.Stem, Enum.Material.Wood)
	if face ~= false then
		local ft = t + .04
		local fz = z - (two and 0 or .03)
		for s = -1, 1, 2 do
			local e = F * CF(s * d * .2, d * .1, fz)
			tri(parent, "EmblemEye", (e * CF(-d * .09, -d * .07, 0)).Position, (e * CF(d * .09, -d * .07, 0)).Position, (e * CF(s * d * .09, d * .1, 0)).Position,
				ft, P.Flame, Enum.Material.Neon)
		end
		K.Part(parent, "EmblemMouth", V3(d * .46, d * .1, ft), F * CF(0, -d * .2, fz), P.Flame, Enum.Material.Neon)
	elseif face == false and not two then
		for s = -1, 1, 2 do
			K.Part(parent, "EmblemRib", V3(d * .05, d * .78, t + .02), F * CF(s * d * .2, 0, z), P.PumpkinDark, Enum.Material.SmoothPlastic)
		end
	end
end

-- 4-point Neon star (two thin diamonds) in frame F
local function star(parent: Instance, F: CFrame, s: number, color: Color3?)
	K.Part(parent, "StarGlint", V3(s * .3, s, .08), F * ANG(0, 0, math.rad(45)), color or GOLD, Enum.Material.Neon)
	K.Part(parent, "StarGlint", V3(s * .3, s, .08), F * ANG(0, 0, math.rad(135)), color or GOLD, Enum.Material.Neon)
end

-- flat bat silhouette in frame F (plane = local XY, local -Z = front), wingspan ~ 5.4 * s
local function batSilhouette(parent: Instance, F: CFrame, s: number, eyes: Color3?)
	local m = K.Model(parent, "BatSilhouette")
	local th = .16
	local function p(x, y)
		return (F * CF(x * s, y * s, 0)).Position
	end
	K.Ellipsoid(m, "BatBody", V3(.72 * s, 1.3 * s, .3), F, CLOTH_INK, Enum.Material.SmoothPlastic)
	K.Ball(m, "BatHead", .66 * s, F * CF(0, .8 * s, 0), CLOTH_INK, Enum.Material.SmoothPlastic)
	for side = -1, 1, 2 do
		tri(m, "BatEar", p(side * .1, 1.0), p(side * .34, 1.0), p(side * .34, 1.42), th, CLOTH_INK)
		-- inner panel: right angle at the shoulder; outer panel: right angle at the wrist (scalloped trailing edge)
		tri(m, "BatWing", p(side * 1.55, .95), p(side * .25, .35), p(side * .61, -.43), th, CLOTH_INK)
		tri(m, "BatWing", p(side * 2.75, .45), p(side * 1.55, .95), p(side * 1.1, -.13), th, CLOTH_INK)
	end
	K.Part(m, "BatEyes", V3(.42 * s, .09 * s, .1), F * CF(0, .84 * s, -.18 * s), eyes or C(255, 120, 40), Enum.Material.Neon)
	return m
end

-- corner cobweb: corner O, unit u (along the top edge), unit v (down the side), slight offset n (toward the viewer)
local function cobweb(parent: Instance, O: Vector3, u: Vector3, v: Vector3, n: Vector3, L: number)
	local m = K.Model(parent, "Cobweb")
	local col = C(232, 232, 240)
	local o = O + n * .06
	local spokes = {}
	for i = 0, 3 do
		local a = math.rad(i * 30)
		spokes[i] = (u * math.cos(a) + v * math.sin(a)).Unit
		K.Bar(m, "WebThread", o, o + spokes[i] * L, .05, .05, col, Enum.Material.SmoothPlastic, { Transparency = .25 })
	end
	for _, r in ipairs({ L * .36, L * .7 }) do
		for i = 0, 2 do
			local a, b = o + spokes[i] * r, o + spokes[i + 1] * r
			local mid = (a + b) / 2
			local sag = mid + (o - mid).Unit * r * .07
			K.Bar(m, "WebThread", a, sag, .045, .045, col, Enum.Material.SmoothPlastic, { Transparency = .3 })
			K.Bar(m, "WebThread", sag, b, .045, .045, col, Enum.Material.SmoothPlastic, { Transparency = .3 })
		end
	end
	return m
end

-- hanging cloth banner. F = rod centre; local X across, Y up, -Z = front. o: W, H, Tail, Color, Trim, Emblem
-- ("Moon"|"Pumpkin"|"Bat"), EmblemY (from the top), EmblemD, Two (emblem visible from both sides), Text, TextColor,
-- TextBox {W, H, Y} (scale of the cloth face), Text2, Text2Box, Rod (default true)
local function banner(parent: Instance, name: string, F: CFrame, o: any)
	local m = K.Model(parent, name)
	local W, H, tail = o.W, o.H, o.Tail or W * .3
	local cloth = o.Color or CLOTH
	if o.Rod ~= false then
		K.CylX(m, "BannerRod", W + .9, .3, F, IRON, Enum.Material.Metal)
		for s = -1, 1, 2 do
			K.Ball(m, "BannerFinial", .5, F * CF(s * (W / 2 + .5), 0, 0), GOLD, Enum.Material.Metal)
		end
	end
	local top = -.12
	local body = K.Part(m, "BannerCloth", V3(W, H, .14), F * CF(0, top - H / 2, 0), cloth, Enum.Material.Fabric)
	local yb = top - H
	tri(m, "BannerTail", (F * CF(-W / 2, yb + .01, 0)).Position, (F * CF(W / 2, yb + .01, 0)).Position, (F * CF(0, yb - tail, 0)).Position, .14, cloth, Enum.Material.Fabric)
	local trim = o.Trim == nil and ORANGE or o.Trim
	if trim then
		K.Part(m, "BannerTrim", V3(W, math.max(.14, H * .045), .17), F * CF(0, top - H * .06, 0), trim, Enum.Material.Fabric)
	end
	if trim and o.TrimBottom ~= false then
		K.Part(m, "BannerTrim", V3(W, math.max(.12, H * .035), .17), F * CF(0, yb + H * .07, 0), trim, Enum.Material.Fabric)
	end
	if o.Tassel ~= false then
		local apex = F * CF(0, yb - tail, 0)
		K.CylY(m, "BannerTassel", .5 + W * .04, .12, apex * CF(0, -.25 - W * .02, 0), GOLD, Enum.Material.Fabric)
		K.Ball(m, "BannerTasselKnot", .28 + W * .015, apex * CF(0, -.05, 0), GOLD, Enum.Material.Fabric)
	end
	local ed = o.EmblemD or W * .55
	local function emblemAt(kind, ex, ey)
		local E = F * CF(ex, ey, 0)
		if kind == "Moon" then
			moon(m, E, ed, cloth, o.Two, o.Glow ~= false)
			if not o.Two and o.Stars ~= false then
				star(m, E * CF(ed * .62, -ed * .32, -.12), ed * .26)
				star(m, E * CF(-ed * .55, ed * .42, -.12), ed * .18)
			end
		elseif kind == "Pumpkin" then
			pumpkinEmblem(m, E, ed, o.Two, o.Face)
		elseif kind == "Bat" then
			batSilhouette(m, E * CF(0, 0, o.Two and 0 or -.12), ed / 5.4)
		end
	end
	if o.Emblem then
		emblemAt(o.Emblem, o.EmblemX or 0, top - (o.EmblemY or H * .4))
	end
	for _, e in ipairs(o.Emblems or {}) do
		emblemAt(e[1], e[2], top - e[3])
	end
	if o.Text then
		local box = o.TextBox or { W = .9, H = .5, Y = .25 }
		local g = K.Sign(body, Enum.NormalId.Front, o.Text, o.TextColor or BONE, { W = box.W, H = box.H, PixelsPerStud = o.PPS or 24, StrokeColor = CLOTH_INK })
		g:FindFirstChild("Title").Position = UDim2.fromScale((1 - box.W) / 2 + (box.X or 0), box.Y)
	end
	if o.Text2 then
		local box = o.Text2Box or { W = .5, H = .22, Y = .72 }
		local g = K.Sign(body, Enum.NormalId.Front, o.Text2, o.Text2Color or ORANGE, { Name = "Lettering2", W = box.W, H = box.H, PixelsPerStud = o.PPS or 24, StrokeColor = CLOTH_INK })
		g:FindFirstChild("Title").Position = UDim2.fromScale((1 - box.W) / 2 + (box.X or 0), box.Y)
	end
	return m, body
end

-- little iron candle lantern with a warm Neon glass (optionally lit)
local function smallLantern(parent: Instance, cf: CFrame, color: Color3, lit: boolean)
	local m = K.Model(parent, "TrickLantern")
	K.Part(m, "LanternTop", V3(.95, .25, .95), cf * CF(0, .78, 0), IRON, Enum.Material.Metal)
	local g = K.Part(m, "LanternPane", V3(.7, 1.15, .7), cf, color, Enum.Material.Neon)
	K.Part(m, "LanternBottom", V3(.85, .2, .85), cf * CF(0, -.67, 0), IRON, Enum.Material.Metal)
	if lit then
		K.Light(g, color, 13, .75)
	end
	return m
end

------------------------------------------------------------------------------------------------------------------
-- Sections
------------------------------------------------------------------------------------------------------------------
local function lamps(ctx, skip, stats)
	local groups = {}
	local function walk(inst: Instance)
		for _, c in ipairs(inst:GetChildren()) do
			if not skip[c] then
				if c:IsA("Model") and LAMP_KINDS[c.Name] then
					local glass, lights = nil, {}
					for _, d in ipairs(c:GetDescendants()) do
						if d:IsA("BasePart") and LAMP_GLASS[d.Name] then
							glass = d
						elseif d:IsA("Light") then
							table.insert(lights, d)
						end
					end
					if glass then
						local pos = glass.CFrame.Position
						-- one colour rhythm per row of lamps (same parent and the same |x| / |z| line): mirrored pairs match
						local key = c.Parent:GetFullName() .. "|" .. tostring(math.floor(math.abs(pos.X) / 8 + .5))
						groups[key] = groups[key] or {}
						table.insert(groups[key], { Glass = glass, Lights = lights, Pos = pos })
					end
				else
					walk(c)
				end
			end
		end
	end
	walk(ctx.District)
	local keys = {}
	for k in pairs(groups) do
		table.insert(keys, k)
	end
	table.sort(keys)
	for gi, key in ipairs(keys) do
		local list = groups[key]
		local zs, seen = {}, {}
		for _, l in ipairs(list) do
			local zk = math.floor(l.Pos.Z + .5)
			if not seen[zk] then
				seen[zk] = true
				table.insert(zs, zk)
			end
		end
		table.sort(zs)
		local rank = {}
		for i, z in ipairs(zs) do
			rank[z] = i
		end
		for _, l in ipairs(list) do
			local col = M.LampCycle[(rank[math.floor(l.Pos.Z + .5)] + gi - 2) % #M.LampCycle + 1]
			K.Remember(l.Glass)
			l.Glass.Color = col
			l.Glass:SetAttribute("Halloween_EventColor", col)
			l.Glass:SetAttribute("Halloween_MapLamp", true)
			for _, light in ipairs(l.Lights) do
				K.Remember(light)
				light.Color = col
				light:SetAttribute("Halloween_EventColor", col)
				light:SetAttribute("Halloween_MapLamp", true)
				stats.LampLights += 1
			end
			stats.Lamps += 1
		end
	end
end

local function spawnRing(root, probe, rng)
	local m = K.Model(root, "SpawnRing")
	local c = V3(0, 0, 377)
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		local r = 11.6
		local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
		local y = probe:Top(x, z, .4, 1)
		local big = i % 2 == 0
		pumpkin(m, V3(x, y, z), big and 2.9 or 2.3, c, { Lobes = 5, Light = (i == 1 or i == 5), Color = big and P.Pumpkin or C(240, 112, 22) },
			rng:NextNumber(-.25, .25))
	end
	for _, z in ipairs({ 377 - 12.4, 377 + 12.4 }) do
		local y = probe:Top(0, z, .4, 1)
		K.Candles(m, CF(0, y, z), 3, rng, { Light = false, Spread = .8 })
	end
end

local function plazaPiles(root, probe, rng)
	local m = K.Model(root, "PlazaPiles")
	local c = V3(0, 0, 342)
	for i, d in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
		local dir = V3(d[1], 0, d[2]).Unit
		local base = c + dir * 24.6
		local side = V3(-dir.Z, 0, dir.X)
		local pile = K.Model(m, "PumpkinPile")
		local y = probe:Top(base.X, base.Z, .4, 1)
		pumpkin(pile, V3(base.X, y, base.Z), 3.5, c, { Lobes = 6, Light = true }, rng:NextNumber(-.2, .2))
		local p2 = base + side * 2.6 + dir * .5
		plain(pile, V3(p2.X, probe:Top(p2.X, p2.Z, .4, 1), p2.Z), 2.3, i % 2 == 0 and C(236, 226, 200) or C(232, 120, 30), rng, 5)
		local p3 = base - side * 2.3 + dir * .8
		plain(pile, V3(p3.X, probe:Top(p3.X, p3.Z, .4, 1), p3.Z), 1.6, C(122, 150, 84), rng, 4)
		if i <= 2 then
			local p4 = base + side * .9 - dir * 1.5
			K.Candles(pile, CF(p4.X, probe:Top(p4.X, p4.Z, .4, 1), p4.Z), 2, rng, { Light = false, Spread = .5 })
		end
	end
end

local function entryArch(root, probe, rng)
	local m = K.Model(root, "EntryArch")
	local lintelY = 19.9
	-- jack-o'-lanterns crowning the arch roof above the pylons (the CrownCaps sit inside the lintel; roof top ~25.4)
	for s = -1, 1, 2 do
		local x = s * 18.6
		local y = probe:Top(x, 401, 25.4, .6)
		pumpkin(m, V3(x, y, 400.7), 3.6, V3(x * .7, y, 360), { Lobes = 6, Light = true, Teeth = false }, 0)
		plain(m, V3(x - s * 2.3, y, 402.2), 1.6, C(236, 226, 200), rng, 4)
	end
	-- hero banners under the lintel on both faces (don't touch the DOGROTS signs above)
	for _, face in ipairs({ { Z = 399.65, Rot = 0, Spawn = true }, { Z = 402.35, Rot = math.pi, Spawn = false } }) do
		local F = CF(0, lintelY - .16, face.Z) * ANG(0, face.Rot, 0)
		banner(m, face.Spawn and "ArchBannerSpawn" or "ArchBannerBack", F, {
			W = 25, H = 3.9, Tail = 1.2, Color = CLOTH, Trim = ORANGE,
			Emblems = { { "Moon", -10.5, 1.95 }, { "Pumpkin", 10.5, 1.95 } }, EmblemD = 2.9,
			Text = "NIGHT OF THE BURIED MOON", TextBox = face.Spawn and { W = .68, H = .5, Y = .1 } or { W = .68, H = .62, Y = .17 }, PPS = 22,
			Text2 = face.Spawn and "THE DEAD YARD ↑" or nil, Text2Box = { W = .36, H = .25, Y = .64 },
		})
		if face.Spawn then
			-- hanging jack-o'-lanterns between the banner and the pylons
			for s = -1, 1, 2 do
				local x = s * 15.2
				K.Chain(m, V3(x, lintelY, face.Z), V3(x, 17.7, face.Z), .02, 4)
				local pm = pumpkin(m, V3(x, 15.7, face.Z), 2.1, V3(x, 15.7, 380), { Lobes = 5, Light = false }, 0)
				pm.Name = "HangingPumpkin"
			end
			for s = -1, 1, 2 do
				local y = probe:Top(s * 18.5, 397.2, .4, 1)
				K.Candles(m, CF(s * 18.4, y, 397.4), 3, rng, { Light = false, Spread = .9 })
			end
		else
			for s = -1, 1, 2 do
				cobweb(m, V3(s * 16.9, lintelY, face.Z + .2), V3(-s, 0, 0), V3(0, -1, 0), V3(0, 0, 1), 3.4)
			end
		end
	end
end

-- small two-sided pennants on the outer lamp columns along the main avenue (x = +-36)
local function lampPennants(root, district, skip)
	local m = K.Model(root, "LampPennants")
	local pp = district:FindFirstChild("01_IslandAndStreets")
	pp = pp and pp:FindFirstChild("PrimaryPaths")
	if not pp then
		return
	end
	local list = {}
	for _, lamp in ipairs(pp:GetChildren()) do
		if lamp.Name == "Lantern_street" then
			local col = lamp:FindFirstChild("Column")
			if col and col:IsA("BasePart") then
				local p = col.CFrame.Position
				-- the avenue rows only, outside THE DEAD YARD footprint
				if math.abs(math.abs(p.X) - 36) < 1 and not (p.X > 32 and p.Z > 530) then
					table.insert(list, p)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Z < b.Z or (a.Z == b.Z and a.X < b.X)
	end)
	local rows, rowOf = {}, {}
	for _, p in ipairs(list) do
		local zk = math.floor(p.Z + .5)
		if not rowOf[zk] then
			table.insert(rows, zk)
			rowOf[zk] = #rows
		end
	end
	for _, p in ipairs(list) do
		local s = p.X > 0 and -1 or 1 -- toward the avenue
		local y = 9.35
		local g = K.Model(m, "LampPennant")
		K.CylY(g, "PennantClamp", .36, .82, CF(p.X, y, p.Z), IRON, Enum.Material.Metal)
		K.Bar(g, "PennantArm", V3(p.X + s * .3, y, p.Z), V3(p.X + s * 2.55, y, p.Z), .15, .15, IRON, Enum.Material.Metal)
		local moonRow = rowOf[math.floor(p.Z + .5)] % 2 == 1
		local F = CF(p.X + s * 1.55, y, p.Z)
		banner(g, "Pennant", F, {
			Rod = false, W = 1.7, H = 2.35, Tail = .75, Color = moonRow and CLOTH or CLOTH_INK, Trim = false,
			TrimBottom = false, Tassel = false, Two = true, Emblem = moonRow and "Moon" or "Pumpkin", EmblemD = 1.15, EmblemY = 1.3,
			Face = false,
		})
	end
end

-- festival garlands strung across the avenue between opposite lamp columns (x = +-36), diamond flags
local function avenueGarlands(root, district)
	local m = K.Model(root, "AvenueGarlands")
	local pp = district:FindFirstChild("01_IslandAndStreets")
	pp = pp and pp:FindFirstChild("PrimaryPaths")
	if not pp then
		return
	end
	local cols = {}
	for _, lamp in ipairs(pp:GetChildren()) do
		local col = lamp.Name == "Lantern_street" and lamp:FindFirstChild("Column")
		if col and col:IsA("BasePart") then
			local p = col.CFrame.Position
			cols[string.format("%d|%d", p.X > 0 and 1 or -1, math.floor(p.Z + .5))] = p
		end
	end
	local flagColors = { P.Pumpkin, CLOTH, CLOTH_INK, P.Pumpkin, VIOLET:Lerp(CLOTH, .45), CLOTH_INK }
	for _, z in ipairs({ 241, 421 }) do
		local a, b = cols["-1|" .. z], cols["1|" .. z]
		if a and b then
			local g = K.Model(m, "AvenueGarland")
			local y, sag, segs = 11.75, 3.1, 6
			local A, B = V3(a.X + .35, y, a.Z), V3(b.X - .35, y, b.Z)
			local function at(t)
				return A:Lerp(B, t) - V3(0, sag * 4 * t * (1 - t), 0)
			end
			for i = 1, segs do
				K.Bar(g, "GarlandRope", at((i - 1) / segs), at(i / segs), .12, .12, C(48, 36, 56), Enum.Material.Fabric)
			end
			local n = 13
			for i = 1, n do
				local t = (i - .5) / n
				local p = at(t)
				K.Part(g, "GarlandFlag", V3(1.25, 1.25, .1), CF(p - V3(0, .86, 0)) * ANG(0, 0, math.rad(45)), flagColors[(i - 1) % #flagColors + 1], Enum.Material.Fabric)
			end
		end
	end
end

-- "THE DEAD YARD" signposts at the avenue junctions (RouteGraph B479, B566)
local function signpost(root, probe, rng, name: string, base: Vector3, dir: Vector3, approach: Vector3)
	local m = K.Model(root, name)
	local up = V3(0, 1, 0)
	local y0 = probe:Top(base.X, base.Z, .3, 1)
	local b = V3(base.X, y0, base.Z)
	K.Part(m, "SignFoot", V3(1.7, .7, 1.7), CF(b + V3(0, .35, 0)), P.StoneDark, Enum.Material.Slate)
	K.Part(m, "SignPost", V3(.6, 9.2, .6), CF(b + V3(0, .7 + 4.6, 0)) * ANG(0, .1, 0), P.WoodDark, Enum.Material.Wood)
	K.Part(m, "SignPostCap", V3(.85, .25, .85), CF(b + V3(0, 10.0, 0)), IRON, Enum.Material.Metal)
	pumpkin(m, b + V3(0, 10.12, 0), 2.0, approach, { Lobes = 5, Light = false, Teeth = false }, rng:NextNumber(-.2, .2))
	local zAxis = dir:Cross(up)
	local function board(yc: number, len: number, h: number, color: Color3, text: string, arrow: boolean, mat: Enum.Material)
		local center = b + dir * (len / 2 + .2) + V3(0, yc, 0)
		local frame = CFrame.fromMatrix(center, dir, up, zAxis)
		local bd = K.Part(m, "SignBoard", V3(len, h, .24), frame, color, mat)
		if arrow then
			local e = b + dir * (len + .2) + V3(0, yc, 0)
			tri(m, "SignArrow", e + V3(0, h / 2, 0), e - V3(0, h / 2, 0), e + dir * (h * .75), .24, color, mat)
			K.Part(m, "SignTrim", V3(len, .09, .27), frame * CF(0, h / 2 - .1, 0), ORANGE, Enum.Material.Fabric)
		end
		for _, faceDef in ipairs({ { Enum.NormalId.Front, -zAxis, "Front" }, { Enum.NormalId.Back, zAxis, "Back" } }) do
			local n = faceDef[2]
			local right = (-n):Cross(up)
			local txt = text
			if arrow then
				txt = right:Dot(dir) > 0 and (text .. " →") or ("← " .. text)
			end
			K.Sign(bd, faceDef[1], txt, arrow and C(255, 214, 120) or BONE, { Name = "Lettering" .. faceDef[3], W = .9, H = .74, PixelsPerStud = 32, StrokeColor = CLOTH_INK })
		end
		return bd
	end
	board(8.0, 5.8, 1.35, P.WoodDark, "THE DEAD YARD", true, Enum.Material.Wood)
	board(6.35, 4.6, 1.05, CLOTH, "NIGHT OF THE BURIED MOON", false, Enum.Material.Wood)
	-- lantern hanging from a short arm on the other side
	local armEnd = b - dir * 1.5 + V3(0, 9.1, 0)
	K.Bar(m, "SignArm", b + V3(0, 9.1, 0) - dir * .3, armEnd, .14, .14, IRON, Enum.Material.Metal)
	K.Bar(m, "SignHook", armEnd, armEnd - V3(0, .5, 0), .08, .08, IRON, Enum.Material.Metal)
	smallLantern(m, CF(armEnd - V3(0, 1.3, 0)), ORANGE, true)
	K.Candles(m, CF(b + dir * 1.6 + zAxis * 1.0), 2, rng, { Light = false, Spread = .3 })
end

local function shops(root, district, probe, rng)
	local m = K.Model(root, "PawMarket")
	local s11 = district:FindFirstChild("11_Shops")
	for i, name in ipairs({ "UPGRADES", "COSMETICS", "SUPPLIES" }) do
		local shop = s11 and s11:FindFirstChild(name)
		local arch = shop and shop:FindFirstChild("Architecture")
		local ridge = arch and arch:FindFirstChild("Ridge")
		local cornice = arch and arch:FindFirstChild("Cornice")
		local c = ridge and ridge.CFrame.Position.Z or ({ 275, 335, 395 })[i]
		local ridgeTop = ridge and (ridge.CFrame.Position.Y + ridge.Size.Y / 2) or 28.7
		local front = cornice and (cornice.CFrame.Position.X - cornice.Size.Z / 2) or 117
		local g = K.Model(m, "Shop" .. name:sub(1, 1) .. name:sub(2):lower())
		pumpkin(g, V3(front + .7, ridgeTop - .05, c), 3.1, V3(60, ridgeTop, c), { Lobes = 5, Light = false, Teeth = false }, rng:NextNumber(-.15, .15))
		local corniceBottom = cornice and (cornice.CFrame.Position.Y - cornice.Size.Y / 2) or 20.4
		local corniceFront = cornice and (cornice.CFrame.Position.X - cornice.Size.Z / 2) or 117
		for s = -1, 1, 2 do
			local F = CF(corniceFront + .32, corniceBottom - .14, c + s * 18.0) * ANG(0, math.pi / 2, 0)
			local moonOne = (s == -1) == (i % 2 == 1)
			banner(g, "ShopBanner", F, {
				W = 2.3, H = 4.3, Tail = .8, Color = moonOne and CLOTH or CLOTH_INK, Trim = moonOne and ORANGE or VIOLET,
				Emblem = moonOne and "Moon" or "Pumpkin", EmblemD = 1.55, EmblemY = 1.9, Stars = false, Glow = false, Tassel = false, TrimBottom = false,
			})
		end
	end
end

local function shelter(root, probe, rng)
	local m = K.Model(root, "ShelterPorch")
	for i, z in ipairs({ 173.5, 182.5, 227.5, 236.5 }) do
		local x = 83.7
		local y = probe:Top(x, z, 16.25, .8)
		if i == 2 or i == 3 then
			pumpkin(m, V3(x, y, z), 2.7, V3(40, y, z), { Lobes = 6, Light = i == 2 }, rng:NextNumber(-.25, .25))
		else
			plain(m, V3(x + .2, y, z), 1.9, i == 1 and C(236, 226, 200) or C(232, 120, 30), rng, 5)
		end
	end
end

local function museum(root, probe, rng)
	local m = K.Model(root, "DogDexMuseum")
	-- bats streaming out of the grand arch (centre ~(-75, 48, 481), radius ~22.5), flat silhouettes facing +X
	local spots = { { 38, 26.6, 1.15, .35 }, { 63, 28.4, .9, -.3 }, { 101, 27.2, 1.3, .2 }, { 128, 26.4, .85, .5 }, { 152, 27.6, 1.05, -.2 } }
	for _, sp in ipairs(spots) do
		local a = math.rad(sp[1])
		local pos = V3(-73.4, 48 + math.sin(a) * sp[2], 481 - math.cos(a) * sp[2])
		batSilhouette(m, CF(pos) * ANG(0, -math.pi / 2, 0) * ANG(0, 0, sp[4]), sp[3])
	end
	-- vertical banners under the entrance lintel (bottom y ~30.45, front face x -70)
	for i, z in ipairs({ 466.6, 495.4 }) do
		local F = CF(-69.75, 30.3, z) * ANG(0, -math.pi / 2, 0)
		banner(m, "MuseumBanner", F, {
			W = 3.7, H = 6.6, Tail = 1.2, Color = i == 1 and CLOTH or CLOTH_INK, Trim = i == 1 and ORANGE or VIOLET,
			Emblem = i == 1 and "Moon" or "Pumpkin", EmblemD = 2.5, EmblemY = 1.75, Stars = false,
			Text = "NIGHT OF THE BURIED MOON", TextBox = { W = .86, H = .48, Y = .47 }, PPS = 24,
		})
	end
	-- pumpkins on the stepped wing roofs (top tier ~58.05), facing the avenue
	for _, z in ipairs({ 428.2, 447.8, 514.2, 533.8 }) do
		local x = -75.6
		local y = probe:Top(x, z, 58.05, 1)
		local carved = z == 447.8 or z == 514.2
		if carved then
			pumpkin(m, V3(x, y, z), 3.6, V3(40, y, z), { Lobes = 5, Light = false, Teeth = false }, 0)
		else
			plain(m, V3(x, y, z), 2.6, C(232, 120, 30), rng, 5)
		end
	end
end

local function leaderboards(root, district, probe, rng)
	local m = K.Model(root, "RecordPavilions")
	local lp = district:FindFirstChild("09_DogPark")
	lp = lp and lp:FindFirstChild("LeaderboardPlaza")
	lp = lp and lp:FindFirstChild("RecordPavilions")
	for _, name in ipairs({ "HonorPavilion", "DiscoveryPavilion", "LegacyPavilion" }) do
		local pav = lp and lp:FindFirstChild(name)
		local roof = pav and pav:FindFirstChild("Roof")
		if roof and roof:IsA("BasePart") then
			local p = roof.CFrame.Position
			local y = p.Y + roof.Size.Y / 2
			pumpkin(m, V3(p.X, y, p.Z), 3.3, V3(-100, y, 240), { Lobes = 5, Light = false, Teeth = false }, rng:NextNumber(-.2, .2))
		end
	end
end

local function mailbox(root, district, probe, rng)
	local m = K.Model(root, "Mailbox")
	local hub = district:FindFirstChild("32_WelcomeHub")
	local mb = hub and hub:FindFirstChild("DeveloperMailbox")
	local roof = mb and mb:FindFirstChild("MailboxRoof")
	local p = roof and roof.CFrame.Position or V3(0, 8.8, 150)
	local y = roof and (p.Y + roof.Size.Y / 2) or 9.2
	pumpkin(m, V3(p.X + 1.2, y, p.Z + .3), 2.4, V3(p.X, y, p.Z + 40), { Lobes = 6, Light = true }, -.2)
	K.Candles(m, CF(p.X - 2.4, y, p.Z + .9), 2, rng, { Light = false, Spread = .4 })
end

-- giant voxel witch hat on THE DOG's head (flat top x -18..18, z -210..-174, y 86); front faces the avenue (+Z).
-- Night presence without a light of its own (the layer's 12 lights are spent): a glowing pumpkin band framed by violet
-- neon, a violet neon rim round the brim and at four steps of the crown (the silhouette reads against the night sky
-- from the spawn), a neon star on the drooping tip with a glowing crescent charm dangling from it, patches sewn on
-- with glowing green thread; the client's bat flock circles it (MainMapLayer, landmark "TheDog").
local function witchHat(root, probe)
	local m = K.Model(root, "TheDogWitchHat")
	local y0 = probe:Top(0, -192, 86, 1.2)
	local O = CF(0, y0, -192) * ANG(0, 0, math.rad(-4)) -- a slight jaunty roll toward -X
	local NEON = Enum.Material.Neon
	local THREAD = P.Neon -- glowing green stitches
	local function blk(name, size, pos, color, mat)
		return K.Part(m, name, size, O * CF(pos), color, mat or Enum.Material.Fabric)
	end
	-- brim: a stepped round slab (voxel circle like the dog's dome), a violet neon rim sandwiched in it (only its
	-- outer edge shows, all the way round)
	local brims = { V3(50, 1.3, 36), V3(36, 1.3, 50), V3(44, 1.3, 44) }
	for i, sz in ipairs(brims) do
		blk("HatBrim", sz, V3(0, .65 + (i == 3 and .01 or 0), 0), HAT:Lerp(CLOTH_INK, i == 3 and .3 or .35))
		blk("HatBrimGlow", V3(sz.X + 1.1, .6, sz.Z + 1.1), V3(0, .62, 0), VIOLET, NEON)
	end
	blk("HatBrimTop", V3(34, .5, 34), V3(0, 1.5, 0), HAT:Lerp(CLOTH_INK, .15))
	-- crown: 14 voxel layers (two purples, a shade lighter than the night sky), the tip bends toward +X and droops
	local widths = { 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8.4, 6.8, 5.2, 3.8 }
	local shiftX = { 0, 0, 0, 0, 0, .4, 1, 2, 3.3, 5, 7, 9.4, 12, 14.8 }
	local lift = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -.6, -2.2 }
	local LH = 3
	local yb = 1.75
	local function layerY(i)
		return yb + (i - .5) * LH + lift[i]
	end
	for i, w in ipairs(widths) do
		local tone = (i % 2 == 0) and HAT:Lerp(C(96, 52, 140), .2) or HAT:Lerp(C(110, 62, 160), .38)
		blk("HatCrown", V3(w, LH, w), V3(shiftX[i], layerY(i), 0), tone)
	end
	-- violet neon rims hugging the foot of four steps
	for _, i in ipairs({ 4, 7, 10, 12 }) do
		local w = widths[i] + .7
		blk("HatStepGlow", V3(w, .5, w), V3(shiftX[i], layerY(i) - LH / 2 + .25, 0), VIOLET, NEON)
	end
	-- band (two layers tall): glowing pumpkin cloth between two violet neon lines + a gold buckle on the front (+Z)
	blk("HatBand", V3(28.8, 4.2, 28.8), V3(0, yb + 2.4, 0), P.PumpkinDark, NEON)
	blk("HatGlowStripe", V3(29.3, .6, 29.3), V3(0, yb + 4.7, 0), VIOLET, NEON)
	blk("HatGlowStripe", V3(29.3, .5, 29.3), V3(0, yb + .45, 0), VIOLET, NEON)
	local bz = 14.45
	blk("HatBuckle", V3(5.4, .6, .5), V3(0, yb + 4.15, bz), GOLD, Enum.Material.Metal)
	blk("HatBuckle", V3(5.4, .6, .5), V3(0, yb + .65, bz), GOLD, Enum.Material.Metal)
	blk("HatBuckle", V3(.6, 3.5, .5), V3(-2.4, yb + 2.4, bz), GOLD, Enum.Material.Metal)
	blk("HatBuckle", V3(.6, 3.5, .5), V3(2.4, yb + 2.4, bz), GOLD, Enum.Material.Metal)
	blk("HatBucklePin", V3(.5, 2.2, .6), V3(-.6, yb + 2.4, bz + .05), P.Gold, NEON)
	-- glowing crescent moon + stars on the front (+Z) of the crown; each floats just in front of the wider layer below
	local mo = O * CF(-1.4, layerY(5), widths[4] / 2 + .3) * ANG(0, math.pi, 0)
	K.CylZ(m, "HatMoon", .4, 5.4, mo, C(255, 236, 170), NEON)
	K.CylZ(m, "HatMoonBite", .5, 4.5, mo * CF(1.45, .95, -.1), HAT, Enum.Material.Fabric)
	for _, s in ipairs({ { 4, 3.2, 2.8 }, { 7, -2.6, 2.3 }, { 9, 2.3, 1.9 } }) do
		local li = s[1]
		star(m, O * CF(shiftX[li] + s[2], layerY(li), widths[li - 1] / 2 + .25) * ANG(0, math.pi, 0), s[3], C(255, 220, 110))
	end
	-- patches sewn on with glowing thread: one on the +X side, a small one on the front of the upper crown
	local px = widths[7] / 2 + shiftX[7] + .16
	blk("HatPatch", V3(.3, 2.5, 3.8), V3(px, layerY(7), 2.6), C(118, 70, 156))
	for k = -1, 1 do
		blk("HatStitch", V3(.36, .22, .9), V3(px + .03, layerY(7) + k * .8, 2.6 - 1.95), THREAD, NEON)
	end
	local fz = widths[11] / 2 + .16
	blk("HatPatch", V3(2.6, 2.2, .3), V3(shiftX[11] - .6, layerY(11), fz), C(150, 64, 40))
	for k = -1, 1, 2 do
		blk("HatStitch", V3(.22, 2.6, .36), V3(shiftX[11] - .6 + k * 1.3, layerY(11), fz + .03), THREAD, NEON)
	end
	-- the drooping tip: a neon star on its end and a glowing crescent charm dangling on a thread
	local tipX = shiftX[#widths] + widths[#widths] / 2
	local tipY = layerY(#widths)
	star(m, O * CF(tipX + .1, tipY, 0) * ANG(0, math.pi / 2, 0), 3.4, C(255, 226, 120))
	local top = O * CF(tipX - .6, tipY - LH / 2, 0)
	local bot = O * CF(tipX - .6, tipY - LH / 2 - 5.5, 0)
	K.Bar(m, "CharmThread", top.Position, bot.Position, .08, .08, C(220, 220, 230), Enum.Material.SmoothPlastic, { Transparency = .2 })
	K.CylZ(m, "CharmMoon", .35, 2.6, bot * CF(0, -1.2, 0), C(255, 236, 170), NEON)
	K.CylZ(m, "CharmMoonBite", .45, 2.2, bot * CF(.7, -.75, 0), HAT, Enum.Material.Fabric)
	-- built at unit scale, then grown about the brim base so it reads from the far end of the avenue
	local SC = 1.3
	local inv = O:Inverse()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = inv * d.CFrame
			d.Size = d.Size * SC
			d.CFrame = O * CF(rel.Position * SC) * (rel - rel.Position)
		end
	end
end

------------------------------------------------------------------------------------------------------------------
function M.Build(ctx)
	local layer = ctx.Layer
	local district = ctx.District
	assert(layer and district, "MainMap: ctx.Layer / ctx.District missing")
	local skip = {}
	for _, n in ipairs({ "38_DeadYard", "39_HalloweenLayer" }) do
		local x = district:FindFirstChild(n)
		if x then
			skip[x] = true
		end
	end
	local rng = newRng(31102026)
	local stats = { Lamps = 0, LampLights = 0 }
	lamps(ctx, skip, stats)
	local probe = Probe.new(district, skip)

	spawnRing(layer, probe, rng)
	plazaPiles(layer, probe, rng)
	entryArch(layer, probe, rng)
	lampPennants(layer, district, skip)
	avenueGarlands(layer, district)
	signpost(layer, probe, rng, "DeadYardSignB479", V3(20.6, 0, 491), V3(0, 0, 1), V3(0, 0, 440))
	-- north side of the Future paving (z 566..584): keeps the gate / "NIGHT OF THE BURIED MOON" plaque sightline clear
	signpost(layer, probe, rng, "DeadYardSignB566", V3(14, 0, 589), V3(1, 0, 0), V3(0, 0, 520))
	shops(layer, district, probe, rng)
	shelter(layer, probe, rng)
	museum(layer, probe, rng)
	leaderboards(layer, district, probe, rng)
	mailbox(layer, district, probe, rng)
	witchHat(layer, probe)

	-- final pass: decorations never block or cast, lights shadowless with a base brightness for the client flicker
	local parts, lights = 0, 0
	for _, d in ipairs(layer:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Anchored = true
			parts += 1
		elseif d:IsA("Light") then
			d.Shadows = false
			d:SetAttribute("HwBaseBrightness", d.Brightness)
			lights += 1
		elseif d:IsA("TextLabel") then
			d:SetAttribute("NoTranslate", true) -- HalloweenClient.MainMapLayer localizes these (MainMapLayer.RU)
		end
	end
	layer:SetAttribute("HalloweenMainMap", true)
	layer:SetAttribute("Parts", parts)
	layer:SetAttribute("Lights", lights)
	layer:SetAttribute("LampsRecoloured", stats.Lamps)
	local note = ctx.Note or print
	note(string.format("MainMap: %d parts, %d lights, %d lamps recoloured (%d lamp lights), %d probe misses",
		parts, lights, stats.Lamps, stats.LampLights, probe.Misses))
	if parts > 900 or lights > 12 then
		note(string.format("MainMap: OVER BUDGET (%d parts / %d lights; budget 900 / 12)", parts, lights))
	end
	return { Parts = parts, Lights = lights, Lamps = stats.Lamps }
end

return M
