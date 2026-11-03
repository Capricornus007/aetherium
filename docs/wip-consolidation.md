# 2026-11-03 rebase/WIP 收斂紀錄

這份紀錄把暫存工作樹 `/tmp/aetherium-rebase2` 的四顆獨有 commit 與 staged index，逐一對到
`patches/UPSTREAM_BASE` 與正式 patch。機器可讀的 commit/tree、patch-id、index diff SHA-256、
21 支對應 patch 的 SHA-256 都固定在 [`patches/WIP_ARCHIVE`](../patches/WIP_ARCHIVE)。因此刪除暫存
工作樹前，不需要依賴 `/tmp` 裡的名稱、reflog 或未提交 index 來保留產品行為。

## 結論

- **缺漏：0。** 四顆 commit 與 staged index 的所有有意義變更，都已有正式 patch。
- **重複新增：0。** 本輪不新增 patch，也不把 staged diff 再包成第四支 tab-group patch。
- **過時內容：1 個 hunk。** `192dbe30267dc` 在 `chrome/browser/BUILD.gn` 對
  `access_code_sink_service` 的舊式無條件依賴，已被正式 `trim/0001` 的
  `enable_service_discovery` 條件化寫法取代；不能把舊 hunk 蓋回去。
- `patches/series` 現有 **23 支**：本次 WIP 映射其中 21 支；另外兩支
  `branding/0005-product-vector-icons.patch` 與 `deps/webrtc/0001-append-dummy-audio-define.patch`
  是之後在正式倉加入的工作，不源自這條 WIP chain。
- `.github/workflows/` 維持沒有 cloud build workflow；本輪沒有恢復任何 workflow。

## 逐項分類

| WIP 物件 | 相對前一顆的範圍 | 分類 | 正式表示 |
|---|---:|---|---|
| `df42009a09386` | 938 files | 已表示 | `adblock/0001..0004`、`branding/0001..0002` |
| `4cbe66f9a4849` | 172 files | 已表示，逐 tree 相同 | `branding/0003-product-layer-aetherium.patch` |
| `192dbe30267dc` | 58 files | 已表示；一個舊 Cast hunk 已淘汰 | `branding/0004`、performance 1、privacy 2、security 3、`trim/0001..0003` |
| `e57559a36481f` | 54 files | 已表示，逐 tree 相同 | `trim/0005-deep-trim-asserts-and-deps.patch` |
| staged index on `e57559a` | 20 files | 已表示，逐 tree 相同 | `trim/0007`、`trim/0008`、`trim/0009` |

Tab-group staged index 的 20 個檔案包括：停用建立／還原／context menu、停用 saved/shared group
sync controllers，以及從 BUILD graph 和 source tree 刪除 `tab_group_dynamic_menu.{cc,h}`。它不是遺失的
第 24 支 patch；把正式 `trim/0007`、`0008`、`0009` 依 series 順序套到 `e57559a`，會得到與 staged
index 完全相同的 tree `67f9225d72d98891dc3bfecc481fb8a8ec4cc5ae`。

## 比對方法與可重現證據

基準是 `patches/UPSTREAM_BASE`：
`6ac1da15572a0e79814c92a86b8430805f9def04`，tree
`ba00aa05bae0730ab2191813283710c573bdd51e`。比對使用獨立 temporary index/object directory；不改
Chromium worktree。結果如下：

1. 從基準依序套 `adblock/0001..0004`、`branding/0001..0002`，tree 等於
   `df42009` 的 `7bfedbb4d78b0765444f905d9f89cd123510573f`。
2. 在 `df42009` 上套 `branding/0003`，tree 等於 `4cbe66f` 的
   `48ac1f6d254e62ff8e4681589214b17e14f3aa60`。
3. 在 `4cbe66f` 上套表中的十支正式 patch，與 `192dbe3` 只差
   `chrome/browser/BUILD.gn` 的 Cast dependency 改良；其餘逐 tree 相同。
4. 在 `192dbe3` 上套 `trim/0005`，tree 等於 `e57559a` 的
   `481c1544502c5e97c7e351c6cf61c881bf75a223`。
5. 在 `e57559a` 上依序套 tab-group 三支 patch，tree 等於 staged index 的
   `67f9225d72d98891dc3bfecc481fb8a8ec4cc5ae`。

`patches/WIP_ARCHIVE` 還固定 staged binary diff SHA-256
`44f16e6fcfdd8e43ecb87ab1123a0b006bcddce321b2c62b040d69222ec19d0d`，以及每支正式 patch 的
SHA-256。日後要移除 `/tmp/aetherium-rebase2`，應先確認 manifest 中的 21 個 `sha256` 條目仍與檔案
一致；如果正式 patch 曾有意更新，必須同步更新本紀錄並重做 tree mapping，而不是把舊 WIP 復活。
