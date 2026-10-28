--[[
    tetoMIDI v2.2 - Liquid Glass UI
    Intro + Floating Bubble (real image) + Auto Player + Custom Song + midi2lua Hub + Discord + tiếng click
    
    HƯỚNG DẪN:
    1. Upload cả folder này lên GitHub (public repo)
    2. Sửa dòng GITHUB_USER và GITHUB_REPO bên dưới cho đúng
    3. Script sẽ tự load ảnh từ GitHub
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

-- ====================== CẤU HÌNH GITHUB ======================
local GITHUB_USER = "talentless-custom-song"
local GITHUB_REPO = "hu"

-- Link server Discord (bấm logo Discord sẽ copy link này)
local DISCORD_LINK = "https://discord.gg/peaqm6uqgB"

-- Server midi2lua hub (hub_server trên PythonAnywhere): bot Discord upload bài lên đây qua API
local HUB_API = "https://midi2lua.pythonanywhere.com"
local HUB_DIR = "tetoMIDI/hub"

local IMAGE_DIR = "tetoMIDI/images"
local IMAGE_FILES = { "logo.png", "icon_auto.png", "icon_custom.png", "discord.png" }
-- Ảnh không bắt buộc: thiếu thì UI vẫn chạy bình thường, không báo lỗi
local OPTIONAL_IMAGES = { ["discord.png"] = true }
local imageCache = {}

-- Nguồn tải ảnh (thử lần lượt, cái nào được thì dùng)
local function imageUrls(name)
    return {
        string.format("https://cdn.jsdelivr.net/gh/%s/%s@main/images/%s", GITHUB_USER, GITHUB_REPO, name),
        string.format("https://raw.githubusercontent.com/%s/%s/main/images/%s", GITHUB_USER, GITHUB_REPO, name),
    }
end

local function httpGetRaw(url)
    -- Cách 1: game:HttpGet
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" and #res > 0 then return res end
    -- Cách 2: request của executor
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        local ok2, r = pcall(req, { Url = url, Method = "GET" })
        if ok2 and type(r) == "table" and r.StatusCode == 200 and type(r.Body) == "string" and #r.Body > 0 then
            return r.Body
        end
    end
    return nil
end

-- File PNG hợp lệ phải bắt đầu bằng "\137PNG" (tránh lưu nhầm trang lỗi 404 HTML)
local function isPng(data)
    return type(data) == "string" and #data > 100 and data:sub(2, 4) == "PNG"
end

local function getAsset(path)
    local fn = getcustomasset or getsynasset
    if not fn then return "" end
    local ok, id = pcall(fn, path)
    if ok and id and id ~= "" then return id end
    return ""
end

-- Tải 1 ảnh về workspace rồi trả về asset id dùng được cho ImageLabel
local function loadImage(name)
    if imageCache[name] then return imageCache[name] end
    if not (writefile and isfile and readfile and (getcustomasset or getsynasset)) then
        warn("[tetoMIDI] Executor không hỗ trợ getcustomasset -> không hiện được ảnh")
        return ""
    end

    pcall(function()
        if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
        if isfolder and not isfolder(IMAGE_DIR) then makefolder(IMAGE_DIR) end
    end)

    local path = IMAGE_DIR .. "/" .. name

    -- Dùng lại file đã tải nếu còn nguyên vẹn
    if isfile(path) then
        local okRead, data = pcall(readfile, path)
        if okRead and isPng(data) then
            local id = getAsset(path)
            if id ~= "" then imageCache[name] = id; return id end
        end
    end

    for _, url in ipairs(imageUrls(name)) do
        local data = httpGetRaw(url)
        if isPng(data) then
            local okW = pcall(writefile, path, data)
            if okW then
                local id = getAsset(path)
                if id ~= "" then imageCache[name] = id; return id end
            end
        end
    end

    if not OPTIONAL_IMAGES[name] then
        warn("[tetoMIDI] Không tải được ảnh: " .. name .. " (kiểm tra repo Public + file trong images/)")
    end
    return ""
end

-- Tải trước toàn bộ ảnh song song, chờ tối đa `timeout` giây
-- `onDone(name)` được gọi mỗi khi tải xong 1 ảnh (để intro cập nhật %)
local function preloadImages(timeout, onDone)
    local pending = #IMAGE_FILES
    for _, name in ipairs(IMAGE_FILES) do
        task.spawn(function()
            loadImage(name)
            pending = pending - 1
            if onDone then pcall(onDone, name) end
        end)
    end
    local t = 0
    while pending > 0 and t < (timeout or 10) do
        task.wait(0.1)
        t = t + 0.1
    end
end

-- Lấy ảnh đã cache (gọi sau preloadImages). Chưa có thì thử tải luôn.
local function getImage(name)
    return imageCache[name] or loadImage(name)
end

-- ====================== TIẾNG CLICK CHUỘT ======================
-- File nằm ở sounds/click.mp3 trong repo (tải về tetoMIDI/sounds/ như ảnh).
-- Tải không được thì dùng ID dự phòng của Roblox.
local SOUND_DIR = "tetoMIDI/sounds"
local CLICK_FILE = "click.mp3"
local CLICK_FALLBACK = "rbxassetid://421058925"
local CLICK_VOLUME = 0.75
local clickId = nil
local clickLoadStarted = false

local function soundUrls(name)
    return {
        string.format("https://cdn.jsdelivr.net/gh/%s/%s@main/sounds/%s", GITHUB_USER, GITHUB_REPO, name),
        string.format("https://raw.githubusercontent.com/%s/%s/main/sounds/%s", GITHUB_USER, GITHUB_REPO, name),
    }
end

-- mp3 hợp lệ bắt đầu bằng "ID3" hoặc byte sync 0xFF (tránh lưu nhầm trang lỗi 404 HTML)
local function isMp3(data)
    if type(data) ~= "string" or #data < 200 then return false end
    return data:sub(1, 3) == "ID3" or data:byte(1) == 0xFF
end

local function loadClickSound()
    if clickLoadStarted then return end
    clickLoadStarted = true
    if not (writefile and isfile and readfile and (getcustomasset or getsynasset)) then return end

    pcall(function()
        if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
        if isfolder and not isfolder(SOUND_DIR) then makefolder(SOUND_DIR) end
    end)

    local path = SOUND_DIR .. "/" .. CLICK_FILE
    if isfile(path) then
        local okRead, data = pcall(readfile, path)
        if okRead and isMp3(data) then
            local id = getAsset(path)
            if id ~= "" then clickId = id; return end
        end
    end

    for _, url in ipairs(soundUrls(CLICK_FILE)) do
        local data = httpGetRaw(url)
        if isMp3(data) and pcall(writefile, path, data) then
            local id = getAsset(path)
            if id ~= "" then clickId = id; return end
        end
    end
end

-- Phát 1 tiếng click (tạo Sound mới mỗi lần để bấm liên tục vẫn kêu chồng được)
local function playClick()
    local snd = Instance.new("Sound")
    snd.Name = "TetoClick"
    snd.SoundId = clickId or CLICK_FALLBACK
    snd.Volume = CLICK_VOLUME
    snd.PlaybackSpeed = 0.96 + math.random() * 0.08   -- lệch nhẹ mỗi lần cho tự nhiên
    snd.Parent = SoundService
    snd:Play()
    task.delay(1.5, function() snd:Destroy() end)
end

-- Gắn tiếng click vào nút: kêu ngay lúc nhấn xuống (chuột hoặc chạm)
local function bindClick(btn)
    btn.MouseButton1Down:Connect(playClick)
end

-- ====================== MIDI2LUA HUB (API) ======================
local hubThumbCache = {}

-- Danh sách bài: {id, name, link, has_thumb, created}
local function hubFetchList()
    local body = httpGetRaw(HUB_API .. "/api/lua/list")
    if type(body) ~= "string" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok and type(data) == "table" then return data end
    return nil
end

-- Nội dung script midi2lua của 1 bài
local function hubFetchScript(id)
    local body = httpGetRaw(HUB_API .. "/api/lua/script/" .. tostring(id))
    if type(body) == "string" and #body > 20 then return body end
    return nil
end

-- Thumbnail PNG: tải về tetoMIDI/hub/<id>.png rồi trả asset id (như logo)
local function hubThumb(id)
    if hubThumbCache[id] then return hubThumbCache[id] end
    if not (writefile and isfile and readfile and (getcustomasset or getsynasset)) then return "" end

    pcall(function()
        if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
        if isfolder and not isfolder(HUB_DIR) then makefolder(HUB_DIR) end
    end)

    local path = HUB_DIR .. "/" .. tostring(id) .. ".png"
    if isfile(path) then
        local okRead, data = pcall(readfile, path)
        if okRead and isPng(data) then
            local asset = getAsset(path)
            if asset ~= "" then hubThumbCache[id] = asset; return asset end
        end
    end

    local data = httpGetRaw(HUB_API .. "/api/lua/thumb/" .. tostring(id))
    if isPng(data) and pcall(writefile, path, data) then
        local asset = getAsset(path)
        if asset ~= "" then hubThumbCache[id] = asset; return asset end
    end
    return ""
end

-- ====================== DATA ======================
local SongList = {}
local CurrentPage = "auto"
local MainVisible = true

pcall(function()
    if isfolder and not isfolder("tetoMIDI") then
        makefolder("tetoMIDI")
    end
    if isfile and isfile("tetoMIDI/customs.json") then
        local data = HttpService:JSONDecode(readfile("tetoMIDI/customs.json"))
        for _, v in ipairs(data) do
            table.insert(SongList, v)
        end
    end
end)

local function saveCustoms()
    pcall(function()
        if isfolder and not isfolder("tetomidi2lua") then
            makefolder("tetomidi2lua")
        end
        if not isfolder("tetoMIDI") then
            makefolder("tetoMIDI")
        end
        writefile("tetoMIDI/customs.json", HttpService:JSONEncode(SongList))
    end)
end

-- ====================== INTRO (laptop gõ lệnh -> logo, tổng 7 giây) ======================
-- Timeline (giây):
--   0.00 - 0.35  nền hiện lên
--   0.35 - 1.30  nắp laptop mở
--   1.50 - 2.80  gõ "pip install tetomidi"
--   3.15 - 3.40  enter, hiện 2 dòng kết quả
--   3.80 - 4.45  laptop zoom + tan, biến thành logo
--   3.95 - 6.35  logo, tên, thanh loading
--   6.35 - 7.00  outro (flash + fade) rồi vào UI chính
local INTRO_TOTAL = 7
local INTRO_OUTRO = 0.65
local INSTALL_CMD = "pip install tetomidi"
local LAPTOP_FILL_X = 0.5    -- laptop chiếm tối đa 50% chiều ngang màn hình
local LAPTOP_FILL_Y = 0.5    -- laptop chiếm tối đa 50% chiều dọc màn hình
local LAPTOP_K_MAX  = 1.35   -- chặn trần để màn hình lớn (PC) laptop cũng không phình to

local function createIntro()
    local introGui = Instance.new("ScreenGui")
    introGui.Name = "TetoMIDI_Intro"
    introGui.IgnoreGuiInset = true
    introGui.DisplayOrder = 9999
    introGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    introGui.Parent = CoreGui

    -- Stage dùng CanvasGroup để fade toàn bộ intro cùng lúc
    local stage = Instance.new("CanvasGroup")
    stage.Size = UDim2.new(1, 0, 1, 0)
    stage.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    stage.BorderSizePixel = 0
    stage.GroupTransparency = 1
    stage.Parent = introGui

    local stageScale = Instance.new("UIScale")
    stageScale.Scale = 1
    stageScale.Parent = stage

    -- ============ PHẦN 1: LAPTOP ============
    -- Laptop thiết kế gốc 330x188, phóng theo hệ số K để lấp gần đầy màn hình
    -- Lấy kích thước màn hình THẬT từ camera (AbsoluteSize của ScreenGui trong
    -- một số executor trả về giá trị cũ/sai -> laptop bị nhỏ giữa màn hình)
    local cam0 = workspace.CurrentCamera
    local vp = (cam0 and cam0.ViewportSize) or Vector2.new(0, 0)
    if vp.X < 100 or vp.Y < 100 then
        vp = introGui.AbsoluteSize
    end
    if vp.X < 100 or vp.Y < 100 then
        vp = Vector2.new(800, 400)
    end
    local K = math.clamp(math.min(vp.X * LAPTOP_FILL_X / 330, vp.Y * LAPTOP_FILL_Y / 188), 0.6, LAPTOP_K_MAX)
    local function s(n)
        return math.floor(n * K + 0.5)
    end

    local laptop = Instance.new("CanvasGroup")
    laptop.AnchorPoint = Vector2.new(0.5, 0.5)
    laptop.Size = UDim2.new(0, s(330), 0, s(188))
    laptop.Position = UDim2.new(0.5, 0, 0.5, -32 + s(6))   -- tâm màn hình laptop trùng tâm logo
    laptop.BackgroundTransparency = 1
    laptop.BorderSizePixel = 0
    laptop.ZIndex = 1
    laptop.Parent = stage

    local laptopScale = Instance.new("UIScale")
    laptopScale.Scale = 0.88
    laptopScale.Parent = laptop

    -- Đế laptop (bàn phím)
    local base = Instance.new("Frame")
    base.AnchorPoint = Vector2.new(0.5, 1)
    base.Size = UDim2.new(0, s(330), 0, s(12))
    base.Position = UDim2.new(0.5, 0, 1, 0)
    base.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
    base.BorderSizePixel = 0
    base.Parent = laptop
    Instance.new("UICorner", base).CornerRadius = UDim.new(0, s(6))

    local baseGradient = Instance.new("UIGradient")
    baseGradient.Color = ColorSequence.new(Color3.fromRGB(228, 228, 228), Color3.fromRGB(135, 135, 135))
    baseGradient.Rotation = 90
    baseGradient.Parent = base

    -- Nửa trên của đế vuông góc: lấp 2 góc trên (nắp khít sát đế, không hở 2 bên)
    local baseTop = Instance.new("Frame")
    baseTop.Size = UDim2.new(1, 0, 0, s(6))
    baseTop.Position = UDim2.new(0, 0, 0, 0)
    baseTop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    baseTop.BorderSizePixel = 0
    baseTop.Parent = base
    local baseTopGradient = Instance.new("UIGradient")
    baseTopGradient.Color = ColorSequence.new(Color3.fromRGB(228, 228, 228), Color3.fromRGB(181, 181, 181))
    baseTopGradient.Rotation = 90
    baseTopGradient.Parent = baseTop

    -- Rãnh mở nắp ở giữa đế
    local notch = Instance.new("Frame")
    notch.AnchorPoint = Vector2.new(0.5, 0)
    notch.Size = UDim2.new(0, s(64), 0, s(3))
    notch.Position = UDim2.new(0.5, 0, 0, 0)
    notch.BackgroundColor3 = Color3.fromRGB(95, 95, 95)
    notch.BorderSizePixel = 0
    notch.Parent = base
    Instance.new("UICorner", notch).CornerRadius = UDim.new(0, s(2))

    -- Nắp laptop: neo ở mép dưới (bản lề), mở bằng cách tăng chiều cao + thu hẹp chiều rộng nhẹ
    local lid = Instance.new("Frame")
    lid.AnchorPoint = Vector2.new(0.5, 1)
    lid.Size = UDim2.new(0, s(330), 0, s(4))      -- rộng đúng bằng đế: 2 bên kín hoàn toàn
    lid.Position = UDim2.new(0.5, 0, 1, -s(12))
    lid.BackgroundColor3 = Color3.fromRGB(215, 215, 215)
    lid.BorderSizePixel = 0
    lid.ClipsDescendants = true
    lid.Parent = laptop
    Instance.new("UICorner", lid).CornerRadius = UDim.new(0, s(10))

    local lidGradient = Instance.new("UIGradient")
    lidGradient.Color = ColorSequence.new(Color3.fromRGB(232, 232, 232), Color3.fromRGB(150, 150, 150))
    lidGradient.Rotation = 90
    lidGradient.Parent = lid

    -- Dải bản lề vuông góc ở đáy nắp: bo góc chỉ còn ở phía trên, đáy nắp liền khít với đế
    local hinge = Instance.new("Frame")
    hinge.AnchorPoint = Vector2.new(0, 1)
    hinge.Size = UDim2.new(1, 0, 0, s(12))
    hinge.Position = UDim2.new(0, 0, 1, 0)
    hinge.BackgroundColor3 = Color3.fromRGB(152, 152, 152)
    hinge.BorderSizePixel = 0
    hinge.Parent = lid

    -- Camera nhỏ trên viền màn hình
    local cam = Instance.new("Frame")
    cam.AnchorPoint = Vector2.new(0.5, 0)
    cam.Size = UDim2.new(0, s(4), 0, s(4))
    cam.Position = UDim2.new(0.5, 0, 0, s(4))
    cam.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    cam.BorderSizePixel = 0
    cam.Visible = false
    cam.Parent = lid
    Instance.new("UICorner", cam).CornerRadius = UDim.new(1, 0)

    -- Màn hình đen bên trong nắp
    local screen = Instance.new("Frame")
    screen.Position = UDim2.new(0, s(8), 0, s(12))
    screen.Size = UDim2.new(1, -s(16), 1, -s(20))
    screen.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    screen.BorderSizePixel = 0
    screen.ClipsDescendants = true
    screen.Visible = false
    screen.Parent = lid
    Instance.new("UICorner", screen).CornerRadius = UDim.new(0, s(5))

    -- Terminal
    local term = Instance.new("TextLabel")
    term.Position = UDim2.new(0, s(10), 0, s(10))
    term.Size = UDim2.new(1, -s(20), 1, -s(20))
    term.BackgroundTransparency = 1
    term.Font = Enum.Font.Code
    term.TextSize = math.clamp(s(12), 10, 100)
    term.TextColor3 = Color3.fromRGB(235, 235, 235)
    term.TextXAlignment = Enum.TextXAlignment.Left
    term.TextYAlignment = Enum.TextYAlignment.Top
    term.RichText = true
    term.Text = ""
    term.Parent = screen

    -- Lớp sáng trắng phủ màn hình lúc laptop biến thành logo
    local screenFlash = Instance.new("Frame")
    screenFlash.Size = UDim2.new(1, 0, 1, 0)
    screenFlash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    screenFlash.BackgroundTransparency = 1
    screenFlash.BorderSizePixel = 0
    screenFlash.ZIndex = 2
    screenFlash.Parent = screen

    -- ============ PHẦN 2: LOGO + LOADING ============
    -- Gom tất cả vào 1 CanvasGroup để hiện ra cùng lúc khi laptop tan
    local content = Instance.new("CanvasGroup")
    content.Size = UDim2.new(1, 0, 1, 0)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.GroupTransparency = 1
    content.ZIndex = 2
    content.Parent = stage

    -- Hào quang mờ phía sau logo
    local halo = Instance.new("Frame")
    halo.AnchorPoint = Vector2.new(0.5, 0.5)
    halo.Size = UDim2.new(0, 260, 0, 260)
    halo.Position = UDim2.new(0.5, 0, 0.5, -30)
    halo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    halo.BackgroundTransparency = 0.95
    halo.BorderSizePixel = 0
    halo.Parent = content
    Instance.new("UICorner", halo).CornerRadius = UDim.new(1, 0)

    -- Card chứa logo.png (nốt nhạc + phím piano)
    local logoFrame = Instance.new("Frame")
    logoFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    logoFrame.Size = UDim2.new(0, 118, 0, 118)
    logoFrame.Position = UDim2.new(0.5, 0, 0.5, -32)
    logoFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
    logoFrame.BackgroundTransparency = 0.05
    logoFrame.BorderSizePixel = 0
    logoFrame.Parent = content
    Instance.new("UICorner", logoFrame).CornerRadius = UDim.new(0, 26)

    local logoStroke = Instance.new("UIStroke")
    logoStroke.Color = Color3.fromRGB(255, 255, 255)
    logoStroke.Transparency = 0.55
    logoStroke.Thickness = 1.5
    logoStroke.Parent = logoFrame

    local logoScale = Instance.new("UIScale")
    logoScale.Scale = 0.5
    logoScale.Parent = logoFrame

    local logo = Instance.new("ImageLabel")
    logo.Size = UDim2.new(1, 0, 1, 0)
    logo.Position = UDim2.new(0, 0, 0, 0)
    logo.BackgroundTransparency = 1
    logo.Image = ""
    logo.ScaleType = Enum.ScaleType.Crop
    logo.Parent = logoFrame
    Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 26)

    -- Chữ dự phòng nếu ảnh tải thất bại
    local logoFallback = Instance.new("TextLabel")
    logoFallback.Size = UDim2.new(1, 0, 1, 0)
    logoFallback.BackgroundTransparency = 1
    logoFallback.Text = "♪"
    logoFallback.TextColor3 = Color3.fromRGB(255, 255, 255)
    logoFallback.Font = Enum.Font.GothamBold
    logoFallback.TextSize = 44
    logoFallback.Visible = false
    logoFallback.Parent = logoFrame

    -- Tên
    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Size = UDim2.new(0, 320, 0, 28)
    title.Position = UDim2.new(0.5, 0, 0.5, 38)
    title.BackgroundTransparency = 1
    title.Text = "TetoMIDI"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.TextTransparency = 1
    title.Parent = content

    -- Dòng trạng thái
    local status = Instance.new("TextLabel")
    status.AnchorPoint = Vector2.new(0.5, 0)
    status.Size = UDim2.new(0, 320, 0, 16)
    status.Position = UDim2.new(0.5, 0, 0.5, 66)
    status.BackgroundTransparency = 1
    status.Text = "loading assets..."
    status.TextColor3 = Color3.fromRGB(150, 150, 150)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextTransparency = 1
    status.Parent = content

    -- Thanh loading (gradient + shine chạy)
    local barBg = Instance.new("Frame")
    barBg.AnchorPoint = Vector2.new(0.5, 0)
    barBg.Size = UDim2.new(0, 220, 0, 5)
    barBg.Position = UDim2.new(0.5, 0, 0.5, 96)
    barBg.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
    barBg.BorderSizePixel = 0
    barBg.Parent = content
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bar.BorderSizePixel = 0
    bar.ClipsDescendants = true
    bar.Parent = barBg
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local barGradient = Instance.new("UIGradient")
    barGradient.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90), Color3.fromRGB(255, 255, 255))
    barGradient.Parent = bar

    -- Vệt sáng lướt trên thanh bar
    local shine = Instance.new("Frame")
    shine.Size = UDim2.new(1, 0, 1, 0)
    shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    shine.BorderSizePixel = 0
    shine.Parent = bar
    local shineGradient = Instance.new("UIGradient")
    shineGradient.Rotation = 20
    shineGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,    1),
        NumberSequenceKeypoint.new(0.40, 1),
        NumberSequenceKeypoint.new(0.50, 0),
        NumberSequenceKeypoint.new(0.60, 1),
        NumberSequenceKeypoint.new(1,    1),
    })
    shineGradient.Parent = shine
    shineGradient.Offset = Vector2.new(-1, 0)

    -- Viền sáng quanh thanh bar (glow nhẹ)
    local barGlow = Instance.new("UIStroke")
    barGlow.Color = Color3.fromRGB(255, 255, 255)
    barGlow.Transparency = 0.75
    barGlow.Thickness = 1
    barGlow.Parent = barBg

    local percent = Instance.new("TextLabel")
    percent.AnchorPoint = Vector2.new(0.5, 0)
    percent.Size = UDim2.new(0, 100, 0, 18)
    percent.Position = UDim2.new(0.5, 0, 0.5, 108)
    percent.BackgroundTransparency = 1
    percent.Text = "0%"
    percent.TextColor3 = Color3.fromRGB(170, 170, 170)
    percent.Font = Enum.Font.GothamMedium
    percent.TextSize = 12
    percent.TextTransparency = 1
    percent.Parent = content

    -- ============ ĐIỀU PHỐI THEO MỐC THỜI GIAN ============
    task.spawn(function()
        local t0 = os.clock()
        local function waitUntil(t)
            local d = t0 + t - os.clock()
            if d > 0 then task.wait(d) end
        end
        local function tween(obj, dur, style, dir, props)
            local tw = TweenService:Create(obj, TweenInfo.new(dur, style, dir), props)
            tw:Play()
            return tw
        end

        local QUAD, SINE, BACK, LINEAR = Enum.EasingStyle.Quad, Enum.EasingStyle.Sine, Enum.EasingStyle.Back, Enum.EasingStyle.Linear
        local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

        local introAlive = true
        local laptopAlive = true

        -- Tải ảnh chạy ngầm ngay từ giây 0 (trong lúc laptop đang diễn)
        local total = #IMAGE_FILES
        local loaded = 0
        local preloadDone = false

        local function applyLogo()
            local iconId = getImage("logo.png")
            if iconId ~= "" then
                logo.Image = iconId
                logoFallback.Visible = false
            else
                logoFallback.Visible = true
            end
        end

        task.spawn(loadClickSound)

        task.spawn(function()
            preloadImages(10, function(name)
                loaded = loaded + 1
                status.Text = string.format("loading assets... (%d/%d)", loaded, total)
            end)
            preloadDone = true
            applyLogo()
        end)

        -- Terminal: dòng lệnh + 2 dòng kết quả + prompt mới
        local typedCount = 0
        local cursorOn = true
        local lines = {}
        local PROMPT = '<font color="#8c8c8c">$</font> '
        local function render()
            local cursor = cursorOn and "_" or " "
            local out = {}
            out[1] = PROMPT .. INSTALL_CMD:sub(1, typedCount) .. ((#lines == 0) and cursor or "")
            for _, l in ipairs(lines) do
                out[#out + 1] = l
            end
            if #lines >= 2 then
                out[#out + 1] = PROMPT .. cursor
            end
            term.Text = table.concat(out, "\n")
        end

        -- 1) Nền hiện lên, laptop nhô lên nhẹ
        tween(stage, 0.35, QUAD, OUT, {GroupTransparency = 0})
        tween(laptopScale, 1.2, QUAD, OUT, {Scale = 1})

        -- 2) Mở nắp laptop
        waitUntil(0.35)
        tween(lid, 0.95, QUAD, OUT, {Size = UDim2.new(0, s(330), 0, s(176))})
        waitUntil(0.5)
        screen.Visible = true
        cam.Visible = true
        render()
        task.spawn(function()
            while laptopAlive do
                task.wait(0.45)
                cursorOn = not cursorOn
                render()
            end
        end)

        -- 3) Tự gõ "pip install tetomidi"
        waitUntil(1.5)
        local typedValue = Instance.new("NumberValue")
        typedValue.Value = 0
        typedValue.Changed:Connect(function(v)
            local n = math.floor(v + 0.5)
            if n ~= typedCount then
                typedCount = n
                cursorOn = true
                render()
            end
        end)
        tween(typedValue, 1.3, LINEAR, OUT, {Value = #INSTALL_CMD})

        -- 4) Enter -> kết quả cài đặt
        waitUntil(3.15)
        typedCount = #INSTALL_CMD
        lines[1] = '<font color="#8c8c8c">Collecting tetomidi</font>'
        render()
        waitUntil(3.4)
        lines[2] = 'Successfully installed tetomidi'
        render()

        -- 5) Laptop biến thành intro: màn hình sáng lên, zoom vào rồi tan
        waitUntil(3.8)
        tween(screenFlash, 0.25, QUAD, OUT, {BackgroundTransparency = 0.55})
        tween(laptopScale, 0.65, QUAD, IN, {Scale = 2.2})
        task.delay(0.2, function()
            tween(laptop, 0.45, QUAD, IN, {GroupTransparency = 1})
        end)

        -- Logo bật lên đúng chỗ màn hình laptop vừa tan
        waitUntil(3.95)
        if not preloadDone then
            logoFallback.Visible = true
        end
        tween(content, 0.45, QUAD, OUT, {GroupTransparency = 0})
        tween(logoScale, 0.6, BACK, OUT, {Scale = 1})

        -- Hiệu ứng nền chạy song song: halo thở + logo lơ lửng + shine lướt
        task.spawn(function()
            local t = 0
            while introAlive do
                t = t + task.wait()
                local pulse = math.sin(t * 2) * 0.5 + 0.5
                halo.Size = UDim2.new(0, 250 + pulse * 22, 0, 250 + pulse * 22)
                halo.BackgroundTransparency = 0.96 - pulse * 0.035
                logoFrame.Position = UDim2.new(0.5, 0, 0.5, -32 + math.sin(t * 1.4) * 4)
            end
        end)
        task.spawn(function()
            while introAlive do
                shineGradient.Offset = Vector2.new(-1, 0)
                local tw = TweenService:Create(shineGradient, TweenInfo.new(1.1, Enum.EasingStyle.Linear), {Offset = Vector2.new(1, 0)})
                tw:Play()
                tw.Completed:Wait()
            end
        end)

        waitUntil(4.1)
        tween(title, 0.4, QUAD, OUT, {TextTransparency = 0})

        -- % mượt bằng NumberValue: chạy 0 -> 100 trong khoảng 4.2s -> 6.05s
        waitUntil(4.2)
        tween(status, 0.35, QUAD, OUT, {TextTransparency = 0})
        tween(percent, 0.35, QUAD, OUT, {TextTransparency = 0})

        local percentValue = Instance.new("NumberValue")
        percentValue.Value = 0
        percentValue.Changed:Connect(function(v)
            local p = math.clamp(v / 100, 0, 1)
            bar.Size = UDim2.new(p, 0, 1, 0)
            percent.Text = math.floor(v + 0.5) .. "%"
        end)
        tween(percentValue, 1.85, SINE, OUT, {Value = 100})

        -- Dọn laptop khi đã tan hẳn
        waitUntil(4.5)
        laptopAlive = false
        laptop:Destroy()

        -- 6) Chờ tải ảnh xong (thường đã xong từ lâu), rồi "ready!"
        waitUntil(6.05)
        while not preloadDone do
            task.wait()
        end
        status.Text = "ready!"

        -- 7) Outro: flash viền logo rồi fade + zoom nhẹ. Kết thúc đúng giây thứ 7
        waitUntil(INTRO_TOTAL - INTRO_OUTRO)
        introAlive = false
        tween(logoStroke, 0.15, QUAD, OUT, {Transparency = 0})
        tween(barGlow, 0.15, QUAD, OUT, {Transparency = 0.3})
        task.wait(0.15)
        tween(stage, 0.5, QUAD, IN, {GroupTransparency = 1})
        tween(stageScale, 0.5, QUAD, IN, {Scale = 1.05})
        task.wait(0.5)
        introGui:Destroy()
        createMainUI()
    end)
end

-- ====================== UI HELPERS (LIQUID GLASS) ======================
local WHITE = Color3.fromRGB(255, 255, 255)
local GLASS_TINT = Color3.fromRGB(24, 28, 40)    -- nền kính xanh đen nhạt
local GLASS_WHITE = Color3.fromRGB(235, 240, 255) -- kính sáng (nút, hàng bài hát)
local BLUR_SIZE = 16                              -- độ mờ phông game phía sau popup (0 = tắt blur)

local function gray(v)
    return Color3.fromRGB(v, v, v)
end

local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or UDim.new(0, 8)
    c.Parent = obj
    return c
end

local function mkGradient(parent, rotation, transparency)
    local g = Instance.new("UIGradient")
    g.Rotation = rotation or 0
    g.Transparency = transparency
    g.Parent = parent
    return g
end

-- Viền kính: sáng ở góc trên-trái, mờ ở giữa, sáng lại nhẹ ở góc dưới-phải
local RIM_SEQ = NumberSequence.new({
    NumberSequenceKeypoint.new(0,    0.10),
    NumberSequenceKeypoint.new(0.30, 0.70),
    NumberSequenceKeypoint.new(0.70, 0.85),
    NumberSequenceKeypoint.new(1,    0.30),
})

local function makeRim(parent, thickness, extraT)
    local rim = Instance.new("UIStroke")
    rim.Name = "Rim"
    rim.Color = WHITE
    rim.Thickness = thickness or 1.2
    rim.Transparency = extraT or 0
    rim.Parent = parent
    mkGradient(rim, 40, RIM_SEQ)
    return rim
end

-- Biến một Frame/Button thành kính lỏng:
--   nền mờ + sheen (ánh phản chiếu cong) + vạch sáng mép trên + viền sáng gradient
-- opts: tint, alpha (BackgroundTransparency), shine (0 = tắt sheen), rim (false = bỏ viền),
--       rimThickness, rimT (độ mờ thêm của viền)
local function glassify(obj, radius, opts)
    opts = opts or {}
    local shine = opts.shine or 1
    local alpha = opts.alpha or 0.5

    obj.BackgroundColor3 = opts.tint or GLASS_TINT
    obj.BackgroundTransparency = alpha
    obj.BorderSizePixel = 0
    obj:SetAttribute("Base", alpha)
    if radius then round(obj, radius) end

    if shine > 0 then
        -- Sheen: sáng ở trên, tan dần xuống giữa, hắt lại nhẹ ở đáy
        local sheen = Instance.new("Frame")
        sheen.Name = "Sheen"
        sheen.Size = UDim2.new(1, 0, 1, 0)
        sheen.BackgroundColor3 = WHITE
        sheen.BorderSizePixel = 0
        sheen.Parent = obj
        if radius then round(sheen, radius) end
        mkGradient(sheen, 90, NumberSequence.new({
            NumberSequenceKeypoint.new(0,    1 - 0.30 * shine),
            NumberSequenceKeypoint.new(0.45, 1 - 0.07 * shine),
            NumberSequenceKeypoint.new(0.55, 1 - 0.02 * shine),
            NumberSequenceKeypoint.new(1,    1 - 0.10 * shine),
        }))

        -- Vạch phản quang mảnh sát mép trên
        local edge = Instance.new("Frame")
        edge.Name = "Edge"
        edge.AnchorPoint = Vector2.new(0.5, 0)
        edge.Size = UDim2.new(0.84, 0, 0, 1)
        edge.Position = UDim2.new(0.5, 0, 0, 1)
        edge.BackgroundColor3 = WHITE
        edge.BorderSizePixel = 0
        edge.Parent = obj
        mkGradient(edge, 0, NumberSequence.new({
            NumberSequenceKeypoint.new(0,   1),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1,   1),
        }))
    end

    if opts.rim ~= false then
        makeRim(obj, opts.rimThickness, opts.rimT)
    end
    return obj
end

-- Bật/tắt các lớp phản chiếu (dùng cho nút điều hướng: chỉ nút đang chọn mới "nổi" kính)
local function glassLayers(obj, on)
    local sheen = obj:FindFirstChild("Sheen")
    local edge = obj:FindFirstChild("Edge")
    local rim = obj:FindFirstChild("Rim")
    if sheen then sheen.Visible = on end
    if edge then edge.Visible = on end
    if rim then rim.Enabled = on end
end

-- Đổi độ trong suốt gốc của kính (hover sẽ sáng hơn 0.1 so với gốc này)
local function setGlassBase(obj, alpha)
    obj:SetAttribute("Base", alpha)
    TweenService:Create(obj, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundTransparency = alpha}):Play()
end

-- Hover: kính sáng lên khi rê chuột vào
local function hoverGlass(hit, frame)
    hit.MouseEnter:Connect(function()
        local base = frame:GetAttribute("Base") or 0.5
        TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundTransparency = math.max(0, base - 0.1)}):Play()
    end)
    hit.MouseLeave:Connect(function()
        local base = frame:GetAttribute("Base") or 0.5
        TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {BackgroundTransparency = base}):Play()
    end)
end

-- Chữ trắng có viền tối rất nhẹ để luôn đọc được trên nền kính
local function softText(label)
    label.TextStrokeColor3 = gray(0)
    label.TextStrokeTransparency = 0.82
end

-- Nút/ô nhập dạng viên thuốc bằng kính. strong = true cho nút hành động chính.
-- (chữ phải nằm ở object con riêng, không gắn vào chính viên thuốc)
local function makePill(parent, size, position, strong)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = position
    f.Parent = parent
    glassify(f, UDim.new(1, 0), {
        tint = GLASS_WHITE,
        alpha = strong and 0.72 or 0.86,
        shine = strong and 1.2 or 0.9,
    })
    return f
end

-- Hiệu ứng nhấn nút: co nhẹ (0.9) rồi bật lại bằng UIScale
local function pressAnim(pill)
    local scale = pill:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Parent = pill
    end
    scale.Scale = 1
    TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.9}):Play()
    task.delay(0.08, function()
        TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    end)
end

-- Blur phông game phía sau popup: đây là thứ làm kính "mờ thật"
-- (BlurEffect chỉ làm mờ thế giới 3D, không làm mờ GUI nên chữ và nút vẫn nét)
local blurFx = nil
local function setBlur(on)
    if BLUR_SIZE <= 0 then return end
    pcall(function()
        if not blurFx then
            blurFx = Lighting:FindFirstChild("TetoGlassBlur")
            if not blurFx then
                blurFx = Instance.new("BlurEffect")
                blurFx.Name = "TetoGlassBlur"
                blurFx.Size = 0
                blurFx.Parent = Lighting
            end
        end
        TweenService:Create(blurFx, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {Size = on and BLUR_SIZE or 0}):Play()
    end)
end

-- Kích thước cửa sổ (vừa cho mobile, không quá to)
local SIDEBAR_W = 140

-- ====================== MAIN UI ======================
function createMainUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "TetoMIDI_v2"
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = CoreGui

    -- ========== TOAST (thông báo tiếng Anh, kính mờ) ==========
    local toast = Instance.new("CanvasGroup")
    toast.Name = "Toast"
    toast.AnchorPoint = Vector2.new(0.5, 1)
    toast.Size = UDim2.new(0, 160, 0, 32)
    toast.Position = UDim2.new(0.5, 0, 1, 40)
    toast.GroupTransparency = 1
    toast.ZIndex = 100
    toast.Parent = gui
    glassify(toast, UDim.new(1, 0), {alpha = 0.3, shine = 1, rimT = 1})
    local toastRim = toast:FindFirstChild("Rim")

    local toastLabel = Instance.new("TextLabel")
    toastLabel.Size = UDim2.new(1, 0, 1, 0)
    toastLabel.BackgroundTransparency = 1
    toastLabel.Text = ""
    toastLabel.TextColor3 = WHITE
    toastLabel.Font = Enum.Font.GothamMedium
    toastLabel.TextSize = 13
    toastLabel.ZIndex = 101
    toastLabel.Parent = toast
    softText(toastLabel)

    local toastToken = 0
    local function showToast(text)
        toastToken = toastToken + 1
        local mine = toastToken

        local w = 160
        pcall(function()
            w = TextService:GetTextSize(text, 13, Enum.Font.GothamMedium, Vector2.new(600, 40)).X + 36
        end)
        toast.Size = UDim2.new(0, w, 0, 32)
        toastLabel.Text = text

        -- Bắt đầu từ dưới, trượt lên
        toast.Position = UDim2.new(0.5, 0, 1, 30)
        local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(toast, info, {Position = UDim2.new(0.5, 0, 1, -16), GroupTransparency = 0}):Play()
        if toastRim then TweenService:Create(toastRim, info, {Transparency = 0}):Play() end

        task.delay(1.9, function()
            if mine ~= toastToken then return end -- đã có thông báo mới hơn
            local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            TweenService:Create(toast, out, {Position = UDim2.new(0.5, 0, 1, 30), GroupTransparency = 1}):Play()
            if toastRim then TweenService:Create(toastRim, out, {Transparency = 1}):Play() end
        end)
    end

    -- ========== FLOATING BUBBLE (real image) ==========
    local bubble = Instance.new("ImageButton")
    bubble.Name = "TetoBubble"
    bubble.Size = UDim2.new(0, 48, 0, 48)
    bubble.Position = UDim2.new(1, -70, 0.5, -24)
    bubble.AutoButtonColor = false
    bubble.Image = getImage("logo.png")
    bubble.ScaleType = Enum.ScaleType.Fit
    bubble.Parent = gui

    if bubble.Image == "" then
        local bubbleFallback = Instance.new("TextLabel")
        bubbleFallback.Size = UDim2.new(1, 0, 1, 0)
        bubbleFallback.BackgroundTransparency = 1
        bubbleFallback.Text = "♪"
        bubbleFallback.TextColor3 = WHITE
        bubbleFallback.Font = Enum.Font.GothamBold
        bubbleFallback.TextSize = 24
        bubbleFallback.Active = false
        bubbleFallback.Parent = bubble
    end
    glassify(bubble, UDim.new(1, 0), {alpha = 0.3, shine = 1.2, rimThickness = 1.6})
    local bubbleStroke = bubble:FindFirstChild("Rim")

    bubble.MouseEnter:Connect(function()
        TweenService:Create(bubble, TweenInfo.new(0.18), {Size = UDim2.new(0, 54, 0, 54)}):Play()
        TweenService:Create(bubbleStroke, TweenInfo.new(0.18), {Thickness = 2.4}):Play()
    end)
    bubble.MouseLeave:Connect(function()
        TweenService:Create(bubble, TweenInfo.new(0.18), {Size = UDim2.new(0, 48, 0, 48)}):Play()
        TweenService:Create(bubbleStroke, TweenInfo.new(0.18), {Thickness = 1.6}):Play()
    end)

    local bubbleDragging, bubbleDragStart, bubbleStartPos, bubbleMoved = false, nil, nil, false

    bubble.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            bubbleDragging = true
            bubbleMoved = false
            bubbleDragStart = input.Position
            bubbleStartPos = bubble.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    bubbleDragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if bubbleDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - bubbleDragStart
            if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
                bubbleMoved = true
            end
            bubble.Position = UDim2.new(
                bubbleStartPos.X.Scale, bubbleStartPos.X.Offset + delta.X,
                bubbleStartPos.Y.Scale, bubbleStartPos.Y.Offset + delta.Y
            )
        end
    end)

    -- ========== MAIN FRAME ==========
    -- Co theo màn hình nhưng bị chặn trong khoảng 330x210 → 470x290
    -- (điện thoại ngang ~ 460x260, PC cũng không phình to)
    -- CanvasGroup để fade toàn bộ nội dung popup cùng lúc
    local main = Instance.new("CanvasGroup")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.Size = UDim2.new(0.62, 0, 0.72, 0)
    main.BackgroundTransparency = 1
    main.BorderSizePixel = 0
    main.Active = true
    main.ClipsDescendants = true
    main.Visible = false
    main.GroupTransparency = 1
    main.Parent = gui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 20)
    mainCorner.Parent = main

    -- Lớp kính nền (nằm dưới cùng): nền mờ + sheen + vạch phản quang
    local glassBase = Instance.new("Frame")
    glassBase.Name = "GlassBase"
    glassBase.Size = UDim2.new(1, 0, 1, 0)
    glassBase.Parent = main
    glassify(glassBase, nil, {alpha = 0.34, shine = 1.3, rim = false})

    local mainScale = Instance.new("UIScale")
    mainScale.Scale = 0.85
    mainScale.Parent = main

    local sizeLimit = Instance.new("UISizeConstraint")
    sizeLimit.MinSize = Vector2.new(330, 210)
    sizeLimit.MaxSize = Vector2.new(470, 290)
    sizeLimit.Parent = main

    -- Viền kính sáng gradient (hiện dần khi mở popup)
    local mainStroke = makeRim(main, 1.5, 1)

    -- Vệt sáng chéo lướt qua mặt kính định kỳ (lớp trên cùng, không chặn chuột)
    local glare = Instance.new("Frame")
    glare.Name = "Glare"
    glare.AnchorPoint = Vector2.new(0.5, 0.5)
    glare.Size = UDim2.new(0.26, 0, 1.9, 0)
    glare.Position = UDim2.new(-0.3, 0, 0.5, 0)
    glare.Rotation = 18
    glare.BackgroundColor3 = WHITE
    glare.BorderSizePixel = 0
    glare.ZIndex = 5
    glare.Parent = main
    mkGradient(glare, 0, NumberSequence.new({
        NumberSequenceKeypoint.new(0,   1),
        NumberSequenceKeypoint.new(0.5, 0.9),
        NumberSequenceKeypoint.new(1,   1),
    }))
    task.spawn(function()
        while gui.Parent do
            task.wait(4.5)
            if MainVisible then
                glare.Position = UDim2.new(-0.3, 0, 0.5, 0)
                TweenService:Create(glare, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Position = UDim2.new(1.3, 0, 0.5, 0)}):Play()
            end
        end
    end)

    -- Mở/đóng popup bằng tween (scale + fade) thay vì bật Visible đột ngột
    local openTween, closeTween
    local function openMain()
        MainVisible = true
        setBlur(true)
        TweenService:Create(mainStroke, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0}):Play()
        if closeTween then closeTween:Cancel() end
        main.Visible = true
        mainScale.Scale = 0.85
        main.GroupTransparency = 1
        TweenService:Create(mainScale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        openTween = TweenService:Create(main, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 0})
        openTween:Play()
    end

    local function closeMain()
        MainVisible = false
        setBlur(false)
        TweenService:Create(mainStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
        if openTween then openTween:Cancel() end
        TweenService:Create(mainScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.9}):Play()
        closeTween = TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
        closeTween:Play()
        closeTween.Completed:Connect(function()
            if not MainVisible then main.Visible = false end
        end)
    end

    -- Bật/tắt bằng bubble
    bubble.MouseButton1Click:Connect(function()
        if bubbleMoved then return end
        playClick()
        if MainVisible then closeMain() else openMain() end
    end)

    -- ===== SIDEBAR (đen → xám) =====
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
    sidebar.Active = true
    sidebar.Parent = main
    glassify(sidebar, nil, {tint = Color3.fromRGB(6, 8, 14), alpha = 0.5, shine = 0.7, rim = false})

    -- Đường chia mảnh giữa sidebar và nội dung
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.AnchorPoint = Vector2.new(1, 0)
    divider.Size = UDim2.new(0, 1, 1, 0)
    divider.Position = UDim2.new(1, 0, 0, 0)
    divider.BackgroundColor3 = WHITE
    divider.BackgroundTransparency = 0.82
    divider.BorderSizePixel = 0
    divider.Parent = sidebar

    -- Kéo cửa sổ bằng sidebar (không kéo nhầm khi cuộn danh sách bài)
    local dragging, dragStart, startPos
    sidebar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Logo + tên
    local headerLogo = Instance.new("ImageLabel")
    headerLogo.Size = UDim2.new(0, 26, 0, 26)
    headerLogo.Position = UDim2.new(0, 8, 0, 10)
    headerLogo.BackgroundTransparency = 1
    headerLogo.Image = getImage("logo.png")
    headerLogo.ScaleType = Enum.ScaleType.Fit
    headerLogo.Parent = sidebar
    round(headerLogo, UDim.new(0, 5))

    local logoTitle = Instance.new("TextLabel")
    logoTitle.Size = UDim2.new(1, -44, 0, 26)
    logoTitle.Position = UDim2.new(0, 40, 0, 10)
    logoTitle.BackgroundTransparency = 1
    logoTitle.Text = "tetoMIDI v2.2"
    logoTitle.TextColor3 = WHITE
    logoTitle.Font = Enum.Font.GothamBold
    logoTitle.TextSize = 12
    logoTitle.TextXAlignment = Enum.TextXAlignment.Left
    logoTitle.Parent = sidebar
    softText(logoTitle)

    -- Nút điều hướng
    local navButtons = {}
    local updatePages -- khai báo trước, gán ở dưới

    local function makeNavBtn(text, iconName, y, page)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 34)
        btn.Position = UDim2.new(0, 8, 0, y)
        btn.BackgroundColor3 = WHITE
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.Parent = sidebar
        glassify(btn, UDim.new(0, 10), {tint = GLASS_WHITE, alpha = 1, shine = 0.9, rimT = 0.2})
        glassLayers(btn, false)      -- chỉ nút đang chọn mới nổi lớp kính (xem updatePages)
        hoverGlass(btn, btn)
        bindClick(btn)

        local iconId = getImage(iconName)
        if iconId ~= "" then
            local icon = Instance.new("ImageLabel")
            icon.Size = UDim2.new(0, 22, 0, 22)
            icon.Position = UDim2.new(0, 6, 0.5, -11)
            icon.BackgroundTransparency = 1
            icon.Image = iconId
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = btn
            round(icon, UDim.new(0, 5))
        end

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -36, 1, 0)
        label.Position = UDim2.new(0, 34, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = WHITE
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = btn
        softText(label)

        btn.MouseButton1Click:Connect(function()
            pressAnim(btn)
            CurrentPage = page
            updatePages()
        end)

        navButtons[page] = btn
        return btn
    end

    makeNavBtn("auto player", "icon_auto.png", 50, "auto")
    makeNavBtn("custom song", "icon_custom.png", 90, "custom")
    makeNavBtn("midi2lua hub", "logo.png", 130, "hub")

    -- Nút Discord (dưới cùng sidebar): bấm = copy link + thông báo
    local discordBtn = Instance.new("TextButton")
    discordBtn.Name = "Discord"
    discordBtn.AnchorPoint = Vector2.new(0, 1)
    discordBtn.Size = UDim2.new(1, -16, 0, 34)
    discordBtn.Position = UDim2.new(0, 8, 1, -10)
    discordBtn.BackgroundColor3 = WHITE
    discordBtn.BackgroundTransparency = 0.9
    discordBtn.Text = ""
    discordBtn.AutoButtonColor = false
    discordBtn.BorderSizePixel = 0
    discordBtn.Parent = sidebar
    glassify(discordBtn, UDim.new(0, 10), {tint = GLASS_WHITE, alpha = 0.88, shine = 0.9, rimT = 0.2})
    hoverGlass(discordBtn, discordBtn)
    bindClick(discordBtn)

    local discordIconId = getImage("discord.png")
    if discordIconId ~= "" then
        local dIcon = Instance.new("ImageLabel")
        dIcon.Size = UDim2.new(0, 22, 0, 22)
        dIcon.Position = UDim2.new(0, 6, 0.5, -11)
        dIcon.BackgroundTransparency = 1
        dIcon.Image = discordIconId
        dIcon.ScaleType = Enum.ScaleType.Fit
        dIcon.Parent = discordBtn
    end

    local discordLabel = Instance.new("TextLabel")
    discordLabel.Size = UDim2.new(1, -36, 1, 0)
    discordLabel.Position = UDim2.new(0, discordIconId ~= "" and 34 or 12, 0, 0)
    discordLabel.BackgroundTransparency = 1
    discordLabel.Text = "discord"
    discordLabel.TextColor3 = WHITE
    discordLabel.Font = Enum.Font.GothamMedium
    discordLabel.TextSize = 13
    discordLabel.TextXAlignment = Enum.TextXAlignment.Left
    discordLabel.Parent = discordBtn
    softText(discordLabel)

    discordBtn.MouseButton1Click:Connect(function()
        local setclip = setclipboard or toclipboard or (syn and syn.write_clipboard) or (Clipboard and Clipboard.set)
        local copied = false
        if setclip then
            copied = pcall(setclip, DISCORD_LINK)
        end
        if copied then
            showToast("Discord link copied")
        else
            showToast("Can't copy - " .. DISCORD_LINK)
            print("[tetoMIDI] Discord: " .. DISCORD_LINK)
        end
    end)

    -- ===== CONTENT =====
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
    content.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
    content.BackgroundTransparency = 1
    content.Parent = main

    -- ===== AUTO PAGE =====
    local autoPage = Instance.new("Frame")
    autoPage.Name = "AutoPage"
    autoPage.Size = UDim2.new(1, 0, 1, 0)
    autoPage.BackgroundTransparency = 1
    autoPage.Parent = content

    -- Kính lúp vẽ bằng Frame (không cần ảnh)
    local magnifier = Instance.new("Frame")
    magnifier.Size = UDim2.new(0, 18, 0, 18)
    magnifier.Position = UDim2.new(0, 12, 0, 13)
    magnifier.BackgroundTransparency = 1
    magnifier.Parent = autoPage

    local lens = Instance.new("Frame")
    lens.Size = UDim2.new(0, 10, 0, 10)
    lens.Position = UDim2.new(0, 1, 0, 1)
    lens.BackgroundTransparency = 1
    lens.BorderSizePixel = 0
    lens.Parent = magnifier
    round(lens, UDim.new(1, 0))
    local lensStroke = Instance.new("UIStroke")
    lensStroke.Color = gray(235)
    lensStroke.Thickness = 2
    lensStroke.Parent = lens

    local handle = Instance.new("Frame")
    handle.AnchorPoint = Vector2.new(0.5, 0.5)
    handle.Size = UDim2.new(0, 2, 0, 7)
    handle.Position = UDim2.new(0, 13, 0, 13)
    handle.Rotation = -45
    handle.BackgroundColor3 = gray(235)
    handle.BorderSizePixel = 0
    handle.Parent = magnifier

    local searchPill = makePill(autoPage, UDim2.new(1, -52, 0, 28), UDim2.new(0, 40, 0, 12))
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -20, 1, 0)
    searchBox.Position = UDim2.new(0, 10, 0, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.Text = ""
    searchBox.PlaceholderText = "search song"
    searchBox.TextColor3 = WHITE
    searchBox.PlaceholderColor3 = gray(205)
    searchBox.Font = Enum.Font.GothamMedium
    searchBox.TextSize = 13
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = searchPill

    -- Khung danh sách (nền đen)
    local listBg = Instance.new("Frame")
    listBg.Size = UDim2.new(1, -24, 1, -96)
    listBg.Position = UDim2.new(0, 12, 0, 50)
    listBg.BackgroundColor3 = gray(0)
    listBg.BorderSizePixel = 0
    listBg.ClipsDescendants = true
    listBg.Parent = autoPage
    glassify(listBg, UDim.new(0, 12), {tint = Color3.fromRGB(4, 6, 12), alpha = 0.45, shine = 0.5, rimT = 0.35})

    local emptyLabel = Instance.new("TextLabel")
    emptyLabel.Size = UDim2.new(1, -20, 1, 0)
    emptyLabel.Position = UDim2.new(0, 10, 0, 0)
    emptyLabel.BackgroundTransparency = 1
    emptyLabel.Text = "no songs yet\nadd one in custom song"
    emptyLabel.TextColor3 = gray(175)
    emptyLabel.Font = Enum.Font.Gotham
    emptyLabel.TextSize = 12
    emptyLabel.Parent = listBg

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, 0, 1, 0)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 3
    listFrame.ScrollBarImageColor3 = gray(190)
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.Parent = listBg

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 6)
    listPadding.PaddingBottom = UDim.new(0, 6)
    listPadding.PaddingLeft = UDim.new(0, 6)
    listPadding.PaddingRight = UDim.new(0, 8)
    listPadding.Parent = listFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 6)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = listFrame

    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 12)
    end)

    local selectedSong = nil

    local function styleRow(row, selected)
        local rim = row:FindFirstChild("Rim")
        local trash = row:FindFirstChild("Trash")
        setGlassBase(row, selected and 0.62 or 0.9)
        if rim then
            rim.Transparency = selected and 0 or 0.45
            rim.Thickness = selected and 1.6 or 1.2
        end
        if trash then trash.Visible = selected end
    end

    local function refreshSongList(filter)
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        filter = (filter or ""):lower()
        local shown = 0
        for i, song in ipairs(SongList) do
            if filter == "" or tostring(song.name):lower():find(filter, 1, true) then
                shown = shown + 1

                local row = Instance.new("Frame")
                row.Name = "Row"
                row.Size = UDim2.new(1, 0, 0, 34)
                row.LayoutOrder = i
                row.Parent = listFrame
                glassify(row, UDim.new(0, 10), {tint = GLASS_WHITE, alpha = 0.9, shine = 0.8, rimT = 0.45})

                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -42, 1, 0)
                btn.BackgroundTransparency = 1
                btn.Text = tostring(song.name)
                btn.TextColor3 = WHITE
                btn.Font = Enum.Font.GothamMedium
                btn.TextSize = 14
                btn.TextTruncate = Enum.TextTruncate.AtEnd
                btn.AutoButtonColor = false
                btn.Parent = row
                softText(btn)
                hoverGlass(btn, row)
                bindClick(btn)

                -- ===== NÚT XÓA: thùng rác đỏ, chỉ hiện khi bài đang được chọn =====
                local trashBtn = Instance.new("TextButton")
                trashBtn.Name = "Trash"
                trashBtn.AnchorPoint = Vector2.new(0.5, 0.5)
                trashBtn.Size = UDim2.new(0, 24, 0, 24)
                trashBtn.Position = UDim2.new(1, -19, 0.5, 0)
                trashBtn.Text = ""
                trashBtn.AutoButtonColor = false
                trashBtn.Visible = false
                trashBtn.Parent = row
                glassify(trashBtn, UDim.new(0, 8), {tint = Color3.fromRGB(235, 64, 64), alpha = 0.2, shine = 0.9, rimT = 0.2})
                bindClick(trashBtn)

                -- Vẽ icon thùng rác bằng Frame (quai + nắp + thân)
                local handle = Instance.new("Frame")
                handle.AnchorPoint = Vector2.new(0.5, 0)
                handle.Size = UDim2.new(0, 5, 0, 2)
                handle.Position = UDim2.new(0.5, 0, 0, 4)
                handle.BackgroundColor3 = WHITE
                handle.BorderSizePixel = 0
                handle.Parent = trashBtn

                local lid = Instance.new("Frame")
                lid.AnchorPoint = Vector2.new(0.5, 0)
                lid.Size = UDim2.new(0, 13, 0, 2)
                lid.Position = UDim2.new(0.5, 0, 0, 6)
                lid.BackgroundColor3 = WHITE
                lid.BorderSizePixel = 0
                lid.Parent = trashBtn

                local body = Instance.new("Frame")
                body.AnchorPoint = Vector2.new(0.5, 0)
                body.Size = UDim2.new(0, 10, 0, 9)
                body.Position = UDim2.new(0.5, 0, 0, 9)
                body.BackgroundColor3 = WHITE
                body.BorderSizePixel = 0
                body.Parent = trashBtn
                round(body, UDim.new(0, 2))

                -- Hover: nút sáng lên
                trashBtn.MouseEnter:Connect(function()
                    TweenService:Create(trashBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(255, 90, 90)}):Play()
                end)
                trashBtn.MouseLeave:Connect(function()
                    TweenService:Create(trashBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(235, 64, 64)}):Play()
                end)

                -- Bấm thùng rác = xóa bài + lưu file + thông báo
                trashBtn.MouseButton1Click:Connect(function()
                    for j, s in ipairs(SongList) do
                        if s == song then
                            table.remove(SongList, j)
                            break
                        end
                    end
                    if selectedSong == song then
                        selectedSong = nil
                    end
                    saveCustoms()
                    refreshSongList(searchBox.Text)
                    showToast("Song deleted")
                end)

                styleRow(row, song == selectedSong)

                btn.MouseButton1Click:Connect(function()
                    for _, other in ipairs(listFrame:GetChildren()) do
                        if other:IsA("Frame") then styleRow(other, false) end
                    end
                    selectedSong = song
                    styleRow(row, true)
                end)
            end
        end
        emptyLabel.Visible = (shown == 0)
        if shown == 0 and #SongList > 0 then
            emptyLabel.Text = "no match"
        else
            emptyLabel.Text = "no songs yet\nadd one in custom song"
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        refreshSongList(searchBox.Text)
    end)

    -- Chạy 1 script midi2lua (dùng chung cho auto player và hub)
    local function playScript(name, script)
        if _G.songisplaying then
            showToast("A song is already playing")
            return
        end
        -- CHỈ chạy đúng 1 script của bài hát (fix lỗi chạy 2 script cùng lúc)
        local ok, err = pcall(function()
            loadstring(script)()
        end)
        if not ok then
            warn("[tetoMIDI] Lỗi chạy song:", err)
            showToast("Song script error")
            return
        end
        showToast("Now playing: " .. tostring(name))
    end

    local playPill = makePill(autoPage, UDim2.new(0, 88, 0, 28), UDim2.new(1, -100, 1, -38), true)
    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(1, 0, 1, 0)
    playBtn.BackgroundTransparency = 1
    playBtn.Text = "play"
    playBtn.TextColor3 = WHITE
    playBtn.Font = Enum.Font.GothamBold
    playBtn.TextSize = 13
    playBtn.AutoButtonColor = false
    playBtn.Parent = playPill
    softText(playBtn)
    hoverGlass(playBtn, playPill)
    bindClick(playBtn)

    playBtn.MouseButton1Click:Connect(function()
        pressAnim(playPill)   -- hiệu ứng nhấn nút

        if not selectedSong then
            showToast("Select a song first")
            return
        end
        playScript(selectedSong.name, selectedSong.script)
    end)

    -- ===== CUSTOM PAGE =====
    local customPage = Instance.new("Frame")
    customPage.Name = "CustomPage"
    customPage.Size = UDim2.new(1, 0, 1, 0)
    customPage.BackgroundTransparency = 1
    customPage.Visible = false
    customPage.Parent = content

    local nameBg = Instance.new("Frame")
    nameBg.Size = UDim2.new(1, -24, 0, 32)
    nameBg.Position = UDim2.new(0, 12, 0, 12)
    nameBg.BackgroundColor3 = gray(0)
    nameBg.BorderSizePixel = 0
    nameBg.Parent = customPage
    glassify(nameBg, UDim.new(0, 12), {tint = Color3.fromRGB(4, 6, 12), alpha = 0.45, shine = 0.5, rimT = 0.35})

    local nameBox = Instance.new("TextBox")
    nameBox.Size = UDim2.new(1, -20, 1, 0)
    nameBox.Position = UDim2.new(0, 10, 0, 0)
    nameBox.BackgroundTransparency = 1
    nameBox.PlaceholderText = "Give the song a name, e.g. Golden Hour"
    nameBox.Text = ""
    nameBox.TextColor3 = WHITE
    nameBox.PlaceholderColor3 = gray(160)
    nameBox.Font = Enum.Font.GothamMedium
    nameBox.TextSize = 12
    nameBox.TextXAlignment = Enum.TextXAlignment.Left
    nameBox.TextTruncate = Enum.TextTruncate.AtEnd
    nameBox.ClearTextOnFocus = false
    nameBox.Parent = nameBg

    local scriptBg = Instance.new("Frame")
    scriptBg.Size = UDim2.new(1, -24, 1, -100)
    scriptBg.Position = UDim2.new(0, 12, 0, 52)
    scriptBg.BackgroundColor3 = gray(0)
    scriptBg.BorderSizePixel = 0
    scriptBg.ClipsDescendants = true
    scriptBg.Parent = customPage
    glassify(scriptBg, UDim.new(0, 12), {tint = Color3.fromRGB(4, 6, 12), alpha = 0.45, shine = 0.5, rimT = 0.35})

    local scriptBox = Instance.new("TextBox")
    scriptBox.Size = UDim2.new(1, -20, 1, -16)
    scriptBox.Position = UDim2.new(0, 10, 0, 8)
    scriptBox.BackgroundTransparency = 1
    scriptBox.PlaceholderText = "Paste the midi2lua script here!"
    scriptBox.Text = ""
    scriptBox.TextColor3 = gray(225)
    scriptBox.PlaceholderColor3 = gray(160)
    scriptBox.Font = Enum.Font.Code
    scriptBox.TextSize = 12
    scriptBox.TextXAlignment = Enum.TextXAlignment.Left
    scriptBox.TextYAlignment = Enum.TextYAlignment.Top
    scriptBox.ClearTextOnFocus = false
    scriptBox.MultiLine = true
    scriptBox.TextWrapped = true
    scriptBox.Parent = scriptBg

    local savePill = makePill(customPage, UDim2.new(0, 190, 0, 28), UDim2.new(0.5, -95, 1, -38), true)
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 1, 0)
    saveBtn.BackgroundTransparency = 1
    saveBtn.Text = "save and add auto player"
    saveBtn.TextColor3 = WHITE
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 12
    saveBtn.AutoButtonColor = false
    saveBtn.Parent = savePill
    softText(saveBtn)
    hoverGlass(saveBtn, savePill)
    bindClick(saveBtn)

    saveBtn.MouseButton1Click:Connect(function()
        pressAnim(savePill)
        local name = nameBox.Text:gsub("^%s*(.-)%s*$", "%1")
        local scr = scriptBox.Text:gsub("^%s*(.-)%s*$", "%1")

        if name == "" or scr == "" then
            warn("[tetoMIDI] Tên bài hoặc script trống")
            showToast("Enter a name and a script")
            return
        end

        table.insert(SongList, {name = name, script = scr})

        pcall(function()
            if isfolder and not isfolder("tetomidi2lua") then
                makefolder("tetomidi2lua")
            end
            local safeName = name:gsub("[^%w%s%-%_]", ""):gsub("%s+", "_")
            if safeName == "" then safeName = "song_" .. tostring(#SongList) end
            writefile("tetomidi2lua/" .. safeName .. ".txt", scr)
            print("[tetoMIDI] Đã lưu → tetomidi2lua/" .. safeName .. ".txt")
        end)

        saveCustoms()
        nameBox.Text = ""
        scriptBox.Text = ""
        searchBox.Text = ""
        refreshSongList("")
        CurrentPage = "auto"
        updatePages()
        showToast("Song added")
        print("[tetoMIDI] Đã thêm bài:", name)
    end)

    -- ===== MIDI2LUA HUB PAGE =====
    local hubPage = Instance.new("Frame")
    hubPage.Name = "HubPage"
    hubPage.Size = UDim2.new(1, 0, 1, 0)
    hubPage.BackgroundTransparency = 1
    hubPage.Visible = false
    hubPage.Parent = content

    local hubSearchPill = makePill(hubPage, UDim2.new(1, -76, 0, 28), UDim2.new(0, 12, 0, 12))
    local hubSearchBox = Instance.new("TextBox")
    hubSearchBox.Size = UDim2.new(1, -20, 1, 0)
    hubSearchBox.Position = UDim2.new(0, 10, 0, 0)
    hubSearchBox.BackgroundTransparency = 1
    hubSearchBox.Text = ""
    hubSearchBox.PlaceholderText = "search hub"
    hubSearchBox.TextColor3 = WHITE
    hubSearchBox.PlaceholderColor3 = gray(205)
    hubSearchBox.Font = Enum.Font.GothamMedium
    hubSearchBox.TextSize = 13
    hubSearchBox.ClearTextOnFocus = false
    hubSearchBox.Parent = hubSearchPill

    local hubSyncPill = makePill(hubPage, UDim2.new(0, 44, 0, 28), UDim2.new(1, -56, 0, 12), true)
    local hubSyncBtn = Instance.new("TextButton")
    hubSyncBtn.Size = UDim2.new(1, 0, 1, 0)
    hubSyncBtn.BackgroundTransparency = 1
    hubSyncBtn.Text = "sync"
    hubSyncBtn.TextColor3 = WHITE
    hubSyncBtn.Font = Enum.Font.GothamBold
    hubSyncBtn.TextSize = 12
    hubSyncBtn.AutoButtonColor = false
    hubSyncBtn.Parent = hubSyncPill
    softText(hubSyncBtn)
    hoverGlass(hubSyncBtn, hubSyncPill)
    bindClick(hubSyncBtn)

    local hubBg = Instance.new("Frame")
    hubBg.Size = UDim2.new(1, -24, 1, -62)
    hubBg.Position = UDim2.new(0, 12, 0, 50)
    hubBg.BorderSizePixel = 0
    hubBg.ClipsDescendants = true
    hubBg.Parent = hubPage
    glassify(hubBg, UDim.new(0, 12), {tint = Color3.fromRGB(4, 6, 12), alpha = 0.45, shine = 0.5, rimT = 0.35})

    local hubEmpty = Instance.new("TextLabel")
    hubEmpty.Size = UDim2.new(1, -20, 1, 0)
    hubEmpty.Position = UDim2.new(0, 10, 0, 0)
    hubEmpty.BackgroundTransparency = 1
    hubEmpty.Text = "loading..."
    hubEmpty.TextColor3 = gray(175)
    hubEmpty.Font = Enum.Font.Gotham
    hubEmpty.TextSize = 12
    hubEmpty.Parent = hubBg

    local hubList = Instance.new("ScrollingFrame")
    hubList.Size = UDim2.new(1, 0, 1, 0)
    hubList.BackgroundTransparency = 1
    hubList.BorderSizePixel = 0
    hubList.ScrollBarThickness = 3
    hubList.ScrollBarImageColor3 = gray(190)
    hubList.CanvasSize = UDim2.new(0, 0, 0, 0)
    hubList.Parent = hubBg

    local hubPadding = Instance.new("UIPadding")
    hubPadding.PaddingTop = UDim.new(0, 6)
    hubPadding.PaddingBottom = UDim.new(0, 6)
    hubPadding.PaddingLeft = UDim.new(0, 6)
    hubPadding.PaddingRight = UDim.new(0, 8)
    hubPadding.Parent = hubList

    local hubLayout = Instance.new("UIListLayout")
    hubLayout.Padding = UDim.new(0, 6)
    hubLayout.SortOrder = Enum.SortOrder.LayoutOrder
    hubLayout.Parent = hubList
    hubLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        hubList.CanvasSize = UDim2.new(0, 0, 0, hubLayout.AbsoluteContentSize.Y + 12)
    end)

    local hubItems = {}
    local hubState = "idle"   -- idle | loading | ok | fail

    -- Nút nhỏ (play / add) trong hàng bài hát
    local function makeRowButton(parent, x, text, strong)
        local pill = makePill(parent, UDim2.new(0, 46, 0, 20), UDim2.new(0, x, 0, 25), strong)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.Text = text
        b.TextColor3 = WHITE
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.AutoButtonColor = false
        b.Parent = pill
        softText(b)
        hoverGlass(b, pill)
        bindClick(b)
        return pill, b
    end

    local function refreshHubList(filter)
        for _, c in ipairs(hubList:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        filter = (filter or ""):lower()
        local shown = 0

        for i, song in ipairs(hubItems) do
            local songName = tostring(song.name)
            if filter == "" or songName:lower():find(filter, 1, true) then
                shown = shown + 1

                local row = Instance.new("Frame")
                row.Name = "HubRow"
                row.Size = UDim2.new(1, 0, 0, 48)
                row.LayoutOrder = i
                row.Parent = hubList
                glassify(row, UDim.new(0, 10), {tint = GLASS_WHITE, alpha = 0.9, shine = 0.8, rimT = 0.45})

                -- Thumbnail (tải ngầm, có chữ ♪ dự phòng)
                local thumb = Instance.new("ImageLabel")
                thumb.Size = UDim2.new(0, 36, 0, 36)
                thumb.Position = UDim2.new(0, 6, 0.5, -18)
                thumb.BackgroundColor3 = gray(20)
                thumb.BackgroundTransparency = 0.4
                thumb.BorderSizePixel = 0
                thumb.Image = ""
                thumb.ScaleType = Enum.ScaleType.Crop
                thumb.Parent = row
                round(thumb, UDim.new(0, 8))

                local thumbFallback = Instance.new("TextLabel")
                thumbFallback.Size = UDim2.new(1, 0, 1, 0)
                thumbFallback.BackgroundTransparency = 1
                thumbFallback.Text = "♪"
                thumbFallback.TextColor3 = gray(200)
                thumbFallback.Font = Enum.Font.GothamBold
                thumbFallback.TextSize = 16
                thumbFallback.Parent = thumb

                if song.has_thumb then
                    task.spawn(function()
                        local assetId = hubThumb(song.id)
                        if assetId ~= "" and thumb.Parent then
                            thumb.Image = assetId
                            thumbFallback.Visible = false
                        end
                    end)
                end

                local nameLabel = Instance.new("TextLabel")
                nameLabel.Size = UDim2.new(1, -54, 0, 18)
                nameLabel.Position = UDim2.new(0, 48, 0, 4)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Text = songName
                nameLabel.TextColor3 = WHITE
                nameLabel.Font = Enum.Font.GothamMedium
                nameLabel.TextSize = 13
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
                nameLabel.Parent = row
                softText(nameLabel)

                local playP, playB = makeRowButton(row, 48, "play", true)
                local addP, addB = makeRowButton(row, 100, "add", false)

                playB.MouseButton1Click:Connect(function()
                    pressAnim(playP)
                    if _G.songisplaying then
                        showToast("A song is already playing")
                        return
                    end
                    showToast("Downloading...")
                    task.spawn(function()
                        local script = hubFetchScript(song.id)
                        if not script then
                            showToast("Download failed")
                            return
                        end
                        playScript(songName, script)
                    end)
                end)

                addB.MouseButton1Click:Connect(function()
                    pressAnim(addP)
                    for _, s in ipairs(SongList) do
                        if s.hubId == song.id then
                            showToast("Already in auto player")
                            return
                        end
                    end
                    task.spawn(function()
                        local script = hubFetchScript(song.id)
                        if not script then
                            showToast("Download failed")
                            return
                        end
                        table.insert(SongList, {name = songName, script = script, hubId = song.id})
                        saveCustoms()
                        refreshSongList(searchBox.Text)
                        showToast("Added to auto player")
                    end)
                end)
            end
        end

        if hubState == "loading" then
            hubEmpty.Visible = true
            hubEmpty.Text = "loading..."
        elseif hubState == "fail" then
            hubEmpty.Visible = true
            hubEmpty.Text = "hub offline\ntap sync to retry"
        elseif shown == 0 then
            hubEmpty.Visible = true
            hubEmpty.Text = (#hubItems > 0) and "no match" or "hub is empty"
        else
            hubEmpty.Visible = false
        end
    end

    local function syncHub()
        if hubState == "loading" then return end
        hubState = "loading"
        refreshHubList(hubSearchBox.Text)
        task.spawn(function()
            local data = hubFetchList()
            if data then
                hubItems = data
                hubState = "ok"
            else
                hubState = "fail"
            end
            refreshHubList(hubSearchBox.Text)
        end)
    end

    hubSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        refreshHubList(hubSearchBox.Text)
    end)

    hubSyncBtn.MouseButton1Click:Connect(function()
        pressAnim(hubSyncPill)
        syncHub()
    end)

    -- ===== CHUYỂN TRANG =====
    updatePages = function()
        autoPage.Visible = (CurrentPage == "auto")
        customPage.Visible = (CurrentPage == "custom")
        hubPage.Visible = (CurrentPage == "hub")
        if CurrentPage == "hub" and hubState == "idle" then
            syncHub()   -- lần đầu mở hub: tự tải danh sách
        end
        for page, btn in pairs(navButtons) do
            local active = (page == CurrentPage)
            glassLayers(btn, active)
            setGlassBase(btn, active and 0.8 or 1)
        end
    end

    updatePages()
    refreshSongList()

    -- Popup tự bật với hiệu ứng mượt ngay sau intro
    task.delay(0.05, openMain)
end

-- Start
createIntro()
