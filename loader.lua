-- tetoMIDI loader (dán đoạn này vào executor)
-- Gist: tetomidi-lua / main.lua
local GIST_USER = "talentless-custom-song"
local GIST_ID   = "b85a0a2c9be4c09c4ae8f0c0cc4bacdf"

local url = ("https://gist.githubusercontent.com/%s/%s/raw/main.lua"):format(GIST_USER, GIST_ID)

local ok, src = pcall(game.HttpGet, game, url)
if not ok or type(src) ~= "string" or #src < 100 then
    return warn("[tetoMIDI] Không tải được script từ Gist: " .. tostring(src))
end

local fn, err = loadstring(src)
if not fn then
    return warn("[tetoMIDI] Lỗi script: " .. tostring(err))
end
fn()
