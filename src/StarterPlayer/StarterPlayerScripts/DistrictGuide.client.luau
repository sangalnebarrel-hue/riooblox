-- DISTRICT GUIDE: the district map (M, ToggleDistrictMap, the directory prompt) and the route chip.
-- Every "SHOW THE WAY" (GUIIntegration N.Navigate -> NavigateDistrict:Fire(name)) and every map
-- row starts a route of glowing ground arrows (ReplicatedStorage.Navigation.PathGuide). Names,
-- keys and aliases resolve through Navigation.Destinations, so old callers ("Your yard",
-- "Factory", "THE DOG", "Mutation lab", "DOG-O-MATIC PLAZA", "Dog Shelter"...) keep working.
-- The HUD chip "-> LAB 120 m X" (ClearMarker, placed by UITheme.LayoutHUD) shows the active
-- route and clears it. docs/NAVIGATION.md.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local PPS=game:GetService("ProximityPromptService")
local Run=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local root=playerGui:FindFirstChild("ScreenGui")
while not root do
 local child=playerGui.ChildAdded:Wait()
 if child.Name=="ScreenGui" then root=child end
end
local NavFolder=RS:WaitForChild("Navigation")
local PathGuide=require(NavFolder:WaitForChild("PathGuide"))
local Destinations=require(NavFolder:WaitForChild("Destinations"))
local RouteGraph=require(NavFolder:WaitForChild("RouteGraph"))
local Routing=require(RS:WaitForChild('MapRouting'))
PathGuide.Start()
local T=PathGuide.T
local function lang()return T("en","ru")end

local gui=Instance.new("Frame");gui.Name="DistrictGuide";gui.Size=UDim2.fromScale(1,1);gui.BackgroundTransparency=1;gui.ZIndex=60;gui.Parent=root
local C=Color3.fromRGB
local U=require(root.Modules.UITheme)
local colors={bg=U.Colors.metal,panel=U.Colors.navy,ink=U.Colors.text,muted=U.Colors.muted,accent=U.Colors.orange}
local function make(class,props,parent):any
 if class=="TextLabel"or class=="TextButton"then props.Font=nil;props.FontFace=U.FontFace;props.ZIndex=props.ZIndex or 4 end
 local o=Instance.new(class);for k,v in pairs(props) do o[k]=v end;o.Parent=parent
 if class=="TextButton"then U.Round(o,8);U.Stroke(o,U.Colors.edge,3)end;return o
end
local function text(parent,txt,pos,size,font,color):any
 return make("TextLabel",{Text=txt,Position=pos,Size=size,BackgroundTransparency=1,
  TextColor3=color or colors.ink,Font=font or Enum.Font.FredokaOne,TextSize=16,
  TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true},parent)
end
-- Self-localized label (AutoTranslate leaves it alone).
local function own(label):any label:SetAttribute("NoTranslate",true);return label end

local veil=make("Frame",{Name="MapOverlay",Visible=false,Size=UDim2.fromScale(1,1),BackgroundColor3=C(10,17,21),BackgroundTransparency=1,BorderSizePixel=0,Active=true},gui)
local panel=make("Frame",{Name="Directory",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(700,490),BackgroundColor3=colors.bg,BorderSizePixel=0},veil)
U.Round(panel,14);U.Stroke(panel,U.Colors.edge,5)
local mapHeader=U.Header(panel,"MapHeader",8,8,684,72)
local heading=text(panel,"DOGROTS",UDim2.fromOffset(24,15),UDim2.fromOffset(260,34),Enum.Font.FredokaOne);heading.TextSize=27
text(panel,"DISTRICT MAP",UDim2.fromOffset(24,51),UDim2.fromOffset(260,22),Enum.Font.FredokaOne,colors.accent).TextSize=12
local close=make("TextButton",{Text="X",Font=Enum.Font.FredokaOne,TextSize=18,TextColor3=colors.ink,BackgroundColor3=colors.panel,BorderSizePixel=0,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-16,0,16),Size=UDim2.fromOffset(36,36)},panel)
local schematic=make("Frame",{Name="Schematic",Position=UDim2.fromOffset(22,94),Size=UDim2.fromOffset(300,338),BackgroundColor3=colors.panel,BorderSizePixel=0,ClipsDescendants=true},panel)
text(schematic,"DOGROTS / ISLAND DIRECTORY",UDim2.fromOffset(12,8),UDim2.fromOffset(220,20),Enum.Font.FredokaOne,colors.muted).TextSize=11

-- The schematic shows the island (X -220..220, Z -260..770), stretched to the panel.
local LOW,HIGH=Vector3.new(-220,0,-260),Vector3.new(220,0,770)
local function xy(v)
 return math.clamp((v.X-LOW.X)/(HIGH.X-LOW.X),0.03,0.97),math.clamp((v.Z-LOW.Z)/(HIGH.Z-LOW.Z),0.03,0.97)
end
-- World position of a destination for the map dot: the live anchor, else the route target.
local function placeOf(entry)
 if entry.Category=="Plot"then
  local id=tonumber(player:GetAttribute("YardId"))
  local target=id and RouteGraph.Target(entry.Key,{YardId=id})
  if target then return target.Pointer end
  return player:GetAttribute("YardSpawnPosition")
 end
 local ok,pos=pcall(Routing.Position,entry.Key,player)
 if ok and typeof(pos)=="Vector3"then return pos end
 local target=RouteGraph.Target(entry.Key)
 return target and target.Pointer or nil
end

local locations={}
local byKey={}
for i,entry in ipairs(Destinations.List) do
 local loc={entry=entry,key=entry.Key,sealed=entry.Sealed,color=Destinations.Color(entry),pos=placeOf(entry) or Vector3.zero,index=i}
 table.insert(locations,loc);byKey[entry.Key]=loc
end
local ROW=58
local list=make("ScrollingFrame",{Name="Destinations",Position=UDim2.fromOffset(342,91),Size=UDim2.fromOffset(338,348),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=colors.accent,CanvasSize=UDim2.fromOffset(0,#locations*ROW),ScrollingDirection=Enum.ScrollingDirection.Y},panel)
local function defaultHint()return T("Choose a place: glowing arrows on the ground will lead you there.","Выбери место — светящиеся стрелки на земле приведут тебя туда.")end
local hint=own(text(panel,defaultHint(),UDim2.fromOffset(24,450),UDim2.new(1,-48,0,24),Enum.Font.FredokaOne,colors.muted));hint.TextSize=13;hint.TextColor3=U.Colors.edge
local function toggle() veil.Visible=not veil.Visible end
-- Each sealed place names itself: "THE VOID — SEALED / FUTURE AREA", "GLOBAL EVENT — COMING SOON".
local function sealedHint(loc)
 local l=lang()
 return string.upper(Destinations.Text(loc.entry,"Name",l)).." — "..Destinations.Text(loc.entry,"Detail",l)
end
local FAILURES={
 noyard={"Your yard is not ready yet. Try again in a moment.","Участок ещё не готов. Попробуй через минуту."},
 unknown={"This place is not on the map.","Этого места нет на карте."},
}
local function failure(reason)local row=FAILURES[reason]or FAILURES.unknown;return T(row[1],row[2])end

-- Starts the route to a destination (rows, map dots, NavigateDistrict). false = map stays open.
local function choose(loc)
 if loc.sealed then hint.Text=sealedHint(loc);veil.Visible=true;return false end
 local ok,reason=PathGuide.Show(loc.key)
 if ok then hint.Text=defaultHint();veil.Visible=false;return true end
 hint.Text=reason=="sealed"and sealedHint(loc)or failure(reason);veil.Visible=true
 return false
end
close.Activated:Connect(toggle)

local rows={}
for i,loc in ipairs(locations) do
 local entry=loc.entry
 local b=make("TextButton",{Name="Destination_"..i,Text="",Position=UDim2.fromOffset(0,(i-1)*ROW),Size=UDim2.new(1,-9,0,ROW-5),BackgroundColor3=colors.panel,BorderSizePixel=0,AutoButtonColor=false},list)
 make("Frame",{Size=UDim2.new(0,3,1,0),BackgroundColor3=loc.color,BorderSizePixel=0},b)
 local icon=own(text(b,entry.Icon,UDim2.fromOffset(9,0),UDim2.new(0,30,1,0),Enum.Font.FredokaOne));icon.TextSize=20;icon.TextXAlignment=Enum.TextXAlignment.Center
 local name=own(text(b,Destinations.Text(entry,"Name",lang()),UDim2.fromOffset(42,5),UDim2.new(1,-150,0,23),Enum.Font.FredokaOne));name.TextSize=15;name.TextWrapped=false;name.TextTruncate=Enum.TextTruncate.AtEnd
 local detail=own(text(b,Destinations.Text(entry,"Detail",lang()),UDim2.fromOffset(42,28),UDim2.new(1,-150,0,18),Enum.Font.FredokaOne,colors.muted));detail.TextSize=11;detail.TextWrapped=false;detail.TextTruncate=Enum.TextTruncate.AtEnd
 -- SHOW PATH pill (a label inside the row: the whole row is the button).
 local pill=make("Frame",{Name="ShowPath",AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-8,0.5,0),Size=UDim2.fromOffset(98,30),BackgroundColor3=loc.sealed and C(150,162,180)or loc.color,BorderSizePixel=0,ZIndex=4},b)
 U.Round(pill,15)
 local pillText=own(text(pill,"",UDim2.fromScale(0,0),UDim2.fromScale(1,1),Enum.Font.FredokaOne,C(255,255,255)));pillText.TextSize=12;pillText.TextXAlignment=Enum.TextXAlignment.Center;pillText.ZIndex=5
 pillText.TextStrokeTransparency=0.55;pillText.TextStrokeColor3=U.Colors.edge
 rows[loc.key]={Button=b,Pill=pill,PillText=pillText,Name=name,Detail=detail,Loc=loc}
 b.Activated:Connect(function()choose(loc)end)
 local x,y=xy(loc.pos)
 local dot=make("TextButton",{Name="MapDot_"..i,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(x,y),Size=UDim2.fromOffset(23,23),Text=tostring(i),TextColor3=colors.bg,TextSize=11,Font=Enum.Font.FredokaOne,BackgroundColor3=loc.color,BorderSizePixel=0},schematic)
 make("UICorner",{CornerRadius=UDim.new(1,0)},dot);dot.Activated:Connect(function()choose(loc)end)
 loc.dot=dot
end
-- Row captions follow the language and the active route.
local function paintRows()
 local active=PathGuide.Active()
 local l=lang()
 for key,row in pairs(rows)do
  local on=active and active.Key==key
  row.Name.Text=Destinations.Text(row.Loc.entry,"Name",l);row.Detail.Text=Destinations.Text(row.Loc.entry,"Detail",l)
  row.PillText.Text=row.Loc.sealed and T("SEALED","ЗАКРЫТО")or on and T("● ON ROUTE","● В ПУТИ")or T("SHOW PATH","ПОКАЗАТЬ ПУТЬ")
  row.Button.BackgroundColor3=on and row.Loc.color:Lerp(colors.panel,0.75)or colors.panel
 end
end
paintRows()
local playerDot=make("Frame",{Name="YouAreHere",AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(9,9),BackgroundColor3=C(255,255,255),BorderSizePixel=0,ZIndex=5},schematic)
make("UICorner",{CornerRadius=UDim.new(1,0)},playerDot)
make("UIStroke",{Color=colors.bg,Thickness=2},playerDot)
local function resize()
 -- Fit and centre the map inside the Core UI safe area (below the top bar, clear of the notch).
 local left,top,width,height=U.SafeArea(root);local compact=width<730
 local w=compact and math.min(430,width-24) or 700
 local h=math.max(220,math.min(490,height-24))
 panel.Position=UDim2.fromOffset(left+width/2,top+height/2)
 panel.Size=UDim2.fromOffset(w,h);mapHeader.Size=UDim2.fromOffset(w-16,72)
 schematic.Visible=not compact
 list.Position=UDim2.fromOffset(compact and 22 or 342,91)
 list.Size=UDim2.fromOffset(compact and w-44 or 338,h-142)
 schematic.Size=UDim2.fromOffset(300,h-151)
 hint.Position=UDim2.fromOffset(24,h-35)
end
resize();root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(resize)
UIS.InputBegan:Connect(function(input,processed)
 if processed or UIS:GetFocusedTextBox() then return end
 if input.KeyCode==Enum.KeyCode.M then toggle() end
end)
PPS.PromptTriggered:Connect(function(prompt)
 if prompt.Name=="DistrictDirectoryPrompt" then veil.Visible=true end
end)

-- The map ticks (5x per second) only while it is open: player dot and live dot positions.
local mapTick=nil
local function refreshDots()
 for _,loc in ipairs(locations)do
  local pos=placeOf(loc.entry)
  if pos then loc.pos=pos;local x,y=xy(pos);loc.dot.Position=UDim2.fromScale(x,y)end
 end
end
veil:GetPropertyChangedSignal("Visible"):Connect(function()
 if veil.Visible then
  refreshDots();paintRows()
  if not mapTick then
   local elapsed=0;local lastSize=Vector2.zero
   mapTick=Run.Heartbeat:Connect(function(dt)
    elapsed+=dt;if elapsed<0.2 then return end;elapsed=0
    local cam=workspace.CurrentCamera
    if cam and cam.ViewportSize~=lastSize then lastSize=cam.ViewportSize;resize() end
    local char=player.Character;local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart")then local x,y=xy(hrp.Position);playerDot.Position=UDim2.fromScale(x,y)end
   end)
  end
 else
  if mapTick then mapTick:Disconnect();mapTick=nil end
  hint.Text=defaultHint()
 end
end)
print("DOGROTS_GUIDE_READY")

-- Your yard moves with the yard you are given (by key: the old code wrote it into row 2).
local function updateYard()
 for _,loc in ipairs(locations)do
  if loc.entry.Category=="Plot"then
   local pos=placeOf(loc.entry)
   if pos then loc.pos=pos;local x,y=xy(pos);loc.dot.Position=UDim2.fromScale(x,y)end
  end
 end
end
updateYard()
player:GetAttributeChangedSignal("YardId"):Connect(updateYard)
player:GetAttributeChangedSignal("YardSpawnPosition"):Connect(updateYard)

------------------------------------------------------------------------------------------------
-- Route chip: "▲ LAB  120 m  ✕". Named ClearMarker so UITheme.LayoutHUD keeps it in the HUD's free
-- zone (top-left of it, clear of the tile columns, the counters and the touch controls).
------------------------------------------------------------------------------------------------
local chip=Instance.new("TextButton");chip.Name="ClearMarker";chip.Text="";chip.AutoButtonColor=false
chip.BackgroundTransparency=1;chip.BorderSizePixel=0;chip.Size=UDim2.fromOffset(214,40);chip.Position=UDim2.fromOffset(120,70)
chip.Visible=false;chip.ZIndex=61;chip.Parent=gui
local face=Instance.new("Frame");face.Name="Face";face.BackgroundColor3=C(23,43,76);face.BackgroundTransparency=0.08;face.BorderSizePixel=0
face.Size=UDim2.fromScale(1,1);face.ZIndex=61;face.Parent=chip
local faceCorner=Instance.new("UICorner");faceCorner.CornerRadius=UDim.new(0,20);faceCorner.Parent=face
local faceStroke=Instance.new("UIStroke");faceStroke.Thickness=2.5;faceStroke.Color=C(72,202,255);faceStroke.Parent=face
local function chipLabel(name,x,w,size,font,align)
 local l=Instance.new("TextLabel");l.Name=name;l.BackgroundTransparency=1;l.Position=UDim2.new(0,x,0,0);l.Size=UDim2.new(0,w,1,0)
 l.FontFace=Font.fromEnum(font);l.TextSize=size;l.TextColor3=C(255,255,255);l.TextXAlignment=align or Enum.TextXAlignment.Left
 l.TextTruncate=Enum.TextTruncate.AtEnd;l.ZIndex=62;l:SetAttribute("NoTranslate",true);l:SetAttribute("KeepFont",true);l.Parent=face
 return l
end
local chipArrow=chipLabel("Arrow",6,30,20,Enum.Font.FredokaOne,Enum.TextXAlignment.Center)
chipArrow.Text="▲"
local chipName=chipLabel("Place",36,96,16,Enum.Font.FredokaOne)
local chipDistance=chipLabel("Distance",134,52,14,Enum.Font.FredokaOne,Enum.TextXAlignment.Right)
local chipClose=chipLabel("Close",186,24,16,Enum.Font.FredokaOne,Enum.TextXAlignment.Center)
chipClose.Text="✕";chipClose.TextColor3=C(255,140,160)
chip.Activated:Connect(function()PathGuide.Clear("cleared")end)

local function chipSize()
 local _,_,width=U.SafeArea(root)
 local narrow=width<520
 local w=narrow and 178 or 214
 chip.Size=UDim2.fromOffset(w,narrow and 36 or 40)
 chipName.Size=UDim2.new(0,w-118,1,0);chipName.TextSize=narrow and 14 or 16
 chipDistance.Position=UDim2.new(0,w-80,0,0);chipClose.Position=UDim2.new(0,w-28,0,0)
end
chipSize();root:GetPropertyChangedSignal("AbsoluteSize"):Connect(chipSize)

local function chipVisible()
 local active=PathGuide.Active()
 chip.Visible=active~=nil and not veil.Visible and root:GetAttribute("OpenMenu")==nil
end
root:GetAttributeChangedSignal("OpenMenu"):Connect(chipVisible)
veil:GetPropertyChangedSignal("Visible"):Connect(chipVisible)
PathGuide.Changed:Connect(function(state)
 if state then
  faceStroke.Color=state.Color;chipArrow.TextColor3=state.Color
  chipName.Text=Destinations.Text(state.Entry,"Short",lang())
  chipDistance.Text=PathGuide.FormatDistance(state.Remaining or 0)
 end
 chipVisible();paintRows()
end)
PathGuide.Progress:Connect(function(state)
 chipDistance.Text=state.Arrived and "✓"or PathGuide.FormatDistance(state.Remaining or 0)
 chipArrow.Rotation=state.Heading or 0
end)

-- PAWPAD navigation events drive the district map and the routes.
local function connectNavigation(hud)
 if hud.Name ~= "ScreenGui" then return end
 gui.ZIndex=60
 U.LayoutHUD(hud) -- places ClearMarker (the route chip) in the HUD free zone
 local signal=hud:WaitForChild("ToggleDistrictMap",10)
 if signal and signal:IsA("BindableEvent") then
  signal.Event:Connect(function() veil.Visible=not veil.Visible end)
 end
 local navigate=hud:WaitForChild("NavigateDistrict",10)
 if navigate and navigate:IsA("BindableEvent") then navigate.Event:Connect(function(name)
  local loc=byKey[Destinations.Resolve(name) or ""]
  if loc then choose(loc) else hint.Text=defaultHint();veil.Visible=true end
 end) end
end
task.spawn(connectNavigation,root)
