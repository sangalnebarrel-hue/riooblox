-- Procedural character animation (no animation assets needed): pickaxe swings and weight lifts
-- are written to the Motor6D.Transform of the arms (and on R15 the waist, hips, knees and root)
-- every frame after the Animator, so they blend over the normal idle animation. Motor transforms
-- are not replicated, so every client also drives the same poses for other players' characters
-- from their corner's replicated hit/rep counters.
-- Swing styles (Config.Mining.Pickaxes[i].Swing): Chop (two-handed overhead), Smash (huge
-- wind-up, heavy pickaxes), Slash (horizontal sweep: scythe, saw), Claw (Twin Claws: right / left
-- swipes and the cross strike, see CLAW), Bounce (Gummy Horror), Prance (Ponycorn-Dolphoodle),
-- Reap (Scarlet Anime Scythe), Scoop (Butterfly Catcher), Rip (Laughsaw), Clack (LEGO Hand),
-- SixSeven (Pickaxe 67), Slurp (Rotten Slime Slug), Alarm (Toothy Alarm Clock), Franken (Zombie-Frankenstein),
-- Chrono (Clown Chronomord), Octo (Nasty Octopus), Fate (Hand of Fate).
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Anim={}
local Skins=(function()local ok,m=pcall(function()return require(game:GetService('ReplicatedStorage'):WaitForChild('Halloween',10):WaitForChild('PickaxeSkins',10))end);if ok and type(m)=='table'then return m end;return{For=function(_,d)return d end}end)() -- Halloween pickaxe skins (remote swing style)

local rad=math.rad
local function ease(a,b,t)t=math.clamp(t,0,1);t=t*t*(3-2*t);return a+(b-a)*t end
-- Piecewise keyframes: {time, value...}; returns the values at t (smoothstep between keys).
local function keys(list,t)
 if t<=list[1][1]then return table.unpack(list[1],2)end
 for i=2,#list do
  local a,b=list[i-1],list[i]
  if t<=b[1]then
   local f=(t-a[1])/(b[1]-a[1])
   local out={}
   for j=2,#a do out[j-1]=ease(a[j],b[j],f)end
   return table.unpack(out)
  end
 end
 return table.unpack(list[#list],2)
end
local REP_TIME=.55 -- one remote lift: up to the top and back down
-- Inspect (pickaxes with Inspect=true: TV-Head, Gummy Horror, Ponycorn): bring it up in front of the face (screen to the
-- camera), tilt it closer, then turn it round to show the screen and lower it back into the tool
-- hold. Keys: time, right shoulder X, shoulder Z, elbow, wrist X, wrist Z (the twist round the
-- handle), waist twist. Checked on a block R15 rig: the CRT stays 2.2+ studs from the head.
local INSPECT={{0,90,0,0,0,0,0},{.35,45,-40,0,-10,45,-10},{.9,48,-38,4,-16,30,-12},{1.25,44,-40,0,-6,58,-8},
 {1.65,70,-12,15,-20,225,0},{2.15,70,-12,15,-20,225,0},{2.6,90,0,0,0,0,0}}
Anim.INSPECT_TIME=INSPECT[#INSPECT][1]
-- Per swing style inspects (same keys and length). Reap (Scarlet Anime Scythe, concept "ОСМОТР"): it
-- comes up in front, twirls once round its pole (the ring of glyphs lights up, MiningClient.PickFX),
-- is held out to show the blade, then goes back into the tool hold. Checked on a block R15 rig: the
-- blade turns above the head and the pole stays clear of the body (MiningModels HandTilt / HandYaw).
local INSPECTS={
 Reap={{0,90,0,0,0,0,0},{.35,95,-30,0,-10,20,-8},{.55,95,-30,0,-10,20,-8},{1.35,95,-30,0,-10,380,-8},
  {1.6,100,-22,6,-16,375,-4},{2.15,100,-22,6,-16,365,-4},{2.6,90,0,0,0,360,0}},
 -- Scoop (Butterfly Catcher, concept "ОСМОТР"): the net comes down in front at arm's length with the
 -- glowing film turned up toward the camera, rocks gently from side to side while the butterflies
 -- dance inside and flutter out (MiningClient.PickFX), twirls once round its pole and goes back into
 -- the tool hold. Checked with the R15 block rig numbers: the hoop stays 3.6+ studs from the head and
 -- clear of the body, the film faces the third-person camera.
 Scoop={{0,90,0,0,0,0,0},{.45,62,-26,24,-30,25,-10},{.95,64,-24,26,-38,5,-12},{1.35,60,-28,22,-24,45,-8},
  {1.9,70,-12,14,-20,405,-4},{2.25,80,-6,8,-8,360,0},{2.6,90,0,0,0,360,0}},
 -- Rip (Laughsaw, concept "ОСМОТР"): it comes up in front with the grin to the camera while the blade
 -- revs (MiningClient.PickFX), turns once all the way round its pole (the sheet's circling arrows: the
 -- blade, the back face, the grin again), then is held up and shaken while the jaw cackles and goes back
 -- into the tool hold. Same rig limits as Reap (the head turns above the hand, clear of the body).
 Rip={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,15,-8},{.6,96,-28,0,-10,15,-8},{1.25,96,-28,0,-10,375,-8},
  {1.45,100,-24,4,-14,368,-5},{1.7,100,-24,4,-8,352,-5},{1.95,100,-24,4,-14,368,-5},{2.2,100,-24,4,-8,356,-5},{2.6,90,0,0,0,360,0}},
 -- Clack (LEGO Hand, concept "ОСМОТР"): the hand comes up in front with the stickers to the camera and is
 -- held still while it ratchets round on its wrist in eight clicks (MiningClient.PickFX), then a proud
 -- little lift as the finger clacks twice and back into the tool hold. Same rig limits as Rip.
 Clack={{0,90,0,0,0,0,0},{.35,96,-30,0,-10,10,-8},{.5,96,-30,0,-10,10,-8},{2.1,98,-28,2,-12,10,-6},
  {2.25,106,-22,6,-18,16,-3},{2.4,98,-28,2,-12,4,-6},{2.6,90,0,0,0,0,0}},
 -- SixSeven (Pickaxe 67, concept "ОСМОТР"): it comes up in front with the 6 and the 7 to the camera, twirls
 -- once all the way round its pole (the sheet's circling arrows; the "67" tag spins on its chain,
 -- MiningClient.PickFX), is held up while the chrome dial ratchets four clicks, a small proud lift as the
 -- digits glitch and the big "67" pops, then back into the tool hold. Same rig limits as Rip.
 SixSeven={{0,90,0,0,0,0,0},{.35,96,-30,0,-10,12,-8},{.55,96,-30,0,-10,12,-8},{1.4,96,-30,0,-10,372,-8},
  {1.6,100,-24,4,-14,366,-5},{2.0,100,-24,4,-14,366,-5},{2.15,106,-20,6,-18,370,-3},{2.6,90,0,0,0,360,0}},
 -- Slurp (Rotten Slime Slug, concept "Осмотр"): the slug comes up in front of the face with its BIG eye to the
 -- camera and is held there while the eye twitches and the slime pulses (MiningClient.PickFX), with a little
 -- nervous shake, then it is turned round to show the snail shell on its back and goes back into the tool
 -- hold. Same keys and rig limits as the default inspect (the head stays 2.2+ studs from the face).
 Slurp={{0,90,0,0,0,0,0},{.35,47,-38,2,-12,40,-10},{.6,47,-38,2,-12,32,-10},{1.0,50,-36,4,-18,46,-12},{1.12,46,-39,2,-10,30,-10},
  {1.4,47,-38,2,-12,38,-10},{1.8,70,-12,15,-20,205,0},{2.2,70,-12,15,-20,205,0},{2.6,90,0,0,0,360,0}},
 -- Alarm (Toothy Alarm Clock, concept "ОСМОТР"): the clock comes up in front with its toothy face to the camera
 -- and is held while the key winds with a whirr and the knife hands spin, turns once all the way round its pole
 -- (the sheet's circling arrows: the side plate, the back with the key and the gear, the face again), then RINGS:
 -- it is shaken hard in the hand while it screams with the jaw wide open (MiningClient.PickFX), and goes back
 -- into the tool hold. Same rig limits as Rip (the head turns above the hand, clear of the body).
 Alarm={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,12,-8},{.85,96,-28,0,-10,12,-8},{1.5,96,-28,0,-10,372,-8},
  {1.62,104,-22,4,-16,368,-4},{1.72,98,-26,2,-8,352,-6},{1.82,104,-22,4,-16,368,-4},{1.92,98,-26,2,-8,352,-6},
  {2.02,104,-22,4,-16,368,-4},{2.12,98,-26,2,-8,354,-6},{2.3,100,-24,4,-12,362,-5},{2.6,90,0,0,0,360,0}},
 -- Franken (Zombie-Frankenstein, concept "Осмотр"): the head comes up in front with its face (the living eye and the
 -- machine eye) to the camera and is held while lightning runs along the seams, twitching now and then like a nervous
 -- tic (MiningClient.PickFX); it is turned round to show the stitched flesh on the back, back to the face, then a spasm:
 -- it jerks in the hand while it growls with the jaw wide open, and goes back into the tool hold. Same rig limits as
 -- Alarm (the head turns above the hand, clear of the body).
 Franken={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,12,-8},{.8,96,-28,0,-10,12,-8},{.86,99,-25,2,-14,18,-7},{.94,96,-28,0,-10,10,-8},
  {1.2,96,-28,0,-10,12,-8},{1.25,94,-30,0,-7,6,-8},{1.33,96,-28,0,-10,12,-8},{1.45,96,-28,0,-10,12,-8},{1.75,96,-28,0,-10,192,-8},
  {1.95,96,-28,0,-10,192,-8},{2.12,98,-26,2,-12,372,-6},{2.18,104,-22,5,-17,378,-4},{2.24,97,-27,1,-7,364,-7},{2.3,103,-23,4,-15,377,-4},
  {2.36,98,-26,2,-9,366,-6},{2.6,90,0,0,0,360,0}},
 -- Chrono (Clown Chronomord, concept "ОСМОТР"): the clown comes up in front with its face to the camera, its eyes pop and
 -- it is held while the clock REWINDS (the hands spin backwards, the eyes go wild, a few nervous little shakes,
 -- MiningClient.PickFX), it turns once all the way round its pole (the sheet's circling arrows: the bells, the red clock
 -- back, the face again), then it LAUGHS: shaken in the hand with the jaw chattering and the tongue flapping, and goes
 -- back into the tool hold. Same rig limits as Alarm (the head turns above the hand, clear of the body).
 Chrono={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,12,-8},{.6,96,-28,0,-10,12,-8},{.72,98,-26,2,-13,4,-7},{.86,96,-28,0,-10,18,-8},
  {1.0,98,-26,2,-13,6,-7},{1.25,96,-28,0,-10,12,-8},{1.85,96,-28,0,-10,372,-8},{1.95,100,-24,4,-14,368,-5},{2.05,96,-27,2,-8,356,-6},
  {2.15,101,-23,4,-15,370,-5},{2.25,96,-27,2,-8,354,-6},{2.35,100,-24,4,-13,366,-5},{2.6,90,0,0,0,360,0}},
 -- Octo (Nasty Octopus, concept "IN HAND: eye looks around curiously" / "EXTRA IDEAS"): the octopus comes up in front with its
 -- big eye to the camera and is tilted from side to side, curious, while the eye darts around and the CURSED PEARL grows in the
 -- long tentacle's curl (MiningClient.PickFX); it turns once all the way round its pole (the ink sac pumping on the back, the
 -- face again), then the TENTACLE LASH: a wet jerk up and a couple of shakes while the tentacles snap open and it squirts ink,
 -- and back into the tool hold. Same rig limits as Chrono (the head turns above the hand, clear of the body).
 Octo={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,12,-8},{.55,97,-27,1,-13,2,-7},{.78,95,-29,0,-7,24,-8},{.98,97,-27,1,-12,6,-7},
  {1.15,96,-28,0,-10,12,-8},{1.75,96,-28,0,-10,372,-8},{1.9,102,-23,5,-16,368,-4},{2.0,94,-30,0,-6,354,-8},{2.1,100,-24,4,-14,368,-5},
  {2.22,96,-27,2,-9,358,-6},{2.6,90,0,0,0,360,0}},
 -- Fate (Hand of Fate, concept "ОСМОТР": the hand turns round, circling arrows): the hand comes up in front with the cursed eye
 -- to the camera and is held while the fingers spread wide and the eye looks round and blinks, with a slow creepy tilt
 -- (MiningClient.PickFX); it turns once all the way round its pole (the back of the hand with its tendons, the eye again), then
 -- the FIST: a slow squeeze up while the fingers close one after another and the eye glares, a heavy little shake, and back
 -- into the tool hold. Same rig limits as Octo (the head turns above the hand, clear of the body).
 Fate={{0,90,0,0,0,0,0},{.35,96,-28,0,-10,12,-8},{.6,97,-27,1,-13,4,-7},{.85,95,-29,0,-8,20,-8},{.95,96,-28,0,-10,12,-8},
  {1.65,96,-28,0,-10,372,-8},{1.75,96,-28,0,-10,372,-8},{2.0,102,-24,4,-16,368,-5},{2.08,99,-26,2,-11,374,-6},{2.16,102,-24,4,-15,367,-5},
  {2.3,100,-25,3,-13,370,-6},{2.6,90,0,0,0,360,0}},
}

-- Twin Claws (Swing='Claw', concept sheet "ANIMATION PREVIEW"): ATTACK RIGHT and ATTACK LEFT swipes
-- take turns (the arm winds up high and outside, then rakes down and across the body while the
-- waist follows through); every 4th strike of a quick chain is the COMBO CROSS STRIKE (both arms
-- wide and high, then crossing down in front). Anim.ClawMove tells the effects which hand struck
-- ('R', 'L' or 'X'). While the claws are only held (no session): IDLE (arms loose at the sides, the
-- claws down and a little forward, breathing) and RUN (arms swept back so the claws trail, a lean
-- forward), blended by ground speed. INSPECT raises both gauntlets crossed in front of the chest
-- (claws up and out, the wrists turned so both rune plates face out, as on the sheet), holds while
-- the claws snap in and out and both runes flash and rise as glowing glyphs (MiningClient.PickFX),
-- then throws the arms wide apart, the claws spread to the sides. Keys: time, right shoulder X, right shoulder Z, right elbow, left
-- shoulder X, left shoulder Z, left elbow, waist twist, lean (negative = forward), wrist twist.
-- Checked on a block R15 rig: the claws clear the legs in the hold and run poses, the crossed
-- gauntlets stay in front of the head in the inspect.
local CLAW={
 R={Length=.3,Keys={{0,40,0,50,40,0,50,0,0,0},{.08,115,32,75,48,-6,70,-22,4,0},{.17,72,-42,8,40,4,74,26,-8,0},{.3,40,0,50,40,0,50,0,0,0}}},
 L={Length=.3,Keys={{0,40,0,50,40,0,50,0,0,0},{.08,48,6,70,115,-32,75,22,4,0},{.17,40,-4,74,72,42,8,-26,-8,0},{.3,40,0,50,40,0,50,0,0,0}}},
 X={Length=.42,Keys={{0,40,0,50,40,0,50,0,0,0},{.12,140,40,60,140,-40,60,0,6,0},{.24,66,-36,6,54,36,10,0,-14,0},{.42,40,0,50,40,0,50,0,0,0}}},
 Inspect={{0,12,12,22,12,-12,22,0,0,0},{.4,74,-40,108,60,40,112,0,0,180},{.65,74,-40,108,60,40,112,0,0,180},
  {1.5,78,-36,104,62,36,108,0,-4,180},{1.95,70,30,30,70,-30,30,0,-6,60},{2.3,50,14,40,50,-14,40,0,0,0},{2.6,12,12,22,12,-12,22,0,0,0}},
 -- held without a session: shoulder X, shoulder Z (outward), elbow, lean
 Hold={12,12,22,0},Run={-48,16,30,-10},
 Chain=1.3, -- seconds between strikes that still count as one chain (the 4th is the cross)
}
Anim.CLAW=CLAW
-- Swing keyframes: time, right shoulder X, right elbow, left shoulder X, waist twist (Y), lean (X)
local SWINGS={
 Chop={Length=.34,Keys={{0,0,0,0,0,0},{.1,155,45,95,-14,-6},{.17,30,5,40,10,14},{.34,0,0,0,0,0}}},
 Smash={Length=.46,Keys={{0,0,0,0,0,0},{.18,175,60,170,-20,-14},{.26,20,0,25,16,22},{.46,0,0,0,0,0}}},
 -- Gummy Horror: a sticky overhead chop that springs back up off the ore like marmalade, twice.
 Bounce={Length=.42,Keys={{0,0,0,0,0,0},{.1,152,45,92,-14,-6},{.17,26,4,36,10,14},{.24,56,16,58,4,6},{.31,22,4,30,7,9},{.36,34,8,38,4,4},{.42,0,0,0,0,0}}},
 -- Ponycorn-Dolphoodle: a graceful prancing chop: a high wind-up with a twist, a light strike and a
 -- little flourish back up (the fins and charms swing through it, MiningClient.PickFX).
 Prance={Length=.4,Keys={{0,0,0,0,0,0},{.11,162,38,96,-20,-8},{.18,28,4,38,12,14},{.26,50,14,48,-8,5},{.33,30,8,34,4,3},{.4,0,0,0,0,0}}},
 -- Scarlet Anime Scythe: a reaping diagonal cut: the blade goes up high over the right shoulder with
 -- the body turned away, cuts down and across point first (MiningModels HandYaw) and follows through
 -- low on the left. Full keys: time, right shoulder X, right shoulder Z, elbow, left shoulder X,
 -- waist twist, lean.
 Reap={Length=.44,Full=true,Keys={{0,0,0,0,0,0,0},{.12,150,-40,40,100,-35,-10},{.2,30,12,0,45,30,18},{.28,14,22,8,25,38,18},{.44,0,0,0,0,0,0}}},
 -- Butterfly Catcher (concept "УДАР"): a sweeping butterfly-catching scoop: the net goes up and back
 -- over the right shoulder with the body turned away, sweeps down and forward in a wide arc onto the
 -- ore (the film leads, the trail draws the arc), then a little flick back up as if something was
 -- caught. Full keys (see Reap). Checked with the R15 block rig numbers: the hoop stays 3+ studs from
 -- the head through the whole arc.
 Scoop={Length=.42,Full=true,Keys={{0,0,0,0,0,0,0},{.11,140,-34,30,80,-28,-8},{.19,40,18,4,40,26,16},{.26,62,10,10,46,14,8},{.33,46,4,6,32,6,4},{.42,0,0,0,0,0,0}}},
 -- Laughsaw (concept "УДАР"): a heavy diagonal saw slam: the head goes up high over the right shoulder
 -- with the body turned away, crashes down across onto the ore and GRINDS there (the arms judder a few
 -- times while the blade bites, MiningClient.PickFX screams it round), then pulls free. Full keys (see Reap).
 Rip={Length=.48,Full=true,Keys={{0,0,0,0,0,0,0},{.13,165,-30,45,110,-32,-12},{.21,38,14,0,50,28,18},{.25,46,11,3,54,24,16},
  {.29,36,15,0,48,28,18},{.33,44,11,3,52,24,16},{.37,38,14,0,48,27,17},{.48,0,0,0,0,0,0}}},
}
-- LEGO Hand (concept "УДАР"): a bouncy plastic slam: the hand goes up high over the right shoulder, comes
-- down diagonally in a wide golden arc onto the ore (the finger clacks shut, PickFX), bounces back up like
-- a toy and settles. Full keys (see Reap).
SWINGS.Clack={Length=.42,Full=true,Keys={{0,0,0,0,0,0,0},{.12,158,-24,40,100,-28,-10},{.2,32,14,2,46,26,16},{.26,54,8,10,52,16,9},
 {.32,36,12,4,44,20,12},{.42,0,0,0,0,0,0}}}
-- Pickaxe 67 (concept "УДАР"): a heavy meme slam with a glitch in it: the head goes up high over the right
-- shoulder and FREEZES there for a few frames (a dropped-frame stutter), slams down diagonally onto the ore
-- in a red arc, then double-taps (a second glitch jolt on the ore, the digits jump, MiningClient.PickFX) and
-- comes back. Full keys (see Reap).
SWINGS.SixSeven={Length=.44,Full=true,Keys={{0,0,0,0,0,0,0},{.11,160,-26,42,104,-30,-11},{.15,162,-25,42,106,-31,-11},
 {.21,30,14,0,46,28,17},{.245,42,10,4,52,22,14},{.28,30,14,0,46,28,17},{.44,0,0,0,0,0,0}}}
-- Rotten Slime Slug (concept "Удар"): a heavy wet overhead chop that STICKS to the ore for a beat (the slime
-- holds it), then tears free with a jerk ("shlorp", the eyes shoot out on their threads, MiningClient.PickFX)
-- and wobbles back. Keys as Chop.
SWINGS.Slurp={Length=.46,Keys={{0,0,0,0,0,0},{.12,156,46,94,-15,-7},{.19,26,4,36,10,15},{.28,30,5,38,10,15},{.32,58,16,56,4,5},
 {.37,38,8,40,6,8},{.46,0,0,0,0,0}}}
-- Toothy Alarm Clock (concept "УДАР"): a heavy overhead club slam: the clock goes up high behind the head, crashes
-- down onto the ore and the arms judder with the RING (the head rattles, the bells shake, the jaw bites,
-- MiningClient.PickFX), then it comes back. Keys as Chop.
SWINGS.Alarm={Length=.48,Keys={{0,0,0,0,0,0},{.13,165,52,100,-16,-8},{.21,24,2,34,12,16},{.25,34,6,40,9,13},{.29,26,3,35,11,15},
 {.33,32,5,38,9,13},{.37,27,3,36,10,14},{.48,0,0,0,0,0}}}
-- Zombie-Frankenstein (concept "Удар": "электрический всплеск + судорожный рывок"): a heavy overhead slam, then the
-- electric surge: the arms jerk in irregular convulsions on the ore (the head shudders, the jaw bites, the blade and
-- the claw clench, MiningClient.PickFX), then it comes back. Keys as Chop.
SWINGS.Franken={Length=.5,Keys={{0,0,0,0,0,0},{.13,162,50,98,-15,-8},{.21,24,2,34,12,16},{.245,38,9,42,7,12},{.27,22,1,33,14,17},
 {.31,33,7,40,8,13},{.335,25,2,35,13,16},{.38,30,5,37,10,14},{.5,0,0,0,0,0}}}
-- Clown Chronomord (concept "УДАР": a wide red arc): the clock goes up high over the right shoulder with the body turned
-- away, comes down diagonally onto the ore in a big arc (the tongue lashes out, the eyes bulge, the hands whirl,
-- MiningClient.PickFX), bounces back up like a jack-in-the-box and settles with a little wobble. Full keys (see Reap).
SWINGS.Chrono={Length=.46,Full=true,Keys={{0,0,0,0,0,0,0},{.12,160,-28,42,102,-30,-11},{.2,32,14,2,46,28,17},{.26,52,8,10,52,16,9},
 {.31,34,12,4,44,22,13},{.36,44,10,6,48,18,11},{.46,0,0,0,0,0,0}}}
-- Nasty Octopus (concept "HIT (MINE)" / "TENTACLE LASH": a quick tentacle snap): the octopus goes up high over the right shoulder
-- with the body turned away, WHIPS down diagonally onto the ore faster than a chop (the tentacles spread open and the eye bulges,
-- MiningClient.PickFX), snaps a little past it like a lash, then recoils up off the ore with a wet wobble and settles. Full keys
-- (see Reap).
SWINGS.Octo={Length=.44,Full=true,Keys={{0,0,0,0,0,0,0},{.12,160,-28,42,102,-30,-11},{.185,28,14,0,44,28,17},{.225,16,17,-2,38,32,19},
 {.29,48,8,8,50,18,10},{.34,32,11,4,44,22,13},{.38,40,10,6,47,19,11},{.44,0,0,0,0,0,0}}}
-- Hand of Fate (concept "УДАР": a wide purple arc): the hand goes up high over the right shoulder with the body turned away,
-- slams down diagonally onto the ore in a big arc, GRABS it (the claws squeeze shut, the eye bulges, MiningClient.PickFX)
-- and holds for a beat with a straining tremor, then rips back up off the ore and settles. Full keys (see Reap).
SWINGS.Fate={Length=.5,Full=true,Keys={{0,0,0,0,0,0,0},{.13,165,-30,45,110,-32,-12},{.21,30,14,0,46,28,18},{.25,34,13,2,48,26,17},
 {.29,29,14,0,45,28,18},{.33,33,13,2,47,26,17},{.39,58,6,12,54,14,8},{.5,0,0,0,0,0,0}}}
function Anim.new(ctx)
 local self:any={}
 local rigs={} -- character -> pose state
 local function motor(character,...)
  for _,name in ipairs({...})do
   local m=character:FindFirstChild(name,true)
   if m and m:IsA('Motor6D')then return m end
  end
  return nil
 end
 local function rig(character)
  if not character then return nil end
  local r=rigs[character]
  if not r then
   r={SwingStart=-1,SwingPower=1,Style='Chop',Side=1,Lifting=false,LiftTarget=0,LiftValue=0,RepStart=-1,DrawStart=-1,Ready=false,ReadyValue=0,InspectStart=-1,InspectKeys=INSPECT,
    ClawCount=0,ClawLast=-10,ClawMove='R',ClawHold=false,HoldValue=0,RunValue=0}
   r.RS=motor(character,'RightShoulder','Right Shoulder')
   r.RE=motor(character,'RightElbow')
   r.LS=motor(character,'LeftShoulder','Left Shoulder')
   r.LE=motor(character,'LeftElbow')
   r.RW=motor(character,'RightWrist')
   r.LW=motor(character,'LeftWrist')
   r.Waist=motor(character,'Waist')
   r.Root=motor(character,'Root')
   r.RH=motor(character,'RightHip');r.LH=motor(character,'LeftHip')
   r.RK=motor(character,'RightKnee');r.LK=motor(character,'LeftKnee')
   if not r.RS then return nil end
   rigs[character]=r
   character.Destroying:Once(function()rigs[character]=nil end)
  end
  return r
 end
 local function characterOf(who)
  if who==nil then return ctx.Player.Character end
  if typeof(who)=='Instance'and who:IsA('Player')then return who.Character end
  return who
 end

 -- One strike. power ~1; style from the pickaxe (Swing). who: nil (local), a Player or a model.
 function self.Swing(power,who,style)
  local r=rig(characterOf(who));if not r then return end
  r.SwingStart=os.clock();r.SwingPower=power or 1;r.Style=style or'Chop'
  if r.InspectStart>=0 then
   r.InspectStart=-1
   if r.RW then r.RW.Transform=CFrame.identity end
   if r.LW then r.LW.Transform=CFrame.identity end
  end
  if r.Style=='Claw'then
   -- right, left, right, CROSS: a chain restarts after a pause (CLAW.Chain)
   if r.SwingStart-r.ClawLast>CLAW.Chain then r.ClawCount=0;r.Side=-1 end
   r.ClawLast=r.SwingStart;r.ClawCount+=1
   if r.ClawCount%4==0 then r.ClawMove='X'else r.Side=-r.Side;r.ClawMove=r.Side>0 and'R'or'L'end
  else
   r.Side=-r.Side -- Slash alternates
  end
 end
 -- Twin Claws: which hand made the last strike of this character ('R', 'L' or 'X' = both), for
 -- the hit effects (MiningClient.PickFX); nil without a rig.
 function self.ClawMove(who)
  local r=rig(characterOf(who))
  return r and r.ClawMove or nil
 end
 -- Draw the pickaxe from the back (session start).
 function self.Draw(who)
  local r=rig(characterOf(who));if not r then return end
  r.DrawStart=os.clock()
 end
 -- Inspect the pickaxe in the hand (local player: MiningClient.Tool); Cancel puts it back.
 -- style (optional): the pickaxe's Swing, for its own inspect keys (INSPECTS).
 function self.Inspect(who,style)
  local r=rig(characterOf(who));if not r then return end
  r.InspectStart=os.clock();r.InspectKeys=style=='Claw'and CLAW.Inspect or INSPECTS[style or'']or INSPECT
  r.InspectBoth=style=='Claw'
 end
 function self.CancelInspect(who)
  local r=rig(characterOf(who));if not r then return end
  if r.InspectStart>=0 then
   r.InspectStart=-1
   if r.RW then r.RW.Transform=CFrame.identity end
   if r.LW then r.LW.Transform=CFrame.identity end
  end
 end
 function self.Inspecting(who)
  local r=rig(characterOf(who))
  return r~=nil and r.InspectStart>=0 and os.clock()-r.InspectStart<Anim.INSPECT_TIME
 end
 -- Hold the pickaxe up, ready to strike, while a mining session runs.
 function self.SetReady(active,who,style)
  local r=rig(characterOf(who));if not r then return end
  r.Ready=active==true
  if style then r.Style=style end
 end
 -- Lift pose: 0 = weight at the chest, 1 = arms locked overhead.
 function self.SetLift(active,progress,who)
  local r=rig(characterOf(who));if not r then return end
  r.Lifting=active;r.LiftTarget=math.clamp(progress or 0,0,1)
  if not active then r.LiftValue=0;r.RepStart=-1 end
 end
 -- One full repetition for a remote lifter (the local player drives SetLift from the meter).
 function self.Rep(who)
  local r=rig(characterOf(who));if not r then return end
  r.Lifting=true;r.RepStart=os.clock()
 end

 local function set(m,cf)if m then m.Transform=cf end end
 local function pose(r,dt)
  local rs,re,ls,le=r.RS,r.RE,r.LS,r.LE
  local now=os.clock()
  r.ReadyValue+=((r.Ready and 1 or 0)-r.ReadyValue)*math.min(1,(dt or 1/60)*10)
  if r.InspectStart>=0 and now-r.InspectStart>=Anim.INSPECT_TIME then
   r.InspectStart=-1;set(r.RW,CFrame.identity);set(r.LW,CFrame.identity)
  end
  local t=now-r.SwingStart
  local style=r.Style
  local spec=SWINGS[style]
  local claw=style=='Claw'and CLAW[r.ClawMove]or nil
  if claw then spec=claw end
  local length=spec and spec.Length or(style=='Slash'and .36 or .26)
  -- Twin Claws held outside a session: the idle / run hold blends in and out (r.ClawHold is set
  -- by the scan below for every character with the claws in its hands).
  local holding=r.ClawHold and not r.Lifting and r.ReadyValue<.5 and not(r.InspectStart>=0)and not(t>=0 and t<length)
  r.HoldValue+=((holding and 1 or 0)-r.HoldValue)*math.min(1,(dt or 1/60)*8)
  if t>=0 and t<length then
   local p=math.min(1.15,r.SwingPower)
   if claw then
    local a,z,elbow,la,lz,lelbow,twist,lean=keys(spec.Keys,t)
    set(rs,CFrame.Angles(rad(a*p),0,rad(z)))
    set(re,CFrame.Angles(rad(elbow),0,0))
    set(ls,CFrame.Angles(rad(la*p),0,rad(lz)))
    set(le,CFrame.Angles(rad(lelbow),0,0))
    set(r.Waist,CFrame.Angles(rad(lean),rad(twist),0))
   elseif spec and spec.Full then
    local a,z,elbow,left,twist,lean=keys(spec.Keys,t)
    set(rs,CFrame.Angles(rad(a*p),0,rad(z)))
    set(re,CFrame.Angles(rad(elbow),0,0))
    set(ls,CFrame.Angles(rad(left*p),0,rad(10)))
    set(r.Waist,CFrame.Angles(rad(lean),rad(twist),0))
   elseif spec then
    local a,elbow,left,twist,lean=keys(spec.Keys,t)
    set(rs,CFrame.Angles(rad(a*p),0,rad(-8)))
    set(re,CFrame.Angles(rad(elbow),0,0))
    set(ls,CFrame.Angles(rad(left*p),0,rad(10)))
    set(r.Waist,CFrame.Angles(rad(lean),rad(twist),0))
   elseif style=='Slash'then
    -- Arm forward at shoulder height, sweeping across the body; the waist follows.
    local sweep,raise,twist=keys({{0,0,40,0},{.1,75*r.Side,95,-24*r.Side},{.2,-80*r.Side,85,26*r.Side},{.36,0,40,0}},t)
    set(rs,CFrame.Angles(rad(raise),rad(sweep),0))
    set(re,CFrame.Angles(rad(10),0,0))
    set(ls,CFrame.Angles(rad(raise*.6),rad(sweep*.5),0))
    set(r.Waist,CFrame.Angles(rad(6),rad(twist),0))
   else -- Claw: a forward jab with one arm (alternating), the other pulls back
    local jab,elbow,twist=keys({{0,30,70,0},{.08,95,0,22},{.26,30,70,0}},t)
    local main,other=r.Side>0 and rs or ls,r.Side>0 and ls or rs
    set(main,CFrame.Angles(rad(jab),0,0))
    set(r.Side>0 and re or le,CFrame.Angles(rad(elbow),0,0))
    set(other,CFrame.Angles(rad(40),0,0))
    set(r.Side>0 and le or re,CFrame.Angles(rad(80),0,0))
    set(r.Waist,CFrame.Angles(0,rad(twist*r.Side),0))
   end
  elseif r.DrawStart>=0 and now-r.DrawStart<.45 and r.Style~='Claw'then -- gloves are never on the back
   -- Reach over the shoulder for the pickaxe on the back, then bring it forward.
   local a,z=keys({{0,0,0},{.18,170,-25},{.45,40,0}},now-r.DrawStart)
   set(rs,CFrame.Angles(rad(a),0,rad(z)))
   set(re,CFrame.Angles(rad(a>90 and 60 or 10),0,0))
  elseif r.InspectStart>=0 and now-r.InspectStart<Anim.INSPECT_TIME and r.InspectBoth then
   local a,z,elbow,la,lz,lelbow,twist,lean,wrist=keys(r.InspectKeys,now-r.InspectStart)
   set(rs,CFrame.Angles(rad(a),0,rad(z)));set(re,CFrame.Angles(rad(elbow),0,0))
   set(ls,CFrame.Angles(rad(la),0,rad(lz)));set(le,CFrame.Angles(rad(lelbow),0,0))
   set(r.RW,CFrame.Angles(0,rad(wrist),0));set(r.LW,CFrame.Angles(0,rad(-wrist),0))
   set(r.Waist,CFrame.Angles(rad(lean),rad(twist),0))
  elseif r.InspectStart>=0 and now-r.InspectStart<Anim.INSPECT_TIME then
   local a,z,elbow,wx,wz,twist=keys(r.InspectKeys or INSPECT,now-r.InspectStart)
   set(rs,CFrame.Angles(rad(a),0,rad(z)))
   set(re,CFrame.Angles(rad(elbow),0,0))
   set(r.RW,CFrame.Angles(rad(wx),0,rad(wz)))
   set(r.Waist,CFrame.Angles(0,rad(twist),0))
  elseif r.Lifting then
   if r.RepStart>=0 then
    local a=(now-r.RepStart)/REP_TIME
    if a>=1 then r.RepStart=-1;r.LiftTarget=0 else r.LiftTarget=a<.5 and ease(0,1,a*2)or ease(1,0,(a-.5)*2)end
   end
   r.LiftValue+=(r.LiftTarget-r.LiftValue)*math.min(1,(dt or 1/60)*14)
   local v=r.LiftValue
   local arm=70+v*105
   local bend=(1-v)*85
   set(rs,CFrame.Angles(rad(arm),0,rad(-6)))
   set(re,CFrame.Angles(rad(bend),0,0))
   set(ls,CFrame.Angles(rad(arm),0,rad(6)))
   set(le,CFrame.Angles(rad(bend),0,0))
   -- R15: squat at the bottom of the lift and drive up with the legs; strain wobble at the top.
   local squat=(1-v)*.8
   local strain=v>.85 and math.sin(now*38)*.6 or 0
   set(r.Root,CFrame.new(0,-squat*.55,0)*CFrame.Angles(rad(-squat*8),0,rad(strain)))
   set(r.RH,CFrame.Angles(rad(squat*38),0,0));set(r.LH,CFrame.Angles(rad(squat*38),0,0))
   set(r.RK,CFrame.Angles(rad(-squat*62),0,0));set(r.LK,CFrame.Angles(rad(-squat*62),0,0))
   set(r.Waist,CFrame.Angles(rad(squat*10-v*4),0,0))
  elseif r.ReadyValue>.02 then
   local k=r.ReadyValue
   local breathe=math.sin(now*2.2)*3
   if r.Style=='Claw'then -- fighting stance: both gauntlets up, the claws a little apart
    set(rs,CFrame.Angles(rad((40+breathe)*k),0,rad(6*k)));set(ls,CFrame.Angles(rad((40-breathe)*k),0,rad(-6*k)))
    set(re,CFrame.Angles(rad(50*k),0,0));set(le,CFrame.Angles(rad(50*k),0,0))
   else
    set(rs,CFrame.Angles(rad((38+breathe)*k),0,rad(-6*k)))
    set(ls,CFrame.Angles(rad((26+breathe)*k),0,rad(14*k)))
    set(re,CFrame.Angles(rad(25*k),0,0))
   end
  elseif r.HoldValue>.02 then
   -- Twin Claws IDLE / RUN hold (replaces the default tool pose of the right arm and the arm swing)
   local k=r.HoldValue
   local root=r.RS.Parent and r.RS.Parent.Parent and r.RS.Parent.Parent:FindFirstChild('HumanoidRootPart')
   local v=root and root.AssemblyLinearVelocity or Vector3.zero
   local want=math.clamp((Vector3.new(v.X,0,v.Z).Magnitude-6)/10,0,1)
   r.RunValue+=(want-r.RunValue)*math.min(1,(dt or 1/60)*6)
   local run=r.RunValue
   local H,R=CLAW.Hold,CLAW.Run
   local breathe=math.sin(now*1.8)*3*(1-run)
   local sx=(H[1]+(R[1]-H[1])*run)*k
   local sz=(H[2]+(R[2]-H[2])*run)*k
   local el=(H[3]+(R[3]-H[3])*run)*k
   set(rs,CFrame.Angles(rad(sx+breathe),0,rad(sz)));set(ls,CFrame.Angles(rad(sx-breathe),0,rad(-sz)))
   set(re,CFrame.Angles(rad(el),0,0));set(le,CFrame.Angles(rad(el),0,0))
   set(r.Waist,CFrame.Angles(rad((H[4]+(R[4]-H[4])*run)*k),0,0))
  end
 end

 RunService.Stepped:Connect(function(_,dt)
  for character,r in pairs(rigs)do
   if character.Parent and r.RS.Parent then pose(r,dt)else rigs[character]=nil end
  end
 end)
 -- Twin Claws in the hands (MiningWorld mounts the left gauntlet "MiningHeldPickaxeL" only while
 -- they are held): those characters get the claw hold. Scanned 4x a second, nearby players only.
 local function holdingClaws(character)
  local l=character and character:FindFirstChild('MiningHeldPickaxeL')
  if not(l and l:GetAttribute('Mount')=='GloveL')then return false end
  local hum=character:FindFirstChildOfClass('Humanoid')
  if not hum or hum.Health<=0 or hum.Sit then return false end
  local st=hum:GetState()
  return st==Enum.HumanoidStateType.Running or st==Enum.HumanoidStateType.RunningNoPhysics or st==Enum.HumanoidStateType.Landed
 end
 task.spawn(function()
  while true do
   task.wait(.25)
   local ok,err=pcall(function()
    local cam=workspace.CurrentCamera
    for _,p in ipairs(Players:GetPlayers())do
     local character=p.Character
     local root=character and character:FindFirstChild('HumanoidRootPart')
     local near=root and cam and(root.Position-cam.CFrame.Position).Magnitude<160
     local want=near and holdingClaws(character)or false
     local r=want and rig(character)or rigs[character]
     if r then r.ClawHold=want end
    end
   end)
   if not ok and ctx.Report then ctx.Report('claw hold: '..tostring(err))end
  end
 end)

 -- Remote players: swing on every replicated hit, hold the lift pose while their corner says
 -- Training and do one rep per TrainSerial step. The owner of a corner is found by UserId.
 local function ownerOf(corner)
  local id=corner:GetAttribute('OwnerUserId')or 0
  if id==0 or id==ctx.Player.UserId then return nil end
  return Players:GetPlayerByUserId(id)
 end
 function self.RemoteHit(corner)
  local owner=ownerOf(corner);if not owner then return end
  local level=(corner:GetAttribute('PickaxeLevel')or 1)
  local def=Skins.For(owner,ctx.M.Pickaxes[level])
  self.Swing(1+(level-1)*.01,owner,def and def.Swing)
  if ctx.PickFX then ctx.PickFX.HitPulse(owner.Character,1)end
 end
 function self.RemoteTraining(corner,repped)
  local owner=ownerOf(corner);if not owner then return end
  if corner:GetAttribute('Training')==true then
   if repped then self.Rep(owner)else self.SetLift(true,0,owner)end
  else
   self.SetLift(false,0,owner)
  end
 end
 -- Remote miners hold their pickaxe ready while their corner is Active.
 function self.RemoteActive(corner)
  local owner=ownerOf(corner);if not owner then return end
  local level=(corner:GetAttribute('PickaxeLevel')or 1)
  local def=Skins.For(owner,ctx.M.Pickaxes[level])
  local r=rig(owner.Character);if r then r.Style=def and def.Swing or'Chop'end
  self.SetReady(corner:GetAttribute('Active')==true,owner)
 end

 return self
end

return Anim
