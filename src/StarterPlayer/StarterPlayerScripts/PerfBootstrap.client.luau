-- Starts the shared client performance state as early as possible after join:
-- Perf.Quality (tier, reduced motion and the WorldEventFX / LowFX / ReducedMotion attributes the
-- older effect scripts read) and the "DOGROTS_Lod" CollectionService tag path of Perf.Lod.
-- Every other script requiring these modules shares this one state.
local Perf = game:GetService("ReplicatedStorage"):WaitForChild("Perf")
require(Perf:WaitForChild("Quality")).Start()
require(Perf:WaitForChild("Lod")).StartTags()
