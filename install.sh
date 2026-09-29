#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# VNM PANEL — STABLE INSTALLER ENTRYPOINT
#
# Repository:
#   https://github.com/nishant1477/Vnm-panel2
#
# Core installer:
#   https://raw.githubusercontent.com/nishant1477/Vnm-panel2/main/install-v5.sh
#
# This wrapper runs the repository's install-v5.sh and then:
#   - forces VNM_DATA_DIR=/opt/hkvm/data
#   - restarts the panel with the corrected environment
#   - creates/verifies the admin account
#   - saves credentials to /opt/hkvm/admin-credentials.txt
#
# No branding replacements are performed.
# ============================================================

set -Eeuo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

readonly CORE_URL='https://raw.githubusercontent.com/nishant1477/Vnm-panel2/main/install-v5.sh'
readonly INSTALL_DIR='/opt/hkvm'
readonly APP_DIR='/opt/hkvm/app'
readonly DATA_DIR='/opt/hkvm/data'
readonly LOG_DIR='/opt/hkvm/logs'
readonly BACKUP_DIR='/opt/hkvm/backups'
readonly CONFIG_DIR='/etc/hkvm'
readonly ENV_FILE='/etc/hkvm/hkvm.env'
readonly LOG_FILE='/opt/hkvm/logs/hkvm.log'
readonly PID_FILE='/opt/hkvm/hkvm.pid'
readonly CREDENTIAL_FILE='/opt/hkvm/admin-credentials.txt'
readonly SERVICE_NAME='hkvm'
readonly SERVICE_FILE='/etc/systemd/system/hkvm.service'
readonly PANEL_PORT='8080'
readonly TMP_DIR="/tmp/vnm-panel-install-$$"
readonly CORE_TMP="${TMP_DIR}/install-v5.sh"

info() {
    printf '%b\n' "${CYAN}[VNM PANEL][INFO]${NC} $*"
}

ok() {
    printf '%b\n' "${GREEN}[VNM PANEL][OK]${NC} $*"
}

warn() {
    printf '%b\n' "${YELLOW}[VNM PANEL][WARNING]${NC} $*"
}

die() {
    printf '%b\n' "${RED}[VNM PANEL][ERROR]${NC} %s\n" "$*" >&2
    exit 1
}

cleanup() {
    rm -rf "${TMP_DIR}" >/dev/null 2>&1 || true
}

trap cleanup EXIT

on_error() {
    local rc=$?

    printf '%b\n' \
        "${RED}[VNM PANEL][ERROR]${NC} Installer failed with exit code ${rc}." \
        >&2

    if [[ -f "${LOG_FILE}" ]]; then
        echo '---------------- VNM PANEL LOG ----------------' >&2
        tail -n 160 "${LOG_FILE}" >&2 || true
        echo '-----------------------------------------------' >&2
    fi

    exit "${rc}"
}

trap on_error ERR

clear 2>/dev/null || true

printf '%b\n' "${CYAN}"

cat <<'EOF'

██╗   ██╗███╗   ██╗███╗   ███╗
██║   ██║████╗  ██║████╗ ████║
██║   ██║██╔██╗ ██║██╔████╔██║
╚██╗ ██╔╝██║╚██╗██║██║╚██╔╝██║
 ╚████╔╝ ██║ ╚████║██║ ╚═╝ ██║
  ╚═══╝  ╚═╝  ╚═══╝╚═╝     ╚═╝

                 VNM
           VNM PANEL V3
        FRESH ULTRA INSTALLER V5

EOF

printf '%b\n' "${NC}"

echo '============================================================'

# ============================================================
# ROOT / OS
# ============================================================

[[ ${EUID} -eq 0 ]] \
    || die 'Please run this installer as root.'

[[ -f /etc/os-release ]] \
    || die 'Unable to detect operating system.'

# shellcheck disable=SC1091
source /etc/os-release

info "Operating System : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"
info "Kernel           : $(uname -r)"

case "${ID:-}" in
    ubuntu|debian)
        ;;
    *)
        die "Unsupported OS: ${ID:-unknown}."
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# CURL
# ============================================================

if ! command -v curl >/dev/null 2>&1; then

    info 'curl not found; installing curl...'

    apt-get update -y
    apt-get install -y ca-certificates curl

fi

command -v curl >/dev/null 2>&1 \
    || die 'curl is required.'

mkdir -p "${TMP_DIR}"

# ============================================================
# DOWNLOAD + VERIFY CORE INSTALLER
# ============================================================

info 'Downloading current VNM Panel V5 core installer...'

curl \
    -fsSL \
    --retry 4 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 180 \
    "${CORE_URL}?v=$(date +%s)" \
    -o "${CORE_TMP}"

[[ -s "${CORE_TMP}" ]] \
    || die 'Downloaded core installer is empty.'

chmod 700 "${CORE_TMP}"

grep -Fq \
    "REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer is not from nishant1477/Vnm-panel2.'

grep -Fq \
    "ZIP_NAME='Vnm-panel.zip'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not reference Vnm-panel.zip.'

grep -Fq \
    "INSTALL_DIR='/opt/hkvm'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not use /opt/hkvm.'

grep -q \
    '# Invalidate current admin sessions' \
    "${CORE_TMP}" &&
    die 'Downloaded core installer contains the known invalid JavaScript # comment. Fix install-v5.sh before using it.' \
    || true

ok 'Core installer validation passed.'

# ============================================================
# RUN REAL CORE INSTALLER
# ============================================================

info 'Starting VNM Panel V5 core installation...'

bash "${CORE_TMP}" "$@"

ok 'VNM Panel V5 core installation completed.'

# ============================================================
# VERIFY CORE INSTALLATION
# ============================================================

[[ -d "${APP_DIR}" ]] \
    || die "Application directory missing: ${APP_DIR}"

[[ -f "${APP_DIR}/app.js" ]] \
    || die "Application entrypoint missing: ${APP_DIR}/app.js"

[[ -f "${ENV_FILE}" ]] \
    || die "Environment file missing: ${ENV_FILE}"

command -v node >/dev/null 2>&1 \
    || die 'Node.js is missing after installation.'

NODE_BIN="$(
    readlink -f "$(command -v node)" 2>/dev/null ||
    command -v node
)"

[[ -x "${NODE_BIN}" ]] \
    || die "Node binary is not executable: ${NODE_BIN}"

# ============================================================
# FORCE THE ACTUAL VNM DATA DIRECTORY
#
# app.js reads VNM_DATA_DIR.
# The old installer only provided HKVM_DATA_DIR,
# which lets the app fall back to /root/.vnm.
# ============================================================

info "Configuring VNM data directory: ${DATA_DIR}"

mkdir -p "${DATA_DIR}"

if grep -q '^VNM_DATA_DIR=' "${ENV_FILE}"; then

    sed -i \
        "s|^VNM_DATA_DIR=.*|VNM_DATA_DIR=${DATA_DIR}|" \
        "${ENV_FILE}"

else

    printf '\nVNM_DATA_DIR=%s\n' "${DATA_DIR}" \
        >> "${ENV_FILE}"

fi

chmod 600 "${ENV_FILE}"

ln -sfn \
    "${ENV_FILE}" \
    "${APP_DIR}/.env"

ok "VNM_DATA_DIR=${DATA_DIR}"

# ============================================================
# RESTART PANEL WITH CORRECTED ENVIRONMENT
# ============================================================

if command -v systemctl >/dev/null 2>&1 &&
   [[ -d /run/systemd/system ]] &&
   [[ -f "${SERVICE_FILE}" ]]; then

    info 'Restarting hkvm service with corrected VNM_DATA_DIR...'

    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"

    sleep 5

    systemctl is-active --quiet "${SERVICE_NAME}" \
        || die 'hkvm service failed after environment correction.'

    ok 'hkvm service restarted successfully.'

else

    warn \
        'systemd service mode is unavailable; standalone mode will use the corrected environment.'

fi

# ============================================================
# DATABASE
# ============================================================

DB_FILE="${DATA_DIR}/vnm.db"

info 'Waiting for VNM Panel database...'

for _ in {1..60}; do

    [[ -f "${DB_FILE}" ]] && break

    sleep 1

done

[[ -f "${DB_FILE}" ]] \
    || die "VNM Panel database was not created at ${DB_FILE}."

info "Using VNM Panel database: ${DB_FILE}"

[[ -d "${APP_DIR}/node_modules/sqlite3" ]] \
    || die 'sqlite3 is missing.'

[[ -d "${APP_DIR}/node_modules/bcryptjs" ]] \
    || die 'bcryptjs is missing.'

# ============================================================
# WAIT FOR USERS TABLE
# ============================================================

info 'Waiting for VNM Panel database schema...'

SCHEMA_READY='false'

export VNM_SQLITE_MODULE="${APP_DIR}/node_modules/sqlite3"
export VNM_DB_FILE="${DB_FILE}"

for _ in {1..60}; do

    if "${NODE_BIN}" <<'NODE' >/dev/null 2>&1
const sqlite3 = require(process.env.VNM_SQLITE_MODULE).verbose();
const db = new sqlite3.Database(process.env.VNM_DB_FILE);

db.get(
  "SELECT 1 FROM sqlite_master WHERE type = \"table\" AND name = \"users\" LIMIT 1",
  (err, row) => {
    db.close();
    process.exit(err || !row ? 1 : 0);
  }
);
NODE
    then

        SCHEMA_READY='true'
        break

    fi

    sleep 1

done

[[ "${SCHEMA_READY}" == 'true' ]] \
    || die 'The VNM Panel users table was not initialized.'

ok 'VNM Panel database schema is ready.'

# ============================================================
# ADMIN CREDENTIAL CREATION
# ============================================================

info 'Generating and verifying fresh admin credentials...'

GENERATED_PASSWORD="$(
    "${NODE_BIN}" -e \
        'process.stdout.write(require("crypto").randomBytes(18).toString("base64url"))'
)"

[[ "${#GENERATED_PASSWORD}" -ge 20 ]] \
    || die 'Admin password generation failed.'

export VNM_APP_DIR="${APP_DIR}"
export VNM_DB_FILE="${DB_FILE}"
export VNM_ADMIN_PASSWORD="${GENERATED_PASSWORD}"

"${NODE_BIN}" <<'NODE'
const sqlite3 =
  require(`${process.env.VNM_APP_DIR}/node_modules/sqlite3`).verbose();

const bcrypt =
  require(`${process.env.VNM_APP_DIR}/node_modules/bcryptjs`);

const db =
  new sqlite3.Database(process.env.VNM_DB_FILE);

const username = 'admin';
const password = process.env.VNM_ADMIN_PASSWORD;

function fail(message) {
  console.error(`[VNM PANEL][ERROR] ${message}`);

  db.close(() => {
    process.exit(1);
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) {
        reject(err);
      } else {
        resolve(row);
      }
    });
  });
}

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function(err) {
      if (err) {
        reject(err);
      } else {
        resolve(this);
      }
    });
  });
}

async function main() {
  if (!password || password.length < 12) {
    fail('Generated admin password is invalid.');
    return;
  }

  const existing = await get(
    `SELECT id, username, password, role, is_active
     FROM users
     WHERE username = ?
     LIMIT 1`,
    [username]
  );

  const hash = bcrypt.hashSync(password, 10);

  if (existing) {

    await run(
      `UPDATE users
       SET password = ?, role = 'admin', is_active = 1
       WHERE username = ?`,
      [hash, username]
    );

  } else {

    await run(
      `INSERT INTO users
       (username, password, email, full_name, role, is_active)
       VALUES (?, ?, ?, ?, 'admin', 1)`,
      [
        username,
        hash,
        'admin@vnm.local',
        'Administrator'
      ]
    );

  }

  const verified = await get(
    `SELECT id, username, password, role, is_active
     FROM users
     WHERE username = ?
     LIMIT 1`,
    [username]
  );

  if (!verified) {
    fail('Admin row was not found after creation/update.');
    return;
  }

  if (!bcrypt.compareSync(password, verified.password)) {
    fail('Admin password verification failed.');
    return;
  }

  if (verified.role !== 'admin') {
    fail('Admin role verification failed.');
    return;
  }

  if (Number(verified.is_active) !== 1) {
    fail('Admin active-status verification failed.');
    return;
  }

  // The VNM sessions table is sid/sess/expires.
  // It does not have a user ID column.
  // Clear existing sessions directly.

  try {

    await run('DELETE FROM sessions');

  } catch (err) {

    // Session cleanup is best-effort.
    // The admin credential has already been verified.

  }

  await new Promise(resolve => {
    db.close(() => resolve());
  });

  console.log('[ADMIN_CREDENTIALS_VERIFIED]');
}

main().catch(err => {
  fail(err && err.message ? err.message : String(err));
});
NODE

# ============================================================
# SAVE CREDENTIALS
# ============================================================

umask 077

cat > "${CREDENTIAL_FILE}" <<EOF
VNM Panel
Username: admin
Password: ${GENERATED_PASSWORD}
Database: ${DB_FILE}
EOF

chmod 600 "${CREDENTIAL_FILE}"
chown root:root "${CREDENTIAL_FILE}"

[[ -s "${CREDENTIAL_FILE}" ]] \
    || die 'Admin credentials file was not created.'

ok "Admin credentials saved to ${CREDENTIAL_FILE}"

# ============================================================
# FINAL STATUS
# ============================================================

PANEL_STATUS='OFFLINE'

if command -v ss >/dev/null 2>&1; then

    for _ in {1..20}; do

        if ss -ltn 2>/dev/null |
            grep -q ":${PANEL_PORT}"; then

            PANEL_STATUS='ONLINE'
            break

        fi

        sleep 1

    done

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

    PUBLIC_IP="$(
        hostname -I 2>/dev/null |
            awk '{print $1}' ||
            true
    )"

fi

[[ -n "${PUBLIC_IP}" ]] \
    || PUBLIC_IP='YOUR_SERVER_IP'

clear 2>/dev/null || true

printf '%b\n' "${GREEN}"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                         VNM                                ║
║                    VNM PANEL V3                            ║
║                  INSTALLATION COMPLETE                    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

  STATUS              : ${PANEL_STATUS}
  PANEL URL           : http://${PUBLIC_IP}:${PANEL_PORT}

  INSTALL DIRECTORY   : ${INSTALL_DIR}
  APPLICATION         : ${APP_DIR}
  DATABASE            : ${DB_FILE}
  CONFIGURATION       : ${ENV_FILE}
  SERVICE             : ${SERVICE_NAME}
  LOG FILE            : ${LOG_FILE}

  ADMIN USERNAME      : admin
  ADMIN CREDENTIALS   : ${CREDENTIAL_FILE}

──────────────────────────────────────────────────────────────

  SERVICE COMMANDS

    systemctl status ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}
    journalctl -u ${SERVICE_NAME} -f

  VIEW ADMIN CREDENTIALS

    cat ${CREDENTIAL_FILE}

──────────────────────────────────────────────────────────────

  REPOSITORY

    https://github.com/nishant1477/Vnm-panel2

  LICENSE

    DISABLED

╚════════════════════════════════════════════════════════════╝

EOF

printf '%b\n' "${NC}"

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then

    ok "VNM Panel is running on port ${PANEL_PORT}."

else

    warn "VNM Panel is not listening yet."

    warn \
        "Check: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"

fi

echo '============================================================'
echo 'VNM Panel installation finished.'
