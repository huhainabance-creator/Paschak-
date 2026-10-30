-- UA Killer Hub | YBA — Версія з архітектурним виправленням інвентарю та діалогів
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
local StarterGui = game:GetService("StarterGui")

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

local sellQueue          = {}
local isBusy             = false
local isBusyStartedAt    = 0
local isEquippingForSale = false
local unsellableItems    = {}
local UNSELLABLE_COOLDOWN = 60

local function getInventoryDiagnostic()
    local bp = player:FindFirstChild("Backpack")
    local char = player.Character
    local bpCount = bp and #bp:GetChildren() or 0
    local charTools = 0
    if char then
        for _, it in ipairs(char:GetChildren()) do
            if it:IsA("Tool") then charTools = charTools + 1 end
        end
    end
    local isCoreEnabled = true
    local getOk, getErr = pcall(function()
        isCoreEnabled = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    end)
    if not getOk then
        warn("[UA Killer Hub | Diag] Помилка GetCoreGuiEnabled(Backpack): " .. tostring(getErr))
    end

    local dGui = player:FindFirstChild("PlayerGui")
    local dGuiObj = dGui and (dGui:FindFirstChild("DialogueGui") or dGui:FindFirstChild("Dialogue") or dGui:FindFirstChild("DialogueBox"))
    local dGuiActive = false
    if dGuiObj then
        dGuiActive = (dGuiObj:IsA("ScreenGui") and dGuiObj.Enabled) or dGuiObj.Visible
    end

    return bpCount, charTools, isCoreEnabled, dGuiActive, dGuiObj
end

local function ensureBackpackEnabled(forceLog)
    local ok, err = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
    end)
    if not ok then
        warn("[UA Killer Hub | Inventory] Помилка виклику SetCoreGuiEnabled(Backpack, true): " .. tostring(err))
    elseif forceLog then
        local bpCount, charTools, isCore = getInventoryDiagnostic()
        print(string.format("[UA Killer Hub | Inventory] SetCoreGuiEnabled(Backpack, true) виконано | CoreEnabled: %s | Tools (BP: %d, Char: %d)",
            tostring(isCore), bpCount, charTools))
    end
end

local function isItemUnsellable(item)
    if not item then return true end
    local lastFail = unsellableItems[item]
    if lastFail and (tick() - lastFail < UNSELLABLE_COOLDOWN) then
        return true
    end
    return false
end

local function markItemUnsellable(item, reason)
    if not item then return end
    unsellableItems[item] = tick()
    warn(string.format("[UA Killer Hub | AutoSell] Предмет [%s] позначено як непродаваний на %d с. Причина: %s",
        item.Name, UNSELLABLE_COOLDOWN, tostring(reason)))
end

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
    local remoteOk, remoteErr = pcall(function()
        if remote then
            remote:FireServer("EndDialogue", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("DialogueEnd", { Option = "Option1", Dialogue = "Dialogue3", NPC = "Merchant" })
            remote:FireServer("EndDialogue", { Option = "Option2", Dialogue = "Dialogue1", NPC = "Merchant" })
        end
    end)
    if not remoteOk then
        warn("[UA Killer Hub | Merchant] Помилка відправки EndDialogue: " .. tostring(remoteErr))
    end

    local gui = getDialogueGui()
    if gui then
        local btnOk, btnErr = pcall(function()
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
        if not btnOk then
            warn("[UA Killer Hub | Merchant] Помилка кліку по кнопках виходу з діалогу: " .. tostring(btnErr))
        end
        task.wait(0.15)
    end
    ensureBackpackEnabled(false)
end

local function sellSingleItem(item)
    if not item or isItemSold(item) or DontSell[item.Name] then return true, "AlreadySold" end
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchant()
    if not hum or not remote or not merchant then return false, "MissingCharacterOrNPC" end

    isEquippingForSale = true
    hum:EquipTool(item)
    local equipTimeout = tick() + 0.8
    while tick() < equipTimeout and item.Parent ~= char do task.wait(0.04) end
    isEquippingForSale = false

    if item.Parent ~= char then
        pcall(function() hum:UnequipTools() end)
        return false, "EquipTimeout"
    end

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
    task.wait(0.1)

    local sold = isItemSold(item)
    if not sold then
        pcall(function() hum:UnequipTools() end)
    end
    ensureBackpackEnabled()

    return sold, sold and "Success" or "ItemStillExists"
end

local function sellSingleItemWithRetries(item, maxRetries)
    maxRetries = maxRetries or 3
    local lastError = "Unknown"
    for attempt = 1, maxRetries do
        if isItemSold(item) then return true, "Success" end
        local ok, errStage = sellSingleItem(item)
        if ok then return true, "Success" end
        lastError = errStage
        task.wait(0.2)
    end

    markItemUnsellable(item, lastError or "SellTimeout")
    local _, _, hum = getCharacter()
    if hum then pcall(function() hum:UnequipTools() end) end
    ensureBackpackEnabled()

    return false, lastError
end

local function isItemInQueue(item)
    for _, q in ipairs(sellQueue) do if q == item then return true end end
    return false
end

local function queueItemForSale(item)
    if not item or not item:IsA("Tool") or DontSell[item.Name] then return end
    if isItemSold(item) or isItemInQueue(item) or isItemUnsellable(item) then return end
    table.insert(sellQueue, item)
end

local function syncSellQueue()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
                queueItemForSale(item)
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
                queueItemForSale(item)
            end
        end
    end
end

local function hasSellableItems()
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
                return true
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
                return true
            end
        end
    end
    return false
end

local backpackChildConn   = nil
local characterChildConn  = nil

local function setupBackpackListener(backpack)
    if backpackChildConn then
        pcall(function() backpackChildConn:Disconnect() end)
        backpackChildConn = nil
    end
    if not backpack then return end
    syncSellQueue()
    backpackChildConn = backpack.ChildAdded:Connect(function(item)
        task.wait(0.15)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
            queueItemForSale(item)
        end
    end)
end

local function setupCharacterInventoryListener(char)
    if characterChildConn then
        pcall(function() characterChildConn:Disconnect() end)
        characterChildConn = nil
    end
    if not char then return end
    characterChildConn = char.ChildAdded:Connect(function(item)
        if isEquippingForSale then return end
        task.wait(0.15)
        if _G.AutoSell and item:IsA("Tool") and not DontSell[item.Name] and not isItemUnsellable(item) then
            queueItemForSale(item)
        end
    end)
end

player.ChildAdded:Connect(function(child)
    if child.Name == "Backpack" then
        setupBackpackListener(child)
        ensureBackpackEnabled()
    end
end)
if player:FindFirstChild("Backpack") then
    setupBackpackListener(player.Backpack)
    ensureBackpackEnabled()
end

local function countTotalCandies()
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return 0 end
    local count = 0
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and EventCandies[item.Name] then count += 1 end
    end
    return count
end

local function clickEventCandyOption()
    local gui = getDialogueGui()
    if not gui then return false end
    for _, btn in ipairs(gui:GetDescendants()) do
        if (btn:IsA("TextButton") or btn:IsA("ImageButton")) and isGuiElementVisible(btn) then
            local txt = btn.Text or ""
            local childText = btn:FindFirstChildOfClass("TextLabel")
            if childText and childText.Text ~= "" then txt = childText.Text end
            local lowerTxt = txt:lower()
            if lowerTxt:find("turn in") or (lowerTxt:find("candy") and not lowerTxt:find("what do i do") and not lowerTxt:find("could you please")) then
                pcall(function()
                    if firesignal then firesignal(btn.MouseButton1Click) firesignal(btn.Activated)
                    else btn.Activated:Fire() end
                end)
                return true
            end
        end
    end
    return false
end

-- Надійне визначення активного діалогового вікна Jack із перевіркою видимості
local function findJackDialogue()
    local gui = getDialogueGui()
    if not gui then return nil end

    local isGuiEnabled = (gui:IsA("ScreenGui") and gui.Enabled) or gui.Visible
    if not isGuiEnabled then return nil end

    local hasJack      = false
    local hasPoints    = false
    local continueElem = nil
    local pointsElem   = nil
    local dialogueBox  = nil
    local anyButton    = nil

    for _, desc in ipairs(gui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            if isGuiElementVisible(desc) then
                local txt   = desc.Text or ""
                local lower = txt:lower()

                if lower:find("jack") or lower:find("cauldron specter") then
                    hasJack = true
                end
                if lower:find("point") then
                    hasPoints = true
                    pointsElem = desc
                    if desc.Parent and desc.Parent:IsA("GuiObject") and desc.Parent.AbsoluteSize.Y > 40 then
                        dialogueBox = desc.Parent
                    end
                end
                if lower:find("click to continue") or (lower:find("continue") and not lower:find("option")) then
                    continueElem = desc
                end
            end
        end

        if desc:IsA("GuiButton") and isGuiElementVisible(desc) then
            anyButton = desc
        end

        if not dialogueBox and desc:IsA("Frame") and isGuiElementVisible(desc) and desc.AbsoluteSize.Y > 60 then
            dialogueBox = desc
        end
    end

    if (hasJack or hasPoints) and (pointsElem or continueElem or dialogueBox) then
        return {
            gui          = gui,
            hasJack      = hasJack,
            hasPoints    = hasPoints,
            continueElem = continueElem,
            pointsElem   = pointsElem,
            dialogueBox  = dialogueBox or (pointsElem and pointsElem.Parent) or (continueElem and continueElem.Parent),
            anyButton    = anyButton,
        }
    end
    return nil
end

-- Автоматичне закриття діалогу через штатну взаємодію з інтерфейсом
local function clickContinueButton(jackData)
    if not jackData then return end

    -- Повна діагностика знайдених елементів
    print("[UA Killer Hub | Event] Діагностика GUI-елементів діалогу Jack:")
    if jackData.pointsElem then
        print(string.format("  • [PointsLabel] Class: %s | Name: '%s' | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.pointsElem.ClassName, jackData.pointsElem.Name, jackData.pointsElem.Text,
            jackData.pointsElem.AbsolutePosition.X, jackData.pointsElem.AbsolutePosition.Y,
            jackData.pointsElem.AbsoluteSize.X, jackData.pointsElem.AbsoluteSize.Y))
    end
    if jackData.continueElem then
        print(string.format("  • [ContinueElem] Class: %s | Name: '%s' | Text: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.continueElem.ClassName, jackData.continueElem.Name, jackData.continueElem.Text,
            jackData.continueElem.AbsolutePosition.X, jackData.continueElem.AbsolutePosition.Y,
            jackData.continueElem.AbsoluteSize.X, jackData.continueElem.AbsoluteSize.Y))
    end
    if jackData.dialogueBox then
        print(string.format("  • [DialogueBox] Class: %s | Name: '%s' | Pos: (%d, %d) | Size: (%d, %d)",
            jackData.dialogueBox.ClassName, jackData.dialogueBox.Name,
            jackData.dialogueBox.AbsolutePosition.X, jackData.dialogueBox.AbsolutePosition.Y,
            jackData.dialogueBox.AbsoluteSize.X, jackData.dialogueBox.AbsoluteSize.Y))
    end
    if jackData.anyButton then
        print(string.format("  • [FoundButton] Class: %s | Name: '%s' | Text: '%s'",
            jackData.anyButton.ClassName, jackData.anyButton.Name, tostring(jackData.anyButton.Text or "")))
    end

    pcall(function()
        -- 1. Якщо елемент мітки чи її батьківський контейнер є кнопкою — викликаємо штатні сигнали
        local targetBtn = (jackData.continueElem and jackData.continueElem:IsA("GuiButton") and jackData.continueElem)
            or (jackData.continueElem and jackData.continueElem.Parent and jackData.continueElem.Parent:IsA("GuiButton") and jackData.continueElem.Parent)
            or jackData.anyButton

        if targetBtn then
            print("[UA Killer Hub | Event] Виклик сигналу кнопки: " .. targetBtn.Name)
            if firesignal then
                firesignal(targetBtn.MouseButton1Click)
                firesignal(targetBtn.Activated)
            else
                targetBtn.Activated:Fire()
            end
        end

        -- 2. Штатний клік мишкою по центру чорного діалогового вікна (де розташований текст і де клікає гравець)
        local targetBox = jackData.dialogueBox or (jackData.pointsElem and jackData.pointsElem.Parent) or jackData.pointsElem
        if VirtualInputManager and targetBox and targetBox:IsA("GuiObject") then
            local absPos = targetBox.AbsolutePosition
            local absSize = targetBox.AbsoluteSize
            local clickX = absPos.X + absSize.X / 2
            local clickY = absPos.Y + absSize.Y / 2

            print(string.format("[UA Killer Hub | Event] Клік мишкою по центру рамки діалогу: (%d, %d)", math.floor(clickX), math.floor(clickY)))
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end

        -- 3. Додатковий клік по центру тексту Continue (якщо він окремий від головної рамки)
        if VirtualInputManager and jackData.continueElem and jackData.continueElem:IsA("GuiObject") and jackData.continueElem ~= targetBox then
            local absPos = jackData.continueElem.AbsolutePosition
            local absSize = jackData.continueElem.AbsoluteSize
            local clickX = absPos.X + absSize.X / 2
            local clickY = absPos.Y + absSize.Y / 2

            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
        end
    end)
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not remote or not hum or not eventNPC then return false end

    local success = false
    pcall(function()
        print("[UA Killer Hub | Event] Взаємодія з Jack...")
        remote:FireServer("PromptTriggered", eventNPC)

        local optionFound   = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then optionFound = true break end
            task.wait(0.15)
        end
        if not optionFound then
            print("[UA Killer Hub | Event] Меню здачі цукерок не з'явилося.")
            return
        end

        print("[UA Killer Hub | Event] Очікування повідомлення про отримані очки...")
        local pointsFound   = false
        local jackData      = nil
        local pointsTimeout = tick() + 4.0
        while tick() < pointsTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then
                pointsFound = true
                local msgText = jackData.pointsElem and jackData.pointsElem.Text or "Очки отримано"
                print(string.format("[UA Killer Hub | Event] Отримано підтвердження: '%s'", msgText))
                break
            end
            task.wait(0.15)
        end
        if not pointsFound or not jackData then
            print("[UA Killer Hub | Event] Повідомлення про очки не з'явилося (таймаут).")
            return
        end

        task.wait(0.35)

        -- Спроба закриття через визначені елементи
        clickContinueButton(jackData)

        -- Перевірка моменту закриття діалогу
        local closeTimeout = tick() + 2.0
        local isClosed     = false
        while tick() < closeTimeout do
            task.wait(0.15)
            if not findJackDialogue() then
                isClosed = true
                break
            end
        end

        if isClosed then
            print("[UA Killer Hub | Event] Діалог Jack успішно закрито!")
            success = true
        else
            print("[UA Killer Hub | Event] Діалог ще відкритий, виконуємо повторний клік...")
            local retryData = findJackDialogue()
            if retryData then
                clickContinueButton(retryData)
                task.wait(0.3)
                if not findJackDialogue() then
                    print("[UA Killer Hub | Event] Діалог Jack успішно закрито після повторного кліку!")
                    success = true
                end
            end
        end
    end)
    return success
end

-- Головний потік продажів та цукерок з повним захистом від зависання
task.spawn(function()
    while true do
        task.wait(0.3)
        if isBusy then
            if isBusyStartedAt > 0 and (tick() - isBusyStartedAt > 20) then
                warn(string.format("[UA Killer Hub | State] УВАГА: виявлено завислий стан isBusy = true (триває %.1fs). Примусове скидання!", tick() - isBusyStartedAt))
                isBusy = false
                isBusyStartedAt = 0
                local _, _, hum = getCharacter()
                if hum then pcall(function() hum:UnequipTools() end) end
                closeMerchantDialogue()
                ensureBackpackEnabled(true)
            end
            continue
        end

        if _G.AutoEventCandy and countTotalCandies() >= 10 then
            isBusy = true
            isBusyStartedAt = tick()
            local ok, err = pcall(function()
                closeMerchantDialogue()
                local candyTimeout = tick() + 25
                while countTotalCandies() > 0 and _G.AutoEventCandy and tick() < candyTimeout do
                    submitAllCandies()
                    task.wait(0.5)
                end
            end)
            if not ok then
                warn("[UA Killer Hub | Event] Помилка виконання циклу AutoEventCandy: " .. tostring(err))
            end
            local _, _, hum = getCharacter()
            if hum then pcall(function() hum:UnequipTools() end) end
            ensureBackpackEnabled(false)
            isBusy = false
            isBusyStartedAt = 0
            continue
        end

        if _G.AutoSell and (#sellQueue > 0 or hasSellableItems()) then
            isBusy = true
            isBusyStartedAt = tick()
            local ok, err = pcall(function()
                syncSellQueue()
                local sellTimeout = tick() + 30
                while _G.AutoSell and #sellQueue > 0 and tick() < sellTimeout do
                    local item = table.remove(sellQueue, 1)
                    if item and not isItemSold(item) and not DontSell[item.Name] and not isItemUnsellable(item) then
                        sellSingleItemWithRetries(item, 3)
                        task.wait(0.15)
                    end
                end
            end)
            if not ok then
                warn("[UA Killer Hub | AutoSell] Помилка виконання циклу AutoSell: " .. tostring(err))
            end
            closeMerchantDialogue()
            local _, _, hum = getCharacter()
            if hum then pcall(function() hum:UnequipTools() end) end
            ensureBackpackEnabled(false)
            isBusy = false
            isBusyStartedAt = 0
        end
    end
end)

local function applyJumpPower()
    local _, _, hum = getCharacter()
    if hum then hum.JumpPower = JP_Value end
end

player.CharacterAdded:Connect(function(newChar)
    task.wait(0.5)
    applyJumpPower()
    setupCharacterInventoryListener(newChar)
    ensureBackpackEnabled()
end)

if player.Character then
    setupCharacterInventoryListener(player.Character)
    ensureBackpackEnabled()
end

-- Сторожовий таймер (Watchdog) для перевірки та діагностики Backpack GUI
local lastLoggedCoreState = nil
local restoreAttempts = 0

task.spawn(function()
    while true do
        task.wait(2.5)
        local diagOk, diagErr = pcall(function()
            local bpCount, charTools, isCoreBackpackEnabled, dGuiActive, dGuiObj = getInventoryDiagnostic()

            -- Логуємо тільки зміну стану для запобігання спаму
            if lastLoggedCoreState ~= isCoreBackpackEnabled then
                lastLoggedCoreState = isCoreBackpackEnabled
                print(string.format("[UA Killer Hub | Watchdog] Стан Backpack GUI: CoreEnabled=%s | isBusy=%s | DialogueActive=%s (Obj: %s) | Tools (Backpack: %d, Char: %d)",
                    tostring(isCoreBackpackEnabled), tostring(isBusy), tostring(dGuiActive), tostring(dGuiObj and dGuiObj.Name or "None"), bpCount, charTools))
            end

            -- Якщо CoreEnabled == false і немає активного діалогу з NPC
            if not isCoreBackpackEnabled and not dGuiActive then
                if restoreAttempts < 3 then
                    restoreAttempts = restoreAttempts + 1
                    warn(string.format("[UA Killer Hub | Watchdog] CoreGuiType.Backpack вимкнено без активного діалогу! Спроба відновлення %d/3...", restoreAttempts))
                    ensureBackpackEnabled(true)
                end
            elseif isCoreBackpackEnabled then
                restoreAttempts = 0
            end

            -- Якщо персонаж тримає предмет, але жодна операція не виконується
            if not isBusy and charTools > 0 and not _G.AutoSell and not _G.AutoEventCandy then
                local _, _, hum = getCharacter()
                if hum then
                    pcall(function() hum:UnequipTools() end)
                end
            end
        end)

        if not diagOk then
            warn("[UA Killer Hub | Watchdog] Помилка діагностичного циклу: " .. tostring(diagErr))
        end
    end
end)

task.spawn(function()
    while task.wait(0.2) do applyJumpPower() end
end)

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
    return player:WaitForChild("PlayerGui", 5) or player:FindFirstChildOfClass("PlayerGui")
end

local targetGuiParent = getSafeGuiParent()
print("[UA Killer Hub | GUI] Контейнер GUI: " .. tostring(targetGuiParent and targetGuiParent.Name))

pcall(function()
    if targetGuiParent then
        local old = targetGuiParent:FindFirstChild("UAKillerHub_GUI")
        if old then old:Destroy() end
    end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        local oldPg = pg:FindFirstChild("UAKillerHub_GUI")
        if oldPg then oldPg:Destroy() end
    end
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
    if value then syncSellQueue() end
end)

createButton(sellPage, "Магазин", "Продати предмети зараз", function()
    if not isBusy then
        showNotification("Магазин", "Початок продажу предметів...", 2)
        local prev = _G.AutoSell
        _G.AutoSell = true
        syncSellQueue()
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
    if value and countTotalCandies() > 0 then
        task.spawn(function()
            isBusy = true
            while countTotalCandies() > 0 and _G.AutoEventCandy do
                submitAllCandies()
                task.wait(0.5)
            end
            ensureBackpackEnabled()
            isBusy = false
        end)
    end
end)

createButton(eventPage, "Івент", "Здати всі цукерки зараз", function()
    if not isBusy then
        showNotification("Івент", "Здача цукерок...", 2)
        task.spawn(function()
            isBusy = true
            submitAllCandies()
            task.wait(0.2)
            ensureBackpackEnabled()
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

print("[UA Killer Hub] Успішно запущено з виправленим інвентарем та MonHub GUI!")
showNotification("UA Killer Hub", "Скрипт успішно запущено!", 3.5)
