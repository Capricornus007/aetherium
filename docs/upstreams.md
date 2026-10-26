# aetherium 上游追蹤清單（用戶 2026-10-26 裁定）

aetherium 是基於 Chromium 的自編瀏覽器。它的「上游」不止 Chromium 官方源碼——
凡是能提供可借鑑補丁／特性／設定的同源分支，都在追蹤範圍內。
本檔是權威清單；`patches/UPSTREAM_BASE` 只釘 Chromium 官方基準 commit，兩者互補。

## 一、核心基準
- **Chromium 官方**：`chromium.googlesource.com/chromium/src`（源碼樹在 `/opt/chromium-src/src`，
  版本讀 `chrome/VERSION`；目前 157.0.8095.0）。`patches/UPSTREAM_BASE` 記的就是這顆基準 hash。

## 二、要追的 Chromium 系分支（包括但不限于）
| 專案 | 倉庫 | 追它的理由／能拿到什麼 |
|---|---|---|
| Bromite | `bromite/bromite` | 隱私/去广告補丁系列、F-Droid 版构建经验 |
| Cromite | `UngluedCromite/cromite`（含 `cromite/www`） | Bromite 后继，Android 端補丁、syslib 策略 |
| Brave | `brave/brave-core` | **adblock_rust（攔截引擎）**、隐私/盾牌、Brave 自有功能 |
| Titanium | 現行 Titanium 瀏覽器倉（Titanium/TitaniumBrowser） | 老舊 Web 兼容、UA 策略（Supermium 同類） |
| Helium | `Chromium-Helium/helium`（Chromium 衍生） | 极客向精簡與隱私取向 |
| Vanadium | `GrapheneOS/Vanadium` | 安全加固、Android WebView/瀏覽器安全預設 |
| Thorium | `alex313031/thorium`（主線）＋ `gz83` 的 thorium 重建（含 SIMD/編譯旗標變體） | 性能編譯取向、X86-64-v3 等優化 |
| 其他 | ungoogled-chromium、Iridium、Supermium、Zen、LibreWolf 等 | 既有 `docs/patch-inventory.md` 已盤過的對象，持續納入 |

> 以上為「包括但不限于」——新出現的、有可借鑑補丁的 Chromium 分支，經查證後追加進本清單。

## 三、追蹤機制（如何「吃」這些上游）
1. **補丁清查**：定期（或手動觸發）比對各倉庫相對於上次清查點的新補丁／設定變更，
   逐條寫進 `docs/patch-inventory.md` 的三行判定（改什麼／aetherium 需不需要＋實測證據／套下去動幾個檔、日後同步痛不痛）。
2. **緊耦合件不退尖端**：adblock_rust 這類被 aetherium 強依賴的元件，跟 `~/Downloads` 既有配套版本，
   不盲跳尖端（用戶規則 46）。
3. **CI 釘基準**：`patches/UPSTREAM_BASE` 釘 Chromium 官方 commit；本清單的各分支以「參考來源」身分存在，
   不直接進 build，避免混入未審查改動。
4. 具體落地（把清單接進 CI drift 檢查、自動抓各倉最新補丁做清查）屬 #56「aetherium 補丁整理輪」的執行範圍。
