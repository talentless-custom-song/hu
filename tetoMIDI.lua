--[[
    tetoMIDI v2.3 - Liquid Glass UI
    Intro + Floating Bubble + Piano Player + Drum Player + Guitar Player (MIDI file + piano roll) + MIDI Hub + Discord + tiếng click
    
    v2.3-fix: thêm ENGINE gửi phím vào game (piano / drum / guitar) - trước đó chỉ có giao diện + piano roll nên không đánh được.
    Xem khối "ENGINE: GỬI PHÍM VÀO GAME" (INPUT_METHOD, DEBUG_KEYS) và README.md.

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
local RunService = game:GetService("RunService")

-- ====================== CẤU HÌNH GITHUB ======================
local GITHUB_USER = "talentless-custom-song"
local GITHUB_REPO = "hu"

-- Link server Discord (bấm logo Discord sẽ copy link này)
local DISCORD_LINK = "https://discord.gg/peaqm6uqgB"

-- Server midi2lua hub (hub_server trên PythonAnywhere): bot Discord upload bài lên đây qua API
-- HUB_API = hub chính (mới). HUB_API_EXTRA = các hub phụ, danh sách bài của tất cả hub sẽ được gộp lại.
-- Hub nào lỗi/offline thì bỏ qua, hub còn lại vẫn hiện bình thường.
local HUB_API = "https://midi2lua.pythonanywhere.com"
local HUB_API_EXTRA = {
    "https://tetomidi.pythonanywhere.com",   -- hub cũ (giữ lại để không mất bài cũ)
}
local HUB_DIR = "tetoMIDI/hub"
local HUB_STALE_SEC = 30      -- mở tab hub lại sau chừng này giây thì tự đồng bộ lại
local HUB_TIMEOUT_SEC = 25    -- quá thời gian này mà hub chưa trả lời thì coi là lỗi

local IMAGE_DIR = "tetoMIDI/images"
local IMAGE_FILES = { "logo.png", "piano.png", "drum.png", "guitar.png", "hub.png", "discord.png", "gear.png" }
-- Ảnh không bắt buộc: thiếu thì UI vẫn chạy bình thường, không báo lỗi
local OPTIONAL_IMAGES = { ["discord.png"] = true, ["piano.png"] = true, ["drum.png"] = true, ["guitar.png"] = true, ["hub.png"] = true, ["gear.png"] = true }
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

-- Đánh dấu "input này thuộc về 1 nút / ô nhập / danh sách" -> cửa sổ không bị kéo theo khi bấm vào đó.
-- (Xem khối KÉO CỬA SỔ: kéo chỉ bắt đầu từ chỗ trống, input đã bị claim sẽ bị bỏ qua)
local UI_CLAIM = setmetatable({}, {__mode = "k"})
local function claimInput(obj)
    obj.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            UI_CLAIM[input] = true
        end
    end)
end

local FOLD_MAP = {
    [192]="a",[193]="a",[194]="a",[195]="a",[196]="a",[197]="a",[198]="ae",[199]="c",[200]="e",[201]="e",[202]="e",
    [203]="e",[204]="i",[205]="i",[206]="i",[207]="i",[208]="d",[209]="n",[210]="o",[211]="o",[212]="o",[213]="o",
    [214]="o",[216]="o",[217]="u",[218]="u",[219]="u",[220]="u",[221]="y",[222]="th",[223]="ss",[224]="a",
    [225]="a",[226]="a",[227]="a",[228]="a",[229]="a",[230]="ae",[231]="c",[232]="e",[233]="e",[234]="e",[235]="e",
    [236]="i",[237]="i",[238]="i",[239]="i",[240]="d",[241]="n",[242]="o",[243]="o",[244]="o",[245]="o",[246]="o",
    [248]="o",[249]="u",[250]="u",[251]="u",[252]="u",[253]="y",[254]="th",[255]="y",[256]="a",[257]="a",[258]="a",
    [259]="a",[260]="a",[261]="a",[262]="c",[263]="c",[264]="c",[265]="c",[266]="c",[267]="c",[268]="c",[269]="c",
    [270]="d",[271]="d",[272]="d",[273]="d",[274]="e",[275]="e",[276]="e",[277]="e",[278]="e",[279]="e",[280]="e",
    [281]="e",[282]="e",[283]="e",[284]="g",[285]="g",[286]="g",[287]="g",[288]="g",[289]="g",[290]="g",[291]="g",
    [292]="h",[293]="h",[294]="h",[295]="h",[296]="i",[297]="i",[298]="i",[299]="i",[300]="i",[301]="i",[302]="i",
    [303]="i",[304]="i",[305]="i",[306]="\u{133}",[308]="j",[309]="j",[310]="k",[311]="k",[313]="l",[314]="l",
    [315]="l",[316]="l",[317]="l",[318]="l",[319]="\u{140}",[321]="l",[322]="l",[323]="n",[324]="n",[325]="n",
    [326]="n",[327]="n",[328]="n",[330]="\u{14B}",[332]="o",[333]="o",[334]="o",[335]="o",[336]="o",[337]="o",
    [338]="oe",[339]="oe",[340]="r",[341]="r",[342]="r",[343]="r",[344]="r",[345]="r",[346]="s",[347]="s",
    [348]="s",[349]="s",[350]="s",[351]="s",[352]="s",[353]="s",[354]="t",[355]="t",[356]="t",[357]="t",[358]="t",
    [359]="t",[360]="u",[361]="u",[362]="u",[363]="u",[364]="u",[365]="u",[366]="u",[367]="u",[368]="u",[369]="u",
    [370]="u",[371]="u",[372]="w",[373]="w",[374]="y",[375]="y",[376]="y",[377]="z",[378]="z",[379]="z",[380]="z",
    [381]="z",[382]="z",[385]="\u{253}",[386]="\u{183}",[388]="\u{185}",[390]="\u{254}",[391]="\u{188}",
    [393]="\u{256}",[394]="\u{257}",[395]="\u{18C}",[398]="\u{1DD}",[399]="\u{259}",[400]="\u{25B}",
    [401]="\u{192}",[403]="\u{260}",[404]="\u{263}",[406]="\u{269}",[407]="\u{268}",[408]="\u{199}",
    [412]="\u{26F}",[413]="\u{272}",[415]="\u{275}",[416]="o",[417]="o",[418]="\u{1A3}",[420]="\u{1A5}",
    [422]="\u{280}",[423]="\u{1A8}",[425]="\u{283}",[428]="\u{1AD}",[430]="\u{288}",[431]="u",[432]="u",
    [433]="\u{28A}",[434]="\u{28B}",[435]="\u{1B4}",[437]="\u{1B6}",[439]="\u{292}",[440]="\u{1B9}",
    [444]="\u{1BD}",[452]="\u{1C6}",[453]="\u{1C6}",[455]="\u{1C9}",[456]="\u{1C9}",[458]="\u{1CC}",
    [459]="\u{1CC}",[461]="a",[462]="a",[463]="i",[464]="i",[465]="o",[466]="o",[467]="u",[468]="u",[469]="u",
    [470]="u",[471]="u",[472]="u",[473]="u",[474]="u",[475]="u",[476]="u",[478]="a",[479]="a",[480]="a",[481]="a",
    [482]="\u{1E3}",[484]="\u{1E5}",[486]="g",[487]="g",[488]="k",[489]="k",[490]="o",[491]="o",[492]="o",
    [493]="o",[494]="\u{1EF}",[496]="j",[497]="\u{1F3}",[498]="\u{1F3}",[500]="g",[501]="g",[502]="\u{195}",
    [503]="\u{1BF}",[504]="n",[505]="n",[506]="a",[507]="a",[508]="\u{1FD}",[510]="\u{1FF}",[512]="a",[513]="a",
    [514]="a",[515]="a",[516]="e",[517]="e",[518]="e",[519]="e",[520]="i",[521]="i",[522]="i",[523]="i",[524]="o",
    [525]="o",[526]="o",[527]="o",[528]="r",[529]="r",[530]="r",[531]="r",[532]="u",[533]="u",[534]="u",[535]="u",
    [536]="s",[537]="s",[538]="t",[539]="t",[540]="\u{21D}",[542]="h",[543]="h",[544]="\u{19E}",[546]="\u{223}",
    [548]="\u{225}",[550]="a",[551]="a",[552]="e",[553]="e",[554]="o",[555]="o",[556]="o",[557]="o",[558]="o",
    [559]="o",[560]="o",[561]="o",[562]="y",[563]="y",[570]="\u{2C65}",[571]="\u{23C}",[573]="\u{19A}",
    [574]="\u{2C66}",[577]="\u{242}",[579]="\u{180}",[580]="\u{289}",[581]="\u{28C}",[582]="\u{247}",
    [584]="\u{249}",[586]="\u{24B}",[588]="\u{24D}",[590]="\u{24F}",[7680]="a",[7681]="a",[7682]="b",[7683]="b",
    [7684]="b",[7685]="b",[7686]="b",[7687]="b",[7688]="c",[7689]="c",[7690]="d",[7691]="d",[7692]="d",[7693]="d",
    [7694]="d",[7695]="d",[7696]="d",[7697]="d",[7698]="d",[7699]="d",[7700]="e",[7701]="e",[7702]="e",[7703]="e",
    [7704]="e",[7705]="e",[7706]="e",[7707]="e",[7708]="e",[7709]="e",[7710]="f",[7711]="f",[7712]="g",[7713]="g",
    [7714]="h",[7715]="h",[7716]="h",[7717]="h",[7718]="h",[7719]="h",[7720]="h",[7721]="h",[7722]="h",[7723]="h",
    [7724]="i",[7725]="i",[7726]="i",[7727]="i",[7728]="k",[7729]="k",[7730]="k",[7731]="k",[7732]="k",[7733]="k",
    [7734]="l",[7735]="l",[7736]="l",[7737]="l",[7738]="l",[7739]="l",[7740]="l",[7741]="l",[7742]="m",[7743]="m",
    [7744]="m",[7745]="m",[7746]="m",[7747]="m",[7748]="n",[7749]="n",[7750]="n",[7751]="n",[7752]="n",[7753]="n",
    [7754]="n",[7755]="n",[7756]="o",[7757]="o",[7758]="o",[7759]="o",[7760]="o",[7761]="o",[7762]="o",[7763]="o",
    [7764]="p",[7765]="p",[7766]="p",[7767]="p",[7768]="r",[7769]="r",[7770]="r",[7771]="r",[7772]="r",[7773]="r",
    [7774]="r",[7775]="r",[7776]="s",[7777]="s",[7778]="s",[7779]="s",[7780]="s",[7781]="s",[7782]="s",[7783]="s",
    [7784]="s",[7785]="s",[7786]="t",[7787]="t",[7788]="t",[7789]="t",[7790]="t",[7791]="t",[7792]="t",[7793]="t",
    [7794]="u",[7795]="u",[7796]="u",[7797]="u",[7798]="u",[7799]="u",[7800]="u",[7801]="u",[7802]="u",[7803]="u",
    [7804]="v",[7805]="v",[7806]="v",[7807]="v",[7808]="w",[7809]="w",[7810]="w",[7811]="w",[7812]="w",[7813]="w",
    [7814]="w",[7815]="w",[7816]="w",[7817]="w",[7818]="x",[7819]="x",[7820]="x",[7821]="x",[7822]="y",[7823]="y",
    [7824]="z",[7825]="z",[7826]="z",[7827]="z",[7828]="z",[7829]="z",[7830]="h",[7831]="t",[7832]="w",[7833]="y",
    [7838]="ss",[7840]="a",[7841]="a",[7842]="a",[7843]="a",[7844]="a",[7845]="a",[7846]="a",[7847]="a",[7848]="a",
    [7849]="a",[7850]="a",[7851]="a",[7852]="a",[7853]="a",[7854]="a",[7855]="a",[7856]="a",[7857]="a",[7858]="a",
    [7859]="a",[7860]="a",[7861]="a",[7862]="a",[7863]="a",[7864]="e",[7865]="e",[7866]="e",[7867]="e",[7868]="e",
    [7869]="e",[7870]="e",[7871]="e",[7872]="e",[7873]="e",[7874]="e",[7875]="e",[7876]="e",[7877]="e",[7878]="e",
    [7879]="e",[7880]="i",[7881]="i",[7882]="i",[7883]="i",[7884]="o",[7885]="o",[7886]="o",[7887]="o",[7888]="o",
    [7889]="o",[7890]="o",[7891]="o",[7892]="o",[7893]="o",[7894]="o",[7895]="o",[7896]="o",[7897]="o",[7898]="o",
    [7899]="o",[7900]="o",[7901]="o",[7902]="o",[7903]="o",[7904]="o",[7905]="o",[7906]="o",[7907]="o",[7908]="u",
    [7909]="u",[7910]="u",[7911]="u",[7912]="u",[7913]="u",[7914]="u",[7915]="u",[7916]="u",[7917]="u",[7918]="u",
    [7919]="u",[7920]="u",[7921]="u",[7922]="y",[7923]="y",[7924]="y",[7925]="y",[7926]="y",[7927]="y",[7928]="y",
    [7929]="y",[7930]="\u{1EFB}",[7932]="\u{1EFD}",[7934]="\u{1EFF}",[880]="\u{371}",[882]="\u{373}",
    [886]="\u{377}",[895]="\u{3F3}",[902]="\u{3AC}",[904]="\u{3AD}",[905]="\u{3AE}",[906]="\u{3AF}",
    [908]="\u{3CC}",[910]="\u{3CD}",[911]="\u{3CE}",[913]="\u{3B1}",[914]="\u{3B2}",[915]="\u{3B3}",
    [916]="\u{3B4}",[917]="\u{3B5}",[918]="\u{3B6}",[919]="\u{3B7}",[920]="\u{3B8}",[921]="\u{3B9}",
    [922]="\u{3BA}",[923]="\u{3BB}",[924]="\u{3BC}",[925]="\u{3BD}",[926]="\u{3BE}",[927]="\u{3BF}",
    [928]="\u{3C0}",[929]="\u{3C1}",[931]="\u{3C3}",[932]="\u{3C4}",[933]="\u{3C5}",[934]="\u{3C6}",
    [935]="\u{3C7}",[936]="\u{3C8}",[937]="\u{3C9}",[938]="\u{3CA}",[939]="\u{3CB}",[975]="\u{3D7}",
    [984]="\u{3D9}",[986]="\u{3DB}",[988]="\u{3DD}",[990]="\u{3DF}",[992]="\u{3E1}",[994]="\u{3E3}",
    [996]="\u{3E5}",[998]="\u{3E7}",[1000]="\u{3E9}",[1002]="\u{3EB}",[1004]="\u{3ED}",[1006]="\u{3EF}",
    [1012]="\u{3B8}",[1015]="\u{3F8}",[1017]="\u{3F2}",[1018]="\u{3FB}",[1021]="\u{37B}",[1022]="\u{37C}",
    [1023]="\u{37D}",[1024]="\u{450}",[1025]="\u{451}",[1026]="\u{452}",[1027]="\u{453}",[1028]="\u{454}",
    [1029]="\u{455}",[1030]="\u{456}",[1031]="\u{457}",[1032]="\u{458}",[1033]="\u{459}",[1034]="\u{45A}",
    [1035]="\u{45B}",[1036]="\u{45C}",[1037]="\u{45D}",[1038]="\u{45E}",[1039]="\u{45F}",[1040]="\u{430}",
    [1041]="\u{431}",[1042]="\u{432}",[1043]="\u{433}",[1044]="\u{434}",[1045]="\u{435}",[1046]="\u{436}",
    [1047]="\u{437}",[1048]="\u{438}",[1049]="\u{439}",[1050]="\u{43A}",[1051]="\u{43B}",[1052]="\u{43C}",
    [1053]="\u{43D}",[1054]="\u{43E}",[1055]="\u{43F}",[1056]="\u{440}",[1057]="\u{441}",[1058]="\u{442}",
    [1059]="\u{443}",[1060]="\u{444}",[1061]="\u{445}",[1062]="\u{446}",[1063]="\u{447}",[1064]="\u{448}",
    [1065]="\u{449}",[1066]="\u{44A}",[1067]="\u{44B}",[1068]="\u{44C}",[1069]="\u{44D}",[1070]="\u{44E}",
    [1071]="\u{44F}",[1120]="\u{461}",[1122]="\u{463}",[1124]="\u{465}",[1126]="\u{467}",[1128]="\u{469}",
    [1130]="\u{46B}",[1132]="\u{46D}",[1134]="\u{46F}",[1136]="\u{471}",[1138]="\u{473}",[1140]="\u{475}",
    [1142]="\u{477}",[1144]="\u{479}",[1146]="\u{47B}",[1148]="\u{47D}",[1150]="\u{47F}",[1152]="\u{481}",
    [1162]="\u{48B}",[1164]="\u{48D}",[1166]="\u{48F}",[1168]="\u{491}",[1170]="\u{493}",[1172]="\u{495}",
    [1174]="\u{497}",[1176]="\u{499}",[1178]="\u{49B}",[1180]="\u{49D}",[1182]="\u{49F}",[1184]="\u{4A1}",
    [1186]="\u{4A3}",[1188]="\u{4A5}",[1190]="\u{4A7}",[1192]="\u{4A9}",[1194]="\u{4AB}",[1196]="\u{4AD}",
    [1198]="\u{4AF}",[1200]="\u{4B1}",[1202]="\u{4B3}",[1204]="\u{4B5}",[1206]="\u{4B7}",[1208]="\u{4B9}",
    [1210]="\u{4BB}",[1212]="\u{4BD}",[1214]="\u{4BF}",[1216]="\u{4CF}",[1217]="\u{4C2}",[1219]="\u{4C4}",
    [1221]="\u{4C6}",[1223]="\u{4C8}",[1225]="\u{4CA}",[1227]="\u{4CC}",[1229]="\u{4CE}",[1232]="\u{4D1}",
    [1234]="\u{4D3}",[1236]="\u{4D5}",[1238]="\u{4D7}",[1240]="\u{4D9}",[1242]="\u{4DB}",[1244]="\u{4DD}",
    [1246]="\u{4DF}",[1248]="\u{4E1}",[1250]="\u{4E3}",[1252]="\u{4E5}",[1254]="\u{4E7}",[1256]="\u{4E9}",
    [1258]="\u{4EB}",[1260]="\u{4ED}",[1262]="\u{4EF}",[1264]="\u{4F1}",[1266]="\u{4F3}",[1268]="\u{4F5}",
    [1270]="\u{4F7}",[1272]="\u{4F9}",[1274]="\u{4FB}",[1276]="\u{4FD}",[1278]="\u{4FF}",
}

-- Chuẩn hóa để tìm kiếm: hạ chữ hoa (Latin, Việt, Hy Lạp, Cyrillic), bỏ dấu (nắng → nang),
-- bỏ dấu câu ASCII. "Nắng Ấm", "nang am", "NẮNG ẤM" đều khớp nhau.
local function searchFold(text)
    text = tostring(text or "")
    local out, ok = {}, true
    ok = pcall(function()
        for _, cp in utf8.codes(text) do
            if cp < 128 then
                local c = string.char(cp):lower()
                if c:match("%w") then out[#out + 1] = c else out[#out + 1] = " " end
            elseif cp >= 0x300 and cp <= 0x36F then
                -- dấu tổ hợp (NFD): bỏ qua
            else
                out[#out + 1] = FOLD_MAP[cp] or utf8.char(cp)
            end
        end
    end)
    if not ok then return string.lower(text) end
    return (table.concat(out):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Mọi từ khóa đều phải có trong tên (thứ tự tùy ý)
local function searchMatch(name, query)
    if query == "" then return true end
    local hay = " " .. name .. " "
    for word in query:gmatch("%S+") do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end

-- Gắn tiếng click vào nút: kêu ngay lúc nhấn xuống (chuột hoặc chạm)
local function bindClick(btn)
    btn.MouseButton1Down:Connect(playClick)
    claimInput(btn)
end

-- ====================== MIDI2LUA HUB (API) ======================
local hubThumbCache = {}

-- Danh sách hub: mỗi hub có url + tag (tiền tố để id của các hub không bị trùng nhau).
-- Hub cũ (tetomidi) giữ tag rỗng để các bài đã "add" từ trước vẫn nhận ra.
local HUBS = {}
do
    local seen = {}
    local function addHub(url)
        if type(url) ~= "string" then return end
        url = url:gsub("%s+", ""):gsub("/+$", "")
        if url == "" or seen[url] then return end
        seen[url] = true
        local host = url:match("^%w+://([^%./]+)") or ("hub" .. (#HUBS + 1))
        local tag = (host == "tetomidi") and "" or (host .. ":")
        table.insert(HUBS, {url = url, tag = tag, name = host})
    end
    addHub(HUB_API)
    for _, u in ipairs(HUB_API_EXTRA) do addHub(u) end
end

-- GET có thử lại (PythonAnywhere free hay "ngủ" và lỗi request đầu tiên)
local function hubGet(url, tries)
    for i = 1, (tries or 2) do
        local body = httpGetRaw(url)
        if body then return body end
        task.wait(0.6 * i)
    end
    return nil
end

local function firstOf(t, ...)
    for _, k in ipairs({...}) do
        if t[k] ~= nil and t[k] ~= "" then return t[k] end
    end
    return nil
end

-- Server có thể trả mảng thẳng hoặc {songs = [...]} / {data = [...]} ... -> chuẩn hoá về mảng
local function hubExtractArray(data)
    if type(data) ~= "table" then return nil end
    if data[1] ~= nil or next(data) == nil then return data end
    for _, k in ipairs({"songs", "list", "data", "items", "results", "files", "scripts"}) do
        if type(data[k]) == "table" then return data[k] end
    end
    -- dạng map {"1": {...}, "2": {...}}
    local arr = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            if v.id == nil then v.id = k end
            table.insert(arr, v)
        end
    end
    if #arr > 0 then return arr end
    return nil
end

-- Lấy danh sách bài của 1 hub: {key, id, name, link, has_thumb, hub}
local function hubFetchOne(hub)
    local body = hubGet(hub.url .. "/api/lua/list?_=" .. tostring(os.time()), 3)
    if type(body) ~= "string" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then return nil end
    local arr = hubExtractArray(data)
    if not arr then return nil end

    local out = {}
    for _, it in ipairs(arr) do
        if type(it) == "table" then
            local id = firstOf(it, "id", "ID", "_id", "slug")
            if id ~= nil then
                local hasThumb = it.has_thumb
                if hasThumb == nil then
                    hasThumb = (firstOf(it, "thumb", "thumbnail", "thumb_url") ~= nil)
                end
                table.insert(out, {
                    id = id,
                    key = hub.tag .. tostring(id),
                    name = tostring(firstOf(it, "name", "title", "filename") or ("song " .. tostring(id))),
                    link = it.link,
                    has_thumb = hasThumb and true or false,
                    created = it.created,
                    hub = hub,
                })
            end
        end
    end
    return out
end

-- Lấy danh sách từ TẤT CẢ hub song song, gộp lại. Trả về (items, soTHubOk) hoặc nil nếu hub nào cũng lỗi.
local function hubFetchList()
    local results, pending = {}, #HUBS
    for i, hub in ipairs(HUBS) do
        task.spawn(function()
            local ok, res = pcall(hubFetchOne, hub)
            results[i] = (ok and res) or false
            pending = pending - 1
        end)
    end
    local t = 0
    while pending > 0 and t < HUB_TIMEOUT_SEC do
        task.wait(0.1)
        t = t + 0.1
    end

    local merged, okCount = {}, 0
    for i = 1, #HUBS do
        if results[i] then
            okCount = okCount + 1
            for _, song in ipairs(results[i]) do table.insert(merged, song) end
        end
    end
    if okCount == 0 then return nil end
    return merged, okCount
end

-- Nội dung script midi2lua của 1 bài
local function hubFetchScript(song)
    local body = hubGet(song.hub.url .. "/api/lua/script/" .. tostring(song.id), 3)
    if type(body) == "string" and #body > 20 then return body end
    return nil
end

-- Thumbnail PNG: tải về tetoMIDI/hub/<key>.png rồi trả asset id (như logo)
local function hubThumb(song)
    local key = song.key
    if hubThumbCache[key] then return hubThumbCache[key] end
    if not (writefile and isfile and readfile and (getcustomasset or getsynasset)) then return "" end

    pcall(function()
        if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
        if isfolder and not isfolder(HUB_DIR) then makefolder(HUB_DIR) end
    end)

    local path = HUB_DIR .. "/" .. tostring(key):gsub("[^%w_%-]", "_") .. ".png"
    if isfile(path) then
        local okRead, data = pcall(readfile, path)
        if okRead and isPng(data) then
            local asset = getAsset(path)
            if asset ~= "" then hubThumbCache[key] = asset; return asset end
        end
    end

    local data = httpGetRaw(song.hub.url .. "/api/lua/thumb/" .. tostring(song.id))
    if isPng(data) and pcall(writefile, path, data) then
        local asset = getAsset(path)
        if asset ~= "" then hubThumbCache[key] = asset; return asset end
    end
    return ""
end

-- ====================== DATA ======================
local CurrentPage = "piano"
local MainVisible = true

pcall(function()
    if isfolder and not isfolder("tetoMIDI") then
        makefolder("tetoMIDI")
    end
end)

-- ====================== MIDI CORE (keymap + đọc MIDI + dữ liệu piano roll) ======================
-- Bảng phím lấy từ app tetoMIDI v1.3 (piano 61/88 phím, drum, guitar).
local Core = {}
-- Bảng phím lấy từ app tetoMIDI v1.3 (defaults_maps.py) — piano/drum giữ nguyên từ nanoMIDIPlayer
Core.PIANO_61 = {
    [36]="1", [37]="!", [38]="2", [39]="@", [40]="3", [41]="4",
    [42]="$", [43]="5", [44]="%", [45]="6", [46]="^", [47]="7",
    [48]="8", [49]="*", [50]="9", [51]="(", [52]="0", [53]="q",
    [54]="Q", [55]="w", [56]="W", [57]="e", [58]="E", [59]="r",
    [60]="t", [61]="T", [62]="y", [63]="Y", [64]="u", [65]="i",
    [66]="I", [67]="o", [68]="O", [69]="p", [70]="P", [71]="a",
    [72]="s", [73]="S", [74]="d", [75]="D", [76]="f", [77]="g",
    [78]="G", [79]="h", [80]="H", [81]="j", [82]="J", [83]="k",
    [84]="l", [85]="L", [86]="z", [87]="Z", [88]="x", [89]="c",
    [90]="C", [91]="v", [92]="V", [93]="b", [94]="B", [95]="n",
    [96]="m",
}
Core.PIANO_88_LOW = {
    [21]="1", [22]="2", [23]="3", [24]="4", [25]="5", [26]="6",
    [27]="7", [28]="8", [29]="9", [30]="0", [31]="q", [32]="w",
    [33]="e", [34]="r", [35]="t",
}
Core.PIANO_88_HIGH = {
    [97]="y", [98]="u", [99]="i", [100]="o", [101]="p", [102]="a",
    [103]="s", [104]="d", [105]="f", [106]="g", [107]="h", [108]="j",
}
Core.VELOCITY_MAP = {
    [0]="1", [4]="2", [8]="3", [12]="4", [16]="5", [20]="6",
    [24]="7", [28]="8", [32]="9", [36]="0", [40]="q", [44]="w",
    [48]="e", [52]="r", [56]="t", [60]="y", [64]="u", [68]="i",
    [72]="o", [76]="p", [80]="a", [84]="s", [88]="d", [92]="f",
    [96]="g", [100]="h", [104]="j", [108]="k", [112]="l", [116]="z",
    [120]="x", [124]="c",
}
Core.DRUMS_MAP = {
    ["kick"]="b", ["kick2"]="n", ["snare"]="c", ["snare2"]="v",
    ["snareSide"]="s", ["tom1"]="d", ["tom1_2"]="f", ["tom"]="g",
    ["tom2_2"]="h", ["lowTom"]="g", ["lowMidTom"]="d", ["closed_Hi-Hat"]="x",
    ["closed_Hi-Hat2"]="m", ["open_Hi-Hat"]="z", ["leftCrash"]="e", ["rightCrash"]="r",
    ["splashCrash"]="w", ["crashChina"]="o", ["ride"]="u", ["rideBell"]="i",
    ["cowbell"]="a",
}

-- Bàn phím guitar: chromatic E2 (40) .. D#5 (75) trải trên các hàng phím 1-0, q-p, a-l, z-m
Core.GUITAR_FIRST_NOTE = 40
Core.GUITAR_KEYS = "1234567890qwertyuiopasdfghjklzxcvbnm"
Core.GUITAR_KEYMAP = {}
for i = 1, #Core.GUITAR_KEYS do
    Core.GUITAR_KEYMAP[Core.GUITAR_FIRST_NOTE + i - 1] = Core.GUITAR_KEYS:sub(i, i)
end

-- ---------------------------------------------------------------- bảng nốt (mappings.py)
-- MIDI note -> tên trong DRUMS_MAP
Core.DRUM_NOTE_TO_NAME = {
    [42] = "closed_Hi-Hat", [44] = "closed_Hi-Hat2", [46] = "open_Hi-Hat",
    [48] = "tom1", [50] = "tom1_2", [60] = "tom", [62] = "tom2_2",
    [49] = "rightCrash", [55] = "leftCrash", [38] = "snare", [40] = "snare2", [37] = "snareSide",
    [35] = "kick", [36] = "kick2", [51] = "ride", [53] = "rideBell", [39] = "cowbell",
    [52] = "crashChina", [57] = "splashCrash", [45] = "lowTom", [47] = "lowMidTom",
}

-- Các làn trong drum roll: {nhãn, {các MIDI note}}
Core.DRUM_LANES = {
    {"Kick",   {35, 36}},
    {"Snare",  {38, 40, 37}},
    {"Hi-hat", {42, 44}},
    {"Open",   {46}},
    {"Tom hi", {48, 50, 60, 62}},
    {"Tom lo", {45, 47}},
    {"Crash",  {49, 55, 52, 57}},
    {"Ride",   {51, 53}},
    {"Bell",   {39}},
}
Core.DRUM_NOTE_TO_LANE = {}
for i, lane in ipairs(Core.DRUM_LANES) do
    for _, n in ipairs(lane[2]) do Core.DRUM_NOTE_TO_LANE[n] = i end
end

Core.GUITAR_OPEN_STRINGS = {40, 45, 50, 55, 59, 64}   -- E2 A2 D3 G3 B3 E4 (thấp -> cao)
Core.GUITAR_STRING_LABELS = {"E", "A", "D", "G", "B", "e"}
Core.GUITAR_MAX_FRET = 15

Core.PIANO_RANGE_88 = {21, 108}
Core.PIANO_RANGE_61 = {36, 96}
Core.SHORT_NOTE = 0.12     -- độ dài (giây) của mọi nốt khi tắt "Note length"
Core.MIN_NOTE_LEN = 0.04
Core.PERCUSSION_CHANNEL = 9

function Core.isBlack(note)
    local m = note % 12
    return m == 1 or m == 3 or m == 6 or m == 8 or m == 10
end

-- Phím máy tính tương ứng với 1 nốt piano: (phím, cóCtrl)
function Core.pianoKeyFor(note)
    local k = Core.PIANO_61[note]
    if k then return k, false end
    k = Core.PIANO_88_LOW[note] or Core.PIANO_88_HIGH[note]
    if k then return k, true end
    return nil, false
end

local function foldIntoRange(note, low, high)
    if high - low < 11 then return note end
    while note < low do note = note + 12 end
    while note > high do note = note - 12 end
    return note
end

-- (dây, phím đàn) thấp nhất trên dây cao nhất dùng được
function Core.guitarStringFret(note)
    local bestS, bestF
    for s, open in ipairs(Core.GUITAR_OPEN_STRINGS) do
        local fret = note - open
        if fret >= 0 and fret <= Core.GUITAR_MAX_FRET and (bestF == nil or fret < bestF or (fret == bestF and s > bestS)) then
            bestS, bestF = s, fret
        end
    end
    if bestS then return bestS, bestF end
    return nil
end

function Core.guitarResolveNote(note, keymap, fold)
    if keymap[note] and keymap[note] ~= "" then return note end
    if fold then
        local lo, hi
        for n, v in pairs(keymap) do
            if v ~= "" then
                if not lo or n < lo then lo = n end
                if not hi or n > hi then hi = n end
            end
        end
        if lo then
            local folded = foldIntoRange(note, lo, hi)
            if keymap[folded] and keymap[folded] ~= "" then return folded end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- đọc file MIDI
local function readVar(data, p)
    local v = 0
    while true do
        local b = data:byte(p)
        if not b then return nil, p end
        p = p + 1
        v = v * 128 + (b % 128)
        if b < 128 then return v, p end
    end
end

-- Trả về song hoặc (nil, lỗi). `yieldFn` (vd task.wait) được gọi định kỳ để file lớn không làm đơ game.
-- song = {length, notes = {{start,end,note,vel,ch}}, events = {{time,kind,note,value,ch}}, bpm, hasPerc}
function Core.parseMidi(data, yieldFn)
    if type(data) ~= "string" or #data < 14 or data:sub(1, 4) ~= "MThd" then
        return nil, "This file is not a valid MIDI file."
    end
    local function u16(p) local a, b = data:byte(p, p + 1); return a * 256 + b end
    local function u32(p) local a, b, c, d = data:byte(p, p + 3); return ((a * 256 + b) * 256 + c) * 256 + d end

    local hlen, fmt, div = u32(5), u16(9), u16(13)
    if fmt == 2 then return nil, "Asynchronous (type 2) MIDI files are not supported." end
    if div >= 0x8000 then return nil, "SMPTE-timed MIDI files are not supported." end
    if div == 0 then div = 480 end

    local size = #data
    local pos = 9 + hlen
    local raw, tempos = {}, {}
    local seq, maxTick, counter = 0, 0, 0

    while pos + 7 <= size do
        local id, len = data:sub(pos, pos + 3), u32(pos + 4)
        local body = pos + 8
        local stop = math.min(body + len, size + 1)
        pos = body + len
        if id == "MTrk" then
            local p, tick, status = body, 0, nil
            while p < stop do
                local d
                d, p = readVar(data, p)
                if not d then break end
                tick = tick + d
                local b = data:byte(p)
                if not b then break end
                if b >= 0x80 then status = b; p = p + 1 end
                if status == nil then break end

                if status == 0xFF then
                    local mt = data:byte(p); p = p + 1
                    local l
                    l, p = readVar(data, p)
                    if not l then break end
                    if mt == 0x51 and l == 3 then
                        local a, b2, c = data:byte(p, p + 2)
                        if a then tempos[#tempos + 1] = {tick, (a * 256 + b2) * 256 + c, #tempos} end
                    end
                    p = p + l
                    if mt == 0x2F then break end
                elseif status == 0xF0 or status == 0xF7 then
                    local l
                    l, p = readVar(data, p)
                    if not l then break end
                    p = p + l
                else
                    local hi, ch = math.floor(status / 16), status % 16
                    local a = data:byte(p)
                    if not a then break end
                    if hi == 0xC or hi == 0xD then
                        p = p + 1
                    else
                        local v = data:byte(p + 1)
                        if not v then break end
                        p = p + 2
                        if hi == 0x9 and v > 0 then
                            seq = seq + 1; raw[#raw + 1] = {tick, seq, 1, ch, a, v}
                        elseif hi == 0x8 or (hi == 0x9 and v == 0) then
                            seq = seq + 1; raw[#raw + 1] = {tick, seq, 0, ch, a, 0}
                        elseif hi == 0xB and a == 64 then
                            seq = seq + 1; raw[#raw + 1] = {tick, seq, 2, ch, a, v}
                        end
                    end
                end
                counter = counter + 1
                if yieldFn and counter % 6000 == 0 then yieldFn() end
            end
            if tick > maxTick then maxTick = tick end
        end
    end

    -- bảng tempo -> giây
    table.sort(tempos, function(x, y) if x[1] ~= y[1] then return x[1] < y[1] end return x[3] < y[3] end)
    local segs = {}
    if #tempos == 0 or tempos[1][1] > 0 then segs[1] = {tick = 0, sec = 0, us = 500000} end
    for _, t in ipairs(tempos) do
        local last = segs[#segs]
        if last and last.tick == t[1] then
            last.us = t[2]
        else
            local sec = last and (last.sec + (t[1] - last.tick) * last.us / 1e6 / div) or 0
            segs[#segs + 1] = {tick = t[1], sec = sec, us = t[2]}
        end
    end
    local bpm = 60000000 / segs[1].us

    table.sort(raw, function(x, y) if x[1] ~= y[1] then return x[1] < y[1] end return x[2] < y[2] end)

    local events, notes, open = {}, {}, {}
    local hasPerc = false
    local si = 1
    for i, r in ipairs(raw) do
        while segs[si + 1] and segs[si + 1].tick <= r[1] do si = si + 1 end
        local s = segs[si]
        local t = s.sec + (r[1] - s.tick) * s.us / 1e6 / div
        local kind, ch, a, v = r[3], r[4], r[5], r[6]
        events[#events + 1] = {time = t, kind = kind, note = a, value = v, ch = ch}
        if kind == 1 then
            local key = ch * 128 + a
            local q = open[key]
            if not q then q = {}; open[key] = q end
            q[#q + 1] = {t, v}
            if ch == Core.PERCUSSION_CHANNEL then hasPerc = true end
        elseif kind == 0 then
            local q = open[ch * 128 + a]
            if q and #q > 0 then
                local st = table.remove(q, 1)
                notes[#notes + 1] = {start = st[1], stop = math.max(t, st[1] + Core.MIN_NOTE_LEN), note = a, vel = st[2], ch = ch}
            end
        end
        if yieldFn and i % 6000 == 0 then yieldFn() end
    end

    local si2 = 1
    while segs[si2 + 1] and segs[si2 + 1].tick <= maxTick do si2 = si2 + 1 end
    local length = segs[si2].sec + (maxTick - segs[si2].tick) * segs[si2].us / 1e6 / div

    for key, q in pairs(open) do   -- nốt không bao giờ nhả: đóng ở cuối bài
        local ch, a = math.floor(key / 128), key % 128
        for _, st in ipairs(q) do
            notes[#notes + 1] = {start = st[1], stop = math.max(length, st[1] + Core.MIN_NOTE_LEN), note = a, vel = st[2], ch = ch}
        end
    end

    if #notes == 0 then return nil, "This MIDI file contains no notes." end
    table.sort(notes, function(x, y) if x.start ~= y.start then return x.start < y.start end return x.note < y.note end)

    return {length = length, notes = notes, events = events, bpm = bpm, hasPerc = hasPerc}
end

-- Tách tay theo cao độ: nốt dưới C4 (60) là tay trái, từ C4 trở lên là tay phải
Core.HAND_SPLIT = 60
function Core.handAllows(mode, note)
    if mode == "left" then return note < Core.HAND_SPLIT end
    if mode == "right" then return note >= Core.HAND_SPLIT end
    return true
end

-- Lọc nốt theo nhạc cụ (giống Song.view của app):
--  drums: chỉ kênh 10 nếu file có, không thì mọi kênh; piano/guitar: bỏ kênh 10
function Core.songNotes(song, mode, skipPercussion)
    local only = (mode == "drums") and song.hasPerc
    local out = {}
    for _, n in ipairs(song.notes) do
        local keep
        if mode == "drums" then
            keep = (not only) or n.ch == Core.PERCUSSION_CHANNEL
        else
            keep = not (skipPercussion ~= false and n.ch == Core.PERCUSSION_CHANNEL)
        end
        if keep then out[#out + 1] = n end
    end
    return out
end

-- ---------------------------------------------------------------- dữ liệu piano roll (rollmodel.py)
local RollData = {}
RollData.__index = RollData

local function newRoll(kind, lo, hi)
    return setmetatable({kind = kind, starts = {}, ends = {}, lanes = {}, vels = {}, frets = {},
        prefixEnd = {}, lo = lo or 21, hi = hi or 108, n = 0}, RollData)
end

function RollData:add(n, lane, fret, uniform)
    local i = self.n + 1
    self.n = i
    self.starts[i] = n.start
    self.ends[i] = uniform and (n.start + Core.SHORT_NOTE) or n.stop
    self.lanes[i] = lane
    self.vels[i] = n.vel
    self.frets[i] = fret or 0
end

function RollData:finish()
    local best = 0
    for i = 1, self.n do
        if self.ends[i] > best then best = self.ends[i] end
        self.prefixEnd[i] = best
    end
    return self
end

-- số phần tử arr[1..n] thỏa pred(arr[i]) (arr tăng dần): tìm nhị phân
local function countWhile(arr, n, pred)
    local lo, hi = 0, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if pred(arr[mid]) then lo = mid else hi = mid - 1 end
    end
    return lo
end

-- Chỉ số [first, last] (1-based) có thể đang nhìn thấy giữa pos và pos+look
function RollData:window(pos, look)
    local first = countWhile(self.prefixEnd, self.n, function(v) return v <= pos end) + 1
    local last = countWhile(self.starts, self.n, function(v) return v < pos + look end)
    return first, last
end

-- cfg: {k88, noteLengths, transpose, fold}
function Core.buildRoll(mode, notes, cfg)
    cfg = cfg or {}
    local uniform = (cfg.noteLengths == false)
    if mode == "piano" then
        local range = (cfg.k88 ~= false) and Core.PIANO_RANGE_88 or Core.PIANO_RANGE_61
        local data = newRoll("piano", range[1], range[2])
        local shift = cfg.transpose or 0
        for _, n in ipairs(notes or {}) do
            local pitch = n.note + shift
            if pitch >= range[1] and pitch <= range[2] then data:add(n, pitch, 0, uniform) end
        end
        return data:finish()
    elseif mode == "drums" then
        local data = newRoll("drums")
        for _, n in ipairs(notes or {}) do
            local name = Core.DRUM_NOTE_TO_NAME[n.note]
            if name and Core.DRUMS_MAP[name] and Core.DRUMS_MAP[name] ~= "" then
                data:add(n, Core.DRUM_NOTE_TO_LANE[n.note], 0, uniform)
            end
        end
        return data:finish()
    else
        local data = newRoll("guitar")
        local keymap = cfg.keymap or Core.GUITAR_KEYMAP
        for _, n in ipairs(notes or {}) do
            local note = Core.guitarResolveNote(n.note, keymap, cfg.fold ~= false)
            if note then
                local s, f = Core.guitarStringFret(note)
                if s then data:add(n, s, f, uniform) end
            end
        end
        return data:finish()
    end
end

-- Nhãn phím trên các làn drum: {{nhãn, "B/N"}, ...}
function Core.drumLaneLabels()
    local out = {}
    for _, lane in ipairs(Core.DRUM_LANES) do
        local keys, seen = {}, {}
        for _, n in ipairs(lane[2]) do
            local k = Core.DRUMS_MAP[Core.DRUM_NOTE_TO_NAME[n] or ""]
            if k and k ~= "" and not seen[k:upper()] then
                seen[k:upper()] = true
                keys[#keys + 1] = k:upper()
            end
        end
        out[#out + 1] = {lane[1], table.concat(keys, "/")}
    end
    return out
end

function Core.formatTime(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

-- ====================== CẤU HÌNH (lưu giữa các lần chạy) ======================
local MIDI_DIR = "tetoMIDI/midi"                 -- bỏ file .mid vào thư mục này (workspace của executor)
local CONFIG_PATH = "tetoMIDI/config.json"
local Cfg = {
    piano  = {k88 = true, sustain = false, velocity = false, noteLengths = true, loop = false, roll3d = false, file = ""},
    drums  = {noteLengths = true, loop = false, file = ""},
    guitar = {noteLengths = true, loop = false, file = ""},
    roll   = {fall = 3.0},                       -- số giây nốt rơi từ trên xuống phím
    ui     = {alpha = 0},                        -- độ trong suốt của cửa sổ (0 = rõ, 0.8 = rất trong)
    bg     = {piano = "", drums = "", guitar = ""}, -- link ảnh nền (png/jpg) của roll
    fake   = {enabled = false, volume = 80, loud = false}, -- tiếng gõ phím giả (volume 0-100); loud = tối đa Roblox (10)
    note   = {color = "4B84AF"},                 -- màu nốt đang rơi (hex RRGGBB)
    hand   = {mode = "all"},                     -- piano: "all" = cả 2 tay, "left" = chỉ tay trái, "right" = chỉ tay phải
}

pcall(function()
    if isfile and isfile(CONFIG_PATH) then
        local saved = HttpService:JSONDecode(readfile(CONFIG_PATH))
        for sec, t in pairs(saved) do
            if type(t) == "table" and Cfg[sec] then
                for k, v in pairs(t) do
                    if Cfg[sec][k] ~= nil and type(Cfg[sec][k]) == type(v) then Cfg[sec][k] = v end
                end
            end
        end
    end
end)

local cfgToken = 0
local function saveCfg()
    cfgToken = cfgToken + 1
    local mine = cfgToken
    task.delay(0.4, function()
        if mine ~= cfgToken then return end
        pcall(function()
            if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
            writefile(CONFIG_PATH, HttpService:JSONEncode(Cfg))
        end)
    end)
end

-- ====================== GÕ PHÍM GIẢ (fake sound) ======================
-- 114 tiếng click (lấy từ tetoMIDI v1.3, keyboard_clicks.npz) gộp trong sounds/keys.mp3.
-- KEY_CLIPS = {vị trí bắt đầu (giây), độ dài (giây)} của từng tiếng trong file.
local KEYS_FILE = "keys.mp3"
local KEY_CLIPS = {
    {0.0, 0.0802},
    {0.1302, 0.16},
    {0.3402, 0.1168},
    {0.507, 0.16},
    {0.717, 0.0996},
    {0.8666, 0.0852},
    {1.0018, 0.1233},
    {1.1751, 0.0797},
    {1.3048, 0.16},
    {1.5148, 0.108},
    {1.6729, 0.0867},
    {1.8095, 0.16},
    {2.0195, 0.0856},
    {2.1552, 0.0756},
    {2.2807, 0.1051},
    {2.4358, 0.0848},
    {2.5706, 0.16},
    {2.7806, 0.0734},
    {2.9039, 0.16},
    {3.1139, 0.16},
    {3.3239, 0.0836},
    {3.4576, 0.16},
    {3.6676, 0.16},
    {3.8776, 0.16},
    {4.0876, 0.0651},
    {4.2027, 0.1098},
    {4.3625, 0.0696},
    {4.4821, 0.1137},
    {4.6458, 0.0801},
    {4.7759, 0.16},
    {4.9859, 0.0708},
    {5.1067, 0.0858},
    {5.2425, 0.16},
    {5.4525, 0.0878},
    {5.5903, 0.1353},
    {5.7755, 0.0799},
    {5.9054, 0.16},
    {6.1154, 0.0691},
    {6.2345, 0.0792},
    {6.3637, 0.16},
    {6.5737, 0.16},
    {6.7837, 0.1241},
    {6.9578, 0.1545},
    {7.1623, 0.1192},
    {7.3315, 0.16},
    {7.5415, 0.16},
    {7.7515, 0.0937},
    {7.8951, 0.16},
    {8.1051, 0.0812},
    {8.2363, 0.0774},
    {8.3638, 0.0646},
    {8.4783, 0.16},
    {8.6883, 0.16},
    {8.8983, 0.0666},
    {9.015, 0.0784},
    {9.1434, 0.16},
    {9.3534, 0.1493},
    {9.5526, 0.16},
    {9.7626, 0.16},
    {9.9726, 0.0666},
    {10.0892, 0.1203},
    {10.2595, 0.16},
    {10.4695, 0.16},
    {10.6795, 0.16},
    {10.8895, 0.16},
    {11.0995, 0.0711},
    {11.2206, 0.1579},
    {11.4286, 0.16},
    {11.6386, 0.1231},
    {11.8117, 0.0705},
    {11.9322, 0.0901},
    {12.0723, 0.16},
    {12.2823, 0.1284},
    {12.4607, 0.1223},
    {12.633, 0.16},
    {12.843, 0.16},
    {13.053, 0.16},
    {13.263, 0.0731},
    {13.3861, 0.114},
    {13.5502, 0.136},
    {13.7362, 0.1479},
    {13.9341, 0.159},
    {14.1431, 0.16},
    {14.3531, 0.1457},
    {14.5488, 0.16},
    {14.7588, 0.16},
    {14.9688, 0.16},
    {15.1788, 0.1178},
    {15.3466, 0.1432},
    {15.5398, 0.1594},
    {15.7492, 0.16},
    {15.9592, 0.1426},
    {16.1518, 0.1283},
    {16.3301, 0.1206},
    {16.5007, 0.1449},
    {16.6955, 0.1252},
    {16.8707, 0.1317},
    {17.0524, 0.16},
    {17.2624, 0.1362},
    {17.4487, 0.16},
    {17.6587, 0.1425},
    {17.8512, 0.0722},
    {17.9733, 0.16},
    {18.1833, 0.131},
    {18.3644, 0.1231},
    {18.5375, 0.16},
    {18.7475, 0.114},
    {18.9115, 0.16},
    {19.1215, 0.0957},
    {19.2671, 0.0651},
    {19.3822, 0.1035},
    {19.5357, 0.1437},
    {19.7295, 0.1396},
    {19.9191, 0.16},
}
local keysId = nil
local keysLoadStarted = false
local keysActive = 0
local MAX_KEY_VOICES = 24
local keyHook = nil

local function loadKeySounds()
    if keysId or keysLoadStarted then return end
    keysLoadStarted = true
    if not (writefile and isfile and readfile and (getcustomasset or getsynasset)) then
        keysLoadStarted = false
        return
    end
    pcall(function()
        if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
        if isfolder and not isfolder(SOUND_DIR) then makefolder(SOUND_DIR) end
    end)
    local path = SOUND_DIR .. "/" .. KEYS_FILE
    if isfile(path) then
        local okRead, data = pcall(readfile, path)
        if okRead and isMp3(data) then
            local id = getAsset(path)
            if id ~= "" then keysId = id; return end
        end
    end
    for _, url in ipairs(soundUrls(KEYS_FILE)) do
        local data = httpGetRaw(url)
        if isMp3(data) and pcall(writefile, path, data) then
            local id = getAsset(path)
            if id ~= "" then keysId = id; return end
        end
    end
    keysLoadStarted = false   -- chưa tải được: lần sau thử lại
end

-- Một tiếng gõ phím ngẫu nhiên, âm lượng theo cài đặt (mỗi lần lệch nhẹ như gõ thật)
local function playKeyClip()
    if not (Cfg.fake.enabled and keysId) then return end
    if keysActive >= MAX_KEY_VOICES then return end
    local clip = KEY_CLIPS[math.random(#KEY_CLIPS)]
    local snd = Instance.new("Sound")
    snd.Name = "TetoKey"
    snd.SoundId = keysId
    snd.TimePosition = clip[1]
    local maxVol = Cfg.fake.loud and 10 or 1   -- Sound.Volume của Roblox tối đa 10
    snd.Volume = math.clamp(Cfg.fake.volume / 100, 0, 1) * maxVol * (0.7 + math.random() * 0.3)
    snd.PlaybackSpeed = 0.97 + math.random() * 0.06
    snd.Parent = SoundService
    keysActive = keysActive + 1
    snd:Play()
    task.delay(clip[2] + 0.1, function()
        keysActive = keysActive - 1
        snd:Destroy()
    end)
end
keyHook = playKeyClip

if Cfg.fake.enabled then task.spawn(loadKeySounds) end


-- ====================== ENGINE: GỬI PHÍM VÀO GAME ======================
-- Port từ app tetoMIDI v1.3 (engine/dispatchers.py + keysim.py + transport.py).
-- Luồng chạy:  P.tick (mỗi Heartbeat) -> P.onAdvance(posCu, posMoi) -> bắn các sự kiện MIDI trong khoảng đó
--              -> Dispatcher (piano / drums / guitar) tra keymap -> Keys.down / Keys.up (xếp hàng)
--              -> Keys.pump() (cuối mỗi Heartbeat) gửi phím thật vào game.
--
-- INPUT_METHOD:
--   "auto"     = VirtualInputManager (chạy cả PC lẫn mobile), lỗi thì tự chuyển sang keypress()/keyrelease()
--   "vim"      = chỉ dùng VirtualInputManager:SendKeyEvent
--   "keypress" = chỉ dùng keypress()/keyrelease() của executor (phím thật của Windows, game phải đang được focus)
-- Nếu nốt trắng đánh được mà nốt đen (Shift) / nốt thấp-cao (Ctrl) không ăn: thử đổi sang "keypress".
Core.INPUT_METHOD = "auto"
Core.DEBUG_KEYS = false       -- true: in mọi phím gửi đi ra console (F9) để kiểm tra engine có chạy không

local Keys = {held = {}, queue = {}, downFrame = {}, frame = 0, method = nil, errors = 0}
Core.Keys = Keys

local KEY_ENUM = {
    ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
    ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
    shift = "LeftShift", ctrl = "LeftControl", alt = "LeftAlt", space = "Space",
}
local KEY_VK = {shift = 0x10, ctrl = 0x11, alt = 0x12, space = 0x20}   -- mã phím Windows cho keypress()
local keyInfoCache = {}

-- tên phím ("t", "5", "shift"...) -> Enum.KeyCode, mã VK
local function keyInfo(name)
    local c = keyInfoCache[name]
    if c then return c[1] or nil, c[2] or nil end
    local code
    pcall(function() code = Enum.KeyCode[KEY_ENUM[name] or name:upper()] end)
    local vk = KEY_VK[name]
    if not vk and #name == 1 then vk = name:upper():byte() end   -- A-Z và 0-9 trùng mã ASCII
    keyInfoCache[name] = {code or false, vk or false}
    return code, vk
end

local VIM_SERVICE
local function getVIM()
    if VIM_SERVICE == nil then
        local ok, v = pcall(function() return game:GetService("VirtualInputManager") end)
        VIM_SERVICE = (ok and v) or false
    end
    return VIM_SERVICE
end

local function hasKeypress()
    return type(keypress) == "function" and type(keyrelease) == "function"
end

function Keys.pickMethod()
    local want = Core.INPUT_METHOD
    local vim, kp = getVIM() ~= false, hasKeypress()
    local m
    if want == "keypress" and kp then m = "keypress"
    elseif want == "vim" and vim then m = "vim"
    elseif vim then m = "vim"
    elseif kp then m = "keypress"
    end
    Keys.method = m or false
    return Keys.method
end

local function sendVia(method, name, down)
    local code, vk = keyInfo(name)
    if method == "vim" then
        if code then getVIM():SendKeyEvent(down, code, false, game) end
    else
        if vk then
            if down then keypress(vk) else keyrelease(vk) end
        end
    end
end

-- Gửi 1 sự kiện phím thật. Trả về true nếu gửi được.
local function send(name, down)
    if Core.DEBUG_KEYS then print("[tetoMIDI] " .. (down and "down " or "up   ") .. name) end
    if Keys.method == nil then Keys.pickMethod() end
    if not Keys.method then
        Keys.errors = Keys.errors + 1
        if Keys.errors == 1 and Keys.onError then pcall(Keys.onError, "This executor can't send key presses") end
        return false
    end
    if pcall(sendVia, Keys.method, name, down) then return true end
    -- phương thức đang dùng bị lỗi: thử phương thức còn lại
    local other = (Keys.method == "vim") and "keypress" or "vim"
    local available = (other == "vim") and (getVIM() ~= false) or hasKeypress()
    if available and pcall(sendVia, other, name, down) then
        Keys.method = other
        return true
    end
    Keys.errors = Keys.errors + 1
    if Keys.errors == 1 and Keys.onError then pcall(Keys.onError, "Key input failed (try INPUT_METHOD)") end
    return false
end

local function rawDown(name)
    if Keys.held[name] then send(name, false) end   -- bấm lại phím đang giữ: nhả ra trước để game nhận nốt mới
    if send(name, true) then Keys.held[name] = true end
    Keys.downFrame[name] = Keys.frame
end

local function rawUp(name)
    if Keys.held[name] then
        Keys.held[name] = nil
        send(name, false)
    end
end

local MOD_LIST = {"shift", "ctrl", "alt"}
local function sameMods(m)
    for _, n in ipairs(MOD_LIST) do
        if (m[n] and true or false) ~= (Keys.held[n] and true or false) then return false end
    end
    return true
end
local function applyMods(m)
    for _, n in ipairs(MOD_LIST) do
        if Keys.held[n] and not m[n] then rawUp(n) end
    end
    for _, n in ipairs(MOD_LIST) do
        if m[n] and not Keys.held[n] then rawDown(n) end
    end
end

Keys.NONE  = {}                 -- không giữ Shift/Ctrl/Alt
Keys.SHIFT = {shift = true}
Keys.CTRL  = {ctrl = true}
Keys.ALT   = {alt = true}

-- Bấm phím `name`. mods = Keys.NONE/SHIFT/CTRL/ALT (modifier cần giữ lúc bấm), nil = không quan tâm (vd Space).
-- Console (xem phím đang chạy): Keys.onLog được UI gán vào; không ảnh hưởng cách gửi phím
Keys.onLog = nil
local function keyLog(kind, name, mods)
    if Keys.onLog then pcall(Keys.onLog, kind, name, mods) end
end

function Keys.down(name, mods)
    Keys.queue[#Keys.queue + 1] = {k = name, down = true, mods = mods}
    keyLog("DOWN", name, mods)
    if keyHook then pcall(keyHook, name) end   -- gõ phím giả (chỉ khi bật trong cài đặt)
end

function Keys.up(name)
    Keys.queue[#Keys.queue + 1] = {k = name, down = false}
    keyLog("UP", name, nil)
end

-- Gọi 1 lần mỗi Heartbeat (sau khi các player chạy xong). Thực thi hàng đợi với các quy tắc:
--  * phím chỉ được nhả từ khung hình sau khi bấm (giữ tối thiểu 1 khung hình để game kịp nhận);
--  * đổi modifier (Shift/Ctrl/Alt) sau khi vừa bấm phím dưới modifier cũ thì đợi sang khung sau, để game đọc đúng
--    trạng thái modifier lúc nhận phím (giống thứ tự "giữ Shift, bấm phím, nhả Shift" của app trên PC).
--    Thao tác cần modifier khác bị hoãn, các thao tác sau vẫn chạy nếu hợp modifier hiện tại -> hợp âm lẫn nốt
--    thường + nốt Shift vẫn ra gần như cùng lúc;
--  * thao tác của CÙNG 1 phím luôn giữ đúng thứ tự; thao tác velocity (Alt) không bao giờ vượt qua thao tác đang hoãn,
--    và khi 1 phím velocity bị hoãn thì mọi thao tác sau nó cũng đợi (để mỗi nốt nhận đúng velocity của nó).
function Keys.pump()
    Keys.frame = Keys.frame + 1
    local frame = Keys.frame
    local q = Keys.queue
    local keep, nkeep = {}, 0
    local waiting, altWait, barrier, dirty = {}, false, false, false
    for i = 1, #q do
        local op = q[i]
        local k = op.k
        local run = not waiting[k] and not barrier
        if run then
            if op.down then
                local m = op.mods
                if m and m.alt and altWait then
                    run = false
                elseif m and not sameMods(m) then
                    if dirty then run = false else applyMods(m) end
                end
            elseif Keys.downFrame[k] == frame then
                run = false
            end
        end
        if run then
            if op.down then
                rawDown(k)
                if op.mods then dirty = true end
            else
                rawUp(k)
            end
        else
            nkeep = nkeep + 1
            keep[nkeep] = op
            waiting[k] = true
            altWait = true
            if op.mods and op.mods.alt then barrier = true end   -- phím velocity bị hoãn: mọi thứ sau nó đợi theo
        end
    end
    Keys.queue = keep
    -- khung này không bấm phím nào dưới modifier: thả Shift/Ctrl/Alt còn giữ (thao tác đang chờ sẽ tự giữ lại khi cần)
    if not dirty then
        for _, n in ipairs(MOD_LIST) do rawUp(n) end
    end
end

-- Thả hết mọi phím ngay lập tức (dừng / tạm dừng / tua / đổi tab)
function Keys.releaseAll()
    Keys.queue = {}
    local names = {}
    for name in pairs(Keys.held) do names[#names + 1] = name end
    Keys.held = {}
    for _, name in ipairs(names) do send(name, false) end
    Keys.downFrame = {}
end

-- ---------------------------------------------------------------- Dispatcher (dispatchers.py)
local Engine = {}
Core.Engine = Engine

local SHIFTED_SYMBOLS = {["!"] = true, ["@"] = true, ["$"] = true, ["%"] = true, ["^"] = true, ["*"] = true, ["("] = true}

local VEL_THRESHOLDS = {}
for k in pairs(Core.VELOCITY_MAP) do VEL_THRESHOLDS[#VEL_THRESHOLDS + 1] = k end
table.sort(VEL_THRESHOLDS)

-- Phím velocity (Alt + phím) cho một velocity MIDI: cùng thuật toán tìm kiếm với app
function Engine.velocityKey(velocity)
    local t, n = VEL_THRESHOLDS, #VEL_THRESHOLDS
    local lo, hi, idx = 0, n - 1, 0
    while lo <= hi do
        idx = math.floor((lo + hi) / 2)
        if idx == 0 or idx == n - 1 then break end
        if t[idx + 1] < velocity then lo = idx + 1 else hi = idx - 1 end
    end
    return Core.VELOCITY_MAP[t[idx + 1]]
end

-- Sự kiện MIDI (bật/tắt nốt, pedal) của 1 bài theo từng nhạc cụ (giống Song.view của app)
function Core.songEvents(song, mode, skipPercussion)
    local only = (mode == "drums") and song.hasPerc
    local out = {}
    for _, e in ipairs(song.events) do
        local keep
        if mode == "drums" then
            keep = (not only) or e.ch == Core.PERCUSSION_CHANNEL
        else
            keep = not (skipPercussion ~= false and e.ch == Core.PERCUSSION_CHANNEL)
        end
        if e.kind == 2 and mode ~= "piano" then keep = false end
        if keep then out[#out + 1] = e end
    end
    return out
end

-- C = Cfg[mode] (đọc trực tiếp nên bật/tắt nút trên UI có tác dụng ngay)
function Engine.newDispatcher(mode, C)
    local D = {now = 0, timers = {}, gen = {}, sustain = false}

    -- "Note length" tắt: mọi phím chỉ chạm ngắn bằng nhau rồi tự thả
    local function tap(key, mods)
        Keys.down(key, mods)
        if C.noteLengths == false then
            D.gen[key] = (D.gen[key] or 0) + 1
            D.timers[#D.timers + 1] = {due = D.now + Core.SHORT_NOTE, key = key, gen = D.gen[key]}
        end
    end

    -- phím máy tính + modifier thật sự được bấm cho 1 nốt: key, mods (nil = nốt không có phím)
    local noteKey

    if mode == "piano" then
        local function resolve(note)
            local k = Core.PIANO_61[note]
            if k then return k end
            if C.k88 ~= false then return Core.PIANO_88_LOW[note] or Core.PIANO_88_HIGH[note] end
            return nil
        end
        noteKey = function(note)
            local key = resolve(note)
            if not key then return nil end
            local lower = key:lower()
            if note >= 36 and note <= 96 then
                if SHIFTED_SYMBOLS[key] then        -- nốt đen dạng ký hiệu: Shift + phím của nốt ngay dưới
                    return Core.PIANO_61[note - 1] or lower, Keys.SHIFT
                elseif key ~= lower then            -- chữ hoa: Shift + chữ thường
                    return lower, Keys.SHIFT
                end
                return key, Keys.NONE
            end
            return lower, Keys.CTRL                 -- ngoài 36..96 (88 phím): lớp Ctrl
        end

        function D.noteOn(note, velocity)
            local key, mods = noteKey(note)
            if not key then return end
            if C.velocity then
                local vk = Engine.velocityKey(velocity)
                Keys.down(vk, Keys.ALT)
                Keys.up(vk)
            end
            tap(key, mods)
        end

        function D.noteOff(note)
            if C.noteLengths == false then return end
            local key = noteKey(note)
            if key then Keys.up(key) end
        end

        function D.control(cc, value)
            if cc ~= 64 or not C.sustain then return end
            local cutoff = 63
            if not D.sustain and value > cutoff then
                D.sustain = true
                Keys.down("space", nil)
            elseif D.sustain and value < cutoff then
                D.sustain = false
                Keys.up("space")
            end
        end

    elseif mode == "drums" then
        noteKey = function(note)
            local name = Core.DRUM_NOTE_TO_NAME[note]
            local k = name and Core.DRUMS_MAP[name]
            if k and k ~= "" then return k:lower(), nil end
            return nil
        end

        function D.noteOn(note)
            local key = noteKey(note)
            if key then tap(key, nil) end
        end

        function D.noteOff(note)
            if C.noteLengths == false then return end
            local key = noteKey(note)
            if key then Keys.up(key) end
        end

    else   -- guitar
        noteKey = function(note)
            local resolved = Core.guitarResolveNote(note, Core.GUITAR_KEYMAP, C.fold ~= false)
            local key = resolved and Core.GUITAR_KEYMAP[resolved]
            if not key or key == "" then return nil end
            local lower = key:lower()
            return lower, (key ~= lower) and Keys.SHIFT or Keys.NONE
        end

        function D.noteOn(note)
            local key, mods = noteKey(note)
            if key then tap(key, mods) end
        end

        function D.noteOff(note)
            if C.noteLengths == false then return end
            local key = noteKey(note)
            if key then Keys.up(key) end
        end
    end

    if not D.control then function D.control() end end

    -- thả các phím "chạm ngắn" đã tới hạn (thời gian bài hát, nên đổi tốc độ vẫn đúng)
    function D.advance(now)
        D.now = now
        local ts = D.timers
        if #ts == 0 then return end
        local rest = {}
        for _, t in ipairs(ts) do
            if t.due <= now then
                if D.gen[t.key] == t.gen then Keys.up(t.key) end   -- đã bị bấm lại thì không thả nhầm
            else
                rest[#rest + 1] = t
            end
        end
        D.timers = rest
    end

    function D.releaseAll()
        D.timers = {}
        D.gen = {}
        D.sustain = false
        Keys.releaseAll()
    end

    return D
end

-- Gắn engine vào 1 player: P.onAdvance / P.onStop / P.onStart là các hook mà createPlayerPage đã gọi sẵn.
-- Trả về {load = function(song) ... end, dispatcher = D}
function Engine.attach(P, C, mode)
    local D = Engine.newDispatcher(mode, C)
    local events, times, n = {}, {}, 0
    local idx, lastPos = 1, nil
    local eng = {dispatcher = D}

    -- đổi bài: nạp lại danh sách sự kiện
    function eng.load(song)
        events = song and Core.songEvents(song, mode, true) or {}
        times = {}
        for i, e in ipairs(events) do times[i] = e.time end
        n = #events
        idx, lastPos = 1, nil
        D.releaseAll()
    end

    local function firstAtOrAfter(pos)   -- sự kiện đầu tiên có time >= pos (tìm nhị phân)
        local lo, hi = 1, n + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if times[mid] < pos then lo = mid + 1 else hi = mid end
        end
        return lo
    end

    local function dispatch(ev)
        if ev.kind == 1 then
            if mode == "piano" and not Core.handAllows(Cfg.hand.mode, ev.note) then return end
            D.noteOn(ev.note, ev.value)
        elseif ev.kind == 0 then D.noteOff(ev.note)
        else D.control(ev.note, ev.value) end
    end

    function P.onAdvance(old, new)
        -- vị trí đổi so với lần trước (mới phát / dừng / tua / lặp bài): tìm lại chỗ. Tiếp tục sau tạm dừng thì giữ nguyên.
        if lastPos == nil or old ~= lastPos then idx = firstAtOrAfter(old) end
        lastPos = new
        D.advance(new)
        while idx <= n and times[idx] <= new do
            local ev = events[idx]
            idx = idx + 1
            local ok, err = pcall(dispatch, ev)
            if not ok then warn("[tetoMIDI] engine: " .. tostring(err)) end
        end
    end

    function P.onStop()
        D.releaseAll()   -- thả hết phím (lastPos giữ lại để biết đây là tạm dừng hay tua)
    end

    function P.onStart()
        -- đang gõ chữ trong ô tìm kiếm thì phím sẽ rơi vào ô đó -> bỏ focus trước khi phát
        pcall(function()
            local tb = UserInputService:GetFocusedTextBox()
            if tb then tb:ReleaseFocus() end
        end)
    end

    return eng
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
local SIDEBAR_W = 132

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
    local function showToast(text, duration)
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

        task.delay(duration or 1.9, function()
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
    main.Size = UDim2.new(0.7, 0, 0.8, 0)
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

    -- Lớp bắt chuột nằm DƯỚI cùng: bấm/kéo vào bất kỳ chỗ trống nào của cửa sổ đều di chuyển được
    -- (nút, ô nhập, danh sách cuộn nằm trên lớp này nên vẫn hoạt động bình thường)
    local dragLayer = Instance.new("Frame")
    dragLayer.Name = "DragLayer"
    dragLayer.Size = UDim2.new(1, 0, 1, 0)
    dragLayer.BackgroundTransparency = 1
    dragLayer.BorderSizePixel = 0
    dragLayer.Active = true
    dragLayer.Parent = main

    local mainScale = Instance.new("UIScale")
    mainScale.Scale = 0.85
    mainScale.Parent = main

    local sizeLimit = Instance.new("UISizeConstraint")
    sizeLimit.MinSize = Vector2.new(380, 280)
    sizeLimit.MaxSize = Vector2.new(680, 430)
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
        openTween = TweenService:Create(main, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = Cfg.ui.alpha})
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

    -- Trạng thái mini player (khai báo trước để bubble dùng được)
    local miniMode = false
    local fromMini

    -- Bật/tắt bằng bubble
    bubble.MouseButton1Click:Connect(function()
        if bubbleMoved then return end
        playClick()
        if miniMode then fromMini() elseif MainVisible then closeMain() else openMain() end
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

    -- ===== KÉO CỬA SỔ =====
    -- Kéo được từ: lớp nền (chỗ trống), sidebar, vùng nội dung, logo + tên.
    -- Có ngưỡng 4px để bấm nút không bị xê dịch; tự chặn không cho cửa sổ trôi ra ngoài màn hình.
    local function viewportSize()
        local cam = workspace.CurrentCamera
        local vp = (cam and cam.ViewportSize) or Vector2.new(0, 0)
        if vp.X < 100 or vp.Y < 100 then vp = gui.AbsoluteSize end
        if vp.X < 100 or vp.Y < 100 then vp = Vector2.new(800, 400) end
        return vp
    end

    local winDrag = nil   -- {start = Vector3, center = Vector2, moved = bool}
    local winRef = main   -- cửa sổ đang kéo: khung lớn (main) hoặc mini

    local function beginWindowDrag(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if winDrag then return end
        winDrag = {
            input = input,
            start = input.Position,
            center = winRef.AbsolutePosition + winRef.AbsoluteSize / 2,
            moved = false,
        }
    end

    local function bindWindowDrag(obj)
        obj.InputBegan:Connect(beginWindowDrag)
    end

    bindWindowDrag(dragLayer)
    bindWindowDrag(sidebar)

    UserInputService.InputChanged:Connect(function(input)
        if not winDrag then return end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
        -- cảm ứng nhiều ngón: chỉ theo dõi đúng ngón đã bắt đầu kéo
        if t == Enum.UserInputType.Touch and input ~= winDrag.input then return end
        -- bấm vào nút / ô nhập / danh sách / thanh tua: không kéo cửa sổ
        if UI_CLAIM[winDrag.input] then winDrag = nil; return end

        local delta = input.Position - winDrag.start
        if not winDrag.moved then
            if math.abs(delta.X) < 4 and math.abs(delta.Y) < 4 then return end
            winDrag.moved = true
        end

        local vp = viewportSize()
        local half = winRef.AbsoluteSize / 2
        local keep = 60   -- luôn chừa lại ít nhất 60px của cửa sổ trong màn hình
        local cx = math.clamp(winDrag.center.X + delta.X, keep - half.X, vp.X - keep + half.X)
        local cy = math.clamp(winDrag.center.Y + delta.Y, keep - half.Y, vp.Y - keep + half.Y)
        winRef.Position = UDim2.new(0, cx, 0, cy)
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not winDrag then return end
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == winDrag.input) then
            winDrag = nil
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
    logoTitle.Text = "tetoMIDI v2.3"
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
        btn.Size = UDim2.new(1, -16, 0, 32)
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
        label.TextSize = 12
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

    makeNavBtn("piano player", "piano.png", 46, "piano")
    makeNavBtn("drum player", "drum.png", 82, "drums")
    makeNavBtn("guitar player", "guitar.png", 118, "guitar")
    makeNavBtn("midi store", "hub.png", 154, "hub")

    -- Nút Discord (dưới cùng sidebar): bấm = copy link + thông báo
    local discordBtn = Instance.new("TextButton")
    discordBtn.Name = "Discord"
    discordBtn.AnchorPoint = Vector2.new(0, 1)
    discordBtn.Size = UDim2.new(1, -16, 0, 32)
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

    -- ===== THANH TIÊU ĐỀ (nút mini / console nằm bên phải, tạo ở cuối) =====
    local HEADER_H = 30
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
    header.Size = UDim2.new(1, -SIDEBAR_W, 0, HEADER_H)
    header.BackgroundTransparency = 1
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = main
    bindWindowDrag(header)

    -- ===== CONTENT =====
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -SIDEBAR_W, 1, -HEADER_H)
    content.Position = UDim2.new(0, SIDEBAR_W, 0, HEADER_H)
    content.BackgroundTransparency = 1
    content.Parent = main
    bindWindowDrag(content)

    -- ===== PIANO ROLL + TRANG PLAYER (piano / drum / guitar) =====
    -- Cùng một bố cục cho 3 trang (như app tetoMIDI): chọn file MIDI, các nút bật/tắt, piano roll, PLAY/STOP.
    local ROLL_BG    = Color3.fromRGB(4, 5, 7)
    local KEY_WHITE  = Color3.fromRGB(230, 230, 230)
    local KEY_BLACK  = Color3.fromRGB(43, 43, 43)
    local PAD_COL    = Color3.fromRGB(21, 24, 30)
    local LANE_LINE  = Color3.fromRGB(14, 18, 25)
    -- Màu nốt rơi: đọc từ Cfg.note.color (hex RRGGBB), đổi được trong cài đặt
    local function hexColor(hex)
        if type(hex) == "string" and #hex == 6 and hex:match("^%x+$") then
            return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
        end
        return Color3.fromRGB(75, 132, 175)
    end
    local NOTE_BODY  = hexColor(Cfg.note.color)
    local NOTE_LIT   = NOTE_BODY:Lerp(WHITE, 0.1)
    local LBL_WHITE  = Color3.fromRGB(42, 42, 42)
    local LBL_BLACK  = Color3.fromRGB(240, 240, 240)
    local LBL_CTRL_W = Color3.fromRGB(31, 95, 153)
    local LBL_CTRL_B = Color3.fromRGB(140, 195, 234)
    local MAX_NOTES_DRAWN = 160
    local ROLL_KB = 0.24         -- phần chiều cao của roll dành cho bàn phím / pad

    local VEL_SHADES = {}
    local noteHitLines = {}      -- vạch trúng phím của các roll (đổi màu cùng lúc)
    local function applyNoteColor()
        NOTE_BODY = hexColor(Cfg.note.color)
        NOTE_LIT = NOTE_BODY:Lerp(WHITE, 0.1)
        for i = 1, 8 do
            VEL_SHADES[i] = ROLL_BG:Lerp(NOTE_BODY, 0.38 + 0.62 * i / 8)
        end
        for _, h in ipairs(noteHitLines) do h.BackgroundColor3 = NOTE_LIT end
    end
    applyNoteColor()

    local players = {}           -- [mode] = player (xem createPlayerPage)

    local function textFit(label, maxSize)
        label.TextScaled = true
        local c = Instance.new("UITextSizeConstraint")
        c.MaxTextSize = maxSize
        c.MinTextSize = 1
        c.Parent = label
    end

    -- ---------------------------------------------------------------- ROLL
    local function createRoll(parent, mode)
        local R = {data = Core.buildRoll(mode, {}, {})}

        local frame = Instance.new("Frame")
        frame.Name = "Roll"
        frame.BackgroundColor3 = ROLL_BG
        frame.BackgroundTransparency = 0.08
        frame.BorderSizePixel = 0
        frame.ClipsDescendants = true
        frame.Parent = parent
        round(frame, UDim.new(0, 10))
        makeRim(frame, 1.2, 0.5)
        R.frame = frame

        -- Ảnh nền của roll (nil/"" = bỏ ảnh, trả lại nền mặc định)
        function R.setBackground(assetId)
            local img = frame:FindFirstChild("BgImage")
            if assetId == nil or assetId == "" then
                if img then img:Destroy() end
                frame.BackgroundTransparency = 0.08
                return
            end
            if not img then
                img = Instance.new("ImageLabel")
                img.Name = "BgImage"
                img.BackgroundTransparency = 1
                img.Size = UDim2.new(1, 0, 1, 0)
                img.ScaleType = Enum.ScaleType.Crop
                img.ImageTransparency = 0.35
                img.ZIndex = 0
                img.Parent = frame
            end
            img.Image = assetId
            frame.BackgroundTransparency = 1
        end

        local fall = Instance.new("Frame")
        fall.Name = "Fall"
        fall.BackgroundTransparency = 1
        fall.BorderSizePixel = 0
        fall.Size = UDim2.new(1, 0, 1 - ROLL_KB, 0)
        fall.ClipsDescendants = true
        fall.Parent = frame

        local guides = Instance.new("Frame")        -- vạch kẻ làn (nằm dưới nốt)
        guides.Name = "Guides"
        guides.BackgroundTransparency = 1
        guides.Size = UDim2.new(1, 0, 1, 0)
        guides.ZIndex = 0
        guides.Parent = fall

        local kb = Instance.new("Frame")
        kb.Name = "Keys"
        kb.BackgroundTransparency = 1
        kb.Position = UDim2.new(0, 0, 1 - ROLL_KB, 0)
        kb.Size = UDim2.new(1, 0, ROLL_KB, 0)
        kb.Parent = frame

        local hitLine = Instance.new("Frame")
        hitLine.BackgroundColor3 = NOTE_LIT
        noteHitLines[#noteHitLines + 1] = hitLine
        hitLine.BackgroundTransparency = 0.45
        hitLine.BorderSizePixel = 0
        hitLine.Position = UDim2.new(0, 0, 1 - ROLL_KB, -1)
        hitLine.Size = UDim2.new(1, 0, 0, 2)
        hitLine.ZIndex = 4
        hitLine.Parent = frame

        local caption = Instance.new("TextLabel")
        caption.BackgroundTransparency = 1
        caption.Position = UDim2.new(0, 10, 0, 5)
        caption.Size = UDim2.new(1, -20, 0, 14)
        caption.Font = Enum.Font.GothamMedium
        caption.TextSize = 11
        caption.TextColor3 = gray(190)
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.TextTruncate = Enum.TextTruncate.AtEnd
        caption.Text = ""
        caption.ZIndex = 6
        caption.Parent = frame

        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.BackgroundTransparency = 1
        emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        emptyLabel.Position = UDim2.new(0.5, 0, (1 - ROLL_KB) / 2, 0)
        emptyLabel.Size = UDim2.new(1, -20, 0, 20)
        emptyLabel.Font = Enum.Font.GothamMedium
        emptyLabel.TextSize = 13
        emptyLabel.TextColor3 = gray(120)
        emptyLabel.Text = "Select a MIDI file to start"
        emptyLabel.ZIndex = 6
        emptyLabel.Parent = frame

        local keyFrames, keyBase, laneRect, fretLabels = {}, {}, {}, {}
        local pool, poolUsed = {}, 0
        local litSet = {}
        local lastPos = nil

        local function clearKeys()
            for _, c in ipairs(kb:GetChildren()) do c:Destroy() end
            for _, c in ipairs(guides:GetChildren()) do c:Destroy() end
            keyFrames, keyBase, laneRect, fretLabels, litSet = {}, {}, {}, {}, {}
        end

        local function guideLine(x)
            local g = Instance.new("Frame")
            g.BackgroundColor3 = LANE_LINE
            g.BorderSizePixel = 0
            g.Position = UDim2.new(x, 0, 0, 0)
            g.Size = UDim2.new(0, 1, 1, 0)
            g.Parent = guides
        end

        local function keyLabel(parent, text, color, y, h)
            local l = Instance.new("TextLabel")
            l.BackgroundTransparency = 1
            l.Position = UDim2.new(0, 0, y, 0)
            l.Size = UDim2.new(1, 0, h, 0)
            l.Font = Enum.Font.GothamBold
            l.Text = text
            l.TextColor3 = color
            l.ZIndex = 3
            textFit(l, 12)
            l.Parent = parent
            return l
        end

        local function buildKeys()
            clearKeys()
            if mode == "piano" then
                local lo, hi = R.data.lo, R.data.hi
                local whites = {}
                for p = lo, hi do
                    if not Core.isBlack(p) then whites[#whites + 1] = p end
                end
                local ww = 1 / #whites
                local wx = {}
                for i, p in ipairs(whites) do wx[p] = (i - 1) * ww end

                for _, p in ipairs(whites) do
                    local f = Instance.new("Frame")
                    f.Position = UDim2.new(wx[p], 0, 0, 0)
                    f.Size = UDim2.new(ww, -1, 1, 0)
                    f.BackgroundColor3 = KEY_WHITE
                    f.BorderSizePixel = 0
                    f.Parent = kb
                    keyFrames[p], keyBase[p] = f, KEY_WHITE
                    laneRect[p] = {wx[p] + ww * 0.1, ww * 0.8}
                    if p % 12 == 0 and p ~= lo then guideLine(wx[p]) end
                    local k, ctrl = Core.pianoKeyFor(p)
                    if k then keyLabel(f, k, ctrl and LBL_CTRL_W or LBL_WHITE, 0.68, 0.3) end
                end

                local bw = ww * 0.6
                for p = lo, hi do
                    if Core.isBlack(p) and wx[p - 1] then
                        local cx = wx[p - 1] + ww
                        local f = Instance.new("Frame")
                        f.Position = UDim2.new(cx - bw / 2, 0, 0, 0)
                        f.Size = UDim2.new(bw, 0, 0.62, 0)
                        f.BackgroundColor3 = KEY_BLACK
                        f.BorderSizePixel = 0
                        f.ZIndex = 2
                        f.Parent = kb
                        keyFrames[p], keyBase[p] = f, KEY_BLACK
                        laneRect[p] = {cx - bw * 0.4, bw * 0.8}
                        local k, ctrl = Core.pianoKeyFor(p)
                        if k then keyLabel(f, k, ctrl and LBL_CTRL_B or LBL_BLACK, 0.45, 0.5) end
                    end
                end
            else
                local labels
                if mode == "drums" then
                    labels = Core.drumLaneLabels()
                else
                    labels = {}
                    for i, s in ipairs(Core.GUITAR_STRING_LABELS) do labels[i] = {s, ""} end
                end
                local n = #labels
                local lw = 1 / n
                for i, lb in ipairs(labels) do
                    local x0 = (i - 1) * lw
                    if i > 1 then guideLine(x0) end
                    local pad = Instance.new("Frame")
                    pad.Position = UDim2.new(x0, 2, 0, 3)
                    pad.Size = UDim2.new(lw, -4, 1, -6)
                    pad.BackgroundColor3 = PAD_COL
                    pad.BorderSizePixel = 0
                    pad.Parent = kb
                    round(pad, UDim.new(0, 6))
                    keyFrames[i], keyBase[i] = pad, PAD_COL
                    laneRect[i] = {x0 + lw * 0.16, lw * 0.68}

                    local name = Instance.new("TextLabel")
                    name.BackgroundTransparency = 1
                    name.Position = UDim2.new(0, 2, 0, 2)
                    name.Size = UDim2.new(1, -4, 0.5, 0)
                    name.Font = Enum.Font.GothamBold
                    name.Text = lb[1]
                    name.TextColor3 = gray(228)
                    name.ZIndex = 3
                    textFit(name, mode == "guitar" and 16 or 12)
                    name.Parent = pad
                    if lb[2] ~= "" then
                        local hint = Instance.new("TextLabel")
                        hint.BackgroundTransparency = 1
                        hint.Position = UDim2.new(0, 2, 0.52, 0)
                        hint.Size = UDim2.new(1, -4, 0.4, 0)
                        hint.Font = Enum.Font.Gotham
                        hint.Text = lb[2]
                        hint.TextColor3 = gray(163)
                        hint.ZIndex = 3
                        textFit(hint, 11)
                        hint.Parent = pad
                    end
                    if mode == "guitar" then   -- số phím đàn đang bấm (hiện khi nốt sáng)
                        local fret = Instance.new("TextLabel")
                        fret.BackgroundTransparency = 1
                        fret.Position = UDim2.new(0, 2, 0.5, 0)
                        fret.Size = UDim2.new(1, -4, 0.45, 0)
                        fret.Font = Enum.Font.GothamBold
                        fret.Text = ""
                        fret.TextColor3 = WHITE
                        fret.Visible = false
                        fret.ZIndex = 3
                        textFit(fret, 14)
                        fret.Parent = pad
                        fretLabels[i] = fret
                    end
                end
            end
        end

        local function newNote()
            local f = Instance.new("Frame")
            f.BackgroundColor3 = NOTE_BODY
            f.BorderSizePixel = 0
            f.Visible = false
            f.ZIndex = 1
            f.Parent = fall
            round(f, UDim.new(0, 2))
            return f
        end

        local function lightKey(lane, idx)
            local k = keyFrames[lane]
            if k then k.BackgroundColor3 = NOTE_LIT end
            local fl = fretLabels[lane]
            if fl then fl.Visible = true end
        end

        local function unlightKey(lane)
            local k = keyFrames[lane]
            if k then k.BackgroundColor3 = keyBase[lane] end
            local fl = fretLabels[lane]
            if fl then fl.Visible = false end
        end

        -- ===== PIANO ROLL 3D (phối cảnh giả bằng Frame 2D) =====
        -- Nốt càng xa phím thì càng nhỏ và co về giữa, các làn hội tụ về phía trên, nốt xa tối dần.
        -- Mặc định tắt (2D). Bật bằng nút "3D roll" trên trang piano.
        local P3_K = 1.6
        local function persDepth(d) return d * (1 + P3_K) / (1 + P3_K * d) end  -- vị trí dọc (0 = phím, 1 = xa nhất)
        local function persScale(d) return 1 / (1 + P3_K * d) end               -- hệ số co ngang
        R.threeD = false
        function R.set3D(on)
            R.threeD = on and true or false
            guides.Visible = not R.threeD   -- vạch kẻ thẳng không hợp với phối cảnh, tắt khi 3D
            R.refresh()
        end

        -- Vẽ khung hình tại vị trí `pos` (giây)
        function R.render(pos, force)
            if not force and pos == lastPos then return end
            lastPos = pos
            R.pos = pos
            local data = R.data
            local look = math.max(0.5, Cfg.roll.fall or 3)
            local first, last = data:window(pos, look)
            local useVel = (mode == "piano" and Cfg.piano.velocity) and true or false
            local minH = (mode == "piano") and 0.02 or 0.05
            local lit = {}
            local used = 0

            for i = first, last do
                local e = data.ends[i]
                if e > pos then
                    local lane = data.lanes[i]
                    local rect = laneRect[lane]
                    if rect then
                        local s = data.starts[i]
                        local y1 = math.min(1 - (s - pos) / look, 1)
                        local y0 = math.max(1 - (e - pos) / look, 0)
                        if y1 > 0 then
                            if used >= MAX_NOTES_DRAWN then break end
                            if y1 - y0 < minH then y0 = y1 - minH end
                            local active = (s <= pos)
                            if active then lit[lane] = i end
                            used = used + 1
                            local f = pool[used]
                            if not f then f = newNote(); pool[used] = f end
                            local dm = 1 - (y0 + y1) / 2
                            if R.threeD then
                                local sc = persScale(dm)
                                f.Position = UDim2.new(0.5 + (rect[1] - 0.5) * sc, 0, 1 - persDepth(1 - y0), 0)
                                f.Size = UDim2.new(rect[2] * sc, 0, persDepth(1 - y0) - persDepth(1 - y1), 0)
                            else
                                f.Position = UDim2.new(rect[1], 0, y0, 0)
                                f.Size = UDim2.new(rect[2], 0, y1 - y0, 0)
                            end
                            local col
                            if active then
                                col = NOTE_LIT
                            elseif useVel then
                                col = VEL_SHADES[math.min(math.floor(data.vels[i] * 8 / 128) + 1, 8)]
                            else
                                col = NOTE_BODY
                            end
                            if R.threeD and not active then col = col:Lerp(ROLL_BG, 0.5 * dm) end
                            if f.BackgroundColor3 ~= col then f.BackgroundColor3 = col end
                            if not f.Visible then f.Visible = true end
                        end
                    end
                end
            end
            for k = used + 1, poolUsed do
                local f = pool[k]
                if f and f.Visible then f.Visible = false end
            end
            poolUsed = used

            for lane in pairs(litSet) do
                if not lit[lane] then
                    unlightKey(lane)
                    litSet[lane] = nil
                end
            end
            for lane, idx in pairs(lit) do
                if not litSet[lane] then lightKey(lane, idx) end
                litSet[lane] = true
                local fl = fretLabels[lane]
                if fl then
                    local txt = tostring(data.frets[idx])
                    if fl.Text ~= txt then fl.Text = txt end
                end
            end
        end

        -- data mới (đổi file / đổi 88 key / đổi note length ...)
        function R.setData(data)
            local rebuild = (R.data.lo ~= data.lo) or (R.data.hi ~= data.hi) or (next(keyFrames) == nil)
            R.data = data
            if rebuild then buildKeys() end
            emptyLabel.Visible = (data.n == 0)
            R.render(R.pos or 0, true)
        end

        function R.setCaption(text) caption.Text = text or "" end
        function R.setEmpty(text)
            emptyLabel.Text = text or ""
            emptyLabel.Visible = (R.data.n == 0) and (text ~= nil and text ~= "")
        end
        function R.refresh() R.render(R.pos or 0, true) end

        buildKeys()
        return R
    end

    -- ---------------------------------------------------------------- PAGE
    local PLAYER_OPTIONS = {
        piano  = {{"88 key", "k88"}, {"Sustain", "sustain"}, {"Velocity", "velocity"}, {"Note length", "noteLengths"}, {"Loop", "loop"}, {"3D roll", "roll3d"}},
        drums  = {{"Note length", "noteLengths"}, {"Loop", "loop"}},
        guitar = {{"Note length", "noteLengths"}, {"Loop", "loop"}},
    }
    local PLAYER_CAPTION = {piano = "Piano roll", drums = "Drum pads", guitar = "Guitar strings"}

    local function makeTextButton(parent, text, size, font)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.Text = text
        b.TextColor3 = WHITE
        b.Font = font or Enum.Font.GothamBold
        b.TextSize = size or 12
        b.AutoButtonColor = false
        b.Parent = parent
        softText(b)
        return b
    end

    -- opts.isolated = true: bản riêng (preview của hub). Có config, file và trạng thái riêng,
    -- không ghi vào Cfg của piano player và không đụng tới players.piano.
    local function createPlayerPage(mode, opts)
        local isolated = opts and opts.isolated or false
        local key = (opts and opts.key) or mode
        local P = {mode = mode, state = "stopped", pos = 0, length = 0, speed = 1, song = nil, notes = {}, name = ""}
        local C = isolated and {k88 = true, sustain = false, velocity = false, noteLengths = true, loop = false, file = ""} or Cfg[mode]
        players[key] = P

        local page = Instance.new("Frame")
        page.Name = "Page_" .. key
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.Parent = content
        P.page = page

        -- Hàng trên: chọn file MIDI
        local filePill = makePill(page, UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 0, 8))
        local fileBtn = makeTextButton(filePill, "select MIDI file", 12, Enum.Font.GothamMedium)
        fileBtn.TextTruncate = Enum.TextTruncate.AtEnd
        hoverGlass(fileBtn, filePill)
        bindClick(fileBtn)

        -- Bản preview của hub: nút quay lại trang hub ở góc phải
        if isolated then
            filePill.Size = UDim2.new(1, -124, 0, 26)
            local backPill = makePill(page, UDim2.new(0, 96, 0, 26), UDim2.new(1, -108, 0, 8))
            local backBtn = makeTextButton(backPill, "< hub", 12, Enum.Font.GothamMedium)
            hoverGlass(backBtn, backPill)
            bindClick(backBtn)
            backBtn.MouseButton1Click:Connect(function()
                pressAnim(backPill)
                CurrentPage = "hub"
                updatePages()
            end)
        end

        -- Hàng nút bật/tắt (88 key / Sustain / Velocity / Note length / Loop)
        local opts = PLAYER_OPTIONS[mode]
        local chipRow = Instance.new("Frame")
        chipRow.BackgroundTransparency = 1
        chipRow.Position = UDim2.new(0, 12, 0, 40)
        chipRow.Size = UDim2.new(1, -24, 0, 24)
        chipRow.Parent = page
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = UDim2.new(1 / #opts, -4, 1, 0)
        grid.CellPadding = UDim2.new(0, 4, 0, 0)
        grid.FillDirection = Enum.FillDirection.Horizontal
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.Parent = chipRow

        local chips = {}
        local function paintChip(key)
            local ch = chips[key]
            local on = C[key] and true or false
            ch.pill.BackgroundColor3 = on and NOTE_LIT or GLASS_WHITE
            setGlassBase(ch.pill, on and 0.3 or 0.86)
        end

        -- Roll
        local roll = createRoll(page, mode)
        if mode == "piano" then roll.set3D(C.roll3d) end
        roll.frame.Position = UDim2.new(0, 12, 0, 70)
        roll.frame.Size = UDim2.new(1, -24, 1, -70 - 44)
        P.roll = roll

        local function rebuildRoll()
            local data = Core.buildRoll(mode, P.notes, {k88 = C.k88, noteLengths = C.noteLengths})
            roll.setData(data)
            if P.song then
                roll.setEmpty(data.n == 0 and "No playable notes in this file" or nil)
            else
                roll.setEmpty("Select a MIDI file to start")
            end
        end
        P.rebuildRoll = rebuildRoll

        -- Bật/tắt 1 tuỳ chọn (dùng chung cho chip trên trang và chip trong mini player)
        function P.toggleOpt(key)
            C[key] = not C[key]
            if chips[key] then paintChip(key) end
            if not isolated then saveCfg() end
            if key == "k88" or key == "noteLengths" then
                rebuildRoll()
            elseif key == "velocity" then
                roll.refresh()
            elseif key == "roll3d" then
                roll.set3D(C.roll3d)
            end
        end
        P.C = C
        P.opts = opts

        for i, o in ipairs(opts) do
            local pill = makePill(chipRow, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0))
            pill.LayoutOrder = i
            local b = makeTextButton(pill, o[1], 12)
            textFit(b, 12)
            hoverGlass(b, pill)
            bindClick(b)
            chips[o[2]] = {pill = pill, btn = b}
            paintChip(o[2])
            b.MouseButton1Click:Connect(function()
                pressAnim(pill)
                P.toggleOpt(o[2])
            end)
        end

        -- ===== Danh sách file MIDI (hiện đè lên roll) =====
        local listPanel = Instance.new("Frame")
        listPanel.Position = UDim2.new(0, 12, 0, 70)
        listPanel.Size = UDim2.new(1, -24, 1, -70 - 44)
        listPanel.BorderSizePixel = 0
        listPanel.ZIndex = 20
        listPanel.Visible = false
        listPanel.ClipsDescendants = true
        listPanel.Parent = page
        glassify(listPanel, UDim.new(0, 10), {tint = Color3.fromRGB(6, 8, 14), alpha = 0.08, shine = 0.4, rimT = 0.35})

        local listHint = Instance.new("TextLabel")
        listHint.BackgroundTransparency = 1
        listHint.Position = UDim2.new(0, 10, 0, 4)
        listHint.Size = UDim2.new(1, -90, 0, 20)
        listHint.Font = Enum.Font.GothamMedium
        listHint.TextSize = 11
        listHint.TextColor3 = gray(170)
        listHint.TextXAlignment = Enum.TextXAlignment.Left
        listHint.Text = MIDI_DIR .. "/"
        listHint.TextTruncate = Enum.TextTruncate.AtEnd
        listHint.ZIndex = 21
        listHint.Parent = listPanel

        local refreshPill = makePill(listPanel, UDim2.new(0, 62, 0, 20), UDim2.new(1, -70, 0, 4), true)
        refreshPill.ZIndex = 21
        local refreshBtn = makeTextButton(refreshPill, "refresh", 11)
        refreshBtn.ZIndex = 22
        hoverGlass(refreshBtn, refreshPill)
        bindClick(refreshBtn)

        local searchBox = Instance.new("TextBox")
        searchBox.Position = UDim2.new(0, 6, 0, 28)
        searchBox.Size = UDim2.new(1, -12, 0, 26)
        searchBox.BackgroundColor3 = WHITE
        searchBox.BackgroundTransparency = 0.9
        searchBox.BorderSizePixel = 0
        searchBox.Text = ""
        searchBox.PlaceholderText = "search files"
        searchBox.PlaceholderColor3 = gray(190)
        searchBox.TextColor3 = WHITE
        searchBox.Font = Enum.Font.GothamMedium
        searchBox.TextSize = 12
        searchBox.ClearTextOnFocus = false
        searchBox.ZIndex = 22
        searchBox.Parent = listPanel
        round(searchBox, UDim.new(0, 8))
        claimInput(searchBox)

        local listScroll = Instance.new("ScrollingFrame")
        listScroll.BackgroundTransparency = 1
        listScroll.BorderSizePixel = 0
        listScroll.Position = UDim2.new(0, 0, 0, 60)
        listScroll.Size = UDim2.new(1, 0, 1, -60)
        listScroll.ScrollBarThickness = 3
        listScroll.ScrollBarImageColor3 = gray(190)
        listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        listScroll.ZIndex = 21
        listScroll.Parent = listPanel
        claimInput(listScroll)
        local lp = Instance.new("UIPadding")
        lp.PaddingLeft = UDim.new(0, 6); lp.PaddingRight = UDim.new(0, 8); lp.PaddingBottom = UDim.new(0, 6)
        lp.Parent = listScroll
        local ll = Instance.new("UIListLayout")
        ll.Padding = UDim.new(0, 4)
        ll.SortOrder = Enum.SortOrder.LayoutOrder
        ll.Parent = listScroll
        ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            listScroll.CanvasSize = UDim2.new(0, 0, 0, ll.AbsoluteContentSize.Y + 8)
        end)

        local listEmpty = Instance.new("TextLabel")
        listEmpty.BackgroundTransparency = 1
        listEmpty.Position = UDim2.new(0, 10, 0, 64)
        listEmpty.Size = UDim2.new(1, -20, 1, -64)
        listEmpty.Font = Enum.Font.Gotham
        listEmpty.TextSize = 12
        listEmpty.TextColor3 = gray(160)
        listEmpty.TextWrapped = true
        listEmpty.Text = "no .mid files found\nput them in workspace/" .. MIDI_DIR
        listEmpty.ZIndex = 21
        listEmpty.Parent = listPanel

        local function setFileText()
            fileBtn.Text = (P.name ~= "" and P.name) or "select MIDI file"
        end

        local function closeList() listPanel.Visible = false end

        local cachedFiles = {}
        local hasListfiles = (listfiles ~= nil)

        -- Đọc lại thư mục tetoMIDI/midi
        local function loadFileList()
            pcall(function()
                if makefolder and isfolder then
                    if not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
                    if not isfolder(MIDI_DIR) then makefolder(MIDI_DIR) end
                end
            end)
            local files = {}
            pcall(function()
                if listfiles then
                    for _, p in ipairs(listfiles(MIDI_DIR)) do
                        local ext = tostring(p):lower():match("%.(%w+)$")
                        if ext == "mid" or ext == "midi" then files[#files + 1] = p end
                    end
                end
            end)
            table.sort(files, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            cachedFiles = files
        end

        -- Vẽ các dòng file khớp với ô tìm kiếm (không đọc lại thư mục)
        local function renderFileList()
            for _, c in ipairs(listScroll:GetChildren()) do
                if c:IsA("Frame") then c:Destroy() end
            end
            local q = searchFold(searchBox.Text)
            local shown = 0
            for _, path in ipairs(cachedFiles) do
                local fname = tostring(path):match("[^/\\]+$") or tostring(path)
                if searchMatch(searchFold(fname), q) then
                    shown = shown + 1
                    local row = Instance.new("Frame")
                    row.Size = UDim2.new(1, 0, 0, 26)
                    row.LayoutOrder = shown
                    row.ZIndex = 22
                    row.Parent = listScroll
                    glassify(row, UDim.new(0, 8), {tint = GLASS_WHITE, alpha = (path == C.file) and 0.62 or 0.9, shine = 0.7, rimT = 0.5})
                    local b = makeTextButton(row, fname, 12, Enum.Font.GothamMedium)
                    b.TextTruncate = Enum.TextTruncate.AtEnd
                    b.ZIndex = 23
                    hoverGlass(b, row)
                    bindClick(b)
                    b.MouseButton1Click:Connect(function()
                        closeList()
                        P.loadPath(path)
                    end)
                end
            end
            if #cachedFiles == 0 then
                listEmpty.Visible = true
                if hasListfiles then
                    listEmpty.Text = "no .mid files found\nput them in workspace/" .. MIDI_DIR
                else
                    listEmpty.Text = "this executor has no listfiles()\ncan't list the MIDI folder"
                end
            elseif shown == 0 then
                listEmpty.Visible = true
                listEmpty.Text = "no file matches \"" .. tostring(searchBox.Text) .. "\""
            else
                listEmpty.Visible = false
            end
        end

        local function populateList()
            loadFileList()
            renderFileList()
        end
        searchBox:GetPropertyChangedSignal("Text"):Connect(renderFileList)

        refreshBtn.MouseButton1Click:Connect(function()
            pressAnim(refreshPill)
            populateList()
        end)
        fileBtn.MouseButton1Click:Connect(function()
            pressAnim(filePill)
            if listPanel.Visible then
                closeList()
            else
                populateList()
                listPanel.Visible = true
            end
        end)

        -- ===== Thanh dưới: PLAY / STOP / thanh tua / thời gian =====
        local playPill = makePill(page, UDim2.new(0, 62, 0, 26), UDim2.new(0, 12, 1, -36), true)
        playPill.BackgroundColor3 = Color3.fromRGB(86, 187, 107)
        local playBtn = makeTextButton(playPill, "play", 12)
        hoverGlass(playBtn, playPill)
        bindClick(playBtn)

        local stopPill = makePill(page, UDim2.new(0, 56, 0, 26), UDim2.new(0, 82, 1, -36), true)
        stopPill.BackgroundColor3 = Color3.fromRGB(234, 71, 62)
        local stopBtn = makeTextButton(stopPill, "stop", 12)
        hoverGlass(stopBtn, stopPill)
        bindClick(stopBtn)

        local timeLabel = Instance.new("TextLabel")
        timeLabel.BackgroundTransparency = 1
        timeLabel.AnchorPoint = Vector2.new(1, 0.5)
        timeLabel.Position = UDim2.new(1, -12, 1, -23)
        timeLabel.Size = UDim2.new(0, 84, 0, 18)
        timeLabel.Font = Enum.Font.GothamMedium
        timeLabel.TextSize = 11
        timeLabel.TextColor3 = gray(200)
        timeLabel.TextXAlignment = Enum.TextXAlignment.Right
        timeLabel.Text = "00:00 / 00:00"
        timeLabel.Parent = page
        softText(timeLabel)

        local track = Instance.new("Frame")
        track.BackgroundColor3 = WHITE
        track.BackgroundTransparency = 0.82
        track.BorderSizePixel = 0
        track.Position = UDim2.new(0, 148, 1, -26)
        track.Size = UDim2.new(1, -148 - 104, 0, 6)
        track.Parent = page
        round(track, UDim.new(1, 0))

        local fill = Instance.new("Frame")
        fill.BackgroundColor3 = NOTE_LIT
        fill.BorderSizePixel = 0
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.Parent = track
        round(fill, UDim.new(1, 0))

        local knob = Instance.new("Frame")
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = WHITE
        knob.BorderSizePixel = 0
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.Size = UDim2.new(0, 11, 0, 11)
        knob.Parent = track
        round(knob, UDim.new(1, 0))

        local seekHit = Instance.new("TextButton")
        seekHit.BackgroundTransparency = 1
        seekHit.Text = ""
        seekHit.AutoButtonColor = false
        seekHit.Position = UDim2.new(0, 148, 1, -34)
        seekHit.Size = UDim2.new(1, -148 - 104, 0, 22)
        seekHit.Parent = page
        claimInput(seekHit)

        local lastTimeText = ""
        local function updateBar()
            local frac = (P.length > 0) and math.clamp(P.pos / P.length, 0, 1) or 0
            fill.Size = UDim2.new(frac, 0, 1, 0)
            knob.Position = UDim2.new(frac, 0, 0.5, 0)
            local t = Core.formatTime(P.pos) .. " / " .. Core.formatTime(P.length)
            if t ~= lastTimeText then
                lastTimeText = t
                timeLabel.Text = t
            end
        end

        local function paintPlay()
            local playing = (P.state == "playing")
            playBtn.Text = playing and "pause" or "play"
            playPill.BackgroundColor3 = playing and Color3.fromRGB(224, 161, 58) or Color3.fromRGB(86, 187, 107)
        end

        -- ===== Điều khiển phát =====
        -- HOOK CỦA ENGINE (khối "ENGINE: GỬI PHÍM VÀO GAME", gắn bằng Core.Engine.attach bên dưới):
        --   P.onAdvance(posCu, posMoi) mỗi khung hình khi đang phát -> bấm phím theo các nốt trong khoảng đó
        --   P.onStop() khi dừng/tạm dừng/tua -> thả hết phím;  P.onStart() khi bắt đầu phát.
        P.engine = Core.Engine.attach(P, C, mode)

        function P.stopPlayback(resetPos)
            local was = P.state
            P.state = "stopped"
            if resetPos then P.pos = 0 end
            if was ~= "stopped" and P.onStop then pcall(P.onStop) end
            paintPlay()
            roll.render(P.pos, true)
            updateBar()
        end

        function P.play()
            if not P.song then showToast("Select a MIDI file first"); return end
            if P.state == "playing" then
                P.state = "paused"
                if P.onStop then pcall(P.onStop) end
            else
                if P.pos >= P.length then P.pos = 0 end
                P.state = "playing"
                if P.onStart then pcall(P.onStart) end
            end
            paintPlay()
        end

        function P.seek(sec)
            P.pos = math.clamp(sec, 0, P.length)
            if P.onStop then pcall(P.onStop) end
            roll.render(P.pos, true)
            updateBar()
        end

        function P.tick(dt)
            if P.state ~= "playing" then return end
            local old = P.pos
            P.pos = P.pos + dt * P.speed
            if P.pos >= P.length then
                if P.onAdvance then pcall(P.onAdvance, old, P.length) end   -- các nốt cuối bài (trước khi thả phím)
                if C.loop then
                    P.pos = 0
                    if P.onStop then pcall(P.onStop) end
                    roll.render(0, true)
                    updateBar()
                    return
                end
                P.stopPlayback(true)
                return
            end
            if P.onAdvance then pcall(P.onAdvance, old, P.pos) end
            roll.render(P.pos)
            updateBar()
        end

        function P.leave()
            closeList()
            if P.state ~= "stopped" then P.stopPlayback(true) end
        end

        playBtn.MouseButton1Click:Connect(function()
            pressAnim(playPill)
            P.play()
        end)
        stopBtn.MouseButton1Click:Connect(function()
            pressAnim(stopPill)
            P.stopPlayback(true)
        end)

        -- Thanh tua: bấm / kéo
        local seeking = false
        local function seekFromX(x)
            local w = math.max(track.AbsoluteSize.X, 1)
            local frac = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
            if P.song then P.seek(frac * P.length) end
        end
        seekHit.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                seeking = true
                seekFromX(input.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if seeking and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                seekFromX(input.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                seeking = false
            end
        end)

        -- ===== Nạp file MIDI =====
        function P.loadPath(path, quiet, autoplay)
            roll.setCaption("Loading...")
            task.spawn(function()
                local ok, data = pcall(readfile, path)
                if not ok or type(data) ~= "string" then
                    roll.setCaption(PLAYER_CAPTION[mode])
                    if not quiet then showToast("Can't read file") end
                    return
                end
                local song, err = Core.parseMidi(data, task.wait)
                if not song then
                    roll.setCaption(PLAYER_CAPTION[mode])
                    if not quiet then showToast(err or "Invalid MIDI file") end
                    return
                end
                P.stopPlayback(true)
                P.song = song
                P.length = song.length
                P.notes = Core.songNotes(song, mode, true)
                P.engine.load(song)
                P.name = tostring(path):match("[^/\\]+$") or tostring(path)
                C.file = path
                if not isolated then saveCfg() end
                setFileText()
                rebuildRoll()
                roll.setCaption(string.format("%s  ·  %s  ·  %d notes", PLAYER_CAPTION[mode], Core.formatTime(song.length), #P.notes))
                updateBar()
                if autoplay then P.play() end
            end)
        end

        roll.setCaption(PLAYER_CAPTION[mode])
        rebuildRoll()
        updateBar()

        -- Mở lại file đã dùng lần trước
        if not isolated and C.file and C.file ~= "" then
            task.spawn(function()
                local exists = false
                pcall(function() exists = isfile and isfile(C.file) end)
                if exists then P.loadPath(C.file, true) end
            end)
        end

        return P
    end

    createPlayerPage("piano")
    createPlayerPage("drums")
    createPlayerPage("guitar")

    -- Preview riêng cho midi hub: piano roll + engine phím, có config/trạng thái riêng (không chung với piano player)

    -- Báo lỗi 1 lần nếu executor không gửi được phím (không có VirtualInputManager lẫn keypress)
    Core.Keys.onError = function(msg) showToast(msg) end

    RunService.Heartbeat:Connect(function(dt)
        for _, P in pairs(players) do P.tick(dt) end
        Core.Keys.pump()   -- gửi phím đã xếp hàng vào game (xem khối ENGINE)
    end)

    -- Icon tải xuống vẽ bằng Frame (mũi tên + khay), đặt trong nút hàng của midi store
    local function makeDownloadIcon(parent)
        local function bar(x, y, w, h, rot)
            local f = Instance.new("Frame")
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Position = UDim2.new(0, x, 0, y)
            f.Size = UDim2.new(0, w, 0, h)
            f.Rotation = rot or 0
            f.BackgroundColor3 = WHITE
            f.BorderSizePixel = 0
            f.Parent = parent
            return f
        end
        bar(23, 7, 2, 9)            -- thân mũi tên
        bar(20, 10, 7, 2, 45)       -- cánh trái
        bar(26, 10, 7, 2, -45)      -- cánh phải
        bar(23, 16, 14, 2)          -- khay
    end

    -- Tải file .mid của bài hub về tetoMIDI/midi, không ghi đè file đã có.
    -- Trả về (đường dẫn, "saved" | "exists") hoặc (nil, thông báo lỗi).
    local function hubSaveMidi(song, name)
        if not (writefile and readfile) then return nil, "This executor can't save files" end
        pcall(function()
            if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
            if isfolder and not isfolder(MIDI_DIR) then makefolder(MIDI_DIR) end
        end)
        local safe = tostring(name or "song"):gsub("[\\/:*?\"<>|]", "_"):sub(1, 60)
        local key = tostring(song.key):gsub("[^%w_%-]", "_")
        local path = MIDI_DIR .. "/" .. safe .. "-" .. key .. ".mid"
        local exists = false
        pcall(function() exists = (isfile and isfile(path)) or false end)
        if exists then return path, "exists" end
        local body = nil
        local sid = tostring(song.id)
        for _, u in ipairs({song.hub.url .. "/api/songs/" .. sid .. "/midi", song.hub.url .. "/api/lua/midi/" .. sid}) do
            local b = hubGet(u, 2)
            if type(b) == "string" and b:sub(1, 4) == "MThd" then body = b; break end
        end
        if not body then return nil, "Hub has no MIDI for this song" end
        if pcall(writefile, path, body) then return path, "saved" end
        return nil, "Could not save the file"
    end

    -- Chạy 1 script midi2lua (không còn dùng cho nút Play của hub, giữ lại để tham khảo)
    local function playScript(name, script)
        if _G.songisplaying then
            showToast("A song is already playing")
            return
        end
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


    -- ===== MIDI HUB PAGE =====
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
    hubSearchBox.PlaceholderText = "search store"
    hubSearchBox.TextColor3 = WHITE
    hubSearchBox.PlaceholderColor3 = gray(205)
    hubSearchBox.Font = Enum.Font.GothamMedium
    hubSearchBox.TextSize = 13
    hubSearchBox.ClearTextOnFocus = false
    hubSearchBox.Parent = hubSearchPill
    claimInput(hubSearchBox)

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
    claimInput(hubList)

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
        filter = searchFold(filter)
        local shown = 0

        for i, song in ipairs(hubItems) do
            local songName = tostring(song.name)
            if searchMatch(searchFold(songName), filter) then
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
                        local assetId = hubThumb(song)
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

                local dlP, dlB = makeRowButton(row, 48, "", true)
                makeDownloadIcon(dlP)

                dlB.MouseButton1Click:Connect(function()
                    pressAnim(dlP)
                    task.spawn(function()
                        -- Lưu .mid vào tetoMIDI/midi và báo rõ đường dẫn đã lưu
                        local path, status = hubSaveMidi(song, songName)
                        if not path then
                            showToast(status or "Download failed", 3)
                            return
                        end
                        local shown = MIDI_DIR .. "/" .. (path:match("[^/\\]+$") or path)
                        if status == "exists" then
                            showToast("Already in " .. shown, 3.5)
                        else
                            showToast("Added to " .. shown, 3.5)
                        end
                    end)
                end)
            end
        end

        if hubState == "loading" then
            hubEmpty.Visible = true
            hubEmpty.Text = "loading..."
        elseif hubState == "fail" then
            hubEmpty.Visible = true
            hubEmpty.Text = "store offline\ntap sync to retry"
        elseif shown == 0 then
            hubEmpty.Visible = true
            hubEmpty.Text = (#hubItems > 0) and "no match" or "store is empty"
        else
            hubEmpty.Visible = false
        end
    end

    local hubLastSync = 0
    local hubSyncToken = 0

    local function syncHub(silent)
        if hubState == "loading" then return end
        hubState = "loading"
        hubSyncToken = hubSyncToken + 1
        local mine = hubSyncToken
        refreshHubList(hubSearchBox.Text)

        -- Chốt chặn: hub treo quá lâu thì báo lỗi, không kẹt "loading" mãi
        task.delay(HUB_TIMEOUT_SEC + 5, function()
            if hubSyncToken == mine and hubState == "loading" then
                hubState = "fail"
                refreshHubList(hubSearchBox.Text)
            end
        end)

        task.spawn(function()
            local data, okCount = hubFetchList()
            if hubSyncToken ~= mine then return end
            if data then
                hubItems = data
                hubState = "ok"
                hubLastSync = os.clock()
                if not silent then
                    showToast(string.format("Synced %d songs", #data))
                end
            else
                hubState = "fail"
                if not silent then showToast("Sync failed") end
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

    -- ===== ẢNH NỀN CHO ROLL =====
    -- Tải ảnh png/jpg từ link, lưu vào tetoMIDI/bg (để mở lại game không cần tải lại).
    local BG_DIR = "tetoMIDI/bg"
    local function isJpg(data)
        return type(data) == "string" and #data > 100 and data:byte(1) == 0xFF and data:byte(2) == 0xD8
    end

    local function loadBackground(mode, url)
        local P = players[mode]
        if not (P and P.roll) then return false, "page not ready" end
        url = (tostring(url or ""):gsub("%s+", ""))
        if url == "" then
            Cfg.bg[mode] = ""
            saveCfg()
            P.roll.setBackground(nil)
            return true
        end
        if not url:match("^https?://") then return false, "link must start with http(s)" end
        if not (writefile and isfile and (getcustomasset or getsynasset)) then
            return false, "this executor can't load images"
        end
        local data = httpGetRaw(url)
        local ext = nil
        if isPng(data) then ext = "png" elseif isJpg(data) then ext = "jpg" end
        if not ext then return false, "not a png/jpg link" end
        if #data > 5 * 1024 * 1024 then return false, "image is over 5 MB" end
        pcall(function()
            if isfolder and not isfolder("tetoMIDI") then makefolder("tetoMIDI") end
            if isfolder and not isfolder(BG_DIR) then makefolder(BG_DIR) end
        end)
        local path = BG_DIR .. "/" .. mode .. "." .. ext
        if not pcall(writefile, path, data) then return false, "can't save the image" end
        local id = getAsset(path)
        if id == "" then return false, "can't load the image" end
        Cfg.bg[mode] = url
        saveCfg()
        P.roll.setBackground(id)
        return true
    end

    -- Khi mở lại game: dùng ảnh đã lưu trong tetoMIDI/bg
    local function restoreBackgrounds()
        for _, mode in ipairs({"piano", "drums", "guitar"}) do
            local P = players[mode]
            if P and P.roll and Cfg.bg[mode] ~= nil and Cfg.bg[mode] ~= "" then
                for _, ext in ipairs({"png", "jpg"}) do
                    local path = BG_DIR .. "/" .. mode .. "." .. ext
                    local exists = false
                    pcall(function() exists = (isfile and isfile(path)) or false end)
                    if exists then
                        local id = getAsset(path)
                        if id ~= "" then P.roll.setBackground(id); break end
                    end
                end
            end
        end
    end
    restoreBackgrounds()

    -- ===== CÀI ĐẶT (icon bánh răng ở sidebar) =====
    local settingsPage = Instance.new("ScrollingFrame")
    settingsPage.Name = "SettingsPage"
    settingsPage.Size = UDim2.new(1, 0, 1, 0)
    settingsPage.BackgroundTransparency = 1
    settingsPage.BorderSizePixel = 0
    settingsPage.ScrollBarThickness = 3
    settingsPage.ScrollBarImageColor3 = gray(190)
    settingsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    settingsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
    settingsPage.Visible = false
    settingsPage.Parent = content
    claimInput(settingsPage)
    local settingsLayout = Instance.new("UIListLayout")
    settingsLayout.Padding = UDim.new(0, 8)
    settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    settingsLayout.Parent = settingsPage
    local settingsPad = Instance.new("UIPadding")
    settingsPad.PaddingLeft = UDim.new(0, 14)
    settingsPad.PaddingRight = UDim.new(0, 14)
    settingsPad.PaddingTop = UDim.new(0, 12)
    settingsPad.PaddingBottom = UDim.new(0, 12)
    settingsPad.Parent = settingsPage

    local settingsOrder = 0
    local function nextOrder()
        settingsOrder = settingsOrder + 1
        return settingsOrder
    end

    local function settingsTitle(text)
        local t = Instance.new("TextLabel")
        t.LayoutOrder = nextOrder()
        t.Size = UDim2.new(1, 0, 0, 24)
        t.BackgroundTransparency = 1
        t.Text = text
        t.TextColor3 = WHITE
        t.Font = Enum.Font.GothamBold
        t.TextSize = 14
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Parent = settingsPage
        softText(t)
    end

    -- Hàng: nhãn | [-] giá trị [+]
    local function stepperRow(text, valueText, onStep)
        local row = Instance.new("Frame")
        row.LayoutOrder = nextOrder()
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        row.Parent = settingsPage

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -150, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = WHITE
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        softText(lbl)

        local val = Instance.new("TextLabel")
        val.Size = UDim2.new(0, 44, 1, 0)
        val.Position = UDim2.new(1, -92, 0, 0)
        val.BackgroundTransparency = 1
        val.Text = valueText()
        val.TextColor3 = WHITE
        val.Font = Enum.Font.GothamBold
        val.TextSize = 13
        val.Parent = row
        softText(val)

        local function stepBtn(x, sign)
            local pill = makePill(row, UDim2.new(0, 30, 0, 26), UDim2.new(1, x, 0.5, -13))
            local b = makeTextButton(pill, sign < 0 and "-" or "+", 15, Enum.Font.GothamBold)
            hoverGlass(b, pill)
            bindClick(b)
            b.MouseButton1Click:Connect(function()
                pressAnim(pill)
                onStep(sign)
                val.Text = valueText()
            end)
        end
        stepBtn(-124, -1)
        stepBtn(-30, 1)
        return row
    end

    -- Hàng: nhãn | [nút bật/tắt]
    local function toggleRow(text, isOn, onToggle)
        local row = Instance.new("Frame")
        row.LayoutOrder = nextOrder()
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        row.Parent = settingsPage

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -90, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = WHITE
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        softText(lbl)

        local pill = makePill(row, UDim2.new(0, 64, 0, 26), UDim2.new(1, -64, 0.5, -13), isOn())
        local b = makeTextButton(pill, isOn() and "on" or "off", 13, Enum.Font.GothamBold)
        hoverGlass(b, pill)
        bindClick(b)
        b.MouseButton1Click:Connect(function()
            pressAnim(pill)
            onToggle()
            b.Text = isOn() and "on" or "off"
        end)
    end

    -- Ô link ảnh nền cho 1 trang (piano / drums / guitar)
    local function backgroundRow(mode, label)
        local row = Instance.new("Frame")
        row.LayoutOrder = nextOrder()
        row.Size = UDim2.new(1, 0, 0, 62)
        row.BackgroundTransparency = 1
        row.Parent = settingsPage

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 18)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = WHITE
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        softText(lbl)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, 0, 0, 26)
        box.Position = UDim2.new(0, 0, 0, 22)
        box.BackgroundColor3 = WHITE
        box.BackgroundTransparency = 0.9
        box.BorderSizePixel = 0
        box.Text = Cfg.bg[mode] or ""
        box.PlaceholderText = "https://...png or .jpg"
        box.PlaceholderColor3 = gray(205)
        box.TextColor3 = WHITE
        box.Font = Enum.Font.GothamMedium
        box.TextSize = 12
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClearTextOnFocus = false
        box.TextTruncate = Enum.TextTruncate.AtEnd
        box.Parent = row
        claimInput(box)

        local applyPill = makePill(row, UDim2.new(0, 70, 0, 22), UDim2.new(0, 0, 0, 40))
        local applyB = makeTextButton(applyPill, "apply", 12, Enum.Font.GothamMedium)
        hoverGlass(applyB, applyPill)
        bindClick(applyB)
        applyB.MouseButton1Click:Connect(function()
            pressAnim(applyPill)
            task.spawn(function()
                local ok, err = loadBackground(mode, box.Text)
                showToast(ok and "Background applied" or ("Background: " .. tostring(err)), 2.5)
            end)
        end)

        local clearPill = makePill(row, UDim2.new(0, 70, 0, 22), UDim2.new(0, 78, 0, 40))
        local clearB = makeTextButton(clearPill, "clear", 12, Enum.Font.GothamMedium)
        hoverGlass(clearB, clearPill)
        bindClick(clearB)
        clearB.MouseButton1Click:Connect(function()
            pressAnim(clearPill)
            task.spawn(function()
                local ok, err = loadBackground(mode, "")
                box.Text = ""
                showToast(ok and "Background removed" or ("Background: " .. tostring(err)), 2.5)
            end)
        end)
    end

    settingsTitle("window")
    stepperRow("transparency", function() return string.format("%d%%", math.floor(Cfg.ui.alpha * 100 + 0.5)) end,
        function(sign)
            Cfg.ui.alpha = math.clamp(math.floor((Cfg.ui.alpha + sign * 0.1) * 10 + 0.5) / 10, 0, 0.8)
            if MainVisible then main.GroupTransparency = Cfg.ui.alpha end
            saveCfg()
        end)

    settingsTitle("hands (piano player)")
    local HAND_OPTS = {{"All", "all"}, {"Left", "left"}, {"Right", "right"}}
    local handPills = {}
    local function paintHands()
        for _, h in ipairs(handPills) do
            setGlassBase(h.pill, (Cfg.hand.mode == h.value) and 0.8 or 1)
        end
    end

    local handLine = Instance.new("Frame")
    handLine.LayoutOrder = nextOrder()
    handLine.Size = UDim2.new(1, 0, 0, 30)
    handLine.BackgroundTransparency = 1
    handLine.Parent = settingsPage

    local handLbl = Instance.new("TextLabel")
    handLbl.Size = UDim2.new(1, -210, 1, 0)
    handLbl.BackgroundTransparency = 1
    handLbl.Text = "notes to play"
    handLbl.TextColor3 = WHITE
    handLbl.Font = Enum.Font.GothamMedium
    handLbl.TextSize = 13
    handLbl.TextXAlignment = Enum.TextXAlignment.Left
    handLbl.Parent = handLine
    softText(handLbl)

    for i, opt in ipairs(HAND_OPTS) do
        local pill = makePill(handLine, UDim2.new(0, 62, 0, 26), UDim2.new(1, -198 + (i - 1) * 68, 0.5, -13))
        local b = makeTextButton(pill, opt[1], 12, Enum.Font.GothamMedium)
        hoverGlass(b, pill)
        bindClick(b)
        handPills[i] = {pill = pill, value = opt[2]}
        b.MouseButton1Click:Connect(function()
            pressAnim(pill)
            Cfg.hand.mode = opt[2]
            saveCfg()
            paintHands()
        end)
    end
    paintHands()

    local handHint = Instance.new("TextLabel")
    handHint.LayoutOrder = nextOrder()
    handHint.Size = UDim2.new(1, 0, 0, 16)
    handHint.BackgroundTransparency = 1
    handHint.Text = "Left: notes below C4 · Right: C4 and above · the falling notes still show all"
    handHint.TextColor3 = gray(190)
    handHint.Font = Enum.Font.GothamMedium
    handHint.TextSize = 11
    handHint.TextXAlignment = Enum.TextXAlignment.Left
    handHint.TextWrapped = true
    handHint.Parent = settingsPage

    settingsTitle("falling notes")
    local notePreview = nil
    local function hexOf(c)
        return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    local function setNoteColor(hex)
        Cfg.note.color = hex
        saveCfg()
        applyNoteColor()
        if notePreview then notePreview.BackgroundColor3 = NOTE_BODY end
    end

    -- Ô xem trước màu đang dùng
    local previewRow = Instance.new("Frame")
    previewRow.LayoutOrder = nextOrder()
    previewRow.Size = UDim2.new(1, 0, 0, 30)
    previewRow.BackgroundTransparency = 1
    previewRow.Parent = settingsPage
    local previewLbl = Instance.new("TextLabel")
    previewLbl.Size = UDim2.new(1, -40, 1, 0)
    previewLbl.BackgroundTransparency = 1
    previewLbl.Text = "selected color"
    previewLbl.TextColor3 = WHITE
    previewLbl.Font = Enum.Font.GothamMedium
    previewLbl.TextSize = 13
    previewLbl.TextXAlignment = Enum.TextXAlignment.Left
    previewLbl.Parent = previewRow
    softText(previewLbl)
    notePreview = Instance.new("Frame")
    notePreview.Size = UDim2.new(0, 28, 0, 24)
    notePreview.Position = UDim2.new(1, -28, 0.5, -12)
    notePreview.BackgroundColor3 = NOTE_BODY
    notePreview.BorderSizePixel = 0
    notePreview.Parent = previewRow
    round(notePreview, UDim.new(0, 6))

    -- Bảng màu: 3 hàng x 12 màu (sáng, tối, xám). Bấm vào ô là chọn.
    local function paletteRow(colorAt)
        local pr = Instance.new("Frame")
        pr.LayoutOrder = nextOrder()
        pr.Size = UDim2.new(1, 0, 0, 26)
        pr.BackgroundTransparency = 1
        pr.Parent = settingsPage
        for col = 1, 12 do
            local c = colorAt(col)
            local sw = Instance.new("TextButton")
            sw.Size = UDim2.new(0, 26, 0, 26)
            sw.Position = UDim2.new(0, (col - 1) * 30, 0, 0)
            sw.BackgroundColor3 = c
            sw.BorderSizePixel = 0
            sw.Text = ""
            sw.AutoButtonColor = false
            sw.Parent = pr
            round(sw, UDim.new(0, 6))
            bindClick(sw)
            local hex = hexOf(c)
            sw.MouseButton1Click:Connect(function()
                setNoteColor(hex)
            end)
        end
    end
    paletteRow(function(col) return Color3.fromHSV((col - 1) / 12, 0.85, 1) end)
    paletteRow(function(col) return Color3.fromHSV((col - 1) / 12, 0.9, 0.55) end)
    paletteRow(function(col) return Color3.fromHSV(0, 0, 1 - (col - 1) / 11 * 0.9) end)

    settingsTitle("fake keyboard sound")
    toggleRow("play key sound when auto plays",
        function() return Cfg.fake.enabled end,
        function()
            Cfg.fake.enabled = not Cfg.fake.enabled
            saveCfg()
            if Cfg.fake.enabled then
                task.spawn(function()
                    loadKeySounds()
                    if not keysId then showToast("Key sound file not loaded (sounds/keys.mp3)", 3) end
                end)
            end
        end)
    stepperRow("volume", function() return tostring(Cfg.fake.volume) end,
        function(sign)
            Cfg.fake.volume = math.clamp(Cfg.fake.volume + sign * 10, 0, 100)
            saveCfg()
        end)
    toggleRow("loud (speaker to mic)",
        function() return Cfg.fake.loud end,
        function()
            Cfg.fake.loud = not Cfg.fake.loud
            saveCfg()
        end)
    local fakeHint = Instance.new("TextLabel")
    fakeHint.LayoutOrder = nextOrder()
    fakeHint.Size = UDim2.new(1, 0, 0, 34)
    fakeHint.BackgroundTransparency = 1
    fakeHint.Text = "Others only hear it if your speakers play it into your mic (use a virtual audio cable or speakers)."
    fakeHint.TextColor3 = gray(190)
    fakeHint.Font = Enum.Font.GothamMedium
    fakeHint.TextSize = 11
    fakeHint.TextWrapped = true
    fakeHint.TextXAlignment = Enum.TextXAlignment.Left
    fakeHint.TextYAlignment = Enum.TextYAlignment.Top
    fakeHint.Parent = settingsPage
    softText(fakeHint)

    settingsTitle("background image (png / jpg link)")
    backgroundRow("piano", "piano roll")
    backgroundRow("drums", "drum roll")
    backgroundRow("guitar", "guitar roll")

    -- Nút icon bánh răng trên sidebar
    makeNavBtn("settings", "gear.png", 190, "settings")

    -- ===== CHUYỂN TRANG =====
    updatePages = function()
        for mode, P in pairs(players) do
            P.page.Visible = (CurrentPage == mode)
            -- Sang cài đặt / midi store thì vẫn giữ nhạc chạy; đổi qua tab nhạc khác thì dừng (giống app)
            if CurrentPage ~= mode and CurrentPage ~= "settings" and CurrentPage ~= "hub" then P.leave() end
        end
        hubPage.Visible = (CurrentPage == "hub")
        settingsPage.Visible = (CurrentPage == "settings")
        if CurrentPage == "hub" and hubState ~= "loading" then
            -- lần đầu / đã lỗi / danh sách cũ: tự đồng bộ lại khi mở tab hub
            if hubState ~= "ok" or (os.clock() - hubLastSync) > HUB_STALE_SEC then
                syncHub(true)
            end
        end
        for page, btn in pairs(navButtons) do
            local active = (page == CurrentPage)
            glassLayers(btn, active)
            setGlassBase(btn, active and 0.8 or 1)
        end
    end

    updatePages()

    -- ===== MINI PLAYER =====
    -- Nút "mini" ở thanh tiêu đề thu cửa sổ thành một bảng nhỏ 300x100: tên bài, các tuỳ chọn
    -- (giống trên trang: 88 key / Sustain / Velocity / Note length / Loop), play và tiến độ.
    -- Nút "full" trong mini bung lại cửa sổ đầy đủ.
    local MINI_W, MINI_H = 300, 166
    local lastMode = "piano"
    local miniTweenMain, miniTweenMini

    local mini = Instance.new("CanvasGroup")
    mini.Name = "Mini"
    mini.AnchorPoint = Vector2.new(0.5, 0.5)
    mini.Position = UDim2.new(0.5, 0, 0.5, 0)
    mini.Size = UDim2.new(0, MINI_W, 0, MINI_H)
    mini.BackgroundTransparency = 1
    mini.BorderSizePixel = 0
    mini.Active = true
    mini.ClipsDescendants = true
    mini.Visible = false
    mini.GroupTransparency = 1
    mini.Parent = gui

    local miniCorner = Instance.new("UICorner")
    miniCorner.CornerRadius = UDim.new(0, 18)
    miniCorner.Parent = mini

    local miniBase = Instance.new("Frame")
    miniBase.Size = UDim2.new(1, 0, 1, 0)
    miniBase.Parent = mini
    glassify(miniBase, nil, {alpha = 0.34, shine = 1.3, rim = false})

    -- Kéo mini bằng chỗ trống (nút và tuỳ chọn nằm trên lớp này nên vẫn bấm được)
    local miniDrag = Instance.new("Frame")
    miniDrag.Size = UDim2.new(1, 0, 1, 0)
    miniDrag.BackgroundTransparency = 1
    miniDrag.BorderSizePixel = 0
    miniDrag.Active = true
    miniDrag.Parent = mini
    bindWindowDrag(miniDrag)

    makeRim(mini, 1.5, 0.3)

    local miniScale = Instance.new("UIScale")
    miniScale.Scale = 0.6
    miniScale.Parent = mini

    local miniName = Instance.new("TextLabel")
    miniName.Position = UDim2.new(0, 42, 0, 6)
    miniName.Size = UDim2.new(0, MINI_W - 42 - 70, 0, 16)
    miniName.BackgroundTransparency = 1
    miniName.Text = ""
    miniName.TextColor3 = WHITE
    miniName.Font = Enum.Font.GothamMedium
    miniName.TextSize = 12
    miniName.TextXAlignment = Enum.TextXAlignment.Left
    miniName.TextTruncate = Enum.TextTruncate.AtEnd
    miniName.Parent = mini
    softText(miniName)

    -- Icon logo + dòng phụ (tên trang đang phát), giống khung trên của bản tham khảo
    local miniIcon = Instance.new("ImageLabel")
    miniIcon.Position = UDim2.new(0, 12, 0, 7)
    miniIcon.Size = UDim2.new(0, 24, 0, 24)
    miniIcon.BackgroundTransparency = 1
    miniIcon.Image = getImage("logo.png")
    miniIcon.ScaleType = Enum.ScaleType.Fit
    miniIcon.Parent = mini
    round(miniIcon, UDim.new(0, 5))

    local miniSub = Instance.new("TextLabel")
    miniSub.Position = UDim2.new(0, 42, 0, 22)
    miniSub.Size = UDim2.new(0, MINI_W - 42 - 70, 0, 12)
    miniSub.BackgroundTransparency = 1
    miniSub.Text = "piano player"
    miniSub.TextColor3 = gray(190)
    miniSub.Font = Enum.Font.GothamMedium
    miniSub.TextSize = 10
    miniSub.TextXAlignment = Enum.TextXAlignment.Left
    miniSub.TextTruncate = Enum.TextTruncate.AtEnd
    miniSub.Parent = mini

    local fullPill = makePill(mini, UDim2.new(0, 50, 0, 20), UDim2.new(1, -62, 0, 6))
    local fullBtn = makeTextButton(fullPill, "full", 11, Enum.Font.GothamMedium)
    hoverGlass(fullBtn, fullPill)
    bindClick(fullBtn)

    -- Hàng tuỳ chọn: lấy theo trang đang phát (piano 5 nút, drums/guitar 2 nút)
    local miniChips, miniChipMode = {}, nil
    local function buildMiniChips(mode)
        for _, c in ipairs(miniChips) do c.pill:Destroy() end
        miniChips = {}
        miniChipMode = mode
        -- Mini chỉ giữ tuỳ chọn chơi; "3D roll" chỉ có ở UI chính
        local opts = {}
        for _, o in ipairs(PLAYER_OPTIONS[mode] or {}) do
            if o[2] ~= "roll3d" then opts[#opts + 1] = o end
        end
        local cellW = (MINI_W - 24 - 8) / 3
        for i, o in ipairs(opts) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local pill = makePill(mini, UDim2.new(0, cellW, 0, 20), UDim2.new(0, 12 + col * (cellW + 4), 0, 116 + row * 24))
            local b = makeTextButton(pill, o[1], 10)
            textFit(b, 10)
            hoverGlass(b, pill)
            bindClick(b)
            miniChips[#miniChips + 1] = {pill = pill, key = o[2], lastOn = nil}
            b.MouseButton1Click:Connect(function()
                pressAnim(pill)
                local P = players[mode]
                if P and P.toggleOpt then P.toggleOpt(o[2]) end
            end)
        end
    end

    local function paintMiniChips()
        local P = players[miniChipMode]
        for _, chip in ipairs(miniChips) do
            local on = (P and P.C and P.C[chip.key]) and true or false
            if chip.lastOn ~= on then
                chip.lastOn = on
                chip.pill.BackgroundColor3 = on and NOTE_LIT or GLASS_WHITE
                setGlassBase(chip.pill, on and 0.3 or 0.86)
            end
        end
    end

    -- Hàng All / Left / Right (chỉ piano): đồng bộ với mục cài đặt
    local handBox = Instance.new("Frame")
    handBox.Position = UDim2.new(0, 12, 0, 92)
    handBox.Size = UDim2.new(1, -24, 0, 20)
    handBox.BackgroundTransparency = 1
    handBox.Parent = mini
    local miniHandPills = {}
    local lastMiniHand = nil
    local MINI_HANDS = {{"All", "all"}, {"Left", "left"}, {"Right", "right"}}
    for i, opt in ipairs(MINI_HANDS) do
        local cw = (MINI_W - 24 - 8) / 3
        local pill = makePill(handBox, UDim2.new(0, cw, 0, 20), UDim2.new(0, (i - 1) * (cw + 4), 0, 0))
        local b = makeTextButton(pill, opt[1], 10, Enum.Font.GothamMedium)
        hoverGlass(b, pill)
        bindClick(b)
        miniHandPills[i] = {pill = pill, value = opt[2]}
        b.MouseButton1Click:Connect(function()
            pressAnim(pill)
            Cfg.hand.mode = opt[2]
            saveCfg()
            paintHands()   -- cập nhật luôn mục trong cài đặt
        end)
    end

    local function paintMiniHands()
        if lastMiniHand == Cfg.hand.mode then return end
        lastMiniHand = Cfg.hand.mode
        for _, h in ipairs(miniHandPills) do
            setGlassBase(h.pill, (Cfg.hand.mode == h.value) and 0.8 or 1)
        end
    end

    local track = Instance.new("Frame")
    track.Position = UDim2.new(0, 50, 0, 47)
    track.Size = UDim2.new(1, -100, 0, 4)
    track.BackgroundColor3 = WHITE
    track.BackgroundTransparency = 0.8
    track.BorderSizePixel = 0
    track.Parent = mini
    round(track, UDim.new(1, 0))

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = WHITE
    fill.BorderSizePixel = 0
    fill.Parent = track
    round(fill, UDim.new(1, 0))

    local timeLbl = Instance.new("TextLabel")
    timeLbl.Position = UDim2.new(0, 12, 0, 40)
    timeLbl.Size = UDim2.new(0, 36, 0, 14)
    timeLbl.BackgroundTransparency = 1
    timeLbl.Text = "0:00 / 0:00"
    timeLbl.TextColor3 = gray(200)
    timeLbl.Font = Enum.Font.GothamMedium
    timeLbl.TextSize = 10
    timeLbl.TextXAlignment = Enum.TextXAlignment.Left
    timeLbl.Parent = mini
    softText(timeLbl)

    local totalLbl = Instance.new("TextLabel")
    totalLbl.Position = UDim2.new(1, -48, 0, 40)
    totalLbl.Size = UDim2.new(0, 36, 0, 14)
    totalLbl.BackgroundTransparency = 1
    totalLbl.Text = "0:00"
    totalLbl.TextColor3 = gray(200)
    totalLbl.Font = Enum.Font.GothamMedium
    totalLbl.TextSize = 10
    totalLbl.TextXAlignment = Enum.TextXAlignment.Right
    totalLbl.Parent = mini
    softText(totalLbl)

    -- Hàng điều khiển: STOP (đưa bài về đầu) | PLAY/PAUSE
    local stopPill = makePill(mini, UDim2.new(0, 44, 0, 22), UDim2.new(0.5, -66, 0, 62))
    local stopBtn = makeTextButton(stopPill, "stop", 11, Enum.Font.GothamMedium)
    hoverGlass(stopBtn, stopPill)
    bindClick(stopBtn)
    stopBtn.MouseButton1Click:Connect(function()
        pressAnim(stopPill)
        local P = miniPlayer()
        if P and P.stopPlayback then P.stopPlayback(true) end
        refreshMini()
    end)

    local playPill = makePill(mini, UDim2.new(0, 30, 0, 30), UDim2.new(0.5, -15, 0, 58), true)
    local playBtn = makeTextButton(playPill, ">", 12, Enum.Font.GothamBold)
    bindClick(playBtn)
    hoverGlass(playBtn, playPill)


    -- Người chơi đang dùng: trang nhạc hiện tại, hoặc trang nhạc gần nhất nếu đang ở cài đặt/store
    local MODE_LABEL = {piano = "piano player", drums = "drum player", guitar = "guitar player"}
    local function miniPlayer()
        if players[CurrentPage] then lastMode = CurrentPage end
        return players[lastMode]
    end

    local function refreshMini()
        local P = miniPlayer()
        if miniChipMode ~= lastMode then buildMiniChips(lastMode) end
        if P and P.song and P.name and P.name ~= "" then
            miniName.Text = P.name
        else
            miniName.Text = "No song loaded"
        end
        playBtn.Text = (P and P.state == "playing") and "||" or ">"
        miniSub.Text = MODE_LABEL[lastMode] or ""
        local frac = 0
        if P and P.length and P.length > 0 then frac = math.clamp(P.pos / P.length, 0, 1) end
        fill.Size = UDim2.new(frac, 0, 1, 0)
        if P and P.length and P.length > 0 then
            timeLbl.Text = Core.formatTime(P.pos)
            totalLbl.Text = Core.formatTime(P.length)
        else
            timeLbl.Text = "0:00"
            totalLbl.Text = "0:00"
        end
        handBox.Visible = (lastMode == "piano")
        paintMiniChips()
        paintMiniHands()
    end

    local function toMini()
        if miniMode or not MainVisible then return end
        miniMode = true
        MainVisible = false
        winRef = mini
        if openTween then openTween:Cancel() end
        if closeTween then closeTween:Cancel() end
        setBlur(false)

        local vp = viewportSize()
        local c = main.AbsolutePosition + main.AbsoluteSize / 2
        local cx = math.clamp(c.X, MINI_W / 2 + 8, vp.X - MINI_W / 2 - 8)
        local cy = math.clamp(c.Y, MINI_H / 2 + 8, vp.Y - MINI_H / 2 - 8)
        mini.Position = UDim2.new(0, cx, 0, cy)
        mini.GroupTransparency = 1
        miniScale.Scale = 0.6
        mini.Visible = true
        refreshMini()

        -- khung lớn: thu về + mờ dần
        TweenService:Create(mainStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
        TweenService:Create(mainScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.6}):Play()
        miniTweenMain = TweenService:Create(main, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
        miniTweenMain:Play()
        miniTweenMain.Completed:Connect(function(state)
            if miniMode and state == Enum.PlaybackState.Completed then main.Visible = false end
        end)

        -- mini: phóng to từ tâm + hiện dần
        TweenService:Create(miniScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        miniTweenMini = TweenService:Create(mini, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = Cfg.ui.alpha})
        miniTweenMini:Play()
    end

    fromMini = function()
        if not miniMode then return end
        miniMode = false
        winRef = main
        if miniTweenMain then miniTweenMain:Cancel() end
        if miniTweenMini then miniTweenMini:Cancel() end

        -- mini: thu nhỏ + mờ dần rồi ẩn
        TweenService:Create(miniScale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.6}):Play()
        local outMini = TweenService:Create(mini, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {GroupTransparency = 1})
        outMini:Play()
        outMini.Completed:Connect(function(state)
            if not miniMode and state == Enum.PlaybackState.Completed then mini.Visible = false end
        end)

        -- khung lớn: nở ra đúng chỗ mini đang đứng
        main.Position = mini.Position
        main.Visible = true
        main.GroupTransparency = 1
        mainScale.Scale = 0.6
        MainVisible = true
        setBlur(true)
        TweenService:Create(mainStroke, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0}):Play()
        TweenService:Create(mainScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        openTween = TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = Cfg.ui.alpha})
        openTween:Play()
    end

    fullBtn.MouseButton1Click:Connect(function() pressAnim(fullPill); fromMini() end)
    playBtn.MouseButton1Click:Connect(function()
        pressAnim(playPill)
        local P = miniPlayer()
        if P then P.play() end
        refreshMini()
    end)

    -- ===== CONSOLE: xem các phím (hotkey) đang được gửi =====
    local CONSOLE_MAX = 300
    local consoleOpen = false
    local consoleBuf = {}
    local consoleRows = {}
    local consoleCount = 0

    local consolePanel = Instance.new("Frame")
    consolePanel.Name = "Console"
    consolePanel.Position = UDim2.new(0, SIDEBAR_W + 8, 0, HEADER_H + 6)
    consolePanel.Size = UDim2.new(1, -SIDEBAR_W - 16, 1, -HEADER_H - 14)
    consolePanel.BorderSizePixel = 0
    consolePanel.ZIndex = 30
    consolePanel.Visible = false
    consolePanel.ClipsDescendants = true
    consolePanel.Parent = main
    glassify(consolePanel, UDim.new(0, 10), {tint = Color3.fromRGB(6, 8, 14), alpha = 0.1, shine = 0.4, rimT = 0.35})

    local consoleTitle = Instance.new("TextLabel")
    consoleTitle.Position = UDim2.new(0, 10, 0, 6)
    consoleTitle.Size = UDim2.new(1, -160, 0, 20)
    consoleTitle.BackgroundTransparency = 1
    consoleTitle.Text = "hotkey console"
    consoleTitle.TextColor3 = WHITE
    consoleTitle.Font = Enum.Font.GothamBold
    consoleTitle.TextSize = 12
    consoleTitle.TextXAlignment = Enum.TextXAlignment.Left
    consoleTitle.Parent = consolePanel
    softText(consoleTitle)

    local clearPill = makePill(consolePanel, UDim2.new(0, 56, 0, 20), UDim2.new(1, -128, 0, 6))
    local clearBtn = makeTextButton(clearPill, "clear", 10, Enum.Font.GothamMedium)
    hoverGlass(clearBtn, clearPill)
    bindClick(clearBtn)

    local closePill = makePill(consolePanel, UDim2.new(0, 56, 0, 20), UDim2.new(1, -66, 0, 6))
    local closeBtn = makeTextButton(closePill, "close", 10, Enum.Font.GothamMedium)
    hoverGlass(closeBtn, closePill)
    bindClick(closeBtn)

    local consoleScroll = Instance.new("ScrollingFrame")
    consoleScroll.Position = UDim2.new(0, 8, 0, 32)
    consoleScroll.Size = UDim2.new(1, -16, 1, -40)
    consoleScroll.BackgroundTransparency = 1
    consoleScroll.BorderSizePixel = 0
    consoleScroll.ScrollBarThickness = 3
    consoleScroll.ScrollBarImageColor3 = gray(190)
    consoleScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    consoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    consoleScroll.Parent = consolePanel
    claimInput(consoleScroll)

    local consoleLayout = Instance.new("UIListLayout")
    consoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    consoleLayout.Parent = consoleScroll

    local function clearRows()
        for _, r in ipairs(consoleRows) do r:Destroy() end
        consoleRows = {}
    end

    local function scrollConsoleBottom()
        task.defer(function()
            if consoleScroll.Parent then
                consoleScroll.CanvasPosition = Vector2.new(0, math.max(0, consoleScroll.AbsoluteCanvasSize.Y - consoleScroll.AbsoluteSize.Y))
            end
        end)
    end

    local function addRow(entry)
        consoleCount = consoleCount + 1
        local lbl = Instance.new("TextLabel")
        lbl.LayoutOrder = consoleCount
        lbl.Size = UDim2.new(1, -4, 0, 14)
        lbl.BackgroundTransparency = 1
        lbl.Text = entry.text
        lbl.TextColor3 = entry.color
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = consoleScroll
        consoleRows[#consoleRows + 1] = lbl
        if #consoleRows > CONSOLE_MAX then
            consoleRows[1]:Destroy()
            table.remove(consoleRows, 1)
        end
    end

    local function consoleAppend(entry)
        consoleBuf[#consoleBuf + 1] = entry
        if #consoleBuf > CONSOLE_MAX then table.remove(consoleBuf, 1) end
        if consoleOpen then
            addRow(entry)
            scrollConsoleBottom()
        end
    end

    local function reloadConsole()
        clearRows()
        for _, e in ipairs(consoleBuf) do addRow(e) end
        scrollConsoleBottom()
    end

    local function toggleConsole(on)
        consoleOpen = on
        consolePanel.Visible = on
        if on then reloadConsole() end
    end

    clearBtn.MouseButton1Click:Connect(function()
        pressAnim(clearPill)
        consoleBuf = {}
        clearRows()
    end)
    closeBtn.MouseButton1Click:Connect(function()
        pressAnim(closePill)
        toggleConsole(false)
    end)

    -- Mỗi phím script gửi (DOWN/UP, có Shift/Ctrl/Alt) được ghi vào console
    Keys.onLog = function(kind, name, mods)
        local m = ""
        if mods then
            local t = {}
            if mods.ctrl then t[#t + 1] = "ctrl" end
            if mods.shift then t[#t + 1] = "shift" end
            if mods.alt then t[#t + 1] = "alt" end
            if #t > 0 then m = table.concat(t, "+") .. "+" end
        end
        local isDown = (kind == "DOWN")
        consoleAppend({
            text = string.format("%s  %s  %s%s", os.date("%H:%M:%S"), isDown and "DOWN" or "UP  ", m, tostring(name)),
            color = isDown and Color3.fromRGB(235, 240, 255) or gray(140),
        })
    end

    -- ===== NÚT "MINI" và "CONSOLE" Ở THANH TIÊU ĐỀ (bên phải) =====
    local miniOpenPill = makePill(header, UDim2.new(0, 58, 0, 22), UDim2.new(1, -70, 0.5, -11))
    local miniOpenBtn = makeTextButton(miniOpenPill, "mini", 11, Enum.Font.GothamMedium)
    hoverGlass(miniOpenBtn, miniOpenPill)
    bindClick(miniOpenBtn)
    miniOpenBtn.MouseButton1Click:Connect(function()
        pressAnim(miniOpenPill)
        toMini()
    end)

    local consoleBtnPill = makePill(header, UDim2.new(0, 74, 0, 22), UDim2.new(1, -152, 0.5, -11))
    local consoleBtn = makeTextButton(consoleBtnPill, "console", 11, Enum.Font.GothamMedium)
    hoverGlass(consoleBtn, consoleBtnPill)
    bindClick(consoleBtn)
    consoleBtn.MouseButton1Click:Connect(function()
        pressAnim(consoleBtnPill)
        toggleConsole(not consoleOpen)
    end)

    task.spawn(function()
        while gui.Parent do
            task.wait(0.15)
            if miniMode then refreshMini() end
        end
    end)

    -- Popup tự bật với hiệu ứng mượt ngay sau intro
    task.delay(0.05, openMain)
end

-- Start
createIntro()
