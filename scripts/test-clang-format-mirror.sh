#!/usr/bin/env bash
# 不使用網路的回歸測試：故障 canonical URL 必須由本機 mirror 接手，且 root/nested
# checkout 都只能接受 DEPS 指定的 commit 與 tree。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/scripts/clang-format-mirror.sh"
tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/source"
git -C "$tmp/source" init --quiet
git -C "$tmp/source" config user.name 'aetherium CI test'
git -C "$tmp/source" config user.email 'ci-test@invalid.example'
printf 'pinned content\n' > "$tmp/source/git-clang-format"
git -C "$tmp/source" add git-clang-format
GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' \
GIT_COMMITTER_DATE='2000-01-01T00:00:00Z' \
  git -C "$tmp/source" commit --quiet -m 'fixture'
revision="$(git -C "$tmp/source" rev-parse HEAD)"
tree="$(git -C "$tmp/source" rev-parse HEAD^{tree})"
git clone --quiet --mirror "$tmp/source" "$tmp/remote.git"

export CLANG_FORMAT_UPSTREAM_URL='https://failure.invalid/clang-format.git'
export CLANG_FORMAT_MIRROR_URL="file://$tmp/remote.git"
export CLANG_FORMAT_TRUSTED_OBJECTS="$revision:$tree"
"$script" setup "$tmp/cache.git"

src="$tmp/chromium/src"
mkdir -p "$src/third_party/webpagereplay"
printf "vars = {'clang_format_revision': '%s'}\n" "$revision" > "$src/DEPS"
printf "vars = {'clang_format_revision': '%s'}\n" "$revision" > \
  "$src/third_party/webpagereplay/DEPS"

for checkout in \
  "$src/third_party/clang-format/script" \
  "$src/third_party/webpagereplay/third_party/clang-format/script"; do
  mkdir -p "$checkout"
  git -C "$checkout" init --quiet
  git -C "$checkout" remote add origin "$CLANG_FORMAT_UPSTREAM_URL"
  git -C "$checkout" fetch --quiet --depth=1 origin "$revision"
  git -C "$checkout" checkout --quiet --detach FETCH_HEAD
done

"$script" verify "$src" "$tmp/cache.git"
printf 'clang-format mirror test: PASS\n'
