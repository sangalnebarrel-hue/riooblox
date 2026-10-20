-- DOGROTS translation QA helper. Install as a LocalScript in StarterPlayerScripts
-- ONLY while testing. It does not change the game and can be removed afterwards.
local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local seen = {}
local total = 0
local MAX_MESSAGES = 180
local SKIP = {DOGROTS=true, ROBLOX=true, ROBUX=true, XP=true, DNA=true}

local function looksEnglish(value)
    if type(value) ~= "string" then return false end
    if value:match("^%s*$") then return false end
    if SKIP[value:match("^%s*(.-)%s*$")] then return false end
    -- Detect untranslated English words; skip numbers and codes such as #001.
    return value:match("%a%a%a%a") ~= nil
end

local function checkOne(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    local value = obj:IsA("TextBox") and obj.PlaceholderText or obj.Text
    if not looksEnglish(value) or seen[value] or total >= MAX_MESSAGES then return end
    seen[value] = true
    total += 1
    print("[DOGROTS RU AUDIT] Possible English text:", string.sub(value, 1, 160), "PATH:", obj:GetFullName())
end

while true do
    task.wait(15) -- Open each game menu while the game is running.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        checkOne(obj)
        if total >= MAX_MESSAGES then break end
    end
    print("[DOGROTS RU AUDIT] Total different potential English strings:", total)
end
