local RS=game:GetService('ReplicatedStorage');local L=game:GetService('Lighting');local C=require(RS.LightingConfig)
C.ApplyPreset()
-- Halloween (WP10a): replicated day/night flag for clients (Lighting attributes are never overridden locally, unlike ClockTime)
local function publishDay(day)local f=math.floor(day*100+.5)/100;if L:GetAttribute('DayFactor')~=f then L:SetAttribute('DayFactor',f)end;if L:GetAttribute('IsNight')~=(day<.05)then L:SetAttribute('IsNight',day<.05)end end
publishDay(math.clamp((math.cos((L.ClockTime-13)*math.pi/12)+.2)*1.2,0,1))
local ev=RS:FindFirstChild('LightingRefreshEvent')or Instance.new('BindableEvent');ev.Name='LightingRefreshEvent';ev.Parent=RS;ev.Event:Connect(C.ApplyPreset)
task.spawn(function()while true do task.wait(1)
 local event=RS.WorldEvents.State:GetAttribute('State')
 if C.DayCycle.Enabled and (event==nil or event=='NORMAL')then
  L.ClockTime=(L.ClockTime+24/(C.DayCycle.Minutes*60))%24
  local day=math.clamp((math.cos((L.ClockTime-13)*math.pi/12)+.2)*1.2,0,1)
  L.Brightness=1.25+day*1.2;L.ExposureCompensation=.18*(1-day);L.Ambient=Color3.fromRGB(102,110,142):Lerp(C.Preset.Ambient,day);L.OutdoorAmbient=Color3.fromRGB(116,126,154):Lerp(C.Preset.OutdoorAmbient,day)
  publishDay(day) -- Halloween (WP10a)
 end
end end)
print('DOGROTS_LIGHTING_APPLIED',L.ClockTime)
