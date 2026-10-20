-- THE UNDERYARD built icons (ReplicatedStorage.Halloween.UnderyardIcons), client UI only (WP-L).
-- Adds the CHAPTER II kinds to the Halloween vector icons (RS.Halloween.Icons, same Frame drawing helpers, same handle
-- API) so every screen and the HUD draw them with Icons.New:
--   Shard (Bell Shard: a cracked bronze-violet sliver of the bell), Key (Coffin Key), Coffin (the Black Coffin with its
--   chains), Dust (Lucky Dust sparkles), Fragment (a stitched cloth patch: cosmetic fragments), Seal (a bell seal
--   medallion), Tombstone (plot cosmetics), Relic (showcase finds), Eye (the Underyard's watching eye: journal / story)
--   local UI = require(RS.Halloween.UnderyardIcons)
--   local h = UI.New(parent, "Shard", {Size = 40, ZIndex = 12})   -- = Icons.New
--   UI.ForReward(row) -> kind, opts  (Chapter II reward rows first, then Icons.ForReward)
-- opts as in Icons: Size, ZIndex, Color (main tint), Glow (accent), Dim (0..1 locked look), Outline.
local Icons = require(script.Parent:WaitForChild("Icons"))

local UI = {}
UI.Icons = Icons

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = C(22, 10, 34)
local VIOLET = C(150, 80, 230)
local MOON = C(150, 200, 255)
local BONE = C(230, 222, 200)
local CANDLE = C(255, 170, 80)
local SICKLY = C(120, 255, 140)
local GOLD = C(255, 200, 70)
UI.Palette = { Violet = VIOLET, Moon = MOON, Bone = BONE, Candle = CANDLE, Sickly = SICKLY, Gold = GOLD, Ink = INK }

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local K = Icons.Draw

-- Bell Shard: two cracked slivers of bell bronze with a violet glow inside the crack and a glint
K.Shard = function(d, o)
	local metal = o.Color or C(206, 160, 96)
	local glow = o.Glow or VIOLET
	d:glow(glow, 1.0, .7)
	local back = d:frame("Back", .62, .46, .26, .62, WHITE, { Rotation = 28 })
	d:round(back, .18)
	d:grad(back, lerp(metal, WHITE, .2), lerp(metal, INK, .55), 0)
	d:line(back, nil, .04)
	local main = d:frame("Main", .42, .54, .34, .74, WHITE, { Rotation = -16 })
	d:round(main, .22)
	d:grad(main, lerp(metal, WHITE, .45), lerp(metal, INK, .4), 20)
	d:line(main, nil, .05)
	-- the crack: a violet seam down the main sliver, glowing
	local crack = d:frame("Crack", .44, .55, .05, .5, lerp(glow, WHITE, .35), { Rotation = -16 })
	d:round(crack, "pill")
	local branch = d:frame("Branch", .5, .48, .035, .18, lerp(glow, WHITE, .45), { Rotation = 30 })
	d:round(branch, "pill")
	-- engraved band of the bell's lip on the sliver
	local band = d:frame("Band", .41, .7, .3, .05, lerp(metal, INK, .35), { Rotation = -16, BackgroundTransparency = .2 })
	d:round(band, "pill")
	d:shine(.36, .32, .1, .24, .35)
	local glint = d:frame("Glint", .74, .24, .08, .08, WHITE, { Rotation = 45 })
	d:round(glint, .2)
end

-- Coffin Key: an iron key with a skull-ish bow, a violet gem and two bit teeth
K.Key = function(d, o)
	local iron = o.Color or C(196, 188, 214)
	local gem = o.Glow or VIOLET
	local shaft = d:bar("Shaft", .36, .62, .84, .14, .1, WHITE)
	d:round(shaft, "pill")
	d:grad(shaft, lerp(iron, WHITE, .35), lerp(iron, INK, .45), 90)
	d:line(shaft, nil, .04)
	for i, t in ipairs({ { .74, .34, .2 }, { .64, .44, .14 } }) do
		local tooth = d:frame("Tooth" .. i, t[1] + .06, t[2] + .05, .1, t[3], WHITE, { Rotation = 45 })
		d:round(tooth, .15)
		d:grad(tooth, lerp(iron, WHITE, .2), lerp(iron, INK, .5), 90)
		d:line(tooth, nil, .035)
	end
	local bow = d:circle("Bow", .3, .7, .42, WHITE)
	d:grad(bow, lerp(iron, WHITE, .4), lerp(iron, INK, .45), 90)
	d:line(bow, nil, .05)
	local hole = d:circle("Hole", .3, .7, .2, lerp(gem, INK, .55))
	d:line(hole, nil, .035)
	local stone = d:circle("Gem", .3, .7, .12, WHITE)
	d:grad(stone, lerp(gem, WHITE, .55), gem, 90)
	d:shine(.24, .6, .1, .06, .45)
end

-- the Black Coffin: a lidded coffin with a cross, chains and violet light leaking from the seam
K.Coffin = function(d, o)
	local wood = o.Color or C(56, 40, 72)
	local glow = o.Glow or VIOLET
	d:glow(glow, 1.05, .74)
	local body = d:frame("Body", .5, .54, .46, .84, WHITE)
	d:round(body, .14)
	d:grad(body, lerp(wood, WHITE, .2), lerp(wood, INK, .6), 90)
	d:line(body, nil, .05)
	local shoulders = d:frame("Shoulders", .5, .36, .6, .28, WHITE)
	d:round(shoulders, .35)
	d:grad(shoulders, lerp(wood, WHITE, .25), lerp(wood, INK, .35), 90)
	d:line(shoulders, nil, .05)
	-- the shoulders hide the body's top stroke: a lid plate over both
	local lid = d:frame("Lid", .5, .5, .34, .66, WHITE)
	d:round(lid, .16)
	d:grad(lid, lerp(wood, WHITE, .32), lerp(wood, INK, .3), 90)
	d:line(lid, lerp(wood, INK, .6), .03)
	local seam = d:frame("Seam", .5, .5, .03, .6, lerp(glow, WHITE, .4), { BackgroundTransparency = .1 })
	d:round(seam, "pill")
	for _, r in ipairs({ { .5, .42, .05, .3 }, { .5, .38, .22, .05 } }) do
		local bar = d:frame("Cross", r[1], r[2], r[3], r[4], WHITE)
		d:round(bar, "pill")
		d:grad(bar, lerp(BONE, WHITE, .4), lerp(BONE, C(140, 120, 90), .4), 90)
		d:line(bar, nil, .03)
	end
	for _, s in ipairs({ -1, 1 }) do
		local chain = d:bar("Chain", .5 + s * .3, .3, .5 - s * .3, .82, .045, C(150, 150, 170), { BackgroundTransparency = .05 })
		d:round(chain, "pill")
		d:line(chain, nil, .025)
	end
	d:shine(.4, .28, .12, .06, .55)
end

-- Lucky Dust: three four-point sparkles and a few motes
K.Dust = function(d, o)
	local col = o.Color or C(255, 226, 120)
	local alt = o.Glow or C(170, 230, 255)
	d:glow(col, .95, .7)
	local function sparkle(name: string, x: number, y: number, s: number, c: Color3)
		for _, r in ipairs({ 0, 90 }) do
			local ray = d:frame(name, x, y, s * .22, s, WHITE, { Rotation = r })
			d:round(ray, "pill")
			d:grad(ray, lerp(c, WHITE, .65), c, 90)
		end
		local core = d:frame(name .. "Core", x, y, s * .36, s * .36, WHITE, { Rotation = 45 })
		d:round(core, .15)
		d:grad(core, WHITE, c, 90)
		d:line(core, nil, .025)
	end
	sparkle("Big", .44, .54, .62, col)
	sparkle("Small", .76, .26, .34, alt)
	sparkle("Tiny", .2, .22, .24, lerp(col, alt, .5))
	for i, p in ipairs({ { .78, .7 }, { .24, .82 }, { .62, .9 } }) do
		local mote = d:circle("Mote" .. i, p[1], p[2], .06, i == 2 and alt or col)
		local _ = mote
	end
end

-- cosmetic fragment: a torn cloth patch with stitches and a needle through it
K.Fragment = function(d, o)
	local cloth = o.Color or C(150, 100, 210)
	local thread = o.Glow or BONE
	local patch = d:frame("Patch", .46, .54, .56, .56, WHITE, { Rotation = -10 })
	d:round(patch, .12)
	d:grad(patch, lerp(cloth, WHITE, .3), lerp(cloth, INK, .45), 70)
	d:line(patch, nil, .05)
	local inner = d:frame("Inner", .46, .54, .4, .4, C(0, 0, 0), { BackgroundTransparency = 1, Rotation = -10 })
	d:round(inner, .08)
	d:line(inner, thread, .025, .15)
	for i = 0, 3 do
		local stitch = d:frame("Stitch" .. i, .3 + i * .1, .32 + i * .015, .05, .02, thread, { Rotation = -10 })
		d:round(stitch, "pill")
	end
	local needle = d:bar("Needle", .2, .86, .86, .16, .045, WHITE)
	d:round(needle, "pill")
	d:grad(needle, C(240, 244, 255), C(150, 156, 180), 90)
	d:line(needle, nil, .025)
	local eye = d:circle("NeedleEye", .82, .2, .08, C(0, 0, 0), { BackgroundTransparency = 1 })
	d:line(eye, C(150, 156, 180), .03)
end

-- bell seal medallion: a wax-and-iron seal with a small bell pressed into it (Glow = state colour)
K.Seal = function(d, o)
	local wax = o.Color or VIOLET
	local rim = o.Glow or MOON
	if o.Glow then
		d:glow(rim, 1.05, .74)
	end
	local disc = d:circle("Disc", .5, .5, .86, WHITE)
	d:grad(disc, lerp(wax, WHITE, .3), lerp(wax, INK, .5), 90)
	d:line(disc, nil, .05)
	local ring = d:circle("Ring", .5, .5, .68, C(0, 0, 0), { BackgroundTransparency = 1 })
	d:line(ring, lerp(rim, WHITE, .2), .035, .1)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local bump = d:circle("Bump" .. i, .5 + math.cos(a) * .43, .5 + math.sin(a) * .43, .11, lerp(wax, INK, .2))
		local _ = bump
	end
	local dome = d:frame("Bell", .5, .48, .26, .3, WHITE)
	d:round(dome, .5)
	d:grad(dome, lerp(rim, WHITE, .4), lerp(rim, INK, .35), 0)
	local lip = d:ellipse("Lip", .5, .62, .38, .08, lerp(rim, WHITE, .2))
	local _ = lip
	d:circle("Clapper", .5, .68, .07, lerp(rim, INK, .5))
	d:shine(.36, .3, .16, .07, .5)
end

-- plot cosmetic: a crooked tombstone with a glowing rune and grass tufts
K.Tombstone = function(d, o)
	local stone = o.Color or C(150, 146, 170)
	local rune = o.Glow or SICKLY
	local slab = d:frame("Slab", .5, .54, .52, .7, WHITE, { Rotation = 7 })
	d:round(slab, .42)
	d:grad(slab, lerp(stone, WHITE, .3), lerp(stone, INK, .45), 90)
	d:line(slab, nil, .05)
	local cross = d:frame("RuneV", .52, .48, .05, .28, rune, { Rotation = 7 })
	d:round(cross, "pill")
	local crossH = d:frame("RuneH", .51, .42, .2, .05, rune, { Rotation = 7 })
	d:round(crossH, "pill")
	local ground = d:ellipse("Ground", .5, .9, .86, .14, C(46, 34, 60))
	d:line(ground, nil, .03)
	for i = -1, 1 do
		local tuft = d:frame("Tuft", .5 + i * .26, .85, .05, .12, C(90, 150, 90), { Rotation = i * 20 })
		d:round(tuft, "pill")
	end
	d:shine(.4, .3, .14, .06, .5)
end

-- showcase find: a relic jewel on a velvet cushion (Color = tier colour)
K.Relic = function(d, o)
	local jewel = o.Color or C(120, 200, 255)
	local cushion = o.Glow or C(110, 40, 90)
	d:glow(jewel, 1.0, .72)
	local pad = d:ellipse("Cushion", .5, .74, .78, .28, WHITE)
	d:grad(pad, lerp(cushion, WHITE, .25), lerp(cushion, INK, .4), 90)
	d:line(pad, nil, .045)
	local gem = d:frame("Gem", .5, .46, .42, .42, WHITE, { Rotation = 45 })
	d:round(gem, .12)
	d:grad(gem, lerp(jewel, WHITE, .6), lerp(jewel, INK, .3), 0)
	d:line(gem, nil, .05)
	local facet = d:frame("Facet", .5, .46, .2, .2, lerp(jewel, WHITE, .75), { Rotation = 45, BackgroundTransparency = .25 })
	d:round(facet, .1)
	d:shine(.4, .36, .1, .05, .35)
end

-- the Underyard's eye: an almond eye with a moon-blue iris and a violet glow (journal, story)
K.Eye = function(d, o)
	local iris = o.Color or MOON
	local glow = o.Glow or VIOLET
	d:glow(glow, 1.0, .74)
	local white = d:frame("White", .5, .5, .82, .46, WHITE)
	d:round(white, "pill")
	d:grad(white, C(250, 246, 236), C(196, 186, 210), 90)
	d:line(white, nil, .05)
	local ir = d:circle("Iris", .5, .5, .36, WHITE)
	d:grad(ir, lerp(iris, WHITE, .35), lerp(iris, INK, .45), 90)
	d:line(ir, nil, .035)
	local pupil = d:frame("Pupil", .5, .5, .1, .3, INK)
	d:round(pupil, "pill")
	d:circle("Glint", .44, .42, .07, WHITE)
	for _, s in ipairs({ -1, 1 }) do
		local lash = d:frame("Lash", .5 + s * .3, .24, .04, .14, INK, { Rotation = s * 30 })
		d:round(lash, "pill")
	end
end

UI.Kinds = { "Shard", "Key", "Coffin", "Dust", "Fragment", "Seal", "Tombstone", "Relic", "Eye" }
for _, name in ipairs(UI.Kinds) do
	if not table.find(Icons.Kinds, name) then
		table.insert(Icons.Kinds, name)
	end
end
table.sort(Icons.Kinds)

UI.New = Icons.New

-- tier / rarity colours of the Chapter II reward rows
UI.TierColor = {
	Common = C(176, 196, 214), Rare = C(38, 164, 243), Epic = C(161, 103, 242), Legendary = C(249, 180, 35),
	Mythic = C(247, 73, 112), Secret = C(230, 115, 245),
}

-- reward row -> icon kind / options (Chapter II kinds; everything else through Icons.ForReward)
function UI.ForReward(row: { [string]: any }): (string, { [string]: any })
	local kind = type(row) == "table" and row.Kind or nil
	if kind == "Shards" then
		return "Shard", {}
	elseif kind == "Key" then
		return "Key", {}
	elseif kind == "Dust" then
		return "Dust", {}
	elseif kind == "Fragments" then
		return "Fragment", {}
	elseif kind == "Find" then
		return "Relic", { Color = UI.TierColor[row.Tier or "Rare"] or UI.TierColor.Rare }
	elseif kind == "Decor" and type(row.Id) == "string" and string.sub(row.Id, 1, 3) == "uy_" then
		return "Tombstone", {}
	elseif kind == "Skin" and type(row.Id) == "string" and string.sub(row.Id, 1, 3) == "UY_" then
		return "Pickaxe", { Glow = VIOLET }
	end
	return Icons.ForReward(row or {})
end

return UI
