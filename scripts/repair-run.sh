#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAVA_SETUP_NO_BRIDGE=1 JAVA_SETUP_NO_PAUSE=1 "$SCRIPT_DIR/install.sh" --fix-all "$@"
EXIT_CODE=$?
SENTINEL_FILE="${JAVA_SETUP_JOB_SENTINEL:-$SCRIPT_DIR/repair-job.exit}"
printf '%s' "$EXIT_CODE" >"$SENTINEL_FILE"
exit "$EXIT_CODE"
