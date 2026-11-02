# aetherium Android args 可行性（2026-10-28）

## 結論

- 同一棵樹可以用 `target_os="android"`、`target_cpu="arm64"` 做 args 層驗證。
- 實測 `gn gen` rc=0（64,423 targets），`ninja -n chrome_public_apk` rc=0（60,183 行命令）。
- **沒有編譯、沒有產生 APK、沒有安裝到手機**；以下「通過」都只到 GN 產生建置圖與 dry-run 為止。

重現命令（輸出目錄可換成任何空目錄）：

```bash
mkdir -p /home/avatar/chromium-out/AndroidCheck
cp ~/Downloads/aetherium/args-android.gn /home/avatar/chromium-out/AndroidCheck/args.gn
cd /opt/chromium-src/src
nice -n19 ionice -c3 ./buildtools/linux64/gn gen /home/avatar/chromium-out/AndroidCheck
ninja -C /home/avatar/chromium-out/AndroidCheck -n chrome_public_apk
```

## 與 Linux args 的衝突點

| 項目 | Linux 定稿 | Android 的問題 | 處理 |
|---|---|---|---|
| `target_os` / `target_cpu` | 不設（預設 linux/x64） | 必須是 `android` / `arm64`；照抄 Linux 會編錯平台 | Android 檔已設，勿覆蓋 |
| Ozone | `use_ozone=true`、`ozone_platform="x11"`、`ozone_platform_x11/wayland/headless=true` | Android 用自己的平台；把 x11/wayland 編進來會拉進 Linux 顯示層 | Android 檔完全不設這組 |
| 擴充 | `enable_extensions=true` | 上游 Android 多處 `assert(!is_android)`，結構性不支援 | Android 必須 `false` |
| PGO | `chrome_pgo_phase=2` + Linux 的 `pgo_data_path` | Android 沒有這份 Linux profile；相位 2 會找錯檔 | Android 用相位 1、不設 `pgo_data_path` |
| glib / CUPS | `use_glib=true`、`use_cups=false` | Android 不用 glib；CUPS 在 Android 本來就 false | 不抄 |
| Widevine | `enable_widevine=true` | Android 預設就是 true（系統 MediaDrm） | 可留可刪，無衝突 |
| 列印 | `enable_printing=false` | Android 的 `enable_printing` 預設是 **true**（系統 Print Spooler） | 已加 `false`；gn/dry-run 過，**編譯與實機未驗** |
| PDF / 預覽 | `enable_pdf=false`、`enable_print_preview=false` | Android 這兩個本來就 false | 已明寫，僅自證 |
| ScreenAI / mDNS / Cast 探索 | 三條都 false | Android 這三條本來就 false（`enable_desktop_android_extensions` 未開時） | 已明寫，僅自證 |
| Cast receiver | `enable_cast_receiver=false` | 預設 false | 已明寫 |
| 品牌字串 | `branding_path_product="aetherium"`、`branding_path_component="aetherium"` | 只設 component 時 `gn gen` 會過，但 `ninja -n` 會找已被改名的 `chrome/app/chromium_strings.grd` 而報 missing | Android 檔已補 product |
| 語音 | 無 | `enable_speech_synthesis`、`enable_speech_recognition` 這棵樹根本沒有宣告（設了只 WARN） | 改成 `enable_speech_service=false`、`enable_browser_speech_service=false` |

## 2026-11-03 整理結果

- `args-android.gn` 是唯一 Android 參數來源；刪除檔尾會把 enterprise 裁剪重新覆寫為
  `true` 的暫緩區，55 個 key 現在每個只宣告一次。
- `.github/workflows/build-android.yml` 的 full-build 路線直接複製這份檔案，`gn gen` 後逐一
  對照 `gn args --list --short`，不再維護另一串 inline args。
- full-build checkout 在 `gclient sync` 前把 `target_os = ["android"]` 寫進 `.gclient`；這和
  `args-android.gn` 裡的 `target_os="android"` 是兩層不同設定。前者決定要不要同步 Android
  toolchain，缺少時 `checkout_android=false`，GN 會在 `build/config/android/config.gni` 直接拒絕。
- WebRTC 在 Chromium 的 `rtc_include_internal_audio_device=false` 路線會先加入 AAudio define，
  再用 `defines =` 寫 dummy define；GN 禁止非空 list 被另一個非空 list 覆蓋。固定補丁
  `deps/webrtc/0001-append-dummy-audio-define.patch` 改成 `+=`，兩個 build intent 都保留。
- workflow 會確認 `aetherium_strings_zh-TW.xtb` 與
  `branded_strings_zh-TW.pak` target 都存在，再開始編譯 `chrome_public_apk`。
- Linux 與 Android 共用 `patches/series` 的 21 支固定順序；補丁只能整支套用，任何衝突
  都會直接失敗，不會逐檔拼出部分狀態。

## 還沒驗證 / 風險

1. **完整編譯**：`is_cfi=true`、`use_thin_lto=true`、`chrome_pgo_phase=1` 只過 GN 與 dry-run；Android 的 CFI/ThinLTO 實際能否編過，要等真編。
2. **`enable_printing=false`**：GN 目標數 64,569 → 64,423（少 146 個），但 Android 列印 UI/Java 類是否還有漏網引用，只有編譯會知道；實機也要確認設定頁沒有留下死入口。
3. **Cast/Media Router**：args 只關掉探索與 receiver；`chrome/browser/media/router` 在 Android dry-run 仍有 11 個物件、`components/media_router` 仍有 70 個。上游沒有 `enable_media_router` 這類 arg，要徹底拆需另寫 BUILD.gn 條件與 C++ stub，風險高，這次沒動。
4. **品牌 product**：Linux 與 Android 都必須同時有 `branding_path_component` 與 `branding_path_product`；只設前者會在 ninja 階段才爆，`gn gen` 看不出來。
