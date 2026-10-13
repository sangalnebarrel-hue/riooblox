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

local STYLES = { GOLDEN = true, RAINBOW = true, CURSED = true, GLITCHED = true }

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
