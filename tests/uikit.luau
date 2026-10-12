--!nolint
-- Unit tests for the pure parts of the UI kit (formatting, layout / grid maths, theme sync,
-- localization coverage): lune run tests/uikit.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
-- Theme builds Color3 / Font values at require time.
Color3 = roblox.Color3
Font = roblox.Font
Enum = roblox.Enum

local KIT = "../src/StarterGui/ScreenGui/Modules/Kit/"
local Format = require(KIT .. "Format")
local Layout = require(KIT .. "Layout")
local Theme = require(KIT .. "Theme")
local Lang = require(KIT .. "Lang")

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
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

-- Repo-relative file reads work from the repo root (check.sh runs there) and from tests/.
local function read(path)
	for _, prefix in { "", "../" } do
		local ok, text = pcall(fs.readFile, prefix .. path)
		if ok then
			return text
		end
	end
	error("cannot read " .. path)
end

-- FORMAT ------------------------------------------------------------------------------------------
test("Format.Short", function()
	local cases = {
		{ 0, "0" }, { 7, "7" }, { 999, "999" }, { 999.9, "999" }, { 1000, "1K" }, { 1234, "1.23K" },
		{ 1239, "1.23K" }, { 12345, "12.3K" }, { 123456, "123K" }, { 999999, "999K" }, { 1e6, "1M" },
		{ 1.5e6, "1.5M" }, { 1.23e6, "1.23M" }, { 2.5e9, "2.5B" }, { 2e12, "2T" }, { 9e15, "9Qa" },
		{ 1e18, "1Qi" }, { 1e21, "1,000Qi" }, { -1500, "-1.5K" }, { -3, "-3" }, { -0.4, "0" },
	}
	for _, c in cases do
		eq(Format.Short(c[1]), c[2], "Short(" .. tostring(c[1]) .. ")")
	end
	eq(Format.Short(2.5, 1), "2.5")
	eq(Format.Short(2.04, 1), "2")
	eq(Format.Short(nil), "—")
	eq(Format.Short(0 / 0), "—")
	eq(Format.Short(math.huge), "∞")
	eq(Format.Short("1500"), "1.5K")
end)

test("Format.Number", function()
	eq(Format.Number(0), "0")
	eq(Format.Number(999), "999")
	eq(Format.Number(1000), "1,000")
	eq(Format.Number(1234567), "1,234,567")
	eq(Format.Number(-1234.9), "-1,234")
	eq(Format.Number(12.9), "12")
	eq(Format.Number("x"), "—")
end)

test("Format.Percent / Mult / Odds", function()
	eq(Format.Percent(0.125), "12.5%")
	eq(Format.Percent(0.5), "50%")
	eq(Format.Percent(0.0025), "0.25%")
	eq(Format.Percent(1.5), "150%")
	eq(Format.Percent(0), "0%")
	eq(Format.Percent(0.05, { Signed = true }), "+5%")
	eq(Format.Percent(-0.05, { Signed = true }), "-5%")
	eq(Format.Percent(0.123456, { Decimals = 2 }), "12.35%")
	eq(Format.Mult(1.25), "x1.25")
	eq(Format.Mult(2), "x2")
	eq(Format.Mult(1.5), "x1.5")
	eq(Format.Odds(0.001), "1 in 1,000")
	eq(Format.Odds(0), "—")
end)

test("Format.Duration / Clock", function()
	eq(Format.Duration(0), "0s")
	eq(Format.Duration(45), "45s")
	eq(Format.Duration(65), "1m 05s")
	eq(Format.Duration(3600), "1h 00m")
	eq(Format.Duration(3725), "1h 02m")
	eq(Format.Duration(90000), "1d 1h")
	eq(Format.Duration(-5), "0s")
	eq(Format.Duration(65, "ru"), "1м 05с")
	eq(Format.Duration(90000, "ru"), "1д 1ч")
	eq(Format.Clock(65), "01:05")
	eq(Format.Clock(3725), "01:02:05")
	eq(Format.Clock(90061), "1d 01:01:01")
	eq(Format.Clock(0), "00:00")
end)

test("Format.Delta / Resolve", function()
	local d, trend, better = Format.Delta(10, 15)
	eq(d, 5)
	eq(trend, "up")
	eq(better, true)
	d, trend, better = Format.Delta(10, 15, false)
	eq(better, false)
	d, trend, better = Format.Delta(20, 12)
	eq(trend, "down")
	eq(better, false)
	d, trend = Format.Delta(3, 3)
	eq(trend, "same")
	eq(Format.Resolve("percent")(0.25), "25%")
	eq(Format.Resolve("short")(12345), "12.3K")
	eq(Format.Resolve("duration", "ru")(65), "1м 05с")
	eq(Format.Resolve(nil)(5), "5")
end)

-- LAYOUT ------------------------------------------------------------------------------------------
test("Layout.Classify", function()
	local desktop = Layout.Classify(1920, 1022)
	truthy(not desktop.Phone, "1920x1022 is desktop")
	local landscape = Layout.Classify(812, 317, true)
	truthy(landscape.Phone and landscape.Landscape, "812x317 phone landscape")
	local portrait = Layout.Classify(390, 786, true)
	truthy(portrait.Phone and not portrait.Landscape, "390x786 phone portrait")
	truthy(not Layout.Classify(1024, 710).Phone, "1024x710 tablet/laptop is desktop")
	truthy(Layout.Classify(1280, 500).Phone, "short window is compact")
end)

test("Layout.WindowRect", function()
	local x, y, w, h = Layout.WindowRect(0, 58, 1920, 1022, false, 1040, 760, 28)
	eq(w, 1040)
	eq(h, 760)
	eq(x, 440)
	eq(y, 58 + 131)
	x, y, w, h = Layout.WindowRect(0, 58, 1280, 662, false, 1040, 760, 28)
	eq(w, 1040)
	eq(h, 606)
	truthy(y >= 58 and y + h <= 58 + 662, "fits vertically")
	x, y, w, h = Layout.WindowRect(44, 36, 724, 318, true, 1040, 760, 28)
	eq(x, 44)
	eq(y, 36)
	eq(w, 724)
	eq(h, 318)
end)

test("Layout.Columns", function()
	local cols, cell = Layout.Columns(1000, 156, 10, 10)
	eq(cols, 5)
	eq(cell, 188)
	cols, cell = Layout.Columns(300, 156, 10, 10)
	eq(cols, 1)
	eq(cell, 280)
	cols = Layout.Columns(1000, 156, 10, 10, 3)
	eq(cols, 3)
	cols, cell = Layout.Columns(20, 156, 10, 10)
	eq(cols, 1)
	truthy(cell >= 1)
	-- Cells plus gaps never exceed the width.
	for width = 120, 2000, 37 do
		for _, minCell in { 80, 120, 156, 210 } do
			local c, w = Layout.Columns(width, minCell, 10, 10)
			truthy(c * w + (c - 1) * 10 + 20 <= math.max(width, minCell + 20), "fits " .. width .. "/" .. minCell)
			truthy(c == 1 or w >= minCell, "cell >= min " .. width .. "/" .. minCell)
		end
	end
end)

test("Layout.CanvasHeight / CellPosition", function()
	eq(Layout.CanvasHeight(500, 5, 206, 10, 10), 20 + 100 * 206 + 99 * 10)
	eq(Layout.CanvasHeight(0, 5, 206, 10, 10), 0)
	eq(Layout.CanvasHeight(1, 5, 206, 10, 10), 226)
	local x, y = Layout.CellPosition(1, 5, 188, 206, 10, 10)
	eq(x, 10)
	eq(y, 10)
	x, y = Layout.CellPosition(7, 5, 188, 206, 10, 10)
	eq(x, 10 + 198)
	eq(y, 10 + 216)
end)

test("Layout.VisibleRange", function()
	local first, last = Layout.VisibleRange(0, 600, 500, 5, 206, 10, 10, 0)
	eq(first, 1)
	eq(last, 15)
	first, last = Layout.VisibleRange(0, 600, 500, 5, 206, 10, 10, 1)
	eq(first, 1)
	eq(last, 20)
	first, last = Layout.VisibleRange(1000, 600, 500, 5, 206, 10, 10, 0)
	eq(first, 21)
	eq(last, 40)
	first, last = Layout.VisibleRange(0, 600, 0, 5, 206, 10, 10, 1)
	eq(last < first, true, "empty")
	-- Last row partially filled.
	local bottom = Layout.ClampScroll(1e6, Layout.CanvasHeight(503, 5, 206, 10, 10), 600)
	first, last = Layout.VisibleRange(bottom, 600, 503, 5, 206, 10, 10, 0)
	eq(last, 503)
	eq(first, 491) -- rows 98..100 (600 px shows three 216 px rows)
	-- Brute force: the range is exactly the cells intersecting the viewport (+ overscan rows).
	local seed = 12345
	local function rand(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	for _ = 1, 400 do
		local count = rand(700)
		local cols = 1 + rand(6)
		local rowH = 40 + rand(200)
		local gap = rand(14)
		local pad = rand(14)
		local viewH = 100 + rand(900)
		local canvas = Layout.CanvasHeight(count, cols, rowH, gap, pad)
		local scroll = Layout.ClampScroll(rand(math.max(1, canvas)), canvas, viewH)
		local overscan = rand(3)
		local f, l = Layout.VisibleRange(scroll, viewH, count, cols, rowH, gap, pad, overscan)
		local rows = math.ceil(count / cols)
		local lo, hi
		for r = 0, rows - 1 do
			local top = pad + r * (rowH + gap)
			if top < scroll + viewH and top + rowH > scroll then
				lo = lo or r
				hi = r
			end
		end
		if count == 0 or not lo then
			truthy(l < f or count > 0, "nothing visible")
		else
			lo = math.max(0, lo - overscan)
			hi = math.min(rows - 1, hi + overscan)
			eq(f, lo * cols + 1, "first")
			eq(l, math.min(count, (hi + 1) * cols), "last")
			truthy(l - f + 1 <= Layout.MaxCells(viewH, cols, rowH, gap, overscan), "bounded by MaxCells")
		end
	end
end)

test("Layout.ScrollToReveal / ClampScroll", function()
	eq(Layout.ClampScroll(-5, 1000, 400), 0)
	eq(Layout.ClampScroll(900, 1000, 400), 600)
	eq(Layout.ClampScroll(100, 300, 400), 0)
	-- Cell 26 (row 5, top 10 + 5*216 = 1090) below a viewport at 0..600 -> scroll so it ends in view.
	local y = Layout.ScrollToReveal(26, 0, 600, 5, 206, 10, 10)
	eq(y, 1090 + 206 + 10 - 600)
	-- Already visible: unchanged.
	eq(Layout.ScrollToReveal(3, 0, 600, 5, 206, 10, 10), 0)
	-- Above the viewport.
	eq(Layout.ScrollToReveal(1, 800, 600, 5, 206, 10, 10), 0)
end)

-- THEME SYNC --------------------------------------------------------------------------------------
local function rgb(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
-- Parses `{key=C(r,g,b), other=U.Colors.x, ['Two words']=U.Colors.y}` (also Color3.fromRGB)
-- into key -> "r,g,b".
local function parseColors(body, refs)
	local out = {}
	for key, r, g, b in string.gmatch(body, "([%w_]+)=C%((%d+),(%d+),(%d+)%)") do
		out[key] = r .. "," .. g .. "," .. b
	end
	for key, r, g, b in string.gmatch(body, "([%w_]+)=Color3%.fromRGB%((%d+),(%d+),(%d+)%)") do
		out[key] = r .. "," .. g .. "," .. b
	end
	if refs then
		for key, ref in string.gmatch(body, "([%w_]+)=U%.Colors%.(%w+)") do
			out[key] = refs[ref]
		end
		for key, ref in string.gmatch(body, "%['([^']+)'%]=U%.Colors%.(%w+)") do
			out[key] = refs[ref]
		end
	end
	return out
end

test("Theme mirrors UITheme colours, rarities and icons", function()
	local source = read("src/StarterGui/ScreenGui/Modules/UITheme.luau")
	local colors = parseColors(string.match(source, "U%.Colors=(%b{})"))
	local n = 0
	for key, value in colors do
		eq(rgb(Theme.Colors[key]), value, "Colors." .. key)
		n += 1
	end
	eq(n, 15, "UITheme colour count")
	local rarity = parseColors(string.match(source, "U%.Rarity=(%b{})"), colors)
	for key, value in rarity do
		truthy(Theme.Rarity[key], "Theme.Rarity has " .. key)
		eq(rgb(Theme.Rarity[key]), value, "Rarity." .. key)
	end
	truthy(rarity["Brainrot God"] ~= nil, "parsed Brainrot God")
	local assets = string.match(source, "U%.Assets=(%b{})")
	for key, id in string.gmatch(assets, "(%w+)='(rbxassetid://%d+)'") do
		eq(Theme.Icons[key], id, "Icons." .. key)
	end
end)

test("Theme covers every variant, mutation and item rarity", function()
	local config = read("src/ReplicatedStorage/DogEconomy/Config.luau")
	local variants = string.match(config, "C%.Variants=(%b{})")
	local count = 0
	for name in string.gmatch(variants, 'Name="(%w+)"') do
		truthy(Theme.Variant[name], "Theme.Variant." .. name)
		truthy(Theme.VariantRank[name], "Theme.VariantRank." .. name)
		count += 1
	end
	eq(count, 6, "variant count")
	local lab = parseColors(string.match(read("src/ReplicatedStorage/LabConfig.luau"), "C%.Colors=(%b{})"))
	for name, value in lab do
		eq(rgb(Theme.Variant[name]), value, "Variant colour " .. name .. " = LabConfig.Colors")
	end
	local values = read("src/ReplicatedStorage/ItemValueConfig.luau")
	local mutations = string.match(values, "Mutation=(%b{})")
	count = 0
	for name in string.gmatch(mutations, "(%u+)=") do
		truthy(Theme.Mutation[name], "Theme.Mutation." .. name)
		count += 1
	end
	truthy(count >= 16, "mutation count " .. count)
	for name in string.gmatch(string.match(values, "Rarity=(%b{})"), "Name='(%w+)'") do
		truthy(Theme.ItemRarity[name], "Theme.ItemRarity." .. name)
		truthy(Theme.RarityRank[name], "Theme.RarityRank." .. name)
	end
	-- Dog rarities (Config.Rarities).
	for name in string.gmatch(string.match(config, "C%.Rarities=(%b{})"), '"(%w+)"') do
		truthy(Theme.Rarity[name], "Theme.Rarity." .. name)
	end
	-- Rank order.
	truthy(Theme.RarityOrder("Secret") > Theme.RarityOrder("Mythic"), "Secret above Mythic")
	truthy(Theme.RarityOrder("Uncommon") > Theme.RarityOrder("Common"), "Uncommon above Common")
	eq(Theme.RarityOrder("Nope"), 0)
	eq(Theme.Hex(Color3.fromRGB(255, 16, 0)), "#FF1000")
	eq(Theme.OnColor(Theme.White), Theme.Colors.text)
	eq(Theme.OnColor(Theme.Colors.edge), Theme.White)
end)

-- LOCALIZATION ------------------------------------------------------------------------------------
test("every kit word has exactly one Russian translation", function()
	local base = {}
	local auto = read("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en, ru in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"([^"]*)"') do
		base[en] = ru
	end
	local kitDict = require("../src/ReplicatedStorage/Localization/Kit")
	truthy(type(kitDict.Exact) == "table" and type(kitDict.Patterns) == "table" and type(kitDict.Phrases) == "table", "dictionary shape")
	local words = {}
	for _, word in Lang.Words do
		words[word] = true
	end
	for name in Theme.Rarity do
		words[Lang.Upper(name)] = true
	end
	for name in Theme.Variant do
		if name ~= "Normal" then
			words[Lang.Upper(name)] = true
		end
	end
	for name in Theme.Mutation do
		if name ~= "NORMAL" then
			words[name] = true
		end
	end
	local missing = {}
	for word in words do
		if not base[word] and not kitDict.Exact[word] then
			table.insert(missing, word)
		end
	end
	table.sort(missing)
	eq(#missing, 0, "untranslated kit words: " .. table.concat(missing, ", "))
	-- No duplicates of the base dictionary (an Exact entry would silently override it).
	for en, ru in kitDict.Exact do
		truthy(base[en] == nil, "Localization.Kit repeats a base entry: " .. en)
		truthy(type(ru) == "string" and ru ~= "" and not string.find(ru, "[A-Za-z]"), "Russian text for " .. en)
	end
end)

test("Lang.T / Override", function()
	Lang.Override = "ru"
	eq(Lang.Get(), "ru")
	eq(Lang.T("BUY", "КУПИТЬ"), "КУПИТЬ")
	eq(Lang.T("BUY"), "BUY")
	Lang.Override = "en"
	eq(Lang.T("BUY", "КУПИТЬ"), "BUY")
	Lang.Override = nil
	eq(Lang.Word("HOLD"), "HOLD TO CONFIRM")
	eq(Lang.Word("UNKNOWN_KEY"), "UNKNOWN_KEY")
	eq(Lang.Upper("Brainrot God"), "BRAINROT GOD")
end)

print(string.format("uikit: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("uikit tests failed")
end
