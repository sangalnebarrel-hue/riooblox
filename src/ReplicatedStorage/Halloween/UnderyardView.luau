-- Presentation rules of CHAPTER II · THE UNDERYARD (ReplicatedStorage.Halloween.UnderyardView, WP-L). Pure: no services,
-- no instances; the Underyard window (Modules.UnderyardScreen), the HALLOWEEN window, the DogDex and the HUD read the
-- same answers from here, and tests/underyard_ui.luau checks them directly.
--   Text        UV.T(en, lang) / UV.F(en, lang, ...) / UV.L(pair, lang)   (Localization.UnderyardUI, then .Underyard)
--   Seals       UV.SealState(view, i, now, ctx) -> state · UV.CurrentSeal(view) · UV.StartAnchor(i) · UV.GoldText(i, lang)
--               UV.FirstRewards(i) -> reward rows · UV.Numeral(i)
--   Objective   UV.Objective(view, now, ctx) -> o · UV.ObjectiveText(o, lang, now) -> title, line
--   Badges      UV.Badges(view, hview, now, ctx) -> {seals, contracts, coffin, dex, collection, journal, Total}
--   Coffin      UV.DropTable() -> {Groups, Total} (exact % from Chapter2Rules.CoffinChance) · UV.Percent(p) · UV.Odds(p)
--   Names       UV.RowName(row, lang) · UV.RowAmount(row) · UV.ContractText(row, lang) · UV.DogSources(id)
--   Journal     UV.JournalReplays(key) -> {{Id, Bus, Data, Label}} · UV.JournalHint(key, lang)
--   Collection  UV.Collection(view, hview) -> {Skins, Decor, Finds}
-- view = the Chapter II view (Features.Underyard.View: Halloween view .Chapter2), hview = the Halloween view (Skins).
-- ctx = {Eligible, InZone, InTrial, Shards, Keys, Near = fn(anchorName) -> bool}
local root = script.Parent
local Cfg = require(root:WaitForChild("Chapter2Config"))
local Rules = require(root:WaitForChild("Chapter2Rules"))

local UV = {}
UV.Config = Cfg
UV.Rules = Rules

local function tbl(t: any): { [any]: any }
	return type(t) == "table" and t or {}
end
local function num(v: any): number
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

---------------------------------------------------------------------------------------------------------------------
-- Text: Localization.UnderyardUI (this package) first, then Localization.Underyard (WP-A's shared labels)
---------------------------------------------------------------------------------------------------------------------
local dicts: any = nil
local function loc(): any
	if dicts then
		return dicts
	end
	local out = { Own = { UI = {}, Templates = {}, Exact = {} }, Base = { UI = {}, Templates = {}, Exact = {} } }
	local ok = pcall(function()
		local folder = root.Parent and root.Parent:FindFirstChild("Localization")
		local own = folder and folder:FindFirstChild("UnderyardUI")
		local base = folder and folder:FindFirstChild("Underyard")
		if own then
			out.Own = require(own) :: any
		end
		if base then
			out.Base = require(base) :: any
		end
	end)
	if not ok then
		warn("UnderyardView: localization unavailable")
	end
	dicts = out
	return out
end
UV.Dicts = loc

local function plural(n: number, one: string, few: string, many: string): string
	n = math.abs(math.floor(n))
	local n10, n100 = n % 10, n % 100
	if n10 == 1 and n100 ~= 11 then
		return one
	end
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14) then
		return few
	end
	return many
end
UV.Plural = plural

function UV.T(en: string, lang: string?): string
	if lang ~= "ru" or type(en) ~= "string" then
		return en
	end
	local d = loc()
	return d.Own.UI[en] or d.Base.UI[en] or d.Own.Exact[en] or d.Base.Exact[en] or en
end

-- string.format of a localized template; a Russian template may be {one, few, many} (by the first number argument)
function UV.F(en: string, lang: string?, ...: any): string
	local fmt: any = en
	if lang == "ru" then
		local d = loc()
		fmt = d.Own.Templates[en] or d.Base.Templates[en] or en
	end
	if type(fmt) == "table" then
		local n = 0
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "number" then
				n = v
				break
			end
		end
		fmt = plural(n, fmt[1], fmt[2], fmt[3])
	end
	local ok, out = pcall(string.format, fmt, ...)
	return ok and out or en
end

-- a config pair {en, ru}
function UV.L(pair: any, lang: string?): string
	if type(pair) == "table" then
		return (lang == "ru" and pair[2]) or pair[1] or ""
	end
	return tostring(pair or "")
end

-- server English -> Russian (UnderyardUI.Exact, Underyard Exact / UI / Patterns), else nil
function UV.Said(text: any, lang: string?): string?
	if lang ~= "ru" or type(text) ~= "string" or text == "" then
		return nil
	end
	local d = loc()
	local own = d.Own.Exact[text] or d.Own.UI[text]
	if own then
		return own
	end
	if type(d.Base.Translate) == "function" then
		local ok, out = pcall(d.Base.Translate, text, "ru")
		if ok and type(out) == "string" then
			return out
		end
	end
	return nil
end

-- Cyrillic-safe upper case
function UV.Upper(text: string): string
	return (string.gsub(string.upper(text), utf8.charpattern, function(ch)
		local c = utf8.codepoint(ch)
		if c >= 0x430 and c <= 0x44F then
			return utf8.char(c - 0x20)
		elseif c == 0x451 then
			return utf8.char(0x401)
		end
		return ch
	end))
end

function UV.Clock(seconds: number, lang: string?): string
	local n = math.max(0, math.floor(num(seconds)))
	local d, h, m, s = n // 86400, (n // 3600) % 24, (n // 60) % 60, n % 60
	if d > 0 then
		return d .. (lang == "ru" and "д" or "d") .. " " .. string.format("%02d:%02d:%02d", h, m, s)
	elseif h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

---------------------------------------------------------------------------------------------------------------------
-- Seals
---------------------------------------------------------------------------------------------------------------------
function UV.Numeral(i: number): string
	local seal = Cfg.Seals[i]
	return seal and seal.Numeral or tostring(i)
end

-- where the trial of seal i starts (Seals.luau default: its altar; activities with their own start point)
function UV.StartAnchor(i: number): string
	local seal = Cfg.Seals[i]
	local a = seal and seal.Activity and seal.Activity.StartAnchor
	if type(a) == "string" then
		return a
	end
	if i == 5 then
		return "DoorCourt" -- Seal V: the Crooked Doors open from their own prompts
	end
	return "SealAltar_" .. i
end

-- the onboarding step that pays an offering right now (Tutorial.Steps[].RefundSeal), or nil
local function coveredSeal(view: any): number?
	local t = tbl(tbl(view).Tutorial)
	if t.Done == true then
		return nil
	end
	local step = Rules.TutorialStep(num(t.Current or t.Step), Cfg)
	return step and step.RefundSeal or nil
end

-- the first seal not cleared yet (nil = all seven broken)
function UV.CurrentSeal(view: any): number?
	local seals = tbl(tbl(view).Seals)
	for i = 1, #Cfg.Seals do
		if not tbl(seals[i]).Cleared then
			return i
		end
	end
	return nil
end

-- State: "Waiting" (date) | "Previous" (seal i-1 not cleared) | "Offer" | "Trial" (offered, not cleared) | "Cleared" | "Gold"
-- Action: "Locked" | "Opens" | "Previous" | "InTrial" | "Descend" | "Need" | "Offer" | "WayOffer" | "Begin" | "Again" |
--         "WayTrial" | "Doors"
function UV.SealState(view: any, i: number, now: number, ctx: any?): any
	local c = tbl(ctx)
	local def = Cfg.Seals[i]
	local row = tbl(tbl(tbl(view).Seals)[i])
	local s: any = { Index = i, Def = def, Row = row }
	local opensAt = row.OpensAt or Rules.SealOpensAt(i, Cfg)
	-- the date gate is pure: a view drawn before the opening moment still opens on time
	local open = row.Open == true or num(now) >= opensAt
	s.Open, s.OpensAt, s.OpensIn = open, opensAt, math.max(0, opensAt - num(now))
	local cost, discounted = Rules.OfferingCost(i, num(now), Cfg)
	if row.Cost ~= nil and num(row.Cost) < cost then
		cost, discounted = num(row.Cost), row.Discount == true
	end
	s.Cost, s.Discount, s.Full = cost, discounted, def.Offering
	s.Covered = coveredSeal(view) == i
	local seals = tbl(tbl(view).Seals)
	s.Previous = i == 1 or tbl(seals[i - 1]).Cleared == true
	s.Offered, s.Cleared, s.Gold = row.Offered == true, row.Cleared == true, row.Gold == true
	local shards = num(c.Shards)
	s.CanAfford = s.Covered or shards >= cost
	s.Missing = math.max(0, cost - shards)
	if s.Cleared then
		s.State = s.Gold and "Gold" or "Cleared"
	elseif not open then
		s.State = "Waiting"
	elseif not s.Previous then
		s.State = "Previous"
	elseif not s.Offered then
		s.State = "Offer"
	else
		s.State = "Trial"
	end
	s.Anchor = s.State == "Offer" and ("SealAltar_" .. i) or UV.StartAnchor(i)
	local near = type(c.Near) == "function" and c.Near or function()
		return false
	end
	if c.Eligible == false then
		s.Action = "Locked"
	elseif s.State == "Waiting" then
		s.Action = "Opens"
	elseif s.State == "Previous" then
		s.Action = "Previous"
	elseif c.InTrial then
		s.Action = "InTrial"
	elseif not c.InZone then
		s.Action = "Descend"
	elseif s.State == "Offer" then
		if not s.CanAfford then
			s.Action = "Need"
		elseif near(s.Anchor) then
			s.Action = "Offer"
		else
			s.Action = "WayOffer"
		end
	elseif i == 5 then
		s.Action = "Doors"
	elseif near(s.Anchor) then
		s.Action = s.State == "Trial" and "Begin" or "Again"
	else
		s.Action = "WayTrial"
	end
	return s
end

-- first-clear rewards of seal i as reward rows (chips): First shards, the key, dogs / plot cosmetics
function UV.FirstRewards(i: number): { any }
	local def = Cfg.Seals[i]
	if not def then
		return {}
	end
	local out = { { Kind = "Shards", Amount = def.Rewards.First } }
	if num(def.Rewards.Keys) > 0 then
		table.insert(out, { Kind = "Key", Amount = def.Rewards.Keys })
	end
	for _, row in ipairs(def.Rewards.Rows or {}) do
		table.insert(out, table.clone(row))
	end
	return out
end

-- the Gold target of seal i as one line
function UV.GoldText(i: number, lang: string?): string
	local def = Cfg.Seals[i]
	local g = def and def.Gold or {}
	local parts = {}
	if g.Total then
		table.insert(parts, UV.F("%d objectives", lang, g.Total))
	end
	if g.PerfectShare then
		table.insert(parts, UV.F("%d%% Perfect", lang, math.floor(g.PerfectShare * 100 + .5)))
	end
	if g.Time then
		table.insert(parts, UV.F("within %s", lang, UV.Clock(g.Time, lang)))
	end
	if g.NoMistakes then
		table.insert(parts, UV.T("no wrong answers", lang))
	end
	if g.NoDowns then
		table.insert(parts, UV.T("never downed", lang))
	end
	if g.NoBleedOut then
		table.insert(parts, UV.T("nobody bleeds out", lang))
	end
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------------------------------------------------------
-- Objective (HUD strip line / window header)
---------------------------------------------------------------------------------------------------------------------
-- Kind: "Chapter1" | "Tutorial" | "Descend" | "Wait" | "Offer" | "Need" | "Trial" | "Doors" | "Done"
function UV.Objective(view: any, now: number, ctx: any?): any
	local c = tbl(ctx)
	view = tbl(view)
	local c1 = tbl(view.Chapter1)
	if c.Eligible == false then
		return { Kind = "Chapter1", Done = num(c1.Done), Total = num(c1.Total) > 0 and num(c1.Total) or #Cfg.Chapter1.Checklist }
	end
	local t = tbl(view.Tutorial)
	local current = num(t.Current)
	if t.Done ~= true and current > 0 then
		local def = Rules.TutorialStep(current, Cfg)
		if def then
			return { Kind = "Tutorial", Step = current, Total = #Cfg.Tutorial.Steps, Def = def }
		end
	end
	if not c.InZone and view.Entered ~= true then
		return { Kind = "Descend", RevealSeen = view.RevealSeen == true }
	end
	local i = UV.CurrentSeal(view)
	if not i then
		return { Kind = "Done" }
	end
	local s = UV.SealState(view, i, now, c)
	local kind = "Trial"
	if s.State == "Waiting" then
		kind = "Wait"
	elseif s.State == "Offer" then
		kind = s.CanAfford and "Offer" or "Need"
	elseif i == 5 then
		kind = "Doors"
	end
	return { Kind = kind, Seal = i, State = s }
end

-- (title, line) of an objective
function UV.ObjectiveText(o: any, lang: string?, now: number?): (string, string)
	o = tbl(o)
	local kind = o.Kind
	if kind == "Chapter1" then
		return UV.T("CHAPTER II", lang), UV.F("Finish Chapter I: %d / %d", lang, num(o.Done), num(o.Total))
	elseif kind == "Tutorial" then
		local def = o.Def or {}
		return UV.F("GUIDE %d / %d", lang, num(o.Step), num(o.Total)), UV.L(def.Title, lang) .. " · " .. UV.L(def.Text, lang)
	elseif kind == "Descend" then
		return UV.T("CHAPTER II", lang), UV.T("Descend through the church in the Dead Yard", lang)
	elseif kind == "Done" then
		return UV.T("THE LAST BELL IS SILENT", lang), UV.T("Contracts, coffins and the Gravekeeper still wait below", lang)
	end
	local s = tbl(o.State)
	local i = num(o.Seal)
	local def = Cfg.Seals[i] or {}
	local title = UV.F("BELL SEAL %s", lang, UV.Numeral(i)) .. " · " .. UV.L(def.Name, lang)
	if kind == "Wait" then
		return title, UV.F("Opens in %s", lang, UV.Clock(math.max(0, num(s.OpensAt) - num(now)), lang))
	elseif kind == "Offer" then
		if s.Covered then
			return title, UV.F("Offer at Altar %s: the guide pays it", lang, UV.Numeral(i))
		end
		return title, UV.F("Offer %d Bell Shards at Altar %s", lang, num(s.Cost), UV.Numeral(i))
	elseif kind == "Need" then
		return title, UV.F("Earn %d more Bell Shards for the offering", lang, num(s.Missing))
	elseif kind == "Doors" then
		return title, UV.T("Open the Crooked Doors in Crooked Row", lang)
	end
	return title, UV.F("Begin the trial: %s", lang, UV.L(def.Title, lang))
end

---------------------------------------------------------------------------------------------------------------------
-- Badges (tabs, the rail tile)
---------------------------------------------------------------------------------------------------------------------
function UV.Badges(view: any, hview: any, now: number, ctx: any?): any
	view = tbl(view)
	local c = tbl(ctx)
	local out = { seals = 0, contracts = 0, coffin = 0, dex = 0, collection = 0, journal = 0, Total = 0 }
	if c.Eligible == false then
		return out
	end
	for i = 1, #Cfg.Seals do
		local s = UV.SealState(view, i, now, c)
		if (s.State == "Offer" and s.CanAfford) or s.State == "Trial" then
			out.seals += 1
		end
	end
	local contracts = tbl(view.Contracts)
	local today = Rules.Day(now)
	local current = contracts.Day == nil or num(contracts.Day) == today
	local all = #tbl(contracts.List) > 0
	for _, row in ipairs(tbl(contracts.List)) do
		if current and not row.Claimed and num(row.Progress) >= num(row.Goal) then
			out.contracts += 1
		end
		all = all and row.Claimed == true
	end
	if current and all and contracts.AllClaimed ~= true then
		out.contracts += 1
	end
	local price = Cfg.Coffin.Price
	if num(c.Keys ~= nil and c.Keys or view.Keys) >= price.Keys and num(c.Shards ~= nil and c.Shards or view.Shards) >= price.Shards then
		out.coffin = 1
	end
	out.dex = #tbl(tbl(view.Dex2).Claimable)
	local fragments = num(view.Fragments)
	local col = UV.Collection(view, hview)
	for _, item in ipairs(col.Decor) do
		if not item.Owned and fragments >= item.Cost then
			out.collection = 1
		end
	end
	for _, item in ipairs(col.Skins) do
		if not item.Owned and item.Cost and fragments >= item.Cost then
			out.collection = 1
		end
	end
	local read = tbl(view.JournalRead)
	for key in pairs(tbl(view.Journal)) do
		if not read[key] then
			out.journal += 1
		end
	end
	out.Total = out.seals + out.contracts + out.coffin + out.dex + out.journal
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- The Black Coffin: names and the drop-rate table
---------------------------------------------------------------------------------------------------------------------
local KIND_NAME = {
	Shards = { "Bell Shards", "Осколки колокола" }, Key = { "Coffin Key", "Ключ от гроба" }, Dust = { "Lucky Dust", "Счастливая пыль" },
	Fragments = { "Cosmetic Fragments", "Фрагменты косметики" }, Bones = { "Bones", "Кости" }, Cash = { "Coins", "Монеты" },
	Candy = { "Moon Candy", "Лунные конфеты" },
}
UV.KindName = KIND_NAME

-- {en, ru} name of a reward row / coffin row / Coffins.Last record
function UV.RowNamePair(row: any): { string }
	row = tbl(row)
	local kind, id = row.Kind, row.Id
	if kind == "Find" and Cfg.Finds.Defs[id] then
		return Cfg.Finds.Defs[id].Name
	elseif kind == "Decor" and Cfg.Decor.Defs[id] then
		return Cfg.Decor.Defs[id].Name
	elseif kind == "Skin" and Cfg.Skins.Defs[id] then
		return Cfg.Skins.Defs[id].Name
	elseif kind == "Dog" and Cfg.Dogs.Defs[id] then
		return Cfg.Dogs.Defs[id].Name
	elseif kind == "Title" and Cfg.Titles[id] then
		return Cfg.Titles[id]
	end
	return KIND_NAME[kind] or { tostring(id or kind or "?"), tostring(id or kind or "?") }
end

function UV.RowName(row: any, lang: string?): string
	return UV.L(UV.RowNamePair(row), lang)
end

-- the amount part of a coffin table row ("60-120", "30 min", "") / a granted row ("x3")
function UV.RowAmount(row: any): string
	row = tbl(row)
	if row.Min and row.Max then
		return tostring(row.Min) .. "–" .. tostring(row.Max)
	elseif row.Amount and num(row.Amount) > 1 then
		return tostring(math.floor(num(row.Amount)))
	end
	return ""
end

-- rarity name of a row (reveal colours, chips)
function UV.RowRarity(row: any): string
	row = tbl(row)
	local kind, id = row.Kind, row.Id
	if kind == "Find" then
		return (Cfg.Finds.Defs[id] and Cfg.Finds.Defs[id].Tier) or row.Tier or "Rare"
	elseif kind == "Decor" and Cfg.Decor.Defs[id] then
		return Cfg.Decor.Defs[id].Rarity
	elseif kind == "Skin" and Cfg.Skins.Defs[id] then
		return Cfg.Skins.Defs[id].Rarity
	elseif kind == "Dog" and Cfg.Dogs.Defs[id] then
		local names = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
		return names[math.clamp(Cfg.Dogs.Defs[id].Rank, 1, 6)]
	elseif kind == "Key" then
		return "Epic"
	elseif kind == "Title" then
		return "Legendary"
	elseif kind == "Fragments" or kind == "Cash" then
		return "Rare"
	end
	local rank = num(row.Rank)
	if rank >= 1 then
		local names = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
		return names[math.clamp(math.floor(rank), 1, 6)]
	end
	return "Common"
end

-- exact percentage text of a probability (0..1): the table sums to 100 000, so three decimals are exact
function UV.Percent(p: number): string
	local v = num(p) * 100
	local s = string.format("%.3f", v)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "0" and v > 0 then
		s = string.format("%.4f", v)
	end
	return s .. "%"
end

-- "1 in 25,000"
function UV.Odds(p: number): string
	p = num(p)
	if p <= 0 then
		return "—"
	end
	local n = math.floor(1 / p + .5)
	local digits = tostring(n)
	local grouped = string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")
	grouped = string.reverse(grouped)
	grouped = string.gsub(grouped, "^,", "")
	return grouped
end

local TIER_ORDER = { "Common", "Rare", "Epic", "Legendary" }
local TIER_NAME = {
	Common = { "COMMON", "ОБЫЧНЫЕ" }, Rare = { "RARE", "РЕДКИЕ" }, Epic = { "EPIC", "ЭПИЧЕСКИЕ" }, Legendary = { "LEGENDARY", "ЛЕГЕНДАРНЫЕ" },
}
UV.TierName = TIER_NAME

-- {Groups = {{Id, Name = {en, ru}, Chance, Weight, Rows = {{Key, Kind, Id, Name, Chance, Weight, Amount, Rarity}},
--  Tiers = {{Tier, Name, Chance, Rows}}? (showcase finds)}}, Total = 1}; groups in Chapter2Config.Coffin.Groups order
local dropCache: any = nil
function UV.DropTable(): any
	if dropCache then
		return dropCache
	end
	local groups, byId = {}, {}
	for _, g in ipairs(Cfg.Coffin.Groups) do
		local entry = { Id = g.Id, Name = g.Name, Chance = 0, Weight = 0, Rows = {} }
		table.insert(groups, entry)
		byId[g.Id] = entry
	end
	local total = 0
	for _, row in ipairs(Cfg.Coffin.Table) do
		local g = byId[row.Group]
		if not g then
			g = { Id = row.Group, Name = { row.Group, row.Group }, Chance = 0, Weight = 0, Rows = {} }
			table.insert(groups, g)
			byId[row.Group] = g
		end
		local chance = Rules.CoffinChance(row, Cfg)
		g.Chance += chance
		g.Weight += num(row.Weight)
		total += chance
		table.insert(g.Rows, { Key = row.Key, Kind = row.Kind, Id = row.Id, Name = UV.RowNamePair(row), Chance = chance, Weight = num(row.Weight),
			Amount = UV.RowAmount(row), Rarity = UV.RowRarity(row), Tier = row.Tier, Coins = row.Coins })
	end
	local find = byId.Find
	if find then
		local tiers = {}
		for _, tier in ipairs(TIER_ORDER) do
			local t = { Tier = tier, Name = TIER_NAME[tier], Chance = 0, Rows = {} }
			for _, r in ipairs(find.Rows) do
				if r.Tier == tier then
					t.Chance += r.Chance
					table.insert(t.Rows, r)
				end
			end
			if #t.Rows > 0 then
				table.insert(tiers, t)
			end
		end
		find.Tiers = tiers
	end
	dropCache = { Groups = groups, Total = total }
	return dropCache
end

---------------------------------------------------------------------------------------------------------------------
-- Contracts
---------------------------------------------------------------------------------------------------------------------
function UV.ContractText(row: any, lang: string?): string
	row = tbl(row)
	local def = Rules.ContractDef(row.Id, Cfg)
	local en = def and def.Text and def.Text[1] or tostring(row.Id or "?")
	if string.find(en, "%%d") then
		return UV.F(en, lang, math.floor(num(row.Goal ~= nil and row.Goal or (def and def.Goal))))
	end
	-- the contract texts live in Localization.Underyard.Templates, with or without a number
	local d = loc()
	local ru = lang == "ru" and (d.Own.Templates[en] or d.Base.Templates[en]) or nil
	if type(ru) == "string" then
		return ru
	end
	return UV.T(en, lang)
end

---------------------------------------------------------------------------------------------------------------------
-- Dex II
---------------------------------------------------------------------------------------------------------------------
-- where an Underyard dog comes from: {en, ru} pairs
function UV.DogSources(id: string): { any }
	local out = {}
	for i, seal in ipairs(Cfg.Seals) do
		for _, row in ipairs(seal.Rewards.Rows or {}) do
			if row.Kind == "Dog" and row.Id == id then
				table.insert(out, { "Bell Seal " .. seal.Numeral .. " (first clear)", "Печать колокола " .. seal.Numeral .. " (первое прохождение)" })
			end
		end
		local _ = i
	end
	if num(Cfg.Dogs.CoffinWeight[id]) > 0 then
		table.insert(out, { "The Black Coffin", "Чёрный гроб" })
	end
	for _, d in ipairs(Cfg.Finale.Rewards.First.Dogs) do
		if d.Id == id then
			table.insert(out, { "The Gravekeeper's last stand (V)", "Последний бой Смотрителя (V)" })
			break
		end
	end
	if id == "HW_HollowKing" and num(Cfg.Doors.Rare.HollowKingChance) > 0 then
		table.insert(out, { "The hidden room behind a Crooked Door", "Тайная комната за кривой дверью" })
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Collection (skins / plot cosmetics / showcase finds), owned vs missing
---------------------------------------------------------------------------------------------------------------------
function UV.Collection(view: any, hview: any): any
	view = tbl(view)
	local owned = tbl(view.Owned)
	local skins = tbl(tbl(hview).Skins)
	local out = { Skins = {}, Decor = {}, Finds = {} }
	for _, id in ipairs(Cfg.Skins.Order) do
		local def = Cfg.Skins.Defs[id]
		local cost = Rules.CraftCost(id, Cfg)
		table.insert(out.Skins, { Kind = "Skin", Id = id, Name = def.Name, Rarity = def.Rarity, Owned = skins[id] == true, DexOnly = def.DexOnly == true,
			Cost = cost })
	end
	for _, id in ipairs(Cfg.Decor.Order) do
		local def = Cfg.Decor.Defs[id]
		table.insert(out.Decor, { Kind = "Decor", Id = id, Name = def.Name, Rarity = def.Rarity, Size = def.Size,
			Owned = tbl(owned.Decor)[id] == true, Cost = Cfg.Craft.Decor })
	end
	for _, id in ipairs(Cfg.Finds.Order) do
		local def = Cfg.Finds.Defs[id]
		table.insert(out.Finds, { Kind = "Find", Id = id, Name = def.Name, Rarity = def.Tier, Tier = def.Tier, Owned = tbl(owned.Finds)[id] == true })
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Journal (§9.6): replays per entry (Bus events only; replays never grant or set flags, DESIGN §24.3)
---------------------------------------------------------------------------------------------------------------------
local REPLAYS = {
	chapter1 = {
		{ Id = "Guide", Bus = "Onboarding", Data = { Replay = true }, Label = { "CHAPTER I GUIDE", "ГИД ГЛАВЫ I" } },
		{ Id = "Brew", Bus = "CauldronClaimLocal", Label = { "THE BREW FINALE", "ФИНАЛ ВАРЕВА" } },
	},
	reveal = {
		{ Id = "Reveal", Bus = "C2Replay", Data = { Id = "Reveal" }, Label = { "IS THAT ALL?", "И ЭТО ВСЁ?" } },
		{ Id = "Church", Bus = "C2Replay", Data = { Id = "Church" }, Label = { "THE CHURCH", "ЦЕРКОВЬ" } },
	},
	descend = { { Id = "Portal", Bus = "C2Replay", Data = { Id = "Portal" }, Label = { "THE DESCENT", "СПУСК" } } },
	finale = { { Id = "Finale", Bus = "C2Replay", Data = { Id = "Finale" }, Label = { "THE FALSE VICTORY", "ЛОЖНАЯ ПОБЕДА" } } },
}
for i = 1, #Cfg.Seals do
	REPLAYS["seal" .. i] = { { Id = "Seal", Bus = "C2Replay", Data = { Id = "Seal", Seal = i }, Label = { "THE SEAL BREAKS", "ПЕЧАТЬ ЛОМАЕТСЯ" } } }
end
UV.Replays = REPLAYS

function UV.JournalReplays(key: string): { any }
	return REPLAYS[key] or {}
end

local HINTS = {
	chapter1 = { "Finish Chapter I in the Dead Yard", "Заверши главу I на Мёртвом дворе" },
	reveal = { "Something under the church is waiting for you", "Под церковью тебя что-то ждёт" },
	descend = { "Descend through the portal in the church", "Спустись через портал в церкви" },
	finale = { "Survive the Gravekeeper's last stand on difficulty V", "Переживи последний бой Смотрителя на сложности V" },
	assault = { "Bring down the Black Bell in a Black Bell Assault", "Обрушь Чёрный колокол во время штурма" },
}
function UV.JournalHint(key: string, lang: string?): string
	local seal = tonumber(string.match(key, "^seal(%d)$"))
	if seal then
		return UV.F("Break Bell Seal %s", lang, UV.Numeral(seal))
	end
	return UV.L(HINTS[key] or { "Keep exploring the Underyard", "Исследуй Поддворье дальше" }, lang)
end

return UV
