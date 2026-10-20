-- Client state of CHAPTER II · THE UNDERYARD (StarterPlayerScripts.HalloweenClient.Chapter2State; DESIGN §22.5).
-- CS.Start(ctx) · CS.View() -> the Chapter II view (Features.Underyard shape, also HalloweenState.View.Chapter2)
-- CS.Server() -> {Enabled, Now, Phase, NextPhaseAt, Start, Resonance} from C2Hello
-- CS.Request(action, args) -> ok, res   (RS.Halloween.Remotes.Request through HalloweenClient.State: never throws,
--                                       the reply's view refreshes both views)
-- CS.Enabled() · CS.Eligible() · CS.RevealSeen() · CS.Notified() · CS.Entered() · CS.Seals() -> mask "1100000"
-- CS.SealCleared(i) · CS.Cleared() · CS.InZone() · CS.District() · CS.Trial() · CS.Tutorial() · CS.Phase()
-- CS.Shards() · CS.Keys() · CS.Dust() · CS.L({en, ru}) · CS.T(englishServerText) -> localized
-- Bus events: "C2Changed" {View} (every new view), "C2Signal" {Kind, Data} (every server signal whose Kind starts
-- with "C2"), "C2Zone" {Inside, District} (server signal, or local presence before it arrives), "C2Ready" {View, Server},
-- "C2Phase" {Phase, NextPhaseAt} (RS.Halloween.State.Chapter2). C2Toast signals become Bus "Toast" (localized).
-- Prompts that carry ActionTextRU / ObjectTextRU attributes (Underyard + church portal) are localized when shown.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local CS = {}
CS.Config = Cfg
CS.Rules = Rules
CS.Layout = Layout

local player = Players.LocalPlayer
local view: any = nil
local server: any = nil
local State: any = nil
local started = false

---------------------------------------------------------------------------------------------------------------------
-- Localization (Localization.Underyard: Exact / UI / Patterns)
---------------------------------------------------------------------------------------------------------------------
local loc: any = nil
local function locModule(): any
	if loc == nil then
		local ok, m = pcall(function()
			local folder = RS:FindFirstChild("Localization")
			local inst = folder and folder:FindFirstChild("Underyard")
			return inst and require(inst)
		end)
		loc = ok and type(m) == "table" and m or false
	end
	return loc or nil
end

function CS.L(pair: any): string
	if type(pair) == "table" then
		return Shared.L(pair[1] or "", pair[2])
	end
	return tostring(pair or "")
end

-- Russian of an English server message (Underyard first, then the Halloween module), else the text itself
function CS.T(en: string): string
	if type(en) ~= "string" or not Shared.IsRussian() then
		return en
	end
	local m = locModule()
	local out = m and m.Translate and m.Translate(en, "ru")
	if out then
		return out
	end
	return Shared.T(en)
end

---------------------------------------------------------------------------------------------------------------------
-- Readers
---------------------------------------------------------------------------------------------------------------------
function CS.View(): any
	return view
end

function CS.Server(): any
	return server
end

function CS.Enabled(): boolean
	return Shared.Chapter2Enabled()
end

function CS.Eligible(): boolean
	return player:GetAttribute("HalloweenChapter1Complete") == true or (view ~= nil and view.Chapter1 ~= nil and view.Chapter1.Complete == true)
end

function CS.RevealSeen(): boolean
	return player:GetAttribute("Chapter2RevealSeen") == true or (view ~= nil and view.RevealSeen == true)
end

function CS.Notified(): boolean
	return player:GetAttribute("Chapter2Notified") == true or (view ~= nil and view.Chapter1 ~= nil and view.Chapter1.Notified == true)
end

function CS.Entered(): boolean
	return player:GetAttribute("Chapter2Entered") == true or (view ~= nil and view.Entered == true)
end

function CS.Seals(): string
	local mask = player:GetAttribute("UySealMask")
	if type(mask) == "string" and #mask == #Cfg.Seals then
		return mask
	end
	return view and type(view.Mask) == "string" and view.Mask or string.rep("0", #Cfg.Seals)
end

function CS.SealCleared(i: number): boolean
	return string.sub(CS.Seals(), i, i) == "1"
end

function CS.Cleared(): number
	local n = 0
	for c in string.gmatch(CS.Seals(), "1") do
		n += #c
	end
	return n
end

function CS.InZone(): boolean
	local attr = player:GetAttribute("UyInZone")
	if attr ~= nil then
		return attr == true
	end
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root ~= nil and Layout.InZone((root :: BasePart).Position, 2)
end

function CS.District(): string
	local d = player:GetAttribute("UyDistrict")
	return type(d) == "string" and d or ""
end

function CS.Trial(): string
	local t = player:GetAttribute("UyTrial")
	return type(t) == "string" and t or ""
end

-- current onboarding step (0 = not started, -1 = done)
function CS.Tutorial(): number
	return tonumber(player:GetAttribute("UyTutorial")) or (view and view.Tutorial and view.Tutorial.Current) or 0
end

function CS.Phase(): number
	local folder = Halloween:FindFirstChild("State")
	local c2 = folder and folder:FindFirstChild("Chapter2")
	local phase = c2 and c2:GetAttribute("Phase")
	if type(phase) == "number" then
		return phase
	end
	return Rules.Phase(Shared.Now(), Cfg)
end

function CS.Shards(): number
	return tonumber(player:GetAttribute("BellShards")) or (view and view.Shards) or 0
end

function CS.Keys(): number
	return tonumber(player:GetAttribute("CoffinKeys")) or (view and view.Keys) or 0
end

function CS.Dust(): number
	return tonumber(player:GetAttribute("LuckyDust")) or (view and view.Dust) or 0
end

function CS.Request(action: string, args: any?): (boolean, any)
	if not State then
		return false, "Not ready"
	end
	return State.Request(action, args)
end

---------------------------------------------------------------------------------------------------------------------
-- View tracking
---------------------------------------------------------------------------------------------------------------------
local function setView(v: any)
	if type(v) ~= "table" or v == view then
		return
	end
	view = v
	Bus.Fire("C2Changed", { View = v })
end

-- Russian prompt text from the server's attributes (Underyard prompts, the church portal)
local function localizePrompt(prompt: ProximityPrompt)
	if not Shared.IsRussian() then
		return
	end
	local action, object = prompt:GetAttribute("ActionTextRU"), prompt:GetAttribute("ObjectTextRU")
	if type(action) == "string" and prompt.ActionText ~= action then
		if prompt:GetAttribute("HwEnglishActionText") == nil then
			prompt:SetAttribute("HwEnglishActionText", prompt.ActionText)
		end
		prompt.ActionText = action
	end
	if type(object) == "string" and prompt.ObjectText ~= object then
		if prompt:GetAttribute("HwEnglishObjectText") == nil then
			prompt:SetAttribute("HwEnglishObjectText", prompt.ObjectText)
		end
		prompt.ObjectText = object
	end
end

local function watchZone()
	local lastInside, lastDistrict = nil, nil
	local function push(inside: boolean, where: string)
		if inside ~= lastInside or where ~= lastDistrict then
			lastInside, lastDistrict = inside, where
			Bus.Fire("C2Zone", { Inside = inside, District = where })
		end
	end
	player:GetAttributeChangedSignal("UyInZone"):Connect(function()
		push(player:GetAttribute("UyInZone") == true, CS.District())
	end)
	player:GetAttributeChangedSignal("UyDistrict"):Connect(function()
		push(CS.InZone(), CS.District())
	end)
	-- before the server's first presence sample (arrival right after a teleport): local detection
	task.spawn(function()
		while true do
			task.wait(.5)
			if player:GetAttribute("UyInZone") == nil then
				local ch = player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local pos = root and (root :: BasePart).Position
				local inside = pos ~= nil and Layout.InZone(pos, 2)
				push(inside, inside and (Layout.District(pos :: Vector3) or "BellSquare") or "")
			end
		end
	end)
end

local function watchPhase()
	local folder = Halloween:WaitForChild("State", 30)
	local c2 = folder and folder:WaitForChild("Chapter2", 60)
	if not c2 then
		return
	end
	local function fire()
		Bus.Fire("C2Phase", { Phase = c2:GetAttribute("Phase") or 0, NextPhaseAt = c2:GetAttribute("NextPhaseAt") or 0 })
	end
	c2:GetAttributeChangedSignal("Phase"):Connect(fire)
	fire()
end

function CS.Start(ctx: any)
	if started then
		return
	end
	started = true
	State = ctx and ctx.State or require(script.Parent:WaitForChild("State"))
	local last = State.View
	if type(last) == "table" then
		setView(last.Chapter2)
	end
	Bus.On("StateChanged", function(data)
		if type(data) == "table" and type(data.View) == "table" then
			setView(data.View.Chapter2)
		end
	end)
	Bus.On("Signal", function(sig)
		if type(sig) ~= "table" or type(sig.Kind) ~= "string" or string.sub(sig.Kind, 1, 2) ~= "C2" then
			return
		end
		local data = sig.Data
		if sig.Kind == "C2Toast" and type(data) == "table" and type(data.Text) == "string" then
			local text = CS.T(data.Text)
			Bus.Fire("Toast", { Text = text, Kind = data.Kind, NoTranslate = true })
		elseif sig.Kind == "C2Phase" and type(data) == "table" then
			if server then
				server.Phase, server.NextPhaseAt = data.Phase, data.NextPhaseAt
			end
		end
		Bus.Fire("C2Signal", { Kind = sig.Kind, Data = data })
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute("ActionTextRU") ~= nil or prompt:GetAttribute("ObjectTextRU") ~= nil then
			localizePrompt(prompt)
		end
	end)
	watchZone()
	task.spawn(watchPhase)
	if not Shared.Chapter2Enabled() then
		return
	end
	-- first sync: the Chapter II view + the server's phase info
	task.spawn(function()
		for attempt = 1, 60 do
			local ok, res = CS.Request("C2Hello")
			if ok and type(res) == "table" then
				server = res.Server
				Bus.Fire("C2Ready", { View = view, Server = server })
				return
			end
			if res == "Chapter II is closed" then
				return
			end
			task.wait(math.min(2 + attempt * .5, 8))
		end
	end)
end

return CS
