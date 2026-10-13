-- Owner-uploaded world/UI sounds, played by ReplicatedStorage.WorldSound.Cue(name).
-- Id = an uploaded audio asset id (0 = none uploaded yet; the cue is then silent).
-- Sell: every sale (collector, bulk, NPC) plays it from EconomyVisuals; while Id is 0 the game's
-- built-in coin chime (MiningAudio) plays instead, so a sale is never silent.
return {
	Zones = {},
	Cues = {
		Sell = { Id = 0, Volume = 0.45, Preview = "Sell" },
	},
}