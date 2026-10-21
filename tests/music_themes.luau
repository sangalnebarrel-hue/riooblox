--!nolint
-- The procedural Halloween OST themes (ReplicatedStorage.Halloween.Music), incl. the Chapter II themes of
-- docs/halloween2/DESIGN.md §16.4 and the beat clock: lune run tests/music_themes.luau
local L = require("./lib/economy_env")
local Music = L.Require("ReplicatedStorage.Halloween.Music")
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

local NEW = { UNDERYARD = 66, TRIAL = 108, COFFIN = 80, FINALE_BELL = 92, FINALE_CHOIR = 70, FINALE_HOUND = 100, REVEAL = 50 }

test("every Chapter II theme exists, has its tempo and is registered for SetTheme", function()
	for name, bpm in pairs(NEW) do
		local t = Music.Themes[name]
		assert(t, "missing theme " .. name)
		assert(t.Bpm == bpm, name .. " bpm " .. tostring(t.Bpm))
		assert(Music.Players[name] and Music.Players[name].Theme == t, name .. " not registered in Music.Players")
	end
	assert(Music.Themes.TRIAL.Bpm == 108 and Music.Themes.FINALE_HOUND.Bpm == 100 and Music.Themes.UNDERYARD.Bpm == 66, "§16.4 tempos")
end)

test("theme data is well formed (instruments, loops, sorted notes inside the loop, playable pitches)", function()
	for name, t in pairs(Music.Themes) do
		assert(type(t.Beats) == "number" and t.Beats > 0, name .. " beats")
		for pi, part in ipairs(t.Parts) do
			local def = Music.Instruments[part.Inst]
			assert(def, name .. " part " .. pi .. " unknown instrument " .. tostring(part.Inst))
			assert(#part.Notes > 0, name .. " part " .. pi .. " is empty")
			local last = -1
			for ni, n in ipairs(part.Notes) do
				assert(n[1] >= last, string.format("%s part %d note %d out of order", name, pi, ni))
				last = n[1]
				assert(n[1] >= 0 and n[1] < t.Beats, string.format("%s part %d note %d at beat %s outside the loop", name, pi, ni, tostring(n[1])))
				assert(n[4] > 0 and n[4] <= 1, name .. " velocity")
				if def.Melodic then
					local speed = def.Speed * 2 ^ (n[2] / 12) * Music.ROOT
					assert(speed >= .1 and speed <= 6, string.format("%s part %d note %d speed %.3f", name, pi, ni, speed))
				end
			end
		end
		for _, loopName in ipairs(t.Loops or {}) do
			assert(Music.Loops[loopName], name .. " unknown loop " .. loopName)
		end
	end
end)

test("the Underyard waltz is in 3/4 D minor: the pizzicato plays oom-pah-pah on every bar", function()
	local t = Music.Themes.UNDERYARD
	assert(t.Beats == 48, "16 bars of 3/4")
	local pizz
	for _, part in ipairs(t.Parts) do
		if part.Inst == "Pizz" then
			pizz = part
		end
	end
	assert(pizz, "pizzicato part")
	local perBar = {}
	for _, n in ipairs(pizz.Notes) do
		local bar = math.floor(n[1] / 3)
		perBar[bar] = (perBar[bar] or 0) + 1
	end
	for bar = 0, 15 do
		assert(perBar[bar] == 5, "bar " .. bar .. " has " .. tostring(perBar[bar]) .. " plucks")
	end
	-- the low choir drone is D
	local d = Music.Loops.ChoirD.Speed
	assert(math.abs(d - .5 * 2 ^ (5 / 12)) < 1e-9, "choir drone on D")
	for _, part in ipairs(t.Parts) do
		if part.Inst == "Box" then
			-- every melody note belongs to D harmonic minor (D E F G A Bb C C#): semitones mod 12 relative to A
			local ok = { [5] = true, [7] = true, [8] = true, [10] = true, [0] = true, [1] = true, [3] = true, [4] = true }
			for _, n in ipairs(part.Notes) do
				assert(ok[n[2] % 12], "melody note outside D minor: " .. n[2])
			end
		end
	end
end)

test("the sequencer plays every note of a looping theme once per loop and a NoLoop sting once", function()
	local function run(name, seconds)
		local player = Music.Player.new(name, Music.Themes[name])
		player.Target, player.Gain, player.Fade = 1, 1, .1
		local count = 0
		local t = 100
		while t < 100 + seconds do
			player:Step(t, 1 / 60, function()
				count += 1
			end)
			t += 1 / 60
		end
		return count
	end
	local function total(name)
		local n = 0
		for _, part in ipairs(Music.Themes[name].Parts) do
			n += #part.Notes
		end
		return n
	end
	local uy = Music.Themes.UNDERYARD
	local loopSeconds = uy.Beats * 60 / uy.Bpm
	local n = run("UNDERYARD", loopSeconds * 2 - .2)
	assert(n >= total("UNDERYARD") * 2 - 8 and n <= total("UNDERYARD") * 2, "two loops of the waltz, got " .. n)
	local sting = run("COFFIN", 30)
	assert(sting == total("COFFIN"), "the coffin sting plays once, got " .. sting .. " of " .. total("COFFIN"))
end)

test("Music.Beat: the theme's clock when it plays, the server clock otherwise", function()
	local hound = Music.Players.FINALE_HOUND
	local bpm, phase, beat = Music.Beat("FINALE_HOUND")
	assert(bpm == 100 and phase >= 0 and phase < 1, "server-clock fallback")
	assert(math.abs(beat - L.Time / .6) < 1e-6, "server clock beats")
	hound.Gain, hound.Target = 1, 1
	hound.Origin = os.clock() - 3.0 -- 3 s into the theme = 5 beats at 100 BPM
	local _, p2, b2 = Music.Beat("FINALE_HOUND")
	assert(math.abs(b2 - 5) < .05, "theme clock beats " .. b2)
	assert(p2 < .05 or p2 > .95, "on the beat")
	hound.Gain, hound.Target, hound.Origin = 0, 0, nil
	local none = Music.Beat("NO_SUCH_THEME")
	assert(none == 0, "unknown theme")
end)

test("the pad swells in and sustains (attack + looped voice); the kick and celesta exist", function()
	local pad = Music.Instruments.Pad
	assert(pad.Attack and pad.Attack > 0 and pad.Loop == true, "pad attack / loop")
	assert(Music.Instruments.Kick and Music.Instruments.Celesta.Rich == true, "kick / celesta (Rich: dropped on Low)")
end)

print(string.format("music_themes: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("music_themes tests failed")
end
