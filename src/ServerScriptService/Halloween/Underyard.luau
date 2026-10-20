-- THE UNDERYARD — zone server (ServerScriptService.Halloween.Underyard; docs/halloween2/DESIGN.md §6.6, §7.2, §22.3).
-- * Portal both ways: the church DESCEND prompt (38_DeadYard.Anchors.Portal, created here when the saved anchor is
--   absent) and the arrival arch ASCEND prompt (40_Underyard.Anchors.ReturnPortal). The move streams the target area
--   in (RequestStreamAroundAsync, bounded) and pivots the character while the client's transition is black.
-- * Presence at 4 Hz: player attributes UyInZone / UyDistrict, UY.OnEnter / UY.OnLeave, Signal C2Zone {Inside, District}.
-- * Per-player district gating (0.5 s): a player inside a district whose seal they have not broken is put back in
--   front of its gate (UnderyardLayout.Unlock; the Black Bell Assault and running trials may open a district).
-- * A player who died in the Underyard less than Zone.RespawnWindow seconds ago respawns at the arrival arch; a fall
--   below Zone.VoidY inside the zone footprint is recovered there too.
-- * The practice ring in Bell Square: stepping in shows Event HP (EventHP zone "Practice") and completes the onboarding
--   step "Practice".
-- * UY.Prompt(anchorName, props, fn): server prompts on 40_Underyard.Anchors parts (created from UnderyardLayout when a
--   saved anchor is missing). ActionText / ObjectText are English; attributes ActionTextRU / ObjectTextRU carry the
--   Russian for the client (Chapter2State localizes every prompt that has them).
-- Signals: C2Zone {Inside, District}, C2Portal {Dir = "Down"|"Up", Stage = "Start"|"Arrived"|"Failed", District?}.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local UY = {}
UY.Layout = Layout

local core: any = nil
local modules: any = nil
local ram: { [Player]: any } = {}
local enterFns: { (Player) -> () } = {}
local leaveFns: { (Player) -> () } = {}
local allowFns: { (Player, string) -> boolean } = {}

local function C2(): any
	return modules and modules.Chapter2
end

local function stateOf(player: Player): any
	local st = ram[player]
	if not st then
		st = { Inside = false, District = "", GraceUntil = 0, PortalAt = -1e9, Busy = false, DiedAt = -1e9, Practice = false,
			ToastAt = -1e9 }
		ram[player] = st
	end
	return st
end

local function toast(player: Player, text: string)
	local c2 = C2()
	if c2 then
		c2.Toast(player, text)
	elseif core then
		core.Signal(player, "C2Toast", { Text = text })
	end
end

local function signal(player: Player, kind: string, data: any)
	if core then
		core.Signal(player, kind, data)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- World + anchors
---------------------------------------------------------------------------------------------------------------------
local function district(): Instance?
	return workspace:FindFirstChild("DOGROTS_District")
end

function UY.Root(): Model?
	local d = district()
	local root = d and d:FindFirstChild("40_Underyard")
	return root and root:IsA("Model") and root or nil
end

-- the anchor part `name` of 40_Underyard.Anchors (created from UnderyardLayout.Anchors when it is missing)
function UY.Anchor(name: string): BasePart?
	local root = UY.Root()
	if not root then
		return nil
	end
	local anchors = root:FindFirstChild("Anchors")
	if not anchors then
		anchors = Instance.new("Folder")
		anchors.Name = "Anchors"
		anchors.Parent = root
	end
	local part = anchors:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end
	local pos = Layout.Anchor(name)
	if not pos then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	p.Parent = anchors
	return p
end

-- props = {Name?, ActionText, ObjectText, ActionTextRU?, ObjectTextRU?, HoldDuration?, MaxActivationDistance?,
--          KeyboardKeyCode?, Eligible = true (refuse players without Chapter I), Attributes = {}?}
local function makePrompt(anchor: BasePart, key: string, props: { [string]: any }, fn: (Player, ProximityPrompt) -> ()): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = props.Name or ("Uy" .. key .. "Prompt")
	prompt.ActionText = props.ActionText or "OPEN"
	prompt.ObjectText = props.ObjectText or ""
	prompt.HoldDuration = props.HoldDuration or 0
	prompt.MaxActivationDistance = props.MaxActivationDistance or 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = props.KeyboardKeyCode or Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("UyPrompt", key)
	if props.ActionTextRU then
		prompt:SetAttribute("ActionTextRU", props.ActionTextRU)
	end
	if props.ObjectTextRU then
		prompt:SetAttribute("ObjectTextRU", props.ObjectTextRU)
	end
	for k, v in pairs(props.Attributes or {}) do
		prompt:SetAttribute(k, v)
	end
	prompt.Parent = anchor
	local busy: { [Player]: boolean } = {}
	prompt.Triggered:Connect(function(player)
		if busy[player] then
			return
		end
		if props.AllowClosed ~= true and not Shared.Chapter2Enabled() then
			toast(player, "Chapter II is closed")
			return
		end
		local c2 = C2()
		if props.Eligible ~= false and not (c2 and c2.Eligible(player)) then
			toast(player, "Finish Chapter I first")
			return
		end
		busy[player] = true
		task.spawn(function()
			local ok, err = pcall(fn, player, prompt)
			busy[player] = nil
			if not ok then
				warn("Underyard prompt " .. key .. " failed: " .. tostring(err))
			end
		end)
	end)
	return prompt
end

function UY.Prompt(anchorName: string, props: { [string]: any }, fn: (Player, ProximityPrompt) -> ()): ProximityPrompt?
	local anchor = UY.Anchor(anchorName)
	if not anchor then
		warn("Underyard: no anchor " .. tostring(anchorName) .. " (40_Underyard missing?)")
		return nil
	end
	return makePrompt(anchor, anchorName, props or {}, fn)
end

-- the church portal anchor (38_DeadYard.Anchors.Portal), created at UnderyardLayout.Church.Portal when absent
local function churchAnchor(): BasePart?
	local d = district()
	local yard = d and d:FindFirstChild("38_DeadYard")
	if not yard then
		return nil
	end
	local anchors = yard:FindFirstChild("Anchors")
	if not anchors then
		anchors = Instance.new("Folder")
		anchors.Name = "Anchors"
		anchors.Parent = yard
	end
	local part = anchors:FindFirstChild("Portal")
	if part and part:IsA("BasePart") then
		return part
	end
	local p = Instance.new("Part")
	p.Name = "Portal"
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(Layout.Church.Portal)
	p.Parent = anchors
	return p
end

---------------------------------------------------------------------------------------------------------------------
-- Presence
---------------------------------------------------------------------------------------------------------------------
local function rootOf(player: Player): BasePart?
	return core and core.Root(player) or nil
end

function UY.InZone(player: Player): boolean
	local st = ram[player]
	if st then
		return st.Inside == true
	end
	local root = rootOf(player)
	return root ~= nil and Layout.InZone(root.Position, 2)
end

function UY.District(player: Player): string?
	local st = ram[player]
	if st and st.Inside and st.District ~= "" then
		return st.District
	end
	local root = rootOf(player)
	return root and Layout.District(root.Position) or nil
end

function UY.Players(): { Player }
	local out = {}
	for player, st in pairs(ram) do
		if st.Inside and player.Parent then
			table.insert(out, player)
		end
	end
	return out
end

function UY.OnEnter(fn: (Player) -> ())
	table.insert(enterFns, fn)
end

function UY.OnLeave(fn: (Player) -> ())
	table.insert(leaveFns, fn)
end

-- other modules may open a district for a player (fn(player, district) -> true): the Assault, door rooms, ...
function UY.AllowDistrict(fn: (Player, string) -> boolean)
	table.insert(allowFns, fn)
end

function UY.Unlocked(player: Player, districtName: string): boolean
	local c2 = C2()
	local cleared = c2 and c2.ClearedCount(player) or (tonumber(player:GetAttribute("UySeals")) or 0)
	if Rules.DistrictUnlocked(cleared, districtName, Layout.Unlock) then
		return true
	end
	-- a running trial that lives in this district (Seals) and the Black Bell Assault open it. A "*" trial (Choir Hunt)
	-- roams only the districts the player has already unlocked, so it opens nothing.
	local Seals = modules and modules.Seals
	local run = Seals and Seals.RunOf and Seals.RunOf(player)
	if run and run.State == "Running" and run.Def and run.Def.District == districtName then
		return true
	end
	if districtName == "BlackBellArena" then
		local st = Halloween:FindFirstChild("State")
		local assault = st and st:FindFirstChild("Assault")
		if assault and assault:GetAttribute("State") == "Active" then
			return true
		end
	end
	for _, fn in ipairs(allowFns) do
		local ok, res = pcall(fn, player, districtName)
		if ok and res == true then
			return true
		end
	end
	return false
end

local function fire(list: { (Player) -> () }, player: Player)
	for _, fn in ipairs(list) do
		task.spawn(function()
			local ok, err = pcall(fn, player)
			if not ok then
				warn("Underyard enter/leave hook failed: " .. tostring(err))
			end
		end)
	end
end

local function inCombat(player: Player): boolean
	local EventHP = modules and modules.EventHP
	if EventHP and type(EventHP.InCombat) == "function" then
		local ok, res = pcall(EventHP.InCombat, player)
		return ok and res == true
	end
	return player:GetAttribute("HwCombat") == true
end
UY.InCombat = inCombat

local function eventHP(method: string, player: Player, zoneId: string, opts: any?)
	local EventHP = modules and modules.EventHP
	local fn = EventHP and EventHP[method]
	if type(fn) == "function" then
		local ok, err = pcall(fn, player, zoneId, opts)
		if not ok then
			warn("Underyard: EventHP." .. method .. " failed: " .. tostring(err))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Teleports
---------------------------------------------------------------------------------------------------------------------
-- RequestStreamAroundAsync (bounded, never fatal) + PivotTo + zero velocity + a short grace for the zone polls.
-- opts = {Delay = s (minimum wait before the move), StreamTimeout = s, NoStream = bool}
function UY.Teleport(player: Player, cf: any, opts: { [string]: any }?): boolean
	local o: { [string]: any } = opts or {}
	local target: CFrame = typeof(cf) == "Vector3" and CFrame.new(cf) or cf
	if typeof(target) ~= "CFrame" then
		return false
	end
	local ch = player.Character
	local root = rootOf(player)
	if not ch or not root then
		return false
	end
	local t0 = os.clock()
	local streamed = o.NoStream == true
	if not streamed then
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(target.Position, o.StreamTimeout or Cfg.Portal.StreamTimeout)
			end)
			streamed = true
		end)
	end
	local limit = o.StreamTimeout or Cfg.Portal.StreamTimeout
	while (not streamed and os.clock() - t0 < limit) or os.clock() - t0 < (o.Delay or 0) do
		task.wait(.05)
	end
	-- the character may have died / respawned meanwhile
	root = rootOf(player)
	if not root or player.Character ~= ch or not ch.Parent then
		return false
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
	end
	stateOf(player).GraceUntil = os.clock() + Cfg.Portal.Grace + .25
	ch:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function arrivalCFrame(): CFrame
	local part = Layout.AnchorPart("Arrival")
	if part then
		local look = Layout.Arrival.LookVector
		return CFrame.lookAt(part.Position, part.Position + Vector3.new(look.X, 0, look.Z))
	end
	return Layout.Arrival
end

local function forecourtCFrame(): CFrame
	local pos = Layout.Church.Forecourt
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)) -- facing away from the church, towards the pit
end

local function portalGuard(player: Player, st: any): (boolean, string?)
	if st.Busy or os.clock() - st.PortalAt < Cfg.Portal.Cooldown then
		return false, "Please wait a moment"
	end
	if inCombat(player) then
		return false, "You can't use the portal during a fight"
	end
	if not rootOf(player) then
		return false, "Wait for your character"
	end
	return true, nil
end

function UY.Descend(player: Player): (boolean, string?)
	if not Shared.Chapter2Enabled() then
		return false, "Chapter II is closed"
	end
	local c2 = C2()
	if not c2 or not c2.Eligible(player) then
		return false, "Finish Chapter I first"
	end
	if player:GetAttribute("Chapter2RevealSeen") ~= true then
		signal(player, "C2Reveal", { Need = "Church" }) -- the client plays the church cinematic first (§6.3)
		return false, "Watch the church first"
	end
	if not UY.Root() then
		return false, "The Underyard is not ready yet"
	end
	local st = stateOf(player)
	local ok, why = portalGuard(player, st)
	if not ok then
		return false, why
	end
	st.Busy, st.PortalAt = true, os.clock()
	signal(player, "C2Portal", { Dir = "Down", Stage = "Start" })
	task.spawn(function()
		local moved = UY.Teleport(player, arrivalCFrame(), { Delay = Cfg.Portal.TransitionDelay })
		st.Busy = false
		if moved then
			st.PortalAt = os.clock()
			signal(player, "C2Portal", { Dir = "Down", Stage = "Arrived", District = "BellSquare" })
			c2.MarkEntered(player) -- Entered, journal "descend", the onboarding starts (after the client fades in)
		else
			signal(player, "C2Portal", { Dir = "Down", Stage = "Failed" })
		end
	end)
	return true, nil
end

-- always allowed (also with Chapter II switched off): nobody is ever stuck below
function UY.Ascend(player: Player): (boolean, string?)
	local st = stateOf(player)
	local ok, why = portalGuard(player, st)
	if not ok then
		return false, why
	end
	local Seals = modules and modules.Seals
	if Seals and type(Seals.Leave) == "function" then
		pcall(Seals.Leave, player, "Ascend")
	end
	st.Busy, st.PortalAt = true, os.clock()
	signal(player, "C2Portal", { Dir = "Up", Stage = "Start" })
	task.spawn(function()
		local moved = UY.Teleport(player, forecourtCFrame(), { Delay = Cfg.Portal.TransitionDelay })
		st.Busy = false
		if moved then
			st.PortalAt = os.clock()
			signal(player, "C2Portal", { Dir = "Up", Stage = "Arrived", District = "" })
		else
			signal(player, "C2Portal", { Dir = "Up", Stage = "Failed" })
		end
	end)
	return true, nil
end

---------------------------------------------------------------------------------------------------------------------
-- Zone polls
---------------------------------------------------------------------------------------------------------------------
local function inFootprint(pos: Vector3): boolean
	local m = Cfg.Zone.FootprintMargin
	local a, b = Layout.Zone.Min, Layout.Zone.Max
	return pos.X >= a.X - m and pos.X <= b.X + m and pos.Z >= a.Z - m and pos.Z <= b.Z + m
end

local function numeral(n: number): string
	local seal = Cfg.Seals[n]
	return seal and seal.Numeral or tostring(n)
end

local function presence(player: Player, st: any)
	local root = rootOf(player)
	local pos = root and root.Position
	local inside = pos ~= nil and Layout.InZone(pos, 2)
	local where = inside and (Layout.District(pos :: Vector3) or "BellSquare") or ""
	if inside ~= st.Inside or where ~= st.District then
		local entered = inside ~= st.Inside
		st.Inside, st.District = inside, where
		core.SetAttr(player, "UyInZone", inside)
		core.SetAttr(player, "UyDistrict", where)
		signal(player, "C2Zone", { Inside = inside, District = where })
		if entered then
			fire(inside and enterFns or leaveFns, player)
		end
	end
	-- the practice ring (Event HP preview + onboarding step "Practice"); a running trial owns the player's combat zone
	local c2 = C2()
	local Seals = modules and modules.Seals
	local inRun = Seals and Seals.RunOf and Seals.RunOf(player) ~= nil
	local practice = inside and where == "BellSquare" and not inRun and c2 ~= nil and c2.InPracticeRing(player)
	if practice and not st.Practice then
		st.Practice = true
		eventHP("Enter", player, Cfg.Combat.PracticeZone)
		c2.TutorialEvent(player, "Practice")
	elseif not practice and st.Practice then
		st.Practice = false
		eventHP("Leave", player, Cfg.Combat.PracticeZone)
	end
	-- void / fall recovery inside the zone footprint
	if pos and inFootprint(pos) and pos.Y < Cfg.Zone.VoidY and pos.Y > -400 and os.clock() > st.GraceUntil then
		st.GraceUntil = os.clock() + 2
		task.spawn(function()
			if UY.Teleport(player, arrivalCFrame(), { NoStream = true }) then
				toast(player, "The Underyard pulled you back up")
			end
		end)
	end
end

local function gate(player: Player, st: any)
	if not st.Inside or st.District == "" or st.District == "BellSquare" or os.clock() < st.GraceUntil then
		return
	end
	if UY.Unlocked(player, st.District) then
		return
	end
	local g = Layout.Gates[st.District]
	if not g then
		return
	end
	local back = g.Position - g.Facing * Cfg.Zone.GatePush + Vector3.new(0, 3.2, 0)
	st.GraceUntil = os.clock() + 1
	task.spawn(function()
		UY.Teleport(player, CFrame.lookAt(back, back - g.Facing), { NoStream = true })
	end)
	if os.clock() - st.ToastAt > 3 then
		st.ToastAt = os.clock()
		toast(player, "SEALED · BELL SEAL " .. numeral(Layout.Unlock[st.District] or 1))
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Respawn into the zone
---------------------------------------------------------------------------------------------------------------------
local function watchCharacter(player: Player, ch: Model)
	local st = stateOf(player)
	local hum = ch:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Connect(function()
			local root = ch:FindFirstChild("HumanoidRootPart")
			local pos = root and (root :: BasePart).Position
			if (pos and Layout.InZone(pos, 2)) or st.Inside then
				st.DiedAt = os.clock()
			end
		end)
	end
	if os.clock() - st.DiedAt < Cfg.Zone.RespawnWindow and Shared.Chapter2Enabled() then
		st.DiedAt = -1e9
		local c2 = C2()
		if c2 and c2.Eligible(player) and UY.Root() then
			local root = ch:WaitForChild("HumanoidRootPart", 10)
			if root then
				task.wait(.25)
				if player.Character == ch then
					UY.Teleport(player, arrivalCFrame(), {})
				end
			end
		end
	end
end

local function track(player: Player)
	stateOf(player)
	player.CharacterAdded:Connect(function(ch)
		task.spawn(watchCharacter, player, ch)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function UY.Start(c: any, m: any)
	core, modules = c, m
	if not Shared.Chapter2Enabled() then
		return
	end
	-- the church DESCEND prompt (prompt visibility per player is client-side; ineligible players are refused here)
	local church = churchAnchor()
	if church then
		makePrompt(church, "Portal", {
			Name = "UnderyardDescendPrompt", ActionText = "DESCEND", ObjectText = "THE UNDERYARD", ActionTextRU = "СПУСТИТЬСЯ",
			ObjectTextRU = "ПОДДВОРЬЕ", HoldDuration = Cfg.Portal.HoldDuration, MaxActivationDistance = Cfg.Portal.Range,
			Attributes = { C2Portal = "Down", HalloweenPrompt = "Portal" },
		}, function(player)
			local ok, err = UY.Descend(player)
			if not ok and err and err ~= "Watch the church first" then
				toast(player, err)
			end
		end)
	else
		warn("Underyard: 38_DeadYard missing, no church portal")
	end
	-- the arrival arch ASCEND prompt (always works, even for a player who somehow lost eligibility)
	UY.Prompt("ReturnPortal", {
		Name = "UnderyardAscendPrompt", ActionText = "ASCEND", ObjectText = "THE DEAD YARD", ActionTextRU = "ПОДНЯТЬСЯ",
		ObjectTextRU = "МЁРТВЫЙ ДВОР", HoldDuration = Cfg.Portal.HoldDuration, MaxActivationDistance = Cfg.Portal.Range,
		Eligible = false, AllowClosed = true, Attributes = { C2Portal = "Up" },
	}, function(player)
		local ok, err = UY.Ascend(player)
		if not ok and err then
			toast(player, err)
		end
	end)
	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ram[player] = nil
	end)
	task.spawn(function()
		local gateAt = 0
		while true do
			task.wait(Cfg.Zone.PresenceRate)
			local now = os.clock()
			local doGate = now - gateAt >= Cfg.Zone.GateRate
			if doGate then
				gateAt = now
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local st = stateOf(player)
				local ok, err = pcall(presence, player, st)
				if not ok then
					warn("Underyard presence failed: " .. tostring(err))
				end
				if doGate and Shared.Chapter2Enabled() then
					local okGate, errGate = pcall(gate, player, st)
					if not okGate then
						warn("Underyard gating failed: " .. tostring(errGate))
					end
				end
			end
		end
	end)
end

return UY
