#!/usr/bin/env bash

# ============================================================
# GKVM PANEL — MAIN ULTRA INSTALLER
#
# Repository:
#   https://github.com/nishant1477/Vnm-panel2
#
# ZIP:
#   GKVM-panel.zip
#
# Supports:
#   - Debian / Ubuntu
#   - Normal VPS with systemd
#   - GitHub Codespaces / containers without systemd
#   - Node.js 20+
#   - Automatic dependency installation
#   - GKVM database initialization
#   - Real bcrypt admin password creation/reset
#   - Secure credentials file
#   - Health checks
#   - Firewall
#   - gkvm management command
#   - License disabled development mode
# ============================================================

set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
MAGENTA='\e[1;35m'
WHITE='\e[1;37m'
NC='\e[0m'

# ============================================================
# GKVM CONFIGURATION
# ============================================================

REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'
ZIP_NAME='GKVM-panel.zip'

INSTALL_DIR='/opt/gkvm'
APP_DIR="${INSTALL_DIR}/app"
DATA_DIR="${INSTALL_DIR}/data"
LOG_DIR="${INSTALL_DIR}/logs"
BACKUP_DIR="${INSTALL_DIR}/backups"

CONFIG_DIR='/etc/gkvm'
ENV_FILE="${CONFIG_DIR}/gkvm.env"
CREDENTIAL_FILE="${CONFIG_DIR}/admin-credentials.txt"

LOG_FILE="${LOG_DIR}/gkvm.log"
BOOTSTRAP_LOG="${LOG_DIR}/bootstrap.log"
PID_FILE="${INSTALL_DIR}/gkvm.pid"

SERVICE_NAME='gkvm-panel'
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

MANAGER_FILE='/usr/local/bin/gkvm'

PANEL_PORT='8080'
PANEL_NAME='GKVM Panel'

ADMIN_USERNAME='admin'
ADMIN_PASSWORD=''

TMP_DIR=''
BOOTSTRAP_PID=''

HAS_SYSTEMD='false'

NODE_BIN=''
NPM_BIN=''
MAIN_JS=''

RUN_USER='root'
RUN_GROUP='root'

# ============================================================
# FUNCTIONS
# ============================================================

line() {
    echo -e "${MAGENTA}============================================================${NC}"
}

info() {
    echo -e "${CYAN}[GKVM][INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[GKVM][OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[GKVM][WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[GKVM][ERROR]${NC} $*"
}

die() {
    error "$*"
    exit 1
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    if [[ -n "${BOOTSTRAP_PID}" ]] &&
       [[ "${BOOTSTRAP_PID}" =~ ^[0-9]+$ ]]; then

        kill "${BOOTSTRAP_PID}" >/dev/null 2>&1 || true
        wait "${BOOTSTRAP_PID}" >/dev/null 2>&1 || true

    fi

    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}" || true
    fi
}

trap cleanup EXIT

# ============================================================
# ERROR HANDLER
# ============================================================

on_error() {

    local rc=$?

    error "Installer failed at line ${BASH_LINENO[0]} (exit ${rc})."

    if [[ -f "${LOG_FILE}" ]]; then

        echo
        echo "---------------- GKVM LOG ----------------"

        tail -n 160 "${LOG_FILE}" || true

        echo "-------------------------------------------"

    fi

    if [[ -f "${BOOTSTRAP_LOG}" ]]; then

        echo
        echo "------------- BOOTSTRAP LOG ---------------"

        tail -n 160 "${BOOTSTRAP_LOG}" || true

        echo "-------------------------------------------"

    fi

    exit "${rc}"
}

trap on_error ERR

# ============================================================
# BANNER
# ============================================================

clear 2>/dev/null || true

echo -e "${CYAN}"

cat <<'EOF'

 ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗
██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║
██║  ███╗█████╔╝ ██║   ██║██╔████╔██║
██║   ██║██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║
╚██████╔╝██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║
 ╚═════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝

             GKVM PANEL
          MAIN ULTRA INSTALLER

EOF

echo -e "${NC}"

line

# ============================================================
# ROOT / OS
# ============================================================

[[ ${EUID} -eq 0 ]] || die "Please run this installer as root."

[[ -f /etc/os-release ]] || die "Unable to detect operating system."

source /etc/os-release

info "Operating System : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"
info "Kernel           : $(uname -r)"

[[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]] \
    || die "Unsupported OS: ${ID:-unknown}. Use Ubuntu or Debian."

# ============================================================
# DETECT INSTALL USER
# ============================================================

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then

    RUN_USER="${SUDO_USER}"

    RUN_GROUP="$(
        id -gn "${SUDO_USER}" 2>/dev/null || echo "${SUDO_USER}"
    )"

else

    RUN_USER="root"
    RUN_GROUP="root"

fi

info "Runtime user     : ${RUN_USER}"
info "Runtime group    : ${RUN_GROUP}"

# ============================================================
# SYSTEMD DETECTION
# ============================================================

if command -v systemctl >/dev/null 2>&1 &&
   [[ -d /run/systemd/system ]]; then

    HAS_SYSTEMD='true'

    ok "systemd detected — service mode enabled."

else

    HAS_SYSTEMD='false'

    warn "systemd not detected — standalone mode enabled."
    info "This is normal in GitHub Codespaces and containers."

fi

line

# ============================================================
# PACKAGES
# ============================================================

export DEBIAN_FRONTEND=noninteractive

info "Updating package lists..."

apt-get update -y

info "Installing base dependencies..."

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

# ============================================================
# VM HOST PACKAGES
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    info "Installing virtualization dependencies..."

    apt-get install -y \
        qemu-system-x86 \
        qemu-utils \
        ovmf \
        cloud-init \
        libvirt-daemon-system \
        libvirt-clients

    ok "Virtualization dependencies installed."

else

    warn "Skipping QEMU/libvirt host packages."
    info "Container/Codespace environment detected."

fi

ok "System dependencies installed."

line

# ============================================================
# NODE.JS
# ============================================================

NODE_OK='false'

if command -v node >/dev/null 2>&1; then

    NODE_VERSION="$(node -v | sed 's/^v//')"
    NODE_MAJOR="${NODE_VERSION%%.*}"

    NODE_BIN="$(command -v node)"
    NODE_BIN="$(
        readlink -f "${NODE_BIN}" 2>/dev/null ||
        echo "${NODE_BIN}"
    )"

    info "Detected Node.js: v${NODE_VERSION}"

    if [[ "${NODE_MAJOR}" =~ ^[0-9]+$ ]] &&
       (( NODE_MAJOR >= 20 )); then

        NODE_OK='true'

    fi

fi

if [[ "${NODE_OK}" != "true" ]]; then

    info "Installing Node.js 22..."

    curl -fsSL \
        https://deb.nodesource.com/setup_22.x |
        bash -

    apt-get install -y nodejs

fi

command -v node >/dev/null 2>&1 \
    || die "Node.js installation failed."

command -v npm >/dev/null 2>&1 \
    || die "npm installation failed."

NODE_BIN="$(
    readlink -f "$(command -v node)" 2>/dev/null ||
    command -v node
)"

NPM_BIN="$(
    readlink -f "$(command -v npm)" 2>/dev/null ||
    command -v npm
)"

[[ -x "${NODE_BIN}" ]] \
    || die "Node binary is not executable: ${NODE_BIN}"

[[ -x "${NPM_BIN}" ]] \
    || die "npm binary is not executable: ${NPM_BIN}"

ok "Node.js: $("${NODE_BIN}" -v)"
ok "npm: $("${NPM_BIN}" -v)"

line

# ============================================================
# STORAGE
# ============================================================

info "Preparing GKVM storage..."

mkdir -p \
    "${INSTALL_DIR}" \
    "${DATA_DIR}" \
    "${LOG_DIR}" \
    "${BACKUP_DIR}" \
    "${CONFIG_DIR}"

chmod 755 \
    "${INSTALL_DIR}" \
    "${DATA_DIR}" \
    "${LOG_DIR}"

chmod 700 \
    "${BACKUP_DIR}" \
    "${CONFIG_DIR}"

touch "${LOG_FILE}"

chmod 640 "${LOG_FILE}"

touch "${BOOTSTRAP_LOG}"

chmod 640 "${BOOTSTRAP_LOG}"

# ============================================================
# BACKUP ENVIRONMENT
# ============================================================

if [[ -f "${ENV_FILE}" ]]; then

    cp -a \
        "${ENV_FILE}" \
        "${BACKUP_DIR}/gkvm.env.$(date +%Y%m%d-%H%M%S).bak"

    ok "Existing GKVM environment backed up."

fi

# ============================================================
# BACKUP DATABASE
# ============================================================

if [[ -f "${DATA_DIR}/vnm.db" ]]; then

    cp -a \
        "${DATA_DIR}/vnm.db" \
        "${BACKUP_DIR}/vnm.db.$(date +%Y%m%d-%H%M%S).bak"

    [[ -f "${DATA_DIR}/vnm.db-wal" ]] &&
        cp -a \
            "${DATA_DIR}/vnm.db-wal" \
            "${BACKUP_DIR}/vnm.db-wal.$(date +%Y%m%d-%H%M%S).bak" ||
        true

    [[ -f "${DATA_DIR}/vnm.db-shm" ]] &&
        cp -a \
            "${DATA_DIR}/vnm.db-shm" \
            "${BACKUP_DIR}/vnm.db-shm.$(date +%Y%m%d-%H%M%S).bak" ||
        true

    ok "Existing GKVM database backed up."

fi

# ============================================================
# STOP OLD SERVICE
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    systemctl stop "${SERVICE_NAME}" \
        >/dev/null 2>&1 || true

fi

# ============================================================
# STOP OLD PID
# ============================================================

if [[ -f "${PID_FILE}" ]]; then

    OLD_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"

    if [[ "${OLD_PID}" =~ ^[0-9]+$ ]]; then

        kill "${OLD_PID}" \
            >/dev/null 2>&1 || true

        for _ in {1..20}; do

            kill -0 "${OLD_PID}" \
                >/dev/null 2>&1 || break

            sleep 0.2

        done

        kill -9 "${OLD_PID}" \
            >/dev/null 2>&1 || true

    fi

    rm -f "${PID_FILE}"

fi

# ============================================================
# STOP OLD GKVM LISTENER
# ============================================================

if command -v lsof >/dev/null 2>&1; then

    mapfile -t LISTEN_PIDS < <(
        lsof \
            -t \
            -nP \
            -iTCP:"${PANEL_PORT}" \
            -sTCP:LISTEN \
            2>/dev/null || true
    )

    for LPID in "${LISTEN_PIDS[@]:-}"; do

        [[ "${LPID}" =~ ^[0-9]+$ ]] || continue

        CMD="$(ps -p "${LPID}" -o args= 2>/dev/null || true)"

        CWD="$(
            readlink -f \
                "/proc/${LPID}/cwd" \
                2>/dev/null || true
        )"

        if [[ "${CWD}" == "${APP_DIR}" ]] ||
           [[ "${CMD}" == *"${APP_DIR}/app.js"* ]]; then

            warn "Stopping old GKVM listener PID ${LPID}."

            kill "${LPID}" \
                >/dev/null 2>&1 || true

            for _ in {1..20}; do

                kill -0 "${LPID}" \
                    >/dev/null 2>&1 || break

                sleep 0.2

            done

            kill -9 "${LPID}" \
                >/dev/null 2>&1 || true

        else

            die \
                "Port ${PANEL_PORT} is already used by another process (PID ${LPID})."

        fi

    done

fi

ok "GKVM storage prepared."

line

# ============================================================
# DOWNLOAD REPOSITORY
# ============================================================

TMP_DIR="$(mktemp -d -t gkvm-installer-XXXXXX)"

REPO_DIR="${TMP_DIR}/repo"
EXTRACT_DIR="${TMP_DIR}/extract"

mkdir -p "${EXTRACT_DIR}"

info "Cloning GKVM repository..."

git clone \
    --depth 1 \
    --single-branch \
    "${REPO_URL}" \
    "${REPO_DIR}"

ok "Repository cloned."

# ============================================================
# FIND ZIP
# ============================================================

ZIP_FILE="${REPO_DIR}/${ZIP_NAME}"

if [[ ! -f "${ZIP_FILE}" ]]; then

    ZIP_FILE="$(
        find "${REPO_DIR}" \
            -type f \
            -name "${ZIP_NAME}" \
            -not -path '*/.git/*' \
            -print \
            -quit \
            2>/dev/null || true
    )"

fi

[[ -n "${ZIP_FILE}" && -f "${ZIP_FILE}" ]] \
    || die "${ZIP_NAME} was not found in repository."

ZIP_SIZE_MB="$(
    du -m "${ZIP_FILE}" |
    awk '{print $1}'
)"

info "Found ${ZIP_NAME}: ${ZIP_SIZE_MB} MB"

(( ZIP_SIZE_MB >= 1 )) \
    || die "GKVM ZIP is empty or invalid."

# ============================================================
# EXTRACT ZIP
# ============================================================

info "Extracting GKVM application..."

unzip -q \
    "${ZIP_FILE}" \
    -d "${EXTRACT_DIR}"

ok "GKVM ZIP extracted."

line

# ============================================================
# DETECT APP ROOT
# ============================================================

info "Detecting GKVM application root..."

mapfile -t APP_FILES < <(
    find "${EXTRACT_DIR}" \
        -type f \
        -name app.js \
        -not -path '*/node_modules/*' \
        -not -path '*/.git/*' \
        -print \
        | sort
)

SOURCE_APP_DIR=''

if [[ "${#APP_FILES[@]}" -gt 0 ]]; then

    SOURCE_APP_DIR="$(dirname "${APP_FILES[0]}")"

fi

# Fallback to package.json main
if [[ -z "${SOURCE_APP_DIR}" ]]; then

    mapfile -t PACKAGE_FILES < <(
        find "${EXTRACT_DIR}" \
            -type f \
            -name package.json \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            -print \
            | sort
    )

    for PKG in "${PACKAGE_FILES[@]}"; do

        DIR="$(dirname "${PKG}")"

        if "${NODE_BIN}" -e '
            const p=require(process.argv[1]);
            const m=p.main;

            process.exit(
                typeof m === "string" && m.trim()
                    ? 0
                    : 1
            );
        ' "${PKG}" >/dev/null 2>&1; then

            SOURCE_APP_DIR="${DIR}"

            break

        fi

    done

fi

[[ -n "${SOURCE_APP_DIR}" ]] \
    || die "Unable to locate GKVM application root."

[[ "${SOURCE_APP_DIR}" != *'/node_modules/'* ]] \
    || die "Safety failure: application root is inside node_modules."

info "Application root: ${SOURCE_APP_DIR}"

# ============================================================
# INSTALL APPLICATION
# ============================================================

rm -rf "${APP_DIR}"

mkdir -p "${APP_DIR}"

cp -a \
    "${SOURCE_APP_DIR}/." \
    "${APP_DIR}/"

[[ -f "${APP_DIR}/app.js" ]] \
    || die "GKVM app.js was not found after extraction."

ok "GKVM application installed."

line

# ============================================================
# APP DATA
# ============================================================

mkdir -p "${APP_DIR}/data"

chmod 755 "${APP_DIR}/data"

# Make sure the application can write data.
chmod -R u+rwX,go+rX "${APP_DIR}"

# ============================================================
# NODE DEPENDENCIES
# ============================================================

cd "${APP_DIR}"

[[ -f package.json ]] \
    || die "package.json missing from GKVM application."

info "Installing GKVM dependencies..."

if [[ -f package-lock.json ]]; then

    if ! "${NPM_BIN}" ci --omit=dev; then

        warn "npm ci failed — retrying npm install."

        "${NPM_BIN}" install --omit=dev

    fi

else

    "${NPM_BIN}" install --omit=dev

fi

info "Rebuilding native modules..."

"${NPM_BIN}" rebuild sqlite3 ssh2 \
    >/dev/null 2>&1 \
    || warn "Native module rebuild returned non-zero."

ok "GKVM dependencies installed."

line

# ============================================================
# SESSION SECRET
# ============================================================

SESSION_SECRET="$(openssl rand -hex 32)"

[[ -n "${SESSION_SECRET}" ]] \
    || die "Failed to generate session secret."

# ============================================================
# ENVIRONMENT
# ============================================================

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

chown root:root "${ENV_FILE}"

ln -sfn \
    "${ENV_FILE}" \
    "${APP_DIR}/.env"

bash -n "${ENV_FILE}" \
    || die "Generated GKVM environment file is invalid."

ok "GKVM environment created."

line

# ============================================================
# ENTRYPOINT
# ============================================================

MAIN_JS="${APP_DIR}/app.js"

info "GKVM entrypoint: ${MAIN_JS}"

"${NODE_BIN}" --check "${MAIN_JS}" \
    || die "GKVM application syntax check failed."

ok "GKVM application syntax check passed."

line

# ============================================================
# CSRF COMPATIBILITY PATCH
# ============================================================

info "Checking GKVM login/CSRF compatibility..."

cp -a \
    "${MAIN_JS}" \
    "${BACKUP_DIR}/app.js.preinstall.$(date +%Y%m%d-%H%M%S).bak"

python3 - "${MAIN_JS}" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])

s = p.read_text(encoding="utf-8")

pattern = re.compile(
    r"function\s+csrfProtection\s*"
    r"\(\s*req\s*,\s*res\s*,\s*next\s*\)\s*\{",
    re.S
)

m = pattern.search(s)

if not m:
    print("NO_NAMED_CSRF_FUNCTION")
    raise SystemExit(0)

brace = s.find("{", m.start())

depth = 0
end = None

for i in range(brace, len(s)):

    ch = s[i]

    if ch == "{":
        depth += 1

    elif ch == "}":

        depth -= 1

        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit(
        "Could not safely parse csrfProtection"
    )

new = r'''function csrfProtection(req, res, next) {
  const mutating = ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method);

  const requestPath =
    (req.originalUrl || req.url || req.path || '/')
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
      `[CSRF] Rejected ${req.method} ${requestPath} from ${req.ip}`
    );

    return res.status(403).json({
      error: 'Invalid or missing CSRF token'
    });
  }

  next();
}'''

s = s[:m.start()] + new + s[end:]

p.write_text(
    s,
    encoding="utf-8"
)

print("PATCHED_CSRF_FUNCTION")
PY

"${NODE_BIN}" --check "${MAIN_JS}" \
    || die "GKVM syntax check failed after CSRF patch."

ok "GKVM login compatibility check completed."

line

# ============================================================
# FIREWALL
# ============================================================

if command -v ufw >/dev/null 2>&1; then

    ufw allow "${PANEL_PORT}/tcp" \
        >/dev/null 2>&1 || true

elif command -v firewall-cmd >/dev/null 2>&1; then

    firewall-cmd \
        --permanent \
        --add-port="${PANEL_PORT}/tcp" \
        >/dev/null 2>&1 || true

    firewall-cmd \
        --reload \
        >/dev/null 2>&1 || true

fi

# ============================================================
# TEMPORARY DATABASE BOOTSTRAP
# ============================================================
#
# Important:
# GKVM itself creates:
#
#   users
#   sessions
#   vms
#   settings
#   etc.
#
# And GKVM itself creates the first admin using bcrypt.
#
# We therefore start the real application once, allow it to
# initialize its SQLite database, stop it, then reset the real
# admin password using the same bcryptjs library.
# ============================================================

info "Initializing GKVM database..."

rm -f "${BOOTSTRAP_LOG}"

touch "${BOOTSTRAP_LOG}"

chmod 640 "${BOOTSTRAP_LOG}"

# Existing database gets preserved.
# GKVM will initialize/migrate it automatically.

cd "${APP_DIR}"

# ============================================================
# START BOOTSTRAP
# ============================================================

(
    export NODE_ENV=production
    export HOST=0.0.0.0
    export PORT="${PANEL_PORT}"
    export PANEL_NAME="GKVM Panel"
    export SESSION_SECRET="${SESSION_SECRET}"
    export LICENSE_MODE=disabled
    export LICENSE_KEY=
    export GKVM_INSTALL_DIR="${INSTALL_DIR}"
    export GKVM_APP_DIR="${APP_DIR}"
    export GKVM_DATA_DIR="${DATA_DIR}"
    export GKVM_LOG_DIR="${LOG_DIR}"

    exec "${NODE_BIN}" "${MAIN_JS}"
) >>"${BOOTSTRAP_LOG}" 2>&1 &

BOOTSTRAP_PID=$!

echo "${BOOTSTRAP_PID}" > "${PID_FILE}"

info "Temporary GKVM process started (PID ${BOOTSTRAP_PID})."

DB_PATH="${DATA_DIR}/vnm.db"

DATABASE_READY='false'

for _ in {1..40}; do

    if [[ -f "${DB_PATH}" ]]; then

        if "${NODE_BIN}" - "${DB_PATH}" <<'NODE' >/dev/null 2>&1
const sqlite3 = require("sqlite3").verbose();

const db = new sqlite3.Database(process.argv[2]);

db.get(
  "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
  (err, row) => {
    db.close();

    if (err || !row) {
      process.exit(1);
    }

    process.exit(0);
  }
);
NODE
        then

            DATABASE_READY='true'
            break

        fi

    fi

    if ! kill -0 "${BOOTSTRAP_PID}" >/dev/null 2>&1; then
        break
    fi

    sleep 1

done

if [[ "${DATABASE_READY}" != "true" ]]; then

    # Fallback: search for vnm.db if the application used another
    # custom database directory.

    FOUND_DB="$(
        find "${INSTALL_DIR}" \
            -type f \
            -name "vnm.db" \
            -not -path '*/node_modules/*' \
            -print \
            -quit \
            2>/dev/null || true
    )"

    if [[ -n "${FOUND_DB}" ]]; then

        DB_PATH="${FOUND_DB}"

        if "${NODE_BIN}" - "${DB_PATH}" <<'NODE' >/dev/null 2>&1
const sqlite3 = require("sqlite3").verbose();

const db = new sqlite3.Database(process.argv[2]);

db.get(
  "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
  (err, row) => {
    db.close();

    process.exit(err || !row ? 1 : 0);
  }
);
NODE
        then

            DATABASE_READY='true'

        fi

    fi

fi

if [[ "${DATABASE_READY}" != "true" ]]; then

    error "GKVM database initialization failed."

    echo
    echo "------------- GKVM BOOTSTRAP LOG ---------------"

    tail -n 240 "${BOOTSTRAP_LOG}" || true

    echo "-------------------------------------------------"

    exit 1

fi

ok "GKVM database initialized."
info "Database: ${DB_PATH}"

# ============================================================
# STOP TEMPORARY APP
# ============================================================

info "Stopping temporary GKVM process..."

kill "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 || true

for _ in {1..30}; do

    if ! kill -0 "${BOOTSTRAP_PID}" \
        >/dev/null 2>&1; then

        break

    fi

    sleep 0.2

done

kill -9 "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 || true

wait "${BOOTSTRAP_PID}" \
    >/dev/null 2>&1 || true

BOOTSTRAP_PID=''

rm -f "${PID_FILE}"

# ============================================================
# ADMIN PASSWORD
# ============================================================
#
# IMPORTANT:
# Do NOT use ADMIN_PASSWORD from .env.
#
# We update the actual "users" table with bcryptjs so the
# password works with /api/login.
# ============================================================

info "Creating secure GKVM admin password..."

ADMIN_PASSWORD="$(
    "${NODE_BIN}" -e '
const crypto = require("crypto");
process.stdout.write(
    crypto.randomBytes(18).toString("base64url")
);
'
)"

[[ -n "${ADMIN_PASSWORD}" ]] \
    || die "Failed to generate admin password."

if [[ ${#ADMIN_PASSWORD} -lt 16 ]]; then

    ADMIN_PASSWORD="$(
        "${NODE_BIN}" -e '
const crypto = require("crypto");
process.stdout.write(
    "GKVM-" + crypto.randomBytes(16).toString("hex")
);
'
    )"

fi

# ============================================================
# UPDATE REAL ADMIN DATABASE RECORD
# ============================================================

info "Updating real GKVM admin account..."

"${NODE_BIN}" - "${DB_PATH}" "${ADMIN_PASSWORD}" <<'NODE'
const sqlite3 = require("sqlite3").verbose();
const bcrypt = require("bcryptjs");

const dbPath = process.argv[2];
const password = process.argv[3];

const hash = bcrypt.hashSync(password, 10);

const db = new sqlite3.Database(dbPath);

function finish(code) {
  db.close(() => process.exit(code));
}

db.serialize(() => {

  db.get(
    "SELECT id FROM users WHERE username = ? LIMIT 1",
    ["admin"],
    (selectErr, row) => {

      if (selectErr) {
        console.error(
          "Could not query admin:",
          selectErr.message
        );

        finish(1);
        return;
      }

      if (!row) {

        db.run(
          `INSERT INTO users
           (username, password, email, full_name, role, is_active)
           VALUES (?, ?, ?, ?, ?, ?)`,
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
                "Could not create admin:",
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

      // Reset the existing admin.
      //
      // Also disable 2FA during installation/reset so a newly
      // generated installer credential is usable immediately.

      db.run(
        `UPDATE users
         SET password = ?,
             role = 'admin',
             is_active = 1,
             email = COALESCE(email, 'admin@gkvm.local'),
             full_name = COALESCE(full_name, 'GKVM Administrator'),
             totp_enabled = 0,
             totp_secret = NULL,
             totp_recovery_codes = NULL
         WHERE username = 'admin'`,
        [hash],
        function(updateErr) {

          if (updateErr) {

            // Older databases may not have TOTP columns.
            // Fall back to the compatible update.

            db.run(
              `UPDATE users
               SET password = ?,
                   role = 'admin',
                   is_active = 1,
                   email = COALESCE(email, 'admin@gkvm.local'),
                   full_name = COALESCE(full_name, 'GKVM Administrator')
               WHERE username = 'admin'`,
              [hash],
              function(fallbackErr) {

                if (fallbackErr) {

                  console.error(
                    "Could not update admin:",
                    fallbackErr.message
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

});
NODE

ok "Real GKVM admin account configured."

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

This password belongs to the real GKVM "users" database.

GKVM uses bcrypt for password verification.

Keep this file private.
============================================================
EOF

chmod 600 "${CREDENTIAL_FILE}"

chown root:root "${CREDENTIAL_FILE}"

ok "Admin credentials saved."

line

# ============================================================
# APP PERMISSIONS
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    # systemd runs the panel as root for VM/QEMU operations.

    chown -R root:root \
        "${APP_DIR}" \
        "${DATA_DIR}" \
        "${LOG_DIR}"

else

    # Codespaces/containers:
    # allow the user who invoked sudo to run gkvm start manually.

    if [[ "${RUN_USER}" != "root" ]]; then

        chown -R \
            "${RUN_USER}:${RUN_GROUP}" \
            "${APP_DIR}" \
            "${DATA_DIR}" \
            "${LOG_DIR}"

        # Credentials/config stay protected under /etc/gkvm.

    fi

fi

# Keep application writable.
chmod -R u+rwX,go+rX "${APP_DIR}"

mkdir -p "${APP_DIR}/data"

chmod 755 "${APP_DIR}/data"

line

# ============================================================
# MANAGEMENT COMMAND
# ============================================================

info "Installing gkvm management command..."

cat > "${MANAGER_FILE}" <<'EOF'
#!/usr/bin/env bash

set -u

SERVICE_NAME="gkvm-panel"

INSTALL_DIR="/opt/gkvm"
APP_DIR="${INSTALL_DIR}/app"
LOG_DIR="${INSTALL_DIR}/logs"

LOG_FILE="${LOG_DIR}/gkvm.log"
PID_FILE="${INSTALL_DIR}/gkvm.pid"

CREDENTIAL_FILE="/etc/gkvm/admin-credentials.txt"

NODE_BIN="$(command -v node 2>/dev/null || true)"
MAIN_JS="${APP_DIR}/app.js"

has_systemd() {

    command -v systemctl >/dev/null 2>&1 &&
    [[ -d /run/systemd/system ]]

}

start_standalone() {

    mkdir -p "${LOG_DIR}" "${APP_DIR}/data"

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

    nohup "${NODE_BIN}" "${MAIN_JS}" \
        >>"${LOG_FILE}" 2>&1 &

    PID=$!

    echo "${PID}" > "${PID_FILE}"

    sleep 3

    if kill -0 "${PID}" >/dev/null 2>&1; then

        echo "GKVM started."
        echo "PID: ${PID}"

        return 0

    fi

    echo "GKVM failed to start."

    tail -n 100 "${LOG_FILE}" || true

    return 1

}

stop_standalone() {

    if [[ ! -f "${PID_FILE}" ]]; then

        echo "GKVM is not running."

        return 0

    fi

    PID="$(cat "${PID_FILE}" 2>/dev/null || true)"

    if [[ "${PID}" =~ ^[0-9]+$ ]]; then

        kill "${PID}" \
            >/dev/null 2>&1 || true

    fi

    rm -f "${PID_FILE}"

    echo "GKVM stopped."

}

status_standalone() {

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

case "${1:-status}" in

    start)

        if has_systemd; then
            systemctl start "${SERVICE_NAME}"
        else
            start_standalone
        fi

        ;;

    stop)

        if has_systemd; then
            systemctl stop "${SERVICE_NAME}"
        else
            stop_standalone
        fi

        ;;

    restart)

        if has_systemd; then

            systemctl restart "${SERVICE_NAME}"

        else

            stop_standalone
            sleep 1
            start_standalone

        fi

        ;;

    status)

        if has_systemd then
            systemctl status "${SERVICE_NAME}" --no-pager
        else
            status_standalone
        fi

        ;;

    logs)

        if has_systemd; then
            journalctl -u "${SERVICE_NAME}" -f
        else
            tail -f "${LOG_FILE}"
        fi

        ;;

    credentials)

        if [[ -r "${CREDENTIAL_FILE}" ]]; then

            cat "${CREDENTIAL_FILE}"

        else

            echo "Use:"
            echo "  sudo gkvm credentials"

            exit 1

        fi

        ;;

    *)

        echo
        echo "GKVM Management"
        echo
        echo "Usage:"
        echo "  gkvm start"
        echo "  gkvm stop"
        echo "  gkvm restart"
        echo "  gkvm status"
        echo "  gkvm logs"
        echo "  gkvm credentials"
        echo

        exit 1

        ;;

esac
EOF

# Fix the deliberate shell syntax line safely.
sed -i 's/if has_systemd then/if has_systemd; then/' "${MANAGER_FILE}"

chmod 755 "${MANAGER_FILE}"

ok "GKVM management command installed."

line

# ============================================================
# SYSTEMD SERVICE
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    info "Creating GKVM systemd service..."

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=GKVM Panel
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

    systemd-analyze verify \
        "${SERVICE_FILE}" \
        || die "systemd service validation failed."

    systemctl daemon-reload

    systemctl enable \
        "${SERVICE_NAME}" \
        >/dev/null 2>&1

    : > "${LOG_FILE}"

    info "Starting GKVM service..."

    systemctl restart "${SERVICE_NAME}"

    sleep 5

    if systemctl is-active --quiet "${SERVICE_NAME}"; then

        ok "GKVM service is ONLINE."

    else

        error "GKVM service failed to start."

        systemctl status \
            "${SERVICE_NAME}" \
            --no-pager \
            --full || true

        journalctl \
            -u "${SERVICE_NAME}" \
            -n 200 \
            --no-pager || true

        exit 1

    fi

# ============================================================
# STANDALONE MODE
# ============================================================

else

    info "Starting GKVM in standalone/background mode..."

    : > "${LOG_FILE}"

    if [[ "${RUN_USER}" == "root" ]]; then

        nohup "${NODE_BIN}" "${MAIN_JS}" \
            >>"${LOG_FILE}" 2>&1 &

        GKVM_PID=$!

    else

        # Run as the Codespaces/container user.
        #
        # This prevents EACCES when the user later runs
        # gkvm restart/status.

        su -s /bin/bash "${RUN_USER}" -c \
            "cd '${APP_DIR}' && nohup '${NODE_BIN}' '${MAIN_JS}' >>'${LOG_FILE}' 2>&1 & echo \$!" \
            > "${PID_FILE}"

        GKVM_PID="$(cat "${PID_FILE}")"

        if [[ ! "${GKVM_PID}" =~ ^[0-9]+$ ]]; then

            die "Could not obtain GKVM standalone PID."

        fi

    fi

    echo "${GKVM_PID}" > "${PID_FILE}"

    sleep 5

    if kill -0 "${GKVM_PID}" >/dev/null 2>&1; then

        ok "GKVM process is running (PID ${GKVM_PID})."

    else

        error "GKVM process exited during startup."

        echo
        echo "------------- GKVM STARTUP LOG ---------------"

        tail -n 240 "${LOG_FILE}" || true

        echo "-----------------------------------------------"

        exit 1

    fi

fi

line

# ============================================================
# PORT HEALTH CHECK
# ============================================================

info "Checking GKVM port ${PANEL_PORT}..."

PANEL_STATUS='OFFLINE'

for _ in {1..20}; do

    if ss -ltn 2>/dev/null |
        grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then

        PANEL_STATUS='ONLINE'

        break

    fi

    sleep 1

done

if [[ "${PANEL_STATUS}" == "ONLINE" ]]; then

    ok "Port ${PANEL_PORT} is listening."

else

    warn "Port ${PANEL_PORT} is not listening yet."

fi

# ============================================================
# HTTP HEALTH CHECK
# ============================================================

HTTP_STATUS="$(
    curl \
        -sS \
        -o /dev/null \
        -w '%{http_code}' \
        --max-time 8 \
        "http://127.0.0.1:${PANEL_PORT}/" \
        2>/dev/null || true
)"

if [[ "${HTTP_STATUS}" =~ ^[0-9]{3}$ ]] &&
   [[ "${HTTP_STATUS}" != "000" ]]; then

    ok "HTTP health check returned ${HTTP_STATUS}."

else

    warn "HTTP health check did not return a response."

fi

# ============================================================
# PUBLIC ACCESS
# ============================================================

PUBLIC_IP=''

if [[ "${CODESPACES:-false}" == "true" ]]; then

    ACCESS_URL="http://127.0.0.1:${PANEL_PORT}"
    ACCESS_MODE="GITHUB CODESPACES PORT FORWARDING"

else

    PUBLIC_IP="$(
        curl \
            -4 \
            -fsS \
            --max-time 10 \
            https://api.ipify.org \
            2>/dev/null || true
    )"

    if [[ -z "${PUBLIC_IP}" ]]; then

        PUBLIC_IP="$(
            hostname -I 2>/dev/null |
            awk '{print $1}' ||
            true
        )"

    fi

    [[ -n "${PUBLIC_IP}" ]] \
        || PUBLIC_IP="YOUR_SERVER_IP"

    ACCESS_URL="http://${PUBLIC_IP}:${PANEL_PORT}"
    ACCESS_MODE="VPS / SERVER"

fi

# ============================================================
# FINAL PROCESS STATE
# ============================================================

if [[ "${HAS_SYSTEMD}" == "true" ]]; then

    MODE="SYSTEMD"

else

    MODE="STANDALONE"

fi

# ============================================================
# FINAL SCREEN
# ============================================================

clear 2>/dev/null || true

echo -e "${GREEN}"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                         GKVM PANEL                         ║
║                    INSTALLATION COMPLETE                   ║
╚════════════════════════════════════════════════════════════╝

  STATUS              : ${PANEL_STATUS}
  LICENSE STATUS      : DISABLED
  MODE                : ${MODE}

  PANEL URL           : ${ACCESS_URL}
  ACCESS MODE         : ${ACCESS_MODE}

  INSTALL DIRECTORY   : ${INSTALL_DIR}
  APPLICATION         : ${APP_DIR}
  ENTRYPOINT          : ${MAIN_JS}
  DATA DIRECTORY      : ${DATA_DIR}
  DATABASE            : ${DB_PATH}

  CONFIGURATION       : ${ENV_FILE}
  CREDENTIALS         : ${CREDENTIAL_FILE}
  LOG FILE            : ${LOG_FILE}

  SERVICE             : ${SERVICE_NAME}

──────────────────────────────────────────────────────────────

  GKVM ADMIN LOGIN

    Username          : ${ADMIN_USERNAME}
    Password          : ${ADMIN_PASSWORD}

──────────────────────────────────────────────────────────────

  MANAGEMENT COMMANDS

    gkvm start
    gkvm stop
    gkvm restart
    gkvm status
    gkvm logs
    sudo gkvm credentials

──────────────────────────────────────────────────────────────

  VPS SYSTEMD COMMANDS

    systemctl start ${SERVICE_NAME}
    systemctl stop ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}
    systemctl status ${SERVICE_NAME}
    journalctl -u ${SERVICE_NAME} -f

──────────────────────────────────────────────────────────────

  CODESPACES

    Open port ${PANEL_PORT}
    from the Codespaces PORTS tab.

──────────────────────────────────────────────────────────────

  SOURCE REPOSITORY

    ${REPO_URL}

  ZIP SOURCE

    ${ZIP_NAME}

╚════════════════════════════════════════════════════════════╝

EOF

echo -e "${NC}"

# ============================================================
# FINAL STATUS
# ============================================================

if [[ "${PANEL_STATUS}" == "ONLINE" ]]; then

    ok "GKVM Panel is running on port ${PANEL_PORT}."

else

    warn "GKVM installed, but port ${PANEL_PORT} is not listening."

    echo
    echo "Check logs with:"
    echo
    echo "  gkvm logs"
    echo

fi

echo
echo "Admin credentials were written to:"
echo
echo "  ${CREDENTIAL_FILE}"
echo

line

echo -e "${CYAN}GKVM Panel installation finished.${NC}"

echo
