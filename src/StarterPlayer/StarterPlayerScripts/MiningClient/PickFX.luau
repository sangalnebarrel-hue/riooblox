-- DOGROTS pickaxe pack, client side: every pickaxe's own hit / crit effects (Theme in
-- Config.Mining.Pickaxes), the living models (idle motion, rainbow / pulsing / flickering parts,
-- the TV screen, a trail while swinging or running) for every held pickaxe in the world and for
-- the market previews, and a short "hit" boost that exaggerates the motion on every strike
-- (eyes pop out, the Hand of Fate's claws squeeze, the saw spins faster, the LEGO hand clacks, the 67 glitches...).
-- Animated parts carry the attributes MiningModels.Pickaxe writes (PickAnim, PickJoint, PickBase,
-- PickPhase, PickPop, PickRainbow, PickPulse, PickFlicker). Held models move through their
-- Motor6D.Transform (local only, written after the Animator in Stepped, like MiningClient.Anim);
-- anchored previews are moved directly.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local PickFX={}

local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local FIRE='rbxasset://textures/particles/fire_main.dds'
local C=Color3.fromRGB
local rad=math.rad
local sin,cos=math.sin,math.cos

-- MOTIONS ----------------------------------------------------------------------------------------
-- Each returns a CFrame in model axes applied at the part's joint. t = clock, ph = phase,
-- h = hit boost 0..1 (decays after every strike), pop = PickPop direction or nil.
local function blink(t,ph)return((t+ph)%3.4)<.14 and 1 or 0 end
local function twitch(t,ph)
 local k=math.floor(t*2.6+ph)
 return math.noise(k*.37,ph*1.7)>.18 and math.noise(k*.91,ph)*.9 or 0
end
-- Ponycorn fins: a slow drift, a flap while running, a whip on a strike, a sway during the inspect.
local function ponyFin(t,h,s)
 local run,insp=s and s.Run or 0,s and s.Insp or 0
 return sin(t*1.8)*.05+run*sin(t*9)*.1+h*sin(t*20)*.3+insp*sin(t*3.2)*.08
end
-- Pickaxe 67: the chain's swing from its eye under the 7 (shared by the chain links and the tag).
local function sixSwing(t,h,s)
 local run,insp=s and s.Run or 0,s and s.Insp or 0
 local o=s and s.Six7 or Vector3.zero
 return CFrame.new(o.X+sin(t*2.6)*.012,o.Y-sin(t*2.6)*.025+h*.06,0)
  *CFrame.Angles(cos(t*1.5)*.06-run*(.5+sin(t*9)*.12)+insp*sin(t*2.6)*.12,0,sin(t*1.9)*.1+run*sin(t*10)*.18+h*sin(t*17)*.55)
end
local MOTIONS={
 Bob=function(t,ph,h)return CFrame.new(0,sin(t*3+ph)*.07,0)end,
 FlutterL=function(t,ph,h)return CFrame.Angles(0,sin(t*26+ph)*.85,0)end,
 FlutterR=function(t,ph,h)return CFrame.Angles(0,-sin(t*26+ph)*.85,0)end,
 ClenchL=function(t,ph,h)return CFrame.Angles(0,0,-(sin(t*1.6)+1)*.07-h*.32)end,
 ClenchR=function(t,ph,h)return CFrame.Angles(0,0,(sin(t*1.6)+1)*.07+h*.32)end,
 BobA=function(t,ph,h)return CFrame.new(0,sin(t*2.6)*.08+h*.25,0)end,
 BobB=function(t,ph,h)return CFrame.new(0,sin(t*2.6+math.pi)*.08+h*.25,0)end,
 Jiggle=function(t,ph,h)return CFrame.new(sin(t*7+ph)*.03+h*sin(t*41)*.12,sin(t*5+ph)*.05+h*sin(t*37)*.14,0)end,
 EyeLook=function(t,ph,h)return CFrame.Angles(sin(t*.7+ph)*.25+h*.3,sin(t*.53+ph*2)*.4,0)end,
 EyeTwitch=function(t,ph,h)local j=twitch(t,ph)*.35+h*sin(t*55)*.25;return CFrame.Angles(j,j*.7,0)end,
 Wave=function(t,ph,h)return CFrame.new(0,sin(t*3+ph)*.08*(1+h*3),sin(t*2.2+ph)*.06)end,
 Drip=function(t,ph,h)local k=(t*.55+ph)%1;return CFrame.new(0,-k*k*.6,0)end,
 Breathe=function(t,ph,h)return CFrame.new(0,sin(t*1.5)*.05+h*.12,0)end,
 Stalk=function(t,ph,h,pop)
  local r=CFrame.Angles(sin(t*1.3+ph)*.2,0,sin(t*1.1+ph*1.7)*.25)
  if pop and h>0 then return CFrame.new(pop*h*1.6)*r end
  return r
 end,
 HandSlow=function(t,ph,h)return CFrame.Angles(0,0,-t*.9)end,
 HandFast=function(t,ph,h)return CFrame.Angles(0,0,-t*5-h*25)end,
 HandBack=function(t,ph,h)return CFrame.Angles(0,0,t*4+h*20)end,
 Shake=function(t,ph,h)return CFrame.Angles(0,0,sin(t*42+ph)*(.04+h*.35))end,
 Fluff=function(t,ph,h)return CFrame.new(0,sin(t*2+ph)*.05,0)end,
 Twitch=function(t,ph,h)local j=twitch(t,ph)*.35+h*sin(t*60)*.4;return CFrame.Angles(j*.4,0,j)end,
 Tongue=function(t,ph,h)return CFrame.Angles(sin(t*4+ph)*.2+h*.7,0,sin(t*3+ph)*.15)end,
 Tentacle=function(t,ph,h)local k=.12*(1+h*2.5);return CFrame.Angles(sin(t*1.8+ph)*k,0,cos(t*1.5+ph)*k)end,
 Curl=function(t,ph,h)return CFrame.Angles((sin(t*1.2+ph)+1)*.1+h*.95,0,0)end,
 BlinkLow=function(t,ph,h)return CFrame.new(0,math.max(blink(t,ph),h>.6 and 1 or 0)*.3,0)end,
 BlinkHigh=function(t,ph,h)return CFrame.new(0,-math.max(blink(t,ph),h>.6 and 1 or 0)*.3,0)end,
 Spin=function(t,ph,h)return CFrame.Angles(0,0,-t*12)end,
 ClawOut=function(t,ph,h)return CFrame.new(0,(sin(t*1.4+ph)+1)*.18-.42+h*.5,0)end,
 Antenna=function(t,ph,h)return CFrame.Angles(0,0,sin(t*3+ph)*.12+h*.45*sin(t*44))end,
 -- TV-Head: the bent antennas sway, rattle while the holder runs, quiver on a strike and during the
 -- inspect; the upper segments swing further (the antenna bends). s = entry state {Run, Insp, Spin}.
 AntennaLow=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(sin(t*2.3+ph)*.04+run*(.08+sin(t*17+ph)*.07),0,sin(t*3+ph)*.07+h*.35*sin(t*44)+run*sin(t*13+ph)*.08+insp*sin(t*31+ph)*.12)
 end,
 AntennaHigh=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(sin(t*2.3+ph-.4)*.08+run*(.16+sin(t*17+ph-.5)*.14),0,sin(t*3+ph-.5)*.14+h*.6*sin(t*44-.6)+run*sin(t*13+ph-.6)*.16+insp*sin(t*31+ph)*.25)
 end,
 -- TV-Head knobs: every few seconds somebody "changes the channel" (a click to a new angle); the
 -- inspect spins them.
 Knob=function(t,ph,h,pop,s)
  local k=math.floor(t*.3+ph)
  return CFrame.Angles(0,0,math.noise(k*.73,ph)*2.4+(s and s.Spin or 0)+h*sin(t*50)*.3)
 end,
 -- TV-Head pixels dripping off the case (PickFX fades them in and out, see TV_DRIP).
 PixelDrip=function(t,ph,h)local k=(t*.6+ph)%1;return CFrame.new(0,-k*k*1.1,0)end,
 -- Gummy Horror (concept sheet "АНИМАЦИЯ"): IDLE stretches and quivers, IN HAND the elastic body
 -- sways (more while running), a HIT is sticky and the head springs back like marmalade (a damped
 -- wobble of the whole head and both horns), INSPECT chomps and rolls the eye. p = the part entry
 -- (Amp = signed share along a horn, DropK = share of a drip's neck).
 GummyWobble=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.new(sin(t*7.3)*.012*(1+run*2)+h*sin(t*31)*.07,sin(t*2.1)*.035+run*sin(t*14)*.045+h*sin(t*26)*.1+insp*sin(t*5)*.05,0)
 end,
 GummyArm=function(t,ph,h,pop,s,p)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  local a=p and p.Amp or 0
  return CFrame.Angles(0,0,a*(sin(t*2.1+.6)*.035+run*sin(t*12)*.09+h*sin(t*24)*.32+insp*sin(t*4.5)*.12))
 end,
 GummyEye=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local k=math.floor(t*.9+ph)
  return CFrame.Angles(math.noise(k*.71,3.1)*.5+insp*sin(t*7)*.35+h*sin(t*47)*.12,math.noise(k*.37,ph+.5)*.9+insp*cos(t*7)*.45,0)
 end,
 GummyLidTop=function(t,ph,h,pop,s)
  local b=math.max(blink(t,ph),h>.55 and .7 or 0,(s and s.Insp or 0)*.3)
  return CFrame.new(0,-b*.34,0)
 end,
 GummyLidBot=function(t,ph,h,pop,s)
  local b=math.max(blink(t,ph),h>.55 and .7 or 0,(s and s.Insp or 0)*.3)
  return CFrame.new(0,b*.14,0)
 end,
 GummyJaw=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  return CFrame.Angles(.04+(sin(t*1.7)+1)*.04+sin(math.min(1,h)*math.pi)*.5+insp*math.max(0,sin(t*9))*.45,0,0)
 end,
 -- a drip stretches on its neck (DropK .33 / .66) and the drop (DropK 1) falls off; PickGoo fades it
 GummyDrop=function(t,ph,h,pop,s,p)
  local k=(t*.42+ph)%1
  local f=p and p.DropK or 1
  local y
  if k<.7 then y=(k/.7)^1.6*.32*f
  elseif f>=1 then y=.32+((k-.7)/.3)^2*1.4
  else y=.32*f*(1-(k-.7)/.3)end
  return CFrame.new(0,-y,0)
 end,
 -- Ponycorn-Dolphoodle (concept sheet "VFX / Анимации"): IDLE the poodle fluff breathes softly and
 -- the dolphin fins drift, IN HAND / RUN the fins sweep back and flap, the charms swing behind and
 -- the fluff bounces, a HIT whips the fins and rattles the charms, INSPECT turns the halo round the
 -- glowing horn. p = the part entry (Amp = fin side, Hang = the charm's hook from the fin root).
 PonyFluff=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  return CFrame.new(cos(t*1.7+ph)*.012,sin(t*2.2+ph)*.03+run*math.abs(sin(t*7+ph))*.05+h*sin(t*24+ph)*.07,sin(t*1.9+ph)*.012)
 end,
 PonyFin=function(t,ph,h,pop,s,p)
  local side=p and p.Amp or 0
  local run=s and s.Run or 0
  return CFrame.Angles(0,side*run*.14,side*ponyFin(t,h,s))
 end,
 PonyCharm=function(t,ph,h,pop,s,p)
  local run=s and s.Run or 0
  local hang=p and p.Hang or Vector3.zero
  local az=sin(t*2.3+ph)*.1+run*sin(t*8+ph)*.3+h*sin(t*15+ph)*.45-(p and p.Amp or 0)*ponyFin(t,h,s)
  local ax=cos(t*1.7+ph)*.06+run*(.35+sin(t*7+ph)*.1)
  return CFrame.new(hang)*CFrame.Angles(ax,0,az)*CFrame.new(-hang)
 end,
 PonyBlink=function(t,ph,h,pop,s)
  local b=math.max(blink(t,ph),h>.6 and .55 or 0)
  return CFrame.new(0,-b*.42,b*.03)
 end,
 PonyHalo=function(t,ph,h,pop,s)
  return CFrame.fromAxisAngle(typeof(pop)=='Vector3'and pop or Vector3.yAxis,t*1.2+(s and s.Spin or 0)*1.5)
 end,
 PonyTail=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  return CFrame.Angles(sin(t*2.2)*.08+run*sin(t*10)*.18+h*sin(t*18)*.25,0,0)
 end,
 -- Scarlet Anime Scythe (concept sheet "АНИМАЦИИ"): IDLE the demon eye looks round and blinks, the
 -- chains and the talisman sway softly, IN HAND / RUN they swing back and rattle, a HIT darts the eye
 -- and whips the chains, INSPECT turns the ring of pixel glyphs round the scythe.
 ScytheEye=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local k=math.floor(t*.8)
  return CFrame.new(math.noise(k*.61,1.3)*.07+insp*sin(t*5)*.05+h*sin(t*53)*.025,math.noise(k*.43,4.1)*.05+insp*cos(t*5)*.04,0)
 end,
 ScytheLidTop=function(t,ph,h)return CFrame.new(0,-math.max(blink(t,ph),h>.6 and .5 or 0)*.21,0)end,
 ScytheLidBot=function(t,ph,h)return CFrame.new(0,math.max(blink(t,ph),h>.6 and .5 or 0)*.21,0)end,
 ScytheChain=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(cos(t*1.6+ph)*.05-run*(.45+sin(t*8+ph)*.12)+insp*sin(t*2.4+ph)*.15,0,sin(t*1.9+ph)*.07+run*sin(t*9+ph)*.18+h*sin(t*16+ph)*.5)
 end,
 ScytheTalisman=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  return CFrame.Angles(cos(t*1.3+ph)*.06-run*(.6+sin(t*10+ph)*.15)+h*sin(t*13)*.25,sin(t*.9+ph)*.12,sin(t*1.7+ph)*.08+run*sin(t*7+ph)*.12+h*sin(t*17+ph)*.4)
 end,
 ScytheHalo=function(t,ph,h,pop,s)
  return CFrame.fromAxisAngle(typeof(pop)=='Vector3'and pop or Vector3.yAxis,t*1.4+(s and s.Spin or 0)*1.2)
 end,
 -- Twin Claws (concept sheet "ANIMATION PREVIEW"): IDLE the claws slowly slide in and out of the
 -- fingers, a strike or a run keeps them fully out, the deploy (the gauntlets come on) shoots them
 -- out, the INSPECT snaps them in and out twice and spreads them; the actuators turn as they slide.
 -- s.ClawIn (0 out .. 1 in), s.Calm, s.Spread and s.Gear are worked out once a frame (twinState).
 TwinClaw=function(t,ph,h,pop,s,p)
  local idle=(sin(t*.8+ph)+1)*.5*.35*(s and s.Calm or 1)
  local k=math.max(s and s.ClawIn or 0,idle)
  return CFrame.new(0,-k*.34,0)*CFrame.Angles(0,0,-(p and p.Amp or 0)*(s and s.Spread or 0))
 end,
 TwinActuator=function(t,ph,h,pop,s)return CFrame.Angles((s and s.Gear or 0)+ph,0,0)end,
 -- Butterfly Catcher (concept sheet "АНИМАЦИИ"): IDLE the butterflies inside the film drift and
 -- flutter, the fireflies wander, the butterfly on the rim slowly opens and closes its wings, the bow
 -- tails sway; IN HAND / RUN the tails stream back and the butterflies flutter faster; a HIT scatters
 -- them; INSPECT they dance round the middle of the film. p = the part entry (Amp = signed tail share).
 NetFly=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  local a=.09+h*.07
  local x=sin(t*.9+ph)*a+cos(t*1.7+ph*2)*.035+insp*cos(t*2.4+ph)*.12+h*sin(t*31+ph)*.03
  local y=cos(t*1.1+ph*1.3)*a+sin(t*2.3+ph)*.035+run*sin(t*6+ph)*.03+insp*sin(t*2.4+ph)*.12
  return CFrame.new(x,y,sin(t*1.3+ph*.7)*.05)*CFrame.Angles(0,sin(t*.8+ph)*.35,sin(t*1.2+ph)*.12)
 end,
 NetWingL=function(t,ph,h,pop,s)local run=s and s.Run or 0;return CFrame.Angles(0,(sin(t*(22+run*12)+ph)+.35)*(.7+h*.25),0)end,
 NetWingR=function(t,ph,h,pop,s)local run=s and s.Run or 0;return CFrame.Angles(0,-(sin(t*(22+run*12)+ph)+.35)*(.7+h*.25),0)end,
 -- the butterfly sitting on the rim: wings open and close slowly; now and then (and on a hit) it flutters
 NetPerchL=function(t,ph,h,pop,s)
  local busy=math.max(math.noise(math.floor(t*.6)*.37,ph)>.25 and 1 or 0,h,s and s.Run or 0)
  return CFrame.Angles(0,busy>0 and(sin(t*24)+1)*.55 or(sin(t*2.4+ph)+1)*.5,0)
 end,
 NetPerchR=function(t,ph,h,pop,s)
  local busy=math.max(math.noise(math.floor(t*.6)*.37,ph)>.25 and 1 or 0,h,s and s.Run or 0)
  return CFrame.Angles(0,-(busy>0 and(sin(t*24)+1)*.55 or(sin(t*2.4+ph)+1)*.5),0)
 end,
 NetFirefly=function(t,ph,h,pop,s)
  return CFrame.new(sin(t*.7+ph)*.24+h*sin(t*23+ph)*.06,cos(t*.9+ph*1.4)*.2+sin(t*2.1+ph)*.04,sin(t*1.1+ph)*.08)
 end,
 NetRibbon=function(t,ph,h,pop,s,p)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  local a=p and p.Amp or 0;local k=math.abs(a)
  return CFrame.Angles(k*(sin(t*1.6+ph)*.05-run*(.35+sin(t*9+ph)*.08)+h*sin(t*14)*.22),0,a*(sin(t*1.9+ph)*.06+h*sin(t*17+ph)*.2+run*sin(t*8+ph)*.08+insp*sin(t*3)*.1))
 end,
 -- Laughsaw ("Кирка Смехопила" concept sheet "АНИМАЦИИ"): IDLE the blade turns slowly and the eye
 -- looks round, IN HAND / RUN the blade spins up and the chains and the tag stream back, a HIT (УДАР)
 -- screams the blade round, drops the jaw open and darts the eye, INSPECT (ОСМОТР) revs the blade and
 -- the jaw cackles. s.SawAngle (the blade's turn) and s.Laugh (the jaw) are worked out once a frame
 -- (sawState). p.Amp on a jaw part = its face (1 front, -1 back) so both jaws drop open outwards.
 SawSpin=function(t,ph,h,pop,s)return CFrame.Angles(0,0,-(s and s.SawAngle or t*2.6))end,
 SawJaw=function(t,ph,h,pop,s,p)
  local open=math.max(math.sin(math.min(1,h*1.25)*math.pi*.5)*.95,s and s.Laugh or 0)
  return CFrame.new(0,-open*.17,0)*CFrame.Angles(open*.2*(p and p.Amp~=0 and p.Amp or 1),0,0)
 end,
 SawIris=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local k=math.floor(t*.9+ph)
  return CFrame.new(math.noise(k*.61,1.3+ph)*.1+insp*sin(t*6)*.06+h*sin(t*53)*.035,math.noise(k*.43,4.1+ph)*.08+insp*cos(t*6)*.05,0)
 end,
 SawChain=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(cos(t*1.7+ph)*.05-run*(.5+sin(t*9+ph)*.12)+insp*sin(t*2.6+ph)*.2,0,sin(t*2.1+ph)*.08+run*sin(t*10+ph)*.18+h*sin(t*18+ph)*.55)
 end,
 SawTag=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  return CFrame.Angles(cos(t*1.4+ph)*.06-run*(.55+sin(t*10+ph)*.15)+h*sin(t*14)*.3,sin(t*1.1+ph)*.18,sin(t*1.8+ph)*.09+run*sin(t*8+ph)*.14+h*sin(t*17+ph)*.45)
 end,
 -- LEGO Hand ("LEGO-Рука" concept sheet "АНИМАЦИИ"): the whole hand turns on the wrist like a real
 -- minifig hand (IDLE a slow sway, IN HAND / RUN it wobbles, a HIT clicks it round and back, the DRAW
 -- snaps it in from a half turn, INSPECT ratchets it all the way round in eight clicks); the curled
 -- finger also clacks shut toward the thumb on every strike and twice at the end of the inspect.
 -- s.LegoTwist / s.LegoClench are worked out once a frame (legoState); p.Hang = the finger's knuckle
 -- relative to the wrist joint.
 LegoHand=function(t,ph,h,pop,s)return CFrame.Angles(0,s and s.LegoTwist or 0,0)end,
 LegoFinger=function(t,ph,h,pop,s,p)
  local k=typeof(p and p.Hang)=='Vector3'and p.Hang or Vector3.zero
  return CFrame.Angles(0,s and s.LegoTwist or 0,0)*CFrame.new(k)*CFrame.Angles(0,0,-(s and s.LegoClench or 0))*CFrame.new(-k)
 end,
 -- Pickaxe 67 ("КИРКА 67" concept sheet "АНИМАЦИИ"): IDLE the 6 and the 7 breathe a little apart and now
 -- and then glitch (a jump sideways for a frame or two), IN HAND / RUN (БЕГ) the chain and the "67" tag
 -- swing and stream back, a HIT (УДАР) glitches both digits hard, whips the chain and clicks the chrome dial
 -- round, INSPECT (ОСМОТР) spins the tag on its chain and ratchets the dial four clicks. s.Six6 / s.Six7
 -- (glitch offsets), s.SixDial (the dial's turn) and s.SixSpin (the tag's) are worked out once a frame
 -- (sixState); p.Hang = the tag's centre from the chain's eye.
 SixDigit6=function(t,ph,h,pop,s)
  local o=s and s.Six6 or Vector3.zero
  return CFrame.new(o.X-sin(t*2.6)*.012,o.Y+sin(t*2.6)*.025+h*.06,0)
 end,
 SixDigit7=function(t,ph,h,pop,s)
  local o=s and s.Six7 or Vector3.zero
  return CFrame.new(o.X+sin(t*2.6)*.012,o.Y-sin(t*2.6)*.025+h*.06,0)
 end,
 SixChain=function(t,ph,h,pop,s)return sixSwing(t,h,s)end,
 SixTag=function(t,ph,h,pop,s,p)
  local k=typeof(p and p.Hang)=='Vector3'and p.Hang or Vector3.zero
  local spin=(s and s.SixSpin or 0)+sin(t*1.1)*.25+h*sin(t*13)*.5
  return sixSwing(t,h,s)*CFrame.new(k)*CFrame.Angles(0,spin,0)*CFrame.new(-k)
 end,
 SixDial=function(t,ph,h,pop,s)return CFrame.Angles(0,s and s.SixDial or 0,0)end,
 -- Rotten Slime Slug ("Кирка Слизень-Гнилушка" concept sheet "Анимации"): IDLE (Ожидание) the slug breathes, the
 -- stalks sway, the eyes look round, the sleepy lid blinks, the tongue hangs and swings, live drops stretch and
 -- fall; IN HAND / RUN (Бег) the slug twitches and hops, the stalks and the tongue flap; a HIT (Удар) squashes
 -- the body and shoots the stalk eyes out on slime threads (MiningModels: a Beam from stalk to eye) and lets
 -- them wobble back; INSPECT (Осмотр) the big eye twitches nervously and the slime pulses.
 -- p.Amp on a stalk part = its share of the throw (segments .2 .. .6, the eye 1); pop = the stalk's direction.
 SlugBody=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  local hop=run*math.abs(sin(t*8.5))*.1
  return CFrame.new(sin(t*.9)*.012+run*sin(t*17)*.02+h*sin(t*29)*.04,sin(t*1.4)*.035+hop-h*.09*cos(math.min(1,h)*math.pi*.5)+insp*sin(t*6)*.035,0)
   *CFrame.Angles(run*sin(t*8.5)*.03,0,sin(t*1.1)*.02+run*sin(t*8.5+1)*.05+h*sin(t*23)*.06)
 end,
 SlugBigEye=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local j=twitch(t,ph)*.035+h*sin(t*47)*.05+insp*twitch(t*3.3,ph+2)*.09
  return CFrame.new(j,j*.6+insp*sin(t*31)*.012,0)
 end,
 SlugLook=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local k=math.floor(t*.75+ph)
  return CFrame.new(math.noise(k*.71,ph+.3)*.07+insp*sin(t*9+ph)*.04+h*sin(t*53)*.02,math.noise(k*.37,ph+3.1)*.05+insp*cos(t*9+ph)*.03,0)
 end,
 SlugLid=function(t,ph,h,pop,s)
  local b=math.max(blink(t*.8,ph),h>.6 and .8 or 0)
  return CFrame.new(0,-b*.13+sin(t*.6)*.015,0)
 end,
 SlugTongue=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(sin(t*1.6+ph)*.08+run*(.3+sin(t*9)*.15)+h*sin(t*20)*.45+insp*sin(t*7)*.2,0,sin(t*1.2)*.1+run*sin(t*8)*.12+insp*sin(t*5)*.15)
 end,
 SlugStalk=function(t,ph,h,pop,s,p)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  local w=h*sin(t*31+ph)*.22 -- the eyes wobble on their threads as they spring back
  local r=CFrame.Angles(sin(t*1.3+ph)*.16+run*sin(t*9+ph)*.18+w,0,sin(t*1.1+ph*1.7)*.2+run*sin(t*8+ph)*.2-w)
  local amp=p and p.Amp or 0
  if typeof(pop)=='Vector3'and amp>0 then return CFrame.new(pop*amp*(h*1.35+insp*.18))*r end
  return r
 end,
 -- Toothy Alarm Clock ("Зубастый Будильник" concept sheet "АНИМАЦИИ"): IDLE the clock breathes and ticks, the
 -- eyes look round and blink, the knife hands creep, the key and the gear turn, the watch sways, now and then it
 -- rattles; IN HAND / RUN (БЕГ) the head bobs, the jaw chatters, the bells jingle, the watch swings back, the hands
 -- race; a HIT (УДАР) rings it: the head rattles, the bells shake, the striker hammers between them, the eyes pop
 -- out and the jaw bites; INSPECT (ОСМОТР) winds the key with a whirr, spins the hands, then the clock RINGS and
 -- screams with the jaw wide open. s.Ring (0..1), s.AlarmMin / s.AlarmHour (hand angles), s.AlarmKey, s.Tick
 -- and s.Scream are worked out once a frame (alarmState). Every head part rides AlarmBody (a translation only,
 -- so it stacks with any joint); p.Amp on a knife hand = 1 the minute hand, 0 the hour hand.
 AlarmBody=function(t,ph,h,pop,s)
  local ring,run=s and s.Ring or 0,s and s.Run or 0
  return CFrame.new(sin(t*61)*.035*ring+sin(t*.9)*.006,sin(t*1.6)*.018+sin(t*53)*.026*ring+run*math.abs(sin(t*8.5))*.05,sin(t*47)*.02*ring)
 end,
 AlarmBell=function(t,ph,h,pop,s)
  local ring,run=s and s.Ring or 0,s and s.Run or 0
  return CFrame.Angles(0,0,sin(t*1.3+ph)*.02+run*sin(t*9+ph)*.06+sin(t*47+ph)*.13*ring)
 end,
 AlarmHammer=function(t,ph,h,pop,s)
  local ring=s and s.Ring or 0
  return CFrame.Angles(0,0,sin(t*1.1)*.05+sin(t*44)*.55*ring)
 end,
 AlarmJaw=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  local bite=sin(math.sqrt(h)*math.pi)*.5 -- a strike: wide open, then it snaps shut
  local chatter=.02+math.max(0,sin(t*2.3))*.03+run*math.abs(sin(t*14))*.1
  return CFrame.Angles(math.max(bite,chatter,s and s.Scream or 0),0,0)
 end,
 AlarmHand=function(t,ph,h,pop,s,p)
  return CFrame.Angles(0,0,-((p and p.Amp==1)and(s and s.AlarmMin or 0)or(s and s.AlarmHour or 0)))
 end,
 AlarmLook=function(t,ph,h,pop,s)
  local ring=s and s.Ring or 0
  local k=math.floor(t*.8+ph)
  return CFrame.new(math.noise(k*.71,ph+.3)*.08+cos(t*21+ph)*.05*ring,math.noise(k*.37,ph+3.1)*.06+sin(t*21+ph)*.05*ring,0)
 end,
 AlarmPop=function(t,ph,h,pop,s,p)
  if typeof(pop)~='Vector3'then return CFrame.identity end
  local insp=s and s.Insp or 0
  return CFrame.new(pop*(h*.42+(s and s.Ring or 0)*.06+insp*.05*(sin(t*7)+1))) -- one phase for the white and the iris
 end,
 AlarmLid=function(t,ph,h,pop,s)
  local b=(s and s.Ring or 0)>.3 and 0 or blink(t*.9,ph) -- a ringing clock never blinks
  return CFrame.new(0,-b*.3,0)
 end,
 AlarmKey=function(t,ph,h,pop,s)return CFrame.Angles(0,0,s and s.AlarmKey or 0)end,
 AlarmGear=function(t,ph,h,pop,s)return CFrame.Angles(0,0,-(s and s.AlarmKey or 0)*.6)end,
 AlarmTick=function(t,ph,h,pop,s)return CFrame.Angles(0,0,-(s and s.Tick or 0)*math.pi/30)end,
 AlarmWatch=function(t,ph,h,pop,s)
  local run,ring=s and s.Run or 0,s and s.Ring or 0
  return CFrame.Angles(sin(t*1.9)*.05-run*(.4+sin(t*9)*.1),0,sin(t*2.2)*.12+run*sin(t*10)*.15+h*sin(t*15)*.5+ring*sin(t*31)*.08)
 end,
 AlarmWatchHand=function(t,ph,h,pop,s,p)
  local k=typeof(p and p.Hang)=='Vector3'and p.Hang or Vector3.zero
  return CFrame.new(k)*CFrame.Angles(0,0,-(s and s.AlarmMin or 0)*.5)*CFrame.new(-k)
 end,
 -- Zombie-Frankenstein ("Кирка Зомби-Франкенштейн" concept sheet "АНИМАЦИИ"): IDLE the segments twitch like a nervous
 -- tic, the living eye rolls and blinks, the machine iris scans, the coil hums, the vial sways; IN HAND (Trail) the
 -- stitched parts swing a little; a HIT (Удар) is an electric surge and a convulsive jerk: the head shudders, the jaw
 -- bites, the blade and the claw clench, the coil bounces; RUN (Бег) the sewn-on pieces dangle: the vial and the charm
 -- swing back, the wires flap, the jaw chatters; INSPECT (Осмотр) the eye scans while lightning runs along the seams
 -- (zombieLive), then a growl. Now and then the whole model has a rare LIVING SPASM. s.Spasm (0..1), s.Growl and
 -- s.ZBolt (the neck bolt's turn) are worked out once a frame (zombieState). Every head part rides ZombieHead (a
 -- translation only, so it stacks with any joint).
 ZombieHead=function(t,ph,h,pop,s)
  local sp,run=s and s.Spasm or 0,s and s.Run or 0
  return CFrame.new(math.noise(t*23,1.3)*.07*sp+h*math.noise(t*31,2.1)*.08+sin(t*.8)*.006,
   sin(t*1.4)*.012+run*math.abs(sin(t*8.5))*.045+math.noise(t*27,4.4)*.05*sp+h*.04,math.noise(t*25,7.7)*.05*sp)
 end,
 ZombieJaw=function(t,ph,h,pop,s)
  local run,sp,growl=s and s.Run or 0,s and s.Spasm or 0,s and s.Growl or 0
  local bite=sin(math.sqrt(h)*math.pi)*.42
  local chew=.03+math.max(0,sin(t*1.7))*.05+run*math.abs(sin(t*13))*.12+sp*math.abs(sin(t*29))*.22
  return CFrame.Angles(math.max(bite,chew,growl*(.4+.06*sin(t*31))),0,0)
 end,
 ZombieEyeL=function(t,ph,h,pop,s)
  local sp=s and s.Spasm or 0
  local k=math.floor(t*.7+ph)
  return CFrame.new(math.noise(k*.71,ph+.3)*.07+cos(t*19)*.04*sp,math.noise(k*.37,ph+3.1)*.05+sin(t*19)*.04*sp+h*.03,0)
 end,
 ZombieLid=function(t,ph,h,pop,s)
  local b=((s and s.Spasm or 0)>.3 or h>.4)and -.4 or blink(t*.8,ph) -- a spasm or a strike: eye wide open
  return CFrame.new(0,-b*.2,0)
 end,
 ZombieEyeR=function(t,ph,h,pop,s)
  local insp=s and s.Insp or 0
  local k=math.floor(t*.55+ph)
  local x=math.noise(k*.53,ph)*.06+insp*sin(t*3.4)*.05
  local y=math.noise(k*.29,ph+5)*.04+insp*cos(t*2.3)*.025
  return CFrame.new(x,y,h*.04)
 end,
 ZombieBlade=function(t,ph,h,pop,s)
  local sp,run=s and s.Spasm or 0,s and s.Run or 0
  return CFrame.Angles(math.noise(t*21,3.3)*.05*sp,0,twitch(t*.7,ph+1)*.035+sin(t*1.3)*.012-h*sin(t*24)*.09+math.noise(t*19,9.1)*.09*sp+run*sin(t*9)*.025)
 end,
 ZombieClaw=function(t,ph,h,pop,s)
  local sp,run=s and s.Spasm or 0,s and s.Run or 0
  return CFrame.Angles(0,0,-sin(math.sqrt(h)*math.pi)*.32+twitch(t*.8,ph+4)*.05+math.noise(t*20,5.5)*.12*sp+run*sin(t*9+1)*.05)
 end,
 ZombieCoil=function(t,ph,h,pop,s,p)
  local sp=s and s.Spasm or 0
  local a=p and p.Amp or 0
  return CFrame.new(0,a*(sin(t*5.5)*.025+h*sin(t*34)*.1+sp*sin(t*41)*.07),0)
 end,
 ZombieBolt=function(t,ph,h,pop,s)return CFrame.Angles(s and s.ZBolt or 0,0,0)end,
 ZombieTic=function(t,ph,h,pop,s)
  local sp=s and s.Spasm or 0
  local j=twitch(t*1.1,ph)
  return CFrame.new(j*.022+math.noise(t*26,ph)*.035*sp+h*math.noise(t*30,ph+1)*.03,0,math.noise(t*24,ph+2)*.03*sp)
 end,
 ZombieWire=function(t,ph,h,pop,s)
  local run,sp=s and s.Run or 0,s and s.Spasm or 0
  return CFrame.Angles(sin(t*1.6+ph)*.04+run*sin(t*10+ph)*.14,0,sin(t*2.1+ph)*.05+h*sin(t*26)*.2+sp*sin(t*33+ph)*.12)
 end,
 ZombieJar=function(t,ph,h,pop,s)
  local run,sp,insp=s and s.Run or 0,s and s.Spasm or 0,s and s.Insp or 0
  return CFrame.Angles(sin(t*1.7)*.05-run*(.45+sin(t*9)*.12)+insp*sin(t*2.4)*.1,0,sin(t*2.1)*.1+run*sin(t*10)*.15+h*sin(t*14)*.5+sp*sin(t*23)*.15)
 end,
 -- Clown Chronomord ("Клоун-Хрономорд" concept sheet "АНИМАЦИИ"): IDLE the clock hands creep BACKWARDS, the gears turn,
 -- the eyes roll each their own way and now and then it giggles (the head bobs, the jaw chatters, the bells jingle); IN
 -- HAND the hat lobes, bells, tongue and pocket watches sway; a HIT lashes the tongue out, the eyes bulge, the jaw bites
 -- and the hands whirl; RUN the hat, the tongue and the watches stream back and the hands race; INSPECT the clock rewinds
 -- (the hands spin backwards, the eyes go wild), it is turned round, then it LAUGHS. s.Laugh (0..1), s.Pop (eyes out),
 -- s.ChMin / s.ChHour / s.ChGear (the hand and gear angles) are worked out once a frame (chronoState). Every head part
 -- rides ClownHead (a translation only, so it stacks with any joint).
 ClownHead=function(t,ph,h,pop,s)
  local lg,run=s and s.Laugh or 0,s and s.Run or 0
  return CFrame.new(sin(t*1.1)*.01+lg*sin(t*23)*.025,sin(t*1.6)*.018+run*math.abs(sin(t*8.5))*.045+h*.05+lg*math.abs(sin(t*21))*.05,0)
 end,
 ClownJaw=function(t,ph,h,pop,s)
  local lg,run=s and s.Laugh or 0,s and s.Run or 0
  local bite=sin(math.sqrt(h)*math.pi)*.42
  return CFrame.Angles(math.max(.03+(sin(t*1.3)+1)*.025,bite,lg*(.18+.22*math.abs(sin(t*22))),run*math.abs(sin(t*12))*.12),0,0)
 end,
 ClownEyePop=function(t,ph,h,pop,s)
  local lg=s and s.Laugh or 0
  return CFrame.new(0,0,math.max(sin(math.sqrt(h)*math.pi)*.2,(s and s.Pop or 0)*.22)+lg*math.abs(sin(t*17+ph))*.05)
 end,
 ClownEye=function(t,ph,h,pop,s)
  local insp,lg=s and s.Insp or 0,s and s.Laugh or 0
  local k=math.floor(t*1.3+ph*3)
  return CFrame.Angles(math.noise(k*.61,ph+.3)*.55+insp*sin(t*9+ph)*.35+lg*sin(t*31+ph)*.15,math.noise(k*.37,ph+2.2)*.7+insp*cos(t*7+ph)*.45,0)
 end,
 ClownTongue=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local lg,run,insp=s and s.Laugh or 0,s and s.Run or 0,s and s.Insp or 0
  local lash=sin(math.sqrt(h)*math.pi)
  return CFrame.Angles(a*(sin(t*1.9)*.06-lash*.35+run*sin(t*9)*.15+lg*sin(t*15)*.1),0,a*(sin(t*1.5+.6)*.1+h*sin(t*19)*.3+lg*sin(t*13)*.14+insp*sin(t*4)*.1+run*sin(t*10+1)*.1))
 end,
 ClownHat=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local lg,run=s and s.Laugh or 0,s and s.Run or 0
  return CFrame.Angles(sin(t*1.7+ph)*.03-run*.12+run*sin(t*9+ph)*.05,0,a*(sin(t*2.1+ph)*.045+run*sin(t*10)*.08+h*sin(t*17)*.22+lg*sin(t*19)*.09))
 end,
 ClownBell=function(t,ph,h,pop,s,p)
  local k=typeof(p and p.Hang)=='Vector3'and p.Hang or Vector3.zero
  local lg,run=s and s.Laugh or 0,s and s.Run or 0
  return CFrame.new(k)*CFrame.Angles(sin(t*2.7+ph)*.1-run*.35+run*sin(t*11)*.1,0,sin(t*3.2+ph)*.16+h*sin(t*24+ph)*.55+lg*sin(t*27+ph)*.3)*CFrame.new(-k)
 end,
 ClownMinute=function(t,ph,h,pop,s)return CFrame.Angles(0,0,s and s.ChMin or 0)end,
 ClownHour=function(t,ph,h,pop,s)return CFrame.Angles(0,0,s and s.ChHour or 0)end,
 ClownGear=function(t,ph,h,pop,s,p)return CFrame.Angles(0,0,(s and s.ChGear or 0)*(p and p.Amp or 1))end,
 ClownWatch=function(t,ph,h,pop,s)
  local run,insp,lg=s and s.Run or 0,s and s.Insp or 0,s and s.Laugh or 0
  return CFrame.Angles(sin(t*1.6+ph)*.05-run*(.45+sin(t*9+ph)*.12)+insp*sin(t*2.4+ph)*.1,0,sin(t*2+ph)*.12+run*sin(t*10+ph)*.15+h*sin(t*14+ph)*.5+lg*sin(t*18+ph)*.15)
 end,
 ClownWatchHand=function(t,ph,h,pop,s,p)
  local k=typeof(p and p.Hang)=='Vector3'and p.Hang or Vector3.zero
  return CFrame.new(k)*CFrame.Angles(0,0,(s and s.ChMin or 0)*1.7*(p and p.Amp or 1))*CFrame.new(-k)
 end,
 -- Nasty Octopus ("Кирка Мерзкий Спрут" concept sheet "ANIMATION PREVIEW"): IDLE the tentacles slowly wiggle and drip; IN HAND
 -- the eye looks around curiously; HIT (MINE) the tentacles spread open and the eye bulges; RUN the tentacles sway harder with
 -- the movement and stream back; STAND a slow, wandering creepy stare (now and then it stares right at the camera). s.EyeX /
 -- s.EyeY (where the eye looks), s.Bulge (the eye out), s.Spread (tentacles open: the draw, the inspect's lash) and s.SacPump
 -- are worked out once a frame (octoState). Every head part rides OctoMantle (a translation only, so it stacks with any joint);
 -- OctoArm turns a free tentacle round its root, more along it (p.Amp = share along), opening round PickPop (pop).
 OctoMantle=function(t,ph,h,pop,s)
  local run,sp=s and s.Run or 0,s and s.Spread or 0
  return CFrame.new(sin(t*.9)*.008,sin(t*1.5)*.028+run*math.abs(sin(t*8.5))*.04+h*.05+sp*.03,0)
 end,
 OctoEye=function(t,ph,h,pop,s)
  return CFrame.new(0,0,s and s.Bulge or 0)*CFrame.Angles(s and s.EyeX or 0,s and s.EyeY or 0,0)
 end,
 OctoArm=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local run,insp,sp=s and s.Run or 0,s and s.Insp or 0,s and s.Spread or 0
  local axis=(typeof(pop)=='Vector3'and pop.Magnitude>.01)and pop.Unit or Vector3.zAxis
  local open=math.max(sin(math.sqrt(h)*math.pi),sp)*.6
  local wig=sin(t*1.7+ph-a*2.4)*.1+sin(t*.9+ph*2)*.05
  local sway=run*sin(t*9+ph-a*2)*.22
  return CFrame.fromAxisAngle(axis,a*(open+wig+sway+insp*sin(t*3.4+ph)*.12))
   *CFrame.Angles(a*(sin(t*1.3+ph*1.7)*.06-run*.22+run*sin(t*8+ph)*.1),0,0)
 end,
 OctoWrap=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local run=s and s.Run or 0
  return CFrame.Angles(0,sin(t*1.2+ph-a*5)*.08+h*sin(t*20)*.08+run*sin(t*7-a*6)*.06,0)
 end,
 OctoCoil=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local run=s and s.Run or 0
  local axis=(typeof(pop)=='Vector3'and pop.Magnitude>.01)and pop.Unit or Vector3.xAxis
  return CFrame.fromAxisAngle(axis,a*a*(sin(t*1.6+ph)*.25+h*sin(t*18)*.4+run*sin(t*9)*.3))
 end,
 OctoSac=function(t,ph,h,pop,s)
  local pulse=(sin(t*2.2)+1)*.5
  return CFrame.new(0,-pulse*.02-h*.03,-pulse*.03-(s and s.SacPump or 0)*.08)
 end,
 -- Hand of Fate ("Кирка Рука Судьбы" concept sheet "АНИМАЦИИ"): IDLE the fingers creep and flex in a slow wave and the eye
 -- looks round and blinks; IN HAND quick glances, now and then a twitch of the fingers; УДАР the claws SQUEEZE shut on the
 -- ore and the eye bulges; БЕГ the fingers flail and the palm bobs; ОСМОТР the hand opens wide, turns round, then closes into
 -- a fist one finger after another while the eye glares. s.EyeX / s.EyeY (where the iris sits), s.Bulge, s.Blink, s.Open
 -- (fingers spread), s.FistAt / s.FistK (the fist wave) and s.Twitch are worked out once a frame (fateState). Every head
 -- part rides FatePalm (a translation only, so it stacks with any joint); FateFinger turns a finger round its root, more
 -- along it (p.Amp = share along), curling forward round PickPop (pop).
 FatePalm=function(t,ph,h,pop,s)
  local run=s and s.Run or 0
  return CFrame.new(sin(t*.8)*.008,sin(t*1.3)*.022+run*math.abs(sin(t*8.5))*.035+h*.04,0)
 end,
 FateFinger=function(t,ph,h,pop,s,p)
  local a=p and p.Amp or 0
  local axis=(typeof(pop)=='Vector3'and pop.Magnitude>.01)and pop.Unit or Vector3.xAxis
  local run=s and s.Run or 0
  local creep=(sin(t*1.25+ph-a*2.2)+1)*.06+sin(t*.6+ph*1.7)*.035
  local twitch=(s and s.Twitch or 0)*sin(t*31+ph*3)*.18
  local flail=run*(sin(t*9+ph*1.3-a*2)*.16+.12)
  local squeeze=sin(math.sqrt(h)*math.pi)*.95
  local fist=0
  if s and s.FistAt then fist=math.clamp((t-s.FistAt-ph*.05)/.12,0,1)*(s.FistK or 1)end
  return CFrame.fromAxisAngle(axis,a*(creep+twitch+flail+math.max(squeeze,fist*1.15)-(s and s.Open or 0)*.55))
 end,
 FateEye=function(t,ph,h,pop,s)
  return CFrame.new(s and s.EyeX or 0,s and s.EyeY or 0,s and s.Bulge or 0)
 end,
 FateLid=function(t,ph,h,pop,s,p)
  local b=s and s.Blink or 0
  return CFrame.new(0,-(p and p.Amp or 0)*b,b*.22)
 end,
 FateTag=function(t,ph,h,pop,s)
  local run,insp=s and s.Run or 0,s and s.Insp or 0
  return CFrame.Angles(sin(t*1.9+ph)*.06-run*(.5+sin(t*9)*.12)+insp*sin(t*2.6)*.15,0,sin(t*2.3+ph)*.1+h*sin(t*17)*.5+run*sin(t*10)*.18)
 end,
 -- Mythic gems circling the head (MiningModels.polish); a strike flings them round faster.
 Orbit=function(t,ph,h)return CFrame.Angles(0,t*2.2+h*4,0)end,
}

-- THEMES (hit / crit effects and trail colours) -------------------------------------------------
local THEMES={
 Wood={C(176,124,74),C(214,170,110),C(120,84,50)},
 Butterfly={C(150,215,255),C(255,236,140),C(255,160,225),C(170,255,200),C(196,160,255)},
 Brick={C(255,200,24),C(222,32,36),C(28,98,214),C(242,242,236)}, -- LEGO Hand: the sheet's ПАЛИТРА
 Digits={C(235,40,52),C(250,250,250),C(30,30,34)}, -- Pickaxe 67: the sheet's ПАЛИТРА (red, black, white)
 Gummy={C(255,92,190),C(170,255,90),C(255,236,90)},
 Slime={C(168,226,52),C(222,238,62),C(120,170,40),C(131,91,81)}, -- Rotten Slime Slug: the sheet's ПАЛИТРА (lime, acid, deep, rot)
 Alarm={C(232,40,40),C(246,196,82),C(244,226,206),C(128,126,130)}, -- Toothy Alarm Clock: the sheet's ПАЛИТРА (red, gold, cream, grey)
 Rainbow={C(255,120,200),C(255,230,110),C(130,210,255),C(190,140,255)},
 Zombie={C(70,160,255),C(196,236,255),C(168,232,40),C(166,84,44),C(232,220,186)}, -- Zombie-Frankenstein: the sheet's ПАЛИТРА (dead blue, spark white, rotten green, rust, bone)
 Clown={C(226,40,48),C(246,206,104),C(250,236,206),C(60,120,220),C(222,168,58)}, -- Clown Chronomord: the sheet's ПАЛИТРА (red, gold, cream, blue, brass)
 Ink={C(80,150,245),C(140,84,232),C(232,112,230),C(255,206,48),C(30,16,48)}, -- Nasty Octopus: the sheet's COLOR PALETTE (blue, violet, pink, yellow) + ink
 Fate={C(155,47,214),C(96,24,150),C(236,170,255),C(215,181,186),C(242,223,191)}, -- Hand of Fate: the sheet's ПАЛИТРА (purple, deep violet, glow, flesh pink, bone cream)
 Saw={C(255,36,40),C(255,196,120),C(240,226,196),C(150,10,16)},
 Anime={C(186,70,255),C(255,50,110),C(255,196,252),C(235,30,50)},
 Claws={C(255,40,64),C(170,70,255),C(255,232,238),C(255,170,90)},
 TV={C(160,255,96),C(214,255,170),C(96,200,70),C(255,80,220),C(90,220,255)},
}
PickFX.Colors=THEMES
-- Ponycorn trails: pink -> yellow in the hand, the full pastel rainbow while running.
local PONY_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,120,200)),ColorSequenceKeypoint.new(.55,C(255,200,140)),ColorSequenceKeypoint.new(1,C(255,240,120))})
local PONY_RAINBOW=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,120,200)),ColorSequenceKeypoint.new(.25,C(255,236,120)),
 ColorSequenceKeypoint.new(.5,C(140,240,170)),ColorSequenceKeypoint.new(.75,C(120,200,255)),ColorSequenceKeypoint.new(1,C(190,140,255))})
local PONY_HUES={C(255,120,200),C(255,190,110),C(255,240,120),C(140,240,170),C(120,200,255),C(190,140,255)}
-- Scarlet Anime Scythe trails: violet -> pink in the hand, a longer scarlet -> violet streak while running.
local SCYTHE_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,170,250)),ColorSequenceKeypoint.new(.45,C(196,80,255)),ColorSequenceKeypoint.new(1,C(150,40,230))})
local SCYTHE_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,90,150)),ColorSequenceKeypoint.new(.5,C(235,40,70)),ColorSequenceKeypoint.new(1,C(170,60,255))})
local SCYTHE_GLYPHS={'斬','魂','刃','鬼','月','冥'}
-- Laughsaw (concept "СЛЕД УДАРА" / "БЕГ"): a hot white -> scarlet -> dark red streak in the hand, a longer
-- one while running with sparks streaming off the blade.
local SAW_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,220,200)),ColorSequenceKeypoint.new(.4,C(255,40,40)),ColorSequenceKeypoint.new(1,C(140,8,14))})
local SAW_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,120,80)),ColorSequenceKeypoint.new(.5,C(235,24,30)),ColorSequenceKeypoint.new(1,C(110,6,10))})
local SAW_SPARK=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,240,200)),ColorSequenceKeypoint.new(.4,C(255,150,60)),ColorSequenceKeypoint.new(1,C(255,30,30))})
local SAW_LAUGH={'HA','HA!','HA-HA','ХА','ХА-ХА'}
-- Twin Claws: the right gauntlet's scarlet, the left one's violet (MiningConfig Visual.Accent / Trim).
local CLAW_RED,CLAW_VIOLET,CLAW_HOT=C(255,40,64),C(170,70,255),C(255,236,240)
local CLAW_RUNE={[1]='右',[-1]='左'}
-- Butterfly Catcher: the glowing pastel butterflies, the swing trail (white -> sky -> pink) and the
-- longer running trail (gold -> sky -> lilac) with stars and butterflies ("СЛЕД ПРИ БЕГЕ").
-- Rotation turning +X into dir (flat cylinders lying on a surface).
local function alignX(dir)
 local d=dir.Unit;local x=Vector3.xAxis;local dot=math.clamp(x:Dot(d),-1,1)
 if dot>.9999 then return CFrame.identity end
 if dot<-.9999 then return CFrame.Angles(0,math.pi,0)end
 return CFrame.fromAxisAngle(x:Cross(d).Unit,math.acos(dot))
end
local NET_WINGS={C(130,206,255),C(255,150,222),C(255,226,118),C(150,248,200),C(196,160,255)}
local NET_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,255,255)),ColorSequenceKeypoint.new(.45,C(150,215,255)),ColorSequenceKeypoint.new(1,C(255,160,225))})
-- LEGO Hand (concept "УДАР" / "БЕГ"): a golden arc (white-hot -> yellow -> orange) in the hand, a longer
-- golden streak while running with little bricks and sparkles left behind ("СЛЕД ПРИ БЕГЕ").
local LEGO_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,246,200)),ColorSequenceKeypoint.new(.4,C(255,206,40)),ColorSequenceKeypoint.new(1,C(255,128,20))})
local LEGO_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,236,140)),ColorSequenceKeypoint.new(.55,C(255,180,30)),ColorSequenceKeypoint.new(1,C(230,90,20))})
local LEGO_STARS={C(255,226,80),C(255,255,255),C(110,170,255),C(255,200,24)}
local LEGO_POP={'click','clack','клац','щёлк'}
-- Pickaxe 67 (concept "УДАР" / "СЛЕД ПРИ БЕГЕ"): a white-hot -> red -> dark red arc in the hand, a longer red
-- -> pink streak while running with little "67"s left behind; the glitch copies are red and cyan.
local SIX_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,236,236)),ColorSequenceKeypoint.new(.4,C(255,40,52)),ColorSequenceKeypoint.new(1,C(130,8,16))})
local SIX_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,120,130)),ColorSequenceKeypoint.new(.5,C(235,30,44)),ColorSequenceKeypoint.new(1,C(90,6,12))})
local SIX_DIGITS={'6','7','67','6','7','67'}
local SIX_COLORS={C(255,40,52),C(255,255,255),C(255,120,130)}
-- Rotten Slime Slug (concept "В руке (Trail)" / "Бег"): an acid -> lime -> deep olive slimy streak in the hand, a longer
-- one while running; drops and puddles left behind (slugLive).
local SLUG_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(236,248,120)),ColorSequenceKeypoint.new(.45,C(168,226,52)),ColorSequenceKeypoint.new(1,C(96,140,30))})
local SLUG_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(222,238,62)),ColorSequenceKeypoint.new(.6,C(140,200,40)),ColorSequenceKeypoint.new(1,C(110,90,60))})
local SLUG_ROT={C(131,91,81),C(66,50,44),C(170,108,68),C(112,103,94)}
-- Toothy Alarm Clock (concept "СЛЕД УДАРА" / "БЕГ"): a white-hot -> scarlet -> dark red streak in the hand, a longer
-- red -> orange one while running; little clocks and gears left behind (alarmLive).
local ALARM_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,226,214)),ColorSequenceKeypoint.new(.4,C(240,36,36)),ColorSequenceKeypoint.new(1,C(120,8,12))})
local ALARM_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,150,90)),ColorSequenceKeypoint.new(.5,C(232,36,36)),ColorSequenceKeypoint.new(1,C(100,6,10))})
local ALARM_RING={'DRRRING!','ДЗЫНЬ!','RRRING!'}
-- Zombie-Frankenstein (concept "В руке (Trail)" / "Бег"): a blue-white electric streak fading into rotten green in the
-- hand, a longer slimy green one while running; slime drops and sparks left behind (zombieLive).
local ZOMBIE_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(220,244,255)),ColorSequenceKeypoint.new(.4,C(70,160,255)),ColorSequenceKeypoint.new(1,C(150,220,40))})
local ZOMBIE_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(214,255,96)),ColorSequenceKeypoint.new(.55,C(150,210,40)),ColorSequenceKeypoint.new(1,C(70,110,40))})
local ZOMBIE_ZAP={'ZZT!','ZZT!!','ЗЗТ!','bzzt'}
-- Clown Chronomord (concept "УДАР" / "СЛЕД ПРИ БЕГЕ"): a white-hot -> scarlet -> dark red arc in the hand, a longer red
-- streak while running with little pocket watches left behind (chronoLive).
local CHRONO_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,236,220)),ColorSequenceKeypoint.new(.4,C(236,40,48)),ColorSequenceKeypoint.new(1,C(120,10,18))})
local CHRONO_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,140,110)),ColorSequenceKeypoint.new(.5,C(226,36,44)),ColorSequenceKeypoint.new(1,C(110,8,14))})
local CHRONO_LAUGH={'HA-HA-HA!','ХА-ХА-ХА!','HA-HA!'}
-- Nasty Octopus (concept "TENTACLE LASH" / RUN): a wet white-cyan -> blue -> violet lash in the hand, a longer blue -> violet ->
-- pink streak while running with drops and little puddles left behind (octoLive); water, toxic bubbles, the crit's word.
local OCTO_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(226,246,255)),ColorSequenceKeypoint.new(.4,C(80,150,245)),ColorSequenceKeypoint.new(1,C(140,84,232))})
local OCTO_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(120,190,255)),ColorSequenceKeypoint.new(.5,C(124,72,220)),ColorSequenceKeypoint.new(1,C(232,112,230))})
local OCTO_WATER={C(150,214,255),C(204,238,255),C(96,170,250)}
local OCTO_TOXIC={C(150,240,80),C(110,214,60),C(196,255,120)}
local OCTO_SPLOOSH={'SPLOOSH!','ШЛЁП!','SPLASH!'}
-- Hand of Fate (concept "УДАР" / "БЕГ"): a white-pink -> purple -> deep violet arc in the hand, a longer glow -> purple ->
-- mauve streak while running with glowing cubes and slime drops left behind (fateLive).
local FATE_TRAIL=ColorSequence.new({ColorSequenceKeypoint.new(0,C(250,220,255)),ColorSequenceKeypoint.new(.4,C(176,64,236)),ColorSequenceKeypoint.new(1,C(96,24,150))})
local FATE_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(236,170,255)),ColorSequenceKeypoint.new(.5,C(155,47,214)),ColorSequenceKeypoint.new(1,C(78,64,72))})
local NET_RUN=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,240,160)),ColorSequenceKeypoint.new(.5,C(150,215,255)),ColorSequenceKeypoint.new(1,C(196,160,255))})

function PickFX.new(ctx)
 local self:any={}
 local player=ctx.Player
 local FX=ctx.FX
 local folder=FX.Folder
 local function low()return FX.Low()end
 local function n(x)return math.max(1,math.floor(x*(low()and .45 or 1)+.5))end
 local function pal(theme)return THEMES[theme]or THEMES.Wood end
 local function pick(list)return list[math.random(1,#list)]end

 -- PRIMITIVE EFFECTS ----------------------------------------------------------------------------
 -- Text particles (digits, hearts, stars, clocks): pooled BillboardGuis that fly out and fade.
 local glyphPool={}
 local function glyph(pos,text,color,size,dir,life)
  local g=table.remove(glyphPool)
  if not g then
   g=Instance.new('BillboardGui');g.Name='PickGlyph';g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=110
   g:SetAttribute('NoTranslate',true)
   local l=Instance.new('TextLabel');l.Name='T';l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true
   l.FontFace=Font.fromEnum(Enum.Font.FredokaOne);l.TextStrokeTransparency=0;l.TextStrokeColor3=C(20,24,40)
   l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
  end
  local l=g:FindFirstChild('T')::TextLabel
  size=size or 34
  g.Size=UDim2.fromOffset(size*math.max(1,#text*.7),size);g.StudsOffsetWorldSpace=Vector3.zero
  l.Text=text;l.TextColor3=color;l.TextTransparency=0;l.TextStrokeTransparency=0;l.Rotation=math.random(-25,25)
  local anchor=Instance.new('Attachment');anchor.Parent=workspace.Terrain;anchor.WorldPosition=pos
  g.Adornee=anchor;g.Parent=folder
  life=life or .8
  dir=dir or Vector3.new(math.random()-.5,math.random()*.8+.4,math.random()-.5)
  TweenService:Create(g,TweenInfo.new(life,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{StudsOffsetWorldSpace=dir*(2.5+math.random()*2)}):Play()
  TweenService:Create(l,TweenInfo.new(life*.45,Enum.EasingStyle.Linear,Enum.EasingDirection.In,0,false,life*.55),{TextTransparency=1,TextStrokeTransparency=1,Rotation=l.Rotation+math.random(-60,60)}):Play()
  task.delay(life+.05,function()
   anchor:Destroy();g.Adornee=nil;g.Parent=nil
   if #glyphPool<40 then table.insert(glyphPool,g)else g:Destroy()end
  end)
 end
 self.Glyph=glyph
 -- Glitch text (Pickaxe 67, concept "ГЛИТЧ-ЭФФЕКТ" / "УДАРНЫЙ ЭФФЕКТ"): a white italic "67" with a red and a
 -- cyan copy split off it and horizontal tear streaks, jittering for its life (updateGlitches, pooled, capped).
 local glitchPool,glitches={},{}
 local function glitch67(pos,size,life,dir,txt)
  if #glitches>=(low()and 3 or 8)then return end
  local g=table.remove(glitchPool)
  if not g then
   g=Instance.new('BillboardGui');g.Name='PickGlitch';g.AlwaysOnTop=true;g.LightInfluence=0;g.MaxDistance=120
   g:SetAttribute('NoTranslate',true)
   for _,spec in ipairs({{'R',C(255,30,50),2},{'B',C(80,230,255),2},{'W',C(255,255,255),3}})do
    local l=Instance.new('TextLabel');l.Name=spec[1];l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true
    l.FontFace=Font.fromEnum(Enum.Font.GothamBlack);l.TextColor3=spec[2];l.ZIndex=spec[3];l.Rotation=-6
    l.TextStrokeTransparency=spec[1]=='W'and .1 or 1;l.TextStrokeColor3=C(110,0,12)
    l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
   end
   for _=1,4 do local f=Instance.new('Frame');f.Name='Streak';f.BorderSizePixel=0;f.ZIndex=4;f.Parent=g end
  end
  txt=txt or'67'
  g.Size=UDim2.fromOffset(size*.62*math.max(1,#txt),size);g.StudsOffsetWorldSpace=Vector3.zero
  for _,l in ipairs(g:GetChildren())do
   if l:IsA('TextLabel')then l.Text=txt;l.TextTransparency=l.Name=='W'and 0 or .15;l.Position=UDim2.fromOffset(0,0)end
  end
  local anchor=Instance.new('Attachment');anchor.Parent=workspace.Terrain;anchor.WorldPosition=pos
  g.Adornee=anchor;g.Parent=folder
  table.insert(glitches,{G=g,Anchor=anchor,Born=os.clock(),Life=life or .8,Dir=dir or Vector3.new(0,1,0),Size=size})
 end
 self.Glitch67=glitch67
 local function updateGlitches(now)
  for i=#glitches,1,-1 do
   local x=glitches[i];local g=x.G
   local k=(now-x.Born)/x.Life
   if k>=1 or not g.Parent then
    x.Anchor:Destroy();g.Adornee=nil;g.Parent=nil;table.remove(glitches,i)
    if #glitchPool<10 then table.insert(glitchPool,g)else g:Destroy()end
   else
    local j=(k<.25 and 1 or .35)*(math.random()<.25 and 1.8 or 1)
    local sz=x.Size
    local tr=k>.6 and(k-.6)/.4 or 0
    for _,c in ipairs(g:GetChildren())do
     if c.Name=='R'then c.Position=UDim2.fromOffset(-sz*.07*j+(math.random()-.5)*sz*.04,(math.random()-.5)*sz*.03);c.TextTransparency=.15+tr*.85
     elseif c.Name=='B'then c.Position=UDim2.fromOffset(sz*.06*j+(math.random()-.5)*sz*.04,(math.random()-.5)*sz*.03);c.TextTransparency=.35+tr*.65
     elseif c.Name=='W'then c.Position=UDim2.fromOffset((math.random()-.5)*sz*.03*j,0);c.TextTransparency=tr;c.TextStrokeTransparency=.1+tr*.9
     elseif c.Name=='Streak'then
      local on=math.random()<.55*(1-tr)
      c.Visible=on
      if on then
       c.BackgroundColor3=math.random()<.5 and C(255,40,52)or C(255,255,255)
       c.BackgroundTransparency=.1+math.random()*.4
       c.Position=UDim2.new(math.random()*.3-.15,0,math.random(),0)
       c.Size=UDim2.new(.5+math.random()*.7,0,0,math.max(2,math.floor(sz*(.02+math.random()*.05))))
      end
     end
    end
    g.StudsOffsetWorldSpace=x.Dir*math.sqrt(k)*(1.2+sz/80)
   end
  end
 end
 -- Small physical bits (bricks, pixels, drops, confetti) that fly, fall and fade.
 local function bits(pos,colors,count,size,speed,mat,shape,opts)
  opts=opts or{}
  for _=1,n(count)do
   local p=Instance.new('Part');p.Name='PickBit';p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Massless=true;p.CastShadow=false
   local s=size*(.7+math.random()*.6)
   p.Size=opts.Flat and Vector3.new(s,s*.25,s*.7)or Vector3.new(s,s,s)
   if shape then p.Shape=shape end
   p.Material=mat or Enum.Material.SmoothPlastic;p.Color=pick(colors);p.Transparency=opts.Transparency or 0
   p.CFrame=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6);p.Parent=folder
   local d=(Vector3.new(math.random()-.5,math.random()*.9+(opts.Up or .3),math.random()-.5)).Unit
   p.AssemblyLinearVelocity=d*speed*(.6+math.random()*.7)
   p.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*18
   TweenService:Create(p,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,opts.Life or .65),{Transparency=1}):Play()
   Debris:AddItem(p,(opts.Life or .65)+.5)
  end
 end
 self.Bits=bits
 -- Neon line pieces (lightning, scratches, slashes) that flash and fade.
 local function line(a,b,width,color,life,props)
  local len=(b-a).Magnitude;if len<.01 then return end
  local p=Instance.new('Part');p.Name='PickLine';p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
  p.Material=Enum.Material.Neon;p.Color=color;p.Size=Vector3.new(width,width,len)
  p.CFrame=CFrame.lookAt((a+b)/2,b);p.Parent=folder
  if props then for k,v in pairs(props)do(p::any)[k]=v end end
  TweenService:Create(p,TweenInfo.new(life or .25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1,Size=Vector3.new(width*.2,width*.2,len)}):Play()
  Debris:AddItem(p,(life or .25)+.05)
  return p
 end
 local function bolt(a,b,color,segments)
  local prev=a
  segments=segments or 5
  for i=1,segments do
   local f=i/segments
   local q=a:Lerp(b,f)
   if i<segments then q+=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*1.1 end
   line(prev,q,.12,color,.18+math.random()*.08)
   prev=q
  end
 end
 local function camFacing(pos)
  local cam=workspace.CurrentCamera
  if not cam then return CFrame.new(pos)end
  return CFrame.lookAt(pos,cam.CFrame.Position)
 end
 -- A crescent (anime slash) in the plane facing the camera.
 local function slash(pos,color,radius,tilt,life)
  local f=camFacing(pos)*CFrame.Angles(0,0,tilt or 0)
  local segs=9;local prev
  for i=0,segs do
   local a=rad(-70+i*140/segs)
   local q=(f*CFrame.new(cos(a)*radius,sin(a)*radius,0)).Position
   if prev then line(prev,q,.16+.22*sin(i/segs*math.pi),color,life or .3)end
   prev=q
  end
 end
 local function scratches(pos,color,cross)
  local f=camFacing(pos)
  for i=-1,1 do
   local o=f*CFrame.new(i*.55,0,0)
   line((o*CFrame.new(-1.3,1.6,0)).Position,(o*CFrame.new(1.3,-1.6,0)).Position,.13,color,.32)
   if cross then line((o*CFrame.new(1.3,1.6,0)).Position,(o*CFrame.new(-1.3,-1.6,0)).Position,.13,color,.32)end
  end
 end
 local function shock(pos,color,size,life)
  local p=Instance.new('Part');p.Name='PickShock';p.Shape=Enum.PartType.Ball;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
  p.CastShadow=false;p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=.45;p.Size=Vector3.one*.5;p.CFrame=CFrame.new(pos);p.Parent=folder
  TweenService:Create(p,TweenInfo.new(life or .35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.one*(size or 6),Transparency=1}):Play()
  Debris:AddItem(p,(life or .35)+.05)
 end
 local function burst(pos,colors,count,speed,tex,dir,opts)
  opts=opts or{}
  FX.Burst(pos,{Texture=tex or SPARK,Color=colors[1],Color2=colors[2]or colors[1],Count=count,Speed=NumberRange.new(speed*.5,speed),
   Direction=dir,Spread=opts.Spread,Acceleration=opts.Acceleration,Lifetime=opts.Lifetime,LightEmission=opts.LightEmission or .8,Size=opts.Size})
 end

 -- Glowing voxel butterflies (Butterfly Catcher): a body and two wings flying on a soft curling path,
 -- flapping, turned toward the camera like the sheet's butterflies, fading out at the end. Capped
 -- (fewer on low FX) and moved together once a frame (updateFlyers).
 local flyers={}
 local function flyer(pos,color,vel,life,size)
  if #flyers>=(low()and 6 or 18)then return end
  size=size or 1
  local function piece(name,sz,col)
   local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
   p.Massless=true;p.Material=Enum.Material.Neon;p.Color=col;p.Size=sz*size;p.CFrame=CFrame.new(pos);p.Parent=folder
   return p
  end
  table.insert(flyers,{Body=piece('PickButterfly',Vector3.new(.05,.22,.05),color:Lerp(Color3.new(1,1,1),.45)),
   L=piece('PickButterfly',Vector3.new(.26,.3,.02),color),R=piece('PickButterfly',Vector3.new(.26,.3,.02),color),
   Pos=pos,Vel=vel,Born=os.clock(),Life=life or 1.4,Size=size,Ph=math.random()*100})
 end
 self.Butterfly=flyer
 local function updateFlyers(now,dt,camPos)
  for i=#flyers,1,-1 do
   local f=flyers[i]
   local age=now-f.Born
   if age>=f.Life or not f.Body.Parent then
    f.Body:Destroy();f.L:Destroy();f.R:Destroy();table.remove(flyers,i)
   else
    f.Vel+=Vector3.new(math.noise(f.Ph,age*1.3)*4,math.noise(age*1.1,f.Ph)*3+.8,math.noise(f.Ph*2,age*1.2)*4)*dt
    f.Vel*=math.max(0,1-dt*1.1)
    f.Pos+=f.Vel*dt
    local base=CFrame.lookAt(f.Pos,camPos)*CFrame.Angles(0,0,math.noise(f.Ph,age)*.6)
    local flap=(sin(age*30+f.Ph)+.4)*.9
    local w=.13*f.Size
    f.Body.CFrame=base
    f.L.CFrame=base*CFrame.Angles(0,flap,0)*CFrame.new(-w,.02*f.Size,0)
    f.R.CFrame=base*CFrame.Angles(0,-flap,0)*CFrame.new(w,.02*f.Size,0)
    local k=age/f.Life
    local tr=k<.08 and 1-k/.08 or(k>.6 and(k-.6)/.4 or 0)
    f.Body.Transparency=tr;f.L.Transparency=tr;f.R.Transparency=tr
   end
  end
 end

 -- HIT EFFECTS PER THEME ------------------------------------------------------------------------
 -- (pos, dir, quality, crit, remote) -> world effects only (the 2D layer is MiningClient.Combo).
 local HIT={}
 HIT.Wood=function(pos,dir,q,crit)
  local c=pal('Wood')
  bits(pos,c,crit and 8 or 4,.22,16,Enum.Material.WoodPlanks,nil,{Flat=true})
  burst(pos,{C(190,160,120)},crit and 10 or 5,6,SMOKE,dir,{LightEmission=0})
 end
 -- LEGO Hand (concept sheet "ЭФФЕКТЫ / VFX"): real plastic 2x2 bricks with studs (ЧАСТИЦЫ: yellow, red,
 -- blue, white) tumble out of the impact; УДАРНЫЙ ЭФФЕКТ: a white-hot flash with jagged golden lightning
 -- rays and four-point stars (✦); grey stone chips; a crit: twice the bricks, more rays, a golden ring and
 -- "CLICK!". Bricks are small welded assemblies (5 parts), capped and halved on low FX.
 local function legoBrick(pos,color,size,vel,life)
  local b=Instance.new('Part');b.Name='PickBrick';b.Size=Vector3.new(size,size*.6,size);b.Color=color;b.Material=Enum.Material.SmoothPlastic
  b.Reflectance=.06;b.CanCollide=false;b.CanQuery=false;b.CanTouch=false;b.CastShadow=false
  b.TopSurface=Enum.SurfaceType.Smooth;b.BottomSurface=Enum.SurfaceType.Smooth
  b.CFrame=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
  local list={b}
  for i=0,3 do
   local s=Instance.new('Part');s.Name='PickBrickStud';s.Shape=Enum.PartType.Cylinder;s.Size=Vector3.new(size*.18,size*.3,size*.3)
   s.Color=color;s.Material=Enum.Material.SmoothPlastic;s.Reflectance=.06;s.CanCollide=false;s.CanQuery=false;s.CanTouch=false;s.CastShadow=false;s.Massless=true
   s.CFrame=b.CFrame*CFrame.new(((i%2)-.5)*size*.5,size*.39,(math.floor(i/2)-.5)*size*.5)*CFrame.Angles(0,0,math.pi/2)
   local w=Instance.new('WeldConstraint');w.Part0=b;w.Part1=s;w.Parent=s
   s.Parent=b;table.insert(list,s)
  end
  b.Parent=folder
  b.AssemblyLinearVelocity=vel
  b.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*14
  life=life or .8
  for _,p in ipairs(list)do TweenService:Create(p,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life),{Transparency=1}):Play()end
  Debris:AddItem(b,life+.45)
 end
 local function legoBricks(pos,dir,count,speed,size,life)
  local cols=pal('Brick')
  for _=1,n(count)do
   local d=(dir*.8+Vector3.new(math.random()-.5,math.random()*.9+.35,math.random()-.5)).Unit
   legoBrick(pos+d*.2,pick(cols),(size or .42)*(.75+math.random()*.5),d*speed*(.55+math.random()*.7),life)
  end
 end
 self.LegoBricks=legoBricks
 -- a jagged golden lightning ray (two kinks), in the plane facing the camera
 local function zap(pos,d,len,width,color,life)
  local f=camFacing(pos)
  local side=(f.RightVector*d:Dot(f.UpVector)-f.UpVector*d:Dot(f.RightVector))
  local a=pos+d*.2
  local b=pos+d*len*.45+side*(math.random()-.5)*.5
  local c=pos+d*len*.7-side*(math.random()-.5)*.4
  local e=pos+d*len
  line(a,b,width,color,life);line(b,c,width*.85,color,life);line(c,e,width*.6,color,life)
 end
 HIT.Brick=function(pos,dir,q,crit,remote)
  local c=pal('Brick')
  local f=camFacing(pos)
  shock(pos,C(255,244,190),crit and 6.5 or 3.6,.22)
  for i=1,n(crit and 9 or 6)do
   local a=(i-1)/(crit and 9 or 6)*math.pi*2+math.random()*.5
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   zap(pos,d,(crit and 3.4 or 2.2)*(.7+math.random()*.5),i%2==0 and .1 or .15,i%3==0 and C(255,255,230)or C(255,206,40),.2+math.random()*.08)
  end
  burst(pos,{C(255,236,140),C(255,170,30)},crit and 26 or 14,16,SPARK,dir)
  legoBricks(pos,dir,remote and 3 or(crit and 11 or 6),crit and 22 or 17,.42,.85)
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 7 or 4,.22,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  for _=1,n(crit and 6 or 3)do glyph(pos,'✦',pick(LEGO_STARS),pick({20,26,32}),nil,.7)end
  if crit then
   FX.Ring(pos,c[1],9,.35)
   glyph(pos+Vector3.new(0,1.6,0),'CLICK!',C(255,206,30),76,Vector3.new(0,1,0),1.1)
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick(LEGO_POP),C(255,214,60),26,Vector3.new(0,1,0),.6)
  end
 end
 -- Pickaxe 67 (concept sheet "ЭФФЕКТЫ / VFX" and "В ИГРЕ"): УДАРНЫЙ ЭФФЕКТ a white flash with jagged white /
 -- red rays and glitch tear streaks across the impact; red, white and black voxel cubes fly out of the ore,
 -- some with a "67" printed on them; ЧАСТИЦЫ red / white "6", "7" and "67" digits; a perfect hit prints a
 -- glitching "67", a crit a GIANT one, a ring and twice everything. Cubes are capped and halved on low FX.
 local function digitCube(pos,color,size,vel,life,label)
  local b=Instance.new('Part');b.Name='PickDigitCube';b.Size=Vector3.one*size;b.Color=color;b.Material=Enum.Material.SmoothPlastic
  b.Reflectance=.05;b.CanCollide=false;b.CanQuery=false;b.CanTouch=false;b.CastShadow=false
  b.TopSurface=Enum.SurfaceType.Smooth;b.BottomSurface=Enum.SurfaceType.Smooth
  b.CFrame=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
  local labels={}
  if label then
   for _,face in ipairs({Enum.NormalId.Front,Enum.NormalId.Back})do
    local g=Instance.new('SurfaceGui');g.Face=face;g.LightInfluence=0;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=60
    g:SetAttribute('NoTranslate',true);g.Parent=b
    local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Size=UDim2.fromScale(1,1);l.TextScaled=true;l.Text='67'
    l.FontFace=Font.fromEnum(Enum.Font.GothamBlack);l.TextColor3=(color.R+color.G+color.B)/3>.7 and C(20,18,22)or C(255,255,255)
    l:SetAttribute('NoTranslate',true);l:SetAttribute('KeepFont',true);l.Parent=g
    table.insert(labels,l)
   end
  end
  b.Parent=folder
  b.AssemblyLinearVelocity=vel
  b.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*14
  life=life or .8
  TweenService:Create(b,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life),{Transparency=1}):Play()
  for _,l in ipairs(labels)do TweenService:Create(l,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life),{TextTransparency=1}):Play()end
  Debris:AddItem(b,life+.45)
 end
 local function digitCubes(pos,dir,count,speed,labeled)
  local cols={C(235,40,52),C(235,40,52),C(244,244,240),C(30,28,32)}
  for i=1,n(count)do
   local d=(dir*.8+Vector3.new(math.random()-.5,math.random()*.9+.35,math.random()-.5)).Unit
   digitCube(pos+d*.2,pick(cols),.34*(.75+math.random()*.55),d*speed*(.55+math.random()*.7),.85,i<=(labeled or 0))
  end
 end
 self.DigitCubes=digitCubes
 HIT.Digits=function(pos,dir,q,crit,remote)
  local c=pal('Digits')
  local f=camFacing(pos)
  shock(pos,C(255,236,236),crit and 6.5 or 3.4,.2)
  for i=1,n(crit and 8 or 5)do
   local a=(i-1)/(crit and 8 or 5)*math.pi*2+math.random()*.5
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   zap(pos,d,(crit and 3.2 or 2)*(.7+math.random()*.5),i%2==0 and .09 or .14,i%2==0 and C(255,255,255)or C(255,40,52),.18+math.random()*.08)
  end
  for _=1,n(remote and 2 or(crit and 7 or 4))do -- glitch tear streaks across the impact
   local o=pos+f.UpVector*(math.random()-.5)*1.8
   local l=1+math.random()*(crit and 3 or 2)
   line(o-f.RightVector*l*.6,o+f.RightVector*l*.4,.05+math.random()*.08,pick(SIX_COLORS),.16+math.random()*.1)
  end
  burst(pos,{C(255,60,70),C(255,255,255)},crit and 22 or 10,13,SPARK,dir)
  digitCubes(pos,dir,remote and 2 or(crit and 10 or 5),crit and 20 or 15,remote and 0 or(crit and 4 or 1))
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 7 or 4,.2,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  for _=1,n(crit and 7 or 3)do glyph(pos,pick(SIX_DIGITS),pick(SIX_COLORS),pick({24,30,36}),nil,.7)end
  if crit then
   glitch67(pos+Vector3.new(0,2,0),160,1.3,Vector3.new(0,1,0))
   shock(pos,C(235,40,52),9)
   FX.Ring(pos,c[1],10,.35)
  elseif q==2 and not remote then
   glitch67(pos+Vector3.new(0,.9,0),46,.6,Vector3.new(0,1,0))
  end
 end
 -- Gummy Horror (concept sheet "ЭФФЕКТЫ / VFX"): caramel splashes fan out of the impact, candy
 -- cubes and gummy bits fly, sticky drops and stretched slime threads, a sticky splat clings to the
 -- ore for a moment. A crit: a bigger splash and "SQUISH!".
 local function splat(pos,dir,color,size)
  local p=Instance.new('Part');p.Name='GummySplat';p.Shape=Enum.PartType.Cylinder;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
  p.CastShadow=false;p.Material=Enum.Material.Glass;p.Color=color;p.Transparency=.1;p.Size=Vector3.new(.08,.3,.3)
  p.CFrame=CFrame.lookAt(pos,pos+dir)*CFrame.Angles(0,math.pi/2,0);p.Parent=folder
  TweenService:Create(p,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=Vector3.new(.08,size,size)}):Play()
  TweenService:Create(p,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.7),{Transparency=1,Size=Vector3.new(.04,size*1.15,size*1.15)}):Play()
  Debris:AddItem(p,1.3)
 end
 HIT.Gummy=function(pos,dir,q,crit,remote)
  local c=pal('Gummy')
  local caramel={C(255,170,40),C(255,206,70),C(255,130,30)}
  for _=1,n(crit and 9 or 5)do
   local a=math.random()*math.pi*2
   local d=(dir*.8+Vector3.new(cos(a),math.random()*.6,sin(a))).Unit
   line(pos+d*.2,pos+d*(1.1+math.random()*(crit and 1.8 or 1.1)),.14+math.random()*.12,pick(caramel),.22+math.random()*.1,{Material=Enum.Material.Glass,Transparency=.05})
  end
  bits(pos,caramel,crit and 10 or 5,.26,14,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.6})
  bits(pos,{c[1],c[2],c[3],C(255,150,205),C(255,140,40)},crit and 12 or 6,.3,17,Enum.Material.Glass,nil,{Transparency=.08,Up=.8,Life=.85})
  bits(pos,{c[1],c[2]},crit and 8 or 4,.2,10,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.2,Up=.3,Life=.9})
  FX.Ring(pos,C(255,170,60),crit and 9 or 5,.4)
  burst(pos,{c[1],c[3]},crit and 14 or 6,7,SPARK,dir)
  if not remote then
   for _=1,n(crit and 4 or 2)do
    local d=(Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)+dir*.5).Unit
    line(pos,pos+d*(1+math.random()*1.2),.05,c[2],.35,{Material=Enum.Material.Glass,Transparency=.15})
   end
   splat(pos,dir,pick({c[1],c[2]}),crit and 1.7 or 1.1)
  end
  if crit then
   glyph(pos+Vector3.new(0,1.5,0),'SQUISH!',c[1],64,Vector3.new(0,1,0),1)
   shock(pos,c[3],8,.3)
  end
 end
 -- Rotten Slime Slug (concept sheet "VFX / SFX"): КАПЛИ СЛИЗИ (glossy lime / acid drops flung out of the impact),
 -- ГНИЛОСТНЫЙ УДАР (a slime splash fanning up with rotten brick and dirt chunks, a splat clinging to the ore),
 -- ЧАВК (a crit prints "SPLURP!", a perfect a little "splurp") and КОЛЕБАНИЕ ГЛАЗ (a crit throws googly eyeballs
 -- out that wobble and fall; the held slug's own eyes shoot out on their threads, see SlugStalk).
 local function eyeball(pos,vel,size,life)
  local w=Instance.new('Part');w.Name='PickEyeball';w.Shape=Enum.PartType.Ball;w.Size=Vector3.one*size;w.Color=C(248,238,208)
  w.Material=Enum.Material.SmoothPlastic;w.CanCollide=false;w.CanQuery=false;w.CanTouch=false;w.CastShadow=false
  w.CFrame=CFrame.lookAt(pos,pos+vel)
  local list={w}
  for i,spec in ipairs({{.55,.08,C(178,48,80)},{.3,.1,C(22,8,16)}})do
   local p=Instance.new('Part');p.Name='PickEyeballIris';p.Shape=Enum.PartType.Cylinder;p.Size=Vector3.new(size*spec[2],size*spec[1],size*spec[1])
   p.Color=spec[3];p.Material=Enum.Material.SmoothPlastic;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Massless=true
   p.CFrame=w.CFrame*CFrame.new(0,0,-size*(.43+i*.03))*CFrame.Angles(0,math.pi/2,0)
   local wc=Instance.new('WeldConstraint');wc.Part0=w;wc.Part1=p;wc.Parent=p;p.Parent=w;table.insert(list,p)
  end
  w.Parent=folder
  w.AssemblyLinearVelocity=vel
  w.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*10
  life=life or .9
  for _,p in ipairs(list)do TweenService:Create(p,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life),{Transparency=1}):Play()end
  Debris:AddItem(w,life+.4)
 end
 self.Eyeball=eyeball
 HIT.Slime=function(pos,dir,q,crit,remote)
  local c=pal('Slime')
  local f=camFacing(pos)
  -- the splash: thick glossy streaks fanning up and out of the impact
  for i=1,n(crit and 10 or 6)do
   local a=rad(15+(i-.5)/(crit and 10 or 6)*150+math.random(-10,10))
   local d=(f.RightVector*cos(a)+f.UpVector*sin(a)+dir*.5).Unit
   line(pos+d*.2,pos+d*(1+math.random()*(crit and 1.9 or 1.2)),.16+math.random()*.14,i%3==0 and c[2]or c[1],.26+math.random()*.1,{Material=Enum.Material.Glass,Transparency=.05})
  end
  -- drops
  bits(pos,{c[1],c[2],c[1]},crit and 14 or 8,.28,13,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.08,Up=.7,Life=.8})
  bits(pos,{c[3],c[1]},crit and 6 or 3,.18,7,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.2,Life=.9})
  -- rot: brick and dirt chunks
  bits(pos,SLUG_ROT,crit and 9 or 5,.26,15,Enum.Material.Wood,nil,{Up=.7,Life=.7})
  burst(pos,{C(150,190,70),C(90,110,50)},crit and 10 or 5,4,SMOKE,dir,{LightEmission=0})
  burst(pos,{c[2],c[1]},crit and 12 or 6,7,SPARK,dir)
  FX.Ring(pos,c[1],crit and 9 or 5,.4)
  if not remote then
   splat(pos,dir,pick({c[1],c[2]}),crit and 1.8 or 1.15)
   for _=1,n(crit and 3 or 2)do -- sticky threads
    local d=(Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)+dir*.5).Unit
    line(pos,pos+d*(1+math.random()*1.2),.05,c[1],.4,{Material=Enum.Material.Glass,Transparency=.1})
   end
  end
  if crit then
   glyph(pos+Vector3.new(0,1.6,0),'SPLURP!',c[2],72,Vector3.new(0,1,0),1.1)
   shock(pos,c[2],8,.3)
   if not remote and not low()then
    for i=1,3 do
     local a=(i-2)*.7
     eyeball(pos+dir*.4,(f.UpVector*(9+math.random()*3)+f.RightVector*math.sin(a)*6+dir*3),.42,.9)
    end
   end
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick({'splurp','шлёп','чавк'}),c[2],26,Vector3.new(0,1,0),.6)
  end
 end
 -- Toothy Alarm Clock (concept sheet "ЭФФЕКТЫ / VFX" and "В ИГРЕ"): УДАР a red-white flash with jagged red rays
 -- and the RING of the bell (red and gold shock rings), ЧАСТИЦЫ red and grey voxel cubes and little gold gears,
 -- ВЫЛЕТАЮЩИЕ ЧАСЫ (small red alarm clocks with cream dials flying out of the ore), a perfect rings "ДЗЫНЬ"; a
 -- КРИТ-ЭФФЕКТ: a big glowing red clock face bursts open over the ore with its hands whirling (critDial),
 -- twice everything and "DRRRING!". Gears and clocks are small welded assemblies, capped and halved on low FX.
 local function welded(main,list,vel,life)
  main.Parent=folder
  main.AssemblyLinearVelocity=vel
  main.AssemblyAngularVelocity=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*12
  life=life or .9
  for _,p in ipairs(list)do TweenService:Create(p,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life),{Transparency=1}):Play()end
  Debris:AddItem(main,life+.4)
 end
 local function piece(name,size,cf,color,mat,shape,parent)
  local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=mat or Enum.Material.SmoothPlastic
  p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.Massless=parent~=nil
  p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
  if shape then p.Shape=shape end
  if parent then local w=Instance.new('WeldConstraint');w.Part0=parent;w.Part1=p;w.Parent=p;p.Parent=parent end
  return p
 end
 local alarmBits=0
 local function alarmGear(pos,vel,size)
  if alarmBits>=(low()and 8 or 24)then return end
  alarmBits+=1;task.delay(1.3,function()alarmBits-=1 end)
  local cf=CFrame.new(pos)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
  local g=piece('PickGear',Vector3.new(size*.3,size,size),cf,C(246,196,82),Enum.Material.Foil,Enum.PartType.Cylinder)
  local list={g}
  for k=0,1 do table.insert(list,piece('PickGearTooth',Vector3.new(size*.26,size*1.3,size*.22),cf*CFrame.Angles(k*math.pi/2+math.pi/4,0,0),C(214,160,60),Enum.Material.Foil,nil,g))end
  welded(g,list,vel,.85)
 end
 local function alarmClock(pos,vel,size)
  if alarmBits>=(low()and 8 or 24)then return end
  alarmBits+=1;task.delay(1.4,function()alarmBits-=1 end)
  local cf=CFrame.lookAt(pos,pos+vel)*CFrame.Angles(0,math.pi/2,0)
  local b=piece('PickClock',Vector3.new(size*.45,size,size),cf,C(224,32,36),Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
  local list={b}
  table.insert(list,piece('PickClockFace',Vector3.new(size*.06,size*.8,size*.8),cf*CFrame.new(size*.23,0,0),C(244,226,206),Enum.Material.SmoothPlastic,Enum.PartType.Cylinder,b))
  table.insert(list,piece('PickClockHand',Vector3.new(size*.05,size*.36,size*.06),cf*CFrame.new(size*.27,size*.15,0),C(150,14,20),Enum.Material.SmoothPlastic,nil,b))
  table.insert(list,piece('PickClockHand',Vector3.new(size*.05,size*.06,size*.28),cf*CFrame.new(size*.27,0,size*.12),C(150,14,20),Enum.Material.SmoothPlastic,nil,b))
  for k=-1,1,2 do table.insert(list,piece('PickClockBell',Vector3.one*size*.36,cf*CFrame.new(0,size*.5,k*size*.32),C(150,148,154),Enum.Material.Metal,Enum.PartType.Ball,b))end
  welded(b,list,vel,1)
 end
 self.AlarmClock=alarmClock
 -- Clown Chronomord's flying pocket watches (concept "ЧАСТИЦЫ" / "МАЛЕНЬКИЕ ЧАСЫ"): a gold or red case, a cream face
 -- turned to the camera, two black hands and the bow on top; the same budget as the alarm clocks.
 local function chronoWatch(pos,vel,size,red)
  if alarmBits>=(low()and 8 or 24)then return end
  alarmBits+=1;task.delay(1.4,function()alarmBits-=1 end)
  local cam=workspace.CurrentCamera
  local cf=(cam and CFrame.lookAt(pos,cam.CFrame.Position)or CFrame.new(pos))*CFrame.Angles(0,math.pi/2,0)
  local b=piece('PickWatch',Vector3.new(size*.3,size,size),cf,red and C(214,40,46)or C(222,168,58),Enum.Material.Metal,Enum.PartType.Cylinder)
  local list={b}
  table.insert(list,piece('PickWatchFace',Vector3.new(size*.06,size*.78,size*.78),cf*CFrame.new(size*.15,0,0),C(244,234,212),Enum.Material.SmoothPlastic,Enum.PartType.Cylinder,b))
  table.insert(list,piece('PickWatchHand',Vector3.new(size*.05,size*.34,size*.06),cf*CFrame.new(size*.19,size*.14,0),C(28,22,24),Enum.Material.SmoothPlastic,nil,b))
  table.insert(list,piece('PickWatchHand',Vector3.new(size*.05,size*.06,size*.26),cf*CFrame.new(size*.19,0,size*.1),C(28,22,24),Enum.Material.SmoothPlastic,nil,b))
  table.insert(list,piece('PickWatchBow',Vector3.new(size*.12,size*.24,size*.24),cf*CFrame.new(0,size*.6,0),C(246,206,104),Enum.Material.Metal,nil,b))
  welded(b,list,vel,1)
 end
 self.ChronoWatch=chronoWatch
 -- the crit's big glowing clock face (camera-facing, grows, the hands whirl, fades); moved in updateDials
 local critDials={}
 local function critDial(pos,size)
  if #critDials>=(low()and 1 or 2)then return end
  local f=camFacing(pos)
  local parts={}
  local function add(name,sz,kind,a,rr,col)
   local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
   p.Material=Enum.Material.Neon;p.Color=col;p.Size=sz;p.Transparency=1;p.Parent=folder
   table.insert(parts,{Part=p,Kind=kind,A=a,R=rr})
  end
  for i=0,23 do add('PickCritRing',Vector3.new(size*.3,size*.07,.08),'ring',i/24*math.pi*2,size,C(255,44,40))end
  for i=0,11 do add('PickCritTick',Vector3.new(size*.05,size*(i%3==0 and .2 or .12),.08),'tick',i/12*math.pi*2,size*.8,i%3==0 and C(255,236,200)or C(255,90,70))end
  add('PickCritHand',Vector3.new(size*.08,size*.68,.08),'hand',0,size*.34,C(255,240,220))
  add('PickCritHand',Vector3.new(size*.1,size*.46,.08),'hand2',0,size*.23,C(255,160,120))
  table.insert(critDials,{Parts=parts,F=f,Born=os.clock(),Life=.95})
 end
 local function updateDials(now)
  for i=#critDials,1,-1 do
   local d=critDials[i]
   local k=(now-d.Born)/d.Life
   if k>=1 then
    for _,x in ipairs(d.Parts)do x.Part:Destroy()end
    table.remove(critDials,i)
   else
    local grow=.45+.55*(1-(1-math.min(1,k*2.2))^3)
    local tr=k<.08 and 1-k/.08 or(k>.55 and(k-.55)/.45 or 0)
    for _,x in ipairs(d.Parts)do
     local p=x.Part
     if x.Kind=='hand'or x.Kind=='hand2'then
      local a=-(k*(x.Kind=='hand'and 9 or 3))*math.pi
      p.CFrame=d.F*CFrame.Angles(0,0,a)*CFrame.new(0,x.R*grow,.05)
     else
      p.CFrame=d.F*CFrame.Angles(0,0,x.A)*CFrame.new(0,x.R*grow,0)
     end
     p.Transparency=math.clamp(tr*.9+(x.Kind=='ring'and .05 or 0),0,1)
    end
   end
  end
 end
 HIT.Alarm=function(pos,dir,q,crit,remote)
  local c=pal('Alarm')
  local f=camFacing(pos)
  shock(pos,C(255,230,220),crit and 6.8 or 3.8,.22)
  -- the ring of the bell: red and gold shock rings
  for i=0,(crit and 3 or 1)do task.delay(i*.07,function()FX.Ring(pos,i%2==0 and c[1]or c[2],4+i*2.6,.36)end)end
  for i=1,n(crit and 10 or 6)do
   local a=(i-1)/(crit and 10 or 6)*math.pi*2+math.random()*.5
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   zap(pos,d,(crit and 3.4 or 2.2)*(.7+math.random()*.5),i%2==0 and .1 or .15,i%3==0 and C(255,236,220)or C(240,36,36),.2+math.random()*.08)
  end
  burst(pos,{C(255,90,70),C(255,220,150)},crit and 24 or 12,14,SPARK,dir)
  bits(pos,{c[1],c[1],C(176,20,26)},crit and 9 or 5,.26,15,Enum.Material.SmoothPlastic,nil,{Up=.7,Life=.7})
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 7 or 4,.22,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  if not remote then
   for _=1,n(crit and 5 or 3)do -- little gold gears
    local d=(dir*.7+Vector3.new(math.random()-.5,math.random()*.9+.3,math.random()-.5)).Unit
    alarmGear(pos+d*.3,d*(10+math.random()*8),.34+math.random()*.16)
   end
   for _=1,n(crit and 4 or(q==2 and 2 or 1))do -- flying alarm clocks
    local d=(dir*.6+Vector3.new(math.random()-.5,math.random()*.8+.6,math.random()-.5)).Unit
    alarmClock(pos+d*.4,d*(9+math.random()*6),.5+math.random()*.2)
   end
  end
  for _=1,n(remote and 1 or(crit and 4 or 2))do glyph(pos,pick({'⏰','⏱','!','!!'}),pick({c[1],c[2],c[3]}),pick({24,30,34}),nil,.75)end
  if crit then
   if not remote then critDial(pos+f.LookVector*.6+Vector3.new(0,.6,0),2.6)end
   glyph(pos+Vector3.new(0,1.9,0),pick(ALARM_RING),C(255,214,90),78,Vector3.new(0,1,0),1.1)
   shock(pos,c[1],9,.3)
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick({'ДЗЫНЬ','ring!','дзынь'}),c[2],26,Vector3.new(0,1,0),.6)
  end
 end
 -- Ponycorn-Dolphoodle (concept sheet "Удар (Hit Effect)"): a rainbow flash, a fan of rainbow
 -- beams bursting up out of the ore, stars and hearts, magic sparks. A crit: a little rainbow arc
 -- over the ore and "MAGIC!".
 HIT.Rainbow=function(pos,dir,q,crit,remote)
  shock(pos,C(255,236,250),crit and 7 or 4.5,.28)
  for i=1,(crit and 4 or 2)do task.delay(i*.05,function()FX.Ring(pos,PONY_HUES[(i*2)%#PONY_HUES+1],3+i*1.8,.45)end)end
  local f=camFacing(pos)
  local beams=n(crit and 8 or 5)
  for i=1,beams do
   local a=rad(30+(i-.5)/beams*120+math.random(-8,8))
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   line(pos+d*.3,pos+d*(1.6+math.random()*(crit and 2.2 or 1.3)),.16+math.random()*.1,PONY_HUES[(i-1)%#PONY_HUES+1],.3+math.random()*.1)
  end
  for _=1,n(crit and 7 or 4)do glyph(pos,pick({'★','♥','✦','✧','♥'}),pick(PONY_HUES),pick({24,30,34}),nil,.9)end
  burst(pos,{C(255,150,220),C(255,240,140)},crit and 26 or 12,11,SPARK,dir)
  if not remote then
   bits(pos,PONY_HUES,crit and 8 or 4,.16,9,Enum.Material.Neon,Enum.PartType.Ball,{Up=1,Life=.7})
  end
  if crit then
   for band=0,2 do slash(pos+Vector3.new(0,.5,0),PONY_HUES[band*2+1],2.3-band*.3,rad(90),.45)end
   glyph(pos+Vector3.new(0,1.6,0),'MAGIC!',C(255,120,210),64,Vector3.new(0,1,0),1)
  end
 end
 -- Zombie-Frankenstein (concept sheet "ЭФФЕКТЫ (VFX / SFX)" and "Удар (Hit Effect)"): an electric surge: a blue-white
 -- flash, jagged blue lightning forking out of the impact and a blue shock ring; the strike throws stone chips, rusty
 -- bits and bone shards and splashes rotten-green slime drops ("осколки + капли слизи"); a perfect crackles "zzt"; a
 -- CRIT: a bigger surge, lightning crawling over the ore, a slime ring and "ZZT!!". Halved on low FX.
 HIT.Zombie=function(pos,dir,q,crit,remote)
  local c=pal('Zombie')
  local f=camFacing(pos)
  shock(pos,C(210,240,255),crit and 6.5 or 3.6,.2)
  for i=1,n(crit and 6 or 3)do
   local a=math.random()*math.pi*2
   local d=(f.RightVector*cos(a)+f.UpVector*(sin(a)*.8+.3)+dir*.4).Unit
   bolt(pos,pos+d*((crit and 3.4 or 2.3)*(.7+math.random()*.5)),i%2==0 and c[2]or c[1],5)
  end
  burst(pos,{c[2],c[1]},crit and 22 or 11,14,SPARK,dir)
  FX.Ring(pos,c[1],crit and 8 or 4.5,.3)
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 6 or 3,.22,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  bits(pos,{c[4],C(112,64,46)},crit and 5 or 2,.18,13,Enum.Material.CorrodedMetal,nil,{Up=.6,Life=.6})
  bits(pos,{c[5],C(206,188,142)},crit and 5 or 2,.17,12,Enum.Material.Limestone,nil,{Flat=true,Up=.7,Life=.6})
  bits(pos,{c[3],C(214,255,96)},crit and 10 or(remote and 2 or 5),.2,10,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.8,Life=.7})
  if crit then
   FX.Ring(pos,c[3],10,.42)
   shock(pos,c[1],9,.3)
   if not remote then
    for i=1,n(6)do task.delay(i*.05,function()
     local o=pos+Vector3.new(math.random()-.5,math.random()-.3,math.random()-.5)*2.2
     bolt(o,o+Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*2.4,i%2==0 and c[2]or c[1],3)
    end)end
   end
   glyph(pos+Vector3.new(0,1.8,0),'ZZT!!',C(150,220,255),78,Vector3.new(0,1,0),1.1)
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick({'zzt','ззт','bzz'}),c[2],26,Vector3.new(0,1,0),.6)
  end
 end
 -- Clown Chronomord (concept sheet "ЭФФЕКТЫ / VFX"): УДАРНЫЙ ЭФФЕКТ a white-hot star with scarlet rays and a red ring;
 -- ЧАСТИЦЫ red voxel dice, gold gears and stone chips; МАЛЕНЬКИЕ ЧАСЫ gold and red pocket watches fly out of the ore;
 -- a perfect giggles "хи-хи"; a CRIT: the big glowing clock face with whirling hands (critDial), more of everything
 -- and "HA-HA-HA!". Halved on low FX.
 HIT.Clown=function(pos,dir,q,crit,remote)
  local c=pal('Clown')
  local f=camFacing(pos)
  shock(pos,C(255,236,220),crit and 6.5 or 3.6,.2)
  local rays=n(crit and 12 or 7)
  for i=1,rays do
   local a=(i-1)/rays*math.pi*2+math.random()*.4
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   line(pos+d*.2,pos+d*((crit and 3.2 or 2)*(.6+math.random()*.6)),i%2==0 and .1 or .16,i%3==0 and C(255,240,220)or c[1],.2+math.random()*.08)
  end
  burst(pos,{C(255,120,90),C(255,220,140)},crit and 24 or 12,14,SPARK,dir)
  FX.Ring(pos,c[1],crit and 8 or 4.5,.3)
  bits(pos,{c[1],C(176,24,32),C(236,70,64)},crit and 9 or 5,.28,15,Enum.Material.SmoothPlastic,nil,{Up=.7,Life=.75})
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 6 or 3,.22,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  if not remote then
   for _=1,n(crit and 4 or 2)do -- little gold gears
    local d=(dir*.7+Vector3.new(math.random()-.5,math.random()*.9+.3,math.random()-.5)).Unit
    alarmGear(pos+d*.3,d*(10+math.random()*8),.3+math.random()*.16)
   end
   for _=1,n(crit and 5 or(q==2 and 3 or 2))do -- flying pocket watches
    local d=(dir*.6+Vector3.new(math.random()-.5,math.random()*.8+.6,math.random()-.5)).Unit
    chronoWatch(pos+d*.4,d*(9+math.random()*6),.48+math.random()*.2,math.random()<.35)
   end
  end
  for _=1,n(remote and 1 or(crit and 4 or 2))do glyph(pos,pick({'✦','✧','⏱','🕐'}),pick({c[1],c[2],c[3]}),pick({22,28,32}),nil,.7)end
  if crit then
   if not remote then critDial(pos+f.LookVector*.6+Vector3.new(0,.6,0),2.6)end
   glyph(pos+Vector3.new(0,1.9,0),pick(CHRONO_LAUGH),C(255,90,80),74,Vector3.new(0,1,0),1.1)
   shock(pos,c[1],9,.3)
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick({'хи-хи','hee-hee','тик!'}),c[2],26,Vector3.new(0,1,0),.6)
  end
 end
 -- Nasty Octopus (concept sheet "VFX EXAMPLES"): WET SPLASHES (glossy white-blue streaks fanning up out of the impact), WATER
 -- DROPLETS (light-blue drops), INK DROPS (glossy black-violet drops and an ink splat clinging to the ore), IMPACT SPLATTER (a
 -- blue / violet spray, an ink cloud, a ring); EXTRA IDEAS: POISONOUS BUBBLE (small toxic green bubbles float up and pop, the
 -- sheet's SLIMY green) and, on a CRIT, the TENTACLE LASH (a violet and a pink crescent snapping through the impact), twice
 -- everything and "SPLOOSH!"; a perfect "bloop". Bubbles are anchored and capped, everything is halved on low FX.
 local octoBubbles=0
 local function octoBubble(pos,size,life)
  if octoBubbles>=(low()and 3 or 10)then return end
  octoBubbles+=1
  local b=Instance.new('Part');b.Name='PickBubble';b.Shape=Enum.PartType.Ball;b.Anchored=true;b.CanCollide=false;b.CanQuery=false;b.CanTouch=false
  b.CastShadow=false;b.Material=Enum.Material.Glass;b.Color=pick(OCTO_TOXIC);b.Transparency=.35;b.Reflectance=.2
  b.Size=Vector3.one*size*.3;b.CFrame=CFrame.new(pos);b.Parent=folder
  life=life or 1
  local to=pos+Vector3.new((math.random()-.5)*1.2,1.4+math.random()*1.4,(math.random()-.5)*1.2)
  TweenService:Create(b,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=Vector3.one*size}):Play()
  TweenService:Create(b,TweenInfo.new(life,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{CFrame=CFrame.new(to)}):Play()
  task.delay(life,function()
   octoBubbles=math.max(0,octoBubbles-1)
   if b.Parent then
    local p=b.Position
    b:Destroy()
    if not(FX.ReducedMotion and FX.ReducedMotion())then shock(p,C(170,255,120),size*2.2,.18)end
   end
  end)
 end
 self.OctoBubble=octoBubble
 HIT.Ink=function(pos,dir,q,crit,remote)
  local c=pal('Ink')
  local f=camFacing(pos)
  shock(pos,C(220,242,255),crit and 6.5 or 3.6,.22)
  -- wet splashes: thick glossy streaks fanning up and out of the impact
  for i=1,n(crit and 10 or 6)do
   local a=rad(15+(i-.5)/(crit and 10 or 6)*150+math.random(-10,10))
   local d=(f.RightVector*cos(a)+f.UpVector*sin(a)+dir*.5).Unit
   line(pos+d*.2,pos+d*(1+math.random()*(crit and 2 or 1.3)),.14+math.random()*.12,i%3==0 and C(235,248,255)or pick(OCTO_WATER),.26+math.random()*.1,{Material=Enum.Material.Glass,Transparency=.08})
  end
  -- water droplets and ink drops
  bits(pos,OCTO_WATER,crit and 14 or 8,.24,13,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.12,Up=.7,Life=.75})
  bits(pos,{c[5],C(58,26,92),c[2]},crit and 9 or 5,.22,11,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.05,Up=.5,Life=.8})
  -- impact splatter: a blue / violet spray, an ink cloud, a ring, stone chips
  burst(pos,{c[1],c[2]},crit and 22 or 11,12,SPARK,dir)
  burst(pos,{C(48,24,78),C(20,10,32)},crit and 10 or 4,4,SMOKE,dir,{LightEmission=0})
  FX.Ring(pos,c[1],crit and 9 or 5,.4)
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 6 or 3,.22,14,Enum.Material.Slate,nil,{Up=.5,Life=.55})
  if not remote then
   splat(pos,dir,pick({c[5],C(52,24,84)}),crit and 1.7 or 1.1)
   for _=1,n(crit and 5 or(q==2 and 3 or 2))do -- poisonous bubbles
    local d=(dir*.6+Vector3.new(math.random()-.5,math.random()*.6+.3,math.random()-.5)).Unit
    octoBubble(pos+d*.5,.22+math.random()*.2,.9+math.random()*.5)
   end
  end
  if crit then
   local tilt=rad(math.random(-35,-15))
   slash(pos+f.UpVector*.25,c[2],2.4,tilt,.32) -- the tentacle lash
   slash(pos-f.UpVector*.2,c[3],1.9,tilt,.28)
   shock(pos,c[2],9,.3)
   FX.Ring(pos,c[5],7,.35)
   glyph(pos+Vector3.new(0,1.8,0),pick(OCTO_SPLOOSH),C(120,190,255),76,Vector3.new(0,1,0),1.1)
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick({'bloop','блуп','буль'}),c[1],26,Vector3.new(0,1,0),.6)
  end
 end
 -- Hand of Fate (concept sheet "ЭФФЕКТЫ / VFX"): СЛЕД УДАРА (purple crescents cutting through the impact and the claws
 -- raking it), ЧАСТИЦЫ (glowing purple crystals and sparkles), РАЗЛЁТ БЛОКОВ (stone and purple-stained voxel blocks flying
 -- out) and, on a CRIT, ПРОКЛЯТЫЙ ГЛАЗ: a huge glowing almond eye with a slit pupil and a ring of rays opens over the ore
 -- (cursedEye, also the inspect's glare and a small one on a perfect).
 local function cursedEye(pos,size,life)
  local f=camFacing(pos)
  local R,U=f.RightVector,f.UpVector
  local c=pal('Fate')
  local w=size*.08
  for _,sgn in ipairs({1,-1})do -- the almond: an upper and a lower arc
   local prev
   for i=0,8 do
    local x=-1+i/4
    local q=pos+R*x*size*.5+U*sgn*(1-x*x)^.8*size*.28
    if prev then line(prev,q,w,i%2==0 and c[3]or c[1],life)end
    prev=q
   end
  end
  local prev
  for i=0,10 do -- the iris
   local a=i/10*math.pi*2
   local q=pos+R*cos(a)*size*.18+U*sin(a)*size*.18
   if prev then line(prev,q,w*.8,c[3],life)end
   prev=q
  end
  line(pos+U*size*.17,pos-U*size*.17,w*1.3,C(24,6,34),life,{Material=Enum.Material.SmoothPlastic}) -- the slit pupil
  for i=1,n(12)do -- the rays
   local a=(i-.5)/12*math.pi*2
   local d=R*cos(a)+U*sin(a)*.75
   local l=(i%2==0 and .22 or .38)*size
   line(pos+d*size*.58,pos+d*(size*.58+l),w*(i%2==0 and .6 or .9),i%3==0 and C(255,236,255)or c[1],life)
  end
  shock(pos,c[1],size*1.5,life*.6)
 end
 self.CursedEye=cursedEye
 HIT.Fate=function(pos,dir,q,crit,remote)
  local c=pal('Fate')
  local f=camFacing(pos)
  shock(pos,C(250,220,255),crit and 6.5 or 3.6,.22)
  local tilt=rad(math.random(-35,-15))
  for k=0,(crit and 2 or 1)do slash(pos+f.UpVector*(k-.5)*.4,k==1 and c[3]or c[1],2.1+k*.35,tilt,.3+k*.03)end
  if not remote then scratches(pos,c[1],crit)end
  for i=1,n(crit and 10 or 6)do -- the impact flash's rays
   local a=(i-1)/(crit and 10 or 6)*math.pi*2+math.random()*.4
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   line(pos+d*.2,pos+d*(crit and 2.6 or 1.7)*(.7+math.random()*.5),i%2==0 and .07 or .12,i%3==0 and C(255,236,255)or c[1],.2+math.random()*.08)
  end
  -- glowing purple crystals and sparkles
  bits(pos,{c[1],c[3],C(200,110,255)},crit and 12 or 7,.22,14,Enum.Material.Neon,nil,{Up=.8})
  burst(pos,{c[1],c[3]},crit and 22 or 11,12,SPARK,dir)
  -- flying blocks: stone, and flesh-pink / purple-stained voxels
  bits(pos,{C(112,106,116),C(84,80,90),C(140,134,140)},crit and 9 or 5,.3,15,Enum.Material.Slate,nil,{Up=.6,Life=.7})
  if not remote then bits(pos,{c[4],c[1],C(122,36,170)},crit and 4 or 2,.26,12,Enum.Material.SmoothPlastic,nil,{Up=.7,Life=.75})end
  burst(pos,{c[2],C(30,10,50)},crit and 8 or 3,4,SMOKE,dir,{LightEmission=0})
  if crit then
   cursedEye(pos+f.LookVector*.6+Vector3.new(0,1.5,0),3.4,.9)
   FX.Ring(pos,c[1],9,.35)
   shock(pos,c[2],9,.3)
  elseif q==2 and not remote then
   cursedEye(pos+f.LookVector*.4+Vector3.new(0,.9,0),1.2,.5)
  end
 end
 -- Laughsaw (concept sheet "ЭФФЕКТЫ / VFX"): ИСКРЫ (a hot spray of sparks thrown along the blade's
 -- turn, falling under gravity, with bright streaks), СЛЕД УДАРА (two scarlet crescents cutting through
 -- the impact), ЧАСТИЦЫ (red and charcoal voxel cubes, little bone-white dice) and КРОВАВЫЕ БРЫЗГИ (dark
 -- red droplets and streaks spraying out, a splat clinging to the ore). A crit (concept "КРИТ"): a
 -- bigger spray, a third crescent, a red ring and the saw's laugh "HA-HA-HA!".
 HIT.Saw=function(pos,dir,q,crit,remote)
  local c=pal('Saw')
  local f=camFacing(pos)
  local tilt=rad(math.random(-30,-12))
  for k=0,(crit and 2 or 1)do slash(pos+f.UpVector*(k-.5)*.4,k==1 and C(255,120,110)or c[1],2+k*.4,tilt,.26+k*.04)end
  shock(pos,C(255,226,210),crit and 5.5 or 3,.2)
  -- sparks: streaks fanned along the blade's turn (to the camera's right) and a falling spray
  local side=f.RightVector
  for i=1,n(crit and 10 or 6)do
   local d=(side*.9+f.UpVector*(math.random()-.25)*1.1+dir*.4).Unit
   local a=pos+d*.2
   line(a,a+d*(.8+math.random()*(crit and 2.2 or 1.4)),.06+math.random()*.06,i%3==0 and C(255,250,220)or C(255,170,70),.16+math.random()*.08)
  end
  burst(pos,{C(255,220,150),C(255,80,40)},crit and 40 or 20,26,SPARK,(side+dir*.3).Unit,{Spread=Vector2.new(30,30),Acceleration=Vector3.new(0,-55,0),Lifetime=NumberRange.new(.3,.6)})
  -- particles: voxel cubes and dice
  bits(pos,{c[1],c[4],C(40,34,38),C(226,30,36)},crit and 10 or 6,.24,15,Enum.Material.SmoothPlastic,nil,{Up=.6})
  if not remote then bits(pos,{c[3],C(214,206,196)},crit and 4 or 2,.2,10,Enum.Material.SmoothPlastic,nil,{Up=.9,Life=.8})end
  -- blood splatter
  for _=1,n(crit and 7 or 4)do
   local a=math.random()*math.pi*2
   local d=(dir*.7+side*cos(a)*.8+f.UpVector*sin(a)*.6).Unit
   line(pos+d*.15,pos+d*(.7+math.random()*(crit and 1.6 or 1)),.08+math.random()*.08,pick({c[4],C(190,16,22),C(120,6,10)}),.28+math.random()*.1,{Material=Enum.Material.Glass})
  end
  bits(pos,{c[4],C(200,18,24),C(110,4,8)},crit and 9 or 5,.16,11,Enum.Material.Glass,Enum.PartType.Ball,{Up=.3,Life=.75})
  if not remote then splat(pos,dir,pick({c[4],C(170,10,16)}),crit and 1.5 or 1)end
  if crit then
   FX.Ring(pos,c[1],9,.35)
   glyph(pos+Vector3.new(0,1.6,0),'HA-HA-HA!',C(255,50,50),70,Vector3.new(0,1,0),1.1)
   for _=1,n(3)do glyph(pos,pick(SAW_LAUGH),pick({c[1],C(255,200,180)}),pick({24,30}),nil,.8)end
  elseif q==2 and not remote then
   glyph(pos+Vector3.new(0,.8,0),pick(SAW_LAUGH),C(255,70,70),26,Vector3.new(0,1,0),.6)
  end
 end
 -- Scarlet Anime Scythe (concept sheet "ЭФФЕКТЫ / VFX"): CUTTING TRAILS (parallel violet crescents
 -- slicing through the impact), PARTICLES (scarlet and violet voxel cubes), SYMBOLS (violet glyphs
 -- popping out) and the IMPACT FLASH (a pink-white star with radial rays). A crit: a crossing
 -- scarlet cut, a third crescent, a bigger star, a ring and 斬.
 local function starburst(pos,colors,rays,len,life)
  local f=camFacing(pos)
  for i=1,rays do
   local a=(i-1)/rays*math.pi*2+math.random()*.3
   local d=f.RightVector*cos(a)+f.UpVector*sin(a)
   local l=len*(i%2==0 and .55 or 1)*(.8+math.random()*.4)
   line(pos+d*.15,pos+d*l,i%2==0 and .07 or .13,colors[(i%#colors)+1],life)
  end
 end
 HIT.Anime=function(pos,dir,q,crit,remote)
  local c=pal('Anime')
  local f=camFacing(pos)
  local tilt=rad(math.random(-38,-14))
  for k=0,(crit and 2 or 1)do
   slash(pos+f.UpVector*(k-.5)*.42,k==1 and c[3]or c[1],2.2+k*.35,tilt,.28+k*.04)
  end
  if crit or q==2 then slash(pos,c[2],2.9,tilt+rad(100),.35)end
  shock(pos,C(255,222,252),crit and 6 or 3.2,.22)
  starburst(pos,{C(255,236,255),c[1],c[3]},n(crit and 12 or 8),crit and 3.2 or 2.1,.22)
  bits(pos,{c[4],C(170,20,40),c[1],C(120,40,200)},crit and 12 or 7,.24,16,Enum.Material.Neon,nil,{Up=.7})
  if not remote then bits(pos,{C(60,22,44),c[4]},crit and 6 or 3,.3,12,Enum.Material.SmoothPlastic,nil,{Up=.6})end
  burst(pos,{c[1],c[3]},crit and 22 or 10,12,SPARK,dir)
  for _=1,n(crit and 4 or 2)do glyph(pos,pick(SCYTHE_GLYPHS),pick({c[1],c[3],C(206,120,255)}),pick({24,30}),nil,.75)end
  if crit then
   FX.Ring(pos,c[1],9,.35)
   glyph(pos+Vector3.new(0,1.6,0),'斬',C(255,60,110),96,Vector3.new(0,1,0),1.1)
  end
 end
 -- Twin Claws (concept sheet "EFFECTS / VFX"): SLASH STREAKS (four parallel claw cuts raking across
 -- the impact in the colour of the hand that struck: scarlet right, violet left), METALLIC SPARKS (a
 -- hot spray falling under gravity, steel chips), the RUNE FLASH (右 / 左 flashing out of the impact)
 -- and IMPACT ON ORE (stone cubes and a glowing punch). The COMBO CROSS STRIKE (Anim.ClawMove 'X')
 -- and every crit: a scarlet and a violet set crossing in an X, both runes, a white flash and rings.
 local function rake(pos,color,tilt,life,core)
  local f=camFacing(pos)*CFrame.Angles(0,0,tilt)
  for i=1,4 do
   local off=(i-2.5)*.42
   local prev
   for k=0,3 do
    local s=k/3
    local q=(f*CFrame.new(off+sin(s*math.pi)*.22,(s-.5)*3.1,0)).Position
    if prev then
     local w=.07+.15*sin((s-.17)*math.pi)
     line(prev,q,w,color,life)
     if core then line(prev,q,w*.35,CLAW_HOT,life*.8)end
    end
    prev=q
   end
  end
 end
 local remoteSide=1
 HIT.Claws=function(pos,dir,q,crit,remote)
  local c=pal('Claws')
  local move=nil
  if not remote and ctx.Anim and ctx.Anim.ClawMove then move=ctx.Anim.ClawMove(player.Character)end
  if remote then remoteSide=-remoteSide;move=remoteSide>0 and'R'or'L'end
  local cross=crit or move=='X'
  local color=move=='L'and CLAW_VIOLET or CLAW_RED
  local core=not remote and not low()
  if cross then
   rake(pos,CLAW_RED,rad(-38),.34,core)
   rake(pos,CLAW_VIOLET,rad(38),.34,core)
   shock(pos,CLAW_HOT,crit and 7 or 5,.24)
   FX.Ring(pos,CLAW_RED,crit and 10 or 8,.35)
   if crit then FX.Ring(pos,CLAW_VIOLET,7,.3)end
   glyph(pos+Vector3.new(-.7,.7,0),'右',CLAW_RED,crit and 46 or 36,Vector3.new(-.4,1,0),.7)
   glyph(pos+Vector3.new(.7,.7,0),'左',CLAW_VIOLET,crit and 46 or 36,Vector3.new(.4,1,0),.7)
  else
   rake(pos,color,rad(move=='L'and 32 or -32)+rad(math.random(-6,6)),.28,core)
   shock(pos,color,q==2 and 3.6 or 2.8,.2)
   glyph(pos+Vector3.new(0,.6,0),move=='L'and'左'or'右',color,q==2 and 36 or 30,Vector3.new(0,1,0),.55)
  end
  -- metallic sparks and steel chips
  burst(pos,{C(255,240,210),c[4]},cross and 30 or 14,24,SPARK,dir,{Spread=Vector2.new(35,35),Acceleration=Vector3.new(0,-55,0),Lifetime=NumberRange.new(.25,.5)})
  bits(pos,{C(206,206,214),C(150,150,160)},cross and 5 or 2,.14,20,Enum.Material.Metal)
  -- impact on ore: stone cubes and a glowing fleck of each hand's colour
  if not remote then bits(pos,{C(122,118,126),C(84,80,90),C(160,156,164)},cross and 7 or 3,.26,12,Enum.Material.Slate,nil,{Up=.6})end
  bits(pos,cross and{CLAW_RED,CLAW_VIOLET}or{color},cross and 6 or 3,.12,16,Enum.Material.Neon,nil,{Up=.7})
 end
 -- Butterfly Catcher (concept sheet "ЭФФЕКТЫ / VFX"): УДАРНЫЙ ЭФФЕКТ a white-gold starburst flash with
 -- pastel rays and four-point stars, БАБОЧКИ И СВЕТЛЯЧКИ glowing voxel butterflies fluttering up out
 -- of the ore and firefly sparks, ЧАСТИЦЫ pastel sparkles. A crit: a bigger flash, two rings of light
 -- and a whole flock.
 HIT.Butterfly=function(pos,dir,q,crit,remote)
  local c=pal('Butterfly')
  shock(pos,C(255,250,226),crit and 6 or 3.4,.24)
  starburst(pos,{C(255,252,236),C(255,226,120),c[1],c[3]},n(crit and 12 or 8),crit and 2.8 or 1.8,.24)
  for _=1,n(remote and 1 or(crit and 7 or(q==2 and 4 or 3)))do
   local d=(dir*.6+Vector3.new(math.random()-.5,math.random()*.8+.4,math.random()-.5)).Unit
   flyer(pos+d*.3,pick(NET_WINGS),d*(3+math.random()*3),1.1+math.random()*.8,.8+math.random()*.5)
  end
  bits(pos,{C(255,240,140),C(214,255,150),C(255,252,214)},crit and 10 or 5,.12,6,Enum.Material.Neon,Enum.PartType.Ball,{Up=1.3,Life=.9})
  burst(pos,{c[1],C(255,255,255)},crit and 22 or 12,9,SPARK,dir)
  for _=1,n(crit and 4 or 2)do glyph(pos,pick({'✦','✧','✦'}),pick(NET_WINGS),pick({22,28}),nil,.8)end
  if crit then FX.Ring(pos,C(190,230,255),9,.4);FX.Ring(pos,C(255,190,235),6,.32)end
 end
 -- TV-Head (concept sheet "EFFECTS"): static tearing across the impact, flying pixels, a static
 -- blast (flat ring + radial streaks) and glitch cubes hanging in the air for a moment.
 HIT.TV=function(pos,dir,q,crit,remote)
  local c=pal('TV')
  local greens={c[1],c[2],c[3]}
  local cam=workspace.CurrentCamera
  local right=cam and cam.CFrame.RightVector or Vector3.new(1,0,0)
  local upv=cam and cam.CFrame.UpVector or Vector3.new(0,1,0)
  for _=1,n(crit and 8 or 5)do
   local o=pos+right*(math.random()-.5)*2.4+upv*(math.random()-.5)*1.8
   local l=.5+math.random()*(crit and 2.6 or 1.8)
   local col=math.random()<.15 and c[4]or(math.random()<.3 and C(240,255,240)or pick(greens))
   line(o-right*l*.5,o+right*l*.5,.06+math.random()*.12,col,.14+math.random()*.12)
  end
  bits(pos,{c[1],c[2],c[1],C(235,255,225)},crit and 16 or 8,.28,18,Enum.Material.Neon,nil,{Up=.6})
  bits(pos,{c[1]},crit and 5 or 2,.55,11,Enum.Material.Glass,nil,{Transparency=.3,Up=.9,Life=.9})
  FX.Ring(pos,c[1],crit and 10 or 6,.35)
  if not remote then
   for i=1,n(crit and 8 or 4)do
    local a=math.random()*math.pi*2
    local d=Vector3.new(cos(a),(math.random()-.3)*.6,sin(a)).Unit
    line(pos+d*.4,pos+d*(1.4+math.random()*1.4),.07,i%2==0 and C(240,255,240)or c[2],.2)
   end
   bits(pos+Vector3.new(0,1,0),{c[1],c[2]},crit and 4 or 2,.4,3.5,Enum.Material.Neon,nil,{Up=1.6,Life=1.1,Transparency=.2})
  end
  for _=1,n(crit and 3 or 1)do glyph(pos,pick({'▣','■','▒','ERR'}),pick(greens),24,nil,.55)end
  if crit then
   shock(pos,c[1],8,.3)
   glyph(pos+Vector3.new(0,1.6,0),'NO SIGNAL',c[1],56,Vector3.new(0,1,0),1)
  end
 end

 -- theme, world position, surface normal, quality (1/2), crit, remote (another player's hit)
 function self.Hit(theme,pos,dir,quality,crit,remote)
  local fn=HIT[theme]or HIT.Wood
  if remote and low()then return end
  local ok,err=pcall(fn,pos,dir or Vector3.new(0,1,0),quality,crit,remote)
  if not ok and ctx.Report then ctx.Report('PickFX '..tostring(theme)..': '..tostring(err))end
  if crit and not remote then shock(pos,pal(theme)[1],7,.3)end
 end
 function self.Palette(theme)return pal(theme)end

 -- LIVING MODELS --------------------------------------------------------------------------------
 local tracked={} -- model -> entry
 local function build(model,anchored)
  -- A pickaxe Model: the held one welded to a character (MiningHeldPickaxe / MiningHeldPickaxeL,
  -- hand or back) or an anchored preview. The inventory Tool carries no visible parts.
  local root=(model:IsA('Model')and model.PrimaryPart)or model:FindFirstChild('Handle')
  if not root then return nil end
  local e={Model=model,Root=root,Anchored=anchored,Parts={},Rainbow={},Pulse={},Flicker={},Drips={},Goo={},Hit=0,Theme=model:GetAttribute('Theme')or'Wood',
   State={Run=0,Insp=0,Spin=0},InspectUntil=0}
  for _,d in ipairs(model:GetDescendants())do
   if d:IsA('BasePart')then
    local kinds=d:GetAttribute('PickAnim')
    if kinds then
     local list={}
     for k in string.gmatch(kinds,'[^,]+')do if MOTIONS[k]then table.insert(list,MOTIONS[k])end end
     local joint=d:GetAttribute('PickJoint')
     local base=d:GetAttribute('PickBase')
     table.insert(e.Parts,{Part=d,Motor=d:FindFirstChild('PickJoint'),Motions=list,Phase=d:GetAttribute('PickPhase')or 0,
      Joint=typeof(joint)=='Vector3'and CFrame.new(joint)or(typeof(base)=='CFrame'and CFrame.new(base.Position)or CFrame.identity),
      Base=typeof(base)=='CFrame'and base or CFrame.identity,Pop=d:GetAttribute('PickPop'),
      Amp=d:GetAttribute('PickAmp')or 0,DropK=d:GetAttribute('PickDropK')or 1,Hang=d:GetAttribute('PickHang')})
    end
    if d:GetAttribute('PickRainbow')then table.insert(e.Rainbow,{Part=d,Phase=d:GetAttribute('PickPhase')or 0})end
    if d:GetAttribute('PickPulse')then table.insert(e.Pulse,{Part=d,Base=d.Transparency})end
    if d:GetAttribute('PickFlicker')then table.insert(e.Flicker,d)end
    if d:GetAttribute('PickDrip')then table.insert(e.Drips,{Part=d,Phase=d:GetAttribute('PickPhase')or 0})end
    if d:GetAttribute('PickGoo')then table.insert(e.Goo,{Part=d,Phase=d:GetAttribute('PickPhase')or 0,Base=d.Transparency})end
   end
  end
  -- Gummy Horror: its head (run drips) and the horn tips (sticky drops flung on a swing).
  if model:GetAttribute('Kind')=='Gummy'then e.Gummy={Head=model:FindFirstChild('GummySkull'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB')}end
  -- Rotten Slime Slug: the glow (light), the falling drops emitter, the drops (puddles fall from them), the
  -- head (inspect slime), the blade tips (trail ends, drops flung on a swing).
  if model:GetAttribute('Kind')=='Slug'then
   local g=model:FindFirstChild('SlugGlow')
   local under=model:FindFirstChild('SlugDrips')
   local drops={}
   for _,d in ipairs(model:GetChildren())do
    if d:IsA('BasePart')and(d.Name=='SlimeLiveDrop'or d.Name=='BladeDripDrop'or d.Name=='SkirtDripDrop')then table.insert(drops,d)end
   end
   e.Slug={Glow=g,Light=g and g:FindFirstChild('SlugLight'),Drips=under and under:FindFirstChildOfClass('ParticleEmitter'),Drops=drops,
    Head=model:FindFirstChild('SlugFace'),Mouth=model:FindFirstChild('Mouth'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),
    NextDrop=os.clock()+1+math.random(),NextRun=0,InspectAt=-100,Fired={},Rate=-1,
    EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and os.clock()or -100}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Slug then e.Slug.EquipAt=os.clock();e.Slug.Fired.Equip=nil end
    end)
   end
  end
  -- Toothy Alarm Clock: the red glow (light, sparks), the mouth dial (inspect / idle effects), the head's sides
  -- (trail ends, sparks on a swing); the hand / key / tick angles it keeps; it rings once on the draw.
  if model:GetAttribute('Kind')=='Alarm'then
   local g=model:FindFirstChild('AlarmGlow')
   local sp=model:FindFirstChild('AlarmSparks')
   local now=os.clock()
   e.Alarm={Glow=g,Light=g and g:FindFirstChild('AlarmLight'),Sparks=sp and sp:FindFirstChildOfClass('ParticleEmitter'),Head=model:FindFirstChild('MawDial'),
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),Min=math.random()*6,Hour=math.random()*6,Key=0,TickAcc=math.random()*60,
    InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,RattleUntil=0,NextIdle=now+3+math.random()*3,NextRun=0,Fired={},Rate=-1}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Alarm then e.Alarm.EquipAt=os.clock();e.Alarm.Fired.Equip=nil end
    end)
   end
  end
  -- Zombie-Frankenstein: the machine eye's light, the vial's light, the coil sparks and the slime drips, the coil tip
  -- (lightning arcs start there), the skull (arcs end there), the seam parts (the lightning runs along them, ZombieSeam
  -- = their order), the blade point and the claw point (trail ends).
  if model:GetAttribute('Kind')=='Zombie'then
   local g=model:FindFirstChild('ZombieGlow')
   local jg=model:FindFirstChild('ZombieJarGlow')
   local sp=model:FindFirstChild('ZombieSparks')
   local dr=model:FindFirstChild('ZombieDrips')
   local seams={}
   for _,d in ipairs(model:GetDescendants())do
    if d:IsA('BasePart')and d:GetAttribute('ZombieSeam')then table.insert(seams,{Part=d,K=d:GetAttribute('ZombieSeam'),Color=d.Color,Material=d.Material,Lit=false})end
   end
   local now=os.clock()
   e.Zombie={Light=g and g:FindFirstChild('ZombieLight'),JarLight=jg and jg:FindFirstChild('ZombieJarLight'),Sparks=sp and sp:FindFirstChildOfClass('ParticleEmitter'),
    Drips=dr and dr:FindFirstChildOfClass('ParticleEmitter'),Coil=model:FindFirstChild('CoilTip'),Head=model:FindFirstChild('ZombieSkull'),Seams=seams,
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,
    SpasmUntil=0,NextSpasm=now+4+math.random()*5,NextArc=now+1+math.random()*2,NextRun=0,WaveAt=-100,WaveLen=.4,Bolt=0,Fired={},Rate=-1,DripRate=-1}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Zombie then e.Zombie.EquipAt=os.clock();e.Zombie.Fired.Equip=nil end
    end)
   end
  end
  -- Clown Chronomord: the clock's warm light and gold sparks, the skull (laughs float off it), the dial (the rewind),
  -- the bells (trail ends); the hand / gear angles it keeps; it honks and giggles on the draw.
  if model:GetAttribute('Kind')=='Clown'then
   local g=model:FindFirstChild('ChronoGlow')
   local sp=model:FindFirstChild('ChronoSparks')
   local now=os.clock()
   e.Chrono={Light=g and g:FindFirstChild('ChronoLight'),Sparks=sp and sp:FindFirstChildOfClass('ParticleEmitter'),Head=model:FindFirstChild('ClownSkull'),
    Dial=model:FindFirstChild('Dial'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),
    Min=math.random()*6,Hour=math.random()*6,Gear=0,InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,
    GiggleUntil=0,NextGiggle=now+5+math.random()*5,NextTick=now+3+math.random()*3,NextRun=0,Fired={},Rate=-1}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Chrono then e.Chrono.EquipAt=os.clock();e.Chrono.Fired.Equip=nil end
    end)
   end
  end
  -- Nasty Octopus: the eye (it looks around, stares at you; its warm light), the drip emitter, the static drops (puddles fall
  -- from them), the cursed pearl, the ink sac, the blade tips (trail ends, water sprayed on a swing); it slurps in on the draw.
  if model:GetAttribute('Kind')=='Octopus'then
   local g=model:FindFirstChild('OctoGlow')
   local under=model:FindFirstChild('OctoDrips')
   local drops={}
   for _,d in ipairs(model:GetChildren())do if d:IsA('BasePart')and d.Name=='DripDrop'then table.insert(drops,d)end end
   local now=os.clock()
   e.Octo={Light=g and g:FindFirstChild('OctoLight'),Drips=under and under:FindFirstChildOfClass('ParticleEmitter'),Drops=drops,
    Eye=model:FindFirstChild('EyeBall'),Pearl=model:FindFirstChild('OctoPearl'),Sac=model:FindFirstChild('InkSac'),
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),TX=0,TY=0,NextLook=now+.5,Stare=false,
    InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,NextMood=now+4+math.random()*4,
    NextDrop=now+1+math.random(),NextRun=0,Fired={},Rate=-1}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Octo then e.Octo.EquipAt=os.clock();e.Octo.Fired.Equip=nil end
    end)
   end
  end
  -- Hand of Fate: the eye (it looks round, glares at you; its purple light), the motes and the drip emitter, the slime drops
  -- (puddles fall from them), the claw tips (trail ends, sparks on a swing); it opens its eye and grabs on the draw.
  if model:GetAttribute('Kind')=='Fate'then
   local g=model:FindFirstChild('FateGlow')
   local under=model:FindFirstChild('FateDrips')
   local drops={}
   for _,d in ipairs(model:GetChildren())do if d:IsA('BasePart')and d.Name=='DripDrop'then table.insert(drops,d)end end
   local now=os.clock()
   e.Fate={Light=g and g:FindFirstChild('FateLight'),Motes=g and g:FindFirstChild('FateMotes'),Drips=under and under:FindFirstChildOfClass('ParticleEmitter'),
    Drops=drops,Eye=model:FindFirstChild('EyeCore'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),TX=0,TY=0,NextLook=now+.5,Stare=false,
    InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,NextMood=now+5+math.random()*4,
    NextBlink=now+1+math.random()*2,BlinkAt=-100,TwitchUntil=0,NextDrop=now+1.5+math.random(),NextRun=0,Fired={},Rate=-1,DripRate=-1,Flash=0}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Fate then e.Fate.EquipAt=os.clock();e.Fate.Fired.Equip=nil end
    end)
   end
  end
  -- Ponycorn: the horn (glow, inspect charge), its halo, the head (floating stars) and the fin tips.
  if model:GetAttribute('Kind')=='Ponycorn'then
   local core=model:FindFirstChild('HornCore')
   local halo={}
   for _,d in ipairs(model:GetChildren())do if d.Name=='HornHalo'and d:IsA('BasePart')then table.insert(halo,d)end end
   e.Pony={Core=core,Light=core and core:FindFirstChild('HornGlow'),Halo=halo,Head=model:FindFirstChild('PonySkull'),
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),NextFloat=os.clock()+1+math.random()*2,NextMote=0,Charging=false,
    LightBase=core and core:FindFirstChild('HornGlow')and core.HornGlow.Range or 8}
  end
  -- Scarlet Anime Scythe: the glyphs (energy wave), the inspect ring, the eye and blade lights, the tip.
  if model:GetAttribute('Kind')=='Scythe'then
   local runes,halo={},{}
   for _,d in ipairs(model:GetDescendants())do
    if d:IsA('BasePart')then
     if d:GetAttribute('PickRune')then table.insert(runes,{Part=d,T=d:GetAttribute('PickRune'),Color=d.Color})
     elseif d.Name=='ScytheHalo'then table.insert(halo,d)end
    end
   end
   local eye=model:FindFirstChild('EyeGlow',true);local blade=model:FindFirstChild('BladeGlow',true)
   e.Scythe={Runes=runes,Halo=halo,Eye=eye,EyeBase=eye and eye.Brightness or 1,Blade=blade,BladeBase=blade and blade.Brightness or 1,
    Head=model:FindFirstChild('ScytheCore'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),
    NextFloat=os.clock()+1.5+math.random()*2,Wave=-10,Charging=false}
  end
  -- Laughsaw: the hub light and embers, the blade's edge (TrailB: sparks), the head (laughs float off it).
  if model:GetAttribute('Kind')=='Saw'then
   local g=model:FindFirstChild('SawGlow')
   e.Saw={Glow=g,Light=g and g:FindFirstChild('SawLight'),Embers=g and g:FindFirstChild('SawEmbers'),Head=model:FindFirstChild('SawCore'),
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),NextFloat=os.clock()+3+math.random()*3,InspectAt=-100,Fired={},Rate=-1,EmberRate=-1,Angle=0}
  end
  -- LEGO Hand: the glow (light, sparkles), the fingertip / thumb (trail ends); the hand snaps in on the draw.
  if model:GetAttribute('Kind')=='Lego'then
   local g=model:FindFirstChild('LegoGlow')
   e.Lego={Glow=g,Light=g and g:FindFirstChild('LegoLight'),Sparkles=g and g:FindFirstChild('LegoSparkles'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),
    NextFloat=os.clock()+2+math.random()*3,NextRun=0,InspectAt=-100,EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and os.clock()or -100,Fired={},Rate=-1,Step=0}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Lego then e.Lego.EquipAt=os.clock()end
    end)
   end
  end
  -- Pickaxe 67: the head's glow (light, sparks), the red piping (it flashes on a glitch), the trail ends;
  -- the digits glitch in on the draw.
  if model:GetAttribute('Kind')=='SixSeven'then
   local g=model:FindFirstChild('SixGlow')
   local edges={}
   for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')and d:GetAttribute('SixEdge')then table.insert(edges,{Part=d,Color=d.Color})end end
   local now=os.clock()
   e.Six={Glow=g,Light=g and g:FindFirstChild('SixLight'),Sparks=g and g:FindFirstChild('SixSparks'),TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),
    Edges=edges,NextGlitch=now+1+math.random()*2,GlitchUntil=0,JitterAt=0,Glitch=0,Dial=0,DialTarget=0,InspectAt=-100,
    EquipAt=(not anchored and model:GetAttribute('Mount')=='Hand')and now or -100,Fired={},Rate=-1,SparkRate=-1,NextFloat=now+2+math.random()*2,NextRun=0}
   if not anchored then
    model:GetAttributeChangedSignal('Mount'):Connect(function()
     if model:GetAttribute('Mount')=='Hand'and e.Six then e.Six.EquipAt=os.clock();e.Six.Fired.Boot=nil end
    end)
   end
  end
  -- Butterfly Catcher: the dome slices (iridescence), the twinkling stars / fireflies, the film's light
  -- and sparkles, the hoop centre (butterflies escape from it) and the hoop sides.
  if model:GetAttribute('Kind')=='Net'then
   local iri,tw={},{}
   for _,d in ipairs(model:GetDescendants())do
    if d:IsA('BasePart')then
     if d:GetAttribute('NetIri')then table.insert(iri,{Part=d,K=d:GetAttribute('NetIri')})end
     if d:GetAttribute('NetTwinkle')then table.insert(tw,{Part=d,Phase=d:GetAttribute('NetTwinkle')})end
    end
   end
   local g=model:FindFirstChild('NetGlow')
   e.Net={Iri=iri,Twinkle=tw,Glow=g,Light=g and g:FindFirstChild('NetLight'),Sparks=g and g:FindFirstChild('NetFireflies'),
    TipA=root:FindFirstChild('TrailA'),TipB=root:FindFirstChild('TrailB'),NextFloat=os.clock()+1.5+math.random()*2,NextRun=0,InspectAt=-100,Fired={},Rate=-1}
  end
  -- Twin Claws: one entry per gauntlet (TwinSide 1 right / -1 left): its rune strokes, lights, the
  -- vent smoke, the ambient sparks and (held only) an air scratch trail on every claw tip.
  if model:GetAttribute('Kind')=='Claws'and model:GetAttribute('TwinSide')then
   local side=model:GetAttribute('TwinSide')
   local tw={Side=side,Runes={},Trails={},Snaps={},Accent=side>0 and CLAW_RED or CLAW_VIOLET,DeployAt=anchored and -100 or os.clock(),
    ClawIn=anchored and 0 or 1,Gear=0,InspectAt=-100,Fired={},Rate=-1}
   for _,d in ipairs(model:GetDescendants())do
    if d:IsA('BasePart')and d:GetAttribute('TwinRune')then table.insert(tw.Runes,{Part=d,Color=d.Color})end
    if d.Name=='ClawTrailA'and d:IsA('Attachment')then table.insert(tw.Snaps,d)end
   end
   tw.Plate=model:FindFirstChild('RunePlate')
   tw.Light=model:FindFirstChild('ClawLight',true);tw.LightBase=tw.Light and tw.Light.Brightness or 1
   tw.RuneLight=model:FindFirstChild('RuneLight',true);tw.RuneBase=tw.RuneLight and tw.RuneLight.Brightness or 1
   tw.Vent=model:FindFirstChild('TwinVentSmoke',true)
   local glowPart=model:FindFirstChild('ClawGlow')
   tw.Ambient=glowPart and glowPart:FindFirstChildOfClass('ParticleEmitter')
   if not anchored then
    local hotEnd=tw.Accent:Lerp(Color3.new(1,1,1),.55)
    for _,a in ipairs(tw.Snaps)do
     local b=a.Parent:FindFirstChild('ClawTrailB')
     if b then
      local tr=Instance.new('Trail');tr.Name='ClawScratch';tr.Attachment0=a;tr.Attachment1=b
      tr.Lifetime=.2;tr.MinLength=.05;tr.LightEmission=1;tr.FaceCamera=false;tr.Enabled=false
      tr.Color=ColorSequence.new(hotEnd,tw.Accent)
      tr.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})
      tr.WidthScale=NumberSequence.new(1,.15);tr.Parent=a.Parent
      table.insert(tw.Trails,tr)
     end
    end
   end
   e.Twin=tw
  end
  local screen=model:FindFirstChild('ScreenGui',true)
  if screen then e.Noise=screen:FindFirstChild('Noise');e.Face=e.Noise and e.Noise:FindFirstChild('Face')end
  -- TV-Head's screen (MiningModels tvScreen): static blocks, ghost faces, the inspect face.
  if e.Noise and e.Noise:FindFirstChild('Static')and e.Noise:FindFirstChild('FaceInspect')then
   local now=os.clock()
   e.TV={Gui=screen,Noise=e.Noise,Face=e.Face,Eyes=e.Face and e.Face:FindFirstChild('Eyes'),Inspect=e.Noise.FaceInspect,
    GhostA=e.Noise:FindFirstChild('GhostA'),GhostB=e.Noise:FindFirstChild('GhostB'),Static=e.Noise.Static:GetChildren(),
    Roll=e.Noise:FindFirstChild('Roll'),Light=screen.Parent and screen.Parent:FindFirstChild('ScreenGlow'),
    Case=model:FindFirstChild('TVCase'),NextStatic=0,NextGlitch=now+1,GlitchUntil=0,NextBlink=now+2,BlinkUntil=0}
  end
  -- Trail between the head's two ends (held models only): the swing and the run leave a streak.
  if not anchored then
   local a,b=root:FindFirstChild('TrailA'),root:FindFirstChild('TrailB')
   if a and b then
    local colors=pal(e.Theme)
    local tr=Instance.new('Trail');tr.Name='PickTrail';tr.Attachment0=a;tr.Attachment1=b
    tr.Lifetime=.28;tr.MinLength=.05;tr.LightEmission=.9;tr.FaceCamera=false
    tr.Color=ColorSequence.new(colors[1],colors[2]or colors[1])
    if e.Gummy then -- sticky pink -> lemon -> lime streak (concept "СЛЕДЫ УДАРОВ И СЛИЗИ")
     tr.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,colors[1]),ColorSequenceKeypoint.new(.5,colors[3]),ColorSequenceKeypoint.new(1,colors[2])})
     tr.Lifetime=.32;tr.LightEmission=.6
    end
    if e.Slug then -- a slimy acid -> lime -> olive streak (concept "В руке (Trail)")
     tr.Color=SLUG_TRAIL;tr.Lifetime=.34;tr.LightEmission=.55
    end
    if e.Alarm then -- a white-hot -> scarlet streak (concept "СЛЕД УДАРА"), red sparks off both sides of the head
     tr.Color=ALARM_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='AlarmTrailSpark';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.3,.6);pe.Speed=NumberRange.new(.5,2);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2.5
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,236,220)),ColorSequenceKeypoint.new(1,C(240,30,30))})
      pe.Parent=att
      e.Alarm.Emitters=e.Alarm.Emitters or{};table.insert(e.Alarm.Emitters,pe)
     end
    end
    if e.Zombie then -- a blue-white -> green electric streak (concept "В руке (Trail)"), blue sparks off both points
     tr.Color=ZOMBIE_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='ZombieTrailSpark';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.2,.45);pe.Speed=NumberRange.new(1,3.5);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=3
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.26),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(220,244,255)),ColorSequenceKeypoint.new(1,C(60,150,255))})
      pe.Parent=att
      e.Zombie.Emitters=e.Zombie.Emitters or{};table.insert(e.Zombie.Emitters,pe)
     end
    end
    if e.Chrono then -- a white-hot -> scarlet arc (concept "УДАР"), gold / red sparks off both bells
     tr.Color=CHRONO_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='ChronoTrailSpark';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.3,.6);pe.Speed=NumberRange.new(.5,2);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2.5
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,226,140)),ColorSequenceKeypoint.new(1,C(236,40,48))})
      pe.Parent=att
      e.Chrono.Emitters=e.Chrono.Emitters or{};table.insert(e.Chrono.Emitters,pe)
     end
    end
    if e.Octo then -- a wet white-cyan -> blue -> violet lash (concept "TENTACLE LASH"), water sprayed off both blade tips
     tr.Color=OCTO_TRAIL;tr.Lifetime=.3;tr.LightEmission=.8
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='OctoTrailSpray';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.3,.6);pe.Speed=NumberRange.new(1,3);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2;pe.Acceleration=Vector3.new(0,-20,0)
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.24),NumberSequenceKeypoint.new(1,.05)});pe.LightEmission=.5
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(220,244,255)),ColorSequenceKeypoint.new(1,C(90,150,250))})
      pe.Parent=att
      e.Octo.Emitters=e.Octo.Emitters or{};table.insert(e.Octo.Emitters,pe)
     end
    end
    if e.Fate then -- a white-pink -> purple -> violet arc (concept "УДАР"), purple sparks off the thumb claw and the little finger's claw
     tr.Color=FATE_TRAIL;tr.Lifetime=.32;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='FateTrailSpark';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.3,.6);pe.Speed=NumberRange.new(.5,2);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2.5
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(250,220,255)),ColorSequenceKeypoint.new(1,C(155,47,214))})
      pe.Parent=att
      e.Fate.Emitters=e.Fate.Emitters or{};table.insert(e.Fate.Emitters,pe)
     end
    end
    if e.Pony then -- pink -> yellow streak in the hand, a rainbow trail while running (concept "В руке" / "Бег")
     tr.Color=PONY_TRAIL;tr.Lifetime=.32;tr.LightEmission=1
     -- glitter at both fin tips: a puff on every swing, a stream while running (PonyTrailSparkle)
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='PonyTrailSparkle';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.45,.9);pe.Speed=NumberRange.new(.4,1.4);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.32),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,140,215)),ColorSequenceKeypoint.new(.5,C(255,240,140)),ColorSequenceKeypoint.new(1,C(160,215,255))})
      pe.Parent=att
      e.Pony.Emitters=e.Pony.Emitters or{};table.insert(e.Pony.Emitters,pe)
     end
    end
    if e.Net then -- a white -> sky -> pink streak (concept "УДАР"), sparkles off both sides of the hoop
     tr.Color=NET_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='NetTrailSparkle';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.4,.8);pe.Speed=NumberRange.new(.3,1.2);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.28),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,244,160)),ColorSequenceKeypoint.new(.5,C(160,220,255)),ColorSequenceKeypoint.new(1,C(255,170,230))})
      pe.Parent=att
      e.Net.Emitters=e.Net.Emitters or{};table.insert(e.Net.Emitters,pe)
     end
    end
    if e.Lego then -- a golden arc (concept "УДАР"), sparkles off the fingertip and the thumb
     tr.Color=LEGO_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='LegoTrailSparkle';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.35,.7);pe.Speed=NumberRange.new(.4,1.6);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2.5
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,250,210)),ColorSequenceKeypoint.new(1,C(255,190,30))})
      pe.Parent=att
      e.Lego.Emitters=e.Lego.Emitters or{};table.insert(e.Lego.Emitters,pe)
     end
    end
    if e.Six then -- a red arc (concept "УДАР"), red sparks off both ends of the head
     tr.Color=SIX_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     for _,att in ipairs({a,b})do
      local pe=Instance.new('ParticleEmitter');pe.Name='SixTrailSpark';pe.Texture=SPARK;pe.Rate=0
      pe.Lifetime=NumberRange.new(.3,.6);pe.Speed=NumberRange.new(.5,1.8);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=2.5
      pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
      pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,240,240)),ColorSequenceKeypoint.new(1,C(255,30,44))})
      pe.Parent=att
      e.Six.Emitters=e.Six.Emitters or{};table.insert(e.Six.Emitters,pe)
     end
    end
    if e.Saw then -- a scarlet streak (concept "СЛЕД УДАРА"), sparks off the blade's edge
     tr.Color=SAW_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     local pe=Instance.new('ParticleEmitter');pe.Name='SawSparks';pe.Texture=SPARK;pe.Rate=0
     pe.Lifetime=NumberRange.new(.25,.5);pe.Speed=NumberRange.new(4,9);pe.SpreadAngle=Vector2.new(35,35);pe.Drag=2
     pe.Acceleration=Vector3.new(0,-40,0);pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)})
     pe.LightEmission=1;pe.Color=SAW_SPARK;pe.Parent=b;e.Saw.Emitter=pe
    end
    if e.Scythe then -- a violet crescent streak behind the blade (concept "Удар"), sparks off the point
     tr.Color=SCYTHE_TRAIL;tr.Lifetime=.3;tr.LightEmission=1
     local pe=Instance.new('ParticleEmitter');pe.Name='ScytheTrailSpark';pe.Texture=SPARK;pe.Rate=0
     pe.Lifetime=NumberRange.new(.35,.7);pe.Speed=NumberRange.new(.5,2);pe.SpreadAngle=Vector2.new(180,180);pe.Drag=3
     pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,0)});pe.LightEmission=1
     pe.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,C(255,170,250)),ColorSequenceKeypoint.new(1,C(170,60,255))})
     pe.Parent=b;e.Scythe.Emitter=pe
    end
    tr.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,1)})
    tr.WidthScale=NumberSequence.new(1,.2);tr.Parent=root
    e.Trail=tr
    -- Equip / unequip retargets the model's HandGrip (back <-> hand) and moves it in one frame:
    -- pause the trail for that frame so it never draws a streak across the body.
    local token=0
    local function jumped()
     token+=1;local mine=token
     tr.Enabled=false;pcall(function()tr:Clear()end)
     task.delay(.15,function()if token==mine and tr.Parent then tr.Enabled=true end end)
    end
    local function watchGrip(grip)
     if not grip:IsA('JointInstance')then return end
     grip:GetPropertyChangedSignal('Part0'):Connect(jumped)
     grip:GetPropertyChangedSignal('C0'):Connect(jumped)
    end
    local grip=root:FindFirstChild('HandGrip')
    if grip then watchGrip(grip)end
    root.ChildAdded:Connect(function(c)if c.Name=='HandGrip'then watchGrip(c);jumped()end end)
   end
  end
  return e
 end
 function self.Track(model,anchored)
  if tracked[model]then return tracked[model]end
  local e=build(model,anchored)
  if not e then return nil end
  tracked[model]=e
  model.AncestryChanged:Connect(function()if not model:IsDescendantOf(game)then tracked[model]=nil end end)
  return e
 end
 function self.Untrack(model)tracked[model]=nil end
 -- Exaggerates the motion of a character's held pickaxe(s) for a moment (every strike).
 function self.HitPulse(character,strength)
  if not character then return end
  for _,c in ipairs(character:GetChildren())do
   if c:IsA('Model')and(c.Name=='MiningHeldPickaxe'or c.Name=='MiningHeldPickaxeL')then
    local e=tracked[c]or self.Track(c,false)
    if e then
     local s=strength or 1
     -- Twin Claws: the gauntlet that struck (Anim.ClawMove: R / L, both on the cross strike) gets the
     -- full pulse (claws out, scratch trails, a puff out of its tubes), the other one a little.
     if e.Twin then
      local move=ctx.Anim and ctx.Anim.ClawMove and ctx.Anim.ClawMove(character)
      local mine=move==nil or move=='X'or move==(e.Twin.Side>0 and'R'or'L')
      if mine then
       if e.Twin.Vent and e.Twin.Vent.Parent and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then e.Twin.Vent:Emit(3)end
      else s*=.25 end
     end
     e.Hit=math.max(e.Hit,s)
     -- Ponycorn: the swing leaves glitter at both fin tips and, for your own swing, a little heart.
     if e.Pony and e.Pony.Emitters and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Pony.Emitters)do if pe.Parent then pe:Emit(5)end end
      local tip=math.random()<.5 and e.Pony.TipA or e.Pony.TipB
      if character==player.Character and tip and tip.Parent then glyph(tip.WorldPosition,pick({'♥','✦','★'}),pick(PONY_HUES),18,nil,.7)end
     end
     -- Butterfly Catcher: the scoop leaves sparkles off the hoop and, for your own swing, a butterfly.
     if e.Net and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Net.Emitters or{})do if pe.Parent then pe:Emit(4)end end
      local g=e.Net.Glow
      if character==player.Character and g and g.Parent then flyer(g.Position,pick(NET_WINGS),Vector3.new(math.random()-.5,1.2,math.random()-.5)*2,1.1,.7)end
     end
     -- Scarlet Anime Scythe: sparks off the point and an energy wave through the glyphs.
     if e.Scythe then
      e.Scythe.Wave=os.clock()
      if e.Scythe.Emitter and e.Scythe.Emitter.Parent and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then e.Scythe.Emitter:Emit(6)end
     end
     -- LEGO Hand: sparkles off the fingertip and the thumb as the hand clacks.
     if e.Lego and e.Lego.Emitters and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Lego.Emitters)do if pe.Parent then pe:Emit(4)end end
     end
     -- Pickaxe 67: red sparks off both ends of the head, the chrome dial clicks round.
     if e.Six then
      e.Six.DialTarget+=math.pi/4
      if e.Six.Emitters and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
       for _,pe in ipairs(e.Six.Emitters)do if pe.Parent then pe:Emit(4)end end
      end
     end
     -- Toothy Alarm Clock: red sparks off both sides of the head and, for your own swing, a tick off the dial.
     if e.Alarm and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Alarm.Emitters or{})do if pe.Parent then pe:Emit(4)end end
      local tip=math.random()<.5 and e.Alarm.TipA or e.Alarm.TipB
      if character==player.Character and tip and tip.Parent and math.random()<.5 then glyph(tip.WorldPosition,pick({'тик','tick','⏰'}),pick({C(255,90,80),C(246,196,82)}),16,nil,.6)end
     end
     -- Zombie-Frankenstein: the convulsive jerk: blue sparks off both points, slime flung off the blade, a lightning
     -- wave down the seams.
     if e.Zombie then
      e.Zombie.WaveAt=os.clock();e.Zombie.WaveLen=.3
      if not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
       for _,pe in ipairs(e.Zombie.Emitters or{})do if pe.Parent then pe:Emit(4)end end
       local tip=e.Zombie.TipA
       if tip and tip.Parent then bits(tip.WorldPosition,{pal('Zombie')[3],C(214,255,96)},2,.18,8,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.2,Life=.6})end
       if e.Zombie.Drips and e.Zombie.Drips.Parent then e.Zombie.Drips:Emit(3)end
      end
     end
     -- Clown Chronomord: sparks off both bells and, for your own swing, now and then a tick off the clock.
     if e.Chrono and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Chrono.Emitters or{})do if pe.Parent then pe:Emit(4)end end
      local dial=e.Chrono.Dial
      if character==player.Character and dial and dial.Parent and math.random()<.4 then glyph(dial.Position,pick({'тик','tick','⏱'}),pick({C(255,90,80),C(246,206,104)}),16,nil,.6)end
     end
     -- Nasty Octopus: water sprays off both blade tips, drops are shaken off the head.
     if e.Octo and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Octo.Emitters or{})do if pe.Parent then pe:Emit(4)end end
      if e.Octo.Drips and e.Octo.Drips.Parent then e.Octo.Drips:Emit(3)end
     end
     -- Hand of Fate: purple sparks off both claws, slime shaken off the palm.
     if e.Fate and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,pe in ipairs(e.Fate.Emitters or{})do if pe.Parent then pe:Emit(4)end end
      if e.Fate.Drips and e.Fate.Drips.Parent then e.Fate.Drips:Emit(2)end
     end
     -- Laughsaw: the blade throws sparks off its edge.
     if e.Saw and e.Saw.Emitter and e.Saw.Emitter.Parent and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then e.Saw.Emitter:Emit(8)end
     -- Rotten Slime Slug: the swing flings slime off both blade tips and shakes drops off the underside.
     if e.Slug and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,tip in ipairs({e.Slug.TipA,e.Slug.TipB})do
       if tip and tip.Parent then bits(tip.WorldPosition,{pal('Slime')[1],pal('Slime')[2]},2,.2,8,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.2,Life=.6})end
      end
      if e.Slug.Drips and e.Slug.Drips.Parent then e.Slug.Drips:Emit(4)end
     end
     -- Gummy Horror: the swing flings a sticky drop off each horn tip.
     if e.Gummy and not low()and not(FX.ReducedMotion and FX.ReducedMotion())then
      for _,tip in ipairs({e.Gummy.TipA,e.Gummy.TipB})do
       if tip and tip.Parent then bits(tip.WorldPosition,{pal('Gummy')[1],pal('Gummy')[2],pal('Gummy')[3]},1,.2,7,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.2,Life=.6})end
      end
     end
    end
   end
  end
 end
 function self.PreviewPulse(model)local e=tracked[model];if e then e.Hit=1 end end
 -- Inspect (MiningClient.Tool, pickaxes with Inspect=true): the held models of a character show
 -- their inspect look for duration seconds (TV-Head: the screen tears, the face changes, the knobs
 -- spin, the antennas quiver). duration 0 ends it.
 function self.Inspect(character,duration)
  if not character then return end
  for _,c in ipairs(character:GetChildren())do
   if c:IsA('Model')and(c.Name=='MiningHeldPickaxe'or c.Name=='MiningHeldPickaxeL')then
    local e=tracked[c]or self.Track(c,false)
    if e then
     e.InspectUntil=os.clock()+(duration or 0)
     e.InspectLen=math.max(.1,duration or 0)
     if e.Pony then e.Pony.Charging=(duration or 0)>0 end
     if e.Scythe then e.Scythe.Charging=(duration or 0)>0;if(duration or 0)>0 then e.Scythe.Wave=os.clock()end end
     if e.Saw then e.Saw.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Saw.Fired)end
     if e.Lego then e.Lego.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Lego.Fired);e.Lego.Step=0 end
     if e.Six then e.Six.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Six.Fired)end
     if e.Net then e.Net.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Net.Fired)end
     if e.Twin then e.Twin.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Twin.Fired)end
     if e.Slug then e.Slug.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Slug.Fired)end
     if e.Alarm then e.Alarm.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Alarm.Fired)end
     if e.Zombie then e.Zombie.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Zombie.Fired)end
     if e.Chrono then e.Chrono.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Chrono.Fired)end
     if e.Octo then e.Octo.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Octo.Fired);e.Octo.NextLook=0 end
     if e.Fate then e.Fate.InspectAt=(duration or 0)>0 and os.clock()or -100;table.clear(e.Fate.Fired);e.Fate.NextLook=0 end
     if e.TV and(duration or 0)>0 then e.TV.GlitchUntil=os.clock()+.3 end
     -- Gummy Horror: drool flies out of the chomping mouth during the inspect.
     if e.Gummy and(duration or 0)>0 and not low()then
      for i=1,3 do task.delay(.5+i*.32,function()
       local head=e.Gummy.Head
       if head and head.Parent and os.clock()<e.InspectUntil then
        bits((head.CFrame*CFrame.new(0,-.5,.6)).Position,{pal('Gummy')[2],pal('Gummy')[1]},2,.16,5,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.4,Life=.6})
       end
      end)end
     end
    end
   end
  end
 end

 local function watchCharacter(character)
  local function add(child)
   if child:IsA('Model')and(child.Name=='MiningHeldPickaxe'or child.Name=='MiningHeldPickaxeL')then
    task.defer(function()if child.Parent then self.Track(child,false)end end)
   end
  end
  for _,c in ipairs(character:GetChildren())do add(c)end
  character.ChildAdded:Connect(add)
 end
 local function watchPlayer(p)
  if p.Character then watchCharacter(p.Character)end
  p.CharacterAdded:Connect(watchCharacter)
 end
 for _,p in ipairs(Players:GetPlayers())do watchPlayer(p)end
 Players.PlayerAdded:Connect(watchPlayer)

 local function reduced()return FX.ReducedMotion and FX.ReducedMotion()end
 local lastFar=0
 -- TV-Head screen: flicker, crawling static, a rolling bar, blinking eyes, now and then a torn
 -- frame; a strike (h) and the inspect split the picture into magenta / cyan ghosts and tear it.
 local function tvScreen(e,t,h)
  local tv=e.TV;local st=e.State
  if t>=tv.NextGlitch then tv.GlitchUntil=t+.07+math.random()*.13;tv.NextGlitch=t+1.4+math.random()*2.8 end
  local glitch=t<tv.GlitchUntil
  local inspecting=st.Insp>.5
  local amount=math.max(h,glitch and .5 or 0,st.Insp*(.3+math.max(0,math.noise(t*3.1,7.3))*.9))
  local g=math.random()
  tv.Noise.BackgroundColor3=Color3.new(.03+g*.05,.1+g*.08+amount*.12,.05+g*.04)
  if t>=tv.NextStatic then
   tv.NextStatic=t+.05
   for _,f in ipairs(tv.Static)do
    local on=math.random()<.3+amount*.6
    f.Visible=on
    if on then
     f.Position=UDim2.fromScale(math.random()*.95,math.random())
     f.Size=UDim2.fromScale(.02+math.random()*(.1+amount*.5),.008+math.random()*(.02+amount*.03))
     f.BackgroundTransparency=math.clamp(.5+math.random()*.4-amount*.3,0,.95)
    end
   end
  end
  if tv.Roll then tv.Roll.Position=UDim2.fromScale(0,(t*.42)%1.25-.12)end
  if tv.Face then tv.Face.Visible=not inspecting end
  tv.Inspect.Visible=inspecting
  local face=inspecting and tv.Inspect or tv.Face
  local jx=(math.random()-.5)*(.006+amount*.07)
  local jy=(math.random()-.5)*(.003+amount*.025)
  if glitch then jx+=(math.random()-.5)*.1 end
  if face then face.Position=UDim2.fromScale(jx,jy)end
  local split=amount*.04
  local ghosts=not inspecting and split>.006
  if tv.GhostA then tv.GhostA.Visible=ghosts;if ghosts then tv.GhostA.Position=UDim2.fromScale(jx-split,jy)end end
  if tv.GhostB then tv.GhostB.Visible=ghosts;if ghosts then tv.GhostB.Position=UDim2.fromScale(jx+split,-jy)end end
  if t>=tv.NextBlink then tv.BlinkUntil=t+.11;tv.NextBlink=t+2.4+math.random()*3.5 end
  if tv.Eyes then tv.Eyes.Visible=t>=tv.BlinkUntil end
  local flick=math.random()<.04 and .5 or 1
  tv.Gui.Brightness=(1.7+sin(t*9)*.15+amount*1.2)*flick
  if tv.Light then tv.Light.Brightness=(1+amount*1.5)*flick end
 end
 -- Ponycorn: the horn charges up during the inspect (brighter core and light, the gold halo turns,
 -- pastel motes stream into the tip, a flash when it is full), stars float off the head now and then
 -- while it is in the hand, the trail turns into a rainbow and glitters while the holder runs.
 local function ponyLive(e,t,dt,h,still)
  local pn=e.Pony;local st=e.State
  local g=st.Insp
  local progress=math.clamp(1-(e.InspectUntil-t)/(e.InspectLen or 2.6),0,1)
  local charge=g*(.35+.65*progress)
  local core=pn.Core
  if core and core.Parent then
   if g>.02 then core.Transparency=math.max(0,core.Transparency-charge) end
   if pn.Light then pn.Light.Brightness=.8+charge*4+h*1.5;pn.Light.Range=pn.LightBase+charge*6 end
  end
  for _,p in ipairs(pn.Halo)do p.Transparency=g>.02 and math.clamp(1-g*(.55+.3*sin(t*6))*(.4+.6*progress),.1,1)or 1 end
  local tip=core and core.Parent and(core.CFrame*CFrame.new(0,core.Size.Y*.5+.1,0)).Position
  if pn.Charging and tip and not still and not low()and t<e.InspectUntil and t>=pn.NextMote then
   pn.NextMote=t+.09
   local m=Instance.new('Part');m.Name='PonyMote';m.Shape=Enum.PartType.Ball;m.Anchored=true;m.CanCollide=false;m.CanQuery=false;m.CanTouch=false
   m.CastShadow=false;m.Material=Enum.Material.Neon;m.Color=pick(PONY_HUES);m.Size=Vector3.one*.14
   local d=Vector3.new(math.random()-.5,math.random()-.3,math.random()-.5).Unit
   m.CFrame=CFrame.new(tip+d*(1.4+math.random()*.8));m.Parent=folder
   TweenService:Create(m,TweenInfo.new(.45,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=CFrame.new(tip),Size=Vector3.one*.04}):Play()
   Debris:AddItem(m,.5)
  end
  if pn.Charging and t>=e.InspectUntil then -- full: a starry flash off the horn
   pn.Charging=false
   if tip and not still then
    shock(tip,C(255,240,250),3.5,.3)
    burst(tip,{C(255,150,220),C(255,240,140)},n(16),7,SPARK,Vector3.new(0,1,0))
    for _=1,n(3)do glyph(tip,pick({'★','✦','♥'}),pick(PONY_HUES),24,nil,.8)end
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local rainbow=run>.5
   if rainbow~=pn.Rainbow then pn.Rainbow=rainbow;e.Trail.Color=rainbow and PONY_RAINBOW or PONY_TRAIL;e.Trail.Lifetime=rainbow and .45 or .32 end
  end
  if pn.Emitters then
   local rate=(run>.3 and not still and not low())and math.floor(run*7+.5)or 0
   if rate~=pn.Rate then pn.Rate=rate;for _,pe in ipairs(pn.Emitters)do pe.Rate=rate end end
  end
  -- IDLE: a star or a heart floats up off the head (in the hand, close to the camera only)
  if t>=pn.NextFloat then
   pn.NextFloat=t+1.6+math.random()*1.8
   local head=pn.Head
   local cam=workspace.CurrentCamera
   if head and head.Parent and cam and not still and not low()and e.Model:GetAttribute('Mount')=='Hand'and(head.Position-cam.CFrame.Position).Magnitude<45 then
    glyph(head.Position+Vector3.new((math.random()-.5)*2.2,math.random()*.8,(math.random()-.5)*1.2),pick({'★','✦','♥','✧'}),pick(PONY_HUES),pick({14,16,18}),Vector3.new(0,.35,0),1.6)
   end
  end
 end
 -- Scarlet Anime Scythe: energy shimmers along the glyphs (a bright wave runs out to the point on
 -- every swing and through the inspect), the demon eye and the blade glow pulse, the ring of pixel
 -- glyphs fades in and turns during the inspect and ends in a "shing" flash at the point; in the hand
 -- a violet glyph floats off the blade now and then; running leaves a longer scarlet streak with
 -- sparks streaming off the point.
 local WHITE=Color3.new(1,1,1)
 local function scytheLive(e,t,dt,h,still)
  local sc=e.Scythe;local st=e.State
  local g=st.Insp
  local wave=(t-sc.Wave)*(g>.3 and .9 or 2.4)          -- 0..1 along the blade
  for _,r in ipairs(sc.Runes)do
   local p=r.Part
   if p.Parent then
    local tr=still and .1 or(.12+.14*(sin(t*2.2-r.T*9)+1)*.5)
    local hot=0
    if wave>=-.1 and wave<=1.3 then hot=math.max(0,1-math.abs(wave-r.T)*6)end
    hot=math.max(hot,g*.35)
    p.Transparency=tr*(1-hot)
    p.Color=hot>.02 and r.Color:Lerp(WHITE,hot*.7)or r.Color
   end
  end
  if g>.3 and wave>1.2 then sc.Wave=t end              -- the inspect keeps the energy running
  if sc.Eye then sc.Eye.Brightness=sc.EyeBase*(1+sin(t*3)*.25)+h*1.5+g*2 end
  if sc.Blade then sc.Blade.Brightness=sc.BladeBase*(1+sin(t*2.2+1)*.2)+h*1.2+g*1.4 end
  local progress=math.clamp(1-(e.InspectUntil-t)/(e.InspectLen or 2.6),0,1)
  for _,p in ipairs(sc.Halo)do p.Transparency=g>.02 and math.clamp(1-g*(.6+.3*sin(t*7))*math.min(1,progress*2.5),.05,1)or 1 end
  if sc.Charging and t>=e.InspectUntil then -- the inspect ends with a "shing" at the point
   sc.Charging=false
   local tip=sc.TipB
   if tip and tip.Parent and not still then
    local pos=tip.WorldPosition
    shock(pos,C(255,226,252),3.2,.25)
    burst(pos,{C(255,170,250),C(190,80,255)},n(14),8,SPARK,Vector3.new(0,1,0))
    glyph(pos,pick(SCYTHE_GLYPHS),C(206,120,255),26,nil,.8)
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=sc.Running then sc.Running=fast;e.Trail.Color=fast and SCYTHE_RUN or SCYTHE_TRAIL;e.Trail.Lifetime=fast and .45 or .3 end
  end
  if sc.Emitter then
   local rate=(run>.3 and not still and not low())and math.floor(run*8+.5)or 0
   if rate~=sc.Rate then sc.Rate=rate;sc.Emitter.Rate=rate end
  end
  if t>=sc.NextFloat then
   sc.NextFloat=t+2+math.random()*1.8
   local tipA,tipB=sc.TipA,sc.TipB
   local cam=workspace.CurrentCamera
   if tipA and tipB and tipA.Parent and cam and not still and not low()and e.Model:GetAttribute('Mount')=='Hand'and(tipA.WorldPosition-cam.CFrame.Position).Magnitude<45 then
    local pos=tipA.WorldPosition:Lerp(tipB.WorldPosition,.25+math.random()*.5)
    glyph(pos,pick(SCYTHE_GLYPHS),pick({C(196,90,255),C(255,170,250)}),pick({14,16,18}),Vector3.new(0,.35,0),1.6)
   end
  end
 end
 -- Butterfly Catcher: the film shimmers (the dome slices drift through sky, lilac and pink), stars and
 -- fireflies twinkle, the light breathes (brighter on a hit and through the inspect); in the hand a
 -- butterfly slips out of the film now and then; running streams sparkles and leaves butterflies
 -- behind; the inspect lets a little flock flutter out round the hoop and ends in a soft starry flash.
 local function netLive(e,t,dt,h,still)
  local nt=e.Net;local st=e.State
  local g=st.Insp
  for _,r in ipairs(nt.Iri)do
   local p=r.Part
   if p.Parent then p.Color=Color3.fromHSV((.6+.1*sin(t*.5+r.K*3)+h*.05)%1,.28+r.K*.12,1)end
  end
  for _,r in ipairs(nt.Twinkle)do
   local p=r.Part
   if p.Parent then
    local k=still and .5 or math.max(0,sin(t*2.6+r.Phase*5))
    p.Transparency=math.clamp(.75-k*k*.75-h*.4-g*.3,0,.9)
   end
  end
  if nt.Light then nt.Light.Brightness=.75+.2*sin(t*1.8)+h*1.4+g*1.1 end
  local glowPart=nt.Glow
  local cam=workspace.CurrentCamera
  local near=glowPart and glowPart.Parent and cam and(glowPart.Position-cam.CFrame.Position).Magnitude<45
  local ip=t-nt.InspectAt
  if ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil and glowPart and not still then
   if ip>.8 and not nt.Fired.Flock then
    nt.Fired.Flock=true
    for i=1,n(5)do
     local a=i/5*math.pi*2
     flyer(glowPart.Position,NET_WINGS[(i-1)%#NET_WINGS+1],Vector3.new(cos(a)*2.2,1.4+math.random(),sin(a)*2.2),1.6+math.random()*.6,.8)
    end
    for _=1,n(3)do glyph(glowPart.Position,pick({'✦','✧'}),pick(NET_WINGS),20,nil,.9)end
   end
   if ip>2.2 and not nt.Fired.End then
    nt.Fired.End=true
    shock(glowPart.Position,C(235,246,255),3,.25)
    burst(glowPart.Position,{C(255,244,160),C(160,220,255)},n(12),5,SPARK,Vector3.new(0,1,0))
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=nt.Running then nt.Running=fast;e.Trail.Color=fast and NET_RUN or NET_TRAIL;e.Trail.Lifetime=fast and .45 or .3 end
  end
  if nt.Emitters then
   local rate=(run>.3 and not still and not low())and math.floor(run*6+.5)or 0
   if rate~=nt.Rate then nt.Rate=rate;for _,pe in ipairs(nt.Emitters)do pe.Rate=rate end end
  end
  if nt.Sparks then
   local want=still and 0 or(run>.4 and 3 or 1.6)
   if nt.Sparks.Rate~=want then nt.Sparks.Rate=want end
  end
  if not(near and not still and not low())then return end
  -- RUN: now and then a butterfly drifts off behind the hoop
  if run>.5 and t>=nt.NextRun then
   nt.NextRun=t+.45+math.random()*.35
   local v=e.Root.AssemblyLinearVelocity
   flyer(glowPart.Position,pick(NET_WINGS),Vector3.new(-v.X*.12,1+math.random(),-v.Z*.12),1.1,.6)
  end
  -- IDLE in the hand: a butterfly slips out of the film
  if t>=nt.NextFloat then
   nt.NextFloat=t+2.6+math.random()*2
   if e.Model:GetAttribute('Mount')=='Hand'then
    flyer(glowPart.Position,pick(NET_WINGS),Vector3.new(math.random()-.5,.8,math.random()-.5),1.8,.6)
   end
  end
 end
 -- Laughsaw, before the parts move: the blade's turn (IDLE slow, faster with the holder's speed, a scream
 -- round on every strike, a long rev through the inspect) and the jaw's laugh (the inspect cackles in
 -- quick chatters, now and then the held saw giggles to itself).
 local function sawState(e,t,dt,h)
  local sw=e.Saw;local st=e.State
  local ip=t-sw.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local rev=inspecting and math.clamp((ip-.3)/.5,0,1)*(ip<2.2 and 1 or .4)or 0
  sw.Angle=(sw.Angle+dt*(2.6+st.Run*9+h*30+rev*18))%(math.pi*2)
  st.SawAngle=sw.Angle
  local laugh=0
  if inspecting and ip>1.2 and ip<2.45 then laugh=math.max(0,sin((ip-1.2)*26))*.85 end
  if not inspecting and sw.GiggleUntil and t<sw.GiggleUntil then laugh=math.max(0,sin(t*24))*.4 end
  st.Laugh=laugh
  sw.IP=inspecting and ip or -1
 end
 -- Laughsaw after the parts moved: the hub light breathes (flares on a hit and through the inspect), the
 -- embers drift up in IDLE and stream while running, sparks pour off the blade while running (БЕГ);
 -- the inspect throws a spray of sparks as the blade revs, a burst of "HA-HA" as the jaw cackles and a
 -- red flash at the end; in the hand the saw giggles to itself now and then.
 local function sawLive(e,t,dt,h,still)
  local sw=e.Saw;local st=e.State
  local g=st.Insp
  if sw.Light then sw.Light.Brightness=.9+.3*sin(t*2.4)+h*2.2+g*1.4 end
  local ip=sw.IP or -1
  local blade=sw.TipB
  if ip>=0 and not still and blade and blade.Parent then
   local pos=blade.WorldPosition
   if ip>.55 and not sw.Fired.Rev then
    sw.Fired.Rev=true
    burst(pos,{C(255,230,170),C(255,60,40)},n(18),14,SPARK,Vector3.new(0,1,0),{Spread=Vector2.new(60,60),Acceleration=Vector3.new(0,-45,0),Lifetime=NumberRange.new(.3,.6)})
   end
   if ip>1.35 and not sw.Fired.Laugh and sw.Head and sw.Head.Parent then
    sw.Fired.Laugh=true
    for i=1,n(4)do task.delay(i*.18,function()
     if sw.Head.Parent then glyph(sw.Head.Position+Vector3.new((math.random()-.5)*1.6,.8,0),pick(SAW_LAUGH),pick({C(255,60,60),C(255,200,180)}),pick({22,28,34}),Vector3.new(0,.8,0),.9)end
    end)end
   end
   if ip>2.35 and not sw.Fired.End then
    sw.Fired.End=true
    shock(pos,C(255,60,50),3.2,.25)
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=sw.Running then sw.Running=fast;e.Trail.Color=fast and SAW_RUN or SAW_TRAIL;e.Trail.Lifetime=fast and .45 or .3 end
  end
  if sw.Emitter then
   local rate=(run>.3 and not still and not low())and math.floor(run*10+.5)or 0
   if rate~=sw.Rate then sw.Rate=rate;sw.Emitter.Rate=rate end
  end
  if sw.Embers then
   local rate=(still and 0)or(low()and 1)or(run>.4 and 6 or 2.5)
   if rate~=sw.EmberRate then sw.EmberRate=rate;sw.Embers.Rate=rate end
  end
  -- IDLE in the hand: now and then a quiet giggle (the jaw chatters, a small "ha" floats off)
  if t>=sw.NextFloat then
   sw.NextFloat=t+5+math.random()*4
   local head=sw.Head
   local cam=workspace.CurrentCamera
   if head and head.Parent and cam and not still and not low()and e.Model:GetAttribute('Mount')=='Hand'and(head.Position-cam.CFrame.Position).Magnitude<45 then
    sw.GiggleUntil=t+.5
    glyph(head.Position+Vector3.new((math.random()-.5)*1.4,1,0),pick({'ha','ha-ha','хи'}),C(255,90,90),16,Vector3.new(0,.35,0),1.3)
   end
  end
 end
 -- LEGO Hand, before the parts move: the hand's turn on the wrist and the finger's clack.
 -- IDLE a slow sway, RUN a wobble, a strike clicks it round and back, the draw snaps it in from a half
 -- turn; the INSPECT ratchets it round 360 degrees in eight 45-degree clicks (.5 .. 2.1 s, timed to the
 -- MiningAudio Plastic inspect clicks) and clacks the finger twice at the end.
 local function legoState(e,t,dt,h)
  local lg=e.Lego;local st=e.State
  local ip=t-lg.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local twist=sin(t*.9)*.09+st.Run*sin(t*9)*.08+sin(math.min(1,h)*math.pi)*.34
  local ek=math.clamp((t-lg.EquipAt)/.42,0,1)
  if ek<1 then twist+=(1-ek)^3*math.pi*.75 end
  local clench=.02+(sin(t*1.6)+1)*.02+h*.2+st.Run*math.abs(sin(t*9))*.05
  lg.IP=-1
  if inspecting then
   local k=math.clamp((ip-.5)/1.6,0,1)*8
   local whole=math.floor(k)
   local snap=math.clamp((k-whole)/.3,0,1);snap=1-(1-snap)^3
   twist=twist*(1-st.Insp)+(whole+(whole<8 and snap or 0))*math.pi/4
   if ip>2.1 and ip<2.5 then clench=math.max(clench,math.max(0,sin((ip-2.1)*16))*.22)end
   lg.IP=ip;lg.Whole=whole
  end
  st.LegoTwist=twist;st.LegoClench=clench
 end
 -- LEGO Hand after the parts moved: the warm glow breathes (brighter on a hit and through the inspect), a
 -- star sparkles off the hand with every ratchet click of the inspect and a ring of stars ends it ("ОСМОТР");
 -- in the hand now and then a tiny brick pops off the top with a click ("СЛУЧАЙНЫЕ ЧАСТИЦЫ"); running
 -- leaves a longer golden streak, sparkles and little bricks behind ("СЛЕД ПРИ БЕГЕ").
 local function legoLive(e,t,dt,h,still)
  local lg=e.Lego;local st=e.State
  local g=st.Insp
  if lg.Light then lg.Light.Brightness=.5+.15*sin(t*2)+h*1.6+g*.9 end
  local glowPart=lg.Glow
  local ip=lg.IP or -1
  if ip>=0 and not still and glowPart and glowPart.Parent then
   local pos=glowPart.CFrame.Position
   if(lg.Whole or 0)>lg.Step then
    lg.Step=lg.Whole
    glyph(pos+Vector3.new((math.random()-.5)*2.4,(math.random()-.3)*2,0),'✦',pick(LEGO_STARS),pick({18,24}),nil,.6)
   end
   if ip>2.15 and not lg.Fired.End then
    lg.Fired.End=true
    shock(pos,C(255,240,180),3.4,.25)
    for i=1,n(6)do
     local a=i/6*math.pi*2
     glyph(pos,'✦',LEGO_STARS[(i-1)%#LEGO_STARS+1],pick({22,28}),Vector3.new(cos(a),sin(a)*.8+.3,0),.85)
    end
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=lg.Running then lg.Running=fast;e.Trail.Color=fast and LEGO_RUN or LEGO_TRAIL;e.Trail.Lifetime=fast and .45 or .3 end
  end
  if lg.Emitters then
   local rate=(run>.3 and not still and not low())and math.floor(run*6+.5)or 0
   if rate~=lg.Rate then lg.Rate=rate;for _,pe in ipairs(lg.Emitters)do pe.Rate=rate end end
  end
  if lg.Sparkles then
   local want=(still and 0)or(low()and .5)or(run>.4 and 2.5 or 1.2)
   if lg.Sparkles.Rate~=want then lg.Sparkles.Rate=want end
  end
  local cam=workspace.CurrentCamera
  local near=glowPart and glowPart.Parent and cam and(glowPart.CFrame.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  -- RUN: a little brick tumbles off behind now and then
  if run>.5 and t>=lg.NextRun then
   lg.NextRun=t+.28+math.random()*.2
   local v=e.Root.AssemblyLinearVelocity
   legoBrick(glowPart.CFrame.Position,pick(pal('Brick')),.2,Vector3.new(-v.X*.15,3+math.random()*2,-v.Z*.15),.5)
  end
  -- IDLE in the hand: a tiny brick pops off the top with a sparkle
  if t>=lg.NextFloat then
   lg.NextFloat=t+4+math.random()*3
   local tip=lg.TipA
   if tip and tip.Parent and e.Model:GetAttribute('Mount')=='Hand'then
    legoBrick(tip.WorldPosition,pick(pal('Brick')),.18,Vector3.new((math.random()-.5)*2,5,(math.random()-.5)*2),.6)
    glyph(tip.WorldPosition,'✦',pick(LEGO_STARS),16,Vector3.new(0,.4,0),.9)
   end
  end
 end
 -- Pickaxe 67, before the parts move: the glitch (IDLE now and then a short one, a hard one on every strike,
 -- the draw "boots" the digits in, the inspect glitches as it starts and as it ends), the dial (a 45-degree
 -- click on every strike, four 90-degree clicks of the inspect at 1.6 .. 1.96 s, timed to the MiningAudio
 -- Digital inspect clicks) and the tag's spin (two turns on its chain while the pickaxe twirls, .6 .. 1.6 s).
 local function sixState(e,t,dt,h)
  local sx=e.Six;local st=e.State
  local ip=t-sx.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  if t>=sx.NextGlitch then sx.GlitchUntil=t+.06+math.random()*.1;sx.NextGlitch=t+2.2+math.random()*3.2 end
  local amount=math.max(t<sx.GlitchUntil and .5 or 0,math.min(1,h*1.3),math.clamp(1-(t-sx.EquipAt)/.45,0,1))
  if inspecting and((ip>.4 and ip<.55)or(ip>2.02 and ip<2.2))then amount=math.max(amount,.9)end
  if amount>.05 then
   if t-sx.JitterAt>.035 then
    sx.JitterAt=t
    st.Six6=Vector3.new((math.random()-.5)*.14*amount,(math.random()-.5)*.04*amount,0)
    st.Six7=Vector3.new((math.random()-.5)*.14*amount,(math.random()-.5)*.04*amount,0)
   end
  else st.Six6=Vector3.zero;st.Six7=Vector3.zero end
  sx.Glitch=amount
  if inspecting then
   for i,at in ipairs({1.6,1.72,1.84,1.96})do
    if ip>=at and not sx.Fired['Dial'..i]then sx.Fired['Dial'..i]=true;sx.DialTarget+=math.pi/2 end
   end
  end
  sx.Dial+=(sx.DialTarget-sx.Dial)*math.min(1,dt*22)
  st.SixDial=sx.Dial
  local spin=0
  if inspecting then local k=math.clamp((ip-.6)/1,0,1);spin=k*k*(3-2*k)*math.pi*4 end
  st.SixSpin=spin
  sx.IP=inspecting and ip or -1
 end
 -- Pickaxe 67 after the parts moved: the red glow breathes (flares on a hit and through the inspect, flickers
 -- in a glitch, the piping flashes white-pink), the inspect pops a glitching "67" as it starts and a big one
 -- with a red flash as it ends; in the hand now and then a little red "6", "7" or "67" floats off the head
 -- (IDLE); running leaves a longer red streak, sparks and little "67"s behind (СЛЕД ПРИ БЕГЕ); the draw
 -- glitches a "67" in.
 local function sixLive(e,t,dt,h,still)
  local sx=e.Six;local st=e.State
  local glitching=sx.Glitch>.3 and not still
  if sx.Light then
   local b=.9+.2*sin(t*2.2)+h*2+st.Insp*1.2
   if glitching and math.random()<.5 then b*=.3 end
   sx.Light.Brightness=b
  end
  local hot=glitching and math.random()<.6
  if hot~=sx.Hot then
   sx.Hot=hot
   for _,r in ipairs(sx.Edges)do if r.Part.Parent then r.Part.Color=hot and C(255,214,222)or r.Color end end
  end
  local glowPart=sx.Glow
  local pos=glowPart and glowPart.Parent and glowPart.CFrame.Position
  local ip=sx.IP or -1
  if ip>=0 and not still and pos then
   if ip>.4 and not sx.Fired.Start then sx.Fired.Start=true;glitch67(pos+Vector3.new(0,1.6,0),30,.5,Vector3.new(0,1,0))end
   if ip>2.05 and not sx.Fired.End then
    sx.Fired.End=true
    shock(pos,C(255,60,70),3.4,.25)
    burst(pos,{C(255,236,236),C(255,40,52)},n(14),7,SPARK,Vector3.new(0,1,0))
    glitch67(pos+Vector3.new(0,1.4,0),60,.9,Vector3.new(0,1,0))
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=sx.Running then sx.Running=fast;e.Trail.Color=fast and SIX_RUN or SIX_TRAIL;e.Trail.Lifetime=fast and .45 or .3 end
  end
  if sx.Emitters then
   local rate=(run>.3 and not still and not low())and math.floor(run*6+.5)or 0
   if rate~=sx.Rate then sx.Rate=rate;for _,pe in ipairs(sx.Emitters)do pe.Rate=rate end end
  end
  if sx.Sparks then
   local want=(still and 0)or(low()and .5)or(run>.4 and 2.5 or 1.2)
   if want~=sx.SparkRate then sx.SparkRate=want;sx.Sparks.Rate=want end
  end
  local cam=workspace.CurrentCamera
  local near=pos and cam and(pos-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: the digits boot in with a small glitching "67"
  if inHand and t-sx.EquipAt<.3 and not sx.Fired.Boot then sx.Fired.Boot=true;glitch67(pos+Vector3.new(0,1.3,0),26,.45,Vector3.new(0,1,0))end
  -- RUN: a little "67" left behind now and then
  if run>.5 and t>=sx.NextRun then
   sx.NextRun=t+.3+math.random()*.2
   local v=e.Root.AssemblyLinearVelocity
   glyph(pos-Vector3.new(v.X,0,v.Z)*.05,pick(SIX_DIGITS),pick(SIX_COLORS),pick({14,18,22}),Vector3.new(-v.X*.02,.4,-v.Z*.02),.7)
  end
  -- IDLE in the hand: a digit floats up off the head
  if t>=sx.NextFloat then
   sx.NextFloat=t+2.5+math.random()*2
   if inHand then
    glyph(pos+Vector3.new((math.random()-.5)*2,math.random()*.8,(math.random()-.5)*1),pick(SIX_DIGITS),pick(SIX_COLORS),pick({14,16,18}),Vector3.new(0,.35,0),1.5)
   end
  end
 end
 -- Twin Claws, before the parts move: how far the claws are drawn in (deploy, inspect choreography),
 -- how calm the idle slide is, the inspect spread and the actuators' turn.
 local function twinState(e,t,dt,h)
  local tw=e.Twin;local st=e.State
  local deploy=math.clamp((t-tw.DeployAt-.08)/.24,0,1)
  local want=1-deploy*deploy
  local ip=(t-tw.InspectAt)/(e.InspectLen or 2.6)
  local inspecting=ip>=0 and ip<=1 and t<e.InspectUntil
  if inspecting then
   -- draw in .. hold .. SNAP out .. draw in .. SNAP out .. spread
   local k
   if ip<.12 then k=ip/.12 elseif ip<.22 then k=1 elseif ip<.26 then k=1-(ip-.22)/.04
   elseif ip<.45 then k=0 elseif ip<.52 then k=(ip-.45)/.07 elseif ip<.55 then k=1-(ip-.52)/.03 else k=0 end
   want=math.max(want,k)
  end
  local before=tw.ClawIn
  tw.ClawIn=want
  -- a "snikt": the claws shot out (deploy, inspect) -> one spark puff over the four tips
  if before>.6 and want<.25 and not e.Anchored and not low()and not reduced()and #tw.Snaps>0 then
   local sum=Vector3.zero
   for _,a in ipairs(tw.Snaps)do sum+=a.WorldPosition end
   burst(sum/#tw.Snaps,{CLAW_HOT,tw.Accent},6,6,SPARK,nil,{Lifetime=NumberRange.new(.15,.35),Spread=Vector2.new(180,180)})
  end
  st.ClawIn=want
  st.Calm=(1-st.Run)*(1-math.min(1,h*1.5))*(inspecting and 0 or 1)
  st.Spread=(inspecting and ip>.55 and math.min(1,(ip-.55)*6)*.16 or 0)*st.Insp+h*.04
  tw.Gear+=dt*(.5+math.abs(want-before)/math.max(dt,1/240)*.5+h*5)
  st.Gear=tw.Gear
  tw.IP=inspecting and ip or -1
 end
 -- Twin Claws after the parts moved: rune flash, lights, scratch trails, ambient sparks, the
 -- inspect's rising runes.
 local function twinLive(e,t,dt,h,still)
  local tw=e.Twin;local st=e.State
  local g=st.Insp
  local ip=tw.IP or -1
  local surge=ip>=0 and(ip>.22 and ip<.3 or ip>.52 and ip<.6)and 1 or 0
  local flash=math.clamp(math.max(h*.9,g*(.35+.25*sin(t*9)),surge),0,1)
  for _,r in ipairs(tw.Runes)do
   local p=r.Part
   if p.Parent then
    local c=r.Color:Lerp(WHITE,.08+.06*sin(t*2.4)+flash*.6)
    if p.Color~=c then p.Color=c end
   end
  end
  if tw.Light then tw.Light.Brightness=tw.LightBase*(1+.15*sin(t*2.4))+h*2+g*1.5 end
  if tw.RuneLight then tw.RuneLight.Brightness=tw.RuneBase*(1+.2*sin(t*2.4))+flash*2.5 end
  if ip>=.24 and not tw.Fired.Rune and tw.Plate and tw.Plate.Parent and not still then
   tw.Fired.Rune=true -- SYMBOL OF POWER: the rune rises off the plate as a glowing glyph
   local pos=tw.Plate.Position
   glyph(pos,CLAW_RUNE[tw.Side]or'右',tw.Accent,54,Vector3.new(0,.8,0),1.3)
   shock(pos,tw.Accent:Lerp(WHITE,.4),2.4,.25)
  end
  if e.Anchored then return end
  local want=(e.Hit>.12 or st.Run>.45 or(ip>.2 and ip<.7))and not still and not low()
  if want~=tw.TrailsOn then
   tw.TrailsOn=want
   for _,tr in ipairs(tw.Trails)do if tr.Parent then tr.Enabled=want end end
  end
  local life=st.Run>.45 and .32 or .2
  if life~=tw.Life then tw.Life=life;for _,tr in ipairs(tw.Trails)do tr.Lifetime=life end end
  if tw.Ambient then
   local rate=(still and 0)or(low()and 1)or(st.Run>.4 and 5 or 2)
   if rate~=tw.Rate then tw.Rate=rate;tw.Ambient.Rate=rate end
  end
 end
 -- Rotten Slime Slug after the parts moved: the slime glow breathes (flares on a hit, pulses through the inspect),
 -- drops fall off the underside (more while running); "Стоит (Stand)": now and then a drop falls from the held
 -- slug to the floor and spreads into a puddle that soaks away; "Бег": a longer streak, slime flung behind and a
 -- trail of little puddles; the draw slurps a few drops off; the inspect drools as it comes up, the big eye
 -- twitches ("?!") and three slime pulses end in a wet burst.
 local slugPuddles=0
 local slugRay=RaycastParams.new();slugRay.FilterType=Enum.RaycastFilterType.Exclude;slugRay.IgnoreWater=false
 local function slugPuddle(from,model,size,cols)
  if slugPuddles>=(low()and 2 or 6)then return end
  slugRay.FilterDescendantsInstances={folder,model.Parent or model}
  local hit=workspace:Raycast(from,Vector3.new(0,-14,0),slugRay)
  if not hit then return end
  local c=cols or pal('Slime') -- cols: another pickaxe's puddle colours (Nasty Octopus: seawater)
  slugPuddles+=1
  local drop=Instance.new('Part');drop.Name='PickSlimeDrop';drop.Shape=Enum.PartType.Ball;drop.Anchored=true;drop.CanCollide=false;drop.CanQuery=false;drop.CanTouch=false
  drop.CastShadow=false;drop.Material=Enum.Material.Glass;drop.Color=c[1];drop.Transparency=.1;drop.Size=Vector3.new(.16,.24,.16);drop.CFrame=CFrame.new(from);drop.Parent=folder
  local fall=math.sqrt(2*math.max(.1,from.Y-hit.Position.Y)/60)
  TweenService:Create(drop,TweenInfo.new(fall,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{CFrame=CFrame.new(hit.Position+Vector3.new(0,.08,0))}):Play()
  Debris:AddItem(drop,fall+.05)
  task.delay(fall,function()
   local up=hit.Normal
   local pd=Instance.new('Part');pd.Name='PickSlimePuddle';pd.Shape=Enum.PartType.Cylinder;pd.Anchored=true;pd.CanCollide=false;pd.CanQuery=false;pd.CanTouch=false
   pd.CastShadow=false;pd.Material=Enum.Material.Glass;pd.Color=pick({c[1],c[2]});pd.Transparency=.15;pd.Size=Vector3.new(.05,.2,.2)
   pd.CFrame=CFrame.new(hit.Position+up*.03)*alignX(up)*CFrame.Angles(math.random()*6,0,0);pd.Parent=folder
   local s=(size or 1)*(.7+math.random()*.5)
   TweenService:Create(pd,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=Vector3.new(.05,s,s*(.75+math.random()*.3))}):Play()
   TweenService:Create(pd,TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,1.1),{Transparency=1,Size=Vector3.new(.03,s*1.15,s*1.1)}):Play()
   if not reduced()then bits(hit.Position+up*.1,{c[1],c[2]},2,.1,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=1.2,Life=.35})end
   Debris:AddItem(pd,2.1)
   task.delay(2.1,function()slugPuddles=math.max(0,slugPuddles-1)end)
  end)
 end
 local function slugLive(e,t,dt,h,still)
  local sl=e.Slug;local st=e.State
  local g=st.Insp
  if sl.Light then sl.Light.Brightness=.55+.12*sin(t*1.4)+h*1.6+g*(.5+.5*sin(t*6))end
  local ip=t-sl.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local head=sl.Head
  if inspecting and not still and head and head.Parent then
   local c=pal('Slime')
   if ip>.3 and not sl.Fired.Drool and sl.Mouth and sl.Mouth.Parent then
    sl.Fired.Drool=true
    bits((sl.Mouth.CFrame*CFrame.new(0,-.3,.2)).Position,{c[1],c[2]},3,.16,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.1,Life=.7})
   end
   if ip>.75 and not sl.Fired.Twitch then
    sl.Fired.Twitch=true
    glyph(head.Position+Vector3.new(0,1.6,0),'?!',c[2],30,Vector3.new(.2,.6,0),.9)
   end
   for i,at in ipairs({1.25,1.5,1.75})do
    if ip>=at and not sl.Fired['Pulse'..i]then
     sl.Fired['Pulse'..i]=true
     shock(head.Position,c[1],2.2+i*.5,.25)
     if sl.Drips and sl.Drips.Parent and not low()then sl.Drips:Emit(3)end
    end
   end
   if ip>2.3 and not sl.Fired.End then
    sl.Fired.End=true
    burst(head.Position,{c[2],c[1]},n(14),6,SPARK,Vector3.new(0,1,0))
    bits(head.Position,{c[1],c[2]},5,.2,7,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.8,Life=.7})
   end
  end
  if sl.Drips then
   local want=(still and 0)or(low()and .6)or(st.Run>.4 and 3.5 or 1.6)
   if want~=sl.Rate then sl.Rate=want;sl.Drips.Rate=want end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=sl.Running then sl.Running=fast;e.Trail.Color=fast and SLUG_RUN or SLUG_TRAIL;e.Trail.Lifetime=fast and .48 or .34 end
  end
  local cam=workspace.CurrentCamera
  local near=head and head.Parent and cam and(head.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  -- DRAW: a few drops slurp off as it comes into the hand
  if e.Model:GetAttribute('Mount')=='Hand'and t-sl.EquipAt<.4 and not sl.Fired.Equip then
   sl.Fired.Equip=true
   bits(head.Position,{pal('Slime')[1],pal('Slime')[2]},4,.18,6,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.6,Life=.6})
  end
  -- RUN: slime flung behind and a trail of little puddles
  if run>.5 and t>=sl.NextRun then
   sl.NextRun=t+.42+math.random()*.25
   local v=e.Root.AssemblyLinearVelocity
   bits(head.Position,{pal('Slime')[1],pal('Slime')[2]},1,.18,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.3,Life=.5})
   slugPuddle(head.Position-Vector3.new(v.X,0,v.Z)*.04,e.Model,.7)
  end
  -- STAND: a drop falls to the floor and soaks away
  if t>=sl.NextDrop then
   sl.NextDrop=t+1.1+math.random()*1.3
   local d=#sl.Drops>0 and sl.Drops[math.random(1,#sl.Drops)]
   if d and d.Parent then slugPuddle(d.Position-Vector3.new(0,.1,0),e.Model,.9)end
  end
 end
 -- Toothy Alarm Clock, before the parts move: how hard it rings (a strike, the draw, the inspect's ring, a little
 -- rattle now and then in IDLE), the knife hands (creep in IDLE, race while running, whirl on a strike and through
 -- the inspect's wind-up), the winding key and gear, the handle dials' ticks (faster while running) and the
 -- inspect's scream. Inspect timing (2.6 s, MiningClient.Anim INSPECTS.Alarm / MiningAudio Alarm Inspect): .35 up,
 -- .4 .. 1.5 the key winds with a whirr and the hands spin while it turns round, 1.6 .. 2.35 it RINGS and screams.
 local function alarmState(e,t,dt,h)
  local al=e.Alarm;local st=e.State
  local ip=t-al.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local winding=inspecting and ip>.4 and ip<1.5
  local ringing=inspecting and ip>1.6 and ip<2.35
  local equip=t-al.EquipAt
  local ring=math.max(math.sqrt(h),ringing and 1 or 0,(equip>=0 and equip<.55)and(1-equip/.55)*.8 or 0,t<al.RattleUntil and .35 or 0)
  st.Ring=ring
  local rate=.35+st.Run*3.5+ring*12+(winding and 9 or 0)
  al.Min=(al.Min+dt*rate)%(math.pi*2)
  al.Hour=(al.Hour+dt*rate*.12)%(math.pi*2)
  al.Key=(al.Key+dt*(.5+(winding and 9 or 0)+ring*2))%(math.pi*2)
  al.TickAcc=(al.TickAcc+dt*(1+st.Run*3+ring*5))%60
  st.AlarmMin,st.AlarmHour,st.AlarmKey,st.Tick=al.Min,al.Hour,al.Key,math.floor(al.TickAcc)
  st.Scream=ringing and(.42+.06*sin(t*38))or 0
  al.IP=inspecting and ip or -1
 end
 -- Toothy Alarm Clock after the parts moved: the red glow breathes and flickers while it rings, faint red sparks in
 -- IDLE (more while running); the inspect: a whirr of sparks off the key, then the RING (gold rings, "DRRRING!",
 -- gears flying) and a little clock at the end; in the hand it rattles and ticks now and then ("тик-так"); running
 -- leaves a longer red streak with a gear or a little clock dropping off behind; the draw rings it once.
 local function alarmLive(e,t,dt,h,still)
  local al=e.Alarm;local st=e.State
  local ring=st.Ring or 0
  if al.Light then al.Light.Brightness=.6+.12*sin(t*1.6)+h*1.8+ring*(.8+.6*sin(t*40))end
  local ip=al.IP or -1
  local head=al.Head
  if ip>=0 and not still and head and head.Parent then
   local c=pal('Alarm')
   local pos=head.Position
   if ip>.5 and not al.Fired.Wind then
    al.Fired.Wind=true
    burst(pos,{C(255,200,120),C(255,60,40)},n(10),5,SPARK,Vector3.new(0,1,0))
    glyph(pos+Vector3.new(0,1.4,0),pick({'вжжж','whirr'}),c[2],22,Vector3.new(0,.5,0),.9)
   end
   if ip>1.62 and not al.Fired.Ring then
    al.Fired.Ring=true
    for i=0,2 do task.delay(i*.12,function()if head.Parent then FX.Ring(head.Position,i%2==0 and c[1]or c[2],3+i*1.6,.4)end end)end
    glyph(pos+Vector3.new(0,1.8,0),pick(ALARM_RING),C(255,214,90),46,Vector3.new(0,.8,0),1)
    if not low()then for _=1,3 do
     local d=Vector3.new(math.random()-.5,1,math.random()-.5).Unit
     alarmGear(pos+d*.6,d*(5+math.random()*3),.3)
    end end
   end
   if ip>2.36 and not al.Fired.End then
    al.Fired.End=true
    shock(pos,c[1],2.8,.25)
    glyph(pos+Vector3.new(0,1.2,0),'⏰',c[1],30,Vector3.new(0,.7,0),.8)
   end
  end
  if al.Sparks then
   local want=(still and 0)or(low()and .4)or(st.Run>.4 and 3 or 1.2)
   if want~=al.Rate then al.Rate=want;al.Sparks.Rate=want end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=al.Running then al.Running=fast;e.Trail.Color=fast and ALARM_RUN or ALARM_TRAIL;e.Trail.Lifetime=fast and .46 or .3 end
  end
  local cam=workspace.CurrentCamera
  local near=head and head.Parent and cam and(head.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: it rings once as it comes into the hand
  if inHand and t-al.EquipAt<.4 and not al.Fired.Equip then
   al.Fired.Equip=true
   glyph(head.Position+Vector3.new(0,1.4,0),pick({'ДЗЫНЬ!','RING!'}),C(255,214,90),26,Vector3.new(0,.6,0),.8)
  end
  -- RUN: now and then a gear or a little clock drops off behind
  if run>.5 and t>=al.NextRun then
   al.NextRun=t+.55+math.random()*.35
   local v=e.Root.AssemblyLinearVelocity
   local back=-Vector3.new(v.X,0,v.Z).Unit
   if math.random()<.6 then alarmGear(head.Position+back*.8,back*3+Vector3.new(0,2,0),.26)
   else alarmClock(head.Position+back*.8,back*2+Vector3.new(0,3,0),.38)end
  end
  -- IDLE in the hand: a little rattle and a "тик-так" now and then
  if inHand and t>=al.NextIdle and ip<0 then
   al.NextIdle=t+4+math.random()*3
   al.RattleUntil=t+.35
   glyph(head.Position+Vector3.new((math.random()-.5)*1.4,1.5,0),pick({'тик-так','tick-tock','тик'}),C(255,120,100),16,Vector3.new(0,.35,0),1.3)
  end
 end
 -- Zombie-Frankenstein, before the parts move: the rare LIVING SPASM in IDLE (every 6-12 s, also in previews), one on
 -- the draw and on a strike (h), the inspect's beats and growl, the neck bolt's turn. Inspect timing (2.6 s,
 -- MiningClient.Anim INSPECTS.Franken / MiningAudio Electric Inspect): .35 up, .45 .. 1.45 the lightning runs along the
 -- seams twice while the eye scans, 1.5 .. 2.05 it is turned round to show the stitched back, 2.05 .. 2.4 a spasm and
 -- a growl with the jaw wide open.
 local function zombieState(e,t,dt,h)
  local z=e.Zombie;local st=e.State
  local ip=t-z.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  if t>=z.NextSpasm then z.NextSpasm=t+6+math.random()*6;if not inspecting then z.SpasmUntil=t+.55 end end
  local equip=t-z.EquipAt
  local spasm=math.max(t<z.SpasmUntil and 1 or 0,(equip>=0 and equip<.5)and(1-equip/.5)or 0,h*.6,(inspecting and ip>2.05 and ip<2.4)and 1 or 0)
  st.Spasm=(st.Spasm or 0)+(spasm-(st.Spasm or 0))*math.min(1,dt*18)
  st.Growl=(inspecting and ip>2.05 and ip<2.45)and 1 or 0
  z.Bolt=(z.Bolt+dt*(st.Spasm*9+(inspecting and ip>.45 and ip<1.45 and 4 or 0)+h*6))%(math.pi*2)
  st.ZBolt=z.Bolt
  z.IP=inspecting and ip or -1
  if inspecting and ip>.45 and ip<1.45 then
   local w=((ip-.45)%.5)/.5
   z.Wave=w
  elseif t-z.WaveAt<z.WaveLen then
   z.Wave=(t-z.WaveAt)/z.WaveLen
  else
   z.Wave=nil
  end
 end
 -- a thin jagged blue arc a -> b (idle crackle round the coil and the skull)
 local function miniArc(a,b,col)
  local prev=a
  for i=1,4 do
   local q=a:Lerp(b,i/4)
   if i<4 then q+=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*.35 end
   line(prev,q,.05,col,.12+math.random()*.06)
   prev=q
  end
 end
 -- Zombie-Frankenstein after the parts moved: the machine eye's light flickers with the current, the vial glows; the
 -- lightning runs along the seams (they turn into blue neon where the wave is: the inspect twice, a strike once);
 -- small blue arcs crackle between the coil and the skull now and then ("маленькие синие молнии"), more during a
 -- spasm; the draw zaps it to life ("ZZT!"); running leaves a longer slimy streak with drops and sparks behind.
 local function zombieLive(e,t,dt,h,still)
  local z=e.Zombie;local st=e.State
  local sp=st.Spasm or 0
  local c=pal('Zombie')
  if z.Light then z.Light.Brightness=.7+.1*sin(t*2.3)+h*1.6+sp*(.6+math.random()*.8)+(z.Wave and .8 or 0)end
  if z.JarLight then z.JarLight.Brightness=.5+.15*sin(t*1.9)+st.Insp*.4 end
  -- seams
  local w=(not still)and z.Wave or nil
  for _,sm in ipairs(z.Seams)do
   local on=w~=nil and math.abs(sm.K-w)<.09
   if on~=sm.Lit and sm.Part.Parent then
    sm.Lit=on
    if on then sm.Part.Material=Enum.Material.Neon;sm.Part.Color=c[2]:Lerp(c[1],math.random()*.6)
    else sm.Part.Material=sm.Material;sm.Part.Color=sm.Color end
   end
  end
  if z.Sparks then
   local want=(still and 0)or(low()and .8)or(2+sp*14+(z.Wave and 6 or 0))
   want=math.floor(want*2+.5)/2
   if want~=z.Rate then z.Rate=want;z.Sparks.Rate=want end
  end
  if z.Drips then
   local want=(still and 0)or(low()and .5)or(st.Run>.4 and 3 or 1.2)
   if want~=z.DripRate then z.DripRate=want;z.Drips.Rate=want end
  end
  local coil,head=z.Coil,z.Head
  local cam=workspace.CurrentCamera
  local near=head and head.Parent and cam and(head.Position-cam.CFrame.Position).Magnitude<(e.Anchored and 200 or 45)
  if not(near and not still and not low())then return end
  -- idle crackle: a small arc from the coil tip to a point on the skull (more often in a spasm / the inspect)
  if t>=z.NextArc and coil and coil.Parent and not e.Anchored then
   z.NextArc=t+((sp>.3 or z.Wave)and .12 or(1.4+math.random()*1.6))
   local hs=head.Size
   local o=head.CFrame*Vector3.new((math.random()-.5)*hs.X,hs.Y*.5,(math.random()-.5)*hs.Z)
   miniArc(coil.Position,o,math.random()<.5 and c[1]or c[2])
  end
  if e.Anchored then return end
  local ip=z.IP or -1
  if ip>=0 then
   if ip>.45 and not z.Fired.Seam then z.Fired.Seam=true;glyph(head.Position+Vector3.new(0,1.6,0),pick(ZOMBIE_ZAP),c[2],26,Vector3.new(0,.6,0),.8)end
   if ip>2.05 and not z.Fired.Growl then
    z.Fired.Growl=true
    shock(head.Position,c[1],3,.25)
    burst(head.Position,{c[2],c[1]},n(12),6,SPARK,Vector3.new(0,1,0))
    bits(head.Position,{c[3],C(214,255,96)},4,.18,6,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.7,Life=.7})
    glyph(head.Position+Vector3.new(0,1.6,0),pick({'ГРРР!','GRRR!'}),c[3],36,Vector3.new(0,.8,0),1)
   end
  end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=z.Running then z.Running=fast;e.Trail.Color=fast and ZOMBIE_RUN or ZOMBIE_TRAIL;e.Trail.Lifetime=fast and .46 or .3 end
  end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: a jolt brings it to life
  if inHand and t-z.EquipAt<.4 and not z.Fired.Equip then
   z.Fired.Equip=true
   for _=1,3 do
    local o=head.Position+Vector3.new(math.random()-.5,math.random()-.2,math.random()-.5)*2
    miniArc(head.Position,o,c[2])
   end
   glyph(head.Position+Vector3.new(0,1.5,0),'ZZT!',C(150,220,255),28,Vector3.new(0,.6,0),.8)
  end
  -- RUN: slime drops flung behind, now and then a spark
  if run>.5 and t>=z.NextRun then
   z.NextRun=t+.45+math.random()*.3
   local v=e.Root.AssemblyLinearVelocity
   local back=-Vector3.new(v.X,0,v.Z).Unit
   bits(head.Position+back*.6,{c[3],C(214,255,96)},1,.18,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.3,Life=.5})
   if math.random()<.4 then burst(head.Position,{c[2],c[1]},3,3,SPARK,back)end
  end
 end
 -- Clown Chronomord, before the parts move: the laugh (the inspect's laugh, a giggle now and then in IDLE, the draw, a
 -- strike), the eyes popping out, the hands running BACKWARDS (slow in IDLE, faster while running, a whirl on a strike,
 -- spinning back through the inspect's rewind) and the gears. Inspect timing (2.6 s, MiningClient.Anim INSPECTS.Chrono /
 -- MiningAudio Clown Inspect): .35 up with the eyes popping, .4 .. 1.25 the clock REWINDS, 1.25 .. 1.85 it is turned
 -- round, 1.9 .. 2.45 it LAUGHS.
 local function chronoState(e,t,dt,h)
  local ch=e.Chrono;local st=e.State
  local ip=t-ch.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local rewind=inspecting and ip>.4 and ip<1.25
  local laughing=inspecting and ip>1.9 and ip<2.45
  if t>=ch.NextGiggle then ch.NextGiggle=t+7+math.random()*6;if not inspecting then ch.GiggleUntil=t+.8 end end
  local equip=t-ch.EquipAt
  local eq=(equip>=0 and equip<.6)and(1-equip/.6)or 0
  local lg=math.max(laughing and 1 or 0,t<ch.GiggleUntil and .55 or 0,eq,h*.5)
  st.Laugh=(st.Laugh or 0)+(lg-(st.Laugh or 0))*math.min(1,dt*14)
  st.Pop=math.max(eq,(inspecting and ip>.3 and ip<.65)and 1 or 0,laughing and .6 or 0)
  local rate=.5+st.Run*4+h*14+(rewind and 16 or 0)+eq*8
  ch.Min+=dt*rate                 -- positive = counter-clockwise from the front: the clock runs backwards
  ch.Hour+=dt*rate/12
  ch.Gear+=dt*(.7+st.Run*3+h*10+(rewind and 9 or 0)+st.Laugh*3)
  st.ChMin,st.ChHour,st.ChGear=ch.Min,ch.Hour,ch.Gear
  ch.IP=inspecting and ip or -1
  ch.Rewind=rewind
 end
 -- Clown Chronomord after the parts moved: the clock's warm light breathes (brighter on a strike, the rewind and a laugh),
 -- slow gold sparks in IDLE (more while running and rewinding); the inspect: "⟲ тик-так" and gears flying off as it
 -- rewinds, then "ХА-ХА-ХА!" with pocket watches thrown up; the draw honks; a giggle now and then in the hand ("хи-хи");
 -- running leaves a longer red streak with a little pocket watch dropping off behind (concept "СЛЕД ПРИ БЕГЕ").
 local function chronoLive(e,t,dt,h,still)
  local ch=e.Chrono;local st=e.State
  local c=pal('Clown')
  if ch.Light then ch.Light.Brightness=.55+.1*sin(t*2)+h*1.5+(st.Laugh or 0)*.4+(ch.Rewind and .6 or 0)end
  if ch.Sparks then
   local want=(still and 0)or(low()and .5)or((st.Run>.4 and 3 or 1.4)+(ch.Rewind and 8 or 0))
   if want~=ch.Rate then ch.Rate=want;ch.Sparks.Rate=want end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=ch.Running then ch.Running=fast;e.Trail.Color=fast and CHRONO_RUN or CHRONO_TRAIL;e.Trail.Lifetime=fast and .46 or .3 end
  end
  local head,dial=ch.Head,ch.Dial
  local cam=workspace.CurrentCamera
  local near=head and head.Parent and cam and(head.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  local ip=ch.IP or -1
  if ip>=0 then
   if ip>.45 and not ch.Fired.Rewind then
    ch.Fired.Rewind=true
    glyph((dial or head).Position+Vector3.new(0,1.2,0),pick({'⟲ тик-так','⟲ tock-tick'}),c[2],24,Vector3.new(0,.5,0),.9)
   end
   if ip>.85 and not ch.Fired.Gears then
    ch.Fired.Gears=true
    for _=1,3 do
     local d=Vector3.new(math.random()-.5,1,math.random()-.5).Unit
     alarmGear((dial or head).Position+d*.8,d*(4+math.random()*3),.26)
    end
   end
   if ip>1.95 and not ch.Fired.Laugh then
    ch.Fired.Laugh=true
    shock(head.Position,c[1],2.8,.25)
    burst(head.Position,{c[2],c[1]},n(12),6,SPARK,Vector3.new(0,1,0))
    for _=1,3 do
     local d=Vector3.new(math.random()-.5,1,math.random()-.5).Unit
     chronoWatch(head.Position+d*.8,d*(5+math.random()*3),.4,math.random()<.4)
    end
    glyph(head.Position+Vector3.new(0,1.7,0),pick(CHRONO_LAUGH),c[1],40,Vector3.new(0,.8,0),1.1)
   end
  end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: a honk and the eyes pop out
  if inHand and t-ch.EquipAt<.4 and not ch.Fired.Equip then
   ch.Fired.Equip=true
   burst(head.Position,{c[2],c[1]},n(8),4,SPARK,Vector3.new(0,1,0))
   glyph(head.Position+Vector3.new(0,1.6,0),'HONK!',c[2],28,Vector3.new(0,.6,0),.8)
  end
  -- IDLE in the hand: a giggle now and then, a "тик-так" (the concept's golden ticking sparks)
  if inHand and ip<0 then
   if ch.GiggleUntil>t and ch.GiggleShown~=ch.GiggleUntil then
    ch.GiggleShown=ch.GiggleUntil
    glyph(head.Position+Vector3.new((math.random()-.5)*1.2,1.5,0),pick({'хи-хи','hee-hee','хе-хе'}),c[1],18,Vector3.new(0,.4,0),1.1)
   end
   if t>=ch.NextTick then
    ch.NextTick=t+4+math.random()*3
    glyph((dial or head).Position+Vector3.new((math.random()-.5)*1.6,.9,0),pick({'тик-так','tick-tock','⚙'}),c[2],16,Vector3.new(0,.35,0),1.3)
   end
  end
  -- RUN: now and then a little pocket watch drops off behind
  if run>.5 and t>=ch.NextRun then
   ch.NextRun=t+.5+math.random()*.35
   local v=e.Root.AssemblyLinearVelocity
   local back=-Vector3.new(v.X,0,v.Z).Unit
   chronoWatch(head.Position+back*.8,back*2.5+Vector3.new(0,2.5,0),.36,math.random()<.35)
  end
 end
 -- Nasty Octopus, before the parts move: where the ONE EYE looks (IN HAND quick curious glances, STAND / on the back a slow
 -- wandering creepy stare, now and then it stares right at the camera; the inspect: it looks around fast, is held still while
 -- it is turned round, then glares at you), how far it bulges (a strike, the draw, the inspect), the tentacles spreading open
 -- (the draw, the inspect's lash) and the ink sac pumping. Inspect timing (2.6 s, MiningClient.Anim INSPECTS.Octo /
 -- MiningAudio Wet Inspect): .35 up, .4 .. 1.15 the eye looks round curiously while the CURSED PEARL grows in the long
 -- tentacle's curl, 1.15 .. 1.75 it is turned round (the ink sac pumps on the back), 1.9 .. 2.3 the TENTACLE LASH and an ink
 -- squirt, the pearl sinks back by 2.55.
 local function octoState(e,t,dt,h)
  local o=e.Octo;local st=e.State
  local ip=t-o.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local equip=t-o.EquipAt
  local eq=(equip>=0 and equip<.6)and(1-equip/.6)or 0
  local inHand=not e.Anchored and e.Model:GetAttribute('Mount')=='Hand'
  if t>=o.NextLook then
   o.Stare=false
   if inspecting then
    o.TX,o.TY=(math.random()-.5)*.5,(math.random()-.5)*.8;o.NextLook=t+.22+math.random()*.2
   elseif not e.Anchored and math.random()<.3 then
    o.Stare=true;o.NextLook=t+1.6+math.random()*1.6
   elseif inHand then -- curious: quick darting glances
    o.TX,o.TY=(math.random()-.5)*.55,(math.random()-.5)*.85;o.NextLook=t+.45+math.random()*.9
   else -- slow, wandering creepy stare
    o.TX,o.TY=(math.random()-.5)*.4,(math.random()-.5)*.7;o.NextLook=t+1.8+math.random()*2.2
   end
  end
  local tx,ty=o.TX,o.TY
  if(o.Stare or(inspecting and ip>1.85))and not e.Anchored then -- stare right at the camera (only when it is in front of the eye)
   local cam=workspace.CurrentCamera
   local eye=o.Eye
   if cam and eye and eye.Parent then
    local d=e.Root.CFrame:VectorToObjectSpace(cam.CFrame.Position-eye.Position)
    if d.Z>.1 then
     tx=math.clamp(-math.atan2(d.Y,math.sqrt(d.X*d.X+d.Z*d.Z)),-.4,.4)
     ty=math.clamp(math.atan2(d.X,d.Z),-.5,.5)
    end
   end
  end
  if inspecting and ip>1.15 and ip<1.85 then tx,ty=0,0 end
  local speed=(inHand or inspecting)and 9 or 2.4
  st.EyeX=(st.EyeX or 0)+(tx-(st.EyeX or 0))*math.min(1,dt*speed)
  st.EyeY=(st.EyeY or 0)+(ty-(st.EyeY or 0))*math.min(1,dt*speed)
  local lash=inspecting and ip>1.88 and ip<2.3
  st.Bulge=math.max(sin(math.sqrt(h)*math.pi)*.16,eq*.12,lash and .16 or 0,(inspecting and ip>.4 and ip<.6)and .1 or 0)
  st.Spread=math.max(eq*.7,lash and 1 or 0)
  st.SacPump=(inspecting and ip>1.3 and ip<1.75)and(.5+.5*sin(ip*30))or 0
  o.IP=inspecting and ip or -1
 end
 -- Nasty Octopus after the parts moved: the eye's warm light (brighter as it bulges), seawater dripping off the head (more
 -- while running), the cursed pearl growing / sinking (inspect), the inspect's "?", the pearl's sparkle, the ink sac's drops
 -- and the TENTACLE LASH with an ink squirt ("SPLOOSH!"); the draw slurps it into the hand ("BLOOP!"); IDLE now and then a
 -- curious "?" in the hand or a creepy "..." on the back; a drop falls to the floor and makes a little puddle; RUN a longer
 -- blue -> violet streak with drops flung and puddles left behind.
 local OCTO_PUDDLE={C(150,214,255),C(110,170,250)}
 local function octoLive(e,t,dt,h,still)
  local o=e.Octo;local st=e.State
  local c=pal('Ink')
  if o.Light then o.Light.Brightness=.45+.08*sin(t*1.7)+h*1.2+(st.Bulge or 0)*2.5 end
  if o.Drips then
   local want=(still and 0)or(low()and .5)or(st.Run>.4 and 3.5 or 1.4)
   if want~=o.Rate then o.Rate=want;o.Drips.Rate=want end
  end
  local ip=o.IP or -1
  local pearl=o.Pearl
  if pearl and pearl.Parent then
   local k=ip>=0 and math.clamp((ip-.75)/.45,0,1)*(1-math.clamp((ip-2.3)/.25,0,1))or 0
   if math.abs(k-(o.PearlK or -1))>.004 then
    o.PearlK=k
    pearl.Size=Vector3.one*(.05+.3*k)
    pearl.Transparency=k<.02 and 1 or 0
   end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=o.Running then o.Running=fast;e.Trail.Color=fast and OCTO_RUN or OCTO_TRAIL;e.Trail.Lifetime=fast and .46 or .3 end
  end
  local eye=o.Eye
  local cam=workspace.CurrentCamera
  local near=eye and eye.Parent and cam and(eye.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  if ip>=0 then
   if ip>.45 and not o.Fired.Q1 then o.Fired.Q1=true;glyph(eye.Position+Vector3.new(.4,1.2,0),'?',c[3],30,Vector3.new(.2,.6,0),.9)end
   if ip>.8 and not o.Fired.Q2 then o.Fired.Q2=true;glyph(eye.Position+Vector3.new(-.4,1.3,0),'?',c[4],24,Vector3.new(-.2,.6,0),.8)end
   if ip>1.05 and not o.Fired.Pearl and pearl and pearl.Parent then
    o.Fired.Pearl=true
    burst(pearl.Position,{C(255,240,252),C(230,150,255)},n(10),3,SPARK,Vector3.new(0,1,0))
    glyph(pearl.Position+Vector3.new(0,.6,0),'✦',C(255,226,250),22,Vector3.new(0,.5,0),.8)
   end
   if ip>1.45 and not o.Fired.Sac and o.Sac and o.Sac.Parent then
    o.Fired.Sac=true
    bits(o.Sac.Position,{c[5],C(70,30,110)},4,.16,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.1,Up=.2,Life=.7})
   end
   if ip>1.92 and not o.Fired.Lash then
    o.Fired.Lash=true
    local pos=eye.Position
    slash(pos+Vector3.new(0,.2,0),c[2],2.2,rad(-25),.32)
    slash(pos,c[3],1.7,rad(-25),.28)
    bits(pos,OCTO_WATER,6,.18,9,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.12,Up=.6,Life=.6})
    bits((o.Sac and o.Sac.Parent and o.Sac.Position)or pos,{c[5],C(70,30,110)},5,.2,8,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.05,Up=.5,Life=.7})
    glyph(pos+Vector3.new(0,1.6,0),pick(OCTO_SPLOOSH),c[1],36,Vector3.new(0,.8,0),1)
   end
  end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: it slurps into the hand, the eye pops open
  if inHand and t-o.EquipAt<.4 and not o.Fired.Equip then
   o.Fired.Equip=true
   bits(eye.Position,OCTO_WATER,5,.16,6,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.6,Life=.6})
   if o.Drips and o.Drips.Parent then o.Drips:Emit(4)end
   glyph(eye.Position+Vector3.new(0,1.5,0),pick({'BLOOP!','БУЛЬК!'}),c[1],26,Vector3.new(0,.6,0),.8)
  end
  -- IDLE: a curious "?" in the hand, a creepy "..." when it only stares
  if ip<0 and t>=o.NextMood then
   o.NextMood=t+6+math.random()*4
   glyph(eye.Position+Vector3.new((math.random()-.5)*1.2,1.4,0),inHand and'?'or'...',inHand and c[4]or c[1],inHand and 20 or 18,Vector3.new(0,.35,0),1.2)
  end
  -- RUN: drops flung behind, little seawater puddles
  if run>.5 and t>=o.NextRun then
   o.NextRun=t+.42+math.random()*.25
   local v=e.Root.AssemblyLinearVelocity
   local flat=Vector3.new(v.X,0,v.Z)
   if flat.Magnitude>1 then
    bits(eye.Position-flat.Unit*.6,OCTO_WATER,2,.16,4,Enum.Material.Glass,Enum.PartType.Ball,{Transparency=.15,Up=.3,Life=.5})
    slugPuddle(eye.Position-flat*.04,e.Model,.7,OCTO_PUDDLE)
   end
  end
  -- STAND: a drop falls to the floor now and then
  if t>=o.NextDrop then
   o.NextDrop=t+1.2+math.random()*1.4
   local d=#o.Drops>0 and o.Drops[math.random(1,#o.Drops)]
   if d and d.Parent then slugPuddle(d.Position-Vector3.new(0,.1,0),e.Model,.8,OCTO_PUDDLE)end
  end
 end
 -- Hand of Fate, before the parts move: where the CURSED EYE looks (IN HAND quick glances, STAND / on the back a slow stare,
 -- now and then right at the camera), its blinks, how far it bulges, the fingers spreading (the draw, the inspect) and the
 -- fist wave (the draw's grab, the inspect), a nervous twitch now and then. Inspect timing (2.6 s, MiningClient.Anim
 -- INSPECTS.Fate / MiningAudio Doom Inspect): .35 up, .4 .. .95 the hand opens wide while the eye looks round and blinks,
 -- .95 .. 1.65 it is turned round (the back with its tendons), 1.72 .. 2.3 it closes into a fist one finger after another
 -- while the eye GLARES at you (the cursed eye flares at 1.95), then it lets go.
 local function fateState(e,t,dt,h)
  local o=e.Fate;local st=e.State
  local ip=t-o.InspectAt
  local inspecting=ip>=0 and ip<=(e.InspectLen or 2.6)and t<e.InspectUntil
  local equip=t-o.EquipAt
  local inHand=not e.Anchored and e.Model:GetAttribute('Mount')=='Hand'
  if t>=o.NextLook then
   o.Stare=false
   if inspecting then
    o.TX,o.TY=(math.random()-.5)*.18,(math.random()-.5)*.1;o.NextLook=t+.18+math.random()*.2
   elseif not e.Anchored and math.random()<.25 then
    o.Stare=true;o.NextLook=t+1.4+math.random()*1.6
   elseif inHand then
    o.TX,o.TY=(math.random()-.5)*.16,(math.random()-.5)*.09;o.NextLook=t+.5+math.random()*1
   else
    o.TX,o.TY=(math.random()-.5)*.12,(math.random()-.5)*.07;o.NextLook=t+1.8+math.random()*2.2
   end
  end
  local tx,ty=o.TX,o.TY
  if(o.Stare or(inspecting and ip>1.7))and not e.Anchored then -- glare right at the camera (only when it is in front of the eye)
   local cam=workspace.CurrentCamera
   local eye=o.Eye
   if cam and eye and eye.Parent then
    local d=e.Root.CFrame:VectorToObjectSpace(cam.CFrame.Position-eye.Position)
    if d.Z>.1 then
     tx=math.clamp(math.atan2(d.X,d.Z)*.12,-.09,.09)
     ty=math.clamp(math.atan2(d.Y,math.sqrt(d.X*d.X+d.Z*d.Z))*.1,-.05,.05)
    end
   end
  end
  if inspecting and ip>.95 and ip<1.65 then tx,ty=0,0 end
  local speed=(inHand or inspecting)and 10 or 3
  st.EyeX=(st.EyeX or 0)+(tx-(st.EyeX or 0))*math.min(1,dt*speed)
  st.EyeY=(st.EyeY or 0)+(ty-(st.EyeY or 0))*math.min(1,dt*speed)
  -- blinks: now and then, twice in the inspect; the eye opens on the draw
  if t>=o.NextBlink then o.BlinkAt=t;o.NextBlink=t+2.4+math.random()*3.2 end
  if inspecting and ip>.55 and not o.Fired.Blink1 then o.Fired.Blink1=true;o.BlinkAt=t end
  if inspecting and ip>1.0 and not o.Fired.Blink2 then o.Fired.Blink2=true;o.BlinkAt=t end
  local bk=t-o.BlinkAt
  local blink=(bk>=0 and bk<.2)and sin(bk/.2*math.pi)or 0
  if equip>=0 and equip<.4 then blink=math.max(blink,1-equip/.4)end
  st.Blink=blink
  local glare=inspecting and ip>1.85 and ip<2.35
  st.Bulge=math.max(sin(math.sqrt(h)*math.pi)*.05,glare and .05 or 0)
  -- fingers: the draw spreads them and snaps them into a grab; the inspect opens wide, then the fist wave
  local open=0
  if equip>=0 and equip<.25 then open=sin(equip/.25*math.pi)end
  if inspecting then
   if ip>.35 and ip<.95 then open=math.max(open,math.clamp((ip-.35)/.2,0,1))
   elseif ip>=.95 and ip<1.65 then open=math.max(open,.3)end
  end
  st.Open=(st.Open or 0)+(open-(st.Open or 0))*math.min(1,dt*12)
  if inspecting and ip>1.6 then
   st.FistAt=o.InspectAt+1.72;st.FistK=1-math.clamp((ip-2.3)/.25,0,1)
  elseif equip>=.15 and equip<.7 then
   st.FistAt=o.EquipAt+.22;st.FistK=(1-math.clamp((equip-.45)/.2,0,1))*.7
  else
   st.FistAt=nil
  end
  st.Twitch=(st.Twitch or 0)+(((t<o.TwitchUntil)and 1 or 0)-(st.Twitch or 0))*math.min(1,dt*10)
  o.IP=inspecting and ip or -1
 end
 -- Hand of Fate after the parts moved: the eye's purple light (brighter as it bulges, flares with the cursed eye), the motes
 -- and the slime drips (more while running); the inspect: a puff of sparkles as the hand opens, the CURSED EYE flaring over it
 -- as it glares, sparkles off the claws as it lets go; the draw: a purple puff and a small cursed eye as it opens; IDLE now and
 -- then the fingers twitch in the hand (a few motes) or the eye flares on the back; a slime drop falls and makes a little
 -- puddle; RUN a longer purple streak with glowing cubes and drops flung behind.
 local FATE_PUDDLE={C(176,64,236),C(140,40,200)}
 local function fateLive(e,t,dt,h,still)
  local o=e.Fate;local st=e.State
  local c=pal('Fate')
  o.Flash=math.max(0,(o.Flash or 0)-dt*2.5)
  if o.Light then o.Light.Brightness=.55+.1*sin(t*1.6)+h*1.4+(st.Bulge or 0)*8+o.Flash*3 end
  if o.Motes then
   local want=(still and 0)or(low()and .6)or(st.Run>.4 and 4 or 1.5)
   if want~=o.Rate then o.Rate=want;o.Motes.Rate=want end
  end
  if o.Drips then
   local want=(still and 0)or(low()and .5)or(st.Run>.4 and 2.5 or 1)
   if want~=o.DripRate then o.DripRate=want;o.Drips.Rate=want end
  end
  if e.Anchored then return end
  local run=st.Run
  if e.Trail then
   local fast=run>.5
   if fast~=o.Running then o.Running=fast;e.Trail.Color=fast and FATE_RUN or FATE_TRAIL;e.Trail.Lifetime=fast and .46 or .32 end
  end
  local eye=o.Eye
  local cam=workspace.CurrentCamera
  local near=eye and eye.Parent and cam and(eye.Position-cam.CFrame.Position).Magnitude<45
  if not(near and not still and not low())then return end
  local ip=o.IP or -1
  if ip>=0 then
   if ip>.45 and not o.Fired.Open then
    o.Fired.Open=true
    burst(eye.Position,{c[3],c[1]},n(12),3,SPARK,Vector3.new(0,1,0))
    if o.Motes and o.Motes.Parent then o.Motes:Emit(6)end
   end
   if ip>1.95 and not o.Fired.Glare then
    o.Fired.Glare=true;o.Flash=1
    local look=cam.CFrame.Position-eye.Position
    cursedEye(eye.Position+look.Unit*1.2+Vector3.new(0,.9,0),2.2,.7)
   end
   if ip>2.3 and not o.Fired.Release then
    o.Fired.Release=true
    for _,tip in ipairs({o.TipA,o.TipB})do
     if tip and tip.Parent then bits(tip.WorldPosition,{c[1],c[3]},3,.12,5,Enum.Material.Neon,nil,{Up=.6,Life=.6})end
    end
   end
  end
  local inHand=e.Model:GetAttribute('Mount')=='Hand'
  -- DRAW: a purple puff, the eye opens with a small cursed eye
  if inHand and t-o.EquipAt<.4 and not o.Fired.Equip then
   o.Fired.Equip=true;o.Flash=.7
   burst(eye.Position,{c[1],c[3]},n(10),4,SPARK,Vector3.new(0,1,0))
   cursedEye(eye.Position+(cam.CFrame.Position-eye.Position).Unit*.9+Vector3.new(0,.6,0),1,.45)
  end
  -- IDLE: the fingers twitch in the hand, the eye flares on the back
  if ip<0 and t>=o.NextMood then
   o.NextMood=t+7+math.random()*4
   if inHand then o.TwitchUntil=t+.5;if o.Motes and o.Motes.Parent then o.Motes:Emit(4)end else o.Flash=.6 end
  end
  -- RUN: glowing cubes and drops flung behind, little puddles of slime
  if run>.5 and t>=o.NextRun then
   o.NextRun=t+.42+math.random()*.25
   local v=e.Root.AssemblyLinearVelocity
   local flat=Vector3.new(v.X,0,v.Z)
   if flat.Magnitude>1 then
    bits(eye.Position-flat.Unit*.6,{c[1],c[3]},2,.14,4,Enum.Material.Neon,nil,{Up=.3,Life=.5})
    slugPuddle(eye.Position-flat*.04,e.Model,.7,FATE_PUDDLE)
   end
  end
  -- STAND: a drop of slime falls to the floor now and then
  if t>=o.NextDrop then
   o.NextDrop=t+1.6+math.random()*1.6
   local d=#o.Drops>0 and o.Drops[math.random(1,#o.Drops)]
   if d and d.Parent then slugPuddle(d.Position-Vector3.new(0,.1,0),e.Model,.8,FATE_PUDDLE)end
  end
 end
 local LIVE={} -- Kind -> fn(e,t,dt,h,still): extra live state machines (Halloween pickaxe skins fill it, PickaxeSkins.Register)
 local function animate(e,t,dt)
  e.Hit=math.max(0,e.Hit-dt*2.2)
  local h=e.Hit*e.Hit
  local still=reduced()
  -- Entry state the motions read: Run (the holder's ground speed), Insp (inspect, eased), Spin.
  local st=e.State
  if not e.Anchored then
   local v=e.Root.AssemblyLinearVelocity
   st.Run+=(math.clamp((Vector3.new(v.X,0,v.Z).Magnitude-4)/12,0,1)-st.Run)*math.min(1,dt*6)
  end
  st.Insp+=((t<e.InspectUntil and 1 or 0)-st.Insp)*math.min(1,dt*8)
  st.Spin+=dt*st.Insp*7
  if e.Twin then twinState(e,t,dt,h)end
  if e.Saw then sawState(e,t,dt,h)end
  if e.Lego then legoState(e,t,dt,h)end
  if e.Six then sixState(e,t,dt,h)end
  if e.Alarm then alarmState(e,t,dt,h)end
  if e.Zombie then zombieState(e,t,dt,h)end
  if e.Chrono then chronoState(e,t,dt,h)end
  if e.Octo then octoState(e,t,dt,h)end
  if e.Fate then fateState(e,t,dt,h)end
  for _,p in ipairs(e.Parts)do
   local T=CFrame.identity
   if not still then for _,fn in ipairs(p.Motions)do T=T*fn(t,p.Phase,h,p.Pop,st,p)end end
   if p.Motor then
    p.Motor.Transform=T
   elseif e.Anchored and p.Part.Parent then
    p.Part.CFrame=e.Root.CFrame*p.Joint*T*p.Joint:Inverse()*p.Base
   end
  end
  for _,r in ipairs(e.Rainbow)do r.Part.Color=Color3.fromHSV((t*.3+r.Phase)%1,.6,1)end
  for _,r in ipairs(e.Pulse)do r.Part.Transparency=math.clamp(r.Base+(sin(t*3.2)+1)*.18-h*.3,0,.95)end
  if e.Pony then ponyLive(e,t,dt,h,still)end
  if e.Scythe then scytheLive(e,t,dt,h,still)end
  if e.Twin then twinLive(e,t,dt,h,still)end
  if e.Net then netLive(e,t,dt,h,still)end
  if e.Saw then sawLive(e,t,dt,h,still)end
  if e.Lego then legoLive(e,t,dt,h,still)end
  if e.Six then sixLive(e,t,dt,h,still)end
  if e.Slug then slugLive(e,t,dt,h,still)end
  if e.Alarm then alarmLive(e,t,dt,h,still)end
  if e.Zombie then zombieLive(e,t,dt,h,still)end
  if e.Chrono then chronoLive(e,t,dt,h,still)end
  if e.Octo then octoLive(e,t,dt,h,still)end
  if e.Fate then fateLive(e,t,dt,h,still)end
  if e.Live==nil and next(LIVE)then e.Live=LIVE[e.Model:GetAttribute('Kind')or'']or false end;if e.Live then e.Live(e,t,dt,h,still)end
  for _,f in ipairs(e.Flicker)do f.Transparency=(math.random()<.35 and h<.2)and 1 or 0 end
  -- Dripping pixels (PixelDrip): appear at the top of the fall, fade out at the bottom.
  for _,d in ipairs(e.Drips)do
   local k=(t*.6+d.Phase)%1
   d.Part.Transparency=still and 1 or(k<.06 and 1 or(k>.7 and math.min(1,(k-.7)/.3)or 0))
  end
  -- Gummy drops (PickGoo): fade in at the top of the stretch, fade out as they fall.
  for _,d in ipairs(e.Goo)do
   local k=(t*.42+d.Phase)%1
   d.Part.Transparency=still and d.Base or(k<.05 and 1-(k/.05)*(1-d.Base)or(k>.85 and math.min(1,d.Base+(k-.85)/.12)or d.Base))
  end
  -- Running with Gummy Horror: now and then a sticky drop slings off the head (light, capped by low FX).
  if e.Gummy and not e.Anchored and st.Run>.5 and not still and not low()and e.Gummy.Head and math.random()<dt*2.5 then
   bits(e.Gummy.Head.Position,{pal('Gummy')[1],pal('Gummy')[2]},1,.16,3,Enum.Material.Glass,Enum.PartType.Ball,{Up=.1,Life=.5,Transparency=.15})
  end
  -- Running with TV-Head: now and then a loose pixel flies off behind it (light, capped by low FX).
  if e.TV and not e.Anchored and st.Run>.5 and not still and not low()and e.TV.Case and math.random()<dt*2.5 then
   bits(e.TV.Case.Position,{pal('TV')[1],pal('TV')[2]},1,.14,3,Enum.Material.Neon,nil,{Up=.2,Life=.45})
  end
  if e.TV then
   tvScreen(e,t,h)
  elseif e.Noise then
   local g=math.random()
   e.Noise.BackgroundColor3=Color3.new(.04+g*.06,.12+g*.14,.07+g*.06)
   if e.Face then e.Face.Position=UDim2.fromOffset((math.random()-.5)*(2+h*14),(math.random()-.5)*(1+h*8))end
  end
 end
 RunService.Stepped:Connect(function(_,dt)
  local cam=workspace.CurrentCamera;if not cam then return end
  local t=os.clock()
  if #flyers>0 then updateFlyers(t,dt,cam.CFrame.Position)end
  if #glitches>0 then updateGlitches(t)end
  if #critDials>0 then updateDials(t)end
  local far=t-lastFar>.1;if far then lastFar=t end
  local camPos=cam.CFrame.Position
  for model,e in pairs(tracked)do
   if not model.Parent or not e.Root.Parent then tracked[model]=nil
   elseif e.Anchored then -- previews (in a ViewportFrame) always
    animate(e,t,dt)
   else
    local d=(e.Root.Position-camPos).Magnitude
    -- Nearby every frame, far away at 10 Hz, very far not at all.
    if d<70 then animate(e,t,dt)elseif d<160 and far then animate(e,t,.1)end
   end
  end
 end)

 self.Themes=THEMES;self.HitFX=HIT;self.LiveFX=LIVE -- Halloween pickaxe skins add their hit themes / live state machines here (ReplicatedStorage.Halloween.PickaxeSkins.Register)
 return self
end

return PickFX
