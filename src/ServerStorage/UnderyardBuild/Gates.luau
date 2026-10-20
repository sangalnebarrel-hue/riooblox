-- THE UNDERYARD · the five veiled gates (ServerStorage.UnderyardBuild.Gates, WP-G, Order 35). Build-time only:
-- tools/edits/40_underyard.luau runs it through tools/sim.luau; saved as 40_Underyard.Gates.Gate_<District>.
-- One arch per UnderyardLayout.Gates entry, standing on the ring road's gate landing, opening (local -Z) towards the
-- district: UKit.VeilArch (crooked pillars, black/white striped pointed arch, dog-skull keystone, hanging bell) plus
--   * the SPECTRAL VEIL filling the opening, crossed chains with a padlock and the hanging SEAL PLAQUE: every one of
--     these parts carries UyHideAtSeal = UnderyardLayout.Unlock[district] (client UnderyardFX hides them per player
--     once that many seals are cleared, LocalTransparencyModifier for parts, Enabled = false for the SurfaceGuis);
--   * the seal plaque's SurfaceGui (square side) says SEALED / ЗАПЕЧАТАНО and a second plate BELL SEAL <n> /
--     ПЕЧАТЬ КОЛОКОЛА <n>: NoTranslate + TextEN / TextRU on the gui and its label, attribute Seal = n;
--   * the district name board above the arch (always visible): TextEN / TextRU from UnderyardLayout.Names;
--   * a gate lantern whose PointLight carries UyLightAtSeal = n (dark until the district opens for that player);
--   * dog gargoyles on the pillar tops looking down the road, bone posts beside the plinths.
-- The Model carries UyGate = district name and UyHideAtSeal-free frame parts; nothing collides inside the opening
-- (16 studs between the pillars, 14.8 between the plinths).
local U = require(script.Parent.UKit)
local K, Y = U.K, U.Y
local P = U.P
local C = U.C
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local M = Enum.Material
local N = Enum.NormalId
local PI = math.pi

local Gates = { Order = 35 }

local OPEN_W = 16 -- clear opening
local PILLAR_H = 15
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }

function Gates.Build(ctx)
	local L = ctx.Layout
	local rng = U.Rng(40035)
	local root = ctx.Model("Gates")
	local lights = 0
	local names = {}
	for name in pairs(L.Gates) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local g = L.Gates[name]
		local seal = L.Unlock[name] or 0
		local hide = { UyHideAtSeal = seal }
		local base = K.Look(g.Position, g.Position + g.Facing) -- -Z faces the district
		local arch = U.VeilArch(root, base, OPEN_W, PILLAR_H, rng, { VeilAttrs = hide, Name = "Gate_" .. name })
		local m = arch.Model
		m:SetAttribute("UyGate", name)
		m:SetAttribute("UySeal", seal)
		local tagged = {}
		for _, p in ipairs(arch.Veil) do
			table.insert(tagged, p)
		end
		-- crossed chains + padlock across the opening (square side)
		local chainParts = {}
		for _, sx in ipairs({ -1, 1 }) do
			local cm = K.Chain(m, (base * CF(sx * (OPEN_W / 2 - .2), 11.5, 1.1)).Position, (base * CF(-sx * (OPEN_W / 2 - .2), 3.2, 1.1)).Position, .6, 14)
			for _, p in ipairs(U.PartsOf(cm)) do
				table.insert(chainParts, p)
			end
		end
		local lock = K.Part(m, "GatePadlock", V3(1.4, 1.6, .6), base * CF(0, 7.2, 1.35), C(150, 120, 60), M.Metal)
		local shackle = K.CylZ(m, "GatePadlockShackle", .3, 1.1, base * CF(0, 8.3, 1.35), P.Iron, M.Metal)
		table.insert(chainParts, lock)
		table.insert(chainParts, shackle)
		for _, p in ipairs(chainParts) do
			table.insert(tagged, p)
		end
		-- the seal plaque hanging from the arch on two chains, readable from the square (its Back face = +Z)
		local plaque = K.Part(m, "SealPlaque", V3(7.4, 1.8, .3), base * CF(0, 13.2, 1.5), C(26, 20, 34), M.Slate)
		local num = K.Part(m, "SealPlaqueNumber", V3(5.2, 1.1, .3), base * CF(0, 11.9, 1.5), C(26, 20, 34), M.Slate)
		local rim = K.Part(m, "SealPlaqueRim", V3(7.8, 2.2, .2), base * CF(0, 13.2, 1.38), U.GLOW.Violet, M.Neon, { Transparency = .2 })
		local wax = K.CylZ(m, "SealWax", .25, 1.3, base * CF(-3.9, 12.4, 1.7), C(150, 30, 60), M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			local ch = K.Chain(m, (arch.Apex * CF(sx * 2.6, -1.6, 1.5)).Position, (base * CF(sx * 3.4, 14.1, 1.5)).Position, .2, 4)
			for _, p in ipairs(U.PartsOf(ch)) do
				table.insert(tagged, p)
			end
		end
		for _, p in ipairs({ plaque, num, rim, wax }) do
			table.insert(tagged, p)
		end
		local g1 = U.Sign(plaque, N.Back, "SEALED", "ЗАПЕЧАТАНО", C(225, 200, 255), { PixelsPerStud = 30, Stroke = false, H = .8, W = .9, Name = "SealSign" })
		local g2 = U.Sign(num, N.Back, "BELL SEAL " .. (ROMAN[seal] or tostring(seal)), "ПЕЧАТЬ КОЛОКОЛА " .. (ROMAN[seal] or tostring(seal)), P.Bone,
			{ PixelsPerStud = 30, Stroke = false, H = .8, W = .9, Name = "SealNumberSign" })
		for _, gui in ipairs({ g1, g2 }) do
			gui:SetAttribute("Seal", seal)
			gui:SetAttribute("UyHideAtSeal", seal)
		end
		U.Tag(tagged, hide)
		-- the district name board above the arch (always visible, both faces)
		local nm = L.Names[name] or { name, name }
		local board = K.Part(m, "GateNameBoard", V3(OPEN_W + 2, 2.2, .4), arch.Apex * CF(0, 2.6, 0) * ANG(0, 0, rng:NextNumber(-.04, .04)), P.WoodDark,
			M.WoodPlanks)
		K.Part(m, "GateNameTrim", V3(OPEN_W + 2.4, .3, .5), board.CFrame * CF(0, 1.2, 0), P.Iron, M.CorrodedMetal)
		K.Part(m, "GateNameTrim", V3(OPEN_W + 2.4, .3, .5), board.CFrame * CF(0, -1.2, 0), P.Iron, M.CorrodedMetal)
		U.Sign(board, N.Back, nm[1], nm[2], P.Bone, { PixelsPerStud = 24, Stroke = false, H = .8, W = .94, Name = "GateName" })
		U.Sign(board, N.Front, nm[1], nm[2], P.Bone, { PixelsPerStud = 24, Stroke = false, H = .8, W = .94, Name = "GateNameBack" })
		-- gargoyles on the pillar tops, looking down the road towards the square
		for k, top in ipairs(arch.Tops) do
			local sx = k == 1 and -1 or 1
			U.Gargoyle(m, top * ANG(0, PI + sx * .35, 0) * CF(0, 0, .3), 1.15, { Eye = U.GLOW.Violet })
		end
		-- gate lantern hanging from the right pillar (lights up when the district opens for the player)
		local lp = base * CF(OPEN_W / 2 + 3.6, 10.6, 1.4)
		K.Rod(m, "GateLanternArm", (base * CF(OPEN_W / 2 + 1.9, 11.6, 1.2)).Position, lp.Position + V3(0, .9, 0), .2, P.Iron, M.CorrodedMetal)
		local _, glass = U.Lantern(m, lp * CF(0, .9, 0), U.GLOW.Candle, "Orange", { Range = 20, Brightness = 1.1, Size = .9 })
		local gl = glass:FindFirstChildWhichIsA("Light")
		if gl then
			gl:SetAttribute("UyLightAtSeal", seal)
			gl:SetAttribute("UyBaseBrightness", gl.Brightness)
		end
		glass:SetAttribute("UyLightAtSeal", seal)
		lights += 1
		-- bone posts and candles at the plinths (square side)
		for _, sx in ipairs({ -1, 1 }) do
			local post = base * CF(sx * (OPEN_W / 2 + 5.6), 0, 2.4)
			K.CylY(m, "GateBonePost", 3.2, .6, post * CF(0, 1.6, 0), P.Bone, M.SmoothPlastic)
			K.Ball(m, "GateBoneKnuckle", .7, post * CF(-.22, 3.3, 0), P.Bone, M.SmoothPlastic)
			K.Ball(m, "GateBoneKnuckle", .7, post * CF(.22, 3.3, 0), P.Bone, M.SmoothPlastic)
		end
		-- fog / wisp hooks for the client veil FX
		Y.AttachAt(plaque, "VeilCentre", (base * CF(0, PILLAR_H * .5, 0)).Position, { Gate = name, Seal = seal })
	end
	root:SetAttribute("Lights", lights)
	if ctx.Note then
		ctx.Note(string.format("Gates: %d parts, %d gates, %d lights", K.Count(root), #names, lights))
	end
end

return Gates
