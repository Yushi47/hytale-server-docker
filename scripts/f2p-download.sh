#!/bin/sh
set -eu

log() {
  printf '%s\n' "$*" >&2
}

lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  case "$(lower "${1:-}")" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

DATA_DIR="${DATA_DIR:-/data}"
SERVER_DIR="${SERVER_DIR:-/data/server}"

check_dir_writable() {
  dir="$1"
  if [ ! -w "${dir}" ]; then
    log "ERROR: Cannot write to ${dir}"
    log "ERROR: Directory exists but is not writable by UID $(id -u)."
    log "ERROR: Current owner: $(ls -ld "${dir}" 2>/dev/null | awk '{print $3":"$4}')"
    log "ERROR: Fix: 'sudo chown -R $(id -u):$(id -g) <host-path>'"
    exit 1
  fi
}

HYTALE_SERVER_JAR="${HYTALE_SERVER_JAR:-${SERVER_DIR}/HytaleServer.jar}"
HYTALE_ASSETS_PATH="${HYTALE_ASSETS_PATH:-${DATA_DIR}/Assets.zip}"

# F2P download configuration
HYTALE_F2P_DOWNLOAD_BASE="${HYTALE_F2P_DOWNLOAD_BASE:-https://download.sanasol.ws/download}"
HYTALE_F2P_DOWNLOAD_LOCK="${HYTALE_F2P_DOWNLOAD_LOCK:-true}"
HYTALE_F2P_AUTO_UPDATE="${HYTALE_F2P_AUTO_UPDATE:-true}"

# Version tracking directory
VERSION_DIR="${DATA_DIR}/.hytale-f2p-versions"

mkdir -p "${SERVER_DIR}"
mkdir -p "${VERSION_DIR}"
check_dir_writable "${SERVER_DIR}"

# Lock to avoid multiple containers downloading into the same volume simultaneously.
LOCK_DIR="${DATA_DIR}/.hytale-download-lock"
LOCK_CREATED_AT_PATH="${LOCK_DIR}/created_at_epoch"
LOCK_TTL_SECONDS=300

lock_acquired=0

cleanup() {
  if [ "${lock_acquired}" -eq 1 ]; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
  fi
}

if is_true "${HYTALE_F2P_DOWNLOAD_LOCK}"; then
  trap cleanup EXIT INT TERM

  for _i in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
      lock_acquired=1
      now_epoch="$(date +%s 2>/dev/null || echo 0)"
      printf '%s\n' "${now_epoch}" >"${LOCK_CREATED_AT_PATH}" 2>/dev/null || true
      printf '%s\n' "$$" >"${LOCK_DIR}/pid" 2>/dev/null || true
      break
    fi

    if [ -f "${LOCK_CREATED_AT_PATH}" ]; then
      created_epoch="$(cat "${LOCK_CREATED_AT_PATH}" 2>/dev/null || echo 0)"
      now_epoch="$(date +%s 2>/dev/null || echo 0)"
      if [ "${created_epoch}" -gt 0 ] && [ $((now_epoch - created_epoch)) -ge "${LOCK_TTL_SECONDS}" ]; then
        log "F2P download: stale lock detected at ${LOCK_DIR} (older than ${LOCK_TTL_SECONDS}s); removing"
        rm -rf "${LOCK_DIR}" 2>/dev/null || true
        continue
      fi
    fi

    log "F2P download: another container may be downloading into ${DATA_DIR}; waiting for lock (${LOCK_DIR})"
    log "F2P download: if this gets stuck, delete ${LOCK_DIR} or set HYTALE_F2P_DOWNLOAD_LOCK=false (power users)"
    sleep 3
  done

  if [ "${lock_acquired}" -ne 1 ]; then
    log "ERROR: F2P download: could not acquire lock ${LOCK_DIR}"
    log "ERROR: If no other container is running, the lock may be stale. You can delete ${LOCK_DIR} and try again."
    log "ERROR: Power users can disable the lock with HYTALE_F2P_DOWNLOAD_LOCK=false"
    exit 1
  fi
else
  log "F2P download: download lock disabled via HYTALE_F2P_DOWNLOAD_LOCK=false"
fi

# Get remote ETag/Last-Modified for a URL (follows redirects)
get_remote_version() {
  _url="$1"
  # Try ETag first, fall back to Last-Modified, then Content-Length as last resort
  _headers=$(curl -sI -L "${_url}" 2>/dev/null | tr -d '\r')
  _etag=$(echo "${_headers}" | grep -i "^etag:" | tail -1 | sed 's/^[^:]*: *//' | tr -d '"')
  if [ -n "${_etag}" ]; then
    printf '%s' "${_etag}"
    return 0
  fi
  _lastmod=$(echo "${_headers}" | grep -i "^last-modified:" | tail -1 | sed 's/^[^:]*: *//')
  if [ -n "${_lastmod}" ]; then
    printf '%s' "${_lastmod}"
    return 0
  fi
  _length=$(echo "${_headers}" | grep -i "^content-length:" | tail -1 | sed 's/^[^:]*: *//')
  if [ -n "${_length}" ]; then
    printf 'size:%s' "${_length}"
    return 0
  fi
  return 1
}

# Check if file needs update (returns 0 if update needed, 1 if up-to-date)
needs_update() {
  _url="$1"
  _dest="$2"
  _name="$3"
  _version_file="${VERSION_DIR}/${_name}.version"

  # File doesn't exist - needs download
  if [ ! -f "${_dest}" ]; then
    log "F2P download: ${_name} not found, will download"
    return 0
  fi

  # Auto-update disabled - skip check
  if ! is_true "${HYTALE_F2P_AUTO_UPDATE}"; then
    log "F2P download: ${_name} exists and HYTALE_F2P_AUTO_UPDATE=false, skipping"
    return 1
  fi

  # Get remote version
  _remote_version=$(get_remote_version "${_url}" 2>/dev/null) || true
  if [ -z "${_remote_version}" ]; then
    log "F2P download: could not get remote version for ${_name}, skipping update check"
    return 1
  fi

  # Get stored version
  _local_version=""
  if [ -f "${_version_file}" ]; then
    _local_version=$(cat "${_version_file}" 2>/dev/null) || true
  fi

  # Compare versions
  if [ "${_remote_version}" = "${_local_version}" ]; then
    log "F2P download: ${_name} is up-to-date (version: ${_remote_version})"
    return 1
  fi

  if [ -n "${_local_version}" ]; then
    log "F2P download: ${_name} has update available"
    log "F2P download:   local:  ${_local_version}"
    log "F2P download:   remote: ${_remote_version}"
  else
    log "F2P download: ${_name} exists but no version recorded, checking for update"
  fi
  return 0
}

# Save version after successful download
save_version() {
  _url="$1"
  _name="$2"
  _version_file="${VERSION_DIR}/${_name}.version"

  _remote_version=$(get_remote_version "${_url}" 2>/dev/null) || true
  if [ -n "${_remote_version}" ]; then
    printf '%s\n' "${_remote_version}" > "${_version_file}"
    log "F2P download: saved version for ${_name}: ${_remote_version}"
  fi
}

# Download function with retries and line-by-line progress
download_file() {
  _url="$1"
  _dest="$2"
  _name="$3"
  _expected_mb="${4:-0}"

  log "F2P download: downloading ${_name} from ${_url}"
  if [ "${_expected_mb}" -gt 0 ] 2>/dev/null; then
    log "F2P download: expected size ~${_expected_mb} MB"
  fi

  # Use temp file for atomic download
  _tmp_dest="${_dest}.tmp"

  for _attempt in 1 2 3; do
    rm -f "${_tmp_dest}" 2>/dev/null || true

    # Start curl in background (silent mode, follow redirects)
    curl -fL -s -o "${_tmp_dest}" "${_url}" &
    _curl_pid=$!

    # Monitor progress every 5 seconds
    _last_size=0
    while kill -0 ${_curl_pid} 2>/dev/null; do
      sleep 5
      if [ -f "${_tmp_dest}" ]; then
        _current_size=$(stat -c%s "${_tmp_dest}" 2>/dev/null || stat -f%z "${_tmp_dest}" 2>/dev/null || echo "0")
        _current_mb=$((_current_size / 1024 / 1024))

        # Calculate speed
        _delta=$((_current_size - _last_size))
        _speed_mb=$((_delta / 1024 / 1024 / 5))

        if [ "${_expected_mb}" -gt 0 ] 2>/dev/null; then
          _pct=$((_current_mb * 100 / _expected_mb))
          if [ ${_speed_mb} -lt 1 ]; then
            _speed_kb=$((_delta / 1024 / 5))
            log "F2P download: ${_name} - ${_current_mb}/${_expected_mb} MB (${_pct}%) - ${_speed_kb} KB/s"
          else
            log "F2P download: ${_name} - ${_current_mb}/${_expected_mb} MB (${_pct}%) - ${_speed_mb} MB/s"
          fi
        else
          if [ ${_speed_mb} -lt 1 ]; then
            _speed_kb=$((_delta / 1024 / 5))
            log "F2P download: ${_name} - ${_current_mb} MB - ${_speed_kb} KB/s"
          else
            log "F2P download: ${_name} - ${_current_mb} MB - ${_speed_mb} MB/s"
          fi
        fi
        _last_size=${_current_size}
      fi
    done

    # Check if curl succeeded
    wait ${_curl_pid}
    _curl_exit=$?

    if [ ${_curl_exit} -eq 0 ] && [ -f "${_tmp_dest}" ]; then
      _final_size=$(stat -c%s "${_tmp_dest}" 2>/dev/null || stat -f%z "${_tmp_dest}" 2>/dev/null || echo "0")
      _final_mb=$((_final_size / 1024 / 1024))
      log "F2P download: ${_name} downloaded (${_final_mb} MB)"
      mv "${_tmp_dest}" "${_dest}"
      return 0
    fi

    log "F2P download: attempt ${_attempt} failed for ${_name}, retrying..."
    rm -f "${_tmp_dest}" 2>/dev/null || true
    sleep 2
  done

  log "ERROR: F2P download: failed to download ${_name} after 3 attempts"
  rm -f "${_tmp_dest}" 2>/dev/null || true
  return 1
}

# Download HytaleServer.jar if missing or outdated
JAR_URL="${HYTALE_F2P_DOWNLOAD_BASE}/HytaleServer.jar"
if needs_update "${JAR_URL}" "${HYTALE_SERVER_JAR}" "HytaleServer.jar"; then
  if download_file "${JAR_URL}" "${HYTALE_SERVER_JAR}" "HytaleServer.jar" "80"; then
    save_version "${JAR_URL}" "HytaleServer.jar"
  else
    log "ERROR: Failed to download HytaleServer.jar"
    log "ERROR: Check if ${JAR_URL} is accessible"
    exit 1
  fi
fi

# Download DualAuth Agent JAR if missing or outdated
DUALAUTH_AGENT_JAR="/opt/dualauth-agent/dualauth-agent.jar"
DUALAUTH_AGENT_LOCAL="${SERVER_DIR}/dualauth-agent.jar"
DUALAUTH_AGENT_URL="https://github.com/sanasol/hytale-auth-server/releases/latest/download/dualauth-agent.jar"
if [ ! -f "${DUALAUTH_AGENT_JAR}" ] && [ ! -f "${DUALAUTH_AGENT_LOCAL}" ]; then
  log "F2P download: DualAuth Agent not found, downloading from GitHub releases..."
  if download_file "${DUALAUTH_AGENT_URL}" "${DUALAUTH_AGENT_LOCAL}" "dualauth-agent.jar" "5"; then
    save_version "${DUALAUTH_AGENT_URL}" "dualauth-agent.jar"
    log "F2P download: DualAuth Agent downloaded to ${DUALAUTH_AGENT_LOCAL}"
  else
    log "WARNING: Failed to download DualAuth Agent (server will start without dual auth)"
  fi
elif needs_update "${DUALAUTH_AGENT_URL}" "${DUALAUTH_AGENT_LOCAL}" "dualauth-agent.jar" 2>/dev/null; then
  if download_file "${DUALAUTH_AGENT_URL}" "${DUALAUTH_AGENT_LOCAL}" "dualauth-agent.jar" "5"; then
    save_version "${DUALAUTH_AGENT_URL}" "dualauth-agent.jar"
  fi
fi

# Download Assets.zip if missing or outdated
ASSETS_URL="${HYTALE_F2P_DOWNLOAD_BASE}/Assets.zip"
if needs_update "${ASSETS_URL}" "${HYTALE_ASSETS_PATH}" "Assets.zip"; then
  log "F2P download: Assets.zip is a large file, this may take a while..."
  if download_file "${ASSETS_URL}" "${HYTALE_ASSETS_PATH}" "Assets.zip" "3300"; then
    save_version "${ASSETS_URL}" "Assets.zip"
  else
    log "ERROR: Failed to download Assets.zip"
    log "ERROR: Check if ${ASSETS_URL} is accessible"
    exit 1
  fi
fi

# Verify files
if [ ! -f "${HYTALE_SERVER_JAR}" ]; then
  log "ERROR: F2P download: HytaleServer.jar not found after download at ${HYTALE_SERVER_JAR}"
  exit 1
fi

if [ ! -f "${HYTALE_ASSETS_PATH}" ]; then
  log "ERROR: F2P download: Assets.zip not found after download at ${HYTALE_ASSETS_PATH}"
  exit 1
fi

# Mark download source
printf 'f2p\n' > "${DATA_DIR}/.hytale-download-source"

log "F2P download: done"
log "F2P download: Server JAR: ${HYTALE_SERVER_JAR}"
log "F2P download: Assets: ${HYTALE_ASSETS_PATH}"
