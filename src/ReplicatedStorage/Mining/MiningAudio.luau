-- Active Mining sound cues (client). The game ships no uploaded SFX, so every cue is built from
-- sounds bundled with every Roblox client (rbxasset://sounds/...), re-pitched, sliced and filtered.
-- v4: every pickaxe has its own SOUND KIT (Config.Mining.Pickaxes[i].Sound = kit name):
--   Swing  the swish of the swing (in a session: on the click; outside: with the animation)
--   Hit    the strike landing on the ore          Perfect  Hit + the kit's gold-zone accent
--   Crit   the server's critical hit (complete on its own)
--   Draw   the pickaxe comes into the hand        Break    the kit's flavour on top of the rock break
--   Idle   (optional) a faint loop while the local player holds it (Saw, TV, Squish, Slime, Magic, Shing, Metal, Fairy, Plastic, Digital, Alarm, Electric, Clown, Wet, Doom)
--   Run    (optional) a loop under Idle that follows the holder's running speed (Shing, Metal, Fairy, Saw, Plastic, Digital, Slime, Alarm, Electric, Clown, Wet, Doom)
--   Inspect (optional) the inspect show (MiningClient.Tool; TV-Head, Gummy Horror, Ponycorn, Scythe, Twin Claws, Butterfly Catcher, Laughsaw, LEGO Hand, Pickaxe 67, Rotten Slime Slug, Toothy Alarm Clock, Zombie-Frankenstein, Clown Chronomord, Nasty Octopus, Hand of Fate)
-- API (backwards compatible):
--   Audio.Play(cue, parent?, ...)                generic cues (Break, RareBreak, Coin, Buy, Deny, Miss,
--                                               Milestone, Whoosh, Click, Holster, Lift, LiftTop, Strength)
--                                               Play('Hit'|'Perfect'|'Crit', parent, tier, soundName) = kit
--   Audio.Pickaxe(cue, def, parent?, opts?)      def = pickaxe def (or its Sound name); parent nil = 2D
--        opts: Remote (3D lite: 2 layers, quieter, own budget), Key (throttle key, e.g. the corner),
--              Volume (multiplier), Combo (perfect accent rises), Air (swing follows the animation)
--   Audio.StartIdle(def, parent) / Audio.StopIdle()
--   Audio.SetVolume(0..1) (the SoundService.DOGROTS_MiningSFX group), Audio.Stats() (live voices)
-- Upload real SFX later: Audio.AssetIds[cue] (generic) and Audio.KitAssetIds[kit][cue] (0 = recipe).
-- Every kit is plain data (Audio.Kits) and can be tuned live from the Studio command bar, e.g.
--   require(game.ReplicatedStorage.Mining.MiningAudio).Kits.Saw.Hit[1][2]=.4   (row = {id, volume, speed, fx})
-- A sound error never reaches the caller (mining, the shop and the hotbar keep working); the
-- first one is reported once with warn().
local SoundService=game:GetService('SoundService')
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local Audio={}

-- UPLOAD SLOTS -----------------------------------------------------------------------------------
Audio.AssetIds={Hit=0,Perfect=0,Crit=0,Break=0,RareBreak=0,Coin=0,Buy=0,Deny=0,Lift=0,LiftTop=0,Strength=0,Miss=0,Click=0,
 Whoosh=0,Draw=0,Holster=0,Milestone=0}
local KIT_CUES={'Swing','Hit','Perfect','Crit','Draw','Break','Inspect'}
local KIT_NAMES={'Wood','Fairy','Plastic','Digital','Squish','Slime','Alarm','Magic','Electric','Clown','Wet','Doom','Saw','Shing','Metal','Glitch'}
Audio.KitAssetIds={}
for _,kit in ipairs(KIT_NAMES)do local t={};for _,cue in ipairs(KIT_CUES)do t[cue]=0 end;Audio.KitAssetIds[kit]=t end
Audio.UploadVolume=.6 -- an uploaded sound plays at this volume (x the cue's multipliers)

-- BUILT-IN SOUNDS (all already used by this place; every client ships them) ----------------------
local TICK='rbxasset://sounds/volume_slider.ogg'       -- tiny UI tick: clicks, thumps (slow), buzz (looped)
local PING='rbxasset://sounds/electronicpingshort.wav' -- short sine ping: bells, beeps, chimes, horns
local KNOCK='rbxasset://sounds/collide.wav'            -- classic collision clunk: knocks, impacts
local LAND='rbxasset://sounds/action_jump_land.mp3'    -- soft landing thud: body, booms (slow)
local WIND='rbxasset://sounds/action_falling.mp3'      -- wind rush loop: whooshes (sliced), roars, static
local WATER='rbxasset://sounds/impact_water.mp3'       -- splash: slime, ink
local SPLAT='rbxasset://sounds/splat.wav'              -- splat: gummy, slime, meat
local CLICK='rbxasset://sounds/clickfast.wav'          -- mechanical click: LEGO, clock ticks
local SLASH='rbxasset://sounds/swordslash.wav'         -- sword swish
local LUNGE='rbxasset://sounds/swordlunge.wav'         -- sword lunge
local SHEATH='rbxasset://sounds/unsheath.wav'          -- metallic "shing"
local HOP='rbxasset://sounds/action_jump.mp3'          -- soft "hup": light swishes, boings
Audio.Sources={TICK,PING,KNOCK,LAND,WIND,WATER,SPLAT,CLICK,SLASH,LUNGE,SHEATH,HOP}

-- MIX --------------------------------------------------------------------------------------------
-- Every cue plays through one SoundGroup, SoundService.DOGROTS_MiningSFX (created here when missing),
-- with a soft compressor, so stacked hits never clip; its Volume is the one knob for all mining
-- sounds (the tail groups below sit inside it and follow it). It is deliberately NOT inside
-- SoundService.DOGROTS_AUDIO: the island's music ducks (a Secret arrival anywhere on the server,
-- Scope:Duck) move every SoundGroup there, which would drop hit feedback to 8% in the middle of a
-- session, and their baseline is captured once (one taken while a cinematic held the groups at 0
-- would keep mining silent until rejoin). The lab's Corrupted silence (all SoundGroups, restored
-- exactly) still covers it.
-- Reverb is never put on the voice: a Sound's effects stop with it, so a 4 s bell would end dead
-- the moment its short sample ends. A row whose preset has a ReverbSoundEffect plays into a child
-- "MiningTail" SoundGroup holding that one reverb (shared by every voice with the same settings,
-- also cheaper on phones than one reverb per voice); a group keeps ringing after its voices end.
local GROUP_NAME='DOGROTS_MiningSFX'
local group=nil
local tails={} -- reverb settings key -> child SoundGroup of the group
local function soundGroup()
 if group and group.Parent then return group end
 local g=SoundService:FindFirstChild(GROUP_NAME)
 if not(g and g:IsA('SoundGroup'))then
  g=Instance.new('SoundGroup');g.Name=GROUP_NAME;g.Volume=1
  local c=Instance.new('CompressorSoundEffect');c.Threshold=-14;c.Ratio=3;c.Attack=.004;c.Release=.12;c.GainMakeup=2;c.Parent=g
  g.Parent=SoundService
 end
 group=g;table.clear(tails)
 return g
end
local tailKeys=setmetatable({},{__mode='k'}) -- reverb settings table -> its key (presets are shared tables)
local function tailKey(props)
 local key=tailKeys[props]
 if key then return key end
 local names={};for k in pairs(props)do table.insert(names,k)end;table.sort(names)
 local parts={};for _,k in ipairs(names)do table.insert(parts,k..'='..tostring(props[k]))end
 key=table.concat(parts,',');tailKeys[props]=key
 return key
end
local function tailGroup(props)
 local g=soundGroup()
 local key=tailKey(props)
 local t=tails[key]
 if t and t.Parent==g then return t end
 t=nil
 for _,c in ipairs(g:GetChildren())do if c:IsA('SoundGroup')and c:GetAttribute('Reverb')==key then t=c;break end end
 if not t then
  t=Instance.new('SoundGroup');t.Name='MiningTail';t.Volume=1;t:SetAttribute('Reverb',key)
  local r=Instance.new('ReverbSoundEffect');for k,v in pairs(props)do(r::any)[k]=v end;r.Parent=t
  t.Parent=g
 end
 tails[key]=t
 return t
end
-- A voice's effects (its row's preset) and the group it plays into.
local function dress(s,fx)
 local into=nil
 for class,props in pairs(fx or{})do
  if class=='ReverbSoundEffect'then into=tailGroup(props)
  else local e=Instance.new(class);for key,v in pairs(props)do(e::any)[key]=v end;e.Parent=s end
 end
 s.SoundGroup=into or soundGroup()
end

local LOCAL_CAP,REMOTE_CAP=16,6 -- voices alive at once (the first layer of a cue may use 4 more)
local live={Local=0,Remote=0}
local function later(t,fn)if t and t>0 then task.delay(t,fn)else fn()end end
local function jitter(amount)return 1+(math.random()*2-1)*(amount or .035)end

-- One voice. row = {id, volume, speed, effects, at=, dur=, attack=, fade=, loop=, to=, ramp=, from=}
-- k = volume multiplier, p = pitch multiplier, where = parent (nil = 2D), lane = 'Local'|'Remote'.
local function shot(row,k,p,where,lane,first)
 local cap=lane=='Remote'and REMOTE_CAP or LOCAL_CAP
 if live[lane]>=cap+(first and 4 or 0)then return nil end
 if where and not where.Parent then return nil end -- the part went away (streamed out, rebuilt) meanwhile
 local s=Instance.new('Sound');s.Name='MiningCue';s.SoundId=row[1]
 local volume=math.clamp(row[2]*k,0,2)
 s.Volume=row.attack and 0 or volume
 s.PlaybackSpeed=math.clamp(row[3]*p,.05,8)
 s.Looped=row.loop==true
 if row.from then s.TimePosition=row.from end
 s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=10;s.RollOffMaxDistance=90
 dress(s,row[4])
 s.Parent=where or SoundService
 live[lane]+=1
 local done=false
 local function finish()if not done then done=true;live[lane]=math.max(0,live[lane]-1)end end
 s.Destroying:Once(finish)
 s.Ended:Once(function()finish();s:Destroy()end)
 -- Belt and braces: a voice whose part streamed out (no Ended, no Destroying) frees its slot too.
 task.delay((row.dur or 5)+1,finish)
 s:Play()
 if row.attack then TweenService:Create(s,TweenInfo.new(row.attack,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Volume=volume}):Play()end
 if row.to then
  TweenService:Create(s,TweenInfo.new(row.ramp or row.dur or .25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{PlaybackSpeed=math.clamp(row.to*p,.05,8)}):Play()
 end
 if row.dur then
  local fade=row.fade or .06
  task.delay(math.max(0,row.dur-fade),function()
   if not s.Parent then return end
   TweenService:Create(s,TweenInfo.new(fade,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Volume=0}):Play()
   task.delay(fade+.02,function()finish();s:Destroy()end)
  end)
  Debris:AddItem(s,row.dur+1)
 else
  Debris:AddItem(s,6)
 end
 return s
end
-- A list of rows; one pitch jitter for the whole cue (chords and two-tone horns stay in tune).
local function play(list,where,lane,k,p,maxLayers)
 local layers=0
 for i,row in ipairs(list)do
  if maxLayers and layers>=maxLayers then break end
  layers+=1
  later(row.at,function()shot(row,k,p,where,lane,i==1)end)
 end
end
-- Rising / falling note runs: arp(id, volume, base speed, {ratios}, gap, fx, start)
local function arp(id,vol,base,steps,gap,fx,start)
 local rows={}
 for i,r in ipairs(steps)do table.insert(rows,{id,vol,base*r,fx,at=(start or 0)+(i-1)*gap})end
 return rows
end
local function join(...)
 local out={}
 for _,list in ipairs({...})do for _,row in ipairs(list)do table.insert(out,row)end end
 return out
end
-- A whoosh: a short slice of the wind loop with an attack and a fade.
local function whoosh(speed,vol,dur,fx,at)
 return{WIND,vol,speed,fx,at=at,dur=dur,attack=math.min(.04,dur*.3),fade=dur*.6,loop=true}
end

-- EFFECT PRESETS (values inside the Roblox ranges) -----------------------------------------------
local WOODY={EqualizerSoundEffect={LowGain=4,MidGain=2,HighGain=-14}}
local BRIGHT={EqualizerSoundEffect={LowGain=-10,MidGain=0,HighGain=4}}
local THUMP={EqualizerSoundEffect={LowGain=10,MidGain=-2,HighGain=-30},DistortionSoundEffect={Level=.45}}
local IMPACT={EqualizerSoundEffect={LowGain=10,MidGain=0,HighGain=-30},DistortionSoundEffect={Level=.55},
 ReverbSoundEffect={DecayTime=1.6,WetLevel=-6,DryLevel=0,Density=1,Diffusion=1}}
local CHIME={ReverbSoundEffect={DecayTime=1.8,WetLevel=-4}}
local CHORUS={ChorusSoundEffect={Depth=.3,Mix=.6,Rate=4},ReverbSoundEffect={DecayTime=1.4,WetLevel=-6}}
local SPARKLE={ChorusSoundEffect={Depth=.35,Mix=.6,Rate=5},ReverbSoundEffect={DecayTime=2.2,WetLevel=-3},EqualizerSoundEffect={LowGain=-8,MidGain=0,HighGain=4}}
local AIRY={EqualizerSoundEffect={LowGain=-8,MidGain=2,HighGain=4},FlangeSoundEffect={Depth=.5,Mix=.6,Rate=3}}
local SQUARE={DistortionSoundEffect={Level=.55},EqualizerSoundEffect={LowGain=-4,MidGain=4,HighGain=0}}
local CRUNCH={DistortionSoundEffect={Level=.85},EqualizerSoundEffect={LowGain=2,MidGain=6,HighGain=-6}}
local WET={EqualizerSoundEffect={LowGain=6,MidGain=-2,HighGain=-14},ReverbSoundEffect={DecayTime=.9,WetLevel=-8}}
local GOO={EqualizerSoundEffect={LowGain=8,MidGain=-4,HighGain=-20},FlangeSoundEffect={Depth=.4,Mix=.5,Rate=2}}
local TREM={TremoloSoundEffect={Depth=1,Duty=.5,Frequency=20}}
local HONK={DistortionSoundEffect={Level=.5},EqualizerSoundEffect={LowGain=2,MidGain=6,HighGain=-6}}
local DOOM={EqualizerSoundEffect={LowGain=10,MidGain=-6,HighGain=-30},ReverbSoundEffect={DecayTime=3,WetLevel=-2}}
local TOLL={ReverbSoundEffect={DecayTime=4,WetLevel=-1,DryLevel=-2,Density=1,Diffusion=1},EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-10}}
local SAW={DistortionSoundEffect={Level=.8},EqualizerSoundEffect={LowGain=2,MidGain=6,HighGain=-4}}
local RING={ReverbSoundEffect={DecayTime=1.6,WetLevel=-4},EqualizerSoundEffect={LowGain=-8,MidGain=0,HighGain=4}}
local SHINE={ReverbSoundEffect={DecayTime=2.2,WetLevel=-3},EqualizerSoundEffect={LowGain=-10,MidGain=0,HighGain=4}}
local CRACKLE={DistortionSoundEffect={Level=.85},TremoloSoundEffect={Depth=1,Duty=.3,Frequency=17},EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=2}}
local STATIC={DistortionSoundEffect={Level=.9},EqualizerSoundEffect={LowGain=-20,MidGain=-6,HighGain=8}}
local PULSE={TremoloSoundEffect={Depth=.8,Duty=.5,Frequency=1.6},EqualizerSoundEffect={LowGain=4,MidGain=-2,HighGain=-12}}
local FLUTTER={TremoloSoundEffect={Depth=.9,Duty=.45,Frequency=17},EqualizerSoundEffect={LowGain=-14,MidGain=-2,HighGain=4}}
local JINGLE={TremoloSoundEffect={Depth=.7,Duty=.35,Frequency=7},ChorusSoundEffect={Depth=.3,Mix=.5,Rate=6},EqualizerSoundEffect={LowGain=-12,MidGain=0,HighGain=3}}

-- PICKAXE SOUND KITS -----------------------------------------------------------------------------
-- The first rows of every cue are its character (a remote player's hit plays only the first two).
local KITS={}
-- Wooden Pickaxe: a hollow wood knock, "tok-tok" on a perfect, a cracking plank on a crit.
KITS.Wood={
 Swing={{HOP,.22,1.3},whoosh(2.2,.22,.16,AIRY)},
 Hit={{KNOCK,.5,1.15,WOODY},{LAND,.32,1.4},{TICK,.16,.55,WOODY}},
 Perfect={{KNOCK,.3,1.6,WOODY,at=.05}},
 Crit={{LAND,.55,.7,THUMP},{KNOCK,.5,.9,WOODY},{CLICK,.35,.6,CRUNCH,at=.03}},
 Draw={{CLICK,.25,.8},{HOP,.18,1.1,nil,at=.04}},
 Break={{KNOCK,.4,.8,WOODY,at=.05}},
}
-- Butterfly Catcher ("Сачок Ловец Бабочек" concept sheet "ЗВУКИ"): the SWING an airy net swish with
-- a soft wing flutter, the HIT a light fairy "pyum" (a bright note gliding down over a soft knock, a
-- sparkle on top), a perfect a high chime, a crit a rising fairy arpeggio and a big "pyum", the DRAW a
-- flutter and a two-note chime, the INSPECT a cute chirping (three quick rising tweets) and a soft
-- chime run; IDLE a quiet flutter of wings, RUN light jingling steps that follow the speed.
KITS.Fairy={
 Swing={{HOP,.22,1.8,AIRY},whoosh(3,.16,.16,BRIGHT),{WIND,.06,2.4,FLUTTER,at=.02,dur=.2,attack=.03,fade=.12,loop=true}},
 Hit={{PING,.26,3.4,CHORUS,to=2,ramp=.16},{KNOCK,.12,2.2},{PING,.12,4.2,SPARKLE,at=.04},{WIND,.05,2.6,FLUTTER,at=.03,dur=.25,attack=.02,fade=.18,loop=true}},
 Perfect={{PING,.15,3.6,SPARKLE,at=.1}},
 Crit=join({{PING,.32,3.6,CHORUS,to=1.8,ramp=.24},{LAND,.26,1.2}},arp(PING,.14,1.6,{1,1.25,1.5,2,2.5},.05,SPARKLE,.08),
  {{WIND,.08,2.4,FLUTTER,at=.1,dur=.5,attack=.05,fade=.3,loop=true}}),
 Draw={{WIND,.07,2.6,FLUTTER,dur=.3,attack=.04,fade=.18,loop=true},{PING,.18,2,CHORUS,at=.06},{PING,.16,2.67,CHORUS,at=.13}},
 Break=arp(PING,.14,2.2,{1.5,1.25,1,1.5},.05,SPARKLE,.05),
 Inspect=join({{WIND,.06,2.4,FLUTTER,dur=2.2,attack=.4,fade=.5,loop=true}},
  {{PING,.12,4.4,nil,at=.35,to=5.6,ramp=.05,dur=.09,loop=true},{PING,.12,4.8,nil,at=.47,to=6.2,ramp=.05,dur=.09,loop=true},{PING,.12,4.4,nil,at=.62,to=5.8,ramp=.06,dur=.1,loop=true}},
  arp(PING,.08,1.6,{1,1.25,1.5,2,1.5,2,2.5},.16,SPARKLE,1.0),
  {{PING,.11,4.6,nil,at=1.9,to=5.8,ramp=.05,dur=.09,loop=true},{PING,.11,5,nil,at=2.0,to=6.4,ramp=.05,dur=.09,loop=true},{PING,.14,3,CHIME,at=2.3}}),
 Idle={{WIND,.008,2.2,FLUTTER,loop=true}}, -- a quiet flutter of wings while it is held (nil = off)
 Run={{PING,.03,3.4,JINGLE,loop=true}}, -- light jingling steps while the holder runs (volume follows the speed)
}
-- LEGO Hand ("LEGO-Рука" concept sheet "ЗВУКИ"): the SWING a light plastic swish with a rattle, the HIT
-- (УДАР) a plastic "tuk" and the click of parts (a hollow plastic knock, two snapping clicks, loose bricks
-- rattling), a perfect adds a bright snap, a crit a whole avalanche of bricks; the DRAW the hand snapping
-- onto the wrist (three ratchet clicks, timed to MiningClient.PickFX), the INSPECT (ОСМОТР) the
-- characteristic construction-set sound (eight ratchet clicks while the hand turns round, a rummage of
-- bricks, the finger's double clack and a sparkle); IDLE a light click and creak of plastic now and then,
-- RUN (БЕГ) a cheerful tapping of parts that follows the speed.
local PLASTIC={EqualizerSoundEffect={LowGain=-4,MidGain=5,HighGain=2}}
local CREAK={TremoloSoundEffect={Depth=1,Duty=.16,Frequency=.6},EqualizerSoundEffect={LowGain=-6,MidGain=2,HighGain=0}}
local RATTLE={TremoloSoundEffect={Depth=.8,Duty=.4,Frequency=9},EqualizerSoundEffect={LowGain=-8,MidGain=3,HighGain=2}}
KITS.Plastic={
 Swing={{HOP,.2,1.5},whoosh(2.4,.18,.14,AIRY),{CLICK,.12,1.6,nil,at=.02}},
 Hit=join({{KNOCK,.42,1.55,PLASTIC},{CLICK,.5,1.2},{CLICK,.34,1.75,nil,at=.03}},arp(CLICK,.14,2.2,{1,1.3,1.1},.03,nil,.06)),
 Perfect={{CLICK,.3,2.3,nil,at=.06},{PING,.07,3.2,BRIGHT,at=.07}},
 Crit=join({{KNOCK,.5,1.1,PLASTIC},{CLICK,.55,.9},{LAND,.3,1}},arp(CLICK,.26,1.3,{1,1.4,1.15,1.7,1.25,1.9,1.4},.035,nil,.04)),
 Draw={{CLICK,.32,1},{CLICK,.26,1.35,nil,at=.12},{CLICK,.24,1.7,nil,at=.24},{KNOCK,.14,2.2,PLASTIC,at=.3}},
 Break=arp(CLICK,.2,1.4,{1,1.3,1.1,1.6,1.25},.035,nil,.04),
 Inspect=join({{CLICK,.24,.9},{HOP,.1,1.3,nil,at=.1}},arp(CLICK,.26,1.25,{1,1.06,1,1.06,1,1.06,1,1.12},.2,PLASTIC,.5),
  arp(CLICK,.1,2.1,{1,1.2,1.1,1.3},.025,nil,1.05),
  {{CLICK,.36,.8,nil,at=2.12},{CLICK,.3,1.1,nil,at=2.3},{KNOCK,.2,1.8,PLASTIC,at=2.31},{PING,.08,3,SPARKLE,at=2.36}}),
 Idle={{CLICK,.03,.24,CREAK,loop=true}}, -- a light click / plastic creak now and then while it is held (nil = off)
 Run={{CLICK,.05,.85,RATTLE,loop=true}}, -- cheerful tapping of parts while the holder runs (volume follows the speed)
}
-- Pickaxe 67 ("КИРКА 67" concept sheet "ЗВУКИ"): the SWING a square-wave swish with a glitch stutter, the HIT
-- (УДАР) "a digital beep + a heavy hit" (the two square beeps "six-seven" over a heavy thump and knock), a
-- perfect adds a high third beep, the CRIT (КРИТ) "a loud glitch sound 67" (a stuttering square "six-seven",
-- a static tear, a bass drop and a 2.67x blip); the DRAW boots the digits (a click, a rising chirp, the
-- "six-seven" beeps and a static flick), the INSPECT (ОСМОТР) "a mechanical click, rotation" (a latch click,
-- the whoosh of the twirl with ratchet ticks, four heavy dial clicks timed to MiningClient.PickFX at 1.6 ..
-- 1.96 s, then the glitch "six-seven"); IDLE (IDLE) "a quiet electronic hum", RUN (БЕГ) "a light digital
-- trail" (fast bit blips that follow the speed).
local HUM={TremoloSoundEffect={Depth=.5,Duty=.5,Frequency=3.5},EqualizerSoundEffect={LowGain=6,MidGain=-4,HighGain=-24}}
local STUTTER={TremoloSoundEffect={Depth=1,Duty=.5,Frequency=26},DistortionSoundEffect={Level=.5},EqualizerSoundEffect={LowGain=-4,MidGain=4,HighGain=0}}
local BITS={TremoloSoundEffect={Depth=1,Duty=.3,Frequency=14},EqualizerSoundEffect={LowGain=-14,MidGain=2,HighGain=2}}
KITS.Digital={
 Swing={whoosh(2.6,.2,.13,SQUARE),{TICK,.1,3},{PING,.05,3,STUTTER,at=.03,dur=.08,loop=true}},
 Hit={{PING,.24,1.5,SQUARE},{LAND,.36,.8,THUMP},{PING,.24,1.68,SQUARE,at=.08},{KNOCK,.3,1.05},{TICK,.14,.3,THUMP,at=.01}},
 Perfect={{PING,.18,2,SQUARE,at=.16}},
 Crit={{PING,.34,1,STUTTER,dur=.16,loop=true},whoosh(4,.3,.3,STATIC),{PING,.34,1.12,STUTTER,at=.17,dur=.18,loop=true},
  {LAND,.5,.6,THUMP},{TICK,.45,.18,THUMP,at=.18},{PING,.2,2.67,SQUARE,at=.36,dur=.12}},
 Draw={{CLICK,.24,.9},{PING,.1,1,SQUARE,at=.03,dur=.12,to=2.4,ramp=.12},{PING,.15,1.5,SQUARE,at=.16},{PING,.15,1.68,SQUARE,at=.24},whoosh(4,.1,.12,STATIC,.3)},
 Break=arp(PING,.18,2,{1.12,1,.84},.06,SQUARE),
 Inspect=join({{CLICK,.3,.75},{CLICK,.2,1.1,nil,at=.08},whoosh(1.4,.12,.4,AIRY,.55),whoosh(1.7,.12,.4,AIRY,.95)},
  arp(TICK,.1,2.4,{1,1.1,1,1.1,1,1.1},.13,nil,.6),
  {{CLICK,.38,.6,nil,at=1.6},{KNOCK,.16,1.6,nil,at=1.6},{CLICK,.38,.65,nil,at=1.72},{CLICK,.38,.6,nil,at=1.84},{CLICK,.42,.55,nil,at=1.96},{KNOCK,.2,1.3,nil,at=1.97},
   whoosh(4,.16,.18,STATIC,2.03),{PING,.24,1.5,STUTTER,at=2.05,dur=.12,loop=true},{PING,.24,1.68,STUTTER,at=2.19,dur=.14,loop=true}}),
 Idle={{TICK,.012,.42,HUM,loop=true},{PING,.006,.5,HUM,loop=true}}, -- a quiet electronic hum while it is held (nil = off)
 Run={{PING,.03,2.4,BITS,loop=true}}, -- a light digital trail while the holder runs (volume follows the speed)
}
-- Gummy Horror ("Кирка Мармеладный ужас"): a living marmalade monster. The swing is a gooey swish
-- with a wet flick, the hit a sticky squelch + a rubbery boing (the springy rebound) + a caramel
-- splash, a crit a big splat and a stretching boing that snaps, the draw a wet squish and a chomp of
-- candy teeth, the inspect chomps three times, stretches with a rising boing and giggles in falling
-- gooey blips; while it is held a faint wet bubbling.
KITS.Squish={
 Swing={{HOP,.22,2},whoosh(1.8,.16,.16,GOO),{SPLAT,.08,2.6,nil,at=.05}},
 Hit={{SPLAT,.48,1.45,WET},{HOP,.22,2.3,nil,at=.02,to=2.9,ramp=.12},{WATER,.18,1.7,WET,at=.03},{KNOCK,.14,1.6,GOO}},
 Perfect={{HOP,.2,3,nil,at=.06},{PING,.1,2.4,CHORUS,at=.08}},
 Crit={{SPLAT,.6,1,GOO},{HOP,.35,1.3,nil,to=2.6,ramp=.25},{WATER,.35,1.2,WET,at=.04},{SPLAT,.3,1.9,nil,at=.08},{PING,.12,1.8,GOO,at=.12,to=3,ramp=.2}},
 Draw={{SPLAT,.24,1.9,GOO},{HOP,.16,2.4,nil,at=.04,to=3.2,ramp=.18},{CLICK,.18,.8,nil,at=.14},{KNOCK,.1,2.2,nil,at=.15}},
 Break={{SPLAT,.42,.95,GOO},{WATER,.3,1.3,WET,at=.05},{SPLAT,.3,1.5,nil,at=.08}},
 Inspect=join({{SPLAT,.3,1.2,GOO},{HOP,.2,1.4,nil,at=.1,to=2.8,ramp=.4}},
  {{CLICK,.26,.8,nil,at=.62},{SPLAT,.14,2,nil,at=.64},{CLICK,.26,.85,nil,at=.94},{SPLAT,.14,2.1,nil,at=.96},{CLICK,.28,.75,nil,at=1.26},{SPLAT,.16,1.9,nil,at=1.28}},
  arp(PING,.1,1.4,{1.5,1.3,1.1,.9},.11,GOO,1.6),
  {{SPLAT,.26,1.3,WET,at=2.3}}),
 Idle={{WATER,.012,.45,GOO,loop=true}}, -- a faint wet bubbling while it is held (nil = off)
}
-- Rotten Slime Slug ("Кирка Слизень-Гнилушка" concept sheet "VFX / SFX"): the SWING a heavy wet swish with
-- a sticky stretch, the HIT the sheet's "Чавк / Слизкий звук" (a fat squelch, a wet splash, a dull rotten
-- thump and a gooey "splurp" gliding down), a perfect adds a sticky "shlorp" pulling off the ore, the CRIT a
-- huge SPLURP (low splat, splash, thump) with three little eye "pops" springing back on their threads; the
-- DRAW a wet squish and a bubbling gurgle, the BREAK a rotten splat, the INSPECT a gurgle as it comes up,
-- the big eye's nervous twitch (quick wet clicks), three slime pulses and a slurp at the end (timed to
-- MiningClient.Anim INSPECTS.Slurp / PickFX); IDLE a faint wet bubbling, RUN squelchy steps that follow
-- the speed.
local SQUELCH={EqualizerSoundEffect={LowGain=8,MidGain=-2,HighGain=-16},TremoloSoundEffect={Depth=.6,Duty=.4,Frequency=5}}
KITS.Slime={
 Swing={whoosh(1.3,.2,.2,WET),{SPLAT,.12,.6,GOO},{HOP,.08,.7,GOO,at=.04,to=.5,ramp=.15}},
 Hit={{SPLAT,.5,.72,WET},{WATER,.32,.85,WET,at=.01},{TICK,.16,.32,THUMP},{PING,.1,.75,GOO,at=.03,to=.38,ramp=.16,dur=.2,loop=true}},
 Perfect={{SPLAT,.26,.55,GOO,at=.08,to=.4,ramp=.2},{HOP,.14,.9,GOO,at=.1,to=1.6,ramp=.12}},
 Crit=join({{SPLAT,.62,.48,WET},{WATER,.48,.6,WET},{LAND,.42,.6,THUMP},{PING,.2,.5,GOO,at=.1,to=1.2,ramp=.15}},
  {{HOP,.16,2.6,nil,at=.16},{HOP,.15,2.9,nil,at=.22},{HOP,.14,2.4,nil,at=.28},{PING,.08,1.1,GOO,at=.36,to=.6,ramp=.2}}),
 Draw={{SPLAT,.26,.9,WET},{WATER,.1,.6,GOO,at=.06,dur=.4,fade=.2,loop=true},{PING,.1,.7,GOO,at=.1,to=.45,ramp=.2}},
 Break={{WATER,.45,.7,WET},{SPLAT,.38,.58,nil,at=.05},{LAND,.24,.7,THUMP,at=.02}},
 Inspect=join({{WATER,.14,.55,GOO,dur=.5,fade=.25,loop=true},{SPLAT,.22,.8,WET,at=.05}},
  arp(CLICK,.16,.55,{1,1.2,.9,1.3,1,1.25},.13,GOO,.55),
  {{SPLAT,.18,.7,GOO,at=1.25},{SPLAT,.2,.62,GOO,at=1.5},{SPLAT,.22,.55,GOO,at=1.75}},
  {{HOP,.14,.6,GOO,at=1.85,to=.4,ramp=.3},{SPLAT,.3,.5,WET,at=2.3},{PING,.08,.9,GOO,at=2.32,to=.45,ramp=.2}}),
 Idle={{WATER,.012,.4,GOO,loop=true}}, -- a faint wet bubbling while it is held (nil = off)
 Run={{SPLAT,.04,.75,SQUELCH,loop=true}}, -- squelchy steps while the holder runs (volume follows the speed)
}
-- Toothy Alarm Clock ("Зубастый Будильник" concept sheet "ЗВУКИ"): the SWING a tick-tock and a heavy swish, the HIT
-- "a loud ring + the alarm clock's scream" (two clanging bell tones through a fast tremolo, a metal clunk and a
-- short hoarse shriek gliding up), a perfect a higher bell, the CRIT "a very loud ring and a scream" (a long
-- two-tone ring, a thump and a long shriek rising and falling); the DRAW winds the key (ratchet clicks) and gives
-- one short ring, the BREAK a ring and a clunk, the INSPECT "a mechanical whirr" (the key winds: a buzzing whirr
-- under ratchet clicks while it turns round) and then it RINGS and screams (timed to MiningClient.Anim
-- INSPECTS.Alarm / PickFX); IDLE "a quiet ticking, the creak of the mechanism", RUN "ticking that speeds up" (a
-- tick loop whose volume and speed follow the holder's speed).
local BELL={TremoloSoundEffect={Depth=1,Duty=.5,Frequency=19},ReverbSoundEffect={DecayTime=1.2,WetLevel=-6},EqualizerSoundEffect={LowGain=-8,MidGain=2,HighGain=3}}
local SCREAM={DistortionSoundEffect={Level=.75},EqualizerSoundEffect={LowGain=-4,MidGain=8,HighGain=-6},TremoloSoundEffect={Depth=.6,Duty=.5,Frequency=16}}
local WHIRR={TremoloSoundEffect={Depth=.7,Duty=.5,Frequency=18},DistortionSoundEffect={Level=.4},EqualizerSoundEffect={LowGain=2,MidGain=4,HighGain=-12}}
local TICKTOCK={TremoloSoundEffect={Depth=1,Duty=.12,Frequency=2},EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=0}}
local TICKFAST={TremoloSoundEffect={Depth=1,Duty=.14,Frequency=5},EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=0}}
KITS.Alarm={
 Swing={{CLICK,.2,1.6},{CLICK,.18,1.2,nil,at=.07},whoosh(1.6,.22,.2)},
 Hit={{PING,.26,3,BELL,dur=.32,fade=.1,loop=true},{KNOCK,.4,1.1},{PING,.18,3.36,BELL,at=.02,dur=.28,fade=.1,loop=true},
  {PING,.13,1.7,SCREAM,at=.03,dur=.22,fade=.08,loop=true,to=2.3,ramp=.18},{CLICK,.2,.7,nil,at=.01}},
 Perfect={{PING,.18,4,BELL,at=.1,dur=.25,fade=.08,loop=true}},
 Crit=join({{PING,.34,3,BELL,dur=.8,fade=.25,loop=true},{PING,.26,3.36,BELL,dur=.8,fade=.25,loop=true},{LAND,.45,.7,THUMP},{KNOCK,.42,.9}},
  {{PING,.22,1.5,SCREAM,at=.05,dur=.32,loop=true,to=2.6,ramp=.3},{PING,.2,2.6,SCREAM,at=.37,dur=.3,fade=.15,loop=true,to=1.6,ramp=.3}}),
 Draw=join(arp(CLICK,.2,1.1,{1,1.15,1,1.15},.07),{{PING,.16,3,BELL,at=.3,dur=.25,fade=.1,loop=true}}),
 Break={{PING,.28,2.6,BELL,dur=.45,fade=.15,loop=true},{KNOCK,.3,.9}},
 Inspect=join({{TICK,.07,1.4,WHIRR,at=.4,dur=1.15,attack=.2,fade=.2,loop=true,to=2.2,ramp=1.1}},
  arp(CLICK,.16,.9,{1,1.1,1,1.1,1,1.1,1,1.1},.13,nil,.42),
  {{PING,.28,3,BELL,at=1.6,dur=.75,fade=.2,loop=true},{PING,.22,3.36,BELL,at=1.6,dur=.75,fade=.2,loop=true},
   {PING,.14,1.6,SCREAM,at=1.65,dur=.55,fade=.15,loop=true,to=2.5,ramp=.4},{KNOCK,.24,1.2,nil,at=2.36}}),
 Idle={{CLICK,.03,.45,TICKTOCK,loop=true},{TICK,.004,.3,CREAK,loop=true}}, -- a quiet tick-tock and a creak while it is held (nil = off)
 Run={{CLICK,.05,1,TICKFAST,loop=true}}, -- ticking that speeds up while the holder runs (volume and speed follow the speed)
}
-- Ponycorn-Dolphoodle ("Кирка Понирог-Дельфудель"): a dreamy magic pickaxe. The swing is a
-- sparkling swish with a rising glissando, the hit a bright major triad over a soft knock (a magic
-- "ting"), a perfect adds a high chime, a crit a dolphin "eeee!" (two fast rising squeaks) and a
-- twinkling arpeggio, the draw a soft "hup" (a prance) and a shimmering rise, the inspect a slow
-- charge (the horn fills with magic: a rising whoosh and an accelerating arpeggio) that ends in a
-- bright chord; while it is held a barely-there magic shimmer.
KITS.Magic={
 Swing={whoosh(2.8,.15,.14,SPARKLE),{PING,.1,2,CHORUS,to=3,ramp=.15}},
 Hit={{PING,.2,1.8,SPARKLE},{KNOCK,.12,1.6},{PING,.16,2.25,SPARKLE,at=.05},{PING,.13,2.7,SPARKLE,at=.1}},
 Perfect={{PING,.14,3.6,SPARKLE,at=.15}},
 Crit=join({{PING,.25,2.6,CHORUS,to=4.2,ramp=.18},{PING,.22,2.6,CHORUS,at=.12,to=4.6,ramp=.18},{LAND,.3,1}},
  arp(PING,.12,1.5,{1,1.25,1.5,2},.05,SPARKLE,.2)),
 Draw={{HOP,.16,1.6},{PING,.18,1.5,SPARKLE,to=2.5,ramp=.2,at=.04},{PING,.12,3,SPARKLE,at=.14}},
 Break=arp(PING,.14,1.5,{3,2.5,2,1.5},.05,SPARKLE),
 Inspect=join({{HOP,.16,1.5},{WIND,.12,1.2,SPARKLE,at=.15,dur=2,attack=1.6,fade=.3,loop=true,to=3.2,ramp=2}},
  arp(PING,.07,1.2,{1,1.25,1.5,2,1.25,1.5,2,2.5,1.5,2,2.5,3},.15,SPARKLE,.25),
  {{PING,.2,2,SPARKLE,at=2.15},{PING,.17,2.5,SPARKLE,at=2.17},{PING,.15,3,SPARKLE,at=2.19},{PING,.1,4,CHIME,at=2.3}}),
 Idle={{WIND,.008,3.2,SPARKLE,loop=true}}, -- a faint magic shimmer while it is held (nil = off)
}
-- Zombie-Frankenstein ("Кирка Зомби-Франкенштейн" concept sheet "ЭФФЕКТЫ (VFX / SFX)"): the SWING a heavy swish with a
-- buzzing arc; the HIT "электрический всплеск + судорожный рывок": a meaty smack, a bone crunch and a crackling zap; a
-- perfect adds a sharp "zzt"; the CRIT "ZZT!!": a long crackling surge, a thump and a wet splat; the DRAW the current
-- switching on (a rising hum, a clank, a zap); the BREAK a crackle and a splat; the INSPECT the lightning running along
-- the seams (two buzzing sweeps), creaking stitches, then the growl (a low distorted roar) and a clank (timed to
-- MiningClient.Anim INSPECTS.Franken / PickFX); IDLE "треск электричества": a low electric hum with a faint crackle,
-- RUN the sewn-on pieces rattling and squelching (volume and speed follow the holder's speed).
local HUM={TremoloSoundEffect={Depth=.5,Duty=.5,Frequency=12},DistortionSoundEffect={Level=.5},EqualizerSoundEffect={LowGain=6,MidGain=0,HighGain=-14}}
local GROWL={DistortionSoundEffect={Level=.85},EqualizerSoundEffect={LowGain=8,MidGain=4,HighGain=-18},TremoloSoundEffect={Depth=.5,Duty=.5,Frequency=9}}
local RATTLE={TremoloSoundEffect={Depth=1,Duty=.25,Frequency=6},EqualizerSoundEffect={LowGain=2,MidGain=4,HighGain=-6}}
KITS.Electric={
 Swing={whoosh(1.6,.22,.2,SQUARE),{TICK,.1,4,CRACKLE,at=.03,dur=.14,loop=true}},
 Hit={{LAND,.45,.9,THUMP},{TICK,.2,3.6,CRACKLE,at=.01,dur=.2,fade=.08,loop=true},{KNOCK,.22,1.4,CRUNCH},{SPLAT,.2,.8,WET,at=.02}},
 Perfect={{TICK,.16,5,CRACKLE,at=.04,dur=.12,loop=true}},
 Crit=join({{TICK,.3,4.5,CRACKLE,dur=.45,fade=.15,loop=true},{KNOCK,.45,.7},{LAND,.5,.6,THUMP}},
  {{TICK,.2,2.6,CRACKLE,at=.12,dur=.3,loop=true,to=5,ramp=.3},{SPLAT,.3,.6,WET,at=.08}}),
 Draw={{TICK,.16,1.2,HUM,dur=.35,loop=true,to=4,ramp=.3},{KNOCK,.2,1.2,nil,at=.12},{TICK,.2,4.5,CRACKLE,at=.3,dur=.15,loop=true}},
 Break={{TICK,.25,4,CRACKLE,dur=.25,loop=true},{SPLAT,.3,.6,WET}},
 Inspect=join({{TICK,.1,.9,HUM,at=.3,dur=.5,attack=.1,fade=.15,loop=true}},
  {{TICK,.16,3.4,CRACKLE,at=.45,dur=.45,fade=.1,loop=true,to=5,ramp=.45},{TICK,.16,3.4,CRACKLE,at=.95,dur=.45,fade=.1,loop=true,to=5,ramp=.45}},
  {{TICK,.05,.6,CREAK,at=1.45,dur=.5,fade=.2,loop=true},{CLICK,.18,.7,nil,at=1.75},{CLICK,.18,.7,nil,at=2.12}},
  {{LAND,.35,.55,GROWL,at=2.05,dur=.4,fade=.15,loop=true,to=.42,ramp=.4},{TICK,.22,4.2,CRACKLE,at=2.08,dur=.3,loop=true},{SPLAT,.24,.7,WET,at=2.2},{KNOCK,.24,1.1,nil,at=2.42}}),
 Idle={{TICK,.012,.45,HUM,loop=true},{TICK,.004,3.2,CRACKLE,loop=true}}, -- a low electric hum and a faint crackle while it is held (nil = off)
 Run={{CLICK,.04,.8,RATTLE,loop=true},{SPLAT,.02,.75,SQUELCH,loop=true}}, -- the sewn-on pieces rattle and squelch while the holder runs
}
-- Clown Chronomord ("Клоун-Хрономорд" concept sheet "ЗВУКИ"): the SWING a swish with jingling bells; the HIT "звон часов +
-- клоунский смех": a knock, a two-bell clock chime and a quick "ha-ha"; a perfect adds a high chime and a tick; the CRIT
-- a cascade of clock chimes, a thump, a honk and a long cackle; the DRAW the key winding back (falling clicks), "honk-honk"
-- and a giggle; the BREAK a chime, a clatter of ticks and a giggle; the INSPECT "обратный ход часов": a ticking whirr
-- running down and falling ratchet clicks while the clock rewinds, creaking springs while it turns round, then a chime
-- and the laugh (timed to MiningClient.Anim INSPECTS.Chrono / PickFX); IDLE "тиканье, скрипы механизмов": a quiet
-- tick-tock and a creak; RUN "ускоряющееся тиканье" (a tick loop whose volume and speed follow the holder's speed).
do
 local GIGGLE={DistortionSoundEffect={Level=.45},EqualizerSoundEffect={LowGain=-4,MidGain=8,HighGain=-4},TremoloSoundEffect={Depth=.45,Duty=.5,Frequency=30}}
 local CHIMES={ReverbSoundEffect={DecayTime=1.6,WetLevel=-5},EqualizerSoundEffect={LowGain=-8,MidGain=2,HighGain=3}}
 local REWIND={TremoloSoundEffect={Depth=1,Duty=.18,Frequency=14},EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=0}}
 -- "ha-ha-ha": short vowels (a ping through a nasal filter) gliding down, a breathy puff on every other one
 local function giggle(n,base,gap,vol,start)
  local rows={}
  for i=1,n do
   local at=(start or 0)+(i-1)*gap;local p=base*(1+((i%2==0)and .06 or 0))*(1-(i-1)*.03)
   table.insert(rows,{PING,vol,p,GIGGLE,at=at,dur=gap*.65,fade=gap*.3,to=p*.8,ramp=gap*.6,loop=true})
   if i%2==1 then table.insert(rows,{HOP,vol*.5,p*1.9,nil,at=at})end
  end
  return rows
 end
 KITS.Clown={
  Swing={whoosh(2,.2,.16,AIRY),{PING,.05,2.4,JINGLE,dur=.22,fade=.1,loop=true}},
  Hit=join({{KNOCK,.36,1.1},{PING,.2,2.4,CHIMES,dur=.3,fade=.12,loop=true},{PING,.15,3,CHIMES,at=.04,dur=.26,fade=.1,loop=true},{CLICK,.16,1.4,nil,at=.01}},
   giggle(2,1.35,.09,.08,.09)),
  Perfect={{PING,.14,4,CHIME,at=.08},{CLICK,.14,2.2,nil,at=.12}},
  Crit=join({{PING,.32,2,CHIMES,dur=.7,fade=.25,loop=true},{PING,.26,2.52,CHIMES,at=.12,dur=.6,fade=.25,loop=true},{PING,.22,3,CHIMES,at=.24,dur=.5,fade=.2,loop=true},
   {LAND,.42,.7,THUMP},{KNOCK,.4,.9},{PING,.22,.8,HONK,at=.05,dur=.2}},giggle(6,1.25,.1,.16,.18)),
  Draw=join(arp(CLICK,.16,1.6,{1.3,1.2,1.1,1},.05),{{PING,.2,.8,HONK,at=.22,dur=.12},{PING,.2,1,HONK,at=.36,dur=.12}},giggle(3,1.45,.08,.08,.5)),
  Break=join({{PING,.24,2.2,CHIMES,dur=.45,fade=.15,loop=true},{KNOCK,.28,.9}},arp(CLICK,.14,1.6,{1,1.4,1.2,1.7},.04,nil,.05),giggle(3,1.3,.09,.09,.12)),
  Inspect=join({{TICK,.08,2.4,REWIND,at=.4,dur=.85,attack=.1,fade=.15,loop=true,to=1.1,ramp=.85}},
   arp(CLICK,.15,1.5,{1.5,1.4,1.3,1.2,1.1,1,.95,.9},.1,nil,.42),
   {{TICK,.05,.6,CREAK,at=1.25,dur=.6,fade=.2,loop=true},{CLICK,.18,.8,nil,at=1.86}},
   {{PING,.22,2.4,CHIMES,at=1.9,dur=.4,fade=.15,loop=true}},giggle(7,1.2,.08,.15,1.95),{{PING,.2,.8,HONK,at=2.5,dur=.12}}),
  Idle={{CLICK,.028,.4,TICKTOCK,loop=true},{TICK,.004,.25,CREAK,loop=true}}, -- a quiet tick-tock and a creak while it is held (nil = off)
  Run={{CLICK,.05,1.05,TICKFAST,loop=true}}, -- ticking that speeds up while the holder runs (volume and speed follow the speed)
 }
end
-- Nasty Octopus ("Кирка Мерзкий Спрут" concept sheet "VFX EXAMPLES" / "SLIMY SOUND"): the SWING a wet tentacle whip (a heavy
-- swish, a lash and a squelch); the HIT a wet splat, a water splash and a sucker "bloop"; a perfect a rising "bloop" and a
-- splash; the CRIT the TENTACLE LASH: a whip crack, a big splash, a thump and a gurgle, then the water raining back; the DRAW
-- a slurp, a squelch and a "bloop" as it sucks onto the hand; the BREAK a splash and a squelch; the INSPECT a squelch as it
-- comes up, two curious rising "bloop?"s while the eye looks round, a cold shimmer as the cursed pearl grows, a gurgle while it
-- is turned round (the ink sac pumping), then the lash: a whip, a splat and the ink squirt, a last drip (timed to
-- MiningClient.Anim INSPECTS.Octo / PickFX); IDLE a faint wet bubbling and a slow drip; RUN squelchy, sloshing steps (volume
-- and speed follow the holder's speed).
do
 local GURGLE={TremoloSoundEffect={Depth=.9,Duty=.5,Frequency=11},EqualizerSoundEffect={LowGain=8,MidGain=-2,HighGain=-18}}
 local PLIP={TremoloSoundEffect={Depth=1,Duty=.08,Frequency=.7},ReverbSoundEffect={DecayTime=1.2,WetLevel=-6},EqualizerSoundEffect={LowGain=-6,MidGain=2,HighGain=-4}}
 local SLOSH={TremoloSoundEffect={Depth=.7,Duty=.45,Frequency=4},EqualizerSoundEffect={LowGain=6,MidGain=-2,HighGain=-14}}
 local PEARL={ChorusSoundEffect={Depth=.4,Mix=.6,Rate=3},ReverbSoundEffect={DecayTime=2,WetLevel=-4},EqualizerSoundEffect={LowGain=-10,MidGain=0,HighGain=2}}
 KITS.Wet={
  Swing={whoosh(1.3,.2,.18,WET),{SLASH,.1,.62,WET,at=.02},{SPLAT,.12,1.1,nil,at=.06}},
  Hit={{SPLAT,.4,1,WET},{WATER,.3,1.2,WET},{LAND,.24,.8},{PING,.09,1.1,GOO,at=.04,to=1.7,ramp=.08,dur=.12,loop=true}},
  Perfect={{PING,.12,1.3,GOO,at=.05,to=2.1,ramp=.1,dur=.14,loop=true},{WATER,.12,1.7,nil,at=.08}},
  Crit=join({{SLASH,.22,.55,WET},{WATER,.5,.8,WET},{SPLAT,.45,.6},{LAND,.4,.6,THUMP}},
   {{WATER,.14,.5,GURGLE,at=.1,dur=.45,fade=.2,loop=true}},arp(PING,.1,.45,{1,1.3,.9,1.2},.05,GOO,.12),{{WATER,.22,1.4,WET,at=.3}}),
  Draw={{SPLAT,.2,1.3,WET},{WATER,.15,1.6,WET,at=.03},{PING,.1,.9,GOO,at=.1,to=1.6,ramp=.15,dur=.18,loop=true}},
  Break={{WATER,.45,.7,WET},{SPLAT,.3,.8,nil,at=.06},{PING,.08,1,GOO,at=.1,to=1.5,ramp=.1,dur=.12,loop=true}},
  Inspect=join({{SPLAT,.18,.9,WET,at=.3}},
   {{PING,.1,1.1,GOO,at=.48,to=1.8,ramp=.12,dur=.16,loop=true},{PING,.1,1.3,GOO,at=.8,to=2.2,ramp=.12,dur=.16,loop=true}},
   {{PING,.1,2.6,PEARL,at=1.0,dur=.5,attack=.2,fade=.25,loop=true,to=3.1,ramp=.5},{PING,.08,3.4,CHIME,at=1.1}},
   {{WATER,.12,.5,GURGLE,at=1.2,dur=.55,fade=.2,loop=true}},
   {{SLASH,.2,.75,WET,at=1.88},{SPLAT,.32,.7,WET,at=1.92},{WATER,.28,.9,WET,at=1.95},{WATER,.1,.45,GURGLE,at=2.0,dur=.3,fade=.15,loop=true},
    {PING,.08,1.2,GOO,at=2.35,to=1.8,ramp=.1,dur=.12,loop=true}}),
  Idle={{WATER,.012,.4,GOO,loop=true},{PING,.03,1.6,PLIP,loop=true}}, -- a faint wet bubbling and a slow drip while it is held (nil = off)
  Run={{SPLAT,.04,.8,SQUELCH,loop=true},{WATER,.02,.9,SLOSH,loop=true}}, -- squelchy, sloshing steps while the holder runs
 }
end
-- Hand of Fate ("Кирка Рука Судьбы" concept sheet "ЗВУКИ"): the SWING a deep whoosh with the creak of bones; the HIT (УДАР)
-- "a dull thud + the grinding of bones" (a low body thud, a knock, a bony crunch and a creak dragging under it); a perfect a
-- second crack and a low toll of fate; the CRIT (КРИТ) "a loud scream + distortion" (a distorted shriek gliding down over a
-- breathy roar and a heavy thump, the toll ringing out); the DRAW the knuckles cracking one after another and a slow breath
-- in as the eye opens; the BREAK a crunch and a toll; the INSPECT (ОСМОТР) "a creepy rustle + the blink of the eye" (the
-- fingers rustling as the hand opens, two wet blinks, a low drone while it is turned round, the knuckles cracking into the
-- fist and the glare's sting), timed to MiningClient.Anim INSPECTS.Fate / PickFX; IDLE "the quiet stirring of the fingers +
-- breathing" (a soft slow breath and a faint dry rustle); RUN "a stirring that speeds up" (volume and speed follow the speed).
do
 local BREATH={TremoloSoundEffect={Depth=.85,Duty=.5,Frequency=.35},EqualizerSoundEffect={LowGain=-4,MidGain=2,HighGain=-10}}
 local RUSTLE={TremoloSoundEffect={Depth=1,Duty=.25,Frequency=13},EqualizerSoundEffect={LowGain=-12,MidGain=2,HighGain=0}}
 local BONE={DistortionSoundEffect={Level=.6},EqualizerSoundEffect={LowGain=-2,MidGain=6,HighGain=-8}}
 local CREAKY={TremoloSoundEffect={Depth=1,Duty=.2,Frequency=9},EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=-6}}
 local SHRIEK={DistortionSoundEffect={Level=.85},EqualizerSoundEffect={LowGain=-4,MidGain=9,HighGain=-4},TremoloSoundEffect={Depth=.55,Duty=.5,Frequency=21},
  ReverbSoundEffect={DecayTime=2.4,WetLevel=-4}}
 local BLINK={EqualizerSoundEffect={LowGain=-6,MidGain=4,HighGain=-8}}
 local DRONE={TremoloSoundEffect={Depth=.5,Duty=.5,Frequency=5},EqualizerSoundEffect={LowGain=8,MidGain=-4,HighGain=-24},ReverbSoundEffect={DecayTime=3,WetLevel=-4}}
 local function cracks(n,base,gap,vol,start)
  local rows={}
  for i=1,n do table.insert(rows,{CLICK,vol,base*(1+(i%3)*.08),BONE,at=(start or 0)+(i-1)*gap})end
  return rows
 end
 KITS.Doom={
  Swing={whoosh(1,.26,.3,DOOM),{TICK,.06,.5,CREAKY,dur=.22,loop=true,at=.02}},
  Hit=join({{LAND,.5,.55,DOOM},{KNOCK,.32,.62},{CLICK,.26,.55,BONE,at=.01},{TICK,.1,.45,CREAKY,at=.03,dur=.28,fade=.12,loop=true}},cracks(2,.7,.05,.1,.05)),
  Perfect={{CLICK,.16,.8,BONE,at=.04},{PING,.12,.5,TOLL,at=.08}},
  Crit=join({{PING,.3,1.15,SHRIEK,dur=.65,fade=.3,loop=true,to=.62,ramp=.6},{WIND,.26,.55,{DistortionSoundEffect={Level=.9},EqualizerSoundEffect={LowGain=6,MidGain=2,HighGain=-18}},dur=.8,attack=.04,fade=.4,loop=true},
   {LAND,.6,.4,DOOM},{KNOCK,.4,.5,THUMP}},cracks(3,.6,.04,.14,.02),{{PING,.2,.38,TOLL,at=.1}}),
  Draw=join(cracks(4,.75,.08,.16),{{WIND,.08,.45,BREATH,at=.25,dur=.7,attack=.3,fade=.3,loop=true,to=.6,ramp=.7},{PING,.1,.5,TOLL,at=.3}}),
  Break={{LAND,.55,.38,DOOM},{CLICK,.24,.5,BONE,at=.03},{PING,.18,.42,TOLL,at=.05}},
  Inspect=join({{TICK,.07,1.3,RUSTLE,at=.35,dur=.55,attack=.1,fade=.2,loop=true}},
   {{SPLAT,.12,2.2,BLINK,at=.56},{SPLAT,.12,2.3,BLINK,at=1.01}},
   {{WIND,.08,.35,DRONE,at=.95,dur=.8,attack=.25,fade=.3,loop=true}},
   cracks(5,.7,.08,.15,1.72),
   {{PING,.22,1.3,SHRIEK,at=1.95,dur=.3,fade=.15,loop=true,to=.9,ramp=.3},{LAND,.3,.5,DOOM,at=1.95},{PING,.12,.45,TOLL,at=2.0}}),
  Idle={{WIND,.014,.45,BREATH,loop=true},{TICK,.004,1.1,RUSTLE,loop=true}}, -- a slow breath and a faint dry rustle while it is held (nil = off)
  Run={{TICK,.035,1.3,RUSTLE,loop=true}}, -- the stirring of the fingers speeds up while the holder runs (volume and speed follow the speed)
 }
end
-- Laughsaw ("Кирка Смехопила" concept sheet "ЗВУКИ"): a screaming circular saw that laughs. The SWING
-- revs the saw (a distorted buzz pitching up) with a heavy swish, the HIT is "the roar of the saw + a mad
-- laugh": the blade biting stone (a high grinding buzz, a knock, a rasp) and a quick "ha-ha", a perfect
-- adds a sharper bite, a CRIT is "a loud laugh and a sharp saw shriek" (a long rising shriek, a heavy
-- thump and a five-beat cackle); the DRAW starts the motor (a pull click, the buzz spinning up, a chain
-- rattle), the INSPECT is "the grinding of mechanisms + a hoarse laugh" (ratchet clicks and a low grind,
-- the saw revving up, then a slow, rough "ha... ha... ha-ha-ha"); IDLE "the quiet spinning of the
-- blade", RUN "the blade spinning faster" (a buzz that rises with the speed). The laugh is a short vowel
-- (a ping through a hoarse filter) gliding down, over a breathy puff, once per "ha".
local LAUGH={DistortionSoundEffect={Level=.7},EqualizerSoundEffect={LowGain=0,MidGain=8,HighGain=-10},TremoloSoundEffect={Depth=.5,Duty=.5,Frequency=34}}
local HOARSE={DistortionSoundEffect={Level=.9},EqualizerSoundEffect={LowGain=4,MidGain=6,HighGain=-14},TremoloSoundEffect={Depth=.7,Duty=.5,Frequency=26}}
local function cackle(n,base,gap,vol,start,fx)
 local rows={}
 for i=1,n do
  local at=(start or 0)+(i-1)*gap;local p=base*(1-(i-1)*.035)
  table.insert(rows,{PING,vol,p,fx or LAUGH,at=at,dur=gap*.7,fade=gap*.3,to=p*.78,ramp=gap*.7,loop=true})
  if i%2==1 then table.insert(rows,{HOP,vol*.6,p*1.6,nil,at=at})end
 end
 return rows
end
KITS.Saw={
 Swing={{TICK,.24,3.2,SAW,dur=.24,loop=true,to=5,ramp=.2},{SLASH,.22,1.15},whoosh(1.6,.18,.2,AIRY)},
 Hit=join({{TICK,.32,5,SAW,dur=.2,loop=true,to=4.2,ramp=.2},{KNOCK,.3,1.25},{SLASH,.16,1.7,CRUNCH,at=.01}},cackle(2,.95,.1,.1,.08)),
 Perfect={{TICK,.18,6.4,SAW,at=.04,dur=.12,loop=true},{PING,.08,2.8,BRIGHT,at=.05}},
 Crit=join({{TICK,.38,3.4,SAW,dur=.5,loop=true,to=7,ramp=.45},{PING,.14,3.6,SAW,dur=.4,loop=true,to=6,ramp=.4},{KNOCK,.42,1},{LAND,.4,.7,THUMP}},
  cackle(5,1.05,.11,.2,.14)),
 Draw={{CLICK,.3,.7},{TICK,.26,.9,SAW,at=.05,dur=.45,loop=true,to=3.6,ramp=.4},{CLICK,.16,1.9,nil,at=.2},{CLICK,.14,2.2,nil,at=.26},{CLICK,.12,2,nil,at=.32}},
 Break=join({{TICK,.3,4,SAW,dur=.3,loop=true,to=2,ramp=.3},{KNOCK,.3,.9}},cackle(3,1,.1,.12,.12)),
 Inspect=join({{CLICK,.22,.6},{CLICK,.2,.7,nil,at=.12},{CLICK,.2,.8,nil,at=.24},{TICK,.12,.45,CRUNCH,at=.05,dur=.55,loop=true,to=.3,ramp=.5},
  {TICK,.2,1.4,SAW,at=.35,dur=.95,loop=true,to=5.2,ramp=.75,fade=.25}},
  cackle(3,.62,.24,.17,1.25,HOARSE),cackle(3,.72,.12,.15,1.98,HOARSE),{{KNOCK,.2,.8,nil,at=2.4}}),
 Idle={{TICK,.022,2.4,SAW,loop=true},{WIND,.006,2.6,PULSE,loop=true}}, -- the quiet spinning of the blade while it is held (nil = off)
 Run={{TICK,.045,3.6,SAW,loop=true}}, -- the blade spins faster while the holder runs (volume and pitch follow the speed)
}
-- Scarlet Anime Scythe ("Алая Аниме-Коса", concept sheet "ЗВУКИ"): the SWING is a fast blade swish
-- with an energy whoosh, the HIT a sharp anime "shing" with a burst of energy (a ringing blade, a
-- high shimmer, a bright whoosh and a low thump), a perfect adds a second ringing cut, a crit is a
-- slow-motion cut (a long shing, a deep boom and a ringing tail); the DRAW a fast stylish unsheathing,
-- the INSPECT a swelling magic sound (a rising whoosh and an accelerating chime run ending in a
-- shing), IDLE a quiet pulsing energy hum, RUN a light whistling trail that follows the speed.
KITS.Shing={
 Swing={{SLASH,.34,1.55,BRIGHT},whoosh(2.4,.2,.2,AIRY),{PING,.06,2.2,SHINE,to=3.2,ramp=.15}},
 Hit={{SHEATH,.42,1.5,RING},{PING,.14,2.9,SHINE,at=.01},{SLASH,.24,2.1,RING,at=.02},whoosh(3.4,.16,.16,BRIGHT,.03),{LAND,.2,1.1,THUMP,at=.01}},
 Perfect={{SHEATH,.24,1.9,RING,at=.05},{PING,.1,3.8,SHINE,at=.07}},
 Crit={{SHEATH,.5,.95,SHINE},{SLASH,.42,.75,SHINE,at=.02},whoosh(1.1,.3,.5,DOOM,.05),{LAND,.45,.55,THUMP,at=.18},{PING,.2,3,SHINE,at=.2},{PING,.14,4,SHINE,at=.26}},
 Draw={whoosh(3,.16,.12,AIRY),{SHEATH,.38,1.3,RING,at=.04},{PING,.1,2.6,SHINE,at=.16}},
 Break={{SLASH,.35,1.2},{SHEATH,.3,.9,nil,at=.05},{PING,.1,2.2,SHINE,at=.08}},
 Inspect=join({whoosh(.9,.1,.3,AIRY),{WIND,.1,.9,SHINE,at=.2,dur=1.9,attack=1.5,fade=.3,loop=true,to=2.6,ramp=1.9}},
  arp(PING,.06,1.3,{1,1.19,1.5,1.78,2,2.38,3,3.56},.2,SHINE,.4),
  {{SHEATH,.4,1.4,RING,at=2.15},{PING,.16,3,SHINE,at=2.17},{LAND,.25,.7,THUMP,at=2.15}}),
 Idle={{WIND,.012,.55,PULSE,loop=true},{TICK,.004,1.6,PULSE,loop=true}}, -- a quiet pulsing hum while it is held (nil = off)
 Run={{WIND,.05,2.4,AIRY,loop=true}}, -- a light whistle while the holder runs (volume follows the speed)
}
-- Twin Claws ("Кирка Когти-Близнецы"): steel talons on servo-driven voxel gauntlets. The SWING is a
-- fast metal swipe through the air, the HIT four claws raking stone (a ringing slash, a knock, a
-- rasping scrape, a dull thump), a perfect adds a second ringing rake, a CRIT is the cross strike (two
-- crossing "shing"s, a heavy clang and boom, a long scrape); the DRAW is the claws deploying (a short
-- servo whirr, then the "snikt" and a lock click, timed to MiningClient.PickFX), the INSPECT follows
-- its choreography (servos draw the claws in, SNAP out, in again, SNAP out, the rune's low hum, the
-- arms thrown apart), IDLE a faint pulsing servo hum, RUN a thin metal whistle that follows the
-- speed. Left and right alternate in pitch.
KITS.Metal={
 Swing={{LUNGE,.24,2.0},whoosh(3.2,.16,.12,AIRY),{SLASH,.14,2.6,BRIGHT,at=.02}},
 Hit={{SLASH,.32,2.0,RING},{KNOCK,.3,1.35},{TICK,.14,4.2,CRUNCH,at=.02,dur=.1,loop=true},{LAND,.18,1.2,THUMP,at=.01}},
 Perfect={{SLASH,.18,2.7,nil,at=.04},{SHEATH,.12,2.2,RING,at=.06}},
 Crit={{SHEATH,.42,1.3,RING},{SHEATH,.36,1.55,RING,at=.05},{LUNGE,.3,1.4,RING,at=.02},{KNOCK,.42,.9,THUMP},{LAND,.45,.6,THUMP,at=.03},
  {TICK,.16,5,CRUNCH,at=.04,dur=.18,loop=true}},
 Draw={{TICK,.1,1.6,CRUNCH,dur=.16,loop=true,to=3.2,ramp=.16},{SHEATH,.34,1.75,RING,at=.12},{CLICK,.22,.8,nil,at=.13}},
 Break={{LUNGE,.32,1.3},{KNOCK,.34,.85},{SLASH,.16,1.8,nil,at=.04}},
 Inspect={{TICK,.08,2,CRUNCH,dur=.3,loop=true,to=1,ramp=.3},{CLICK,.2,.9,nil,at=.3},
  {SHEATH,.4,1.6,RING,at=.58},{CLICK,.2,1.1,nil,at=.58},{PING,.1,.5,TOLL,at=.62},
  {TICK,.07,2.4,CRUNCH,at=1.17,dur=.18,loop=true,to=1.2,ramp=.18},{SHEATH,.4,1.9,RING,at=1.36},{CLICK,.2,1.2,nil,at=1.36},
  whoosh(2.6,.2,.25,AIRY,1.8),{LUNGE,.22,1.6,nil,at=1.85},{PING,.12,1,TOLL,at=1.9}},
 Idle={{TICK,.006,.9,PULSE,loop=true},{WIND,.008,.45,PULSE,loop=true}}, -- a faint servo hum while they are held (nil = off)
 Run={{WIND,.04,2.8,AIRY,loop=true}}, -- a thin metal whistle while the holder runs (volume follows the speed)
 Alternate=1.06, -- every other Swing / Hit is this much higher (left / right claw)
}
-- TV-Head ("Retro Horror"): a heavy steel CRT. The swing drags a crackling static tail, the hit is
-- a hollow case thunk + a static burst + a two-tone glitch beep, a crit is the "NO SIGNAL" test tone
-- and the tube switching off, the draw powers the tube on (thunk, rising whine, static), the
-- inspect flips channels (click, static sweep, a falling square-wave "heh-heh-heh"), and while it is
-- held the tube hisses and whines faintly.
KITS.Glitch={
 Swing={whoosh(3.2,.24,.18,STATIC),{TICK,.12,5,CRUNCH},{TICK,.07,.9,CRACKLE,dur=.16,loop=true,at=.02}},
 Hit={{KNOCK,.42,.85,THUMP},whoosh(4,.26,.14,STATIC),{PING,.18,.62,SQUARE,dur=.09},{PING,.13,1.24,SQUARE,at=.05,dur=.07},{TICK,.18,6,CRUNCH,at=.03}},
 Perfect={{PING,.15,1.9,SQUARE,at=.06,dur=.08},{PING,.12,2.53,SQUARE,at=.1,dur=.08}},
 Crit={{PING,.3,1,SQUARE,dur=.45,loop=true},whoosh(4,.35,.5,STATIC),{KNOCK,.45,.7,THUMP},{TICK,.3,.3,THUMP,at=.45,to=.15,ramp=.2},{PING,.12,4,BRIGHT,at=.46,dur=.12,to=1,ramp=.12}},
 Draw={{KNOCK,.3,.7,THUMP},{TICK,.18,.5,BRIGHT,dur=.35,loop=true,to=7,ramp=.35},whoosh(4,.14,.25,STATIC,.2),{PING,.1,2.6,SQUARE,at=.34,dur=.05}},
 Break={whoosh(3,.3,.3,STATIC),{PING,.2,.5,SQUARE,dur=.2}},
 Inspect=join({{CLICK,.32,.7},whoosh(2.6,.22,.5,STATIC,.04),{TICK,.1,.35,CRACKLE,dur=.6,loop=true,at=.1},{CLICK,.26,.95,nil,at=.55}},
  arp(PING,.11,.52,{1,.84,.7},.15,SQUARE,.7),
  {{CLICK,.28,1.15,nil,at=1.6},whoosh(4,.18,.28,STATIC,1.6),{TICK,.1,.5,BRIGHT,at=2.3,dur=.25,loop=true,to=4,ramp=.25}}),
 Idle={{WIND,.018,3.5,STATIC,loop=true},{TICK,.006,7.5,BRIGHT,loop=true}}, -- CRT hiss + a thin tube whine while it is held (nil = off)
}
Audio.Kits=KITS

local function kitName(def)
 local name=type(def)=='table'and def.Sound or def
 if type(name)=='string'and KITS[name]then return name end
 return'Wood'
end
Audio.Kit=kitName

-- Swing timing out of a session (the whoosh follows the character animation's downstroke).
local SWING_DELAY={Chop=.04,Smash=.12,Slash=.03,Claw=.05,Bounce=.04,Prance=.05,Reap=.09,Scoop=.07,Rip=.1,Clack=.09,SixSeven=.15,Alarm=.1,Franken=.12,Chrono=.1,Octo=.09,Fate=.13}
-- A common gold-zone shimmer every kit's Perfect gets (the timing judgement sounds the same).
local GOLD={{TICK,.12,2.6,CHIME,at=.02}}

-- A sound must never break gameplay code: every public entry runs protected, the first error is
-- reported once.
local warned=false
local function guard(fn,...)
 local ok,err=pcall(fn,...)
 if not ok and not warned then warned=true;warn('MiningAudio: '..tostring(err))end
end

local kitLast=setmetatable({},{__mode='k'}) -- throttle key (lane name, a corner or a player) -> kit..cue -> time
local KIT_GAP={Swing=.07,Hit=.045,Perfect=.045,Crit=.08,Draw=.6,Break=.3,Inspect=2}
local density,densityAt=0,0
local function pickaxe(cue,def,where,opts)
 if type(cue)~='string'then return end
 opts=type(opts)=='table'and opts or{}
 local name=kitName(def)
 local kit=KITS[name]
 local lane=opts.Remote and'Remote'or'Local'
 local owner=opts.Key or lane
 local stamps=kitLast[owner];if not stamps then stamps={};kitLast[owner]=stamps end
 local now=os.clock()
 if KIT_GAP[cue]and now-(stamps[name..cue]or -1)<KIT_GAP[cue]then return end
 stamps[name..cue]=now
 local k=(opts.Volume or 1)*(opts.Remote and .7 or 1)
 local p=jitter()
 -- Left / right claw: every other swing and every other strike (hit or perfect) of this owner.
 if kit.Alternate and(cue=='Swing'or cue=='Hit'or cue=='Perfect')then
  local side=name..(cue=='Swing'and'SwingSide'or'HitSide')
  stamps[side]=not stamps[side]
  if stamps[side]then p*=kit.Alternate end
 end
 -- Another player's pickaxe: the first two layers (the swish only its first), its own voice budget.
 local max=opts.Remote and(cue=='Swing'and 1 or 2)or nil
 -- Dense hitting (several hits within ~half a second): the impact keeps its two main layers.
 if not opts.Remote and(cue=='Hit'or cue=='Perfect')then
  density=density*math.exp(-(now-densityAt)/.5)+1;densityAt=now
  if density>3 then max=2 end
 end
 local upload=Audio.KitAssetIds[name]and Audio.KitAssetIds[name][cue]
 local function go()
  if type(upload)=='number'and upload>0 then
   shot({'rbxassetid://'..string.format('%.0f',upload),Audio.UploadVolume,1},k,p,where,lane,true)
  elseif cue=='Perfect'then
   play(kit.Hit,where,lane,k,p,max)
   if not opts.Remote then
    local rise=1+math.min(.06,(tonumber(opts.Combo)or 0)*.004)
    play(kit.Perfect or{},where,lane,k,p*rise)
    play(GOLD,where,lane,k,rise)
   end
  elseif kit[cue]then
   play(kit[cue],where,lane,k,p,max)
  end
 end
 local delay=(cue=='Swing'and opts.Air)and(SWING_DELAY[type(def)=='table'and def.Swing or'Chop']or 0)or 0
 later(delay,go)
end
function Audio.Pickaxe(cue,def,where,opts)guard(pickaxe,cue,def,where,opts)end

-- Idle loop of the pickaxe in the local player's hand (Saw, TV). One at a time.
-- A kit's Run rows play under it at a volume that follows the local character's ground speed.
local idle={}
local runConn=nil
local function stopIdle()
 if runConn then runConn:Disconnect();runConn=nil end
 for _,s in ipairs(idle)do
  if s.Parent then TweenService:Create(s,TweenInfo.new(.25),{Volume=0}):Play();Debris:AddItem(s,.3)end
 end
 table.clear(idle)
end
function Audio.StopIdle()guard(stopIdle)end
local function startIdle(def,where)
 stopIdle()
 local kit=KITS[kitName(def)]
 if not(kit and kit.Idle)then return end
 for _,row in ipairs(kit.Idle)do
  local s=Instance.new('Sound');s.Name='MiningIdle';s.SoundId=row[1];s.Looped=true;s.Volume=0;s.PlaybackSpeed=row[3]
  s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=6;s.RollOffMaxDistance=40
  dress(s,row[4])
  s.Parent=where or SoundService;s:Play()
  TweenService:Create(s,TweenInfo.new(.4),{Volume=row[2]}):Play()
  table.insert(idle,s)
 end
 if kit.Run and RunService:IsClient()then
  local voices={}
  for _,row in ipairs(kit.Run)do
   local s=Instance.new('Sound');s.Name='MiningRun';s.SoundId=row[1];s.Looped=true;s.Volume=0;s.PlaybackSpeed=row[3]
   dress(s,row[4]);s.Parent=where or SoundService;s:Play()
   table.insert(idle,s);table.insert(voices,{Sound=s,Volume=row[2],Speed=row[3]})
  end
  local level=0
  runConn=RunService.Heartbeat:Connect(function(dt)
   local character=Players.LocalPlayer and Players.LocalPlayer.Character
   local root=character and character:FindFirstChild('HumanoidRootPart')
   local v=root and root.AssemblyLinearVelocity or Vector3.zero
   local want=math.clamp((Vector3.new(v.X,0,v.Z).Magnitude-5)/14,0,1)
   level+=(want-level)*math.min(1,dt*5)
   for _,x in ipairs(voices)do
    if x.Sound.Parent then x.Sound.Volume=x.Volume*level;x.Sound.PlaybackSpeed=x.Speed*(.85+level*.3)end
   end
  end)
 end
end
function Audio.StartIdle(def,where)guard(startIdle,def,where)end

-- GENERIC CUES (shared by every pickaxe) ---------------------------------------------------------
local function one(id,vol,speed,where,fx,extra)
 local row={id,vol,speed,fx}
 for key,v in pairs(extra or{})do row[key]=v end
 later(row.at,function()shot(row,1,1,where,where and'Remote'or'Local',true)end)
end
local CUES={}
CUES.Milestone=function(where)
 for i,step in ipairs({1,1.25,1.5,2,2.5})do one(PING,.16,step*1.1,where,CHIME,{at=(i-1)*.07})end
 one(TICK,.3,.2,where,IMPACT)
end
CUES.Draw=function(where)one(SHEATH,.2,1.1,where);one(TICK,.1,1.3,where)end
CUES.Holster=function(where)one(CLICK,.15,.9,where);one(HOP,.12,.9,where)end
CUES.Miss=function(where)
 one(TICK,.14,.5,where,{EqualizerSoundEffect={LowGain=0,MidGain=0,HighGain=-18},DistortionSoundEffect={Level=.3}})
end
CUES.Break=function(where)
 one(KNOCK,.48,.72,where);one(LAND,.42,.8,where);one(TICK,.3,.16,where,IMPACT)
end
CUES.RareBreak=function(where)
 CUES.Break(where)
 for i,step in ipairs({1,1.25,1.5,2})do one(TICK,.18,step*1.5,where,CHIME,{at=(i-1)*.12})end
end
local coinAt=0
CUES.Coin=function(where,combo)
 local now=os.clock();if now-coinAt<.07 then return end;coinAt=now
 one(TICK,.11,1.8+math.min(.6,(combo or 0)*.06),where)
end
CUES.Buy=function(where)
 for i,step in ipairs({1,1.25,1.5,2})do one(TICK,.18,step*1.5,where,CHIME,{at=(i-1)*.1})end
end
CUES.Deny=function(where)
 local fx={EqualizerSoundEffect={LowGain=0,MidGain=0,HighGain=-18},DistortionSoundEffect={Level=.3}}
 one(TICK,.18,.5,where,fx);one(TICK,.18,.42,where,fx,{at=.08})
end
-- A real whoosh now (a slice of the wind loop), not a re-pitched tick.
CUES.Whoosh=function(where)
 shot(whoosh(2.2,.28,.2,AIRY),1,jitter(),where,where and'Remote'or'Local',true)
end
CUES.Lift=function(where,progress)
 one(TICK,.07,.35+(progress or 0)*.5,where,{EqualizerSoundEffect={LowGain=8,MidGain=-4,HighGain=-20}})
end
CUES.LiftTop=function(where)CUES.Whoosh(where);one(LAND,.4,.7,where,nil,{at=.18})end
CUES.Strength=function(where)
 for i,step in ipairs({1,1.5})do one(TICK,.16,step*1.5,where,CHIME,{at=(i-1)*.11})end
end
CUES.Click=function(where)one(TICK,.1,1.2,where)end

local KIT_CUE={Hit=true,Perfect=true,Crit=true}
local throttle={Hit=.04,Perfect=.04,Crit=.05,Miss=.08,Lift=.05,Click=.05,Milestone=.4,Draw=.5,Holster=.3}
local lastPlayed={}
-- Legacy entry: Play(cue, parent, ...). Hit / Perfect / Crit with a sound name use that kit.
local function playCue(cue,where,...)
 if type(cue)~='string'then return end
 if KIT_CUE[cue]then
  local _tier,sound=...
  pickaxe(cue,sound or'Wood',where,{Remote=where~=nil})
  return
 end
 local now=os.clock()
 if throttle[cue]and now-(lastPlayed[cue]or 0)<throttle[cue]then return end
 lastPlayed[cue]=now
 local asset=Audio.AssetIds[cue]
 if type(asset)=='number'and asset>0 then shot({'rbxassetid://'..string.format('%.0f',asset),.5,1},1,1,where,where and'Remote'or'Local',true);return end
 local fn=CUES[cue];if fn then fn(where,...)end
end
function Audio.Play(cue,where,...)guard(playCue,cue,where,...)end

-- The one knob for every mining sound (a future settings slider): 0..1.
function Audio.SetVolume(v)guard(function()soundGroup().Volume=math.clamp(tonumber(v)or 1,0,1)end)end
function Audio.Stats()return{Local=live.Local,Remote=live.Remote}end

-- The group exists from the start (not on the first mining sound), so a scene that silences every
-- SoundGroup and restores them later (the lab's Corrupted cinematic) finds it.
guard(soundGroup)
-- Warm the bundled files once (they load from disk; this only removes the first-play hitch).
task.spawn(function()
 pcall(function()game:GetService('ContentProvider'):PreloadAsync(Audio.Sources)end)
end)

return Audio
