-- Build-time builder kit for THE DEAD YARD (ServerStorage.HalloweenBuild.Kit). The builders in this folder are run
-- offline by the place build (hw/edits/deadyard.luau, through tools/sim.luau) and their output is SAVED in the place, so
-- the Dead Yard can be seen and edited in Studio. They are kept in ServerStorage for reference / rebuilding and never run
-- in a live server. House style (copied from the map installers): anchored parts, CanCollide/CanQuery/CastShadow only for
-- solid parts, CanTouch false, smooth surfaces, Fredoka One lettering.
local K = {}
K.C = Color3.fromRGB
local C = K.C

K.Palette = {
	Ink = C(18, 10, 28), Night = C(26, 22, 40), Navy = C(22, 32, 62), Ground = C(52, 46, 58), Mud = C(46, 38, 36),
	DeadGrass = C(70, 78, 52), Moss = C(62, 92, 58), Stone = C(104, 104, 118), StoneDark = C(70, 70, 84), StoneLight = C(140, 138, 150),
	Cobble = C(92, 86, 100), Slate = C(60, 62, 74), Bone = C(236, 226, 200), BoneDark = C(196, 182, 150), Wood = C(92, 64, 46),
	WoodDark = C(58, 40, 32), WoodOld = C(112, 92, 72), Rust = C(126, 70, 44), RustDark = C(84, 48, 36), Iron = C(52, 54, 62),
	Pumpkin = C(255, 128, 24), PumpkinDark = C(190, 80, 18), Stem = C(78, 96, 44), Neon = C(120, 255, 110), Toxic = C(150, 255, 70),
	Purple = C(122, 62, 200), Violet = C(176, 92, 240), DeepPurple = C(40, 16, 60), Blood = C(200, 30, 50), Ghost = C(170, 225, 255),
	Gold = C(255, 200, 70), Candle = C(255, 236, 196), Flame = C(255, 170, 60), Cream = C(255, 242, 208), Leaf = C(96, 60, 36),
}
local P = K.Palette
K.FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

local function apply(p: BasePart, solid: boolean?)
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

K.Stats = { Parts = 0, Lights = 0 }

function K.Model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function K.Folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- props: Solid (collide), Shadow, Transparency, Reflectance, Class ("Part"|"WedgePart"|"CornerWedgePart"), Shape, Attrs
function K.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, props: { [string]: any }?): BasePart
	props = props or {}
	local p = Instance.new(props.Class or "Part")
	p.Name = name
	if props.Shape then
		(p :: any).Shape = props.Shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color or P.Stone
	p.Material = material or Enum.Material.SmoothPlastic
	apply(p, props.Solid)
	if props.Shadow ~= nil then
		p.CastShadow = props.Shadow
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	for k, v in pairs(props.Attrs or {}) do
		p:SetAttribute(k, v)
	end
	p.Parent = parent
	K.Stats.Parts += 1
	return p
end

function K.Box(parent, name, size, cf, color, material, props)
	return K.Part(parent, name, size, cf, color, material, props)
end

function K.Wedge(parent, name, size, cf, color, material, props)
	props = props or {}
	props.Class = "WedgePart"
	return K.Part(parent, name, size, cf, color, material, props)
end

function K.Corner(parent, name, size, cf, color, material, props)
	props = props or {}
	props.Class = "CornerWedgePart"
	return K.Part(parent, name, size, cf, color, material, props)
end

function K.Ball(parent, name, d: number, cf: CFrame, color, material, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	return K.Part(parent, name, Vector3.new(d, d, d), cf, color, material, props)
end

-- cylinder standing along world/local Y (Roblox cylinders run along X, so it is rotated)
function K.CylY(parent, name, height: number, d: number, cf: CFrame, color, material, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return K.Part(parent, name, Vector3.new(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, props)
end

function K.CylX(parent, name, length: number, d: number, cf: CFrame, color, material, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return K.Part(parent, name, Vector3.new(length, d, d), cf, color, material, props)
end

function K.CylZ(parent, name, length: number, d: number, cf: CFrame, color, material, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return K.Part(parent, name, Vector3.new(length, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), color, material, props)
end

-- ellipsoid via SpecialMesh Sphere (pumpkin lobes, skulls, puddles)
function K.Ellipsoid(parent, name, size: Vector3, cf: CFrame, color, material, props)
	local p = K.Part(parent, name, size, cf, color, material, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- correct lookAt (Lune's CFrame.lookAt is broken; the sim env wraps CFrame, this is safe everywhere)
function K.Look(at: Vector3, target: Vector3, upHint: Vector3?): CFrame
	local look = target - at
	if look.Magnitude < 1e-6 then
		return CFrame.new(at)
	end
	look = look.Unit
	local up = upHint or Vector3.new(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, -1))
	end
	right = right.Unit
	return CFrame.fromMatrix(at, right, right:Cross(look).Unit, -look)
end

-- box spanning two points (planks, rails, bones, chains)
function K.Bar(parent, name, a: Vector3, b: Vector3, w: number, h: number, color, material, props)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	return K.Part(parent, name, Vector3.new(w, h, len), K.Look(mid, b), color, material, props)
end

-- cylinder spanning two points
function K.Rod(parent, name, a: Vector3, b: Vector3, d: number, color, material, props)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	return K.CylX(parent, name, len, d, K.Look(mid, b) * CFrame.Angles(0, math.pi / 2, 0), color, material, props)
end

function K.Light(part: BasePart, color: Color3, range: number?, brightness: number?, kind: string?): Light
	local l = Instance.new(kind or "PointLight")
	l.Color = color
	l.Range = range or 14
	l.Brightness = brightness or .8
	l.Shadows = false
	l.Parent = part
	K.Stats.Lights += 1
	return l
end

function K.Attach(part: BasePart, name: string, cf: CFrame?, attrs: { [string]: any }?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf or CFrame.new()
	for k, v in pairs(attrs or {}) do
		a:SetAttribute(k, v)
	end
	a.Parent = part
	return a
end

-- invisible marker part with an attachment (crow perches, fog points, ghost paths on open ground)
function K.Marker(parent: Instance, name: string, pos: Vector3, attrs: { [string]: any }?): Attachment
	local p = K.Part(parent, name .. "Marker", Vector3.new(.2, .2, .2), CFrame.new(pos), P.Ink, nil, { Transparency = 1 })
	return K.Attach(p, name, CFrame.new(), attrs)
end

-- SurfaceGui lettering on a part face (signs, plaques, tombstone engravings)
function K.Sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3?, opts: { [string]: any }?): SurfaceGui
	opts = opts or {}
	local g = Instance.new("SurfaceGui")
	g.Name = opts.Name or "Lettering"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = opts.PixelsPerStud or 20
	g.LightInfluence = opts.LightInfluence or 0
	g.Brightness = opts.Brightness or 1
	g.AlwaysOnTop = false
	g.MaxDistance = opts.MaxDistance or 400
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(opts.W or .92, opts.H or .84)
	t.Position = UDim2.fromScale((1 - (opts.W or .92)) / 2, (1 - (opts.H or .84)) / 2)
	t.FontFace = K.FONT
	t.TextScaled = true
	t.TextWrapped = true
	t.Text = text
	t.TextColor3 = color or P.Cream
	t.TextStrokeTransparency = opts.Stroke == false and 1 or .2
	t.TextStrokeColor3 = opts.StrokeColor or P.Ink
	if opts.Rotation then
		t.Rotation = opts.Rotation
	end
	if opts.Gradient then
		local gr = Instance.new("UIGradient")
		gr.Color = ColorSequence.new(opts.Gradient[1], opts.Gradient[2])
		gr.Rotation = 90
		gr.Parent = t
	end
	t.Parent = g
	g.Parent = part
	return g
end

function K.Rng(seed: number): Random
	return Random.new(seed)
end

-- uniform helpers for organic variation
function K.Jitter(rng: Random, amount: number): number
	return rng:NextNumber(-amount, amount)
end

function K.Count(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- mark an EXISTING place part as changed by the event (World.Disable restores it when the event is switched off)
function K.Remember(inst: Instance)
	if inst:GetAttribute("Halloween_Changed") then
		return
	end
	inst:SetAttribute("Halloween_Changed", true)
	pcall(function()
		inst:SetAttribute("Halloween_OriginalColor", (inst :: any).Color)
	end)
	if inst:IsA("BasePart") then
		inst:SetAttribute("Halloween_OriginalTransparency", inst.Transparency)
		inst:SetAttribute("Halloween_OriginalCanCollide", inst.CanCollide)
		inst:SetAttribute("Halloween_OriginalCanQuery", inst.CanQuery)
	end
	pcall(function()
		inst:SetAttribute("Halloween_OriginalEnabled", (inst :: any).Enabled)
	end)
end

function K.Hide(inst: Instance)
	for _, d in ipairs(inst:IsA("BasePart") and { inst } or inst:GetDescendants()) do
		if d:IsA("BasePart") then
			K.Remember(d)
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			K.Remember(d)
			d.Enabled = false
		end
	end
end

------------------------------------------------------------------------------------------------------------------
-- Common Halloween props (shared by every builder so the yard reads as one set)
------------------------------------------------------------------------------------------------------------------

-- jack-o'-lantern: ribbed lobes, stem, carved neon face (faces -Z of cf). size = diameter
function K.Pumpkin(parent: Instance, cf: CFrame, size: number, opts: { [string]: any }?): Model
	opts = opts or {}
	local m = K.Model(parent, opts.Name or "Pumpkin")
	local d = size
	local color = opts.Color or P.Pumpkin
	local lobes = opts.Lobes or 6
	for i = 1, lobes do
		local a = (i - 1) / lobes * math.pi * 2
		local off = Vector3.new(math.cos(a) * d * .17, 0, math.sin(a) * d * .17)
		K.Ellipsoid(m, "PumpkinLobe", Vector3.new(d * .62, d * .72, d * .62), cf * CFrame.new(off + Vector3.new(0, d * .36, 0)),
			i % 2 == 0 and color or color:Lerp(P.PumpkinDark, .25), Enum.Material.SmoothPlastic)
	end
	K.Ellipsoid(m, "PumpkinCore", Vector3.new(d * .8, d * .7, d * .8), cf * CFrame.new(0, d * .36, 0), color:Lerp(P.PumpkinDark, .1), Enum.Material.SmoothPlastic)
	K.CylY(m, "PumpkinStem", d * .22, d * .12, cf * CFrame.new(0, d * .76, 0) * CFrame.Angles(.18, 0, .12), opts.Stem or P.Stem, Enum.Material.Wood)
	if opts.Face ~= false then
		local glow = opts.Glow or P.Flame
		local z = -d * .41
		K.Wedge(m, "PumpkinEye", Vector3.new(.05, d * .16, d * .14), cf * CFrame.new(-d * .15, d * .45, z) * CFrame.Angles(0, math.pi / 2, 0), glow, Enum.Material.Neon)
		K.Wedge(m, "PumpkinEye", Vector3.new(.05, d * .16, d * .14), cf * CFrame.new(d * .15, d * .45, z) * CFrame.Angles(0, -math.pi / 2, 0), glow, Enum.Material.Neon)
		K.Part(m, "PumpkinMouth", Vector3.new(d * .4, d * .07, .05), cf * CFrame.new(0, d * .27, z - .01), glow, Enum.Material.Neon)
		for i = -1, 1, 2 do
			K.Part(m, "PumpkinTooth", Vector3.new(d * .07, d * .06, .06), cf * CFrame.new(i * d * .08, d * .315, z - .02), color, Enum.Material.SmoothPlastic)
		end
		if opts.Light ~= false then
			local core = K.Part(m, "PumpkinGlow", Vector3.new(.2, .2, .2), cf * CFrame.new(0, d * .4, 0), glow, Enum.Material.Neon, { Transparency = 1 })
			K.Light(core, glow, d * 3.2, .6)
		end
	end
	return m
end

-- iron lantern on a post or hanging: glass part gets HwLantern attribute (client flicker / flare)
function K.Lantern(parent: Instance, cf: CFrame, color: Color3, kind: string, opts: { [string]: any }?): Model
	opts = opts or {}
	local m = K.Model(parent, "HwLantern")
	local h = opts.Height or 0
	if h > 0 then
		K.CylY(m, "LanternPost", h, .45, cf * CFrame.new(0, h / 2, 0), P.Iron, Enum.Material.CorrodedMetal, { Solid = true })
		K.Part(m, "LanternArm", Vector3.new(1.6, .22, .22), cf * CFrame.new(.6, h - .3, 0), P.Iron, Enum.Material.CorrodedMetal)
	end
	local top = cf * CFrame.new(h > 0 and 1.3 or 0, h > 0 and h - 1.4 or 0, 0)
	K.Part(m, "LanternCap", Vector3.new(1.4, .3, 1.4), top * CFrame.new(0, 1.05, 0), P.Iron, Enum.Material.CorrodedMetal)
	K.Wedge(m, "LanternRoof", Vector3.new(1.4, .5, .7), top * CFrame.new(0, 1.45, -.35), P.Iron, Enum.Material.CorrodedMetal)
	K.Wedge(m, "LanternRoof", Vector3.new(1.4, .5, .7), top * CFrame.new(0, 1.45, .35) * CFrame.Angles(0, math.pi, 0), P.Iron, Enum.Material.CorrodedMetal)
	local glass = K.Part(m, "LanternGlass", Vector3.new(.95, 1.5, .95), top * CFrame.new(0, .15, 0), color, Enum.Material.Neon,
		{ Attrs = { HwLantern = kind } })
	for _, x in ipairs({ -.5, .5 }) do
		for _, z in ipairs({ -.5, .5 }) do
			K.Part(m, "LanternFrame", Vector3.new(.12, 1.7, .12), top * CFrame.new(x, .15, z), P.Iron, Enum.Material.CorrodedMetal)
		end
	end
	K.Part(m, "LanternBase", Vector3.new(1.2, .25, 1.2), top * CFrame.new(0, -.72, 0), P.Iron, Enum.Material.CorrodedMetal)
	K.Light(glass, color, opts.Range or 18, opts.Brightness or 1.1)
	return m
end

-- a small candle cluster on the ground / ledge (flames: HwCandle)
function K.Candles(parent: Instance, cf: CFrame, count: number, rng: Random, opts: { [string]: any }?): Model
	opts = opts or {}
	local m = K.Model(parent, "Candles")
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, opts.Spread or .9)
		local h = rng:NextNumber(.4, 1.2)
		local base = cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
		K.CylY(m, "CandleWax", h, rng:NextNumber(.22, .34), base * CFrame.new(0, h / 2, 0), P.Candle:Lerp(P.BoneDark, rng:NextNumber(0, .4)), Enum.Material.SmoothPlastic)
		local flame = K.Ellipsoid(m, "CandleFlame", Vector3.new(.16, .3, .16), base * CFrame.new(0, h + .17, 0), P.Flame, Enum.Material.Neon,
			{ Attrs = { HwCandle = true } })
		if i == 1 and opts.Light ~= false then
			K.Light(flame, P.Flame, opts.Range or 9, .55)
		end
	end
	return m
end

-- dead, crooked tree (branch recursion). Trunk base at cf.
function K.DeadTree(parent: Instance, cf: CFrame, height: number, rng: Random, opts: { [string]: any }?): Model
	opts = opts or {}
	local m = K.Model(parent, "DeadTree")
	local bark = opts.Color or C(58, 46, 44)
	local function branch(from: Vector3, dir: Vector3, len: number, thick: number, depth: number)
		local to = from + dir * len
		K.Rod(m, depth == 0 and "DeadTrunk" or "DeadBranch", from, to, thick, bark:Lerp(C(30, 24, 26), depth * .12), Enum.Material.Wood,
			{ Solid = depth == 0 })
		K.Ball(m, "DeadKnot", thick * 1.05, CFrame.new(to), bark, Enum.Material.Wood)
		if depth >= (opts.Depth or 3) then
			if rng:NextNumber() < .35 then
				m:SetAttribute("Perches", (m:GetAttribute("Perches") or 0) + 1)
				local mk = K.Part(m, "PerchPoint", Vector3.new(.2, .2, .2), CFrame.new(to), bark, nil, { Transparency = 1 })
				K.Attach(mk, "CrowPerch")
			end
			return
		end
		local n = depth == 0 and 3 or rng:NextInteger(2, 3)
		for _ = 1, n do
			local d2 = (dir + Vector3.new(rng:NextNumber(-.9, .9), rng:NextNumber(.05, .7), rng:NextNumber(-.9, .9))).Unit
			branch(to, d2, len * rng:NextNumber(.55, .72), thick * .62, depth + 1)
		end
	end
	local base = cf.Position
	K.Ellipsoid(m, "DeadRoots", Vector3.new(height * .28, height * .08, height * .28), CFrame.new(base + Vector3.new(0, .1, 0)), bark, Enum.Material.Wood)
	branch(base, (Vector3.new(rng:NextNumber(-.15, .15), 1, rng:NextNumber(-.15, .15))).Unit, height * .45, height * .09, 0)
	return m
end

-- tombstone with engraving (faces -Z of cf), style 1..4
function K.Tombstone(parent: Instance, cf: CFrame, style: number, rng: Random, text: string?): Model
	local m = K.Model(parent, "Tombstone")
	local stone = P.Stone:Lerp(P.StoneDark, rng:NextNumber(0, .6))
	local tilt = CFrame.Angles(rng:NextNumber(-.08, .08), 0, rng:NextNumber(-.1, .1))
	local w, h = rng:NextNumber(2.2, 3), rng:NextNumber(2.6, 3.8)
	local base = cf * tilt
	K.Part(m, "GraveBase", Vector3.new(w + .8, .45, 1.6), cf * CFrame.new(0, .22, 0), P.StoneDark, Enum.Material.Slate, { Solid = true })
	if style == 1 then
		local slab = K.Part(m, "GraveSlab", Vector3.new(w, h - w / 2, .55), base * CFrame.new(0, .45 + (h - w / 2) / 2, 0), stone, Enum.Material.Slate, { Solid = true })
		K.CylX(m, "GraveArch", .55, w, base * CFrame.new(0, .45 + h - w / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), stone, Enum.Material.Slate)
		if text then
			K.Sign(slab, Enum.NormalId.Front, text, P.BoneDark, { PixelsPerStud = 24, Stroke = false, H = .5 })
		end
	elseif style == 2 then
		K.Part(m, "GraveCross", Vector3.new(.55, h + .6, .55), base * CFrame.new(0, .45 + (h + .6) / 2, 0), stone, Enum.Material.Slate, { Solid = true })
		K.Part(m, "GraveCross", Vector3.new(w * .9, .55, .55), base * CFrame.new(0, .45 + h * .72, 0), stone, Enum.Material.Slate)
	elseif style == 3 then
		local slab = K.Part(m, "GraveSlab", Vector3.new(w, h, .6), base * CFrame.new(0, .45 + h / 2, 0), stone, Enum.Material.Slate, { Solid = true })
		K.Wedge(m, "GraveTop", Vector3.new(w, .7, .3), base * CFrame.new(0, .45 + h + .35, -.15), stone, Enum.Material.Slate)
		K.Wedge(m, "GraveTop", Vector3.new(w, .7, .3), base * CFrame.new(0, .45 + h + .35, .15) * CFrame.Angles(0, math.pi, 0), stone, Enum.Material.Slate)
		if text then
			K.Sign(slab, Enum.NormalId.Front, text, P.BoneDark, { PixelsPerStud = 24, Stroke = false, H = .5 })
		end
	else
		-- paw-print dog grave: small slab with a bone on top
		local slab = K.Part(m, "GraveSlab", Vector3.new(w * .9, h * .7, .5), base * CFrame.new(0, .45 + h * .35, 0), stone, Enum.Material.Slate, { Solid = true })
		K.Bone(m, base * CFrame.new(0, .45 + h * .7 + .25, 0), w * .8, P.Bone)
		K.Sign(slab, Enum.NormalId.Front, "🐾", P.BoneDark, { PixelsPerStud = 24, Stroke = false, H = .6 })
	end
	-- moss and a crack line for wear
	K.Part(m, "GraveMoss", Vector3.new(w * .6, .1, .3), base * CFrame.new(rng:NextNumber(-.3, .3), .52, -.2), P.Moss, Enum.Material.Grass)
	return m
end

-- cartoon dog bone (along X of cf)
function K.Bone(parent: Instance, cf: CFrame, length: number, color: Color3?): Model
	local m = K.Model(parent, "Bone")
	local col = color or P.Bone
	local t = length * .2
	K.CylX(m, "BoneShaft", length * .8, t, cf, col, Enum.Material.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		K.Ball(m, "BoneKnob", t * 1.25, cf * CFrame.new(s * length * .42, 0, t * .45), col, Enum.Material.SmoothPlastic)
		K.Ball(m, "BoneKnob", t * 1.25, cf * CFrame.new(s * length * .42, 0, -t * .45), col, Enum.Material.SmoothPlastic)
	end
	return m
end

-- hanging chain between two points (links alternate orientation)
function K.Chain(parent: Instance, a: Vector3, b: Vector3, sag: number, links: number?): Model
	local m = K.Model(parent, "Chain")
	local n = links or math.max(4, math.floor((b - a).Magnitude / .55))
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		local link = K.Bar(m, "ChainLink", prev, p, .14, .32, P.Iron, Enum.Material.CorrodedMetal)
		if i % 2 == 0 then
			link.CFrame = link.CFrame * CFrame.Angles(0, 0, math.pi / 2)
		end
		prev = p
	end
	return m
end

-- glowing mushrooms cluster
function K.Mushrooms(parent: Instance, cf: CFrame, count: number, rng: Random, color: Color3?): Model
	local m = K.Model(parent, "GlowShrooms")
	local col = color or P.Neon
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, .9)
		local h = rng:NextNumber(.3, .9)
		local base = cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(-.2, .2), 0, rng:NextNumber(-.2, .2))
		K.CylY(m, "ShroomStem", h, .14, base * CFrame.new(0, h / 2, 0), P.Cream, Enum.Material.SmoothPlastic)
		K.Ellipsoid(m, "ShroomCap", Vector3.new(h * .9, h * .4, h * .9), base * CFrame.new(0, h, 0), col, Enum.Material.Neon)
	end
	return m
end

return K
