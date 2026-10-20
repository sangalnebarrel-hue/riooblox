-- Studio-only test commands for NIGHT OF THE BURIED MOON (ServerScriptService.Halloween.Debug).
-- Client panel: F7 in Studio (HalloweenClient.HUD) or the command bar:
--   game.ReplicatedStorage.Halloween.Remotes.Request:InvokeServer("Debug", {Cmd = "Candy", N = 500})
-- Commands: Candy {N}, Curse {N}, BloodMoon, BloodMoonNow, BloodMoonStop, Souls {N}, ResetDaily, Skins, Dog {Id},
--           Block {Tier}, Boss {Difficulty}, Brew (cauldron ready now), Onboarding (show the guide again), Rush.
-- CHAPTER II (request "C2Debug", Studio places only: RunService:IsStudio() and game.GameId == 0):
--   Shards {N}, Keys {N}, Fragments {N}, Dust {N}, Seal {N} (seals 1..N offered + cleared, 0 = reset), Offer {N},
--   Phase {N} (open seals 1..N early; no N = back to the dates), Complete1 (latch Chapter I), Reveal (show the
--   "IS THAT ALL?" reveal again), Tutorial {Step} (0 = restart, -1 = done), Contracts (finish today's contracts),
--   Daily (new UTC day state), Rested {N}, Calendar {N} (Calendar.Force; N < 0 follows the date), Finale (BossFinale.Debug /
--   Force), HP {N} (EventHP: enter the practice zone, N = damage), Descend / Ascend (portal without the prompt).
local RunService = game:GetService("RunService")

local D = {}
D.Commands = {}

function D.Start(core, modules)
	if not RunService:IsStudio() then
		return
	end
	local R = core.Rules
	local Config = core.Config
	local cmd = D.Commands
	cmd.Candy = function(player, a)
		return core.Transact(player, "Debug", function(_p, _h, ctx)
			return { Message = "+" .. ctx.Candy(math.clamp(tonumber(a.N) or 500, 1, 1e6), "Debug", { NoMult = true, NoCap = true }) .. " Candy" }
		end)
	end
	cmd.Curse = function(player, a)
		local st = core.State(player)
		if st then
			st.Curse = math.clamp(tonumber(a.N) or 100, 0, 100)
		end
		return true, { Message = "Curse set" }
	end
	cmd.BloodMoon = function()
		modules.BloodMoon.Force(false)
		return true, { Message = "Blood Moon warning started" }
	end
	cmd.BloodMoonNow = function()
		modules.BloodMoon.Force(true)
		return true, { Message = "Blood Moon is up" }
	end
	cmd.BloodMoonStop = function()
		modules.BloodMoon.Stop()
		return true, { Message = "Back to the schedule" }
	end
	cmd.Souls = function(player, a)
		modules.Exorcism.Add(math.clamp(tonumber(a.N) or 500, 1, 10000), player)
		return true, { Message = "Souls added" }
	end
	cmd.ResetDaily = function(player)
		return core.Transact(player, "Debug", function(_p, h)
			h.Quests.Day, h.Houses.Day, h.Rush.Day = -1, -1, -1
			return { Message = "Daily state reset" }
		end)
	end
	cmd.Skins = function(player)
		return core.Transact(player, "Debug", function(_p, _h, ctx)
			for _, id in ipairs(Config.Skins.Order) do
				ctx.Skin(id)
			end
			return { Message = "All skins granted" }
		end)
	end
	cmd.Dog = function(player, a)
		local id = type(a.Id) == "string" and a.Id or Config.Dogs.Order[1]
		R.Check(Config.Dogs.Defs[id] ~= nil, "Unknown event dog")
		return core.Transact(player, "Debug", function(_p, _h, ctx)
			ctx.Dog(id)
			return { Message = id .. " granted" }
		end, { Dogs = { id } })
	end
	cmd.Block = function(player, a)
		local tier = a.Tier == "Cursed Pumpkin" and "Cursed Pumpkin" or "Pumpkin"
		return core.Transact(player, "Debug", function(_p, _h, ctx)
			R.Check(ctx.Block(tier, 1), "Block storage full")
			return { Message = tier .. " block granted" }
		end)
	end
	cmd.Boss = function(player, a)
		local Boss = modules.Boss
		R.Check(Boss and Boss.Summon, "Boss module missing")
		local ok, err = Boss.Summon(math.clamp(tonumber(a.Difficulty) or 1, 1, 5), "Debug", player)
		return ok, ok and { Message = "The Gravekeeper rises" } or err
	end
	cmd.Brew = function(player)
		return core.Transact(player, "Debug", function(_p, h)
			h.Cauldron.StartedAt = os.time() - 8 * 86400
			return { Message = "Brew ready" }
		end)
	end
	cmd.Onboarding = function(player)
		return core.Transact(player, "Debug", function(_p, h)
			h.Onboarded = false
			return { Message = "Guide will show on the next visit" }
		end)
	end
	cmd.Rush = function(player)
		return core.Transact(player, "Debug", function(_p, h)
			h.Rush.Remaining = Config.CandyRush.Seconds
			h.Rush.Active = false
			return { Message = "Candy Rush refilled" }
		end)
	end
	core.OnRequest("Debug", function(player, a)
		local fn = cmd[a.Cmd]
		R.Check(fn ~= nil, "Unknown debug command")
		return fn(player, a)
	end, { Cost = .5 })
	D.StartChapter2(core, modules)
end

---------------------------------------------------------------------------------------------------------------------
-- CHAPTER II (C2Debug). Every write goes through Chapter2.Transact (EvenIfClosed: testable with the chapter off).
---------------------------------------------------------------------------------------------------------------------
D.C2 = {}
-- the first function a module exposes among `names` (other packages' debug hooks)
local function hook(m: any, names: { string }): any
	for _, name in ipairs(names) do
		if type(m) == "table" and type(m[name]) == "function" then
			return m[name]
		end
	end
	return nil
end

function D.StartChapter2(core, modules)
	local R = core.Rules
	local cmd = D.C2
	local function C2()
		local c2 = modules.Chapter2
		R.Check(c2 ~= nil, "Chapter II module missing")
		return c2
	end
	local function tx(player, fn, opts)
		opts = opts or {}
		opts.EvenIfClosed = true
		return C2().Transact(player, "C2Debug", fn, opts)
	end
	local function n(a, default, lo, hi)
		return math.clamp(math.floor(tonumber(a.N) or default), lo, hi)
	end
	cmd.Shards = function(player, a)
		return tx(player, function(_p, _u, ctx)
			return { Message = "+" .. ctx.Shards(n(a, 500, 1, 1e6), "Debug") .. " Bell Shards" }
		end)
	end
	cmd.Keys = function(player, a)
		return tx(player, function(_p, _u, ctx)
			return { Message = "+" .. ctx.Keys(n(a, 3, 1, 12), "Debug") .. " Coffin Keys" }
		end)
	end
	cmd.Fragments = function(player, a)
		return tx(player, function(_p, _u, ctx)
			return { Message = "+" .. ctx.Fragments(n(a, 90, 1, 99999)) .. " fragments" }
		end)
	end
	cmd.Dust = function(player, a)
		return tx(player, function(_p, _u, ctx)
			return { Message = "+" .. ctx.Dust(n(a, 1000, 1, 1e9)) .. " Lucky Dust" }
		end)
	end
	cmd.Seal = function(player, a)
		local upto = n(a, 1, 0, 7)
		return tx(player, function(_p, u, _ctx, now)
			for i = 1, 7 do
				local s = u.Seals[tostring(i)]
				if i <= upto then
					s.Offered, s.Cleared = true, true
					s.At = s.At > 0 and s.At or now
				else
					s.Offered, s.Cleared, s.Gold, s.At, s.Progress = false, false, false, 0, 0
				end
			end
			return { Message = "Seals cleared: " .. upto }
		end)
	end
	cmd.Offer = function(player, a)
		local i = n(a, 1, 1, 7)
		return tx(player, function(_p, u)
			u.Seals[tostring(i)].Offered = true
			return { Message = "Offering made: seal " .. i }
		end)
	end
	cmd.Phase = function(_player, a)
		local c2 = C2()
		local v = tonumber(a.N)
		c2.SetPhaseOverride(v and v >= 0 and v or nil)
		return true, { Message = "Phase " .. c2.Phase() }
	end
	cmd.Complete1 = function(player)
		return tx(player, function(_p, u, ctx, now)
			if not u.Chapter1.Complete then
				u.Chapter1.Complete, u.Chapter1.At = true, now
				ctx.Journal("chapter1")
				ctx.C2Signal("C2Reveal", { Chapter1 = true })
			end
			return { Message = "Chapter I complete" }
		end)
	end
	cmd.Reveal = function(player)
		return tx(player, function(_p, u, ctx)
			u.Chapter1.Notified = false
			u.RevealSeen = false
			ctx.C2Signal("C2Reveal", { Chapter1 = true })
			return { Message = "The reveal will play again" }
		end)
	end
	cmd.Tutorial = function(player, a)
		local step = math.floor(tonumber(a.Step or a.N) or 0)
		return tx(player, function(_p, u)
			if step < 0 then
				u.Tutorial.Done = true
			else
				u.Tutorial.Done, u.Tutorial.Step, u.Tutorial.Refunded, u.Tutorial.Mark = false, step, false, 0
			end
			return { Message = "Guide step " .. step }
		end)
	end
	cmd.Contracts = function(player)
		return tx(player, function(_p, u)
			for _, row in ipairs(u.Daily.Contracts.List) do
				row.Progress = row.Goal
			end
			return { Message = "Contracts finished" }
		end)
	end
	cmd.Daily = function(player)
		return tx(player, function(p, u, _ctx, now)
			u.Daily.Day = -1
			modules.Chapter2.Feature.EnsureDaily(p, now)
			return { Message = "Daily state reset" }
		end)
	end
	cmd.Rested = function(player, a)
		return tx(player, function(_p, u)
			u.Rested.Pool = n(a, 750, 0, 750)
			return { Message = "Rested pool " .. u.Rested.Pool }
		end)
	end
	cmd.Calendar = function(_player, a)
		local fn = hook(modules.Calendar, { "Force", "ForceStage", "SetStage", "Debug" })
		R.Check(fn ~= nil, "Calendar module missing")
		local v = tonumber(a.N)
		-- a negative N (or none) returns to following the date
		local ok, msg = fn(v and v >= 0 and math.clamp(math.floor(v), 0, 8) or nil)
		return ok ~= false, { Message = type(msg) == "string" and msg or ("Calendar stage " .. tostring(v or "auto")) }
	end
	cmd.Finale = function(player, a)
		local fn = hook(modules.BossFinale, { "Debug", "Force", "ForceStart" })
		R.Check(fn ~= nil, "Finale module missing")
		local ok, res = fn(player, a)
		return ok ~= false, type(res) == "table" and res or { Message = "Finale started" }
	end
	cmd.HP = function(player, a)
		local EventHP = modules.EventHP
		R.Check(EventHP ~= nil, "Event HP module missing")
		local dmg = tonumber(a.N)
		if dmg and dmg > 0 and type(EventHP.Damage) == "function" then
			EventHP.Damage(player, math.min(dmg, 1000), "Debug", {})
			return true, { Message = "Damage " .. dmg }
		end
		if type(EventHP.Enter) == "function" then
			EventHP.Enter(player, "Practice")
		end
		return true, { Message = "Event HP on" }
	end
	cmd.Descend = function(player)
		local UY = modules.Underyard
		R.Check(UY ~= nil, "Underyard module missing")
		local ok, err = UY.Descend(player)
		return ok, ok and { Message = "Descending" } or err
	end
	cmd.Ascend = function(player)
		local UY = modules.Underyard
		R.Check(UY ~= nil, "Underyard module missing")
		local ok, err = UY.Ascend(player)
		return ok, ok and { Message = "Ascending" } or err
	end
	core.OnRequest("C2Debug", function(player, a)
		R.Check(RunService:IsStudio() and game.GameId == 0, "Unknown debug command")
		local fn = cmd[a.Cmd]
		R.Check(fn ~= nil, "Unknown debug command")
		return fn(player, a)
	end, { Cost = .5, AllowDisabled = false })
end

return D
