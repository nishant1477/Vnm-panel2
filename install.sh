#!/usr/bin/env bash

# ============================================================
#                    GKVM PANEL
#              ULTRA INSTALLER V2.0
#
# Repository:
#   https://github.com/nishant1477/Vnm-panel2
#
# Package:
#   GKVM-panel.zip
#
# Supported:
#   Ubuntu
#   Debian
#   Normal VPS / systemd
#   GitHub Codespaces
#   Containers without systemd
#
# Features:
#   ✓ Animated terminal installer UI
#   ✓ Progress indicators
#   ✓ Automatic OS detection
#   ✓ Node.js 20+ detection
#   ✓ Automatic dependency installation
#   ✓ Real GKVM app detection
#   ✓ Real GKVM database discovery
#   ✓ Real bcrypt admin password reset
#   ✓ Admin credential verification
#   ✓ SQLite backup
#   ✓ Existing config backup
#   ✓ Systemd support
#   ✓ Standalone/Codespaces support
#   ✓ Automatic port health check
#   ✓ HTTP health check
#   ✓ Firewall handling
#   ✓ GKVM management CLI
#   ✓ Admin password reset command
#   ✓ Log viewer
#   ✓ License disabled for development build
# ============================================================

set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

ESC=$'\033'

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

BLACK="${ESC}[30m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"
MAGENTA="${ESC}[35m"
CYAN="${ESC}[36m"
WHITE="${ESC}[37m"

BRIGHT_RED="${ESC}[91m"
BRIGHT_GREEN="${ESC}[92m"
BRIGHT_YELLOW="${ESC}[93m"
BRIGHT_BLUE="${ESC}[94m"
BRIGHT_MAGENTA="${ESC}[95m"
BRIGHT_CYAN="${ESC}[96m"
BRIGHT_WHITE="${ESC}[97m"

# ============================================================
# GLOBAL CONFIG
# ============================================================

APP_NAME="GKVM Panel"
APP_VERSION="2.0"

REPO_URL="https://github.com/nishant1477/Vnm-panel2.git"
ZIP_NAME="GKVM-panel.zip"

INSTALL_DIR="/opt/gkvm"
APP_DIR="${INSTALL_DIR}/app"
DATA_DIR="${INSTALL_DIR}/data"
LOG_DIR="${INSTALL_DIR}/logs"
BACKUP_DIR="${INSTALL_DIR}/backups"

CONFIG_DIR="/etc/gkvm"
ENV_FILE="${CONFIG_DIR}/gkvm.env"
RUNTIME_FILE="${CONFIG_DIR}/runtime.conf"
CREDENTIAL_FILE="${CONFIG_DIR}/admin-credentials.txt"

LOG_FILE="${LOG_DIR}/gkvm.log"
BOOTSTRAP_LOG="${LOG_DIR}/bootstrap.log"
INSTALLER_LOG="/var/log/gkvm-installer.log"

PID_FILE="${INSTALL_DIR}/gkvm.pid"

SERVICE_NAME="gkvm-panel"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

MANAGER_FILE="/usr/local/bin/gkvm"

PANEL_PORT="8080"

NODE_BIN=""
NPM_BIN=""
MAIN_JS=""

SOURCE_APP_DIR=""
ZIP_FILE=""
TMP_DIR=""

RUNTIME_USER="root"
RUNTIME_GROUP="root"
RUNTIME_HOME="/root"

HAS_SYSTEMD="false"
IS_CODESPACES="false"

DB_PATH=""

ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""

BOOTSTRAP_PID=""

ANIMATION="false"

# ============================================================
# TERMINAL DETECTION
# ============================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    ANIMATION="true"
fi

if [[ "${CODESPACES:-false}" == "true" ]]; then
    IS_CODESPACES="true"
fi

# ============================================================
# LOG FILE SETUP
# ============================================================

mkdir -p "$(dirname "${INSTALLER_LOG}")" 2>/dev/null || true
touch "${INSTALLER_LOG}" 2>/dev/null || true

exec > >(tee -a "${INSTALLER_LOG}") 2>&1

# ============================================================
# UI FUNCTIONS
# ============================================================

terminal_width() {
    local width
    width="$(tput cols 2>/dev/null || echo 68)"

    if [[ ! "${width}" =~ ^[0-9]+$ ]]; then
        width=68
    fi

    (( width > 110 )) && width=110
    (( width < 60 )) && width=60

    echo "${width}"
}

center_text() {
    local text="$1"
    local width="$2"

    local visible="${text//\x1b\[[0-9;]*m/}"
    local len="${#visible}"

    local spaces=$(( (width - len) / 2 ))

    (( spaces < 0 )) && spaces=0

    printf "%${spaces}s%s\n" "" "$text"
}

banner() {

    clear 2>/dev/null || true

    local width
    width="$(terminal_width)"

    echo
    echo -e "${BRIGHT_CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║                    ██████╗ ██╗  ██╗██╗   ██╗                 ║"
    echo "║                   ██╔════╝ ██║ ██╔╝██║   ██║                 ║"
    echo "║                   ██║  ███╗█████╔╝ ██║   ██║                 ║"
    echo "║                   ██║   ██║██╔═██╗ ╚██╗ ██╔╝                 ║"
    echo "║                   ╚██████╔╝██║  ██╗ ╚████╔╝                  ║"
    echo "║                    ╚═════╝ ╚═╝  ╚═╝  ╚═══╝                   ║"
    echo "║                                                              ║"
    echo "║                     GKVM PANEL                               ║"
    echo "║                 ULTRA INSTALLER ${APP_VERSION}                       ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo -e "${DIM}${CYAN}     VM Management • KVM • QEMU • Console • Network • Admin${RESET}"
    echo
}

section() {

    local title="$1"

    echo
    echo -e "${BRIGHT_MAGENTA}${BOLD}┌────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BRIGHT_MAGENTA}${BOLD}│ ${title}${RESET}"
    echo -e "${BRIGHT_MAGENTA}${BOLD}└────────────────────────────────────────────────────────────┘${RESET}"
}

info() {
    echo -e "  ${CYAN}◆${RESET} ${WHITE}$*${RESET}"
}

success() {
    echo -e "  ${BRIGHT_GREEN}✔${RESET} ${BRIGHT_GREEN}$*${RESET}"
}

warning() {
    echo -e "  ${BRIGHT_YELLOW}⚠${RESET} ${BRIGHT_YELLOW}$*${RESET}"
}

error_msg() {
    echo -e "  ${BRIGHT_RED}✖${RESET} ${BRIGHT_RED}$*${RESET}"
}

detail() {
    echo -e "    ${DIM}└─${RESET} $*"
}

die() {
    error_msg "$*"
    exit 1
}

separator() {
    echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
}

# ============================================================
# ANIMATED SPINNER
# ============================================================

run_step() {

    local label="$1"
    shift

    local frames=(
        "⠋"
        "⠙"
        "⠹"
        "⠸"
        "⠼"
        "⠴"
        "⠦"
        "⠧"
        "⠇"
        "⠏"
    )

    local pid
    local i=0
    local rc=0

    if [[ "${ANIMATION}" == "true" ]]; then

        "$@" >>"${INSTALLER_LOG}" 2>&1 &
        pid=$!

        while kill -0 "${pid}" >/dev/null 2>&1; do

            printf "\r  ${BRIGHT_CYAN}%s${RESET} ${WHITE}%-52s${RESET}" \
                "${frames[$((i % ${#frames[@]}))]}" \
                "${label}"

            i=$((i + 1))

            sleep 0.08

        done

        if wait "${pid}"; then
            rc=0
        else
            rc=$?
        fi

        if [[ "${rc}" -eq 0 ]]; then

            printf "\r  ${BRIGHT_GREEN}✔${RESET} ${GREEN}%-60s${RESET}\n" \
                "${label}"

        else

            printf "\r  ${BRIGHT_RED}✖${RESET} ${RED}%-60s${RESET}\n" \
                "${label}"

        fi

    else

        info "${label}..."

        if "$@" >>"${INSTALLER_LOG}" 2>&1; then

            success "${label}"

        else

            rc=$?

            error_msg "${label} failed."

        fi

    fi

    return "${rc}"
}

# ============================================================
# SIMPLE EFFECT
# ============================================================

pulse() {

    [[ "${ANIMATION}" == "true" ]] || return 0

    local text="$1"

    for symbol in "." ".." "..."; do

        printf "\r  ${DIM}${CYAN}%s%s${RESET}" \
            "${text}" \
            "${symbol}"

        sleep 0.12

    done

    printf "\r\033[2K"

}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    if [[ -n "${BOOTSTRAP_PID}" ]] &&
       [[ "${BOOTSTRAP_PID}" =~ ^[0-9]+$ ]]; then

        kill "${BOOTSTRAP_PID}" \
            >/dev/null 2>&1 || true

        wait "${BOOTSTRAP_PID}" \
            >/dev/null 2>&1 || true

    fi

    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}" || true
    fi
}

trap cleanup EXIT

# ============================================================
# ERROR HANDLER
# ============================================================

installer_error() {

    local rc=$?

    echo
    separator

    error_msg "GKVM installer stopped unexpectedly."
    detail "Exit code : ${rc}"
    detail "Installer log : ${INSTALLER_LOG}"

    if [[ -f "${BOOTSTRAP_LOG}" ]]; then

        echo
        echo -e "${BRIGHT_YELLOW}Bootstrap diagnostics:${RESET}"

        tail -n 120 "${BOOTSTRAP_LOG}" || true

    fi

    echo

    exit "${rc}"
}

trap installer_error ERR

# ============================================================
# CHECK ROOT
# ============================================================

[[ "${EUID}" -eq 0 ]] ||
    die "Run this installer as root."

# ============================================================
# BANNER
# ============================================================

banner

# ============================================================
# DETECT OS
# ============================================================

section "SYSTEM DETECTION"

[[ -f /etc/os-release ]] ||
    die "Cannot detect operating system."

source /etc/os-release

info "Operating system : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"
info "Kernel           : $(uname -r)"

if [[ "${ID:-}" != "ubuntu" &&
      "${ID:-}" != "debian" ]]; then

    die "Supported systems: Ubuntu and Debian."

fi

# ============================================================
# DETECT RUNTIME USER
# ============================================================

if [[ -n "${SUDO_USER:-}" &&
      "${SUDO_USER}" != "root" ]]; then

    RUNTIME_USER="${SUDO_USER}"

else

    RUNTIME_USER="root"

fi

RUNTIME_GROUP="$(
    id -gn "${RUNTIME_USER}" 2>/dev/null ||
    echo "${RUNTIME_USER}"
)"

RUNTIME_HOME="$(
    getent passwd "${RUNTIME_USER}" |
    cut -d: -f6
)"

[[ -n "${RUNTIME_HOME}" ]] ||
    RUNTIME_HOME="/root"

info "Runtime user      : ${RUNTIME_USER}"
info "Runtime home      : ${RUNTIME_HOME}"

# ============================================================
# SYSTEMD
# ============================================================

if command -v systemctl >/dev/null 2>&1 &&
   [[ -d /run/systemd/system ]]; then

    HAS_SYSTEMD="true"

    success "systemd available"

else

    HAS_SYSTEMD="false"

    warning "systemd unavailable"
    detail "Standalone process mode will be used."

fi

if [[ "${IS_CODESPACES}" == "true" ]]; then

    warning "GitHub Codespaces detected"
    detail "No systemd VM-host service will be created."

fi

# ============================================================
# HARDWARE
# ============================================================

if [[ -e /dev/kvm ]]; then
    success "/dev/kvm detected"
    detail "KVM acceleration is available."
else
    warning "/dev/kvm not detected"
    detail "GKVM can still install, but local KVM acceleration may be unavailable."
fi

separator

# ============================================================
# PACKAGE INSTALLATION
# ============================================================

section "SYSTEM DEPENDENCIES"

run_step \
    "Updating APT package indexes" \
    apt-get update -y

run_step \
    "Installing base packages" \
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
        python3 \
        sqlite3 \
        util-linux

# ============================================================
# VM PACKAGES
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" &&
      -e /dev/kvm ]]; then

    run_step \
        "Installing QEMU and virtualization packages" \
        apt-get install -y \
            qemu-system-x86 \
            qemu-utils \
            ovmf \
            cloud-init \
            libvirt-daemon-system \
            libvirt-clients

else

    warning "Skipping heavy local VM-host packages for this environment."

fi

# ============================================================
# NODE.JS
# ============================================================

section "NODE.JS RUNTIME"

NODE_OK="false"

if command -v node >/dev/null 2>&1; then

    NODE_VERSION="$(
        node -v |
        sed 's/^v//'
    )"

    NODE_MAJOR="${NODE_VERSION%%.*}"

    if [[ "${NODE_MAJOR}" =~ ^[0-9]+$ ]] &&
       (( NODE_MAJOR >= 20 )); then

        NODE_OK="true"

        NODE_BIN="$(
            readlink -f "$(command -v node)" 2>/dev/null ||
            command -v node
        )"

        NPM_BIN="$(
            readlink -f "$(command -v npm)" 2>/dev/null ||
            command -v npm
        )"

        success "Node.js ${NODE_VERSION} detected"

    else

        warning "Detected Node.js ${NODE_VERSION}, but GKVM requires Node.js 20+."

    fi

fi

if [[ "${NODE_OK}" != "true" ]]; then

    run_step \
        "Configuring NodeSource Node.js 22 repository" \
        bash -c \
        'curl -fsSL https://deb.nodesource.com/setup_22.x | bash -'

    run_step \
        "Installing Node.js 22" \
        apt-get install -y nodejs

fi

NODE_BIN="$(
    readlink -f "$(command -v node)" 2>/dev/null ||
    command -v node
)"

NPM_BIN="$(
    readlink -f "$(command -v npm)" 2>/dev/null ||
    command -v npm
)"

[[ -x "${NODE_BIN}" ]] ||
    die "Node binary is unavailable."

[[ -x "${NPM_BIN}" ]] ||
    die "npm binary is unavailable."

success "Node.js : $("${NODE_BIN}" -v)"
success "npm     : $("${NPM_BIN}" -v)"

separator

# ============================================================
# STORAGE
# ============================================================

section "GKVM STORAGE"

mkdir -p \
    "${INSTALL_DIR}" \
    "${APP_DIR}" \
    "${DATA_DIR}" \
    "${LOG_DIR}" \
    "${BACKUP_DIR}" \
    "${CONFIG_DIR}"

touch "${LOG_FILE}"
touch "${BOOTSTRAP_LOG}"

chmod 755 \
    "${INSTALL_DIR}" \
    "${APP_DIR}" \
    "${DATA_DIR}" \
    "${LOG_DIR}"

chmod 700 \
    "${BACKUP_DIR}" \
    "${CONFIG_DIR}"

chmod 640 \
    "${LOG_FILE}" \
    "${BOOTSTRAP_LOG}"

success "GKVM directories prepared."

# ============================================================
# OLD SERVICE
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    systemctl stop "${SERVICE_NAME}" \
        >/dev/null 2>&1 || true

fi

# ============================================================
# OLD PID
# ============================================================

if [[ -f "${PID_FILE}" ]]; then

    OLD_PID="$(
        cat "${PID_FILE}" 2>/dev/null ||
        true
    )"

    if [[ "${OLD_PID}" =~ ^[0-9]+$ ]]; then

        kill "${OLD_PID}" \
            >/dev/null 2>&1 ||
            true

        for _ in {1..25}; do

            if ! kill -0 "${OLD_PID}" \
                >/dev/null 2>&1; then

                break

            fi

            sleep 0.2

        done

        kill -9 "${OLD_PID}" \
            >/dev/null 2>&1 ||
            true

    fi

    rm -f "${PID_FILE}"

fi

# ============================================================
# OLD PORT
# ============================================================

if command -v lsof >/dev/null 2>&1; then

    mapfile -t PORT_PIDS < <(
        lsof \
            -t \
            -nP \
            -iTCP:"${PANEL_PORT}" \
            -sTCP:LISTEN \
            2>/dev/null ||
            true
    )

    for PID in "${PORT_PIDS[@]:-}"; do

        [[ "${PID}" =~ ^[0-9]+$ ]] ||
            continue

        CMD="$(
            ps -p "${PID}" \
                -o args= \
                2>/dev/null ||
                true
        )"

        CWD="$(
            readlink -f "/proc/${PID}/cwd" \
                2>/dev/null ||
                true
        )"

        if [[ "${CWD}" == "${APP_DIR}" ]] ||
           [[ "${CMD}" == *"${APP_DIR}/app.js"* ]]; then

            warning "Stopping old GKVM process PID ${PID}."

            kill "${PID}" \
                >/dev/null 2>&1 ||
                true

        else

            die \
                "Port ${PANEL_PORT} is already used by another application."

        fi

    done

fi

# ============================================================
# BACKUP EXISTING APP
# ============================================================

if [[ -f "${APP_DIR}/app.js" ]]; then

    BACKUP_APP="${BACKUP_DIR}/app-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "${BACKUP_APP}"

    pulse "Backing up existing GKVM"

    cp -a \
        "${APP_DIR}/." \
        "${BACKUP_APP}/"

    success "Previous application backed up"
    detail "${BACKUP_APP}"

fi

# ============================================================
# BACKUP ENV
# ============================================================

if [[ -f "${ENV_FILE}" ]]; then

    cp -a \
        "${ENV_FILE}" \
        "${BACKUP_DIR}/gkvm.env.$(date +%Y%m%d-%H%M%S).bak"

    success "Existing environment backed up."

fi

separator

# ============================================================
# DOWNLOAD
# ============================================================

section "GKVM PACKAGE"

TMP_DIR="$(
    mktemp -d \
    -t \
    gkvm-installer-XXXXXX
)"

REPO_DIR="${TMP_DIR}/repo"
EXTRACT_DIR="${TMP_DIR}/extract"

mkdir -p "${EXTRACT_DIR}"

run_step \
    "Downloading GKVM repository" \
    git clone \
        --depth 1 \
        --single-branch \
        "${REPO_URL}" \
        "${REPO_DIR}"

ZIP_FILE="${REPO_DIR}/${ZIP_NAME}"

if [[ ! -f "${ZIP_FILE}" ]]; then

    ZIP_FILE="$(
        find "${REPO_DIR}" \
            -type f \
            -name "${ZIP_NAME}" \
            -not -path "*/.git/*" \
            -print \
            -quit \
            2>/dev/null ||
            true
    )"

fi

[[ -n "${ZIP_FILE}" &&
   -f "${ZIP_FILE}" ]] ||
    die "${ZIP_NAME} was not found."

ZIP_SIZE="$(du -h "${ZIP_FILE}" | awk '{print $1}')"

success "GKVM package found"
detail "Size: ${ZIP_SIZE}"

run_step \
    "Validating GKVM archive" \
    unzip -t "${ZIP_FILE}"

run_step \
    "Extracting GKVM archive" \
    unzip -q \
        "${ZIP_FILE}" \
        -d "${EXTRACT_DIR}"

separator

# ============================================================
# APP DETECTION
# ============================================================

section "APPLICATION DETECTION"

mapfile -t APP_FILES < <(
    find "${EXTRACT_DIR}" \
        -type f \
        -name "app.js" \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -print |
    sort
)

SOURCE_APP_DIR=""

if [[ "${#APP_FILES[@]}" -gt 0 ]]; then

    for FILE in "${APP_FILES[@]}"; do

        DIR="$(dirname "${FILE}")"

        if [[ -f "${DIR}/package.json" ]]; then

            SOURCE_APP_DIR="${DIR}"
            break

        fi

    done

fi

if [[ -z "${SOURCE_APP_DIR}" &&
      "${#APP_FILES[@]}" -gt 0 ]]; then

    SOURCE_APP_DIR="$(
        dirname "${APP_FILES[0]}"
    )"

fi

[[ -n "${SOURCE_APP_DIR}" ]] ||
    die "Could not locate GKVM app.js."

if [[ "${SOURCE_APP_DIR}" == *"/node_modules/"* ]]; then
    die "Safety check failed: app root is inside node_modules."
fi

info "Detected application:"
detail "${SOURCE_APP_DIR}"

# ============================================================
# INSTALL APP
# ============================================================

rm -rf "${APP_DIR}"

mkdir -p "${APP_DIR}"

cp -a \
    "${SOURCE_APP_DIR}/." \
    "${APP_DIR}/"

MAIN_JS="${APP_DIR}/app.js"

[[ -f "${MAIN_JS}" ]] ||
    die "GKVM app.js missing after installation."

success "GKVM application installed."

# ============================================================
# RUNTIME OWNERSHIP
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    chown -R root:root \
        "${INSTALL_DIR}"

else

    chown -R \
        "${RUNTIME_USER}:${RUNTIME_GROUP}" \
        "${INSTALL_DIR}"

fi

mkdir -p "${APP_DIR}/data"

# ============================================================
# NODE DEPENDENCIES
# ============================================================

section "NODE DEPENDENCIES"

cd "${APP_DIR}"

[[ -f package.json ]] ||
    die "GKVM package.json missing."

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    DEP_USER="root"

else

    DEP_USER="${RUNTIME_USER}"

fi

if [[ -f package-lock.json ]]; then

    if [[ "${DEP_USER}" == "root" ]]; then

        run_step \
            "Installing locked npm dependencies" \
            "${NPM_BIN}" ci --omit=dev ||
        run_step \
            "Installing npm dependencies using fallback" \
            "${NPM_BIN}" install --omit=dev

    else

        run_step \
            "Installing locked npm dependencies" \
            runuser -u "${DEP_USER}" \
                -- "${NPM_BIN}" ci --omit=dev ||
        run_step \
            "Installing npm dependencies using fallback" \
            runuser -u "${DEP_USER}" \
                -- "${NPM_BIN}" install --omit=dev

    fi

else

    if [[ "${DEP_USER}" == "root" ]]; then

        run_step \
            "Installing npm dependencies" \
            "${NPM_BIN}" install --omit=dev

    else

        run_step \
            "Installing npm dependencies" \
            runuser -u "${DEP_USER}" \
                -- "${NPM_BIN}" install --omit=dev

    fi

fi

if [[ "${DEP_USER}" == "root" ]]; then

    run_step \
        "Rebuilding native modules" \
        "${NPM_BIN}" rebuild sqlite3 ssh2

else

    run_step \
        "Rebuilding native modules" \
        runuser -u "${DEP_USER}" \
            -- "${NPM_BIN}" rebuild sqlite3 ssh2

fi

success "GKVM dependencies installed."

separator

# ============================================================
# SESSION CONFIG
# ============================================================

section "GKVM CONFIGURATION"

SESSION_SECRET="$(
    openssl rand -hex 32
)"

[[ -n "${SESSION_SECRET}" ]] ||
    die "Could not generate session secret."

cat > "${ENV_FILE}" <<EOF
NODE_ENV=production

HOST=0.0.0.0
PORT=${PANEL_PORT}

PANEL_NAME="GKVM Panel"

SESSION_SECRET=${SESSION_SECRET}

LICENSE_MODE=disabled
LICENSE_KEY=

GKVM_INSTALL_DIR=${INSTALL_DIR}
GKVM_APP_DIR=${APP_DIR}
GKVM_DATA_DIR=${DATA_DIR}
GKVM_LOG_DIR=${LOG_DIR}
EOF

chmod 600 "${ENV_FILE}"

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    chown root:root "${ENV_FILE}"

    ln -sfn \
        "${ENV_FILE}" \
        "${APP_DIR}/.env"

else

    STANDALONE_ENV="${INSTALL_DIR}/gkvm.env"

    cp -f \
        "${ENV_FILE}" \
        "${STANDALONE_ENV}"

    chown \
        "${RUNTIME_USER}:${RUNTIME_GROUP}" \
        "${STANDALONE_ENV}"

    chmod 600 "${STANDALONE_ENV}"

    rm -f "${APP_DIR}/.env"

    ln -sfn \
        "${STANDALONE_ENV}" \
        "${APP_DIR}/.env"

fi

success "Environment generated."

# ============================================================
# SYNTAX CHECK
# ============================================================

run_step \
    "Checking GKVM JavaScript syntax" \
    "${NODE_BIN}" \
        --check \
        "${MAIN_JS}"

success "Application syntax is valid."

separator

# ============================================================
# OPTIONAL CSRF COMPATIBILITY
# ============================================================

section "AUTHENTICATION COMPATIBILITY"

cp -a \
    "${MAIN_JS}" \
    "${BACKUP_DIR}/app.js.preinstall.$(date +%Y%m%d-%H%M%S).bak"

python3 - "${MAIN_JS}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

pattern = re.compile(
    r"function\s+csrfProtection\s*"
    r"\(\s*req\s*,\s*res\s*,\s*next\s*\)\s*\{",
    re.S
)

match = pattern.search(text)

if not match:
    print("NO_CSRF_FUNCTION")
    raise SystemExit(0)

brace_start = text.find(
    "{",
    match.start()
)

depth = 0
end = None

for index in range(
    brace_start,
    len(text)
):

    char = text[index]

    if char == "{":
        depth += 1

    elif char == "}":

        depth -= 1

        if depth == 0:
            end = index + 1
            break

if end is None:
    raise SystemExit(
        "Could not safely parse csrfProtection."
    )

replacement = r'''function csrfProtection(req, res, next) {
  const mutating = [
    'POST',
    'PUT',
    'PATCH',
    'DELETE'
  ].includes(req.method);

  const requestPath =
    (req.originalUrl ||
     req.url ||
     req.path ||
     '/')
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

  const headerToken =
    req.get('x-csrf-token');

  if (
    !headerToken ||
    headerToken !== req.session.csrfToken
  ) {
    console.warn(
      `[CSRF] Rejected ${req.method} ${requestPath} from ${req.ip}`
    );

    return res.status(403).json({
      error:
        'Invalid or missing CSRF token'
    });
  }

  next();
}'''

text = (
    text[:match.start()]
    + replacement
    + text[end:]
)

path.write_text(
    text,
    encoding="utf-8"
)

print("CSRF_PATCHED")
PY

run_step \
    "Validating application after auth compatibility check" \
    "${NODE_BIN}" \
        --check \
        "${MAIN_JS}"

success "Authentication compatibility check completed."

separator

# ============================================================
# FIREWALL
# ============================================================

section "NETWORK ACCESS"

if command -v ufw >/dev/null 2>&1; then

    ufw allow "${PANEL_PORT}/tcp" \
        >/dev/null 2>&1 ||
        true

    success "UFW rule configured for port ${PANEL_PORT}."

elif command -v firewall-cmd >/dev/null 2>&1; then

    firewall-cmd \
        --permanent \
        --add-port="${PANEL_PORT}/tcp" \
        >/dev/null 2>&1 ||
        true

    firewall-cmd \
        --reload \
        >/dev/null 2>&1 ||
        true

    success "firewalld rule configured."

else

    warning "No UFW/firewalld detected."
    detail "Make sure TCP ${PANEL_PORT} is reachable through your VPS firewall."

fi

separator

# ============================================================
# RUNTIME HELPERS
# ============================================================

run_as_runtime() {

    if [[ "${RUNTIME_USER}" == "root" ]]; then

        env \
            HOME="${RUNTIME_HOME}" \
            PATH="${PATH}" \
            "$@"

    else

        runuser \
            -u "${RUNTIME_USER}" \
            -- \
            env \
            HOME="${RUNTIME_HOME}" \
            PATH="${PATH}" \
            "$@"

    fi
}

# ============================================================
# DATABASE BOOTSTRAP
# ============================================================

section "DATABASE INITIALIZATION"

rm -f "${BOOTSTRAP_LOG}"

touch "${BOOTSTRAP_LOG}"

chmod 640 "${BOOTSTRAP_LOG}"

info "Starting GKVM temporarily to discover its real database..."

export BOOTSTRAP_NODE="${NODE_BIN}"

if [[ "${RUNTIME_USER}" == "root" ]]; then

    (
        export HOME="${RUNTIME_HOME}"
        export NODE_ENV="production"
        export HOST="0.0.0.0"
        export PORT="${PANEL_PORT}"
        export PANEL_NAME="GKVM Panel"
        export SESSION_SECRET="${SESSION_SECRET}"
        export LICENSE_MODE="disabled"
        export LICENSE_KEY=""
        export GKVM_INSTALL_DIR="${INSTALL_DIR}"
        export GKVM_APP_DIR="${APP_DIR}"
        export GKVM_DATA_DIR="${DATA_DIR}"
        export GKVM_LOG_DIR="${LOG_DIR}"

        exec "${NODE_BIN}" "${MAIN_JS}"

    ) >>"${BOOTSTRAP_LOG}" 2>&1 &

    BOOTSTRAP_PID=$!

else

    runuser \
        -u "${RUNTIME_USER}" \
        -- \
        env \
        HOME="${RUNTIME_HOME}" \
        NODE_ENV="production" \
        HOST="0.0.0.0" \
        PORT="${PANEL_PORT}" \
        PANEL_NAME="GKVM Panel" \
        SESSION_SECRET="${SESSION_SECRET}" \
        LICENSE_MODE="disabled" \
        LICENSE_KEY="" \
        GKVM_INSTALL_DIR="${INSTALL_DIR}" \
        GKVM_APP_DIR="${APP_DIR}" \
        GKVM_DATA_DIR="${DATA_DIR}" \
        GKVM_LOG_DIR="${LOG_DIR}" \
        "${NODE_BIN}" \
        "${MAIN_JS}" \
        >>"${BOOTSTRAP_LOG}" 2>&1 &

    BOOTSTRAP_PID=$!

fi

echo "${BOOTSTRAP_PID}" > "${PID_FILE}"

success "Temporary GKVM process started."
detail "PID: ${BOOTSTRAP_PID}"

# ============================================================
# DATABASE PATH DETECTION
# ============================================================

DB_READY="false"

for _ in {1..60}; do

    DB_PATH="$(
        sed -n \
            's/.*Database:[[:space:]]*\(.*\)$/\1/p' \
            "${BOOTSTRAP_LOG}" |
        tail -n 1 |
        sed 's/[[:space:]]*$//' ||
        true
    )"

    if [[ -n "${DB_PATH}" &&
          -f "${DB_PATH}" ]]; then

        DB_READY="true"
        break

    fi

    if ! kill -0 "${BOOTSTRAP_PID}" \
        >/dev/null 2>&1; then

        break

    fi

    sleep 1

done

# ============================================================
# FALLBACK DATABASE SEARCH
# ============================================================

if [[ "${DB_READY}" != "true" ]]; then

    warning "GKVM did not expose its database path yet."
    info "Searching known GKVM locations..."

    DB_PATH="$(
        find \
            "${RUNTIME_HOME}" \
            "${INSTALL_DIR}" \
            -type f \
            -name "vnm.db" \
            -not -path "*/node_modules/*" \
            -print \
            -quit \
            2>/dev/null ||
            true
    )"

    if [[ -n "${DB_PATH}" &&
          -f "${DB_PATH}" ]]; then

        DB_READY="true"

    fi

fi

# ============================================================
# DATABASE VALIDATION
# ============================================================

if [[ "${DB_READY}" != "true" ]]; then

    echo
    error_msg "Could not locate GKVM's real database."

    echo
    echo -e "${BRIGHT_YELLOW}GKVM bootstrap output:${RESET}"
    tail -n 240 "${BOOTSTRAP_LOG}" || true

    exit 1

fi

success "Real GKVM database found."

detail "${DB_PATH}"

# ============================================================
# VERIFY USERS TABLE
# ============================================================

DB_CHECK="$(
    "${NODE_BIN}" \
        - "${DB_PATH}" \
        <<'NODE'
const sqlite3 = require("sqlite3").verbose();

const db = new sqlite3.Database(
  process.argv[2]
);

db.get(
  `
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name = 'users'
  `,
  (err, row) => {

    db.close();

    if (err || !row) {
      process.exit(1);
    }

    process.stdout.write(
      "USERS_TABLE_OK"
    );
  }
);
NODE
)"

[[ "${DB_CHECK}" == "USERS_TABLE_OK" ]] ||
    die "GKVM users table was not created."

success "GKVM users table verified."

# ============================================================
# STOP BOOTSTRAP
# ============================================================

info "Stopping temporary GKVM instance..."

kill "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 ||
    true

for _ in {1..40}; do

    if ! kill -0 "${BOOTSTRAP_PID}" \
        >/dev/null 2>&1; then

        break

    fi

    sleep 0.25

done

kill -9 "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 ||
    true

wait "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 ||
    true

BOOTSTRAP_PID=""

rm -f "${PID_FILE}"

sleep 1

success "Temporary instance stopped."

separator

# ============================================================
# DATABASE BACKUP
# ============================================================

section "DATABASE SAFETY"

if [[ -f "${DB_PATH}" ]]; then

    DB_BACKUP="${BACKUP_DIR}/$(basename "${DB_PATH}").$(date +%Y%m%d-%H%M%S).bak"

    cp -a \
        "${DB_PATH}" \
        "${DB_BACKUP}"

    success "Database backup created."

    detail "${DB_BACKUP}"

fi

if [[ -f "${DB_PATH}-wal" ]]; then

    cp -a \
        "${DB_PATH}-wal" \
        "${DB_BACKUP}-wal" ||
        true

fi

if [[ -f "${DB_PATH}-shm" ]]; then

    cp -a \
        "${DB_PATH}-shm" \
        "${DB_BACKUP}-shm" ||
        true

fi

separator

# ============================================================
# ADMIN PASSWORD
# ============================================================

section "ADMIN SECURITY"

ADMIN_USERNAME="admin"

ADMIN_PASSWORD="$(
    "${NODE_BIN}" \
        -e '
          const crypto = require("crypto");
          process.stdout.write(
            crypto.randomBytes(18).toString("base64url")
          );
        '
)"

[[ -n "${ADMIN_PASSWORD}" ]] ||
    die "Could not generate admin password."

if (( ${#ADMIN_PASSWORD} < 16 )); then

    ADMIN_PASSWORD="$(
        "${NODE_BIN}" \
            -e '
              const crypto = require("crypto");
              process.stdout.write(
                "GKVM-" +
                crypto.randomBytes(16).toString("hex")
              );
            '
    )"

fi

info "Generated secure admin password."

# ============================================================
# REAL BCRYPT ADMIN UPDATE
# ============================================================

ADMIN_RESULT="$(
    "${NODE_BIN}" \
        - "${DB_PATH}" "${ADMIN_PASSWORD}" \
        <<'NODE'
const sqlite3 = require("sqlite3").verbose();
const bcrypt = require("bcryptjs");

const dbPath = process.argv[2];
const password = process.argv[3];

const hash = bcrypt.hashSync(
  password,
  10
);

const db = new sqlite3.Database(
  dbPath
);

function finish(code) {
  db.close(() => {
    process.exit(code);
  });
}

db.serialize(() => {

  db.get(
    `
      SELECT id
      FROM users
      WHERE username = ?
      LIMIT 1
    `,
    ["admin"],
    (selectErr, user) => {

      if (selectErr) {

        console.error(
          "Admin query failed:",
          selectErr.message
        );

        finish(1);
        return;

      }

      if (!user) {

        db.run(
          `
            INSERT INTO users
            (
              username,
              password,
              email,
              full_name,
              role,
              is_active
            )
            VALUES (?, ?, ?, ?, ?, ?)
          `,
          [
            "admin",
            hash,
            "admin@gkvm.local",
            "GKVM Administrator",
            "admin",
            1
          ],
          (insertErr) => {

            if (insertErr) {

              console.error(
                "Admin creation failed:",
                insertErr.message
              );

              finish(1);
              return;

            }

            console.log(
              "ADMIN_CREATED"
            );

            finish(0);

          }
        );

        return;
      }

      db.all(
        "PRAGMA table_info(users)",
        (pragmaErr, columns) => {

          if (pragmaErr) {

            console.error(
              "Could not inspect users table:",
              pragmaErr.message
            );

            finish(1);
            return;

          }

          const names = new Set(
            columns.map(
              column => column.name
            )
          );

          const updates = [
            "password = ?",
            "role = 'admin'",
            "is_active = 1"
          ];

          const values = [
            hash
          ];

          if (names.has("totp_enabled")) {
            updates.push(
              "totp_enabled = 0"
            );
          }

          if (names.has("totp_secret")) {
            updates.push(
              "totp_secret = NULL"
            );
          }

          if (names.has("totp_recovery_codes")) {
            updates.push(
              "totp_recovery_codes = NULL"
            );
          }

          const sql = `
            UPDATE users
            SET ${updates.join(", ")}
            WHERE username = 'admin'
          `;

          db.run(
            sql,
            values,
            function(updateErr) {

              if (updateErr) {

                console.error(
                  "Admin password update failed:",
                  updateErr.message
                );

                finish(1);
                return;

              }

              if (this.changes !== 1) {

                console.error(
                  "Admin account was not updated."
                );

                finish(1);
                return;

              }

              console.log(
                "ADMIN_UPDATED"
              );

              finish(0);

            }
          );

        }
      );

    }
  );

});
NODE
)"

if [[ "${ADMIN_RESULT}" == "ADMIN_CREATED" ]]; then

    success "Real GKVM admin account created."

else

    success "Real GKVM admin password reset."

fi

# ============================================================
# VERIFY CREDENTIALS
# ============================================================

section "LOGIN VERIFICATION"

LOGIN_TEST="$(
    "${NODE_BIN}" \
        - "${DB_PATH}" "${ADMIN_PASSWORD}" \
        <<'NODE'
const sqlite3 = require("sqlite3").verbose();
const bcrypt = require("bcryptjs");

const db = new sqlite3.Database(
  process.argv[2]
);

const password = process.argv[3];

db.get(
  `
    SELECT username, password, role, is_active
    FROM users
    WHERE username = 'admin'
    LIMIT 1
  `,
  (err, row) => {

    if (err) {

      console.error(
        err.message
      );

      db.close();
      process.exit(1);

    }

    if (!row) {

      console.error(
        "Admin user missing."
      );

      db.close();
      process.exit(1);

    }

    const valid =
      bcrypt.compareSync(
        password,
        row.password
      );

    db.close();

    if (
      valid &&
      row.role === "admin" &&
      Number(row.is_active) === 1
    ) {

      process.stdout.write(
        "LOGIN_VALID"
      );

      process.exit(0);

    }

    process.exit(1);

  }
);
NODE
)"

[[ "${LOGIN_TEST}" == "LOGIN_VALID" ]] ||
    die "Generated GKVM admin credentials failed verification."

success "Admin username/password verified against bcrypt."

# ============================================================
# SAVE CREDENTIALS
# ============================================================

cat > "${CREDENTIAL_FILE}" <<EOF
============================================================
                    GKVM PANEL
                 ADMIN CREDENTIALS
============================================================

Username:
${ADMIN_USERNAME}

Password:
${ADMIN_PASSWORD}

Panel Port:
${PANEL_PORT}

Database:
${DB_PATH}

Generated:
$(date -Is)

============================================================
IMPORTANT
============================================================

This is the REAL GKVM administrator password.

It was bcrypt-hashed and verified directly against
the GKVM users database.

Do not share this file publicly.
============================================================
EOF

chmod 600 "${CREDENTIAL_FILE}"
chown root:root "${CREDENTIAL_FILE}"

success "Verified credentials saved."

separator

# ============================================================
# RUNTIME CONFIG
# ============================================================

section "RUNTIME CONFIGURATION"

cat > "${RUNTIME_FILE}" <<EOF
RUNTIME_USER=$(printf '%q' "${RUNTIME_USER}")
RUNTIME_GROUP=$(printf '%q' "${RUNTIME_GROUP}")
RUNTIME_HOME=$(printf '%q' "${RUNTIME_HOME}")
DB_PATH=$(printf '%q' "${DB_PATH}")
PANEL_PORT=$(printf '%q' "${PANEL_PORT}")
EOF

chmod 640 "${RUNTIME_FILE}"
chown root:root "${RUNTIME_FILE}"

# ============================================================
# SYSTEMD
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    info "Building systemd service..."

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=GKVM Panel - Virtual Machine Management
Documentation=${REPO_URL}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

WorkingDirectory=${APP_DIR}

EnvironmentFile=${ENV_FILE}

ExecStart=${NODE_BIN} ${MAIN_JS}

Restart=always
RestartSec=5

KillSignal=SIGTERM
TimeoutStopSec=30

User=root
Group=root

LimitNOFILE=1048576

StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${SERVICE_FILE}"

    run_step \
        "Validating systemd service" \
        systemd-analyze verify \
            "${SERVICE_FILE}"

    run_step \
        "Reloading systemd" \
        systemctl daemon-reload

    run_step \
        "Enabling GKVM service" \
        systemctl enable "${SERVICE_NAME}"

    : > "${LOG_FILE}"

else

    warning "systemd service skipped."
    detail "GKVM will use standalone process mode."

fi

# ============================================================
# MANAGEMENT CLI
# ============================================================

section "GKVM MANAGEMENT CLI"

cat > "${MANAGER_FILE}" <<'GKVM_MANAGER'
#!/usr/bin/env bash

set -Eeuo pipefail

SERVICE_NAME="gkvm-panel"

INSTALL_DIR="/opt/gkvm"
APP_DIR="${INSTALL_DIR}/app"
LOG_DIR="${INSTALL_DIR}/logs"

LOG_FILE="${LOG_DIR}/gkvm.log"
PID_FILE="${INSTALL_DIR}/gkvm.pid"

CONFIG_DIR="/etc/gkvm"
RUNTIME_FILE="${CONFIG_DIR}/runtime.conf"
CREDENTIAL_FILE="${CONFIG_DIR}/admin-credentials.txt"

MAIN_JS="${APP_DIR}/app.js"

NODE_BIN="$(
    readlink -f "$(command -v node)" 2>/dev/null ||
    command -v node
)"

if [[ -f "${RUNTIME_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNTIME_FILE}"
fi

RUNTIME_USER="${RUNTIME_USER:-root}"
RUNTIME_GROUP="${RUNTIME_GROUP:-root}"
RUNTIME_HOME="${RUNTIME_HOME:-/root}"
DB_PATH="${DB_PATH:-}"

has_systemd() {

    command -v systemctl >/dev/null 2>&1 &&
    [[ -d /run/systemd/system ]]

}

as_runtime() {

    if [[ "${RUNTIME_USER}" == "root" ]]; then

        env \
            HOME="${RUNTIME_HOME}" \
            "$@"

    elif [[ "${EUID}" -eq 0 ]]; then

        runuser \
            -u "${RUNTIME_USER}" \
            -- \
            env \
            HOME="${RUNTIME_HOME}" \
            "$@"

    elif [[ "$(id -un)" == "${RUNTIME_USER}" ]]; then

        env \
            HOME="${RUNTIME_HOME}" \
            "$@"

    else

        echo "Run this command as ${RUNTIME_USER} or with sudo."
        exit 1

    fi

}

standalone_status() {

    if [[ -f "${PID_FILE}" ]]; then

        PID="$(cat "${PID_FILE}" 2>/dev/null || true)"

        if [[ "${PID}" =~ ^[0-9]+$ ]] &&
           kill -0 "${PID}" >/dev/null 2>&1; then

            echo "GKVM: RUNNING"
            echo "PID : ${PID}"

            return 0

        fi

    fi

    echo "GKVM: STOPPED"

}

standalone_start() {

    mkdir -p \
        "${LOG_DIR}" \
        "${APP_DIR}/data"

    if [[ -f "${PID_FILE}" ]]; then

        PID="$(cat "${PID_FILE}" 2>/dev/null || true)"

        if [[ "${PID}" =~ ^[0-9]+$ ]] &&
           kill -0 "${PID}" >/dev/null 2>&1; then

            echo "GKVM is already running."
            echo "PID: ${PID}"

            return 0

        fi

        rm -f "${PID_FILE}"

    fi

    echo "Starting GKVM..."

    if [[ "${RUNTIME_USER}" == "root" ||
          "${EUID}" -eq 0 ]]; then

        as_runtime \
            nohup "${NODE_BIN}" "${MAIN_JS}" \
            >>"${LOG_FILE}" 2>&1 &

        PID=$!

    else

        if [[ "$(id -un)" != "${RUNTIME_USER}" ]]; then

            echo "Use: sudo gkvm start"
            exit 1

        fi

        (
            cd "${APP_DIR}"

            nohup \
                "${NODE_BIN}" \
                "${MAIN_JS}" \
                >>"${LOG_FILE}" 2>&1
        ) &

        PID=$!

    fi

    echo "${PID}" > "${PID_FILE}"

    sleep 3

    if kill -0 "${PID}" >/dev/null 2>&1; then

        echo "GKVM started."
        echo "PID: ${PID}"

    else

        echo "GKVM failed to start."

        tail -n 100 \
            "${LOG_FILE}" ||
            true

        exit 1

    fi

}

standalone_stop() {

    if [[ ! -f "${PID_FILE}" ]]; then

        echo "GKVM is not running."

        return 0

    fi

    PID="$(cat "${PID_FILE}" 2>/dev/null || true)"

    if [[ "${PID}" =~ ^[0-9]+$ ]]; then

        kill "${PID}" \
            >/dev/null 2>&1 ||
            true

    fi

    rm -f "${PID_FILE}"

    echo "GKVM stopped."

}

show_credentials() {

    if [[ "${EUID}" -ne 0 &&
          ! -r "${CREDENTIAL_FILE}" ]]; then

        echo "Credentials are protected."
        echo
        echo "Run:"
        echo
        echo "  sudo gkvm credentials"

        exit 1

    fi

    cat "${CREDENTIAL_FILE}"

}

reset_admin() {

    if [[ "${EUID}" -ne 0 ]]; then

        echo "Admin reset requires root access."
        echo "Running with sudo..."

        exec sudo "$0" reset-admin

    fi

    [[ -n "${DB_PATH}" &&
       -f "${DB_PATH}" ]] ||
        {
            echo "GKVM database not found."
            exit 1
        }

    NEW_PASSWORD="$(
        "${NODE_BIN}" \
            -e '
              const crypto = require("crypto");
              process.stdout.write(
                crypto.randomBytes(18).toString("base64url")
              );
            '
    )"

    "${NODE_BIN}" \
        - "${DB_PATH}" "${NEW_PASSWORD}" \
        <<'NODE'
const sqlite3 = require("sqlite3").verbose();
const bcrypt = require("bcryptjs");

const dbPath = process.argv[2];
const password = process.argv[3];

const hash = bcrypt.hashSync(
  password,
  10
);

const db = new sqlite3.Database(
  dbPath
);

db.all(
  "PRAGMA table_info(users)",
  (pragmaErr, columns) => {

    if (pragmaErr) {
      console.error(pragmaErr.message);
      process.exit(1);
    }

    const names =
      new Set(columns.map(c => c.name));

    const updates = [
      "password = ?",
      "role = 'admin'",
      "is_active = 1"
    ];

    if (names.has("totp_enabled")) {
      updates.push(
        "totp_enabled = 0"
      );
    }

    if (names.has("totp_secret")) {
      updates.push(
        "totp_secret = NULL"
      );
    }

    if (names.has("totp_recovery_codes")) {
      updates.push(
        "totp_recovery_codes = NULL"
      );
    }

    const hashValue = hash;

    db.run(
      `
        UPDATE users
        SET ${updates.join(", ")}
        WHERE username = 'admin'
      `,
      [hashValue],
      function(err) {

        if (err) {
          console.error(err.message);
          process.exit(1);
        }

        if (this.changes !== 1) {
          console.error(
            "Admin account does not exist."
          );
          process.exit(1);
        }

        db.close(() => {
          process.stdout.write(
            password
          );
        });

      }
    );

  }
);
NODE

    # Rewrite credential file.
    cat > "${CREDENTIAL_FILE}" <<EOF
============================================================
                    GKVM PANEL
                 ADMIN CREDENTIALS
============================================================

Username:
admin

Password:
${NEW_PASSWORD}

Database:
${DB_PATH}

Generated:
$(date -Is)

============================================================
EOF

    chmod 600 "${CREDENTIAL_FILE}"

    echo
    echo "============================================================"
    echo "              GKVM ADMIN PASSWORD RESET"
    echo "============================================================"
    echo
    echo "Username : admin"
    echo "Password : ${NEW_PASSWORD}"
    echo
    echo "Credential file:"
    echo "${CREDENTIAL_FILE}"
    echo
    echo "============================================================"

}

health() {

    echo
    echo "GKVM HEALTH"
    echo "-----------"

    if command -v ss >/dev/null 2>&1; then

        if ss -ltn |
            grep -Eq ":${PANEL_PORT:-8080}([[:space:]]|$)"; then

            echo "Port 8080 : ONLINE"

        else

            echo "Port 8080 : OFFLINE"

        fi

    fi

    STATUS="$(
        curl \
            -sS \
            -o /dev/null \
            -w '%{http_code}' \
            --max-time 5 \
            "http://127.0.0.1:${PANEL_PORT:-8080}/" \
            2>/dev/null ||
            true
    )"

    echo "HTTP       : ${STATUS:-NO RESPONSE}"

}

info_screen() {

    echo
    echo "============================================================"
    echo "                       GKVM INFO"
    echo "============================================================"
    echo
    echo "Install directory : ${INSTALL_DIR}"
    echo "Application       : ${APP_DIR}"
    echo "Database          : ${DB_PATH:-unknown}"
    echo "Runtime user      : ${RUNTIME_USER}"
    echo "Runtime home      : ${RUNTIME_HOME}"
    echo "Port              : ${PANEL_PORT:-8080}"
    echo "Credentials       : ${CREDENTIAL_FILE}"
    echo
    echo "============================================================"

}

case "${1:-status}" in

    start)

        if has_systemd; then

            if [[ "${EUID}" -eq 0 ]]; then
                systemctl start "${SERVICE_NAME}"
            else
                sudo systemctl start "${SERVICE_NAME}"
            fi

        else

            standalone_start

        fi

        ;;

    stop)

        if has_systemd; then

            if [[ "${EUID}" -eq 0 ]]; then
                systemctl stop "${SERVICE_NAME}"
            else
                sudo systemctl stop "${SERVICE_NAME}"
            fi

        else

            standalone_stop

        fi

        ;;

    restart)

        if has_systemd; then

            if [[ "${EUID}" -eq 0 ]]; then
                systemctl restart "${SERVICE_NAME}"
            else
                sudo systemctl restart "${SERVICE_NAME}"
            fi

        else

            standalone_stop
            sleep 1
            standalone_start

        fi

        ;;

    status)

        if has_systemd; then

            if [[ "${EUID}" -eq 0 ]]; then
                systemctl status "${SERVICE_NAME}" --no-pager
            else
                sudo systemctl status "${SERVICE_NAME}" --no-pager
            fi

        else

            standalone_status

        fi

        ;;

    logs)

        if has_systemd; then

            if [[ "${EUID}" -eq 0 ]]; then
                journalctl -u "${SERVICE_NAME}" -f
            else
                sudo journalctl -u "${SERVICE_NAME}" -f
            fi

        else

            tail -f "${LOG_FILE}"

        fi

        ;;

    credentials)

        show_credentials

        ;;

    reset-admin)

        reset_admin

        ;;

    health)

        health

        ;;

    info)

        info_screen

        ;;

    *)

        echo
        echo "GKVM MANAGEMENT"
        echo
        echo "  gkvm start"
        echo "  gkvm stop"
        echo "  gkvm restart"
        echo "  gkvm status"
        echo "  gkvm logs"
        echo "  gkvm health"
        echo "  gkvm info"
        echo "  gkvm credentials"
        echo "  sudo gkvm reset-admin"
        echo

        ;;

esac
GKVM_MANAGER

chmod 755 "${MANAGER_FILE}"

success "GKVM management CLI installed."

separator

# ============================================================
# START GKVM
# ============================================================

section "GKVM STARTUP"

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    : > "${LOG_FILE}"

    run_step \
        "Reloading systemd configuration" \
        systemctl daemon-reload

    run_step \
        "Starting GKVM service" \
        systemctl restart "${SERVICE_NAME}"

    sleep 3

    if systemctl is-active --quiet "${SERVICE_NAME}"; then

        success "GKVM systemd service is ONLINE."

    else

        error_msg "GKVM service did not remain online."

        systemctl status \
            "${SERVICE_NAME}" \
            --no-pager \
            --full ||
            true

        echo
        tail -n 160 "${LOG_FILE}" || true

        exit 1

    fi

else

    : > "${LOG_FILE}"

    if [[ "${RUNTIME_USER}" == "root" ]]; then

        (
            export HOME="${RUNTIME_HOME}"
            export NODE_ENV="production"
            export HOST="0.0.0.0"
            export PORT="${PANEL_PORT}"
            export PANEL_NAME="GKVM Panel"
            export LICENSE_MODE="disabled"
            export LICENSE_KEY=""
            export GKVM_INSTALL_DIR="${INSTALL_DIR}"
            export GKVM_APP_DIR="${APP_DIR}"
            export GKVM_DATA_DIR="${DATA_DIR}"
            export GKVM_LOG_DIR="${LOG_DIR}"

            nohup \
                "${NODE_BIN}" \
                "${MAIN_JS}" \
                >>"${LOG_FILE}" 2>&1
        ) &

        GKVM_PID=$!

    else

        runuser \
            -u "${RUNTIME_USER}" \
            -- \
            env \
            HOME="${RUNTIME_HOME}" \
            NODE_ENV="production" \
            HOST="0.0.0.0" \
            PORT="${PANEL_PORT}" \
            PANEL_NAME="GKVM Panel" \
            LICENSE_MODE="disabled" \
            LICENSE_KEY="" \
            GKVM_INSTALL_DIR="${INSTALL_DIR}" \
            GKVM_APP_DIR="${APP_DIR}" \
            GKVM_DATA_DIR="${DATA_DIR}" \
            GKVM_LOG_DIR="${LOG_DIR}" \
            nohup \
            "${NODE_BIN}" \
            "${MAIN_JS}" \
            >>"${LOG_FILE}" 2>&1 &

        GKVM_PID=$!

    fi

    echo "${GKVM_PID}" > "${PID_FILE}"

    sleep 4

    if kill -0 "${GKVM_PID}" >/dev/null 2>&1; then

        success "GKVM standalone process is ONLINE."

        detail "PID: ${GKVM_PID}"

    else

        error_msg "GKVM standalone process stopped unexpectedly."

        tail -n 200 "${LOG_FILE}" || true

        exit 1

    fi

fi

separator

# ============================================================
# PORT HEALTH
# ============================================================

section "HEALTH CHECK"

PANEL_STATUS="OFFLINE"

for _ in {1..30}; do

    if ss -ltn 2>/dev/null |
        grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then

        PANEL_STATUS="ONLINE"
        break

    fi

    sleep 1

done

if [[ "${PANEL_STATUS}" == "ONLINE" ]]; then

    success "TCP port ${PANEL_PORT} is ONLINE."

else

    warning "TCP port ${PANEL_PORT} is not listening."

fi

# ============================================================
# HTTP HEALTH
# ============================================================

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

if [[ "${HTTP_STATUS}" =~ ^[0-9]{3}$ ]] &&
   [[ "${HTTP_STATUS}" != "000" ]]; then

    success "HTTP health check : ${HTTP_STATUS}"

else

    warning "HTTP health check did not return a response."

fi

# ============================================================
# DATABASE FINAL CHECK
# ============================================================

if [[ -f "${DB_PATH}" ]]; then

    success "Database is present."

    detail "${DB_PATH}"

else

    warning "Database file was not found at the recorded path."

fi

# ============================================================
# ACCESS INFORMATION
# ============================================================

PUBLIC_IP=""

if [[ "${IS_CODESPACES}" == "true" ]]; then

    ACCESS_URL="http://localhost:${PANEL_PORT}"
    ACCESS_MODE="CODESPACES PORT FORWARDING"

else

    PUBLIC_IP="$(
        curl \
            -4 \
            -fsS \
            --max-time 8 \
            https://api.ipify.org \
            2>/dev/null ||
            true
    )"

    if [[ -z "${PUBLIC_IP}" ]]; then

        PUBLIC_IP="$(
            hostname -I 2>/dev/null |
            awk '{print $1}' ||
            true
        )"

    fi

    [[ -n "${PUBLIC_IP}" ]] ||
        PUBLIC_IP="YOUR_SERVER_IP"

    ACCESS_URL="http://${PUBLIC_IP}:${PANEL_PORT}"
    ACCESS_MODE="VPS / SERVER"

fi

# ============================================================
# FINAL CREDENTIAL PROTECTION
# ============================================================

chmod 600 "${CREDENTIAL_FILE}"

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    chown root:root "${CREDENTIAL_FILE}"

fi

# ============================================================
# FINAL SCREEN
# ============================================================

clear 2>/dev/null || true

echo
echo -e "${BRIGHT_CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║                   ✦ GKVM PANEL READY ✦                      ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo
echo -e "${BRIGHT_GREEN}${BOLD}  SYSTEM STATUS${RESET}"
separator

printf "  %-24s ${BRIGHT_GREEN}%s${RESET}\n" \
    "Panel" \
    "${PANEL_STATUS}"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Mode" \
    "$([[ "${HAS_SYSTEMD}" == "true" ]] && echo "SYSTEMD" || echo "STANDALONE")"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Port" \
    "${PANEL_PORT}"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "HTTP" \
    "${HTTP_STATUS:-NO RESPONSE}"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Database" \
    "${DB_PATH}"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Runtime user" \
    "${RUNTIME_USER}"

echo
echo -e "${BRIGHT_MAGENTA}${BOLD}  PANEL ACCESS${RESET}"
separator

printf "  %-24s ${BRIGHT_CYAN}%s${RESET}\n" \
    "URL" \
    "${ACCESS_URL}"

printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Access mode" \
    "${ACCESS_MODE}"

echo
echo -e "${BRIGHT_YELLOW}${BOLD}  ADMIN LOGIN${RESET}"
separator

printf "  %-24s ${BRIGHT_WHITE}%s${RESET}\n" \
    "Username" \
    "${ADMIN_USERNAME}"

printf "  %-24s ${BRIGHT_GREEN}${BOLD}%s${RESET}\n" \
    "Password" \
    "${ADMIN_PASSWORD}"

echo
printf "  %-24s ${WHITE}%s${RESET}\n" \
    "Credentials file" \
    "${CREDENTIAL_FILE}"

echo
echo -e "${BRIGHT_BLUE}${BOLD}  MANAGEMENT${RESET}"
separator

echo "    gkvm start"
echo "    gkvm stop"
echo "    gkvm restart"
echo "    gkvm status"
echo "    gkvm logs"
echo "    gkvm health"
echo "    gkvm info"
echo "    sudo gkvm reset-admin"
echo "    sudo gkvm credentials"

echo
echo -e "${BRIGHT_CYAN}${BOLD}  INSTALLATION PATHS${RESET}"
separator

printf "  %-24s %s\n" \
    "Application" \
    "${APP_DIR}"

printf "  %-24s %s\n" \
    "Logs" \
    "${LOG_FILE}"

printf "  %-24s %s\n" \
    "Backups" \
    "${BACKUP_DIR}"

printf "  %-24s %s\n" \
    "Config" \
    "${ENV_FILE}"

echo
echo -e "${DIM}License mode: DISABLED (development build)${RESET}"
echo -e "${DIM}Repository: ${REPO_URL}${RESET}"

echo
echo -e "${BRIGHT_GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    INSTALLATION COMPLETE                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo

if [[ "${IS_CODESPACES}" == "true" ]]; then

    warning "Open port ${PANEL_PORT} from the Codespaces PORTS tab."

    detail "The private 10.x container address is not your public panel URL."

fi

echo
success "GKVM Panel installation finished successfully."
echo
