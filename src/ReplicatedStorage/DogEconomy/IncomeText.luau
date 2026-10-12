-- Income text shared by the HUD, menus and world popups: compact coin numbers (1.2K, 3.4M, 5B)
-- and the few income phrases, in English or Russian. UI built with these strings localizes
-- itself and is marked NoTranslate (see DOGROTS_AutoTranslateUI), like ReplicatedStorage.Mining.MiningText.
-- Labels left to the auto-translator use the English forms in ReplicatedStorage.Localization.Income.
local T={}

local UNITS={{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}}
-- 950 -> "950", 1234 -> "1.2K", 98765 -> "98.8K", 123456 -> "123K", 2500000 -> "2.5M".
function T.Compact(n)
 n=tonumber(n)or 0
 if n~=n or n==math.huge or n==-math.huge then return '0' end
 local sign=n<0 and '-' or '';local a=math.abs(n)
 for _,unit in ipairs(UNITS)do
  local value=a/unit[1]
  -- 999,960 reads "1M", not "1000K".
  if value>=.9995 then
   local text=value>=99.95 and string.format('%.0f',value)or(string.format('%.1f',value):gsub('%.0$',''))
   return sign..text..unit[2]
  end
 end
 return sign..string.format('%.0f',math.floor(a+.5))
end

local cached=nil
function T.IsRussian()
 if cached~=nil then return cached end
 local ok,locale=pcall(function()
  local player=game:GetService('Players').LocalPlayer
  local service=game:GetService('LocalizationService')
  if game:GetService('RunService'):IsStudio()or not player then return service.RobloxLocaleId end
  return player.LocaleId or service.RobloxLocaleId
 end)
 cached=ok and type(locale)=='string'and locale:sub(1,2):lower()=='ru'or false
 return cached
end
function T.ResetLocale()cached=nil end

local S={
 PerMinute={'+$%1/min','+$%1/мин'},
 Popup={'+$%1','+$%1'},
 Income={'INCOME','ДОХОД'},
 NoIncome={'Put dogs in kennels to earn','Посади собак в будки — и они начнут приносить деньги'},
 ItemsFull={'FINDS FULL · SELL','НАХОДКИ: НЕТ МЕСТА · ПРОДАЙ'},
 Items={'Finds %1/%2','Находки %1/%2'},
 SellTip={'Your finds storage is full: sell finds at the collector in your yard','Место для находок закончилось: продай находки у сборщика в своём дворе'},
}
function T.Get(key,...)
 local row=S[key];if not row then return key end
 local args={...}
 return (string.gsub(T.IsRussian()and row[2]or row[1],'%%(%d)',function(i)return tostring(args[tonumber(i)or 0]or'')end))
end
-- "+$1.2K/min" (localized).
function T.PerMinute(n)return T.Get('PerMinute',T.Compact(n))end
-- English "$1.2K / min" for labels the auto-translator handles (Localization.Income pattern).
function T.PerMinuteLabel(n)return '$'..T.Compact(n)..' / min'end
return T
