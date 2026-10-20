-- Timing-hit strikes on every Halloween target (ServerScriptService.Halloween.Strike).
-- The Mining Corner feel everywhere: the client (StarterPlayerScripts.MiningClient.HalloweenStrike) draws the same timing
-- circles from server-issued targets; this module judges every click like MiningRules.Hit (the client CLAIMS a Perfect,
-- the server confirms or downgrades it, crits are rolled here), computes damage with MiningRules.HitDamage and the
-- player's REAL pickaxe (player attributes MiningPickaxe / MiningStrength, written by the economy server) and applies
-- it to the target. A server-confirmed Perfect Hit pays Config.Candy.PerfectHit through Core.Queue (capped per minute by
-- Config.Candy.PerfectHitCap).
--
-- KIND API (Ores, DigSpots, Boss (WP8), Houses mini boss (WP10b))
--   Strike.Register(kind, def)   def = {
--       Range = 14,              studs from the target part's centre (prompt distance; the server allows + 6)
--       Verb = "MINE"|"DIG"|"STRIKE"|"BREAK",       prompt ActionText (the client localizes these four)
--       Damage = "Raw" | "Power" | fn(player, target, hit) -> number,
--                                "Raw" (default): hit.Damage (MiningRules.HitDamage, real pickaxe);
--                                "Power": hit.Power * target.Unit (tier-normalized: a plain hit with no Strength surplus
--                                is 1 power; Perfect / combo / crit / Strength multiply it; +4% per pickaxe level above 1)
--       CanHit = fn(player, target) -> ok, err?      checked on Begin and on every hit
--       OnBegin = fn(player, target) -> extra?       a player starts a session on the target (extra goes to the client)
--       OnHit = fn(player, target, hit) -> extra?    BEFORE the damage is applied: may change hit.Applied (e.g. 0 = miss,
--                                ×3 weak point); extra (table) is sent back to the hitter and merged into StrikeFx
--       OnBreak = fn(player, target, info)            HP reached 0 (runs in its own thread, may yield / Transact)
--                                info = {Killer, Contributors = {[userId] = {Player, Damage, Hits, Perfects, LastAt}},
--                                        Position, Kind, Data}
--       OnRemove = fn(target, reason)
--       Perfect = true,          Perfect Hit candy on this kind (default true)
--       Activity = "Hit",        Core.Activity kind for every hit (curse relief)
--       Remove = true,           remove the target automatically when it breaks (false: the kind decides)
--       EventMult = nil | true | "Apply",   CHAPTER II kinds: hit.EventMult = the attacker's EventHP.DamageMult (WEAKENED
--                                .7, else 1); "Apply" also multiplies hit.Applied by it before OnHit (nil: Chapter I, untouched)
--   }
--   Strike.Add(t) -> target       t = {Kind, Position=Vector3 | CFrame=CFrame (hit box centre), Radius=3, Size=Vector3?
--       (hit box, default Radius*2 cube), HP, MaxHP?, Unit? (HP per power for Damage="Power"), Color=Color3,
--       Material="Slate", Data={}, Owner=player?, Shared=true (false + Owner: only the owner may hit it),
--       Name="", NameRU="" (prompt object text), Variant="", Seed=n, Ground=Vector3?, Facing=yaw?, Panel=true,
--       HitPoints={{Pos=Vector3 (part space), Normal=Vector3 (part space)}}?, Attributes={...}?}
--     target = {Id, Kind, Def, Part, HP, MaxHP, Unit, Radius, Position, Data, Owner, Shared, Alive, Contributors, BornAt,
--               LastHitAt}
--   Strike.Move(target, cframe)   moving targets (boss plates, skeletons); hit points move with the part
--   Strike.Remove(target, reason) reason is replicated as the part attribute EndReason ("Broke"|"Sink"|...)
--   Strike.Damage(target, amount, player?) -> applied     external damage (breaks the target at 0)
--   Strike.SetHP(target, hp, maxHP?)                      re-scale (dig spot diggers); hp > 0 revives a broken target
--                                                         of a Remove = false kind (fresh contributors)
--   Strike.Get(id) / Strike.All(kind?)
--   Strike.HitDamage(player) -> n  average plain hit with the player's real pickaxe (0 = no pickaxe)
--   Strike.HitsHP(player, hits) -> n                       HP that needs `hits` plain hits from this player (Raw)
-- GLOBAL GATES (CHAPTER II): Strike.CanAct = {{Name, Fn}} checked on every Begin and every hit, before the kind's CanHit.
--   Strike.AddCanAct(name, fn(player, target) -> ok, err?)  (re-adding a name replaces it) ; Strike.RemoveCanAct(name)
--   Strike.CheckCanAct(player, target?) -> ok, err          EventHP adds "EventHP": a DOWNED player cannot strike
--                                                          ("HW:DOWNED"). No gate registered = Chapter I unchanged.
-- Replication: every target is an invisible anchored Part in Workspace.HalloweenLive.Targets (CanQuery true, tag
-- "HalloweenTarget") with attributes TargetId, Kind, HP, MaxHP, Color, Verb, Range, Radius, Variant, Seed, Label, LabelRU,
-- Material, Shared, OwnerUserId, Ground, Facing, Panel, BornAt (+ EndReason when it goes away) and child Attachments
-- "HitPoint" (attributes Normal (world), Index).
-- Requests (Core.OnRequest): StrikeBegin {Target}, StrikeHit {Target (circle id), Quality, Miss, Point}, StrikeEnd {}.
-- Signals: StrikeFx {UserId, TargetId, Kind, Quality, Crit, Point, Damage, Miss} (players near the target, not the
-- hitter), TargetBroke {TargetId, Kind, Position, UserId, Variant} (all).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local EconConfig = require(RS:WaitForChild("DogEconomy"):WaitForChild("Config"))
local MR = require(RS:WaitForChild("Mining"):WaitForChild("MiningRules"))
local M = EconConfig.Mining

local Strike = { Kinds = {}, Targets = {}, Sessions = {}, NextId = 0, IdBase = {}, CanAct = {} }
Strike.TAG = "HalloweenTarget"
Strike.TierBonus = .04 -- "Power" damage: +4% per pickaxe level above the first
Strike.RangeSlack = 6
Strike.FxRange = 140
Strike.M = M
Strike.MR = MR

local rng = Random.new()
Strike.Random = function(): number
	return rng:NextNumber()
end
Strike.Clock = function(): number
	return workspace:GetServerTimeNow()
end
Strike.Now = function(): number
	return os.time()
end

local core = nil
local started = nil -- the server's modules table (EventHP is reached through it lazily)

local function round1(x: number): number
	return math.floor(x * 10 + .5) / 10
end

local function folder(): Instance
	local live = workspace:FindFirstChild("HalloweenLive")
	if not live then
		live = Instance.new("Folder")
		live.Name = "HalloweenLive"
		live.Parent = workspace
	end
	local f = live:FindFirstChild("Targets")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Targets"
		f.Parent = live
	end
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- pickaxe helpers (REAL stats only: never a skin)
---------------------------------------------------------------------------------------------------------------------
function Strike.PickOf(player: Player): (any, number)
	local level = tonumber(player:GetAttribute("MiningPickaxe")) or 0
	return M.Pickaxes[level], level
end

function Strike.StrengthOf(player: Player): number
	return tonumber(player:GetAttribute("MiningStrength")) or 0
end

function Strike.HitDamage(player: Player): number
	local pick = Strike.PickOf(player)
	if not pick then
		return 0
	end
	return MR.HitDamage(M, { Strength = Strike.StrengthOf(player) }, pick, 1, 0, false)
end

function Strike.HitsHP(player: Player, hits: number): number
	return math.max(1, Strike.HitDamage(player)) * math.max(1, hits or 1)
end

-- tier-normalized hit power: 1 = a plain hit with no Strength surplus on the Wooden Pickaxe
function Strike.Power(damage: number, pick: any, level: number): number
	return damage / math.max(1, pick.Damage or 1) * (1 + Strike.TierBonus * math.max(0, (level or 1) - 1))
end

---------------------------------------------------------------------------------------------------------------------
-- pure timing judgement (MiningRules.Hit semantics on a Halloween session)
---------------------------------------------------------------------------------------------------------------------
local function findCircle(s, id: number)
	for slot, t in pairs(s.Targets or {}) do
		if t.Id == id then
			return t, slot
		end
	end
	return nil, nil
end

local function respawnCircle(s, slot: number, at: number, window: number)
	s.NextId = (s.NextId or 0) + 1
	s.Targets[slot] = { Id = s.NextId, Slot = slot, SpawnAt = at, Window = window }
end

-- s = {Targets, Stale, NextId, LastHitAt, Combo}; args = {Target, Quality, Miss}
-- -> {Ok=false, Code} | {Ok=true, Message="MISS"|"TOO_LATE"|"STALE"} | {Ok=true, Message="HIT"|"PERFECT"|"CRIT", Quality,
--    Crit, Damage, Combo (before this hit), Slot}
function Strike.Judge(s, pick, now: number, ping: number?, args, random: (() -> number)?, strength: number?)
	local id = math.floor(tonumber(args.Target) or -1)
	local t, slot = findCircle(s, id)
	if not t then
		if s.Stale and s.Stale[id] then
			return { Ok = true, Message = "STALE" }
		end
		return { Ok = false, Code = "M:TARGET_GONE" }
	end
	local tm = M.Timing
	local w = t.Window
	local e = now - t.SpawnAt
	ping = math.clamp(tonumber(ping) or 0, 0, 1)
	if e < -tm.ServerSlack then
		return { Ok = false, Code = "M:TOO_EARLY" }
	end
	if args.Miss == true or e > w + ping + tm.LateGrace then
		respawnCircle(s, slot, math.max(now, t.SpawnAt) + M.Client.RespawnDelay, pick.Window)
		s.Combo = 0
		return { Ok = true, Message = args.Miss == true and "MISS" or "TOO_LATE" }
	end
	if e < tm.GoodFrom * w - tm.ServerSlack then
		return { Ok = false, Code = "M:TOO_EARLY" }
	end
	if now - (s.LastHitAt or 0) < M.MinHitGap then
		return { Ok = false, Code = "M:NOT_READY" }
	end
	local claimed = tonumber(args.Quality) == 2
	local serverPerfect = e >= tm.PerfectFrom * w - tm.ServerSlack and e <= tm.PerfectTo * w + ping + tm.ServerSlack
	local quality = (claimed and serverPerfect) and 2 or 1
	if now - (s.LastHitAt or 0) > M.ComboTimeout then
		s.Combo = 0
	end
	s.LastHitAt = now
	local crit = (random or Strike.Random)() < (pick.CritChance or 0)
	local combo = s.Combo or 0
	local damage = MR.HitDamage(M, { Strength = strength or 0 }, pick, quality, combo, crit)
	if quality == 2 then
		s.Combo = math.min(M.ComboCap, combo + 1)
	else
		s.Combo = 0
	end
	respawnCircle(s, slot, now + M.Client.RespawnDelay, pick.Window)
	return { Ok = true, Message = crit and "CRIT" or quality == 2 and "PERFECT" or "HIT", Quality = quality, Crit = crit, Damage = damage,
		Combo = combo, Slot = slot }
end

---------------------------------------------------------------------------------------------------------------------
-- kinds and targets
---------------------------------------------------------------------------------------------------------------------
function Strike.Register(kind: string, def: { [string]: any }?)
	assert(type(kind) == "string" and #kind > 0 and #kind <= 40, "Strike.Register: bad kind")
	local spec: { [string]: any } = def or {}
	local d = {
		Kind = kind, Range = tonumber(spec.Range) or 14, Verb = spec.Verb or "STRIKE", Damage = spec.Damage or "Raw",
		CanHit = spec.CanHit, OnBegin = spec.OnBegin, OnHit = spec.OnHit, OnBreak = spec.OnBreak, OnRemove = spec.OnRemove,
		Perfect = spec.Perfect ~= false, Activity = spec.Activity or "Hit", Remove = spec.Remove ~= false,
		EventMult = (spec.EventMult == true or spec.EventMult == "Apply") and spec.EventMult or nil,
	}
	Strike.Kinds[kind] = d
	return d
end

---------------------------------------------------------------------------------------------------------------------
-- global gates (CHAPTER II): every gate must allow a player before any kind's own CanHit runs
---------------------------------------------------------------------------------------------------------------------
function Strike.AddCanAct(name: string, fn: (Player, any) -> (boolean, string?))
	assert(type(name) == "string" and type(fn) == "function", "Strike.AddCanAct: bad gate")
	for _, g in ipairs(Strike.CanAct) do
		if g.Name == name then
			g.Fn = fn
			return
		end
	end
	table.insert(Strike.CanAct, { Name = name, Fn = fn })
end

function Strike.RemoveCanAct(name: string)
	for i = #Strike.CanAct, 1, -1 do
		if Strike.CanAct[i].Name == name then
			table.remove(Strike.CanAct, i)
		end
	end
end

function Strike.CheckCanAct(player: Player, target: any?): (boolean, string?)
	for _, g in ipairs(Strike.CanAct) do
		local ok, allowed, err = pcall(g.Fn, player, target)
		if not ok then
			warn("Halloween Strike: gate " .. g.Name .. " failed: " .. tostring(allowed))
		elseif not allowed then
			return false, type(err) == "string" and err or "HW:CANT"
		end
	end
	return true, nil
end

-- the attacker's Event HP damage multiplier (WEAKENED) for kinds that opt in; 1 without combat or EventHP
local function eventMult(player: Player): number
	local hp = started and started.EventHP
	if type(hp) ~= "table" or type(hp.DamageMult) ~= "function" then
		return 1
	end
	local ok, m = pcall(hp.DamageMult, player)
	return (ok and tonumber(m)) or 1
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function syncHP(target)
	local part = target.Part
	if part and part.Parent then
		setAttr(part, "HP", round1(math.max(0, target.HP)))
		setAttr(part, "MaxHP", round1(target.MaxHP))
	end
end

local function defaultPoints(size: Vector3): { any }
	local out = {}
	local rx, ry, rz = size.X / 2, size.Y / 2, size.Z / 2
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2 * 2
		local h = ((i - 1) % 3) / 2 -- 0 .. 1
		local y = -ry * .4 + h * ry * 1.1
		local k = math.sqrt(math.max(.15, 1 - (y / math.max(ry, .1)) ^ 2))
		local n = Vector3.new(math.cos(a), .3 + h * .4, math.sin(a)).Unit
		table.insert(out, { Pos = Vector3.new(math.cos(a) * rx * k * .95, y, math.sin(a) * rz * k * .95), Normal = n })
	end
	return out
end

function Strike.Add(t: { [string]: any })
	local def = Strike.Kinds[t.Kind]
	assert(def, "Strike.Add: unknown kind " .. tostring(t.Kind))
	Strike.NextId += 1
	local id = Strike.NextId
	local cf = typeof(t.CFrame) == "CFrame" and t.CFrame or CFrame.new(t.Position or Vector3.zero)
	local radius = tonumber(t.Radius) or 3
	local size = typeof(t.Size) == "Vector3" and t.Size or Vector3.new(radius * 2, radius * 2, radius * 2)
	local maxHP = math.max(1, tonumber(t.MaxHP) or tonumber(t.HP) or 10)
	local hp = math.clamp(tonumber(t.HP) or maxHP, 0, maxHP)
	local part = Instance.new("Part")
	part.Name = "Target_" .. id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cf
	local color = typeof(t.Color) == "Color3" and t.Color or Color3.fromRGB(180, 160, 140)
	local owner = t.Owner
	part:SetAttribute("TargetId", id)
	part:SetAttribute("Kind", t.Kind)
	part:SetAttribute("HP", round1(hp))
	part:SetAttribute("MaxHP", round1(maxHP))
	part:SetAttribute("Color", color)
	part:SetAttribute("Verb", def.Verb)
	part:SetAttribute("Range", def.Range)
	part:SetAttribute("Radius", radius)
	part:SetAttribute("Material", type(t.Material) == "string" and t.Material or "Slate")
	part:SetAttribute("Shared", t.Shared ~= false)
	part:SetAttribute("OwnerUserId", (typeof(owner) == "Instance" and owner:IsA("Player")) and owner.UserId or 0)
	part:SetAttribute("BornAt", Strike.Clock())
	part:SetAttribute("Panel", t.Panel ~= false)
	if type(t.Variant) == "string" then
		part:SetAttribute("Variant", t.Variant)
	end
	if t.Seed then
		part:SetAttribute("Seed", math.floor(tonumber(t.Seed) or 0))
	end
	if type(t.Name) == "string" then
		part:SetAttribute("Label", t.Name)
	end
	if type(t.NameRU) == "string" then
		part:SetAttribute("LabelRU", t.NameRU)
	end
	if typeof(t.Ground) == "Vector3" then
		part:SetAttribute("Ground", t.Ground)
	end
	if t.Facing then
		part:SetAttribute("Facing", tonumber(t.Facing) or 0)
	end
	for k, v in pairs(type(t.Attributes) == "table" and t.Attributes or {}) do
		part:SetAttribute(k, v)
	end
	local points = type(t.HitPoints) == "table" and #t.HitPoints > 0 and t.HitPoints or defaultPoints(size)
	for i, p in ipairs(points) do
		local a = Instance.new("Attachment")
		a.Name = "HitPoint"
		a.Position = p.Pos
		local n = typeof(p.Normal) == "Vector3" and p.Normal or Vector3.new(0, 1, 0)
		a:SetAttribute("Normal", cf:VectorToWorldSpace(n.Unit))
		a:SetAttribute("Index", i)
		a.Parent = part
	end
	pcall(function()
		CollectionService:AddTag(part, Strike.TAG) -- tagged before parenting: replicates with the part
	end)
	part.Parent = folder()
	local target = {
		Id = id, Kind = t.Kind, Def = def, Part = part, HP = hp, MaxHP = maxHP, Unit = tonumber(t.Unit) or 1, Radius = radius,
		Position = cf.Position, Data = type(t.Data) == "table" and t.Data or {}, Owner = owner, Shared = t.Shared ~= false, Alive = true,
		Contributors = {}, BornAt = os.clock(), LastHitAt = 0, Variant = t.Variant, Points = #points,
	}
	Strike.Targets[id] = target
	return target
end

function Strike.Get(id: any)
	return Strike.Targets[tonumber(id) or -1]
end

function Strike.All(kind: string?): { any }
	local out = {}
	for _, t in pairs(Strike.Targets) do
		if kind == nil or t.Kind == kind then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end

function Strike.Move(target, cframe: CFrame)
	if type(target) ~= "table" or not target.Part then
		return
	end
	target.Position = cframe.Position
	if target.Part.Parent then
		target.Part.CFrame = cframe
	end
end

-- also revives a broken (not removed) target of a kind with Remove = false (boss plates that grow back)
function Strike.SetHP(target, hp: number, maxHP: number?)
	if type(target) ~= "table" or target.Removed then
		return
	end
	if maxHP then
		target.MaxHP = math.max(1, maxHP)
	end
	target.HP = math.clamp(hp, 0, target.MaxHP)
	if target.HP > 0 and not target.Alive then
		target.Alive, target.Broken = true, false
		target.Contributors = {}
	end
	syncHP(target)
end

function Strike.Remove(target, reason: string?)
	if type(target) ~= "table" then
		target = Strike.Get(target)
	end
	if not target or target.Removed then
		return
	end
	target.Removed = true
	target.Alive = false
	Strike.Targets[target.Id] = nil
	for player, s in pairs(Strike.Sessions) do
		if s.Target == target then
			Strike.Sessions[player] = nil
		end
	end
	local part = target.Part
	if part and part.Parent then
		part:SetAttribute("EndReason", reason or "Removed")
		part:SetAttribute("HP", round1(math.max(0, target.HP)))
		-- leave it a moment so the reason replicates before the part goes away
		task.delay(.6, function()
			if part.Parent then
				part:Destroy()
			end
		end)
	end
	if target.Def.OnRemove then
		task.spawn(function()
			local ok, err = pcall(target.Def.OnRemove, target, reason)
			if not ok then
				warn("Halloween Strike: OnRemove (" .. target.Kind .. ") failed: " .. tostring(err))
			end
		end)
	end
end

local function contribute(target, player: Player, applied: number, perfect: boolean?)
	local c = target.Contributors[player.UserId]
	if not c then
		c = { Player = player, Damage = 0, Hits = 0, Perfects = 0, LastAt = 0 }
		target.Contributors[player.UserId] = c
	end
	c.Player = player
	c.Damage += applied
	c.Hits += 1
	if perfect then
		c.Perfects += 1
	end
	c.LastAt = os.clock()
	return c
end
Strike.Contribute = contribute

local function breakTarget(target, killer: Player?)
	if target.Broken then
		return
	end
	target.Broken = true
	target.Alive = false
	target.HP = 0
	syncHP(target)
	local info = { Killer = killer, Contributors = target.Contributors, Position = target.Position, Kind = target.Kind, Data = target.Data }
	if core then
		core.Signal("all", "TargetBroke", { TargetId = target.Id, Kind = target.Kind, Position = target.Position,
			UserId = killer and killer.UserId or 0, Variant = target.Variant })
	end
	if target.Def.OnBreak then
		task.spawn(function()
			local ok, err = pcall(target.Def.OnBreak, killer, target, info)
			if not ok then
				warn("Halloween Strike: OnBreak (" .. target.Kind .. ") failed: " .. tostring(err))
			end
		end)
	end
	if target.Def.Remove then
		Strike.Remove(target, "Broke")
	end
end

function Strike.Damage(target, amount: number, player: Player?): number
	if type(target) ~= "table" or not target.Alive then
		return 0
	end
	local applied = math.clamp(tonumber(amount) or 0, 0, target.HP)
	target.HP -= applied
	if player then
		contribute(target, player, applied)
	end
	syncHP(target)
	if target.HP <= 1e-6 then
		breakTarget(target, player)
	end
	return applied
end

---------------------------------------------------------------------------------------------------------------------
-- sessions (one per player)
---------------------------------------------------------------------------------------------------------------------
local function rootOf(player: Player): BasePart?
	if core then
		return core.Root(player)
	end
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

function Strike.InRange(player: Player, target, slack: number?): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	return (root.Position - target.Position).Magnitude <= target.Def.Range + (slack or Strike.RangeSlack)
end

local function pingOf(player: Player): number
	local ok, v = pcall(function()
		return player:GetNetworkPing()
	end)
	return ok and tonumber(v) or 0
end

local function gate(player: Player, target): (boolean, string?)
	if not target or not target.Alive then
		return false, "HW:GONE"
	end
	if not Shared.Enabled() then
		return false, "HW:OFF"
	end
	if #Strike.CanAct > 0 then
		local okAct, errAct = Strike.CheckCanAct(player, target)
		if not okAct then
			return false, errAct
		end
	end
	if target.Shared == false and target.Owner ~= nil and target.Owner ~= player then
		return false, "HW:NOT_YOURS"
	end
	if target.Def.CanHit then
		local ok, okHit, err = pcall(target.Def.CanHit, player, target)
		if not ok then
			warn("Halloween Strike: CanHit (" .. target.Kind .. ") failed: " .. tostring(okHit))
			return false, "HW:GONE"
		end
		if not okHit then
			return false, err or "HW:CANT"
		end
	end
	return true
end

local function viewTargets(s)
	return MR.ViewTargets(s)
end

function Strike.Begin(player: Player, a: { [string]: any })
	local target = Strike.Get(a.Target)
	local ok, err = gate(player, target)
	if not ok then
		return false, err
	end
	local pick, level = Strike.PickOf(player)
	if not pick then
		return false, "HW:NEED_PICKAXE"
	end
	if not Strike.InRange(player, target, Strike.RangeSlack) then
		return false, "HW:FAR"
	end
	local now = Strike.Clock()
	local s = Strike.Sessions[player]
	local extra = nil
	local live = s ~= nil and s.Target == target and s.Level == level and Strike.Now() <= (s.ActiveUntil or 0) and next(s.Targets) ~= nil
	if not live then
		local base = math.max(Strike.IdBase[player] or 0, s and s.NextId or 0)
		s = { Target = target, Targets = {}, Stale = {}, NextId = base, LastHitAt = 0, Combo = 0, Level = level }
		MR.IssueTargets(s, M, pick, now)
		Strike.Sessions[player] = s
		if target.Def.OnBegin then
			local okB, res = pcall(target.Def.OnBegin, player, target)
			if okB then
				extra = res
			else
				warn("Halloween Strike: OnBegin (" .. target.Kind .. ") failed: " .. tostring(res))
			end
		end
		s.Extra = extra
	end
	Strike.IdBase[player] = s.NextId
	s.ActiveUntil = Strike.Now() + M.SessionSeconds
	if core then
		core.Activity(player, nil)
	end
	return true, { TargetId = target.Id, Kind = target.Kind, Targets = viewTargets(s), HP = round1(target.HP), MaxHP = round1(target.MaxHP),
		Extra = s.Extra, Window = pick.Window, Circles = pick.Circles }
end

local function broadcast(player: Player, target, v, point: number?, applied: number, extra: any)
	if not core then
		return
	end
	local data = { UserId = player.UserId, TargetId = target.Id, Kind = target.Kind, Quality = v.Quality, Crit = v.Crit, Point = point,
		Damage = round1(applied), Miss = type(extra) == "table" and extra.Miss == true or nil }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local root = rootOf(other)
			if root and (root.Position - target.Position).Magnitude <= Strike.FxRange then
				core.Signal(other, "StrikeFx", data)
			end
		end
	end
end

local function applyDamageMode(def, player: Player, target, hit): number
	local mode = def.Damage
	if type(mode) == "function" then
		local ok, n = pcall(mode, player, target, hit)
		return (ok and tonumber(n)) or hit.Damage
	elseif mode == "Power" then
		return hit.Power * (target.Unit or 1)
	end
	return hit.Damage
end

function Strike.Hit(player: Player, a: { [string]: any })
	local s = Strike.Sessions[player]
	if not s then
		return false, "M:SESSION_OVER"
	end
	local target = s.Target
	if not target.Alive then
		Strike.Sessions[player] = nil
		return false, "HW:GONE"
	end
	if Strike.Now() > (s.ActiveUntil or 0) then
		Strike.Sessions[player] = nil
		return false, "M:SESSION_OVER"
	end
	local pick, level = Strike.PickOf(player)
	if not pick then
		return false, "HW:NEED_PICKAXE"
	end
	local now = Strike.Clock()
	if level ~= s.Level then
		-- a new pickaxe mid-session: its own circles (count / window)
		MR.IssueTargets(s, M, pick, now)
		s.Level = level
		Strike.IdBase[player] = s.NextId
		return true, { Message = "STALE", Targets = viewTargets(s), HP = round1(target.HP), MaxHP = round1(target.MaxHP) }
	end
	local ok, err = gate(player, target)
	if not ok then
		return false, err
	end
	if not Strike.InRange(player, target, Strike.RangeSlack + 4) then
		return false, "HW:FAR"
	end
	local v = Strike.Judge(s, pick, now, pingOf(player), a, Strike.Random, Strike.StrengthOf(player))
	Strike.IdBase[player] = s.NextId
	if not v.Ok then
		return false, v.Code
	end
	s.ActiveUntil = Strike.Now() + M.SessionSeconds
	if v.Quality == nil then
		return true, { Message = v.Message, Targets = viewTargets(s), HP = round1(target.HP), MaxHP = round1(target.MaxHP) }
	end
	local point = tonumber(a.Point)
	point = (point and point >= 1 and point <= (target.Points or 0)) and math.floor(point) or nil
	local def = target.Def
	local hit = { Damage = v.Damage, Quality = v.Quality, Crit = v.Crit, Combo = v.Combo, Pick = pick, Level = level, Point = point,
		Power = Strike.Power(v.Damage, pick, level), Player = player }
	hit.Applied = applyDamageMode(def, player, target, hit)
	if def.EventMult then
		hit.EventMult = eventMult(player)
		if def.EventMult == "Apply" then
			hit.Applied = (tonumber(hit.Applied) or 0) * hit.EventMult
		end
	end
	local extra = nil
	if def.OnHit then
		local okH, res = pcall(def.OnHit, player, target, hit)
		if okH then
			extra = res
		else
			warn("Halloween Strike: OnHit (" .. target.Kind .. ") failed: " .. tostring(res))
		end
	end
	if not target.Alive then
		return true, { Message = v.Message, Quality = v.Quality, Crit = v.Crit, Damage = 0, HP = 0, MaxHP = round1(target.MaxHP), Broke = true,
			Targets = viewTargets(s), Extra = extra }
	end
	target.LastHitAt = os.clock()
	local applied = math.clamp(tonumber(hit.Applied) or 0, 0, target.HP)
	target.HP -= applied
	contribute(target, player, applied, v.Quality == 2)
	syncHP(target)
	-- perfect-hit candy (server-confirmed only), capped per minute inside Core.Queue
	local candy = 0
	if core then
		if v.Quality == 2 and def.Perfect then
			candy = core.Queue(player, { Candy = Config.Candy.PerfectHit, Source = "Perfect", Quest = { Perfect = 1 }, Stat = { Perfect = 1 },
				Relief = { "Perfect" } })
		end
		core.Activity(player, def.Activity)
	end
	broadcast(player, target, v, point, applied, extra)
	local broke = false
	if target.HP <= 1e-6 then
		broke = true
		breakTarget(target, player)
	end
	return true, { Message = broke and "BROKE" or v.Message, Quality = v.Quality, Crit = v.Crit, Damage = round1(applied), Raw = v.Damage,
		Combo = s.Combo, HP = round1(math.max(0, target.HP)), MaxHP = round1(target.MaxHP), Broke = broke, Candy = candy,
		Targets = (not broke) and viewTargets(s) or nil, Extra = extra }
end

function Strike.End(player: Player)
	Strike.Sessions[player] = nil
	return true, {}
end

---------------------------------------------------------------------------------------------------------------------
-- loot helpers shared by the Halloween kinds (ore, dig spots; the boss may reuse them)
---------------------------------------------------------------------------------------------------------------------
-- event mutation for a rare find: Config.Rewards.RareFindMutations (BloodMoonOnly rows need an ACTIVE Blood Moon)
function Strike.RareMutation(roll: number, bloodMoon: boolean): (any, number)
	local rows = {}
	local total = 0
	for _, r in ipairs(Config.Rewards.RareFindMutations or {}) do
		if not r.BloodMoonOnly or bloodMoon then
			table.insert(rows, r)
			total += r.Weight or 0
		end
	end
	if #rows == 0 then
		return { Id = "HAUNTED", Weight = 1 }, 1
	end
	local row = Shared.Weighted(rows, function()
		return roll
	end)
	return row, (row.Weight or 0) / math.max(1, total)
end

function Strike.RandRange(range: any, roll: number): number
	if type(range) ~= "table" then
		return tonumber(range) or 0
	end
	local a, b = range[1] or 0, range[2] or range[1] or 0
	return a + math.floor(roll * (b - a + 1 - 1e-9))
end

-- compact item summary for signals / UI
function Strike.ItemSummary(item: any): any
	if type(item) ~= "table" then
		return nil
	end
	return { Uid = item.ItemUid, Id = item.ItemId, Name = item.DisplayName or item.Name or item.ItemId, Mutation = item.Mutation,
		Rarity = item.Rarity, Class = item.Class, TierIndex = item.TierIndex, Weight = item.WeightKg, Value = item.SellValue }
end

-- the pit-style reveal (EconomyVisuals, WP5 patch accepts Venue "Halloween") + the zone-wide Find beam signal
function Strike.Reveal(player: Player, item: any, position: Vector3)
	if type(item) ~= "table" then
		return
	end
	local remote = RS:FindFirstChild("DiscoveryReveal")
	if remote and remote:IsA("RemoteEvent") and player.Parent then
		local payload = table.clone(item)
		payload.LootSpawn = { CFrame = CFrame.new(position + Vector3.new(0, 1, 0)), OwnerUserId = player.UserId, Venue = "Halloween" }
		pcall(function()
			remote:FireClient(player, payload)
		end)
	end
	if core then
		core.Signal("zone", "Find", { Item = Strike.ItemSummary(item), Position = position, UserId = player.UserId })
	end
end

---------------------------------------------------------------------------------------------------------------------
-- start
---------------------------------------------------------------------------------------------------------------------
function Strike.Start(c, modules)
	core = c
	Strike.Core = c
	started = type(modules) == "table" and modules or nil
	folder()
	c.OnRequest("StrikeBegin", function(player, a)
		return Strike.Begin(player, a)
	end, { Cost = 1 })
	c.OnRequest("StrikeHit", function(player, a)
		return Strike.Hit(player, a)
	end, { Cost = .25 })
	c.OnRequest("StrikeEnd", function(player)
		return Strike.End(player)
	end, { Cost = .2, AllowDisabled = true })
	Players.PlayerRemoving:Connect(function(player)
		Strike.Sessions[player] = nil
		Strike.IdBase[player] = nil
	end)
	-- expired sessions + targets of players who left
	task.spawn(function()
		while true do
			task.wait(5)
			local now = Strike.Now()
			for player, s in pairs(Strike.Sessions) do
				if now > (s.ActiveUntil or 0) + 5 or not player.Parent then
					Strike.Sessions[player] = nil
				end
			end
			if not Shared.Enabled() then
				for _, t in ipairs(Strike.All()) do
					Strike.Remove(t, "Off")
				end
			end
		end
	end)
end

return Strike
