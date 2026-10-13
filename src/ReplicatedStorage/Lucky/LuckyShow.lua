-- Shared look and timing for every Lucky Block presentation: the conveyor arrival, the block's
-- client aura, the opening on the Lucky Pad and the roulette. Presentation only; odds, prices
-- and rolls stay in LuckyBlockConfig / LuckyLifecycle.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local Config=require(game:GetService('ReplicatedStorage'):WaitForChild('LuckyBlockConfig'))
local S={}

S.Rarities=Config.Rarities
-- Vivid colours for neon, beams and shockwaves (index = rank).
S.World={Color3.fromRGB(214,224,234),Color3.fromRGB(46,170,255),Color3.fromRGB(190,84,255),Color3.fromRGB(255,198,52),
 Color3.fromRGB(255,56,98),Color3.fromRGB(150,72,255)}
-- Second colour of each tier (gradients, inner glow, sparks).
S.Accent={Color3.fromRGB(150,162,176),Color3.fromRGB(120,255,255),Color3.fromRGB(255,130,250),Color3.fromRGB(255,248,196),
 Color3.fromRGB(255,176,48),Color3.fromRGB(70,255,226)}
-- UI colours (same family as UITheme.U.Rarity, so cards match inventory and Dex).
S.UI={Color3.fromRGB(170,190,205),Color3.fromRGB(38,164,243),Color3.fromRGB(161,103,242),Color3.fromRGB(249,180,35),
 Color3.fromRGB(247,73,112),Color3.fromRGB(230,115,245)}
S.Names={EN={'COMMON','RARE','EPIC','LEGENDARY','MYTHIC','SECRET'},RU={'ОБЫЧНЫЙ','РЕДКИЙ','ЭПИЧЕСКИЙ','ЛЕГЕНДАРНЫЙ','МИФИЧЕСКИЙ','СЕКРЕТНЫЙ'}}

-- Seconds. Charge = the block powering up on the pad before it bursts; Reel = roulette spin
-- (desktop / low-FX); Land = winner flourish; SecretReveal = server delay between the open
-- commit and the yard-wide Secret dog cinematic, so the roulette lands first.
S.Timing={Charge=1.15,Reel=4.4,ReelLow=2.6,Land=1.1,SecretReveal=6.8,ArrivalGrace=6}

function S.Rank(tier)
 if type(tier)=='number'then return math.clamp(math.floor(tier),1,6)end
 return Config.Rank(tier)or 1
end
function S.Color(tier)return S.World[S.Rank(tier)]end
function S.AccentColor(tier)return S.Accent[S.Rank(tier)]end
function S.UIColor(tier)return S.UI[S.Rank(tier)]end

-- Same quality gates the game already uses (SecretArrivals.Kit, LuckyBlockFX).
function S.Low()
 local p=Players.LocalPlayer;if not p then return false end
 local choice=p:GetAttribute('WorldEventFX')
 return choice=='Low'or p:GetAttribute('LowFX')==true or p:GetAttribute('ReducedMotion')==true
  or(choice==nil and UIS.TouchEnabled)
end
function S.ReducedMotion()
 local p=Players.LocalPlayer;return p~=nil and p:GetAttribute('ReducedMotion')==true
end
-- Camera effects must leave scripted cameras (DOG-O-MATIC, mining, Secret cinematics) alone.
function S.CameraFree()
 local cam=workspace.CurrentCamera
 return cam~=nil and cam.CameraType~=Enum.CameraType.Scriptable and not cam:GetAttribute('SecretZoom')and not cam:GetAttribute('DiscoveryZoom')
end

return S
