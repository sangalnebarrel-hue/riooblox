local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local player = game:GetService("Players").LocalPlayer -- Halloween (WP10a)

local BACKGROUND_MUSIC_ID = 78560130014615

local NORMAL_VOLUME = 0.15
local EVENT_VOLUME = 0

local state = ReplicatedStorage
	:WaitForChild("WorldEvents")
	:WaitForChild("State")

local audioGroup = SoundService
	:WaitForChild("DOGROTS_AUDIO")
	:FindFirstChild("Ambient")

local music = Instance.new("Sound")
music.Name = "DOGROTS_BackgroundMusic"
music.SoundId = "rbxassetid://" .. BACKGROUND_MUSIC_ID
music.Looped = true
music.Volume = 0
music.SoundGroup = audioGroup
music.Parent = SoundService

music:Play()

local currentTween

local function updateMusic()
	local eventState = state:GetAttribute("State")

	local targetVolume

	if eventState == "ACTIVE" or eventState == "ENDING" then
		targetVolume = EVENT_VOLUME
	else
		targetVolume = NORMAL_VOLUME
	end
	-- Halloween (WP10a): another music owner (the Halloween OST) or the Music setting silences this track
	if SoundService:GetAttribute("DOGROTS_MusicOwner") ~= nil or (player and player:GetAttribute("Music") == false) then
		targetVolume = 0
	end

	if currentTween then
		currentTween:Cancel()
	end

	currentTween = TweenService:Create(
		music,
		TweenInfo.new(1.5),
		{Volume = targetVolume}
	)

	currentTween:Play()
end

state:GetAttributeChangedSignal("State"):Connect(updateMusic)
SoundService:GetAttributeChangedSignal("DOGROTS_MusicOwner"):Connect(updateMusic) -- Halloween (WP10a)
if player then
	player:GetAttributeChangedSignal("Music"):Connect(updateMusic)
end

updateMusic()