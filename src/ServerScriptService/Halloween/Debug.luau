-- Studio-only test commands for NIGHT OF THE BURIED MOON (ServerScriptService.Halloween.Debug).
-- Client panel: F7 in Studio (HalloweenClient.HUD) or the command bar:
--   game.ReplicatedStorage.Halloween.Remotes.Request:InvokeServer("Debug", {Cmd = "Candy", N = 500})
-- Commands: Candy {N}, Curse {N}, BloodMoon, BloodMoonNow, BloodMoonStop, Souls {N}, ResetDaily, Skins, Dog {Id},
--           Block {Tier}, Boss {Difficulty}, Brew (cauldron ready now), Onboarding (show the guide again), Rush.
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
end

return D
