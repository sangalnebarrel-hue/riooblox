-- ArtifactPanel: the artifact slots of ONE dog (equip / replace / remove), for any screen that
-- shows a dog. Artifacts boost only the dog they are on; slots follow the dog's rank
-- (Common 1, Rare 2, Epic 2, Legendary 3, Mythic 3, Secret 4). Everything is server-validated
-- (Features.Equipment actions EquipArtifact / UnequipArtifact).
--
--   local handle = ArtifactPanel.Mount(parent, {DogUid = uid, Net = Modules.Net})
--   handle.Update(snapshot)   -- optional: the panel also follows Net.Changed by itself
--   handle.Destroy()
-- props: Pending = artifact uid to place (slots then show PLACE HERE), OnDone = fn() after a
-- successful equip in that mode, ZIndex.
--   ArtifactPanel.OpenWindow(dogUid, {Pending?})  a (stacked) kit window around the panel
--   ArtifactPanel.PickDog(artifactUid?)           choose a dog, then a slot, for one artifact
--                                                 (no uid: choose a dog to manage its artifacts)
local RS = game:GetService("ReplicatedStorage")

local Shared = require(script.Parent.Shared)
local Kit = Shared.Kit
local E = Shared.E
local T = Shared.T
local Totals = require(RS.DogEconomy.BonusSources.Artifacts)

local ArtifactPanel = {}

-- The artifact in slot `slot` of a dog (snapshot view), and every artifact of that dog.
local function onDog(data: any, dogUid: string): ({ [number]: any }, number)
	local bySlot, n = {}, 0
	for _, entry in ipairs(data and data.Artifacts or {}) do
		if entry.DogUid == dogUid and type(entry.Slot) == "number" then
			bySlot[entry.Slot] = entry
			n += 1
		end
	end
	return bySlot, n
end

local function dogNames(snapshot: any): { [string]: string }
	local names = {}
	local profile = snapshot and snapshot.Profile
	for uid, dog in pairs(profile and profile.Dogs or {}) do
		names[uid] = Shared.DogName(dog)
	end
	return names
end

-- Equips artifactUid on dogUid's slot after confirming anything that gets replaced or moved.
-- Yields. Returns true when the server equipped it.
function ArtifactPanel.Equip(snapshot: any, artifactUid: string, dogUid: string, slot: number, net: any?): boolean
	local data = Shared.Data(snapshot)
	local entry = Shared.Find(data, artifactUid)
	local dog = Shared.Dog(snapshot, dogUid)
	if not entry or not dog then
		Kit.Toast(T("That artifact or dog is no longer available.", "Этот артефакт или собака больше недоступны."), { Kind = "warn", NoTranslate = true })
		return false
	end
	local bySlot = onDog(data, dogUid)
	local occupant = bySlot[slot]
	if occupant and occupant.Uid == artifactUid then
		Kit.Toast(T("Already in this slot.", "Уже в этом слоте."), { Kind = "info", NoTranslate = true })
		return false
	end
	local newName = Shared.Name(E.Def(entry.Id))
	local lines, cards = {}, {}
	if occupant then
		local oldName = Shared.Name(E.Def(occupant.Id))
		table.insert(lines, oldName .. T(" goes back to your bag.", " вернётся в сумку."))
		table.insert(cards, Shared.Card(occupant))
	end
	if entry.DogUid and entry.DogUid ~= dogUid then
		local from = Shared.Dog(snapshot, entry.DogUid)
		table.insert(lines, newName .. T(" moves from ", " перейдёт от ") .. Shared.DogName(from) .. ".")
	elseif entry.DogUid == dogUid and entry.Slot then
		table.insert(lines, newName .. T(" moves from slot ", " перейдёт из слота ") .. tostring(entry.Slot) .. ".")
	end
	if #lines > 0 then
		table.insert(cards, 1, Shared.Card(entry))
		local title = occupant and (T("REPLACE ", "ЗАМЕНИТЬ ") .. string.upper(Shared.Name(E.Def(occupant.Id))) .. "?")
			or (T("MOVE ", "ПЕРЕНЕСТИ ") .. string.upper(newName) .. "?")
		local ok = Kit.Confirm(title, table.concat(lines, " ") .. T(" Nothing is lost.", " Ничего не теряется."), {
			NoTranslate = true,
			Cards = cards,
			CardKind = "Item",
			ConfirmText = occupant and Shared.W("REPLACE_HERE") or T("MOVE", "ПЕРЕНЕСТИ"),
			CancelText = Shared.W("CANCEL"),
			Accent = Shared.Colors.Artifact,
		}):Await()
		if not ok then
			return false
		end
	end
	local requestOk = Shared.Request("EquipArtifact", { Uid = artifactUid, DogUid = dogUid, Slot = slot }, {
		Success = newName .. T(" now boosts ", " теперь усиливает ") .. Shared.DogName(dog),
	})
	local _ = net
	return requestOk
end

function ArtifactPanel.Mount(parent: GuiObject, props: any): any
	local p = props or {}
	assert(typeof(parent) == "Instance" and parent:IsA("GuiObject"), "ArtifactPanel.Mount: parent must be a GuiObject")
	assert(type(p.DogUid) == "string", "ArtifactPanel.Mount: DogUid required")
	local net = p.Net or Shared.Net
	local self: any = { DogUid = p.DogUid, Pending = p.Pending, Maid = Kit.Maid.new(), Destroyed = false }
	local z = math.max(3, (p.ZIndex or parent.ZIndex or 1) + 1)

	local root = Kit.New("Frame", { Name = "ArtifactPanel", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, parent)
	self.Root = root
	self.Maid:Give(root)
	local header = Kit.New("Frame", { Name = "Header", BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, ZIndex = z }, root)
	Kit.Corner(header, 14)
	Kit.Stroke(header, Shared.Colors.Artifact, 2, 0.2)
	local dogHolder = Kit.New("Frame", { Name = "Dog", BackgroundTransparency = 1, ZIndex = z + 1 }, header)
	local dogSlot = Kit.Preview.Slot(dogHolder)
	self.Maid:Give(function()
		dogSlot:Destroy()
	end)
	local title = Kit.Text(header, { Name = "DogName", TextSize = 20, Scaled = true, MinTextSize = 11, ZIndex = z + 1 })
	local tagRow = Kit.New("Frame", { Name = "Tags", BackgroundTransparency = 1, ZIndex = z + 1 }, header)
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tagRow)
	local rarityTag = Kit.RarityTag(tagRow, "Common", { Height = 20, TextSize = 12, LayoutOrder = 1, ZIndex = z + 2 })
	local slotsPill = Kit.Pill(tagRow, { Name = "Slots", Height = 20, TextSize = 12, Color = Shared.Colors.Artifact, LayoutOrder = 2, ZIndex = z + 2, NoTranslate = true })
	local summary = Kit.Text(header, { Name = "Summary", TextSize = 14, Color = Kit.Theme.InkMuted, Scaled = true, MinTextSize = 9, ZIndex = z + 1, NoTranslate = true })
	local note = Kit.Text(root, { Name = "Note", TextSize = 14, Color = Kit.Theme.Ink, Scaled = true, MinTextSize = 9, ZIndex = z, NoTranslate = true })
	local list = Kit.New("ScrollingFrame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		ZIndex = z,
	}, root)
	self.List = list

	-- Four slot tiles, built once.
	local tiles = {}
	for i = 1, E.MaxDogSlots do
		local tile: any = {}
		local frame = Kit.New("Frame", { Name = "Slot" .. i, BackgroundColor3 = Kit.Theme.White, BorderSizePixel = 0, ZIndex = z + 1 }, list)
		Kit.Corner(frame, 14)
		tile.Stroke = Kit.Stroke(frame, Kit.Theme.Colors.edge, 2, 0.3)
		tile.Frame = frame
		tile.Label = Kit.Text(frame, { Name = "SlotLabel", TextSize = 13, Color = Kit.Theme.InkMuted, ZIndex = z + 2, NoTranslate = true })
		tile.Holder = Kit.New("Frame", { Name = "Preview", BackgroundTransparency = 1, ZIndex = z + 2 }, frame)
		tile.Preview = Kit.Preview.Slot(tile.Holder)
		tile.Plus = Kit.Text(frame, { Name = "Plus", Text = "+", TextSize = 46, AlignX = "Center", Color = Shared.Colors.Artifact, ZIndex = z + 2, NoTranslate = true })
		tile.Name = Kit.Text(frame, { Name = "PieceName", TextSize = 16, Scaled = true, MinTextSize = 9, AlignX = "Center", ZIndex = z + 2, NoTranslate = true })
		tile.Stat = Kit.Text(frame, { Name = "Stat", TextSize = 15, Scaled = true, MinTextSize = 9, AlignX = "Center", Font = "numeric", ZIndex = z + 2, NoTranslate = true })
		tile.Primary = Kit.Button(frame, { Name = "Primary", Text = "", Style = "primary", TextSize = 15, ZIndex = z + 3, NoTranslate = true })
		tile.Secondary = Kit.Button(frame, { Name = "Secondary", Text = Shared.W("REMOVE"), Style = "secondary", TextSize = 15, ZIndex = z + 3, NoTranslate = true })
		tile.Veil = Kit.New("Frame", { Name = "LockedVeil", BackgroundColor3 = Kit.Theme.SurfaceAlt, BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = z + 4 }, frame)
		Kit.Corner(tile.Veil, 14)
		tile.LockText = Kit.Text(tile.Veil, { Name = "Lock", TextSize = 14, Scaled = true, MinTextSize = 9, Wrap = true, AlignX = "Center", Color = Kit.Theme.InkMuted, Position = UDim2.new(0, 8, 0.25, 0), Size = UDim2.new(1, -16, 0.5, 0), ZIndex = z + 5, NoTranslate = true })
		self.Maid:Give(function()
			tile.Preview:Destroy()
		end)
		self.Maid:Give(tile.Primary)
		self.Maid:Give(tile.Secondary)
		tiles[i] = tile
	end
	self.Tiles = tiles
	self.Header, self.Title, self.Summary, self.Note, self.SlotsPill = header, title, summary, note, slotsPill

	local function layout()
		local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
		if w < 2 then
			return
		end
		local compact = w < 520 or h < 300
		local headerH = compact and 56 or 72
		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.new(1, 0, 0, headerH)
		local s = headerH - 10
		dogHolder.Position = UDim2.fromOffset(6, 5)
		dogHolder.Size = UDim2.fromOffset(s, s)
		local x = s + 14
		title.Position = UDim2.fromOffset(x, 4)
		title.Size = UDim2.new(1, -(x + 8), 0, compact and 20 or 24)
		tagRow.Position = UDim2.fromOffset(x, compact and 24 or 30)
		tagRow.Size = UDim2.new(1, -(x + 8), 0, 20)
		summary.Position = UDim2.fromOffset(x, compact and 40 or 50)
		summary.Size = UDim2.new(1, -(x + 8), 0, compact and 14 or 18)
		note.Position = UDim2.fromOffset(4, headerH + 4)
		note.Size = UDim2.new(1, -8, 0, 18)
		local top = headerH + 26
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 0, 1, -top)
		local viewH = h - top
		local cols = w >= 700 and 4 or (w >= 330 and 2 or 1)
		local gap = 10
		local tileW = math.floor((w - 8 - gap * (cols - 1)) / cols)
		local rows = math.ceil(#tiles / cols)
		local tileH = math.floor(math.clamp(rows == 1 and viewH - 4 or (viewH - gap) / 2, 150, 230))
		for i, tile in ipairs(tiles) do
			local c = (i - 1) % cols
			local r = math.floor((i - 1) / cols)
			tile.Frame.Position = UDim2.fromOffset(c * (tileW + gap), r * (tileH + gap))
			tile.Frame.Size = UDim2.fromOffset(tileW, tileH)
			local pad = 8
			tile.Label.Position = UDim2.fromOffset(pad, 4)
			tile.Label.Size = UDim2.new(1, -pad * 2, 0, 18)
			local buttonH = 40
			local textH = 20
			local previewS = math.max(30, math.min(tileW - pad * 2, tileH - 22 - textH * 2 - buttonH - pad * 2 - 4))
			tile.Holder.Position = UDim2.new(0.5, -previewS / 2, 0, 22)
			tile.Holder.Size = UDim2.fromOffset(previewS, previewS)
			tile.Plus.Position = UDim2.new(0, 0, 0, 22)
			tile.Plus.Size = UDim2.new(1, 0, 0, previewS)
			local y = 22 + previewS + 2
			tile.Name.Position = UDim2.fromOffset(pad, y)
			tile.Name.Size = UDim2.new(1, -pad * 2, 0, textH)
			tile.Stat.Position = UDim2.fromOffset(pad, y + textH)
			tile.Stat.Size = UDim2.new(1, -pad * 2, 0, textH)
			local by = tileH - pad - buttonH
			if tile.Secondary.Instance.Visible then
				local half = math.floor((tileW - pad * 2 - 6) / 2)
				tile.Primary.Instance.Position = UDim2.fromOffset(pad, by)
				tile.Primary.Instance.Size = UDim2.fromOffset(half, buttonH)
				tile.Secondary.Instance.Position = UDim2.fromOffset(pad + half + 6, by)
				tile.Secondary.Instance.Size = UDim2.fromOffset(half, buttonH)
			else
				tile.Primary.Instance.Position = UDim2.fromOffset(pad, by)
				tile.Primary.Instance.Size = UDim2.fromOffset(tileW - pad * 2, buttonH)
			end
		end
		list.CanvasSize = UDim2.fromOffset(0, rows * (tileH + gap) - gap + 4)
	end
	self.Maid:Give(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))

	local function render()
		if self.Destroyed then
			return
		end
		local snapshot = self.Snapshot
		local data = Shared.Data(snapshot)
		local dog = Shared.Dog(snapshot, self.DogUid)
		if not dog then
			title.Text = T("This dog is no longer in your team", "Этой собаки больше нет в твоей команде")
			summary.Text = T("Its artifacts went back to your bag.", "Её артефакты вернулись в сумку.")
			note.Text = ""
			for _, tile in ipairs(tiles) do
				tile.Frame.Visible = false
			end
			return
		end
		title.Text = Shared.DogName(dog)
		dogSlot:Show({ Kind = "Dog", DogId = dog.DogId, Variant = dog.Variant })
		rarityTag:SetRarity(dog.Rarity or "Common")
		local slots = Shared.DogSlots(dog)
		local bySlot, used = onDog(data, self.DogUid)
		slotsPill:Set(used .. " / " .. slots .. T(" ARTIFACT SLOTS", " СЛОТОВ АРТЕФАКТОВ"), Shared.Colors.Artifact)
		-- What this dog gets (per-dog caps applied, same numbers as the server).
		local parts = {}
		local profile = snapshot.Profile
		if type(profile) == "table" then
			local totals = Totals.Totals(profile, dog)
			for _, stat in ipairs(E.ArtifactStats) do
				if totals[stat] and totals[stat] > 0 then
					table.insert(parts, Shared.StatLine(stat, totals[stat]))
				end
			end
		end
		summary.Text = #parts > 0 and (T("THIS DOG: ", "ЭТОЙ СОБАКЕ: ") .. table.concat(parts, " · "))
			or T("No artifacts yet: add one to boost this dog.", "Артефактов пока нет: добавь, чтобы усилить собаку.")
		local pending = self.Pending and Shared.Find(data, self.Pending)
		if self.Pending and not pending then
			self.Pending = nil
		end
		if pending then
			note.Text = T("Choose a slot for ", "Выбери слот для ") .. Shared.Name(E.Def(pending.Id))
			note.TextColor3 = Shared.Colors.Artifact:Lerp(Kit.Theme.Ink, 0.3)
		else
			note.Text = T("Artifacts boost ONLY this dog. Better dogs have more slots.", "Артефакты усиливают ТОЛЬКО эту собаку. У лучших собак больше слотов.")
			note.TextColor3 = Kit.Theme.Ink
		end
		for i, tile in ipairs(tiles) do
			tile.Frame.Visible = true
			tile.Label.Text = T("SLOT ", "СЛОТ ") .. i
			local entry = bySlot[i]
			if i > slots then
				tile.Veil.Visible = true
				tile.LockText.Text = "🔒\n" .. T("Needs a ", "Нужна собака ") .. Shared.SlotUnlock(i) .. T(" dog", "")
				tile.Preview:Show(nil)
				tile.Primary.Instance.Visible = false
				tile.Secondary.Instance.Visible = false
				tile.Stroke.Color = Kit.Theme.Colors.edge
				continue
			end
			tile.Veil.Visible = false
			tile.Primary.Instance.Visible = true
			if entry then
				local def = E.Def(entry.Id)
				tile.Preview:Show({ Kind = "Equipment", Id = entry.Id })
				tile.Plus.Visible = false
				tile.Name.Text = Shared.Name(def)
				tile.Name.TextColor3 = Kit.Theme.Ink
				tile.Stat.Text = def and Shared.StatLine(def.Stat, entry.Value or E.Value(entry)) or ""
				tile.Stat.TextColor3 = def and Shared.StatColor(def.Stat):Lerp(Kit.Theme.Ink, 0.3) or Kit.Theme.Ink
				tile.Stroke.Color = Shared.RarityColor(entry.Rarity)
				tile.Stroke.Transparency = 0
				tile.Primary:SetText(pending and Shared.W("REPLACE_HERE") or Shared.W("SWAP"))
				tile.Primary:SetStyle(pending and "gold" or "primary")
				tile.Secondary.Instance.Visible = not pending
			else
				tile.Preview:Show(nil)
				tile.Plus.Visible = true
				tile.Name.Text = Shared.W("EMPTY")
				tile.Name.TextColor3 = Kit.Theme.InkMuted
				tile.Stat.Text = ""
				tile.Stroke.Color = Kit.Theme.Colors.edge
				tile.Stroke.Transparency = 0.3
				tile.Primary:SetText(pending and Shared.W("PLACE") or Shared.W("ADD"))
				tile.Primary:SetStyle(pending and "gold" or "success")
				tile.Secondary.Instance.Visible = false
			end
			tile.Entry = entry
		end
		layout()
	end
	self.Render = render

	local busy = false
	local function slotAction(i: number, secondary: boolean)
		if busy or self.Destroyed then
			return
		end
		local tile = tiles[i]
		local snapshot = self.Snapshot
		busy = true
		if secondary and tile.Entry then
			Shared.Request("UnequipArtifact", { Uid = tile.Entry.Uid }, { Button = tile.Secondary, Success = Shared.Name(E.Def(tile.Entry.Id)) .. T(" is back in your bag", " снова в сумке") })
		elseif self.Pending then
			local placed = ArtifactPanel.Equip(snapshot, self.Pending, self.DogUid, i, net)
			if placed then
				self.Pending = nil
				if p.OnDone then
					task.spawn(p.OnDone)
				end
			end
		else
			ArtifactPanel.Pick(self.DogUid, i)
		end
		busy = false
	end
	for i, tile in ipairs(tiles) do
		tile.Primary:SetOnClick(function()
			slotAction(i, false)
		end)
		tile.Secondary:SetOnClick(function()
			slotAction(i, true)
		end)
	end

	function self.Update(snapshot: any)
		if type(snapshot) == "table" then
			self.Snapshot = snapshot
			render()
		end
	end
	function self.Destroy()
		if self.Destroyed then
			return
		end
		self.Destroyed = true
		self.Maid:Clean()
	end
	self.Maid:Give(net.Changed:Connect(function(snapshot)
		self.Update(snapshot)
	end))
	local cached = net.Cached and net.Cached()
	if cached then
		self.Update(cached)
	end
	task.spawn(function()
		local fresh = net.Snapshot(4)
		if fresh and not self.Destroyed then
			self.Update(fresh)
		end
	end)
	layout()
	return self
end

-- A window around the panel of one dog. Stacked over an open kit window (the shop, a dog page).
function ArtifactPanel.OpenWindow(dogUid: string, opts: any?): any
	local o = opts or {}
	local snapshot = Shared.Net.Cached()
	local dog = Shared.Dog(snapshot, dogUid)
	local win = Kit.Window.new({
		Key = "DogArtifacts",
		Name = "DogArtifacts",
		Title = T("ARTIFACTS · ", "АРТЕФАКТЫ · ") .. Shared.DogName(dog),
		Subtitle = Shared.Scope("Artifact"),
		Accent = Shared.Colors.Artifact,
		Icon = "Dogs",
		Stack = Kit.Window.Top() ~= nil,
		MaxSize = Vector2.new(940, 640),
		NoTranslate = true,
	})
	local handle
	handle = ArtifactPanel.Mount(win.Body, {
		DogUid = dogUid,
		Pending = o.Pending,
		ZIndex = 3,
		OnDone = function()
			win:Close("done")
			if o.OnDone then
				o.OnDone()
			end
		end,
	})
	win.Closed:Connect(function()
		task.defer(function()
			handle.Destroy()
			win:Destroy()
		end)
	end)
	win:Open()
	ArtifactPanel.Window, ArtifactPanel.Handle = win, handle
	return win, handle
end

-- Chooses an artifact from the bag for slot `slot` of a dog (a stacked window).
function ArtifactPanel.Pick(dogUid: string, slot: number): any
	local snapshot = Shared.Net.Cached()
	local dog = Shared.Dog(snapshot, dogUid)
	local filter: string? = nil
	local win = Kit.Window.new({
		Key = "ArtifactPicker",
		Name = "ArtifactPicker",
		Title = T("CHOOSE AN ARTIFACT", "ВЫБЕРИ АРТЕФАКТ"),
		Subtitle = Shared.DogName(dog) .. T(" · slot ", " · слот ") .. slot .. " · " .. Shared.Scope("Artifact"),
		Accent = Shared.Colors.Artifact,
		Icon = "Star",
		Stack = Kit.Window.Top() ~= nil,
		MaxSize = Vector2.new(980, 700),
		NoTranslate = true,
	})
	local body = win.Body
	local options = { { Id = "All", Text = Shared.W("ALL"), NoTranslate = true } }
	for _, stat in ipairs(E.ArtifactStats) do
		table.insert(options, { Id = stat, Text = Shared.StatName(stat), Color = Shared.StatColor(stat), NoTranslate = true })
	end
	local grid
	local function refresh()
		local snap = Shared.Net.Cached()
		local data = Shared.Data(snap)
		local names = dogNames(snap)
		local items = {}
		for _, entry in ipairs(data and data.Artifacts or {}) do
			local def = E.Def(entry.Id)
			local here = entry.DogUid == dogUid and entry.Slot == slot
			if def and not here and (filter == nil or def.Stat == filter) then
				table.insert(items, entry)
			end
		end
		-- Free pieces first, then the strongest.
		table.sort(items, function(a, b)
			local fa, fb = a.DogUid == nil, b.DogUid == nil
			if fa ~= fb then
				return fa
			end
			local ra, rb = E.RarityIndex[a.Rarity] or 0, E.RarityIndex[b.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
			return (a.Value or 0) > (b.Value or 0)
		end)
		grid.Names = names
		grid:SetItems(items)
	end
	local chips = Kit.Chips(body, {
		Name = "StatFilter",
		Options = options,
		Selected = "All",
		AllowNone = false,
		ZIndex = 3,
		OnChange = function(id)
			filter = id ~= "All" and id or nil
			refresh()
		end,
	})
	grid = Kit.CardGrid(body, {
		Name = "Artifacts",
		Kind = "Item",
		ZIndex = 3,
		CardSize = Vector2.new(150, 196),
		Map = function(entry)
			local data = Shared.Card(entry)
			-- Which dog wears it now (choosing it moves it here).
			local name = entry.DogUid and grid and grid.Names and grid.Names[entry.DogUid]
			if name then
				data.Badge = "🐾 " .. Shared.Clip(name, 14)
			end
			return data
		end,
		Empty = {
			Title = T("NO ARTIFACTS HERE", "ЗДЕСЬ НЕТ АРТЕФАКТОВ"),
			Body = T("Open DIG CRATES and RELIC CHESTS in the EQUIPMENT shop at the Paw Market.", "Открывай ЯЩИКИ КОПАТЕЛЯ и СУНДУКИ РЕЛИКВИЙ в магазине экипировки на Лапа-рынке."),
			ActionText = Shared.W("GO_SHOP"),
			NoTranslate = true,
			OnAction = function()
				local ok, screen = pcall(require, script.Parent.EquipmentScreen)
				if ok then
					screen.Open("artifacts")
				end
			end,
		},
		OnClick = function(entry)
			task.spawn(function()
				local placed = ArtifactPanel.Equip(Shared.Net.Cached(), entry.Uid, dogUid, slot)
				if placed then
					win:Close("done")
				end
			end)
		end,
	})
	local function layout(l)
		local chipH = l and l.Phone and 36 or 40
		chips.Instance.Position = UDim2.fromOffset(0, 0)
		chips.Instance.Size = UDim2.new(1, 0, 0, chipH)
		grid.Instance.Position = UDim2.fromOffset(0, chipH + 6)
		grid.Instance.Size = UDim2.new(1, 0, 1, -(chipH + 6))
	end
	win.Resized:Connect(layout)
	layout(win:GetLayout())
	local changed = Shared.Net.Changed:Connect(function()
		if win.IsOpen then
			refresh()
		end
	end)
	win.Closed:Connect(function()
		changed:Disconnect()
		task.defer(function()
			grid:Destroy()
			chips:Destroy()
			win:Destroy()
		end)
	end)
	refresh()
	win:Open()
	ArtifactPanel.Picker = win
	return win
end

-- Choose a dog for one artifact, then its slot (EQUIP ON A DOG in the shop). Without an
-- artifact uid the chosen dog's panel opens for browsing (MANAGE A DOG).
function ArtifactPanel.PickDog(artifactUid: string?, onDone: (() -> ())?): any
	local snapshot = Shared.Net.Cached()
	local data = Shared.Data(snapshot)
	local entry = artifactUid and Shared.Find(data, artifactUid) or nil
	local search = ""
	local win = Kit.Window.new({
		Key = "ArtifactDogPicker",
		Name = "ArtifactDogPicker",
		Title = T("CHOOSE A DOG", "ВЫБЕРИ СОБАКУ"),
		Subtitle = entry and (Shared.Name(E.Def(entry.Id)) .. " · " .. Shared.Scope("Artifact"))
			or T("Pick a dog to see and change its artifacts", "Выбери собаку, чтобы управлять её артефактами"),
		Accent = Shared.Colors.Artifact,
		Icon = "Dogs",
		Stack = Kit.Window.Top() ~= nil,
		MaxSize = Vector2.new(980, 720),
		NoTranslate = true,
	})
	local body = win.Body
	local grid
	local function refresh()
		local snap = Shared.Net.Cached()
		local d = Shared.Data(snap)
		local profile = snap and snap.Profile
		local used = {}
		for _, a in ipairs(d and d.Artifacts or {}) do
			if a.DogUid then
				used[a.DogUid] = (used[a.DogUid] or 0) + 1
			end
		end
		local items = {}
		local needle = string.lower(search)
		for uid, dog in pairs(profile and profile.Dogs or {}) do
			if dog.State ~= "Walking" then
				local name = Shared.DogName(dog)
				if needle == "" or string.find(string.lower(name), needle, 1, true) then
					table.insert(items, { Uid = uid, Dog = dog, Used = used[uid] or 0, Slots = Shared.DogSlots(dog), Name = name })
				end
			end
		end
		table.sort(items, function(a, b)
			local ra, rb = Kit.Theme.RarityOrder(a.Dog.Rarity), Kit.Theme.RarityOrder(b.Dog.Rarity)
			if ra ~= rb then
				return ra > rb
			end
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			return a.Uid < b.Uid
		end)
		grid:SetItems(items)
	end
	local box = Kit.SearchBox(body, {
		Name = "Search",
		Placeholder = T("Search dogs", "Поиск собак"),
		ZIndex = 3,
		OnChange = function(text)
			search = text or ""
			refresh()
		end,
	})
	grid = Kit.CardGrid(body, {
		Name = "Dogs",
		Kind = "Dog",
		ZIndex = 3,
		Key = function(item)
			return item.Uid
		end,
		Map = function(item)
			local full = item.Used >= item.Slots
			return {
				Id = item.Uid,
				Name = item.Name,
				Rarity = item.Dog.Rarity,
				Variant = item.Dog.Variant,
				Preview = { Kind = "Dog", DogId = item.Dog.DogId, Variant = item.Dog.Variant },
				Stats = { { Text = item.Used .. "/" .. item.Slots .. T(" SLOTS", " СЛОТ."), Color = full and Kit.Theme.Colors.muted or Shared.Colors.Artifact } },
				Subtitle = item.Used .. "/" .. item.Slots .. T(" artifact slots used", " слотов занято"),
			}
		end,
		Empty = { Title = T("NO DOGS YET", "СОБАК ПОКА НЕТ"), Body = T("Get a dog from THE DOG line first.", "Сначала возьми собаку на линии THE DOG."), NoTranslate = true },
		OnClick = function(item)
			if not entry then
				ArtifactPanel.OpenWindow(item.Uid)
				return
			end
			ArtifactPanel.OpenWindow(item.Uid, {
				Pending = artifactUid,
				OnDone = function()
					win:Close("done")
					if onDone then
						onDone()
					end
				end,
			})
		end,
	})
	local function layout(l)
		local boxH = l and l.Phone and 40 or 44
		box.Instance.Position = UDim2.fromOffset(0, 0)
		box.Instance.Size = UDim2.new(1, 0, 0, boxH)
		grid.Instance.Position = UDim2.fromOffset(0, boxH + 6)
		grid.Instance.Size = UDim2.new(1, 0, 1, -(boxH + 6))
	end
	win.Resized:Connect(layout)
	layout(win:GetLayout())
	win.Closed:Connect(function()
		task.defer(function()
			grid:Destroy()
			box:Destroy()
			win:Destroy()
		end)
	end)
	refresh()
	win:Open()
	ArtifactPanel.DogPicker = win
	return win
end

return ArtifactPanel
