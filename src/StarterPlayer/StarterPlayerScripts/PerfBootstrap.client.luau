-- Starts the shared client performance state as early as possible after join:
-- Perf.Quality (tier, reduced motion and the WorldEventFX / LowFX / ReducedMotion attributes the
-- older effect scripts read), the "DOGROTS_Lod" CollectionService tag path of Perf.Lod, and the
-- UISound volume buses (Setting_UIVolume / Setting_SFXVolume -> SoundService.DOGROTS_AUDIO groups).
-- Every other script requiring these modules shares this one state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Perf = ReplicatedStorage:WaitForChild("Perf")
require(Perf:WaitForChild("Quality")).Start()
require(Perf:WaitForChild("Lod")).StartTags()
require(ReplicatedStorage:WaitForChild("UISound")).Start()
