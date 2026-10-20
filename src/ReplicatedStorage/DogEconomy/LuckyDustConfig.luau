-- LUCKY DUST balance (docs/halloween2/DESIGN.md §14): dismantling Lucky Blocks into Lucky Dust and forging new
-- blocks from it at the DUST FORGE. Every number of the system lives here; the maths is in
-- ReplicatedStorage.Halloween.DustRules (pure, tested by tests/lucky_dust.luau), the server actions in
-- ServerScriptService.Economy.Features.LuckyDust and the screens in Modules.InventoryScreen (LUCKY BLOCKS / FORGE).
-- Lucky Dust itself is a stored resource (DogEconomy.Resources.Kinds.LuckyDust, p.Resources.LuckyDust).
local C = {}

C.Version = 1

-- Value: 1 dust stands for 100 coins of block value (DustRules.BlockValue: min(conveyor price, EV of the contents);
-- event tiers use their TradeValue).
C.CoinsPerDust = 100

-- Dismantling returns this share of a block's value as dust. Allowed range .20-.30 (DustRules clamps to it, the tests
-- prove that no dismantle -> forge cycle pays back at any value inside the range).
C.Salvage = 0.25
C.SalvageMin = 0.20
C.SalvageMax = 0.30

-- Forging charges the full value (ForgeRate 1 = 100 %), only for these tiers (never Mythic, Secret or event tiers).
C.ForgeRate = 1
C.Forgeable = { "Common", "Rare", "Epic", "Legendary" }
C.ForgeMaxCount = 5 -- blocks per DustForge request (the bag forges one at a time)

-- Dismantles that contain a block of this rank or higher (Legendary, Mythic, Secret, Pumpkin 4, Cursed Pumpkin 5)
-- need an explicit confirmation (Dismantle {Confirm = true}; the bag asks for a hold-to-confirm).
C.ConfirmRank = 4

-- NIGHT OF THE BURIED MOON tiers also return Halloween candy (event resource, Features.Halloween.AddCandy). Only
-- while the Halloween event is on; no souls, no quest progress.
C.EventCandy = { Pumpkin = 15, ["Cursed Pumpkin"] = 50 }

-- Requests.
C.MaxBatch = 30 -- blocks per dismantle (block uids + legacy credit stacks)
C.QuoteSeconds = 60 -- a quote token lives this long in server RAM
C.ReceiptCount = 8 -- dismantle results kept in the profile (a repeated token answers the same result)

-- The bag's "DISMANTLE ALL" picker offers these tiers (cheap blocks people collect in piles).
C.BulkTiers = { "Common", "Rare" }

return C
