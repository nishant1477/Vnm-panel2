
set -Eeuo pipefail

# ============================================================
# VNM PANEL V3 — FRESH ULTRA INSTALLER V6
# GitHub ZIP -> verify -> detect RDP build -> install -> run
# ============================================================

RED='\e[1;31m'; GREEN='\e[1;32m'; YELLOW='\e[1;33m'
CYAN='\e[1;36m'; MAGENTA='\e[1;35m'; NC='\e[0m'

REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'
ZIP_CANDIDATES=('VNM-Panel.zip' 'Vnm-Panel.zip' 'Vnm-panel.zip')

INSTALL_DIR='/opt/hkvm'
APP_DIR="${INSTALL_DIR}/app"
DATA_DIR="${INSTALL_DIR}/data"
LOG_DIR="${INSTALL_DIR}/logs"
BACKUP_DIR="${INSTALL_DIR}/backups"
CONFIG_DIR='/etc/hkvm'
ENV_FILE="${CONFIG_DIR}/hkvm.env"
LOG_FILE="${LOG_DIR}/hkvm.log"
PID_FILE="${INSTALL_DIR}/hkvm.pid"
BUILD_INFO_FILE="${DATA_DIR}/install-build-info.txt"
SERVICE_NAME='hkvm'
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PANEL_PORT='8080'

TMP_DIR=''; REPO_DIR=''; EXTRACT_DIR=''; SOURCE_APP_DIR=''
ZIP_FILE=''; ZIP_SHA256=''; ZIP_SIZE_BYTES='0'
HAS_SYSTEMD='false'; NODE_BIN=''; NPM_BIN=''; MAIN_JS=''
PANEL_STATUS='OFFLINE'; HTTP_STATUS='000'; PUBLIC_IP=''
PROCESS_STATUS='STOPPED'; MODE='UNKNOWN'
RDP_SOURCE_STATUS='NOT_DETECTED'; RDP_INSTALL_STATUS='NOT_DETECTED'
SELECTED_ZIP_NAME=''; RDP_MARKER_FILE=''

line(){ echo -e "${MAGENTA}============================================================${NC}"; }
info(){ echo -e "${CYAN}[VNM PANEL][INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[VNM PANEL][OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[VNM PANEL][WARNING]${NC} $*"; }
error(){ echo -e "${RED}[VNM PANEL][ERROR]${NC} $*"; }
die(){ error "$*"; exit 1; }

cleanup(){
  [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}" || true
}
trap cleanup EXIT

on_error(){
  local rc=$?
  error "Installer failed at line ${BASH_LINENO[0]} (exit ${rc})."
  if [[ -f "${LOG_FILE}" ]]; then
    echo '---------------- VNM PANEL LOG ----------------'
    tail -n 160 "${LOG_FILE}" || true
    echo '-----------------------------------------------'
  fi
  exit "${rc}"
}
trap on_error ERR

clear 2>/dev/null || true

echo -e "${CYAN}"
cat <<'BANNER'

██╗   ██╗███╗   ██╗███╗   ███╗
██║   ██║████╗  ██║████╗ ████║
██║   ██║██╔██╗ ██║██╔████╔██║
╚██╗ ██╔╝██║╚██╗██║██║╚██╔╝██║
 ╚████╔╝ ██║ ╚████║██║ ╚═╝ ██║
  ╚═══╝  ╚═╝  ╚═══╝╚═╝     ╚═╝

                 VNM
           VNM PANEL V3
        FRESH ULTRA INSTALLER V6

BANNER
echo -e "${NC}"
line

# ============================================================
# HELPERS
# ============================================================

has_rdp_code(){
  local root="$1"
  [[ -d "$root" ]] || return 1

  if find "$root" -type f \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      \( -name 'vm-detail.ejs' -o -name 'rdp.js' \) \
      -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  grep -RIsm1 \
    --exclude-dir=node_modules \
    --exclude-dir=.git \
    --include='*.js' --include='*.ejs' --include='*.html' --include='*.json' \
    -E 'tab-rdp|Enable RDP|Install RDP|RDP.*Online|RDP.*Disabled' \
    "$root" >/dev/null 2>&1
}

find_app_root(){
  local root="$1" candidate
  mapfile -t APP_FILES < <(
    find "$root" -type f -name app.js \
      -not -path '*/node_modules/*' -not -path '*/.git/*' \
      -print | sort
  )

  for candidate in "${APP_FILES[@]:-}"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$(dirname "$candidate")/package.json" ]]; then
      dirname "$candidate"; return 0
    fi
  done

  if ((${#APP_FILES[@]} > 0)); then dirname "${APP_FILES[0]}"; return 0; fi
  return 1
}

stop_old_instance(){
  if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi

  if [[ -f "${PID_FILE}" ]]; then
    local old_pid
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
      local cmd cwd
      cmd="$(ps -p "${LPID}" -o args= 2>/dev/null || true)"
      cwd="$(readlink -f "/proc/${LPID}/cwd" 2>/dev/null || true)"
      if [[ "${cwd}" == "${APP_DIR}" ]] || [[ "${cmd}" == *"${APP_DIR}/app.js"* ]]; then
        warn "Stopping old VNM Panel listener PID ${LPID} on port ${PANEL_PORT}."
        kill "${LPID}" >/dev/null 2>&1 || true
        for _ in {1..20}; do
          kill -0 "${LPID}" >/dev/null 2>&1 || break
          sleep 0.2
        done
        kill -9 "${LPID}" >/dev/null 2>&1 || true
      else
        die "Port ${PANEL_PORT} is already used by another process (PID ${LPID})."
      fi
    done
  fi
}

# ============================================================
# ROOT / OS
# ============================================================
[[ ${EUID} -eq 0 ]] || die 'Please run this installer as root.'
[[ -f /etc/os-release ]] || die 'Unable to detect operating system.'
# shellcheck disable=SC1091
source /etc/os-release
info "Operating System : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"
info "Kernel           : $(uname -r)"
[[ "${ID:-}" == 'ubuntu' || "${ID:-}" == 'debian' ]] || die "Unsupported OS: ${ID:-unknown}."

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  HAS_SYSTEMD='true'; ok 'systemd detected — service mode enabled.'
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
apt-get install -y ca-certificates curl git unzip file lsof procps iproute2 openssl build-essential python3

if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
  info 'Installing virtualization dependencies...'
  apt-get install -y qemu-system-x86 qemu-utils ovmf cloud-init libvirt-daemon-system libvirt-clients
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
  if [[ "${NODE_MAJOR}" =~ ^[0-9]+$ ]] && (( NODE_MAJOR >= 20 )); then NODE_OK='true'; fi
fi

if [[ "${NODE_OK}" != 'true' ]]; then
  info 'Installing Node.js 22...'
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

command -v node >/dev/null 2>&1 || die 'Node.js installation failed.'
command -v npm >/dev/null 2>&1 || die 'npm installation failed.'
NODE_BIN="$(readlink -f "$(command -v node)" 2>/dev/null || command -v node)"
NPM_BIN="$(readlink -f "$(command -v npm)" 2>/dev/null || command -v npm)"
[[ -x "${NODE_BIN}" ]] || die "Resolved Node binary is not executable: ${NODE_BIN}"
[[ -x "${NPM_BIN}" ]] || die "Resolved npm binary is not executable: ${NPM_BIN}"
ok "Node.js: $("${NODE_BIN}" -v) | npm: $("${NPM_BIN}" -v)"
info "Node binary: ${NODE_BIN}"
line

# ============================================================
# STORAGE / OLD INSTANCE
# ============================================================
info "Preparing ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}" "${DATA_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" "${CONFIG_DIR}"
chmod 755 "${INSTALL_DIR}" "${DATA_DIR}" "${LOG_DIR}"
chmod 700 "${BACKUP_DIR}" "${CONFIG_DIR}"
touch "${LOG_FILE}"; chmod 640 "${LOG_FILE}"

EXISTING_SESSION_SECRET=''
if [[ -f "${ENV_FILE}" ]]; then
  cp -a "${ENV_FILE}" "${BACKUP_DIR}/hkvm.env.$(date +%Y%m%d-%H%M%S).bak"
  EXISTING_SESSION_SECRET="$({ grep -E '^SESSION_SECRET=' "${ENV_FILE}" || true; } | head -n 1 | cut -d= -f2- | sed 's/^"//; s/"$//')"
  ok 'Existing configuration backed up.'
fi
stop_old_instance
ok 'Old VNM Panel instance stopped.'
line

# ============================================================
# GITHUB -> VERIFY -> SELECT ZIP
# ============================================================
TMP_DIR="$(mktemp -d -t vnm-panel-installer-XXXXXX)"
REPO_DIR="${TMP_DIR}/repo"
EXTRACT_DIR="${TMP_DIR}/extract"
mkdir -p "${EXTRACT_DIR}"

info 'Cloning VNM Panel repository...'
git clone --depth 1 --single-branch "${REPO_URL}" "${REPO_DIR}"
ok 'Repository cloned.'

SELECTED_BUILD_ROOT=''
SELECTED_ZIP_NAME=''

for CANDIDATE in "${ZIP_CANDIDATES[@]}"; do
  CANDIDATE_PATH="${REPO_DIR}/${CANDIDATE}"
  [[ -f "${CANDIDATE_PATH}" ]] || continue

  SIZE_BYTES="$(stat -c '%s' "${CANDIDATE_PATH}" 2>/dev/null || echo 0)"
  (( SIZE_BYTES > 1048576 )) || { warn "Skipping suspiciously small archive: ${CANDIDATE}"; continue; }

  info "Testing archive: ${CANDIDATE} (${SIZE_BYTES} bytes)"
  if ! unzip -tq "${CANDIDATE_PATH}" >/dev/null 2>&1; then
    warn "Archive failed ZIP integrity test: ${CANDIDATE}"
    continue
  fi

  TEST_DIR="${TMP_DIR}/test-${#CANDIDATE}"
  rm -rf "${TEST_DIR}"; mkdir -p "${TEST_DIR}"
  if ! unzip -q "${CANDIDATE_PATH}" -d "${TEST_DIR}"; then
    warn "Could not extract ${CANDIDATE}; skipping."
    rm -rf "${TEST_DIR}"; continue
  fi

  if [[ -z "${SELECTED_BUILD_ROOT}" ]] && has_rdp_code "${TEST_DIR}"; then
    SELECTED_BUILD_ROOT="${TEST_DIR}"
    SELECTED_ZIP_NAME="${CANDIDATE}"
    ZIP_FILE="${CANDIDATE_PATH}"
    info "RDP-enabled build detected in ${CANDIDATE}."
    break
  fi
done

if [[ -z "${ZIP_FILE}" ]]; then
  for CANDIDATE in "${ZIP_CANDIDATES[@]}"; do
    CANDIDATE_PATH="${REPO_DIR}/${CANDIDATE}"
    [[ -f "${CANDIDATE_PATH}" ]] || continue
    if unzip -tq "${CANDIDATE_PATH}" >/dev/null 2>&1; then
      ZIP_FILE="${CANDIDATE_PATH}"
      SELECTED_ZIP_NAME="${CANDIDATE}"
      break
    fi
  done
fi

[[ -n "${ZIP_FILE}" && -f "${ZIP_FILE}" ]] || die 'No valid VNM Panel ZIP archive was found in the repository.'

ZIP_SIZE_BYTES="$(stat -c '%s' "${ZIP_FILE}")"
ZIP_SHA256="$(sha256sum "${ZIP_FILE}" | awk '{print $1}')"
info "Selected ZIP : ${SELECTED_ZIP_NAME}"
info "ZIP size     : ${ZIP_SIZE_BYTES} bytes"
info "ZIP SHA-256  : ${ZIP_SHA256}"

rm -rf "${EXTRACT_DIR}"; mkdir -p "${EXTRACT_DIR}"
info 'Extracting selected application...'
unzip -q "${ZIP_FILE}" -d "${EXTRACT_DIR}"
ok 'ZIP extracted.'

if has_rdp_code "${EXTRACT_DIR}"; then
  RDP_SOURCE_STATUS='DETECTED'; ok 'RDP code detected in selected ZIP.'
else
  RDP_SOURCE_STATUS='NOT_DETECTED'; warn 'RDP code was not detected in selected ZIP.'
fi
line

# ============================================================
# APPLICATION ROOT
# ============================================================
info 'Detecting real VNM Panel application root...'
SOURCE_APP_DIR="$(find_app_root "${EXTRACT_DIR}" || true)"
[[ -n "${SOURCE_APP_DIR}" ]] || die 'Unable to locate the real VNM Panel application root.'
[[ "${SOURCE_APP_DIR}" != *'/node_modules/'* ]] || die 'Safety failure: application root is inside node_modules.'
info "Application root: ${SOURCE_APP_DIR}"

rm -rf "${APP_DIR}"; mkdir -p "${APP_DIR}"
cp -a "${SOURCE_APP_DIR}/." "${APP_DIR}/"
[[ -f "${APP_DIR}/app.js" ]] || die 'Expected VNM Panel app.js was not found after extraction.'
[[ -f "${APP_DIR}/package.json" ]] || die 'package.json missing from application.'
ok "Application installed into ${APP_DIR}."
line

# ============================================================
# DEPENDENCIES
# ============================================================
cd "${APP_DIR}"
if [[ -d node_modules ]]; then
  ok 'Bundled node_modules detected — keeping bundled dependencies.'
else
  info 'Bundled node_modules not found — installing production dependencies.'
  if [[ -f package-lock.json ]]; then
    "${NPM_BIN}" ci --omit=dev
  else
    "${NPM_BIN}" install --omit=dev
  fi
fi

[[ -d node_modules ]] || die 'node_modules is missing after dependency installation.'
info 'Rebuilding native modules for this host...'
"${NPM_BIN}" rebuild sqlite3 ssh2 >/dev/null 2>&1 || warn 'Native module rebuild returned non-zero; startup validation will catch runtime failures.'
ok 'Node.js dependencies are ready.'
line

# ============================================================
# DEVELOPMENT LICENSE / CONFIGURATION
# ============================================================
if [[ -z "${EXISTING_SESSION_SECRET}" ]]; then EXISTING_SESSION_SECRET="$(openssl rand -hex 32)"; fi
[[ -n "${EXISTING_SESSION_SECRET}" ]] || die 'Failed to obtain a session secret.'

cat > "${ENV_FILE}" <<ENV_EOF
NODE_ENV=production
PORT=${PANEL_PORT}
PANEL_NAME="VNM Panel"
SESSION_SECRET=${EXISTING_SESSION_SECRET}

LICENSE_MODE=disabled
LICENSE_KEY=

HKVM_INSTALL_DIR=${INSTALL_DIR}
HKVM_APP_DIR=${APP_DIR}
HKVM_DATA_DIR=${DATA_DIR}
HKVM_LOG_DIR=${LOG_DIR}

VNM_DATA_DIR=${DATA_DIR}
ENV_EOF

chmod 600 "${ENV_FILE}"; chown root:root "${ENV_FILE}"
ln -sfn "${ENV_FILE}" "${APP_DIR}/.env"
bash -n "${ENV_FILE}" || die "Generated VNM Panel environment file is invalid: ${ENV_FILE}"
ok 'Configuration created.'
ok 'License is DISABLED — no license key is required.'
line

# ============================================================
# ENTRYPOINT / SYNTAX / RDP VALIDATION
# ============================================================
MAIN_JS="${APP_DIR}/app.js"
info "Panel entrypoint: ${MAIN_JS}"
"${NODE_BIN}" --check "${MAIN_JS}" || die 'Application syntax check failed.'
ok 'Application syntax check passed.'

RDP_MARKER_FILE="$(find "${APP_DIR}" -type f -not -path '*/node_modules/*' \( -name 'vm-detail.ejs' -o -name 'rdp.js' \) -print -quit 2>/dev/null || true)"
if has_rdp_code "${APP_DIR}"; then
  RDP_INSTALL_STATUS='DETECTED'; ok 'RDP feature detected in installed application.'
else
  RDP_INSTALL_STATUS='NOT_DETECTED'; warn 'RDP feature was not detected in installed application.'
fi
line

# ============================================================
# BEST-EFFORT LOGIN / CSRF COMPATIBILITY PATCH
# ============================================================
info 'Checking login/CSRF compatibility...'
cp -a "${MAIN_JS}" "${BACKUP_DIR}/app.js.preinstall.$(date +%Y%m%d-%H%M%S).bak"

python3 - "${MAIN_JS}" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
pattern = re.compile(r'function\s+csrfProtection\s*\(\s*req\s*,\s*res\s*,\s*next\s*\)\s*\{', re.S)
m = pattern.search(s)

if not m:
    print('NO_NAMED_CSRF_FUNCTION')
    raise SystemExit(0)

brace = s.find('{', m.start())
depth = 0
end = None
for i in range(brace, len(s)):
    ch = s[i]
    if ch == '{': depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0:
            end = i + 1
            break

if end is None: raise SystemExit('Could not safely parse csrfProtection')

new = '''function csrfProtection(req, res, next) {
  const mutating = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method);

  const requestPath = (
    req.originalUrl || req.url || req.path || '/'
  ).split('?')[0].replace(/\\/+$/, '') || '/';

  const isLogin = requestPath === '/login' || requestPath === '/api/login';

  if (!mutating || isLogin || requestPath.startsWith('/api/auth/')) {
    return next();
  }

  const headerToken = req.get('x-csrf-token');
  if (!headerToken || headerToken !== req.session.csrfToken) {
    console.warn(
      `[CSRF] Rejected ${req.method} ${requestPath} (bad/missing token) from ${req.ip}`
    );
    return res.status(403).json({ error: 'Invalid or missing CSRF token' });
  }

  next();
}'''

p.write_text(s[:m.start()] + new + s[end:], encoding='utf-8')
print('PATCHED_CSRF_FUNCTION')
PY

"${NODE_BIN}" --check "${MAIN_JS}" || die 'Application syntax check failed after login compatibility patch.'
ok 'Login compatibility check completed.'
line

# ============================================================
# BUILD INFORMATION
# ============================================================
cat > "${BUILD_INFO_FILE}" <<BUILD_EOF
VNM_INSTALLER_VERSION=V6
INSTALL_TIMESTAMP=$(date -Is)
REPOSITORY=${REPO_URL}
ZIP_NAME=${SELECTED_ZIP_NAME}
ZIP_SIZE_BYTES=${ZIP_SIZE_BYTES}
ZIP_SHA256=${ZIP_SHA256}
RDP_IN_SOURCE=${RDP_SOURCE_STATUS}
RDP_IN_INSTALL=${RDP_INSTALL_STATUS}
RDP_MARKER_FILE=${RDP_MARKER_FILE:-NONE}
APP_DIR=${APP_DIR}
PANEL_PORT=${PANEL_PORT}
BUILD_EOF
chmod 640 "${BUILD_INFO_FILE}"
ok "Build information saved to ${BUILD_INFO_FILE}."
line

# ============================================================
# FIREWALL
# ============================================================
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# ============================================================
# SYSTEMD / STANDALONE
# ============================================================
if [[ "${HAS_SYSTEMD}" == 'true' ]]; then
  info 'Creating systemd service...'
  cat > "${SERVICE_FILE}" <<SERVICE_EOF
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
SERVICE_EOF

  chmod 644 "${SERVICE_FILE}"
  systemd-analyze verify "${SERVICE_FILE}" || die 'systemd service validation failed.'
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
  : > "${LOG_FILE}"
  systemctl restart "${SERVICE_NAME}"
  sleep 5

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok 'VNM Panel service is ONLINE.'
    PROCESS_STATUS='RUNNING'; MODE='SYSTEMD'
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
  nohup "${NODE_BIN}" "${MAIN_JS}" >>"${LOG_FILE}" 2>&1 &
  VNM_PANEL_PID=$!
  echo "${VNM_PANEL_PID}" > "${PID_FILE}"
  sleep 5

  if kill -0 "${VNM_PANEL_PID}" >/dev/null 2>&1; then
    ok "VNM Panel process is running (PID ${VNM_PANEL_PID})."
    PROCESS_STATUS='RUNNING'; MODE='STANDALONE'
  else
    error 'VNM Panel process exited during startup.'
    echo '---------------- VNM PANEL STARTUP LOG ----------------'
    tail -n 240 "${LOG_FILE}" || true
    echo '--------------------------------------------------------'
    exit 1
  fi
fi
line

# ============================================================
# HEALTH CHECKS
# ============================================================
info "Checking panel port ${PANEL_PORT}..."
PANEL_STATUS='OFFLINE'
for _ in {1..20}; do
  if ss -ltn 2>/dev/null | grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then
    PANEL_STATUS='ONLINE'; break
  fi
  sleep 1
done

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then ok "Port ${PANEL_PORT} is listening."; else warn "Port ${PANEL_PORT} is not listening."; fi

HTTP_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:${PANEL_PORT}/" 2>/dev/null || true)"
if [[ "${HTTP_STATUS}" =~ ^[0-9]{3}$ ]] && [[ "${HTTP_STATUS}" != '000' ]]; then
  ok "HTTP health check returned ${HTTP_STATUS}."
else
  warn 'HTTP health check did not return a response.'
fi

# ============================================================
# PUBLIC IP — FIXED SYNTAX
# ============================================================
PUBLIC_IP="$(
  curl \
    -4 \
    -fsS \
    --max-time 10 \
    'https://api.ipify.org' \
    2>/dev/null || true
)"

if [[ -z "${PUBLIC_IP}" ]]; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
[[ -n "${PUBLIC_IP}" ]] || PUBLIC_IP='YOUR_SERVER_IP'

# ============================================================
# FINAL SCREEN
# ============================================================
clear 2>/dev/null || true
echo -e "${GREEN}"
cat <<FINAL_EOF

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                         VNM                                ║
║                    VNM PANEL V3                            ║
║                  INSTALLATION COMPLETE                    ║
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

  SERVICE COMMANDS

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

  ZIP SOURCE

    ${SELECTED_ZIP_NAME}

  ZIP SHA-256

    ${ZIP_SHA256}

  RDP SOURCE

    ${RDP_SOURCE_STATUS}

  RDP INSTALLED

    ${RDP_INSTALL_STATUS}

  LICENSE

    DISABLED — no key is required for this development build.

╚════════════════════════════════════════════════════════════╝

FINAL_EOF
echo -e "${NC}"

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then
  ok "VNM Panel is running on port ${PANEL_PORT}."
else
  warn "VNM Panel installed, but port ${PANEL_PORT} is not listening yet."
  warn "Check: tail -n 240 ${LOG_FILE}"
fi

if [[ "${RDP_INSTALL_STATUS}" == 'DETECTED' ]]; then
  ok 'RDP feature is present in the installed application.'
else
  warn 'RDP feature is NOT present in the installed application.'
  warn "Check: grep -RIl --exclude-dir=node_modules 'tab-rdp' ${APP_DIR}"
fi

line
echo -e "${CYAN}VNM Panel V6 installation finished.${NC}"
