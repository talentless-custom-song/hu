# tetoMIDI Assets + Script

## Cấu trúc

```
tetomidi-assets/
├── tetoMIDI.lua          ← Script chính (Liquid Glass)
├── images/
│   ├── logo.png          ← Logo bubble + intro
│   ├── icon_auto.png     ← Icon Auto Player
│   └── icon_custom.png   ← Icon Custom Song
└── README.md
```

## Cách dùng

1. Upload **toàn bộ folder này** lên GitHub (repo phải để **Public**)
2. Mở file `tetoMIDI.lua`
3. Sửa 2 dòng này:

```lua
local GITHUB_USER = "YourGitHubUsername"   -- ← username GitHub của bạn
local GITHUB_REPO = "tetomidi-assets"      -- ← tên repo
```

4. Copy toàn bộ nội dung `tetoMIDI.lua` vào Delta Executor và chạy.

## Tính năng

- Liquid Glass UI
- Floating bubble dùng ảnh thật (kéo được + click ẩn/hiện)
- Auto Player (search + play)
- Custom Song → lưu vào `tetomidi2lua/` trong workspace của executor
- Ảnh tải từ GitHub (jsDelivr, dự phòng raw.githubusercontent) → lưu vào `tetoMIDI/images/` → hiển thị bằng `getcustomasset`
- Executor cần hỗ trợ `writefile` + `getcustomasset` (Delta, Wave, Codex... đều có)
