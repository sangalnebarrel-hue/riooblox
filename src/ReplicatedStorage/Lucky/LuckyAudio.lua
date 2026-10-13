-- Lucky Block sound cues (client). The place ships no uploaded lucky SFX (RewardAudio's lucky/*
-- keys and WorldSoundConfig are empty), so every cue is built from sounds bundled with every
-- Roblox client, re-pitched and filtered like SecretArrivals.Kit and Mining/MiningAudio.
-- Upload real SFX later by setting AssetIds (0 = built-in recipe).
local SoundService=game:GetService('SoundService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Audio={}

Audio.AssetIds={Charge=0,Shake=0,Crack=0,Burst=0,Whoosh=0,Tick=0,Land=0,Reveal=0,Arrive=0,Void=0,Buy=0}

local TICK='rbxasset://sounds/volume_slider.ogg'
local COLLIDE='rbxasset://sounds/collide.wav'
local PING='rbxasset://sounds/electronicpingshort.wav'
local SLASH='rbxasset://sounds/swordslash.wav'
local LAND='rbxasset://sounds/action_jump_land.mp3'

local active=0
local function shot(id,volume,speed,parent,effects,speedTo,rampTime)
 if active>=16 then return nil end
 local s=Instance.new('Sound');s.Name='LuckyCue';s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed or 1
 s.RollOffMinDistance=10;s.RollOffMaxDistance=140
 for class,props in pairs(effects or{})do
  local e=Instance.new(class);for k,v in pairs(props)do(e::any)[k]=v end;e.Parent=s
 end
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
local IMPACT={EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-30},DistortionSoundEffect={Level=.55},
 ReverbSoundEffect={DecayTime=2.4,WetLevel=-2,DryLevel=0,Density=1,Diffusion=1}}
local STING={ReverbSoundEffect={DecayTime=6,WetLevel=0,DryLevel=-6,Density=1,Diffusion=1},EqualizerSoundEffect={LowGain=8,MidGain=-2,HighGain=-18}}
local WHOOSH={EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=2},FlangeSoundEffect={Depth=.6,Mix=.85,Rate=6},ReverbSoundEffect={DecayTime=1.4,WetLevel=-6}}

local CUES={}
-- The block powering up: a rising, flanged tone with a low heartbeat under it.
CUES.Charge=function(parent,rank,seconds)
 seconds=seconds or 1.1
 shot(TICK,.32,.28,parent,{FlangeSoundEffect={Depth=.5,Mix=.7,Rate=3},ReverbSoundEffect={DecayTime=1.6,WetLevel=-5}},1.15+(rank or 1)*.05,seconds)
 local beats=math.max(2,math.floor(seconds/.28))
 for i=0,beats-1 do later(i*seconds/beats,function()shot(TICK,.22+i*.04,.2+i*.012,parent,{EqualizerSoundEffect={LowGain=10,MidGain=-8,HighGain=-40}})end)end
end
CUES.Shake=function(parent,amount)shot(COLLIDE,.12+(amount or .5)*.2,.55+math.random()*.15,parent)end
CUES.Crack=function(parent)
 shot(COLLIDE,.3,1.5,parent,{DistortionSoundEffect={Level=.4}})
 shot(TICK,.14,2.2,parent)
end
-- The block bursting open. Heavier tiers boom lower and ring longer.
CUES.Burst=function(parent,rank)
 rank=rank or 1
 shot(LAND,.55,.8-rank*.04,parent)
 shot(TICK,.42,.18-rank*.01,parent,IMPACT)
 shot(SLASH,.2,.9-rank*.05,parent,WHOOSH)
 if rank>=4 then later(.05,function()shot(PING,.2,.7,parent,CHIME)end)end
 if rank>=5 then shot(TICK,.7,.14,parent,STING)end
 if rank>=6 then for i=0,6 do later(i*.05,function()shot(TICK,.25,1.6+math.random()*2.6,parent,{DistortionSoundEffect={Level=.8}})end)end end
end
CUES.Whoosh=function(parent,speed)shot(TICK,.3,(speed or 1)*.45,parent,WHOOSH)end
-- One roulette card passing the marker; pitch rises as the strip slows down.
CUES.Tick=function(parent,pitch)shot(TICK,.12,pitch or 1.3,parent)end
-- The roulette stopping on the winner: a longer arpeggio for rarer dogs.
CUES.Land=function(parent,rank)
 rank=rank or 1
 local steps=({{1,1.5},{1,1.25,1.5},{1,1.25,1.5,2},{1,1.25,1.5,2,2.5},{1,1.2,1.5,1.8,2.25,3},{1,1.12,1.33,1.5,2,2.67,3}})[math.clamp(rank,1,6)]
 for i,step in ipairs(steps)do later((i-1)*.1,function()shot(TICK,.2,step*1.5,parent,CHIME)end)end
 if rank>=3 then shot(PING,.18,1+rank*.05,parent,CHIME)end
 if rank>=5 then shot(TICK,.6,.15,parent,STING);shot(LAND,.4,.6,parent)end
end
CUES.Reveal=function(parent,rank)
 shot(PING,.22,.9+(rank or 1)*.06,parent,CHIME)
 if (rank or 1)>=4 then later(.12,function()shot(PING,.18,1.4,parent,CHIME)end)end
end
-- A block leaving THE DOG's mouth onto the tongue.
CUES.Arrive=function(parent,rank)
 rank=rank or 1
 shot(TICK,.25+rank*.05,.4,parent,WHOOSH)
 later(.15,function()shot(PING,.12+rank*.03,.8+rank*.08,parent,CHIME)end)
 if rank>=4 then later(.1,function()shot(TICK,.4,.16,parent,IMPACT)end)end
 if rank>=5 then later(.2,function()shot(TICK,.6,.15,parent,STING)end)end
end
-- The Secret block's void: a deep drone with glitches on top.
CUES.Void=function(parent)
 shot(TICK,.7,.1,parent,STING)
 shot(TICK,.35,.22,parent,{FlangeSoundEffect={Depth=1,Mix=1,Rate=.6},ReverbSoundEffect={DecayTime=5,WetLevel=0}},.12,2)
 for i=0,5 do later(.3+i*.07,function()shot(TICK,.18,2+math.random()*2.5,parent,{DistortionSoundEffect={Level=.8}})end)end
end
CUES.Buy=function(parent)
 for i,step in ipairs({1,1.25,1.5,2})do later((i-1)*.09,function()shot(TICK,.16,step*1.5,parent,CHIME)end)end
end

local throttle={Tick=.035,Shake=.08,Crack=.12}
local last={}
function Audio.Play(cue,parent,...)
 local now=os.clock()
 if throttle[cue]and now-(last[cue]or 0)<throttle[cue]then return end
 last[cue]=now
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot('rbxassetid://'..string.format('%.0f',asset),.5,1,parent);return end
 local fn=CUES[cue];if fn then fn(parent,...)end
end

return Audio
