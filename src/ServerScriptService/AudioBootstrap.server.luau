-- Creates the sound buses SoundService.DOGROTS_AUDIO/{UI,SFX,Ambient} at server start (the place only
-- ships Music and WorldEvents). They replicate to every client; RewardAudio, WorldSound,
-- LabAudioConfig, WorldAmbience and UISound already route their sounds into them.
require(game:GetService('ReplicatedStorage'):WaitForChild('UISound')).EnsureGroups()
