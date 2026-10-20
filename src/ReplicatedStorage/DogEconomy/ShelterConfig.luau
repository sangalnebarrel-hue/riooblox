-- DOG SHELTER numbers, shared by the server rules (ServerScriptService.Economy.ShelterRules) and the window
-- (StarterGui.ScreenGui.Modules.ShelterScreen). Pure data plus the visit rule; no services.
--
-- Visit rule (InReach): the player's HumanoidRootPart in DogShelter.SellAnchor's object space is within VisitRadius
-- studs of the reception anchor, or inside the shelter hall box. The server adds Slack to the box (it judges a lagged
-- copy of a character running at up to 72 studs/s); the client closes its window with the stricter CloseRadius and no
-- slack, so a window that is open is always served (A07 D1). The ShelterPrompt itself reaches 13 studs and the doorway
-- is 24 studs from the anchor.
local C = {
	Rate = 0.25, -- share of the catalog value the shelter pays (a definition may set ShelterRate)
	VisitRadius = 26, -- server acceptance radius around SellAnchor
	CloseRadius = 24, -- client: the window closes beyond this outside the hall
	-- The hall around the reception desk in SellAnchor object space: walls at x -24 / +22, side walls at z -38 / +38.
	Reception = { Offset = { -1, 4.5, 0 }, Size = { 48, 18, 78 }, Slack = 2 },
	QuoteTTL = 45, -- seconds a reviewed price stays valid (server clock; the client counts TTL down on os.clock)
	HoldRank = 5, -- Mythic and Secret dogs (and every event dog) are sold with a hold-to-confirm
	HoldSeconds = 1.2, -- the hold of the CONFIRM button
	RetryDelay = 0.75, -- one automatic retry of a List refused for a lagged visit or a busy / loading profile
	ClosePoll = 0.5, -- client: seconds between the walk-away checks while the window is open
}

function C.InReach(x: number, y: number, z: number, client: boolean?): boolean
	local radius = client and C.CloseRadius or C.VisitRadius
	if x * x + y * y + z * z <= radius * radius then
		return true
	end
	local box = C.Reception
	local slack = client and 0 or (box.Slack or 0)
	return math.abs(x - box.Offset[1]) <= box.Size[1] / 2 + slack
		and math.abs(y - box.Offset[2]) <= box.Size[2] / 2 + slack
		and math.abs(z - box.Offset[3]) <= box.Size[3] / 2 + slack
end

return C
