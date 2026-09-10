#!/usr/bin/env bash

set -o pipefail

TOOL_VERSION="1.0.0"
JDK_TARGET_VERSION="${JDK_TARGET_VERSION:-25}"
JDK_DISTRIBUTION="${JDK_DISTRIBUTION:-temurin}"
ENABLE_MIRROR_ACCELERATION="${ENABLE_MIRROR_ACCELERATION:-auto}"
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${REPORT_DIR:-$HOME/Downloads/java-setup-reports}"
PROGRESS_DIR="$REPORT_DIR/progress"
PUBLIC_SITE="${JAVA_SETUP_PUBLIC_SITE:-https://765785.github.io/java-idea-installer/}"

LOG_LINES=""
PROGRESS_ACTION="install"
PROGRESS_STARTED_AT=""
PROGRESS_IDS=()
PROGRESS_LABELS=()
PROGRESS_ESTIMATES=()
PROGRESS_STATUSES=()
PROGRESS_MESSAGES=()

log_info() {
  _java_setup_log "信息" "$*"
}

log_ok() {
  _java_setup_log "完成" "$*"
}

log_warn() {
  _java_setup_log "提醒" "$*"
}

log_error() {
  _java_setup_log "错误" "$*"
}

_java_setup_log() {
  local level="$1"
  shift
  local line
  line="[$(date '+%H:%M:%S')] ${level} $*"
  if [[ -n "$LOG_LINES" ]]; then
    LOG_LINES="${LOG_LINES}"$'\n'"${line}"
  else
    LOG_LINES="$line"
  fi
  printf '%s\n' "$line"
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

ensure_report_dirs() {
  mkdir -p "$REPORT_DIR" "$PROGRESS_DIR"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t\r\n' '   '
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

atomic_write() {
  local target="$1"
  local content="$2"
  local directory temporary
  directory="$(dirname "$target")"
  mkdir -p "$directory"
  temporary="$(mktemp "${directory}/.java-setup.XXXXXX")"
  printf '%s\n' "$content" >"$temporary"
  mv -f "$temporary" "$target"
}

safe_remove_tree() {
  local target="$1"
  local parent parent_resolved base resolved
  [[ -n "$target" && "$target" != "/" && "$target" != "$HOME" ]] || return 1
  parent="$(dirname "$target")"
  base="$(basename "$target")"
  [[ -n "$base" && "$base" != "." && "$base" != ".." ]] || return 1
  parent_resolved="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1
  resolved="$parent_resolved/$base"
  case "$resolved" in
    "$HOME/Library/"*|"/Applications/"*|"${TMPDIR:-/tmp}/"*) ;;
    *) return 1 ;;
  esac
  rm -rf -- "$resolved"
}

progress_init() {
  local action="$1"
  shift
  ensure_report_dirs
  PROGRESS_ACTION="$action"
  PROGRESS_STARTED_AT="$(timestamp)"
  PROGRESS_IDS=()
  PROGRESS_LABELS=()
  PROGRESS_ESTIMATES=()
  PROGRESS_STATUSES=()
  PROGRESS_MESSAGES=()

  local item id label seconds
  for item in "$@"; do
    IFS='|' read -r id label seconds <<<"$item"
    PROGRESS_IDS+=("$id")
    PROGRESS_LABELS+=("$label")
    PROGRESS_ESTIMATES+=("${seconds:-30}")
    PROGRESS_STATUSES+=("pending")
    PROGRESS_MESSAGES+=("")
  done
  progress_write "running" 0 0 "准备开始" "null"
}

progress_set_step() {
  local index="$1"
  local status="$2"
  local message="${3:-}"
  local percent="${4:--1}"
  PROGRESS_STATUSES[index]="$status"
  PROGRESS_MESSAGES[index]="$message"
  if [[ "$percent" -lt 0 ]]; then
    local total="${#PROGRESS_IDS[@]}"
    local finished=$index
    if [[ "$status" == "complete" ]]; then
      finished=$((index + 1))
    fi
    percent=$((finished * 100 / (total > 0 ? total : 1)))
  fi
  progress_write "running" "$index" "$percent" "$message" "null"
}

progress_write() {
  local status="$1"
  local current="$2"
  local percent="$3"
  local message="$4"
  local result_json="${5:-null}"
  local steps="["
  local index count
  count="${#PROGRESS_IDS[@]}"

  for ((index = 0; index < count; index++)); do
    if [[ "$index" -gt 0 ]]; then
      steps+=","
    fi
    steps+="{\"id\":$(json_string "${PROGRESS_IDS[$index]}"),"
    steps+="\"label\":$(json_string "${PROGRESS_LABELS[$index]}"),"
    steps+="\"status\":$(json_string "${PROGRESS_STATUSES[$index]}"),"
    steps+="\"estimatedSeconds\":${PROGRESS_ESTIMATES[$index]},"
    steps+="\"message\":$(json_string "${PROGRESS_MESSAGES[$index]}")}"
  done
  steps+="]"

  local payload
  payload="{"
  payload+="\"schemaVersion\":1,"
  payload+="\"action\":$(json_string "$PROGRESS_ACTION"),"
  payload+="\"status\":$(json_string "$status"),"
  payload+="\"currentStep\":$current,"
  payload+="\"totalSteps\":$count,"
  payload+="\"percent\":$percent,"
  payload+="\"steps\":$steps,"
  payload+="\"startedAt\":$(json_string "$PROGRESS_STARTED_AT"),"
  payload+="\"updatedAt\":$(json_string "$(timestamp)"),"
  payload+="\"message\":$(json_string "$message"),"
  payload+="\"result\":$result_json,"
  payload+="\"log\":$(json_string "$LOG_LINES")"
  payload+="}"
  atomic_write "$PROGRESS_DIR/progress.json" "$payload"
}

copy_progress_assets() {
  local source_dir="$TOOLKIT_ROOT/scripts"
  [[ -d "$source_dir" ]] || source_dir="$TOOLKIT_ROOT"
  local file remote
  for file in progress.html progress.js; do
    if [[ ! -f "$source_dir/$file" ]]; then
      remote="$PUBLIC_SITE/scripts/$file"
      curl -fsSL "$remote" -o "$PROGRESS_DIR/$file" 2>/dev/null || true
      continue
    fi
    if [[ -f "$source_dir/$file" ]]; then
      cp "$source_dir/$file" "$PROGRESS_DIR/$file"
    fi
  done
  if [[ ! -f "$source_dir/lib/progress-server.py" ]]; then
    curl -fsSL "$PUBLIC_SITE/scripts/lib/progress-server.py" -o "$PROGRESS_DIR/progress-server.py" 2>/dev/null || true
  elif [[ -f "$source_dir/lib/progress-server.py" ]]; then
    cp "$source_dir/lib/progress-server.py" "$PROGRESS_DIR/progress-server.py"
  fi
}

find_free_port() {
  local port="$1"
  local limit=$((port + 20))
  while [[ "$port" -lt "$limit" ]]; do
    if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      printf '%s' "$port"
      return 0
    fi
    port=$((port + 1))
  done
  printf '%s' 0
}

open_progress_page() {
  local action="$1"
  if [[ "${JAVA_SETUP_NO_UI:-0}" == "1" ]]; then
    ensure_report_dirs
    copy_progress_assets
    printf ''
    return 0
  fi
  ensure_report_dirs
  copy_progress_assets
  progress_init "$action" >/dev/null 2>&1 || true

  local port token server_url local_url
  port="$(find_free_port 8765)"
  if [[ "$port" -ne 0 && -x /usr/bin/python3 && -f "$PROGRESS_DIR/progress-server.py" ]]; then
    token="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')"
    nohup /usr/bin/python3 "$PROGRESS_DIR/progress-server.py" "$PROGRESS_DIR" --port "$port" --token "$token" >/dev/null 2>&1 &
    sleep 0.6
    server_url="http://127.0.0.1:${port}/progress.html?return=$(printf '%s' "$PUBLIC_SITE" | sed 's/:/%3A/g; s#/#%2F#g')&token=$token"
    if open "$server_url" >/dev/null 2>&1; then
      printf '%s' "$server_url"
      return 0
    fi
  fi

  local_url="file://$PROGRESS_DIR/progress.html?return=$(printf '%s' "$PUBLIC_SITE" | sed 's/:/%3A/g; s#/#%2F#g')"
  open "$local_url" >/dev/null 2>&1 || true
  printf '%s' "$local_url"
}

version_major() {
  local value="${1:-0}"
  local parsed
  if [[ "$value" == 1.* ]]; then
    parsed="$(printf '%s' "${value#1.}" | cut -d. -f1)"
  else
    parsed="$(printf '%s' "$value" | sed -E 's/^[^0-9]*([0-9]+).*/\1/')"
  fi
  if [[ "$parsed" =~ ^[0-9]+$ ]]; then
    printf '%s' "$parsed"
  else
    printf '0'
  fi
}

version_ge() {
  local left right
  left="$(version_major "$1")"
  right="$(version_major "$2")"
  [[ "$left" -ge "$right" ]]
}

version_lt() {
  ! version_ge "$1" "$2"
}

java_version_at() {
  local home="$1"
  local java_exe="$home/bin/java"
  [[ -x "$java_exe" ]] || return 1
  local output version
  output="$("$java_exe" -version 2>&1 || true)"
  version="$(printf '%s\n' "$output" | sed -n '1s/.*"\([^"]*\)".*/\1/p')"
  [[ -n "$version" ]] || return 1
  printf '%s' "$version"
}

add_java_candidate() {
  local home="$1"
  local source="$2"
  local version major candidate
  [[ -n "$home" && -x "$home/bin/java" ]] || return 0
  home="$(cd "$home" 2>/dev/null && pwd -P)" || return 0
  version="$(java_version_at "$home")" || return 0
  major="$(version_major "$version")"

  for candidate in "${JAVA_CANDIDATE_PATHS[@]:-}"; do
    [[ "$candidate" == "$home" ]] && return 0
  done
  JAVA_CANDIDATE_PATHS+=("$home")
  JAVA_CANDIDATE_VERSIONS+=("$version")
  JAVA_CANDIDATE_MAJORS+=("$major")
  JAVA_CANDIDATE_SOURCES+=("$source")
}

get_java_candidates() {
  JAVA_CANDIDATE_PATHS=()
  JAVA_CANDIDATE_VERSIONS=()
  JAVA_CANDIDATE_MAJORS=()
  JAVA_CANDIDATE_SOURCES=()

  if [[ -n "${JAVA_HOME:-}" ]]; then
    add_java_candidate "$JAVA_HOME" "JAVA_HOME"
  fi

  if command -v java >/dev/null 2>&1; then
    local resolved
    resolved="$(command -v java)"
    resolved="$(cd "$(dirname "$resolved")/.." 2>/dev/null && pwd -P)" || resolved=""
    add_java_candidate "$resolved" "PATH"
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    while IFS= read -r home; do
      add_java_candidate "$home" "系统 JDK"
    done < <(/usr/libexec/java_home -V 2>&1 | sed -n 's/^[[:space:]]*[^[:space:]]*[[:space:]]\+\(.*\)$/\1/p')
  fi

  local root candidate
  for root in /Library/Java/JavaVirtualMachines "$HOME/Library/Java/JavaVirtualMachines"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r candidate; do
      add_java_candidate "$candidate/Contents/Home" "安装目录"
    done < <(find "$root" -maxdepth 1 -type d -name '*.jdk' 2>/dev/null)
  done

  local brew_prefix
  if command -v brew >/dev/null 2>&1; then
    while IFS= read -r brew_prefix; do
      add_java_candidate "$brew_prefix" "Homebrew"
    done < <(brew --prefix --installed 2>/dev/null | grep -E '/(openjdk|temurin)(@|$)' || true)
  fi
}

select_java_home() {
  local index best_index=-1 best_major=-1 best_version="" major version
  for ((index = 0; index < ${#JAVA_CANDIDATE_PATHS[@]}; index++)); do
    major="${JAVA_CANDIDATE_MAJORS[$index]}"
    version="${JAVA_CANDIDATE_VERSIONS[$index]}"
    if [[ "$major" -ge "$JDK_TARGET_VERSION" ]]; then
      if [[ "$best_index" -lt 0 || "$major" -gt "$best_major" ]]; then
        best_index=$index
        best_major=$major
        best_version="$version"
      fi
    elif [[ "$best_index" -lt 0 && "$major" -gt "$best_major" ]]; then
      best_index=$index
      best_major=$major
      best_version="$version"
    fi
  done
  if [[ "$best_index" -ge 0 ]]; then
    printf '%s|%s|%s|%s' "${JAVA_CANDIDATE_PATHS[$best_index]}" "$best_version" "$best_major" "${JAVA_CANDIDATE_SOURCES[$best_index]}"
  fi
}

idea_version_at() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null && return 0
  fi
  local product_info="$app/Contents/Resources/product-info.json"
  if [[ -f "$product_info" ]]; then
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$product_info" | head -n1
  fi
}

find_idea_installations() {
  IDEA_PATHS=()
  IDEA_VERSIONS=()
  local root found version
  for root in /Applications "$HOME/Applications"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r found; do
      version="$(idea_version_at "$found")"
      IDEA_PATHS+=("$found")
      IDEA_VERSIONS+=("$version")
    done < <(find "$root" -maxdepth 1 -type d \( -iname 'IntelliJ IDEA CE*.app' -o -iname 'IntelliJ IDEA Community*.app' \) 2>/dev/null)
  done
}

json_extract() {
  local json="$1"
  local key_path="$2"
  if command -v plutil >/dev/null 2>&1; then
    printf '%s' "$json" | plutil -extract "$key_path" raw -o - - 2>/dev/null && return 0
  fi
  return 1
}

get_latest_idea_release() {
  IDEA_LATEST_STATUS="unavailable"
  IDEA_LATEST_VERSION=""
  IDEA_LATEST_BUILD=""
  IDEA_LATEST_DMG=""
  IDEA_LATEST_CHECKSUM=""
  IDEA_LATEST_MESSAGE="无法确认最新版，按已安装处理"

  local url json arch key
  url='https://data.services.jetbrains.com/products/releases?code=IIC&latest=true&type=release'
  if ! json="$(curl -fsSL --max-time 20 "$url" 2>/dev/null)"; then
    return 0
  fi

  IDEA_LATEST_VERSION="$(json_extract "$json" 'IIC.0.version' || true)"
  IDEA_LATEST_BUILD="$(json_extract "$json" 'IIC.0.build' || true)"
  arch="$(uname -m)"
  if [[ "$arch" == "arm64" ]]; then
    key='IIC.0.downloads.macM1.link'
    checksum_key='IIC.0.downloads.macM1.checksumLink'
  else
    key='IIC.0.downloads.mac.link'
    checksum_key='IIC.0.downloads.mac.checksumLink'
  fi
  IDEA_LATEST_DMG="$(json_extract "$json" "$key" || true)"
  IDEA_LATEST_CHECKSUM="$(json_extract "$json" "$checksum_key" || true)"
  if [[ -n "$IDEA_LATEST_VERSION" && -n "$IDEA_LATEST_DMG" ]]; then
    IDEA_LATEST_STATUS="ok"
    IDEA_LATEST_MESSAGE="已获取 JetBrains 官方最新版"
  fi
}

detect_network() {
  NETWORK_DOMESTIC=false
  NETWORK_INTERNATIONAL=false
  if curl -fsS --connect-timeout 3 --max-time 5 -o /dev/null 'https://mirrors.tuna.tsinghua.edu.cn/' 2>/dev/null; then
    NETWORK_DOMESTIC=true
  fi
  if curl -fsS --connect-timeout 3 --max-time 5 -o /dev/null 'https://github.com/' 2>/dev/null; then
    NETWORK_INTERNATIONAL=true
  fi
  if [[ "$NETWORK_DOMESTIC" == true && "$NETWORK_INTERNATIONAL" == true ]]; then
    NETWORK_STATUS="ok"
  elif [[ "$NETWORK_DOMESTIC" == true || "$NETWORK_INTERNATIONAL" == true ]]; then
    NETWORK_STATUS="partial"
  else
    NETWORK_STATUS="unavailable"
  fi
  if [[ "$ENABLE_MIRROR_ACCELERATION" == "always" || ( "$ENABLE_MIRROR_ACCELERATION" == "auto" && "$NETWORK_DOMESTIC" == true && "$NETWORK_INTERNATIONAL" == false ) ]]; then
    NETWORK_MIRROR="tuna"
  else
    NETWORK_MIRROR="default"
  fi
}

check_health() {
  HEALTH_ITEMS=()
  if [[ -z "${JAVA_HOME:-}" ]]; then
    HEALTH_ITEMS+=("java_home|JAVA_HOME 未设置|warning|true|java_home|自动指向选中的 JDK")
  elif [[ ! -x "$JAVA_HOME/bin/java" ]]; then
    HEALTH_ITEMS+=("java_home|JAVA_HOME 指向错误路径|warning|true|java_home|自动重新检测并设置有效 JDK")
  fi

  if [[ ${#JAVA_CANDIDATE_PATHS[@]} -gt 1 ]]; then
    HEALTH_ITEMS+=("multiple_jdks|检测到多个 JDK|warning|true|multiple_jdks|将优先使用满足目标要求的最高版本")
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    local java_home_version
    java_home_version="$(java_version_at "$JAVA_HOME" || true)"
    if [[ -n "$java_home_version" ]] && version_lt "$java_home_version" "$JDK_TARGET_VERSION"; then
      HEALTH_ITEMS+=("java_home|JAVA_HOME 版本低于目标版本|warning|true|java_home|切换到 JDK $JDK_TARGET_VERSION")
    fi
  fi

  if [[ -d /Applications ]] && find /Applications -maxdepth 1 -type d \( -iname 'IntelliJ IDEA CE*.app' -o -iname 'IntelliJ IDEA Community*.app' \) -print -quit 2>/dev/null | grep -q .; then
    if xattr -lr /Applications/IntelliJ\ IDEA\ CE*.app 2>/dev/null | grep -q 'com.apple.quarantine'; then
      HEALTH_ITEMS+=("gatekeeper|IDEA 被 Gatekeeper 隔离|warning|true|gatekeeper|自动移除应用隔离属性")
    fi
  fi
}

detection_json() {
  get_java_candidates
  find_idea_installations
  get_latest_idea_release
  detect_network

  local selected selected_path selected_version selected_major selected_source
  selected="$(select_java_home)"
  if [[ -n "$selected" ]]; then
    IFS='|' read -r selected_path selected_version selected_major selected_source <<<"$selected"
  fi

  if [[ -z "${selected_path:-}" ]]; then
    JDK_STATUS="missing"
    JDK_VERSION="null"
    JDK_PATH="null"
    JDK_MESSAGE="未检测到可用 JDK"
  elif [[ "$selected_major" -lt "$JDK_TARGET_VERSION" ]]; then
    JDK_STATUS="outdated"
    JDK_VERSION="$(json_string "$selected_version")"
    JDK_PATH="$(json_string "$selected_path")"
    JDK_MESSAGE="当前版本低于目标版本 $JDK_TARGET_VERSION"
  else
    JDK_STATUS="ok"
    JDK_VERSION="$(json_string "$selected_version")"
    JDK_PATH="$(json_string "$selected_path")"
    JDK_MESSAGE="可用于 Java 开发"
  fi

  local idea_index=0 idea_best_index=-1 idea_best_major=-1 version major
  for ((idea_index = 0; idea_index < ${#IDEA_PATHS[@]}; idea_index++)); do
    version="${IDEA_VERSIONS[$idea_index]}"
    major="$(version_major "$version")"
    if (( major > idea_best_major )); then
      idea_best_index=$idea_index
      idea_best_major=$major
    fi
  done

  if [[ "$idea_best_index" -lt 0 ]]; then
    IDEA_STATUS="missing"
    IDEA_VERSION="null"
    IDEA_PATH="null"
    IDEA_MESSAGE="未检测到 IntelliJ IDEA Community"
  elif [[ "$IDEA_LATEST_STATUS" != "ok" ]]; then
    IDEA_STATUS="ok"
    IDEA_VERSION="$(json_string "${IDEA_VERSIONS[$idea_best_index]}")"
    IDEA_PATH="$(json_string "${IDEA_PATHS[$idea_best_index]}")"
    IDEA_MESSAGE="无法确认最新版，按已安装处理"
  elif version_lt "${IDEA_VERSIONS[$idea_best_index]}" "$IDEA_LATEST_VERSION"; then
    IDEA_STATUS="outdated"
    IDEA_VERSION="$(json_string "${IDEA_VERSIONS[$idea_best_index]}")"
    IDEA_PATH="$(json_string "${IDEA_PATHS[$idea_best_index]}")"
    IDEA_MESSAGE="当前版本可升级到 $IDEA_LATEST_VERSION"
  else
    IDEA_STATUS="ok"
    IDEA_VERSION="$(json_string "${IDEA_VERSIONS[$idea_best_index]}")"
    IDEA_PATH="$(json_string "${IDEA_PATHS[$idea_best_index]}")"
    IDEA_MESSAGE="已是最新版本"
  fi

  if [[ -z "${JAVA_HOME:-}" ]]; then
    JAVA_HOME_STATUS="missing"
    JAVA_HOME_VALUE="null"
    JAVA_HOME_VERSION="null"
    JAVA_HOME_MESSAGE="JAVA_HOME 未设置"
  elif [[ ! -x "$JAVA_HOME/bin/java" ]]; then
    JAVA_HOME_STATUS="invalid"
    JAVA_HOME_VALUE="$(json_string "$JAVA_HOME")"
    JAVA_HOME_VERSION="null"
    JAVA_HOME_MESSAGE="JAVA_HOME 指向的路径无效"
  else
    JAVA_HOME_VERSION_VALUE="$(java_version_at "$JAVA_HOME" || true)"
    if [[ -n "$JAVA_HOME_VERSION_VALUE" ]] && version_lt "$JAVA_HOME_VERSION_VALUE" "$JDK_TARGET_VERSION"; then
      JAVA_HOME_STATUS="mismatch"
    else
      JAVA_HOME_STATUS="ok"
    fi
    JAVA_HOME_VALUE="$(json_string "$JAVA_HOME")"
    JAVA_HOME_VERSION="$(json_string "$JAVA_HOME_VERSION_VALUE")"
    JAVA_HOME_MESSAGE="JAVA_HOME 配置有效"
  fi

  check_health
  local health_json="[" item id title severity fixable action message first=true
  for item in "${HEALTH_ITEMS[@]:-}"; do
    [[ -n "$item" ]] || continue
    IFS='|' read -r id title severity fixable action message <<<"$item"
    [[ "$first" == true ]] || health_json+=","
    first=false
    health_json+="{\"id\":$(json_string "$id"),\"title\":$(json_string "$title"),\"severity\":$(json_string "$severity"),\"fixable\":$fixable,\"action\":$(json_string "$action"),\"message\":$(json_string "$message")}"
  done
  health_json+="]"

  local warnings=0 errors=0
  for item in "$JDK_STATUS" "$IDEA_STATUS" "$JAVA_HOME_STATUS"; do
    case "$item" in
      ok) ;;
      missing|invalid|error) errors=$((errors + 1)); warnings=$((warnings + 1)) ;;
      *) warnings=$((warnings + 1)) ;;
    esac
  done
  if [[ "${#HEALTH_ITEMS[@]}" -gt 0 ]]; then
    warnings=$((warnings + ${#HEALTH_ITEMS[@]}))
  fi

  local os_version architecture
  os_version="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
  architecture="$(uname -m)"
  printf '{'
  printf '"schemaVersion":1,'
  printf '"toolVersion":%s,' "$(json_string "$TOOL_VERSION")"
  printf '"generatedAt":%s,' "$(json_string "$(timestamp)")"
  printf '"os":{"family":"macos","version":%s,"architecture":%s},' "$(json_string "$os_version")" "$(json_string "$architecture")"
  printf '"network":{"status":%s,"mirrorMode":%s,"selectedMirror":%s,"domesticReachable":%s,"internationalReachable":%s,"ideaVersionCheck":%s,"message":%s},' \
    "$(json_string "$NETWORK_STATUS")" "$(json_string "$ENABLE_MIRROR_ACCELERATION")" "$(json_string "$NETWORK_MIRROR")" \
    "$NETWORK_DOMESTIC" "$NETWORK_INTERNATIONAL" "$(json_string "$IDEA_LATEST_STATUS")" "$(json_string "$IDEA_LATEST_MESSAGE")"
  printf '"components":{'
  printf '"jdk":{"status":%s,"version":%s,"path":%s,"targetVersion":%s,"source":%s,"message":%s},' \
    "$(json_string "$JDK_STATUS")" "$JDK_VERSION" "$JDK_PATH" "$JDK_TARGET_VERSION" "$(json_string "${selected_source:-}")" "$(json_string "$JDK_MESSAGE")"
  printf '"idea":{"status":%s,"version":%s,"latestVersion":%s,"build":%s,"path":%s,"message":%s},' \
    "$(json_string "$IDEA_STATUS")" "$IDEA_VERSION" "$(if [[ -n "$IDEA_LATEST_VERSION" ]]; then json_string "$IDEA_LATEST_VERSION"; else printf null; fi)" \
    "$(if [[ -n "$IDEA_LATEST_BUILD" ]]; then json_string "$IDEA_LATEST_BUILD"; else printf null; fi)" "$IDEA_PATH" "$(json_string "$IDEA_MESSAGE")"
  printf '"javaHome":{"status":%s,"path":%s,"version":%s,"message":%s}},' \
    "$(json_string "$JAVA_HOME_STATUS")" "$JAVA_HOME_VALUE" "$JAVA_HOME_VERSION" "$(json_string "$JAVA_HOME_MESSAGE")"
  printf '"health":%s,' "$health_json"
  printf '"summary":{"ok":%s,"warnings":%s,"errors":%s}' "$((3 - warnings > 0 ? 3 - warnings : 0))" "$warnings" "$errors"
  printf '}'
}

build_result_url() {
  local json="$1"
  local encoded
  encoded="$(printf '%s' "$json" | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
  if [[ "${#encoded}" -lt 90000 ]]; then
    printf '%s#result=%s' "$PUBLIC_SITE" "$encoded"
  fi
}

run_detect() {
  ensure_report_dirs
  log_info "正在检测 macOS、JDK、IDEA 和环境变量..."
  local json result_path url exit_code=0
  json="$(detection_json)"
  result_path="$REPORT_DIR/detection_result.json"
  atomic_write "$result_path" "$json"

  printf '\n检测报告\n'
  printf '结果文件：%s\n' "$result_path"
  log_ok "检测完成"

  url="$(build_result_url "$json")"
  if [[ -n "$url" ]]; then
    open "$url" >/dev/null 2>&1 || log_warn "无法自动打开网页，请手动上传检测结果。"
  else
    log_warn "结果过长，请把 JSON 文件拖到网页中。"
  fi

  if printf '%s' "$json" | grep -q '"errors":[1-9]'; then
    exit_code=10
  elif printf '%s' "$json" | grep -q '"warnings":[1-9]'; then
    exit_code=20
  fi
  return "$exit_code"
}

configure_brew_mirror() {
  [[ "$NETWORK_MIRROR" == "tuna" ]] || return 0
  export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
  log_info "已启用清华 Homebrew 镜像加速"
}

resolve_temurin_cask() {
  command -v brew >/dev/null 2>&1 || return 1
  local candidate info
  for candidate in "temurin@$JDK_TARGET_VERSION" "temurin"; do
    info="$(brew info --cask --json=v2 "$candidate" 2>/dev/null || true)"
    if [[ -n "$info" ]] && printf '%s' "$info" | grep -Eq '"version"[[:space:]]*:[[:space:]]*"'"$JDK_TARGET_VERSION"'([.,"]|$)' ; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

install_temurin_official() {
  local architecture api_url json package_url checksum_url package_file expected actual
  architecture="$(uname -m)"
  if [[ "$architecture" == "arm64" ]]; then
    architecture="aarch64"
  else
    architecture="x64"
  fi
  api_url="https://api.adoptium.net/v3/assets/latest/$JDK_TARGET_VERSION/hotspot?architecture=$architecture&image_type=jdk&os=mac&vendor=eclipse"
  json="$(curl -fsSL --max-time 30 "$api_url")"
  package_url="$(json_extract "$json" '0.binary.package.link' || true)"
  checksum_url="$(json_extract "$json" '0.binary.package.checksumLink' || true)"
  [[ -n "$package_url" ]] || return 1
  [[ "$package_url" == https://* && "$checksum_url" == https://* ]] || {
    log_error "拒绝下载非 HTTPS 安装包"
    return 1
  }
  package_file="$(mktemp "$TMPDIR/Temurin-XXXXXX.pkg")"
  curl -fL --progress-bar "$package_url" -o "$package_file"
  expected="$(curl -fsSL --max-time 30 "$checksum_url" | sed -n 's/^\([a-fA-F0-9]\{64\}\).*/\1/p')"
  actual="$(shasum -a 256 "$package_file" | awk '{print $1}')"
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    rm -f "$package_file"
    log_error "Adoptium 官方安装包 SHA-256 校验失败"
    return 1
  fi
  log_info "即将通过 sudo 安装 Temurin JDK $JDK_TARGET_VERSION"
  sudo installer -pkg "$package_file" -target /
  rm -f "$package_file"
}

install_jdk() {
  configure_brew_mirror
  local cask
  cask="$(resolve_temurin_cask || true)"
  if [[ -n "$cask" ]]; then
    log_info "从 Homebrew 动态选择 cask：$cask"
    if brew install --cask "$cask"; then
      return 0
    fi
    log_warn "Homebrew 安装失败，改用 Adoptium 官方 pkg。"
  else
    log_warn "未查询到 Temurin $JDK_TARGET_VERSION 的 Homebrew cask，改用官方 pkg。"
  fi
  install_temurin_official
}

install_idea_official() {
  get_latest_idea_release
  if [[ "$IDEA_LATEST_STATUS" != "ok" ]]; then
    log_error "无法取得 JetBrains 官方 IDEA 下载信息"
    return 1
  fi

  local dmg mount_point temp_root expected actual source_app target_app
  dmg="$(mktemp "$TMPDIR/idea-community-XXXXXX.dmg")"
  mount_point="$(mktemp -d "$TMPDIR/idea-mount-XXXXXX")"
  temp_root="$(mktemp -d "$TMPDIR/idea-app-XXXXXX")"
  [[ "$IDEA_LATEST_DMG" == https://* && "$IDEA_LATEST_CHECKSUM" == https://* ]] || {
    log_error "拒绝下载非 HTTPS 安装包"
    return 1
  }
  curl -fL --progress-bar "$IDEA_LATEST_DMG" -o "$dmg"
  expected="$(curl -fsSL --max-time 30 "$IDEA_LATEST_CHECKSUM" | sed -n 's/^\([a-fA-F0-9]\{64\}\).*/\1/p')"
  actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    rm -rf "$dmg" "$mount_point" "$temp_root"
    log_error "IDEA 官方安装包 SHA-256 校验失败"
    return 1
  fi

  hdiutil attach "$dmg" -mountpoint "$mount_point" -nobrowse -quiet
  source_app="$(find "$mount_point" -maxdepth 1 -type d -name '*.app' -print -quit)"
  if [[ -z "$source_app" ]]; then
    hdiutil detach "$mount_point" -quiet || true
    rm -rf "$dmg" "$mount_point" "$temp_root"
    log_error "IDEA 安装镜像中没有找到应用"
    return 1
  fi
  ditto "$source_app" "$temp_root/IntelliJ IDEA CE.app"
  hdiutil detach "$mount_point" -quiet || true
  rm -rf "$dmg" "$mount_point"

  target_app="/Applications/IntelliJ IDEA CE.app"
  if [[ -w /Applications ]]; then
    safe_remove_tree "$target_app"
    ditto "$temp_root/IntelliJ IDEA CE.app" "$target_app"
  else
    sudo rm -rf -- "$target_app"
    sudo ditto "$temp_root/IntelliJ IDEA CE.app" "$target_app"
  fi
  rm -rf "$temp_root"
  xattr -rd com.apple.quarantine "$target_app" 2>/dev/null || true
}

install_idea() {
  find_idea_installations
  get_latest_idea_release
  local best_index=-1 best_major=-1 index major
  for ((index = 0; index < ${#IDEA_PATHS[@]}; index++)); do
    major="$(version_major "${IDEA_VERSIONS[$index]}")"
    if (( major > best_major )); then
      best_index=$index
      best_major=$major
    fi
  done

  if [[ "$best_index" -ge 0 && "$IDEA_LATEST_STATUS" == "ok" ]]; then
    if ! version_lt "${IDEA_VERSIONS[$best_index]}" "$IDEA_LATEST_VERSION"; then
      return 0
    fi
  fi

  configure_brew_mirror
  if [[ "$best_index" -lt 0 ]] && command -v brew >/dev/null 2>&1; then
    if brew install --cask intellij-idea-ce; then
      find_idea_installations
      best_index=-1
      best_major=-1
      for ((index = 0; index < ${#IDEA_PATHS[@]}; index++)); do
        major="$(version_major "${IDEA_VERSIONS[$index]}")"
        if (( major > best_major )); then
          best_index=$index
          best_major=$major
        fi
      done
      if [[ "$best_index" -ge 0 && "$IDEA_LATEST_STATUS" == "ok" ]] && ! version_lt "${IDEA_VERSIONS[$best_index]}" "$IDEA_LATEST_VERSION"; then
        return 0
      fi
    fi
  fi
  install_idea_official
}

set_java_environment() {
  local selected home version source profile block quoted_home
  selected="$(select_java_home)"
  [[ -n "$selected" ]] || return 1
  IFS='|' read -r home version _ source <<<"$selected"
  export JAVA_HOME="$home"

  if [[ "${SHELL:-}" == *zsh* || -n "${ZSH_VERSION:-}" ]]; then
    profile="$HOME/.zshrc"
  else
    profile="$HOME/.bash_profile"
  fi
  touch "$profile"
  printf -v quoted_home '%q' "$home"
  block="# >>> java-idea-installer >>>\nexport JAVA_HOME=$quoted_home\nexport PATH=\"\$JAVA_HOME/bin:\$PATH\"\n# <<< java-idea-installer <<<"

  local temp
  temp="$(mktemp "${profile}.java-setup.XXXXXX")"
  awk '
    /^# >>> java-idea-installer >>>$/ { skip=1; next }
    /^# <<< java-idea-installer <<<$/ { skip=0; next }
    skip != 1 { print }
  ' "$profile" >"$temp"
  printf '\n%b\n' "$block" >>"$temp"
  mv "$temp" "$profile"
  log_ok "已更新 $profile 中的 JAVA_HOME 和 PATH"
}

run_smoke_test() {
  local temp
  temp="$(mktemp -d "$TMPDIR/java-setup-smoke.XXXXXX")"
  cat >"$temp/HelloWorld.java" <<'JAVA'
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello World");
    }
}
JAVA
  (
    cd "$temp" || exit 1
    export PATH="$JAVA_HOME/bin:$PATH"
    javac HelloWorld.java
    output="$(java HelloWorld)"
    [[ "$output" == "Hello World" ]]
  )
  local result=$?
  rm -rf "$temp"
  [[ "$result" -eq 0 ]]
}

run_install() {
  open_progress_page install >/dev/null 2>&1 || true
  progress_init install \
    "prepare|检查系统和网络|30" \
    "jdk|安装或确认 JDK $JDK_TARGET_VERSION|120" \
    "idea|安装最新版 IntelliJ IDEA Community|180" \
    "verify|配置环境并运行 Hello World|40"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "dry-run：不会执行真实安装。"
    progress_set_step 0 complete "dry-run 环境检查完成" 25
    for index in 1 2 3; do progress_set_step "$index" complete "dry-run 跳过" -1; done
    progress_write success 4 100 "dry-run 已完成" "null"
    return 0
  fi

  progress_set_step 0 running "正在检查系统环境"
  detect_network
  find_idea_installations
  get_java_candidates
  progress_set_step 0 complete "环境和网络检查完成"

  progress_set_step 1 running "正在准备 JDK $JDK_TARGET_VERSION"
  local selected
  selected="$(select_java_home)"
  if [[ -z "$selected" ]] || version_lt "$(cut -d'|' -f2 <<<"$selected")" "$JDK_TARGET_VERSION"; then
    install_jdk || {
      progress_set_step 1 failed "JDK 安装失败"
      progress_write failed 1 30 "JDK 安装失败" "null"
      return 1
    }
    get_java_candidates
  fi
  progress_set_step 1 complete "JDK 已就绪"

  progress_set_step 2 running "正在安装或升级 IDEA"
  if ! install_idea; then
    progress_set_step 2 failed "IDEA 安装失败"
    progress_write failed 2 60 "IDEA 安装失败" "null"
    return 1
  fi
  progress_set_step 2 complete "IDEA 已就绪"

  progress_set_step 3 running "正在配置环境并运行冒烟测试"
  set_java_environment || {
    progress_set_step 3 failed "没有可用 JDK"
    progress_write failed 3 80 "没有可用 JDK" "null"
    return 1
  }
  if ! run_smoke_test; then
    progress_set_step 3 failed "Hello World 验证失败"
    progress_write failed 3 80 "Hello World 验证失败" "null"
    return 1
  fi
  progress_set_step 3 complete "Hello World 验证通过"

  local result
  result="$(detection_json)"
  atomic_write "$REPORT_DIR/detection_result.json" "$result"
  progress_write success 4 100 "Java 和 IDEA 已安装并验证完成" "$result"
  log_ok "安装完成，请回到网页查看最终报告。"
  return 0
}

run_fix() {
  local fix="$1"
  open_progress_page fix >/dev/null 2>&1 || true
  progress_init fix "$fix|修复 $fix|60"
  progress_set_step 0 running "正在执行修复"
  get_java_candidates

  case "$fix" in
    java_home|path|multiple_jdks)
      set_java_environment || return 1
      ;;
    idea_repair)
      install_idea || return 1
      ;;
    gatekeeper)
      local app
      while IFS= read -r app; do
        xattr -rd com.apple.quarantine "$app" 2>/dev/null || true
      done < <(find /Applications -maxdepth 1 -type d -iname 'IntelliJ IDEA CE*.app' 2>/dev/null)
      ;;
    port)
      local port
      for port in 8080 8081 8000 3000 63342; do
        if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
          log_warn "端口 $port 已被占用"
        fi
      done
      ;;
    *)
      log_error "未知修复项：$fix"
      return 2
      ;;
  esac
  progress_set_step 0 complete "修复步骤完成"
  local result
  result="$(detection_json)"
  progress_write success 1 100 "修复完成" "$result"
  return 0
}

uninstall_idea() {
  local removed=false
  if command -v brew >/dev/null 2>&1 && brew list --cask intellij-idea-ce >/dev/null 2>&1; then
    brew uninstall --cask intellij-idea-ce && removed=true
  fi
  if [[ "$removed" == false ]]; then
    local app
    for app in /Applications/IntelliJ\ IDEA\ CE*.app "$HOME/Applications/IntelliJ IDEA CE.app"; do
      [[ -d "$app" ]] || continue
      if [[ -w "$(dirname "$app")" ]]; then
        safe_remove_tree "$app"
      else
        sudo rm -rf -- "$app"
      fi
      removed=true
    done
  fi
  [[ "$removed" == true ]]
}

remove_jetbrains_user_data() {
  local roots root directory
  roots=(
    "$HOME/Library/Application Support/JetBrains"
    "$HOME/Library/Caches/JetBrains"
    "$HOME/Library/Logs/JetBrains"
  )
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r directory; do
      safe_remove_tree "$directory" || continue
      log_info "已清理 $directory"
    done < <(find "$root" -maxdepth 1 -type d -name 'IntelliJIdea*' 2>/dev/null)
  done
  rm -f "$HOME/Library/Preferences/com.jetbrains.intellij.idea.plist"
}

run_uninstall() {
  local keep_settings="${KEEP_SETTINGS:-0}"
  log_warn "默认卸载会删除 IDEA、目标 JDK、JetBrains 设置、缓存、插件和最近项目历史。"
  log_warn "不会删除你的 Java 项目源码目录。"
  if [[ "$keep_settings" != "1" ]]; then
    printf '确认彻底清理请输入 DELETE：'
    local answer
    read -r answer
    if [[ "$answer" != "DELETE" ]]; then
      log_info "已取消卸载。"
      return 0
    fi
  fi

  open_progress_page uninstall >/dev/null 2>&1 || true
  progress_init uninstall \
    "detect|检测已安装组件|20" \
    "idea|卸载 IntelliJ IDEA Community|60" \
    "jdk|卸载目标 JDK|60" \
    "clean|清理环境变量与配置|30"

  progress_set_step 0 running "正在检测已安装组件"
  get_java_candidates
  local selected
  selected="$(select_java_home)"
  progress_set_step 0 complete "检测完成"

  progress_set_step 1 running "正在卸载 IDEA"
  uninstall_idea || log_warn "未检测到可自动卸载的 IDEA"
  progress_set_step 1 complete "IDEA 处理完成"

  progress_set_step 2 running "正在卸载 JDK"
  if command -v brew >/dev/null 2>&1; then
    brew uninstall --cask "temurin@$JDK_TARGET_VERSION" >/dev/null 2>&1 || true
    brew uninstall --cask temurin >/dev/null 2>&1 || true
  fi
  progress_set_step 2 complete "JDK 处理完成"

  progress_set_step 3 running "正在清理用户环境变量"
  if [[ "$keep_settings" != "1" ]]; then
    remove_jetbrains_user_data
  fi
  local home version source profile temp
  if [[ -n "$selected" ]]; then
    IFS='|' read -r home version _ source <<<"$selected"
  fi
  if [[ "${JAVA_HOME:-}" == "$home" ]]; then
    unset JAVA_HOME
  fi
  for profile in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [[ -f "$profile" ]] || continue
    temp="$(mktemp "${profile}.java-setup.XXXXXX")"
    awk '
      /^# >>> java-idea-installer >>>$/ { skip=1; next }
      /^# <<< java-idea-installer <<<$/ { skip=0; next }
      skip != 1 { print }
    ' "$profile" >"$temp"
    mv "$temp" "$profile"
  done
  progress_set_step 3 complete "清理完成"
  progress_write success 4 100 "卸载和清理完成" "null"
  return 0
}
