-- UI sound cues of the kit (Kit.Sound). Pure data: no services, safe to require from tests.
--
-- TO USE REAL AUDIO: upload short UI sounds (Creator Hub > Audio, 0.05-0.6 s, mono) and put the
-- numeric asset ids in `Id` below. While Id is 0 the cue plays `Fallback`, a sound that ships
-- with every Roblox client (rbxasset://sounds/...), so the game clicks even without uploads.
--   Id        uploaded asset id (number); 0 = use Fallback
--   Fallback  rbxasset:// sound bundled with the Roblox client
--   Volume    0..1 before the player's master volume (UI sounds stay quiet)
--   Pitch     PlaybackSpeed of the fallback (an uploaded Id plays at PitchId, default 1)
--   Jitter    random +-PlaybackSpeed so repeated clicks do not sound mechanical
--   Gap       minimum seconds between two plays of this cue (hover: 0.06 s)
--   Voices    Sound instances kept for the cue (overlapping plays)
local CLICK = "rbxasset://sounds/volume_slider.ogg"
local PING = "rbxasset://sounds/electronicpingshort.wav"

local Config = {}

Config.Cues = {
	Hover = { Id = 0, Fallback = CLICK, Volume = 0.1, Pitch = 1.9, Jitter = 0.05, Gap = 0.06, Voices = 2 },
	Click = { Id = 0, Fallback = CLICK, Volume = 0.42, Pitch = 1.25, Jitter = 0.04, Gap = 0.03, Voices = 2 },
	Toggle = { Id = 0, Fallback = CLICK, Volume = 0.36, Pitch = 1.55, Jitter = 0.03, Gap = 0.03, Voices = 1 },
	Tab = { Id = 0, Fallback = CLICK, Volume = 0.3, Pitch = 1.7, Jitter = 0.03, Gap = 0.04, Voices = 1 },
	Open = { Id = 0, Fallback = CLICK, Volume = 0.34, Pitch = 0.95, Jitter = 0.02, Gap = 0.08, Voices = 1 },
	Close = { Id = 0, Fallback = CLICK, Volume = 0.28, Pitch = 0.78, Jitter = 0.02, Gap = 0.08, Voices = 1 },
	Success = { Id = 0, Fallback = PING, Volume = 0.24, Pitch = 1.25, Jitter = 0.02, Gap = 0.12, Voices = 1 },
	Error = { Id = 0, Fallback = CLICK, Volume = 0.42, Pitch = 0.55, Jitter = 0.02, Gap = 0.15, Voices = 1 },
	Coin = { Id = 0, Fallback = PING, Volume = 0.2, Pitch = 1.7, Jitter = 0.06, Gap = 0.08, Voices = 2 },
	Notify = { Id = 0, Fallback = PING, Volume = 0.18, Pitch = 1.0, Jitter = 0.02, Gap = 0.2, Voices = 1 },
}

-- Order of the cues in docs and the Studio demo.
Config.Order = { "Hover", "Click", "Toggle", "Tab", "Open", "Close", "Success", "Error", "Coin", "Notify" }

-- At most this many UI sounds start within one second (a burst of toasts never becomes noise).
Config.MaxPerSecond = 14

-- Player attribute of the in-game setting (false = muted; nil / true = on).
Config.Attribute = "UISounds"

-- SoundGroup the voices play through: SoundService.DOGROTS_AUDIO.<Group> (created on the
-- client when the place has none, so the UI volume has one knob).
Config.Folder = "DOGROTS_AUDIO"
Config.Group = "UI"

-- Asset URL of a cue: the uploaded id when set, else the bundled fallback.
function Config.Url(cue: any): string
	local id = tonumber(cue and cue.Id)
	if id and id > 0 and id == math.floor(id) then
		return "rbxassetid://" .. string.format("%.0f", id)
	end
	return cue and cue.Fallback or CLICK
end

-- PlaybackSpeed of one play: the cue pitch (fallback) or PitchId (uploaded) +- jitter, times mult.
function Config.Speed(cue: any, random: number?, mult: number?): number
	local id = tonumber(cue and cue.Id)
	local base = (id and id > 0) and (cue.PitchId or 1) or (cue.Pitch or 1)
	local jitter = cue.Jitter or 0
	local r = random or 0.5
	return math.clamp((base + (r * 2 - 1) * jitter) * (mult or 1), 0.25, 3)
end

return Config
