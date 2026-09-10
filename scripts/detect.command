#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/common-functions.sh" ]]; then
  exec "$SCRIPT_DIR/detect.sh" "$@"
fi

CACHE="$HOME/Library/Application Support/JavaSetup/toolkit"
BASE_URL="https://765785.github.io/java-idea-installer/downloads"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-setup.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[信息] 正在下载并校验一键修复助手..."
curl -fsSL "$BASE_URL/SHA256SUMS.txt" -o "$TMP_DIR/SHA256SUMS.txt"
EXPECTED="$(awk '$2 == "java-idea-toolkit-macos.zip" { print $1 }' "$TMP_DIR/SHA256SUMS.txt" | head -n1)"
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]] || {
  echo "[错误] 无法取得官方校验值。" >&2
  exit 1
}

curl -fsSL "$BASE_URL/java-idea-toolkit-macos.zip" -o "$TMP_DIR/toolkit.zip"
if command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "$TMP_DIR/toolkit.zip" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$TMP_DIR/toolkit.zip" | awk '{print $1}')"
else
  echo "[错误] 系统缺少 SHA-256 校验工具。" >&2
  exit 1
fi
[[ "$ACTUAL" == "$EXPECTED" ]] || {
  echo "[错误] 工具包 SHA-256 校验失败。" >&2
  exit 1
}

mkdir -p "$CACHE"
/usr/bin/unzip -oq "$TMP_DIR/toolkit.zip" -d "$CACHE"
chmod +x "$CACHE/detect.sh" "$CACHE/install.sh" "$CACHE/uninstall.sh" 2>/dev/null || true
exec "$CACHE/detect.command" "$@"
