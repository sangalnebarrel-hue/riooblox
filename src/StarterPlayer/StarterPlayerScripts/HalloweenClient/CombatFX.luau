-- CHAPTER II combat in the world (StarterPlayerScripts.HalloweenClient.CombatFX, docs/halloween2/DESIGN.md §10.2-§10.3).
-- Client only, purely visual: the server (ServerScriptService.Halloween.EventHP) decides every hit.
-- * Hazard telegraphs from Signal "Hazard" (RS.Halloween.Hazards.Encode; {List} waves; {Cancel} ids): every shape of
--   Hazards (Circle, Ring with gaps, Line sweep, Cone, Safe = inverse glow with a bright edge, Box) as a rim + a fill that
--   grows to ImpactAt, coloured by the attack Kind (or def.Color), laid on the ground under the shape (ONE raycast per
--   hazard, tilted to the surface normal), moving with its Path. A telegraph pulses faster and brighter while the local
--   player stands inside it; ring gaps glow as safe doorways; safe circles brighten their edge. Drawing starts at the
--   player's own ShowAt (H10 Candle Corgi owners get it earlier), so nothing appears late.
-- * Impacts: shockwave rings / glowing cracks / dust per shape (FX.Shockwave, FX.Cracks, FX.Debris), a lingering
--   haze for DPS hazards (gas), a sound and a distance-scaled shake.
-- * Floating damage numbers for Signal Combat {Kind = "Hit"} over the hit player's head (shield damage in moon blue,
--   DPS ticks smaller); the knock-back velocity of the local player's own hits.
-- * Downed allies (player attributes HwDowned / HwCombatZone, the same zone as the local player): a pulsing light pillar,
--   a ground ring and a localized REVIVE billboard (name, distance, bleed-out time, "REVIVING..." while someone holds).
-- * REVIVE prompts (server ProximityPrompt "HwRevivePrompt" on downed characters): localized ActionText, hidden from the
--   downed player and from players outside that zone, HoldDuration scaled by the local HwReviveSpeed (H14 Bridehound).
-- Quality: Config.Quality[*].Telegraph detail (1 / 1 / .6; segment counts, chevrons, particles) via Shared.Quality();
-- ReducedMotion: steady rims (no flicker), no shake (FX), no flashes. Everything lives in FX.Folder() (SelfManagedFX).
-- Bus out: "CombatHazard" {Id, Kind, Shape, ImpactAt, Inside} (first frame a telegraph is drawn).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local CombatFX = { Started = false }

local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local RGB = Color3.fromRGB
local PI = math.pi
local WHITE = Color3.new(1, 1, 1)

local BLOOD = RGB(232, 48, 72)
local VIOLET = RGB(168, 92, 255)
local CANDLE = RGB(255, 158, 64)
local SICKLY = RGB(120, 255, 140)
local GRAVE = RGB(255, 96, 70)
local MOON = RGB(150, 200, 255)
local GOLD = RGB(255, 222, 130)
local INK = RGB(16, 12, 26)
local BONE = RGB(230, 222, 200)

-- attack Kind -> telegraph colour (def.Color wins)
CombatFX.Colors = {
	Slam = BLOOD, Stomp = VIOLET, Sweep = BLOOD, Erupt = SICKLY, FakeMound = SICKLY, Bite = BLOOD, Slash = BLOOD,
	Shockwave = VIOLET, Bell = VIOLET, Curse = VIOLET, Choir = MOON, Wave = VIOLET, Ring = VIOLET,
	Rock = CANDLE, RockImpact = CANDLE, RockExplode = CANDLE, Bone = BONE, BoneRain = BONE, Fall = CANDLE, Pendulum = CANDLE,
	Gas = SICKLY, Vent = SICKLY, Poison = SICKLY,
	Line = GRAVE, GraveLine = GRAVE, GraveLines = GRAVE, Collapse = GRAVE, Volley = GRAVE,
	Lantern = VIOLET, Safe = VIOLET, Debug = BLOOD,
}

function CombatFX.ColorOf(kind: any, color: any): Color3
	if typeof(color) == "Color3" then
		return color
	end
	return CombatFX.Colors[kind or ""] or BLOOD
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flat(v: Vector3): Vector3
	return V3(v.X, 0, v.Z)
end

function CombatFX.Start(ctx)
	if CombatFX.Started then
		return
	end
	CombatFX.Started = true
	local Shared, Config, Bus, FX, Audio = ctx.Shared, ctx.Config, ctx.Bus, ctx.FX, ctx.Audio
	local player = ctx.Player or Players.LocalPlayer
	local L = Shared.L
	local Halloween = RS:WaitForChild("Halloween")
	local Hazards = require(Halloween:WaitForChild("Hazards"))
	local Rules = require(Halloween:WaitForChild("CombatRules"))

	local function now(): number
		return Shared.Now()
	end
	local function low(): boolean
		return Shared.Low()
	end
	local function reduced(): boolean
		return Shared.ReducedMotion()
	end
	-- Telegraph detail: Config.Quality[q].Telegraph (1 / 1 / .6 by design §17)
	local function detail(): number
		local q = Shared.Quality()
		local row = Config.Quality and Config.Quality[q]
		local v = row and tonumber(row.Telegraph)
		if v then
			return math.clamp(v, .3, 1)
		end
		return q == "Low" and .6 or 1
	end
	local function myRoot(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return (r and r:IsA("BasePart")) and r or nil
	end
	local function play(name: string, where: any, opts: any?)
		if Audio and Audio.Play then
			Audio.Play(name, where, opts)
		end
	end
	-- the Chapter II cue when the audio library has it (WP-P: HazardWarn / HazardImpact / ShockwaveRing), else an
	-- existing Halloween cue
	local function cue(preferred: string, fallback: string): string
		local ok, has = pcall(function()
			return Audio and Audio.Has and Audio.Has(preferred)
		end)
		return (ok and has) and preferred or fallback
	end
	local lastWarn = 0
	local function shakeAt(pos: Vector3, amount: number, dur: number, range: number)
		local r = myRoot()
		if not r then
			return
		end
		local d = (r.Position - pos).Magnitude
		if d < range then
			FX.Shake(amount * (1 - d / range) ^ 1.4, dur)
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- ground: ONE raycast per hazard, the drawing lies in the plane of the hit (tilted to its normal)
	---------------------------------------------------------------------------------------------------------------
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local function groundFrame(point: Vector3): CFrame
		local ignore: { Instance } = { FX.Folder() }
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(ignore, pl.Character)
			end
		end
		local live = workspace:FindFirstChild("HalloweenLive")
		if live then
			table.insert(ignore, live)
		end
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(point + V3(0, 6, 0), V3(0, -26, 0), rayParams)
		local pos, n = point, V3(0, 1, 0)
		if hit then
			pos = hit.Position
			if hit.Normal.Y > .65 then
				n = hit.Normal
			end
		end
		local x = n:Cross(V3(0, 0, 1))
		if x.Magnitude < 1e-3 then
			x = V3(1, 0, 0)
		end
		x = x.Unit
		local z = x:Cross(n).Unit
		return CFrame.fromMatrix(pos + n * .07, x, n, z)
	end

	---------------------------------------------------------------------------------------------------------------
	-- drawings
	---------------------------------------------------------------------------------------------------------------
	local drawings = {} -- id -> drawing
	local waiting = {} -- id -> {Def, ShowAt}

	-- a part placed in the drawing's ground frame (kept so a moving shape can re-place it)
	local function piece(dr: any, localCF: CFrame, size: Vector3, color: Color3, tr: number, opts: any?): BasePart
		local o = opts or {}
		local p = FX.Part({ Class = o.Class or "Part", Shape = o.Shape, Size = size, Color = color, Transparency = tr,
			Material = o.Material or Enum.Material.Neon, CFrame = dr.Base * localCF, Parent = dr.Model })
		local entry = { P = p, Local = localCF }
		table.insert(dr.Parts, entry)
		dr.Entry[p] = entry
		return p
	end
	-- a flat disc (cylinder lying in the ground plane)
	local function discAt(dr: any, x: number, z: number, radius: number, color: Color3, tr: number, h: number?): BasePart
		return piece(dr, CF(x, 0, z) * ANG(0, 0, PI / 2), V3(h or .06, radius * 2, radius * 2), color, tr, { Shape = Enum.PartType.Cylinder })
	end
	-- a short tangent bar at angle a (radians) on radius r: Size = (radial thickness, height, tangent length)
	local function arcLocal(r: number, a: number, y: number?): CFrame
		return CF(math.cos(a) * r, y or 0, math.sin(a) * r) * ANG(0, -a, 0)
	end
	-- rim of segments from a0 to a1 (radians), skipping `skip(angleDeg)` sectors
	local function rim(dr: any, r: number, color: Color3, n: number, a0: number, a1: number, thick: number, skip: ((number) -> boolean)?)
		local list = {}
		for i = 0, n - 1 do
			local a = a0 + (a1 - a0) * (i + .5) / n
			if not (skip and skip(math.deg(a) % 360)) then
				local len = math.abs(a1 - a0) / n * r * 1.04
				table.insert(list, piece(dr, arcLocal(r, a, .02), V3(thick, .14, math.max(.2, len)), color, .1))
			end
		end
		return list
	end

	-- a ">" lying on the ground: its tip at `tip`, pointing along `dir` (flat), two arms of `len`
	local function chevron(dr: any, tip: Vector3, dir: Vector3, len: number, color: Color3, tr: number, meta: any)
		local d = flat(dir)
		if d.Magnitude < 1e-3 then
			return
		end
		d = d.Unit
		local side = V3(-d.Z, 0, d.X)
		for _, k in ipairs({ -1, 1 }) do
			local back = (-d + side * k).Unit
			local c = tip + back * (len / 2)
			local p = piece(dr, CFrame.lookAt(c, c + back), V3(.34, .1, len), color, tr)
			local e = table.clone(meta)
			e.P = p
			table.insert(dr.Chevrons, e)
		end
	end

	local function shapeColor(d: any): Color3
		return CombatFX.ColorOf(d.Kind, d.Color)
	end

	-- Circle: segmented rim, faint full disc, a fill disc growing to the rim, crossed runes in the middle
	local function buildCircle(dr: any, s: any, q: number)
		local r = math.max(.5, tonumber(s.Radius) or 4)
		local col = dr.Color
		dr.Rim = rim(dr, r, col, math.clamp(math.floor(r * 2.4 * q), 12, 44), 0, PI * 2, .45)
		dr.Faint = discAt(dr, 0, 0, r, col, .82, .04)
		dr.Grow = discAt(dr, 0, .01, .2, col:Lerp(WHITE, .15), .45, .05)
		dr.GrowR = r
		local rune = math.min(r * .55, 6)
		table.insert(dr.Rune, piece(dr, CF(0, .03, 0) * ANG(0, PI / 4, 0), V3(rune, .1, .3), col:Lerp(WHITE, .3), .3))
		table.insert(dr.Rune, piece(dr, CF(0, .03, 0) * ANG(0, -PI / 4, 0), V3(rune, .1, .3), col:Lerp(WHITE, .3), .3))
	end

	-- Ring: inner + outer rims and an annulus of slabs whose band grows outwards; gaps get safe-green doorway posts
	local function buildRing(dr: any, s: any, q: number)
		local inner = math.max(0, tonumber(s.Inner) or 0)
		local outer = math.max(inner + .5, tonumber(s.Outer) or inner + 4)
		local col = dr.Color
		local skip = function(deg: number)
			return Hazards.InGap(s, deg)
		end
		local n = math.clamp(math.floor(outer * 2.2 * q), 16, 64)
		dr.Rim = rim(dr, outer, col, n, 0, PI * 2, .45, skip)
		if inner > .8 then
			for _, p in ipairs(rim(dr, inner, col, math.clamp(math.floor(inner * 2.2 * q), 10, 48), 0, PI * 2, .35, skip)) do
				table.insert(dr.Rim, p)
			end
		end
		dr.Band = {}
		local m = math.clamp(math.floor(outer * 1.6 * q), 14, 56)
		dr.BandM = m
		for i = 0, m - 1 do
			local a = (i + .5) / m * PI * 2
			if not Hazards.InGap(s, math.deg(a) % 360) then
				local slab = piece(dr, arcLocal(inner, a, .01), V3(.1, .05, (PI * 2 / m) * outer * 1.05), col, .55)
				table.insert(dr.Band, { P = slab, A = a })
			end
		end
		dr.Inner, dr.Outer = inner, outer
		-- doorways: two bright posts on each gap edge + a soft safe glow in the gap
		for _, g in ipairs(type(s.Gaps) == "table" and s.Gaps or {}) do
			local a = math.rad(tonumber(g.Angle or g[1]) or 0)
			local w = math.rad(tonumber(g.Width or g[2]) or 0)
			local mid = (inner + outer) / 2
			for _, e in ipairs({ a - w / 2, a + w / 2 }) do
				local post = piece(dr, arcLocal(mid, e, .5), V3(outer - inner + .4, 1, .25), SICKLY:Lerp(WHITE, .35), .15)
				table.insert(dr.Safe, post)
			end
			local glow = piece(dr, arcLocal(mid, a, .02), V3(outer - inner, .04, math.max(.5, w * mid * .9)), SICKLY, .7)
			table.insert(dr.Safe, glow)
		end
	end

	-- Line: two side rails + end bars, a fill that sweeps From -> To, chevrons pointing along the sweep
	local function buildLine(dr: any, s: any, q: number)
		local from, to = dr.Local(s.From), dr.Local(s.To)
		local dir = flat(to - from)
		local len = math.max(.5, dir.Magnitude)
		dir = dir.Unit
		local side = V3(-dir.Z, 0, dir.X)
		local w = math.max(.5, tonumber(s.Width) or 4)
		local col = dr.Color
		local mid = (from + to) / 2
		for _, k in ipairs({ -1, 1 }) do
			local c = mid + side * (w / 2) * k
			table.insert(dr.Rim, piece(dr, CFrame.lookAt(c + V3(0, .02, 0), c + V3(0, .02, 0) + dir), V3(.4, .14, len), col, .1))
		end
		for _, e in ipairs({ from, to }) do
			table.insert(dr.Rim, piece(dr, CFrame.lookAt(e + V3(0, .02, 0), e + V3(0, .02, 0) + side), V3(.4, .14, w), col, .1))
		end
		dr.Faint = piece(dr, CFrame.lookAt(mid, mid + dir), V3(w, .04, len), col, .84)
		dr.Sweep = piece(dr, CFrame.lookAt(from, from + dir), V3(w * .96, .05, .2), col:Lerp(WHITE, .12), .45)
		dr.LineFrom, dr.LineDir, dr.LineLen, dr.LineW = from, dir, len, w
		local count = math.max(2, math.floor(math.min(6, len / 7) * q))
		local arm = math.min(w * .32, 2.2)
		for i = 1, count do
			local tip = from + dir * (len * i / (count + 1) + arm * .35) + V3(0, .04, 0)
			chevron(dr, tip, dir, arm, col:Lerp(WHITE, .45), .4, { I = i, N = count })
		end
	end

	-- Cone: rim arc + two edges + a fan of slabs growing outwards
	local function buildCone(dr: any, s: any, q: number)
		local r = math.max(1, tonumber(s.Radius) or 8)
		local dir = typeof(s.Dir) == "Vector3" and flat(s.Dir) or V3(0, 0, -1)
		if dir.Magnitude < 1e-3 then
			dir = V3(0, 0, -1)
		end
		local center = math.atan2(dir.Unit.Z, dir.Unit.X)
		local half = math.rad(math.clamp(tonumber(s.Angle) or 90, 5, 360) / 2)
		local col = dr.Color
		dr.Rim = rim(dr, r, col, math.clamp(math.floor(r * 2 * half * q), 6, 36), center - half, center + half, .45)
		if half < PI - .01 then
			for _, k in ipairs({ -1, 1 }) do
				local a = center + half * k
				local tip = V3(math.cos(a) * r, .02, math.sin(a) * r)
				table.insert(dr.Rim, piece(dr, CFrame.lookAt(tip / 2, tip), V3(.45, .14, r), col, .1))
			end
		end
		local n = math.clamp(math.floor(14 * q), 8, 18)
		dr.Fan = {}
		for i = 1, n do
			local a = center - half + 2 * half * (i - .5) / n
			local p = piece(dr, CF(0, .01, 0), V3(.2, .05, .2), col, .55)
			table.insert(dr.Fan, { P = p, A = a, W = 2 * half / n * r * 1.12 })
		end
		dr.ConeR = r
	end

	-- Safe (inverse): a bright gold edge, a soft lit floor inside, and the danger band OUTSIDE in the attack colour
	local function buildSafe(dr: any, s: any, q: number)
		local r = math.max(1, tonumber(s.Radius) or 8)
		local band = math.min(14, math.max(4, (tonumber(s.Outer) or (r + 14)) - r))
		local col = dr.Color
		dr.Edge = rim(dr, r, GOLD, math.clamp(math.floor(r * 2.6 * q), 16, 48), 0, PI * 2, .7)
		for _, p in ipairs(dr.Edge) do
			p.Size = V3(p.Size.X, .3, p.Size.Z)
		end
		dr.Lit = discAt(dr, 0, 0, r, GOLD, .82, .04)
		dr.Band = {}
		local m = math.clamp(math.floor((r + band) * 1.4 * q), 16, 48)
		for i = 0, m - 1 do
			local a = (i + .5) / m * PI * 2
			local slab = piece(dr, arcLocal(r + band / 2, a, .01), V3(band, .05, (PI * 2 / m) * (r + band) * 1.05), col, .8)
			table.insert(dr.Band, { P = slab, A = a })
		end
		-- inward arrows on the danger band: "get inside"
		local arrows = math.max(4, math.floor(8 * q))
		local arm = math.clamp(band * .22, 1.2, 2.2)
		for i = 1, arrows do
			local a = (i - .5) / arrows * PI * 2
			local out = V3(math.cos(a), 0, math.sin(a))
			for j = 0, 1 do -- a double chevron ">>" pointing into the safe circle
				local tip = out * (r + band * .38 + j * arm * .9) + V3(0, .05, 0)
				chevron(dr, tip, -out, arm, GOLD, .35, { I = 1, N = 1 })
			end
		end
		local holder = piece(dr, CF(0, 3, 0), V3(.2, .2, .2), GOLD, 1)
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = math.min(40, r * 2)
		light.Brightness = 0
		light.Shadows = false
		light.Parent = holder
		dr.Light = light
		dr.SafeR = r
	end

	-- Box: four edge bars + a fill growing from the middle
	local function buildBox(dr: any, s: any, _q: number)
		local size: Vector3 = s.Size
		local look = flat(s.CFrame.LookVector)
		if look.Magnitude < 1e-3 then
			look = V3(0, 0, -1)
		end
		local rot = CFrame.lookAt(Vector3.zero, look.Unit)
		dr.BoxRot, dr.BoxSize = rot, size
		local col = dr.Color
		local hx, hz = size.X / 2, size.Z / 2
		for _, e in ipairs({ { 0, -hz, size.X, .4 }, { 0, hz, size.X, .4 }, { -hx, 0, .4, size.Z }, { hx, 0, .4, size.Z } }) do
			table.insert(dr.Rim, piece(dr, rot * CF(e[1], .02, e[2]), V3(e[3], .14, e[4]), col, .1))
		end
		dr.Faint = piece(dr, rot * CF(0, 0, 0), V3(size.X, .04, size.Z), col, .84)
		dr.Grow = piece(dr, rot * CF(0, .01, 0), V3(.2, .05, .2), col:Lerp(WHITE, .12), .45)
	end

	local BUILD = { Circle = buildCircle, Ring = buildRing, Line = buildLine, Cone = buildCone, Safe = buildSafe, Box = buildBox }

	local function destroy(dr: any, fade: number?)
		if dr.Dead then
			return
		end
		dr.Dead = true
		drawings[dr.Id] = nil
		if dr.Haze then
			pcall(function()
				dr.Haze.Enabled = false
			end)
		end
		local model = dr.Model
		if fade and fade > 0 and not reduced() then
			for _, e in ipairs(dr.Parts) do
				if e.P.Parent then
					FX.Tween(e.P, fade, { Transparency = 1 })
				end
			end
			if dr.Light then
				FX.Tween(dr.Light, fade, { Brightness = 0 })
			end
			Debris:AddItem(model, fade + .05)
		else
			model:Destroy()
		end
	end

	local function create(d: any, showAt: number)
		local ty = Hazards.TypeOf(d.Shape)
		local builder = ty and BUILD[ty]
		if not builder then
			return
		end
		local model = Instance.new("Model")
		model.Name = "CombatTelegraph_" .. tostring(d.Id)
		model.Parent = FX.Folder()
		local start = Hazards.Center(d.Shape)
		local dr = { Id = d.Id, Def = d, Type = ty, ShowAt = showAt, Model = model, Parts = {}, Entry = {}, Rim = {}, Rune = {}, Safe = {},
			Chevrons = {}, Color = shapeColor(d), Start = start }
		local ok, err = pcall(function()
			dr.Base = groundFrame(start)
			dr.Rot = dr.Base - dr.Base.Position
			dr.GroundY = dr.Base.Position.Y
			-- world -> the drawing's local ground frame (shape points are world positions around Start)
			dr.Local = function(p: Vector3): Vector3
				local o = flat(p - start)
				return V3(o.X, 0, o.Z)
			end
			builder(dr, d.Shape, detail())
		end)
		if not ok then
			warn("CombatFX: telegraph build failed: " .. tostring(err))
			model:Destroy()
			return
		end
		drawings[d.Id] = dr
		if Bus then
			Bus.Fire("CombatHazard", { Id = d.Id, Kind = d.Kind, Shape = d.Shape, ImpactAt = d.ImpactAt })
		end
		-- a soft warning cue for hazards close to the local player (one per .15 s: waves stay readable, not noisy)
		local r = myRoot()
		if r and (flat(r.Position - start)).Magnitude < Hazards.Extent(d.Shape) + 30 and os.clock() - lastWarn > .15 then
			lastWarn = os.clock()
			if d.Kind == "Rock" or d.Kind == "RockImpact" or d.Kind == "Fall" or d.Kind == "Bone" or d.Kind == "BoneRain" then
				play("RockWhistle", start, { Volume = .35 })
			elseif cue("HazardWarn", "") == "HazardWarn" then
				play("HazardWarn", start, { Volume = (tonumber(d.Damage) or 0) >= 15 and .8 or .55 })
			elseif (tonumber(d.Damage) or 0) >= 15 then
				play("GroundCrack", start, { Volume = .3, Pitch = 1.25 })
			end
		end
	end

	-- the drawing's current ground frame (moving shapes follow their Path)
	local function rebase(dr: any, t: number)
		local shape = dr.Def.Shape
		local c = Hazards.PathCenter(shape, t)
		if not c then
			return
		end
		-- the same rule as Hazards.At: lines and boxes move by the path's offset, every other shape centres on the path
		if dr.Type == "Line" or dr.Type == "Box" then
			c = dr.Start + (c - shape.Path[1].Center)
		end
		local base = dr.Rot + V3(c.X, dr.GroundY, c.Z)
		if (base.Position - dr.Base.Position).Magnitude < .01 then
			return
		end
		dr.Base = base
		for _, e in ipairs(dr.Parts) do
			if e.P.Parent then
				e.P.CFrame = base * e.Local
			end
		end
		if dr.Haze and dr.HazePart then
			dr.HazePart.CFrame = CF(base.Position + V3(0, 1, 0))
		end
	end

	local function setLocal(dr: any, part: BasePart, localCF: CFrame)
		local e = dr.Entry[part]
		if e then
			e.Local = localCF
		end
		part.CFrame = dr.Base * localCF
	end

	local function impactFX(dr: any)
		local d = dr.Def
		local col = dr.Color
		local base = dr.Base.Position
		local n = dr.Base.UpVector
		local dmg = tonumber(d.Damage) or 0
		local heavy = dmg >= 15
		local s = Hazards.At(d.Shape, 0)
		local reach = 0
		if dr.Type == "Line" then
			local from, dir, len = dr.LineFrom, dr.LineDir, dr.LineLen
			local count = math.clamp(math.floor(len / 6 * detail()), 2, 8)
			for i = 0, count do
				local p = dr.Base * (from + dir * (len * i / count))
				FX.Ring(p, col, dr.LineW * .9, .45, { Thickness = .18 })
				if i % 2 == 0 and not low() then
					FX.Cracks(p, n, col, dr.LineW * .9, 1.4)
				end
			end
			FX.Light(dr.Base * (from + dir * len * .5) + n * 3, col, len * .7, 2.4, .6)
			reach = len / 2 + dr.LineW
		elseif dr.Type == "Ring" then
			FX.Ring(base, col, dr.Outer, .5, { Thickness = .3 })
			FX.Ring(base, col:Lerp(WHITE, .4), (dr.Inner + dr.Outer) / 2, .4, { Thickness = .18 })
			if not low() then
				local bursts = math.floor(6 * detail())
				for i = 1, bursts do
					local a = math.rad((i / bursts) * 360 + math.random() * 20)
					if not Hazards.InGap(s, math.deg(a) % 360) then
						local rr = (dr.Inner + dr.Outer) / 2
						FX.Burst(base + V3(math.cos(a) * rr, .6, math.sin(a) * rr), { Color = col, Color2 = WHITE, Count = 8, Speed = { 6, 12 },
							Lifetime = { .3, .6 }, Size = { .4, .7, 0 }, Spread = 50, Direction = V3(0, 1, 0) })
					end
				end
			end
			reach = dr.Outer
		elseif dr.Type == "Safe" then
			FX.Ring(base, GOLD, dr.SafeR, .6, { Thickness = .3 })
			if not reduced() then
				for _, b in ipairs(dr.Band) do
					b.P.Transparency = .15
				end
			end
			reach = dr.SafeR + 14
		elseif dr.Type == "Box" then
			local size = dr.BoxSize
			FX.Shockwave(base + n * .2, col, math.max(size.X, size.Z) / 2, .6)
			if not low() then
				FX.Cracks(base, n, col, math.min(size.X, size.Z) * .8, 1.6)
			end
			reach = math.max(size.X, size.Z) / 2
		else
			local r = dr.Type == "Cone" and dr.ConeR or (tonumber(s.Radius) or 4)
			local center = base
			if dr.Type == "Cone" and #dr.Fan > 0 then
				local mid = dr.Fan[math.ceil(#dr.Fan / 2)].A
				center = base + V3(math.cos(mid) * r * .5, 0, math.sin(mid) * r * .5)
			end
			if dmg > 0 then
				FX.Shockwave(center + n * .2, col, dr.Type == "Cone" and r * .7 or r, .6)
				if not low() then
					FX.Cracks(center, n, col, r * .85, 1.8)
					if heavy then
						FX.Debris(center + n * .6, RGB(64, 58, 72), Enum.Material.Slate, 10, 26, { MaxSize = 1.1, Floor = center.Y + .2 })
					end
				end
			end
			reach = r
		end
		if (tonumber(d.DPS) or 0) > 0 and (tonumber(d.Linger) or 0) > 0 and dr.Type ~= "Safe" then
			-- a lingering haze (gas vents, curses) for the linger time
			local life = tonumber(d.Linger) or 0
			local holder = FX.Part({ Size = V3(.2, .2, .2), Transparency = 1, CFrame = CF(base + V3(0, 1, 0)), Parent = dr.Model })
			local att = Instance.new("Attachment")
			att.Parent = holder
			local e = Instance.new("ParticleEmitter")
			e.Texture = FX.Textures.Smoke
			e.Color = ColorSequence.new(col, col:Lerp(INK, .5))
			e.LightEmission = .25
			e.LightInfluence = 0
			local size = math.min(8, math.max(2.5, reach * .6))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * .4), NumberSequenceKeypoint.new(.5, size), NumberSequenceKeypoint.new(1, size * 1.3) })
			e.Transparency = NumberSequence.new(.55, 1)
			e.Lifetime = NumberRange.new(1.2, 2.2)
			e.Speed = NumberRange.new(.5, 2)
			e.SpreadAngle = Vector2.new(180, 20)
			e.Acceleration = V3(0, 1.2, 0)
			e.Shape = Enum.ParticleEmitterShape.Disc
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			att.CFrame = ANG(0, 0, 0)
			e.Rate = math.floor(12 * FX.Budget("Particles") * detail() + .5)
			e:SetAttribute("HwParticlePriority", true)
			e.Parent = att
			holder.Size = V3(.2, .2, .2)
			dr.Haze, dr.HazePart = e, holder
			task.delay(life, function()
				if e.Parent then
					e.Enabled = false
				end
			end)
			play("CurseWhisper", base, { Volume = .25 })
		end
		if dmg > 0 then
			local sound = dr.Type == "Ring" and cue("ShockwaveRing", "") or ""
			if sound == "" then
				sound = cue("HazardImpact", heavy and "BossSlam" or "RockImpact")
			end
			play(sound, base, { Volume = heavy and .65 or .5, Pitch = dr.Type == "Line" and 1.15 or 1 })
			shakeAt(base, heavy and .55 or .35, heavy and .45 or .3, reach + 30)
		end
	end

	-- one frame of every live drawing
	local function stepDrawing(dr: any, t: number, me: Vector3?)
		local d = dr.Def
		local k = Hazards.Progress(d, t, dr.ShowAt)
		local since = t - d.ImpactAt
		local phase = Hazards.Phase(d, t, dr.ShowAt)
		rebase(dr, since)
		local inside = me ~= nil and Hazards.Contains(d.Shape, me, since)
		local ease = smooth(k)
		local rm = reduced()
		local pulse = rm and .5 or (.5 + .5 * math.sin(t * ((inside and 16 or 8) + 14 * k)))
		local rimTr = inside and (.02 + pulse * .12) or (.08 + pulse * .25)
		for _, p in ipairs(dr.Rim) do
			p.Transparency = rimTr
		end
		-- Circle / Box: the fill grows to the full shape
		if dr.Grow then
			if dr.Type == "Box" then
				local s = dr.BoxSize
				dr.Grow.Size = V3(math.max(.2, s.X * ease), .05, math.max(.2, s.Z * ease))
			else
				local r = math.max(.2, dr.GrowR * ease)
				dr.Grow.Size = V3(.05, r * 2, r * 2)
			end
			dr.Grow.Transparency = phase == "Linger" and (.35 + pulse * .2) or (.55 - .25 * k)
		end
		for _, p in ipairs(dr.Rune) do
			p.Transparency = .2 + pulse * .4
		end
		-- Ring: the band thickens from the inner edge to the outer
		if dr.Type == "Ring" and dr.Band then
			local thick = math.max(.1, (dr.Outer - dr.Inner) * ease)
			local arc = (PI * 2 / dr.BandM) * (dr.Inner + thick) * 1.06 -- the arc of the band's growing outer edge
			for _, b in ipairs(dr.Band) do
				setLocal(dr, b.P, arcLocal(dr.Inner + thick / 2, b.A, .01))
				b.P.Size = V3(thick, .05, math.max(.2, arc))
				b.P.Transparency = .62 - .25 * k
			end
			for _, p in ipairs(dr.Safe) do
				p.Transparency = (p.Size.Y > .5) and (.1 + (1 - pulse) * .2) or (.55 + pulse * .15)
			end
		end
		-- Line: the fill sweeps from From towards To; chevrons run along the sweep
		if dr.Sweep then
			local len = math.max(.2, dr.LineLen * ease)
			local from, dir = dr.LineFrom, dr.LineDir
			local c = from + dir * (len / 2)
			setLocal(dr, dr.Sweep, CFrame.lookAt(c + V3(0, .01, 0), c + V3(0, .01, 0) + dir))
			dr.Sweep.Size = V3(dr.LineW * .96, .05, len)
			dr.Sweep.Transparency = phase == "Linger" and .35 or (.55 - .2 * k)
		end
		for _, ch in ipairs(dr.Chevrons) do
			if dr.Type == "Safe" then
				ch.P.Transparency = rm and .3 or (.15 + (1 - pulse) * .45)
			else
				local wave = rm and .5 or ((t * 2.2 - ch.I / (ch.N + 1)) % 1)
				ch.P.Transparency = .25 + wave * .6
			end
		end
		-- Cone: the fan grows outwards
		if dr.Fan then
			local len = math.max(.2, dr.ConeR * ease)
			for _, f in ipairs(dr.Fan) do
				local tip = V3(math.cos(f.A) * len, .01, math.sin(f.A) * len)
				setLocal(dr, f.P, CFrame.lookAt(tip / 2 + V3(0, .01, 0), tip))
				f.P.Size = V3(math.max(.2, f.W * len / dr.ConeR), .05, len)
				f.P.Transparency = .6 - .25 * k
			end
		end
		-- Safe: the gold edge brightens, the danger band outside fills in
		if dr.Type == "Safe" then
			for _, p in ipairs(dr.Edge) do
				p.Transparency = rm and .05 or (.02 + (1 - pulse) * .15)
			end
			if dr.Lit then
				dr.Lit.Transparency = .86 - .12 * k
			end
			if dr.Light then
				dr.Light.Brightness = 1.2 + 1.3 * k
			end
			for _, b in ipairs(dr.Band) do
				local tr = phase == "Linger" and (.3 + (rm and .1 or pulse * .2)) or (.82 - .45 * k)
				b.P.Transparency = inside and math.max(.15, tr - .15) or tr
			end
		end
		if dr.Faint then
			dr.Faint.Transparency = .86 - .08 * k
		end
		return inside
	end

	local function receive(d: any)
		if type(d) ~= "table" or d.Id == nil or drawings[d.Id] or waiting[d.Id] then
			return
		end
		local showAt = tonumber(d.ShowAt) or Hazards.ShowAt(d)
		local t = now()
		if t > Hazards.EndAt(d) + .1 then
			return -- arrived too late to matter
		end
		if t >= showAt then
			create(d, showAt)
		else
			waiting[d.Id] = { Def = d, ShowAt = showAt }
		end
	end

	local function cancel(ids: any)
		for _, id in ipairs(type(ids) == "table" and ids or {}) do
			waiting[id] = nil
			local dr = drawings[id]
			if dr then
				destroy(dr, .25)
			end
		end
	end

	CombatFX.Receive = function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Cancel then
			cancel(payload.Cancel)
			return
		end
		local list = payload.List or { payload }
		for _, enc in ipairs(list) do
			local okD, d = pcall(Hazards.Decode, enc)
			if okD and d then
				receive(d)
			end
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- floating damage numbers + own knock-back
	---------------------------------------------------------------------------------------------------------------
	local lastPopup = {} -- userId -> clock (DPS ticks are throttled)
	local function headOf(pl: Player): Vector3?
		local ch = pl.Character
		local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
		return (head and head:IsA("BasePart")) and head.Position or nil
	end
	local function onHit(data: any)
		local uid = tonumber(data.UserId) or 0
		local pl = Players:GetPlayerByUserId(uid)
		local mine = pl == player
		if mine and typeof(data.Knock) == "Vector3" then
			local r = myRoot()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if r then
				r.AssemblyLinearVelocity = data.Knock
				if hum then
					hum:ChangeState(Enum.HumanoidStateType.Freefall)
				end
			end
		end
		local head = pl and headOf(pl)
		if not head then
			return
		end
		local amount = tonumber(data.Amount) or 0
		if amount <= 0 then
			return
		end
		local clock = os.clock()
		if data.Tick and clock - (lastPopup[uid] or 0) < .45 then
			return
		end
		lastPopup[uid] = clock
		local absorbed = tonumber(data.Absorbed) or 0
		local shieldOnly = absorbed >= amount - 1e-3
		local text = "-" .. tostring(math.max(1, math.floor(amount + .5)))
		local color = shieldOnly and MOON or (mine and RGB(255, 86, 96) or RGB(255, 150, 150))
		local jitter = V3((math.random() - .5) * 1.6, 0, (math.random() - .5) * 1.6)
		FX.Popup(head + V3(0, 1.6, 0) + jitter, text, color, mine and not data.Tick)
	end

	---------------------------------------------------------------------------------------------------------------
	-- downed allies: light pillar + ground ring + REVIVE billboard
	---------------------------------------------------------------------------------------------------------------
	local markers = {} -- Player -> marker
	local function myZone(): string?
		if player:GetAttribute("HwCombat") ~= true then
			return nil
		end
		local z = player:GetAttribute("HwCombatZone")
		return type(z) == "string" and z or nil
	end
	local function wantsMarker(pl: Player): boolean
		if pl == player or pl:GetAttribute("HwDowned") ~= true then
			return false
		end
		local z = myZone()
		return z ~= nil and pl:GetAttribute("HwCombatZone") == z
	end
	local function removeMarker(pl: Player)
		local m = markers[pl]
		markers[pl] = nil
		if m then
			m.Model:Destroy()
			if m.Gui then
				m.Gui:Destroy()
			end
		end
	end
	local function label(parent: Instance, name: string, size: number, color: Color3, y: number, h: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.FontFace = FX.Font
		t.TextSize = size
		t.TextColor3 = color
		t.Position = UDim2.new(0, 8, 0, y)
		t.Size = UDim2.new(1, -16, 0, h)
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextScaled = true
		t:SetAttribute("NoTranslate", true)
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size
		limit.MinTextSize = 8
		limit.Parent = t
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = 1.5
		stroke.Parent = t
		t.Parent = parent
		return t
	end
	local function makeMarker(pl: Player)
		local ch = pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local model = Instance.new("Model")
		model.Name = "HwDownedMarker_" .. pl.UserId
		model.Parent = FX.Folder()
		local feet = root.Position - V3(0, 2.9, 0)
		local pillar = FX.Part({ Shape = Enum.PartType.Cylinder, Size = V3(26, .9, .9), Color = BLOOD, Transparency = .35,
			CFrame = CF(feet + V3(0, 13, 0)) * ANG(0, 0, PI / 2), Parent = model })
		local glow = FX.Part({ Shape = Enum.PartType.Cylinder, Size = V3(26, 3.2, 3.2), Color = BLOOD:Lerp(VIOLET, .4), Transparency = .78,
			Material = Enum.Material.ForceField, CFrame = pillar.CFrame, Parent = model })
		local ring = FX.Part({ Shape = Enum.PartType.Cylinder, Size = V3(.1, 7, 7), Color = BLOOD, Transparency = .25,
			CFrame = CF(feet + V3(0, .1, 0)) * ANG(0, 0, PI / 2), Parent = model })
		local inner = FX.Part({ Shape = Enum.PartType.Cylinder, Size = V3(.12, 6.2, 6.2), Color = INK, Transparency = .35,
			Material = Enum.Material.SmoothPlastic, CFrame = ring.CFrame, Parent = model })
		local light = Instance.new("PointLight")
		light.Color = BLOOD
		light.Range = 16
		light.Brightness = 2
		light.Shadows = false
		light.Parent = pillar
		-- the billboard lives in the local PlayerGui (adornee = the downed root), so it never replicates or lingers
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local gui = Instance.new("BillboardGui")
		gui.Name = "HwDownedCard_" .. pl.UserId
		gui.Adornee = root
		gui.Size = UDim2.fromOffset(190, 84)
		gui.StudsOffsetWorldSpace = V3(0, 4.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 320
		gui.ResetOnSpawn = false
		gui:SetAttribute("NoTranslate", true)
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = INK
		card.BackgroundTransparency = .18
		card.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = BLOOD
		stroke.Thickness = 2
		stroke.Parent = card
		local title = label(card, "Title", 24, GOLD, 4, 28)
		local name = label(card, "Name", 15, BONE, 32, 18)
		local info = label(card, "Info", 13, RGB(220, 200, 240), 50, 16)
		local track = Instance.new("Frame")
		track.Name = "Bleed"
		track.Position = UDim2.new(0, 12, 1, -10)
		track.Size = UDim2.new(1, -24, 0, 5)
		track.BackgroundColor3 = RGB(40, 14, 30)
		track.BorderSizePixel = 0
		track.Parent = card
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(1, 0)
		tc.Parent = track
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = BLOOD
		fill.BorderSizePixel = 0
		fill.Parent = track
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(1, 0)
		fc.Parent = fill
		gui.Parent = pg
		local m = { Player = pl, Model = model, Pillar = pillar, Glow = glow, Ring = ring, Inner = inner, Light = light, Gui = gui, Title = title,
			Name = name, Info = info, Fill = fill, Stroke = stroke, Root = root, Born = os.clock() }
		markers[pl] = m
		if not reduced() then
			pillar.Size = V3(.2, .9, .9)
			FX.Tween(pillar, .45, { Size = V3(26, .9, .9) }, Enum.EasingStyle.Back)
		end
		FX.Ring(feet + V3(0, .2, 0), BLOOD, 7, .5)
		play("BellCreak", feet, { Volume = .35, Pitch = .8 })
	end
	local function stepMarkers(t: number)
		for _, pl in ipairs(Players:GetPlayers()) do
			local want = wantsMarker(pl)
			local m = markers[pl]
			if m and (not want or not m.Root.Parent or m.Root ~= (pl.Character and pl.Character:FindFirstChild("HumanoidRootPart"))) then
				removeMarker(pl)
				m = nil
			end
			if want and not m then
				makeMarker(pl)
			end
		end
		local me = myRoot()
		local canRevive = player:GetAttribute("HwDowned") ~= true
		for pl, m in pairs(markers) do
			local feet = m.Root.Position - V3(0, 2.9, 0)
			local pulse = reduced() and .5 or (.5 + .5 * math.sin(t * 5))
			m.Pillar.CFrame = CF(feet + V3(0, 13, 0)) * ANG(0, 0, PI / 2)
			m.Glow.CFrame = m.Pillar.CFrame
			m.Ring.CFrame = CF(feet + V3(0, .1, 0)) * ANG(0, (reduced() and 0 or t * .8), PI / 2)
			m.Inner.CFrame = CF(feet + V3(0, .12, 0)) * ANG(0, 0, PI / 2)
			m.Pillar.Transparency = .2 + pulse * .3
			m.Light.Brightness = 1.4 + pulse * 1.4
			local by = tonumber(pl:GetAttribute("HwReviveBy")) or 0
			local untilT = tonumber(pl:GetAttribute("HwDownedUntil")) or 0
			local left = math.max(0, untilT - Shared.Now())
			local total = Rules.Config().DownedSeconds
			m.Fill.Size = UDim2.fromScale(math.clamp(left / math.max(1, total), 0, 1), 1)
			local dist = me and math.floor((me.Position - m.Root.Position).Magnitude + .5) or 0
			m.Name.Text = pl.DisplayName
			if by ~= 0 then
				local who = Players:GetPlayerByUserId(by)
				m.Title.Text = L("REVIVING...", "ПОДНИМАЮТ...")
				m.Title.TextColor3 = SICKLY
				m.Stroke.Color = SICKLY
				m.Info.Text = who and who.DisplayName or ""
				m.Pillar.Color = SICKLY
				m.Ring.Color = SICKLY
				m.Light.Color = SICKLY
			else
				m.Title.Text = canRevive and L("REVIVE", "ПОДНЯТЬ") or L("DOWNED", "ПОВЕРЖЕН")
				m.Title.TextColor3 = GOLD
				m.Stroke.Color = BLOOD
				m.Info.Text = L(string.format("%d m · %d s", dist, math.ceil(left)), string.format("%d м · %d с", dist, math.ceil(left)))
				m.Pillar.Color = BLOOD
				m.Ring.Color = BLOOD
				m.Light.Color = BLOOD
			end
			m.Fill.BackgroundColor3 = left < 6 and BLOOD:Lerp(WHITE, pulse * .5) or BLOOD
		end
	end

	---------------------------------------------------------------------------------------------------------------
	-- REVIVE prompts (server ProximityPrompt on downed characters): localized and filtered for this player
	---------------------------------------------------------------------------------------------------------------
	local prompts = {} -- prompt -> true
	local function stylePrompt(prompt: ProximityPrompt)
		if not prompt.Parent then
			prompts[prompt] = nil
			return
		end
		local target = tonumber(prompt:GetAttribute("HwTargetUserId")) or 0
		local zone = prompt:GetAttribute("HwCombatZone")
		local mine = target == player.UserId
		local allowed = not mine and player:GetAttribute("HwCombat") == true and player:GetAttribute("HwDowned") ~= true
			and player:GetAttribute("HwCombatZone") == zone
		prompt.Enabled = allowed
		prompt.ActionText = L("REVIVE", "ПОДНЯТЬ")
		local who = Players:GetPlayerByUserId(target)
		prompt.ObjectText = who and who.DisplayName or ""
		local base = tonumber(prompt:GetAttribute("HwReviveBase")) or 2.2
		local targetSpeed = tonumber(prompt:GetAttribute("HwTargetSpeed")) or 1
		local mySpeed = tonumber(player:GetAttribute("HwReviveSpeed")) or 1
		prompt.HoldDuration = base / math.max(.1, targetSpeed * mySpeed)
	end
	local function watchPrompt(inst: Instance)
		if inst:IsA("ProximityPrompt") and inst.Name == "HwRevivePrompt" and not prompts[inst] then
			prompts[inst] = true
			stylePrompt(inst)
			inst.AncestryChanged:Connect(function()
				if not inst:IsDescendantOf(workspace) then
					prompts[inst] = nil
				end
			end)
		end
	end
	local function watchCharacter(ch: Model)
		for _, d in ipairs(ch:GetDescendants()) do
			watchPrompt(d)
		end
		ch.DescendantAdded:Connect(watchPrompt)
	end
	local function watchPlayer(pl: Player)
		if pl.Character then
			watchCharacter(pl.Character)
		end
		pl.CharacterAdded:Connect(watchCharacter)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		watchPlayer(pl)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(removeMarker)
	local function restyleAll()
		for prompt in pairs(prompts) do
			stylePrompt(prompt)
		end
	end
	for _, a in ipairs({ "HwCombat", "HwDowned", "HwCombatZone", "HwReviveSpeed" }) do
		player:GetAttributeChangedSignal(a):Connect(restyleAll)
	end

	---------------------------------------------------------------------------------------------------------------
	-- wiring + the frame loop (bound only while something is drawn)
	---------------------------------------------------------------------------------------------------------------
	Bus.On("Signal", function(s)
		if type(s) ~= "table" or type(s.Data) ~= "table" then
			return
		end
		if s.Kind == "Hazard" then
			CombatFX.Receive(s.Data)
		elseif s.Kind == "Combat" and s.Data.Kind == "Hit" then
			onHit(s.Data)
		end
	end)

	local lastMarkers = 0
	RunService.Heartbeat:Connect(function()
		local hasWork = next(drawings) ~= nil or next(waiting) ~= nil or next(markers) ~= nil or player:GetAttribute("HwCombat") == true
		if not hasWork then
			return
		end
		local t = now()
		for id, w in pairs(waiting) do
			if t >= w.ShowAt then
				waiting[id] = nil
				create(w.Def, w.ShowAt)
			end
		end
		local r = myRoot()
		local me = r and r.Position or nil
		for _, dr in pairs(drawings) do
			local d = dr.Def
			if not dr.Dead then
				local ok, err = pcall(function()
					stepDrawing(dr, t, me)
					if not dr.Impacted and t >= d.ImpactAt then
						dr.Impacted = true
						impactFX(dr)
					end
				end)
				if not ok then
					warn("CombatFX: telegraph step failed: " .. tostring(err))
					destroy(dr)
				elseif t >= Hazards.EndAt(d) + .15 then
					destroy(dr, .3)
				end
			end
		end
		if os.clock() - lastMarkers >= 1 / 15 then
			lastMarkers = os.clock()
			local ok, err = pcall(stepMarkers, t)
			if not ok then
				warn("CombatFX: downed markers failed: " .. tostring(err))
			end
		end
	end)
	-- the HUD reads the drawings for its "inside a telegraph" edge warning
	CombatFX.Inside = function(): boolean
		local r = myRoot()
		if not r then
			return false
		end
		local t = now()
		for _, dr in pairs(drawings) do
			if not dr.Dead and t < dr.Def.ImpactAt and Hazards.Contains(dr.Def.Shape, r.Position, t - dr.Def.ImpactAt) then
				return true
			end
		end
		return false
	end
	CombatFX.Count = function(): number
		local n = 0
		for _ in pairs(drawings) do
			n += 1
		end
		return n
	end
end

return CombatFX
