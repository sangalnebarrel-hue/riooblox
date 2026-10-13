-- Kit.Sound: short UI sound cues for the whole game (kit windows, HUD, legacy menus).
--   Kit.Sound.Play("Click")                 -- Hover | Click | Toggle | Tab | Open | Close |
--                                           -- Success | Error | Coin | Notify
--   Kit.Sound.Play("Coin", {Pitch = 1.1, Volume = 0.8})   -- multipliers for one play
--   Kit.Sound.Attach(button)                 -- hover + click sounds on any GuiButton (once)
--   button:SetAttribute("KitSound", "Tab")   -- the cue its click plays ("" = silent)
--   Kit.Sound.Enabled() / Kit.Sound.SetEnabled(false)    -- the "UI SOUNDS" setting
-- Cue data (asset ids to replace with real audio, volumes, pitches): Kit/SoundConfig.luau.
-- A few Sound instances per cue are created on first use in SoundService.KitUISounds and play
-- through SoundService.DOGROTS_AUDIO.UI. Each cue has a minimum gap (hover 60 ms) and at most
-- Config.MaxPerSecond sounds start per second. Nothing runs while no sound is requested.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Config = require(script.Parent.SoundConfig)

local Sound = {}
Sound.Config = Config
Sound.Cues = Config.Cues
-- true silences every cue for this session (tests, cinematics); the player setting is separate.
Sound.Muted = false

local voices: { [string]: { any } } = {}
local cursor: { [string]: number } = {}
local last: { [string]: number } = {}
local windowStart, windowCount = -math.huge, 0
local group: SoundGroup? = nil
local holder: Folder? = nil
local stats = { Played = 0, Throttled = 0, Voices = 0 }
local warmed = false

local function soundGroup(): SoundGroup?
	if group and group.Parent then
		return group
	end
	group = nil
	local root = SoundService:FindFirstChild(Config.Folder)
	if root then
		local existing = root:FindFirstChild(Config.Group)
		if existing == nil then
			local created = Instance.new("SoundGroup")
			created.Name = Config.Group
			created.Volume = 1
			created.Parent = root
			existing = created
		end
		if existing and existing:IsA("SoundGroup") then
			group = existing
		end
	end
	return group
end

local function folder(): Folder
	if holder and holder.Parent then
		return holder
	end
	local existing = SoundService:FindFirstChild("KitUISounds")
	if existing and existing:IsA("Folder") then
		holder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "KitUISounds"
	created.Parent = SoundService
	holder = created
	return created
end

-- The next voice of a cue (round robin over cue.Voices instances).
local function voice(name: string, cue: any): any
	local list = voices[name]
	if not list then
		list = {}
		voices[name] = list
	end
	local count = math.max(1, math.floor(tonumber(cue.Voices) or 1))
	local index = ((cursor[name] or 0) % count) + 1
	cursor[name] = index
	local sound = list[index]
	if not (sound and sound.Parent) then
		sound = Instance.new("Sound")
		sound.Name = "Kit_" .. name .. "_" .. index
		sound.Looped = false
		sound.SoundGroup = soundGroup()
		sound.Parent = folder()
		list[index] = sound
		stats.Voices += 1
	end
	local url = Config.Url(cue)
	if sound.SoundId ~= url then
		sound.SoundId = url -- the owner may set an uploaded id while the game runs
	end
	return sound
end

function Sound.Enabled(): boolean
	if Sound.Muted then
		return false
	end
	local player = Players.LocalPlayer
	return not (player and player:GetAttribute(Config.Attribute) == false)
end

-- The "UI SOUNDS" setting: a player attribute (local to this session).
function Sound.SetEnabled(on: boolean)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute(Config.Attribute, on == true)
	end
end

-- Plays a cue. opts: Pitch / Volume multipliers. Returns true when a sound started.
function Sound.Play(name: string, opts: any?): boolean
	local cue = Config.Cues[name]
	if not cue or not Sound.Enabled() then
		return false
	end
	if not warmed then
		-- The first sound creates one voice per cue, so the others are loaded before they play.
		warmed = true
		task.defer(Sound.Warm)
	end
	local now = os.clock()
	if now - (last[name] or -math.huge) < (cue.Gap or 0.03) then
		stats.Throttled += 1
		return false
	end
	if now - windowStart >= 1 then
		windowStart, windowCount = now, 0
	end
	if windowCount >= Config.MaxPerSecond then
		stats.Throttled += 1
		return false
	end
	last[name] = now
	windowCount += 1
	local o: any = opts or {}
	local ok = pcall(function()
		local sound = voice(name, cue)
		sound.Volume = math.clamp((cue.Volume or 0.3) * (tonumber(o.Volume) or 1), 0, 1)
		sound.PlaybackSpeed = Config.Speed(cue, math.random(), tonumber(o.Pitch))
		sound.TimePosition = 0
		sound:Play()
	end)
	if ok then
		stats.Played += 1
	end
	return ok
end

-- True when the last input came from a mouse (touch taps also fire MouseEnter: no hover there).
function Sound.MouseInput(): boolean
	local ok, kind = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if not ok then
		return false
	end
	return kind == Enum.UserInputType.MouseMovement
		or kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.MouseButton2
		or kind == Enum.UserInputType.MouseWheel
end

local function usable(button: GuiButton): boolean
	return button.Active and button:GetAttribute("KitDisabled") ~= true and button:GetAttribute("UIEnabled") ~= false
end

-- Hover (mouse / gamepad selection) and click sounds on a GuiButton. Wires a button once (the
-- KitSoundWired attribute); the click cue is the button's KitSound attribute ("Click" when
-- unset, "" for none), read at click time. Returns the connections (give them to a Maid) or nil.
function Sound.Attach(button: GuiButton, opts: any?): { RBXScriptConnection }?
	if not button:IsA("GuiButton") or button:GetAttribute("KitSoundWired") == true then
		return nil
	end
	button:SetAttribute("KitSoundWired", true)
	local o: any = opts or {}
	if o.Cue ~= nil and button:GetAttribute("KitSound") == nil then
		button:SetAttribute("KitSound", o.Cue)
	end
	local connections = {}
	if o.NoHover ~= true then
		table.insert(connections, button.MouseEnter:Connect(function()
			if Sound.MouseInput() and usable(button) then
				Sound.Play("Hover")
			end
		end))
		table.insert(connections, button.SelectionGained:Connect(function()
			if usable(button) then
				Sound.Play("Hover")
			end
		end))
	end
	table.insert(connections, button.Activated:Connect(function()
		if not usable(button) then
			return
		end
		local cue = button:GetAttribute("KitSound")
		if cue == "" then
			return
		end
		Sound.Play(type(cue) == "string" and cue or "Click")
	end))
	return connections
end

-- Creates one voice per cue now (loads uploaded assets before their first play).
function Sound.Warm()
	for _, name in ipairs(Config.Order) do
		local cue = Config.Cues[name]
		if cue then
			pcall(voice, name, cue)
		end
	end
end

function Sound.Stats(): any
	return { Played = stats.Played, Throttled = stats.Throttled, Voices = stats.Voices }
end

return Sound
