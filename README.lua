-- UA Killer Hub | YBA — Версія з оптимізованим компактним розміром GUI (висота ~255px)
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
    if hookmetamethod and checkcaller and getcallingscript then
        local primary = player.Character and player.Character.PrimaryPart
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

-- =======================================================
-- БЕЗПЕЧНИЙ CRASH & WALKSPEED BYPASS
-- =======================================================
pcall(function()
    if hookmetamethod and checkcaller then
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid", 5)
        if humanoid then
            local OldIndex
            OldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Key)
                if not checkcaller() and self == humanoid and Key == "WalkSpeed" then
                    return 16
                end
                return OldIndex(self, Key)
            end))
            print("[UA Killer Hub | Init] WalkSpeed/Crash Bypass активовано.")
        end
    end
end)

-- =======================================================
-- Ініціалізація папки та флагу авто-завантаження
-- =======================================================
pcall(function()
    if isfolder and not isfolder("UAKillerHub") then
        makefolder("UAKillerHub")
    end
    if isfile and isfile(autoLoadFile) then
        local content = readfile(autoLoadFile)
        shouldAutoLoad = (content == "true")
        print("[UA Killer Hub | Init] Автозавантаження у файлі: " .. tostring(shouldAutoLoad))
    end
end)

-- =======================================================
-- ГЛОБАЛЬНІ НАЛАШТУВАННЯ
-- =======================================================
_G.ItemFarm        = false
_G.AutoSell        = false
_G.AutoEventCandy  = false
_G.AutoBuy         = false
_G.ItemESP         = false
_G.FlySpeed        = 120
_G.PickupDistance  = 3
JP_Value           = 50

_G.SelectedItems = {
    ["Mysterious Arrow"] = false,
    ["Rokakaka"]         = false,
    ["Lucky Arrow"]      = false,
    ["Pure Rokakaka"]    = false,
    ["Rib Cage of the Saint's Corpse"] = false,
    ["Left Arm of the Saint's Corpse"] = false,
    ["Heart of the Saint's Corpse"]    = false,
    ["Pelvis of the Saint's Corpse"]   = false,
    ["Deo's Diary"]      = false,
    ["Ancient Scroll"]   = false,
    ["Quinton's Glove"]  = false,
    ["Steel Ball"]       = false,
    ["Zepellin's Headband"] = false,
    ["Clackers"]         = false,
    ["Stone Mask"]       = false,
    ["Diamond"]          = false,
    ["Gold Coin"]        = false,
    ["Blue Candy"]       = false,
    ["Green Candy"]      = false,
    ["Red Candy"]        = false,
    ["Yellow Candy"]     = false,
}

_G.ShopItems = {
    ["Mysterious Arrow"] = false,
    ["Rokakaka"]         = false,
}

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

local farmThreadActive  = false
local farmStatusText    = "Очікування..."

local flightState
local noclipConnection
local antiAfkConnection

-- =======================================================
-- ДОПОМІЖНІ ФУНКЦІЇ
-- =======================================================
local function setFarmStatus(text)
    farmStatusText = text
end

local function isPlayerAlive()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    return hum and hum.Health > 0 and char.PrimaryPart ~= nil
end

local function applyJumpPower()
    pcall(function()
        local char = player.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.UseJumpPower = true
            char.Humanoid.JumpPower = JP_Value
        end
    end)
end

-- Безпечний NoClip
local function enableNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        pcall(function()
            local char = player.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end)
end

local function disableNoClip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end

-- Політ
local function startFlight()
    if flightState then return end
    local char = player.Character
    if not char or not char.PrimaryPart then return end

    local hrp = char.PrimaryPart
    enableNoClip()

    local bv = Instance.new("BodyVelocity")
    bv.Name = "HubFlightVelocity"
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = "HubFlightGyro"
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.CFrame = hrp.CFrame
    bg.P = 10000
    bg.Parent = hrp

    flightState = { bv = bv, bg = bg }
end

local function stopFlight()
    if flightState then
        pcall(function()
            if flightState.bv then flightState.bv:Destroy() end
            if flightState.bg then flightState.bg:Destroy() end
        end)
        flightState = nil
    end
    disableNoClip()
end

local function flyTo(targetPos, speed, stopDist)
    stopDist = stopDist or 2
    local char = player.Character
    if not char or not char.PrimaryPart then return false end

    local hrp = char.PrimaryPart
    startFlight()

    while _G.ItemFarm and isPlayerAlive() do
        local currentPos = hrp.Position
        local diff = targetPos - currentPos
        local dist = diff.Magnitude

        if dist <= stopDist then
            if flightState and flightState.bv then
                flightState.bv.Velocity = Vector3.zero
            end
            return true
        end

        local dir = diff.Unit
        if flightState and flightState.bv and flightState.bg then
            flightState.bv.Velocity = dir * (speed or _G.FlySpeed)
            flightState.bg.CFrame = CFrame.new(currentPos, currentPos + dir)
        end

        task.wait(0.05)
    end
    return false
end

-- =======================================================
-- ЄДИНИЙ КОНТРОЛЕР СТАНУ ITEMFARM
-- =======================================================
local itemFarmToggle
local startFarmThread

local function setItemFarmState(enabled)
    _G.ItemFarm = (enabled == true)
    if itemFarmToggle and itemFarmToggle:Get() ~= _G.ItemFarm then
        itemFarmToggle:Set(_G.ItemFarm, false)
    end

    if _G.ItemFarm then
        startFarmThread()
    else
        farmThreadActive = false
        setFarmStatus("Зупинено")
        stopFlight()
    end

    print(string.format("[UA Killer Hub | Farm] Стан синхронізовано: _G.ItemFarm=%s, farmThreadActive=%s",
        tostring(_G.ItemFarm),
        tostring(farmThreadActive)
    ))
end

-- =======================================================
-- АВТО-ПІДБІР ТА ЛОГІКА ITEM FARM
-- =======================================================
local function fireProximityPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    local success = false
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
            success = true
        end
    end)
    if not success then
        pcall(function()
            local oldHold = prompt.HoldDuration
            prompt.HoldDuration = 0
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
            prompt.HoldDuration = oldHold
            success = true
        end)
    end
    return success
end

local function findTargetItems()
    local targets = {}
    local itemSpawns = workspace:FindFirstChild("Item_Spawns")
    local itemsFolder = itemSpawns and itemSpawns:FindFirstChild("Items")
    if not itemsFolder then return targets end

    for _, obj in ipairs(itemsFolder:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local itemName = obj.Name
            local isSelected = _G.SelectedItems[itemName]
            if isSelected then
                local promptPart = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                if promptPart and prompt then
                    table.insert(targets, {
                        instance = obj,
                        part     = promptPart,
                        prompt   = prompt,
                        name     = itemName
                    })
                end
            end
        end
    end
    return targets
end

startFarmThread = function()
    if farmThreadActive then return end
    farmThreadActive = true

    task.spawn(function()
        print("[UA Killer Hub | Farm] Потік автофарму запущено.")
        while _G.ItemFarm do
            if not isPlayerAlive() then
                setFarmStatus("Очікування персонажа...")
                stopFlight()
                task.wait(1)
                continue
            end

            setFarmStatus("Пошук предметів...")
            local targets = findTargetItems()

            if #targets == 0 then
                setFarmStatus("Предметів не знайдено")
                stopFlight()
                task.wait(1.5)
                continue
            end

            local hrp = player.Character.PrimaryPart
            table.sort(targets, function(a, b)
                return (a.part.Position - hrp.Position).Magnitude < (b.part.Position - hrp.Position).Magnitude
            end)

            local targetItem = targets[1]
            setFarmStatus("Лечу до: " .. targetItem.name)

            local reached = flyTo(targetItem.part.Position, _G.FlySpeed, _G.PickupDistance)
            if reached and _G.ItemFarm and targetItem.instance.Parent then
                setFarmStatus("Підбираю: " .. targetItem.name)
                task.wait(0.15)
                for _ = 1, 3 do
                    if not targetItem.instance.Parent then break end
                    fireProximityPrompt(targetItem.prompt)
                    task.wait(0.2)
                end
                task.wait(0.2)
            end
            task.wait(0.1)
        end

        stopFlight()
        setFarmStatus("Зупинено")
        farmThreadActive = false
        print("[UA Killer Hub | Farm] Потік автофарму зупинено.")
    end)
end

-- =======================================================
-- ХЕЛЛОВІН ІВЕНТ ТА АВТО-ПРОДАЖ
-- =======================================================
local function countTotalCandies()
    local count = 0
    local bp = player:FindFirstChild("Backpack")
    local ch = player.Character
    local candyNames = {
        ["Green Candy"] = true, ["Yellow Candy"] = true,
        ["Blue Candy"]  = true, ["Red Candy"]    = true,
    }
    local function checkContainer(c)
        if not c then return end
        for _, it in ipairs(c:GetChildren()) do
            if it:IsA("Tool") and candyNames[it.Name] then
                count = count + 1
            end
        end
    end
    checkContainer(bp)
    checkContainer(ch)
    return count
end

local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local d = pg:FindFirstChild("Dialogue") or pg:FindFirstChild("DialogueGui")
    return d and d:FindFirstChild("Halloween Event")
end

local function isGuiElementVisible(elem)
    if not elem then return false end
    local cur = elem
    while cur and cur:IsA("GuiObject") do
        if not cur.Visible then return false end
        cur = cur.Parent
    end
    local screenGui = elem:FindFirstAncestorWhichIsA("ScreenGui")
    if screenGui and not screenGui.Enabled then return false end
    return true
end

local function clickGuiElement(elem)
    if not elem or not elem:IsA("GuiObject") then return false end
    local ap = elem.AbsolutePosition
    local as = elem.AbsoluteSize
    if as.X <= 0 or as.Y <= 0 then return false end
    local cx = ap.X + as.X / 2
    local cy = ap.Y + as.Y / 2
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
    return true
end

local function closeAllPlayerDialogueGuis()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, gui in ipairs(pg:GetChildren()) do
        local nameLower = gui.Name:lower()
        if nameLower:find("dialogue") or nameLower:find("npc") or nameLower:find("chat") or nameLower:find("talk") then
            if gui:IsA("ScreenGui") and gui.Enabled then
                pcall(function() gui.Enabled = false end)
            end
            for _, descendant in ipairs(gui:GetDescendants()) do
                if descendant:IsA("GuiObject") and descendant.Visible then
                    pcall(function() descendant.Visible = false end)
                end
            end
        end
    end
end

local function closeMerchantDialogue()
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("Modules", 5)
    remote = remote and remote:WaitForChild("Net", 5)
    remote = remote and remote:WaitForChild("RE_DialogueOptionSelected", 5)
    if remote then
        pcall(function()
            remote:FireServer("EndDialogue")
            remote:FireServer("Close")
            remote:FireServer("Cancel")
        end)
    end
    task.wait(0.08)
    closeAllPlayerDialogueGuis()
end

local function sellItem(itemName)
    local char = player.Character
    local bp = player:FindFirstChild("Backpack")
    local item = (char and char:FindFirstChild(itemName)) or (bp and bp:FindFirstChild(itemName))
    if not item then return false end

    local remote = game:GetService("ReplicatedStorage"):WaitForChild("Modules", 5)
    remote = remote and remote:WaitForChild("Net", 5)
    remote = remote and remote:WaitForChild("RF_ItemAction", 5)
    if remote then
        local res
        pcall(function()
            res = remote:InvokeServer("Sell", item)
        end)
        task.wait(0.15)
        return true
    end
    return false
end

local function autoSellRoutine()
    if not _G.AutoSell then return end
    local merchant = workspace:FindFirstChild("Merchant") or workspace:FindFirstChild("Merchant NPC")
    if not merchant then return end
    local prompt = merchant:FindFirstChildWhichIsA("ProximityPrompt", true)

    for itemKey, shouldSell in pairs(_G.SelectedItems) do
        if shouldSell and _G.AutoSell then
            while _G.AutoSell do
                local char = player.Character
                local bp = player:FindFirstChild("Backpack")
                local found = (char and char:FindFirstChild(itemKey)) or (bp and bp:FindFirstChild(itemKey))
                if not found then break end

                if prompt and isPlayerAlive() then
                    fireProximityPrompt(prompt)
                    task.wait(0.2)
                end
                sellItem(itemKey)
                task.wait(0.2)
            end
        end
    end
    closeMerchantDialogue()
end

local function interactWithJack()
    local char = player.Character
    local jack = workspace:FindFirstChild("Jack, The Cauldron Specter")
    if not jack then
        for _, model in ipairs(workspace:GetChildren()) do
            if model:IsA("Model") and (model.Name:lower():find("jack") or model.Name:lower():find("specter")) then
                jack = model
                break
            end
        end
    end
    if not jack then return false end
    local prompt = jack:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        fireProximityPrompt(prompt)
        task.wait(0.25)
        return true
    end
    return false
end

local function clickEventCandyOption()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, elem in ipairs(pg:GetDescendants()) do
        if elem:IsA("TextButton") or elem:IsA("ImageButton") or elem:IsA("TextLabel") then
            local txt = elem:IsA("TextLabel") and elem.Text or (elem:IsA("TextButton") and elem.Text or "")
            local lowerTxt = txt:lower()
            if lowerTxt:find("turn in") or (lowerTxt:find("candy") and not lowerTxt:find("what")) then
                local btn = elem:IsA("GuiButton") and elem or elem:FindFirstAncestorWhichIsA("GuiButton")
                if btn and isGuiElementVisible(btn) then
                    clickGuiElement(btn)
                    return true
                end
            end
        end
    end
    return false
end

local function findJackDialogue()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end

    local hasJack      = false
    local hasPoints    = false
    local continueElem = nil
    local pointsElem   = nil
    local dialogueBox  = nil

    for _, gui in ipairs(pg:GetChildren()) do
        local isGuiEnabled = (gui:IsA("ScreenGui") and gui.Enabled) or gui.Visible
        if isGuiEnabled then
            for _, desc in ipairs(gui:GetDescendants()) do
                if desc:IsA("GuiObject") and isGuiElementVisible(desc) then
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        local text  = desc.Text or ""
                        local lower = text:lower()

                        if lower:find("jack") or lower:find("cauldron specter") then
                            hasJack = true
                            if not dialogueBox then
                                dialogueBox = desc:FindFirstAncestorWhichIsA("Frame") or desc.Parent
                            end
                        end

                        if lower:find("you now have") or (lower:find("points") and lower:find("have")) then
                            hasPoints  = true
                            pointsElem = desc
                            if not dialogueBox then
                                dialogueBox = desc:FindFirstAncestorWhichIsA("Frame") or desc.Parent
                            end
                        end

                        if lower:find("click to continue") or lower:find("continue") then
                            continueElem = desc
                            if not dialogueBox then
                                dialogueBox = desc:FindFirstAncestorWhichIsA("Frame") or desc.Parent
                            end
                        end
                    end
                end
            end
        end
    end

    if (hasJack or hasPoints) and (pointsElem or continueElem or dialogueBox) then
        return {
            pointsElem   = pointsElem,
            continueElem = continueElem,
            dialogueBox  = dialogueBox,
            hasJack      = hasJack,
            hasPoints    = hasPoints,
        }
    end
    return nil
end

local function clickJackContinue(jackData)
    if not jackData then return false end
    local clicked = false

    local targetBtn = nil
    if jackData.continueElem and jackData.continueElem:IsA("GuiButton") then
        targetBtn = jackData.continueElem
    elseif jackData.continueElem then
        targetBtn = jackData.continueElem:FindFirstAncestorWhichIsA("GuiButton")
    end

    if targetBtn and isGuiElementVisible(targetBtn) then
        pcall(function()
            if firesignal and targetBtn.Activated then
                firesignal(targetBtn.Activated)
                clicked = true
            end
        end)
        if not clicked then
            clicked = clickGuiElement(targetBtn)
        end
    end

    if not clicked and jackData.continueElem and isGuiElementVisible(jackData.continueElem) then
        clicked = clickGuiElement(jackData.continueElem)
    end

    if not clicked and jackData.pointsElem and isGuiElementVisible(jackData.pointsElem) then
        clicked = clickGuiElement(jackData.pointsElem)
    end

    if not clicked and jackData.dialogueBox and isGuiElementVisible(jackData.dialogueBox) then
        clicked = clickGuiElement(jackData.dialogueBox)
    end

    return clicked
end

local function submitAllCandies()
    if not _G.AutoEventCandy then return end
    print("[UA Killer Hub | Event] Початок автоматичної здачі цукерок Jack...")

    local jackInteracted = interactWithJack()
    if not jackInteracted then
        print("[UA Killer Hub | Event] Jack NPC не знайдено поблизу.")
        return
    end

    task.wait(0.35)

    local optionFound = false
    local optionTimeout = tick() + 3
    while tick() < optionTimeout and _G.AutoEventCandy do
        if clickEventCandyOption() then
            optionFound = true
            break
        end
        task.wait(0.2)
    end

    task.wait(0.3)

    local jackData = nil
    local pointsTimeout = tick() + 4
    while tick() < pointsTimeout and _G.AutoEventCandy do
        jackData = findJackDialogue()
        if jackData then break end
        task.wait(0.15)
    end

    if jackData then
        print("[UA Killer Hub | Event] Діалог отримання очок виявлено. Виконую клік...")
        for attempt = 1, 4 do
            clickJackContinue(jackData)
            task.wait(0.25)
            if not findJackDialogue() then
                print("[UA Killer Hub | Event] Діалог Jack успішно закрито після кліку!")
                break
            end
        end

        if findJackDialogue() then
            print("[UA Killer Hub | Event] Застосовую примусове закриття діалогових GUI...")
            closeAllPlayerDialogueGuis()
        end
    else
        closeAllPlayerDialogueGuis()
    end
end

task.spawn(function()
    while task.wait(3.5) do
        if _G.AutoEventCandy and isPlayerAlive() then
            if countTotalCandies() > 0 then
                submitAllCandies()
            end
        end
        if _G.AutoSell and isPlayerAlive() then
            autoSellRoutine()
        end
    end
end)

-- =======================================================
-- ПЕРЕВІРКА ТА ІНІЦІАЛІЗАЦІЯ БАТЬКІВСЬКОГО GUI
-- =======================================================
local function getSafeGuiParent()
    local success, core = pcall(function() return game:GetService("CoreGui") end)
    if success and core then return core end
    return player:WaitForChild("PlayerGui")
end

local targetGuiParent = getSafeGuiParent()

pcall(function()
    local old = targetGuiParent:FindFirstChild("UAKillerHub_GUI")
    if old then old:Destroy() end
end)

-- =======================================================
-- ГОЛОВНЕ ВІКНО MONHUB GUI (ВИСОТА ~255px)
-- =======================================================
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

-- Верхня панель (TitleBar)
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
SearchIcon.TextSize              = 10
SearchIcon.TextColor3            = Color3.fromRGB(120, 125, 135)

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size                  = UDim2.new(1, -30, 1, 0)
SearchBox.Position              = UDim2.new(0, 26, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText       = "Пошук функції..."
SearchBox.PlaceholderColor3     = Color3.fromRGB(110, 115, 125)
SearchBox.Text                  = ""
SearchBox.Font                  = Enum.Font.Gotham
SearchBox.TextSize              = 11
SearchBox.TextColor3            = Color3.fromRGB(230, 233, 240)
SearchBox.TextXAlignment        = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus      = false

local PagesFolder = Instance.new("Folder", ContentArea)
PagesFolder.Name = "Pages"

local tabs       = {}
local activeTab  = nil
local uiElementsRegistry = {}

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

    local dot = Instance.new("Frame", switch)
    dot.Size             = UDim2.new(0, 14, 0, 14)
    dot.Position         = toggleState and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel  = 0
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local function updateVisual()
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
        }):Play()
        local targetPos = toggleState and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        TweenService:Create(dot, TweenInfo.new(0.2), { Position = targetPos }):Play()
    end

    switch.MouseButton1Click:Connect(function()
        toggleState = not toggleState
        updateVisual()
        if callback then callback(toggleState) end
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })

    return {
        Set = function(self, val, fireCallback)
            toggleState = (val == true)
            updateVisual()
            if fireCallback and callback then callback(toggleState) end
        end,
        Get = function(self) return toggleState end,
    }
end

local function createSlider(page, tabName, text, minVal, maxVal, step, defaultVal, callback)
    local curVal = math.clamp(defaultVal or minVal, minVal, maxVal)

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 48)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -70, 0, 22)
    titleLbl.Position              = UDim2.new(0, 12, 0, 4)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 12
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local valLbl = Instance.new("TextLabel", card)
    valLbl.Size                  = UDim2.new(0, 50, 0, 22)
    valLbl.Position              = UDim2.new(1, -58, 0, 4)
    valLbl.BackgroundTransparency = 1
    valLbl.Text                  = tostring(curVal)
    valLbl.Font                  = Enum.Font.GothamBold
    valLbl.TextSize              = 12
    valLbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    valLbl.TextXAlignment        = Enum.TextXAlignment.Right

    local track = Instance.new("Frame", card)
    track.Size             = UDim2.new(1, -24, 0, 6)
    track.Position         = UDim2.new(0, 12, 0, 32)
    track.BackgroundColor3 = Color3.fromRGB(42, 46, 58)
    track.BorderSizePixel  = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    local initialRatio = (curVal - minVal) / (maxVal - minVal)
    fill.Size             = UDim2.new(initialRatio, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local sliding = false
    local function updateFromInput(input)
        local relX = math.clamp(input.Position.X - track.AbsolutePosition.X, 0, track.AbsoluteSize.X)
        local ratio = relX / track.AbsoluteSize.X
        local rawVal = minVal + ratio * (maxVal - minVal)
        local steppedVal = math.floor((rawVal / step) + 0.5) * step
        steppedVal = math.clamp(steppedVal, minVal, maxVal)

        curVal = steppedVal
        valLbl.Text = tostring(curVal)
        fill.Size = UDim2.new((curVal - minVal) / (maxVal - minVal), 0, 1, 0)
        if callback then callback(curVal) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            updateFromInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })

    return {
        Set = function(self, val, fireCallback)
            curVal = math.clamp(val, minVal, maxVal)
            valLbl.Text = tostring(curVal)
            fill.Size = UDim2.new((curVal - minVal) / (maxVal - minVal), 0, 1, 0)
            if fireCallback and callback then callback(curVal) end
        end,
        Get = function(self) return curVal end,
    }
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 34)
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
    card.Size             = UDim2.new(1, 0, 0, 32)
    card.BackgroundColor3 = Color3.fromRGB(23, 26, 33)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local stroke = Instance.new("UIStroke", card)
    stroke.Color = Color3.fromRGB(38, 42, 53)
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel", card)
    lbl.Size                  = UDim2.new(1, -20, 1, 0)
    lbl.Position              = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextSize              = 11
    lbl.TextColor3            = Color3.fromRGB(160, 165, 178)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })

    return {
        Set = function(self, newText)
            lbl.Text = newText
        end
    }
end

-- =======================================================
-- СТВОРЕННЯ ВКЛАДОК ТА ЕЛЕМЕНТІВ UI
-- =======================================================
local mainPage = createTab("Головна",  "🏠")
local farmPage = createTab("Автофарм", "⚡")
local shopPage = createTab("Магазин",  "🛒")
local miscPage = createTab("Інше",     "⚙")

local autoLoadToggle, jumpPowerSlider, flySpeedSlider, pickupDistanceSlider
local itemEspToggle, autoSellToggle, autoCandyToggle
local autoBuyToggle, antiAfkToggle, noclipToggle, autoRespawnToggle
local itemToggleControls = {}

local saveCurrentConfig, loadCurrentConfig

-- ││ Головна ││──────────────────────────────────────────
createSection(mainPage, "Головна", "Конфігурація")

autoLoadToggle = createToggle(mainPage, "Головна", "Автозавантаження при старті", shouldAutoLoad, function(value)
    shouldAutoLoad = value
    pcall(function()
        if writefile then writefile(autoLoadFile, tostring(value)) end
    end)
    print("[UA Killer Hub | Config] Автозавантаження збережено: " .. tostring(value))
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

-- ││ Автофарм ││─────────────────────────────────────────
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

pickupDistanceSlider = createSlider(farmPage, "Автофарм", "Дистанція підбору", 2, 8, 0.5, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

itemEspToggle = createToggle(farmPage, "Автофарм", "Увімкнути ESP", _G.ItemESP, function(val)
    manuallyChanged.ItemESP = true
    _G.ItemESP = val
end)

itemFarmToggle = createToggle(farmPage, "Автофарм", "Увімкнути автофарм", _G.ItemFarm, function(value)
    manuallyChanged.ItemFarm = true
    setItemFarmState(value)
end)

createSection(farmPage, "Автофарм", "Фільтр предметів")

local sortedItemKeys = {}
for name, _ in pairs(_G.SelectedItems) do
    table.insert(sortedItemKeys, name)
end
table.sort(sortedItemKeys)

for _, itemName in ipairs(sortedItemKeys) do
    local defaultChecked = _G.SelectedItems[itemName]
    local t = createToggle(farmPage, "Автофарм", itemName, defaultChecked, function(val)
        _G.SelectedItems[itemName] = val
    end)
    itemToggleControls[itemName] = t
end

-- ││ Магазин ││──────────────────────────────────────────
createSection(shopPage, "Магазин", "Торгівля")

autoSellToggle = createToggle(shopPage, "Магазин", "Авто-продаж предметів", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    _G.AutoSell = value
    if value then
        task.spawn(autoSellRoutine)
    else
        closeMerchantDialogue()
    end
end)

autoCandyToggle = createToggle(shopPage, "Магазин", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
    if value then
        task.spawn(submitAllCandies)
    end
end)

autoBuyToggle = createToggle(shopPage, "Магазин", "Авто-купівля", _G.AutoBuy, function(value)
    manuallyChanged.AutoBuy = value
    _G.AutoBuy = value
end)

-- ││ Інше ││────────────────────────────────────────────
createSection(miscPage, "Інше", "Додаткові утиліти")

antiAfkToggle = createToggle(miscPage, "Інше", "Анти-АФК", false, function(value)
    manuallyChanged.AntiAFK = true
    if value then
        if not antiAfkConnection then
            antiAfkConnection = player.Idled:Connect(function()
                pcall(function()
                    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(1)
                    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end)
            end)
        end
    else
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
    end
end)

noclipToggle = createToggle(miscPage, "Інше", "NoClip", false, function(value)
    manuallyChanged.StandaloneNoClip = true
    if value then
        enableNoClip()
    else
        if not flightState then disableNoClip() end
    end
end)

autoRespawnToggle = createToggle(miscPage, "Інше", "Авто-респавн при смерті", false, function(value)
    manuallyChanged.AutoRespawn = true
    if value then
        task.spawn(function()
            while value and task.wait(1) do
                local char = player.Character
                local hum = char and char:FindFirstChild("Humanoid")
                if hum and hum.Health <= 0 then
                    task.wait(2)
                    pcall(function()
                        local rf = game:GetService("ReplicatedStorage"):WaitForChild("Modules", 2)
                        rf = rf and rf:WaitForChild("Net", 2)
                        rf = rf and rf:WaitForChild("RF_Respawn", 2)
                        if rf then rf:InvokeServer() end
                    end)
                end
            end
        end)
    end
end)

-- =======================================================
-- СИСТЕМА КОНФІГУРАЦІЙ ТА JSON
-- =======================================================
saveCurrentConfig = function()
    local cfgData = {
        ItemFarm        = _G.ItemFarm,
        AutoSell        = _G.AutoSell,
        AutoEventCandy  = _G.AutoEventCandy,
        AutoBuy         = _G.AutoBuy,
        ItemESP         = _G.ItemESP,
        AntiAFK         = (antiAfkConnection ~= nil),
        StandaloneNoClip= (noclipConnection ~= nil),
        FlySpeed        = _G.FlySpeed,
        PickupDistance  = _G.PickupDistance,
        JumpPower       = JP_Value,
        SelectedItems   = _G.SelectedItems,
    }

    local success, jsonStr = pcall(function()
        return HttpService:JSONEncode(cfgData)
    end)

    if success and jsonStr then
        pcall(function()
            if writefile then
                writefile(configFile, jsonStr)
                print(string.format("[UA Killer Hub | Config] Збереження: ItemFarm=%s AutoSell=%s AutoCandy=%s",
                    tostring(cfgData.ItemFarm), tostring(cfgData.AutoSell), tostring(cfgData.AutoEventCandy)))
                showNotification("UA Killer Hub", "Конфігурацію збережено успішно!", 3)
            end
        end)
    else
        showNotification("UA Killer Hub", "Помилка кодування JSON!", 3)
    end
end

loadCurrentConfig = function(silent)
    if not (isfile and isfile(configFile)) then
        if not silent then showNotification("UA Killer Hub", "Файл конфігурації не знайдено!", 3) end
        return nil
    end

    local raw = readfile(configFile)
    local success, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if not (success and type(data) == "table") then
        if not silent then showNotification("UA Killer Hub", "Помилка читання JSON!", 3) end
        return nil
    end

    print(string.format("[UA Killer Hub | Config] Завантажено JSON: ItemFarm=%s AutoSell=%s AutoCandy=%s",
        tostring(data.ItemFarm), tostring(data.AutoSell), tostring(data.AutoEventCandy)))

    if data.FlySpeed and flySpeedSlider then flySpeedSlider:Set(data.FlySpeed, true) end
    if data.PickupDistance and pickupDistanceSlider then pickupDistanceSlider:Set(data.PickupDistance, true) end
    if data.JumpPower and jumpPowerSlider then jumpPowerSlider:Set(data.JumpPower, true) end

    if type(data.SelectedItems) == "table" then
        for itemName, state in pairs(data.SelectedItems) do
            _G.SelectedItems[itemName] = state
            if itemToggleControls[itemName] then
                itemToggleControls[itemName]:Set(state, false)
            end
        end
    end

    if not silent then
        if data.ItemFarm ~= nil then setItemFarmState(data.ItemFarm) end
        if data.AutoSell ~= nil and autoSellToggle then autoSellToggle:Set(data.AutoSell, true) end
        if data.AutoEventCandy ~= nil and autoCandyToggle then autoCandyToggle:Set(data.AutoEventCandy, true) end
        if data.ItemESP ~= nil and itemEspToggle then itemEspToggle:Set(data.ItemESP, true) end
        if data.AntiAFK ~= nil and antiAfkToggle then antiAfkToggle:Set(data.AntiAFK, true) end
        if data.StandaloneNoClip ~= nil and noclipToggle then noclipToggle:Set(data.StandaloneNoClip, true) end
        if data.AutoRespawn ~= nil and autoRespawnToggle then autoRespawnToggle:Set(data.AutoRespawn, true) end
        showNotification("UA Killer Hub", "Конфігурацію завантажено вручну!", 3)
    end

    return data
end

-- =======================================================
-- ПОЕТАПНЕ АВТО-ЗАВАНТАЖЕННЯ (15 СЕКУНД ОЧІКУВАННЯ, 1 СЕК МІЖ КРОКАМИ)
-- =======================================================
local AUTOLOAD_DELAY = 15
local AUTOLOAD_STEP  = 1.0

local function runSteppedAutoLoad()
    print(string.format("[UA Killer Hub | AutoLoad] Очікування %d секунд перед запуском...", AUTOLOAD_DELAY))
    showNotification("Auto Load", string.format("Автозавантаження через %d секунд...", AUTOLOAD_DELAY), 4)

    task.wait(AUTOLOAD_DELAY)

    local data = loadCurrentConfig(true)
    if not data then
        print("[UA Killer Hub | AutoLoad] Файл конфігурації відсутній або пошкоджений.")
        return
    end

    print("[UA Killer Hub | AutoLoad] Початок поетапного відновлення перемикачів...")

    local steps = {
        {
            key     = "ItemFarm",
            control = itemFarmToggle,
            label   = "Автофарм",
            activate = function(val)
                setItemFarmState(val)
            end,
        },
        {
            key     = "AutoSell",
            control = autoSellToggle,
            label   = "Авто-продаж",
            activate = function(val)
                _G.AutoSell = (val == true)
                if autoSellToggle then autoSellToggle:Set(_G.AutoSell, false) end
                if _G.AutoSell then task.spawn(autoSellRoutine) end
            end,
        },
        {
            key     = "AutoEventCandy",
            control = autoCandyToggle,
            label   = "Halloween Event",
            activate = function(val)
                _G.AutoEventCandy = (val == true)
                if autoCandyToggle then autoCandyToggle:Set(_G.AutoEventCandy, false) end
                if _G.AutoEventCandy then task.spawn(submitAllCandies) end
            end,
        },
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
            label   = "Анти-АФК",
            activate = function(val)
                if antiAfkToggle then antiAfkToggle:Set((val == true), true) end
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
            key     = "AutoRespawn",
            control = autoRespawnToggle,
            label   = "Авто-респавн",
            activate = function(val)
                if autoRespawnToggle then autoRespawnToggle:Set((val == true), true) end
            end,
        },
    }

    local totalSteps = #steps
    for i, step in ipairs(steps) do
        if manuallyChanged[step.key] then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' пропущено (ручна зміна).", i, totalSteps, step.label))
            task.wait(AUTOLOAD_STEP)
            continue
        end

        local savedVal = data[step.key]
        if savedVal == true then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' увімкнено.", i, totalSteps, step.label))
            showNotification("Auto Load", string.format("(%d/%d) %s", i, totalSteps, step.label), AUTOLOAD_STEP + 0.5)
            step.activate(true)
        else
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' збережено як false, пропускаємо.", i, totalSteps, step.label))
        end

        task.wait(AUTOLOAD_STEP)
    end

    print("[UA Killer Hub | AutoLoad] Поетапне відновлення завершено.")
    showNotification("Auto Load", "✓ Всі налаштування відновлено!", 4)
end

-- =======================================================
-- ВІДКРИТТЯ ІНТЕРФЕЙСУ (GUI з'являється одразу)
-- =======================================================
switchTab("Головна")
print("[UA Killer Hub | Init] Інтерфейс відкрито та готовий до роботи!")

if shouldAutoLoad then
    task.spawn(runSteppedAutoLoad)
end

showNotification("UA Killer Hub", "Завантажено успішно! (RightShift — сховати)", 4)
