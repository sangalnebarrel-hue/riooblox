-- THE BLACK COFFIN (ServerStorage.UnderyardBuild.BlackCoffin, WP-K4, Order 31). Build-time only: run by
-- tools/edits/40_underyard.luau through tools/sim.luau after the Bell Square builder (WP-G, Order 30); saved as
-- 40_Underyard.BlackCoffin (ModelStreamingMode Atomic). docs/halloween2/DESIGN.md §9.7, CoffinConfig.Model / Attr.
--   * Seated on the shrine's Attachment CoffinSeat (the bier of 40_Underyard.BellSquare.CoffinShrine); without that
--     builder it uses UnderyardLayout.Square.CoffinShrine and builds its own small bier + three chain posts.
--   * A tall black lacquered coffin (3.6 x 2.2 x 7.2, the classic six-sided outline: narrow foot towards the bell
--     tower, wide shoulders, the head towards the reredos): walls, corner posts, silver trims, bar handles, a plinth,
--     violet satin lining and a pillow inside, violet runes on the walls and the lid.
--   * The lid is its own hinge model (Atomic, PrimaryPart LidHinge on the -X long side, attribute CoffinLid): the
--     client swings it open about LidHinge's Z axis. It carries a raised panel, a silver crescent-moon-and-paw crest
--     and runes.
--   * Seam light (CoffinSeam = light-up order, Neon, Transparency 1): the lid joint all round, the corner seams and
--     cracks in the walls. Inner glow (CoffinInner, Transparency 1) with a disabled PointLight (CoffinLight).
--   * Three chains CoffinChain_1..3 (attribute CoffinChain = i, links CoffinLink = n) from the shrine's chain rings
--     (Attachments ChainAnchor_1..3) up over the lid's edges to the padlock (CoffinPadlock) on the lid.
--   * A small candle set on the bier's corners (flames HwCandle, CoffinCandle on the model).
-- Visual parts never collide: one invisible CoffinCollider box keeps the coffin solid while the client animates.
local BlackCoffin = { Order = 31 }

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local C3 = Color3.fromRGB
local M = Enum.Material
local PI = math.pi

local function rgb(t: { number }): Color3
	return C3(t[1], t[2], t[3])
end

-- part helpers (seat-local CFrames are mapped to the world by the caller's `at`)
local function make(parent: Instance, class: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material,
	opts: { [string]: any }?): BasePart
	local o = opts or {}
	local p = Instance.new(class) :: BasePart
	p.Name = name
	if o.Shape then
		(p :: any).Shape = o.Shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = o.Collide == true
	p.CanQuery = o.Collide == true
	p.CanTouch = false
	p.CastShadow = o.Shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.Transparency then
		p.Transparency = o.Transparency
	end
	if o.Reflectance then
		p.Reflectance = o.Reflectance
	end
	for k, v in pairs(o.Attrs or {}) do
		p:SetAttribute(k, v)
	end
	p.Parent = parent
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function atomic(m: Model)
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
end

-- a CFrame at `pos` whose X axis is `x` (horizontal), Y up, Z = X x Y
local function frame(pos: Vector3, x: Vector3): CFrame
	local xx = V3(x.X, 0, x.Z).Unit
	local up = V3(0, 1, 0)
	return CFrame.fromMatrix(pos, xx, up, xx:Cross(up))
end

-- a CFrame at the midpoint of a -> b whose Z axis runs along a -> b (any direction; Y as close to up as possible)
local function along(a: Vector3, b: Vector3): CFrame
	local d = b - a
	local z = d.Unit
	local up = math.abs(z.Y) > .98 and V3(1, 0, 0) or V3(0, 1, 0)
	local x = up:Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix((a + b) / 2, x, y, z)
end

function BlackCoffin.Build(ctx: any)
	local L = ctx.Layout
	local RS = game:GetService("ReplicatedStorage")
	local halloween = RS:FindFirstChild("Halloween")
	local CC = require((halloween and halloween:FindFirstChild("CoffinConfig")) :: ModuleScript) -- (the offline env has no WaitForChild)
	local D = CC.Model
	local A = CC.Attr
	local P = CC.Palette
	local rng = Random.new(31031)

	local INK, LACQUER, LACQUER2 = rgb(P.Ink), rgb(P.Lacquer), C3(30, 22, 44)
	local SILVER, SILVER_D, IRON = rgb(P.Silver), C3(104, 100, 118), rgb(P.Iron)
	local RUNE, SATIN, SATIN_D = rgb(P.Rune), rgb(P.Satin), C3(34, 12, 46)
	local WAX, FLAME = rgb(P.Wax), rgb(P.Candle)

	-------------------------------------------------------------------------------------------------------- the seat
	-- WP-G's shrine: Attachment CoffinSeat on its bier + ChainAnchor_1..3 on its posts (world CFrames computed here: the
	-- offline environment has no WorldCFrame)
	local seat: CFrame? = nil
	local space = 2.4 -- height of the clear coffin space the seat is the centre of (WP-G attribute SizeY)
	local anchors: { Vector3 } = {}
	local shrine: Instance? = nil
	for _, d in ipairs(ctx.Root:GetDescendants()) do
		if d:IsA("Attachment") and d.Name == "CoffinSeat" and d.Parent and d.Parent:IsA("BasePart") then
			seat = (d.Parent :: BasePart).CFrame * d.CFrame
			space = tonumber(d:GetAttribute("SizeY")) or space
			shrine = d.Parent.Parent
			break
		end
	end
	if shrine then
		for _, d in ipairs(shrine:GetDescendants()) do
			local k = d:IsA("Attachment") and tonumber(string.match(d.Name, "^ChainAnchor_(%d)$"))
			if k and d.Parent and d.Parent:IsA("BasePart") then
				anchors[k] = ((d.Parent :: BasePart).CFrame * d.CFrame).Position
			end
		end
	end
	local root = ctx.Model(D.Name)
	atomic(root)
	root:SetAttribute(A.Root, true)
	local fallback = seat == nil
	local S: CFrame = seat or (L.Square.CoffinShrine * CF(0, D.FallbackSeatY, 0))
	-- level, and lowered so the coffin rests on the bier (the seat is the centre of a slightly taller clear space)
	S = CFrame.fromMatrix(S.Position - V3(0, math.max(0, space - D.Height) / 2, 0), S.XVector, V3(0, 1, 0), S.XVector:Cross(V3(0, 1, 0)))
	local function at(cf: CFrame): CFrame
		return S * cf
	end
	local function wp(v: Vector3): Vector3
		return S * v
	end
	for k = 1, 3 do
		if not anchors[k] then
			anchors[k] = wp(D.FallbackAnchors[k])
		end
	end
	pcall(function()
		root:SetAttribute(A.Seat, S)
	end)
	ctx.Note(fallback and "BlackCoffin: no CoffinSeat attachment, seated on UnderyardLayout.Square.CoffinShrine (own bier)"
		or "BlackCoffin: seated on the shrine's CoffinSeat")

	local pivot = make(root, "Part", "CoffinPivot", V3(1, 1, 1), S, INK, M.SmoothPlastic, { Transparency = 1 })
	root.PrimaryPart = pivot

	-------------------------------------------------------------------------------------------------------- outline
	local HALF_H = D.Height / 2 -- 1.1: seat at the centre of the coffin volume
	local BOTTOM = -HALF_H
	local JOINT = HALF_H - D.LidHeight -- body top / lid bottom (.6)
	local TOP = HALF_H -- 1.1
	local hw, hh, hf = D.Width / 2, D.HeadWidth / 2, D.FootWidth / 2
	local zH, zS, zF = D.Length / 2, D.Shoulder, -D.Length / 2
	-- the outline (outer wall faces) counter-clockwise seen from above, starting at the foot's right corner
	local function outline(grow: number): { Vector3 }
		local g = grow
		return {
			V3(hf + g, 0, zF - g), V3(hw + g, 0, zS), V3(hh + g, 0, zH + g), V3(-hh - g, 0, zH + g), V3(-hw - g, 0, zS), V3(-hf - g, 0, zF - g),
		}
	end
	-- half width of the outline at z (outer wall face)
	local function halfAt(z: number): number
		if z >= zS then
			return hw + (hh - hw) * (z - zS) / (zH - zS)
		end
		return hf + (hw - hf) * (z - zF) / (zS - zF)
	end
	-- each edge of a polygon: a, b, outward normal (horizontal), length
	local function edges(poly: { Vector3 }): { any }
		local out = {}
		for i = 1, #poly do
			local a, b = poly[i], poly[i % #poly + 1]
			local d = b - a
			local n = V3(d.Z, 0, -d.X).Unit -- right of the direction = outward for a counter-clockwise polygon
			if n:Dot((a + b) / 2) < 0 then
				n = -n
			end
			table.insert(out, { A = a, B = b, N = n, Len = d.Magnitude })
		end
		return out
	end
	-- a flat hexagonal slab (union of a centre box and four bands along the slanted edges) between y0 and y1
	local function slab(parent: Instance, name: string, grow: number, y0: number, y1: number, color: Color3, material: Enum.Material,
		opts: { [string]: any }?)
		local o = opts or {}
		local poly = outline(grow)
		local t = y1 - y0
		local yc = (y0 + y1) / 2
		local minHalf = hf + grow
		local list = {}
		table.insert(list, make(parent, "Part", name, V3(minHalf * 2, t, (zH - zF) + grow * 2), at(CF(0, yc, (zH + zF) / 2)), color,
			material, o))
		local band = math.min((hw - hf) + .06, minHalf * 2 - .02) -- covers the gap to the centre box, never past the far edge
		for i, e in ipairs(edges(poly)) do
			if i ~= 3 and i ~= 6 then -- the head and foot edges lie inside the centre box
				local mid = (e.A + e.B) / 2 - e.N * band / 2
				local cf = frame(V3(mid.X, yc, mid.Z), e.N)
				table.insert(list, make(parent, "Part", name, V3(band, t, e.Len), at(cf), color, material, o))
			end
		end
		return list
	end

	-------------------------------------------------------------------------------------------------------- the body
	local body = model(root, "Body")
	local bodyH = JOINT - BOTTOM -- 1.7
	local ring = edges(outline(0))
	for i, e in ipairs(ring) do
		local mid = (e.A + e.B) / 2 - e.N * D.Wall / 2
		make(body, "Part", "Wall", V3(D.Wall, bodyH - .02, e.Len + .04), at(frame(V3(mid.X, BOTTOM + bodyH / 2, mid.Z), e.N)), LACQUER, M.SmoothPlastic,
			{ Reflectance = .06, Shadow = true })
		-- a recessed panel on every wall (a slightly lighter lacquer inset) and a thin silver bead around it
		local inset = math.max(.4, e.Len - .7)
		local pmid = (e.A + e.B) / 2 + e.N * .012
		make(body, "Part", "WallPanel", V3(.03, bodyH - .62, inset), at(frame(V3(pmid.X, BOTTOM + bodyH / 2 + .02, pmid.Z), e.N)), LACQUER2,
			M.SmoothPlastic, { Reflectance = .1 })
		for _, dy in ipairs({ -(bodyH - .62) / 2 - .03, (bodyH - .62) / 2 + .03 }) do
			make(body, "Part", "PanelBead", V3(.04, .05, inset + .06), at(frame(V3(pmid.X, BOTTOM + bodyH / 2 + .02 + dy, pmid.Z), e.N)),
				SILVER_D, M.Metal)
		end
		-- bar handles on the long sides (two per lower side, one per upper side)
		local handles = (i == 1 or i == 5) and { .3, .7 } or ((i == 2 or i == 4) and { .5 } or {})
		for _, s in ipairs(handles) do
			local hp = e.A:Lerp(e.B, s) + e.N * .16
			local hcf = at(frame(V3(hp.X, BOTTOM + .78, hp.Z), e.N))
			make(body, "Part", "HandleBar", V3(.09, .09, .8), hcf, SILVER, M.Metal)
			for _, sz in ipairs({ -.36, .36 }) do
				make(body, "Part", "HandleMount", V3(.18, .14, .1), hcf * CF(-.06, 0, sz), SILVER_D, M.Metal)
			end
		end
	end
	-- corner posts (round over the joints) with silver caps top and bottom
	for _, v in ipairs(outline(0)) do
		local c = v - V3(v.X, 0, 0).Unit * .04
		make(body, "Part", "CornerPost", V3(bodyH - .02, .3, .3), at(CF(c.X, BOTTOM + bodyH / 2, v.Z) * ANG(0, 0, PI / 2)), LACQUER, M.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder, Reflectance = .06 })
		for _, y in ipairs({ BOTTOM + .2, JOINT - .1 }) do
			make(body, "Part", "CornerCap", V3(.2, .36, .36), at(CF(c.X, y, v.Z) * ANG(0, 0, PI / 2)), SILVER_D, M.Metal,
				{ Shape = Enum.PartType.Cylinder })
		end
	end
	-- the plinth (a wider black base with a silver lip) and the rim trim under the lid joint
	slab(body, "Plinth", .1, BOTTOM - .02, BOTTOM + .16, INK, M.SmoothPlastic, { Shadow = true })
	for _, e in ipairs(edges(outline(.11))) do
		local mid = (e.A + e.B) / 2
		make(body, "Part", "PlinthLip", V3(.04, .05, e.Len), at(frame(V3(mid.X, BOTTOM + .14, mid.Z), e.N)), SILVER_D, M.Metal)
	end
	for _, e in ipairs(edges(outline(.015))) do
		local mid = (e.A + e.B) / 2
		make(body, "Part", "RimTrim", V3(.05, .1, e.Len + .02), at(frame(V3(mid.X, JOINT - .16, mid.Z), e.N)), SILVER, M.Metal)
	end
	-- inside: the satin floor (bands following the taper), the quilted lining walls, the pillow at the head
	for k = 0, 3 do
		local z0 = zF + D.Wall + k * (D.Length - 2 * D.Wall) / 4
		local z1 = z0 + (D.Length - 2 * D.Wall) / 4
		local half = math.min(halfAt(z0), halfAt(z1)) - D.Wall - .02
		make(body, "Part", "Lining", V3(half * 2, .12, z1 - z0 + .02), at(CF(0, BOTTOM + .24, (z0 + z1) / 2)), SATIN, M.Fabric)
	end
	for _, e in ipairs(edges(outline(-D.Wall - .01))) do
		local mid = (e.A + e.B) / 2 - e.N * .03
		make(body, "Part", "LiningWall", V3(.06, bodyH - .5, math.max(.2, e.Len - .12)), at(frame(V3(mid.X, BOTTOM + .3 + (bodyH - .5) / 2, mid.Z), e.N)),
			SATIN_D, M.Fabric)
		-- quilting: two buttons per wall
		for _, s in ipairs({ .3, .7 }) do
			local bp = e.A:Lerp(e.B, s) - e.N * .07
			make(body, "Part", "LiningButton", V3(.12, .12, .12), at(CF(bp.X, BOTTOM + .95, bp.Z)), RUNE:Lerp(SATIN, .5), M.Fabric,
				{ Shape = Enum.PartType.Ball })
		end
	end
	make(body, "Part", "Pillow", V3(1.7, .36, .95), at(CF(0, BOTTOM + .48, zH - D.Wall - .62)), C3(70, 30, 92), M.Fabric)
	make(body, "Part", "PillowSeam", V3(1.74, .04, .99), at(CF(0, BOTTOM + .48, zH - D.Wall - .62)), C3(110, 60, 140), M.Fabric)
	-- the solid volume players stand against (visual parts never collide, the lid moves on clients only)
	make(root, "Part", "CoffinCollider", V3(D.Width - .1, D.Height, D.Length), S, INK, M.SmoothPlastic, { Transparency = 1, Collide = true })

	-------------------------------------------------------------------------------------------------------- runes
	-- glyphs as bar segments in a unit square (u across, v up): angular "bell" runes of the Underyard
	local GLYPHS = {
		{ { 0, 0, 0, 1 }, { 0, .7, .6, 1 }, { 0, .35, .6, .65 } },
		{ { .1, 0, .5, 1 }, { .5, 1, .9, 0 }, { .25, .4, .75, .4 } },
		{ { .5, 0, .5, 1 }, { .1, .75, .9, .75 }, { .2, .2, .8, .45 } },
		{ { .1, 0, .1, .8 }, { .1, .8, .9, .55 }, { .9, .55, .1, .3 } },
		{ { .5, 0, .5, .7 }, { .5, .7, .1, 1 }, { .5, .7, .9, 1 } },
		{ { .1, .2, .5, 1 }, { .5, 1, .9, .2 }, { .1, .2, .9, .2 } },
	}
	local runeCount = 0
	-- a bar lying on a surface (normal n) from a to b: Z along the bar, Y = the normal, `w` wide, `t` thick
	local function surfaceBar(parent: Instance, name: string, a: Vector3, b: Vector3, n: Vector3, w: number, t: number, color: Color3,
		material: Enum.Material, opts: { [string]: any }?): BasePart
		local z = (b - a).Unit
		local y = (n - z * n:Dot(z)).Unit
		local x = y:Cross(z)
		local cf = CFrame.fromMatrix((a + b) / 2 + y * t / 2, x, y, z)
		return make(parent, "Part", name, V3(w, t, (b - a).Magnitude + w), at(cf), color, material, opts)
	end
	-- place glyph g with its unit square mapped by `map(u, v) -> seat-local Vector3` (on the surface), normal `n`
	local function glyph(parent: Instance, g: number, map: (number, number) -> Vector3, n: Vector3, w: number)
		for _, seg in ipairs(GLYPHS[(g - 1) % #GLYPHS + 1]) do
			local a, b = map(seg[1], seg[2]), map(seg[3], seg[4])
			if (b - a).Magnitude > .02 then
				surfaceBar(parent, "Rune", a, b, n, w, .03, RUNE, M.Neon, { Transparency = .3, Attrs = { [A.Rune] = true } })
				runeCount += 1
			end
		end
	end
	-- side runes: one glyph on each wall panel
	for i, e in ipairs(ring) do
		local size = math.min(.62, e.Len * .32)
		local centre = (e.A + e.B) / 2 + e.N * .028
		local dir = (e.B - e.A).Unit
		glyph(body, i, function(u, v)
			return centre + dir * (u - .5) * size * .8 + V3(0, BOTTOM + bodyH / 2 + .02 + (v - .5) * size, 0)
		end, e.N, .07)
	end

	-------------------------------------------------------------------------------------------------------- seam light
	local seams = model(root, "Seams")
	local function seam(name: string, size: Vector3, cf: CFrame, order: number)
		make(seams, "Part", name, size, at(cf), rgb(CC.Colors[6]), M.Neon, { Transparency = 1, Attrs = { [A.Seam] = order } })
	end
	-- the lid joint all round (lights first)
	for _, e in ipairs(edges(outline(.045))) do
		local mid = (e.A + e.B) / 2
		seam("SeamJoint", V3(.06, .08, e.Len + .06), frame(V3(mid.X, JOINT - .03, mid.Z), e.N), 1)
	end
	-- the corner seams down every post
	for _, v in ipairs(outline(.12)) do
		seam("SeamCorner", V3(bodyH - .5, .05, .05), CF(v.X, BOTTOM + bodyH / 2 + .1, v.Z) * ANG(0, 0, PI / 2), 2)
	end
	-- cracks spreading down the long walls (zigzags from the joint)
	for i, e in ipairs(ring) do
		if e.Len > 1.6 then
			local dir = (e.B - e.A).Unit
			for _, s in ipairs((i == 1 or i == 5) and { .28, .72 } or { .5 }) do
				local p = e.A:Lerp(e.B, s) + e.N * .05
				local y = JOINT - .02
				local pts = { V3(p.X, y, p.Z) }
				for k = 1, 3 do
					local off = (k % 2 == 1 and 1 or -1) * rng:NextNumber(.12, .26)
					p = p + dir * off
					y -= rng:NextNumber(.22, .36)
					table.insert(pts, V3(p.X, y, p.Z))
				end
				for k = 1, #pts - 1 do
					local cf = along(pts[k], pts[k + 1])
					make(seams, "Part", "SeamCrack", V3(.045, .045, (pts[k + 1] - pts[k]).Magnitude + .04), at(cf), rgb(CC.Colors[6]), M.Neon,
						{ Transparency = 1, Attrs = { [A.Seam] = 2 + k } })
				end
			end
		end
	end
	-- the glow inside (seen when the lid is open) + its light
	local inner = model(root, "Inner")
	local glow = make(inner, "Part", "InnerGlow", V3(hf * 2 - .5, .06, D.Length - 1.4), at(CF(0, BOTTOM + .32, .1)), rgb(CC.Colors[6]), M.Neon,
		{ Transparency = 1, Attrs = { [A.Inner] = true } })
	make(inner, "Part", "InnerHaze", V3(hf * 2 - .3, .9, D.Length - 1.2), at(CF(0, BOTTOM + .8, .1)), rgb(CC.Colors[6]), M.ForceField,
		{ Transparency = 1, Attrs = { [A.Inner] = true } })
	local light = Instance.new("PointLight")
	light.Name = "InnerLight"
	light.Color = rgb(CC.Colors[6])
	light.Range = 18
	light.Brightness = 3
	light.Shadows = false
	light.Enabled = false
	light:SetAttribute(A.Light, true)
	light.Parent = glow

	-------------------------------------------------------------------------------------------------------- the lid
	local lid = model(root, "Lid")
	atomic(lid)
	lid:SetAttribute(A.Lid, true)
	lid:SetAttribute("OpenAngle", D.OpenAngle)
	local hingeX = -hw - D.Overhang
	local hinge = make(lid, "Part", "LidHinge", V3(.2, .2, .2), at(CF(hingeX, JOINT, 0)), INK, M.SmoothPlastic, { Transparency = 1 })
	lid.PrimaryPart = hinge
	slab(lid, "LidSlab", D.Overhang, JOINT, JOINT + .3, LACQUER, M.SmoothPlastic, { Reflectance = .08, Shadow = true })
	slab(lid, "LidPanel", -.32, JOINT + .3, TOP - .02, LACQUER2, M.SmoothPlastic, { Reflectance = .12 })
	-- the satin underside (seen while the lid hangs open) with a quilted seam
	slab(lid, "LidLining", -D.Wall - .06, JOINT - .025, JOINT + .005, SATIN_D, M.Fabric)
	slab(lid, "LidLiningQuilt", -D.Wall - .5, JOINT - .04, JOINT - .02, SATIN, M.Fabric)
	-- bevel: the panel's silver edge bead and the slab's lip
	for _, e in ipairs(edges(outline(-.3))) do
		local mid = (e.A + e.B) / 2
		make(lid, "Part", "PanelBead", V3(.06, .06, e.Len), at(frame(V3(mid.X, JOINT + .33, mid.Z), e.N)), SILVER_D, M.Metal)
	end
	for _, e in ipairs(edges(outline(D.Overhang + .01))) do
		local mid = (e.A + e.B) / 2
		make(lid, "Part", "LidLip", V3(.04, .08, e.Len + .02), at(frame(V3(mid.X, JOINT + .15, mid.Z), e.N)), SILVER_D, M.Metal)
	end
	-- the crest at the head end: a silver crescent moon (a disc with a black disc over it) and a paw beneath
	local crest = V3(0, TOP + .01, zH - 1.75)
	make(lid, "Part", "CrestMoon", V3(.05, 1.1, 1.1), at(CF(crest) * ANG(0, 0, PI / 2)), SILVER, M.Metal, { Shape = Enum.PartType.Cylinder })
	make(lid, "Part", "CrestMoonShadow", V3(.06, .96, .96), at(CF(crest + V3(.22, .005, .18)) * ANG(0, 0, PI / 2)), LACQUER2, M.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder })
	local paw = V3(0, TOP + .01, zH - 3.0)
	make(lid, "Part", "CrestPaw", V3(.05, .5, .44), at(CF(paw) * ANG(0, 0, PI / 2)), SILVER, M.Metal, { Shape = Enum.PartType.Cylinder })
	for _, toe in ipairs({ V3(-.27, 0, .3), V3(-.09, 0, .4), V3(.09, 0, .4), V3(.27, 0, .3) }) do
		make(lid, "Part", "CrestToe", V3(.05, .2, .2), at(CF(paw + toe) * ANG(0, 0, PI / 2)), SILVER, M.Metal, { Shape = Enum.PartType.Cylinder })
	end
	-- lid runes: a ring of glyphs round the panel
	local lidRunes = { { -.62, -2.6 }, { .62, -2.6 }, { -.72, -1.2 }, { .72, -1.2 }, { -.86, .3 }, { .86, .3 }, { -.6, 2.95 }, { .6, 2.95 } }
	for i, uv in ipairs(lidRunes) do
		local c = V3(uv[1], TOP - .02, uv[2])
		glyph(lid, i + 2, function(u, v)
			return c + V3((u - .5) * .34, 0, (v - .5) * .44)
		end, V3(0, 1, 0), .06)
	end
	-- the hinge knuckles at the shoulder
	for _, dz in ipairs({ -.45, .45 }) do
		make(lid, "Part", "HingeKnuckle", V3(.42, .16, .16), at(CF(hingeX + .02, JOINT + .02, zS + dz) * ANG(0, PI / 2, 0)), SILVER_D, M.Metal,
			{ Shape = Enum.PartType.Cylinder })
	end

	-------------------------------------------------------------------------------------------------------- padlock
	local lock = model(root, "Padlock")
	lock:SetAttribute(A.Padlock, true)
	local lockAt = V3(0, TOP + .38, -.75)
	make(lock, "Part", "PadlockBody", V3(.64, .56, .26), at(CF(lockAt)), IRON, M.CorrodedMetal, { Shadow = true })
	make(lock, "Part", "PadlockPlate", V3(.5, .42, .04), at(CF(lockAt + V3(0, 0, -.14))), SILVER_D, M.Metal)
	make(lock, "Part", "PadlockKeyhole", V3(.1, .18, .03), at(CF(lockAt + V3(0, -.04, -.165))), RUNE, M.Neon,
		{ Attrs = { [A.Rune] = true } })
	for _, sx in ipairs({ -1, 1 }) do
		make(lock, "Part", "PadlockShackle", V3(.09, .36, .09), at(CF(lockAt + V3(sx * .2, .44, 0))), SILVER_D, M.Metal)
		make(lock, "Part", "PadlockRivet", V3(.07, .07, .03), at(CF(lockAt + V3(sx * .18, .16, -.165))), SILVER, M.Metal)
	end
	make(lock, "Part", "PadlockShackle", V3(.49, .09, .09), at(CF(lockAt + V3(0, .62, 0))), SILVER_D, M.Metal)

	-------------------------------------------------------------------------------------------------------- chains
	-- from the shrine ring k over the lid's edge to the padlock; 4-bar links alternating flat / upright
	local lidTop = TOP + .07
	local ends = {
		{ V3(-halfAt(-1.0) - D.Overhang - .02, JOINT + .26, -1.0), V3(-.3, lidTop, -.78) },
		{ V3(halfAt(-1.0) + D.Overhang + .02, JOINT + .26, -1.0), V3(.3, lidTop, -.78) },
		{ V3(0, JOINT + .26, zH + D.Overhang + .02), V3(0, lidTop, -.5) },
	}
	local linkCount = 0
	for k = 1, 3 do
		local cm = model(root, "CoffinChain_" .. k)
		cm:SetAttribute(A.Chain, k)
		local a = S:PointToObjectSpace(anchors[k])
		local edge, finish = ends[k][1], ends[k][2]
		-- the path: a sagging curve from the ring up to the lid's edge, then flat across the lid to the padlock
		local pts = {}
		local mid = (a + edge) / 2 - V3(0, .32, 0)
		local n1 = math.max(4, math.floor((edge - a).Magnitude / .36 + .5))
		for i = 0, n1 do
			local t = i / n1
			table.insert(pts, a:Lerp(mid, t):Lerp(mid:Lerp(edge, t), t))
		end
		local n2 = math.max(2, math.floor((finish - edge).Magnitude / .36 + .5))
		local edgeTop = V3(edge.X * .97, lidTop, edge.Z * .985)
		for i = 1, n2 do
			table.insert(pts, edgeTop:Lerp(finish, (i - 1) / (n2 - 1)))
		end
		for i = 1, #pts - 1 do
			local p0, p1 = pts[i], pts[i + 1]
			if (p1 - p0).Magnitude > .05 then
				local cf = along(p0, p1) * ANG(0, 0, i % 2 == 0 and PI / 2 or 0)
				local len = math.max(.42, (p1 - p0).Magnitude + .1)
				local attrs = { [A.Link] = i }
				for _, sx in ipairs({ -.1, .1 }) do
					make(cm, "Part", "Link", V3(.06, .06, len), at(cf * CF(sx, 0, 0)), IRON, M.CorrodedMetal, { Attrs = attrs })
				end
				for _, sz in ipairs({ -len / 2 + .03, len / 2 - .03 }) do
					make(cm, "Part", "Link", V3(.26, .06, .06), at(cf * CF(0, 0, sz)), IRON, M.CorrodedMetal, { Attrs = attrs })
				end
				linkCount += 1
			end
		end
		cm:SetAttribute("Anchor", anchors[k])
	end

	-------------------------------------------------------------------------------------------------------- candles
	local candles = model(root, "Candles")
	candles:SetAttribute(A.Candle, true)
	local bierTop = BOTTOM - .02
	local clusters = { V3(-1.85, bierTop, zF + .45), V3(1.85, bierTop, zF + .45), V3(-1.98, bierTop, zH - .5), V3(1.98, bierTop, zH - .5) }
	for ci, c in ipairs(clusters) do
		make(candles, "Part", "CandleDish", V3(.08, .62, .62), at(CF(c + V3(0, .04, 0)) * ANG(0, 0, PI / 2)), IRON, M.CorrodedMetal,
			{ Shape = Enum.PartType.Cylinder })
		for k = 1, 3 do
			local a = (k - 1) * 2.1 + ci
			local r = k == 1 and 0 or .17
			local h = (k == 1 and .95 or .5) + rng:NextNumber(0, .25)
			local d = k == 1 and .22 or .17
			local base = c + V3(math.cos(a) * r, .08, math.sin(a) * r)
			make(candles, "Part", "CandleWax", V3(h, d, d), at(CF(base + V3(0, h / 2, 0)) * ANG(0, 0, PI / 2)), WAX:Lerp(C3(196, 182, 150), rng:NextNumber(0, .35)),
				M.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
			make(candles, "Part", "CandleDrip", V3(.08, .2, .08), at(CF(base + V3(d * .45, h - .12, 0))), WAX, M.SmoothPlastic)
			local flame = make(candles, "Part", "CandleFlame", V3(.13, .26, .13), at(CF(base + V3(0, h + .15, 0))), FLAME, M.Neon,
				{ Attrs = { HwCandle = true } })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = flame
			if k == 1 and ci <= 2 then
				local l = Instance.new("PointLight")
				l.Color = FLAME
				l.Range = 9
				l.Brightness = .55
				l.Shadows = false
				l.Parent = flame
			end
		end
	end

	-------------------------------------------------------------------------------------------------------- fallback bier
	if fallback then
		local f = model(root, "FallbackShrine")
		f:SetAttribute(A.Fallback, true)
		local floorY = -D.FallbackSeatY
		make(f, "Part", "Dais", V3(9, .5, 11), at(CF(0, floorY + .25, 1.6)), C3(68, 64, 84), M.Slate, { Collide = true, Shadow = true })
		make(f, "Part", "Bier", V3(5.2, BOTTOM - floorY - .5, 7.5), at(CF(0, (floorY + .5 + BOTTOM) / 2, 0)), C3(140, 136, 158), M.Slate,
			{ Collide = true, Shadow = true })
		for k = 1, 3 do
			local a = S:PointToObjectSpace(anchors[k])
			make(f, "Part", "ChainPost", V3(a.Y - floorY - .2, .9, .9), at(CF(a.X, (a.Y + floorY + .3) / 2, a.Z) * ANG(0, 0, PI / 2)), IRON,
				M.CorrodedMetal, { Shape = Enum.PartType.Cylinder, Collide = true })
			make(f, "Part", "ChainRing", V3(.25, 1.4, 1.4), at(CF(a) * ANG(0, k == 3 and PI / 2 or 0, 0)), IRON, M.CorrodedMetal,
				{ Shape = Enum.PartType.Cylinder })
		end
	end

	local parts = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	root:SetAttribute("Parts", parts)
	ctx.Note(string.format("BlackCoffin: %d parts, %d chain links, %d rune bars", parts, linkCount, runeCount))
	return root
end

return BlackCoffin
