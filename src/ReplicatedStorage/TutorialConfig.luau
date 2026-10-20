-- Main DOGROTS tutorial, version 4 (docs/halloween2/TUTORIAL.md): the step track shared by the server rules
-- (ServerScriptService.Economy.OnboardingRules) and the client director (Modules.TutorialDirector), plus every
-- tutorial number. Pure data: no services, safe to require from tests.
--
-- Step kinds:
--   Intro      the welcome card; the server waits for Tutorial {Action = "Start"}
--   Milestone  done when the profile shows it (OnboardingRules.Observe sets Seen[Flag] from profile state)
--   View       done when the client reports the screen as open: Tutorial {Action = "Seen", Key}
--              (the profile Evidence also completes it, e.g. a player who already unlocked Caverns)
--   Arrive     done when the server sees the character at the place: Tutorial {Action = "Arrive", Key}
--              (radius checked with server positions, Arrive[Key] below)
--   Final      the last card; Tutorial {Action = "Finish"} completes the tutorial
-- Every step from 1 to LastStep - 1 can be skipped with Tutorial {Action = "SkipStep"} once it has run for
-- SkipAfter seconds (the server records Skipped[step]); a step never becomes a dead end.
local C = {}

C.Version = 4
C.LastStep = 14

-- Seconds a step must have been running before SKIP THIS STEP is accepted (server and client).
C.SkipAfter = 120
-- Client: seconds before a tutorial request counts as lost (buttons come back with RETRY).
C.RequestTimeout = 8
-- Client: the camera focus on a step's target (none with reduced motion).
C.FocusSeconds = 2.2
-- Client: seconds to wait for a streamed-in target before falling back to the destination anchor.
C.TargetWait = 3
-- Client: seconds after EconomyReady before the first card shows (lets the arrival camera settle).
C.ShowAfter = 2
-- Client: seconds between Arrive reports while the character stands in range and the server refused.
C.ArriveRetry = 3
-- Client: how often the director re-evaluates targets, distances and timers (render is event driven too).
C.Tick = 0.5
-- Client: a moving target (a dog on THE DOG's tongue) is re-picked at most this often.
C.RetargetEvery = 4

-- The free Lucky Block of the LUCKY BLOCKS step (granted once, only while there is storage room).
C.FreeBlock = { Tier = "Common", Origin = "Tutorial" }

-- Arrive steps: Radius is what the client waits for before it reports; the server accepts Radius + Slack
-- (a lagged client position, DESIGN §4.4).
C.Arrive = {
	-- any LuckyPad_n of the player's own yard (LuckyLifecycleConfig.PlacementSlots pads)
	LuckyPad = { Radius = 14, Slack = 6 },
	-- the Mutation Lab: its entrance gap and the START MUTATION console (05_MutationLab anchors)
	Lab = { Radius = 22, Slack = 6, Anchors = { "EntranceAnchor", "InteractionAnchor" }, Fallback = { Vector3.new(66, 3, 477), Vector3.new(77, 3.9, 477) } },
}

-- The track. Flag: the Seen key that completes the step. Key: the Seen / Arrive key the client sends.
-- Destination: Navigation.Destinations key for SHOW ME (PathGuide). Screen: the menu the step opens
-- (gui OpenMenu value the director watches for View steps).
C.Steps = {
	[0] = { Id = "Welcome", Kind = "Intro" },
	[1] = { Id = "BuyDog", Kind = "Milestone", Flag = "DogOwned", Destination = "DogLine" },
	[2] = { Id = "Assign", Kind = "Milestone", Flag = "Assigned", Destination = "MyKennels" },
	[3] = { Id = "FirstDig", Kind = "Milestone", Flag = "Found", Destination = "MyKennels" },
	[4] = { Id = "Collect", Kind = "View", Flag = "Inventory", Key = "Inventory", Screen = "Inventory" },
	[5] = { Id = "Sell", Kind = "Milestone", Flag = "Sold", Destination = "Collector" },
	[6] = { Id = "Upgrade", Kind = "Milestone", Flag = "Upgraded", Screen = "UpgradeTree" },
	[7] = { Id = "Layers", Kind = "View", Flag = "Layers", Key = "Layers", Screen = "Layers" },
	[8] = { Id = "Mining", Kind = "Milestone", Flag = "MiningHit", Destination = "MiningCorner" },
	[9] = { Id = "Strength", Kind = "Milestone", Flag = "StrengthTrain", Screen = "UpgradeTree" },
	[10] = { Id = "Lucky", Kind = "Arrive", Flag = "LuckyPad", Key = "LuckyPad", Destination = "PlayerYards" },
	[11] = { Id = "Lab", Kind = "Arrive", Flag = "Lab", Key = "Lab", Destination = "MutationLab" },
	[12] = { Id = "DogDex", Kind = "View", Flag = "DogDex", Key = "DogDex", Screen = "DogDex" },
	[13] = { Id = "Trade", Kind = "View", Flag = "Trade", Key = "Trade", Screen = "Trade" },
	[14] = { Id = "Done", Kind = "Final" },
}

-- Strength branch of the UPGRADE TREE (step 9 completes with any level of one of these).
C.StrengthNodes = { "IronGrip", "HeavyLifter", "TitanBack", "Colossus", "MountainBreaker" }

-- Version 3 (18 cards, 0..17) -> version 4 step for players who were still in the tutorial. Each old step goes
-- to the first version-4 step that teaches what they had not seen yet; Observe then fast-forwards past
-- everything their profile already proves. Players who had finished or skipped are never pulled back.
--   v3: 0 welcome, 1 dog, 2 assign, 3 dig, 4 sell, 5 level 2, 6 upgrade tree, 7 mining, 8 strength,
--       9 pickaxes (info), 10 dog line + depths (info), 11 lucky blocks (info), 12 dog-o-matic (info),
--       13 lab (info), 14 dogdex (info), 15 trading (info), 16 events (info), 17 final
C.MigrateV3 = {
	[0] = 0,
	[1] = 1,
	[2] = 2,
	[3] = 3,
	[4] = 5, -- they had a find to sell: COLLECT is behind them
	[5] = 6, -- REACH LEVEL 2 is gone; next is the UPGRADE TREE
	[6] = 6,
	[7] = 7, -- LAYERS is new and comes before the quarry (already-mined players skip 8 at once)
	[8] = 7,
	[9] = 7,
	[10] = 7,
	[11] = 10,
	[12] = 11, -- DOG-O-MATIC is gone; next is the LAB
	[13] = 11,
	[14] = 12,
	[15] = 13,
	[16] = 14, -- EVENTS is gone; the final card
	[17] = 14,
}

function C.Step(index: number?): any
	return index ~= nil and C.Steps[index] or nil
end

-- Step index of a Seen / Arrive key (nil when no step uses it).
function C.StepOfKey(key: any): number?
	for index = 0, C.LastStep do
		local step = C.Steps[index]
		if step and step.Key == key then
			return index
		end
	end
	return nil
end

-- Can SKIP THIS STEP be used on `index` that started at `startedAt` (unix), at `now`?
function C.CanSkipStep(index: number, startedAt: number?, now: number): boolean
	if index < 1 or index >= C.LastStep then
		return false
	end
	return now >= (tonumber(startedAt) or 0) + C.SkipAfter
end

return C
