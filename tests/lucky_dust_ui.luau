--!nocheck
-- LUCKY DUST in the bag, end to end: lune run tests/lucky_dust_ui.luau [layout_dump_dir]
-- Runs the REAL Modules.InventoryScreen with a mock UI kit (instances that keep their properties, signals that fire,
-- a virtual task scheduler and clock) against the REAL server feature Economy.Features.LuckyDust (Rules.Action on an
-- in-memory profile, every reply carrying a fresh snapshot like Runtime.Request). Drives the block DISMANTLE quote
-- card (Common, Legendary Danger hold, pumpkin candy, an expired quote), DISMANTLE ALL, the DUST FORGE (balance,
-- buttons, Legendary hold, storage full), phone layouts, Russian and reduced motion. With a directory argument it
-- also writes the absolute rectangles of the visible page per layout (JSON) for a visual check of the layout.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")

local L = require("./lib/economy_env")
local OUT = process.args[1]

------------------------------------------------------------------------------------------------
-- Virtual clock + scheduler
------------------------------------------------------------------------------------------------
local clock = 1000
local queue = {}
local function schedule(at, co, ...)
	table.insert(queue, { At = at, Co = co, Args = table.pack(...) })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error("task error: " .. tostring(err) .. "\n" .. debug.traceback(co), 0)
	end
end
local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
task.defer = task.spawn
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	schedule(clock + (t or 0), co, ...)
	return co
end
function task.wait(t)
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		return 0
	end
	schedule(clock + (t or 0.03), co)
	coroutine.yield()
	return t
end
local function advance(dt)
	local target = clock + dt
	while true do
		table.sort(queue, function(a, b) return a.At < b.At end)
		local job = queue[1]
		if not job or job.At > target then
			break
		end
		table.remove(queue, 1)
		clock = math.max(clock, job.At)
		if coroutine.status(job.Co) == "suspended" then
			resume(job.Co, table.unpack(job.Args, 1, job.Args.n))
		end
	end
	clock = target
end

------------------------------------------------------------------------------------------------
-- Mock instances
------------------------------------------------------------------------------------------------
local function Signal()
	local s = { Handlers = {} }
	function s:Connect(fn)
		table.insert(self.Handlers, fn)
		local h = self.Handlers
		return { Disconnect = function() local i = table.find(h, fn); if i then table.remove(h, i) end end, Connected = true }
	end
	s.Once = s.Connect
	function s:Fire(...)
		for _, fn in ipairs(table.clone(self.Handlers)) do
			task.spawn(fn, ...)
		end
	end
	function s:Wait() return nil end
	return s
end

local MI = {}
local SIGNALS = { Changed = true, Activated = true, MouseButton1Click = true, MouseEnter = true, MouseLeave = true, InputBegan = true, InputEnded = true, Destroying = true, SelectionGained = true, SelectionLost = true, Focused = true, FocusLost = true }
local DEFAULTS = {
	Visible = true, Size = roblox.UDim2.new(), Position = roblox.UDim2.new(), AnchorPoint = roblox.Vector2.zero, ZIndex = 1,
	Text = "", BackgroundTransparency = 0, TextSize = 14, LayoutOrder = 0, Active = false, Value = 0, TextTransparency = 0,
	Enabled = true, Scale = 1, AbsoluteRotation = 0,
}
local root -- the ScreenGui

local function absRect(inst)
	if inst == nil or inst.__class == "ScreenGui" then
		local s = inst and inst.__p.ScreenSize or roblox.Vector2.new(1280, 720)
		return 0, 0, s.X, s.Y
	end
	local parent = rawget(inst, "__parent")
	local px, py, pw, ph = absRect(parent)
	local size, pos, anchor = inst.__p.Size or DEFAULTS.Size, inst.__p.Position or DEFAULTS.Position, inst.__p.AnchorPoint or DEFAULTS.AnchorPoint
	local w = size.X.Scale * pw + size.X.Offset
	local h = size.Y.Scale * ph + size.Y.Offset
	if inst.__p.AutoW then
		w = inst.__p.AutoW
	end
	local x = px + pos.X.Scale * pw + pos.X.Offset - anchor.X * w
	local y = py + pos.Y.Scale * ph + pos.Y.Offset - anchor.Y * h
	return x, y, w, h
end

function MI.new(class, props, parent)
	local self = { __class = class, __p = {}, __children = {}, __signals = {}, __prop = {}, __attrs = {}, __attrSignals = {} }
	setmetatable(self, MI)
	for k, v in pairs(props or {}) do
		self[k] = v
	end
	if parent then
		self.Parent = parent
	end
	return self
end
MI.__index = function(self, k)
	local p = rawget(self, "__p")
	if k == "ClassName" then return self.__class end
	if k == "Parent" then return rawget(self, "__parent") end
	if k == "AbsoluteSize" then
		local _, _, w, h = absRect(self)
		return roblox.Vector2.new(w, h)
	end
	if k == "AbsolutePosition" then
		local x, y = absRect(self)
		return roblox.Vector2.new(x, y)
	end
	if SIGNALS[k] then
		local s = self.__signals[k]
		if not s then s = Signal(); self.__signals[k] = s end
		return s
	end
	if p[k] ~= nil then return p[k] end
	if MI[k] then return MI[k] end
	if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
	if k == "Name" then return self.__class end
	-- A child by name.
	for _, c in ipairs(self.__children) do
		if c.Name == k then return c end
	end
	return nil
end
MI.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "__parent")
		if old then
			local i = table.find(old.__children, self)
			if i then table.remove(old.__children, i) end
		end
		rawset(self, "__parent", v)
		if v then table.insert(v.__children, self) end
		return
	end
	local before = self.__p[k]
	self.__p[k] = v
	if before ~= v then
		local s = self.__prop[k]
		if s then s:Fire() end
		if k == "Value" and self.__signals.Changed then self.__signals.Changed:Fire(v) end
	end
end
MI.__tostring = function(self) return self.Name end
function MI:GetPropertyChangedSignal(k)
	local s = self.__prop[k]
	if not s then s = Signal(); self.__prop[k] = s end
	return s
end
function MI:FindFirstChild(name)
	for _, c in ipairs(self.__children) do
		if c.Name == name then return c end
	end
	return nil
end
function MI:FindFirstChildWhichIsA(class)
	for _, c in ipairs(self.__children) do
		if c:IsA(class) then return c end
	end
	return nil
end
function MI:FindFirstAncestorWhichIsA(class)
	local p = rawget(self, "__parent")
	while p do
		if p:IsA(class) then return p end
		p = rawget(p, "__parent")
	end
	return nil
end
function MI:IsA(class)
	if class == self.__class or class == "Instance" or class == "GuiObject" and self.__class ~= "ScreenGui" then return true end
	if class == "LayerCollector" and self.__class == "ScreenGui" then return true end
	if class == "GuiButton" and (self.__class == "TextButton" or self.__class == "ImageButton") then return true end
	return false
end
function MI:GetChildren() return table.clone(self.__children) end
function MI:GetDescendants()
	local out = {}
	local function walk(i) for _, c in ipairs(i.__children) do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function MI:Destroy()
	self.Parent = nil
	rawset(self, "__destroyed", true)
end
function MI:ClearAllChildren() for _, c in ipairs(table.clone(self.__children)) do c:Destroy() end end
function MI:SetAttribute(k, v) self.__attrs[k] = v end
function MI:GetAttribute(k) return self.__attrs[k] end
function MI:IsDescendantOf(x)
	local p = rawget(self, "__parent")
	while p do if p == x then return true end; p = rawget(p, "__parent") end
	return false
end
local InstanceMock = { new = function(class, parent) return MI.new(class, nil, parent) end }

------------------------------------------------------------------------------------------------
-- Loader with a client environment (own module cache)
------------------------------------------------------------------------------------------------
local cache, overrides = {}, {}
local lang = "en"
local reduced = false
local workspaceStub = setmetatable({ GetServerTimeNow = function() return 1760000000 + clock end, FindFirstChild = function() return nil end }, { __index = function() return nil end })
local warnings = {}
local function requireNode(node)
	local path = L.Paths[node]
	assert(path, "require: not a src module")
	if overrides[path] ~= nil then return overrides[path] end
	if cache[path] ~= nil then return cache[path] end
	local file
	for _, ext in ipairs({ ".luau", ".client.luau", ".server.luau" }) do
		if fs.isFile("src/" .. path .. ext) then file = "src/" .. path .. ext; break end
	end
	assert(file, "no source " .. path)
	local env = setmetatable({
		script = node, game = L.Game, workspace = workspaceStub, require = requireNode,
		Color3 = roblox.Color3, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, UDim2 = roblox.UDim2,
		UDim = roblox.UDim, Enum = roblox.Enum, Font = roblox.Font, ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange, Rect = roblox.Rect,
		Instance = InstanceMock, typeof = typeof, task = task, Random = L.Random,
		warn = function(...) table.insert(warnings, table.concat({ ... }, " ")) end,
		print = function() end,
		os = setmetatable({ clock = function() return clock end, time = function() return 1760000000 + math.floor(clock) end }, { __index = os }),
	}, { __index = _G })
	local result = luau.load(fs.readFile(file), { debugName = file, environment = env })()
	cache[path] = result
	return result
end

------------------------------------------------------------------------------------------------
-- Server: the real feature on an in-memory profile
------------------------------------------------------------------------------------------------
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end, Current = function() return 1 end }
local R = L.Require("ServerScriptService.Economy.Rules")
local Feature = L.Require("ServerScriptService.Economy.Features.LuckyDust")
local Res = L.Require("ReplicatedStorage.DogEconomy.Resources")
Feature.TradeBusy = function() return false end
Feature.Opening = function() return false end
Feature.EventOn = function() return true end
local profile = R.Normalize(R.Profile(1, 1760000000), 1, 1760000000)
local n = 0
local function addBlock(tier, state)
	n += 1
	local uid = string.format("%032x", 0xB000 + n)
	profile.OwnedBlocks[uid] = { Uid = uid, OwnerUserId = 1, Tier = tier, State = state or "Stored", PurchasedAt = 1759000000 + n, PaidRandom = false, Origin = "Reward", Slot = state and state ~= "Stored" and 1 or nil, ReadyAt = state and 1760000000 + 99 or nil }
	return uid
end

------------------------------------------------------------------------------------------------
-- Client mocks: player, Net, Kit, navigation
------------------------------------------------------------------------------------------------
local player = { UserId = 1, Name = "Tester", __attrs = {}, __signals = {} }
function player:GetAttribute(k) return self.__attrs[k] end
function player:SetAttribute(k, v)
	self.__attrs[k] = v
	local s = self.__signals[k]
	if s then s:Fire() end
end
function player:GetAttributeChangedSignal(k)
	local s = self.__signals[k]
	if not s then s = Signal(); self.__signals[k] = s end
	return s
end
L.Stubs.Players.LocalPlayer = player

local requests = {}
local function snapshot()
	local view = R.Copy(profile)
	for _, b in pairs(view.OwnedBlocks) do b.Seed, b.Pool, b.Variants = nil, nil, nil end
	return { Profile = view, Features = {}, ItemCapacity = 50 }
end
local cached = snapshot()
local changed = Signal()
local function project()
	player:SetAttribute("LuckyDust", Res.Get(profile, "LuckyDust"))
end
local Net = {
	Changed = changed,
	Request = function(action, args)
		table.insert(requests, { Action = action, Args = R.Copy(args) })
		local copy = R.Copy(profile)
		local ok, message, extra = pcall(R.Action, copy, action, R.Copy(args), 1760000000 + math.floor(clock), function() return 0.5 end)
		if not ok then
			return false, message
		end
		R.Validate(copy)
		profile = copy
		local result = { Message = message }
		for k, v in pairs(extra or {}) do result[k] = v end
		cached = snapshot()
		result.StateSnapshot = cached
		changed:Fire(cached)
		return true, result
	end,
	Snapshot = function() cached = snapshot(); changed:Fire(cached); return cached end,
	Cached = function() return cached end,
	Publish = function(s) cached = s; changed:Fire(s) end,
	OnPush = function() return { Disconnect = function() end } end,
}
overrides["StarterGui/ScreenGui/Modules/Net"] = Net
overrides["StarterGui/ScreenGui/Modules/GUIIntegration"] = { Navigate = function() end, OpenScreen = function() end }
overrides["ReplicatedStorage/PlotInteractionAccess"] = { CanUse = function() return false end }
overrides["ReplicatedStorage/LuckyBlockVisuals"] = { Build = function() return nil end }

local Theme = requireNode(L.Game.StarterGui.ScreenGui.Modules.Kit.Theme)
local Format = requireNode(L.Game.StarterGui.ScreenGui.Modules.Kit.Format)
local toasts, modals = {}, {}
local function textWidth(text, size)
	local chars = utf8.len(tostring(text)) or #tostring(text)
	return math.floor(chars * (size or 14) * 0.58)
end
local function button(parent, p)
	p = p or {}
	local b = { Props = p, Disabled = p.Disabled == true, Busy = false, Text = p.Text or "", Style = p.Style or "primary" }
	b.Instance = MI.new("TextButton", { Name = p.Name or "KitButton", Size = p.Size or roblox.UDim2.fromOffset(170, 46), Position = p.Position or roblox.UDim2.new(), LayoutOrder = p.LayoutOrder or 0, ZIndex = p.ZIndex or 1, Text = "" }, parent)
	b.Instance.__p.Caption = b.Text
	function b:SetText(t) self.Text = t; self.Instance.__p.Caption = t end
	function b:SetStyle(s) self.Style = s end
	function b:SetDisabled(v) self.Disabled = v end
	function b:SetBusy(v) self.Busy = v end
	function b:SetPrice(v) self.Price = v end
	function b:SetIcon() end
	function b:SetOnClick(fn) self.Props.OnClick = fn end
	function b:Click()
		assert(not self.Disabled, "clicked a disabled button: " .. tostring(self.Text))
		if self.Props.OnClick then task.spawn(self.Props.OnClick) end
	end
	function b:Destroy() self.Instance:Destroy() end
	return b
end
local function text(parent, p)
	p = p or {}
	local t = MI.new(p.Class or "TextLabel", { Name = p.Name or "Label", Text = p.Text or "", TextSize = p.TextSize or 16, Size = p.Size or roblox.UDim2.fromScale(1, 1), Position = p.Position or roblox.UDim2.new(), AnchorPoint = p.AnchorPoint or roblox.Vector2.zero, ZIndex = p.ZIndex or 1, LayoutOrder = p.LayoutOrder or 0, TextColor3 = p.Color }, parent)
	if p.NoTranslate then t:SetAttribute("NoTranslate", true) end
	return t
end
local function pill(parent, p)
	p = p or {}
	local o = { Props = p }
	o.Instance = MI.new("Frame", { Name = p.Name or "KitPill", Size = p.Size or roblox.UDim2.fromOffset(0, p.Height or 22), Position = p.Position or roblox.UDim2.new(), AnchorPoint = p.AnchorPoint or roblox.Vector2.zero, LayoutOrder = p.LayoutOrder or 0, BackgroundColor3 = p.Color }, parent)
	o.Label = text(o.Instance, { Text = p.Text or "", TextSize = p.TextSize })
	function o:Set(t, color)
		if t then
			self.Label.Text = t
			self.Instance.__p.AutoW = textWidth(t, p.TextSize or 13) + (p.PadX or 8) * 2
			self.Instance.__p.Caption = t
			local s = self.Instance.__prop.AbsoluteSize
			if s then s:Fire() end
		end
		if color then self.Instance.BackgroundColor3 = color end
	end
	function o:SetGradient() end
	function o:SetVisible(v) self.Instance.Visible = v end
	function o:Destroy() self.Instance:Destroy() end
	o:Set(p.Text or "")
	return o
end
local function slot()
	return { Show = function(self, spec) self.Spec = spec end, Clear = function() end, Destroy = function(self) self.Dead = true end }
end
local Kit = {
	Theme = Theme,
	Format = Format,
	Words = {},
	Lang = function() return lang end,
	T = function(en, ru) if lang == "ru" and ru then return ru end return en end,
	Word = function(w) return w end,
	Now = function() return 1760000000 + clock end,
	New = function(class, props, parent) return MI.new(class, props, parent) end,
	Text = text,
	Icon = function(parent) return MI.new("ImageLabel", nil, parent) end,
	Corner = function(o) return MI.new("UICorner", nil, o) end,
	Stroke = function(o) return MI.new("UIStroke", nil, o) end,
	Padding = function(o) return MI.new("UIPadding", nil, o) end,
	Button = button,
	Pill = pill,
	RarityTag = function(parent, r, p) local o = pill(parent, p); o.SetRarity = function() end; return o end,
	MutationTag = function(parent, m, p) local o = pill(parent, p); o.SetMutation = function() end; return o end,
	ProgressBar = function(parent, p)
		local o = { Value = 0, Text = "" }
		o.Instance = MI.new("Frame", { Name = p.Name or "KitProgress", Size = roblox.UDim2.new(1, 0, 0, p.Height or 18) }, parent)
		function o:SetValue(v) self.Value = v end
		function o:SetText(t) self.Text = t; self.Instance.__p.Caption = t end
		function o:SetColor(c) self.Color = c end
		return o
	end,
	Tooltip = function() end,
	EmptyState = function(parent) return { SetVisible = function() end, Set = function() end, Instance = MI.new("Frame", nil, parent) } end,
	Toast = function(t, o) table.insert(toasts, { Text = t, Opts = o or {} }) end,
	Chips = function(parent, p)
		local o = { Props = p, Selected = table.clone(p.Selected or {}) }
		o.Instance = MI.new("Frame", { Name = p.Name or "KitChips", Size = p.Size or roblox.UDim2.new(1, 0, 0, 36), Position = p.Position or roblox.UDim2.new() }, parent)
		function o:SetSelected(list, silent) self.Selected = list; if not silent and p.OnChange then task.spawn(p.OnChange, list) end end
		function o:GetSelected() return self.Selected end
		function o:Toggle(id)
			local i = table.find(self.Selected, id)
			if i then table.remove(self.Selected, i) else table.insert(self.Selected, id) end
			if p.OnChange then task.spawn(p.OnChange, table.clone(self.Selected)) end
		end
		function o:Destroy() end
		return o
	end,
	SearchBox = function(parent, p) local o = { Instance = MI.new("Frame", { Name = p.Name }, parent) }; function o:SetText() end; return o end,
	SortSelect = function(parent, p) return { Instance = MI.new("Frame", { Name = p.Name }, parent) } end,
	CardGrid = function(host, p)
		local o = { Props = p, Items = {}, Empty = { Set = function() end } }
		o.Instance = MI.new("Frame", { Name = p.Name, Size = roblox.UDim2.fromScale(1, 1) }, host)
		function o:SetItems(items)
			self.Items = items
			for _, item in ipairs(items) do p.Map(item) end -- card data must build
		end
		function o:RefreshKey() end
		function o:Destroy() end
		return o
	end,
	Preview = { BuildSize = 256, Register = function() end, Slot = function() return slot() end },
	Sound = { Play = function() end, Attach = function() end },
	Overlay = { Popup = function() end, Push = function(e) return e end, Remove = function() end },
	Motion = {
		Reduced = function() return reduced end,
		Tween = function(inst, _t, goals)
			for k, v in pairs(goals) do inst[k] = v end
			return nil
		end,
	},
}
local function modal(p)
	local m = { Props = p, Done = false, Callbacks = {} }
	m.ConfirmButton = button(nil, { Text = p.ConfirmText or "CONFIRM" })
	m.CancelButton = button(nil, { Text = "CANCEL" })
	m.Maid = { Give = function() end }
	if p.Content then
		m.Content = MI.new("Frame", { Name = "Content", Size = roblox.UDim2.fromOffset(480, p.ContentHeight or 120), ZIndex = 20 }, nil)
		p.Content(m.Content, 480)
	end
	for _, card in ipairs(p.Cards or {}) do
		assert(card.Name and card.Rarity and card.Preview, "modal card data")
	end
	function m:Then(fn) if self.Done then task.spawn(fn, self.Result) else table.insert(self.Callbacks, fn) end return self end
	function m:Resolve(v)
		if self.Done then return end
		self.Done, self.Result = true, v == true
		for _, fn in ipairs(self.Callbacks) do task.spawn(fn, self.Result) end
	end
	table.insert(modals, m)
	return m
end
Kit.Modal = modal
Kit.Confirm = function(title, body, opts) local p = table.clone(opts or {}); p.Title, p.Body = title, body; return modal(p) end

-- The window: pages under a body frame sized from the chosen layout.
local layout = { Phone = false, Landscape = false, Width = 1060, Height = 600 }
local windows = {}
Kit.Window = {
	new = function(p)
		local w = { Props = p, IsOpen = false, Pages = {}, Tab = p.Tab, Resized = Signal(), Badges = {} }
		root = MI.new("ScreenGui", { Name = "KitWindows" })
		root.__p.ScreenSize = roblox.Vector2.new(layout.Width + 40, layout.Height + 200)
		w.Gui = root
		w.Body = MI.new("Frame", { Name = "Body", Position = roblox.UDim2.fromOffset(20, 150), Size = roblox.UDim2.fromOffset(layout.Width, layout.Height) }, root)
		function w:Page(id)
			if not self.Pages[id] then
				self.Pages[id] = MI.new("Frame", { Name = "Page_" .. id, Size = roblox.UDim2.fromScale(1, 1), Visible = (self.Tab == nil) or self.Tab == id }, self.Body)
			end
			return self.Pages[id]
		end
		function w:GetLayout() return table.clone(layout) end
		function w:SetBadge(id, v) self.Badges[id] = v end
		function w:SetTab(id, silent)
			self.Tab = id
			for pid, page in pairs(self.Pages) do page.Visible = pid == id end
			if not silent and p.OnTab then task.spawn(p.OnTab, id) end
		end
		function w:SetTitle() end
		function w:Open()
			self.IsOpen = true
			if p.OnOpen then task.spawn(p.OnOpen, self) end
			self.Resized:Fire(self:GetLayout())
		end
		function w:Close(reason)
			if not self.IsOpen then return end
			self.IsOpen = false
			if p.OnClose then task.spawn(p.OnClose, self, reason or "api") end
		end
		function w:Destroy() self.IsOpen = false; root:Destroy() end
		function w:Relayout()
			w.Body.Size = roblox.UDim2.fromOffset(layout.Width, layout.Height)
			root.__p.ScreenSize = roblox.Vector2.new(layout.Width + 40, layout.Height + 200)
			self.Resized:Fire(self:GetLayout())
		end
		table.insert(windows, w)
		return w
	end,
}
overrides["StarterGui/ScreenGui/Modules/Kit"] = Kit

------------------------------------------------------------------------------------------------
-- Scenario
------------------------------------------------------------------------------------------------
local passed, failed = 0, 0
local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1 else failed += 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end
local function lastToast() return toasts[#toasts] end
local function lastModal() return modals[#modals] end

local S
local function open(page)
	S.Open(nil, page)
	advance(0.1)
end
local function dump(name)
	if not OUT then
		return
	end
	-- Rectangles of every visible object under the visible page (absolute pixels).
	local out = { Screen = { layout.Width + 40, layout.Height + 200 }, Body = { 20, 150, layout.Width, layout.Height }, Items = {} }
	local w = windows[#windows]
	local page = w.Pages[w.Tab]
	local function walk(inst, depth)
		if not inst.Visible then return end
		local x, y, ww, hh = absRect(inst)
		local caption = inst.__p.Caption or (inst.__class == "TextLabel" and inst.Text) or nil
		if inst.__class ~= "UICorner" and inst.__class ~= "UIStroke" and inst.__class ~= "UIPadding" and inst.__class ~= "UIGradient" and inst.__class ~= "UIListLayout" and inst.__class ~= "UIScale" then
			table.insert(out.Items, { Name = inst.Name, Class = inst.__class, Rect = { x, y, ww, hh }, Text = caption, Depth = depth })
		end
		for _, c in ipairs(inst.__children) do walk(c, depth + 1) end
	end
	walk(page, 0)
	fs.writeFile(OUT .. "/" .. name .. ".json", serde.encode("json", out))
end

-- Profile: a few of everything.
for _ = 1, 4 do addBlock("Common") end
for _ = 1, 3 do addBlock("Rare") end
addBlock("Epic")
addBlock("Legendary")
addBlock("Legendary", "Placed")
addBlock("Pumpkin")
profile.LuckyCredits.Common = 2
cached = snapshot()
project()

S = requireNode(L.Game.StarterGui.ScreenGui.Modules.InventoryScreen)

check("opens on the blocks tab with the dust counter and DISMANTLE ALL", function()
	open("LuckyBlocks")
	local ui = S.UI
	truthy(ui.DustPill, "dust pill")
	eq(ui.DustPill.Label.Text, "✨ 0")
	truthy(ui.BulkButton, "bulk button")
	truthy(ui.ForgeCards and ui.ForgeCards.Common and ui.ForgeCards.Legendary, "forge cards")
	eq(windows[1].Tab, "blocks")
end)

check("block detail: DISMANTLE shows the yield; a Common quote card, confirm -> dust", function()
	local ui = S.UI
	local g
	for _, item in ipairs(ui.BlockGrid.Items) do if item.Tier == "Common" then g = item end end
	truthy(g, "common group")
	ui.BlockGrid.Props.OnClick(g)
	local d = ui.BlockDetail
	truthy(d.Dismantle.Instance.Visible, "dismantle visible")
	eq(d.Dismantle.Price, "✨ 12")
	d.Dismantle:Click()
	local m = lastModal()
	eq(m.Props.Title, "DISMANTLE THIS BLOCK?")
	eq(m.Props.Danger, false)
	eq(m.Props.Hold, 0)
	eq(m.Props.ConfirmText, "DISMANTLE · ✨ 12")
	m:Resolve(true)
	advance(0.1)
	eq(Res.Get(profile, "LuckyDust"), 12, "server dust")
	eq(lastToast().Text, "Dismantled 1 block: +12 Lucky Dust")
	project()
	advance(1)
	eq(ui.DustPill.Label.Text, "✨ 12", "counter")
end)

check("Legendary: Danger hold-to-confirm card; cancel keeps the block", function()
	local ui = S.UI
	local g
	for _, item in ipairs(ui.BlockGrid.Items) do if item.Tier == "Legendary" then g = item end end
	ui.BlockGrid.Props.OnClick(g)
	local d = ui.BlockDetail
	eq(d.Dismantle.Price, "✨ 1,875")
	d.Dismantle:Click()
	local m = lastModal()
	eq(m.Props.Danger, true)
	eq(m.Props.Hold, 1.2)
	eq(m.Props.ConfirmStyle, "danger")
	m:Resolve(false)
	advance(0.1)
	local legendary = 0
	for _, b in pairs(profile.OwnedBlocks) do if b.Tier == "Legendary" then legendary += 1 end end
	eq(legendary, 2, "kept")
	d.Dismantle:Click()
	m = lastModal()
	m:Resolve(true)
	advance(0.1)
	eq(requests[#requests].Args.Confirm, true, "confirm sent")
	eq(Res.Get(profile, "LuckyDust"), 12 + 1875)
	project()
	advance(1)
end)

check("Pumpkin: quote card shows the candy bonus", function()
	local ui = S.UI
	local g
	for _, item in ipairs(ui.BlockGrid.Items) do if item.Tier == "Pumpkin" then g = item end end
	ui.BlockGrid.Props.OnClick(g)
	ui.BlockDetail.Dismantle:Click()
	local m = lastModal()
	truthy(string.find(m.Props.Body, "15 Candy", 1, true), m.Props.Body)
	truthy(m.Content:FindFirstChild("Quote"):FindFirstChild("Candy"), "candy pill")
	m:Resolve(false)
end)

check("an expired quote is asked again before the dismantle", function()
	local ui = S.UI
	local g
	for _, item in ipairs(ui.BlockGrid.Items) do if item.Tier == "Rare" then g = item end end
	ui.BlockGrid.Props.OnClick(g)
	ui.BlockDetail.Dismantle:Click()
	local m = lastModal()
	local before = #requests
	advance(70) -- the server forgot the quote
	m:Resolve(true)
	advance(0.1)
	eq(requests[before + 1].Action, "DismantleQuote", "re-quote")
	eq(requests[before + 2].Action, "Dismantle")
	eq(Res.Get(profile, "LuckyDust"), 12 + 1875 + 55)
	project()
	advance(1)
end)

check("DISMANTLE ALL: chips, a live quote, confirm dismantles Common + Rare and credits", function()
	local ui = S.UI
	ui.BulkButton:Click()
	local m = lastModal()
	eq(m.Props.Title, "DISMANTLE ALL")
	local chips = m.Content:FindFirstChild("Tiers")
	truthy(chips, "chips")
	advance(0.5)
	local summary = m.Content:FindFirstChild("Summary")
	truthy(string.find(summary.Text, "→", 1, true), "summary " .. summary.Text)
	truthy(not m.ConfirmButton.Disabled, "confirm enabled")
	local dust = Res.Get(profile, "LuckyDust")
	m:Resolve(true)
	advance(0.1)
	local left = 0
	for _, b in pairs(profile.OwnedBlocks) do if b.Tier == "Common" or b.Tier == "Rare" then left += 1 end end
	eq(left, 0, "all common / rare gone")
	eq(profile.LuckyCredits.Common, 0, "credits gone")
	eq(Res.Get(profile, "LuckyDust"), dust + 3 * 12 + 2 * 55 + 2 * 12)
	project()
	advance(1)
	ui.BulkButton:Click()
	eq(lastToast().Text, "No Common or Rare blocks in your bag to dismantle.")
end)

check("DUST FORGE: buttons follow the balance; forge a Rare; Legendary asks for a hold", function()
	local ui = S.UI
	windows[1]:SetTab("forge")
	advance(0.1)
	local dust = Res.Get(profile, "LuckyDust")
	eq(ui.ForgeDust.Text, Format.Number(dust))
	local rare = ui.ForgeCards.Rare
	eq(rare.Button.Text, "FORGE")
	eq(ui.ForgeCards.Legendary.Button.Disabled, true, "legendary unaffordable")
	truthy(string.find(ui.ForgeCards.Legendary.Button.Text, "NEED", 1, true), ui.ForgeCards.Legendary.Button.Text)
	local blocks = R.Count(profile.OwnedBlocks)
	rare.Button:Click()
	advance(1)
	eq(R.Count(profile.OwnedBlocks), blocks + 1, "forged")
	eq(Res.Get(profile, "LuckyDust"), dust - 220)
	eq(lastToast().Text, "Forged a Rare Lucky Block")
	project()
	advance(1)
	-- Enough for a Legendary: hold confirm.
	Res.Add(profile, "LuckyDust", 20000)
	project()
	advance(1)
	ui.ForgeCards.Legendary.Button:Click()
	local m = lastModal()
	eq(m.Props.Hold, 0.8)
	m:Resolve(true)
	advance(0.5)
	local legendary = 0
	for _, b in pairs(profile.OwnedBlocks) do if b.Tier == "Legendary" and b.Origin == "DustForge" then legendary += 1 end end
	eq(legendary, 1)
	project()
	advance(1)
end)

check("DUST FORGE: storage full disables every FORGE button", function()
	local ui = S.UI
	while R.Count(profile.OwnedBlocks) < 60 do addBlock("Common") end
	cached = snapshot()
	changed:Fire(cached)
	advance(0.5)
	for tier, c in pairs(ui.ForgeCards) do
		eq(c.Button.Disabled, true, tier)
		eq(c.Button.Text, "STORAGE FULL")
	end
end)

dump("desktop_forge")
windows[1]:SetTab("blocks")
advance(0.1)
dump("desktop_blocks")

-- Phone portrait and landscape layouts, then Russian.
local function relayoutTo(l)
	layout = l
	windows[#windows]:Relayout()
	advance(0.1)
end
check("phone portrait layout", function()
	relayoutTo({ Phone = true, Landscape = false, Width = 374, Height = 690 })
	dump("phone_blocks")
	windows[#windows]:SetTab("forge")
	advance(0.1)
	dump("phone_forge")
	truthy(not S.UI.ForgeHint.Visible, "hint hidden on phones")
end)
check("phone landscape layout", function()
	relayoutTo({ Phone = true, Landscape = true, Width = 780, Height = 290 })
	dump("landscape_forge")
	windows[#windows]:SetTab("blocks")
	advance(0.1)
	dump("landscape_blocks")
	-- A phone tap on a block opens the stacked detail window with its own DISMANTLE.
	local g = S.UI.BlockGrid.Items[1]
	S.UI.BlockGrid.Props.OnClick(g)
	truthy(S.DetailUI and S.DetailUI.Dismantle, "phone detail dismantle")
end)
check("Russian: the window rebuilds with Russian dust texts", function()
	S.Close()
	advance(0.1)
	lang = "ru"
	relayoutTo({ Phone = false, Landscape = false, Width = 1060, Height = 600 })
	S.Open({ Tab = "forge" })
	advance(0.5)
	local ui = S.UI
	eq(ui.ForgeTitle.Text, "СЧАСТЛИВАЯ ПЫЛЬ")
	eq(ui.ForgeCards.Common.Button.Text, "ХРАНИЛИЩЕ ПОЛНО")
	dump("ru_forge")
	windows[#windows]:SetTab("blocks")
	advance(0.1)
	dump("ru_blocks")
	ui.BulkButton:Click()
	local m = lastModal()
	eq(m.Props.Title, "РАЗОБРАТЬ ВСЁ")
	advance(0.5)
	truthy(string.find(m.Content:FindFirstChild("Summary").Text, "Блоков", 1, true), m.Content:FindFirstChild("Summary").Text)
	truthy(string.find(m.Content:FindFirstChild("Detail").Text, "за раз", 1, true), "30 at a time: " .. m.Content:FindFirstChild("Detail").Text)
	truthy(string.find(m.ConfirmButton.Text, "РАЗОБРАТЬ", 1, true), m.ConfirmButton.Text)
	m:Resolve(false)
end)
check("reduced motion: no sparks, counter jumps", function()
	reduced = true
	Res.Add(profile, "LuckyDust", 5)
	project()
	advance(0.1)
	eq(S.UI.DustPill.Label.Text, "✨ " .. Format.Number(Res.Get(profile, "LuckyDust")))
end)

-- Sparks are cleaned up.
advance(5)
local sparks = 0
for _, w in ipairs(windows) do
	for _, inst in ipairs(w.Gui:GetDescendants()) do if inst.Name == "DustSpark" then sparks += 1 end end
end
check("no dust sparks left behind", function() eq(sparks, 0) end)
check("no warnings from the bag", function() eq(#warnings, 0, table.concat(warnings, " | ")) end)
print(string.format("lucky_dust_ui: %d passed, %d failed (%d requests, %d toasts, %d dialogs)", passed, failed, #requests, #toasts, #modals))
if failed > 0 then
	error("lucky_dust_ui tests failed")
end
