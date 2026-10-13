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
local WATER='rbxasset://sounds/impact_water.mp3'
local FALL='rbxasset://sounds/action_falling.mp3'
-- Classic sounds bundled with the client; every identity also layers one of the cues above, so a
-- pickaxe never goes silent if a bundled file is missing on some platform.
local CLICK='rbxasset://sounds/clickfast.wav'
local SPLAT='rbxasset://sounds/splat.wav'
local JUMP='rbxasset://sounds/action_jump.mp3'
local UNSHEATH='rbxasset://sounds/unsheath.wav'
local LUNGE='rbxasset://sounds/swordlunge.wav'

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

local CHORUS={ChorusSoundEffect={Depth=.3,Mix=.6,Rate=4},ReverbSoundEffect={DecayTime=1.4,WetLevel=-6}}
local DIST={DistortionSoundEffect={Level=.6},EqualizerSoundEffect={LowGain=-4,MidGain=4,HighGain=0}}
local TREM={TremoloSoundEffect={Depth=1,Duty=.5,Frequency=22}}
local WET={EqualizerSoundEffect={LowGain=6,MidGain=-2,HighGain=-14},ReverbSoundEffect={DecayTime=.9,WetLevel=-8}}
local DOOM={EqualizerSoundEffect={LowGain=10,MidGain=-6,HighGain=-30},ReverbSoundEffect={DecayTime=3,WetLevel=-2}}
local SHINE={ReverbSoundEffect={DecayTime=2.2,WetLevel=-3},EqualizerSoundEffect={LowGain=-10,MidGain=0,HighGain=4}}
-- Sound identity of every pickaxe (Config.Mining.Pickaxes[i].Sound): {id, volume, pitch, effects, delay}.
local SOUNDS={
 Wood={{COLLIDE,.26,1.4},{TICK,.08,.6,{EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-12}}}},
 Fairy={{PING,.14,2.3,CHORUS},{PING,.1,2.9,CHORUS,.06},{COLLIDE,.12,1.9}},
 Plastic={{CLICK,.32,1.5},{COLLIDE,.16,2.4},{TICK,.1,1.6,nil,.04}},
 Digital={{PING,.18,1.55,DIST},{PING,.18,1.2,DIST,.09},{COLLIDE,.12,1.3}},
 Squish={{SPLAT,.3,1.6},{JUMP,.14,1.9},{COLLIDE,.12,1.6}},
 Slime={{SPLAT,.34,.75,WET},{WATER,.24,.9,WET},{TICK,.08,.4}},
 Alarm={{PING,.13,3.1,TREM},{PING,.11,3.1,TREM,.07},{PING,.09,3.1,TREM,.14},{COLLIDE,.14,1.3}},
 Magic={{PING,.16,1.8,CHORUS},{PING,.13,2.4,CHORUS,.07},{PING,.1,3.0,CHORUS,.14},{COLLIDE,.12,1.5}},
 Electric={{TICK,.26,3.6,DIST},{COLLIDE,.24,.95},{TICK,.18,4.2,DIST,.05}},
 Clown={{PING,.14,1.1,TREM},{TICK,.14,2.6,nil,.08},{TICK,.14,2.6,nil,.16},{COLLIDE,.16,1.2}},
 Wet={{WATER,.3,1.25,WET},{SPLAT,.2,.9},{COLLIDE,.1,1.1}},
 Doom={{FALL,.18,.35,DOOM},{COLLIDE,.3,.6},{TICK,.2,.2,IMPACT}},
 Saw={{SLASH,.22,1.45,DIST},{TICK,.15,5,DIST},{COLLIDE,.16,1.4}},
 Shing={{UNSHEATH,.28,1.35,SHINE},{SLASH,.24,1.8,SHINE,.02},{COLLIDE,.12,1.7}},
 Metal={{LUNGE,.22,1.9},{SLASH,.2,2.1,nil,.03},{COLLIDE,.24,1.6}},
 Glitch={{PING,.16,.62,DIST},{TICK,.2,6,DIST,.03},{PING,.12,1.9,DIST,.06},{COLLIDE,.14,1.2}},
}
local function play(list,parent,pitch,volume)
 for _,row in ipairs(list)do
  local function go()shot(row[1],row[2]*(volume or 1),jitter(row[3]*(pitch or 1)),parent,row[4])end
  if row[5]and row[5]>0 then later(row[5],go)else go()end
 end
end

local CUES={}
-- tier = pickaxe FX tier (1..7): heavier pickaxes sound lower and fuller; sound = the pickaxe's
-- identity (SOUNDS), when given.
CUES.Hit=function(parent,tier,sound)
 tier=tier or 1
 if sound and SOUNDS[sound]then play(SOUNDS[sound],parent,1,1);return end
 shot(COLLIDE,.26,jitter(1.45-tier*.06),parent)
 shot(TICK,.08,jitter(.62-tier*.03),parent,{EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-12}})
end
CUES.Perfect=function(parent,tier,sound)
 CUES.Hit(parent,tier,sound)
 shot(PING,.2,1.3+(tier or 1)*.02,parent)
end
CUES.Crit=function(parent,tier,sound)
 shot(TICK,.42,.14,parent,IMPACT)
 if sound and SOUNDS[sound]then play(SOUNDS[sound],parent,.8,1.35)
 else
  shot(COLLIDE,.34,.9,parent)
  if (tier or 1)>=6 then shot(SLASH,.18,.7,parent)end
 end
end
-- Combo milestone (x10, x25, x50, x100...): a rising fanfare.
CUES.Milestone=function(parent)
 for i,step in ipairs({1,1.25,1.5,2,2.5})do later((i-1)*.07,function()shot(PING,.16,step*1.1,parent,CHIME)end)end
 shot(TICK,.3,.2,parent,IMPACT)
end
-- Equipping / drawing the pickaxe.
CUES.Draw=function(parent)
 shot(UNSHEATH,.2,1.1,parent);shot(TICK,.1,1.3,parent)
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

local throttle={Hit=.04,Perfect=.04,Crit=.05,Miss=.08,Lift=.05,Click=.05,Milestone=.4}
function Audio.Play(cue,parent,...)
 local now=os.clock()
 if throttle[cue]and now-(lastPlayed[cue]or 0)<throttle[cue]then return end
 lastPlayed[cue]=now
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot('rbxassetid://'..string.format('%.0f',asset),.5,1,parent);return end
 local fn=CUES[cue];if fn then fn(parent,...)end
end

return Audio
