--!nolint
-- Chapter II pickaxe skins (ReplicatedStorage.Halloween.PickaxeSkins2) registered into PickaxeSkins:
-- lune run tests/pickaxe_skins2.luau
-- Runs the real modules (tests/lib/economy_env): registration and its idempotence, the resolver overlays only the VISUAL
-- keys, the skins carry no stat keys, Skins.Of ignores the event switch, every design builds a sound model, every
-- sound kit follows the soft-impact rule, palettes / crit stamps / live specs are complete and point at real parts,
-- Config.Skins owns the ids, the localization is complete and unique, and (client path) the hit themes and living
-- state machines register into a PickFX ctx and run a full draw / strike / inspect / run timeline without an error.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

-- Lune has no physics / derived world-space properties (Position, AssemblyLinearVelocity, WorldPosition) and no
-- ParticleEmitter:Emit: the live timeline runs on proxies of the built model that answer them like Roblox.
pcall(function()
	roblox.implementMethod("ParticleEmitter", "Emit", function() end)
end)
local proxies = setmetatable({}, { __mode = "k" })
local proxy
local function wrap(v)
	if typeof(v) == "Instance" then
		return proxy(v)
	end
	return v
end
proxy = function(inst)
	if proxies[inst] then
		return proxies[inst]
	end
	local px = setmetatable({}, {
		__index = function(_, k)
			if k == "Position" and inst:IsA("BasePart") then return inst.CFrame.Position end
			if k == "AssemblyLinearVelocity" and inst:IsA("BasePart") then return Vector3.new(6, 0, 3) end
			if k == "WorldPosition" and inst:IsA("Attachment") then
				local p = inst.Parent
				return p and (p.CFrame * inst.CFrame).Position or inst.CFrame.Position
			end
			local v = inst[k]
			if type(v) == "function" then
				return function(_, ...)
					local res = table.pack(v(inst, ...))
					for i = 1, res.n do
						if typeof(res[i]) == "Instance" then
							res[i] = proxy(res[i])
						elseif type(res[i]) == "table" then
							local out = {}
							for j, x in ipairs(res[i]) do out[j] = wrap(x) end
							res[i] = out
						end
					end
					return table.unpack(res, 1, res.n)
				end
			end
			return wrap(v)
		end,
		__newindex = function(_, k, v) inst[k] = v end,
	})
	proxies[inst] = px
	return px
end
local tweens = { Create = function() return { Play = function() end } end }
L.Stubs.TweenService = tweens
L.Stubs.Debris = { AddItem = function() end }
L.Workspace = setmetatable({ CurrentCamera = { CFrame = CFrame.new(0, 4, 12) }, GetServerTimeNow = function() return L.Time end,
	FindFirstChild = function() return nil end }, { __index = function() return nil end })

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local Skins = L.Require("ReplicatedStorage.Halloween.PickaxeSkins")
local S2 = L.Require("ReplicatedStorage.Halloween.PickaxeSkins2")
-- the hit FX build tweens (TweenService.Create is stubbed): TweenInfo into the environments of the src modules that
-- create them (economy_env gives every module its own environment table over a read-only global table)
local TweenInfoStub = { new = function(...) return { ... } end }
local function giveTweenInfo(fn)
	local ok, env = pcall(getfenv, fn)
	if ok and type(env) == "table" then
		rawset(env, "TweenInfo", TweenInfoStub)
	end
end
local Config = L.Require("ReplicatedStorage.Halloween.Config")
local UY = { "UY_ToothyAlarm", "UY_FateHand", "UY_Laughsaw", "UY_TVHead", "UY_NastyOctopus", "UY_GummyHorror", "UY_BellReaper" }
local CH1 = { "GraveShovel", "BonePickaxe", "PumpkinSmasher", "GhostScythe", "LivingCoffin", "SoulReaper" }
local STATS = { "Damage", "Window", "Circles", "CritChance", "CritMult", "PerfectMult", "ComboStep", "ComboMax", "Luck", "CoinBonus",
	"Strength", "Price", "FX", "Level", "MaxStrength" }

test("PickaxeSkins registers the seven Chapter II skins after Chapter I, once", function()
	eq(#Skins.List, 13, "skins")
	for i, id in ipairs(CH1) do
		eq(Skins.Order[i], id, "chapter I order")
	end
	for i, id in ipairs(UY) do
		eq(Skins.Order[6 + i], id, "chapter II order")
		truthy(Skins.ById[id] == S2.ById[id], "ById " .. id)
		eq(Skins.ById[id].Chapter, 2, id .. " chapter")
	end
	truthy(S2.Register(Skins) == true, "re-register returns true")
	eq(#Skins.List, 13, "no duplicates after a second Register")
	eq(#Skins.Order, 13, "no duplicate order entries")
	truthy(S2.Register(nil) == false and S2.Register({}) == false, "bad Skins tables refused")
end)

test("the skins carry only presentation keys (no stat keys)", function()
	for _, s in ipairs(S2.List) do
		for _, k in ipairs(STATS) do
			truthy(s[k] == nil, s.Id .. " carries stat key " .. k)
		end
		for _, k in ipairs({ "Id", "Name", "RU", "Icon", "Rarity", "Theme", "ThemeAlt", "Swing", "Sound", "Visual", "Trait", "TraitRU", "Lore", "LoreRU" }) do
			truthy(s[k] ~= nil, s.Id .. " missing " .. k)
		end
		truthy(s.Inspect == true, s.Id .. " has an inspect")
		truthy(type(s.Visual.Kind) == "string" and string.sub(s.Visual.Kind, 1, 3) == "HW_", s.Id .. " kind prefix")
	end
end)

test("Resolve overlays only the VISUAL keys; stats always come from the real tier", function()
	local Mining = L.Require("ReplicatedStorage.DogEconomy.MiningConfig")
	local tiers = Mining.Pickaxes
	truthy(type(tiers) == "table" and #tiers >= 2, "mining tiers")
	local visual = {}
	for _, k in ipairs(Skins.VISUAL) do visual[k] = true end
	for _, def in ipairs({ tiers[1], tiers[#tiers] }) do
		for _, id in ipairs(UY) do
			local s = Skins.ById[id]
			local out = Skins.Resolve(def, id)
			truthy(out ~= def, "a resolved clone")
			eq(out.SkinId, id, "SkinId")
			eq(out.BaseId, def.Id, "BaseId")
			for k, v in pairs(def) do
				if not visual[k] then
					truthy(out[k] == v, id .. " changed non-visual key " .. tostring(k))
				end
			end
			for k in pairs(visual) do
				if s[k] ~= nil and k ~= "Theme" then
					truthy(out[k] == s[k], id .. " did not overlay " .. k)
				end
			end
			truthy(out.Theme == s.Theme or out.Theme == s.ThemeAlt, id .. " theme")
			truthy(Skins.Resolve(def, id) == out, "cached")
		end
		truthy(Skins.Resolve(def, "NoSuchSkin") == def, "unknown skin = the real def")
	end
end)

test("Skins.Of ignores the event switch (owned skins stay visible when the event is off)", function()
	local src = fs.readFile("src/ReplicatedStorage/Halloween/PickaxeSkins.luau")
	truthy(not string.find(src, "Shared.Enabled", 1, true), "Skins.Of must not read Shared.Enabled")
	local p = roblox.Instance.new("Player")
	p:SetAttribute("PickaxeSkin", "UY_BellReaper")
	eq(Skins.Of(p), "UY_BellReaper", "Of")
	p:SetAttribute("PickaxeSkin", "GraveShovel")
	eq(Skins.Of(p), "GraveShovel", "Of chapter I")
	p:SetAttribute("PickaxeSkin", "Nope")
	eq(Skins.Of(p), nil, "unknown id")
	eq(Skins.Of({}), nil, "not a player")
	local src2 = fs.readFile("src/ReplicatedStorage/Halloween/PickaxeSkins.luau")
	local n = select(2, string.gsub(src2, "%[WP%-K2%]", ""))
	eq(n, 1, "exactly one marked registration line in PickaxeSkins")
end)

-- every design builds a model that follows the PickaxeSkins model contract
local built = {}
test("every design builds a deterministic, contract-conform model", function()
	for _, id in ipairs(UY) do
		local s = Skins.ById[id]
		truthy(S2.Designs[s.Visual.Kind] and Skins.Designs[s.Visual.Kind], id .. " design registered")
		local m = Skins.Build(id)
		truthy(m and m:IsA("Model"), id .. " model")
		local handle = m.PrimaryPart
		truthy(handle and handle.Name == "Handle", id .. " handle")
		eq(m:GetAttribute("Kind"), s.Visual.Kind, id .. " kind")
		eq(m:GetAttribute("Theme"), s.Theme, id .. " theme")
		eq(m:GetAttribute("SkinId"), id, id .. " skin id")
		truthy(handle:FindFirstChild("TrailA") and handle:FindFirstChild("TrailB"), id .. " trail points")
		local parts, lights, emitters, animated = 0, 0, 0, 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				truthy(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, id .. " " .. d.Name .. " physics flags")
				truthy(d.Massless, id .. " massless")
				if d ~= handle and d:GetAttribute("PickAnim") then
					animated += 1
					truthy(typeof(d:GetAttribute("PickBase")) == "CFrame", id .. " " .. d.Name .. " PickBase")
				end
				local sz = d.Size
				truthy(d == handle or (sz.X > 0 and sz.Y > 0 and sz.Z > 0 and sz.X < 7 and sz.Y < 7 and sz.Z < 7), id .. " " .. d.Name .. " size " .. tostring(sz))
			elseif d:IsA("Light") then
				lights += 1
				truthy(d.Shadows == false, id .. " light shadows off")
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			end
		end
		truthy(parts >= 200 and parts <= 650, id .. " part count " .. parts)
		truthy(animated >= 15, id .. " animated parts " .. animated)
		truthy(lights >= 1 and lights <= 2, id .. " lights " .. lights)
		eq(emitters, 1, id .. " emitters")
		-- deterministic: the server's held model equals every client's
		local m2 = Skins.Build(id)
		local a, b = m:GetDescendants(), m2:GetDescendants()
		eq(#a, #b, id .. " rebuild size")
		for i = 1, #a do
			if a[i]:IsA("BasePart") then
				truthy((a[i].CFrame.Position - b[i].CFrame.Position).Magnitude < 1e-6 and a[i].Color == b[i].Color, id .. " deterministic " .. a[i].Name)
			end
		end
		built[id] = m
	end
end)

local SOURCES = { "TICK", "PING", "KNOCK", "LAND", "WIND", "WATER", "SPLAT", "CLICK", "SLASH", "LUNGE", "SHEATH", "HOP" }
local fakeAudio = { Sources = SOURCES, Kits = {}, KitAssetIds = {} }
local EFFECTS = { EqualizerSoundEffect = true, DistortionSoundEffect = true, ReverbSoundEffect = true, ChorusSoundEffect = true,
	FlangeSoundEffect = true, TremoloSoundEffect = true }
test("sound kits: complete, valid rows, exactly one soft impact per hit, never a THUMP", function()
	local kits = S2.Kits(fakeAudio)
	local known = {}
	for _, src in ipairs(SOURCES) do known[src] = true end
	local function impact(row) return row[1] == "KNOCK" or row[1] == "LAND" end
	for _, s in ipairs(S2.List) do
		local kit = kits[s.Sound]
		truthy(kit, s.Id .. " kit " .. s.Sound)
		for _, cue in ipairs({ "Swing", "Hit", "Perfect", "Crit", "Draw", "Break", "Inspect", "Idle" }) do
			truthy(type(kit[cue]) == "table" and #kit[cue] > 0, s.Sound .. " cue " .. cue)
		end
		for cue, rows in pairs(kit) do
			local impacts = 0
			for i, row in ipairs(rows) do
				local tag = s.Sound .. "." .. cue .. "[" .. i .. "]"
				truthy(known[row[1]], tag .. " built-in sample")
				truthy(type(row[2]) == "number" and row[2] > 0 and row[2] <= .5, tag .. " volume " .. tostring(row[2]))
				truthy(type(row[3]) == "number" and row[3] > 0 and row[3] <= 8, tag .. " speed")
				local fx = row[4]
				if fx ~= nil then
					truthy(type(fx) == "table", tag .. " fx table")
					for cls in pairs(fx) do truthy(EFFECTS[cls], tag .. " effect " .. tostring(cls)) end
					local eqz, dist = fx.EqualizerSoundEffect, fx.DistortionSoundEffect
					truthy(not (dist and eqz and (eqz.LowGain or 0) >= 8), tag .. " THUMP-style distorted low boost")
				end
				if cue == "Idle" or cue == "Run" then
					truthy(row.loop == true and row[2] <= .05, tag .. " quiet loop")
				end
				if impact(row) then
					impacts += 1
					truthy(row[2] <= .3, tag .. " impact volume")
					truthy(not (fx and fx.DistortionSoundEffect), tag .. " impact without distortion")
					truthy(not (fx and fx.EqualizerSoundEffect and (fx.EqualizerSoundEffect.LowGain or 0) > 4), tag .. " soft impact EQ")
				end
			end
			if cue == "Hit" then
				eq(impacts, 1, s.Sound .. ".Hit soft impacts")
				truthy(impact(rows[2]) and (rows[2].at or 0) <= .02, s.Sound .. ".Hit impact is the second row, on the beat")
			elseif cue == "Perfect" then
				eq(impacts, 0, s.Sound .. ".Perfect (plays on top of Hit)")
			else
				truthy(impacts <= 1, s.Sound .. "." .. cue .. " impacts " .. impacts)
			end
		end
	end
end)

test("palettes, crit stamps, live specs and designs are complete and point at real parts", function()
	for _, s in ipairs(S2.List) do
		local pal = S2.Palettes[s.Theme]
		truthy(pal and #pal >= 4, s.Id .. " palette")
		truthy(Skins.Palettes[s.Theme] == pal, s.Id .. " palette registered")
		for _, c in ipairs(pal) do truthy(typeof(c) == "Color3", s.Id .. " palette colour") end
		local crit = S2.CritText[s.Theme]
		truthy(crit and #crit[1] > 0 and #crit[2] > 0 and crit[1] ~= crit[2], s.Id .. " crit EN/RU")
		eq(Skins.CritText(s.Theme), crit[1], s.Id .. " CritText through PickaxeSkins")
		local spec = S2.LiveSpecs[s.Visual.Kind]
		truthy(spec, s.Id .. " live spec")
		eq(spec.Theme, s.Theme, s.Id .. " live spec theme")
		local m = built[s.Id]
		if m then
			local names, animNames = {}, {}
			for _, d in ipairs(m:GetDescendants()) do
				names[d.Name] = true
				if d:IsA("BasePart") and d:GetAttribute("PickAnim") then
					animNames[d.Name] = true
					for k in string.gmatch(d:GetAttribute("PickAnim"), "[^,]+") do animNames["@" .. k] = true end
				end
			end
			truthy(names[spec.Focus], s.Id .. " focus part " .. tostring(spec.Focus))
			for n in pairs(spec.Glow or {}) do truthy(names[n], s.Id .. " glow part " .. n) end
			for n in pairs(spec.Tint or {}) do truthy(names[n], s.Id .. " tint part " .. n) end
			for n in pairs(spec.Flames or {}) do truthy(names[n], s.Id .. " flame light " .. n) end
			for n in pairs(spec.Moves or {}) do truthy(animNames[n], s.Id .. " moved part is animated: " .. n) end
			for n in pairs(spec.MovesByAnim or {}) do truthy(animNames["@" .. n], s.Id .. " anim group " .. n) end
			if spec.Mood then truthy(type(spec.MoodEvery) == "number", s.Id .. " MoodEvery") end
			if spec.Idle then truthy(type(spec.IdleEvery) == "number", s.Id .. " IdleEvery") end
		end
	end
end)

test("Config.Skins owns the Chapter II ids (order, names, rarity, chapter)", function()
	local cs = Config.Skins
	eq(#cs.Order, #Skins.Order, "config order length")
	for i, id in ipairs(Skins.Order) do
		eq(cs.Order[i], id, "config order " .. i)
		local s = Skins.ById[id]
		eq(cs.Names[id], s.Name, id .. " name")
		eq(cs.Rarity[id], s.Rarity, id .. " rarity")
	end
	for _, id in ipairs(UY) do
		eq(cs.Chapter[id], 2, id .. " chapter")
		truthy(string.sub(id, 1, 3) == "UY_", id .. " id prefix")
	end
	for _, id in ipairs(CH1) do
		truthy(cs.Chapter[id] == nil, id .. " stays chapter I")
	end
	local rar = { Epic = 0, Legendary = 0, Mythic = 0, Secret = 0 }
	for _, id in ipairs(UY) do rar[cs.Rarity[id]] += 1 end
	eq(rar.Epic, 1, "epic") eq(rar.Legendary, 2, "legendary") eq(rar.Mythic, 3, "mythic") eq(rar.Secret, 1, "secret")
	local hs = fs.readFile("src/StarterGui/ScreenGui/Modules/HalloweenScreen.luau")
	truthy(string.find(hs, "Config.Skins.Chapter[sid] == 2", 1, true), "the Halloween window's cosmetics tab lists Chapter I skins only")
end)

test("localization: every name, label, trait and lore line, unique keys", function()
	local Dict = L.Require("ReplicatedStorage.Localization.PickaxeSkins2")
	for _, s in ipairs(S2.List) do
		truthy(Dict.Exact[s.Name], s.Id .. " name " .. s.Name)
		truthy(Dict.Exact[string.upper(s.Name)], s.Id .. " upper name")
		truthy(Dict.Exact[string.upper(s.Name) .. " SKIN"], s.Id .. " skin label")
		eq(Dict.Exact[s.Trait], s.TraitRU, s.Id .. " trait")
		eq(Dict.Exact[s.Lore], s.LoreRU, s.Id .. " lore")
		local hit = false
		for _, rule in ipairs(Dict.Patterns) do
			if string.match(s.Name .. " equipped", rule[1]) then hit = true end
		end
		truthy(hit, s.Id .. " equipped reply")
	end
	-- no key repeats another dictionary (the base AutoTranslate table or another Localization module)
	local base = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for key in string.gmatch(base, '%["(.-)"%]%s*=') do
		truthy(Dict.Exact[key] == nil, "repeats a base entry: " .. key)
	end
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		if name ~= "PickaxeSkins2.luau" then
			local other = L.Require("ReplicatedStorage.Localization." .. string.gsub(name, "%.luau$", ""))
			for _, tbl in ipairs({ type(other) == "table" and other.Exact or {}, type(other) == "table" and other.UI or {} }) do
				for key in pairs(tbl) do
					truthy(Dict.Exact[key] == nil, "repeats " .. name .. ": " .. key)
				end
			end
		end
	end
end)

test("server Register: the sound kits reach MiningAudio.Kits next to Chapter I's", function()
	L.Overrides["ReplicatedStorage/Mining/MiningAudio"] = fakeAudio
	Skins.Register()
	for _, s in ipairs(S2.List) do
		truthy(fakeAudio.Kits[s.Sound], "kit " .. s.Sound)
		truthy(fakeAudio.KitAssetIds[s.Sound] and fakeAudio.KitAssetIds[s.Sound].Hit == 0, "upload slots " .. s.Sound)
	end
	truthy(fakeAudio.Kits.HW_Grave, "chapter I kits still registered")
end)

test("client Register: hit themes + living state machines register and run a full timeline", function()
	-- a fresh client-side copy of the modules
	L.Reset()
	L.Stubs.RunService.IsClient = function() return true end
	L.Stubs.RunService.IsServer = function() return false end
	local SkinsC = L.Require("ReplicatedStorage.Halloween.PickaxeSkins")
	local folder = roblox.Instance.new("Folder")
	local glyphs, bitsN = 0, 0
	local ctx = {
		FX = { Folder = folder, Low = function() return false end, ReducedMotion = function() return false end, Burst = function() end, Ring = function() end },
		PickFX = { Themes = {}, HitFX = {}, LiveFX = {}, Glyph = function() glyphs += 1 end, Bits = function() bitsN += 1 end, Track = function() return {} end, Untrack = function() end },
	}
	giveTweenInfo(SkinsC.Build) -- PickaxeSkins (the liveFX primitives)
	giveTweenInfo(SkinsC.Register) -- PickaxeSkins2 (its wrapper of Register, the hit themes)
	SkinsC.Register(ctx)
	L.Stubs.RunService.IsClient = function() return false end
	L.Stubs.RunService.IsServer = function() return true end
	for _, s in ipairs(S2.List) do
		truthy(ctx.PickFX.Themes[s.Theme], s.Id .. " theme palette")
		truthy(type(ctx.PickFX.HitFX[s.Theme]) == "function", s.Id .. " hit theme")
		truthy(type(ctx.PickFX.LiveFX[s.Visual.Kind]) == "function", s.Id .. " live state machine")
		-- every hit variant: plain / perfect / crit, local / remote
		for _, v in ipairs({ { 1, false, false }, { 2, false, false }, { 2, true, false }, { 1, true, true }, { 2, false, true } }) do
			ctx.PickFX.HitFX[s.Theme](Vector3.new(0, 2, 0), Vector3.new(0, 1, 0), v[1], v[2], v[3])
		end
		-- the resolved theme switched from ThemeAlt to the Halloween theme
		local Mining = L.Require("ReplicatedStorage.DogEconomy.MiningConfig")
		eq(SkinsC.Resolve(Mining.Pickaxes[1], s.Id).Theme, s.Theme, s.Id .. " resolved theme after registration")
		-- a held model's life: in the hand (draw), idle, a mood, a strike, running, the inspect and its finale
		local m = proxy(SkinsC.Build(s.Id))
		m:SetAttribute("Mount", "Hand")
		local root = m.PrimaryPart
		local e = { Model = m, Root = root, Anchored = false, Parts = {}, Pulse = {}, Hit = 0, State = { Run = 0, Insp = 0, Spin = 0 }, InspectUntil = 0 }
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("PickAnim") then
				local joint = d:GetAttribute("PickJoint")
				table.insert(e.Parts, { Part = d, Phase = d:GetAttribute("PickPhase") or 0, Joint = typeof(joint) == "Vector3" and CFrame.new(joint) or CFrame.identity,
					Base = d:GetAttribute("PickBase") or CFrame.identity })
			end
			if d:IsA("BasePart") and d:GetAttribute("PickPulse") then table.insert(e.Pulse, { Part = d, Base = d.Transparency }) end
		end
		local live = ctx.PickFX.LiveFX[s.Visual.Kind]
		local glyphsBefore = glyphs
		local t = 0
		while t < 14 do
			if math.abs(t - 3) < .05 then e.Hit = 1 end
			if math.abs(t - 5) < .05 then e.InspectUntil = t + 2.6 end
			e.State.Insp = t < e.InspectUntil and 1 or 0
			e.State.Run = (t > 9 and t < 11) and 1 or 0
			live(e, t, .05, e.Hit * e.Hit, false)
			e.Hit = math.max(0, e.Hit - .05 * 2.2)
			t += .05
		end
		truthy(glyphs > glyphsBefore, s.Id .. " the inspect ran to its finale (world effects reached)")
		truthy(e.HwLive and e.HwLive.Hand == true, s.Id .. " the draw was seen")
		-- an anchored preview (UI) and reduced motion never error either
		e.Anchored = true
		for k = 1, 10 do live(e, 20 + k * .1, .1, 0, k % 2 == 0) end
	end
	truthy(glyphs > 0 and bitsN > 0, "the effects reached PickFX")
	L.Reset()
end)

print(string.format("pickaxe_skins2: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("pickaxe_skins2 tests failed")
end
