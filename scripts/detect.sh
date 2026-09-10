#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON="$SCRIPT_DIR/lib/common-functions.sh"

if [[ ! -f "$COMMON" ]]; then
  echo "[错误] 工具包不完整。请下载并解压完整的 macOS 工具包后重试。" >&2
  exit 1
fi

TOOLKIT_ROOT="$SCRIPT_DIR"
export TOOLKIT_ROOT
# shellcheck source=scripts/lib/common-functions.sh
source "$COMMON"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_error "此脚本仅支持 macOS。"
  exit 1
fi

run_detect
exit $?
