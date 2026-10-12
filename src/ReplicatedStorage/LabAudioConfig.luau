-- Genetics lab sound cues (client). The place ships no uploaded lab SFX, so every cue is built from
-- sounds bundled with every Roblox client, re-pitched and filtered the same way Lucky.LuckyAudio and
-- Mining.MiningAudio do. Upload real SFX later by setting AssetIds (0 = built-in recipe).
--   Audio.Play(cue, parent?, volumeScale?)   parent: a part (3D) or nil (UI, SoundService)
-- Chamber cues: Console, Lock, Scan, Charge, Pulse, Reveal, Rare. Window cues: Select, Step, Confirm, Deny, Extract.
local SoundService=game:GetService('SoundService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Audio={}

Audio.AssetIds={Console=0,Lock=0,Scan=0,Charge=0,Pulse=0,Reveal=0,Rare=0,Select=0,Step=0,Confirm=0,Deny=0,Extract=0}

local TICK='rbxasset://sounds/volume_slider.ogg'
local COLLIDE='rbxasset://sounds/collide.wav'
local PING='rbxasset://sounds/electronicpingshort.wav'
local LAND='rbxasset://sounds/action_jump_land.mp3'

local active=0
local function shot(id,volume,speed,parent,effects,speedTo,rampTime)
 if active>=14 then return nil end
 local s=Instance.new('Sound');s.Name='LabCue';s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed or 1
 s.RollOffMinDistance=8;s.RollOffMaxDistance=70
 for class,props in pairs(effects or{})do
  local e=Instance.new(class);for k,v in pairs(props)do(e::any)[k]=v end;e.Parent=s
 end
 local group=SoundService:FindFirstChild('DOGROTS_AUDIO');local sfx=group and group:FindFirstChild('SFX')
 if sfx and sfx:IsA('SoundGroup')then s.SoundGroup=sfx end
 s.Parent=parent or SoundService
 active+=1
 local done=false
 local function finish()if not done then done=true;active-=1 end end
 s.Destroying:Once(finish)
 s.Ended:Once(function()finish();s:Destroy()end)
 s:Play()
 if speedTo then TweenService:Create(s,TweenInfo.new(rampTime or 1,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{PlaybackSpeed=speedTo}):Play()end
 Debris:AddItem(s,8)
 return s
end
local function later(t,fn)task.delay(t,fn)end

local CHIME={ReverbSoundEffect={DecayTime=1.8,WetLevel=-4}}
local GLASS={ReverbSoundEffect={DecayTime=2.6,WetLevel=-2},EqualizerSoundEffect={LowGain=-10,MidGain=0,HighGain=2}}
local THUNK={EqualizerSoundEffect={LowGain=10,MidGain=-2,HighGain=-30},ReverbSoundEffect={DecayTime=1.4,WetLevel=-6}}
local HUM={FlangeSoundEffect={Depth=.5,Mix=.75,Rate=3},ReverbSoundEffect={DecayTime=1.6,WetLevel=-5}}
local LOWPASS={EqualizerSoundEffect={LowGain=0,MidGain=0,HighGain=-18},DistortionSoundEffect={Level=.3}}
local STING={ReverbSoundEffect={DecayTime=5,WetLevel=0,DryLevel=-6,Density=1,Diffusion=1},EqualizerSoundEffect={LowGain=8,MidGain=-2,HighGain=-18}}

local CUES={}
-- The terminal wakes up: two soft glassy tones.
CUES.Console=function(parent,k)
 shot(PING,(.16)*k,.9,parent,GLASS)
 later(.12,function()shot(PING,(.14)*k,1.2,parent,GLASS)end)
end
-- The chamber seals: a low thunk with a short hiss.
CUES.Lock=function(parent,k)
 shot(LAND,(.45)*k,.55,parent,THUNK)
 shot(COLLIDE,(.22)*k,.6,parent,THUNK)
 later(.08,function()shot(TICK,(.12)*k,.3,parent,{EqualizerSoundEffect={LowGain=-20,MidGain=-4,HighGain=6},FlangeSoundEffect={Depth=.8,Mix=.9,Rate=9}})end)
end
-- DNA analysis: a run of quick electronic ticks rising in pitch.
CUES.Scan=function(parent,k)
 for i=0,7 do later(i*.07,function()shot(TICK,(.09)*k,1.4+i*.09,parent)end)end
end
-- Energy builds: a rising flanged tone over a slow heartbeat.
CUES.Charge=function(parent,k)
 shot(TICK,(.28)*k,.3,parent,HUM,1.2,1.3)
 for i=0,3 do later(i*.32,function()shot(TICK,(.18+i*.04)*k,.2+i*.015,parent,{EqualizerSoundEffect={LowGain=10,MidGain=-8,HighGain=-40}})end)end
end
-- The sequence lands: an impact under a shimmering ring.
CUES.Pulse=function(parent,k)
 shot(TICK,(.42)*k,.16,parent,{EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-30},DistortionSoundEffect={Level=.5},ReverbSoundEffect={DecayTime=2,WetLevel=-3}})
 shot(COLLIDE,(.25)*k,.8,parent)
 later(.05,function()shot(PING,(.18)*k,.75,parent,GLASS)end)
end
-- A result: a bright rising arpeggio.
CUES.Reveal=function(parent,k)
 for i,step in ipairs({1,1.25,1.5,2})do later((i-1)*.09,function()shot(TICK,(.17)*k,step*1.5,parent,CHIME)end)end
end
-- A rare result (mutated variant, secret bloodline): a long low sting, then a sparkling run.
CUES.Rare=function(parent,k)
 shot(TICK,(.5)*k,.12,parent,STING)
 later(.15,function()for i,step in ipairs({1,1.19,1.5,1.78,2,2.38})do later((i-1)*.08,function()shot(TICK,(.16)*k,step*1.5,parent,CHIME)end)end end)
 later(.6,function()shot(PING,(.2)*k,1.5,parent,GLASS)end)
end
-- Window feedback.
CUES.Select=function(parent,k)shot(TICK,(.1)*k,1.25,parent)end
CUES.Step=function(parent,k)
 shot(TICK,(.1)*k,1.1,parent)
 later(.06,function()shot(TICK,(.1)*k,1.5,parent)end)
end
CUES.Confirm=function(parent,k)
 shot(PING,(.14)*k,1,parent,CHIME)
 later(.1,function()shot(PING,(.12)*k,1.33,parent,CHIME)end)
end
CUES.Deny=function(parent,k)
 shot(TICK,(.16)*k,.5,parent,LOWPASS)
 later(.08,function()shot(TICK,(.16)*k,.42,parent,LOWPASS)end)
end
-- A dog dissolves into DNA: a falling, filtered sweep.
CUES.Extract=function(parent,k)
 shot(TICK,(.26)*k,1.6,parent,HUM,.4,.9)
 later(.35,function()shot(PING,(.12)*k,.6,parent,GLASS)end)
end

local throttle={Select=.05,Step=.08,Deny=.15,Scan=.3}
local lastPlayed={}
-- volume: optional multiplier (the presentation lowers the lab during world events).
function Audio.Play(cue,parent,volume)
 local now=os.clock()
 if throttle[cue]and now-(lastPlayed[cue]or 0)<throttle[cue]then return end
 lastPlayed[cue]=now
 local k=math.clamp(tonumber(volume)or 1,0,1)
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot('rbxassetid://'..string.format('%.0f',asset),.5*k,1,parent);return end
 local fn=CUES[cue]
 if fn then
  local ok,err=pcall(fn,parent,k)
  if not ok then warn('Lab audio '..tostring(cue)..': '..tostring(err))end
 end
end
function Audio.Has(cue)return CUES[cue]~=nil end

return Audio
