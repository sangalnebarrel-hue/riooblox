-- HALLOWEEN CALENDAR — every number of the main-map countdown (ReplicatedStorage.Halloween.HalloweenCalendarConfig).
-- docs/halloween2/DESIGN.md §13. Shared by the server (Calendar service), the client (HalloweenClient.CalendarFX) and the
-- offline stage builders (ServerStorage.HalloweenCalendarBuild). Pure data: requires nothing.
--
-- HOW IT WORKS
--   The island slowly rots toward Halloween: D-7 (October 24, 00:00 UTC) is stage 1, each UTC midnight adds a stage, and
--   October 31 00:00 UTC is stage 8 (the full transformation). Stage decorations are prebuilt offline into
--   ServerStorage.HalloweenCalendar.Stage01..Stage08 (saved in the place, editable in Studio); the server moves every
--   folder with stage <= today into Workspace.DOGROTS_District.41_HalloweenCalendar (and back if the date goes back in
--   Studio). Everything else (dead grass, fog, moon, lamps, windows, eyes, sway, bats, ghosts, whispers) is client-side
--   and reads the per-stage numbers below. Every stage keeps the earlier ones (StageParams is cumulative).
--   Switch: Config.HalloweenCalendarEnabled (Shared.CalendarEnabled()); players hide the decor with the HALLOWEEN window's
--   map-decor toggle (player attribute HwMapDecor).
local C = {}

C.Version = 1
C.Target = { Year = 2026, Month = 10, Day = 31, Hour = 0 } -- UTC; stage 8 from this moment
-- optional end of the calendar (UTC): from this moment the decor goes back into storage (stage 0). nil = it stays until
-- the event (or HalloweenCalendarEnabled) is switched off.
C.Until = nil :: { Year: number, Month: number, Day: number, Hour: number? }?
C.CheckEvery = 120 -- s between server date checks (the next stage boundary is also scheduled exactly)
C.Studio = {
	ForceStage = nil :: number?, -- 0..8: Studio only (never a live server); the C2Debug "Calendar n" command overrides it
}

-- where the stage folders live
C.Root = "41_HalloweenCalendar" -- Workspace.DOGROTS_District.<Root> (Model, created by the server when missing)
C.Storage = "HalloweenCalendar" -- ServerStorage.<Storage>.StageNN (Folders, built by tools/edits/41_calendar.luau)
C.StateName = "Calendar" -- ReplicatedStorage.Halloween.State.<StateName> {Enabled, Stage, DaysLeft, Target, NextAt, Forced, Revision}

---------------------------------------------------------------------------------------------------------------------
-- Stages. `From` = days before the target (D-From, 00:00 UTC) the stage starts; stage 8 starts at the target itself.
-- Per-stage visual parameters (anything left out keeps the previous stage's value — StageParams is cumulative and
-- every number only grows; tests/calendar.luau checks it):
--   Grass       share of the island grass parts (EventTintSurface, Material Grass) tinted dead
--   GrassDepth  how far a tinted part goes toward its dead colour (0..1)
--   Atmos       weight of the Halloween Lighting layer "CALENDAR" (fog / haze / grade / moon size; full = C.Lighting)
--   Dark        extra night darkening (0..1 of C.Lighting.NightDarken)
--   Mist        ground mist around the camera (0..1)
--   Halo        moon halo (0..1: the moon reads bigger)          Eclipse  black eclipse disc over the moon (0..1)
--   Lamps       lamp tint strength toward the calendar orange / violet (0..1)
--   Bats        bats circling the calendar roosts (High quality)   Ghosts   distant ghosts at once (High quality)
--   Whispers    whispers per minute near calendar trees            Sounds   strange night sounds per minute
--   Windows     window blinks per minute (museum + shelter glass)  Eyes     share of tree eyes open at a time (0..1)
--   Sway        branch sway amplitude in degrees                   Wisps    spectral wisps near the camera
--   Leaves      falling dry leaves near the camera (0..1)          Finale   October 31 extras (0..1)
---------------------------------------------------------------------------------------------------------------------
C.Base = {
	Grass = 0, GrassDepth = .5, Atmos = 0, Dark = 0, Mist = 0, Halo = 0, Eclipse = 0, Lamps = 0, Bats = 0, Ghosts = 0,
	Whispers = 0, Sounds = 0, Windows = 0, Eyes = 0, Sway = 0, Wisps = 0, Leaves = 0, Finale = 0,
}
C.Stages = {
	{ Folder = "Stage01", From = 7, Label = { "D-7", "Д-7" }, Name = { "THE FIRST ROT", "ПЕРВАЯ ГНИЛЬ" },
		Toast = { "D-7 · The grass around the Dead Yard is dying…", "Д-7 · Трава у Мёртвого двора увядает…" },
		Grass = .10, GrassDepth = .55, Atmos = .12, Leaves = .35 },
	{ Folder = "Stage02", From = 6, Label = { "D-6", "Д-6" }, Name = { "CROOKED SPROUTS", "КРИВЫЕ РОСТКИ" },
		Toast = { "D-6 · Crooked trees are sprouting across the island.", "Д-6 · По острову прорастают кривые деревья." },
		Grass = .20, GrassDepth = .6, Atmos = .24, Dark = .3, Leaves = .45 },
	{ Folder = "Stage03", From = 5, Label = { "D-5", "Д-5" }, Name = { "THE FOG ROLLS IN", "ТУМАН СГУЩАЕТСЯ" },
		Toast = { "D-5 · The fog thickens. Something rustles in the dark.", "Д-5 · Туман густеет. В темноте что-то шуршит." },
		Grass = .33, GrassDepth = .65, Atmos = .38, Dark = .45, Mist = .2, Bats = 4, Sounds = .8, Leaves = .55 },
	{ Folder = "Stage04", From = 4, Label = { "D-4", "Д-4" }, Name = { "THE TREES ARE WATCHING", "ДЕРЕВЬЯ СМОТРЯТ" },
		Toast = { "D-4 · The trees have opened their eyes. The windows blink back.", "Д-4 · Деревья открыли глаза. Окна моргают в ответ." },
		Grass = .42, GrassDepth = .7, Atmos = .5, Dark = .55, Mist = .3, Bats = 6, Sounds = 1, Windows = 2, Eyes = .25,
		Leaves = .6 },
	{ Folder = "Stage05", From = 3, Label = { "D-3", "Д-3" }, Name = { "THE SWOLLEN MOON", "РАЗДУТАЯ ЛУНА" },
		Toast = { "D-3 · The moon swells. Ghosts drift at the edge of sight.", "Д-3 · Луна растёт. На краю зрения бродят призраки." },
		Grass = .55, GrassDepth = .75, Atmos = .62, Dark = .65, Mist = .55, Halo = .55, Lamps = .5, Bats = 8, Ghosts = 2,
		Sounds = 1.2, Windows = 3, Eyes = .35, Leaves = .65 },
	{ Folder = "Stage06", From = 2, Label = { "D-2", "Д-2" }, Name = { "CREEPING ROOTS", "ПОЛЗУЧИЕ КОРНИ" },
		Toast = { "D-2 · Roots creep toward the streets. Can you hear the whispers?", "Д-2 · Корни ползут к улицам. Слышите шёпот?" },
		Grass = .75, GrassDepth = .82, Atmos = .78, Dark = .8, Mist = .75, Halo = .7, Lamps = .7, Bats = 10, Ghosts = 3,
		Whispers = 1.2, Sounds = 1.5, Windows = 4, Eyes = .5, Sway = 4, Leaves = .75 },
	{ Folder = "Stage07", From = 1, Label = { "D-1", "Д-1" }, Name = { "ALMOST LOST", "ПОЧТИ ПОТЕРЯН" },
		Toast = { "D-1 · Tomorrow is Halloween. The island is almost lost…", "Д-1 · Завтра Хэллоуин. Остров почти потерян…" },
		Grass = .92, GrassDepth = .9, Atmos = 1, Dark = 1, Mist = 1, Halo = .85, Eclipse = .4, Lamps = .9, Bats = 14,
		Ghosts = 4, Whispers = 2, Sounds = 2, Windows = 6, Eyes = .7, Sway = 6, Wisps = 8, Leaves = .85 },
	{ Folder = "Stage08", From = 0, Label = { "OCT 31", "31 ОКТ" }, Name = { "HALLOWEEN NIGHT", "НОЧЬ ХЭЛЛОУИНА" },
		Toast = { "HAPPY HALLOWEEN! The Night of the Buried Moon has come.", "С ХЭЛЛОУИНОМ! Ночь Погребённой Луны настала." },
		Grass = 1, GrassDepth = .95, Halo = 1, Eclipse = .75, Lamps = 1, Bats = 18, Ghosts = 6, Whispers = 2.5, Sounds = 2.5,
		Windows = 8, Eyes = .9, Sway = 7, Wisps = 12, Leaves = 1, Finale = 1 },
}
C.MaxStage = #C.Stages

---------------------------------------------------------------------------------------------------------------------
-- Client: quality scaling (Config.Quality[*].CalendarFX overrides when present, DESIGN §17)
---------------------------------------------------------------------------------------------------------------------
C.Quality = { High = 1, Medium = .6, Low = .3 }

-- dead grass (CalendarFX): which parts, which colours, in which order
C.Grass = {
	Reapply = 60, -- s: re-apply the tint (a world event's colour restore never fights it for long)
	AfterEvent = 6, -- s after a world event ends before the tint is applied again (its 3 s restore tween first)
	Glide = 6, -- s: a newly tinted part fades to its dead colour
	-- the rot spreads out of THE DEAD YARD: parts nearer this point turn first (Spread 0 = pure hash order, 1 = pure distance)
	Origin = { X = 124, Z = 640 },
	Spread = .7,
	SpreadRange = 900, -- studs over which the distance rank runs from 0 to 1
	Exclude = { "04_PlayerYards" }, -- top-level DOGROTS_District children never tinted (the players' own yards)
	Colors = { { 176, 122, 52 }, { 150, 104, 46 }, { 168, 142, 70 }, { 132, 84, 44 }, { 186, 98, 40 } }, -- dry / rust / straw
}

-- the Halloween Lighting layer "CALENDAR" (HalloweenClient.Lighting.Layer): the full D-1 look, blended by Atmos.
-- Prio 15 sits between NIGHT (10) and the Dead Yard ZONE (20): inside the yard / the Underyard their own looks win.
C.Lighting = {
	Prio = 15,
	MaxDensity = .36, -- gameplay visibility: the fog never goes thicker than this
	Fade = 4, -- s: weight glide on stage changes
	Atmo = { Density = .36, Offset = .14, Color = { 150, 136, 168 }, Decay = { 104, 62, 70 }, Haze = 2.1, Glare = 0 },
	Bloom = { Intensity = .36, Size = 26, Threshold = 1.42 },
	Clouds = { Cover = .62, Density = .36, Color = { 118, 96, 122 } },
	Sky = { MoonAngularSize = 22, StarCount = 2600 },
	GradeDay = { Tint = { 255, 236, 218 }, Saturation = -.04, Contrast = .06, Brightness = -.01 },
	GradeNight = { Tint = { 236, 224, 255 }, Saturation = -.02, Contrast = .08, Brightness = -.01 },
	NightDarken = .05, -- grade Brightness taken off at full night × Dark
	Finale = { -- October 31 (× Finale): an orange-violet Halloween night
		Atmo = { Color = { 168, 120, 150 }, Decay = { 140, 60, 40 } },
		Clouds = { Color = { 150, 84, 70 } },
		Grade = { Tint = { 255, 222, 206 }, Saturation = .04, Contrast = .1 },
	},
}

-- lamps (Halloween_MapLamp glasses + lights): blend toward these by Lamps (per-lamp hash picks the colour)
C.Lamps = { Colors = { { 255, 118, 24 }, { 150, 70, 235 } } }

-- the museum's BlueWindow panes and the Dog Shelter glass light up and blink (restored exactly afterwards)
C.Windows = {
	Paths = {
		{ "06_DogDexMuseum", "SideFacadeDetails", "*BlueWindow" },
		{ "32_WelcomeHub", "DogShelter", "Architecture", "*FrontWindow" },
		{ "32_WelcomeHub", "DogShelter", "Architecture", "*SideWindow" },
	},
	Range = 260, -- studs from the camera
	On = { 1.2, 4.5 }, -- s a window stays lit
	Colors = { { 255, 170, 70 }, { 255, 132, 40 }, { 190, 120, 255 }, { 130, 255, 120 } },
	Transparency = .12,
	Flicker = .35, -- chance a lit window flickers off/on once
	Rescan = 15, -- s between window list refreshes (streaming)
}

-- tree faces (CalEyes parts) and branches (CalSway models) built by the stage builders
C.Eyes = { Range = 220, Open = { 2.5, 7 }, Closed = { 3, 10 }, BlinkTime = .12, Color = { 255, 150, 50 } }
C.Sway = { Range = 170, Speed = { .45, .8 }, Gust = .35, MaxParts = 600 } -- MaxParts: moved per update (30 Hz), × quality
C.Candles = { Range = 140 }

-- creatures and presences (counts are High quality; × C.Quality)
C.Bats = { Range = 320, Radius = { 7, 13 }, Height = { 3, 8 }, Night = .55 } -- by day only this share flies
C.Ghosts = { Range = { 70, 230 }, Every = { 14, 34 }, Life = { 14, 26 }, Night = .5, Color = { 196, 228, 255 } }
C.Whispers = { Range = 40, Volume = .55 }
C.Sounds = {
	Cues = { "Owl", "Howl", "CrowCaw", "CoffinKnock", "DoorCreak", "Cackle", "BellToll", "Bats" },
	Distance = { 40, 110 }, Volume = .5, Night = .3, -- by day the rate is × Night
}
C.Mist = { Banks = 6, Rate = 1.6, Radius = { 18, 60 }, Color = { 196, 186, 214 } }
C.Wisps = { Radius = { 8, 34 }, Height = { 1.2, 4.5 }, Colors = { { 150, 255, 140 }, { 190, 120, 255 }, { 255, 170, 80 } } }
C.Leaves = { Rate = 10, Radius = 40, Colors = { { 196, 110, 40 }, { 170, 70, 30 }, { 210, 160, 60 } } }

-- the moon (around BloodMoonFX's Buried Moon): halo rings and the eclipse disc, at Halo / Eclipse
C.Moon = { HaloScale = { 1.35, 1.9 }, HaloColor = { 255, 176, 96 }, RingColor = { 186, 120, 255 }, EclipseColor = { 10, 6, 16 } }

---------------------------------------------------------------------------------------------------------------------
-- Offline builders (ServerStorage.HalloweenCalendarBuild): placement rules and budgets
---------------------------------------------------------------------------------------------------------------------
C.Build = {
	Seed = 31102026,
	MaxParts = 9000, MaxLights = 90, -- whole ServerStorage.HalloweenCalendar (tools/verify_world.luau budgets it too)
	Island = { X0 = -218, X1 = 218, Z0 = -258, Z1 = 760 }, -- the main island (grass top y ~0)
	Cell = 2, -- occupancy grid cell (studs)
	PathMargin = 2.5, -- studs kept clear around any ground-level geometry (paths, plazas, buildings, props)
	-- areas nothing is ever placed in: the yards, shops, the Dead Yard, the spawn, the factory approach, doors / prompts
	Keepout = {
		{ X0 = -180, X1 = 180, Z0 = -170, Z1 = 166, Name = "PlayerYards" },
		{ X0 = 66, X1 = 168, Z0 = 240, Z1 = 428, Name = "Shops" },
		{ X0 = 25, X1 = 220, Z0 = 520, Z1 = 760, Name = "DeadYard" },
		{ X0 = -32, X1 = 32, Z0 = 340, Z1 = 414, Name = "Spawn" },
		{ X0 = -36, X1 = 36, Z0 = -258, Z1 = 166, Name = "DogFactory" },
		{ X0 = 76, X1 = 152, Z0 = 158, Z1 = 252, Name = "Shelter" },
	},
	PromptMargin = 9, -- studs around every ProximityPrompt / NavigationAnchor / *Door* / *Entrance* part
	SkyIslands = "23_DistrictPolish/Horizon_Islands",
}

return C
