--[[
  Smart Freecam & ESP Hub (Full Version - Modified & Updated)
  - 실행 시 초기 로딩 알림/소리 제거
  - Infinite Yield / DEX Explorer 실행 시 모달 창
  - 락온 (자연스러운 에임) 적중률 및 이동 예측 보정 적용
  - 락온 거리 조절 슬라이더 및 초기화 버튼 추가 (기본 1000m)
  - ESP 아래 '락온 무지개 ESP' 토글 추가 (기본 OFF 설정)
  - Status Bar UI: HP (락온시에만 표시) / 핑 / Smart Hub 구성
  - Key Bind Controls: 실행 시 락온 외 나머지 기능 기본 OFF (비활성화 알림 안 뜸)
  - UI 메뉴 기본 크기: 크게 (Large)
  - [수정] 프리캠 모드 마우스 시점 회동(화면 이동) 기능 복구
  - [수정] PgDn 키 (카메라를 내 위치로 이동) 단축키 로직 구현 완료
  - [수정] ESP 닉네임 및 락온 무지개 ESP 표시 위치(Head Adornee & Offset) 보정
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

local freecamEnabled = false
local espEnabled = false
local namesEnabled = false
local skyboxDeleted = false
local tpModeActive = false
local showKillFeed = true
local isKoreanLang = true

local isHeadlessEnabled = false
local legitLockEnabled = false -- 락온 (자연스러운 에임) 변수
local lockOnEspEnabled = false -- 락온 무지개 ESP 활성화 변수 (기본 OFF)
local maxLockOnDistance = 1000 -- 락온 최대 거리 변수 (기본 1000m)

-- 개별 키 및 기능 활성화/비활성화 제어 테이블 (실행 시 락온만 true, 나머지 false)
local keyStates = {
    LockOn = true,          -- 락온 기능 (마우스 휠클릭)
    End = false,            -- End 클릭 (프리캠 토글)
    EndLong = false,        -- End 길게 누르기 (FOV 초기화)
    PgDn = false,           -- PgDn 클릭 (카메라 이동)
    PgDnLong = false,       -- PgDn 길게 누르기 (공간 도약)
    RightBracket = false,   -- ] 클릭 (머리 트래킹)
    RightBracketLong = false-- ] 길게 누르기 (TP 모드)
}

-- Watermark (상태 바) UI 표시 제어 변수 (HP / 핑 / Smart Hub)
local showHpBlock = true
local showPingBlock = true
local showHubBlock = true
local showWatermarkUI = true

-- 알림 제어 상태 변수
local leftNotifyEnabled = false
local rightNotifyEnabled = true

-- 착용 중인 뿔 및 악세서리 아이템 저장 테이블
local equippedHorns = {}

-- 원본 장신구 보관용 폴더 및 상태 변수
local removedAccessoriesFolder = nil
local accessoriesDeletedEnabled = false

-- 락온 및 헤드 트래킹 상태 변수
local lockOnActive = false
local lockOnTarget = nil
local headLockActive = false
local originalNeckC0 = nil
local currentNeck = nil
local smoothNeckC0 = nil

-- 핑 및 블록 모드 상태 변수
local pingModeActive = false
local blockModeActive = false
local activePings = {}
local activeBlocks = {}
local undoStack = {}
local redoStack = {}

-- 블록 하이라이트
local blockHoverHighlight = Instance.new("Highlight")
blockHoverHighlight.Name = "BlockHoverHighlight"
blockHoverHighlight.FillTransparency = 1
blockHoverHighlight.OutlineTransparency = 0
blockHoverHighlight.Parent = nil

-- 환경 복구용 변수
local skyboxBackup = Instance.new("Folder")
skyboxBackup.Name = "SkyboxBackup"
local originalClockTime = 14
local originalTimeOfDay = "14:00:00"
local originalLatitude = 23.5
local originalFogEnd = Lighting.FogEnd
local originalAtmosphereDensity = Lighting:FindFirstChildOfClass("Atmosphere") and Lighting:FindFirstChildOfClass("Atmosphere").Density or 0
local originalSpecular = Lighting.EnvironmentSpecularScale
local originalDiffuse = Lighting.EnvironmentDiffuseScale

local position = Vector3.zero
local velocity = Vector3.zero
local yaw = 0
local pitch = 0
local smoothYaw = 0
local smoothPitch = 0

local targetFov = 70
local normalFov = 70

local sensitivity = 0.08
local baseSpeed = 50
local lerpSpeed = 12
local acceleration = 6
local fovLerpSpeed = 10

local lastFreecamPosition = nil
local lastFreecamYaw = nil
local lastFreecamPitch = nil

local ACTION_NAME = "FREECAM_BLOCK_MOVEMENT"
local espObjects = {}

-- 입력 상태 구조체
local inputState = {
    End = false,
    Mb3 = false,
    Del = false,
    RightBracket = false,
    PgDn = false
}

-- 세션 시간 측정용
local startTime = os.clock()

local function playSound(soundId, volume, pitch)
    task.spawn(function()
        local success, sound = pcall(function()
            local s = Instance.new("Sound")
            s.SoundId = "rbxassetid://" .. tostring(soundId)
            s.Volume = (volume or 0.6) * 3.5
            s.PlaybackSpeed = pitch or 1
            s.Parent = SoundService
            s:Play()
            return s
        end)
        if success and sound then
            sound.Ended:Connect(function() sound:Destroy() end)
            task.wait(5)
            if sound and sound.Parent then sound:Destroy() end
        end
    end)
end

-- -------------------------------------------------------------
-- UI 빌드 (Neverlose 라이브러리)
-- -------------------------------------------------------------
local NeverLose = loadstring(game:HttpGet("https://raw.githubusercontent.com/4lpaca-pin/NeverLose/refs/heads/main/source.luau"))()

local Notification = NeverLose:CreateNotification()
local Logging = NeverLose:CreateLogger()

-- 기본 창 열기/닫기 단축키: Delete
local minimizeKeybind = Enum.KeyCode.Delete

local window = NeverLose:CreateWindow({
    Logo = NeverLose.GlobalLogo,
    Name = "Hub",
    Content = "0xxxna1",
    Size = NeverLose.Scales.Large, -- 실행 시 기본 메뉴 크기 크게 설정
    ConfigFolder = "FreecamHubConfig",
    Enable3DRenderer = false,
    Keybind = "Delete",
    AutoShow = false -- 실행 시 자동으로 켜지는 현상 방지
})

-- 실행 시 자동 켜짐 방지 보장
if window then
    if window.SetInterface then
        window:SetInterface(false)
    end
    if window.ToggleInterface and window.Enabled then
        window:ToggleInterface()
    end
end

local Watermark = window:Watermark()
Watermark:SetRender(true)

-- Watermark 구성: [ HP ] / [ 핑 ] / [ Smart Hub ]
local hpBlock = Watermark:AddBlock("heart-rate", "HP: - / -")
local pingBlock = Watermark:AddBlock("chart-four-vertical-bars", "0 MS")
local UITogg = Watermark:AddBlock("cube-vertexes", "Smart Hub")

local function setBlockVisible(block, vis)
    if not block then return end
    pcall(function()
        if type(block) == "table" then
            if block.SetVisible then block:SetVisible(vis) end
            if block.Frame then block.Frame.Visible = vis end
            if block.Instance then block.Instance.Visible = vis end
            if block.Container then block.Container.Visible = vis end
            if block.Label then block.Label.Visible = vis end
            if block.Text then block.Text.Visible = vis end
        end
        if block.Visible ~= nil then block.Visible = vis end
    end)
end

local function updateWatermarkVisibility()
    Watermark:SetRender(showWatermarkUI)
    
    -- HP는 showHpBlock, showWatermarkUI가 true이고 '락온(lockOnActive)' 중일 때만 표시
    setBlockVisible(hpBlock, showHpBlock and showWatermarkUI and lockOnActive)
    setBlockVisible(pingBlock, showPingBlock and showWatermarkUI)
    setBlockVisible(UITogg, showHubBlock and showWatermarkUI)
end

UITogg:Input(function()
    window:ToggleInterface()
end)

-- 핑 실시간 업데이트 루프
task.spawn(function()
    while true do
        task.wait(1)
        if showPingBlock and showWatermarkUI and pingBlock then
            local pingVal = math.round(player:GetNetworkPing() * 1000)
            pingBlock:SetText(tostring(pingVal) .. " MS")
        end
    end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FreecamNotifyGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local rightSideGui = Instance.new("Frame")
rightSideGui.Name = "RightSideGuideFrame"
rightSideGui.Size = UDim2.new(0, 280, 0, 220)
rightSideGui.Position = UDim2.new(1, -300, 0.5, -110)
rightSideGui.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
rightSideGui.BackgroundTransparency = 0.2
rightSideGui.Visible = false
rightSideGui.Parent = screenGui
local sideCorner = Instance.new("UICorner") sideCorner.CornerRadius = UDim.new(0, 6) sideCorner.Parent = rightSideGui
local sideStroke = Instance.new("UIStroke") sideStroke.Thickness = 1.5 sideStroke.Color = Color3.fromRGB(255, 170, 0) sideStroke.Parent = rightSideGui

local sideText = Instance.new("TextLabel")
sideText.Size = UDim2.new(1, -20, 1, -20)
sideText.Position = UDim2.new(0, 10, 0, 10)
sideText.BackgroundTransparency = 1
sideText.TextColor3 = Color3.fromRGB(255, 255, 255)
sideText.TextSize = 13
sideText.Font = Enum.Font.GothamMedium
sideText.TextXAlignment = Enum.TextXAlignment.Left
sideText.TextYAlignment = Enum.TextYAlignment.Top
sideText.TextWrapped = true
sideText.Parent = rightSideGui

local function showNotification(messageKr, messageEn)
    local msg = isKoreanLang and messageKr or (messageEn or messageKr)
    if leftNotifyEnabled then
        Logging.new("info", msg, 5)
    end
    if rightNotifyEnabled then
        local notif = Notification.new({
            Title = "System Notification",
            Content = msg,
            Duration = 3,
            Position = UDim2.new(1, -20, 1, -20),
            AnchorPoint = Vector2.new(1, 1)
        })
        if notif and type(notif) == "table" and notif.Frame then
            notif.Frame.Position = UDim2.new(1, -20, 1, -20)
            notif.Frame.AnchorPoint = Vector2.new(1, 1)
        end
    end
end

-- -------------------------------------------------------------
-- 고급형 세련된 실시간 킬 피드 UI
-- -------------------------------------------------------------
local realtimeKillFeedGui = Instance.new("ScreenGui")
realtimeKillFeedGui.Name = "RealtimeKillFeedGui"
realtimeKillFeedGui.ResetOnSpawn = false
realtimeKillFeedGui.IgnoreGuiInset = true
realtimeKillFeedGui.Parent = player:WaitForChild("PlayerGui")

local killFeedContainer = Instance.new("Frame")
killFeedContainer.Name = "KillFeedContainer"
killFeedContainer.Size = UDim2.new(0, 260, 0, 300)
killFeedContainer.Position = UDim2.new(1, -280, 1, -20)
killFeedContainer.AnchorPoint = Vector2.new(0, 1)
killFeedContainer.BackgroundTransparency = 1
killFeedContainer.Visible = showKillFeed
killFeedContainer.Parent = realtimeKillFeedGui

local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Padding = UDim.new(0, 6)
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
feedLayout.Parent = killFeedContainer

local function addKillFeedMessage(victimName, distStr)
    if not showKillFeed then return end

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 32)
    card.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    card.BackgroundTransparency = 0.15
    card.ClipsDescendants = true
    card.Parent = killFeedContainer

    local cCorner = Instance.new("UICorner")
    cCorner.CornerRadius = UDim.new(0, 8)
    cCorner.Parent = card

    local cStroke = Instance.new("UIStroke")
    cStroke.Thickness = 1
    cStroke.Transparency = 0.7
    cStroke.Color = Color3.fromRGB(255, 60, 60)
    cStroke.Parent = card

    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(0, 3, 1, -8)
    accentLine.Position = UDim2.new(0, 4, 0.5, 0)
    accentLine.AnchorPoint = Vector2.new(0, 0.5)
    accentLine.BackgroundColor3 = Color3.fromRGB(255, 75, 75)
    accentLine.BorderSizePixel = 0
    accentLine.Parent = card

    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(1, 0)
    accentCorner.Parent = accentLine

    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -16, 1, 0)
    contentFrame.Position = UDim2.new(0, 12, 0, 0)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -55, 1, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Text = "☠️ " .. victimName
    nameLabel.Parent = contentFrame

    local distBadge = Instance.new("Frame")
    distBadge.Size = UDim2.new(0, 48, 0, 18)
    distBadge.Position = UDim2.new(1, -50, 0.5, -9)
    distBadge.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    distBadge.Parent = contentFrame

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 6)
    bCorner.Parent = distBadge

    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(1, 0, 1, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(255, 180, 80)
    distLabel.TextSize = 10
    distLabel.Font = Enum.Font.GothamBold
    distLabel.Text = distStr or "10m"
    distLabel.Parent = distBadge

    card.Position = UDim2.new(0, 50, 0, 0)
    card.BackgroundTransparency = 1
    TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 0.15
    }):Play()

    local children = killFeedContainer:GetChildren()
    local count = 0
    for _, child in ipairs(children) do
        if child:IsA("Frame") then count = count + 1 end
    end
    if count > 6 then
        for _, child in ipairs(children) do
            if child:IsA("Frame") then child:Destroy() break end
        end
    end

    task.delay(8.0, function()
        if card and card.Parent then
            local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            TweenService:Create(card, fadeInfo, {BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 0)}):Play()
            for _, desc in ipairs(card:GetDescendants()) do
                if desc:IsA("TextLabel") then
                    TweenService:Create(desc, fadeInfo, {TextTransparency = 1}):Play()
                elseif desc:IsA("Frame") then
                    TweenService:Create(desc, fadeInfo, {BackgroundTransparency = 1}):Play()
                elseif desc:IsA("UIStroke") then
                    TweenService:Create(desc, fadeInfo, {Transparency = 1}):Play()
                end
            end
            task.wait(0.4)
            if card and card.Parent then card:Destroy() end
        end
    end)
end

local function getFormattedName(p)
    local dName = p.DisplayName
    local rName = p.Name
    if dName == rName then
        return dName
    else
        return dName .. " (@" .. rName .. ")"
    end
end

local function monitorPlayerDeath(p)
    if p == player then return end
    local function onChar(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hum.Died:Connect(function()
                local nameStr = p.Name
                local myChar = player.Character
                local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
                local targetHrp = char:FindFirstChild("HumanoidRootPart")
                local distStr = "15m"
                if myHrp and targetHrp then
                    distStr = string.format("%dm", math.floor((myHrp.Position - targetHrp.Position).Magnitude))
                end
                addKillFeedMessage(nameStr, distStr)
            end)
        end
    end
    if p.Character then onChar(p.Character) end
    p.CharacterAdded:Connect(onChar)
end

for _, p in ipairs(Players:GetPlayers()) do
    monitorPlayerDeath(p)
end
Players.PlayerAdded:Connect(monitorPlayerDeath)

-- 커스텀 아이템 카탈로그 (순서: 뿔 -> 날개 -> 모자)
local hornCatalog = {
    [1] = {
        rawNameKr = "뿔 (Horns)",
        rawNameEn = "Horns",
        type = "Accessory",
        skins = {
            ["보라뿔"] = 76479271580913,
            ["빨간불"] = 215718515,
            ["파란불"] = 74891470
        }
    },
    [2] = {
        rawNameKr = "날개 (Angel & Golden Wings)",
        rawNameEn = "Wings",
        type = "Wing",
        skins = {
            ["천사날개"] = 192557913,
            ["황금날개"] = 417456127
        }
    },
    [3] = {
        rawNameKr = "모자 (Hats)",
        rawNameEn = "Hats",
        type = "Accessory",
        skins = {
            ["발키리"] = 1365767,
            ["페도라"] = 119916949
        }
    }
}
local activeAppliedItems = {}

local function applyHornToCharacter(char, itemId, itemType)
    if not char then return false end

    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if not head then return false end

    local existing = char:FindFirstChild("CustomHorn_" .. itemId)
    if existing then existing:Destroy() end

    local success, fetched = pcall(function()
        return game:GetObjects("rbxassetid://" .. tostring(itemId))
    end)

    if success and fetched and #fetched > 0 then
        local acc = fetched[1]
        acc.Name = "CustomHorn_" .. itemId
        
        if acc:IsA("Accessory") or acc:IsA("Accoutrement") then
            local handle = acc:FindFirstChild("Handle")
            if handle then
                handle.CanCollide = false
                local handleAttachment = handle:FindFirstChildOfClass("Attachment")
                local targetAttachment = nil
                
                if handleAttachment then
                    targetAttachment = char:FindFirstChild(handleAttachment.Name, true)
                end

                if not targetAttachment and itemType == "Wing" then
                    targetAttachment = (torso and (torso:FindFirstChild("BodyBackAttachment") or torso:FindFirstChild("BackAttachment")))
                end

                acc.Parent = char

                if targetAttachment and handleAttachment then
                    local weld = Instance.new("Weld")
                    weld.Name = "AccessoryWeld"
                    weld.Part0 = handle
                    weld.Part1 = targetAttachment.Parent
                    weld.C0 = handleAttachment.CFrame
                    weld.C1 = targetAttachment.CFrame
                    weld.Parent = handle
                else
                    local targetPart = (itemType == "Wing" and torso) or head
                    local weld = Instance.new("Weld")
                    weld.Name = "AccessoryWeld"
                    weld.Part0 = handle
                    weld.Part1 = targetPart
                    weld.C0 = CFrame.new(0, 0, 0)
                    weld.C1 = (itemType == "Wing") and CFrame.new(0, 0, -0.15) or CFrame.new(0, 0, 0)
                    weld.Parent = handle
                end
            else
                acc.Parent = char
            end
        else
            if itemType == "Wing" and torso then
                if acc:IsA("BasePart") then
                    acc.CanCollide = false
                    acc.CFrame = torso.CFrame
                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = acc
                    weld.Part1 = torso
                    weld.Parent = acc
                end
            else
                if acc:IsA("BasePart") then
                    acc.CanCollide = false
                    acc.CFrame = head.CFrame
                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = acc
                    weld.Part1 = head
                    weld.Parent = acc
                end
            end
            acc.Parent = char
        end
        equippedHorns[itemId] = acc
        return true
    end
    return false
end

local function applyAllActiveItems(char)
    task.wait(0.2)
    for itemId, itemData in pairs(activeAppliedItems) do
        applyHornToCharacter(char, itemId, itemData.type)
    end
end

local function applyHeadless(char)
    if not isHeadlessEnabled then return end
    if not char then return end
    local head = char:FindFirstChild("Head")
    if head then
        head.Transparency = 1
        local face = head:FindFirstChildOfClass("Decal")
        if face then face.Transparency = 1 end
    end
end

local function removeHeadless(char)
    if not char then return end
    local head = char and char:FindFirstChild("Head")
    if head then
        head.Transparency = 0
        local face = head:FindFirstChildOfClass("Decal")
        if face then face.Transparency = 0 end
    end
end

local function removeLockOnMarker()
    if lockOnTarget and lockOnTarget.Character then
        local highlight = lockOnTarget.Character:FindFirstChild("LockOnHighlight") 
        if highlight then highlight:Destroy() end
    end
end

local function createLockOnMarker(targetChar)
    if not targetChar then return end
    removeLockOnMarker()

    -- '락온 (자연스러운 에임)'이 ON 상태이거나 '락온 무지개 ESP'가 OFF일 경우 하이라이트 생성 안 함
    if legitLockEnabled or not lockOnEspEnabled then
        return
    end

    local highlight = targetChar:FindFirstChild("LockOnHighlight")
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "LockOnHighlight"
        highlight.Adornee = targetChar
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 0
        highlight.Parent = targetChar
    end
end

-- 무지개 ESP 실시간 발광 회로
task.spawn(function()
    local hue = 0
    while true do
        task.wait(0.03)
        hue = (hue + 0.01) % 1
        local rainbowColor = Color3.fromHSV(hue, 0.9, 1)

        if lockOnActive and lockOnTarget and lockOnTarget.Character and not legitLockEnabled and lockOnEspEnabled then
            local highlight = lockOnTarget.Character:FindFirstChild("LockOnHighlight")
            if highlight then
                highlight.FillColor = rainbowColor
                highlight.OutlineColor = rainbowColor
            else
                createLockOnMarker(lockOnTarget.Character)
            end
        else
            removeLockOnMarker()
        end
    end
end)

local function onCharacterLoaded(char)
    isHeadlessEnabled = false
    originalNeckC0 = nil
    currentNeck = nil
    smoothNeckC0 = nil
    equippedHorns = {}

    lockOnActive = false
    updateWatermarkVisibility()
    removeLockOnMarker()
    lockOnTarget = nil

    applyAllActiveItems(char)

    task.delay(0.1, function()
        removeHeadless(char)
    end)

    if accessoriesDeletedEnabled then
        task.wait(0.3)
        if not removedAccessoriesFolder then
            removedAccessoriesFolder = Instance.new("Folder")
            removedAccessoriesFolder.Name = "RemovedAccessoriesFolder"
        end
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Accoutrement") and not string.find(item.Name, "CustomHorn_") then
                item.Parent = removedAccessoriesFolder
            end
        end
    end

    local hrp = char:WaitForChild("HumanoidRootPart", 5) or char:WaitForChild("Torso", 5)
    local hum = char:WaitForChild("Humanoid", 5)

    if hrp and hum then
        hum.Died:Connect(function()
            lockOnActive = false
            updateWatermarkVisibility()
            removeLockOnMarker()
            lockOnTarget = nil
        end)

        hum:GetPropertyChangedSignal("Sit"):Connect(function()
            if not hum.Sit then
                task.spawn(function()
                    task.wait(0.05)
                    if not freecamEnabled then
                        local camera = workspace.CurrentCamera
                        if camera then
                            camera.CameraType = Enum.CameraType.Custom
                            camera.CameraSubject = hum
                        end
                    end
                end)
                if currentNeck and originalNeckC0 then
                    currentNeck.C0 = originalNeckC0
                    smoothNeckC0 = nil
                end
            end
        end)
    end
end

player.CharacterAdded:Connect(onCharacterLoaded)
if player.Character then
    task.spawn(function()
        onCharacterLoaded(player.Character)
    end)
end

local crosshair = Instance.new("Frame")
crosshair.Size = UDim2.new(0, 16, 0, 16) crosshair.AnchorPoint = Vector2.new(0.5, 0.5) crosshair.Position = UDim2.new(0.5, 0, 0.5, 0) crosshair.BackgroundTransparency = 1 crosshair.Visible = false crosshair.Parent = screenGui
local hLine = Instance.new("Frame") hLine.Size = UDim2.new(1, 0, 0, 2) hLine.Position = UDim2.new(0, 0, 0.5, -1) hLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255) hLine.BorderSizePixel = 0 hLine.Parent = crosshair
local vLine = Instance.new("Frame") vLine.Size = UDim2.new(0, 2, 1, 0) vLine.Position = UDim2.new(0.5, -1, 0, 0) vLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255) vLine.BorderSizePixel = 0 vLine.Parent = crosshair

local function updateMouseState()
    if not freecamEnabled then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
    end
end

local function updateRightSideBar()
    if not freecamEnabled or (not pingModeActive and not blockModeActive) then
        rightSideGui.Visible = false
        return
    end
    rightSideGui.Visible = true
    if pingModeActive then
        sideStroke.Color = Color3.fromRGB(0, 255, 100)
        sideText.Text = isKoreanLang 
            and "📍 [핑 모드 조작법]\n\n• 마우스 좌클릭 : 에임 지점에 핑 생성\n• 마우스 우클릭 : 조준선 근처 핑 삭제\n• R 키 : 블록 조작 모드로 전환\n• F 키 : 모드 종료"
            or "📍 [Ping Mode Controls]\n\n• Left Click : Create Ping at Aim\n• Right Click : Remove Ping near Cursor\n• Key R : Switch to Block Mode\n• Key F : Exit Mode"
    elseif blockModeActive then
        sideStroke.Color = Color3.fromRGB(255, 170, 0)
        sideText.Text = isKoreanLang 
            and "🧱 [블록 조작 모드 조작법]\n\n• Z 키 : 바라보는 가상 블록 삭제\n• X / C 키 : 실행 취소 / 다시 실행\n• V 키 : 삭제된 블록 개수 확인\n• R 키 : 핑 모드로 전환\n• F 키 : 모드 종료"
            or "🧱 [Block Mode Controls]\n\n• Key Z : Delete Hovered Block\n• Key X / C : Undo / Redo\n• Key V : View Deleted Count\n• Key R : Switch to Ping Mode\n• Key F : Exit Mode"
    end
end

local function setSkyboxDeleted(targetState)
    if skyboxDeleted == targetState then return end
    skyboxDeleted = targetState

    if skyboxDeleted then
        originalClockTime = Lighting.ClockTime
        originalTimeOfDay = Lighting.TimeOfDay
        originalLatitude = Lighting.GeographicLatitude
        for _, obj in ipairs(Lighting:GetChildren()) do
            if obj:IsA("Sky") or obj:IsA("Atmosphere") then obj.Parent = skyboxBackup end
        end
        Lighting.ClockTime = 12
        Lighting.GeographicLatitude = 0
        showNotification("🌌 Skybox가 삭제되었습니다. (태양 중앙 고정)", "🌌 Skybox deleted.")
    else
        for _, obj in ipairs(skyboxBackup:GetChildren()) do obj.Parent = Lighting end
        Lighting.ClockTime = originalClockTime
        Lighting.TimeOfDay = originalTimeOfDay
        Lighting.GeographicLatitude = originalLatitude
        showNotification("🌌 Skybox가 복구되었습니다. (기존 날씨 원복)", "🌌 Skybox restored.")
    end
end

local function isValidTarget(targetPlayer)
    if not targetPlayer then return false end

    local myTeam = player.Team and player.Team.Name or ""
    local tTeam = targetPlayer.Team and targetPlayer.Team.Name or ""

    if myTeam == "Criminal" and tTeam == "Criminal" then return false end
    if myTeam == "Police" and tTeam == "Police" then return false end
    if myTeam == "Prisoner" and tTeam == "Prisoner" then return false end
    if myTeam == "Marines" and tTeam == "Marines" then return false end
    if myTeam == "Criminals" and tTeam == "Criminals" then return false end
    if myTeam == "Guards" and tTeam == "Guards" then return false end
    if myTeam == "Inmates" and tTeam == "Inmates" then return false end

    local qqTeams = { ["Criminal"] = true, ["Police"] = true, ["Prisoner"] = true }
    if qqTeams[myTeam] then
        if tTeam == "Prisoner" then return false end
    end

    local policeTeams = { ["Criminals"] = true, ["Guards"] = true, ["Inmates"] = true }
    if policeTeams[myTeam] then
        if tTeam == "Neutral" then return false end
    end
    
    if myTeam == "시민" then
        if tTeam == "시민" or tTeam == "레이더" then return false end
    end

    local armyTeams = {
        ["육군"] = true, ["취사병"] = true, ["의무병"] = true, ["군사경찰"] = true,
        ["특수임무대"] = true, ["특수전사령부"] = true, ["조교"] = true, ["교관"] = true,
        ["부사관"] = true, ["장교"] = true, ["교육사령부"] = true
    }

    if armyTeams[myTeam] then
        if tTeam == "영창" or tTeam == "본부" then return false end
    end

    if myTeam == "레이더" then
        if tTeam == "민간인" or tTeam == "레이더" or tTeam == "영창" then return false end
    end

    return true
end

-- -------------------------------------------------------------
-- 화면 중앙 모달 confirmation 함수
-- -------------------------------------------------------------
local function showConfirmModal(titleText, promptText, onConfirm)
    local modalGui = Instance.new("ScreenGui")
    modalGui.Name = "ConfirmModalGui"
    modalGui.ResetOnSpawn = false
    modalGui.IgnoreGuiInset = true
    modalGui.Parent = player:WaitForChild("PlayerGui")

    local bgOverlay = Instance.new("Frame")
    bgOverlay.Size = UDim2.new(1, 0, 1, 0)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bgOverlay.BackgroundTransparency = 0.5
    bgOverlay.Parent = modalGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 320, 0, 160)
    frame.Position = UDim2.new(0.5, -160, 0.5, -80)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.Parent = modalGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = Color3.fromRGB(255, 170, 0)
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.Position = UDim2.new(0, 0, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -20, 0, 45)
    desc.Position = UDim2.new(0, 10, 0, 45)
    desc.BackgroundTransparency = 1
    desc.Text = promptText
    desc.TextColor3 = Color3.fromRGB(200, 200, 200)
    desc.TextSize = 13
    desc.Font = Enum.Font.Gotham
    desc.TextWrapped = true
    desc.Parent = frame

    local confirmBtn = Instance.new("TextButton")
    confirmBtn.Size = UDim2.new(0, 120, 0, 35)
    confirmBtn.Position = UDim2.new(0.5, 10, 1, -45)
    confirmBtn.BackgroundColor3 = Color3.fromRGB(40, 150, 60)
    confirmBtn.Text = isKoreanLang and "확인" or "Confirm"
    confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    confirmBtn.Font = Enum.Font.GothamBold
    confirmBtn.TextSize = 14
    confirmBtn.Parent = frame

    local confirmCorner = Instance.new("UICorner")
    confirmCorner.CornerRadius = UDim.new(0, 6)
    confirmCorner.Parent = confirmBtn

    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Size = UDim2.new(0, 120, 0, 35)
    cancelBtn.Position = UDim2.new(0.5, -130, 1, -45)
    cancelBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    cancelBtn.Text = isKoreanLang and "취소" or "Cancel"
    cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.TextSize = 14
    cancelBtn.Parent = frame

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 6)
    cancelCorner.Parent = cancelBtn

    confirmBtn.MouseButton1Click:Connect(function()
        modalGui:Destroy()
        if onConfirm then onConfirm() end
    end)

    cancelBtn.MouseButton1Click:Connect(function()
        modalGui:Destroy()
    end)
end

-- -------------------------------------------------------------
-- ESP 시스템 제어 함수
-- -------------------------------------------------------------
local function createESP(targetPlayer)
    if targetPlayer == player then return end

    local function applyHighlight(character)
        if not espEnabled then return end
        
        local highlight = character:FindFirstChild("ESPHighlight")
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "ESPHighlight" 
            highlight.FillTransparency = 0.65 
            highlight.OutlineTransparency = 0.15 
            highlight.Parent = character
            espObjects[targetPlayer] = highlight
        end
        
        local teamColor = (targetPlayer.TeamColor and typeof(targetPlayer.TeamColor) == "BrickColor" and targetPlayer.TeamColor.Color) or Color3.fromRGB(255, 255, 255)
        local outlineColor = teamColor
        local fillColor = teamColor
        
        local tTeamName = targetPlayer.Team and targetPlayer.Team.Name or ""
        
        if tTeamName == "레이더" then
            outlineColor = Color3.fromRGB(255, 0, 0)
            fillColor = Color3.fromRGB(0, 0, 0)
        elseif tTeamName == "특수전사령부" then
            outlineColor = Color3.fromHex("#898989")
        end
        
        highlight.FillColor = fillColor
        highlight.OutlineColor = outlineColor
        
        local nameTag = character:FindFirstChild("ESPNameTag")
        if namesEnabled then
            local targetHead = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
            if not nameTag then
                local bGui = Instance.new("BillboardGui")
                bGui.Name = "ESPNameTag" 
                bGui.AlwaysOnTop = true 
                bGui.Size = UDim2.new(0, 200, 0, 30) 
                bGui.StudsOffset = Vector3.new(0, 3, 0)
                if targetHead then bGui.Adornee = targetHead end
                
                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0) 
                label.BackgroundTransparency = 1 
                label.Font = Enum.Font.GothamBold 
                label.TextSize = 12 
                label.TextStrokeTransparency = 0 
                label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) 
                label.Parent = bGui
                bGui.Parent = character 
                nameTag = bGui
            else
                if targetHead and nameTag.Adornee ~= targetHead then
                    nameTag.Adornee = targetHead
                end
            end
            local label = nameTag:FindFirstChildOfClass("TextLabel")
            if label then 
                label.Text = getFormattedName(targetPlayer)
                label.TextColor3 = teamColor 
            end
        else
            if nameTag then nameTag:Destroy() end
        end
    end

    if targetPlayer.Character then applyHighlight(targetPlayer.Character) end
    targetPlayer.CharacterAdded:Connect(applyHighlight)

    targetPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        if targetPlayer.Character then applyHighlight(targetPlayer.Character) end
    end)
    targetPlayer:GetPropertyChangedSignal("TeamColor"):Connect(function()
        if targetPlayer.Character then applyHighlight(targetPlayer.Character) end
    end)
end

player:GetPropertyChangedSignal("Team"):Connect(function()
    if espEnabled then
        task.wait(0.1)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                createESP(p)
            end
        end
    end
end)

local function removeESP(targetPlayer)
    if espObjects[targetPlayer] then espObjects[targetPlayer] = nil end
    if targetPlayer.Character then
        local highlight = targetPlayer.Character:FindFirstChild("ESPHighlight") if highlight then highlight:Destroy() end
        local nameTag = targetPlayer.Character:FindFirstChild("ESPNameTag") if nameTag then nameTag:Destroy() end
    end
end

local function updateAllESP()
    if espEnabled then 
        for _, p in ipairs(Players:GetPlayers()) do createESP(p) end 
    else 
        for _, p in ipairs(Players:GetPlayers()) do removeESP(p) end 
    end
end

Players.PlayerAdded:Connect(function(p) if espEnabled then createESP(p) end end)
Players.PlayerRemoving:Connect(removeESP)

local function disableCharacterMovement()
    ContextActionService:BindAction(ACTION_NAME, function() return Enum.ContextActionResult.Sink end, false, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.V, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.R, Enum.KeyCode.F, Enum.KeyCode.T)
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.AutoRotate = false humanoid:UnequipTools() end
    end
end

local function enableCharacterMovement()
    ContextActionService:UnbindAction(ACTION_NAME)
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.AutoRotate = true end
    end
end

local function getTargetNearMouse()
    local camera = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local closestPlayer = nil
    local shortestDistance = math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and isValidTarget(p) then
            local targetPart = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
            local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
            if targetPart and humanoid and humanoid.Health > 0 then
                local screenPos, onScreen = camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist2D < shortestDistance then shortestDistance = dist2D closestPlayer = p end
                end
            end
        end
    end
    return closestPlayer
end

local function getMouseRaycast()
    local camera = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local mouseRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {player.Character}
    return workspace:Raycast(rayOrigin, rayDirection * 1000, raycastParams)
end

local function createPingAt(position)
    local pingPart = Instance.new("Part") pingPart.Shape = Enum.PartType.Ball pingPart.Size = Vector3.new(0.5, 0.5, 0.5) pingPart.Position = position pingPart.Anchored = true pingPart.CanCollide = false pingPart.Transparency = 1 pingPart.Parent = workspace
    local bGui = Instance.new("BillboardGui") bGui.AlwaysOnTop = true bGui.Size = UDim2.new(0, 30, 0, 30) bGui.Adornee = pingPart bGui.Parent = screenGui
    local ringFrame = Instance.new("Frame") ringFrame.Size = UDim2.new(1, 0, 1, 0) ringFrame.BackgroundTransparency = 1 ringFrame.Parent = bGui
    local ringCorner = Instance.new("UICorner") ringCorner.CornerRadius = UDim.new(1, 0) ringCorner.Parent = ringFrame
    local ringStroke = Instance.new("UIStroke") ringStroke.Color = Color3.fromRGB(255, 75, 75) ringStroke.Thickness = 2 ringStroke.Parent = ringFrame
    local centerDot = Instance.new("Frame") centerDot.Size = UDim2.new(0, 6, 0, 6) centerDot.AnchorPoint = Vector2.new(0.5, 0.5) centerDot.Position = UDim2.new(0.5, 0, 0.5, 0) centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255) centerDot.BorderSizePixel = 0 centerDot.Parent = bGui
    local dotCorner = Instance.new("UICorner") dotCorner.CornerRadius = UDim.new(1, 0) dotCorner.Parent = centerDot
    local textGui = Instance.new("BillboardGui") textGui.AlwaysOnTop = true textGui.Size = UDim2.new(0, 100, 0, 20) textGui.StudsOffset = Vector3.new(0, 1.5, 0) textGui.Adornee = pingPart textGui.Parent = screenGui
    local label = Instance.new("TextLabel") label.Size = UDim2.new(1, 0, 1, 0) label.BackgroundTransparency = 1 label.Font = Enum.Font.GothamBold label.TextSize = 11 label.TextColor3 = Color3.fromRGB(255, 75, 75) label.TextStrokeTransparency = 0.2 label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0) label.Text = isKoreanLang and "📍 계산중" or "📍 Calc..." label.Parent = textGui

    activePings[pingPart] = { RingGui = bGui, TextGui = textGui, Label = label }
    playSound(4088924043, 1, 1)

    task.spawn(function()
        local step = 0
        while pingPart and pingPart.Parent do
            step = step + 1
            local pulse = 1 + math.sin(step * 0.15) * 0.2
            bGui.Size = UDim2.new(0, 30 * pulse, 0, 30 * pulse)
            ringStroke.Transparency = 0.1 + math.abs(math.sin(step * 0.15)) * 0.4
            
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local distance = (player.Character.HumanoidRootPart.Position - pingPart.Position).Magnitude
                label.Text = string.format("📍 %.1fm", distance)
            end
            
            task.wait()
        end
    end)
end

local function destroyPing(pingPart)
    if activePings[pingPart] then
        activePings[pingPart].RingGui:Destroy() activePings[pingPart].TextGui:Destroy() activePings[pingPart] = nil pingPart:Destroy()
        playSound(8503529139, 0.8, 0.9)
    end
end

local function clearAllPings() for pingPart, _ in pairs(activePings) do destroyPing(pingPart) end table.clear(activePings) end

local function deleteTargetBlock()
    local res = getMouseRaycast()
    if res and res.Instance and res.Instance:IsA("BasePart") and res.Instance ~= workspace.Terrain then
        local target = res.Instance
        local idx = table.find(activeBlocks, target) if idx then table.remove(activeBlocks, idx) end
        target.Parent = nil
        table.insert(undoStack, {type = "delete", block = target}) table.clear(redoStack)
        showNotification("🗑️ 가리킨 조준선 블록을 삭제했습니다.", "🗑️ Deleted targeted block.") playSound(8503529139, 0.8, 0.8) updateRightSideBar()
    end
end

local function undoAction()
    if #undoStack == 0 then showNotification("↩️ 되돌릴 작업이 없습니다.", "↩️ Nothing to undo.") return end
    local action = table.remove(undoStack)
    if action.type == "delete" then
        action.block.Parent = workspace table.insert(activeBlocks, action.block) table.insert(redoStack, action)
        showNotification("↩️ 실행 취소: 삭제되었던 가상 블록을 복구했습니다.", "↩️ Undo: Restored deleted block.") playSound(8503529139, 0.9, 1.2) updateRightSideBar()
    end
end

local function redoAction()
    if #redoStack == 0 then showNotification("↪️ 다시 실행할 작업이 없습니다.", "↪️ Nothing to redo.") return end
    local action = table.remove(redoStack)
    if action.type == "delete" then
        local idx = table.find(activeBlocks, action.block) if idx then table.remove(activeBlocks, idx) end
        action.block.Parent = nil table.insert(undoStack, action)
        showNotification("↪️ 다시 실행: 복구했던 가상 블록을 다시 삭제했습니다.", "↪️ Redo: Deleted block again.") playSound(8503529139, 0.8, 1.3) updateRightSideBar()
    end
end

local function enableFreecam()
    freecamEnabled = true

    local camera = workspace.CurrentCamera local cf = camera.CFrame
    if lastFreecamPosition then position = lastFreecamPosition yaw = lastFreecamYaw or 0 pitch = lastFreecamPitch or 0
    else position = cf.Position local rx, ry = cf:ToOrientation() pitch = math.deg(rx) yaw = math.deg(ry) end
    smoothPitch = pitch smoothYaw = yaw camera.CameraType = Enum.CameraType.Scriptable
    targetFov = normalFov
    disableCharacterMovement() updateMouseState()
    showNotification("🎥 프리캠이 활성화되었습니다. [마우스 휠: FOV 조절 / Delete: UI]", "🎥 Freecam Enabled. [Scroll: FOV / Delete: UI]") playSound(8503529139, 1, 1.1)
end

local function disableFreecam(skipNotify)
    lastFreecamPosition = position lastFreecamYaw = yaw lastFreecamPitch = pitch
    freecamEnabled = false pingModeActive = false blockModeActive = false crosshair.Visible = false rightSideGui.Visible = false
    clearAllPings()
    local camera = workspace.CurrentCamera camera.CameraType = Enum.CameraType.Custom camera.FieldOfView = normalFov
    enableCharacterMovement() updateMouseState()

    if not skipNotify then showNotification("❌ 프리캠이 비활성화되었습니다. (블록 보존됨)", "❌ Freecam Disabled.") playSound(8503529139, 0.9, 0.8) end
end

local function toggleLockOn()
    if lockOnActive then
        lockOnActive = false 
        removeLockOnMarker()
        lockOnTarget = nil
        hpBlock:SetText("HP: - / -")
        updateWatermarkVisibility()
        showNotification("🎯 락온이 해제되었습니다.", "🎯 Lock-On Released.") playSound(8503529139, 1.2, 0.8)
    else
        local target = getTargetNearMouse()
        if target then
            local myChar = player.Character
            local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
            local targetHrp = target.Character and (target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("Torso"))

            if myHrp and targetHrp then
                local dist = (myHrp.Position - targetHrp.Position).Magnitude
                if dist > maxLockOnDistance then
                    showNotification(
                        string.format("⚠️ 타겟이 너무 멉니다 (%dm 이상 락온 불가).", maxLockOnDistance), 
                        string.format("⚠️ Target too far (> %dm).", maxLockOnDistance)
                    )
                    playSound(8503529139, 1, 0.8)
                    return
                end
            end

            lockOnTarget = target 
            lockOnActive = true 
            updateWatermarkVisibility()
            createLockOnMarker(target.Character)

            local targetName = getFormattedName(target) 
            local targetPartType = headLockActive and (isKoreanLang and "머리" or "Head") or (isKoreanLang and "몸통" or "Torso")
            showNotification("🎯 " .. targetName .. " " .. targetPartType .. " (Lock-On)", "🎯 Locked on to " .. targetName) playSound(8503529139, 1.4, 1.1)
        else
            showNotification("⚠️ 화면에 락온할 대상이 존재하지 않거나 조준할 수 없는 팀입니다.", "⚠️ No valid Lock-On target in view.")
        end
    end
end

-- -------------------------------------------------------------
-- UI 레이아웃 구성
-- -------------------------------------------------------------
local modTab = window:AddTab({ Icon = 'cloud', Name = "Mod" })
local camSec = modTab:AddSection({ Name = "Camera Control", Position = 'right' })
local espSec = modTab:AddSection({ Name = "ESP Setup", Position = 'left' })
local charSec = modTab:AddSection({ Name = "Character", Position = 'left' })

-- ESP 설정 섹션
local espLabelObj = espSec:AddLabel('ESP (플레이어 강조)')
espLabelObj:AddToggle({
    Default = false, Flag = "esp_toggle",
    Callback = function(v)
        espEnabled = v
        updateAllESP()
        if espEnabled then
            showNotification("👁️ ESP 기능이 활성화되었습니다.", "👁️ ESP Activated.")
            playSound(8503529139, 1, 1.2)
        else
            showNotification("🚫 ESP 기능이 비활성화되었습니다.", "🚫 ESP Deactivated.")
            playSound(8503529139, 1, 0.8)
        end
    end
})

-- 락온 무지개 ESP 토글 (기본 OFF)
local lockOnEspLabelObj = espSec:AddLabel('락온 무지개 ESP')
lockOnEspLabelObj:AddToggle({
    Default = false, Flag = "lockon_rainbow_esp",
    Callback = function(v)
        lockOnEspEnabled = v
        if not v then
            removeLockOnMarker()
        elseif lockOnActive and lockOnTarget and lockOnTarget.Character then
            createLockOnMarker(lockOnTarget.Character)
        end
    end
})

local espNamesLabelObj = espSec:AddLabel('닉네임 표시')
espNamesLabelObj:AddToggle({
    Default = false, Flag = "esp_names",
    Callback = function(v)
        namesEnabled = v
        updateAllESP()
        if namesEnabled then
            showNotification("🏷️ 닉네임 표시 기능이 활성화되었습니다.", "🏷️ Display Names Enabled.")
        else
            showNotification("🚫 닉네임 표시 기능이 비활성화되었습니다.", "🚫 Display Names Disabled.")
        end
    end
})

local killfeedShowLabelObj = espSec:AddLabel('킬피드 표시')
killfeedShowLabelObj:AddToggle({
    Default = true, Flag = "killfeed_show",
    Callback = function(v)
        showKillFeed = v
        killFeedContainer.Visible = v
        if v then
            showNotification("🗡️ 실시간 킬 피드가 활성화되었습니다.", "🗡️ Kill Feed Enabled.")
        else
            showNotification("🙈 실시간 킬 피드가 숨겨졌습니다.", "🙈 Kill Feed Hidden.")
        end
    end
})

local headTrackLabel = espSec:AddLabel('정밀 머리 트래킹')
headTrackLabel:AddToggle({
    Default = headLockActive, Flag = "headtrack",
    Callback = function(v)
        headLockActive = v
        if headLockActive then
            showNotification("👀 캐릭터 머리 트래킹이 활성화되었습니다.", "👀 Head Tracking Enabled.")
            playSound(8503529139, 1, 1.2)
        else
            showNotification("🚫 캐릭터 머리 트래킹이 해제되었습니다. (몸통 고정)", "🚫 Head Tracking Disabled.")
            playSound(8503529139, 1, 0.8)
        end
        if lockOnActive and lockOnTarget and lockOnTarget.Character then createLockOnMarker(lockOnTarget.Character) end
    end
})

local legitLockLabelObj = espSec:AddLabel('락온 (자연스러운 에임)')
legitLockLabelObj:AddToggle({
    Default = false, Flag = "legit_lockon",
    Callback = function(v)
        legitLockEnabled = v
        if legitLockEnabled then
            removeLockOnMarker() -- 자연스러운 에임 활성화 시 무지개 ESP 숨김
            showNotification("🤫 락온 (자연스러운 에임)이 활성화되었습니다.", "🤫 Legit Lock-On Enabled.")
            playSound(8503529139, 1, 1.2)
        else
            if lockOnActive and lockOnTarget and lockOnTarget.Character then
                createLockOnMarker(lockOnTarget.Character) -- 끄면 무지개 ESP 복구
            end
            showNotification("🎯 일반 락온(즉시 고정)으로 변경되었습니다.", "🎯 Instant Lock-On Enabled.")
            playSound(8503529139, 1, 0.8)
        end
    end
})

-- 락온 최대 거리 설정 슬라이더
local lockOnDistLabelObj = espSec:AddLabel('락온 최대 거리 (m)')
local lockOnDistSlider = lockOnDistLabelObj:AddSlider({
    Min = 100, Max = 5000, Default = 1000, Flag = "lockon_dist_slider",
    Callback = function(v)
        maxLockOnDistance = v
    end
})

-- 락온 최대거리 초기화 버튼
local resetLockOnDistBtn = espSec:AddButton({
    Name = "락온 최대거리 초기화",
    Callback = function()
        maxLockOnDistance = 1000
        if lockOnDistSlider then
            pcall(function()
                if lockOnDistSlider.Set then lockOnDistSlider:Set(1000) end
                if lockOnDistSlider.SetValue then lockOnDistSlider:SetValue(1000) end
            end)
        end
        showNotification("🔄 락온 최대 거리가 초기화되었습니다 (1000m).", "🔄 Lock-On Max Distance reset (1000m).")
        playSound(8503529139, 1, 1)
    end
})

-- Character 섹션 (Custom Item 카탈로그 연동)
local hornOpts = {}
local selectedHornIdx = 1
local selectedSkinName = ""

local function updateHornOpts()
    table.clear(hornOpts)
    for i, h in ipairs(hornCatalog) do 
        table.insert(hornOpts, isKoreanLang and h.rawNameKr or h.rawNameEn) 
    end
end
updateHornOpts()

local skinDropdown = nil

local function getSkinNamesForIndex(idx)
    local item = hornCatalog[idx]
    local names = {}
    if item and item.skins then
        if idx == 1 then
            names = {"보라뿔", "빨간불", "파란불"}
        else
            for skinName, _ in pairs(item.skins) do
                table.insert(names, skinName)
            end
            table.sort(names)
        end
    end
    if #names == 0 then table.insert(names, "기본") end
    return names
end

local customItemLabel = charSec:AddLabel('커스텀 아이템')
local customItemDropdown = customItemLabel:AddDropdown({
    Default = hornOpts[1], Values = hornOpts, Flag = "horn_drop",
    Callback = function(v)
        for i, h in ipairs(hornCatalog) do
            if (isKoreanLang and h.rawNameKr or h.rawNameEn) == v then 
                selectedHornIdx = i 
                local skinList = getSkinNamesForIndex(selectedHornIdx)
                selectedSkinName = skinList[1]
                if skinDropdown and skinDropdown.SetValues then
                    skinDropdown:SetValues(skinList)
                end
                break 
            end
        end
    end
})

local skinLabel = charSec:AddLabel('스킨')
skinDropdown = skinLabel:AddDropdown({
    Default = getSkinNamesForIndex(1)[1], 
    Values = getSkinNamesForIndex(1), 
    Flag = "skin_drop",
    Callback = function(v)
        selectedSkinName = v
        local itemData = hornCatalog[selectedHornIdx]
        local char = player.Character
        if not char or not itemData then return end

        local newSkinId = itemData.skins and itemData.skins[selectedSkinName]
        if not newSkinId then return end

        local oldSkinIdToRemove = nil
        for skinName, sId in pairs(itemData.skins or {}) do
            if activeAppliedItems[sId] and sId ~= newSkinId then
                oldSkinIdToRemove = sId
                break
            end
        end

        if oldSkinIdToRemove then
            activeAppliedItems[oldSkinIdToRemove] = nil
            if equippedHorns[oldSkinIdToRemove] then
                if type(equippedHorns[oldSkinIdToRemove]) == "userdata" and equippedHorns[oldSkinIdToRemove].Parent then
                    equippedHorns[oldSkinIdToRemove]:Destroy()
                end
                equippedHorns[oldSkinIdToRemove] = nil
            end
            local oldObj = char:FindFirstChild("CustomHorn_" .. oldSkinIdToRemove)
            if oldObj then oldObj:Destroy() end

            task.spawn(function()
                local applied = applyHornToCharacter(char, newSkinId, itemData.type)
                if applied then
                    activeAppliedItems[newSkinId] = { type = itemData.type, name = itemData.rawNameKr }
                    showNotification("🔄 아이템 스킨이 변경되었습니다: " .. selectedSkinName, "🔄 Item Skin Changed: " .. selectedSkinName)
                    playSound(8503529139, 1, 1.2)
                end
            end)
        end
    end
})

selectedSkinName = getSkinNamesForIndex(1)[1]

local applyItemBtn = charSec:AddButton({
    Name = "아이템 적용",
    Callback = function()
        local itemData = hornCatalog[selectedHornIdx]
        local char = player.Character
        if not char or not itemData then return end

        local skinId = itemData.skins and itemData.skins[selectedSkinName]
        if not skinId then
            for _, id in pairs(itemData.skins or {}) do skinId = id break end
        end

        if not skinId then return end

        if activeAppliedItems[skinId] then
            showNotification("⚠️ 이미 착용 중인 아이템 스킨입니다: " .. selectedSkinName, "⚠️ Skin already equipped: " .. selectedSkinName)
            return
        end

        task.spawn(function()
            local applied = applyHornToCharacter(char, skinId, itemData.type)
            if applied then
                activeAppliedItems[skinId] = { type = itemData.type, name = itemData.rawNameKr }
                showNotification("🔥 아이템 스킨이 적용되었습니다: " .. (isKoreanLang and itemData.rawNameKr or itemData.rawNameEn) .. " (" .. selectedSkinName .. ")", "🔥 Applied: " .. selectedSkinName)
                playSound(8503529139, 1, 1.2)
            else
                showNotification("❌ 아이템 로드 실패 (ID: " .. skinId .. ")", "❌ Failed to load item.")
            end
        end)
    end
})

local removeItemBtn = charSec:AddButton({
    Name = "아이템 해제",
    Callback = function()
        local itemData = hornCatalog[selectedHornIdx]
        local char = player.Character
        local skinId = itemData and itemData.skins and itemData.skins[selectedSkinName]
        local removed = false

        if skinId then
            if activeAppliedItems[skinId] then
                activeAppliedItems[skinId] = nil
                removed = true
            end

            if equippedHorns[skinId] then
                if type(equippedHorns[skinId]) == "userdata" and equippedHorns[skinId].Parent then
                    equippedHorns[skinId]:Destroy()
                end
                equippedHorns[skinId] = nil
            end

            if char then
                local existing = char:FindFirstChild("CustomHorn_" .. skinId)
                if existing then existing:Destroy() end
            end
        end

        if removed then
            showNotification("❄️ 선택한 스킨이 해제되었습니다: " .. selectedSkinName, "❄️ Skin Removed: " .. selectedSkinName)
            playSound(8503529139, 0.9, 0.8)
        else
            showNotification("⚠️ 착용 중이지 않은 스킨입니다: " .. selectedSkinName, "⚠️ Skin not equipped.")
        end
    end
})

local headlessLabelObj = charSec:AddLabel('헤드리스 모드')
headlessLabelObj:AddToggle({
    Default = false, Flag = "headless",
    Callback = function(v)
        isHeadlessEnabled = v
        local char = player.Character
        if isHeadlessEnabled then
            applyHeadless(char)
            showNotification("🎃 헤드리스 기능이 적용되었습니다.", "🎃 Headless Mode Applied.")
            playSound(8503529139, 1, 1.2)
        else
            removeHeadless(char)
            showNotification("🎃 헤드리스 기능이 해제되었습니다.", "🎃 Headless Mode Removed.")
            playSound(8503529139, 1, 0.8)
        end
    end
})

local rmAccLabelObj = charSec:AddLabel('장신구 제거')
rmAccLabelObj:AddToggle({
    Default = false, Flag = "rm_acc",
    Callback = function(v)
        accessoriesDeletedEnabled = v
        local char = player.Character
        if not char then return end

        if v then
            if not removedAccessoriesFolder then
                removedAccessoriesFolder = Instance.new("Folder")
                removedAccessoriesFolder.Name = "RemovedAccessoriesFolder"
            end

            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Accoutrement") and not string.find(item.Name, "CustomHorn_") then
                    item.Parent = removedAccessoriesFolder
                end
            end
            playSound(8503529139, 1, 1)
        else
            if removedAccessoriesFolder then
                for _, item in ipairs(removedAccessoriesFolder:GetChildren()) do
                    item.Parent = char
                end
            end
            playSound(8503529139, 1, 1.2)
        end
    end
})

-- Client 탭
local envTab = window:AddTab({ Icon = 'folder', Name = "Client" })

-- SYSTEM OVERVIEW
local sysOverviewSec = envTab:AddSection({ Name = "SYSTEM OVERVIEW", Position = 'left' })

local sessionTimeLabel = sysOverviewSec:AddLabel("세션: 00:00:00")
local serverRegionLabel = sysOverviewSec:AddLabel("서버: AS")
local playersCountLabel = sysOverviewSec:AddLabel(string.format("플레이어: %d/%d", #Players:GetPlayers(), Players.MaxPlayers))

task.spawn(function()
    while task.wait(1) do
        local elapsed = math.floor(os.clock() - startTime)
        local hrs = math.floor(elapsed / 3600)
        local mins = math.floor((elapsed % 3600) / 60)
        local secs = elapsed % 60
        
        local sessionPrefix = isKoreanLang and "세션" or "Session"
        local serverPrefix = isKoreanLang and "서버" or "Server"
        local playerPrefix = isKoreanLang and "플레이어" or "Players"
        
        sessionTimeLabel:SetText(string.format("%s: %02d:%02d:%02d", sessionPrefix, hrs, mins, secs))
        serverRegionLabel:SetText(string.format("%s: AS", serverPrefix))
        playersCountLabel:SetText(string.format("%s: %d/%d", playerPrefix, #Players:GetPlayers(), Players.MaxPlayers))
    end
end)

-- Anti-AFK
local antiAfkSec = envTab:AddSection({ Name = "Anti-AFK System", Position = 'right' })
local antiAfkEnabled = true

local antiAfkLabelObj = antiAfkSec:AddLabel('Anti-AFK (강퇴 방지)')
antiAfkLabelObj:AddToggle({
    Default = true, Flag = "anti_afk",
    Callback = function(v)
        antiAfkEnabled = v
        if antiAfkEnabled then
            showNotification("🛡️ Anti-AFK 방지 모듈이 활성화되었습니다.", "🛡️ Anti-AFK Activated.")
        else
            showNotification("⚠️ Anti-AFK 방지 모듈이 해제되었습니다.", "⚠️ Anti-AFK Deactivated.")
        end
    end
})

local VirtualUser = game:GetService("VirtualUser")
player.Idled:Connect(function()
    if antiAfkEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        showNotification("🛡️ Anti-AFK: 잠수 방지 액션이 동작했습니다.", "🛡️ Anti-AFK triggered.")
    end
end)

-- Notifications
local notifySec = envTab:AddSection({ Name = "Notifications", Position = 'left' })

local leftNotifyLabelObj = notifySec:AddLabel('왼쪽 알림 로그')
leftNotifyLabelObj:AddToggle({
    Default = false, Flag = "left_notify",
    Callback = function(v) leftNotifyEnabled = v end
})

local rightNotifyLabelObj = notifySec:AddLabel('오른쪽 UI 알림')
rightNotifyLabelObj:AddToggle({
    Default = true, Flag = "right_notify",
    Callback = function(v) rightNotifyEnabled = v end
})

-- Status Bar Custom (HP / 핑 / Smart Hub)
local watermarkSec = envTab:AddSection({ Name = "Status Bar (Watermark)", Position = 'left' })

local hpBarToggleObj = watermarkSec:AddLabel('상대 HP 표시')
hpBarToggleObj:AddToggle({
    Default = true, Flag = "show_hp_bar",
    Callback = function(v)
        showHpBlock = v
        updateWatermarkVisibility()
    end
})

local pingBarToggleObj = watermarkSec:AddLabel('핑 표시')
pingBarToggleObj:AddToggle({
    Default = true, Flag = "show_ping_bar",
    Callback = function(v)
        showPingBlock = v
        updateWatermarkVisibility()
    end
})

local hubBarToggleObj = watermarkSec:AddLabel('Smart Hub 표시')
hubBarToggleObj:AddToggle({
    Default = true, Flag = "show_hub_bar",
    Callback = function(v)
        showHubBlock = v
        updateWatermarkVisibility()
    end
})

local barShowToggleObj = watermarkSec:AddLabel('Status Bar 표시 / 숨기기')
barShowToggleObj:AddToggle({
    Default = true, Flag = "show_watermark_ui",
    Callback = function(v)
        showWatermarkUI = v
        updateWatermarkVisibility()
        if v then
            showNotification("상단 바 UI가 표시됩니다.", "Status bar displayed.")
        else
            showNotification("상단 바 UI가 숨겨졌습니다.", "Status bar hidden.")
        end
    end
})

-- Graphics
local gfxSec = envTab:AddSection({ Name = "Graphics", Position = 'left' })

local graphicsEnhancements = Instance.new("Folder")
graphicsEnhancements.Name = "GraphicsEnhancements"
local cc = Instance.new("ColorCorrectionEffect", graphicsEnhancements)
cc.Saturation = 0.35 cc.Contrast = 0.25 cc.Brightness = 0.05
local bloom = Instance.new("BloomEffect", graphicsEnhancements)
bloom.Intensity = 0.5 bloom.Size = 25
local sunrays = Instance.new("SunRaysEffect", graphicsEnhancements)
sunrays.Intensity = 0.06 sunrays.Spread = 0.15

graphicsEnhancements.Parent = Lighting
Lighting.EnvironmentSpecularScale = 1
Lighting.EnvironmentDiffuseScale = 1

local rtxTog = gfxSec:AddLabel('RTX 그래픽 향상')
rtxTog:AddToggle({
    Default = true, Flag = "rtx",
    Callback = function(v)
        if v then
            graphicsEnhancements.Parent = Lighting
            Lighting.EnvironmentSpecularScale = 1
            Lighting.EnvironmentDiffuseScale = 1
            showNotification("✨ RTX 그래픽 향상 모드가 적용되었습니다.", "✨ RTX Mode Applied.")
        else
            graphicsEnhancements.Parent = nil
            Lighting.EnvironmentSpecularScale = originalSpecular
            Lighting.EnvironmentDiffuseScale = originalDiffuse
            showNotification("✨ RTX 그래픽 향상 모드가 해제되었습니다.", "✨ RTX Mode Disabled.")
        end
    end
})

local skyboxLabelTextKr = "스카이박스 제거"
local shadowLabelTextKr = "그림자 제거"
local fogLabelTextKr = "안개/날씨 효과 제거"

local skyboxLabelTextEn = "Remove Skybox"
local shadowLabelTextEn = "Remove Shadows"
local fogLabelTextEn = "Remove Fog & Weather"

local skyboxLabel = gfxSec:AddLabel(skyboxLabelTextKr)
skyboxLabel:AddToggle({ Default = false, Flag = "skybox", Callback = function(v) setSkyboxDeleted(v) end })

local shadowLabel = gfxSec:AddLabel(shadowLabelTextKr)
shadowLabel:AddToggle({ Default = false, Flag = "shadows", Callback = function(v) Lighting.GlobalShadows = not v end })

local fogLabel = gfxSec:AddLabel(fogLabelTextKr)
fogLabel:AddToggle({
    Default = false, Flag = "fog",
    Callback = function(v)
        if v then
            Lighting.FogEnd = 100000
            if Lighting:FindFirstChildOfClass("Atmosphere") then Lighting:FindFirstChildOfClass("Atmosphere").Density = 0 end
        else
            Lighting.FogEnd = originalFogEnd
            if Lighting:FindFirstChildOfClass("Atmosphere") then Lighting:FindFirstChildOfClass("Atmosphere").Density = originalAtmosphereDensity end
        end
    end
})

-- External Scripts
local extSec = envTab:AddSection({ Name = "External Scripts", Position = 'right' })

extSec:AddButton({
    Name = "Launch Infinite Yield",
    Callback = function()
        showConfirmModal("Infinite Yield", isKoreanLang and "Infinite Yield를 실행하시겠습니까?" or "Launch Infinite Yield?", function()
            task.spawn(function()
                local success = pcall(function() 
                    loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))() 
                end)
                if success then playSound(8503529139, 1, 1) end
            end)
        end)
    end
})

extSec:AddButton({
    Name = "Launch DEX Explorer",
    Callback = function()
        showConfirmModal("DEX Explorer", isKoreanLang and "DEX Explorer를 실행하시겠습니까?" or "Launch DEX Explorer?", function()
            task.spawn(function()
                local success = pcall(function() 
                    loadstring(game:HttpGet("https://rawscripts.net/raw/Universal-Script-Keyless-mobile-dex-17888"))() 
                end)
                if success then playSound(8503529139, 1, 1) end
            end)
        end)
    end
})

local keyControlSec = envTab:AddSection({ Name = "Key Bind Controls", Position = 'right' })

local lockOnKeyLabelObj = keyControlSec:AddLabel('락온 기능 (마우스 휠클릭)')
lockOnKeyLabelObj:AddToggle({
    Default = true, Flag = "key_lockon_toggle",
    Callback = function(v)
        keyStates.LockOn = v
        if not v and lockOnActive then toggleLockOn() end
    end
})

local endKeyLabelObj = keyControlSec:AddLabel('End 키 (프리캠 토글)')
endKeyLabelObj:AddToggle({
    Default = false, Flag = "key_end_toggle",
    Callback = function(v)
        keyStates.End = v
        if not v and freecamEnabled then disableFreecam(false) end
    end
})

local endLongKeyLabelObj = keyControlSec:AddLabel('End 길게누르기 (FOV 초기화)')
endLongKeyLabelObj:AddToggle({
    Default = false, Flag = "key_end_long_toggle",
    Callback = function(v) keyStates.EndLong = v end
})

local pgdnKeyLabelObj = keyControlSec:AddLabel('PgDn 키 (카메라 이동)')
pgdnKeyLabelObj:AddToggle({
    Default = false, Flag = "key_pgdn_toggle",
    Callback = function(v) keyStates.PgDn = v end
})

local pgdnLongKeyLabelObj = keyControlSec:AddLabel('PgDn 길게누르기 (공간 도약)')
pgdnLongKeyLabelObj:AddToggle({
    Default = false, Flag = "key_pgdn_long_toggle",
    Callback = function(v) keyStates.PgDnLong = v end
})

local bracketKeyLabelObj = keyControlSec:AddLabel('] 키 (머리 트래킹)')
bracketKeyLabelObj:AddToggle({
    Default = false, Flag = "key_bracket_toggle",
    Callback = function(v) keyStates.RightBracket = v end
})

local bracketLongKeyLabelObj = keyControlSec:AddLabel('] 길게누르기 (TP 모드)')
bracketLongKeyLabelObj:AddToggle({
    Default = false, Flag = "key_bracket_long_toggle",
    Callback = function(v)
        keyStates.RightBracketLong = v
        if not v and tpModeActive then
            tpModeActive = false
            showNotification("🚫 TP 모드가 해제되었습니다.", "🚫 TP Mode Disabled.")
        end
    end
})

-- UI 단축키 및 시스템 설정 (메뉴 크기 기본 '크게')
local menuKeybindLabelObj = window.UserSettings:AddLabel("메뉴 단축키")
menuKeybindLabelObj:AddKeybind({
    Default = 'Delete',
    Callback = function(v)
        window.Keybind = v
        minimizeKeybind = v
        Logging.new("ps4-touchpad", 'Changed ui keybind to '..tostring(v), 5)
    end,
})

local scaleMapKrToEn = {
    ["기본"] = "Default",
    ["크게"] = "Large",
    ["모바일"] = "Mobile",
    ["작게"] = "Small"
}

local menuScaleLabelObj = window.UserSettings:AddLabel('메뉴 크기')
local menuScaleDropdown = menuScaleLabelObj:AddDropdown({
    Default = "크게", -- 메뉴 크기 크게 기본 설정
    Values = {"기본", "크게", "모바일", "작게"},
    Callback = function(v)
        local targetScaleKey = scaleMapKrToEn[v] or v
        if NeverLose.Scales[targetScaleKey] then
            window:SetSize(NeverLose.Scales[targetScaleKey])
            Logging.new("crop", 'Changed ui size to '..tostring(targetScaleKey), 5)
        end
    end,
})

local langToggleLabelObj = window.UserSettings:AddLabel('한국어')
langToggleLabelObj:AddToggle({
    Default = true,
    Callback = function(v)
        isKoreanLang = v
        if window.Set3DRender then window:Set3DRender(v) end
        updateHornOpts()
        
        if customItemDropdown and customItemDropdown.SetValues then
            customItemDropdown:SetValues(hornOpts)
        end

        if menuScaleDropdown and menuScaleDropdown.SetValues then
            if v then
                menuScaleDropdown:SetValues({"기본", "크게", "모바일", "작게"})
            else
                menuScaleDropdown:SetValues({"Default", "Large", "Mobile", "Small"})
            end
        end

        if v then
            if customItemLabel.SetText then customItemLabel:SetText("커스텀 아이템") end
            if skinLabel.SetText then skinLabel:SetText("스킨") end
            if applyItemBtn.SetText then applyItemBtn:SetText("아이템 적용") end
            if removeItemBtn.SetText then removeItemBtn:SetText("아이템 해제") end
            if rtxTog.SetText then rtxTog:SetText("RTX 그래픽 향상") end
            if skyboxLabel.SetText then skyboxLabel:SetText(skyboxLabelTextKr) end
            if shadowLabel.SetText then shadowLabel:SetText(shadowLabelTextKr) end
            if fogLabel.SetText then fogLabel:SetText(fogLabelTextKr) end
            if espLabelObj.SetText then espLabelObj:SetText('ESP (플레이어 강조)') end
            if lockOnEspLabelObj.SetText then lockOnEspLabelObj:SetText('락온 무지개 ESP') end
            if espNamesLabelObj.SetText then espNamesLabelObj:SetText('닉네임 표시') end
            if killfeedShowLabelObj.SetText then killfeedShowLabelObj:SetText('킬피드 표시') end
            if headTrackLabel.SetText then headTrackLabel:SetText('정밀 머리 트래킹') end
            if legitLockLabelObj and legitLockLabelObj.SetText then legitLockLabelObj:SetText('락온 (자연스러운 에임)') end
            if lockOnDistLabelObj and lockOnDistLabelObj.SetText then lockOnDistLabelObj:SetText('락온 최대 거리 (m)') end
            if resetLockOnDistBtn and resetLockOnDistBtn.SetText then resetLockOnDistBtn:SetText("락온 최대거리 초기화") end
            if headlessLabelObj.SetText then headlessLabelObj:SetText('헤드리스 모드') end
            if rmAccLabelObj.SetText then rmAccLabelObj:SetText('장신구 제거') end
            if antiAfkLabelObj.SetText then antiAfkLabelObj:SetText('Anti-AFK (강퇴 방지)') end
            if leftNotifyLabelObj.SetText then leftNotifyLabelObj:SetText('왼쪽 알림 로그') end
            if rightNotifyLabelObj.SetText then rightNotifyLabelObj:SetText('오른쪽 UI 알림') end
            if hpBarToggleObj.SetText then hpBarToggleObj:SetText('상대 HP 표시') end
            if pingBarToggleObj.SetText then pingBarToggleObj:SetText('핑 표시') end
            if hubBarToggleObj.SetText then hubBarToggleObj:SetText('Smart Hub 표시') end
            if barShowToggleObj.SetText then barShowToggleObj:SetText('Status Bar 표시 / 숨기기') end
            if menuKeybindLabelObj.SetText then menuKeybindLabelObj:SetText("메뉴 단축키") end
            if menuScaleLabelObj.SetText then menuScaleLabelObj:SetText('메뉴 크기') end
            if langToggleLabelObj.SetText then langToggleLabelObj:SetText('한국어') end
            if lockOnKeyLabelObj.SetText then lockOnKeyLabelObj:SetText('락온 기능 (마우스 휠클릭)') end
            if endKeyLabelObj.SetText then endKeyLabelObj:SetText('End 키 (프리캠 토글)') end
            if endLongKeyLabelObj.SetText then endLongKeyLabelObj:SetText('End 길게누르기 (FOV 초기화)') end
            if pgdnKeyLabelObj.SetText then pgdnKeyLabelObj:SetText('PgDn 키 (카메라 이동)') end
            if pgdnLongKeyLabelObj.SetText then pgdnLongKeyLabelObj:SetText('PgDn 길게누르기 (공간 도약)') end
            if bracketKeyLabelObj.SetText then bracketKeyLabelObj:SetText('] 키 (머리 트래킹)') end
            if bracketLongKeyLabelObj.SetText then bracketLongKeyLabelObj:SetText('] 길게누르기 (TP 모드)') end
            showNotification("🌐 한국어 번역이 활성화되었습니다.")
        else
            if customItemLabel.SetText then customItemLabel:SetText("Custom Item") end
            if skinLabel.SetText then skinLabel:SetText("Skin") end
            if applyItemBtn.SetText then applyItemBtn:SetText("Apply Item") end
            if removeItemBtn.SetText then removeItemBtn:SetText("Remove Item") end
            if rtxTog.SetText then rtxTog:SetText("RTX Enhancements") end
            if skyboxLabel.SetText then skyboxLabel:SetText(skyboxLabelTextEn) end
            if shadowLabel.SetText then shadowLabel:SetText(shadowLabelTextEn) end
            if fogLabel.SetText then fogLabel:SetText(fogLabelTextEn) end
            if espLabelObj.SetText then espLabelObj:SetText('ESP (Player Highlight)') end
            if lockOnEspLabelObj.SetText then lockOnEspLabelObj:SetText('Lock-On Rainbow ESP') end
            if espNamesLabelObj.SetText then espNamesLabelObj:SetText('Display Names') end
            if killfeedShowLabelObj.SetText then killfeedShowLabelObj:SetText('Show Kill Feed') end
            if headTrackLabel.SetText then headTrackLabel:SetText('Precision Head Tracking') end
            if legitLockLabelObj and legitLockLabelObj.SetText then legitLockLabelObj:SetText('Lock-On (Legit Smooth Aim)') end
            if lockOnDistLabelObj and lockOnDistLabelObj.SetText then lockOnDistLabelObj:SetText('Lock-On Max Range (m)') end
            if resetLockOnDistBtn and resetLockOnDistBtn.SetText then resetLockOnDistBtn:SetText("Reset Lock-On Distance") end
            if headlessLabelObj.SetText then headlessLabelObj:SetText('Headless Mode') end
            if rmAccLabelObj.SetText then rmAccLabelObj:SetText('Remove Accessories') end
            if antiAfkLabelObj.SetText then antiAfkLabelObj:SetText('Anti-AFK (Anti-Kick)') end
            if leftNotifyLabelObj.SetText then leftNotifyLabelObj:SetText('Left notification') end
            if rightNotifyLabelObj.SetText then rightNotifyLabelObj:SetText('Right notification') end
            if hpBarToggleObj.SetText then hpBarToggleObj:SetText('HP Display') end
            if pingBarToggleObj.SetText then pingBarToggleObj:SetText('Ping Display') end
            if hubBarToggleObj.SetText then hubBarToggleObj:SetText('Smart Hub Display') end
            if barShowToggleObj.SetText then barShowToggleObj:SetText('Toggle Status Bar') end
            if menuKeybindLabelObj.SetText then menuKeybindLabelObj:SetText("Menu Keybind") end
            if menuScaleLabelObj.SetText then menuScaleLabelObj:SetText('Menu Scale') end
            if langToggleLabelObj.SetText then langToggleLabelObj:SetText('Korean') end
            if lockOnKeyLabelObj.SetText then lockOnKeyLabelObj:SetText('Lock-On Feature (MB3)') end
            if endKeyLabelObj.SetText then endKeyLabelObj:SetText('End Key (Freecam)') end
            if endLongKeyLabelObj.SetText then endLongKeyLabelObj:SetText('End Hold (FOV Reset)') end
            if pgdnKeyLabelObj.SetText then pgdnKeyLabelObj:SetText('PgDn Key (Move Camera)') end
            if pgdnLongKeyLabelObj.SetText then pgdnLongKeyLabelObj:SetText('PgDn Hold (Teleport)') end
            if bracketKeyLabelObj.SetText then bracketKeyLabelObj:SetText('] Key (Head Track)') end
            if bracketLongKeyLabelObj.SetText then bracketLongKeyLabelObj:SetText('] Hold (TP Mode)') end
            showNotification("🌐 English Language Enabled.", "🌐 English Language Enabled.")
        end
        updateRightSideBar()
    end,
})

-- -------------------------------------------------------------
-- 메인 RenderStepped 루프 (프리캠, 락온 에임, 머리 트래킹)
-- -------------------------------------------------------------
RunService.RenderStepped:Connect(function(deltaTime)
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- 1. 락온 트래킹 및 에임 보정
    if lockOnActive and lockOnTarget and lockOnTarget.Character then
        local tChar = lockOnTarget.Character
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        local targetPart = headLockActive and (tChar:FindFirstChild("Head") or tChar:FindFirstChild("HumanoidRootPart")) 
                           or (tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("Torso") or tChar:FindFirstChild("Head"))

        if tHum and tHum.Health > 0 and targetPart then
            -- 상대 HP Watermark 실시간 업데이트 (락온 상태일 때만 활성화/표시)
            if showHpBlock and showWatermarkUI and hpBlock then
                setBlockVisible(hpBlock, true)
                local currentHp = math.floor(tHum.Health)
                local maxHp = math.floor(tHum.MaxHealth)
                hpBlock:SetText(string.format("HP: %d / %d", currentHp, maxHp))
            end

            -- 실시간 거리 초과 체크
            local myChar = player.Character
            local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
            if myHrp then
                local dist = (myHrp.Position - targetPart.Position).Magnitude
                if dist > maxLockOnDistance then
                    lockOnActive = false
                    removeLockOnMarker()
                    lockOnTarget = nil
                    hpBlock:SetText("HP: - / -")
                    updateWatermarkVisibility()
                    showNotification("🎯 타겟이 사거리를 벗어나 락온이 해제되었습니다.", "🎯 Target out of range.")
                    return
                end
            end

            -- 락온 카메라 추적 로직
            if not freecamEnabled then
                if legitLockEnabled then
                    -- [자연스러운 락온 에임 개선]
                    -- 1박자 뒤쳐짐 방지: 이동 예측 보정 (AssemblyLinearVelocity)
                    local targetVel = targetPart.AssemblyLinearVelocity or targetPart.Velocity or Vector3.zero
                    local predictedPos = targetPart.Position + (targetVel * 0.038)
                    
                    -- 사람다운 미세 지터 오차 (자연스러움 유지 + 고명중률)
                    local humanJitter = Vector3.new(
                        math.sin(os.clock() * 12) * 0.08,
                        math.cos(os.clock() * 10) * 0.08,
                        0
                    )
                    predictedPos = predictedPos + humanJitter

                    -- 프레임 지연이 없는 유연하고 빠른 스무스 Lerp 에임
                    local currentCF = camera.CFrame
                    local targetCF = CFrame.new(currentCF.Position, predictedPos)
                    camera.CFrame = currentCF:Lerp(targetCF, math.clamp(deltaTime * 28, 0.25, 0.65))
                else
                    -- 일반 락온 (즉시 고정)
                    camera.CFrame = CFrame.new(camera.CFrame.Position, targetPart.Position)
                end
            end
        else
            lockOnActive = false
            removeLockOnMarker()
            lockOnTarget = nil
            hpBlock:SetText("HP: - / -")
            updateWatermarkVisibility()
            showNotification("🎯 타겟이 사망하여 락온이 해제되었습니다.", "🎯 Target died.")
        end
    else
        -- 락온 해제 상태에서는 HP 블록을 숨김 처리
        if showHpBlock and showWatermarkUI and hpBlock then
            setBlockVisible(hpBlock, false)
            if hpBlock.Text ~= "HP: - / -" then
                hpBlock:SetText("HP: - / -")
            end
        end
    end

    -- 2. 머리 정밀 트래킹 (Head Lock)
    if headLockActive and player.Character then
        local char = player.Character
        local neck = char:FindFirstChild("Neck", true)
        local head = char:FindFirstChild("Head")
        if neck and head then
            if not currentNeck then
                currentNeck = neck
                originalNeckC0 = neck.C0
            end
            local targetPos = nil
            if lockOnActive and lockOnTarget and lockOnTarget.Character then
                local tPart = lockOnTarget.Character:FindFirstChild("Head") or lockOnTarget.Character:FindFirstChild("HumanoidRootPart")
                if tPart then targetPos = tPart.Position end
            else
                local res = getMouseRaycast()
                if res and res.Position then targetPos = res.Position end
            end

            if targetPos then
                local neckWorldPos = head.Position
                local dir = (targetPos - neckWorldPos).Unit
                local localDir = neck.Parent.CFrame:VectorToObjectSpace(dir)
                local goalC0 = CFrame.new(originalNeckC0.Position) * CFrame.Angles(math.asin(localDir.Y), -math.atan2(localDir.X, -localDir.Z), 0)
                if not smoothNeckC0 then smoothNeckC0 = neck.C0 end
                smoothNeckC0 = smoothNeckC0:Lerp(goalC0, math.clamp(deltaTime * 15, 0.1, 0.5))
                neck.C0 = smoothNeckC0
            end
        end
    elseif currentNeck and originalNeckC0 then
        currentNeck.C0 = originalNeckC0
        currentNeck = nil
        originalNeckC0 = nil
        smoothNeckC0 = nil
    end

    -- 3. 프리캠 카메라 조작 업데이트
    if freecamEnabled then
        smoothYaw = smoothYaw + (yaw - smoothYaw) * math.clamp(deltaTime * lerpSpeed, 0, 1)
        smoothPitch = smoothPitch + (pitch - smoothPitch) * math.clamp(deltaTime * lerpSpeed, 0, 1)

        local moveVector = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, -1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, 1) end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(1, 0, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveVector = moveVector + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveVector = moveVector + Vector3.new(0, -1, 0) end

        local camRot = CFrame.Angles(0, math.rad(smoothYaw), 0) * CFrame.Angles(math.rad(smoothPitch), 0, 0)
        if moveVector.Magnitude > 0 then
            moveVector = moveVector.Unit
            local speed = baseSpeed
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed = speed * 2.5 end
            velocity = velocity + (camRot * moveVector * speed - velocity) * math.clamp(deltaTime * acceleration, 0, 1)
        else
            velocity = velocity * (1 - math.clamp(deltaTime * acceleration, 0, 1))
        end

        position = position + velocity * deltaTime
        camera.CFrame = CFrame.new(position) * camRot
        camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * math.clamp(deltaTime * fovLerpSpeed, 0, 1)
    end
end)

-- -------------------------------------------------------------
-- 키보드 / 마우스 입력 바인딩 처리
-- -------------------------------------------------------------
UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if freecamEnabled then
        -- 프리캠 마우스 회전 (화면 바라보기 이동) 처리
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Delta
            yaw = yaw - delta.X * sensitivity
            pitch = math.clamp(pitch - delta.Y * sensitivity, -89, 89)
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            targetFov = math.clamp(targetFov - (input.Position.Z * 6), 15, 120)
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    local key = input.KeyCode

    if key == Enum.KeyCode.RightShift then
        task.spawn(function()
            task.wait()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end)
    end

    local isHotkey = (key == minimizeKeybind) or (key == Enum.KeyCode.PageDown) or (key == Enum.KeyCode.End) or (key == Enum.KeyCode.R) or (key == Enum.KeyCode.F) or (key == Enum.KeyCode.Z) or (key == Enum.KeyCode.X) or (key == Enum.KeyCode.C) or (key == Enum.KeyCode.V) or (key == Enum.KeyCode.One) or (key == Enum.KeyCode.Two) or (key == Enum.KeyCode.T) or (key == Enum.KeyCode.RightBracket) or (input.UserInputType == Enum.UserInputType.MouseButton3) or (input.UserInputType == Enum.UserInputType.MouseButton1) or (freecamEnabled and pingModeActive and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2))

    if gameProcessed and not isHotkey then return end

    if key == minimizeKeybind then
        if freecamEnabled then return end
        inputState.Del = true
    end

    if key == Enum.KeyCode.End then
        inputState.End = true
        task.delay(0.4, function()
            if inputState.End == true then
                inputState.End = "LongPressed"
                if not keyStates.EndLong then
                    return
                end
                if freecamEnabled then
                    targetFov = 70
                    showNotification("🔍 FOV가 70으로 초기화되었습니다.", "🔍 FOV reset to 70.") playSound(8503529139, 1, 1)
                end
            end
        end)
    end

    if key == Enum.KeyCode.RightBracket then
        inputState.RightBracket = true
        task.delay(0.4, function()
            if inputState.RightBracket == true then
                inputState.RightBracket = "LongPressed"
                if not keyStates.RightBracketLong then
                    return
                end
                if lockOnActive then
                    showNotification("⚠️ 락온 상태에서는 TP 모드를 켤 수 없습니다.", "⚠️ Cannot enable TP mode while Lock-On is active.")
                    playSound(8503529139, 1, 0.8)
                    return
                end

                tpModeActive = not tpModeActive
                if tpModeActive then
                    showNotification("🌀 TP 모드가 활성화되었습니다. (마우스 휠클릭으로 이동)", "🌀 TP Mode Enabled. (Click Wheel to TP)")
                    playSound(8503529139, 1, 1.2)
                else
                    showNotification("🚫 TP 모드가 해제되었습니다.", "🚫 TP Mode Disabled.")
                    playSound(8503529139, 1, 0.8)
                end
            end
        end)
    end

    if input.UserInputType == Enum.UserInputType.MouseButton3 then
        if tpModeActive then
            local res = getMouseRaycast()
            if res and res.Position then
                local targetPos = res.Position + Vector3.new(0, 3, 0)
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = CFrame.new(targetPos)
                    playSound(130845581077634, 2, 1)
                    showNotification("🌀 마우스 커서 위치로 텔레포트했습니다.", "🌀 Teleported to mouse position.")
                end
            end
            return
        end
        
        if freecamEnabled then showNotification("⚠️ 프리캠 작동 중에는 사용할 수 없습니다.", "⚠️ Unavailable during Freecam.") return end

        if not keyStates.LockOn then
            return
        end

        toggleLockOn()
    end

    if key == Enum.KeyCode.PageDown then
        inputState.PgDn = true
        task.delay(0.4, function()
            if inputState.PgDn == true then
                inputState.PgDn = "LongPressed"
                if not keyStates.PgDnLong then
                    return
                end
                if freecamEnabled then
                    local character = player.Character
                    if character and character:FindFirstChild("HumanoidRootPart") then
                        local hrp = character.HumanoidRootPart
                        local targetPos = position
                        
                        local targetCFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.rad(smoothYaw), 0)
                        hrp.CFrame = targetCFrame
                        
                        showNotification("⚡ 공간 도약 완료!", "⚡ Teleported to camera!")
                        disableFreecam(true)
                    end
                else
                    showNotification("⚠️ 프리캠이 켜진 상태에서만 공간 도약이 가능합니다.", "⚠️ Freecam must be enabled.")
                end
            end
        end)
    end

    if freecamEnabled then
        if key == Enum.KeyCode.One then
            baseSpeed = math.min(baseSpeed + 20, 500)
            showNotification("🚀 프리캠 속도 증가: " .. baseSpeed, "🚀 Freecam Speed Increased: " .. baseSpeed)
        elseif key == Enum.KeyCode.Two then
            baseSpeed = math.max(baseSpeed - 20, 10)
            showNotification("🐢 프리캠 속도 감소: " .. baseSpeed, "🐢 Freecam Speed Decreased: " .. baseSpeed)
        elseif key == Enum.KeyCode.T then
            baseSpeed = 50
            showNotification("🔄 프리캠 속도 초기화: " .. baseSpeed, "🔄 Freecam Speed Reset: " .. baseSpeed)
        elseif key == Enum.KeyCode.F then
            if not pingModeActive and not blockModeActive then
                pingModeActive = true blockModeActive = false crosshair.Visible = true
                showNotification("📍 핑 모드가 활성화되었습니다. [R: 블록/핑 모드 전환 | F: 모드 종료]", "📍 Ping Mode Enabled.") playSound(8503529139, 1, 1.2) updateRightSideBar() updateMouseState()
            else
                pingModeActive = false blockModeActive = false crosshair.Visible = false
                showNotification("🚫 가상 인프라 모드가 종료되었습니다.", "🚫 Infrastructure Mode Ended.") playSound(8503529139, 1, 0.8) updateRightSideBar() updateMouseState()
            end
        elseif key == Enum.KeyCode.R then
            if pingModeActive then
                pingModeActive = false blockModeActive = true crosshair.Visible = true
                showNotification("🧱 블록 조작 모드가 활성화되었습니다. [Z: 삭제 / X: 실행취소 / C: 다시실행 / R: 핑 모드 전환 / F: 모드 종료]", "🧱 Block Mode Enabled.") playSound(8503529139, 1, 1.2) updateRightSideBar() updateMouseState()
            elseif blockModeActive then
                blockModeActive = false pingModeActive = true crosshair.Visible = true
                showNotification("📍 핑 모드가 활성화되었습니다. [R: 블록/핑 모드 전환 | F: 모드 종료]", "📍 Ping Mode Enabled.") playSound(8503529139, 1, 1.2) updateRightSideBar() updateMouseState()
            end
        end
    end

    if freecamEnabled and blockModeActive then
        if key == Enum.KeyCode.Z then
            deleteTargetBlock()
        elseif key == Enum.KeyCode.X then
            undoAction()
        elseif key == Enum.KeyCode.C then
            redoAction()
        elseif key == Enum.KeyCode.V then
            showNotification("🧱 삭제된 가상 블록 수: " .. #undoStack, "🧱 Deleted blocks count: " .. #undoStack)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode

    if key == Enum.KeyCode.End then
        if inputState.End == true then
            if not keyStates.End then
                return
            end
            if freecamEnabled then disableFreecam(false) else enableFreecam() end
        end
        inputState.End = false
    elseif key == Enum.KeyCode.PageDown then
        if inputState.PgDn == true then
            -- PgDn 짧게 누르기: 카메라를 내 캐릭터 위치로 즉시 이동
            if keyStates.PgDn and freecamEnabled then
                local char = player.Character
                local targetPart = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
                if targetPart then
                    position = targetPart.Position
                    showNotification("📷 카메라가 내 캐릭터 위치로 이동했습니다.", "📷 Camera moved to player position.")
                    playSound(8503529139, 1, 1)
                end
            end
        end
        inputState.PgDn = false
    elseif key == Enum.KeyCode.RightBracket then
        if inputState.RightBracket == true then
            if not keyStates.RightBracket then
                return
            end
            headLockActive = not headLockActive
            if headLockActive then
                showNotification("👀 캐릭터 머리 트래킹 활성화", "👀 Head Tracking Enabled") playSound(8503529139, 1, 1.2)
            else
                showNotification("🚫 캐릭터 머리 트래킹 해제", "🚫 Head Tracking Disabled") playSound(8503529139, 1, 0.8)
            end
        end
        inputState.RightBracket = false
    end
end)
