-- Owned Halloween cosmetics after the event is switched off (ServerScriptService.Halloween.AfterEvent).
-- With Config.HalloweenEventEnabled = false the event server does not start (HalloweenServer), but pickaxe skins are
-- owned forever (docs/halloween2/DESIGN.md §2): the equipped skin keeps showing because the player attribute
-- PickaxeSkin is set from the saved profile, and the Halloween Request remote still answers SkinEquip so a skins menu
-- can change it (SkinList feeds the HALLOWEEN window's after-event cosmetics tab, opened from the SKINS rail tile while
-- the player attribute HwHasSkins is true). Every other action is refused politely. Player data is never written except
-- p.Halloween.Skin and the delivery of Chapter II dogs that were earned while the dog storage was full
-- (p.Underyard.PendingDogs, DESIGN §9.4).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local AE = {}

local function owned(h: any, id: string): boolean
	return type(h) == "table" and type(h.Skins) == "table" and h.Skins[id] == true
end

local function project(player: Player, Runtime: any)
	local p = Runtime.Views[player.UserId]
	local h = type(p) == "table" and p.Halloween or nil
	local skin = type(h) == "table" and type(h.Skin) == "string" and h.Skin or ""
	player:SetAttribute("PickaxeSkin", (skin ~= "" and owned(h, skin)) and skin or "")
	-- the SKINS rail tile (UITheme) shows while the player owns any Halloween pickaxe skin
	local any = false
	for _, v in pairs(type(h) == "table" and type(h.Skins) == "table" and h.Skins or {}) do
		if v == true then
			any = true
			break
		end
	end
	player:SetAttribute("HwHasSkins", any)
end

-- the skins part of a view for the HALLOWEEN window's after-event cosmetics tab: {Skins = {[id] = true}, Skin, Ended}
local function skinView(player: Player, Runtime: any): any
	local p = Runtime.Views[player.UserId]
	local h = type(p) == "table" and p.Halloween or nil
	local set = {}
	for id, v in pairs(type(h) == "table" and type(h.Skins) == "table" and h.Skins or {}) do
		if v == true and type(id) == "string" then
			set[id] = true
		end
	end
	local equipped = player:GetAttribute("PickaxeSkin")
	return { Skins = set, Skin = type(equipped) == "string" and equipped or "", Ended = true }
end

-- one parked Chapter II dog into the dog storage (the same mint as Halloween Core's ctx.Dog) -> true when delivered
local function deliverOne(player: Player, Runtime: any, R: any): boolean
	local uid = player.UserId
	local view = Runtime.Views[uid]
	local u = type(view) == "table" and view.Underyard or nil
	local first = type(u) == "table" and type(u.PendingDogs) == "table" and u.PendingDogs[1] or nil
	if type(first) ~= "table" or type(first.Id) ~= "string" or not R.Free(view) or not Runtime.Engine.AssetReady(first.Id) then
		return false
	end
	local id = first.Id
	local key, supplyKey = "p:" .. uid, "supply:" .. id
	local ok = Runtime.Tx:Run({ key, supplyKey }, function(v)
		local p = v[key]
		Runtime.Engine:Authorize(p, uid)
		local row = type(p.Underyard) == "table" and type(p.Underyard.PendingDogs) == "table" and p.Underyard.PendingDogs[1] or nil
		R.Check(type(row) == "table" and row.Id == id and R.Free(p), "Nothing to deliver")
		local supply = v[supplyKey] or {}
		v[supplyKey] = supply
		local dog = R.Mint(p, id, Runtime.Engine.Guid(), supply, os.time(), Runtime.Engine.Random, "BuriedMoon",
			type(row.Variant) == "string" and row.Variant or nil, true)
		dog.PricePaid = 0
		dog.Origin = "Underyard"
		table.remove(p.Underyard.PendingDogs, 1)
		R.Validate(p)
		return { Delivered = id }
	end)
	if ok then
		pcall(Runtime.Refresh, player)
	end
	return ok == true
end

function AE.Start(request: RemoteFunction?, closedMessage: string)
	local okRuntime, Runtime = pcall(function()
		return require(SSS:WaitForChild("Economy"):WaitForChild("Runtime"))
	end)
	local okRules, R = pcall(function()
		return require(SSS.Economy:WaitForChild("Rules"))
	end)
	if not okRuntime or not okRules then
		warn("Halloween AfterEvent: economy runtime unavailable")
		Runtime = nil
	end

	local function watch(player: Player)
		if not Runtime then
			return
		end
		task.spawn(function()
			for _ = 1, 120 do
				if not player.Parent then
					return
				end
				if Runtime.Ready(player) then
					project(player, Runtime)
					-- Chapter II dogs that waited for room in the dog storage still arrive after the event
					while player.Parent do
						local okD, delivered = pcall(deliverOne, player, Runtime, R)
						if not okD then
							warn("Halloween AfterEvent: pending dog delivery failed: " .. tostring(delivered))
						end
						task.wait(okD and delivered and 2 or 10)
					end
					return
				end
				task.wait(1)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end

	if not (request and request:IsA("RemoteFunction")) then
		return
	end
	local busy = {}
	request.OnServerInvoke = function(player: Player, action: any, args: any)
		if (action ~= "SkinEquip" and action ~= "SkinList") or not Runtime then
			return false, closedMessage
		end
		-- every equip is a profile write: the economy's request budget keeps a spamming client from lagging the server
		if type(Runtime.Allow) == "function" and not Runtime.Allow(player, 2) then
			return false, "Please wait a moment"
		end
		if busy[player] or not Runtime.Ready(player) then
			return false, "Your saved profile is still loading"
		end
		if action == "SkinList" then
			return true, { View = skinView(player, Runtime) }
		end
		local id = type(args) == "table" and type(args.Id) == "string" and #args.Id <= 40 and args.Id or ""
		busy[player] = true
		local key = "p:" .. player.UserId
		local ok, result = Runtime.Tx:Run({ key }, function(v)
			local p = v[key]
			Runtime.Engine:Authorize(p, player.UserId)
			local h = p.Halloween
			R.Check(id == "" or owned(h, id), "You don't own this skin")
			if type(h) == "table" then
				h.Skin = id
			end
			R.Validate(p)
			return { Message = id == "" and "Skin removed" or "Skin equipped", Skin = id }
		end)
		busy[player] = nil
		if not ok then
			return false, tostring(result)
		end
		player:SetAttribute("PickaxeSkin", id)
		if type(result) == "table" then
			result.View = skinView(player, Runtime)
		end
		return true, result
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return AE
