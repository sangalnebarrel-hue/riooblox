-- DiscoveryVisuals: the 3D look of a find everywhere it is shown (card viewports, the dig-pit
-- reveal, the yard showcase, reward machines). One model per find id, built from code by
-- DogEconomy.ItemModels (Forge recipes, cached templates, two levels of detail); ids without a
-- recipe fall back to the old voxel model in ReplicatedStorage.DiscoveryModels.
--
--   V.Clone(x, opts) -> Model?        x = {ItemId, Mutation?, WeightKg?}
--        opts.Lod = 0 (default, full detail) | 1 (silhouette for many distant copies)
--        opts.NoScale = true skips the weight scaling (viewports frame the model anyway)
--   V.Style(model, mutation)          restyles a find model; any mutation to any other, repeatable
--   V.Preview(parent, x, px, py, w, h) -> ViewportFrame   a framed, lit preview
--   V.Show(frame, x[, w, h])          swaps the find inside a preview frame (same frame, camera)
--   V.Bounds(model) -> (CFrame, Vector3)   box of the visible parts (works without Model APIs)
--   V.WeightScale(x) -> number        (WeightKg / BaseWeightKg)^(1/3), clamped to .25..ScaleCap
--   V.Rarity(itemId) -> string, V.RarityColor(rarity) -> Color3
--
-- Mutation styling (docs/ITEM_MODELS.md): accents are the parts a recipe marked with b:Accent
-- (the ItemAccent attribute). A model without any (old voxel models) uses its clearly more vivid
-- parts (at most a third, maybe none) and gets a stronger body tint, like the old all-over look.
--   GOLDEN   body lerps to gold, Foil on large parts and Metal on the rest; accents bright gold Neon
--   RAINBOW  accents Neon, one fixed hue each; body a slight pastel tint
--   CURSED   body darkened toward deep crimson / black; accents red Neon
--   GLITCHED body tinted magenta / cyan by turns; accents cyan Neon; one or two transparent
--            offset "ghost" copies of the largest accent (or the largest part)
--   HAUNTED / PUMPKINIZED / BLOOD MOON / ECLIPSED   the NIGHT OF THE BURIED MOON looks (see STYLES below)
--   NORMAL   the recipe's own look
-- The original colour / material of a styled part is kept in the BaseColor / BaseMaterial
-- attributes, ghosts carry ItemGhost; V.Style restores both before applying a new mutation.
local V = {}
local Replicated = game:GetService("ReplicatedStorage")
local Economy = script.Parent
local ItemModels = require(Economy:WaitForChild("ItemModels"))
local Items = require(Economy:WaitForChild("ItemDefinitions"))

local C = Color3.fromRGB
local GOLD = C(255, 196, 54)
local GOLD_GLOW = C(255, 222, 110)
local CURSED_BODY = C(46, 6, 14)
local CURSED_GLOW = C(255, 40, 62)
local GLITCH_MAGENTA = C(255, 64, 214)
local GLITCH_CYAN = C(50, 240, 255)
local BLACK = Color3.new(0, 0, 0)

-- Same colours as Kit.Theme.ItemRarity (Kit is client UI; this module also runs on the server).
V.RarityColors = {
	Common = C(170, 190, 205),
	Uncommon = C(125, 219, 48),
	Rare = C(38, 164, 243),
	Epic = C(161, 103, 242),
	Legendary = C(249, 180, 35),
	Secret = C(230, 115, 245),
}
V.RarityRank = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Secret = 6 }

local rarityTable: any = nil
-- Item rarity by the ItemValueConfig.Rarity thresholds (the same rule as ItemValuation).
function V.Rarity(itemId: string?): string
	local d = itemId and Items[itemId]
	if type(d) ~= "table" then
		return "Common"
	end
	if d.Class == "Secret" then
		return "Secret"
	end
	if rarityTable == nil then
		local module = Replicated:FindFirstChild("ItemValueConfig")
		local ok, config = pcall(function()
			return module and require(module :: any)
		end)
		rarityTable = ok and type(config) == "table" and config.Rarity or false
	end
	for _, row in rarityTable or {} do
		if (tonumber(d.BaseDropChance) or 1) <= row.MaxChance then
			return row.Name
		end
	end
	return "Common"
end

function V.RarityColor(rarity: string?): Color3
	return (rarity and V.RarityColors[rarity]) or V.RarityColors.Common
end

-- Model scale of a find of this weight (1 = base weight).
function V.WeightScale(x: any): number
	local d = type(x) == "table" and Items[x.ItemId]
	if type(d) ~= "table" or type(d.BaseWeightKg) ~= "number" or d.BaseWeightKg <= 0 then
		return 1
	end
	local w = tonumber(x.WeightKg)
	if not w or w ~= w or w <= 0 or w == math.huge then
		w = d.BaseWeightKg
	end
	return math.clamp((w / d.BaseWeightKg) ^ (1 / 3), 0.25, math.max(0.25, tonumber(d.ScaleCap) or 8))
end

-- Box (centre frame, size) of the visible parts; ghosts and the invisible Root included only
-- when visible. Pure CFrame maths, so it also works in Lune tests.
function V.Bounds(model: Instance): (CFrame, Vector3)
	local lo, hi
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ext = Vector3.new(
				math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
				math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
				math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
			)
			local c = cf.Position
			lo = lo and lo:Min(c - ext) or (c - ext)
			hi = hi and hi:Max(c + ext) or (c + ext)
		end
	end
	if not lo then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end

-- Scales a model about its pivot. Model:ScaleTo in the engine; a plain part transform where the
-- API does not exist (Lune tests).
local function scaleModel(model: Model, s: number)
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * s)
	end)
	if ok then
		return
	end
	local root = model.PrimaryPart
	local pivot = root and root.CFrame or CFrame.new()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(p.CFrame)
			p.Size = p.Size * s
			p.CFrame = pivot * (rel - rel.Position + rel.Position * s)
		end
	end
end

-- STYLE -------------------------------------------------------------------------------------------

local function vivid(color: Color3): number
	local _, s, v = color:ToHSV()
	return s * v
end

local function volume(p: BasePart): number
	return p.Size.X * p.Size.Y * p.Size.Z
end

local function restore(model: Instance): { BasePart }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("ItemGhost") then
				d:Destroy()
			else
				local base = d:GetAttribute("BaseColor")
				if typeof(base) == "Color3" then
					d.Color = base
				end
				local mat = d:GetAttribute("BaseMaterial")
				if type(mat) == "string" then
					local ok, value = pcall(function()
						return (Enum.Material :: any)[mat]
					end)
					if ok and value then
						d.Material = value
					end
				end
				if d.Transparency < 1 then
					table.insert(parts, d)
				end
			end
		end
	end
	return parts
end

local function remember(p: BasePart)
	if p:GetAttribute("BaseColor") == nil then
		p:SetAttribute("BaseColor", p.Color)
		p:SetAttribute("BaseMaterial", p.Material.Name)
	end
end

-- Splits the visible parts into body and accents. Without recipe accents (old voxel models) the
-- clearly more vivid parts stand in (at most a third, possibly none); the third result is true then.
local function split(parts: { BasePart }): ({ BasePart }, { BasePart }, boolean)
	local body, accents = {}, {}
	for _, p in parts do
		if p:GetAttribute("ItemAccent") then
			table.insert(accents, p)
		else
			table.insert(body, p)
		end
	end
	if #accents > 0 or #body == 0 then
		return body, accents, false
	end
	local values = {}
	for i, p in body do
		values[i] = vivid(p.Color)
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local threshold = math.max(0.45, sorted[math.ceil(#sorted / 2)] + 0.2)
	local order = {}
	for i = 1, #body do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if math.abs(values[a] - values[b]) > 1e-4 then
			return values[a] > values[b]
		end
		return a < b
	end)
	local chosen = {}
	for k = 1, math.max(1, math.floor(#body / 3)) do
		local i = order[k]
		if values[i] < threshold then
			break
		end
		chosen[i] = true
		table.insert(accents, body[i])
	end
	local rest = {}
	for i, p in body do
		if not chosen[i] then
			table.insert(rest, p)
		end
	end
	return rest, accents, true
end

local function addGhosts(model: Instance, accents: { BasePart }, body: { BasePart })
	local source, best = nil, -1
	local pool: { BasePart } = if #accents > 0 then accents else body
	for _, p in pool do
		local v = volume(p)
		if v > best then
			source, best = p, v
		end
	end
	if not source then
		return
	end
	local root = (model :: any).PrimaryPart
	local basis = root and root.CFrame or CFrame.new()
	local size = source.Size
	local step = math.clamp(math.max(size.X, size.Y, size.Z) * 0.08, 0.06, 0.25)
	local count = (model:GetAttribute("ItemModelLod") or 0) >= 1 and 1 or 2
	local looks = {
		{ Color = GLITCH_MAGENTA, Offset = Vector3.new(step, step * 0.35, 0) },
		{ Color = GLITCH_CYAN, Offset = Vector3.new(-step, -step * 0.25, 0) },
	}
	for i = 1, count do
		local look = looks[i]
		local ghost = source:Clone()
		for _, child in ghost:GetChildren() do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		ghost.Name = "GlitchGhost"
		ghost:SetAttribute("ItemAccent", nil)
		ghost:SetAttribute("BaseColor", nil)
		ghost:SetAttribute("BaseMaterial", nil)
		ghost:SetAttribute("ItemGhost", true)
		ghost.Color = look.Color
		ghost.Material = Enum.Material.Neon
		ghost.Transparency = source.Transparency > 0.5 and 0.85 or 0.6
		ghost.CastShadow = false
		ghost.CFrame = ghost.CFrame + basis:VectorToWorldSpace(look.Offset)
		if not source.Anchored then
			-- the model is already welded (e.g. a reveal): the ghost rides on its source part
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = source
			weld.Part1 = ghost
			weld.Parent = ghost
		end
		ghost.Parent = source.Parent
	end
end

-- NIGHT OF THE BURIED MOON mutations (ItemValueConfig.PostCapMutation): every look is colour + Neon + extra ItemGhost
-- parts, so it reads in ViewportFrames (no lights / particles there) and V.Style restores it like GLITCHED.
--   HAUNTED      pale ghost-green body, mint Neon accents, a translucent spirit copy rising out of the find + wisps
--   PUMPKINIZED  pumpkin-orange body, warm carved-glow accents, green vines creeping over it, a stem and leaves on top
--   BLOOD MOON   deep blood-red body, red Neon accents and glowing veins across the surface
--   ECLIPSED     near-black void body, violet Neon accents and cracks, a broken violet corona of void slivers behind it
local HAUNT_BODY = C(170, 242, 210)
local HAUNT_GLOW = C(120, 255, 196)
local HAUNT_SPIRIT = C(176, 255, 226)
local PUMPKIN_BODY = C(255, 122, 20)
local PUMPKIN_GLOW = C(255, 208, 74)
local VINE = C(58, 128, 36)
local VINE_LEAF = C(112, 200, 58)
local STEM = C(96, 120, 44)
local BLOOD_BODY = C(98, 6, 14)
local BLOOD_GLOW = C(255, 36, 42)
local ECLIPSE_BODY = C(12, 8, 20)
local ECLIPSE_GLOW = C(176, 70, 255)
local ECLIPSE_SHARD = C(28, 14, 44)
-- Beam / ring colours of the event mutations (EconomyVisuals reveals; Kit.Theme is client UI only).
V.MutationColors = { HAUNTED = C(150, 255, 214), PUMPKINIZED = C(255, 140, 30), ["BLOOD MOON"] = C(255, 40, 52), ECLIPSED = C(176, 70, 255) }
V.EventMutations = { HAUNTED = true, PUMPKINIZED = true, ["BLOOD MOON"] = true, ECLIPSED = true }

-- Direction from a find towards the preview camera (V.FrameCamera): surface details go on the faces it sees.
local VIEW = Vector3.new(0.42, 0.24, -0.87).Unit

local function seedOf(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483646
	end
	return h + 1
end

-- A fresh extra part that rides on `source` (welded when the model is already welded, e.g. a reveal).
local function ghostPart(source: BasePart, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = source.Anchored
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("ItemGhost", true)
	return p
end
local function mount(ghost: BasePart, source: BasePart)
	if not source.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = source
		weld.Part1 = ghost
		weld.Parent = ghost
	end
	ghost.Parent = source.Parent
end

local function shapeOf(p: BasePart): string
	if p:IsA("WedgePart") or p:IsA("CornerWedgePart") then
		return "Wedge"
	end
	if p:IsA("Part") then
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			return mesh.MeshType == Enum.MeshType.Sphere and "Ellipsoid" or "Other"
		end
		if p.Shape == Enum.PartType.Ball then
			return "Ball"
		elseif p.Shape == Enum.PartType.Cylinder then
			return "Cylinder"
		elseif p.Shape == Enum.PartType.Block then
			return "Block"
		end
	end
	return "Other"
end

-- The visible faces of a part as local frames: normal n, in-plane axes u / v, half sizes, depth, shape limits.
local AXES = {
	{ Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), "X", "Y", "Z" },
	{ Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), "X", "Z", "Y" },
	{ Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), "Z", "Y", "X" },
	{ Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), "Z", "Y", "X" },
	{ Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), "X", "Y", "Z" },
}
local function faces(p: BasePart): { any }
	local shape = shapeOf(p)
	if shape == "Wedge" or shape == "Other" then
		return {}
	end
	local out = {}
	for _, a in AXES do
		local n, u, v = a[1], a[2], a[3]
		local s = p.Size
		local w, h, d = (s :: any)[a[4]], (s :: any)[a[5]], (s :: any)[a[6]]
		local score = p.CFrame:VectorToWorldSpace(n):Dot(VIEW)
		if score > 0.05 and w > 0.12 and h > 0.12 then
			local limitU, limitV, along = 0.42, 0.42, nil
			if shape == "Ball" or shape == "Ellipsoid" then
				limitU, limitV = 0.22, 0.22
			elseif shape == "Cylinder" then
				if n.X ~= 0 then
					limitU, limitV = 0.25, 0.25 -- flat end disc
				else
					limitU, limitV, along = 0.4, 0.0, u -- curved side: only along the axis, on the centre line
				end
			end
			table.insert(out, { N = n, U = u, V = v, W = w, H = h, D = d, Score = score, LimitU = limitU, LimitV = limitV, Along = along, Curved = shape ~= "Block" })
		end
	end
	table.sort(out, function(x, y)
		return x.Score > y.Score
	end)
	return out
end

-- Thin glowing zig-zag lines (cracks, veins, vines) on the visible faces of the largest parts.
-- o = {Count, Color, Material, Transparency, Width, Seed, Steps, Leaf (colour: a leaf wedge at each end)}
local function addLines(model: Instance, pool: { BasePart }, o: any)
	local _, extentSize = V.Bounds(model)
	local extent = math.max(extentSize.X, extentSize.Y, extentSize.Z, 0.2)
	local rng = Random.new(o.Seed)
	local width = math.clamp(extent * (o.Width or 0.03), 0.035, 0.16)
	local sorted = table.clone(pool)
	table.sort(sorted, function(a, b)
		return volume(a) > volume(b)
	end)
	local made, tries = 0, 0
	while made < o.Count and tries < o.Count * 4 do
		tries += 1
		local source = sorted[((tries - 1) % math.min(#sorted, 4)) + 1]
		if not source then
			break
		end
		local list = faces(source)
		local f = list[math.min(#list, 1 + (rng:NextNumber() < 0.35 and 1 or 0))]
		if f then
			local hw, hh = f.W / 2, f.H / 2
			local x = rng:NextNumber(-1, 1) * hw * f.LimitU
			local y = rng:NextNumber(-1, 1) * hh * f.LimitV
			local angle = f.Along and (rng:NextNumber() < 0.5 and 0 or math.pi) or rng:NextNumber(0, 2 * math.pi)
			local steps = f.Curved and math.min(2, o.Steps or 3) or (o.Steps or 3)
			local reach = math.min(f.W, f.H) * (f.Curved and 0.3 or 0.42)
			if f.Along then
				reach = f.W * 0.32
			end
			local lastPos, lastDir
			for k = 1, steps do
				local len = math.clamp(reach * rng:NextNumber(0.45, 0.8), width * 2, extent * 0.5)
				if not f.Along and k > 1 then
					angle += rng:NextNumber(-0.75, 0.75)
				end
				local dir = f.U * math.cos(angle) + f.V * math.sin(angle)
				local nx = x + math.cos(angle) * len
				local ny = y + math.sin(angle) * len
				if math.abs(nx) > hw * 0.92 or math.abs(ny) > hh * 0.92 then
					break
				end
				local centre = f.U * ((x + nx) / 2) + f.V * ((y + ny) / 2) + f.N * (f.D / 2 + 0.015)
				local seg = ghostPart(source)
				seg.Name = o.Name or "EventMutationLine"
				seg.Size = Vector3.new(len + width * 0.6, width * (1 - (k - 1) * 0.18), 0.03)
				seg.CFrame = source.CFrame * CFrame.fromMatrix(centre, dir, f.N:Cross(dir))
				seg.Color = o.Color
				seg.Material = o.Material or Enum.Material.Neon
				seg.Transparency = o.Transparency or 0
				mount(seg, source)
				lastPos, lastDir = f.U * nx + f.V * ny + f.N * (f.D / 2 + 0.02), dir
				x, y = nx, ny
			end
			if o.Leaf and lastPos then
				local leaf = ghostPart(source, "Part")
				leaf.Name = "PumpkinVineLeaf"
				local size = math.clamp(width * 3.2, 0.1, 0.4)
				leaf.Size = Vector3.new(size, size * 0.62, 0.035)
				leaf.CFrame = source.CFrame * CFrame.fromMatrix(lastPos, lastDir, f.N:Cross(lastDir)) * CFrame.Angles(0, 0, math.rad(35))
				leaf.Color = o.Leaf
				leaf.Material = Enum.Material.SmoothPlastic
				mount(leaf, source)
			end
			made += 1
		end
	end
end

local function largest(list: { BasePart }, n: number): { BasePart }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		return volume(a) > volume(b)
	end)
	local out = {}
	for i = 1, math.min(n, #sorted) do
		out[i] = sorted[i]
	end
	return out
end

local function upOf(model: Instance): Vector3
	local root = (model :: any).PrimaryPart
	return root and root.CFrame.UpVector or Vector3.new(0, 1, 0)
end

-- HAUNTED: a translucent spirit copy of the biggest parts drifting up out of the find, plus two wisps.
local function addSpirit(model: Instance, parts: { BasePart }, lod: number)
	local box, size = V.Bounds(model)
	local up = upOf(model)
	local lift = math.max(size.Y * 0.26, 0.15)
	local drift = Vector3.new(-0.06, 0, 0.04) * math.max(size.X, size.Z)
	for i, source in largest(parts, lod >= 1 and 2 or 6) do
		local ghost = source:Clone()
		for _, child in ghost:GetChildren() do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		ghost.Name = "HauntedSpirit"
		ghost:SetAttribute("ItemAccent", nil)
		ghost:SetAttribute("BaseColor", nil)
		ghost:SetAttribute("BaseMaterial", nil)
		ghost:SetAttribute("ItemGhost", true)
		ghost.Color = HAUNT_SPIRIT
		ghost.Material = Enum.Material.Neon
		ghost.Transparency = i == 1 and 0.8 or 0.86
		ghost.CastShadow = false
		ghost.Size = ghost.Size * 1.03
		ghost.CFrame = ghost.CFrame + up * lift + drift
		mount(ghost, source)
	end
	if lod >= 1 then
		return
	end
	local anchor = largest(parts, 1)[1]
	if not anchor then
		return
	end
	local e = math.max(size.X, size.Y, size.Z)
	for k, off in { Vector3.new(0.32, 0.62, -0.2), Vector3.new(-0.36, 0.48, -0.26) } do
		local wisp = ghostPart(anchor)
		wisp.Name = "HauntedWisp"
		wisp.Shape = Enum.PartType.Ball
		local d = math.clamp(e * (k == 1 and 0.13 or 0.09), 0.08, 0.5)
		wisp.Size = Vector3.new(d, d, d)
		wisp.CFrame = CFrame.new(box.Position + Vector3.new(off.X * size.X, 0, off.Z * size.Z) + up * (off.Y * size.Y + lift))
		wisp.Color = HAUNT_GLOW
		wisp.Material = Enum.Material.Neon
		wisp.Transparency = 0.35
		mount(wisp, anchor)
	end
end

-- PUMPKINIZED: a curled stem with two leaves on the highest part.
local function addStem(model: Instance, parts: { BasePart })
	local top, best = nil, -math.huge
	for _, p in parts do
		local cf, h = p.CFrame, p.Size / 2
		local t = cf.Position.Y + math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
		if t > best then
			top, best = p, t
		end
	end
	if not top then
		return
	end
	local _, size = V.Bounds(model)
	local e = math.clamp(math.max(size.X, size.Y, size.Z), 0.4, 6)
	local up = upOf(model)
	local base = top.CFrame.Position + up * (best - top.CFrame.Position.Y - 0.02)
	local h = e * 0.2
	local d = math.clamp(e * 0.06, 0.06, 0.35)
	local stem = ghostPart(top)
	stem.Name = "PumpkinStem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(h, d, d)
	stem.CFrame = CFrame.new(base + up * (h / 2)) * CFrame.Angles(0, 0, math.rad(90 - 14))
	stem.Color = STEM
	stem.Material = Enum.Material.Wood
	mount(stem, top)
	local tip = ghostPart(top)
	tip.Name = "PumpkinStem"
	tip.Shape = Enum.PartType.Cylinder
	tip.Size = Vector3.new(h * 0.55, d * 0.8, d * 0.8)
	tip.CFrame = CFrame.new(base + up * (h * 1.05) + Vector3.new(-h * 0.22, 0, 0)) * CFrame.Angles(0, 0, math.rad(90 + 48))
	tip.Color = STEM
	tip.Material = Enum.Material.Wood
	mount(tip, top)
	for k, side in { 1, -1 } do
		local leaf = ghostPart(top)
		leaf.Name = "PumpkinLeaf"
		leaf.Size = Vector3.new(e * 0.2, 0.04, e * 0.12)
		leaf.CFrame = CFrame.new(base + up * (h * (0.35 + k * 0.12)) + Vector3.new(side * e * 0.1, 0, -side * e * 0.03))
			* CFrame.Angles(math.rad(-18 * side), math.rad(30 * side), math.rad(22 * side))
		leaf.Color = VINE_LEAF
		leaf.Material = Enum.Material.SmoothPlastic
		mount(leaf, top)
	end
end

-- ECLIPSED: the black find in front of a glowing violet sun (two translucent Neon discs just behind it, facing the
-- preview camera) wearing a crescent corona (thick and bright at the upper left, thin and faint opposite), and void shards on the rim.
local function addCorona(model: Instance, parts: { BasePart }, lod: number)
	local anchor = largest(parts, 1)[1]
	if not anchor then
		return
	end
	local box, size = V.Bounds(model)
	local radius = math.max(size.X, size.Y, size.Z) * 0.55
	local back = math.max(size.X, size.Z) * 0.32 + 0.05
	local frame = CFrame.lookAt(box.Position - VIEW * back, box.Position + VIEW * 4)
	local rng = Random.new(seedOf(tostring(model:GetAttribute("ItemId") or model.Name)))
	local disc = ghostPart(anchor)
	disc.Name = "EclipseDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.04, radius * 1.9, radius * 1.9)
	disc.CFrame = frame * CFrame.new(0, 0, -0.02) * CFrame.Angles(0, math.pi / 2, 0)
	disc.Color = C(58, 18, 112)
	disc.Material = Enum.Material.Neon
	disc.Transparency = 0.5
	mount(disc, anchor)
	local core = ghostPart(anchor)
	core.Name = "EclipseDisc"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(0.04, radius * 1.45, radius * 1.45)
	core.CFrame = frame * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, math.pi / 2, 0)
	core.Color = C(132, 64, 230)
	core.Material = Enum.Material.Neon
	core.Transparency = 0.62
	mount(core, anchor)
	local n = lod >= 1 and 10 or 20
	local base = math.clamp(radius * 0.1, 0.05, 0.42)
	local peak = math.rad(130)
	local skip = { [rng:NextInteger(1, n)] = true, [rng:NextInteger(1, n)] = true }
	for i = 1, n do
		if not skip[i] then
			local a = (i - 0.5) / n * math.pi * 2
			local glow = ((math.cos(a - peak) + 1) / 2) ^ 1.6
			local r = radius * (0.97 + glow * 0.05)
			local sliver = ghostPart(anchor)
			sliver.Name = "EclipseCorona"
			sliver.Size = Vector3.new(2 * math.pi * r / n * 1.04, base * (0.3 + glow * 0.9), 0.04)
			sliver.CFrame = frame * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
			sliver.Color = ECLIPSE_GLOW:Lerp(C(236, 200, 255), glow * 0.55)
			sliver.Material = Enum.Material.Neon
			sliver.Transparency = 0.5 - glow * 0.5
			mount(sliver, anchor)
		end
	end
	if lod >= 1 then
		return
	end
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local shard = ghostPart(anchor)
		shard.Name = "EclipseShard"
		local d = math.clamp(radius * rng:NextNumber(0.1, 0.17), 0.06, 0.5)
		local r = radius * rng:NextNumber(1.12, 1.26)
		shard.Size = Vector3.new(d * 0.5, d, d * 0.3)
		shard.CFrame = frame * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0.05)
			* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
		shard.Color = ECLIPSE_SHARD
		shard.Material = Enum.Material.SmoothPlastic
		mount(shard, anchor)
		local edge = ghostPart(anchor)
		edge.Name = "EclipseShard"
		edge.Size = Vector3.new(d * 0.12, d * 0.9, d * 0.32)
		edge.CFrame = shard.CFrame * CFrame.new(d * 0.24, 0, 0)
		edge.Color = ECLIPSE_GLOW
		edge.Material = Enum.Material.Neon
		mount(edge, anchor)
	end
end

-- Recipes where glowing accents make up most of the find (crystals, potions) would turn into one big Neon blob:
-- only the smallest accents (about a third of the volume) keep the glow, the rest take the body tint.
local function balance(body: { BasePart }, accents: { BasePart }): ({ BasePart }, { BasePart })
	local total, glow = 0, 0
	for _, p in body do
		total += volume(p)
	end
	for _, p in accents do
		glow += volume(p)
	end
	total += glow
	if #accents == 0 or glow <= total * 0.45 then
		return body, accents
	end
	local sorted = table.clone(accents)
	table.sort(sorted, function(a, b)
		return volume(a) < volume(b)
	end)
	local keep, moved, sum = {}, table.clone(body), 0
	for _, p in sorted do
		if sum + volume(p) <= total * 0.34 or #keep == 0 then
			table.insert(keep, p)
			sum += volume(p)
		else
			table.insert(moved, p)
		end
	end
	return moved, keep
end

local STYLES = { GOLDEN = true, RAINBOW = true, CURSED = true, GLITCHED = true, HAUNTED = true, PUMPKINIZED = true, ["BLOOD MOON"] = true, ECLIPSED = true }

-- Restyles a find model for a mutation (NORMAL or unknown names restore the original look).
-- Safe on any model: recipe models, old voxel models, models without accents, empty models.
function V.Style(model: Instance?, mutation: string?)
	if not model then
		return
	end
	local name = string.upper(tostring(mutation or "NORMAL"))
	local parts = restore(model)
	if not STYLES[name] or #parts == 0 then
		model:SetAttribute("ItemMutation", "NORMAL")
		return
	end
	model:SetAttribute("ItemMutation", name)
	-- models without recipe accents get a stronger body tint so the mutation still reads
	local body, accents, plain = split(parts)
	for _, p in parts do
		remember(p)
	end
	if name == "GOLDEN" then
		local _, extentSize = V.Bounds(model)
		local extent = math.max(extentSize.X, extentSize.Y, extentSize.Z, 0.01)
		local maxVolume = 0
		for _, p in body do
			maxVolume = math.max(maxVolume, volume(p))
		end
		for _, p in body do
			p.Color = p.Color:Lerp(GOLD, 0.72)
			local m = p.Material
			if m ~= Enum.Material.Glass and m ~= Enum.Material.Neon and m ~= Enum.Material.ForceField then
				local large = volume(p) >= maxVolume * 0.3 and math.max(p.Size.X, p.Size.Y, p.Size.Z) >= extent * 0.25
				p.Material = large and Enum.Material.Foil or Enum.Material.Metal
			end
		end
		for _, p in accents do
			p.Color = GOLD_GLOW
			p.Material = Enum.Material.Neon
		end
	elseif name == "RAINBOW" then
		for i, p in body do
			local hue = (i * 0.137) % 1
			p.Color = if plain then p.Color:Lerp(Color3.fromHSV(hue, 0.7, 1), 0.55) else p.Color:Lerp(Color3.fromHSV(hue, 0.35, 1), 0.28)
		end
		for i, p in accents do
			p.Color = Color3.fromHSV((0.02 + (i - 1) * 0.618034) % 1, 0.78, 1)
			p.Material = Enum.Material.Neon
		end
	elseif name == "CURSED" then
		for _, p in body do
			p.Color = p.Color:Lerp(CURSED_BODY, 0.62):Lerp(BLACK, 0.12)
		end
		for _, p in accents do
			p.Color = CURSED_GLOW
			p.Material = Enum.Material.Neon
		end
	elseif name == "GLITCHED" then
		for i, p in body do
			p.Color = p.Color:Lerp(i % 2 == 0 and GLITCH_CYAN or GLITCH_MAGENTA, plain and 0.5 or 0.36)
		end
		for _, p in accents do
			p.Color = GLITCH_CYAN
			p.Material = Enum.Material.Neon
		end
		addGhosts(model, accents, body)
	elseif V.EventMutations[name] then
		local lod = model:GetAttribute("ItemModelLod") or 0
		local seed = seedOf(tostring(model:GetAttribute("ItemId") or model.Name) .. name)
		body, accents = balance(body, accents)
		local pool: { BasePart } = if #body > 0 then body else accents
		if name == "HAUNTED" then
			for _, p in body do
				p.Color = p.Color:Lerp(HAUNT_BODY, plain and 0.66 or 0.55)
			end
			for _, p in accents do
				p.Color = HAUNT_GLOW
				p.Material = Enum.Material.Neon
			end
			addSpirit(model, pool, lod)
		elseif name == "PUMPKINIZED" then
			for _, p in body do
				p.Color = p.Color:Lerp(PUMPKIN_BODY, plain and 0.74 or 0.64)
			end
			for _, p in accents do
				p.Color = PUMPKIN_GLOW
				p.Material = Enum.Material.Neon
			end
			addLines(model, pool, { Count = lod >= 1 and 2 or 4, Color = VINE, Material = Enum.Material.SmoothPlastic, Width = 0.034,
				Seed = seed, Steps = 3, Leaf = VINE_LEAF, Name = "PumpkinVine" })
			addStem(model, pool)
		elseif name == "BLOOD MOON" then
			for _, p in body do
				p.Color = p.Color:Lerp(BLOOD_BODY, plain and 0.74 or 0.66):Lerp(BLACK, 0.08)
			end
			for _, p in accents do
				p.Color = BLOOD_GLOW
				p.Material = Enum.Material.Neon
			end
			addLines(model, pool, { Count = lod >= 1 and 3 or 7, Color = BLOOD_GLOW, Width = 0.034, Seed = seed, Steps = 3, Name = "BloodMoonVein" })
		elseif name == "ECLIPSED" then
			for _, p in body do
				p.Color = p.Color:Lerp(ECLIPSE_BODY, plain and 0.9 or 0.86)
				if p.Material == Enum.Material.Foil or p.Material == Enum.Material.Neon then
					p.Material = Enum.Material.SmoothPlastic
				end
			end
			for _, p in accents do
				p.Color = ECLIPSE_GLOW
				p.Material = Enum.Material.Neon
			end
			addLines(model, pool, { Count = lod >= 1 and 2 or 5, Color = ECLIPSE_GLOW, Width = 0.03, Seed = seed, Steps = 3, Name = "EclipseCrack" })
			addCorona(model, pool, lod)
		end
	end
end

-- CLONE -------------------------------------------------------------------------------------------

local function legacySource(itemId: string): Instance?
	local folder = Replicated:FindFirstChild("DiscoveryModels") or Replicated:WaitForChild("DiscoveryModels", 5)
	local source = folder and folder:FindFirstChild(itemId)
	if source and source:IsA("Model") then
		return source
	end
	return nil
end

-- A ready-to-parent model of the find: recipe template clone (or the old model), mutation style,
-- weight scale. Every part is anchored and non-interactive. nil for unknown ids.
function V.Clone(x: any, opts: any?): Model?
	if type(x) ~= "table" or type(x.ItemId) ~= "string" then
		return nil
	end
	local lod = opts and tonumber(opts.Lod) or 0
	local model = ItemModels.Get(x.ItemId, lod)
	if model then
		local root = model.PrimaryPart
		if root then
			root.Size = Vector3.new(0.05, 0.05, 0.05) -- keeps GetBoundingBox on the visible parts
		end
	else
		local source = legacySource(x.ItemId)
		if not source then
			return nil
		end
		model = source:Clone() :: Model
		model:SetAttribute("ItemModelLegacy", true)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			elseif d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
				d:Destroy()
			end
		end
	end
	model:SetAttribute("ItemId", x.ItemId)
	V.Style(model, x.Mutation)
	if not (opts and opts.NoScale) then
		local scale = V.WeightScale(x)
		if math.abs(scale - 1) > 1e-3 then
			scaleModel(model, scale)
		end
	end
	return model
end

-- PREVIEW -----------------------------------------------------------------------------------------

V.PreviewFieldOfView = 34

-- Frames the camera on the model from the front-right, higher for flat finds, so the whole
-- box fits the frame (aspect = width / height).
function V.FrameCamera(camera: Camera, model: Instance, aspect: number)
	local box, size = V.Bounds(model)
	local flat = size.Y < 0.45 * math.max(size.X, size.Z)
	local pitch = math.rad(flat and 36 or 14)
	local yaw = math.rad(26)
	local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
	local look = CFrame.lookAt(Vector3.zero, -dir)
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local tanH = tanV * math.clamp(aspect, 0.2, 5)
	local half = size / 2
	local distance = 0.5
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local q = look:VectorToObjectSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				distance = math.max(distance, math.max(math.abs(q.X) / tanH, math.abs(q.Y) / tanV) + q.Z)
			end
		end
	end
	camera.CFrame = CFrame.lookAt(box.Position + dir * distance * 1.06, box.Position)
	camera.Focus = box
end

-- Puts the find x in a preview frame made by V.Preview (or any ViewportFrame): one model per
-- frame, replaced in place; the same find again is a no-op.
function V.Show(frame: ViewportFrame, x: any, w: number?, h: number?): ViewportFrame
	local key = type(x) == "table" and (tostring(x.ItemId) .. "|" .. string.upper(tostring(x.Mutation or "NORMAL"))) or ""
	local current = frame:FindFirstChild("Find")
	if current and frame:GetAttribute("PreviewKey") == key then
		return frame
	end
	frame:SetAttribute("PreviewKey", key)
	if current then
		current:Destroy()
	end
	local model = type(x) == "table" and V.Clone(x, { NoScale = true }) or nil
	if not model then
		return frame
	end
	model.Name = "Find"
	local camera = frame:FindFirstChildOfClass("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Name = "PreviewCamera"
		camera.FieldOfView = V.PreviewFieldOfView
		camera.Parent = frame
	end
	-- (pcall only for Lune tests, whose instance model lacks ViewportFrame.CurrentCamera)
	pcall(function()
		frame.CurrentCamera = camera
	end)
	local aw = w or frame.AbsoluteSize.X
	local ah = h or frame.AbsoluteSize.Y
	V.FrameCamera(camera :: Camera, model, (aw > 0 and ah > 0) and aw / ah or 1)
	model.Parent = frame
	return frame
end

-- A lit ViewportFrame showing the find (callers: Kit.Preview, PreviewRenderer.Item, screens).
function V.Preview(parent: Instance?, x: any, px: number?, py: number?, w: number?, h: number?): ViewportFrame
	local frame = Instance.new("ViewportFrame")
	frame.Name = "DiscoveryPreview"
	frame.Position = UDim2.fromOffset(px or 0, py or 0)
	frame.Size = UDim2.fromOffset(w or 100, h or 100)
	frame.BackgroundColor3 = C(13, 24, 39)
	frame.BorderSizePixel = 0
	-- key light from the front-left above the camera, a cool ambient so dark bodies keep their shape
	frame.Ambient = C(150, 148, 172)
	frame.LightColor = C(255, 247, 232)
	frame.LightDirection = Vector3.new(0.4, -0.85, 0.6)
	V.Show(frame, x, w, h)
	frame.Parent = parent
	return frame
end

return V
