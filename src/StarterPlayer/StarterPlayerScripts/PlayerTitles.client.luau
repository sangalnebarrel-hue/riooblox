-- Player titles above every character (docs/TITLES.md). The server projects the equipped title id as
-- the player attribute TitleId (Economy.Features.Titles); this script draws it for everyone with
-- ReplicatedStorage.TitleBadge in a BillboardGui on the character's Head:
--   * depth-tested (AlwaysOnTop off), hidden beyond MaxDistance 90 studs, its size part studs and part
--     pixels so it shrinks a little with distance;
--   * rarity styling (TitleDefinitions.Styles); the animated ones (Legendary, Mythic, Secret) move only
--     within 50 studs of the camera, at most 12 at once (the nearest), through TitleBadge's single
--     shared Heartbeat; Low FX and Reduced Motion keep every badge still;
--   * your own title hides in first person (the camera fades your head: LocalTransparencyModifier).
-- Characters: CharacterAdded / CharacterRemoving and TitleId changes rebuild only that player's badge.
-- The animated set is re-chosen twice a second (no per-frame work while nothing animates).
-- Also starts the TITLES window's unlock toasts (TitlesScreen.Watch).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Localization = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local Titles = require(RS:WaitForChild("DogEconomy"):WaitForChild("TitleDefinitions"))
local Badge = require(RS:WaitForChild("TitleBadge"))

local player = Players.LocalPlayer
local MAX_DISTANCE = 90
local ANIMATE_DISTANCE = 50
local MAX_ANIMATED = 12
local HEIGHT_STUDS, HEIGHT_PIXELS = 0.55, 12
local OFFSET = Vector3.new(0, 3.1, 0)

-- Title billboards live directly in PlayerGui with ResetOnSpawn = false: a respawn clears
-- PlayerGui's resettable children, and a plain Folder holder is not guaranteed to survive it.
local holder = player:WaitForChild("PlayerGui")

local function lang(): string
	local ok, locale = pcall(function()
		if RunService:IsStudio() then
			return Localization.RobloxLocaleId
		end
		return player.LocaleId ~= "" and player.LocaleId or Localization.RobloxLocaleId
	end)
	return ok and type(locale) == "string" and string.lower(string.sub(locale, 1, 2)) == "ru" and "ru" or "en"
end

local function stillFX(): boolean
	return player:GetAttribute("WorldEventFX") == "Low" or player:GetAttribute("LowFX") == true or player:GetAttribute("ReducedMotion") == true
end

type Entry = {
	Player: Player,
	Gui: BillboardGui?,
	Badge: any,
	Head: BasePart?,
	Def: any,
	Connections: { RBXScriptConnection },
	HeadConnection: RBXScriptConnection?,
	FirstPerson: boolean,
	Bound: Model?,
}
local entries: { [Player]: Entry } = {}

local function setEnabled(e: Entry)
	if e.Gui then
		e.Gui.Enabled = e.Def ~= nil and e.Head ~= nil and e.Head.Parent ~= nil and not e.FirstPerson
	end
end

local function refresh(e: Entry)
	local def = Titles.Get(e.Player:GetAttribute("TitleId"))
	e.Def = def
	if not def then
		if e.Badge then
			e.Badge:SetAnimated(false)
		end
		setEnabled(e)
		return
	end
	if not e.Gui then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Title_" .. e.Player.UserId
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = MAX_DISTANCE
		gui.StudsOffsetWorldSpace = OFFSET
		gui.ResetOnSpawn = false
		gui:SetAttribute("NoTranslate", true)
		gui.Parent = holder
		e.Gui = gui
		e.Badge = Badge.new(gui, { ZIndex = 1 })
	end
	local gui = e.Gui :: BillboardGui
	local aspect = e.Badge:Set(def, lang())
	gui.Size = UDim2.new(HEIGHT_STUDS * aspect, math.floor(HEIGHT_PIXELS * aspect), HEIGHT_STUDS, HEIGHT_PIXELS)
	gui.Adornee = e.Head
	setEnabled(e)
end

local function bindHead(e: Entry, character: Model?)
	if e.HeadConnection then
		e.HeadConnection:Disconnect()
		e.HeadConnection = nil
	end
	e.Head = nil
	e.Bound = character
	e.FirstPerson = false
	if e.Gui then
		local gui: any = e.Gui
		gui.Adornee = nil
	end
	setEnabled(e)
	if not character then
		return
	end
	task.spawn(function()
		local head = character:WaitForChild("Head", 10)
		if not head or not head:IsA("BasePart") or entries[e.Player] ~= e or e.Player.Character ~= character then
			return
		end
		e.Head = head
		if e.Player == player then
			-- The default camera fades your own head in first person: hide your title with it.
			local function check()
				e.FirstPerson = head.LocalTransparencyModifier > 0.9
				setEnabled(e)
			end
			e.HeadConnection = head:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(check)
			check()
		end
		refresh(e)
	end)
end

local function track(p: Player)
	if entries[p] then
		return
	end
	local e: Entry = { Player = p, Gui = nil, Badge = nil, Head = nil, Def = nil, Connections = {}, HeadConnection = nil, FirstPerson = false, Bound = nil }
	entries[p] = e
	table.insert(e.Connections, p:GetAttributeChangedSignal("TitleId"):Connect(function()
		refresh(e)
	end))
	table.insert(e.Connections, p.CharacterAdded:Connect(function(character)
		bindHead(e, character)
	end))
	-- A far player's character can reach this client by streaming after CharacterAdded fired;
	-- the Character property still changes, so bind on that too (once per character).
	table.insert(e.Connections, p:GetPropertyChangedSignal("Character"):Connect(function()
		local character = p.Character
		if character and e.Bound ~= character then
			bindHead(e, character)
		end
	end))
	table.insert(e.Connections, p.CharacterRemoving:Connect(function()
		bindHead(e, nil)
	end))
	bindHead(e, p.Character)
	refresh(e)
end

local function untrack(p: Player)
	local e = entries[p]
	if not e then
		return
	end
	entries[p] = nil
	for _, c in ipairs(e.Connections) do
		c:Disconnect()
	end
	if e.HeadConnection then
		e.HeadConnection:Disconnect()
	end
	if e.Badge then
		e.Badge:Destroy()
	end
	if e.Gui then
		e.Gui:Destroy()
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(track, p)
end
Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)

-- Language changes (Studio locale switch): redraw every title.
pcall(function()
	Localization:GetPropertyChangedSignal("RobloxLocaleId"):Connect(function()
		for _, e in pairs(entries) do
			refresh(e)
		end
	end)
end)

-- Which badges animate: the nearest animated titles within ANIMATE_DISTANCE, at most MAX_ANIMATED.
task.spawn(function()
	while true do
		task.wait(0.5)
		local camera = workspace.CurrentCamera
		local still = stillFX() or Badge.Reduced()
		local candidates = {}
		for _, e in pairs(entries) do
			if e.Badge then
				local style = e.Def and Titles.Style(e.Def)
				local head = e.Head
				if not still and camera and style and style.Animated and head and head.Parent and e.Gui and e.Gui.Enabled then
					local d = (head.Position - camera.CFrame.Position).Magnitude
					if d <= ANIMATE_DISTANCE then
						table.insert(candidates, { E = e, D = d })
					else
						e.Badge:SetAnimated(false)
					end
				else
					e.Badge:SetAnimated(false)
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.D < b.D
		end)
		for i, c in ipairs(candidates) do
			c.E.Badge:SetAnimated(i <= MAX_ANIMATED)
		end
	end
end)

-- NEW TITLE UNLOCKED toasts (and the TITLES window) live in ScreenGui.Modules.TitlesScreen.
task.spawn(function()
	local gui = player.PlayerGui:WaitForChild("ScreenGui", 60)
	local modules = gui and gui:WaitForChild("Modules", 30)
	local module = modules and modules:WaitForChild("TitlesScreen", 30)
	if module then
		local ok, screen = pcall(require, module)
		if ok and type(screen) == "table" and type(screen.Watch) == "function" then
			screen.Watch()
		elseif not ok then
			warn("DOGROTS TitlesScreen: " .. tostring(screen))
		end
	end
end)
