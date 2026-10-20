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
	if kind == "mid" then
		local s1 = u.Seals["1"]
		s1.Offered, s1.Cleared, s1.Gold, s1.At, s1.Best = true, true, true, NOW - DAY, 1840
		u.Seals["2"].Offered, u.Seals["2"].Cleared, u.Seals["2"].At = true, true, NOW - 3600
		u.Seals["3"].Offered = true
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
	P:SetAttribute("MoonCandy", hv.Candy or 900)
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

if OUT then
	fs.writeDir(OUT)
	fs.writeFile(OUT .. "/underyard_dump.json", serde.encode("json", dumps))
	print("layouts: " .. #dumps .. " -> " .. OUT)
end
for _, w in ipairs(CE.Warnings) do
	print("warn: " .. w)
end
print(string.format("underyard_ui: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
