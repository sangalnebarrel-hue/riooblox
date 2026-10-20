-- TRICK OR TREAT STREET (ServerScriptService.Halloween.Houses), WP10b.
-- Seven abandoned houses along Hollow Lane. Every player may knock on each door once per UTC day
-- (profile.Halloween.Houses.Knocked, reset by Feature.EnsureDaily). The outcome is decided here:
--   TREAT (Config.TrickOrTreat.TreatChance): Config.Candy.TreatHouse candy, offered by a skeleton paw.
--   TRICK: one weighted effect from Config.TrickOrTreat.Tricks + the Config.Candy.TrickHouse consolation candy
--          (every trick pays). Server-side parts of the tricks: CurseBoost -> Core.AddCurse; MiniBoss -> a Strike target
--          of kind "MiniBoss" on the porch that pays a candy bounty when broken (personal; escapes after a while).
--          Jumpscare / Ghosts / Fog / FakeChest are client presentation only (HouseFX). No control tricks, ever.
-- Every knock: quest Knock, stat Knocks, souls Exorcism.Souls.Knock, curse relief "Knock".
-- Entry points: the server ProximityPrompts "KNOCK" on the Persistent anchors House1..7 (World.Prompt) and the request
-- `HouseKnock {Index}` (same rules; must stand at the door).
-- Signals (to "all"; the client State re-fires them on the Bus):
--   House     {Index, Kind = "Treat"|"Trick", Trick = id?, UserId, Candy, Knocked, Day}   door animation + effect
--   HouseBoss {Kind = "Spawn"|"Down"|"Escape", Index, UserId, TargetId?, Candy?}          porch skeleton lifecycle
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout

local Houses = {}
Houses.Clock = os.clock -- tests replace it
Houses.Random = Random.new()
Houses.Bosses = {} -- player -> {Target, Index, Id, Expires}
Houses.Messages = {
	Already = "You already knocked on this door today. Come back tomorrow!",
	TooFar = "Walk up to the door to knock",
	Invalid = "Invalid house",
	Busy = "Please wait a moment",
	Treat = "TREAT! +%d Candy",
	Trick = "TRICK! +%d Candy",
	BossDown = "The porch skeleton crumbles! +%d Candy",
	BossEscape = "The porch skeleton slipped back into the house",
}

local function T()
	return Config.TrickOrTreat
end

local function check(ok: any, msg: string)
	if not ok then
		error(msg, 0)
	end
end

local function randInt(range: { number }, rand: () -> number): number
	local lo, hi = math.floor(range[1] or 0), math.floor(range[2] or range[1] or 0)
	if hi < lo then
		lo, hi = hi, lo
	end
	return math.clamp(lo + math.floor(rand() * (hi - lo + 1)), lo, hi)
end
Houses.RandInt = randInt

local function rnd(): number
	return Houses.Random:NextNumber()
end

---------------------------------------------------------------------------------------------------------------------
-- Pure rules (Lune-tested in tools/hw_test_wp10b.luau)
---------------------------------------------------------------------------------------------------------------------
function Houses.Count(): number
	return math.max(1, math.floor(T().Houses or #Layout.Houses))
end

-- integer 1..Houses or nil
function Houses.ValidIndex(i: any): number?
	if type(i) ~= "number" or i ~= i or i % 1 ~= 0 or i < 1 or i > Houses.Count() or Layout.Houses[i] == nil then
		return nil
	end
	return i
end

function Houses.TrickRow(id: string?)
	for _, row in ipairs(T().Tricks) do
		if row.Id == id then
			return row
		end
	end
	return nil
end

-- outcome of one knock: {Kind = "Treat"} | {Kind = "Trick", Trick = id, Row = row}. rand() -> [0, 1)
function Houses.Roll(rand: (() -> number)?): { [string]: any }
	rand = rand or rnd
	if rand() < (T().TreatChance or .6) then
		return { Kind = "Treat" }
	end
	local row = Shared.Weighted(T().Tricks, rand)
	return { Kind = "Trick", Trick = row.Id, Row = row }
end

function Houses.CandyRange(outcome: { [string]: any }): { number }
	if outcome.Kind == "Treat" then
		return Config.Candy.TreatHouse
	end
	return Config.Candy.TrickHouse
end

function Houses.BountyRange(): { number }
	return T().MiniBossCandy or Config.Candy.TreatHouse
end

function Houses.KnockedCount(h: any): number
	local n = 0
	for key, v in pairs(h.Houses.Knocked) do
		if v == true and Houses.ValidIndex(tonumber(key)) then
			n += 1
		end
	end
	return n
end

function Houses.CanKnock(h: any, index: number, day: number): boolean
	return h.Houses.Day ~= day or h.Houses.Knocked[tostring(index)] ~= true
end

-- transaction body. h = profile.Halloween after Feature.EnsureDaily (Core.Transact does that); ctx = Core ctx.
function Houses.Resolve(h: any, ctx: any, index: number, outcome: { [string]: any }, rand: (() -> number)?): { [string]: any }
	rand = rand or rnd
	check(Houses.ValidIndex(index) ~= nil, Houses.Messages.Invalid)
	local key = tostring(index)
	check(h.Houses.Knocked[key] ~= true, Houses.Messages.Already)
	h.Houses.Knocked[key] = true
	local treat = outcome.Kind == "Treat"
	local wanted = randInt(Houses.CandyRange(outcome), rand)
	local candy = ctx.Candy(wanted, treat and "Treat" or "Trick", { NoCap = true })
	ctx.Quest("Knock", 1)
	ctx.Stat("Knocks", 1)
	ctx.Souls(Config.Exorcism.Souls.Knock or 0)
	ctx.Relief("Knock")
	local knocked = Houses.KnockedCount(h)
	return {
		Message = string.format(treat and Houses.Messages.Treat or Houses.Messages.Trick, candy),
		Kind = outcome.Kind, Trick = outcome.Trick, Candy = candy, Index = index, Knocked = knocked, Day = h.Houses.Day,
		AllKnocked = knocked >= Houses.Count(),
	}
end

---------------------------------------------------------------------------------------------------------------------
-- Mini boss (Strike kind "MiniBoss")
---------------------------------------------------------------------------------------------------------------------
local core, modules = nil, nil
local strikeReady = false

local function signal(kind: string, data: any)
	if core then
		core.Signal("all", kind, data)
	end
end

local function bossPosition(index: number): Vector3
	local h = Layout.Houses[index]
	-- hit box centre on the front path between the porch steps and the yard gate (HouseFX raycasts the feet down)
	return h.Porch + Vector3.new(0, 2.1, 1.2)
end
Houses.BossPosition = bossPosition

local function targetId(target: any): any
	if type(target) ~= "table" then
		return nil
	end
	return target.Id or target.TargetId
end

local function bossHP(player: Player): number
	local Strike = modules and modules.Strike
	local hits = T().MiniBossHP or 6
	-- WP7 helpers when available: HP that needs `hits` average hits with this player's real pickaxe
	if Strike and type(Strike.HitsHP) == "function" then
		local ok, hp = pcall(Strike.HitsHP, player, hits)
		if ok and type(hp) == "number" and hp > 0 then
			return hp
		end
	end
	if Strike and type(Strike.HitDamage) == "function" then
		local ok, dmg = pcall(Strike.HitDamage, player)
		if ok and type(dmg) == "number" and dmg > 0 then
			return dmg * hits
		end
	end
	return hits
end

local function grantBounty(player: Player, index: number, reason: string)
	if not core or not player.Parent then
		return
	end
	local ok, res = core.Transact(player, "HouseBounty", function(_p, _h, ctx)
		local candy = ctx.Candy(randInt(Houses.BountyRange(), rnd), "MiniBoss", { NoCap = true })
		ctx.Souls(Config.Exorcism.Souls.Knock or 0)
		ctx.Relief("Break")
		return { Candy = candy, Message = string.format(Houses.Messages.BossDown, candy) }
	end)
	signal("HouseBoss", { Kind = "Down", Index = index, UserId = player.UserId, Candy = ok and res.Candy or 0, Reason = reason })
	if not ok and type(res) == "string" then
		core.Toast(player, res, "error")
	end
end

local function clearBoss(player: Player, reason: string?)
	local b = Houses.Bosses[player]
	if not b then
		return
	end
	Houses.Bosses[player] = nil
	local Strike = modules and modules.Strike
	if Strike and b.Target and not b.Broken then
		pcall(Strike.Remove, b.Target, reason or "Removed")
	end
end

function Houses.SpawnBoss(player: Player, index: number)
	if not player.Parent then
		return
	end
	local Strike = modules and modules.Strike
	if not (strikeReady and Strike and type(Strike.Add) == "function") then
		-- no timing-hit system on this server: never lose the reward
		grantBounty(player, index, "NoStrike")
		return
	end
	clearBoss(player, "Replaced")
	local hp = bossHP(player)
	local ok, target = pcall(Strike.Add, {
		Kind = "MiniBoss", Position = bossPosition(index), Radius = 3, HP = hp, MaxHP = hp,
		Color = Color3.fromRGB(236, 226, 200), Material = "Slate", Size = Vector3.new(4.4, 4.6, 5.2),
		Data = { House = index, UserId = player.UserId }, Owner = player, Shared = false,
		Name = "PORCH SKELETON", NameRU = "СКЕЛЕТ С КРЫЛЬЦА", Facing = math.pi, -- faces the lane (+Z)
		Attributes = { HouseIndex = index },
	})
	if not ok or target == nil then
		warn("Halloween Houses: mini boss spawn failed: " .. tostring(target))
		grantBounty(player, index, "NoStrike")
		return
	end
	local entry = { Target = target, Index = index, Id = targetId(target), Expires = Houses.Clock() + (T().MiniBossSeconds or 45) }
	Houses.Bosses[player] = entry
	signal("HouseBoss", { Kind = "Spawn", Index = index, UserId = player.UserId, TargetId = entry.Id })
	task.delay(T().MiniBossSeconds or 45, function()
		if Houses.Bosses[player] == entry and not entry.Broken then
			clearBoss(player, "Timeout")
			signal("HouseBoss", { Kind = "Escape", Index = index, UserId = player.UserId, TargetId = entry.Id })
			if player.Parent and core then
				core.Toast(player, Houses.Messages.BossEscape, "info")
			end
		end
	end)
end

function Houses.RegisterStrike()
	local Strike = modules and modules.Strike
	if strikeReady or not (Strike and type(Strike.Register) == "function") then
		return strikeReady
	end
	local ok, err = pcall(Strike.Register, "MiniBoss", {
		Range = 14, Verb = "STRIKE",
		CanHit = function(player: Player, target: any)
			local owner = type(target) == "table" and target.Owner or nil
			if owner ~= nil and owner ~= player then
				return false, "This skeleton is haunting another player"
			end
			return true
		end,
		OnBreak = function(player: Player, target: any, _info: any)
			local owner = (type(target) == "table" and target.Owner) or player
			local entry = Houses.Bosses[owner]
			local index = (entry and entry.Index) or (type(target) == "table" and type(target.Data) == "table" and target.Data.House) or 1
			if entry and (entry.Id == nil or entry.Id == targetId(target)) then
				entry.Broken = true
				Houses.Bosses[owner] = nil
			end
			if owner and owner.Parent then
				task.spawn(grantBounty, owner, index, "Broken")
			end
		end,
	})
	if not ok then
		warn("Halloween Houses: Strike.Register failed: " .. tostring(err))
		return false
	end
	strikeReady = true
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- Knock
---------------------------------------------------------------------------------------------------------------------
local busy = {}
local lastKnock = {}

local function knock(player: Player, index: any): (boolean, any)
	if not core then
		return false, "Not ready"
	end
	local i = Houses.ValidIndex(index)
	if not i then
		return false, Houses.Messages.Invalid
	end
	if not Shared.Enabled() then
		return false, "The Night of the Buried Moon has ended"
	end
	if not core.Near(player, Layout.Houses[i].Prompt, (T().Range or 12) + 4) then
		return false, Houses.Messages.TooFar
	end
	local clock = Houses.Clock()
	if busy[player] or clock - (lastKnock[player] or -1e9) < .8 then
		return false, Houses.Messages.Busy
	end
	busy[player] = true
	lastKnock[player] = clock
	local outcome = Houses.Roll()
	local okCall, ok, result = pcall(core.Transact, player, "HouseKnock", function(_p, h, ctx)
		return Houses.Resolve(h, ctx, i, outcome)
	end)
	busy[player] = nil
	if not okCall then
		return false, tostring(ok)
	end
	if not ok then
		return false, result
	end
	signal("House", { Index = i, Kind = result.Kind, Trick = result.Trick, UserId = player.UserId, Candy = result.Candy,
		Knocked = result.Knocked, Day = result.Day })
	if result.Kind == "Trick" then
		local row = Houses.TrickRow(result.Trick) or {}
		if result.Trick == "CurseBoost" then
			core.AddCurse(player, row.Curse or 18)
		elseif result.Trick == "MiniBoss" then
			task.delay(1.4, Houses.SpawnBoss, player, i) -- the skeleton jumps out once the door is open
		end
	end
	return true, result
end
Houses.Knock = knock

function Houses.Start(c, mods)
	core, modules = c, mods or {}
	Houses.RegisterStrike()
	local world = modules.World
	for i = 1, Houses.Count() do
		if world and type(world.Prompt) == "function" then
			world.Prompt("House" .. i, {
				Name = "HalloweenHousePrompt", ActionText = "KNOCK", ObjectText = "TRICK OR TREAT",
				MaxActivationDistance = T().Range or 12, HoldDuration = .25,
			}, function(player)
				local ok, err = knock(player, i)
				if not ok and type(err) == "string" and err ~= Houses.Messages.Busy then
					core.Toast(player, err, "error")
				end
			end)
		end
	end
	core.OnRequest("HouseKnock", function(player, a)
		return knock(player, tonumber(a.Index))
	end, { Cost = 2 })
	Players.PlayerRemoving:Connect(function(player)
		clearBoss(player, "Left")
		busy[player] = nil
		lastKnock[player] = nil
	end)
	return Houses
end

-- tests: inject a core / modules without starting prompts
function Houses._Bind(c, mods)
	core, modules = c, mods or {}
	strikeReady = false
end

return Houses
