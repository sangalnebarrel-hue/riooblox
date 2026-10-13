--!nocheck
-- Generator of tests/fixtures/legacy_profile_v5.json: a rich profile built by the PRE-OVERHAUL code
-- (git tag pre-overhaul-v5). Not a test. To regenerate: check the tag out into a scratch worktree,
-- copy this file to <worktree>/tests/ and run `lune run tests/make_legacy_v5.luau <out.json>` there.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local L = require("./lib/economy_env")
local NOW = 1760000000
L.Time = NOW
local folder = function() return { GetChildren = function() return {} end, FindFirstChild = function() return nil end } end
L.Workspace = setmetatable({
	WaitForChild = function() return { WaitForChild = function() return folder() end } end,
	GetServerTimeNow = function() return L.Time end,
	FindFirstChild = function() return nil end,
}, { __index = function() return nil end })
L.Overrides["ServerScriptService/Economy/Runtime"] = { Views = {}, Ready = function() return true end, Allow = function() return true end }
L.Overrides["ServerScriptService/Economy/ServerLuck"] = { Ranks = function() return {} end }
local R = L.Require("ServerScriptService.Economy.Rules")
local function rng(seed)
	local state = seed or 7
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
local p = R.Profile(424242, NOW)
R.Normalize(p, 424242, NOW)
p.Cash = 12345678
p.Bones = 4321
p.Level = 30
p.XP = 1200
for i = 1, 4 do p.UnlockedLayers[tostring(i)] = true end
p.CurrentLayer = 3
p.Upgrades.DogStorage = 20
p.Upgrades.Plot = 5 -- yard stage 6: all 5 kennels
p.Prestige = 1
-- Earned titles of every legacy kind, one equipped.
p.Cosmetics = { Dex10 = true, Dex25 = true, SetHounds = true, ["Discovery:CROWN_JEWELS:Normal"] = true, Prestige1 = true, Event2 = true, Finds100 = true, GoldenKennel = true }
p.EquippedCosmetic = "Dex25"
-- Dogs with variants, mastery, ascension, a lab dog and a locked favourite.
local ids = { "Breadog", "Sausagedog", "Potatodog", "KingCorgi", "Cerberdog", "Breadog" }
local variants = { "Normal", "Golden", "Void", "Shiny", "Corrupted", "Glitched" }
for i, id in ipairs(ids) do
	local ok, d = pcall(R.Mint, p, id, string.format("legacy%02d", i), {}, NOW, rng(i), "Test", variants[i], true)
	if ok and d then
		d.Mastery = 10 * i
		if i <= 5 then d.AssignedSlot = "DigSlot_" .. i; d.State = "Digging"; d.NextWorkAt = NOW end
		if i == 6 then d.Locked = true; d.Favorite = true; d.AscensionLevel = 2; d.Origin = "LAB_FUSION"; d.LabRecipe = "GOLDEN_BREAKFAST" end
	end
end
-- 30 minutes of real digging: coins, finds, records, feed, dog income.
for s = 1, 1800 do
	L.Time = NOW + s
	R.Normalize(p, 424242, L.Time)
	R.Dig(p, L.Time, rng(1000 + s))
end
-- Lab data from the old procedures.
p.Lab.DNA = p.Lab.DNA or {}
p.Lab.DNA.CommonDNA = 14; p.Lab.DNA.RareDNA = 3; p.Lab.DNA.MutationShards = 5
p.Lab.Experiments = 9; p.Lab.TutorialComplete = true
-- Mining state mid-ore on Limestone with the old HP/value.
p.Mining.PickaxeOwned = 3; p.Mining.PickaxeLevel = 3; p.Mining.Strength = 150; p.Mining.OresBroken = 321
p.Mining.Collection = { Limestone = 120, Coal = 80, Copper = 60, Iron = 40, Gold = 21 }
-- A favourite find and a market-free item.
local n = 0
for uid, x in pairs(p.Items) do n += 1; if n == 1 then x.Favorite = true end end
R.Validate(p)
local json = serde.encode("json", p)
fs.writeFile(process.args[1], json)
print("legacy profile:", #json, "bytes;", n, "items;", (function() local c = 0 for _ in pairs(p.Dogs) do c += 1 end return c end)(), "dogs; cash", p.Cash)
