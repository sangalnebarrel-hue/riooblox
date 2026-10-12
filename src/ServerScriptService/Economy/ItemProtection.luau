-- ItemProtection: the one registry of reasons a find must stay in its owner's inventory. Sales and
-- transfers ask it instead of each system checking every other system's flags.
--   Register(name, fn, contexts?)   fn(p, uid, item) -> reason string | nil. Pure and cheap: it runs
--                                   inside profile transactions, once per find. contexts limits it
--                                   to some of the contexts below ({Bulk=true}); nil = all of them.
--                                   Registering a name again replaces it. A showcase protector:
--                                     ItemProtection.Register('Showcase', function(p, uid)
--                                      return Showcase.Has(p, uid) and 'This find is on your showcase' end)
--   Reason(p, uid, context?, ignore?) -> the first reason (registration order) or nil
--   IsProtected(p, uid, context?, ignore?) -> boolean
-- Contexts: 'Sell' (one chosen find at the collector), 'Bulk' (BulkSell, "sell all" quotes),
-- 'Transfer' (trade offers, market listings, lab catalysts: ItemRules.Get(p, uid, true)).
-- context nil asks every protector. ignore = {[name]=true} skips protectors (BulkSell with
-- IncludeFavorites=true skips Favorite). A protector that errors protects the find (fail closed).
-- Built in: 'Favorite' (item.Favorite == true), for bulk sales only.
local P={List={},ByName={}}
P.Contexts={Sell=true,Bulk=true,Transfer=true}

function P.Register(name,fn,contexts)
 assert(type(name)=='string'and #name>0 and type(fn)=='function','ItemProtection.Register(name, fn[, contexts])')
 if contexts~=nil then
  assert(type(contexts)=='table','contexts must be a set such as {Bulk=true}')
  for context in pairs(contexts)do assert(P.Contexts[context],'Unknown protection context '..tostring(context))end
 end
 local row=P.ByName[name]
 if row then row.Fn=fn;row.Contexts=contexts
 else row={Name=name,Fn=fn,Contexts=contexts};P.ByName[name]=row;table.insert(P.List,row)end
end

function P.Reason(p,uid,context,ignore)
 local item=type(p)=='table'and type(p.Items)=='table'and p.Items[uid]or nil
 if type(item)~='table'then return nil end
 for _,row in ipairs(P.List)do
  if not(ignore and ignore[row.Name])and(context==nil or row.Contexts==nil or row.Contexts[context])then
   local ok,reason=pcall(row.Fn,p,uid,item)
   if not ok then return 'This find is protected ('..row.Name..')'end
   if type(reason)=='string'and reason~=''then return reason end
  end
 end
 return nil
end

function P.IsProtected(p,uid,context,ignore)return P.Reason(p,uid,context,ignore)~=nil end

P.Register('Favorite',function(_p,_uid,item)
 if item.Favorite==true then return 'Favorite finds are kept out of bulk sales'end
 return nil
end,{Bulk=true})
return P
