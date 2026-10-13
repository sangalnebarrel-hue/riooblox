-- Keeps every NavigationAnchors mirror (Persistent: clients always have it, even when the building
-- itself is not streamed in) on its Target part: once at start, whenever a target moves, and a slow
-- sweep for anchors or targets that appear later. MapRouting reads these anchors.
local nav=workspace:WaitForChild('DOGROTS_District'):WaitForChild('NavigationAnchors')
local watched={}
local function sync(mirror)
 local ref=mirror:FindFirstChild('Target')
 local target=ref and ref:IsA('ObjectValue') and ref.Value
 if not(mirror:IsA('BasePart')and target and target:IsA('BasePart'))then return end
 if mirror.CFrame~=target.CFrame then mirror.CFrame=target.CFrame end
 if not watched[target] then
  watched[target]=target:GetPropertyChangedSignal('CFrame'):Connect(function()if mirror.Parent then mirror.CFrame=target.CFrame end end)
  target.Destroying:Connect(function()local c=watched[target];watched[target]=nil;if c then c:Disconnect()end end)
 end
end
while true do
 for _,mirror in ipairs(nav:GetChildren())do sync(mirror)end
 task.wait(10)
end
