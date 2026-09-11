#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAVA_SETUP_NO_BRIDGE=1 JAVA_SETUP_NO_PAUSE=1 JAVA_SETUP_NO_UI=1 "$SCRIPT_DIR/install.sh" --fix-all "$@"
EXIT_CODE=$?
SENTINEL_FILE="${JAVA_SETUP_JOB_SENTINEL:-$SCRIPT_DIR/repair-job.exit}"
mkdir -p "$(dirname "$SENTINEL_FILE")"
SENTINEL_TEMP="${SENTINEL_FILE}.$$"
printf '%s' "$EXIT_CODE" >"$SENTINEL_TEMP"
mv -f "$SENTINEL_TEMP" "$SENTINEL_FILE"
exit "$EXIT_CODE"
