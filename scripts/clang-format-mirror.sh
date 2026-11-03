#!/usr/bin/env bash
# 以經過物件身分驗證的本機鏡像，取代 clang-format 的故障 googlesource 端點。
set -euo pipefail

readonly default_upstream='https://chromium.googlesource.com/external/github.com/llvm/llvm-project/clang/tools/clang-format.git'
readonly default_mirror='https://github.com/chromium-full-mirror/external_github.com_llvm_llvm-project_clang_tools_clang-format.git'
readonly default_trusted_objects='9f796802e5d633c96dbe97e0b6683d5e62594f9f:5f33aa6fa9d255066a8d13ed0135ae5ac67c75a6
842084dbd4b0f205c9d014f0e129c139aa5ac517:75f3297d2edb638a533aebdb42fb8d269d8ed591'

upstream="${CLANG_FORMAT_UPSTREAM_URL:-$default_upstream}"
mirror="${CLANG_FORMAT_MIRROR_URL:-$default_mirror}"
trusted_objects="${CLANG_FORMAT_TRUSTED_OBJECTS:-$default_trusted_objects}"

usage() {
  cat <<'EOF'
用法：
  clang-format-mirror.sh setup  <bare-cache-path>
  clang-format-mirror.sh verify <chromium-src-path> <bare-cache-path>
EOF
}

fail() {
  printf '::error::clang-format 鏡像：%s\n' "$*" >&2
  exit 1
}

trusted_tree() {
  local wanted="$1" revision tree
  while IFS=: read -r revision tree; do
    if [ "$revision" = "$wanted" ]; then
      printf '%s\n' "$tree"
      return 0
    fi
  done <<< "$trusted_objects"
  return 1
}

validate_trusted_objects() {
  local cache="$1" revision expected_tree actual_revision actual_tree count=0
  while IFS=: read -r revision expected_tree; do
    [ -n "$revision" ] || continue
    count=$((count + 1))
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || fail "不合法的信任 commit：$revision"
    [[ "$expected_tree" =~ ^[0-9a-f]{40}$ ]] || fail "不合法的信任 tree：$expected_tree"
    actual_revision="$(git --git-dir="$cache" rev-parse --verify "$revision^{commit}" 2>/dev/null)" ||
      fail "鏡像缺少信任 commit $revision"
    [ "$actual_revision" = "$revision" ] || fail "鏡像回傳錯誤 commit：$actual_revision"
    actual_tree="$(git --git-dir="$cache" rev-parse "$revision^{tree}")"
    [ "$actual_tree" = "$expected_tree" ] ||
      fail "$revision 的 tree 不符（預期 $expected_tree，實得 $actual_tree）"
    printf '• 已驗證 clang-format commit %s，tree %s\n' "$revision" "$actual_tree"
  done <<< "$trusted_objects"
  [ "$count" -gt 0 ] || fail '信任物件清單是空的'
}

setup_mirror() {
  local cache="$1" parent partial attempt rc=1 wait_s
  case "$cache" in
    /*) ;;
    *) fail 'bare cache 必須使用絕對路徑' ;;
  esac
  parent="$(dirname "$cache")"
  partial="${cache}.partial.$$"
  mkdir -p "$parent"

  for attempt in 1 2 3 4 5; do
    rm -rf "$partial"
    printf '>> 建立 clang-format 完整鏡像（第 %d 次嘗試）\n' "$attempt"
    if git clone --quiet --mirror "$mirror" "$partial"; then
      rm -rf "$cache"
      mv "$partial" "$cache"
      rc=0
      break
    else
      rc=$?
    fi
    if [ "$attempt" -lt 5 ]; then
      wait_s=$((attempt * 15))
      printf '::warning::clang-format 鏡像第 %d 次失敗（rc=%d），%d 秒後重試\n' \
        "$attempt" "$rc" "$wait_s"
      sleep "$wait_s"
    fi
  done
  rm -rf "$partial"
  [ "$rc" -eq 0 ] || fail '鏡像五輪都無法下載'

  validate_trusted_objects "$cache"

  # gclient 仍保留 canonical URL；Git 在開啟網路前才把它改寫成本機 bare
  # repository。因此 DEPS allowed_hosts 不必放寬，root 與遞迴 DEPS 也共用同一規則。
  git config --global protocol.file.allow always
  git config --global --replace-all "url.file://${cache}.insteadOf" "$upstream"
  printf '• %s 已改寫至本機唯讀來源 file://%s\n' "$upstream" "$cache"
}

revision_from_deps() {
  local deps="$1"
  awk -F"'" '$2 == "clang_format_revision" { print $4; exit }' "$deps"
}

verify_checkout() {
  local label="$1" deps="$2" checkout="$3" cache="$4"
  local expected expected_tree actual actual_tree cache_tree
  [ -f "$deps" ] || fail "$label DEPS 不存在：$deps"
  [ -d "$checkout/.git" ] || fail "$label checkout 不存在：$checkout"
  expected="$(revision_from_deps "$deps")"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]] || fail "$label DEPS 沒有精確的 clang_format_revision"
  expected_tree="$(trusted_tree "$expected")" ||
    fail "$label DEPS 要求尚未納入信任清單的 commit $expected"
  actual="$(git -C "$checkout" rev-parse --verify HEAD^{commit})"
  [ "$actual" = "$expected" ] ||
    fail "$label revision 不符（DEPS $expected，checkout $actual）"
  actual_tree="$(git -C "$checkout" rev-parse HEAD^{tree})"
  [ "$actual_tree" = "$expected_tree" ] ||
    fail "$label content tree 不符（預期 $expected_tree，實得 $actual_tree）"
  cache_tree="$(git --git-dir="$cache" rev-parse "$expected^{tree}")"
  [ "$cache_tree" = "$actual_tree" ] || fail "$label checkout 與預先驗證的鏡像內容不同"
  git -C "$checkout" diff-index --quiet HEAD -- || fail "$label checkout 有未提交內容"
  printf '• %s：DEPS revision=%s，content tree=%s（完全相符）\n' \
    "$label" "$actual" "$actual_tree"
}

case "${1:-}" in
  setup)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    setup_mirror "$2"
    ;;
  verify)
    [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    [ -d "$3" ] || fail "bare cache 不存在：$3"
    validate_trusted_objects "$3"
    verify_checkout 'root DEPS' "$2/DEPS" "$2/third_party/clang-format/script" "$3"
    verify_checkout 'nested webpagereplay DEPS' \
      "$2/third_party/webpagereplay/DEPS" \
      "$2/third_party/webpagereplay/third_party/clang-format/script" "$3"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
