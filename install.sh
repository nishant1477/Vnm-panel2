#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GKVM Panel - Automatic Installer
# Repository: nishant1477/Vnm-panel2
# ============================================================

APP_NAME="GKVM Panel"
SERVICE_NAME="gkvm-panel"

INSTALL_DIR="/opt/gkvm-panel"
CONFIG_DIR="/etc/gkvm-panel"

ZIP_URL="https://github.com/nishant1477/Vnm-panel2/raw/refs/heads/main/GKVM-panel.zip"

DEFAULT_PORT="8080"
LOG_FILE="/var/log/gkvm-panel-install.log"

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[GKVM] $*"
}

error() {
    echo
    echo "[GKVM][ERROR] $*"
    exit 1
}

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    error "Please run this installer as root."
fi

echo
echo "============================================================"
echo "              GKVM PANEL INSTALLER"
echo "============================================================"
echo

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
else
    error "Unable to detect operating system."
fi

log "Operating System: ${PRETTY_NAME:-Unknown}"

# ------------------------------------------------------------
# Install system dependencies
# ------------------------------------------------------------

log "Installing required packages..."

if command -v apt-get >/dev/null 2>&1; then

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    apt-get install -y \
        curl \
        wget \
        unzip \
        ca-certificates \
        git \
        sudo \
        openssl \
        procps \
        lsof \
        net-tools \
        python3 \
        python3-pip \
        python3-venv \
        build-essential

elif command -v dnf >/dev/null 2>&1; then

    dnf install -y \
        curl \
        wget \
        unzip \
        ca-certificates \
        git \
        sudo \
        openssl \
        procps-ng \
        lsof \
        net-tools \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make

elif command -v yum >/dev/null 2>&1; then

    yum install -y \
        curl \
        wget \
        unzip \
        ca-certificates \
        git \
        sudo \
        openssl \
        procps \
        lsof \
        net-tools \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make

else
    error "Unsupported Linux distribution."
fi

# ------------------------------------------------------------
# Install Node.js if required
# ------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then

    log "Node.js not found. Installing Node.js 22..."

    if command -v apt-get >/dev/null 2>&1; then

        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs

    elif command -v dnf >/dev/null 2>&1; then

        curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
        dnf install -y nodejs

    elif command -v yum >/dev/null 2>&1; then

        curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
        yum install -y nodejs

    fi
fi

if command -v node >/dev/null 2>&1; then
    log "Node.js: $(node --version)"
fi

if command -v npm >/dev/null 2>&1; then
    log "npm: $(npm --version)"
fi

# ------------------------------------------------------------
# Stop existing GKVM service
# ------------------------------------------------------------

log "Stopping previous GKVM installation..."

systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# ------------------------------------------------------------
# Create directories
# ------------------------------------------------------------

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# ------------------------------------------------------------
# Temporary directory
# ------------------------------------------------------------

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

ZIP_FILE="$TMP_DIR/GKVM-panel.zip"
EXTRACT_DIR="$TMP_DIR/extracted"

mkdir -p "$EXTRACT_DIR"

# ------------------------------------------------------------
# Download GKVM
# ------------------------------------------------------------

log "Downloading GKVM Panel..."

curl \
    -fL \
    --retry 5 \
    --retry-delay 2 \
    "$ZIP_URL" \
    -o "$ZIP_FILE" \
    || error "Failed to download GKVM-panel.zip."

if [[ ! -s "$ZIP_FILE" ]]; then
    error "Downloaded GKVM-panel.zip is empty."
fi

log "Download complete."
log "Package size: $(du -h "$ZIP_FILE" | awk '{print $1}')"

# ------------------------------------------------------------
# Validate ZIP
# ------------------------------------------------------------

log "Checking ZIP integrity..."

if ! unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    error "GKVM-panel.zip is corrupted or invalid."
fi

# ------------------------------------------------------------
# Extract
# ------------------------------------------------------------

log "Extracting GKVM Panel..."

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"

# Handle ZIP with a single top-level directory
shopt -s dotglob nullglob

FILES=("$EXTRACT_DIR"/*)

if [[ ${#FILES[@]} -eq 1 && -d "${FILES[0]}" ]]; then

    cp -a "${FILES[0]}"/. "$INSTALL_DIR"/

else

    cp -a "$EXTRACT_DIR"/. "$INSTALL_DIR"/

fi

shopt -u dotglob nullglob

# ------------------------------------------------------------
# Find application
# ------------------------------------------------------------

find_file() {
    find "$INSTALL_DIR" \
        -type f \
        -name "$1" \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -print -quit
}

PACKAGE_JSON="$(find_file "package.json" || true)"
REQUIREMENTS="$(find_file "requirements.txt" || true)"

APP_ROOT="$INSTALL_DIR"
START_COMMAND=""

# ------------------------------------------------------------
# Node.js application
# ------------------------------------------------------------

if [[ -n "$PACKAGE_JSON" ]]; then

    APP_ROOT="$(dirname "$PACKAGE_JSON")"

    log "Node.js application detected."
    log "Application directory: $APP_ROOT"

    cd "$APP_ROOT"

    log "Installing Node.js dependencies..."

    if [[ -f package-lock.json ]]; then

        npm ci --omit=dev || npm install --omit=dev

    else

        npm install --omit=dev

    fi

    # package.json start script
    if node -e '
        const pkg=require("./package.json");
        process.exit(
            pkg.scripts && pkg.scripts.start ? 0 : 1
        );
    ' >/dev/null 2>&1; then

        START_COMMAND="npm start"

    elif [[ -f "$APP_ROOT/server.js" ]]; then

        START_COMMAND="node server.js"

    elif [[ -f "$APP_ROOT/app.js" ]]; then

        START_COMMAND="node app.js"

    elif [[ -f "$APP_ROOT/index.js" ]]; then

        START_COMMAND="node index.js"

    elif [[ -f "$APP_ROOT/main.js" ]]; then

        START_COMMAND="node main.js"

    fi

fi

# ------------------------------------------------------------
# Python application
# ------------------------------------------------------------

if [[ -n "$REQUIREMENTS" && -z "$START_COMMAND" ]]; then

    APP_ROOT="$(dirname "$REQUIREMENTS")"

    log "Python application detected."
    log "Application directory: $APP_ROOT"

    cd "$APP_ROOT"

    log "Creating Python virtual environment..."

    python3 -m venv "$APP_ROOT/.venv"

    "$APP_ROOT/.venv/bin/python" \
        -m pip install --upgrade \
        pip \
        setuptools \
        wheel

    log "Installing Python dependencies..."

    "$APP_ROOT/.venv/bin/pip" \
        install \
        -r "$REQUIREMENTS"

    if [[ -f "$APP_ROOT/main.py" ]]; then

        START_COMMAND="$APP_ROOT/.venv/bin/python $APP_ROOT/main.py"

    elif [[ -f "$APP_ROOT/app.py" ]]; then

        START_COMMAND="$APP_ROOT/.venv/bin/python $APP_ROOT/app.py"

    elif [[ -f "$APP_ROOT/server.py" ]]; then

        START_COMMAND="$APP_ROOT/.venv/bin/python $APP_ROOT/server.py"

    fi

fi

# ------------------------------------------------------------
# Check shell startup scripts
# ------------------------------------------------------------

if [[ -z "$START_COMMAND" ]]; then

    for SCRIPT in \
        "$APP_ROOT/start.sh" \
        "$APP_ROOT/run.sh" \
        "$APP_ROOT/server.sh"
    do

        if [[ -f "$SCRIPT" ]]; then

            chmod +x "$SCRIPT"

            START_COMMAND="$SCRIPT"

            break

        fi

    done

fi

# ------------------------------------------------------------
# Make sure startup command exists
# ------------------------------------------------------------

if [[ -z "$START_COMMAND" ]]; then

    error "Could not automatically determine GKVM startup command.

The ZIP was installed into:

$INSTALL_DIR

Please check the project startup files."

fi

log "Startup command:"
echo "  $START_COMMAND"

# ------------------------------------------------------------
# Generate admin credentials
# ------------------------------------------------------------

log "Generating secure admin credentials..."

ADMIN_USERNAME="admin"

ADMIN_PASSWORD="$(
    openssl rand -base64 64 |
    tr -dc 'A-Za-z0-9@#%+=_' |
    head -c 24
)"

if [[ ${#ADMIN_PASSWORD} -lt 16 ]]; then

    ADMIN_PASSWORD="GKVM-$(openssl rand -hex 16)"

fi

# ------------------------------------------------------------
# Credentials file
# ------------------------------------------------------------

mkdir -p "$CONFIG_DIR"

CREDENTIAL_FILE="$CONFIG_DIR/admin-credentials.txt"

cat > "$CREDENTIAL_FILE" <<EOF
============================================================
                    GKVM PANEL
                 ADMIN CREDENTIALS
============================================================

Username:
$ADMIN_USERNAME

Password:
$ADMIN_PASSWORD

============================================================

Panel:
http://YOUR_SERVER_IP:${DEFAULT_PORT}

Generated:
$(date -Is)

IMPORTANT:
Keep this file private.
Do not share the password publicly.
============================================================
EOF

chmod 600 "$CREDENTIAL_FILE"

# ------------------------------------------------------------
# Environment file
# ------------------------------------------------------------

ENV_FILE="$CONFIG_DIR/gkvm.env"

cat > "$ENV_FILE" <<EOF
NODE_ENV=production

HOST=0.0.0.0
PORT=${DEFAULT_PORT}
GKVM_PORT=${DEFAULT_PORT}

ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF

chmod 600 "$ENV_FILE"

# ------------------------------------------------------------
# Permissions
# ------------------------------------------------------------

chmod -R u+rwX,go+rX "$INSTALL_DIR"

# ------------------------------------------------------------
# Create systemd service
# ------------------------------------------------------------

log "Creating systemd service..."

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GKVM Panel
Documentation=https://github.com/nishant1477/Vnm-panel2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

WorkingDirectory=${APP_ROOT}

EnvironmentFile=-${ENV_FILE}

ExecStart=/bin/bash -lc '${START_COMMAND}'

Restart=always
RestartSec=5

KillSignal=SIGTERM
TimeoutStopSec=30

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Enable service
# ------------------------------------------------------------

systemctl daemon-reload

systemctl enable "$SERVICE_NAME"

# ------------------------------------------------------------
# Start service
# ------------------------------------------------------------

log "Starting GKVM Panel..."

systemctl restart "$SERVICE_NAME"

sleep 5

# ------------------------------------------------------------
# Service status
# ------------------------------------------------------------

if systemctl is-active --quiet "$SERVICE_NAME"; then

    STATUS="RUNNING"

else

    STATUS="FAILED"

fi

# ------------------------------------------------------------
# Detect panel port
# ------------------------------------------------------------

DETECTED_PORT=""

for i in {1..10}; do

    DETECTED_PORT="$(
        ss -lntp 2>/dev/null |
        grep -E \
        ':(8080|3000|3001|5000|8000|5173|80)[[:space:]]' |
        sed -n 's/.*:\([0-9]\+\).*/\1/p' |
        head -n 1 || true
    )"

    if [[ -n "$DETECTED_PORT" ]]; then
        break
    fi

    sleep 1

done

if [[ -z "$DETECTED_PORT" ]]; then
    DETECTED_PORT="$DEFAULT_PORT"
fi

# ------------------------------------------------------------
# Detect server IP
# ------------------------------------------------------------

SERVER_IP="$(
    hostname -I 2>/dev/null |
    awk '{print $1}'
)"

if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="YOUR_SERVER_IP"
fi

PANEL_URL="http://${SERVER_IP}:${DETECTED_PORT}"

# ------------------------------------------------------------
# Update credentials with actual URL
# ------------------------------------------------------------

cat > "$CREDENTIAL_FILE" <<EOF
============================================================
                    GKVM PANEL
                 ADMIN CREDENTIALS
============================================================

Username:
$ADMIN_USERNAME

Password:
$ADMIN_PASSWORD

Panel:
$PANEL_URL

Port:
$DETECTED_PORT

Generated:
$(date -Is)

============================================================
IMPORTANT

Keep this file private.
Do not share this password publicly.
============================================================
EOF

chmod 600 "$CREDENTIAL_FILE"

# ------------------------------------------------------------
# Final output
# ------------------------------------------------------------

echo
echo
echo "============================================================"
echo "          GKVM PANEL INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Status       : $STATUS"
echo "Panel URL    : $PANEL_URL"
echo "Install Path : $INSTALL_DIR"
echo "Config       : $ENV_FILE"
echo "Credentials  : $CREDENTIAL_FILE"
echo "Service      : $SERVICE_NAME"
echo
echo "------------------------------------------------------------"
echo "                    ADMIN LOGIN"
echo "------------------------------------------------------------"
echo
echo "Username     : $ADMIN_USERNAME"
echo "Password     : $ADMIN_PASSWORD"
echo
echo "------------------------------------------------------------"
echo "                  IMPORTANT COMMANDS"
echo "------------------------------------------------------------"
echo
echo "Status:"
echo "  systemctl status $SERVICE_NAME"
echo
echo "Restart:"
echo "  systemctl restart $SERVICE_NAME"
echo
echo "Logs:"
echo "  journalctl -u $SERVICE_NAME -f"
echo
echo "Credentials:"
echo "  cat $CREDENTIAL_FILE"
echo
echo "============================================================"

# ------------------------------------------------------------
# Failed startup warning
# ------------------------------------------------------------

if [[ "$STATUS" != "RUNNING" ]]; then

    echo
    echo "[GKVM][WARNING] GKVM did not start successfully."
    echo
    echo "Run:"
    echo
    echo "  journalctl -u $SERVICE_NAME -n 100 --no-pager"
    echo

fi

echo
echo "[GKVM] Installation finished."
echo
