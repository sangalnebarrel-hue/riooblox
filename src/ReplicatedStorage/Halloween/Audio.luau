-- Halloween sound effects (ReplicatedStorage.Halloween.Audio), client only.
-- The game ships no uploaded SFX, so every cue is synthesised from the 12 sounds bundled with every Roblox client
-- (rbxasset://sounds/...), re-pitched, sliced, layered and filtered (same row format as Mining.MiningAudio).
-- API
--   Audio.Play(cue, where?, opts?)            where = Vector3 | BasePart | Attachment | nil (2D); opts {Volume, Pitch, Delay}
--   Audio.Loop(cue, where?, opts?) -> handle  handle:Stop(fade?), handle:SetVolume(v, fade?), handle:SetPitch(p)
--   Audio.Has(cue), Audio.Cues (live recipe table), Audio.AssetIds[cue] = uploaded id (0 = recipe)
-- Row = {soundId, volume, speed, fx?, at=, dur=, attack=, fade=, loop=, to=, ramp=, from=}
-- Groups: interactive feedback plays in SoundService.DOGROTS_HalloweenSFX (outside DOGROTS_AUDIO so music ducks never
-- swallow it); ambience beds play in DOGROTS_AUDIO.HalloweenAmbience (ducked with the music by Secret arrivals).
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Audio = {}
Audio.AssetIds = {}
Audio.UploadVolume = .6

local TICK = "rbxasset://sounds/volume_slider.ogg"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local KNOCK = "rbxasset://sounds/collide.wav"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local WIND = "rbxasset://sounds/action_falling.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"
local SPLAT = "rbxasset://sounds/splat.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local SLASH = "rbxasset://sounds/swordslash.wav"
local LUNGE = "rbxasset://sounds/swordlunge.wav"
local SHEATH = "rbxasset://sounds/unsheath.wav"
local HOP = "rbxasset://sounds/action_jump.mp3"
Audio.Sources = { TICK = TICK, PING = PING, KNOCK = KNOCK, LAND = LAND, WIND = WIND, WATER = WATER, SPLAT = SPLAT,
	CLICK = CLICK, SLASH = SLASH, LUNGE = LUNGE, SHEATH = SHEATH, HOP = HOP }

-- FX presets (shared tables; reverb presets become shared tail groups)
local P = {}
P.THUMP = { EqualizerSoundEffect = { LowGain = 10, MidGain = -2, HighGain = -30 }, DistortionSoundEffect = { Level = .45 } }
P.WOODY = { EqualizerSoundEffect = { LowGain = 4, MidGain = 2, HighGain = -14 } }
P.WET = { EqualizerSoundEffect = { LowGain = 6, MidGain = -2, HighGain = -14 } }
P.GOO = { EqualizerSoundEffect = { LowGain = 8, MidGain = -4, HighGain = -20 }, FlangeSoundEffect = { Depth = .4, Mix = .5, Rate = 2 } }
P.BONE = { DistortionSoundEffect = { Level = .6 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 6, HighGain = -8 } }
P.CREAKY = { TremoloSoundEffect = { Depth = 1, Duty = .2, Frequency = 9 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = -6 } }
P.BREATH = { TremoloSoundEffect = { Depth = .85, Duty = .5, Frequency = .35 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 2, HighGain = -10 } }
P.FLUTTER = { TremoloSoundEffect = { Depth = .9, Duty = .45, Frequency = 17 }, EqualizerSoundEffect = { LowGain = -14, MidGain = -2, HighGain = 4 } }
P.CRACKLE = { DistortionSoundEffect = { Level = .85 }, TremoloSoundEffect = { Depth = 1, Duty = .3, Frequency = 17 }, EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = 2 } }
P.STING = { ReverbSoundEffect = { DecayTime = 6, WetLevel = 0, DryLevel = -6, Density = 1, Diffusion = 1 }, EqualizerSoundEffect = { LowGain = 8, MidGain = -2, HighGain = -18 } }
P.TOLL = { ReverbSoundEffect = { DecayTime = 4, WetLevel = -1, DryLevel = -2, Density = 1, Diffusion = 1 }, EqualizerSoundEffect = { LowGain = 6, MidGain = 0, HighGain = -10 } }
P.HOWL = { TremoloSoundEffect = { Depth = .3, Duty = .5, Frequency = 5.5 }, EqualizerSoundEffect = { LowGain = -4, MidGain = 6, HighGain = -12 }, DistortionSoundEffect = { Level = .2 },
	ReverbSoundEffect = { DecayTime = 5, WetLevel = -2, DryLevel = -4, Density = 1, Diffusion = 1 } }
P.CAW = { DistortionSoundEffect = { Level = .9 }, EqualizerSoundEffect = { LowGain = -12, MidGain = 10, HighGain = -2 }, TremoloSoundEffect = { Depth = .6, Duty = .5, Frequency = 20 } }
P.WHISPER = { TremoloSoundEffect = { Depth = 1, Duty = .3, Frequency = 11 }, EqualizerSoundEffect = { LowGain = -20, MidGain = -2, HighGain = 6 }, FlangeSoundEffect = { Depth = .5, Mix = .6, Rate = 2 } }
P.GHOST = { TremoloSoundEffect = { Depth = .35, Duty = .5, Frequency = 5 }, ChorusSoundEffect = { Depth = .45, Mix = .7, Rate = 1.2 }, EqualizerSoundEffect = { LowGain = -2, MidGain = 4, HighGain = -10 },
	ReverbSoundEffect = { DecayTime = 5, WetLevel = -2, DryLevel = -4, Density = 1, Diffusion = 1 } }
P.CHAIN = { EqualizerSoundEffect = { LowGain = -6, MidGain = 4, HighGain = 2 } }
P.GUST = { EqualizerSoundEffect = { LowGain = 4, MidGain = -2, HighGain = -12 }, FlangeSoundEffect = { Depth = .6, Mix = .5, Rate = .12 } }
P.BOOM = { DistortionSoundEffect = { Level = .8 }, EqualizerSoundEffect = { LowGain = 10, MidGain = 0, HighGain = -20 } }
P.SUB = { EqualizerSoundEffect = { LowGain = 10, MidGain = -6, HighGain = -30 } }
P.HALL = { ReverbSoundEffect = { DecayTime = 3.2, WetLevel = -4, DryLevel = -1, Density = 1, Diffusion = 1 } }
P.CRYPT = { ReverbSoundEffect = { DecayTime = 6, WetLevel = 0, DryLevel = -4, Density = 1, Diffusion = 1 } }
P.BRIGHT = { EqualizerSoundEffect = { LowGain = -8, MidGain = 0, HighGain = 4 } }
P.ROAR = { DistortionSoundEffect = { Level = .7 }, EqualizerSoundEffect = { LowGain = 8, MidGain = 2, HighGain = -16 }, TremoloSoundEffect = { Depth = .4, Duty = .5, Frequency = 13 },
	ReverbSoundEffect = { DecayTime = 3, WetLevel = -3, DryLevel = -1, Density = 1, Diffusion = 1 } }
Audio.Presets = P

local function arp(id, vol, base, steps, gap, fx, start)
	local rows = {}
	for i, r in ipairs(steps) do
		table.insert(rows, { id, vol, base * r, fx, at = (start or 0) + (i - 1) * gap })
	end
	return rows
end
local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, row in ipairs(list) do
			table.insert(out, row)
		end
	end
	return out
end
Audio.Arp, Audio.Join = arp, join

-- CUES (recipes owned by WP10a). Group: "SFX" (default, outside DOGROTS_AUDIO: never ducked), "Ambience" (ducked with the
-- island's music), "UI". Loop cues (Loop = true) are played with Audio.Loop: every row loops, at/dur are ignored.
-- 3D rows: near/far = RollOffMin/MaxDistance (InverseTapered); spatial(rows, near, far) fills them in.
-- Timbres are built from the 12 built-in sounds only (pitch, slicing, layering, EQ/tremolo/flange/chorus/distortion and
-- shared reverb tails); exact values are starting points to tune by ear in Studio.
local C = {}
Audio.Cues = C
local function spatial(rows, near: number, far: number)
	for _, r in ipairs(rows) do
		r.near = r.near or near
		r.far = r.far or far
	end
	return rows
end
local function chains(n: number, gap: number, vol: number)
	local r = {}
	for i = 0, n - 1 do
		table.insert(r, { SHEATH, vol + (i % 3) * .03, 1.5 + (i % 4) * .18, P.CHAIN, at = i * gap, dur = .14, fade = .08 })
	end
	return r
end
P.MUFFLED = { EqualizerSoundEffect = { LowGain = 6, MidGain = -6, HighGain = -26 } }
P.HOOT = { TremoloSoundEffect = { Depth = .35, Duty = .5, Frequency = 7 }, EqualizerSoundEffect = { LowGain = 2, MidGain = 2, HighGain = -14 },
	ReverbSoundEffect = { DecayTime = 3.2, WetLevel = -4, DryLevel = -1, Density = 1, Diffusion = 1 } }
P.CRACK = { DistortionSoundEffect = { Level = .9 }, EqualizerSoundEffect = { LowGain = 2, MidGain = 6, HighGain = -4 } }

-- UI (2D) ------------------------------------------------------------------------------------------------------------
C.UiOpen = { Group = "UI", Rows = arp(PING, .1, 1.2, { 1, 1.26, 1.5 }, .045, P.BRIGHT) }
C.UiTab = { Group = "UI", Rows = { { TICK, .25, 1.5 } } }
C.CandyTick = { Group = "UI", Rows = { { PING, .07, 2.4, P.BRIGHT }, { TICK, .12, 2.2, nil, at = .01 } }, Jitter = .08 }
C.CandyBig = { Group = "UI", Rows = join(arp(PING, .1, 1.6, { 1, 1.26, 1.5, 2 }, .05, P.BRIGHT), { { HOP, .2, 1.4, nil, at = .02 } }) }
C.QuestDone = { Group = "UI", Rows = join(arp(PING, .12, 1, { 1, 1.26, 1.5, 2, 2.52 }, .07, P.HALL), { { LAND, .25, .7, P.SUB } }) }
C.Unlock = { Group = "UI", Rows = join(arp(PING, .12, .8, { 1, 1.5, 2, 3 }, .09, P.HALL), { { SHEATH, .2, .8, nil, at = .05 } }) }
C.Deny = { Group = "UI", Rows = { { PING, .12, .55, P.WOODY }, { PING, .1, .5, P.WOODY, at = .09 } } }
C.Claim = { Group = "UI", Rows = join(arp(PING, .1, 1.3, { 1, 1.26, 1.5, 2 }, .06, P.BRIGHT), { { WATER, .12, 1.8, P.WET, at = .05, dur = .3 } }) }
C.RushTick = { Group = "UI", Rows = { { TICK, .1, 1.8 }, { PING, .03, 2.2, P.BRIGHT } } }

-- The gate, lanterns, chains -------------------------------------------------------------------------------------------
C.GateCreak = { Rows = spatial({ { TICK, .14, .32, P.CREAKY, loop = true, attack = .3, dur = 2.6, fade = .6, to = .26, ramp = 2.4 },
	{ TICK, .06, .5, P.CREAKY, at = .9, loop = true, attack = .2, dur = 1.4, fade = .5, to = .42, ramp = 1.2 },
	{ KNOCK, .35, .45, P.WOODY, at = 2.3 }, { LAND, .3, .35, P.SUB, at = 2.35 } }, 18, 220) }
C.GateChain = { Rows = spatial(join(chains(7, .075, .09), { { CLICK, .14, .6, P.BONE, at = .1 }, { KNOCK, .12, 1.8, nil, at = .5 } }), 14, 160) }
C.LanternFlare = { Rows = spatial({ { WIND, .14, 1.9, P.GUST, dur = .45, attack = .05, fade = .3 }, { PING, .05, .8, P.TOLL, at = .05 },
	{ TICK, .03, .9, P.CRACKLE, at = .02, dur = .5, fade = .3, loop = true } }, 12, 120) }
C.ChainRattle = { Rows = spatial(join(chains(6, .07, .08), { { CLICK, .1, .6, P.BONE, at = .05 }, { KNOCK, .06, 1.6, P.CHAIN, at = .46 } }), 8, 90) }

-- Night life ---------------------------------------------------------------------------------------------------------
-- wolf howl: rise -> long fall + a quieter fifth above (pack chorus) + breath; heard from far away (cliffs / void)
C.Howl = { Group = "Ambience", Rows = spatial({ { PING, .14, .42, P.HOWL, loop = true, attack = .35, dur = 1.0, fade = .3, to = .58, ramp = .7 },
	{ PING, .14, .58, P.HOWL, at = .8, loop = true, attack = .2, dur = 1.8, fade = 1.0, to = .4, ramp = 1.6 },
	{ PING, .05, .86, P.HOWL, at = .95, loop = true, attack = .3, dur = 1.5, fade = .9, to = .62, ramp = 1.4 },
	{ WIND, .05, 1.4, P.BREATH, loop = true, attack = .4, dur = 2.4, fade = 1 } }, 60, 650) }
C.CrowCaw = { Group = "Ambience", Rows = spatial({ { HOP, .2, 1.25, P.CAW, to = 1.05, ramp = .2, dur = .28, fade = .1 },
	{ HOP, .17, 1.19, P.CAW, at = .38, to = 1.0, ramp = .2, dur = .26, fade = .1 }, { HOP, .12, 1.3, P.CAW, at = .76, to = 1.08, ramp = .2, dur = .22, fade = .1 } }, 10, 140), Jitter = .06 }
C.Whisper = { Group = "Ambience", Rows = spatial({ { WIND, .05, 2.8, P.WHISPER, loop = true, attack = .25, dur = 1.1, fade = .45, to = 2.4, ramp = 1.1 },
	{ SLASH, .04, .45, P.GUST, at = .2 }, { WIND, .03, 3.2, P.WHISPER, at = .55, loop = true, attack = .2, dur = .8, fade = .4, to = 2.9, ramp = .8 } }, 3, 28), Jitter = .08 }
C.GhostWoo = { Group = "Ambience", Rows = spatial({ { PING, .11, .5, P.GHOST, loop = true, attack = .6, dur = 3, fade = 1.2, to = .62, ramp = 1.4 },
	{ PING, .04, .75, P.GHOST, at = .4, loop = true, attack = .7, dur = 2.4, fade = 1.1, to = .93, ramp = 1.2 } }, 12, 100) }
C.CoffinKnock = { Group = "Ambience", Rows = spatial({ { KNOCK, .35, .55, P.MUFFLED }, { KNOCK, .3, .52, P.MUFFLED, at = .28 },
	{ KNOCK, .38, .5, P.MUFFLED, at = .56 }, { LAND, .15, .6, P.SUB, at = .62 } }, 6, 60), Jitter = .05 }
C.Owl = { Group = "Ambience", Rows = spatial({ { PING, .09, .62, P.HOOT, loop = true, dur = .45, attack = .05, fade = .2, to = .58, ramp = .4 },
	{ PING, .08, .6, P.HOOT, at = .62, loop = true, dur = .75, attack = .06, fade = .35, to = .54, ramp = .7 } }, 20, 260), Jitter = .04 }
C.Bats = { Group = "Ambience", Rows = spatial({ { WIND, .06, 2.4, P.FLUTTER, loop = true, attack = .05, dur = .5, fade = .3 },
	{ WIND, .04, 2.7, P.FLUTTER, at = .18, loop = true, attack = .05, dur = .45, fade = .3 }, { HOP, .04, 2.6, P.CAW, at = .1, dur = .08 } }, 8, 90), Jitter = .1 }

-- Beds (Audio.Loop) ------------------------------------------------------------------------------------------------------
C.WindBed = { Group = "Ambience", Loop = true, Rows = { { WIND, .07, .5, P.GUST, loop = true }, { WIND, .018, 1.6, { EqualizerSoundEffect = { LowGain = -20, MidGain = -6, HighGain = 6 } }, loop = true } } }
C.GraveAmbience = { Group = "Ambience", Loop = true, Rows = spatial({ { WIND, .05, .42, P.GUST, loop = true },
	{ TICK, .03, .14, { FlangeSoundEffect = { Depth = 1, Mix = 1, Rate = .6 } }, loop = true } }, 25, 110) }
C.FireCrackle = { Group = "Ambience", Loop = true, Rows = spatial({ { TICK, .025, .9, P.CRACKLE, loop = true }, { WIND, .02, .35, P.SUB, loop = true } }, 6, 45) }
C.CauldronBubbles = { Group = "Ambience", Loop = true, Rows = spatial({ { WATER, .05, .45, P.GOO, loop = true }, { WATER, .025, .8, P.WET, loop = true } }, 8, 60) }
C.RedRain = { Group = "Ambience", Loop = true, Rows = { { WIND, .06, 2.2, { EqualizerSoundEffect = { LowGain = -14, MidGain = 0, HighGain = 4 } }, loop = true }, { WATER, .03, 3.2, P.BRIGHT, loop = true } } }
C.BloodMoonAmbience = { Group = "Ambience", Loop = true, Rows = { { WIND, .05, .28, P.SUB, loop = true },
	{ TICK, .025, .12, { FlangeSoundEffect = { Depth = 1, Mix = 1, Rate = .35 }, EqualizerSoundEffect = { LowGain = 4, MidGain = 0, HighGain = -10 } }, loop = true } } }
C.CurseWhisper = { Group = "Ambience", Loop = true, Rows = { { WIND, .04, 2.6, P.WHISPER, loop = true }, { TICK, .02, .3, P.BREATH, loop = true } } }

-- The cauldron, candy, pumpkins -------------------------------------------------------------------------------------------
C.CauldronSplash = { Rows = spatial({ { WATER, .35, .7, P.WET }, { SPLAT, .25, .6, P.GOO, at = .04 }, { WATER, .2, 1.2, P.WET, at = .12, dur = .4 } }, 12, 120) }
C.CauldronFlash = { Rows = spatial(join({ { LAND, .7, .3, P.STING }, { WIND, .4, .8, P.GUST, dur = .9, attack = .05, fade = .6 } },
	arp(PING, .12, .9, { 1, 1.19, 1.5, 2 }, .06, P.HALL, .05)), 20, 220) }
C.CauldronLevelUp = { Rows = spatial(join(arp(PING, .14, .7, { 1, 1.26, 1.5, 2, 2.52, 3 }, .09, P.TOLL), { { WATER, .3, .6, P.GOO }, { LAND, .4, .4, P.SUB, at = .1 } }), 20, 220) }
C.CandyDrop = { Rows = spatial({ { CLICK, .2, 1.8, nil }, { WATER, .14, 2.2, P.WET, at = .1, dur = .25 } }, 10, 90), Jitter = .1 }
C.BlockPop = { Rows = spatial({ { LAND, .5, .7, P.THUMP }, { HOP, .3, .8 }, { PING, .1, 1.5, P.HALL, at = .05 } }, 12, 140) }
C.PumpkinShake = { Rows = spatial({ { KNOCK, .3, .9, P.WOODY }, { CLICK, .15, .7, P.BONE, at = .03 } }, 10, 110), Jitter = .08 }
C.PumpkinCrack = { Rows = spatial({ { KNOCK, .45, .75, P.WOODY }, { LAND, .25, .9, P.THUMP }, { CLICK, .22, .6, P.BONE, at = .02 },
	{ CLICK, .18, .7, P.BONE, at = .07 }, { CLICK, .16, .65, P.BONE, at = .12 }, { SPLAT, .16, .85, P.WET, at = .05 } }, 10, 120) }
C.PumpkinBurst = { Rows = spatial({ { KNOCK, .6, .6, P.WOODY }, { LAND, .6, .5, P.BOOM }, { SPLAT, .45, .85, P.WET, at = .05 },
	{ WATER, .3, 1.1, P.WET, at = .06 }, { WIND, .35, .9, P.GUST, at = .02, dur = .8, fade = .5 } }, 12, 150) }

-- The bell, the Blood Moon, weather ---------------------------------------------------------------------------------------
C.BellToll = { Rows = spatial({ { PING, .32, .5, P.TOLL }, { PING, .16, .25, P.TOLL, at = .01 }, { PING, .06, 1.0, P.TOLL, at = .015 },
	{ LAND, .25, .5, P.THUMP } }, 30, 420) }
C.Heartbeat = { Rows = { { LAND, .55, .42, P.THUMP }, { LAND, .38, .42, P.THUMP, at = .18 } } }
C.Thunder = { Rows = { { LAND, .85, .22, P.STING }, { SLASH, .18, .45, P.CRACK, dur = .35, fade = .2 },
	{ WIND, .5, .35, { EqualizerSoundEffect = { LowGain = 10, MidGain = -4, HighGain = -20 } }, dur = 2.4, fade = 1.6 },
	{ WIND, .32, .26, P.SUB, at = .3, dur = 3, attack = .3, fade = 2 }, { KNOCK, .4, .5, { DistortionSoundEffect = { Level = .7 } } } }, Jitter = .06 }
C.BloodMoonWarn = { Rows = { { LAND, .6, .24, P.STING }, { PING, .14, .5, P.TOLL, at = .1 }, { PING, .1, .53, P.TOLL, at = .1 },
	{ WIND, .25, .35, P.SUB, loop = true, attack = 1, dur = 3, fade = 1.5, to = .42, ramp = 3 } } }
C.BloodMoonRise = { Rows = join({ { LAND, .8, .2, P.STING }, { WIND, .45, .3, P.SUB, dur = 4, attack = 1.5, fade = 2, loop = true, to = .45, ramp = 4 },
	{ PING, .1, .5, P.GHOST, at = .2, loop = true, attack = 1.2, dur = 3.6, fade = 1.6, to = .53, ramp = 3 } }, arp(PING, .16, .5, { 1, 1.19, 1.41 }, .5, P.TOLL, .3)) }
C.BloodMoonEnd = { Rows = join(arp(PING, .12, .7, { 1.41, 1.19, 1 }, .45, P.TOLL), { { WIND, .3, .5, P.GUST, dur = 2.5, fade = 1.8 } }) }

-- THE GRAVEKEEPER (heard across the whole pit and from the rim) ---------------------------------------------------------
C.BossRoar = { Rows = spatial({ { WIND, .6, .28, P.ROAR, dur = 2.2, attack = .2, fade = 1, to = .22, ramp = 2 }, { LAND, .8, .25, P.BOOM },
	{ PING, .2, .3, P.ROAR, dur = 1.8, loop = true, attack = .15, fade = .9, to = .24, ramp = 1.6 }, { LUNGE, .25, .3, P.ROAR, at = .05, dur = 1.2, fade = .6 } }, 30, 330) }
C.BossSlam = { Rows = spatial({ { LAND, 1, .3, P.BOOM }, { KNOCK, .7, .35, P.BOOM, at = .02 }, { WIND, .45, .5, P.SUB, dur = 1.2, fade = .9 },
	{ CLICK, .2, .45, P.BONE, at = .06 } }, 25, 300) }
C.BossBurrow = { Rows = spatial({ { WIND, .5, .3, P.SUB, dur = 2, attack = .2, fade = 1.2, loop = true }, { KNOCK, .5, .4, P.WOODY, at = .2 },
	{ KNOCK, .4, .35, P.WOODY, at = .6 }, { LAND, .6, .3, P.BOOM, at = 1.0 } }, 25, 300) }
C.BossEmerge = { Rows = spatial({ { LAND, .85, .22, P.STING }, { KNOCK, .65, .3, P.BOOM }, { WIND, .5, .4, P.GUST, dur = 1.6, fade = 1 },
	{ SPLAT, .3, .4, P.WET, at = .05 }, { CLICK, .25, .5, P.BONE, at = .1 } }, 30, 330) }
C.BossStep = { Rows = spatial({ { LAND, .55, .35, P.THUMP }, { KNOCK, .2, .4, P.WOODY, at = .02 } }, 20, 200), Jitter = .06 }
C.BossDeath = { Rows = spatial(join({ { LAND, .9, .2, P.STING }, { WIND, .5, .3, P.ROAR, dur = 3.5, attack = .1, fade = 2.4, to = .15, ramp = 3.2 },
	{ CLICK, .2, .5, P.BONE, at = 1.2 }, { CLICK, .18, .7, P.BONE, at = 1.35 }, { KNOCK, .35, .4, P.BONE, at = 1.5 } },
	arp(PING, .11, .6, { 2, 1.5, 1.26, 1 }, .25, P.TOLL, .4)), 40, 400) }
C.BossEnrage = { Rows = spatial({ { WIND, .6, .4, P.ROAR, dur = 1.6, attack = .1, fade = .8, to = .55, ramp = 1.2 }, { LAND, .8, .3, P.BOOM },
	{ PING, .2, .35, P.STING, at = .2 }, { PING, .1, .495, P.STING, at = .2 } }, 30, 360) }
C.RockWhistle = { Rows = spatial({ { WIND, .25, 2.6, P.BRIGHT, dur = 1.4, attack = .2, fade = .2, loop = true, to = 1.4, ramp = 1.3 } }, 20, 220) }
C.RockImpact = { Rows = spatial({ { LAND, .8, .35, P.BOOM }, { KNOCK, .5, .5, P.WOODY, at = .02 }, { CLICK, .2, .5, P.BONE, at = .05 } }, 15, 220), Jitter = .06 }
C.SkeletonRattle = { Rows = spatial((function()
	local r = {}
	for i = 0, 5 do
		table.insert(r, { CLICK, .12, .9 + (i % 3) * .2, P.BONE, at = i * .05 })
	end
	return r
end)(), 10, 120), Jitter = .1 }
C.SkeletonBreak = { Rows = spatial({ { KNOCK, .45, .9, P.BONE }, { CLICK, .25, .7, P.BONE, at = .02 }, { CLICK, .2, 1.1, P.BONE, at = .07 },
	{ HOP, .15, .6, nil, at = .04 } }, 10, 140) }
C.WeakPointHit = { Rows = spatial({ { LAND, .6, .5, P.BOOM }, { PING, .2, 1.4, P.HALL, at = .02 }, { SHEATH, .25, .7, nil, at = .01 } }, 20, 250) }
C.ArmorBreak = { Rows = spatial({ { KNOCK, .8, .4, P.BOOM }, { LAND, .7, .35, P.STING, at = .03 }, { SHEATH, .35, .5, nil, at = .05 },
	{ CLICK, .3, .4, P.BONE, at = .08 } }, 20, 260) }
-- polish pass (P3a): hit reactions, crack stages, weak points, the bell summon and the staged death
-- pained bony grunt on crits / weak-point hits (rate-limited by BossFX)
C.BossHurt = { Rows = spatial({ { WIND, .35, .55, P.ROAR, dur = .55, attack = .03, fade = .35, to = .42, ramp = .5 }, { KNOCK, .3, .55, P.BONE },
	{ CLICK, .18, .6, P.BONE, at = .03 } }, 25, 280), Jitter = .06 }
-- a stone plate cracks a stage further (BossFX lowers the pitch per stage)
C.PlateCrack = { Rows = spatial({ { KNOCK, .45, .55, P.BOOM }, { CLICK, .25, .45, P.CRACK, at = .01 }, { CLICK, .18, .7, P.CRACK, at = .06 },
	{ SLASH, .1, .5, P.CRACK, at = .02, dur = .25, fade = .15 } }, 18, 220), Jitter = .05 }
-- weak points open: a rising gold chime over a sub thump
C.WeakOpen = { Rows = spatial(join(arp(PING, .12, 1.2, { 1, 1.26, 1.5 }, .06, P.HALL), { { LAND, .4, .45, P.SUB },
	{ WIND, .2, 1.6, P.GUST, dur = .6, fade = .4 } }), 25, 300) }
-- the grave bell's yoke creaks as it swings; stone cracking its way from the bell to the pit
C.BellCreak = { Rows = spatial({ { TICK, .12, .38, P.CREAKY, loop = true, attack = .1, dur = .8, fade = .3, to = .3, ramp = .7 },
	{ KNOCK, .2, .5, P.WOODY, at = .05 }, { TICK, .08, .45, P.CREAKY, at = .9, loop = true, attack = .1, dur = .6, fade = .3, to = .36, ramp = .5 } }, 14, 180) }
C.GroundCrack = { Rows = spatial({ { LAND, .35, .4, P.SUB }, { CLICK, .14, .55, P.CRACK }, { CLICK, .12, .7, P.CRACK, at = .07 },
	{ CLICK, .1, .5, P.CRACK, at = .15 }, { KNOCK, .2, .6, P.BONE, at = .1 }, { SLASH, .08, .4, P.CRACK, at = .02, dur = .3, fade = .2 } }, 20, 260), Jitter = .06 }
-- the killing blow: a hard sting + crack, a bell-like ring and a long sub tail
C.KillBlow = { Rows = spatial({ { LAND, .9, .2, P.STING }, { KNOCK, .7, .28, P.BOOM, at = .01 }, { SLASH, .3, .35, P.CRACK, dur = .4, fade = .3 },
	{ PING, .14, .35, P.TOLL, at = .02 }, { WIND, .4, .25, P.SUB, dur = 1.6, fade = 1.2 } }, 40, 450) }
-- the soul tears out of the ribcage: a rising ghost whoosh + chime over a sub drop
C.SoulBurst = { Rows = spatial(join({ { WIND, .45, 1.1, P.GUST, dur = 1.4, attack = .05, fade = 1, to = 1.6, ramp = 1.2 },
	{ PING, .16, .75, P.GHOST, loop = true, dur = 2.2, attack = .1, fade = 1.4, to = 1.1, ramp = 2 }, { LAND, .5, .3, P.SUB } },
	arp(PING, .12, 1, { 1, 1.26, 1.5, 2 }, .09, P.HALL, .1)), 40, 450) }
-- bones raining down and clattering over the arena floor
C.BoneScatter = { Rows = spatial((function()
	local r = { { KNOCK, .3, .7, P.BONE }, { HOP, .12, .5, nil, at = .02 } }
	for i = 0, 5 do
		table.insert(r, { CLICK, .13 - (i % 2) * .03, .6 + (i % 3) * .22, P.BONE, at = .18 + i * .11 })
	end
	return r
end)(), 20, 260) }
-- the soul reaches the moon: a shimmering choir swell (2D, it fills the sky)
C.MoonFlare = { Rows = join({ { PING, .12, 1.0, P.GHOST, loop = true, dur = 2.6, attack = .4, fade = 1.6, to = 1.5, ramp = 2.4 },
	{ PING, .09, 1.5, P.GHOST, at = .15, loop = true, dur = 2.4, attack = .4, fade = 1.5, to = 2.0, ramp = 2.2 },
	{ WIND, .2, 1.8, P.GUST, dur = 2, attack = .3, fade = 1.4 } }, arp(PING, .08, 2, { 1, 1.5, 2, 3 }, .12, P.HALL, .2)) }

-- Digging / finds ------------------------------------------------------------------------------------------------------
C.DigSoil = { Rows = spatial({ { LAND, .35, .8, P.WOODY }, { KNOCK, .15, 1.2, nil, at = .02 } }, 10, 110), Jitter = .08 }
C.DigBone = { Rows = spatial({ { CLICK, .3, .8, P.BONE }, { KNOCK, .25, 1.1, P.BONE, at = .03 }, { LAND, .2, .9, P.WOODY } }, 10, 110), Jitter = .08 }
C.DigPumpkin = { Rows = spatial({ { KNOCK, .35, .8, P.WOODY }, { SPLAT, .2, 1.1, P.WET, at = .03 } }, 10, 110), Jitter = .08 }
C.DigGhost = { Rows = spatial({ { PING, .08, .7, P.GHOST, dur = 1, attack = .1, fade = .6, loop = true, to = .9, ramp = .8 }, { LAND, .25, .9, P.WOODY } }, 10, 120) }
C.DigCursed = { Rows = spatial({ { LAND, .4, .5, P.BOOM }, { WIND, .2, .6, P.WHISPER, dur = .8, fade = .5, loop = true },
	{ PING, .06, .47, P.STING, at = .05 } }, 10, 140) }
C.TreasureReveal = { Rows = spatial(join(arp(PING, .16, 1, { 1, 1.26, 1.5, 2, 2.52, 3 }, .07, P.HALL), { { LAND, .5, .45, P.STING }, { SHEATH, .3, .9, nil, at = .1 } }), 15, 220) }
C.RareFind = { Rows = join(arp(PING, .14, 1.2, { 1, 1.26, 1.5, 2 }, .06, P.HALL), { { LAND, .35, .6, P.SUB } }) }
C.OreBreak = { Rows = spatial({ { KNOCK, .6, .55, P.BOOM }, { LAND, .5, .45, P.THUMP }, { CLICK, .2, .7, P.BONE, at = .04 } }, 12, 140) }

-- Trick-or-treat houses ---------------------------------------------------------------------------------------------------
C.DoorCreak = { Rows = spatial({ { TICK, .12, .4, P.CREAKY, loop = true, attack = .2, dur = 1.3, fade = .3, to = .3, ramp = 1.2 } }, 10, 110) }
C.DoorKnock = { Rows = spatial({ { KNOCK, .4, .85, P.WOODY }, { KNOCK, .38, .85, P.WOODY, at = .22 }, { KNOCK, .42, .82, P.WOODY, at = .44 } }, 10, 110) }
C.DoorSlam = { Rows = spatial({ { KNOCK, .7, .5, P.WOODY }, { LAND, .6, .4, P.THUMP } }, 12, 140) }
-- the one allowed scare (house TRICK only): short (0.6 s), loud but not piercing
C.Jumpscare = { Rows = { { WIND, .55, 1.8, P.ROAR, dur = .6, attack = .01, fade = .35 }, { PING, .26, 2.6, { DistortionSoundEffect = { Level = .9 } }, dur = .5, loop = true, to = 1.6, ramp = .45 },
	{ LAND, .7, .4, P.BOOM } } }
C.Cackle = { Rows = spatial((function()
	local r = {}
	for i = 1, 5 do
		table.insert(r, { HOP, .18, 1.9 - .1 * i, { DistortionSoundEffect = { Level = .6 }, EqualizerSoundEffect = { LowGain = -10, MidGain = 8, HighGain = 0 } }, at = .11 * i, dur = .12 })
	end
	return r
end)(), 12, 120) }

-- Curse, rush, exorcism, misc -------------------------------------------------------------------------------------------
C.CurseMax = { Rows = { { LAND, .6, .25, P.STING }, { WIND, .3, 2.2, P.WHISPER, dur = 2, attack = .4, fade = 1.2, loop = true } } }
C.RushStart = { Rows = join(arp(PING, .14, 1, { 1, 1.26, 1.5, 2, 2.52, 3, 4 }, .05, P.BRIGHT), { { WIND, .3, 1.4, P.GUST, dur = .7, fade = .4 } }) }
C.ExorcismPulse = { Rows = { { PING, .1, .9, P.HALL }, { PING, .07, 1.35, P.HALL, at = .05 } } }
C.ExorcismMilestone = { Rows = join(arp(PING, .16, .8, { 1, 1.26, 1.5, 2, 2.52 }, .1, P.TOLL), { { LAND, .6, .3, P.STING } }) }
C.Sparkle = { Rows = arp(PING, .06, 2, { 1, 1.5, 2 }, .04, P.BRIGHT), Jitter = .1 }
C.Teleport = { Rows = { { WIND, .3, 1.6, P.GUST, dur = .8, attack = .1, fade = .5 }, { PING, .1, 1.2, P.HALL } } }
-- polish pass (P3b): the reward card, the brew finale, the exorcism milestone
C.RewardOpen = { Group = "UI", Rows = join({ { WIND, .22, 1.5, P.GUST, dur = .6, attack = .05, fade = .4 } }, arp(PING, .1, .9, { 1, 1.5, 2 }, .07, P.HALL, .12)) }
C.RewardSecret = { Group = "UI", Rows = join({ { LAND, .3, .3, P.STING } }, arp(PING, .06, 1, { 1, 1.26, 1.5, 2, 2.52, 3, 4 }, .06, P.HALL, .05),
	{ { WIND, .12, 2.4, P.WHISPER, dur = 1.2, attack = .2, fade = .8, loop = true } }) }
C.BrewRise = { Rows = spatial(join({ { WATER, .2, .45, P.GOO, loop = true, dur = 2.6, attack = 1.5, fade = .4, to = .75, ramp = 2.4 },
	{ WIND, .25, .4, P.SUB, loop = true, dur = 2.4, attack = 1.6, fade = .5 } }, arp(PING, .1, .7, { 1, 1.26, 1.5, 2 }, .12, P.TOLL, 1.7)), 16, 180) }
C.SoulRise = { Rows = { { PING, .12, .6, P.GHOST, loop = true, dur = 2.2, attack = .4, fade = .9, to = 1.4, ramp = 2 },
	{ WIND, .22, 1.2, P.WHISPER, loop = true, dur = 1.8, attack = .3, fade = 1 }, { LAND, .4, .35, P.STING, at = 1.6 } } }

-- MIX --------------------------------------------------------------------------------------------------------------
local groups = {}
local function namedGroup(name: string, parent: Instance, volume: number, compress: boolean): SoundGroup
	local g = groups[name]
	if g and g.Parent then
		return g
	end
	g = parent:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = volume
		if compress then
			local c = Instance.new("CompressorSoundEffect")
			c.Threshold = -16
			c.Ratio = 3
			c.Attack = .005
			c.Release = .15
			c.GainMakeup = 2
			c.Parent = g
		end
		g.Parent = parent
	end
	groups[name] = g
	return g
end
local function audioFolder(): Instance
	local f = SoundService:FindFirstChild("DOGROTS_AUDIO")
	if not f then
		f = Instance.new("Folder")
		f.Name = "DOGROTS_AUDIO"
		f.Parent = SoundService
	end
	return f
end
function Audio.Group(kind: string?): SoundGroup
	if kind == "Ambience" then
		return namedGroup("HalloweenAmbience", audioFolder(), .8, false)
	elseif kind == "Music" then
		return namedGroup("Halloween", audioFolder(), .7, true)
	elseif kind == "UI" then
		return namedGroup("DOGROTS_HalloweenUI", SoundService, .9, false)
	end
	return namedGroup("DOGROTS_HalloweenSFX", SoundService, 1, true)
end

local tails = {}
local tailKeys = setmetatable({}, { __mode = "k" })
local function tailGroup(parentGroup: SoundGroup, props)
	local key = tailKeys[props]
	if not key then
		local names = {}
		for k in pairs(props) do
			table.insert(names, k)
		end
		table.sort(names)
		local parts = {}
		for _, k in ipairs(names) do
			table.insert(parts, k .. "=" .. tostring(props[k]))
		end
		key = table.concat(parts, ",")
		tailKeys[props] = key
	end
	local id = parentGroup.Name .. "|" .. key
	local t = tails[id]
	if t and t.Parent == parentGroup then
		return t
	end
	t = Instance.new("SoundGroup")
	t.Name = "HalloweenTail"
	t.Volume = 1
	local r = Instance.new("ReverbSoundEffect")
	for k, v in pairs(props) do
		(r :: any)[k] = v
	end
	r.Parent = t
	t.Parent = parentGroup
	tails[id] = t
	return t
end
local function dress(s: Sound, fx, group: SoundGroup)
	local into = nil
	for class, props in pairs(fx or {}) do
		if class == "ReverbSoundEffect" then
			into = tailGroup(group, props)
		else
			local e = Instance.new(class)
			for key, v in pairs(props) do
				(e :: any)[key] = v
			end
			e.Parent = s
		end
	end
	s.SoundGroup = into or group
end

-- where -> a parent instance (Vector3 positions get a pooled invisible anchor part, client-local)
local anchorFolder = nil
local function anchorAt(pos: Vector3, life: number): BasePart
	if not anchorFolder or not anchorFolder.Parent then
		anchorFolder = Instance.new("Folder")
		anchorFolder.Name = "DOGROTS_HalloweenAudio"
		anchorFolder.Parent = workspace
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(.2, .2, .2)
	p.CFrame = CFrame.new(pos)
	p.Parent = anchorFolder
	Debris:AddItem(p, life)
	return p
end

-- voice caps: one-shot rows (+4 for a cue's first row) and looped bed rows count separately, so the ambience beds held
-- in the yard (up to ~14 rows) never starve the one-shot SFX
local CAP, LOOP_CAP = 22, 18
local live, liveLoop = 0, 0
local warned = {}
local function shot(row, k, p, parent, group, first, loopHandle)
	if loopHandle then
		if liveLoop >= LOOP_CAP then
			return nil
		end
	elseif live >= CAP + (first and 4 or 0) then
		return nil
	end
	if parent and not parent.Parent then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "HalloweenCue"
	s.SoundId = row[1]
	local volume = math.clamp(row[2] * k, 0, 2)
	s.Volume = row.attack and 0 or volume
	s.PlaybackSpeed = math.clamp(row[3] * p, .05, 8)
	s.Looped = row.loop == true
	if row.from then
		s.TimePosition = row.from
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = row.near or 12
	s.RollOffMaxDistance = row.far or 140
	dress(s, row[4], group)
	s.Parent = parent or SoundService
	if loopHandle then
		liveLoop += 1
	else
		live += 1
	end
	local done = false
	local function finish()
		if not done then
			done = true
			if loopHandle then
				liveLoop = math.max(0, liveLoop - 1)
			else
				live = math.max(0, live - 1)
			end
		end
	end
	s.Destroying:Once(finish)
	s.Ended:Once(function()
		finish()
		s:Destroy()
	end)
	s:Play()
	if row.attack then
		TweenService:Create(s, TweenInfo.new(row.attack, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = volume }):Play()
	end
	if row.to then
		TweenService:Create(s, TweenInfo.new(row.ramp or row.dur or .25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ PlaybackSpeed = math.clamp(row.to * p, .05, 8) }):Play()
	end
	if loopHandle then
		table.insert(loopHandle.Sounds, { Sound = s, Base = volume, Speed = row[3] })
		return s
	end
	if row.dur then
		local fade = row.fade or .06
		task.delay(math.max(0, row.dur - fade), function()
			if not s.Parent then
				return
			end
			TweenService:Create(s, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 }):Play()
			task.delay(fade + .02, function()
				finish()
				s:Destroy()
			end)
		end)
		Debris:AddItem(s, row.dur + 1)
		task.delay(row.dur + 1.2, finish)
	else
		Debris:AddItem(s, 8)
		task.delay(8.2, finish)
	end
	return s
end

local function resolve(where, life): Instance?
	if typeof(where) == "Vector3" then
		return anchorAt(where, life)
	elseif typeof(where) == "Instance" then
		return where
	end
	return nil
end

function Audio.Has(cue: string): boolean
	return C[cue] ~= nil
end

local function cueOf(name: string)
	local c = C[name]
	if not c and not warned[name] then
		warned[name] = true
		warn("Halloween Audio: unknown cue " .. tostring(name))
	end
	return c
end

local function uploaded(name: string)
	local id = Audio.AssetIds[name]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. id
	elseif type(id) == "string" and id ~= "" and id ~= "0" then
		return id
	end
	return nil
end

-- the base game's "UI SOUNDS: OFF" setting (Kit.Sound: player attribute UISounds == false) silences our UI cues too
local function uiSoundsOff(): boolean
	local player = Players and Players.LocalPlayer
	return player ~= nil and player:GetAttribute("UISounds") == false
end

function Audio.Play(name: string, where: any?, opts: { [string]: any }?)
	local ok, err = pcall(function()
		local cue = cueOf(name)
		if not cue or (cue.Group == "UI" and uiSoundsOff()) then
			return
		end
		opts = opts or {}
		local k = (opts.Volume or 1) * (cue.Volume or 1)
		local jitterAmt = cue.Jitter or .03
		local p = (opts.Pitch or 1) * (1 + (math.random() * 2 - 1) * jitterAmt)
		local group = Audio.Group(cue.Group)
		local function go()
			local longest = 0
			for _, row in ipairs(cue.Rows) do
				longest = math.max(longest, (row.at or 0) + (row.dur or 6))
			end
			local parent = resolve(where, longest + 2)
			local up = uploaded(name)
			if up then
				shot({ up, Audio.UploadVolume, 1 }, k, opts.Pitch or 1, parent, group, true)
				return
			end
			for i, row in ipairs(cue.Rows) do
				if row.at and row.at > 0 then
					task.delay(row.at, shot, row, k, p, parent, group, i == 1)
				else
					shot(row, k, p, parent, group, i == 1)
				end
			end
		end
		if opts.Delay and opts.Delay > 0 then
			task.delay(opts.Delay, go)
		else
			go()
		end
	end)
	if not ok and not warned["!" .. name] then
		warned["!" .. name] = true
		warn("Halloween Audio failed (" .. tostring(name) .. "): " .. tostring(err))
	end
end

-- looping beds: every row plays looped until handle:Stop(fade)
function Audio.Loop(name: string, where: any?, opts: { [string]: any }?)
	local handle = { Sounds = {}, Alive = true, Gain = 1 }
	local ok, err = pcall(function()
		local cue = cueOf(name)
		if not cue then
			return
		end
		opts = opts or {}
		local k = (opts.Volume or 1) * (cue.Volume or 1)
		local group = Audio.Group(cue.Group)
		local parent = resolve(where, 1e6)
		handle.Parent = typeof(where) == "Vector3" and parent or nil
		for _, row in ipairs(cue.Rows) do
			local r = table.clone(row)
			r.loop = true
			r.dur = nil
			r.at = nil
			shot(r, k, opts.Pitch or 1, parent, group, true, handle)
		end
	end)
	if not ok then
		warn("Halloween Audio loop failed (" .. tostring(name) .. "): " .. tostring(err))
	end
	function handle:SetVolume(v: number, fade: number?)
		self.Gain = v
		for _, e in ipairs(self.Sounds) do
			if e.Sound.Parent then
				if fade and fade > 0 then
					TweenService:Create(e.Sound, TweenInfo.new(fade), { Volume = e.Base * v }):Play()
				else
					e.Sound.Volume = e.Base * v
				end
			end
		end
	end
	function handle:SetPitch(pitch: number)
		for _, e in ipairs(self.Sounds) do
			if e.Sound.Parent then
				e.Sound.PlaybackSpeed = math.clamp(e.Speed * pitch, .05, 8)
			end
		end
	end
	function handle:Stop(fade: number?)
		if not self.Alive then
			return
		end
		self.Alive = false
		fade = fade or .6
		for _, e in ipairs(self.Sounds) do
			local s = e.Sound
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
				Debris:AddItem(s, fade + .05)
			end
		end
		if self.Parent then
			Debris:AddItem(self.Parent, fade + .1)
		end
	end
	return handle
end

function Audio.Stats()
	return { Live = live, Cap = CAP, LoopLive = liveLoop, LoopCap = LOOP_CAP }
end

return Audio
