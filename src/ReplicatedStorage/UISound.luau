-- Interface sounds: named cues on a small voice pool, routed through the game's sound buses.
--
--   local UISound = require(ReplicatedStorage.UISound)
--   UISound.Play("Success")                         -- a cue name from UISound.Cues
--   UISound.Play("Coin", { Pitch = 1.2, Volume = 0.8, Bus = "SFX", From = guiObject })
--   local binding = UISound.Bind(button)            -- hover + press sounds; binding:Disconnect()
--   UISound.Bind(button, { Hover = "Hover", Press = false })
--   UISound.EnsureGroups()                          -- server: SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient}
--
-- Buses: SoundService.DOGROTS_AUDIO holds SoundGroups UI, SFX and Ambient (created by the server at
-- start, ServerScriptService.AudioBootstrap; the place itself only has Music and WorldEvents) next
-- to the existing Music and WorldEvents groups. On the client the UI / SFX group volumes follow the
-- Setting_UIVolume / Setting_SFXVolume player attributes (0..1, default 1). If a group is missing
-- the sound still plays, with the setting applied to the sound itself.
--
-- Cues are built from sounds bundled with every Roblox client that this project's audio already
-- uses (MiningAudio, LabAudioConfig, LuckyAudio), re-pitched in layers. An owner can upload real
-- sounds and set UISound.AssetIds[cue] to the asset id (0 = the built-in recipe).
-- Limits: at most MaxVoices (6) sounds at once (low-priority cues never cut others off), and a
-- per-cue cooldown so hover spam stays quiet. A GUI subtree is silenced with the UISoundOff = true
-- attribute on it or any ancestor (Kit windows with Sound = false set it).
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UISound = {}

UISound.Folder = "DOGROTS_AUDIO"
UISound.Groups = { "UI", "SFX", "Ambient" }
UISound.Settings = { UI = "Setting_UIVolume", SFX = "Setting_SFXVolume" }
UISound.MaxVoices = 6

-- Engine-bundled sounds (rbxasset://sounds/...), the same ones the place's audio modules use.
local TICK = "rbxasset://sounds/volume_slider.ogg"
local COLLIDE = "rbxasset://sounds/collide.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local SLASH = "rbxasset://sounds/swordslash.wav"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
UISound.Bundled = { TICK, COLLIDE, PING, SLASH, LAND }

-- Owner-uploaded replacements: rbxassetid numbers (0 = built-in recipe).
UISound.AssetIds = {
	Hover = 0, Press = 0, Open = 0, Close = 0, Tab = 0, Toggle = 0, Success = 0, Error = 0, Reward = 0,
	Coin = 0, Whoosh = 0, Pop = 0, Rare = 0, Epic = 0, Legendary = 0, Countdown = 0, Lock = 0,
}

-- A layer: { sound, volume, pitch, delay (s), pitch jitter (fraction) }.
-- Priority: 0 never takes a busy voice; higher cues may cut off an equal or lower one.
local CHIME = { 1, 1.25, 1.5, 2 } -- the place's chime steps (MiningAudio Buy, LuckyAudio)
local function chime(steps: number, volume: number, gap: number, sound: string?): { any }
	local layers = {}
	for i = 1, steps do
		table.insert(layers, { sound or TICK, volume, CHIME[i] * 1.5, (i - 1) * gap, 0 })
	end
	return layers
end
local function with(layers: { any }, ...: any): { any }
	local out = table.clone(layers)
	for i = 1, select("#", ...) do
		table.insert(out, (select(i, ...)))
	end
	return out
end

UISound.Cues = {
	Hover = { Bus = "UI", Priority = 0, Cooldown = 0.06, Layers = { { TICK, 0.05, 2.1, 0, 0.03 } } },
	Press = { Bus = "UI", Priority = 1, Cooldown = 0.05, Layers = { { TICK, 0.12, 1.25, 0, 0.03 } } },
	Open = { Bus = "UI", Priority = 1, Cooldown = 0.12, Layers = { { TICK, 0.11, 1.5, 0, 0 }, { TICK, 0.09, 1.875, 0.05, 0 } } },
	Close = { Bus = "UI", Priority = 1, Cooldown = 0.12, Layers = { { TICK, 0.1, 1.875, 0, 0 }, { TICK, 0.08, 1.5, 0.05, 0 } } },
	Tab = { Bus = "UI", Priority = 1, Cooldown = 0.05, Layers = { { TICK, 0.1, 1.6, 0, 0.02 } } },
	Toggle = { Bus = "UI", Priority = 1, Cooldown = 0.05, Layers = { { TICK, 0.12, 1.4, 0, 0 }, { TICK, 0.07, 2.1, 0.04, 0 } } },
	Success = { Bus = "UI", Priority = 2, Cooldown = 0.15, Layers = { { TICK, 0.16, 1.5, 0, 0 }, { TICK, 0.16, 2.25, 0.11, 0 } } },
	Error = { Bus = "UI", Priority = 2, Cooldown = 0.2, Layers = { { TICK, 0.18, 0.5, 0, 0 }, { TICK, 0.18, 0.42, 0.08, 0 } } },
	Reward = { Bus = "UI", Priority = 3, Cooldown = 0.25, Layers = chime(4, 0.18, 0.1) },
	Coin = { Bus = "UI", Priority = 1, Cooldown = 0.05, Layers = { { TICK, 0.11, 1.8, 0, 0.04 } } },
	Whoosh = { Bus = "UI", Priority = 1, Cooldown = 0.1, Layers = { { SLASH, 0.14, 0.9, 0, 0.05 } } },
	Pop = { Bus = "UI", Priority = 1, Cooldown = 0.04, Layers = { { TICK, 0.16, 2.6, 0, 0.05 } } },
	Rare = { Bus = "UI", Priority = 3, Cooldown = 0.3, Layers = with(chime(2, 0.16, 0.1), { PING, 0.12, 1.2, 0, 0 }) },
	Epic = { Bus = "UI", Priority = 3, Cooldown = 0.3, Layers = with(chime(3, 0.17, 0.1), { PING, 0.13, 1.1, 0, 0 }) },
	Legendary = { Bus = "UI", Priority = 4, Cooldown = 0.4, Layers = with(chime(4, 0.18, 0.12), { LAND, 0.24, 0.7, 0, 0 }) },
	Countdown = { Bus = "UI", Priority = 2, Cooldown = 0.2, Layers = { { TICK, 0.2, 1, 0, 0 } } },
	Lock = { Bus = "UI", Priority = 1, Cooldown = 0.1, Layers = { { COLLIDE, 0.18, 1.6, 0, 0 }, { TICK, 0.12, 0.7, 0.03, 0 } } },
}

-- The asset each layer of a cue plays (an uploaded replacement plays alone, at full layer 1 volume).
function UISound.Layers(cue: string): { any }?
	local def = UISound.Cues[cue]
	if not def then
		return nil
	end
	local id = tonumber(UISound.AssetIds[cue]) or 0
	if id > 0 then
		local first = def.Layers[1]
		return { { "rbxassetid://" .. string.format("%.0f", id), math.max(0.3, first[2] * 2), 1, 0, first[5] } }
	end
	return def.Layers
end

------------------------------------------------------------------------------------------------
-- Voice pool (pure apart from Create: tests drive it with fake sounds and a fake clock)
------------------------------------------------------------------------------------------------
local Mixer = {}
Mixer.__index = Mixer
UISound.Mixer = Mixer

-- options: {Max, Create = () -> sound-like, Clock = () -> number}
function Mixer.new(options: any): any
	return setmetatable({ Max = options.Max or UISound.MaxVoices, Create = options.Create, Clock = options.Clock or os.clock, Voices = {} }, Mixer)
end

-- A voice for a sound of `priority` lasting `length` seconds, or nil when every voice is busy with
-- something at least as important (priority 0 never cuts anything off).
function Mixer.Take(self: any, priority: number, length: number): any
	local now = self.Clock()
	local victim = nil
	for _, voice in ipairs(self.Voices) do
		if voice.BusyUntil <= now then
			victim = voice
			break
		end
	end
	if not victim and #self.Voices < self.Max then
		victim = { Sound = self.Create(), BusyUntil = 0, Priority = 0, Started = 0 }
		table.insert(self.Voices, victim)
	end
	if not victim and priority > 0 then
		for _, voice in ipairs(self.Voices) do
			if voice.Priority <= priority and (not victim or voice.Started < victim.Started) then
				victim = voice
			end
		end
		if victim then
			pcall(function()
				victim.Sound:Stop()
			end)
		end
	end
	if victim then
		victim.BusyUntil, victim.Priority, victim.Started = now + length, priority, now
	end
	return victim
end

function Mixer.Busy(self: any): number
	local now, n = self.Clock(), 0
	for _, voice in ipairs(self.Voices) do
		if voice.BusyUntil > now then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------------------------------------
-- Buses
------------------------------------------------------------------------------------------------

-- Server: makes sure SoundService.DOGROTS_AUDIO has the UI, SFX and Ambient SoundGroups.
function UISound.EnsureGroups(): Instance
	local folder = SoundService:FindFirstChild(UISound.Folder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = UISound.Folder
		folder.Parent = SoundService
	end
	for _, name in ipairs(UISound.Groups) do
		local group = folder:FindFirstChild(name)
		if not (group and group:IsA("SoundGroup")) then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Volume = 1
			group.Parent = folder
		end
	end
	return folder
end

local function settingVolume(bus: string): number
	local key = UISound.Settings[bus]
	local player = Players.LocalPlayer
	local value = key and player and player:GetAttribute(key)
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(value, 0, 1)
end

local groups: { [string]: SoundGroup } = {}
local watched: { [string]: boolean } = {}
-- The bus's SoundGroup (nil until the server has created it); applies the volume setting once found.
function UISound.Group(bus: string): SoundGroup?
	local cached = groups[bus]
	if cached and cached.Parent then
		return cached
	end
	local folder = SoundService:FindFirstChild(UISound.Folder)
	local group = folder and folder:FindFirstChild(bus)
	if not (group and group:IsA("SoundGroup")) then
		return nil
	end
	groups[bus] = group
	local key = UISound.Settings[bus]
	local player = Players.LocalPlayer
	if key and player and RunService:IsClient() then
		group.Volume = settingVolume(bus)
		if not watched[bus] then
			watched[bus] = true
			player:GetAttributeChangedSignal(key):Connect(function()
				local current = groups[bus]
				if current then
					current.Volume = settingVolume(bus)
				end
			end)
		end
	end
	return group
end

------------------------------------------------------------------------------------------------
-- Playback (client)
------------------------------------------------------------------------------------------------

local mixer: any = nil
local function shared(): any
	if not mixer then
		mixer = Mixer.new({
			Create = function()
				local sound = Instance.new("Sound")
				sound.Name = "DOGROTS_UISound"
				sound.Parent = SoundService
				return sound
			end,
		})
	end
	return mixer
end

local last: { [string]: number } = {}

function UISound.Silenced(object: Instance?): boolean
	local node = object
	while node do
		if node:GetAttribute("UISoundOff") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

local function playLayer(layer: any, bus: string, priority: number, options: any)
	local pitch = layer[3] * (options.Pitch or 1)
	local jitter = layer[5] or 0
	if jitter > 0 then
		pitch *= 1 + (math.random() * 2 - 1) * jitter
	end
	local voice = shared():Take(priority, 0.6)
	if not voice then
		return
	end
	local sound: Sound = voice.Sound
	local group = UISound.Group(bus)
	sound.SoundGroup = group
	sound.SoundId = layer[1]
	sound.PlaybackSpeed = pitch
	sound.Volume = math.clamp(layer[2] * (options.Volume or 1) * (group and 1 or settingVolume(bus)), 0, 2)
	sound:Play()
	-- The voice is busy for the real length once the asset is loaded (cached after the first play).
	if sound.TimeLength > 0 then
		voice.BusyUntil = os.clock() + sound.TimeLength / pitch + 0.03
	end
end

-- Plays a cue. options: {Pitch = multiplier, Volume = multiplier, Bus = "UI" | "SFX", From = an
-- Instance whose UISoundOff ancestors silence it}. Returns true when the cue started.
function UISound.Play(cue: string, options: any?): boolean
	local o = options or {}
	local def = UISound.Cues[cue]
	if not def or not RunService:IsClient() then
		return false
	end
	if o.From and UISound.Silenced(o.From) then
		return false
	end
	local now = os.clock()
	if now - (last[cue] or -math.huge) < (def.Cooldown or 0) then
		return false
	end
	last[cue] = now
	local bus = o.Bus or def.Bus or "UI"
	for _, layer in ipairs(UISound.Layers(cue) or {}) do
		if (layer[4] or 0) > 0 then
			task.delay(layer[4], playLayer, layer, bus, def.Priority or 1, o)
		else
			playLayer(layer, bus, def.Priority or 1, o)
		end
	end
	return true
end

-- Hover (mouse enter / gamepad selection, not touch) and press (Activated) sounds on a button.
-- options: {Hover = cue | false, Press = cue | false}. Disabled kit buttons (KitDisabled) stay
-- silent on press. Returns a connection-like object (Disconnect / Destroy).
function UISound.Bind(button: GuiButton, options: any?): any
	local o = options or {}
	local hover = if o.Hover == nil then "Hover" else o.Hover
	local press = if o.Press == nil then "Press" else o.Press
	local connections = {}
	if hover then
		local function onHover()
			if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
				UISound.Play(hover, { From = button })
			end
		end
		table.insert(connections, button.MouseEnter:Connect(onHover))
		table.insert(connections, button.SelectionGained:Connect(onHover))
	end
	if press then
		table.insert(connections, button.Activated:Connect(function()
			if button:GetAttribute("KitDisabled") ~= true then
				UISound.Play(press, { From = button })
			end
		end))
	end
	local binding = {}
	function binding.Disconnect()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	binding.Destroy = binding.Disconnect
	return binding
end

return UISound
