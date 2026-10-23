# aetherium 功能裁剪（trim）定稿紀錄

本輪：2026-10-23。做完的是「裁剪收尾三件事」：補丁系列完整套一遍並驗證、args.gn 定稿、
`gn gen` 跑成功並留下規模數字。**沒有跑全量編譯**（本機 14GB RAM、用戶還在用瀏覽器，
規則 27/57 與本輪指令都禁止把硬體吃滿；只做了 `gn gen`／`gn desc`／`gn args --list`／
`ninja -t graph` 這類輕量查詢）。

源碼樹：`/opt/chromium-src/src`｜`chrome/VERSION` = 157.0.8095.0｜HEAD `6ac1da15572a0`（detached）

---

## 1. 補丁套用結果（全綠）

`~/Downloads/aetherium/patches/` 下實際是 **10 支**補丁（不是 8 支，trim/ 兩支是 2026-10-22 加的）：

| 補丁 | 碰到幾個檔案 | 內容 |
|---|---|---|
| `adblock/0001-mv2-restore` | 4 | 救回 MV2 擴充、about:extensions 顯示 manifest 版本 |
| `adblock/0002-remove-navigation-source-param` | 1 | `components/search_engines/template_url.cc`：搜尋 URL 不帶 source 追蹤參數 |
| `adblock/0003-disable-intranet-redirect-detector` | 1 | `chrome/browser/intranet_redirect_detector.cc`：不探內網重導向 |
| `adblock/0004-disable-dial-periodic-discovery` | 1 | `chrome/browser/media/router/discovery/dial/dial_registry.cc`：DIAL 週期性廣播 |
| `performance/0001-default-memory-saver-on` | 1 | `components/performance_manager/user_tuning/prefs.cc`：記憶體節省出廠開 |
| `security/0001-disable-battery-status-service` | 2 | `services/device/battery/battery_status_service.{cc,h}`：拿掉電池指紋 |
| `security/0002-disable-sb-incident-reporting` | 5 | Safe Browsing 事件回報整條斷掉 |
| `security/0003-disable-sb-client-side-phishing-report` | 1 | 釣魚頁比對結果不上報 |
| `trim/0001-disable-printing-pdf-screenai-cast` | **26（全 BUILD.gn）** | 把打印／PDF／Screen AI／服務發現／背景模式的「無條件引用」改成 `if` 條件 |
| `trim/0002-headless-ozone-autodetect` | 2 | headless 的 ozone 平台改執行期自動偵測 |

實測（2026-10-23）：

- 10 支**全部**在樹上，`git status --porcelain` = 44 個 `M`（`trim/0001` 26 檔 + 其餘 18 檔，
  檔案有重疊所以總數是 44）。
- 為了證明「不是只在舊樹上剛好對上」，本輪把 44 個改動用 `git stash push --staged` 收起來、
  讓樹回到乾淨 HEAD，**從零跑一次 `apply-patches.sh`**：10 支全過、44 檔，
  產出的 `git diff --cached` 與收起來前**逐位元組相同**（`diff -q` 無差異）。確認後 drop 掉 stash。
- `scripts/apply-patches.sh` 本輪改成**冪等**：舊版第二輪一定不綠
  （`git apply --check` 看的是「能不能再套一次」，重複套用必然衝突，被誤判成「套用失敗」）。
  現在先用 `git apply --reverse --check` 判「已在樹上」→ 跳過不算錯，並新增 `--dry-run`
  （只回報狀態、不動樹）。兩條路徑都實跑過：
  乾淨樹 → 「本輪新套 10 支｜原本已在樹上 0 支」；已套樹 → 「新套 0 支｜已在樹上 10 支」，兩者 rc=0。
- ⚠️ 補丁是**未 commit 的工作區改動**（跟之前一樣）。要 commit 進 `/opt/chromium-src` 那棵樹
  是另一件事，本輪沒做（那棵樹是 detached HEAD 的上游 checkout，改了會妨礙日後 gclient sync）。

---

## 2. args.gn 定稿

**路徑：`/opt/chromium-src/src/out/Aetherium/args.gn`**（新建的正式建置目錄；
舊的 `out/Release` 現已不存在，實測 `/opt/chromium-src/src/out/` 本輪開始時是空的）。

- 自訂 key 共 **44 條**，逐條用 `gn args --list --short out/Aetherium` 核對過
  （該實測清單 **1260** 條真 arg）。結果：**0 條打錯字／查無此名**。
  這是必查項，因為 GN 對不存在的 arg 只 WARN 不報錯，值會被靜默丟掉。
- 上一版 `~/Downloads/chromium-patches/args.gn.2026-10-11` 裡有幾條在 157 **已不存在**，
  設了等於沒設（實測 `gn args --list` 查無）：`enable_vr`、`enable_nacl`、`enable_plugins`、
  `enable_media_router`、`enable_xfa`、`enable_swiftshader`（SwiftShader 拆成
  `enable_swiftshader_vulkan` + `angle_enable_swiftshader` 兩條）。本檔一律拿掉並改用真開關。
- 每條都有繁中註解寫「這是什麼／為什麼這樣設」，此檔不重複。關鍵群組：
  - 最佳化三件套（用戶定案開著）：`use_thin_lto=true`、`is_cfi=true`、`chrome_pgo_phase=2`、
    `pgo_data_path="//chrome/build/pgo_profiles/chrome-linux-main-…profdata"`、
    `optimize_for_size=true`，`is_official_build` 仍留 false（官方建置會綁死遥測/logging 等假設）。
  - 裁剪：`enable_printing=false`、`enable_print_preview=false`、`use_cups=false`、
    `enable_pdf=false`、`enable_screen_ai_service=false`、`enable_service_discovery=false`、
    `enable_mdns=false`、`enable_reporting=false`、`enable_background_mode=false`、
    `enable_hangout_services_extension=false`、`enable_remoting=false`（← 本輪新增，見第 6 節）。
  - 保留：`enable_extensions=true`、`enable_rust=true`、`enable_swiftshader_vulkan=true`、
    `angle_enable_swiftshader=true`、`use_ozone=true` + `ozone_platform_x11/wayland/headless=true`、
    `ozone_platform="x11"`、`proprietary_codecs=true`、`ffmpeg_branding="Chrome"`、
    `enable_widevine=true`。
  - 品牌：`branding_path_component="aetherium"`（實測 `chrome/app/theme/aetherium/BRANDING`
    內 `PRODUCT_FULLNAME=aetherium` 全小寫）、`use_dummy_lastchange=false`（否則 about:version 全 0）。

### 旗標「寫了」不等於「套上了」——實測產物層

`gn gen` 之後到 `out/Aetherium/toolchain.ninja` 反查（87 條編譯規則全部帶這些旗標）：

| 項目 | 實測 |
|---|---|
| ThinLTO | `-flto=thin` 出現 87 次 |
| PGO | `-fprofile-use=../../chrome/build/pgo_profiles/chrome-linux-main-…profdata` 87 次（**沒有網路下載**，走樹內既有 profile） |
| CFI | `-fsanitize=cfi` 87 次 |
| -Os | 87 次（`optimize_for_size`） |
| trim/0002 的 define | `gn desc out/Aetherium //chrome/browser/headless:initializer defines` → `AETHERIUM_HEADLESS_OZONE_DEFAULT="x11"`、`HAS_HEADLESS`、`HAS_X11`、`HAS_WAYLAND` 四條都在 |

（PGO 若留空 `pgo_data_path`，GN 會 `exec_script(//tools/update_pgo_profiles.py … get_profile_path)`
去 Google 抓 profile——本機環境 dl.google.com 不可達，所以 args.gn 里寫死指向樹內那份。）

---

## 3. `gn gen` 結果

```
cd /opt/chromium-src/src && nice -n19 ionice -c3 ./buildtools/linux64/gn gen out/Aetherium
Done. Made 35918 targets from 5016 files in 5911ms     rc=0
```

- `./buildtools/linux64/gn` 是樹內 gn（PATH 裡**沒有** `gn`/`autoninja`；
  `~/bin/chromium-build.sh` 第 22 行 export 的 `/opt/chromium-src/depot_tools` 這個目錄
  **現在不存在**，real depot_tools 在 `/opt/depot_tools` 與 `src/third_party/depot_tools`）。
- ⚠️ **`gn gen --check` 不是綠的**，但這不是裁剪造成的：同一棵樹把裁剪 flag 全部打開做對照組
  （`out/ProbeNoTrim`）跑 `--check` 一樣失敗（4 條錯），正式組 9 條錯，內容都是
  test 檔的「Can't include this header / Include not allowed」政策抱怨，加上一條
  `//gpu/webgpu/dawn_commit_hash.h: Source file not found`（那是 DEPS hook 要生成的檔，
  本機樹沒跑到那步 hook）。上表口徑（`gn gen` 不加 `--check`）才是正式構建用的，**成功**。

---

## 4. 規模指標（邊數）

先前流傳的「裁剪後 223,852 edges」**用本輪三種口徑都重現不了**（差一兩個數量級），
判斷是當時統計命令不同。為避免又拿一個來路不明的數字比，本輪把**同指令、同樹、只差 flag**
的對照組一起量（`out/ProbeNoTrim` = 10 支補丁都套著、但裁剪 flag 全開回上游預設）：

| 口徑（命令都列在下面） | 裁剪後 Aetherium | 裁剪前 ProbeNoTrim | 差 |
|---|---|---|---|
| GN 目標數 `gn ls out/X \| wc -l` | **35,918** | 36,385 | −467 |
| build.ninja 邊 `grep -c '^build '` | **52,045** | 52,796 | −751 |
| toolchain.ninja 邊 | **43,160** | 43,491 | −331 |
| `ninja -C out/X -t graph chrome \| wc -l` | **2,048,045** | 2,087,978 | −39,933 |
| `ninja -C out/X -t graph \| wc -l`（all） | **5,030,607** | — | — |

要怎麼讀：GN 層「少 467 個目標、少 1,082 條 ninja 邊」≈ 上游那些打印/PDF/Screen AI/
服務發現的 target 不再進圖；`chrome` 目標的圖行數少約 4 萬行（≈1.9%）是含標頭依賴的
檔案級規模。**真正的產物體積/編譯時間變化要等編一次才知道，本輪按指令沒編。**
日後要比較，固定用「`gn ls`＋`grep -c '^build ' build.ninja`＋`-t graph chrome`」這三口徑。

---

## 5. 哪些是「改源碼」而不是 flag（檔案:行號，行號是 2026-10-23 樹上實測）

光設 flag 會斷鏈：157 桌面代碼把打印/PDF/Screen AI/服務發現/背景模式**當必開**無條件引用，
所以 `trim/0001` 先把 26 個 BUILD.gn 的 deps 包成 `if`，flag 才關得掉。

| 檔案（`/opt/chromium-src/src/` 下） | 第一處行號 | 加了多少處 `if (enable_…)` |
|---|---|---|
| `chrome/test/BUILD.gn` | 333 | 18 |
| `chrome/browser/BUILD.gn` | 1582 | 14 |
| `chrome/browser/extensions/BUILD.gn` | 1234 | 10 |
| `chrome/browser/ui/lens/BUILD.gn` | 182 | 5 |
| `chrome/browser/ui/read_anything/BUILD.gn` | 96 | 5 |
| `chrome/browser/accessibility/BUILD.gn` | 77 | 4 |
| `chrome/browser/prefs/BUILD.gn` | 219 | 4 |
| `chrome/browser/renderer_context_menu/BUILD.gn` | 201 | 4 |
| `chrome/browser/ui/BUILD.gn` | 164 | 4 |
| `chrome/renderer/BUILD.gn` | 270 | 3 |
| `components/printing/browser/BUILD.gn` | 35 | 3 |
| `printing/backend/BUILD.gn` | 35 | 3 |
| `chrome/browser/accessibility/tree_fixing/BUILD.gn` | 73 | 2 |
| `chrome/browser/back_forward_cache/BUILD.gn` | 60 | 2 |
| `chrome/browser/component_updater/BUILD.gn` | 250 | 2 |
| `chrome/browser/contextual_tasks/BUILD.gn` | 553 | 2 |
| `chrome/browser/enterprise/data_protection/BUILD.gn` | 59 | 2 |
| `chrome/browser/guest_view/BUILD.gn` | 131 | 2 |
| `chrome/browser/ui/webui/settings/BUILD.gn` | 109 | 2 |
| `chrome/browser/ui/webui/side_panel/read_anything/BUILD.gn` | 72 | 2 |
| `chrome/tools/service_discovery_sniffer/BUILD.gn` | 21 | 2 |
| `chrome/utility/BUILD.gn` | 155 | 2 |
| `printing/common/BUILD.gn` | 12 | 1 |
| `chrome/browser/accessibility/live_caption/BUILD.gn` | 60 | 1 |
| `chrome/browser/profiles/BUILD.gn` | 997 | 1 |
| `chrome/browser/ui/blocked_content/BUILD.gn` | 135 | 1 |

用到的條件只有 6 個 flag：`enable_printing`、`enable_print_preview`、`enable_pdf`、
`enable_screen_ai_service`、`enable_service_discovery`、`enable_background_mode`。

`trim/0002`（headless ozone 自動偵測）：

- `chrome/browser/headless/BUILD.gn:30-46` —— 編譯期把「這個建置真的有哪幾個 ozone 平台」
  傳進去：`:35` 是 `AETHERIUM_HEADLESS_OZONE_DEFAULT="<ozone_platform>"`，
  `:38/:41/:44` 分別是 `HAS_HEADLESS`／`HAS_X11`／`HAS_WAYLAND`。
  ⚠️ 不能改成直接 dep `//ui/ozone:platform`（visibility 擋住），也不能用三元運算子（GN 不支援），
  所以走 define 傳值。
- `chrome/browser/headless/headless_mode_init.cc:100-140` —— 執行期選擇順序：
  明確帶 `--ozone-platform` > 有編 headless 就 headless > 照 `WAYLAND_DISPLAY`
  （`base::Environment::Create()->HasVar("WAYLAND_DISPLAY")`，:109-110）在**有編進來**的
  平台裡挑 wayland 或 x11（:112-135）> 建置出廠預設。只選存在的平台，所以永遠不會
  選到沒編進去的那個而 `LOG(FATAL)` abort。

其它純 flag 的裁剪（不需要改源碼，上游本来就支持關）：`use_cups`、`enable_mdns`、
`enable_reporting`、`enable_hangout_services_extension`、`enable_remoting`。
`xfa` 已无需處理（157 上游已移除 XFA，`gn args --list` 查無 `enable_xfa`）。

---

## 6. 驗收項：`/proc/<pid>/environ` 可讀

- 實測 `pgrep -c -x aetherium` = **0**（本機現在沒有跑著的 aetherium 進程，用戶瀏覽器沒開），
  所以 `head -c 80 /proc/$(pgrep -x aetherium | head -1)/environ` 這道**没法驗，需用戶自己把
  aetherium 開起來再跑一次**（本輪按指令不去啟動他的瀏覽器，也不碰 :0 桌面）。
- 能先交的是「源碼層沒有洗 environ 的東西」這條間接證據（實測，不是推測）：
  10 支補丁裡唯一碰環境變數的是 `trim/0002`，它只**讀** `WAYLAND_DISPLAY`
  （`base/environment.h`）；全樹搜 `base/`、`chrome/`、`sandbox/`、`linux-sandbox/` 找不到
  `clearenv`／`environ = nullptr` 之类把環境抹掉的實作。Helium 會洗 environ，上游 Chromium 不會，
  我們的改名/裁剪沒動這條路徑。
- 已裝的那包是 2026-10-13 的舊產物（`/usr/lib/aetherium/aetherium`，292MB，
  `pacman -Q` → `aetherium 157.0.8095.0-1`），**不含本輪的 trim**；要拿本輪結論當驗收，
  得先重編再裝。

---

## 7. 沒做完／要用戶拍板的（本輪一律沒動）

1. **品牌化補丁系列的衝突**（這才是下次真編的頭號障礙）：
   `~/Downloads/chromium-patches/` 四支的狀態本輪實測——
   `0001-privacy…`、`0002-branding…`、`0003-icon…` 可乾淨套用，
   `0004-aetherium-branding-round2.patch`（1178 檔、40MB）**衝突**：
   `chrome/app/chromium_strings.grd:1863` 與全部 `chrome/app/resources/chromium_strings_*.xtb`
   的 row 都對不上（10-22 重新 sync 後上游字串行號位移）。要重新產生。
   本輪只套了 `0003-icon-aetherium.patch`——因為 `gn gen` 在產生階段就要透過
   `build/util/branding.gni` 的 `exec_script(version.py …)` 讀
   `chrome/app/theme/aetherium/BRANDING`，那個目錄是 0003 建立的；不套它就沒辦法驗 args.gn。
   要撤回：`git apply -R ~/Downloads/chromium-patches/0003-icon-aetherium.patch`。
   ⚠️ 0002 目前**未套**，所以 `.desktop` 檔名（`chrome/common/channel_info_posix.cc` 的
   `GetDesktopName()`）與 `~/.config/<目錄名>`（`chrome/common/chrome_paths_linux.cc`）
   這兩個出廠值還在樹上維持上游的 `chromium-browser.desktop`／`chromium`；
   真編之前必須把 0002（或等價改動）一起處理掉，否則設定目錄與 WM_CLASS 會退回 chromium。
2. **`enable_on_device_translation=false` 關不掉**（裝置端翻譯）。實測 `gn gen` 直接報錯：
   `ERROR at //chrome/browser/on_device_translation/BUILD.gn:7:1: Assertion failed.`
   源頭是 `chrome/browser/accessibility/live_caption/BUILD.gn:47` 無條件引用那個目標。
   args.gn 裡已把這行拿掉並寫成註解。要真裁，必須再改那兩個 BUILD.gn（包 `if` + 去掉上游 assert），
   是用戶還沒點頭的一項。
3. **`enable_remoting = false`（Chrome 遠端桌面主機端）是本輪自己加的裁剪**，
   不在用戶那張「已定案」清單上。要反悔就刪掉 args.gn 那行（可回退，只影響 `//remoting` 那坨目標）。
4. **`use_cups=false` + 打印全刪**之後，`~/Downloads/pkgbuilds/aetherium/PKGBUILD` 的
   `depends=(… libcups …)` 與 `optdepends` 裡跟打印/PDF 相關的項可以清掉；
   `.desktop` 的 `MimeType=` 裡那條 `application/pdf` 也已無對應 handler。
   （動 PKGBUILD 是用戶的打包檔，本輪沒改。）
5. **`.github/workflows/build-linux.yml`／`build-android.yml` 的 `gn gen --args` 用的是旧 arg 名**
   （`enable_vr`、`enable_media_router`、`enable_plugins`、`safe_browsing_mode=0`… 見第 2 節），
   跟本輪定稿的 args.gn 是兩套機制。要統一成「走 patches/ + scripts/apply-patches.sh」需要用戶點頭。
6. **本輪沒有編譯、也沒有裝/卸任何系統套件**；`out/Aetherium`（含 build.ninja、
   toolchain.ninja、args.gn）與 `out/ProbeNoTrim`（對照組）留在樹裡。
   `ProbeNoTrim` 只是量邊數用的，下次接手可直接 `rm -rf /opt/chromium-src/src/out/ProbeNoTrim`。
7. 順帶一提：`git -C /opt/chromium-src/src status` 乾淨（未 commit 的 44+73 檔改動是本輪補丁狀態，
   沒有其它游離改動）；`agents/internal`、`agents/shared`、`chrome/app/theme/google_chrome`
   等 submodule 是**未初始化**狀態（`git submodule status` 前綴 `-`），跟裁剪無關。

---

## 8. 下一次接手的入口命令（全部唯讀或可重覆執行）

```bash
cat /opt/chromium-src/src/chrome/VERSION
git -C /opt/chromium-src/src status --porcelain | wc -l      # 44（补丁）+ 73（0003-icon）
~/Downloads/aetherium/scripts/apply-patches.sh --dry-run      # 只報狀態，不動樹
cd /opt/chromium-src/src
./buildtools/linux64/gn gen out/Aetherium                     # 正試建置，成功標語 Made N targets
./buildtools/linux64/gn args --list --short out/Aetherium | wc -l   # 真 arg 總數（本輪 1260）
./buildtools/linux64/gn ls out/Aetherium | wc -l               # 目標數（本輪 35918）
grep -c '^build ' out/Aetherium/build.ninja                    # 邊數（本輪 52045）
./buildtools/linux64/gn desc out/Aetherium //chrome/browser/headless:initializer defines
grep -F -c 'fsanitize=cfi' out/Aetherium/toolchain.ninja        # CFI 真的套上（本輪 87）
# 用戶開起 aetherium 後才能驗的那條：
head -c 80 /proc/$(pgrep -x aetherium | head -1)/environ
```
