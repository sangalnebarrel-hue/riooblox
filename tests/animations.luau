--!nolint
-- Kennel dig animations: lune run tests/animations.luau
-- Loads the real ReplicatedStorage.DogAnimationPlayer and DogDigProfiles (from src/) over the
-- place's real clip ModuleScripts, then checks
--   * every dog's dig chain resolves to existing, decodable clips (profile > attribute > names);
--   * the clips the audit flagged are no longer used as work loops;
--   * accents last at most DogDigProfiles.MinCycle (= Config MinCooldown + Duration) at x1.0;
--   * authored hops join, and the measured pose gaps of every transition (core bones);
--   * the kennel driver over several work cycles for every dog: continuous work, accents that
--     end exactly on each find, no frozen one-shots, End -> Idle when production stops,
--     deterministic join phase, and per-frame pose continuity for a set of dogs.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

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
local function check(cond, msg)
	if not cond then
		error(msg or "check failed", 2)
	end
end

-- The built place when check.sh just built it, else the base place (the clips are not rebuilt).
local placePath = if fs.isFile("build/DOGROTS_MINING.rbxl") then "build/DOGROTS_MINING.rbxl" else "place/DOGROTS_base.rbxl"
local game = roblox.deserializePlace(fs.readFile(placePath))
local library = game:GetService("ReplicatedStorage"):FindFirstChild("DogAnimationClips")
local templates = game:GetService("ServerStorage"):FindFirstChild("DogTemplates")
assert(library and templates, "place has no DogAnimationClips / DogTemplates")

-- Economy facts from src (plain data, parsed rather than executed).
local configSource = fs.readFile("src/ReplicatedStorage/DogEconomy/Config.luau")
local work = configSource:match("C%.Work=(%b{})")
local WORK = {}
for key, value in work:gmatch("(%a+)=([%d%.]+)") do
	WORK[key] = tonumber(value)
end
local definitions = {}
for row in fs.readFile("src/ReplicatedStorage/DogEconomy/DogDefinitions.luau"):gmatch("{Index=%d+,[^\n]*") do
	local id, visual = row:match('Id="([^"]+)"'), row:match('VisualAsset="([^"]+)"')
	if id and visual then
		definitions[id] = { Id = id, VisualAsset = visual }
	end
end

-- Clip modules run like Roblox would run them (HttpService:JSONDecode, script.Parent aliases).
local moduleCache = {}
local function runClip(m)
	if moduleCache[m] ~= nil then
		return moduleCache[m]
	end
	local http = { JSONDecode = function(_, s)
		return serde.decode("json", s)
	end }
	local parent = m.Parent
	local env = setmetatable({
		game = { GetService = function(_, name)
			assert(name == "HttpService", "clip asked for " .. tostring(name))
			return http
		end },
		script = { Name = m.Name, Parent = {
			WaitForChild = function(_, n)
				return parent:FindFirstChild(n)
			end,
			FindFirstChild = function(_, n)
				return parent:FindFirstChild(n)
			end,
		} },
		require = function(x)
			return runClip(x)
		end,
		Vector3 = Vector3,
		CFrame = CFrame,
	}, { __index = _G })
	local result = luau.load(m.Source, { debugName = m.Name, environment = env })()
	moduleCache[m] = result
	return result
end

-- DogAnimationPlayer with a controlled clock and stubbed services.
local clock = 1000
local markers = { Gait = {}, Profiles = {}, Economy = {}, Definitions = {} }
markers.Economy.WaitForChild = function()
	return markers.Definitions
end
local replicated = {
	WaitForChild = function(_, name)
		if name == "DogAnimationClips" then
			return library
		elseif name == "DogWalkGait" then
			return markers.Gait
		elseif name == "DogDigProfiles" then
			return markers.Profiles
		elseif name == "DogEconomy" then
			return markers.Economy
		end
		error("unexpected WaitForChild " .. tostring(name))
	end,
	FindFirstChild = function()
		return nil
	end,
}
local Profiles = luau.load(fs.readFile("src/ReplicatedStorage/DogDigProfiles.luau"), { debugName = "DogDigProfiles" })()
local warnings = {}
local env = setmetatable({
	game = { GetService = function(_, name)
		assert(name == "ReplicatedStorage", "player asked for " .. tostring(name))
		return replicated
	end },
	workspace = { GetServerTimeNow = function()
		return clock
	end },
	require = function(x)
		if x == markers.Gait then
			return { new = function()
				return nil
			end }
		elseif x == markers.Profiles then
			return Profiles
		elseif x == markers.Definitions then
			return definitions
		end
		return runClip(x)
	end,
	warn = function(...)
		table.insert(warnings, table.concat({ ... }, " "))
	end,
	Vector3 = Vector3,
	CFrame = CFrame,
}, { __index = _G })
local Player = luau.load(fs.readFile("src/ReplicatedStorage/DogAnimationPlayer.luau"), { debugName = "DogAnimationPlayer", environment = env })()

local dogIds = {}
for _, folder in library:GetChildren() do
	table.insert(dogIds, folder.Name)
end
table.sort(dogIds)

-- Pose gaps on the body bones, in degrees.
local function poseOf(clip, frame)
	local pose = {}
	for name, frames in pairs(clip.Tracks) do
		pose[name] = frames[math.clamp(frame, 1, #frames)]
	end
	return pose
end
local function gap(names, a, b)
	local worst = 0
	for _, name in ipairs(names) do
		local x, y = a[name] or CFrame.identity, b[name] or CFrame.identity
		local _, angle = (x:Inverse() * y):ToAxisAngle()
		angle = math.abs(angle) % (2 * math.pi)
		worst = math.max(worst, if angle > math.pi then 2 * math.pi - angle else angle)
	end
	return math.deg(worst)
end
local function load(id, name)
	return assert(Player.LoadClip(id, name), id .. "/" .. tostring(name) .. " does not load")
end
-- The gap a matched entry leaves: last frame of `from` -> the frame MatchPhase picks in `into`.
local function matchedGap(id, from, into)
	local a, b = load(id, from), load(id, into)
	local phase = Player.MatchPhase(setmetatable({}, Player), b, {}, a)
	local frame = math.floor(phase * b.FPS + 0.5) + 1
	return gap(Player.CoreNames(b), poseOf(a, a.Frames), poseOf(b, frame))
end
local function joinGap(id, from, into)
	local a, b = load(id, from), load(id, into)
	return gap(Player.CoreNames(b), poseOf(a, a.Frames), poseOf(b, 1))
end

local MIN_CYCLE = WORK.MinCooldown + WORK.Duration

test("DogDigProfiles.MinCycle matches Config.Work (MinCooldown + Duration)", function()
	check(Profiles.MinCycle == MIN_CYCLE, "MinCycle " .. tostring(Profiles.MinCycle) .. " vs " .. MIN_CYCLE)
end)

test("every profile names a real dog and real clips", function()
	local problems = {}
	for id, profile in pairs(Profiles.Dogs) do
		local folder = library:FindFirstChild(id)
		if not folder then
			table.insert(problems, id .. " has no clip folder")
		else
			for key, value in pairs(profile) do
				if key == "Fade" then
					for fadeKey, seconds in pairs(value) do
						if type(seconds) ~= "number" or seconds < 0 or seconds > 1 then
							table.insert(problems, id .. ".Fade." .. fadeKey)
						end
					end
				elseif key == "FindEvery" then
					if type(value) ~= "number" or value < 1 then
						table.insert(problems, id .. ".FindEvery")
					end
				elseif key == "Repeat" then
					if type(value) ~= "boolean" or not profile.Action then
						table.insert(problems, id .. ".Repeat needs an Action")
					end
				elseif value ~= false then
					local list = if type(value) == "table" then value else { value }
					for _, name in ipairs(list) do
						local source = folder:FindFirstChild(name)
						if not source or not source:IsA("ModuleScript") then
							table.insert(problems, id .. "." .. key .. " = " .. tostring(name) .. " is missing")
						end
					end
				end
			end
		end
	end
	table.sort(problems)
	check(#problems == 0, table.concat(problems, "; "))
end)

local chains = {}
test("every dog resolves a complete, decodable dig chain", function()
	local problems = {}
	for _, id in ipairs(dogIds) do
		local chain = Player.Chain(id)
		if not chain or not chain.Idle or not chain.Loop then
			table.insert(problems, id .. ": no Idle/Loop")
		else
			chains[id] = chain
			if not Player.ResolveName(id, "Walk") then
				table.insert(problems, id .. ": no Walk")
			end
			local names = { chain.Idle, chain.Loop }
			for _, list in ipairs({ chain.Start or {}, chain.End or {}, chain.Accent or {} }) do
				for _, name in ipairs(list) do
					table.insert(names, name)
				end
			end
			for _, name in ipairs(names) do
				local clip = Player.LoadClip(id, name)
				if not clip then
					table.insert(problems, id .. "/" .. name .. " does not decode")
				elseif clip.SourceName ~= name then
					table.insert(problems, id .. "/" .. name .. " resolved to " .. clip.SourceName)
				end
			end
		end
	end
	check(#dogIds == 101, "expected 101 dogs, found " .. #dogIds)
	check(#problems == 0, table.concat(problems, "; "))
	check(#warnings == 0, "clip warnings: " .. table.concat(warnings, "; "))
end)

test("precedence: profile > folder attribute > candidate names", function()
	-- CaptainCorgi's folder says WorkClip=Rally; the profile wins.
	check(library.CaptainCorgi:GetAttribute("WorkClip") == "Rally", "fixture changed")
	check(Player.ResolveName("CaptainCorgi", "Work") == "Sniff", "profile Loop")
	-- Sausagedog has no Loop in a profile: its attribute WorkClip=DigLoop.
	check(Player.ResolveName("Sausagedog", "Work") == library.Sausagedog:GetAttribute("WorkClip"), "attribute")
	-- Breadog has no attributes: candidates.
	check(library.Breadog:GetAttribute("WorkClip") == nil and Player.ResolveName("Breadog", "Work") == "DigLoop", "candidates")
	check(Player.ResolveName("Breadog", "Start") == "DigStart" and Player.ResolveName("Breadog", "Find") == "DigFind", "new roles")
	-- false disables a role even when a candidate clip exists.
	check(library.TheDog:FindFirstChild("Dig_Start") and Player.ResolveChain("TheDog", "Start") == nil, "false = none")
	check(Player.ResolveName("Vampug", "Idle") == "Idle_Night", "Vampug idle")
	-- The original protocol: role names resolve, exact clip names play as they are.
	check(load("NeonHound", "Idle").SourceName == "IDLE", "role Idle")
	check(load("TheDog", "Find").SourceName == "Find", "exact clip name wins over the Find role")
	check(Player.DogIdFor("Zombark_Roblox") == "Zombark" and Player.DogIdFor("Breadog") == "Breadog", "VisualAsset -> Id")
end)

test("the clips the audit flagged are not work loops any more", function()
	local banned = {
		CaptainCorgi = "Rally", MechaBark = "ChargeImpact", Barkula = "BAT_DIG", ["404Dog"] = "Depth_Bypass",
		TheDog = "Ground_Opens",
	}
	for id, name in pairs(banned) do
		check(chains[id].Loop ~= name, id .. " still loops " .. name)
		for _, list in ipairs({ chains[id].Start or {}, chains[id].End or {} }) do
			for _, clip in ipairs(list) do
				check(clip ~= name, id .. " still plays " .. name .. " in its chain")
			end
		end
	end
	check(not table.find(chains.TheDog.Accent or {}, "Ground_Opens"), "TheDog's arrival cinematic stays out of the kennel")
	check(chains.Vampug.Idle ~= "Sleep", "Vampug rests with its eyes shut")
	check(chains.CoffeeDog.Start[1] == "DrinkStart" and chains.CoffeeDog.End[1] == "DrinkEnd", "CoffeeDog keeps its drink chain")
	check(chains.Ramendog.Start[1] == "DigStart", "Ramendog's DigStart leads into Cook")
	-- No kennel clip is squeezed any more: the old 4 s window does not exist.
	for _, id in ipairs(dogIds) do
		local loop = load(id, chains[id].Loop)
		check(Player.GetWorkSpeed(id, chains[id].Loop, MIN_CYCLE) == 1 or loop.Duration > MIN_CYCLE, id .. " loop would be sped up")
	end
end)

test("accents play at x1.0 and fit between two finds", function()
	local rows = {}
	for _, id in ipairs(dogIds) do
		local chain = chains[id]
		if chain.Accent then
			local seconds = assert(Player.SequenceDuration(id, chain.Accent))
			check(seconds <= MIN_CYCLE, id .. " accent lasts " .. seconds .. " s > " .. MIN_CYCLE)
			table.insert(rows, string.format("%s %s %.2fs%s", id, table.concat(chain.Accent, "+"), seconds, chain.Repeat and " (repeat)" or ""))
		end
	end
	check(#rows > 20, "expected accents for the find dogs")
end)

-- Transition report. Authored hops inside one sequence must join and an accent must return to
-- its loop moderately; rest <-> work posture changes are crossfaded adaptively (longer for a
-- bigger gap) and only reported here; the per-frame continuity test below measures them.
local report = {}
test("transition pose gaps (core bones)", function()
	local problems = {}
	local function note(id, kind, from, into, degrees, limit)
		table.insert(report, { id, kind, from, into, degrees })
		if limit and degrees > limit then
			table.insert(problems, string.format("%s %s %s->%s %.0f deg > %d", id, kind, from, into, degrees, limit))
		end
	end
	for _, id in ipairs(dogIds) do
		local chain = chains[id]
		for _, list in ipairs({ chain.Start or {}, chain.End or {}, chain.Accent or {} }) do
			for i = 1, #list - 1 do
				note(id, "hop", list[i], list[i + 1], joinGap(id, list[i], list[i + 1]), 12)
			end
		end
		if chain.Start then
			note(id, "start>loop", chain.Start[#chain.Start], chain.Loop, matchedGap(id, chain.Start[#chain.Start], chain.Loop))
		end
		if chain.Accent then
			local last = chain.Accent[#chain.Accent]
			note(id, "accent>loop", last, chain.Loop, matchedGap(id, last, chain.Loop), 45)
			if chain.Repeat then
				note(id, "repeat", last, chain.Accent[1], joinGap(id, last, chain.Accent[1]), 12)
			end
		end
		if chain.End then
			note(id, "loop>end", chain.Loop, chain.End[1], joinGap(id, chain.Loop, chain.End[1]))
			note(id, "end>idle", chain.End[#chain.End], chain.Idle, matchedGap(id, chain.End[#chain.End], chain.Idle))
		end
	end
	check(#problems == 0, table.concat(problems, "; "))
end)

-- Kennel driver simulation ---------------------------------------------------------------------
-- A light stand-in rig built from the real template bone hierarchy (Lune has no Model pivots
-- or Bone.Transform defaults): bones are tables the player writes Transform into.
local function fakeRig(id)
	local template = assert(templates:FindFirstChild(definitions[id].VisualAsset), "no template for " .. id)
	local attributes = { AnimationBaseScale = 1, VisualSize = Vector3.new(6, 4, 6), DogId = id }
	local model = { Name = id }
	local list, fakes = {}, {}
	local function world(node)
		if not node.IsBone then
			return node.CFrame
		end
		return world(node.Parent) * node.CFrame * node.Transform
	end
	local boneMeta = { __index = function(self, key)
		if key == "TransformedWorldCFrame" then
			return world(self)
		elseif key == "WorldCFrame" then
			return world(self.Parent) * self.CFrame
		end
		return nil
	end }
	for _, real in template:GetDescendants() do
		local bone = real:IsA("Bone")
		if bone or real:IsA("BasePart") then
			local fake = { Name = real.Name, CFrame = real.CFrame, IsBone = bone, Transform = CFrame.identity }
			fake.IsA = function(self, class)
				if self.IsBone then
					return class == "Bone"
				end
				return class == "BasePart"
			end
			if bone then
				setmetatable(fake, boneMeta)
			end
			fakes[real] = fake
			table.insert(list, fake)
		end
	end
	for real, fake in pairs(fakes) do
		fake.Parent = fakes[real.Parent] or model
	end
	function model:GetDescendants()
		return list
	end
	function model:GetScale()
		return 1
	end
	function model:GetPivot()
		return CFrame.identity
	end
	function model:GetAttribute(key)
		return attributes[key]
	end
	function model:FindFirstChild()
		return nil
	end
	return model
end

local function coreBones(player)
	local names = {}
	for _, name in ipairs(Player.CoreNames(load(player.DogId, Player.Chain(player.DogId).Loop))) do
		local bone = player.Bones[name]
		if bone then
			table.insert(names, bone)
		end
	end
	return names
end

-- The authored pose (rotation only) of the clip the player is on, at server time `at`, using
-- the same timeline as Player:Sample (loop wrap, recovery to frame 1, one-shot hold).
local function angleBetween(a, b)
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	angle = math.abs(angle) % (2 * math.pi)
	return if angle > math.pi then 2 * math.pi - angle else angle
end
local function authoredPose(player, bones, at)
	local clip = player.Clip
	local seconds = math.max(0, (at - player.StartTime) * player.Speed + (player.PhaseOffset or 0))
	local t = if player.Looped then seconds % (clip.Duration + player.Recovery) else math.min(seconds, clip.Duration)
	local recovery = if t > clip.Duration and player.Recovery > 0 then (function(a)
		a = math.clamp(a, 0, 1)
		return a * a * (3 - 2 * a)
	end)((t - clip.Duration) / player.Recovery) else 0
	local f = math.min(t, clip.Duration) * clip.FPS
	local index, alpha = math.floor(f) + 1, f % 1
	local pose = {}
	for _, bone in ipairs(bones) do
		local frames = clip.Tracks[bone.Name]
		local cf = CFrame.identity
		if frames then
			cf = frames[math.min(index, #frames)]:Lerp(frames[math.min(index + 1, #frames)], alpha)
			if recovery > 0 then
				cf = cf:Lerp(frames[1], recovery)
			end
		end
		pose[bone] = cf.Rotation
	end
	return pose
end

-- One dog through several cycles: assigned (fresh), digging, storage full, resumed.
-- Returns stats; `measure` samples bones (visible) and records the per-frame pose change.
local function simulate(id, cycle, fps, seconds, measure)
	local chain = chains[id]
	local model = fakeRig(id)
	local player = Player.new(model, id)
	Player.PreloadChain(id)
	player.CacheScale = true
	local t0 = 1000
	clock = t0
	local info = { Working = true, AssignedAt = t0, NextWorkAt = t0 + WORK.Duration, WorkSequence = 0, WorkCycle = cycle }
	local stats = { Finds = 0, Accents = 0, AccentErrors = {}, Frozen = 0, WrongClip = {}, MaxJump = 0, MaxExcess = 0, Cuts = {}, RestOk = false }
	local accentNames = {}
	for _, name in ipairs(chain.Accent or {}) do
		accentNames[name] = true
	end
	local workSet = { [chain.Loop] = true }
	for _, list in ipairs({ chain.Start or {}, chain.Accent or {} }) do
		for _, name in ipairs(list) do
			workSet[name] = true
		end
	end
	-- Production stops (storage full) 26 s before the end and resumes 14 s later.
	local stopAt = t0 + seconds - 26
	local resumeAt = stopAt + 14
	local dt = 1 / fps
	local bones = measure and coreBones(player)
	local last, lastClip, lastStart = {}, nil, nil
	local accentDuration = chain.Accent and Player.SequenceDuration(id, chain.Accent)
	local finishedSince = nil
	for step = 0, math.floor(seconds * fps) do
		clock = t0 + step * dt
		-- Server: the tick credits the find within a second after the deadline.
		if info.Working and clock >= info.NextWorkAt + 0.4 then
			info.WorkSequence += 1
			info.NextWorkAt = math.floor(clock) + cycle
			stats.Finds += 1
		end
		local working = not (clock >= stopAt and clock < resumeAt)
		if not working and info.Working then
			info.Working = false
		elseif working and not info.Working then
			info.Working = true
			info.NextWorkAt = math.floor(clock) + WORK.Duration
		end
		Player.PumpPreload(2)
		player:UpdateKennel(info, clock, measure == true)
		if measure then
			player:Step(clock)
		else
			player:Advance(clock)
		end
		local clip = player.Clip
		check(clip, id .. ": no clip at " .. clock - t0)
		-- An accent copy starts: it must end exactly on the coming find.
		if clip.SourceName == (chain.Accent and chain.Accent[1]) and (lastClip ~= clip or lastStart ~= player.StartTime) then
			stats.Accents += 1
			-- Copies of a repeating action end on NextWorkAt - k*D; every other accent on NextWorkAt.
			local ends = player.StartTime + accentDuration
			local copies = (info.NextWorkAt - ends) / accentDuration
			local aligned = math.abs(copies - math.floor(copies + 0.5)) < 1e-6 and copies > -1e-6
			if not aligned or (not chain.Repeat and math.abs(ends - info.NextWorkAt) > 1e-6) then
				table.insert(stats.AccentErrors, string.format("t=%.2f ends %.3f next %.3f", clock - t0, ends - t0, info.NextWorkAt - t0))
			end
		end
		lastClip, lastStart = clip, player.StartTime
		-- Never hold a finished one-shot (the dog would freeze).
		if not player.Looped and player:IsDone(clock) then
			finishedSince = finishedSince or clock
			if clock - finishedSince > 2.5 * dt then
				stats.Frozen += 1
			end
		else
			finishedSince = nil
		end
		-- While producing (after the lead-in) the dog only plays its work clips.
		if info.Working and clock - t0 > 3 and not (clock >= resumeAt and clock < resumeAt + 3) and not workSet[clip.SourceName] then
			stats.WrongClip[clip.SourceName] = (stats.WrongClip[clip.SourceName] or 0) + 1
		end
		-- Resting: the rest pose once DigEnd and the boundary wait are over.
		if not info.Working and clock >= stopAt + 7 and clip.SourceName == chain.Idle and player.Looped then
			stats.RestOk = true
		end
		if measure then
			-- Smoothness, per body bone and frame:
			--  * outside a crossfade the pose moves exactly as the clip does (no jumps);
			--  * a clip change either joins (within a few degrees) or crossfades for at least
			--    max(.15 s, gap / 150 deg/s): never a cut across a real gap;
			--  * inside a crossfade the extra motion stays moderate.
			local changed = clip ~= stats.LastClip or player.StartTime ~= stats.LastStart
			local before, now = authoredPose(player, bones, clock - dt), authoredPose(player, bones, clock)
			local jump, excess, cut = 0, 0, 0
			for _, bone in ipairs(bones) do
				local previous = last[bone]
				if previous then
					local turned = math.deg(angleBetween(previous, bone.Transform))
					jump = math.max(jump, turned)
					excess = math.max(excess, turned - math.deg(angleBetween(before[bone], now[bone])))
					cut = math.max(cut, math.deg(angleBetween(previous, before[bone])))
				end
				last[bone] = bone.Transform
			end
			stats.MaxJump = math.max(stats.MaxJump, jump)
			local blending = player.BlendFrom ~= nil or stats.WasBlending
			if changed and step > 0 then
				local needed = math.min(0.7, math.max(0.15, cut / 150)) * 0.95
				if cut > 5 and (player.BlendDuration or 0) < needed then
					table.insert(stats.Cuts, string.format("%.2fs %s->%s %.0f deg in %.2fs", clock - t0, stats.LastClip and stats.LastClip.SourceName or "?", clip.SourceName, cut, player.BlendDuration or 0))
				end
			elseif not blending and not changed and excess > 3 then
				table.insert(stats.Cuts, string.format("%.2fs jump on %s %.1f deg", clock - t0, clip.SourceName, excess))
			end
			if blending and excess > stats.MaxExcess then
				stats.MaxExcess, stats.ExcessAt = excess, string.format("%.2fs on %s", clock - t0, clip.SourceName)
			end
			stats.LastClip, stats.LastStart, stats.WasBlending = clip, player.StartTime, player.BlendFrom ~= nil
		end
	end
	return stats, player
end

test("kennel driver: every dog works continuously and lands accents on finds (10 s and 24 s cycles)", function()
	local problems = {}
	for _, cycle in ipairs({ MIN_CYCLE, 24 }) do
		for _, id in ipairs(dogIds) do
			local ok, stats = pcall(simulate, id, cycle, 10, 3 * cycle + 20, false)
			if not ok then
				table.insert(problems, id .. ": " .. tostring(stats))
			else
				if stats.Frozen > 0 then
					table.insert(problems, string.format("%s/%ds froze on a finished one-shot %d frames", id, cycle, stats.Frozen))
				end
				for name, frames in pairs(stats.WrongClip) do
					table.insert(problems, string.format("%s/%ds played %s while producing (%d frames)", id, cycle, name, frames))
				end
				if not stats.RestOk then
					table.insert(problems, string.format("%s/%ds never settled into Idle after production stopped", id, cycle))
				end
				for _, err in ipairs(stats.AccentErrors) do
					table.insert(problems, string.format("%s/%ds accent misaligned %s", id, cycle, err))
				end
				local chain = chains[id]
				if chain.Accent and not chain.Repeat and chain.Every == 1 and stats.Accents < stats.Finds - 2 then
					table.insert(problems, string.format("%s/%ds %d finds but %d accents", id, cycle, stats.Finds, stats.Accents))
				end
				if chain.Accent and chain.Repeat and stats.Accents < stats.Finds then
					table.insert(problems, string.format("%s/%ds repeat action played %d copies for %d finds", id, cycle, stats.Accents, stats.Finds))
				end
			end
		end
	end
	table.sort(problems)
	check(#problems == 0, #problems .. " problems: " .. table.concat(problems, "; ", 1, math.min(#problems, 12)))
end)

test("kennel driver: joining mid-work enters the loop at the same phase on every client", function()
	for _, id in ipairs({ "Breadog", "Samuriba", "MechaBark", "TheDog", "404Dog" }) do
		local info = { Working = true, AssignedAt = 1000, NextWorkAt = 1037, WorkSequence = 9, WorkCycle = 24 }
		local a = Player.new(fakeRig(id), id)
		local b = Player.new(fakeRig(id), id)
		clock = 1030.25
		a:UpdateKennel(info, clock, false)
		clock = 1030.25
		b:UpdateKennel(info, clock, true)
		check(a.Clip.SourceName == b.Clip.SourceName and a.StartTime == b.StartTime, id .. " join differs between clients")
		check(a.Clip.SourceName ~= (chains[id].Start or {})[1], id .. " replayed DigStart on join")
		check(a.BlendFrom == nil or a.BlendDuration == 0, id .. " fades in from the bind pose on join")
	end
end)

test("kennel driver: a fresh assignment plays DigStart, then the phase-matched loop", function()
	local info = { Working = true, AssignedAt = 2000, NextWorkAt = 2004, WorkSequence = 0, WorkCycle = 24 }
	local player = Player.new(fakeRig("Breadog"), "Breadog")
	clock = 2000.1
	player:UpdateKennel(info, clock, true)
	check(player.Clip.SourceName == "DigStart" and player.Queue and player.Queue.Name == "DigLoop", "DigStart queued into DigLoop")
	-- Breadog's Idle ends exactly where DigStart begins: an authored join is cut, not blended.
	check(player.BlendDuration == 0 or player.BlendDuration >= chains.Breadog.Fades.Start, "start fade")
	local ends = player.StartTime + player.Clip.Duration
	clock = ends + 0.01
	player:Step(clock)
	check(player.Clip.SourceName == "DigLoop" and player.Looped, "loop after DigStart")
	check(player.BlendDuration == 0 or player.BlendDuration >= chains.Breadog.Fades.Loop, "loop fade")
	check(player:Remaining(clock) > 0 and not player:IsDone(clock), "a loop is never done")
end)

test("kennel driver: per-frame pose continuity at 20 fps over 12 s cycles (no pops on any transition)", function()
	local rows, problems = {}, {}
	for _, id in ipairs({ "Breadog", "Sausagedog", "CoffeeDog", "Ramendog", "CaptainCorgi", "MechaBark", "Barkula", "404Dog",
		"Samuriba", "Cubedog", "TheDog", "Vampug", "SharkdogPrime", "Dogzilla", "LongDog", "ArcadeAkita", "Crabull", "GoldenBoi",
		"MilkyPup", "GalaxyHusky", "Pelmendog", "RocketDachshund", "Dogdogdogdog", "WizardWoof", "CaptainBark", "Aurion" }) do
		local stats = simulate(id, 12, 20, 76, true)
		table.insert(rows, string.format("%-15s fade extra %.1f deg/frame (%s), raw max %.1f", id, stats.MaxExcess, stats.ExcessAt or "-", stats.MaxJump))
		for _, cut in ipairs(stats.Cuts) do
			table.insert(problems, id .. " " .. cut)
		end
		if stats.MaxExcess > 25 then
			table.insert(problems, string.format("%s crossfade adds %.1f deg/frame at %s", id, stats.MaxExcess, stats.ExcessAt))
		end
	end
	if #problems > 0 or require("@lune/process").env.ANIM_VERBOSE == "1" then
		print(table.concat(rows, "\n"))
	end
	check(#problems == 0, table.concat(problems, "; ", 1, math.min(#problems, 15)))
end)

test("player API: queue, IsDone/Remaining, explicit fades, closed seams", function()
	local player = Player.new(fakeRig("Cubedog"), "Cubedog")
	clock = 3000
	check(player:Play("Dig_End", { FadeTime = 0, Looped = false, Next = { "Idle", { FadeTime = 0.3, Looped = true } } }), "play")
	check(not player:IsDone(clock) and math.abs(player:Remaining(clock) - player.Clip.Duration) < 1e-9, "fresh one-shot")
	clock += player.Clip.Duration + 0.001
	check(player:IsDone(clock), "done after its duration")
	player:Step(clock)
	check(player.Clip.SourceName == "Idle" and player.BlendDuration == 0.3, "Next played with its fade")
	-- A closed one-shot loops without the recovery hold; an open one recovers.
	check(load("Cubedog", "Cube_Impact_Sequence").SeamClosed, "Cube_Impact_Sequence is closed")
	player:Play("Cube_Impact_Sequence", { Looped = true, FadeTime = 0 })
	check(player.Recovery == 0, "closed seam: no recovery")
	player:Play("Impact", { Looped = true, FadeTime = 0 })
	check(player.Recovery > 0, "open seam: recovery")
	-- Default fade is unchanged for the other callers.
	player:Play("Walk")
	check(player.BlendDuration == 0.18, "default crossfade .18")
end)

print(string.format("animations: %d passed, %d failed", passed, failed))
if failed > 0 then
	local worst = {}
	for _, row in ipairs(report) do
		if row[5] > 25 then
			table.insert(worst, string.format("  %s %s %s->%s %.0f", row[1], row[2], row[3], row[4], row[5]))
		end
	end
	if #worst > 0 then
		print("largest transition gaps (crossfaded adaptively):\n" .. table.concat(worst, "\n"))
	end
	error("animation tests failed")
end
