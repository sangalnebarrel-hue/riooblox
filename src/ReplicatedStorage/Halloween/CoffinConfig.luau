-- THE BLACK COFFIN · server + presentation numbers (ReplicatedStorage.Halloween.CoffinConfig, WP-K4;
-- docs/halloween2/DESIGN.md §9.2-§9.4, §9.7, §24.4). The coffin's balance (price, keys, the drop table, duplicates) lives
-- in Chapter2Config.Coffin / Duplicates / Dogs (WP-A); this module only holds what the opening itself needs:
--   * the server: request, proximity, cooldown, who sees the show, what is announced server-wide and when
--   * the offline model (ServerStorage.UnderyardBuild.BlackCoffin): sizes and the attribute contract the client reads
--   * the client presentation (HalloweenClient.CoffinFX): timings per rarity, the Secret show, camera, colours, card
--   * C.Beats(rank, secret): the show's beat times (pure), shared by the server (the Hollow King hand-off and the
--     announcement land on the show's beats) and the client
-- Shared by server, client and the offline builder (pure data + pure functions, no requires).
local C = {}

---------------------------------------------------------------------------------------------------------------------
-- SERVER (ServerScriptService.Halloween.Coffin)
---------------------------------------------------------------------------------------------------------------------
C.Request = { Action = "C2CoffinOpen", Cost = 3, DebugAction = "C2CoffinDebug" }
C.Anchor = "CoffinShrine" -- 40_Underyard.Anchors part (UnderyardLayout.Anchors.CoffinShrine): proximity + prompt
C.Radius = 14 -- studs from the anchor (+ Chapter2Config.Proximity.Slack for a lagged client)
C.Cooldown = 2.5 -- seconds between two openings of one player (the show itself is client side)
C.NearRadius = 110 -- other players this close to the shrine see the opening (the lighter version)
C.Prompt = {
	ActionText = { "OPEN", "ОТКРЫТЬ" },
	ObjectText = { "THE BLACK COFFIN", "ЧЁРНЫЙ ГРОБ" },
	HoldDuration = .6,
	MaxActivationDistance = 12,
}
C.SecretDog = "HW_HollowKing" -- the Secret row: SecretReveal arrival + C2Announce {Kind = "HollowKing"} server-wide
C.AnnounceRank = 5 -- any other unconverted reward of this coffin rank or higher: C2Announce {Kind = "Mythic"}
C.BonusGroup = "Find" -- the extra rolls (H16 CROWN OF THE UNDERYARD, H12 COFFIN SENSE) roll this display group
C.BonusDog = "HW_CoffinPug" -- H12: Chapter2Config.Dogs.Defs.HW_CoffinPug.BonusFindChance per opening (yard team)
C.Window = { Page = "Underyard", Tab = "Coffin" } -- DogEconomyOpen when the prompt is refused for keys / shards
-- the Hollow King's arrival (ServerScriptService.SecretReveal.Show, venue "Coffin"): where the display king stands, in
-- the shrine's frame (UnderyardLayout.Square.CoffinShrine: -Z faces the tower, floor y 0). Its arrival script walks it
-- ~9 studs out of the dark behind that spot, i.e. out of the coffin, and raises the black moon behind the shrine.
C.King = { Ground = Vector3.new(0, .04, -9), Venue = "Coffin" }

---------------------------------------------------------------------------------------------------------------------
-- THE MODEL (offline builder, Order 31) — sizes in studs, local to the CoffinSeat (X across, Y up, Z along the coffin,
-- foot at -Z towards the bell tower, head at +Z towards the shrine's reredos)
---------------------------------------------------------------------------------------------------------------------
C.Model = {
	Name = "BlackCoffin",
	Width = 3.6, -- at the shoulders
	HeadWidth = 2.6,
	FootWidth = 2.2,
	Length = 7.2,
	Shoulder = 1.6, -- z of the shoulders
	Height = 2.2, -- body 1.7 + lid .5
	LidHeight = .5,
	Overhang = .08, -- the lid's lip over the walls
	Wall = .22,
	OpenAngle = 118, -- degrees the lid swings open on its hinge (the -X long edge) and hangs at
	-- the shrine's chain anchors when WP-G's shrine (Attachments ChainAnchor_1..3) is absent: seat-local positions
	FallbackAnchors = { Vector3.new(-5.0, -.3, 0), Vector3.new(5.0, -.3, 0), Vector3.new(0, -.3, 5.6) },
	FallbackSeatY = 3.2, -- seat height above the shrine CFrame (WP-G: bier top 2.0 + half the 2.4 coffin space)
}
-- attributes the client reads (CoffinFX): on the BlackCoffin model and its parts / sub-models
C.Attr = {
	Root = "CoffinRoot", -- model: true
	Seat = "CoffinSeat", -- model: CFrame of the seat (centre of the coffin volume)
	Lid = "CoffinLid", -- the lid hinge model (Atomic, PrimaryPart = LidHinge): true
	Seam = "CoffinSeam", -- Neon seam / crack parts (Transparency 1 in the place): light-up order 1..n
	Inner = "CoffinInner", -- Neon glow inside the coffin (Transparency 1)
	Light = "CoffinLight", -- the inner PointLight (Enabled = false in the place)
	Chain = "CoffinChain", -- chain models CoffinChain_1..3: index
	Link = "CoffinLink", -- every chain link part: its index along the chain
	Padlock = "CoffinPadlock", -- the padlock model: true
	Rune = "CoffinRune", -- violet rune parts (dim in the place, brighten in the show)
	Candle = "CoffinCandle", -- the small candle set model: true (flames also carry HwCandle)
	Fallback = "CoffinFallbackShrine", -- the bier built when WP-G's shrine is absent
}

---------------------------------------------------------------------------------------------------------------------
-- PRESENTATION (HalloweenClient.CoffinFX) — show-time seconds; a slow-motion window stretches show time on screen
---------------------------------------------------------------------------------------------------------------------
C.Show = {
	-- per rank 1..5 (Common .. Mythic): chain gap, rattle length, card delay after the lid opens, camera hold after the card
	Pace = {
		{ Gap = .42, Rattle = .7, Card = 1.4, Hold = 1.2 },
		{ Gap = .48, Rattle = .85, Card = 1.5, Hold = 1.4 },
		{ Gap = .55, Rattle = 1.0, Card = 1.7, Hold = 1.7 },
		{ Gap = .62, Rattle = 1.2, Card = 1.9, Hold = 2.0 },
		{ Gap = .68, Rattle = 1.45, Card = 2.4, Hold = 2.4 },
	},
	ChainStart = .85, -- first chain tightens
	Tighten = .42, -- tighten -> snap
	Padlock = .15, -- after the last snap the padlock drops
	CandleFlare = .3, -- after the last snap
	RattleDelay = .2, -- after the last snap the lid starts to rattle
	OpenDelay = .15, -- after the rattle the lid blasts open
	Swell = .35, -- Rare+: the sub swell this long before the lid opens
	Rise = 1.2, -- the reward climbs out of the coffin
	RiseHeight = 3.6, -- studs above the seat
	RiseSize = 2.8, -- the risen reward fits a box this big
	SlowMo = { Rank = 5, From = .1, Length = .45, Rate = .3 }, -- Mythic: show seconds [open+From, +Length] at Rate
	Lightning = { Rank = 5, At = { -.55, -.18, .16 }, Height = 46 }, -- Mythic strikes, relative to the lid opening
	ShockwaveRank = 2, -- Rare+ adds the ring shockwave
	Pillar = { Height = 46, Core = 1.8, Glow = 4.2, Thin = .45 }, -- Thin: the core / glow scale once the reward is out
	CardLife = 9, -- seconds the card stays after the cinematic before it closes itself
	CloseLid = .9, -- the reset: the lid swings shut
	NearLinger = 2.5, -- the lighter version resets this long after its reveal
	Near = { Volume = .65, Particles = .6 }, -- the lighter version for other players
	SkipLead = 0, -- the cinematic becomes skippable this long after the lid opens (§9.7: "after the lid opens")
	-- the Secret (H16 THE HOLLOW KING): absolute show seconds. Up to Open the coffin show; at Handoff the server's
	-- SecretReveal arrival takes over (Dogs/HW_HollowKing beats relative to it: moon rises .5, the king walks out 1.2-3.0,
	-- totality + crown of fire 3.2, title 4.3) and the Mega layer names the raiser world-wide at +4.2.
	Secret = {
		Gap = .7, Rattle = 1.1,
		Blackout = 4.25, -- screen to black, music cut (Mixer "HollowKing" = Silence), the candles die
		BlackoutHold = 1.2,
		Lift = .45, -- the black overlay settles at this alpha so only the violet seams and runes read
		Open = 6.6, -- the lid blasts open
		Handoff = 6.7, -- the server starts the arrival (SecretReveal.Show) at At + Handoff
		Follow = 5.9, -- the camera stays on the arrival this long after the hand-off
		Release = 4.6, -- the music cut is released this long after the hand-off (the arrival keeps its own duck)
		Linger = 8.8, -- the lid stays open this long after the hand-off (the arrival's Hold 8.2 + its fade)
		-- the arrival's beats (SecretArrivals/Dogs/HW_HollowKing), relative to the hand-off; also the fallback show's
		Rise = .5, Walk = 1.2, Arrive = 3.0, Total = 3.2, Title = 4.3, Banner = 4.2,
		MoonDistance = 4.6, MoonHeight = 9.4, MoonRadius = 3.7, -- fallback moon, shrine frame (z towards the reredos)
		KingHeight = 6.0,
	},
	Omen = { Tint = .9, Banner = 4.2, Hold = 5.5 }, -- the fallback world-wide banner (no SecretReveal arrival)
}

-- rarity colours of the seam light / pillar / banner (rank 1..6), brighter than the UI chips so they read as light
C.Colors = {
	{ 214, 226, 236 }, -- Common: bone-white
	{ 70, 178, 255 }, -- Rare
	{ 176, 116, 255 }, -- Epic
	{ 255, 196, 64 }, -- Legendary
	{ 255, 84, 128 }, -- Mythic
	{ 168, 70, 255 }, -- Secret: violet
}
C.Palette = {
	Ink = { 14, 10, 22 }, Lacquer = { 20, 14, 30 }, Iron = { 64, 62, 74 }, Silver = { 150, 146, 162 }, Rune = { 150, 80, 230 },
	RuneHot = { 215, 160, 255 }, Satin = { 52, 20, 70 }, Candle = { 255, 170, 80 }, Wax = { 236, 226, 200 },
	Moon = { 196, 220, 255 }, Corona = { 190, 110, 255 }, Crown = { 176, 76, 255 }, Spark = { 255, 196, 120 },
}

-- the reveal camera (seat-local {camera, look-at}): framing of the chains / rattle, the reveal, the Secret
C.Camera = {
	Fov = 55, RevealFov = 50, SlowFov = 44,
	Main = { Vector3.new(2.0, 6.0, -11.5), Vector3.new(0, .4, .6) },
	Push = { Vector3.new(1.4, 5.2, -9.6), Vector3.new(0, .5, .4) },
	Reveal = { Vector3.new(2.4, 4.4, -11.6), Vector3.new(0, 3.1, -.2) },
	SecretLow = { Vector3.new(1.0, 1.3, -12.5), Vector3.new(0, 4.5, 6) },
	SecretOpen = { Vector3.new(-1.6, 2.4, -15.5), Vector3.new(0, 2.6, 0) },
	SecretKing = { Vector3.new(-3.0, 2.2, -18.5), Vector3.new(0, 2.6, -3.0) },
}

---------------------------------------------------------------------------------------------------------------------
-- Beats: the show's timeline for a coffin rank (1..6) — pure, shared by server and client
---------------------------------------------------------------------------------------------------------------------
-- -> {Rank, Secret, Chains = {{Tighten, Snap} x3}, Padlock, Flare, RattleFrom, RattleTo, Open, Rise, Card, End,
--     Swell?, Shockwave, Lightning = {t...}, SlowFrom?, SlowTo?, SlowRate?, Blackout?, Lift?, Handoff?, Release?,
--     Reveal (when the reward is shown to the world: the announcement lands here), SkipAfter, RealEnd (seconds on screen)}
function C.Beats(rank: any, secret: boolean?): { [string]: any }
	local r = math.clamp(math.floor(tonumber(rank) or 1), 1, 6)
	local S = C.Show
	local isSecret = secret == true or (secret == nil and r >= 6)
	local pace = isSecret and S.Secret or S.Pace[math.min(r, 5)]
	local b: { [string]: any } = { Rank = r, Secret = isSecret, Chains = {}, Lightning = {} }
	for k = 1, 3 do
		local t0 = S.ChainStart + (k - 1) * pace.Gap
		b.Chains[k] = { Tighten = t0, Snap = t0 + S.Tighten }
	end
	local last = b.Chains[3].Snap
	b.Padlock = last + S.Padlock
	b.Flare = last + S.CandleFlare
	b.RattleFrom = last + S.RattleDelay
	b.RattleTo = b.RattleFrom + pace.Rattle
	b.Shockwave = r >= S.ShockwaveRank
	if isSecret then
		local X = S.Secret
		b.Blackout = X.Blackout
		b.Lift = X.Blackout + X.BlackoutHold
		b.Open = X.Open
		b.Handoff = X.Handoff
		b.Release = X.Handoff + X.Release
		b.Rise = X.Handoff + X.Walk
		b.Reveal = X.Handoff + X.Total
		b.Card = X.Handoff + X.Follow
		b.End = b.Card
		b.Swell = X.Open - S.Swell
	else
		b.Open = b.RattleTo + S.OpenDelay
		b.Rise = b.Open + .15
		b.Reveal = b.Open
		b.Card = b.Open + pace.Card
		b.End = b.Card + pace.Hold
		if r >= 3 then
			b.Swell = b.Open - S.Swell
		end
		if r >= S.Lightning.Rank then
			for _, dt in ipairs(S.Lightning.At) do
				table.insert(b.Lightning, b.Open + dt)
			end
		end
		if r >= S.SlowMo.Rank then
			b.SlowFrom = b.Open + S.SlowMo.From
			b.SlowTo = b.SlowFrom + S.SlowMo.Length
			b.SlowRate = S.SlowMo.Rate
		end
	end
	b.SkipAfter = b.Open + S.SkipLead
	b.RealEnd = C.RealTime(b, b.End)
	return b
end

-- show seconds -> seconds on screen (the slow-motion window plays slower)
function C.RealTime(b: { [string]: any }, showT: number): number
	local from, to, rate = b.SlowFrom, b.SlowTo, b.SlowRate
	if not from or not to or not rate or rate <= 0 or showT <= from then
		return showT
	end
	if showT <= to then
		return from + (showT - from) / rate
	end
	return showT + (to - from) * (1 / rate - 1)
end

-- seconds on screen -> show seconds (inverse of RealTime)
function C.ShowTime(b: { [string]: any }, realT: number): number
	local from, to, rate = b.SlowFrom, b.SlowTo, b.SlowRate
	if not from or not to or not rate or rate <= 0 or realT <= from then
		return realT
	end
	local slowEnd = from + (to - from) / rate
	if realT <= slowEnd then
		return from + (realT - from) * rate
	end
	return realT - (to - from) * (1 / rate - 1)
end

return C
