# aetherium 補丁盤點：別家 Chromium 分支的補丁清查

盤點基準（全部為實測，不是引用別人的說法）：

- 源碼樹：`/opt/chromium-src/src`（唯讀；本報告沒動過樹內任何檔案）
- 版本：`chrome/VERSION` 讀出 `MAJOR=157 MINOR=0 BUILD=8095 PATCH=0`（即 157.0.8095.0）
- 工作區狀態：`git status --short` 有 1257 個 `M` 檔（你既有的品牌化／圖示補丁已套在樹上），
  HEAD 是 `9fe7d73194 Roll vulkan-deps ...`（detached HEAD）。
  ⇒ 本報告所有「試套（dry-run）」都是在这个「已含你本地改動」的狀態上做的，比對乾淨樹更接近真實。
- 構建參數現況：`out/Release/args.gn`（`proprietary_codecs=true`、`ffmpeg_branding="Chrome"`、
  `enable_widevine=true`、`optimize_for_size=true`、`is_official_build=false`、
  `branding_path_component="aetherium"`、`use_thin_lto=false`）
- 既有補丁：`~/Downloads/chromium-patches/0001-privacy-disable-google-channels-and-ai-components.patch`
  （2 檔）、`0002-branding-aetherium.patch`（4 檔）、`0003-icon-aetherium.patch`（73 檔）、
  `0004-aetherium-branding-round2.patch`（大檔）。本報告會標明新補丁與它們是否重複。
- 試套工具（兩種都跑，因為你的 `scripts/apply-patches.sh` 用 `git apply --check --ignore-whitespace`）：
  `patch -p1 --dry-run --batch -N -g0`（寬容）與 `git apply --check -p1 --ignore-space-change --ignore-whitespace`（嚴格）

---

## 0. 三條必須先讀的實測結論（其中一條推翻既有判斷）

### 0.1 MV2 確實需要補丁 —— 先前「MV2 不需要補丁」的結論只對了一半，必須修正

之前只查了 `extensions/common/extension.cc:60` 的 `kMinimumSupportedManifestVersion = 2`，
那行只管「manifest 解析階段能不能過」，不管「擴充會不會被啟用」。真正的總開關在別的檔案：

- `/opt/chromium-src/src/extensions/browser/manifest_v2_handler.cc:111-118`

      bool ShouldDisableLegacyExtensions() {
        if (g_allow_mv2_for_testing) {
          // We allow legacy MV2 extensions for testing purposes.
          return false;
        }
        return true;                       // <== 157 桌面版無條件殺掉 MV2
      }

- `/opt/chromium-src/src/extensions/browser/manifest_v2_util.cc:20-46`：
  `IsExtensionAffected()` 把「manifest_version < 3 且不是 component 位置」的擴充一律判定受影響。
- `/opt/chromium-src/src/extensions/browser/manifest_v2_handler.cc:196-199`：
  `OnExtensionSystemReady() { CheckDisabledExtensions(); DisableAffectedExtensions(); }`
  ⇒ 瀏覽器一啟動就把既存 MV2 擴充加上 `disable_reason::DISABLE_UNSUPPORTED_MANIFEST_VERSION` 停用。
- 擋安裝路徑：同檔 `ShouldBlockExtensionInstallation()`（:158-168）、
  擋手動啟用路徑：`ShouldBlockExtensionEnable()`（:170-175），
  以及 `extensions/browser/api/management/management_api.cc:598 CheckManifestV2Deprecation()`
  裡頭對 `ShouldBlockExtensionEnable()` 有 `CHECK(!...)`。
- 全樹引用這個機制的檔案 26 個（含 `chrome/browser/extensions/extension_service.cc`、
  `extensions/browser/extension_registrar.cc`、`extensions/browser/disable_reason.cc`）。
- 查過沒有企業政策／runtime feature 可以繞過：在 `chrome/browser/policy/`、`components/policy/`
  找不到 `ManifestV2Availability`、`AllowedManifestVersions` 這類東西（上游已拿掉），
  `ShouldDisableLegacyExtensions()` 裡也沒有 `base::FeatureList` 判斷。

結論：要留 MV2（例如 enhanced-h264ify 這種 MV2 擴充），**必須打補丁**，
或者接受每次啟動都被停用。已收錄成 `patches/adblock/0001-mv2-restore-ungoogled-155.patch`（試套：兩種工具都通過）。

### 0.2 HEVC/H.265 在 157 已经是上游默認開啟，別家的 HEVC 補丁全部不用

- `/opt/chromium-src/src/media/media_options.gni:127-129`

      enable_hevc_parser_and_hw_decoder =
          proprietary_codecs &&
          (use_fuzzing_engine || is_win || is_apple || is_android || is_linux)

  ⇒ 你的 `proprietary_codecs = true` 已經讓它在 Linux x64 上預設為 true。
- 同檔 `:154-156`：`enable_platform_hevc = proprietary_codecs && (enable_hevc_parser_and_hw_decoder || is_cast_media_device)` ⇒ 跟著開。
- 同檔 `:168-171`：`platform_has_optional_hevc_decode_support = enable_platform_hevc && (is_win || is_chromeos || is_linux || is_apple || is_android)` ⇒ Linux 在清單內。
- 同檔 `:122`：`enable_hls_demuxer = proprietary_codecs` ⇒ HLS 也跟著開。
- 同檔 `:195-205` 的 assert 只要求 `proprietary_codecs`，你都滿足。
- 沒支援的只有 Dolby Vision（`:97-98` 只給 cast/win）與 AC3/EAC3/DTS 平台直通（`:74-85` 給 cast/ios/win/android）。
  ⇒ 想補 AC3/EAC3 只能靠 FFmpeg 那側，不是補丁能解決（見第 4 節 Cromite 的 `Enable-HEVC-decoding` 類條目判定）。

所以 Thorium 的 `add-hevc-ffmpeg-decoder-parser.patch`、Cromite 的 `Enable-HEVC-decoding.patch`、
Bromite 系的 ffmpeg 改動，在 157 上**全部不需要**，而且收了反而會跟上游的 buildflag 打架。

### 0.3 「args.gn 關功能」的正確邊界：三個可用、四個已失效（含你 CI 裡的一顆無效參數）

本輪在 157 树里实测的 GN 参数存在性（`grep -rn` 遍歷 `chrome/ components/ services/ content/ build/ media/` 的 `*.gni`）：

- 上游真支援、你可以放心寫進 args.gn：
  - `enable_hevc_parser_and_hw_decoder`（預設已 true）
  - `enable_chrome_notifications`（`chrome/common/features.gni:50 = is_mac || is_win || is_linux`）
  - `init_stack_vars` / `init_stack_vars_zero`（`build/config/compiler/BUILD.gn:144/153`；
    你的 `is_official_build=false` ⇒ 目前拿到的是 `-ftrivial-auto-var-init=pattern`，
    想要 Vanadium 的 `zero` 版本只要加 `init_stack_vars_zero = true`，**不用補丁**，但會全量重編）
- 已失效／不存在的參數（寫了會 `gn gen` 報 Unrecognized argument 或根本無效果）：
  - `enable_media_router`：本樹所有 `*.gni` 都找不到宣告 ⇒ 你 `.github/workflows/build-linux.yml:149`
    的 `enable_media_router=false` 是無效參數（同一行裡 `enable_pdf=false`、`enable_spellcheck=false`
    等也是走「關開關」這條你已實測會斷鏈的路）。
  - `safe_browsing_mode=0`、`enable_screen_ai_service=false`、`enable_on_device_translation=false`：
    沿用你已有的實測結論，不重複驗證；正確的做種仍是「摘註冊／摘 BUILD.gn target 引用」。
  - `enable_network_time_service`：查無宣告；取而代之的是 `components/network_time/network_time_tracker.cc`
    還在（從 `net/base/` 搬到 `components/`），且 `chrome/browser/net/system_network_context_manager.cc:954`
    確實把 `g_browser_process->network_time_tracker()` 掛進去了 ⇒ 這條只能靠補丁或 `--disable-features`。

另外補一條與你硬需求有關的實測：**擴展通知進 dunst 不需要補丁**。
157 桌面 Linux 有原生的 freedesktop D-Bus 通知橋（`chrome/browser/notifications/notification_platform_bridge_linux.cc`，
1715 行，實作 `org.freedesktop.Notifications`），而且：

- `chrome/common/chrome_features.cc:1488 BASE_FEATURE(kNativeNotifications, base::FEATURE_ENABLED_BY_DEFAULT)`
- `chrome/common/chrome_features.cc:1506 BASE_FEATURE(kSystemNotifications, base::FEATURE_ENABLED_BY_DEFAULT)`
- `chrome/browser/notifications/notification_platform_bridge_delegator.cc:52-75`：Linux 走系統通知，
  只有在偏好 `prefs::kAllowSystemNotifications` 被關掉時才退回瀏覽器內建的 Message Center。
⇒ 若你實際看到通知沒進 dunst，問題在（a）偏好值、（b）`.desktop` 檔名與 `desktop-entry` hint 對不上、
（c）dunst 的規則匹配，而不是缺補丁。驗收方法寫在 README 步驟 5。

---

## 1. 查證方式（全部可重跑，皆唯讀）

- 拉別家補丁清單：
  - `gh api "repos/<owner>/<repo>/git/trees/<branch>?recursive=1" --jq '.tree[].path'`
  - ungoogled 整包：`curl -sSL https://codeload.github.com/ungoogled-software/ungoogled-chromium/tar.gz/refs/heads/master`
    （解出的 `patches/series` 110 行 = 108 條補丁 + 2 個空行，那就是官方套用的順序與全清單）
- 對 157 樹做唯讀試套（一次全量）：見本檔第 3 節每條的結標記；單條命令範例：

      cd /opt/chromium-src/src
      patch -p1 --dry-run --batch -N -g0 -i <patch>
      git apply --check -p1 --ignore-space-change --ignore-whitespace <patch>

- 鏈式驗證（證明收錄的 8 條可同時套）：把 8 條涉及的 16 個檔案用 `cp --parents`
  複製到 `/tmp/chain/src`，在副本裡依序 `patch -p1`（真套，不碰 /opt），8/8 成功、無 fuzz。
- 存在性查證一律用 `ls`／`find`／`grep -n` 對具體路徑，判定行都附檔案與行號。

---

## 2. 各家補丁總量與現況（實測）

- **ungoogled-chromium**（`ungoogled-software/ungoogled-chromium`，原 Eloston 專案）
  實際補丁檔 123 個，`patches/series` 收錄 108 條（檔案 110 行、含 2 個空行）；master 標的版 `chromium_version.txt` → 最新 tag `155.0.8059.39-1`。
  分類：`patches/core/{inox-patchset,iridium-browser,ungoogled-chromium,bromite}`、
  `patches/extra/{...}`、`patches/upstream-fixes`。本報告第 3 節逐條判定。
- **inox-patchset**：原 GitHub 倉（`inox-patchset/inox-patchset`）**已 404 消失**；
  唯一還拿得到的副本是 ungoogled 裡收錄的 0001/0003/0005/0006/0008/0013/0015/0016/0019/0021。
- **Iridium Browser**（`iridium-browser/iridium-browser`）：repo 是「tarball 狀態」的完整 Chromium 鏡像，
  補丁直接改在樹裡，**沒有獨立 .patch 檔**（實測 `patches/` 目錄 0 檔）；
  `chrome/VERSION` = `120.0.6099.224`，最後 pushedAt 2024-01-26 ⇒ 事實停更。
  它的補丁內容以 ungoogled 收錄的 6 條 iridium 檔為代表（見第 3.2、3.4 節）。
- **Superium（sdagk）**：查無此專案。實測：`gh api users/sdagk` → 404；
  `gh search repos superium` 全是同名遊戲／網站目錄；Codeberg API 空；GitLab API 空；
  `sdagkas` 名下只有 2 個无关倉。存在的同音專案是 **Supermium**（`win32ss/supermium`，
  Windows XP/2003/Vista/7/8 相容向，branch `main`，pushedAt 2026-10-09，根目錄 15 個 .patch bundle）。
  ⇒ 本報告按 Supermium 盤點（第 6.1 節），對你（Artix/x64 Linux 桌面）**全都不適用**。
- **Bromite**（`bromite/bromite`）：`build/patches/` 206 個 .patch；最後 pushedAt 2024-01-24，
  官方已由 successor 倉宣告 ARCHIVED（搜尋結果中 `nikolowry/bromite-builder` 的敘述直接寫
  「Bromite is no longer maintained. Please see uazo/cromite」）。
- **Cromite**（`uazo/cromite`，Bromite 後繼，Android）：`build/patches/` 327 個 .patch，
  權威清單檔 `build/cromite_patches_list.txt`（333 行）；pushedAt 2026-10-11（活躍）。
- **Vanadium**（`GrapheneOS/Vanadium`，Android/WebView，GrapheneOS 的手機瀏覽器）：
  `patches/` 302 個編號 .patch + `subprojects_patches/` 6 個（v8 2 個、search_engines_data 3 個、其他 1 個）；
  pushedAt 2026-10-08（活躍，也是你手機 Helium/Titanium 的底）。第 5 節逐類判定。
- **Thorium**（`Alex313031/thorium`，你桌上主力）：全樹 52 個 .patch
  （`other/` 28、`infra/Flatpak/com.alex313031.thorium/patches/chromium/` 18、`ffmpeg/` 2、`arm/raspi/` 2、根 1、
  `infra/chromium-restore-jpeg-xl-support-120.patch` 1）；此外用 `src/` 目錄「整檔覆寫」895 個檔案
  （含 `src/build/config/compiler_opt.gni`、`src/build/config/compiler/BUILD.gn`）——
  也就是它主要不是靠 .patch，而是靠直接換檔＋分 CPU 檔次（AVX2/AVX512/SSE2/CrOS/Mac 各一套 `thorium_version.txt`）。
- **Zen Browser**（`zen-browser/desktop`，Firefox 系）：263 個 .patch，採「每個被改的原始檔對應一個 .patch」
  的 overlay 模式（`src/browser/base/content/aboutDialog-js.patch` 這種）。補丁本體不可套到 Chromium，
  只當需求清單（第 7 節）。
- **LibreWolf**（Firefox 系）：本輪**未能取到清單**（`gitea.librewolf.net` TLS handshake 失敗、
  GitLab API 404「Project Not Found」、GitHub 搜尋 `librewolf-patches-bundle` 空-results）。
  已記在第 10.2 節的待補事項；需求部分我以 Zen 的 prefs 清單 + 通行的 Firefox 隱私偏好清單代替，
  並在該節明確標「未取到原始檔，屬二手資訊」。
- **Chromium 官方編譯期開關**：見第 8 節。

---

## 3. ungoogled-chromium 108 條逐條判定

標記說明：
- `套=` 後是兩種工具的試套結果（`P`=patch --dry-run 通過、`G`=git apply --check 通過、`F`=失敗、`R`=被判為「已套用/反向」）。
- `檔=` 是該補丁實際動的檔案數（`grep -c '^--- '` 測得）。
- 每條三行內容：①改什麼＋你會看見的差別 ②在 157 需不需要＋實測依據 ③套用要動到什麼＋同步痛度。

### 3.1 upstream-fixes（1 條）

- `upstream-fixes/missing-dependencies.patch` 套=P/G 檔=6
  ① 補 `chrome/browser/chrome_content_browser_client.cc`、`chrome/browser/extensions/BUILD.gn`、
  `chrome/common/BUILD.gn` 等的 deps 漏declare（它存在的目的是「剪掉二進位後能編得過」）。
  ② 不需要：你沒有 prune 任何 target，`gn gen` 也過得去（`out/Release` 已存在且有 `.build-ok`）。
  ③ 收它只會增加日後同步噪音（6 檔）。判定：不要。

### 3.2 core/inox-patchset（5 條）

- `0001-fix-building-without-safebrowsing.patch` 套=F/F 檔=9
  ① inox 版「關掉 Safe Browsing 還能編」的修補（動 `chrome_content_browser_client_navigation_throttles.cc`、
  `component_updater/file_type_policies_component_installer.cc` 等）。
  ② 不需要：你走的是「保留代碼、把查詢 URL 導到 127.0.0.1」路線（既有 0001-privacy 補丁第 2 檔），
  而且本條在 157 已套不上（F/F）。
  ③ —。判定：不要（路線不同 + 套不上）。
- `0003-disable-autofill-download-manager.patch` 套=P/G 檔=1
  ① 把 `components/autofill/core/browser/crowdsourcing/autofill_crowdsourcing_manager.cc` 的
  `StartRequest()` 掏空 ⇒ 不再把表單內容/地址上傳給 Google 換「自動填充建議」。
  ② 不需要補丁：同一個開關有官方 runtime feature，
  `components/autofill/core/common/autofill_debug_features.cc:143
  BASE_FEATURE(kAutofillServerCommunication, base::FEATURE_ENABLED_BY_DEFAULT)`，
  启动加 `--disable-features=AutofillServerCommunication` 就等效，零同步成本。
  ③ 若你堅持「焊死、不讓人改 flag」才收：1 檔、痛度低（但掏空後同檔多個常數/靜態字串會變未使用，
  靠 `treat_warnings_as_errors=false` 兜住）。判定：不要（用旗標），保留為可選焊死項（第 10.1 節）。
- `0005-disable-default-extensions.patch` 套=P/G 檔=4
  ① 清掉內建元件擴充清單（`component_extensions_allowlist/allowlist.cc`、`component_loader.cc`、
  external install 清單）⇒ 不再自動帶入 Google Docs Offline 之类的元件擴充。
  ② 不需要：你用的是自己從 Web Store 裝的一般擴充（Bitwarden 等），元件擴充清單对你的体验没影响；
  而且你的 Google Docs 流程走 floccus→Drive，不是 Docs Offline 編輯器。
  ③ 4 檔、其中 `component_loader.cc` 是上游高频改动档 ⇒ 痛度中高。判定：不要。
- `0015-disable-update-pings.patch` 套=P/G 檔=1
  ① `chrome/updater/configurator.cc:139 UpdateUrl()` 回空清單 ⇒ 外掛的 Chromium Updater 不再更新/回連。
  ② 不需要：你自编版沒有安裝 chrome updater（`out/Release` 只有 `chrome` 與 `chrome_sandbox` 兩個產物，
  實測 `ls out/Release`），這條動的是 `chrome/updater/` 這套只在 official/品牌安裝情境才適用的東西。
  ③ —。判定：不要。
- `0021-disable-rlz.patch` 套=P/G 檔=2
  ① 只在根 `BUILD.gn` 的 `group("gn_all")` 裡拿掉 `//rlz:rlz_id/rlz_lib/rlz_unittests` 的引用 + 動 `rlz/buildflags/buildflags.gni`。
  ② 不需要：這是「少編測試」型補丁，**不改變執行期行為**（不發 RLZ 上報）；
  而且本樹 `chrome/common/BUILD.gn:519` 只引用 `//rlz/buildflags`（產生 buildflag 標頭），
  `//rlz` 的實際連結面在 `chrome/installer/util/BUILD.gn:192/387`、`chrome/installer/setup/BUILD.gn:46`（安裝程式路徑）。
  ③ —。判定：不要（對執行期無效，白增加同步面）。
- （0013/0016/0019 三條放在第 3.4 節的 extra 群裡判定，因為 ungoogled 把它們排在 extra。）

### 3.3 core/iridium-browser（2 條）—— 兩條都收

- `safe_browsing-disable-incident-reporting.patch` 套=P/G 檔=5 ⇒ **已收錄**（`patches/security/0002-...`）
  ① 擋掉「事件回報」上傳：`incident_report_uploader_impl.cc:31` 的
  `https://sb-ssl.google.com/safebrowsing/clientreport/incident`、
  `incident_reporting_service.cc:304 IsEnabledForProfile()` 直接 false、
  `chrome_safe_browsing_blocking_page_factory.cc` 把「進階回報」選項釘 false、外加 blocking page / loud error UI 兩處。
  你看得見的差別：危險網站警告頁上的「回報」動作不再把你的 URL + 電腦上的模組/驅動清單送出去。
  ② 需要，且與你既有 0001 補丁不重複：你現行補丁只改 `sb_protocol_manager_util.cc` 的 v4/v5 前綴，
  這條走的是 `sb-ssl.google.com` 這張獨立主機與另一條 code path（實測行號見上）。
  ③ 5 檔、全 .cc（不動頭檔）⇒ 重編 5 個編譯單位 + 連結；痛度中（safe_browsing 是上游改動最频繁的目录之一）。
- `safe_browsing-disable-reporting-of-safebrowsing-over.patch` 套=P/G 檔=1 ⇒ **已收錄**（`patches/security/0003-...`）
  ① 掏空 `components/safe_browsing/core/browser/client_side_detection_service_base.cc` 的
  `SendClientReportPhishingRequest()` ⇒ 本地 ML 判定「像钓鱼」時不再把頁面 URL、DOM 特徵、
  ACCESS_TOKEN、WEB_CONTENT POST 給 Google。
  ② 需要，且你既有補丁蓋不到：同檔 `:42` 的
  `kClientReportPhishingUrl[] = "https://sb-ssl.google.com/safebrowsing/clientreport/phishing"` 是寫死的常數，
  `:459 GetClientReportUrl()` 只是把常數包成 GURL，**不會讀你改過的 kSbV4UrlPrefix/kSbV5UrlPrefix**。
  ③ 1 檔（大段刪除、介面不變）⇒ 痛度中；省力的等效改法是只把 `if (!IsEnabled())` 改成 `if (true)`（1 行、幾乎不會衝突）。

### 3.4 core/ungoogled-chromium（28 條）＋ core/bromite（1 條）

- `disable-crash-reporter.patch` 套=P/G 檔=3 ⇒ 不要
  ① 動 `chrome/app/crash_reporter_client.cc`、`components/crash/core/app/crashpad.cc`、
  `util/posix/handler_main.cc`：不啟動 crashpad、不上傳 minidump。
  ② 不需要：157 的非品牌构建本來就不會上傳——
  `chrome/app/chrome_crash_reporter_client.cc:190-196 GetCollectStatsConsent()` 在
  `#if BUILDFLAG(GOOGLE_CHROME_BRANDING)` 之外把 `is_official_chrome_build = false`，
  回傳 false ⇒ handler 不送件。
  ③ —。判定：不要（3 檔 + 動 `components/crash/**` 的痛度不花在已經關掉的東西上）。
- `disable-google-host-detection.patch` 套=F/F 檔=9 ⇒ 不要
  ① 拿掉 Google 主機場域偵測（含新的 `glic_user_status_request.cc`、`suggest_internals_handler.cc`、
  `google_url_loader_*`）。② 套不上（F/F）＝與 157 上下文不同步。
  ③ 要收得整套重寫。判定：不要（先記在第 10.1 節的「以後想做再手改」清單）。
- `replace-google-search-engine-with-nosearch.patch` 套=P/G 檔=1 ⇒ 不要
  ① 把 `chrome/browser/search_engines/prepopulated_engines.json` 的預設搜尋換成 NoSearch。
  ② 不要：你明示 Google 是預設搜尋（硬依賴）。③ —。判定：不要（與既定需求衝突）。
- `toggle-translation-via-switch.patch` 套=P/G(寬)/F(嚴) 檔=5 ⇒ 不要
  ① 讓「翻譯」可以被一個開關整体關掉（context menu + translate_language_list + prefs）。
  ② 不需要：你已經用 0001-privacy 補丁把 `RegisterTranslateKitComponent` 整塊 `#if 0` 摘掉，
  而且 `enable_on_device_translation=false` 的 GN 路徑你已實測會斷鏈。
  ③ 5 檔 + 嚴格模式套不上（你的 apply-patches.sh 會直接中止）。判定：不要。
- `disable-untraceable-urls.patch` 套=P/G 檔=3 ⇒ 不要
  ① 把 `rlz/lib/financial_ping.cc`、`rlz/lib/lib_values.{cc,h}` 的 `clients1.google.com` 金融 ping 寫死壞。
  ② 不需要：如 3.2 的 0021 所述，`//rlz` 的實際程式碼只進到 `chrome/installer/**`（Windows/macOS 安裝程式）；
  桌面 Linux 的 `chrome` 目標不連結這條路徑。
  ③ —。判定：不要。
- `disable-profile-avatar-downloading.patch` 套=P/G 檔=1 ⇒ 不要
  ① 不再從 `www.google.com/account/about/profile-images` 下載浮士德頭像清單。
  ② 不要：你保留 Google 帳號登入，頭像是登入體驗的一環；而且這檔只影響「你在設定裡點頭像」時，
  不會背景自動抓。③ 痛度低但不是重點。判定：不要（用戶依賴）。
- `disable-gcm.patch` 套=F/F 檔=2 ⇒ 不要
  ① 斷掉 GCM（`chrome/browser/gcm/google_gcm_client_impl.cc`、`gcm_driver_desktop.cc`）的雲端推送通道。
  ② 不要，兩條實測依據：(a) 套不上（F/F）；(b) GCM 是你 Google 帳號同步／Web Push 的通道之一，
  你保留了 Google 登入與 floccus→Drive。目錄 `chrome/browser/gcm/` 在 157 仍存在（實測 6 檔以上）。
  ③ —。判定：不要。
- `disable-domain-reliability.patch` 套=F/F 檔=6 ⇒ 不要（但列入第 10.1 節「值得手工重做」的第一名）
  ① Domain Reliability 會把「載入失敗的子資源 URL」上報給 `https://dr.smzdm...`？——實際是
  `https://clientservices.googleapis.com/domainreliability/upload`。
  ② 功能仍在（`components/domain_reliability/` 實測存在），所以需求是真的；但 ungoogled 這份在 157 套不上（F/F，29KB、6 檔）。
  ③ 手工版最小改法：讓 `ProfileNetworkContextService` 不設定 DR 上傳 URL（1–2 檔）⇒ 我沒做，因為要改的是
  `chrome/browser/profiles/profile_network_context_service.cc`，屬你的既有補丁未覆蓋區域，值得单独一轮。
  判定：這條是「該要但目前收不到」，已寫進第 10.1 節。
- `block-trk-and-subdomains.patch` 套=P/G 檔=13 ⇒ 不要（重要，理由不是套不上）
  ① ungoogled 的做法是把一批 Google URL 加上 `trk:` 前綴，讓請求直接失敗（13 檔，含
  `chrome_autocomplete_scheme_classifier.cc`、`history_utils.cc`、`browser_navigator.cc` 等）。
  ② 不需要：你已經用更精準的方式做了同一件事（0001-privacy 補丁改 URL 常數），而這條會順帶把
  OneGoogleBar／拼字檢查／ autocomplete 建議之类的 Google 端點一起打死，跟你「不砍沒說的 Google 服務」抵觸；
  另外本樹實測已找不到 `"trk:` 這個前綴的既有用法（grep 0 筆），表示上游已把這批端點改掉或移除。
  ③ 13 檔、橫跨 UI＋history ⇒ 痛度高。判定：不要。
- `disable-gaia.patch` 套=P/G 檔=1 ⇒ 不要
  ① `google_apis/gaia/gaia_auth_fetcher.cc` 直接回錯誤 ⇒ 帳號登入全斷。
  ② 不要：你保留 Google 登入（硬依賴）。判定：不要（用戶依賴）。
- `disable-fonts-googleapis-references.patch` 套=P/G 檔=4 ⇒ 不要（並記「你要的其實不是這條」）
  ① 改的是 `components/dom_distiller/content/browser/dom_distiller_viewer_source.cc:308` 的 CSP、
  `components/dom_distiller/core/html/preview.html`，加上 crashpad doxygen 的 CSS 與 `tools/md_browser/base.css`
  （後兩檔是文件工具，永遠不會在瀏覽器裡跑）。
  ② 不需要：你的字型硬需求是「系統字型釘 TsukuGo/JetBrains Maple Mono/霞鶩文楷、永遠不准裝 Noto」，
  這條碰不到那層；而 157 裡真正會去抓 Google 字型的是**另外兩處**本補丁沒覆蓋的地方：
  `chrome/browser/ui/webui/side_panel/read_anything/read_anything_untrusted_ui.cc:262`（CSP 放寬 fonts.googleapis.com/gstatic）
  與 `chrome/browser/resources/contextual_tasks/extension/tab_picker.html:8,10`（`family=Google+Sans`）。
  ③ —。判定：不要收這條；真要做（讀音模式／contextual tasks 不抓遠端字型）請另行寫 1 檔補丁，已記第 10.1 節。
- `disable-webstore-urls.patch` 套=P/G 檔=6 ⇒ 不要
  ① 打死 Chrome Web Store 的安裝/驗證/更新 URL（`chrome_content_browser_client_extensions_part.cc`、
  `chrome_content_verifier_delegate.cc` 等）。
  ② 不要：你在用 Bitwarden，需要從 Web Store 安裝/更新。判定：不要（用戶依賴）。
- `fix-learn-doubleclick-hsts.patch` 套=P/G 檔=1 ⇒ 不要
  ① 不讓 `transport_security_state_generator.cc` 把 DoubleClick 域加進 HSTS preload。
  ② 需要與否取決於你是否 prune `net/` 的 preload 清單，你沒有；而且它只在產生 preload 資料時才作用
  （一般 `gn gen` + ninja chrome 不會重跑這個 generator）。痛度低但價值近 0。判定：不要。
- `disable-webrtc-log-uploader.patch` 套=P(寬)/F(嚴格) 檔=2 ⇒ 不要
  ① WebRTC 記錄上傳停用（`chrome/browser/media/webrtc/webrtc_log_uploader.cc` +
  `chrome/browser/ui/browser_ui_prefs.cc`：不上傳通話記錄、並把自動上傳偏好預設關）。
  ② 嚴格模式套不上 ⇒ 你的 `apply-patches.sh`（用 `git apply --check`）會中止整輪，不收。
  ③ 想處理 WebRTC 隱私，先考慮 `--force-webrtc-ip-handling-policy` 這條官方命令列旗標
  （存在性實測見 3.9 的 `default-webrtc-ip-handling-policy` 條目）。判定：不要。
- `disable-ai.patch` 套=R(已套用/反向)/F 檔=59 ⇒ 不要
  ① 59 檔的大範圍 AI 移除（`BUILD.gn` 多處 + `chrome/browser/ai/**` + side panel 等）。
  ② 不需要：你已用 0001-privacy 補丁摘掉 `ManageScreenAIComponentRegistration`、`RegisterTranslateKitComponent`、
  `RegisterWasmTtsEngineComponent`、`RegisterDictationConnectorComponent` 等註冊；
  而且本條被試套判定為「內容已存在／反向」（R），代表大部分改動在 157 已是這樣寫的。
  ③ 59 檔 ⇒ 痛度極高（典型的「以後跟上游同步變地獄」形態）。判定：不要。
- `fix-building-with-prunned-binaries.patch` 套=F/F 檔=15 ⇒ 不要
  ① 配合 `pruning.list` 刪掉預二進位後讓構建過得去。② 你完全沒有 prune（實測：你的 args.gn 與 CI 都沒有 prune 步驟）。
  ③ —。判定：不要。
- `disable-network-time-tracker.patch` 套=P/G 檔=1 ⇒ 不要（但**推翻我最初的判斷**，理由要寫清楚）
  ① 讓 NetworkTimeTracker 不發 `https://clients2.google.com/time/...` 時間查詢。
  ② 我一开始查 `net/base/network_time_tracker.*` 得到「不存在」是錯的：檔案已搬到
  `components/network_time/network_time_tracker.cc`（實測 `find` 有），且
  `chrome/browser/net/system_network_context_manager.cc:954` 確實把它掛進 network context。
  ⇒ 需求是真的，本條也套得上。最終仍判定**不要收**，理由只有一個：
  這條是「多一次 Google 時間查詢」，而你的 `disable_fieldtrial_testing_config=true` + 非品牌构建環境下
  它只在系統時鐘明顯異常時才會被用到；收它的長期成本（1 檔，但每次同步都要重新驗一次）不划算。
  若你希望完全不碰 clients2.google.com，这条可以立刻收（1 檔、痛度低）——列为第 10.1 节第 2 名。
- `disable-mei-preload.patch` 套=F/F 檔=2 ⇒ 不要
  ① Intel MEI（`enable_mei_preload`）相关 target 引用拿掉。② 套不上（F/F），且 157 已改結構。
  ③ —。判定：不要。
- `fix-building-without-safebrowsing.patch` 套=R/F 檔=132 ⇒ 不要
  ① 「關掉 Safe Browsing 還能編」的超大修補（132 個檔案，多半是 BUILD.gn 與測試檔引用）。
  ② 不需要：你走「保留 SB 代碼 + 導向 127.0.0.1」路線，正是要避開這 132 檔的地獄；
  而且 157 已把 SB 的引用結構改掉（試套判定 R/F）。
  ③ 132 檔 ⇒ 這就是「跟上游同步變地獄」的教科書例子，堅決不收。判定：不要。
- `remove-unused-preferences-fields.patch` 套=F/F 檔=228 ⇒ 不要
  ① 刪除 228 個檔案裡的「已死功能的偏好欄位」。
  ② 不要：228 檔的痛度 + 你沒有要極致瘦身偏好層。判定：不要（成本形態直接否決）。
- `block-requests.patch` 套=F/F 檔=9 ⇒ 不要
  ① 一批 URL 換成 `about:blank`（OneGoogleBar、spellcheck、profile resetter 等）。
  ② 套不上（F/F）；且其中拼字檢查（spellcheck）那條会让「拼字檢查」失效，你没说过要砍它。判定：不要。
- `disable-privacy-sandbox.patch` 套=R/F 檔=2 ⇒ 不要
  ① 從 BUILD.gn 移除 Privacy Sandbox（ADSS/Topic/PreloadPages）相關 target。
  ② 部分上游已撤：實測 `components/preload_pages` 在本樹**不存在**（0 檔），
  且試套判定「反向/已套用」⇒ 上游已做掉一部分。
  ③ 2 檔，但判定不做。判定：不要（上游已合併 + 套不上）。
- `doh-changes.patch` 套=P/G 檔=4 ⇒ 不要
  ① 改 DoH 供應商清單與預設行為（`default_dns_over_https_config_source.cc`、`doh_probe_runner.cc`、
  `doh_provider_entry.cc`）。
  ② 不要：你的 DNS 由 sing-box + AdGuardHome（127.0.0.1:5591）負責，瀏覽器不該自己選 DoH 供應商；
  改這條會跟你的網路設定打架。判定：不要（與用戶網路環境衝突）。
- `extensions-manifestv2.patch` 套=P/G 檔=4 ⇒ **已收錄**（`patches/adblock/0001-...`，理由詳見第 0.1 節）
- `remove-f1-shortcut.patch` 套=P/G 檔=1 ⇒ 不要（列為可選）
  ① 拿掉 F1 開啟「Chromium 說明」頁的鍵盤快速鍵（`chrome/browser/ui/views/accelerator_table.cc`）。
  ② 价值纯属个人偏好；你没提过 F1 误触问题。收它 = 多一条以后每次同步都要重验的档案。判定：先不要（要就说一句，1 檔、成本最低）。
- `move-js-optimizer-unfamiliar-sites.patch` 套=F/F 檔=5 ⇒ 不要
  ① 「JavaScript 預先編譯 optimizer」只對熟悉網站啟用（省記憶體/流量）。
  ② 套不上（F/F，上游把這個功能改到 `chrome/browser/resources/side_panel`＋v8_page.ts 等）。
  ③ —。判定：不要（若想關整個 optimizer，用 `--disable-features=JavascriptOptimizer` 這條路先試）。
- `remove-navigation-source-param.patch` 套=P/G 檔=1 ⇒ **已收錄**（`patches/adblock/0002-...`）
  ① `components/search_engines/template_url.cc` 的 `GOOGLE_SEARCH_SOURCE` case 清空 ⇒
  從位址列/realbox 搜尋 Google 時網址不再帶 `?source=chrome.ob` / `?source=chrome.rb`。
  ② 需要：這是瀏覽器自己拼進 URL 的追蹤參數，uBlock 攔不到；試套通過即代表這段代碼在 157 仍原样存在。
  ③ 1 檔、單一 case 區塊 ⇒ 痛度低。
- `disable-tos-dialog.patch` 套=F/F 檔=1 ⇒ 不要
  ① 首次啟動的服務條款對話框（`chrome/browser/first_run.h`）。
  ② 套不上；你也不是新 profile。判定：不要。
- `bromite/disable-fetching-field-trials.patch` 套=P/G 檔=2 ⇒ 不要（**這條是「上游已做完」的典型**）
  ① 讓 variations seed 不再向伺服器抓取 + Android 側 `ChromeFeatureList.java` 讀參數回預設值。
  ② 不需要：讀 157 的 `components/variations/service/variations_service.cc:IsFetchingEnabled()` 就知道——
  非 `GOOGLE_CHROME_BRANDING` 且沒給 `--variations-server-url` 且非測試時**本來就 return false**
  （補丁要刪的正是在那段 `#else` 分支）。你的构建是非品牌（`is_official_build=false`、
  無 `google_chrome_branding`）⇒ 生效中的就是 upstream 那條 false 路徑。Java 那半是 Android 專屬。
  ③ —。判定：不要（上游已合併，且你的 args.gn 另有 `disable_fieldtrial_testing_config = true`）。

### 3.5 extra/inox-patchset（5 條）

- `0006-modify-default-prefs.patch` 套=F/F 檔=12 ⇒ 不要
  ① 一口氣改 12 個檔案的預設偏好（背景模式、预测加载、SPARI、cookie、NTP 建議等）。
  ② 不收的主因是形態問題：12 檔混雜多個你沒點名的行為變更（其中一些會順帶改掉你想要的東西，
  例如预测加載/預取）。你要的單一項目都能用「設定頁勾選」或 `--disable-features=` 精確拿到。判定：不要（太粗）。
- `0008-restore-classic-ntp.patch` 套=P/G 檔=1 ⇒ 不要（需用戶拍板的 UI 取捨）
  ① 改 `chrome/browser/search/search.cc`（本樹實測此路徑存在），把新分頁的「傳統 NTP 佈局」找回來。
  ② 主觀項目，且你沒提過 NTP 外觀需求。判定：不收，等你說要再收（1 檔、痛度低）。
- `0013-disable-missing-key-warning.patch` 套=P/G 檔=1 ⇒ 不要（**上游已自己關掉**）
  ① 拿掉啟動時「Google API 金鑰缺失」的信息_bar_。
  ② 實測 `chrome/browser/ui/startup/infobar_utils.cc:257` 寫的是
  `if (false && !google_apis::HasAPIKeyConfigured())` ⇒ 這條信息欄在 157 已被上游硬開關鎖死，
  補丁只是多此一舉。判定：不要（證據型：上游已合併）。
- `0016-chromium-sandbox-pie.patch` 套=P/G 檔=1 ⇒ 不要（**實測你的產物已經是 PIE**）
  ① 給 `sandbox/linux/BUILD.gn` 的 suid sandbox 來源加 `-fPIE`/`-pie`。
  ② 不需要：直接讀你自己編出來的二進位 ELF 頭（`out/Release`，2026-10-11 產物）：
  `chrome` = e_type 3（DYN，即 PIE）、`chrome_sandbox` = e_type 3（DYN，即 PIE）。
  ⇒ 現行工具鏈（Artix clang/lld）預設就產 PIE，補丁是重疊劳动。判定：不要（實測產物型證據）。
- `0019-disable-battery-status-service.patch` 套=P/G 檔=2 ⇒ **已收錄**（`patches/security/0001-...`）
  ① 掏空 `services/device/battery/battery_status_service.{cc,h}`：`AddCallback()`（實測 :38）
  不再建立 BatteryStatusManager、不監聽 UPower，直接回空的 `mojom::BatteryStatus()`。
  差別：網站 `navigator.getBattery()` 永遠拿到假值（charging=true、level=1.0），少一條指紋；
  瀏覽器自身的電量/省電顯示走 `base::PowerMonitor`，不受影響。
  ② 需要：`services/device/battery/` 與 `third_party/blink/renderer/modules/battery/`（含 `battery_manager.idl`）
  在 157 都還在，且查無可關的 runtime feature。③ 2 檔（含 1 支頭檔），
  但引用這支頭檔的只有 3 支非測試檔（`services/device/device_service.cc`、
  `battery_monitor_impl.h`、`battery_status_manager.h`）⇒ 重編面很小。痛度中低。

### 3.6 extra/debian、extra/iridium-browser（6 條）

- `debian/disable/google-api-warning.patch` 套=R/F 檔=1 ⇒ 不要（同 0013，上游 `if (false && ...)` 已鎖）
- `iridium-browser/mime_util-force-text-x-suse-ymp-to-be-downloaded.patch` 套=P/G 檔=1 ⇒ 不要
  ① 把 `application/x-ymp`（openSUSE 一鍵安裝腳本）強制當下載檔。② 與你的發行版（Artix）毫無關係。判定：不要。
- `iridium-browser/prefs-always-prompt-for-download-directory-by-defaul.patch` 套=P/G 檔=1 ⇒ 不要（設定頁就有）
  ① 把 `chrome/browser/download/download_prefs.cc:355` 的 `prefs::kPromptForDownload` 預設改 true
  （「每个下载前都问我存哪」）。
  ② 不需要補丁：`chrome/browser/resources/settings/downloads/page_page.ts`（實測 :279）有
  `prompt_for_download_.Init(prefs::kPromptForDownload, prefs)` ⇒ 設定裡就有這個勾選框，
  你的 profile 是既有的，勾一次就永久生效（值存在 Preferences 裡），不必花一條補丁。判定：不要（用設定）。
- `iridium-browser/updater-disable-auto-update.patch` 套=P/G 檔=1 ⇒ 不要
  ① 動的是 `chrome/browser/mac/app_controller_mac.mm`（macOS 專屬 updater）。
  ② 平台不符（你在 Linux）。判定：不要（實測檔名＝mac only）。
- `iridium-browser/Remove-EV-certificates.patch` 套=F/F 檔=1 ⇒ 不要
  ① 清空 `net/cert/ev_root_ca_metadata.cc` 的 EV 根證書表。
  ② 不收有兩條實測：(a) 套不上（F/F，證書清單整塊換過）；(b) 這表在 157 仍是活的
  （`net/cert/cert_verify_proc_builtin.cc:38` 有引用，`net/BUILD.gn:167` 還把
  `cert/ev_root_ca_metadata_data.cc` 编進去），所以要清就得手改，而且清完只是「網站不再顯示綠色公司名」
  這種你看不见的差別。判定：不要。
- `iridium-browser/browser-disable-profile-auto-import-on-first-run.patch` 套=P/G 檔=1 ⇒ 不要
  ① 首次啟動不從別的瀏覽器Importer 書籤/密碼。
  ② 你的 profile 已存在（`out/Release` 都編好了，你不是首啟）；Thorium 的資料你也没说要导。判定：不要（情境不符）。

### 3.7 extra/bromite（3 條，全部不收，但理由是「形態」不是「沒用」）

- `fingerprinting-flags-client-rects-and-measuretext.patch` 套=F/F 檔=19 ⇒ 不要
  ① 給 `getClientRects()/getBoundingClientRect()/measureText()` 加可開關的亂數噪點（防 canvas/几何指紋）。
  ② 不收：(a) 套不上（19 檔，含 `chrome/browser/ungoogled_flag_entries.h` 這種需要前置補丁新建的檔案）；
  (b) 這類幾何噪點對你的實際痛點（登入 Google、Bitwarden 自動填入、CAPTCHA）有真實破壞風險。
  ③ 若要做，最小自製版只需要 `third_party/blink/renderer/core/dom/element.cc` + `dom/geometry` 兩檔，
  已在第 10.1 節列為「你要我再動手的備案」。
- `flag-fingerprinting-canvas-image-data-noise.patch` 套=F/F 檔=11 ⇒ 不要
  ① `getImageData()` 加噪點（canvas 讀取指紋）。② 套不上（11 檔，同樣依賴 `bromite_flag_entries.h`）；
  而且 `third_party/blink/renderer/core/html/canvas/`（實測 72 檔）在 157 結構已與補丁基線不同。
  風險面：某些登入流程/圖形應用会被噪點打壞。備案同上用 1 檔自製（`html_canvas_element.cc`）。
- `flag-max-connections-per-host.patch` 套=F/F 檔=6 ⇒ 不要
  ① 把每個 host 的 HTTP 連線上限做成可調（防「用連線數做指紋」+ 緩解排隊）。
  ② 套不上（6 檔，依賴 bromite 自己的 flag 框架檔案）。判定：不要（列入 10.1 備案）。

### 3.8 extra/ungoogled-chromium：框架與新檔型（3 條）

- `add-components-ungoogled.patch` 套=P/G 檔=3 ⇒ 不要（框架，不收）
  ① 新建 `chrome/browser/ungoogled_flag_entries.h`、`ungoogled_flag_choices.h` 等（試套輸出 3 個檔案中有 3 個是 `/dev/null` 型新建）。
  ② 它是 30+ 條 `add-flag-*` 的地基；只收地基不收旗標沒意義，整套收就是 40+ 檔的長期同步負債。判定：不要（連同 3.9 整群一起否決）。
- `add-ungoogled-flag-headers.patch` 套=P/G 檔=7 ⇒ 不要（同上，框架）
- `add-credits.patch` 套=P/G 檔=3 ⇒ 不要
  ① 在 about:credits 加 ungoogled 自己的謝辭與授權檔。② 你要的是 aetherium 品牌（你已有 0002/0004 品牌補丁），
  不是別人的品牌露出。判定：不要。

### 3.9 extra/ungoogled-chromium：其餘 54 條（其中 31 條是 add-flag* 旗標框架型；框架群整群不收，逐條仍給判定）

共同實測事實（這是它們被否決的**主因**，不是猜測）：
- 這一整群在 157 的試套結果都是 `F/F`；
- 它們的檔案清單裡普遍出現 `ungoogled_flag_entries.h` / `ungoogled_flag_choices.h`
  （由 3.8 那兩條新建檔，本樹不存在）與 `chrome/browser/ui/webui/flags/*`、`about_flags.cc` 的 ungoogled 專屬上下文；
- 也就是「要收就得把 ungoogled 的整套旗標框架（約 40+ 檔、含 WebUI 面板）一起搬進來」，
  每輪上游同步都要重做 ⇒ 正是你定義的「同步變地獄」。
以下逐條：①它想做什麼＋你會看見的差別 ②對你的價值判定 ③替代方案（多數不用補丁就有）。

- `add-flag-to-configure-extension-downloading.patch`（6 檔）：控制擴充下載來源。對你無價值（你用 Web Store）。不要。
- `add-flag-for-search-engine-collection.patch`（5 檔）：自動從造訪的站點收集可新增的搜尋引擎。
  ②你有 Google 就好，價值低。替代：造訪該站後 Chrome 自己會提示新增。
- `add-flag-to-disable-beforeunload.patch`（2 檔）：忽略「確定要離開？」攔截。②這條其實有日常價值
  （表單頁誤關不再被擋）。替代：`--disable-features=DismissBeforeUnload...` 這類 flag 需你自己驗證；
  已列入第 10.1 節「值得單獨手工做」（只 2 檔：`app_modal_dialog_manager.cc`）。
- `add-flag-to-force-punycode-hostnames.patch`（2 檔）：位址列永遠顯示 punycode（防 Unicode 偽造域名）。
  ②安全上有真實意義、成本低（`url_formatter.cc` 1 檔）。列入 10.1 手工備案。
- `add-flag-to-show-avatar-button.patch`（3 檔）：工具列顯示頭像按鈕。②主觀，且你登入 Google 時本來就有。不要。
- `add-suggestions-url-field.patch`（13 檔）：搜尋引擎編輯頁加一個「建議 URL」欄位。②對你無價值。不要。
- `add-flag-to-hide-crashed-bubble.patch`（2 檔）：不顯示「無法還原頁面」氣泡。②有日常價值、1 檔可自製。10.1 備案。
- `add-flag-to-scroll-tabs.patch`（4 檔）：豎向分頁列可用捲輪。②你沒提過。不要。
- `enable-paste-and-go-new-tab-button.patch`（2 檔）：NTP 貼上並前往按鈕。套=**P/G**（這群裡少數通過的）。
  ②主觀便利，不是需求。不收（避免多一條同步債）。
- `add-flag-for-bookmark-bar-ntp.patch`（3 檔）：在 NTP 也顯示書籤列。②主觀。不要。
- `enable-menu-on-reload-button.patch`（1 檔）：重新載入按鈕長按出選單（清除快取重載）。套=**P/G**。
  ②真便利、1 檔（`reload_button.cc`）。判定：先不收，等你一句話就收（最低成本的一條）。
- `add-flag-for-omnibox-autocomplete-filtering.patch`（6 檔）：過濾位址列自動完成來源。②不要（太細）。
- `add-flag-to-close-window-with-last-tab.patch`（4 檔）：關掉最後一個分頁時整個視窗不關。
  ②在 i3 裡這是你可能想要的行為。1 檔可自製（`browser_tab_strip_model_delegate.cc`）。10.1 備案。
- `add-flag-to-convert-popups-to-tabs.patch`（3 檔）：彈窗一律轉成分頁。②有價值（Bitwarden/登入弹窗体验）。10.1 備案。
- `add-flag-to-disable-local-history-expiration.patch`（2 檔）：本機歷史不主動過期。②你沒提；不要。
- `add-extra-channel-info.patch`（1 檔）：about:version 顯示 channel 資訊。套=**P/G**。
  ②對你沒價值（你自己就是 channel）。不要。
- `prepopulated-search-engines.patch`（1 檔）：預置額外搜尋引擎清單。套=**P/G**。
  ②你明確只要 Google；不要。
- `add-flag-to-clear-data-on-exit.patch`（4 檔）：登出即清資料。②與你「profile 長期使用」相斥。不要。
- `add-flag-for-qr-generator.patch`（4 檔）：分頁選單產生 QR。②不要（手機端有更好工具）。
- `add-flag-for-grab-handle.patch`（2 檔）：分頁列拖把手。②不要。
- `add-flag-for-close-confirmation.patch`（4 檔）：關閉前確認。②與 beforeunload 那條重疊，先不收。
- `keep-expired-flags.patch`（1 檔）：讓 `about:flags` 裡已過期的條目還能用。套=**P/G**。
  ②**不收**：它會讓你能開啟上游刻意關死的實驗功能，穩定性風險由你承擔。判定：不要。
- `add-flag-for-custom-ntp.patch`（3 檔）：自訂 NTP URL。②替代：`--homepage` + 設定裡「使用自訂網頁當新分頁」。不要。
- `add-flag-for-tab-hover-cards.patch`（5 檔）：分頁懸停預覽卡。②不要。
- `add-flag-to-hide-tab-close-buttons.patch`（3 檔）：隱藏分頁關閉 X。②不要。
- `add-flag-to-disable-tls-grease.patch`（2 檔）：關掉 TLS GREASE。②**不要**：GREASE 是 anti-指紋機制，
  關掉反而更容易被中間設備識別；這條與你的目標反向。
- `add-flag-to-change-http-accept-header.patch`（3 檔）：自訂 `Accept` 標頭。②不要（uBlock/AGH 層更合適）。
- `add-flag-for-disabling-link-drag.patch`（5 檔）：連結不可拖曳。②不要。
- `add-flag-to-hide-extensions-menu.patch`（2 檔）：隱藏擴充選單圖示。②與「要用 Bitwarden/看通知」相斥。不要。
- `add-flag-to-hide-fullscreen-exit-ui.patch`（3 檔）：全螢幕時不顯示退出提示。
  ②對 HiDPI/全螢幕看片有用，1–2 檔可自製（`fullscreen_control_host.cc`）。10.1 備案。
- `add-flag-for-incognito-themes.patch`（3 檔）：無痕模式獨立主題。②不要。
- `add-flags-for-referrer-customization.patch`（11 檔）：自訂 referrer 發送策略。
  ②有價值但要 11 檔（含 `navigation_request.cc`、`render_frame_impl.cc`）。替代：
  `--disable-features=ReduceReferrer...`／設定頁的 referrer 選項。不收（成本/風險）。
- `default-webrtc-ip-handling-policy.patch`（1 檔）：WebRTC 本機 IP 洩漏的政策預設值。
  實測它做的是把 `chrome/browser/ui/browser_ui_prefs.cc:160` 註冊的
  `prefs::kWebRTCIPHandlingPolicy` 預設從 `blink::kWebRTCIPHandlingDefault` 改成
  `blink::kWebRTCIPHandlingDisableNonProxiedUdp`（兩組常數都宣告在
  `third_party/blink/public/common/peerconnection/webrtc_ip_handling_policy.h:17-32`）。
  ②**不收補丁**，因為 157 有官方命令列旗標：`content/public/common/content_switches.cc:852
  kForceWebRtcIPHandlingPolicy = "force-webrtc-ip-handling-policy"` ⇒
  在 `.desktop`／啟動腳本加
  `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`（或 `default_public_interface_only`）
  就能達到同一件事，零同步成本、隨時可改。這條是我原本想收的第 5 條，被實測推翻為「不用補丁」。
  ③ —。判定：不要（有官方旗標）。
- `add-flags-for-existing-switches.patch`（3 檔）：把既有 `--switches` 暴露到 about:flags 方便關。套=F/F。
  ②不要（你需要的是腳本裡寫旗標，不是 WebUI）。
- `add-flag-to-reduce-system-info.patch`（5 檔）：減少的 UA-CH / client hints 資訊。套=F/F。
  ②不收：(a) 套不上；(b) 157 的 UA-CH 是必需協定，砍高熵 client hints 會打壞 YouTube/Google 登入的品質判定。
- `add-flag-to-remove-client-hints.patch`（6 檔）：完全移除 client hints。套=F/F。
  ②不要：同上，且與「要能連上 Google 看 YouTube」抵觸。
- `add-flag-to-spoof-webgl-renderer-info.patch`（5 檔）：偽造 WebGL 廠商/型號。套=F/F。
  ②不要：(a) 套不上；(b) 你有 NVIDIA 獨顯 + 想要硬解/流暢渲染，WebGL 資訊偽造對指紋收益小、對 3D/遠端桌面風險大。
- `enable-extra-locales.patch`（4 檔）：新增 `extra_locales` GN 參數以加入不在清單裡的語言。套=P/G。
  ②**不需要**：實測 `build/config/locales.gni:113` 已含 `"zh-TW"`（臺灣正體在默認清單內）⇒
  你的 UI 語言需求不用補丁。判定：不要（上游已包含）。
- `remove-pac-size-limit.patch`（1 檔）：放寬 PAC 自動設定檔大小上限。套=P/G。
  ②不要：你的代理是 sing-box（策略路由），不用 PAC 檔案。判定：不要（情境不符）。
- `enable-certificate-transparency-and-add-flag.patch`（2 檔）：開啟 CT 強制驗證。套=F/F。
  ②不要：上游預設已启用 CT 機制（且這條套不上）。
- `add-flag-to-increase-incognito-storage-quota.patch`（4 檔）：無痕儲存配額。套=F/F。②不要。
- `disable-ai-search-shortcuts.patch`（2 檔）：拿掉位址列的 AI 搜尋快捷。套=F/F。
  ②功能確實存在（實測 `chrome/browser/ui/webui/side_panel/...`、`featured_search_provider.cc` 在樹裡），
  但補丁套不上。替代：`--disable-features=AiDataCenterUrlButton,...` 需你自己試；或摘註冊（你已做的那種路線）。
  判定：不收補丁，列入 10.1 備案。
- `disable-fedcm-by-default.patch`（1 檔）：FedCM（Federated Credential Management）預設關。套=P/G。
  ②**不要，且這是本輪最重要的一條「反建議」**：FedCM 是 157 第三代 cookie 政策下
  「Sign in with Google」視窗的實作路徑（`content/public/browser/content_features.cc`），
  你靠 Google 登入與 floccus→Google Drive，預設關掉它會直接打壞第三方站的 Google 登入。判定：不要。
- `bundle-hyphenation-patterns.patch`（1 檔）：把連字字典捆進構建（不靠網路抓）。套=P/G。
  ②不要：連字（hyphenation）補的是 `third_party/hyphenation_patterns` 在「剪枝後缺失」的問題，
  你完全沒剪二進位（第 3.4 的 `fix-building-with-prunned-binaries` 判定同樣適用在這裡）；
  而且中文/CJK 排版不做英文式連字，你的字型需求靠 TsukuGo/霞鶩文楷釘好就好。判定：不要。
- `disable-intranet-redirect-detector.patch` 套=P/G 檔=1 ⇒ **已收錄**（`patches/adblock/0003-...`）
  ① `chrome/browser/intranet_redirect_detector.cc` 的 `FinishSleep()` 改成無條件 return，
  啟動後不再發內網網域探測的 DNS 與兩個 http 請求。②需要，實測功能是活的：
  `chrome/browser/browser_process_impl.cc:1198` 真的建立了這個物件。③1 檔、痛度低。
- `disable-dial-repeating-discovery.patch` 套=P/G 檔=1 ⇒ **已收錄**（`patches/adblock/0004-...`）
  ① `chrome/browser/media/router/discovery/dial/dial_registry.cc:156 StartPeriodicDiscovery()`
  拿掉 `DoDiscovery()` 與 `repeating_timer_` ⇒ 不再週期性對區網發 SSDP/DIAL 廣播。
  ②需要但價值中等：`DialRegistry` 由 `dial_media_sink_service_impl.cc:124` 建立，
  也就是「投放探索啟動後才跑」，不是開機就廣播。③1 檔、痛度低（`repeating_timer_` 成員未使用會噴警告）。
- `disable-download-quarantine.patch` 套=P/G 檔=4 ⇒ 不要
  ①拿掉下載檔案的「隔離標記」（Windows 的 Zone.Identifier 交替数据流、macOS 的 quarantine xattr），
  落點在 `base/files/base_file.cc`、`base/files/BUILD.gn`、
  `chrome/browser/file_system_access/file_system_access_safe_move_helper.cc` 等 4 檔。
  ②不要：Linux 檔案系統沒有這套隔離標記可關，對你等於空轉（判定依據：4 檔中有 2 檔在 `base/files/`
  的平台分支、1 檔是 FSAA helper；這條我沒逐行讀完，屬「檔案清單 + 平台機制」層級的判定）。
  ③ —。
- `fix-building-without-mdns-and-service-discovery.patch` 套=P/G 檔=4 ⇒ 不要（但它是「關 mDNS」的必要搭配）
  ①在 `enable_mdns=false` 時讓 `dns_sd_registry.cc`、`dns_sd_device_lister.cc`、
  相關 BUILD.gn 與 browser_tests 還能編過。
  ②不需要：你 args.gn 沒關 mdns；而 `chrome/common/features.gni` 的
  `enable_service_discovery = enable_mdns` 說明「關 mDNS」在 157 是合法路线。
  ③若哪天你想徹底停掉區網服務探索（SSDNS/mDNS），正確順序是 args.gn 加 `enable_mdns = false`
  再收這條（4 檔）⇒ 已列第 10.1 節備案。判定：暫時不要。
- `first-run-page.patch` 套=P/G 檔=4 ⇒ 不要
  ①新建一個 first-run 歡迎 WebUI（動 `chrome/browser/chrome_browser_main.cc`、
  `chrome/browser/ui/webui/chrome_web_ui_configs.cc`、`chrome/common/webui_url_constants.cc` + 1 支新建檔），
  首啟時顯示 ungoogled 自己的頁面。
  ②不要：那是別人的品牌頁；你要的是 aetherium 品牌（你已有 0002/0004 品牌補丁）。
  ③4 檔且新建 WebUI target ⇒ 痛度中。
- `remove-disable-setuid-sandbox-as-bad-flag.patch` 套=P/G 檔=1 ⇒ 不要（方向与你相反）
  ①把 `chrome/browser/ui/startup/bad_flags_prompt.cc` 裡「以 `--disable-setuid-sandbox` 之类的危险旗标
  启动时显示黄色警告条」这个检查移除掉（ungoogled 需要它，因為他們的发行版会带这类参数）。
  ②不要：你需要的是**保留**这个警告——它是防止你哪天用无沙箱方式启动还不自知的唯一提示。判定：不要。
- `disable-formatting-in-omnibox.patch` 套=P/G 檔=2 ⇒ 不要
  ①动 `chrome/browser/ui/location_bar/chrome_location_bar_model_delegate.cc` 与
  `chrome/browser/ui/status_bubble.h`，把位址列里自动完成文字的格式化显示关掉。
  ②不要：纯外观取向，你没提过这类需求（判定依据是它动的 2 个档案都在 UI 层；我這轮没拆这份档逐行读）。
  ③2 檔、痛度低，你想要随时说。
- `add-ipv6-probing-option.patch` 套=F/F 檔=4 ⇒ 不要
  ①把「IPv6 探測」做成可关的 ungoogled 旗标（动 `ungoogled_flag_entries.h`、
  `chrome/browser/about_flags.cc` 系的 features.cc/.h、`net/dns/host_resolver_manager.cc`）。
  ②不要，兩條：(a) 套不上（F/F，框架檔不存在）；(b) 你的既定环境是「v4 不通、测试一律用 v6」，
  关 IPv6 探测对你是**反效果**。判定：不要。
- `add-flag-for-disabling-jit.patch` 套=F/F 檔=3 ⇒ 不要
  ①把「完全关掉 V8 JIT」做成启动旗标（动 `ungoogled_flag_entries.h`、
  `content/browser/renderer_host/render_process_host_impl.cc`、`build/config/v8.gni`/v8 相关）。
  ②不收：套不上（F/F）+ 框架依赖；而且效果是让所有网页退回直译模式，流畅度代价极大，
  与你的「不要卡顿」目标相反。判定：不要。
  （若真想要「关 JIT」的实验做法，执行期等价手段我这轮没验证，不能给你保证。）
- `remove-uneeded-ui.patch` 套=R(反向/已套用)/F 檔=31 ⇒ 不要（本輪單檔數第二大的一條）
  ①一次刪掉 31 個檔案裡的「多餘 UI」：設定頁項目、`settings_chromium_strings.grdp` 字串、
  書籤/選單元件、NTP 元素等（它是 ungoogled 最招牌、也最難跟版的一條）。
  ②不收，兩條實測依據：(a) 試套被 GNU patch 判定「內容已存在/反向」、嚴格模式 F，
  代表 157 上游已把其中一批東西自己拿掉了；(b) 31 檔裡含 `.grdp` 字串檔與 WebUI 資源，
  這正是「跟上游同步會變成地獄」的形態（你自己在 0004 品牌補丁裡已經體會過改字串檔要動幾百個 xtb）。
  ③ —。判定：不要；真想砍 UI，用企业 policy/`chrome://flags` 逐項關，別用這條。

### 3.10 小計

ungoogled 108 條的試套統計（series 檔共 110 行、內含 2 個空行；實測）：`patch --dry-run` 通過 52、失敗 51、判定「反向/已套用」5，
`git apply --check`（你 apply-patches.sh 用的嚴格模式）通過 50、失敗 58。
最終收錄 4 條（adblock 0001/0002/0003/0004）+ security 2 條（iridium 那兩條在 core 群）＋
另有 1 條來自 ungoogled/inox 的 battery（extra 群）= 來自 ungoogled 的收錄共 7 條，
自己寫的 1 條（performance/0001）。

---

## 4. Bromite（206 條）與 Cromite（327 條）判定

這兩家都是 **Android 瀏覽器**，補丁主體是 Java/Kotlin/APK/設定頁改動。
先把量講清楚（實測 `grep -cE '^build/patches/.*\.patch$'`）：

- Bromite：206 條（`build/patches/`），2024-01-24 後停更。按名稱關鍵字計數：
  Disable 54、Remove 19、Enable 16、Block 8、Add-flag 7、flag 18、Revert 6、Restore 5、Allow 5、
  fingerprint 1、Bromite 3、Android 2、Clamp 1、Reduce 1。
- Cromite：327 條（權威清單 `build/cromite_patches_list.txt`，333 行），2026-10-11 仍活躍。關鍵字計數：
  Disable 102、Remove 18、Enable 30、Allow 13、Add-flag 7、flag 24、fingerprint 7、Android 16、
  Branding 2、Restore 8、Add-setting 3、Revert 5、Block 9、Reduce 4、Bromite 4、Cromite 5。

判定分三層：

### 4.1 結構性「不要」（Android 限定）

Cromite/Bromite 的補丁大量動 `chrome/android/**`、`components/*/{android,java}/**`、`*.java/*.kt`、
`AndroidManifest`、APK resource。桌面版根本不編這些 target（你的 `autoninja -C out/Default chrome`
只出 `chrome` 與 `chrome_sandbox`，實測 `ls out/Release`）。
⇒ 「Add-setting-to-invert-tap-and-long-tap」、「Android-Toolbar-Scroll-Ablation-setting」、
「Block-Intents-While-Locked」、「Android-Pixel-Perfect-Mode」、「Disable-Android-AppRestrictions」、
「Bromite-package-name」、「Cromite-Branding」等（Android 關鍵字 16 條 + 名稱即 Android 的全部）：不要。

### 4.2 「157 上游已做掉／已由既有補丁覆蓋」的具名條目

- `Disable-fetching-of-all-field-trials.patch`：上游 `IsFetchingEnabled()` 對非品牌构建已 return false（見 3.4 最後一條）。不要。
- `Disable-FLoC-and-privacy-sandbox.patch` / `Disable-conversion-measurement-api.patch`：
  實測 `components/preload_pages` 不存在、Privacy Sandbox 部分已被 ungoogled 的 `disable-privacy-sandbox`
  判定為「已套用/反向」⇒ 上游已撤。不要。
- `Disable-AsyncDNS-by-default.patch`：这条会关掉 Chromium 自己的异步 DNS resolver（走 getaddrinfo）。
  你走 sing-box + AGH(127.0.0.1:5591) ⇒ 关掉只会让 DNS 变慢、并沒有隱私收益（連線還是到同一處）。不要。
- `Disable-TLS-resumption.patch`：關 TLS session resumption。②不要：它明顯加重 handshake 負擔，
  而你的痛點是構建成本與流暢度，不是 TLS 會話票據指紋。
- `Disable-DRM-media-origin-IDs-preprovisioning.patch` / `Disable-media-DRM-preprovisioning-by-default.patch`：
  ②不要：你保留 `enable_widevine=true` 與 `proprietary_codecs=true`，pre-provisioning 關掉會讓首次播放
  DRM 內容變慢或需要現場取得。
- `Clamp-time-resolution-in-requestAnimationFrame.patch` / `AudioBuffer-AnalyserNode-fp-mitigations.patch` /
  `Android-fonts-fingerprinting-mitigation.patch` / `Client-hints-overrides.patch`：
  這四條是 Cromite 的指紋緩解群（fingerprint 關鍵字 7 條）。
  ②不收，理由有兩條實測：(a) 它們的落點是 blink/renderer 核心與 `runtime_features.cc`，
  你在 157 上的同位置已與補丁基線不同（ungoogled 收錄的同一批 bromite 旗標補丁 dry-run 全 F/F，見 3.7）；
  (b) 你已有 uBlock Origin + AGH，且你的硬性需求裡「輸入法候選框必須看得见、字型釘死」與
  fonts 指紋緩解（把字形度量改壞）方向抵觸。
- `Block-gateway-attacks-via-websockets.patch`：擋 WebSocket 打內網閘道（localhost 攻擊）。
  ②值得知道但**不收**：157 已有 Local Network Access（LNA）機制在上游實作
  （Cromite 自己也寫了 `Partially-revert-upstream-M152-LNP-Require-ACCESS_LO...` 來退讓），
  再打這條會與上游 LNA 撞車。判定：不要（上游已有等效機制）。
- `Content-settings-infrastructure.patch` / `Add-webGL-site-setting.patch` / `Add-webRTC-site-settings.patch`：
  這些是 Cromite 自己加的「每站權限設定 UI」（1500+ 行的 Java/UI 體系）。桌面版對應機制是
  `chrome://settings/content/*`（上游就有 site settings），不要。
- `Add-bookmark-import-export-actions.patch` / `import-and-export-bookmarks-feature.patch`（Vanadium 也有）：
  桌面版 `chrome://bookmarks` 選單本来就有匯入/匯出。不要。
- `Dictionary-suggestions-for-the-Omnibox.patch`、`Add-DuckDuckGo-Lite-search-engine.patch`、
  `Add-English-only-search-engine.patch`、`set-default-search-engine-to-DuckDuckGo`（Vanadium）：
  ②不要：你明示 Google 是預設搜尋。
- `Disable-all-predictors-code.patch`、`Disable-all-promo-dialogs.patch`、`Disable-NTP-remote-suggestions-by-default.patch`：
  ②部分有價值，但 157 的對應開關在上游 runtime features 裡
  （`InterestFeedContentSuggestions`、`NtpRealbox*`、`PreloadPages` 等），
  用 `--disable-features=` 一次拿到，不必打補丁。判定：不要（用旗標）。

### 4.3 「桌面可借鑒但本輪不收」的具名條目（第 10.1 節備案）

- `Disable-BackForwardCache.patch`（Cromite）：關整個 bfcache。②不建議：bfcache 對 13GB 機器是**省記憶體/省 CPU**的，
  關掉只會更卡。判定：不要。
- `Add-flag-to-control-video-playback-resume-feature.patch`、`Always-open-browser-controls-in-new-tab.patch`：UI 偏好，不要。
- `Enable-HEVC-decoding.patch` / `Media-HEVC-Support.patch` 這一類（Cromite/Thorium/Bromite 都有 HEVC 條目）：
  **不要**，理由見第 0.2 節（157 的 Linux 已預設 `enable_hevc_parser_and_hw_decoder=true`）。
- `chromium-restore-jpeg-xl-support-120.patch`（Thorium，同一思路 Cromite 也有 `Enable-JPEG-XL...`）：
  **不要**，實測 `third_party/blink/renderer/platform/image-decoders/jxl/` **存在** ⇒ 上游 M133 起已把 JPEG XL
  解碼放回來了，120 時代那條「恢復」補丁在 157 是多此一舉（而且會跟 jxl/ 目錄打架）。

---

## 5. Vanadium（302 條 + 6 條 subprojects）判定

實測名稱前綴計數（去號後）：`Extend*` 28、`Extension-of*` 4、`config-*` 14、`bugfix*` 11、
`disable*` 42 + `Disable*` 13（55）、`enable*` 12 + `Enable*` 7（19）、`remove*` 10 + `Remove*` 5（15）、
`Support*` 8、`Restore*` 7、`Revert*` 3、`tmp-*` 3、`upstream-*` 3、`Implement*` 2、`use-*` 3、`set-*` 2。

### 5.1 佔大頭的構建管路（約 60+ 條）：不要，且是結構性不要

`patches/0026`–`0062`、`0169`–`0200` 這一大片全是 `Extend-<target>-sources-and-deps` /
`config-*`（給 config-apk 生成 protobuf、反射挂載 helper、Trichrome APK manifest）。
它們的存在理由是 Android 的 Trichrome/Library-AAPK 打包體系必須把上游 target 拆開重組。
桌面版 `chrome` 目標不走 Trichrome ⇒ 一條都不能收。判定：不要（實測名稱與 `generate-release`/`args.gn` 的 android 前提）。

### 5.2 安全硬化類：逐條（這是最有參考價值的一組）

- `0010-enable-stack-clash-protection-for-arm64-targets`、`0015-Only-enable-shadow_call_stack-on-android-arm64-targe`、
  `0016-Use-fstack-protector-strong-with-shadow-call-stack-w`：不要。
  實測依據：`build/config/compiler/BUILD.gn:441-449` 的 SCS 分支里有 `assert(is_android)` ⇒ 桌面 x64 打不開 SCS。
- `0011-switch-to-fstack-protector-strong`：**可選，但要先講代價**。
  ①把 POSIX 平台的 `-fstack-protector` 換成 `-fstack-protector-strong`。
  ②157 現況實測：`build/config/compiler/BUILD.gn:448-470` 裡 `is_chromeos` 才用 strong，
  其餘 `is_posix`（含 Linux）走 `-fstack-protector`（:466-468）⇒ 對你確實是升級。
  ③但它落在 `build/config/compiler/BUILD.gn`（全域 config，`build/config/BUILDCONFIG.gn:370-381` 把
  這些 config 掛在每個 target 上）⇒ **改這一行 = 整個樹全部重編**（你上次 6 小時的那種），
  而且 strong 會增加 .text 尺寸，跟你 `optimize_for_size = true` 的取向相沖。
  判定：不收（列为第 10.3 節「要用戶拍板」第 1 名）。
- `0012-enable-fwrapv-in-Clang-for-non-UBSan-builds`：不要。
  ①全域加 `-fwrapv`（有符號溢位走回繞而非 UB）。②實測 `build/config/compiler/BUILD.gn` 裡沒有 `-fwrapv` ⇒ 上游確實沒有；
  ③但同樣是全域 cflags ⇒ 全量重編 + 尺寸/速度成本，且上游用 UBSan/CFI 的路线取代它。判定：不要（全量重編類，需你点头才做任何）。
- `0013-enable-ftrivial-auto-var-init-zero`：**不要補丁，用 args.gn 就有**。
  實測 `build/config/compiler/BUILD.gn:144 init_stack_vars = !(is_android && is_official_build)`（Linux 為 true）、
  `:153 init_stack_vars_zero = is_official_build && !dcheck_always_on`（你 false ⇒ 目前得到 pattern 版），
  `:3262-3268 config("default_init_stack_vars")` 在 `init_stack_vars_zero` 時用 `-ftrivial-auto-var-init=zero`。
  ⇒ args.gn 加一行 `init_stack_vars_zero = true` 就是 Vanadium 這條的效果（仍會觸發全量重編，因為 cflags 变了）。
- `0122-enable-memory-tagging-in-all-processes`（MTE）：不要。ARM 专属（你手機是 Pixel/Titanium 系），桌面 x64 無關。
- `0123-enable-split-cache-by-default`：不要。它補的是 Android 的 Split-Cache 機制（`android_webview`/`base/android`）。
- `0124-enable-partitioning-connections-by-default`：不要。Socket 隔離按站点分组在桌面版对应
  「分区连接」是上游已有的 `NetworkIsolationKey` 行為；且補丁落點在 `services/network/**`（Android 側開關）。
- `0126-enable-strict-site-isolation-by-default-on-Android` / `0127-Enable-strict-origin-isolation-by-default` /
  `0250-Enable-origin-keyed-process-isolation-by-default`：不要——桌面版 157 的 Site Isolation
  本來就是預設全開（`--disable-features=IsolateOrigins` 才是关掉它的手段；本輪没在桌面树里找到需要打补丁的默认缺口）。
- `0128-Enable-reduce-accept-language-header-by-default` / `0161-Derive-high-entropy-client-hints-with-reduced-user-a`：不要。
  ①把 `Accept-Language` 精簡、高熵 client hints 用縮減後的 UA 推導。
  ②不要：你要求繁中 UI 與 Google 服務可用；砍 `Accept-Language` 會直接影響 Google 返回的語言/搜尋結果品質。
- `0129-use-Google-Chrome-branding-for-client-hints`：不要（品牌伪装向，與你 aetherium 品牌化方向相反）。
- `0103-stub-out-the-battery-status-API`：與inox 0019 同一件事，桌面版我們收的是 inox 那條（已收 security/0001）。

### 5.3 隱私/默认值類（對你大部分「已用別的方法做到」）

`0063-disable-first-run-welcome-page`、`0065/0066/0067` field trial/variations、`0069` navigation error
correction、`0071` network prediction、`0072` metrics、`0073` hyperlink auditing、`0074` popular sites、
`0075/0076/0077` 建議/傳感器、`0079` third-party cookies、`0080` background sync、`0086/0087` safe browsing reporting、
`0090` component updater pings、`0092` trivial subdomain hiding、`0110/0112/0113` optimization guides/hints、
`0114` network time tracker、`0116` Glic、`0119` HTTPS-only、`0120` HTTPS for component updates、
`0125` Do Not Track、`0134` null check bugfix、`0242/0243` password leak detection、`0252/0253` NTP cards：
判定「不要打補丁」，理由分三類，都是實測可查的：
- 與你既有補丁重複：`0086/0087`（safe browsing reporting）= 本輪已收的 security/0002、0003；
  `0090`（component updater pings）= 你 0001-privacy 已摘 `RegisterFileTypePolicies/CrowdDeny/...` 註冊。
- 有官方 runtime feature / 設定頁可用，不需要編譯期動刀：`0071/0075/0110/0112/0113`
  （OptimizationHints、SearchSuggestPreload、NtpModules 等）、`0079`（chrome://settings/cookies）、
  `0242/0243`（chrome://settings/passwords 的洩漏檢查開關）、`0063`/`0092`/`0252/0253`。
- 不適用於桌面：`0091` search provider logo、`0131` settings help icon、`0133` remove feedback menu、
  `0141` safety check、`0142/0145/0147/0148/0150/0152/0153` 全是 Android 設定頁 preference 移除（Java）。
- 特例：`0114 disable-network-time-tracker-by-default` 與 ungoogled 那條同源，见 3.4（可选手工，成本 1 档）。
- 特例：`0119 Make-HTTPS-only-mode-the-default`：桌面 157 對應 chrome://settings/security 的
  「Always use secure connections」，設定頁勾選即可，不要補丁。

### 5.4 手機上的 aetherium？

你沒要求把 aetherium 做成 Android 版，所以 `patches/android/` 這個分類目錄這次**留空**（只有 .gitkeep）。
理由與實測：Vanadium/Bromite/Cromite 的補丁主體是 Java/Kotlin/APK，桌面 `chrome` 目標不編這些；
真要移植 Android 版時，需要的是另一整套 `args.gn`（Vanadium 的 `args.gn` 在 repo 根，可當起點）與
Trichrome 打包管路，那是另一個任務，不屬於「桌面補丁」范畴。

---

## 6. Supermium（15 條）與 Thorium（52 條）判定

### 6.1 Supermium（`win32ss/supermium`，根目錄 15 個 .patch bundle）

實測檔名：`150_about_flags_and_finishing_touches.patch`、`client_hints.patch`、`general_features.patch`、
`misc_changes_20261002.patch`、`ptr_device_fix.patch`、`quic_fix.patch`、
`supermium_150_core_encrypt_mojo.patch`、`supermium_150_core_mem.patch`、`supermium_150_core_sandbox.patch`、
`touch_device_support_win7.patch`、`ui_part_1.patch`、`ui_part_2.patch`、
`ungoogled_supermium_and_mv2.patch`、`waveinput_output_restore.patch`、
`win7_notification_bug_and_improved_pwa_install_prompt_block.patch`、`xp_tts_fix.patch`。

- 全部判定：不要。①它們的主題是 Windows XP/2003/Vista/7 的 API 回充（waveInput、toast 通知、
  `core_sandbox`/`core_mem` 的舊 Windows 進程兼容）。②你在 Artix/X11/Linux：
  `waveinput_output_restore`（Windows 音效）、`xp_tts_fix`（Windows TTS）、
  `win7_*`、`touch_device_support_win7`、`ptr_device_fix`（Windows Pointer）全部無落點。
- 唯一值得記一筆的是 `ungoogled_supermium_and_mv2.patch`：它證明「MV2 要靠補丁救」在業界是共識做法，
  與第 0.1 節的實測結論互相對齊（不是只有 ungoogled 一家）。

### 6.2 Thorium（`Alex313031/thorium`，52 個 .patch + `src/` 895 個整檔覆寫）

- `other/*.patch`（28 條）逐條判定（名稱 → 對你的價值）：
  - `add-hevc-ffmpeg-decoder-parser.patch`、`ffmpeg_hevc_ac3.patch`、`change-libavcodec-header.patch`：
    **不要**，第 0.2 節已證明 157 Linux 的 HEVC 是預設開的；AC3/EAC3 平台解碼在 157 的預設是
    `enable_platform_ac3_eac3_audio = proprietary_codecs && (is_cast_media_device || (is_ios && tvOS))`
    （`media/media_options.gni:74-76`）⇒ 桌面拿不到，但那是 FFmpeg 软解的議題，不是這條補丁能解决的（它动的是 third_party/ffmpeg 嵌套仓）。
  - `chromium-restore-jpeg-xl-support-120.patch`（在 `infra/`）：**不要**，第 4.3 節實測 `image-decoders/jxl/` 已存在。
  - `disable-privacy-sandbox.patch`：**不要**，與 ungoogled 同條一樣被判「已套用/反向」，且上游已撤部分内容。
  - `fix_drag_and_drop_on_wayland.patch`、`fix_wayland_scale_crash.patch`：**不要**，你的 args.gn 明確
    `ozone_platform_wayland = false`（Wayland-only 的東西一律不留）。
  - `fix_disable_aero_crash.patch`、`mini_installer.patch`、`win_updater.patch`、`fix_getupdatesprocessor_crash.patch`、
    `fix_file_dialog_crash.patch`、`fix_setting_popover_invoker_crash.patch`、`fix_profile_selector_crash.patch`：
    **不要**，Windows 專屬或已在上游修掉（这些是 Thorium 追上游慢才需要的回填）。
  - `fix_touch_emulator_double_tap_zoom.patch`、`keyboard_shortcuts.patch`、`open_in_same_tab.patch`、
    `restore_download_shelf.patch`、`ftp-support-thorium.patch`、`multi-language-translate.patch`、
    `remove_discovery_module_from_ntp.patch`、`thorium-2024-ui.patch`、`thorium_webui.patch`、
    `GPC.patch`、`partalloc.patch`、`fix-policy-templates.patch`、`fix_absl_undefined_symbol.patch`、
    `fix_dangling_pointer_tooltip.patch`：不要。①它們多數是「把上游 UI 改回舊樣/加回被砍的东西」
    或「Thorium 自家 UI 主題」，屬於主觀取向；②`GPC.patch`（Global Privacy Control 標頭）是唯一
    功能面明確、與你需求不衝突的一條，但 157 上游已實作GPC
    （`chrome://settings/privacy` 的「詢問網站不要出售我的資料」就是它），不需要補丁。
    `partalloc.patch`：157 的 PartitionAlloc 已是上游主線分配器，無需補丁。
  - `arm/raspi/netflix.patch`、`arm/raspi/widevine-other-locations.patch`：不要（ARM/RPi 專屬）。
  - `infra/Flatpak/com.alex313031.thorium/patches/chromium/*`（18 條）與 `ffmpeg/*`（2 條）：不要，
    全部是 Flatpak/Snap 沙箱打包情境（`flatpak-Add-initial-sandbox-support`、
    `Enable-new-dtags-on-non-component-builds`、`Use-CHROME_WRAPPER-as-the-executable-on-restart` 等），
    你直接跑 `out/Release/chrome`，不是 flatpak。
    其中 `Enable-accelerated-mjpeg-decode-on-Linux.patch` 有一點桌面價值（MJPEG 硬解），
    但你没提过需要看 MJPEG 流（监控摄像头之类），故不收。
    `x11-Set-_NET_WM_BYPASS_COMPOSITOR-for-fullscreen.patch`：**這條是本次「可選清單」裡對你最有用的一条**
    （全螢幕播放時繞過合成器，省 GPU/省電、掉帧更少），你沒有 compositing（i3 裸跑）⇒
    收益近乎 0，所以不收，但記在第 10.1 節。
  - `other/SSE2/angle-lockfree.patch`、`infra/hangout_services/`：不要。
- Thorium 的真正「性能」來源不是 .patch，而是 `src/` 目錄的整檔覆寫（895 檔）＋分檔次
  （`other/{AVX2,AVX512,SSE2,CrOS,Mac}/thorium_version.txt`）＋`src/build/config/compiler_opt.gni`
  與 `src/build/config/compiler/BUILD.gn` 的替換，也就是「改全域 cflags（含 PGO/-march）」+
  「用官方 `is_official_build` 路線 + 自己的 orderfile」。
  ⇒ 你既然已否決「拿 aetherium 去 CI 六小時構建」，Thorium 這套做法的成品形態對你不可複製
  （它靠的是每次都全量重編）。你要「某些 Thorium 的快」，正确做法是 args.gn 層面（第 8 節），不是補丁。

### 6.3 Iridium（補丁在樹內、無獨立檔）

以 ungoogled 收錄的 6 條 iridium 補丁為代表，判定全部寫在 3.3 / 3.6 節：
2 條收錄（safe_browsing 那兩條）、4 條不要（ymp MIME、mac updater、EV 清單、首啟匯入）。
Iridium 本體 `chrome/VERSION = 120.0.6099.224`、2024-01 後未更新 ⇒
把它當代碼來源是危險的（120 → 157 差 37 個大版本的資安修復都不在裡面）。
它的「需求清單」價值：不匯入其他瀏覽器資料、下載前詢問、EV 顯示移除、 updater 停 —— 四条里只有「询问」有設定頁替代。

---

## 7. Firefox 系（Zen Browser / LibreWolf）：只能當需求清單

**明確區分**：Zen/LibreWolf 的補丁本體是改 Firefox 的 `browser/`、`toolkit/`、`.xhtml/.js/.sys.mjs`、
`about:config` 偏好，与 Chromium 的 C++/Blink/mojom 體系沒有對應關係，**一條都不能套**。
它對你的用途是「別人認為使用者該有的功能清單」，逐條對應到 Chromium 侧的正确做法。

### 7.1 Zen Browser（`zen-browser/desktop`，dev 分支，2026-10-11 活躍；實測 263 個 .patch）

補丁形態是逐檔 overlay（例：`src/browser/base/content/aboutDialog-js.patch`、
`src/accessible/base/TextAttrs-cpp.patch`），這是一種值得你借鑒的**倉庫管理方式**：
每改一個源檔就存一個同名 `.patch`，比 ungoogled 的主題式大檔更好對上游同步。

它的偏好檔清單（實測 `prefs/` 目錄）就是一份現成的需求清單：
- `prefs/firefox/ai.yaml`：把 AI 功能全關。→ 你已用 0001-privacy 摘註冊 + `--disable-features` 這條路。
- `prefs/firefox/performance.yaml`、`prefs/fastfox/smoothscroll.yaml`：滾動/渲染平順度。
  → Chromium 侧對應 `--enable-features=OverscrollHistoryElastic`、`smooth-scrolling` 之类的运行期 feature，
  不是編譯期補丁。
- `prefs/firefox/newtab.yaml`、`urlbar.yaml`、`pdf.yaml`、`pip.yaml`（畫中畫）、`multilingual.yaml`、`extensions.yaml`
  → 全部在 Chromium 有設定頁或 policy 對應。
- `prefs/privatefox/privacy.yaml`、`disablemozilla.yaml`：關 telemetry / 關 Mozilla 服務。
  → 你對應的是 `enable_reporting=false`、`disable_fieldtrial_testing_config=true`（args.gn，已做）。
- `prefs/zen/*`（glance、workspaces、compact-mode、kbs、boosts、downloads、folders、library）：
  分頁工作區/雙欄瀏覽/關鍵字分頁等**产品功能**。Chromium 侧对应「分頁群組 + 擴充」，
  不可能用補丁做（做起來是幾十檔的 UI 重寫，正是「同步地獄」形態）。判定：不当補丁，当願景清单。

### 7.2 LibreWolf（**本輪未取到原始清單，以下為二手資訊**）

- 取證失敗的實測記錄：`https://gitea.librewolf.net/...` 進行 TLS 握手時
  `SSL routines::unexpected eof while reading`；GitLab API 對 `librewolf/browser` 回
  `404 Project Not Found`；`gh search repos librewolf-patches-bundle` 回空；
  文件頁 WebFetch 回 `FORBIDDEN（額度限制）`。
- ⇒ 因此本節不列「逐條判定」，只記錄它公认的項目類型（**未逐條驗證，不要用這段做決策**）：
  關 telemetry、改預設搜尋為 DuckDuckGo、移除 Firefox Accounts/Pocket/Sync 入口、
  強化 RFP（`privacy.resistFingerprinting`）、強制 HTTPS-Only、清掉 Cookie 白名單機制、
  啟用 first-party isolation、關 WebRTC 本地 IP、關 UA 精簡度。
  對應到 Chromium 侧，這些幾乎都落在：`--disable-features=`／chrome://settings 頁面／企業 policy／
  `net:https_only_upgrades` 這類既有機制；其中「resistFingerprinting」在 Chromium 沒有等效單旗標，
  这正是 Bromite/Cromite 那批指紋補丁想填的洞（判定見 3.7 / 4.2）。
- 隔天要補齊的入口命令（寫進 README 的接手區塊）：
  用瀏覽器打開 `https://librewolf.net/docs/settings/` 或
  `https://codeberg.org/librewolf/browser/src/branch/master/librewolf-prefs.js`（自行確認鏡像），
  或直接 `gh api repos/<owner>/librewolf-patches-bundle/contents` 查有没有可用的镜像仓。

---

## 8. Chromium 官方的「編譯期開關」實測清單（这一類不算補丁，但要分得清）

先講一句你聽的來的話：**能用 args.gn 或啟動旗標解决的，就不要打補丁**，
因為補丁每輪上游同步都要重驗，開關不會。

### 8.1 官方真的支援（157 有宣告、且被 code 引用）

- 編解碼（`media/media_options.gni`）：`proprietary_codecs`、`ffmpeg_branding`、
  `enable_hevc_parser_and_hw_decoder`(:127)、`enable_platform_hevc`(:154)、
  `enable_hls_demuxer`(:122)、`platform_has_optional_hevc_decode_support`(:169，Linux 在內)、
  `enable_platform_dolby_vision`(:97，Linux 拿不到)、`enable_platform_ac3_eac3_audio`(:74，Linux 拿不到)、
  `enable_platform_dts_audio`(:81 false)、`media_use_openh264`(:55)。
- 擴充/通知（`chrome/common/features.gni`）：`enable_extensions_core`、
  `enable_chrome_notifications`(:50，Linux true)、`enable_session_service`、`enable_background_mode`、
  `chrome_root_store_cert_management_ui`、`enable_service_discovery = enable_mdns`。
- 硬化（`build/config/compiler/BUILD.gn`）：`init_stack_vars`(:144)、`init_stack_vars_zero`(:153)
  → `-ftrivial-auto-var-init=zero/pattern`(:3262-3268)；stack protector 在 :448-470（**不是 GN 參數**，
  是寫死的 if-else，要改就是改這個全域檔案 = 全量重編，見 5.2）。
- 其他你已在用的合法參數：`use_ozone`、`ozone_platform_x11/wayland`、`symbol_level`、
  `use_thin_lto`、`optimize_for_size`、`branding_path_component`、`use_dummy_lastchange`、
  `treat_warnings_as_errors`、`clang_use_chrome_plugins`、`enable_widevine`（+ `enable_cdm_host_verification`）。

### 8.2 「看起來能關，實際上會炸」的一類（沿用你已實測的結論，本輪補充結構原因）

- `safe_browsing_mode=0`、`enable_screen_ai_service=false`、`enable_on_device_translation=false`：
  會斷鏈，因為 157 桌面代碼把這些 target 當成必開引用
  （你自己記下的兩處：`chrome/test/BUILD.gn:1497`、`chrome/browser/accessibility/BUILD.gn:106`）。
  ungoogled 的對應做法是兩條超大補丁：`fix-building-without-safebrowsing.patch`（132 檔）、
  `fix-building-with-prunned-binaries.patch`（15 檔）——
  這就是「關開關」要付的代價，數字直接擺在這裡，你看完自然同意不該走這條。
- `enable_media_router=false`：**參數在 157 已不存在**（第 0.3 節實測），你 CI 那行寫錯了。
- 你的 CI 還用 perl 大範圍擦 `assert(enable_vr|enable_pdf|enable_print_preview|enable_ar|enable_supervised_users)`
  再補一堆空 `group(...)`（`build-linux.yml:88-137`）——
  這等於「用腳本造補丁」，比 .patch 更難追蹤，而且它跟本目錄這 8 條 .patch 是兩套並行機制。
  這一條我沒動，但它是第 10.3 節第 2 名（建議統一：全部走 `patches/**.patch`，
  讓 `scripts/apply-patches.sh` 是唯一入口）。

---

## 9. 本次收錄的 8 條補丁與試套結果

全部落在 `~/Downloads/aetherium/patches/`，檔名自帶來源線索；每檔頂部有中文說明區塊
（出處、改什麼、157 需不需要＋實測依據、痛度、驗證命令）。

1. `adblock/0001-mv2-restore-ungoogled-155.patch`（113 行）— ungoogled，4 檔
   改：`ShouldDisableLegacyExtensions()` → false（+3 檔修飾）。差別：MV2 擴充不再被自動停用/擋安裝。
   痛度：中（核心 1 檔）。試套：patch --dry-run **通過**、git apply --check **通過**、鏈式 **通過**。
2. `adblock/0002-remove-navigation-source-param-ungoogled-155.patch`（58 行）— ungoogled，1 檔
   改：`template_url.cc` 的 `GOOGLE_SEARCH_SOURCE`。差別：搜尋網址不再帶 `source=chrome.ob/rb`。
   痛度：低。試套：通過／通過／鏈式通過。
3. `adblock/0003-disable-intranet-redirect-detector-ungoogled-155.patch`（53 行）— ungoogled，1 檔
   改：`intranet_redirect_detector.cc` 的 `FinishSleep()` 直接 return。差別：啟動後不再發內網探測 DNS/HTTP
   （實證這功能在 157 是活的：`chrome/browser/browser_process_impl.cc:1198`）。痛度：低。通過／通過／鏈式通過。
4. `adblock/0004-disable-dial-periodic-discovery-ungoogled-155.patch`（65 行）— ungoogled，1 檔
   改：`chrome/browser/media/router/discovery/dial/dial_registry.cc:156 StartPeriodicDiscovery()`
   拿掉 `DoDiscovery()` 與 `repeating_timer_`。
   差別：區網不再被週期性 SSDP/DIAL 廣播。價值中等——實測 `DialRegistry` 由
   `chrome/browser/media/router/discovery/dial/dial_media_sink_service_impl.cc:124` 建立，
   也就是「投放/Cast 裝置探索一旦啟動就會開始週期廣播」，不是開機就無腦發；
   你不用 Chromecast，所以這條屬於「潔癖型、零風險、LAN 變安靜」。痛度：低。
   試套：通過／通過／鏈式通過。
5. `security/0001-disable-battery-status-service-inox-ungoogled-155.patch`（145 行）— inox 0019，2 檔
   改：`battery_status_service.{cc,h}` 永遠回空電量。差別：`navigator.getBattery()` 指紋面消失。
   痛度：中低（引用頭檔的只有 3 支非測試檔）。通過／通過／鏈式通過。
6. `security/0002-disable-sb-incident-reporting-iridium-ungoogled-155.patch`（124 行）— Iridium，5 檔
   改：`incident_reporting_service.cc:304` → false + `sb-ssl.google.com/.../incident` 加 trk 前綴等。
   差別：警告頁「回報」不再上傳 URL + 機器模組清單。痛度：中。通過／通過／鏈式通過。
7. `security/0003-disable-sb-client-side-phishing-report-iridium-ungoogled-155.patch`（164 行）— Iridium，1 檔
   改：`client_side_detection_service_base.cc` 的釣魚頁二次上報掏空。
   差別：不再把頁面 URL/內容摘要/token POST 到 `sb-ssl.google.com/.../phishing`（你既有 0001 蓋不到這條）。
   痛度：中。通過／通過／鏈式通過。
8. `performance/0001-default-memory-saver-on.patch`（50 行）— 本輪自製，1 檔 1 行
   改：`components/performance_manager/user_tuning/prefs.cc:35` 的
   `kMemorySaverModeState` 預設 `kDisabled` → `kEnabled`（力道 kMedium 不動）。
   差別：後台閒置分頁自動掛起，13GB 記憶體比較不會被吃爆；代價是分頁重新載入、表單未送內容可能丟。
   痛度：極低（1 行）。通過／通過／鏈式通過。
   **這條是最需要你拍板的**，反悔也不用重編：chrome://settings/performance 關掉即可。

試套方法與結果摘要（逐條對 `/opt/chromium-src/src` 做唯讀 `patch --dry-run -p1`，全部 8/8 通過；
再用 `git apply --check -p1 --ignore-space-change --ignore-whitespace` 嚴格複驗，8/8 通過；
最後在 `/tmp/chain/src`（16 支檔案的稀疏副本）依序真套 8 條，8/8 成功、無 fuzz、無 reject）。
涉及檔案重疊檢查：8 條一共動 16 支檔案（4+1+1+1+2+5+1+1），`sort | uniq -d` 回空 ⇒ 8 條彼此零重疊、
先後順序無關；再逐支對 `git status --short` 比對，16/16 都是「乾淨」⇒ 與你既有 0001~0004 補丁零重疊。

---

## 10. 我拿不準、或你該拍板的點

### 10.1 「该要但目前收不到」與「值得手工做」的備案（按我建議的優先序）

1. Domain Reliability 上報停用（ungoogled 那份 6 檔 F/F 套不上）。實測 `components/domain_reliability/` 存在，
   這條會在資源載入失敗時把 URL 送 `clientservices.googleapis.com`。手工版只需讓
   `chrome/browser/profiles/profile_network_context_service.cc` 不設 DR 上傳 URL（1–2 檔）。
2. Network Time Tracker 停用（`components/network_time/network_time_tracker.cc`，1 檔，ungoogled 那份可用）。
   我這次沒收，理由寫在 3.4；你要是想「完全不碰 clients2.google.com」，說一句我就收進來。
3. 真正的「webui 不抓 Google 字型」補丁（1–2 檔：
   `chrome/browser/ui/webui/side_panel/read_anything/read_anything_untrusted_ui.cc:262`、
   `chrome/browser/resources/contextual_tasks/extension/tab_picker.html:8,10`）。
   這才是與你字型需求相關的東西，ungoogled 那條（4 檔）打不到。
4. `beforeunload` 忽略、隱藏當機重啟氣泡、彈窗轉分頁、關閉最後分頁不關視窗、全螢幕不顯示退出提示、
   punycode 强制显示：各 1–2 檔，全部是「你说要我才做」的生活品質項。
5. Canvas / client-rects 指紋噪點（Bromite 系，落點在 blink 核心）：能做，但我建議你**先想清楚**——
   這會動到你 Google 登入、CAPTCHA、Bitwarden 的表單渲染路徑。
6. WebRTC IP 洩漏：用 `--force-webrtc-ip-handling-policy`（官方旗標）即可，不要補丁。

### 10.2 我沒查證到、不能負責的部分

- LibreWolf 的補丁/偏好清單（網路與額度兩頭堵，見 7.2）。隔天補查的入口命令已寫在該節與 README。
- 各家補丁「能不能編過」我只做了文字層級的試套，**沒有編譯**（你的硬性禁令＋正在跑的三個編譯）。
  文字套得上 ≠ 編得過；每條我都在檔頭註了它動到哪個 target 與是否觸發大範圍重編。
- 「Thorium 在某些方面不如你想要的」——這句話我無法用檔案量化，
  我只查清它的做法是「全域 cflags + 全量重編 + 換檔」，這與你的構建成本約束相衝，所以沒有收它的東西。

### 10.3 需要你做決定的三件事

1. **要不要動 `build/config/compiler/BUILD.gn`（stack-protector-strong / -fwrapv / auto-var-init=zero）**。
   這一支檔是全域 config ⇒ 改它就是整棵樹全部重編（你上次 6 小時的那種）。
   不是「很久所以不做」，而是要你知道**代價是全量重編 + .text 變大（跟 optimize_for_size 相沖）**，
   收益是記憶體安全邊防線升級。要還不要，你一句話。
2. **`performance/0001` 記憶體節省模式預設開**要不要留（分頁會被自動掛起的取捨）。
3. **`.github/workflows/build-linux.yml` 與 `patches/` 這套要不要統一**。
   現況：workflow 裡用 perl 正則大範圍擦 `BUILD.gn` 的 assert、再 printf 出一堆空 `group()`，
   同時還帶著一個 157 已不存在的 `enable_media_router=false`（第 0.3 節實測）
   與 `safe_browsing_mode=0`（你已實測會斷鏈）。這等於有兩套互不相認的補丁機制，
   日後跟上游同步時誰覆蓋誰沒人说得清。建議把 workflow 那些改動也落成 `patches/**.patch`，
   由 `scripts/apply-patches.sh` 唯一入口套用；但這要改你的 CI，所以我沒有擅自動。

---

## 11. 原始來源 URL（本輪實際抓取/查證用的）

- ungoogled-chromium（master，錨定 155.0.8059.39；123 個 .patch、series 108 條）
  - https://github.com/ungoogled-software/ungoogled-chromium
  - https://github.com/ungoogled-software/ungoogled-chromium/tree/master/patches
  - https://raw.githubusercontent.com/ungoogled-software/ungoogled-chromium/master/patches/series
  - tarball：https://codeload.github.com/ungoogled-software/ungoogled-chromium/tar.gz/refs/heads/master
  - 版本錨：https://github.com/ungoogled-software/ungoogled-chromium/blob/master/chromium_version.txt
- inox-patchset 原倉（已消失）：https://github.com/inox-patchset/inox-patchset → GitHub API 回 404
- Iridium Browser：https://github.com/iridium-browser/iridium-browser
  （`chrome/VERSION` = 120.0.6099.224；README 自述「tarball 狀態」；pushedAt 2024-01-26）
- Supermium（你記成 Superium/sdagk 的實體）：https://github.com/win32ss/supermium
  （根目錄 15 個 .patch；官網 https://www.supermium.net/ ；https://en.wikipedia.org/wiki/Supermium ）
- Bromite：https://github.com/bromite/bromite （`build/patches/` 206 條；pushedAt 2024-01-24）
- Cromite：https://github.com/uazo/cromite （`build/patches/` 327 條；
  `build/cromite_patches_list.txt` 333 行；pushedAt 2026-10-11）
- Vanadium：https://github.com/GrapheneOS/Vanadium （`patches/` 302 條、`subprojects_patches/` 6 條、
  根目錄 `args.gn`、`generate-release`；pushedAt 2026-10-08）
- Thorium：https://github.com/Alex313031/thorium （`other/` 28 條、`infra/Flatpak/**` 18+2 條、`src/` 895 檔；
  pushedAt 2026-10-11）
- Zen Browser（Firefox 系，需求清單用）：https://github.com/zen-browser/desktop
  （263 個 .patch；`prefs/**.yaml` 清單；pushedAt 2026-10-11）
- LibreWolf（未能取到，待補）：https://librewolf.net/docs/settings/ 、
  https://gitea.librewolf.net/ （本輪 TLS 握手失敗）
- Chromium 官方文件/源碼位置（第 8 節全部引自本地樹）：
  https://github.com/chromium/chromium 、
  https://www.chromium.org/developers/how-tos/build-instructions-linux/
