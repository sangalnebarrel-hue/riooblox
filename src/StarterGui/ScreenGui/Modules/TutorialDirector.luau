-- Main DOGROTS tutorial director, version 4 (docs/halloween2/TUTORIAL.md). Started by Modules.OnboardingGuide (which
-- GUIIntegration starts once per session); replaces the old card UI of the guide.
--
-- A state machine keyed on the server step (player attributes TutorialStep / TutorialActive / TutorialStepAt /
-- TutorialSkippable written by Economy.Runtime from Economy.OnboardingRules; the track is ReplicatedStorage.TutorialConfig).
-- For every step it shows a Kit card in its own ScreenGui (DOGROTS_Tutorial, DisplayOrder 55: above the HUD and the
-- Halloween guide, below Kit windows at 60) with the title, one sentence, the objective and its progress and buttons
-- (GuiButton.Activated through Kit.Button), and in the world:
--   * a 2.2 s camera focus on the step's target (HalloweenClient.Cinema when it is there, else an own pcall'd camera
--     tween with a guaranteed restore; none with reduced motion; any tap skips it),
--   * a Highlight on the target, a world marker over it (name, distance, bouncing arrow, a light beacon on Medium+
--     quality) and SHOW THE WAY (Navigation.PathGuide) to the step's destination,
--   * for menu steps a pulsing ring around the HUD rail tile that opens the menu.
-- View steps report Tutorial {Action = "Seen"} when their menu opens (gui attribute OpenMenu); place steps report
-- {Action = "Arrive"} once the character is in range (the server checks again with its own positions). There is no
-- NEXT on task steps: SHOW ME replays the focus and the path, and SKIP THIS STEP opens 120 s after the step started
-- (at the Lucky Blocks step: CLAIM FREE BLOCK). HOW TO PLAY (Director.Replay) runs the same cards client-only.
--
-- Robustness: requests time out after 8 s (buttons come back with RETRY, which resends the same request id, so a
-- late reply is never applied twice); render and every world update run in pcall; markers rebind on CharacterAdded;
-- the layer is rebuilt if something destroys it and the director stops cleanly with the main ScreenGui; a target
-- that does not stream in within 3 s falls back to the destination anchor (path + marker, never a hang); the card is
-- the only input-taking object of the layer, nothing uses Modal, and the focus never leaves a Scriptable camera.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local TC = require(ReplicatedStorage:WaitForChild("TutorialConfig"))

local Director = {}
local controller: any = nil

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLUE = C(38, 164, 243)
local GOLD = C(249, 180, 35)
local GOLD_HI = C(255, 214, 92)
local GREEN = C(125, 219, 48)
local RED = C(247, 73, 112)
local INK = C(23, 43, 76)
local MUTED = C(83, 112, 150)
local SURFACE_ALT = C(244, 240, 232)
local TASKS = TC.LastStep - 1 -- task steps 1..13
local LAYER_NAME = "DOGROTS_Tutorial"
local WORLD_NAME = "DOGROTS_TutorialWorld"
local FOCUS_BIND = "DOGROTS_TutorialFocus"
local FOCUS_MAX_DISTANCE = 260 -- no camera trip to a far place (path + marker are enough there)

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The camera path of a focus: ease from `from` to `shot`, hold, ease back.
local function focusCurve(from: CFrame, shot: CFrame, t: number, duration: number): CFrame
	local inTime = math.min(0.7, duration * 0.32)
	local outTime = math.min(0.6, duration * 0.27)
	local w = 1
	if t < inTime then
		w = smooth(t / inTime)
	elseif t > duration - outTime then
		w = 1 - smooth((t - (duration - outTime)) / outTime)
	end
	return from:Lerp(shot, w)
end

local function newId(): string
	return (string.gsub(HttpService:GenerateGUID(false), "-", ""))
end

local function mmss(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Director.Replay()
	if controller then
		controller.Replay()
	end
end

function Director.Running(): boolean
	return controller ~= nil
end

function Director.Stop()
	if controller then
		controller.Stop()
	end
end

function Director.Start(gui: any, navigation: any): any
	if controller then
		return controller
	end
	local player = Players.LocalPlayer
	local modules = script.Parent
	local Kit = require(modules:WaitForChild("Kit"))
	local Base = require(modules.Kit:WaitForChild("Base"))
	local remote = ReplicatedStorage:WaitForChild("DogEconomyRequest")

	-- Localization: ReplicatedStorage.Localization.Tutorial (UI / Exact / Templates).
	local Dict: any = { UI = {}, Exact = {}, Templates = {} }
	do
		local folder = ReplicatedStorage:FindFirstChild("Localization")
		local module = folder and folder:FindFirstChild("Tutorial")
		if module then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				Dict = value
			end
		end
	end
	local function ru(): boolean
		return Kit.Lang() == "ru"
	end
	local function T(en: string): string
		if ru() then
			return Dict.UI[en] or Dict.Exact[en] or en
		end
		return en
	end
	local function F(en: string, ...): string
		local pattern = ru() and Dict.Templates[en] or en
		local ok, text = pcall(string.format, pattern, ...)
		return ok and text or string.format(en, ...)
	end
	-- A server reply in the player's language (unknown replies stay English: the error label is left to AutoTranslate).
	local function say(message: any): string
		local text = tostring(message or "")
		return ru() and Dict.Exact[text] or text
	end

	local Shared: any = nil
	do
		local folder = ReplicatedStorage:FindFirstChild("Halloween")
		local module = folder and folder:FindFirstChild("Shared")
		if module then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				Shared = value
			end
		end
	end
	local function quality(): string
		if Shared and Shared.Quality then
			local ok, q = pcall(Shared.Quality)
			if ok and type(q) == "string" then
				return q
			end
		end
		return player:GetAttribute("LowFX") == true and "Low" or "High"
	end
	local function reduced(): boolean
		return Kit.Motion.Reduced()
	end

	local GameConfig: any = nil
	do
		local folder = ReplicatedStorage:FindFirstChild("DogEconomy")
		local module = folder and folder:FindFirstChild("Config")
		if module then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				GameConfig = value
			end
		end
	end
	local PathGuide: any = nil
	local function pathGuide(): any
		if PathGuide == nil then
			PathGuide = false
			local folder = ReplicatedStorage:FindFirstChild("Navigation")
			local module = folder and folder:FindFirstChild("PathGuide")
			if module then
				local ok, value = pcall(require, module)
				if ok and type(value) == "table" then
					PathGuide = value
				end
			end
		end
		return PathGuide or nil
	end

	------------------------------------------------------------------------------------------------------------------
	-- The cards (rebuilt when the language changes)
	------------------------------------------------------------------------------------------------------------------
	-- Icon: Kit icon key. Action: "Path" (SHOW ME) or a menu ("Inventory", "UpgradeTree", "Layers", "Strength",
	-- "DogDex", "Trade"). Tile: the HUD rail tile that opens the menu.
	local cardCache, cardLang = nil, nil
	local function cards(): any
		local lang = Kit.Lang()
		if cardCache and cardLang == lang then
			return cardCache
		end
		cardLang = lang
		cardCache = {
			[0] = {
				Title = T("WELCOME TO DOGROTS"),
				Body = T("Your dogs dig, you sell, your yard grows. This guide walks you through the real loop, one task at a time."),
				Objective = T("Press START when you are ready"),
				Icon = "Dogs",
			},
			[1] = {
				Title = T("BUY YOUR FIRST DOG"),
				Body = T("Walk to THE DOG's tongue and buy a dog you can afford: every dog is a worker for your yard."),
				Objective = T("Buy a dog on THE DOG's tongue"),
				Icon = "Dogs",
				Action = "Path",
			},
			[2] = {
				Title = T("PUT YOUR DOG TO WORK"),
				Body = T("Back in your yard, walk up to an empty kennel and assign your dog: only assigned dogs dig."),
				Objective = T("Assign a dog to a kennel"),
				Icon = "Yard",
				Action = "Path",
			},
			[3] = {
				Title = T("WAIT FOR THE FIRST DIG"),
				Body = T("Your dog digs in cycles: every dig pays Coins straight into your wallet and can turn up a find."),
				Objective = T("Watch your dog finish its first dig"),
				Icon = "Dig",
				Action = "Path",
			},
			[4] = {
				Title = T("COLLECT YOUR LOOT"),
				Body = T("Every find your dogs dig up lands in your BAG. Open it and look at what you found."),
				Objective = T("Open your BAG"),
				Icon = "Inventory",
				Action = "Inventory",
				Tile = "Inventory",
			},
			[5] = {
				Title = T("SELL A FIND"),
				Body = T("Take your finds to the Collector in your yard and sell them for Coins."),
				Objective = T("Sell a find at your Collector"),
				Icon = "Coins",
				Action = "Path",
			},
			[6] = {
				Title = T("GROW YOUR UPGRADE TREE"),
				Body = T("Spend Coins on any node of the UPGRADE TREE: every level makes your yard stronger for good."),
				Objective = T("Buy any node of the UPGRADE TREE"),
				Icon = "Records",
				Action = "UpgradeTree",
				Tile = "Yard",
			},
			[7] = {
				Title = T("DIG DEEPER: LAYERS"),
				Body = T("Deeper layers pay much more. Open LAYERS and check what the next one needs."),
				Objective = T("Open the LAYERS panel"),
				Icon = "Bones",
				Action = "Layers",
				Tile = "Yard",
			},
			[8] = {
				Title = T("MINE ORE IN YOUR QUARRY"),
				Body = T("Buy a pickaxe at the PICKAXES stall, then tap each ring as it shrinks onto the ore."),
				Objective = T("Buy a pickaxe and hit the ore"),
				Icon = "Dig",
				Action = "Path",
			},
			[9] = {
				Title = T("BUILD YOUR STRENGTH"),
				Body = T("STRENGTH is a branch of the UPGRADE TREE: buy IRON GRIP to hit harder and unlock better pickaxes."),
				Objective = T("Buy a node of the STRENGTH branch"),
				Icon = "EnergySnack",
				Action = "Strength",
				Tile = "Yard",
			},
			[10] = {
				Title = T("LUCKY BLOCKS"),
				Body = T("Lucky Blocks hatch dogs on the Lucky Pads of your yard. Walk to a pad: a FREE block is waiting there!"),
				Objective = T("Walk to a Lucky Pad in your yard"),
				Icon = "RareBlock",
				Action = "Path",
			},
			[11] = {
				Title = T("THE MUTATION LAB"),
				Body = T("At the nuclear tower a dog can mutate into Shiny, Golden, Corrupted, Glitched or Void. Your first try is free!"),
				Objective = T("Walk to the Mutation Lab"),
				Icon = "Lab",
				Action = "Path",
			},
			[12] = {
				Title = T("YOUR DOGDEX"),
				Body = T("The DOGDEX lists every dog you have discovered, and collection milestones pay rewards."),
				Objective = T("Open the DOGDEX"),
				Icon = "DogDex",
				Action = "DogDex",
				Tile = "DogDex",
			},
			[13] = {
				Title = T("SAFE TRADING"),
				Body = T("Trade dogs and finds with other players: put yours on the table, press READY, then HOLD CONFIRM."),
				Objective = T("Open the TRADE screen"),
				Icon = "Trade",
				Action = "Trade",
				Tile = "Trade",
			},
			[14] = {
				Title = T("YOU KNOW THE LOOP!"),
				Body = T("Buy dogs, dig, sell, upgrade, mine and go deeper. HOW TO PLAY in SETTINGS replays this guide anytime."),
				Objective = T("All tasks done"),
				Icon = "Star",
			},
		}
		return cardCache
	end
	local function actionText(action: string?): string
		if action == "Path" then
			return T("SHOW ME")
		elseif action == "Inventory" then
			return T("OPEN MY BAG")
		elseif action == "UpgradeTree" then
			return T("OPEN UPGRADE TREE")
		elseif action == "Layers" then
			return T("OPEN LAYERS")
		elseif action == "Strength" then
			return T("OPEN STRENGTH")
		elseif action == "DogDex" then
			return T("OPEN DOGDEX")
		elseif action == "Trade" then
			return T("OPEN TRADE")
		end
		return ""
	end

	------------------------------------------------------------------------------------------------------------------
	-- State
	------------------------------------------------------------------------------------------------------------------
	local state: any = {
		Alive = true,
		Replay = nil, -- HOW TO PLAY step (client only) or nil
		Collapsed = false,
		Pending = nil, -- a button's request {Token, Action, Args, Id, Manual}
		Background = nil, -- a silent Seen / Arrive report (never blocks the buttons)
		Failed = nil, -- {Action, Args, Id} of a manual request that can be retried
		Error = nil, -- text under the objective
		ShowAfter = os.clock() + TC.ShowAfter,
		Entered = nil, -- "<mode>:<step>" whose world is set up
		Token = 0, -- bumps on every enter (async target waits compare it)
		Target = nil, -- {Instance?, Position, Size, Label, Moving, Fallback}
		RetargetAt = 0,
		FocusPending = false,
		FocusDeadline = 0,
		Focusing = false,
		ArriveAt = 0,
		SeenAt = {},
		PathKey = nil, -- the destination key this director last drew
		LastServerStep = nil,
		CompleteFlash = 0,
		NoPad = false,
		Rebuilds = 0,
	}
	local connections: { RBXScriptConnection } = {}
	local function connect(signal: any, fn: any)
		local c = signal:Connect(fn)
		table.insert(connections, c)
		return c
	end
	local warned: { [string]: number } = {}
	local function warnOnce(where: string, err: any)
		local now = os.clock()
		if now - (warned[where] or -60) >= 30 then
			warned[where] = now
			warn("DOGROTS tutorial " .. where .. ": " .. tostring(err))
		end
	end

	local function serverStep(): number
		return math.clamp(math.floor(tonumber(player:GetAttribute("TutorialStep")) or 0), 0, TC.LastStep)
	end
	local function currentStep(): number
		return state.Replay or serverStep()
	end
	local function serverActive(): boolean
		return player:GetAttribute("TutorialActive") == true
			and player:GetAttribute("EconomyReady") == true
			and tonumber(player:GetAttribute("TutorialVersion")) == TC.Version
	end
	local function wanted(): boolean
		if state.Replay ~= nil then
			return true
		end
		return serverActive() and os.clock() >= state.ShowAfter
	end
	local function blocked(): boolean
		if gui:GetAttribute("OpenMenu") ~= nil then
			return true
		end
		if (tonumber(gui:GetAttribute("ModalOwnerCount")) or 0) > 0 then
			return true
		end
		if gui:GetAttribute("MiningActive") == true or gui:GetAttribute("UIHidden") == true then
			return true
		end
		if gui:GetAttribute("CinemaActive") == true and not state.Focusing then
			return true
		end
		return false
	end
	local function serverNow(): number
		local ok, now = pcall(function()
			return workspace:GetServerTimeNow()
		end)
		return ok and now or os.time()
	end
	local function skipRemaining(): number
		if player:GetAttribute("TutorialSkippable") == true then
			return 0
		end
		local at = tonumber(player:GetAttribute("TutorialStepAt")) or 0
		return math.max(0, at + TC.SkipAfter - serverNow())
	end

	------------------------------------------------------------------------------------------------------------------
	-- World lookups (everything nil-safe: parts stream in and out)
	------------------------------------------------------------------------------------------------------------------
	local function rootPart(): BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return (root and root:IsA("BasePart")) and root or nil
	end
	local function district(): Instance?
		return workspace:FindFirstChild("DOGROTS_District")
	end
	local function myYard(): Instance?
		local map = district()
		local yards = map and map:FindFirstChild("04_PlayerYards")
		if not yards then
			return nil
		end
		local id = player:GetAttribute("YardId")
		for _, yard in ipairs(yards:GetChildren()) do
			if yard:GetAttribute("OwnerUserId") == player.UserId and yard:GetAttribute("YardId") == id then
				return yard
			end
		end
		return nil
	end
	-- Position, size (largest extent) and a part to adorn for an instance.
	local function describe(object: Instance?): (Vector3?, number, BasePart?)
		if not object or not object.Parent then
			return nil, 0, nil
		end
		if object:IsA("BasePart") then
			local size = object.Size
			return object.Position, math.max(size.X, size.Y, size.Z), object
		end
		if object:IsA("Model") then
			local ok, cf, size = pcall(function()
				return object:GetBoundingBox()
			end)
			local part = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
			if ok and cf then
				return cf.Position, math.max(size.X, size.Y, size.Z), part
			end
			if part then
				return part.Position, math.max(part.Size.X, part.Size.Y, part.Size.Z), part
			end
		end
		if object:IsA("Attachment") then
			return object.WorldPosition, 2, object.Parent :: any
		end
		return nil, 0, nil
	end
	local function coins(): number
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild("Coins")
		return (value and value:IsA("ValueBase")) and (tonumber((value :: any).Value) or 0) or 0
	end
	local function myDogs(): { Instance }
		local folder = player:FindFirstChild("DogInventory")
		return folder and folder:GetChildren() or {}
	end
	local function luckyPads(): { BasePart }
		local yard = myYard()
		local pads = {}
		if yard then
			for slot = 1, 6 do
				local pad = yard:FindFirstChild("LuckyPad_" .. slot)
				if pad and pad:IsA("BasePart") then
					table.insert(pads, pad)
				end
			end
		end
		return pads
	end
	local function arrivePoints(key: string): { Vector3 }
		local points = {}
		if key == "LuckyPad" then
			for _, pad in ipairs(luckyPads()) do
				table.insert(points, pad.Position)
			end
		elseif key == "Lab" then
			local map = district()
			local lab = map and map:FindFirstChild("05_MutationLab")
			for _, name in ipairs(TC.Arrive.Lab.Anchors) do
				local anchor = lab and lab:FindFirstChild(name)
				if anchor and anchor:IsA("BasePart") then
					table.insert(points, anchor.Position)
				end
			end
			if #points == 0 then
				for _, point in ipairs(TC.Arrive.Lab.Fallback) do
					table.insert(points, point)
				end
			end
		end
		return points
	end

	-- The thing a step points at: {Instance?, Position, Size, Label, Moving?, Fallback?} or nil (a menu step).
	local function resolveTarget(index: number): any
		local map = district()
		if index == 1 then
			-- the nearest dog on THE DOG's tongue the player can afford
			local line = map and map:FindFirstChild("03_DogLine")
			local active = line and line:FindFirstChild("ActiveDogs")
			local root = rootPart()
			local wallet = coins()
			local best, bestDistance = nil, math.huge
			for _, dog in ipairs(active and active:GetChildren() or {}) do
				local price = tonumber(dog:GetAttribute("CurrentPrice"))
				local owner = dog:GetAttribute("OwnerUserId")
				if dog:IsA("Model") and dog:GetAttribute("DogId") and price and price <= wallet and (owner == nil or owner == 0)
					and dog:GetAttribute("State") == "OnLine" and dog:GetAttribute("PurchaseBusy") ~= true then
					local position = describe(dog)
					if position then
						local distance = root and (position - root.Position).Magnitude or 0
						if distance < bestDistance then
							best, bestDistance = dog, distance
						end
					end
				end
			end
			if best then
				return { Instance = best, Label = T("BUY THIS DOG"), Moving = true }
			end
			local tongue = line and (line:FindFirstChild("Tongue") or line:FindFirstChild("EntranceAnchor"))
			if tongue then
				return { Instance = tongue, Label = T("THE DOG"), Big = true }
			end
			return nil
		end
		local yard = myYard()
		if index == 2 or index == 3 then
			if not yard then
				return nil
			end
			local slots = {}
			for _, child in ipairs(yard:GetChildren()) do
				local n = tonumber(string.match(child.Name, "^DigSlot_(%d+)$"))
				if n then
					table.insert(slots, { N = n, Slot = child })
				end
			end
			table.sort(slots, function(a, b)
				return a.N < b.N
			end)
			if index == 3 then
				-- the kennel of a working dog
				for _, entry in ipairs(myDogs()) do
					local slotName = entry:GetAttribute("AssignedSlot")
					local slot = type(slotName) == "string" and slotName ~= "" and yard:FindFirstChild(slotName)
					if slot then
						return { Instance = slot, Label = T("DIGGING") }
					end
				end
			end
			for _, row in ipairs(slots) do
				if row.Slot:GetAttribute("Unlocked") ~= false and not row.Slot:GetAttribute("AssignedDogUid") then
					return { Instance = row.Slot, Label = index == 2 and T("EMPTY KENNEL") or T("DIGGING") }
				end
			end
			return slots[1] and { Instance = slots[1].Slot, Label = T("YOUR KENNEL") } or nil
		end
		if index == 5 then
			local vendor = yard and (yard:FindFirstChild("SellAnchor") or yard:FindFirstChild("Vendor"))
			if vendor then
				return { Instance = vendor, Highlight = yard and yard:FindFirstChild("Vendor") or vendor, Label = T("COLLECTOR") }
			end
			return nil
		end
		if index == 8 then
			local corner = yard and yard:FindFirstChild("MiningCorner")
			if not corner then
				return nil
			end
			if (tonumber(player:GetAttribute("MiningPickaxeOwned")) or 0) < 1 then
				local shop = corner:FindFirstChild("MiningPickaxeShop")
				if shop then
					return { Instance = shop, Label = T("BUY A PICKAXE") }
				end
			end
			local ore = corner:FindFirstChild("MiningOreCore") or corner:FindFirstChild("MiningPad")
			return ore and { Instance = ore, Label = T("HIT THE ORE") } or nil
		end
		if index == 10 then
			local pads = luckyPads()
			local free = nil
			for _, pad in ipairs(pads) do
				if not pad:GetAttribute("LuckyBlockUid") then
					free = pad
					break
				end
			end
			local pad = free or pads[1]
			return pad and { Instance = pad, Label = T("LUCKY PAD · FREE BLOCK") } or nil
		end
		if index == 11 then
			local lab = map and map:FindFirstChild("05_MutationLab")
			local anchor = lab and (lab:FindFirstChild("InteractionAnchor") or lab:FindFirstChild("EntranceAnchor"))
			local compound = lab and lab:FindFirstChild("NuclearCompound")
			local console = compound and compound:FindFirstChild("Console")
			if anchor then
				return { Instance = anchor, Highlight = console, Label = T("MUTATION LAB") }
			end
			return nil
		end
		return nil
	end
	-- Destination fallback (a target that is not streamed in / not built): the route's own anchor point.
	local function anchorFallback(index: number): any
		local step = TC.Steps[index]
		local key = step and step.Destination
		if not key then
			return nil
		end
		local ok, point = pcall(function()
			local folder = ReplicatedStorage:FindFirstChild("Navigation")
			local RouteGraph = require((folder :: any):FindFirstChild("RouteGraph"))
			local target = RouteGraph.Target(key, { YardId = player:GetAttribute("YardId") })
			return target and target.Pointer
		end)
		if ok and typeof(point) == "Vector3" then
			return { Position = point, Size = 6, Label = T("THIS WAY"), Fallback = true }
		end
		if index == 11 then
			return { Position = TC.Arrive.Lab.Fallback[2], Size = 6, Label = T("MUTATION LAB"), Fallback = true }
		end
		return nil
	end
	local function hasWorld(index: number): boolean
		local card = cards()[index]
		return card ~= nil and card.Action == "Path"
	end

	------------------------------------------------------------------------------------------------------------------
	-- The layer and the card
	------------------------------------------------------------------------------------------------------------------
	local ui: any = {}
	local render: () -> ()
	local layout: () -> ()
	local onPrimary: () -> ()
	local onSecondary: () -> ()
	local buildLayer: () -> ()

	local function buildCard(layer: any)
		local card = Kit.New("Frame", {
			Name = "TutorialCard",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Active = true, -- the card itself takes taps (they never reach the world behind it)
			Visible = false,
			ZIndex = 2,
		}, layer)
		Kit.Corner(card, 18)
		Kit.Stroke(card, INK, 3, 0)
		Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, C(240, 247, 255)) }, card)
		ui.Card = card
		ui.Pop = Kit.New("UIScale", { Name = "Pop" }, card)
		-- header band
		local band = Kit.New("Frame", { Name = "Band", BorderSizePixel = 0, BackgroundColor3 = BLUE, ZIndex = 3 }, card)
		Kit.Corner(band, 14)
		Kit.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(84, 190, 255), BLUE) }, band)
		ui.Band = band
		local iconCircle = Kit.New("Frame", { Name = "IconCircle", BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 4 }, card)
		Kit.Corner(iconCircle, "pill")
		Kit.Stroke(iconCircle, INK, 2, 0)
		ui.IconCircle = iconCircle
		ui.IconHolder = Kit.New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Position = UDim2.fromScale(0.16, 0.16), Size = UDim2.fromScale(0.68, 0.68), ZIndex = 5 }, iconCircle)
		ui.Kicker = Kit.Text(card, { Name = "Kicker", TextSize = 13, Scaled = true, MinTextSize = 8, Color = WHITE, Stroke = 0.35, NoTranslate = true, ZIndex = 4 })
		ui.Title = Kit.Text(card, { Name = "Title", TextSize = 24, Scaled = true, MinTextSize = 12, Color = INK, NoTranslate = true, ZIndex = 4 })
		ui.Body = Kit.Text(card, { Name = "Body", TextSize = 16, Wrap = true, AlignY = "Top", Color = MUTED, NoTranslate = true, ZIndex = 4 })
		-- objective box: check mark, objective, progress bar
		local objective = Kit.New("Frame", { Name = "Objective", BorderSizePixel = 0, BackgroundColor3 = SURFACE_ALT, ZIndex = 3 }, card)
		Kit.Corner(objective, 12)
		Kit.Stroke(objective, INK, 2, 0.75)
		ui.Objective = objective
		ui.Check = Kit.Text(objective, { Name = "Check", Text = "○", TextSize = 20, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = BLUE, NoTranslate = true, ZIndex = 4 })
		ui.Goal = Kit.Text(objective, { Name = "Goal", TextSize = 16, Wrap = true, Color = INK, NoTranslate = true, ZIndex = 4 })
		ui.Bar = Kit.ProgressBar(objective, { Name = "Progress", Height = 16, TextSize = 11, Color = GREEN, NoTranslate = true, ZIndex = 4 })
		ui.Info = Kit.Text(card, { Name = "Info", TextSize = 14, Wrap = true, AlignY = "Top", Color = INK, NoTranslate = true, ZIndex = 4 })
		-- the error line is left to AutoTranslate (server replies from any system can show here)
		ui.Error = Kit.Text(card, { Name = "Error", TextSize = 14, Wrap = true, AlignY = "Top", Color = RED, ZIndex = 4 })
		ui.Hint = Kit.Text(card, { Name = "Hint", TextSize = 13, Wrap = true, AlignX = "Center", Color = MUTED, NoTranslate = true, ZIndex = 4 })
		ui.Primary = Kit.Button(card, { Name = "Primary", Text = "", Style = "primary", TextSize = 18, NoTranslate = true, ZIndex = 4, OnClick = function()
			onPrimary()
		end })
		ui.Secondary = Kit.Button(card, { Name = "Secondary", Text = "", Style = "secondary", TextSize = 15, NoTranslate = true, ZIndex = 4, OnClick = function()
			onSecondary()
		end })
		ui.Collapse = Kit.Button(card, { Name = "Collapse", Text = "–", Style = "ghost", TextSize = 24, NoTranslate = true, ZIndex = 5, OnClick = function()
			state.Collapsed = not state.Collapsed
			render()
		end })
		ui.Dots = {}
		for i = 1, TASKS do
			local dot = Kit.New("Frame", { Name = "Dot" .. i, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 4 }, card)
			Kit.Corner(dot, "pill")
			ui.Dots[i] = dot
		end
		-- HUD rail tile ring (menu steps): an input-transparent outline over the tile + a pointing hand
		local ring = Kit.New("Frame", { Name = "TileRing", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Visible = false, ZIndex = 1 }, layer)
		Kit.Corner(ring, 16)
		ui.RingStroke = Kit.Stroke(ring, GOLD, 4, 0)
		ui.Ring = ring
		ui.Hand = Kit.Text(layer, { Name = "TileHand", Text = "👈", TextSize = 34, Scaled = true, MinTextSize = 10, AlignX = "Center", NoTranslate = true, ZIndex = 1, Size = UDim2.fromOffset(40, 40) })
		ui.Hand.Visible = false
		ui.Hand.Active = false
	end

	local lastIcon = nil
	buildLayer = function()
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		-- the previous layer's handlers go first, so removing a stale copy does not count as a rebuild
		for _, c in ipairs(ui.LayerConnections or {}) do
			c:Disconnect()
		end
		ui.LayerConnections = nil
		local old = playerGui:FindFirstChild(LAYER_NAME)
		if old then
			old:Destroy()
		end
		local layer = Instance.new("ScreenGui")
		layer.Name = LAYER_NAME
		layer.ResetOnSpawn = false
		layer.IgnoreGuiInset = true
		layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		layer.DisplayOrder = 55
		layer.Enabled = true -- always enabled: visibility is the card's; HideUI may toggle the layer (HideWithUI)
		pcall(function()
			layer.ScreenInsets = Enum.ScreenInsets.None
		end)
		layer:SetAttribute("HideWithUI", true)
		ui = {}
		lastIcon = nil
		buildCard(layer)
		ui.Layer = layer
		layer.Parent = playerGui
		ui.LayerConnections = {
			layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				task.defer(function()
					local ok, err = pcall(layout)
					if not ok then
						warnOnce("layout", err)
					end
				end)
			end),
			layer.Destroying:Connect(function()
				-- something tore the layer down (a PlayerGui reset, a cleanup script): build it again
				if not state.Alive then
					return
				end
				state.Rebuilds += 1
				if state.Rebuilds > 20 then
					warnOnce("rebuild", "the tutorial layer keeps being destroyed")
					return
				end
				task.delay(0.2, function()
					if state.Alive and (not ui.Layer or not ui.Layer.Parent) then
						local ok, err = pcall(buildLayer)
						if not ok then
							warnOnce("rebuild", err)
						end
						render()
					end
				end)
			end),
		}
	end

	------------------------------------------------------------------------------------------------------------------
	-- World markers
	------------------------------------------------------------------------------------------------------------------
	local world: any = { Folder = nil, Anchor = nil, Adornee = nil, Board = nil, Distance = nil, Arrow = nil, Beacon = nil, Ring = nil, Highlight = nil, Tweens = {} }
	local function worldFolder(): Folder
		local folder = world.Folder
		if folder and folder.Parent == workspace then
			return folder
		end
		folder = workspace:FindFirstChild(WORLD_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = WORLD_NAME
			folder.Parent = workspace
		end
		world.Folder = folder
		return folder
	end
	local function clearWorld()
		for _, tween in ipairs(world.Tweens) do
			pcall(function()
				tween:Cancel()
			end)
		end
		world.Tweens = {}
		world.Adornee = nil
		for _, key in ipairs({ "Anchor", "Beacon", "Ring", "Highlight" }) do
			local object = world[key]
			if object then
				pcall(function()
					object:Destroy()
				end)
			end
			world[key] = nil
		end
		world.Board, world.Distance, world.Arrow = nil, nil, nil
	end
	local function targetPosition(target: any): (Vector3?, number)
		if not target then
			return nil, 0
		end
		if target.Instance then
			local position, size = describe(target.Instance)
			if position then
				return position, size
			end
		end
		return target.Position, target.Size or 6
	end
	-- Marker + highlight + beacon for a target (replaces the previous ones).
	local function showWorld(target: any)
		clearWorld()
		if not target then
			return
		end
		local position, size = targetPosition(target)
		if not position then
			return
		end
		local folder = worldFolder()
		local high = quality() ~= "Low"
		local anchor = Instance.new("Part")
		anchor.Name = "TutorialMarker"
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch, anchor.CastShadow = true, false, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(position)
		local board = Instance.new("BillboardGui")
		board.Name = "Marker"
		board.AlwaysOnTop = true
		board.LightInfluence = 0
		board.MaxDistance = 1500
		board.Size = UDim2.fromOffset(230, 104)
		board.StudsOffsetWorldSpace = Vector3.new(0, math.clamp(size * 0.5, 1.5, 22) + 3, 0)
		board:SetAttribute("NoTranslate", true)
		local label = Kit.Text(board, { Name = "Label", Text = target.Label or "", TextSize = 22, Scaled = true, MinTextSize = 10, AlignX = "Center", Color = GOLD_HI, Stroke = 0, NoTranslate = true, Size = UDim2.new(1, 0, 0, 28) })
		label.TextStrokeColor3 = INK
		local distance = Kit.Text(board, { Name = "Distance", Text = "", TextSize = 15, Scaled = true, MinTextSize = 8, AlignX = "Center", Color = WHITE, Stroke = 0, Font = "numeric", NoTranslate = true,
			Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 18) })
		distance.TextStrokeColor3 = INK
		local arrow = Kit.Text(board, { Name = "Arrow", Text = "⬇️", TextSize = 46, Scaled = true, MinTextSize = 10, AlignX = "Center", NoTranslate = true,
			Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 52) })
		board.Parent = anchor
		anchor.Parent = folder
		world.Anchor, world.Board, world.Distance, world.Arrow = anchor, board, distance, arrow
		if not reduced() then
			local bob = TweenService:Create(arrow, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 56) })
			bob:Play()
			table.insert(world.Tweens, bob)
		end
		-- a soft light column + ground ring where to go (not for a dog walking on the tongue)
		if high and not target.Moving and not target.Big then
			local beacon = Instance.new("Part")
			beacon.Name = "TutorialBeacon"
			beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch, beacon.CastShadow = true, false, false, false, false
			beacon.Material = Enum.Material.Neon
			beacon.Color = GOLD
			beacon.Shape = Enum.PartType.Cylinder
			beacon.Size = Vector3.new(46, 1.6, 1.6)
			beacon.CFrame = CFrame.new(position + Vector3.new(0, 23 + size * 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
			beacon.Transparency = 0.7
			beacon.Parent = folder
			world.Beacon = beacon
			local disc = Instance.new("Part")
			disc.Name = "TutorialRing"
			disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = true, false, false, false, false
			disc.Material = Enum.Material.Neon
			disc.Color = GOLD
			disc.Shape = Enum.PartType.Cylinder
			local radius = math.clamp(size * 0.6 + 2, 4, 14)
			disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
			local ground = position - Vector3.new(0, math.min(size * 0.5, 4), 0)
			disc.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
			disc.Transparency = 0.72
			disc.Parent = folder
			world.Ring = disc
			if not reduced() then
				local pulse = TweenService:Create(beacon, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.86 })
				pulse:Play()
				table.insert(world.Tweens, pulse)
			end
		end
		local highlightTarget = target.Highlight or target.Instance
		if highlightTarget and (highlightTarget:IsA("Model") or highlightTarget:IsA("BasePart")) then
			local hl = Instance.new("Highlight")
			hl.Name = "TutorialHighlight"
			hl.FillColor = GOLD
			hl.FillTransparency = target.Big and 1 or 0.82
			hl.OutlineColor = GOLD_HI
			hl.OutlineTransparency = 0
			hl.DepthMode = (target.Big or size > 40) and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = highlightTarget
			hl.Parent = folder
			world.Highlight = hl
			if not reduced() then
				local glow = TweenService:Create(hl, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { OutlineTransparency = 0.55 })
				glow:Play()
				table.insert(world.Tweens, glow)
			end
		end
		-- a moving target (a dog on the tongue): the marker rides on the dog itself
		if target.Moving and target.Instance then
			local _, _, part = describe(target.Instance)
			if part then
				board.Adornee = part
				world.Adornee = part
			end
		end
	end
	local function setWorldVisible(visible: boolean)
		if world.Board then
			world.Board.Enabled = visible
		end
		if world.Highlight then
			world.Highlight.Enabled = visible
		end
		for _, key in ipairs({ "Beacon", "Ring" }) do
			local part = world[key]
			if part then
				part.LocalTransparencyModifier = visible and 0 or 1
			end
		end
	end
	local function updateDistance()
		local root = rootPart()
		local at = world.Adornee and world.Adornee.Parent and world.Adornee or world.Anchor
		if not world.Distance or not at or not root then
			return
		end
		local d = (at.Position - root.Position).Magnitude
		world.Distance.Text = d < 8 and "" or F("%d m", math.floor(d + 0.5))
	end

	------------------------------------------------------------------------------------------------------------------
	-- Camera focus (Cinema when present, else an own guaranteed-restore tween)
	------------------------------------------------------------------------------------------------------------------
	local focus: any = { Handle = nil, Cancel = nil, Token = nil }
	local function cinema(): any
		local scripts = player:FindFirstChild("PlayerScripts")
		local folder = scripts and scripts:FindFirstChild("HalloweenClient")
		local module = folder and folder:FindFirstChild("Cinema")
		if not module or not module:IsA("ModuleScript") then
			return nil
		end
		local ok, value = pcall(require, module)
		if ok and type(value) == "table" and type(value.Play) == "function" then
			return value
		end
		return nil
	end
	local function cancelFocus()
		local cancel = focus.Cancel
		focus.Cancel = nil
		if cancel then
			pcall(cancel)
		end
		state.Focusing = false
	end
	-- A 3/4 shot of `target` from the player's side, pulled in front of walls.
	local function shotFor(position: Vector3, size: number, from: Vector3): CFrame
		local flat = Vector3.new(from.X - position.X, 0, from.Z - position.Z)
		local dir = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, 1)
		-- turn 28° so the shot is not straight along the player's line
		local angle = math.rad(28)
		dir = Vector3.new(dir.X * math.cos(angle) - dir.Z * math.sin(angle), 0, dir.X * math.sin(angle) + dir.Z * math.cos(angle))
		local distance = math.clamp(size * 1.5 + 14, 18, 52)
		local height = math.clamp(size * 0.7 + 8, 9, 30)
		local look = position + Vector3.new(0, math.min(size * 0.2, 4), 0)
		local eye = position + dir * distance + Vector3.new(0, height, 0)
		local ok, hit = pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { player.Character :: any, worldFolder() }
			return workspace:Raycast(look, eye - look, params)
		end)
		if ok and hit then
			eye = hit.Position + (look - hit.Position).Unit * 1.5
		end
		return CFrame.lookAt(eye, look)
	end
	local function playFocus(target: any): boolean
		if reduced() or not target then
			return false
		end
		local cam = workspace.CurrentCamera
		local root = rootPart()
		if not cam or not root or cam.CameraType ~= Enum.CameraType.Custom then
			return false
		end
		local position, size = targetPosition(target)
		if not position or (position - root.Position).Magnitude > FOCUS_MAX_DISTANCE then
			return false
		end
		cancelFocus()
		local duration = TC.FocusSeconds
		local shot = shotFor(position, size, root.Position)
		local startCam = cam.CFrame
		local startRoot = root.Position
		local function from(): CFrame
			local r = rootPart()
			return startCam + ((r and r.Position or startRoot) - startRoot)
		end
		local token = {}
		focus.Token = token
		local function done()
			if focus.Token == token then
				focus.Token = nil
				focus.Cancel = nil
				state.Focusing = false
				render()
			end
		end
		-- the shared cinematic system (WP-P): it blends from the player's camera into the shot and back by itself,
		-- with a ref-counted control lock, skip input and a guaranteed restore; no letterbox / UI hiding / audio duck
		-- for a short tutorial look
		local Cinema = cinema()
		if Cinema then
			local ok, handle = pcall(Cinema.Play, {
				Id = "TutorialFocus",
				Duration = duration,
				Shot = function()
					return shot
				end,
				BlendIn = math.min(0.7, duration * 0.32),
				BlendOut = math.min(0.6, duration * 0.27),
				Focus = { Target = position },
				Letterbox = false,
				HideUI = false,
				Duck = false,
				Skippable = true,
				SkipAfter = 0.2,
				LockControls = true,
				OnDone = done,
				OnSkip = done,
			})
			if ok and handle then
				state.Focusing = true
				focus.Cancel = function()
					if type(handle) == "table" and type(handle.Cancel) == "function" then
						handle.Cancel()
					end
					done()
				end
				render()
				return true
			end
			if ok then
				return false -- refused: another cinematic or a menu owns the camera
			end
			warnOnce("cinema", handle)
		end
		-- own focus: Scriptable for at most `duration`, restored on finish, skip, error, death and Stop
		local finished = false
		local links: { RBXScriptConnection } = {}
		local subject = cam.CameraSubject
		local function finish()
			if finished then
				return
			end
			finished = true
			for _, link in ipairs(links) do
				link:Disconnect()
			end
			pcall(function()
				RunService:UnbindFromRenderStep(FOCUS_BIND)
			end)
			pcall(function()
				if cam.CameraType == Enum.CameraType.Scriptable then
					cam.CameraType = Enum.CameraType.Custom
				end
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				cam.CameraSubject = humanoid or subject
			end)
			done()
		end
		local started = os.clock()
		local ok, err = pcall(function()
			cam.CameraType = Enum.CameraType.Scriptable
			RunService:BindToRenderStep(FOCUS_BIND, Enum.RenderPriority.Camera.Value + 1, function()
				if focus.Token ~= token then
					finish()
					return
				end
				local t = os.clock() - started
				if t >= duration then
					finish()
					return
				end
				cam.CFrame = focusCurve(from(), shot, t, duration)
			end)
			table.insert(links, UserInputService.InputBegan:Connect(function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.Keyboard
					or kind == Enum.UserInputType.Gamepad1 then
					finish()
				end
			end))
			table.insert(links, player.CharacterRemoving:Connect(finish))
		end)
		if not ok then
			finish()
			warnOnce("focus", err)
			return false
		end
		state.Focusing = true
		focus.Cancel = finish
		render()
		return true
	end

	------------------------------------------------------------------------------------------------------------------
	-- Path and HUD ring
	------------------------------------------------------------------------------------------------------------------
	local function showPath(index: number): boolean
		local step = TC.Steps[index]
		local key = step and step.Destination
		local PG = pathGuide()
		if not key or not PG then
			return false
		end
		local ok, shown = pcall(PG.Show, key)
		if ok and shown then
			state.PathKey = key
			return true
		end
		return false
	end
	local function clearPath()
		local PG = pathGuide()
		if not PG or not state.PathKey then
			return
		end
		pcall(function()
			local a = PG.Active()
			if a and a.Key == state.PathKey then
				PG.Clear("cleared")
			end
		end)
		state.PathKey = nil
	end
	local function railTile(key: string?): any
		if not key then
			return nil
		end
		local ok, U = pcall(require, modules:FindFirstChild("UITheme") :: any)
		if not ok or type(U) ~= "table" then
			return nil
		end
		for _, tile in ipairs(U.QuickTiles or {}) do
			if tile.key == key then
				return tile
			end
		end
		return nil
	end
	local ringTween: any = nil
	local function updateRing(index: number, visible: boolean)
		local ring, hand = ui.Ring, ui.Hand
		if not ring or not hand then
			return
		end
		local card = cards()[index]
		local tile = visible and card and railTile(card.Tile)
		local root = tile and tile.root
		local hudVisible = gui:FindFirstChild("HUD") and (gui :: any).HUD.Visible
		if not root or not root.Parent or not root.Visible or not hudVisible or root.AbsoluteSize.X < 4 then
			ring.Visible = false
			hand.Visible = false
			if ringTween then
				ringTween:Cancel()
				ringTween = nil
			end
			return
		end
		local offset = root.AbsolutePosition - ui.Layer.AbsolutePosition
		local size = root.AbsoluteSize
		ring.Position = UDim2.fromOffset(offset.X - 5, offset.Y - 5)
		ring.Size = UDim2.fromOffset(size.X + 10, size.Y + 10)
		local leftSide = offset.X + size.X / 2 < ui.Layer.AbsoluteSize.X / 2
		hand.Text = leftSide and "👈" or "👉"
		hand.Position = UDim2.fromOffset(leftSide and (offset.X + size.X + 8) or (offset.X - 48), offset.Y + size.Y / 2 - 20)
		ring.Visible = true
		hand.Visible = true
		if not ringTween and not reduced() then
			ui.RingStroke.Transparency = 0
			ringTween = TweenService:Create(ui.RingStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
			ringTween:Play()
		end
	end

	------------------------------------------------------------------------------------------------------------------
	-- Requests (8 s timeout, retry with the same id)
	------------------------------------------------------------------------------------------------------------------
	local function onReply(action: string, result: any)
		if type(result) ~= "table" then
			return
		end
		local free = result.FreeBlock
		if type(free) == "table" then
			if free.Granted then
				Kit.Toast(T("+1 FREE COMMON LUCKY BLOCK · it is in your BAG"), { Kind = "success", NoTranslate = true, Duration = 4 })
			elseif free.Reason == "Full" then
				Kit.Toast(T("Your Lucky Block storage is full, so no free block this time."), { Kind = "warn", NoTranslate = true, Duration = 4 })
			end
		end
		if action == "Finish" then
			Kit.Toast(T("Tutorial complete! HOW TO PLAY in SETTINGS replays it."), { Kind = "success", NoTranslate = true, Duration = 4 })
		end
	end
	-- manual: a button press (busy state, timeout message, RETRY); otherwise a silent background report. The two
	-- live in separate slots, so a report in flight never blocks a button.
	local function request(action: string, args: any?, manual: boolean, retryId: string?)
		local slot = manual and "Pending" or "Background"
		if state[slot] then
			return
		end
		local id = retryId or newId()
		local payload = { Action = action }
		for k, v in pairs(args or {}) do
			payload[k] = v
		end
		local token = {}
		state[slot] = { Token = token, Action = action, Args = args, Id = id, Manual = manual }
		if manual then
			state.Error = nil
			state.Failed = nil
		end
		render()
		-- retryable: the request may never have reached the server (no answer, transport error): RETRY resends it
		-- with the same id. A server refusal is a definitive answer: its message shows, the buttons stay as they are.
		local function settle(failure: string?, result: any, retryable: boolean?)
			if not state[slot] or state[slot].Token ~= token then
				return -- timed out before: a late reply only refreshes (attributes already carry the server state)
			end
			state[slot] = nil
			if failure then
				if manual then
					state.Error = failure
					state.Failed = retryable and { Action = action, Args = args, Id = id } or nil
					Kit.Sound.Play("Error")
				end
			else
				onReply(action, result)
			end
			render()
		end
		task.spawn(function()
			local transport, ok, result = pcall(function()
				return remote:InvokeServer("Tutorial", payload, id)
			end)
			if not state.Alive then
				return
			end
			if not transport then
				settle(T("Connection problem. Tap RETRY."), nil, true)
			elseif not ok then
				settle(say(result), nil)
			else
				settle(nil, result)
			end
		end)
		task.delay(TC.RequestTimeout, function()
			if state.Alive and state[slot] and state[slot].Token == token then
				settle(T("No answer from the server. Tap RETRY."), nil, true)
			end
		end)
	end

	------------------------------------------------------------------------------------------------------------------
	-- Entering a step
	------------------------------------------------------------------------------------------------------------------
	local function applyTarget(index: number, target: any)
		state.Target = target
		state.RetargetAt = os.clock() + TC.RetargetEvery
		local ok, err = pcall(showWorld, target)
		if not ok then
			warnOnce("marker", err)
		end
		setWorldVisible(wanted() and not blocked())
		updateDistance()
		if index == 10 then
			state.NoPad = #luckyPads() == 0
		end
	end
	-- Waits up to TargetWait seconds for the target to stream in, then falls back to the destination anchor.
	local function setupWorld(index: number, token: number, autoFocus: boolean, autoPath: boolean)
		task.spawn(function()
			local deadline = os.clock() + TC.TargetWait
			local target = resolveTarget(index)
			while not target and os.clock() < deadline and state.Alive and state.Token == token do
				task.wait(0.25)
				target = resolveTarget(index)
			end
			if not state.Alive or state.Token ~= token then
				return
			end
			if not target then
				target = anchorFallback(index)
			end
			applyTarget(index, target)
			if autoPath then
				showPath(index)
			end
			if autoFocus and target then
				state.FocusPending = true
				state.FocusDeadline = os.clock() + 15 -- the arrival camera can hold the view for up to 12 s
			end
			render()
		end)
	end
	local function enter(index: number)
		local mode = state.Replay ~= nil and "replay" or "live"
		local key = mode .. ":" .. index
		if state.Entered == key then
			return
		end
		local previous = state.Entered
		state.Entered = key
		state.Token += 1
		cancelFocus()
		clearWorld()
		state.Target = nil
		state.FocusPending = false
		state.NoPad = false
		state.Error = nil
		state.Failed = nil
		-- a finished task: a short success beat (sound + pop) before the next card
		local last = state.LastServerStep
		if mode == "live" then
			state.LastServerStep = index
			if last and index > last and previous and previous:sub(1, 4) == "live" then
				state.CompleteFlash = os.clock() + 1.4
				Kit.Sound.Play("Success")
				if not reduced() and ui.Pop then
					ui.Pop.Scale = 0.94
					TweenService:Create(ui.Pop, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end
		end
		if hasWorld(index) then
			setupWorld(index, state.Token, not state.Collapsed, true)
		else
			clearPath() -- a menu step: the previous step's route is not this step's way
		end
	end
	local function leaveAll()
		state.Entered = nil
		state.Token += 1
		cancelFocus()
		clearWorld()
		state.Target = nil
		state.FocusPending = false
		updateRing(0, false)
	end

	------------------------------------------------------------------------------------------------------------------
	-- Buttons
	------------------------------------------------------------------------------------------------------------------
	local function openMenu(action: string)
		local ok, err = pcall(function()
			if action == "Inventory" then
				navigation.OpenPage("Inventory")
			elseif action == "UpgradeTree" then
				navigation.OpenPage("UpgradeTree")
			elseif action == "Layers" then
				navigation.OpenPage("Layers")
			elseif action == "Strength" then
				local opened = false
				local module = modules:FindFirstChild("UpgradeTreeScreen")
				if module then
					local okScreen, screen = pcall(require, module)
					if okScreen and type(screen) == "table" and type(screen.Open) == "function" then
						opened = pcall(screen.Open, "IronGrip")
					end
				end
				if not opened then
					navigation.OpenPage("UpgradeTree")
				end
			elseif action == "DogDex" then
				navigation.OpenPage("DogDex")
			elseif action == "Trade" then
				navigation.OpenScreen("Trade")
			end
		end)
		if not ok then
			warnOnce("open " .. action, err)
		end
	end
	local function showMe(index: number)
		state.Collapsed = false
		local function go(target: any)
			showPath(index)
			if target then
				playFocus(target)
			end
		end
		if state.Target then
			go(state.Target)
		else
			-- the target was not there yet: look again, then go (path even without a target)
			state.Token += 1
			local token = state.Token
			task.spawn(function()
				local target = resolveTarget(index)
				if not target then
					task.wait(0.4)
					target = resolveTarget(index) or anchorFallback(index)
				end
				if state.Alive and state.Token == token then
					applyTarget(index, target)
					go(target)
					render()
				end
			end)
		end
	end
	local function stopReplay()
		state.Replay = nil
		clearPath()
		leaveAll()
		render()
	end
	onPrimary = function()
		local index = currentStep()
		if state.Replay ~= nil then
			if index >= TC.LastStep then
				stopReplay()
			else
				state.Replay = index + 1
				render()
			end
			return
		end
		if state.Pending then
			return
		end
		if state.Failed then
			local failed = state.Failed
			request(failed.Action, failed.Args, true, failed.Id)
			return
		end
		if index == 0 then
			request("Start", nil, true)
		elseif index >= TC.LastStep then
			request("Finish", nil, true)
		else
			local card = cards()[index]
			if card and card.Action == "Path" then
				showMe(index)
			elseif card and card.Action then
				openMenu(card.Action)
			end
		end
	end
	onSecondary = function()
		local index = currentStep()
		if state.Replay ~= nil then
			if index > 0 then
				state.Replay = index - 1
				render()
			else
				stopReplay()
			end
			return
		end
		if state.Pending then
			return
		end
		if index == 0 then
			request("Skip", nil, true)
		elseif index == TC.StepOfKey("LuckyPad") then
			if state.NoPad or skipRemaining() <= 0 then
				request("Claim", nil, true)
			end
		elseif index < TC.LastStep and skipRemaining() <= 0 then
			request("SkipStep", nil, true)
		end
	end

	------------------------------------------------------------------------------------------------------------------
	-- Objectives (text, fraction 0..1, bar text)
	------------------------------------------------------------------------------------------------------------------
	local function progress(index: number): (number, string, string?)
		if index == 0 then
			return 0, "", nil
		elseif index >= TC.LastStep then
			return 1, F("%d / %d", TASKS, TASKS), nil
		end
		if state.Replay ~= nil then
			return 0, "", nil
		end
		if index == 1 then
			local wallet = coins()
			return 0, "0 / 1", F("Your Coins: %s", Kit.Format.Short(wallet, 1))
		elseif index == 3 then
			-- the dig timer of the working dog (NextWorkAt is server unix time)
			local soonest = nil
			for _, entry in ipairs(myDogs()) do
				local slot = entry:GetAttribute("AssignedSlot")
				local at = tonumber(entry:GetAttribute("NextWorkAt"))
				if type(slot) == "string" and slot ~= "" and at then
					soonest = soonest and math.min(soonest, at) or at
				end
			end
			if soonest then
				local left = soonest - serverNow()
				if left > 0 then
					return 1 - math.clamp(left / 30, 0, 1), F("NEXT DIG IN %ds", math.ceil(left)), nil
				end
				return 1, T("DIGGING…"), nil
			end
			return 0, "0 / 1", nil
		elseif index == 5 then
			local finds = tonumber(player:GetAttribute("ItemCount")) or 0
			return 0, "0 / 1", finds > 0 and F("Finds in your BAG: %d", finds) or T("Your dog's next find will land in your BAG")
		elseif index == 7 then
			local layers = GameConfig and GameConfig.Layers
			local unlocked = tonumber(player:GetAttribute("MiningLayer")) or tonumber(player:GetAttribute("CurrentLayer")) or 1
			local nextLayer = type(layers) == "table" and layers[unlocked + 1]
			if nextLayer then
				local name = T(string.upper(tostring(nextLayer.Name or "")))
				return 0, "0 / 1", F("Next: %s · Level %d · %s Coins", name, tonumber(nextLayer.Level) or 0, Kit.Format.Short(tonumber(nextLayer.Cost) or 0, 1))
			end
			return 0, "0 / 1", nil
		elseif index == 8 then
			local owned = (tonumber(player:GetAttribute("MiningPickaxeOwned")) or 0) >= 1
			return owned and 0.5 or 0, owned and "1 / 2" or "0 / 2", nil
		elseif index == 10 or index == 11 then
			local root = rootPart()
			local points = arrivePoints(index == 10 and "LuckyPad" or "Lab")
			local best = nil
			for _, point in ipairs(points) do
				local d = root and (point - root.Position).Magnitude
				if d and (not best or d < best) then
					best = d
				end
			end
			if best then
				local radius = TC.Arrive[index == 10 and "LuckyPad" or "Lab"].Radius
				local left = math.max(0, best - radius)
				return 1 - math.clamp(left / 220, 0, 1), left <= 0 and T("HERE!") or F("%d m TO GO", math.floor(left + 0.5)), nil
			end
			return 0, "0 / 1", nil
		elseif index == 13 then
			local level = tonumber(player:GetAttribute("Level")) or 1
			local need = GameConfig and tonumber(GameConfig.TradeLevel) or 5
			return 0, "0 / 1", level >= need and T("You can trade already!") or F("Trading unlocks at Level %d (you are Level %d)", need, level)
		end
		return 0, "0 / 1", nil
	end

	------------------------------------------------------------------------------------------------------------------
	-- Layout and render
	------------------------------------------------------------------------------------------------------------------
	local function textHeight(text: string, size: number, width: number): number
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(math.max(40, width), 1000))
		end)
		if ok and bounds then
			return math.ceil(bounds.Y)
		end
		return size * 2
	end
	local function textWidth(text: string, size: number): number
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(2000, 200))
		end)
		return ok and bounds and math.ceil(bounds.X) or #text * size * 0.6
	end
	layout = function()
		local layer, card = ui.Layer, ui.Card
		if not layer or not card then
			return
		end
		local sx, sy, sw, sh = Base.SafeArea(layer)
		local touch = UserInputService.TouchEnabled
		local landscape = sw > sh * 1.25
		local small = math.min(sw, sh) < 500
		local wide = small and landscape -- phone landscape: buttons in a right column, a low card
		local pad = small and 12 or 16
		local w = math.floor(math.min(wide and 600 or (small and sw - 24 or 490), sw - 24))
		local collapsed = state.Collapsed and state.Replay == nil
		local icon = collapsed and 34 or (small and 44 or 56)
		local btnH = small and 42 or 46
		local bodySize = small and 14 or 16
		local hasInfo = ui.Info.Text ~= ""
		local hasError = ui.Error.Text ~= ""
		local hasHint = ui.Hint.Text ~= ""
		local colW = wide and 170 or 0
		local textX = pad + icon + 10
		-- header band behind the kicker
		ui.Band.Position = UDim2.fromOffset(4, 4)
		ui.IconCircle.Position = UDim2.fromOffset(pad, collapsed and 9 or pad)
		ui.IconCircle.Size = UDim2.fromOffset(icon, icon)
		ui.Kicker.Position = UDim2.fromOffset(textX, collapsed and 6 or pad - 2)
		ui.Kicker.Size = UDim2.fromOffset(w - textX - 56, 16)
		local titleMax = collapsed and 18 or (small and 20 or 25)
		local titleW = w - textX - 56
		local titleH = collapsed and 22 or (small and 24 or 30)
		-- a long title (Russian) takes two lines instead of shrinking to a small single line
		local twoLines = not collapsed and textWidth(ui.Title.Text, titleMax) > titleW
		if twoLines then
			titleH = math.floor(titleMax * 2.25)
		end
		ui.Title.TextWrapped = twoLines
		ui.Title.Position = UDim2.fromOffset(textX, collapsed and 24 or pad + 18)
		ui.Title.Size = UDim2.fromOffset(titleW, titleH)
		local limit = ui.Title:FindFirstChildWhichIsA("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = titleMax
		end
		ui.Collapse.Instance.Position = UDim2.fromOffset(w - 48, 4)
		ui.Collapse.Instance.Size = UDim2.fromOffset(44, 44)
		local h
		if collapsed then
			h = 54
			ui.Band.Size = UDim2.fromOffset(w - 8, 22)
		else
			local headerBottom = pad + math.max(icon, 18 + titleH) + 8
			ui.Band.Size = UDim2.fromOffset(w - 8, pad + 14)
			local contentW = w - pad * 2 - (wide and colW + 10 or 0)
			local y = headerBottom
			ui.Body.TextSize = bodySize
			local bodyH = textHeight(ui.Body.Text, bodySize, contentW)
			ui.Body.Position = UDim2.fromOffset(pad, y)
			ui.Body.Size = UDim2.fromOffset(contentW, bodyH + 2)
			y += bodyH + 8
			-- the objective wraps (Russian runs ~20% longer) instead of shrinking to an unreadable size
			local goalSize = small and 14 or 16
			ui.Goal.TextSize = goalSize
			local goalH = math.clamp(textHeight(ui.Goal.Text, goalSize, contentW - 44), goalSize + 4, goalSize * 2 + 8)
			local barShown = ui.Bar.Instance.Visible
			local objH = 6 + goalH + (barShown and 24 or 6)
			ui.Objective.Position = UDim2.fromOffset(pad, y)
			ui.Objective.Size = UDim2.fromOffset(contentW, objH)
			ui.Check.Position = UDim2.fromOffset(8, 6 + math.floor((goalH - 22) / 2))
			ui.Check.Size = UDim2.fromOffset(22, 22)
			ui.Goal.Position = UDim2.fromOffset(34, 6)
			ui.Goal.Size = UDim2.fromOffset(contentW - 44, goalH)
			ui.Bar.Instance.Position = UDim2.fromOffset(10, objH - 21)
			ui.Bar.Instance.Size = UDim2.fromOffset(contentW - 20, 15)
			y += objH + 6
			if hasInfo then
				local infoSize = small and 13 or 14
				ui.Info.TextSize = infoSize
				local infoH = textHeight(ui.Info.Text, infoSize, contentW)
				ui.Info.Position = UDim2.fromOffset(pad, y)
				ui.Info.Size = UDim2.fromOffset(contentW, infoH + 2)
				y += infoH + 6
			end
			if hasError then
				local errorH = textHeight(ui.Error.Text, 14, contentW)
				ui.Error.Position = UDim2.fromOffset(pad, y)
				ui.Error.Size = UDim2.fromOffset(contentW, errorH + 2)
				y += errorH + 6
			end
			local secondaryVisible = ui.Secondary.Instance.Visible
			if wide then
				-- right column: the two buttons stacked next to the text
				local bx = w - pad - colW
				local by = headerBottom
				ui.Primary.Instance.Position = UDim2.fromOffset(bx, by)
				ui.Primary.Instance.Size = UDim2.fromOffset(colW, btnH)
				ui.Secondary.Instance.Position = UDim2.fromOffset(bx, by + btnH + 8)
				ui.Secondary.Instance.Size = UDim2.fromOffset(colW, btnH - 4)
				local columnBottom = by + btnH + (secondaryVisible and (btnH + 4) or 0) + 4
				if hasHint then
					ui.Hint.TextSize = 12
					local hintH = textHeight(ui.Hint.Text, 12, colW)
					ui.Hint.Position = UDim2.fromOffset(bx, columnBottom + 4)
					ui.Hint.Size = UDim2.fromOffset(colW, hintH + 2)
					columnBottom += hintH + 8
				end
				y = math.max(y, columnBottom + 4)
			else
				if hasHint then
					ui.Hint.TextSize = 13
					local hintH = textHeight(ui.Hint.Text, 13, w - pad * 2)
					ui.Hint.Position = UDim2.fromOffset(pad, y)
					ui.Hint.Size = UDim2.fromOffset(w - pad * 2, hintH + 2)
					y += hintH + 6
				end
				local gap = 8
				if secondaryVisible then
					local secondaryW = math.clamp(textWidth(ui.Secondary.Caption.Text, 15) + 34, 110, math.floor((w - pad * 2 - gap) * 0.5))
					local primaryW = w - pad * 2 - gap - secondaryW
					ui.Primary.Instance.Position = UDim2.fromOffset(pad + secondaryW + gap, y)
					ui.Primary.Instance.Size = UDim2.fromOffset(primaryW, btnH)
					ui.Secondary.Instance.Position = UDim2.fromOffset(pad, y)
					ui.Secondary.Instance.Size = UDim2.fromOffset(secondaryW, btnH)
				else
					ui.Primary.Instance.Position = UDim2.fromOffset(pad, y)
					ui.Primary.Instance.Size = UDim2.fromOffset(w - pad * 2, btnH)
				end
				y += btnH + 8
			end
			-- progress dots across the bottom
			local dotsVisible = state.Replay == nil and currentStep() > 0
			local gap = 4
			local dotW = math.floor((w - pad * 2 - (TASKS - 1) * gap) / TASKS)
			for i, dot in ipairs(ui.Dots) do
				dot.Visible = dotsVisible
				dot.Position = UDim2.fromOffset(pad + (i - 1) * (dotW + gap), y)
				dot.Size = UDim2.fromOffset(dotW, 6)
			end
			h = y + (dotsVisible and 6 or 0) + pad - 2
		end
		-- where: bottom centre, clear of touch controls; phone landscape centred in the HUD's free zone
		local bottom
		if touch and not landscape and small then
			bottom = 235
		elseif touch and small then
			bottom = 10
		elseif touch then
			bottom = 120
		else
			bottom = 84 -- above the Roblox hotbar
		end
		local cx = sx + sw / 2
		local innerL, innerR = gui:GetAttribute("HUDInnerLeft"), gui:GetAttribute("HUDInnerRight")
		if wide and type(innerL) == "number" and type(innerR) == "number" and innerR - innerL >= w + 16 then
			local ox = gui.AbsolutePosition.X - layer.AbsolutePosition.X
			cx = math.clamp(ox + (innerL + innerR) / 2, sx + w / 2 + 12, sx + sw - w / 2 - 12)
		end
		local maxH = sh - 20
		h = math.min(h, maxH)
		local yBottom = math.max(sy + h + 8, sy + sh - bottom)
		card.Position = UDim2.fromOffset(math.floor(cx), math.floor(yBottom))
		card.Size = UDim2.fromOffset(w, h)
	end

	local function paintDots(index: number)
		for i, dot in ipairs(ui.Dots or {}) do
			local done = i < index or index >= TC.LastStep
			dot.BackgroundColor3 = done and GREEN or (i == index and GOLD or C(208, 222, 238))
		end
	end

	local function renderCard()
		local card = ui.Card
		if not card then
			return
		end
		local show = wanted() and not blocked()
		local index = currentStep()
		local data = cards()[index]
		-- live mode: follow the server step
		if wanted() and data then
			enter(index)
		elseif state.Entered then
			-- the tutorial ended (FINISH / SKIP) or is not ready: take everything of ours out of the world
			if not serverActive() then
				clearPath()
			end
			leaveAll()
		end
		card.Visible = show and data ~= nil
		setWorldVisible(show)
		updateRing(index, show and data ~= nil and (state.Replay ~= nil or not state.Collapsed))
		if not card.Visible or not data then
			return
		end
		local replay = state.Replay ~= nil
		local collapsed = state.Collapsed and not replay
		-- icon
		if lastIcon ~= data.Icon then
			lastIcon = data.Icon
			for _, child in ipairs(ui.IconHolder:GetChildren()) do
				child:Destroy()
			end
			Kit.Icon(ui.IconHolder, data.Icon, { Size = UDim2.fromScale(1, 1), ZIndex = 6, Color = WHITE })
		end
		-- kicker
		local kicker
		if replay then
			kicker = F("HOW TO PLAY · %d / %d", index + 1, TC.LastStep + 1)
		elseif os.clock() < state.CompleteFlash then
			kicker = T("✓ TASK DONE!")
		elseif index == 0 then
			kicker = T("TUTORIAL")
		elseif index >= TC.LastStep then
			kicker = T("TUTORIAL COMPLETE")
		else
			kicker = F("TUTORIAL · TASK %d / %d", index, TASKS)
		end
		ui.Kicker.Text = kicker
		ui.Band.BackgroundColor3 = os.clock() < state.CompleteFlash and GREEN or BLUE
		ui.Title.Text = data.Title
		ui.Body.Text = data.Body
		for _, object in ipairs({ ui.Body, ui.Objective, ui.Info, ui.Error, ui.Hint, ui.Primary.Instance, ui.Secondary.Instance }) do
			object.Visible = not collapsed
		end
		for _, dot in ipairs(ui.Dots) do
			dot.Visible = not collapsed
		end
		ui.Collapse:SetText(collapsed and "+" or "–")
		ui.Collapse.Instance.Visible = not replay
		-- objective
		local fraction, barText, info = progress(index)
		ui.Goal.Text = data.Objective
		local done = index >= TC.LastStep
		ui.Check.Text = done and "✓" or "○"
		ui.Check.TextColor3 = done and GREEN or BLUE
		ui.Bar:SetValue(fraction)
		ui.Bar:SetText(barText)
		ui.Bar.Instance.Visible = not collapsed and index > 0 and not replay
		ui.Info.Text = (not replay and info) or ""
		ui.Error.Text = (not replay and state.Error) or ""
		ui.Info.Visible = not collapsed and ui.Info.Text ~= ""
		ui.Error.Visible = not collapsed and ui.Error.Text ~= ""
		paintDots(index)
		-- buttons
		local primary, secondary = ui.Primary, ui.Secondary
		local pending = state.Pending ~= nil and state.Pending.Manual
		local hint = ""
		if replay then
			primary:SetText(index >= TC.LastStep and T("DONE") or T("NEXT"))
			primary:SetStyle("primary")
			secondary:SetText(index > 0 and T("BACK") or T("CLOSE"))
			secondary.Instance.Visible = not collapsed
			secondary:SetDisabled(false)
			secondary.Props.Hold = nil
		else
			if state.Failed then
				primary:SetText(T("RETRY"))
				primary:SetStyle("gold")
			elseif index == 0 then
				primary:SetText(T("START"))
				primary:SetStyle("success")
			elseif index >= TC.LastStep then
				primary:SetText(T("FINISH"))
				primary:SetStyle("success")
			else
				primary:SetText(actionText(data.Action))
				primary:SetStyle("primary")
			end
			secondary.Instance.Visible = not collapsed and index < TC.LastStep
			-- leaving the whole tutorial is a hold (it cannot be undone); skipping one step is a tap
			secondary.Props.Hold = index == 0 and 1 or nil
			if index == 0 then
				secondary:SetText(T("SKIP TUTORIAL"))
				secondary:SetDisabled(false)
				hint = T("Already know the game? Hold SKIP TUTORIAL.")
			elseif index < TC.LastStep then
				local left = skipRemaining()
				local isLucky = index == TC.StepOfKey("LuckyPad")
				local open = left <= 0 or (isLucky and state.NoPad)
				if isLucky then
					secondary:SetText(open and T("CLAIM FREE BLOCK") or F("CLAIM IN %s", mmss(left)))
				else
					secondary:SetText(open and T("SKIP THIS STEP") or F("SKIP IN %s", mmss(left)))
				end
				secondary:SetDisabled(not open)
				if not open and left <= TC.SkipAfter - 30 then
					hint = T("Stuck? You can skip this step soon.")
				end
			end
			if state.Focusing then
				hint = T("Tap anywhere to skip")
			end
		end
		ui.Hint.Text = collapsed and "" or hint
		ui.Hint.Visible = ui.Hint.Text ~= ""
		primary:SetBusy(pending)
		secondary:SetBusy(false)
		if pending then
			secondary:SetDisabled(true)
		end
		layout()
	end
	render = function()
		if not state.Alive then
			return
		end
		local ok, err = pcall(renderCard)
		if not ok then
			warnOnce("render", err)
		end
	end

	------------------------------------------------------------------------------------------------------------------
	-- The tick: reports, retargeting, timers
	------------------------------------------------------------------------------------------------------------------
	local VIEW_MENUS = { Inventory = { Inventory = true, InventoryDetail = true }, Layers = { Layers = true }, DogDex = { DogDex = true, DexEntry = true }, Trade = { Trade = true } }
	local function checkView()
		if state.Replay ~= nil or not serverActive() or state.Background then
			return
		end
		local index = serverStep()
		local step = TC.Steps[index]
		if not step or step.Kind ~= "View" then
			return
		end
		local open = gui:GetAttribute("OpenMenu")
		local menus = VIEW_MENUS[step.Key]
		if type(open) == "string" and menus and menus[open] then
			local last = state.SeenAt[step.Key] or -10
			if os.clock() - last >= TC.ArriveRetry then
				state.SeenAt[step.Key] = os.clock()
				request("Seen", { Key = step.Key }, false)
			end
		end
	end
	local function checkArrive()
		if state.Replay ~= nil or not serverActive() or state.Background then
			return
		end
		local index = serverStep()
		local step = TC.Steps[index]
		if not step or step.Kind ~= "Arrive" then
			return
		end
		local root = rootPart()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end
		local radius = TC.Arrive[step.Key].Radius
		for _, point in ipairs(arrivePoints(step.Key)) do
			if (point - root.Position).Magnitude <= radius then
				if os.clock() - state.ArriveAt >= TC.ArriveRetry then
					state.ArriveAt = os.clock()
					request("Arrive", { Key = step.Key }, false)
				end
				return
			end
		end
	end
	-- A dog picked on the tongue stays the target while it is still for sale and affordable (no marker hopping
	-- between dogs as they walk past each other).
	local function stillValid(target: any): boolean
		local dog = target and target.Moving and target.Instance
		if not dog or not dog.Parent then
			return false
		end
		local price = tonumber(dog:GetAttribute("CurrentPrice"))
		local owner = dog:GetAttribute("OwnerUserId")
		return price ~= nil and price <= coins() and (owner == nil or owner == 0) and dog:GetAttribute("State") == "OnLine"
			and dog:GetAttribute("PurchaseBusy") ~= true
	end
	local function retarget()
		local index = currentStep()
		if not hasWorld(index) or not state.Entered then
			return
		end
		local target = state.Target
		local gone = target and target.Instance and not target.Instance.Parent
		local due = os.clock() >= state.RetargetAt
		if not gone and not due then
			return
		end
		state.RetargetAt = os.clock() + TC.RetargetEvery
		if target and target.Moving and stillValid(target) then
			return
		end
		local fresh = resolveTarget(index)
		if fresh and (not target or fresh.Instance ~= target.Instance or fresh.Label ~= target.Label) then
			-- a better target appeared (an affordable dog, the ore after buying the pickaxe, a free pad, the yard)
			local first = not target or target.Fallback
			applyTarget(index, fresh)
			if first and state.Replay == nil then
				showPath(index) -- e.g. the yard was assigned after the step began
			end
		elseif not fresh and gone then
			applyTarget(index, anchorFallback(index))
		end
	end
	local function tick()
		if not ui.Layer or not ui.Layer.Parent then
			return
		end
		checkView()
		checkArrive()
		retarget()
		updateDistance()
		-- the pending focus waits for a visible card and a free camera (the arrival camera, a menu)
		if state.FocusPending then
			if os.clock() > state.FocusDeadline then
				state.FocusPending = false
			elseif wanted() and not blocked() and not state.Collapsed and state.Target then
				local cam = workspace.CurrentCamera
				if cam and cam.CameraType == Enum.CameraType.Custom then
					state.FocusPending = false
					playFocus(state.Target)
				end
			end
		end
		render()
	end

	------------------------------------------------------------------------------------------------------------------
	-- Wiring
	------------------------------------------------------------------------------------------------------------------
	buildLayer()
	for _, name in ipairs({ "TutorialStep", "TutorialActive", "TutorialStatus", "TutorialStepAt", "TutorialSkippable", "TutorialVersion", "EconomyReady",
		"YardId", "MiningPickaxeOwned", "Level", "ItemCount" }) do
		connect(player:GetAttributeChangedSignal(name), function()
			if name == "MiningPickaxeOwned" or name == "YardId" then
				state.RetargetAt = 0
			elseif name == "EconomyReady" and player:GetAttribute("EconomyReady") == true then
				-- the first card waits a moment after the profile loads (the arrival camera settles)
				state.ShowAfter = math.max(state.ShowAfter, os.clock() + TC.ShowAfter)
			end
			render()
		end)
	end
	for _, name in ipairs({ "OpenMenu", "ModalOwnerCount", "MiningActive", "UIHidden", "CinemaActive", "HUDInnerLeft", "HUDInnerRight" }) do
		connect(gui:GetAttributeChangedSignal(name), function()
			if name == "OpenMenu" then
				checkView()
				if gui:GetAttribute("OpenMenu") ~= nil then
					cancelFocus() -- a menu takes the screen: never keep the camera
				end
			end
			render()
		end)
	end
	connect(GuiService:GetPropertyChangedSignal("TopbarInset"), render)
	connect(UserInputService:GetPropertyChangedSignal("TouchEnabled"), render)
	connect(player.CharacterRemoving, function()
		cancelFocus()
	end)
	connect(player.CharacterAdded, function()
		-- rebind: re-resolve the target (yard parts, the dog line) for the new character
		task.delay(1, function()
			if not state.Alive then
				return
			end
			state.RetargetAt = 0
			local index = currentStep()
			if state.Entered and hasWorld(index) then
				setupWorld(index, state.Token, false, false)
			end
			render()
		end)
	end)
	local function stop()
		if not state.Alive then
			return
		end
		state.Alive = false
		cancelFocus()
		clearWorld()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		for _, c in ipairs(ui.LayerConnections or {}) do
			c:Disconnect()
		end
		if ringTween then
			ringTween:Cancel()
		end
		if ui.Layer then
			pcall(function()
				ui.Layer:Destroy()
			end)
		end
		if world.Folder then
			pcall(function()
				world.Folder:Destroy()
			end)
		end
		if controller and controller.State == state then
			controller = nil
		end
	end
	-- the main ScreenGui going away ends this director (GUIIntegration starts a new one with the new gui)
	connect(gui.Destroying, stop)
	task.spawn(function()
		while state.Alive do
			local ok, err = pcall(tick)
			if not ok then
				warnOnce("tick", err)
			end
			task.wait(TC.Tick)
		end
	end)

	local self = {
		State = state,
		Stop = stop,
		-- HOW TO PLAY: the same cards, client only, from the first one
		Replay = function()
			pcall(function()
				navigation.Close()
			end)
			state.Replay = 0
			state.Collapsed = false
			state.ShowAfter = 0
			state.Error = nil
			state.Failed = nil
			render()
		end,
		Render = render,
	}
	controller = self
	render()
	return self
end

return Director
