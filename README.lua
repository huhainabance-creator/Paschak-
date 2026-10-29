-- UA Killer Hub | YBA — Версія з виправленим ItemFarm та MonHub GUI
print("[UA Killer Hub | Init] Початок запуску скрипта...")

if not game:IsLoaded() then
    print("[UA Killer Hub | Init] Очікування повного завантаження гри...")
    game.Loaded:Wait()
end
print("[UA Killer Hub | Init] Гра завантажена.")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
while not player do
    task.wait(0.1)
    player = Players.LocalPlayer
end
print("[UA Killer Hub | Init] Гравець ідентифікований: " .. player.Name)

local autoLoadFile = "UAKillerHub/YBA_AutoLoad.txt"
local configFile   = "UAKillerHub/YBA_Config.json"
local shouldAutoLoad = false

-- =======================================================
-- БЕЗПЕЧНА АКТИВАЦІЯ ITEM MAGNITUDE BYPASS
-- =======================================================
pcall(function()
    if hookmetamethod and newcclosure and checkcaller and getcallingscript then
        local char = player.Character or player.CharacterAdded:Wait()
        local primary = char:WaitForChild("HumanoidRootPart", 3) or char.PrimaryPart
        if primary then
            local OldIndexItem
            OldIndexItem = hookmetamethod(primary.Position, "__index", newcclosure(function(self, Key)
                if not checkcaller() and Key:lower() == "magnitude" and getcallingscript().Name == "ItemSpawn" then
                    return 0
                end
                return OldIndexItem(self, Key)
            end))
            print("[UA Killer Hub | Init] Item Magnitude Bypass активовано.")
        end
    end
end)

-- ====================================================
-- БЕЗПЕЧНИЙ CRASH & WALKSPEED BYPASS
-- ====================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
pcall(function()
    local FunctionLibrary = require(
        ReplicatedStorage:WaitForChild("Modules", 2):WaitForChild("FunctionLibrary", 2)
    )
    local OldPcall = FunctionLibrary.pcall
    FunctionLibrary.pcall = function(...)
        local args = { ... }
        if type(args[1]) == "function" and #getupvalues(args[1]) == 11 then
            return
        end
        return OldPcall(...)
    end
    print("[UA Killer Hub | Init] WalkSpeed/Crash Bypass активовано.")
end)

-- Ініціалізація папки та флагу авто-завантаження
pcall(function()
    if makefolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
    if isfile and isfile(autoLoadFile) then
        shouldAutoLoad = (readfile(autoLoadFile) == "true")
    elseif writefile then
        writefile(autoLoadFile, "false")
    end
end)

-- ====================
-- ГЛОБАЛЬНІ НАЛАШТУВАННЯ
-- ====================
_G.AutoSell        = false
_G.AutoEventCandy  = false
_G.AutoBuy         = false
_G.ItemFarm        = false
_G.ItemESP         = false
_G.FlySpeed        = 150
_G.PickupDistance  = 3.5
_G.AntiAFK         = false
_G.StandaloneNoClip= false
_G.AutoRespawn     = true

_G.SelectedItems = {
    ["Ancient Scroll"] = false,
    ["Blue Candy"] = false,
    ["Caesar's Headband"] = false,
    ["Christmas Present"] = false,
    ["Clackers"] = false,
    ["Diamond"] = false,
    ["Dio's Diary"] = false,
    ["Frog"] = false,
    ["Gloves"] = false,
    ["Green Candy"] = false,
    ["Gold Coin"] = false,
    ["Lucky Arrow"] = false,
    ["Lucky Stone Mask"] = false,
    ["Mysterious Bow"] = false,
    ["Mysterious Arrow"] = false,
    ["Pure Rokakaka"] = false,
    ["Quinton's Glove"] = false,
    ["Red Candy"] = false,
    ["Rib Cage of The Saint's Corpse"] = false,
    ["Rokakaka"] = false,
    ["Steel Ball"] = false,
    ["Stone Mask"] = false,
    ["Yellow Candy"] = false,
    ["Zepellin's Headband"] = false,
    ["Zeppeli's Hat"] = false,
}

local bannedCoordinates = {}
local failedItemAttempts= {}
local espObjects        = {}
local itemCache         = {}
local lastCacheRefresh  = 0
local CACHE_REFRESH_INTERVAL = 1.25
local BAN_TTL           = 30

local farmThreadActive  = false
local farmSessionId     = 0
local farmStatusText    = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection
local JP_Value = 50

local uiElementsRegistry = {}

local manuallyChanged = {
    ItemFarm        = false,
    AutoSell        = false,
    AutoEventCandy  = false,
    AutoBuy         = false,
    ItemESP         = false,
    AntiAFK         = false,
    StandaloneNoClip= false,
    AutoRespawn     = false,
}

-- ====================
-- ДОПОМІЖНІ ФУНКЦІЇ
-- ====================
local function setFarmStatus(text)
    farmStatusText = text
end

local function isInvalidItemPart(obj)
    if not obj then return true end
    local current = obj
    while current and current ~= workspace do
        if current:IsA("Backpack") then return true end
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then return true end
        current = current.Parent
    end
    return false
end

local function cleanupBannedCoordinates()
    local now = tick()
    for i = #bannedCoordinates, 1, -1 do
        if now - bannedCoordinates[i].time > BAN_TTL then
            table.remove(bannedCoordinates, i)
        end
    end
end

local function isCoordinateBanned(pos, itemPart)
    cleanupBannedCoordinates()
    for _, entry in ipairs(bannedCoordinates) do
        if (pos - entry.pos).Magnitude < 3 then
            if entry.instance and itemPart and entry.instance == itemPart then
                return true
            elseif not entry.instance then
                return true
            end
        end
    end
    return false
end

local function banFailedItem(item, reason)
    if not item or not item.part then return end
    local pos = item.position or item.part.Position
    local partInstance = item.part
    local itemName = item.name or "Unknown"

    table.insert(bannedCoordinates, {
        pos = pos,
        time = tick(),
        instance = partInstance,
        reason = reason or "failed_pickup",
        name = itemName,
    })

    warn(string.format("[UA Killer Hub | Blacklist] Об'єкт тимчасово заблоковано на %ds: [%s | Instance: %s] на позиції (%.1f, %.1f, %.1f) | Причина: %s",
        BAN_TTL, itemName, tostring(partInstance), pos.X, pos.Y, pos.Z, tostring(reason)))
end

local function resolveItemFromPrompt(desc)
    if not desc or not desc:IsA("ProximityPrompt") or not desc.Parent then return nil end

    local parent    = desc.Parent
    local model     = parent:IsA("Model") and parent or parent.Parent
    local itemName  = ""

    if _G.SelectedItems[parent.Name] ~= nil then
        itemName = parent.Name
    elseif model and _G.SelectedItems[model.Name] ~= nil then
        itemName = model.Name
    elseif desc.ObjectText and _G.SelectedItems[desc.ObjectText] ~= nil then
        itemName = desc.ObjectText
    end

    if itemName == "" then return nil end

    local targetPart = parent:IsA("BasePart") and parent
        or parent:FindFirstChildWhichIsA("BasePart")
        or (model and model:FindFirstChildWhichIsA("BasePart"))

    if not targetPart or targetPart.Transparency >= 1 then return nil end
    if isCoordinateBanned(targetPart.Position, targetPart) or isInvalidItemPart(targetPart) then return nil end
    if not desc.Enabled then return nil end

    return {
        prompt   = desc,
        part     = targetPart,
        parent   = parent,
        name     = itemName,
        position = targetPart.Position,
    }
end

local function anyItemSelected()
    for _, v in pairs(_G.SelectedItems) do
        if v then return true end
    end
    return false
end

local function shouldFarmItem(itemName)
    if not anyItemSelected() then return true end
    return _G.SelectedItems[itemName] == true
end

local function pruneItemCache()
    for i = #itemCache, 1, -1 do
        local it = itemCache[i]
        if not it or not it.part or not it.part:IsDescendantOf(workspace)
           or not it.prompt or not it.prompt:IsDescendantOf(workspace)
           or isInvalidItemPart(it.parent)
           or isCoordinateBanned(it.position, it.part) then
            table.remove(itemCache, i)
        end
    end
end

local function refreshItemCache(force)
    local now = tick()
    if not force and (now - lastCacheRefresh < CACHE_REFRESH_INTERVAL) then
        pruneItemCache()
        return itemCache
    end

    lastCacheRefresh = now
    table.clear(itemCache)

    local t0 = os.clock()
    local promptCount = 0
    local validCount = 0

    local descendants = workspace:GetDescendants()
    for _, desc in ipairs(descendants) do
        if desc:IsA("ProximityPrompt") then
            promptCount = promptCount + 1
            local item = resolveItemFromPrompt(desc)
            if item and shouldFarmItem(item.name) then
                table.insert(itemCache, item)
                validCount = validCount + 1
            end
        end
    end

    local elapsed = os.clock() - t0
    if elapsed > 0.03 or validCount > 0 then
        print(string.format("[UA Killer Hub | Cache] Оновлення: знайдено %d валідних предметів (перевірено %d prompt) за %.4f с",
            validCount, promptCount, elapsed))
    end

    return itemCache
end

local function getNearestItem(hrp)
    local nearest, shortest = nil, math.huge
    for _, item in ipairs(refreshItemCache()) do
        if item.prompt:IsDescendantOf(workspace) and item.part:IsDescendantOf(workspace) and not isInvalidItemPart(item.parent) then
            local dist = (hrp.Position - item.position).Magnitude
            if dist < shortest then
                shortest = dist
                nearest  = item
            end
        end
    end
    return nearest, shortest
end

local function applyESP(part, name)
    if espObjects[part] then return end
    if not part or part.Transparency == 1 or isCoordinateBanned(part.Position) or isInvalidItemPart(part) then return end

    local bgui = Instance.new("BillboardGui")
    bgui.Name        = "YBA_Item_ESP"
    bgui.AlwaysOnTop = true
    bgui.Size        = UDim2.new(0, 140, 0, 32)
    bgui.Adornee     = part

    local text = Instance.new("TextLabel")
    text.Parent              = bgui
    text.BackgroundTransparency = 1
    text.Size                = UDim2.new(1, 0, 1, 0)
    text.Text                = name
    text.TextColor3          = Color3.fromRGB(139, 124, 246)
    text.TextSize            = 13
    text.Font                = Enum.Font.GothamBold
    text.TextStrokeTransparency = 0

    bgui.Parent       = part
    espObjects[part]  = bgui
end

local function clearESP()
    for part, gui in pairs(espObjects) do
        if gui then gui:Destroy() end
        espObjects[part] = nil
    end
    table.clear(espObjects)
end

local function getCharacter()
    local char = player.Character
    if not char or not char:IsDescendantOf(workspace) then
        return nil, nil, nil
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

-- Відстеження респавну та життєвого циклу персонажа
player.CharacterAdded:Connect(function(newChar)
    print("[UA Killer Hub | Character] Завантажено нового персонажа: " .. tostring(newChar.Name))
    cleanupFlight()
    pcall(function()
        for _, obj in ipairs(player:GetChildren()) do
            if obj.Name == "YBA_VirtualCFrame" then obj:Destroy() end
        end
    end)
    task.spawn(function()
        local hrp = newChar:WaitForChild("HumanoidRootPart", 5)
        if not hrp then
            warn("[UA Killer Hub | Character] HumanoidRootPart не знайдено протягом 5 секунд після появи моделі.")
        end
    end)
end)

local function zeroHrpVelocity(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function cleanupFlight()
    if not flightState then return end
    if flightState.tween then pcall(function() flightState.tween:Cancel() end) end
    if flightState.heartbeatConn then pcall(function() flightState.heartbeatConn:Disconnect() end) end
    if flightState.cframeValue then pcall(function() flightState.cframeValue:Destroy() end) end
    flightState = nil

    local char, hrp = getCharacter()
    if hrp then zeroHrpVelocity(hrp) end
    if char and not _G.StandaloneNoClip and not _G.ItemFarm then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

local function stopFlight()
    cleanupFlight()
    if noclipConnection and not _G.StandaloneNoClip and not _G.ItemFarm then
        pcall(function() noclipConnection:Disconnect() end)
        noclipConnection = nil
    end
    pcall(function()
        for _, obj in ipairs(player:GetChildren()) do
            if obj.Name == "YBA_VirtualCFrame" then obj:Destroy() end
        end
    end)
end

local function ensureNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if not _G.ItemFarm and not _G.StandaloneNoClip then return end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= hrp then
                part.CanCollide = false
            end
        end
    end)
end

local function moveToItemAndPickup(item)
    if not item or not item.part or not item.part:IsDescendantOf(workspace) then return false end
    if not item.prompt or not item.prompt:IsDescendantOf(workspace) then return false end
    if isInvalidItemPart(item.parent) then return false end

    local char, hrp = getCharacter()
    if not hrp then
        warn("[UA Killer Hub | ItemFarm] Рух скасовано: персонаж або HumanoidRootPart відсутній на старті")
        return false
    end

    cleanupFlight()

    local cframeValue = Instance.new("CFrameValue")
    cframeValue.Name   = "YBA_VirtualCFrame"
    cframeValue.Value  = hrp.CFrame
    cframeValue.Parent = player

    local targetCFrame = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    local distance     = (targetCFrame.Position - hrp.Position).Magnitude
    local speed        = math.max(_G.FlySpeed or 150, 20)
    local tweenTime    = math.max(distance / speed, 0.05)

    local tween = TweenService:Create(cframeValue, TweenInfo.new(tweenTime, Enum.EasingStyle.Linear), { Value = targetCFrame })

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent then return end
        local currentHrp = char:FindFirstChild("HumanoidRootPart")
        if not currentHrp or not cframeValue.Parent then return end
        currentHrp.CFrame = cframeValue.Value
        zeroHrpVelocity(currentHrp)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= currentHrp then
                part.CanCollide = false
            end
        end
    end)

    flightState = { cframeValue = cframeValue, tween = tween, heartbeatConn = heartbeatConn }

    local function shouldContinue()
        return _G.ItemFarm
            and item.part:IsDescendantOf(workspace)
            and not isInvalidItemPart(item.part)
            and item.prompt:IsDescendantOf(workspace)
    end

    tween:Play()
    local finished = false
    local tweenCompletedConn
    tweenCompletedConn = tween.Completed:Once(function() finished = true end)

    local flightTimeout = tick() + tweenTime + 2.0
    while not finished do
        if not shouldContinue() or not hrp or not hrp.Parent or tick() > flightTimeout then
            if tweenCompletedConn then tweenCompletedConn:Disconnect() end
            cleanupFlight()
            return false
        end
        RunService.Heartbeat:Wait()
    end

    if not shouldContinue() then cleanupFlight() return false end

    targetCFrame      = CFrame.new(item.part.Position + Vector3.new(0, 1.2, 0))
    cframeValue.Value = targetCFrame
    local currentHrp  = char:FindFirstChild("HumanoidRootPart")
    if currentHrp then
        currentHrp.CFrame = targetCFrame
        zeroHrpVelocity(currentHrp)
    end

    task.wait(0.04)

    if not shouldContinue() then cleanupFlight() return false end

    -- Фіксуємо стан інвентарю перед взаємодією для точного підтвердження
    local backpack = player:FindFirstChild("Backpack")
    local initialBackpackCount = backpack and #backpack:GetChildren() or 0
    local initialCharTools = 0
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Tool") then initialCharTools = initialCharTools + 1 end
        end
    end
    local initialTotalTools = initialBackpackCount + initialCharTools

    item.prompt.RequiresLineOfSight = false
    item.prompt.HoldDuration        = 0

    local requestTime = os.clock()
    if fireproximityprompt then
        fireproximityprompt(item.prompt, 0)
    end

    -- Достовірна перевірка результату підбору з вимірюванням затримки
    local confirmed = false
    local maxWait = 0.75
    local checkStart = os.clock()

    while (os.clock() - checkStart) < maxWait do
        if not item.prompt:IsDescendantOf(workspace) or not item.part:IsDescendantOf(workspace) or isInvalidItemPart(item.parent) then
            confirmed = true
            break
        end
        if not item.prompt.Enabled then
            confirmed = true
            break
        end
        local curBackpack = backpack and #backpack:GetChildren() or 0
        local curCharTools = 0
        if char then
            for _, obj in ipairs(char:GetChildren()) do
                if obj:IsA("Tool") then curCharTools = curCharTools + 1 end
            end
        end
        if (curBackpack + curCharTools) > initialTotalTools then
            confirmed = true
            break
        end
        task.wait(0.04)
    end

    local latency = os.clock() - requestTime
    cleanupFlight()

    if confirmed then
        print(string.format("[UA Killer Hub | ItemFarm] Підтверджено підбір [%s] за %.3f с (Instance: %s)",
            item.name, latency, tostring(item.part)))
        return true
    else
        warn(string.format("[UA Killer Hub | ItemFarm] Підбір [%s] не підтверджено сервером за %.3f с (Instance: %s)",
            item.name, latency, tostring(item.part)))
        return false
    end
end

local function tryRespawn()
    if not _G.AutoRespawn then return end
    local char, _, hum = getCharacter()
    if hum and hum.Health <= 0 then
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        local remote = remotesFolder and remotesFolder:FindFirstChild("LoadCharacter")
        if remote then
            local ok, err = pcall(function() remote:FireServer() end)
            if ok then
                print("[UA Killer Hub | Respawn] Відправлено запит LoadCharacter для респавну.")
            else
                warn("[UA Killer Hub | Respawn] Помилка виклику LoadCharacter: " .. tostring(err))
            end
        else
            warn("[UA Killer Hub | Respawn] Remote LoadCharacter не знайдено в ReplicatedStorage.Remotes.")
        end
    end
end

-- =======================================================
-- ЄДИНИЙ КОНТРОЛЕР СТАНУ ITEMFARM
-- =======================================================
local itemFarmToggle

local function startFarmThread()
    if farmThreadActive then return end
    farmThreadActive = true
    farmSessionId    = farmSessionId + 1
    local currentSession = farmSessionId

    task.spawn(function()
        setFarmStatus("Пошук предметів...")
        while _G.ItemFarm and farmThreadActive and (farmSessionId == currentSession) do
            tryRespawn()
            local _, hrp = getCharacter()
            if not hrp then
                setFarmStatus("Очікування персонажа...")
                task.wait(0.5)
                continue
            end
            local targetItem = getNearestItem(hrp)
            if not targetItem then
                setFarmStatus("Предметів не знайдено")
                task.wait(0.35)
                continue
            end

            setFarmStatus("Лечу до: " .. targetItem.name)
            local itemPart = targetItem.part
            local success = moveToItemAndPickup(targetItem)

            if success then
                failedItemAttempts[itemPart] = nil
                if espObjects[itemPart] then
                    pcall(function() espObjects[itemPart]:Destroy() end)
                    espObjects[itemPart] = nil
                end
                lastCacheRefresh = 0
            else
                local attempts = (failedItemAttempts[itemPart] or 0) + 1
                failedItemAttempts[itemPart] = attempts
                if attempts >= 2 then
                    banFailedItem(targetItem, "2_failed_attempts")
                    failedItemAttempts[itemPart] = nil
                    lastCacheRefresh = 0
                else
                    warn(string.format("[UA Killer Hub | ItemFarm] Спроба %d/2 для [%s] неуспішна, наступна спроба пізніше",
                        attempts, targetItem.name))
                    task.wait(0.15)
                end
            end
            task.wait(0.08)
        end

        if farmSessionId == currentSession then
            farmThreadActive = false
            setFarmStatus("Зупинено")
            stopFlight()
        end
    end)
end

local function setItemFarmState(enabled)
    _G.ItemFarm = (enabled == true)

    if itemFarmToggle and itemFarmToggle:Get() ~= _G.ItemFarm then
        itemFarmToggle:Set(_G.ItemFarm, false)
    end

    if _G.ItemFarm then
        startFarmThread()
    else
        farmSessionId    = farmSessionId + 1
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    end

    print(string.format("[UA Killer Hub | Farm] Стан синхронізовано: _G.ItemFarm=%s, farmThreadActive=%s, GUI=%s",
        tostring(_G.ItemFarm),
        tostring(farmThreadActive),
        tostring(itemFarmToggle and itemFarmToggle:Get())))
end

-- =======================================================
-- МАГАЗИН ТА ІВЕНТ (ВЗАЄМОДІЯ З ДІАЛОГАМИ)
-- =======================================================
local DontSell = {
    ["Lucky Arrow"] = true, ["Christmas Present"] = true,
    ["Green Candy"] = true, ["Yellow Candy"] = true,
    ["Blue Candy"]  = true, ["Red Candy"]    = true,
    ["Lucky Stone Mask"] = true,
}

local EventCandies = {
    ["Green Candy"] = true, ["Yellow Candy"] = true,
    ["Blue Candy"]  = true, ["Red Candy"]    = true,
}

local sellQueue = {}
local isBusy    = false

local function getMerchant()
    local d = ReplicatedStorage:FindFirstChild("Dialogue")
    return d and d:FindFirstChild("Merchant")
end

local function getEventNPC()
    local d = ReplicatedStorage:FindFirstChild("Dialogue")
    return d and d:FindFirstChild("Halloween Event")
end

local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("DialogueGui") or pg:FindFirstChild("Dialogue") or pg:FindFirstChild("DialogueBox")
end

-- Перевірка фактичної видимості GUI-елемента на екрані
local function isGuiElementVisible(elem)
    if not elem or not elem:IsA("GuiObject") then return false end
    if not elem.Visible then return false end
    if elem.AbsoluteSize.X <= 0 or elem.AbsoluteSize.Y <= 0 then return false end

    local current = elem.Parent
    while current and current:IsA("GuiObject") do
        if not current.Visible then return false end
        current = current.Parent
    end

    local screenGui = elem:FindFirstAncestorWhichIsA("ScreenGui")
    if screenGui and not screenGui.Enabled then return false end

    return true
end

local function isItemSold(item)
    if not item or not item.Parent or not item:IsDescendantOf(game) then return true end
    local char    = player.Character
    local backpack = player:FindFirstChild("Backpack")
    if (backpack and item:IsDescendantOf(backpack)) or (char and item:IsDescendantOf(char)) then
        return false
    end
    return true
end

local function autoClickDialogueButtons()
    local gui = getDialogueGui()
    if not gui then return end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lower = txt:lower()
            if lower:find("sell this") or lower:find("i'd like to sell") or lower:find("deal") or lower:find("all") then
                pcall(function()
                    if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                    else btn.Activated:Fire() end
                end)
            end
        end
    end
end

local function closeMerchantDialogue()
    local char   = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("DialogueEnd", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
        end
    end)
    local gui = getDialogueGui()
    if gui then
        pcall(function()
            for _, btn in ipairs(gui:GetDescendants()) do
                if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
                    local txt = btn.Text or ""
                    local childText = btn:FindFirstChildOfClass("TextLabel")
                    if childText and childText.Text ~= "" then txt = childText.Text end
                    local lower = txt:lower()
                    if lower:find("nevermind") or lower:find("nothing") or lower:find("bye") or lower:find("leave") or lower:find("no") or lower:find("exit") or lower:find("close") or lower:find("goodbye") then
                        if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                        else btn.Activated:Fire() end
                    end
                end
            end
        end)
        task.wait(0.12)
        if gui:IsA("ScreenGui") and gui.Enabled then pcall(function() gui.Enabled = false end) end
    end
end

local function sellSingleItem(item)
    if not item or isItemSold(item) or DontSell[item.Name] then return true, "AlreadySold" end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not hum or not remote or not merchant then return false, "MissingCharacterOrNPC" end

    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char do task.wait(0.04) end
    if item.Parent ~= char then return false, "EquipTimeout" end

    task.wait(0.12)
    remote:FireServer("PromptTriggered", merchant)
    task.wait(0.12)
    autoClickDialogueButtons()

    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
    task.wait(0.12)
    autoClickDialogueButtons()

    local sellTimeout = tick() + 1.2
    while tick() < sellTimeout do
        if isItemSold(item) then break end
        autoClickDialogueButtons()
        task.wait(0.08)
    end

    pcall(function()
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue5", NPC = "Merchant" })
        remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
        remote:FireServer("DialogueEnd",  { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
    end)

    local finalCheckTimeout = tick() + 0.6
    while tick() < finalCheckTimeout do
        if isItemSold(item) then break end
        task.wait(0.05)
    end

    local sold = isItemSold(item)
    if not sold and item.Parent == char then
        pcall(function() hum:UnequipTools() end)
    end
    return sold, sold and "Success" or "ItemNotRemoved"
end

local function findSellableItem()
    local backpack = player:FindFirstChild("Backpack")
    local char     = player.Character
    if backpack then
        for _, it in ipairs(backpack:GetChildren()) do
            if it:IsA("Tool") and not DontSell[it.Name] and not isItemSold(it) then return it end
        end
    end
    if char then
        for _, it in ipairs(char:GetChildren()) do
            if it:IsA("Tool") and not DontSell[it.Name] and not isItemSold(it) then return it end
        end
    end
    return nil
end

local function processSellQueue()
    if isBusy or not _G.AutoSell then return end
    isBusy = true
    task.spawn(function()
        while _G.AutoSell do
            local nextItem = findSellableItem()
            if not nextItem then break end
            local sold, reason = sellSingleItem(nextItem)
            task.wait(0.1)
            local remaining = findSellableItem()
            if not remaining then
                closeMerchantDialogue()
                break
            end
        end
        closeMerchantDialogue()
        isBusy = false
    end)
end

local function queueItemForSale(item)
    if not _G.AutoSell or not item or DontSell[item.Name] then return end
    if not isBusy then processSellQueue() end
end

-- =======================================================
-- ХЕЛОВІН ІВЕНТ (АВТОЗДАЧА ЦУКЕРОК ТА ЗАКРИТТЯ ДІАЛОГУ)
-- =======================================================
local function hasCandies()
    local backpack = player:FindFirstChild("Backpack")
    local char     = player.Character
    if backpack then
        for _, it in ipairs(backpack:GetChildren()) do
            if it:IsA("Tool") and EventCandies[it.Name] then return true end
        end
    end
    if char then
        for _, it in ipairs(char:GetChildren()) do
            if it:IsA("Tool") and EventCandies[it.Name] then return true end
        end
    end
    return false
end

local function findJackDialogue()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local candidates = {
        pg:FindFirstChild("DialogueGui"),
        pg:FindFirstChild("Dialogue"),
        pg:FindFirstChild("DialogueBox"),
        pg:FindFirstChild("HUD"),
    }
    for _, root in ipairs(candidates) do
        if root then
            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                    local t = (descendant.Text or ""):lower()
                    if t:find("cauldron specter") or t:find("jack") or t:find("candy") or t:find("candies") or t:find("points") or t:find("halloween") then
                        return root
                    end
                end
            end
        end
    end
    return getDialogueGui()
end

local function clickJackDialogueButton(btn)
    if not btn or not isGuiElementVisible(btn) then return false end
    local clicked = false
    pcall(function()
        if firesignal then
            firesignal(btn.MouseButton1Click)
            firesignal(btn.MouseButton1Down)
            firesignal(btn.MouseButton1Up)
            firesignal(btn.Activated)
            clicked = true
        end
    end)
    pcall(function()
        local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
        clicked = true
    end)
    return clicked
end

local function clickContinueButton()
    local dialogueGui = findJackDialogue()
    if not dialogueGui then return false end
    local clickedAny = false
    for _, elem in ipairs(dialogueGui:GetDescendants()) do
        if isGuiElementVisible(elem) then
            local txt = ""
            if elem:IsA("TextButton") or elem:IsA("TextLabel") then
                txt = (elem.Text or ""):lower()
            end
            if txt:find("click to continue") or txt:find("continue") or txt:find("next") or txt:find("close") or txt:find("done") then
                local targetBtn = elem:IsA("TextButton") and elem or elem:FindFirstAncestorWhichIsA("TextButton")
                if targetBtn and isGuiElementVisible(targetBtn) then
                    clickJackDialogueButton(targetBtn)
                    clickedAny = true
                else
                    pcall(function()
                        local pos = elem.AbsolutePosition + (elem.AbsoluteSize / 2)
                        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                        task.wait(0.03)
                        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
                        clickedAny = true
                    end)
                end
            end
        end
    end

    if not clickedAny then
        for _, boxName in ipairs({"DialogueBox", "Frame", "Container", "Background"}) do
            local box = dialogueGui:FindFirstChild(boxName, true)
            if box and box:IsA("GuiObject") and isGuiElementVisible(box) then
                pcall(function()
                    local pos = box.AbsolutePosition + (box.AbsoluteSize / 2)
                    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                    task.wait(0.03)
                    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
                    clickedAny = true
                end)
                if clickedAny then break end
            end
        end
    end
    return clickedAny
end

local function closeEventDialogue()
    local char   = player.Character
    local remote = char and char:FindFirstChild("RemoteEvent")
    pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Halloween Event" })
            remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Halloween Event" })
            remote:FireServer("DialogueEnd",  { Option = "Option1", Dialogue = "Dialogue1", NPC = "Halloween Event" })
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue2", NPC = "Halloween Event" })
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Halloween Event" })
        end
    end)

    local closeTimeout = tick() + 2.0
    while tick() < closeTimeout do
        local dGui = findJackDialogue()
        if not dGui then break end
        local foundVisible = false
        for _, el in ipairs(dGui:GetDescendants()) do
            if el:IsA("GuiObject") and isGuiElementVisible(el) then
                foundVisible = true
                break
            end
        end
        if not foundVisible then break end

        clickContinueButton()
        task.wait(0.15)
    end

    local finalGui = findJackDialogue()
    if finalGui and finalGui:IsA("ScreenGui") and finalGui.Enabled then
        pcall(function() finalGui.Enabled = false end)
    end
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not hum or not remote or not eventNPC then return false end

    remote:FireServer("PromptTriggered", eventNPC)
    task.wait(0.2)
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue1", NPC = "Halloween Event" })
    task.wait(0.2)
    remote:FireServer("DialogueType", { Option = "Option1", Dialogue = "Dialogue2", NPC = "Halloween Event" })
    task.wait(0.2)

    local waitTimeout = tick() + 2.0
    while tick() < waitTimeout do
        clickContinueButton()
        task.wait(0.12)
        local dGui = findJackDialogue()
        if not dGui then break end
    end

    closeEventDialogue()
    return true
end

local function checkAndSubmitEventCandies()
    if not _G.AutoEventCandy or isBusy then return end
    if not hasCandies() then return end
    isBusy = true
    task.spawn(function()
        submitAllCandies()
        task.wait(0.2)
        closeEventDialogue()
        isBusy = false
    end)
end

-- =======================================================
-- ІНВЕНТАР ТА ФОНОВІ ПОТОКИ
-- =======================================================
local function setupInventoryListeners()
    local backpack = player:WaitForChild("Backpack", 5)
    if backpack then
        backpack.ChildAdded:Connect(function(item)
            if item:IsA("Tool") then
                task.wait(0.08)
                if _G.AutoEventCandy and EventCandies[item.Name] then
                    checkAndSubmitEventCandies()
                elseif _G.AutoSell and not DontSell[item.Name] then
                    queueItemForSale(item)
                end
            end
        end)
    end

    player.CharacterAdded:Connect(function(newChar)
        newChar.ChildAdded:Connect(function(item)
            if item:IsA("Tool") then
                task.wait(0.08)
                if _G.AutoEventCandy and EventCandies[item.Name] then
                    checkAndSubmitEventCandies()
                elseif _G.AutoSell and not DontSell[item.Name] then
                    queueItemForSale(item)
                end
            end
        end)
    end)

    if player.Character then
        player.Character.ChildAdded:Connect(function(item)
            if item:IsA("Tool") then
                task.wait(0.08)
                if _G.AutoEventCandy and EventCandies[item.Name] then
                    checkAndSubmitEventCandies()
                elseif _G.AutoSell and not DontSell[item.Name] then
                    queueItemForSale(item)
                end
            end
        end)
    end
end
setupInventoryListeners()

-- Anti-AFK
task.spawn(function()
    while true do
        task.wait(180)
        if _G.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end
    end
end)

local function applyJumpPower()
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

local function checkExistingInventoryOnStart()
    task.spawn(function()
        task.wait(1.5)
        if _G.AutoEventCandy and hasCandies() then
            checkAndSubmitEventCandies()
        end
        local sellItem = findSellableItem()
        if _G.AutoSell and sellItem then
            queueItemForSale(sellItem)
        end
    end)
end

task.spawn(function()
    while task.wait(0.2) do applyJumpPower() end
end)

-- Фоновий цикл оновлення ESP з очищенням пам'яті
task.spawn(function()
    while true do
        task.wait(0.8)
        if _G.ItemESP then
            for part, gui in pairs(espObjects) do
                if not part or not part.Parent or not part:IsDescendantOf(workspace) then
                    if gui then pcall(function() gui:Destroy() end) end
                    espObjects[part] = nil
                end
            end
            for _, item in ipairs(refreshItemCache()) do applyESP(item.part, item.name) end
        else
            clearESP()
        end
    end
end)

-- =======================================================
-- БЕЗПЕЧНЕ СТВОРЕННЯ MONHUB GUI
-- =======================================================
print("[UA Killer Hub | GUI] Початок створення графічного інтерфейсу...")

local function getSafeGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then
        local testOk = pcall(function()
            local f = Instance.new("Folder", core)
            f:Destroy()
        end)
        if testOk then return core end
    end
    local pgui = player:WaitForChild("PlayerGui", 5)
    return pgui or player:FindFirstChildOfClass("PlayerGui")
end

local targetGuiParent = getSafeGuiParent()
print("[UA Killer Hub | GUI] Батьківський контейнер GUI: " .. tostring(targetGuiParent and targetGuiParent.Name))

pcall(function()
    local old = targetGuiParent:FindFirstChild("UAKillerHub_GUI")
    if old then old:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "UAKillerHub_GUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = targetGuiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 520, 0, 255)
MainFrame.Position         = UDim2.new(0.5, -260, 0.5, -128)
MainFrame.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
MainFrame.BorderSizePixel  = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent           = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent       = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color     = Color3.fromRGB(38, 42, 53)
MainStroke.Thickness = 1
MainStroke.Parent    = MainFrame

-- Контейнер сповіщень
local ToastContainer = Instance.new("Frame")
ToastContainer.Name                  = "ToastContainer"
ToastContainer.Size                  = UDim2.new(0, 240, 1, -20)
ToastContainer.Position              = UDim2.new(1, -250, 0, 10)
ToastContainer.BackgroundTransparency = 1
ToastContainer.Parent                = ScreenGui

local ToastList = Instance.new("UIListLayout")
ToastList.Padding             = UDim.new(0, 6)
ToastList.SortOrder           = Enum.SortOrder.LayoutOrder
ToastList.VerticalAlignment   = Enum.VerticalAlignment.Bottom
ToastList.HorizontalAlignment = Enum.HorizontalAlignment.Center
ToastList.Parent              = ToastContainer

local function showNotification(title, message, duration)
    duration = duration or 3
    local toast = Instance.new("Frame")
    toast.Size             = UDim2.new(1, 0, 0, 0)
    toast.BackgroundColor3 = Color3.fromRGB(27, 30, 38)
    toast.BorderSizePixel  = 0
    toast.ClipsDescendants = true
    toast.Parent           = ToastContainer

    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", toast)
    stroke.Color       = Color3.fromRGB(139, 124, 246)
    stroke.Thickness   = 1
    stroke.Transparency = 1

    local titleLbl = Instance.new("TextLabel", toast)
    titleLbl.Size                  = UDim2.new(1, -16, 0, 20)
    titleLbl.Position              = UDim2.new(0, 10, 0, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = title
    titleLbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    titleLbl.Font                  = Enum.Font.GothamBold
    titleLbl.TextSize              = 13
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left
    titleLbl.TextTransparency      = 1

    local msgLbl = Instance.new("TextLabel", toast)
    msgLbl.Size                  = UDim2.new(1, -16, 0, 22)
    msgLbl.Position              = UDim2.new(0, 10, 0, 26)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text                  = message
    msgLbl.TextColor3            = Color3.fromRGB(200, 205, 215)
    msgLbl.Font                  = Enum.Font.Gotham
    msgLbl.TextSize              = 11
    msgLbl.TextXAlignment        = Enum.TextXAlignment.Left
    msgLbl.TextTransparency      = 1

    TweenService:Create(toast,    TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 55) }):Play()
    TweenService:Create(stroke,   TweenInfo.new(0.2), { Transparency = 0 }):Play()
    TweenService:Create(titleLbl, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
    TweenService:Create(msgLbl,   TweenInfo.new(0.2), { TextTransparency = 0 }):Play()

    task.delay(duration, function()
        pcall(function()
            TweenService:Create(toast,    TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
            TweenService:Create(stroke,   TweenInfo.new(0.2), { Transparency = 1 }):Play()
            TweenService:Create(titleLbl, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
            local tw = TweenService:Create(msgLbl, TweenInfo.new(0.2), { TextTransparency = 1 })
            tw:Play()
            tw.Completed:Wait()
            toast:Destroy()
        end)
    end)
end

-- Верхня панель
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = MainFrame

Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleLine = Instance.new("Frame", TitleBar)
TitleLine.Size             = UDim2.new(1, 0, 0, 1)
TitleLine.Position         = UDim2.new(0, 0, 1, -1)
TitleLine.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
TitleLine.BorderSizePixel  = 0

local TitleText = Instance.new("TextLabel", TitleBar)
TitleText.Size             = UDim2.new(0, 140, 1, 0)
TitleText.Position         = UDim2.new(0, 14, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text             = "UA Killer Hub"
TitleText.Font             = Enum.Font.GothamBold
TitleText.TextSize         = 14
TitleText.TextColor3       = Color3.fromRGB(240, 242, 245)
TitleText.TextXAlignment   = Enum.TextXAlignment.Left

local Badge = Instance.new("TextLabel", TitleBar)
Badge.Size             = UDim2.new(0, 36, 0, 18)
Badge.Position         = UDim2.new(0, 126, 0.5, -9)
Badge.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
Badge.Text             = "YBA"
Badge.Font             = Enum.Font.GothamBold
Badge.TextSize         = 10
Badge.TextColor3       = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", Badge).CornerRadius = UDim.new(0, 4)

local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size             = UDim2.new(0, 26, 0, 26)
CloseBtn.Position         = UDim2.new(1, -34, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
CloseBtn.Text             = "✕"
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.TextSize         = 12
CloseBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton", TitleBar)
MinBtn.Size             = UDim2.new(0, 26, 0, 26)
MinBtn.Position         = UDim2.new(1, -66, 0.5, -13)
MinBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
MinBtn.Text             = "—"
MinBtn.Font             = Enum.Font.GothamBold
MinBtn.TextSize         = 12
MinBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetSize = isMinimized and UDim2.new(0, 520, 0, 42) or UDim2.new(0, 520, 0, 255)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize }):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    showNotification("UA Killer Hub", "Натисніть RightShift, щоб відкрити знову", 3.5)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- Сайдбар
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Name             = "Sidebar"
Sidebar.Size             = UDim2.new(0, 125, 1, -42)
Sidebar.Position         = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
Sidebar.BorderSizePixel  = 0

local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.Padding             = UDim.new(0, 4)
SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarList.SortOrder           = Enum.SortOrder.LayoutOrder

local SidebarPad = Instance.new("UIPadding", Sidebar)
SidebarPad.PaddingTop   = UDim.new(0, 8)
SidebarPad.PaddingLeft  = UDim.new(0, 6)
SidebarPad.PaddingRight = UDim.new(0, 6)

-- Контентна панель
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Name                  = "ContentArea"
ContentArea.Size                  = UDim2.new(1, -125, 1, -42)
ContentArea.Position              = UDim2.new(0, 125, 0, 42)
ContentArea.BackgroundTransparency = 1

local SearchFrame = Instance.new("Frame", ContentArea)
SearchFrame.Name             = "SearchFrame"
SearchFrame.Size             = UDim2.new(1, -20, 0, 26)
SearchFrame.Position         = UDim2.new(0, 10, 0, 6)
SearchFrame.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
SearchFrame.BorderSizePixel  = 0
Instance.new("UICorner", SearchFrame).CornerRadius = UDim.new(0, 6)

local SearchIcon = Instance.new("TextLabel", SearchFrame)
SearchIcon.Size                  = UDim2.new(0, 24, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text                  = "🔍"
SearchIcon.Font                  = Enum.Font.Gotham
SearchIcon.TextSize              = 11
SearchIcon.TextColor3            = Color3.fromRGB(150, 155, 165)

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size                  = UDim2.new(1, -30, 1, 0)
SearchBox.Position              = UDim2.new(0, 28, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText       = "Пошук функцій..."
SearchBox.PlaceholderColor3     = Color3.fromRGB(110, 115, 130)
SearchBox.TextColor3            = Color3.fromRGB(240, 242, 245)
SearchBox.Font                  = Enum.Font.Gotham
SearchBox.TextSize              = 12
SearchBox.TextXAlignment        = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus      = false

local PagesFolder = Instance.new("Folder", ContentArea)
PagesFolder.Name = "Pages"

local tabs      = {}
local activeTab = nil

local function filterItems(query)
    query = query:lower()
    for _, item in ipairs(uiElementsRegistry) do
        if item.Page == activeTab then
            item.Frame.Visible = (query == "" or item.Name:lower():find(query, 1, true) ~= nil)
        end
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterItems(SearchBox.Text)
end)

local function switchTab(tabName)
    activeTab    = tabName
    SearchBox.Text = ""
    for name, tabData in pairs(tabs) do
        local active = (name == tabName)
        tabData.Page.Visible = active
        TweenService:Create(tabData.Button, TweenInfo.new(0.2), {
            BackgroundColor3 = active and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(23, 25, 32),
            TextColor3       = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 165),
        }):Play()
    end
    filterItems("")
end

local function createTab(tabName, iconText)
    local btn = Instance.new("TextButton", Sidebar)
    btn.Name             = tabName .. "_Tab"
    btn.Size             = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = Color3.fromRGB(23, 25, 32)
    btn.Text             = (iconText or "•") .. "  " .. tabName
    btn.Font             = Enum.Font.GothamMedium
    btn.TextSize         = 12
    btn.TextColor3       = Color3.fromRGB(150, 155, 165)
    btn.TextXAlignment   = Enum.TextXAlignment.Left
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIPadding", btn).PaddingLeft = UDim.new(0, 10)

    local page = Instance.new("ScrollingFrame", PagesFolder)
    page.Name                = tabName .. "_Page"
    page.Size                = UDim2.new(1, -20, 1, -40)
    page.Position            = UDim2.new(0, 10, 0, 36)
    page.BackgroundTransparency = 1
    page.BorderSizePixel     = 0
    page.ScrollBarThickness  = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(139, 124, 246)
    page.CanvasSize          = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible             = false

    local list = Instance.new("UIListLayout", page)
    list.Padding   = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", page)
    pad.PaddingRight  = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 10)

    tabs[tabName] = { Button = btn, Page = page }
    btn.MouseButton1Click:Connect(function() switchTab(tabName) end)
    return page
end

local function createSection(page, tabName, text)
    local sec = Instance.new("Frame", page)
    sec.Size                  = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", sec)
    lbl.Size                  = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text:upper()
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 10
    lbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = sec })
    return sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local toggleState = (defaultVal == true)

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -56, 1, 0)
    titleLbl.Position              = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 12
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local switch = Instance.new("TextButton", card)
    switch.Size             = UDim2.new(0, 36, 0, 20)
    switch.Position         = UDim2.new(1, -44, 0.5, -10)
    switch.BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
    switch.Text             = ""
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", switch)
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.Position         = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function setState(val, triggerCallback)
        toggleState = (val == true)
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58),
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = toggleState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        }):Play()
        if triggerCallback and callback then callback(toggleState) end
    end

    switch.MouseButton1Click:Connect(function()
        setState(not toggleState, true)
    end)

    local controlObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
            if triggerCallback == nil then triggerCallback = true end
            setState(val, triggerCallback)
        end,
        Get   = function() return toggleState end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local currentVal = defaultVal or min

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 48)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -60, 0, 20)
    titleLbl.Position              = UDim2.new(0, 12, 0, 4)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 12
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local valLabel = Instance.new("TextLabel", card)
    valLabel.Size                  = UDim2.new(0, 46, 0, 20)
    valLabel.Position              = UDim2.new(1, -54, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text                  = tostring(currentVal)
    valLabel.Font                  = Enum.Font.GothamBold
    valLabel.TextSize              = 12
    valLabel.TextColor3            = Color3.fromRGB(139, 124, 246)
    valLabel.TextXAlignment        = Enum.TextXAlignment.Right

    local track = Instance.new("Frame", card)
    track.Size             = UDim2.new(1, -24, 0, 6)
    track.Position         = UDim2.new(0, 12, 0, 32)
    track.BackgroundColor3 = Color3.fromRGB(42, 46, 58)
    track.BorderSizePixel  = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    local initialAlpha = math.clamp((currentVal - min) / (max - min), 0, 1)
    fill.Size             = UDim2.new(initialAlpha, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local draggingSlider = false
    local function updateFromX(x)
        local absPos   = track.AbsolutePosition.X
        local absSize  = track.AbsoluteSize.X
        local alpha    = math.clamp((x - absPos) / absSize, 0, 1)
        local rawValue = min + alpha * (max - min)
        local steps    = math.round((rawValue - min) / step)
        local stepped  = min + steps * step
        stepped        = math.clamp(stepped, min, max)
        currentVal     = stepped
        valLabel.Text  = tostring(currentVal)
        fill.Size      = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
        if callback then callback(currentVal) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateFromX(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    local controlObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, val, triggerCallback)
            val = math.clamp(val, min, max)
            local steps = math.round((val - min) / step)
            currentVal  = min + steps * step
            valLabel.Text = tostring(currentVal)
            fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
            if triggerCallback and callback then callback(currentVal) end
        end,
        Get   = function() return currentVal end,
    }
    table.insert(uiElementsRegistry, controlObj)
    return controlObj
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 36)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local btn = Instance.new("TextButton", card)
    btn.Size                  = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text                  = text
    btn.Font                  = Enum.Font.GothamMedium
    btn.TextSize              = 12
    btn.TextColor3            = Color3.fromRGB(240, 242, 245)

    btn.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(36, 40, 52) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.delay(0.1, function()
            TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(28, 31, 39) }):Play()
        end)
        if callback then callback() end
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return card
end

local function createStatusLabel(page, tabName, text)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 34)
    card.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", card)
    lbl.Size                  = UDim2.new(1, -20, 1, 0)
    lbl.Position              = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextSize              = 11
    lbl.TextColor3            = Color3.fromRGB(180, 185, 195)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    local statusObj = {
        Name  = text,
        Page  = tabName,
        Frame = card,
        Set   = function(self, newText) lbl.Text = newText end,
    }
    table.insert(uiElementsRegistry, statusObj)
    return statusObj
end

-- =======================================================
-- СТВОРЕННЯ ВКЛАДОК ТА ЕЛЕМЕНТІВ КЕРУВАННЯ
-- =======================================================
local mainPage  = createTab("Головна", "🏠")
local farmPage  = createTab("Автофарм", "🌾")
local sellPage  = createTab("Магазин", "💰")
local eventPage = createTab("Івент", "🎃")
local miscPage  = createTab("Різне", "⚙️")

local autoLoadToggle, jumpPowerSlider, flySpeedSlider, pickupDistanceSlider
local itemEspToggle, autoSellToggle, autoCandyToggle
local autoBuyToggle, antiAfkToggle, noclipToggle, autoRespawnToggle
local itemToggleControls = {}

local loadCurrentConfig
local saveCurrentConfig

-- ── Головна ───────────────────────────────────────────────
createSection(mainPage, "Головна", "Конфігурація")

autoLoadToggle = createToggle(mainPage, "Головна", "Авто-завантаження конфігу", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    pcall(function()
        if writefile then
            writefile(autoLoadFile, value and "true" or "false")
            showNotification("Конфігурація", "Авто-завантаження: " .. (value and "Увімкнено" or "Вимкнено"), 2.5)
        end
    end)
end)

createButton(mainPage, "Головна", "Завантажити конфіг вручну", function()
    if loadCurrentConfig then loadCurrentConfig(false) end
end)

createButton(mainPage, "Головна", "Зберегти поточний конфіг", function()
    if saveCurrentConfig then saveCurrentConfig() end
end)

createSection(mainPage, "Головна", "Характеристики")

jumpPowerSlider = createSlider(mainPage, "Головна", "Висота стрибка (JumpPower)", 50, 200, 1, JP_Value, function(val)
    JP_Value = val
    applyJumpPower()
end)

-- ── Автофарм ─────────────────────────────────────────────
createSection(farmPage, "Автофарм", "Основні параметри")

local statusLabel = createStatusLabel(farmPage, "Автофарм", "Статус: Очікування...")
task.spawn(function()
    while task.wait(0.35) do
        pcall(function() statusLabel:Set("Статус: " .. farmStatusText) end)
    end
end)

flySpeedSlider = createSlider(farmPage, "Автофарм", "Швидкість польоту", 50, 350, 5, _G.FlySpeed, function(val)
    _G.FlySpeed = val
end)

pickupDistanceSlider = createSlider(farmPage, "Автофарм", "Дистанція підбору (Неактивно)", 2, 8, 0.5, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    manuallyChanged.ItemESP = true
    _G.ItemESP = val
end)

-- Ініціалізація перемикача ItemFarm через єдиний контролер
itemFarmToggle = createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
    manuallyChanged.ItemFarm = true
    setItemFarmState(value)
end)

createSection(farmPage, "Автофарм", "Фільтр предметів")

createButton(farmPage, "Автофарм", "Увімкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = true
        if itemToggleControls[name] then itemToggleControls[name]:Set(true, false) end
    end
    lastCacheRefresh = 0
end)

createButton(farmPage, "Автофарм", "Вимкнути всі предмети", function()
    for name in pairs(_G.SelectedItems) do
        _G.SelectedItems[name] = false
        if itemToggleControls[name] then itemToggleControls[name]:Set(false, false) end
    end
    lastCacheRefresh = 0
end)

local sortedItems = {}
for name in pairs(_G.SelectedItems) do table.insert(sortedItems, name) end
table.sort(sortedItems)

for _, itemName in ipairs(sortedItems) do
    local ctrl = createToggle(farmPage, "Автофарм", itemName, _G.SelectedItems[itemName], function(val)
        _G.SelectedItems[itemName] = val
        lastCacheRefresh = 0
    end)
    itemToggleControls[itemName] = ctrl
end

-- ── Магазин ──────────────────────────────────────────────
createSection(sellPage, "Магазин", "Автопродаж")

autoSellToggle = createToggle(sellPage, "Магазин", "Увімкнути автопродаж", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    _G.AutoSell = value
    if value then processSellQueue() end
end)

createButton(sellPage, "Магазин", "Продати предмети зараз", function()
    if not isBusy then
        showNotification("Магазин", "Початок продажу предметів...", 2)
        local prev = _G.AutoSell
        _G.AutoSell = true
        processSellQueue()
        task.spawn(function()
            while isBusy do task.wait(0.2) end
            _G.AutoSell = prev
        end)
    else
        showNotification("Магазин", "Продаж уже виконується!", 2)
    end
end)

createSection(sellPage, "Магазин", "Автокупівля")

autoBuyToggle = createToggle(sellPage, "Магазин", "Автокупівля (Merchant)", _G.AutoBuy, function(value)
    manuallyChanged.AutoBuy = true
    _G.AutoBuy = value
end)

-- ── Івент ────────────────────────────────────────────────
createSection(eventPage, "Івент", "Halloween Event")

autoCandyToggle = createToggle(eventPage, "Івент", "Авто-здача конфет", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
    if value then checkAndSubmitEventCandies() end
end)

createButton(eventPage, "Івент", "Здати всі цукерки зараз", function()
    if not isBusy then
        showNotification("Івент", "Здача цукерок...", 2)
        task.spawn(function()
            isBusy = true
            submitAllCandies()
            task.wait(0.2)
            closeEventDialogue()
            isBusy = false
            showNotification("Івент", "Здачу завершено!", 2)
        end)
    else
        showNotification("Івент", "Дія вже виконується!", 2)
    end
end)

-- ── Різне ────────────────────────────────────────────────
createSection(miscPage, "Різне", "Утиліти")

antiAfkToggle = createToggle(miscPage, "Різне", "Anti-AFK", _G.AntiAFK, function(value)
    manuallyChanged.AntiAFK = true
    _G.AntiAFK = value
end)

noclipToggle = createToggle(miscPage, "Різне", "NoClip", _G.StandaloneNoClip, function(value)
    manuallyChanged.StandaloneNoClip = true
    _G.StandaloneNoClip = value
    if value then ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)

autoRespawnToggle = createToggle(miscPage, "Різне", "Авто-респавн після смерті", _G.AutoRespawn, function(value)
    manuallyChanged.AutoRespawn = true
    _G.AutoRespawn = value
end)

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЇ (ЗБЕРЕЖЕННЯ / ВІДНОВЛЕННЯ СТАНУ)
-- =======================================================
saveCurrentConfig = function()
    local data = {
        AutoSell        = _G.AutoSell,
        AutoEventCandy  = _G.AutoEventCandy,
        AutoBuy         = _G.AutoBuy,
        ItemFarm        = _G.ItemFarm,
        ItemESP         = _G.ItemESP,
        AntiAFK         = _G.AntiAFK,
        SelectedItems   = _G.SelectedItems,
        FlySpeed        = _G.FlySpeed,
        PickupDistance  = _G.PickupDistance,
        JumpPower       = JP_Value,
        StandaloneNoClip= _G.StandaloneNoClip,
        AutoRespawn     = _G.AutoRespawn,
    }

    local success, err = pcall(function()
        if writefile then
            local json = HttpService:JSONEncode(data)
            writefile(configFile, json)
            print("[UA Killer Hub | Config] Конфігурацію збережено: ItemFarm=" .. tostring(data.ItemFarm))
            showNotification("Конфігурація", "Налаштування успішно збережено!", 3)
        end
    end)
    if not success then
        warn("[UA Killer Hub | Config] Помилка збереження: " .. tostring(err))
    end
end

local function applyLoadedConfig(data, isAuto)
    if type(data) ~= "table" then return end

    if data.SelectedItems and type(data.SelectedItems) == "table" then
        for name, val in pairs(data.SelectedItems) do
            if _G.SelectedItems[name] ~= nil then
                _G.SelectedItems[name] = val
                if itemToggleControls[name] then
                    itemToggleControls[name]:Set(val, false)
                end
            end
        end
        lastCacheRefresh = 0
    end

    if data.JumpPower      and jumpPowerSlider      then jumpPowerSlider:Set(data.JumpPower, true) end
    if data.FlySpeed       and flySpeedSlider       then flySpeedSlider:Set(data.FlySpeed, true) end
    if data.PickupDistance and pickupDistanceSlider then pickupDistanceSlider:Set(data.PickupDistance, true) end

    local function applyTogglesDirectly()
        if data.ItemESP          ~= nil and itemEspToggle      then itemEspToggle:Set(data.ItemESP, false) _G.ItemESP = data.ItemESP end
        if data.AntiAFK          ~= nil and antiAfkToggle      then antiAfkToggle:Set(data.AntiAFK, true) end
        if data.AutoRespawn      ~= nil and autoRespawnToggle  then autoRespawnToggle:Set(data.AutoRespawn, true) end
        if data.StandaloneNoClip ~= nil and noclipToggle       then noclipToggle:Set(data.StandaloneNoClip, true) end
        if data.AutoBuy          ~= nil and autoBuyToggle      then autoBuyToggle:Set(data.AutoBuy, true) end
        if data.AutoSell         ~= nil and autoSellToggle     then autoSellToggle:Set(data.AutoSell, true) end
        if data.AutoEventCandy   ~= nil and autoCandyToggle    then autoCandyToggle:Set(data.AutoEventCandy, true) end
        if data.ItemFarm         ~= nil then setItemFarmState(data.ItemFarm) end
    end

    if not isAuto then
        applyTogglesDirectly()
        showNotification("Конфігурація", "Конфігурацію завантажено вручну!", 3)
        return
    end

    -- Поступове покрокове відновлення для авто-завантаження
    task.spawn(function()
        print("[UA Killer Hub | AutoLoad] Початок покрокового відновлення функцій (інтервал 1с)...")
        showNotification("Авто-завантаження", "Поступове відновлення збережених функцій...", 3)

        local toggleQueue = {
            {
                key     = "ItemESP",
                control = itemEspToggle,
                label   = "ESP",
                activate = function(val)
                    _G.ItemESP = (val == true)
                    if itemEspToggle then itemEspToggle:Set(_G.ItemESP, false) end
                end,
            },
            {
                key     = "AntiAFK",
                control = antiAfkToggle,
                label   = "Anti-AFK",
                activate = function(val)
                    if antiAfkToggle then antiAfkToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "AutoRespawn",
                control = autoRespawnToggle,
                label   = "Авто-респавн",
                activate = function(val)
                    if autoRespawnToggle then autoRespawnToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "StandaloneNoClip",
                control = noclipToggle,
                label   = "NoClip",
                activate = function(val)
                    if noclipToggle then noclipToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "AutoBuy",
                control = autoBuyToggle,
                label   = "Автокупівля",
                activate = function(val)
                    if autoBuyToggle then autoBuyToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "AutoSell",
                control = autoSellToggle,
                label   = "Автопродаж",
                activate = function(val)
                    if autoSellToggle then autoSellToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "AutoEventCandy",
                control = autoCandyToggle,
                label   = "Авто-івент",
                activate = function(val)
                    if autoCandyToggle then autoCandyToggle:Set((val == true), true) end
                end,
            },
            {
                key     = "ItemFarm",
                control = itemFarmToggle,
                label   = "Автофарм",
                activate = function(val)
                    setItemFarmState(val == true)
                end,
            },
        }

        for _, item in ipairs(toggleQueue) do
            local savedVal = data[item.key]
            if savedVal == true then
                task.wait(1.0)
                if not manuallyChanged[item.key] then
                    item.activate(true)
                    print(string.format("[UA Killer Hub | AutoLoad] Відновлено: %s (true)", item.label))
                else
                    print(string.format("[UA Killer Hub | AutoLoad] Пропущено %s: змінено користувачем під час очікування.", item.label))
                end
            else
                if item.control and not manuallyChanged[item.key] then
                    item.control:Set(false, false)
                end
            end
        end

        print("[UA Killer Hub | AutoLoad] Покрокове відновлення конфігурації завершено.")
        showNotification("Авто-завантаження", "Усі збережені функції успішно відновлено!", 3.5)
    end)
end

loadCurrentConfig = function(isAuto)
    if not isfile or not isfile(configFile) then
        if not isAuto then showNotification("Конфігурація", "Файл конфігурації не знайдено!", 3) end
        return
    end

    local success, content = pcall(function() return readfile(configFile) end)
    if not success or not content or content == "" then
        warn("[UA Killer Hub | Config] Помилка читання файлу: " .. tostring(content))
        return
    end

    local ok, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok or type(data) ~= "table" then
        warn("[UA Killer Hub | Config] Помилка розбору JSON: " .. tostring(data))
        return
    end

    print("[UA Killer Hub | Config] Завантаження конфігурації... isAuto=" .. tostring(isAuto) .. ", ItemFarm=" .. tostring(data.ItemFarm))
    applyLoadedConfig(data, isAuto)
end

-- Відкриваємо першу вкладку за замовчуванням
switchTab("Головна")

-- Якщо ввімкнено авто-завантаження — чекаємо 15 секунд і по черзі активуємо збережені функції
if shouldAutoLoad then
    task.spawn(function()
        print("[UA Killer Hub | AutoLoad] AutoLoad увімкнено. Очікування 15 секунд перед завантаженням конфігу...")
        showNotification("Авто-завантаження", "Конфіг буде застосовано через 15 секунд...", 4)
        task.wait(15)
        if shouldAutoLoad then
            loadCurrentConfig(true)
        else
            print("[UA Killer Hub | AutoLoad] Скасовано: користувач вимкнув авто-завантаження під час 15с паузи.")
        end
    end)
end

checkExistingInventoryOnStart()
print("[UA Killer Hub] Успішно запущено з покращеним ItemFarm та MonHub GUI!")
showNotification("UA Killer Hub", "Скрипт успішно запущено!", 3.5)
