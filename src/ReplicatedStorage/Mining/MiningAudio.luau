-- Active Mining sound cues (client). The game ships no uploaded SFX, so every cue is built from
-- sounds bundled with every Roblox client, re-pitched and filtered the same way
-- SecretArrivals.Kit does. Upload real SFX later by setting AssetIds below (0 = use built-ins).
local SoundService=game:GetService('SoundService')
local Debris=game:GetService('Debris')
local Audio={}

-- Optional uploaded sounds (rbxassetid numbers). When set, the cue plays this asset instead.
Audio.AssetIds={Hit=0,Perfect=0,Crit=0,Break=0,RareBreak=0,Coin=0,Buy=0,Deny=0,Lift=0,LiftTop=0,Strength=0,Miss=0,Click=0,Whoosh=0}

local TICK='rbxasset://sounds/volume_slider.ogg'
local COLLIDE='rbxasset://sounds/collide.wav'
local PING='rbxasset://sounds/electronicpingshort.wav'
local SLASH='rbxasset://sounds/swordslash.wav'
local LAND='rbxasset://sounds/action_jump_land.mp3'

local lastPlayed={}
local active=0
local function shot(id,volume,speed,parent,effects)
 if active>=14 then return nil end
 local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed or 1
 s.RollOffMinDistance=8;s.RollOffMaxDistance=80
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
 Debris:AddItem(s,6)
 return s
end
local function later(delay,fn)task.delay(delay,fn)end
local function jitter(x,amount)return x*(1+(math.random()*2-1)*(amount or .04))end

local IMPACT={EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-30},DistortionSoundEffect={Level=.55},
 ReverbSoundEffect={DecayTime=1.6,WetLevel=-6,DryLevel=0,Density=1,Diffusion=1}}
local CHIME={ReverbSoundEffect={DecayTime=1.8,WetLevel=-4}}

local CUES={}
-- tier = pickaxe FX tier (1..7): heavier pickaxes sound lower and fuller.
CUES.Hit=function(parent,tier)
 tier=tier or 1
 shot(COLLIDE,.26,jitter(1.45-tier*.06),parent)
 shot(TICK,.08,jitter(.62-tier*.03),parent,{EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-12}})
end
CUES.Perfect=function(parent,tier)
 CUES.Hit(parent,tier)
 shot(PING,.22,1.3+(tier or 1)*.02,parent)
end
CUES.Crit=function(parent,tier)
 shot(TICK,.42,.14,parent,IMPACT)
 shot(COLLIDE,.34,.9,parent)
 if (tier or 1)>=6 then shot(SLASH,.18,.7,parent)end
end
CUES.Miss=function(parent)
 shot(TICK,.14,.5,parent,{EqualizerSoundEffect={LowGain=0,MidGain=0,HighGain=-18},DistortionSoundEffect={Level=.3}})
end
CUES.Break=function(parent)
 shot(COLLIDE,.48,.72,parent)
 shot(LAND,.42,.8,parent)
 shot(TICK,.3,.16,parent,IMPACT)
end
CUES.RareBreak=function(parent)
 CUES.Break(parent)
 for i,step in ipairs({1,1.25,1.5,2})do later((i-1)*.12,function()shot(TICK,.18,step*1.5,parent,CHIME)end)end
end
local coinAt=0
CUES.Coin=function(parent,combo)
 local now=os.clock();if now-coinAt<.07 then return end;coinAt=now
 shot(TICK,.11,1.8+math.min(.6,(combo or 0)*.06),parent)
end
CUES.Buy=function(parent)
 for i,step in ipairs({1,1.25,1.5,2})do later((i-1)*.1,function()shot(TICK,.18,step*1.5,parent,CHIME)end)end
end
CUES.Deny=function(parent)
 local fx={EqualizerSoundEffect={LowGain=0,MidGain=0,HighGain=-18},DistortionSoundEffect={Level=.3}}
 shot(TICK,.18,.5,parent,fx);later(.08,function()shot(TICK,.18,.42,parent,fx)end)
end
CUES.Whoosh=function(parent)
 shot(TICK,.32,.45,parent,{EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=2},FlangeSoundEffect={Depth=.6,Mix=.85,Rate=6},ReverbSoundEffect={DecayTime=1.4,WetLevel=-6}})
end
CUES.Lift=function(parent,progress)
 shot(TICK,.07,.35+(progress or 0)*.5,parent,{EqualizerSoundEffect={LowGain=8,MidGain=-4,HighGain=-20}})
end
CUES.LiftTop=function(parent)
 CUES.Whoosh(parent)
 later(.18,function()shot(LAND,.4,.7,parent)end)
end
CUES.Strength=function(parent)
 for i,step in ipairs({1,1.5})do later((i-1)*.11,function()shot(TICK,.16,step*1.5,parent,CHIME)end)end
end
CUES.Click=function(parent)shot(TICK,.1,1.2,parent)end

local throttle={Hit=.04,Perfect=.04,Crit=.05,Miss=.08,Lift=.05,Click=.05}
function Audio.Play(cue,parent,...)
 local now=os.clock()
 if throttle[cue]and now-(lastPlayed[cue]or 0)<throttle[cue]then return end
 lastPlayed[cue]=now
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot('rbxassetid://'..string.format('%.0f',asset),.5,1,parent);return end
 local fn=CUES[cue];if fn then fn(parent,...)end
end

return Audio
