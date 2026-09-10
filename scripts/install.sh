#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON="$SCRIPT_DIR/lib/common-functions.sh"
DRY_RUN=0
FIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      FIX="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ ! -f "$COMMON" ]]; then
  echo "[错误] 工具包不完整。请下载并解压完整的 macOS 工具包后重试。" >&2
  exit 1
fi

TOOLKIT_ROOT="$SCRIPT_DIR"
export TOOLKIT_ROOT
export DRY_RUN
# shellcheck source=scripts/lib/common-functions.sh
source "$COMMON"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_error "此脚本仅支持 macOS。"
  exit 1
fi

if [[ -n "$FIX" ]]; then
  run_fix "$FIX"
  exit $?
fi

run_install
exit $?
