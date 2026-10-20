-- DOG SHELTER service: the actions of ReplicatedStorage.ShelterRequest (bound by CommunityServices; every call
-- returns true, data or false, message). The window is Modules.ShelterScreen (Kit window "Shelter").
--   List  {}                -> {Rows = {row}, Count, Sellable, Total, Rate, TTL, HoldSeconds, ServerNow}
--   Quote {Uid}             -> row + {Token (32 hex), TTL, Expires (server os.time), ServerNow}
--   Sell  {Token, Confirm?} -> {Message, Cash, Uid, Name, DogId, Balance}
-- row = {Uid, DogId, Name, Rarity, Variant, Mastery, AscensionLevel, Locked, Favorite, State, AssignedSlot, Edition,
--        SerialNumber, PaidRandom, Rank, Event, Price, Breakdown = {Base, Rate, Bonus, Variant, Mastery, Ascension,
--        Price}, Eligible, Reason?, Protection? (ShelterRules code), NeedsHold}
-- Rules (A07 fixes): the visit is judged with ShelterConfig.InReach (radius 26 around the reception or inside the
-- hall, D1); an unready profile and a rate-limited call get their own messages; a quote lives QuoteTTL seconds of
-- SERVER time and carries the TTL so the client never compares against its own clock (D3); Favorite dogs are
-- protected and rank >= 5 / event dogs need Confirm = true (D8); one broken dog cannot break the list (D13); a sale
-- records Stats.Sale + LastSaleAt and releases the dog's artifacts through the feature normalizers (D7).
-- A Sell retried with the same token is answered from the transaction receipt: never paid twice.
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local R = require(script.Parent.Rules)
local D = require(script.Parent.DogDefinitions)
local C = require(script.Parent.Config)
local Stats = require(script.Parent.RecordStats)
local SRules = require(script.Parent.ShelterRules)

local S = { Quotes = {} }
local Config = SRules.Config

local function runtime()
	return require(script.Parent.Runtime)
end

local function describe(d: any): any
	local def = D[d.DogId]
	return {
		Uid = d.DogUid,
		DogId = d.DogId,
		Name = def and def.DisplayName or d.DisplayName,
		Rarity = def and def.Rarity or d.Rarity,
		Variant = d.Variant,
		Mastery = d.Mastery or 0,
		AscensionLevel = d.AscensionLevel or 0,
		Locked = d.Locked == true,
		Favorite = d.Favorite == true,
		State = d.State,
		AssignedSlot = d.AssignedSlot or "",
		Edition = d.Edition,
		SerialNumber = d.SerialNumber or 0,
		PaidRandom = d.PaidRandom == true,
		Rank = def and def.Rank or 0,
		Event = def ~= nil and def.EventDex ~= nil,
	}
end

-- Price rounding can hide changes to mastery, mutation or other attributes: the player confirms the same
-- individual dog in the same state that was reviewed.
local function fingerprint(d: any): string
	return table.concat({
		d.DogUid, d.DogId, tostring(d.OwnerUserId), d.Variant or "", tostring(d.Mastery or 0), tostring(d.MasteryXP or 0),
		tostring(d.AscensionLevel or 0), d.Edition or "", tostring(d.SerialNumber or 0), tostring(d.Locked == true),
		tostring(d.Favorite == true), d.State or "", d.AssignedSlot or "", tostring(d.PaidRandom == true),
	}, "|")
end

-- One list row. Raises for a dog the catalog cannot price (the caller marks it protected instead).
function S.Row(p: any, uid: string, d: any, trading: any): any
	local def = D[d.DogId]
	local row = describe(d)
	local ok, reason, code = SRules.Eligible(p, uid, trading)
	local breakdown = SRules.Breakdown(d, D, R.Bonus, C)
	row.Price = breakdown.Price
	row.Breakdown = breakdown
	row.Eligible = ok
	row.Reason = reason
	row.Protection = code
	row.NeedsHold = SRules.NeedsHold(def)
	return row
end

-- A row for a record that could not be described (unknown definition, corrupt fields): shown, never sellable.
local function brokenRow(uid: any, d: any): any
	local record = type(d) == "table" and d or {}
	local text = function(v: any, fallback: string): string
		return type(v) == "string" and v or fallback
	end
	return {
		Uid = tostring(uid),
		DogId = text(record.DogId, ""),
		Name = text(record.DisplayName, text(record.DogId, "Dog")),
		Rarity = text(record.Rarity, "Common"),
		Variant = text(record.Variant, "Normal"),
		Mastery = 0,
		AscensionLevel = 0,
		Locked = record.Locked == true,
		Favorite = record.Favorite == true,
		State = text(record.State, ""),
		AssignedSlot = text(record.AssignedSlot, ""),
		Rank = 0,
		Event = false,
		Price = 0,
		Eligible = false,
		Reason = SRules.Messages.Error,
		Protection = "Error",
		NeedsHold = false,
	}
end

local function shelterAnchor(): BasePart?
	local district = workspace:FindFirstChild("DOGROTS_District")
	local hub = district and district:FindFirstChild("32_WelcomeHub")
	local building = hub and hub:FindFirstChild("DogShelter")
	local anchor = building and building:FindFirstChild("SellAnchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor
	end
	return nil
end

-- True while the player's living character is at the reception (server positions, ShelterConfig.InReach).
function S.InReach(player: Player): boolean
	local anchor = shelterAnchor()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (anchor and root and humanoid and humanoid.Health > 0) then
		return false
	end
	local offset = anchor.CFrame:PointToObjectSpace((root :: BasePart).Position)
	return SRules.InReach(offset.X, offset.Y, offset.Z, false)
end

function S.Visit(player: Player)
	R.Check(S.InReach(player), "Visit the reception inside Dog Shelter")
end

local function list(rt: any, player: Player): any
	local p = rt.Engine:Get(player.UserId)
	R.Check(type(p) == "table" and type(p.Dogs) == "table", "Please wait for your profile")
	local trading = rt.Engine.TradeByUser[player.UserId]
	local rows, sellable, total = {}, 0, 0
	for uid, d in pairs(p.Dogs) do
		local ok, row = pcall(S.Row, p, uid, d, trading)
		if not ok then
			warn("DOGROTS shelter: dog " .. tostring(uid) .. " cannot be listed: " .. tostring(row))
			row = brokenRow(uid, d)
		end
		table.insert(rows, row)
		if row.Eligible then
			sellable += 1
			total += row.Price
		end
	end
	table.sort(rows, SRules.Order)
	return {
		Rows = rows,
		Count = #rows,
		Sellable = sellable,
		Total = total,
		Rate = Config.Rate,
		TTL = Config.QuoteTTL,
		HoldSeconds = Config.HoldSeconds,
		ServerNow = os.time(),
	}
end

local function quote(rt: any, player: Player, a: any): any
	R.Check(type(a.Uid) == "string" and #a.Uid >= 1 and #a.Uid <= 100, "Invalid request")
	local p = rt.Engine:Get(player.UserId)
	R.Check(type(p) == "table" and type(p.Dogs) == "table", "Please wait for your profile")
	local trading = rt.Engine.TradeByUser[player.UserId]
	local ok, reason = SRules.Eligible(p, a.Uid, trading)
	R.Check(ok, reason)
	local d = p.Dogs[a.Uid]
	local q = S.Row(p, a.Uid, d, trading)
	local now = os.time()
	q.Token = (Http:GenerateGUID(false):gsub("-", ""))
	q.TTL = Config.QuoteTTL
	q.Expires = now + Config.QuoteTTL
	q.ServerNow = now
	q.Fingerprint = fingerprint(d)
	S.Quotes[player.UserId] = q
	local preview = R.Copy(q)
	preview.Fingerprint = nil
	return preview
end

local function sell(rt: any, player: Player, a: any): (boolean, any)
	R.Check(type(a.Token) == "string" and #a.Token == 32 and a.Token:match("^%x+$") ~= nil, "Invalid confirmation")
	local userId = player.UserId
	local key = "p:" .. userId
	-- 26 characters keep a journal key under the DataStore key limit; both ends of the token go in, so two tokens that
	-- share a prefix never share a receipt.
	local receipt = "sh:" .. userId .. ":" .. a.Token:sub(1, 13) .. a.Token:sub(-13)
	local confirmed = a.Confirm == true
	local ok, result = rt.Tx:Run({ key }, function(v)
		S.Visit(player)
		local now = os.time()
		local q = S.Quotes[userId]
		R.Check(q and q.Token == a.Token and now <= q.Expires, "Confirmation expired; choose the dog again")
		R.Check(not q.NeedsHold or confirmed, "Hold the button to confirm this sale")
		local p = v[key]
		rt.Engine:Authorize(p, userId)
		local valid, reason = SRules.Eligible(p, q.Uid, rt.Engine.TradeByUser[userId])
		R.Check(valid, reason)
		local d = p.Dogs[q.Uid]
		R.Check(fingerprint(d) == q.Fingerprint, "Dog changed; review this dog again before selling")
		R.Check(SRules.Price(d, D, R.Bonus) == q.Price, "Dog changed; request a new price")
		p.Dogs[q.Uid] = nil
		R.Credit(p, q.Price)
		-- A shelter sale is a sale: stats, the tutorial's sale step (LastSaleAt) and the lifetime coins.
		Stats.Sale(p, q.Price)
		p.LastSaleAt = now
		-- The feature normalizers give back what pointed at the dog (artifacts return to the bag, A07 D7). A failing
		-- normalizer must not block the sale: Rules.Validate still checks the structure below.
		if R.Features and R.Features.Normalize then
			local released, err = pcall(R.Features.Normalize, R, p, now)
			if not released then
				warn("DOGROTS shelter: release after sale: " .. tostring(err))
			end
		end
		R.Validate(p)
		return {
			Message = q.Name .. " found a new home! +" .. q.Price .. " Coins",
			Cash = q.Price,
			Uid = q.Uid,
			Name = q.Name,
			DogId = q.DogId,
			Balance = p.Cash,
		}
	end, receipt)
	if ok then
		local current = S.Quotes[userId]
		if current and current.Token == a.Token then
			S.Quotes[userId] = nil
		end
		local refreshed, err = pcall(rt.Refresh, player)
		if not refreshed then
			warn("DOGROTS shelter: refresh after sale: " .. tostring(err))
		end
		pcall(function()
			player:SetAttribute("LastShelterSaleAt", os.time())
		end)
	end
	return ok, result
end

function S.Request(player: Player, action: any, a: any): (boolean, any)
	local rt = runtime()
	R.Check(rt.Ready(player), "Please wait for your profile")
	R.Check(rt.Allow(player, 1), "Too many requests; wait a moment")
	R.Check(type(action) == "string" and type(a) == "table", "Invalid request")
	if action == "List" then
		S.Visit(player)
		return true, list(rt, player)
	elseif action == "Quote" then
		S.Visit(player)
		return true, quote(rt, player, a)
	elseif action == "Sell" then
		-- The visit is checked inside the transaction: a retry of a sale that already went through is answered
		-- from its receipt wherever the player stands.
		return sell(rt, player, a)
	end
	return false, "Unknown shelter action"
end

function S.Clear(userId: number)
	S.Quotes[userId] = nil
end

Players.PlayerRemoving:Connect(function(player)
	S.Quotes[player.UserId] = nil
end)

return S
