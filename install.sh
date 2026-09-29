#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# VNM PANEL — STABLE INSTALLER ENTRYPOINT
#
# Repository:
#   https://github.com/nishant1477/Vnm-panel2
#
# Core:
#   https://raw.githubusercontent.com/nishant1477/Vnm-panel2/main/install-v5.sh
#
# The core install-v5.sh performs the actual panel installation.
# This wrapper only:
#   - downloads/validates the correct core installer
#   - runs it
#   - fixes the runtime data-directory environment
#   - creates/verifies the admin account
#
# No branding replacements are performed.
# ============================================================================

readonly CORE_URL='https://raw.githubusercontent.com/nishant1477/Vnm-panel2/main/install-v5.sh'
readonly TMP="/tmp/vnm-panel-install-v5-$$.sh"
readonly CORE_TMP="/tmp/vnm-panel-install-v5-core-$$.sh"

readonly INSTALL_DIR='/opt/hkvm'
readonly APP_DIR='/opt/hkvm/app'
readonly DATA_DIR='/opt/hkvm/data'
readonly LOG_DIR='/opt/hkvm/logs'
readonly BACKUP_DIR='/opt/hkvm/backups'
readonly CONFIG_DIR='/etc/hkvm'
readonly ENV_FILE='/etc/hkvm/hkvm.env'
readonly LOG_FILE='/opt/hkvm/logs/hkvm.log'
readonly CREDENTIAL_FILE='/opt/hkvm/admin-credentials.txt'

readonly SERVICE_NAME='hkvm'
readonly SERVICE_FILE='/etc/systemd/system/hkvm.service'

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

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
    rm -f "${TMP}" "${CORE_TMP}" || true
}

trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || die 'Run the VNM Panel installer as root.'
[[ -f /etc/os-release ]] || die 'Unable to detect the operating system.'

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    ubuntu|debian)
        ;;
    *)
        die "VNM Panel requires Debian or Ubuntu (detected: ${ID:-unknown})."
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# BASIC DEPENDENCIES
# ============================================================================

if ! command -v curl >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl
fi

command -v curl >/dev/null 2>&1 || die 'curl is required.'

# ============================================================================
# DOWNLOAD THE ACTUAL VNM PANEL CORE INSTALLER
# ============================================================================

CORE_FETCH_URL="${CORE_URL}?v=$(date +%s)"

info 'Downloading current VNM Panel V5 installer...'

curl \
    -fsSL \
    --retry 4 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 180 \
    "${CORE_FETCH_URL}" \
    -o "${CORE_TMP}"

[[ -s "${CORE_TMP}" ]] \
    || die 'Downloaded install-v5.sh is empty.'

chmod 700 "${CORE_TMP}"

# ============================================================================
# VALIDATION
# ============================================================================

grep -Fq \
    "REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer is not the Vnm-panel2 installer.'

grep -Fq \
    "ZIP_NAME='Vnm-panel.zip'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not use Vnm-panel.zip.'

grep -Fq \
    "INSTALL_DIR='/opt/hkvm'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not use /opt/hkvm.'

grep -Fq \
    "SERVICE_NAME='hkvm'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not use hkvm.'

grep -Fq \
    'LICENSE_MODE=disabled' \
    "${CORE_TMP}" \
    || die 'Downloaded core installer does not contain LICENSE_MODE=disabled.'

ok 'Core installer validation passed.'

# ============================================================================
# RUN CORE INSTALLER
# ============================================================================

info 'Starting VNM Panel V5 core installation...'

bash "${CORE_TMP}" "$@"

ok 'VNM Panel V5 core installation completed.'

# ============================================================================
# VERIFY INSTALLATION
# ============================================================================

[[ -d "${APP_DIR}" ]] \
    || die "Application directory missing: ${APP_DIR}"

[[ -f "${APP_DIR}/app.js" ]] \
    || die "VNM Panel entrypoint missing: ${APP_DIR}/app.js"

[[ -f "${ENV_FILE}" ]] \
    || die "VNM Panel environment file missing: ${ENV_FILE}"

# ============================================================================
# IMPORTANT DATA-DIRECTORY FIX
#
# app.js uses:
#
#   process.env.VNM_DATA_DIR || ~/.vnm
#
# The original core installer only writes HKVM_DATA_DIR.
# Therefore app.js can fall back to /root/.vnm/vnm.db.
#
# Force the real VNM data directory here.
# ============================================================================

info 'Configuring VNM runtime data directory...'

if grep -q '^VNM_DATA_DIR=' "${ENV_FILE}" 2>/dev/null; then
    sed -i \
        "s|^VNM_DATA_DIR=.*|VNM_DATA_DIR=${DATA_DIR}|" \
        "${ENV_FILE}"
else
    printf '\nVNM_DATA_DIR=%s\n' "${DATA_DIR}" >> "${ENV_FILE}"
fi

chmod 600 "${ENV_FILE}"

mkdir -p "${DATA_DIR}"

# Keep the application's .env synchronized.
ln -sfn "${ENV_FILE}" "${APP_DIR}/.env"

ok "VNM data directory configured: ${DATA_DIR}"

# ============================================================================
# RESTART PANEL SO NEW VNM_DATA_DIR IS ACTIVE
# ============================================================================

if command -v systemctl >/dev/null 2>&1 &&
   [[ -f "${SERVICE_FILE}" ]] &&
   [[ -d /run/systemd/system ]]; then

    info 'Restarting VNM Panel with corrected environment...'

    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"

    sleep 5

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok 'VNM Panel service is ONLINE.'
    else
        warn 'VNM Panel service is not active after restart.'
    fi
fi

# ============================================================================
# NODE
# ============================================================================

command -v node >/dev/null 2>&1 \
    || die 'Node.js is missing after installation.'

NODE_BIN="$(
    readlink -f "$(command -v node)" 2>/dev/null ||
    command -v node
)"

[[ -x "${NODE_BIN}" ]] \
    || die "Node.js binary is not executable: ${NODE_BIN}"

# ============================================================================
# DATABASE
# ============================================================================

DB_FILE="${DATA_DIR}/vnm.db"

info 'Waiting for VNM Panel database...'

for _ in {1..60}; do
    [[ -f "${DB_FILE}" ]] && break
    sleep 1
done

[[ -f "${DB_FILE}" ]] \
    || die "VNM Panel database was not created: ${DB_FILE}"

info "Using VNM Panel database: ${DB_FILE}"

# ============================================================================
# REQUIRED MODULES
# ============================================================================

[[ -d "${APP_DIR}/node_modules/sqlite3" ]] \
    || die 'sqlite3 is missing from the VNM Panel installation.'

[[ -d "${APP_DIR}/node_modules/bcryptjs" ]] \
    || die 'bcryptjs is missing from the VNM Panel installation.'

# ============================================================================
# WAIT FOR USERS TABLE
# ============================================================================

info 'Waiting for VNM Panel database schema...'

SCHEMA_READY='false'

for _ in {1..60}; do

    if "${NODE_BIN}" -e '
const sqlite3 = require(process.argv[1]).verbose();
const db = new sqlite3.Database(process.argv[2]);

db.get(
    "SELECT 1 FROM sqlite_master WHERE type = '\''table'\'' AND name = '\''users'\'' LIMIT 1",
    (err, row) => {
        db.close();
        process.exit(err || !row ? 1 : 0);
    }
);
' \
        "${APP_DIR}/node_modules/sqlite3" \
        "${DB_FILE}" \
        >/dev/null 2>&1; then

        SCHEMA_READY='true'
        break
    fi

    sleep 1
done

[[ "${SCHEMA_READY}" == 'true' ]] \
    || die 'VNM Panel users table was not initialized.'

ok 'VNM Panel database schema is ready.'

# ============================================================================
# ADMIN ACCOUNT
# ============================================================================

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
        `
        SELECT
            id,
            username,
            password,
            role,
            is_active
        FROM users
        WHERE username = ?
        LIMIT 1
        `,
        [username]
    );

    const hash = bcrypt.hashSync(password, 10);

    if (existing) {

        await run(
            `
            UPDATE users
            SET
                password = ?,
                role = 'admin',
                is_active = 1
            WHERE username = ?
            `,
            [hash, username]
        );

    } else {

        await run(
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
            VALUES
                (
                    ?,
                    ?,
                    ?,
                    ?,
                    'admin',
                    1
                )
            `,
            [
                username,
                hash,
                'admin@vnm.local',
                'Administrator'
            ]
        );
    }

    const verified = await get(
        `
        SELECT
            id,
            username,
            password,
            role,
            is_active
        FROM users
        WHERE username = ?
        LIMIT 1
        `,
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

    // The VNM sessions table contains:
    // sid, sess, expires
    //
    // It does NOT contain user_id.
    // Therefore clear the session table directly.

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

# ============================================================================
# SAVE ADMIN CREDENTIALS
# ============================================================================

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
    || die 'Admin credential file was not created.'

ok "Fresh admin credentials written: ${CREDENTIAL_FILE}"

# ============================================================================
# FINAL PANEL CHECK
# ============================================================================

PANEL_PORT='8080'
PANEL_STATUS='OFFLINE'

for _ in {1..20}; do

    if ss -ltn 2>/dev/null |
        grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then

        PANEL_STATUS='ONLINE'
        break
    fi

    sleep 1
done

# ============================================================================
# FINAL SCREEN
# ============================================================================

clear 2>/dev/null || true

echo -e "${GREEN}"

cat <<EOF

╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                         VNM                                ║
║                    VNM PANEL V3                            ║
║                  INSTALLATION COMPLETE                    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

  STATUS              : ${PANEL_STATUS}
  PANEL URL           : http://YOUR_SERVER_IP:${PANEL_PORT}

  INSTALL DIRECTORY   : ${INSTALL_DIR}
  APPLICATION         : ${APP_DIR}
  DATABASE            : ${DB_FILE}
  CONFIGURATION       : ${ENV_FILE}
  SERVICE             : ${SERVICE_NAME}
  LOG FILE            : ${LOG_FILE}

──────────────────────────────────────────────────────────────

  ADMIN USERNAME      : admin
  ADMIN CREDENTIALS   : ${CREDENTIAL_FILE}

  VIEW CREDENTIALS:

    cat ${CREDENTIAL_FILE}

──────────────────────────────────────────────────────────────

  SOURCE REPOSITORY

    https://github.com/nishant1477/Vnm-panel2

  LICENSE

    DISABLED

╚════════════════════════════════════════════════════════════╝

EOF

echo -e "${NC}"

if [[ "${PANEL_STATUS}" == 'ONLINE' ]]; then
    ok "VNM Panel is running on port ${PANEL_PORT}."
else
    warn "VNM Panel is not listening yet."
    warn "Check: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
fi

printf '\n'
ok 'VNM Panel installation finished.'
