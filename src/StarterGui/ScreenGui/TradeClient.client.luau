-- Trade System 2.0 (docs/TRADE.md): loads the TRADE window module at start so a trade invitation
-- (DogEconomyPush 'TradeInvite') shows its popup and live trade pushes are heard even before the
-- window was opened once. The window itself is built only when it first opens.
local ok, err = pcall(function()
	require(script.Parent:WaitForChild("Modules"):WaitForChild("TradeScreen")).Start()
end)
if not ok then
	warn("DOGROTS trade client: " .. tostring(err))
end
