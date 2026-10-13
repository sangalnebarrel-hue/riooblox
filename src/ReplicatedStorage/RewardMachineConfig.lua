-- A free DOG TOKEN refills five hours after use; extra tokens can be bought (Lucky Spin
-- packs) by accounts that Roblox allows to buy paid random items (PolicyService checks every
-- purchase and every paid activation; free tokens are always spent first).
-- All outcomes occupy integer slots in the same 10,000-slot server pool shown on the odds
-- board, the CHANCES overlay and the token shop (RewardMachineOdds.Build).
-- The drum has exactly nine physical sectors (Sector_1..9), one row each, in drum order.
-- DogTier rows are rarity tiers: a win picks one of ALL released dogs of that rarity that the
-- machine may award (CanDropFromRoulette), uniformly; a row with several Ranks first picks the
-- rarity by RankWeights. Every rarity owns one probability budget, whatever its member count.
-- Aurion owns FixedUnits slots. While a world event whose perks carry MachineAurion is ACTIVE
-- (Rainbow Rift), those slots are multiplied (capped by EventBoostCap) for the whole
-- activation and every other row shrinks proportionally; the boost ends with the event.
-- docs/DOGOMATIC.md lists the table and the expected spins per rarity.
-- PriceRobux is intentionally unset; the UI reads each live Roblox product price.
-- Retain configured IDs/counts for retired products so pending receipts can resolve.

return {
	FreeOnly=false,
	Cost=0,
	TicketCost=1,
	TicketCapacity=1,
	StartingTickets=1,
	TicketRefillSeconds=18000,
	Cooldown=7,
	OddsDenominator=10000,
	EventBoostCap=10,

	TicketProducts={
		{
			Key='TicketSingle',
			Name='Lucky Spin',
			Count=1,
			Id=3717465311,
			Enabled=true,
			PriceRobux=nil
		},

		{
			Key='TicketPack5',
			Name='Lucky Bundle',
			Count=5,
			Id=3717461474,
			Enabled=true,
			PriceRobux=nil
		},

		{
			Key='TicketPack15',
			Name='Mega Spin Bundle',
			Count=15,
			Id=3717461640,
			Enabled=true,
			PriceRobux=nil
		},
	},

	Rewards={
		-- Nine rows, in drum order: each owns a physical sector (Sector_1..9)
		-- of the world drum. Weights are slots out of the 9,980 that Aurion leaves.

		{
			Kind='DogTier',
			Tier='Common',
			Ranks={1},
			Weight=2200,
			Name='Common Dog'
		},

		{
			Kind='DogTier',
			Tier='Rare',
			Ranks={2},
			Weight=1000,
			Name='Rare Dog'
		},

		{
			Kind='DogTier',
			Tier='Epic',
			Ranks={3},
			Weight=300,
			Name='Epic Dog'
		},

		{
			Kind='Item',
			Id='dog_tag',
			Weight=900,
			Name='Dog Tag'
		},

		{
			Kind='DogTier',
			Tier='Legendary',
			Ranks={4,5},
			RankWeights={[4]=3,[5]=1},
			Weight=120,
			Name='Legendary+ Dog'
		},

		{
			Kind='Cash',
			Amount=2400,
			Coins={
				MinCash=2400,
				IncomeMinutes=15
			},
			Weight=2660,
			Name='Coin Bag'
		},

		{
			Kind='Bones',
			Amount=40,
			Weight=1900,
			Name='40 Bones'
		},

		{
			Kind='Boost',
			Id='EnergySnack',
			Duration=900,
			Weight=900,
			Name='Energy Snack · 15 min'
		},

		{
			Kind='Dog',
			Id='Aurion',
			Weight=0,
			FixedUnits=20,
			Required=true,
			Jackpot=true,
			Name='Aurion'
		}
	}
}
