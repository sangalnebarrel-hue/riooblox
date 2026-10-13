-- Offline income: a welcome-back share of the team's real income (Rules.IncomeModel, the same
-- number as the HUD "+$/min"). Online, dogs pay their full income straight into the wallet.
return {
 Version=2,Enabled=true,Efficiency=.20,MaxAwaySeconds=2*60*60,MinAwaySeconds=5*60,
 -- MaxPendingCoins is a safety guard, not a game rule (MaxAwaySeconds is): it must stay above the
 -- strongest 2-hour payout (5 Void Secrets, full UPGRADE TREE, best artifacts and accessories: ~12.3B,
 -- docs/ECONOMY.md), otherwise offline bonuses (tree NIGHT/ENDLESS SHIFT, Offline accessories) do nothing.
 MaxPendingCoins=50000000000,
 Description='Assigned dogs keep earning 20% of their income for up to 2 hours while you are away. Online they earn the full amount.',
}
