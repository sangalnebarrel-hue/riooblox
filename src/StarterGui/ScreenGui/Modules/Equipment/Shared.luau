-- Client helpers shared by the EQUIPMENT screens (EquipmentScreen, ArtifactPanel, CaseOpening):
-- self-localized words (Kit.T), stat and scope texts, card data for Kit grids, the "Equipment"
-- preview kind (3D looks built from parts, EquipmentVisuals), server requests with toasts, the
-- odds dialog and the piece details dialog.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")

local Modules = script.Parent.Parent
local Kit = require(Modules.Kit)
local Base = require(Modules.Kit.Base)
local Net = require(Modules.Net)
local E = require(RS.DogEconomy.EquipmentDefinitions)
local Visuals = require(RS.DogEconomy.EquipmentVisuals)
local DogDefinitions = require(RS.DogEconomy.DogDefinitions)

local S = { E = E, Visuals = Visuals, Kit = Kit, Net = Net, Dogs = DogDefinitions }

-- Two clearly different families: accessories boost YOU (sky blue), artifacts boost ONE DOG (amber).
S.Colors = {
	Accessory = Color3.fromRGB(32, 168, 236),
	Artifact = Color3.fromRGB(240, 132, 32),
}

local T = Kit.T
S.T = T

S.Words = {
	SHOP = { "EQUIPMENT SHOP", "МАГАЗИН ЭКИПИРОВКИ" },
	ACCESSORIES = { "PLAYER ACCESSORIES", "АКСЕССУАРЫ ИГРОКА" },
	ARTIFACTS = { "DOG ARTIFACTS", "АРТЕФАКТЫ СОБАК" },
	CASES = { "CASES", "КЕЙСЫ" },
	BAG = { "MY BAG", "МОЯ СУМКА" },
	OPEN = { "OPEN", "ОТКРЫТЬ" },
	ODDS = { "ODDS", "ШАНСЫ" },
	CLOSE = { "CLOSE", "ЗАКРЫТЬ" },
	WEAR = { "WEAR", "НАДЕТЬ" },
	TAKE_OFF = { "TAKE OFF", "СНЯТЬ" },
	EQUIP_DOG = { "EQUIP ON A DOG", "НАДЕТЬ НА СОБАКУ" },
	LOCK = { "LOCK", "ЗАЩИТИТЬ" },
	UNLOCK = { "UNLOCK", "СНЯТЬ ЗАЩИТУ" },
	SALVAGE = { "SALVAGE", "РАЗОБРАТЬ" },
	SELECT = { "SELECT", "ВЫБРАТЬ" },
	CANCEL = { "CANCEL", "ОТМЕНА" },
	ALL = { "ALL", "ВСЕ" },
	WORN = { "WORN", "НАДЕТО" },
	ON_DOG = { "ON A DOG", "НА СОБАКЕ" },
	LOCKED = { "LOCKED", "ЗАЩИЩЕНО" },
	NEW = { "NEW", "НОВОЕ" },
	QUALITY = { "QUALITY", "КАЧЕСТВО" },
	EMPTY = { "EMPTY", "ПУСТО" },
	SORT_RARITY = { "RARITY", "РЕДКОСТЬ" },
	SORT_VALUE = { "BONUS", "БОНУС" },
	SORT_NEW = { "NEWEST", "НОВЫЕ" },
	KEYS = { "KEYS", "КЛЮЧИ" },
	BUY_KEY = { "BUY KEY", "КУПИТЬ КЛЮЧ" },
	BAG_FULL = { "BAG FULL", "СУМКА ПОЛНА" },
	ADD = { "ADD ARTIFACT", "ДОБАВИТЬ" },
	SWAP = { "SWAP", "ЗАМЕНИТЬ" },
	REMOVE = { "REMOVE", "СНЯТЬ" },
	PLACE = { "PLACE HERE", "ПОСТАВИТЬ СЮДА" },
	REPLACE_HERE = { "REPLACE", "ЗАМЕНИТЬ" },
	GO_SHOP = { "GET ARTIFACTS", "ПОЛУЧИТЬ АРТЕФАКТЫ" },
	PITY = { "GUARANTEED!", "ГАРАНТИЯ!" },
	COLLECT = { "COLLECT", "ЗАБРАТЬ" },
	AGAIN = { "OPEN AGAIN", "ЕЩЁ РАЗ" },
	SKIP = { "SKIP", "ПРОПУСТИТЬ" },
}
function S.W(key: string): string
	local pair = S.Words[key]
	if not pair then
		return key
	end
	return T(pair[1], pair[2])
end

-- Rarity words (upper case) in the player's language.
S.RarityUpper = {
	Common = { "COMMON", "ОБЫЧНЫЙ" },
	Uncommon = { "UNCOMMON", "НЕОБЫЧНЫЙ" },
	Rare = { "RARE", "РЕДКИЙ" },
	Epic = { "EPIC", "ЭПИЧЕСКИЙ" },
	Legendary = { "LEGENDARY", "ЛЕГЕНДАРНЫЙ" },
	Mythic = { "MYTHIC", "МИФИЧЕСКИЙ" },
	Secret = { "SECRET", "СЕКРЕТНЫЙ" },
}
function S.Rarity(rarity: string?): string
	local pair = S.RarityUpper[rarity or "Common"]
	return pair and T(pair[1], pair[2]) or string.upper(tostring(rarity))
end
function S.RarityColor(rarity: string?): Color3
	return Kit.Theme.RarityColor(rarity)
end

function S.Name(def: any): string
	if not def then
		return T("Unknown piece", "Неизвестный предмет")
	end
	return T(def.Name, def.Ru)
end
function S.CaseName(case: any): string
	return T(case.Name, case.Ru)
end
function S.StatName(stat: string): string
	local info = E.Stats[stat]
	if not info then
		return stat
	end
	return T(info.Name, info.Ru)
end
function S.StatColor(stat: string): Color3
	local info = E.Stats[stat]
	local c = info and info.Color or { 83, 112, 150 }
	return Color3.fromRGB(c[1], c[2], c[3])
end
-- "+3.5% LUCK"
function S.StatLine(stat: string, value: number): string
	return E.Format(value) .. " " .. S.StatName(stat)
end
-- Short form for cards and reel tiles: "+16.1% MUTATION".
function S.StatShort(stat: string): string
	local info = E.Stats[stat]
	if not info then
		return stat
	end
	return T(info.Short or info.Name, info.ShortRu or info.Ru)
end
function S.StatChip(stat: string, value: number): string
	return string.format("+%.1f%%", (tonumber(value) or 0) * 100) .. " " .. S.StatShort(stat)
end
-- What the stat does for this kind of piece (tooltip / details).
function S.Help(stat: string, kind: string): string
	local help = E.StatHelp[stat]
	local pair = help and (kind == "Artifact" and help.Dog or help.You)
	return pair and T(pair[1], pair[2]) or ""
end
-- Who the piece helps: the line that keeps the two families apart.
function S.Scope(kind: string): string
	if kind == "Artifact" then
		return T("BOOSTS ONE DOG", "УСИЛИВАЕТ ОДНУ СОБАКУ")
	end
	return T("BOOSTS YOU · ALL DOGS", "УСИЛИВАЕТ ТЕБЯ · ВСЕХ СОБАК")
end
-- At most n characters (UTF-8 aware), with an ellipsis when cut.
function S.Clip(text: string, n: number): string
	local length = utf8.len(text)
	if not length or length <= n then
		return text
	end
	local cut = utf8.offset(text, n)
	if not cut then
		return text
	end
	return string.sub(text, 1, cut - 1) .. "…"
end
function S.SlotName(slot: string): string
	local info = E.SlotInfo[slot]
	return info and T(info.Name, info.Ru) or slot
end
function S.Quality(roll: number): string
	return T("QUALITY ", "КАЧЕСТВО ") .. E.Quality(roll) .. "%"
end

-- Slots needed rarity text for a locked artifact slot (slot 2 -> "RARE+").
function S.SlotUnlock(slot: number): string
	for rank, n in ipairs(E.DogSlotsByRank) do
		if n >= slot then
			local rarity = E.DogRarities[rank]
			if rank == #E.DogSlotsByRank then
				return S.Rarity(rarity)
			end
			return S.Rarity(rarity) .. "+"
		end
	end
	return "—"
end

-- snapshot.Features.Equipment (nil while the server has none).
function S.Data(snapshot: any): any
	local features = type(snapshot) == "table" and snapshot.Features
	return type(features) == "table" and features.Equipment or nil
end
-- One piece by uid from the snapshot lists.
function S.Find(data: any, uid: string): any
	if not data or not uid then
		return nil
	end
	for _, list in ipairs({ data.Artifacts or {}, data.Accessories or {} }) do
		for _, entry in ipairs(list) do
			if entry.Uid == uid then
				return entry
			end
		end
	end
	return nil
end
function S.Dog(snapshot: any, dogUid: string?): any
	local profile = type(snapshot) == "table" and snapshot.Profile
	local dogs = type(profile) == "table" and profile.Dogs
	return dogUid and type(dogs) == "table" and dogs[dogUid] or nil
end
function S.DogSlots(dog: any): number
	if not dog then
		return 0
	end
	return E.DogSlots(DogDefinitions[dog.DogId] or dog)
end
function S.DogName(dog: any): string
	if not dog then
		return T("a dog", "собака")
	end
	local def = DogDefinitions[dog.DogId]
	return tostring(dog.DisplayName or (def and def.DisplayName) or dog.DogId)
end

-- Kit card data for one owned piece: rarity tag (+ a lock pill), one stat chip, a corner badge
-- for the state (worn / on a dog / new). Short texts so 146 px cards never overflow.
-- opts: Selecting, Selected, New.
function S.Card(entry: any, opts: any?): any
	local o = opts or {}
	local def = E.Def(entry.Id)
	local stat = def and def.Stat or entry.Stat
	local data: any = {
		Id = entry.Uid,
		Name = S.Name(def),
		Rarity = entry.Rarity,
		Preview = { Kind = "Equipment", Id = entry.Id },
		Stats = stat and { { Text = S.StatChip(stat, entry.Value or E.Value(entry)), Color = S.StatColor(stat) } } or {},
		Subtitle = S.Scope(def and def.Kind or "Accessory"),
	}
	if entry.Locked then
		data.Tag, data.TagColor = "🔒", Kit.Theme.Colors.gold
	end
	if entry.DogUid then
		data.Badge, data.BadgeColor = "🐾 " .. S.W("ON_DOG"), S.Colors.Artifact
	elseif entry.Slot then
		data.Badge, data.BadgeColor = S.W("WORN"), S.Colors.Accessory
	elseif o.New and o.New[entry.Uid] then
		data.Badge, data.BadgeColor = S.W("NEW"), Kit.Theme.Danger
	end
	if o.Selecting then
		data.Selected = o.Selected and o.Selected[entry.Uid] == true or false
		if entry.Locked then
			data.Disabled = true
			data.DisabledReason = T("Locked pieces cannot be salvaged. Unlock it first.", "Защищённые предметы нельзя разобрать. Сначала сними защиту.")
		elseif entry.DogUid or entry.Slot then
			data.Disabled = true
			data.DisabledReason = T("Take it off before salvaging it.", "Сначала сними его, потом разбирай.")
		end
	end
	return data
end

-- The "Equipment" preview kind: {Kind="Equipment", Id=pieceId} or {Kind="Equipment", Case=caseId}.
local registered = false
function S.RegisterPreview()
	if registered then
		return
	end
	registered = true
	Kit.Preview.Register("Equipment", function(spec, parent)
		if spec.Case then
			return Visuals.Viewport(parent, { Case = spec.Case })
		end
		return Visuals.Viewport(parent, { Id = spec.Id })
	end, function(spec)
		return spec.Case and ("case:" .. tostring(spec.Case)) or tostring(spec.Id)
	end)
end
S.RegisterPreview()

-- A preview in any frame (cached by Kit.Preview).
function S.Preview(holder: GuiObject, spec: any): any
	local slot = Kit.Preview.Slot(holder)
	slot:Show(spec)
	return slot
end

-- A server request with feedback: busy button, toast with the server's message.
-- Returns ok, result. opts: Button (Kit button), Quiet (no success toast), Success (text).
function S.Request(action: string, args: any, opts: any?): (boolean, any)
	local o = opts or {}
	if o.Button then
		o.Button:SetBusy(true)
	end
	local ok, result = Net.Request(action, args)
	if o.Button then
		o.Button:SetBusy(false)
	end
	local message = type(result) == "table" and result.Message or result
	if not ok then
		Kit.Toast(tostring(message or T("Something went wrong; try again", "Что-то пошло не так, попробуй ещё раз")), { Kind = "error" })
	elseif not o.Quiet then
		Kit.Toast(o.Success or tostring(message), { Kind = "success", NoTranslate = o.Success ~= nil })
	end
	return ok, result
end

-- Robux price of a developer product (Roblox's own number), cached; falls back to the config note.
local prices: { [number]: number } = {}
local loading: { [number]: boolean } = {}
function S.RobuxPrice(product: any, onReady: (() -> ())?): string
	local id = product.ProductId
	if prices[id] then
		return "R$ " .. prices[id]
	end
	if not loading[id] then
		loading[id] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return Marketplace:GetProductInfoAsync(id, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[id] = info.PriceInRobux
				if onReady then
					onReady()
				end
			else
				task.delay(10, function()
					loading[id] = nil
				end)
			end
		end)
	end
	return product.Robux and ("R$ " .. product.Robux) or "R$"
end
function S.PromptRobux(product: any)
	local ok, err = pcall(function()
		Marketplace:PromptProductPurchase(Players.LocalPlayer, product.ProductId)
	end)
	if not ok then
		warn("[DOGROTS equipment] purchase prompt failed:", err)
		Kit.Toast(T("Purchase unavailable. Please try again.", "Покупка недоступна. Попробуй ещё раз."), { Kind = "error", NoTranslate = true })
	end
end

-- Odds table of a case (shown before any purchase). caseRow: a snapshot Cases row.
-- opts.Buy = text of a confirm button (the dialog then resolves true only when it is pressed).
function S.ShowOdds(caseRow: any, opts: any?): any
	local o = opts or {}
	local case = E.CaseById[caseRow.Id]
	if not case then
		return nil
	end
	local pool = E.Pool(case)
	local rows = caseRow.Odds or E.Odds(case)
	local lines = {}
	for i = #rows, 1, -1 do
		table.insert(lines, rows[i])
	end
	local _, _, _, sh = Base.SafeArea(Kit.Overlay.Modals())
	local rowH = 50
	local wanted = #lines * (rowH + 6) + 44
	-- Title, a two-line body, buttons and paddings take about 204 px of the dialog.
	local height = math.max(96, math.min(wanted, sh - 24 - 204))
	return Kit.Modal({
		Title = T("ODDS · ", "ШАНСЫ · ") .. S.CaseName(case),
		Body = T("Every open gives exactly one piece. Its quality (0–100%) is rolled too: higher quality, bigger bonus.",
			"Каждое открытие даёт ровно один предмет. Его качество (0–100%) тоже случайно: чем выше, тем больше бонус."),
		NoTranslate = true,
		NoCancel = o.Buy == nil,
		ConfirmText = o.Buy or S.W("CLOSE"),
		ConfirmStyle = o.Buy and "gold" or nil,
		CancelText = S.W("CANCEL"),
		Accent = case.Kind == "Artifact" and S.Colors.Artifact or S.Colors.Accessory,
		ContentHeight = height,
		Width = 560,
		Content = function(frame, width)
			local scroll = Kit.New("ScrollingFrame", {
				Name = "OddsList",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.fromOffset(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				ZIndex = frame.ZIndex,
			}, frame)
			Kit.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
			for i, row in ipairs(lines) do
				local line = Kit.New("Frame", {
					Name = "Row_" .. row.Rarity,
					BackgroundColor3 = Kit.Theme.White,
					Size = UDim2.new(1, -8, 0, rowH),
					LayoutOrder = i,
					ZIndex = frame.ZIndex,
				}, scroll)
				Kit.Corner(line, 10)
				Kit.Stroke(line, S.RarityColor(row.Rarity), 2, 0.2)
				local tag = Kit.Pill(line, {
					Text = S.Rarity(row.Rarity),
					Color = S.RarityColor(row.Rarity),
					Height = 22,
					TextSize = 13,
					Position = UDim2.fromOffset(8, 5),
					ZIndex = frame.ZIndex + 1,
					NoTranslate = true,
				})
				local gradient = Kit.Theme.RarityGradient[row.Rarity]
				if gradient then
					tag:SetGradient(gradient[1], gradient[2])
				end
				local pct = row.Chance * 100
				Kit.Text(line, {
					Name = "Chance",
					Text = (pct >= 1 and string.format("%.1f%%", pct) or string.format("%.2f%%", pct)) .. (row.Chance < 0.02 and ("  ·  " .. Kit.Format.Odds(row.Chance)) or ""),
					Font = "numeric",
					TextSize = 18,
					AlignX = "Right",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 3),
					Size = UDim2.new(0.5, 0, 0, 24),
					ZIndex = frame.ZIndex + 1,
					NoTranslate = true,
				})
				local names = {}
				for _, def in ipairs(pool[row.Rarity] or {}) do
					table.insert(names, S.Name(def) .. " (" .. S.StatName(def.Stat) .. " " .. E.Format(def.Min) .. "–" .. E.Format(def.Max):sub(2) .. ")")
				end
				Kit.Text(line, {
					Name = "Pieces",
					Text = table.concat(names, " · "),
					TextSize = 12,
					Color = Kit.Theme.InkMuted,
					Scaled = true,
					MinTextSize = 8,
					Wrap = true,
					Position = UDim2.fromOffset(10, 27),
					Size = UDim2.new(1, -20, 0, 20),
					ZIndex = frame.ZIndex + 1,
					NoTranslate = true,
				})
			end
			if case.Pity then
				Kit.Text(scroll, {
					Name = "Pity",
					Text = T("Guarantee: at least one ", "Гарантия: хотя бы один ") .. S.Rarity(case.Pity.Rarity) .. T(" or better every ", " или лучше каждые ") .. case.Pity.Opens .. T(" opens.", " открытий."),
					TextSize = 14,
					Color = Kit.Theme.Ink,
					Wrap = true,
					Size = UDim2.new(1, -8, 0, 36),
					LayoutOrder = #lines + 1,
					ZIndex = frame.ZIndex,
					NoTranslate = true,
				})
			end
			local _ = width
		end,
	})
end

return S
