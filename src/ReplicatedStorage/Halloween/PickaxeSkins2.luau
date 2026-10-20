-- HALLOWEEN PART II · THE UNDERYARD: the seven Chapter II pickaxe skins (ReplicatedStorage.Halloween.PickaxeSkins2).
-- Same contract as the Chapter I skins in ReplicatedStorage.Halloween.PickaxeSkins, which registers this module once at
-- load (PickaxeSkins2.Register(Skins, internals)): a skin is PRESENTATION ONLY. It swaps the model, the living motion,
-- the swing style, the hit FX theme and the sound kit of whatever pickaxe tier the player really owns; Skins.Resolve
-- overlays only the Skins.VISUAL keys, so every stat (Damage, Window, Circles, Crit*, Luck, CoinBonus, Strength...)
-- always comes from Config.Mining.Pickaxes[level]. Ownership is profile.Halloween.Skins like Chapter I (Config.Skins
-- lists these ids with Chapter = 2: the Halloween window shows Chapter I, the Underyard window Chapter II); the equipped
-- skin is the server-written player attribute PickaxeSkin. Skins of either chapter stay visible when the event is off.
--
-- API
--   S2.List / S2.ById / S2.Order     the seven defs (Id, Name, RU, Icon, Rarity, Chapter = 2, Theme, ThemeAlt, Swing,
--                                    Sound, Color, Inspect, Visual, Trait/TraitRU, Lore/LoreRU) - Skins.List format
--   S2.Designs                       Visual.Kind -> builder(model, v, def, len, top) (the PickaxeSkins model contract:
--                                    Handle along +Y, grip 1.4 below its centre, faces look along +Z, striking ends
--                                    along +-X, returns the two trail points)
--   S2.Kits(Audio) -> {name = kit}   MiningAudio sound kits (built-in samples only); every Hit has exactly ONE soft
--                                    impact row (KNOCK / LAND under the SOFT EQ, never THUMP) placed second, so the
--                                    density / remote limit (first two rows) keeps the character layer plus the impact
--   S2.Palettes / S2.CritText        theme -> {Color3...} (PickFX palette) / {EN, RU} crit stamp
--   S2.LiveSpecs                     Visual.Kind -> living state machine spec (PickaxeSkins' liveFX format)
--   S2.Register(Skins, internals?)   idempotent: appends the skins to Skins.List / ById / Order, the designs to
--                                    internals.Designs (else Skins.Designs), palettes to Skins.Palettes, crit texts to
--                                    internals.CritText, live specs to internals.LiveSpecs, and wraps Skins.Register so
--                                    the sound kits (MiningAudio.Kits) and hit themes (PickFX.HitFX) follow the Chapter I
--                                    ones (server: kits; client with the MiningClient ctx: kits + hit themes)
-- Every model is deterministic (seeded hash noise): the server's held model equals every client's preview, and the
-- offline renders (tools/sim.luau) equal the game.
local RunService = game:GetService('RunService')

local Shared = nil
pcall(function()
	local folder = script.Parent
	local mod = folder and (folder:FindFirstChild('Shared') or folder:WaitForChild('Shared', 5))
	if mod then
		Shared = require(mod)
	end
end)

local S2 = {}
local IS_CLIENT = RunService:IsClient()

---------------------------------------------------------------------------------------------------------------------
-- THE SEVEN SKINS (Underyard motifs; Swing = an existing MiningClient.Anim style, ThemeAlt = the stock hit theme used
-- until PickFX exports its tables, so the look degrades gracefully)
---------------------------------------------------------------------------------------------------------------------
S2.List = {
	{ Id = 'UY_ToothyAlarm', Name = 'Toothy Alarm', RU = 'Зубастый Будильник', Icon = '⏰', Rarity = 'Epic', Chapter = 2,
		Theme = 'HW_UyAlarm', ThemeAlt = 'Alarm', Swing = 'Alarm', Sound = 'HW_UyAlarm', Color = { 120, 255, 140 }, Inspect = true,
		Trait = 'Cosmetic · funeral alarm clock · snapping teeth · twin bell hammers',
		TraitRU = 'Косметика · похоронный будильник · клацающие зубы · два молота-колокола',
		Lore = 'It rang once at every funeral in the Underyard, and nobody ever woke up. Now it rings on every hit, just in case.',
		LoreRU = 'Он звонил на каждых похоронах в Поддворье, и никто так и не проснулся. Теперь он звенит при каждом ударе, на всякий случай.',
		Visual = { Kind = 'HW_UyToothyAlarm', Length = 4.6, Shaft = { 34, 30, 44 }, ShaftMaterial = 'SmoothPlastic', Head = { 46, 40, 60 },
			Accent = { 120, 255, 140 }, Trim = { 230, 222, 200 }, Bell = { 132, 106, 66 }, Patina = { 96, 168, 136 }, Glass = { 170, 205, 255 },
			Candle = { 255, 170, 80 }, Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.2, 0 }, IconDist = 9.5 } },
	{ Id = 'UY_FateHand', Name = 'Buried Hand of Fate', RU = 'Рука Судьбы · Погребённая', Icon = '⌛', Rarity = 'Legendary', Chapter = 2,
		Theme = 'HW_UyFate', ThemeAlt = 'Fate', Swing = 'Fate', Sound = 'HW_UyFate', Color = { 150, 200, 255 }, Inspect = true,
		Trait = 'Cosmetic · a pale hand from the grave · hourglass pick · sand that never runs out',
		TraitRU = 'Косметика · бледная рука из могилы · кирка-песочные часы · песок, который не кончается',
		Lore = 'Somebody was buried holding their own hourglass. The hand dug its way back up, and it is not letting go of the time it has left.',
		LoreRU = 'Кого-то похоронили с собственными песочными часами в руке. Рука прокопала путь наверх и не отпустит оставшееся время.',
		Visual = { Kind = 'HW_UyFateHand', Length = 4.8, Shaft = { 200, 204, 190 }, ShaftMaterial = 'SmoothPlastic', Head = { 44, 36, 50 },
			Accent = { 150, 200, 255 }, Sand = { 170, 110, 255 }, Skin = { 206, 210, 196 }, Cloth = { 216, 208, 188 }, Dirt = { 86, 62, 42 },
			Gold = { 226, 176, 90 }, Trim = { 232, 224, 204 }, Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.1, 0 }, IconDist = 9.8 } },
	{ Id = 'UY_Laughsaw', Name = 'Funeral Laughsaw', RU = 'Смехопила · Похоронная', Icon = '🎪', Rarity = 'Legendary', Chapter = 2,
		Theme = 'HW_UySaw', ThemeAlt = 'Saw', Swing = 'Rip', Sound = 'HW_UySaw', Color = { 150, 80, 230 }, Inspect = true,
		Trait = 'Cosmetic · dead-circus saw blade · ribbon stripes · a grin that never stops',
		TraitRU = 'Косметика · пила мёртвого цирка · полосы-ленты · ухмылка, которая не гаснет',
		Lore = 'The Funeral Carnival closed a hundred years ago. The saw from its last act still spins, and still thinks the joke is funny.',
		LoreRU = 'Похоронный карнавал закрылся сто лет назад. Пила из его последнего номера всё ещё крутится и всё ещё считает шутку смешной.',
		Visual = { Kind = 'HW_UyLaughsaw', Length = 4.8, Shaft = { 28, 24, 32 }, ShaftMaterial = 'SmoothPlastic', Head = { 230, 222, 206 },
			Accent = { 150, 80, 230 }, Trim = { 24, 20, 30 }, Red = { 168, 36, 60 }, Steel = { 176, 180, 190 }, Candle = { 255, 170, 80 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.3, 0 }, IconDist = 9.8 } },
	{ Id = 'UY_TVHead', Name = 'Static TV-Head', RU = 'ТВ-Башка · Помехи', Icon = '📺', Rarity = 'Mythic', Chapter = 2,
		Theme = 'HW_UyTV', ThemeAlt = 'TV', Swing = 'Smash', Sound = 'HW_UyTV', Color = { 170, 200, 255 }, Inspect = true,
		Trait = 'Cosmetic · a crooked old TV on a pole · static eyes · rabbit-ear antennas',
		TraitRU = 'Косметика · кривой старый телевизор на шесте · глаза из помех · антенны-рожки',
		Lore = 'It only shows one channel, and that channel is watching you back. Do not change it. It does not like that.',
		LoreRU = 'Он ловит лишь один канал, и этот канал смотрит на тебя. Не переключай. Ему это не нравится.',
		Visual = { Kind = 'HW_UyTVHead', Length = 4.8, Shaft = { 52, 40, 34 }, ShaftMaterial = 'Wood', Head = { 86, 58, 42 },
			Accent = { 196, 180, 255 }, Screen = { 150, 200, 255 }, Trim = { 214, 186, 124 }, Ink = { 20, 16, 28 }, Candle = { 255, 170, 80 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.2, 0 }, IconDist = 9.6 } },
	{ Id = 'UY_NastyOctopus', Name = 'Marsh Octopus', RU = 'Мерзкий Спрут · Болотный', Icon = '🐙', Rarity = 'Mythic', Chapter = 2,
		Theme = 'HW_UyOcto', ThemeAlt = 'Ink', Swing = 'Octo', Sound = 'HW_UyOcto', Color = { 120, 255, 140 }, Inspect = true,
		Trait = 'Cosmetic · a marsh octopus coiled round a shovel · glowing spots · bog drips',
		TraitRU = 'Косметика · болотный спрут, обвивший лопату · светящиеся пятна · болотные капли',
		Lore = "Pulled out of the Mourning Marsh still holding a gravedigger's shovel. It refuses to give it back, so now it digs with you.",
		LoreRU = 'Его вытащили из Скорбного болота вместе с лопатой могильщика. Возвращать её он отказался, так что теперь копает вместе с тобой.',
		Visual = { Kind = 'HW_UyOctopus', Length = 5, Shaft = { 74, 58, 44 }, ShaftMaterial = 'Wood', Head = { 104, 112, 108 },
			Accent = { 120, 255, 140 }, Body = { 78, 146, 96 }, Spots = { 150, 80, 230 }, Sucker = { 214, 196, 170 }, Moss = { 92, 120, 60 },
			Trim = { 54, 48, 44 }, Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.0, 0 }, IconDist = 10 } },
	{ Id = 'UY_GummyHorror', Name = 'Gummy Horror', RU = 'Мармеладный Ужас', Icon = '🍬', Rarity = 'Mythic', Chapter = 2,
		Theme = 'HW_UyGummy', ThemeAlt = 'Gummy', Swing = 'Bounce', Sound = 'HW_UyGummy', Color = { 190, 110, 255 }, Inspect = true,
		Trait = 'Cosmetic · translucent gummy skull · gummy-worm picks · jelly that drips forever',
		TraitRU = 'Косметика · прозрачный мармеладный череп · кирки из мармеладных червей · вечно капающее желе',
		Lore = 'The candy shop in the Underyard sold only one flavour: regret. This one came out of the mould grinning.',
		LoreRU = 'Кондитерская Поддворья продавала только один вкус: сожаление. Этот вышел из формы уже с ухмылкой.',
		Visual = { Kind = 'HW_UyGummyHorror', Length = 4.6, Shaft = { 236, 230, 218 }, ShaftMaterial = 'SmoothPlastic', Head = { 176, 96, 255 },
			Accent = { 120, 255, 140 }, Orange = { 255, 170, 80 }, Lime = { 150, 255, 120 }, Licorice = { 30, 22, 40 }, Sugar = { 250, 246, 255 },
			Polish = false, IconViewport = true, PreviewDist = 15, IconFocus = { 0, 3.0, 0 }, IconDist = 9.5 } },
	{ Id = 'UY_BellReaper', Name = 'Bell Reaper', RU = 'Жнец Колокола', Icon = '🔔', Rarity = 'Secret', Chapter = 2,
		Theme = 'HW_UyBell', ThemeAlt = 'Anime', Swing = 'Reap', Sound = 'HW_UyBell', Color = { 170, 110, 255 }, Inspect = true,
		Trait = "Cosmetic · SECRET · the Black Bell's scythe · a violet moon for a blade",
		TraitRU = 'Косметика · СЕКРЕТ · коса Чёрного колокола · фиолетовая луна вместо лезвия',
		Lore = 'Only those who found every dog of the Underyard ever hear it ring. When it tolls, the moon answers.',
		LoreRU = 'Его звон слышат лишь те, кто нашёл всех собак Поддворья. Когда он бьёт, луна отвечает.',
		Visual = { Kind = 'HW_UyBellReaper', Length = 6, Shaft = { 22, 18, 28 }, ShaftMaterial = 'SmoothPlastic', Head = { 34, 30, 42 },
			Accent = { 170, 110, 255 }, Moon = { 200, 176, 255 }, Crater = { 120, 84, 196 }, Rope = { 196, 178, 140 }, Bone = { 232, 224, 204 },
			Polish = false, IconViewport = true, PreviewDist = 16, IconFocus = { 1.3, 2.7, 0 }, IconDist = 11 } },
}

S2.ById = {}
S2.Order = {}
for _, s in ipairs(S2.List) do
	S2.ById[s.Id] = s
	table.insert(S2.Order, s.Id)
end

---------------------------------------------------------------------------------------------------------------------
-- BUILDER HELPERS (the PickaxeSkins / MiningModels conventions: anchored, non-colliding, smooth surfaces)
---------------------------------------------------------------------------------------------------------------------
local SP, SL, ME, FA, NE, GL = Enum.Material.SmoothPlastic, Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Fabric, Enum.Material.Neon, Enum.Material.Glass
local WO, CM = Enum.Material.Wood, Enum.Material.CorrodedMetal
local V3, CF = Vector3.new, CFrame.new
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local SMALL = { CastShadow = false }
local GLOW = { CastShadow = false }

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
-- Cylinder along the model X axis (Roblox cylinders run along local X): bells, axles, hammer heads.
local function cylX(parent, name, length, d, cf, color, mat, props)
	local p = part(parent, name, V3(length, d, d), cf, color, mat, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- Cylinder along the model Y axis.
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
-- Ring of n boxes in the XY plane of cf (opening facing +-Z); color(i) shades every box; skip(i) leaves gaps.
local function ring(parent, name, cf, radius, thick, depth, n, color, mat, skip, props)
	local out = {}
	local len = 2 * radius * math.tan(math.pi / n) + .04
	for i = 0, n - 1 do
		if not (skip and skip(i)) then
			local a = i / n * math.pi * 2
			local c = type(color) == 'function' and color(i) or color
			table.insert(out, part(parent, name, V3(thick, len, depth), cf * CF(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a), c, mat, props))
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
local function animAll(list, kind, phase, joint)
	for _, p in ipairs(list) do
		anim(p, kind, phase, joint)
	end
	return list
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
local SPARK_TEX = 'rbxasset://textures/particles/sparkles_main.dds'
local SMOKE_TEX = 'rbxasset://textures/particles/smoke_main.dds'
-- A slow drifting particle emitter (begin -> peak -> fade); held models carry one per skin.
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
-- Deterministic hash noise (the same model on the server, on every client and offline; no Random dependency).
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
-- A rivet / nail head driven in at pos, facing along dir.
local function rivet(model, pos, dir, color, size)
	size = size or 1
	return part(model, 'Rivet', V3(.09, .035, .09) * size, CF(pos + dir * .015 * size) * alignY(dir), color, ME, { CastShadow = false, Reflectance = .1 })
end
-- Cubic Bezier point.
local function bez(p0, p1, p2, p3, t)
	local u = 1 - t
	return p0 * u * u * u + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t * t * t
end
-- A tube along the points (round rods with ball joints), diameter d0 -> d1; color(k) per segment.
local function tube(model, name, pts, d0, d1, color, mat, props, jointName)
	local out = {}
	for k = 1, #pts - 1 do
		local f = (k - 1) / math.max(1, #pts - 2)
		local d = d0 + (d1 - d0) * f
		local c = type(color) == 'function' and color(k) or color
		table.insert(out, rod(model, name, pts[k], pts[k + 1], d, c, mat, props))
		if k > 1 then
			table.insert(out, ball(model, jointName or name, d * 1.02, CF(pts[k]), c, mat, props))
		end
	end
	return out
end
-- A voxel shell: cubes of `cell` on the surface of the ellipsoid (rx, ry, rz) round centre; keep(p) filters (p is the
-- offset from the centre), color(p) shades every cube. Returns the cubes.
local function shell(model, name, centre, rx, ry, rz, cell, keep, color, mat, props)
	local out = {}
	local nx, ny, nz = math.ceil(rx / cell), math.ceil(ry / cell), math.ceil(rz / cell)
	local skin = cell / math.min(rx, ry, rz) * 1.15
	for i = -nx, nx do
		for j = -ny, ny do
			for k = -nz, nz do
				local p = V3(i * cell, j * cell, k * cell)
				local q = math.sqrt((p.X / rx) ^ 2 + (p.Y / ry) ^ 2 + (p.Z / rz) ^ 2)
				if q <= 1 and q > 1 - skin and (not keep or keep(p)) then
					table.insert(out, part(model, name, V3(cell + .004, cell + .004, cell + .004), CF(centre + p), color(p), mat, props))
				end
			end
		end
	end
	return out
end
-- A dog bone from a to b (shaft + two knobs at each end), lying in the plane facing `normal`.
local function dogBone(model, name, a, b, w, color, normal)
	local out = { bar(model, name, a, b, w, w * .8, color, SP) }
	local d = (b - a).Unit
	local side = d:Cross(normal or V3(0, 0, 1)).Unit
	for _, e in ipairs({ a, b }) do
		for _, s in ipairs({ -1, 1 }) do
			table.insert(out, ball(model, name .. 'Knob', w * 1.35, CF(e + side * s * w * .55), color, SP, SMALL))
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- DESIGNS
---------------------------------------------------------------------------------------------------------------------
local DESIGNS = {}

-- <<HW_UyToothyAlarm
-- TOOTHY ALARM (Epic): the funeral alarm clock of the Underyard. A round ink-iron clock case (a proud band round its
-- side, a bone-white voxel bezel, rivets) facing +Z: a pale moon-blue dial with dog-bone markers at 12 / 3 / 9 and
-- ticks, two mad sickly-green eyes under angry brows, bone clock hands, and the lower half of the face torn open into
-- a dark maw with a row of bone fangs above and a SNAPPING lower jaw. The glass broke when the mouth grew: only the
-- upper half is left, cracked, with jagged shards round the rim. TWIN BELL HAMMERS: two big verdigris bronze alarm
-- bells on iron arms at +-X are the striking faces (clappers inside), each with a little striker that trembles over
-- it. A carry ring on top with a moth on it, a melting candle on the shoulder, little clock feet standing on an iron
-- cradle, a paw print on the back plate. The pole is ink iron with black / bone stripes, a funeral ribbon bow and a
-- green-stitched grip; the pommel is the winding key (it turns).
-- Motion (PickFX generic): the jaw chomps (GummyJaw), the pupils look round (EyeLook), the minute hand turns
-- (HandSlow), the strikers tremble (Shake), the ribbon tails flutter (ScytheTalisman), the moth flaps (FlutterL/R),
-- the candle flame flickers (Shake + PickPulse), the key turns (Orbit); live: the hour hand, ringing, chatter.
DESIGNS.HW_UyToothyAlarm = function(model, v, def, len, top)
	local rnd = rng(2611)
	local shade = shader(rnd)
	local ink = rgb(v.Head)
	local poleC = rgb(v.Shaft)
	local bone = rgb(v.Trim)
	local glow = rgb(v.Accent)
	local bronze = rgb(v.Bell)
	local patina = rgb(v.Patina)
	local glass = rgb(v.Glass)
	local flameC = rgb(v.Candle)
	local maw = Color3.fromRGB(26, 10, 22)
	local iron = ink:Lerp(BLACK, .25)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local R = .95
	local H = V3(0, top.Y + R + .2, 0)          -- clock centre
	local FZ = .3                               -- the face plane
	local function at(x, y, z) return CF(H + V3(x, y, z)) end

	-- POLE: ink iron, flat edge strips, black / bone stripe bands, the grip ------------------------------------------------
	local y0, y1 = -half + .1, H.Y - R + .02
	cylY(model, 'Pole', y1 - y0, .3, CF(0, (y0 + y1) / 2, 0), shade(poleC, .06), SP, { Reflectance = .05 })
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		part(model, 'PoleEdge', V3(.05, y1 - y0 - .2, .05), CF(math.sin(a) * .135, (y0 + y1) / 2, math.cos(a) * .135), poleC:Lerp(bone, .1), SL, SMALL)
	end
	for k, by in ipairs({ -.62, -.36, -.1, .16, .42, .68 }) do
		cylY(model, k % 2 == 0 and 'StripeBone' or 'StripeInk', .2, .35, CF(0, by, 0), k % 2 == 0 and shade(bone, .05) or shade(maw:Lerp(ink, .5), .05), SP)
	end
	for _, by in ipairs({ -half + .3, -2.05, -.75, 1.55 }) do
		cylY(model, 'PoleCollar', .1, .4, CF(0, by, 0), shade(iron, .06), ME, { Reflectance = .08 })
	end
	for k = 0, 10 do
		local gy = -1.95 + k * .105
		part(model, 'GripWrap', V3(.4, .095, .4), CF(0, gy, 0) * CFrame.Angles(0, k * .35, (k % 2 == 0 and .08 or -.08)), shade(Color3.fromRGB(38, 30, 40), .12), material('Leather', FA))
		if k % 3 == 1 then
			part(model, 'GripStitch', V3(.26, .02, .02), CF(0, gy, .205) * CFrame.Angles(0, 0, .5), glow, NE, GLOW)
		end
	end
	-- the funeral ribbon bow (black with bone edging), its striped tails flutter
	local bowY = 1.08
	local ribbon = shade(maw:Lerp(ink, .35), .06)
	part(model, 'BowKnot', V3(.15, .15, .1), CF(0, bowY, .2), ribbon, FA)
	for _, sx in ipairs({ -1, 1 }) do
		blob(model, 'BowLoop', V3(.3, .17, .08), CF(sx * .19, bowY + .04, .2) * CFrame.Angles(0, 0, sx * .38), ribbon, FA)
		blob(model, 'BowLoopEdge', V3(.2, .07, .09), CF(sx * .21, bowY + .05, .2) * CFrame.Angles(0, 0, sx * .38), shade(bone, .04), FA, SMALL)
		local hang = V3(sx * .04, bowY - .05, .21)
		for k = 1, 4 do
			local tail = part(model, 'BowTail', V3(.09, .12, .02), CF(hang + V3(sx * k * .04, -k * .115, 0)) * CFrame.Angles(0, 0, sx * .3), k % 2 == 0 and shade(bone, .04) or ribbon, FA, SMALL)
			anim(tail, 'ScytheTalisman', sx * .7, hang)
		end
		wedge(model, 'BowTailEnd', V3(.02, .1, .09), CF(hang + V3(sx * .2, -.6, 0)) * CFrame.Angles(0, math.pi / 2, math.pi) * CFrame.Angles(0, 0, 0), ribbon, FA, SMALL)
	end
	-- the cradle the clock stands in
	cylY(model, 'Cradle', .14, .46, CF(0, y1 - .05, 0), shade(iron, .06), ME, { Reflectance = .06 })
	for _, sx in ipairs({ -1, 1 }) do
		bar(model, 'CradleArm', V3(sx * .18, y1 - .05, 0), V3(sx * .5, H.Y - R * .8, 0), .08, .14, shade(iron, .06), ME)
	end

	-- CASE: the drum, its side band, the bezel, the back ---------------------------------------------------------------------
	cylZ(model, 'Case', FZ * 2 - .04, R * 2 - .06, CF(H), shade(ink, .04), SP)
	ring(model, 'CaseBand', CF(H), R - .03, .11, .26, 28, function() return shade(ink:Lerp(bone, .06), .12) end, ME, nil, { Reflectance = .05 })
	ring(model, 'Bezel', CF(H + V3(0, 0, FZ + .02)), R - .1, .17, .18, 28, function(i) return shade(i % 7 == 0 and bone:Lerp(BLACK, .12) or bone, .08) end, SP)
	ring(model, 'BackRim', CF(H - V3(0, 0, FZ)), R - .1, .14, .12, 24, function() return shade(iron, .1) end, ME)
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2 + .3
		rivet(model, H + V3(math.cos(a) * (R + .03), math.sin(a) * (R + .03), 0), V3(math.cos(a), math.sin(a), 0), bone:Lerp(BLACK, .2), 1.1)
	end
	cylZ(model, 'BackPlate', .05, 1.5, CF(H - V3(0, 0, FZ + .02)), shade(iron:Lerp(BLACK, .2), .05), ME)
	-- a paw print on the back plate, the alarm knob and the set screw
	blob(model, 'PawPad', V3(.4, .32, .05), at(0, -.12, -FZ - .06), shade(bone, .05), SP)
	for _, toe in ipairs({ { -.22, .14 }, { -.08, .25 }, { .08, .25 }, { .22, .14 } }) do
		blob(model, 'PawToe', V3(.14, .16, .05), at(toe[1], toe[2], -FZ - .06), shade(bone, .05), SP)
	end
	cylZ(model, 'AlarmKnob', .12, .2, at(-.5, .48, -FZ - .08), shade(bronze, .06), ME)
	cylZ(model, 'SetScrew', .1, .14, at(.52, .46, -FZ - .07), shade(bronze, .06), ME)

	-- DIAL: pale moon-blue face, dog-bone markers, ticks -------------------------------------------------------------------
	cylZ(model, 'Dial', .04, R * 2 - .3, CF(H + V3(0, 0, FZ - .03)), glass:Lerp(WHITE, .55), SP)
	for k = 0, 6 do
		local a = math.rad(k * 30)
		local p = V3(math.cos(a) * .64, math.sin(a) * .64, FZ)
		if k == 0 or k == 3 or k == 6 then
			local d = V3(math.cos(a), math.sin(a), 0)
			dogBone(model, 'DialBone', H + p - d * .08, H + p + d * .08, .05, ink:Lerp(BLACK, .2), V3(0, 0, 1))
		else
			part(model, 'DialTick', V3(.12, .04, .02), CF(H + p) * CFrame.Angles(0, 0, a), ink:Lerp(BLACK, .2), SP, SMALL)
		end
	end
	-- eyes: dark sockets, green eyeballs, slit pupils that look round, angry brows
	for _, sx in ipairs({ -1, 1 }) do
		blob(model, 'EyeSocket', V3(.36, .32, .05), at(sx * .29, .27, FZ), maw, SP)
		local eye = ball(model, 'AlarmEye', .25, at(sx * .29, .27, FZ + .02), glow, NE, GLOW)
		eye:SetAttribute('PickPulse', true)
		local pivot = H + V3(sx * .29, .27, FZ + .02)
		anim(part(model, 'AlarmPupil', V3(.055, .17, .03), at(sx * .29, .27, FZ + .14), Color3.fromRGB(12, 30, 16), SP, SMALL), 'EyeLook', sx * .7, pivot)
		anim(ball(model, 'AlarmGlint', .05, at(sx * .29 + .05, .33, FZ + .13), WHITE, NE, SMALL), 'EyeLook', sx * .7, pivot)
		part(model, 'Brow', V3(.34, .07, .06), at(sx * .3, .47, FZ + .04) * CFrame.Angles(0, 0, sx * -.32), shade(ink:Lerp(BLACK, .3), .05), SP)
	end
	-- the maw: a torn mouth, fangs above, the snapping jaw below, a green throat glow
	blob(model, 'Maw', V3(1.24, .56, .05), at(0, -.36, FZ), maw, SP)
	local throat = blob(model, 'MawGlow', V3(.7, .24, .03), at(0, -.4, FZ + .015), glow, NE, { Transparency = .55, CastShadow = false })
	throat:SetAttribute('PickPulse', true)
	for k = -3, 3 do
		local x = k * .15
		local lenK = .17 + (k % 2 == 0 and .05 or 0) - math.abs(k) * .01
		spike(model, 'UpperFang', H + V3(x, -.12 - math.abs(k) * .018, FZ + .03), V3(0, -1, 0), V3(0, 0, 1), lenK, .12, .07, shade(bone, .06), SP)
	end
	part(model, 'UpperGum', V3(1.05, .06, .06), at(0, -.12, FZ + .02), shade(Color3.fromRGB(120, 40, 60), .08), SP)
	local jawPivot = H + V3(0, -.5, FZ - .3)
	local jaw = {}
	table.insert(jaw, part(model, 'JawLip', V3(.98, .07, .07), at(0, -.62, FZ + .03), shade(Color3.fromRGB(120, 40, 60), .08), SP))
	for k = -2, 2 do
		table.insert(jaw, spike(model, 'LowerFang', H + V3(k * .16 + .02, -.6 + math.abs(k) * .02, FZ + .04), V3(0, 1, 0), V3(0, 0, 1), .15 + (k == 0 and .03 or 0), .11, .06, shade(bone, .06), SP))
	end
	animAll(jaw, 'GummyJaw', 0, jawPivot)
	-- the hands (bone): the minute hand turns, the hour hand creeps (live), the hub
	local hub = H + V3(0, .02, FZ + .1)
	local minute = dogBone(model, 'MinuteHand', hub, hub + V3(0, .56, 0), .045, bone:Lerp(WHITE, .2), V3(0, 0, 1))
	table.insert(minute, spike(model, 'MinuteHand', hub + V3(0, .56, 0), V3(0, 1, 0), V3(0, 0, 1), .12, .1, .03, bone:Lerp(WHITE, .2), SP, SMALL))
	animAll(minute, 'HandSlow', 0, hub)
	local hour = dogBone(model, 'HourHand', hub, hub + V3(-.27, .2, .02), .055, bone, V3(0, 0, 1))
	animAll(hour, 'Live', 0, hub)
	ball(model, 'HandHub', .13, CF(hub + V3(0, 0, .03)), shade(bronze, .05), ME)
	ball(model, 'HandPin', .05, CF(hub + V3(0, 0, .09)), glow, NE, SMALL)
	-- the broken glass: the upper half survived (cracked), shards round the lower rim
	for j = 0, 4 do
		local gy = -.06 + j * .17
		local w = 2 * math.sqrt(math.max(0, (R - .18) ^ 2 - (gy + .085) ^ 2)) - .02
		if w > .1 then
			part(model, 'DialGlass', V3(w, .17, .02), at(0, gy + .085, FZ + .16), glass, GL, { Transparency = .72, CastShadow = false })
		end
	end
	for k = 1, 7 do
		local a = math.rad(200 + k * 18)
		local r = R - .2
		local p = H + V3(math.cos(a) * r, math.sin(a) * r, FZ + .16)
		spike(model, 'GlassShard', p, V3(-math.cos(a), -math.sin(a), 0), V3(0, 0, 1), .1 + rnd() * .1, .08, .02, glass:Lerp(WHITE, .4), GL, { Transparency = .45, CastShadow = false })
	end
	local crackAt = H + V3(.38, .52, FZ + .18)
	for _, d in ipairs({ V3(-.3, .06, 0), V3(-.1, -.28, 0), V3(.08, -.22, 0), V3(-.22, -.14, 0) }) do
		bar(model, 'GlassCrack', crackAt, crackAt + d, .018, .01, Color3.fromRGB(60, 70, 90), SP, { Transparency = .2, CastShadow = false })
	end

	-- TWIN BELL HAMMERS (+-X): iron arms, verdigris bronze bells (mouth out), clappers, trembling strikers -------------------
	local bellY = .22
	-- bell profile along X from the crown: {offset, diameter, length} (round shoulder, straight waist, flared lip)
	local PROFILE = { { .03, .26, .06 }, { .09, .46, .07 }, { .17, .6, .1 }, { .28, .64, .13 }, { .4, .67, .12 }, { .5, .74, .08 }, { .57, .84, .06 }, { .625, .95, .05 } }
	local function bellR(off)
		local prev = PROFILE[1]
		for _, row in ipairs(PROFILE) do
			if row[1] >= off then
				local f = (off - prev[1]) / math.max(1e-3, row[1] - prev[1])
				return (prev[2] + (row[2] - prev[2]) * math.clamp(f, 0, 1)) * .5
			end
			prev = row
		end
		return prev[2] * .5
	end
	for _, sx in ipairs({ -1, 1 }) do
		local crownX = sx * 1.16
		local root = H + V3(sx * (R - .06), bellY, 0)
		bar(model, 'BellArm', root, H + V3(crownX, bellY, 0), .14, .16, shade(iron, .06), ME, { Reflectance = .05 })
		cylX(model, 'BellArmCollar', .08, .24, at(sx * (R + .06), bellY, 0), shade(bronze, .06), ME)
		-- a curled brace from the case shoulder to the crown
		local b0, b3 = H + V3(sx * .5, .78, 0), H + V3(crownX + sx * .04, bellY + .16, 0)
		local pts = {}
		for k = 0, 5 do
			local t = k / 5
			table.insert(pts, bez(b0, H + V3(sx * .95, 1.05, 0), H + V3(sx * 1.25, .75, 0), b3, t))
		end
		tube(model, 'BellBrace', pts, .07, .06, function() return shade(iron, .06) end, ME)
		ball(model, 'BraceCurl', .12, CF(b0), shade(bronze, .06), ME)
		-- the bell along X
		for i, row in ipairs(PROFILE) do
			local col = (i == 4 or i == 7) and shade(bronze:Lerp(patina, .5), .08) or shade(bronze, .08)
			cylX(model, 'Bell', row[3], row[2], at(crownX + sx * row[1], bellY, 0), col, ME, { Reflectance = .08 })
		end
		cylX(model, 'BellBand', .03, .7, at(crownX + sx * .34, bellY, 0), bronze:Lerp(WHITE, .25), ME, { Reflectance = .15 })
		cylX(model, 'BellBand', .025, .98, at(crownX + sx * .64, bellY, 0), bronze:Lerp(WHITE, .2), ME, { Reflectance = .15 })
		cylX(model, 'BellMouth', .02, .8, at(crownX + sx * .66, bellY, 0), Color3.fromRGB(30, 22, 18), SP)
		ball(model, 'BellCrown', .2, at(crownX - sx * .03, bellY, 0), shade(bronze, .05), ME)
		local clapper = ball(model, 'BellClapper', .18, at(crownX + sx * .56, bellY - .16, 0), iron, ME)
		anim(clapper, 'Shake', sx, H + V3(crownX + sx * .2, bellY, 0))
		-- verdigris streaks running down the bell
		for k = 1, 5 do
			local a = rnd() * math.pi * 2
			local off = .2 + rnd() * .3
			local rr = bellR(off) + .005
			part(model, 'Patina', V3(.1 + rnd() * .1, .03, .07), at(crownX + sx * off, bellY + math.cos(a) * rr, math.sin(a) * rr) * CFrame.Angles(a, 0, 0), patina:Lerp(WHITE, k % 2 * .15), SP, SMALL)
		end
		-- the striker trembling over the bell
		local post = H + V3(sx * .62, .72, -.05)
		local strike = {}
		table.insert(strike, rod(model, 'StrikerArm', post, H + V3(sx * 1.42, bellY + .52, -.05), .05, shade(iron, .05), ME))
		table.insert(strike, ball(model, 'Striker', .15, at(sx * 1.42, bellY + .5, -.05), shade(bronze, .05), ME))
		animAll(strike, 'Shake', sx * 1.3, post)
		ball(model, 'StrikerPost', .12, CF(post), shade(iron, .05), ME)
	end

	-- TOP: the carry ring with a moth on it, the melting candle on the shoulder ----------------------------------------------
	local ringC = H + V3(0, R + .32, 0)
	part(model, 'RingPost', V3(.12, .2, .12), CF(H + V3(0, R + .02, 0)), shade(iron, .05), ME)
	ring(model, 'CarryRing', CF(ringC), .25, .07, .09, 14, function() return shade(iron:Lerp(bone, .15), .08) end, ME)
	local mothAt = ringC + V3(.08, .27, .02)
	blob(model, 'MothBody', V3(.07, .07, .2), CF(mothAt) * CFrame.Angles(math.rad(70), 0, 0), Color3.fromRGB(70, 60, 54), SP, SMALL)
	for _, sx in ipairs({ -1, 1 }) do
		local wing = part(model, 'MothWing', V3(.2, .02, .14), CF(mothAt + V3(sx * .11, .01, 0)) * CFrame.Angles(0, 0, sx * .25), Color3.fromRGB(196, 186, 168), SP, SMALL)
		anim(wing, sx < 0 and 'FlutterL' or 'FlutterR', 0, mothAt)
		part(model, 'MothSpot', V3(.05, .025, .05), CF(mothAt + V3(sx * .13, .025, 0)), glow, NE, SMALL)
	end
	local cA = math.rad(55)
	local cBase = H + V3(math.cos(cA) * (R - .02), math.sin(cA) * (R - .02) + .02, .08)
	cylY(model, 'CandleDish', .04, .26, CF(cBase), shade(bronze, .05), ME)
	cylY(model, 'Candle', .3, .13, CF(cBase + V3(0, .17, 0)), shade(bone, .04), SP)
	for k = 1, 3 do
		local a = k * 2.1
		part(model, 'WaxDrip', V3(.04, .08 + k * .03, .04), CF(cBase + V3(math.cos(a) * .065, .2 - k * .03, math.sin(a) * .065)), bone:Lerp(WHITE, .3), SP, SMALL)
	end
	part(model, 'Wick', V3(.02, .05, .02), CF(cBase + V3(0, .345, 0)), BLACK, SP, SMALL)
	local flame = blob(model, 'CandleFlame', V3(.08, .16, .08), CF(cBase + V3(0, .43, 0)), flameC, NE, GLOW)
	flame:SetAttribute('PickPulse', true)
	anim(flame, 'Shake', .4, cBase + V3(0, .35, 0))
	light(flame, 'CandleLight', flameC, 4, .6)
	-- clock feet
	for _, sx in ipairs({ -1, 1 }) do
		local a = math.rad(-90 + sx * 38)
		local f0 = H + V3(math.cos(a) * (R - .05), math.sin(a) * (R - .05), 0)
		local f1 = f0 + V3(sx * .2, -.3, 0)
		bar(model, 'ClockLeg', f0, f1, .1, .12, shade(iron, .06), ME)
		ball(model, 'ClockFoot', .2, CF(f1), shade(bone, .05), SP)
	end
	-- a cobweb between the left bell arm and the case
	local wc = H + V3(-R - .02, .62, .05)
	for _, s in ipairs({ V3(-.42, -.02, 0), V3(-.3, -.32, 0), V3(-.02, -.36, 0) }) do
		bar(model, 'Cobweb', wc, wc + s, .016, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .3, CastShadow = false })
	end
	bar(model, 'Cobweb', wc + V3(-.24, -.01, 0), wc + V3(-.17, -.18, 0), .014, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .4, CastShadow = false })
	bar(model, 'Cobweb', wc + V3(-.17, -.18, 0), wc + V3(-.01, -.21, 0), .014, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .4, CastShadow = false })

	-- POMMEL: the winding key (turns round the pole) ---------------------------------------------------------------------------
	local kY = -half - .12
	local key = {}
	table.insert(key, cylY(model, 'KeyShaft', .26, .12, CF(0, kY, 0), shade(bronze, .05), ME, { Reflectance = .1 }))
	table.insert(key, part(model, 'KeyBridge', V3(.5, .1, .08), CF(0, kY - .2, 0), shade(bronze, .05), ME, { Reflectance = .1 }))
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(key, cylZ(model, 'KeyLobe', .08, .34, CF(sx * .25, kY - .26, 0), shade(bronze, .05), ME, { Reflectance = .1 }))
		table.insert(key, cylZ(model, 'KeyHole', .1, .12, CF(sx * .25, kY - .26, 0), Color3.fromRGB(30, 22, 18), SP, SMALL))
	end
	animAll(key, 'Orbit', 0, V3(0, kY, 0))

	-- LIGHT + FX -------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'DialGlow', V3(.4, .4, .1), at(0, -.05, FZ - .1), glow, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'DialLight', glow, 6.5, .9)
	emitter(lamp, 'MawSparks', SPARK_TEX, glow:Lerp(WHITE, .3), 2, .22, .6, 1.3, V3(0, 1.2, 0))

	model:SetAttribute('BackC0', CF(.25, -.3, .3))
	model:SetAttribute('DisplayScale', .82)
	return H + V3(-1.8, bellY, 0), H + V3(1.8, bellY, 0)
end
-- >>HW_UyToothyAlarm

-- <<HW_UyFateHand
-- BURIED HAND OF FATE (Legendary): a pale grave hand clutching an HOURGLASS PICK. The pick head IS the hourglass,
-- lying along X: two glass bulbs meet at a narrow neck hidden in the fist, glowing sand heaped in both (moon-blue on
-- the -X side, violet on the +X side), each bulb caged by bronze posts between an inner collar and a dark end plate.
-- Beyond the end plates: a long curved iron pick point (+X) and a square iron hammer with a moon on its face (-X). The
-- hand: a voxel palm behind the neck, four long fingers wrapped over the top and down the front (dirt on the
-- knuckles, long dark nails), the thumb across them, a gold funeral ring with a violet stone, tendons and a stitched
-- scar on the back. The POLE is the forearm: pale, veined, stitched, wrapped in strips of burial shroud (loose ends
-- flutter), a linen-bandaged grip, a black cuff and a bead bracelet with a moon charm at the wrist. The POMMEL is the
-- grave it climbed out of: a clump of earth with grass, a tiny tombstone and a worm. A moth rests on the +X plate.
-- Motion: the shroud ends and the charm flutter (ScytheTalisman), the moth flaps (FlutterL/R), the worm wriggles
-- (Wave), the sand and the stone pulse (PickPulse); live: the fingers squeeze on a strike and open in the inspect.
DESIGNS.HW_UyFateHand = function(model, v, def, len, top)
	local rnd = rng(3307)
	local shade = shader(rnd)
	local skin = rgb(v.Skin)
	local iron = rgb(v.Head)
	local blue = rgb(v.Accent)
	local violet = rgb(v.Sand)
	local cloth = rgb(v.Cloth)
	local dirt = rgb(v.Dirt)
	local gold = rgb(v.Gold)
	local bone = rgb(v.Trim)
	local bronze = Color3.fromRGB(150, 116, 70)
	local nailC = Color3.fromRGB(58, 46, 56)
	local vein = Color3.fromRGB(120, 110, 150)
	local glassC = Color3.fromRGB(206, 224, 255)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, top.Y + .78, 0)            -- the hourglass axis / fist centre
	local function at(x, y, z) return CF(H + V3(x, y, z)) end

	-- FOREARM (the pole): pale segments, veins, a stitched seam, a torn patch showing bone --------------------------------
	local yA, yW = -half + .02, H.Y - .98
	local y = yA
	local k = 0
	while y < yW - .01 do
		local h = math.min(.34, yW - y)
		local f = (y - yA) / (yW - yA)
		cylY(model, 'Forearm', h + .01, .4 - f * .06, CF(0, y + h / 2, 0) * CFrame.Angles(0, k * .7, 0), shade(skin, .1), SP)
		y += h
		k += 1
	end
	for _, vv in ipairs({ { .4, .15, 1.1, .6 }, { 2.3, -.2, .9, .4 } }) do
		local a = vv[1]
		local p0 = V3(math.sin(a) * .2, vv[2], math.cos(a) * .2)
		local p1 = V3(math.sin(a + .5) * .19, vv[2] + vv[3], math.cos(a + .5) * .19)
		bar(model, 'Vein', p0, p1, .03, .02, vein, SP, SMALL)
		bar(model, 'Vein', p1, p1 + V3(math.sin(a) * .01, vv[4], math.cos(a) * .01), .025, .02, vein, SP, SMALL)
	end
	part(model, 'Seam', V3(.03, .8, .02), CF(.1, .55, .19) * CFrame.Angles(0, .5, 0), Color3.fromRGB(110, 70, 80), SP, SMALL)
	for s = 0, 4 do
		part(model, 'Stitch', V3(.12, .025, .02), CF(.1, .23 + s * .16, .2) * CFrame.Angles(0, .5, .4), Color3.fromRGB(40, 30, 36), SP, SMALL)
	end
	part(model, 'TornPatch', V3(.2, .3, .03), CF(-.06, -.15, -.19) * CFrame.Angles(0, math.pi + .3, 0), Color3.fromRGB(90, 60, 70), SP, SMALL)
	part(model, 'BoneShow', V3(.12, .22, .03), CF(-.06, -.15, -.205) * CFrame.Angles(0, math.pi + .3, 0), bone, SP, SMALL)
	-- burial shroud: two bands of three diagonal strips, a loose end on each that flutters
	for bi, band in ipairs({ { -.6, 3 }, { .5, 3 } }) do
		for st = 0, band[2] - 1 do
			part(model, 'Shroud', V3(.46, .12, .46), CF(0, band[1] + st * .15, 0) * CFrame.Angles(0, st * .9, .36 * (bi % 2 == 0 and 1 or -1)), shade(cloth, .08), FA)
		end
		local a = bi * 2.2
		local hang = V3(math.cos(a) * .23, band[1] + band[2] * .15 - .05, math.sin(a) * .23)
		for st = 1, 4 do
			anim(part(model, 'ShroudEnd', V3(.12 - st * .014, .17, .02), CF(hang + V3(math.cos(a) * st * .04, -st * .15, math.sin(a) * st * .04)) * CFrame.Angles(0, -a + math.pi / 2, .12 * st),
				shade(cloth, .06), FA, { CastShadow = false, Transparency = st == 4 and .2 or 0 }), 'ScytheTalisman', bi * .8, hang)
		end
	end
	-- the grip: linen bandage with grave stains
	for g = 0, 10 do
		local gy = -1.95 + g * .105
		part(model, 'Bandage', V3(.46, .095, .46), CF(0, gy, 0) * CFrame.Angles(0, g * .35, (g % 2 == 0 and .1 or -.1)), g % 4 == 2 and shade(cloth:Lerp(dirt, .35), .08) or shade(cloth, .08), FA)
	end
	-- the wrist: a black cuff and a bead bracelet with a crescent-moon charm
	local cuffY = yW - .1
	cylY(model, 'Cuff', .14, .44, CF(0, cuffY, 0), Color3.fromRGB(28, 22, 32), FA)
	cylY(model, 'CuffEdge', .03, .46, CF(0, cuffY + .07, 0), bone, FA, SMALL)
	local braceY = cuffY - .22
	for b = 0, 11 do
		local a = b / 12 * math.pi * 2
		ball(model, 'Bead', .09, CF(math.cos(a) * .215, braceY + math.sin(b * 1.7) * .015, math.sin(a) * .215), b % 3 == 0 and violet:Lerp(BLACK, .3) or Color3.fromRGB(40, 30, 44), SP, SMALL)
	end
	local charmHang = V3(0, braceY - .03, .24)
	local charm = {}
	table.insert(charm, part(model, 'CharmLink', V3(.03, .1, .03), CF(charmHang - V3(0, .06, 0)), bronze, ME, SMALL))
	table.insert(charm, part(model, 'CharmMoon', V3(.05, .2, .03), CF(charmHang - V3(.03, .2, 0)) * CFrame.Angles(0, 0, .2), gold, ME, SMALL))
	table.insert(charm, part(model, 'CharmMoon', V3(.06, .08, .03), CF(charmHang - V3(-.02, .29, 0)) * CFrame.Angles(0, 0, -.9), gold, ME, SMALL))
	table.insert(charm, part(model, 'CharmMoon', V3(.06, .08, .03), CF(charmHang - V3(-.02, .11, 0)) * CFrame.Angles(0, 0, .9), gold, ME, SMALL))
	animAll(charm, 'ScytheTalisman', .3, charmHang)

	-- THE HAND: wrist, palm, back of the hand ----------------------------------------------------------------------------------
	local wristTop = H + V3(0, -.56, -.2)
	rod(model, 'Wrist', V3(0, yW - .04, 0), wristTop, .44, shade(skin, .05), SP)
	ball(model, 'WristJoint', .46, CF(wristTop), shade(skin, .05), SP)
	ball(model, 'UlnaKnob', .15, CF(V3(.2, yW + .18, -.06)), shade(skin:Lerp(WHITE, .1), .04), SP, SMALL)
	part(model, 'Palm', V3(.92, .62, .3), at(0, -.22, -.29), shade(skin, .05), SP)
	part(model, 'PalmHeel', V3(.76, .22, .32), at(0, -.48, -.25), shade(skin:Lerp(BLACK, .05), .04), SP)
	for t = -1, 2 do
		bar(model, 'Tendon', H + V3(t * .16 - .08, -.46, -.45), H + V3(t * .2 - .1, .04, -.45), .045, .03, skin:Lerp(vein, .35), SP, SMALL)
	end
	part(model, 'HandScar', V3(.03, .36, .02), at(.2, -.24, -.445) * CFrame.Angles(0, 0, .5), Color3.fromRGB(110, 70, 80), SP, SMALL)
	for st = 0, 2 do
		part(model, 'Stitch', V3(.11, .024, .02), at(.13 + st * .065, -.33 + st * .1, -.45) * CFrame.Angles(0, 0, -.9), Color3.fromRGB(40, 30, 36), SP, SMALL)
	end
	-- four long fingers over the top of the neck and down its front (index at -X, pinky at +X): the middle joint bulges,
	-- the tips curl under, long dark nails, grave dirt on the knuckles; the thumb crosses them from -X
	local FING = { { -.3, 1.0 }, { -.1, 1.08 }, { .1, 1.02 }, { .3, .86 } }
	for i, f in ipairs(FING) do
		local x, kf = f[1], f[2]
		local k1 = H + V3(x, .06, -.3)
		local k2 = H + V3(x, .2 + .06 * kf, -.05)
		local k3 = H + V3(x, .08 + .04 * kf, .24 + .04 * kf)
		local k4 = H + V3(x, -.2 - .04 * kf, .16)
		local col = shade(skin, .07)
		local finger = {}
		table.insert(finger, bar(model, 'Finger', k1, k2, .17, .17, col, SP))
		table.insert(finger, ball(model, 'Knuckle', .19, CF(k2), shade(skin, .05), SP))
		table.insert(finger, bar(model, 'Finger', k2, k3, .165, .165, col, SP))
		table.insert(finger, ball(model, 'Knuckle', .18, CF(k3), shade(skin:Lerp(WHITE, .08), .05), SP))
		table.insert(finger, bar(model, 'Finger', k3, k4, .15, .15, shade(skin, .07), SP))
		local along = (k4 - k3).Unit
		local outward = along:Cross(V3(1, 0, 0)).Unit
		if outward.Z < 0 then outward = -outward end
		table.insert(finger, bar(model, 'Nail', k4 - along * .14 + outward * .07, k4 + outward * .07, .12, .03, nailC, SP))
		table.insert(finger, spike(model, 'NailTip', k4 + outward * .06, along, outward, .13, .11, .03, nailC, SP))
		if i % 2 == 1 then
			table.insert(finger, part(model, 'KnuckleDirt', V3(.1, .05, .06), CF(k3 + V3(.03, .06, .07)) * CFrame.Angles(.4, 0, .3), shade(dirt, .15), Enum.Material.Ground, SMALL))
		end
		if i == 3 then -- the funeral ring on the ring finger
			local mid = (k1 + k2) / 2
			table.insert(finger, bar(model, 'FuneralRing', mid - (k2 - k1).Unit * .035, mid + (k2 - k1).Unit * .035, .21, .21, gold, ME, { Reflectance = .2 }))
			local stone = ball(model, 'RingStone', .1, CF(mid + V3(0, .11, -.02)), violet, NE, GLOW)
			stone:SetAttribute('PickPulse', true)
			table.insert(finger, stone)
		end
		animAll(finger, 'Live', i * .2, k1)
	end
	local thumb = {}
	local t1, t2, t3, t4 = H + V3(-.44, -.34, -.14), H + V3(-.52, -.12, .14), H + V3(-.3, -.05, .36), H + V3(-.06, -.07, .38)
	table.insert(thumb, bar(model, 'Thumb', t1, t2, .2, .2, shade(skin, .05), SP))
	table.insert(thumb, ball(model, 'Knuckle', .21, CF(t2), shade(skin, .05), SP))
	table.insert(thumb, bar(model, 'Thumb', t2, t3, .19, .19, shade(skin, .05), SP))
	table.insert(thumb, ball(model, 'Knuckle', .19, CF(t3), shade(skin:Lerp(WHITE, .08), .05), SP))
	table.insert(thumb, bar(model, 'Thumb', t3, t4, .17, .17, shade(skin, .05), SP))
	table.insert(thumb, bar(model, 'Nail', t4 - V3(.13, 0, 0) + V3(0, 0, .08), t4 + V3(0, 0, .08), .13, .03, nailC, SP))
	table.insert(thumb, spike(model, 'NailTip', t4 + V3(0, 0, .07), V3(1, -.1, 0), V3(0, 0, 1), .13, .12, .03, nailC, SP))
	animAll(thumb, 'Live', .9, t1)

	-- THE HOURGLASS PICK (along X): glass bulbs, glowing sand, collars, end plates, bronze cage posts ------------------------
	local BULB = { { .56, .3 }, { .64, .48 }, { .72, .62 }, { .8, .72 }, { .88, .78 }, { .96, .76 }, { 1.04, .68 }, { 1.12, .56 }, { 1.18, .44 } }
	for _, sx in ipairs({ -1, 1 }) do
		local sandC = sx < 0 and blue or violet
		for b, row in ipairs(BULB) do
			local d = row[2]
			cylX(model, 'HourglassBulb', .085, d, at(sx * row[1], 0, 0), glassC, GL, { Transparency = .62, CastShadow = false })
			if b >= 2 and b <= 8 then
				local ds = d * .62
				local sand = cylX(model, 'Sand', .085, ds, at(sx * row[1], -(d - ds) / 2 + .03, 0), sandC, NE, { Transparency = .1, CastShadow = false })
				if b % 3 == 0 then sand:SetAttribute('PickPulse', true) end
			end
		end
		ball(model, 'SandHeap', .3, at(sx * .84, -.12, 0), sandC:Lerp(WHITE, .25), NE, { Transparency = .2, CastShadow = false })
		cylX(model, 'NeckCollar', .07, .46, at(sx * .51, 0, 0), shade(bronze, .06), ME, { Reflectance = .12 })
		cylX(model, 'EndPlate', .12, .98, at(sx * 1.25, 0, 0), shade(iron, .06), WO)
		cylX(model, 'EndPlateRim', .05, 1.02, at(sx * 1.2, 0, 0), shade(bronze, .06), ME, { Reflectance = .12 })
		for p = 0, 3 do
			local a = p / 4 * math.pi * 2 + math.pi / 4
			local q0 = H + V3(sx * .54, math.cos(a) * .2, math.sin(a) * .2)
			local q1 = H + V3(sx * 1.18, math.cos(a) * .42, math.sin(a) * .42)
			local mid = H + V3(sx * .88, math.cos(a) * .44, math.sin(a) * .44)
			rod(model, 'CagePost', q0, mid, .055, shade(bronze, .05), ME)
			rod(model, 'CagePost', mid, q1, .055, shade(bronze, .05), ME)
			ball(model, 'CageBead', .09, CF(mid), shade(bronze:Lerp(WHITE, .2), .05), ME)
		end
	end
	-- +X: the long curved pick point
	local p0, p3 = H + V3(1.3, 0, 0), H + V3(2.36, -.74, 0)
	local pts = {}
	for s = 0, 6 do
		table.insert(pts, bez(p0, H + V3(1.8, .06, 0), H + V3(2.16, -.12, 0), p3, s / 6))
	end
	for s = 1, #pts - 1 do
		local f = (s - 1) / (#pts - 1)
		bar(model, 'PickPoint', pts[s], pts[s + 1] + (pts[s + 1] - pts[s]).Unit * .03, .3 - f * .2, .26 - f * .16, shade(iron, .08), ME, { Reflectance = .05 })
	end
	spike(model, 'PickTip', pts[#pts], (pts[#pts] - pts[#pts - 1]), V3(0, 0, 1), .28, .1, .08, bone, SP)
	cylX(model, 'PickCollar', .1, .4, at(1.36, 0, 0), shade(bronze, .05), ME, { Reflectance = .12 })
	for s = 2, 5, 3 do
		bar(model, 'PickBand', pts[s] + V3(0, .02, 0), pts[s + 1] - (pts[s + 1] - pts[s]).Unit * .15, .3 - (s - 1) / 6 * .2 + .03, .27 - (s - 1) / 6 * .16 + .03, shade(bronze, .05), ME)
	end
	-- -X: the square hammer with a moon on its face
	part(model, 'Hammer', V3(.36, .52, .5), at(-1.5, 0, 0), shade(iron, .06), ME, { Reflectance = .05 })
	for _, yy in ipairs({ -.2, .2 }) do
		part(model, 'HammerBand', V3(.38, .06, .54), at(-1.5, yy, 0), shade(bronze, .05), ME, { Reflectance = .12 })
	end
	cylX(model, 'HammerFace', .05, .44, at(-1.7, 0, 0), shade(iron:Lerp(WHITE, .1), .05), ME)
	local moon = blob(model, 'HammerMoon', V3(.03, .26, .26), at(-1.73, .02, .02), blue:Lerp(WHITE, .3), NE, GLOW)
	moon:SetAttribute('PickPulse', true)
	blob(model, 'HammerMoonShadow', V3(.035, .22, .22), at(-1.74, .06, .08), iron, SP, SMALL)
	-- the moth on the +X plate
	local mothAt = H + V3(1.25, .55, .02)
	blob(model, 'MothBody', V3(.07, .2, .07), CF(mothAt), Color3.fromRGB(70, 60, 54), SP, SMALL)
	for _, sz in ipairs({ -1, 1 }) do
		local wing = part(model, 'MothWing', V3(.02, .14, .2), CF(mothAt + V3(0, .01, sz * .11)) * CFrame.Angles(sz * .25, 0, 0), Color3.fromRGB(196, 186, 168), SP, SMALL)
		anim(wing, sz < 0 and 'FlutterL' or 'FlutterR', .5, mothAt)
		part(model, 'MothSpot', V3(.025, .05, .05), CF(mothAt + V3(.012, .02, sz * .13)), blue, NE, SMALL)
	end

	-- POMMEL: the grave it climbed out of ------------------------------------------------------------------------------------
	local G = V3(0, -half - .12, 0)
	for c = 1, 16 do
		local a = rnd() * math.pi * 2
		local r = .1 + rnd() * .26
		local s = .16 + rnd() * .12
		part(model, 'GraveEarth', V3(s, s * .8, s), CF(G + V3(math.cos(a) * r, (rnd() - .5) * .24 - r * .3, math.sin(a) * r)) * CFrame.Angles(rnd(), rnd() * 3, rnd()), shade(dirt, .2), Enum.Material.Ground)
	end
	part(model, 'GraveEarth', V3(.5, .22, .5), CF(G + V3(0, .02, 0)), shade(dirt, .1), Enum.Material.Ground)
	for g = -1, 1 do
		wedge(model, 'GraveGrass', V3(.03, .2 + rnd() * .08, .07), CF(G + V3(-.2 + g * .05, .2, .12)) * CFrame.Angles(0, 0, g * .3), Color3.fromRGB(86, 120, 56), Enum.Material.Grass, SMALL)
		wedge(model, 'GraveGrass', V3(.03, .16 + rnd() * .08, .07), CF(G + V3(.1 + g * .05, .19, -.2)) * CFrame.Angles(0, 1.5, g * .3), Color3.fromRGB(86, 120, 56), Enum.Material.Grass, SMALL)
	end
	local stoneCF = CF(G + V3(.2, .2, .14)) * CFrame.Angles(0, -.4, -.25)
	part(model, 'TinyStone', V3(.22, .22, .06), stoneCF, shade(Color3.fromRGB(130, 128, 136), .08), SL)
	cylZ(model, 'TinyStoneTop', .06, .22, stoneCF * CF(0, .11, 0), shade(Color3.fromRGB(130, 128, 136), .08), SL)
	part(model, 'TinyStoneCrack', V3(.02, .12, .07), stoneCF * CF(.03, .02, 0) * CFrame.Angles(0, 0, .5), Color3.fromRGB(50, 46, 54), SP, SMALL)
	local wormC = Color3.fromRGB(214, 130, 140)
	for w = 0, 2 do
		anim(ball(model, 'Worm', .07, CF(G + V3(-.18 + w * .055, .05 + math.sin(w * 1.6) * .03, -.25)), wormC:Lerp(BLACK, w * .08), SP, SMALL), 'Wave', w * .6, G + V3(-.18, .05, -.25))
	end

	-- LIGHT + FX -------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'SandGlow', V3(.4, .4, .4), at(-.84, -.1, 0), blue, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'SandLight', blue, 6.5, 1)
	emitter(lamp, 'SandMotes', SPARK_TEX, blue:Lerp(WHITE, .3), 2.5, .2, .5, 1.6, V3(0, -.6, 0))
	local lamp2 = part(model, 'SandGlowB', V3(.3, .3, .3), at(.84, -.1, 0), violet, SP, { Transparency = 1, CastShadow = false })
	light(lamp2, 'SandLightB', violet, 4.5, .7)

	model:SetAttribute('BackC0', CF(.25, -.3, .3))
	model:SetAttribute('DisplayScale', .8)
	return H + V3(-1.7, 0, 0), p3
end
-- >>HW_UyFateHand

-- <<HW_UyLaughsaw
-- FUNERAL LAUGHSAW (Legendary): the last act of the dead circus. The HEAD is a big circular saw blade facing +Z that
-- never stops turning: a steel rim with sixteen hooked teeth (two of them chipped violet), three rings of black /
-- bone / funeral-red RIBBON STRIPES that twist into a spiral, an iron axle. In front of it, still, sits the GRIN: a
-- round bone-white clown plate with a striped rim, laughing ^ ^ eyes over a violet tear, red cheeks, a red nose and a
-- huge grin of teeth whose lower lip drops when it laughs, crowned with a tilted black top hat (violet band, a pale
-- funeral flower). A yoke behind the blade holds the axle; under it a pierrot ruff of black / bone points with three
-- brass bells, and two striped funeral ribbons streaming down. The POLE is a black / bone circus barber stripe with a
-- violet velvet grip; the POMMEL a striped circus ball with a brass star.
-- Motion: the blade spins (HandFast; faster on a strike), the jaw laughs (GummyJaw), the hat bobs (Bob), the bells
-- swing and the ribbons stream (ScytheTalisman); live: the blade revs through the inspect / a run, the grin cackles.
DESIGNS.HW_UyLaughsaw = function(model, v, def, len, top)
	local rnd = rng(4451)
	local shade = shader(rnd)
	local bone = rgb(v.Head)
	local ink = rgb(v.Trim)
	local violet = rgb(v.Accent)
	local red = rgb(v.Red)
	local steel = rgb(v.Steel)
	local brass = Color3.fromRGB(206, 160, 76)
	local poleC = rgb(v.Shaft)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local RD = 1.25
	local H = V3(0, top.Y + RD + .08, 0)        -- blade / grin centre
	local function at(x, y, z) return CF(H + V3(x, y, z)) end

	-- POLE: barber stripes, a velvet grip, collars --------------------------------------------------------------------------
	local y0, y1 = -half + .1, H.Y - RD - .25
	cylY(model, 'Pole', y1 - y0, .3, CF(0, (y0 + y1) / 2, 0), shade(poleC, .05), SP)
	local st = 0
	local y = -.72
	while y < y1 - .3 do
		part(model, 'PoleStripe', V3(.33, .13, .33), CF(0, y, 0) * CFrame.Angles(0, 0, .38), st % 2 == 0 and shade(bone, .05) or shade(ink, .05), SP)
		y += .17
		st += 1
	end
	for _, by in ipairs({ -half + .3, -2.05, -.78 }) do
		cylY(model, 'PoleCollar', .1, .38, CF(0, by, 0), shade(brass, .06), ME, { Reflectance = .12 })
	end
	for g = 0, 10 do
		local gy = -1.95 + g * .105
		part(model, 'GripVelvet', V3(.4, .095, .4), CF(0, gy, 0) * CFrame.Angles(0, g * .35, (g % 2 == 0 and .08 or -.08)), shade(violet:Lerp(BLACK, .45), .1), FA)
		if g % 3 == 1 then
			part(model, 'GripStitch', V3(.26, .02, .02), CF(0, gy, .205) * CFrame.Angles(0, 0, .5), brass, ME, SMALL)
		end
	end
	-- the pierrot ruff and its bells, two striped funeral ribbons streaming down
	local ruffY = y1 - .02
	cylY(model, 'RuffCollar', .14, .42, CF(0, ruffY, 0), shade(ink, .05), SP)
	for r = 0, 11 do
		local a = r / 12 * math.pi * 2
		local dir = V3(math.cos(a), -.35, math.sin(a))
		spike(model, 'Ruff', V3(math.cos(a) * .16, ruffY + .02, math.sin(a) * .16), dir, V3(0, 1, 0), .34, .2, .06, r % 2 == 0 and shade(bone, .04) or shade(ink, .05), FA)
		if r % 4 == 1 then
			local hang = V3(math.cos(a) * .44, ruffY - .13, math.sin(a) * .44)
			local bellParts = { ball(model, 'RuffBell', .13, CF(hang - V3(0, .08, 0)), brass, ME, { Reflectance = .15 }),
				part(model, 'RuffBellSlot', V3(.08, .02, .02), CF(hang - V3(0, .1, 0)) * CFrame.Angles(0, -a, 0), Color3.fromRGB(40, 30, 20), SP, SMALL) }
			animAll(bellParts, 'ScytheTalisman', r * .4, hang)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		local hang = V3(sx * .17, ruffY - .05, .08)
		for k = 1, 6 do
			local strip = part(model, 'FuneralRibbon', V3(.1, .15, .02), CF(hang + V3(sx * k * .03, -k * .145, .02 * k)) * CFrame.Angles(.06 * k, 0, sx * .12), k % 2 == 0 and shade(bone, .04) or shade(ink, .05), FA, SMALL)
			anim(strip, 'ScytheTalisman', sx * .9, hang)
		end
		wedge(model, 'FuneralRibbonEnd', V3(.02, .12, .1), CF(hang + V3(sx * .21, -.95, .14)) * CFrame.Angles(0, math.pi / 2, math.pi), shade(ink, .05), FA, SMALL)
	end

	-- THE YOKE behind the blade, the axle -------------------------------------------------------------------------------------
	local yokeZ = -.3
	local yk = {}
	for k = 0, 5 do
		local t = k / 5
		table.insert(yk, bez(V3(0, ruffY + .08, 0), V3(0, ruffY + .45, -.05), V3(0, H.Y - .9, yokeZ), H + V3(0, -.12, yokeZ), t))
	end
	tube(model, 'Yoke', yk, .2, .16, function() return shade(ink, .05) end, ME)
	cylZ(model, 'AxleHousing', .2, .42, at(0, 0, yokeZ), shade(brass, .05), ME, { Reflectance = .12 })
	cylZ(model, 'Axle', .5, .16, at(0, 0, -.07), shade(steel:Lerp(BLACK, .3), .05), ME)

	-- THE BLADE (spins round the axle): ribbon-stripe rings, the steel rim, sixteen hooked teeth -------------------------------
	local disc = {}
	local cols = { ink, bone, red }
	for ri, rr in ipairs({ { .46, .22, 12 }, { .7, .26, 16 }, { .95, .26, 20 } }) do
		local n = rr[3]
		for _, p in ipairs(ring(model, 'BladeStripe', CF(H), rr[1], rr[2], .1, n, function(i)
			local c = cols[(i + ri) % 3 + 1]
			return shade(c, .06)
		end, SP)) do
			table.insert(disc, p)
		end
	end
	for _, p in ipairs(ring(model, 'BladeRim', CF(H), 1.13, .14, .12, 28, function() return shade(steel, .08) end, ME, nil, { Reflectance = .15 })) do
		table.insert(disc, p)
	end
	for _, p in ipairs(ring(model, 'BladeRivetRing', CF(H + V3(0, 0, .065)), 1.06, .03, .02, 28, steel:Lerp(BLACK, .3), ME, nil, SMALL)) do
		table.insert(disc, p)
	end
	for tth = 0, 15 do
		local a = tth / 16 * math.pi * 2
		local radial = V3(math.cos(a), math.sin(a), 0)
		local tangent = V3(-math.sin(a), math.cos(a), 0)
		local base = H + radial * 1.17
		local chipped = tth == 3 or tth == 10
		table.insert(disc, spike(model, 'BladeTooth', base, (radial * .55 - tangent * .85).Unit, V3(0, 0, 1), .32, .22, .1, chipped and violet or shade(steel, .06), ME, { Reflectance = .1 }))
	end
	animAll(disc, 'HandFast', 0, H)

	-- THE GRIN (still, in front of the blade) ----------------------------------------------------------------------------------
	local FZ = .17
	cylZ(model, 'GrinPlate', .16, 1.04, at(0, 0, FZ), shade(bone, .03), SP)
	ring(model, 'GrinRim', CF(H + V3(0, 0, FZ + .02)), .5, .1, .16, 20, function(i) return i % 2 == 0 and shade(ink, .04) or shade(bone:Lerp(BLACK, .08), .04) end, SP)
	local face = FZ + .09
	for _, sx in ipairs({ -1, 1 }) do
		-- laughing ^ eyes, the violet tear under the right one, red cheeks
		bar(model, 'LaughEye', H + V3(sx * .2 - .07, .1, face), H + V3(sx * .2, .19, face), .05, .03, ink, SP, SMALL)
		bar(model, 'LaughEye', H + V3(sx * .2, .19, face), H + V3(sx * .2 + .07, .1, face), .05, .03, ink, SP, SMALL)
		blob(model, 'Cheek', V3(.14, .09, .03), at(sx * .3, -.03, face - .005), red:Lerp(WHITE, .2), SP, SMALL)
	end
	local tear = blob(model, 'Tear', V3(.06, .11, .03), at(.2, .0, face + .005), violet, NE, GLOW)
	tear:SetAttribute('PickPulse', true)
	ball(model, 'ClownNose', .14, at(0, .05, face + .04), red, SP)
	ball(model, 'NoseGlint', .04, at(.03, .08, face + .1), WHITE, NE, SMALL)
	-- the grin: a dark crescent, a row of teeth above, the lower lip + teeth drop when it laughs
	local mouth = {}
	for m = -4, 4 do
		local mx = m * .075
		local my = -.14 - (16 - m * m) * .008
		table.insert(mouth, part(model, 'Grin', V3(.08, .12, .02), at(mx, my, face), Color3.fromRGB(30, 10, 24), SP, SMALL))
		if math.abs(m) <= 3 then
			part(model, 'GrinTooth', V3(.06, .05, .03), at(mx, my + .04, face + .01), WHITE, SP, SMALL)
		end
	end
	local jawPivot = H + V3(0, -.2, FZ - .05)
	local jaw = {}
	for m = -3, 3 do
		local mx = m * .075
		local my = -.14 - (16 - m * m) * .008
		table.insert(jaw, part(model, 'GrinLowerTooth', V3(.06, .045, .03), at(mx, my - .045, face + .012), WHITE, SP, SMALL))
	end
	table.insert(jaw, part(model, 'GrinLip', V3(.5, .04, .03), at(0, -.3, face + .005), red, SP, SMALL))
	animAll(jaw, 'GummyJaw', 0, jawPivot)
	-- the top hat (tilted), its violet band and a pale funeral flower; it bobs
	local hatCF = at(-.08, .52, .3) * CFrame.Angles(0, 0, .22)
	local hat = {}
	table.insert(hat, cylY(model, 'HatBrim', .05, .46, hatCF, shade(ink, .04), FA))
	table.insert(hat, cylY(model, 'HatCrown', .4, .3, hatCF * CF(0, .22, 0), shade(ink, .04), FA))
	table.insert(hat, cylY(model, 'HatTop', .03, .32, hatCF * CF(0, .43, 0), shade(ink:Lerp(WHITE, .08), .04), FA))
	table.insert(hat, cylY(model, 'HatBand', .07, .31, hatCF * CF(0, .07, 0), violet, FA))
	table.insert(hat, ball(model, 'HatFlower', .11, hatCF * CF(.1, .1, .13), bone:Lerp(WHITE, .3), SP, SMALL))
	table.insert(hat, ball(model, 'HatFlowerHeart', .05, hatCF * CF(.1, .1, .18), brass, SP, SMALL))
	table.insert(hat, part(model, 'HatLeaf', V3(.1, .03, .05), hatCF * CF(.17, .06, .14) * CFrame.Angles(0, 0, -.5), Color3.fromRGB(70, 110, 60), SP, SMALL))
	animAll(hat, 'Bob', .3)

	-- POMMEL: a striped circus ball with a brass star -------------------------------------------------------------------------
	local B = V3(0, -half - .1, 0)
	ball(model, 'CircusBall', .46, CF(B), red, SP)
	cylY(model, 'CircusBallBand', .1, .47, CF(B), bone, SP)
	cylZ(model, 'CircusBallRing', .06, .48, CF(B), ink, SP)
	for p = 0, 4 do
		local a = p / 5 * math.pi * 2 + math.pi / 2
		spike(model, 'StarPoint', B + V3(math.cos(a) * .03, math.sin(a) * .03, .24), V3(math.cos(a), math.sin(a), 0), V3(0, 0, 1), .1, .07, .02, brass, ME, SMALL)
	end

	-- LIGHT + FX ---------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'GrinGlow', V3(.4, .4, .1), at(0, 0, FZ + .2), violet, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'GrinLight', violet, 6, .8)
	local sparkAt = part(model, 'SawSparkFX', V3(.3, .3, .3), at(0, -RD, 0), Color3.fromRGB(255, 170, 80), SP, { Transparency = 1, CastShadow = false })
	emitter(sparkAt, 'SawSparks', SPARK_TEX, Color3.fromRGB(255, 190, 110), 2, .16, 1.2, .8, V3(0, -2, 0))

	model:SetAttribute('BackC0', CF(.2, -.3, .35))
	model:SetAttribute('DisplayScale', .8)
	return H + V3(-RD - .08, 0, 0), H + V3(RD + .08, 0, 0)
end
-- >>HW_UyLaughsaw

-- <<HW_UyTVHead
-- STATIC TV-HEAD (Mythic): a crooked old television from a Crooked Row parlour, set on a pole and leaning (the whole
-- set sits tilted). A walnut plank cabinet with a crooked gothic crest (a pointed arch with a round violet window,
-- crooked spires on the corners), stubby turned feet and a tapering CRT back with vent slats. The SCREEN is a grid of
-- static pixels (a third of them flicker: PickFlicker) in a brass bezel under curved glass, and the static has EYES:
-- two glowing white eyes with darting pupils and a violet signal-wave grin. The right panel carries two brass knobs (they
-- click to a new channel now and then) over a speaker grille and an amber power lamp; rabbit-ear antennas with little
-- bells sway on top next to a melting candle and a cobweb. A crooked iron bracket holds it on a dark wood pole wrapped
-- by its own power cord (the plug swings); black tape grip; the pommel is a glowing vacuum tube.
-- Motion: the antennas sway / rattle (AntennaLow / AntennaHigh), the knobs click round (Knob), the pupils dart
-- (ScytheEye), the static flickers (PickFlicker), the candle flame shakes, the plug swings (ScytheTalisman); live: the
-- signal grin pulses, channel zaps through the inspect.
DESIGNS.HW_UyTVHead = function(model, v, def, len, top)
	local rnd = rng(5209)
	local shade = shader(rnd)
	local wood = rgb(v.Head)
	local poleC = rgb(v.Shaft)
	local glow = rgb(v.Accent)
	local screenC = rgb(v.Screen)
	local brass = rgb(v.Trim)
	local ink = rgb(v.Ink)
	local flameC = rgb(v.Candle)
	local iron = Color3.fromRGB(46, 42, 50)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local W, HT, D = 2.0, 1.55, 1.1
	local C = V3(0, top.Y + 1.0, 0)
	local TV = CF(C) * CFrame.Angles(0, .12, -.13)
	local function tv(x, y, z) return TV * CF(x, y, z) end
	local function tvp(x, y, z) return (TV * CF(x, y, z)).Position end
	local FZ = D / 2

	-- CABINET: walnut planks, the crest, spires, feet ---------------------------------------------------------------------------
	part(model, 'Cabinet', V3(W - .1, HT - .1, D - .08), tv(0, 0, -.02), shade(wood:Lerp(BLACK, .3), .05), WO)
	for _, sy in ipairs({ -1, 1 }) do
		part(model, 'CabinetPlank', V3(W + .1, .11, D + .06), tv(0, sy * (HT / 2 - .02), 0), shade(wood, .1), WO)
		part(model, 'CabinetPlankEdge', V3(W + .14, .04, D + .1), tv(0, sy * (HT / 2 + .05), 0), shade(wood:Lerp(BLACK, .2), .05), WO)
	end
	for _, sx in ipairs({ -1, 1 }) do
		for p = 0, 3 do
			part(model, 'CabinetSide', V3(.11, (HT - .1) / 4 - .01, D + .04), tv(sx * (W / 2 - .01), -HT / 2 + .05 + (p + .5) * (HT - .1) / 4, 0), shade(wood, .14), WO)
		end
		for gl = 0, 2 do
			part(model, 'Grain', V3(.02, .025, .3 + rnd() * .4), tv(sx * (W / 2 + .045), -.45 + gl * .42 + rnd() * .1, (rnd() - .5) * .3), wood:Lerp(BLACK, .35), WO, SMALL)
		end
	end
	-- front frame boards round the screen and the panel
	part(model, 'FrontBoard', V3(W - .1, .12, .06), tv(0, HT / 2 - .13, FZ), shade(wood, .08), WO)
	part(model, 'FrontBoard', V3(W - .1, .14, .06), tv(0, -HT / 2 + .14, FZ), shade(wood, .08), WO)
	part(model, 'FrontBoard', V3(.1, HT - .3, .06), tv(-W / 2 + .1, 0, FZ), shade(wood, .08), WO)
	part(model, 'PanelBoard', V3(.5, HT - .3, .06), tv(.68, 0, FZ - .01), shade(wood:Lerp(BLACK, .1), .06), WO)
	-- crooked gothic crest: a pointed arch with a round window, crooked spires on the corners
	local crest = tv(-.15, HT / 2 + .1, FZ - .12)
	part(model, 'CrestBase', V3(1.0, .1, .12), crest, shade(wood, .06), WO)
	wedge(model, 'CrestArch', V3(.12, .42, .5), crest * CF(-.25, .26, 0) * CFrame.Angles(0, -math.pi / 2, 0), shade(wood, .06), WO)
	wedge(model, 'CrestArch', V3(.12, .42, .5), crest * CF(.25, .26, 0) * CFrame.Angles(0, math.pi / 2, 0), shade(wood, .06), WO)
	local win = cylZ(model, 'CrestWindow', .14, .2, crest * CF(0, .2, .01), glow, NE, GLOW)
	win:SetAttribute('PickPulse', true)
	cylZ(model, 'CrestWindowRim', .12, .26, crest * CF(0, .2, 0), shade(brass, .05), ME)
	for _, sx in ipairs({ -1, 1 }) do
		local base = tvp(sx * (W / 2 - .05), HT / 2 + .07, FZ - .1)
		part(model, 'SpireBase', V3(.16, .14, .16), CF(base) * TV.Rotation, shade(wood:Lerp(BLACK, .15), .05), WO)
		spike(model, 'Spire', base + V3(0, .06, 0), (TV.Rotation * CF(sx * .25, 1, 0)).Position, V3(0, 0, 1), .38, .12, .12, shade(wood:Lerp(BLACK, .2), .05), WO)
		cylY(model, 'Foot', .18, .16, tv(sx * (W / 2 - .2), -HT / 2 - .13, FZ - .2), shade(wood:Lerp(BLACK, .1), .06), WO)
		ball(model, 'FootBall', .15, tv(sx * (W / 2 - .2), -HT / 2 - .23, FZ - .2), shade(brass, .05), ME)
	end
	-- the CRT back: stepped, vented, a neck
	part(model, 'CRTBack', V3(1.5, 1.1, .32), tv(-.05, 0, -D / 2 - .14), shade(wood:Lerp(BLACK, .25), .06), WO)
	part(model, 'CRTBack', V3(1.0, .74, .3), tv(-.05, 0, -D / 2 - .44), shade(wood:Lerp(BLACK, .3), .06), WO)
	part(model, 'CRTNeck', V3(.46, .4, .22), tv(-.05, 0, -D / 2 - .7), shade(iron, .06), ME)
	for sl = 0, 4 do
		part(model, 'Vent', V3(.9, .04, .03), tv(-.05, -.32 + sl * .16, -D / 2 - .31), BLACK, SP, SMALL)
	end

	-- SCREEN: bezel, the static grid, the eyes, the signal grin, curved glass ------------------------------------------------------
	local SX, SY = -.18, .02                     -- screen centre
	local SW, SH = 1.12, .98
	for _, sy in ipairs({ -1, 1 }) do
		part(model, 'Bezel', V3(SW + .14, .08, .1), tv(SX, SY + sy * (SH / 2 + .04), FZ + .02), shade(brass, .06), ME, { Reflectance = .1 })
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(model, 'Bezel', V3(.08, SH + .16, .1), tv(SX + sx * (SW / 2 + .04), SY, FZ + .02), shade(brass, .06), ME, { Reflectance = .1 })
	end
	for bi = 0, 3 do
		for bj = 0, 2 do
			part(model, 'ScreenBack', V3(SW / 4 + .005, SH / 3 + .005, .04), tv(SX - SW / 2 + (bi + .5) * SW / 4, SY - SH / 2 + (bj + .5) * SH / 3, FZ), ink, SP)
		end
	end
	local CELL = .093
	local cols, rows = 12, 10
	local statics = { Color3.fromRGB(70, 70, 86), Color3.fromRGB(120, 120, 136), Color3.fromRGB(170, 170, 186), Color3.fromRGB(210, 212, 226), screenC:Lerp(BLACK, .3), glow:Lerp(BLACK, .4) }
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local x = SX - SW / 2 + (i + .5) * (SW / cols)
			local y = SY - SH / 2 + (j + .5) * (SH / rows)
			local px = part(model, 'Static', V3(CELL, CELL, .02), tv(x, y, FZ + .03), statics[1 + math.floor(rnd() * #statics)], NE, { CastShadow = false, Transparency = .25 })
			if rnd() < .33 then
				px:SetAttribute('PickFlicker', true)
			end
		end
	end
	-- static eyes: glowing white ovals ringed with pale pixels, dark pupils that dart about
	for _, sx in ipairs({ -1, 1 }) do
		local ex, ey = SX + sx * .25, SY + .16
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			part(model, 'EyeRing', V3(.07, .07, .02), tv(ex + math.cos(a) * .15, ey + math.sin(a) * .12, FZ + .045), screenC:Lerp(WHITE, .5), NE, GLOW)
		end
		local white = blob(model, 'StaticEye', V3(.24, .19, .02), tv(ex, ey, FZ + .05), WHITE, NE, GLOW)
		white:SetAttribute('PickPulse', true)
		local pupil = blob(model, 'StaticPupil', V3(.1, .12, .02), tv(ex, ey, FZ + .065), ink, SP, SMALL)
		anim(pupil, 'ScytheEye', sx * .4, tvp(ex, ey, FZ + .065))
	end
	-- the signal grin: a violet zigzag wave
	local wave = { { -.36, -.2 }, { -.24, -.3 }, { -.12, -.18 }, { 0, -.32 }, { .12, -.19 }, { .24, -.3 }, { .36, -.2 } }
	for k = 1, #wave - 1 do
		local a, b = wave[k], wave[k + 1]
		local seg = bar(model, 'SignalGrin', tvp(SX + a[1], SY + a[2], FZ + .05), tvp(SX + b[1], SY + b[2], FZ + .05), .05, .02, glow, NE, GLOW)
		seg:SetAttribute('PickPulse', true)
	end
	part(model, 'ScreenGlass', V3(SW + .02, SH + .02, .04), tv(SX, SY, FZ + .11), screenC:Lerp(WHITE, .4), GL, { Transparency = .78, CastShadow = false })
	-- scan line + a crack on the glass
	part(model, 'ScanLine', V3(SW, .02, .01), tv(SX, SY + .3, FZ + .135), screenC:Lerp(WHITE, .6), NE, { Transparency = .5, CastShadow = false })
	local crackAt = tvp(SX - .42, SY - .34, FZ + .14)
	for _, d in ipairs({ V3(.22, .08, 0), V3(.12, .24, 0), V3(.26, -.04, 0) }) do
		bar(model, 'GlassCrack', crackAt, crackAt + (TV.Rotation * CF(d)).Position, .016, .01, Color3.fromRGB(200, 210, 230), SP, { Transparency = .3, CastShadow = false })
	end
	-- the right panel: two knobs, the speaker grille, the amber power lamp
	for k, ky in ipairs({ .38, .08 }) do
		local kc = tv(.68, ky, FZ + .06)
		local knob = {}
		table.insert(knob, cylZ(model, 'Knob', .1, .25, kc, shade(brass, .05), ME, { Reflectance = .12 }))
		table.insert(knob, cylZ(model, 'KnobCap', .04, .17, kc * CF(0, 0, .06), shade(brass:Lerp(WHITE, .2), .05), ME))
		table.insert(knob, part(model, 'KnobPointer', V3(.03, .1, .02), kc * CF(0, .05, .085), ink, SP, SMALL))
		animAll(knob, 'Knob', k * 1.7, kc.Position)
		for t = 0, 5 do
			local a = t / 6 * math.pi * 2
			part(model, 'KnobTick', V3(.02, .02, .01), kc * CF(math.cos(a) * .17, math.sin(a) * .17, -.03), brass:Lerp(WHITE, .3), SP, SMALL)
		end
	end
	for sl = 0, 4 do
		part(model, 'Grille', V3(.36, .035, .03), tv(.68, -.18 - sl * .075, FZ + .03), shade(ink:Lerp(brass, .2), .05), ME, SMALL)
	end
	local lampP = ball(model, 'PowerLamp', .08, tv(.68, -.58, FZ + .04), flameC, NE, GLOW)
	lampP:SetAttribute('PickPulse', true)

	-- TOP: rabbit-ear antennas with bells, a melting candle, a cobweb -------------------------------------------------------------
	local abase = tvp(.15, HT / 2 + .08, -.2)
	cylY(model, 'AntennaBase', .1, .34, CF(abase) * TV.Rotation, shade(iron, .05), ME)
	ball(model, 'AntennaDome', .22, CF(abase + V3(0, .06, 0)), shade(iron, .05), ME)
	for k, sx in ipairs({ -1, 1 }) do
		local elbow = abase + (TV.Rotation * CF(sx * .45, .8, -.05)).Position
		local tip = elbow + (TV.Rotation * CF(sx * .45, .55, .08)).Position
		local low = { rod(model, 'Antenna', abase + V3(0, .1, 0), elbow, .05, shade(iron:Lerp(WHITE, .3), .05), ME, { Reflectance = .2 }), ball(model, 'AntennaJoint', .08, CF(elbow), iron, ME) }
		animAll(low, 'AntennaLow', k * 1.3, abase)
		local high = { rod(model, 'Antenna', elbow, tip, .04, shade(iron:Lerp(WHITE, .35), .05), ME, { Reflectance = .2 }), ball(model, 'AntennaBell', .13, CF(tip), shade(brass, .05), ME, { Reflectance = .15 }) }
		animAll(high, 'AntennaHigh', k * 1.3, abase)
	end
	local cBase = tvp(-.72, HT / 2 + .09, .1)
	cylY(model, 'Candle', .32, .14, CF(cBase + V3(0, .16, 0)), shade(Color3.fromRGB(226, 216, 196), .04), SP)
	for k = 1, 3 do
		part(model, 'WaxDrip', V3(.05, .14 + k * .06, .04), tv(-.72 + (k - 2) * .07, HT / 2 - .02 - k * .05, FZ + .03), Color3.fromRGB(236, 228, 210), SP, SMALL)
	end
	part(model, 'Wick', V3(.02, .05, .02), CF(cBase + V3(0, .345, 0)), BLACK, SP, SMALL)
	local flame = blob(model, 'CandleFlame', V3(.08, .16, .08), CF(cBase + V3(0, .43, 0)), flameC, NE, GLOW)
	flame:SetAttribute('PickPulse', true)
	anim(flame, 'Shake', .3, cBase + V3(0, .35, 0))
	light(flame, 'CandleLight', flameC, 4, .55)
	local wc = tvp(W / 2 - .05, HT / 2 + .03, FZ - .02)
	for _, d in ipairs({ V3(-.44, .02, 0), V3(-.3, .3, 0), V3(-.02, .42, 0) }) do
		bar(model, 'Cobweb', wc, wc + d, .016, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .3, CastShadow = false })
	end
	bar(model, 'Cobweb', wc + V3(-.22, .01, 0), wc + V3(-.15, .15, 0), .014, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .4, CastShadow = false })
	bar(model, 'Cobweb', wc + V3(-.15, .15, 0), wc + V3(-.01, .21, 0), .014, .01, Color3.fromRGB(236, 236, 240), SP, { Transparency = .4, CastShadow = false })

	-- MOUNT + POLE: the crooked bracket, the dark wood pole, its power cord and the plug, the tape grip ----------------------------
	local bottom = tvp(0, -HT / 2 - .08, -.1)
	local y0, y1 = -half + .1, bottom.Y - .45
	cylY(model, 'Pole', y1 - y0, .32, CF(0, (y0 + y1) / 2, 0), shade(poleC, .06), WO)
	for _, by in ipairs({ -half + .3, -2.05, -.75, .6, y1 - .05 }) do
		cylY(model, 'PoleBand', .1, .38, CF(0, by, 0), shade(iron, .06), ME, { Reflectance = .06 })
	end
	part(model, 'MountPlate', V3(.7, .08, .5), CF(bottom) * TV.Rotation, shade(iron, .05), ME)
	bar(model, 'MountArm', V3(0, y1 - .05, 0), bottom + V3(-.12, -.02, 0), .16, .16, shade(iron, .05), ME)
	bar(model, 'MountBrace', V3(0, y1 - .2, 0), bottom + V3(.28, -.02, .1), .08, .08, shade(iron, .05), ME)
	bar(model, 'MountBrace', V3(0, y1 - .2, 0), bottom + V3(-.3, -.02, -.12), .08, .08, shade(iron, .05), ME)
	for g = 0, 10 do
		local gy = -1.95 + g * .105
		part(model, 'GripTape', V3(.4, .095, .4), CF(0, gy, 0) * CFrame.Angles(0, g * .35, (g % 2 == 0 and .08 or -.08)), g % 4 == 0 and shade(glow:Lerp(BLACK, .55), .06) or shade(ink, .08), Enum.Material.Fabric)
	end
	-- the power cord: out of the CRT neck, down and round the pole
	local neck = tvp(-.05, -.1, -D / 2 - .82)
	local cord = { neck, neck + V3(.04, -.3, -.06), tvp(-.1, -HT / 2 - .04, -D / 2 + .1), V3(.2, y1 + .05, -.1) }
	for k = 0, 9 do
		local a = k * .95 + 1
		table.insert(cord, V3(math.cos(a) * .22, y1 - .15 - k * .19, math.sin(a) * .22))
	end
	tube(model, 'PowerCord', cord, .07, .07, function() return shade(Color3.fromRGB(30, 26, 34), .05) end, SP)
	local plugHang = cord[#cord]
	local plug = {}
	for k = 1, 3 do
		table.insert(plug, part(model, 'CordEnd', V3(.06, .1, .06), CF(plugHang - V3(0, k * .09, 0)), Color3.fromRGB(30, 26, 34), SP, SMALL))
	end
	table.insert(plug, part(model, 'Plug', V3(.16, .18, .1), CF(plugHang - V3(0, .38, 0)), Color3.fromRGB(60, 50, 44), SP))
	for _, px in ipairs({ -.04, .04 }) do
		table.insert(plug, part(model, 'PlugPin', V3(.025, .1, .025), CF(plugHang - V3(-px, .52, 0)), brass, ME, SMALL))
	end
	animAll(plug, 'ScytheTalisman', .6, plugHang)

	-- POMMEL: a glowing vacuum tube -------------------------------------------------------------------------------------------
	local T0 = V3(0, -half - .1, 0)
	cylY(model, 'TubeBase', .14, .34, CF(T0), shade(Color3.fromRGB(40, 30, 26), .05), SP)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		part(model, 'TubePin', V3(.03, .06, .03), CF(T0 + V3(math.cos(a) * .1, .1, math.sin(a) * .1)), brass, ME, SMALL)
	end
	cylY(model, 'TubeGlass', .38, .3, CF(T0 - V3(0, .26, 0)), screenC:Lerp(WHITE, .5), GL, { Transparency = .55, CastShadow = false })
	ball(model, 'TubeTip', .3, CF(T0 - V3(0, .45, 0)), screenC:Lerp(WHITE, .5), GL, { Transparency = .55, CastShadow = false })
	part(model, 'TubePlate', V3(.16, .26, .03), CF(T0 - V3(0, .26, 0)), iron, ME, SMALL)
	local fil = part(model, 'TubeFilament', V3(.03, .2, .03), CF(T0 - V3(0, .27, .03)), flameC, NE, GLOW)
	fil:SetAttribute('PickPulse', true)

	-- LIGHT + FX ---------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'ScreenGlow', V3(.5, .5, .1), tv(SX, SY, FZ - .1), screenC, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'ScreenLight', screenC, 7, 1)
	emitter(lamp, 'StaticMotes', SPARK_TEX, screenC:Lerp(WHITE, .5), 2, .16, .6, 1, V3(0, .8, 0))

	model:SetAttribute('BackC0', CF(.3, -.1, .55))
	model:SetAttribute('DisplayScale', .8)
	return tvp(-W / 2 - .05, 0, 0), tvp(W / 2 + .05, 0, 0)
end
-- >>HW_UyTVHead

-- <<HW_UyOctopus
-- MARSH OCTOPUS (Mythic): a sickly-green octopus out of the Mourning Marsh, coiled round a gravedigger's spade. The
-- SPADE (point up) is mossy, rust-flecked marsh iron with a rolled rim, moss creeping up from the shoulders and a
-- riveted socket; a lily pad with a glowing marsh flower sits on one shoulder. The OCTOPUS clings to the blade's front:
-- a bulbous voxel mantle (mottled green, glowing violet spots, duckweed on top, a siphon on its side) with two big
-- bulging gold eyes (horizontal slit pupils that look round, lids that blink). Eight arms with pale suckers: two climb
-- the blade's edges and curl over its point, two spread out sideways and curl (the striking ends), four spiral down
-- the shaft; bog water drips off the curls. The POLE is old wood with tarred rope wraps and iron ferrules; the POMMEL
-- is the spade's D-handle.
-- Motion: the free arms sway (Tentacle), the curled tips curl (Curl), the pupils look round (EyeLook), the lids blink
-- (BlinkLow / BlinkHigh), the drips stretch and fall (GummyDrop + PickGoo), the spots and the flower pulse; live: the
-- arms writhe through the inspect, bubbles on a mood.
DESIGNS.HW_UyOctopus = function(model, v, def, len, top)
	local rnd = rng(6113)
	local shade = shader(rnd)
	local iron = rgb(v.Head)
	local wood = rgb(v.Shaft)
	local glow = rgb(v.Accent)
	local body = rgb(v.Body)
	local spots = rgb(v.Spots)
	local sucker = rgb(v.Sucker)
	local moss = rgb(v.Moss)
	local dark = rgb(v.Trim)
	local rust = Color3.fromRGB(140, 84, 50)
	local bog = Color3.fromRGB(90, 140, 96)
	model.PrimaryPart.Transparency = 1
	local half = len * .5

	-- POLE: old wood, tarred rope wraps, iron ferrules, the D-handle -------------------------------------------------------------
	local bY = top.Y + .35                      -- the blade's shoulder line
	local y0, y1 = -half + .25, bY - .3
	local y = y0
	while y < y1 - .01 do
		local h = math.min(.5 + rnd() * .3, y1 - y)
		cylY(model, 'Shaft', h + .01, .32 + rnd() * .02, CF(0, y + h / 2, 0) * CFrame.Angles(0, rnd() * 6, 0), shade(wood, .12), WO)
		y += h
	end
	for _, fy in ipairs({ -half + .4, -2.05, -.75, .9 }) do
		cylY(model, 'Ferrule', .12, .4, CF(0, fy, 0), shade(dark, .06), CM)
	end
	for g = 0, 10 do
		local gy = -1.95 + g * .105
		part(model, 'TarRope', V3(.42, .095, .42), CF(0, gy, 0) * CFrame.Angles(0, g * .4, (g % 2 == 0 and .12 or -.12)), shade(Color3.fromRGB(58, 48, 36), .12), FA)
	end
	for g = 0, 3 do
		part(model, 'Rope', V3(.4, .07, .4), CF(0, .2 + g * .08, 0) * CFrame.Angles(0, g * .6, .25), shade(Color3.fromRGB(150, 126, 86), .08), FA)
	end
	local dY = -half + .22
	for _, sx in ipairs({ -1, 1 }) do
		bar(model, 'DHandle', V3(0, dY + .05, 0), V3(sx * .28, dY - .3, 0), .14, .14, shade(wood, .08), WO)
	end
	cylX(model, 'DGrip', .7, .16, CF(0, dY - .36, 0), shade(wood:Lerp(BLACK, .15), .06), WO)
	part(model, 'DCollar', V3(.24, .1, .24), CF(0, dY + .07, 0), shade(dark, .05), CM)

	-- THE SPADE: socket, straps, the blade built row by row (moss low, rust, a rolled rim) -------------------------------------------
	cylY(model, 'Socket', .42, .38, CF(0, bY - .16, 0), shade(iron:Lerp(BLACK, .35), .06), CM)
	for _, sz in ipairs({ -1, 1 }) do
		part(model, 'Strap', V3(.14, .6, .05), CF(0, bY - .55, sz * .19), shade(dark, .06), CM)
		rivet(model, V3(0, bY - .4, sz * .22), V3(0, 0, sz), iron:Lerp(WHITE, .2))
		rivet(model, V3(0, bY - .7, sz * .22), V3(0, 0, sz), iron:Lerp(WHITE, .2))
	end
	local CELL = .22
	local HALF = { 3.2, 3.45, 3.5, 3.45, 3.3, 3.0, 2.65, 2.2, 1.65, 1.0 }
	local D = .14
	for j = 1, #HALF do
		local hw = HALF[j]
		local cy = bY + (j - .5) * CELL
		for i = -4, 4 do
			local frac = hw - (math.abs(i) - .5)
			if frac > .3 then
				local w = CELL * math.clamp(frac, .3, 1)
				local x = i * CELL - (i > 0 and 1 or (i < 0 and -1 or 0)) * (CELL - w) / 2
				local outer = frac < 1.5 or j == #HALF
				local col, mat = shade(iron, .16), ME
				if outer then
					col, mat = shade(iron:Lerp(BLACK, .3), .1), CM
				elseif rnd() < (j <= 3 and .55 or .12) then
					col, mat = shade(moss, .2), Enum.Material.Grass
				elseif rnd() < .18 then
					col, mat = shade(rust, .15), CM
				end
				part(model, outer and 'BladeRim' or 'BladeIron', V3(w - .012, CELL - .012, D + (outer and .05 or 0)), CF(x, cy, (rnd() - .5) * .012), col, mat)
			end
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(model, 'FootTread', V3(.7, .15, .15), CF(sx * .5, bY - .02, 0), shade(iron:Lerp(BLACK, .2), .06), ME, { Shape = Enum.PartType.Cylinder })
	end
	-- the lily pad and its glowing marsh flower on the right shoulder
	local LP = V3(.62, bY + .12, .02)
	cylY(model, 'LilyPad', .04, .5, CF(LP + V3(.08, .08, 0)) * CFrame.Angles(0, 0, -.25), shade(Color3.fromRGB(70, 130, 64), .08), Enum.Material.Grass)
	local flowerAt = LP + V3(.1, .2, .02)
	for p = 0, 4 do
		local a = p / 5 * math.pi * 2
		local petal = blob(model, 'MarshPetal', V3(.1, .05, .18), CF(flowerAt + V3(math.cos(a) * .07, .02, math.sin(a) * .07)) * CFrame.Angles(0, -a + math.pi / 2, .5), spots:Lerp(WHITE, .25), SP, SMALL)
		petal:SetAttribute('PickPulse', true)
	end
	local fc = ball(model, 'MarshFlower', .08, CF(flowerAt + V3(0, .05, 0)), glow, NE, GLOW)
	fc:SetAttribute('PickPulse', true)

	-- THE OCTOPUS: the voxel mantle on the blade's front, spots, duckweed, the siphon, the eyes --------------------------------------
	local M = V3(0, bY + .78, .36)
	local RX, RY, RZ = .56, .64, .42
	local mantle = shell(model, 'Mantle', M, RX, RY, RZ, .15, function(p) return p.Z > -.28 end, function(p)
		local k = rnd()
		local c = k < .2 and body:Lerp(BLACK, .25) or (k > .85 and body:Lerp(WHITE, .18) or body)
		return shade(p.Y > .2 and c:Lerp(bog, .25) or c, .08)
	end, SP)
	-- the sac: a second, smaller bulb on top leaning back (the octopus head shape)
	local SAC = M + V3(0, .5, -.06)
	for _, p in ipairs(shell(model, 'Mantle', SAC, .42, .42, .34, .15, function(p) return p.Y > -.05 and p.Z > -.3 end, function(p)
		local k = rnd()
		return shade(k < .2 and body:Lerp(BLACK, .25) or body:Lerp(bog, .3), .08)
	end, SP)) do
		table.insert(mantle, p)
	end
	for _, p in ipairs(mantle) do
		anim(p, 'Breathe', 0)
	end
	table.insert(mantle, blob(model, 'MantleCore', V3(RX, RY, RZ) * 1.82, CF(M), body:Lerp(BLACK, .3), SP))
	table.insert(mantle, blob(model, 'MantleCore', V3(.42, .42, .34) * 1.8, CF(SAC), body:Lerp(BLACK, .3), SP))
	animAll(mantle, 'Breathe', 0)
	for s = 1, 9 do
		local a = rnd() * math.pi * 1.6 - math.pi * .3
		local e = (rnd() - .3) * 1.1
		local dir = V3(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e) * .2 + .8).Unit
		local pos = M + V3(dir.X * RX, dir.Y * RY, dir.Z * RZ) * 1.03
		if pos.Y < M.Y - .2 and math.abs(pos.X) < .4 then
			pos += V3(0, .4, 0) -- keep the spots off the eyes
		end
		local spot = blob(model, 'MantleSpot', V3(.1 + rnd() * .06, .1 + rnd() * .06, .05), CF(pos) * alignY(dir) * CFrame.Angles(math.pi / 2, 0, 0), spots, NE, GLOW)
		spot:SetAttribute('PickPulse', true)
		anim(spot, 'Breathe', 0)
	end
	for d = 1, 7 do
		local a = rnd() * math.pi * 2
		local r = rnd() * .3
		local pos = SAC + V3(math.cos(a) * r, .42 * math.sqrt(math.max(0, 1 - (r / .42) ^ 2)) * .98, math.sin(a) * r * .7)
		anim(part(model, 'Duckweed', V3(.07, .02, .07), CF(pos) * CFrame.Angles(0, a, 0), Color3.fromRGB(120, 190, 70), SP, SMALL), 'Breathe', 0)
	end
	local siphon = { rod(model, 'Siphon', M + V3(-RX + .05, -.2, .1), M + V3(-RX - .14, -.3, .18), .14, body:Lerp(BLACK, .15), SP),
		cylX(model, 'SiphonMouth', .04, .12, CF(M + V3(-RX - .15, -.3, .18)), Color3.fromRGB(30, 50, 34), SP, SMALL) }
	animAll(siphon, 'Breathe', 0)
	for _, sx in ipairs({ -1, 1 }) do
		local ec = M + V3(sx * .25, -.18, .3)
		ball(model, 'EyeBulge', .34, CF(ec - V3(0, 0, .03)), body:Lerp(WHITE, .1), SP)
		local eye = ball(model, 'OctoEye', .28, CF(ec + V3(0, 0, .02)), Color3.fromRGB(230, 200, 70), SP)
		local iris = cylZ(model, 'OctoIris', .02, .2, CF(ec + V3(0, 0, .155)), Color3.fromRGB(150, 210, 70), NE, GLOW)
		iris:SetAttribute('PickPulse', true)
		anim(part(model, 'OctoPupil', V3(.15, .05, .02), CF(ec + V3(0, 0, .17)), Color3.fromRGB(14, 20, 12), SP, SMALL), 'EyeLook', sx * .6, ec)
		anim(ball(model, 'OctoGlint', .04, CF(ec + V3(.04, .05, .17)), WHITE, NE, SMALL), 'EyeLook', sx * .6, ec)
		anim(part(model, 'LidTop', V3(.32, .14, .06), CF(ec + V3(0, .2, .1)), body:Lerp(BLACK, .1), SP), 'BlinkHigh', sx * .3)
		anim(part(model, 'LidBottom', V3(.3, .1, .06), CF(ec + V3(0, -.18, .1)), body:Lerp(BLACK, .1), SP), 'BlinkLow', sx * .3)
		part(model, 'Brow', V3(.3, .06, .08), CF(ec + V3(sx * -.02, .2, .1)) * CFrame.Angles(0, 0, sx * .25), body:Lerp(BLACK, .35), SP, SMALL)
		_ = eye
	end

	-- THE ARMS ------------------------------------------------------------------------------------------------------------------
	-- arm(pts, d0, d1, tipFrom, motion, phase, jointName): rods + ball joints, suckers on the side facing `inner`, the
	-- segments from tipFrom on animated (whole arm when tipFrom = 1)
	local function arm(pts, d0, d1, tipFrom, motion, phase, inner)
		local segs = {}
		for k = 1, #pts - 1 do
			local f = (k - 1) / math.max(1, #pts - 2)
			local d = d0 + (d1 - d0) * f
			local c = shade(body, .1)
			local seg = { rod(model, 'Arm', pts[k], pts[k + 1], d, c, SP) }
			if k > 1 then
				table.insert(seg, ball(model, 'ArmJoint', d * 1.02, CF(pts[k]), c, SP))
			end
			if k % 2 == 0 and d > .07 then
				local along = (pts[k + 1] - pts[k]).Unit
				local side = inner and (inner - pts[k]) or V3(0, -1, 0)
				local off = (side - along * side:Dot(along))
				if off.Magnitude > 1e-3 then
					table.insert(seg, cylX(model, 'Sucker', .05, d * .55, CF((pts[k] + pts[k + 1]) / 2 + off.Unit * d * .45) * alignY(off.Unit) * CFrame.Angles(0, 0, math.pi / 2), sucker, SP, SMALL))
				end
			end
			table.insert(segs, seg)
		end
		local joint = pts[math.max(1, tipFrom)]
		for k, seg in ipairs(segs) do
			if k >= tipFrom then
				animAll(seg, motion, phase, joint)
			end
		end
		local last = pts[#pts]
		ball(model, 'ArmTip', d1 * .9, CF(last), shade(body:Lerp(WHITE, .1), .05), SP, SMALL)
		return last
	end
	local function curlPts(from, dir, up, radius, turns, steps)
		local out = {}
		local side = dir:Cross(up).Unit
		for k = 1, steps do
			local a = k / steps * turns * math.pi * 2
			local r = radius * (1 - k / steps * .55)
			table.insert(out, from + dir * math.sin(a) * r + up * (1 - math.cos(a)) * r + side * k * .01)
		end
		return out
	end
	-- two arms spread out sideways and curl down (the striking ends); the curl tips drip bog water
	local tips = {}
	for _, sx in ipairs({ -1, 1 }) do
		local pts = { M + V3(sx * .36, -.48, .34), M + V3(sx * .72, -.58, .4), M + V3(sx * 1.08, -.52, .34), M + V3(sx * 1.38, -.38, .24) }
		for _, p in ipairs(curlPts(pts[#pts], V3(sx, 0, 0), V3(0, 1, 0), .24, .8, 5)) do
			table.insert(pts, p)
		end
		local tip = arm(pts, .24, .07, 1, 'Tentacle', sx * 1.4, M + V3(0, -2, 0))
		table.insert(tips, tip)
		local dripAt = M + V3(sx * 1.4, -.62, .24)
		for dk, dd in ipairs({ { .33, .05 }, { .66, .045 }, { 1, .085 } }) do
			local drop = blob(model, 'BogDrip', V3(dd[2], dd[2] * (dk < 3 and 1.6 or 1.2), dd[2]), CF(dripAt - V3(0, .05 * dk, 0)), bog:Lerp(glow, .3), GL, { Transparency = .25, CastShadow = false })
			drop:SetAttribute('PickGoo', true)
			drop:SetAttribute('PickDropK', dd[1])
			anim(drop, 'GummyDrop', sx * .3, dripAt)
		end
	end
	-- two arms climb the blade's edges, wrapping it, and curl over its point
	for _, sx in ipairs({ -1, 1 }) do
		local pts = { M + V3(sx * .45, .1, .2), M + V3(sx * .74, .4, .12), V3(sx * .8, M.Y + .72, -.08), V3(sx * .74, M.Y + 1.0, .12),
			V3(sx * .58, M.Y + 1.24, -.06), V3(sx * .4, M.Y + 1.42, .12), V3(sx * .22, M.Y + 1.5, .16), V3(sx * .14, M.Y + 1.38, .2) }
		arm(pts, .2, .07, 6, 'Curl', sx * .8, V3(0, M.Y + .6, 0))
	end
	-- four arms spiral down the shaft, their loose tips sway
	for k = 0, 3 do
		local a0 = k / 4 * math.pi * 2 + .4
		local pts = { M + V3(math.cos(a0) * .3, -.5, .22 + math.sin(a0) * .1) }
		local steps = 6 + k
		for s = 1, steps do
			local a = a0 + s * .95
			table.insert(pts, V3(math.cos(a) * .25, bY - .2 - s * .17, math.sin(a) * .25))
		end
		local last = pts[#pts]
		table.insert(pts, last + V3(math.cos(a0 + steps * .95) * .18, -.12, math.sin(a0 + steps * .95) * .18))
		arm(pts, .17, .06, #pts - 2, 'Tentacle', k * .9, V3(0, last.Y, 0))
	end
	-- a dribble of bog water under the mantle
	local dripAt = M + V3(.1, -.62, .3)
	for dk, dd in ipairs({ { .33, .045 }, { .66, .04 }, { 1, .075 } }) do
		local drop = blob(model, 'BogDrip', V3(dd[2], dd[2] * 1.4, dd[2]), CF(dripAt - V3(0, .05 * dk, 0)), bog:Lerp(glow, .3), GL, { Transparency = .25, CastShadow = false })
		drop:SetAttribute('PickGoo', true)
		drop:SetAttribute('PickDropK', dd[1])
		anim(drop, 'GummyDrop', .7, dripAt)
	end

	-- LIGHT + FX -----------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'BogGlow', V3(.4, .4, .4), CF(M + V3(0, 0, .2)), glow, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'BogLight', glow, 7, 1)
	emitter(lamp, 'BogBubbles', SPARK_TEX, glow:Lerp(WHITE, .4), 2, .2, .4, 1.6, V3(0, 1, 0))

	model:SetAttribute('BackC0', CF(.25, -.35, .35))
	model:SetAttribute('DisplayScale', .8)
	return tips[1], tips[2]
end
-- >>HW_UyOctopus

-- <<HW_UyGummyHorror
-- GUMMY HORROR (Mythic): a translucent violet gummy DOG SKULL out of the Underyard candy shop. A voxel jelly cranium and
-- snout (glossy translucent cubes, lighter on top, sour-sugar crystals stuck on), deep sockets with candy eyeballs that
-- roll about, a dark gummy nose, CANDY-CORN fangs above and on a wobbling lower jaw, pointed gummy ears, and inside it all
-- a glowing green jawbreaker "brain" with a swirl. The pick arms are two fat GUMMY WORMS (lime / orange and orange /
-- violet, ribbed, sugar-crusted) that burst out of the skull's sides, arch over and dive down into little worm heads with
-- open mouths; jelly drips forever off the jaw and the worm heads. The POLE is a paper lollipop stick wound with a black
-- licorice lace; the grip is a stack of gummy rings; the POMMEL a foil-wrapped bonbon with twisted ends.
-- Motion: the skull jiggles (GummyWobble), the worms bend from the root (GummyArm), the eyes roll (GummyEye), the jaw
-- chews (GummyJaw), the drips stretch and fall (GummyDrop + PickGoo), the core pulses; live: chomps and wobbles.
DESIGNS.HW_UyGummyHorror = function(model, v, def, len, top)
	local rnd = rng(7019)
	local shade = shader(rnd)
	local gummy = rgb(v.Head)
	local core = rgb(v.Accent)
	local orange = rgb(v.Orange)
	local lime = rgb(v.Lime)
	local licorice = rgb(v.Licorice)
	local sugar = rgb(v.Sugar)
	local stick = rgb(v.Shaft)
	local yellow = Color3.fromRGB(255, 214, 90)
	local JELLY = { Transparency = .3, CastShadow = false }
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local H = V3(0, top.Y + .82, 0)             -- skull centre

	-- POLE: the paper lollipop stick, the licorice lace, the gummy-ring grip, the bonbon ------------------------------------------
	local y0, y1 = -half + .1, H.Y - .55
	cylY(model, 'Stick', y1 - y0, .28, CF(0, (y0 + y1) / 2, 0), shade(stick, .03), SP)
	for k = 0, 3 do
		local a = k * math.pi / 2
		part(model, 'StickSeam', V3(.02, y1 - y0 - .3, .02), CF(math.sin(a) * .14, (y0 + y1) / 2, math.cos(a) * .14), stick:Lerp(BLACK, .12), SP, SMALL)
	end
	local lace = {}
	for k = 0, 22 do
		local a = k * .75
		table.insert(lace, V3(math.cos(a) * .16, -.62 + k * .115, math.sin(a) * .16))
	end
	tube(model, 'Licorice', lace, .075, .075, function(k) return k % 6 == 0 and gummy or shade(licorice, .05) end, SP)
	local ringCols = { gummy, lime, orange }
	for g = 0, 9 do
		local gy = -1.92 + g * .115
		cylY(model, 'GummyRing', .1, .42, CF(0, gy, 0), ringCols[g % 3 + 1], GL, { Transparency = .2 })
		if g % 2 == 0 then
			part(model, 'RingSugar', V3(.05, .04, .05), CF(math.cos(g) * .2, gy + .04, math.sin(g) * .2), sugar, SP, SMALL)
		end
	end
	local B = V3(0, -half - .14, 0)
	ball(model, 'Bonbon', .4, CF(B), shade(gummy:Lerp(BLACK, .2), .04), SP, { Reflectance = .25 })
	cylX(model, 'BonbonBand', .08, .41, CF(B), sugar, SP, { Reflectance = .2 })
	for _, sx in ipairs({ -1, 1 }) do
		cylX(model, 'BonbonTwist', .12, .14, CF(B + V3(sx * .24, 0, 0)), shade(gummy:Lerp(BLACK, .2), .04), SP, { Reflectance = .25 })
		for f = -1, 1 do
			spike(model, 'BonbonEnd', B + V3(sx * .28, 0, 0), V3(sx, f * .5, 0), V3(0, 0, 1), .22, .14, .03, f == 0 and sugar or shade(gummy:Lerp(BLACK, .1), .04), SP)
		end
	end
	-- the sticky jelly joint holding the skull on the stick
	blob(model, 'JellyJoint', V3(.46, .3, .46), CF(V3(0, y1 + .02, 0)), gummy, GL, JELLY)

	-- THE SKULL: a translucent voxel cranium + snout, sugar, sockets, the core ----------------------------------------------------
	local Cc = H + V3(0, .1, -.08)
	local Sn = H + V3(0, -.22, .42)
	local sockets = { V3(-.24, -.06, .42), V3(.24, -.06, .42) }
	local skull = shell(model, 'GummySkull', Cc, .62, .55, .52, .155, function(p)
		for _, s in ipairs(sockets) do
			if (p - s).Magnitude < .19 then return false end
		end
		return true
	end, function(p)
		return shade(p.Y > .25 and gummy:Lerp(WHITE, .18) or (p.Y < -.25 and gummy:Lerp(BLACK, .15) or gummy), .08)
	end, GL, JELLY)
	for _, p in ipairs(shell(model, 'GummySnout', Sn, .34, .25, .36, .14, function(p) return p.Z > -.12 end, function(p)
		return shade(p.Y > .1 and gummy:Lerp(WHITE, .12) or gummy, .08)
	end, GL, JELLY)) do
		table.insert(skull, p)
	end
	-- dark sockets with candy eyeballs that roll
	for _, s in ipairs(sockets) do
		local c = Cc + s - V3(0, 0, .06)
		table.insert(skull, blob(model, 'Socket', V3(.3, .3, .1), CF(c), gummy:Lerp(BLACK, .55), GL, { Transparency = .15, CastShadow = false }))
		local eye = { ball(model, 'CandyEye', .22, CF(c + V3(0, 0, .04)), sugar, SP),
			cylZ(model, 'CandyIris', .02, .12, CF(c + V3(0, 0, .15)), core, NE, GLOW),
			cylZ(model, 'CandyPupil', .025, .06, CF(c + V3(0, 0, .16)), licorice, SP, SMALL) }
		animAll(eye, 'GummyEye', s.X, c + V3(0, 0, .04))
	end
	-- brow ridge, ears, nose, sour sugar on top
	for _, sx in ipairs({ -1, 1 }) do
		table.insert(skull, part(model, 'Brow', V3(.3, .1, .14), CF(Cc + V3(sx * .24, .14, .44)) * CFrame.Angles(0, 0, sx * -.2), gummy:Lerp(BLACK, .25), GL, JELLY))
		table.insert(skull, wedge(model, 'GummyEar', V3(.12, .4, .26), CF(Cc + V3(sx * .4, .58, -.12)) * CFrame.Angles(0, 0, sx * -.3), gummy:Lerp(WHITE, .1), GL, JELLY))
	end
	table.insert(skull, blob(model, 'GummyNose', V3(.22, .14, .12), CF(Sn + V3(0, .1, .33)), gummy:Lerp(BLACK, .5), GL, { Transparency = .1 }))
	for k = 1, 16 do
		local a = rnd() * math.pi * 2
		local e = .35 + rnd() * .9
		local d = V3(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e))
		table.insert(skull, part(model, 'Sugar', V3(.05, .05, .05), CF(Cc + V3(d.X * .64, d.Y * .57, d.Z * .54)) * CFrame.Angles(rnd(), rnd(), rnd()), sugar, SP, SMALL))
	end
	-- candy-corn fangs on the upper jaw
	local function candyCorn(base, dir, size)
		local u = dir.Unit
		local out = {}
		table.insert(out, part(model, 'CandyCorn', V3(.08, .06, .08) * size, CF(base) * alignY(u), yellow, SP, SMALL))
		table.insert(out, part(model, 'CandyCorn', V3(.07, .06, .07) * size, CF(base + u * .06 * size) * alignY(u), orange, SP, SMALL))
		table.insert(out, spike(model, 'CandyCornTip', base + u * .09 * size, u, V3(0, 0, 1), .09 * size, .07 * size, .06 * size, sugar, SP, SMALL))
		return out
	end
	for t = -2, 2 do
		local tx = t * .1
		for _, p in ipairs(candyCorn(Sn + V3(tx, -.2, .24 - math.abs(t) * .03), V3(0, -1, .1), math.abs(t) == 2 and 1.25 or 1)) do
			table.insert(skull, p)
		end
	end
	-- the lower jaw (chews) with its own candy corn
	local jawPivot = Sn + V3(0, -.2, -.42)
	local jaw = { blob(model, 'GummyJaw', V3(.6, .16, .56), CF(Sn + V3(0, -.36, -.02)), gummy:Lerp(BLACK, .1), GL, JELLY) }
	for t = -1, 1 do
		for _, p in ipairs(candyCorn(Sn + V3(t * .12, -.3, .22 - math.abs(t) * .03), V3(0, 1, .1), .9)) do
			table.insert(jaw, p)
		end
	end
	local jdrip = Sn + V3(.08, -.46, .1)
	animAll(jaw, 'GummyJaw', 0, jawPivot)
	animAll(skull, 'GummyWobble', 0)
	-- the jawbreaker brain inside
	local brain = ball(model, 'JawbreakerCore', .5, CF(Cc + V3(0, .02, -.04)), core, NE, { Transparency = .1, CastShadow = false })
	brain:SetAttribute('PickPulse', true)
	ring(model, 'CoreSwirl', CF(Cc + V3(0, .02, -.04)) * CFrame.Angles(.4, .3, 0), .27, .05, .06, 12, function(i) return i % 2 == 0 and WHITE or orange end, SP, nil, SMALL)
	anim(brain, 'GummyWobble', 0)

	-- THE GUMMY WORMS: out of the skull sides, arching over and down into worm heads (the striking ends) --------------------------------
	local tips = {}
	for wi, sx in ipairs({ -1, 1 }) do
		local cA, cB = wi == 1 and lime or orange, wi == 1 and orange or gummy
		local p0, p1, p2, p3 = Cc + V3(sx * .5, -.08, -.04), Cc + V3(sx * 1.25, .55, -.04), Cc + V3(sx * 1.85, .05, -.04), Cc + V3(sx * 1.62, -.85, -.04)
		local N = 10
		local prev = bez(p0, p1, p2, p3, 0)
		for k = 1, N do
			local f = k / N
			local q = bez(p0, p1, p2, p3, f)
			local d = .3 - f * .08
			local segParts = { rod(model, 'GummyWorm', prev, q, d, k % 2 == 0 and cA or cB, GL, { Transparency = .12 }) }
			table.insert(segParts, ball(model, 'GummyWormJoint', d * .96, CF(q), k % 2 == 0 and cB or cA, GL, { Transparency = .12 }))
			if k % 3 == 1 then
				table.insert(segParts, part(model, 'WormSugar', V3(.05, .05, .05), CF(q + V3(0, d * .5, 0)) * CFrame.Angles(rnd(), rnd(), rnd()), sugar, SP, SMALL))
			end
			for _, sp in ipairs(segParts) do
				sp:SetAttribute('PickAmp', sx * f)
			end
			animAll(segParts, 'GummyArm', 0, p0)
			prev = q
		end
		-- the worm head: a round head pointing down, two dot eyes, an open mouth
		local dirDown = (p3 - bez(p0, p1, p2, p3, .9)).Unit
		local hd = p3 + dirDown * .12
		local head = { ball(model, 'WormHead', .3, CF(hd), cA, GL, { Transparency = .1 }) }
		local side = dirDown:Cross(V3(0, 0, 1)).Unit
		for _, e in ipairs({ -1, 1 }) do
			table.insert(head, ball(model, 'WormEye', .06, CF(hd + side * e * .07 + V3(0, 0, .13)), licorice, SP, SMALL))
		end
		table.insert(head, blob(model, 'WormMouth', V3(.12, .1, .06), CF(hd + dirDown * .12 + V3(0, 0, .06)), licorice:Lerp(gummy, .2), SP, SMALL))
		for _, hp in ipairs(head) do
			hp:SetAttribute('PickAmp', sx)
		end
		animAll(head, 'GummyArm', 0, p0)
		local tip = hd + dirDown * .16
		table.insert(tips, tip)
		for dk, dd in ipairs({ { .33, .05 }, { .66, .045 }, { 1, .09 } }) do
			local drop = blob(model, 'JellyDrip', V3(dd[2], dd[2] * (dk < 3 and 1.6 or 1.2), dd[2]), CF(tip - V3(0, .04 * dk, 0)), cA, GL, { Transparency = .25, CastShadow = false })
			drop:SetAttribute('PickGoo', true)
			drop:SetAttribute('PickDropK', dd[1])
			anim(drop, 'GummyDrop', wi * .37, tip)
		end
	end
	-- jelly dripping off the jaw
	for di, jx in ipairs({ -.16, .1 }) do
		local at0 = jdrip + V3(jx - .08, 0, 0)
		for dk, dd in ipairs({ { .33, .05 }, { .66, .045 }, { 1, .085 } }) do
			local drop = blob(model, 'JellyDrip', V3(dd[2], dd[2] * (dk < 3 and 1.6 or 1.2), dd[2]), CF(at0 - V3(0, .04 * dk, 0)), gummy, GL, { Transparency = .25, CastShadow = false })
			drop:SetAttribute('PickGoo', true)
			drop:SetAttribute('PickDropK', dd[1])
			anim(drop, 'GummyDrop', di * .53, at0)
		end
	end

	-- LIGHT + FX -----------------------------------------------------------------------------------------------------------------
	local lamp = part(model, 'CoreGlow', V3(.3, .3, .3), CF(Cc), core, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'CoreLight', core, 7, 1.1)
	emitter(lamp, 'SugarSparkle', SPARK_TEX, sugar, 2, .16, .5, 1.2, V3(0, .6, 0))

	model:SetAttribute('BackC0', CF(.25, -.35, .35))
	model:SetAttribute('DisplayScale', .8)
	return tips[1], tips[2]
end
-- >>HW_UyGummyHorror

-- <<HW_UyBellReaper
-- BELL REAPER (Secret): the scythe of the Black Bell, given only to whoever found every dog of the Underyard. The HEAD is
-- a black iron BELL sitting on the pole like a cap (mouth down): a flared lip, a waist ringed with violet runes, a crack
-- up the front leaking violet light, a clapper swinging inside under the lip, a crooked iron hanger on the crown and a
-- little bone dog skull with violet eyes on top. Out of its shoulder sweeps the BLADE: a violet CRESCENT MOON (thick in
-- the middle, tapering to both horns), a dark rim on its outer curve, a lavender moon face with craters on both sides, a
-- violet cutting edge with a white-hot core on the inner curve and a soft aura, ending in a long point; a dark iron spur
-- hooks back on the other side. Three tiny ghost BELLS circle the head with violet wisps. The POLE is obsidian bound by two
-- spiralling iron straps with violet runes and bone collars; the bell's rope coils down it and ends in a tassel; the grip
-- is black leather with violet stitching; the POMMEL a small black hand bell.
-- Motion: the ghost bells Orbit, the clapper and the tassel swing (ScytheChain / ScytheTalisman), runes / edge / crack /
-- eyes pulse (PickPulse); live: the bell tolls (the clapper strikes, the runes flare), the moon brightens.
-- Held like a scythe: HandTilt 28 / HandYaw 45.
DESIGNS.HW_UyBellReaper = function(model, v, def, len, top)
	local rnd = rng(8887)
	local shade = shader(rnd)
	local black = rgb(v.Shaft)
	local iron = rgb(v.Head)
	local violet = rgb(v.Accent)
	local moonC = rgb(v.Moon)
	local crater = rgb(v.Crater)
	local rope = rgb(v.Rope)
	local bone = rgb(v.Bone)
	local hot = Color3.fromRGB(248, 236, 255)
	model.PrimaryPart.Transparency = 1
	local half = len * .5
	local mouthY = top.Y - .05                  -- the bell's lip
	local B = V3(0, mouthY + .6, 0)              -- bell centre

	-- POLE: obsidian, two spiralling iron straps, rune inlays, bone collars, the grip -----------------------------------------------
	local y0, y1 = -half + .15, mouthY + .9
	cylY(model, 'Pole', y1 - y0, .3, CF(0, (y0 + y1) / 2, 0), shade(black, .05), SP, { Reflectance = .08 })
	for st = 0, 1 do
		local pts = {}
		for k = 0, 26 do
			local a = k * .62 + st * math.pi
			table.insert(pts, V3(math.cos(a) * .155, -.7 + k * .13, math.sin(a) * .155))
		end
		tube(model, 'IronStrap', pts, .05, .05, function() return shade(iron:Lerp(WHITE, .12), .05) end, ME, { Reflectance = .1 })
	end
	for k = 0, 5 do
		local ry = -.45 + k * .55
		local r = part(model, 'PoleRune', V3(.05, .22, .02), CF(0, ry, .155), violet, NE, GLOW)
		r:SetAttribute('PickPulse', true)
		part(model, 'PoleRuneBar', V3(.12, .03, .02), CF(0, ry + (k % 2 == 0 and .05 or -.05), .155), violet, NE, GLOW)
	end
	for _, cy in ipairs({ -half + .35, -2.1, -.75, mouthY - .3 }) do
		cylY(model, 'BoneCollar', .12, .4, CF(0, cy, 0), shade(bone, .05), SP)
		cylY(model, 'BoneCollarRim', .04, .44, CF(0, cy + .07, 0), bone:Lerp(BLACK, .12), SP)
	end
	for g = 0, 11 do
		local gy = -2.02 + g * .11
		part(model, 'GripWrap', V3(.37, .09, .37), CF(0, gy, 0) * CFrame.Angles(0, g * .4, (g % 2 == 0 and .1 or -.1)), shade(Color3.fromRGB(30, 24, 36), .1), material('Leather', FA))
		if g % 3 == 1 then
			part(model, 'GripStitch', V3(.3, .02, .02), CF(0, gy, .19) * CFrame.Angles(0, 0, .5), violet, NE, GLOW)
		end
	end
	-- the bell rope coiling down the pole, its tassel
	local ropePts = { B + V3(.3, .62, -.2), B + V3(.5, .2, -.38), V3(.55, mouthY - .12, -.3), V3(.36, mouthY - .3, -.1) }
	for k = 0, 12 do
		local a = 1.2 + k * .8
		table.insert(ropePts, V3(math.cos(a) * .21, mouthY - .45 - k * .2, math.sin(a) * .21))
	end
	tube(model, 'BellRope', ropePts, .09, .08, function(k) return k % 2 == 0 and shade(rope, .05) or shade(rope:Lerp(BLACK, .15), .05) end, FA)
	local tasselAt = ropePts[#ropePts]
	local tassel = { ball(model, 'TasselKnot', .14, CF(tasselAt - V3(0, .04, 0)), rope:Lerp(BLACK, .1), FA) }
	for t = 0, 5 do
		local a = t / 6 * math.pi * 2
		table.insert(tassel, part(model, 'Tassel', V3(.03, .3, .03), CF(tasselAt + V3(math.cos(a) * .04, -.2, math.sin(a) * .04)) * CFrame.Angles(math.sin(a) * .15, 0, math.cos(a) * .15), t % 2 == 0 and rope or violet:Lerp(BLACK, .3), FA, SMALL))
	end
	animAll(tassel, 'ScytheTalisman', .4, tasselAt)
	-- POMMEL: a small black hand bell
	local P = V3(0, -half - .05, 0)
	for _, row in ipairs({ { 0, .2, .06 }, { -.08, .3, .1 }, { -.18, .34, .1 }, { -.27, .4, .06 }, { -.31, .46, .03 } }) do
		cylY(model, 'PommelBell', row[3], row[2], CF(P + V3(0, row[1], 0)), shade(iron, .05), ME, { Reflectance = .1 })
	end
	local pc = ball(model, 'PommelClapper', .12, CF(P + V3(0, -.34, 0)), violet, NE, GLOW)
	pc:SetAttribute('PickPulse', true)
	anim(pc, 'ScytheChain', .2, P - V3(0, .1, 0))

	-- THE BELL (mouth down, on the pole top) --------------------------------------------------------------------------------------
	local PROFILE = { { .03, 1.44, .06 }, { .1, 1.32, .1 }, { .22, 1.18, .14 }, { .38, 1.06, .18 }, { .56, 1.0, .18 }, { .72, .96, .14 }, { .84, .86, .1 }, { .95, .7, .1 }, { 1.04, .5, .08 }, { 1.1, .3, .06 } }
	local function bellR(off)
		local prev = PROFILE[1]
		for _, row in ipairs(PROFILE) do
			if row[1] >= off then
				local f = (off - prev[1]) / math.max(1e-3, row[1] - prev[1])
				return (prev[2] + (row[2] - prev[2]) * math.clamp(f, 0, 1)) * .5
			end
			prev = row
		end
		return prev[2] * .5
	end
	for i, row in ipairs(PROFILE) do
		cylY(model, 'BlackBell', row[3], row[2], CF(0, mouthY + row[1], 0) * CFrame.Angles(0, i * .3, 0), shade(iron, .06), ME, { Reflectance = .12 })
	end
	cylY(model, 'BellLipRing', .04, 1.48, CF(0, mouthY + .06, 0), shade(iron:Lerp(violet, .25), .05), ME, { Reflectance = .15 })
	cylY(model, 'BellWaistRing', .04, 1.1, CF(0, mouthY + .28, 0), shade(iron:Lerp(WHITE, .12), .05), ME, { Reflectance = .15 })
	cylY(model, 'BellWaistRing', .04, 1.0, CF(0, mouthY + .66, 0), shade(iron:Lerp(WHITE, .12), .05), ME, { Reflectance = .15 })
	local inside = cylY(model, 'BellInside', .02, 1.24, CF(0, mouthY + .02, 0), violet:Lerp(BLACK, .55), NE, { Transparency = .1, CastShadow = false })
	inside:SetAttribute('PickPulse', true)
	-- the ring of runes on the waist (3 x 3 pixel marks, facing out)
	local RUNES = { { '#.#', '.#.', '#.#' }, { '###', '#..', '###' }, { '.#.', '###', '.#.' }, { '#..', '###', '..#' }, { '##.', '.##', '#.#' } }
	for k = 0, 7 do
		local a = math.rad(-90 + k * 45)
		local ry = mouthY + .47
		local r = bellR(.47) + .012
		local out = V3(math.cos(a), 0, -math.sin(a))
		local side = V3(math.sin(a), 0, math.cos(a))
		local px = .05
		local glyph = RUNES[k % #RUNES + 1]
		for rr = 1, 3 do
			for cc = 1, 3 do
				if string.sub(glyph[rr], cc, cc) == '#' then
					local g = part(model, 'BellRune', V3(px - .006, px - .006, .02), CFrame.fromMatrix(V3(0, ry, 0) + out * r + side * (cc - 2) * px + V3(0, (2 - rr) * px, 0), side, V3(0, 1, 0), out), violet, NE, GLOW)
					g:SetAttribute('PickPulse', true)
				end
			end
		end
	end
	-- the crack up the front, violet light leaking out
	local crack = { { .06, .0 }, { .1, .14 }, { .05, .27 }, { .12, .42 }, { .08, .55 } }
	for k = 1, #crack - 1 do
		local a0, a1 = crack[k], crack[k + 1]
		local p0 = V3(a0[1], mouthY + .03 + a0[2], bellR(.03 + a0[2]) + .01)
		local p1 = V3(a1[1], mouthY + .03 + a1[2], bellR(.03 + a1[2]) + .01)
		local c = bar(model, 'BellCrack', p0, p1, .04, .03, violet:Lerp(WHITE, .25), NE, GLOW)
		c:SetAttribute('PickPulse', true)
	end
	-- the clapper inside, its ball swinging just under the lip
	local hangC = V3(.24, mouthY + .8, 0)
	local clapper = { rod(model, 'ClapperRod', hangC, V3(.3, mouthY - .08, 0), .06, shade(iron, .05), ME), ball(model, 'Clapper', .22, CF(V3(.3, mouthY - .16, 0)), shade(iron:Lerp(violet, .2), .05), ME) }
	animAll(clapper, 'ScytheChain', .7, hangC)
	-- the crooked iron hanger on the crown and the little dog skull on top
	local crownY = mouthY + 1.15
	ring(model, 'Hanger', CF(V3(0, crownY + .2, 0)) * CFrame.Angles(0, .25, .12), .2, .07, .1, 12, function() return shade(iron:Lerp(WHITE, .1), .06) end, ME, function(i) return i >= 9 end)
	for _, sx in ipairs({ -1, 1 }) do
		bar(model, 'HangerStrap', V3(sx * .14, crownY - .06, 0), V3(sx * .18, crownY + .14, 0), .07, .1, shade(iron, .05), ME)
	end
	local K = CF(0, crownY + .5, .02) * CFrame.Angles(0, 0, -.12)
	part(model, 'SkullCap', V3(.36, .26, .32), K, shade(bone, .05), SP)
	part(model, 'SkullSnout', V3(.2, .14, .22), K * CF(0, -.08, .22), shade(bone, .05), SP)
	part(model, 'SkullNose', V3(.08, .05, .03), K * CF(0, -.04, .34), Color3.fromRGB(30, 20, 30), SP, SMALL)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, 'SkullSocket', V3(.1, .08, .03), K * CF(sx * .08, .02, .165), Color3.fromRGB(20, 10, 30), SP, SMALL)
		local e = ball(model, 'SkullEye', .06, K * CF(sx * .08, .02, .175), violet, NE, GLOW)
		e:SetAttribute('PickPulse', true)
		wedge(model, 'SkullEar', V3(.05, .16, .1), K * CF(sx * .14, .2, -.06) * CFrame.Angles(0, 0, sx * -.3), shade(bone, .05), SP)
	end
	for t = -1, 1 do
		part(model, 'SkullTooth', V3(.035, .045, .03), K * CF(t * .05, -.16, .31), WHITE, SP, SMALL)
	end

	-- THE MOON BLADE: a crescent round O (thick in the middle, horns at both ends) ------------------------------------------------
	local O = B + V3(1.55, -.5, -.02)
	local RO = 2.0
	local T0, T1 = math.rad(160), math.rad(-38)
	local N = 28
	local frames = {}
	for i = 1, N do
		local u = (i - .5) / N
		local th = T0 + (T1 - T0) * u
		local rad = V3(math.cos(th), math.sin(th), 0)
		local tan = V3(math.sin(th), -math.cos(th), 0) -- along the sweep (decreasing angle)
		local w = .07 + .76 * math.sin(math.pi * u) ^ .85
		local seg = 2 * RO * math.sin(math.abs(T1 - T0) / N / 2)
		frames[i] = { U = u, Th = th, R = rad, T = tan, W = w, Seg = seg }
	end
	local function band(f, name, r0, r1, depth, color, mat, props, lenK, z)
		local rm = (r0 + r1) * .5
		local c = O + f.R * rm + V3(0, 0, z or 0)
		local segLen = f.Seg * rm / RO
		return part(model, name, V3(segLen * (lenK or 1.16), math.max(.02, r1 - r0), depth), CFrame.fromMatrix(c, f.T, f.R, f.T:Cross(f.R)), color, mat, props)
	end
	local edges = {}
	for i, f in ipairs(frames) do
		local w = f.W
		local inner = RO - w
		band(f, 'MoonRim', RO - .1, RO + .02, .2 - f.U * .04, shade(iron:Lerp(violet, .15), .08), ME, { Reflectance = .1 }, 1.08)
		if w > .24 then
			band(f, 'MoonFace', inner + .12, RO - .1, .17, shade(i % 5 == 0 and moonC:Lerp(WHITE, .15) or moonC, .07), SP)
		end
		local e = band(f, 'MoonEdge', inner + .02, inner + math.min(.12, w * .5), .1, violet, NE, GLOW)
		e:SetAttribute('PickPulse', true)
		table.insert(edges, e)
		band(f, 'MoonEdgeHot', inner - .01, inner + .03, .06, hot, NE, GLOW)
		band(f, 'MoonAura', inner - .12, inner - .01, .03, violet, NE, { CastShadow = false, Transparency = .55 })
		if i % 4 == 2 and w > .3 then
			band(f, 'MoonRimStud', RO + .01, RO + .07, .12, shade(iron:Lerp(WHITE, .2), .05), ME, SMALL, .3)
		end
	end
	-- craters on both faces of the moon
	for _, face in ipairs({ 1, -1 }) do
		for c = 1, 6 do
			local fi = math.floor((.18 + c * .1 + (face < 0 and .05 or 0)) * N + .5)
			local f = frames[math.clamp(fi, 1, N)]
			if f.W > .36 then
				local rr = RO - .1 - (f.W - .22) * (.3 + rnd() * .4)
				local size = .12 + rnd() * .14 * math.min(1, f.W / .6)
				local pos = O + f.R * rr + V3(0, 0, face * .09)
				cylZ(model, 'CraterRim', .02, size * 1.25, CF(pos), moonC:Lerp(WHITE, .25), SP, SMALL)
				cylZ(model, 'Crater', .025, size, CF(pos + V3(0, 0, face * .006)), shade(crater, .08), SP, SMALL)
			end
		end
	end
	do
		local last = frames[N]
		local tipBase = O + last.R * (RO - last.W * .5) + last.T * last.Seg * .4
		spike(model, 'MoonTip', tipBase, last.T, last.R, .62, .14, .14, moonC, SP)
		spike(model, 'MoonTipEdge', tipBase - last.R * .04, last.T, last.R, .7, .08, .06, hot, NE, GLOW)
	end
	-- the clamp holding the horn in the bell's shoulder
	local root = O + frames[1].R * (RO - .05)
	part(model, 'BladeClamp', V3(.3, .44, .4), CF(root + V3(.05, -.05, 0)) * CFrame.Angles(0, 0, -.5), shade(iron, .06), ME)
	for k = -1, 1 do
		part(model, 'ClampRivet', V3(.05, .05, .04), CF(root + V3(.05 + k * .08, -.05 + k * .12, .21)), violet, NE, GLOW)
	end
	-- the back spur: a small dark crescent hooking down behind
	local sb = B + V3(-.5, .45, 0)
	local prevS = sb
	for k = 1, 4 do
		local f = k / 4
		local p = sb + V3(-f * .75, f * .25 - f * f * .6, 0)
		bar(model, 'BackSpur', prevS, p, .2 - f * .1, .16 - f * .06, shade(iron, .08), ME)
		prevS = p
	end
	spike(model, 'BackSpurTip', prevS, V3(-.3, -1, 0), V3(0, 0, 1), .3, .12, .1, iron:Lerp(violet, .3), ME)

	-- THE GHOST BELLS circling the head ------------------------------------------------------------------------------------------
	local center = B + V3(.2, .15, 0)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + .6
		local p = center + V3(math.cos(a) * 1.55, math.sin(k * 2.1) * .3, math.sin(a) * 1.55)
		local gb = {}
		table.insert(gb, cylY(model, 'GhostBell', .14, .22, CF(p + V3(0, .02, 0)), hot, NE, { Transparency = .25, CastShadow = false }))
		table.insert(gb, cylY(model, 'GhostBell', .06, .3, CF(p - V3(0, .08, 0)), violet:Lerp(WHITE, .4), NE, { Transparency = .25, CastShadow = false }))
		table.insert(gb, ball(model, 'GhostBellTop', .12, CF(p + V3(0, .12, 0)), hot, NE, { Transparency = .25, CastShadow = false }))
		table.insert(gb, ball(model, 'GhostBellHalo', .5, CF(p), violet, NE, { Transparency = .7, CastShadow = false }))
		table.insert(gb, blob(model, 'GhostBellWisp', V3(.1, .1, .36), CFrame.lookAt(p, p + V3(-math.sin(a), 0, math.cos(a))) * CF(0, 0, .26), violet, NE, { Transparency = .5, CastShadow = false }))
		animAll(gb, 'Orbit', k / 3, center)
	end

	-- LIGHT + FX -----------------------------------------------------------------------------------------------------------------
	local mid = frames[math.floor(N * .45)]
	local lamp = part(model, 'MoonGlow', V3(.6, .6, .2), CF(O + mid.R * (RO - mid.W * .5)), violet, SP, { Transparency = 1, CastShadow = false })
	light(lamp, 'MoonLight', violet, 8, 1.2)
	emitter(lamp, 'MoonDust', SPARK_TEX, violet:Lerp(WHITE, .35), 4, .24, .7, 1.4, V3(0, 1.2, 0))
	local bellLamp = part(model, 'BellGlow', V3(.4, .3, .4), CF(0, mouthY + .1, 0), violet, SP, { Transparency = 1, CastShadow = false })
	light(bellLamp, 'BellLight', violet, 5, .8)

	model:SetAttribute('BackC0', CF(.15, -.35, .2))
	model:SetAttribute('HandYaw', 45)
	model:SetAttribute('HandTilt', 28)
	model:SetAttribute('DisplayScale', .76)
	local tipW = frames[N]
	return B + V3(-1.2, .2, 0), O + tipW.R * (RO - tipW.W * .5) + tipW.T * .6
end
-- >>HW_UyBellReaper

-- @@DESIGNS2_END
S2.Designs = DESIGNS

---------------------------------------------------------------------------------------------------------------------
-- SOUND KITS (MiningAudio.Kits rows: {soundId, volume, speed, effects?, at=, dur=, attack=, fade=, loop=, to=, ramp=})
---------------------------------------------------------------------------------------------------------------------
-- The impact rule (DESIGN §16.3): every Hit carries exactly ONE soft impact (KNOCK or LAND under SOFT, second row);
-- no kit uses a THUMP / DOOM-style distorted low boost; Crit / Break keep at most one soft impact.
function S2.Kits(Audio)
	local TICK, PING, KNOCK, LAND, WIND, WATER, SPLAT, CLICK, SLASH, _LUNGE, SHEATH, HOP = table.unpack(Audio.Sources)
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
	-- n clicks / ticks (ratchets, knuckles, rattles)
	local function clicks(id, n, base, gap, vol, start, fx)
		local rows = {}
		for i = 1, n do
			table.insert(rows, { id, vol, base * (1 + (i % 3) * .08), fx, at = (start or 0) + (i - 1) * gap })
		end
		return rows
	end
	-- a sliding laugh / bubble run: n gliding pings
	local function glides(n, base, gap, vol, start, fx, drop)
		local rows = {}
		for i = 1, n do
			local p = base * (1 - (i - 1) * .035)
			table.insert(rows, { PING, vol, p, fx, at = (start or 0) + (i - 1) * gap, dur = gap * .7, fade = gap * .3, to = p * (drop or .78), ramp = gap * .7, loop = true })
		end
		return rows
	end
	local SOFT = { EqualizerSoundEffect = { LowGain = 2, MidGain = 0, HighGain = -6 } }
	local AIRY = { EqualizerSoundEffect = { LowGain = -8, MidGain = 2, HighGain = 4 }, FlangeSoundEffect = { Depth = .5, Mix = .6, Rate = 3 } }
	local BONE = { DistortionSoundEffect = { Level = .5 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 6, HighGain = -8 } }
	local CRUNCH = { DistortionSoundEffect = { Level = .75 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 6, HighGain = -6 } }
	local RATTLE = { TremoloSoundEffect = { Depth = 1, Duty = .3, Frequency = 11 }, EqualizerSoundEffect = { LowGain = -8, MidGain = 4, HighGain = 0 } }
	local CREAK = { TremoloSoundEffect = { Depth = 1, Duty = .16, Frequency = .6 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 2, HighGain = 0 } }
	local BELL = { ReverbSoundEffect = { DecayTime = 1.4, WetLevel = -5 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 2, HighGain = 2 } }
	local RINGER = { TremoloSoundEffect = { Depth = 1, Duty = .5, Frequency = 22 }, EqualizerSoundEffect = { LowGain = -8, MidGain = 3, HighGain = 0 },
		ReverbSoundEffect = { DecayTime = 1, WetLevel = -6 } }
	local TICKTOCK = { TremoloSoundEffect = { Depth = 1, Duty = .12, Frequency = 2 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = -4 } }
	local GLASS = { ReverbSoundEffect = { DecayTime = 1.6, WetLevel = -4 }, EqualizerSoundEffect = { LowGain = -10, MidGain = 0, HighGain = 4 } }
	local SAND = { EqualizerSoundEffect = { LowGain = -20, MidGain = -4, HighGain = 6 }, TremoloSoundEffect = { Depth = .5, Duty = .5, Frequency = 13 } }
	local TOLL = { ReverbSoundEffect = { DecayTime = 4, WetLevel = -1, DryLevel = -2, Density = 1, Diffusion = 1 }, EqualizerSoundEffect = { LowGain = 4, MidGain = 0, HighGain = -10 } }
	local BUZZ = { DistortionSoundEffect = { Level = .8 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 6, HighGain = -2 } }
	local RING = { ReverbSoundEffect = { DecayTime = 1.6, WetLevel = -4 }, EqualizerSoundEffect = { LowGain = -8, MidGain = 0, HighGain = 4 } }
	local HONK = { DistortionSoundEffect = { Level = .5 }, EqualizerSoundEffect = { LowGain = 0, MidGain = 6, HighGain = -6 }, ChorusSoundEffect = { Depth = .3, Mix = .5, Rate = 5 } }
	local LAUGH = { DistortionSoundEffect = { Level = .7 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 8, HighGain = -10 }, TremoloSoundEffect = { Depth = .5, Duty = .5, Frequency = 30 } }
	local STATIC = { DistortionSoundEffect = { Level = .9 }, EqualizerSoundEffect = { LowGain = -20, MidGain = -6, HighGain = 8 } }
	local WHINE = { EqualizerSoundEffect = { LowGain = -20, MidGain = -8, HighGain = 4 } }
	local BOG = { EqualizerSoundEffect = { LowGain = 6, MidGain = -2, HighGain = -14 }, ReverbSoundEffect = { DecayTime = .9, WetLevel = -8 } }
	local BLUB = { EqualizerSoundEffect = { LowGain = 4, MidGain = 2, HighGain = -12 }, FlangeSoundEffect = { Depth = .4, Mix = .4, Rate = 1.5 } }
	local GOO = { EqualizerSoundEffect = { LowGain = 6, MidGain = -4, HighGain = -18 }, FlangeSoundEffect = { Depth = .4, Mix = .5, Rate = 2 } }
	local SQUISH = { EqualizerSoundEffect = { LowGain = 6, MidGain = -2, HighGain = -14 } }
	local WOBBLE = { TremoloSoundEffect = { Depth = .7, Duty = .5, Frequency = 9 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 4, HighGain = -6 } }
	local CHOIR = { ChorusSoundEffect = { Depth = .5, Mix = .75, Rate = 1.5 }, ReverbSoundEffect = { DecayTime = 3.2, WetLevel = -2 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 3, HighGain = -6 } }
	local SHINE = { ReverbSoundEffect = { DecayTime = 2.2, WetLevel = -3 }, EqualizerSoundEffect = { LowGain = -10, MidGain = 0, HighGain = 4 } }
	local DRONE = { TremoloSoundEffect = { Depth = .5, Duty = .5, Frequency = 5 }, EqualizerSoundEffect = { LowGain = 6, MidGain = -4, HighGain = -20 }, ReverbSoundEffect = { DecayTime = 3, WetLevel = -4 } }
	local KITS = {}
	-- TOOTHY ALARM: a bright bell clang on every hit with the teeth clicking shut; a perfect is a quick double ding, a
	-- crit the full alarm (a trilling ring) and a chomp; the draw winds the key and gives a short ring; the inspect winds
	-- it, ticks, then RINGS and chatters; idle: a faint tick-tock.
	KITS.HW_UyAlarm = {
		Swing = { { HOP, .2, 1.1 }, whoosh(1.9, .2, .18, AIRY), { CLICK, .1, 1.6, nil, at = .02 }, { CLICK, .08, 1.3, nil, at = .09 } },
		Hit = { { SHEATH, .3, 1.5, BELL }, { KNOCK, .22, 1.05, SOFT }, { PING, .12, 1.9, BELL, at = .01, dur = .35, fade = .25 }, { CLICK, .22, .8, BONE, at = .04 } },
		Perfect = { { PING, .12, 2.4, BELL, at = .05 }, { PING, .1, 2.85, BELL, at = .11 } },
		Crit = { { SHEATH, .34, 1.2, BELL }, { KNOCK, .22, .95, SOFT }, { PING, .18, 2.2, RINGER, at = .02, dur = .6, fade = .2, loop = true },
			{ CLICK, .28, .7, CRUNCH, at = .06 }, { CLICK, .24, .75, BONE, at = .14 } },
		Draw = join(clicks(CLICK, 4, 1.4, .06, .12, 0), { { PING, .12, 2.2, RINGER, at = .3, dur = .35, fade = .15, loop = true } }),
		Break = { { SHEATH, .26, .9, BELL }, { CLICK, .2, .7, BONE, at = .05 }, { PING, .1, 1.6, BELL, at = .06 } },
		Inspect = join(clicks(CLICK, 10, 1.3, .09, .11, .2), clicks(TICK, 4, .95, .25, .08, 1.2, TICKTOCK),
			{ { PING, .2, 2.2, RINGER, at = 1.6, dur = .7, fade = .25, loop = true }, { CLICK, .22, .75, BONE, at = 1.65 }, { CLICK, .22, .8, BONE, at = 1.8 },
				{ CLICK, .22, .75, BONE, at = 1.95 }, { SHEATH, .2, 1.4, BELL, at = 2.3 } }),
		Idle = { { TICK, .012, 1.6, TICKTOCK, loop = true } },
		Run = { { CLICK, .04, 1.1, RATTLE, loop = true } },
	}
	-- BURIED HAND OF FATE: grave earth giving way under a glass "ting", sand hissing through the hourglass, bony
	-- knuckles; a crit tolls a far bell; the inspect creaks the fingers open, pours the sand and ticks the time away.
	KITS.HW_UyFate = {
		Swing = { { HOP, .2, .9 }, whoosh(1.4, .22, .26, AIRY), { WIND, .06, 3.2, SAND, at = .03, dur = .2, loop = true } },
		Hit = { { PING, .12, 2.6, GLASS, at = .01 }, { LAND, .24, .9, SOFT }, { WIND, .08, 3, SAND, at = .02, dur = .3, fade = .2, loop = true }, { CLICK, .14, .55, BONE, at = .04 } },
		Perfect = { { PING, .1, 3.1, GLASS, at = .05 }, { TICK, .1, 2.2, nil, at = .08 } },
		Crit = { { PING, .18, 1.7, GLASS, at = .02 }, { LAND, .26, .75, SOFT }, { WIND, .12, 2.4, SAND, dur = .7, fade = .3, loop = true },
			{ PING, .16, .6, TOLL, at = .1 }, { CLICK, .22, .5, CRUNCH, at = .05 } },
		Draw = { { WIND, .07, 2.8, SAND, dur = .5, attack = .1, fade = .25, loop = true }, { CLICK, .16, .6, BONE, at = .05 }, { CLICK, .14, .7, BONE, at = .14 },
			{ PING, .1, 2.6, GLASS, at = .35 } },
		Break = { { WIND, .08, 2.6, SAND, at = .03, dur = .45, loop = true }, { LAND, .22, .7, SOFT } },
		Inspect = join({ { TICK, .12, .3, CREAK, dur = .8, attack = .1, fade = .3, loop = true } }, clicks(CLICK, 4, .6, .1, .14, .4, BONE),
			{ { WIND, .08, 3, SAND, at = .9, dur = 1, attack = .2, fade = .4, loop = true } }, clicks(TICK, 4, 2.1, .25, .1, 1.1),
			{ { PING, .16, .5, TOLL, at = 2.2 }, { PING, .1, 2.6, GLASS, at = 2.25 } }),
		Idle = { { WIND, .008, 3, SAND, loop = true } },
		Run = { { WIND, .03, 2.4, SAND, loop = true } },
	}
	-- FUNERAL LAUGHSAW: a whirring saw bite with a little circus honk; a perfect honks twice, a crit screams and
	-- giggles; the draw revs it up; the inspect revs, giggles and plays three organ notes of a funeral march.
	KITS.HW_UySaw = {
		Swing = { { SLASH, .26, 1.1, AIRY }, whoosh(2.2, .18, .2, AIRY), { TICK, .08, 3.2, BUZZ, dur = .25, loop = true } },
		Hit = { { TICK, .2, 3.6, BUZZ, dur = .18, fade = .08, loop = true }, { KNOCK, .2, 1.2, SOFT }, { SHEATH, .18, 1.6, RING }, { PING, .1, 1.2, HONK, at = .03, dur = .12 } },
		Perfect = { { PING, .12, 1.9, HONK, at = .05, dur = .1 }, { PING, .1, 2.4, HONK, at = .12, dur = .1 } },
		Crit = join({ { TICK, .24, 3.2, BUZZ, dur = .4, fade = .15, loop = true }, { KNOCK, .22, 1, SOFT }, { SHEATH, .26, 1.2, RING } }, glides(5, 1.1, .1, .14, .1, LAUGH)),
		Draw = { { TICK, .12, 2.4, BUZZ, dur = .5, attack = .15, fade = .1, loop = true, to = 3.6, ramp = .4 }, { PING, .1, 1.5, HONK, at = .45, dur = .12 } },
		Break = join({ { SHEATH, .2, 1.1, RING } }, glides(3, 1, .09, .1, .04, LAUGH)),
		Inspect = join({ { TICK, .1, 2.2, BUZZ, dur = 1.3, attack = .3, fade = .2, loop = true, to = 4, ramp = 1 } }, glides(4, .9, .18, .14, 1.0, LAUGH),
			{ { PING, .12, 1, HONK, at = 1.8, dur = .15 }, { PING, .12, 1.26, HONK, at = 1.95, dur = .15 }, { PING, .12, 1.5, HONK, at = 2.1, dur = .25 } }),
		Idle = { { TICK, .01, 2.6, BUZZ, loop = true } },
		Run = { { TICK, .03, 3, BUZZ, loop = true } },
	}
	-- STATIC TV-HEAD: a burst of static and a hollow CRT knock with a thin whine; a perfect clicks the channel, a crit
	-- floods with static and the whine drops; the draw powers on (a rising whine, a pop); the inspect zaps through the
	-- channels and settles on the one that watches you.
	KITS.HW_UyTV = {
		Swing = { { HOP, .2, .85 }, whoosh(1.3, .22, .28), { WIND, .07, 2.4, STATIC, at = .02, dur = .22, loop = true } },
		Hit = { { WIND, .16, 2.2, STATIC, dur = .2, fade = .1, loop = true }, { LAND, .24, .85, SOFT }, { CLICK, .2, 1.1, nil, at = .02 }, { PING, .05, 3.6, WHINE, at = .01, dur = .2, loop = true } },
		Perfect = { { CLICK, .16, 1.5, nil, at = .05 }, { PING, .08, 3.2, WHINE, at = .06, dur = .12 } },
		Crit = { { WIND, .24, 1.8, STATIC, dur = .55, fade = .25, loop = true }, { LAND, .26, .7, SOFT }, { CLICK, .24, .9, CRUNCH, at = .04 },
			{ PING, .1, 3.8, WHINE, at = .05, dur = .5, loop = true, to = 1.2, ramp = .45 } },
		Draw = { { PING, .08, 4, WHINE, dur = .35, loop = true, to = 2, ramp = .3 }, { WIND, .1, 2.6, STATIC, at = .05, dur = .4, fade = .2, loop = true }, { CLICK, .18, 1.2, nil, at = .4 } },
		Break = { { WIND, .16, 1.6, STATIC, dur = .4, loop = true }, { CLICK, .2, .8, nil, at = .03 } },
		Inspect = join({ { WIND, .07, 2.4, STATIC, dur = 2.2, attack = .3, fade = .4, loop = true } }, clicks(CLICK, 3, 1.3, .3, .18, .5),
			{ { PING, .08, 3.6, WHINE, at = 1.3, dur = .6, loop = true }, { CLICK, .2, .9, nil, at = 2.2 }, { WIND, .12, 1.8, STATIC, at = 2.25, dur = .3, loop = true } }),
		Idle = { { WIND, .01, 2.4, STATIC, loop = true } },
		Run = { { CLICK, .04, 1.3, RATTLE, loop = true } },
	}
	-- MARSH OCTOPUS: a wet tentacle slap into bog water with a bubble "blub"; a perfect blubs twice, a crit is a big
	-- splorch and a string of bubbles; the draw slurps; the inspect gurgles and blows bubbles; idle: a slow bog trickle.
	KITS.HW_UyOcto = {
		Swing = { { SPLAT, .12, 1.3 }, whoosh(1.5, .22, .24), { WATER, .05, 1.6, BOG, at = .04 } },
		Hit = { { SPLAT, .32, .8, BOG }, { KNOCK, .2, 1.1, SOFT }, { WATER, .12, .8, BOG, at = .02 }, { PING, .08, .7, BLUB, at = .05, to = 1.1, ramp = .08, dur = .12 } },
		Perfect = { { PING, .1, .8, BLUB, at = .05, to = 1.3, ramp = .1, dur = .14 }, { PING, .08, 1, BLUB, at = .13, to = 1.6, ramp = .1, dur = .12 } },
		Crit = join({ { SPLAT, .4, .6, GOO }, { LAND, .24, .8, SOFT }, { WATER, .2, .6, BOG, at = .03 } }, glides(3, .8, .09, .1, .1, BLUB, 1.5)),
		Draw = { { SPLAT, .18, 1 }, { WATER, .1, 1.1, BOG, at = .06 }, { PING, .08, .9, BLUB, at = .2, to = 1.4, ramp = .1, dur = .14 } },
		Break = { { SPLAT, .3, .65, GOO }, { WATER, .14, .7, BOG, at = .04 } },
		Inspect = join({ { WATER, .1, .7, BOG, at = .2 }, { SPLAT, .16, .9, GOO, at = .45 } }, glides(5, .75, .2, .1, .7, BLUB, 1.5),
			{ { SPLAT, .22, .75, BOG, at = 2.0 }, { WATER, .14, .9, BOG, at = 2.05 } }),
		Idle = { { WATER, .008, .6, BOG, loop = true } },
		Run = { { WATER, .03, 1, BOG, loop = true } },
	}
	-- GUMMY HORROR: a squishy jelly bite that wobbles back (a gliding "boing"), sugar crunching; a perfect boings up, a
	-- crit is a big gloopy squelch; the draw jiggles; the inspect chomps, wobbles and crunches its sugar.
	KITS.HW_UyGummy = {
		Swing = { { HOP, .2, 1.5 }, whoosh(2, .18, .2, AIRY), { PING, .05, 1.2, WOBBLE, dur = .2, loop = true, to = 1.8, ramp = .2 } },
		Hit = { { SPLAT, .3, 1.15, SQUISH }, { KNOCK, .18, 1.3, SOFT }, { PING, .08, .9, WOBBLE, at = .02, to = 1.5, ramp = .12, dur = .2, loop = true }, { CLICK, .1, 2.4, nil, at = .04 } },
		Perfect = { { HOP, .14, 2.2, nil, at = .04 }, { PING, .08, 1.6, WOBBLE, at = .06, to = 2.4, ramp = .15, dur = .2, loop = true } },
		Crit = { { SPLAT, .42, .8, GOO }, { LAND, .22, 1.1, SOFT }, { PING, .14, .7, WOBBLE, dur = .5, to = 1.6, ramp = .4, loop = true },
			{ CLICK, .18, 2, CRUNCH, at = .05 }, { SPLAT, .16, 1.4, nil, at = .12 } },
		Draw = { { SPLAT, .16, 1.3 }, { HOP, .12, 1.9, nil, at = .05 }, { PING, .08, 1.1, WOBBLE, at = .1, to = 1.8, ramp = .2, dur = .25, loop = true } },
		Break = { { SPLAT, .3, .9, GOO }, { CLICK, .12, 2.2, CRUNCH, at = .05 } },
		Inspect = join({ { PING, .07, .8, WOBBLE, dur = 1.2, attack = .2, fade = .3, loop = true, to = 1.4, ramp = 1 } },
			{ { SPLAT, .2, 1.1, SQUISH, at = .5 }, { SPLAT, .2, 1.2, SQUISH, at = .75 }, { SPLAT, .2, 1.05, SQUISH, at = 1.0 } }, clicks(CLICK, 6, 2.2, .06, .1, 1.4, CRUNCH),
			{ { HOP, .16, 2.4, nil, at = 2.1 }, { PING, .1, 1.4, WOBBLE, at = 2.15, to = 2.6, ramp = .2, dur = .3, loop = true } }),
		Idle = { { SPLAT, .006, .6, GOO, loop = true } },
		Run = { { SPLAT, .02, 1.4, SQUISH, loop = true } },
	}
	-- BELL REAPER: every cut tolls a deep black bell under a ringing steel shing and a moon shimmer; a perfect tolls a
	-- higher bell, a crit tolls low with a choir; the draw rises out of a drone; the inspect tolls three times, rising,
	-- while the choir swells; idle: a low drone and a far choir.
	KITS.HW_UyBell = {
		Swing = { { SLASH, .3, .9, AIRY }, whoosh(1.3, .24, .3, AIRY), { PING, .05, 1.1, CHOIR, to = 1.5, ramp = .2, dur = .3, loop = true } },
		Hit = { { PING, .16, .5, TOLL }, { LAND, .2, .8, SOFT }, { SHEATH, .26, .8, RING, at = .01 }, { PING, .08, 2.4, SHINE, at = .03 } },
		Perfect = { { PING, .12, 1, TOLL, at = .05 }, { PING, .08, 3, SHINE, at = .1 } },
		Crit = { { PING, .24, .4, TOLL }, { LAND, .24, .6, SOFT }, { SHEATH, .32, .65, RING }, { PING, .14, .9, CHOIR, at = .12, dur = 1.1, fade = .5, loop = true },
			{ PING, .1, 2.6, SHINE, at = .2 } },
		Draw = { { PING, .14, .45, TOLL }, { WIND, .07, .5, DRONE, at = .1, dur = .8, attack = .3, fade = .3, loop = true }, { SHEATH, .2, .9, RING, at = .25 } },
		Break = { { PING, .18, .42, TOLL }, { PING, .1, 1.2, CHOIR, at = .06, dur = .6, loop = true } },
		Inspect = { { WIND, .08, .4, DRONE, dur = 2.4, attack = .5, fade = .5, loop = true }, { PING, .16, .42, TOLL, at = .4 }, { PING, .16, .5, TOLL, at = 1.1 },
			{ PING, .18, .6, TOLL, at = 1.8 }, { PING, .1, .94, CHOIR, at = .6, dur = 1.5, fade = .6, loop = true }, { PING, .1, 2.8, SHINE, at = 2.1 }, { SHEATH, .26, .8, RING, at = 2.3 } },
		Idle = { { WIND, .012, .4, DRONE, loop = true }, { PING, .003, .7, CHOIR, loop = true } },
		Run = { { WIND, .04, 1.6, AIRY, loop = true } },
	}
	return KITS
end

---------------------------------------------------------------------------------------------------------------------
-- PALETTES, CRIT STAMPS ([1] main glow: circles / trail start, [2] trail end, then accents)
---------------------------------------------------------------------------------------------------------------------
local C = Color3.fromRGB
S2.Palettes = {
	HW_UyAlarm = { C(120, 255, 140), C(230, 222, 200), C(206, 255, 214), C(150, 80, 230) },
	HW_UyFate = { C(150, 200, 255), C(206, 210, 196), C(232, 242, 255), C(170, 110, 255) },
	HW_UySaw = { C(150, 80, 230), C(236, 230, 218), C(255, 170, 80), C(168, 36, 60) },
	HW_UyTV = { C(196, 206, 255), C(150, 80, 230), C(244, 246, 255), C(120, 255, 140) },
	HW_UyOcto = { C(120, 255, 140), C(78, 146, 96), C(206, 255, 214), C(150, 80, 230) },
	HW_UyGummy = { C(190, 110, 255), C(120, 255, 140), C(255, 220, 250), C(255, 170, 80) },
	HW_UyBell = { C(170, 110, 255), C(232, 224, 204), C(246, 228, 255), C(46, 34, 66) },
}
S2.CritText = {
	HW_UyAlarm = { 'WAKE UP!', 'ПОДЪЁМ!' },
	HW_UyFate = { 'FATE!', 'СУДЬБА!' },
	HW_UySaw = { 'HEE-HEE!', 'ХИ-ХИ!' },
	HW_UyTV = { 'STATIC!', 'ПОМЕХИ!' },
	HW_UyOcto = { 'SPLORCH!', 'ХЛЮП!' },
	HW_UyGummy = { 'GLORP!', 'ШЛЁП!' },
	HW_UyBell = { 'TOLLED!', 'ПРОЗВОНИЛ!' },
}

---------------------------------------------------------------------------------------------------------------------
-- HIT THEMES (client; world hit FX through the MiningClient FX / PickFX public primitives)
---------------------------------------------------------------------------------------------------------------------
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
	local function fxPart(name, color, size, cf, transparency, shape)
		local p = Instance.new('Part')
		p.Name = name
		if shape then p.Shape = shape end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = NE
		p.Color = color
		p.Transparency = transparency or .2
		p.Size = size
		p.CFrame = cf
		p.Parent = folder()
		return p
	end
	-- a glowing ball that swells and fades (impact flash)
	local function shock(pos, color, size, life)
		local p = fxPart('HwShock', color, V3(.5, .5, .5), CF(pos), .45, Enum.PartType.Ball)
		TweenService:Create(p, TweenInfo.new(life or .3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(1, 1, 1) * (size or 5), Transparency = 1 }):Play()
		Debris:AddItem(p, (life or .3) + .05)
	end
	-- a soft rising wisp / bubble on a wobbling path, fading out
	local function wisp(pos, color, size, rise, life)
		local p = fxPart('HwWisp', color, V3(size, size, size), CF(pos), .2, Enum.PartType.Ball)
		local goal = pos + V3((math.random() - .5) * 2, rise, (math.random() - .5) * 2)
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = CF(goal), Size = V3(size, size, size) * .4, Transparency = 1 }):Play()
		Debris:AddItem(p, life + .05)
	end
	-- a neon streak from a to b that flashes and thins out
	local function streak(a, b, width, color, life)
		local len = (b - a).Magnitude
		if len < .01 then
			return
		end
		local p = fxPart('HwStreak', color, V3(width, width, len), CFrame.lookAt((a + b) / 2, b), 0)
		TweenService:Create(p, TweenInfo.new(life or .25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = V3(width * .2, width * .2, len) }):Play()
		Debris:AddItem(p, (life or .25) + .05)
	end
	-- an arc in the plane facing the camera (moon cuts, saw sweeps), from angle a0 to a1 (degrees)
	local function arc(pos, color, radius, a0, a1, width, life)
		local cam = workspace.CurrentCamera
		local f = cam and CFrame.lookAt(pos, cam.CFrame.Position) or CF(pos)
		local prev
		local steps = 9
		for i = 0, steps do
			local a = math.rad(a0 + (a1 - a0) * i / steps)
			local q = (f * CF(math.cos(a) * radius, math.sin(a) * radius, 0)).Position
			if prev then
				streak(prev, q, width * (.35 + .65 * math.sin(i / steps * math.pi)), color, life or .3)
			end
			prev = q
		end
	end
	-- static: flat neon pixels popping round the impact (TV)
	local function pixels(pos, colors, count, spread, life)
		for _ = 1, n(count) do
			local q = pos + V3((math.random() - .5) * spread, (math.random() - .2) * spread, (math.random() - .5) * spread)
			local s = .14 + math.random() * .16
			local p = fxPart('HwPixel', colors[math.random(1, #colors)], V3(s, s, .04), CFrame.lookAt(q, q + V3(math.random() - .5, 0, math.random() - .5)), .1)
			TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), { Transparency = 1, CFrame = p.CFrame * CF(0, .6 + math.random(), 0) }):Play()
			Debris:AddItem(p, life + .05)
		end
	end
	local HIT = {}
	-- TOOTHY ALARM: a bone flash, green sparks, broken teeth and brass cogs, two ringing sound waves
	HIT.HW_UyAlarm = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyAlarm
		shock(pos, c[2], crit and 6 or 3.4, .2)
		FX.Burst(pos, { Color = c[1], Color2 = c[3], Count = n(crit and 22 or 11), Speed = NumberRange.new(7, 14), Direction = dir, LightEmission = 1 })
		bits(pos, { c[2], C(250, 246, 236) }, crit and 8 or 4, .12, 13, SP, nil, { Up = .8, Life = .6 })
		bits(pos, { C(132, 106, 66), C(170, 140, 90) }, crit and 6 or 3, .18, 12, ME, Enum.PartType.Cylinder, { Flat = true, Up = .7, Life = .6 })
		FX.Ring(pos, c[1], crit and 8 or 4.5, .3)
		FX.Ring(pos + V3(0, .15, 0), c[3], crit and 11 or 6.5, .45)
		if not remote then
			for i = 1, n(crit and 6 or 3) do
				local a = (i / 6) * math.pi * 2 + math.random()
				streak(pos + V3(math.cos(a), .3, math.sin(a)) * .6, pos + V3(math.cos(a) * 1.9, .6 + math.random() * .6, math.sin(a) * 1.9), .08, c[1], .22)
			end
		end
		if crit then
			shock(pos, c[1], 8.5, .3)
			glyph(pos + V3(0, 1.8, 0), 'WAKE UP!', 'ПОДЪЁМ!', c[1], 76, V3(0, 1, 0), 1.1)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'ding', 'дзынь', c[3], 26, V3(0, 1, 0), .6)
		end
	end
	-- BURIED HAND OF FATE: a moon-blue flash, a spray of glowing sand that rains back down, grave dirt, rising wisps
	HIT.HW_UyFate = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyFate
		shock(pos, c[3], crit and 6 or 3.4, .22)
		FX.Burst(pos, { Color = c[1], Color2 = c[4], Count = n(crit and 26 or 13), Speed = NumberRange.new(5, 11), Direction = dir, LightEmission = 1,
			Acceleration = V3(0, -18, 0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .22), NumberSequenceKeypoint.new(1, 0) }) })
		bits(pos, { c[1], c[4], C(220, 230, 255) }, crit and 12 or 6, .09, 10, NE, nil, { Up = .9, Life = .7 })
		bits(pos, { C(86, 62, 42), C(110, 84, 58) }, crit and 7 or 4, .22, 12, Enum.Material.Ground, nil, { Up = .6, Life = .55 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if not remote then
			for _ = 1, n(crit and 5 or 2) do
				wisp(pos + V3(math.random() - .5, .2, math.random() - .5), c[1]:Lerp(WHITE, .3), .36, 2.6 + math.random() * 2, 1 + math.random() * .4)
			end
		end
		if crit then
			FX.Ring(pos, c[4], 12, .45)
			shock(pos, c[1], 8.5, .32)
			glyph(pos + V3(0, 1.8, 0), 'FATE!', 'СУДЬБА!', c[1], 78, V3(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'tock', 'так', c[3], 26, V3(0, 1, 0), .6)
		end
	end
	-- FUNERAL LAUGHSAW: a violet flash, sparks screaming off sideways, black / white / red confetti, a saw sweep
	HIT.HW_UySaw = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UySaw
		shock(pos, c[1], crit and 6 or 3.4, .2)
		FX.Burst(pos, { Color = c[3], Color2 = WHITE, Count = n(crit and 26 or 13), Speed = NumberRange.new(12, 22), Direction = dir, LightEmission = 1, Spread = Vector2.new(85, 20) })
		bits(pos, { C(24, 20, 30), C(236, 230, 218), c[4], c[1] }, crit and 14 or 7, .2, 14, SP, nil, { Flat = true, Up = .9, Life = .8 })
		FX.Ring(pos, c[1], crit and 8 or 4.5, .3)
		if not remote then
			local tilt = math.random(-30, 30)
			arc(pos, c[3], 1.6, 200 + tilt, 340 + tilt, .16, .28)
			for i = 1, n(crit and 7 or 3) do
				local a = math.random() * math.pi * 2
				local d = V3(math.cos(a), .3 + math.random() * .4, math.sin(a))
				streak(pos + d * .3, pos + d * (1.6 + math.random() * 1.2), .07, i % 2 == 0 and c[3] or WHITE, .2)
			end
		end
		if crit then
			FX.Ring(pos, c[3], 11, .45)
			shock(pos, c[3], 8.5, .3)
			glyph(pos + V3(0, 1.8, 0), 'HEE-HEE!', 'ХИ-ХИ!', c[1], 78, V3(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'zing', 'вжик', c[3], 26, V3(0, 1, 0), .6)
		end
	end
	-- STATIC TV-HEAD: a white flash, static pixels popping, a scan-line streak, violet / green sparks
	HIT.HW_UyTV = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyTV
		shock(pos, c[3], crit and 6 or 3.4, .18)
		FX.Burst(pos, { Color = c[1], Color2 = c[2], Count = n(crit and 20 or 10), Speed = NumberRange.new(7, 13), Direction = dir, LightEmission = 1 })
		bits(pos, { C(86, 58, 42), C(120, 84, 60) }, crit and 6 or 3, .2, 12, WO, nil, { Flat = true, Up = .6, Life = .55 })
		FX.Ring(pos, c[1], crit and 8 or 4.5, .28)
		if not remote then
			pixels(pos, { c[3], c[1], c[2], C(130, 130, 140), c[4] }, crit and 14 or 7, crit and 3 or 2, .45)
			local cam = workspace.CurrentCamera
			local right = cam and cam.CFrame.RightVector or V3(1, 0, 0)
			streak(pos - right * (crit and 2.4 or 1.4) + V3(0, .4, 0), pos + right * (crit and 2.4 or 1.4) + V3(0, .4, 0), .06, c[3], .25)
		end
		if crit then
			shock(pos, c[2], 8, .3)
			FX.Ring(pos, c[2], 11, .42)
			glyph(pos + V3(0, 1.8, 0), 'STATIC!', 'ПОМЕХИ!', c[3], 76, V3(0, 1, 0), 1.1)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'bzzt', 'бззт', c[1], 26, V3(0, 1, 0), .6)
		end
	end
	-- MARSH OCTOPUS: a bog-water splash, green goo, rising bubbles, a ring of glowing spots
	HIT.HW_UyOcto = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyOcto
		shock(pos, c[1], crit and 6 or 3.4, .22)
		FX.Burst(pos, { Texture = SMOKE_TEX, Color = c[2], Count = n(crit and 6 or 3), Speed = NumberRange.new(2, 5), LightEmission = 0, Acceleration = V3(0, 1, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .9), NumberSequenceKeypoint.new(1, 2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .4), NumberSequenceKeypoint.new(1, 1) }) })
		FX.Burst(pos, { Color = c[1], Color2 = c[3], Count = n(crit and 22 or 11), Speed = NumberRange.new(6, 13), Direction = dir, LightEmission = .9 })
		bits(pos, { c[2], C(60, 110, 70), C(110, 170, 120) }, crit and 12 or 6, .22, 13, GL, Enum.PartType.Ball, { Up = .8, Life = .65, Transparency = .3 })
		bits(pos, { c[4] }, crit and 4 or 2, .12, 10, NE, Enum.PartType.Ball, { Up = .9, Life = .6 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if not remote then
			for _ = 1, n(crit and 6 or 3) do
				wisp(pos + V3((math.random() - .5) * 1.2, 0, (math.random() - .5) * 1.2), c[3], .22 + math.random() * .18, 2 + math.random() * 1.5, .9 + math.random() * .5)
			end
		end
		if crit then
			FX.Ring(pos, c[4], 12, .45)
			shock(pos, c[2], 9, .32)
			glyph(pos + V3(0, 1.8, 0), 'SPLORCH!', 'ХЛЮП!', c[1], 78, V3(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'blub', 'бульк', c[3], 26, V3(0, 1, 0), .6)
		end
	end
	-- GUMMY HORROR: a violet flash, chunks of translucent jelly in three flavours, sugar sparkles
	HIT.HW_UyGummy = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyGummy
		shock(pos, c[1], crit and 6.5 or 3.6, .22)
		FX.Burst(pos, { Color = c[3], Color2 = c[1], Count = n(crit and 22 or 11), Speed = NumberRange.new(6, 12), Direction = dir, LightEmission = 1 })
		bits(pos, { c[1], c[2], c[4] }, crit and 12 or 6, .26, 14, GL, nil, { Up = .8, Life = .7, Transparency = .25 })
		bits(pos, { WHITE, c[3] }, crit and 8 or 4, .08, 11, NE, nil, { Up = 1, Life = .55 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		if not remote and crit then
			for i = 1, n(5) do
				local a = (i / 5) * math.pi * 2
				streak(pos, pos + V3(math.cos(a) * 2.2, .5 + math.random(), math.sin(a) * 2.2), .12, i % 2 == 0 and c[2] or c[4], .3)
			end
		end
		if crit then
			FX.Ring(pos, c[2], 12, .45)
			shock(pos, c[2], 9, .32)
			glyph(pos + V3(0, 1.8, 0), 'GLORP!', 'ШЛЁП!', c[1], 78, V3(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'boing', 'боинг', c[3], 26, V3(0, 1, 0), .6)
		end
	end
	-- BELL REAPER: a violet toll, rings of sound washing out, a crescent-moon cut, souls rising
	HIT.HW_UyBell = function(pos, dir, q, crit, remote)
		local c = S2.Palettes.HW_UyBell
		shock(pos, c[3], crit and 7 or 3.8, .24)
		FX.Burst(pos, { Color = c[1], Color2 = c[3], Count = n(crit and 24 or 12), Speed = NumberRange.new(7, 14), Direction = dir, LightEmission = 1 })
		bits(pos, { C(46, 34, 66), C(30, 24, 40) }, crit and 7 or 4, .24, 14, SL, nil, { Up = .5, Life = .6 })
		bits(pos, { c[1], c[3] }, crit and 8 or 4, .12, 12, NE, nil, { Up = .9, Life = .6 })
		FX.Ring(pos, c[1], crit and 9 or 5, .32)
		FX.Ring(pos + V3(0, .2, 0), c[3], crit and 13 or 7, .5)
		if not remote then
			local tilt = math.random(-25, 10)
			arc(pos, c[1], 2.1, 110 + tilt, 250 + tilt, .26, .34)
			arc(pos + V3(.1, .05, 0), c[3], 1.75, 125 + tilt, 235 + tilt, .12, .3)
			for _ = 1, n(crit and 6 or 2) do
				wisp(pos + V3(math.random() - .5, .3, math.random() - .5), c[3]:Lerp(c[1], math.random() * .5), .32, 3 + math.random() * 2.5, 1 + math.random() * .5)
			end
		end
		if crit then
			FX.Ring(pos, c[2], 16, .6)
			shock(pos, c[1], 10, .35)
			glyph(pos + V3(0, 1.8, 0), 'TOLLED!', 'ПРОЗВОНИЛ!', c[3], 78, V3(0, 1, 0), 1.2)
		elseif q == 2 and not remote then
			glyph(pos + V3(0, .8, 0), 'dong', 'дон', c[3], 26, V3(0, 1, 0), .7)
		end
	end
	return HIT
end

---------------------------------------------------------------------------------------------------------------------
-- LIVING STATE MACHINES (client; specs in PickaxeSkins' liveFX format: run by PickFX every animated frame after the
-- generic motions; lights breathe and flare, emitters busier on a run / inspect, extra motion through api.push, DRAW /
-- INSPECT / FINALE / MOOD / IDLE / RUN / HIT hooks). World effects only for held models near the camera, nothing with
-- Reduced Motion, fewer bits on Low FX (api.n). Subtle by design: the hit themes carry the big moments.
---------------------------------------------------------------------------------------------------------------------
local liveCtx = nil -- the MiningClient ctx (FX.Ring for the live hooks); set when the hit themes register
local function seq(a, b, c)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(.5, b), ColorSequenceKeypoint.new(1, c) })
end
-- A part's world position (nil when gone).
local function at(p, offset)
	if p and p.Parent then
		return offset and (p.CFrame * CF(offset)).Position or p.Position
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
-- the extra spin / bob of orbiting parts; squeeze pulls them in toward the pole
local function orbit(e, s, t, group, api, bob, squeeze)
	for _, p in ipairs(s.Moves[group] or {}) do
		local r = p.Base.Position - p.Joint.Position
		local radial = V3(r.X, 0, r.Z)
		local inward = radial.Magnitude > .01 and -radial.Unit * squeeze or V3(0, 0, 0)
		api.push(e, p, CFrame.Angles(0, s.Orb, 0) * CF(inward + V3(0, math.sin(t * 2.4 + p.Phase * 6.28) * bob, 0)))
	end
end
local function waves(pos, color, size, life)
	local fx = liveCtx and liveCtx.FX
	if fx and fx.Ring and pos then
		fx.Ring(pos, color, size, life)
	end
end
local function emit(s, count)
	for _, m in ipairs(s.Emitters) do
		if m.E.Parent then m.E:Emit(count) end
	end
end
local LIVE_SPECS = {}

-- TOOTHY ALARM: the eyes glow, the hour hand creeps (and races with the minute hand while it is wound in the inspect),
-- every few seconds it chatters its teeth; the strikers RING on the draw, a mood and the inspect's alarm (they hammer the
-- bells, the jaw clacks, sound waves roll off). DRAW: a green flash, a RING. INSPECT: the hands spin as the key winds,
-- then the alarm; finale: WAKE UP.
LIVE_SPECS.HW_UyToothyAlarm = {
	Theme = 'HW_UyAlarm', Focus = 'DialGlow', Flames = { CandleLight = .3 }, HitEmit = 3, InspRate = 2,
	RunTrail = seq(C(232, 255, 236), C(120, 255, 140), C(40, 90, 60)),
	Glow = { AlarmEye = .5, MawGlow = .5, CandleFlame = .4, HandPin = .4 },
	Tint = { CandleFlame = true }, Hot = C(255, 240, 190), Dim = C(230, 110, 30),
	Moves = { JawLip = 'Jaw', LowerFang = 'Jaw', HourHand = 'Hour', HourHandKnob = 'Hour', MinuteHand = 'Minute', MinuteHandKnob = 'Minute',
		Striker = 'Striker', StrikerArm = 'Striker' },
	MoodEvery = 6,
	IdleEvery = 3,
	Move = function(e, s, t, dt, h, ip, api)
		s.Wind = (s.Wind or 0) + dt * e.State.Insp * 9
		local hourA = CFrame.Angles(0, 0, -t * .075 - s.Wind * .25)
		for _, p in ipairs(s.Moves.Hour or {}) do api.push(e, p, hourA) end
		if s.Wind > 0 then
			local minA = CFrame.Angles(0, 0, -s.Wind)
			for _, p in ipairs(s.Moves.Minute or {}) do api.push(e, p, minA) end
		end
		if s.MoodAt then s.RingAt, s.RingLen = s.MoodAt, .45 end
		local ringing = env(t, s.RingAt, s.RingLen or .8, .02, .12)
		if ip > 1.45 and ip < 2.2 then ringing = 1 end
		if ringing > 0 then
			local a = CFrame.Angles(0, 0, math.sin(t * 70) * .25 * ringing)
			for _, p in ipairs(s.Moves.Striker or {}) do api.push(e, p, a) end
		end
		local chat = ringing > 0 and math.abs(math.sin(t * 30)) * .25 * ringing or ((ip > .5 and ip < 1.4) and math.abs(math.sin(ip * 20)) * .3 or 0)
		if chat > 0 then
			for _, p in ipairs(s.Moves.Jaw or {}) do api.push(e, p, CFrame.Angles(chat, 0, 0)) end
		end
		s.Lift = ringing * .3
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.RingAt, s.RingLen = t, .7
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus, V3(0, 0, .3))
		if p then
			api.shock(p, c[1], 3, .25)
			api.burst(p, c[1], c[3], 10, 5)
			waves(p, c[1], 5, .4)
			if s.Own then api.glyph(p + V3(0, 1.1, 0), 'RIIING!', 'ДЗЫНЬ!', c[1], 26, V3(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .3))
		if ip > .4 and not s.Fired.Wind then
			s.Fired.Wind = true
			if p and s.Own then api.glyph(p + V3(0, .9, 0), 'tick-tock', 'тик-так', c[3], 18, V3(0, 1, 0), .9) end
		end
		if ip > 1.5 and not s.Fired.Ring then
			s.Fired.Ring = true
			s.Boost = 1
			if p then
				waves(p, c[1], 6, .45)
				api.burst(p, c[1], c[3], 12, 6)
			end
			emit(s, 6)
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .3))
		if not p then return end
		s.RingAt, s.RingLen = t, .5
		api.shock(p, c[1], 3.6, .3)
		waves(p, c[3], 7, .5)
		api.glyph(p + V3(0, 1, 0), 'WAKE UP!', 'ПОДЪЁМ!', c[1], 32, V3(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, V3(0, 0, .3))
		if p then waves(p, s.Pal[1], 4, .35) end
	end,
	Idle = function(e, s, t, api)
		emit(s, 1)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .5, { s.Pal[2], C(132, 106, 66) }, 1, .08, 3, ME, nil, { Up = .3, Life = .45 }) end
	end,
	Hit = function(e, s, t, strength, api)
		if strength >= .88 then s.RingAt, s.RingLen = t, .3 end
	end,
}
-- BURIED HAND OF FATE: the sand glows and the ring's stone breathes; every strike the fingers squeeze the hourglass, now
-- and then they flex and a little sand trickles out. DRAW: a moon-blue flash, sand bursting out of the bulbs. INSPECT:
-- the fingers open (the hourglass shows), sand pours, they clench again; finale: FATE.
LIVE_SPECS.HW_UyFateHand = {
	Theme = 'HW_UyFate', Focus = 'SandGlow', HitEmit = 3, InspRate = 2.5,
	RunTrail = seq(C(236, 244, 255), C(150, 200, 255), C(110, 70, 200)),
	Glow = { SandHeap = .5, RingStone = .5, HammerMoon = .4, Sand = .25 },
	MovesByAnim = { Live = 'Fist' },
	MoodEvery = 6.5,
	IdleEvery = 2.8,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then s.FlexAt = s.MoodAt end
		s.Squeeze = math.max(0, (s.Squeeze or 0) - dt * 2.4)
		local open = 0
		if ip > .25 and ip < 1.7 then
			open = math.min(1, (ip - .25) / .3, (1.7 - ip) / .3)
		end
		local flex = env(t, s.FlexAt, 1.1, .3, .5)
		local curl = s.Squeeze * .14 - open * .55 - flex * .22 + math.sin(t * 1.3) * .015
		-- the fingers (phase .2 .. .8) curl round X at their knuckle; the thumb (phase .9) swings round Y
		local thumbA = CFrame.Angles(0, -open * .5 - s.Squeeze * .06, 0)
		for _, p in ipairs(s.Moves.Fist or {}) do
			if p.Phase > .85 then
				api.push(e, p, thumbA)
			else
				api.push(e, p, CFrame.Angles(curl + p.Phase * flex * .1, 0, 0))
			end
		end
		s.Lift = open * .3
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Squeeze = 1
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3, .25)
			api.burst(p, c[1], c[4], 12, 4, { Acceleration = V3(0, -10, 0) })
			if s.Own then api.glyph(p + V3(.8, 1, 0), 'tick... tock', 'тик... так', c[3], 20, V3(0, 1, 0), 1) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		if ip > .55 and not s.Fired.Pour then
			s.Fired.Pour = true
			emit(s, 8)
			local p = at(s.Focus)
			if p then api.bits(p, { c[1], c[4] }, 6, .07, 3, NE, nil, { Up = .2, Life = 1 }) end
		end
		if ip > 1.75 and not s.Fired.Clench then
			s.Fired.Clench = true
			s.Squeeze = 1
			s.Boost = 1
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus)
		if not p then return end
		s.Squeeze = 1
		api.shock(p, c[1], 3.6, .3)
		waves(p, c[1], 5, .45)
		api.glyph(p + V3(.8, 1, 0), 'FATE!', 'СУДЬБА!', c[1], 32, V3(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus)
		if p then api.bits(p - V3(0, .2, 0), { s.Pal[1], s.Pal[4] }, 3, .06, 2, NE, nil, { Up = .1, Life = .9 }) end
	end,
	Idle = function(e, s, t, api)
		emit(s, 1)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .5, { C(86, 62, 42), s.Pal[1] }, 1, .09, 3, Enum.Material.Ground, nil, { Up = .2, Life = .45 }) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Squeeze = math.max(s.Squeeze or 0, strength)
	end,
}

-- FUNERAL LAUGHSAW: the blade revs harder while running, through the inspect and after a strike; every few seconds the
-- grin cackles (the jaw chatters, the hat tips). DRAW: it revs up with a spray of sparks and a HEE-HEE. INSPECT: a long
-- rev, a laugh, a spray of confetti; finale: HA-HA-HA.
LIVE_SPECS.HW_UyLaughsaw = {
	Theme = 'HW_UySaw', Focus = 'GrinGlow', HitEmit = 4, InspRate = 3, RunRate = 2,
	RunTrail = seq(C(255, 240, 220), C(150, 80, 230), C(168, 36, 60)),
	Glow = { Tear = .5, NoseGlint = .3 },
	Moves = { BladeStripe = 'Disc', BladeRim = 'Disc', BladeRivetRing = 'Disc', BladeTooth = 'Disc', GrinLowerTooth = 'Jaw', GrinLip = 'Jaw',
		HatBrim = 'Hat', HatCrown = 'Hat', HatTop = 'Hat', HatBand = 'Hat', HatFlower = 'Hat', HatFlowerHeart = 'Hat', HatLeaf = 'Hat' },
	MoodEvery = 6,
	IdleEvery = 2.4,
	Move = function(e, s, t, dt, h, ip, api)
		local st = e.State
		s.Rev = (s.Rev or 0) + dt * (st.Insp * 14 + st.Run * 6 + s.Rush * 12)
		if s.Rev > 0 then
			local spin = CFrame.Angles(0, 0, -s.Rev)
			for _, p in ipairs(s.Moves.Disc or {}) do api.push(e, p, spin) end
		end
		if s.MoodAt then s.CackleAt, s.CackleLen = s.MoodAt, .6 + math.random() * .4 end
		local cackle = env(t, s.CackleAt, s.CackleLen or .8, .04, .15)
		if ip > .9 and ip < 1.6 then cackle = 1 end
		if cackle > 0 then
			local chat = math.abs(math.sin(t * 28)) * .4 * cackle
			for _, p in ipairs(s.Moves.Jaw or {}) do api.push(e, p, CFrame.Angles(chat, 0, 0)) end
			local tip = CFrame.Angles(0, 0, math.sin(t * 14) * .08 * cackle)
			for _, p in ipairs(s.Moves.Hat or {}) do api.push(e, p, tip) end
		end
		s.Lift = cackle * .3
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		s.CackleAt, s.CackleLen = t, .7
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus, V3(0, 0, .2))
		if p then
			api.shock(p, c[1], 3.2, .25)
			api.burst(p - V3(0, 1.1, 0), c[3], WHITE, 12, 8, { Acceleration = V3(0, -14, 0) })
			if s.Own then api.glyph(p + V3(0, 1.2, 0), 'HEE-HEE!', 'ХИ-ХИ!', c[1], 26, V3(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .2))
		if ip > 1.0 and not s.Fired.Laugh then
			s.Fired.Laugh = true
			if p and s.Own then api.glyph(p + V3(0, 1, 0), 'ha-ha', 'ха-ха', c[3], 20, V3(0, 1, 0), .9) end
		end
		if ip > 1.8 and not s.Fired.Confetti then
			s.Fired.Confetti = true
			if p then api.bits(p, { C(24, 20, 30), C(236, 230, 218), c[4], c[1] }, 10, .14, 7, SP, nil, { Flat = true, Up = .9, Life = .9 }) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .2))
		if not p then return end
		s.Rush = 1
		api.shock(p, c[1], 3.8, .3)
		api.bits(p, { C(24, 20, 30), C(236, 230, 218), c[4] }, 8, .14, 8, SP, nil, { Flat = true, Up = .9, Life = .9 })
		api.glyph(p + V3(0, 1.2, 0), 'HA-HA-HA!', 'ХА-ХА-ХА!', c[1], 32, V3(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, V3(0, .2, .2))
		if p and s.Own then api.glyph(p + V3(0, .9, 0), 'hee', 'хи', s.Pal[3], 16, V3(0, 1, 0), .8) end
	end,
	Idle = function(e, s, t, api)
		emit(s, 2)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .6, { C(24, 20, 30), C(236, 230, 218), s.Pal[4] }, 1, .1, 3, SP, nil, { Flat = true, Up = .4, Life = .5 }) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength)
	end,
}

-- STATIC TV-HEAD: the screen glow breathes, the candle flickers; every few seconds the picture ZAPS (the eyes and the grin
-- flicker bright, a pop of static). DRAW: it powers on (a white flash, a burst of static). INSPECT: three channel zaps,
-- then the eyes lock on you; finale: STAY TUNED.
LIVE_SPECS.HW_UyTVHead = {
	Theme = 'HW_UyTV', Focus = 'ScreenGlow', Flames = { CandleLight = .3 }, HitEmit = 3, InspRate = 2,
	RunTrail = seq(C(250, 250, 255), C(196, 206, 255), C(110, 60, 200)),
	Glow = { StaticEye = .5, SignalGrin = .6, CrestWindow = .4, PowerLamp = .4, TubeFilament = .4, EyeRing = .3 },
	Tint = { CandleFlame = true }, Hot = C(255, 240, 190), Dim = C(230, 110, 30),
	MoodEvery = 5.5,
	IdleEvery = 2.6,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then s.ZapAt = s.MoodAt end
		local zap = env(t, s.ZapAt, .45, .02, .1)
		for _, z in ipairs({ .5, .8, 1.1 }) do
			if ip > z and ip < z + .18 then zap = 1 end
		end
		s.Lift = zap > 0 and (math.random() < .5 and .6 or 0) or 0
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.ZapAt = t
		e.Hit = math.max(e.Hit, .7)
		local p = at(s.Focus, V3(0, 0, .3))
		if p then
			api.shock(p, c[3], 3.2, .2)
			api.bits(p, { c[3], c[1], c[2] }, 6, .12, 5, NE, nil, { Flat = true, Up = .6, Life = .5 })
			if s.Own then api.glyph(p + V3(0, 1.1, 0), 'bzzt!', 'бззт!', c[1], 24, V3(0, 1, 0), .8) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .3))
		for k, z in ipairs({ .5, .8, 1.1 }) do
			if ip > z and not s.Fired['Zap' .. k] then
				s.Fired['Zap' .. k] = true
				if p then api.bits(p, { c[3], c[1], c[2], c[4] }, 4, .1, 4, NE, nil, { Flat = true, Up = .5, Life = .4 }) end
			end
		end
		if ip > 1.6 and not s.Fired.Watch then
			s.Fired.Watch = true
			s.Boost = 1
			if p and s.Own then api.glyph(p + V3(0, 1, 0), 'I SEE YOU', 'Я ВИЖУ ТЕБЯ', c[3], 20, V3(0, 1, 0), 1.1) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus, V3(0, 0, .3))
		if not p then return end
		s.ZapAt = t
		api.shock(p, c[1], 3.6, .25)
		waves(p, c[2], 5, .4)
		api.glyph(p + V3(0, 1.1, 0), 'STAY TUNED', 'НЕ ПЕРЕКЛЮЧАЙ', c[3], 28, V3(0, 1, 0), 1.2)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, V3(0, 0, .3))
		if p then api.bits(p, { s.Pal[3], s.Pal[1] }, 2, .08, 3, NE, nil, { Flat = true, Up = .5, Life = .35 }) end
	end,
	Idle = function(e, s, t, api)
		emit(s, 1)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .7, { s.Pal[3], s.Pal[2] }, 1, .09, 3, NE, nil, { Flat = true, Up = .4, Life = .4 }) end
	end,
	Hit = function(e, s, t, strength, api)
		if strength >= .88 then s.ZapAt = t end
	end,
}

-- MARSH OCTOPUS: the spots and the eyes glow, the free arms writhe (much more through the inspect and after a strike),
-- now and then it blows bog bubbles out of its siphon. DRAW: a splash and a BLUB. INSPECT: the arms writhe, a stream of
-- bubbles, a wet slap; finale: SPLORCH.
LIVE_SPECS.HW_UyOctopus = {
	Theme = 'HW_UyOcto', Focus = 'BogGlow', HitEmit = 3, InspRate = 2.5,
	RunTrail = seq(C(220, 255, 226), C(120, 255, 140), C(60, 100, 70)),
	Glow = { MantleSpot = .5, OctoIris = .4, MarshFlower = .4, MarshPetal = .3 },
	MovesByAnim = { Tentacle = 'Arms', Curl = 'Climb' },
	MoodEvery = 6,
	IdleEvery = 2.6,
	Move = function(e, s, t, dt, h, ip, api)
		local k = e.State.Insp * .2 + s.Rush * .14 + e.State.Run * .06
		if k > .002 then
			for _, p in ipairs(s.Moves.Arms or {}) do
				api.push(e, p, CFrame.Angles(math.sin(t * 3.3 + p.Phase) * k, 0, math.cos(t * 2.7 + p.Phase) * k))
			end
			for _, p in ipairs(s.Moves.Climb or {}) do
				api.push(e, p, CFrame.Angles(math.sin(t * 4 + p.Phase) * k * 1.5, 0, 0))
			end
		end
		if s.MoodAt then s.BlubAt = s.MoodAt end
		s.Lift = env(t, s.BlubAt, .8, .1, .4) * .3
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3, .25)
			api.burst(p, c[1], c[3], 10, 5)
			api.bits(p, { c[2], C(60, 110, 70) }, 4, .14, 5, GL, Enum.PartType.Ball, { Up = .7, Life = .6, Transparency = .3 })
			if s.Own then api.glyph(p + V3(0, 1.1, 0), 'BLUB!', 'БУЛЬК!', c[1], 26, V3(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus)
		if ip > .7 and not s.Fired.Bubbles then
			s.Fired.Bubbles = true
			if p then
				for k = 1, api.n(5) do api.wisp(p + V3((k - 3) * .15, .3, .4), c[3], .14 + k * .02, 2 + k * .3, 1.4) end
			end
		end
		if ip > 1.9 and not s.Fired.Slap then
			s.Fired.Slap = true
			s.Rush = 1
			if p and s.Own then api.glyph(p + V3(0, 1, 0), 'blub-blub', 'буль-буль', c[3], 18, V3(0, 1, 0), .9) end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus)
		if not p then return end
		s.Rush = 1
		api.shock(p, c[1], 3.6, .3)
		api.bits(p, { c[2], C(60, 110, 70), c[4] }, 6, .16, 6, GL, Enum.PartType.Ball, { Up = .8, Life = .7, Transparency = .3 })
		api.glyph(p + V3(0, 1.1, 0), 'SPLORCH!', 'ХЛЮП!', c[1], 32, V3(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus, V3(-.7, -.3, .2))
		if p then
			for k = 1, api.n(3) do api.wisp(p + V3(-.1 * k, .05 * k, 0), s.Pal[3], .1 + k * .03, 1.6 + k * .4, 1.3) end
		end
	end,
	Idle = function(e, s, t, api)
		emit(s, 1)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .5, { s.Pal[2], C(110, 170, 120) }, 1, .09, 3, GL, Enum.PartType.Ball, { Up = .3, Life = .45, Transparency = .3 }) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength)
	end,
}

-- GUMMY HORROR: the jawbreaker brain glows, the skull jiggles harder after a strike and on a run; every few seconds it
-- chomps. DRAW: a jelly splash and a BOING. INSPECT: nom, nom, a sugar sparkle; finale: GLORP.
LIVE_SPECS.HW_UyGummyHorror = {
	Theme = 'HW_UyGummy', Focus = 'CoreGlow', HitEmit = 3, InspRate = 2,
	RunTrail = seq(C(255, 230, 255), C(190, 110, 255), C(120, 255, 140)),
	Glow = { JawbreakerCore = .4, CandyIris = .4 },
	MovesByAnim = { GummyJaw = 'Jaw', GummyWobble = 'Skull' },
	MoodEvery = 5,
	IdleEvery = 2.5,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then s.ChompAt, s.ChompLen = s.MoodAt, .5 + math.random() * .4 end
		local chomp = 0
		if env(t, s.ChompAt, s.ChompLen or 0, .02, .05) > 0 then
			chomp = math.max(0, math.sin((t - s.ChompAt) * 16)) * .35
		elseif ip > .45 and ip < 1.3 then
			chomp = math.max(0, math.sin(ip * 15)) * .4
		end
		if chomp > .001 then
			for _, p in ipairs(s.Moves.Jaw or {}) do api.push(e, p, CFrame.Angles(chomp, 0, 0)) end
		end
		local jig = s.Rush * .05 + e.State.Run * .02
		if jig > .001 then
			local off = CF(math.sin(t * 29) * jig, math.sin(t * 23) * jig * 1.4, 0)
			for _, p in ipairs(s.Moves.Skull or {}) do api.push(e, p, off) end
		end
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.Rush = 1
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3, .25)
			api.bits(p, { c[1], c[2], c[4] }, 5, .16, 6, GL, nil, { Up = .8, Life = .6, Transparency = .25 })
			if s.Own then api.glyph(p + V3(0, 1.1, 0), 'BOING!', 'БОИНГ!', c[3], 26, V3(0, 1, 0), .9) end
		end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus)
		for k, z in ipairs({ .6, 1.0 }) do
			if ip > z and not s.Fired['Nom' .. k] then
				s.Fired['Nom' .. k] = true
				if p and s.Own then api.glyph(p + V3((k - 1.5) * .6, .9, .3), 'nom', 'ням', c[3], 18, V3(0, 1, 0), .7) end
			end
		end
		if ip > 1.5 and not s.Fired.Sugar then
			s.Fired.Sugar = true
			emit(s, 10)
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus)
		if not p then return end
		s.Rush = 1
		api.shock(p, c[1], 3.6, .3)
		api.bits(p, { c[1], c[2], c[4] }, 7, .18, 7, GL, nil, { Up = .8, Life = .7, Transparency = .25 })
		api.glyph(p + V3(0, 1.1, 0), 'GLORP!', 'ШЛЁП!', c[1], 32, V3(0, 1, 0), 1.1)
	end,
	Mood = function(e, s, t, api)
		emit(s, 2)
	end,
	Idle = function(e, s, t, api)
		emit(s, 1)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.bits(p - flat.Unit * .5 - V3(0, .5, 0), { s.Pal[1], s.Pal[2], s.Pal[4] }, 1, .1, 3, GL, nil, { Up = .3, Life = .5, Transparency = .25 }) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength)
	end,
}

-- BELL REAPER: the moon glows, the ghost bells circle (they race through the inspect and after a strike, drawn in close),
-- and every few seconds the black bell TOLLS on its own (the clapper strikes, the runes and the crack flare, a ring of
-- sound rolls off). DRAW: a toll, a violet crescent off the moon's point. INSPECT: three tolls; finale: TOLLED.
LIVE_SPECS.HW_UyBellReaper = {
	Theme = 'HW_UyBell', Focus = 'BellGlow', HitEmit = 4, InspSpin = 4, RunSpin = 1, RushSpin = 3, InspRate = 2,
	RunTrail = seq(C(250, 236, 255), C(170, 110, 255), C(46, 34, 66)),
	Glow = { MoonEdge = .5, BellRune = .6, BellCrack = .5, BellInside = .4, SkullEye = .4, PoleRune = .3 },
	Moves = { ClapperRod = 'Clapper', Clapper = 'Clapper' },
	MovesByAnim = { Orbit = 'Ghosts' },
	MoodEvery = 7,
	IdleEvery = 2.6,
	Move = function(e, s, t, dt, h, ip, api)
		if s.MoodAt then s.TollAt = s.MoodAt end
		for _, z in ipairs({ .4, 1.1, 1.8 }) do
			if ip > z and ip < z + .05 then s.TollAt = t end
		end
		local toll = env(t, s.TollAt, 1.2, .04, .9)
		if toll > 0 then
			local swing = CFrame.Angles(0, 0, math.sin((t - s.TollAt) * 12) * .45 * toll)
			for _, p in ipairs(s.Moves.Clapper or {}) do api.push(e, p, swing) end
		end
		s.Lift = toll * .35
		orbit(e, s, t, 'Ghosts', api, .12, e.State.Insp * .4)
	end,
	Draw = function(e, s, t, api)
		local c = s.Pal
		s.TollAt = t
		s.Rush = 1
		e.Hit = math.max(e.Hit, .8)
		local p = at(s.Focus)
		if p then
			api.shock(p, c[1], 3.4, .3)
			waves(p, c[1], 6, .5)
		end
		local tip = s.TipB and s.TipB.Parent and s.TipB.WorldPosition
		if tip then api.crescent(tip, c[3], 1.6, math.rad(-30), .32) end
	end,
	Inspect = function(e, s, t, ip, api)
		local c = s.Pal
		local p = at(s.Focus)
		for k, z in ipairs({ .4, 1.1, 1.8 }) do
			if ip > z and not s.Fired['Toll' .. k] then
				s.Fired['Toll' .. k] = true
				if p then waves(p, k == 3 and c[3] or c[1], 4 + k * 1.5, .5) end
				if k == 3 then emit(s, 10) end
			end
		end
	end,
	Finale = function(e, s, t, api)
		local c = s.Pal
		local p = at(s.Focus)
		if not p then return end
		s.Rush = 1
		local tip = s.TipB and s.TipB.Parent and s.TipB.WorldPosition or p
		api.crescent(tip, c[3], 1.9, math.rad(-30), .34)
		api.shock(p, c[1], 4, .3)
		waves(p, c[3], 9, .6)
		api.glyph(p + V3(0, 1.3, 0), 'TOLLED!', 'ПРОЗВОНИЛ!', c[3], 32, V3(0, 1, 0), 1.2)
		for k = 1, api.n(3) do api.wisp(p + V3((k - 2) * .4, .3, 0), c[3], .24, 3, 1.3) end
	end,
	Mood = function(e, s, t, api)
		local p = at(s.Focus)
		if p then waves(p, s.Pal[1], 4.5, .5) end
	end,
	Idle = function(e, s, t, api)
		emit(s, 2)
	end,
	Run = function(e, s, t, flat, api)
		local p = at(s.Focus)
		if p then api.wisp(p - flat.Unit * .7, s.Pal[1], .2, 1, .8) end
	end,
	Hit = function(e, s, t, strength, api)
		s.Rush = math.max(s.Rush, strength * .7)
	end,
}
S2.LiveSpecs = LIVE_SPECS

---------------------------------------------------------------------------------------------------------------------
-- REGISTRATION
---------------------------------------------------------------------------------------------------------------------
local kitsDone, fxDone = false, false
local registered = setmetatable({}, { __mode = 'k' })
local function registerKits()
	if kitsDone then
		return
	end
	local RS = game:GetService('ReplicatedStorage')
	local mining = RS:FindFirstChild('Mining')
	local mod = mining and mining:FindFirstChild('MiningAudio')
	if not mod then
		return
	end
	local Audio = require(mod)
	if type(Audio) ~= 'table' or type(Audio.Kits) ~= 'table' or type(Audio.Sources) ~= 'table' then
		return
	end
	for name, kit in pairs(S2.Kits(Audio)) do
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
		return -- PickFX without the export: the skins keep their stock ThemeAlt (like Chapter I)
	end
	for name, pal in pairs(S2.Palettes) do
		themes[name] = pal
	end
	for name, fn in pairs(hitThemes(ctx)) do
		hit[name] = fn
	end
	liveCtx = ctx
	fxDone = true
end

function S2.Register(Skins, internals)
	if type(Skins) ~= 'table' or type(Skins.List) ~= 'table' then
		return false
	end
	if registered[Skins] then
		return true
	end
	registered[Skins] = true
	internals = type(internals) == 'table' and internals or {}
	Skins.ById = Skins.ById or {}
	Skins.Order = Skins.Order or {}
	for _, s in ipairs(S2.List) do
		if not Skins.ById[s.Id] then
			table.insert(Skins.List, s)
			Skins.ById[s.Id] = s
			table.insert(Skins.Order, s.Id)
		end
	end
	local designs = type(internals.Designs) == 'table' and internals.Designs or Skins.Designs
	if type(designs) == 'table' then
		for kind, fn in pairs(DESIGNS) do
			designs[kind] = fn
		end
	end
	if type(Skins.Palettes) == 'table' then
		for name, pal in pairs(S2.Palettes) do
			Skins.Palettes[name] = pal
		end
	end
	if type(internals.CritText) == 'table' then
		for name, t in pairs(S2.CritText) do
			internals.CritText[name] = t
		end
	end
	if type(internals.LiveSpecs) == 'table' then
		for kind, spec in pairs(LIVE_SPECS) do
			internals.LiveSpecs[kind] = spec
		end
	end
	-- the sound kits and hit themes follow every Skins.Register (server: MiningWorld; client: MiningClient.World)
	local base = Skins.Register
	if type(base) == 'function' then
		Skins.Register = function(ctx, ...)
			local result = base(ctx, ...)
			local ok, err = pcall(registerKits)
			if not ok then
				warn('PickaxeSkins2: sound kits ' .. tostring(err))
			end
			if IS_CLIENT and type(ctx) == 'table' then
				ok, err = pcall(registerFX, ctx)
				if not ok then
					warn('PickaxeSkins2: hit themes ' .. tostring(err))
				end
			end
			return result
		end
	end
	return true
end

return S2
