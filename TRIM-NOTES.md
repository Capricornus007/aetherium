# aetherium 功能裁剪（trim）定稿紀錄

> ## 2026-10-23 第二輪（品牌化收尾＋assert 解除）已完成，先看這一段
>
> 上一段（同日的「裁剪定稿」）留下的兩個最大未了項，本輪都做完並實測過：
>
> 1. **品牌化補丁重新產生完成**：`patches/branding/0001-theme-aetherium-icons.patch`
>    ＋ `patches/branding/0002-branding-rename-aetherium.patch.gz`。`GetDesktopName()`
>    現在回 `aetherium.desktop`、`~/.config` 目錄名是 `aetherium`、BRANDING 全小寫
>    `aetherium`、grit 字串檔 849 個檔案 63,419 處 `Chromium→aetherium` 全部重對到
>    158 的樹上。證據見第 9 節。
> 2. **`enable_on_device_translation=false` 真的關得掉了**：`patches/trim/0003-…`，
>    `gn gen` 由 rc=1（踩上游 assert）變成 rc=0。改了哪些檔哪一行見第 10 節。
> 3. 順帶把舊 0004  mega-patch 裡那批**跟品牌無關的本地隱私／AI 改動**（Safe Browsing
>    位址 sinkhole、拼字檢查預設關、autofill 預設關、NTP 那排 AI 磁貼、設定頁 AI 整頁、
>    預置捷徑磁貼…共 16 檔）搬進 `patches/privacy/0001-…`，否則今天重編就會把用戶
>    瀏覽器上已經存在幾個星期的行為弄丟。詳見第 11 節。
> 4. 補丁總數 **14 支**（原 10 支 ＋ branding 2 ＋ trim/0003 ＋ privacy/0001），
>    全部從**乾淨樹**重跑一次全綠，且與手刻狀態**逐位元組相同**；`apply-patches.sh`
>    現在支援 `.patch.gz` 且保證 14 支彼此**不重疊同一個檔案**（重疊會讓冪等判斷失真，
>    這是本輪踩過的第二個坑，見第 12 節）。
> 5. `config/args.gn` 進倉庫了（權威版本）；CI 也改成走同一個入口（見第 13 節）。
>
> 還沒有做的：**沒有編譯**（本輪指令與規則 27/57 都禁止在这臺 14GB 的機器上跑全量
>  編譯），所以「產物體積／執行期行為」仍是待驗項目；見第 14 節。

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

## 7. 沒做完／要用戶拍板的（10-23 第一輪當時的清單；其中 1、2、3 三項已在第二輪解決，見第 9、10、11 節）

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

---

## 9. 第二輪：品牌化補丁重做（這是用戶最火的那一條）

### 9.1 兩支補丁的分工

| 補丁 | 檔案數 | 內容 |
|---|---|---|
| `patches/branding/0001-theme-aetherium-icons.patch` | 73（全是新增的圖檔＋`BRANDING`） | 建立 `chrome/app/theme/{,default_100_percent/,default_200_percent/}aetherium/` 三組圖示目錄（Arcaea 雙色調 artwork）。原本這是 `~/Downloads/chromium-patches/0003-icon-aetherium.patch`，本輪把它收進倉庫，並把檔內 `chrome/app/theme/aetherium/BRANDING` 那 10 行的 `PRODUCT_INSTALLER_FULLNAME/SHORTNAME` 從 `Chromium Installer` 改成 `aetherium Installer`（同行數，hunk header 不用動）。 |
| `patches/branding/0002-branding-rename-aetherium.patch.gz` | 858 | 真正的改名：849 個 grit 字串檔（`.grd/.grdp/.xtb`，63,419 處 `Chromium`→`aetherium`）＋ 9 個出廠值／輸出檔名的程式檔。 |

兩支**互不重疊**（0002 完全不碰 `theme/aetherium/` 那些新檔，只碰 `theme/chromium/BRANDING` 這個上游既有檔），所以 0002 可以直接對乾淨樹生效，不需要 0001 先跑。

0002 是 gzip 是因為純文字版 **30MB**，超過 GitHub 單一檔 25MB 的軟上限（gzip 後 5.1MB，內容逐位元組校驗過相同）。`scripts/apply-patches.sh` 本輪起支援 `.patch.gz`（套前解到暫存檔、結束一律刪）。

### 9.2 改名規則（跟舊 0004 的差別）

- 字串檔：整檔把 `Chromium` 這個**大小寫完全一致**的词換成 `aetherium`。實測舊 0004 的 81,734 行字串改動裡，81,722 行就是這個規則的產物（我用腳本逐行比對過）。大寫 `CHROMIUM`（例如 `<ph name="BEGIN_LINK_CHROMIUM" />` 這種占位符名稱）**一律不動**，小寫 `chromium`（`www.chromium.org` 這種網址）也不動——動了會咬壞 grit。
- `ChromiumOS`→`aetheriumOS`、`Chromium OS`→`aetherium OS`（照上面的規則自然產生）。
- **偏離舊補丁的一處（故意的）**：舊 0004 在 `et/eu/hr/hu/sr-Latn/th` 六個語系的 `chromium_strings_*.xtb` 裡，把兩條訊息 id（`535243042947607642`、`8890569919834781711`）中的 `Chromium OS` 留著不改，同檔其它 200 多個語系卻照改，英語本體也照改（`chromium_strings.grd:1577` 是 `ChromiumOS could not save Chromium data...`）——那是舊補丁自己不一致。本輪改成全部一致（`aetherium OS`），符合規則 34「不準翻不該翻的、也别漏翻」。
- 範圍排除：`ios/**`（286 檔，我們不做 iOS）、`tools/grit/grit/testdata/*`（grit 自己單測的 fixtures，改了會弄壞 grit 測試）。其餘 849 檔全覆蓋，本輪新增了舊補丁漏掉的 72 個語系檔（`ash/strings/` 那一批多數語系舊補丁只改了 17 個）。
- 舊 `~/Downloads/chromium-patches/0002-branding-aetherium.patch` 寫的是 `Aetherium`（大寫 A），跟「產品名一律全小寫」的定案衝突 ⇒ **作廢**，後繼内容由 0002-branding-rename 承担。

### 9.3 改名證據（全部是實跑，不是看補丁內容）

```
$ grep -n 'PRODUCT_FULLNAME\|PRODUCT_INSTALLER' chrome/app/theme/aetherium/BRANDING chrome/app/theme/chromium/BRANDING
chrome/app/theme/aetherium/BRANDING:3:PRODUCT_FULLNAME=aetherium
chrome/app/theme/aetherium/BRANDING:5:PRODUCT_INSTALLER_FULLNAME=aetherium Installer
chrome/app/theme/chromium/BRANDING:3:PRODUCT_FULLNAME=aetherium
chrome/app/theme/chromium/BRANDING:5:PRODUCT_INSTALLER_FULLNAME=aetherium Installer

$ grep -n 'return "aetherium.desktop";' chrome/common/channel_info_posix.cc
153:  return "aetherium.desktop";

$ grep -n 'data_dir_basename = "aetherium";' chrome/common/chrome_paths_linux.cc
99:  std::string data_dir_basename = "aetherium";

$ ninja -C out/Aetherium -t targets all | grep -E 'channel_info_posix\.o|chrome_paths_linux\.o'
obj/chrome/common/channel_info/channel_info_posix.o: cxx
obj/chrome/common/constants/chrome_paths_linux.o: cxx          # 兩個檔真的進建置圖，不是只改了檔

$ ninja -C out/Aetherium -t commands gen/chrome/common/chrome_version.h | tail -1 | sh   # 實際跑 version action
../../third_party/cpython3/host/bin/python3 ../../build/util/version.py -f ../../chrome/VERSION \
    -f ../../chrome/app/theme/aetherium/BRANDING -o gen/chrome/common/chrome_version.h ...
$ grep -n 'PRODUCT_FULLNAME_STRING\|PRODUCT_SHORTNAME_STRING\|COPYRIGHT_STRING' out/Aetherium/gen/chrome/common/chrome_version.h
19:#define PRODUCT_FULLNAME_STRING "aetherium"
20:#define PRODUCT_SHORTNAME_STRING "aetherium"
22:#define COPYRIGHT_STRING "Copyright 2026 The Chromium Authors. All rights reserved."

$ strings -a /usr/lib/aetherium/aetherium | grep -xc 'aetherium.desktop'   # 10-13 那包舊產物的旁證
1
$ strings -a /usr/lib/aetherium/aetherium | grep -xc 'chromium-browser.desktop'
0
```

`~/.config/aetherium` 這條的完整鏈路（讀原始碼證明，不靠猜）：
`chrome/common/chrome_paths_linux.cc:90` 先取 `GetXDGDirectory(env, "XDG_CONFIG_HOME", ".config")`
→ `:99` 出廠名 `aetherium`（原為 `chromium`）→ `:100` `config_dir.Append("aetherium" + GetChannelSuffixForDataDir())`
→ 非 official 建置的 channel suffix 是空字串，所以就是 `~/.config/aetherium`（可用 `CHROME_CONFIG_HOME` 整個覆寫，`:83-91`）。

`WM_CLASS` 那條也是同一個來源推出去的，不用另外改：
`chrome/browser/shell_integration_linux.cc:574 GetProgramClassClass()` 拿 `chrome::GetDesktopName()`
（現在是 `aetherium.desktop`）→ `internal::GetDesktopBaseName()` 去掉 `.desktop` → `:537` 首字母大寫
→ res_class = `Aetherium`、res_name = `aetherium`。另外本輪也一起改了四個會露出品牌的出廠值：

| 檔案:行 | 原值 | 现值 | 這是什麼 |
|---|---|---|---|
| `chrome/browser/shell_integration_linux.cc:584` | `"chromium-browser"` | `"aetherium"` | 瀏覽器自己建立的 .desktop 裡 `Icon=` 的名字（要跟 PKGBUILD 裝的 `aetherium.png` 對上） |
| `chrome/browser/shell_integration_linux.cc:1043` | `"chromium"` | `"aetherium"` | 直接啟動用的 custom URI scheme 名稱 |
| `chrome/renderer/chrome_content_renderer_client.cc:600` | `FromAscii("chromium")` | `FromAscii("aetherium")` | 同一個 scheme 在 renderer 端的註冊，兩邊必須一致 |
| `media/audio/pulse/pulse_util.cc:40-41` | `kBrowserDisplayName="chromium-browser"`、`PRODUCT_STRING="Chromium"` | 皆 `aetherium` | PulseAudio 裡看到的應用程式名（音量控制器／混音器那一列） |
| `chrome/installer/linux/BUILD.gn:74,211,568` | `$root_out_dir/chrome`、`package="chromium-browser"` | `aetherium` | deb/rpm 打包用的產物路徑與套件名（我們走 PKGBUILD，這幾條是保持一致、不在路徑上） |
| `chrome/BUILD.gn:160,1906,2056` | `_chrome_output_name="chrome"` 等 | `aetherium` | **編譯輸出的執行檔就叫 `aetherium`**，PKGBUILD 第 78 行 `install -m755 "$_srcout/aetherium"` 綁這個名字 |
| `build/util/version.py:59-63` | 非 official 一律讀 `LASTCHANGE.dummy` | 優先讀真 `LASTCHANGE`（沒有才退回） | `LASTCHANGE.dummy` 裡沒有 `LASTCHANGE_YEAR` 這行（實測 grep 計數：真檔 1、dummy 0），不修的話 `COPYRIGHT_STRING` 會留著未替換的 `@LASTCHANGE_YEAR@` 字面。上表產生出的 `Copyright 2026` 就是修好後的結果。 |

### 9.4 規模數字對照（同口徑，只差本輪兩件事）

| 口徑 | 10-23 第一輪 | 10-23 第二輪（本輪） | 差 | 說明 |
|---|---|---|---|---|
| `gn ls out/Aetherium \| wc -l` | 35,918 | **35,877** | −41 | 品牌改名不動目標數；−41 全部來自 `enable_on_device_translation=false`（翻譯引擎那 41 個目標退出） |
| `grep -c '^build ' build.ninja` | 52,045 | **51,990** | −55 | 同上 |
| `grep -c '^build ' toolchain.ninja` | 43,160 | **43,129** | −31 | 同上 |
| `ninja -t graph chrome \| wc -l` | 2,048,045 | **2,046,418** | −1,627 | 同上 |
| CFI／ThinLTO／PGO／-Os 在 toolchain.ninja 的次數 | 87／87／87／87 | **87／87／87／87** | 0 | 最佳化三件套沒被本輪改動弄掉 |
| `gn args --list --short \| wc -l` | 1260 | 1260 | 0 | args.gn 的 45 條 key 逐條核對，查無此名 0 條 |

⚠️ 本輪實測口徑教訓：`gn ls` 與 `ninja -t targets all` 都會把 **test／fuzzing 目標**算進去，那些目標本來就無條件引用 `//remoting`、`//printing`、`//pdf`，所以「`gn ls \| grep //remoting` 還有 97 個目標」不等於「瀏覽器裡還有 remoting」。真正該看的口徑是 `ninja -t graph chrome`（= 會進產物的那張圖），本輪實測在那個口徑下：

| 子系統（圖中的 obj/ 前綴） | chrome 產物圖裡的檔數 |
|---|---|
| `obj/remoting/` | **0**（`enable_remoting=false` 確實整包拿掉） |
| `obj/pdf/`、`obj/chrome/browser/printing`、`obj/chrome/browser/screen_ai`、`obj/chrome/browser/local_discovery` | **0** |
| `obj/chrome/browser/on_device_translation`、`obj/components/on_device_translation/` | **0** |
| `obj/printing/`＋`obj/components/printing/` | 15（upstream 設計如此：`enable_printing=false` 時它自己留 `printing/backend/print_backend_dummy.cc` 加 mojom 介面層，不是漏裁） |

---

## 10. 第二輪：`enable_on_device_translation=false` 的 assert 是這樣解掉的

上游的病根（158 實測）：`enable_on_device_translation` 的預設值是
`is_mac || is_win || is_linux || is_chromeos`（`components/on_device_translation/buildflags/features.gni:8`），
桌面三大平台恆真，所以上游在四個 BUILD.gn 檔的第一行直接寫 `assert(enable_on_device_translation)`
（`chrome/browser/on_device_translation/BUILD.gn:7`、`components/on_device_translation/BUILD.gn:7`、
`.../service/BUILD.gn:7`、`.../public/mojom/BUILD.gn:8`），另外还有 3 处引用忘了包 `if`。
全樹總共 17 处用 `if (enable_on_device_translation)` 保護，只有下面 4 处漏掉——補丁就是把這 4 处補齊，
**沒有動那四條 assert 本身**（flag 關掉時那四個檔根本不會被載入，assert 自然不會踩到）。

改成兩支補丁分擔（**分工理由見第 12 節：補丁之間不准碰同一個檔案**）：
`chrome/browser/accessibility/BUILD.gn` 與 `chrome/browser/accessibility/live_caption/BUILD.gn`
這兩檔 trim/0001 本來就在改（screen_ai 那些 `if`），所以它那兩個 GN 點**併進 trim/0001**
（檔案數仍是 26，只是這兩個檔的 hunk 變多）；剩下的 4 檔是
`patches/trim/0003-disable-on-device-translation.patch`：

| # | 檔案 | 改動 |
|---|---|---|
| 1 | `chrome/browser/accessibility/BUILD.gn`（**在 trim/0001 裡**） | 新增 `import("//components/on_device_translation/buildflags/features.gni")`；原本在 `if (!is_android)` 那塊 deps 裡無條件列出的 `//chrome/browser/on_device_translation`（原 :113）與 `//components/on_device_translation`（原 :117）拿出來，放進新的 `if (enable_on_device_translation) { deps += [...] }` |
| 2 | `chrome/browser/accessibility/live_caption/BUILD.gn`（**在 trim/0001 裡**） | 同上 import；`source_set("impl")` 的 deps 裡那兩條（原 :47、:52）包進 `if (enable_on_device_translation)`；`source_set("browser_tests")` 的 `//components/on_device_translation`（原 :141）也包。`//components/on_device_translation/buildflags`（那條是產生 `buildflags.h` 的目標，自己沒有 assert）保留無條件引用，C++ 才拿得到 BUILDFLAG 巨集 |
| 3 | `chrome/browser/ui/webui/on_device_translation_internals/BUILD.gn` | import ＋把 deps 裡的 `//components/on_device_translation`（原 :30）包進 `if (enable_on_device_translation)` |
| 4 | `chrome/browser_exposed_mojom_targets.gni` | import ＋把 `//components/on_device_translation/public/mojom:mojom`（原 :163）從無條件清單挪到檔尾新增的 `if (enable_on_device_translation) { ... += [...] }`（這份清單只餵 `//chrome/test/fuzzing/renderer_fuzzing`，但它是無條件引用，照樣會踩 assert） |
| 5 | `chrome/browser/accessibility/live_caption/live_translate_controller_factory.cc` | 標頭 6 行與「有 installer 就建 on-device 派傳器」那段包 `#if BUILDFLAG(ENABLE_ON_DEVICE_TRANSLATION)`，`#else` 分支留空 ⇒ flag 關掉時 `on_device_dispatcher` 是 nullptr，即時字幕翻譯沒有本地翻譯來源（本來也沒有 Google 金鑰） |
| 6 | `chrome/browser/ui/webui/on_device_translation_internals/on_device_translation_internals_page_handler_impl.cc` | 整份實作分成兩個分支：`#if` 是上游原樣；`#else` 給一個「只有頁面、沒有資料」的存根（構造時直接回空清單、安裝/移除是 no-op）。理由：`ComponentManager` 的符號在 flag 關掉時根本不存在，這樣 `chrome://on-device-translation-internals` 也不會炸。 |

**反證（證明是這些改動在起作用，不是 flag 自己變了）**——在同一棵樹上只把
`live_caption/BUILD.gn` 那一處還原成上游的無條件引用（其它 3 處不動），跑 `gn gen`：

```
ERROR at //chrome/browser/on_device_translation/BUILD.gn:7:1: Assertion failed.
assert(enable_on_device_translation)
^-----
See //chrome/browser/accessibility/live_caption/BUILD.gn:46:5: which caused the file to be included.
    "//chrome/browser/on_device_translation",
 rc=1
```
（行號是 158 现在的位置 48，前面表格寫的 47 是改動前第一處引用的行號。）
把那一處改回來：`Done. Made 35877 targets from 5012 files` rc=0。
⇒ 只要這 4 個 GN 點少任何一處，`enable_on_device_translation=false` 就還是關不掉。

---

## 11. 第二輪：`patches/privacy/0001-local-privacy-and-ai-surface-trims.patch`（16 檔）

舊 `0004-aetherium-branding-round2.patch` 其實是一支「品牌改名＋隱私／UI 裁剪」混在一起的
mega-patch。品牌那半在第 9 節重做了；這 16 檔是另外那半，本輪搬進來，因為**不搬的話今天重編
就會把用戶已經用了几個星期的行為弄丟**（不是新功能，是既有行為的回歸）。
實測：舊補丁這 18 檔裡 **17 檔在 158 的樹上可以零衝突套用**，只有
`chrome/browser/history/top_sites_factory.cc` 因為上游把外層條件從 `#if !BUILDFLAG(IS_ANDROID)`
改成 `#if !BUILDFLAG(IS_ANDROID) || BUILDFLAG(ENABLE_EXTENSIONS_CORE)` 而位移，已手動重對。
內容清單：

| 檔案 | 白話：改完會怎樣 |
|---|---|
| `chrome/browser/component_updater/registration.cc` | 不再向 Google 元件更新器註冊：檔案類型策略、CrowdDeny、DictationConnector、Zxcvbn 密碼強度資料、WasmTts 語音、Screen AI 那幾顆元件（背景下載就斷了）。TranslateKit 那塊本輪**不用**舊補丁的 `#if 0` 髒活，改回上游的 `#if BUILDFLAG(ENABLE_ON_DEVICE_TRANSLATION)`——第 10 節之後 flag 真的會關，那段自然編譯掉 |
| `chrome/browser/history/top_sites_factory.cc` | 新設定檔的「最常瀏覽網站」區不再預置那顆 Chrome Web Store 磁貼（用戶自己加的捷徑、實際瀏覽記錄不受影響） |
| `chrome/browser/spellchecker/spellcheck_factory.cc` | 拼字檢查預設關（設定頁的開關還在） |
| `chrome/browser/ui/startup/infobar_utils.cc` | 兩條橫幅不再彈：「沒有 Google API 金鑰」與「恢復上次工作階段」的促銷橫幅 |
| `chrome/browser/ui/webui/new_tab_page/action_chips/action_chips_generator.cc` | 新分頁那一整排 AI 磁貼（AI 模式／生成圖片／深度搜尋／畫布／腦力激盪／學習／寫作／加圖）全部清空。註解裡記了為什麼不能只關 feature：選單是三選一，關掉 scaled 反而掉進 old 那組（正是深度搜尋＋生成圖片） |
| `.../new_tab_page/composebox/variations/composebox_fieldtrial.cc` | 新分頁那個「問問 Google」compose 框（含框內 AI 按鈕）預設關 |
| `.../new_tab_page/new_tab_page_ui.cc` | 新分頁的促銷氣泡不回傳 promo（走 kDisabledBrowserPromo） |
| `chrome/browser/ui/webui/settings/settings_ui.cc` | 設定頁「AI 創新功能」整頁不顯示（`showAiPage` 鎖 false，Glic 狀態訂閱那行也一起封死） |
| `chrome/browser/resources/settings/settings_menu/{settings_menu.html,settings_menu.ts,settings_menu.css}` | 左側選單拿掉「您與 Google」與「自動填入和密碼」兩項；「關於 aetherium」改用 `chrome://theme/current-channel-logo` 的品牌圖（跟全小寫 aetherium logo 一致） |
| `chrome/browser/resources/new_tab_page/app.ts` | 新分頁那個「自訂 aetherium」膠囊一律收成鉛筆圖示，不顯示文字（規則 37：太長會被截斷） |
| `ui/webui/resources/cr_components/most_visited/most_visited.ts` | 不提供「新增捷徑」那顆空磁貼 |
| `components/autofill/core/common/autofill_prefs.cc` | 地址／信用卡的 Autofill 預設關（同步偏好也是關） |
| `components/omnibox/browser/omnibox_prefs.cc` | 網址列「AI 模式」按鈕預設關 |
| `components/safe_browsing/core/browser/db/sb_protocol_manager_util.cc` | Safe Browsing v4/v5 的伺服器前綴指向 `https://127.0.0.1/safebrowsing-disabled/…`——實測這臺機器的防護交給 AP 上的 AdGuardHome＋uBlock，這條是把「瀏覽記錄送到 Google」的通道整個閘死 |

舊補丁裡另外兩個 `components/vector_icons/aetherium/{product,product_refresh}.icon` **沒有搬**：
158 的 settings_menu 用的是 `chrome://theme/current-channel-logo`，這兩檔在樹裡沒有任何引用者
（`grep -rn 'aetherium/product' --include=BUILD.gn --include=*.cc .` 實測 0 命中），留下來就是死檔。

---

## 12. 本輪踩到必須記錄的坑

1. **`rm -rf out/Aetherium` 會把 args.gn 一起清掉**，而且 `gn gen` 不報錯——它自己生一份
   只寫 `# Set build arguments here.` 的預設檔，目標數還從 35,877 變 36,876，看不出來就當
   「裁剪生效了」。教訓：權威 args.gn 一定要進倉庫（本輪放到 `config/args.gn`，建置目錄那份
   只是它的複製品），CI 也一律從那份複製。
2. **兩支補丁碰同一個檔案會讓 `apply-patches.sh` 的冪等判斷誤報「衝突」**。
   本輪 trim/0003 剛做出來時跟 trim/0001 都碰 `chrome/browser/accessibility/BUILD.gn` 與
   `.../live_caption/BUILD.gn`（而且改的是同一個 deps 清單），`git apply --reverse --check`
   就看不到「已在樹上」了，第二輪跑必然紅。試過 `-U0/-U1/-U2`（放寬 context 行數）無效，
   `--reverse --check --3way` 會逐檔印「已完全套用」但回傳碼仍是 1，不能用。
   定案：**補丁之間一律不许碰同一個檔案**（本輪把 trim/0003 裡那兩檔的改動併回 trim/0001，
   trim/0003 只留 4 檔）。校驗命令：

   ```bash
   python3 - <<'PY'
   import glob,os,gzip
   def f(p):
       d=gzip.open(p,'rt',errors='replace') if p.endswith('.gz') else open(p,encoding='utf-8',errors='replace')
       return {l.split(' a/')[1].split(' b/')[0].strip() for l in d if l.startswith('diff --git a/')}
   s={p:f(p) for p in sorted(glob.glob('patches/**/*.patch*',recursive=True))}
   k=list(s); bad=[(a,b) for i,a in enumerate(k) for b in k[i+1:] if s[a]&s[b]]
   print('補丁',len(k),'支；重疊對:',bad)
   PY
   ```
   目前實測：14 支、重疊 0。

---

## 13. CI 改寫（這是「盯 CI 到全綠」的實際內容）

實測背景：倉庫是 **PUBLIC**，所以 GitHub Actions 對它是免費額度（用戶已明確：「我沒充錢，
自動構建就是免費、超時就停」），推檔不花用戶錢。`gh repo view --json visibility` 回 `PUBLIC`。

历史（`gh run list`）：`Build Linux`／`Build Android` **從未綠過**。最近一輪（2026-10-15，
run 38718614178／38718614222）16-17 分鐘失敗，失敗步驟用 `gh run view --json jobs` 查是同一個：
**`Configure GN build`**；再往前 2026-08 那幾輪是 `6h00m` 被 cancelled（撞 GitHub Actions
單 job 6 小時上限）。根因兩條：
1. workflow 的 `gn gen --args` 用一串 157/158 已不存在的 arg 名（`enable_vr`、`enable_plugins`、
   `enable_nacl`、`enable_media_router`、`enable_feed`、`enable_reading_list`、
   `build_with_tflite_lib`、`safe_browsing_mode=0`、`enable_swiftshader`），GN 對已存在的名字
   才吃，其餘會報 `Invalid configuration value`；
2. workflow 根本沒套 `patches/`（它用 perl 大范围擦 `assert(enable_vr…)` ＋ `printf` 生一堆空
   `group()` 的老辦法），跟本倉庫的補丁系列互不相認。

本輪改成（兩個 yml 都重寫）：
- **push／PR 路徑**：抓 upstream → `gclient sync --shallow --no-history --nohooks` → `runhooks`
  → `install-build-deps.sh` → **`scripts/apply-patches.sh`（跟本機同一個入口）** →
  複製 `config/args.gn` 進 `out/Aetherium` 後 `gn gen` → 品牌化驗收 ＋ 裁剪驗收。
  這條路徑不吃 CPU，幾十分鐘内結束，红就是「補丁跟上游衝突／arg 名壞了／assert 沒解」，
  有用且穩定。
- **完整編譯**：改成只有 `workflow_dispatch` 且勾 `full_build` 才跑（`autoninja chrome`）。
  理由就是上面那條 6h 上限＋免費 runner 只有 2 核 7GB，Chromium 整包物理上編不完；
  把它留在 push 路上等於「每次改動都必然不綠」，那樣「盯到全綠」這件事就没有意義了。
  想真的編就去 Actions 頁手動觸發（會跑到被砍，跟 2026-08 一樣，但那時是你自願要看的）。
- **CI 釘上游基準**：新增 `patches/UPSTREAM_BASE`（目前 = `6ac1da15572a0e79814c92a86b8430805f9def04`，
  也就是本機這棵樹／補丁生成時的 upstream commit，158.0.8118.0）。兩個 workflow 在 `fetch` 之後、
  `gclient sync` 之前用 `git fetch --depth=1 origin <sha>` 釘過去，抓不到就退回 HEAD 並發
  `::warning::`。理由是 `.grd/.xtb` 這 849 個檔上游幾乎天天在動，不釘的話每次 push 都會紅在
  「補丁與上游衝突」——那是漂移訊號，不該混進「我這次改壞了」的閘門。要看漂移就手動觸發時
  勾 `check_against_head`（那個 input 就是為此存在）。**重新產生補丁之後記得一起更新這檔。**
- 樹内 PGO profile 不存在時自動把 `chrome_pgo_phase` 改成 0（CI 的 gclient 不一定抓 324MB profile，
  不這樣會紅在環境差異上，而不是紅在裁剪上）。
- 兩個 yml 都保留 ccache 機制，但掛在 dispatch 路徑。
- `config/args.gn` 新增（權威版），建置目錄那份是複製品；本檔第 2 節的 44 條逐條核對結論仍然成立，
  本輪多了 `enable_on_device_translation` 共 45 條。

---

## 14. 還剩什麼（依重要程度排）

1. **沒有編譯**。本輪按指令只做 `gn gen`／`gn desc`／`ninja -t` 層級的輕量驗證（本機 14GB RAM
   ＋規則 27/57 禁止吃滿硬體，用戶還在用瀏覽器）。所以：
   - 品牌改名的「執行期最終外觀」（選單文字、關於頁、工作列標題、音量Mixerk 那一列）
     是**由源碼＋建置圖推證**，還沒有跑起來看過；
   - `patches/privacy/0001` 與 `trim/0003` 的 C++ 改動有沒有編譯錯誤，只有 CI 的完整編譯能判，
     而那一條按上面的原因只在手動觸發時跑。下次真正編譯前，建議先 `ninja -C out/Aetherium` 
     只打 `//chrome/common:channel_info //chrome/common:constants 
     //chrome/browser/accessibility/live_caption:impl //chrome/browser/ui/webui/on_device_translation_internals`
     這幾個小目標（記憶體友善），先抓掉可能的語法錯。
   - `chrome/browser/resources/settings/…`、`most_visited.ts`、`app.ts` 那幾檔是 TypeScript/WebUI，
     要 `optimize_webui` 跑過才看得見問題，本機一樣沒跑。
2. **PKGBUILD 有三項要跟上**（`~/Downloads/pkgbuilds/aetherium/PKGBUILD`，那是用戶的打包檔，本輪沒動）：
   - 第 140 行 `StartupWMClass=aetherium.desktop` 是錯的。WM_CLASS 由 `GetDesktopName()` 去掉
     `.desktop` 之後得來（res_name=`aetherium`、res_class=`Aetherium`，因為
     `shell_integration_linux.cc:537` 會把首字母大寫），所以這裡該寫 `StartupWMClass=Aetherium`
     （i3 的 `window::class` 比對 res_class，比 res_name 穩）。不改的話工作列/跳窗清單會重複開第二個圖標。
   - `depends=(… libcups …)` 與 optdepends 裡打印/PDF 那幾項可以清掉（`use_cups=false`＋打印全關，
     產物不再鏈 libcups）。
   - `.desktop` 的 `MimeType=` 裡 `application/pdf` 已沒有對應 handler，該拿掉。
   - 另外 `_srcout` 的預設還是 `out/Release`，而正式建置目錄現在是 `out/Aetherium`
     （實測 `/opt/chromium-src/src/out/` 下只有 `Aetherium/`），不改就得每次帶 `AETHERIUM_OUT=`。
3. **`enable_remoting = false` 白話說明（用戶問「這又是啥」）**：那是 **Chrome Remote Desktop**
   ——「讓另一臺機器上的 Google 帳號遠端看到、操作這臺電腦」的主機端（`//remoting` 那一坨：
   中繼連線、畫面編解碼、host 程式、`remoting_host` 服務）。它跟「把畫面投放到 Chromecast」
   不同（那個叫 DIAL/mDNS，我們用 `enable_service_discovery=false`＋`enable_mdns=false` 關掉了）。
   關掉會少的只有：裝不起 Chrome Remote Desktop 的「從這裡遠端控制這臺機器」功能，
   以及瀏覽器裡跟它相關的那幾個 policy／mojo 介面。這臺機器不用它，所以保留 false。
   實測效果（`ninja -t graph chrome` 口徑）：`obj/remoting/` **0 檔**，整個子系统不进產物。
   要反悔就把 `config/args.gn` 那一行刪掉（可回退，只影響 `//remoting` 那坨）。
4. **舊 `0003-backup-two-tone.patch`（18 檔）沒搬**：它的內容是把 Arcaea 雙色調圖直接蓋到
   `chrome/app/theme/chromium/**`（上游的 chromium 目錄）上。我們走的是
   `branding_path_component="aetherium"` ⇒ 讀的是 `theme/aetherium/**`，蓋 `theme/chromium/**` 
   是多餘的，而且每次 sync 都會跟上游改圖衝突。留著當備用，不需要進補丁系列。
5. **本機残留**（下次接手可直接清）：`/opt/chromium-src/src/out/Aetherium/`（build.ninja、
   toolchain.ninja、args.gn、gen/ 都還在，留著下次直接編譯用）；
   `/opt/chromium-src/.aetherium-backup/prestate-2026-10-23.patch`（2.9MB，本輪開始前的工作區快照，
   現在所有内容都能由 `patches/` 重現，可以刪）；`git stash list` 裡本輪建的 3 個 stash
   （`10 補丁狀態`／`13 補丁狀態`／`14 補丁狀態`）都是補丁可重現的中間態，確認無用後 `git stash drop` 清掉。
6. **用戶 i3 設定不需要改**：實測 `~/.config/i3/config.d/autostart.conf` 裡「chromium」只出現在註解，
   沒有視窗規則或啟動命令綁舊名字，所以改成 `aetherium.desktop`／`Aetherium` 不會打斷他的工作流。


## 15. 下一次接手的入口命令（全部唯讀或可重覆執行；本輪第二版）

```bash
cat /opt/chromium-src/src/chrome/VERSION                   # 158.0.8118.0
git -C /opt/chromium-src/src status --porcelain | wc -l     # 14 支補丁全套＝995 個檔案（858 品牌＋117 原裁剪＋16 隱私＋4 ODT）
cd /opt/chromium-src/src
~/Downloads/aetherium/scripts/apply-patches.sh --dry-run     # 只報狀態，不動樹（冪等）
~/Downloads/aetherium/scripts/apply-patches.sh               # 從乾淨樹一次套完 14 支
./buildtools/linux64/gn gen out/Aetherium                    # 本輪實測 rc=0、Made 35877 targets
./buildtools/linux64/gn args --list --short out/Aetherium | wc -l   # 真 arg 總數 1260
./buildtools/linux64/gn ls out/Aetherium | wc -l             # 35877（含 test 目標，別拿它判裁剪）
grep -c '^build ' out/Aetherium/build.ninja                  # 51990
ninja -C out/Aetherium -t graph chrome | grep -c 'obj/remoting/'   # 0（判裁剪要看這個口徑）
grep -F -c 'fsanitize=cfi' out/Aetherium/toolchain.ninja     # 87
# 品牌化現場證據（本輪跑過、都過）
grep -n 'PRODUCT_FULLNAME=aetherium' chrome/app/theme/aetherium/BRANDING
grep -n 'return "aetherium.desktop";' chrome/common/channel_info_posix.cc
grep -n 'data_dir_basename = "aetherium";' chrome/common/chrome_paths_linux.cc
( cd out/Aetherium && ninja -t commands gen/chrome/common/chrome_version.h | tail -1 | sh )
grep -n 'PRODUCT_FULLNAME_STRING' out/Aetherium/gen/chrome/common/chrome_version.h
# 用戶把 aetherium 開起來之後才能驗的那條
head -c 80 /proc/$(pgrep -x aetherium | head -1)/environ
```

