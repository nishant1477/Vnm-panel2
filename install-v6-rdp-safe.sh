#!/usr/bin/env bash

# ============================================================
# VNM PANEL V3 — RDP-SAFE ULTRA INSTALLER V6
# GitHub ZIP -> validate -> stage -> swap -> run -> health check
#
# Development build:
#   LICENSE_MODE=disabled
#   No license prompt
#
# Safety:
#   - Validates ZIP integrity before touching the live app
#   - Detects/selects an RDP-enabled ZIP automatically
#   - Stages the new build before stopping the current panel
#   - Preserves the existing SESSION_SECRET
#   - Backs up the previous application before replacement
#   - Attempts automatic rollback if the new build fails after swap
#   - Avoids pipefail/SIGPIPE false positives in RDP/port detection
#   - Keeps bundled node_modules when present
#   - Rebuilds sqlite3/ssh2 only when they fail to load
# ============================================================

set -Eeuo pipefail

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
MAGENTA='\e[1;35m'
NC='\e[0m'

REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'

INSTALL_DIR='/opt/hkvm'
APP_DIR="${INSTALL_DIR}/app"
DATA_DIR="${INSTALL_DIR}/data"
LOG_DIR="${INSTALL_DIR}/logs"
BACKUP_DIR="${INSTALL_DIR}/backups"
STAGING_DIR="${INSTALL_DIR}/.staging"
CONFIG_DIR='/etc/hkvm'
ENV_FILE="${CONFIG_DIR}/hkvm.env"
LOG_FILE="${LOG_DIR}/hkvm.log"
PID_FILE="${INSTALL_DIR}/hkvm.pid"
BUILD_INFO_FILE="${DATA_DIR}/install-build-info.txt"

SERVICE_NAME='hkvm'
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PANEL_PORT='8080'

TMP_DIR=''
HAS_SYSTEMD='false'
NODE_BIN=''
NPM_BIN=''
MAIN_JS=''

SELECTED_ZIP=''
ZIP_SHA256=''
ZIP_SIZE_BYTES='0'
REPO_COMMIT='unknown'

RDP_SOURCE_STATUS='NOT_DETECTED'
RDP_INSTALL_STATUS='NOT_DETECTED'
RDP_MARKER_FILE=''

SWAP_STARTED='false'
OLD_APP_BACKUP=''
OLD_ENV_BACKUP=''

line() {
  echo -e "${MAGENTA}============================================================${NC}"
}

info() {
  echo -e "${CYAN}[VNM PANEL][INFO]${NC} $*"
}

ok() {
  echo -e "${GREEN}[VNM PANEL][OK]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[VNM PANEL][WARNING]${NC} $*"
}

error() {
  echo -e "${RED}[VNM PANEL][ERROR]${NC} $*"
}

cleanup() {
  [[ -z "${TMP_DIR}" || ! -d "${TMP_DIR}" ]] || rm -rf "${TMP_DIR}" || true
  [[ ! -d "${STAGING_DIR}" ]] || rm -rf "${STAGING_DIR}" || true
}

restore_old_install() {
  local rollback_pid=''

  [[ "${SWAP_STARTED}" == 'true' ]] || return 0

  warn 'Attempting automatic rollback to the previous VNM Panel build...'

  if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  elif [[ -f "${PID_FILE}" ]]; then
    rollback_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ "${rollback_pid}" =~ ^[0-9]+$ ]]; then
      kill "${rollback_pid}" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "${rollback_pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${PID_FILE}"
  fi

  rm -rf "${APP_DIR}" || true

  if [[ -n "${OLD_APP_BACKUP}" && -d "${OLD_APP_BACKUP}" ]]; then
    mv "${OLD_APP_BACKUP}" "${APP_DIR}" || true
  fi

  if [[ -n "${OLD_ENV_BACKUP}" && -f "${OLD_ENV_BACKUP}" ]]; then
    cp -f "${OLD_ENV_BACKUP}" "${ENV_FILE}" || true
  else
    rm -f "${ENV_FILE}" || true
  fi

  if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart "${SERVICE_NAME}" >/dev/null 2>&1 || true
  elif [[ -f "${APP_DIR}/app.js" && -x "${NODE_BIN}" ]]; then
    set -a
    if [[ -f "${ENV_FILE}" ]]; then
      # shellcheck disable=SC1090
      source "${ENV_FILE}" || true
    fi
    set +a

    nohup "${NODE_BIN}" "${APP_DIR}/app.js" >>"${LOG_FILE}" 2>&1 &
    echo "$!" > "${PID_FILE}" || true
  fi

  warn 'Rollback attempted. Check the panel log before retrying.'
}

on_error() {
  local rc=$?

  error "Installer failed at line ${BASH_LINENO[0]} (exit ${rc})."

  if [[ -f "${LOG_FILE}" ]]; then
    echo '---------------- VNM PANEL LOG ----------------'
    tail -n 160 "${LOG_FILE}" || true
    echo '-----------------------------------------------'
  fi

  if [[ "${SWAP_STARTED}" == 'true' ]]; then
    restore_old_install || true
  fi

  exit "${rc}"
}

trap cleanup EXIT
trap on_error ERR

has_rdp_code() {
  local root="$1"
  local marker=''

  [[ -d "${root}" ]] || return 1

  # Do not use find | grep -q here: with pipefail, find may return 141
  # after grep exits early, causing a false negative.
  marker="$(
    find "${root}" \
      -type f \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      \( -name 'vm-detail.ejs' -o -name 'rdp.js' \) \
      -print -quit \
      2>/dev/null || true
  )"

  if [[ -n "${marker}" ]]; then
    return 0
  fi

  grep -RIsm1 \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --include='*.js' \
    --include='*.ejs' \
    --include='*.html' \
    --include='*.json' \
    -E 'tab-rdp|Enable RDP|Install RDP|RDP.*Online|RDP.*Disabled' \
    "${root}" >/dev/null 2>&1
}

find_app_root() {
  local root="$1"
  local candidate=''
  local pkg=''

  mapfile -t APP_FILES < <(
    find "${root}" \
      -type f \
      -name app.js \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      -print |
    sort
  )

  for candidate in "${APP_FILES[@]:-}"; do
    [[ -n "${candidate}" ]] || continue
    if [[ -f "$(dirname "${candidate}")/package.json" ]]; then
      dirname "${candidate}"
      return 0
    fi
  done

  mapfile -t PACKAGE_FILES < <(
    find "${root}" \
      -type f \
      -name package.json \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      -print |
    sort
  )

  for pkg in "${PACKAGE_FILES[@]:-}"; do
    if "${NODE_BIN}" -e \
      'const p=require(process.argv[1]); process.exit(typeof p.main==="string"&&p.main.trim()?0:1)' \
      "${pkg}" >/dev/null 2>&1; then
      dirname "${pkg}"
      return 0
    fi
  done

  return 1
}

stop_old_instance() {
  local old_pid=''
  local LPID=''
  local CMD=''
  local CWD=''

  if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  if [[ -f "${PID_FILE}" ]]; then
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"

    if [[ "${old_pid}" =~ ^[0-9]+$ ]]; then
      kill "${old_pid}" >/dev/null 2>&1 || true

      for _ in {1..20}; do
        kill -0 "${old_pid}" >/dev/null 2>&1 || break
        sleep 0.2
      done

      kill -9 "${old_pid}" >/dev/null 2>&1 || true
    fi

    rm -f "${PID_FILE}"
  fi

  if command -v lsof >/dev/null 2>&1; then
    mapfile -t LISTEN_PIDS < <(
      lsof -t -nP -iTCP:"${PANEL_PORT}" -sTCP:LISTEN 2>/dev/null || true
    )

    for LPID in "${LISTEN_PIDS[@]:-}"; do
      [[ "${LPID}" =~ ^[0-9]+$ ]] || continue

      CMD="$(ps -p "${LPID}" -o args= 2>/dev/null || true)"
      CWD="$(readlink -f "/proc/${LPID}/cwd" 2>/dev/null || true)"

      if [[ "${CWD}" == "${APP_DIR}" ]] ||
         [[ "${CMD}" == *"${APP_DIR}/app.js"* ]]; then

        warn "Stopping old VNM Panel listener PID ${LPID} on port ${PANEL_PORT}."

        kill "${LPID}" >/dev/null 2>&1 || true

        for _ in {1..20}; do
          kill -0 "${LPID}" >/dev/null 2>&1 || break
          sleep 0.2
        done

        kill -9 "${LPID}" >/dev/null 2>&1 || true
      else
        error "Port ${PANEL_PORT} is already used by another process (PID ${LPID})."
        return 1
      fi
    done
  fi
}

validate_native_modules() {
  local output=''

  output="$(
    cd "${APP_DIR}" &&
    "${NODE_BIN}" <<'NODE'
let failed = false;

for (const mod of ['sqlite3', 'ssh2']) {
  try {
    require(mod);
    console.log(`[MODULE_OK] ${mod}`);
  } catch (err) {
    failed = true;
    console.log(
      `[MODULE_FAIL] ${mod}: ${err && err.message ? err.message : err}`
    );
  }
}

process.exit(failed ? 1 : 0);
NODE
  )" || true

  echo "${output}"

  grep -q '^\[MODULE_OK\] sqlite3$' <<<"${output}" || return 1
  grep -q '^\[MODULE_OK\] ssh2$' <<<"${output}" || return 1
  return 0
}

validate_app() {
  [[ -f "${APP_DIR}/app.js" ]] || return 1
  [[ -f "${APP_DIR}/package.json" ]] || return 1
  [[ -d "${APP_DIR}/node_modules" ]] || return 1
  "${NODE_BIN}" --check "${APP_DIR}/app.js"
}

write_env() {
  cat > "${ENV_FILE}" <<EOF_ENV
NODE_ENV=production
PORT=${PANEL_PORT}
PANEL_NAME="VNM Panel"
SESSION_SECRET=${SESSION_SECRET}

LICENSE_MODE=disabled
LICENSE_KEY=

HKVM_INSTALL_DIR=${INSTALL_DIR}
HKVM_APP_DIR=${APP_DIR}
HKVM_DATA_DIR=${DATA_DIR}
HKVM_LOG_DIR=${LOG_DIR}

VNM_DATA_DIR=${DATA_DIR}
EOF_ENV

  chmod 600 "${ENV_FILE}"
  chown root:root "${ENV_FILE}"
}

clear 2>/dev/null || true

echo -e "${CYAN}"
cat <<'ASCII'

██╗   ██╗███╗   ██╗███╗   ███╗
██║   ██║████╗  ██║████╗ ████║
██║   ██║██╔██╗ ██║██╔████╔██║
╚██╗ ██╔╝██║╚██╗██║██║╚██╔╝██║
 ╚████╔╝ ██║ ╚████║██║ ╚═╝ ██║
  ╚═══╝  ╚═╝  ╚═══╝╚═╝     ╚═╝

                 VNM
           VNM PANEL V3
        RDP-SAFE ULTRA INSTALLER V6

ASCII
echo -e "${NC}"
line

# ============================================================
# ROOT / OS
# ============================================================

[[ ${EUID} -eq 0 ]] || { error 'Please run this installer as root.'; exit 1; }
[[ -f /etc/os-release ]] || { error 'Unable to detect operating system.'; exit 1; }

# shellcheck disable=SC1091
source /etc/os-release

info "Operating System : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"
info "Kernel           : $(uname -r)"

if [[ "${ID:-}" != 'ubuntu' && "${ID:-}" != 'debian' ]]; then
  error "Unsupported OS: ${ID:-unknown}."
  exit 1
fi

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  HAS_SYSTEMD='true'
  ok 'systemd detected — service mode enabled.'
else
  warn 'systemd not detected — standalone/background mode enabled.'
  info 'This is normal in GitHub Codespaces and containers.'
fi

line

# ============================================================
# PACKAGES
# ============================================================

export DEBIAN_FRONTEND=noninteractive

info 'Updating package lists...'
apt-get update -y

info 'Installing base dependencies...'
apt-get install -y \
  ca-certificates \
  curl \
  git \
  unzip \
  file \
  lsof \
  procps \
  iproute2 \
  openssl \
  build-essential \
  python3

if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
  info 'Installing virtualization dependencies...'
  apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    ovmf \
    cloud-init \
    libvirt-daemon-system \
    libvirt-clients
else
  warn 'Skipping libvirt/QEMU host packages because systemd is unavailable.'
fi

ok 'System dependencies installed.'
line

# ============================================================
# NODE / NPM
# ============================================================

NODE_OK='false'

if command -v node >/dev/null 2>&1; then
  NODE_VERSION="$(node -v | sed 's/^v//')"
  NODE_MAJOR="${NODE_VERSION%%.*}"

  if [[ "${NODE_MAJOR}" =~ ^[0-9]+$ ]] && (( NODE_MAJOR >= 20 )); then
    NODE_OK='true'
  fi

  info "Detected Node.js: v${NODE_VERSION}"
fi

if [[ "${NODE_OK}" != 'true' ]]; then
  info 'Installing Node.js 22...'
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

command -v node >/dev/null 2>&1 || { error 'Node.js installation failed.'; exit 1; }
command -v npm >/dev/null 2>&1 || { error 'npm installation failed.'; exit 1; }

NODE_BIN="$(readlink -f "$(command -v node)" 2>/dev/null || command -v node)"
NPM_BIN="$(readlink -f "$(command -v npm)" 2>/dev/null || command -v npm)"

[[ -x "${NODE_BIN}" ]] || { error "Resolved Node binary is not executable: ${NODE_BIN}"; exit 1; }
[[ -x "${NPM_BIN}" ]] || { error "Resolved npm binary is not executable: ${NPM_BIN}"; exit 1; }

ok "Node.js: $("${NODE_BIN}" -v) | npm: $("${NPM_BIN}" -v)"
info "Node binary: ${NODE_BIN}"
line

# ============================================================
# STORAGE / CONFIG SNAPSHOT
# ============================================================

mkdir -p \
  "${INSTALL_DIR}" \
  "${DATA_DIR}" \
  "${LOG_DIR}" \
  "${BACKUP_DIR}" \
  "${CONFIG_DIR}"

chmod 755 "${INSTALL_DIR}" "${DATA_DIR}" "${LOG_DIR}"
chmod 700 "${BACKUP_DIR}" "${CONFIG_DIR}"

touch "${LOG_FILE}"
chmod 640 "${LOG_FILE}"

EXISTING_SESSION_SECRET=''

if [[ -f "${ENV_FILE}" ]]; then
  OLD_ENV_BACKUP="${BACKUP_DIR}/hkvm.env.$(date +%Y%m%d-%H%M%S).bak"
  cp -a "${ENV_FILE}" "${OLD_ENV_BACKUP}"

  EXISTING_SESSION_SECRET="$(
    sed -n 's/^SESSION_SECRET=//p' "${ENV_FILE}" |
    head -n 1 |
    sed 's/^"//; s/"$//' ||
    true
  )"

  ok 'Existing configuration backed up.'
fi

line

# ============================================================
# GITHUB -> ZIP
# ============================================================

TMP_DIR="$(mktemp -d -t vnm-panel-installer-XXXXXX)"
REPO_DIR="${TMP_DIR}/repo"
EXTRACT_DIR="${TMP_DIR}/extract"

mkdir -p "${EXTRACT_DIR}"

info 'Cloning VNM Panel repository directly...'
git clone --depth 1 --single-branch "${REPO_URL}" "${REPO_DIR}"

REPO_COMMIT="$(git -C "${REPO_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
ok "Repository cloned: ${REPO_COMMIT}"

mapfile -t AVAILABLE_ZIPS < <(
  find "${REPO_DIR}" \
    -maxdepth 1 \
    -type f \
    -iname '*.zip' \
    -printf '%f\n' |
  sort
)

if ((${#AVAILABLE_ZIPS[@]} == 0)); then
  error 'No VNM Panel ZIP archive was found in the repository.'
  exit 1
fi

info "ZIP archives found: ${AVAILABLE_ZIPS[*]}"

for CANDIDATE in "${AVAILABLE_ZIPS[@]}"; do
  CANDIDATE_PATH="${REPO_DIR}/${CANDIDATE}"
  CANDIDATE_SIZE="$(stat -c '%s' "${CANDIDATE_PATH}" 2>/dev/null || echo 0)"

  if (( CANDIDATE_SIZE < 1048576 )); then
    warn "Skipping suspiciously small archive: ${CANDIDATE}"
    continue
  fi

  info "Checking archive: ${CANDIDATE}"

  if ! unzip -tq "${CANDIDATE_PATH}" >/dev/null 2>&1; then
    warn "ZIP integrity test failed: ${CANDIDATE}"
    continue
  fi

  TEST_DIR="${TMP_DIR}/test-${RANDOM}-${RANDOM}"
  mkdir -p "${TEST_DIR}"

  if ! unzip -q "${CANDIDATE_PATH}" -d "${TEST_DIR}"; then
    warn "Could not extract ${CANDIDATE}; skipping."
    rm -rf "${TEST_DIR}"
    continue
  fi

  if has_rdp_code "${TEST_DIR}"; then
    SELECTED_ZIP="${CANDIDATE}"
    rm -rf "${TEST_DIR}"
    ok "RDP-enabled build selected: ${CANDIDATE}"
    break
  fi

  rm -rf "${TEST_DIR}"
done

if [[ -z "${SELECTED_ZIP}" ]]; then
  error 'No valid RDP-enabled VNM Panel ZIP was found.'
  exit 1
fi

ZIP_FILE="${REPO_DIR}/${SELECTED_ZIP}"
ZIP_SIZE_BYTES="$(stat -c '%s' "${ZIP_FILE}")"
ZIP_SHA256="$(sha256sum "${ZIP_FILE}" | awk '{print $1}')"

info "Selected ZIP : ${SELECTED_ZIP}"
info "ZIP size     : ${ZIP_SIZE_BYTES} bytes"
info "ZIP SHA-256  : ${ZIP_SHA256}"

unzip -q "${ZIP_FILE}" -d "${EXTRACT_DIR}"

if has_rdp_code "${EXTRACT_DIR}"; then
  RDP_SOURCE_STATUS='DETECTED'
  ok 'RDP code confirmed in the selected ZIP.'
else
  error 'Selected ZIP contains no RDP feature.'
  exit 1
fi

line

# ============================================================
# DISCOVER APP ROOT BEFORE TOUCHING LIVE APP
# ============================================================

info 'Detecting real VNM Panel application root...'

SOURCE_APP_DIR="$(find_app_root "${EXTRACT_DIR}" || true)"

if [[ -z "${SOURCE_APP_DIR}" ]]; then
  error 'Unable to locate the real VNM Panel application root.'
  exit 1
fi

if [[ "${SOURCE_APP_DIR}" == *'/node_modules/'* ]]; then
  error 'Safety failure: application root is inside node_modules.'
  exit 1
fi

info "Application root: ${SOURCE_APP_DIR}"

# ============================================================
# STAGING
# ============================================================

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

info 'Copying new build into staging...'
cp -a "${SOURCE_APP_DIR}/." "${STAGING_DIR}/"

[[ -f "${STAGING_DIR}/app.js" ]] || { error 'Staged app.js is missing.'; exit 1; }
[[ -f "${STAGING_DIR}/package.json" ]] || { error 'Staged package.json is missing.'; exit 1; }

ok 'Application staged successfully.'

# ============================================================
# STAGED DEPENDENCIES
# ============================================================

VALIDATION_APP_DIR="${APP_DIR}"
APP_DIR="${STAGING_DIR}"

cd "${APP_DIR}"

if [[ -d "${APP_DIR}/node_modules" ]]; then
  ok 'Bundled node_modules detected — keeping bundled dependencies.'
else
  info 'Bundled node_modules not found — installing production dependencies...'

  if [[ -f package-lock.json ]]; then
    if ! "${NPM_BIN}" ci --omit=dev; then
      warn 'npm ci failed; retrying with npm install --omit=dev.'
      "${NPM_BIN}" install --omit=dev
    fi
  else
    "${NPM_BIN}" install --omit=dev
  fi
fi

[[ -d "${APP_DIR}/node_modules" ]] || {
  error 'node_modules is missing after dependency installation.'
  exit 1
}

info 'Validating sqlite3 and ssh2 in staging...'

if validate_native_modules; then
  ok 'sqlite3 and ssh2 loaded successfully — rebuild skipped.'
else
  warn 'sqlite3/ssh2 did not load; performing targeted native rebuild...'
  "${NPM_BIN}" rebuild sqlite3 ssh2 --foreground-scripts

  validate_native_modules || {
    error 'sqlite3/ssh2 still fail after native rebuild.'
    exit 1
  }

  ok 'Native modules rebuilt successfully.'
fi

"${NODE_BIN}" --check "${APP_DIR}/app.js" || {
  error 'Staged application syntax check failed.'
  exit 1
}

ok 'Staged application syntax check passed.'

if has_rdp_code "${APP_DIR}"; then
  RDP_INSTALL_STATUS='DETECTED'

  RDP_MARKER_FILE="$(
    find "${APP_DIR}" \
      -type f \
      -not -path '*/node_modules/*' \
      \( -name 'vm-detail.ejs' -o -name 'rdp.js' \) \
      -print -quit \
      2>/dev/null ||
      true
  )"

  ok 'RDP feature confirmed in staged application.'
else
  error 'RDP feature is missing from staged application.'
  exit 1
fi

APP_DIR="${VALIDATION_APP_DIR}"

line

# ============================================================
# SESSION SECRET
# ============================================================

if [[ -n "${EXISTING_SESSION_SECRET}" ]]; then
  SESSION_SECRET="${EXISTING_SESSION_SECRET}"
else
  SESSION_SECRET="$(openssl rand -hex 32)"
fi

[[ -n "${SESSION_SECRET}" ]] || {
  error 'Failed to create a session secret.'
  exit 1
}

# ============================================================
# LIVE SWAP
# ============================================================

info 'Staging is fully validated. Stopping live panel and switching build...'

stop_old_instance

SWAP_STARTED='true'

if [[ -d "${APP_DIR}" ]]; then
  OLD_APP_BACKUP="${BACKUP_DIR}/app.$(date +%Y%m%d-%H%M%S)"
  mv "${APP_DIR}" "${OLD_APP_BACKUP}"
  ok "Previous application backed up to ${OLD_APP_BACKUP}."
fi

mkdir -p "${APP_DIR}"

# Move normal files.
shopt -s dotglob nullglob
STAGED_ITEMS=("${STAGING_DIR}"/*)
if ((${#STAGED_ITEMS[@]} > 0)); then
  mv "${STAGED_ITEMS[@]}" "${APP_DIR}/"
fi
shopt -u dotglob nullglob

rm -f "${APP_DIR}/.env" "${APP_DIR}/.env.generated" 2>/dev/null || true

[[ -f "${APP_DIR}/app.js" ]] || {
  error 'Live swap failed: app.js is missing.'
  exit 1
}

write_env

ln -sfn "${ENV_FILE}" "${APP_DIR}/.env"
[[ -L "${APP_DIR}/.env" ]] || {
  error 'Failed to create .env symlink.'
  exit 1
}

MAIN_JS="${APP_DIR}/app.js"

"${NODE_BIN}" --check "${MAIN_JS}" || {
  error 'Application syntax check failed after live swap.'
  exit 1
}

ok 'Live application syntax check passed.'

# ============================================================
# CSRF COMPATIBILITY PATCH
# ============================================================

info 'Checking login/CSRF compatibility...'

cp -a \
  "${MAIN_JS}" \
  "${BACKUP_DIR}/app.js.preinstall.$(date +%Y%m%d-%H%M%S).bak"

python3 - "${MAIN_JS}" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')

pattern = re.compile(
    r'function\s+csrfProtection\s*\(\s*req\s*,\s*res\s*,\s*next\s*\)\s*\{',
    re.S,
)

m = pattern.search(s)

if not m:
    print('NO_NAMED_CSRF_FUNCTION')
    raise SystemExit(0)

brace = s.find('{', m.start())
depth = 0
end = None

for i in range(brace, len(s)):
    ch = s[i]
    if ch == '{':
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit('Could not safely parse csrfProtection')

new = r"""
function csrfProtection(req, res, next) {
  const mutating = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method);

  const requestPath = (
    req.originalUrl ||
    req.url ||
    req.path ||
    '/'
  )
    .split('?')[0]
    .replace(/\/+$/, '') || '/';

  const isLogin =
    requestPath === '/login' ||
    requestPath === '/api/login';

  if (
    !mutating ||
    isLogin ||
    requestPath.startsWith('/api/auth/')
  ) {
    return next();
  }

  const headerToken = req.get('x-csrf-token');

  if (
    !headerToken ||
    headerToken !== req.session.csrfToken
  ) {
    console.warn(
      `[CSRF] Rejected ${req.method} ${requestPath} (bad/missing token) from ${req.ip}`
    );

    return res
      .status(403)
      .json({
        error: 'Invalid or missing CSRF token'
      });
  }

  next();
}
""".lstrip()

p.write_text(s[:m.start()] + new + s[end:], encoding='utf-8')
print('PATCHED_CSRF_FUNCTION')
PY

"${NODE_BIN}" --check "${MAIN_JS}" || {
  error 'Application syntax check failed after CSRF patch.'
  exit 1
}

ok 'Login compatibility check completed.'

# ============================================================
# BUILD INFO
# ============================================================

cat > "${BUILD_INFO_FILE}" <<EOF_BUILD
VNM_INSTALLER_VERSION=V6-RDP-SAFE
INSTALL_TIMESTAMP=$(date -Is)
REPOSITORY=${REPO_URL}
REPOSITORY_COMMIT=${REPO_COMMIT}
ZIP_NAME=${SELECTED_ZIP}
ZIP_SIZE_BYTES=${ZIP_SIZE_BYTES}
ZIP_SHA256=${ZIP_SHA256}
RDP_IN_SOURCE=${RDP_SOURCE_STATUS}
RDP_IN_INSTALL=${RDP_INSTALL_STATUS}
RDP_MARKER_FILE=${RDP_MARKER_FILE:-NONE}
APP_DIR=${APP_DIR}
PANEL_PORT=${PANEL_PORT}
EOF_BUILD

chmod 640 "${BUILD_INFO_FILE}"

# ============================================================
# FIREWALL
# ============================================================

if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

line

# ============================================================
# SYSTEMD / STANDALONE
# ============================================================

if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
  info 'Creating systemd service...'

  cat > "${SERVICE_FILE}" <<EOF_SERVICE
[Unit]
Description=VNM Panel V3
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${NODE_BIN} ${MAIN_JS}
Restart=always
RestartSec=5
User=root
Group=root
LimitNOFILE=1048576
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  chmod 644 "${SERVICE_FILE}"

  systemd-analyze verify "${SERVICE_FILE}" || {
    error 'systemd service validation failed.'
    exit 1
  }

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
  : > "${LOG_FILE}"
  systemctl restart "${SERVICE_NAME}"

  sleep 5

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok 'VNM Panel service is ONLINE.'
  else
    error 'VNM Panel service failed to start.'
    systemctl status "${SERVICE_NAME}" --no-pager --full || true
    journalctl -u "${SERVICE_NAME}" -n 200 --no-pager || true
    exit 1
  fi
else
  info 'Starting VNM Panel in standalone/background mode...'

  : > "${LOG_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a

  nohup \
    "${NODE_BIN}" \
    "${MAIN_JS}" \
    >>"${LOG_FILE}" 2>&1 &

  VNM_PANEL_PID=$!
  echo "${VNM_PANEL_PID}" > "${PID_FILE}"

  sleep 5

  if kill -0 "${VNM_PANEL_PID}" >/dev/null 2>&1; then
    ok "VNM Panel process is running (PID ${VNM_PANEL_PID})."
  else
    error 'VNM Panel process exited during startup.'
    echo '---------------- VNM PANEL STARTUP LOG ----------------'
    tail -n 240 "${LOG_FILE}" || true
    echo '--------------------------------------------------------'
    exit 1
  fi
fi

# Successful start: do not rollback on later non-critical health warnings.
SWAP_STARTED='false'

line

# ============================================================
# HEALTH CHECKS
# ============================================================

info "Checking panel port ${PANEL_PORT}..."

PANEL_STATUS='OFFLINE'

for _ in {1..20}; do
  if ss -ltn 2>/dev/null |
     grep -E ":${PANEL_PORT}([[:space:]]|$)" >/dev/null; then
    PANEL_STATUS='ONLINE'
    break
  fi
  sleep 1
done

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then
  ok "Port ${PANEL_PORT} is listening."
else
  warn "Port ${PANEL_PORT} is not listening."
fi

HTTP_STATUS="$(
  curl \
    -sS \
    -o /dev/null \
    -w '%{http_code}' \
    --max-time 8 \
    "http://127.0.0.1:${PANEL_PORT}/" \
    2>/dev/null ||
    true
)"

if [[ "${HTTP_STATUS}" =~ ^[0-9]{3}$ && "${HTTP_STATUS}" != '000' ]]; then
  ok "HTTP health check returned ${HTTP_STATUS}."
else
  warn 'HTTP health check did not return a response.'
fi

PUBLIC_IP="$(
  curl \
    -4 \
    -fsS \
    --max-time 10 \
    https://api.ipify.org \
    2>/dev/null ||
    true
)"

if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi

[[ -n "${PUBLIC_IP}" ]] || PUBLIC_IP='YOUR_SERVER_IP'

if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
  PROCESS_STATUS='RUNNING'
  MODE='SYSTEMD'
else
  PROCESS_STATUS='RUNNING'
  MODE='STANDALONE'
fi

clear 2>/dev/null || true

echo -e "${GREEN}"
cat <<EOF_FINAL

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                         VNM                                ║
║                    VNM PANEL V3                            ║
║                 INSTALLATION COMPLETE                     ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

  STATUS              : ${PANEL_STATUS}
  HTTP STATUS         : ${HTTP_STATUS}
  LICENSE STATUS      : DISABLED
  RDP STATUS          : ${RDP_INSTALL_STATUS}
  PANEL URL           : http://${PUBLIC_IP}:${PANEL_PORT}

  INSTALL DIRECTORY   : ${INSTALL_DIR}
  APPLICATION         : ${APP_DIR}
  ENTRYPOINT          : ${MAIN_JS}
  DATA DIRECTORY      : ${DATA_DIR}
  CONFIGURATION       : ${ENV_FILE}
  SERVICE             : ${SERVICE_NAME}
  PROCESS             : ${PROCESS_STATUS}
  MODE                : ${MODE}
  NODE BINARY         : ${NODE_BIN}
  LOG FILE            : ${LOG_FILE}
  BUILD INFO          : ${BUILD_INFO_FILE}

──────────────────────────────────────────────────────────────

  VPS SERVICE COMMANDS

    systemctl start ${SERVICE_NAME}
    systemctl stop ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}
    systemctl status ${SERVICE_NAME}
    journalctl -u ${SERVICE_NAME} -f

  STANDALONE / CODESPACES

    cat ${PID_FILE}
    tail -f ${LOG_FILE}

──────────────────────────────────────────────────────────────

  SOURCE REPOSITORY

    ${REPO_URL}

  REPOSITORY COMMIT

    ${REPO_COMMIT}

  ZIP SOURCE

    ${SELECTED_ZIP}

  ZIP SHA-256

    ${ZIP_SHA256}

  RDP SOURCE

    ${RDP_SOURCE_STATUS}

  RDP INSTALLED

    ${RDP_INSTALL_STATUS}

  ROLLBACK BACKUP

    ${OLD_APP_BACKUP:-NONE}

  LICENSE

    DISABLED — no key is required for this development build.

╚════════════════════════════════════════════════════════════╝

EOF_FINAL
echo -e "${NC}"

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then
  ok "VNM Panel is running on port ${PANEL_PORT}."
else
  warn "VNM Panel installed, but port ${PANEL_PORT} is not listening yet."
  warn "Check: tail -n 240 ${LOG_FILE}"
fi

line
echo -e "${CYAN}VNM Panel V6 installation finished.${NC}"
