-- NIGHT OF THE BURIED MOON: cosmetic pickaxe skins (ReplicatedStorage.Halloween.PickaxeSkins).
-- A skin is PRESENTATION ONLY: it swaps the model, the living motion, the swing style, the hit FX theme and the
-- sound kit of whatever pickaxe tier the player really owns. Every stat (Damage, Window, Circles, Crit*, Luck,
-- CoinBonus, Strength, Price, FX tier...) always comes from Config.Mining.Pickaxes[level]; the server rules never see
-- a skin (they only index M.Pickaxes[m.PickaxeLevel]).
-- Ownership: profile.Halloween.Skins (server). The equipped skin is the SERVER-written player attribute
-- `PickaxeSkin` (Halloween.Core.Sync after an ownership check; Actions "SkinEquip"). Event off => no skin.
--
-- API
--   Skins.List / Skins.ById / Skins.Order      the six skin defs (Id, Name, RU, Icon, Rarity, Theme, Swing, Sound,
--                                              Color, Inspect, Visual, Trait/TraitRU, Lore/LoreRU)
--   Skins.Resolve(def, skinId) -> def'         visual def for a REAL tier def: a cached clone with only the VISUAL
--                                              keys replaced (def itself when there is no / an unknown skin)
--   Skins.Of(player) -> skinId?                the player's equipped skin (validated id, nil when the event is off)
--   Skins.For(player, def) -> def'             = Resolve(def, Of(player))
--   Skins.Build(skinId | def, level?) -> Model a pickaxe Model exactly like MiningModels.Pickaxe builds them
--                                              (Handle, Kind/Theme/Level attrs, TrailA/B, PickAnim, PickBase...);
--                                              a def that is not a skin falls back to the stock builder
--   Skins.Register(ctx?)                       idempotent: wraps MiningModels.Pickaxe so the stock builder builds
--                                              skin defs too (server held model), adds the sound kits to
--                                              MiningAudio.Kits and, with the MiningClient ctx (client), the hit
--                                              themes / palettes to PickFX (needs PickFX's Themes/HitFX export) and
--                                              the living state machines to PickFX.LiveFX (LIVE_SPECS below)
--   Skins.CritText(theme) -> string?           themed crit stamp for MiningClient.Mine
--   Skins.Name(skin) -> string                 localized name (client)
--   Skins.Track(model) / Skins.Untrack(model)  client: living motion for an anchored UI preview (ViewportFrame) through
--                                              the MiningClient's PickFX (false until MiningClient registered)
--   Skins.Palettes                             theme -> {Color3...} (UI accents / circle colours of each skin)
-- Model conventions (see MiningModels): Handle along +Y (grip 1.4 below its centre), faces/eyes look along +Z,
-- striking ends along +-X, Kind names prefixed HW_ so no stock Kind-specific code ever matches them. Living motion
-- uses PickFX's generic MOTIONS / flags (PickAnim, PickJoint, PickPhase, PickAmp, PickPop, PickHang, PickPulse,
-- PickFlicker) plus, on the client, one live state machine per skin (PickFX.LiveFX[Kind]: lights, extra motion, draw /
-- inspect / idle / run effects; see LIVING STATE MACHINES). Every model is deterministic (seeded hash), so the
-- server's held model equals every client's preview.
local RS = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local Shared = nil
pcall(function() Shared = require(script.Parent:WaitForChild('Shared')) end)

local Skins = {}
local IS_CLIENT = RunService:IsClient()

---------------------------------------------------------------------------------------------------------------------
-- THE SIX SKINS
---------------------------------------------------------------------------------------------------------------------
-- Theme = Halloween hit theme (PickFX, registered by Register(ctx)); ThemeAlt = the stock theme used when PickFX
-- does not export its tables (older PickFX): the look degrades gracefully instead of falling back to Wood.
Skins.List = {
	{ Id = 'GraveShovel', Name = 'Grave Shovel', RU = 'Могильная Лопата', Icon = '🪦', Rarity = 'Epic',
		Theme = 'HW_Grave', ThemeAlt = 'Zombie', Swing = 'Chop', Sound = 'HW_Grave', Color = { 120, 255, 130 }, Inspect = true,
		Trait = 'Cosmetic · ghost-lit spade · coffin-nail rivets · skull pommel', TraitRU = 'Косметика · лопата с призрачным светом · гробовые гвозди · навершие-череп',
		Lore = 'The old gravedigger of the Dead Yard never put it down. Something in the blade still looks back at you.',
		LoreRU = 'Старый могильщик Мёртвого Двора никогда не выпускал её из рук. Что-то в лезвии до сих пор смотрит на тебя.',
		Visual = { Kind = 'HW_GraveShovel', Length = 4.4, Shaft = { 78, 60, 46 }, ShaftMaterial = 'Wood', Head = { 118, 114, 110 },
			Accent = { 120, 255, 130 }, Trim = { 58, 50, 46 }, Rust = { 150, 84, 46 }, Bone = { 228, 218, 190 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.0, 0 }, IconDist = 9.5 } },
	{ Id = 'BonePickaxe', Name = 'Bone Pickaxe', RU = 'Костяная Кирка', Icon = '🦴', Rarity = 'Legendary',
		Theme = 'HW_Bone', ThemeAlt = 'Clown', Swing = 'Clack', Sound = 'HW_Bone', Color = { 255, 176, 60 }, Inspect = true,
		Trait = 'Cosmetic · spine handle · femur pick · skull with burning eyes', TraitRU = 'Косметика · рукоять-позвоночник · кирка из бедренных костей · череп с горящими глазами',
		Lore = 'Somebody dug up a very good boy and gave him a job. He still wags his tail when you swing.',
		LoreRU = 'Кто-то выкопал очень хорошего пса и дал ему работу. Он до сих пор виляет хвостом, когда ты замахиваешься.',
		Visual = { Kind = 'HW_BonePickaxe', Length = 4.8, Shaft = { 222, 210, 182 }, ShaftMaterial = 'SmoothPlastic', Head = { 236, 226, 200 },
			Accent = { 255, 170, 50 }, Trim = { 92, 58, 40 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 2.9, 0 }, IconDist = 9.5 } },
	{ Id = 'PumpkinSmasher', Name = 'Pumpkin Smasher', RU = 'Тыквенный Крушитель', Icon = '🎃', Rarity = 'Legendary',
		Theme = 'HW_Pumpkin', ThemeAlt = 'Gummy', Swing = 'Smash', Sound = 'HW_Pumpkin', Color = { 255, 140, 30 }, Inspect = true,
		Trait = 'Cosmetic · jack-o\'-lantern maul · candle-lit grin · vine handle', TraitRU = 'Косметика · молот-тыква · ухмылка со свечой · рукоять из лозы',
		Lore = 'Carved on the night of the Buried Moon. The candle inside has never gone out, and the grin gets wider with every hit.',
		LoreRU = 'Вырезана в ночь Погребённой Луны. Свеча внутри ни разу не погасла, а ухмылка шире с каждым ударом.',
		Visual = { Kind = 'HW_PumpkinSmasher', Length = 4.6, Shaft = { 64, 52, 34 }, ShaftMaterial = 'Wood', Head = { 255, 128, 24 },
			Accent = { 255, 176, 40 }, Vine = { 74, 150, 56 }, Trim = { 86, 80, 84 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.0, 0 }, IconDist = 9 } },
	{ Id = 'GhostScythe', Name = 'Ghost Scythe', RU = 'Призрачная Коса', Icon = '👻', Rarity = 'Mythic',
		Theme = 'HW_Ghost', ThemeAlt = 'Anime', Swing = 'Reap', Sound = 'HW_Ghost', Color = { 140, 215, 255 }, Inspect = true,
		Trait = 'Cosmetic · a ghost bound into the blade · chains · circling wisps', TraitRU = 'Косметика · призрак, скованный в лезвии · цепи · кружащие огоньки',
		Lore = 'The ghost was chained to the blade a hundred years ago. It wails with every swing, but between you and me, it loves the job.',
		LoreRU = 'Призрака приковали к лезвию сто лет назад. Он воет при каждом взмахе, но, между нами, ему нравится эта работа.',
		Visual = { Kind = 'HW_GhostScythe', Length = 5.6, Shaft = { 112, 122, 136 }, ShaftMaterial = 'Wood', Head = { 150, 220, 255 },
			Accent = { 120, 205, 255 }, Trim = { 62, 70, 88 }, Cloth = { 200, 236, 255 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 1.25, 2.3, 0 }, IconDist = 10.2 } },
	{ Id = 'LivingCoffin', Name = 'Living Coffin', RU = 'Живой Гроб', Icon = '⚰️', Rarity = 'Mythic',
		Theme = 'HW_Coffin', ThemeAlt = 'Fate', Swing = 'Franken', Sound = 'HW_Coffin', Color = { 255, 96, 50 }, Inspect = true,
		Trait = 'Cosmetic · a hungry coffin · fanged lid snaps open on every hit · glowing maw', TraitRU = 'Косметика · голодный гроб · зубастая крышка клацает при каждом ударе · пылающая пасть',
		Lore = 'Somebody inside really wants to help you dig. Every hit lets them out a little more.',
		LoreRU = 'Кто-то внутри очень хочет помочь тебе копать. С каждым ударом он выбирается чуть больше.',
		Visual = { Kind = 'HW_LivingCoffin', Length = 5, Shaft = { 44, 30, 30 }, ShaftMaterial = 'Wood', Head = { 92, 46, 36 },
			Accent = { 255, 70, 40 }, Trim = { 62, 60, 66 }, Brass = { 206, 162, 84 }, Lining = { 60, 16, 22 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.1, 0 }, IconDist = 9.6 } },
	{ Id = 'SoulReaper', Name = 'Soul Reaper', RU = 'Жнец Душ', Icon = '💀', Rarity = 'Secret',
		Theme = 'HW_Soul', ThemeAlt = 'Fate', Swing = 'Reap', Sound = 'HW_Soul', Color = { 186, 90, 255 }, Inspect = true,
		Trait = 'Cosmetic · SECRET · Death\'s own scythe · orbiting soul orbs', TraitRU = 'Косметика · СЕКРЕТ · коса самой Смерти · кружащие души',
		Lore = 'Only those who exorcised the whole Dead Yard ever hold it. The souls circling the hood are the ones it has already collected.',
		LoreRU = 'Её держали лишь те, кто изгнал всех духов Мёртвого Двора. Души, кружащие у капюшона, — те, что она уже собрала.',
		Visual = { Kind = 'HW_SoulReaper', Length = 6, Shaft = { 26, 20, 34 }, ShaftMaterial = 'SmoothPlastic', Head = { 40, 34, 50 },
			Accent = { 186, 90, 255 }, Panel = { 64, 26, 112 }, Hood = { 34, 22, 46 }, Bone = { 232, 224, 204 },
			Polish = false, IconViewport = true, PreviewDist = 16, IconFocus = { 1.3, 2.6, 0 }, IconDist = 11 } },
}

Skins.ById = {}
Skins.Order = {}
for _, s in ipairs(Skins.List) do
	Skins.ById[s.Id] = s
	table.insert(Skins.Order, s.Id)
end

---------------------------------------------------------------------------------------------------------------------
-- RESOLVER (pure; the only door through which a skin reaches a pickaxe def)
---------------------------------------------------------------------------------------------------------------------
-- Keys a skin may replace. NEVER: Damage, Window, Circles, CritChance, CritMult, PerfectMult, ComboStep, ComboMax,
-- Luck, CoinBonus, Strength, Price, FX, Rarity, Id, Trait, Lore.
Skins.VISUAL = { 'Visual', 'Theme', 'Swing', 'Sound', 'Color', 'Icon', 'Inspect', 'Name', 'RU' }
local fxReady = false -- client: the Halloween hit themes are registered in PickFX
local cache = setmetatable({}, { __mode = 'k' }) -- real def -> skinId -> resolved def

local function themeOf(s)
	if IS_CLIENT and not fxReady then
		return s.ThemeAlt or s.Theme
	end
	return s.Theme
end

function Skins.Resolve(def, skinId)
	local s = type(skinId) == 'string' and Skins.ById[skinId] or nil
	if type(def) ~= 'table' or not s then
		return def
	end
	local byDef = cache[def]
	if not byDef then
		byDef = {}
		cache[def] = byDef
	end
	local out = byDef[skinId]
	if out then
		return out
	end
	out = table.clone(def)
	for _, k in ipairs(Skins.VISUAL) do
		if s[k] ~= nil then
			out[k] = s[k]
		end
	end
	out.Theme = themeOf(s)
	out.SkinId = skinId
	out.BaseId = def.Id
	byDef[skinId] = out
	return out
end

local function enabled()
	if not Shared then
		return true
	end
	local ok, on = pcall(Shared.Enabled)
	return not ok or on == true
end

function Skins.Of(player)
	if typeof(player) ~= 'Instance' or not player:IsA('Player') then
		return nil
	end
	local id = player:GetAttribute('PickaxeSkin')
	if type(id) ~= 'string' or not Skins.ById[id] or not enabled() then
		return nil
	end
	return id
end

function Skins.For(player, def)
	return Skins.Resolve(def, Skins.Of(player))
end

function Skins.Name(s)
	s = type(s) == 'string' and Skins.ById[s] or s
	if type(s) ~= 'table' then
		return ''
	end
	if Shared and Shared.IsRussian and Shared.IsRussian() then
		return s.RU or s.Name
	end
	return s.Name
end

---------------------------------------------------------------------------------------------------------------------
-- BUILDER HELPERS (same shapes and conventions as MiningModels, so PickFX / Mount treat the models identically)
---------------------------------------------------------------------------------------------------------------------
local SP, SL, ME, FA, NE, GL = Enum.Material.SmoothPlastic, Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Fabric, Enum.Material.Neon, Enum.Material.Glass
local WO, CM = Enum.Material.Wood, Enum.Material.CorrodedMetal
local V3, CF = Vector3.new, CFrame.new
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local SMALL = { CastShadow = false }

local function rgb(t, fallback)
	t = t or fallback or { 150, 150, 150 }
	return Color3.fromRGB(t[1], t[2], t[3])
end
local function material(name, fallback)
	local ok, m = pcall(function() return (Enum.Material :: any)[name] end)
	if ok and m then
		return m
	end
	return fallback or SL
end
local function part(parent, name, size, cf, color, mat, props)
	local p = Instance.new('Part')
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or SP
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end
local function wedge(parent, name, size, cf, color, mat, props)
	local p = Instance.new('WedgePart')
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or SP
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end
-- Rotation that turns +Y into dir.
local function alignY(dir)
	local up = V3(0, 1, 0)
	local d = dir.Unit
	local dot = math.clamp(up:Dot(d), -1, 1)
	if dot > .9999 then
		return CFrame.identity
	end
	if dot < -.9999 then
		return CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(up:Cross(d).Unit, math.acos(dot))
end
local function ball(parent, name, d, cf, color, mat, props)
	local p = part(parent, name, V3(d, d, d), cf, color, mat, props)
	p.Shape = Enum.PartType.Ball
	return p
end
local function blob(parent, name, size, cf, color, mat, props)
	local p = part(parent, name, size, cf, color, mat, props)
	local mesh = Instance.new('SpecialMesh')
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end
-- Cylinder along the model Y axis (Roblox cylinders run along local X).
local function cylY(parent, name, height, d, cf, color, mat, props)
	local p = part(parent, name, V3(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- Cylinder along the model Z axis (discs facing the camera).
local function cylZ(parent, name, depth, d, cf, color, mat, props)
	local p = part(parent, name, V3(depth, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- Box from a to b (width w, depth h).
local function bar(parent, name, a, b, w, h, color, mat, props)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	return part(parent, name, V3(w, len, h), CF(mid) * alignY(b - a), color, mat, props)
end
local function rod(parent, name, a, b, d, color, mat, props)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local p = part(parent, name, V3(len, d, d), CF(mid) * alignY(b - a) * CFrame.Angles(0, 0, math.pi / 2), color, mat, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- Ring of n boxes in the XY plane of cf (opening facing +-Z); skip(i) leaves gaps.
local function ring(parent, name, cf, radius, thick, depth, n, color, mat, skip, props)
	local out = {}
	local len = 2 * radius * math.tan(math.pi / n) + .04
	for i = 0, n - 1 do
		if not (skip and skip(i)) then
			local a = i / n * math.pi * 2
			table.insert(out, part(parent, name, V3(thick, len, depth), cf * CF(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a), color, mat, props))
		end
	end
	return out
end
local function anim(p, kind, phase, joint)
	p:SetAttribute('PickAnim', kind)
	if phase then
		p:SetAttribute('PickPhase', phase)
	end
	if joint then
		p:SetAttribute('PickJoint', joint)
	end
	return p
end
local function trailPoints(handle, a, b)
	local p1 = Instance.new('Attachment')
	p1.Name = 'TrailA'
	p1.Position = a
	p1.Parent = handle
	local p2 = Instance.new('Attachment')
	p2.Name = 'TrailB'
	p2.Position = b
	p2.Parent = handle
end
local function light(parent, name, color, range, brightness)
	local l = Instance.new('PointLight')
	l.Name = name
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end
-- A slow drifting particle emitter (begin -> peak -> fade), held models: 1 per skin.
local SPARK_TEX = 'rbxasset://textures/particles/sparkles_main.dds'
local SMOKE_TEX = 'rbxasset://textures/particles/smoke_main.dds'
local FIRE_TEX = 'rbxasset://textures/particles/fire_main.dds'
local function emitter(parent, name, tex, color, rate, size, speed, life, accel)
	local e = Instance.new('ParticleEmitter')
	e.Name = name
	e.Texture = tex
	e.Rate = rate
	e.Lifetime = NumberRange.new(life * .7, life)
	e.Speed = NumberRange.new(speed * .4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = accel or V3(0, .6, 0)
	e.Drag = 1.5
	e.LightEmission = 1
	e.LockedToPart = false
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.25, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .25), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end
-- Deterministic hash noise (the same model on the server and on every client; no Random dependency).
local function rng(seed)
	local s = seed
	return function()
		s += 1
		local x = math.sin(s * 12.9898 + seed * 78.233) * 43758.5453
		return x - math.floor(x)
	end
end
local function shader(rnd)
	return function(c, amount)
		local k = (rnd() - .5) * (amount or .16)
		return k > 0 and c:Lerp(WHITE, k * .6) or c:Lerp(BLACK, -k)
	end
end
-- A pointed spike: a wedge tapering along dir from base (normal = the flat side's facing).
local function spike(model, name, base, dir, normal, length, width, thick, color, mat, props)
	dir = dir.Unit
	local side = dir:Cross(normal).Unit
	local nrm = side:Cross(dir).Unit
	local c = base + dir * length * .5
	return wedge(model, name, V3(thick, length, width), CFrame.fromMatrix(c, side, dir, nrm) * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
end
-- A chain of n links hanging from `hang` straight down (model axes), every link animated at the hook.
local function chain(model, name, hang, links, size, colors, mat, motion, phase, props)
	local list = {}
	for k = 1, links do
		local cf = CF(hang - V3(0, size * .55 + (k - 1) * size * .82, 0)) * CFrame.Angles(0, k % 2 == 0 and math.pi / 2 or 0, 0)
		local col = colors[(k - 1) % #colors + 1]
		local link = part(model, name, V3(size * .38, size, size * .62), cf, col, mat or ME, props or { CastShadow = false, Reflectance = .06 })
		if motion then
			anim(link, motion, phase, hang)
		end
		table.insert(list, link)
	end
	return list, hang - V3(0, size * .55 + (links - 1) * size * .82 + size * .5, 0)
end
-- A coffin nail driven in at pos, pointing out along dir: square head + a short bent shank.
local function nail(model, pos, dir, color, size)
	size = size or 1
	local rot = alignY(dir)
	part(model, 'CoffinNailHead', V3(.11, .035, .11) * size, CF(pos + dir * .018 * size) * rot, color, ME, { CastShadow = false, Reflectance = .1 })
	part(model, 'CoffinNail', V3(.04, .07, .04) * size, CF(pos - dir * .02 * size) * rot, color:Lerp(BLACK, .3), ME, SMALL)
end

---------------------------------------------------------------------------------------------------------------------
-- DESIGNS
---------------------------------------------------------------------------------------------------------------------
local DESIGNS = {}

-- <<HW_GraveShovel
-- GRAVE SHOVEL (Epic): the Dead Yard gravedigger's spade. A pointed voxel spade of worn, hammered steel (rolled rim,
-- foot treads on the shoulders, a raised centre spine, clustered rust, a polished cutting edge, a cracked point still
-- caked with grave dirt, a grass tuft and a worm) with a GHOST trapped in it: a riveted reliquary window in the middle
-- of the blade where a translucent green ghost face pushes through the metal (hollow eyes, a wailing mouth, two little
-- hands gripping the window's edge). Three tiny sheet ghosts circle the blade. The socket is a riveted iron collar
-- with two straps running down the shaft, every rivet a square-headed coffin nail, a cobweb in the corner. The shaft
-- is weathered plank wood with iron ferrules, a rope knot carrying a swinging wooden R.I.P. tag and a cloth-wrapped
-- grip; the pommel is a dog skull with green-lit eyes and a chattering jaw.
-- Motion (PickFX generic): mini ghosts Orbit round the pole, the ghost face Breathes (its glow pulses, PickPulse),
-- the hands Jiggle, the tag swings (ScytheTalisman at the knot), the worm Waves, the skull's eyes pulse and its jaw
-- snaps on a strike (GummyJaw).
DESIGNS.HW_GraveShovel = function(model, v, def, len, top)
	local rnd = rng(311)
	local shade = shader(rnd)
	local steel = rgb(v.Head)
	local rust = rgb(v.Rust)
	local wood = rgb(v.Shaft)
	local dark = rgb(v.Trim)
	local green = rgb(v.Accent)
	local bone = rgb(v.Bone)
	local edgeC = Color3.fromRGB(206, 206, 200)
	local deep = Color3.fromRGB(14, 34, 22)
	local nailC = Color3.fromRGB(92, 88, 84)
	local dirt = Color3.fromRGB(86, 62, 42)
	local ghostC = green:Lerp(WHITE, .2)
	model.PrimaryPart.Transparency = 1
	local half = len * .5

	-- SHAFT: plank core, four uneven boards with grain, iron ferrules ------------------------------------------------
	local sY = top.Y + .05                          -- socket centre
	local y0, y1 = -half + .05, sY - .2
	part(model, 'ShaftCore', V3(.34, y1 - y0, .34), CF(0, (y0 + y1) / 2, 0), wood:Lerp(BLACK, .4), WO)
	local y = y0
	while y < y1 - .01 do
		local h = math.min(.45 + rnd() * .3, y1 - y)
		for side = 0, 3 do
			local a = side * math.pi / 2
			local off = .18 + rnd() * .02
			local col = shade(wood, .24)
			part(model, 'ShaftBoard', V3(.35 - rnd() * .04, h - .014, .05), CF(math.sin(a) * off, y + h / 2, math.cos(a) * off) * CFrame.Angles(0, a, 0), col, WO)
			if rnd() < .6 then
				part(model, 'Grain', V3(.025, h * (.35 + rnd() * .5), .012), CF(math.sin(a) * (off + .024), y + h * (.3 + rnd() * .4), math.cos(a) * (off + .024)) * CFrame.Angles(0, a, 0) * CF((rnd() - .5) * .16, 0, 0), col:Lerp(BLACK, .4), WO, SMALL)
			end
		end
		y += h
	end
	for _, fy in ipairs({ -half + .32, -.55, .75 }) do
		part(model, 'Ferrule', V3(.48, .16, .48), CF(0, fy, 0), shade(dark, .1), CM)
		part(model, 'FerruleLip', V3(.5, .04, .5), CF(0, fy + .08, 0), shade(steel, .1), ME, { Reflectance = .05 })
		part(model, 'FerruleLip', V3(.5, .04, .5), CF(0, fy - .08, 0), shade(steel:Lerp(BLACK, .2), .1), ME)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			nail(model, V3(math.sin(a) * .25, fy, math.cos(a) * .25), V3(math.sin(a), 0, math.cos(a)), nailC, .8)
		end
	end
	-- GRIP: dark cloth turns with a lighter binding (y -1.95 .. -.8)
	for k = 0, 10 do
		local gy = -1.95 + k * .105
		local col = k % 4 == 0 and Color3.fromRGB(122, 98, 70) or shade(Color3.fromRGB(56, 46, 42), .14)
		part(model, 'GripWrap', V3(.44, .095, .44), CF(0, gy, 0) * CFrame.Angles(0, k * .35, (k % 2 == 0 and .08 or -.08)), col, FA)
	end
	-- rope knot under the socket carrying the swinging R.I.P. tag (front)
	local knotY = sY - .62
	for k = 0, 2 do
		cylY(model, 'Rope', .065, .46 - k * .02, CF(0, knotY + k * .065, 0) * CFrame.Angles(0, k, 0), Color3.fromRGB(176, 150, 106), FA)
	end
	part(model, 'RopeKnot', V3(.12, .12, .1), CF(.06, knotY, .23), Color3.fromRGB(160, 134, 92), FA)
	local hang = V3(.06, knotY - .04, .27)
	local tagParts = {}
	for k = 1, 3 do
		table.insert(tagParts, part(model, 'TagCord', V3(.03, .1, .03), CF(hang - V3(0, k * .09 - .02, 0)) * CFrame.Angles(0, 0, (k % 2 == 0 and .15 or -.15)), Color3.fromRGB(176, 150, 106), FA, SMALL))
	end
	local tagC = CF(hang - V3(0, .5, -.02)) * CFrame.Angles(0, 0, .06)
	local tagWood = Color3.fromRGB(158, 124, 86)
	table.insert(tagParts, part(model, 'RipTag', V3(.56, .32, .05), tagC, tagWood, Enum.Material.WoodPlanks))
	table.insert(tagParts, wedge(model, 'RipTagTop', V3(.05, .12, .28), tagC * CF(-.14, .22, 0) * CFrame.Angles(0, -math.pi / 2, 0), tagWood, Enum.Material.WoodPlanks))
	table.insert(tagParts, wedge(model, 'RipTagTop', V3(.05, .12, .28), tagC * CF(.14, .22, 0) * CFrame.Angles(0, math.pi / 2, 0), tagWood, Enum.Material.WoodPlanks))
	table.insert(tagParts, part(model, 'RipTagHole', V3(.05, .05, .055), tagC * CF(0, .22, 0), BLACK, SP, SMALL))
	-- voxel letters R I P (3 x 5 pixels each), burnt into the tag
	local FONT = {
		R = { '##.', '#.#', '##.', '#.#', '#.#' },
		I = { '#', '#', '#', '#', '#' },
		P = { '##.', '#.#', '##.', '#..', '#..' },
	}
	local px = .043
	local x0 = -.21
	for _, ch in ipairs({ 'R', 'I', 'P' }) do
		local rows = FONT[ch]
		for r = 1, 5 do
			local row = rows[r]
			for c = 1, #row do
				if string.sub(row, c, c) == '#' then
					table.insert(tagParts, part(model, 'RipLetter', V3(px, px, .02), tagC * CF(x0 + (c - .5) * px, (3 - r) * px - .01, .03), Color3.fromRGB(46, 30, 20), SP, SMALL))
				end
			end
		end
		x0 += (#rows[1] + 1.2) * px
	end
	for _, p in ipairs(tagParts) do
		anim(p, 'ScytheTalisman', .4, hang)
	end

	-- SOCKET: riveted collar, flared top, straps down the shaft, a cobweb ------------------------------------------------
	part(model, 'Socket', V3(.48, .56, .44), CF(0, sY, 0), shade(steel:Lerp(BLACK, .45), .08), CM)
	part(model, 'SocketBand', V3(.52, .08, .48), CF(0, sY - .2, 0), shade(dark, .08), CM)
	part(model, 'SocketTop', V3(.7, .18, .3), CF(0, sY + .34, 0), shade(steel:Lerp(BLACK, .3), .08), CM)
	wedge(model, 'SocketFlare', V3(.3, .18, .28), CF(-.49, sY + .34, 0) * CFrame.Angles(0, -math.pi / 2, 0), steel:Lerp(BLACK, .32), CM)
	wedge(model, 'SocketFlare', V3(.3, .18, .28), CF(.49, sY + .34, 0) * CFrame.Angles(0, math.pi / 2, 0), steel:Lerp(BLACK, .32), CM)
	for _, z in ipairs({ 1, -1 }) do
		part(model, 'Strap', V3(.14, 1.15, .05), CF(0, sY - .75, z * .21), shade(dark, .1), CM)
		wedge(model, 'StrapEnd', V3(.14, .12, .05), CF(0, sY - 1.39, z * .21) * CFrame.Angles(math.pi, z > 0 and 0 or math.pi, 0), dark, CM)
		for k = 0, 2 do
			nail(model, V3(0, sY - .2 - k * .4, z * .24), V3(0, 0, z), nailC, .9)
		end
	end
	local web = Color3.fromRGB(236, 236, 240)
	local wc = V3(-.55, sY + .7, .1)          -- web anchored in the corner between collar and shoulder
	local spokes = { V3(-.62, .02, 0), V3(-.5, -.42, 0), V3(-.12, -.62, 0), V3(.02, -.5, 0) }
	for _, s in ipairs(spokes) do
		bar(model, 'Cobweb', wc, wc + s, .018, .01, web, SP, { Transparency = .25, CastShadow = false })
	end
	for _, r in ipairs({ .22, .42 }) do
		for k = 1, #spokes - 1 do
			bar(model, 'Cobweb', wc + spokes[k].Unit * r * (1 + (k % 2) * .1), wc + spokes[k + 1].Unit * r, .016, .01, web, SP, { Transparency = .35, CastShadow = false })
		end
	end
	ball(model, 'Spider', .07, CF(wc + V3(-.24, -.24, .01)), Color3.fromRGB(22, 18, 24), SP, SMALL)

	-- a little ghost-flame lantern hanging from the socket on a short chain
	local lh = V3(-.52, sY + .2, .1)
	local lantern, lb = chain(model, 'LanternChain', lh, 3, .13, { shade(dark:Lerp(steel, .4), .05) }, ME, 'ScytheChain', 1.7)
	local L = lb - V3(0, .22, 0)
	local lparts = {}
	table.insert(lparts, part(model, 'LanternCap', V3(.3, .06, .3), CF(L + V3(0, .2, 0)), dark, ME))
	table.insert(lparts, wedge(model, 'LanternRoof', V3(.3, .1, .15), CF(L + V3(0, .28, .075)), dark, ME))
	table.insert(lparts, wedge(model, 'LanternRoof', V3(.3, .1, .15), CF(L + V3(0, .28, -.075)) * CFrame.Angles(0, math.pi, 0), dark, ME))
	table.insert(lparts, part(model, 'LanternBase', V3(.3, .06, .3), CF(L - V3(0, .2, 0)), dark, ME))
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		table.insert(lparts, part(model, 'LanternBar', V3(.04, .36, .04), CF(L + V3(c[1] * .12, 0, c[2] * .12)), dark, ME, SMALL))
	end
	table.insert(lparts, part(model, 'LanternGlass', V3(.22, .32, .22), CF(L), green:Lerp(WHITE, .55), GL, { Transparency = .5, CastShadow = false }))
	local flame = blob(model, 'LanternFlame', V3(.1, .18, .1), CF(L - V3(0, .02, 0)), green:Lerp(WHITE, .25), NE, SMALL)
	flame:SetAttribute('PickPulse', true)
	table.insert(lparts, flame)
	for _, q in ipairs(lparts) do
		anim(q, 'ScytheChain', 1.7, lh)
	end
	light(flame, 'LanternLight', green, 4.5, .7)

	-- BLADE: a pointed spade in the XY plane (face +Z) built row by row --------------------------------------------------
	local CELL = .26
	local bY = sY + .43                        -- shoulder line
	local HALF = { 4.6, 4.75, 4.85, 4.9, 4.9, 4.8, 4.6, 4.25, 3.75, 3.1, 2.35, 1.5, .8 }
	local rows = #HALF
	local D = .15                               -- blade thickness
	local rustAt = { V3(-.85, bY + .35, 0), V3(.95, bY + 1.1, 0), V3(-.3, bY + 2.35, 0) }
	-- the reliquary window (no steel cells): rows 3..8, columns -2..2
	local function window(i, j) return j >= 3 and j <= 8 and math.abs(i) <= 2 end
	for j = 1, rows do
		local hw = HALF[j]
		local cy = bY + (j - .5) * CELL
		for i = -5, 5 do
			local frac = hw - (math.abs(i) - .5)
			if frac > .3 and not window(i, j) then
				local w = CELL * math.clamp(frac, .3, 1)
				local x = i * CELL - (i > 0 and 1 or (i < 0 and -1 or 0)) * (CELL - w) / 2
				local outer = frac < 1.5 or j == rows
				local cutting = outer and j >= 6
				local p = V3(x, cy, 0)
				local col, mat, d, refl = shade(steel, .18), ME, D + (rnd() - .5) * .03, .05
				local rusty = false
				for _, r in ipairs(rustAt) do
					if (p - r).Magnitude < .42 + rnd() * .2 then rusty = true end
				end
				if cutting then
					col, mat, d, refl = shade(edgeC, .08), ME, D - .03, .18
				elseif outer then
					col, mat, d, refl = shade(steel:Lerp(BLACK, .3), .1), CM, D + .05, 0
				elseif rusty and rnd() < .8 then
					col, mat = shade(rnd() < .5 and rust or rust:Lerp(BLACK, .3), .15), CM
				end
				part(model, cutting and 'BladeEdge' or (outer and 'BladeRim' or 'BladeSteel'), V3(w - .012, CELL - .012, d), CF(x, cy, (rnd() - .5) * .012), col, mat, { Reflectance = refl })
			end
		end
	end
	-- foot treads rolled over the shoulders, the raised spine, dents, the crack, rim nails
	for _, s in ipairs({ -1, 1 }) do
		local tread = part(model, 'FootTread', V3(.78, .17, .17), CF(s * .62, bY - .02, 0), shade(steel:Lerp(BLACK, .25), .08), ME, { Shape = Enum.PartType.Cylinder, Reflectance = .05 })
		part(model, 'TreadCap', V3(.06, .19, .19), CF(s * 1.02, bY - .02, 0), shade(dark, .08), CM)
	end
	part(model, 'BladeSpine', V3(.14, CELL * 2, D + .08), CF(0, bY + CELL * 1, 0), shade(steel:Lerp(BLACK, .22), .06), ME, { Reflectance = .06 })
	part(model, 'BladeSpineBack', V3(.2, CELL * 4.5, .06), CF(0, bY + CELL * 2.2, -D / 2 - .03), shade(steel:Lerp(BLACK, .3), .06), ME)
	for k = 1, 6 do
		local dx, dy = (rnd() - .5) * 1.6, bY + .3 + rnd() * 1.6
		part(model, 'Dent', V3(.07 + rnd() * .05, .07 + rnd() * .05, .012), CF(dx, dy, -(D / 2 + .015)), steel:Lerp(BLACK, .45), ME, SMALL)
	end
	local tipY = bY + rows * CELL
	bar(model, 'Crack', V3(.1, tipY - .06, D / 2 + .01), V3(-.05, tipY - .4, D / 2 + .01), .035, .012, Color3.fromRGB(24, 20, 20), SP, SMALL)
	bar(model, 'Crack', V3(-.05, tipY - .4, D / 2 + .01), V3(.07, tipY - .62, D / 2 + .01), .03, .012, Color3.fromRGB(24, 20, 20), SP, SMALL)
	for _, x in ipairs({ -.88, -.44, .44, .88 }) do
		nail(model, V3(x, bY + .12, D / 2 + .02), V3(0, 0, 1), nailC, .85)
	end
	-- GRAVE DIRT caked on the point (front and back), a grass tuft, a worm
	for k = 1, 9 do
		local fy = tipY - .18 - rnd() * .5
		local fx = (rnd() - .5) * (tipY - fy) * 1.3
		local zf = k % 3 == 0 and -1 or 1
		part(model, 'GraveDirt', V3(.12 + rnd() * .12, .08 + rnd() * .1, .06), CF(fx, fy, zf * (D / 2 + .03)) * CFrame.Angles(0, 0, rnd() - .5), shade(dirt, .22), Enum.Material.Ground)
	end
	for k = -1, 1 do
		wedge(model, 'GraveGrass', V3(.025, .2 + rnd() * .08, .06), CF(.2 + k * .05, tipY - .42, D / 2 + .05) * CFrame.Angles(0, 0, k * .3), Color3.fromRGB(96, 132, 60), Enum.Material.Grass, SMALL)
	end
	local wormC = Color3.fromRGB(214, 130, 140)
	for k = 0, 2 do
		anim(ball(model, 'Worm', .07, CF(-.16 + k * .055, tipY - .5 + math.sin(k * 1.6) * .03, D / 2 + .07), wormC:Lerp(BLACK, k * .08), SP, SMALL), 'Wave', k * .6, V3(-.16, tipY - .5, D / 2 + .07))
	end

	-- THE GHOST IN THE BLADE: a dark riveted window, the face pushing through, little hands on the edge ----------------
	local wY = bY + CELL * 5.5                  -- window centre
	local W, Hh = CELL * 5, CELL * 6
	part(model, 'WindowBack', V3(W + .02, Hh + .02, D - .02), CF(0, wY, 0), deep, SP)
	for _, s in ipairs({ -1, 1 }) do
		part(model, 'WindowFrame', V3(.07, Hh + .08, D + .07), CF(s * (W / 2 + .03), wY, 0), shade(steel:Lerp(rust, .35), .08), CM)
		part(model, 'WindowFrame', V3(W + .12, .07, D + .07), CF(0, wY + s * (Hh / 2 + .03), 0), shade(steel:Lerp(rust, .35), .08), CM)
		for k = -1, 1 do
			nail(model, V3(s * (W / 2 + .03), wY + k * .45, D / 2 + .045), V3(0, 0, 1), nailC, .75)
		end
	end
	local face = {}
	local head = blob(model, 'GhostFace', V3(.94, 1.18, .54), CF(0, wY + .02, .04), green, NE, { Transparency = .42, CastShadow = false })
	head:SetAttribute('PickPulse', true)
	table.insert(face, head)
	table.insert(face, blob(model, 'GhostFaceCore', V3(.6, .78, .4), CF(0, wY + .06, .05), ghostC:Lerp(WHITE, .35), NE, { Transparency = .25, CastShadow = false }))
	table.insert(face, blob(model, 'GhostFaceTop', V3(.5, .34, .3), CF(0, wY + .42, .08), ghostC:Lerp(WHITE, .45), NE, { Transparency = .3, CastShadow = false }))
	for _, s in ipairs({ -1, 1 }) do
		table.insert(face, blob(model, 'GhostEye', V3(.17, .25, .12), CF(s * .16, wY + .14, .25) * CFrame.Angles(0, 0, s * .15), Color3.fromRGB(10, 24, 14), SP, SMALL))
		table.insert(face, ball(model, 'GhostEyeGlint', .045, CF(s * .16 + .03, wY + .2, .31), WHITE, NE, SMALL))
		table.insert(face, blob(model, 'GhostCheek', V3(.1, .06, .05), CF(s * .27, wY - .02, .26), Color3.fromRGB(140, 255, 170), NE, { Transparency = .35, CastShadow = false }))
	end
	table.insert(face, blob(model, 'GhostMouth', V3(.16, .26, .12), CF(0, wY - .24, .24), Color3.fromRGB(10, 24, 14), SP, SMALL))
	for _, p in ipairs(face) do
		anim(p, 'Breathe', 0)
	end
	light(head, 'GhostGlow', green, 7.5, 1.2)
	-- little hands gripping the window edges (three fingers each)
	for _, s in ipairs({ -1, 1 }) do
		for f = -1, 1 do
			local fp = V3(s * (W / 2 + .02), wY - .05 + f * .1, D / 2 + .1)
			anim(blob(model, 'GhostFinger', V3(.16, .075, .1), CF(fp) * CFrame.Angles(0, 0, s * f * .15), ghostC, NE, { Transparency = .3, CastShadow = false }), 'Jiggle', s + f * .3, fp)
		end
		anim(blob(model, 'GhostPalm', V3(.16, .26, .1), CF(s * (W / 2 - .07), wY - .05, D / 2 + .06), green, NE, { Transparency = .45, CastShadow = false }), 'Jiggle', s, V3(s * W / 2, wY, 0))
	end
	local holder = part(model, 'GhostWispFX', V3(.6, .6, .1), CF(0, wY + .3, .12), green, SP, { Transparency = 1, CastShadow = false })
	emitter(holder, 'GhostWisps', SMOKE_TEX, ghostC, 2.5, .5, .5, 1.8, V3(0, 1.2, 0))

	-- THREE TINY SHEET GHOSTS circling the blade (built facing outward; Orbit turns them round the pole) ------------------
	local center = V3(0, wY + .15, 0)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + .5
		local out = V3(math.sin(a), 0, math.cos(a))
		local g = CFrame.lookAt(center + out * 1.75 + V3(0, (k - 1) * .36, 0), center + out * 3 + V3(0, (k - 1) * .36, 0))
		local bits = {}
		table.insert(bits, ball(model, 'MiniGhost', .3, g * CF(0, .1, 0), ghostC:Lerp(WHITE, .5), NE, { Transparency = .12, CastShadow = false }))
		table.insert(bits, blob(model, 'MiniGhostSheet', V3(.32, .34, .28), g * CF(0, -.06, 0), ghostC:Lerp(WHITE, .4), NE, { Transparency = .18, CastShadow = false }))
		table.insert(bits, blob(model, 'MiniGhostTail', V3(.18, .2, .16), g * CF(0, -.24, .06) * CFrame.Angles(.5, 0, 0), ghostC, NE, { Transparency = .35, CastShadow = false }))
		for _, s in ipairs({ -1, 1 }) do
			table.insert(bits, ball(model, 'MiniGhostEye', .055, g * CF(s * .06, .12, -.14), Color3.fromRGB(10, 20, 14), SP, SMALL))
		end
		table.insert(bits, ball(model, 'MiniGhostMouth', .05, g * CF(0, .03, -.14), Color3.fromRGB(10, 20, 14), SP, SMALL))
		for _, q in ipairs(bits) do
			anim(q, 'Orbit', k / 3, center)
		end
	end

	-- POMMEL: a dog skull (snout forward, pointed ears), green-lit eyes, a snapping jaw ---------------------------------
	local K = CF(0, -half - .3, .02)
	part(model, 'SkullCap', V3(.58, .4, .52), K * CF(0, .08, -.03), shade(bone, .06), SP)
	part(model, 'SkullDome', V3(.46, .12, .42), K * CF(0, .3, -.05), shade(bone, .06), SP)
	part(model, 'SkullBrow', V3(.6, .1, .18), K * CF(0, .2, .2), shade(bone:Lerp(BLACK, .05), .06), SP)
	part(model, 'SkullCheek', V3(.52, .22, .44), K * CF(0, -.14, 0), bone:Lerp(BLACK, .08), SP)
	part(model, 'SkullSnout', V3(.3, .2, .32), K * CF(0, -.12, .32), shade(bone, .05), SP)
	part(model, 'SkullSnoutTop', V3(.24, .06, .26), K * CF(0, -.01, .3), shade(bone, .05), SP)
	part(model, 'SkullNose', V3(.13, .08, .05), K * CF(0, -.06, .48), Color3.fromRGB(30, 22, 18), SP, SMALL)
	part(model, 'SkullCrack', V3(.03, .18, .02), K * CF(-.12, .2, .26) * CFrame.Angles(0, 0, .4), Color3.fromRGB(70, 60, 50), SP, SMALL)
	for _, s in ipairs({ -1, 1 }) do
		part(model, 'SkullSocket', V3(.17, .15, .05), K * CF(s * .14, .05, .27), Color3.fromRGB(14, 22, 14), SP, SMALL)
		local eyeGlow = ball(model, 'SkullEye', .09, K * CF(s * .14, .05, .29), green:Lerp(WHITE, .25), NE, SMALL)
		eyeGlow:SetAttribute('PickPulse', true)
		wedge(model, 'SkullEar', V3(.08, .22, .16), K * CF(s * .22, .4, -.08) * CFrame.Angles(0, 0, s * -.3), shade(bone, .06), SP)
		part(model, 'SkullCheekBone', V3(.08, .08, .24), K * CF(s * .27, -.06, .08), shade(bone, .05), SP)
	end
	local jawPivot = (K * CF(0, -.24, -.12)).Position
	for k = -1, 1 do
		part(model, 'SkullTooth', V3(.05, .06, .05), K * CF(k * .07, -.25, .44), WHITE, SP, SMALL)
	end
	local jawParts = { part(model, 'SkullJaw', V3(.3, .08, .36), K * CF(0, -.32, .2), bone:Lerp(BLACK, .1), SP) }
	for k = -1, 1, 2 do
		table.insert(jawParts, part(model, 'SkullFang', V3(.045, .07, .045), K * CF(k * .1, -.25, .36), WHITE, SP, SMALL))
	end
	for _, p in ipairs(jawParts) do
		anim(p, 'GummyJaw', 0, jawPivot)
	end

	model:SetAttribute('BackC0', CF(.3, -.25, .3))
	model:SetAttribute('DisplayScale', .82)
	return V3(-1.15, wY, 0), V3(1.15, wY, 0)
end
-- >>HW_GraveShovel

-- <<HW_BonePickaxe
-- BONE PICKAXE (Legendary): a pickaxe grown from a dog skeleton. The HANDLE is a spine: stacked vertebrae (bodies,
-- cartilage discs, spinous and transverse processes) with a leather-strapped grip, a ribcage hugging the neck under
-- the head and a wagging tailbone for a pommel. The HEAD is a big dog skull facing +Z (brow ridge, deep sockets with
-- amber glowing eyes, a long snout with nose cavity, fangs, a snapping lower jaw, cracks and chips) with two femurs
-- lashed to it as the pick arms: the -X femur ends in its round femur head (the hammer), the +X femur in its knobby
-- condyles split into a sharpened bone point (the pick). Leather straps and bone pins bind it all; a dog-bone charm
-- swings on a cord of little teeth.
-- Motion (PickFX generic): the jaw snaps on a strike and chomps in the inspect (GummyJaw), the eyes twitch
-- (EyeTwitch) and glow (PickPulse), the ribs breathe (Breathe), the tailbone wags (Antenna), the charm swings
-- (ScytheChain).
DESIGNS.HW_BonePickaxe = function(model, v, def, len, top)
	local rnd = rng(523)
	local shade = shader(rnd)
	local bone = rgb(v.Head)
	local old = rgb(v.Shaft)
	local glow = rgb(v.Accent)
	local leather = rgb(v.Trim)
	local cart = Color3.fromRGB(196, 168, 160)
	local hole = Color3.fromRGB(26, 18, 16)
	local crackC = Color3.fromRGB(120, 100, 80)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, top.Y + .55, 0)             -- skull centre
	local Sk = 1.3                              -- skull scale
	local function at(x, y, z) return CF(H + V3(x, y, z) * Sk) end

	-- SPINE HANDLE: vertebrae from the tail up to the skull ------------------------------------------------------------
	local yTop = H.Y - .78
	local yBot = -half + .25
	local pitch = .25
	local k = 0
	local y = yBot
	while y < yTop do
		local grip = y > -2.0 and y < -.8
		local s = 1 - math.clamp((yTop - y) / (yTop - yBot), 0, 1) * .12
		local col = shade(old, .1)
		cylY(model, 'Vertebra', pitch * .62, .48 * s, CF(0, y, 0) * CFrame.Angles(0, k * .4, 0), col, SP)
		cylY(model, 'VertebraRim', .04, .52 * s, CF(0, y + pitch * .28, 0), col:Lerp(WHITE, .12), SP)
		cylY(model, 'Disc', pitch * .3, .4 * s, CF(0, y + pitch * .48, 0), shade(cart, .08), SP)
		if not grip then
			part(model, 'Foramen', V3(.08, .06, .02), CF(0, y, .24 * s), crackC:Lerp(BLACK, .3), SP, SMALL)
		end
		if not grip then
			wedge(model, 'SpinousProcess', V3(.09, .16, .24), CF(0, y + .02, -.33 * s) * CFrame.Angles(math.pi, 0, 0), shade(old, .1), SP)
			for _, sx in ipairs({ -1, 1 }) do
				part(model, 'TransverseProcess', V3(.18 * s, .08, .1), CF(sx * .33 * s, y + .03, -.04) * CFrame.Angles(0, 0, sx * .25), shade(old, .1), SP)
			end
		end
		y += pitch
		k += 1
	end
	-- leather grip straps (crossing) with bone toggles
	for i = 0, 5 do
		local gy = -1.95 + i * .2
		part(model, 'GripStrap', V3(.55, .09, .55), CF(0, gy, 0) * CFrame.Angles(0, i * .5, (i % 2 == 0 and .16 or -.16)), shade(leather, .12), material('Leather', FA))
	end
	part(model, 'GripStitch', V3(.03, 1.1, .02), CF(0, -1.4, .28), Color3.fromRGB(230, 200, 140), FA, SMALL)
	for _, gy in ipairs({ -2.0, -.8 }) do
		cylY(model, 'GripCuff', .1, .58, CF(0, gy, 0), shade(leather:Lerp(BLACK, .25), .08), material('Leather', FA))
		part(model, 'BoneToggle', V3(.2, .06, .06), CF(.12, gy, .3), bone, SP, SMALL)
	end
	-- TAILBONE pommel: shrinking caudal vertebrae, a pointed tip; wags
	local tailParts = {}
	local ty = yBot - .12
	for i = 0, 3 do
		local s = .32 - i * .06
		table.insert(tailParts, part(model, 'TailBone', V3(s, .14, s), CF(math.sin(i * .5) * .03, ty - i * .15, 0) * CFrame.Angles(0, i * .3, 0), shade(old, .1), SP))
		table.insert(tailParts, part(model, 'TailDisc', V3(s * .7, .04, s * .7), CF(0, ty - i * .15 - .08, 0), cart, SP, SMALL))
	end
	table.insert(tailParts, spike(model, 'TailTip', V3(0, ty - .62, 0), V3(0, -1, 0), V3(0, 0, 1), .26, .12, .1, old, SP))
	for _, p in ipairs(tailParts) do
		anim(p, 'Antenna', 0, V3(0, yBot - .05, 0))
	end

	-- RIBCAGE under the head: 3 pairs of ribs leaving the spine at the back, sweeping out, forward and down, their tips
	-- left open in front like a cradle (they breathe)
	for r = 1, 3 do
		local ry = yTop - .02 - (r - 1) * .3
		local spread = .66 - r * .08
		local ribParts = {}
		for _, sx in ipairs({ -1, 1 }) do
			local prev = V3(sx * .12, ry, -.18)
			for sgm = 1, 6 do
				local f = sgm / 6
				local a = f * math.pi * .78
				local p = V3(sx * (.12 + math.sin(a) * spread), ry - f * f * .42, -.18 + (1 - math.cos(a)) * spread * .62)
				table.insert(ribParts, bar(model, 'Rib', prev, p, .09 - f * .025, .075, shade(bone, .08), SP))
				prev = p
			end
			table.insert(ribParts, ball(model, 'RibTip', .09, CF(prev), shade(bone, .06), SP))
		end
		for _, p in ipairs(ribParts) do
			anim(p, 'Breathe', r * .3)
		end
	end

	-- SKULL (dog, facing +Z) --------------------------------------------------------------------------------------------
	local skull = {}
	local function sp(name, size, cf, col, mat, props) local p = part(model, name, size * Sk, cf, col, mat or SP, props); table.insert(skull, p); return p end
	sp('Cranium', V3(.9, .7, .8), at(0, .08, -.12), shade(bone, .05))
	sp('CraniumTop', V3(.74, .16, .7), at(0, .48, -.14), shade(bone, .05))
	sp('Crest', V3(.12, .12, .62), at(0, .6, -.14), shade(bone, .05))
	sp('Occiput', V3(.6, .5, .18), at(0, .1, -.6), shade(bone:Lerp(BLACK, .05), .05))
	sp('Brow', V3(.96, .14, .24), at(0, .32, .24), shade(bone, .04))
	sp('Cheek', V3(.84, .3, .5), at(0, -.24, .08), shade(bone:Lerp(BLACK, .06), .05))
	for _, sx in ipairs({ -1, 1 }) do
		sp('Zygoma', V3(.14, .14, .5), at(sx * .48, -.12, .02), shade(bone, .05))
		sp('Socket', V3(.26, .24, .1), at(sx * .22, .12, .32), hole)
		sp('SocketRim', V3(.08, .3, .14), at(sx * .38, .12, .3), shade(bone, .05))
		local e = ball(model, 'Eye', .2 * Sk, at(sx * .22, .12, .35), glow, NE, SMALL)
		e:SetAttribute('PickPulse', true)
		anim(e, 'EyeTwitch', sx, (H + V3(sx * .22, .12, .3) * Sk))
		anim(part(model, 'EyePupil', V3(.05, .15, .03), at(sx * .22, .12, .45), Color3.fromRGB(60, 20, 0), SP, SMALL), 'EyeTwitch', sx, (H + V3(sx * .22, .12, .3) * Sk))
		sp('TempleCrack', V3(.03, .2, .02), at(sx * .3, .4, .37) * CFrame.Angles(0, 0, sx * .5), crackC, SP, SMALL)
	end
	-- snout
	sp('Snout', V3(.5, .3, .72), at(0, -.18, .64), shade(bone, .05))
	sp('SnoutBridge', V3(.36, .1, .62), at(0, .02, .58), shade(bone, .05))
	sp('Nose', V3(.22, .14, .06), at(0, -.08, 1.0), hole)
	sp('NoseFire', V3(.14, .08, .04), at(0, -.09, .99), glow, NE, SMALL)
	sp('NoseSeptum', V3(.03, .12, .04), at(0, -.08, 1.02), shade(bone, .05), SP, SMALL)
	for t = -2, 2 do
		local fang = math.abs(t) == 2
		sp('Tooth', V3(.07, fang and .16 or .08, .07), at(t * .085, -.36 - (fang and .04 or 0), .94 - math.abs(t) * .05), WHITE, SP, SMALL)
	end
	sp('Chip', V3(.12, .1, .12), at(.24, .46, .2) * CFrame.Angles(.3, .4, .2), shade(bone:Lerp(BLACK, .1), .05))
	sp('Crack', V3(.03, .32, .02), at(-.1, .3, .37) * CFrame.Angles(0, 0, .3), crackC, SP, SMALL)
	sp('Crack', V3(.03, .2, .02), at(-.05, .16, .37) * CFrame.Angles(0, 0, -.5), crackC, SP, SMALL)
	-- lower jaw (snaps on a strike)
	local jawPivot = H + V3(0, -.36, -.1) * Sk
	sp('MouthFire', V3(.36, .05, .5), at(0, -.4, .6), glow, NE, SMALL)
	local jaw = {}
	table.insert(jaw, part(model, 'Jaw', V3(.46, .12, .74) * Sk, at(0, -.46, .5), shade(bone:Lerp(BLACK, .06), .05), SP))
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(jaw, part(model, 'JawRamus', V3(.1, .26, .2) * Sk, at(sx * .3, -.36, .02), shade(bone, .05), SP))
		table.insert(jaw, part(model, 'LowerFang', V3(.06, .13, .06) * Sk, at(sx * .16, -.36, .8), WHITE, SP, SMALL))
	end
	for t = -1, 1 do
		table.insert(jaw, part(model, 'LowerTooth', V3(.06, .07, .06) * Sk, at(t * .08, -.37, .86), WHITE, SP, SMALL))
	end
	for _, p in ipairs(jaw) do
		anim(p, 'GummyJaw', 0, jawPivot)
	end
	local lamp = part(model, 'SkullGlow', V3(.3, .3, .3), at(0, .1, .1), glow, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'SkullLight', glow, 6.5, 1.1)
	emitter(lamp, 'EyeEmbers', SPARK_TEX, glow, 2.5, .22, .5, 1.2, V3(0, 1.2, 0))

	-- skull top: sutures and a melting candle (its flame flickers)
	sp('Suture', V3(.03, .02, .5), at(0, .565, -.12), crackC, SP, SMALL)
	sp('Suture', V3(.5, .02, .03), at(0, .565, -.3), crackC, SP, SMALL)
	local cTop = H + V3(.18, .62, -.2) * Sk
	cylY(model, 'Candle', .42, .2, CF(cTop + V3(0, .2, 0)), Color3.fromRGB(240, 232, 208), SP)
	for k = 0, 3 do
		local a = k * 1.7
		part(model, 'WaxDrip', V3(.06, .12 + (k % 2) * .14, .05), CF(cTop + V3(math.cos(a) * .1, .3 - (k % 2) * .07, math.sin(a) * .1)), Color3.fromRGB(246, 240, 222), SP, SMALL)
	end
	cylY(model, 'WaxPool', .05, .34, CF(cTop + V3(0, .01, 0)), Color3.fromRGB(240, 232, 208), SP, SMALL)
	part(model, 'Wick', V3(.02, .07, .02), CF(cTop + V3(0, .44, 0)), BLACK, SP, SMALL)
	local flame = blob(model, 'CandleFlame', V3(.1, .2, .1), CF(cTop + V3(0, .55, 0)), Color3.fromRGB(255, 220, 120), NE, SMALL)
	local flameCore = blob(model, 'CandleFlameCore', V3(.05, .1, .05), CF(cTop + V3(0, .52, 0)), WHITE, NE, SMALL)
	for _, f in ipairs({ flame, flameCore }) do
		anim(f, 'Shake', 0, cTop + V3(0, .44, 0))
		f:SetAttribute('PickPulse', true)
	end

	-- FEMURS: the pick arms ------------------------------------------------------------------------------------------
	local function femurShaft(sx)
		local pts = {}
		for i = 0, 6 do
			local f = i / 6
			table.insert(pts, H + V3(sx * (.6 + f * 1.55), .02 - f * f * .5, -.1))
		end
		for i = 1, #pts - 1 do
			local d = .42 + math.sin(i / (#pts - 1) * math.pi) * -.08
			rod(model, 'Femur', pts[i], pts[i + 1], d, shade(bone, .06), SP)
			if i % 2 == 0 then
				rod(model, 'FemurRidge', pts[i] + V3(0, .13, 0), pts[i + 1] + V3(0, .13, 0), .08, shade(bone:Lerp(BLACK, .08), .04), SP)
			end
		end
		for _, i in ipairs({ 1, 3, 5 }) do -- knuckle rings and hairline cracks along the shaft
			cylY(model, 'FemurKnuckle', .06, .46, CF(pts[i + 1]) * alignY(pts[i + 1] - pts[i]), shade(bone:Lerp(BLACK, .06), .04), SP)
			part(model, 'FemurCrack', V3(.16, .025, .02), CF((pts[i] + pts[i + 1]) / 2 + V3(0, -.06, .19)) * CFrame.Angles(0, 0, sx * .35), crackC, SP, SMALL)
		end
		for _, i in ipairs({ 2, 4 }) do
			local m = (pts[i] + pts[i + 1]) / 2
			part(model, 'MarrowGlow', V3(.2, .035, .03), CF(m + V3(0, 0, .17)) * CFrame.Angles(0, 0, sx * (i == 2 and .5 or -.4)), glow, NE, SMALL)
			part(model, 'MarrowGlow', V3(.1, .03, .03), CF(m + V3(sx * .08, -.06, .17)) * CFrame.Angles(0, 0, sx * 1.2), glow, NE, SMALL)
		end
		return pts[#pts]
	end
	-- -X femur: neck + round head + trochanter (the hammer)
	local endL = femurShaft(-1)
	part(model, 'FemurFlare', V3(.46, .44, .44), CF(endL + V3(-.08, 0, 0)), shade(bone, .05), SP)
	local neck = endL + V3(-.26, .18, 0)
	rod(model, 'FemurNeck', endL, neck, .3, shade(bone, .05), SP)
	ball(model, 'FemurHead', .64, CF(neck + V3(-.24, .14, 0)), shade(bone, .04), SP)
	part(model, 'Trochanter', V3(.26, .32, .3), CF(endL + V3(-.02, -.26, 0)), shade(bone, .05), SP)
	part(model, 'FemurCrack', V3(.24, .03, .02), CF(endL + V3(.25, .06, .14)), crackC, SP, SMALL)
	-- +X femur: condyles split into a sharpened bone point (the pick)
	local endR = femurShaft(1)
	for _, z in ipairs({ -.12, .12 }) do
		ball(model, 'Condyle', .38, CF(endR + V3(.06, -.04, z * 1.2)), shade(bone, .04), SP)
	end
	local tipBase = endR + V3(.2, -.08, 0)
	spike(model, 'BonePoint', tipBase, V3(1, -.45, 0), V3(0, 0, 1), 1.15, .38, .32, shade(bone, .04), SP)
	part(model, 'MarrowCore', V3(.16, .16, .2), CF(tipBase + V3(-.02, 0, 0)), glow, NE, SMALL)
	spike(model, 'BoneSplinter', tipBase + V3(0, .12, .08), V3(1, -.15, .1), V3(0, 0, 1), .7, .16, .12, shade(bone:Lerp(WHITE, .1), .04), SP)
	spike(model, 'BoneSplinter', tipBase + V3(0, -.1, -.1), V3(1, -.75, -.1), V3(0, 0, 1), .6, .14, .12, shade(bone:Lerp(BLACK, .08), .04), SP)
	-- lashings where the femurs meet the skull: leather wraps + bone pins
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 2 do
			local p = H + V3(sx * (.7 + i * .11), .01, -.1)
			part(model, 'Lashing', V3(.08, .48, .48), CF(p) * CFrame.Angles(i * .3, 0, sx * .12), shade(leather, .12), material('Leather', FA))
		end
		part(model, 'BonePin', V3(.07, .07, .62), CF(H + V3(sx * .82, .28, -.1)), WHITE, SP, SMALL)
		for _, z in ipairs({ -.42, .22 }) do
			ball(model, 'PinKnob', .1, CF(H + V3(sx * .82, .28, z)), WHITE, SP, SMALL)
		end
		sp('Molar', V3(.07, .07, .1), at(sx * .2, -.33, .62), WHITE, SP, SMALL)
	end
	-- neck collar joining spine and skull
	cylY(model, 'Atlas', .18, .62, CF(0, yTop + .04, -.08), shade(old, .08), SP)
	cylY(model, 'Axis', .16, .52, CF(0, yTop + .2, -.08), shade(old, .08), SP)

	-- a necklace of teeth draped round the neck under the skull (front)
	for k = -4, 4 do
		local a = k / 4 * 1.1
		local p = V3(math.sin(a) * .42, yTop + .08 - math.cos(a) * .02 - (1 - math.cos(a)) * -.1, math.cos(a) * .3 + .02)
		part(model, 'NecklaceCord', V3(.12, .025, .025), CF(p) * CFrame.Angles(0, -a, 0), leather, FA, SMALL)
		if k ~= 0 then
			wedge(model, 'NecklaceTooth', V3(.05, .14, .07), CF(p - V3(0, .08, 0)) * CFrame.Angles(math.pi, -a, 0), WHITE, SP, SMALL)
		else
			local g = part(model, 'NecklaceGem', V3(.1, .12, .06), CF(p - V3(0, .08, .02)) * CFrame.Angles(0, 0, math.pi / 4), glow, NE, SMALL)
			g:SetAttribute('PickPulse', true)
		end
	end

	-- DOG-BONE CHARM on a cord of teeth, swinging from the left femur ---------------------------------------------------
	local hang = H + V3(-1.2, -.2, .1)
	local charm = {}
	for i = 1, 4 do
		local p = hang - V3(0, i * .1, 0)
		table.insert(charm, part(model, 'CharmCord', V3(.025, .1, .025), CF(p), Color3.fromRGB(70, 50, 40), FA, SMALL))
		if i % 2 == 0 then
			table.insert(charm, wedge(model, 'CharmTooth', V3(.04, .1, .06), CF(p + V3(0, 0, .03)) * CFrame.Angles(math.pi, 0, 0), WHITE, SP, SMALL))
		end
	end
	local cb = hang - V3(0, .56, 0)
	table.insert(charm, part(model, 'CharmBone', V3(.32, .08, .08), CF(cb), WHITE, SP))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			table.insert(charm, ball(model, 'CharmKnob', .1, CF(cb + V3(sx * .16, sy * .04, 0)), WHITE, SP))
		end
	end
	for _, p in ipairs(charm) do
		anim(p, 'ScytheChain', .7, hang)
	end

	model:SetAttribute('BackC0', CF(.35, .1, .3))
	return H + V3(-2.0, .2, 0), H + V3(2.55, -.55, 0)
end
-- >>HW_BonePickaxe

-- <<HW_PumpkinSmasher
-- PUMPKIN SMASHER (Legendary): a giant jack-o'-lantern maul. The HEAD is a big ribbed pumpkin (ten lobes, dark
-- grooves, blotches) with a carved grinning face on the +Z side glowing from the candle inside (triangle eyes with a
-- burning core, a triangle nose, a jagged toothy grin), bound by a riveted iron hoop round its sides that carries
-- the two striking faces at +-X (iron plates with four stubby studs each). On top a twisted dark stem, two broad
-- leaves and a curling tendril. The HANDLE is a thick twisted vine: a dark core wound with a green vine helix, leaves
-- and curling tendrils sprouting along it, a twine-wrapped grip; the pommel is a baby jack-o'-lantern with its own
-- little glowing face.
-- Motion (PickFX generic): the face glow breathes (PickPulse) while little flame tongues dance inside the eyes and
-- mouth (Shake), the stem and leaves wobble (Antenna / Fluff), the tendrils curl (Curl), the vine leaves flutter on
-- a run (PonyFin with PickAmp side), the baby pumpkin bobs (Bob).
DESIGNS.HW_PumpkinSmasher = function(model, v, def, len, top)
	local rnd = rng(733)
	local shade = shader(rnd)
	local orange = rgb(v.Head)
	local groove = orange:Lerp(Color3.fromRGB(120, 40, 0), .55)
	local glowC = rgb(v.Accent)
	local hot = Color3.fromRGB(255, 244, 170)
	local carve = Color3.fromRGB(70, 26, 6)
	local vine = rgb(v.Vine)
	local stemC = Color3.fromRGB(86, 96, 46)
	local iron = rgb(v.Trim)
	local twine = Color3.fromRGB(186, 160, 110)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, top.Y + .95, 0)            -- pumpkin centre
	local RX, RY, RZ = 1.12, .9, 1.0           -- pumpkin half sizes

	-- PUMPKIN BODY: ten lobes round the Y axis, grooves between them -------------------------------------------------
	blob(model, 'PumpkinCore', V3(RX * 1.86, RY * 1.86, RZ * 1.86), CF(H), groove, SP)
	local N = 10
	for i = 0, N - 1 do
		local a = (i + .5) / N * math.pi * 2
		local dir = V3(math.sin(a), 0, math.cos(a))
		local r = V3(dir.X * RX, 0, dir.Z * RZ)
		local lobeW = 2 * math.pi * RX / N * 1.18
		local col = shade(orange, .14)
		blob(model, 'PumpkinLobe', V3(lobeW, RY * 2.02, .82), CFrame.lookAt(H + r * .66, H + r * 2), col, SP)
		local g = (i + 1) / N * math.pi * 2
		local gd = V3(math.sin(g) * RX, 0, math.cos(g) * RZ)
		blob(model, 'PumpkinGroove', V3(.14, RY * 1.9, .2), CFrame.lookAt(H + gd * .86, H + gd * 2), groove, SP)
	end
	-- top and bottom caps (the dimples the lobes gather into)
	blob(model, 'PumpkinTop', V3(RX * 1.5, .3, RZ * 1.4), CF(H + V3(0, RY * .78, 0)), shade(orange:Lerp(BLACK, .08), .05), SP)
	blob(model, 'PumpkinBottom', V3(RX * 1.4, .28, RZ * 1.3), CF(H - V3(0, RY * .8, 0)), shade(orange:Lerp(BLACK, .12), .05), SP)
	for k = 1, 10 do
		local a = rnd() * math.pi * 2
		local yy = (rnd() - .5) * RY * 1.2
		local d = V3(math.sin(a) * RX * 1.0, yy, math.cos(a) * RZ * 1.0)
		if d.Z < .55 or math.abs(d.X) > .6 then
			blob(model, 'Blotch', V3(.18 + rnd() * .14, .12 + rnd() * .1, .06), CFrame.lookAt(H + d, H + d * 2), orange:Lerp(Color3.fromRGB(150, 90, 20), .5), SP, SMALL)
		end
	end

	-- CARVED FACE (+Z): dark carved rims, glowing insides, little flame tongues ------------------------------------------
	local FZ = H.Z + RZ * 1.06
	-- the lobes' front surface (z) at a face point x, y (relative to the centre)
	local function zs(x, y) return H.Z + RZ * 1.07 * math.sqrt(math.max(.05, 1 - (x / 1.27) ^ 2 - (y / .98) ^ 2)) end
	local glowParts = {}
	-- an isoceles triangle facing +Z (apex up), two mirrored wedges; returns both
	local function tri(name, cf, w, h, depth, color, mat, props)
		local l = wedge(model, name, V3(depth, h, w / 2), cf * CF(-w / 4, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), color, mat, props)
		local r = wedge(model, name, V3(depth, h, w / 2), cf * CF(w / 4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), color, mat, props)
		return l, r
	end
	local function hole(name, cf, w, h, apexDown)
		local base = apexDown and cf * CFrame.Angles(0, 0, math.pi) or cf
		tri(name .. 'Rim', base * CF(0, 0, -.02), w + .14, h + .12, .1, carve, SP)
		local a, b = tri(name, base * CF(0, 0, .02), w, h, .06, glowC, NE, SMALL)
		a:SetAttribute('PickPulse', true)
		b:SetAttribute('PickPulse', true)
		table.insert(glowParts, a)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local ecf = CF(H.X + sx * .42, H.Y + .26, zs(.42, .26) - .01) * CFrame.Angles(-.2, sx * .4, 0)
		hole('FaceEye', ecf, .44, .36, false)
		blob(model, 'EyeFire', V3(.14, .18, .04), ecf * CF(0, -.04, .06), hot, NE, SMALL)
		anim(blob(model, 'EyeFlame', V3(.09, .14, .03), ecf * CF(0, .03, .07), WHITE, NE, SMALL), 'Shake', sx, (ecf * CF(0, -.08, .07)).Position)
	end
	local ncf = CF(H.X, H.Y - .02, zs(0, -.02) - .01)
	hole('FaceNose', ncf, .2, .16, true)
	-- the grin: a crescent of glowing segments with three teeth
	local grin = {}
	for i = -4, 4 do
		local x = i * .135
		local yy = H.Y - .34 + (x * x) * .55
		local zz = zs(x, yy - H.Y) - .02
		local h = .2 - math.abs(i) * .015
		part(model, 'GrinRim', V3(.16, h + .1, .1), CF(x, yy, zz) * CFrame.Angles(0, x * .6, i * -.06), carve, SP)
		local g = part(model, 'Grin', V3(.15, h, .06), CF(x, yy, zz + .04) * CFrame.Angles(0, x * .6, i * -.06), glowC, NE, SMALL)
		g:SetAttribute('PickPulse', true)
		table.insert(grin, g)
	end
	for _, i in ipairs({ -2, 1, 3 }) do
		local x = i * .135
		local yy = H.Y - .34 + (x * x) * .55
		local up = i % 2 == 0
		part(model, 'GrinTooth', V3(.1, .1, .08), CF(x, yy + (up and .07 or -.07), zs(x, yy - H.Y) + .05) * CFrame.Angles(0, x * .6, 0), orange, SP)
	end
	for i = 1, 3 do
		local x = (i - 2) * .26
		anim(blob(model, 'MouthFlame', V3(.07, .12, .03), CF(x, H.Y - .33 + x * x * .55, zs(x, -.33) + .05), hot, NE, SMALL), 'Shake', i * .7, V3(x, H.Y - .4, zs(x, -.4)))
	end
	local lamp = part(model, 'CandleLight', V3(.4, .4, .4), CF(H + V3(0, -.1, .3)), glowC, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'PumpkinGlow', glowC, 7.5, 1.3)
	local smoke = part(model, 'StemSmokeFX', V3(.3, .1, .3), CF(H + V3(0, RY + .1, 0)), glowC, SP, { Transparency = 1, CastShadow = false })
	emitter(smoke, 'PumpkinEmbers', FIRE_TEX, glowC, 3, .3, .8, 1.1, V3(0, 2.2, 0))

	-- lobe highlights on the front half, vines climbing from the collar onto the pumpkin
	for i = 0, N - 1 do
		local a = (i + .5) / N * math.pi * 2
		if math.cos(a) > -.2 then
			local d = V3(math.sin(a) * RX, 0, math.cos(a) * RZ)
			blob(model, 'LobeShine', V3(.12, RY * 1.1, .05), CFrame.lookAt(H + d * 1.04 + V3(0, .18, 0), H + d * 3), orange:Lerp(Color3.fromRGB(255, 210, 120), .45), SP, SMALL)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local prevC = V3(sx * .18, H.Y - RY - .05, .12)
		for k = 1, 5 do
			local a = k / 5 * 1.3
			local p = H + V3(sx * (.3 + math.sin(a) * .62), -RY * math.cos(a) * 1.02 + .04, math.cos(a) * .5 + .2)
			rod(model, 'ClimbVine', prevC, p, .09, shade(vine:Lerp(BLACK, .1), .08), SP)
			if k >= 2 then
				blob(model, 'ClimbLeaf', V3(.22, .05, .16), CF(p + V3(sx * .08, .02, .1)) * CFrame.Angles(.6, sx * .4, sx * .3), shade(vine, .1), SP)
			end
			prevC = p
		end
	end
	-- a candy-corn charm swinging from the hoop
	local cHang = H + V3(-.75, -RY - .18, .2)
	local corn = { part(model, 'CharmString', V3(.025, .24, .025), CF(cHang - V3(0, .12, 0)), Color3.fromRGB(60, 40, 30), FA, SMALL) }
	local cc = cHang - V3(0, .4, 0)
	for k, col in ipairs({ Color3.fromRGB(255, 250, 236), Color3.fromRGB(255, 150, 30), Color3.fromRGB(255, 214, 60) }) do
		local w = .26 - (k - 1) * .07
		local a, b = tri('CandyCorn', CF(cc - V3(0, (k - 2) * .1 + .02, 0)) * CFrame.Angles(0, 0, math.pi), w, .1, .1, col, SP)
		table.insert(corn, a)
		table.insert(corn, b)
	end
	for _, p in ipairs(corn) do
		anim(p, 'ScytheChain', 1.1, cHang)
	end

	-- IRON HOOP round the sides (XY plane) + the two striking faces --------------------------------------------------------
	local hoop = ring(model, 'Hoop', CF(H), RX + .06, .16, .34, 22, shade(iron, .06), CM, function(i) return i == 5 or i == 6 end)
	for i, p in ipairs(hoop) do
		if i % 3 == 0 then
			local out = (p.CFrame.Position - H).Unit
			nail(model, p.CFrame.Position + out * .08, out, iron:Lerp(WHITE, .2), .9)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local fc = CF(H + V3(sx * (RX + .2), 0, 0))
		part(model, 'StrikePlate', V3(.16, .9, .9), fc, shade(iron, .06), CM)
		part(model, 'StrikePlateRim', V3(.1, 1.0, 1.0), fc * CF(-sx * .08, 0, 0), shade(iron:Lerp(BLACK, .25), .06), CM)
		part(model, 'StrikeFace', V3(.06, .7, .7), fc * CF(sx * .1, 0, 0), shade(iron:Lerp(WHITE, .18), .05), ME, { Reflectance = .1 })
		for _, c in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			nail(model, fc.Position + V3(sx * .09, c[1] * .4, c[2] * .4), V3(-sx, 0, 0) * -1, iron:Lerp(WHITE, .3), .8)
		end
		for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local base = fc.Position + V3(sx * .12, c[1] * .24, c[2] * .24)
			part(model, 'StudBase', V3(.1, .2, .2), CF(base), iron, CM)
			spike(model, 'Stud', base + V3(sx * .04, 0, 0), V3(sx, 0, 0), V3(0, 0, 1), .2, .16, .16, iron:Lerp(WHITE, .25), ME)
		end
		part(model, 'StrapTop', V3(.5, .12, .3), CF(H + V3(sx * (RX - .12), RY - .02, 0)) * CFrame.Angles(0, 0, sx * -.7), shade(iron, .06), CM)
		part(model, 'StrapBottom', V3(.5, .12, .3), CF(H + V3(sx * (RX - .12), -RY + .02, 0)) * CFrame.Angles(0, 0, sx * .7), shade(iron, .06), CM)
	end

	-- STEM, LEAVES, TENDRIL on top ------------------------------------------------------------------------------------------
	local sTop = H + V3(0, RY * .86, 0)
	local stem = {}
	for k = 0, 3 do
		table.insert(stem, part(model, 'Stem', V3(.32 - k * .04, .2, .32 - k * .04), CF(sTop + V3(k * .05, .1 + k * .17, -k * .02)) * CFrame.Angles(.1 * k, k * .5, -.14 * k), shade(stemC, .1), WO))
	end
	table.insert(stem, part(model, 'StemTip', V3(.17, .18, .17), CF(sTop + V3(.26, .8, -.06)) * CFrame.Angles(0, .3, -.9), stemC:Lerp(BLACK, .2), WO))
	table.insert(stem, part(model, 'StemCurl', V3(.13, .13, .13), CF(sTop + V3(.4, .78, -.06)) * CFrame.Angles(0, .3, -1.6), stemC:Lerp(BLACK, .25), WO))
	for _, p in ipairs(stem) do
		anim(p, 'Antenna', 0, sTop)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local lp = sTop + V3(sx * .46, .2, sx * .12)
		local leaf = {}
		table.insert(leaf, blob(model, 'Leaf', V3(.78, .08, .56), CF(lp) * CFrame.Angles(0, sx * .5, sx * .25), shade(vine:Lerp(BLACK, .1), .08), SP))
		table.insert(leaf, blob(model, 'LeafLobe', V3(.42, .07, .36), CF(lp + V3(sx * .3, .04, .2)) * CFrame.Angles(0, sx * .9, sx * .2), shade(vine, .08), SP))
		table.insert(leaf, part(model, 'LeafVein', V3(.5, .02, .03), CF(lp + V3(0, .04, 0)) * CFrame.Angles(0, sx * .5, sx * .25), vine:Lerp(WHITE, .25), SP, SMALL))
		for _, p in ipairs(leaf) do
			anim(p, 'Fluff', sx)
		end
	end
	local tend = sTop + V3(-.1, .2, .12)
	local prev = tend
	for k = 1, 9 do
		local a = k * .8
		local r = .3 - k * .022
		local p = tend + V3(-.15 - math.cos(a) * r, .1 + k * .04 + math.sin(a) * r * .6, .1 + math.sin(a) * r * .5)
		anim(rod(model, 'Tendril', prev, p, .05, vine:Lerp(WHITE, .1), SP, SMALL), 'Curl', .2, tend)
		prev = p
	end

	-- VINE HANDLE: dark core, a vine wound round it, leaves and tendrils, twine grip ---------------------------------------
	local yB, yT = -half + .2, H.Y - RY + .05
	cylY(model, 'VineCore', yT - yB, .4, CF(0, (yB + yT) / 2, 0), Color3.fromRGB(78, 62, 40), WO)
	for k = 0, 3 do
		cylY(model, 'VineCoreKnot', .1, .44, CF(0, yB + .4 + k * 1.05, 0), Color3.fromRGB(80, 64, 40), WO)
	end
	local steps = 34
	local prevV = nil
	for k = 0, steps do
		local f = k / steps
		local yy = yB + .15 + f * (yT - yB - .25)
		if yy < -2.0 or yy > -.8 then
			local a = f * math.pi * 2 * 4.2
			local p = V3(math.cos(a) * .23, yy, math.sin(a) * .23)
			if prevV then
				rod(model, 'Vine', prevV, p, .14, shade(vine:Lerp(BLACK, .15), .1), SP)
			end
			prevV = p
			if k % 3 == 1 then
				local out = V3(math.cos(a), 0, math.sin(a))
				local leaf = blob(model, 'VineLeaf', V3(.34, .06, .24), CFrame.lookAt(p + out * .16, p + out * 2) * CFrame.Angles(math.pi / 2, 0, 0), shade(vine, .1), SP)
				leaf:SetAttribute('PickAmp', out.X >= 0 and 1 or -1)
				anim(leaf, 'PonyFin', k, p)
			end
		else
			prevV = nil
		end
	end
	for _, ty in ipairs({ .25, 1.2 }) do
		local base = V3(.2, ty, .05)
		local pv = base
		for k = 1, 6 do
			local a = k * 1.1
			local p = base + V3(.12 + math.cos(a) * (.16 - k * .018), k * .05, math.sin(a) * (.16 - k * .018))
			anim(rod(model, 'HandleTendril', pv, p, .04, vine:Lerp(WHITE, .15), SP, SMALL), 'Curl', ty, base)
			pv = p
		end
	end
	local prev2 = nil
	for k = 0, 40 do
		local f = k / 40
		local yy = yB + .2 + f * (yT - yB - .3)
		if yy < -2.05 or yy > -.75 then
			local a = -f * math.pi * 2 * 3.1 + 1.5
			local p = V3(math.cos(a) * .23, yy, math.sin(a) * .23)
			if prev2 then
				rod(model, 'Vine2', prev2, p, .07, shade(vine:Lerp(WHITE, .12), .08), SP)
			end
			prev2 = p
		else
			prev2 = nil
		end
	end
	-- a tiny pumpkin growing on the vine (bobs) and its leaf
	local tp = V3(.3, .65, .1)
	local tiny = {}
	for i = 0, 4 do
		local a = (i + .5) / 5 * math.pi * 2
		table.insert(tiny, blob(model, 'TinyLobe', V3(.16, .2, .14), CF(tp + V3(math.sin(a) * .08, 0, math.cos(a) * .08)) * CFrame.Angles(0, a, 0), shade(orange, .1), SP))
	end
	table.insert(tiny, part(model, 'TinyStem', V3(.05, .1, .05), CF(tp + V3(0, .13, 0)), stemC, WO, SMALL))
	table.insert(tiny, blob(model, 'TinyLeaf', V3(.18, .04, .12), CF(tp + V3(-.1, .14, 0)) * CFrame.Angles(0, 0, .4), vine, SP, SMALL))
	for _, q in ipairs(tiny) do
		anim(q, 'Bob', .4, tp)
	end
	-- twine grip
	for k = 0, 11 do
		local gy = -2.0 + k * .1
		part(model, 'Twine', V3(.45, .085, .45), CF(0, gy, 0) * CFrame.Angles(0, k * .4, (k % 2 == 0 and .12 or -.12)), shade(twine, .1), FA)
	end
	-- iron collar under the pumpkin
	cylY(model, 'NeckCollar', .2, .56, CF(0, yT - .12, 0), shade(iron, .06), CM)
	for k = 0, 3 do
		local a = k * math.pi / 2
		nail(model, V3(math.sin(a) * .29, yT - .12, math.cos(a) * .29), V3(math.sin(a), 0, math.cos(a)), iron:Lerp(WHITE, .2), .8)
	end

	-- POMMEL: a baby jack-o'-lantern ------------------------------------------------------------------------------------------
	local B = V3(0, -half - .1, 0)
	local baby = {}
	for i = 0, 5 do
		local a = (i + .5) / 6 * math.pi * 2
		table.insert(baby, blob(model, 'BabyLobe', V3(.3, .4, .26), CF(B + V3(math.sin(a) * .17, 0, math.cos(a) * .17)) * CFrame.Angles(0, a, 0), shade(orange, .1), SP))
	end
	for _, sx in ipairs({ -1, 1 }) do
		local a, b = tri('BabyEye', CF(B + V3(sx * .1, .05, .29)), .1, .09, .04, glowC, NE, SMALL)
		table.insert(baby, a)
		table.insert(baby, b)
	end
	table.insert(baby, part(model, 'BabyGrin', V3(.2, .05, .04), CF(B + V3(0, -.07, .29)), glowC, NE, SMALL))
	table.insert(baby, part(model, 'BabyStem', V3(.08, .1, .08), CF(B + V3(0, -.26, 0)), stemC, WO))
	for _, p in ipairs(baby) do
		anim(p, 'Bob', 1.3)
	end

	model:SetAttribute('BackC0', CF(.35, .15, .35))
	model:SetAttribute('DisplayScale', .82)
	return H + V3(-RX - .3, 0, 0), H + V3(RX + .3, 0, 0)
end
-- >>HW_PumpkinSmasher

-- <<HW_GhostScythe
-- GHOST SCYTHE (Mythic): a ghost bound to a reaper's scythe. The BLADE is the ghost itself: a translucent spectral
-- body stretched into a long crescent along a black-iron spine (riveted, with jagged teeth on its back), glowing from
-- within, a white-hot cutting edge and a soft aura, its wailing face (hollow eyes, an "O" mouth, little cheeks) at the
-- wide root and its tail curling off into wisps at the point. Iron chain bands shackle the body to the spine and two
-- chains hang from the head with broken cuffs. The HEAD is a riveted iron socket with a ring of ghost-blue rune
-- slits and a hooked back spike. The POLE is pale ash wood with knots, wound with three bands of spectral cloth and
-- iron rings; the grip is bandaged (one loose end flutters); the pommel is a little iron spirit lantern with a
-- ghost flame. Four wisps circle the head.
-- Motion (PickFX generic): chains swing (ScytheChain), wisps Orbit, the tail and its wisps wave (Wave), the face's
-- glow and the edge pulse (PickPulse), the lantern flame flickers (Shake), the bandage end flutters (ScytheTalisman).
-- Held like the Scarlet Anime Scythe: HandTilt 28 / HandYaw 45 so the Reap swing leads with the point.
DESIGNS.HW_GhostScythe = function(model, v, def, len, top)
	local rnd = rng(919)
	local shade = shader(rnd)
	local ash = rgb(v.Shaft)
	local ghost = rgb(v.Head)
	local glowC = rgb(v.Accent)
	local iron = rgb(v.Trim)
	local cloth = rgb(v.Cloth)
	local hot = Color3.fromRGB(235, 250, 255)
	local darkFace = Color3.fromRGB(16, 30, 54)
	local GLOW = { CastShadow = false }
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, len * .5 + .06, 0)         -- head centre

	-- POLE: ash segments with knots, spectral cloth bands, iron rings ---------------------------------------------------
	local yB, yT = -half + .1, H.Y - .5
	local y = yB
	while y < yT - .01 do
		local h = math.min(.5 + rnd() * .35, yT - y)
		cylY(model, 'Pole', h + .01, .38 + rnd() * .03, CF(0, y + h / 2, 0) * CFrame.Angles(0, rnd() * 6, 0), shade(ash, .12), WO)
		if rnd() < .5 then
			local a = rnd() * math.pi * 2
			blob(model, 'Knot', V3(.13, .17, .1), CF(math.cos(a) * .19, y + h * .5, math.sin(a) * .15) * CFrame.Angles(0, -a, 0), ash:Lerp(BLACK, .35), WO, SMALL)
		end
		y += h
	end
	for _, ry in ipairs({ -half + .25, -.6, .55, yT - .05 }) do
		cylY(model, 'IronRing', .1, .47, CF(0, ry, 0), shade(iron, .08), ME, { Reflectance = .08 })
	end
	-- spectral cloth bands (diagonal turns, translucent)
	for _, band in ipairs({ { .0, 4 }, { 1.05, 3 }, { 1.85, 5 } }) do
		for k = 0, band[2] - 1 do
			local by = band[1] + k * .11
			part(model, 'SpiritCloth', V3(.46, .08, .46), CF(0, by, 0) * CFrame.Angles(0, k * .5, .3), cloth, FA, { Transparency = .3, CastShadow = false })
		end
	end
	-- spirit cloth tails trailing from the bands
	for bi, band in ipairs({ { .0, 4 }, { 1.05, 3 }, { 1.85, 5 } }) do
		for t = 0, 1 do
			local a = (bi * 1.7 + t * 2.4)
			local at0 = V3(math.cos(a) * .24, band[1] + .02, math.sin(a) * .24)
			for k = 1, 3 do
				anim(part(model, 'SpiritTail', V3(.1 - k * .02, .2, .02), CF(at0 + V3(math.cos(a) * k * .05, -k * .17, math.sin(a) * k * .05)) * CFrame.Angles(0, -a + math.pi / 2, .1 * k), cloth, FA,
					{ Transparency = .25 + k * .12, CastShadow = false }), 'ScytheTalisman', bi + t, at0)
			end
		end
	end
	-- bandaged grip + a loose end
	for k = 0, 10 do
		part(model, 'Bandage', V3(.45, .09, .45), CF(0, -1.95 + k * .105, 0) * CFrame.Angles(0, k * .35, (k % 2 == 0 and .12 or -.12)), shade(Color3.fromRGB(64, 70, 84), .08), material('Leather', FA))
	end
	local tieAt = V3(.2, -.8, .12)
	for k = 1, 3 do
		anim(part(model, 'BandageEnd', V3(.09, .2, .02), CF(tieAt + V3(.03 * k, -k * .17, .04)) * CFrame.Angles(0, .3, .2 * k), Color3.fromRGB(200, 236, 255), FA, SMALL), 'ScytheTalisman', .6, tieAt)
	end
	-- POMMEL: iron spirit lantern with a ghost flame
	local L0 = V3(0, -half - .2, 0)
	part(model, 'LanternTop', V3(.36, .07, .36), CF(L0 + V3(0, .2, 0)), iron, ME)
	part(model, 'LanternBase', V3(.36, .07, .36), CF(L0 + V3(0, -.2, 0)), iron, ME)
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		part(model, 'LanternBar', V3(.045, .36, .045), CF(L0 + V3(c[1] * .15, 0, c[2] * .15)), iron, ME, SMALL)
	end
	part(model, 'LanternGlass', V3(.26, .32, .26), CF(L0), glowC:Lerp(WHITE, .5), GL, { Transparency = .55, CastShadow = false })
	spike(model, 'LanternSpike', L0 + V3(0, -.23, 0), V3(0, -1, 0), V3(0, 0, 1), .22, .12, .12, iron, ME)
	local lf = blob(model, 'LanternFlame', V3(.12, .2, .12), CF(L0 + V3(0, -.02, 0)), glowC, NE, GLOW)
	anim(lf, 'Shake', 0, L0 - V3(0, .1, 0))
	lf:SetAttribute('PickPulse', true)
	light(lf, 'LanternLight', glowC, 5, .8)

	-- HEAD: riveted iron socket, rune slits, the back spike ---------------------------------------------------------------
	part(model, 'Socket', V3(.7, .9, .56), CF(H), shade(iron, .06), SL)
	part(model, 'SocketCap', V3(.78, .14, .64), CF(H + V3(0, .5, 0)), shade(iron:Lerp(BLACK, .2), .06), SL)
	part(model, 'SocketNeck', V3(.52, .24, .52), CF(H + V3(0, -.55, 0)), shade(iron:Lerp(BLACK, .2), .06), SL)
	for _, sx in ipairs({ -1, 1 }) do
		for k = -1, 1 do
			nail(model, H + V3(sx * .36, k * .27, .1), V3(sx, 0, 0), iron:Lerp(WHITE, .25), .8)
		end
	end
	-- the spirit eye on the front plate: a ring of rune bits round a glowing gem
	part(model, 'FrontPlate', V3(.56, .56, .06), CF(H + V3(0, .04, .3)), shade(iron:Lerp(BLACK, .25), .05), SL)
	local gem = ball(model, 'SpiritGem', .22, CF(H + V3(0, .04, .33)), hot, NE, GLOW)
	gem:SetAttribute('PickPulse', true)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local r = part(model, 'RuneBit', V3(.05, .05, .03), CF(H + V3(math.cos(a) * .19, .04 + math.sin(a) * .19, .34)) * CFrame.Angles(0, 0, a), glowC, NE, GLOW)
		if k % 2 == 0 then r:SetAttribute('PickPulse', true) end
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(model, 'Flange', V3(.1, .7, .46), CF(H + V3(sx * .39, 0, 0)), shade(iron:Lerp(WHITE, .08), .05), SL)
		spike(model, 'CapSpike', H + V3(sx * .24, .56, 0), V3(sx * .3, 1, 0), V3(0, 0, 1), .26, .12, .12, iron, SL)
	end
	spike(model, 'CapSpike', H + V3(0, .56, 0), V3(0, 1, 0), V3(0, 0, 1), .34, .14, .14, iron, SL)
	for k = 0, 7 do -- a chain coiled round the socket neck
		local a = k * .9
		part(model, 'CoilChain', V3(.06, .15, .1), CF(math.cos(a) * .31, H.Y - .45 - k * .05, math.sin(a) * .27) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, k % 2 == 0 and 0 or math.pi / 2, math.pi / 2.4), shade(iron:Lerp(WHITE, .15), .05), ME, { CastShadow = false })
	end
	-- the hooked back spike (-X)
	local sb = H + V3(-.3, .1, 0)
	local prevS = sb
	for k = 1, 4 do
		local f = k / 4
		local p = sb + V3(-f * .9, f * f * -.4 + f * .15, 0)
		bar(model, 'BackSpike', prevS, p, .2 - f * .1, .16 - f * .06, shade(iron, .08), SL)
		prevS = p
	end
	spike(model, 'BackSpikeTip', prevS, V3(-.6, -1, 0), V3(0, 0, 1), .3, .12, .1, iron:Lerp(WHITE, .15), ME)

	-- BLADE: the ghost stretched along a cubic spine ----------------------------------------------------------------------
	local function bez(p0, p1, p2, p3, t) local u = 1 - t; return p0 * u * u * u + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t * t * t end
	local P0, P1, P2, P3 = H + V3(.3, .36, 0), H + V3(1.75, 1.2, 0), H + V3(3.35, .55, 0), H + V3(2.95, -1.95, 0)
	local function spineAt(t) return bez(P0, P1, P2, P3, math.clamp(t, 0, 1)) end
	local N = 22
	local function widthAt(t) return 1.08 * (1 - t) ^ .6 + .04 end
	local frames = {}
	for i = 1, N do
		local t = (i - .5) / N
		local pos = spineAt(t)
		local tan = (spineAt(t + .01) - spineAt(t - .01)).Unit
		frames[i] = { T = t, Pos = pos, Tan = tan, N = V3(tan.Y, -tan.X, 0), W = widthAt(t), Seg = (spineAt(i / N) - spineAt((i - 1) / N)).Magnitude }
	end
	local function band(f, name, a, b, depth, color, mat, props, lenK, z)
		local c = f.Pos + f.N * (a + b) * .5 + V3(0, 0, z or 0)
		local stretch = 1 + math.max(0, .5 - (a + b) * .5) * .25
		return part(model, name, V3(f.Seg * (lenK or 1.14) * stretch, math.max(.02, b - a), depth), CFrame.fromMatrix(c, f.Tan, f.N, f.Tan:Cross(f.N)), color, mat, props)
	end
	local edges = {}
	for i, f in ipairs(frames) do
		local w, t = f.W, f.T
		local rim = math.max(.08, math.min(.16, w * .2))
		band(f, 'BladeSpine', -.04 - rnd() * .05, rim, .24 - t * .08, shade(iron, .1), SL, nil, 1.08)
		if i % 2 == 0 and t < .9 then
			band(f, 'SpineTooth', -.15 - rnd() * .05, -.03, .14, shade(iron:Lerp(BLACK, .2), .08), SL, nil, .45)
		end
		if i % 3 == 1 and t < .8 then
			band(f, 'SpineRivet', rim * .35, rim * .35 + .05, .27 - t * .08, iron:Lerp(WHITE, .3), ME, GLOW, .2)
		end
		band(f, 'GhostBody', rim, w * .8, .2 - t * .08, shade(ghost, .04), GL, { Transparency = .1, CastShadow = false }, 1.0)
		band(f, 'GhostCore', rim + w * .1, w * .62, .07, glowC, NE, { Transparency = .45, CastShadow = false }, 1.0)
		local e = band(f, 'BladeEdge', w * .8, w, .07, hot, NE, GLOW)
		e:SetAttribute('PickPulse', true)
		table.insert(edges, e)
		band(f, 'BladeAura', w, w + .1, .03, glowC, NE, { CastShadow = false, Transparency = .6 })
	end
	-- the face at the root (front +Z)
	do
		local f = frames[3]
		local c = f.Pos + f.N * f.W * .46
		local z = (.2 - f.T * .08) / 2 + .03
		local up = -f.N
		local function onFace(dx, dy) return c + f.Tan * dx + up * dy + V3(0, 0, z) end
		for _, sx in ipairs({ -1, 1 }) do
			blob(model, 'GhostEye', V3(.16, .24, .08), CFrame.fromMatrix(onFace(sx * .17, .1), f.Tan, up, f.Tan:Cross(up)) * CFrame.Angles(0, 0, sx * .2), darkFace, SP, SMALL)
			ball(model, 'GhostEyeGlint', .045, CF(onFace(sx * .17 + .03, .16) + V3(0, 0, .04)), WHITE, NE, SMALL)
			blob(model, 'GhostCheek', V3(.1, .05, .03), CFrame.fromMatrix(onFace(sx * .3, -.06), f.Tan, up, f.Tan:Cross(up)), Color3.fromRGB(170, 220, 255), NE, { Transparency = .3, CastShadow = false })
		end
		blob(model, 'GhostMouth', V3(.14, .22, .08), CFrame.fromMatrix(onFace(0, -.2), f.Tan, up, f.Tan:Cross(up)), darkFace, SP, SMALL)
		-- back of the head on -Z: two darker eye hollows seen through the glass
		for _, sx in ipairs({ -1, 1 }) do
			blob(model, 'GhostEyeBack', V3(.14, .2, .05), CFrame.fromMatrix(c + f.Tan * sx * .17 + up * .1 - V3(0, 0, z), f.Tan, up, f.Tan:Cross(up)), darkFace, SP, SMALL)
		end
	end
	light(edges[math.floor(N * .4)], 'GhostLight', glowC, 7.5, 1.1)
	local mist = part(model, 'GhostMistFX', V3(1, 1, .2), CF(frames[math.floor(N * .4)].Pos), glowC, SP, { Transparency = 1, CastShadow = false })
	emitter(mist, 'GhostMist', SMOKE_TEX, glowC:Lerp(WHITE, .4), 3, .6, .5, 1.6, V3(0, .8, 0))
	-- more lost souls faintly inside the blade (tiny eye pairs) and two little ghost hands reaching out of the edge
	for _, idx in ipairs({ 9, 14 }) do
		local f = frames[idx]
		local c = f.Pos + f.N * f.W * .45
		local z = (.2 - f.T * .08) / 2 + .02
		for _, sx in ipairs({ -1, 1 }) do
			blob(model, 'LostSoulEye', V3(.06, .09, .03), CF(c + f.Tan * sx * .07 + V3(0, 0, z)), Color3.fromRGB(60, 110, 170), SP, { Transparency = .35, CastShadow = false })
		end
		blob(model, 'LostSoulMouth', V3(.05, .07, .03), CF(c + f.N * .1 + V3(0, 0, z)), Color3.fromRGB(60, 110, 170), SP, { Transparency = .35, CastShadow = false })
	end
	for _, idx in ipairs({ 6, 11 }) do
		local f = frames[idx]
		local base = f.Pos + f.N * (f.W + .02)
		local hand = {}
		table.insert(hand, blob(model, 'GhostArm', V3(.12, .32, .1), CFrame.fromMatrix(base + f.N * .14, f.Tan, f.N, f.Tan:Cross(f.N)), ghost:Lerp(WHITE, .3), NE, { Transparency = .35, CastShadow = false }))
		for k = -1, 1 do
			table.insert(hand, blob(model, 'GhostFinger', V3(.05, .14, .05), CFrame.fromMatrix(base + f.N * .34 + f.Tan * k * .05, f.Tan, f.N, f.Tan:Cross(f.N)) * CFrame.Angles(0, 0, k * .3), ghost:Lerp(WHITE, .4), NE, { Transparency = .3, CastShadow = false }))
		end
		for _, q in ipairs(hand) do
			anim(q, 'Jiggle', idx, base)
		end
	end
	-- the tail: the point curls off into wisps
	do
		local last = frames[N]
		local tip = last.Pos + last.Tan * last.Seg * .45
		spike(model, 'BladeTipSpine', tip, last.Tan, last.N, .36, .12, .16, iron, SL)
		spike(model, 'BladeTipEdge', tip + last.N * .05, last.Tan, last.N, .48, .1, .06, hot, NE, GLOW)
		local tail = tip + last.Tan * .3
		for k = 1, 4 do
			local p = tail + V3(-.12 * k, -.1 * k + math.sin(k) * .08, .05 * (k % 2))
			anim(ball(model, 'TailWisp', .18 - k * .03, CF(p), glowC:Lerp(WHITE, .3), NE, { Transparency = .2 + k * .12, CastShadow = false }), 'Wave', k * .4)
		end
	end
	-- chain bands shackling the body to the spine
	for _, t in ipairs({ .34, .6 }) do
		local i = math.floor(t * N + .5)
		local f = frames[i]
		local w = f.W
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			local p = f.Pos + f.N * (w * .4 + math.cos(a) * w * .48) + V3(0, 0, math.sin(a) * .16)
			part(model, 'ChainBand', V3(.07, .16, .1), CFrame.fromMatrix(p, f.Tan, f.N, f.Tan:Cross(f.N)) * CFrame.Angles(a, k % 2 == 0 and 0 or math.pi / 2, 0), shade(iron:Lerp(WHITE, .1), .08), ME, { Reflectance = .08, CastShadow = false })
		end
	end
	-- two chains hanging from the head with broken cuffs
	for k, hx in ipairs({ -.22, .22 }) do
		local hang = H + V3(hx, -.62, .12)
		local links, bottom = chain(model, 'HangChain', hang, k == 1 and 7 or 5, .15, { shade(iron:Lerp(WHITE, .15), .05), shade(iron, .05) }, ME, 'ScytheChain', k * .9)
		local cuff = {}
		table.insert(cuff, part(model, 'Cuff', V3(.24, .08, .24), CF(bottom - V3(0, .03, 0)), iron, ME, { Reflectance = .08 }))
		table.insert(cuff, part(model, 'CuffHinge', V3(.08, .12, .08), CF(bottom + V3(.12, -.03, 0)), iron:Lerp(WHITE, .2), ME, SMALL))
		table.insert(cuff, part(model, 'CuffGlow', V3(.16, .03, .16), CF(bottom - V3(0, .07, 0)), glowC, NE, { Transparency = .3, CastShadow = false }))
		for _, p in ipairs(cuff) do
			anim(p, 'ScytheChain', k * .9, hang)
		end
	end

	-- WISPS circling the head ------------------------------------------------------------------------------------------------
	local center = H + V3(.4, .2, 0)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		local p = center + V3(math.cos(a) * 1.25, math.sin(k * 1.7) * .3, math.sin(a) * 1.25)
		local w = {}
		table.insert(w, ball(model, 'Wisp', .2, CF(p), hot, NE, { Transparency = .1, CastShadow = false }))
		table.insert(w, ball(model, 'WispHalo', .38, CF(p), glowC, NE, { Transparency = .65, CastShadow = false }))
		table.insert(w, blob(model, 'WispTail', V3(.12, .1, .34), CF(p) * CFrame.Angles(0, -a, 0) * CF(0, 0, .22), glowC, NE, { Transparency = .5, CastShadow = false }))
		for _, q in ipairs(w) do
			anim(q, 'Orbit', k / 4, center)
		end
	end

	model:SetAttribute('BackC0', CF(.15, -.35, .2))
	model:SetAttribute('HandYaw', 45)
	model:SetAttribute('HandTilt', 28)
	model:SetAttribute('DisplayScale', .8)
	return H + V3(-1.0, .3, 0), H + V3(2.95, -1.9, 0)
end
-- >>HW_GhostScythe

-- <<HW_LivingCoffin
-- LIVING COFFIN (Mythic): a coffin that is alive and hungry (a coffin "mimic" on a pole). The HEAD is a six-sided
-- coffin lying along X (studded iron cap at the head end -X, broad shoulders, tapering to the foot end +X, where a
-- bone dog skull is bolted on as the second striking face) built from mahogany planks with brass corners, side handles,
-- studs and a brass trim along the outline. The LID (+Z) hangs ajar on its lower long edge: the upper long edge is a
-- MOUTH - a jagged row of fangs on the body meeting a row on the lid, a red-to-orange glowing maw inside (embers rise
-- out of it, its light spills out), two yellow eyes with slit pupils peeking over the edge (they blink), a long red
-- tongue lolling out over the top and bony fingers curling over the foot half. A chain is wrapped diagonally across
-- the lid with a brass padlock; the lid keeps its crescent-moon emblem and the paw-print plaque. The POLE is iron-
-- banded wood wound with a chain, the grip black leather with red cross stitching, the pommel a brass "safety coffin"
-- bell on an iron arm; one more chain with a padlock dangles from the head end.
-- Motion (PickFX generic): the lid breathes / chews and snaps wide open on every strike (Curl round the hinge, teeth,
-- chain and padlock ride with it), the eyes blink (ScytheLidTop / ScytheLidBot) and look round (EyeLook), the tongue
-- lolls and flicks (Tongue), the fingers creep out (ClawOut), the maw glow pulses (PickPulse), chains and the bell
-- swing (ScytheChain).
DESIGNS.HW_LivingCoffin = function(model, v, def, len, top)
	local rnd = rng(1201)
	local shade = shader(rnd)
	local wood = rgb(v.Head)
	local dark = rgb(v.Shaft)
	local brass = rgb(v.Brass)
	local iron = rgb(v.Trim)
	local lining = rgb(v.Lining)
	local eyeC = rgb(v.Accent)                -- maw / hit glow (red-orange)
	local eyeY = Color3.fromRGB(255, 214, 90)    -- the eyes
	local fang = Color3.fromRGB(246, 240, 222)
	local boneC = Color3.fromRGB(232, 222, 196)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, top.Y + .88, 0)            -- coffin centre
	local X0, XS, X1 = -1.9, -1.05, 1.9        -- head end, shoulders, foot end
	local W0, WS, W1 = .5, .92, .3             -- half widths there
	local ZB, ZL = -.46, .24                   -- body back, lid seat
	local function xRange(a) -- the x interval where the outline's half width >= a
		local xa = a <= W0 and X0 or X0 + (a - W0) / (WS - W0) * (XS - X0)
		local xb = a <= W1 and X1 or XS + (WS - a) / (WS - W1) * (X1 - XS)
		return xa, xb
	end
	local function hw(x) -- the outline's half width at x
		return x < XS and W0 + (x - X0) / (XS - X0) * (WS - W0) or WS - (x - XS) / (X1 - XS) * (WS - W1)
	end
	local RH = .13
	local rows = {}
	local j = 0
	while true do
		local yc = -WS + RH * (j + .5)
		if yc > WS then break end
		table.insert(rows, yc)
		j += 1
	end

	-- BODY: plank rows (voxel outline), the satin lining under the lid, battens on the back --------------------------
	for _, yc in ipairs(rows) do
		local xa, xb = xRange(math.abs(yc))
		part(model, 'CoffinPlank', V3(xb - xa, RH - .008, ZL - ZB), CF(H + V3((xa + xb) / 2, yc, (ZB + ZL) / 2)), shade(wood, .12), WO)
		local la, lb = xRange(math.abs(yc) + .06)
		if lb - la > .1 then
			if yc > 0 then -- the upper half: the glowing maw (deep red down in the throat, orange toward the lips)
				local k = math.clamp(yc / WS, 0, 1)
				local m = part(model, 'Maw', V3(lb - la, RH, .02), CF(H + V3((la + lb) / 2, yc, ZL - .005)), Color3.fromRGB(150, 16, 10):Lerp(Color3.fromRGB(255, 120, 30), k), NE, SMALL)
				if k > .5 then m:SetAttribute('PickPulse', true) end
			else
				part(model, 'Lining', V3(lb - la, RH, .02), CF(H + V3((la + lb) / 2, yc, ZL - .005)), shade(lining, .06), FA, SMALL)
			end
		end
	end
	for _, bx in ipairs({ -.95, .55 }) do
		local a = WS - .06
		part(model, 'Batten', V3(.16, a * 2 - .1, .06), CF(H + V3(bx, 0, ZB - .03)), shade(dark, .08), WO)
	end
	-- brass handles on both long sides
	for _, sy in ipairs({ -1, 1 }) do
		for _, hx in ipairs({ -.55, .45 }) do
			local xa = hx
			local edge = sy * (WS - .02 - (hx > XS and (hx - XS) / (X1 - XS) * (WS - W1) or 0))
			local p = H + V3(xa, edge + sy * .1, (ZB + ZL) / 2)
			part(model, 'Handle', V3(.42, .05, .07), CF(p), brass, ME, { Reflectance = .12 })
			for _, ex in ipairs({ -.19, .19 }) do
				part(model, 'HandleBracket', V3(.06, .1, .08), CF(p + V3(ex, -sy * .05, 0)), brass:Lerp(BLACK, .2), ME)
			end
		end
	end
	-- brass studs along both long sides
	for k = 0, 8 do
		local x = X0 + .15 + k / 8 * (X1 - X0 - .3)
		local a = x < XS and W0 + (x - X0) / (XS - X0) * (WS - W0) or WS - (x - XS) / (X1 - XS) * (WS - W1)
		for _, sy in ipairs({ -1, 1 }) do
			if not (math.abs(x + .55) < .3 or math.abs(x - .45) < .3) then
				ball(model, 'SideStud', .07, CF(H + V3(x, sy * (a + .01), ZL - .08)), brass:Lerp(BLACK, .1), ME, SMALL)
				ball(model, 'SideStud', .07, CF(H + V3(x, sy * (a + .01), ZB + .1)), brass:Lerp(BLACK, .1), ME, SMALL)
			end
		end
	end
	-- striking caps: iron plates on both ends, studs at the head end
	for _, e in ipairs({ { X0, W0, -1 }, { X1, W1, 1 } }) do
		local x, w, sx = e[1], e[2], e[3]
		local cap = H + V3(x + sx * .05, 0, (ZB + ZL + .14) / 2)
		part(model, 'EndCap', V3(.1, w * 2 + .06, ZL - ZB + .2), CF(cap), shade(iron, .06), CM)
		part(model, 'EndCapFace', V3(.06, w * 2 - .12, ZL - ZB), CF(cap + V3(sx * .06, 0, 0)), shade(iron:Lerp(WHITE, .15), .05), ME, { Reflectance = .08 })
		if sx < 0 then
			for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }, { 0, 0 } }) do
				local b = cap + V3(sx * .08, c[1] * w * .5, c[2] * .2)
				spike(model, 'CapStud', b, V3(sx, 0, 0), V3(0, 0, 1), .24, .18, .18, iron:Lerp(WHITE, .2), ME)
			end
		end
	end
	-- the clamp where the pole enters the bottom edge
	local clampY = H.Y - (WS - (0 - XS) / (X1 - XS) * (WS - W1)) - .06
	part(model, 'Clamp', V3(.7, .24, ZL - ZB + .18), CF(0, clampY, H.Z + (ZB + ZL) / 2), shade(iron, .06), CM)
	for _, z in ipairs({ 1, -1 }) do
		part(model, 'ClampPlate', V3(.5, .5, .05), CF(0, clampY + .2, H.Z + (z > 0 and ZL + .02 or ZB - .025)), shade(iron:Lerp(BLACK, .15), .05), CM)
		for _, bx in ipairs({ -.17, .17 }) do
			nail(model, V3(bx, clampY + .25, H.Z + (z > 0 and ZL + .05 or ZB - .05)), V3(0, 0, z), iron:Lerp(WHITE, .3), .9)
		end
	end

	-- THE MOUTH along the upper long edge: fangs on the body, the maw's lips glowing, eyes, tongue, fingers -----------------
	local eyeXs = { -.95, -.55 }
	local function nearEye(x) for _, ex in ipairs(eyeXs) do if math.abs(x - ex) < .17 then return true end end return false end
	for k = 0, 19 do
		local x = X0 + .22 + k / 19 * (X1 - X0 - .5)
		if not nearEye(x) then
			local big = k % 4 == 1
			spike(model, big and 'BodyFang' or 'BodyTooth', H + V3(x, hw(x) - .08, ZL - .01), V3(0, 0, 1), V3(0, 1, 0), big and .2 or .14, .12, .09, shade(fang, .05), SP)
		end
	end
	for k = 0, 9 do
		local x = X0 + .45 + k / 9 * (X1 - X0 - .9)
		local lip = part(model, 'MawLip', V3(.36, .05, .02), CF(H + V3(x, hw(x) - .16, ZL + .012)), Color3.fromRGB(255, 176, 70), NE, SMALL)
		lip:SetAttribute('PickPulse', true)
	end
	-- two eyes peeking over the edge (slit pupils look round; lids blink)
	for i, ex in ipairs(eyeXs) do
		local ec = H + V3(ex, hw(ex) + .03, ZL + .15)
		local e = ball(model, 'CoffinEye', .24, CF(ec), eyeY, NE, SMALL)
		e:SetAttribute('PickPulse', true)
		anim(part(model, 'CoffinPupil', V3(.05, .17, .03), CF(ec + V3(0, 0, .115)), Color3.fromRGB(40, 0, 4), SP, SMALL), 'EyeLook', i, ec)
		anim(part(model, 'CoffinGlint', V3(.04, .04, .02), CF(ec + V3(.05, .05, .118)), WHITE, NE, SMALL), 'EyeLook', i, ec)
		local slant = (i == 1 and -1 or 1) * .3 -- angry brows slanting toward each other
		anim(blob(model, 'CoffinLidTop', V3(.32, .17, .12), CF(ec + V3(0, .19, .08)) * CFrame.Angles(0, 0, slant), Color3.fromRGB(70, 16, 18), SP), 'ScytheLidTop', i * .7, ec)
		anim(blob(model, 'CoffinLidBot', V3(.3, .15, .1), CF(ec + V3(0, -.2, .07)), Color3.fromRGB(70, 16, 18), SP), 'ScytheLidBot', i * .7, ec)
	end
	-- the tongue lolling out over the top and down the side
	local tr = H + V3(.3, hw(.3) - .04, ZL + .1)
	local tpts = { tr, tr + V3(0, .2, .1), tr + V3(.01, .38, .06), tr + V3(.02, .48, -.1), tr + V3(.04, .47, -.3), tr + V3(.06, .38, -.46) }
	local tongue = {}
	for k = 1, #tpts - 1 do
		local w = .24 - k * .015
		table.insert(tongue, bar(model, 'Tongue', tpts[k], tpts[k + 1], w, .07, Color3.fromRGB(226, 76, 98):Lerp(Color3.fromRGB(190, 50, 74), k / 5), SP))
		table.insert(tongue, bar(model, 'TongueGroove', tpts[k], tpts[k + 1], .03, .075, Color3.fromRGB(160, 34, 56), SP, SMALL))
	end
	table.insert(tongue, blob(model, 'TongueTip', V3(.18, .08, .16), CF(tpts[#tpts] + V3(0, -.02, -.04)), Color3.fromRGB(190, 50, 74), SP))
	for _, p in ipairs(tongue) do
		anim(p, 'Tongue', .3, tr)
	end
	-- bony fingers curling over the foot half
	for k = 0, 3 do
		local fx = .85 + k * .12
		local base = H + V3(fx, hw(fx) - .38, ZL + .05)
		local finger = {}
		table.insert(finger, part(model, 'FingerBone', V3(.055, .3, .055), CF(base + V3(0, .1, 0)), boneC, SP, SMALL))
		table.insert(finger, part(model, 'FingerTip', V3(.05, .12, .05), CF(base + V3(0, .3, .05)) * CFrame.Angles(.9, 0, 0), boneC, SP, SMALL))
		table.insert(finger, part(model, 'Knuckle', V3(.07, .06, .07), CF(base + V3(0, .25, .015)), boneC:Lerp(BLACK, .08), SP, SMALL))
		for _, p in ipairs(finger) do
			anim(p, 'ClawOut', k * .25)
		end
	end
	local lamp = part(model, 'MawLight', V3(.3, .3, .1), CF(H + V3(-.2, WS - .3, ZL + .12)), eyeC, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'MawGlow', Color3.fromRGB(255, 96, 40), 7, 1.5)
	emitter(lamp, 'MawEmbers', FIRE_TEX, Color3.fromRGB(255, 120, 40), 3, .26, .8, 1, V3(0, 2.2, .6))

	-- THE SKULL on the foot end (a bone dog skull bolted on as the second striking face, snout +X) ----------------------
	local K = H + V3(X1 + .3, 0, -.02)
	part(model, 'SkullCollar', V3(.1, .7, .78), CF(H + V3(X1 + .04, 0, -.02)), shade(iron, .06), CM)
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		nail(model, H + V3(X1 + .1, c[1] * .26, -.02 + c[2] * .3), V3(1, 0, 0), iron:Lerp(WHITE, .3), .8)
	end
	part(model, 'SkullCranium', V3(.44, .52, .58), CF(K), shade(boneC, .05), SP)
	part(model, 'SkullDome', V3(.34, .14, .5), CF(K + V3(-.02, .32, 0)), shade(boneC, .05), SP)
	part(model, 'SkullBrow', V3(.12, .13, .66), CF(K + V3(.2, .15, 0)), shade(boneC, .05), SP)
	for _, sz in ipairs({ -1, 1 }) do
		part(model, 'SkullSocket', V3(.06, .2, .2), CF(K + V3(.23, .04, sz * .15)), Color3.fromRGB(30, 6, 6), SP, SMALL)
		local se = ball(model, 'SkullEye', .13, CF(K + V3(.25, .04, sz * .15)), eyeC, NE, SMALL)
		se:SetAttribute('PickPulse', true)
		part(model, 'SkullCheek', V3(.24, .12, .1), CF(K + V3(.14, -.12, sz * .3)), shade(boneC, .05), SP)
		wedge(model, 'SkullEar', V3(.1, .2, .14), CF(K + V3(-.1, .36, sz * .22)) * CFrame.Angles(sz * -.3, 0, 0), shade(boneC, .05), SP)
	end
	part(model, 'SkullSnout', V3(.36, .26, .32), CF(K + V3(.38, -.12, 0)), shade(boneC, .05), SP)
	part(model, 'SkullNose', V3(.05, .1, .15), CF(K + V3(.57, -.06, 0)), Color3.fromRGB(30, 6, 6), SP, SMALL)
	for t = -2, 2 do
		local f = math.abs(t) == 2
		part(model, 'SkullTooth', V3(.05, f and .13 or .07, .05), CF(K + V3(.5 - math.abs(t) * .03, -.28 - (f and .03 or 0), t * .07)), WHITE, SP, SMALL)
	end
	part(model, 'SkullJaw', V3(.34, .08, .28), CF(K + V3(.33, -.36, 0)), boneC:Lerp(BLACK, .1), SP)
	part(model, 'SkullCrack', V3(.02, .2, .03), CF(K + V3(.24, .2, -.08)) * CFrame.Angles(.5, 0, 0), Color3.fromRGB(90, 70, 56), SP, SMALL)

	-- LID: inset plank rows, raised panel, brass corners, moon emblem, nail border; hinged at the lower edge ----------------
	local hinge = H + V3(0, -WS + .02, ZL)
	local crack = CFrame.new(hinge) * CFrame.Angles(.2, 0, 0) * CFrame.new(-hinge) -- built ajar
	local lid = {}
	local function lp(p) p.CFrame = crack * p.CFrame; table.insert(lid, p); return p end
	for _, yc in ipairs(rows) do
		local xa, xb = xRange(math.abs(yc) + .03)
		if xb - xa > .1 then
			lp(part(model, 'LidPlank', V3(xb - xa, RH - .008, .14), CF(H + V3((xa + xb) / 2, yc, ZL + .07)), shade(wood:Lerp(WHITE, .04), .1), WO))
		end
	end
	for _, yc in ipairs(rows) do
		local xa, xb = xRange(math.abs(yc) + .18)
		if xb - xa > .1 and math.abs(yc) < WS - .16 then
			lp(part(model, 'LidPanel', V3(xb - xa, RH - .008, .05), CF(H + V3((xa + xb) / 2, yc, ZL + .165)), shade(dark:Lerp(wood, .5), .08), WO))
		end
	end
	for _, c in ipairs({ { X0, W0 }, { XS, WS }, { X1, W1 } }) do
		for _, sy in ipairs({ -1, 1 }) do
			lp(part(model, 'BrassCorner', V3(.16, .16, .17), CF(H + V3(c[1] + (c[1] == X0 and .06 or (c[1] == X1 and -.06 or 0)), sy * (c[2] - .06), ZL + .08)), brass, ME, { Reflectance = .15 }))
		end
	end
	for k = 0, 9 do
		local f = k / 9
		local x = X0 + .2 + f * (X1 - X0 - .4)
		local a = x < XS and W0 + (x - X0) / (XS - X0) * (WS - W0) or WS - (x - XS) / (X1 - XS) * (WS - W1)
		for _, sy in ipairs({ -1, 1 }) do
			local np = H + V3(x, sy * (a - .09), ZL + .145)
			lp(part(model, 'LidNail', V3(.06, .06, .03), CF(np), brass:Lerp(BLACK, .25), ME, SMALL))
		end
	end
	-- brass trim along the six edges of the lid (the coffin outline), dark trim on the back
	local corners = { V3(X0, -W0, 0), V3(XS, -WS, 0), V3(X1, -W1, 0), V3(X1, W1, 0), V3(XS, WS, 0), V3(X0, W0, 0) }
	for i = 1, 6 do
		local c0, c1 = corners[i], corners[i % 6 + 1]
		local in0 = V3(c0.X - math.sign(c0.X) * .05, c0.Y - math.sign(c0.Y) * .05, 0)
		local in1 = V3(c1.X - math.sign(c1.X) * .05, c1.Y - math.sign(c1.Y) * .05, 0)
		lp(bar(model, 'LidTrim', H + in0 + V3(0, 0, ZL + .15), H + in1 + V3(0, 0, ZL + .15), .07, .04, brass:Lerp(BLACK, .1), ME, { Reflectance = .12 }))
		bar(model, 'BackTrim', H + c0 + V3(0, 0, ZB - .015), H + c1 + V3(0, 0, ZB - .015), .08, .04, shade(dark, .05), WO)
	end
	-- crescent moon emblem + two little stars
	local mc = H + V3(-.6, .18, ZL + .2)
	lp(cylZ(model, 'MoonEmblem', .04, .46, CF(mc), brass, ME, { Reflectance = .2 }))
	lp(cylZ(model, 'MoonShadow', .05, .4, CF(mc + V3(.11, .06, .005)), shade(dark:Lerp(wood, .5), .02), WO))
	for _, st in ipairs({ { .28, .2, .1 }, { .32, -.16, .07 } }) do
		local sp = mc + V3(st[1], st[2], 0)
		lp(part(model, 'Star', V3(st[3], st[3], .03), CF(sp) * CFrame.Angles(0, 0, math.pi / 4), brass, ME, { Reflectance = .2 }))
		lp(part(model, 'Star', V3(st[3] * .6, st[3] * 1.6, .03), CF(sp), brass, ME, { Reflectance = .2 }))
	end
	-- a brass plaque on the foot half
	lp(part(model, 'Plaque', V3(.7, .22, .03), CF(H + V3(.55, .27, ZL + .2)), brass:Lerp(BLACK, .1), ME, { Reflectance = .1 }))
	-- a paw print engraved on the plaque (the coffin's occupant was a very good dog)
	local pc = H + V3(.55, .26, ZL + .222)
	lp(blob(model, 'PawPad', V3(.1, .08, .02), CF(pc + V3(0, -.025, 0)), Color3.fromRGB(70, 40, 22), SP, SMALL))
	for q, o in ipairs({ { -.075, .03 }, { -.028, .06 }, { .028, .06 }, { .075, .03 } }) do
		lp(ball(model, 'PawToe', .035, CF(pc + V3(o[1], o[2], 0)), Color3.fromRGB(70, 40, 22), SP, SMALL))
	end
	for _, sx in ipairs({ -1, 1 }) do
		lp(part(model, 'PlaqueScrew', V3(.04, .04, .02), CF(H + V3(.55 + sx * .3, .27, ZL + .222)), brass:Lerp(BLACK, .3), ME, SMALL))
	end
	-- a chain wrapped diagonally across the lid (stapled at both ends) with a brass padlock in the middle
	local A, B = H + V3(-1.62, -hw(-1.62) + .1, ZL + .23), H + V3(1.5, hw(1.5) - .1, ZL + .23)
	local d = B - A
	local n = math.floor(d.Magnitude / .14)
	local rot = alignY(d)
	local chainC = { shade(iron:Lerp(WHITE, .25), .05), shade(iron:Lerp(WHITE, .1), .05) }
	for k = 0, n - 1 do
		local flat = k % 2 == 0
		lp(part(model, 'LidChain', flat and V3(.1, .17, .04) or V3(.04, .17, .1), CF(A + d * ((k + .5) / n)) * rot, chainC[k % 2 + 1], ME, { CastShadow = false, Reflectance = .08 }))
	end
	for _, e in ipairs({ A, B }) do
		lp(part(model, 'LidStaple', V3(.18, .08, .06), CF(e) * rot, iron, ME))
	end
	local lockAt = A + d * .5 - V3(0, .2, -.02)
	lp(part(model, 'LidPadlock', V3(.28, .24, .1), CF(lockAt), brass, ME, { Reflectance = .15 }))
	lp(part(model, 'LidPadlockShackle', V3(.04, .14, .05), CF(lockAt + V3(-.08, .16, 0)), iron:Lerp(WHITE, .35), ME, SMALL))
	lp(part(model, 'LidPadlockShackle', V3(.04, .14, .05), CF(lockAt + V3(.08, .16, 0)), iron:Lerp(WHITE, .35), ME, SMALL))
	lp(part(model, 'LidPadlockShackle', V3(.2, .04, .05), CF(lockAt + V3(0, .22, 0)), iron:Lerp(WHITE, .35), ME, SMALL))
	lp(part(model, 'LidKeyhole', V3(.04, .09, .02), CF(lockAt + V3(0, -.02, .055)), BLACK, SP, SMALL))
	-- the lid's own row of fangs (hanging from its upper edge, meeting the body's)
	for k = 0, 18 do
		local x = X0 + .3 + k / 18 * (X1 - X0 - .6)
		if not nearEye(x) then
			local big = k % 4 == 3
			lp(spike(model, big and 'LidFang' or 'LidTooth', H + V3(x, hw(x) - .1, ZL + .01), V3(0, 0, -1), V3(0, 1, 0), big and .2 or .14, .12, .09, shade(fang, .05), SP))
		end
	end
	for _, p in ipairs(lid) do
		anim(p, 'Curl', 0, hinge)
	end

	-- CHAINS with padlocks dangling from the coffin's lower corners ------------------------------------------------------------
	for k, cx in ipairs({ -1.3 }) do
		local hy = cx < XS and W0 + (cx - X0) / (XS - X0) * (WS - W0) or WS - (cx - XS) / (X1 - XS) * (WS - W1)
		local hang = H + V3(cx, -hy - .02, .05)
		part(model, 'ChainStaple', V3(.14, .06, .1), CF(hang + V3(0, .02, 0)), iron, ME)
		local links, bottom = chain(model, 'CoffinChain', hang, k == 1 and 6 or 4, .16, { shade(iron:Lerp(WHITE, .2), .05), shade(iron:Lerp(WHITE, .1), .05) }, ME, 'ScytheChain', k * 1.3)
		local lock = {}
		table.insert(lock, part(model, 'PadlockBody', V3(.26, .22, .12), CF(bottom - V3(0, .13, 0)), brass, ME, { Reflectance = .15 }))
		table.insert(lock, part(model, 'PadlockShackle', V3(.04, .14, .05), CF(bottom + V3(-.07, 0, 0)), iron:Lerp(WHITE, .3), ME, SMALL))
		table.insert(lock, part(model, 'PadlockShackle', V3(.04, .14, .05), CF(bottom + V3(.07, 0, 0)), iron:Lerp(WHITE, .3), ME, SMALL))
		table.insert(lock, part(model, 'PadlockShackle', V3(.18, .04, .05), CF(bottom + V3(0, .07, 0)), iron:Lerp(WHITE, .3), ME, SMALL))
		table.insert(lock, part(model, 'Keyhole', V3(.04, .08, .02), CF(bottom - V3(0, .13, -.065)), BLACK, SP, SMALL))
		for _, p in ipairs(lock) do
			anim(p, 'ScytheChain', k * 1.3, hang)
		end
	end

	-- POLE: dark wood, iron bands, carved grooves, a chain coil, leather grip ------------------------------------------------
	local yB, yT = -half + .1, clampY - .06
	cylY(model, 'Pole', yT - yB, .42, CF(0, (yB + yT) / 2, 0), dark:Lerp(wood, .6), WO)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		part(model, 'PoleGroove', V3(.03, yT - yB - .2, .03), CF(math.cos(a) * .205, (yB + yT) / 2, math.sin(a) * .205), dark:Lerp(BLACK, .2), WO, SMALL)
	end
	for _, by in ipairs({ -half + .3, -.55, .35, 1.25, yT - .15 }) do
		cylY(model, 'IronBand', .13, .5, CF(0, by, 0), shade(iron:Lerp(WHITE, .12), .06), CM)
		for q = 0, 3 do
			local a = q * math.pi / 2 + .4
			nail(model, V3(math.cos(a) * .26, by, math.sin(a) * .26), V3(math.cos(a), 0, math.sin(a)), iron:Lerp(WHITE, .3), .8)
		end
	end
	for k = 0, 11 do
		local a = k * .95
		part(model, 'PoleChain', V3(.07, .17, .11), CF(math.cos(a) * .25, yT - .35 - k * .06, math.sin(a) * .25) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, k % 2 == 0 and 0 or math.pi / 2, math.pi / 2.4), shade(iron:Lerp(WHITE, .2), .05), ME, SMALL)
	end
	for k = 0, 9 do
		part(model, 'GripLeather', V3(.48, .1, .48), CF(0, -1.95 + k * .115, 0) * CFrame.Angles(0, k * .3, 0), shade(Color3.fromRGB(34, 28, 30), .1), material('Leather', FA))
		if k % 2 == 0 then
			for _, s in ipairs({ -1, 1 }) do
				part(model, 'GripStitch', V3(.025, .1, .02), CF(0, -1.95 + k * .115, .25) * CFrame.Angles(0, 0, s * .7), eyeC:Lerp(BLACK, .2), FA, SMALL)
			end
		end
	end
	-- POMMEL: the coffin bell on a little iron arm
	local arm0 = V3(0, -half + .02, 0)
	part(model, 'BellArmBase', V3(.46, .12, .46), CF(arm0), iron, ME)
	bar(model, 'BellArm', arm0 - V3(0, .04, 0), arm0 + V3(.32, -.14, 0), .07, .07, iron, ME)
	local hook = arm0 + V3(.34, -.18, 0)
	local bell = {}
	table.insert(bell, part(model, 'BellHook', V3(.04, .1, .04), CF(hook - V3(0, .04, 0)), iron, ME, SMALL))
	local bc = hook - V3(0, .2, 0)
	table.insert(bell, cylY(model, 'BellTop', .08, .12, CF(bc + V3(0, .1, 0)), brass, ME, { Reflectance = .2 }))
	for q, d in ipairs({ .18, .22, .26, .3 }) do
		table.insert(bell, cylY(model, 'Bell', .06, d, CF(bc + V3(0, .06 - q * .05, 0)), brass:Lerp(WHITE, q * .03), ME, { Reflectance = .2 }))
	end
	table.insert(bell, cylY(model, 'BellLip', .04, .34, CF(bc - V3(0, .17, 0)), brass:Lerp(BLACK, .15), ME, { Reflectance = .2 }))
	table.insert(bell, ball(model, 'BellClapper', .07, CF(bc - V3(0, .22, 0)), iron, ME, SMALL))
	for _, p in ipairs(bell) do
		anim(p, 'ScytheChain', .3, hook)
	end

	model:SetAttribute('BackC0', CF(.4, -.2, .4))
	model:SetAttribute('DisplayScale', .8)
	return H + V3(X0 - .25, 0, 0), H + V3(X1 + .62, -.1, 0)
end
-- >>HW_LivingCoffin

-- <<HW_SoulReaper
-- SOUL REAPER (Secret): Death's own scythe. The HEAD is the Reaper himself: a voxel black-violet hood with a
-- pointed cowl and ragged hem, and inside it a bone skull with deep sockets, violet fire eyes and a grin of teeth.
-- From the hood sweeps a huge crescent BLADE: a jagged black-iron spine with thorn teeth, a deep purple panel shot
-- through with glowing soul veins and runes, a violet neon edge with a white-hot core and a soft aura, ending in a
-- long point; a black thorn hooks back on the other side. Five SOUL ORBS (pale violet cores in purple halos, each
-- with a little face and a wispy tail) circle the head. The POLE is obsidian black with violet rune inlays and
-- bone collars, a tattered black banner hangs under the hood, the grip is wrapped in black leather with violet
-- stitching, and the pommel is a bone claw clutching a soul gem.
-- Motion (PickFX generic): the soul orbs Orbit round the pole, the banner strips flutter (ScytheTalisman), the eyes,
-- veins, runes and edge pulse (PickPulse), the eye flames flicker (Shake), the jaw grins wider on a strike (GummyJaw).
-- Held like a scythe: HandTilt 28 / HandYaw 45.
DESIGNS.HW_SoulReaper = function(model, v, def, len, top)
	local rnd = rng(1777)
	local shade = shader(rnd)
	local black = rgb(v.Shaft)
	local steel = rgb(v.Head)
	local violet = rgb(v.Accent)
	local panel = rgb(v.Panel)
	local hoodC = rgb(v.Hood)
	local boneC = rgb(v.Bone)
	local hot = Color3.fromRGB(246, 226, 255)
	local pink = Color3.fromRGB(255, 150, 240)
	local GLOW = { CastShadow = false }
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, len * .5 + .1, 0)          -- hood centre
	local function at(x, y, z) return CF(H + V3(x, y, z)) end

	-- POLE: obsidian segments, violet rune inlays, bone collars ---------------------------------------------------------
	local yB, yT = -half + .15, H.Y - .55
	local y = yB
	local seg = 0
	while y < yT - .01 do
		local h = math.min(.62, yT - y)
		part(model, 'Pole', V3(.3, h - .02, .3), CF(0, y + h / 2, 0), shade(black, .1), SP, { Reflectance = .08 })
		for _, a in ipairs({ 0, math.pi / 2, math.pi, math.pi * 1.5 }) do
			part(model, 'PoleEdge', V3(.06, h - .06, .06), CF(math.sin(a + math.pi / 4) * .19, y + h / 2, math.cos(a + math.pi / 4) * .19), shade(black:Lerp(steel, .4), .08), SL)
		end
		if not (y > -2.1 and y < -.7) then
			local r = part(model, 'PoleRune', V3(.05, h * .5, .02), CF(0, y + h / 2, .155), violet, NE, GLOW)
			r:SetAttribute('PickPulse', true)
			part(model, 'PoleRuneBar', V3(.12, .03, .02), CF(0, y + h * (.35 + (seg % 3) * .1), .155), violet, NE, GLOW)
			part(model, 'PoleRuneBack', V3(.05, h * .4, .02), CF(0, y + h / 2, -.155), violet:Lerp(BLACK, .2), NE, GLOW)
		end
		y += h
		seg += 1
	end
	for _, cy in ipairs({ -half + .3, -2.15, -.6, .7, yT - .1 }) do
		cylY(model, 'BoneCollar', .12, .42, CF(0, cy, 0), shade(boneC, .06), SP)
		cylY(model, 'BoneCollarRim', .04, .46, CF(0, cy + .07, 0), boneC:Lerp(BLACK, .12), SP)
		for k = 0, 3 do
			local a = k * math.pi / 2
			wedge(model, 'CollarSpur', V3(.06, .12, .1), CF(math.sin(a) * .25, cy - .02, math.cos(a) * .25) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.pi, 0, 0), boneC, SP, SMALL)
		end
	end
	for k = 0, 11 do
		part(model, 'GripWrap', V3(.37, .09, .37), CF(0, -2.02 + k * .11, 0) * CFrame.Angles(0, k * .4, (k % 2 == 0 and .1 or -.1)), shade(Color3.fromRGB(30, 24, 36), .1), material('Leather', FA))
		if k % 3 == 1 then
			part(model, 'GripStitch', V3(.3, .02, .02), CF(0, -2.02 + k * .11, .19) * CFrame.Angles(0, 0, .5), violet, NE, GLOW)
		end
	end
	-- POMMEL: a bone claw clutching a soul gem
	local G = V3(0, -half - .18, 0)
	local gem = ball(model, 'SoulGem', .32, CF(G), violet:Lerp(WHITE, .25), NE, GLOW)
	gem:SetAttribute('PickPulse', true)
	ball(model, 'SoulGemShell', .42, CF(G), violet, GL, { Transparency = .55, CastShadow = false })
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		local p0 = G + V3(math.sin(a) * .1, .3, math.cos(a) * .1)
		local p1 = G + V3(math.sin(a) * .25, .08, math.cos(a) * .25)
		local p2 = G + V3(math.sin(a) * .2, -.16, math.cos(a) * .2)
		bar(model, 'Talon', p0, p1, .07, .07, shade(boneC, .06), SP)
		bar(model, 'Talon', p1, p2, .06, .06, shade(boneC, .06), SP)
		spike(model, 'TalonTip', p2, (G + V3(0, -.26, 0) - p2), V3(math.cos(a), 0, -math.sin(a)), .14, .06, .06, black, SP)
	end

	-- HOOD: a voxel cowl (an ellipsoid shell of cubes, the face opening to +Z, open underneath), a lighter rim round
	-- the opening and a peak sweeping up and back
	local hood = {}
	local HC = H + V3(0, .14, -.08)
	local A, B, Cz = .66, .84, .66
	local CELL = .17
	for i = -5, 5 do
		for j = -6, 6 do
			for k = -5, 5 do
				local p = V3(i * CELL, j * CELL, k * CELL)
				local q = math.sqrt((p.X / A) ^ 2 + (p.Y / B) ^ 2 + (p.Z / Cz) ^ 2)
				local face = p.Z > -.12 and (p.X / .46) ^ 2 + ((p.Y + .06) / .62) ^ 2 < 1
				if q <= 1 and q > 1 - CELL / .62 * 1.15 and not face and p.Y > -B * .78 then
					table.insert(hood, part(model, 'Hood', V3(CELL + .004, CELL + .004, CELL + .004), CF(HC + p), shade(hoodC, .14), FA))
				end
			end
		end
	end
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local px, py = math.cos(a) * .5, math.sin(a) * .66 - .06
		if py > -.55 then
			table.insert(hood, part(model, 'HoodRim', V3(.12, .12, .12), CF(HC + V3(px, py, math.sqrt(math.max(0, 1 - (px / A) ^ 2 - (py / B) ^ 2)) * Cz - .1)), shade(hoodC:Lerp(violet, .3), .08), FA))
		end
	end
	local peak = { V3(0, .78, -.3), V3(0, .9, -.5), V3(0, .98, -.7), V3(0, 1.02, -.88) }
	for k, p in ipairs(peak) do
		table.insert(hood, part(model, 'HoodPeak', V3(.34 - k * .06, .2, .24), CF(HC + p) * CFrame.Angles(-.4 - k * .12, 0, 0), shade(hoodC, .1), FA))
	end
	-- ragged hem hanging under the hood (flutters)
	for k = -4, 4 do
		local hx = k * .17
		local hl = .3 + rnd() * .35
		local hem = wedge(model, 'HoodHem', V3(.04, hl, .16), at(hx, -.78 - hl / 2, -.1 + math.abs(k) * .02) * CFrame.Angles(0, math.pi / 2 * (k % 2 == 0 and 1 or -1), math.pi), shade(hoodC, .1), FA)
		anim(hem, 'ScytheTalisman', k * .3, H + V3(hx, -.75, 0))
	end

	-- SKULL inside the hood -----------------------------------------------------------------------------------------------
	part(model, 'HoodShadow', V3(.9, 1.1, .1), at(0, .08, -.3), Color3.fromRGB(12, 6, 18), SP)
	part(model, 'SkullCranium', V3(.7, .58, .55), at(0, .2, 0), shade(boneC, .05), SP)
	part(model, 'SkullBrow', V3(.74, .12, .2), at(0, .32, .24), shade(boneC, .05), SP)
	part(model, 'SkullCheek', V3(.62, .2, .5), at(0, -.12, .02), boneC:Lerp(BLACK, .06), SP)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, 'SkullSocket', V3(.22, .2, .08), at(sx * .16, .14, .27), Color3.fromRGB(16, 6, 24), SP)
		local e = ball(model, 'SoulEye', .13, at(sx * .16, .14, .3), violet:Lerp(WHITE, .3), NE, GLOW)
		e:SetAttribute('PickPulse', true)
		local f = blob(model, 'EyeFlame', V3(.08, .2, .06), at(sx * .16, .3, .3), pink, NE, { Transparency = .2, CastShadow = false })
		anim(f, 'Shake', sx, H + V3(sx * .16, .2, .3))
		part(model, 'SkullCheekbone', V3(.1, .08, .2), at(sx * .3, -.03, .14), shade(boneC, .05), SP)
	end
	wedge(model, 'SkullNose', V3(.06, .12, .1), at(0, 0, .28), Color3.fromRGB(16, 6, 24), SP)
	part(model, 'SkullUpperJaw', V3(.46, .1, .3), at(0, -.24, .16), shade(boneC, .05), SP)
	for t = -3, 3 do
		part(model, 'SkullTooth', V3(.055, .09, .05), at(t * .062, -.31, .3 - math.abs(t) * .015), WHITE, SP, SMALL)
	end
	local jawPivot = H + V3(0, -.3, -.05)
	local jaw = { part(model, 'SkullJaw', V3(.44, .11, .32), at(0, -.42, .14), shade(boneC:Lerp(BLACK, .06), .05), SP) }
	for t = -2, 2 do
		table.insert(jaw, part(model, 'SkullLowerTooth', V3(.055, .08, .05), at(t * .065, -.35, .28 - math.abs(t) * .015), WHITE, SP, SMALL))
	end
	for _, p in ipairs(jaw) do
		anim(p, 'GummyJaw', 0, jawPivot)
	end
	local eyeLamp = part(model, 'EyeLamp', V3(.3, .2, .1), at(0, .14, .2), violet, SP, { Transparency = 1, CastShadow = false })
	light(eyeLamp, 'SoulLight', violet, 8, 1.3)

	-- BLADE: the crescent ----------------------------------------------------------------------------------------------------
	local function bez(p0, p1, p2, p3, t) local u = 1 - t; return p0 * u * u * u + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t * t * t end
	local P0, P1, P2, P3 = H + V3(.6, .55, -.05), H + V3(2.1, 1.45, -.05), H + V3(3.75, .6, -.05), H + V3(3.25, -2.3, -.05)
	local function spineAt(t) return bez(P0, P1, P2, P3, math.clamp(t, 0, 1)) end
	local N = 26
	local function widthAt(t) return 1.22 * (1 - t) ^ .58 + .03 end
	local frames = {}
	for i = 1, N do
		local t = (i - .5) / N
		local pos = spineAt(t)
		local tan = (spineAt(t + .01) - spineAt(t - .01)).Unit
		frames[i] = { T = t, Pos = pos, Tan = tan, N = V3(tan.Y, -tan.X, 0), W = widthAt(t), Seg = (spineAt(i / N) - spineAt((i - 1) / N)).Magnitude }
	end
	local function band(f, name, a, b, depth, color, mat, props, lenK, z)
		local c = f.Pos + f.N * (a + b) * .5 + V3(0, 0, z or 0)
		local stretch = 1 + math.max(0, .5 - (a + b) * .5) * .25
		return part(model, name, V3(f.Seg * (lenK or 1.14) * stretch, math.max(.02, b - a), depth), CFrame.fromMatrix(c, f.Tan, f.N, f.Tan:Cross(f.N)), color, mat, props)
	end
	local edges = {}
	for i, f in ipairs(frames) do
		local w, t = f.W, f.T
		local rim = math.max(.08, math.min(.18, w * .2))
		band(f, 'BladeSpine', -.03 - rnd() * .06, rim, .26 - t * .1, shade(steel, .12), SL, nil, 1.08)
		if i % 2 == 1 and t < .9 then
			local tb = f.Pos - f.N * .05
			spike(model, 'SpineThorn', tb, -f.N + f.Tan * -.35, V3(0, 0, 1), .26 - t * .12, .14, .1, shade(steel:Lerp(BLACK, .2), .06), SL)
		end
		band(f, 'BladeBand', rim, rim + w * .07, .21 - t * .07, shade(violet:Lerp(BLACK, .55), .06), SP)
		local p0, p1 = rim + w * .07, w * .7
		if p1 > p0 + .02 then
			band(f, 'BladePanel', p0, p1, .15 - t * .05, shade(panel, .06), SP)
		end
		local line = band(f, 'BladeLine', w * .7, w * .75, .12 - t * .04, violet, NE, GLOW)
		line:SetAttribute('PickPulse', true)
		band(f, 'BladeEdge', w * .75, w * .95, .07, violet:Lerp(pink, .3), NE, GLOW)
		local core = band(f, 'BladeEdgeHot', w * .95, w, .05, hot, NE, GLOW)
		table.insert(edges, core)
		band(f, 'BladeAura', w, w + .12, .03, violet, NE, { CastShadow = false, Transparency = .55 })
	end
	-- soul veins: glowing branching lines across the panel (both faces)
	for _, face in ipairs({ 1, -1 }) do
		for _, vt in ipairs({ .12, .3, .48, .64 }) do
			local i = math.floor(vt * N + .5)
			local f = frames[i]
			local z = face * ((.15 - f.T * .05) / 2 + .012)
			local a = f.Pos + f.N * (f.W * .18) + V3(0, 0, z)
			local b = f.Pos + f.N * (f.W * .62) + f.Tan * f.W * .2 + V3(0, 0, z)
			local vein = bar(model, 'SoulVein', a, b, .04, .015, violet, NE, GLOW)
			vein:SetAttribute('PickPulse', true)
			local m = (a + b) / 2
			bar(model, 'SoulVein', m, m + f.Tan * f.W * .25 - f.N * f.W * .05, .03, .015, violet:Lerp(pink, .3), NE, GLOW)
		end
	end
	-- runes along the panel (front): 3 x 3 pixel marks
	local RUNES = { { '#.#', '.#.', '#.#' }, { '###', '#..', '###' }, { '.#.', '###', '.#.' }, { '#..', '###', '..#' } }
	for k, rt in ipairs({ .2, .36, .52, .66 }) do
		local i = math.floor(rt * N + .5)
		local f = frames[i]
		local c = f.Pos + f.N * f.W * .42
		local z = (.15 - f.T * .05) / 2 + .015
		local up = -f.N
		local px = .07 * (1.1 - rt * .5)
		for r = 1, 3 do
			for cc = 1, 3 do
				if string.sub(RUNES[k][r], cc, cc) == '#' then
					local g = part(model, 'Rune', V3(px - .008, px - .008, .02), CFrame.fromMatrix(c + f.Tan * (cc - 2) * px + up * (2 - r) * px + V3(0, 0, z), f.Tan, up, f.Tan:Cross(up)), hot, NE, GLOW)
					g:SetAttribute('PickPulse', true)
				end
			end
		end
	end
	do
		local last = frames[N]
		local tipBase = last.Pos + last.Tan * last.Seg * .45
		spike(model, 'BladeTip', tipBase, last.Tan, last.N, .55, .14, .18, steel, SL)
		spike(model, 'BladeTipEdge', tipBase + last.N * .05, last.Tan, last.N, .66, .1, .06, hot, NE, GLOW)
	end
	local bladeFX = part(model, 'SoulMistFX', V3(1.2, 1.2, .2), CF(frames[math.floor(N * .4)].Pos + frames[math.floor(N * .4)].N * .4), violet, SP, { Transparency = 1, CastShadow = false })
	emitter(bladeFX, 'SoulSparks', SPARK_TEX, violet:Lerp(WHITE, .3), 5, .3, .8, 1.3, V3(0, 1.5, 0))
	-- the clamp joining hood and blade, the back thorn
	part(model, 'BladeClamp', V3(.36, .6, .44), at(.62, .45, -.05), shade(steel, .08), SL)
	for _, sz in ipairs({ -1, 1 }) do
		for k = -1, 1 do
			part(model, 'ClampRivet', V3(.06, .06, .04), at(.62, .45 + k * .18, -.05 + sz * .23), violet, NE, GLOW)
		end
	end
	local tb0 = H + V3(-.62, .3, -.1)
	local prevT = tb0
	for k = 1, 4 do
		local f = k / 4
		local p = tb0 + V3(-f * 1.0, f * .2 - f * f * .55, 0)
		bar(model, 'BackThorn', prevT, p, .22 - f * .12, .18 - f * .08, shade(steel, .1), SL)
		prevT = p
	end
	spike(model, 'BackThornTip', prevT, V3(-.5, -1, 0), V3(0, 0, 1), .36, .12, .1, steel:Lerp(violet, .3), SL)

	-- BANNER: tattered black cloth hanging under the hood ------------------------------------------------------------------
	local bTop = H.Y - .75
	local bannerHang = V3(0, bTop, .18)
	for k = 0, 4 do
		local bx = -.24 + k * .12
		local bl = .7 + rnd() * .5
		local strip = part(model, 'Banner', V3(.12, bl, .03), CF(bx, bTop - bl / 2, .2), shade(hoodC, .1), FA)
		anim(strip, 'ScytheTalisman', k * .25, bannerHang)
		local tear = wedge(model, 'BannerTear', V3(.03, .14, .12), CF(bx, bTop - bl - .07, .2) * CFrame.Angles(0, math.pi / 2, math.pi), shade(hoodC, .1), FA)
		anim(tear, 'ScytheTalisman', k * .25, bannerHang)
	end
	local sigil = part(model, 'BannerSigil', V3(.2, .2, .02), CF(0, bTop - .35, .225) * CFrame.Angles(0, 0, math.pi / 4), violet, NE, GLOW)
	anim(sigil, 'ScytheTalisman', .5, bannerHang)
	sigil:SetAttribute('PickPulse', true)
	cylY(model, 'BannerRod', .08, .7, CF(0, bTop + .02, .2) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), steel, ME)

	-- SOUL ORBS circling the head ------------------------------------------------------------------------------------------
	local center = H + V3(.3, .1, 0)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + .9
		local p = center + V3(math.cos(a) * 1.75, math.sin(k * 2.1) * .45, math.sin(a) * 1.75)
		local out = V3(math.cos(a), 0, math.sin(a))
		local face = CFrame.lookAt(p, p + out)
		local orb = {}
		table.insert(orb, ball(model, 'SoulOrb', .26, CF(p), hot, NE, { Transparency = .05, CastShadow = false }))
		table.insert(orb, ball(model, 'SoulHalo', .46, CF(p), violet, NE, { Transparency = .6, CastShadow = false }))
		table.insert(orb, blob(model, 'SoulTail', V3(.14, .12, .46), CFrame.lookAt(p, p + V3(-math.sin(a), 0, math.cos(a))) * CF(0, 0, .3), violet:Lerp(pink, .3), NE, { Transparency = .45, CastShadow = false }))
		for _, sx in ipairs({ -1, 1 }) do
			table.insert(orb, ball(model, 'SoulEye', .045, face * CF(sx * .05, .03, -.12), Color3.fromRGB(40, 10, 60), SP, SMALL))
		end
		table.insert(orb, ball(model, 'SoulMouth', .04, face * CF(0, -.04, -.12), Color3.fromRGB(40, 10, 60), SP, SMALL))
		for _, q in ipairs(orb) do
			anim(q, 'Orbit', k / 5, center)
		end
	end

	model:SetAttribute('BackC0', CF(.15, -.35, .2))
	model:SetAttribute('HandYaw', 45)
	model:SetAttribute('HandTilt', 28)
	model:SetAttribute('DisplayScale', .76)
	return H + V3(-1.2, .2, 0), H + V3(3.25, -2.2, 0)
end
-- >>HW_SoulReaper

-- @@DESIGNS_END

---------------------------------------------------------------------------------------------------------------------
-- BUILD
---------------------------------------------------------------------------------------------------------------------
local Models = nil
local stockPickaxe = nil -- MiningModels.Pickaxe before Register wrapped it
local function models()
	if not Models then
		Models = require(RS:WaitForChild('Mining'):WaitForChild('MiningModels'))
	end
	if not stockPickaxe then
		stockPickaxe = Models.Pickaxe
	end
	return Models
end

local function isSkinDef(def)
	return type(def) == 'table' and type(def.Visual) == 'table' and DESIGNS[def.Visual.Kind] ~= nil
end
Skins.IsSkinDef = isSkinDef

function Skins.Build(id, level)
	local def = type(id) == 'string' and Skins.ById[id] or id
	if type(def) ~= 'table' then
		return nil
	end
	level = level or 1
	if not isSkinDef(def) then
		models()
		return stockPickaxe(def, level)
	end
	local v = def.Visual
	local kind = v.Kind
	local model = Instance.new('Model')
	model.Name = 'Pickaxe'
	local len = v.Length or 4.2
	local handle = part(model, 'Handle', V3(.32, len, .32), CFrame.identity, rgb(v.Shaft, { 120, 82, 48 }), material(v.ShaftMaterial or 'Wood'), { Massless = true })
	model.PrimaryPart = handle
	model:SetAttribute('Kind', kind)
	model:SetAttribute('Theme', def.Theme or 'Wood')
	model:SetAttribute('Level', level)
	model:SetAttribute('SkinId', def.SkinId or def.Id)
	local top = CF(0, len * .5 - .2, 0)
	local a, b = DESIGNS[kind](model, v, def, len, top)
	if a and b then
		trailPoints(handle, a, b)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA('BasePart') then
			d.Massless = true
			d:SetAttribute('PickaxeLevel', level)
			if d ~= handle and d:GetAttribute('PickAnim') then
				d:SetAttribute('PickBase', handle.CFrame:ToObjectSpace(d.CFrame))
			end
		end
	end
	return model
end

---------------------------------------------------------------------------------------------------------------------
-- SOUND KITS (MiningAudio.Kits rows: {soundId, volume, speed, effects?, at=, dur=, attack=, fade=, loop=, to=, ramp=})
---------------------------------------------------------------------------------------------------------------------
local KITS = nil
local function buildKits(Audio)
	local TICK, PING, KNOCK, LAND, WIND, WATER, SPLAT, CLICK, SLASH, LUNGE, SHEATH, HOP = table.unpack(Audio.Sources)
	local function whoosh(speed, vol, dur, fx, at)
		return { WIND, vol, speed, fx, at = at, dur = dur, attack = math.min(.04, dur * .3), fade = dur * .6, loop = true }
	end
	local function join(...)
		local out = {}
		for _, list in ipairs({ ... }) do
			for _, row in ipairs(list) do
				table.insert(out, row)
			end
		end
		return out
	end
	local AIRY = { EqualizerSoundEffect = { LowGain = -8, MidGain = 2, HighGain = 4 }, FlangeSoundEffect = { Depth = .5, Mix = .6, Rate = 3 } }
	local THUMP = { EqualizerSoundEffect = { LowGain = 10, MidGain = -2, HighGain = -30 }, DistortionSoundEffect = { Level = .45 } }
	local DIRT = { EqualizerSoundEffect = { LowGain = 8, MidGain = 0, HighGain = -18 } }
	local CLANG = { ReverbSoundEffect = { DecayTime = 1.2, WetLevel = -6 }, EqualizerSoundEffect = { LowGain = 2, MidGain = 4, HighGain = -6 } }
	local WAIL = { ChorusSoundEffect = { Depth = .45, Mix = .7, Rate = 3 }, ReverbSoundEffect = { DecayTime = 2.6, WetLevel = -3 },
		EqualizerSoundEffect = { LowGain = -6, MidGain = 3, HighGain = -4 } }
	local HAUNT = { TremoloSoundEffect = { Depth = .6, Duty = .5, Frequency = .5 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 2, HighGain = -10 } }
	local RATTLE = { TremoloSoundEffect = { Depth = 1, Duty = .3, Frequency = 11 }, EqualizerSoundEffect = { LowGain = -8, MidGain = 4, HighGain = 0 } }
	KITS = {}
	-- GRAVE SHOVEL: the spade bites dirt (a soft earthy thud under a dull iron clang); a perfect adds a ghostly
	-- chime, a crit a long ghost wail gliding down; idle: a faint haunted wind.
	KITS.HW_Grave = {
		Swing = { { HOP, .2, 1.0 }, whoosh(1.7, .2, .2, AIRY) },
		Hit = { { LAND, .45, .75, DIRT }, { SHEATH, .2, .5, CLANG }, { KNOCK, .3, .7 }, { WATER, .06, .5, DIRT, at = .02 } },
		Perfect = { { PING, .12, 1.1, WAIL, at = .05, to = .9, ramp = .3, dur = .35, loop = true } },
		Crit = { { LAND, .6, .55, THUMP }, { SHEATH, .3, .42, CLANG }, { KNOCK, .45, .6 },
			{ PING, .2, 1.2, WAIL, at = .05, to = .55, ramp = .7, dur = .85, fade = .35, loop = true } },
		Draw = { { SHEATH, .2, .65, CLANG }, { CLICK, .15, .6, nil, at = .06 } },
		Break = { { LAND, .45, .55, DIRT, at = .03 }, { PING, .1, .9, WAIL, at = .06, to = .5, ramp = .5, dur = .55, loop = true } },
		Inspect = join({ { SHEATH, .2, .7, CLANG }, { WIND, .07, .6, HAUNT, at = .3, dur = 1.6, attack = .4, fade = .5, loop = true } },
			{ { PING, .12, .9, WAIL, at = .9, to = 1.3, ramp = .5, dur = .6, loop = true }, { PING, .1, 1.3, WAIL, at = 1.6, to = .7, ramp = .6, dur = .7, loop = true } },
			{ { KNOCK, .22, .6, nil, at = 2.3 } }),
		Idle = { { WIND, .01, .5, HAUNT, loop = true } },
	}
	local BONE = { DistortionSoundEffect = { Level = .6 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 6, HighGain = -8 } }
	local CHIME = { ReverbSoundEffect = { DecayTime = 1.8, WetLevel = -4 } }
	local CRUNCH = { DistortionSoundEffect = { Level = .85 }, EqualizerSoundEffect = { LowGain = 2, MidGain = 6, HighGain = -6 } }
	local function rattle(n, base, gap, vol, start, fx)
		local rows = {}
		for i = 1, n do
			table.insert(rows, { CLICK, vol, base * (1 + (i % 3) * .09), fx or BONE, at = (start or 0) + (i - 1) * gap })
		end
		return rows
	end
	-- BONE PICKAXE: dry bone knocks and a clattering rattle; a crit cracks bone; the inspect chatters its teeth and
	-- lets out a little dog howl; idle / run: a faint rattle of loose bones.
	KITS.HW_Bone = {
		Swing = { { HOP, .2, 1.4 }, whoosh(2.4, .18, .16, AIRY), { CLICK, .07, 1.1, RATTLE, at = .02, dur = .18, loop = true } },
		Hit = join({ { KNOCK, .42, 1.25 }, { CLICK, .36, .75, BONE } }, rattle(3, .9, .035, .14, .03)),
		Perfect = { { CLICK, .2, 1.3, BONE, at = .05 }, { PING, .08, 1.6, CHIME, at = .06 } },
		Crit = join({ { LAND, .5, .7, THUMP }, { KNOCK, .45, .9 }, { CLICK, .4, .55, CRUNCH } }, rattle(6, .85, .04, .18, .04)),
		Draw = join({ { HOP, .14, 1.3 } }, rattle(4, 1, .05, .16, .02)),
		Break = rattle(5, .8, .04, .15, .03),
		Inspect = join(rattle(10, 1.1, .06, .12, .15, RATTLE), { { PING, .16, .7, WAIL, at = 1.0, to = 1.05, ramp = .5, dur = .95, fade = .35, loop = true },
			{ PING, .1, 1.05, WAIL, at = 1.55, to = .8, ramp = .4, dur = .5, loop = true } }, rattle(3, .9, .05, .14, 2.2)),
		Idle = { { CLICK, .02, .5, RATTLE, loop = true } },
		Run = { { CLICK, .05, .9, RATTLE, loop = true } },
	}
	local SQUISH = { EqualizerSoundEffect = { LowGain = 8, MidGain = -2, HighGain = -16 } }
	local GOO = { EqualizerSoundEffect = { LowGain = 8, MidGain = -4, HighGain = -20 }, FlangeSoundEffect = { Depth = .4, Mix = .5, Rate = 2 } }
	local LAUGH = { DistortionSoundEffect = { Level = .7 }, EqualizerSoundEffect = { LowGain = 0, MidGain = 8, HighGain = -10 }, TremoloSoundEffect = { Depth = .5, Duty = .5, Frequency = 30 } }
	local HOARSE = { DistortionSoundEffect = { Level = .9 }, EqualizerSoundEffect = { LowGain = 4, MidGain = 6, HighGain = -14 }, TremoloSoundEffect = { Depth = .7, Duty = .5, Frequency = 26 } }
	local CRACKLE = { DistortionSoundEffect = { Level = .85 }, TremoloSoundEffect = { Depth = 1, Duty = .3, Frequency = 17 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = 2 } }
	local function cackle(n, base, gap, vol, start, fx)
		local rows = {}
		for i = 1, n do
			local at = (start or 0) + (i - 1) * gap
			local p = base * (1 - (i - 1) * .035)
			table.insert(rows, { PING, vol, p, fx or LAUGH, at = at, dur = gap * .7, fade = gap * .3, to = p * .78, ramp = gap * .7, loop = true })
			if i % 2 == 1 then
				table.insert(rows, { HOP, vol * .6, p * 1.6, nil, at = at })
			end
		end
		return rows
	end
	-- PUMPKIN SMASHER: a big squishy splat over a hollow thump; a crit bursts the pumpkin with a cackle; the
	-- candle inside crackles while it is held; the inspect is a wicked jack-o'-lantern laugh.
	KITS.HW_Pumpkin = {
		Swing = { { HOP, .22, .8 }, whoosh(1.2, .24, .26) },
		Hit = { { SPLAT, .42, .62, SQUISH }, { KNOCK, .4, .62, THUMP }, { LAND, .28, .75 }, { SPLAT, .12, 1.1, nil, at = .04 } },
		Perfect = { { SPLAT, .16, .95, nil, at = .05 }, { PING, .08, 1.3, CHIME, at = .06 } },
		Crit = join({ { SPLAT, .55, .45, GOO }, { LAND, .6, .5, THUMP }, { KNOCK, .5, .55 }, { SPLAT, .25, .8, nil, at = .08 } }, cackle(4, 1.05, .11, .16, .12)),
		Draw = { { SPLAT, .16, 1.15 }, { CLICK, .14, .7, nil, at = .05 }, { TICK, .05, 2.2, CRACKLE, at = .08, dur = .3, loop = true } },
		Break = join({ { SPLAT, .4, .5, GOO, at = .03 } }, cackle(3, 1, .1, .12, .1)),
		Inspect = join({ { TICK, .06, 2, CRACKLE, dur = 2.2, attack = .2, fade = .4, loop = true } }, cackle(3, .7, .22, .16, .6, HOARSE), cackle(4, .85, .11, .15, 1.5)),
		Idle = { { TICK, .008, 2.2, CRACKLE, loop = true } },
	}
	local RING = { ReverbSoundEffect = { DecayTime = 1.6, WetLevel = -4 }, EqualizerSoundEffect = { LowGain = -8, MidGain = 0, HighGain = 4 } }
	local SHINE = { ReverbSoundEffect = { DecayTime = 2.2, WetLevel = -3 }, EqualizerSoundEffect = { LowGain = -10, MidGain = 0, HighGain = 4 } }
	local FLUTTER = { TremoloSoundEffect = { Depth = .9, Duty = .45, Frequency = 17 }, EqualizerSoundEffect = { LowGain = -14, MidGain = -2, HighGain = 4 } }
	-- GHOST SCYTHE: a ringing spectral cut with a ghostly "woo" gliding off it; a crit is a long wail; the draw
	-- flutters and sighs; idle: a faint haunted breeze; run: a thin whistle.
	KITS.HW_Ghost = {
		Swing = { { SLASH, .3, 1.2, AIRY }, whoosh(2, .2, .24, AIRY), { PING, .05, 1.6, WAIL, to = 2.2, ramp = .2, dur = .25, loop = true } },
		Hit = { { SHEATH, .36, 1.25, RING }, { PING, .16, 1.8, WAIL, at = .01, to = 1.2, ramp = .3, dur = .4, loop = true }, { LAND, .2, 1.1, THUMP }, whoosh(3, .1, .2, AIRY, .02) },
		Perfect = { { PING, .14, 2.4, SHINE, at = .05 } },
		Crit = { { SHEATH, .4, 1, RING }, { LAND, .4, .8, THUMP }, { PING, .28, 1.5, WAIL, at = .03, to = .7, ramp = .8, dur = 1, fade = .4, loop = true },
			{ PING, .14, 2.2, SHINE, at = .08 }, { WIND, .1, 1.2, FLUTTER, at = .05, dur = .6, attack = .1, fade = .3, loop = true } },
		Draw = { { SHEATH, .26, 1.1, RING }, { WIND, .06, 1.5, FLUTTER, at = .05, dur = .4, attack = .1, fade = .25, loop = true },
			{ PING, .08, 2, WAIL, at = .1, to = 1.5, ramp = .3, dur = .4, loop = true } },
		Break = { { PING, .16, 1.4, WAIL, at = .04, to = .8, ramp = .6, dur = .7, loop = true }, { SHEATH, .2, .9, RING } },
		Inspect = join({ { WIND, .07, .9, HAUNT, dur = 2.3, attack = .4, fade = .5, loop = true } },
			{ { PING, .14, 1.2, WAIL, at = .4, to = 1.9, ramp = .6, dur = .8, loop = true }, { PING, .12, 1.9, WAIL, at = 1.2, to = 1, ramp = .7, dur = .8, loop = true } },
			rattle(5, .8, .07, .12, 1.9, RATTLE), { { SHEATH, .22, 1.2, RING, at = 2.3 } }),
		Idle = { { WIND, .012, .8, HAUNT, loop = true } },
		Run = { { WIND, .04, 1.8, AIRY, loop = true } },
	}
	local WOODY = { EqualizerSoundEffect = { LowGain = 4, MidGain = 2, HighGain = -14 } }
	local CREAK = { TremoloSoundEffect = { Depth = 1, Duty = .16, Frequency = .6 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 2, HighGain = 0 } }
	local CREAKY = { TremoloSoundEffect = { Depth = 1, Duty = .2, Frequency = 9 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = -6 } }
	local TOLL = { ReverbSoundEffect = { DecayTime = 4, WetLevel = -1, DryLevel = -2, Density = 1, Diffusion = 1 }, EqualizerSoundEffect = { LowGain = 6, MidGain = 0, HighGain = -10 } }
	local DOOM = { EqualizerSoundEffect = { LowGain = 10, MidGain = -6, HighGain = -30 }, ReverbSoundEffect = { DecayTime = 3, WetLevel = -2 } }
	local BREATH = { TremoloSoundEffect = { Depth = .85, Duty = .5, Frequency = .35 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 2, HighGain = -10 } }
	-- LIVING COFFIN: a heavy hollow wooden slam, the fanged lid snapping shut (a bony click), the lid creaking and the
	-- chains rattling; a perfect tolls a bell,
	-- a crit is a doom boom with a long creak; the inspect creaks the lid open, somebody knocks three times from
	-- inside and the little coffin bell rings; idle: a slow breath and a faint creak.
	KITS.HW_Coffin = {
		Swing = { { HOP, .2, .75 }, whoosh(1, .26, .3), { TICK, .06, .4, CREAKY, dur = .25, loop = true, at = .02 } },
		Hit = { { KNOCK, .55, .5, WOODY }, { LAND, .4, .55, THUMP }, { CLICK, .3, .5, BONE, at = .07 }, { CLICK, .22, .6, RATTLE, at = .02, dur = .25, fade = .1, loop = true },
			{ TICK, .08, .35, CREAKY, at = .04, dur = .35, loop = true } },
		Perfect = { { KNOCK, .2, .8, WOODY, at = .06 }, { PING, .1, .55, TOLL, at = .08 } },
		Crit = { { LAND, .6, .4, DOOM }, { KNOCK, .5, .45, THUMP }, { CLICK, .36, .42, BONE, at = .08 }, { CLICK, .3, .5, CRUNCH, at = .16 }, { TICK, .12, .3, CREAK, at = .05, dur = .7, loop = true }, { PING, .2, .42, TOLL, at = .1 },
			{ CLICK, .25, .5, RATTLE, at = .06, dur = .4, loop = true } },
		Draw = { { TICK, .12, .35, CREAK, dur = .55, attack = .05, fade = .2, loop = true }, { CLICK, .2, .6, RATTLE, at = .1, dur = .3, loop = true }, { KNOCK, .2, .55, WOODY, at = .45 } },
		Break = { { KNOCK, .45, .45, WOODY }, { PING, .15, .38, TOLL, at = .05 } },
		Inspect = { { TICK, .14, .3, CREAK, dur = .9, attack = .1, fade = .3, loop = true }, { KNOCK, .3, .6, WOODY, at = 1.0 }, { KNOCK, .3, .62, WOODY, at = 1.3 },
			{ KNOCK, .34, .58, WOODY, at = 1.6 }, { PING, .14, 2.4, CHIME, at = 2.0 }, { PING, .12, 2.4, CHIME, at = 2.25 }, { PING, .1, .42, TOLL, at = 2.3 } },
		Idle = { { TICK, .006, .3, CREAK, loop = true }, { WIND, .008, .4, BREATH, loop = true } },
		Run = { { CLICK, .045, .7, RATTLE, loop = true } },
	}
	local CHOIR = { ChorusSoundEffect = { Depth = .5, Mix = .75, Rate = 1.5 }, ReverbSoundEffect = { DecayTime = 3.2, WetLevel = -2 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 3, HighGain = -6 } }
	local SHRIEK = { DistortionSoundEffect = { Level = .85 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 9, HighGain = -4 }, TremoloSoundEffect = { Depth = .55, Duty = .5, Frequency = 21 },
		ReverbSoundEffect = { DecayTime = 2.4, WetLevel = -4 } }
	local DRONE = { TremoloSoundEffect = { Depth = .5, Duty = .5, Frequency = 5 }, EqualizerSoundEffect = { LowGain = 8, MidGain = -4, HighGain = -24 }, ReverbSoundEffect = { DecayTime = 3, WetLevel = -4 } }
	-- SOUL REAPER: a deep ringing reap with a ghostly choir breathing out of every cut; a crit shrieks and tolls;
	-- the draw rises out of a drone; the inspect is a swelling choir and a bell; idle: a low drone and a far choir.
	KITS.HW_Soul = {
		Swing = { { SLASH, .32, .95, AIRY }, whoosh(1.4, .24, .28, AIRY), { PING, .06, .9, CHOIR, to = 1.4, ramp = .2, dur = .3, loop = true } },
		Hit = { { SHEATH, .4, .95, RING }, { LAND, .35, .6, DOOM }, { PING, .14, 1.1, CHOIR, at = .02, dur = .5, to = .75, ramp = .5, loop = true }, whoosh(2.6, .12, .18, AIRY, .02) },
		Perfect = { { PING, .14, 1.5, SHINE, at = .05 }, { PING, .08, 2.25, SHINE, at = .1 } },
		Crit = { { LAND, .6, .4, DOOM }, { SHEATH, .45, .7, RING }, { PING, .26, 1.2, SHRIEK, dur = .7, fade = .3, loop = true, to = .6, ramp = .65 },
			{ PING, .2, .45, TOLL, at = .1 }, { PING, .14, .9, CHOIR, at = .12, dur = 1.2, fade = .5, loop = true } },
		Draw = { { SHEATH, .3, .8, RING }, { WIND, .08, .5, DRONE, at = .1, dur = .8, attack = .3, fade = .3, loop = true },
			{ PING, .1, .9, CHOIR, at = .2, to = 1.35, ramp = .5, dur = .7, loop = true } },
		Break = { { LAND, .5, .4, DOOM }, { PING, .16, 1, CHOIR, at = .05, to = 1.5, ramp = .6, dur = .8, loop = true } },
		Inspect = { { WIND, .08, .4, DRONE, dur = 2.4, attack = .5, fade = .5, loop = true }, { PING, .1, .75, CHOIR, at = .3, dur = .5, loop = true },
			{ PING, .1, .94, CHOIR, at = .65, dur = .5, loop = true }, { PING, .1, 1.12, CHOIR, at = 1.0, dur = .5, loop = true }, { PING, .12, 1.5, CHOIR, at = 1.35, dur = .9, fade = .4, loop = true },
			{ SHEATH, .3, .8, RING, at = 2.1 }, { PING, .18, .45, TOLL, at = 2.15 } },
		Idle = { { WIND, .014, .4, DRONE, loop = true }, { PING, .004, .7, CHOIR, loop = true } },
		Run = { { WIND, .04, 1.6, AIRY, loop = true } },
	}
	return KITS
end

---------------------------------------------------------------------------------------------------------------------
-- HIT THEMES (client; PickFX palettes + hit effects, built from the MiningClient FX / PickFX public primitives)
---------------------------------------------------------------------------------------------------------------------
local C = Color3.fromRGB
Skins.Palettes = { -- [1] main glow (circles, trail start), [2] second (trail end), then accents
	HW_Grave = { C(120, 255, 130), C(110, 82, 58), C(210, 255, 210), C(150, 84, 46) },
	HW_Bone = { C(255, 176, 60), C(236, 226, 200), C(255, 236, 170), C(120, 100, 80) },
	HW_Pumpkin = { C(255, 140, 30), C(255, 214, 60), C(90, 160, 50), C(255, 244, 170) },
	HW_Ghost = { C(140, 215, 255), C(230, 248, 255), C(90, 160, 240), C(62, 70, 88) },
	HW_Coffin = { C(255, 84, 40), C(255, 190, 80), C(110, 56, 44), C(120, 30, 26) },
	HW_Soul = { C(186, 90, 255), C(246, 226, 255), C(255, 150, 240), C(64, 26, 112) },
}
local CRIT_TEXT = {
	HW_Grave = { 'R.I.P.!', 'R.I.P.!' },
	HW_Bone = { 'CRACK!', 'ХРУСЬ!' },
	HW_Pumpkin = { 'SMASH!', 'ХРЯСЬ!' },
	HW_Ghost = { 'BOO!', 'БУ!' },
	HW_Coffin = { 'CHOMP!', 'ХРУМ!' },
	HW_Soul = { 'REAPED!', 'ЖАТВА!' },
}
function Skins.CritText(theme)
	local t = CRIT_TEXT[theme]
	if not t then
		return nil
	end
	return (Shared and Shared.IsRussian and Shared.IsRussian()) and t[2] or t[1]
end

local function hitThemes(ctx)
	local FX, PickFX = ctx.FX, ctx.PickFX
	local TweenService = game:GetService('TweenService')
	local Debris = game:GetService('Debris')
	local function low() return FX.Low and FX.Low() end
	local function n(x) return math.max(1, math.floor(x * (low() and .45 or 1) + .5)) end
	local function ru() return Shared and Shared.IsRussian and Shared.IsRussian() end
	local function folder() return FX.Folder or workspace end
	local function glyph(pos, en, ruText, color, size, dir, life)
		if PickFX.Glyph then
			PickFX.Glyph(pos, ru() and ruText or en, color, size, dir, life)
		end
	end
	local function bits(pos, colors, count, size, speed, mat, shape, opts)
		if PickFX.Bits then
			PickFX.Bits(pos, colors, count, size, speed, mat, shape, opts)
		end
	end
	-- a glowing ball that swells and fades (impact flash)
	local function shock(pos, color, size, life)
		local p = Instance.new('Part')
		p.Name = 'HwShock'
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = NE
		p.Color = color
		p.Transparency = .45
		p.Size = Vector3.one * .5
		p.CFrame = CFrame.new(pos)
		p.Parent = folder()
		TweenService:Create(p, TweenInfo.new(life or .3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * (size or 5), Transparency = 1 }):Play()
		Debris:AddItem(p, (life or .3) + .05)
	end
	-- a soft rising wisp (ghost / soul): a neon ball floating up on a wobbling path, fading out
	local function wisp(pos, color, size, rise, life)
		local p = Instance.new('Part')
		p.Name = 'HwWisp'
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = NE
		p.Color = color
		p.Transparency = .2
		p.Size = Vector3.one * size
		p.CFrame = CFrame.new(pos)
		p.Parent = folder()
		local goal = pos + Vector3.new((math.random() - .5) * 2, rise, (math.random() - .5) * 2)
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = CFrame.new(goal), Size = Vector3.one * size * .4, Transparency = 1 }):Play()
		Debris:AddItem(p, life + .05)
	end
	-- a neon streak from a to b that flashes and thins out
	local function streak(a, b, width, color, life)
		local len = (b - a).Magnitude
		if len < .01 then
			return
		end
		local p = Instance.new('Part')
		p.Name = 'HwStreak'
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = NE
		p.Color = color
		p.Size = Vector3.new(width, width, len)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Parent = folder()
		TweenService:Create(p, TweenInfo.new(life or .25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(width * .2, width * .2, len) }):Play()
		Debris:AddItem(p, (life or .25) + .05)
	end
	-- a crescent cut in the plane facing the camera (scythe skins)
	local function crescent(pos, color, radius, tilt, life)
		local cam = workspace.CurrentCamera
		local f = (cam and CFrame.lookAt(pos, cam.CFrame.Position) or CFrame.new(pos)) * CFrame.Angles(0, 0, tilt or 0)
		local prev
		for i = 0, 9 do
			local a = math.rad(-70 + i * 14)
			local q = (f * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0)).Position
			if prev then
				streak(prev, q, .14 + .22 * math.sin(i / 9 * math.pi), color, life or .3)
			end
			prev = q
		end
	end
	local function smoke(pos, color, count, size)
		FX.Burst(pos, { Texture = SMOKE_TEX, Color = color, Count = n(count), Speed = NumberRange.new(2, 5), LightEmission = 0, Acceleration = Vector3.new(0, 1, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or .9), NumberSequenceKeypoint.new(1, (size or .9) * 2.2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }) })
	end
	-- a jaw snapping shut in front of the camera: two rows of fangs slam together, then fade
	local function snap(pos, color, size, life)
		local cam = workspace.CurrentCamera
		local f = cam and CFrame.lookAt(pos, cam.CFrame.Position) or CFrame.new(pos)
		for _, row in ipairs({ -1, 1 }) do
			for k = -2, 2 do
				local p = Instance.new('Part')
				p.Name = 'HwFang'
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Material = SP
				p.Color = WHITE
				p.Size = Vector3.new(.3, .3, .06) * size
				p.CFrame = f * CFrame.new(k * .36 * size, row * 1.1 * size, 0) * CFrame.Angles(0, 0, math.pi / 4)
				p.Parent = folder()
				local edge = Instance.new('Part')
				edge.Name = 'HwFangGlow'
				edge.Anchored = true
				edge.CanCollide = false
				edge.CanQuery = false
				edge.CanTouch = false
				edge.CastShadow = false
				edge.Material = NE
				edge.Color = color
				edge.Transparency = .3
				edge.Size = Vector3.new(1.9, .08, .04) * size
				edge.CFrame = f * CFrame.new(0, row * 1.1 * size, -.02)
				edge.Parent = folder()
				local shut = TweenInfo.new(.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TweenService:Create(p, shut, { CFrame = f * CFrame.new(k * .36 * size, row * .14 * size, 0) * CFrame.Angles(0, 0, math.pi / 4) }):Play()
				TweenService:Create(edge, shut, { CFrame = f * CFrame.new(0, row * .28 * size, -.02) }):Play()
				local fade = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, .12)
				TweenService:Create(p, fade, { Transparency = 1 }):Play()
				TweenService:Create(edge, fade, { Transparency = 1 }):Play()
				Debris:AddItem(p, life + .2)
				Debris:AddItem(edge, life + .2)
			end
		end
	end
	local HIT = {}
	HIT.HW_Bone = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Bone
		shock(pos, c[2], crit and 6 or 3.4, .2)
		FX.Burst(pos, { Color = c[1], Color2 = c[3], Count = n(crit and 20 or 10), Speed = NumberRange.new(7, 14), Direction = dir, LightEmission = .9 })
		bits(pos, { c[2], C(214, 202, 174), C(250, 244, 226) }, crit and 12 or 6, .24, 15, SP, nil, { Flat = true, Up = .7, Life = .65 })
		bits(pos, { WHITE, c[2] }, crit and 6 or 3, .12, 12, SP, nil, { Up = .9, Life = .6 })
		bits(pos, { C(112, 106, 116), C(84, 80, 90) }, crit and 5 or 3, .26, 14, SL, nil, { Up = .5, Life = .6 })
		FX.Ring(pos, c[1], crit and 8 or 4.5, .3)
		if crit then
			shock(pos, c[1], 8.5, .3)
			FX.Ring(pos, c[2], 11, .42)
			glyph(pos + Vector3.new(0, 1.8, 0), 'CRACK!', 'ХРУСЬ!', c[3], 74, Vector3.new(0, 1, 0), 1.1)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'clack', 'клац', c[3], 26, Vector3.new(0, 1, 0), .6)
		end
	end
	HIT.HW_Pumpkin = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Pumpkin
		shock(pos, c[1], crit and 6.5 or 3.8, .22)
		FX.Burst(pos, { Texture = FIRE_TEX, Color = c[2], Color2 = c[1], Count = n(crit and 14 or 7), Speed = NumberRange.new(3, 8), Acceleration = Vector3.new(0, 8, 0), Lifetime = NumberRange.new(.5, 1), LightEmission = 1 })
		FX.Burst(pos, { Color = c[4], Color2 = c[1], Count = n(crit and 16 or 8), Speed = NumberRange.new(8, 15), Direction = dir, LightEmission = .9 })
		bits(pos, { c[1], C(230, 110, 20), C(255, 160, 60) }, crit and 12 or 6, .3, 15, SP, nil, { Up = .7, Life = .7 })
		bits(pos, { C(250, 236, 200), C(240, 220, 170) }, crit and 8 or 4, .1, 13, SP, nil, { Flat = true, Up = .9, Life = .6 })
		bits(pos, { c[3], C(60, 120, 40) }, crit and 4 or 2, .16, 11, SP, nil, { Flat = true, Up = .8, Life = .6 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if crit then
			FX.Ring(pos, c[2], 12, .42)
			shock(pos, c[2], 9, .3)
			glyph(pos + Vector3.new(0, 1.8, 0), 'SMASH!', 'ХРЯСЬ!', c[2], 78, Vector3.new(0, 1, 0), 1.1)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'splat', 'шмяк', c[1], 26, Vector3.new(0, 1, 0), .6)
		end
	end
	HIT.HW_Ghost = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Ghost
		shock(pos, c[2], crit and 6 or 3.4, .22)
		if not remote then
			local tilt = math.rad(math.random(-35, -15))
			for k = 0, (crit and 2 or 1) do
				crescent(pos + Vector3.new(0, (k - .5) * .4, 0), k == 1 and c[2] or c[1], 2 + k * .35, tilt, .32)
			end
			for _ = 1, n(crit and 7 or 3) do
				wisp(pos + Vector3.new(math.random() - .5, math.random() * .5, math.random() - .5), c[2], .4 + math.random() * .2, 3 + math.random() * 2.5, .9 + math.random() * .5)
			end
		end
		FX.Burst(pos, { Color = c[2], Color2 = c[1], Count = n(crit and 22 or 11), Speed = NumberRange.new(6, 12), Direction = dir, LightEmission = 1, Acceleration = Vector3.new(0, 6, 0) })
		smoke(pos, c[1], crit and 5 or 2, .8)
		bits(pos, { C(112, 106, 116), C(84, 80, 90) }, crit and 6 or 3, .24, 14, SL, nil, { Up = .5, Life = .6 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if crit then
			FX.Ring(pos, c[2], 12, .45)
			glyph(pos + Vector3.new(0, 1.8, 0), 'BOO!', 'БУ!', c[2], 82, Vector3.new(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'wooo', 'ууу', c[2], 26, Vector3.new(0, 1, 0), .7)
		end
	end
	HIT.HW_Coffin = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Coffin
		shock(pos, c[1], crit and 6.5 or 3.6, .22)
		if not remote then
			snap(pos + Vector3.new(0, .4, 0), c[1], crit and 1.25 or .8, .3)
		end
		-- red / orange sparks flung out of the maw, splinters, nails, ember smoke
		FX.Burst(pos, { Color = c[1], Color2 = c[2], Count = n(crit and 26 or 14), Speed = NumberRange.new(10, 20), Direction = dir, LightEmission = 1, Spread = Vector2.new(80, 80) })
		FX.Burst(pos, { Texture = FIRE_TEX, Color = c[2], Color2 = c[1], Count = n(crit and 10 or 5), Speed = NumberRange.new(2, 6), Acceleration = Vector3.new(0, 8, 0), Lifetime = NumberRange.new(.4, .9), LightEmission = 1 })
		bits(pos, { c[3], C(92, 46, 36), C(140, 86, 60) }, crit and 10 or 5, .28, 16, Enum.Material.WoodPlanks, nil, { Flat = true, Up = .6, Life = .7 })
		bits(pos, { C(246, 240, 222), C(220, 210, 190) }, crit and 5 or 2, .1, 13, SP, nil, { Up = .8, Life = .55 })
		smoke(pos, c[4], crit and 5 or 2, 1)
		FX.Ring(pos, c[1], crit and 8 or 4.5, .3)
		if crit then
			FX.Ring(pos, c[2], 11, .45)
			shock(pos, c[2], 9, .35)
			if not remote then
				for i = 1, n(6) do
					local a = (i / 6) * math.pi * 2
					streak(pos, pos + Vector3.new(math.cos(a) * 2.4, .6 + math.random() * 1.4, math.sin(a) * 2.4), .1, i % 2 == 0 and c[2] or c[1], .3)
				end
			end
			glyph(pos + Vector3.new(0, 1.8, 0), 'CHOMP!', 'ХРУМ!', c[1], 80, Vector3.new(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'snap', 'клац', c[2], 26, Vector3.new(0, 1, 0), .6)
		end
	end
	HIT.HW_Soul = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Soul
		shock(pos, c[2], crit and 7 or 3.8, .24)
		if not remote then
			local tilt = math.rad(math.random(-40, -15))
			for k = 0, (crit and 2 or 1) do
				crescent(pos + Vector3.new(0, (k - .5) * .45, 0), k == 1 and c[3] or c[1], 2.2 + k * .4, tilt, .34)
			end
			for _ = 1, n(crit and 8 or 3) do
				wisp(pos + Vector3.new(math.random() - .5, math.random() * .4, math.random() - .5), c[2]:Lerp(c[1], math.random() * .5), .35 + math.random() * .2, 3.5 + math.random() * 3, 1 + math.random() * .6)
			end
		end
		FX.Burst(pos, { Color = c[1], Color2 = c[2], Count = n(crit and 24 or 12), Speed = NumberRange.new(7, 14), Direction = dir, LightEmission = 1 })
		bits(pos, { c[1], c[3], C(140, 70, 220) }, crit and 10 or 5, .2, 13, NE, nil, { Up = .8, Life = .6 })
		bits(pos, { C(60, 52, 70), C(40, 34, 50) }, crit and 7 or 4, .26, 14, SL, nil, { Up = .5, Life = .6 })
		smoke(pos, c[4], crit and 6 or 2, 1)
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if crit then
			FX.Ring(pos, c[3], 13, .5)
			shock(pos, c[1], 10, .35)
			glyph(pos + Vector3.new(0, 1.8, 0), 'REAPED!', 'ЖАТВА!', c[3], 80, Vector3.new(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'soul', 'душа', c[2], 26, Vector3.new(0, 1, 0), .7)
		end
	end
	HIT.HW_Grave = function(pos, dir, q, crit, remote)
		local c = Skins.Palettes.HW_Grave
		shock(pos, c[3], crit and 6 or 3.4, .22)
		FX.Burst(pos, { Color = c[1], Color2 = c[3], Count = n(crit and 22 or 11), Speed = NumberRange.new(6, 13), Direction = dir, LightEmission = .9 })
		FX.Burst(pos, { Texture = SMOKE_TEX, Color = c[2], Count = n(crit and 6 or 3), Speed = NumberRange.new(2, 5), LightEmission = 0, Acceleration = Vector3.new(0, 1, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .9), NumberSequenceKeypoint.new(1, 2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }) })
		bits(pos, { c[2], C(78, 58, 42), C(132, 100, 70) }, crit and 9 or 5, .26, 14, Enum.Material.Ground, nil, { Up = .7, Life = .6 })
		bits(pos, { c[4], C(110, 106, 102) }, crit and 4 or 2, .16, 12, Enum.Material.CorrodedMetal, nil, { Up = .6, Life = .55 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if not remote then
			for _ = 1, n(crit and 5 or 2) do
				wisp(pos + Vector3.new(math.random() - .5, 0, math.random() - .5), c[1]:Lerp(WHITE, .3), .45, 3 + math.random() * 2, .9 + math.random() * .4)
			end
		end
		if crit then
			FX.Ring(pos, c[3], 12, .45)
			glyph(pos + Vector3.new(0, 1.8, 0), 'R.I.P.!', 'R.I.P.!', c[1], 74, Vector3.new(0, 1, 0), 1.1)
		elseif q == 2 and not remote then
			glyph(pos + Vector3.new(0, .8, 0), 'thud', 'бух', c[3], 26, Vector3.new(0, 1, 0), .6)
		end
	end
	-- the same primitives drive the skins' living state machines (liveFX)
	return HIT, { n = n, low = low, glyph = glyph, bits = bits, shock = shock, wisp = wisp, crescent = crescent, snap = snap }
end

---------------------------------------------------------------------------------------------------------------------
-- LIVING STATE MACHINES (client; PickFX.LiveFX[Kind], run by PickFX every animated frame right after the generic
-- motions, like the stock Scarlet Anime Scythe / Hand of Fate live code). Every skin: lights that breathe (flames
-- flicker) and flare on a strike, a draw and through the inspect; its emitter busier while running and through the
-- inspect, a puff on every strike; extra motion on top of the generic one (lantern sway, jaw chatter, chewing, darting
-- eyes, faster / bobbing orbits); a hotter, longer trail while running; a DRAW flourish; INSPECT beats and a finale;
-- IDLE moods / floats in the hand and things flung behind on a RUN. World effects only for held models near the camera
-- (never in a ViewportFrame preview); Reduced Motion: steady lights, no extra motion, no effects; Low FX: no idle /
-- run floats, fewer bits (n()).
---------------------------------------------------------------------------------------------------------------------
local SMOKE_GREY = Color3.fromRGB(150, 140, 136)
local function seq(a, b, c)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(.5, b), ColorSequenceKeypoint.new(1, c) })
end
local LIVE_SPECS = {} -- Kind -> spec (filled below); liveFX turns every spec into a PickFX live function

local function liveFX(ctx, K)
	local FX = ctx.FX
	local n, glyph, bits, shock, wisp, crescent, snap = K.n, K.glyph, K.bits, K.shock, K.wisp, K.crescent, K.snap
	local function low() return K.low() == true end
	local function pick(list) return list[math.random(1, #list)] end
	local function burst(pos, c1, c2, count, speed, opts)
		opts = opts or {}
		FX.Burst(pos, { Texture = opts.Texture, Color = c1, Color2 = c2, Count = n(count), Speed = NumberRange.new(speed * .4, speed),
			Spread = opts.Spread or Vector2.new(180, 180), Acceleration = opts.Acceleration or Vector3.new(0, 2, 0), Lifetime = opts.Lifetime,
			LightEmission = opts.LightEmission or 1, Size = opts.Size, Transparency = opts.Transparency })
	end
	-- a soft puff of smoke (candle / stem smoke), no glow
	local function puff(pos, color, size)
		FX.Burst(pos, { Texture = SMOKE_TEX, Color = color, Count = 1, Speed = NumberRange.new(.2, .6), Spread = Vector2.new(15, 15),
			Acceleration = Vector3.new(0, 1.6, 0), Lifetime = NumberRange.new(1.1, 1.7), LightEmission = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * .5), NumberSequenceKeypoint.new(1, size * 1.6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 1) }) })
	end
	local function flicker(t, seed, amp)
		return 1 + amp * (math.noise(t * 7.3, seed) * .8 + math.noise(t * 17.1, seed + 9.7) * .45)
	end
	-- an extra transform on an animated part entry, on top of what PickFX wrote this frame (Motor6D or anchored preview)
	local function push(e, p, X)
		if p.Motor then
			p.Motor.Transform = p.Motor.Transform * X
		elseif e.Anchored and p.Part.Parent then
			p.Part.CFrame = p.Part.CFrame * (p.Base:Inverse() * p.Joint * X * p.Joint:Inverse() * p.Base)
		end
	end
	-- the API a spec's hooks get: the primitives + its palette
	local api = { n = n, glyph = glyph, bits = bits, shock = shock, wisp = wisp, crescent = crescent, snap = snap, burst = burst, puff = puff,
		pick = pick, push = push, low = low }

	local function init(e, spec, t)
		local s = { Lights = {}, Emitters = {}, Glow = {}, Tint = {}, Moves = {}, Fired = {}, Flash = 0, Boost = 0, Rush = 0, Orb = 0,
			LastHit = e.Hit, InspUntil = e.InspectUntil, InspAt = -100, Charging = false, Hand = false, Rate = -1, Running = false,
			NextIdle = t + 1.2 + math.random() * 2, NextMood = t + 3 + math.random() * 4, NextRun = 0, NextTint = 0, Seed = math.random() * 50,
			Pal = Skins.Palettes[spec.Theme] }
		local pulse = {}
		for _, r in ipairs(e.Pulse) do pulse[r.Part] = true end
		for _, d in ipairs(e.Model:GetDescendants()) do
			if d:IsA('Light') then
				table.insert(s.Lights, { L = d, Base = d.Brightness, Flame = spec.Flames and spec.Flames[d.Name] or nil })
			elseif d:IsA('ParticleEmitter') then
				table.insert(s.Emitters, { E = d, Base = d.Rate })
			elseif d:IsA('BasePart') then
				local g = spec.Glow and spec.Glow[d.Name]
				if g then table.insert(s.Glow, { Part = d, Base = d.Transparency, Pulse = pulse[d], K = g }) end
				if spec.Tint and spec.Tint[d.Name] then table.insert(s.Tint, { Part = d, Base = d.Color }) end
			end
		end
		for _, p in ipairs(e.Parts) do
			local g = (spec.Moves and spec.Moves[p.Part.Name]) or (spec.MovesByAnim and spec.MovesByAnim[p.Part:GetAttribute('PickAnim') or ''])
			if g then
				s.Moves[g] = s.Moves[g] or {}
				table.insert(s.Moves[g], p)
			end
		end
		s.Focus = e.Model:FindFirstChild(spec.Focus) or e.Root
		local root = e.Root
		s.TipA, s.TipB = root:FindFirstChild('TrailA'), root:FindFirstChild('TrailB')
		if e.Trail then
			s.TrailColor, s.TrailLife = e.Trail.Color, e.Trail.Lifetime
		end
		if spec.Init then spec.Init(e, s, api) end
		return s
	end

	local function make(spec)
		return function(e, t, dt, h, still)
			local s = e.HwLive
			if not s then
				s = init(e, spec, t)
				e.HwLive = s
			end
			local st = e.State
			local insp = st.Insp
			local lo = low()
			-- events: a strike (PickFX.HitPulse raised e.Hit), an inspect starting / cancelled, the draw (Mount -> Hand)
			local struck = e.Hit > s.LastHit + 1e-3
			if e.InspectUntil ~= s.InspUntil then
				s.InspUntil = e.InspectUntil
				s.Charging = e.InspectUntil > t + .05
				s.InspAt = s.Charging and t or -100
				table.clear(s.Fired)
			end
			local ip = (s.Charging and t < e.InspectUntil) and (t - s.InspAt) or -1
			if struck then s.Flash = math.max(s.Flash, e.Hit) end
			s.Flash = math.max(0, s.Flash - dt * 3)
			s.Boost = math.max(0, s.Boost - dt * 1.6)
			s.Rush = math.max(0, s.Rush - dt * 1.2)
			-- lights: breathe / flicker, flare on a strike, the draw and through the inspect
			local glow = s.Flash * 1.3 + s.Boost * 1.4 + insp * (spec.InspGlow or 1)
			for _, l in ipairs(s.Lights) do
				local k = 1
				if not still then
					k = l.Flame and flicker(t, s.Seed + #l.L.Name, l.Flame * (1 + st.Run * .6)) or (1 + .16 * math.sin(t * 2.1 + s.Seed))
				end
				l.L.Brightness = math.max(0, l.Base * (k + glow))
			end
			-- emitters: busier while running and through the inspect, calmer on Low FX / Reduced Motion
			local rate = 1 + st.Run * (spec.RunRate or 1.5) + insp * (spec.InspRate or 1.5)
			if still then rate *= .4 elseif lo then rate *= .5 end
			rate = math.floor(rate * 10 + .5) / 10
			if rate ~= s.Rate then
				s.Rate = rate
				for _, m in ipairs(s.Emitters) do m.E.Rate = m.Base * rate end
			end
			if struck and not still and not lo then
				for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(spec.HitEmit or 3) end end
			end
			-- glow parts brighter through the inspect / a mood / a strike (Transparency from their base, pulse parts on top
			-- of PickFX's pulse)
			local lift = insp * .3 + s.Boost * .25 + s.Flash * .15 + (s.Lift or 0)
			if lift > .001 or (s.LiftWas or 0) > .001 then -- (at rest the parts keep their base / PickFX's pulse)
				for _, g in ipairs(s.Glow) do
					local p = g.Part
					local base = g.Pulse and p.Transparency or g.Base
					p.Transparency = math.clamp(base - lift * g.K, 0, 1)
				end
			end
			s.LiftWas = lift
			-- flame colours (20 Hz)
			if #s.Tint > 0 and t >= s.NextTint then
				s.NextTint = t + .05
				local hot, dim = spec.Hot or WHITE, spec.Dim or BLACK
				for i, r in ipairs(s.Tint) do
					local k = still and 0 or math.noise(t * 6.1, i * .37 + s.Seed) * 1.6 + s.Boost * .5 + s.Flash * .4
					r.Part.Color = k > 0 and r.Base:Lerp(hot, math.min(1, k) * .6) or r.Base:Lerp(dim, math.min(1, -k) * .45)
				end
			end
			-- extra motion (never with Reduced Motion)
			local inHand = e.Anchored or e.Model:GetAttribute('Mount') == 'Hand'
			if not still then
				if spec.Mood and inHand and ip < 0 and t >= s.NextMood then
					s.NextMood = t + spec.MoodEvery * (.75 + math.random() * .5)
					s.MoodAt = t
				end
				s.Orb += dt * (insp * (spec.InspSpin or 0) + st.Run * (spec.RunSpin or 0) + s.Rush * (spec.RushSpin or 0))
				if spec.Move then spec.Move(e, s, t, dt, h, ip, api) end
			else
				s.Lift = 0
			end
			local mood = s.MoodAt -- a mood started this frame (Move began its motion; Mood adds its effects below)
			s.MoodAt = nil
			-- trail: hotter and longer while running
			if e.Trail and spec.RunTrail then
				local fast = st.Run > .5
				if fast ~= s.Running then
					s.Running = fast
					e.Trail.Color = fast and spec.RunTrail or s.TrailColor
					e.Trail.Lifetime = fast and .46 or s.TrailLife
				end
			end
			s.LastHit = e.Hit
			if e.Anchored then
				return
			end
			-- WORLD EFFECTS (held, near the camera, no Reduced Motion)
			local focus = s.Focus
			local cam = workspace.CurrentCamera
			local near = focus and focus.Parent and cam and (focus.Position - cam.CFrame.Position).Magnitude < 45
			local fx = near and not still
			local me = ctx.Player
			s.Own = me ~= nil and me.Character ~= nil and e.Model.Parent == me.Character -- text pops only for your own pickaxe
			local wasHand = s.Hand
			s.Hand = inHand
			if inHand and not wasHand then -- the DRAW
				s.Boost = 1
				s.EquipAt = t
				if fx and spec.Draw then
					spec.Draw(e, s, t, api)
				end
				s.LastHit = e.Hit
			end
			if fx and ip >= 0 and spec.Inspect then
				spec.Inspect(e, s, t, ip, api)
				s.LastHit = e.Hit
			end
			if s.Charging and t >= e.InspectUntil then -- the inspect ran to its end: the finale
				s.Charging = false
				if fx and spec.Finale then
					s.Boost = 1
					spec.Finale(e, s, t, api)
				end
				s.LastHit = e.Hit
			end
			if mood and fx and not lo and spec.Mood then
				spec.Mood(e, s, t, api)
			end
			if not fx or lo or not inHand then
				return
			end
			if struck and spec.Hit then spec.Hit(e, s, t, e.Hit, api) end
			if ip < 0 and spec.Idle and t >= s.NextIdle then
				s.NextIdle = t + spec.IdleEvery * (.75 + math.random() * .5)
				spec.Idle(e, s, t, api)
			end
			if st.Run > .5 and spec.Run and t >= s.NextRun then
				s.NextRun = t + .4 + math.random() * .25
				local v = e.Root.AssemblyLinearVelocity
				local flat = Vector3.new(v.X, 0, v.Z)
				if flat.Magnitude > 1 then spec.Run(e, s, t, flat, api) end
			end
		end
	end

	local LIVE = {}
	for kind, spec in pairs(LIVE_SPECS) do
		LIVE[kind] = make(spec)
	end
	return LIVE
end

-- A part's world position (nil when gone).
local function at(p, offset)
	if p and p.Parent then
		return offset and (p.CFrame * CFrame.new(offset)).Position or p.Position
	end
	return nil
end
-- Envelope 0 -> 1 -> 0 over len seconds since t0 (attack a, release r).
local function env(t, t0, len, a, r)
	if not t0 then return 0 end
	local k = t - t0
	if k < 0 or k > len then return 0 end
	return math.min(1, k / a, (len - k) / r)
end
-- the extra spin / bob of orbiting parts (wisps, souls); squeeze pulls them in toward the pole
local function orbit(e, s, t, group, api, bob, squeeze)
	for _, p in ipairs(s.Moves[group] or {}) do
		local r = p.Base.Position - p.Joint.Position
		local radial = Vector3.new(r.X, 0, r.Z)
		local inward = radial.Magnitude > .01 and -radial.Unit * squeeze or Vector3.zero
		api.push(e, p, CFrame.Angles(0, s.Orb, 0) * CFrame.new(inward + Vector3.new(0, math.sin(t * 2.4 + p.Phase * 6.28) * bob, 0)))
	end
end

-- GRAVE SHOVEL: the trapped ghost peeks out of its window now and then (its face pushes through the metal and lights
-- up, a wisp escapes), the lantern sways on its chain (harder on a run, kicked by every strike), the mini ghosts bob
-- and race round the blade through the inspect; the lantern flame flickers. DRAW: the ghost bursts up to the window
-- with a green flash and three wisps. INSPECT: wisps rise, the skull pommel chatters, a green R.I.P. finale.
LIVE_SPECS.HW_GraveShovel = {
	Theme = 'HW_Grave', Focus = 'GhostFace', Flames = { LanternLight = .32 }, HitEmit = 2, InspSpin = 3, RunSpin = .8, RushSpin = 3,
	RunTrail = seq(Color3.fromRGB(232, 255, 232), Color3.fromRGB(120, 255, 130), Color3.fromRGB(60, 110, 70)),
	Glow = { GhostFace = 1, GhostFaceCore = .8, GhostFaceTop = .8, GhostPalm = .6, GhostFinger = .5, LanternFlame = .5, SkullEye = .6 },
	Moves = { GhostFace = 'Face', GhostFaceCore = 'Face', GhostFaceTop = 'Face', GhostEye = 'Face', GhostEyeGlint = 'Face', GhostCheek = 'Face',
		GhostMouth = 'Face', LanternChain = 'Lantern', LanternCap = 'Lantern', LanternRoof = 'Lantern', LanternBase = 'Lantern',
		LanternBar = 'Lantern', LanternGlass = 'Lantern', LanternFlame = 'Lantern', MiniGhost = 'Mini', MiniGhostSheet = 'Mini',
		MiniGhostTail = 'Mini', MiniGhostEye = 'Mini', MiniGhostMouth = 'Mini', SkullJaw = 'Jaw', SkullFang = 'Jaw' },
	MoodEvery = 8,
	IdleEvery = 3.2,
	Move = function(e, s, t, dt, h, ip, api)
		local st = e.State
		local peek = env(t, s.MoodAt or s.PeekAt, 1.3, .25, .45)
		if s.MoodAt then s.PeekAt = s.MoodAt end
		s.Lift = peek * .3
		local out = peek * .16 + st.Insp * .2 + s.Boost * .1
		for _, p in ipairs(s.Moves.Face or {}) do
			api.push(e, p, CFrame.new(0, 0, out))
		end
		s.Kick = math.max(s.Kick or 0, h)
		s.Kick = math.max(0, s.Kick - dt * 1.4)
		local amp = 1 + st.Run * 1.6
		local sway = CFrame.Angles(math.sin(t * 1.3 + .4) * .07 * amp, 0, math.sin(t * 1.75) * .11 * amp + s.Kick * math.sin(t * 11) * .45)
		for _, p in ipairs(s.Moves.Lantern or {}) do
			api.push(e, p, sway)
		end
		orbit(e, s, t, 'Mini', api, .1, 0)
		local chat = (ip > .9 and ip < 1.6) and math.abs(math.sin(ip * 26)) * .35 or 0
		if chat > 0 then
			for _, p in ipairs(s.Moves.Jaw or {}) do
				api.push(e, p, CFrame.Angles(chat, 0, 0))
			end
		end
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.PeekAt = t
		s.Kick = 1
		e.Hit = math.max(e.Hit, .7)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[3], 3, .25)
			api.burst(p, c[1], c[3], 12, 5)
			for k = 1, api.n(3) do
				api.wisp(p + Vector3.new((k - 2) * .4, .2, .3), c[1]:Lerp(WHITE, .3), .32, 2.6 + k * .5, 1.2)
			end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus, Vector3.new(0, .2, .3))
		if ip > .45 and not s.Fired.Rise then
			s.Fired.Rise = true
			s.Kick = .7
			if p then
				for k = 1, api.n(3) do
					api.wisp(p + Vector3.new((k - 2) * .35, 0, 0), c[1]:Lerp(WHITE, .35), .28, 2.4 + k * .4, 1.4)
				end
			end
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(6) end end
		end
		if ip > 1.7 and not s.Fired.Again then
			s.Fired.Again = true
			if p then api.wisp(p, c[3], .3, 3, 1.3) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus, Vector3.new(0, 0, .3))
		if not p then return end
		api.shock(p, c[3], 3.6, .3)
		api.burst(p, c[1], c[3], 16, 7)
		api.glyph(p + Vector3.new(0, .6, 0), 'R.I.P.', 'R.I.P.', c[1], 30, Vector3.new(0, 1, 0), 1.1)
		for k = 1, api.n(2) do
			api.wisp(p + Vector3.new((k - 1.5) * .5, .2, 0), c[1]:Lerp(WHITE, .3), .3, 3, 1.3)
		end
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, Vector3.new(0, .1, .35))
		if p then
			api.wisp(p, s.Pal[1]:Lerp(WHITE, .35), .26, 2.4, 1.5)
		end
	end,
	Idle = function(e, s, t, api)
		local p = at(s.Focus, Vector3.new((math.random() - .5) * .6, .4, .2))
		if p then
			api.wisp(p, s.Pal[1]:Lerp(WHITE, .25), .16 + math.random() * .06, 1.8 + math.random(), 1.5)
		end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then
			api.wisp(p - flat.Unit * .6, s.Pal[1]:Lerp(WHITE, .3), .2, 1.2, .8)
			api.bits(p - flat.Unit * .4 + Vector3.new(0, 1, 0), { s.Pal[2], Color3.fromRGB(86, 62, 42) }, 1, .1, 3, Enum.Material.Ground, nil, { Up = .2, Life = .45 })
		end
	end,
	Hit = function(e, s, t, strength, api)
		s.Kick = math.max(s.Kick or 0, strength)
	end,
}

-- BONE PICKAXE: the candle on the skull flickers (its flame shifts colour, the skull's amber light flickers with it,
-- a curl of smoke rises now and then), the jaw chatters every few seconds, embers float out of the sockets. DRAW: the
-- jaw snaps wide with an amber flash and a WOOF. INSPECT (held up still): it chatters like it is laughing, the candle
-- flares and the eyes burn, a WOOF finale with a burst of embers.
LIVE_SPECS.HW_BonePickaxe = {
	Theme = 'HW_Bone', Focus = 'SkullGlow', Flames = { SkullLight = .22 }, HitEmit = 3,
	RunTrail = seq(Color3.fromRGB(255, 248, 226), Color3.fromRGB(255, 176, 60), Color3.fromRGB(150, 90, 40)),
	Glow = { Eye = .6, NoseFire = .5, MouthFire = .5, CandleFlame = .4 },
	Tint = { CandleFlame = true, CandleFlameCore = true, NoseFire = true, MouthFire = true },
	Hot = Color3.fromRGB(255, 250, 210), Dim = Color3.fromRGB(230, 90, 20),
	Moves = { Jaw = 'Jaw', JawRamus = 'Jaw', LowerFang = 'Jaw', LowerTooth = 'Jaw', CandleFlame = 'Flame', CandleFlameCore = 'Flame' },
	MoodEvery = 5,
	IdleEvery = 2.8,
	Move = function(e, s, t, dt, h, ip, api)
		local chatting = env(t, s.ChatAt, s.ChatLen or .6, .05, .1) > 0
		local chat = 0
		if chatting then
			chat = math.abs(math.sin((t - s.ChatAt) * 27)) * .3
		elseif ip > .55 and ip < 1.7 then -- the inspect: it laughs
			chat = math.abs(math.sin(ip * 22)) * .38
		end
		if s.MoodAt then
			s.ChatAt, s.ChatLen = s.MoodAt, .45 + math.random() * .35
		end
		if chat > 0 then
			for _, p in ipairs(s.Moves.Jaw or {}) do
				api.push(e, p, CFrame.Angles(chat, 0, 0))
			end
		end
		-- the flame stretches and leans with the flicker
		local lean = math.noise(t * 3.1, s.Seed) * .25 - e.State.Run * .35
		for _, p in ipairs(s.Moves.Flame or {}) do
			api.push(e, p, CFrame.Angles(lean, 0, math.noise(t * 2.7, s.Seed + 4) * .3))
		end
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		e.Hit = math.max(e.Hit, .9)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3.2, .25)
			api.burst(p, c[1], c[3], 12, 5, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 6, 0) })
			api.bits(p, { c[2], Color3.fromRGB(214, 202, 174) }, 4, .1, 6, SP, nil, { Up = .8, Life = .5 })
			if s.Own then api.glyph(p + Vector3.new(0, 1, 0), 'WOOF!', 'ГАВ!', c[3], 28, Vector3.new(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus)
		if ip > .6 and not s.Fired.Laugh then
			s.Fired.Laugh = true
			if p then api.glyph(p + Vector3.new(0, .9, 0), 'heh-heh', 'хе-хе', c[3], 20, Vector3.new(0, 1, 0), .9) end
		end
		if ip > 1.25 and not s.Fired.Flare then
			s.Fired.Flare = true
			s.Boost = 1
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(8) end end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus)
		if not p then return end
		e.Hit = math.max(e.Hit, 1)
		api.shock(p, c[1], 3.8, .3)
		api.burst(p, c[1], c[3], 18, 7, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 8, 0) })
		api.bits(p, { c[2], WHITE }, 5, .12, 8, SP, nil, { Up = .8, Life = .55 })
		api.glyph(p + Vector3.new(0, 1, 0), 'WOOF!', 'ГАВ!', c[3], 34, Vector3.new(0, 1, 0), 1.1)
	end,
	Idle = function(e, s, t, api)
		local flame = e.Model:FindFirstChild('CandleFlame')
		local p = at(flame, Vector3.new(0, .2, 0))
		if p then api.puff(p, SMOKE_GREY, .25) end
		if math.random() < .5 then
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(1) end end
		end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then
			api.bits(p - flat.Unit * .5, { s.Pal[2], Color3.fromRGB(214, 202, 174) }, 2, .09, 3, SP, nil, { Up = .2, Life = .45 })
		end
	end,
}

-- PUMPKIN SMASHER: the candle inside flickers (the carved face's colour wavers between gold and ember, the light
-- with it), the stem and the tendril sway (harder on a run), every few seconds the grin cackles (a flare, two seeds
-- spat out, a little "hehe"); embers drift off the stem. DRAW: the face flares with a burst of fire and a cackle.
-- INSPECT: the candle roars, seeds pop out of the grin, fire shoots up the stem, a HA-HA finale. A Perfect strike
-- spits seeds.
local function seeds(p, s, api, count)
	api.bits(p, { Color3.fromRGB(250, 236, 200), Color3.fromRGB(240, 220, 170) }, count, .1, 7, SP, nil, { Flat = true, Up = .6, Life = .6 })
end
LIVE_SPECS.HW_PumpkinSmasher = {
	Theme = 'HW_Pumpkin', Focus = 'CandleLight', Flames = { PumpkinGlow = .38 }, HitEmit = 3, InspRate = 2.5, RunRate = 2,
	RunTrail = seq(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 140, 30), Color3.fromRGB(200, 60, 20)),
	Glow = { Grin = .5, FaceEye = .5, FaceNose = .5, EyeFire = .4 },
	Tint = { Grin = true, FaceEye = true, FaceNose = true, EyeFire = true, MouthFlame = true },
	Hot = Color3.fromRGB(255, 236, 150), Dim = Color3.fromRGB(210, 70, 10),
	Moves = { Stem = 'Stem', StemTip = 'Stem', StemCurl = 'Stem', Tendril = 'Tendril' },
	MoodEvery = 7,
	IdleEvery = 2.6,
	Move = function(e, s, t, dt, h, ip, api)
		local run = e.State.Run
		local amp = 1 + run * 2.2
		local sway = CFrame.Angles(math.sin(t * 1.1) * .05 * amp, 0, math.cos(t * .9 + .5) * .07 * amp)
		for _, p in ipairs(s.Moves.Stem or {}) do api.push(e, p, sway) end
		for _, p in ipairs(s.Moves.Tendril or {}) do api.push(e, p, CFrame.Angles(math.sin(t * 1.6) * .1 * amp, 0, 0)) end
		local cackle = env(t, s.CackleAt, .7, .05, .25)
		if s.MoodAt then s.CackleAt = s.MoodAt end
		s.Lift = cackle * (.6 + .4 * math.sin(t * 40))
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		e.Hit = math.max(e.Hit, .8)
		s.CackleAt = t
		local p = at(s.Focus, Vector3.new(0, 0, .6))
		if p then
			api.shock(p, c[1], 3.4, .25)
			api.burst(p + Vector3.new(0, .8, 0), c[2], c[1], 14, 5, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 9, 0) })
			if s.Own then api.glyph(p + Vector3.new(0, 1.1, 0), 'HA-HA!', 'ХА-ХА!', c[2], 28, Vector3.new(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus, Vector3.new(0, -.3, .7))
		if ip > .5 and not s.Fired.Seeds then
			s.Fired.Seeds = true
			s.CackleAt = t
			if p then seeds(p, s, api, 5) end
		end
		if ip > 1.3 and not s.Fired.Fire then
			s.Fired.Fire = true
			local top = at(s.Focus, Vector3.new(0, 1, 0))
			if top then api.burst(top, c[2], c[1], 12, 4, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 10, 0), Spread = Vector2.new(25, 25) }) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus, Vector3.new(0, 0, .6))
		if not p then return end
		s.CackleAt = t
		api.shock(p, c[1], 4, .3)
		api.burst(p, c[2], c[1], 18, 7, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 8, 0) })
		seeds(p, s, api, 4)
		api.glyph(p + Vector3.new(0, 1.1, 0), 'HA-HA!', 'ХА-ХА!', c[2], 34, Vector3.new(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, Vector3.new(0, -.3, .7))
		if p then
			seeds(p, s, api, 2)
			if s.Own then api.glyph(p + Vector3.new(0, .7, 0), 'hehe', 'хе-хе', s.Pal[2], 18, Vector3.new(0, 1, 0), .8) end
		end
	end,
	Idle = function(e, s, t, api)
		for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(2) end end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then
			seeds(p - flat.Unit * .5, s, api, 1)
			api.bits(p - flat.Unit * .5, { s.Pal[1], s.Pal[2] }, 1, .08, 3, NE, nil, { Up = .4, Life = .4 })
		end
	end,
	Hit = function(e, s, t, strength, api)
		if strength >= .88 then -- a Perfect (1) or a remote strike, not a plain swing (.7 / .8)
			local p = at(s.Focus, Vector3.new(0, -.3, .7))
			if p then seeds(p, s, api, 3) end
		end
	end,
}

-- GHOST SCYTHE: the wisps bob as they circle and race round the head after a strike and through the inspect, now and
-- then one sheds a wisp; every few seconds the ghost wails (its glow surges, the wisps rush, a soft "ooo"); the
-- lantern flame flickers. DRAW: the wisps burst out with a ghost-white flash and a crescent. INSPECT (the twirl): the
-- chains rattle, a ring of wisps spirals up, a BOO finale off the blade's point.
LIVE_SPECS.HW_GhostScythe = {
	Theme = 'HW_Ghost', Focus = 'GhostMistFX', Flames = { LanternLight = .3 }, HitEmit = 3, InspSpin = 4, RunSpin = 1, RushSpin = 4,
	RunTrail = seq(Color3.fromRGB(240, 250, 255), Color3.fromRGB(140, 215, 255), Color3.fromRGB(90, 120, 240)),
	Glow = { GhostCore = .8, BladeAura = .5, WispHalo = .5, CuffGlow = .5, LanternFlame = .4 },
	Tint = { LanternFlame = true },
	Hot = WHITE, Dim = Color3.fromRGB(60, 130, 230),
	Moves = { Wisp = 'Wisps', WispHalo = 'Wisps', WispTail = 'Wisps' },
	MoodEvery = 7.5,
	IdleEvery = 2.8,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then
			s.Rush = 1
			s.WailAt = s.MoodAt
		end
		s.Lift = env(t, s.WailAt, 1.2, .2, .6) * .35
		orbit(e, s, t, 'Wisps', api, .14, e.State.Insp * .25)
	end,
	Init = function(e, s)
		s.Wisps = {}
		for _, d in ipairs(e.Model:GetChildren()) do
			if d.Name == 'Wisp' and d:IsA('BasePart') then table.insert(s.Wisps, d) end
		end
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		e.Hit = math.max(e.Hit, .7)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[2], 3.2, .25)
			api.crescent(p, c[1], 1.6, math.rad(-25), .3)
		end
		for k, w in ipairs(s.Wisps) do
			local q = at(w)
			if q and k <= api.n(4) then api.wisp(q, c[2], .26, 2.4 + k * .3, 1.2) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		if ip > .6 and not s.Fired.Rattle then
			s.Fired.Rattle = true
			e.Hit = math.max(e.Hit, .6)
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(8) end end
		end
		if ip > 1.05 and not s.Fired.Ring then
			s.Fired.Ring = true
			local center = at(s.Wisps[1])
			local head = at(s.Focus)
			if center and head then
				for k = 1, api.n(6) do
					local a = k / 6 * math.pi * 2
					api.wisp(head + Vector3.new(math.cos(a) * 1.3, .2, math.sin(a) * 1.3), c[2]:Lerp(c[1], k % 2 * .5), .22, 3.2, 1.4)
				end
			end
		end
		if ip > 1.75 and not s.Fired.Ooo then
			s.Fired.Ooo = true
			local p = at(s.Focus)
			if p then api.glyph(p + Vector3.new(0, .8, 0), 'wooo~', 'ууу~', c[2], 22, Vector3.new(0, 1, 0), 1) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = s.TipB and s.TipB.Parent and s.TipB.WorldPosition or at(s.Focus)
		if not p then return end
		s.Rush = 1
		api.crescent(p, c[2], 1.8, math.rad(-30), .32)
		api.shock(p, c[2], 3.4, .28)
		api.burst(p, c[2], c[1], 16, 7)
		api.glyph(p + Vector3.new(0, .9, 0), 'BOO!', 'БУ!', c[2], 34, Vector3.new(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus)
		if p and s.Own then api.glyph(p + Vector3.new(0, .7, 0), 'ooo', 'ууу', s.Pal[2], 16, Vector3.new(0, 1, 0), .9) end
	end,
	Idle = function(e, s, t, api)
		local w = #s.Wisps > 0 and api.pick(s.Wisps)
		local p = at(w)
		if p then api.wisp(p, s.Pal[2], .16, 1.8 + math.random(), 1.4) end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.wisp(p - flat.Unit * .7, s.Pal[1]:Lerp(WHITE, .4), .22, 1, .8) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength * .7)
	end,
}

-- LIVING COFFIN: its eyes dart round in quick jumps (faster through the inspect), every few seconds it chews (the lid
-- chomps two to four times, embers puff out of the maw), the lid rattles on a run, the maw glow wavers. DRAW: the lid
-- bursts open, phantom fangs slam shut in front of it, a GRRR. INSPECT: it chews and chews, embers pour out, a CHOMP
-- finale.
LIVE_SPECS.HW_LivingCoffin = {
	Theme = 'HW_Coffin', Focus = 'MawLight', Flames = { MawGlow = .2 }, HitEmit = 5, InspRate = 2,
	RunTrail = seq(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 84, 40), Color3.fromRGB(120, 20, 20)),
	Glow = { MawLip = .5, CoffinEye = .4 },
	Moves = { CoffinPupil = 'Eyes', CoffinGlint = 'Eyes' },
	MovesByAnim = { Curl = 'Lid' },
	MoodEvery = 4.5,
	IdleEvery = 3.2,
	Move = function(e, s, t, dt, h, ip, api)
		-- darting eyes: a new target every .3-1.2 s (faster in the inspect), snapped to quickly
		if t >= (s.NextLook or 0) then
			s.NextLook = t + (ip >= 0 and .18 + math.random() * .3 or .35 + math.random() * .9)
			s.LookTX, s.LookTY = (math.random() - .5) * .7, (math.random() - .5) * 1.1
		end
		local k = math.min(1, dt * 28)
		s.LookX = (s.LookX or 0) + ((s.LookTX or 0) - (s.LookX or 0)) * k
		s.LookY = (s.LookY or 0) + ((s.LookTY or 0) - (s.LookY or 0)) * k
		local look = CFrame.Angles(s.LookX, s.LookY, 0)
		for _, p in ipairs(s.Moves.Eyes or {}) do api.push(e, p, look) end
		-- chewing: a bout of chomps (mood), non-stop through the inspect, a rattle while running
		if s.MoodAt then
			s.ChewAt, s.ChewLen = s.MoodAt, .5 + math.random() * .6
			s.Chomps = 0
		end
		local chew = 0
		if env(t, s.ChewAt, s.ChewLen or 0, .02, .05) > 0 then
			chew = math.max(0, math.sin((t - s.ChewAt) * 15)) * .32
		elseif ip > .35 and ip < 2.2 then
			chew = math.max(0, math.sin(ip * 17)) * .4
		end
		chew += e.State.Run * math.abs(math.sin(t * 21)) * .06
		if chew > .001 then
			for _, p in ipairs(s.Moves.Lid or {}) do api.push(e, p, CFrame.Angles(chew, 0, 0)) end
		end
		s.Chew = chew
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		e.Hit = math.max(e.Hit, 1)
		local p = at(s.Focus, Vector3.new(0, 0, .3))
		if p then
			api.snap(p + Vector3.new(0, .3, .4), c[1], .7, .28)
			api.shock(p, c[1], 3.2, .25)
			api.burst(p, c[2], c[1], 14, 5, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 8, 0) })
			if s.Own then api.glyph(p + Vector3.new(0, 1.1, 0), 'GRRR!', 'РРРР!', c[1], 28, Vector3.new(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		if ip > .6 and not s.Fired.Embers then
			s.Fired.Embers = true
			local p = at(s.Focus, Vector3.new(0, .2, .3))
			if p then api.burst(p, c[2], c[1], 10, 3, { Texture = FIRE_TEX, Acceleration = Vector3.new(0, 7, 0), Spread = Vector2.new(40, 40) }) end
		end
		if ip > 1.5 and not s.Fired.Lick then
			s.Fired.Lick = true
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(6) end end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		e.Hit = math.max(e.Hit, 1)
		local p = at(s.Focus, Vector3.new(0, 0, .3))
		if not p then return end
		api.snap(p + Vector3.new(0, .3, .4), c[1], .9, .3)
		api.shock(p, c[1], 3.8, .3)
		api.burst(p, c[1], c[2], 18, 8)
		api.glyph(p + Vector3.new(0, 1.1, 0), 'CHOMP!', 'ХРУМ!', c[1], 34, Vector3.new(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(3) end end
	end,
	Idle = function(e, s, t, api)
		for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(2) end end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .5, { s.Pal[1], s.Pal[2] }, 2, .08, 3, NE, nil, { Up = .4, Life = .45 }) end
	end,
}

-- SOUL REAPER: the soul orbs bob as they circle and flare one after another, a soul now and then slips away and
-- spirals up, the eye flames flicker violet / pink and the hood's light with them; strikes make the souls race. DRAW:
-- a violet flash, a crescent off the blade, the souls burst out. INSPECT (the twirl): the orbs are drawn in close and
-- spin fast, sparks pour off the blade, souls spiral up, a SOULS finale off the blade's point.
LIVE_SPECS.HW_SoulReaper = {
	Theme = 'HW_Soul', Focus = 'EyeLamp', Flames = { SoulLight = .18 }, HitEmit = 4, InspSpin = 4.5, RunSpin = 1, RushSpin = 4,
	RunTrail = seq(Color3.fromRGB(255, 220, 255), Color3.fromRGB(186, 90, 255), Color3.fromRGB(64, 26, 112)),
	Glow = { EyeFlame = .4, BladeAura = .4, SoulVein = .4, Rune = .4 },
	Tint = { EyeFlame = true },
	Hot = Color3.fromRGB(255, 190, 250), Dim = Color3.fromRGB(110, 40, 220),
	Moves = { SoulOrb = 'Orbs', SoulHalo = 'Orbs', SoulTail = 'Orbs', SoulEye = 'Orbs', SoulMouth = 'Orbs' },
	MoodEvery = 6,
	IdleEvery = 2.6,
	Init = function(e, s)
		s.Orbs, s.Halos = {}, {}
		for _, d in ipairs(e.Model:GetChildren()) do
			if d:IsA('BasePart') then
				if d.Name == 'SoulOrb' then table.insert(s.Orbs, d) end
				if d.Name == 'SoulHalo' then table.insert(s.Halos, { Part = d, Base = d.Transparency, Phase = d:GetAttribute('PickPhase') or 0 }) end
			end
		end
	end,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then s.Rush = math.max(s.Rush, .6) end
		orbit(e, s, t, 'Orbs', api, .16, e.State.Insp * .45)
		-- the orbs flare one after another (round the ring), all of them through the inspect
		for _, r in ipairs(s.Halos) do
			local k = math.max(0, math.cos(t * 2.6 - r.Phase * math.pi * 2)) ^ 6
			r.Part.Transparency = math.clamp(r.Base - k * .35 - e.State.Insp * .3 - s.Flash * .2, .05, 1)
		end
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3.4, .25)
			if s.Own then api.glyph(p + Vector3.new(0, 1, 0), '☠', '☠', c[3], 30, Vector3.new(0, 1, 0), .9) end
		end
		local tip = s.TipB and s.TipB.Parent and s.TipB.WorldPosition
		if tip then api.crescent(tip, c[1], 1.7, math.rad(-30), .3) end
		for k, o in ipairs(s.Orbs) do
			local q = at(o)
			if q and k <= api.n(5) then api.wisp(q, c[2]:Lerp(c[1], .4), .24, 2.6 + k * .25, 1.2) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		if ip > .6 and not s.Fired.Sparks then
			s.Fired.Sparks = true
			for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(10) end end
		end
		if ip > 1.1 and not s.Fired.Spiral then
			s.Fired.Spiral = true
			for k, o in ipairs(s.Orbs) do
				local q = at(o)
				if q and k <= api.n(5) then api.wisp(q, c[2]:Lerp(c[3], k % 2 * .5), .2, 3.4, 1.5) end
			end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		local p = s.TipB and s.TipB.Parent and s.TipB.WorldPosition or at(s.Focus)
		if not p then return end
		api.crescent(p, c[3], 1.9, math.rad(-30), .34)
		api.shock(p, c[1], 3.8, .3)
		api.burst(p, c[1], c[2], 18, 8)
		api.glyph(p + Vector3.new(0, .9, 0), 'SOULS!', 'ДУШИ!', c[3], 34, Vector3.new(0, 1, 0), 1.1)
		for k, o in ipairs(s.Orbs) do
			local q = at(o)
			if q and k <= api.n(3) then api.wisp(q, c[2], .22, 3, 1.2) end
		end
	end,
	Mood = function(e, s, t, api)
		local o = #s.Orbs > 0 and api.pick(s.Orbs)
		local q = at(o)
		if q then api.wisp(q, s.Pal[2]:Lerp(s.Pal[1], .3), .2, 3, 1.6) end
	end,
	Idle = function(e, s, t, api)
		for _, m in ipairs(s.Emitters) do if m.E.Parent then m.E:Emit(2) end end
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.wisp(p - flat.Unit * .7, s.Pal[1], .2, 1, .8) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength * .7)
	end,
}

---------------------------------------------------------------------------------------------------------------------
-- REGISTRATION (idempotent; server: MiningWorld, client: MiningClient.World with its ctx)
---------------------------------------------------------------------------------------------------------------------
local wrapped, kitsDone, fxDone = false, false, false
local function wrapModels()
	if wrapped then
		return
	end
	local M = models()
	if M.__HalloweenSkins then
		wrapped = true
		return
	end
	local stock = stockPickaxe
	M.Pickaxe = function(def, level)
		if isSkinDef(def) then
			return Skins.Build(def, level)
		end
		return stock(def, level)
	end
	M.__HalloweenSkins = Skins
	wrapped = true
end
local function registerKits()
	if kitsDone then
		return
	end
	local mining = RS:FindFirstChild('Mining')
	local mod = mining and mining:FindFirstChild('MiningAudio')
	if not mod then
		return
	end
	local Audio = require(mod)
	if type(Audio) ~= 'table' or type(Audio.Kits) ~= 'table' or type(Audio.Sources) ~= 'table' then
		return
	end
	for name, kit in pairs(KITS or buildKits(Audio)) do
		Audio.Kits[name] = kit
		if type(Audio.KitAssetIds) == 'table' and not Audio.KitAssetIds[name] then
			Audio.KitAssetIds[name] = { Swing = 0, Hit = 0, Perfect = 0, Crit = 0, Draw = 0, Break = 0, Inspect = 0 }
		end
	end
	kitsDone = true
end
local function registerFX(ctx)
	if fxDone or type(ctx) ~= 'table' or type(ctx.PickFX) ~= 'table' or type(ctx.FX) ~= 'table' then
		return
	end
	local themes, hit = ctx.PickFX.Themes, ctx.PickFX.HitFX
	if type(themes) ~= 'table' or type(hit) ~= 'table' then
		return -- PickFX without the export: skins keep their stock ThemeAlt
	end
	for name, pal in pairs(Skins.Palettes) do
		themes[name] = pal
	end
	local hitFns, kit = hitThemes(ctx)
	for name, fn in pairs(hitFns) do
		hit[name] = fn
	end
	-- the living state machines (PickFX.LiveFX: draw / inspect / idle / run life in the hand); older PickFX: none
	if type(ctx.PickFX.LiveFX) == 'table' then
		for kind, fn in pairs(liveFX(ctx, kit)) do
			ctx.PickFX.LiveFX[kind] = fn
		end
	end
	fxDone = true
	fxReady = true
	table.clear(cache) -- resolved defs switch from ThemeAlt to the Halloween themes
	-- A skin model PickFX already tracked before the palettes existed (its trail took the Wood colours): track again.
	local Players = game:GetService('Players')
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		for _, m in ipairs(character and character:GetChildren() or {}) do
			local theme = m:IsA('Model') and m:GetAttribute('Theme')
			if (m.Name == 'MiningHeldPickaxe' or m.Name == 'MiningHeldPickaxeL') and type(theme) == 'string' and Skins.Palettes[theme] then
				local root = m.PrimaryPart
				local trail = root and root:FindFirstChild('PickTrail')
				if trail and ctx.PickFX.Untrack then
					trail:Destroy()
					ctx.PickFX.Untrack(m)
					ctx.PickFX.Track(m, false)
				end
			end
		end
	end
end
local hooked = false
local function hookSkinChange(ctx)
	-- The equipped skin changed while the pickaxe is in the hand: rebind the inspect key, restart the idle loop
	-- with the new sound kit (MiningClient.Tool only does both on equip / level change).
	if hooked or type(ctx) ~= 'table' or typeof(ctx.Player) ~= 'Instance' then
		return
	end
	hooked = true
	ctx.Player:GetAttributeChangedSignal('PickaxeSkin'):Connect(function()
		task.defer(function()
			local T = ctx.Tool
			if not T then
				return
			end
			if T.SyncInspect then
				pcall(T.SyncInspect)
			end
			local tool = T.Find and T.Find()
			if tool and tool.Parent == ctx.Player.Character and ctx.Audio and ctx.M then
				ctx.Audio.StartIdle(Skins.For(ctx.Player, ctx.M.Pickaxes[tool:GetAttribute('Level') or 1] or ctx.M.Pickaxes[1]))
			end
		end)
	end)
end
local trackCtx = nil
-- Living motion for a skin preview Model (a ViewportFrame / UI preview, anchored): needs the MiningClient that
-- registered (client). Returns true when PickFX tracks it.
function Skins.Track(model, anchored)
	local fx = trackCtx and trackCtx.PickFX
	if fx and fx.Track and model then
		return fx.Track(model, anchored ~= false) ~= nil
	end
	return false
end
function Skins.Untrack(model)
	local fx = trackCtx and trackCtx.PickFX
	if fx and fx.Untrack and model then
		fx.Untrack(model)
	end
end

function Skins.Register(ctx)
	local ok, err = pcall(wrapModels)
	if not ok then
		warn('PickaxeSkins: models ' .. tostring(err))
	end
	ok, err = pcall(registerKits)
	if not ok then
		warn('PickaxeSkins: sound kits ' .. tostring(err))
	end
	if IS_CLIENT and ctx then
		trackCtx = trackCtx or (type(ctx) == 'table' and ctx.PickFX and ctx) or nil
		ok, err = pcall(registerFX, ctx)
		if not ok then
			warn('PickaxeSkins: hit themes ' .. tostring(err))
		end
		pcall(hookSkinChange, ctx)
	end
	return true
end
Skins.Designs = DESIGNS

return Skins
