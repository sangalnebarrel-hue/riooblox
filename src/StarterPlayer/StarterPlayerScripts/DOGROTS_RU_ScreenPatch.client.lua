-- DOGROTS: targeted Russian localization patch for 3 screens.
-- Install as a NEW LocalScript in StarterPlayer > StarterPlayerScripts.
-- Safe to run alongside one existing AutoTranslateUI. Does not modify gameplay/data.
-- Covers Genetical Lab, Excavation Layers, and offline Welcome Back rewards.
local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then return end
if _G.DOGROTS_RU_SCREEN_PATCH_ACTIVE then return end
_G.DOGROTS_RU_SCREEN_PATCH_ACTIVE = true

local playerGui = player:WaitForChild("PlayerGui")
local exact = {
    ["A discovery catalyst changes the odds."] = "Катализатор находок изменяет шансы.",
    ["ANCIENT RUINS"] = "ДРЕВНИЕ РУИНЫ",
    ["ANCIENT RUINS · 50–150m"] = "ДРЕВНИЕ РУИНЫ · 50–150 м",
    ["Ancient Ruins"] = "Древние руины",
    ["Assigned dogs earn"] = "Назначенные собаки зарабатывают",
    ["CAVERNS"] = "ПЕЩЕРЫ",
    ["CAVERNS · 10–50m"] = "ПЕЩЕРЫ · 10–50 м",
    ["CLAIM COINS"] = "ЗАБРАТЬ МОНЕТЫ",
    ["COINS WHILE AWAY"] = "МОНЕТ ЗА ВРЕМЯ ОТСУТСТВИЯ",
    ["CURSED DEPTHS"] = "ПРОКЛЯТЫЕ ГЛУБИНЫ",
    ["CURSED DEPTHS · 150–500m"] = "ПРОКЛЯТЫЕ ГЛУБИНЫ · 150–500 м",
    ["Caverns"] = "Пещеры",
    ["Claim whenever you are ready."] = "Забирай награду, когда захочешь.",
    ["Combine bloodlines or ascend with duplicates."] = "Объединяй родословные или повышай ранг с помощью копий.",
    ["Cursed Depths"] = "Проклятые глубины",
    ["DNA EXTRACTION"] = "ИЗВЛЕЧЕНИЕ ДНК",
    ["DNA EXTRACTION · LEVEL 8"] = "ИЗВЛЕЧЕНИЕ ДНК · УРОВЕНЬ 8",
    ["Discover classified genetic combinations."] = "Открывай секретные генетические комбинации.",
    ["EXPERIMENTAL CREATION"] = "ЭКСПЕРИМЕНТАЛЬНОЕ СОЗДАНИЕ",
    ["EXPERIMENTAL CREATION · LEVEL 18"] = "ЭКСПЕРИМЕНТАЛЬНОЕ СОЗДАНИЕ · УРОВЕНЬ 18",
    ["FUSION / ASCEND"] = "СЛИЯНИЕ / ВОЗВЫШЕНИЕ",
    ["FUSION / ASCEND · LEVEL 12"] = "СЛИЯНИЕ / ВОЗВЫШЕНИЕ · УРОВЕНЬ 12",
    ["GENE TARGETING"] = "ГЕНЕТИЧЕСКАЯ НАВОДКА",
    ["GENE TARGETING · LEVEL 5"] = "ГЕНЕТИЧЕСКАЯ НАВОДКА · УРОВЕНЬ 5",
    ["LAST TIME AWAY"] = "ВРЕМЯ ОТСУТСТВИЯ",
    ["Level 16 · 50,000 Cash"] = "Уровень 16 · 50 000 монет",
    ["Level 28 · 300,000 Cash"] = "Уровень 28 · 300 000 монет",
    ["Level 4 · 1,500 Cash"] = "Уровень 4 · 1 500 монет",
    ["Level 9 · 10,000 Cash"] = "Уровень 9 · 10 000 монет",
    ["MUTATION"] = "МУТАЦИЯ",
    ["MUTATION · LEVEL 1"] = "МУТАЦИЯ · УРОВЕНЬ 1",
    ["Permanently recycle one dog into DNA."] = "Безвозвратно переработай одну собаку в ДНК.",
    ["Reroll the variant. Your dog always survives."] = "Смени вариант мутации. Собака останется жива.",
    ["THE VOID"] = "ПУСТОТА",
    ["THE VOID · 500m+"] = "ПУСТОТА · от 500 м",
    ["The Void"] = "Пустота",
    ["Unlock Ancient Ruins first"] = "Сначала открой Древние руины",
    ["Unlock Caverns first"] = "Сначала открой Пещеры",
    ["Unlock Cursed Depths first"] = "Сначала открой Проклятые глубины",
    ["WELCOME BACK"] = "С ВОЗВРАЩЕНИЕМ",
    ["WORK TIME"] = "ВРЕМЯ РАБОТЫ",
    ["YOUR DOGS EARNED"] = "СОБАКИ ЗАРАБОТАЛИ",
    ["YOUR PACK KEPT BUSY!"] = "ТВОЯ СТАЯ НЕ СИДЕЛА БЕЗ ДЕЛА!",
    ["Your pack kept working"] = "Твоя стая продолжала работать",
}
local labNames = {
    ["MUTATION"] = "МУТАЦИЯ",
    ["МУТАЦИЯ"] = "МУТАЦИЯ",
    ["GENE TARGETING"] = "ГЕНЕТИЧЕСКАЯ НАВОДКА",
    ["ГЕНЕТИЧЕСКАЯ НАВОДКА"] = "ГЕНЕТИЧЕСКАЯ НАВОДКА",
    ["DNA EXTRACTION"] = "ИЗВЛЕЧЕНИЕ ДНК",
    ["ИЗВЛЕЧЕНИЕ ДНК"] = "ИЗВЛЕЧЕНИЕ ДНК",
    ["FUSION / ASCEND"] = "СЛИЯНИЕ / ВОЗВЫШЕНИЕ",
    ["СЛИЯНИЕ / ВОЗВЫШЕНИЕ"] = "СЛИЯНИЕ / ВОЗВЫШЕНИЕ",
    ["EXPERIMENTAL CREATION"] = "ЭКСПЕРИМЕНТАЛЬНОЕ СОЗДАНИЕ",
    ["ЭКСПЕРИМЕНТАЛЬНОЕ СОЗДАНИЕ"] = "ЭКСПЕРИМЕНТАЛЬНОЕ СОЗДАНИЕ",
}
local layers = {
    ["CAVERNS"] = "ПЕЩЕРЫ",
    ["ANCIENT RUINS"] = "ДРЕВНИЕ РУИНЫ",
    ["CURSED DEPTHS"] = "ПРОКЛЯТЫЕ ГЛУБИНЫ",
    ["THE VOID"] = "ПУСТОТА",
}
local depthNames = {
    ["Caverns"] = "Пещеры",
    ["Ancient Ruins"] = "Древние руины",
    ["Cursed Depths"] = "Проклятые глубины",
    ["The Void"] = "Пустоту",
}

local function isRussian()
    -- Player Emulator sets RobloxLocaleId, not always Player.LocaleId.
    local locale
    if RunService:IsStudio() then
        locale = LocalizationService.RobloxLocaleId
    else
        locale = player.LocaleId
    end
    return type(locale) == "string" and locale:lower():sub(1, 2) == "ru"
end

local function durationRu(value)
    return value:gsub("(%d+)%s*h", "%1 ч"):gsub("(%d+)%s*m", "%1 мин")
end

local function translate(source)
    if source == "" then return source end
    local direct = exact[source]
    if direct then return direct end

    -- Gene lab: procedure names are built as Name .. ' · LEVEL ' .. Level.
    local name, level = source:match("^(.-)%s*·%s*LEVEL%s+(%d+)$")
    if name and labNames[name] then
        return labNames[name] .. " · УРОВЕНЬ " .. level
    end

    -- Digging depth cards: ranges and costs come from current game data.
    local layer, depth = source:match("^(.-)%s*·%s*(.+)$")
    if layer and layers[layer] and depth:match("%d") then
        if depth == "500m+" then
            depth = "от 500 м"
        else
            depth = depth:gsub("(%d+)m", "%1 м")
        end
        return layers[layer] .. " · " .. depth
    end

    local neededLayer = source:match("^Unlock%s+(.+)%s+first$")
    if neededLayer and depthNames[neededLayer] then
        return "Сначала открой " .. depthNames[neededLayer]
    end

    local requiredLevel, cash = source:match("^Level%s+(%d+)%s*·%s*([%d,]+)%s+Cash$")
    if requiredLevel then
        return "Уровень " .. requiredLevel .. " · " .. cash .. " монет"
    end

    -- Offline reward popup/toast: preserve real amounts and duration values.
    local claim = source:match("^CLAIM%s+([%d,]+)%s+COINS$")
        or source:match("^CLAIM%s+([%d,]+)%s+МОНЕТ$")
    if claim then return "ЗАБРАТЬ " .. claim .. " МОНЕТ" end

    local toast = source:match("^YOUR DOGS EARNED%s*%+([%d,]+)%s+COINS%s+WHILE AWAY$")
        or source:match("^ТВОИ СОБАКИ ЗАРАБОТАЛИ%s*%+([%d,]+)%s+МОНЕТ.*$")
    if toast then
        return "СОБАКИ ЗАРАБОТАЛИ\n+" .. toast .. " МОНЕТ БЕЗ ТЕБЯ"
    end

    local onlyCoins = source:match("^%+([%d,]+)%s+COINS$")
    if onlyCoins then return "+" .. onlyCoins .. " МОНЕТ" end

    local work, absent = source:match("^WORK TIME:%s*(.-)%s*·%s*LAST TIME AWAY:%s*(.+)$")
    if not work then
        work, absent = source:match("^ВРЕМЯ РАБОТЫ:%s*(.-)%s*·%s*ПРОШЛЫЙ ВЫХОД:%s*(.+)$")
    end
    if work then
        return "ВРЕМЯ РАБОТЫ: " .. durationRu(work)
            .. " · ВНЕ ИГРЫ: " .. durationRu(absent)
    end

    local workSingle = source:match("^WORK TIME:%s*(.+)$")
    if workSingle then return "ВРЕМЯ РАБОТЫ: " .. durationRu(workSingle) end
    local awaySingle = source:match("^LAST TIME AWAY:%s*(.+)$")
    if awaySingle then return "ВНЕ ИГРЫ: " .. durationRu(awaySingle) end

    local percent, maximum = source:match(
        "^Assigned dogs earn%s+(%d+)%% of their base income for up to%s+(.-)%. Claim whenever you are ready%.$"
    )
    if percent then
        return "Назначенные собаки зарабатывают " .. percent
            .. "% базового дохода за время до " .. durationRu(maximum)
            .. ". Забирай награду, когда захочешь."
    end

    return source -- Never touch unrelated UI, names or numbers.
end

local watched = setmetatable({}, {__mode = "k"})
local function apply(obj)
    local state = watched[obj]
    if not state or state.busy or not obj.Parent then return end
    local current = obj[state.property]
    if current ~= state.applied then
        state.source = current -- Another game script generated a new English text.
    end
    local desired = isRussian() and translate(state.source) or state.source
    if desired ~= current then
        state.busy = true
        state.applied = desired
        obj[state.property] = desired
        state.busy = false
    else
        state.applied = current
    end
end

local function attach(obj)
    if watched[obj] then return end
    local property
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        property = "Text"
    elseif obj:IsA("TextBox") then
        property = "PlaceholderText" -- Do not change what the player types.
    else
        return
    end
    watched[obj] = {property = property, source = obj[property], applied = obj[property], busy = false}
    obj:GetPropertyChangedSignal(property):Connect(function() apply(obj) end)
    obj.Destroying:Connect(function() watched[obj] = nil end)
    apply(obj)
end

for _, obj in ipairs(playerGui:GetDescendants()) do
    attach(obj)
end
playerGui.DescendantAdded:Connect(function(obj)
    task.defer(attach, obj)
end)

local function refreshAll()
    for obj in pairs(watched) do
        if obj.Parent then apply(obj) end
    end
end
player:GetPropertyChangedSignal("LocaleId"):Connect(refreshAll)
LocalizationService:GetPropertyChangedSignal("RobloxLocaleId"):Connect(refreshAll)

print("[DOGROTS RU] Lab / Depth / Offline patch ready; Russian:", isRussian())
