#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="${1:-$ROOT/_site/downloads}"
mkdir -p "$OUTPUT"

rm -f "$OUTPUT/java-idea-toolkit-windows.zip" "$OUTPUT/java-idea-toolkit-macos.zip"

(
  cd "$SCRIPT_DIR"
  zip -q -X -r "$OUTPUT/java-idea-toolkit-windows.zip" \
    detect.bat \
    install.bat \
    uninstall.bat \
    progress.html \
    progress.js \
    lib/common-functions.bat \
    lib/windows.ps1 \
    lib/progress-server.ps1
)

(
  cd "$SCRIPT_DIR"
  zip -q -X -r "$OUTPUT/java-idea-toolkit-macos.zip" \
    detect.command \
    detect.sh \
    install.command \
    install.sh \
    uninstall.command \
    uninstall.sh \
    progress.html \
    progress.js \
    lib/common-functions.sh \
    lib/progress-server.py
)

printf 'Built toolkits in %s\n' "$OUTPUT"
ls -lh "$OUTPUT"/java-idea-toolkit-*.zip

(
  cd "$OUTPUT"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum java-idea-toolkit-windows.zip java-idea-toolkit-macos.zip >SHA256SUMS.txt
  else
    shasum -a 256 java-idea-toolkit-windows.zip java-idea-toolkit-macos.zip >SHA256SUMS.txt
  fi
)
printf 'Wrote %s\n' "$OUTPUT/SHA256SUMS.txt"
