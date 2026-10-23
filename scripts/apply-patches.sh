#!/usr/bin/env bash
# aetherium 補丁系列套用腳本。
#
# 用法：
#   在源碼樹裡跑（例：cd /opt/chromium-src/src）
#     ~/Downloads/aetherium/scripts/apply-patches.sh          # 套用
#     ~/Downloads/aetherium/scripts/apply-patches.sh --dry-run # 只回報狀態，不動樹
#
# 2026-10-22 修正：舊版某支補丁失敗時只印一行就 exit，後面的補丁整批被跳過卻看不出來
# （adblock/0003 過時那次，trim/ 兩支整個沒套）。現在會印「已套／新套／未套」三張清單，
# 並用 ::error:: 讓 GitHub Actions 標紅。
#
# 2026-10-23 修正：補丁「已經在樹上」時原本會報「套用失敗」（因為 git apply --check
# 看的是「能不能再套一次」，重複套用必然衝突），導致第二輪跑一定不綠。
# 現在先用 git apply --reverse --check 判别「已套用」，這類補丁直接跳過、不算錯誤，
# 所以本腳本可重複執行（冪等）。真套不上去的才失敗。
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

mapfile -t patches < <(find "$patch_dir" -type f -name '*.patch' | sort)

already=()   # 樹上已有這支的內容（跳過）
applied=()   # 這輪新套上去的
total="${#patches[@]}"

for i in "${!patches[@]}"; do
  patch="${patches[$i]}"
  printf '\n檢查補丁：%s\n' "$patch"
  if git apply --reverse --check --ignore-space-change --ignore-whitespace "$patch" 2>/dev/null; then
    printf '  狀態：已在樹上（跳過，不重複套用）\n'
    already+=("$patch")
  elif git apply --check --ignore-space-change --ignore-whitespace "$patch" 2>/dev/null; then
    if [ "$dry_run" -eq 1 ]; then
      printf '  狀態：可乾淨套用（dry-run，未實際寫入）\n'
      applied+=("$patch")
    else
      git apply --index --ignore-space-change --ignore-whitespace "$patch"
      printf '  狀態：已套用\n'
      applied+=("$patch")
    fi
  else
    # 既不在樹上、也套不下去 ⇒ 補丁與上游現況衝突，必須修補丁，不可繞過。
    remaining=("${patches[@]:$((i + 1))}")
    printf '::error::補丁套用失敗（與上游衝突）：%s\n' "$patch"
    printf '已在新樹上（跳過）%d 支：\n' "${#already[@]}"
    printf '  %s\n' "${already[@]:-（無）}"
    printf '本輪已新套 %d 支：\n' "${#applied[@]}"
    printf '  %s\n' "${applied[@]:-（無）}"
    printf '未套用 %d 支（含這一支本身）：\n' "${#remaining[@]}"
    printf '  %s\n' "${remaining[@]:-（無）}"
    printf '修法：對照上游現況重新產生這一支（git diff 產生後用 git apply --check 驗），\n'
    printf '      或確認該功能已被上游移除後把這支刪掉。\n'
    exit 1
  fi
done

printf '\n總結：補丁共 %d 支｜本輪新套 %d 支｜原本已在樹上 %d 支\n' \
       "$total" "${#applied[@]}" "${#already[@]}"
if [ "$dry_run" -eq 1 ]; then
  printf '（dry-run：樹未變動）\n'
fi
printf '全部補丁狀態正常。\n'
