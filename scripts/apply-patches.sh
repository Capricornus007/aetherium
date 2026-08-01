#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
patch_dir="$repo_root/patches"

if [ ! -d "$patch_dir" ]; then
  echo "Patch directory not found: $patch_dir"
  exit 1
fi

find "$patch_dir" -type f -name '*.patch' | sort | while IFS= read -r patch; do
  printf '\nApplying patch: %s\n' "$patch"
  if git apply --check --ignore-space-change --ignore-whitespace "$patch"; then
    git apply --index --ignore-space-change --ignore-whitespace "$patch"
  else
    echo "Patch failed to apply cleanly: $patch"
    exit 1
  fi
done

echo "All patches applied successfully."
