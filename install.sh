#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================================
# VNM PANEL — STABLE INSTALLER ENTRYPOINT
#
# Repository:
#   https://github.com/nishant1477/Vnm-panel2
#
# Flow:
#   1. Install required host prerequisites.
#   2. Download the maintained VNM Panel V5 installer from this repository.
#   3. Run the repository's installer (which installs VNM-Panel.zip).
#   4. Create + verify a fresh admin credential in the live SQLite database.
#
# Runtime-compatible HKVM_* variables and /opt/hkvm paths are preserved.
# No blanket HKVM/HKVM_* branding substitutions are performed.
# ============================================================================

readonly CORE_URL='https://raw.githubusercontent.com/nishant1477/Vnm-panel2/main/install-v5.sh'
readonly TMP="/tmp/vnm-panel-install-v5-$$.sh"
readonly CORE_TMP="/tmp/vnm-panel-install-v5-core-$$.sh"
readonly CREDENTIAL_FILE='/opt/hkvm/admin-credentials.txt'
readonly ENV_FILE='/etc/hkvm/hkvm.env'

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
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
    printf '%b\n' "${RED}[VNM PANEL][ERROR]${NC} %s" "$*" >&2
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

command -v apt-get >/dev/null 2>&1 || die 'apt-get is required on Debian/Ubuntu.'
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# HOST PREREQUISITES
# ============================================================================

install_vnm_panel_prerequisites() {
    [[ "${VNM_PANEL_PREREQS_DONE:-false}" == 'true' ]] && {
        info 'VNM Panel host prerequisites were already installed by the parent installer.'
        return 0
    }

    info 'Updating APT package lists...'
    apt-get update -y

    info 'Installing VNM Panel host prerequisites...'
    apt-get install -y \
        ca-certificates \
        curl \
        unzip \
        file \
        lsof \
        procps \
        iproute2 \
        openssl \
        build-essential \
        python3 \
        cloud-image-utils \
        genisoimage

    # Match Vnm-panel2/install-v5.sh:
    # install the virtualization stack on normal systemd hosts, but don't
    # unnecessarily force the full virtualization stack into containers or
    # Codespaces where systemd is unavailable.
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        info 'systemd detected; installing QEMU + OVMF host packages...'
        apt-get install -y \
            qemu-system-x86 \
            qemu-utils \
            ovmf
    else
        info 'systemd not detected; core installer will handle non-systemd mode.'
    fi

    command -v curl >/dev/null 2>&1 \
        || die 'curl is still missing after prerequisite installation.'

    command -v unzip >/dev/null 2>&1 \
        || die 'unzip is still missing after prerequisite installation.'

    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        qemu-system-x86_64 --version | head -n 1 || true
    fi

    if [[ -e /dev/kvm ]]; then
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            ok 'KVM device detected and accessible.'
        else
            warn '/dev/kvm exists but is not readable/writable by root.'
        fi
    else
        warn 'KVM device /dev/kvm is not available. Software QEMU may still work where supported.'
    fi

    export VNM_PANEL_PREREQS_DONE='true'
    ok 'VNM Panel host prerequisites are installed.'
}

install_vnm_panel_prerequisites

# ============================================================================
# DOWNLOAD THE CORRECT CORE INSTALLER
# ============================================================================

CORE_FETCH_URL="${CORE_URL}?v=$(date +%s)"

info 'Downloading VNM Panel V5 core installer from Vnm-panel2...'

curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 10 \
    --max-time 120 \
    "${CORE_FETCH_URL}" \
    -o "${CORE_TMP}"

[[ -s "${CORE_TMP}" ]] \
    || die 'Downloaded VNM Panel core installer is empty.'

chmod 700 "${CORE_TMP}"

# Safety validation:
# Make sure we downloaded the actual Vnm-panel2 installer and not the old
# stripathi02123-tech/Vnm-panel installer.
grep -Fq \
    "REPO_URL='https://github.com/nishant1477/Vnm-panel2.git'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer is not the expected nishant1477/Vnm-panel2 installer.'

grep -Fq \
    "ZIP_NAME='Vnm-panel.zip'" \
    "${CORE_TMP}" \
    || die 'Downloaded core installer is missing the expected Vnm-panel.zip source.'

grep -Fq \
    'PANEL_NAME="VNM Panel"' \
    "${CORE_TMP}" \
    || die 'Downloaded core installer failed VNM Panel environment validation.'

cp -f "${CORE_TMP}" "${TMP}"
chmod 700 "${TMP}"

info 'Starting VNM Panel V5 core installation...'

"${TMP}" "$@"

# ============================================================================
# ADMIN CREDENTIAL CREATION / DISPLAY / RECOVERY
# ============================================================================

create_and_verify_admin_credentials() {
    local app_dir='/opt/hkvm/app'
    local data_dir='/opt/hkvm/data'
    local node_bin=''
    local db_file=''
    local generated_password=''
    local candidate=''

    command -v node >/dev/null 2>&1 \
        || die 'Node.js is missing; cannot create admin credentials.'

    node_bin="$(
        readlink -f "$(command -v node)" 2>/dev/null \
        || command -v node
    )"

    # install-v5.sh writes these variables into /etc/hkvm/hkvm.env.
    if [[ -f "${ENV_FILE}" ]]; then
        # shellcheck disable=SC1091
        source "${ENV_FILE}" || true

        app_dir="${HKVM_APP_DIR:-${app_dir}}"
        data_dir="${HKVM_DATA_DIR:-${data_dir}}"
    fi

    # Known VNM/HKVM database locations.
    #
    # Current Vnm-panel2 install-v5.sh creates:
    #   /opt/hkvm/data
    #
    # Older VNM/HKVM builds may use:
    #   /root/.vnm/vnm.db
    #   /opt/hkvm/app/data/vnm.db
    #
    local candidates=(
        '/root/.vnm/vnm.db'
        "${data_dir}/vnm.db"
        '/opt/hkvm/data/vnm.db'
        '/opt/hkvm/app/data/vnm.db'
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            db_file="${candidate}"
            break
        fi
    done

    # Give the panel time to initialize the database.
    if [[ -z "${db_file}" ]]; then
        info 'Waiting for the VNM Panel database to initialize...'

        for _ in {1..45}; do
            for candidate in "${candidates[@]}"; do
                if [[ -f "${candidate}" ]]; then
                    db_file="${candidate}"
                    break
                fi
            done

            [[ -n "${db_file}" ]] && break

            sleep 1
        done
    fi

    # Last-resort discovery.
    if [[ -z "${db_file}" ]]; then
        db_file="$(
            find /root /opt/hkvm \
                -type f \
                -name 'vnm.db' \
                -not -path '*/node_modules/*' \
                -not -path '*/tmp/*' \
                -print \
                -quit \
                2>/dev/null || true
        )"
    fi

    [[ -n "${db_file}" && -f "${db_file}" ]] \
        || die 'Live VNM database could not be found; admin credentials were not generated.'

    [[ -d "${app_dir}" ]] \
        || die "VNM application directory not found: ${app_dir}"

    [[ -d "${app_dir}/node_modules/sqlite3" ]] \
        || die 'sqlite3 is missing from the VNM application; cannot safely modify the database.'

    # Prefer bcryptjs, but support bcrypt too.
    local bcrypt_module=''

    if [[ -d "${app_dir}/node_modules/bcryptjs" ]]; then
        bcrypt_module="${app_dir}/node_modules/bcryptjs"
    elif [[ -d "${app_dir}/node_modules/bcrypt" ]]; then
        bcrypt_module="${app_dir}/node_modules/bcrypt"
    else
        die 'Neither bcryptjs nor bcrypt is installed in the VNM application.'
    fi

    info "Using VNM Panel database: ${db_file}"
    info 'Generating and verifying fresh admin credentials...'

    generated_password="$(
        "${node_bin}" -e \
            'process.stdout.write(require("crypto").randomBytes(18).toString("base64url"))'
    )"

    [[ "${#generated_password}" -ge 20 ]] \
        || die 'Admin password generation failed.'

    export VNM_APP_DIR="${app_dir}"
    export VNM_DB_FILE="${db_file}"
    export VNM_ADMIN_PASSWORD="${generated_password}"
    export VNM_BCRYPT_MODULE="${bcrypt_module}"

    "${node_bin}" <<'NODE'
const sqlite3 = require(`${process.env.VNM_APP_DIR}/node_modules/sqlite3`);
const bcryptModule = require(process.env.VNM_BCRYPT_MODULE);

const bcrypt =
  typeof bcryptModule.hashSync === 'function'
    ? bcryptModule
    : (
        bcryptModule.default &&
        typeof bcryptModule.default.hashSync === 'function'
          ? bcryptModule.default
          : null
      );

if (!bcrypt) {
  throw new Error(
    'Loaded bcrypt module does not expose hashSync/compareSync.'
  );
}

const db = new sqlite3.Database(process.env.VNM_DB_FILE);

const username = 'admin';
const password = process.env.VNM_ADMIN_PASSWORD;

function fail(message) {
  console.error(`[VNM PANEL][ERROR] ${message}`);
  db.close(() => process.exit(1));
}

function quoteIdent(name) {
  return `"${String(name).replace(/"/g, '""')}"`;
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

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) {
        reject(err);
      } else {
        resolve(rows || []);
      }
    });
  });
}

async function tableExists(table) {
  return Boolean(
    await get(
      `SELECT 1
       FROM sqlite_master
       WHERE type='table'
         AND name = ?
       LIMIT 1`,
      [table]
    )
  );
}

async function tableInfo(table) {
  return all(`PRAGMA table_info(${quoteIdent(table)})`);
}

async function main() {
  if (!password || password.length < 12) {
    fail('Generated admin password is invalid.');
    return;
  }

  if (!await tableExists('users')) {
    fail(
      'The live database does not contain a users table; refusing to guess another authentication schema.'
    );
    return;
  }

  const columns = await tableInfo('users');
  const colMap = new Map(columns.map(c => [c.name, c]));

  if (!colMap.has('username') || !colMap.has('password')) {
    fail(
      'The users table does not contain username/password columns.'
    );
    return;
  }

  const hash = bcrypt.hashSync(password, 12);

  const existing = await get(
    `SELECT rowid
     FROM ${quoteIdent('users')}
     WHERE ${quoteIdent('username')} = ?
     LIMIT 1`,
    [username]
  );

  if (existing) {
    const assignments = [
      `${quoteIdent('password')} = ?`
    ];

    const params = [hash];

    if (colMap.has('role')) {
      assignments.push(`${quoteIdent('role')} = ?`);
      params.push('admin');
    }

    if (colMap.has('is_active')) {
      assignments.push(`${quoteIdent('is_active')} = ?`);
      params.push(1);
    }

    params.push(username);

    await run(
      `UPDATE ${quoteIdent('users')}
       SET ${assignments.join(', ')}
       WHERE ${quoteIdent('username')} = ?`,
      params
    );
  } else {
    const insertColumns = [];
    const placeholders = [];
    const values = [];

    const addColumn = (name, value) => {
      if (colMap.has(name)) {
        insertColumns.push(quoteIdent(name));
        placeholders.push('?');
        values.push(value);
      }
    };

    addColumn('username', username);
    addColumn('password', hash);
    addColumn('email', 'admin@vnm.local');
    addColumn('full_name', 'Administrator');
    addColumn('role', 'admin');
    addColumn('is_active', 1);

    const missingRequired = columns.filter(c => {
      if (!c.notnull) return false;
      if (c.pk) return false;
      if (c.dflt_value !== null) return false;

      return !insertColumns.includes(
        quoteIdent(c.name)
      );
    });

    if (missingRequired.length) {
      fail(
        `Cannot safely create admin; required users columns are unsupported: ${
          missingRequired.map(c => c.name).join(', ')
        }`
      );
      return;
    }

    await run(
      `INSERT INTO ${quoteIdent('users')}
       (${insertColumns.join(', ')})
       VALUES (${placeholders.join(', ')})`,
      values
    );
  }

  const row = await get(
    `SELECT *
     FROM ${quoteIdent('users')}
     WHERE ${quoteIdent('username')} = ?
     LIMIT 1`,
    [username]
  );

  if (!row) {
    fail('Admin row was not found after update/insert.');
    return;
  }

  if (!bcrypt.compareSync(password, row.password)) {
    fail('bcrypt password verification failed.');
    return;
  }

  if (
    colMap.has('role') &&
    row.role !== 'admin'
  ) {
    fail('Admin role verification failed.');
    return;
  }

  if (
    colMap.has('is_active') &&
    Number(row.is_active) !== 1
  ) {
    fail('Admin active-status verification failed.');
    return;
  }

  # Invalidate current admin sessions only when that table exists and
  # actually contains user_id.
  if (await tableExists('sessions')) {
    const sessionColumns = await tableInfo('sessions');

    const hasUserId = sessionColumns.some(
      c => c.name === 'user_id'
    );

    if (hasUserId && colMap.has('id')) {
      await run(
        `DELETE FROM ${quoteIdent('sessions')}
         WHERE ${quoteIdent('user_id')} = (
           SELECT ${quoteIdent('id')}
           FROM ${quoteIdent('users')}
           WHERE ${quoteIdent('username')} = ?
         )`,
        [username]
      );
    }
  }

  await new Promise(resolve => db.close(resolve));

  console.log('[ADMIN_CREDENTIALS_VERIFIED]');
  process.exit(0);
}

main().catch(err => {
  fail(err.message || String(err));
});
NODE

    umask 077
    mkdir -p "$(dirname "${CREDENTIAL_FILE}")"

    cat > "${CREDENTIAL_FILE}" <<EOF
VNM/HKVM Panel
Username: admin
Password: ${generated_password}
EOF

    chmod 600 "${CREDENTIAL_FILE}"
    chown root:root "${CREDENTIAL_FILE}"

    [[ -s "${CREDENTIAL_FILE}" ]] \
        || die 'Admin credential file was not created.'

    grep -Fq 'Username: admin' "${CREDENTIAL_FILE}" \
        || die 'Admin credential file is missing the username.'

    grep -Fq 'Password: ' "${CREDENTIAL_FILE}" \
        || die 'Admin credential file is missing the password.'

    ok "Fresh admin credentials written and verified: ${CREDENTIAL_FILE}"
}

# ============================================================================
# CREATE ADMIN
# ============================================================================

create_and_verify_admin_credentials

# ============================================================================
# FINAL CREDENTIAL DISPLAY
# ============================================================================

printf '\n'

printf '%b\n' \
    "${GREEN}============================================================${NC}"

printf '%b\n' \
    "${CYAN}VNM PANEL ADMIN CREDENTIALS${NC}"

printf '%b\n' \
    "${GREEN}============================================================${NC}"

cat "${CREDENTIAL_FILE}"

printf '\n'

info "Credentials file: ${CREDENTIAL_FILE}"
info "View again with: cat ${CREDENTIAL_FILE}"
info "Core installer: ${CORE_URL}"

exit 0
