#!/usr/bin/env bash
# aetherium 補丁系列套用腳本。
#
# 用法：
#   在源碼樹裡跑（例：cd /opt/chromium-src/src）
#     ~/Downloads/aetherium/scripts/apply-patches.sh           # 套用
#     ~/Downloads/aetherium/scripts/apply-patches.sh --dry-run # 只回報狀態，不動樹
#
# `patches/series` 是唯一順序來源。每支補丁都必須整支通過 `git apply --check`；
# 不拆檔、不猜測「部分已套」，避免產生不屬於任何已知版本的混合樹。
# 請在 `patches/UPSTREAM_BASE` 的乾淨 checkout 執行；重複執行會明確失敗。
#
# 2026-10-23（同日第二版）：支援 .patch.gz。品牌改名那支原文 30MB，超過 GitHub
# 單一檔 25MB 軟上限，改存 gzip（5.1MB）；套用前先解到暫存檔，結束一定刪。
set -euo pipefail

dry_run=0
if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
  dry_run=1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
patch_dir="$repo_root/patches"

if [ ! -d "$patch_dir" ]; then
  echo "Patch directory not found: $patch_dir"
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "目前目錄不是 git 倉庫。請先 cd 到源碼樹（/opt/chromium-src/src）再跑本腳本。"
  exit 1
fi
printf '目標倉庫：%s\n' "$(git rev-parse --show-toplevel)"

series_file="$patch_dir/series"
if [ ! -f "$series_file" ]; then
  echo "Patch series not found: $series_file"
  exit 1
fi

patches=()
declare -A listed=()
while IFS= read -r entry; do
  entry="${entry%$'\r'}"
  case "$entry" in
    ""|'#'*) continue ;;
    /*|../*|*/../*|*/..) echo "Invalid patch path in series: $entry"; exit 1 ;;
    *.patch|*.patch.gz) ;;
    *) echo "Invalid patch suffix in series: $entry"; exit 1 ;;
  esac
  if [ -n "${listed[$entry]:-}" ]; then
    echo "Duplicate patch in series: $entry"
    exit 1
  fi
  if [ ! -f "$patch_dir/$entry" ]; then
    echo "Listed patch not found: $entry"
    exit 1
  fi
  listed[$entry]=1
  patches+=("$patch_dir/$entry")
done < "$series_file"

while IFS= read -r entry; do
  if [ -z "${listed[$entry]:-}" ]; then
    echo "Patch is not listed in series: $entry"
    exit 1
  fi
done < <(find "$patch_dir" -type f \( -name '*.patch' -o -name '*.patch.gz' \) \
           -printf '%P\n' | sort)

applied=()   # 這輪新套上去的
failed=()    # 套不下去（與上游衝突或樹不乾淨）
total="${#patches[@]}"

tmp_patch=""
cleanup() { rm -f "${tmp_patch:-}"; }
trap cleanup EXIT

for i in "${!patches[@]}"; do
  patch="${patches[$i]}"
  cleanup
  tmp_patch=""
  if [ "${patch##*.}" = "gz" ]; then
    tmp_patch="$(mktemp --suffix=.patch)"
    gunzip -c "$patch" > "$tmp_patch"
    target="$tmp_patch"
  else
    target="$patch"
  fi

  printf '\n檢查補丁：%s\n' "$patch"
  if git apply --check --ignore-space-change --ignore-whitespace "$target" 2>/dev/null; then
    if [ "$dry_run" -eq 1 ]; then
      printf '  狀態：可乾淨套用（dry-run，未實際寫入）\n'
      applied+=("$patch")
    else
      git apply --index --ignore-space-change --ignore-whitespace "$target"
      printf '  狀態：已套用\n'
      applied+=("$patch")
    fi
  else
    # A listed patch is an atomic unit. Never split it by file: doing so can
    # silently create a tree that corresponds to neither side of the patch.
    printf '::error::補丁套用失敗（與上游衝突）：%s\n' "$patch"
    failed+=("$patch")
  fi
done
cleanup

printf '\n總結：補丁共 %d 支｜本輪新套 %d 支｜失敗 %d 支\n' \
       "$total" "${#applied[@]}" "${#failed[@]}"
printf '本輪新套：%s\n' "${applied[*]:-（無）}"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '套用失敗：%s\n' "${failed[*]}"
  printf '修法：對照上游現況重新產生這一支（git diff 產生後用 git apply --check 驗），\n'
  printf '      或確認該功能已被上游移除後把這支刪掉。\n'
  exit 1
fi
if [ "$dry_run" -eq 1 ]; then
  printf '（dry-run：樹未變動）\n'
fi
printf '全部補丁狀態正常。\n'
