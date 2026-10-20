--!nolint
-- ReplicatedStorage.AudioMixer (docs/halloween2/DESIGN.md §16.1): lune run tests/audio_mixer.luau
-- The pure duck math, the runtime duck / release on fake groups (quietest reason wins, release restores the baseline),
-- and the bus layout builder that tools/edits/05_audio.luau runs offline (idempotent, keeps volumes, no makeup on Pickaxe).
local L = require("./lib/economy_env")
local roblox = require("@lune/roblox")
local Mixer = L.Require("ReplicatedStorage.AudioMixer")
local M = Mixer.Math
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
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-6)
end

test("Resolve: preset names, numbers, tables (unknown groups dropped, values clamped)", function()
	local c = M.Resolve("Cinematic")
	assert(near(c.Music, .15) and near(c.Ambience, .35) and near(c.Pickaxe, .25) and near(c.Boss, .4), "cinematic preset")
	assert(near(c.SFX, .5) and near(c.UI, .8) and near(c.WorldEvents, .15), "cinematic preset (rest)")
	assert(c.Cinema == nil, "the Cinema bus is never in a preset")
	local n = M.Resolve(.3)
	for _, name in ipairs(Mixer.Order) do
		if name == "Cinema" then
			assert(n[name] == nil, "a number never ducks the Cinema bus")
		else
			assert(near(n[name], .3), "number applies to " .. name)
		end
	end
	local t = M.Resolve({ Music = 1.7, Ambience = -1, Nope = .2, UI = "x" })
	assert(t.Music == 1 and t.Ambience == 0 and t.Nope == nil and t.UI == nil, "clamped / filtered")
	assert(next(M.Resolve("NoSuchPreset")) == nil and next(M.Resolve(nil)) == nil, "unknown spec = no duck")
	assert(M.Resolve({ Music = 0 / 0 }).Music == nil, "NaN levels are ignored")
end)

test("Level: the quietest active reason wins per group; untouched groups stay at 1", function()
	local reasons = { A = { Music = .5, UI = .9 }, B = { Music = .2 }, C = { Ambience = .7 } }
	assert(near(M.Level(reasons, "Music"), .2), "quietest wins")
	assert(near(M.Level(reasons, "UI"), .9), "single reason")
	assert(near(M.Level(reasons, "Ambience"), .7), "other group")
	assert(M.Level(reasons, "Boss") == 1, "untouched")
	assert(M.Level({}, "Music") == 1, "no reasons")
	local targets = M.Targets({ Music = .7, UI = 1, Boss = 1 }, reasons)
	assert(near(targets.Music, .14) and near(targets.UI, .9) and targets.Boss == 1, "targets = base * level")
	assert(M.Target(-1, .5) == 0 and near(M.Target(.8, 2), .8), "target clamps")
end)

-- runtime on fake groups ----------------------------------------------------------------------------------------------
local clock = 0
local fakes = {}
local function setup(volumes)
	Mixer._Reset()
	table.clear(fakes)
	for name, v in pairs(volumes) do
		fakes[name] = { Volume = v, Name = name }
	end
	Mixer.Hooks.Client = function()
		return true
	end
	Mixer.Hooks.Instances = function(name)
		return fakes[name] and { fakes[name] } or {}
	end
	Mixer.Hooks.Tween = function(g, volume)
		g.Volume = volume
	end
	Mixer.Hooks.Now = function()
		return clock
	end
end
local BASE = { Music = .7, WorldEvents = .7, Ambience = .8, UI = 1, Pickaxe = 1, Boss = 1, SFX = 1, Cinema = 1 }

test("Duck lowers to base * level, release restores the exact baseline", function()
	setup(BASE)
	Mixer.Duck("Secret1", { Music = .5, Ambience = .5 }, .5)
	assert(near(fakes.Music.Volume, .35) and near(fakes.Ambience.Volume, .4), "ducked")
	assert(fakes.UI.Volume == 1 and fakes.Pickaxe.Volume == 1, "other buses untouched")
	Mixer.Release("Secret1", 1)
	assert(near(fakes.Music.Volume, .7) and near(fakes.Ambience.Volume, .8), "restored")
	assert(not Mixer.Ducking("Secret1"), "reason gone")
end)

test("quietest reason wins; releasing the quietest returns to the next one, then to the baseline", function()
	setup(BASE)
	Mixer.Duck("A", { Music = .5 }, 0)
	Mixer.Duck("B", { Music = .2, Boss = .4 }, 0)
	assert(near(fakes.Music.Volume, .14), "B is quieter")
	Mixer.Duck("C", { Music = .9 }, 0)
	assert(near(fakes.Music.Volume, .14), "a louder reason never raises the level")
	Mixer.Release("B", 0)
	assert(near(fakes.Music.Volume, .35) and fakes.Boss.Volume == 1, "back to A, Boss restored")
	Mixer.Release("A", 0)
	assert(near(fakes.Music.Volume, .63), "C still ducks")
	Mixer.Release("C", 0)
	assert(near(fakes.Music.Volume, .7), "baseline")
	assert(Mixer.Level("Music") == 1, "level 1 after every release")
end)

test("presets: Cinematic per §16.1; the Cinema bus stays at its level", function()
	setup(BASE)
	Mixer.Duck("Cinema:church", "Cinematic", .8)
	assert(near(fakes.Music.Volume, .7 * .15) and near(fakes.Pickaxe.Volume, .25) and near(fakes.Boss.Volume, .4), "cinematic")
	assert(fakes.Cinema.Volume == 1, "cinema bus untouched")
	Mixer.Duck("Reveal", "Silence", 1.2)
	for _, name in ipairs({ "Music", "Ambience", "Pickaxe", "Boss", "SFX", "UI", "WorldEvents" }) do
		assert(fakes[name].Volume == 0, name .. " silenced")
	end
	assert(fakes.Cinema.Volume == 1, "the reveal's own sounds stay audible")
	Mixer.Release("Reveal")
	assert(near(fakes.Music.Volume, .7 * .15), "cinematic still holds")
	Mixer.Release("Cinema:church")
	for name, v in pairs(BASE) do
		assert(near(fakes[name].Volume, v), name .. " restored")
	end
end)

test("the same reason ducking again replaces its levels (never stacks); unknown releases are no-ops", function()
	setup(BASE)
	Mixer.Duck("X", { Music = .5 }, 0)
	Mixer.Duck("X", { Music = .8 }, 0)
	assert(near(fakes.Music.Volume, .56), "replaced, not min-stacked with itself")
	Mixer.Release("Nope", 0)
	assert(near(fakes.Music.Volume, .56), "unknown release changes nothing")
	Mixer.Release("X", 0)
	Mixer.Release("X", 0)
	assert(near(fakes.Music.Volume, .7), "double release safe")
end)

test("the baseline is the group's own level, never a value captured mid-duck; SetBase moves it deliberately", function()
	setup(BASE)
	Mixer.Duck("A", { UI = .5 }, 0)
	assert(near(fakes.UI.Volume, .5), "ducked")
	-- a second duck while the first holds the group down must not mistake .5 for the baseline
	Mixer.Duck("B", { UI = .8 }, 0)
	Mixer.Release("A", 0)
	assert(near(fakes.UI.Volume, .8), "B over the real baseline")
	Mixer.SetBase("UI", .6)
	assert(near(fakes.UI.Volume, .48), "new base applies under the active duck")
	Mixer.Release("B", 0)
	assert(near(fakes.UI.Volume, .6), "released to the new base")
	assert(near(Mixer.Base("UI"), .6), "Base reports it")
end)

test("server / non-client: every call is a safe no-op", function()
	setup(BASE)
	Mixer.Hooks.Client = function()
		return false
	end
	Mixer.Duck("A", "Silence", 0)
	Mixer.SetBase("Music", .1)
	assert(fakes.Music.Volume == .7 and not Mixer.Ducking("A"), "nothing moved")
	Mixer.Release("A")
end)

test("Mark / Since: the 'just played' board", function()
	setup(BASE)
	assert(Mixer.Since("PickaxeImpact") == math.huge, "never marked")
	clock = 10
	Mixer.Mark("PickaxeImpact")
	clock = 10.12
	assert(near(Mixer.Since("PickaxeImpact"), .12), "elapsed")
end)

test("Stats lists reasons and per-bus levels", function()
	setup(BASE)
	Mixer.Duck("Z", { Boss = .3 }, 0)
	local s = Mixer.Stats()
	assert(s.Reasons[1] == "Z" and near(s.Levels.Boss, .3) and s.Levels.Music == 1, "stats")
end)

-- the bus layout builder ----------------------------------------------------------------------------------------------
local function tree(ss)
	local out = {}
	for _, d in ss:GetDescendants() do
		local line = d:GetFullName()
		if d:IsA("SoundGroup") then
			line ..= string.format(" %.3f", d.Volume)
		elseif d.ClassName == "CompressorSoundEffect" then
			line ..= string.format(" %g/%g/%g", d.Threshold, d.Ratio, d.GainMakeup)
		end
		table.insert(out, line)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

test("Ensure builds §16.1 exactly, keeps existing volumes, moves the stray mining group, is idempotent", function()
	local ss = roblox.Instance.new("Folder")
	ss.Name = "SoundService"
	local audio = roblox.Instance.new("Folder")
	audio.Name = "DOGROTS_AUDIO"
	audio.Parent = ss
	local music = roblox.Instance.new("SoundGroup")
	music.Name = "Music"
	music.Volume = .6 -- the designer's level: kept
	music.Parent = audio
	local stray = roblox.Instance.new("SoundGroup")
	stray.Name = "DOGROTS_MiningSFX"
	stray.Parent = ss
	local oldComp = roblox.Instance.new("CompressorSoundEffect")
	oldComp.GainMakeup = 2
	oldComp.Parent = stray
	local extra = roblox.Instance.new("CompressorSoundEffect")
	extra.Parent = stray
	local report = Mixer.Ensure(ss, { KeepVolume = true })
	assert(report.Moved == 1, "stray mining group moved")
	local sfx = ss:FindFirstChild("DOGROTS_SFX")
	assert(sfx, "DOGROTS_SFX folder")
	for _, name in ipairs({ "Pickaxe", "Boss", "SFX", "Cinema" }) do
		local g = sfx:FindFirstChild(name)
		assert(g and g:IsA("SoundGroup") and near(g.Volume, 1, 1e-4), name .. " bus")
	end
	for name, v in pairs({ Music = .6, WorldEvents = .7, Ambience = .8, UI = 1 }) do
		local g = audio:FindFirstChild(name)
		assert(g and g:IsA("SoundGroup") and near(g.Volume, v, 1e-4), name .. " level " .. tostring(g and g.Volume))
	end
	assert(audio.Music:FindFirstChild("Halloween"), "the OST group sits under Music")
	local mining = sfx.Pickaxe:FindFirstChild("DOGROTS_MiningSFX")
	assert(mining == stray, "the same instance, re-parented")
	local comps = 0
	for _, c in mining:GetChildren() do
		if c.ClassName == "CompressorSoundEffect" then
			comps += 1
			assert(c.GainMakeup == 0, "mining compressor makeup forced to 0")
		end
	end
	assert(comps == 1, "duplicate compressors collapsed to one")
	for _, d in sfx.Pickaxe:GetDescendants() do
		if d.ClassName == "CompressorSoundEffect" then
			assert(d.GainMakeup <= 0, "no positive makeup gain anywhere on the pickaxe bus")
		end
	end
	local before = tree(ss)
	local again = Mixer.Ensure(ss, { KeepVolume = true })
	assert(again.Created == 0 and again.Moved == 0, "second run creates nothing")
	assert(tree(ss) == before, "second run changes nothing")
end)

print(string.format("audio_mixer: %d passed, %d failed", passed, failed))
