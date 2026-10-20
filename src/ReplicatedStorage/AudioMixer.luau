-- AudioMixer (ReplicatedStorage.AudioMixer): the one owner of the game's SoundGroup volumes (docs/halloween2/DESIGN.md
-- §16.1). Client module; on the server every call is a safe no-op (Group only looks the group up, nothing moves).
--
-- Bus layout (built offline by tools/edits/05_audio.luau from Mixer.Spec, repaired here on the client when missing):
--   SoundService.DOGROTS_AUDIO (Folder)   Music .7 (child "Halloween": the procedural OST) · WorldEvents .7 ·
--                                         Ambience .8 · UI 1
--   SoundService.DOGROTS_SFX (Folder)     Pickaxe 1 (child "DOGROTS_MiningSFX": every mining sound) · Boss 1 · SFX 1 ·
--                                         Cinema 1 (story stingers that must stay audible under a cinematic duck)
--
-- API
--   Mixer.Group(name) -> SoundGroup?        Music | WorldEvents | Ambience | UI | Pickaxe | Boss | SFX | Cinema
--   Mixer.Child(name) -> SoundGroup?        a nested group of Mixer.Spec.Children ("Halloween", "DOGROTS_MiningSFX")
--   Mixer.Duck(reason, levels, fade?)       levels = {Music = .2, ...} (fractions of the baseline) | preset name
--                                           ("Cinematic", "Silence", "Dialog", "Combat") | a number for every duckable
--                                           group. Several reasons at once: per group the QUIETEST reason wins.
--   Mixer.Release(reason, fade?)            drop a reason (no-op when unknown); the groups glide back
--   Mixer.Ducking(reason) -> bool ; Mixer.Level(name) -> current duck fraction of a group
--   Mixer.SetBase(name, volume)             the deliberate way to change a group's baseline (a future settings slider)
--   Mixer.Preset[name]                      duck presets (Mixer.Preset.Cinematic per §16.1)
--   Mixer.Mark(key) / Mixer.Since(key)      tiny "something just played" board shared by the sound engines (the
--                                           pickaxe kit marks "PickaxeImpact"; Halloween Dig* cues then play softly)
--   Mixer.Ensure(soundService) -> report    create / repair the bus layout (runtime and the offline edit)
--   Mixer.Math                              the pure duck math (tests/audio_mixer.luau)
-- Only SoundGroup.Volume is written, never Sound.Volume, so the music engines' own fades keep working. The baseline of a
-- group is its Volume the first time the mixer sees that instance (or Mixer.SetBase), never a value captured while a
-- duck holds it down, so a release always lands on the real level.
local Mixer = {}

---------------------------------------------------------------------------------------------------------------------
-- Layout (pure data: the offline edit and the runtime build the same tree from it)
---------------------------------------------------------------------------------------------------------------------
-- Compressors: catch peaks of stacked one-shots. The pickaxe bus never adds makeup gain (it is the loudest, most frequent
-- feedback in the game); SFX / Boss keep the +2 dB their Halloween group had, so existing cue levels stay where they were.
Mixer.Spec = {
	Folders = { "DOGROTS_AUDIO", "DOGROTS_SFX" },
	Groups = {
		Music = { Folder = "DOGROTS_AUDIO", Volume = .7, Duck = true },
		WorldEvents = { Folder = "DOGROTS_AUDIO", Volume = .7, Duck = true },
		Ambience = { Folder = "DOGROTS_AUDIO", Volume = .8, Duck = true },
		UI = { Folder = "DOGROTS_AUDIO", Volume = 1, Duck = true },
		Pickaxe = { Folder = "DOGROTS_SFX", Volume = 1, Duck = true,
			Compressor = { Threshold = -10, Ratio = 4, Attack = .002, Release = .1, GainMakeup = 0 } },
		Boss = { Folder = "DOGROTS_SFX", Volume = 1, Duck = true,
			Compressor = { Threshold = -14, Ratio = 3, Attack = .006, Release = .2, GainMakeup = 2 } },
		SFX = { Folder = "DOGROTS_SFX", Volume = 1, Duck = true,
			Compressor = { Threshold = -16, Ratio = 3, Attack = .005, Release = .15, GainMakeup = 2 } },
		Cinema = { Folder = "DOGROTS_SFX", Volume = 1, Duck = false,
			Compressor = { Threshold = -12, Ratio = 3, Attack = .004, Release = .25, GainMakeup = 0 } },
	},
	-- nested groups (their volume follows the parent bus)
	Children = {
		Halloween = { Parent = "Music", Volume = 1,
			Compressor = { Threshold = -16, Ratio = 3, Attack = .005, Release = .15, GainMakeup = 2 } },
		DOGROTS_MiningSFX = { Parent = "Pickaxe", Volume = 1,
			Compressor = { Threshold = -14, Ratio = 3, Attack = .004, Release = .12, GainMakeup = 0 } },
	},
}
Mixer.Order = { "Music", "WorldEvents", "Ambience", "UI", "Pickaxe", "Boss", "SFX", "Cinema" }

-- Duck presets (fractions of each group's baseline). Cinema is never ducked by a preset.
Mixer.Preset = {
	Cinematic = { Music = .15, Ambience = .35, Pickaxe = .25, Boss = .4, SFX = .5, UI = .8, WorldEvents = .15 },
	Silence = { Music = 0, Ambience = 0, Pickaxe = 0, Boss = 0, SFX = 0, UI = 0, WorldEvents = 0 },
	Dialog = { Music = .4, Ambience = .6, Pickaxe = .7, Boss = .7, SFX = .8, WorldEvents = .4 },
	Combat = { Music = .7, Ambience = .5, WorldEvents = .6 },
}

---------------------------------------------------------------------------------------------------------------------
-- Pure math
---------------------------------------------------------------------------------------------------------------------
local Math = {}
Mixer.Math = Math

-- levels spec -> {[group] = fraction 0..1} (unknown groups and non-numbers ignored)
function Math.Resolve(levels: any, presets: { [string]: any }?, groups: { [string]: any }?): { [string]: number }
	local out = {}
	local g = groups or Mixer.Spec.Groups
	if type(levels) == "string" then
		levels = (presets or Mixer.Preset)[levels]
	end
	if type(levels) == "number" then
		local v = math.clamp(levels, 0, 1)
		for name, def in pairs(g) do
			if def.Duck ~= false then
				out[name] = v
			end
		end
		return out
	end
	if type(levels) ~= "table" then
		return out
	end
	for name, v in pairs(levels) do
		if g[name] and type(v) == "number" and v == v then
			out[name] = math.clamp(v, 0, 1)
		end
	end
	return out
end

-- the duck fraction of a group: the quietest active reason (1 = untouched)
function Math.Level(reasons: { [string]: { [string]: number } }, group: string): number
	local level = 1
	for _, levels in pairs(reasons) do
		local v = levels[group]
		if v and v < level then
			level = v
		end
	end
	return level
end

-- the volume a group should glide to
function Math.Target(base: number, level: number): number
	return math.max(0, base) * math.clamp(level, 0, 1)
end

-- every group's target volume: {[group] = base * level}
function Math.Targets(bases: { [string]: number }, reasons: { [string]: { [string]: number } }): { [string]: number }
	local out = {}
	for name, base in pairs(bases) do
		out[name] = Math.Target(base, Math.Level(reasons, name))
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Building the tree (Instance.new + properties only: also runs offline through tools/sim.luau)
---------------------------------------------------------------------------------------------------------------------
local function applyCompressor(group: Instance, spec: { [string]: number }?, report: { [string]: any }?)
	local found = {}
	for _, c in ipairs(group:GetChildren()) do
		if c.ClassName == "CompressorSoundEffect" then
			table.insert(found, c)
		end
	end
	if not spec then
		return
	end
	local comp = found[1]
	for i = 2, #found do
		found[i]:Destroy() -- one compressor per bus (duplicates stack their makeup gain)
	end
	if not comp then
		comp = Instance.new("CompressorSoundEffect")
		comp.Name = "DOGROTS_BusCompressor"
		comp.Parent = group
		if report then
			report.Created += 1
		end
	end
	for key, v in pairs(spec) do
		if (comp :: any)[key] ~= v then
			(comp :: any)[key] = v
		end
	end
end

local function findClass(parent: Instance, name: string, class: string): Instance?
	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == name and c.ClassName == class then
			return c
		end
	end
	return nil
end

local function ensureGroup(parent: Instance, name: string, def: { [string]: any }, report: { [string]: any }?, keepVolume: boolean?): Instance
	local g = findClass(parent, name, "SoundGroup")
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name;
		(g :: any).Volume = def.Volume
		g.Parent = parent
		if report then
			report.Created += 1
			table.insert(report.Groups, name)
		end
	elseif not keepVolume and math.abs((g :: any).Volume - def.Volume) > 1e-4 then
		(g :: any).Volume = def.Volume
	end
	applyCompressor(g :: Instance, def.Compressor, report)
	return g :: Instance
end

-- Create / repair the bus layout under `soundService`. opts.KeepVolume: never overwrite an existing group's Volume
-- (runtime repair keeps whatever the place says). Returns {Created, Groups = {names created}, Moved}.
function Mixer.Ensure(soundService: Instance, opts: { [string]: any }?): { [string]: any }
	local report = { Created = 0, Groups = {}, Moved = 0 }
	local keep = opts ~= nil and opts.KeepVolume == true
	local folders = {}
	for _, name in ipairs(Mixer.Spec.Folders) do
		local f = soundService:FindFirstChild(name)
		if not f then
			f = Instance.new("Folder")
			f.Name = name
			f.Parent = soundService
			report.Created += 1
		end
		folders[name] = f
	end
	local made = {}
	for _, name in ipairs(Mixer.Order) do
		local def = Mixer.Spec.Groups[name]
		made[name] = ensureGroup(folders[def.Folder], name, def, report, keep)
	end
	local childNames = {}
	for name in pairs(Mixer.Spec.Children) do
		table.insert(childNames, name)
	end
	table.sort(childNames)
	for _, name in ipairs(childNames) do
		local def = Mixer.Spec.Children[name]
		local parent = made[def.Parent]
		-- an older build / client left the child at the SoundService root: move it under its bus
		local stray = findClass(soundService, name, "SoundGroup")
		if stray and not findClass(parent, name, "SoundGroup") then
			stray.Parent = parent
			report.Moved += 1
		end
		ensureGroup(parent, name, def, report, keep)
	end
	return report
end

---------------------------------------------------------------------------------------------------------------------
-- Runtime (client)
---------------------------------------------------------------------------------------------------------------------
local isClient: boolean? = nil
local function client(): boolean
	if isClient == nil then
		-- FindService: never creates anything (the offline builder runs this module on a place file)
		local ok, v = pcall(function()
			local rs = game:FindService("RunService")
			return rs ~= nil and rs:IsClient()
		end)
		isClient = ok and v == true
	end
	return isClient == true
end

local soundServiceRef: Instance? = nil
local function soundService(): Instance?
	if soundServiceRef then
		return soundServiceRef
	end
	local ok, s = pcall(function()
		return game:GetService("SoundService")
	end)
	soundServiceRef = ok and s or nil
	return soundServiceRef
end

local cache: { [string]: Instance } = {}
local bases = setmetatable({}, { __mode = "k" }) -- SoundGroup -> baseline volume
local ensured = false
-- the client only builds missing pieces once the place has loaded: before that the replicated folders may simply not
-- have arrived yet, and a client-made DOGROTS_AUDIO next to the replicated one would split the buses
local function loaded(): boolean
	local ok, v = pcall(function()
		return game:IsLoaded()
	end)
	return ok and v == true
end

local function lookup(name: string): Instance?
	local ss = soundService()
	if not ss then
		return nil
	end
	local def = Mixer.Spec.Groups[name]
	if def then
		local folder = ss:FindFirstChild(def.Folder)
		return folder and findClass(folder, name, "SoundGroup") or nil
	end
	local child = Mixer.Spec.Children[name]
	if child then
		local parent = lookup(child.Parent)
		return parent and findClass(parent, name, "SoundGroup") or nil
	end
	return nil
end

local function resolve(name: string): Instance?
	local g = cache[name]
	if g and g.Parent then
		return g
	end
	g = lookup(name)
	if not g and client() and not ensured and loaded() then
		-- the place has no bus layout (an old build) or it has not replicated yet: build the missing pieces locally
		ensured = true
		local ss = soundService()
		if ss then
			pcall(Mixer.Ensure, ss, { KeepVolume = true })
		end
		g = lookup(name)
	end
	if g then
		cache[name] = g
		if bases[g] == nil then
			bases[g] = (g :: any).Volume
		end
	end
	return g
end

function Mixer.Group(name: string): SoundGroup?
	if type(name) ~= "string" or not Mixer.Spec.Groups[name] then
		return nil
	end
	local ok, g = pcall(resolve, name)
	return (if ok then g else nil) :: any
end

function Mixer.Child(name: string): SoundGroup?
	if type(name) ~= "string" or not Mixer.Spec.Children[name] then
		return nil
	end
	local ok, g = pcall(resolve, name)
	return (if ok then g else nil) :: any
end

-- every SoundGroup of that name under the bus folder (a client-made copy and the replicated one may both exist briefly)
local function instancesOf(name: string): { Instance }
	local out = {}
	local ss = soundService()
	local def = Mixer.Spec.Groups[name]
	local folder = ss and def and ss:FindFirstChild(def.Folder)
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == name and c.ClassName == "SoundGroup" then
				table.insert(out, c)
				if bases[c] == nil then
					bases[c] = (c :: any).Volume
				end
			end
		end
	end
	return out
end

local reasons: { [string]: { [string]: number } } = {}
local tweens = setmetatable({}, { __mode = "k" })

-- Hooks (tests replace them): Tween(group, volume, seconds), Now()
Mixer.Hooks = {
	Tween = function(group: Instance, volume: number, seconds: number)
		local prev = tweens[group]
		if prev then
			prev:Cancel()
			tweens[group] = nil
		end
		if seconds <= .01 then
			(group :: any).Volume = volume
			return
		end
		local tw = game:GetService("TweenService"):Create(group, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Volume = volume })
		tweens[group] = tw
		tw:Play()
	end,
	Now = function(): number
		return os.clock()
	end,
}
-- tests drive the runtime without a client (fake groups through Mixer.Hooks.Instances)
Mixer.Hooks.Client = client

local function groupsOf(name: string): { Instance }
	local fake = (Mixer.Hooks :: any).Instances
	if type(fake) == "function" then
		return fake(name)
	end
	return instancesOf(name)
end

local function apply(fade: number)
	for _, name in ipairs(Mixer.Order) do
		local level = Math.Level(reasons, name)
		for _, g in ipairs(groupsOf(name)) do
			local base = bases[g]
			if base == nil then
				base = (g :: any).Volume
				bases[g] = base
			end
			local target = Math.Target(base, level)
			if math.abs((g :: any).Volume - target) > 1e-4 or tweens[g] then
				local ok, err = pcall(Mixer.Hooks.Tween, g, target, fade)
				if not ok then
					warn("AudioMixer: " .. tostring(err))
				end
			end
		end
	end
end

function Mixer.Duck(reason: string, levels: any, fade: number?)
	if not Mixer.Hooks.Client() or type(reason) ~= "string" then
		return
	end
	reasons[reason] = Math.Resolve(levels, Mixer.Preset, Mixer.Spec.Groups)
	apply(math.max(0, fade or .6))
end

function Mixer.Release(reason: string, fade: number?)
	if not Mixer.Hooks.Client() or reasons[reason] == nil then
		return
	end
	reasons[reason] = nil
	apply(math.max(0, fade or 1))
end

function Mixer.Ducking(reason: string): boolean
	return reasons[reason] ~= nil
end

function Mixer.Level(name: string): number
	return Math.Level(reasons, name)
end

function Mixer.SetBase(name: string, volume: number)
	if not Mixer.Hooks.Client() or not Mixer.Spec.Groups[name] then
		return
	end
	local v = math.clamp(tonumber(volume) or 1, 0, 2)
	for _, g in ipairs(groupsOf(name)) do
		bases[g] = v
	end
	apply(.25)
end

function Mixer.Base(name: string): number?
	local g = groupsOf(name)[1]
	return g and bases[g] or nil
end

-- "something just played" board
local marks: { [string]: number } = {}
function Mixer.Mark(key: string)
	marks[key] = Mixer.Hooks.Now()
end
function Mixer.Since(key: string): number
	local at = marks[key]
	return at and (Mixer.Hooks.Now() - at) or math.huge
end

function Mixer.Stats(): { [string]: any }
	local levels = {}
	for _, name in ipairs(Mixer.Order) do
		levels[name] = Math.Level(reasons, name)
	end
	local list = {}
	for r in pairs(reasons) do
		table.insert(list, r)
	end
	table.sort(list)
	return { Reasons = list, Levels = levels }
end

-- tests: forget every reason / baseline
function Mixer._Reset()
	table.clear(reasons)
	table.clear(marks)
	table.clear(cache)
	for g in pairs(bases) do
		bases[g] = nil
	end
	ensured = false
end

-- the client registers every bus once the place has loaded, so each baseline is taken before anything ducks (and a
-- place without the layout gets it repaired, the pickaxe group moved under its bus)
if client() then
	task.spawn(function()
		if not loaded() then
			pcall(function()
				game.Loaded:Wait()
			end)
		end
		for _, name in ipairs(Mixer.Order) do
			pcall(resolve, name)
		end
		for name in pairs(Mixer.Spec.Children) do
			pcall(resolve, name)
		end
	end)
end

return Mixer
