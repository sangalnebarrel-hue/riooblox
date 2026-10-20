-- Genetics lab sound cues (client). The place ships no uploaded lab SFX, so every cue is built from
-- sounds bundled with every Roblox client, re-pitched and filtered the same way Lucky.LuckyAudio and
-- Mining.MiningAudio do. Upload real SFX later by setting AssetIds (0 = built-in recipe).
--   Audio.Play(cue, parent?, volumeScale?, pitch?)   parent: a part (3D) or nil (UI, SoundService)
-- Chamber cues: Console, Lock, Scan, Charge, Pulse, Reveal, Rare. Window cues: Select, Step, Confirm, Deny, Extract.
-- Mutation machine cues (Modules.LabPresentation): Activate (button + alarm), Servo (arm and lift), Fill
-- (liquid rising), Tick (one colour-reel step; pitch rises as the reel slows), Arc (electric zap).
-- Nuclear tower cues (Modules.LabPresentation): DoorOpen, DoorSlam, Beam, Fail, Coins, Crack, Flash,
-- Eruption, Splat, ErrorBeep, Key (one typed key), Thunder, Portal, Pop (the dog back in the inventory),
-- Boom. Loops (Audio.Loop): Siren (the nuclear alarm), Rumble, VoidHum.
local SoundService=game:GetService('SoundService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Audio={}

Audio.AssetIds={Console=0,Lock=0,Scan=0,Charge=0,Pulse=0,Reveal=0,Rare=0,Select=0,Step=0,Confirm=0,Deny=0,Extract=0,Activate=0,Servo=0,Fill=0,Tick=0,Arc=0,
 DoorOpen=0,DoorSlam=0,Beam=0,Fail=0,Coins=0,Crack=0,Flash=0,Eruption=0,Splat=0,ErrorBeep=0,Key=0,Thunder=0,Portal=0,Pop=0,Boom=0,Siren=0,Rumble=0,VoidHum=0}

local TICK='rbxasset://sounds/volume_slider.ogg'
local COLLIDE='rbxasset://sounds/collide.wav'
local PING='rbxasset://sounds/electronicpingshort.wav'
local LAND='rbxasset://sounds/action_jump_land.mp3'
local WIND='rbxasset://sounds/action_falling.mp3'
local SPLAT='rbxasset://sounds/splat.wav'
local CLICK='rbxasset://sounds/clickfast.wav'

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

-- The machine: a heavy clunk of the big button, then a two-tone alarm.
CUES.Activate=function(parent,k)
 shot(LAND,(.5)*k,.5,parent,THUNK)
 shot(COLLIDE,(.25)*k,.45,parent,THUNK)
 for i=0,2 do later(.15+i*.28,function()shot(PING,(.13)*k,i%2==0 and .62 or .5,parent,{DistortionSoundEffect={Level=.35},ReverbSoundEffect={DecayTime=1.2,WetLevel=-6}})end)end
end
-- Hydraulics: a filtered rising whir.
CUES.Servo=function(parent,k)
 shot(TICK,(.22)*k,.35,parent,{EqualizerSoundEffect={LowGain=6,MidGain=-4,HighGain=-24},FlangeSoundEffect={Depth=.6,Mix=.8,Rate=6}},.7,.9)
end
-- Liquid floods the chamber: low bubbling ticks.
CUES.Fill=function(parent,k)
 for i=0,9 do later(i*.09,function()shot(TICK,(.07)*k,.25+math.random()*.2,parent,{EqualizerSoundEffect={LowGain=8,MidGain=-6,HighGain=-30},ReverbSoundEffect={DecayTime=1.4,WetLevel=-4}})end)end
end
-- One step of the colour reel (pitch from the caller).
CUES.Tick=function(parent,k,pitch)
 shot(TICK,(.16)*k,(pitch or 1)*1.3,parent,CHIME)
end
-- Electric arc: a short distorted crackle.
CUES.Arc=function(parent,k)
 shot(COLLIDE,(.12)*k,1.6+math.random()*.6,parent,{DistortionSoundEffect={Level=.8},EqualizerSoundEffect={LowGain=-12,MidGain=0,HighGain=4}})
end

-- NUCLEAR TOWER ----------------------------------------------------------------------------------
-- The blast door: hydraulics whine up, then a heavy latch.
CUES.DoorOpen=function(parent,k)
 shot(TICK,(.3)*k,.25,parent,{EqualizerSoundEffect={LowGain=8,MidGain=-4,HighGain=-26},FlangeSoundEffect={Depth=.7,Mix=.85,Rate=4}},.65,1.4)
 shot(WIND,(.25)*k,.5,parent,{EqualizerSoundEffect={LowGain=6,MidGain=-6,HighGain=-30}})
 later(1.3,function()shot(LAND,(.5)*k,.45,parent,THUNK)end)
end
CUES.DoorSlam=function(parent,k)
 shot(LAND,(.8)*k,.38,parent,THUNK)
 shot(COLLIDE,(.45)*k,.35,parent,THUNK)
 later(.05,function()shot(LAND,(.4)*k,.3,parent,STING)end)
end
-- The sky beam: a rising flanged roar and a deep impact.
CUES.Beam=function(parent,k)
 shot(TICK,(.45)*k,.18,parent,HUM,1.4,1.1)
 shot(WIND,(.5)*k,.6,parent,{EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-10},DistortionSoundEffect={Level=.35}})
 later(.9,function()shot(LAND,(.7)*k,.32,parent,STING)end)
end
-- MUTATION FAILED: three low buzzes.
CUES.Fail=function(parent,k)
 for i=0,2 do later(i*.34,function()shot(TICK,(.38)*k,.22,parent,{DistortionSoundEffect={Level=.9},EqualizerSoundEffect={LowGain=6,MidGain=2,HighGain=-20}})end)end
end
-- Golden: a shower of coin chinks.
CUES.Coins=function(parent,k)
 for i=0,15 do later(i*.07+math.random()*.05,function()shot(PING,(.1)*k,1.6+math.random()*.8,parent,CHIME)end)end
end
-- Shiny: the concrete cracks with a glassy ring.
CUES.Crack=function(parent,k)
 shot(COLLIDE,(.4)*k,1.4+math.random()*.4,parent,GLASS)
 shot(LAND,(.3)*k,.9,parent,{EqualizerSoundEffect={LowGain=-6,MidGain=2,HighGain=4}})
end
CUES.Flash=function(parent,k)
 shot(PING,(.22)*k,2,parent,GLASS)
 later(.04,function()shot(TICK,(.2)*k,2.6,parent,CHIME)end)
end
-- Corrupted: the eruption (a roaring gush) and the drops landing.
CUES.Eruption=function(parent,k)
 shot(WIND,(.7)*k,.45,parent,{EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-12},DistortionSoundEffect={Level=.5}},.8,2)
 for i=0,5 do later(i*.18,function()shot(SPLAT,(.35)*k,.5+math.random()*.3,parent,THUNK)end)end
end
CUES.Splat=function(parent,k)shot(SPLAT,(.3)*k,.7+math.random()*.5,parent)end
-- Glitched: the error ding and keyboard keys.
CUES.ErrorBeep=function(parent,k)
 shot(PING,(.3)*k,.72,parent,CHIME)
 later(.12,function()shot(PING,(.28)*k,.54,parent,CHIME)end)
end
CUES.Key=function(parent,k)shot(CLICK,(.25)*k,.9+math.random()*.3,parent)end
-- Void: thunder, the portal's swirl.
CUES.Thunder=function(parent,k)
 shot(LAND,(.8)*k,.22,parent,STING)
 shot(WIND,(.5)*k,.35,parent,{EqualizerSoundEffect={LowGain=10,MidGain=-4,HighGain=-20},ReverbSoundEffect={DecayTime=4,WetLevel=0}})
 shot(COLLIDE,(.4)*k,.5,parent,{DistortionSoundEffect={Level=.7}})
end
CUES.Portal=function(parent,k)
 shot(TICK,(.4)*k,.12,parent,{FlangeSoundEffect={Depth=1,Mix=1,Rate=1.5},ReverbSoundEffect={DecayTime=5,WetLevel=0}},.5,2.5)
 shot(WIND,(.35)*k,.3,parent,{FlangeSoundEffect={Depth=1,Mix=.8,Rate=.8}})
end
-- The dog jumps back into the inventory.
CUES.Pop=function(parent,k)
 shot(PING,(.2)*k,1.5,parent,CHIME)
 later(.06,function()shot(TICK,(.16)*k,2.2,parent,CHIME)end)
end
CUES.Boom=function(parent,k)
 shot(LAND,(1)*k,.25,parent,STING)
 shot(COLLIDE,(.6)*k,.3,parent,{DistortionSoundEffect={Level=.8},EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-20}})
 shot(WIND,(.6)*k,.4,parent,THUNK)
end

-- Loops: Audio.Loop(name, parent?, volume?) -> {Stop=function(fade?)}. The nuclear alarm is a
-- distorted two-tone klaxon whose pitch sweeps up and down like an air-raid siren.
local LOOPS={
 Siren={{Id=PING,Volume=.32,Speed=.5,To=.82,Period=1.1,Effects={DistortionSoundEffect={Level=.55},ReverbSoundEffect={DecayTime=2.2,WetLevel=-4},EqualizerSoundEffect={LowGain=2,MidGain=4,HighGain=-6}}},
  {Id=TICK,Volume=.2,Speed=.3,To=.46,Period=1.1,Effects={DistortionSoundEffect={Level=.7},FlangeSoundEffect={Depth=.5,Mix=.6,Rate=6}}}},
 Rumble={{Id=WIND,Volume=.45,Speed=.35,To=.42,Period=2.4,Effects={EqualizerSoundEffect={LowGain=10,MidGain=-6,HighGain=-30}}}},
 VoidHum={{Id=TICK,Volume=.35,Speed=.12,To=.16,Period=3,Effects={FlangeSoundEffect={Depth=1,Mix=1,Rate=.6},ReverbSoundEffect={DecayTime=6,WetLevel=0}}},
  {Id=WIND,Volume=.25,Speed=.25,To=.3,Period=4,Effects={EqualizerSoundEffect={LowGain=8,MidGain=-8,HighGain=-30}}}},
}
function Audio.Loop(name,parent,volume)
 local spec=LOOPS[name];local sounds={};local tweens={}
 local k=math.clamp(tonumber(volume)or 1,0,1)
 if spec then
  local group=SoundService:FindFirstChild('DOGROTS_AUDIO');local sfx=group and group:FindFirstChild('SFX')
  for _,layer in ipairs(spec)do
   local s=Instance.new('Sound');s.Name='LabLoop';s.SoundId=layer.Id;s.Looped=true;s.Volume=0;s.PlaybackSpeed=layer.Speed
   s.RollOffMinDistance=20;s.RollOffMaxDistance=260
   for class,props in pairs(layer.Effects or{})do local e=Instance.new(class);for key,v in pairs(props)do(e::any)[key]=v end;e.Parent=s end
   if sfx and sfx:IsA('SoundGroup')then s.SoundGroup=sfx end
   s.Parent=parent or SoundService;s:Play()
   local fade=TweenService:Create(s,TweenInfo.new(.4),{Volume=layer.Volume*k});fade:Play()
   local sweep=TweenService:Create(s,TweenInfo.new(layer.Period/2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{PlaybackSpeed=layer.To});sweep:Play()
   table.insert(sounds,s);table.insert(tweens,sweep)
  end
 end
 local handle={Sounds=sounds}
 function handle.Stop(fade,pitchDown)
  for _,t in ipairs(tweens)do t:Cancel()end
  for _,s in ipairs(sounds)do
   if s.Parent then
    local goal={Volume=0};if pitchDown then goal.PlaybackSpeed=s.PlaybackSpeed*.35 end
    local t=TweenService:Create(s,TweenInfo.new(fade or .3),goal);t:Play()
    Debris:AddItem(s,(fade or .3)+.1)
   end
  end
  table.clear(sounds)
 end
 return handle
end

local throttle={Select=.05,Step=.08,Deny=.15,Scan=.3,Tick=.04,Arc=.12,Key=.03,Splat=.05,Crack=.08}
local lastPlayed={}
-- volume: optional multiplier (the presentation lowers the lab during world events); pitch: Tick only.
function Audio.Play(cue,parent,volume,pitch)
 local now=os.clock()
 if throttle[cue]and now-(lastPlayed[cue]or 0)<throttle[cue]then return end
 lastPlayed[cue]=now
 local k=math.clamp(tonumber(volume)or 1,0,1)
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot('rbxassetid://'..string.format('%.0f',asset),.5*k,1,parent);return end
 local fn=CUES[cue]
 if fn then
  local ok,err=pcall(fn,parent,k,tonumber(pitch))
  if not ok then warn('Lab audio '..tostring(cue)..': '..tostring(err))end
 end
end
function Audio.Has(cue)return CUES[cue]~=nil end

return Audio
