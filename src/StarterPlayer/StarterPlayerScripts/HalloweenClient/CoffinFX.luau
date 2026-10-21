-- THE BLACK COFFIN — the opening presentation (StarterPlayerScripts.HalloweenClient.CoffinFX, WP-K4;
-- docs/halloween2/DESIGN.md §9.7, §17, §24.4). Client presentation only: the server rolls, pays and announces
-- (ServerScriptService.Halloween.Coffin); this module shows it on the prebuilt 40_Underyard.BlackCoffin (CoffinConfig.Attr).
--   C2Coffin (the opener)  the cinematic (Cinema "Coffin": letterbox, locked controls, hidden HUD; skippable once the lid
--                          opens = fast-forward to the card): three chains tighten and snap one by one (links fly, sparks),
--                          the padlock drops, the candles flare, the lid rattles in its frame while cracks of light run
--                          along the seams in the rarity colour, the lid blasts open on its hinge and hangs, a light pillar
--                          in the rarity colour, the reward climbs out of the coffin, then the 3D card (ViewportFrame: dog /
--                          cosmetic / find / currency icon) with the rarity banner, NEW or the duplicate's conversion (§9.4),
--                          the bonus rows (H16 crown, H12 pug), CONTINUE / OPEN AGAIN. Rare+ adds a ring shockwave; Mythic
--                          lightning strikes around the shrine and a slow-motion lid (CoffinConfig.Beats).
--   SECRET (H16)           slower chains, then total blackout (screen black, the music cut: Mixer "HollowKing" = Silence,
--                          the candles die), the violet seams burn in the dark, the lid blasts open into a violet pillar and
--                          the show hands over to the server's Secret arrival (SecretReveal venue "Coffin": the black moon
--                          rises behind the coffin and eclipses, the Hollow King walks out of the coffin as an ink
--                          silhouette, the crown of violet fire, the Mega layer's world-wide "<NAME> RAISED THE HOLLOW KING")
--                          while the camera holds the composition. Without that arrival in the place (payload.Arrival
--                          false) this module plays its own moon, eclipse, crown, silhouette, banner and card — never both.
--   C2CoffinNear           players near the shrine see the lighter version on the same server clock (no camera, no card:
--                          a name plate over the coffin, quieter, fewer particles).
--   C2Announce HollowKing  the banner for everyone when no arrival plays it (Arrival false); with the arrival the Mega
--                          layer names the raiser. "Mythic" announcements belong to the HUD (WP-L).
--   C2CoffinRefused        a localized toast + the deny cue.
-- Every show runs on the server clock (payload.At = show second 0), so the opener and the onlookers see the same beats and
-- the Hollow King's hand-off lands on the lid. One show at a time: the player's own openings queue, a lighter show yields
-- to the player's own. Everything is built in pcall; one teardown restores the coffin (lid, chains, padlock, seams, inner
-- glow, runes, candles), the shrine prompt, the character, the grade, the mixer duck and the fade, and destroys the scene
-- and the card (also on error, death or a respawn). Quality: Shared.Budget("CoffinFX") (links, bolts, lights, motes);
-- Reduced Motion: no shake / screen flashes / slow-motion punch, a calmer rattle, static camera cuts (Cinema).
-- API (also for tests): CoffinFX.Start(ctx), CoffinFX.Play(payload, {Near?}) -> show?, CoffinFX.Stop(reason?),
-- CoffinFX.Describe(row) -> {Title, Sub, Amount?, Status?, Kind}, CoffinFX.Announce(data), CoffinFX.Refused(data),
-- CoffinFX.BuildReward(row) -> Model?, CoffinFX.State.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local CC = require(Halloween:WaitForChild("CoffinConfig"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local CoffinFX = {}
CoffinFX.Config = CC
local player = Players.LocalPlayer
local ctx: any = nil
local started = false

local C3 = Color3.fromRGB
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local function rgb(t: { number }): Color3
	return C3(t[1], t[2], t[3])
end
local INK = rgb(CC.Palette.Ink)
local BONE = C3(230, 222, 200)
local VIOLET = rgb(CC.Palette.Rune)
local VIOLET_HOT = rgb(CC.Palette.RuneHot)
local CROWN = rgb(CC.Palette.Crown)
local MOON = rgb(CC.Palette.Moon)
local SPARK = rgb(CC.Palette.Spark)
local CANDLE = rgb(CC.Palette.Candle)
local PANEL = C3(24, 18, 36)
local PANEL_DARK = C3(14, 10, 22)
local UP = Vector3.new(0, 1, 0)
local SMOOTH = Enum.SurfaceType.Smooth
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder standing up (axis X -> Y)
local RARITY_RU = { Common = "ОБЫЧНОЕ", Rare = "РЕДКОЕ", Epic = "ЭПИЧЕСКОЕ", Legendary = "ЛЕГЕНДАРНОЕ", Mythic = "МИФИЧЕСКОЕ",
	Secret = "СЕКРЕТНОЕ" }
local REVEAL_CUE = { "CoffinRevealCommon", "CoffinRevealRare", "CoffinRevealEpic", "CoffinRevealLegendary", "CoffinRevealMythic",
	"CoffinRevealSecret" }

-- everything the module keeps between frames (read by tests)
local State: any = { Current = nil, Queue = {}, Card = nil, Shows = 0, Banners = 0, Omens = 0, Toasts = 0, Last = nil }
CoffinFX.State = State

---------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------
local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("CoffinFX: " .. msg)
	end
end
local function safe(key: string, fn: (...any) -> ...any, ...: any): boolean
	local ok, err = pcall(fn, ...)
	if not ok then
		warnOnce(key, tostring(err))
	end
	return ok
end

-- Russian: Localization.Coffin first (UI + server messages), then Localization.Underyard
local locs: { any }? = nil
local function ruOf(en: string): string?
	if locs == nil then
		local list = {}
		for _, name in ipairs({ "Coffin", "Underyard" }) do
			local ok, m = pcall(function()
				local folder = RS:FindFirstChild("Localization")
				local inst = folder and folder:FindFirstChild(name)
				return inst and require(inst :: any)
			end)
			if ok and type(m) == "table" and type(m.Translate) == "function" then
				table.insert(list, m)
			end
		end
		locs = list
	end
	for _, m in ipairs(locs :: { any }) do
		local ok, ru = pcall(m.Translate, en, "ru")
		if ok and type(ru) == "string" then
			return ru
		end
	end
	return nil
end
local function T(en: string): string
	if type(en) ~= "string" or not Shared.IsRussian() then
		return en
	end
	return ruOf(en) or Shared.T(en)
end
-- a localized string.format template (the template itself is the key)
local function F(en: string, ...: any): string
	local ok, out = pcall(string.format, T(en), ...)
	if ok then
		return out
	end
	local okEn, outEn = pcall(string.format, en, ...)
	return okEn and outEn or en
end
local function Lp(pair: any): string
	if type(pair) == "table" then
		return Shared.L(pair[1] or "", pair[2])
	end
	return tostring(pair or "")
end
-- upper case for Latin and Cyrillic (string.upper only knows ASCII: "Полое сердце" -> "ПОЛОЕ СЕРДЦЕ")
local function upper(text: string): string
	local ok, out = pcall(function()
		local chars = {}
		for _, c in utf8.codes(text) do
			if (c >= 0x61 and c <= 0x7A) or (c >= 0x430 and c <= 0x44F) then
				c -= 32
			elseif c == 0x451 then
				c = 0x401
			end
			table.insert(chars, utf8.char(c))
		end
		return table.concat(chars)
	end)
	return ok and out or string.upper(text)
end
CoffinFX.Upper = upper

local function reduced(): boolean
	return Shared.ReducedMotion()
end
local function budget(): number
	local ok, v = pcall(Shared.Budget, "CoffinFX")
	return ok and type(v) == "number" and v > 0 and v or 1
end
local function lowQuality(): boolean
	return Shared.Quality() == "Low"
end
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function outCubic(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end
local function outBack(x: number): number
	x = math.clamp(x, 0, 1)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function tween(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(math.max(0, seconds), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end
local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.time()
end
local function rarityColor(rank: number): Color3
	return rgb(CC.Colors[math.clamp(math.floor(rank), 1, 6)] or CC.Colors[1])
end
local function rarityName(rank: number): string
	local name = Shared.Rarity(math.clamp(math.floor(rank), 1, 6))
	return name
end
local function rarityLabel(rank: number): string
	local name = rarityName(rank)
	return Shared.IsRussian() and (RARITY_RU[name] or string.upper(name)) or string.upper(name)
end

-- one write for many anchored parts (absolute CFrames, so nothing drifts however often it runs)
local function moveParts(parts: { BasePart }, cfs: { CFrame })
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(parts) do
			p.CFrame = cfs[i]
		end
	end
end

local function module(name: string): any
	local m = ctx and ctx.Modules and ctx.Modules[name]
	if m then
		return m
	end
	local inst = script.Parent and script.Parent:FindFirstChild(name)
	if inst then
		local ok, value = pcall(require, inst)
		if ok then
			return value
		end
	end
	return nil
end
local function cinema(): any
	return module("Cinema")
end
local function cs(): any
	return module("Chapter2State")
end
local mixerMod: any = nil
local function mixer(): any
	if mixerMod == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("AudioMixer", 5) :: any)
		end)
		mixerMod = ok and type(m) == "table" and m or false
	end
	return mixerMod or nil
end
local fxMod: any = nil
local function fx(): any
	if fxMod == nil then
		local ok, m = pcall(function()
			return (ctx and ctx.FX) or require(Halloween:WaitForChild("FX") :: any)
		end)
		fxMod = ok and type(m) == "table" and m or false
	end
	return fxMod or nil
end
local audioMod: any = nil
local function audio(): any
	if audioMod == nil then
		local ok, m = pcall(function()
			return (ctx and ctx.Audio) or require(Halloween:WaitForChild("Audio") :: any)
		end)
		audioMod = ok and type(m) == "table" and m or false
	end
	return audioMod or nil
end
-- a cue (quieter for the lighter version)
local function cue(show: any?, name: string, where: any?, volume: number?, opts: { [string]: any }?)
	local a = audio()
	if not a or not a.Play then
		return
	end
	local o = opts and table.clone(opts) or {}
	o.Volume = (volume or 1) * (show and show.Near and CC.Show.Near.Volume or 1)
	if where == nil and show and show.Near and show.Rig then
		where = show.Rig.Seat.Position -- onlookers hear the coffin where it stands
	end
	safe("cue" .. name, a.Play, name, where, o)
end

---------------------------------------------------------------------------------------------------------------------
-- What a reward row is, in words (pure; the card, the name plate, tests)
---------------------------------------------------------------------------------------------------------------------
local CURRENCY = {
	Dust = "LUCKY DUST", Shards = "BELL SHARDS", Bones = "BONES", Cash = "COINS", Fragments = "COSMETIC FRAGMENTS",
	Key = "COFFIN KEY", Candy = "CANDY", Title = "TITLE",
}
local CHIP = { Dust = "LUCKY DUST +%s", Shards = "BELL SHARDS +%s", Fragments = "FRAGMENTS +%s", Bones = "BONES +%s",
	Cash = "COINS +%s", Key = "COFFIN KEYS +%s", Candy = "CANDY +%s" }
-- the short form of a chip on a narrow card (an icon instead of the words)
local ICON = { Dust = "✨", Shards = "🔔", Fragments = "🧵", Bones = "🦴", Cash = "💰", Key = "🗝", Candy = "🍬" }
local REASON = { Owned = "DUPLICATE", Full = "STORAGE FULL", Unavailable = "NOT AVAILABLE YET", Undeclared = "CONVERTED",
	Unknown = "CONVERTED" }

local function nameOf(kind: string?, id: string?): string?
	if type(id) ~= "string" then
		return nil
	end
	local def = kind == "Find" and Cfg.Finds.Defs[id] or kind == "Decor" and Cfg.Decor.Defs[id] or kind == "Skin" and Cfg.Skins.Defs[id]
		or kind == "Dog" and Cfg.Dogs.Defs[id] or nil
	return def and Lp(def.Name) or nil
end

-- -> {Kind, Title, Sub, Amount?, Status?, New?, Chips = {string}, Short = {string}}
function CoffinFX.Describe(row: any): any
	row = type(row) == "table" and row or {}
	local kind = tostring(row.Kind or "")
	local out: any = { Kind = kind, Chips = {}, Short = {} }
	local amount = math.max(0, math.floor(tonumber(row.Amount) or 0))
	if kind == "Find" or kind == "Decor" or kind == "Skin" or kind == "Dog" then
		out.Title = upper(nameOf(kind, row.Id) or tostring(row.Id or "?"))
		if kind == "Find" then
			out.Sub = T("SHOWCASE FIND")
		elseif kind == "Decor" then
			out.Sub = T("PLOT COSMETIC")
		elseif kind == "Skin" then
			out.Sub = T("PICKAXE SKIN")
		else
			local def = Cfg.Dogs.Defs[row.Id]
			out.Sub = def and F("EVENT DOG · %s", def.Code) or T("EVENT DOG")
		end
	else
		out.Title = T(CURRENCY[kind] or "REWARD")
		out.Sub = T("FROM THE BLACK COFFIN")
		out.Amount = "+" .. Shared.Format(amount)
	end
	if row.Converted then
		out.Status = T(REASON[row.Reason or ""] or "CONVERTED")
		for _, c in ipairs(type(row.Conversion) == "table" and row.Conversion or {}) do
			local tpl = CHIP[c.Kind]
			if tpl then
				local n = Shared.Format(tonumber(c.Amount) or 0)
				table.insert(out.Chips, F(tpl, n))
				table.insert(out.Short, (ICON[c.Kind] or "+") .. " +" .. n)
			end
		end
	elseif kind == "Dog" then
		out.Status = T("JOINED YOUR DOGS")
		out.New = true
	elseif kind == "Find" then
		out.Status = T("NEW · ADDED TO YOUR ITEMS")
		out.New = true
	elseif kind == "Decor" then
		out.Status = T("NEW · ADDED TO YOUR PLOT COSMETICS")
		out.New = true
	elseif kind == "Skin" then
		out.Status = T("NEW · ADDED TO YOUR PICKAXE SKINS")
		out.New = true
	end
	if type(row.Overflow) == "table" then
		out.Status = T("KEY STORAGE FULL")
		local n = Shared.Format(tonumber(row.Overflow.Amount) or 0)
		table.insert(out.Chips, F(CHIP.Shards, n))
		table.insert(out.Short, ICON.Shards .. " +" .. n)
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Reward models: the real thing when the place has it (MenuModels / DiscoveryVisuals / DecorModels / PickaxeSkins),
-- else a small built icon. Every model is display-only (anchored, no collisions, no scripts / prompts / sounds).
---------------------------------------------------------------------------------------------------------------------
local function ipart(m: Instance, name: string, shape: Enum.PartType?, size: Vector3, cf: CFrame, color: Color3,
	material: Enum.Material?, extra: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	for k, v in pairs(extra or {}) do
		(p :: any)[k] = v
	end
	p.Parent = m
	return p
end
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON, METAL, FABRIC = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Fabric
local CF, ANG, V3 = CFrame.new, CFrame.Angles, Vector3.new

local ICONS: { [string]: (Model) -> () } = {}
ICONS.Dust = function(m) -- a velvet pouch spilling glittering dust
	ipart(m, "Pouch", BALL, V3(1.7, 1.5, 1.7), CF(0, .75, 0), C3(96, 44, 140), FABRIC)
	ipart(m, "Neck", CYL, V3(.45, .62, .62), CF(0, 1.55, 0) * CYL_UP, C3(84, 36, 124), FABRIC)
	ipart(m, "Tie", CYL, V3(.14, .72, .72), CF(0, 1.42, 0) * CYL_UP, C3(236, 196, 92), METAL)
	ipart(m, "Ruffle", BALL, V3(.86, .36, .86), CF(0, 1.86, 0), C3(110, 54, 156), FABRIC)
	for i = 1, 7 do
		local a = i * 2.3
		ipart(m, "Mote", BALL, Vector3.one * (.12 + (i % 3) * .05), CF(math.cos(a) * (.5 + i * .09), 1.9 + (i % 4) * .26, math.sin(a) * .5), C3(255, 226, 150), NEON)
	end
	ipart(m, "Spill", CYL, V3(.12, 1.1, 1.1), CF(.9, .06, .5) * CYL_UP, C3(255, 214, 120), NEON, { Transparency = .25 })
end
ICONS.Shards = function(m) -- a cracked bronze bell and its floating shards
	local bronze = C3(176, 128, 64)
	ipart(m, "BellBody", CYL, V3(1.1, 1.3, 1.3), CF(0, .9, 0) * CYL_UP, bronze, METAL)
	ipart(m, "BellShoulder", BALL, V3(1.3, 1.1, 1.3), CF(0, 1.45, 0), bronze, METAL)
	ipart(m, "BellLip", CYL, V3(.24, 1.75, 1.75), CF(0, .32, 0) * CYL_UP, bronze:Lerp(BLACK, .2), METAL)
	ipart(m, "BellCrown", CYL, V3(.16, .5, .5), CF(0, 2.05, 0), bronze:Lerp(BLACK, .3), METAL)
	ipart(m, "Crack", nil, V3(.07, 1.25, .07), CF(.3, 1.0, -.66) * ANG(0, 0, .35), VIOLET_HOT, NEON)
	ipart(m, "Crack", nil, V3(.07, .55, .07), CF(.12, .55, -.69) * ANG(0, 0, -.5), VIOLET_HOT, NEON)
	for i, o in ipairs({ V3(1.15, 1.7, .2), V3(-1.1, 1.3, -.3), V3(.6, 2.4, .5) }) do
		local w = Instance.new("WedgePart")
		w.Name = "Shard"
		w.Size = V3(.12, .55 - i * .06, .4)
		w.CFrame = CF(o) * ANG(i * .7, i * 1.3, i * .4)
		w.Color = bronze
		w.Material = METAL
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
		w.Parent = m
		ipart(m, "ShardGlow", BALL, Vector3.one * .16, CF(o), VIOLET_HOT, NEON)
	end
end
ICONS.Bones = function(m) -- two crossed bones
	for _, a in ipairs({ .62, -.62 }) do
		local base = CF(0, .9, 0) * ANG(0, 0, a)
		ipart(m, "Shaft", CYL, V3(2.3, .34, .34), base, BONE)
		for _, x in ipairs({ -1.18, 1.18 }) do
			for _, z in ipairs({ -.15, .15 }) do
				ipart(m, "Knob", BALL, Vector3.one * .48, base * CF(x, z, 0), BONE)
			end
		end
	end
end
ICONS.Cash = function(m) -- a stack of gold coins
	local gold = C3(246, 196, 64)
	for i = 0, 4 do
		ipart(m, "Coin", CYL, V3(.18, 1.3, 1.3), CF((i % 2) * .05, .1 + i * .19, (i % 3) * .04) * CYL_UP, gold, METAL)
	end
	ipart(m, "CoinFace", CYL, V3(.02, .8, .8), CF(0, 1.06, 0) * CYL_UP, gold:Lerp(C3(255, 240, 180), .5), NEON, { Transparency = .3 })
	ipart(m, "LeaningCoin", CYL, V3(.18, 1.3, 1.3), CF(1.05, .62, .1) * ANG(0, 0, .25), gold, METAL)
end
ICONS.Fragments = function(m) -- cloth scraps fanned like cards, stitched, with a needle and thread
	for i, c in ipairs({ C3(96, 40, 130), C3(220, 210, 186), C3(140, 136, 160) }) do
		local base = CF((i - 2) * .45, 1.0 + (i % 2) * .15, (i - 2) * -.08) * ANG(-1.25, 0, (i - 2) * .38)
		ipart(m, "Scrap", nil, V3(1.2, .07, 1.4), base, c, FABRIC)
		ipart(m, "Stitch", nil, V3(.95, .09, .05), base * CF(0, .01, .45), C3(236, 196, 92), FABRIC)
		ipart(m, "Stitch", nil, V3(.05, .09, .9), base * CF(.45, .01, 0), C3(236, 196, 92), FABRIC)
	end
	ipart(m, "Needle", CYL, V3(1.6, .07, .07), CF(.3, 1.25, -.4) * ANG(0, .3, .7), C3(210, 210, 220), METAL)
	ipart(m, "Thread", CYL, V3(1.2, .03, .03), CF(-.2, .7, -.45) * ANG(0, .2, -.4), C3(236, 196, 92), FABRIC)
end
ICONS.Key = function(m) -- an ornate coffin key with a violet gem
	local iron = C3(150, 146, 162)
	local bow = CF(0, 2.1, 0)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		ipart(m, "Bow", nil, V3(.18, .44, .18), bow * CF(math.cos(a) * .5, math.sin(a) * .5, 0) * ANG(0, 0, a), iron, METAL)
	end
	ipart(m, "Gem", BALL, Vector3.one * .42, bow, VIOLET_HOT, NEON)
	ipart(m, "Collar", CYL, V3(.16, .36, .36), CF(0, 1.5, 0) * CYL_UP, iron, METAL)
	ipart(m, "Shaft", CYL, V3(1.6, .2, .2), CF(0, .7, 0) * CYL_UP, iron, METAL)
	ipart(m, "Bit", nil, V3(.42, .14, .12), CF(.25, .1, 0), iron, METAL)
	ipart(m, "Bit", nil, V3(.3, .14, .12), CF(.2, .34, 0), iron, METAL)
end
ICONS.Title = function(m) -- a small crown
	local gold = C3(246, 196, 64)
	ipart(m, "Band", CYL, V3(.45, 1.5, 1.5), CF(0, .3, 0) * CYL_UP, gold, METAL)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		ipart(m, "Spike", nil, V3(.18, .7, .18), CF(math.cos(a) * .62, .85, math.sin(a) * .62), gold, METAL)
		ipart(m, "Jewel", BALL, Vector3.one * .2, CF(math.cos(a) * .62, 1.25, math.sin(a) * .62), VIOLET_HOT, NEON)
	end
end
ICONS.Candy = function(m)
	ipart(m, "Candy", BALL, V3(1.3, 1.1, 1.1), CF(0, .8, 0), C3(255, 140, 60))
	for _, x in ipairs({ -1, 1 }) do
		ipart(m, "Twist", nil, V3(.5, .6, .2), CF(x * .85, .8, 0) * ANG(0, 0, x * .5), C3(255, 210, 90))
	end
end
ICONS.Unknown = function(m)
	ipart(m, "Orb", BALL, Vector3.one * 1.4, CF(0, .8, 0), VIOLET, NEON, { Transparency = .2 })
	ipart(m, "Core", BALL, Vector3.one * .7, CF(0, .8, 0), WHITE, NEON)
end

-- a dark voxel dog for a dog whose menu model is not in this place
local function silhouetteDog(m: Model, color: Color3)
	ipart(m, "Body", nil, V3(1.2, 1.1, 2.4), CF(0, 1.5, 0), color)
	ipart(m, "Chest", nil, V3(1.1, 1.0, .8), CF(0, 1.75, -1.15), color)
	ipart(m, "Head", nil, V3(1.0, .95, 1.0), CF(0, 2.5, -1.55), color)
	ipart(m, "Snout", nil, V3(.6, .45, .55), CF(0, 2.3, -2.25), color)
	for _, x in ipairs({ -.33, .33 }) do
		ipart(m, "Ear", nil, V3(.22, .55, .3), CF(x, 3.1, -1.45) * ANG(0, 0, x * .6), color)
		ipart(m, "Eye", BALL, Vector3.one * .16, CF(x * .8, 2.6, -2.06), VIOLET_HOT, NEON)
		for _, z in ipairs({ -.9, .9 }) do
			ipart(m, "Leg", nil, V3(.34, 1.0, .34), CF(x * 1.25, .5, z), color)
		end
	end
	ipart(m, "Tail", nil, V3(.2, .2, .9), CF(0, 2.0, 1.45) * ANG(.7, 0, 0), color)
end

local function prepare(model: Model): Model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Sound")
			or d:IsA("BillboardGui") or d:IsA("Humanoid") then
			d:Destroy()
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	return model
end

local function icon(kind: string): Model
	local m = Instance.new("Model")
	m.Name = "CoffinIcon_" .. kind
	local build = ICONS[kind] or ICONS.Unknown
	local ok, err = pcall(build, m)
	if not ok then
		warnOnce("icon" .. kind, tostring(err))
		m:ClearAllChildren()
		ICONS.Unknown(m)
	end
	return prepare(m)
end

local function dogModel(id: string): Model?
	local folder = RS:FindFirstChild("MenuModels")
	local src = folder and folder:FindFirstChild(id)
	if src and src:IsA("Model") then
		return src:Clone()
	end
	return nil
end

-- -> a fresh display model of the reward, and whether it is the real thing (false = icon / silhouette)
function CoffinFX.BuildReward(row: any): (Model?, boolean)
	row = type(row) == "table" and row or {}
	local kind, id = row.Kind, row.Id
	local ok, model = pcall(function(): Model?
		if type(id) ~= "string" then
			return nil
		end
		if kind == "Dog" then
			return dogModel(id)
		elseif kind == "Find" then
			local inst = RS:FindFirstChild("DogEconomy") and RS.DogEconomy:FindFirstChild("DiscoveryVisuals")
			return inst and require(inst :: any).Clone({ ItemId = id }, { NoScale = true }) or nil
		elseif kind == "Decor" then
			local inst = RS:FindFirstChild("Decor") and RS.Decor:FindFirstChild("DecorModels")
			return inst and require(inst :: any).Get(id) or nil
		elseif kind == "Skin" then
			local inst = Halloween:FindFirstChild("PickaxeSkins")
			return inst and require(inst :: any).Build(id) or nil
		end
		return nil
	end)
	if not ok then
		warnOnce("reward" .. tostring(kind), tostring(model))
	end
	if ok and model and typeof(model) == "Instance" and model:IsA("Model") then
		return prepare(model), true
	end
	if kind == "Dog" then
		local m = Instance.new("Model")
		m.Name = "CoffinDogSilhouette"
		silhouetteDog(m, C3(30, 22, 44))
		return prepare(m), false
	end
	return icon(type(kind) == "string" and ICONS[kind] ~= nil and kind or "Unknown"), false
end

-- scale a model so its largest side is `size` (when the engine can), -> its bounding size afterwards
local function fit(model: Model, size: number): Vector3
	local ok, _, ext = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and typeof(ext) == "Vector3" then
		local big = math.max(ext.X, ext.Y, ext.Z)
		if big > 1e-3 and math.abs(big - size) > 1e-3 then
			pcall(function()
				(model :: any):ScaleTo((model :: any):GetScale() * size / big)
			end)
		end
		local ok2, _, ext2 = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok2 and typeof(ext2) == "Vector3" then
			return ext2
		end
		return ext
	end
	return Vector3.one * size
end

-- the model's pivot relative to its bounding-box centre (so it can spin about its middle)
local function centreOffset(model: Model): CFrame
	local ok, bb = pcall(function()
		return model:GetBoundingBox()
	end)
	local pivot = model:GetPivot()
	if ok and typeof(bb) == "CFrame" then
		return CFrame.new(bb.Position):Inverse() * CFrame.new(pivot.Position) * pivot.Rotation
	end
	return pivot.Rotation
end

---------------------------------------------------------------------------------------------------------------------
-- The coffin rig (the baked model; client-local changes only, everything recorded and restored)
---------------------------------------------------------------------------------------------------------------------
local function underyardRoot(): Instance?
	local district = workspace:FindFirstChild("DOGROTS_District")
	return district and district:FindFirstChild("40_Underyard") or nil
end
local function findCoffin(): Model?
	local root = underyardRoot()
	local m = root and root:FindFirstChild(CC.Model.Name)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end
CoffinFX.FindCoffin = findCoffin

local function partsOf(inst: Instance?): { BasePart }
	local out = {}
	if not inst then
		return out
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function collectRig(model: Model): any
	local A = CC.Attr
	local rig: any = { Model = model, Seams = {}, Inner = {}, Runes = {}, Chains = {}, Flames = {}, MaxOrder = 1 }
	local seat = model:GetAttribute(A.Seat)
	if typeof(seat) ~= "CFrame" then
		local pivot = model:FindFirstChild("CoffinPivot")
		seat = (pivot and pivot:IsA("BasePart")) and pivot.CFrame or model:GetPivot()
	end
	rig.Seat = seat
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") then
			if d:GetAttribute(A.Lid) then
				rig.LidModel = d
			elseif d:GetAttribute(A.Chain) ~= nil then
				local k = tonumber(d:GetAttribute(A.Chain))
				if k then
					rig.Chains[k] = { Model = d, Parts = {}, Anchor = d:GetAttribute("Anchor") }
				end
			elseif d:GetAttribute(A.Padlock) then
				rig.PadlockModel = d
			elseif d:GetAttribute(A.Candle) then
				rig.CandleModel = d
			end
		elseif d:IsA("BasePart") then
			local order = d:GetAttribute(A.Seam)
			if order ~= nil then
				local o = tonumber(order) or 1
				rig.MaxOrder = math.max(rig.MaxOrder, o)
				table.insert(rig.Seams, { Part = d, Order = o, T0 = d.Transparency, C0 = d.Color })
			elseif d:GetAttribute(A.Inner) then
				table.insert(rig.Inner, { Part = d, T0 = d.Transparency, C0 = d.Color })
			elseif d:GetAttribute(A.Rune) then
				table.insert(rig.Runes, { Part = d, T0 = d.Transparency, C0 = d.Color })
			end
		elseif d:IsA("PointLight") and d:GetAttribute(A.Light) then
			rig.Light = { Light = d, Enabled = d.Enabled, Brightness = d.Brightness, Color = d.Color }
		end
	end
	-- the lid: every part relative to its hinge
	local lid = rig.LidModel
	if lid then
		local hinge = lid.PrimaryPart or lid:FindFirstChild("LidHinge")
		if hinge and hinge:IsA("BasePart") then
			local parts, rel, cfs = {}, {}, {}
			for _, p in ipairs(partsOf(lid)) do
				table.insert(parts, p)
				table.insert(cfs, p.CFrame)
				table.insert(rel, hinge.CFrame:ToObjectSpace(p.CFrame))
			end
			rig.Lid = { Hinge = hinge.CFrame, Parts = parts, Rel = rel, Closed = cfs,
				Angle = math.rad(tonumber(lid:GetAttribute("OpenAngle")) or CC.Model.OpenAngle) }
		end
	end
	for _, ch in pairs(rig.Chains) do
		ch.Parts = partsOf(ch.Model)
		ch.Base = {}
		for i, p in ipairs(ch.Parts) do
			ch.Base[i] = p.CFrame
		end
		if typeof(ch.Anchor) ~= "Vector3" then
			local first = ch.Parts[1]
			ch.Anchor = first and first.Position or rig.Seat.Position
		end
	end
	rig.Padlock = partsOf(rig.PadlockModel)
	-- candles: the coffin's own set + the shrine's stands (WP-G CoffinShrine)
	local function addFlame(p: BasePart)
		if p:GetAttribute("HwCandle") == true and (p.Position - rig.Seat.Position).Magnitude < 10 then
			table.insert(rig.Flames, p)
		end
	end
	for _, p in ipairs(partsOf(rig.CandleModel)) do
		addFlame(p)
	end
	local root = underyardRoot()
	local square = root and root:FindFirstChild("BellSquare")
	local shrine = square and square:FindFirstChild("CoffinShrine")
	for _, p in ipairs(partsOf(shrine)) do
		addFlame(p)
	end
	return rig
end

local function seatPoint(rig: any, local3: Vector3): Vector3
	return (rig.Seat :: CFrame) * local3
end

-- the lid at angle `a` (radians about the hinge's Z), lifted `lift` studs and twisted `twist` radians (the rattle)
local function poseLid(rig: any, a: number, lift: number?, twist: number?)
	local L = rig.Lid
	if not L then
		return
	end
	local h = L.Hinge * CF(0, lift or 0, 0) * ANG(0, twist or 0, 0) * ANG(0, 0, a)
	local cfs = table.create(#L.Parts)
	for i, rel in ipairs(L.Rel) do
		cfs[i] = h * rel
	end
	moveParts(L.Parts, cfs)
end

local function setLTM(parts: { BasePart }, v: number)
	for _, p in ipairs(parts) do
		p.LocalTransparencyModifier = v
	end
end

local function restoreRig(rig: any)
	if not rig then
		return
	end
	local L = rig.Lid
	if L then
		safe("restoreLid", moveParts, L.Parts, L.Closed)
	end
	for _, ch in pairs(rig.Chains) do
		safe("restoreChain", function()
			moveParts(ch.Parts, ch.Base)
			setLTM(ch.Parts, 0)
		end)
	end
	safe("restorePadlock", setLTM, rig.Padlock, 0)
	safe("restoreFlames", setLTM, rig.Flames, 0)
	for _, list in ipairs({ rig.Seams, rig.Inner, rig.Runes }) do
		for _, s in ipairs(list) do
			safe("restoreGlow", function()
				s.Part.Transparency = s.T0
				s.Part.Color = s.C0
			end)
		end
	end
	if rig.Light then
		safe("restoreLight", function()
			local l = rig.Light
			l.Light.Enabled = l.Enabled
			l.Light.Brightness = l.Brightness
			l.Light.Color = l.Color
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Scene helpers (client-local parts under workspace.DOGROTS_CoffinFX, destroyed with the show)
---------------------------------------------------------------------------------------------------------------------
local function fxFolder(): Folder
	local f = workspace:FindFirstChild("DOGROTS_CoffinFX")
	if f and f:IsA("Folder") then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = "DOGROTS_CoffinFX"
	folder:SetAttribute("SelfManagedFX", true)
	folder.Parent = workspace
	return folder
end

local function spart(show: any, props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = NEON
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or show.Scene
	return p
end
local function slight(show: any, parent: Instance, color: Color3, range: number, brightness: number): PointLight?
	if show.LightBudget <= 0 then
		return nil
	end
	show.LightBudget -= 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end
local function burst(show: any, pos: Vector3, opts: { [string]: any })
	if show.Late then
		return
	end
	local f = fx()
	if f and f.Burst then
		local o = table.clone(opts)
		o.Count = math.max(1, math.floor((o.Count or 18) * (show.Near and CC.Show.Near.Particles or 1) + .5))
		safe("burst", f.Burst, pos, o)
	end
end

-- tumbling pieces (flying chain links, the padlock) integrated in the show loop
local function fling(show: any, part: BasePart, vel: Vector3, spin: Vector3, life: number, floor: number)
	table.insert(show.Debris, { Part = part, V = vel, R = spin, T = 0, Life = life, Floor = floor, Base = part.Transparency })
end
local function stepDebris(show: any, dt: number)
	for i = #show.Debris, 1, -1 do
		local c = show.Debris[i]
		c.T += dt
		local p = c.Part
		if c.T >= c.Life or not p.Parent then
			if p.Parent then
				p:Destroy()
			end
			table.remove(show.Debris, i)
		else
			c.V += Vector3.new(0, -60 * dt, 0)
			local pos = p.Position + c.V * dt
			if pos.Y < c.Floor then
				pos = Vector3.new(pos.X, c.Floor, pos.Z)
				c.V = Vector3.new(c.V.X * .45, math.abs(c.V.Y) * .3, c.V.Z * .45)
				c.R *= .6
			end
			p.CFrame = CF(pos) * p.CFrame.Rotation * ANG(c.R.X * dt, c.R.Y * dt, c.R.Z * dt)
			local fade = math.clamp((c.T - c.Life * .65) / (c.Life * .35), 0, 1)
			p.Transparency = c.Base + (1 - c.Base) * fade
		end
	end
end

-- a forked lightning bolt from the sky to `target` (Mythic)
local function bolt(show: any, target: Vector3, color: Color3)
	local rng = show.Rng
	local top = target + Vector3.new(rng:NextNumber(-8, 8), CC.Show.Lightning.Height, rng:NextNumber(-8, 8))
	local n = lowQuality() and 6 or 10
	local pts = { top }
	for i = 1, n - 1 do
		local base = top:Lerp(target, i / n)
		local j = 2.4 * (1 - i / n) + .6
		table.insert(pts, base + Vector3.new(rng:NextNumber(-j, j), 0, rng:NextNumber(-j, j)))
	end
	table.insert(pts, target)
	local parts = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local cf = CFrame.lookAt((a + b) / 2, b)
		table.insert(parts, spart(show, { Name = "Bolt", Size = Vector3.new(.32, .32, (b - a).Magnitude + .2), CFrame = cf, Color = WHITE }))
		if not lowQuality() then
			table.insert(parts, spart(show, { Name = "BoltGlow", Size = Vector3.new(1.1, 1.1, (b - a).Magnitude + .4), CFrame = cf, Color = color,
				Transparency = .55 }))
		end
	end
	local anchor = spart(show, { Name = "BoltLight", Size = Vector3.one * .2, CFrame = CF(target + UP * 2), Transparency = 1 })
	local light = slight(show, anchor, color:Lerp(WHITE, .5), 40, 8)
	table.insert(parts, anchor)
	table.insert(show.Bolts, { Parts = parts, Light = light, T = 0, Life = .42 })
	burst(show, target + UP * .5, { Color = WHITE, Color2 = color, Count = 26, Speed = { 8, 20 }, Lifetime = { .25, .6 }, Size = { .5, .8, 0 },
		Spread = 70, Direction = UP })
	cue(show, "Thunder", target, .9)
	local c = cinema()
	if c and not show.Near and not reduced() then
		safe("flash", c.Flash, color:Lerp(WHITE, .7), .45, .22)
	end
end
local function stepBolts(show: any, dt: number)
	for i = #show.Bolts, 1, -1 do
		local b = show.Bolts[i]
		b.T += dt
		local k = b.T / b.Life
		-- two flickers then gone
		local vis = (k < .25 or (k > .4 and k < .62)) and 0 or (k < 1 and .7 or 1)
		for _, p in ipairs(b.Parts) do
			if p.Name == "Bolt" then
				p.Transparency = vis
			elseif p.Name == "BoltGlow" then
				p.Transparency = .55 + .45 * vis
			end
		end
		if b.Light then
			b.Light.Brightness = 8 * (1 - math.clamp(k, 0, 1))
		end
		if k >= 1 then
			for _, p in ipairs(b.Parts) do
				p:Destroy()
			end
			table.remove(show.Bolts, i)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The card (the opener): rarity banner, the 3D reward, NEW / the conversion, bonus rows, CONTINUE / OPEN AGAIN
---------------------------------------------------------------------------------------------------------------------
local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextScaled = true
	l.TextColor3 = BONE
	l.TextWrapped = true
	l.Active = false
	l:SetAttribute("NoTranslate", true)
	for k, v in pairs(props) do
		if k ~= "Max" and k ~= "Min" then
			(l :: any)[k] = v
		end
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = props.Max or 28
	c.MinTextSize = props.Min or 10
	c.Parent = l
	l.Parent = parent
	return l
end
local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end
local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function button(parent: Instance, text: string, color: Color3, primary: boolean): TextButton
	local b = Instance.new("TextButton")
	b.Name = primary and "Continue" or "OpenAgain"
	b.AutoButtonColor = true
	b.Active = true
	b.Selectable = true
	b.BackgroundColor3 = primary and color or PANEL_DARK
	b.FontFace = FONT
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = primary and PANEL_DARK or BONE
	b:SetAttribute("NoTranslate", true)
	corner(b, 12)
	stroke(b, color, 2, primary and .4 or 0)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 22
	c.MinTextSize = 11
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = parent
	return b
end
local function chip(parent: Instance, text: string, color: Color3, order: number, width: number): Frame
	local f = Instance.new("Frame")
	f.Name = "Chip"
	f.LayoutOrder = order
	f.Size = UDim2.new(0, width, 1, 0)
	f.BackgroundColor3 = color:Lerp(PANEL_DARK, .7)
	f.BackgroundTransparency = .1
	f.Active = false
	corner(f, 10)
	stroke(f, color, 1.5, .25)
	label(f, { Name = "Text", Text = text, Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), TextColor3 = color:Lerp(WHITE, .45),
		Max = 18 })
	f.Parent = parent
	return f
end

local function screenSize(): Vector2
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	if typeof(v) == "Vector2" and v.X > 10 and v.Y > 10 then
		return v
	end
	return Vector2.new(1280, 720)
end

local function openRequest(show: any)
	local state = cs()
	if not state or not state.Request then
		return
	end
	task.spawn(function()
		local ok, res = state.Request(CC.Request.Action, {})
		if not ok then
			CoffinFX.Refused({ Text = type(res) == "string" and res or "Something went wrong, try again" })
		end
	end)
end

local function affordAgain(payload: any): boolean
	if payload.Preview then
		return false
	end
	local price = Cfg.Coffin.Price
	if (tonumber(payload.Keys) or 0) < price.Keys or (tonumber(payload.Shards) or 0) < price.Shards then
		return false
	end
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local anchor = Layout.Anchor and Layout.Anchor(CC.Anchor)
	if typeof(anchor) ~= "Vector3" then
		anchor = Layout.Square.CoffinShrine.Position
	end
	return root ~= nil and ((root :: BasePart).Position - anchor).Magnitude <= CC.Radius + Cfg.Proximity.Slack
end

-- -> card {Gui, Close(reason), Closed (bool), Model, Viewport}
local function buildCard(show: any): any
	local payload = show.Payload
	local rows = type(payload.Rows) == "table" and payload.Rows or { payload.Main }
	local main = type(payload.Main) == "table" and payload.Main or rows[1] or {}
	local rank = show.Rank
	local color = show.Color
	local kicker = payload.Preview and T("PREVIEW · NOTHING GRANTED") or payload.Forced and T("YOUR FIRST BLACK COFFIN") or T("THE BLACK COFFIN")
	if show.Beats and show.Beats.Secret and payload.Arrival and #rows > 1 then
		-- the Hollow King had his own arrival: this card only shows what else the coffin gave
		main = rows[2]
		rows = { table.unpack(rows, 2) }
		rank = math.clamp(math.floor(tonumber(main.Rank) or 2), 1, 6)
		color = rarityColor(rank)
		kicker = T("ALSO FROM THE BLACK COFFIN")
	end
	local info = CoffinFX.Describe(main)
	local card: any = { Closed = false, Conns = {} }
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "DOGROTS_CoffinCard"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 92
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g:SetAttribute("NoTranslate", true)
	g:SetAttribute("CinemaKeep", true)
	card.Gui = g
	local screen = screenSize()
	local wide = screen.X > screen.Y * 1.25 and screen.Y < 560
	local W = wide and math.min(760, screen.X - 32) or math.min(440, screen.X - 32)
	local H = wide and math.min(360, screen.Y - 24) or math.min(620, screen.Y - 40)
	-- the dim behind the card (visual only: never input-sinking)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = PANEL_DARK
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Parent = g
	tween(dim, .35, { BackgroundTransparency = .55 })
	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.AnchorPoint = Vector2.new(.5, .5)
	frame.Position = UDim2.fromScale(.5, .5)
	frame.Size = UDim2.fromOffset(W, H)
	frame.BackgroundColor3 = PANEL
	frame.Active = false
	corner(frame, 18)
	stroke(frame, color, 3)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(PANEL:Lerp(color, .18), PANEL_DARK)
	grad.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = reduced() and 1 or .82
	scale.Parent = frame
	frame.Parent = g
	card.Frame = frame
	if not reduced() then
		tween(scale, .45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	-- columns: the viewport (left on wide screens, top otherwise) and the text
	local pad = 16
	local viewSize = wide and (H - pad * 2) or math.min(W - pad * 2, H * .42)
	local textX = wide and (viewSize + pad * 2) or pad
	local textW = wide and (W - viewSize - pad * 3) or (W - pad * 2)
	local y = pad
	label(frame, { Name = "Kicker", Text = kicker, Size = UDim2.fromOffset(textW, 20), Position = UDim2.fromOffset(textX, y),
		TextColor3 = BONE:Lerp(color, .25), Max = 16 })
	y += 24
	-- the rarity banner (a ribbon in the rarity colour)
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.fromOffset(textW, 42)
	banner.Position = UDim2.fromOffset(textX, y)
	banner.BackgroundColor3 = color
	banner.Active = false
	corner(banner, 10)
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color:Lerp(WHITE, .35)), ColorSequenceKeypoint.new(.5, color),
		ColorSequenceKeypoint.new(1, color:Lerp(BLACK, .35)) })
	bg.Parent = banner
	banner.Parent = frame
	label(banner, { Name = "Rarity", Text = rarityLabel(rank), Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3),
		TextColor3 = PANEL_DARK, Max = 30 })
	y += 50
	-- the 3D reward: a tinted well, a soft halo in the rarity colour behind the model, the ViewportFrame on top
	local viewPos = wide and UDim2.fromOffset(pad, pad) or UDim2.fromOffset((W - viewSize) / 2, y)
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.fromOffset(viewSize, viewSize)
	well.Position = viewPos
	well.BackgroundColor3 = color:Lerp(PANEL_DARK, .82)
	well.BackgroundTransparency = .15
	well.ZIndex = 1
	well.Active = false
	corner(well, 14)
	stroke(well, color, 1.5, .5)
	well.Parent = frame
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(.5, .5)
	glow.Position = UDim2.fromScale(.5, .52)
	glow.Size = UDim2.fromScale(.74, .74)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = .8
	glow.ZIndex = 1
	glow.Active = false
	corner(glow, 999)
	local halo = Instance.new("UIGradient")
	halo.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.6, .35), NumberSequenceKeypoint.new(1, 1) })
	halo.Parent = glow
	glow.Parent = well
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Reward"
	vf.Size = UDim2.fromOffset(viewSize, viewSize)
	vf.Position = viewPos
	vf.BackgroundTransparency = 1
	vf.Ambient = C3(150, 140, 170)
	vf.LightColor = WHITE
	vf.LightDirection = Vector3.new(-.4, -1, -.6)
	vf.ZIndex = 2
	vf.Active = false
	vf.Parent = frame
	card.Viewport = vf
	local vcam = Instance.new("Camera")
	vcam.Name = "Camera"
	vcam.FieldOfView = 30
	vcam.Parent = vf
	vf.CurrentCamera = vcam
	local model = CoffinFX.BuildReward(main)
	if model then
		local ext = fit(model, 4)
		local off = centreOffset(model)
		model:PivotTo(CF(0, 0, 0) * off)
		model.Parent = vf
		local dist = (math.max(ext.X, ext.Y, ext.Z) * .62) / math.tan(math.rad(vcam.FieldOfView / 2)) + 1
		vcam.CFrame = CFrame.lookAt(Vector3.new(0, dist * .22, -dist), Vector3.zero)
		card.Model = model
		card.Offset = off
	end
	if not wide then
		y += viewSize + 8
	end
	-- name, sub line, amount
	local nameH = wide and 44 or 38
	label(frame, { Name = "Title", Text = info.Title or "", Size = UDim2.fromOffset(textW, nameH), Position = UDim2.fromOffset(textX, y),
		TextColor3 = WHITE, Max = 34 })
	y += nameH + 2
	label(frame, { Name = "Sub", Text = info.Amount and (info.Amount .. "  ·  " .. (info.Sub or "")) or (info.Sub or ""),
		Size = UDim2.fromOffset(textW, 22), Position = UDim2.fromOffset(textX, y), TextColor3 = color:Lerp(WHITE, .5), Max = 20 })
	y += 28
	-- NEW / the conversion
	if info.Status then
		local st = label(frame, { Name = "Status", Text = info.Status, Size = UDim2.fromOffset(textW, 24), Position = UDim2.fromOffset(textX, y),
			TextColor3 = main.Converted and C3(255, 196, 110) or C3(140, 255, 170), Max = 20 })
		card.Status = st
		y += 28
	end
	local chipRow = Instance.new("Frame")
	chipRow.Name = "Conversion"
	chipRow.BackgroundTransparency = 1
	chipRow.Size = UDim2.fromOffset(textW, 30)
	chipRow.Position = UDim2.fromOffset(textX, y)
	chipRow.Active = false
	chipRow.Parent = frame
	card.Chips = {}
	local n = #info.Chips
	local cw = n == 1 and math.min(textW, 240) or math.floor((textW - 8 * (n - 1)) / math.max(1, n))
	local x0 = n == 1 and math.floor((textW - cw) / 2) or 0
	local short = cw < 150 -- a narrow chip shows the currency's icon instead of its name
	for i, text in ipairs(info.Chips) do
		local c = chip(chipRow, short and info.Short[i] or text, C3(255, 196, 110), i, cw)
		c.Position = UDim2.fromOffset(x0 + (i - 1) * (cw + 8), 0)
		c.Visible = false
		table.insert(card.Chips, c)
	end
	if #info.Chips > 0 then
		y += 36
	end
	-- the bonus rows (H16 crown, H12 pug)
	for i = 2, #rows do
		local r = rows[i]
		local d = CoffinFX.Describe(r)
		local who = r.Bonus == "Crown" and T("CROWN OF THE UNDERYARD") or r.Bonus == "Pug" and T("COFFIN SENSE") or T("BONUS")
		local text = who .. ": " .. (d.Title or "") .. (r.Converted and #d.Chips > 0 and ("  →  " .. table.concat(d.Chips, " · ")) or "")
		local holder = Instance.new("Frame")
		holder.Name = "Bonus"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(textW, 28)
		holder.Position = UDim2.fromOffset(textX, y)
		holder.Active = false
		holder.Parent = frame
		chip(holder, text, VIOLET_HOT, i, textW)
		y += 34
	end
	-- the wallet + the buttons
	local footY = H - pad - 48
	local wallet = F("COFFIN KEYS %d  ·  BELL SHARDS %s", tonumber(payload.Keys) or 0, Shared.Format(tonumber(payload.Shards) or 0))
	label(frame, { Name = "Wallet", Text = wallet, Size = UDim2.fromOffset(textW, 18), Position = UDim2.fromOffset(textX, footY - 22),
		TextColor3 = BONE:Lerp(PANEL, .3), Max = 15 })
	local again = affordAgain(payload)
	local bw = again and math.floor((textW - 10) / 2) or textW
	local cont = button(frame, T("CONTINUE"), color, true)
	cont.Size = UDim2.fromOffset(bw, 48)
	cont.Position = UDim2.fromOffset(textX + (again and bw + 10 or 0), footY)
	card.Continue = cont
	if again then
		local ag = button(frame, T("OPEN AGAIN"), color, false)
		ag.Size = UDim2.fromOffset(bw, 48)
		ag.Position = UDim2.fromOffset(textX, footY)
		card.Again = ag
		table.insert(card.Conns, ag.Activated:Connect(function()
			if card.Closed then
				return
			end
			card.Close("Again")
			openRequest(show)
		end))
	end
	table.insert(card.Conns, cont.Activated:Connect(function()
		card.Close("Continue")
	end))
	pcall(function()
		local GuiService = game:GetService("GuiService")
		if game:GetService("UserInputService").GamepadEnabled then
			GuiService.SelectedObject = cont
		end
	end)
	-- the conversion plays out: the stamp, then the chips pop in
	if main.Converted then
		task.delay(reduced() and .2 or .9, function()
			if card.Closed then
				return
			end
			if card.Viewport then
				tween(card.Viewport, .5, { ImageTransparency = .55 })
			end
			for i, c in ipairs(card.Chips) do
				task.delay((i - 1) * .3, function()
					if not card.Closed and c.Parent then
						c.Visible = true
						cue(nil, "CandyTick", nil, .5, { Pitch = 1 + i * .08 })
					end
				end)
			end
		end)
	else
		for _, c in ipairs(card.Chips) do
			c.Visible = true
		end
	end
	function card.Close(reason: string?)
		if card.Closed then
			return
		end
		card.Closed = true
		card.Reason = reason or "Close"
		for _, c in ipairs(card.Conns) do
			c:Disconnect()
		end
		if g.Parent then
			if not reduced() then
				tween(scale, .2, { Scale = .9 })
			end
			tween(dim, .2, { BackgroundTransparency = 1 })
			task.delay(.22, function()
				g:Destroy()
			end)
		end
		if State.Card == card then
			State.Card = nil
		end
	end
	g.Parent = pg
	card.ShownAt = os.clock()
	State.Card = card
	return card
end

---------------------------------------------------------------------------------------------------------------------
-- Name plate over the coffin (the lighter version) and the banners (Secret fallback / omen)
---------------------------------------------------------------------------------------------------------------------
local function namePlate(show: any)
	local main = show.Payload.Main or {}
	local info = CoffinFX.Describe(main)
	local anchor = spart(show, { Name = "PlateAnchor", Size = Vector3.one * .2, Transparency = 1,
		CFrame = CF(seatPoint(show.Rig, Vector3.new(0, CC.Show.RiseHeight + 3.2, 0))) })
	local g = Instance.new("BillboardGui")
	g.Name = "CoffinNamePlate"
	g.Size = UDim2.fromOffset(300, 74)
	g.LightInfluence = 0
	g.MaxDistance = CC.NearRadius
	g.AlwaysOnTop = false
	g.Adornee = anchor
	g:SetAttribute("NoTranslate", true)
	label(g, { Name = "Who", Text = upper(tostring(show.Payload.Name or "")), Size = UDim2.new(1, 0, 0, 22), TextColor3 = BONE,
		TextStrokeTransparency = .3, Max = 20 })
	label(g, { Name = "What", Text = rarityLabel(show.Rank) .. " · " .. (info.Title or ""), Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 24), TextColor3 = show.Color:Lerp(WHITE, .25), TextStrokeTransparency = .2, Max = 28 })
	g.Parent = anchor
	show.Plate = g
end

local bannerGui: ScreenGui? = nil
-- a top banner: kicker line, main line, sub line; fades after `hold` seconds
local function banner(main: string, kicker: string?, sub: string?, color: Color3, hold: number): any
	local handle: any = { Alive = true }
	local ok, err = pcall(function()
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		if bannerGui and bannerGui.Parent then
			bannerGui:Destroy()
		end
		local g = Instance.new("ScreenGui")
		g.Name = "DOGROTS_CoffinBanner"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 93
		g:SetAttribute("NoTranslate", true)
		g:SetAttribute("CinemaKeep", true)
		bannerGui = g
		local f = Instance.new("Frame")
		f.Name = "Banner"
		f.AnchorPoint = Vector2.new(.5, 0)
		f.Position = UDim2.new(.5, 0, 0, 70)
		f.Size = UDim2.new(.92, 0, 0, 112)
		f.BackgroundTransparency = 1
		f.Active = false
		f.Parent = g
		local back = Instance.new("Frame")
		back.Name = "Back"
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = PANEL_DARK
		back.BackgroundTransparency = .25
		back.Active = false
		corner(back, 16)
		stroke(back, color, 2, .2)
		back.Parent = f
		local texts = {}
		table.insert(texts, label(f, { Name = "Kicker", Text = kicker or "", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 8),
			TextColor3 = color:Lerp(WHITE, .4), Max = 18 }))
		table.insert(texts, label(f, { Name = "Main", Text = main, Size = UDim2.new(1, -24, 0, 46), Position = UDim2.fromOffset(12, 32),
			TextColor3 = WHITE, TextStrokeTransparency = .4, Max = 40 }))
		table.insert(texts, label(f, { Name = "Sub", Text = sub or "", Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 82),
			TextColor3 = BONE, Max = 16 }))
		for _, t in ipairs(texts) do
			t.TextTransparency = 1
			tween(t, .5, { TextTransparency = 0 })
		end
		back.BackgroundTransparency = 1
		tween(back, .5, { BackgroundTransparency = .25 })
		g.Parent = pg
		handle.Gui = g
		function handle.Hide()
			if not handle.Alive then
				return
			end
			handle.Alive = false
			for _, t in ipairs(texts) do
				tween(t, .6, { TextTransparency = 1 })
			end
			tween(back, .6, { BackgroundTransparency = 1 })
			task.delay(.65, function()
				g:Destroy()
			end)
		end
		task.delay(hold, function()
			handle.Hide()
		end)
	end)
	if not ok then
		warnOnce("banner", tostring(err))
	end
	handle.Hide = handle.Hide or function() end
	State.Banners += 1
	return handle
end

---------------------------------------------------------------------------------------------------------------------
-- The show
---------------------------------------------------------------------------------------------------------------------
local stepShow: (any, number) -> ()
local teardown: (any, string) -> ()

-- seam brightness order: order 1 lights with the first snap, 2 with the second, 3+ spread over the rattle
local function seamLitAt(show: any, order: number): number
	local b = show.Beats
	if order <= 1 then
		return b.Chains[1].Snap
	elseif order == 2 then
		return b.Chains[2].Snap
	end
	local span = math.max(.3, b.RattleTo - b.RattleFrom)
	local n = math.max(1, show.Rig.MaxOrder - 2)
	return b.Chains[3].Snap + (order - 3) / n * span
end

-- the lid's angle (radians), lift and twist at show time t
local function lidPose(show: any, t: number): (number, number, number)
	local b = show.Beats
	local rig = show.Rig
	local open = rig.Lid and rig.Lid.Angle or math.rad(CC.Model.OpenAngle)
	local calm = reduced() and .35 or 1
	if t < b.RattleFrom then
		return 0, 0, 0
	end
	if t < b.Open then
		local k = t < b.RattleTo and smooth((t - b.RattleFrom) / .25) or 0
		if b.Secret and t >= b.Lift then
			k = .45 -- trembling in the dark
		end
		local s = t * 31
		local amp = math.rad(2.4) * k * calm * (show.Near and .7 or 1)
		local a = math.max(0, math.sin(s) * amp + math.sin(s * 1.7) * amp * .5)
		local lift = math.max(0, math.sin(s * .9 + 1)) * .05 * k * calm
		local twist = math.sin(s * .6) * math.rad(.6) * k * calm
		return a, lift, twist
	end
	local x = t - b.Open
	-- blast open with a heavy overshoot, then hang and sway
	local spring = 1 - math.exp(-7 * x) * math.cos(9 * x)
	local sway = math.sin(x * 1.6) * math.rad(1.2) * smooth(x - .8) * calm
	return open * math.clamp(spring, 0, 1.12) + sway, 0, 0
end

local function ensurePillar(show: any)
	if show.Pillar or show.Rank <= 0 then
		return
	end
	local rig = show.Rig
	local base = seatPoint(rig, Vector3.new(0, .5, 0))
	local P = CC.Show.Pillar
	local core = spart(show, { Name = "PillarCore", Shape = CYL, Size = Vector3.new(.2, P.Core, P.Core), CFrame = CF(base) * CYL_UP,
		Color = show.Color:Lerp(WHITE, .35), Transparency = .15 })
	local glow = spart(show, { Name = "PillarGlow", Shape = CYL, Size = Vector3.new(.2, P.Glow, P.Glow), CFrame = CF(base) * CYL_UP,
		Color = show.Color, Material = Enum.Material.ForceField, Transparency = .45 })
	local light = slight(show, core, show.Color, 28, 0)
	local motes = nil
	if not lowQuality() then
		local a = Instance.new("Attachment")
		a.Parent = core
		motes = Instance.new("ParticleEmitter")
		motes.Name = "PillarMotes"
		motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		motes.Color = ColorSequence.new(show.Color:Lerp(WHITE, .3), show.Color)
		motes.LightEmission = .9
		motes.LightInfluence = 0
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new(.1, 1)
		motes.Lifetime = NumberRange.new(1.2, 2.2)
		motes.Speed = NumberRange.new(6, 12)
		motes.SpreadAngle = Vector2.new(8, 8)
		motes.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis (up)
		motes.Rate = 18 * budget() * (show.Near and CC.Show.Near.Particles or 1)
		motes.Parent = a
	end
	show.Pillar = { Core = core, Glow = glow, Light = light, Motes = motes, Base = base }
end

local function ensureReward(show: any)
	if show.Reward ~= nil then
		return
	end
	show.Reward = false
	if show.Beats.Secret then
		return -- the Hollow King walks out (the arrival, or the fallback below)
	end
	local main = show.Payload.Main or {}
	local model = CoffinFX.BuildReward(main)
	if not model then
		return
	end
	fit(model, CC.Show.RiseSize)
	local off = centreOffset(model)
	model.Name = "CoffinReward"
	model.Parent = show.Scene
	-- a showcase find brings its own aura colour and glint parts (WP-K3: ShowcaseAura / ShowcaseGlint)
	local auraColor = model:GetAttribute("ShowcaseAura")
	auraColor = typeof(auraColor) == "Color3" and auraColor or show.Color
	local aura = spart(show, { Name = "RewardAura", Shape = BALL, Size = Vector3.one * (CC.Show.RiseSize * 1.25), CFrame = CF(show.Rig.Seat.Position),
		Color = auraColor, Material = Enum.Material.ForceField, Transparency = .6 })
	local light = slight(show, aura, auraColor:Lerp(WHITE, .3), 14, 2.2)
	if not lowQuality() then
		local glints = 0
		for _, d in ipairs(model:GetDescendants()) do
			if glints < 3 and d:IsA("BasePart") and d:GetAttribute("ShowcaseGlint") then
				glints += 1
				local at = Instance.new("Attachment")
				at.Parent = d
				local e = Instance.new("ParticleEmitter")
				e.Name = "Glint"
				e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				e.Color = ColorSequence.new(auraColor:Lerp(WHITE, .6))
				e.LightEmission = 1
				e.LightInfluence = 0
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.4, .35), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(.4, .8)
				e.Speed = NumberRange.new(0, .4)
				e.Rate = 5 * budget()
				e.Parent = at
			end
		end
	end
	show.Reward = { Model = model, Offset = off, Aura = aura, Light = light }
end

-- the Secret fallback (no SecretReveal arrival in the place): the black moon, the eclipse, the king's silhouette, the crown
local function ensureKing(show: any)
	if show.King then
		return
	end
	local shrine: CFrame = Layout.Square.CoffinShrine
	local X = CC.Show.Secret
	local king: any = { Shrine = shrine }
	local moonAt = shrine * Vector3.new(0, X.MoonHeight, X.MoonDistance)
	king.MoonAt = moonAt
	king.Moon = spart(show, { Name = "BlackMoon", Shape = BALL, Size = Vector3.one * X.MoonRadius * 2, CFrame = CF(moonAt), Color = INK,
		Material = Enum.Material.SmoothPlastic, Transparency = 1 })
	king.Halo = spart(show, { Name = "MoonHalo", Shape = BALL, Size = Vector3.one * X.MoonRadius * 2.7, CFrame = CF(moonAt), Color = VIOLET,
		Material = Enum.Material.ForceField, Transparency = 1 })
	king.Sliver = spart(show, { Name = "LastLight", Shape = BALL, Size = Vector3.one * X.MoonRadius * 2.02, CFrame = CF(moonAt), Color = MOON,
		Transparency = 1 })
	king.MoonLight = slight(show, king.Moon, VIOLET_HOT, 40, 0)
	king.Tongues = {}
	for i = 1, lowQuality() and 6 or 10 do
		king.Tongues[i] = spart(show, { Name = "CrownFire", Size = Vector3.new(.3, .9, .3), Color = i % 2 == 0 and CROWN or VIOLET_HOT, Transparency = 1,
			CFrame = CF(moonAt) })
	end
	local model = dogModel(CC.SecretDog)
	if model then
		prepare(model)
	else
		model = Instance.new("Model")
		model.Name = "KingSilhouette"
		silhouetteDog(model, INK)
		prepare(model)
	end
	local ext = fit(model, X.KingHeight)
	local _ = ext
	model.Name = "HollowKing"
	model.Parent = show.Scene
	pcall(function()
		local h = Instance.new("Highlight")
		h.Name = "Ink"
		h.FillColor = INK
		h.FillTransparency = 0
		h.OutlineColor = VIOLET
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		king.Highlight = h
	end)
	king.Model = model
	-- feet on the floor: the model's bounding-box bottom at y 0 of the shrine frame
	local okBB, bb, size = pcall(function()
		return model:GetBoundingBox()
	end)
	local pivot = model:GetPivot()
	if okBB and typeof(bb) == "CFrame" then
		king.Rel = CFrame.new(bb.Position - Vector3.new(0, size.Y / 2, 0)):Inverse() * pivot
	else
		king.Rel = CFrame.new()
	end
	setLTM(partsOf(model), 1)
	show.King = king
end

local function stepKing(show: any, t: number)
	local king = show.King
	if not king then
		return
	end
	local X = CC.Show.Secret
	local h0 = show.Beats.Handoff
	local x = t - h0
	local shrine: CFrame = king.Shrine
	-- the moon rises behind the shrine and its last sliver of light is swallowed at totality
	local mv = smooth((x - X.Rise) / 1.4) * (1 - smooth((x - X.Title - 2.4) / 1.2))
	local lift = (1 - smooth((x - X.Rise) / 1.6)) * X.MoonRadius * 2.2
	local centre = king.MoonAt - Vector3.new(0, lift, 0)
	local cam = workspace.CurrentCamera
	local toCam = cam and (cam.CFrame.Position - centre) or (shrine.LookVector * 30)
	toCam = toCam.Magnitude > .01 and toCam.Unit or shrine.LookVector
	local right = toCam:Cross(UP)
	right = right.Magnitude > .01 and right.Unit or shrine.RightVector
	king.Moon.CFrame = CF(centre + toCam * .3)
	king.Moon.Transparency = 1 - mv
	king.Halo.CFrame = CF(centre)
	local surge = x > X.Total and math.exp(-(x - X.Total) * 2) or 0
	king.Halo.Transparency = 1 - mv * (.25 + .35 * surge)
	local cover = smooth((x - X.Rise) / (X.Total - X.Rise))
	king.Sliver.CFrame = CF(centre - toCam * .2 + right * (1 - cover) * X.MoonRadius * .24)
	king.Sliver.Transparency = (mv > .01 and cover < .999) and (1 - mv) or 1
	if king.MoonLight then
		king.MoonLight.Brightness = mv * (.6 + 3 * surge)
	end
	-- the king walks out of the coffin toward the tower, an ink silhouette until totality
	local walk = smooth((x - X.Walk) / (X.Arrive - X.Walk))
	local from = CC.King.Ground + Vector3.new(0, 0, 9.15)
	local at = CC.King.Ground:Lerp(from, 1 - walk)
	local bob = math.abs(math.sin(x * 6)) * .12 * (walk < 1 and walk > 0 and 1 or 0)
	local feet = shrine * CF(at.X, bob, at.Z)
	king.Model:PivotTo(feet * king.Rel)
	if x >= X.Walk and not king.Shown then
		king.Shown = true
		setLTM(partsOf(king.Model), 0)
	end
	if king.Highlight then
		local reveal = smooth((x - X.Total) / .9)
		king.Highlight.FillTransparency = reveal
		king.Highlight.OutlineTransparency = x < X.Walk and 1 or math.clamp(.05 + .9 * smooth((x - X.Title - .6) / 1.4), 0, 1)
	end
	-- the crown of violet fire drops onto its head at totality
	local head = shrine * (at + Vector3.new(0, X.KingHeight * .95, -1.4))
	local crownVis = smooth((x - X.Total + .9) / .5) * (1 - smooth((x - X.Total - 2.2) / .9))
	local drop = smooth((x - X.Total) / .35)
	local crownAt = head + Vector3.new(0, (1 - drop) * 4 + .2, 0)
	for i, tongue in ipairs(king.Tongues) do
		local a = (i - 1) / #king.Tongues * math.pi * 2 + x * 1.4
		local hgt = (.7 + .4 * math.sin(x * 11 + i * 2.1)) * (1 + 1.2 * surge)
		tongue.Size = Vector3.new(.3, hgt, .3)
		tongue.CFrame = CF(crownAt + Vector3.new(math.cos(a) * .75, hgt / 2, math.sin(a) * .75)) * ANG(0, -a, .12 * math.sin(x * 7 + i))
		tongue.Transparency = 1 - .9 * crownVis
	end
end

-- the opener's camera (seat-local framings of CoffinConfig.Camera) at show time t
local function camAt(show: any, t: number): CFrame
	local b = show.Beats
	local S: CFrame = show.Rig.Seat
	local Cm = CC.Camera
	local function frame(spec: { Vector3 }): (Vector3, Vector3)
		return S * spec[1], S * spec[2]
	end
	local function blend(a: { Vector3 }, c: { Vector3 }, k: number): CFrame
		local p0, l0 = frame(a)
		local p1, l1 = frame(c)
		return CFrame.lookAt(p0:Lerp(p1, k), l0:Lerp(l1, k))
	end
	if b.Secret then
		if t < b.Blackout then
			return blend(Cm.Main, Cm.Push, smooth(t / b.Blackout))
		elseif t < b.Open then
			return blend(Cm.SecretLow, Cm.SecretLow, 0)
		elseif t < b.Handoff + .5 then
			return blend(Cm.SecretLow, Cm.SecretOpen, outCubic((t - b.Open) / .6))
		end
		return blend(Cm.SecretOpen, Cm.SecretKing, smooth((t - b.Handoff - .5) / 2.9))
	end
	if t < b.Open then
		return blend(Cm.Main, Cm.Push, smooth(t / b.Open))
	end
	return blend(Cm.Push, Cm.Reveal, outCubic((t - b.Open) / .9))
end
local function fovAt(show: any, t: number): number
	local b = show.Beats
	local Cm = CC.Camera
	if b.SlowFrom and t >= b.SlowFrom - .1 and t <= b.SlowTo + .4 and not reduced() then
		local k = smooth((t - b.SlowFrom + .1) / .15) * (1 - smooth((t - b.SlowTo) / .4))
		return Cm.RevealFov + (Cm.SlowFov - Cm.RevealFov) * k
	end
	if t >= b.Open then
		return Cm.Fov + (Cm.RevealFov - Cm.Fov) * smooth((t - b.Open) / .8)
	end
	return Cm.Fov
end

-- show time now
local function showTime(show: any): number
	return CC.ShowTime(show.Beats, os.clock() - show.T0)
end

-- the beat events: {T, Name, Fn(show, late)}; `late` = fast-forwarded (state only: no sounds, no bursts)
local function buildEvents(show: any): { any }
	local b = show.Beats
	local rig = show.Rig
	local ev = {}
	local function add(t: number?, name: string, fn: (any, boolean) -> ())
		if t then
			table.insert(ev, { T = t, Name = name, Fn = fn })
		end
	end
	for k = 1, 3 do
		local beat = b.Chains[k]
		add(beat.Tighten, "Tighten" .. k, function(s, late)
			local ch = rig.Chains[k]
			if not late and ch then
				cue(s, "CoffinChain", ch.Anchor, .9)
				burst(s, ch.Anchor, { Color = SPARK, Count = 6, Speed = { 2, 5 }, Lifetime = { .2, .45 }, Size = { .2, .3, 0 } })
			end
		end)
		add(beat.Snap, "Snap" .. k, function(s, late)
			local ch = rig.Chains[k]
			if not ch then
				return
			end
			setLTM(ch.Parts, 1)
			if late then
				return
			end
			cue(s, "CoffinChainSnap", ch.Anchor, 1)
			-- the links fly: clones of a budgeted share of the chain's parts
			local every = math.max(1, math.floor(1 / budget() + .5))
			local origin = seatPoint(rig, Vector3.new(0, .8, 0))
			local floor = seatPoint(rig, Vector3.new(0, -CC.Model.Height / 2 - .05, 0)).Y
			for i, p in ipairs(ch.Parts) do
				if i % every == 0 then
					local c = spart(s, { Name = "FlyingLink", Size = p.Size, CFrame = p.CFrame, Color = p.Color, Material = p.Material })
					local out = (p.Position - origin)
					out = Vector3.new(out.X, 0, out.Z)
					out = out.Magnitude > .01 and out.Unit or Vector3.new(1, 0, 0)
					local rng = s.Rng
					local vel = out * rng:NextNumber(6, 14) + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 12), rng:NextNumber(-2, 2))
					fling(s, c, vel, Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)), rng:NextNumber(1.1, 1.6), floor)
				end
			end
			local mid = ch.Parts[math.max(1, math.floor(#ch.Parts * .6))]
			local at = mid and mid.Position or ch.Anchor
			burst(s, at, { Color = SPARK, Color2 = s.Color, Count = 22, Speed = { 6, 14 }, Lifetime = { .25, .6 }, Size = { .3, .45, 0 } })
			local c = cinema()
			if c and s.Cinema then
				safe("shake", c.Shake, .1 + k * .03, .25)
				safe("impulse", c.Impulse, .25 + k * .1)
			end
		end)
	end
	add(b.Padlock, "Padlock", function(s, late)
		setLTM(rig.Padlock, 1)
		if late then
			return
		end
		cue(s, "ChainRattle", seatPoint(rig, Vector3.new(0, 1.4, -.8)), .8)
		local floor = seatPoint(rig, Vector3.new(0, -CC.Model.Height / 2 - .05, 0)).Y
		local rng = s.Rng
		local side = rig.Seat.RightVector * (rng:NextNumber() < .5 and -1 or 1)
		for _, p in ipairs(rig.Padlock) do
			local c = spart(s, { Name = "FallingPadlock", Size = p.Size, CFrame = p.CFrame, Color = p.Color, Material = p.Material })
			fling(s, c, side * 4 + Vector3.new(0, 5, 0), Vector3.new(4, 9, 3), 1.6, floor)
		end
	end)
	add(b.Flare, "Flare", function(s, late)
		if late then
			return
		end
		cue(s, "CandleLight", rig.Seat.Position, .8)
		for _, f in ipairs(rig.Flames) do
			burst(s, f.Position, { Color = CANDLE, Color2 = s.Color, Count = 4, Speed = { 1, 3 }, Lifetime = { .3, .6 }, Size = { .15, .25, 0 },
				Direction = UP, Spread = 25 })
		end
	end)
	add(b.RattleFrom, "Rattle", function(s, late)
		if late then
			return
		end
		cue(s, "CoffinRattle", rig.Seat.Position, 1)
		cue(s, "CoffinKnock", rig.Seat.Position, .6, { Delay = .25 })
		local c = cinema()
		if c and s.Cinema then
			safe("shake", c.Shake, b.Secret and .08 or .06 + .03 * s.Rank, b.RattleTo - b.RattleFrom)
		end
	end)
	add(b.Swell, "Swell", function(s, late)
		if not late then
			cue(s, "SubSwell", rig.Seat.Position, .7)
		end
	end)
	for i, lt in ipairs(b.Lightning) do
		add(lt, "Lightning" .. i, function(s, late)
			if late or i > math.max(1, math.floor(3 * budget() + .5)) then
				return
			end
			local ch = rig.Chains[(i - 1) % 3 + 1]
			local target = ch and typeof(ch.Anchor) == "Vector3" and ch.Anchor or rig.Seat.Position
			bolt(s, target, s.Color)
		end)
	end
	if b.Secret then
		add(b.Blackout, "Blackout", function(s, late)
			setLTM(rig.Flames, 1)
			if not s.Near then
				local m = mixer()
				if m then
					safe("duck", m.Duck, "HollowKing", "Silence", late and 0 or .25)
					s.Ducked = true
				end
				s.Fade(1, late and 0 or .3)
				s.Grade(1)
			end
			if not late then
				cue(s, "CandleSnuff", rig.Seat.Position, .9)
				cue(s, "Heartbeat", nil, .8)
			end
		end)
		add(b.Lift, "Lift", function(s, late)
			if not s.Near then
				s.Fade(CC.Show.Secret.Lift, late and 0 or .7)
			end
			if not late then
				cue(s, "Heartbeat", nil, .9)
				cue(s, "Whisper2", rig.Seat.Position, .7, { Delay = .4 })
			end
		end)
		add(b.Open - .95, "Beat", function(s, late)
			if not late then
				cue(s, "Heartbeat", nil, 1)
			end
		end)
	end
	add(b.Open, "Open", function(s, late)
		ensurePillar(s)
		if b.Secret and not s.Near then
			s.Fade(.12, late and 0 or .8)
		end
		if late then
			return
		end
		cue(s, "CoffinLid", rig.Seat.Position, 1)
		cue(s, REVEAL_CUE[s.Rank] or REVEAL_CUE[1], nil, s.Near and .8 or 1)
		if not s.Near and not b.Secret then
			Bus.Fire("MusicOverride", { Theme = "COFFIN", Seconds = 8, Fade = .4 })
		end
		local top = seatPoint(rig, Vector3.new(0, CC.Model.Height / 2 + .2, 0))
		burst(s, top, { Color = s.Color:Lerp(WHITE, .3), Color2 = s.Color, Count = 34 + 10 * s.Rank, Speed = { 8, 20 }, Lifetime = { .5, 1.2 },
			Size = { .5, .9, 0 }, Direction = UP, Spread = 40 })
		if b.Shockwave then
			local f = fx()
			local ground = seatPoint(rig, Vector3.new(0, -CC.Model.Height / 2, 0))
			if f and f.Shockwave then
				safe("shock", f.Shockwave, ground, s.Color, (s.Near and 10 or 16) + 2 * s.Rank, .8)
			end
			if s.Rank >= 4 and f and f.Ring then
				task.delay(.18, function()
					if s.Alive then
						safe("ring", f.Ring, ground, s.Color:Lerp(WHITE, .4), 24 + 2 * s.Rank, 1.1, { Thickness = .3 })
					end
				end)
			end
			cue(s, "ShockwaveRing", ground, .6)
		end
		local c = cinema()
		if c and s.Cinema then
			safe("impulse", c.Impulse, .8 + .15 * s.Rank)
			if not reduced() then
				safe("flash", c.Flash, s.Color:Lerp(WHITE, .5), .25 + .05 * s.Rank, .35)
			end
		end
	end)
	add(b.Rise, "Rise", function(s, _late)
		if b.Secret then
			if not s.Payload.Arrival then
				ensureKing(s)
			end
			return
		end
		ensureReward(s)
	end)
	if b.Secret then
		add(b.Handoff, "Handoff", function(s, late)
			if s.Payload.Arrival then
				return -- the server's SecretReveal arrival takes the stage
			end
			ensureKing(s)
			if not late then
				cue(s, "CoffinRevealSecret", nil, 1)
			end
		end)
		add(b.Handoff + CC.Show.Secret.Total, "Totality", function(s, late)
			if s.Payload.Arrival or late then
				return
			end
			cue(s, "BellTollHuge", nil, .7)
			local c = cinema()
			if c and s.Cinema and not reduced() then
				safe("flash", c.Flash, VIOLET_HOT, .55, .5)
			end
			local king = s.King
			if king then
				burst(s, king.MoonAt, { Color = VIOLET, Count = 40, Speed = { 4, 12 }, Lifetime = { .7, 1.4 }, Size = { .5, .8, 0 } })
			end
		end)
		add(b.Handoff + CC.Show.Secret.Banner, "Banner", function(s, late)
			if s.Payload.Arrival or late or s.Near then
				return -- the Mega layer names the raiser; onlookers get the omen banner (C2Announce)
			end
			local main = F("%s RAISED THE HOLLOW KING", upper(tostring(s.Payload.Name or "")))
			s.Banner = banner(main, T("✦ SECRET ✦"), T("FROM THE BLACK COFFIN"), VIOLET_HOT, CC.Show.Omen.Hold)
		end)
		add(b.Release, "Release", function(s, late)
			if not s.Near then
				s.Fade(0, late and 0 or 1.2)
			end
			if s.Ducked then
				local m = mixer()
				if m then
					safe("release", m.Release, "HollowKing", 2)
				end
				s.Ducked = false
			end
			s.Grade(0)
		end)
	end
	add(b.Card, "Card", function(s, _late)
		if s.Near then
			namePlate(s)
			return
		end
		-- the Hollow King's arrival is its own card: only extra rows get one
		local rows = type(s.Payload.Rows) == "table" and s.Payload.Rows or {}
		if b.Secret and s.Payload.Arrival and #rows <= 1 then
			s.CardDone = true
			return
		end
		local ok, card = pcall(buildCard, s)
		if ok and card then
			s.Card = card
		else
			warnOnce("card", tostring(card))
			s.CardDone = true
		end
	end)
	table.sort(ev, function(x, y)
		return x.T < y.T
	end)
	return ev
end

-- per-frame visuals that are a function of show time (so a fast-forward lands on the right state)
local function animate(show: any, t: number, dt: number)
	local b = show.Beats
	local rig = show.Rig
	local resetK = show.ResetAt and math.clamp((os.clock() - show.ResetAt) / CC.Show.CloseLid, 0, 1) or 0
	-- the lid
	if rig.Lid then
		local a, lift, twist = lidPose(show, t)
		if show.ResetAt then
			local from = show.ResetFrom or a
			show.ResetFrom = from
			a = from * (1 - resetK ^ 2)
			lift, twist = 0, 0
		end
		poseLid(rig, a, lift, twist)
	end
	-- a tightening chain strains and shivers
	for k = 1, 3 do
		local ch = rig.Chains[k]
		local beat = b.Chains[k]
		if ch and #ch.Parts > 0 then
			if t >= beat.Tighten and t < beat.Snap then
				local x = (t - beat.Tighten) / (beat.Snap - beat.Tighten)
				local amp = .05 * smooth(x) * (reduced() and .4 or 1)
				local cfs = table.create(#ch.Parts)
				for i, base in ipairs(ch.Base) do
					local toward = (ch.Anchor - base.Position)
					local pull = toward.Magnitude > .01 and toward.Unit * .12 * smooth(x) or Vector3.zero
					local j = Vector3.new(math.sin(t * 57 + i), math.sin(t * 43 + i * 1.7), math.sin(t * 61 + i * .7)) * amp
					cfs[i] = base + pull + j
				end
				moveParts(ch.Parts, cfs)
				ch.Strained = true
			elseif ch.Strained and t >= beat.Snap then
				ch.Strained = false
				moveParts(ch.Parts, ch.Base)
			end
			if show.ResetAt then
				setLTM(ch.Parts, 1 - smooth((resetK - .3) / .7))
			end
		end
	end
	if show.ResetAt then
		setLTM(rig.Padlock, 1 - smooth((resetK - .3) / .7))
		setLTM(rig.Flames, 0)
	end
	-- the seams light up in the rarity colour, then soften once the light pours out of the open coffin
	local pulse = .5 + .5 * math.sin(t * 9)
	local fadeOut = show.ResetAt and resetK or 0
	for _, s in ipairs(rig.Seams) do
		local lit = smooth((t - seamLitAt(show, s.Order)) / .25)
		local after = t >= b.Open and smooth((t - b.Open) / .6) or 0
		local alpha = lit * (1 - .45 * after) * (1 - fadeOut)
		s.Part.Color = show.Color:Lerp(WHITE, .2 * pulse * lit)
		s.Part.Transparency = 1 - alpha * (.85 + .15 * pulse)
	end
	-- the runes wake with the seams
	local wake = smooth((t - b.Chains[1].Snap) / math.max(.4, b.RattleTo - b.Chains[1].Snap)) * (1 - fadeOut)
	if b.Secret and b.Blackout and t >= b.Blackout then
		wake = 1 - fadeOut
	end
	for _, r in ipairs(rig.Runes) do
		r.Part.Color = r.C0:Lerp(b.Secret and VIOLET_HOT or show.Color:Lerp(VIOLET_HOT, .5), wake)
		r.Part.Transparency = r.T0 * (1 - wake)
	end
	-- the inner glow and its light
	local inner = smooth((t - b.Open + .1) / .35) * (1 - fadeOut)
	for _, s in ipairs(rig.Inner) do
		local base = s.Part.Material == Enum.Material.ForceField and .45 or .05
		s.Part.Color = show.Color
		s.Part.Transparency = 1 - (1 - base) * inner * (.85 + .15 * pulse)
	end
	if rig.Light then
		local l = rig.Light.Light
		l.Enabled = inner > .01 or rig.Light.Enabled
		l.Color = show.Color
		l.Brightness = inner > .01 and (3.5 + pulse) * inner or rig.Light.Brightness
	end
	-- the candle flares (own halos over the flames: the world's flicker keeps its own lights)
	if not show.Halos and t >= b.Flare - .05 then
		show.Halos = {}
		for i, f in ipairs(rig.Flames) do
			local h = spart(show, { Name = "CandleHalo", Shape = BALL, Size = Vector3.one * .6, CFrame = f.CFrame, Color = CANDLE, Transparency = 1 })
			local l = (i % 3 == 1) and slight(show, h, CANDLE, 10, 0) or nil
			table.insert(show.Halos, { Part = h, Light = l, Flame = f })
		end
	end
	if show.Halos then
		local flare = smooth((t - b.Flare) / .2) * (1 - .6 * smooth((t - b.Flare - .5) / 1.5))
		if b.Secret and b.Blackout and t >= b.Blackout then
			flare = 0
		end
		flare *= (1 - fadeOut)
		for _, h in ipairs(show.Halos) do
			local flick = .85 + .15 * math.sin(t * 23 + h.Part.Size.X * 10)
			h.Part.CFrame = h.Flame.CFrame * CF(0, .2, 0)
			h.Part.Size = Vector3.one * (.35 + .55 * flare * flick)
			h.Part.Color = CANDLE:Lerp(show.Color, .45 * flare)
			h.Part.Transparency = 1 - .75 * flare
			if h.Light then
				h.Light.Brightness = 2.2 * flare * flick
				h.Light.Color = CANDLE:Lerp(show.Color, .35)
			end
		end
	end
	-- the pillar
	local P = show.Pillar
	if P then
		local x = t - b.Open
		local rise = outCubic(x / .45)
		local H = CC.Show.Pillar.Height * rise
		local gone = show.ResetAt and resetK or 0
		local wob = 1 + .06 * math.sin(t * 7)
		-- the pillar narrows once the reward (or the king) is out, so the reward reads in front of it
		local thinAt = b.Secret and (b.Handoff + CC.Show.Secret.Walk) or (b.Rise + CC.Show.Rise * .6)
		local thin = 1 - (1 - CC.Show.Pillar.Thin) * smooth((t - thinAt) / .8)
		local up = CF(P.Base + UP * (H / 2)) * CYL_UP
		local core = CC.Show.Pillar.Core * wob * thin * (1 - .7 * gone)
		P.Core.Size = Vector3.new(math.max(.2, H), core, core)
		P.Core.CFrame = up
		P.Core.Transparency = .15 + .85 * gone + .15 * smooth((x - 2) / 2)
		P.Glow.Size = Vector3.new(math.max(.2, H), CC.Show.Pillar.Glow * wob * thin, CC.Show.Pillar.Glow * wob * thin)
		P.Glow.CFrame = up
		P.Glow.Transparency = .45 + .55 * gone + .15 * smooth((x - 2) / 2)
		if P.Light then
			P.Light.Brightness = 4 * rise * (1 - gone)
		end
		if P.Motes then
			P.Motes.Enabled = gone < .5
		end
	end
	-- the reward climbs out of the coffin, turns in the light and bobs
	local R = show.Reward
	if R then
		local x = (t - b.Rise) / CC.Show.Rise
		local h = -.6 + (CC.Show.RiseHeight + .6) * outBack(x)
		if show.ResetAt then
			h -= (CC.Show.RiseHeight + 1.2) * smooth(resetK)
		end
		local bob = x >= 1 and math.sin((t - b.Rise) * 2.2) * .12 or 0
		local spin = (t - b.Rise) * 1.15
		local centre = (show.Rig.Seat :: CFrame) * CF(0, h + bob, 0)
		R.Model:PivotTo(CF(centre.Position) * ANG(0, spin, 0) * R.Offset)
		R.Aura.CFrame = CF(centre.Position)
		R.Aura.Transparency = .6 + .4 * (show.ResetAt and resetK or 0) + .05 * math.sin(t * 5)
	end
	-- the fallback king
	stepKing(show, t)
	-- the flying links, the padlock, the bolts
	stepDebris(show, dt)
	stepBolts(show, dt)
	-- the card's turning reward
	local card = show.Card
	if card and not card.Closed and card.Model then
		card.Spin = (card.Spin or 0) + dt * .9
		card.Model:PivotTo(ANG(0, card.Spin, 0) * card.Offset)
	end
	-- the opener's own character stays out of the shot while the camera is ours
	if show.Cinema and show.Hide then
		for _, p in ipairs(show.Hide) do
			p.LocalTransparencyModifier = 1
		end
	end
end

-- fire the beat events up to show time t (late = fast-forwarded)
local function runEvents(show: any, t: number, late: boolean)
	while show.Next <= #show.Events and show.Events[show.Next].T <= t do
		local e = show.Events[show.Next]
		show.Next += 1
		show.Late = late
		local ok, err = pcall(e.Fn, show, late)
		show.Late = false
		if not ok then
			warnOnce("event" .. e.Name, tostring(err))
		end
		if not show.Alive then
			return
		end
	end
end

-- jump the show forward to show time `target` (the skip): every beat in between happens silently
local function fastForward(show: any, target: number)
	local now = showTime(show)
	if target <= now then
		return
	end
	show.T0 -= CC.RealTime(show.Beats, target) - CC.RealTime(show.Beats, now)
	runEvents(show, target, true)
end

-- the reset (lid closes, chains return, light dies), then the teardown
local function beginReset(show: any)
	if show.ResetAt or not show.Alive then
		return
	end
	show.ResetAt = os.clock()
	if show.Card and not show.Card.Closed then
		show.Card.Close("Reset")
	end
	if show.Plate and show.Plate.Parent then
		tween(show.Plate, .4, { Size = UDim2.fromOffset(300, 0) })
	end
	task.delay(CC.Show.CloseLid * .85, function()
		if show.Alive then
			cue(show, "CoffinKnock", show.Rig.Seat.Position, .7)
		end
	end)
end

local function stepOnce(show: any, dt: number)
	local t = showTime(show)
	runEvents(show, t, false)
	if not show.Alive then
		return
	end
	animate(show, t, dt)
	local b = show.Beats
	-- when is it over?
	if not show.ResetAt then
		local due: boolean
		if show.Near then
			due = t >= (b.Secret and (b.Handoff + CC.Show.Secret.Linger) or (b.Reveal + CC.Show.NearLinger))
		else
			local card = show.Card
			local cardOver = show.CardDone or (card ~= nil and card.Closed)
			if card and not card.Closed and card.ShownAt and os.clock() - card.ShownAt > CC.Show.CardLife and not show.Cinema then
				card.Close("Timeout")
				cardOver = true
			end
			-- the Hollow King's arrival keeps the lid open until it has walked out and been crowned; a card the player
			-- closed (CONTINUE / OPEN AGAIN) closes the coffin at once
			local hold = b.Secret and (b.Handoff + CC.Show.Secret.Linger) or b.End
			local userClosed = card ~= nil and card.Closed and (card.Reason == "Continue" or card.Reason == "Again")
			due = cardOver and (t >= hold or (userClosed and not b.Secret))
			if cardOver and show.Cinema and t < b.End then
				-- CONTINUE during the hold: the camera goes home now
				local h = show.Cinema
				safe("endCinema", h.Skip)
			end
		end
		if due then
			beginReset(show)
		end
	elseif os.clock() - show.ResetAt >= CC.Show.CloseLid + .35 then
		teardown(show, "Done")
	end
end

stepShow = function(show: any, dt: number)
	-- one frame at a time: a beat that yields (a model built on demand) never lets the next frame re-enter
	if not show.Alive or show.Stepping then
		return
	end
	show.Stepping = true
	local ok, err = pcall(stepOnce, show, dt)
	show.Stepping = false
	if not ok then
		error(err, 0)
	end
end

teardown = function(show: any, reason: string)
	if not show.Alive then
		return
	end
	show.Alive = false
	show.Reason = reason
	if show.Conn then
		show.Conn:Disconnect()
		show.Conn = nil
	end
	if show.Cinema then
		local h = show.Cinema
		show.Cinema = nil
		safe("cinemaCancel", h.Cancel)
	end
	if show.Card and not show.Card.Closed then
		safe("cardClose", show.Card.Close, reason)
	end
	if show.Banner and reason ~= "Done" then
		safe("banner", show.Banner.Hide)
	end
	restoreRig(show.Rig)
	if show.Hide then
		for _, p in ipairs(show.Hide) do
			pcall(function()
				p.LocalTransparencyModifier = 0
			end)
		end
	end
	for _, p in ipairs(show.Prompts or {}) do
		pcall(function()
			p.Prompt.Enabled = p.Enabled
		end)
	end
	if show.Ducked then
		local m = mixer()
		if m then
			safe("release", m.Release, "HollowKing", 1)
		end
		show.Ducked = false
	end
	safe("grade", show.Grade, 0, true)
	if show.UsedFade then
		local c = cinema()
		if c and c.Fade then
			safe("fade", c.Fade, 0, .4)
		end
	end
	for _, b in ipairs(show.Bolts) do
		for _, p in ipairs(b.Parts) do
			pcall(p.Destroy, p)
		end
	end
	if show.Scene then
		safe("scene", show.Scene.Destroy, show.Scene)
	end
	if State.Current == show then
		State.Current = nil
	end
	State.Last = { Id = show.Payload.Id, Reason = reason, Near = show.Near, Rank = show.Rank }
	-- the next queued opening of this player
	local nextPayload = table.remove(State.Queue, 1)
	if nextPayload then
		task.defer(function()
			CoffinFX.Play(nextPayload)
		end)
	end
end

-- the shrine prompt stays hidden while its coffin is busy (client-local Enabled; ProximityPromptService is untouched)
local function hidePrompts(show: any)
	show.Prompts = {}
	local root = underyardRoot()
	local anchors = root and root:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(CC.Anchor)
	if not anchor then
		return
	end
	for _, d in ipairs(anchor:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d:GetAttribute("CoffinPrompt") then
			table.insert(show.Prompts, { Prompt = d, Enabled = d.Enabled })
			d.Enabled = false
		end
	end
end

local function startCinema(show: any)
	local c = cinema()
	if not c or not c.Play or show.Near then
		return
	end
	local b = show.Beats
	local offset = os.clock() - show.T0 -- the server-clock lead the show started with
	local blocked = c.Blocked and c.Blocked({ Shot = true }) or nil
	local function play(force: boolean)
		return c.Play({
			Id = "Coffin",
			Duration = math.max(1, b.RealEnd - offset),
			Shot = function(tc: number)
				return camAt(show, CC.ShowTime(b, tc + offset))
			end,
			Fov = function(tc: number)
				return fovAt(show, CC.ShowTime(b, tc + offset))
			end,
			Focus = { Target = show.Rig.Seat.Position, Radius = 9, Far = .4, Near = .05 },
			Letterbox = true,
			Skippable = true,
			SkipAfter = math.max(.5, CC.RealTime(b, b.SkipAfter) - offset),
			LockControls = true,
			HideUI = true,
			Duck = "Cinematic",
			BlendIn = .7,
			BlendOut = .7,
			Force = force,
			OnSkip = function()
				if not show.Alive then
					return
				end
				if b.Secret and show.Payload.Arrival then
					return -- the arrival plays on in the world; only the camera goes home
				end
				fastForward(show, math.max(b.Card, showTime(show)))
			end,
			OnDone = function(_ok: boolean, _reason: string)
				show.Cinema = nil
				if show.Hide then
					for _, p in ipairs(show.Hide) do
						pcall(function()
							p.LocalTransparencyModifier = 0
						end)
					end
				end
			end,
		})
	end
	local handle = nil
	if blocked == nil or blocked == "Menu" then
		-- the player asked for this coffin: a window left open (the Underyard COFFIN tab) does not stop the show
		handle = play(blocked == "Menu")
	elseif blocked == "Busy" then
		-- another cinematic: no camera for this one (the world show and the card still play)
		handle = nil
	end
	if handle then
		show.Cinema = handle
		function show.Fade(alpha: number, dur: number)
			show.UsedFade = true
			if handle.Fade then
				safe("fade", handle.Fade, alpha, dur, { MaxHold = 14 })
			else
				safe("fade", c.Fade, alpha, dur, { MaxHold = 14 })
			end
		end
		local ch = player.Character
		if ch then
			show.Hide = partsOf(ch)
		end
	end
end

-- -> the show (nil when it could not start)
function CoffinFX.Play(payload: any, opts: { [string]: any }?): any
	if type(payload) ~= "table" or type(payload.Main) ~= "table" then
		return nil
	end
	local o = opts or {}
	local near = o.Near == true
	local current = State.Current
	if current then
		if near then
			return nil -- one show at a time; a lighter show never interrupts
		end
		if current.Near then
			teardown(current, "Preempted")
		elseif current.Payload.Id ~= payload.Id then
			table.insert(State.Queue, payload)
			return nil
		else
			return current
		end
	end
	local model = findCoffin()
	if not model then
		-- the coffin is not streamed in (or not in this place): the opener still gets the card
		if not near then
			local stub: any = { Payload = payload, Rank = math.clamp(math.floor(tonumber(payload.Rank) or 1), 1, 6), Alive = true }
			stub.Color = rarityColor(stub.Rank)
			stub.Beats = CC.Beats(stub.Rank)
			if not (stub.Beats.Secret and payload.Arrival) or (type(payload.Rows) == "table" and #payload.Rows > 1) then
				local ok, card = pcall(buildCard, stub)
				if ok and card then
					task.delay(CC.Show.CardLife + 4, function()
						card.Close("Timeout")
					end)
				end
			end
			cue(nil, REVEAL_CUE[stub.Rank] or REVEAL_CUE[1], nil, 1)
		end
		return nil
	end
	local rank = math.clamp(math.floor(tonumber(payload.Rank) or 1), 1, 6)
	local secret = rank >= 6
	local show: any = {
		Payload = payload, Near = near, Rank = rank, Color = rarityColor(rank), Beats = CC.Beats(rank, secret), Alive = true,
		Debris = {}, Bolts = {}, Next = 1, Late = false, LightBudget = math.floor(12 * budget() + .5),
		Rng = Random.new(math.floor(tonumber(payload.Seed) or 1) % 2147483646 + 1),
	}
	if secret then
		show.Color = rarityColor(6)
	end
	-- show second 0 = payload.At on the server clock (a late signal starts the show a little way in)
	local lead = 0
	if type(payload.At) == "number" then
		lead = math.clamp(serverNow() - payload.At, 0, near and 3 or 1.2)
	end
	show.T0 = os.clock() - lead
	function show.Fade(alpha: number, dur: number)
		local c = cinema()
		if c and c.Fade then
			show.UsedFade = true
			safe("fade", c.Fade, alpha, dur, { MaxHold = 14 })
		end
	end
	function show.Grade(k: number, instant: boolean?)
		local cc = show.GradeFx
		if k > 0 and not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "DOGROTS_CoffinGrade"
			cc.Brightness = 0
			cc.Saturation = 0
			cc.Contrast = 0
			cc.TintColor = WHITE
			cc.Parent = Lighting
			show.GradeFx = cc
		end
		if not cc then
			return
		end
		local goal = { Brightness = -.12 * k, Saturation = -.6 * k, Contrast = .18 * k, TintColor = WHITE:Lerp(C3(214, 196, 255), k) }
		if instant then
			for key, v in pairs(goal) do
				(cc :: any)[key] = v
			end
		else
			tween(cc, .8, goal)
		end
		if k <= 0 then
			task.delay(instant and 0 or .85, function()
				if show.GradeFx == cc and cc.Parent then
					cc:Destroy()
					show.GradeFx = nil
				end
			end)
		end
	end
	local ok, err = pcall(function()
		show.Rig = collectRig(model)
		local scene = Instance.new("Model")
		scene.Name = "CoffinShow_" .. tostring(payload.Id or "")
		scene.Parent = fxFolder()
		show.Scene = scene
		show.Events = buildEvents(show)
		State.Current = show
		State.Shows += 1
		if not near then
			hidePrompts(show) -- (onlookers keep theirs: their own opening takes the coffin over)
			startCinema(show)
		end
		show.Conn = RunService.Heartbeat:Connect(function(dt: number)
			local okStep, errStep = pcall(stepShow, show, dt)
			if not okStep then
				warnOnce("step", tostring(errStep))
				teardown(show, "Error")
			end
		end)
		-- belt and braces: whatever happens, the coffin is restored
		task.delay(show.Beats.RealEnd + CC.Show.CardLife + 30, function()
			if show.Alive then
				teardown(show, "Watchdog")
			end
		end)
	end)
	if not ok then
		warnOnce("play", tostring(err))
		teardown(show, "Error")
		return nil
	end
	return show
end

-- stop everything (tests, Chapter II switched off)
function CoffinFX.Stop(reason: string?)
	table.clear(State.Queue)
	local current = State.Current
	if current then
		teardown(current, reason or "Stopped")
	end
	if State.Card then
		State.Card.Close(reason or "Stopped")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Announcements, refusals
---------------------------------------------------------------------------------------------------------------------
-- C2Announce: the Hollow King's banner for everyone when no arrival names the raiser (Arrival false). Mythic is the HUD's.
function CoffinFX.Announce(data: any)
	-- only the Black Coffin's raise (no Source / "Coffin"); a Crooked Door or finale Hollow King is the HUD's banner
	if type(data) ~= "table" or data.Kind ~= "HollowKing" or data.Arrival == true or (data.Source ~= nil and data.Source ~= "Coffin") then
		return
	end
	if data.UserId == player.UserId then
		return -- the opener's own show has the banner
	end
	local revealAt = tonumber(data.RevealAt) or serverNow()
	local wait = math.clamp(revealAt + CC.Show.Omen.Banner - CC.Show.Secret.Total - serverNow(), 0, 6)
	State.Omens += 1
	task.delay(wait, function()
		local main = F("%s RAISED THE HOLLOW KING", upper(tostring(data.Name or "?")))
		banner(main, T("✦ SECRET ✦"), T("FROM THE BLACK COFFIN"), VIOLET_HOT, CC.Show.Omen.Hold)
		cue(nil, "BellTollFar", nil, .6)
		if not reduced() then
			local c = cinema()
			if c and c.Flash then
				safe("omenFlash", c.Flash, VIOLET, .18, CC.Show.Omen.Tint)
			end
		end
	end)
end

-- C2CoffinRefused / a refused OPEN AGAIN: a localized toast
function CoffinFX.Refused(data: any)
	local text = type(data) == "table" and type(data.Text) == "string" and data.Text or "Something went wrong, try again"
	State.Toasts += 1
	Bus.Fire("Toast", { Text = T(text), Kind = "Deny", NoTranslate = true })
	cue(nil, "Deny", nil, .8)
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function CoffinFX.Start(c: any)
	if started then
		return
	end
	started = true
	ctx = c
	if c and c.FX then
		fxMod = c.FX
	end
	if c and c.Audio then
		audioMod = c.Audio
	end
	Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" or not Shared.Chapter2Enabled() then
			return
		end
		local kind, data = sig.Kind, sig.Data
		if kind == "C2Coffin" then
			CoffinFX.Play(data)
		elseif kind == "C2CoffinNear" then
			CoffinFX.Play(data, { Near = true })
		elseif kind == "C2CoffinRefused" then
			CoffinFX.Refused(data)
		elseif kind == "C2Announce" then
			CoffinFX.Announce(data)
		end
	end)
	-- a respawn never inherits a hidden character or a lingering card
	player.CharacterAdded:Connect(function()
		local current = State.Current
		if current and current.Hide then
			current.Hide = nil
		end
	end)
end

return CoffinFX
