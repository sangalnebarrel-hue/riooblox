-- CHAPTER II combat on the server (ServerScriptService.Halloween.EventHP, docs/halloween2/DESIGN.md §10.1-§10.2).
-- Event HP is a second health pool that only exists inside combat zones (the Gravekeeper pit while a fight runs, the
-- Black Bell Arena, the Hollow Mine run, Crooked Door fights, the Funeral Run pendulums, the practice ring). Humanoid
-- health is never touched and Event HP never kills: at 0 a player is DOWNED until an ally revives them, their H11 Mourning
-- Shiba self-revive fires, or they bleed out (back to the zone spawn at 60% HP, WEAKENED). Normal deaths (falls) still
-- work as before. The rules are the pure state machine RS.Halloween.CombatRules (tests/combat.luau); this module owns
-- the live states and every side effect: player attributes, walk speed, the REVIVE prompt, teleports, hazards, signals.
--
-- API (modules.EventHP; every function is safe for a player who is not in combat)
--   EventHP.SetZone(zoneId, {Spawn = Vector3|CFrame?, Name = string|{en, ru}?, Trial = true|trialId?}) -> zone
--   EventHP.Enter(player, zoneId, opts {MaxHP?, Spawn?, Name?, Trial?}?) -> ok      (Trial: true or the trial id = the 40%
--                                                     per-hit cap; HP = MaxHP; a re-enter of the same
--                                                     zone within 30 s keeps the old state)
--   EventHP.Leave(player, zoneId?) -> ok             (only that zone when given; a downed player gets up without penalty)
--   EventHP.InCombat(player) ; EventHP.Zone(player) -> zoneId? ; EventHP.Players(zoneId) -> {Player}
--   EventHP.Damage(player, amount, source, info?) -> applied, hpApplied
--       info {Kind ("Gas": H10 -30%), Tick (DPS: no i-frames), Mult, Knock = Vector3 velocity, From = Vector3}
--   EventHP.Heal(player, n) -> healed ; EventHP.Shield(player, amount, seconds?) -> shield
--   EventHP.Down(player, source?) -> ok ; EventHP.Revive(player, by?, opts {HP, Shield, Self}?) -> ok
--   EventHP.IsDowned(player) ; EventHP.CanTarget(player) (in combat and not downed: boss targeting)
--   EventHP.HP(player) -> hp, maxHP, shield ; EventHP.DamageMult(player) (WEAKENED .7) ; EventHP.TakenMult(player) (1.25)
--   EventHP.Hazard(zoneId, def) -> id ; EventHP.HazardWave(zoneId, defs) -> {id} ; EventHP.CancelHazards(zoneId, ids?)
--       def: RS.Halloween.Hazards (Shape, Telegraph, ImpactAt?, Damage, Knock?, Linger?, DPS?, Color?, Kind, Source,
--       Delay?, OnHit? [WP-C]: fn(player, dealt, knockVelocity?, pos) after each impact hit that landed).
--       ImpactAt nil = now + H10 lead + Telegraph (+ Delay), so CANDLELIGHT owners always see it .35 s early.
--       Unfair defs are made fair (Hazards.Sanitize: longer telegraph, capped damage, slower path, a ring gap) and an
--       impact never lands before its full telegraph has shown.
--   EventHP.OnDown(fn(player, zoneId, source)) / OnRevive(fn(player, zoneId, by?)) / OnBleedOut(fn(player, zoneId,
--       reason)) / OnWipe(fn(zoneId, players)) -> disconnect()
--       A wipe (every player of a zone downed) fires OnWipe once; whoever is still downed in that zone WipeGrace (1.5 s)
--       later bleeds out (reason "Wipe", OnBleedOut is not fired for those: the wipe already failed the encounter).
-- Requests: C2SelfRevive {} (H11 once per fight after 8 s downed); Studio only: C2CombatDebug {Cmd, N}.
-- Signals (core.Signal): Combat {Kind = "Enter"|"Leave"|"Hit"|"Down"|"Revive"|"BleedOut"|"Wipe"|"Shield", UserId, Zone,
--   HP, Max, Shield, Amount, Absorbed, Source, Hazard, Knock (own hits), Until, By, Weakened, Reason} to the player and
--   (Hit / Down / Revive / BleedOut) to the zone + players within NearbyRange; Hazard (Hazards.Encode payload with that
--   player's ShowAt, or {List = {...}} for a wave, or {Cancel = {ids}}) to players within HazardRange + the zone.
-- Player attributes (§3.4 + additions): HwCombat, HwCombatZone, HwHP, HwHPMax, HwShield, HwDowned, HwDownedUntil,
--   HwWeakenedUntil, HwReviveBy, HwSelfReviveAt (server time the H11 self-revive unlocks, 0 = none), HwReviveSpeed (this
--   player's revive speed as a reviver, H14 = 2). REVIVE prompt: ProximityPrompt "HwRevivePrompt" in the downed player's
--   HumanoidRootPart (attributes HwRevive, HwTargetUserId, HwTargetSpeed, HwReviveBase, HwCombatZone); clients localize
--   it, hide their own and scale HoldDuration by their HwReviveSpeed; the server checks the real hold time.
-- Dog abilities through modules.Chapter2.HasTeamDog (H10 Candle Corgi, H11 Mourning Shiba, H14 Bridehound), stats through
-- modules.Chapter2.Progress(reviver, "Revive", 1); the Strike gate "EventHP" stops downed players from striking.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Hazards = require(Halloween:WaitForChild("Hazards"))
local BossMath = require(Halloween:WaitForChild("BossMath"))
local Rules = require(Halloween:WaitForChild("CombatRules"))

local EventHP = {
	Zones = {}, States = {}, Left = {}, NextHazard = 0,
	Listeners = { Down = {}, Revive = {}, BleedOut = {}, Wipe = {} },
}
EventHP.Rules, EventHP.Hazards, EventHP.BossMath = Rules, Hazards, BossMath

local core, modules = nil, nil

-- overridable (tests drive the module with fake players, positions and a manual clock)
EventHP.Now = function(): number
	return workspace:GetServerTimeNow()
end
EventHP.RootOf = function(player: Player): BasePart?
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and hum and hum.Health > 0 then
		return root
	end
	return nil
end
EventHP.PlayerList = function(): { Player }
	return Players:GetPlayers()
end
EventHP.Send = function(target: Player, kind: string, data: any)
	if core then
		core.Signal(target, kind, data)
	end
end
-- listeners run in their own threads; the wipe fallback waits WipeGrace
EventHP.Spawn = function(fn: (...any) -> (), ...: any)
	task.spawn(fn, ...)
end
EventHP.Delay = function(seconds: number, fn: (...any) -> (), ...: any)
	task.delay(seconds, fn, ...)
end

local function cfg()
	return Rules.Config()
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function half(x: number): number
	-- shown HP in half steps, rounded up (a living player never shows 0)
	return math.ceil(x * 2 - 1e-9) / 2
end

local function round1(x: number): number
	return math.floor(x * 10 + .5) / 10
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function fire(list: { any }, ...)
	for _, fn in ipairs(table.clone(list)) do
		EventHP.Spawn(function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				warn("EventHP listener failed: " .. tostring(err))
			end
		end, ...)
	end
end

local function listen(list: { any }, fn: any): () -> ()
	assert(type(fn) == "function", "EventHP: listener must be a function")
	table.insert(list, fn)
	return function()
		local i = table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- team-dog abilities (modules.Chapter2.HasTeamDog, cached a few seconds per player)
---------------------------------------------------------------------------------------------------------------------
local dogCache = {}
-- key: "Candle" (H10) | "Mourning" (H11) | "Bride" (H14) | "Wolf" (H15)
function EventHP.HasDog(player: Player, key: string): boolean
	local c = cfg()
	local id = c.Dogs[key]
	if not id then
		return false
	end
	local clock = os.clock()
	local entry = dogCache[player]
	if not entry or clock - entry.At > c.DogRefresh then
		entry = { At = clock, Has = {} }
		dogCache[player] = entry
	end
	local v = entry.Has[id]
	if v == nil then
		v = false
		local C2 = modules and modules.Chapter2
		if type(C2) == "table" and type(C2.HasTeamDog) == "function" then
			local ok, res = pcall(C2.HasTeamDog, player, id)
			v = ok and res == true
		end
		entry.Has[id] = v
	end
	return v
end

local function progress(player: Player, key: string, n: number)
	local C2 = modules and modules.Chapter2
	if type(C2) == "table" and type(C2.Progress) == "function" then
		local ok, err = pcall(C2.Progress, player, key, n)
		if not ok then
			warn("EventHP: Chapter2.Progress failed: " .. tostring(err))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- zones
---------------------------------------------------------------------------------------------------------------------
local function toSpawn(v: any): CFrame?
	if typeof(v) == "CFrame" then
		return v
	elseif typeof(v) == "Vector3" then
		return CFrame.new(v + Vector3.new(0, 3, 0))
	end
	return nil
end

local function zoneOf(zoneId: string)
	local z = EventHP.Zones[zoneId]
	if not z then
		z = { Id = zoneId, Members = {}, Hazards = {}, Wiped = false, Trial = false }
		EventHP.Zones[zoneId] = z
	end
	return z
end

function EventHP.SetZone(zoneId: string, opts: any?)
	local z = zoneOf(tostring(zoneId))
	if type(opts) == "table" then
		z.Spawn = toSpawn(opts.Spawn) or z.Spawn
		if opts.Name ~= nil then
			z.Name = opts.Name
		end
		if opts.Trial ~= nil then
			z.Trial = opts.Trial ~= false -- true or a trial id (Seals passes def.Id)
		end
	end
	return z
end

function EventHP.Players(zoneId: string): { Player }
	local z = EventHP.Zones[zoneId]
	local out = {}
	if z then
		for pl in pairs(z.Members) do
			if EventHP.States[pl] then
				table.insert(out, pl)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.UserId < b.UserId
	end)
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- signals
---------------------------------------------------------------------------------------------------------------------
local function send(player: Player, kind: string, data: any)
	local ok, err = pcall(EventHP.Send, player, kind, data)
	if not ok then
		warn("EventHP signal failed: " .. tostring(err))
	end
end

-- the zone members + anyone within NearbyRange of `player` (floating numbers, downed markers)
local function sendAround(player: Player, zone: any, kind: string, data: any, skipSelf: boolean?)
	local sent = {}
	if zone then
		for pl in pairs(zone.Members) do
			if not (skipSelf and pl == player) then
				sent[pl] = true
				send(pl, kind, data)
			end
		end
	end
	local origin = EventHP.RootOf(player)
	if not origin then
		return
	end
	local range = cfg().NearbyRange
	for _, pl in ipairs(EventHP.PlayerList()) do
		if not sent[pl] and not (skipSelf and pl == player) then
			local r = EventHP.RootOf(pl)
			if r and (r.Position - origin.Position).Magnitude <= range then
				send(pl, kind, data)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- attributes
---------------------------------------------------------------------------------------------------------------------
local COMBAT_ATTRS = { "HwCombat", "HwCombatZone", "HwHP", "HwHPMax", "HwShield", "HwDowned", "HwDownedUntil", "HwReviveBy",
	"HwSelfReviveAt", "HwReviveSpeed" }

local function selfReviveAt(P: any): number
	local st = P.St
	if not st.Downed or st.SelfReviveUsed or not EventHP.HasDog(P.Player, "Mourning") then
		return 0
	end
	return Rules.SelfReviveAt(st, cfg())
end

local function publish(P: any)
	local pl, st = P.Player, P.St
	local c = cfg()
	local now = EventHP.Now()
	setAttr(pl, "HwCombat", true)
	setAttr(pl, "HwCombatZone", P.Zone)
	setAttr(pl, "HwHP", st.Downed and 0 or half(st.HP))
	setAttr(pl, "HwHPMax", round1(st.MaxHP))
	setAttr(pl, "HwShield", half(st.Shield))
	setAttr(pl, "HwDowned", st.Downed)
	setAttr(pl, "HwDownedUntil", st.Downed and st.DownedUntil or 0)
	setAttr(pl, "HwWeakenedUntil", st.WeakenedUntil > now and st.WeakenedUntil or 0)
	setAttr(pl, "HwReviveBy", P.ReviveBy or 0)
	setAttr(pl, "HwSelfReviveAt", selfReviveAt(P))
	setAttr(pl, "HwReviveSpeed", EventHP.HasDog(pl, "Bride") and c.H14ReviveSpeed or 1)
end

local function clearAttrs(player: Player, st: any?)
	for _, name in ipairs(COMBAT_ATTRS) do
		setAttr(player, name, nil)
	end
	local now = EventHP.Now()
	local weak = st and st.WeakenedUntil or 0
	setAttr(player, "HwWeakenedUntil", weak > now and weak or nil)
end

---------------------------------------------------------------------------------------------------------------------
-- walk speed while downed. MovementModifiers (ServerScriptService) rewrites WalkSpeed 10x a second from its own base and
-- adopts foreign writes as the new base, so while it manages this humanoid the slow speed goes through its documented
-- humanoid attribute BaseWalkSpeed (restored afterwards: its real base is never touched); otherwise WalkSpeed itself.
---------------------------------------------------------------------------------------------------------------------
local movement: any = nil
local function movementModule(): any
	if movement == nil then
		movement = false
		local inst = SSS:FindFirstChild("MovementModifiers")
		if inst and inst:IsA("ModuleScript") then
			local ok, m = pcall(require, inst)
			if ok and type(m) == "table" then
				movement = m
			end
		end
	end
	return movement or nil
end

local function humanoidOf(player: Player): Humanoid?
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function applyWalk(P: any)
	local hum = humanoidOf(P.Player)
	if not hum then
		return
	end
	if P.Walk and P.Walk.Humanoid == hum then
		return
	end
	local slow = cfg().DownedWalkSpeed
	local mm = movementModule()
	local mstate = mm and type(mm.States) == "table" and mm.States[P.Player]
	local managed = type(mstate) == "table" and mstate.Humanoid == hum
	P.Walk = { Humanoid = hum, Managed = managed, Attr = hum:GetAttribute("BaseWalkSpeed"), Speed = hum.WalkSpeed, Applied = slow }
	if managed then
		hum:SetAttribute("BaseWalkSpeed", slow)
	else
		hum.WalkSpeed = slow
	end
end

local function restoreWalk(P: any)
	local w = P.Walk
	P.Walk = nil
	if not w or not w.Humanoid or not w.Humanoid.Parent then
		return
	end
	local hum = w.Humanoid
	if w.Managed then
		hum:SetAttribute("BaseWalkSpeed", w.Attr)
	elseif math.abs(hum.WalkSpeed - w.Applied) < .01 then
		hum.WalkSpeed = w.Speed
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the REVIVE prompt
---------------------------------------------------------------------------------------------------------------------
local function removePrompt(P: any)
	for _, c in ipairs(P.PromptConns or {}) do
		c:Disconnect()
	end
	P.PromptConns = nil
	if P.Prompt then
		P.Prompt:Destroy()
		P.Prompt = nil
	end
	table.clear(P.Holds)
	P.ReviveBy = 0
end

local function canRevive(P: any, reviver: Player): boolean
	if reviver == P.Player or not P.St.Downed then
		return false
	end
	local R = EventHP.States[reviver]
	if not R or R.Zone ~= P.Zone or R.St.Downed then
		return false
	end
	local a = EventHP.RootOf(reviver)
	local b = EventHP.RootOf(P.Player)
	if not a or not b then
		return false
	end
	return (a.Position - b.Position).Magnitude <= cfg().ReviveRange + 4
end

local function holderOf(P: any): number
	local best, at = 0, math.huge
	for pl, started in pairs(P.Holds) do
		if started < at then
			best, at = pl.UserId, started
		end
	end
	return best
end

-- server side of the hold (also used by tests): began / ended / triggered by `reviver`
function EventHP.ReviveHold(target: Player, reviver: Player, stage: string): boolean
	local P = EventHP.States[target]
	if not P or not P.St.Downed then
		return false
	end
	local now = EventHP.Now()
	if stage == "Began" then
		if not canRevive(P, reviver) then
			return false
		end
		P.Holds[reviver] = now
		P.ReviveBy = holderOf(P)
		publish(P)
		return true
	elseif stage == "Ended" then
		P.Holds[reviver] = nil
		P.ReviveBy = holderOf(P)
		publish(P)
		return true
	elseif stage == "Triggered" then
		local started = P.Holds[reviver]
		P.Holds[reviver] = nil
		P.ReviveBy = holderOf(P)
		if not started or not canRevive(P, reviver) then
			publish(P)
			return false
		end
		local c = cfg()
		local mySpeed = EventHP.HasDog(reviver, "Bride") and c.H14ReviveSpeed or 1
		local targetSpeed = EventHP.HasDog(target, "Mourning") and c.H11ReviveSpeed or 1
		local need = Rules.ReviveAccept(c, Rules.ReviveHold(c, mySpeed, targetSpeed))
		if now - started + 1e-6 < need then
			publish(P)
			return false
		end
		return EventHP.Revive(target, reviver)
	end
	return false
end

local function createPrompt(P: any)
	removePrompt(P)
	local ch = P.Player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local c = cfg()
	local targetSpeed = EventHP.HasDog(P.Player, "Mourning") and c.H11ReviveSpeed or 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HwRevivePrompt"
	prompt.ActionText = "REVIVE"
	prompt.ObjectText = P.Player.DisplayName
	prompt.HoldDuration = Rules.ReviveHold(c, 1, targetSpeed)
	prompt.MaxActivationDistance = c.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("HwRevive", true)
	prompt:SetAttribute("HwTargetUserId", P.Player.UserId)
	prompt:SetAttribute("HwTargetSpeed", targetSpeed)
	prompt:SetAttribute("HwReviveBase", c.ReviveHold)
	prompt:SetAttribute("HwCombatZone", P.Zone)
	local target = P.Player
	P.PromptConns = {
		prompt.PromptButtonHoldBegan:Connect(function(reviver)
			EventHP.ReviveHold(target, reviver, "Began")
		end),
		prompt.PromptButtonHoldEnded:Connect(function(reviver)
			EventHP.ReviveHold(target, reviver, "Ended")
		end),
		prompt.Triggered:Connect(function(reviver)
			EventHP.ReviveHold(target, reviver, "Triggered")
		end),
	}
	prompt.Parent = root
	P.Prompt = prompt
end

---------------------------------------------------------------------------------------------------------------------
-- downed / revive / bleed-out / wipe
---------------------------------------------------------------------------------------------------------------------
local function endStrike(player: Player)
	local S = modules and modules.Strike
	if type(S) == "table" and type(S.End) == "function" then
		pcall(S.End, player)
	end
end

local function teleport(player: Player, cf: CFrame)
	local done = false
	local UY = modules and modules.Underyard
	if type(UY) == "table" and type(UY.Teleport) == "function" then
		local layout = Halloween:FindFirstChild("UnderyardLayout")
		local okL, L = false, nil
		if layout then
			okL, L = pcall(require, layout)
		end
		if okL and type(L) == "table" and type(L.InZone) == "function" and L.InZone(cf.Position) then
			local ok, res = pcall(UY.Teleport, player, cf)
			done = ok and res ~= false
		end
	end
	if not done then
		local ch = player.Character
		if ch then
			pcall(function()
				ch:PivotTo(cf)
				local root = ch:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end)
		end
	end
end

local checkWipe

local function bleed(P: any, reason: string)
	local now = EventHP.Now()
	local c = cfg()
	Rules.BleedOut(P.St, now, c)
	removePrompt(P)
	restoreWalk(P)
	local zone = EventHP.Zones[P.Zone]
	if reason ~= "Died" and zone and zone.Spawn then
		teleport(P.Player, zone.Spawn)
	end
	publish(P)
	sendAround(P.Player, zone, "Combat", { Kind = "BleedOut", UserId = P.Player.UserId, Zone = P.Zone, HP = half(P.St.HP), Max = round1(P.St.MaxHP),
		Weakened = P.St.WeakenedUntil, Reason = reason })
	if reason ~= "Wipe" then
		fire(EventHP.Listeners.BleedOut, P.Player, P.Zone, reason)
	end
end

local function downed(P: any, source: any)
	local zone = EventHP.Zones[P.Zone]
	endStrike(P.Player)
	applyWalk(P)
	createPrompt(P)
	publish(P)
	sendAround(P.Player, zone, "Combat", { Kind = "Down", UserId = P.Player.UserId, Zone = P.Zone, Until = P.St.DownedUntil,
		Source = type(source) == "string" and source or nil })
	fire(EventHP.Listeners.Down, P.Player, P.Zone, source)
	if zone then
		checkWipe(zone)
	end
end

local function finishWipe(zone: any, token: any)
	if zone.WipeToken ~= token then
		return
	end
	zone.WipeToken = nil
	for pl in pairs(zone.Members) do
		local P = EventHP.States[pl]
		if P and P.St.Downed then
			bleed(P, "Wipe")
		end
	end
	zone.Wiped = false
end
EventHP.FinishWipe = function(zoneId: string)
	local zone = EventHP.Zones[zoneId]
	if zone and zone.WipeToken then
		finishWipe(zone, zone.WipeToken)
	end
end

function checkWipe(zone: any)
	if zone.Wiped then
		return
	end
	local states, members = {}, {}
	for pl in pairs(zone.Members) do
		local P = EventHP.States[pl]
		if P then
			table.insert(states, P.St)
			table.insert(members, pl)
		end
	end
	if not Rules.Wiped(states) then
		return
	end
	zone.Wiped = true
	table.sort(members, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, pl in ipairs(members) do
		send(pl, "Combat", { Kind = "Wipe", Zone = zone.Id })
	end
	fire(EventHP.Listeners.Wipe, zone.Id, members)
	local token = {}
	zone.WipeToken = token
	EventHP.Delay(cfg().WipeGrace, finishWipe, zone, token)
end

---------------------------------------------------------------------------------------------------------------------
-- enter / leave
---------------------------------------------------------------------------------------------------------------------
local function maxHPFor(player: Player, opts: any?): number
	local c = cfg()
	local base = tonumber(opts and opts.MaxHP) or c.MaxHP
	if EventHP.HasDog(player, "Bride") then
		base += c.H14MaxHP
	end
	return base
end

function EventHP.Enter(player: Player, zoneId: string, opts: any?): boolean
	if typeof(player) ~= "Instance" and type(player) ~= "table" then
		return false
	end
	zoneId = tostring(zoneId)
	local now = EventHP.Now()
	local c = cfg()
	local zone = zoneOf(zoneId)
	if type(opts) == "table" then
		if opts.Spawn and not zone.Spawn then
			zone.Spawn = toSpawn(opts.Spawn)
		end
		if opts.Name ~= nil and zone.Name == nil then
			zone.Name = opts.Name
		end
		if opts.Trial ~= nil then
			zone.Trial = opts.Trial ~= false -- true or a trial id (Seals passes def.Id)
		end
	end
	local P = EventHP.States[player]
	if P and P.Zone == zoneId then
		if type(opts) == "table" and tonumber(opts.MaxHP) then
			P.MaxOpt = tonumber(opts.MaxHP)
			Rules.SetMax(P.St, maxHPFor(player, opts))
			publish(P)
		end
		return true
	end
	if P then
		EventHP.Leave(player)
	end
	local maxHP = maxHPFor(player, opts)
	local left = EventHP.Left[player]
	local st
	if Rules.Resumable(left, zoneId, now, c) then
		st = left.St
		Rules.SetMax(st, maxHP)
	else
		st = Rules.New(c, now, maxHP)
		if left and Rules.Weakened(left.St, now) then
			st.WeakenedUntil = left.St.WeakenedUntil -- the penalty follows the player into the next fight
		end
	end
	EventHP.Left[player] = nil
	P = { Player = player, Zone = zoneId, St = st, Hist = {}, Holds = {}, ReviveBy = 0, MaxOpt = tonumber(opts and opts.MaxHP),
		EnteredAt = now }
	EventHP.States[player] = P
	zone.Members[player] = true
	zone.Wiped = false
	publish(P)
	send(player, "Combat", { Kind = "Enter", UserId = player.UserId, Zone = zoneId, Name = zone.Name, HP = half(st.HP), Max = round1(st.MaxHP) })
	return true
end

function EventHP.Leave(player: Player, zoneId: string?): boolean
	local P = EventHP.States[player]
	if not P or (zoneId ~= nil and P.Zone ~= tostring(zoneId)) then
		return false
	end
	local now = EventHP.Now()
	if P.St.Downed then
		Rules.Undown(P.St, now, cfg())
	end
	removePrompt(P)
	restoreWalk(P)
	EventHP.States[player] = nil
	local zone = EventHP.Zones[P.Zone]
	if zone then
		zone.Members[player] = nil
	end
	EventHP.Left[player] = { Zone = P.Zone, St = P.St, LeftAt = now }
	if player.Parent then
		clearAttrs(player, P.St)
		send(player, "Combat", { Kind = "Leave", UserId = player.UserId, Zone = P.Zone })
	end
	if zone then
		checkWipe(zone)
	end
	return true
end

function EventHP.InCombat(player: Player): boolean
	return EventHP.States[player] ~= nil
end

function EventHP.Zone(player: Player): string?
	local P = EventHP.States[player]
	return P and P.Zone or nil
end

function EventHP.IsDowned(player: Player): boolean
	local P = EventHP.States[player]
	return P ~= nil and P.St.Downed == true
end

function EventHP.CanTarget(player: Player): boolean
	local P = EventHP.States[player]
	return P ~= nil and not P.St.Downed
end

function EventHP.HP(player: Player): (number, number, number)
	local P = EventHP.States[player]
	if not P then
		return 0, 0, 0
	end
	return P.St.HP, P.St.MaxHP, P.St.Shield
end

-- the state that carries WEAKENED: the live one, else the one kept after leaving
local function weakState(player: Player): any
	local P = EventHP.States[player]
	if P then
		return P.St
	end
	local left = EventHP.Left[player]
	return left and left.St or nil
end

function EventHP.DamageMult(player: Player): number
	return Rules.DealtMult(weakState(player), EventHP.Now())
end

function EventHP.TakenMult(player: Player): number
	return Rules.TakenMult(weakState(player), EventHP.Now())
end

---------------------------------------------------------------------------------------------------------------------
-- damage / heal / shield / down / revive
---------------------------------------------------------------------------------------------------------------------
local function isGas(info: any): boolean
	return info.Kind == "Gas" or info.Source == "Gas"
end

function EventHP.Damage(player: Player, amount: number, source: any?, info: any?): (number, number)
	local P = EventHP.States[player]
	if not P then
		return 0, 0
	end
	local i = type(info) == "table" and info or {}
	if type(source) == "string" and i.Source == nil then
		i.Source = source
	end
	local now = EventHP.Now()
	local c = cfg()
	local taken = Rules.TakenMult(P.St, now) * math.max(0, tonumber(i.Mult) or 1)
	if isGas(i) and EventHP.HasDog(player, "Candle") then
		taken *= c.H10GasMult
	end
	local applied, result, absorbed = Rules.Damage(P.St, amount, now, c, { Taken = taken, Tick = i.Tick == true })
	if result == "IFrame" or result == "Downed" or result == "None" then
		return 0, 0
	end
	local total = applied + absorbed
	local knock = typeof(i.Knock) == "Vector3" and i.Knock or nil
	if knock then
		local root = EventHP.RootOf(player)
		if root then
			pcall(function()
				root.AssemblyLinearVelocity = knock
			end)
		end
	end
	publish(P)
	local data = { Kind = "Hit", UserId = player.UserId, Zone = P.Zone, Amount = round1(total), Absorbed = round1(absorbed),
		Source = type(source) == "string" and source or nil, Hazard = i.Hazard, HP = P.St.Downed and 0 or half(P.St.HP),
		Max = round1(P.St.MaxHP), Shield = half(P.St.Shield), Tick = i.Tick == true or nil }
	local mine = table.clone(data)
	mine.Knock = knock
	mine.From = typeof(i.From) == "Vector3" and i.From or nil
	send(player, "Combat", mine)
	sendAround(player, EventHP.Zones[P.Zone], "Combat", data, true)
	if result == "Down" then
		downed(P, source)
	end
	return total, applied
end

function EventHP.Heal(player: Player, amount: number): number
	local P = EventHP.States[player]
	if not P then
		return 0
	end
	local healed = Rules.Heal(P.St, amount)
	if healed > 0 then
		publish(P)
	end
	return healed
end

function EventHP.Shield(player: Player, amount: number, seconds: number?): number
	local P = EventHP.States[player]
	if not P or P.St.Downed then
		return 0
	end
	local shield = Rules.AddShield(P.St, amount, EventHP.Now(), seconds)
	publish(P)
	send(player, "Combat", { Kind = "Shield", UserId = player.UserId, Zone = P.Zone, Shield = half(shield), Amount = round1(tonumber(amount) or 0) })
	return shield
end

function EventHP.Down(player: Player, source: any?): boolean
	local P = EventHP.States[player]
	if not P or P.St.Downed then
		return false
	end
	Rules.Down(P.St, EventHP.Now(), cfg())
	downed(P, source)
	return true
end

function EventHP.Revive(player: Player, by: Player?, opts: any?): boolean
	local P = EventHP.States[player]
	if not P or not P.St.Downed then
		return false
	end
	local o = type(opts) == "table" and opts or {}
	local now = EventHP.Now()
	local c = cfg()
	local shield = tonumber(o.Shield)
	if shield == nil and by and by ~= player and EventHP.HasDog(by, "Bride") then
		shield = c.H14ReviveShield
	end
	Rules.Revive(P.St, now, c, { HP = tonumber(o.HP) or c.ReviveHP, Shield = shield })
	removePrompt(P)
	restoreWalk(P)
	publish(P)
	local zone = EventHP.Zones[P.Zone]
	if zone then
		zone.Wiped = false
		zone.WipeToken = nil
	end
	sendAround(player, zone, "Combat", { Kind = "Revive", UserId = player.UserId, Zone = P.Zone, By = by and by.UserId or 0, HP = half(P.St.HP),
		Max = round1(P.St.MaxHP), Shield = half(P.St.Shield), Self = o.Self == true or nil })
	fire(EventHP.Listeners.Revive, player, P.Zone, by)
	if by and by ~= player then
		progress(by, "Revive", 1)
	end
	return true
end

function EventHP.SelfRevive(player: Player): (boolean, string?)
	local P = EventHP.States[player]
	if not P then
		return false, "You are not in a fight"
	end
	if not P.St.Downed then
		return false, "You are not downed"
	end
	if not EventHP.HasDog(player, "Mourning") then
		return false, "MOURNING VEIL needs the Mourning Shiba in your yard team"
	end
	local c = cfg()
	local ok, why = Rules.CanSelfRevive(P.St, EventHP.Now(), c)
	if not ok then
		if why == "Used" then
			return false, "MOURNING VEIL was already used in this fight"
		end
		return false, "MOURNING VEIL is not ready yet"
	end
	P.St.SelfReviveUsed = true
	EventHP.Revive(player, player, { HP = c.SelfReviveHP, Shield = 0, Self = true })
	return true, nil
end

function EventHP.OnDown(fn: (Player, string, any) -> ())
	return listen(EventHP.Listeners.Down, fn)
end
function EventHP.OnRevive(fn: (Player, string, Player?) -> ())
	return listen(EventHP.Listeners.Revive, fn)
end
function EventHP.OnBleedOut(fn: (Player, string, string) -> ())
	return listen(EventHP.Listeners.BleedOut, fn)
end
function EventHP.OnWipe(fn: (string, { Player }) -> ())
	return listen(EventHP.Listeners.Wipe, fn)
end

---------------------------------------------------------------------------------------------------------------------
-- hazards
---------------------------------------------------------------------------------------------------------------------
local function prepare(zone: any, def: any, now: number): any
	local c = cfg()
	EventHP.NextHazard += 1
	local d = table.clone(def)
	d.Id = EventHP.NextHazard
	d.Telegraph = math.max(0, tonumber(d.Telegraph) or 0)
	if tonumber(d.ImpactAt) == nil then
		d.ImpactAt = now + c.H10Lead + d.Telegraph + math.max(0, tonumber(d.Delay) or 0)
	end
	local fixed, problems = Hazards.Sanitize(d, { Trial = zone.Trial or (d.Trial ~= nil and d.Trial ~= false) })
	if #problems > 0 and Shared.IsStudio then
		warn("EventHP hazard " .. tostring(d.Kind) .. " made fair: " .. table.concat(problems, "; "))
	end
	d = fixed
	-- the impact never lands before the whole telegraph has been on screen
	if d.ImpactAt < now + d.Telegraph then
		d.ImpactAt = now + d.Telegraph
	end
	d.Delay = nil
	return d
end

local function recipientsOf(zone: any, d: any): { [Player]: boolean }
	local c = cfg()
	local out = {}
	local center = Hazards.Center(d.Shape)
	local range = c.HazardRange + Hazards.Extent(d.Shape)
	for _, pl in ipairs(EventHP.PlayerList()) do
		if zone.Members[pl] then
			out[pl] = true
		else
			local r = EventHP.RootOf(pl)
			if r and (r.Position - center).Magnitude <= range then
				out[pl] = true
			end
		end
	end
	return out
end

local function showAtFor(pl: Player, d: any, now: number): number
	local base = Hazards.ShowAt(d)
	if EventHP.HasDog(pl, "Candle") then
		return math.max(now, base - cfg().H10Lead)
	end
	return math.max(now, base)
end

local function schedule(zone: any, d: any)
	zone.Hazards[d.Id] = { Def = d, Impacted = false, NextTick = 0, Recipients = {} }
	return zone.Hazards[d.Id]
end

function EventHP.Hazard(zoneId: string, def: any): number?
	if type(def) ~= "table" or not Hazards.TypeOf(def.Shape) then
		return nil
	end
	local zone = zoneOf(tostring(zoneId))
	local now = EventHP.Now()
	local d = prepare(zone, def, now)
	local h = schedule(zone, d)
	for pl in pairs(recipientsOf(zone, d)) do
		h.Recipients[pl] = true
		send(pl, "Hazard", Hazards.Encode(d, showAtFor(pl, d, now)))
	end
	return d.Id
end

-- several hazards in one signal per player (bone rain, grave lines)
function EventHP.HazardWave(zoneId: string, defs: { any }): { number }
	local zone = zoneOf(tostring(zoneId))
	local now = EventHP.Now()
	local ids, list = {}, {}
	for _, def in ipairs(type(defs) == "table" and defs or {}) do
		if type(def) == "table" and Hazards.TypeOf(def.Shape) then
			local d = prepare(zone, def, now)
			schedule(zone, d)
			table.insert(ids, d.Id)
			table.insert(list, d)
		end
	end
	local per = {}
	for _, d in ipairs(list) do
		for pl in pairs(recipientsOf(zone, d)) do
			zone.Hazards[d.Id].Recipients[pl] = true
			per[pl] = per[pl] or {}
			table.insert(per[pl], Hazards.Encode(d, showAtFor(pl, d, now)))
		end
	end
	for pl, payload in pairs(per) do
		send(pl, "Hazard", { List = payload })
	end
	return ids
end

function EventHP.CancelHazards(zoneId: string, ids: { number }?): number
	local zone = EventHP.Zones[tostring(zoneId)]
	if not zone then
		return 0
	end
	local cancel, who = {}, {}
	local only = nil
	if type(ids) == "table" then
		only = {}
		for _, id in ipairs(ids) do
			only[id] = true
		end
	end
	for id, h in pairs(zone.Hazards) do
		if not only or only[id] then
			zone.Hazards[id] = nil
			table.insert(cancel, id)
			for pl in pairs(h.Recipients) do
				who[pl] = true
			end
		end
	end
	if #cancel > 0 then
		table.sort(cancel)
		for pl in pairs(who) do
			if pl.Parent then
				send(pl, "Hazard", { Cancel = cancel })
			end
		end
	end
	return #cancel
end

-- where was the player at server time t (interpolated from the 10 Hz history; the live root after the last sample)
local function posAt(P: any, t: number): Vector3?
	local hist = P.Hist
	local n = #hist
	if n == 0 then
		local r = EventHP.RootOf(P.Player)
		return r and r.Position or nil
	end
	if t >= hist[n].T then
		local r = EventHP.RootOf(P.Player)
		return r and r.Position or hist[n].P
	end
	if t <= hist[1].T then
		return hist[1].P
	end
	for i = n, 2, -1 do
		local a, b = hist[i - 1], hist[i]
		if t >= a.T then
			local k = b.T > a.T and (t - a.T) / (b.T - a.T) or 1
			return a.P:Lerp(b.P, math.clamp(k, 0, 1))
		end
	end
	return hist[1].P
end
EventHP.PositionAt = posAt

local function knockOf(d: any, pos: Vector3): Vector3?
	local k = d.Knock
	local power, up = nil, nil
	if type(k) == "number" then
		power = k
	elseif type(k) == "table" then
		power, up = tonumber(k.Power or k[1]), tonumber(k.Up or k[2])
	end
	if not power or power <= 0 then
		return nil
	end
	up = up or power * .45
	local s = Hazards.At(d.Shape, 0)
	local ty = Hazards.TypeOf(s)
	local dir
	if ty == "Line" then
		local v = flat(s.To - s.From)
		local n = Vector3.new(-v.Z, 0, v.X)
		if n.Magnitude < 1e-3 then
			n = Vector3.new(1, 0, 0)
		end
		n = n.Unit
		if n:Dot(flat(pos - s.From)) < 0 then
			n = -n
		end
		dir = n
	elseif ty == "Safe" then
		dir = flat(Hazards.Center(s) - pos) -- pushed back towards the safe circle
	else
		dir = flat(pos - Hazards.Center(s))
	end
	if dir.Magnitude < .1 then
		dir = Vector3.new(0, 0, 1)
	end
	return dir.Unit * power + Vector3.new(0, up, 0)
end

local function impact(zone: any, h: any)
	local c = cfg()
	local d = h.Def
	local dmg = tonumber(d.Damage) or 0
	if dmg <= 0 then
		return
	end
	local t1 = d.ImpactAt
	local t0 = t1 - c.HazardGrace
	local hits = {}
	for pl in pairs(zone.Members) do
		local P = EventHP.States[pl]
		if P and not P.St.Downed then
			local p1 = posAt(P, t1)
			if p1 and Hazards.Contains(d.Shape, p1, 0) then
				local p0 = posAt(P, t0)
				if p0 == nil or Hazards.Contains(d.Shape, p0, -c.HazardGrace) then
					table.insert(hits, { Player = pl, Pos = p1 })
				end
			end
		end
	end
	for _, hit in ipairs(hits) do
		local knock = knockOf(d, hit.Pos) -- [WP-C] kept for OnHit
		local dealt = EventHP.Damage(hit.Player, dmg, d.Source or d.Kind, { Kind = d.Kind, Hazard = d.Id, Knock = knock,
			From = Hazards.Center(Hazards.At(d.Shape, 0)) })
		-- [WP-C] def.OnHit(player, dealt, knockVelocity?, pos): the hazard's owner learns who it really hit (the Gravekeeper's
		-- Curse + knock signal); only for hits that landed (not i-frames)
		if dealt > 0 and type(d.OnHit) == "function" then
			local ok, err = pcall(d.OnHit, hit.Player, dealt, knock, hit.Pos)
			if not ok then
				warn("EventHP hazard OnHit failed: " .. tostring(err))
			end
		end
	end
end

local function linger(zone: any, h: any, now: number, step: number)
	local d = h.Def
	local dps = tonumber(d.DPS) or 0
	if dps <= 0 then
		return
	end
	local t = now - d.ImpactAt
	for pl in pairs(zone.Members) do
		local P = EventHP.States[pl]
		if P and not P.St.Downed then
			local pos = posAt(P, now)
			if pos and Hazards.Contains(d.Shape, pos, t) then
				EventHP.Damage(pl, dps * step, d.Source or d.Kind, { Kind = d.Kind, Hazard = d.Id, Tick = true })
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the 10 Hz combat tick
---------------------------------------------------------------------------------------------------------------------
local lastDogPass = 0

function EventHP.Tick(dt: number)
	local now = EventHP.Now()
	local c = cfg()
	-- 1. position history of every combat player (grace rewind)
	for player, P in pairs(EventHP.States) do
		local r = EventHP.RootOf(player)
		if r then
			table.insert(P.Hist, { T = now, P = r.Position })
		end
		while #P.Hist > 0 and P.Hist[1].T < now - 1.5 do
			table.remove(P.Hist, 1)
		end
	end
	-- 2. hazards of every zone
	for _, zone in pairs(EventHP.Zones) do
		for id, h in pairs(zone.Hazards) do
			local d = h.Def
			if not h.Impacted and now >= d.ImpactAt then
				h.Impacted = true
				h.NextTick = d.ImpactAt + c.DPSTick
				impact(zone, h)
			end
			if h.Impacted then
				if now >= Hazards.EndAt(d) then
					zone.Hazards[id] = nil
				elseif now >= h.NextTick then
					h.NextTick += c.DPSTick
					if h.NextTick < now then
						h.NextTick = now + c.DPSTick
					end
					linger(zone, h, now, c.DPSTick)
				end
			end
		end
	end
	-- 3. every state: regen, bleed-out, revive holds, dog changes
	local dogPass = os.clock() - lastDogPass >= c.DogRefresh
	if dogPass then
		lastDogPass = os.clock()
	end
	for player, P in pairs(EventHP.States) do
		local ev = Rules.Tick(P.St, now, dt, c)
		if ev.BleedOut then
			bleed(P, "Timer")
		end
		if P.St.Downed then
			for reviver in pairs(P.Holds) do
				if not canRevive(P, reviver) then
					EventHP.ReviveHold(player, reviver, "Ended")
				end
			end
			if P.Walk and not P.Walk.Managed and P.Walk.Humanoid.Parent and P.Walk.Humanoid.WalkSpeed > P.Walk.Applied + .01 then
				P.Walk.Humanoid.WalkSpeed = P.Walk.Applied
			end
		end
		if dogPass and not P.St.Downed then
			local want = maxHPFor(player, { MaxHP = P.MaxOpt })
			if math.abs(want - P.St.MaxHP) > 1e-6 then
				Rules.SetMax(P.St, want)
			end
		end
		if EventHP.States[player] == P then
			publish(P)
		end
	end
	-- 4. WEAKENED that ran out after leaving
	for player, left in pairs(EventHP.Left) do
		if not player.Parent then
			EventHP.Left[player] = nil
		else
			local weak = left.St.WeakenedUntil or 0
			if weak <= now then
				setAttr(player, "HwWeakenedUntil", nil)
				if now - left.LeftAt > c.ReEnterGrace then
					EventHP.Left[player] = nil
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------------------------------------------------
local function forget(player: Player)
	local P = EventHP.States[player]
	if P then
		removePrompt(P)
		EventHP.States[player] = nil
		local zone = EventHP.Zones[P.Zone]
		if zone then
			zone.Members[player] = nil
			checkWipe(zone)
		end
	end
	EventHP.Left[player] = nil
	dogCache[player] = nil
	for _, zone in pairs(EventHP.Zones) do
		for _, h in pairs(zone.Hazards) do
			h.Recipients[player] = nil
		end
	end
end
EventHP.Forget = forget

local function watchCharacter(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10)
	if not (hum and hum:IsA("Humanoid")) then
		return
	end
	hum.Died:Connect(function()
		local P = EventHP.States[player]
		if P and P.St.Downed then
			bleed(P, "Died") -- a real death while downed ends the downed state (no teleport: the respawn moves them)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local P = EventHP.States[player]
		if P then
			P.Hist = {}
			P.Walk = nil
		end
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		local P = EventHP.States[player]
		if P then
			removePrompt(P)
			P.Walk = nil
		end
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

-- Studio QA: C2CombatDebug {Cmd = "Enter"|"Leave"|"Hit"|"Down"|"Revive"|"Shield"|"Weaken"|"Hazards", N}
function EventHP.Debug(player: Player, cmd: string, n: number?): (boolean, string)
	local root = EventHP.RootOf(player)
	if cmd == "Enter" then
		local spawn = root and root.CFrame or nil
		EventHP.Enter(player, "Debug", { Spawn = spawn, Name = { "PRACTICE", "ТРЕНИРОВКА" } })
		return true, "Entered Debug combat"
	elseif cmd == "Leave" then
		return EventHP.Leave(player), "Left combat"
	elseif cmd == "Hit" then
		return EventHP.Damage(player, n or 20, "Debug") > 0, "Combat hit dealt"
	elseif cmd == "Down" then
		return EventHP.Down(player, "Debug"), "Combat: downed"
	elseif cmd == "Revive" then
		return EventHP.Revive(player, nil), "Combat: revived"
	elseif cmd == "Shield" then
		return EventHP.Shield(player, n or 20) > 0, "Combat: shield added"
	elseif cmd == "Weaken" then
		local P = EventHP.States[player]
		if P then
			P.St.WeakenedUntil = EventHP.Now() + cfg().WeakenedSeconds
			publish(P)
		end
		return P ~= nil, "Combat: weakened"
	elseif cmd == "Hazards" and root then
		if not EventHP.InCombat(player) then
			EventHP.Enter(player, "Debug", { Spawn = root.CFrame, Name = { "PRACTICE", "ТРЕНИРОВКА" } })
		end
		local p = Vector3.new(root.Position.X, root.Position.Y - 3, root.Position.Z)
		local look = flat(root.CFrame.LookVector)
		look = look.Magnitude > .1 and look.Unit or Vector3.new(0, 0, -1)
		local side = Vector3.new(-look.Z, 0, look.X)
		EventHP.HazardWave("Debug", {
			{ Shape = Hazards.Circle(p + look * 12, 6), Telegraph = 1.4, Damage = 14, Kind = "Slam", Source = "Debug" },
			{ Shape = Hazards.Ring(p, 10, 16, { { Angle = Hazards.AngleOf(look), Width = 40 } }), Telegraph = 1.8, Damage = 14,
				Kind = "Shockwave", Source = "Debug", Delay = .6 },
			{ Shape = Hazards.Line(p - side * 20 + look * 6, p + side * 20 + look * 6, 5), Telegraph = 1.6, Damage = 18, Kind = "Line",
				Source = "Debug", Delay = 1.2 },
			{ Shape = Hazards.Cone(p, -look, 90, 14), Telegraph = 1.3, Damage = 10, Kind = "Sweep", Source = "Debug", Delay = 1.8 },
			{ Shape = Hazards.Box(CFrame.lookAt(p + side * 14, p + side * 14 + look), Vector3.new(8, 2, 14)), Telegraph = 1.2,
				Damage = 12, Kind = "Curse", Source = "Debug", Delay = 2.4 },
			{ Shape = Hazards.Circle(p - look * 10, 5), Telegraph = 1, Damage = 0, DPS = 6, Linger = 5, Kind = "Gas", Source = "Debug",
				Delay = 2.8 },
			{ Shape = Hazards.Safe(p, 9, 40, { Path = { { At = 0, Center = p }, { At = 6, Center = p + look * 30 } } }), Telegraph = 1.2,
				Damage = 0, DPS = 7, Linger = 6, Kind = "Lantern", Source = "Debug", Delay = 4 },
		})
		return true, "Hazards spawned"
	end
	return false, "Unknown combat debug command"
end

function EventHP.Start(c, mods)
	core = c
	modules = mods
	EventHP.Core = c
	local Strike = modules and modules.Strike
	if type(Strike) == "table" and type(Strike.AddCanAct) == "function" then
		Strike.AddCanAct("EventHP", function(player)
			if EventHP.IsDowned(player) then
				return false, "HW:DOWNED"
			end
			return true
		end)
	end
	c.OnRequest("C2SelfRevive", function(player)
		local ok, err = EventHP.SelfRevive(player)
		if not ok then
			return false, err
		end
		local hp = EventHP.HP(player)
		return true, { HP = hp }
	end, { Cost = 2 })
	if Shared.IsStudio and game.GameId == 0 then
		c.OnRequest("C2CombatDebug", function(player, a)
			return EventHP.Debug(player, tostring(a.Cmd or ""), tonumber(a.N))
		end, { Cost = .5 })
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, pl in ipairs(Players:GetPlayers()) do
		watchPlayer(pl)
	end
	Players.PlayerRemoving:Connect(forget)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		local step = 1 / math.max(1, cfg().TickRate)
		if acc < step then
			return
		end
		local d = math.min(acc, .5)
		acc = 0
		if next(EventHP.States) == nil and next(EventHP.Left) == nil then
			local any = false
			for _, zone in pairs(EventHP.Zones) do
				if next(zone.Hazards) then
					any = true
					break
				end
			end
			if not any then
				return
			end
		end
		local ok, err = pcall(EventHP.Tick, d)
		if not ok then
			warn("EventHP tick failed: " .. tostring(err))
		end
	end)
end

return EventHP
