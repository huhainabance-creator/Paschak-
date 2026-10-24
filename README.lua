-- UA Killer Hub | YBA — Версія з компактним GUI (зменшено на 1/3 для зручності на телефонах)
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

-- =======================================================
-- БЕЗПЕЧНИЙ CRASH & WALKSPEED BYPASS
-- =======================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
pcall(function()
    local FunctionLibrary = require(
        ReplicatedStorage:WaitForChild("Modules", 2):WaitForChild("FunctionLibrary", 2)
    )
    local OldPcall = FunctionLibrary.pcall
    FunctionLibrary.pcall = function(...)
        local args = { ... }
        if type(args[1]) == "table" and type(args[2]) == "table" then
            if args[1].Key == "Crash" or args[1].Key == "Walkspeed" then
                return true
            end
        end
        return OldPcall(...)
    end
    print("[UA Killer Hub | Init] Crash & Walkspeed Bypass активовано.")
end)

-- =======================================================
-- БАЗОВІ ЗМІННІ
-- =======================================================
_G.ItemFarm         = false
_G.AutoArcade       = false
_G.AutoSell         = false
_G.AutoEventCandy   = false
_G.AutoBuy          = false
_G.AntiAFK          = false
_G.StandaloneNoClip = false

_G.FlySpeed       = 75
_G.PickupDistance = 35
_G.ArcadeSpeed    = 0.25

local selectedItems = {
    ["Mysterious Arrow"]      = true,
    ["Rokakaka"]              = true,
    ["Lucky Arrow"]           = true,
    ["Rib Cage of The Saint's Corpse"] = true,
    ["Pure Rokakaka"]         = true,
    ["DEO's Diary"]           = true,
    ["Steel Ball"]            = true,
    ["Quinton's Glove"]       = true,
    ["Ancient Scroll"]        = true,
    ["Stone Mask"]            = true,
    ["Diamond"]               = true,
    ["Left Arm of The Saint's Corpse"] = true,
    ["Eye of The Saint's Corpse"] = true,
    ["Heart of The Saint's Corpse"] = true,
    ["Pelvis of The Saint's Corpse"] = true
}

local manuallyChanged = {
    ItemFarm         = false,
    AutoArcade       = false,
    AutoSell         = false,
    AutoEventCandy   = false,
    AutoBuy          = false,
    AntiAFK          = false,
    StandaloneNoClip = false,
}

local antiAfkConnection = nil
local noclipConnection  = nil
local JP_Value          = 50
local farmStatusText    = "Очікування..."
local farmThreadActive  = false

local function getSafeGuiParent()
    local coreGui = game:GetService("CoreGui")
    local success, _ = pcall(function()
        local test = coreGui:FindFirstChildOfClass("ScreenGui")
    end)
    if success then return coreGui end
    return player:WaitForChild("PlayerGui", 5) or coreGui
end

local function getCharacter()
    local char = player.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    local hum  = char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function ensureNoClip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if _G.ItemFarm or _G.StandaloneNoClip then
            local char = player.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        else
            if noclipConnection then
                noclipConnection:Disconnect()
                noclipConnection = nil
            end
        end
    end)
end

local function applyJumpPower()
    local char, _, hum = getCharacter()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = JP_Value
    end
end

local function clickElementDirect(elem)
    if not elem then return false end
    local clicked = false

    if elem:IsA("GuiButton") then
        pcall(function()
            for _, conn in ipairs(getconnections(elem.MouseButton1Click)) do
                conn:Fire()
                clicked = true
            end
        end)
        pcall(function()
            for _, conn in ipairs(getconnections(elem.Activated)) do
                conn:Fire()
                clicked = true
            end
        end)
    end

    if not clicked then
        pcall(function()
            local absPos = elem.AbsolutePosition
            local absSz  = elem.AbsoluteSize
            local cx = absPos.X + absSz.X / 2
            local cy = absPos.Y + absSz.Y / 2
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
            clicked = true
        end)
    end
    return clicked
end

-- =======================================================
-- СИСТЕМА ДІАЛОГУ JACK (HALLOWEEN EVENT)
-- =======================================================
local function isGuiElementVisible(elem)
    if not elem then return false end
    if not elem.Visible then return false end
    if elem:IsA("CanvasGroup") and elem.GroupTransparency >= 0.95 then return false end
    local current = elem.Parent
    while current and not current:IsA("ScreenGui") do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end
    return true
end

local function findJackDialogue()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end

    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            for _, desc in ipairs(gui:GetDescendants()) do
                if desc:IsA("TextLabel") and isGuiElementVisible(desc) then
                    local text = desc.Text:lower()
                    if text:find("you now have") and (text:find("point") or text:find("candy") or text:find("candies")) then
                        local dialogueBox = desc.Parent
                        local continueElem = nil

                        for _, sibling in ipairs(dialogueBox:GetDescendants()) do
                            if isGuiElementVisible(sibling) then
                                local sText = (sibling:IsA("TextLabel") or sibling:IsA("TextButton")) and sibling.Text:lower() or ""
                                if sText:find("click to continue") or sText:find("continue") then
                                    continueElem = sibling
                                    break
                                end
                            end
                        end

                        if not continueElem then
                            for _, elem in ipairs(gui:GetDescendants()) do
                                if isGuiElementVisible(elem) and elem ~= desc then
                                    local eText = (elem:IsA("TextLabel") or elem:IsA("TextButton")) and elem.Text:lower() or ""
                                    if eText:find("click to continue") then
                                        continueElem = elem
                                        break
                                    end
                                end
                            end
                        end

                        return {
                            screenGui     = gui,
                            dialogueBox   = dialogueBox,
                            pointsElem    = desc,
                            continueElem  = continueElem,
                            fallbackFrame = dialogueBox
                        }
                    end
                end
            end
        end
    end
    return nil
end

local function clickContinueButton(elem)
    if not elem then return false end
    local clicked = false

    if elem:IsA("GuiButton") then
        pcall(function()
            for _, conn in ipairs(getconnections(elem.MouseButton1Click)) do
                conn:Fire()
                clicked = true
            end
        end)
        pcall(function()
            for _, conn in ipairs(getconnections(elem.Activated)) do
                conn:Fire()
                clicked = true
            end
        end)
    end

    if not clicked then
        pcall(function()
            local absPos = elem.AbsolutePosition
            local absSz  = elem.AbsoluteSize
            local cx = absPos.X + absSz.X / 2
            local cy = absPos.Y + absSz.Y / 2
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
            clicked = true
        end)
    end

    return clicked
end

-- =======================================================
-- СИСТЕМА ДІАЛОГУ ТОРГОВЦЯ (AUTO-SELL)
-- =======================================================
local function getDialogueGui()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end

    for _, name in ipairs({ "DialogueGui", "Dialogue", "NPC_Dialogue", "ChatGui" }) do
        local g = pg:FindFirstChild(name)
        if g and g:IsA("ScreenGui") and g.Enabled then return g end
    end

    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") and g.Enabled then
            if g:FindFirstChild("DialogueFrame", true)
            or g:FindFirstChild("OptionsFrame",  true)
            or g:FindFirstChild("Dialogue",      true)
            or g:FindFirstChild("Speech",        true) then
                return g
            end
        end
    end
    return nil
end

local function findClickableInContainer(container, targetWords)
    if not container then return nil end
    local best = nil

    for _, desc in ipairs(container:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local text = desc.Text:lower()
            for _, word in ipairs(targetWords) do
                if text:find(word:lower(), 1, true) then
                    local p = desc
                    while p and p ~= container and not p:IsA("GuiButton") do
                        p = p.Parent
                    end
                    if p and p:IsA("GuiButton") and isGuiElementVisible(p) then return p end
                    if isGuiElementVisible(desc) then best = best or desc end
                end
            end
        end
    end
    return best
end

local function clickDialogueOption(keywords, timeout)
    timeout = timeout or 2.0
    local deadline = tick() + timeout

    while tick() < deadline do
        local gui = getDialogueGui()
        if gui then
            local elem = findClickableInContainer(gui, keywords)
            if elem then
                task.wait(0.1)
                clickElementDirect(elem)
                return true
            end
        end
        task.wait(0.08)
    end
    return false
end

local function isMerchantDialogueOpen()
    local gui = getDialogueGui()
    if not gui or not gui.Enabled then return false end
    for _, desc in ipairs(gui:GetDescendants()) do
        if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and isGuiElementVisible(desc) then
            local t = desc.Text:lower()
            if t:find("sell") or t:find("merchant") or t:find("buy") or t:find("item") then
                return true
            end
        end
    end
    return false
end

local function closeMerchantDialogue()
    local gui = getDialogueGui()
    if not gui then return end

    local closeWords = { "close", "bye", "cancel", "leave", "nevermind", "nothing", "goodbye" }
    local elem = findClickableInContainer(gui, closeWords)
    if elem then
        clickElementDirect(elem)
        task.wait(0.3)
        return
    end

    pcall(function()
        local closeBtn = gui:FindFirstChild("Close", true)
                      or gui:FindFirstChild("CloseButton", true)
                      or gui:FindFirstChild("Exit", true)
        if closeBtn then clickElementDirect(closeBtn) end
    end)
    task.wait(0.2)
end

local function getMerchantNPC()
    for _, n in ipairs({ "Merchant", "ShiftPmerchant", "Item Merchant", "Seller" }) do
        local npc = workspace:FindFirstChild(n)
        if npc then return npc end
    end
    local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC")
    if npcs then
        for _, n in ipairs({ "Merchant", "ShiftPmerchant", "Item Merchant", "Seller" }) do
            local npc = npcs:FindFirstChild(n)
            if npc then return npc end
        end
        for _, child in ipairs(npcs:GetChildren()) do
            if child.Name:lower():find("merchant") or child.Name:lower():find("seller") then
                return child
            end
        end
    end
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name:lower():find("merchant") and child:FindFirstChild("HumanoidRootPart") then
            return child
        end
    end
    return nil
end

local function getEventNPC()
    for _, name in ipairs({ "Jack, The Cauldron Specter", "Jack", "Cauldron Specter" }) do
        local npc = workspace:FindFirstChild(name)
        if npc then return npc end
    end
    local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC")
    if npcs then
        for _, child in ipairs(npcs:GetChildren()) do
            if child.Name:lower():find("jack") or child.Name:lower():find("cauldron") then
                return child
            end
        end
    end
    for _, child in ipairs(workspace:GetChildren()) do
        if (child.Name:lower():find("jack") or child.Name:lower():find("cauldron"))
        and (child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Head")) then
            return child
        end
    end
    return nil
end

local function clickEventCandyOption()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end

    local candyWords = { "candy", "candies", "halloween", "submit", "give", "exchange", "points" }
    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            for _, desc in ipairs(gui:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and isGuiElementVisible(desc) then
                    local text = desc.Text:lower()
                    for _, word in ipairs(candyWords) do
                        if text:find(word, 1, true) then
                            local btn = desc:IsA("GuiButton") and desc or desc:FindFirstAncestorWhichIsA("GuiButton")
                            if btn then
                                clickElementDirect(btn)
                                return true
                            else
                                clickElementDirect(desc)
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function submitAllCandies()
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local eventNPC = getEventNPC()
    if not remote or not hum or not eventNPC then return false end

    local success = false
    pcall(function()
        remote:FireServer("PromptTriggered", eventNPC)
        local optionFound  = false
        local optionTimeout = tick() + 2.5
        while tick() < optionTimeout and _G.AutoEventCandy do
            if clickEventCandyOption() then optionFound = true break end
            task.wait(0.15)
        end
        if not optionFound then return end

        local pointsFound    = false
        local jackData       = nil
        local pointsTimeout  = tick() + 4.0
        while tick() < pointsTimeout and _G.AutoEventCandy do
            jackData = findJackDialogue()
            if jackData and jackData.hasPoints then pointsFound = true break end
            task.wait(0.15)
        end
        if not pointsFound or not jackData then return end

        task.wait(0.3)
        local clickTarget = jackData.continueElem or jackData.pointsElem or jackData.fallbackFrame
        if clickTarget then
            clickContinueButton(clickTarget)
            local closeTimeout = tick() + 1.5
            local isClosed     = false
            while tick() < closeTimeout do
                task.wait(0.15)
                if not findJackDialogue() then isClosed = true break end
            end
            if isClosed then success = true end
        end
    end)
    return success
end

local function getInventoryItems()
    local items = {}
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and selectedItems[item.Name] then
                table.insert(items, item)
            end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and selectedItems[item.Name] then
                table.insert(items, item)
            end
        end
    end
    return items
end

local function sellItem(itemName)
    local char, _, hum = getCharacter()
    local remote   = char and char:FindFirstChild("RemoteEvent")
    local merchant = getMerchantNPC()
    if not remote or not hum or not merchant then return false end

    local sold = false
    pcall(function()
        local bp = player:FindFirstChild("Backpack")
        local tool = (bp and bp:FindFirstChild(itemName)) or (char and char:FindFirstChild(itemName))
        if tool and tool.Parent == bp then hum:EquipTool(tool) task.wait(0.2) end

        remote:FireServer("PromptTriggered", merchant)
        if not clickDialogueOption({ "sell", "something to sell", "i have something" }, 2.0) then return end
        task.wait(0.2)

        local confirmKeywords = { "yes", "confirm", "sure", "sell for", "deal", "accept" }
        if not clickDialogueOption(confirmKeywords, 2.0) then return end
        task.wait(0.2)

        local continueKeywords = { "click to continue", "continue", "bye", "see ya", "thanks" }
        clickDialogueOption(continueKeywords, 1.5)
        task.wait(0.15)

        local isStillInInventory = false
        local checkBp   = player:FindFirstChild("Backpack")
        local checkChar = player.Character
        if (checkBp and checkBp:FindFirstChild(itemName)) or (checkChar and checkChar:FindFirstChild(itemName)) then
            isStillInInventory = true
        end

        sold = not isStillInInventory
    end)

    task.wait(0.2)
    if isMerchantDialogueOpen() then closeMerchantDialogue() end
    return sold
end

local function sellAllItems()
    local items = getInventoryItems()
    if #items == 0 then return end

    local uniqueNames = {}
    for _, item in ipairs(items) do
        uniqueNames[item.Name] = true
    end

    for itemName, _ in pairs(uniqueNames) do
        if not _G.AutoSell then break end
        local maxAttempts = 15
        local count = 0
        while count < maxAttempts and _G.AutoSell do
            local bp   = player:FindFirstChild("Backpack")
            local char = player.Character
            local hasItem = (bp and bp:FindFirstChild(itemName)) or (char and char:FindFirstChild(itemName))
            if not hasItem then break end

            local sold = sellItem(itemName)
            count = count + 1
            task.wait(0.25)
            if not sold and count > 3 then break end
        end
    end

    if isMerchantDialogueOpen() then closeMerchantDialogue() end
end

-- =======================================================
-- MONHUB GUI (ЗМЕНШЕНИЙ РОЗМІР ~1/3)
-- =======================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "UAKillerHub_MonHub"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = getSafeGuiParent()

local MainFrame = Instance.new("Frame")
MainFrame.Name             = "MainFrame"
MainFrame.Size             = UDim2.new(0, 350, 0, 270)
MainFrame.Position         = UDim2.new(0.5, -175, 0.5, -135)
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
ToastContainer.Size                  = UDim2.new(0, 190, 1, -20)
ToastContainer.Position              = UDim2.new(1, -200, 0, 10)
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
    toast.BackgroundColor3 = Color3.fromRGB(26, 29, 38)
    toast.BorderSizePixel  = 0
    toast.ClipsDescendants = true
    toast.Parent           = ToastContainer

    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", toast)
    s.Color     = Color3.fromRGB(139, 124, 246)
    s.Thickness = 1

    local titleLbl = Instance.new("TextLabel", toast)
    titleLbl.Size                  = UDim2.new(1, -16, 0, 18)
    titleLbl.Position              = UDim2.new(0, 10, 0, 4)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = title
    titleLbl.Font                  = Enum.Font.GothamBold
    titleLbl.TextSize              = 11
    titleLbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local msgLbl = Instance.new("TextLabel", toast)
    msgLbl.Size                  = UDim2.new(1, -16, 0, 20)
    msgLbl.Position              = UDim2.new(0, 10, 0, 22)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text                  = message
    msgLbl.Font                  = Enum.Font.Gotham
    msgLbl.TextSize              = 10
    msgLbl.TextColor3            = Color3.fromRGB(220, 222, 230)
    msgLbl.TextXAlignment        = Enum.TextXAlignment.Left
    msgLbl.TextWrapped           = true

    TweenService:Create(toast,    TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 48) }):Play()
    task.delay(duration, function()
        if not toast or not toast.Parent then return end
        local close = TweenService:Create(toast, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 0) })
        close:Play()
        close.Completed:Connect(function() toast:Destroy() end)
    end)
end

-- =======================================================
-- ВЕРХНЯ ПАНЕЛЬ (TitleBar)
-- =======================================================
local TitleBar = Instance.new("Frame")
TitleBar.Name             = "TitleBar"
TitleBar.Size             = UDim2.new(1, 0, 0, 32)
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
TitleText.Size             = UDim2.new(0, 110, 1, 0)
TitleText.Position         = UDim2.new(0, 10, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text             = "UA Killer Hub"
TitleText.Font             = Enum.Font.GothamBold
TitleText.TextSize         = 12
TitleText.TextColor3       = Color3.fromRGB(240, 242, 245)
TitleText.TextXAlignment   = Enum.TextXAlignment.Left

local Badge = Instance.new("TextLabel", TitleBar)
Badge.Size             = UDim2.new(0, 28, 0, 16)
Badge.Position         = UDim2.new(0, 95, 0.5, -8)
Badge.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
Badge.Text             = "YBA"
Badge.Font             = Enum.Font.GothamBold
Badge.TextSize         = 9
Badge.TextColor3       = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", Badge).CornerRadius = UDim.new(0, 4)

local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size             = UDim2.new(0, 22, 0, 22)
CloseBtn.Position         = UDim2.new(1, -28, 0.5, -11)
CloseBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
CloseBtn.Text             = "✕"
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.TextSize         = 11
CloseBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton", TitleBar)
MinBtn.Size             = UDim2.new(0, 22, 0, 22)
MinBtn.Position         = UDim2.new(1, -54, 0.5, -11)
MinBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
MinBtn.Text             = "—"
MinBtn.Font             = Enum.Font.GothamBold
MinBtn.TextSize         = 11
MinBtn.TextColor3       = Color3.fromRGB(160, 165, 175)
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

-- Перетягування
local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
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
    local targetSize = isMinimized and UDim2.new(0, 350, 0, 32) or UDim2.new(0, 350, 0, 270)
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
Sidebar.Size             = UDim2.new(0, 95, 1, -32)
Sidebar.Position         = UDim2.new(0, 0, 0, 32)
Sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
Sidebar.BorderSizePixel  = 0

local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.Padding             = UDim.new(0, 4)
SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SidebarList.SortOrder           = Enum.SortOrder.LayoutOrder

local SidebarPad = Instance.new("UIPadding", Sidebar)
SidebarPad.PaddingTop   = UDim.new(0, 8)
SidebarPad.PaddingLeft  = UDim.new(0, 4)
SidebarPad.PaddingRight = UDim.new(0, 4)

-- Контентна панель
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Name                  = "ContentArea"
ContentArea.Size                  = UDim2.new(1, -95, 1, -32)
ContentArea.Position              = UDim2.new(0, 95, 0, 32)
ContentArea.BackgroundTransparency = 1

local SearchFrame = Instance.new("Frame", ContentArea)
SearchFrame.Name             = "SearchFrame"
SearchFrame.Size             = UDim2.new(1, -16, 0, 24)
SearchFrame.Position         = UDim2.new(0, 8, 0, 6)
SearchFrame.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
SearchFrame.BorderSizePixel  = 0
Instance.new("UICorner", SearchFrame).CornerRadius = UDim.new(0, 6)

local SearchIcon = Instance.new("TextLabel", SearchFrame)
SearchIcon.Size                  = UDim2.new(0, 20, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text                  = "🔍"
SearchIcon.Font                  = Enum.Font.Gotham
SearchIcon.TextSize              = 11
SearchIcon.TextColor3            = Color3.fromRGB(150, 155, 165)

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size                  = UDim2.new(1, -24, 1, 0)
SearchBox.Position              = UDim2.new(0, 22, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.PlaceholderText       = "Пошук..."
SearchBox.PlaceholderColor3     = Color3.fromRGB(110, 115, 130)
SearchBox.TextColor3            = Color3.fromRGB(240, 242, 245)
SearchBox.Font                  = Enum.Font.Gotham
SearchBox.TextSize              = 11
SearchBox.TextXAlignment        = Enum.TextXAlignment.Left
SearchBox.ClearTextOnFocus      = false

local PagesFolder = Instance.new("Folder", ContentArea)
PagesFolder.Name = "Pages"

local tabs      = {}
local activeTab = nil
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
    btn.Size             = UDim2.new(1, 0, 0, 26)
    btn.BackgroundColor3 = Color3.fromRGB(23, 25, 32)
    btn.Text             = (iconText or "•") .. " " .. tabName
    btn.Font             = Enum.Font.GothamMedium
    btn.TextSize         = 11
    btn.TextColor3       = Color3.fromRGB(150, 155, 165)
    btn.TextXAlignment   = Enum.TextXAlignment.Left
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIPadding", btn).PaddingLeft = UDim.new(0, 8)

    local page = Instance.new("ScrollingFrame", PagesFolder)
    page.Name                = tabName .. "_Page"
    page.Size                = UDim2.new(1, -16, 1, -36)
    page.Position            = UDim2.new(0, 8, 0, 32)
    page.BackgroundTransparency = 1
    page.BorderSizePixel     = 0
    page.ScrollBarThickness  = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(139, 124, 246)
    page.CanvasSize          = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible             = false

    local list = Instance.new("UIListLayout", page)
    list.Padding   = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", page)
    pad.PaddingRight  = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 8)

    tabs[tabName] = { Button = btn, Page = page }
    btn.MouseButton1Click:Connect(function() switchTab(tabName) end)
    return page
end

local function createSection(page, tabName, text)
    local sec = Instance.new("Frame", page)
    sec.Size                  = UDim2.new(1, 0, 0, 20)
    sec.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", sec)
    lbl.Size                  = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text:upper()
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 9
    lbl.TextColor3            = Color3.fromRGB(139, 124, 246)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = sec })
    return sec
end

local function createToggle(page, tabName, text, defaultVal, callback)
    local toggleState = (defaultVal == true)

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 28)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -48, 1, 0)
    titleLbl.Position              = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 11
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local switch = Instance.new("Frame", card)
    switch.Size             = UDim2.new(0, 30, 0, 16)
    switch.Position         = UDim2.new(1, -38, 0.5, -8)
    switch.BackgroundColor3 = toggleState and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58)
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", switch)
    knob.Size             = UDim2.new(0, 12, 0, 12)
    knob.Position         = toggleState and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function setVisual(val, fireCallback)
        toggleState = val
        TweenService:Create(switch, TweenInfo.new(0.2), {
            BackgroundColor3 = val and Color3.fromRGB(139, 124, 246) or Color3.fromRGB(42, 46, 58),
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = val and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6),
        }):Play()
        if fireCallback and callback then callback(val) end
    end

    local clickBtn = Instance.new("TextButton", card)
    clickBtn.Size                   = UDim2.new(1, 0, 1, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text                   = ""
    clickBtn.MouseButton1Click:Connect(function()
        setVisual(not toggleState, true)
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return {
        Frame = card,
        Set   = function(_, val, fire) setVisual(val, fire ~= false) end,
        Get   = function(_) return toggleState end,
    }
end

local function createSlider(page, tabName, text, min, max, step, defaultVal, callback)
    local currentVal = defaultVal or min

    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 38)
    card.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel", card)
    titleLbl.Size                  = UDim2.new(1, -50, 0, 18)
    titleLbl.Position              = UDim2.new(0, 10, 0, 2)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                  = text
    titleLbl.Font                  = Enum.Font.GothamMedium
    titleLbl.TextSize              = 11
    titleLbl.TextColor3            = Color3.fromRGB(230, 233, 240)
    titleLbl.TextXAlignment        = Enum.TextXAlignment.Left

    local valLabel = Instance.new("TextLabel", card)
    valLabel.Size                  = UDim2.new(0, 40, 0, 18)
    valLabel.Position              = UDim2.new(1, -46, 0, 2)
    valLabel.BackgroundTransparency = 1
    valLabel.Text                  = tostring(currentVal)
    valLabel.Font                  = Enum.Font.GothamBold
    valLabel.TextSize              = 10
    valLabel.TextColor3            = Color3.fromRGB(139, 124, 246)
    valLabel.TextXAlignment        = Enum.TextXAlignment.Right

    local bar = Instance.new("Frame", card)
    bar.Size             = UDim2.new(1, -20, 0, 5)
    bar.Position         = UDim2.new(0, 10, 0, 24)
    bar.BackgroundColor3 = Color3.fromRGB(42, 46, 58)
    bar.BorderSizePixel  = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", bar)
    fill.Size             = UDim2.new(math.clamp((currentVal - min) / (max - min), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(139, 124, 246)
    fill.BorderSizePixel  = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local sliding = false
    local function updateFromPos(x)
        local rel     = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local raw     = min + (max - min) * rel
        local stepped = math.floor((raw - min) / step + 0.5) * step + min
        stepped       = math.clamp(stepped, min, max)
        currentVal    = stepped
        valLabel.Text = tostring(stepped)
        fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
        if callback then callback(currentVal) end
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            updateFromPos(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromPos(input.Position.X)
        end
    end)

    local function setValue(val, fireCallback)
        currentVal    = math.clamp(val, min, max)
        valLabel.Text = tostring(currentVal)
        fill.Size     = UDim2.new((currentVal - min) / (max - min), 0, 1, 0)
        if fireCallback and callback then callback(currentVal) end
    end

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return {
        Frame = card,
        Set   = function(_, val, fire) setValue(val, fire ~= false) end,
        Get   = function(_) return currentVal end,
    }
end

local function createButton(page, tabName, text, callback)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 28)
    card.BackgroundColor3 = Color3.fromRGB(38, 42, 53)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local btn = Instance.new("TextButton", card)
    btn.Size                  = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text                  = text
    btn.Font                  = Enum.Font.GothamMedium
    btn.TextSize              = 11
    btn.TextColor3            = Color3.fromRGB(240, 242, 245)

    btn.MouseButton1Click:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(139, 124, 246) }):Play()
        task.delay(0.15, function()
            TweenService:Create(card, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(38, 42, 53) }):Play()
        end)
        if callback then callback() end
    end)

    table.insert(uiElementsRegistry, { Name = text, Page = tabName, Frame = card })
    return card
end

local function createStatusLabel(page, tabName, initialText)
    local card = Instance.new("Frame", page)
    card.Size             = UDim2.new(1, 0, 0, 26)
    card.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    card.BorderSizePixel  = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

    local s = Instance.new("UIStroke", card)
    s.Color     = Color3.fromRGB(42, 46, 58)
    s.Thickness = 1

    local lbl = Instance.new("TextLabel", card)
    lbl.Size                  = UDim2.new(1, -20, 1, 0)
    lbl.Position              = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = initialText
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextSize              = 11
    lbl.TextColor3            = Color3.fromRGB(180, 185, 195)
    lbl.TextXAlignment        = Enum.TextXAlignment.Left

    table.insert(uiElementsRegistry, { Name = initialText, Page = tabName, Frame = card })
    return {
        Frame = card,
        Set   = function(_, t) lbl.Text = t end,
    }
end

-- =======================================================
-- СТВОРЕННЯ СТОРІНОК ТА ВКЛАДОК
-- =======================================================
local mainPage   = createTab("Головна",  "⚙")
local farmPage   = createTab("Автофарм", "⚡")
local itemsPage  = createTab("Предмети", "🎒")
local arcadePage = createTab("Аркада",   "🎰")
local miscPage   = createTab("Різне",    "✨")

-- Посилання на контролери
local itemFarmToggle
local autoSellToggle
local autoEventCandyToggle
local autoArcadeToggle
local autoBuyToggle
local antiAfkToggle
local noclipToggle
local autoLoadToggle

local flySpeedSlider
local pickupDistanceSlider
local jumpPowerSlider
local arcadeSpeedSlider

local itemToggles = {}

local saveCurrentConfig
local loadCurrentConfig

-- ── Головна ──────────────────────────────────────────────
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

pickupDistanceSlider = createSlider(farmPage, "Автофарм", "Дистанція збору", 10, 80, 1, _G.PickupDistance, function(val)
    _G.PickupDistance = val
end)

createSection(farmPage, "Автофарм", "Автоматизація")

local function startFarmThread()
    if farmThreadActive then return end
    farmThreadActive = true

    task.spawn(function()
        print("[UA Killer Hub | Farm] Потік фарму запущено.")
        while _G.ItemFarm do
            local char, root, hum = getCharacter()
            if not char or not root or not hum then
                farmStatusText = "Очікування персонажа..."
                task.wait(0.5)
            else
                ensureNoClip()
                local itemFolder = workspace:FindFirstChild("Item_Spawns") or workspace:FindFirstChild("Items")
                local targetItem = nil
                local targetDist = math.huge

                if itemFolder then
                    for _, obj in ipairs(itemFolder:GetDescendants()) do
                        if not _G.ItemFarm then break end
                        if obj:IsA("TouchTransmitter") and obj.Parent then
                            local itemPart = obj.Parent
                            local itemName = itemPart.Name
                            if itemPart.Parent and itemPart.Parent:IsA("Model") then
                                itemName = itemPart.Parent.Name
                            end

                            if selectedItems[itemName] then
                                local dist = (root.Position - itemPart.Position).Magnitude
                                if dist < targetDist then
                                    targetDist = dist
                                    targetItem = itemPart
                                end
                            end
                        end
                    end
                end

                if targetItem and targetItem.Parent and _G.ItemFarm then
                    local targetPos = targetItem.Position
                    farmStatusText = "Політ до: " .. targetItem.Name
                    while _G.ItemFarm and targetItem and targetItem.Parent do
                        local c, r, _ = getCharacter()
                        if not c or not r then break end
                        local dist = (r.Position - targetItem.Position).Magnitude
                        if dist <= _G.PickupDistance then
                            firetouchinterest(r, targetItem, 0)
                            task.wait(0.05)
                            firetouchinterest(r, targetItem, 1)
                            task.wait(0.1)
                            break
                        end
                        local dir = (targetItem.Position - r.Position).Unit
                        r.AssemblyLinearVelocity = dir * _G.FlySpeed
                        task.wait(0.03)
                    end
                else
                    farmStatusText = "Пошук предметів..."
                    task.wait(0.5)
                end
            end
            task.wait(0.1)
        end
        farmThreadActive = false
        farmStatusText = "Вимкнено"
        print("[UA Killer Hub | Farm] Потік фарму завершено.")
    end)
end

local function setItemFarmState(enabled)
    manuallyChanged.ItemFarm = true
    _G.ItemFarm = enabled
    print(string.format("[UA Killer Hub | Controller] setItemFarmState -> %s", tostring(enabled)))

    if itemFarmToggle and itemFarmToggle:Get() ~= enabled then
        itemFarmToggle:Set(enabled, false)
    end

    if enabled then
        ensureNoClip()
        startFarmThread()
    else
        farmStatusText = "Вимкнено"
        if not _G.StandaloneNoClip and noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end
end

itemFarmToggle = createToggle(farmPage, "Автофарм", "Фарм предметів (Item Farm)", _G.ItemFarm, function(value)
    setItemFarmState(value)
end)

autoSellToggle = createToggle(farmPage, "Автофарм", "Авто-продаж торговцю (Auto Sell)", _G.AutoSell, function(value)
    manuallyChanged.AutoSell = true
    _G.AutoSell = value
    if value then
        task.spawn(function()
            while _G.AutoSell do
                sellAllItems()
                task.wait(4.0)
            end
        end)
    end
end)

autoEventCandyToggle = createToggle(farmPage, "Автофарм", "Авто-здача конфет (Halloween Event)", _G.AutoEventCandy, function(value)
    manuallyChanged.AutoEventCandy = true
    _G.AutoEventCandy = value
    if value then
        task.spawn(function()
            while _G.AutoEventCandy do
                submitAllCandies()
                task.wait(3.5)
            end
        end)
    end
end)

-- ── Предмети ─────────────────────────────────────────────
createSection(itemsPage, "Предмети", "Вибір предметів для збору")

for itemName, enabled in pairs(selectedItems) do
    local toggle = createToggle(itemsPage, "Предмети", itemName, enabled, function(val)
        selectedItems[itemName] = val
    end)
    itemToggles[itemName] = toggle
end

-- ── Аркада ───────────────────────────────────────────────
createSection(arcadePage, "Аркада", "Авто-Аркада")

arcadeSpeedSlider = createSlider(arcadePage, "Аркада", "Затримка прокруту (сек)", 0.1, 1.5, 0.05, _G.ArcadeSpeed, function(val)
    _G.ArcadeSpeed = val
end)

autoArcadeToggle = createToggle(arcadePage, "Аркада", "Авто-крутка аркади", _G.AutoArcade, function(value)
    manuallyChanged.AutoArcade = true
    _G.AutoArcade = value
    if value then
        task.spawn(function()
            while _G.AutoArcade do
                local char   = player.Character
                local remote = char and char:FindFirstChild("RemoteFunction")
                if remote then
                    pcall(function() remote:InvokeServer("Arcade", "Roll") end)
                end
                task.wait(_G.ArcadeSpeed + 0.1)
            end
        end)
    end
end)

autoBuyToggle = createToggle(arcadePage, "Аркада", "Авто-купівля Lucky Arrow", _G.AutoBuy, function(value)
    manuallyChanged.AutoBuy = true
    _G.AutoBuy = value
    if value then
        task.spawn(function()
            while _G.AutoBuy do
                local char   = player.Character
                local remote = char and char:FindFirstChild("RemoteEvent")
                if remote then remote:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" }) end
                task.wait(2.5 + math.random() * 1.5)
            end
        end)
    end
end)

-- ── Різне ────────────────────────────────────────────────
createSection(miscPage, "Різне", "Персонаж та безпека")

antiAfkToggle = createToggle(miscPage, "Різне", "Anti-AFK", _G.AntiAFK, function(value)
    manuallyChanged.AntiAFK = true
    _G.AntiAFK = value
    if antiAfkConnection then antiAfkConnection:Disconnect() antiAfkConnection = nil end
    if value then
        antiAfkConnection = player.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

noclipToggle = createToggle(miscPage, "Різне", "NoClip (Завжди активний)", _G.StandaloneNoClip, function(value)
    manuallyChanged.StandaloneNoClip = true
    _G.StandaloneNoClip = value
    if value then ensureNoClip()
    elseif not _G.ItemFarm and noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end)

-- =======================================================
-- СИСТЕМА ЗБЕРЕЖЕННЯ / ЗАВАНТАЖЕННЯ КОНФІГУРАЦІЇ
-- =======================================================
saveCurrentConfig = function()
    local configData = {
        FlySpeed         = _G.FlySpeed,
        PickupDistance   = _G.PickupDistance,
        JumpPower        = JP_Value,
        ArcadeSpeed      = _G.ArcadeSpeed,
        ItemFarm         = _G.ItemFarm,
        AutoArcade       = _G.AutoArcade,
        AutoSell         = _G.AutoSell,
        AutoEventCandy   = _G.AutoEventCandy,
        AutoBuy          = _G.AutoBuy,
        AntiAFK          = _G.AntiAFK,
        StandaloneNoClip = _G.StandaloneNoClip,
        SelectedItems    = selectedItems,
    }

    local ok, encoded = pcall(function() return HttpService:JSONEncode(configData) end)
    if not ok then
        showNotification("Конфіг", "Помилка серіалізації JSON!", 3)
        return
    end

    pcall(function()
        if writefile then
            if not isfolder("UAKillerHub") and makefolder then makefolder("UAKillerHub") end
            writefile(configFile, encoded)
        end
    end)
    showNotification("Конфіг", "Налаштування успішно збережено!", 3)
end

loadCurrentConfig = function(isAutoLoad)
    local raw = nil
    pcall(function()
        if isfile and isfile(configFile) and readfile then raw = readfile(configFile) end
    end)
    if not raw then
        if not isAutoLoad then showNotification("Конфіг", "Файл конфігурації не знайдено!", 3) end
        return nil
    end

    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then
        if not isAutoLoad then showNotification("Конфіг", "Помилка читання JSON!", 3) end
        return nil
    end

    -- Відновлення слайдерів
    if data.FlySpeed         then _G.FlySpeed       = data.FlySpeed         if flySpeedSlider       then flySpeedSlider:Set(data.FlySpeed, false) end end
    if data.PickupDistance   then _G.PickupDistance = data.PickupDistance   if pickupDistanceSlider then pickupDistanceSlider:Set(data.PickupDistance, false) end end
    if data.JumpPower        then JP_Value          = data.JumpPower        if jumpPowerSlider      then jumpPowerSlider:Set(data.JumpPower, false) applyJumpPower() end end
    if data.ArcadeSpeed      then _G.ArcadeSpeed    = data.ArcadeSpeed      if arcadeSpeedSlider    then arcadeSpeedSlider:Set(data.ArcadeSpeed, false) end end

    -- Відновлення списку предметів
    if type(data.SelectedItems) == "table" then
        for k, v in pairs(data.SelectedItems) do
            selectedItems[k] = v
            if itemToggles[k] then itemToggles[k]:Set(v, false) end
        end
    end

    -- Якщо ручне завантаження — відновлюємо одразу все
    if not isAutoLoad then
        if data.ItemFarm         ~= nil then setItemFarmState(data.ItemFarm) end
        if data.AutoArcade       ~= nil and autoArcadeToggle       then autoArcadeToggle:Set(data.AutoArcade, true) end
        if data.AutoSell         ~= nil and autoSellToggle         then autoSellToggle:Set(data.AutoSell, true) end
        if data.AutoEventCandy   ~= nil and autoEventCandyToggle   then autoEventCandyToggle:Set(data.AutoEventCandy, true) end
        if data.AutoBuy          ~= nil and autoBuyToggle          then autoBuyToggle:Set(data.AutoBuy, true) end
        if data.AntiAFK          ~= nil and antiAfkToggle          then antiAfkToggle:Set(data.AntiAFK, true) end
        if data.StandaloneNoClip ~= nil and noclipToggle           then noclipToggle:Set(data.StandaloneNoClip, true) end
        showNotification("Конфіг", "Конфігурацію завантажено вручну!", 3)
    end

    return data
end

-- =======================================================
-- ПОЕТАПНЕ АВТОЗАВАНТАЖЕННЯ (Auto Load з очікуванням 15с)
-- =======================================================
pcall(function()
    if isfile and isfile(autoLoadFile) and readfile then
        local content = readfile(autoLoadFile)
        shouldAutoLoad = (content:lower():find("true") ~= nil)
    end
end)

local function runSteppedAutoLoad()
    print("[UA Killer Hub | AutoLoad] Очікування 15 секунд перед відновленням налаштувань...")
    showNotification("Auto Load", "Очікування 15 сек. перед застосуванням конфігурації...", 4)

    local AUTOLOAD_DELAY = 15
    local AUTOLOAD_STEP  = 1.0

    task.wait(AUTOLOAD_DELAY)

    if not shouldAutoLoad then
        print("[UA Killer Hub | AutoLoad] AutoLoad вимкнено під час очікування, скасування.")
        return
    end

    print("[UA Killer Hub | AutoLoad] Початок поетапного завантаження...")
    showNotification("Auto Load", "Починаємо відновлення налаштувань...", 3)

    local data = loadCurrentConfig(true)
    if not data then
        print("[UA Killer Hub | AutoLoad] Дані конфігу відсутні, автозавантаження зупинено.")
        return
    end

    local restorationSteps = {
        {
            key      = "ItemFarm",
            label    = "Item Farm",
            activate = function(val) setItemFarmState(val) end,
        },
        {
            key      = "AutoSell",
            label    = "Auto Sell",
            activate = function(val) if autoSellToggle then autoSellToggle:Set(val, true) end end,
        },
        {
            key      = "AutoEventCandy",
            label    = "Auto Candy (Halloween)",
            activate = function(val) if autoEventCandyToggle then autoEventCandyToggle:Set(val, true) end end,
        },
        {
            key      = "AutoArcade",
            label    = "Auto Arcade",
            activate = function(val) if autoArcadeToggle then autoArcadeToggle:Set(val, true) end end,
        },
        {
            key      = "AutoBuy",
            label    = "Auto Buy",
            activate = function(val) if autoBuyToggle then autoBuyToggle:Set(val, true) end end,
        },
        {
            key      = "AntiAFK",
            label    = "Anti-AFK",
            activate = function(val) if antiAfkToggle then antiAfkToggle:Set(val, true) end end,
        },
        {
            key      = "StandaloneNoClip",
            label    = "NoClip",
            activate = function(val) if noclipToggle then noclipToggle:Set(val, true) end end,
        },
    }

    local totalSteps = #restorationSteps
    for i, step in ipairs(restorationSteps) do
        if not shouldAutoLoad then break end

        if manuallyChanged[step.key] then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — '%s' змінено вручну користувачем, пропускаємо.", i, totalSteps, step.label))
        elseif data[step.key] == true then
            print(string.format("[UA Killer Hub | AutoLoad] Крок %d/%d — Вмикаємо '%s'...", i, totalSteps, step.label))
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
