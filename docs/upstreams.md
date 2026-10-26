# aetherium 補丁來源清單（用戶 2026-10-26 裁定）

**先講清楚性質**：aetherium 是一個「補丁倉」——本倉只放「打算往 Chromium 源碼打的補丁」與
「這些補丁該不該打的清查報告」（見 README 與 `docs/patch-inventory.md`），不放瀏覽器源碼。
源碼樹在 `/opt/chromium-src/src`（版本讀 `chrome/VERSION`，目前 157.0.8095.0）。

所以本清單**不是「git 上游追蹤」**（aetherium 不會去 merge 下面任何一個倉的提交歷史），
而是「**補丁研讀來源**」：從這些同源 Chromium 分支裡，把值得借鑑的補丁／設定／特性挖出來，
逐條判定後決定要不要變成 aetherium 自己的補丁。這正是 `docs/patch-inventory.md` 在做的事。

## 一、源碼基準（唯一真正「跟版本」的對象）
- **Chromium 官方**：`chromium.googlesource.com/chromium/src`。`patches/UPSTREAM_BASE` 釘的就是
  這顆官方 commit hash——這是 aetherium 補丁「往哪份源碼上打」的基準，不是要 merge 的上游。

## 二、補丁研讀來源（包括但不限于）
| 專案 | 倉庫 | 從它那裡挖什麼 |
|---|---|---|
| Bromite | `bromite/bromite` | 隱私／去廣告補丁系列 |
| Cromite | `UngluedCromite/cromite` | Bromite 後繼，Android 端補丁、syslib 策略 |
| Brave | `brave/brave-core` | **adblock_rust（攔截引擎）**、盾牌、自有功能 |
| Titanium | Titanium 瀏覽器倉 | 老舊 Web 兼容、UA 策略 |
| Helium | Chromium-Helium | 精簡與隱私取向 |
| Vanadium | `GrapheneOS/Vanadium` | 安全加固、Android 安全預設 |
| Thorium | `alex313031/thorium` ＋ `gz83` 的重建變體 | 性能編譯旗標、X86-64-vN 優化 |
| 其他 | ungoogled-chromium、Iridium、Supermium、Zen、LibreWolf… | `patch-inventory.md` 已盤過的對象，持續納入 |

> 「包括但不限于」——新出現的、有可借鑑補丁的 Chromium 分支，查證後追加進本清單。

## 三、用法（如何「吃」這些來源）
1. 定期或手動比對各倉相對於上次清查點的新補丁／設定變更，逐條寫進 `docs/patch-inventory.md`
   的三行判定（改什麼／aetherium 需不需要＋實測證據／套下去動幾個檔、日後同步痛不痛）。
2. 緊耦合件（如 adblock_rust）跟 `~/Downloads` 既有配套版本，不盲跳尖端（規則 46）。
3. 這些來源**不直接進 build**；只有經過 patch-inventory 判定「要打」的，才落成 `patches/` 下的補丁檔。
4. 具體落地（自動抓各倉最新補丁做清查、CI drift 檢查）屬 #56「aetherium 補丁整理輪」執行範圍。
