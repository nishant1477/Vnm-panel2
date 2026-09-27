#!/usr/bin/env bash
# ============================================================================
# GKVM PANEL — ULTRA NEXUS TITANIUM EDITION
# Production installer / preflight wrapper for the legacy GKVM/HKVM runtime.
# Build: TX-2026.09.27-0002
# ============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------- Metadata -----------------------------------
GKVM_NAME="GKVM Panel"
GKVM_CODENAME="ULTRA NEXUS"
GKVM_VERSION="TITANIUM EDITION 2026.9"
GKVM_BUILD="TX-2026.09.27-0002"

# IMPORTANT: this pinned legacy installer is intentionally retained. We patch
# only visible branding; internal HKVM variables/paths/services remain intact.
VNM_PANEL_LEGACY_COMMIT="dd9db741e4fac2394a514bae2c0d4ef933e00540"
LEGACY_RAW="https://raw.githubusercontent.com/stripathi02123-tech/Vnm-panel/${VNM_PANEL_LEGACY_COMMIT}/install-direct.sh"

WORK_DIR="/tmp/gkvm-nexus-$$"
LEGACY_RAW_FILE="${WORK_DIR}/install-direct.sh.raw"
LEGACY_PATCHED="${WORK_DIR}/install-direct.sh"

LOG_FILE="/var/log/gkvm-installer.log"
TELEMETRY_FILE="/var/log/gkvm-telemetry.json"
CREDENTIAL_FILE="/root/gkvm-admin.txt"

PANEL_PORT="${PANEL_PORT:-8080}"
GKVM_PANEL_PORT="${GKVM_PANEL_PORT:-${PANEL_PORT}}"

ANIMATION=1
ULTRA_EFFECTS=1
ASCII_MODE=0
QUIET_MODE=0
SKIP_KVM_TEST=0
SKIP_FIREWALL=0
SKIP_BENCHMARK=0
DRY_RUN=0
WIZARD=0
REPAIR_MODE=0
ASSUME_YES=0
THEME="CYBER"

# State
SYSTEMD_AVAILABLE=0
DEPLOY_STATUS=1
FIREWALL_CHANGED=0
FIREWALL_BACKUP=""
ACTUAL_SHA256=""
START_TS="$(date +%s)"
HOSTNAME_SHORT="$(hostname 2>/dev/null || printf 'host')"
STAGE_LOG=()
WARNINGS=()
ERRORS=()

# ------------------------------- ANSI ---------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_PRIMARY=$'\033[38;5;51m'
    C_SECONDARY=$'\033[38;5;141m'
    C_SUCCESS=$'\033[38;5;82m'
    C_WARN=$'\033[38;5;220m'
    C_ERROR=$'\033[38;5;203m'
    C_WHITE=$'\033[38;5;255m'
    C_MUTED=$'\033[38;5;245m'
    C_BLUE=$'\033[38;5;75m'
    C_GREEN=$'\033[38;5;120m'
    C_RED=$'\033[38;5;196m'
    C_PINK=$'\033[38;5;213m'
    C_ORANGE=$'\033[38;5;208m'
    C_ICE=$'\033[38;5;159m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_PRIMARY=''; C_SECONDARY=''; C_SUCCESS=''
    C_WARN=''; C_ERROR=''; C_WHITE=''; C_MUTED=''; C_BLUE=''; C_GREEN=''; C_RED=''
    C_PINK=''; C_ORANGE=''; C_ICE=''
fi

apply_theme() {
    case "${THEME^^}" in
        FIRE)
            C_PRIMARY=$'\033[38;5;196m'; C_SECONDARY=$'\033[38;5;208m'
            C_BLUE=$'\033[38;5;214m'; C_PINK=$'\033[38;5;197m'; C_ICE=$'\033[38;5;220m';;
        ICE)
            C_PRIMARY=$'\033[38;5;87m'; C_SECONDARY=$'\033[38;5;159m'
            C_BLUE=$'\033[38;5;75m'; C_PINK=$'\033[38;5;147m'; C_ICE=$'\033[38;5;231m';;
        MATRIX)
            C_PRIMARY=$'\033[38;5;46m'; C_SECONDARY=$'\033[38;5;118m'
            C_BLUE=$'\033[38;5;40m'; C_PINK=$'\033[38;5;154m'; C_ICE=$'\033[38;5;157m';;
        CYBER|*)
            C_PRIMARY=$'\033[38;5;51m'; C_SECONDARY=$'\033[38;5;141m'
            C_BLUE=$'\033[38;5;75m'; C_PINK=$'\033[38;5;213m'; C_ICE=$'\033[38;5;159m';;
    esac
}
apply_theme

# ------------------------------ Utilities -----------------------------------
mkdir -p "${WORK_DIR}"

cleanup() {
    rm -rf "${WORK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

on_error() {
    local rc=$?
    ERRORS+=("Installer failed at line ${BASH_LINENO[0]} (exit ${rc})")
    printf '%b\n' "${C_ERROR}${C_BOLD}✖ GKVM installer stopped (exit ${rc}).${C_RESET}"
    printf '%b\n' "${C_MUTED}Log: ${LOG_FILE}${C_RESET}"
    exit "${rc}"
}
trap on_error ERR

rotate_log() {
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
    if [[ -f "${LOG_FILE}" ]]; then
        local size
        size="$(stat -c %s "${LOG_FILE}" 2>/dev/null || echo 0)"
        if (( size > 2097152 )); then
            mv -f "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null || true
        fi
    fi
    touch "${LOG_FILE}" 2>/dev/null || true
}
rotate_log

log_raw() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "${LOG_FILE}" 2>/dev/null || true
}

log_info() {
    log_raw "INFO: $*"
    (( QUIET_MODE )) || printf '%b\n' "${C_PRIMARY}◆${C_RESET} $*"
}

log_success() {
    log_raw "SUCCESS: $*"
    (( QUIET_MODE )) || printf '%b\n' "${C_SUCCESS}✔${C_RESET} $*"
}

log_warn() {
    WARNINGS+=("$*")
    log_raw "WARN: $*"
    (( QUIET_MODE )) || printf '%b\n' "${C_WARN}▲${C_RESET} $*"
}

log_error() {
    log_raw "ERROR: $*"
    printf '%b\n' "${C_ERROR}✖${C_RESET} $*" >&2
}

section() {
    local number="$1"
    local title="$2"
    local width="${TERM_WIDTH:-80}"
    local label="[ ${number} ] ${title}"
    local remaining

    (( width < 40 )) && width=40
    if (( ${#label} > width - 4 )); then
        label="${label:0:$((width - 4))}"
    fi
    remaining=$((width - ${#label} - 3))
    (( remaining < 1 )) && remaining=1

    printf '\n'
    printf '%b' "${C_BOLD}${C_PRIMARY}╭─ ${label} "
    printf '─%.0s' $(seq 1 "${remaining}")
    printf '%b\n' "╮${C_RESET}"
    STAGE_LOG+=("${number}:${title}")
}

run_cmd() {
    if (( DRY_RUN )); then
        log_info "DRY-RUN: $*"
        return 0
    fi
    log_raw "EXEC: $*"
    "$@"
}

run_shell() {
    if (( DRY_RUN )); then
        log_info "DRY-RUN: $*"
        return 0
    fi
    log_raw "EXEC-SHELL: $*"
    bash -lc "$*"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

trim() {
    awk '{$1=$1; print}' <<< "$*"
}

need_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Run this installer as root or with sudo."
        exit 1
    fi
}

terminal_probe() {
    TERM_WIDTH="$(tput cols 2>/dev/null || echo 100)"
    TERM_HEIGHT="$(tput lines 2>/dev/null || echo 30)"
    [[ "${TERM_WIDTH}" =~ ^[0-9]+$ ]] || TERM_WIDTH=100
    [[ "${TERM_HEIGHT}" =~ ^[0-9]+$ ]] || TERM_HEIGHT=30
    (( TERM_WIDTH > 160 )) && TERM_WIDTH=160
    (( TERM_WIDTH < 60 )) && TERM_WIDTH=60
    export TERM_WIDTH TERM_HEIGHT
}

spinner() {
    local msg="$1"
    local duration="${2:-1}"
    (( ! ANIMATION || QUIET_MODE )) && { printf '%b\n' "${C_PRIMARY}◆${C_RESET} ${msg}"; return 0; }
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local end=$((SECONDS + duration))
    local i=0
    while (( SECONDS < end )); do
        printf '\r%b' "${C_SECONDARY}${frames[i % ${#frames[@]}]}${C_RESET} ${msg}"
        sleep 0.08
        ((i++))
    done
    printf '\r%b\n' "${C_SUCCESS}✔${C_RESET} ${msg}"
}

bar() {
    local label="$1"
    local pct="$2"
    local width=34
    local fill=$((pct * width / 100))
    local empty=$((width - fill))
    if (( fill < 0 )); then fill=0; fi
    if (( empty < 0 )); then empty=0; fi
    if (( fill > width )); then fill=${width}; fi
    if (( empty > width )); then empty=${width}; fi
    printf '%b' "${C_MUTED}${label} ${C_RESET}"
    printf '%b' "${C_PRIMARY}"
    if (( fill > 0 )); then
        printf '█%.0s' $(seq 1 "${fill}")
    fi
    printf '%b' "${C_MUTED}"
    if (( empty > 0 )); then
        printf '░%.0s' $(seq 1 "${empty}")
    fi
    printf '%b\n' "${C_RESET} ${pct}%"
}

banner() {
    clear 2>/dev/null || true
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}║ ${C_WHITE}GKVM PANEL${C_RESET}${C_PRIMARY}${C_BOLD}  //  ${C_SECONDARY}${GKVM_CODENAME}${C_RESET}${C_PRIMARY}${C_BOLD}  //  ${C_PINK}${GKVM_VERSION}${C_RESET}${C_PRIMARY}${C_BOLD} ║${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}║${C_RESET} Build ${C_WHITE}${GKVM_BUILD}${C_RESET}   Host ${C_WHITE}${HOSTNAME_SHORT}${C_RESET}   Port ${C_WHITE}${PANEL_PORT}${C_RESET} ${C_PRIMARY}${C_BOLD}║${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

cinematic_boot() {
    (( QUIET_MODE )) && return 0
    printf '\n%b\n' "${C_SECONDARY}${C_BOLD}>>> INITIALIZING ULTRA NEXUS CORE...${C_RESET}"
    bar "NEXUS CORE" 100
    bar "SECURITY LAYER" 100
    bar "KVM MATRIX" 100
    bar "DEPLOYMENT ENGINE" 100
    printf '%b\n' "${C_PRIMARY}${C_BOLD}◆ SYSTEM READY ◆${C_RESET}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --theme=*) THEME="${1#*=}"; apply_theme; shift ;;
            --theme) THEME="${2:-CYBER}"; apply_theme; shift 2 ;;
            --port=*) PANEL_PORT="${1#*=}"; shift ;;
            --port) PANEL_PORT="${2:-8080}"; shift 2 ;;
            --skip-kvm-test) SKIP_KVM_TEST=1; shift ;;
            --skip-firewall) SKIP_FIREWALL=1; shift ;;
            --skip-benchmark) SKIP_BENCHMARK=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --wizard) WIZARD=1; shift ;;
            --repair-kvm) REPAIR_MODE=1; shift ;;
            --assume-yes|-y) ASSUME_YES=1; shift ;;
            --quiet) QUIET_MODE=1; shift ;;
            --no-animation) ANIMATION=0; shift ;;
            --ascii) ASCII_MODE=1; shift ;;
            --no-effects) ULTRA_EFFECTS=0; shift ;;
            --help|-h)
                cat <<HELP
${GKVM_NAME} — ${GKVM_CODENAME}

Usage:
  sudo bash install.sh [options]

Options:
  --wizard              Select panel port interactively
  --port PORT           Set panel port (default: 8080)
  --theme THEME         CYBER | FIRE | ICE | MATRIX
  --repair-kvm          Run the manual KVM doctor/repair path
  --skip-kvm-test       Skip functional QEMU/KVM test
  --skip-firewall       Do not modify UFW/firewalld
  --skip-benchmark      Skip KVM vs TCG benchmark
  --dry-run             Show actions without changing the system
  --assume-yes, -y      Accept installer prompts
  --quiet               Reduce live output
  --no-animation        Disable spinner/animation
  --ascii               Prefer ASCII-safe output
  --no-effects          Disable optional visual effects
  --help, -h            Show this help
HELP
                exit 0 ;;
            *)
                log_error "Unknown option: $1"
                exit 2 ;;
        esac
    done

    [[ "${THEME^^}" =~ ^(CYBER|FIRE|ICE|MATRIX)$ ]] || THEME=CYBER
    apply_theme

    if ! [[ "${PANEL_PORT}" =~ ^[0-9]+$ ]] || (( PANEL_PORT < 1 || PANEL_PORT > 65535 )); then
        log_error "Invalid panel port: ${PANEL_PORT}"
        exit 2
    fi
    GKVM_PANEL_PORT="${PANEL_PORT}"
    export PANEL_PORT GKVM_PANEL_PORT
}

wizard() {
    (( WIZARD )) || return 0
    if (( ASSUME_YES )); then
        return 0
    fi
    printf '%b\n' "${C_BOLD}${C_PRIMARY}GKVM CONFIGURATION WIZARD${C_RESET}"
    read -r -p "Panel HTTP port [${PANEL_PORT}]: " answer || true
    [[ -n "${answer}" ]] && PANEL_PORT="${answer}"
    if ! [[ "${PANEL_PORT}" =~ ^[0-9]+$ ]] || (( PANEL_PORT < 1 || PANEL_PORT > 65535 )); then
        die "Invalid panel port selected."
    fi
    GKVM_PANEL_PORT="${PANEL_PORT}"
    export PANEL_PORT GKVM_PANEL_PORT
    printf '%b\n' "${C_SUCCESS}✔${C_RESET} Panel port: ${PANEL_PORT}"
}

die() {
    log_error "$*"
    exit 1
}

# ------------------------------ Host scans ----------------------------------
host_telemetry() {
    section "01" "HOST TELEMETRY"
    local cpu="unknown" threads="?" ram="?" disk="?" arch="?" kernel="?" uptime_s="?"
    cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2; exit}' || true)"
    threads="$(nproc 2>/dev/null || echo '?')"
    ram="$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo '?')"
    disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo '?')"
    arch="$(uname -m 2>/dev/null || echo '?')"
    kernel="$(uname -r 2>/dev/null || echo '?')"
    uptime_s="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo '?')"
    printf '  %bCPU%b       : %s\n' "${C_PRIMARY}" "${C_RESET}" "${cpu:-unknown}"
    printf '  %bThreads%b   : %s\n' "${C_PRIMARY}" "${C_RESET}" "${threads}"
    printf '  %bMemory%b    : %s\n' "${C_PRIMARY}" "${C_RESET}" "${ram}"
    printf '  %bDisk%b      : %s\n' "${C_PRIMARY}" "${C_RESET}" "${disk}"
    printf '  %bArch%b      : %s\n' "${C_PRIMARY}" "${C_RESET}" "${arch}"
    printf '  %bKernel%b    : %s\n' "${C_PRIMARY}" "${C_RESET}" "${kernel}"
    printf '  %bUptime(s)%b : %s\n' "${C_PRIMARY}" "${C_RESET}" "${uptime_s}"
}

network_matrix() {
    section "02" "NETWORK MATRIX"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: network checks simulated"
        return 0
    fi
    if command_exists curl; then
        local ip=""
        ip="$(curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
        printf '  %bPublic IPv4%b : %s\n' "${C_PRIMARY}" "${C_RESET}" "${ip:-unavailable}"
    fi
    if command_exists ip; then
        printf '  %bInterfaces%b   :\n' "${C_PRIMARY}" "${C_RESET}"
        ip -br addr 2>/dev/null | sed 's/^/    /' || true
    fi
    if command_exists curl; then
        local region=""
        region="$(curl -4 -fsS --max-time 4 https://ipinfo.io/json 2>/dev/null | tr '\n' ' ' | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        [[ -n "${region}" ]] && printf '  %bGeo hint%b      : %s\n' "${C_PRIMARY}" "${C_RESET}" "${region}"
    fi
}

install_prerequisites() {
    section "03" "PREREQUISITES"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: prerequisite installation skipped"
        return 0
    fi
    source /etc/os-release 2>/dev/null || true
    local id="${ID:-unknown}"
    case "${id}" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y \
                ca-certificates curl git file lsof procps iproute2 openssl \
                build-essential python3 sqlite3 util-linux \
                cloud-image-utils genisoimage qemu-system-x86 qemu-utils ovmf
            ;;
        *)
            die "Unsupported OS: ${id}. This installer currently targets Ubuntu/Debian."
            ;;
    esac

    command_exists qemu-system-x86_64 || die "qemu-system-x86_64 is not installed"
    command_exists qemu-img || die "qemu-img is not installed"
    command_exists cloud-localds || log_warn "cloud-localds unavailable; VM cloud-init tooling may be limited"
    log_success "Required packages installed"
}

kvm_scan() {
    section "04" "KVM DEEP SCAN"
    local dev="NO" virt="unknown" modules="unknown"
    [[ -e /dev/kvm ]] && dev="YES"
    virt="$(lscpu 2>/dev/null | awk -F: '/Virtualization/ {gsub(/^ +/,"",$2); print $2; exit}' || true)"
    modules="$(lsmod 2>/dev/null | awk '$1 ~ /^kvm(_intel|_amd)?$/ {print $1}' | paste -sd, - || true)"
    printf '  %b/dev/kvm%b       : %s\n' "${C_PRIMARY}" "${C_RESET}" "${dev}"
    printf '  %bVirtualization%b : %s\n' "${C_PRIMARY}" "${C_RESET}" "${virt:-unknown}"
    printf '  %bModules%b       : %s\n' "${C_PRIMARY}" "${C_RESET}" "${modules:-none}"

    if [[ "${dev}" != "YES" ]] && (( REPAIR_MODE )); then
        kvm_doctor
    elif [[ "${dev}" != "YES" ]]; then
        log_warn "/dev/kvm is unavailable. Use --repair-kvm for the manual doctor path."
    else
        log_success "KVM device detected"
    fi
}

kvm_functional_test() {
    section "05" "KVM FUNCTIONAL TEST"
    if (( SKIP_KVM_TEST )); then
        log_warn "Functional test skipped by flag"
        return 0
    fi
    if (( DRY_RUN )); then
        log_info "DRY-RUN: QEMU KVM launch simulated"
        return 0
    fi
    command_exists qemu-system-x86_64 || { log_warn "QEMU unavailable; functional test skipped"; return 0; }
    [[ -e /dev/kvm ]] || { log_warn "No /dev/kvm; functional test skipped"; return 0; }

    set +e
    timeout 6s qemu-system-x86_64 \
        -accel kvm \
        -machine q35 \
        -display none \
        -nodefaults \
        -S >/dev/null 2>&1
    local rc=$?
    set -e

    if (( rc == 0 || rc == 124 )); then
        log_success "QEMU/KVM functional launch accepted"
    else
        log_warn "QEMU/KVM functional launch returned ${rc}"
    fi
}

benchmark_accelerators() {
    section "06" "ACCELERATOR BENCHMARK"
    if (( DRY_RUN || SKIP_BENCHMARK )); then
        log_info "Accelerator benchmark skipped"
        return 0
    fi
    command_exists qemu-system-x86_64 || { log_warn "QEMU unavailable; benchmark skipped"; return 0; }

    local start_kvm end_kvm start_tcg end_tcg
    if [[ -e /dev/kvm ]]; then
        start_kvm="$(date +%s%N)"
        timeout 2s qemu-system-x86_64 -accel kvm -machine q35 -display none -nodefaults -S >/dev/null 2>&1 || true
        end_kvm="$(date +%s%N)"
        local kvm_ms=$(( (end_kvm - start_kvm) / 1000000 ))
        printf '  %bKVM startup probe%b : %s ms\n' "${C_PRIMARY}" "${C_RESET}" "${kvm_ms}"
    else
        log_warn "No /dev/kvm; KVM benchmark unavailable"
    fi

    start_tcg="$(date +%s%N)"
    timeout 2s qemu-system-x86_64 -accel tcg -machine q35 -display none -nodefaults -S >/dev/null 2>&1 || true
    end_tcg="$(date +%s%N)"
    local tcg_ms=$(( (end_tcg - start_tcg) / 1000000 ))
    printf '  %bTCG startup probe%b : %s ms\n' "${C_PRIMARY}" "${C_RESET}" "${tcg_ms}"
}

kvm_doctor() {
    printf '%b\n' "${C_BOLD}${C_WARN}KVM MANUAL REPAIR / DOCTOR MODE${C_RESET}"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: would attempt modprobe kvm and architecture module"
        return 0
    fi

    modprobe kvm 2>/dev/null || true
    if [[ "$(uname -m)" =~ ^(x86_64|amd64)$ ]]; then
        modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
    fi

    cat > /etc/udev/rules.d/99-gkvm-kvm.rules <<'RULE'
KERNEL=="kvm", GROUP="kvm", MODE="0660"
RULE

    if command_exists udevadm; then
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger --name-match=kvm 2>/dev/null || true
    fi

    if [[ -e /dev/kvm ]]; then
        log_success "KVM device available after doctor pass"
    else
        log_warn "KVM is still unavailable; host/hypervisor nested virtualization may be required"
    fi
}

firewall_status() {
    section "07" "FIREWALL MATRIX"
    if (( SKIP_FIREWALL || DRY_RUN )); then
        log_info "Firewall modification skipped"
        return 0
    fi

    if command_exists ufw; then
        FIREWALL_BACKUP="${WORK_DIR}/ufw-status.txt"
        ufw status numbered > "${FIREWALL_BACKUP}" 2>&1 || true
        if [[ "${ASSUME_YES}" == "1" ]]; then
            ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
            FIREWALL_CHANGED=1
            log_success "UFW rule added for TCP ${PANEL_PORT}"
        else
            read -r -p "Allow TCP ${PANEL_PORT} through UFW? [Y/n] " ans || true
            if [[ ! "${ans}" =~ ^[Nn]$ ]]; then
                ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
                FIREWALL_CHANGED=1
                log_success "UFW rule added for TCP ${PANEL_PORT}"
            else
                log_info "UFW change skipped"
            fi
        fi
    elif command_exists firewall-cmd; then
        if [[ "${ASSUME_YES}" == "1" ]]; then
            firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            FIREWALL_CHANGED=1
            log_success "firewalld rule added for TCP ${PANEL_PORT}"
        else
            log_info "firewalld detected; use --assume-yes to automatically open TCP ${PANEL_PORT}"
        fi
    else
        log_info "No supported firewall manager detected"
    fi
}

rollback_firewall() {
    [[ "${FIREWALL_CHANGED}" == "1" ]] || return 0
    log_warn "A firewall change was made during this run. Original state snapshot: ${FIREWALL_BACKUP:-not available}"
}

# ---------------------------- Legacy engine ---------------------------------
download_legacy_installer() {
    section "08" "LEGACY ENGINE DOWNLOAD"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: legacy installer download skipped"
        return 0
    fi

    mkdir -p "${WORK_DIR}"
    log_info "Fetching pinned legacy installer..."
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 10 --max-time 180 \
        -o "${LEGACY_RAW_FILE}" "${LEGACY_RAW}"

    [[ -s "${LEGACY_RAW_FILE}" ]] || die "Downloaded legacy installer is empty"

    local size
    size="$(stat -c %s "${LEGACY_RAW_FILE}" 2>/dev/null || echo 0)"
    (( size >= 1024 )) || die "Downloaded legacy installer is unexpectedly small (${size} bytes)"
    (( size <= 1048576 )) || die "Downloaded legacy installer is unexpectedly large (${size} bytes)"

    bash -n "${LEGACY_RAW_FILE}" || die "Legacy installer syntax validation failed"

    # SAFE BRAND PATCH ONLY.
    # DO NOT globally replace HKVM: internal compatibility identifiers are
    # intentionally preserved for the existing runtime/service layout.
    sed \
      -e 's/^PANEL_NAME=HKVM$/PANEL_NAME="GKVM"/' \
      -e 's/^PANEL_NAME="HKVM"$/PANEL_NAME="GKVM"/' \
      -e 's/HKVM PANEL V3/GKVM PANEL V3/g' \
      -e 's/HKVM V5/GKVM V5/g' \
      -e 's/HKVM Panel/GKVM Panel/g' \
      -e 's/HKVM PANEL/GKVM PANEL/g' \
      "${LEGACY_RAW_FILE}" > "${LEGACY_PATCHED}"

    bash -n "${LEGACY_PATCHED}" || die "Patched legacy installer syntax validation failed"

    ACTUAL_SHA256="$(sha256sum "${LEGACY_PATCHED}" | awk '{print $1}')"
    if [[ -n "${LEGACY_SHA256:-}" ]]; then
        [[ "${ACTUAL_SHA256}" == "${LEGACY_SHA256}" ]] || die "SHA256 verification failed"
        log_success "Legacy installer SHA256 verified"
    else
        log_info "Legacy installer SHA256 observed: ${ACTUAL_SHA256}"
    fi

    chmod 700 "${LEGACY_PATCHED}"
    log_success "Pinned legacy installer prepared"
}

patch_legacy_port() {
    # The legacy installer is deliberately treated as opaque except for the
    # documented branding patch. We export port variables so installers that
    # support them can consume the selected port without rewriting internals.
    export PANEL_PORT GKVM_PANEL_PORT
    log_info "Exported PANEL_PORT=${PANEL_PORT} and GKVM_PANEL_PORT=${GKVM_PANEL_PORT}"
}

deploy_legacy() {
    section "09" "GKVM CORE DEPLOYMENT"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: legacy deployment skipped"
        DEPLOY_STATUS=0
        return 0
    fi

    patch_legacy_port
    chmod +x "${LEGACY_PATCHED}"

    log_info "Launching pinned legacy deployment engine..."
    set +e
    env \
        PANEL_PORT="${PANEL_PORT}" \
        GKVM_PANEL_PORT="${GKVM_PANEL_PORT}" \
        GKVM_NAME="${GKVM_NAME}" \
        bash "${LEGACY_PATCHED}" 2>&1 | tee -a "${LOG_FILE}"
    local child_rc=${PIPESTATUS[0]}
    set -e

    if (( child_rc != 0 )); then
        DEPLOY_STATUS="${child_rc}"
        die "Legacy deployment failed with exit code ${child_rc}"
    fi

    DEPLOY_STATUS=0
    log_success "Legacy deployment completed"
}

# ----------------------- Application discovery ------------------------------
wait_for_database() {
    local max_wait=25
    local i=0
    while (( i < max_wait )); do
        [[ -f /root/.vnm/vnm.db ]] && return 0
        i=$((i + 1))
        sleep 1
    done
    return 1
}

find_gkvm_database() {
    local candidates=(
        "/root/.vnm/vnm.db"
        "/opt/hkvm/app/vnm.db"
        "/opt/hkvm/vnm.db"
        "/opt/gkvm/app/vnm.db"
        "/opt/gkvm/vnm.db"
    )
    local item
    for item in "${candidates[@]}"; do
        if [[ -f "${item}" ]]; then
            printf '%s\n' "${item}"
            return 0
        fi
    done

    find /root /opt -type f -name 'vnm.db' 2>/dev/null | head -n 1
}

find_node_app_root() {
    local roots=(
        "/opt/hkvm/app"
        "/opt/gkvm/app"
        "/opt/hkvm"
        "/opt/gkvm"
    )
    local root
    for root in "${roots[@]}"; do
        if [[ -f "${root}/package.json" ]] && [[ -d "${root}/node_modules" ]]; then
            printf '%s\n' "${root}"
            return 0
        fi
    done

    find /opt /root -type f -name package.json -path '*/node_modules/../package.json' 2>/dev/null | head -n1 | xargs -r dirname
}

sync_gkvm_admin_credentials() {
    section "10" "ADMIN CREDENTIAL SYNCHRONIZATION"
    if (( DRY_RUN )); then
        log_info "DRY-RUN: SQLite/bcrypt administrator sync skipped"
        return 0
    fi

    local db_path app_root node_bin
    db_path="$(find_gkvm_database || true)"

    if [[ -z "${db_path}" || ! -f "${db_path}" ]]; then
        log_warn "GKVM database not found; admin synchronization skipped"
        return 0
    fi

    node_bin="$(command -v node || true)"
    if [[ -z "${node_bin}" ]]; then
        log_warn "Node.js not found; admin synchronization skipped"
        return 0
    fi

    app_root="$(find_node_app_root || true)"
    if [[ -z "${app_root}" ]]; then
        log_warn "GKVM Node application root not located; admin synchronization skipped"
        return 0
    fi

    if [[ ! -d "${app_root}/node_modules/bcryptjs" || ! -d "${app_root}/node_modules/sqlite3" ]]; then
        log_warn "bcryptjs/sqlite3 modules not found under ${app_root}; admin synchronization skipped"
        return 0
    fi

    local admin_password
    admin_password="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9@#%+=_' | head -c 20)"
    [[ -n "${admin_password}" ]] || admin_password="GKVM-Admin-$(date +%s)-$(printf '%04d' "$((RANDOM % 10000))")"

    local result
    if ! result="$(
        cd "${app_root}"
        GKVM_DB_PATH="${db_path}" GKVM_ADMIN_PASSWORD="${admin_password}" "${node_bin}" <<'NODE'
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');

const dbPath = process.env.GKVM_DB_PATH;
const password = process.env.GKVM_ADMIN_PASSWORD;

if (!dbPath || !password) process.exit(2);

const db = new sqlite3.Database(dbPath, err => {
  if (err) {
    console.error(err.message);
    process.exit(1);
  }

  const hash = bcrypt.hashSync(password, 10);

  db.run(
    `UPDATE users SET password = ?, is_active = 1, role = 'admin' WHERE username = 'admin'`,
    [hash],
    function(err) {
      if (err) {
        console.error(err.message);
        db.close();
        process.exit(1);
      }

      if (this.changes > 0) {
        console.log('ADMIN_UPDATED');
        db.close();
        return;
      }

      db.run(
        `INSERT INTO users (username, password, email, role, is_active)
         VALUES (?, ?, ?, 'admin', 1)`,
        ['admin', hash, 'admin@gkvm.local'],
        function(err2) {
          if (err2) {
            console.error(err2.message);
            db.close();
            process.exit(1);
          }
          console.log('ADMIN_CREATED');
          db.close();
        }
      );
    }
  );
});
NODE
    )"; then
        log_warn "Could not synchronize GKVM administrator credentials"
        return 0
    fi

    cat > "${CREDENTIAL_FILE}" <<CREDS
GKVM PANEL — ADMIN CREDENTIALS
================================
URL: http://<SERVER-IP>:${PANEL_PORT}
Username: admin
Password: ${admin_password}
Database: ${db_path}
Account role: admin
Generated: $(date -Is)
Build: ${GKVM_BUILD}
================================
Keep this file private.
CREDS
    chmod 600 "${CREDENTIAL_FILE}"

    printf '%b\n' "${C_SUCCESS}${C_BOLD}╭────────────────────────────────────────────────────────────╮${C_RESET}"
    printf '%b\n' "${C_SUCCESS}${C_BOLD}│                 GKVM ADMIN LOGIN READY                   │${C_RESET}"
    printf '%b\n' "${C_SUCCESS}${C_BOLD}├────────────────────────────────────────────────────────────┤${C_RESET}"
    printf '%b\n' "${C_RESET}│ Username : ${C_WHITE}admin${C_RESET}"
    printf '%b\n' "${C_RESET}│ Password : ${C_WHITE}${admin_password}${C_RESET}"
    printf '%b\n' "${C_RESET}│ DB       : ${C_WHITE}${db_path}${C_RESET}"
    printf '%b\n' "${C_RESET}│ Saved to : ${C_WHITE}${CREDENTIAL_FILE}${C_RESET}"
    printf '%b\n' "${C_SUCCESS}${C_BOLD}╰────────────────────────────────────────────────────────────╯${C_RESET}"
    log_success "Administrator credential sync result: ${result}"
}

panel_health() {
    section "11" "PANEL HEALTH CHECK"
    local ok=0

    if command -v systemctl >/dev/null 2>&1 && [[ "${SYSTEMD_AVAILABLE}" == "1" ]]; then
        if systemctl is-active --quiet hkvm.service 2>/dev/null; then
            log_success "HKVM-compatible service is active"
            ok=1
        fi
    fi

    if (( ! ok )) && command_exists curl; then
        local code="000"
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${PANEL_PORT}/" 2>/dev/null || true)"
        if [[ "${code}" =~ ^(2|3)[0-9][0-9]$ || "${code}" == "401" || "${code}" == "403" ]]; then
            log_success "GKVM HTTP endpoint responding (${code})"
            ok=1
        else
            log_warn "Panel HTTP check returned ${code}"
        fi
    fi

    if (( ! ok )); then
        log_warn "Panel health could not be conclusively confirmed"
        return 1
    fi
    return 0
}

# ------------------------------- Telemetry ----------------------------------
json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g' <<< "$1" | tr -d '\n'
}

telemetry_json_stages() {
    local out=""
    local item
    for item in "${STAGE_LOG[@]}"; do
        item="${item//\\/\\\\}"
        item="${item//\"/\\\"}"
        out+="\"${item}\",";
    done
    printf '%s' "${out%,}"
}

write_telemetry() {
    section "12" "TELEMETRY EXPORT"
    local end_ts duration host_json warning_json error_json
    end_ts="$(date +%s)"
    duration=$((end_ts - START_TS))

    host_json="$(json_escape "${HOSTNAME_SHORT}")"
    warning_json=""
    local w
    for w in "${WARNINGS[@]}"; do
        warning_json+="\"$(json_escape "${w}")\",";
    done
    warning_json="${warning_json%,}"

    error_json=""
    local e
    for e in "${ERRORS[@]}"; do
        error_json+="\"$(json_escape "${e}")\",";
    done
    error_json="${error_json%,}"

    cat > "${TELEMETRY_FILE}" <<JSON
{
  "product": "$(json_escape "${GKVM_NAME}")",
  "codename": "$(json_escape "${GKVM_CODENAME}")",
  "version": "$(json_escape "${GKVM_VERSION}")",
  "build": "$(json_escape "${GKVM_BUILD}")",
  "hostname": "${host_json}",
  "theme": "$(json_escape "${THEME}")",
  "panel_port": ${PANEL_PORT},
  "deploy_status": ${DEPLOY_STATUS},
  "dry_run": ${DRY_RUN},
  "duration_seconds": ${duration},
  "legacy_installer_sha256": "${ACTUAL_SHA256}",
  "stages": [$(telemetry_json_stages)],
  "warnings": [${warning_json}],
  "errors": [${error_json}],
  "timestamp": "$(date -Is)"
}
JSON
    chmod 600 "${TELEMETRY_FILE}" 2>/dev/null || true
    log_success "Telemetry written to ${TELEMETRY_FILE}"
}

final_screen() {
    section "13" "ULTRA NEXUS FINALIZATION"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}║                    GKVM INSTALL COMPLETE                          ║${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╠══════════════════════════════════════════════════════════════════════╣${C_RESET}"
    printf '%b\n' "${C_RESET}║ Panel       : ${C_WHITE}http://<SERVER-IP>:${PANEL_PORT}${C_RESET}"
    printf '%b\n' "${C_RESET}║ Build       : ${C_WHITE}${GKVM_BUILD}${C_RESET}"
    printf '%b\n' "${C_RESET}║ Theme       : ${C_WHITE}${THEME}${C_RESET}"
    printf '%b\n' "${C_RESET}║ Credentials : ${C_WHITE}${CREDENTIAL_FILE}${C_RESET}"
    printf '%b\n' "${C_RESET}║ Installer log: ${C_WHITE}${LOG_FILE}${C_RESET}"
    printf '%b\n' "${C_RESET}║ Telemetry   : ${C_WHITE}${TELEMETRY_FILE}${C_RESET}"
    printf '%b\n' "${C_PRIMARY}${C_BOLD}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"

    if (( ${#WARNINGS[@]} > 0 )); then
        printf '%b\n' "${C_WARN}${C_BOLD}Warnings:${C_RESET}"
        local w
        for w in "${WARNINGS[@]}"; do
            printf '  %b•%b %s\n' "${C_WARN}" "${C_RESET}" "${w}"
        done
    fi

    printf '%b\n' "${C_SUCCESS}${C_BOLD}◆ GKVM ULTRA NEXUS IS READY ◆${C_RESET}"
}

# ------------------------------- Main ---------------------------------------
main() {
    parse_args "$@"
    need_root
    terminal_probe
    banner
    cinematic_boot
    wizard

    if command -v systemctl >/dev/null 2>&1 && [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" == "systemd" ]]; then
        SYSTEMD_AVAILABLE=1
    fi

    host_telemetry
    network_matrix
    install_prerequisites
    kvm_scan
    kvm_functional_test
    benchmark_accelerators
    firewall_status
    download_legacy_installer
    deploy_legacy
    sync_gkvm_admin_credentials
    panel_health || true
    rollback_firewall
    write_telemetry
    final_screen
}

main "$@"
