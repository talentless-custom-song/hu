# tetoMIDI Assets + Script

## Cấu trúc

```
hu/
├── tetoMIDI.lua          ← Script chính (Liquid Glass, v2.3)
├── images/
│   ├── logo.png          ← Logo bubble + intro
│   ├── piano.png  drum.png  guitar.png  hub.png   ← icon sidebar (lấy từ app tetoMIDI v1.3)
│   ├── icon_auto.png  icon_custom.png             ← icon cũ (không còn dùng, có thể xoá)
│   └── discord.png       ← Icon Discord
├── sounds/
│   └── click.mp3         ← Tiếng click chuột khi bấm nút
└── README.md
```

## Cách dùng

1. Upload **toàn bộ folder này** lên GitHub (repo phải để **Public**), nhớ upload cả 4 icon mới trong `images/`.
2. Mở `tetoMIDI.lua`, kiểm tra 2 dòng `GITHUB_USER` / `GITHUB_REPO`.
3. Chạy `tetoMIDI.lua` trong executor (Delta, Wave, Codex...).
4. Bỏ file `.mid` / `.midi` vào thư mục `tetoMIDI/midi/` trong workspace của executor, rồi mở tab piano / drum / guitar → bấm ô "select MIDI file".

## Giao diện (v2.3)

Sidebar: **piano player · drum player · guitar player · midi hub · discord**

Mỗi trang player có: chọn file MIDI, các nút bật/tắt, piano roll rơi nốt, PLAY / STOP, thanh tua + thời gian.

| Trang | Nút bật/tắt | Roll |
|---|---|---|
| piano player | 88 key · Sustain · Velocity · Note length · Loop | bàn phím 88 (hoặc 61) phím, in sẵn phím máy tính tương ứng (chữ xanh = phím giữ CTRL) |
| drum player | Note length · Loop | 9 làn trống + phím gán |
| guitar player | Note length · Loop | 6 dây, hiện số phím đàn khi nốt sáng |

- **88 key**: bật = 88 phím (nốt ngoài 36–96 dùng lớp CTRL), tắt = 61 phím.
- **Velocity**: tô đậm/nhạt nốt theo velocity.
- **Note length**: bật = nốt giữ độ dài thật; tắt = mọi nốt ngắn như nhau.
- Bảng phím (piano 61/88, velocity, drum, guitar, cách chọn dây/phím) lấy từ app tetoMIDI v1.3 — nằm ở khối `MIDI CORE` trong `tetoMIDI.lua` (`Core.PIANO_61`, `Core.DRUMS_MAP`, `Core.GUITAR_KEYMAP`...); engine bấm phím nằm ở khối `ENGINE` ngay sau đó.
- Cấu hình (nút bật/tắt, file đang chọn) lưu ở `tetoMIDI/config.json`.
- Cửa sổ kéo được từ mọi chỗ trống (nút, ô nhập, danh sách cuộn và thanh tua không kéo cửa sổ).

## Trạng thái

- Đã xong: giao diện, đọc file MIDI, piano roll, chạy/tạm dừng/tua, **engine bấm phím vào game** (piano / drum / guitar).
- Chưa làm (bước sau): midi hub tải file `.mid` về `tetoMIDI/midi/` (hiện hub vẫn chạy script midi2lua cũ).

## Engine bấm phím (sửa lỗi "có key map mà không đánh được")

Bản v2.3 trước đó chỉ có giao diện + piano roll, **chưa có đoạn code nào gửi phím** (`P.onAdvance` / `P.onStop` không ai gắn),
nên bấm PLAY chỉ thấy nốt rơi chứ game không nhận phím. Giờ khối `ENGINE: GỬI PHÍM VÀO GAME` trong `tetoMIDI.lua` (port từ
`engine/dispatchers.py` + `keysim.py` + `transport.py` của app v1.3) làm việc đó:

- **Piano**: bảng 61 phím; nốt đen = `Shift` + phím (ký hiệu `! @ $ % ^ * (` = Shift + phím số của nốt ngay dưới, chữ hoa = Shift + chữ thường);
  nốt ngoài 36–96 (khi bật *88 key*) dùng lớp `Ctrl`; *Velocity* = `Alt` + phím velocity trước mỗi nốt; *Sustain* = giữ `Space` theo pedal (CC64).
- **Drum**: MIDI note -> tên trống -> phím trong `Core.DRUMS_MAP` (kênh 10 nếu file có, không thì mọi kênh).
- **Guitar**: `Core.GUITAR_KEYMAP` (note 40–75, gập octave nếu nốt ngoài dải).
- *Note length* bật = giữ phím đúng độ dài nốt; tắt = chạm ngắn 0.12 s. Dừng / tạm dừng / tua / đổi tab / đổi bài = thả hết phím.
- Gửi phím bằng `VirtualInputManager:SendKeyEvent` (chạy cả PC lẫn mobile), tự chuyển sang `keypress()/keyrelease()` nếu executor không có / bị lỗi.
  Đổi bằng `Core.INPUT_METHOD` (`"auto"`, `"vim"`, `"keypress"`) ở đầu khối ENGINE.
- Giữ `Shift/Ctrl/Alt` qua ít nhất 1 khung hình để game đọc đúng modifier; nốt thường + nốt Shift trong cùng 1 hợp âm vẫn ra gần như cùng lúc.

### Nếu vẫn không đánh được
1. Đặt `Core.DEBUG_KEYS = true` rồi bấm PLAY, mở console (F9): thấy dòng `[tetoMIDI] down t ...` nghĩa là engine đang gửi phím.
   Không thấy dòng nào -> file MIDI không có nốt hợp lệ cho tab đó (vd drum nhưng file không có nốt trống), hoặc chọn nhầm tab.
2. Thấy dòng nhưng game không nhận: thử `Core.INPUT_METHOD = "keypress"` (PC) hoặc `"vim"`.
3. Nốt trắng ăn mà nốt đen / nốt thấp-cao không ăn: game đọc Shift/Ctrl theo kiểu khác -> thử đổi `INPUT_METHOD` như trên.
4. Toast "This executor can't send key presses": executor không có cả `VirtualInputManager` lẫn `keypress`.
5. Đang gõ chữ trong ô tìm kiếm thì phím rơi vào ô đó — script tự bỏ focus ô chữ khi bấm PLAY.
6. Chỉ chạy 1 bản script cùng lúc (chạy lại script mà chưa tắt bản cũ sẽ bấm phím 2 lần).

## Chỉnh nhanh

- Tắt blur phông game: đặt `BLUR_SIZE = 0` (trong khối UI HELPERS)
- Hub: `HUB_API` (hub chính, hiện là `https://midi2lua.pythonanywhere.com`); thêm hub phụ vào `HUB_API_EXTRA` (danh sách bài của các hub được gộp lại)
- Thời gian nốt rơi: `Cfg.roll.fall` (giây, mặc định 3)
- Thư mục MIDI: `MIDI_DIR`
- Chỉnh to nhỏ tiếng click: `CLICK_VOLUME` (trong khối TIẾNG CLICK CHUỘT)
- Chỉnh to nhỏ laptop intro: `LAPTOP_FILL_X`, `LAPTOP_FILL_Y`, `LAPTOP_K_MAX`
