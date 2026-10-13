-- TRADE window (Trade System 2.0, docs/TRADE.md; UI kit docs/UIKIT.md). Kit window Key = "Trade".
--   Lobby (no session): incoming invitations on top (ACCEPT / DECLINE), then the players of this
--   server (avatar, name, level, TRADE button or the reason it is off) with a search box.
--   Session, desktop: "YOU GIVE" (left, blue) and "<NAME> GIVES" (right, orange) card grids with
--   rarity borders, variant / mutation tags, x N for identical entries and the coin row; the centre
--   strip holds the value check, both players' status, the countdown and the one big button that
--   walks READY -> safety countdown -> HOLD TO CONFIRM. Under "YOU GIVE": the inventory picker
--   (DOGS / FINDS, search, rarity chips, sort, - / + steppers for identical finds).
--   Phones: GIVE / GET / ADD tabs instead of the columns; the centre strip becomes a bottom bar.
--   A summary modal asks again when you give >= 3x what you get, or a Legendary or rarer asset.
-- Data: Modules.Net snapshots (Trade, Players, Profile) and DogEconomyPush 'Trade' / 'TradeInvite'
-- (live). The invite popup also works while the window is closed: ScreenGui.TradeClient loads this
-- module at start (S.Start). Requests: TradeRequest {Target}, TradeCancel {Target?}, Trade {Action =
-- Accept | Decline | Offer | Ready | Unready | Confirm}. Rules and values: DogEconomy.TradeRules.
-- Text: Localization.Trade (UI / Templates; the window's labels carry NoTranslate, server replies
-- stay translatable by DOGROTS_AutoTranslateUI).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Dict = require(RS:WaitForChild("Localization"):WaitForChild("Trade"))
local Economy = RS:WaitForChild("DogEconomy")
local Config = require(Economy:WaitForChild("Config"))
local Defs = require(Economy:WaitForChild("DogDefinitions"))
local Rules = require(Economy:WaitForChild("TradeRules"))
local Theme, Format = Kit.Theme, Kit.Format
local P = Theme.Colors
local ACCENT = Color3.fromRGB(41, 204, 168) -- UITheme.WindowSpecs.Trade
local MINE = P.blue
local THEIRS = Color3.fromRGB(255, 146, 43)
local Z = 3

local S = {}

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------
local function ru(): boolean
	return Kit.Lang() == "ru"
end
local function T(en: string): string
	if ru() then
		return Dict.UI[en] or Dict.Exact[en] or en
	end
	return en
end
local function F(en: string, ...: any): string
	local pattern = en
	if ru() then
		pattern = Dict.Templates[en] or en
	end
	return string.format(pattern, ...)
end
-- A server reply in the player's language (trade replies; the rest stays with AutoTranslate).
local function said(text: any): string
	local message = tostring(text or "")
	if not ru() then
		return message
	end
	local exact = Dict.Exact[message]
	if exact then
		return exact
	end
	for _, rule in ipairs(Dict.Patterns) do
		local out, n = string.gsub(message, rule[1], rule[2])
		if n > 0 then
			return out
		end
	end
	return message
end
local function short(n: any): string
	return Format.Short(math.max(0, math.floor(tonumber(n) or 0)))
end
local function clock(seconds: number): string
	return Format.Clock(math.max(0, math.ceil(seconds)), Kit.Lang())
end

------------------------------------------------------------------------------------------------
-- State (kept here, not in the instances)
------------------------------------------------------------------------------------------------
local st: any = {
	Snapshot = nil, -- last Net snapshot (Profile for the picker)
	Trade = nil, -- last server trade view (Engine.TradeView) or nil
	TradeAt = -1, -- server time of the trade info held
	Ended = {}, -- [tradeId] = true: sessions that ended (stale views of them are ignored)
	PlayerRows = {}, -- Runtime.TradePlayers rows (+ EndsAt clocks)
	PlayersAt = -1,
	Draft = nil, -- {Dogs, Items, Cash}: my local edits the server has not answered yet
	DraftRev = 0,
	Sending = false,
	SendAt = 0,
	Tab = "dogs",
	Query = "",
	Rarities = {},
	Sort = "rarity",
	Descending = true,
	PlayerQuery = "",
	PhoneTab = "give",
	Busy = false,
	ReviewUntil = 0, -- os.clock() when READY unlocks (server ReviewIn)
	ConfirmUntil = 0, -- os.clock() when CONFIRM unlocks (server ConfirmIn)
	LastToast = {},
}

local function me(): number
	local player = Players.LocalPlayer
	return player and player.UserId or 0
end
local function profile(): any
	return st.Snapshot and st.Snapshot.Profile or nil
end
local function key(id: any): string
	return tostring(id)
end
local function partnerId(): number?
	return st.Trade and st.Trade.Partner or nil
end
local function nameOf(id: any, fallback: string?): string
	for _, row in ipairs(st.PlayerRows) do
		if row.Id == id then
			return row.Name or fallback or "?"
		end
	end
	local player = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
	return player and player.DisplayName or fallback or T("Partner")
end
local function serverOffer(id: any): any
	local t = st.Trade
	return t and t.Offers and t.Offers[key(id)] or nil
end
-- My offer as shown: the local draft while a change is on its way, else the server's.
local function myOffer(): any
	if st.Draft then
		return st.Draft
	end
	local o = serverOffer(me())
	return { Dogs = table.clone(o and o.Dogs or {}), Items = table.clone(o and o.Items or {}), Cash = o and o.Cash or 0 }
end
local function reducedFX(): boolean
	local player = Players.LocalPlayer
	return Kit.Motion.Reduced() or (player ~= nil and (player:GetAttribute("ReducedMotion") == true or player:GetAttribute("LowFX") == true))
end
-- Throttled info toasts (live changes of the partner).
local function toastOnce(text: string, kind: string, gap: number?)
	local now = os.clock()
	if now - (st.LastToast[text] or -99) < (gap or 3) then
		return
	end
	local count = 0
	for _ in pairs(st.LastToast) do
		count += 1
	end
	if count > 40 then
		st.LastToast = {}
	end
	st.LastToast[text] = now
	Kit.Toast(text, { Kind = kind, NoTranslate = true })
end
local function serverToast(message: any, kind: string?)
	Kit.Toast(said(message), { Kind = kind or "error" })
end

------------------------------------------------------------------------------------------------
-- Assets: card data, values, protection reasons
------------------------------------------------------------------------------------------------
local function dogReason(p: any, d: any): string?
	if d.State == "Walking" then
		return T("On the way: wait for the delivery")
	elseif d.Locked then
		return T("Locked: unlock it in MY DOGS first")
	elseif (d.AssignedSlot or "") ~= "" then
		return T("Working in a kennel: take it out first")
	end
	for _, shown in pairs(p.DisplayDogs or {}) do
		if shown == d.DogUid then
			return T("On display: take it off first")
		end
	end
	if p.Reservations and p.Reservations[d.DogUid] then
		return T("Reserved")
	end
	return nil
end
local function itemReason(p: any, x: any): string?
	if x.Tradeable == false then
		return T("This find cannot be traded")
	elseif x.Favorite then
		return T("Favourite: remove the star first")
	elseif p.ItemReservations and p.ItemReservations[x.ItemUid] then
		return T("Reserved")
	end
	return nil
end
local function weightText(kg: any): string
	local w = tonumber(kg) or 0
	if w >= 100 then
		return F("%s kg", Format.Short(w))
	end
	return F("%s kg", string.format(w >= 10 and "%.1f" or "%.2f", w))
end
local function valueOf(kind: string, rec: any): number
	if type(rec) ~= "table" then
		return 0
	end
	if type(rec.Value) == "number" then
		return rec.Value
	end
	return kind == "Dog" and Rules.DogValue(rec) or Rules.ItemValue(rec)
end
local function rarityOf(kind: string, rec: any): string
	if type(rec) ~= "table" then
		return "Common"
	end
	return kind == "Dog" and Rules.DogRarity(rec) or Rules.ItemRarity(rec)
end
local function mutationOf(rec: any): string
	return string.upper(tostring(rec and rec.Mutation or "NORMAL"))
end
-- Card data of a dog / find record (a profile record or a slim trade detail).
local function cardFor(kind: string, rec: any, id: string): any
	local data: any = { Id = id, Rarity = rarityOf(kind, rec) }
	if kind == "Dog" then
		local def = Defs[rec.DogId]
		data.Name = rec.DisplayName or (def and def.DisplayName) or tostring(rec.DogId)
		data.Variant = rec.Variant
		data.Preview = { Kind = "Dog", DogId = rec.DogId, Variant = rec.Variant }
	else
		data.Name = rec.DisplayName or tostring(rec.ItemId)
		local mutation = mutationOf(rec)
		if mutation ~= "NORMAL" then
			data.Tag, data.TagColor = mutation, Theme.MutationColor(mutation)
		end
		data.Mutation = mutation
		data.Preview = { Kind = "Item", ItemId = rec.ItemId, Mutation = mutation }
	end
	return data
end
-- Entries of an offer grouped for the columns: identical dogs (species + variant + ascension) and
-- identical finds (item + mutation) become one card with x N.
local function groupsOf(id: any): ({ any }, number)
	local mine = id == me()
	local offer = mine and myOffer() or serverOffer(id)
	if not offer then
		return {}, 0
	end
	local details = (serverOffer(id) or {}).Details or {}
	local p = mine and profile() or nil
	local list, byKey, total = {}, {}, offer.Cash or 0
	local function add(kind: string, uid: string)
		local rec = (p and (kind == "Dog" and p.Dogs or p.Items)[uid]) or details[uid]
		if type(rec) ~= "table" then
			return
		end
		local groupKey = kind == "Dog" and ("D|" .. tostring(rec.DogId) .. "|" .. tostring(rec.Variant) .. "|" .. tostring(rec.AscensionLevel or 0))
			or ("I|" .. Rules.GroupKey(rec))
		local value = valueOf(kind, rec)
		total += value
		local group = byKey[groupKey]
		if not group then
			group = { Key = groupKey, Kind = kind, Uids = {}, Rec = rec, Value = 0 }
			byKey[groupKey] = group
			table.insert(list, group)
		end
		table.insert(group.Uids, uid)
		group.Value += value
	end
	for _, uid in ipairs(offer.Dogs or {}) do
		add("Dog", uid)
	end
	for _, uid in ipairs(offer.Items or {}) do
		add("Item", uid)
	end
	for _, group in ipairs(list) do
		local card = cardFor(group.Kind, group.Rec, group.Key)
		card.Count = #group.Uids
		local stats = { { Text = "≈" .. short(group.Value) } }
		if group.Kind == "Item" and #group.Uids == 1 then
			table.insert(stats, 1, { Text = weightText(group.Rec.WeightKg) })
		end
		card.Stats = stats
		card.Selected = false
		group.Card = card
	end
	return list, total
end
local function isBigGive(): boolean
	for _, group in ipairs((groupsOf(me()))) do
		if Rules.IsBig(rarityOf(group.Kind, group.Rec)) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------------------
-- UI (built once, updated in place)
------------------------------------------------------------------------------------------------
local win: any = nil
local ui: any = nil
local render: () -> ()
local renderLobby: () -> ()
local renderSession: () -> ()
local relayout: (layout: any?) -> ()
local scheduleSend: () -> ()

local function text(parent: Instance, props: any): any
	local p = table.clone(props)
	if p.NoTranslate == nil then
		p.NoTranslate = true
	end
	p.ZIndex = p.ZIndex or Z + 1
	return Kit.Text(parent, p)
end
local function panel(parent: Instance, name: string, color: Color3?): Frame
	local frame = Kit.New("Frame", {
		Name = name,
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = Z,
	}, parent)
	Kit.Corner(frame, Theme.Radius.Card)
	Kit.Stroke(frame, color or P.edge, 2, color and 0 or 0.45)
	return frame
end
local function place(object: any, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	object.Size = UDim2.fromOffset(math.max(1, math.floor(w)), math.max(1, math.floor(h)))
end

-- A virtual grid of kit cards. Wide-short views switch to list rows (like Kit.CardGrid). With
-- Stepper, groups of identical finds get - n/N + controls.
local function cards(parent: Instance, opts: any): any
	local cardSize: Vector2 = opts.CardSize or Vector2.new(132, 176)
	return Kit.VirtualGrid(parent, {
		Name = opts.Name,
		ZIndex = Z + 1,
		Gap = 8,
		Padding = 6,
		Empty = opts.Empty,
		Key = function(item: any): any
			return item.Key
		end,
		CellSize = function(w: number, h: number): Vector2
			if w < (opts.ListBelow or 300) or h < cardSize.Y * 1.15 then
				return Vector2.new(math.min(opts.RowWidth or 290, w), opts.RowHeight or 70)
			end
			return cardSize
		end,
		Create = function(frame: Frame): any
			local cell: any = {}
			cell.Card = Kit.DogCard.new(frame)
			cell.Card.OnClick = function()
				if cell.Item and opts.OnClick then
					opts.OnClick(cell.Item)
				end
			end
			if opts.Stepper then
				local z = frame.ZIndex + 12
				local bar = Kit.New("Frame", {
					Name = "Stepper",
					BackgroundColor3 = P.edge,
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(112, 30),
					Visible = false,
					ZIndex = z,
				}, frame)
				Kit.Corner(bar, "pill")
				cell.Stepper = bar
				cell.Minus = Kit.Button(bar, {
					Text = "−",
					Style = "secondary",
					Size = UDim2.fromOffset(30, 26),
					Position = UDim2.fromOffset(2, 2),
					ZIndex = z + 1,
					NoTranslate = true,
					OnClick = function()
						if cell.Item and opts.OnStep then
							opts.OnStep(cell.Item, -1)
						end
					end,
				})
				cell.Plus = Kit.Button(bar, {
					Text = "+",
					Style = "success",
					Size = UDim2.fromOffset(30, 26),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -2, 0, 2),
					ZIndex = z + 1,
					NoTranslate = true,
					OnClick = function()
						if cell.Item and opts.OnStep then
							opts.OnStep(cell.Item, 1)
						end
					end,
				})
				cell.Amount = text(bar, {
					TextSize = 15,
					Font = "numeric",
					AlignX = "Center",
					Color = Theme.White,
					Position = UDim2.fromOffset(32, 0),
					Size = UDim2.new(1, -64, 1, 0),
					ZIndex = z + 1,
				})
			end
			return cell
		end,
		Bind = function(cell: any, item: any)
			cell.Item = item
			cell.Card:Bind(item.Card)
			if cell.Stepper then
				local stepper = item.Stepper
				cell.Stepper.Visible = stepper ~= nil
				if stepper then
					cell.Amount.Text = string.format("%d/%d", stepper.In, stepper.Of)
					cell.Minus:SetDisabled(stepper.In <= 0)
					cell.Plus:SetDisabled(stepper.In >= stepper.Of)
				end
			end
		end,
		Unbind = function(cell: any)
			cell.Item = nil
		end,
		Layout = function(cell: any, w: number, h: number)
			cell.Card:Layout(w, h)
			if cell.Stepper then
				if w >= h * 1.8 then
					cell.Stepper.AnchorPoint = Vector2.new(1, 0.5)
					cell.Stepper.Position = UDim2.new(1, -40, 0.5, 0)
				else
					local previewH = math.max(40, math.floor(h * 0.5))
					cell.Stepper.AnchorPoint = Vector2.new(0.5, 1)
					cell.Stepper.Position = UDim2.new(0.5, 0, 0, 8 + previewH)
				end
			end
		end,
		Destroy = function(cell: any)
			cell.Card:Destroy()
			if cell.Minus then
				cell.Minus:Destroy()
				cell.Plus:Destroy()
			end
		end,
	})
end

------------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------------
local applyTrade: (view: any, at: number, authoritative: boolean) -> boolean
local applyPlayers: (rows: any, at: number) -> ()

-- One request; toasts a refusal; absorbs a trade view in the reply (the snapshot goes through Net).
local function request(action: string, args: any, button: any?): (boolean, any)
	if button then
		button:SetBusy(true)
	end
	local ok, result = Net.Request(action, args)
	if button then
		button:SetBusy(false)
	end
	if ok and type(result) == "table" and type(result.Trade) == "table" then
		applyTrade(result.Trade, tonumber(result.Trade.Now) or -1, false)
	end
	if not ok then
		serverToast(type(result) == "table" and result.Message or result, "error")
	end
	return ok, result
end

local function invite(row: any, button: any?)
	if st.Busy then
		return
	end
	st.Busy = true
	local ok = request("TradeRequest", { Target = row.Id }, button)
	st.Busy = false
	if ok then
		Kit.Toast(F("Invitation sent to %s", row.Name or "?"), { Kind = "success", NoTranslate = true })
	end
end
local function answer(row: any, accept: boolean, button: any?)
	if st.Busy then
		return
	end
	st.Busy = true
	local args = { Action = accept and "Accept" or "Decline", From = row.Id }
	if row.InviteIn and row.InviteIn.Id then
		args.Invite = row.InviteIn.Id
	end
	local ok = request("Trade", args, button)
	st.Busy = false
	if ok and accept then
		S.Open()
	elseif ok then
		Kit.Toast(T("Invitation declined"), { Kind = "info", NoTranslate = true })
	end
end
local function withdraw(row: any, button: any?)
	request("TradeCancel", { Target = row.Id }, button)
end

-- Offer edits: applied to the draft at once (cards respond instantly), sent after a short pause
-- so quick clicks become one request (the server rate limit is ~1.5 requests / second).
local function editOffer(fn: (draft: any) -> boolean)
	if not st.Trade then
		return
	end
	local draft = myOffer()
	if fn(draft) == false then
		return
	end
	st.Draft = draft
	st.DraftRev += 1
	scheduleSend()
	render()
end
scheduleSend = function()
	st.SendAt = os.clock() + 0.45
	if st.Sending then
		return
	end
	st.Sending = true
	task.spawn(function()
		while true do
			local left = st.SendAt - os.clock()
			if left > 0 then
				task.wait(left)
			else
				local draft = st.Draft
				if not (draft and st.Trade) then
					break
				end
				local rev = st.DraftRev
				local ok = request("Trade", { Action = "Offer", Dogs = draft.Dogs, Items = draft.Items, Cash = draft.Cash })
				if not ok then
					-- The server's offer is the truth: drop the edit it refused.
					st.Draft = nil
					break
				end
				if st.DraftRev == rev then
					st.Draft = nil
					break
				end
			end
		end
		st.Sending = false
		render()
	end)
end

local function toggleDog(uid: string)
	editOffer(function(draft)
		local index = table.find(draft.Dogs, uid)
		if index then
			table.remove(draft.Dogs, index)
			return true
		end
		if #draft.Dogs >= Rules.MaxDogs then
			Kit.Toast(F("Maximum %d dogs per trade", Rules.MaxDogs), { Kind = "warn", NoTranslate = true })
			return false
		end
		table.insert(draft.Dogs, uid)
		return true
	end)
end
-- Finds: +1 adds the next copy of the group (the cheapest first, so your best copies stay),
-- -1 removes the copy added last.
local function stepItems(uids: { string }, delta: number)
	editOffer(function(draft)
		if delta < 0 then
			for i = #draft.Items, 1, -1 do
				if table.find(uids, draft.Items[i]) then
					table.remove(draft.Items, i)
					return true
				end
			end
			return false
		end
		if #draft.Items >= Rules.MaxItems then
			Kit.Toast(F("Maximum %d finds per trade", Rules.MaxItems), { Kind = "warn", NoTranslate = true })
			return false
		end
		for _, uid in ipairs(uids) do
			if not table.find(draft.Items, uid) then
				table.insert(draft.Items, uid)
				return true
			end
		end
		Kit.Toast(T("Every copy is already in the trade"), { Kind = "info", NoTranslate = true })
		return false
	end)
end
local function removeGroup(group: any)
	editOffer(function(draft)
		local list = group.Kind == "Dog" and draft.Dogs or draft.Items
		for i = #list, 1, -1 do
			if table.find(group.Uids, list[i]) then
				table.remove(list, i)
				return true
			end
		end
		return false
	end)
end
local function parseCash(raw: string): number?
	local s = string.lower((string.gsub(raw or "", "[%s,_]", "")))
	if s == "" then
		return 0
	end
	local digits, suffix = string.match(s, "^([%d%.]+)([kmbt]?)$")
	local n = tonumber(digits or "")
	if not n then
		return nil
	end
	local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12 } :: any)[suffix] or 1
	return math.floor(n * mult)
end
local function setCash(raw: string)
	local p = profile()
	local n = parseCash(raw)
	if not n then
		Kit.Toast(T("Type a number, e.g. 2500 or 1.5k"), { Kind = "warn", NoTranslate = true })
		render()
		return
	end
	local wallet = p and tonumber(p.Cash) or 0
	if n > wallet then
		Kit.Toast(T("You do not have that many coins"), { Kind = "warn", NoTranslate = true })
		n = math.max(0, math.floor(wallet))
	end
	editOffer(function(draft)
		if draft.Cash == n then
			return false
		end
		draft.Cash = n
		return true
	end)
end

local function sendStep(action: string, button: any?)
	local t = st.Trade
	if not t or st.Busy then
		return
	end
	st.Busy = true
	request("Trade", { Action = action, Version = t.Version }, button)
	st.Busy = false
	render()
end
-- The summary modal for risky trades, then CONFIRM.
local function confirmTrade(button: any)
	local t = st.Trade
	if not t then
		return
	end
	local give, giveValue = groupsOf(me())
	local get, getValue = groupsOf(t.Partner)
	local fair = Rules.Fairness(giveValue, getValue)
	if not (fair.Warn or isBigGive()) then
		sendStep("Confirm", button)
		return
	end
	local list = {}
	for _, group in ipairs(give) do
		local card = table.clone(group.Card)
		card.Badge, card.BadgeColor = T("YOU GIVE"), Theme.Danger
		card.Subtitle = "≈" .. short(group.Value)
		table.insert(list, card)
	end
	for _, group in ipairs(get) do
		local card = table.clone(group.Card)
		card.Badge, card.BadgeColor = T("YOU GET"), Theme.Success
		card.Subtitle = "≈" .. short(group.Value)
		table.insert(list, card)
	end
	local body
	if fair.Warn then
		body = F("You give about %s and get about %s. Check every card before you confirm.", short(giveValue), short(getValue))
	else
		body = T("You are giving away a Legendary or rarer dog or find. Check every card before you confirm.")
	end
	local version = t.Version
	Kit.Confirm(T("CONFIRM THIS TRADE?"), body, {
		Cards = list,
		CardKind = "Dog",
		Danger = true,
		ConfirmText = T("CONFIRM TRADE"),
		CancelText = T("BACK"),
		NoTranslate = true,
	}):Then(function(ok)
		if ok and st.Trade and st.Trade.Version == version then
			sendStep("Confirm", button)
		elseif ok then
			Kit.Toast(T("The offer changed. Check it again."), { Kind = "warn", NoTranslate = true })
		end
	end)
end

------------------------------------------------------------------------------------------------
-- Celebration (a short confetti burst; pooled, nothing runs afterwards)
------------------------------------------------------------------------------------------------
local confetti: any = nil
local celebrating = false
local function celebrate()
	if celebrating or reducedFX() then
		return
	end
	local layer = Kit.Overlay.Top()
	if not confetti then
		confetti = { Pieces = {} }
		for i = 1, 26 do
			local piece = Kit.New("Frame", {
				Name = "TradeConfetti" .. i,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Visible = false,
				ZIndex = 940,
			}, layer)
			Kit.Corner(piece, i % 3 == 0 and "pill" or 3)
			table.insert(confetti.Pieces, piece)
		end
		local label = Kit.Text(layer, {
			Name = "TradeDone",
			Text = "",
			TextSize = 46,
			Color = Theme.White,
			Stroke = true,
			AlignX = "Center",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(600, 70),
			ZIndex = 945,
			NoTranslate = true,
		})
		label.Visible = false
		confetti.Label = label
		confetti.Scale = Kit.New("UIScale", {}, label)
	end
	celebrating = true
	local size = layer.AbsoluteSize
	local cx, cy = size.X / 2, size.Y * 0.42
	local colors = { P.gold, P.green, P.blue, P.purple, P.red, ACCENT, Theme.Rarity.Secret }
	local rng = Random.new()
	for i, piece in ipairs(confetti.Pieces) do
		local angle = (i / #confetti.Pieces) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local distance = rng:NextNumber(150, 360)
		local s = rng:NextInteger(8, 15)
		piece.BackgroundColor3 = colors[(i % #colors) + 1]
		piece.BackgroundTransparency = 0
		piece.Size = UDim2.fromOffset(s, math.floor(s * rng:NextNumber(0.6, 1.4)))
		piece.Position = UDim2.fromOffset(cx, cy)
		piece.Rotation = 0
		piece.Visible = true
		Kit.Motion.Tween(piece, rng:NextNumber(0.9, 1.3), {
			Position = UDim2.fromOffset(cx + math.cos(angle) * distance, cy + math.sin(angle) * distance * 0.75 + 60),
			Rotation = rng:NextInteger(-260, 260),
			BackgroundTransparency = 1,
		})
	end
	local label = confetti.Label
	label.Text = T("TRADE COMPLETE!")
	label.Position = UDim2.fromOffset(cx, cy)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	label.Visible = true
	confetti.Scale.Scale = 0.6
	Kit.Motion.Tween(confetti.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.4, function()
		Kit.Motion.Tween(label, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(1.8, function()
		for _, piece in ipairs(confetti.Pieces) do
			piece.Visible = false
		end
		label.Visible = false
		celebrating = false
	end)
end

------------------------------------------------------------------------------------------------
-- Invite popup (outside the window: a small card in the kit overlay layer; never blocks input)
------------------------------------------------------------------------------------------------
local banner: any = nil
local function hideBanner()
	if banner then
		banner.Root.Visible = false
		banner.Kind, banner.Row = nil, nil
		if banner.Countdown then
			banner.Countdown:SetEndsAt(nil)
		end
	end
end
local function buildBanner()
	if banner then
		return banner
	end
	local layer = Kit.Overlay.Top()
	banner = {}
	local root = Kit.New("Frame", {
		Name = "TradeInvitePopup",
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(360, 112),
		Visible = false,
		Active = true,
		ZIndex = 950,
	}, layer)
	Kit.Corner(root, 16)
	Kit.Stroke(root, ACCENT, 3)
	banner.Root = root
	banner.Avatar = Kit.New("ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = P.secondary,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 951,
	}, root)
	Kit.Corner(banner.Avatar, "pill")
	banner.Title = text(root, { TextSize = 17, Scaled = true, MinTextSize = 11, Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -112, 0, 24), ZIndex = 951 })
	banner.Sub = text(root, { TextSize = 13, Color = Theme.InkMuted, Position = UDim2.fromOffset(72, 32), Size = UDim2.new(1, -150, 0, 18), ZIndex = 951 })
	banner.Countdown = Kit.Countdown(root, {
		TextSize = 13,
		Color = Theme.InkMuted,
		AlignX = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 32),
		Size = UDim2.fromOffset(70, 18),
		ZIndex = 951,
		DoneText = "",
		OnDone = function()
			if banner.Kind == "invite" then
				hideBanner()
			end
		end,
	})
	banner.More = Kit.Pill(root, { Text = "", Height = 18, TextSize = 11, Color = P.red, Position = UDim2.fromOffset(40, 50), ZIndex = 953, NoTranslate = true })
	banner.More:SetVisible(false)
	banner.Close = Kit.Button(root, {
		Text = "×",
		Style = "ghost",
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		ZIndex = 952,
		NoTranslate = true,
		OnClick = hideBanner,
	})
	banner.Yes = Kit.Button(root, {
		Text = T("ACCEPT"),
		Style = "success",
		Size = UDim2.new(0.5, -15, 0, 40),
		Position = UDim2.new(0, 10, 1, -48),
		ZIndex = 952,
		NoTranslate = true,
	})
	banner.No = Kit.Button(root, {
		Text = T("DECLINE"),
		Style = "secondary",
		Size = UDim2.new(0.5, -15, 0, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 1, -48),
		ZIndex = 952,
		NoTranslate = true,
	})
	banner.Yes:SetOnClick(function()
		local row = banner.Row
		if banner.Kind == "invite" and row then
			hideBanner()
			answer(row, true)
		elseif banner.Kind == "started" then
			hideBanner()
			S.Open()
		end
	end)
	banner.No:SetOnClick(function()
		local row = banner.Row
		if banner.Kind == "invite" and row then
			hideBanner()
			answer(row, false)
		else
			hideBanner()
		end
	end)
	local function position()
		local x, y, w = 0, 0, layer.AbsoluteSize.X
		local ok, sx, sy, sw = pcall(function()
			local guiService: any = game:GetService("GuiService")
			local inset = guiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
			return inset.Min.X, inset.Min.Y, inset.Max.X - inset.Min.X
		end)
		if ok and sw then
			x, y, w = sx, sy, sw
		end
		local width = math.min(360, w - 16)
		root.Size = UDim2.fromOffset(width, 112)
		if w >= 700 then
			root.AnchorPoint = Vector2.new(1, 0)
			root.Position = UDim2.fromOffset(x + w - 16, y + 76)
		else
			root.AnchorPoint = Vector2.new(0.5, 0)
			root.Position = UDim2.fromOffset(x + w / 2, y + 8)
		end
	end
	banner.Position = position
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Visible then
			position()
		end
	end)
	return banner
end
local function incoming(): { any }
	local list = {}
	for _, row in ipairs(st.PlayerRows) do
		if row.InviteIn and (row.InviteIn.EndsAt or 0) > os.clock() then
			table.insert(list, row)
		end
	end
	table.sort(list, function(a, b)
		return (a.InviteIn.EndsAt or 0) > (b.InviteIn.EndsAt or 0)
	end)
	return list
end
-- Shows the newest incoming invitation (kind "invite") or "your trade started" (kind "started").
local function showBanner(kind: string, row: any)
	if kind == "invite" then
		-- An invite needs an answer: Hide UI (screenshots) gives way, or the card would sit in a
		-- disabled layer until the invite expires.
		local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
		local mainGui = pg and pg:FindFirstChild("ScreenGui")
		if mainGui and mainGui:GetAttribute("UIHidden") == true then
			mainGui:SetAttribute("UIHidden", nil)
		end
	end
	local b = buildBanner()
	b.Kind, b.Row = kind, row
	b.Avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(row.Id) .. "&w=150&h=150"
	if kind == "invite" then
		b.Title.Text = F("%s wants to trade", row.Name or "?")
		b.Sub.Text = row.Level and F("Level %d", row.Level) or ""
		b.Yes:SetText(T("ACCEPT"))
		b.No:SetText(T("DECLINE"))
		local left = math.max(0, (row.InviteIn and row.InviteIn.EndsAt or os.clock()) - os.clock())
		b.Countdown:SetEndsAt(Kit.Now() + left)
		local others = #incoming() - 1
		b.More:SetVisible(others > 0)
		b.More:Set("+" .. tostring(others))
	else
		b.Title.Text = F("Trade with %s started", row.Name or "?")
		b.Sub.Text = T("Open the window to add your offer")
		b.Yes:SetText(T("OPEN"))
		b.No:SetText(T("LATER"))
		b.Countdown:SetEndsAt(nil)
		b.More:SetVisible(false)
	end
	b.Position()
	b.Root.Visible = true
	if not reducedFX() then
		local final = b.Root.Position
		b.Root.Position = final - UDim2.fromOffset(0, 12)
		Kit.Motion.Tween(b.Root, 0.22, { Position = final }, Enum.EasingStyle.Back)
	end
end

------------------------------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------------------------------
local function rarityOptions(): { any }
	local out = {}
	for _, r in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
		table.insert(out, { Id = r, Text = T(string.upper(r)), Color = Theme.RarityColor(r), NoTranslate = true })
	end
	return out
end

local function buildLobby(root: Frame)
	local lobby = Kit.New("Frame", { Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z }, root)
	ui.Lobby = lobby
	ui.InvitesTitle = text(lobby, { Text = T("INVITATIONS"), TextSize = 18, Color = THEIRS })
	ui.Invites = Kit.VirtualList(lobby, {
		Name = "Invites",
		RowHeight = 66,
		ZIndex = Z + 1,
		Key = function(row: any): any
			return row.Id
		end,
		Create = function(frame: Frame): any
			local c: any = {}
			local face = panel(frame, "Invite", THEIRS)
			face.Size = UDim2.fromScale(1, 1)
			face.ZIndex = frame.ZIndex + 1
			local z = frame.ZIndex + 2
			c.Avatar = Kit.New("ImageLabel", { BackgroundColor3 = P.secondary, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(48, 48), ZIndex = z }, face)
			Kit.Corner(c.Avatar, "pill")
			c.Title = text(face, { TextSize = 17, Scaled = true, MinTextSize = 11, Position = UDim2.fromOffset(64, 8), Size = UDim2.new(1, -300, 0, 24), ZIndex = z })
			c.Left = Kit.Countdown(face, { TextSize = 13, Color = Theme.InkMuted, Prefix = T("Expires in "), Position = UDim2.fromOffset(64, 34), Size = UDim2.new(1, -300, 0, 18), ZIndex = z, DoneText = T("Expired") })
			c.Yes = Kit.Button(face, { Text = T("ACCEPT"), Style = "success", Size = UDim2.fromOffset(110, 42), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -128, 0.5, 0), ZIndex = z, NoTranslate = true })
			c.No = Kit.Button(face, { Text = T("DECLINE"), Style = "secondary", Size = UDim2.fromOffset(110, 42), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = z, NoTranslate = true })
			c.Yes:SetOnClick(function()
				if c.Item then
					answer(c.Item, true, c.Yes)
				end
			end)
			c.No:SetOnClick(function()
				if c.Item then
					answer(c.Item, false, c.No)
				end
			end)
			c.Face = face
			return c
		end,
		Bind = function(c: any, row: any)
			c.Item = row
			c.Avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(row.Id) .. "&w=150&h=150"
			c.Title.Text = F("%s wants to trade", row.Name or "?")
			c.Left:SetEndsAt(Kit.Now() + math.max(0, (row.InviteIn and row.InviteIn.EndsAt or 0) - os.clock()))
		end,
		Unbind = function(c: any)
			c.Item = nil
		end,
		Layout = function(c: any, w: number)
			local narrow = w < 470
			local bw = narrow and 84 or 110
			c.Yes.Instance.Size = UDim2.fromOffset(bw, 42)
			c.No.Instance.Size = UDim2.fromOffset(bw, 42)
			c.Yes.Instance.Position = UDim2.new(1, -(bw + 18), 0.5, 0)
			c.Title.Size = UDim2.new(1, -(64 + bw * 2 + 30), 0, 24)
			c.Left.Instance.Size = UDim2.new(1, -(64 + bw * 2 + 30), 0, 18)
		end,
		Destroy = function(c: any)
			c.Yes:Destroy()
			c.No:Destroy()
			c.Left:Destroy()
		end,
	})
	ui.PlayersTitle = text(lobby, { Text = T("PLAYERS IN THIS SERVER"), TextSize = 18 })
	ui.Rule = text(lobby, { TextSize = 13, Color = Theme.InkMuted, Wrap = true })
	ui.PlayerSearch = Kit.SearchBox(lobby, {
		Placeholder = T("Find a player"),
		ZIndex = Z + 1,
		OnChange = function(value: string)
			st.PlayerQuery = string.lower(value or "")
			renderLobby()
		end,
	})
	ui.Players = Kit.VirtualGrid(lobby, {
		Name = "Players",
		ZIndex = Z + 1,
		Gap = 8,
		Padding = 4,
		CellSize = function(w: number): Vector2
			return Vector2.new(math.min(w, 330), 84)
		end,
		Key = function(row: any): any
			return row.Id
		end,
		Empty = { Icon = "Trade", Title = T("NO PLAYERS YET"), Body = T("Nobody else is in this server right now."), NoTranslate = true },
		Create = function(frame: Frame): any
			local c: any = {}
			local face = panel(frame, "Player")
			face.Size = UDim2.fromScale(1, 1)
			face.ZIndex = frame.ZIndex + 1
			local z = frame.ZIndex + 2
			c.Avatar = Kit.New("ImageLabel", { BackgroundColor3 = P.secondary, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(60, 60), ZIndex = z }, face)
			Kit.Corner(c.Avatar, "pill")
			c.Name = text(face, { TextSize = 18, Scaled = true, MinTextSize = 11, Position = UDim2.fromOffset(80, 8), Size = UDim2.new(1, -206, 0, 24), ZIndex = z })
			c.Sub = text(face, { TextSize = 13, Color = Theme.InkMuted, Position = UDim2.fromOffset(80, 33), Size = UDim2.new(1, -206, 0, 18), ZIndex = z })
			c.Status = Kit.Pill(face, { Text = "", Height = 18, TextSize = 11, Position = UDim2.fromOffset(80, 55), ZIndex = z, NoTranslate = true })
			c.Button = Kit.Button(face, { Text = T("TRADE"), Size = UDim2.fromOffset(112, 44), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = z, NoTranslate = true })
			c.Tip = Kit.Tooltip(c.Button.Instance, function()
				return c.Reason or ""
			end)
			c.Button:SetOnClick(function()
				local row = c.Item
				if not row then
					return
				end
				if row.InviteIn then
					answer(row, true, c.Button)
				elseif row.Block == "Sent" then
					withdraw(row, c.Button)
				else
					invite(row, c.Button)
				end
			end)
			return c
		end,
		Bind = function(c: any, row: any)
			c.Item = row
			c.Avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(row.Id) .. "&w=150&h=150"
			c.Name.Text = row.Name or "?"
			local myLevel = (profile() and tonumber(profile().Level)) or 1
			c.Sub.Text = F("@%s · Level %d", tostring(row.Username or row.Name or "?"), tonumber(row.Level) or 1)
			local status, color = T("ONLINE"), P.secondary
			if row.InviteIn then
				status, color = T("INVITED YOU"), P.green
			elseif row.Status == "Trading" then
				status, color = T("TRADING"), P.gold
			end
			c.Status:Set(status, color)
			local caption, style, enabled, reason = T("TRADE"), "primary", true, nil
			local block = row.Block
			if row.InviteIn then
				caption, style = T("ACCEPT"), "success"
			elseif block == "Level" then
				caption, enabled, reason = F("LV %d", Config.TradeLevel), false, F("Reach level %d to trade (you are level %d)", Config.TradeLevel, myLevel)
			elseif block == "TheirLevel" then
				caption, enabled, reason = F("LV %d", Config.TradeLevel), false, F("This player needs level %d", Config.TradeLevel)
			elseif block == "Busy" then
				caption, enabled, reason = T("BUSY"), false, T("This player is in another trade")
			elseif block == "Trading" then
				enabled, reason = false, T("Finish your current trade first")
			elseif block == "Sent" then
				caption, style, reason = T("CANCEL"), "secondary", T("Invitation sent. Tap to take it back")
				local left = math.max(0, (row.InviteOut and row.InviteOut.EndsAt or 0) - os.clock())
				c.Sub.Text = F("Invitation sent · %s", clock(left))
			elseif block == "Cooldown" then
				local left = math.max(0, (row.CooldownEndsAt or 0) - os.clock())
				caption, enabled, reason = F("WAIT %ds", math.ceil(left)), false, T("Wait a moment before inviting this player again")
			end
			c.Reason = reason
			c.Button:SetText(caption)
			c.Button:SetStyle(style)
			c.Button:SetDisabled(not enabled)
		end,
		Unbind = function(c: any)
			c.Item = nil
		end,
		Destroy = function(c: any)
			c.Button:Destroy()
			if c.Tip and c.Tip.Destroy then
				c.Tip.Destroy()
			end
		end,
	})
end

local function buildColumn(root: Frame, name: string, color: Color3, mine: boolean): any
	local col: any = {}
	col.Frame = panel(root, name, color)
	local header = Kit.New("Frame", { Name = "Header", BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = Z + 1 }, col.Frame)
	Kit.Corner(header, Theme.Radius.Card - 2)
	col.Header = header
	col.Title = text(header, { TextSize = 19, Scaled = true, MinTextSize = 12, Color = Theme.White, Stroke = 0.3, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0), ZIndex = Z + 2 })
	col.Value = text(header, { TextSize = 16, Font = "numeric", Color = Theme.White, Stroke = 0.3, AlignX = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 130, 1, 0), ZIndex = Z + 2 })
	col.Grid = cards(col.Frame, {
		Name = name .. "Cards",
		CardSize = Vector2.new(124, 164),
		RowHeight = 64,
		RowWidth = 220,
		ListBelow = 250,
		Empty = mine and { Icon = "Inventory", Title = T("NOTHING YET"), Body = T("Add dogs, finds or coins to your offer."), NoTranslate = true }
			or { Icon = "Trade", Title = T("NOTHING YET"), Body = T("Your partner has not added anything."), NoTranslate = true },
		OnClick = function(group: any)
			if mine then
				removeGroup(group)
			end
		end,
	})
	local cash = Kit.New("Frame", { Name = "Cash", BackgroundColor3 = Theme.Field, BorderSizePixel = 0, ZIndex = Z + 1 }, col.Frame)
	Kit.Corner(cash, Theme.Radius.Field)
	col.Cash = cash
	Kit.Icon(cash, "Coins", { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = Z + 2, Glyph = "$" })
	col.CashCaption = text(cash, { Text = T("COINS"), TextSize = 14, Color = Theme.InkMuted, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(0, 80, 1, 0), ZIndex = Z + 2 })
	if mine then
		local box = Kit.New("TextBox", {
			Name = "Amount",
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "0",
			PlaceholderText = "0",
			PlaceholderColor3 = Theme.InkMuted,
			TextColor3 = Theme.Ink,
			FontFace = Theme.FontNumeric,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(1, -130, 1, -10),
			ZIndex = Z + 2,
		}, cash)
		box:SetAttribute("NoTranslate", true)
		box:SetAttribute("KeepFont", true)
		Kit.Corner(box, Theme.Radius.Small)
		Kit.Padding(box, 8, 0, 8, 0)
		box.FocusLost:Connect(function()
			setCash(box.Text)
		end)
		col.CashBox = box
	else
		col.CashLabel = text(cash, { TextSize = 17, Font = "numeric", AlignX = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(1, -130, 1, 0), ZIndex = Z + 2 })
	end
	return col
end

local function buildPicker(root: Frame)
	local pick: any = {}
	pick.Frame = panel(root, "Picker")
	pick.Tabs = Kit.Tabs(pick.Frame, {
		Tabs = { { Id = "dogs", Text = T("DOGS"), NoTranslate = true }, { Id = "items", Text = T("FINDS"), NoTranslate = true } },
		Selected = st.Tab,
		Accent = MINE,
		ZIndex = Z + 1,
		TextSize = 15,
		OnChange = function(id: string)
			st.Tab = id
			renderSession()
		end,
	})
	pick.Sort = Kit.SortSelect(pick.Frame, {
		Options = { { Id = "rarity", Text = T("RARITY") }, { Id = "value", Text = T("VALUE") }, { Id = "newest", Text = T("NEWEST") } },
		Selected = st.Sort,
		ZIndex = Z + 1,
		OnChange = function(id: string, descending: boolean)
			st.Sort, st.Descending = id, descending
			renderSession()
		end,
	})
	pick.Search = Kit.SearchBox(pick.Frame, {
		Placeholder = T("Search by name"),
		ZIndex = Z + 1,
		OnChange = function(value: string)
			st.Query = string.lower(value or "")
			renderSession()
		end,
	})
	pick.Chips = Kit.Chips(pick.Frame, {
		Multi = true,
		Options = rarityOptions(),
		ZIndex = Z + 1,
		TextSize = 13,
		OnChange = function(selected: any)
			local set = {}
			for _, id in ipairs(selected or {}) do
				set[id] = true
			end
			st.Rarities = set
			renderSession()
		end,
	})
	pick.Grid = cards(pick.Frame, {
		Name = "PickerCards",
		CardSize = Vector2.new(132, 176),
		RowHeight = 66,
		RowWidth = 300,
		ListBelow = 280,
		Stepper = true,
		Empty = { Icon = "Inventory", Title = T("NOTHING TO ADD"), Body = T("Try another search or filter."), NoTranslate = true },
		OnClick = function(item: any)
			if item.Kind == "Dog" then
				toggleDog(item.Uids[1])
			elseif #item.Uids == 1 then
				local uid = item.Uids[1]
				local inOffer = table.find(myOffer().Items, uid) ~= nil
				stepItems(item.Uids, inOffer and -1 or 1)
			else
				stepItems(item.Uids, 1)
			end
		end,
		OnStep = function(item: any, delta: number)
			stepItems(item.Uids, delta)
		end,
	})
	ui.Picker = pick
end

local function buildCenter(root: Frame)
	local c: any = {}
	c.Frame = panel(root, "Center", ACCENT)
	c.Heading = text(c.Frame, { Text = T("VALUE CHECK"), TextSize = 15, Color = Theme.InkMuted, AlignX = "Center" })
	c.Give = text(c.Frame, { TextSize = 15, Font = "numeric", Color = MINE, Scaled = true, MinTextSize = 10 })
	c.Get = text(c.Frame, { TextSize = 15, Font = "numeric", Color = THEIRS, Scaled = true, MinTextSize = 10 })
	c.Bar = Kit.ProgressBar(c.Frame, { Value = 0.5, Height = 16, Color = P.green, ZIndex = Z + 1, NoTranslate = true })
	c.Verdict = Kit.Pill(c.Frame, { Text = "", Height = 24, TextSize = 13, ZIndex = Z + 2, NoTranslate = true })
	c.Note = text(c.Frame, { Text = T("Estimate only. Always check the cards."), TextSize = 12, Color = Theme.InkMuted, Wrap = true, AlignX = "Center" })
	c.Mine = Kit.Pill(c.Frame, { Text = "", Height = 26, TextSize = 13, ZIndex = Z + 2, NoTranslate = true })
	c.Theirs = Kit.Pill(c.Frame, { Text = "", Height = 26, TextSize = 13, ZIndex = Z + 2, NoTranslate = true })
	c.Status = text(c.Frame, { TextSize = 14, Scaled = true, MinTextSize = 10, AlignX = "Right" })
	c.Countdown = Kit.Countdown(c.Frame, {
		TextSize = 22,
		AlignX = "Center",
		Color = P.gold,
		Prefix = T("CONFIRM IN "),
		DoneText = "",
		ZIndex = Z + 2,
		OnDone = function()
			if c.State == "countdown" then
				render()
			end
		end,
	})
	c.Steps = text(c.Frame, { Text = T("1 ADD · 2 READY · 3 WAIT · 4 HOLD CONFIRM"), TextSize = 12, Color = Theme.InkMuted, Wrap = true, AlignX = "Center" })
	c.Main = Kit.Button(c.Frame, { Text = T("READY"), Style = "gold", TextSize = 20, ZIndex = Z + 2, NoTranslate = true })
	c.Main:SetOnClick(function()
		local state = c.State
		if state == "ready" then
			sendStep("Ready", c.Main)
		elseif state == "confirm" then
			confirmTrade(c.Main)
		end
	end)
	c.Unready = Kit.Button(c.Frame, { Text = T("NOT READY"), Style = "secondary", TextSize = 15, ZIndex = Z + 2, NoTranslate = true })
	c.Unready:SetOnClick(function()
		sendStep("Unready", c.Unready)
	end)
	c.Cancel = Kit.Button(c.Frame, { Text = T("CANCEL TRADE"), Style = "danger", TextSize = 15, ZIndex = Z + 2, NoTranslate = true })
	c.Cancel:SetOnClick(function()
		if st.Busy then
			return
		end
		st.Busy = true
		local ok = request("TradeCancel", {}, c.Cancel)
		st.Busy = false
		if ok then
			st.Draft = nil
		end
	end)
	ui.Center = c
end

local function build()
	ui = { Lang = Kit.Lang(), InviteRows = {} }
	win = Kit.Window.new({
		Key = "Trade",
		Title = T("TRADE"),
		Subtitle = T("Swap dogs, finds and coins with players here"),
		Accent = ACCENT,
		Icon = "Trade",
		MaxSize = Vector2.new(1200, 800),
		NoTranslate = true,
		OnOpen = function()
			S._opened()
		end,
		OnClose = function()
			S._closed()
		end,
	})
	buildLobby(win.Body)
	local session = Kit.New("Frame", { Name = "Session", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = Z }, win.Body)
	ui.Session = session
	ui.PhoneTabs = Kit.Tabs(session, {
		Tabs = {
			{ Id = "give", Text = T("GIVE"), NoTranslate = true },
			{ Id = "get", Text = T("GET"), NoTranslate = true },
			{ Id = "add", Text = T("ADD"), NoTranslate = true },
		},
		Selected = st.PhoneTab,
		Accent = ACCENT,
		ZIndex = Z + 1,
		TextSize = 15,
		OnChange = function(id: string)
			st.PhoneTab = id
			relayout()
		end,
	})
	ui.Give = buildColumn(session, "YouGive", MINE, true)
	ui.Get = buildColumn(session, "TheyGive", THEIRS, false)
	buildPicker(session)
	buildCenter(session)
	win.Resized:Connect(function(layout)
		relayout(layout)
	end)
end

------------------------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------------------------
local function layoutColumn(col: any, w: number, h: number, compact: boolean)
	local headerH = compact and 34 or 40
	local cashH = compact and 40 or 46
	place(col.Header, 4, 4, w - 8, headerH)
	place(col.Grid.Instance, 2, headerH + 8, w - 4, h - headerH - cashH - 16)
	place(col.Cash, 6, h - cashH - 6, w - 12, cashH)
	col.Value.Size = UDim2.new(0, math.min(150, math.floor(w * 0.4)), 1, 0)
	col.Title.Size = UDim2.new(1, -(math.min(150, math.floor(w * 0.4)) + 24), 1, 0)
end
local function layoutPicker(pick: any, w: number, h: number, compact: boolean)
	local pad = 6
	local y = pad
	local sortW = math.min(200, math.floor(w * 0.45))
	if compact and w >= 520 then
		-- One toolbar row: tabs, search, sort; chips under it.
		local tabsW = 190
		place(pick.Tabs.Instance, pad, y, tabsW, 36)
		place(pick.Search.Instance, pad + tabsW + 6, y, w - tabsW - sortW - pad * 2 - 12, 36)
		place(pick.Sort.Instance, w - sortW - pad, y, sortW, 36)
		y += 42
	else
		place(pick.Tabs.Instance, pad, y, w - sortW - pad * 2 - 6, 38)
		place(pick.Sort.Instance, w - sortW - pad, y, sortW, 38)
		y += 44
		place(pick.Search.Instance, pad, y, w - pad * 2, 38)
		y += 44
	end
	place(pick.Chips.Instance, pad, y, w - pad * 2, 32)
	y += 36
	place(pick.Grid.Instance, 2, y, w - 4, h - y - 4)
end
local function layoutCenter(c: any, w: number, h: number, mode: string)
	local everything = { c.Heading, c.Give, c.Get, c.Note, c.Steps, c.Countdown.Instance, c.Bar.Instance, c.Verdict.Instance, c.Mine.Instance, c.Theirs.Instance }
	for _, object in ipairs(everything) do
		object.Visible = true
	end
	c.Status.Visible = mode ~= "column"
	c.Cancel:SetText(mode == "column" and T("CANCEL TRADE") or T("CANCEL"))
	c.Verdict.Instance.AnchorPoint = Vector2.new(0.5, 0)
	c.Mine.Instance.AnchorPoint = Vector2.new(0.5, 0)
	c.Theirs.Instance.AnchorPoint = Vector2.new(0.5, 0)
	if mode == "column" then
		local pad = 10
		local iw = w - pad * 2
		place(c.Heading, pad, 8, iw, 20)
		place(c.Give, pad, 32, iw, 20)
		place(c.Get, pad, 54, iw, 20)
		place(c.Bar.Instance, pad, 80, iw, 16)
		c.Verdict.Instance.Position = UDim2.fromOffset(w / 2, 102)
		place(c.Note, pad, 130, iw, 32)
		c.Mine.Instance.Position = UDim2.fromOffset(w / 2, 172)
		c.Theirs.Instance.Position = UDim2.fromOffset(w / 2, 204)
		place(c.Countdown.Instance, pad, 240, iw, 30)
		local bottom = h - pad
		place(c.Cancel.Instance, pad, bottom - 40, iw, 40)
		bottom -= 46
		place(c.Unready.Instance, pad, bottom - 38, iw, 38)
		bottom -= 44
		place(c.Main.Instance, pad, bottom - 60, iw, 60)
		bottom -= 66
		place(c.Steps, pad, math.max(274, bottom - 40), iw, 36)
		c.Steps.Visible = bottom - 40 >= 274
	elseif mode == "bar" then
		-- Phone portrait: status / value on top, the buttons below.
		local pad = 8
		local iw = w - pad * 2
		c.Heading.Visible, c.Note.Visible, c.Steps.Visible, c.Give.Visible, c.Get.Visible = false, false, false, false, false
		c.Mine.Instance.Visible, c.Theirs.Instance.Visible = false, false
		c.Verdict.Instance.AnchorPoint = Vector2.new(0, 0)
		c.Verdict.Instance.Position = UDim2.fromOffset(pad, 5)
		place(c.Status, pad + iw * 0.45, 5, iw * 0.55, 24)
		c.Status.TextXAlignment = Enum.TextXAlignment.Right
		place(c.Bar.Instance, pad, 34, iw, 12)
		place(c.Countdown.Instance, pad, 48, iw, 20)
		local y = h - 52 - pad
		place(c.Cancel.Instance, pad, y, 92, 52)
		local unreadyW = c.Unready.Instance.Visible and 104 or 0
		place(c.Main.Instance, pad + 98, y, iw - 98 - (unreadyW > 0 and unreadyW + 6 or 0), 52)
		place(c.Unready.Instance, w - pad - unreadyW, y, math.max(1, unreadyW), 52)
	else
		-- Phone landscape: one row.
		local pad = 6
		c.Heading.Visible, c.Note.Visible, c.Steps.Visible, c.Give.Visible, c.Get.Visible = false, false, false, false, false
		c.Mine.Instance.Visible, c.Theirs.Instance.Visible = false, false
		local x = pad
		place(c.Cancel.Instance, x, pad, 84, h - pad * 2)
		x += 90
		local infoW = math.max(140, math.floor((w - x) * 0.32))
		c.Verdict.Instance.AnchorPoint = Vector2.new(0, 0)
		c.Verdict.Instance.Position = UDim2.fromOffset(x, pad)
		place(c.Bar.Instance, x, h - pad - 14, infoW, 12)
		place(c.Status, x + infoW + 8, pad, 150, 20)
		c.Status.TextXAlignment = Enum.TextXAlignment.Left
		place(c.Countdown.Instance, x + infoW + 8, h - pad - 22, 150, 20)
		local unreadyW = c.Unready.Instance.Visible and 100 or 0
		local mainW = math.min(260, w - (x + infoW + 170) - unreadyW - pad)
		place(c.Main.Instance, w - pad - unreadyW - (unreadyW > 0 and 6 or 0) - mainW, pad, mainW, h - pad * 2)
		place(c.Unready.Instance, w - pad - unreadyW, pad, math.max(1, unreadyW), h - pad * 2)
	end
end

relayout = function(layout: any?)
	if not win then
		return
	end
	local l = layout or win:GetLayout()
	local W, H = l.Width or 0, l.Height or 0
	if W < 10 or H < 10 then
		return
	end
	-- Lobby
	do
		local y = 0
		local invites = #ui.InviteRows
		ui.InvitesTitle.Visible = invites > 0
		ui.Invites.Instance.Visible = invites > 0
		if invites > 0 then
			place(ui.InvitesTitle, 4, 0, W - 8, 24)
			local listH = math.min(invites, l.Phone and 1.6 or 2.4) * 72 + 6
			place(ui.Invites.Instance, 0, 26, W, listH)
			y = 26 + listH + 6
		end
		local searchW = l.Phone and W or math.min(320, math.floor(W * 0.4))
		if l.Phone then
			place(ui.PlayersTitle, 4, y, W - 8, 24)
			y += 26
			place(ui.PlayerSearch.Instance, 0, y, W, 40)
			y += 46
		else
			place(ui.PlayersTitle, 4, y + 8, W - searchW - 16, 24)
			place(ui.PlayerSearch.Instance, W - searchW, y, searchW, 40)
			y += 46
		end
		place(ui.Rule, 4, y, W - 8, 20)
		y += 24
		place(ui.Players.Instance, 0, y, W, H - y)
	end
	-- Session
	local compact = l.Phone or W < 860
	ui.Compact = compact
	if not compact then
		ui.PhoneTabs.Instance.Visible = false
		local centerW = W >= 1100 and 240 or 214
		local gap = 10
		local colW = math.floor((W - centerW - gap * 2) / 2)
		local giveH = math.max(210, math.floor(H * 0.4))
		ui.Give.Frame.Visible, ui.Get.Frame.Visible, ui.Picker.Frame.Visible = true, true, true
		place(ui.Give.Frame, 0, 0, colW, giveH)
		layoutColumn(ui.Give, colW, giveH, false)
		place(ui.Picker.Frame, 0, giveH + gap, colW, H - giveH - gap)
		layoutPicker(ui.Picker, colW, H - giveH - gap, false)
		place(ui.Center.Frame, colW + gap, 0, centerW, H)
		ui.Center.Unready.Instance.Visible = ui.Center.ShowUnready == true
		layoutCenter(ui.Center, centerW, H, "column")
		place(ui.Get.Frame, colW + gap + centerW + gap, 0, W - (colW + gap + centerW + gap), H)
		layoutColumn(ui.Get, W - (colW + gap + centerW + gap), H, false)
	else
		local landscape = l.Landscape == true or (W > H * 1.6)
		local tabsH = landscape and 36 or 40
		local barH = landscape and 58 or 128
		ui.PhoneTabs.Instance.Visible = true
		place(ui.PhoneTabs.Instance, 0, 0, W, tabsH)
		local top = tabsH + 6
		local contentH = H - top - barH - 6
		local tab = st.PhoneTab
		ui.Give.Frame.Visible = tab == "give"
		ui.Get.Frame.Visible = tab == "get"
		ui.Picker.Frame.Visible = tab == "add"
		place(ui.Give.Frame, 0, top, W, contentH)
		layoutColumn(ui.Give, W, contentH, true)
		place(ui.Get.Frame, 0, top, W, contentH)
		layoutColumn(ui.Get, W, contentH, true)
		place(ui.Picker.Frame, 0, top, W, contentH)
		layoutPicker(ui.Picker, W, contentH, true)
		place(ui.Center.Frame, 0, H - barH, W, barH)
		ui.Center.Unready.Instance.Visible = ui.Center.ShowUnready == true
		layoutCenter(ui.Center, W, barH, landscape and "row" or "bar")
	end
end

------------------------------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------------------------------
local function playerRows(): { any }
	local out = {}
	for _, row in ipairs(st.PlayerRows) do
		local q = st.PlayerQuery
		local name = string.lower(tostring(row.Name or "")) .. " " .. string.lower(tostring(row.Username or ""))
		if q == "" or string.find(name, q, 1, true) then
			table.insert(out, row)
		end
	end
	-- Invited you first, then those you can trade with, then the rest; by name.
	local function rank(row: any): number
		if row.InviteIn then
			return 0
		elseif row.CanInvite then
			return 1
		elseif row.Block == "Sent" or row.Block == "Cooldown" then
			return 2
		end
		return 3
	end
	table.sort(out, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a.Name) < tostring(b.Name)
	end)
	return out
end

local lobbyTicking = false
renderLobby = function()
	if not ui then
		return
	end
	local invites = incoming()
	local changed = #invites ~= #(ui.InviteRows or {})
	ui.InviteRows = invites
	ui.Invites:SetItems(invites)
	ui.Players:SetItems(playerRows())
	local myLevel = (profile() and tonumber(profile().Level)) or 1
	if myLevel < Config.TradeLevel then
		ui.Rule.Text = F("Trading unlocks at level %d. You are level %d.", Config.TradeLevel, myLevel)
		ui.Rule.TextColor3 = P.red
	else
		ui.Rule.Text = T("Nothing moves until both players press READY and then CONFIRM.")
		ui.Rule.TextColor3 = Theme.InkMuted
	end
	if changed then
		relayout()
	end
	-- Timers on the rows (invitation expiry, cooldowns): one 1 Hz refresh while the lobby shows them.
	if not lobbyTicking then
		lobbyTicking = true
		task.spawn(function()
			while win and win.IsOpen and ui and ui.Lobby.Visible do
				local timed = false
				for _, row in ipairs(st.PlayerRows) do
					if row.InviteOut or row.CooldownEndsAt or row.InviteIn then
						timed = true
						break
					end
				end
				if not timed then
					break
				end
				task.wait(1)
				if not (win and win.IsOpen and ui and ui.Lobby.Visible) then
					break
				end
				local expired = false
				for _, row in ipairs(st.PlayerRows) do
					if row.CooldownEndsAt and row.CooldownEndsAt <= os.clock() then
						row.CooldownEndsAt, row.Cooldown = nil, nil
						if row.Block == "Cooldown" then
							row.Block, row.CanInvite = nil, true
						end
						expired = true
					end
					if row.InviteOut and (row.InviteOut.EndsAt or 0) <= os.clock() then
						-- Unanswered: the server starts the same cooldown as for a decline.
						row.InviteOut = nil
						if row.Block == "Sent" then
							row.Block, row.CanInvite = "Cooldown", false
							row.CooldownEndsAt = os.clock() + Rules.InviteCooldown
						end
						expired = true
					end
					if row.InviteIn and (row.InviteIn.EndsAt or 0) <= os.clock() then
						row.InviteIn = nil
						expired = true
					end
				end
				if expired then
					renderLobby()
				else
					ui.Players:Refresh()
				end
			end
			lobbyTicking = false
		end)
	end
end

local function sortPicker(list: { any })
	local field = st.Sort
	local desc = st.Descending
	table.sort(list, function(a, b)
		local x, y
		if field == "value" then
			x, y = a.Value, b.Value
		elseif field == "newest" then
			x, y = a.Time, b.Time
		else
			x, y = Rules.RarityRank[a.Rarity] or 0, Rules.RarityRank[b.Rarity] or 0
			if x == y then
				x, y = a.Value, b.Value
			end
		end
		if x ~= y then
			if desc then
				return x > y
			end
			return x < y
		end
		return a.Key < b.Key
	end)
end
local function pickerItems(): { any }
	local p = profile()
	if not p then
		return {}
	end
	local offer = myOffer()
	local query, rarities = st.Query, st.Rarities
	local filtered = next(rarities) ~= nil
	local function passes(name: string, rarity: string, extra: string): boolean
		if filtered and not rarities[rarity] then
			return false
		end
		if query ~= "" then
			local hay = string.lower(name .. " " .. extra .. " " .. rarity .. " " .. T(string.upper(rarity)))
			if not string.find(hay, query, 1, true) then
				return false
			end
		end
		return true
	end
	local list = {}
	if st.Tab == "dogs" then
		for uid, d in pairs(p.Dogs or {}) do
			local rarity = Rules.DogRarity(d)
			local name = tostring(d.DisplayName or d.DogId)
			if passes(name, rarity, tostring(d.Variant or "")) then
				local reason = dogReason(p, d)
				local value = Rules.DogValue(d)
				local card = cardFor("Dog", d, uid)
				card.Stats = { { Text = "≈" .. short(value) } }
				card.Selected = table.find(offer.Dogs, uid) ~= nil
				card.Disabled = reason ~= nil and not card.Selected
				card.DisabledReason = reason
				card.Locked = d.Locked == true
				table.insert(list, { Key = uid, Kind = "Dog", Uids = { uid }, Value = value, Rarity = rarity, Time = tonumber(d.CreatedAt) or 0, Card = card })
			end
		end
	else
		local groups = {}
		for uid, x in pairs(p.Items or {}) do
			local rarity = Rules.ItemRarity(x)
			local name = tostring(x.DisplayName or x.ItemId)
			if passes(name, rarity, mutationOf(x)) then
				local reason = itemReason(p, x)
				local groupKey = Rules.GroupKey(x) .. (reason and "|x" or "")
				local group = groups[groupKey]
				if not group then
					group = { Key = groupKey, Kind = "Item", Uids = {}, Values = {}, Value = 0, Rarity = rarity, Time = 0, Rec = x, Reason = reason }
					groups[groupKey] = group
					table.insert(list, group)
				end
				local value = Rules.ItemValue(x)
				table.insert(group.Uids, uid)
				group.Values[uid] = value
				group.Value = math.max(group.Value, value)
				group.Time = math.max(group.Time, tonumber(x.FoundAt) or 0)
			end
		end
		for _, group in ipairs(list) do
			-- The cheapest copy first: + gives that one, your best copies stay.
			table.sort(group.Uids, function(a, b)
				if group.Values[a] ~= group.Values[b] then
					return group.Values[a] < group.Values[b]
				end
				return a < b
			end)
			local inOffer = 0
			for _, uid in ipairs(group.Uids) do
				if table.find(offer.Items, uid) then
					inOffer += 1
				end
			end
			local card = cardFor("Item", group.Rec, group.Key)
			local count = #group.Uids
			if count == 1 then
				card.Stats = { { Text = weightText(group.Rec.WeightKg) }, { Text = "≈" .. short(group.Value) } }
			else
				card.Stats = { { Text = "≈" .. short(group.Value) } }
				if group.Reason then
					card.Count = count
				end
			end
			card.Selected = inOffer > 0
			card.Disabled = group.Reason ~= nil
			card.DisabledReason = group.Reason
			group.Card = card
			if count > 1 and not group.Reason then
				group.Stepper = { In = inOffer, Of = count }
			end
		end
	end
	sortPicker(list)
	return list
end

local function setStatus(pill: any, ready: boolean, confirmed: boolean, waiting: string)
	if confirmed then
		pill:Set(T("CONFIRMED ✓"), P.green)
	elseif ready then
		pill:Set(T("READY ✓"), P.green)
	else
		pill:Set(waiting, Theme.Colors.secondary, Theme.InkMuted)
	end
end

renderSession = function()
	local t = st.Trade
	if not (ui and t) then
		return
	end
	local myKey, theirKey = key(me()), key(t.Partner)
	local name = nameOf(t.Partner, "?")
	local mine, give = groupsOf(me())
	local theirs, get = groupsOf(t.Partner)
	local offer = myOffer()
	local partnerOffer = serverOffer(t.Partner) or { Cash = 0 }
	-- Columns
	ui.Give.Value.Text = "≈" .. short(give)
	ui.Get.Value.Text = "≈" .. short(get)
	local giveItems, getItems = {}, {}
	for _, group in ipairs(mine) do
		table.insert(giveItems, { Key = group.Key, Kind = group.Kind, Uids = group.Uids, Card = group.Card })
	end
	for _, group in ipairs(theirs) do
		table.insert(getItems, { Key = group.Key, Kind = group.Kind, Uids = group.Uids, Card = group.Card })
	end
	ui.Give.Grid:SetItems(giveItems)
	ui.Get.Grid:SetItems(getItems)
	if ui.Give.CashBox and not ui.Give.CashBox:IsFocused() then
		ui.Give.CashBox.Text = Format.Number(offer.Cash or 0)
	end
	ui.Get.CashLabel.Text = Format.Number(partnerOffer.Cash or 0)
	local ready, theirReady = t.Ready[myKey] == true, t.Ready[theirKey] == true
	local confirmed, theirConfirmed = t.Confirmed[myKey] == true, t.Confirmed[theirKey] == true
	ui.Give.Title.Text = T("YOU GIVE") .. ((ready and not st.Draft) and " ✓" or "")
	ui.Get.Title.Text = F("%s GIVES", string.upper(name)) .. (theirReady and " ✓" or "")
	-- Picker
	ui.Picker.Grid:SetItems(pickerItems())
	ui.Picker.Tabs:SetBadge("dogs", #offer.Dogs > 0 and tostring(#offer.Dogs) or nil)
	ui.Picker.Tabs:SetBadge("items", #offer.Items > 0 and tostring(#offer.Items) or nil)
	ui.PhoneTabs:SetBadge("give", (#offer.Dogs + #offer.Items) > 0 and tostring(#offer.Dogs + #offer.Items) or nil)
	local theirCount = #(partnerOffer.Dogs or {}) + #(partnerOffer.Items or {})
	ui.PhoneTabs:SetBadge("get", theirCount > 0 and tostring(theirCount) or nil)
	-- Value check
	local c = ui.Center
	local fair = Rules.Fairness(give, get)
	c.Give.Text = F("You give ≈ %s", short(give))
	c.Get.Text = F("You get ≈ %s", short(get))
	c.Bar:SetValue(fair.Level == "Empty" and 0.5 or (1 - fair.Share))
	if fair.Level == "Over" then
		c.Bar:SetColor(P.red)
		c.Verdict:Set(T("YOU GIVE MUCH MORE"), P.red)
	elseif fair.Level == "Under" then
		c.Bar:SetColor(P.green)
		c.Verdict:Set(T("YOU GET MUCH MORE"), P.green)
	elseif fair.Level == "Empty" then
		c.Bar:SetColor(Theme.Disabled)
		c.Verdict:Set(T("EMPTY TRADE"), Theme.Colors.secondary, Theme.InkMuted)
	else
		local even = math.abs(fair.Share - 0.5) < 0.17
		c.Bar:SetColor(even and P.green or P.gold)
		c.Verdict:Set(even and T("FAIR TRADE") or T("ROUGHLY FAIR"), even and P.green or P.gold)
	end
	setStatus(c.Mine, ready and not st.Draft, confirmed, T("YOU: NOT READY"))
	setStatus(c.Theirs, theirReady, theirConfirmed, F("%s: WAITING", name))
	local function mark(isReady: boolean, isConfirmed: boolean): string
		return isConfirmed and "✓✓" or isReady and "✓" or "…"
	end
	c.Status.Text = F("You %s · %s %s", mark(ready and not st.Draft, confirmed), name, mark(theirReady, theirConfirmed))
	-- The one big button.
	local state, caption, style = "wait", "", "secondary"
	local empty = (#offer.Dogs + #offer.Items) == 0 and (offer.Cash or 0) == 0 and theirCount == 0 and (partnerOffer.Cash or 0) == 0
	local reviewLeft = st.ReviewUntil - os.clock()
	local confirmLeft = st.ConfirmUntil - os.clock()
	if t.Committing then
		state, caption = "busy", T("TRADING…")
	elseif st.Draft or st.Sending then
		state, caption = "saving", T("SAVING…")
	elseif empty then
		state, caption = "empty", T("ADD SOMETHING")
	elseif not ready then
		if reviewLeft > 0 then
			state, caption = "review", T("CHECK THE OFFER…")
		else
			state, caption, style = "ready", T("READY"), "gold"
		end
	elseif not theirReady then
		state, caption = "waitReady", F("WAITING FOR %s", string.upper(name))
	elseif confirmLeft > 0 then
		state, caption = "countdown", T("SAFETY CHECK…")
	elseif not confirmed then
		state, caption, style = "confirm", T("HOLD TO CONFIRM"), "success"
	elseif not theirConfirmed then
		state, caption = "waitConfirm", F("WAITING FOR %s", string.upper(name))
	else
		state, caption = "busy", T("TRADING…")
	end
	c.State = state
	c.Main.Props.Hold = state == "confirm" and 1 or nil
	c.Main:SetText(caption)
	c.Main:SetStyle(style)
	c.Main:SetDisabled(state ~= "ready" and state ~= "confirm")
	c.Main:SetBusy(state == "busy")
	local showUnready = ready and not confirmed and not t.Committing
	if c.ShowUnready ~= showUnready then
		c.ShowUnready = showUnready
		relayout()
	end
	c.Unready:SetDisabled(not showUnready)
	if state == "countdown" then
		c.Countdown:SetEndsAt(Kit.Now() + confirmLeft)
	else
		c.Countdown:SetEndsAt(nil)
	end
	if state == "review" then
		local token = {}
		st.ReviewToken = token
		task.delay(reviewLeft + 0.05, function()
			if st.ReviewToken == token then
				render()
			end
		end)
	end
	win:SetTitle(T("TRADE"), F("Trading with %s", name))
end

render = function()
	if not (win and ui) then
		return
	end
	local inSession = st.Trade ~= nil
	ui.Lobby.Visible = not inSession
	ui.Session.Visible = inSession
	if inSession then
		renderSession()
	else
		win:SetTitle(T("TRADE"), T("Swap dogs, finds and coins with players here"))
		renderLobby()
	end
end

------------------------------------------------------------------------------------------------
-- Data in
------------------------------------------------------------------------------------------------
applyPlayers = function(rows: any, at: number)
	if type(rows) ~= "table" or at < st.PlayersAt then
		return
	end
	st.PlayersAt = at
	local now = os.clock()
	for _, row in ipairs(rows) do
		if row.InviteIn then
			row.InviteIn.EndsAt = now + (tonumber(row.InviteIn.In) or 0)
		end
		if row.InviteOut then
			row.InviteOut.EndsAt = now + (tonumber(row.InviteOut.In) or 0)
		end
		if row.Cooldown then
			row.CooldownEndsAt = now + (tonumber(row.Cooldown) or 0)
		end
	end
	st.PlayerRows = rows
	if banner and banner.Kind == "invite" and banner.Row then
		local still = false
		for _, row in ipairs(rows) do
			if row.Id == banner.Row.Id and row.InviteIn then
				still = true
			end
		end
		if not still then
			hideBanner()
		end
	end
end

applyTrade = function(view: any, at: number, authoritative: boolean): boolean
	local current = st.Trade
	if view then
		if st.Ended[view.Id] then
			return false
		end
		if current and current.Id == view.Id then
			local seq, held = tonumber(view.Seq) or 0, tonumber(current.Seq) or 0
			if seq < held or (seq == held and (tonumber(view.Now) or 0) < (tonumber(current.Now) or 0)) then
				return false
			end
		end
		if not authoritative and not current and at < st.TradeAt then
			return false
		end
	else
		if not current then
			st.TradeAt = math.max(st.TradeAt, at)
			return false
		end
		if not authoritative and at <= st.TradeAt then
			return false -- a snapshot as old as our news: keep the session until a newer one ends it
		end
	end
	if view and current and current.Id ~= view.Id then
		st.Draft = nil
	end
	if not view then
		st.Draft = nil
	end
	st.Trade = view
	st.TradeAt = math.max(st.TradeAt, at)
	if view then
		st.ReviewUntil = os.clock() + (tonumber(view.ReviewIn) or 0)
		local confirmIn = tonumber(view.ConfirmIn)
		st.ConfirmUntil = confirmIn and (os.clock() + confirmIn) or 0
	end
	return true
end

local function onSnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	st.Snapshot = snapshot
	local at = tonumber(snapshot.Now) or -1
	applyTrade(snapshot.Trade, at, false)
	applyPlayers(snapshot.Players, at)
	if win and win.IsOpen then
		render()
	end
end

-- DogEconomyPush 'Trade': {Event, Trade, Players, Now}.
local function onTradePush(data: any)
	if type(data) ~= "table" then
		return
	end
	local event = type(data.Event) == "table" and data.Event or {}
	local at = tonumber(data.Now) or -1
	local names = type(event.Names) == "table" and event.Names or {}
	local function who(id: any): string
		return names[key(id)] or nameOf(id, "?")
	end
	local kind = event.Kind
	local ending = kind == "Cancelled" or kind == "Completed" or kind == "Left" or kind == "Expired"
	if ending and event.Trade then
		local count = 0
		for _ in pairs(st.Ended) do
			count += 1
		end
		if count > 64 then
			st.Ended = {}
		end
		st.Ended[event.Trade] = true
	end
	local previous = st.Trade
	applyPlayers(data.Players, at)
	applyTrade(data.Trade, at, true)
	local open = win and win.IsOpen
	local mine = me()
	if kind == "Started" then
		local partner = event.From == mine and event.To or event.From
		toastOnce(F("Trading with %s", who(partner)), "success", 1)
		hideBanner()
		-- Phones start on ADD: the offer is empty, picking is the first step.
		st.PhoneTab = "add"
		if ui then
			ui.PhoneTabs:Select("add", true)
			relayout()
		end
		if not open and event.By ~= mine then
			-- My invitation was accepted: open the window unless another menu is in use.
			local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
			local main = gui and gui:FindFirstChild("ScreenGui")
			if main and main:GetAttribute("OpenMenu") == nil then
				S.Open()
			else
				showBanner("started", { Id = partner, Name = who(partner) })
			end
		end
	elseif kind == "Changed" then
		if event.By ~= mine then
			local action = event.Action
			if action == "Offer" then
				toastOnce(F("%s changed the offer. Check it again.", who(event.By)), "info", 3)
				if ui and ui.Get then
					local stroke = ui.Get.Frame:FindFirstChildWhichIsA("UIStroke")
					if stroke and not reducedFX() then
						stroke.Color = P.gold
						stroke.Thickness = 4
						Kit.Motion.Tween(stroke, 0.6, { Color = THEIRS, Thickness = 2 })
					end
				end
			elseif action == "Ready" then
				toastOnce(F("%s is ready", who(event.By)), "info", 2)
			elseif action == "Confirm" then
				toastOnce(F("%s confirmed. Your turn!", who(event.By)), "success", 2)
			end
		end
	elseif kind == "Cancelled" then
		if event.By ~= mine and previous then
			toastOnce(F("%s cancelled the trade", who(event.By)), "warn", 1)
		elseif previous then
			toastOnce(T("Trade cancelled"), "info", 1)
		end
		if banner and banner.Kind == "started" then
			hideBanner()
		end
	elseif kind == "Left" then
		if previous then
			local other = (event.By and event.By ~= mine) and event.By or previous.Partner
			toastOnce(F("%s left the server. The trade was cancelled.", who(other)), "warn", 1)
		end
	elseif kind == "Expired" then
		if previous then
			toastOnce(T("The trade was idle too long and was cancelled"), "warn", 1)
		end
	elseif kind == "Completed" then
		toastOnce(T("Trade complete! Check your new dogs and finds."), "success", 1)
		celebrate()
		task.spawn(function()
			Net.Snapshot(0)
		end)
	elseif kind == "Failed" then
		serverToast(event.Message, "error")
	elseif kind == "InviteGone" then
		if event.From == mine then
			local reason = event.Reason
			if reason == "Declined" then
				toastOnce(F("%s declined your invitation", who(event.To)), "warn", 1)
			elseif reason == "Expired" then
				toastOnce(F("%s did not answer", who(event.To)), "info", 1)
			elseif reason == "Busy" and not st.Trade then
				toastOnce(F("%s started another trade", who(event.To)), "info", 1)
			end
		elseif event.To == mine and banner and banner.Kind == "invite" and banner.Row and banner.Row.InviteIn and banner.Row.InviteIn.Id == event.Invite then
			hideBanner()
			local upcoming = incoming()[1]
			if upcoming and not (win and win.IsOpen) then
				showBanner("invite", upcoming)
			end
		end
	end
	if open then
		render()
	end
end

-- DogEconomyPush 'TradeInvite': an incoming invitation. A popup, never a forced window.
local function onInvitePush(data: any)
	if type(data) ~= "table" or data.To ~= me() then
		return
	end
	local name = (type(data.Names) == "table" and data.Names[key(data.From)]) or nameOf(data.From, "?")
	local row: any = nil
	for _, r in ipairs(st.PlayerRows) do
		if r.Id == data.From then
			row = r
		end
	end
	row = row or { Id = data.From, Name = name }
	row.Name = row.Name or name
	row.Level = row.Level or data.FromLevel
	row.InviteIn = row.InviteIn or { Id = data.Invite }
	row.InviteIn.Id = data.Invite
	row.InviteIn.EndsAt = os.clock() + (tonumber(data.In) or 45)
	local known = false
	for _, r in ipairs(st.PlayerRows) do
		if r == row then
			known = true
		end
	end
	if not known then
		table.insert(st.PlayerRows, row)
	end
	if win and win.IsOpen then
		if not st.Trade then
			toastOnce(F("%s wants to trade", name), "info", 2)
			render()
		end
		return
	end
	if st.Trade then
		return
	end
	showBanner("invite", row)
end

------------------------------------------------------------------------------------------------
-- Window life
------------------------------------------------------------------------------------------------
local openToken = 0
function S._opened()
	openToken += 1
	local token = openToken
	hideBanner()
	local cached = Net.Cached()
	if cached then
		onSnapshot(cached)
	end
	render()
	relayout()
	task.spawn(function()
		local snapshot = Net.Snapshot(1)
		if snapshot and token == openToken and win.IsOpen then
			onSnapshot(snapshot)
		end
		-- While open: a light refresh for anything a push missed (shared cache with other screens).
		while token == openToken and win.IsOpen do
			task.wait(10)
			if token ~= openToken or not win.IsOpen then
				break
			end
			Net.Snapshot(8)
		end
	end)
end
function S._closed()
	openToken += 1
	if ui and ui.Give and ui.Give.CashBox then
		ui.Give.CashBox:ReleaseFocus()
	end
end

local function rebuildIfLanguageChanged()
	if win and ui and ui.Lang ~= Kit.Lang() and not win.IsOpen then
		-- Grids first: their cards hand the 3D previews back to the kit cache.
		for _, grid in ipairs({ ui.Give.Grid, ui.Get.Grid, ui.Picker.Grid, ui.Players, ui.Invites }) do
			grid:Destroy()
		end
		win:Destroy()
		win, ui = nil, nil
	end
end

local started = false
-- Called at start by ScreenGui.TradeClient (and by Open): subscribes to the pushes once.
function S.Start()
	if started then
		return
	end
	started = true
	Net.OnPush("Trade", onTradePush)
	Net.OnPush("TradeInvite", onInvitePush)
	Net.Changed:Connect(onSnapshot)
	local cached = Net.Cached()
	if cached then
		onSnapshot(cached)
	end
end

-- GUIIntegration.kitScreens: N.OpenPage('Trade') / N.OpenScreen('Trade') / DogEconomyOpen 'Trade'.
function S.Open(_arg: any?)
	S.Start()
	rebuildIfLanguageChanged()
	if not win then
		build()
		relayout()
	end
	if win.IsOpen then
		render()
		return
	end
	render() -- the right view (lobby / session) from the first frame
	win:Open()
end

function S.Close()
	if win and win.IsOpen then
		win:Close("api")
	end
end

-- For tests and debugging.
S._State = st
S._Rules = Rules
function S._UI(): any
	return ui
end
function S._Banner(): any
	return banner
end

return S
