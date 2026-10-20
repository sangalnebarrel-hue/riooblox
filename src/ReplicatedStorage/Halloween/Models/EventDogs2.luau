-- THE UNDERYARD · event dogs H09-H16 (ReplicatedStorage.Halloween.Models.EventDogs2, WP-K1; DESIGN §9.8).
-- Eight original voxel dogs on the exact rig contract of Models.EventDogs (H01-H08): the same Rig builder (bevelled
-- blocks, layered eyes, paws, tufts, FX hooks), the same skeleton names (Root > Body > Neck > Head > Jaw / Ear_L / Ear_R,
-- Tail > Tail2 > TailTip, Leg_* > Paw_* as the four lowest bones), the same DogBone / DogBoneOffset part binding and the
-- same procedural clip set (Idle / Walk / Run / DigStart / DigLoop / DigEnd / DigFind / Sniff / Sleep / Happy / RareFind
-- / Signature + the signature under the dog's own name), so every dog system (kennels, displays, previews, reveals,
-- DogAnimationPlayer, the Secret arrival) treats them exactly like the Chapter I dogs.
--   H09 HW_BellPup        Bell Pup         bronze bell collar, a lantern hanging from its curled tail (ECHO EAR)
--   H10 HW_CandleCorgi    Candle Corgi     wax-dripped corgi carrying three candles (CANDLELIGHT)
--   H11 HW_MourningShiba  Mourning Shiba   black lace veil and hat, glowing tears (MOURNING VEIL)
--   H12 HW_CoffinPug      Coffin Pug       a tiny coffin backpack whose lid flaps open (COFFIN SENSE)
--   H13 HW_MothHound      Moth Hound       lean hound with moth wings, feathered antennae, fluff ruff (MOTH SWARM)
--   H14 HW_Bridehound     Bridehound       silky hound in a tattered bridal veil with blue funeral roses (ETERNAL VOW)
--   H15 HW_BellkeeperWolf Bellkeeper Wolf  ash wolf, bell-rope sash with three bronze bells, violet eyes (RESONANT HOWL)
--   H16 HW_HollowKing     Hollow King      SECRET: hollow-ribbed regal dog, violet flame crown, moth-wing cape,
--                                          black moon pendant (CROWN OF THE UNDERYARD)
-- How it plugs in: requiring this module registers the eight specs in Models.EventDogs.Specs, so EventDogs.Build /
-- Clip / Duration / ClipNamesFor / StartFX / BurstFX work for the new ids too (EventDogs.Order, the Chapter I list,
-- is untouched). EventDogs2.Build stamps EventDex = "Underyard2026". The place build (tools/edits/30_dogs2.luau) saves
-- ServerStorage.DogTemplates.<Id>, ReplicatedStorage.MenuModels.<Id> and the clip ModuleScripts
-- ReplicatedStorage.DogAnimationClips.<Id>.<clip>. Ability FX hooks only use the recipes of Models.EventDogs, so the
-- existing callers (kennel dig bursts, dig spots, the boss companion, previews) light them up unchanged.
local E = require(script.Parent.EventDogs)

local D = {}
D.Version = 1
D.EventDex = "Underyard2026"
D.Generated = "WP-K1 EventDogs2 v1"
D.Order = { "HW_BellPup", "HW_CandleCorgi", "HW_MourningShiba", "HW_CoffinPug", "HW_MothHound", "HW_Bridehound",
	"HW_BellkeeperWolf", "HW_HollowKing" }
D.ClipNames = E.ClipNames
D.FPS = E.FPS
D.Base = E

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local MAT = Enum.Material
local PI = math.pi
local TAU = 2 * PI
local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local Mth = E.Math
local sinU, smooth, bump, rise, hold, flick = Mth.sinU, Mth.smooth, Mth.bump, Mth.rise, Mth.hold, Mth.flick

---------------------------------------------------------------------------------------------------------------------
-- Shared helpers (the skeleton conventions of Models.EventDogs)
---------------------------------------------------------------------------------------------------------------------
-- the tail chain (Tail > Tail2 > TailTip): a wave that travels to the tip
local function tail(add, pitch: number, amp: number, x: number, k: number, lag: number?)
	local l: number = lag or 0.09
	add("Tail", 0, 0, 0, pitch, amp * math.sin(TAU * k * x), 0)
	add("Tail2", 0, 0, 0, pitch * 0.3, amp * 0.8 * math.sin(TAU * (k * x - l)), 0)
	add("TailTip", 0, 0, 0, pitch * 0.2, amp * 0.7 * math.sin(TAU * (k * x - 2 * l)), 0)
end

-- a standard quadruped skeleton: legs at x = ±lx, front z = fz, hind z = hz, hips at hipY, paws at pawY
local function legBones(list, lx: number, fz: number, hz: number, hipY: number, pawY: number, dz: number?)
	for _, l in ipairs({ { "FL", 1, fz }, { "FR", -1, fz }, { "BL", 1, hz }, { "BR", -1, hz } }) do
		table.insert(list, { "Leg_" .. l[1], "Body", V3(l[2] * lx, hipY, l[3]) })
		table.insert(list, { "Paw_" .. l[1], "Leg_" .. l[1], V3(l[2] * lx, pawY, l[3] + (dz or 0)) })
	end
	return list
end
local LEG_TAGS = { { "FL", 1, true }, { "FR", -1, true }, { "BL", 1, false }, { "BR", -1, false } }

-- Continuous motions (flames, veils, antennae) run in every clip except DigStart / DigEnd: EventDogs.Clip blends the
-- dig loop's extras into those two, so skipping them there makes the kennel chain join exactly.
local function ambient(clip: string): boolean
	return clip ~= "DigStart" and clip ~= "DigEnd"
end

-- every leg at once: a front value and a hind value (rx), optional splay (rz, mirrored per side)
local function legs(add, front: number, hind: number, splay: number?)
	for _, l in ipairs(LEG_TAGS) do
		add("Leg_" .. l[1], 0, 0, 0, l[3] and front or hind, 0, (splay or 0) * l[2])
	end
end

-- sitting back on the haunches (k = 0..1): the body drops and tips up, the hind legs fold forward under it
local function sit(add, k: number, drop: number)
	add("Body", 0, -drop * k, 0.1 * k, 0.32 * k, 0, 0)
	add("Leg_BL", 0, 0, 0, 0.85 * k, 0, 0)
	add("Leg_BR", 0, 0, 0, 0.85 * k, 0, 0)
	add("Paw_BL", 0, 0, 0, -1.0 * k, 0, 0)
	add("Paw_BR", 0, 0, 0, -1.0 * k, 0, 0)
	add("Leg_FL", 0, 0, 0, -0.28 * k, 0, 0)
	add("Leg_FR", 0, 0, 0, -0.28 * k, 0, 0)
end

-- A cast bell hanging from `top` (its loop), mouth down: crown, waisted body, flared lip, dark mouth, clapper.
-- Returns the body part (for lights / hooks).
local function bell(r, bone: string, name: string, top: Vector3, d: number, body: Color3, hi: Color3, lo: Color3, rune: Color3?)
	r:Box(bone, name .. "Loop", V3(d * 0.2, d * 0.22, d * 0.07), top - V3(0, d * 0.09, 0), lo, MAT.Metal)
	r:Round(bone, name .. "Crown", V3(d * 0.52, d * 0.2, d * 0.52), top - V3(0, d * 0.27, 0), hi, MAT.Metal, d * 0.05)
	local main = r:Round(bone, name .. "Body", V3(d * 0.74, d * 0.5, d * 0.74), top - V3(0, d * 0.6, 0), body, MAT.Metal, d * 0.1, hi)
	r:Round(bone, name .. "Lip", V3(d, d * 0.16, d), top - V3(0, d * 0.92, 0), body, MAT.Metal, d * 0.04, lo)
	r:Box(bone, name .. "Mouth", V3(d * 0.78, d * 0.03, d * 0.78), top - V3(0, d * 1.0, 0), C(30, 20, 14))
	r:Ball(bone, name .. "Clapper", d * 0.2, top - V3(0, d * 1.05, 0), lo, MAT.Metal)
	r:Box(bone, name .. "Shine", V3(d * 0.12, d * 0.32, d * 0.05), top + V3(d * 0.2, -d * 0.6, -d * 0.36), C(255, 236, 190), MAT.Metal)
	if rune then
		r:Neon(bone, name .. "Rune", V3(d * 0.78, d * 0.05, d * 0.78), top - V3(0, d * 0.7, 0), rune)
	end
	return main
end

-- An upward flame of `steps` stacked neon blocks rooted at `base` (a Tuft turned up), with a hot core.
local function flame(r, bone: string, name: string, base: Vector3, len: number, w: number, outer: Color3, inner: Color3, core: Color3?)
	r:Tuft(bone, name, CF(base) * ANG(PI, 0, 0), len, w, 3, outer, inner, MAT.Neon)
	if core then
		return r:Neon(bone, name .. "Core", V3(w * 0.45, len * 0.32, w * 0.45), base + V3(0, len * 0.2, 0), core)
	end
	return nil
end

-- A small rose: a bud wrapped in four turned petals and two leaves, facing `facing` (CFrame rotation; the rose looks
-- along its -Z). s = size.
local function rose(r, bone: string, name: string, at: Vector3, s: number, petal: Color3, petalHi: Color3, petalLo: Color3, leaf: Color3, facing: CFrame?)
	local base = CF(at) * (facing or CF())
	r:Box(bone, name .. "Bud", V3(s * 0.42, s * 0.42, s * 0.5), base * CF(0, 0, -s * 0.12) * ANG(0, 0, PI / 4), petalHi)
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		r:Box(bone, name .. "Petal" .. i, V3(s * 0.46, s * 0.34, s * 0.3), base * CF(math.cos(a) * s * 0.26, math.sin(a) * s * 0.26, 0) * ANG(0, 0, a),
			i % 2 == 0 and petal or petalLo)
	end
	r:Box(bone, name .. "Heart", V3(s * 0.16, s * 0.16, s * 0.1), base * CF(0, 0, -s * 0.38), petalLo)
	for i, sx in ipairs({ -1, 1 }) do
		r:Box(bone, name .. "Leaf" .. i, V3(s * 0.5, s * 0.08, s * 0.28), base * CF(sx * s * 0.42, -s * 0.3, s * 0.1) * ANG(0, 0, sx * 0.5), leaf)
	end
end

-- A triangle in the plane of `frame` (wing coordinates {u, v}: u along the wing, v across it): apex `a`, base b..c
-- (isosceles fit: the Rig:Tri of the bat wings of Models.EventDogs).
local function panel(r, bone: string, name: string, frame: CFrame, a, b, c, th: number, color: Color3, mat)
	local m = { (b[1] + c[1]) / 2, (b[2] + c[2]) / 2 }
	local du, dv = a[1] - m[1], a[2] - m[2]
	local h = math.sqrt(du * du + dv * dv)
	local w = math.sqrt((b[1] - c[1]) ^ 2 + (b[2] - c[2]) ^ 2)
	local mid = (frame * CF((a[1] + m[1]) / 2, (a[2] + m[2]) / 2, 0)).Position
	local turn = frame.Rotation * ANG(0, 0, math.atan2(dv, du) - PI / 2)
	r:Tri(bone, name, mid, w, h, th, color, mat, false, turn)
end

-- A moth wing in the plane of `frame` (local X = out along the wing, local Y = toward its leading edge, thin in Z):
-- a triangular forewing (root, apex, tornus) in two tones, a dark costa and outer margin, a pale fringe and an
-- eyespot (ring + iris + glowing pupil) that shows on both faces. o.Round = a rounder hindwing outline.
-- Returns the outer-margin part (for hooks).
local function mothWing(r, bone: string, name: string, frame: CFrame, len: number, wid: number, o: any)
	local th = o.Thick or 0.05
	local function P(p): Vector3
		return (frame * CF(p[1], p[2], 0)).Position
	end
	local root = { 0, 0 }
	local apex = o.Round and { len, -wid * 0.12 } or { len, wid * 0.32 }
	local tornus = o.Round and { len * 0.46, -wid * 0.92 } or { len * 0.7, -wid * 0.7 }
	panel(r, bone, name .. "Web", frame, root, apex, tornus, th, o.Main, o.Mat)
	local k = 0.62
	panel(r, bone, name .. "Inner", frame, root, { apex[1] * k, apex[2] * k }, { tornus[1] * k, tornus[2] * k }, th + 0.012, o.Dark, o.Mat)
	if o.Round then
		-- a rounded lobe under the hindwing
		local lobe = { len * 0.7, -wid * 0.62 }
		panel(r, bone, name .. "Lobe", frame, root, apex, lobe, th - 0.005, o.Main, o.Mat)
	end
	local margin = r:Seg(bone, name .. "Margin", P(apex), P(tornus), 0.13, th + 0.02, o.Dark, o.Mat)
	r:Seg(bone, name .. "Costa", P({ len * 0.1, apex[2] * 0.1 }), P(apex), 0.07, th + 0.02, o.Dark, o.Mat)
	for i = 1, 3 do
		local q = { apex[1] + (tornus[1] - apex[1]) * (i / 4), apex[2] + (tornus[2] - apex[2]) * (i / 4) }
		local out = { q[1] + 0.06, q[2] - 0.04 }
		r:Box(bone, name .. "Fringe" .. i, V3(0.12, 0.12, th + 0.03), CF(P(out)) * frame.Rotation * ANG(0, 0, PI / 4), o.Fringe, o.Mat)
	end
	local ex = o.EyeAt or { 0.56, -0.1 }
	local e = { len * ex[1], wid * ex[2] }
	local ew = wid * (o.EyeK or 0.42)
	r:Box(bone, name .. "EyeRing", V3(ew, ew, th + 0.04), CF(P(e)) * frame.Rotation * ANG(0, 0, PI / 4), o.Ring, o.Mat)
	r:Box(bone, name .. "EyeIn", V3(ew * 0.62, ew * 0.62, th + 0.06), CF(P(e)) * frame.Rotation * ANG(0, 0, PI / 4), o.Iris, o.Mat)
	r:Neon(bone, name .. "Pupil", V3(ew * 0.26, ew * 0.26, th + 0.08), CF(P({ e[1] + ew * 0.06, e[2] + ew * 0.06 })) * frame.Rotation, o.Glow)
	if o.Edge then
		r:Seg(bone, name .. "Edge", P({ apex[1] + 0.05, apex[2] + 0.03 }), P({ tornus[1] + 0.04, tornus[2] - 0.05 }), 0.05, th + 0.03, o.Edge, MAT.Neon,
			{ Transparency = 0.1 })
	end
	return margin
end

---------------------------------------------------------------------------------------------------------------------
-- Dog specs (same fields as Models.EventDogs: Code, SignatureName, Bones, Durations, Motion, Extra, Build)
---------------------------------------------------------------------------------------------------------------------
local SPECS = {}
D.Specs = SPECS

---------------------------------------------------------------- H09 BELL PUP (Rare)
do
	local FUR, FUR_HI, FUR_LO = C(186, 198, 226), C(214, 224, 246), C(140, 150, 192)
	local EAR, EAR_LO, EAR_HI = C(98, 98, 146), C(72, 70, 112), C(128, 128, 178)
	local CREAM, CREAM_LO, NOSE, PINK = C(250, 248, 242), C(224, 224, 238), C(52, 44, 66), C(244, 134, 156)
	local COLLAR, COLLAR_HI, GOLD = C(104, 54, 150), C(140, 86, 190), C(246, 200, 96)
	local BRONZE, BRONZE_HI, BRONZE_LO = C(206, 142, 62), C(242, 194, 108), C(140, 88, 36)
	local IRON, CANDLE, CANDLE_HOT, GLASS = C(58, 54, 70), C(255, 170, 80), C(255, 238, 170), C(255, 214, 150)
	local LAMP = V3(0, 3.0, 1.06)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 1.62, 0.25) },
		{ "Neck", "Body", V3(0, 2.2, -0.72) },
		{ "Bell", "Neck", V3(0, 1.98, -1.2) },
		{ "Head", "Neck", V3(0, 2.55, -1.05) },
		{ "Jaw", "Head", V3(0, 2.62, -2.05) },
		{ "Ear_L", "Head", V3(0.92, 3.86, -1.2) },
		{ "Ear_R", "Head", V3(-0.92, 3.86, -1.2) },
		{ "Tail", "Body", V3(0, 2.05, 1.25) },
		{ "Tail2", "Tail", V3(0, 2.65, 1.5) },
		{ "TailTip", "Tail2", V3(0, 3.28, 1.38) },
		{ "Lamp", "TailTip", V3(0, 3.38, 1.06) },
		{ "Wick", "Lamp", LAMP },
	}
	legBones(bones, 0.5, -0.42, 1.0, 1.15, 0.3, -0.04)
	SPECS.HW_BellPup = {
		Code = "H09",
		SignatureName = "BellJingle",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.2 },
		Motion = { Breath = 0.04, Wag = 0.42, Stride = 0.5, Hop = 0.6, Look = 0.24 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the candle in the lantern never sits still
			if ambient(clip) then
				add("Wick", 0.01 * sinU(x, 11), 0.02 * (flick(x, looped and 7 or 9) - 0.5), 0, 0, TAU * (looped and 1 or 0.5) * x, 0)
			end
			if clip == "Idle" then
				-- ECHO EAR: it hears something, one ear perks up, the head tilts, then it relaxes; the bell tinkles once
				local perk = bump(u, 0.22, 0.48)
				add("Ear_L", 0, 0, 0, -0.15 * perk, 0, 0.6 * perk)
				add("Ear_R", 0, 0, 0, 0, 0, -0.12 * perk + 0.05 * sinU(u, 2))
				add("Head", 0, 0, 0, 0.04 * perk, 0.1 * perk, 0.22 * perk)
				local ting = bump(u, 0.6, 0.74)
				add("Bell", 0, 0, 0, 0.1 * sinU(u, 2) + 0.3 * ting * math.sin(TAU * 6 * (u - 0.6) / 0.14), 0, 0.12 * ting * math.sin(TAU * 4 * u))
				add("Lamp", 0, 0, 0, 0.14 * sinU(u, 1, 0.2), 0, 0.08 * sinU(u, 1))
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				local a = clip == "Run" and 1.6 or 1
				add("Bell", 0, 0, 0, 0.34 * a * sinU(u, k, 0.25), 0, 0.1 * sinU(u, 1))
				add("Ear_L", 0, 0, 0, 0.1 * a, 0, 0.22 * a * sinU(u, k, 0.15))
				add("Ear_R", 0, 0, 0, 0.1 * a, 0, -0.22 * a * sinU(u, k, 0.15))
				add("Lamp", 0, 0, 0, -0.3 * a * sinU(u, k, 0.35), 0, 0.1 * sinU(u, 1))
			elseif clip == "DigLoop" then
				add("Bell", 0, 0, 0, 0.3 * sinU(u, 2), 0, 0.1 * sinU(u, 1))
				add("Ear_L", 0, 0, 0, 0.35, 0, 0.1 * sinU(u, 1))
				add("Ear_R", 0, 0, 0, 0.35, 0, -0.1 * sinU(u, 1))
				add("Lamp", 0, 0, 0, 0.25 * sinU(u, 1), 0, 0.18 * sinU(u, 1, 0.25))
			elseif clip == "Sleep" then
				add("Ear_L", 0, 0, 0, 0, 0, -0.08)
				add("Ear_R", 0, 0, 0, 0, 0, 0.08)
				add("Lamp", 0, 0, 0, 0.05 * sinU(u, 1), 0, 0)
				add("Bell", 0, 0, 0, 0.3, 0, 0)
			elseif clip == "Sniff" then
				local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
				add("Ear_L", 0, 0, 0, 0.3 * down, 0, 0.1 * math.sin(TAU * 1.2 * t) * down)
				add("Ear_R", 0, 0, 0, 0.3 * down, 0, -0.1 * math.sin(TAU * 1.2 * t) * down)
				add("Bell", 0, 0, 0, 0.35 * down, 0, 0.15 * math.sin(TAU * 1.4 * t) * down)
				add("Lamp", 0, 0, 0, 0.2 * math.sin(TAU * 0.8 * t), 0, 0)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				-- the bell rings out, the ears flap, the lantern swings round
				local joy = bump(t, 0.05, d - 0.05)
				add("Bell", 0, 0, 0, 0.55 * math.sin(TAU * 5 * t / d) * joy, 0, 0.3 * math.sin(TAU * 7 * t / d) * joy)
				add("Ear_L", 0, 0, 0, 0, 0, 0.45 * (0.5 + 0.5 * math.sin(TAU * 4 * t / d)) * joy)
				add("Ear_R", 0, 0, 0, 0, 0, -0.45 * (0.5 + 0.5 * math.sin(TAU * 4 * t / d)) * joy)
				add("Lamp", 0, 0, 0, 0.45 * math.sin(TAU * 3 * t / d) * joy, 0, 0.25 * math.sin(TAU * 2 * t / d) * joy)
			elseif clip == "Signature" then
				-- BELL JINGLE: it listens (head tilt, one ear up), shakes its head so the bell rings like mad, then two
				-- proud hops with the lantern held high
				local listen = hold(t, 0.1, 0.4, 0.85, 1.05)
				add("Head", 0, 0, 0, 0.06 * listen, 0.14 * listen, 0.3 * listen)
				add("Ear_L", 0, 0, 0, -0.2 * listen, 0, 0.85 * listen)
				add("Ear_R", 0, 0, 0, 0, 0, -0.15 * listen)
				local shake = bump(t, 1.05, 2.0)
				local w = math.sin(TAU * 7 * t)
				add("Head", 0, 0, 0, 0, 0.45 * w * shake, 0.12 * w * shake)
				add("Neck", 0, 0, 0, 0, 0.18 * w * shake, 0)
				add("Ear_L", 0, 0, 0, 0, 0, 0.7 * math.sin(TAU * 7 * t + 0.7) * shake)
				add("Ear_R", 0, 0, 0, 0, 0, 0.7 * math.sin(TAU * 7 * t + 0.7) * shake)
				add("Bell", 0, 0, 0, 0.7 * math.sin(TAU * 5 * t) * shake, 0, 0.4 * math.sin(TAU * 7 * t + 1) * shake)
				local hop = bump(t, 2.05, 2.55) + 0.6 * bump(t, 2.6, 3.05)
				add("Body", 0, 0.5 * hop, 0, 0.1 * hop, 0, 0)
				legs(add, 0.5 * hop, -0.45 * hop)
				add("Bell", 0, 0, 0, -0.3 * hop, 0, 0)
				add("Ear_L", 0, 0, 0, 0, 0, 0.35 * hop)
				add("Ear_R", 0, 0, 0, 0, 0, -0.35 * hop)
				add("Jaw", 0, 0, 0, -0.28 * bump(t, 1.0, d - 0.05), 0, 0)
				add("Lamp", 0, 0, 0, 0.5 * math.sin(TAU * 3 * t / d) * bump(t, 1.0, d), 0, 0.2 * math.sin(TAU * 2 * t / d) * bump(t, 1.0, d))
				tail(add, 0.3 * bump(t, 1.9, d), 0.6 * bump(t, 1.9, d), t / d, 7)
			end
		end,
		Build = function(r)
			-------- a round little pup in moon-silver fur: cream chest fluff, a slate spot on its back
			r:Round("Body", "Torso", V3(1.46, 1.24, 2.0), V3(0, 1.66, 0.28), FUR, nil, 0.24, FUR_HI)
			r:Round("Body", "Rump", V3(1.36, 1.06, 0.36), V3(0, 1.7, 1.3), FUR, nil, 0.14, FUR_HI)
			r:Box("Body", "Belly", V3(1.0, 0.08, 1.5), V3(0, 1.03, 0.3), CREAM)
			r:Tuft("Body", "Fluff", CF(0, 2.16, -0.74), 0.86, 0.92, 3, CREAM, CREAM_LO)
			r:Round("Body", "BackSpot", V3(0.86, 0.08, 0.96), V3(0.18, 2.29, 0.55), EAR, nil, 0.03)
			r:Box("Body", "FlankSpot", V3(0.04, 0.38, 0.52), V3(0.735, 1.82, 0.72), EAR)
			r:Box("Body", "FlankSpotB", V3(0.04, 0.22, 0.26), V3(-0.735, 1.9, 0.2), EAR)
			-------- stubby legs, cream paws with pink beans
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.5, front and -0.42 or 1.0
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.44, 0.78, 0.46), V3(x, 0.7, z), FUR, nil, 0.09)
				if front then
					r:Round(leg, "Shoulder_" .. tag, V3(0.52, 0.5, 0.58), V3(x, 1.2, z), FUR, nil, 0.12, FUR_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.56, 0.7, 0.72), V3(x + s * 0.02, 1.26, z + 0.04), FUR, nil, 0.16, FUR_HI)
				end
				r:Paw(paw, tag, x, z - 0.05, 0.54, 0.58, 0.3, CREAM, { Toe = CREAM, Bean = PINK })
			end
			-------- neck with a plum collar, gold studs, and the bronze bell (Bell bone swings it)
			r:Round("Neck", "Neck", V3(0.88, 0.6, 0.76), V3(0, 2.2, -0.72), FUR, nil, 0.14)
			r:Round("Neck", "Collar", V3(0.98, 0.18, 0.86), V3(0, 2.05, -0.74), COLLAR, MAT.Fabric, 0.04, COLLAR_HI)
			r:Pair(function(s, side)
				r:Box("Neck", "Stud_" .. side, V3(0.06, 0.08, 0.08), V3(s * 0.49, 2.05, -0.86), GOLD, MAT.Metal)
				r:Box("Neck", "StudB_" .. side, V3(0.08, 0.08, 0.06), V3(s * 0.3, 2.05, -1.17), GOLD, MAT.Metal)
			end)
			local bellBody = bell(r, "Bell", "Bell", V3(0, 1.98, -1.22), 0.52, BRONZE, BRONZE_HI, BRONZE_LO)
			-------- the big round head: a cream blaze, a button nose, huge starry eyes, a curl on top
			r:Round("Head", "Cranium", V3(1.84, 1.5, 1.6), V3(0, 3.28, -1.32), FUR, nil, 0.3, FUR_HI)
			r:Round("Head", "Cheeks", V3(1.96, 0.84, 1.2), V3(0, 2.92, -1.5), FUR, nil, 0.22)
			r:Box("Head", "Blaze", V3(0.3, 0.86, 0.05), V3(0, 3.4, -2.13), CREAM)
			r:Box("Head", "BlazeTop", V3(0.5, 0.3, 0.05), V3(0, 3.78, -2.1), CREAM)
			r:Round("Head", "Muzzle", V3(0.98, 0.56, 0.52), V3(0, 2.82, -2.3), CREAM, nil, 0.14)
			r:Round("Head", "Nose", V3(0.38, 0.24, 0.2), V3(0, 3.02, -2.6), NOSE, nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.1, 0.05, 0.03), V3(0.08, 3.1, -2.71), C(200, 196, 220))
			r:Box("Head", "MouthLine", V3(0.04, 0.12, 0.03), V3(0, 2.86, -2.57), NOSE)
			r:Pair(function(s, side)
				r:Box("Head", "Smile_" .. side, V3(0.18, 0.04, 0.03), CF(s * 0.09, 2.78, -2.565) * ANG(0, 0, s * 0.35), NOSE)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.46, 3.32, -2.12), 0.44, 0.5,
					{ Rim = FUR_LO, White = C(252, 252, 255), Iris = C(66, 74, 154), Pupil = C(18, 16, 36), IrisK = 0.8, Look = V3(s * 0.02, -0.02, 0) })
				r:Neon("Head", "EyeSpark_" .. side, V3(0.06, 0.06, 0.03), V3(s * 0.46 - 0.1, 3.2, -2.29), C(255, 255, 255))
				r:Box("Head", "Brow_" .. side, V3(0.22, 0.07, 0.05), CF(s * 0.46, 3.66, -2.13) * ANG(0, 0, -s * 0.22), FUR_LO)
				r:Box("Head", "Blush_" .. side, V3(0.24, 0.08, 0.03), V3(s * 0.7, 2.98, -2.115), C(250, 168, 196))
			end)
			-- a soft forelock curling forward over the blaze
			r:Round("Head", "Forelock", V3(0.46, 0.2, 0.5), V3(0.06, 4.08, -1.72), FUR_HI, nil, 0.06)
			r:Round("Head", "ForelockCurl", V3(0.3, 0.22, 0.26), CF(0.12, 4.08, -2.02) * ANG(0.5, 0, 0), FUR_HI, nil, 0.06)
			r:Box("Head", "ForelockTip", V3(0.18, 0.16, 0.14), CF(0.14, 3.96, -2.14) * ANG(0.9, 0, 0), CREAM)
			-------- long floppy ears (ECHO EAR): slate velvet with a lighter stripe
			r:Pair(function(s, side)
				local ear = "Ear_" .. side
				local flap = CF(s * 1.02, 3.18, -1.2) * ANG(0, 0, s * 0.12)
				r:Round(ear, "EarBase_" .. side, V3(0.3, 0.32, 0.62), V3(s * 0.96, 3.8, -1.2), EAR, nil, 0.06)
				r:Round(ear, "Ear_" .. side, V3(0.22, 1.3, 0.72), flap, EAR, nil, 0.07, EAR_HI)
				r:Box(ear, "EarTip_" .. side, V3(0.24, 0.32, 0.66), flap * CF(0, -0.52, 0), EAR_LO)
				r:Box(ear, "EarStripe_" .. side, V3(0.04, 0.86, 0.12), flap * CF(s * 0.11, 0.06, -0.16), EAR_HI)
			end)
			-------- jaw: chin and a little pink tongue
			r:Round("Jaw", "Chin", V3(0.7, 0.18, 0.42), V3(0, 2.5, -2.26), CREAM_LO, nil, 0.05)
			r:Box("Jaw", "Tongue", V3(0.22, 0.05, 0.24), CF(0.06, 2.56, -2.42) * ANG(-0.3, 0, 0), PINK)
			-------- the curled tail holds a little lantern over its back (Lamp swings on the tip, Wick flickers)
			r:Seg("Tail", "TailA", V3(0, 2.02, 1.32), V3(0, 2.66, 1.56), 0.3, 0.3, FUR)
			r:Seg("Tail2", "TailB", V3(0, 2.64, 1.55), V3(0, 3.28, 1.42), 0.26, 0.26, FUR)
			r:Seg("TailTip", "TailC", V3(0, 3.26, 1.44), V3(0, 3.42, 1.12), 0.22, 0.22, FUR_HI)
			r:Round("TailTip", "TailFluff", V3(0.3, 0.26, 0.26), V3(0, 3.44, 1.06), CREAM, nil, 0.06)
			r:Box("Lamp", "LampHook", V3(0.05, 0.16, 0.05), V3(0, 3.3, 1.06), IRON, MAT.Metal)
			r:Box("Lamp", "LampRing", V3(0.16, 0.14, 0.04), V3(0, 3.2, 1.06), IRON, MAT.Metal)
			r:Box("Lamp", "LampRoof", V3(0.2, 0.08, 0.2), V3(0, 3.12, 1.06), IRON, MAT.Metal)
			r:Box("Lamp", "LampCap", V3(0.36, 0.08, 0.36), V3(0, 3.05, 1.06), BRONZE, MAT.Metal)
			r:Box("Lamp", "LampGlass", V3(0.28, 0.32, 0.28), V3(0, 2.85, 1.06), GLASS, MAT.Glass, { Transparency = 0.4 })
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					r:Box("Lamp", "LampPost" .. sx .. sz, V3(0.05, 0.34, 0.05), V3(sx * 0.15, 2.85, 1.06 + sz * 0.15), IRON, MAT.Metal)
				end
			end
			r:Box("Lamp", "LampBase", V3(0.36, 0.08, 0.36), V3(0, 2.65, 1.06), BRONZE, MAT.Metal)
			r:Box("Lamp", "LampFoot", V3(0.2, 0.06, 0.2), V3(0, 2.59, 1.06), BRONZE_LO, MAT.Metal)
			local candle = r:Neon("Wick", "LampFlame", V3(0.12, 0.18, 0.12), LAMP - V3(0, 0.13, 0), CANDLE)
			r:Neon("Wick", "LampFlameHot", V3(0.06, 0.1, 0.06), LAMP - V3(0, 0.16, 0), CANDLE_HOT)
			r:Light(candle, CANDLE, 8, 1.1)
			-------- ability FX hooks (ECHO EAR): warm embers off the lantern, golden ringing sparkles off the bell
			r:Hook(candle, "Lantern", "Embers", LAMP - V3(0, 0.05, 0), CANDLE, C(255, 120, 40), 4, 0)
			r:Hook(bellBody, "Bell", "Stars", V3(0, 1.5, -1.3), C(255, 220, 120), BRONZE_HI, 3, 0)
		end,
	}
end

---------------------------------------------------------------- H10 CANDLE CORGI (Epic)
do
	local FUR, FUR_HI, FUR_LO = C(224, 134, 62), C(240, 162, 92), C(182, 100, 44)
	local WHITE, WHITE_LO, NOSE, PINK = C(252, 248, 238), C(230, 222, 206), C(40, 28, 26), C(240, 110, 124)
	local WAX, WAX_HI, WAX_LO = C(246, 236, 210), C(255, 251, 238), C(220, 204, 170)
	local CANDLE, CANDLE_HOT, WICK = C(255, 170, 80), C(255, 240, 170), C(36, 28, 24)
	local SEAL, SEAL_LO, RIBBON = C(196, 44, 56), C(140, 26, 36), C(150, 40, 52)
	-- candles: {x, z, height, width, flame length}
	local CANDLES = { { 0.34, -0.15, 0.92, 0.36, 0.42 }, { -0.36, 0.55, 0.62, 0.32, 0.34 }, { 0.14, 1.2, 0.4, 0.3, 0.3 } }
	local SADDLE = 2.33
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 1.5, 0.35) },
		{ "Neck", "Body", V3(0, 2.05, -1.12) },
		{ "Head", "Neck", V3(0, 2.45, -1.45) },
		{ "Jaw", "Head", V3(0, 2.4, -2.5) },
		{ "Ear_L", "Head", V3(0.44, 3.42, -1.55) },
		{ "Ear_R", "Head", V3(-0.44, 3.42, -1.55) },
		{ "Tail", "Body", V3(0, 1.98, 1.95) },
		{ "Tail2", "Tail", V3(0, 2.12, 2.2) },
		{ "TailTip", "Tail2", V3(0, 2.22, 2.4) },
	}
	for i, c in ipairs(CANDLES) do
		local top = SADDLE + c[3]
		table.insert(bones, { "Flame_" .. i, "Body", V3(c[1], top + 0.06, c[2]) })
		table.insert(bones, { "Flare_" .. i, "Body", V3(c[1], SADDLE + 0.04, c[2]) })
	end
	legBones(bones, 0.56, -0.72, 1.42, 1.0, 0.28, -0.04)
	local function flames(add, x: number, looped: boolean, lean: number, low: number)
		for i = 1, #CANDLES do
			add("Flame_" .. i, 0.015 * sinU(x, 9 + 2 * i, 0.3 * i), 0.025 * (flick(x, (looped and 7 or 9) + i, 0.21 * i) - 0.5) - low, 0,
				lean + 0.12 * sinU(x, 5 + i, 0.13 * i), 0.5 * sinU(x, 3, 0.2 * i), 0.12 * sinU(x, 6 + i, 0.1))
		end
	end
	local function flares(add, k: number, x: number)
		for i, c in ipairs(CANDLES) do
			-- the tall flare hides inside its candle (k = 0) and climbs out of the wick (k = 1)
			add("Flare_" .. i, 0, (c[3] - 0.02) * k, 0, 0.1 * math.sin(TAU * (4 + i) * x) * k, 0.6 * math.sin(TAU * 2 * x + i) * k, 0)
		end
	end
	SPECS.HW_CandleCorgi = {
		Code = "H10",
		SignatureName = "CandleSploot",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.6 },
		Motion = { Breath = 0.05, Wag = 0.55, Stride = 0.55, Hop = 0.45, Look = 0.22, HipY = 1.0 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			if clip == "Idle" then
				flames(add, u, true, 0, 0)
				-- a corgi butt wiggle
				local wig = bump(u, 0.62, 0.82)
				add("Body", 0, 0, 0, 0, 0.05 * math.sin(TAU * 10 * u) * wig, 0.04 * math.sin(TAU * 10 * u) * wig)
				tail(add, 0.1, 0.9 * wig, u, 10)
			elseif clip == "Walk" or clip == "Run" then
				flames(add, u, true, clip == "Run" and 0.55 or 0.28, 0)
				add("Body", 0, 0, 0, 0, 0, 0.05 * sinU(u, clip == "Run" and 1 or 2, 0.25))
			elseif clip == "DigLoop" then
				flames(add, u, true, -0.15, 0)
			elseif clip == "Sleep" then
				-- the candles burn low while it sleeps
				flames(add, u, true, 0, 0.13)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				flames(add, x, false, 0, 0)
				local a, b = 0.1, d - 0.1
				flares(add, hold(t, a, a + 0.3, b - 0.35, b), x)
			elseif clip == "Signature" then
				-- CANDLE SPLOOT: it flops into a proud sploot (hind legs straight back), the candles flare up tall, it looks
				-- back at them over its shoulder with a panting grin, then pops back up
				flames(add, x, false, 0, 0)
				local down = hold(t, 0.2, 0.65, 2.65, 3.15)
				add("Body", 0, -0.55 * down, 0.05 * down, -0.04 * down, 0, 0)
				add("Leg_BL", 0, 0, 0, -1.45 * down, 0, 0.12 * down)
				add("Leg_BR", 0, 0, 0, -1.45 * down, 0, -0.12 * down)
				add("Paw_BL", 0, 0, 0, -0.35 * down, 0, 0)
				add("Paw_BR", 0, 0, 0, -0.35 * down, 0, 0)
				add("Leg_FL", 0, 0, 0, 1.15 * down, 0, -0.08 * down)
				add("Leg_FR", 0, 0, 0, 1.15 * down, 0, 0.08 * down)
				add("Paw_FL", 0, 0, 0, -0.45 * down, 0, 0)
				add("Paw_FR", 0, 0, 0, -0.45 * down, 0, 0)
				local look = hold(t, 1.2, 1.6, 2.2, 2.6)
				add("Neck", 0, 0, 0, 0.1 * down, 0.7 * look, 0)
				add("Head", 0, 0, 0, -0.1 * down + 0.15 * look, 0.5 * look, 0.12 * look)
				add("Jaw", 0, 0, 0, -0.22 * bump(t, 0.3, d - 0.1) - 0.05 * math.sin(TAU * 6 * t) * down, 0, 0)
				add("Ear_L", 0, 0, 0, -0.25 * down, 0, 0)
				add("Ear_R", 0, 0, 0, -0.25 * down, 0, 0)
				flares(add, hold(t, 0.75, 1.15, 2.3, 2.75), x)
				local pop = bump(t, 3.0, d)
				add("Body", 0, 0.25 * pop, 0, 0, 0, 0)
				tail(add, 0.2, 0.8 * bump(t, 0.3, d - 0.05), t / d, 9)
			elseif ambient(clip) then
				flames(add, x, looped, 0, 0)
			end
		end,
		Build = function(r)
			-------- a long low red-and-white corgi with a heart-shaped fluffy rump
			r:Round("Body", "Torso", V3(1.66, 1.2, 3.0), V3(0, 1.6, 0.35), FUR, nil, 0.26, FUR_HI)
			r:Round("Body", "Chest", V3(1.3, 1.0, 0.3), V3(0, 1.56, -1.18), WHITE, nil, 0.1)
			r:Box("Body", "Belly", V3(1.2, 0.08, 2.5), V3(0, 0.99, 0.35), WHITE)
			r:Pair(function(s, side)
				r:Box("Body", "Underside_" .. side, V3(0.05, 0.3, 2.3), V3(s * 0.835, 1.18, 0.3), WHITE)
			end)
			r:Round("Body", "Rump", V3(1.5, 0.92, 0.28), V3(0, 1.64, 1.9), FUR_HI, nil, 0.12)
			r:Pair(function(s, side)
				r:Round("Body", "Cheek_" .. side, V3(0.66, 0.5, 0.12), V3(s * 0.36, 1.42, 2.06), WHITE, nil, 0.05)
			end)
			-------- a saddle of candle wax poured over its back, dripping down both flanks
			r:Round("Body", "Wax", V3(1.5, 0.16, 2.3), V3(0, SADDLE - 0.08, 0.45), WAX, nil, 0.05, WAX_HI)
			-- the wax runs over the flank edge as a thick lip and drips down in uneven runs with fat beads
			local drips = { L = { { -0.62, 0.42, 0.2 }, { -0.1, 0.66, 0.24 }, { 0.62, 0.3, 0.16 }, { 1.12, 0.52, 0.2 } },
				R = { { -0.4, 0.58, 0.22 }, { 0.3, 0.36, 0.18 }, { 0.8, 0.7, 0.24 }, { 1.3, 0.26, 0.15 } } }
			r:Pair(function(s, side)
				r:Box("Body", "WaxLip_" .. side, V3(0.1, 0.14, 2.1), V3(s * 0.8, SADDLE - 0.14, 0.45), WAX)
				for i, dz in ipairs(drips[side]) do
					local z, len, w = dz[1], dz[2], dz[3]
					r:Tuft("Body", "Drip" .. i .. "_" .. side, CF(s * 0.86, SADDLE - 0.12, z), len, w, 2, WAX, WAX_HI)
					r:Round("Body", "DripBead" .. i .. "_" .. side, V3(w * 0.85, w * 0.8, w * 0.85), V3(s * 0.87, SADDLE - 0.12 - len, z), WAX_HI, nil, w * 0.2)
				end
			end)
			-------- three candles of different heights, wax pooled round their feet, flames on the Flame bones and tall
			-- flares hidden inside each candle (Flare bones lift them out in Happy / Signature)
			local mainFlame
			for i, c in ipairs(CANDLES) do
				local cx, cz, h, w, fl = c[1], c[2], c[3], c[4], c[5]
				local top = SADDLE + h
				r:Round("Body", "Pool" .. i, V3(w + 0.22, 0.08, w + 0.22), V3(cx, SADDLE + 0.02, cz), WAX_LO, nil, 0.03)
				r:Round("Body", "Candle" .. i, V3(w, h, w), V3(cx, SADDLE + h / 2, cz), WAX, nil, 0.04, WAX_HI)
				r:Box("Body", "CandleCup" .. i, V3(w - 0.08, 0.04, w - 0.08), V3(cx, top + 0.005, cz), WAX_LO)
				r:Box("Body", "CandleDrip" .. i, V3(0.08, h * 0.36, 0.06), V3(cx + w * 0.3, top - h * 0.18, cz - w / 2 - 0.02), WAX_HI)
				r:Box("Body", "CandleDripB" .. i, V3(0.06, 0.06, h * 0.22), V3(cx - w / 2 - 0.02, top - 0.06, cz + 0.04), WAX_HI)
				r:Box("Body", "Wick" .. i, V3(0.05, 0.12, 0.05), V3(cx, top + 0.05, cz), WICK)
				local fb = "Flame_" .. i
				local base = V3(cx, top + 0.06, cz)
				local core = flame(r, fb, "Flame" .. i .. "_", base, fl, fl * 0.5, CANDLE, CANDLE_HOT, C(255, 252, 230))
				mainFlame = mainFlame or core
				-- the flare: a tall blue-hearted tongue, sunk inside the candle until it is lifted
				flame(r, "Flare_" .. i, "Flare" .. i .. "_", V3(cx, SADDLE + 0.04, cz), h - 0.1, math.min(w - 0.14, 0.22), CANDLE, CANDLE_HOT)
			end
			r:Light(mainFlame, CANDLE, 8, 1.2)
			-------- short legs with white socks
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.56, front and -0.72 or 1.42
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.48, 0.58, 0.5), V3(x, 0.56, z), FUR, nil, 0.09)
				if front then
					r:Round(leg, "Shoulder_" .. tag, V3(0.56, 0.5, 0.62), V3(x, 0.98, z), FUR, nil, 0.13, FUR_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.62, 0.62, 0.74), V3(x + s * 0.02, 1.02, z + 0.04), FUR, nil, 0.16, FUR_HI)
				end
				r:Box(leg, "Sock_" .. tag, V3(0.5, 0.18, 0.52), V3(x, 0.36, z), WHITE)
				r:Paw(paw, tag, x, z - 0.05, 0.56, 0.6, 0.28, WHITE, { Toe = WHITE, Bean = C(214, 140, 130) })
			end
			-------- neck: white ruff, a red ribbon with a wax seal stamped with a paw
			r:Round("Neck", "Neck", V3(1.0, 0.7, 0.8), V3(0, 2.1, -1.12), FUR, nil, 0.16)
			r:Round("Neck", "Ruff", V3(0.86, 0.66, 0.3), V3(0, 1.96, -1.46), WHITE, nil, 0.1)
			r:Round("Neck", "Ribbon", V3(1.06, 0.12, 0.86), V3(0, 1.92, -1.12), RIBBON, MAT.Fabric, 0.03)
			r:Round("Neck", "Seal", V3(0.38, 0.38, 0.1), V3(0, 1.72, -1.66), SEAL, nil, 0.06)
			r:Box("Neck", "SealRim", V3(0.44, 0.1, 0.08), V3(0, 1.72, -1.64), SEAL_LO)
			r:Box("Neck", "SealPaw", V3(0.12, 0.1, 0.03), V3(0, 1.68, -1.72), SEAL_LO)
			for i, o in ipairs({ V3(-0.09, 0.09, 0), V3(0, 0.12, 0), V3(0.09, 0.09, 0) }) do
				r:Box("Neck", "SealToe" .. i, V3(0.05, 0.05, 0.03), V3(0, 1.72, -1.72) + o, SEAL_LO)
			end
			-------- the fox-like head: white blaze, cheeks and muzzle, a black nose, a panting grin
			r:Round("Head", "Skull", V3(1.32, 1.1, 1.2), V3(0, 2.92, -1.72), FUR, nil, 0.22, FUR_HI)
			r:Box("Head", "Blaze", V3(0.24, 0.72, 0.05), V3(0, 3.12, -2.33), WHITE)
			r:Round("Head", "Cheeks", V3(1.36, 0.5, 0.86), V3(0, 2.62, -1.95), WHITE, nil, 0.1)
			r:Round("Head", "Snout", V3(0.66, 0.46, 0.72), V3(0, 2.62, -2.6), WHITE, nil, 0.12, C(255, 252, 246))
			r:Round("Head", "Nose", V3(0.3, 0.22, 0.18), V3(0, 2.8, -2.98), NOSE, nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.08, 0.05, 0.03), V3(0.06, 2.87, -3.08), C(180, 170, 170))
			r:Box("Head", "MouthLine", V3(0.04, 0.12, 0.03), V3(0, 2.64, -2.97), NOSE)
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.33, 3.02, -2.32), 0.32, 0.32,
					{ Rim = FUR_LO, White = C(255, 252, 246), Iris = C(96, 58, 30), IrisK = 0.82, Look = V3(s * 0.01, 0, 0) })
				r:Box("Head", "Smile_" .. side, V3(0.2, 0.04, 0.03), CF(s * 0.1, 2.54, -2.955) * ANG(0, 0, s * 0.4), NOSE)
				r:Box("Head", "Blush_" .. side, V3(0.2, 0.07, 0.03), V3(s * 0.52, 2.74, -2.385), C(252, 170, 170))
			end)
			-------- big upright corgi ears (white inside); a drop of wax has dripped onto the left tip
			r:Pair(function(s, side)
				local ear = "Ear_" .. side
				local turn = ANG(0, 0, -s * 0.2)
				r:Tri(ear, "Ear_" .. side, V3(s * 0.48, 3.86, -1.55), 0.68, 0.98, 0.14, FUR, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.47, 3.8, -1.64), 0.4, 0.62, 0.04, WHITE_LO, MAT.SmoothPlastic, false, turn)
				r:Box(ear, "EarBase_" .. side, V3(0.5, 0.16, 0.24), V3(s * 0.44, 3.42, -1.55), FUR_HI)
			end)
			r:Box("Ear_L", "EarWax", V3(0.16, 0.14, 0.18), V3(0.58, 4.22, -1.55), WAX_HI)
			r:Box("Ear_L", "EarWaxDrip", V3(0.07, 0.18, 0.08), V3(0.62, 4.08, -1.63), WAX)
			-------- jaw: an open panting mouth with a pink tongue
			r:Round("Jaw", "Jaw", V3(0.56, 0.16, 0.5), V3(0, 2.33, -2.55), WHITE_LO, nil, 0.05)
			r:Box("Jaw", "Tongue", V3(0.2, 0.05, 0.3), CF(0, 2.39, -2.76) * ANG(-0.2, 0, 0), PINK)
			-------- fluffy nub tail
			r:Round("Tail", "TailA", V3(0.46, 0.46, 0.46), V3(0, 2.02, 2.1), FUR_HI, nil, 0.12)
			r:Round("Tail2", "TailB", V3(0.4, 0.38, 0.38), V3(0, 2.14, 2.34), FUR, nil, 0.1)
			r:Round("TailTip", "TailC", V3(0.28, 0.28, 0.28), V3(0, 2.24, 2.5), WHITE, nil, 0.07)
			-------- ability FX hooks (CANDLELIGHT): embers off the two tall candles
			r:Hook(mainFlame, "Candle", "Embers", V3(0.34, SADDLE + 0.92 + 0.45, -0.15), CANDLE, C(255, 110, 40), 5, 0)
			r:Hook(r.Model:FindFirstChild("Flame2_Core"), "CandleB", "Embers", V3(-0.36, SADDLE + 0.62 + 0.36, 0.55), CANDLE_HOT, CANDLE, 3, 0)
		end,
	}
end

---------------------------------------------------------------- H11 MOURNING SHIBA (Epic)
do
	local FUR, FUR_HI, FUR_LO = C(44, 40, 50), C(70, 64, 80), C(28, 26, 34)
	local TAN, TAN_LO, CREAM, CREAM_LO, NOSE = C(204, 146, 86), C(170, 114, 62), C(244, 234, 214), C(222, 206, 182), C(18, 14, 20)
	local LACE, LACE_HI, LACE_DOT = C(36, 30, 46), C(66, 56, 82), C(150, 132, 176)
	local RIBBON, CAMEO, CAMEO_BG, SILVER = C(112, 62, 160), C(240, 232, 246), C(124, 94, 164), C(200, 200, 214)
	local TEAR, TEAR_HOT = C(150, 200, 255), C(226, 242, 255)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.0, 0.3) },
		{ "Neck", "Body", V3(0, 2.7, -1.05) },
		{ "Head", "Neck", V3(0, 3.05, -1.5) },
		{ "Jaw", "Head", V3(0, 2.98, -2.72) },
		{ "Ear_L", "Head", V3(0.5, 4.16, -1.75) },
		{ "Ear_R", "Head", V3(-0.5, 4.16, -1.75) },
		{ "Hat", "Head", V3(0, 4.22, -2.05) },
		{ "Veil", "Head", V3(0, 4.26, -1.42) },
		{ "Veil2", "Body", V3(0, 2.84, -0.6) },
		{ "Tear_L", "Head", V3(0.44, 3.3, -2.62) },
		{ "Tear_R", "Head", V3(-0.44, 3.3, -2.62) },
		{ "Tail", "Body", V3(0, 2.62, 1.55) },
		{ "Tail2", "Tail", V3(0, 3.1, 1.52) },
		{ "TailTip", "Tail2", V3(0, 3.2, 1.18) },
	}
	legBones(bones, 0.58, -0.8, 1.2, 1.5, 0.36, -0.06)
	SPECS.HW_MourningShiba = {
		Code = "H11",
		SignatureName = "Lament",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.6 },
		Motion = { Breath = 0.05, Wag = 0.28, Stride = 0.45, Hop = 0.45, Look = 0.18 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the lace veil behind the head and the lace shawl on the shoulders sway; the tears shimmer
			if ambient(clip) then
				local sway = clip == "Walk" and 0.2 or clip == "Run" and 0.42 or clip == "DigLoop" and 0.1 or 0.04
				add("Veil", 0, 0, 0, -sway + 0.04 * sinU(x, looped and (clip == "Run" and 2 or 1) or 2), 0, 0.04 * sinU(x, 1, 0.3))
				add("Veil2", 0, 0.01 * sinU(x, looped and 2 or 3), 0, -0.4 * sway * sinU(x, 2, 0.2), 0, 0.04 * sinU(x, looped and 2 or 3, 0.1))
				add("Hat", 0, 0, 0, 0.02 * sinU(x, looped and 1 or 2, 0.4), 0, 0.03 * sinU(x, 1))
				for i, side in ipairs({ "L", "R" }) do
					add("Tear_" .. side, 0, -0.012 * (0.5 + 0.5 * sinU(x, looped and 2 or 3, 0.3 * i)), 0, 0, 0, 0)
				end
			end
			if clip == "Idle" then
				-- a little sniffle: the head dips, the ears droop for a moment
				local sn = bump(u, 0.6, 0.72) + 0.6 * bump(u, 0.74, 0.84)
				add("Head", 0, -0.03 * sn, 0, -0.1 * sn, 0, 0)
				add("Ear_L", 0, 0, 0, -0.15 * sn, 0, -0.12 * sn)
				add("Ear_R", 0, 0, 0, -0.15 * sn, 0, 0.12 * sn)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				-- a hopeful little smile: the veil flutters up, the tears sparkle
				local joy = bump(t, 0.05, d - 0.05)
				add("Veil", 0, 0, 0, -0.3 * joy, 0, 0.08 * math.sin(TAU * 4 * t / d) * joy)
				add("Veil2", 0, 0.03 * joy, 0, 0.06 * math.sin(TAU * 5 * t / d) * joy, 0, 0.05 * math.sin(TAU * 4 * t / d) * joy)
				add("Hat", 0, 0.06 * joy, 0, -0.1 * joy, 0, 0.12 * math.sin(TAU * 2 * t / d) * joy)
			elseif clip == "Signature" then
				-- LAMENT: it sits, bows its head, the tears roll down; it lifts its muzzle in a soft howl that flings them
				-- away, the veil lifts in the wind, then it shakes it off and wags, comforted
				local k = hold(t, 0.1, 0.5, d - 0.5, d - 0.1)
				sit(add, k, 0.42)
				local bow = hold(t, 0.3, 0.7, 1.15, 1.4)
				add("Neck", 0, 0, 0, -0.25 * bow, 0, 0)
				add("Head", 0, 0, 0, -0.3 * bow, 0, 0)
				add("Ear_L", 0, 0, 0, -0.2 * bow, 0, -0.25 * bow)
				add("Ear_R", 0, 0, 0, -0.2 * bow, 0, 0.25 * bow)
				local howl = hold(t, 1.3, 1.65, 2.25, 2.55)
				add("Neck", 0, 0, 0, 0.42 * howl, 0, 0)
				add("Head", 0, 0, 0, 0.4 * howl, 0, 0.04 * math.sin(TAU * 6 * t) * howl)
				add("Jaw", 0, 0, 0, -0.42 * howl - 0.05 * math.sin(TAU * 8 * t) * howl, 0, 0)
				add("Ear_L", 0, 0, 0, -0.35 * howl, 0, 0)
				add("Ear_R", 0, 0, 0, -0.35 * howl, 0, 0)
				add("Veil", 0, 0, 0, -0.35 * howl, 0, 0.08 * math.sin(TAU * 3 * t) * howl)
				add("Veil2", 0, 0.03 * howl, 0, 0.06 * math.sin(TAU * 4 * t) * howl, 0, 0.04 * math.sin(TAU * 3 * t) * howl)
				local roll = rise(t, 0.45, 1.15) * (1 - rise(t, 2.6, 2.85))
				local fling = rise(t, 1.35, 1.6) * (1 - rise(t, 2.6, 2.85))
				for _, side in ipairs({ "L", "R" }) do
					local s = side == "L" and 1 or -1
					add("Tear_" .. side, s * 0.45 * fling, -0.2 * roll - 0.4 * fling, -0.25 * fling, 0, 0, 0)
				end
				local shake = bump(t, 2.55, 3.15)
				add("Body", 0, 0, 0, 0, 0, 0.12 * math.sin(TAU * 9 * t) * shake)
				add("Head", 0, 0, 0, 0, 0.3 * math.sin(TAU * 9 * t + 0.5) * shake, 0.1 * math.sin(TAU * 9 * t) * shake)
				add("Veil2", 0, 0, 0, 0, 0, 0.1 * math.sin(TAU * 9 * t + 1) * shake)
				tail(add, 0.15, 0.55 * bump(t, 2.9, d), t / d, 6)
			end
		end,
		Build = function(r)
			-------- a black-and-tan shiba: cream chest and belly, tan points, a black lace ruff with a cameo
			r:Round("Body", "Torso", V3(1.66, 1.36, 2.7), V3(0, 2.05, 0.3), FUR, nil, 0.24, FUR_HI)
			r:Round("Body", "Chest", V3(1.22, 1.08, 0.3), V3(0, 1.95, -1.12), CREAM, nil, 0.1)
			r:Box("Body", "Belly", V3(1.3, 0.1, 2.2), V3(0, 1.37, 0.3), CREAM)
			r:Pair(function(s, side)
				r:Box("Body", "TanLine_" .. side, V3(0.05, 0.08, 2.0), V3(s * 0.835, 1.52, 0.35), TAN)
				r:Box("Body", "ChestTan_" .. side, V3(0.1, 0.9, 0.08), V3(s * 0.6, 1.98, -1.25), TAN)
			end)
			r:Round("Body", "Ruff", V3(1.26, 0.24, 1.0), V3(0, 2.5, -1.05), LACE, MAT.Fabric, 0.06, LACE_HI)
			for i = 0, 4 do
				local a = (i - 2) * 0.32
				local px, pz = math.sin(a) * 0.62, -1.05 - math.cos(a) * 0.5
				r:Box("Body", "Scallop" .. i, V3(0.3, 0.2, 0.08), CF(px, 2.32, pz) * ANG(0, -a, 0) * ANG(0, 0, PI / 4), LACE, MAT.Fabric)
				r:Box("Body", "LaceDot" .. i, V3(0.06, 0.06, 0.04), CF(px, 2.48, pz - 0.03) * ANG(0, -a, 0), LACE_DOT)
			end
			r:Round("Body", "CameoFrame", V3(0.36, 0.42, 0.08), V3(0, 2.3, -1.62), SILVER, MAT.Metal, 0.05)
			local cameo = r:Round("Body", "Cameo", V3(0.28, 0.34, 0.06), V3(0, 2.3, -1.66), CAMEO_BG, nil, 0.04)
			r:Box("Body", "CameoHead", V3(0.12, 0.14, 0.03), V3(0.02, 2.33, -1.7), CAMEO)
			r:Box("Body", "CameoEar", V3(0.05, 0.08, 0.03), V3(-0.03, 2.43, -1.7), CAMEO)
			r:Box("Body", "CameoSnout", V3(0.08, 0.05, 0.03), V3(0.09, 2.3, -1.7), CAMEO)
			-------- legs: black with tan bands and cream socks
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.58, front and -0.8 or 1.2
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.48, 1.0, 0.5), V3(x, 0.92, z), FUR, nil, 0.09)
				if front then
					r:Round(leg, "Shoulder_" .. tag, V3(0.54, 0.6, 0.6), V3(x, 1.5, z), FUR, nil, 0.13, FUR_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.6, 0.86, 0.8), V3(x + s * 0.02, 1.55, z + 0.04), FUR, nil, 0.17, FUR_HI)
				end
				r:Box(leg, "TanBand_" .. tag, V3(0.52, 0.1, 0.54), V3(x, 0.78, z), TAN)
				r:Round(leg, "Sock_" .. tag, V3(0.52, 0.36, 0.54), V3(x, 0.56, z), CREAM, nil, 0.08)
				r:Paw(paw, tag, x, z - 0.06, 0.6, 0.66, 0.36, CREAM, { Toe = CREAM, Bean = C(70, 56, 62) })
			end
			-------- the head: urajiro cheeks, tan brow dots, sad lidded eyes with glowing tear tracks
			r:Round("Neck", "Neck", V3(1.0, 0.8, 0.86), V3(0, 2.78, -1.1), FUR, nil, 0.16)
			r:Round("Head", "Head", V3(1.5, 1.24, 1.36), V3(0, 3.62, -1.86), FUR, nil, 0.26, FUR_HI)
			r:Round("Head", "Cheeks", V3(1.62, 0.56, 1.0), V3(0, 3.1, -2.12), CREAM, nil, 0.14)
			r:Box("Head", "CheekLine", V3(1.6, 0.06, 0.9), V3(0, 3.39, -2.12), TAN)
			r:Round("Head", "Muzzle", V3(0.78, 0.48, 0.68), V3(0, 3.1, -2.82), CREAM, nil, 0.12)
			r:Round("Head", "Nose", V3(0.34, 0.24, 0.18), V3(0, 3.3, -3.18), NOSE, nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.09, 0.05, 0.03), V3(0.07, 3.37, -3.28), C(150, 140, 160))
			r:Box("Head", "MouthLine", V3(0.04, 0.12, 0.03), V3(0, 3.14, -3.17), NOSE)
			r:Box("Head", "Mouth", V3(0.32, 0.04, 0.03), V3(0, 3.06, -3.17), NOSE)
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.36, 3.62, -2.54), 0.36, 0.34,
					{ Rim = FUR_LO, White = C(250, 248, 252), Iris = C(74, 46, 32), IrisK = 0.8, Look = V3(0, -0.03, 0), Lid = FUR_HI, Turn = ANG(0, 0, -s * 0.12) })
				r:Box("Head", "BrowDot_" .. side, V3(0.16, 0.11, 0.05), CF(s * 0.34, 3.93, -2.55) * ANG(0, 0, s * 0.3), TAN)
				-- the glowing tear track and the tear itself (Tear bones roll it)
				r:Neon("Head", "TearTrackA_" .. side, V3(0.05, 0.12, 0.03), V3(s * 0.44, 3.4, -2.56), TEAR, { Transparency = 0.15 })
				r:Neon("Head", "TearTrackB_" .. side, V3(0.05, 0.12, 0.03), V3(s * 0.44, 3.31, -2.64), TEAR, { Transparency = 0.25 })
				r:Neon("Tear_" .. side, "Tear_" .. side, V3(0.09, 0.11, 0.07), V3(s * 0.44, 3.2, -2.67), TEAR)
				r:Neon("Tear_" .. side, "TearHot_" .. side, V3(0.04, 0.05, 0.04), V3(s * 0.44 + 0.01, 3.22, -2.71), TEAR_HOT)
				r:Box("Head", "Whisker_" .. side, V3(0.05, 0.05, 0.03), V3(s * 0.26, 3.18, -3.17), FUR_LO)
			end)
			-------- triangular ears (cream inside)
			r:Pair(function(s, side)
				local ear = "Ear_" .. side
				local turn = ANG(0, 0, -s * 0.16)
				r:Tri(ear, "Ear_" .. side, V3(s * 0.5, 4.5, -1.75), 0.62, 0.76, 0.14, FUR, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.49, 4.45, -1.83), 0.36, 0.48, 0.04, CREAM_LO, MAT.SmoothPlastic, false, turn)
				r:Box(ear, "EarBase_" .. side, V3(0.46, 0.14, 0.22), V3(s * 0.47, 4.17, -1.75), FUR_HI)
			end)
			-------- the mourning hat: a tilted black pillbox with a violet ribbon, a lace rose and a short net over the brow
			r:Round("Hat", "HatCrown", V3(0.5, 0.2, 0.5), CF(0.02, 4.32, -2.05) * ANG(0.12, 0, -0.1), LACE, MAT.Fabric, 0.05, LACE_HI)
			r:Box("Hat", "HatBand", V3(0.52, 0.06, 0.52), CF(0.02, 4.26, -2.05) * ANG(0.12, 0, -0.1), RIBBON, MAT.Fabric)
			r:Box("Hat", "HatRoseA", V3(0.16, 0.16, 0.12), CF(0.27, 4.32, -2.22) * ANG(0, 0, PI / 4), LACE_HI, MAT.Fabric)
			r:Box("Hat", "HatRoseB", V3(0.1, 0.1, 0.13), CF(0.27, 4.32, -2.23), RIBBON, MAT.Fabric)
			r:Box("Hat", "HatBowL", V3(0.16, 0.1, 0.06), CF(-0.2, 4.3, -2.3) * ANG(0, 0, 0.4), RIBBON, MAT.Fabric)
			r:Box("Hat", "HatBowR", V3(0.16, 0.1, 0.06), CF(-0.06, 4.3, -2.31) * ANG(0, 0, -0.4), RIBBON, MAT.Fabric)
			r:Box("Hat", "Net", V3(0.96, 0.32, 0.03), V3(0, 4.06, -2.565), C(104, 92, 128), nil, { Transparency = 0.45 })
			r:Box("Hat", "NetHem", V3(0.96, 0.04, 0.04), V3(0, 3.9, -2.57), RIBBON)
			for i = 0, 2 do
				r:Box("Hat", "NetDot" .. i, V3(0.05, 0.05, 0.04), V3(-0.3 + i * 0.3, 4.06 + (i % 2) * 0.08, -2.585), LACE_DOT)
			end
			-------- the lace veil falling from the hat down the back of the head (Veil), and a lace shawl with a violet hem
			-- over the shoulders (Veil2)
			r:Seg("Veil", "VeilBack", V3(0, 4.3, -1.5), V3(0, 3.42, -1.06), 1.38, 0.05, LACE_HI, MAT.Fabric, { Transparency = 0.2 })
			r:Pair(function(s, side)
				r:Seg("Veil", "VeilEdge_" .. side, V3(s * 0.68, 4.28, -1.5), V3(s * 0.7, 3.42, -1.06), 0.06, 0.07, LACE, MAT.Fabric)
			end)
			for i = 0, 2 do
				r:Box("Veil", "VeilDot" .. i, V3(0.07, 0.07, 0.07), CF(-0.36 + i * 0.36, 3.86 - (i % 2) * 0.16, -1.29 + (i % 2) * 0.08) * ANG(0.46, 0, 0), LACE_DOT)
			end
			r:Round("Veil2", "Shawl", V3(1.86, 0.1, 1.16), V3(0, 2.78, -0.55), LACE_HI, MAT.Fabric, 0.03, nil)
			r:Pair(function(s, side)
				r:Box("Veil2", "ShawlSide_" .. side, V3(0.06, 0.56, 1.12), V3(s * 0.9, 2.52, -0.55), LACE_HI, MAT.Fabric, { Transparency = 0.15 })
				r:Box("Veil2", "ShawlHem_" .. side, V3(0.08, 0.05, 1.14), V3(s * 0.905, 2.24, -0.55), RIBBON, MAT.Fabric)
				for i = 0, 2 do
					r:Box("Veil2", "ShawlScallop" .. i .. "_" .. side, V3(0.07, 0.2, 0.2), CF(s * 0.905, 2.17, -0.92 + i * 0.37) * ANG(PI / 4, 0, 0), LACE, MAT.Fabric)
					r:Box("Veil2", "ShawlDot" .. i .. "_" .. side, V3(0.07, 0.06, 0.06), V3(s * 0.935, 2.5 + (i % 2) * 0.12, -0.92 + i * 0.37), LACE_DOT)
				end
			end)
			-------- jaw
			r:Round("Jaw", "Jaw", V3(0.6, 0.18, 0.5), V3(0, 2.9, -2.86), CREAM_LO, nil, 0.05)
			r:Box("Jaw", "Tongue", V3(0.2, 0.05, 0.2), V3(0, 2.98, -3.02), C(220, 100, 120))
			-------- the curled tail over the back (black on top, cream beneath)
			r:Round("Tail", "TailRoot", V3(0.44, 0.56, 0.44), V3(0, 2.86, 1.6), FUR, nil, 0.1)
			r:Round("Tail2", "TailCurl", V3(0.48, 0.44, 0.64), V3(0, 3.2, 1.38), FUR, nil, 0.12, FUR_HI)
			r:Box("Tail2", "TailCurlCream", V3(0.38, 0.1, 0.5), V3(0, 2.97, 1.38), CREAM)
			r:Round("TailTip", "TailFront", V3(0.42, 0.44, 0.42), V3(0, 3.1, 1.06), FUR, nil, 0.1)
			r:Round("TailTip", "TailTipCream", V3(0.36, 0.3, 0.36), V3(0, 2.84, 1.04), CREAM, nil, 0.07)
			-------- light + ability FX hooks (MOURNING VEIL): moonlit tears, a glint off the cameo
			local tear = r.Model:FindFirstChild("Tear_L")
			r:Light(tear, TEAR, 6, 0.7)
			r:Hook(tear, "Tears", "Wisps", V3(0.44, 3.2, -2.7), TEAR, TEAR_HOT, 2, 0)
			r:Hook(cameo, "Cameo", "Stars", V3(0, 2.3, -1.72), CAMEO, TEAR, 2, 0)
		end,
	}
end

---------------------------------------------------------------- H12 COFFIN PUG (Legendary)
do
	local FAWN, FAWN_HI, FAWN_LO = C(238, 220, 190), C(250, 238, 216), C(204, 180, 146)
	local MASK, MASK_HI, NOSE, PINK = C(40, 34, 40), C(66, 58, 66), C(16, 14, 18), C(238, 112, 130)
	local WOOD, WOOD_HI, WOOD_LO = C(84, 50, 42), C(112, 72, 56), C(54, 32, 28)
	local BRASS, BRASS_HI, STRAP, BONE = C(214, 170, 78), C(248, 216, 132), C(78, 56, 42), C(242, 234, 214)
	local LINING, GLOW, GLOW_HOT = C(130, 64, 160), C(120, 255, 140), C(226, 255, 226)
	-- the coffin, head end toward the dog's head: {z0, z1, width}
	local SEGS = { { -0.62, -0.4, 0.6 }, { -0.4, -0.14, 0.86 }, { -0.14, 0.38, 1.08 }, { 0.38, 0.86, 0.96 }, { 0.86, 1.24, 0.8 }, { 1.24, 1.46, 0.6 } }
	local FLOOR, TOP = 2.46, 3.06
	local HINGE = V3(-0.57, TOP, 0.42)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 1.78, 0.3) },
		{ "Coffin", "Body", V3(0, FLOOR, 0.42) },
		{ "Lid", "Coffin", HINGE },
		{ "Peek", "Coffin", V3(0, 2.7, 0.42) },
		{ "Neck", "Body", V3(0, 2.42, -0.92) },
		{ "Head", "Neck", V3(0, 2.65, -1.3) },
		{ "Jaw", "Head", V3(0, 2.55, -2.5) },
		{ "Ear_L", "Head", V3(0.82, 3.98, -1.66) },
		{ "Ear_R", "Head", V3(-0.82, 3.98, -1.66) },
		{ "Tail", "Body", V3(0, 2.2, 1.5) },
		{ "Tail2", "Tail", V3(0, 2.6, 1.8) },
		{ "TailTip", "Tail2", V3(0, 2.72, 1.7) },
	}
	legBones(bones, 0.62, -0.5, 1.08, 1.2, 0.32, -0.06)
	SPECS.HW_CoffinPug = {
		Code = "H12",
		SignatureName = "CoffinPeek",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.6 },
		Motion = { Breath = 0.06, Wag = 0.45, Stride = 0.42, Hop = 0.45, Look = 0.2 },
		Extra = function(clip, t, d, u, add)
			local function lid(open: number, peek: number)
				add("Lid", 0, 0, 0, 0, 0, open)
				add("Peek", 0, 0.38 * peek, 0, 0, 0, 0)
			end
			if clip == "Idle" then
				-- something inside lifts the lid to peek out, looks around, and shuts it again
				local open = bump(u, 0.45, 0.78)
				lid(0.55 * open + 0.03 * math.sin(TAU * 20 * u) * open, math.min(1, open * 1.6))
				add("Peek", 0, 0, 0, 0, 0.5 * math.sin(TAU * 3 * u) * open, 0)
				add("Coffin", 0, 0, 0, 0.02 * sinU(u, 1), 0, 0.015 * sinU(u, 1, 0.25))
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				local a = clip == "Run" and 1.5 or 1
				lid(0.14 * a * math.max(0, sinU(u, k)), 0)
				add("Coffin", 0, 0.03 * a * math.max(0, sinU(u, k, 0.1)), 0, 0.04 * a * sinU(u, k, 0.2), 0, 0.03 * sinU(u, 1))
			elseif clip == "DigLoop" then
				lid(0.1 * math.max(0, sinU(u, 2, 0.3)), 0)
				add("Coffin", 0, 0, 0, 0.03 * sinU(u, 2), 0, 0)
			elseif clip == "Sleep" then
				-- the ghost inside keeps watch over the sleeping pug through a crack
				lid(0.16 + 0.02 * sinU(u, 1), 0.85)
			elseif clip == "Sniff" then
				local open = bump(t, 0.6, d - 0.3)
				lid(0.3 * open, open)
				add("Peek", 0, 0, 0, 0, 0.6 * math.sin(TAU * 0.8 * t) * open, 0)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				-- the lid bangs open, the glow inside cheers, it bangs shut
				local a, b = 0.1, d - 0.1
				local open = hold(t, a, a + 0.15, b - 0.3, b)
				lid(1.15 * open + 0.12 * math.sin(TAU * 6 * t / d) * open, open)
				add("Coffin", 0, 0.06 * open, 0, 0, 0, 0.06 * math.sin(TAU * 4 * t / d) * open)
			elseif clip == "Signature" then
				-- COFFIN PEEK: the pug looks back at its coffin; the lid creaks open, two eyes rise out of the green glow...
				-- SLAM! The pug jumps out of its skin, then the lid chatters like a laughing mouth and the pug wags along
				local look = hold(t, 0.15, 0.5, 1.45, 1.6)
				add("Neck", 0, 0, 0, 0.05 * look, 0.75 * look, 0)
				add("Head", 0, 0, 0, 0.1 * look, 0.5 * look, 0.15 * look)
				local creak = rise(t, 0.45, 1.35) * (1 - rise(t, 1.45, 1.55))
				local peek = rise(t, 0.85, 1.3) * (1 - rise(t, 1.42, 1.52))
				local chatter = bump(t, 2.05, 3.35)
				lid(0.95 * creak + 0.03 * math.sin(TAU * 13 * t) * creak + 0.4 * math.max(0, math.sin(TAU * 6 * t)) * chatter, peek + 0.6 * chatter)
				add("Peek", 0, 0, 0, 0, 0.6 * math.sin(TAU * 2 * t) * peek, 0)
				local jump = bump(t, 1.5, 2.0)
				add("Body", 0, 0.55 * jump, 0, 0.1 * jump, 0, 0)
				legs(add, 0.55 * jump, -0.5 * jump, 0.25 * jump)
				add("Ear_L", 0, 0, 0, 0.2 * jump, 0, -0.6 * jump)
				add("Ear_R", 0, 0, 0, 0.2 * jump, 0, 0.6 * jump)
				add("Jaw", 0, 0, 0, -0.4 * jump - 0.15 * chatter, 0, 0)
				add("Coffin", 0, 0.12 * jump, 0, 0.1 * jump, 0, 0.08 * math.sin(TAU * 6 * t) * chatter)
				add("Body", 0, 0, 0, 0, 0.12 * math.sin(TAU * 4 * t) * chatter, 0)
				tail(add, 0.25 * chatter, 0.7 * chatter, t / d, 9)
			end
		end,
		Build = function(r)
			-------- a stocky cream pug in a leather harness, with rolls on its neck
			r:Round("Body", "Torso", V3(1.92, 1.36, 2.3), V3(0, 1.8, 0.3), FAWN, nil, 0.26, FAWN_HI)
			r:Round("Body", "Chest", V3(1.6, 1.06, 0.3), V3(0, 1.78, -0.9), FAWN_HI, nil, 0.1)
			r:Box("Body", "Belly", V3(1.56, 0.1, 1.9), V3(0, 1.13, 0.3), FAWN_HI)
			r:Pair(function(s, side)
				r:Box("Body", "Strap_" .. side, V3(0.08, 1.24, 0.16), V3(s * 0.98, 1.82, -0.25), STRAP)
				r:Box("Body", "StrapHip_" .. side, V3(0.08, 1.24, 0.16), V3(s * 0.98, 1.82, 0.95), STRAP)
				r:Box("Body", "Buckle_" .. side, V3(0.1, 0.22, 0.24), V3(s * 1.01, 2.1, -0.25), BRASS, MAT.Metal)
				r:Box("Body", "BuckleIn_" .. side, V3(0.11, 0.1, 0.12), V3(s * 1.01, 2.1, -0.25), STRAP)
				r:Box("Body", "Wrinkle_" .. side, V3(0.05, 0.06, 0.5), V3(s * 0.965, 2.22, 0.35), FAWN_LO)
			end)
			r:Box("Body", "ChestStrap", V3(1.66, 0.14, 0.1), V3(0, 2.02, -1.06), STRAP)
			r:Box("Body", "BellyStrap", V3(1.66, 0.08, 0.16), V3(0, 1.1, 0.95), STRAP)
			r:Box("Body", "BellyStrapB", V3(1.66, 0.08, 0.16), V3(0, 1.1, -0.25), STRAP)
			r:Box("Body", "Tag", V3(0.24, 0.24, 0.05), CF(0, 1.8, -1.12) * ANG(0, 0, PI / 4), BRASS, MAT.Metal)
			-------- the coffin backpack: a stepped hexagonal box of dark wood, brass handles and corners, crossed bones on
			-- the lid, violet satin lining, a hinged lid (Lid bone) and two green eyes living inside (Peek bone lifts them)
			local mid = (FLOOR + TOP) / 2
			for i, sg in ipairs(SEGS) do
				local z0, z1, w = sg[1], sg[2], sg[3]
				local zc = (z0 + z1) / 2
				r:Box("Coffin", "Coffin" .. i, V3(w, TOP - FLOOR, z1 - z0 + 0.01), V3(0, mid, zc), i % 2 == 0 and WOOD or WOOD_HI, MAT.Wood)
				r:Box("Coffin", "Lining" .. i, V3(w - 0.14, 0.02, z1 - z0 + 0.012), V3(0, TOP - 0.005, zc), LINING, MAT.Fabric)
				r:Box("Lid", "Lid" .. i, V3(w + 0.06, 0.08, z1 - z0 + 0.012), V3(0, TOP + 0.04, zc), WOOD_LO, MAT.Wood)
				if i > 1 and i < #SEGS then
					r:Box("Lid", "LidTop" .. i, V3(w - 0.18, 0.05, z1 - z0 + 0.012), V3(0, TOP + 0.105, zc), WOOD, MAT.Wood)
				end
				r:Box("Coffin", "Base" .. i, V3(w + 0.04, 0.06, z1 - z0 + 0.012), V3(0, FLOOR + 0.03, zc), WOOD_LO, MAT.Wood)
			end
			r:Pair(function(s, side)
				for j, hd in ipairs({ { 0.12, 1.08 }, { 1.05, 0.8 } }) do
					local hz, w = hd[1], hd[2]
					r:Box("Coffin", "Handle" .. j .. "_" .. side, V3(0.05, 0.08, 0.3), V3(s * (w / 2 + 0.06), mid, hz), BRASS, MAT.Metal)
					r:Box("Coffin", "HandlePin" .. j .. "A_" .. side, V3(0.06, 0.06, 0.05), V3(s * (w / 2 + 0.03), mid, hz - 0.13), BRASS_HI, MAT.Metal)
					r:Box("Coffin", "HandlePin" .. j .. "B_" .. side, V3(0.06, 0.06, 0.05), V3(s * (w / 2 + 0.03), mid, hz + 0.13), BRASS_HI, MAT.Metal)
				end
				r:Box("Lid", "LidCorner_" .. side, V3(0.1, 0.1, 0.1), V3(s * 0.57, TOP + 0.05, -0.14), BRASS, MAT.Metal)
				r:Box("Lid", "LidCornerB_" .. side, V3(0.1, 0.1, 0.1), V3(s * 0.51, TOP + 0.05, 0.86), BRASS, MAT.Metal)
			end)
			r:Box("Lid", "Latch", V3(0.06, 0.16, 0.1), V3(0.58, TOP, 0.12), BRASS_HI, MAT.Metal)
			-- crossed bones on the lid
			for i, a in ipairs({ 0.7, -0.7 }) do
				local frame = CF(0, TOP + 0.15, 0.42) * ANG(0, a, 0)
				r:Box("Lid", "LidBone" .. i, V3(0.08, 0.04, 0.5), frame, BONE)
				r:Box("Lid", "LidBoneKnobA" .. i, V3(0.16, 0.05, 0.08), frame * CF(0, 0, -0.26), BONE)
				r:Box("Lid", "LidBoneKnobB" .. i, V3(0.16, 0.05, 0.08), frame * CF(0, 0, 0.26), BONE)
			end
			-- inside: a pool of grave-light and two eyes (hidden under the lid until Peek lifts them)
			local glow = r:Neon("Peek", "GhostGlow", V3(0.6, 0.04, 1.1), V3(0, 2.74, 0.42), GLOW, { Transparency = 0.2 })
			r:Pair(function(s, side)
				r:Neon("Peek", "GhostEye_" .. side, V3(0.13, 0.15, 0.12), V3(s * 0.14, 2.8, 0.1), GLOW_HOT)
				r:Box("Peek", "GhostPupil_" .. side, V3(0.05, 0.08, 0.13), V3(s * 0.14, 2.79, 0.09), C(30, 70, 40))
			end)
			r:Light(glow, GLOW, 7, 0.8)
			-------- short pug legs with black nails
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.62, front and -0.5 or 1.08
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				r:Round(leg, "Leg_" .. tag, V3(0.56, 0.84, 0.58), V3(x, 0.76, z), FAWN, nil, 0.1)
				if front then
					r:Round(leg, "Shoulder_" .. tag, V3(0.64, 0.5, 0.68), V3(x, 1.22, z), FAWN, nil, 0.14, FAWN_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.68, 0.72, 0.8), V3(x + s * 0.02, 1.24, z + 0.04), FAWN, nil, 0.18, FAWN_HI)
				end
				r:Paw(paw, tag, x, z - 0.06, 0.66, 0.7, 0.32, FAWN_LO, { Toe = FAWN, Nail = MASK })
			end
			-------- the round pug head: black mask, forehead wrinkles, huge eyes, a blep
			r:Round("Neck", "Neck", V3(1.2, 0.7, 0.82), V3(0, 2.52, -1.02), FAWN, nil, 0.14)
			r:Box("Neck", "Roll", V3(1.24, 0.06, 0.86), V3(0, 2.4, -1.02), FAWN_LO)
			r:Box("Neck", "RollB", V3(1.16, 0.06, 0.8), V3(0, 2.62, -1.04), FAWN_LO)
			r:Round("Head", "Head", V3(1.92, 1.66, 1.6), V3(0, 3.2, -1.76), FAWN, nil, 0.3, FAWN_HI)
			r:Round("Head", "Jowls", V3(2.02, 0.86, 1.2), V3(0, 2.8, -1.92), FAWN, nil, 0.22)
			r:Round("Head", "Mask", V3(1.36, 0.92, 0.08), V3(0, 3.06, -2.57), MASK, nil, 0.04)
			r:Round("Head", "Muzzle", V3(1.12, 0.66, 0.36), V3(0, 2.78, -2.72), MASK, nil, 0.1, MASK_HI)
			r:Round("Head", "Nose", V3(0.44, 0.24, 0.16), V3(0, 3.04, -2.92), NOSE, nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.1, 0.05, 0.03), V3(0.1, 3.11, -3.005), C(170, 170, 180))
			r:Box("Head", "MouthLine", V3(0.04, 0.16, 0.03), V3(0, 2.84, -2.91), C(14, 12, 16))
			r:Box("Head", "WrinkleA", V3(0.54, 0.06, 0.04), V3(0, 3.78, -2.56), FAWN_LO)
			r:Box("Head", "WrinkleB", V3(0.34, 0.06, 0.04), V3(0, 3.9, -2.54), FAWN_LO)
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.42, 3.32, -2.61), 0.5, 0.5,
					{ Rim = MASK, White = C(250, 248, 244), Iris = C(66, 44, 30), IrisK = 0.82, Look = V3(s * 0.02, -0.02, 0) })
				r:Box("Head", "Brow_" .. side, V3(0.3, 0.07, 0.04), CF(s * 0.42, 3.68, -2.57) * ANG(0, 0, s * 0.18), FAWN_LO)
				r:Round("Head", "Jowl_" .. side, V3(0.34, 0.48, 0.42), V3(s * 0.62, 2.74, -2.56), FAWN_LO, nil, 0.08)
				r:Round("Ear_" .. side, "EarTop_" .. side, V3(0.5, 0.14, 0.5), V3(s * 0.84, 3.98, -1.74), MASK, nil, 0.04)
				r:Round("Ear_" .. side, "EarFlap_" .. side, V3(0.5, 0.44, 0.14), V3(s * 0.86, 3.82, -2.02), MASK, nil, 0.04)
			end)
			r:Round("Jaw", "Jaw", V3(0.96, 0.22, 0.4), V3(0, 2.42, -2.62), MASK, nil, 0.06)
			r:Box("Jaw", "Blep", V3(0.18, 0.05, 0.2), CF(0.08, 2.52, -2.86) * ANG(-0.5, 0, 0), PINK)
			-------- curly tail with a dark tip
			r:Round("Tail", "TailA", V3(0.34, 0.42, 0.34), V3(0, 2.38, 1.64), FAWN, nil, 0.06)
			r:Round("Tail2", "TailB", V3(0.32, 0.32, 0.38), V3(0, 2.7, 1.82), FAWN, nil, 0.06)
			r:Round("TailTip", "TailC", V3(0.26, 0.26, 0.26), V3(0, 2.6, 1.68), MASK, nil, 0.05)
			-------- ability FX hook (COFFIN SENSE): grave-light wisps leaking out of the coffin seam
			r:Hook(r.Model:FindFirstChild("Lid3"), "Coffin", "Wisps", V3(0, TOP + 0.12, 0.42), GLOW, GLOW_HOT, 3, 0.8)
		end,
	}
end

---------------------------------------------------------------- H13 MOTH HOUND (Legendary)
do
	local FUR, FUR_HI, FUR_LO = C(186, 170, 152), C(212, 198, 180), C(140, 124, 108)
	local FLUFF, FLUFF_LO, NOSE = C(248, 240, 224), C(224, 212, 190), C(52, 40, 46)
	local WING, WING_HI, WING_DARK, FRINGE = C(150, 112, 192), C(194, 164, 222), C(90, 62, 128), C(240, 226, 204)
	local RING, IRIS, GLOW, ANT, FEATHER = C(242, 208, 132), C(44, 28, 60), C(150, 200, 255), C(112, 86, 60), C(214, 190, 150)
	local FORE = { Len = 1.95, Wid = 1.1, Raise = 0.95, Sweep = 1.0, Root = 3.32, Z = -0.4, X = 0.4 }
	local HIND = { Len = 1.3, Wid = 0.9, Raise = 0.42, Sweep = 1.22, Root = 3.16, Z = 0.15, X = 0.36 }
	local function wingFrame(w, s: number): CFrame
		return CF(s * w.X, w.Root, w.Z) * ANG(0, -s * w.Sweep, 0) * ANG(0, 0, s * w.Raise) * CFrame.fromMatrix(V3(), V3(s, 0, 0), V3(0, 0, -1))
	end
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.55, 0.3) },
		{ "Neck", "Body", V3(0, 3.2, -1.05) },
		{ "Head", "Neck", V3(0, 3.75, -1.55) },
		{ "Jaw", "Head", V3(0, 3.66, -2.62) },
		{ "Ear_L", "Head", V3(0.38, 4.3, -1.45) },
		{ "Ear_R", "Head", V3(-0.38, 4.3, -1.45) },
		{ "Antenna_L", "Head", V3(0.2, 4.36, -1.95) },
		{ "Antenna_R", "Head", V3(-0.2, 4.36, -1.95) },
		{ "Wing_L", "Body", V3(FORE.X, FORE.Root, FORE.Z) },
		{ "Wing_R", "Body", V3(-FORE.X, FORE.Root, FORE.Z) },
		{ "Hind_L", "Body", V3(HIND.X, HIND.Root, HIND.Z) },
		{ "Hind_R", "Body", V3(-HIND.X, HIND.Root, HIND.Z) },
		{ "Tail", "Body", V3(0, 2.8, 1.62) },
		{ "Tail2", "Tail", V3(0, 3.0, 2.14) },
		{ "TailTip", "Tail2", V3(0, 3.26, 2.6) },
	}
	legBones(bones, 0.46, -0.78, 1.25, 2.2, 0.4, -0.02)
	local function wings(add, fore: number, hind: number, sweep: number?)
		add("Wing_L", 0, 0, 0, 0, sweep or 0, fore)
		add("Wing_R", 0, 0, 0, 0, -(sweep or 0), -fore)
		add("Hind_L", 0, 0, 0, 0, (sweep or 0) * 0.6, hind)
		add("Hind_R", 0, 0, 0, 0, -(sweep or 0) * 0.6, -hind)
	end
	SPECS.HW_MothHound = {
		Code = "H13",
		SignatureName = "Flutter",
		Bones = bones,
		Durations = { Idle = 4.0, Signature = 3.4 },
		Motion = { Breath = 0.04, Wag = 0.3, Stride = 0.48, Hop = 0.55, Look = 0.28 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the feathered antennae never stop tasting the air
			if ambient(clip) then
				add("Antenna_L", 0, 0, 0, 0.08 * sinU(x, looped and 3 or 5), 0, 0.1 * sinU(x, looped and 2 or 4, 0.2))
				add("Antenna_R", 0, 0, 0, 0.08 * sinU(x, looped and 3 or 5, 0.4), 0, -0.1 * sinU(x, looped and 2 or 4, 0.6))
			end
			if clip == "Idle" then
				-- slow wing breathing, then a quick flutter
				local fl = bump(u, 0.55, 0.8)
				local w = 0.12 * sinU(u, 1) + 0.4 * fl * math.sin(TAU * 12 * u)
				wings(add, w, w * 0.7)
			elseif clip == "Walk" then
				wings(add, 0.18 * sinU(u, 2), 0.12 * sinU(u, 2, 0.1), 0.05)
			elseif clip == "Run" then
				wings(add, 0.45 * sinU(u, 2), 0.32 * sinU(u, 2, 0.12), 0.2)
			elseif clip == "DigLoop" then
				wings(add, 0.3 + 0.06 * sinU(u, 2), 0.2, 0)
			elseif clip == "Sleep" then
				-- wings folded down over its back like a tent
				wings(add, -0.62 + 0.02 * sinU(u, 1), -0.42, 0.25)
				add("Antenna_L", 0, 0, 0, 0.5, 0, 0.2)
				add("Antenna_R", 0, 0, 0, 0.5, 0, -0.2)
			elseif clip == "Sniff" then
				local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
				wings(add, 0.15 * down * math.sin(TAU * 3 * t), 0.1 * down)
				add("Antenna_L", 0, 0, 0, -0.35 * down, 0, 0.15 * math.sin(TAU * 4 * t) * down)
				add("Antenna_R", 0, 0, 0, -0.35 * down, 0, -0.15 * math.sin(TAU * 4 * t) * down)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local joy = bump(t, 0.05, d - 0.05)
				local w = 0.55 * math.sin(TAU * (clip == "RareFind" and 10 or 6) * t / d) * joy
				wings(add, w + 0.15 * joy, w * 0.8)
				add("Root", 0, (clip == "RareFind" and 0.25 or 0.12) * joy, 0, 0, 0, 0)
			elseif clip == "Signature" then
				-- FLUTTER: it rears up on its hind legs, wings beating fast, and hovers a moment searching for the light
				-- (head and antennae turning), then floats down into a soft bow
				local rear = hold(t, 0.3, 0.8, 2.45, 2.95)
				add("Body", 0, 0.5 * rear, 0, 0.55 * rear, 0, 0)
				add("Leg_BL", 0, 0, 0, -0.55 * rear, 0, 0)
				add("Leg_BR", 0, 0, 0, -0.55 * rear, 0, 0)
				local paddle = math.sin(TAU * 4 * t)
				add("Leg_FL", 0, 0, 0, 0.7 * rear + 0.25 * paddle * rear, 0, 0)
				add("Leg_FR", 0, 0, 0, 0.7 * rear - 0.25 * paddle * rear, 0, 0)
				add("Paw_FL", 0, 0, 0, -0.6 * rear, 0, 0)
				add("Paw_FR", 0, 0, 0, -0.6 * rear, 0, 0)
				local beat = math.sin(TAU * 8 * t) * hold(t, 0.2, 0.5, 2.6, 3.0)
				wings(add, 0.25 + 0.6 * beat, 0.15 + 0.45 * math.sin(TAU * 8 * t - 0.6) * hold(t, 0.2, 0.5, 2.6, 3.0))
				add("Root", 0, 0.28 * rear + 0.05 * beat * rear, 0, 0, 0, 0)
				local search = math.sin(TAU * 0.9 * (t - 0.8)) * hold(t, 0.8, 1.1, 2.2, 2.5)
				add("Neck", 0, 0, 0, -0.35 * rear, 0.25 * search, 0)
				add("Head", 0, 0, 0, -0.15 * rear, 0.35 * search, 0.1 * search)
				add("Antenna_L", 0, 0, 0, -0.3 * rear, 0, 0.25 * rear)
				add("Antenna_R", 0, 0, 0, -0.3 * rear, 0, -0.25 * rear)
				local bow = bump(t, 2.85, d)
				add("Body", 0, -0.1 * bow, 0, -0.15 * bow, 0, 0)
				legs(add, -0.25 * bow, 0.15 * bow)
				add("Head", 0, 0, 0, -0.2 * bow, 0, 0)
				tail(add, 0.2 * rear, 0.4 * hold(t, 0.3, 0.6, 2.8, d), t / d, 6)
			end
		end,
		Build = function(r)
			-------- a lean sighthound: deep chest, tucked waist, long thin legs, a fluffy cream moth ruff
			r:Round("Body", "Chest", V3(1.3, 1.5, 1.22), V3(0, 2.62, -0.62), FUR, nil, 0.26, FUR_HI)
			r:Round("Body", "Waist", V3(0.98, 0.95, 1.5), V3(0, 2.8, 0.72), FUR, nil, 0.2, FUR_HI)
			r:Round("Body", "Hips", V3(1.08, 1.0, 0.62), V3(0, 2.82, 1.32), FUR, nil, 0.2, FUR_HI)
			r:Box("Body", "Underline", V3(0.7, 0.1, 1.4), CF(0, 2.38, 0.55) * ANG(-0.18, 0, 0), FLUFF_LO)
			r:Round("Body", "Collar", V3(1.42, 0.5, 1.12), V3(0, 3.36, -0.82), FLUFF, nil, 0.14, C(255, 252, 244))
			r:Tuft("Body", "Ruff", CF(0, 3.3, -1.28), 1.12, 1.18, 3, FLUFF, FLUFF_LO)
			r:Pair(function(s, side)
				r:Tuft("Body", "RuffSide_" .. side, CF(s * 0.62, 3.3, -0.92) * ANG(0, 0, s * 0.35), 0.8, 0.5, 3, FLUFF_LO, FLUFF)
				r:Tuft("Body", "RuffBack_" .. side, CF(s * 0.5, 3.45, -0.42) * ANG(-0.5, 0, s * 0.5), 0.5, 0.4, 2, FLUFF, FLUFF_LO)
				r:Box("Body", "FlankFluff_" .. side, V3(0.06, 0.4, 0.55), V3(s * 0.5, 2.85, 1.0), FLUFF_LO)
			end)
			-------- legs: long and fine, fluffy cream ankle tufts
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.46, front and -0.78 or 1.25
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				if front then
					r:Round(leg, "Thigh_" .. tag, V3(0.44, 1.32, 0.48), V3(x, 1.6, z), FUR, nil, 0.09)
					r:Round(leg, "Elbow_" .. tag, V3(0.5, 0.5, 0.56), V3(x, 2.1, z), FUR, nil, 0.12, FUR_HI)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.5, 1.0, 0.78), V3(x + s * 0.02, 2.05, z + 0.05), FUR, nil, 0.16, FUR_HI)
					r:Round(leg, "Hock_" .. tag, V3(0.4, 0.72, 0.42), V3(x, 1.3, z + 0.08), FUR, nil, 0.08)
				end
				r:Round(paw, "Shin_" .. tag, V3(0.36, 0.72, 0.38), V3(x, 0.66, z), FUR, nil, 0.07)
				r:Round(paw, "AnkleFluff_" .. tag, V3(0.42, 0.22, 0.44), V3(x, 0.38, z), FLUFF, nil, 0.06)
				r:Paw(paw, tag, x, z - 0.06, 0.48, 0.56, 0.24, FUR_LO, { Toe = FUR_HI, Nail = C(60, 48, 52) })
			end
			-------- long neck and narrow head; big glossy moth eyes with a moon-blue shine
			r:Round("Neck", "Neck", V3(0.62, 1.1, 0.7), CF(0, 3.45, -1.22) * ANG(0.45, 0, 0), FUR, nil, 0.12)
			r:Round("Head", "Head", V3(0.92, 0.82, 1.06), V3(0, 4.0, -1.76), FUR, nil, 0.2, FUR_HI)
			r:Round("Head", "Snout", V3(0.52, 0.42, 1.0), V3(0, 3.82, -2.7), FUR, nil, 0.1, FUR_HI)
			r:Round("Head", "SnoutUnder", V3(0.5, 0.16, 0.9), V3(0, 3.66, -2.68), FLUFF_LO, nil, 0.04)
			r:Round("Head", "Nose", V3(0.24, 0.18, 0.14), V3(0, 3.98, -3.2), NOSE, nil, 0.04)
			r:Box("Head", "NoseShine", V3(0.07, 0.04, 0.03), V3(0.05, 4.04, -3.28), C(180, 170, 180))
			r:Box("Head", "Stripe", V3(0.14, 0.06, 0.9), V3(0, 4.03, -2.62), FUR_LO)
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.28, 4.08, -2.29), 0.32, 0.34,
					{ Rim = FUR_LO, NoWhite = true, Iris = IRIS, Pupil = C(16, 10, 26), IrisK = 0.94, PupilK = 0.62, Shine = GLOW, Look = V3(s * 0.02, 0, 0) })
				r:Neon("Head", "EyeSpark_" .. side, V3(0.05, 0.05, 0.03), V3(s * 0.28 - 0.07, 4.0, -2.41), C(255, 255, 255))
				r:Tuft("Head", "Cheek_" .. side, CF(s * 0.44, 3.86, -1.86) * ANG(-0.5, 0, s * 0.8), 0.36, 0.26, 2, FLUFF, FLUFF_LO)
				-- folded rose ears with fluffy tips
				local ear = "Ear_" .. side
				r:Round(ear, "Ear_" .. side, V3(0.18, 0.32, 0.5), CF(s * 0.42, 4.3, -1.42) * ANG(0.5, 0, s * 0.45), FUR_LO, nil, 0.05)
				r:Box(ear, "EarTuft_" .. side, V3(0.16, 0.2, 0.22), CF(s * 0.5, 4.22, -1.18) * ANG(0.5, 0, s * 0.45), FLUFF)
				-- feathered antennae: a short stalk carrying a fern-like plume (a broad blade with a dark rib and notched
				-- edges) and a glowing tip
				local ant = "Antenna_" .. side
				local p0, p1, p2 = V3(s * 0.2, 4.36, -1.95), V3(s * 0.32, 4.62, -2.06), V3(s * 0.56, 5.3, -2.02)
				r:Seg(ant, "Stalk_" .. side, p0, p1, 0.06, 0.06, ANT)
				r:Seg(ant, "Plume_" .. side, p1, p1:Lerp(p2, 0.75), 0.24, 0.04, FEATHER)
				r:Seg(ant, "PlumeTip_" .. side, p1:Lerp(p2, 0.7), p2, 0.13, 0.04, FEATHER)
				r:Seg(ant, "PlumeRib_" .. side, p1, p2, 0.04, 0.06, ANT)
				for i = 1, 3 do
					local p = p1:Lerp(p2, 0.12 + i * 0.17)
					r:Box(ant, "PlumeNotch" .. i .. "_" .. side, V3(0.3, 0.025, 0.05), CF(p) * ANG(0, 0, s * 0.35), ANT)
				end
				r:Neon(ant, "AntennaTip_" .. side, V3(0.09, 0.09, 0.09), p2 + V3(s * 0.02, 0.04, 0), GLOW)
			end)
			r:Round("Jaw", "Jaw", V3(0.44, 0.14, 0.8), V3(0, 3.56, -2.66), FLUFF_LO, nil, 0.04)
			r:Box("Jaw", "Tongue", V3(0.16, 0.04, 0.24), V3(0, 3.62, -2.9), C(232, 120, 136))
			-------- moth wings: dusky violet forewings with amber-ringed eyespots, smaller hindwings behind
			local tips = {}
			r:Pair(function(s, side)
				local fore = { Main = WING, Dark = WING_DARK, Fringe = FRINGE, Ring = RING, Iris = IRIS, Glow = GLOW, EyeAt = { 0.56, -0.1 }, Mat = MAT.Fabric }
				tips[side] = mothWing(r, "Wing_" .. side, "Fore_" .. side, wingFrame(FORE, s), FORE.Len, FORE.Wid, fore)
				local hind = { Main = WING_HI, Dark = WING, Fringe = FRINGE, Ring = WING_DARK, Iris = RING, Glow = GLOW, EyeAt = { 0.5, -0.36 }, EyeK = 0.36,
					Round = true, Mat = MAT.Fabric }
				mothWing(r, "Hind_" .. side, "Hind_" .. side, wingFrame(HIND, s), HIND.Len, HIND.Wid, hind)
				r:Round("Wing_" .. side, "WingRoot_" .. side, V3(0.3, 0.26, 0.4), V3(s * FORE.X, FORE.Root, FORE.Z), FLUFF, nil, 0.08)
			end)
			-------- whip tail ending in a moth-fluff tuft
			r:Seg("Tail", "TailA", V3(0, 2.82, 1.6), V3(0, 3.02, 2.16), 0.18, 0.18, FUR)
			r:Seg("Tail2", "TailB", V3(0, 3.0, 2.12), V3(0, 3.26, 2.62), 0.15, 0.15, FUR)
			r:Seg("TailTip", "TailC", V3(0, 3.24, 2.58), V3(0, 3.42, 2.84), 0.12, 0.12, FUR_HI)
			r:Round("TailTip", "TailTuft", V3(0.3, 0.28, 0.38), V3(0, 3.48, 2.96), FLUFF, nil, 0.08)
			-------- light + ability FX hooks (MOTH SWARM): wing dust off both forewing tips, a glimmer at the antennae
			local antTip = r.Model:FindFirstChild("AntennaTip_L")
			r:Light(antTip, GLOW, 6, 0.6)
			r:Pair(function(s, side)
				r:Hook(tips[side], "Wing_" .. side, "Trail", (wingFrame(FORE, s) * CF(FORE.Len * 0.9, 0, 0)).Position, WING_HI, GLOW, 6, 0)
			end)
			r:Hook(antTip, "Antenna", "Stars", V3(0.58, 5.34, -2.02), GLOW, C(220, 236, 255), 2, 0)
		end,
	}
end

---------------------------------------------------------------- H14 BRIDEHOUND (Mythic)
do
	local COAT, COAT_HI, COAT_LO, SHADE = C(240, 236, 230), C(252, 250, 247), C(210, 204, 200), C(198, 194, 218)
	local VEIL, VEIL_EDGE, NOSE = C(214, 228, 255), C(246, 250, 255), C(84, 76, 96)
	local ROSE, ROSE_HI, ROSE_LO, LEAF = C(66, 106, 214), C(128, 168, 246), C(36, 62, 150), C(44, 88, 80)
	local PEARL, GLOW, RIBBON = C(250, 246, 240), C(150, 200, 255), C(250, 250, 255)
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.5, 0.3) },
		{ "Neck", "Body", V3(0, 3.0, -1.0) },
		{ "Bouquet", "Neck", V3(0, 2.9, -1.46) },
		{ "Head", "Neck", V3(0, 3.95, -1.62) },
		{ "Jaw", "Head", V3(0, 3.92, -2.75) },
		{ "Ear_L", "Head", V3(0.44, 4.45, -1.78) },
		{ "Ear_R", "Head", V3(-0.44, 4.45, -1.78) },
		{ "Veil", "Head", V3(0, 4.62, -1.52) },
		{ "Veil2", "Body", V3(0, 3.3, -0.45) },
		{ "Train", "Veil2", V3(0, 3.28, 1.22) },
		{ "Tail", "Body", V3(0, 3.02, 1.78) },
		{ "Tail2", "Tail", V3(0, 3.42, 2.15) },
		{ "TailTip", "Tail2", V3(0, 3.62, 2.52) },
	}
	legBones(bones, 0.48, -0.85, 1.3, 2.15, 0.4, -0.02)
	local function drape(add, veil: number, train: number, flutter: number, x: number, k: number)
		add("Veil", 0, 0, 0, -veil + 0.04 * flutter * math.sin(TAU * k * x), 0, 0.05 * flutter * math.sin(TAU * k * x + 1))
		add("Veil2", 0, 0, 0, 0, 0, 0.03 * flutter * math.sin(TAU * k * x + 0.5))
		add("Train", 0, 0, 0, -train + 0.08 * flutter * math.sin(TAU * k * x + 2), 0, 0.1 * flutter * math.sin(TAU * k * x + 1.4))
	end
	SPECS.HW_Bridehound = {
		Code = "H14",
		SignatureName = "Waltz",
		Bones = bones,
		Durations = { Idle = 4.4, Signature = 3.8 },
		Motion = { Breath = 0.04, Wag = 0.3, Stride = 0.44, Hop = 0.5, Look = 0.2 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			if clip == "Idle" then
				drape(add, 0.03, 0.04, 1, u, 1)
				add("Bouquet", 0, 0, 0, 0.04 * sinU(u, 1, 0.3), 0, 0.03 * sinU(u, 1))
				-- a wistful head tilt
				local tilt = bump(u, 0.3, 0.62)
				add("Head", 0, 0, 0, -0.05 * tilt, -0.08 * tilt, -0.18 * tilt)
				add("Ear_L", 0, 0, 0, 0, 0, 0.06 * sinU(u, 1))
				add("Ear_R", 0, 0, 0, 0, 0, -0.06 * sinU(u, 1, 0.2))
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				local a = clip == "Run" and 1.8 or 1
				drape(add, 0.12 * a, 0.25 * a, a, u, 2)
				add("Ear_L", 0, 0, 0, 0.08 * a, 0, 0.14 * a * sinU(u, k, 0.15))
				add("Ear_R", 0, 0, 0, 0.08 * a, 0, -0.14 * a * sinU(u, k, 0.15))
				add("Bouquet", 0, 0, 0, 0.15 * a * sinU(u, k, 0.3), 0, 0)
			elseif clip == "DigLoop" then
				drape(add, 0.05, 0.1, 0.6, u, 2)
				add("Ear_L", 0, 0, 0, 0.2, 0, 0.08 * sinU(u, 1))
				add("Ear_R", 0, 0, 0, 0.2, 0, -0.08 * sinU(u, 1))
				add("Bouquet", 0, 0, 0, 0.2 + 0.1 * sinU(u, 2), 0, 0)
			elseif clip == "Sleep" then
				drape(add, 0, 0.02, 0.3, u, 1)
				add("Ear_L", 0, 0, 0, -0.1, 0, -0.12)
				add("Ear_R", 0, 0, 0, -0.1, 0, 0.12)
			elseif clip == "Sniff" then
				local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
				drape(add, 0, 0.05, 0.6, x, 3)
				add("Ear_L", 0, 0, 0, 0.35 * down, 0, 0)
				add("Ear_R", 0, 0, 0, 0.35 * down, 0, 0)
				add("Bouquet", 0, 0, 0, 0.3 * down, 0, 0)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local joy = bump(t, 0.05, d - 0.05)
				drape(add, 0.25 * joy, 0.45 * joy, 2 * joy, x, 4)
				add("Ear_L", 0, 0, 0, 0, 0, 0.3 * joy)
				add("Ear_R", 0, 0, 0, 0, 0, -0.3 * joy)
				add("Bouquet", 0, 0, 0, 0.3 * math.sin(TAU * 3 * t / d) * joy, 0, 0)
			elseif clip == "Signature" then
				-- WALTZ: a curtsy, then it rises onto its hind legs, front paws lifted together, and turns one slow full
				-- circle with the veil and the train flying out; it lands in a deep bow
				local curtsy = bump(t, 0.1, 0.95)
				add("Body", 0, -0.12 * curtsy, 0, -0.16 * curtsy, 0, 0)
				legs(add, -0.32 * curtsy, 0.16 * curtsy)
				add("Neck", 0, 0, 0, -0.2 * curtsy, 0, 0)
				add("Head", 0, 0, 0, -0.2 * curtsy, 0, 0)
				local dance = hold(t, 0.95, 1.35, 2.95, 3.3)
				add("Body", 0, 0.44 * dance, 0, 0.5 * dance, 0, 0)
				add("Leg_BL", 0, 0, 0, -0.5 * dance, 0, 0)
				add("Leg_BR", 0, 0, 0, -0.5 * dance, 0, 0)
				local sway = math.sin(TAU * 2 * t) * dance
				add("Leg_FL", 0, 0, 0, 0.95 * dance + 0.1 * sway, 0, -0.1 * dance)
				add("Leg_FR", 0, 0, 0, 0.95 * dance + 0.1 * sway, 0, 0.1 * dance)
				add("Paw_FL", 0, 0, 0, -0.7 * dance, 0, 0)
				add("Paw_FR", 0, 0, 0, -0.7 * dance, 0, 0)
				add("Root", 0, 0, 0, 0, TAU * rise(t, 1.25, 3.05), 0)
				add("Neck", 0, 0, 0, -0.3 * dance, 0, 0)
				add("Head", 0, 0, 0, -0.15 * dance, 0, 0.12 * math.sin(TAU * 1.5 * t) * dance)
				drape(add, 0.12 * dance, 0.28 * dance, 1.6 * dance, t / d, 6)
				add("Ear_L", 0, 0, 0, 0, 0, 0.35 * dance)
				add("Ear_R", 0, 0, 0, 0, 0, -0.35 * dance)
				add("Bouquet", 0, 0, 0, -0.2 * dance, 0, 0.15 * sway)
				local bow = bump(t, 3.2, d)
				add("Neck", 0, 0, 0, -0.2 * bow, 0, 0)
				add("Head", 0, 0, 0, -0.3 * bow, 0, 0)
				tail(add, 0.2 * dance, 0.4 * dance, t / d, 4)
			end
		end,
		Build = function(r)
			-------- an elegant silky hound: long ivory coat falling in a skirt of strands, a feathered chest
			r:Round("Body", "Torso", V3(1.3, 1.24, 2.8), V3(0, 2.62, 0.4), COAT, nil, 0.24, COAT_HI)
			r:Round("Body", "Chest", V3(1.36, 1.5, 0.95), V3(0, 2.52, -0.82), COAT, nil, 0.26, COAT_HI)
			local skirt = { { -0.95, 0.72 }, { -0.5, 0.82 }, { -0.05, 0.76 }, { 0.4, 0.84 }, { 0.85, 0.74 }, { 1.3, 0.62 } }
			r:Pair(function(s, side)
				for i, sk in ipairs(skirt) do
					r:Tuft("Body", "Skirt" .. i .. "_" .. side, CF(s * 0.66, 2.32, sk[1]) * ANG(0, 0, s * 0.06), sk[2], 0.3, 3, i % 2 == 0 and COAT_HI or COAT,
						i % 2 == 0 and SHADE or COAT_LO, nil, 1.5)
				end
			end)
			for i, bx in ipairs({ -0.34, 0, 0.34 }) do
				r:Tuft("Body", "Bib" .. i, CF(bx, 2.62, -1.28), 0.86 - math.abs(bx) * 0.5, 0.34, 3, COAT_HI, SHADE)
			end
			-------- long fine legs with feathering; a blue garter on the left hind leg
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.48, front and -0.85 or 1.3
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				if front then
					r:Round(leg, "Thigh_" .. tag, V3(0.42, 1.25, 0.46), V3(x, 1.6, z), COAT, nil, 0.09)
					r:Tuft(leg, "Feather_" .. tag, CF(x, 1.95, z + 0.22), 0.72, 0.26, 3, COAT_HI, SHADE)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.52, 0.95, 0.8), V3(x + s * 0.02, 2.05, z + 0.05), COAT, nil, 0.16, COAT_HI)
					r:Round(leg, "Hock_" .. tag, V3(0.38, 0.72, 0.4), V3(x, 1.3, z + 0.08), COAT, nil, 0.08)
					r:Tuft(leg, "Feather_" .. tag, CF(x, 1.62, z + 0.3), 0.6, 0.26, 2, COAT_HI, SHADE)
				end
				r:Round(paw, "Shin_" .. tag, V3(0.34, 0.75, 0.36), V3(x, 0.66, z), COAT, nil, 0.07)
				r:Paw(paw, tag, x, z - 0.06, 0.46, 0.56, 0.26, COAT_LO, { Toe = COAT, Nail = SHADE })
			end
			r:Box("Leg_BL", "Garter", V3(0.44, 0.09, 0.46), V3(0.48, 1.5, 1.38), ROSE, MAT.Fabric)
			r:Box("Leg_BL", "GarterBow", V3(0.08, 0.14, 0.14), V3(0.71, 1.5, 1.38), ROSE_HI, MAT.Fabric)
			-------- the long neck with a pearl necklace
			r:Seg("Neck", "Neck", V3(0, 2.95, -1.0), V3(0, 4.05, -1.7), 0.6, 0.7, COAT)
			r:Tuft("Neck", "NeckFeather", CF(0, 3.6, -1.58) * ANG(-0.35, 0, 0), 0.7, 0.42, 3, COAT_HI, SHADE)
			for i = 0, 8 do
				local a = (i - 4) * 0.3
				r:Ball("Neck", "Pearl" .. i, 0.12, V3(0.4 * math.sin(a), 2.98 + 0.22 * (1 - math.cos(a)), -1.22 - 0.36 * math.cos(a)), PEARL, nil, { Reflectance = 0.15 })
			end
			-------- the narrow head: a silky topknot, almond moon-blue eyes with lashes, long silken ears
			r:Round("Head", "Head", V3(0.9, 0.86, 1.04), V3(0, 4.26, -1.9), COAT, nil, 0.2, COAT_HI)
			r:Round("Head", "Snout", V3(0.46, 0.4, 1.15), V3(0, 4.06, -2.9), COAT_HI, nil, 0.1)
			r:Round("Head", "Nose", V3(0.22, 0.16, 0.12), V3(0, 4.2, -3.5), NOSE, nil, 0.04)
			r:Box("Head", "NoseShine", V3(0.07, 0.04, 0.03), V3(0.05, 4.25, -3.57), C(200, 196, 220))
			r:Tuft("Head", "Topknot", CF(0, 4.6, -2.14) * ANG(-1.88, 0, 0), 0.62, 0.4, 3, COAT_HI, SHADE)
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.24, 4.34, -2.4), 0.26, 0.18,
					{ Rim = SHADE, White = C(244, 248, 255), Iris = GLOW, Glow = true, IrisK = 0.8, Pupil = C(40, 60, 110), Lid = COAT_HI, Turn = ANG(0, 0, -s * 0.15) })
				r:Box("Head", "Lash_" .. side, V3(0.12, 0.03, 0.03), CF(s * 0.37, 4.43, -2.44) * ANG(0, 0, s * 0.5), C(70, 64, 90))
				r:Box("Head", "LashB_" .. side, V3(0.08, 0.03, 0.03), CF(s * 0.39, 4.38, -2.44) * ANG(0, 0, s * 0.15), C(70, 64, 90))
				local ear = "Ear_" .. side
				r:Round(ear, "EarTop_" .. side, V3(0.24, 0.3, 0.5), V3(s * 0.45, 4.42, -1.76), COAT, nil, 0.06)
				r:Round(ear, "Ear_" .. side, V3(0.22, 1.42, 0.6), CF(s * 0.52, 3.72, -1.72) * ANG(0, 0, s * 0.06), COAT, nil, 0.06, COAT_HI)
				r:Tuft(ear, "EarStrandA_" .. side, CF(s * 0.6, 4.18, -1.52), 1.5, 0.18, 3, COAT_HI, SHADE)
				r:Tuft(ear, "EarStrandB_" .. side, CF(s * 0.6, 4.18, -1.92), 1.38, 0.18, 3, SHADE, COAT_HI)
			end)
			r:Round("Jaw", "Jaw", V3(0.4, 0.14, 0.9), V3(0, 3.82, -2.86), COAT_LO, nil, 0.04)
			-------- a crown of blue funeral roses and the tattered bridal veil it holds
			for i, a in ipairs({ -1.1, -0.55, 0, 0.55, 1.1 }) do
				local p = V3(0.42 * math.sin(a), 4.68 + 0.04 * math.cos(a), -1.66 - 0.12 * math.cos(a))
				rose(r, "Head", "CrownRose" .. i, p, i == 3 and 0.32 or 0.27, ROSE, ROSE_HI, ROSE_LO, LEAF, ANG(0, 0, -a * 0.6) * ANG(1.15, 0, 0))
			end
			r:Seg("Veil", "VeilHead", V3(0, 4.66, -1.55), V3(0, 3.62, -0.96), 1.1, 0.04, VEIL, MAT.Fabric, { Transparency = 0.45 })
			r:Pair(function(s, side)
				r:Seg("Veil", "VeilFlare_" .. side, V3(s * 0.48, 4.62, -1.58), V3(s * 0.74, 3.62, -0.98), 0.42, 0.04, VEIL, MAT.Fabric, { Transparency = 0.5 })
				r:Seg("Veil", "VeilLace_" .. side, V3(s * 0.66, 4.62, -1.58), V3(s * 0.94, 3.62, -0.98), 0.05, 0.06, VEIL_EDGE, MAT.Fabric)
			end)
			r:Seg("Veil2", "VeilNape", V3(0, 3.66, -0.98), V3(0, 3.3, -0.46), 1.24, 0.04, VEIL, MAT.Fabric, { Transparency = 0.45 })
			r:Box("Veil2", "VeilBack", V3(1.36, 0.04, 1.72), V3(0, 3.29, 0.38), VEIL, MAT.Fabric, { Transparency = 0.45 })
			r:Pair(function(s, side)
				r:Box("Veil2", "VeilSide_" .. side, V3(0.04, 0.52, 1.6), V3(s * 0.69, 3.04, 0.38), VEIL, MAT.Fabric, { Transparency = 0.45 })
				r:Box("Veil2", "VeilLaceTop_" .. side, V3(0.05, 0.05, 1.64), V3(s * 0.7, 3.28, 0.38), VEIL_EDGE, MAT.Fabric)
				for i, tl in ipairs({ { -0.2, 0.16 }, { 0.18, 0.34 }, { 0.6, 0.12 }, { 0.98, 0.26 } }) do
					r:Box("Veil2", "VeilTear" .. i .. "_" .. side, V3(0.04, tl[2], 0.26), V3(s * 0.69, 2.78 - tl[2] / 2, tl[1]), VEIL, MAT.Fabric, { Transparency = 0.45 })
				end
			end)
			local trainPart
			r:Pair(function(s, side)
				local a, b = V3(s * 0.4, 3.27, 1.22), V3(s * 0.58, 1.8, 1.96)
				local strip = r:Seg("Train", "Train_" .. side, a, b, 0.42, 0.04, VEIL, MAT.Fabric, { Transparency = 0.45 })
				trainPart = trainPart or strip
				r:Seg("Train", "TrainLace_" .. side, a + V3(s * 0.21, 0, 0), b + V3(s * 0.21, 0, 0), 0.05, 0.06, VEIL_EDGE, MAT.Fabric)
				for i, dx in ipairs({ -0.12, 0.06, 0.18 }) do
					local len = ({ 0.28, 0.16, 0.36 })[i]
					r:Box("Train", "TrainTear" .. i .. "_" .. side, V3(0.12, len, 0.04), CF(b + V3(s * dx, -len / 2 + 0.02, len * 0.2)) * ANG(-0.45, 0, 0), VEIL, MAT.Fabric,
						{ Transparency = 0.35 })
				end
			end)
			-------- a bouquet of blue roses tied with a white ribbon, hanging from the pearls
			rose(r, "Bouquet", "BouquetRose1", V3(0, 2.74, -1.5), 0.27, ROSE, ROSE_HI, ROSE_LO, LEAF)
			rose(r, "Bouquet", "BouquetRose2", V3(0.22, 2.6, -1.45), 0.22, ROSE_HI, ROSE, ROSE_LO, LEAF, ANG(0, 0.3, 0))
			rose(r, "Bouquet", "BouquetRose3", V3(-0.22, 2.6, -1.45), 0.22, ROSE, ROSE_HI, ROSE_LO, LEAF, ANG(0, -0.3, 0))
			r:Box("Bouquet", "Stems", V3(0.14, 0.32, 0.08), V3(0, 2.36, -1.44), LEAF)
			r:Box("Bouquet", "Bow", V3(0.36, 0.1, 0.06), V3(0, 2.9, -1.46), RIBBON, MAT.Fabric)
			local gem = r:Neon("Bouquet", "BowGem", V3(0.09, 0.09, 0.05), V3(0, 2.9, -1.5), GLOW)
			r:Pair(function(s, side)
				r:Box("Bouquet", "RibbonTail_" .. side, V3(0.06, 0.4, 0.04), CF(s * 0.1, 2.24, -1.46) * ANG(0, 0, s * 0.2), RIBBON, MAT.Fabric)
			end)
			r:Light(gem, GLOW, 7, 0.8)
			-------- a long plumed tail
			r:Seg("Tail", "TailA", V3(0, 3.02, 1.78), V3(0, 3.42, 2.15), 0.24, 0.24, COAT)
			r:Seg("Tail2", "TailB", V3(0, 3.42, 2.15), V3(0, 3.62, 2.52), 0.22, 0.22, COAT)
			r:Seg("TailTip", "TailC", V3(0, 3.62, 2.52), V3(0, 3.55, 2.85), 0.2, 0.2, COAT_HI)
			r:Round("TailTip", "TailCurl", V3(0.3, 0.3, 0.36), V3(0, 3.45, 2.95), COAT_HI, nil, 0.08)
			r:Tuft("Tail", "PlumeA", CF(0, 3.18, 1.98), 0.55, 0.26, 2, COAT_HI, SHADE)
			r:Tuft("Tail2", "PlumeB", CF(0, 3.5, 2.35), 0.6, 0.26, 2, COAT_HI, SHADE)
			r:Tuft("TailTip", "PlumeC", CF(0, 3.52, 2.72), 0.45, 0.22, 2, SHADE, COAT_HI)
			-------- ability FX hooks (ETERNAL VOW): moonlit wisps off the train, petals of light round the bouquet
			r:Hook(trainPart, "Train", "Wisps", V3(0.5, 2.1, 1.8), GLOW, C(230, 240, 255), 3, 0)
			r:Hook(gem, "Bouquet", "Stars", V3(0, 2.7, -1.6), ROSE_HI, GLOW, 2, 0)
		end,
	}
end

---------------------------------------------------------------- H15 BELLKEEPER WOLF (Mythic)
do
	local FUR, FUR_HI, FUR_LO = C(118, 120, 134), C(152, 154, 168), C(82, 82, 96)
	local DARK, DARK_HI, CREAM, CREAM_LO, NOSE = C(52, 50, 64), C(72, 70, 86), C(214, 212, 206), C(186, 182, 176), C(20, 18, 24)
	local VIOLET, VIOLET_HOT = C(170, 100, 255), C(228, 196, 255)
	local ROPE, ROPE_LO, BRONZE, BRONZE_HI, BRONZE_LO = C(172, 132, 82), C(126, 92, 56), C(198, 136, 60), C(238, 186, 104), C(132, 82, 34)
	-- the bell-rope sash: a loop from the left withers across the chest, round the right flank and back over the hips
	local PATH = { V3(0.5, 3.66, -0.5), V3(0.94, 3.1, -1.0), V3(0.4, 2.52, -1.5), V3(-0.3, 2.2, -1.48), V3(-0.94, 2.2, -0.85),
		V3(-0.86, 2.36, 0.0), V3(-0.86, 2.74, 0.82), V3(-0.5, 3.38, 1.26), V3(0.32, 3.42, 0.95), V3(0.52, 3.44, 0.2) }
	-- bells: {bone, top (its loop), size, where it hangs on the rope}
	local BELLS = {
		{ "Bell_1", V3(0.06, 2.32, -1.8), 0.58, V3(0.06, 2.4, -1.52) },
		{ "Bell_2", V3(-1.08, 2.26, 0.0), 0.5, V3(-0.9, 2.36, 0.0) },
		{ "Bell_3", V3(-1.06, 2.64, 0.82), 0.46, V3(-0.9, 2.74, 0.82) },
	}
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.55, 0.3) },
		{ "Neck", "Body", V3(0, 3.1, -1.05) },
		{ "Head", "Neck", V3(0, 3.7, -1.75) },
		{ "Jaw", "Head", V3(0, 3.48, -2.85) },
		{ "Ear_L", "Head", V3(0.42, 4.38, -1.78) },
		{ "Ear_R", "Head", V3(-0.42, 4.38, -1.78) },
		{ "Tail", "Body", V3(0, 3.05, 1.85) },
		{ "Tail2", "Tail", V3(0, 2.75, 2.4) },
		{ "TailTip", "Tail2", V3(0, 2.3, 2.75) },
	}
	for _, b in ipairs(BELLS) do
		table.insert(bones, { b[1], "Body", b[2] })
	end
	legBones(bones, 0.56, -0.85, 1.4, 2.05, 0.42, -0.04)
	SPECS.HW_BellkeeperWolf = {
		Code = "H15",
		SignatureName = "ResonantHowl",
		Bones = bones,
		Durations = { Idle = 4.4, Signature = 3.8 },
		Motion = { Breath = 0.045, Wag = 0.25, Stride = 0.46, Hop = 0.5, Look = 0.24 },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the bells swing one after another (a lag along the rope)
			local function bells(a: number, k: number, side: number)
				for i, b in ipairs(BELLS) do
					add(b[1], 0, 0, 0, a * math.sin(TAU * (k * x - 0.12 * i)), 0, side * math.sin(TAU * (k * x - 0.12 * i - 0.25)))
				end
			end
			if clip == "Idle" then
				bells(0.06, 1, 0.04)
				-- now and then it gives the chest bell a little toll
				local toll = bump(u, 0.5, 0.72)
				add("Bell_1", 0, 0, 0, 0.4 * toll * math.sin(TAU * 4 * (u - 0.5) / 0.22), 0, 0)
				add("Ear_L", 0, 0, 0, -0.1 * toll, 0, 0)
				add("Ear_R", 0, 0, 0, -0.1 * toll, 0, 0)
			elseif clip == "Walk" then
				bells(0.3, 2, 0.1)
			elseif clip == "Run" then
				bells(0.5, 2, 0.18)
			elseif clip == "DigLoop" then
				bells(0.25, 2, 0.08)
			elseif clip == "Sleep" then
				bells(0.02, 1, 0)
			elseif clip == "Sniff" then
				local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
				for i, b in ipairs(BELLS) do
					add(b[1], 0, 0, 0, (0.3 + 0.1 * math.sin(TAU * 1.5 * t - i)) * down, 0, 0)
				end
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local joy = bump(t, 0.05, d - 0.05)
				for i, b in ipairs(BELLS) do
					add(b[1], 0, 0, 0, 0.55 * math.sin(TAU * (5 * t / d - 0.12 * i)) * joy, 0, 0.2 * math.sin(TAU * (4 * t / d - 0.12 * i)) * joy)
				end
			elseif clip == "Signature" then
				-- RESONANT HOWL: it sits back and howls at the ceiling of the world; the bells answer one after another
				-- in a travelling wave and the whole wolf trembles with the resonance
				local k = hold(t, 0.1, 0.55, d - 0.55, d - 0.1)
				sit(add, k, 0.5)
				local howl = hold(t, 0.8, 1.2, d - 1.0, d - 0.55)
				add("Neck", 0, 0, 0, 0.5 * howl, 0, 0)
				add("Head", 0, 0, 0, 0.45 * howl, 0, 0.04 * math.sin(TAU * 7 * t) * howl)
				add("Jaw", 0, 0, 0, -0.52 * howl - 0.06 * math.sin(TAU * 9 * t) * howl, 0, 0)
				add("Ear_L", 0, 0, 0, -0.35 * howl, 0, 0)
				add("Ear_R", 0, 0, 0, -0.35 * howl, 0, 0)
				local ring = hold(t, 1.0, 1.3, 3.0, 3.4)
				for i, b in ipairs(BELLS) do
					local ph = t - 1.0 - 0.16 * (i - 1)
					add(b[1], 0, 0, 0, 0.65 * math.sin(TAU * 2.5 * ph) * ring, 0, 0.25 * math.sin(TAU * 3.5 * ph) * ring)
				end
				add("Body", 0.012 * math.sin(TAU * 14 * t) * ring, 0, 0, 0, 0, 0)
				tail(add, -0.2 * k, 0.3 * k, t / d, 3)
			end
		end,
		Build = function(r)
			-------- a big ash-grey wolf: a heavy shoulder ruff, a dark saddle, cream chest and belly
			r:Round("Body", "Torso", V3(1.6, 1.45, 3.0), V3(0, 2.62, 0.4), FUR, nil, 0.26, FUR_HI)
			r:Round("Body", "Ruff", V3(1.8, 1.75, 1.15), V3(0, 2.75, -0.78), FUR_HI, nil, 0.3, C(172, 174, 188))
			r:Round("Body", "Saddle", V3(1.3, 0.1, 1.9), V3(0, 3.36, 0.65), DARK, nil, 0.04)
			r:Pair(function(s, side)
				r:Box("Body", "FlankShade_" .. side, V3(0.04, 0.5, 2.0), V3(s * 0.81, 3.02, 0.6), DARK_HI)
				for i, z in ipairs({ -1.05, -0.6, -0.15 }) do
					r:Tuft("Body", "RuffTuft" .. i .. "_" .. side, CF(s * 0.84, 3.2 - i * 0.12, z) * ANG(0, 0, s * 0.35), 0.6, 0.42, 2, FUR_HI, FUR)
				end
			end)
			r:Round("Body", "ChestCream", V3(1.1, 1.1, 0.16), V3(0, 2.4, -1.4), CREAM, nil, 0.06)
			r:Box("Body", "Belly", V3(1.2, 0.1, 2.4), V3(0, 1.9, 0.4), CREAM)
			-------- the sash: a braided bell-rope loop with a knot and a tassel at the withers
			for i, p in ipairs(PATH) do
				local q = PATH[i % #PATH + 1]
				r:Seg("Body", "Rope" .. i, p, q, 0.17, 0.17, i % 2 == 0 and ROPE or ROPE_LO)
				local mid = (p + q) / 2
				local dir = (q - p).Unit
				local perp = dir:Cross(V3(0, 1, 0))
				perp = perp.Magnitude > 0.1 and perp.Unit or V3(1, 0, 0)
				r:Seg("Body", "Braid" .. i, mid - perp * 0.1 - dir * 0.05, mid + perp * 0.1 + dir * 0.05, 0.05, 0.05, ROPE_LO)
			end
			r:Round("Body", "Knot", V3(0.32, 0.3, 0.32), PATH[1], ROPE_LO, nil, 0.08)
			r:Seg("Body", "Pull", PATH[1] + V3(0.08, -0.08, -0.06), V3(0.84, 2.92, -0.66), 0.11, 0.11, ROPE)
			r:Tuft("Body", "Tassel", CF(0.86, 2.9, -0.66), 0.42, 0.24, 2, ROPE_LO, ROPE)
			-------- three bronze bells with violet runes hang from the rope (each on its own swinging bone)
			local mainBell
			for i, b in ipairs(BELLS) do
				r:Seg(b[1], "Hanger" .. i, b[4], b[2], 0.06, 0.06, ROPE_LO)
				local part = bell(r, b[1], "Bell" .. i, b[2], b[3], BRONZE, BRONZE_HI, BRONZE_LO, VIOLET)
				mainBell = mainBell or part
			end
			-------- strong legs, cream inner stripes, pale claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.56, front and -0.85 or 1.4
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				if front then
					r:Round(leg, "Thigh_" .. tag, V3(0.48, 1.25, 0.52), V3(x, 1.55, z), FUR, nil, 0.1)
					r:Round(leg, "Elbow_" .. tag, V3(0.56, 0.5, 0.6), V3(x, 2.0, z), FUR, nil, 0.13, FUR_HI)
					r:Box(leg, "Stripe_" .. tag, V3(0.05, 0.9, 0.28), V3(x - s * 0.245, 1.45, z), CREAM_LO)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.6, 1.0, 0.9), V3(x + s * 0.02, 2.0, z + 0.05), FUR, nil, 0.18, FUR_HI)
					r:Round(leg, "Hock_" .. tag, V3(0.42, 0.72, 0.44), V3(x, 1.3, z + 0.1), FUR, nil, 0.09)
				end
				r:Round(paw, "Shin_" .. tag, V3(0.4, 0.75, 0.42), V3(x, 0.66, z), FUR, nil, 0.08)
				r:Paw(paw, tag, x, z - 0.06, 0.56, 0.66, 0.3, FUR_LO, { Toe = FUR, Nail = CREAM })
			end
			-------- a thick maned neck
			r:Seg("Neck", "Neck", V3(0, 3.0, -1.05), V3(0, 3.85, -1.7), 0.95, 0.95, FUR_HI)
			for i = 0, 2 do
				r:Tuft("Neck", "Mane" .. i, CF(0, 4.0 - i * 0.24, -1.4 + i * 0.26) * ANG(-0.9, 0, 0), 0.55, 0.5, 2, FUR_HI, FUR)
			end
			r:Pair(function(s, side)
				r:Tuft("Neck", "NeckRuff_" .. side, CF(s * 0.5, 3.4, -1.4) * ANG(0, 0, s * 0.6), 0.55, 0.45, 2, FUR_HI, CREAM_LO)
			end)
			-------- the wolf head: dark brow and muzzle stripe, cream underjaw, slanted violet eyes, tall dark-tipped ears
			r:Round("Head", "Head", V3(1.2, 1.0, 1.15), V3(0, 3.95, -1.98), FUR, nil, 0.22, FUR_HI)
			r:Box("Head", "Brow", V3(1.0, 0.14, 0.12), V3(0, 4.22, -2.56), DARK)
			r:Box("Head", "Crest", V3(0.3, 0.06, 0.9), V3(0, 4.46, -2.0), DARK)
			r:Round("Head", "Snout", V3(0.64, 0.5, 1.1), V3(0, 3.64, -2.96), FUR, nil, 0.12, FUR_HI)
			r:Round("Head", "SnoutUnder", V3(0.62, 0.22, 0.96), V3(0, 3.46, -2.92), CREAM, nil, 0.05)
			r:Box("Head", "SnoutStripe", V3(0.3, 0.05, 0.9), V3(0, 3.895, -2.95), DARK)
			r:Round("Head", "Nose", V3(0.3, 0.22, 0.18), V3(0, 3.84, -3.52), NOSE, nil, 0.05)
			r:Box("Head", "NoseShine", V3(0.09, 0.05, 0.03), V3(0.07, 3.91, -3.62), C(150, 150, 170))
			r:Pair(function(s, side)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.3, 4.0, -2.56), 0.32, 0.24,
					{ Rim = DARK, White = C(236, 226, 255), Iris = VIOLET, Glow = true, IrisK = 0.86, Pupil = C(30, 12, 46), Turn = ANG(0, 0, s * 0.18) })
				r:Tuft("Head", "Cheek_" .. side, CF(s * 0.6, 3.72, -1.95) * ANG(-0.5, 0, s * 0.9), 0.5, 0.36, 3, FUR_HI, CREAM_LO)
				local ear = "Ear_" .. side
				local turn = ANG(0, 0, -s * 0.14)
				r:Tri(ear, "Ear_" .. side, V3(s * 0.42, 4.78, -1.78), 0.56, 0.88, 0.14, FUR, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.41, 4.72, -1.86), 0.3, 0.52, 0.04, CREAM_LO, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarTip_" .. side, (CF(V3(s * 0.42, 4.78, -1.78)) * turn * CF(0, 0.29, -0.005)).Position, 0.2, 0.3, 0.155, DARK, MAT.SmoothPlastic, false, turn)
				r:Box(ear, "EarBase_" .. side, V3(0.48, 0.14, 0.22), V3(s * 0.42, 4.4, -1.78), FUR_HI)
				r:Box("Jaw", "Fang_" .. side, V3(0.06, 0.12, 0.06), V3(s * 0.18, 3.43, -3.26), C(244, 240, 232))
			end)
			r:Round("Jaw", "Jaw", V3(0.56, 0.18, 0.9), V3(0, 3.32, -2.88), CREAM_LO, nil, 0.05)
			r:Box("Jaw", "Tongue", V3(0.22, 0.04, 0.3), V3(0, 3.42, -3.0), C(200, 96, 120))
			-------- a big bushy tail with a dark tip
			r:Seg("Tail", "TailA", V3(0, 3.05, 1.85), V3(0, 2.75, 2.4), 0.5, 0.5, FUR)
			r:Seg("Tail2", "TailB", V3(0, 2.75, 2.4), V3(0, 2.3, 2.75), 0.48, 0.48, FUR_HI)
			r:Seg("TailTip", "TailC", V3(0, 2.3, 2.75), V3(0, 1.95, 2.88), 0.38, 0.38, DARK)
			r:Round("Tail", "TailFluffA", V3(0.56, 0.56, 0.5), V3(0, 2.9, 2.14), FUR, nil, 0.12)
			r:Round("Tail2", "TailFluffB", V3(0.54, 0.5, 0.5), V3(0, 2.52, 2.6), FUR_HI, nil, 0.12)
			-------- light + ability FX hooks (RESONANT HOWL): violet resonance sparkling off the bells
			local rune = r.Model:FindFirstChild("Bell1Rune")
			r:Light(rune, VIOLET, 7, 0.9)
			r:Hook(mainBell, "Bell", "Stars", BELLS[1][2] - V3(0, 0.3, 0), VIOLET_HOT, VIOLET, 4, 1.0)
			r:Hook(r.Model:FindFirstChild("Bell3Body"), "BellB", "Stars", BELLS[3][2] - V3(0, 0.25, 0), VIOLET, VIOLET_HOT, 2, 0)
		end,
	}
end

---------------------------------------------------------------- H16 HOLLOW KING (SECRET)
do
	local INK, INK_HI, INK_LO = C(26, 22, 40), C(50, 42, 72), C(12, 10, 20)
	local BONE, BONE_HI, BONE_LO = C(232, 224, 204), C(250, 246, 232), C(186, 176, 156)
	local VIOLET, VIOLET_HOT, VIOLET_DEEP, VOIDC = C(150, 80, 230), C(218, 176, 255), C(84, 36, 140), C(70, 26, 120)
	local MOON, BLACKMOON, IRON, IRON_HI = C(170, 210, 255), C(8, 6, 12), C(66, 58, 84), C(110, 100, 136)
	local CAPE, CAPE_HI, CAPE_LO = C(58, 36, 92), C(90, 60, 134), C(32, 20, 54)
	local FORE = { Len = 2.15, Wid = 1.1, Raise = 0.62, Sweep = 1.02, Root = 3.72, Z = -0.62, X = 0.38 }
	local HIND = { Len = 1.45, Wid = 1.0, Root = 3.5, Z = 0.8, X = 0.32 }
	local CROWN = V3(0, 4.92, -1.86)
	local function foreFrame(s: number): CFrame
		return CF(s * FORE.X, FORE.Root, FORE.Z) * ANG(0, -s * FORE.Sweep, 0) * ANG(0, 0, s * FORE.Raise)
			* CFrame.fromMatrix(V3(), V3(s, 0, 0), V3(0, 0, -1))
	end
	-- hindwings lie back along the hips, their broad edge falling outward over the haunches
	local function hindFrame(s: number): CFrame
		local x = V3(s * 0.25, -0.35, 1).Unit
		local yr = V3(-s, 0.75, 0)
		local y = (yr - x * yr:Dot(x)).Unit
		return CFrame.fromMatrix(V3(s * HIND.X, HIND.Root, HIND.Z), x, y, x:Cross(y))
	end
	local bones = {
		{ "Root", nil, V3(0, 0, 0) },
		{ "Body", "Root", V3(0, 2.8, 0.3) },
		{ "Heart", "Body", V3(0, 2.86, 0.18) },
		{ "Neck", "Body", V3(0, 3.3, -1.0) },
		{ "Pendant", "Neck", V3(0, 3.22, -1.46) },
		{ "Head", "Neck", V3(0, 4.12, -1.62) },
		{ "Jaw", "Head", V3(0, 4.02, -2.78) },
		{ "Ear_L", "Head", V3(0.52, 4.8, -1.7) },
		{ "Ear_R", "Head", V3(-0.52, 4.8, -1.7) },
		{ "Crown", "Head", CROWN },
		{ "Fire", "Crown", CROWN + V3(0, 0.12, 0) },
		{ "Cape_L", "Body", V3(FORE.X, FORE.Root, FORE.Z) },
		{ "Cape_R", "Body", V3(-FORE.X, FORE.Root, FORE.Z) },
		{ "Hind_L", "Body", V3(HIND.X, HIND.Root, HIND.Z) },
		{ "Hind_R", "Body", V3(-HIND.X, HIND.Root, HIND.Z) },
		{ "Tail", "Body", V3(0, 3.08, 1.66) },
		{ "Tail2", "Tail", V3(0, 3.32, 2.18) },
		{ "TailTip", "Tail2", V3(0, 3.62, 2.58) },
	}
	legBones(bones, 0.52, -0.95, 1.4, 2.35, 0.42, 0)
	local function cape(add, spread: number, back: number)
		add("Cape_L", 0, 0, 0, 0, -back, spread)
		add("Cape_R", 0, 0, 0, 0, back, -spread)
		add("Hind_L", 0, 0, 0, 0, 0, -0.4 * spread)
		add("Hind_R", 0, 0, 0, 0, 0, 0.4 * spread)
	end
	SPECS.HW_HollowKing = {
		Code = "H16",
		SignatureName = "Coronation",
		Bones = bones,
		Durations = { Idle = 5.0, Signature = 4.0 },
		Motion = { Breath = 0.035, Wag = 0.2, Stride = 0.42, Hop = 0.45, Look = 0.18, Spin = false },
		Extra = function(clip, t, d, u, add)
			local looped = E.IsLooped(clip)
			local x = looped and u or t / d
			-- the violet crown fire flickers; the hollow heart turns and beats twice per cycle
			if ambient(clip) then
				add("Fire", 0.01 * sinU(x, 13), 0.04 * (flick(x, looped and 7 or 9) - 0.5), 0, 0.06 * sinU(x, 5), TAU * (looped and 1 or 0.5) * x,
					0.06 * sinU(x, 6, 0.3))
				local n = looped and 2 or 3
				local phase = (x * n) % 1
				local beat = bump(phase, 0, 0.16) + 0.6 * bump(phase, 0.2, 0.34)
				add("Heart", 0, 0.03 * beat, 0, 0, TAU * (looped and 1 or 0.5) * x, 0)
			end
			if clip == "Idle" then
				cape(add, 0.05 * sinU(u, 1), 0)
				add("Pendant", 0, 0, 0, 0.05 * sinU(u, 1, 0.3), 0, 0.03 * sinU(u, 1))
			elseif clip == "Walk" or clip == "Run" then
				local k = clip == "Run" and 1 or 2
				local a = clip == "Run" and 1.8 or 1
				cape(add, 0.06 * a * sinU(u, 2), 0.12 * a)
				add("Pendant", 0, 0, 0, 0.2 * a * sinU(u, k, 0.3), 0, 0.05 * sinU(u, 1))
			elseif clip == "DigLoop" then
				cape(add, 0.15 + 0.04 * sinU(u, 2), 0)
				add("Pendant", 0, 0, 0, 0.3 + 0.1 * sinU(u, 2), 0, 0)
			elseif clip == "Sleep" then
				-- the cape folds down over the sleeping king, the crown burns low
				cape(add, -0.32 + 0.02 * sinU(u, 1), 0.12)
				add("Fire", 0, -0.08, 0, 0, 0, 0)
				add("Pendant", 0, 0, 0, 0.35, 0, 0)
			elseif clip == "Sniff" then
				local down = hold(t, 0.05, 0.45, d - 0.5, d - 0.05)
				cape(add, 0.08 * down, 0.05 * down)
				add("Pendant", 0, 0, 0, 0.3 * down, 0, 0.1 * math.sin(TAU * 1.2 * t) * down)
			elseif clip == "DigFind" or clip == "Happy" or clip == "RareFind" then
				local joy = bump(t, 0.05, d - 0.05)
				cape(add, 0.45 * joy + 0.15 * math.sin(TAU * 4 * t / d) * joy, -0.1 * joy)
				add("Fire", 0, 0.1 * joy, 0, 0, 0, 0)
				add("Pendant", 0, 0, 0, 0.3 * math.sin(TAU * 3 * t / d) * joy, 0, 0)
				if clip == "RareFind" then
					add("Root", 0, 0.45 * bump(t, 0.3, d - 0.2), 0, 0, 0, 0)
				end
			elseif clip == "Signature" then
				-- CORONATION: the king sits tall, the crown fire flares and turns, the moth-wing cape spreads wide and beats
				-- twice, the hollow heart pounds; then it bows its crowned head
				local k = hold(t, 0.1, 0.6, d - 0.6, d - 0.1)
				sit(add, k, 0.55)
				local proud = hold(t, 0.6, 1.0, 2.9, 3.3)
				add("Neck", 0, 0, 0, 0.25 * proud, 0, 0)
				add("Head", 0, 0, 0, -0.15 * proud, 0, 0)
				add("Jaw", 0, 0, 0, -0.1 * proud, 0, 0)
				local flare = hold(t, 0.9, 1.3, 3.0, 3.5)
				add("Fire", 0, 0.14 * flare, 0, 0, TAU * 1.5 * rise(t, 0.9, 3.5), 0)
				local spread = hold(t, 1.0, 1.5, 2.9, 3.4)
				cape(add, 0.7 * spread + 0.22 * math.sin(TAU * 1.6 * (t - 1.5)) * spread, -0.35 * spread)
				add("Heart", 0, 0.05 * math.sin(TAU * 3 * t) * flare, 0, 0, 0, 0)
				add("Pendant", 0, 0, 0, 0.25 * math.sin(TAU * 1.2 * t) * k, 0, 0)
				local bow = bump(t, 3.2, d)
				add("Neck", 0, 0, 0, -0.3 * bow, 0, 0)
				add("Head", 0, 0, 0, -0.25 * bow, 0, 0)
				tail(add, -0.1 * k, 0.25 * k, t / d, 2)
			end
		end,
		Build = function(r)
			-------- an ink-black regal hound whose middle is hollow: a bone spine and ribcage over a violet void
			r:Round("Body", "Chest", V3(1.36, 1.62, 0.92), V3(0, 2.82, -0.92), INK, nil, 0.28, INK_HI)
			r:Round("Body", "Hips", V3(1.24, 1.32, 0.86), V3(0, 2.92, 1.24), INK, nil, 0.26, INK_HI)
			for i, z in ipairs({ -0.4, -0.1, 0.2, 0.5, 0.78 }) do
				r:Box("Body", "Vertebra" .. i, V3(0.34, 0.24, 0.24), V3(0, 3.46, z), BONE)
				r:Box("Body", "Spinous" .. i, V3(0.1, 0.22, 0.12), CF(0, 3.66, z + 0.03) * ANG(-0.3, 0, 0), BONE_HI)
			end
			r:Seg("Body", "Sternum", V3(0, 2.12, -0.5), V3(0, 2.28, 0.86), 0.16, 0.14, BONE_LO)
			r:Pair(function(s, side)
				for i, rb in ipairs({ { -0.3, 1 }, { 0.0, 1 }, { 0.3, 0.95 }, { 0.58, 0.86 } }) do
					local z, k = rb[1], rb[2]
					local a, b, c, e = V3(s * 0.14, 3.42, z), V3(s * 0.6 * k, 3.18, z), V3(s * 0.64 * k, 2.6, z), V3(s * 0.08, 2.2 + (1 - k) * 0.2, z)
					r:Seg("Body", "RibTop" .. i .. "_" .. side, a, b, 0.13, 0.13, BONE)
					r:Seg("Body", "RibSide" .. i .. "_" .. side, b, c, 0.13, 0.13, BONE)
					r:Seg("Body", "RibLow" .. i .. "_" .. side, c, e, 0.12, 0.12, BONE_LO)
				end
			end)
			r:Neon("Body", "Void", V3(0.8, 0.7, 1.05), V3(0, 2.86, 0.18), VOIDC, { Transparency = 0.55 })
			-- the hollow heart: a violet flame burning in the empty ribcage
			local heart = r:Neon("Heart", "HeartCore", V3(0.26, 0.26, 0.26), CF(0, 2.82, 0.18) * ANG(0.6, 0.78, 0), VIOLET_HOT)
			flame(r, "Heart", "HeartFire", V3(0, 2.92, 0.18), 0.55, 0.32, VIOLET, VIOLET_HOT, C(250, 240, 255))
			r:Light(heart, VIOLET, 9, 1.4)
			-------- long regal legs: bone knee caps, violet bands, bone claws
			for _, l in ipairs(LEG_TAGS) do
				local tag, s, front = l[1], l[2], l[3]
				local x, z = s * 0.52, front and -0.95 or 1.4
				local leg, paw = "Leg_" .. tag, "Paw_" .. tag
				if front then
					r:Round(leg, "Thigh_" .. tag, V3(0.44, 1.32, 0.48), V3(x, 1.72, z), INK, nil, 0.09)
					r:Round(leg, "Elbow_" .. tag, V3(0.52, 0.5, 0.56), V3(x, 2.2, z), INK, nil, 0.12, INK_HI)
					r:Box(leg, "KneeCap_" .. tag, V3(0.24, 0.2, 0.08), V3(x, 1.2, z - 0.25), BONE)
				else
					r:Round(leg, "Thigh_" .. tag, V3(0.56, 1.0, 0.86), V3(x + s * 0.02, 2.2, z + 0.05), INK, nil, 0.17, INK_HI)
					r:Round(leg, "Hock_" .. tag, V3(0.38, 0.75, 0.42), V3(x, 1.4, z + 0.1), INK, nil, 0.08)
				end
				r:Round(paw, "Shin_" .. tag, V3(0.34, 0.8, 0.36), V3(x, 0.66, z), INK, nil, 0.07)
				r:Neon(paw, "Band_" .. tag, V3(0.38, 0.05, 0.4), V3(x, 1.0, z), VIOLET)
				r:Paw(paw, tag, x, z - 0.06, 0.46, 0.6, 0.26, INK_HI, { Toe = INK_HI, Nail = BONE })
			end
			-------- a tall neck behind a fan of moth-feather collar, the black moon pendant on the chest
			r:Seg("Neck", "Neck", V3(0, 3.25, -1.0), V3(0, 4.2, -1.68), 0.72, 0.82, INK)
			for i = -2, 2 do
				local frame = CF(0, 3.6, -1.0) * ANG(0, i * 0.38, 0) * CF(0, 0.42, 0.42) * ANG(-0.35, 0, 0)
				r:Box("Neck", "Collar" .. (i + 3), V3(0.36, 0.95, 0.06), frame, i % 2 == 0 and CAPE or CAPE_HI, MAT.Fabric)
				r:Neon("Neck", "CollarTrim" .. (i + 3), V3(0.36, 0.05, 0.08), frame * CF(0, 0.47, 0), VIOLET)
			end
			r:Pair(function(s, side)
				r:Seg("Pendant", "Chain_" .. side, V3(s * 0.34, 3.6, -1.26), V3(s * 0.05, 3.18, -1.46), 0.05, 0.05, IRON_HI, MAT.Metal)
			end)
			r:Box("Pendant", "Bail", V3(0.1, 0.12, 0.06), V3(0, 3.18, -1.46), IRON_HI, MAT.Metal)
			r:Cyl("Pendant", "MoonRim", 0.06, 0.6, CF(0, 2.86, -1.44) * ANG(0, PI / 2, 0), VIOLET, MAT.Neon)
			r:Cyl("Pendant", "BlackMoon", 0.08, 0.5, CF(0, 2.86, -1.47) * ANG(0, PI / 2, 0), BLACKMOON, nil, { Reflectance = 0.12 })
			for i, a in ipairs({ -0.75, -0.25, 0.25, 0.75 }) do
				r:Neon("Pendant", "MoonLight" .. i, V3(0.05, 0.11, 0.03), CF(0.235 * math.cos(a), 2.86 + 0.235 * math.sin(a), -1.515) * ANG(0, 0, a), MOON)
			end
			-------- the noble head under a half-mask of bone; violet eyes burning in the sockets
			r:Round("Head", "Head", V3(0.98, 0.9, 1.15), V3(0, 4.4, -1.92), INK, nil, 0.2, INK_HI)
			r:Round("Head", "Snout", V3(0.56, 0.48, 1.05), V3(0, 4.16, -2.92), INK, nil, 0.11, INK_HI)
			r:Box("Head", "MaskBrow", V3(0.9, 0.28, 0.06), V3(0, 4.62, -2.52), BONE)
			r:Box("Head", "MaskBrowEdge", V3(0.92, 0.05, 0.07), V3(0, 4.48, -2.53), BONE_LO)
			r:Box("Head", "MaskRidge", V3(0.12, 0.06, 0.62), V3(0, 4.42, -2.72), BONE)
			r:Round("Head", "Nose", V3(0.24, 0.18, 0.14), V3(0, 4.32, -3.44), INK_HI, nil, 0.04)
			r:Box("Head", "NoseShine", V3(0.07, 0.04, 0.03), V3(0.05, 4.37, -3.52), C(170, 150, 210))
			r:Pair(function(s, side)
				r:Box("Head", "MaskCheek_" .. side, V3(0.06, 0.3, 0.52), V3(s * 0.48, 4.3, -2.2), BONE_LO)
				r:Eye("Head", "Eye_" .. side, V3(s * 0.26, 4.34, -2.5), 0.28, 0.2,
					{ Rim = INK_LO, NoWhite = true, Iris = VIOLET_HOT, Glow = true, IrisK = 1, PupilK = 0.35, Pupil = VIOLET_DEEP, Turn = ANG(0, 0, s * 0.2) })
				local ear = "Ear_" .. side
				local turn = ANG(0, 0, -s * 0.12)
				r:Tri(ear, "Ear_" .. side, V3(s * 0.52, 5.18, -1.7), 0.5, 0.95, 0.14, INK, MAT.SmoothPlastic, false, turn)
				r:Tri(ear, "EarIn_" .. side, V3(s * 0.51, 5.12, -1.78), 0.26, 0.56, 0.04, VIOLET_DEEP, MAT.SmoothPlastic, false, turn)
				r:Box(ear, "EarBase_" .. side, V3(0.4, 0.14, 0.22), V3(s * 0.48, 4.8, -1.7), INK_HI)
				r:Box("Jaw", "Fang_" .. side, V3(0.06, 0.12, 0.06), V3(s * 0.17, 3.98, -3.22), BONE)
			end)
			r:Round("Jaw", "Jaw", V3(0.5, 0.16, 0.84), V3(0, 3.86, -2.86), INK_HI, nil, 0.04)
			-------- the crown: an iron circlet with bone spikes, each spike and the heart of the crown burning violet
			for i = 0, 7 do
				local a = i / 8 * TAU
				r:Box("Crown", "Circlet" .. i, V3(0.22, 0.14, 0.08), CF(CROWN + V3(0.27 * math.cos(a), 0, 0.27 * math.sin(a))) * ANG(0, -a + PI / 2, 0), IRON, MAT.Metal)
			end
			local spikes = {}
			for i, a in ipairs({ -PI / 2, -PI / 2 + 0.9, -PI / 2 - 0.9, -PI / 2 + 1.8, -PI / 2 - 1.8 }) do
				local h = i == 1 and 0.42 or (i <= 3 and 0.34 or 0.28)
				local base = CROWN + V3(0.27 * math.cos(a), 0.07 + h / 2, 0.27 * math.sin(a))
				r:Box("Crown", "Spike" .. i, V3(0.1, h, 0.1), base, BONE)
				r:Box("Crown", "SpikeTip" .. i, V3(0.06, 0.1, 0.06), base + V3(0, h / 2 + 0.05, 0), BONE_HI)
				spikes[i] = base + V3(0, h / 2 + 0.1, 0)
			end
			r:Neon("Crown", "CrownGem", V3(0.12, 0.12, 0.05), CROWN + V3(0, 0.02, -0.31), VIOLET_HOT)
			local fire = flame(r, "Fire", "CrownFire", CROWN + V3(0, 0.08, 0), 0.72, 0.34, VIOLET, VIOLET_HOT, C(250, 240, 255))
			for i, p in ipairs(spikes) do
				flame(r, "Fire", "SpikeFire" .. i, p, i == 1 and 0.34 or 0.26, i == 1 and 0.17 or 0.14, VIOLET, VIOLET_HOT)
			end
			r:Light(fire, VIOLET_HOT, 8, 1.0)
			-------- the cape of moth wings: tall forewings rising behind the shoulders, hindwings over the haunches
			local tips = {}
			r:Pair(function(s, side)
				local fore = { Main = CAPE, Dark = CAPE_LO, Fringe = BONE_LO, Ring = BONE, Iris = VIOLET_DEEP, Glow = VIOLET_HOT, Edge = VIOLET,
					EyeAt = { 0.55, -0.12 }, Mat = MAT.Fabric }
				tips[side] = mothWing(r, "Cape_" .. side, "Cape_" .. side, foreFrame(s), FORE.Len, FORE.Wid, fore)
				local hind = { Main = CAPE_HI, Dark = CAPE, Fringe = BONE_LO, Ring = VIOLET_DEEP, Iris = BONE, Glow = VIOLET, EyeAt = { 0.5, -0.36 },
					EyeK = 0.36, Round = true, Mat = MAT.Fabric }
				mothWing(r, "Hind_" .. side, "Hind_" .. side, hindFrame(s), HIND.Len, HIND.Wid, hind)
				r:Round("Cape_" .. side, "Clasp_" .. side, V3(0.3, 0.3, 0.3), V3(s * FORE.X, FORE.Root, FORE.Z), BONE, nil, 0.07)
				r:Neon("Cape_" .. side, "ClaspGem_" .. side, V3(0.12, 0.12, 0.12), V3(s * FORE.X, FORE.Root + 0.02, FORE.Z - 0.14), VIOLET_HOT)
			end)
			r:Round("Body", "Mantle", V3(0.95, 0.14, 0.5), V3(0, 3.68, -0.62), CAPE, MAT.Fabric, 0.04, CAPE_HI)
			-------- a long ink tail with bone plates and a violet flame at the tip
			r:Seg("Tail", "TailA", V3(0, 3.08, 1.66), V3(0, 3.32, 2.18), 0.26, 0.26, INK)
			r:Seg("Tail2", "TailB", V3(0, 3.32, 2.18), V3(0, 3.62, 2.58), 0.22, 0.22, INK)
			r:Seg("TailTip", "TailC", V3(0, 3.62, 2.58), V3(0, 3.78, 2.82), 0.18, 0.18, INK_HI)
			r:Seg("Tail", "TailPlateA", V3(0, 3.22, 1.76), V3(0, 3.44, 2.12), 0.12, 0.08, BONE)
			r:Seg("Tail2", "TailPlateB", V3(0, 3.44, 2.24), V3(0, 3.72, 2.56), 0.1, 0.07, BONE)
			flame(r, "TailTip", "TailFire", V3(0, 3.82, 2.86), 0.4, 0.2, VIOLET, VIOLET_HOT)
			-------- ability FX hooks (CROWN OF THE UNDERYARD): crown fire, the soul in the ribs, moth dust off the cape
			r:Hook(fire, "Crown", "Flame", CROWN + V3(0, 0.45, 0), VIOLET_HOT, VIOLET, 5, 1.2)
			r:Hook(heart, "Heart", "Soul", V3(0, 2.95, 0.18), VIOLET, VIOLET_HOT, 4, 0)
			r:Pair(function(s, side)
				r:Hook(tips[side], "Cape_" .. side, "Trail", (foreFrame(s) * CF(FORE.Len * 0.86, -FORE.Wid * 0.3, 0)).Position, VIOLET, VIOLET_HOT, 4, 0)
			end)
		end,
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Public API (mirrors Models.EventDogs; the specs are registered in EventDogs.Specs so its builders serve them too)
---------------------------------------------------------------------------------------------------------------------
for _, id in ipairs(D.Order) do
	local spec = SPECS[id]
	assert(spec, "EventDogs2: no spec for " .. id)
	spec.EventDex = D.EventDex
	E.Specs[id] = spec
end

function D.Has(id: string): boolean
	return SPECS[id] ~= nil
end
function D.Spec(id: string)
	return SPECS[id]
end
function D.BoneNames(id: string): { string }
	return E.BoneNames(id)
end
-- every clip saved for a dog: D.ClipNames + its signature clip under the dog's own name
function D.ClipNamesFor(id: string): { string }
	return E.ClipNamesFor(id)
end
function D.Duration(id: string, clip: string): number
	return E.Duration(id, clip)
end
function D.IsLooped(clip: string): boolean
	return E.IsLooped(clip)
end
-- One clip as the DogAnimationPlayer table {duration, loop, fps, category, tracks} (nil for an unknown dog / clip).
function D.Clip(id: string, clipName: string): any
	if not SPECS[id] then
		return nil
	end
	return E.Clip(id, clipName)
end
D.Serialize = E.Serialize

-- The clip folder attributes DogAnimationPlayer reads (role -> clip name) plus provenance.
function D.FolderAttributes(id: string): { [string]: string }
	local spec = SPECS[id]
	return { Generated = D.Generated, IdleClip = "Idle", WalkClip = "Walk", WorkClip = "DigLoop", SignatureClip = spec and spec.SignatureName or "Signature" }
end
-- The first line of a generated clip ModuleScript.
function D.ClipHeader(id: string, clip: string): string
	return string.format("-- %s.%s (generated by tools/edits/30_dogs2.luau from RS.Halloween.Models.EventDogs2; do not edit)\n", id, clip)
end

-- A fresh model of an Underyard event dog (not parented). opts.Name overrides the model name.
function D.Build(id: string, opts: any?): Model?
	if not SPECS[id] then
		return nil
	end
	local model = E.Build(id, opts)
	if model then
		model:SetAttribute("EventDex", D.EventDex)
		model:SetAttribute("Chapter", 2)
	end
	return model
end

-- Ability FX (client): the same HwFX_* hook runner as the Chapter I dogs.
D.StartFX = E.StartFX
D.BurstFX = E.BurstFX

return D
