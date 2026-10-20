--!nocheck
-- CHAPTER II UI, headless: lune run tests/underyard_ui.luau [layout_dump_dir]
-- Runs the REAL Modules.UnderyardScreen (Kit window "Underyard") on tests/lib/client_env.luau against Chapter II views made
-- by the REAL server feature (Economy.Features.Underyard / .Halloween View on in-memory profiles), plus the pure rules of
-- ReplicatedStorage.Halloween.UnderyardView and the Chapter II parts of the HALLOWEEN window, the DogDex, UITheme and the
-- HUD. Checks: the window builds on phone portrait / landscape / desktop in English and Russian; every tab renders from a
-- sample view; the drop-rate table sums to exactly 100%; buttons send the right requests (C2SealOffer, C2TrialStart,
-- C2ContractClaim, C2ContractBonus, C2Exchange, C2CoffinOpen, C2DexClaim, C2Craft, C2Journal); REPLAY buttons only fire
-- Bus events; localization coverage and no duplicate keys. With a directory argument it also writes the visible GUI of
-- every layout as JSON draw lists (tools render them to PNG for a visual check).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")

local E = require("./lib/economy_env")
local CE = require("./lib/client_env")
local OUT = process.args[1]

local passed, failed = 0, 0
local function test(name, fn)
	local before = #CE.Errors
	local ok, err = pcall(fn)
	if ok and #CE.Errors > before then
		ok, err = false, "client errors: " .. table.concat(CE.Errors, "\n", before + 1)
	end
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
local function cyrillic(s)
	return type(s) == "string" and string.find(s, "[\208\209]") ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Server views (real feature code)
---------------------------------------------------------------------------------------------------------------------
local Cfg = E.Require("ReplicatedStorage.Halloween.Chapter2Config")
local Rules = E.Require("ReplicatedStorage.Halloween.Chapter2Rules")
local UF = E.Require("ServerScriptService.Economy.Features.Underyard")
local HF = E.Require("ServerScriptService.Economy.Features.Halloween")

local DAY = 86400
local START = Rules.UnixFromDate(2026, 10, 20)
local NOW = START + 3 * DAY + 3600 -- Oct 23 01:00 UTC: seals I-V open, VI opens tomorrow
E.Time = NOW

local function chapter1Done(p)
	-- the Chapter I checklist (Chapter2Config.Chapter1.Req), finished
	local h = p.Halloween
	h.Boss = { Best = 3 }
	h.Cauldron = { Invested = 420 }
	h.Stats = { Knocks = 9, BloodMoons = 1, Spots = 12 }
end

-- kind: "locked" (Chapter I half done) | "mid" (Chapter II under way) | "done" (everything cleared)
local function profile(kind)
	local p = { UserId = 77, DogDex = {}, Resources = { BellShards = 0, LuckyDust = 0 },
		Halloween = { Boss = { Best = 2 }, Cauldron = { Invested = 120 }, Stats = { Knocks = 7, BloodMoons = 0, Spots = 4 }, Skins = {}, Candy = 900 } }
	if kind == "locked" then
		HF.Shape(p)
		return p
	end
	chapter1Done(p)
	UF.EnsureDaily(p, NOW)
	local u = p.Underyard
	u.Chapter1.Complete, u.Chapter1.At, u.Chapter1.Notified = true, NOW - 2 * DAY, true
	u.RevealSeen, u.Entered = true, true
	u.Tutorial.Step, u.Tutorial.Done = #Cfg.Tutorial.Steps, true
	p.Resources.BellShards, p.Resources.LuckyDust = 640, 1250
	u.Keys, u.Fragments = 2, 60
	if kind == "mid" or kind == "mid3" then
		local s1 = u.Seals["1"]
		s1.Offered, s1.Cleared, s1.Gold, s1.At, s1.Best = true, true, true, NOW - DAY, 1840
		u.Seals["2"].Offered, u.Seals["2"].Cleared, u.Seals["2"].At = true, true, NOW - 3600
		u.Seals["3"].Offered = true
		if kind == "mid3" then -- seal III broken too: seal IV waits for its offering
			u.Seals["3"].Cleared, u.Seals["3"].At = true, NOW - 600
		end
		p.DogDex.HW_BellPup, p.DogDex.HW_CandleCorgi, p.DogDex.HW_MourningShiba = true, true, true
		local list = u.Daily.Contracts.List
		list[1].Progress = list[1].Goal
		list[2].Progress = math.floor(list[2].Goal / 2)
		u.Daily.Raw, u.Daily.Eff, u.Daily.Exchange, u.Daily.Doors = 620, 540, 12, 1
		u.Rested.Pool = 120
		u.Owned.Decor[Cfg.Decor.Order[4]] = true
		u.Owned.Finds[Cfg.Finds.Order[1]] = true
		u.Owned.Finds[Cfg.Finds.Order[7]] = true
		p.Halloween.Skins[Cfg.Skins.Order[1]] = true
		u.Coffins.Opened = 3
		u.Coffins.Last = {
			{ Key = Cfg.Finds.Order[7], Kind = "Find", Id = Cfg.Finds.Order[7], Amount = 1, Rank = 3, At = NOW - 400 },
			{ Key = "Shards", Kind = "Shards", Amount = 120, Rank = 1, At = NOW - 7200 },
			{ Key = Cfg.Decor.Order[4], Kind = "Decor", Id = Cfg.Decor.Order[4], Amount = 1, Rank = 2, Converted = true, At = NOW - 2 * DAY },
		}
		for _, key in ipairs({ "chapter1", "reveal", "descend", "seal1", "seal2" }) do
			u.Journal[key] = NOW - 2 * DAY
		end
		u.JournalRead.chapter1, u.JournalRead.reveal = true, true
	else
		for i = 1, 7 do
			local s = u.Seals[tostring(i)]
			s.Offered, s.Cleared, s.Gold, s.At, s.Best = true, true, i ~= 5, NOW - DAY, 2000 + i
		end
		for _, id in ipairs(Cfg.Dogs.Order) do
			p.DogDex[id] = true
		end
		for _, id in ipairs(Cfg.Decor.Order) do
			u.Owned.Decor[id] = true
		end
		for _, id in ipairs(Cfg.Finds.Order) do
			u.Owned.Finds[id] = true
		end
		for _, id in ipairs(Cfg.Skins.Order) do
			p.Halloween.Skins[id] = true
		end
		for _, tier in ipairs(Cfg.Dex2Rewards) do
			u.Dex2Claims[tostring(tier.Count)] = true
		end
		for _, key in ipairs(Cfg.Journal.Order) do
			u.Journal[key] = NOW - DAY
			u.JournalRead[key] = true
		end
		for _, row in ipairs(u.Daily.Contracts.List) do
			row.Progress, row.Claimed = row.Goal, true
		end
		u.Daily.Contracts.AllClaimed = true
		u.Keys = Cfg.Coffin.MaxKeys
	end
	UF.Shape(p)
	HF.Shape(p)
	return p
end
local function views(kind)
	local p = profile(kind)
	local hv = HF.View(p, NOW)
	return hv, hv.Chapter2, p
end

---------------------------------------------------------------------------------------------------------------------
-- The client
---------------------------------------------------------------------------------------------------------------------
CE.Unix = NOW
-- FredokaOne advance widths (per 1 px of TextSize, ASCII 32..126); Cyrillic falls back to a sans font in Roblox
local FREDOKA = { 0.253, 0.267, 0.429, 0.749, 0.475, 0.838, 0.748, 0.208, 0.384, 0.384, 0.503, 0.527, 0.238, 0.433, 0.237, 0.526,
	0.608, 0.407, 0.609, 0.608, 0.592, 0.53, 0.56, 0.561, 0.582, 0.56, 0.238, 0.237, 0.627, 0.478, 0.627, 0.512, 0.908, 0.765,
	0.646, 0.679, 0.704, 0.638, 0.637, 0.714, 0.699, 0.257, 0.549, 0.639, 0.587, 0.87, 0.72, 0.775, 0.632, 0.83, 0.631, 0.583,
	0.731, 0.726, 0.783, 0.999, 0.741, 0.686, 0.643, 0.348, 0.528, 0.348, 0.526, 0.826, 0.482, 0.596, 0.592, 0.517, 0.598, 0.573,
	0.45, 0.585, 0.605, 0.255, 0.252, 0.536, 0.327, 0.851, 0.606, 0.6, 0.582, 0.582, 0.457, 0.489, 0.449, 0.606, 0.638, 0.793,
	0.567, 0.604, 0.586, 0.381, 0.217, 0.381, 0.651 }
CE.TextWidth = function(text, size)
	local w = 0
	local ok = pcall(function()
		for _, c in utf8.codes(text) do
			if c >= 32 and c <= 126 then
				w += FREDOKA[c - 31]
			elseif (c >= 0x410 and c <= 0x42F) or c == 0x401 then
				w += 0.74
			elseif (c >= 0x430 and c <= 0x44F) or c == 0x451 then
				w += 0.63
			elseif c >= 0x1F000 then
				w += 1.1
			else
				w += 0.6
			end
		end
	end)
	if not ok then
		w = #text * 0.55
	end
	return w * size
end
-- audio cues the window asks for (the real Halloween.Audio needs Debris)
local cues = {}
CE.Overrides["Halloween/Audio"] = {
	Has = function()
		return true
	end,
	Play = function(cue)
		table.insert(cues, cue)
	end,
}
-- Roblox defaults the fake instance leaves unset
do
	local new = CE.Instance.new
	CE.Instance.new = function(className, parent)
		local o = new(className, parent)
		if className == "ScrollingFrame" then
			o.CanvasPosition = roblox.Vector2.zero
			o.CanvasSize = roblox.UDim2.new()
		elseif className == "UIScale" then
			o.Scale = 1
		end
		return o
	end
end
local RSFake = CE.MountReplicated()
local HW = RSFake.Halloween
local remotes = CE.Folder("Remotes", HW)
local request = CE.Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = remotes
local stateFolder = CE.Folder("State", HW)
local c2State = CE.Folder("Chapter2", stateFolder)
c2State:SetAttribute("Enabled", true)

local P = CE.Player
CE.Spawn(roblox.Vector3.new(0, 3, 0))

local current = { HView = nil }
local calls = {}
local replies = {}
CE.OnInvoke = function(remote, action, args)
	table.insert(calls, { Remote = remote.Name, Action = action, Args = args })
	local fn = replies[action]
	if fn then
		return fn(args)
	end
	return true, { View = current.HView }
end
local function lastCall(action)
	for i = #calls, 1, -1 do
		if calls[i].Action == action then
			return calls[i]
		end
	end
	return nil
end

local function setAttributes(cv, hv)
	P:SetAttribute("HalloweenChapter1Complete", cv.Chapter1 and cv.Chapter1.Complete == true)
	P:SetAttribute("BellShards", cv.Shards)
	P:SetAttribute("CoffinKeys", cv.Keys)
	P:SetAttribute("LuckyDust", cv.Dust)
	P:SetAttribute("MoonCandy", math.max(tonumber(hv.Candy) or 0, 900)) -- the Toll Box needs candy
	P:SetAttribute("UySealMask", cv.Mask)
end

local gui = CE.MainGui()
local Kit = CE.Require(gui.Modules.Kit)
Kit.SetNavigation(false)
local Lang = CE.Require(gui.Modules.Kit.Lang)
local Bus = CE.Require(HW.Bus)
local UV = CE.Require(HW.UnderyardView)
local Screen = CE.Require(gui.Modules.UnderyardScreen)

local function load(kind)
	local hv, cv = views(kind)
	current.HView = hv
	setAttributes(cv, hv)
	Bus.Fire("StateChanged", { View = hv })
	return hv, cv
end

---------------------------------------------------------------------------------------------------------------------
-- Pure rules (ReplicatedStorage.Halloween.UnderyardView)
---------------------------------------------------------------------------------------------------------------------
local function ctxOf(c)
	return { Eligible = c.Eligible ~= false, InZone = c.InZone == true, InTrial = c.InTrial == true, Shards = c.Shards or 0, Keys = c.Keys or 0,
		Near = function(anchor)
			return c.Near == anchor
		end }
end
test("drop rates: every chance is Chapter2Rules.CoffinChance and the table sums to exactly 100%", function()
	local t = UV.DropTable()
	local sum, rows, weight = 0, 0, 0
	for _, g in ipairs(t.Groups) do
		local gs = 0
		for _, r in ipairs(g.Rows) do
			rows += 1
			weight += r.Weight
			gs += r.Chance
			eq(r.Chance, r.Weight / Rules.CoffinTotal(Cfg), "chance of " .. tostring(r.Key))
		end
		truthy(math.abs(gs - g.Chance) < 1e-12, "group " .. g.Id .. " sums its rows")
		if g.Tiers then
			local ts = 0
			for _, tier in ipairs(g.Tiers) do
				ts += tier.Chance
			end
			truthy(math.abs(ts - g.Chance) < 1e-12, "find tiers sum to the group")
		end
		sum += g.Chance
	end
	eq(rows, #Cfg.Coffin.Table, "every table row is listed")
	eq(weight, Cfg.Coffin.TotalWeight, "weights")
	truthy(math.abs(sum - 1) < 1e-12 and math.abs(t.Total - 1) < 1e-12, "sum " .. sum)
	-- the shown percentages (three decimals, exact for a 100 000 table) add up to 100
	local shown = 0
	for _, g in ipairs(t.Groups) do
		for _, r in ipairs(g.Rows) do
			shown += tonumber((string.gsub(UV.Percent(r.Chance), "%%", ""))) or 0
		end
	end
	truthy(math.abs(shown - 100) < 1e-6, "percent strings add up to 100: " .. shown)
	eq(UV.Percent(0.27682), "27.682%")
	eq(UV.Percent(0.15), "15%")
	eq(UV.Percent(0.00004), "0.004%")
	eq(UV.Odds(0.00004), "25,000")
end)

test("seal states: date lock, previous seal, offering (catch-up discount, the guide pays), trial, doors, gold", function()
	local _, cv = views("mid")
	local s4 = UV.SealState(cv, 4, NOW, ctxOf({ InZone = true, Shards = 640 }))
	eq(s4.State, "Previous", "IV waits for III")
	local s6 = UV.SealState(cv, 6, NOW, ctxOf({ InZone = true, Shards = 640 }))
	eq(s6.State, "Waiting", "VI opens tomorrow")
	eq(s6.Action, "Opens")
	truthy(s6.OpensIn > 0 and s6.OpensIn <= DAY, "countdown")
	local s3 = UV.SealState(cv, 3, NOW, ctxOf({ InZone = true, Near = UV.StartAnchor(3) }))
	eq(s3.State, "Trial")
	eq(s3.Action, "Begin", "at the start point")
	eq(UV.SealState(cv, 3, NOW, ctxOf({ InZone = true })).Action, "WayTrial", "elsewhere: the way")
	eq(UV.SealState(cv, 3, NOW, ctxOf({ InZone = false })).Action, "Descend", "outside: descend")
	eq(UV.SealState(cv, 3, NOW, ctxOf({ InZone = true, InTrial = true })).Action, "InTrial")
	local _, cv3 = views("mid3")
	local o4 = UV.SealState(cv3, 4, NOW, ctxOf({ InZone = true, Shards = 640, Near = "SealAltar_4" }))
	eq(o4.State, "Offer")
	eq(o4.Action, "Offer")
	eq(o4.Cost, cv3.Seals[4].Cost)
	local poor = UV.SealState(cv3, 4, NOW, ctxOf({ InZone = true, Shards = 10, Near = "SealAltar_4" }))
	eq(poor.Action, "Need")
	eq(poor.Missing, cv3.Seals[4].Cost - 10)
	-- seal I opened 3 days ago: the catch-up discount
	local _, fresh = views("locked")
	local s1 = UV.SealState(fresh, 1, NOW, ctxOf({ Eligible = false }))
	eq(s1.Action, "Locked", "Chapter I first")
	truthy(cv.Seals[1].Discount and cv.Seals[1].Cost < Cfg.Seals[1].Offering, "seal I discounted")
	-- Gold / cleared
	eq(UV.SealState(cv, 1, NOW, ctxOf({ InZone = true })).State, "Gold")
	eq(UV.SealState(cv, 2, NOW, ctxOf({ InZone = true })).State, "Cleared")
	eq(UV.StartAnchor(2), "RunStart")
	eq(UV.StartAnchor(5), "DoorCourt")
	eq(UV.StartAnchor(1), "SealAltar_1")
end)

test("objective line and badges", function()
	local _, locked = views("locked")
	local o = UV.Objective(locked, NOW, ctxOf({ Eligible = false }))
	eq(o.Kind, "Chapter1")
	local title, line = UV.ObjectiveText(o, "en", NOW)
	eq(title, "CHAPTER II")
	eq(line, "Finish Chapter I: 2 / 5")
	local _, cv = views("mid")
	o = UV.Objective(cv, NOW, ctxOf({ InZone = true }))
	eq(o.Kind, "Trial")
	eq(o.Seal, 3)
	title, line = UV.ObjectiveText(o, "ru", NOW)
	truthy(cyrillic(title) and cyrillic(line), "Russian objective: " .. title .. " / " .. line)
	local b = UV.Badges(cv, nil, NOW, ctxOf({ InZone = true, Shards = 640, Keys = 2 }))
	truthy(b.contracts >= 1, "a finished contract to claim")
	truthy(b.dex >= 1, "a Dex II milestone to claim")
	truthy(b.journal >= 1, "unread journal entries")
	eq(b.Total, b.seals + b.contracts + b.coffin + b.dex + b.journal)
	local _, done = views("done")
	eq(UV.Objective(done, NOW, ctxOf({ InZone = true })).Kind, "Done")
end)

test("journal replays are Bus events only (§24.3)", function()
	for _, key in ipairs(Cfg.Journal.Order) do
		for _, r in ipairs(UV.JournalReplays(key)) do
			truthy(r.Bus == "C2Replay" or r.Bus == "Onboarding" or r.Bus == "CauldronClaimLocal", key .. ": " .. tostring(r.Bus))
			truthy(r.Request == nil and r.Action == nil, "no request")
			truthy(type(r.Label) == "table" and cyrillic(r.Label[2]), "label pair")
		end
	end
	eq(UV.JournalReplays("seal4")[1].Data.Seal, 4)
	eq(UV.JournalReplays("reveal")[1].Data.Id, "Reveal")
	eq(UV.JournalReplays("finale")[1].Data.Id, "Finale")
end)

---------------------------------------------------------------------------------------------------------------------
-- Localization: every self-localized string has Russian, no key is repeated
---------------------------------------------------------------------------------------------------------------------
local Own = E.Require("ReplicatedStorage.Localization.UnderyardUI")
local Base = E.Require("ReplicatedStorage.Localization.Underyard")
test("localization: every T / F literal of the Chapter II UI has Russian with the same placeholders", function()
	local files = {
		{ "src/StarterGui/ScreenGui/Modules/UnderyardScreen.luau", "[^%w_.:]([TF])%(\"(.-)\"" },
		{ "src/ReplicatedStorage/Halloween/UnderyardView.luau", "UV%.([TF])%(\"(.-)\"" },
		{ "src/StarterPlayer/StarterPlayerScripts/HalloweenClient/HUD/Chapter2.luau", "[^%w_.:]([TF])%(\"(.-)\"" },
		{ "src/StarterGui/ScreenGui/Modules/HalloweenScreen.luau", "U([TF])%(\"(.-)\"" },
		{ "src/StarterGui/ScreenGui/Modules/DogdexScreen.luau", "U([TF])%(\"(.-)\"" },
	}
	local missing, total = {}, 0
	for _, f in ipairs(files) do
		local source = fs.readFile(f[1])
		for kind, en in string.gmatch(source, f[2]) do
			total += 1
			local ru
			if kind == "T" then
				ru = Own.UI[en] or Base.UI[en] or Own.Exact[en] or Base.Exact[en]
			else
				ru = Own.Templates[en] or Base.Templates[en]
			end
			if not ru then
				table.insert(missing, f[1]:match("[^/]+$") .. " " .. kind .. ": " .. en)
			else
				for _, form in ipairs(type(ru) == "table" and ru or { ru }) do
					local bare = string.gsub(en, "%%[%d%.]*[dsf]", "")
					truthy(cyrillic(form) or not string.find(bare, "%a"), "Russian for " .. en)
					local _, a = string.gsub(en, "%%[%d%.]*[dsf]", "")
					local _, b = string.gsub(form, "%%[%d%.]*[dsf]", "")
					eq(b, a, "placeholders of " .. en)
				end
			end
		end
	end
	-- tips / tile / pills shown through UITheme.U.L and the HUD tooltips
	for _, en in ipairs({ "UNDERYARD", "Below the church: Bell Seals, daily contracts, the Black Coffin and the Dex II",
		"Earned in THE UNDERYARD. Offer them at the Bell Seal altars and open the Black Coffin.",
		"Dismantle Lucky Blocks for it in your bag and forge new Lucky Blocks with it.", "BELL SHARDS", "LUCKY DUST", "COFFIN KEYS",
		"Open the Black Coffin in Bell Square with one. Never sold.", "PUMPKIN BLOCK FOR EXORCISTS", "A PUMPKIN BLOCK FOR THE EXORCISTS" }) do
		total += 1
		if not (Own.UI[en] or Base.UI[en]) then
			table.insert(missing, "UI: " .. en)
		end
	end
	truthy(total > 150, "strings found: " .. total)
	eq(#missing, 0, table.concat(missing, " | "))
end)

test("localization: UnderyardUI repeats no key of Localization.Underyard, no Exact key of any dictionary or the base table", function()
	for _, section in ipairs({ "UI", "Templates", "Exact" }) do
		for en in pairs(Own[section]) do
			truthy(Base[section][en] == nil, "UnderyardUI." .. section .. " repeats Underyard: " .. en)
		end
	end
	for en in pairs(Own.UI) do
		truthy(Base.Exact[en] == nil, "UI key is an Underyard Exact key: " .. en)
	end
	local base = {}
	local auto = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DOGROTS_AutoTranslateUI.client.luau")
	for en in string.gmatch(auto, '%["([^"]+)"%]%s*=%s*"') do
		base[en] = true
	end
	for _, name in ipairs(fs.readDir("src/ReplicatedStorage/Localization")) do
		if name ~= "UnderyardUI.luau" then
			local other = E.Require("ReplicatedStorage.Localization." .. name:gsub("%.luau$", ""))
			for en in pairs(Own.Exact) do
				truthy(not (type(other) == "table" and other.Exact and other.Exact[en]), "Exact key also in " .. name .. ": " .. en)
				truthy(not base[en], "Exact repeats the base dictionary: " .. en)
			end
		end
	end
	-- every Underyard dog has its ability in both languages
	for _, id in ipairs(Cfg.Dogs.Order) do
		local d = Own.Dogs[id]
		truthy(d and cyrillic(d.Ability[2]) and cyrillic(d.Text[2]) and d.Ability[1] ~= "" and d.Text[1] ~= "", "ability of " .. id)
	end
	-- Format / Translate
	eq(Own.Format("%d UNDERYARD DOGS FOUND", "ru", 3), "НАЙДЕНО 3 СОБАКИ ПОДДВОРЬЯ")
	eq(Own.Format("%d UNDERYARD DOGS FOUND", "ru", 5), "НАЙДЕНО 5 СОБАК ПОДДВОРЬЯ")
	eq(Own.Format("%d UNDERYARD DOGS FOUND", "ru", 1), "НАЙДЕНА 1 СОБАКА ПОДДВОРЬЯ")
	eq(Own.Translate("SHOW THE WAY", "ru"), "ПОКАЗАТЬ ПУТЬ")
	eq(Own.Translate("SHOW THE WAY", "en"), nil)
end)

test("wiring: kit route, UITheme tile and pills, HALLOWEEN / HUD relabels", function()
	local gi = fs.readFile("src/StarterGui/ScreenGui/Modules/GUIIntegration.luau")
	truthy(string.find(gi, "kitScreens.Underyard='UnderyardScreen' -- [WP-L]", 1, true), "GUIIntegration kitScreens.Underyard")
	local theme = fs.readFile("src/StarterGui/ScreenGui/Modules/UITheme.luau")
	truthy(string.find(theme, "key='Underyard',label='UNDERYARD'", 1, true) and string.find(theme, "when='HalloweenChapter1Complete'", 1, true), "UNDERYARD tile")
	truthy(string.find(theme, "key='BellShards',name='QuickShards'", 1, true), "Bell Shards pill")
	truthy(string.find(theme, "key='LuckyDust',name='QuickDust'", 1, true), "Lucky Dust pill")
	truthy(string.find(theme, "lp:GetAttribute(t.spec.when)==true", 1, true), "LayoutHUD hides tiles until their attribute is true")
	local hs = fs.readFile("src/StarterGui/ScreenGui/Modules/HalloweenScreen.luau")
	truthy(string.find(hs, 'Block = "PUMPKIN BLOCK FOR EXORCISTS"', 1, true), "HALLOWEEN exorcism milestone relabel")
	local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HalloweenClient/HUD.luau")
	truthy(string.find(hud, 'Block = "A PUMPKIN BLOCK FOR THE EXORCISTS"', 1, true), "HUD milestone relabel")
	-- presentation code never writes ProximityPromptService and uses Activated
	for _, file in ipairs({ "src/StarterGui/ScreenGui/Modules/UnderyardScreen.luau", "src/StarterGui/ScreenGui/Modules/UnderyardScreen/Waypoint.luau",
		"src/StarterPlayer/StarterPlayerScripts/HalloweenClient/HUD/Chapter2.luau" }) do
		local source = fs.readFile(file)
		truthy(not string.find(source, "ProximityPromptService", 1, true), file .. " touches ProximityPromptService")
		truthy(not string.find(source, "MouseButton1Click", 1, true), file .. " uses MouseButton1Click")
		truthy(not string.find(source, "Modal%s*=%s*true"), file .. " sinks input")
	end
end)

local SCREENS = {
	{ Id = "portrait", Size = roblox.Vector2.new(390, 844), Touch = true },
	{ Id = "landscape", Size = roblox.Vector2.new(844, 390), Touch = true },
	{ Id = "desktop", Size = roblox.Vector2.new(1280, 720), Touch = false },
}
local function screen(sc)
	if Screen.IsOpen() then
		Screen.Close()
		CE.Advance(0.6)
	end
	CE.Screen = sc.Size
	CE.Camera.ViewportSize = sc.Size
	CE.UserInputService.TouchEnabled = sc.Touch
	CE.UserInputService.KeyboardEnabled = not sc.Touch
end

local function layer()
	return CE.PlayerGui:FindFirstChild("KitWindows")
end

---------------------------------------------------------------------------------------------------------------------
-- Layout dump (absolute rectangles with the look of every visible object)
---------------------------------------------------------------------------------------------------------------------
local dumps = {}
local function color(c)
	return c and { math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5) } or nil
end
local function dump(label)
	if not OUT then
		return
	end
	local list = {}
	local function rect(o, px, py, pw, ph, scroll)
		local s, p, a = o.Size, o.Position, o.AnchorPoint or roblox.Vector2.zero
		local w = pw * s.X.Scale + s.X.Offset
		local h = ph * s.Y.Scale + s.Y.Offset
		local x = px + pw * p.X.Scale + p.X.Offset - a.X * w - (scroll and scroll.X or 0)
		local y = py + ph * p.Y.Scale + p.Y.Offset - a.Y * h - (scroll and scroll.Y or 0)
		return x, y, w, h
	end
	-- AutomaticSize X (kit pills): the width of the content
	local function autoW(o, ph)
		local pad = o:FindFirstChildWhichIsA("UIPadding")
		local extra = pad and ((pad.PaddingLeft and pad.PaddingLeft.Offset or 0) + (pad.PaddingRight and pad.PaddingRight.Offset or 0)) or 0
		if o:IsA("TextLabel") or o:IsA("TextButton") then
			return o.TextBounds.X + extra
		end
		local flow = o:FindFirstChildWhichIsA("UIListLayout")
		local horizontal = flow and flow.FillDirection == roblox.Enum.FillDirection.Horizontal
		local sum, best, n = 0, 0, 0
		for _, c in ipairs(o:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then
				local w = c.Size.X.Offset + (c.SizeConstraint == roblox.Enum.SizeConstraint.RelativeYY and c.Size.X.Scale * ph or 0)
				if w < 1 then
					w = autoW(c, ph)
				end
				n += 1
				sum += w
				best = math.max(best, w)
			end
		end
		if horizontal then
			return sum + math.max(0, n - 1) * (flow.Padding and flow.Padding.Offset or 0) + extra
		end
		return best + extra
	end
	local function walk(o, px, py, pw, ph, clip, depth, scroll, listLayout)
		local kids = {}
		for i, c in ipairs(o:GetChildren()) do
			table.insert(kids, { I = i, C = c })
		end
		table.sort(kids, function(a, b)
			local za = a.C:IsA("GuiObject") and a.C.ZIndex or 0
			local zb = b.C:IsA("GuiObject") and b.C.ZIndex or 0
			if za ~= zb then
				return za < zb
			end
			return a.I < b.I
		end)
		-- a UIListLayout (kit buttons and pills): children follow each other
		local flow = o:FindFirstChildWhichIsA("UIListLayout")
		local pad = o:FindFirstChildWhichIsA("UIPadding")
		local cx, cy, cw, ch = px, py, pw, ph
		if pad then
			local l = pad.PaddingLeft and (pad.PaddingLeft.Scale * pw + pad.PaddingLeft.Offset) or 0
			local t = pad.PaddingTop and (pad.PaddingTop.Scale * ph + pad.PaddingTop.Offset) or 0
			local r = pad.PaddingRight and (pad.PaddingRight.Scale * pw + pad.PaddingRight.Offset) or 0
			local b = pad.PaddingBottom and (pad.PaddingBottom.Scale * ph + pad.PaddingBottom.Offset) or 0
			cx, cy, cw, ch = px + l, py + t, pw - l - r, ph - t - b
		end
		local flowAt = 0
		local flowItems = {}
		if flow then
			local horizontal = flow.FillDirection == roblox.Enum.FillDirection.Horizontal
			local gap = flow.Padding and (flow.Padding.Offset + flow.Padding.Scale * (horizontal and cw or ch)) or 0
			local items = {}
			for _, k in ipairs(kids) do
				if k.C:IsA("GuiObject") and k.C.Visible then
					table.insert(items, k.C)
				end
			end
			table.sort(items, function(a, b)
				return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
			end)
			local total = 0
			local sizes = {}
			local flex = {}
			for i, c in ipairs(items) do
				local yy = c.SizeConstraint == roblox.Enum.SizeConstraint.RelativeYY
				local w = (yy and ch or cw) * c.Size.X.Scale + c.Size.X.Offset
				local h = ch * c.Size.Y.Scale + c.Size.Y.Offset
				local fill = c:FindFirstChildWhichIsA("UIFlexItem")
				if fill and fill.FlexMode == roblox.Enum.UIFlexMode.Fill then
					table.insert(flex, c)
				elseif c:IsA("TextLabel") and w < 1 and c.Text ~= "" then
					w = c.TextBounds.X -- AutomaticSize X
				end
				sizes[c] = { w, h }
				total += (horizontal and w or h) + (i > 1 and gap or 0)
			end
			if #flex > 0 and horizontal then
				local spare = math.max(0, cw - total) / #flex
				for _, c in ipairs(flex) do
					sizes[c][1] += spare
					total += spare
				end
			end
			local start = 0
			local align = horizontal and flow.HorizontalAlignment or flow.VerticalAlignment
			if align == roblox.Enum.HorizontalAlignment.Center or align == roblox.Enum.VerticalAlignment.Center then
				start = ((horizontal and cw or ch) - total) / 2
			elseif align == roblox.Enum.HorizontalAlignment.Right or align == roblox.Enum.VerticalAlignment.Bottom then
				start = (horizontal and cw or ch) - total
			end
			flowAt = start
			for _, c in ipairs(items) do
				local w, h = sizes[c][1], sizes[c][2]
				if horizontal then
					local y = cy + (ch - h) / 2
					if flow.VerticalAlignment == roblox.Enum.VerticalAlignment.Top then
						y = cy
					end
					flowItems[c] = { cx + flowAt, y, w, h }
					flowAt += w + gap
				else
					local x = cx + (cw - w) / 2
					if flow.HorizontalAlignment == roblox.Enum.HorizontalAlignment.Left then
						x = cx
					end
					flowItems[c] = { x, cy + flowAt, w, h }
					flowAt += h + gap
				end
			end
		end
		for _, k in ipairs(kids) do
			local c = k.C
			if c:IsA("GuiObject") and c.Visible then
				local x, y, w, h
				if flowItems[c] then
					x, y, w, h = table.unpack(flowItems[c])
				else
					x, y, w, h = rect(c, cx, cy, cw, ch, scroll)
					local auto = c.AutomaticSize
					if w < 1 and (auto == roblox.Enum.AutomaticSize.X or auto == roblox.Enum.AutomaticSize.XY) then
						local nw = autoW(c, h)
						x -= (c.AnchorPoint and c.AnchorPoint.X or 0) * nw
						w = nw
					end
				end
				local item = { N = c.Name, C = c.ClassName, X = x, Y = y, W = w, H = h, D = depth, Clip = clip, Bg = color(c.BackgroundColor3),
					Bt = c.BackgroundTransparency, Rot = c.Rotation ~= 0 and c.Rotation or nil }
				local corner = c:FindFirstChildWhichIsA("UICorner")
				if corner and corner.CornerRadius then
					item.R = corner.CornerRadius.Scale * math.min(w, h) + corner.CornerRadius.Offset
				end
				local stroke = c:FindFirstChildWhichIsA("UIStroke")
				if stroke and stroke.Enabled ~= false then
					item.St = { color(stroke.Color), stroke.Thickness or 1, stroke.Transparency or 0,
						stroke.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Border and "b" or "c" }
				end
				local grad = c:FindFirstChildWhichIsA("UIGradient")
				if grad and grad.Enabled ~= false and grad.Color then
					local keys = {}
					for _, kp in ipairs(grad.Color.Keypoints) do
						table.insert(keys, { kp.Time, color(kp.Value) })
					end
					local tk = nil
					if grad.Transparency then
						tk = {}
						for _, kp in ipairs(grad.Transparency.Keypoints) do
							table.insert(tk, { kp.Time, kp.Value })
						end
					end
					item.G = { keys, grad.Rotation or 0, tk }
				end
				if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
					local limit = c:FindFirstChildWhichIsA("UITextSizeConstraint")
					item.T = c.Text
					item.Ts = c.TextSize
					item.Tc = color(c.TextColor3)
					item.Tt = c.TextTransparency
					item.Sc = c.TextScaled or nil
					item.Wr = c.TextWrapped or nil
					item.Ax = c.TextXAlignment and c.TextXAlignment.Name or "Center"
					item.Ay = c.TextYAlignment and c.TextYAlignment.Name or "Center"
					item.Mx = limit and limit.MaxTextSize or nil
					item.Mn = limit and limit.MinTextSize or nil
					item.Rich = c.RichText or nil
					item.Stk = c.TextStrokeTransparency and c.TextStrokeTransparency < 1 and { color(c.TextStrokeColor3), c.TextStrokeTransparency } or nil
				end
				if c:IsA("ImageLabel") or c:IsA("ImageButton") then
					item.Img = c.Image
					item.Ic = color(c.ImageColor3)
					item.It = c.ImageTransparency
				end
				table.insert(list, item)
				local nclip = clip
				if c.ClipsDescendants or c:IsA("ScrollingFrame") then
					local cl = { x, y, x + w, y + h }
					if clip then
						cl = { math.max(cl[1], clip[1]), math.max(cl[2], clip[2]), math.min(cl[3], clip[3]), math.min(cl[4], clip[4]) }
					end
					nclip = cl
				end
				local nscroll = c:IsA("ScrollingFrame") and c.CanvasPosition or nil
				walk(c, x, y, w, h, nclip, depth + 1, nscroll)
			elseif c:IsA("LayerCollector") then
				walk(c, 0, 0, CE.Screen.X, CE.Screen.Y, nil, depth + 1, nil)
			end
		end
	end
	for _, name in ipairs({ "KitWindows", "KitOverlay", "KitToasts" }) do
		local g = CE.PlayerGui:FindFirstChild(name)
		if g and g.Enabled ~= false then
			walk(g, 0, 0, CE.Screen.X, CE.Screen.Y, nil, 0, nil)
		end
	end
	table.insert(dumps, { Label = label, Screen = { CE.Screen.X, CE.Screen.Y }, Items = list })
end

---------------------------------------------------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------------------------------------------------
test("the window opens on every tab, every screen, both languages", function()
	for _, kind in ipairs({ "mid", "locked", "done" }) do
		for _, lang in ipairs({ "en", "ru" }) do
			Lang.Override = lang
			for _, sc in ipairs(SCREENS) do
				screen(sc)
				load(kind)
				for _, tab in ipairs(Screen.Tabs) do
					Screen.Open(tab)
					CE.Advance(0.8)
					truthy(Screen.IsOpen(), "open " .. tab)
					dump(kind .. "_" .. lang .. "_" .. sc.Id .. "_" .. tab)
					-- the rest of the page, a screen at a time
					local scroll = OUT and kind ~= "locked" and Screen.Window and Screen.Window:Page(tab):FindFirstChild("Scroll", true)
					if scroll and scroll:IsA("ScrollingFrame") then
						local viewH = scroll.AbsoluteSize.Y
						local canvas = scroll.CanvasSize.Y.Offset
						local k = 1
						while k <= 6 and k * viewH * 0.85 < canvas - viewH * 0.4 do
							scroll.CanvasPosition = roblox.Vector2.new(0, math.min(canvas - viewH, k * viewH * 0.85))
							CE.Advance(0.1)
							dump(kind .. "_" .. lang .. "_" .. sc.Id .. "_" .. tab .. "_s" .. k)
							k += 1
						end
						scroll.CanvasPosition = roblox.Vector2.zero
					end
				end
			end
		end
	end
	Lang.Override = "en"
end)

-- buttons -> requests (the server is CE.OnInvoke: it answers ok with the same view unless a reply is set)
local Layout = CE.Require(HW.UnderyardLayout)
local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function shownButton(name)
	for _, d in ipairs(CE.PlayerGui:GetDescendants()) do
		if d.Name == name and d:IsA("GuiButton") and CE.Shown(d) then
			return d
		end
	end
	return nil
end
local function openOn(tab)
	if not Screen.IsOpen() then
		Screen.Open(tab)
	else
		Screen.Open(tab)
	end
	CE.Advance(0.6)
	return Screen.Window:Page(tab)
end
local function at(anchor)
	local pos = Layout.Anchor(anchor)
	assert(pos, "anchor " .. anchor)
	CE.MoveTo(pos + roblox.Vector3.new(2, 0, 0))
end
test("buttons send the right requests (seals, contracts, Toll Box, coffin, Dex II, tailor, journal)", function()
	Lang.Override = "en"
	screen(SCREENS[3])
	local hv, cv = load("mid")
	P:SetAttribute("UyInZone", true)
	P:SetAttribute("UyTrial", "")
	-- BEGIN TRIAL at the start of seal III (offered, playable)
	at(UV.StartAnchor(3))
	local page = openOn("seals")
	local n0 = #calls
	CE.Click(find(page, "Seal_3").Action)
	CE.Advance(0.3)
	local call = lastCall("C2TrialStart")
	truthy(call and #calls > n0, "C2TrialStart sent")
	eq(call.Args.Seal, 3, "trial of seal III")
	truthy(not Screen.IsOpen(), "the window closes for the trial")
	-- OFFER at altar IV (seal III broken, IV open and not offered, enough shards)
	load("mid3")
	at("SealAltar_4")
	page = openOn("seals")
	CE.Click(find(page, "Seal_4").Action)
	CE.Advance(0.3)
	call = lastCall("C2SealOffer")
	truthy(call, "C2SealOffer sent")
	eq(call.Args.Seal, 4)
	-- far from the altar: SHOW THE WAY (a waypoint, no request)
	at("CoffinShrine")
	page = openOn("seals")
	local before = #calls
	CE.Click(find(page, "Seal_4").Action)
	CE.Advance(0.3)
	eq(#calls, before, "no request on SHOW THE WAY")
	truthy(Screen.Waypoint and Screen.Waypoint.Active(), "a waypoint to the altar")
	truthy(CE.Workspace:FindFirstChild("DOGROTS_UnderyardWay"), "the marker exists")
	Screen.Waypoint.Clear("test")
	truthy(not CE.Workspace:FindFirstChild("DOGROTS_UnderyardWay"), "the marker is torn down")
	-- CONTRACTS: CLAIM the finished contract; the bonus stays locked
	page = openOn("contracts")
	local first = cv.Contracts.List[1]
	CE.Click(find(find(page, "Contract1"), "Claim"))
	CE.Advance(0.3)
	call = lastCall("C2ContractClaim")
	truthy(call, "C2ContractClaim sent")
	eq(call.Args.Id, first.Id)
	local bonusBtn = find(find(page, "Bonus"), "Claim")
	eq(CE.Click(bonusBtn), false, "bonus locked until all three are claimed")
	-- THE TOLL BOX: next to it, + then BUY
	at("TollBox")
	page = openOn("contracts")
	CE.Click(find(page, "Plus"))
	CE.Click(find(page, "Buy"))
	CE.Advance(0.3)
	call = lastCall("C2Exchange")
	truthy(call, "C2Exchange sent")
	eq(call.Args.Shards, Screen.State.Amount, "the chosen amount")
	-- COFFIN: at the shrine with a key and shards -> the window closes and C2CoffinOpen goes out
	at("CoffinShrine")
	page = openOn("coffin")
	CE.Click(find(page, "Open"))
	CE.Advance(0.3)
	truthy(lastCall("C2CoffinOpen"), "C2CoffinOpen sent")
	truthy(not Screen.IsOpen(), "closed for the coffin's cinematic")
	-- DEX II: the 3-dog milestone
	page = openOn("dex")
	CE.Click(find(find(page, "Milestone1"), "Claim"))
	CE.Advance(0.3)
	call = lastCall("C2DexClaim")
	truthy(call, "C2DexClaim sent")
	eq(call.Args.Count, UV.Config.Dex2Rewards[1].Count)
	-- TAILOR: CRAFT -> confirm -> C2Craft
	page = openOn("collection")
	local decorId = nil
	for _, id in ipairs(UV.Config.Decor.Order) do
		if not cv.Owned.Decor[id] then
			decorId = id
			break
		end
	end
	CE.Click(find(find(page, "Decor_" .. decorId), "Craft"))
	CE.Advance(0.4)
	local confirm = shownButton("Confirm")
	truthy(confirm, "confirm dialog")
	CE.Click(confirm)
	CE.Advance(0.4)
	call = lastCall("C2Craft")
	truthy(call, "C2Craft sent")
	eq(call.Args.Id, decorId)
	-- JOURNAL: unread entries are marked read; REPLAY only fires Bus events
	CE.Advance(1)
	page = openOn("journal")
	CE.Advance(4)
	local marked = {}
	for _, c in ipairs(calls) do
		if c.Action == "C2Journal" then
			marked[c.Args.Key] = true
		end
	end
	truthy(marked.descend and marked.seal1 and marked.seal2, "unread entries marked read")
	local replays = {}
	local offs = {}
	for _, name in ipairs({ "C2Replay", "Onboarding", "CauldronClaimLocal" }) do
		table.insert(offs, Bus.On(name, function(d)
			table.insert(replays, { Name = name, Data = d })
		end))
	end
	local requests = #calls
	page = openOn("journal")
	CE.Click(find(find(page, "Entry_reveal"), "Replay1"))
	CE.Advance(0.6)
	page = openOn("journal")
	CE.Click(find(find(page, "Entry_chapter1"), "Replay1"))
	CE.Advance(0.6)
	page = openOn("journal")
	CE.Click(find(find(page, "Entry_seal2"), "Replay1"))
	CE.Advance(0.6)
	for _, off in ipairs(offs) do
		off.Disconnect()
	end
	-- (reopening the window may refresh the view with C2Hello; nothing else may go out)
	for k = requests + 1, #calls do
		eq(calls[k].Action, "C2Hello", "replays never send requests")
	end
	local seen = {}
	for _, r in ipairs(replays) do
		seen[r.Name .. ":" .. tostring(type(r.Data) == "table" and r.Data.Id or "")] = r.Data
	end
	truthy(seen["C2Replay:Reveal"] and seen["C2Replay:Reveal"].Replay == true, "C2Replay Reveal")
	truthy(seen["Onboarding:"] and seen["Onboarding:"].Replay == true, "Chapter I guide replay")
	truthy(seen["C2Replay:Seal"] and seen["C2Replay:Seal"].Seal == 2, "seal II replay")
	Screen.Close()
	CE.Advance(0.5)
	P:SetAttribute("UyInZone", false)
end)

local HS = CE.Require(gui.Modules.HalloweenScreen)
test("HALLOWEEN window: the CHAPTER II card and the dex CHAPTER I / CHAPTER II switch", function()
	Screen.Close()
	CE.Advance(0.5)
	for _, kind in ipairs({ "locked", "mid" }) do
		for _, lang in ipairs({ "en", "ru" }) do
			Lang.Override = lang
			for _, sc in ipairs(SCREENS) do
				screen(sc)
				if HS.IsOpen() then
					HS.Close()
					CE.Advance(0.5)
				end
				load(kind)
				HS.Open("event")
				CE.Advance(0.8)
				truthy(HS.IsOpen(), "HALLOWEEN open")
				dump("hs_" .. kind .. "_" .. lang .. "_" .. sc.Id .. "_event")
				HS.Open({ Tab = "dex", Chapter = 2 })
				CE.Advance(0.8)
				dump("hs_" .. kind .. "_" .. lang .. "_" .. sc.Id .. "_dex2")
				HS.Open({ Tab = "dex", Chapter = 1 })
				CE.Advance(0.5)
			end
		end
	end
	HS.Close()
	CE.Advance(0.5)
	Lang.Override = "en"
end)

-- the DogDex window reads the economy snapshot through Modules.Net
local snapshot = nil
local netChanged = CE.Signal.new()
CE.Overrides["Modules/Net"] = {
	Cached = function()
		return snapshot
	end,
	Snapshot = function()
		return snapshot
	end,
	Changed = netChanged,
	Request = function()
		return true, {}
	end,
	OnPush = function()
		return { Disconnect = function() end }
	end,
	Publish = function() end,
}
local function setSnapshot(kind)
	local hv, cv, p = views(kind)
	snapshot = { Profile = { DogDex = p.DogDex, Dogs = {}, DexFavorites = {} }, Features = { Dogdex = { DexStats = {} }, Halloween = hv, Underyard = cv } }
	return hv, cv, p
end
local Dex = CE.Require(gui.Modules.DogdexScreen)
test("DogDex: THE UNDERYARD COLLECTION tab (Dex II milestones through C2DexClaim, reply View on the Bus)", function()
	Lang.Override = "en"
	screen(SCREENS[3])
	local hv, cv = setSnapshot("mid")
	current.HView = hv
	setAttributes(cv, hv)
	Dex.OpenEvent(UV.Config.EventId)
	CE.Advance(0.8)
	truthy(Dex.IsOpen(), "DogDex open")
	eq(Dex.Window.Tab, "underyard", "opened on the Underyard tab")
	local ev = Dex.UI.Events[UV.Config.EventId]
	truthy(ev, "Underyard event page")
	local first = UV.Config.Dex2Rewards[1]
	local tier = ev.Tiers[first.Count]
	eq(tier.Button.Instance.Active ~= false, true, "3 dogs found: CLAIM")
	local fired = nil
	local off = Bus.On("StateChanged", function(d)
		fired = d
	end)
	local after = views("mid")
	replies.C2DexClaim = function(args)
		return true, { Count = args.Count, Rewards = { { Kind = "Shards", Amount = 300 }, { Kind = "Key", Amount = 1 } }, View = after }
	end
	CE.Click(tier.Button.Instance)
	CE.Advance(0.5)
	local call = lastCall("C2DexClaim")
	truthy(call, "C2DexClaim sent")
	eq(call.Args.Count, first.Count, "milestone count")
	truthy(fired and fired.View == after, "reply View fired as StateChanged")
	if type(off) == "function" then
		off()
	elseif type(off) == "table" and off.Disconnect then
		off:Disconnect()
	end
	replies.C2DexClaim = nil
	for _, lang in ipairs({ "en", "ru" }) do
		Lang.Override = lang
		for _, sc in ipairs(SCREENS) do
			Dex.Close()
			CE.Advance(0.5)
			screen(sc)
			Dex.OpenEvent(UV.Config.EventId)
			CE.Advance(0.8)
			dump("dex_mid_" .. lang .. "_" .. sc.Id .. "_underyard")
		end
	end
	Dex.Close()
	CE.Advance(0.5)
	Lang.Override = "en"
end)

-- HalloweenClient.HUD.Chapter2 with a recording HUD environment (the real UITheme needs the place's MainWindow)
local hcFolder = CE.Folder("HalloweenClient", CE.Service("StarterPlayer"))
CE.Mount("StarterPlayer/StarterPlayerScripts/HalloweenClient", hcFolder)
local C2HUD = CE.Require(hcFolder.HUD.Chapter2)
local Icons = CE.Require(HW.Icons)
local banners, toasts, tileBadges, layouts, popped = {}, {}, {}, 0, 0
local hudFrame = gui.HUD
local flyLayer = CE.Instance.new("Frame")
flyLayer.Name = "HalloweenFly"
flyLayer.Size = roblox.UDim2.fromScale(1, 1)
flyLayer.Parent = gui
local tileRoot = CE.Instance.new("Frame")
tileRoot.Name = "QuickUnderyard"
tileRoot.Parent = hudFrame
local tileButton = CE.Instance.new("TextButton")
tileButton.Name = "Open"
tileButton.Parent = tileRoot
local tileIcon = CE.Instance.new("ImageLabel")
tileIcon.Name = "CandyIcon"
tileIcon.Image = ""
tileIcon.Parent = tileButton
local FakeU = {
	PillSpecs = { { key = "Coins", name = "MoneyWidget", always = true }, { key = "Level", name = "XPWidget", always = true } },
	QuickTiles = { { key = "Underyard", root = tileRoot, button = tileButton, icon = tileIcon, spec = { key = "Underyard", when = "HalloweenChapter1Complete" } } },
	ChapterPills = {},
	HUD = { Touch = false, Layout = { Free = { Left = 120, Right = 1180, Top = 90, Bottom = 650 } } },
	RequestHUDLayout = function()
		layouts += 1
	end,
	SetTileBadge = function(key, text, color)
		table.insert(tileBadges, { Key = key, Text = text, Color = color })
	end,
	Pop = function()
		popped += 1
	end,
	L = function(en)
		return UV.T(en, Lang.Get and Lang.Get() or "en")
	end,
}
local fakeH = {
	Banner = function(data)
		table.insert(banners, data)
	end,
}
local function hudLabel(parent, props)
	local p = table.clone(props)
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	return Kit.Text(parent, p)
end
local function hudPill(name, glyph)
	local root = Kit.New("Frame", { Name = name, BackgroundTransparency = 1, Size = roblox.UDim2.fromOffset(138, 46), Visible = false })
	local holder = Kit.New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Size = roblox.UDim2.fromOffset(40, 40) }, root)
	hudLabel(holder, { Name = "Glyph", Text = glyph, TextSize = 30 })
	local value = hudLabel(root, { Name = "Value", Text = "0", TextSize = 28 })
	root.Parent = hudFrame
	return root, value, holder, root
end
local hudToast = Kit.Toast
test("HUD: objective line, Coffin Key pill, C2Announce banners, fly-ins, UNDERYARD tile", function()
	Lang.Override = "en"
	screen(SCREENS[3])
	Kit.Toast = function(text, opts)
		table.insert(toasts, text)
	end
	local hv, cv = load("mid")
	P:SetAttribute("UyInZone", true)
	P:SetAttribute("UyTrial", "")
	C2HUD.Start(fakeH, { Player = P, Gui = gui, Hud = hudFrame, U = FakeU, Kit = Kit, Bus = Bus, Shared = CE.Require(HW.Shared), Icons = Icons, Label = hudLabel,
		New = Kit.New, TextStroke = function() end, Glass = function() end, Audio = function(cue)
			table.insert(cues, cue)
		end, FlyLayer = flyLayer, Reduced = function()
			return false
		end, Low = function()
			return false
		end, Pill = hudPill })
	Bus.Fire("C2Changed", { View = cv })
	CE.Advance(1)
	local line = hudFrame:FindFirstChild("UnderyardObjective")
	truthy(line and line.Visible, "objective line in the Underyard")
	local o = UV.Objective(cv, CE.Unix, { Eligible = true, InZone = true, InTrial = false, Shards = cv.Shards, Keys = cv.Keys, Near = function()
		return false
	end })
	local title = UV.ObjectiveText(o, "en", CE.Unix)
	eq(line.Title.Text, title, "objective title")
	truthy(string.find(line.Title.Text, "BELL SEAL III", 1, true), "the current seal: " .. line.Title.Text)
	-- a trial hides it
	P:SetAttribute("UyTrial", "Echo")
	CE.Advance(0.6)
	truthy(not line.Visible, "hidden during a trial")
	P:SetAttribute("UyTrial", "")
	CE.Advance(0.6)
	truthy(line.Visible, "back after the trial")
	-- the Coffin Key pill: in the Underyard only
	local keys = hudFrame:FindFirstChild("QuickKeys")
	truthy(keys and (keys:GetAttribute("HUDValue") or 0) > 0, "key pill wanted in the Underyard")
	local hasSpec = false
	for _, spec in ipairs(FakeU.PillSpecs) do
		hasSpec = hasSpec or spec.key == "CoffinKeys"
	end
	truthy(hasSpec and FakeU.PillSpecs[#FakeU.PillSpecs].key == "Level", "CoffinKeys pill spec before LEVEL")
	P:SetAttribute("UyInZone", false)
	CE.Advance(0.6)
	eq(keys:GetAttribute("HUDValue"), 0, "no key pill outside")
	truthy(not line.Visible, "no objective line outside the Underyard and the Dead Yard")
	-- the Dead Yard: the way down once Chapter I is complete and the Underyard was never entered
	local _, fresh = load("locked")
	P:SetAttribute("HalloweenChapter1Complete", true)
	local cv2 = table.clone(fresh)
	cv2.Chapter1 = table.clone(fresh.Chapter1)
	cv2.Chapter1.Complete = true
	cv2.Entered = false
	Bus.Fire("C2Changed", { View = cv2 })
	P:SetAttribute("HwInZone", true)
	CE.Advance(0.6)
	truthy(line.Visible, "Dead Yard: descend line")
	eq(line.Line.Text, UV.T("Descend through the church in the Dead Yard", "en"))
	P:SetAttribute("HwInZone", false)
	load("mid")
	P:SetAttribute("UyInZone", true)
	CE.Advance(0.6)
	-- announcements: the Black Coffin's Hollow King belongs to the Secret arrival / CoffinFX (no second HUD banner);
	-- someone else's finale Hollow King -> a banner at once; with a menu open -> a toast
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "HollowKing", Name = "Mira", UserId = 99, Arrival = true } })
	CE.Advance(0.2)
	eq(#banners, 0, "coffin Hollow King: the arrival presents it")
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "HollowKing", Source = "Finale", Name = "Mira", UserId = 99 } })
	CE.Advance(0.2)
	eq(#banners, 1, "Hollow King banner")
	eq(banners[1].Style, "Underyard")
	truthy(string.find(banners[1].Subtitle, "Mira", 1, true), "who found it")
	truthy(string.find(banners[1].Subtitle, "Gravekeeper", 1, true), "says where it came from")
	gui:SetAttribute("OpenMenu", "Underyard")
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "Assault", Name = "", UserId = 0 } })
	CE.Advance(0.2)
	eq(#banners, 1, "no banner over a menu")
	truthy(#toasts >= 1, "toast instead")
	gui:SetAttribute("OpenMenu", nil)
	-- my own Hollow King waits for its show
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "HollowKing", Source = "Doors", Name = P.DisplayName, UserId = P.UserId } })
	CE.Advance(2)
	eq(#banners, 1, "own Hollow King held back")
	CE.Advance(8)
	eq(#banners, 2, "own Hollow King after the reveal")
	-- Mythic names the find, FinaleClear the party
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "Mythic", Name = "Ivo", UserId = 5, DogId = "HW_BellkeeperWolf" } })
	CE.Advance(0.2)
	truthy(string.find(banners[3].Subtitle, "Bellkeeper Wolf", 1, true), "mythic dog named: " .. banners[3].Subtitle)
	Lang.Override = "ru"
	Bus.Fire("C2Signal", { Kind = "C2Announce", Data = { Kind = "FinaleClear", Name = "Ivo", UserId = 5 } })
	CE.Advance(0.2)
	truthy(cyrillic(banners[4].Title) and cyrillic(banners[4].Subtitle), "Russian banner")
	Lang.Override = "en"
	-- shards / keys fly into their pills, then the icons are gone
	local shardsPill = Kit.New("Frame", { Name = "QuickShards", Size = roblox.UDim2.fromOffset(138, 46), Position = roblox.UDim2.fromOffset(600, 10) }, hudFrame)
	FakeU.ChapterPills.Shards = shardsPill
	local before = popped
	Bus.Fire("C2Signal", { Kind = "C2Shards", Data = { Amount = 120, Source = "Contract" } })
	CE.Advance(0.1)
	local flying = 0
	for _, c in ipairs(flyLayer:GetChildren()) do
		if c.Name == "UyShard" then
			flying += 1
		end
	end
	truthy(flying >= 1, "shards in flight")
	CE.Advance(2)
	truthy(popped > before, "the pill popped")
	for _, c in ipairs(flyLayer:GetChildren()) do
		truthy(c.Name ~= "UyShard", "flight cleaned up")
	end
	Bus.Fire("C2Signal", { Kind = "C2Key", Data = { Amount = 1, Source = "Contract" } })
	CE.Advance(2)
	-- the tile: built art + a badge with the things to claim
	CE.Advance(2.5)
	truthy(tileIcon:FindFirstChild("UyTileArt"), "tile art")
	local lastBadge = nil
	for _, b in ipairs(tileBadges) do
		if b.Key == "Underyard" then
			lastBadge = b
		end
	end
	truthy(lastBadge and tonumber(lastBadge.Text) and tonumber(lastBadge.Text) > 0, "tile badge counts what is ready")
	Kit.Toast = hudToast
end)

if OUT then
	fs.writeDir(OUT)
	fs.writeFile(OUT .. "/underyard_dump.json", serde.encode("json", dumps))
	print("layouts: " .. #dumps .. " -> " .. OUT)
end
for _, w in ipairs(CE.Warnings) do
	-- the kit's generic dog preview needs the place's UITheme (MainWindow templates), absent in this fake client
	if not string.find(w, "^Kit%.Preview: .-UITheme") then
		print("warn: " .. w)
	end
end
print(string.format("underyard_ui: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
