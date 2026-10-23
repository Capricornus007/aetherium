# aetherium

你自己编的 Chromium 浏览器的产品名（一律全小写 aetherium）。这个仓库放的是「打算往源代码里打的补丁」
和「这些补丁该不该打的清查报告」，不放浏览器源代码。

源代码树在 `/opt/chromium-src/src`，版本 157.0.8095.0（读的是 `chrome/VERSION`）。
本仓库与那棵树是分开两回事：**这里只有补丁文字档和说明，动到源码要靠你（或代理）主动执行套用步骤。**

---

## 一、现况（2026-10-12 这一轮做完的事）

- `docs/patch-inventory.md`：把别家（ungoogled-chromium、Iridium、Supermium、Bromite、Cromite、
  Vanadium、Thorium、Zen、LibreWolf）为自家 Chromium 分支写的补丁全部盘了一遍，
  每一条都写了三行判定（改什么 / 在 157 需不需要 + 实测证据 / 套下去要动几个档案、日后跟上游同步痛不痛）。
  ungoogled 的 108 条（series 档案 110 行）是**逐条**用只读方式在你的源码树上试过套的，通过与否都记进报告。
- `patches/` 下面这次真的放了 8 个补丁档（其余分类目录维持空，理由写在报告第 5.4 节）：
  - `patches/adblock/` 4 条：MV2 扩展救回、去掉搜索 URL 的追踪参数、关内网探测、关 DIAL 周期性广播
  - `patches/security/` 3 条：电池指纹、Safe Browsing 事件回报、Safe Browsing 钓鱼页二次上报
  - `patches/performance/` 1 条：内存节省模式默认打开
  - `patches/android/` 空
- 这 8 条全部做过三种检查：个别 `patch --dry-run`、个别 `git apply --check`、
  以及在 `/tmp` 的稀疏副本里依序真套一遍（证明它们可以同时存在、不互相冲突）。
  详细结果在报告第 9 节。

有一条需要你先知道，因为它跟你原本的认知不同（证据在报告第 0.1 节，都带档案与行号）：

> 你以为「157 里 MV2 扩展不用补丁就能用」。实际上 `extensions/common/extension.cc:60` 那个
> `kMinimumSupportedManifestVersion = 2` 只管「manifest 能不能解析」，
> 不管「扩展会不会被启用」。真正动手的是
> `extensions/browser/manifest_v2_handler.cc:111-118` 的 `ShouldDisableLegacyExtensions()`，
> 它在 157 桌面版**无条件 return true**，而 `OnExtensionSystemReady()`（同档 :196-199）
> 会在浏览器一启动就把所有 MV2 扩展标记停用、并且挡住 MV2 的安装。
> 没有企业政策、没有 about:flags 开关能绕过（查过 `chrome/browser/policy/`、`components/policy/`）。
> 所以要留 MV2 扩展，`patches/adblock/0001-...patch` 是必须的。

另外两条实测结论（不用打补丁就能省事的）：

- HEVC/H.265 在 157 的 Linux 已经是上游默认开启（`media/media_options.gni:127-129,154-156,169-171`），
  Thorium/Bromite/Cromite 那些「加 HEVC」的补丁在你这条线上完全不需要。
  JPEG XL 也是（`third_party/blink/renderer/platform/image-decoders/jxl/` 目录实际存在，上游已还原）。
- 扩展通知进 dunst 也不需要补丁：157 有原生 freedesktop D-Bus 通知桥
  （`chrome/browser/notifications/notification_platform_bridge_linux.cc`），
  且 `kNativeNotifications`、`kSystemNotifications` 两个 feature 默认就是开
  （`chrome/common/chrome_features.cc:1488,1506`）。

---

## 二、怎么逐条验收（不懂程序也能照做，一条一条来）

下面每一段都可以直接贴进终端执行。除了「第 5 步」之外，全部是**只读**的，不会改到任何档案。

### 第 0 步：先确认树的版本跟你的认知一致

    cat /opt/chromium-src/src/chrome/VERSION
    ls /opt/chromium-src/src/out/Release

要看到 `MAJOR=157`。如果这里的数字变了（例如升到 158），
下面所有试套结果都要重跑一次，因为补丁是按 157 的档案内容核对的。

### 第 1 步：逐条做「只读试套」，看会不会冲突

先做宽松版（GNU patch）：

    cd /opt/chromium-src/src
    for f in $(find ~/Downloads/aetherium/patches -name '*.patch' | sort); do
      printf '\n=== %s\n' "$f"
      patch -p1 --dry-run --batch -N -g0 -i "$f"
    done

再做严格版（这才是你仓库里 `scripts/apply-patches.sh` 实际用的判断方式）：

    cd /opt/chromium-src/src
    for f in $(find ~/Downloads/aetherium/patches -name '*.patch' | sort); do
      printf '%-70s ' "$(basename "$f")"
      if git apply --check -p1 --ignore-space-change --ignore-whitespace "$f" 2>/dev/null; then
        echo 可套
      else
        echo 冲突; git apply --check -p1 --ignore-space-change --ignore-whitespace "$f"
      fi
    done

怎么看结果：
- 「可套」= 这档补丁能原样落到 157 的档案上。这次 8 条应该全部「可套」。
- 「冲突」+ 后面列出某个档案名 = 上游改动让上下文对不上了。
  这时候不要硬套，把冲突的档案名回报给代理，改法通常就是把补丁里那一行手动改到源码上
  （每条补丁的头部都写了「真正的核心改动只有哪一行」）。

`--dry-run` 的意义：GNU patch 只做「假装套用」的比对，不写档、不留备份、不建目录。

### 第 2 步：确认这 8 条互不撞车

每条补丁动了哪些档案，写在各自档头。这次 8 条一共动 16 个档案，彼此没有交集，
所以先后顺序无所谓。要机器验证这一点：

    for f in $(find ~/Downloads/aetherium/patches -name '*.patch' | sort); do
      grep '^--- a/' "$f" | sed 's#^--- a/##'
    done | sort | uniq -d

回传空白（没有任何一行输出）就是没有重复档案。

### 第 3 步：真套（会动到源代码树，做完就要决定编不编）

这一步开始**会写档**。要动手前建议先照你自己的规矩，把树的状态留个退路：

    cd /opt/chromium-src/src
    git diff --stat | tail -3          # 看看目前已有多少本地改动（你的品牌化补丁）

然后依序套（用你仓库里现成的脚本，它是唯一入口，套不上会自己停下来不会半套）：

    bash ~/Downloads/aetherium/scripts/apply-patches.sh

这个脚本用 `find ... | sort`，实际顺序是：`adblock/0001..0004` →
`performance/0001` → `security/0001..0003`，且它会 `git apply --index`（套完顺便进暂存区）。

反悔（把补丁改动全部丢掉，但会连你原来的品牌化改动一起丢，**不要**在这棵树上用）：
所以正确做法是「先只套新的这批」，要退回就逐条反向：

    cd /opt/chromium-src/src
    patch -p1 -R -i ~/Downloads/aetherium/patches/adblock/0001-mv2-restore-ungoogled-155.patch

（每条档头都有它的路径，把 `-R` 加进去就是撤销。）

### 第 4 步：套完怎么知道有没有效果（挑 3 条能一眼看的）

- MV2 那条：套完可以用 grep 直接看代码变成什么（只读）：

      sed -n '108,116p' /opt/chromium-src/src/extensions/browser/manifest_v2_handler.cc

  要看到 `bool ShouldDisableLegacyExtensions() {` 下面只有 `return false;`。
  真正的使用验证要等浏览器编好之后：打开 `chrome://extensions`，
  你的 MV2 扩展不应出现「不受支援/已停用」；没编之前这一步只能先看代码。
- 搜索追踪参数那条：编好之后从位址列搜 Google，看结果网址里还有没有 `source=chrome.ob`。
- 电池指纹那条：编好之后开浏览器控制台执行 `await navigator.getBattery()`，
  拿到的应该是 `charging: true, level: 1` 的固定值（而不是你笔电真的电量）。
  这一类「要跑起来才看得到」的验证，都必须等重新编译之后，急不得。

### 第 5 步：要不要重编、编多久（讲实数，不含糊）

- 这 8 条一共动 16 个档案，其中只有 `security/0001`（电池）动了 1 个头文件
  （`services/device/battery/battery_status_service.h`），
  而实测引用这个头文件的非测试档案只有 3 个（`services/device/device_service.cc`、
  `battery_monitor_impl.h`、`battery_status_manager.h`）。
- 也就是说：**没有一条会强迫整棵树重编**。要重编的是这 16 个编译单位 + 重新链接 chrome 可执行档。
  （真正花时间的是最后那个链接步骤，以及链接器/磁盘；这个跟你是否开 ccache 有关。）
- 相对的，报告第 10.3 节第 1 名那件事（改 `build/config/compiler/BUILD.gn` 换
  `-fstack-protector-strong`／`-fwrapv`／`init_stack_vars_zero`）**才会造成全量重编**，
  因为那是挂在每个目标上的全局 config（`build/config/BUILDCONFIG.gn:370-381`）。
  这类要不要做，由你拍板，不是代理替你先做掉。

### 第 6 步：性能那条（内存节省）要不要留

套上去之后第一次开浏览器：

1. 打开 `chrome://settings/performance`，看「内存节省」是不是已经被打开了
   （补丁做的就是把这个开关的出厂值从关改成开）。
2. 开十几个分页，放着别动，几分钟后看哪些分页变淡/被挂起。
3. 如果觉得受不了（怕丢表单内容），不用重新编译就能反悔：把那个开关关掉就好
   ——它写的就是同一个偏好（`performance_tuning.high_efficiency_mode.state`）。
4. 建议顺手把 floccus 同步用的网页、网页版 Bitwarden 之类的分页加进
   「始终不悬挂以下站点」白名单，避免同步跑到一半被挂起。

---

## 三、你该拍板的三件事（这一轮代理不敢替你决定的）

1. 要不要改 `build/config/compiler/BUILD.gn`（stack protector strong、`-fwrapv`、
   `init_stack_vars_zero = true`）。这三个都能用 args.gn 或改一行全局 config 做到，
   代价都是**整棵树重编**，`.text` 也会变大（跟你现在 `optimize_for_size = true` 的方向相冲）。
2. `patches/performance/0001`（内存节省默认开）要不要留着。取舍说明见上面第 6 步。
3. `.github/workflows/build-linux.yml` 现在是用 perl 正则大面积擦 `BUILD.gn`、
   再用 printf 生一堆空 `group()`，跟这个仓库的 `patches/*.patch` 是两套并行、互不相认的机制；
   而且那行 `gn gen --args` 里写了 `enable_media_router=false`——实测 157 全树已经没有这个 GN 参数了
   （`chrome/`、`components/`、`services/`、`content/`、`build/` 的 `*.gni` 都找不到宣告），
   同时 `safe_browsing_mode=0` 也是你已经实测会断链的那条路。
   建议统一成「一律走 patches/ + scripts/apply-patches.sh 这个入口」，但改你的 CI 要你说一句。

## 四、这一轮没查到的东西（不要当成已确认）

- LibreWolf 的补丁/偏好清单没拿到：`gitea.librewolf.net` TLS 握手失败、GitLab API 回 404、
  GitHub 搜 `librewolf-patches-bundle` 空结果、文件页抓取被额度挡。
  隔天补查入口：`https://librewolf.net/docs/settings/`。
- 各家补丁「套得上 ≠ 编得过 ≠ 跑得动」：这一轮按你的禁令没有编译任何东西，
  所有结论都是文字层 + 源码阅读层。要落实必须编一次。
- 你现在有没有真的在用 MV2 扩展，代理没查（不能碰你的 profile）。
  你自己开 Thorium 的 `chrome://extensions` 看一眼各扩展的 manifest 版本即可；
  只要有任一个是 MV2，`patches/adblock/0001` 就是必须项。

## 五、下一次接手的入口命令

    cat /opt/chromium-src/src/chrome/VERSION
    git -C /opt/chromium-src/src status --short | wc -l
    find ~/Downloads/aetherium/patches -name '*.patch' | sort
    # 逐条只读试套（第 1 步的两个 for 循环，复制即跑）
    # 完整判定与证据：~/Downloads/aetherium/docs/patch-inventory.md

---

## 六、2026-10-23 追記（裁剪 trim 收尾，本輪實際狀態）

- 補丁數現為 **14 支**（上面第一節寫的 8 支是 10-12 那輪的舊數字，10 支是 10-23 第一輪）：
  第一輪新增 `patches/trim/0001-disable-printing-pdf-screenai-cast.patch`（26 個 BUILD.gn）與
  `patches/trim/0002-headless-ozone-autodetect.patch`（2 檔）；第二輪（10-23）新增
  `patches/branding/0001-theme-aetherium-icons.patch`（73 檔，品牌圖示＋BRANDING）、
  `patches/branding/0002-branding-rename-aetherium.patch.gz`（858 檔，Chromium→aetherium 全部
  改名：grit 字串 849 檔 63,419 處＋輸出檔名＋`aetherium.desktop`＋`~/.config/aetherium`）、
  `patches/trim/0003-disable-on-device-translation.patch`（解掉上游那條 assert，讓
  `enable_on_device_translation=false` 真的關得掉）與
  `patches/privacy/0001-local-privacy-and-ai-surface-trims.patch`（16 檔，把舊 0004 mega-patch 裡
  跟品牌無關的隱私／AI 改動搬進補丁系列）。14 支全部從乾淨樹重跑過、彼此不碰同一個檔案，
  套完 `gn gen` rc=0（35,877 targets）。
  並用「收乾淨再從零套一次」證明瞭逐位元組可重現。
- `scripts/apply-patches.sh` 改成**冪等**（先判「已在樹上」就跳過）並新增 `--dry-run`，
  所以第二輪跑不再假報失敗。
- 正式 args.gn 定稿在 `/opt/chromium-src/src/out/Aetherium/args.gn`，44 條自訂 key
  逐條對過 `gn args --list --short`（實測 1260 條真 arg，查無打錯字）；
  `gn gen` 成功（35,918 目標）。
- 全部結論、邊數實測、檔案:行號、以及「還剩什麼（含品牌化 0004 補丁衝突）」寫在
  **`~/Downloads/aetherium/TRIM-NOTES.md`**，那份才是裁剪這條線的權威紀錄。

