#!/usr/bin/env bash
# =============================================================================
# GKVM PANEL — BLAZING ULTRA EDITION
# Premium terminal bootstrapper for the existing VNM/HKVM direct-install flow.
#
# Runtime/deployment logic intentionally remains the same:
#   • existing pinned legacy installer
#   • existing HKVM_INSTALL_DIR / HKVM_APP_DIR contracts
#   • /opt/hkvm
#   • hkvm.service
#   • QEMU/KVM preparation and checks
#
# UI layer upgraded with:
#   • beveled pseudo-3D cards
#   • multi-stop truecolor gradients
#   • neon depth/shadow effects
#   • holographic scanlines
#   • animated particle field
#   • plasma/fire effects
#   • animated progress core
#   • perspective terminal banners
# =============================================================================

set -Eeuo pipefail

readonly GKVM_NAME="GKVM Panel"
readonly GKVM_VERSION="ULTRA EDITION 2026"
readonly LEGACY_COMMIT="dd9db741e4fac2394a514bae2c0d4ef933e00540"
readonly LEGACY_URL="https://raw.githubusercontent.com/stripathi02123-tech/Vnm-panel/${LEGACY_COMMIT}/install-direct.sh"
readonly WORK_ROOT="/tmp/gkvm-installer-$$"
readonly LEGACY_RAW="${WORK_ROOT}/legacy-install.sh"
readonly LEGACY_PATCHED="${WORK_ROOT}/gkvm-install.sh"
readonly KVM_TEST_LOG="${WORK_ROOT}/kvm-test.log"
readonly CHILD_LOG="${WORK_ROOT}/child-installer.log"
readonly INSTALLER_LOG="/var/log/gkvm-installer.log"
readonly PANEL_PORT="8080"

VNM_PANEL_PREREQS_DONE="${VNM_PANEL_PREREQS_DONE:-false}"
ANIMATION="true"
ULTRA_EFFECTS="true"
QUIET_MODE="false"
SKIP_KVM_TEST="false"
SKIP_FIREWALL="false"
KVM_AVAILABLE="false"
KVM_READWRITE="false"
KVM_TEST="NOT_RUN"
QEMU_INSTALLED="false"
SYSTEMD_AVAILABLE="false"
INTERNET_AVAILABLE="false"
CHILD_EXIT_CODE="0"
START_TIME="$(date +%s)"

# =============================================================================
# ANSI / TRUECOLOR ENGINE
# =============================================================================

ESC=$'\033'
RESET="${ESC}[0m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"; ITALIC="${ESC}[3m"; UNDERLINE="${ESC}[4m"
BLACK="${ESC}[30m"; RED="${ESC}[31m"; GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"; BLUE="${ESC}[34m"; MAGENTA="${ESC}[35m"; CYAN="${ESC}[36m"; WHITE="${ESC}[37m"
BRIGHT_BLACK="${ESC}[90m"; BRIGHT_RED="${ESC}[91m"; BRIGHT_GREEN="${ESC}[92m"; BRIGHT_YELLOW="${ESC}[93m"; BRIGHT_BLUE="${ESC}[94m"; BRIGHT_MAGENTA="${ESC}[95m"; BRIGHT_CYAN="${ESC}[96m"; BRIGHT_WHITE="${ESC}[97m"
PINK="${ESC}[38;5;213m"; HOT_PINK="${ESC}[38;5;205m"; PURPLE="${ESC}[38;5;141m"; VIOLET="${ESC}[38;5;135m"; DEEP_PURPLE="${ESC}[38;5;93m"
ICE="${ESC}[38;5;159m"; SKY="${ESC}[38;5;117m"; AQUA="${ESC}[38;5;87m"; LIME="${ESC}[38;5;118m"; MINT="${ESC}[38;5;121m"
GOLD="${ESC}[38;5;220m"; ORANGE="${ESC}[38;5;208m"; FIRE="${ESC}[38;5;202m"; FLAME="${ESC}[38;5;196m"

rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
bgr() { printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3"; }

TERM_WIDTH="$(tput cols 2>/dev/null || echo 88)"
(( TERM_WIDTH < 72 )) && TERM_WIDTH=72

if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
  ANIMATION="false"
  ULTRA_EFFECTS="false"
fi
[[ "${CI:-false}" == "true" ]] && ULTRA_EFFECTS="false"

mkdir -p "${WORK_ROOT}"
touch "${INSTALLER_LOG}" 2>/dev/null || true
exec > >(tee -a "${INSTALLER_LOG}") 2>&1

# =============================================================================
# TERMINAL STATE / CLEANUP
# =============================================================================

hide_cursor() { [[ "${ANIMATION}" == "true" ]] && printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
clear_screen() { clear 2>/dev/null || printf '\033[2J\033[H'; }
move_home() { printf '\033[H'; }
clear_line() { printf '\r\033[2K'; }
reset_terminal() { printf '%b' "${RESET}\033[0m\033[?25h"; }

cleanup() {
  reset_terminal
  rm -rf "${WORK_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT

on_error() {
  local rc=$?
  reset_terminal
  echo
  printf '%b\n' "${BRIGHT_RED}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  printf '%b\n' "${BRIGHT_RED}${BOLD}║                       GKVM INSTALLER ERROR                          ║${RESET}"
  printf '%b\n' "${BRIGHT_RED}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  printf '  %b Exit Code : %s\n' "${BRIGHT_RED}✖${RESET}" "${rc}"
  printf '  %b Log File  : %s\n' "${BRIGHT_CYAN}◆${RESET}" "${INSTALLER_LOG}"
  [[ -f "${CHILD_LOG}" ]] && { echo; printf '%b\n' "${BRIGHT_YELLOW}${BOLD}Last installer output:${RESET}"; tail -n 100 "${CHILD_LOG}" || true; }
  [[ -f "${KVM_TEST_LOG}" ]] && { echo; printf '%b\n' "${BRIGHT_YELLOW}${BOLD}KVM diagnostics:${RESET}"; tail -n 40 "${KVM_TEST_LOG}" || true; }
  exit "${rc}"
}
trap on_error ERR

# =============================================================================
# BASIC HELPERS
# =============================================================================

die() { failure "$*"; return 1; }
info() { printf '  %b %s\n' "${BRIGHT_CYAN}◆${RESET}" "$*"; }
success() { printf '  %b %s\n' "${BRIGHT_GREEN}✔${RESET}" "$*"; }
warning() { printf '  %b %s\n' "${BRIGHT_YELLOW}⚠${RESET}" "$*"; }
failure() { printf '  %b %s\n' "${BRIGHT_RED}✖${RESET}" "$*" >&2; }
muted() { printf '  %b\n' "${DIM}$*${RESET}"; }
divider() { printf '%b\n' "${DIM}${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
thin_divider() { printf '%b\n' "${DIM}${CYAN}──────────────────────────────────────────────────────────────────────${RESET}"; }

label() {
  local key="$1" value="$2" color="${3:-${WHITE}}"
  printf '  %b%-25s%b %b%s%b\n' "${DIM}" "${key}" "${RESET}" "${color}" "${value}" "${RESET}"
}

# =============================================================================
# GRADIENT / PSEUDO-3D UI ENGINE
# =============================================================================

hex_to_rgb() {
  local h="${1#\#}"
  printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

gradient_text() {
  local text="$1" start="${2:-#59F3FF}" end="${3:-#D85BFF}"
  local -a a b
  read -r -a a <<< "$(hex_to_rgb "${start}")"
  read -r -a b <<< "$(hex_to_rgb "${end}")"
  local len=${#text}
  (( len < 1 )) && { echo; return; }
  local denom=$(( len > 1 ? len - 1 : 1 ))
  local i t r g bl
  for ((i=0; i<len; i++)); do
    t=$(( i * 1000 / denom ))
    r=$(( a[0] + (b[0]-a[0]) * t / 1000 ))
    g=$(( a[1] + (b[1]-a[1]) * t / 1000 ))
    bl=$(( a[2] + (b[2]-a[2]) * t / 1000 ))
    printf '%b%s%b' "$(rgb "$r" "$g" "$bl")" "${text:i:1}" "${RESET}"
  done
  echo
}

gradient_line() { gradient_text "$1" "#45F3FF" "#FF4FD8"; }

side_shadow() { printf '%b' "${DEEP_PURPLE}▐${RESET}"; }

bevel_box() {
  local title="$1" value="$2" color="$3" desc="${4:-}" width=66
  local inner=$((width-4))
  local title_line="◆ ${title}"
  local value_line="${value}"
  local pad=$(( inner - ${#title_line} )); (( pad < 1 )) && pad=1
  echo
  printf '  %b╭──────────────────────────────────────────────────────────────────╮%b\n' "${VIOLET}" "${RESET}"
  printf '  %b│ %b%s%b%*s%b│%b\n' "${VIOLET}" "${WHITE}${BOLD}" "${title_line}" "${RESET}" "$pad" "" "${VIOLET}" "${RESET}"
  printf '  %b│ %b┌────────────────────────────────────────────────────────────┐%b│%b\n' "${VIOLET}" "${PURPLE}" "${RESET}" "${VIOLET}"
  printf '  %b│ %b│ %b%-58s%b %b│%b│%b\n' "${VIOLET}" "${PURPLE}" "${color}${BOLD}" "${value_line:0:58}" "${RESET}" "${PURPLE}" "${VIOLET}" "${RESET}"
  if [[ -n "${desc}" ]]; then
    local wrapped="${desc:0:58}"
    printf '  %b│ %b│ %b%-58s%b %b│%b│%b\n' "${VIOLET}" "${PURPLE}" "${DIM}" "${wrapped}" "${RESET}" "${PURPLE}" "${VIOLET}" "${RESET}"
  fi
  printf '  %b│ %b└────────────────────────────────────────────────────────────┘%b│%b\n' "${VIOLET}" "${PURPLE}" "${RESET}" "${VIOLET}"
  printf '  %b╰──────────────────────────────────────────────────────────────────╯%b\n' "${VIOLET}" "${RESET}"
}

card() {
  local title="$1" status="$2" color="$3" description="${4:-}"
  bevel_box "${title}" "${status}" "${color}" "${description}"
}

section() {
  local number="$1" title="$2" subtitle="$3"
  echo
  printf '%b╭────────────────────────────────────────────────────────────────────────╮%b\n' "${PURPLE}" "${RESET}"
  printf '%b│ %b%s%b  %b%-54s%b│%b\n' "${PURPLE}" "${ICE}${BOLD}" "${number}" "${RESET}" "${WHITE}${BOLD}" "${title}" "${RESET}" "${PURPLE}"
  printf '%b│ %b%-68s%b│%b\n' "${PURPLE}" "${DIM}" "${subtitle:0:68}" "${RESET}" "${PURPLE}"
  printf '%b╰────────────────────────────────────────────────────────────────────────╯%b\n' "${PURPLE}" "${RESET}"
  echo
}

holo_scan() {
  [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0
  local width=58
  local i
  for ((i=0; i<width; i+=2)); do
    printf '\r  %b%s%b' "${AQUA}" "$(printf '%*s' "$i" '' | tr ' ' '·')" "${RESET}"
    sleep 0.006
  done
  clear_line
}

particle_burst() {
  [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0
  local -a p=("✦" "✧" "◆" "◇" "⬢" "⬡" "•" "·")
  local -a c=("${BRIGHT_CYAN}" "${ICE}" "${PURPLE}" "${PINK}" "${GOLD}" "${BRIGHT_GREEN}" "${BRIGHT_YELLOW}" "${WHITE}")
  local i idx
  for ((i=0; i<32; i++)); do
    idx=$((i % ${#p[@]}))
    printf '\r  %b%s %b%s%b %b%s%b %b%s%b' "${c[$idx]}" "${p[$idx]}" "${c[$((idx+2)%8)]}" "${p[$((idx+2)%8)]}" "${RESET}" "${c[$((idx+4)%8)]}" "${p[$((idx+4)%8)]}" "${RESET}" "${DIM}" "GKVM POWER MATRIX${RESET}"
    sleep 0.025
  done
  clear_line
}

fire_animation() {
  [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0
  local -a flames=("${FLAME}🔥${RESET}" "${FIRE}🔥${RESET}" "${ORANGE}🔥${RESET}" "${GOLD}🔥${RESET}" "${BRIGHT_YELLOW}🔥${RESET}" "${GOLD}🔥${RESET}" "${ORANGE}🔥${RESET}" "${FIRE}🔥${RESET}")
  local f
  for f in "${flames[@]}"; do
    printf '\r  %b %bGKVM POWER CORE STARTING...%b' "${f}" "${BRIGHT_WHITE}${BOLD}" "${RESET}"
    sleep 0.045
  done
  clear_line
}

spark_animation() {
  [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0
  local -a seq=("✦" "✧" "◆" "◇" "⬢" "⬡" "⚡" "✦")
  local -a colors=("${BRIGHT_CYAN}" "${ICE}" "${BRIGHT_MAGENTA}" "${PINK}" "${PURPLE}" "${GOLD}" "${BRIGHT_YELLOW}" "${BRIGHT_GREEN}")
  local i idx
  for ((i=0; i<24; i++)); do
    idx=$((i % ${#seq[@]}))
    printf '\r  %b%b%s%b %bGKVM holographic matrix%b' "${colors[$idx]}" "${BOLD}" "${seq[$idx]}" "${RESET}" "${DIM}" "${RESET}"
    sleep 0.022
  done
  clear_line
}

plasma_bar() {
  local current="$1" total="$2" text="$3" width=48
  (( total < 1 )) && total=1
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local fill="" blank=""
  (( filled > 0 )) && fill="$(printf '%*s' "$filled" '' | tr ' ' '█')"
  (( empty > 0 )) && blank="$(printf '%*s' "$empty" '' | tr ' ' '░')"
  local pct=$(( current * 100 / total ))
  local colors=("${BRIGHT_CYAN}" "${AQUA}" "${ICE}" "${PURPLE}" "${PINK}" "${GOLD}")
  local shown="${fill}${blank}"
  local out=""
  local i ch idx
  for ((i=0; i<${#shown}; i++)); do
    ch="${shown:i:1}"; idx=$((i % ${#colors[@]})); out+="${colors[$idx]}${ch}"
  done
  printf '\r  %b[%s%b] %b%3d%%%b %s%b' "${BRIGHT_CYAN}" "${out}" "${RESET}" "${GOLD}${BOLD}" "${pct}" "${RESET}" "${WHITE}" "${text}${RESET}"
  (( current == total )) && echo
}

# Keep original helper name as a compatibility alias.
energy_bar() { plasma_bar "$@"; }

run_effect() {
  local text="$1"; shift
  if [[ "${ANIMATION}" != "true" ]]; then
    info "${text}..."
    "$@"
    success "${text}"
    return
  fi
  local -a frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  "$@" >>"${INSTALLER_LOG}" 2>&1 &
  local pid=$! i=0 c
  while kill -0 "${pid}" >/dev/null 2>&1; do
    case $((i % 8)) in
      0) c="${BRIGHT_CYAN}";; 1) c="${ICE}";; 2) c="${PURPLE}";; 3) c="${PINK}";;
      4) c="${BRIGHT_MAGENTA}";; 5) c="${GOLD}";; 6) c="${BRIGHT_GREEN}";; *) c="${BRIGHT_YELLOW}";;
    esac
    printf '\r  %b%b%s%b %b%-58s%b' "${c}" "${BOLD}" "${frames[$((i % ${#frames[@]}))]}" "${RESET}" "${WHITE}" "${text}" "${RESET}"
    i=$((i+1))
    sleep 0.055
  done
  if wait "${pid}"; then
    printf '\r  %b%b✔%b %b%-58s%b\n' "${BRIGHT_GREEN}" "${BOLD}" "${RESET}" "${BRIGHT_GREEN}" "${text}" "${RESET}"
  else
    printf '\r  %b%b✖%b %b%-58s%b\n' "${BRIGHT_RED}" "${BOLD}" "${RESET}" "${BRIGHT_RED}" "${text}" "${RESET}"
    return 1
  fi
}

# =============================================================================
# LOGO / BOOT
# =============================================================================

draw_logo() {
  clear_screen
  hide_cursor
  echo
  printf '%b╔════════════════════════════════════════════════════════════════════════════╗%b\n' "${VIOLET}${BOLD}" "${RESET}"
  printf '%b║%b                                                                            %b║%b\n' "${VIOLET}" "${RESET}" "${VIOLET}" "${RESET}"
  gradient_text "               ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗" "#41EFFF" "#FF4FD8"
  gradient_text "              ██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║" "#45D7FF" "#C45DFF"
  gradient_text "              ██║  ███╗█████╔╝ ██║   ██║██╔████╔██║" "#4BFFF0" "#FF5A9F"
  gradient_text "              ██║   ██║██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║" "#5FD4FF" "#B15CFF"
  gradient_text "              ╚██████╔╝██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║" "#47E7FF" "#FF68D5"
  printf '%b║%b                                                                            %b║%b\n' "${VIOLET}" "${RESET}" "${VIOLET}" "${RESET}"
  printf '%b║%b                    %bG K V M   P A N E L%b                             %b║%b\n' "${VIOLET}" "${RESET}" "${WHITE}${BOLD}" "${RESET}" "${VIOLET}" "${RESET}"
  printf '%b║%b                       %b3D N E O N   C O R E%b                          %b║%b\n' "${VIOLET}" "${RESET}" "${ICE}${BOLD}" "${RESET}" "${VIOLET}" "${RESET}"
  printf '%b║%b                                                                            %b║%b\n' "${VIOLET}" "${RESET}" "${VIOLET}" "${RESET}"
  printf '%b╚════════════════════════════════════════════════════════════════════════════╝%b\n' "${VIOLET}${BOLD}" "${RESET}"
  echo
  gradient_line "                         PREMIUM HOST BOOTSTRAP"
  echo
  printf '        %b🔥%b %bQEMU%b   ×   %bKVM%b   ×   %bOVMF%b   ×   %bCloud Images%b   ×   %bVM Control%b\n' "${FLAME}" "${RESET}" "${FIRE}" "${RESET}" "${GOLD}" "${RESET}" "${BRIGHT_CYAN}" "${RESET}" "${PURPLE}" "${RESET}" "${PINK}" "${RESET}"
  printf '                             %b◈  HOLOGRAPHIC HOST CORE  ◈%b\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"
  echo
  fire_animation
  spark_animation
  holo_scan
  particle_burst
  divider
}

# =============================================================================
# OPTIONS
# =============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-animation) ANIMATION="false"; ULTRA_EFFECTS="false";;
      --fast) ANIMATION="false"; ULTRA_EFFECTS="false";;
      --skip-kvm-test) SKIP_KVM_TEST="true";;
      --skip-firewall) SKIP_FIREWALL="true";;
      --quiet) QUIET_MODE="true"; ANIMATION="false"; ULTRA_EFFECTS="false";;
      --version) echo "${GKVM_NAME} ${GKVM_VERSION}"; exit 0;;
      --help)
        cat <<'HELP'

GKVM Panel Ultra Installer

Usage:
  install.sh
  install.sh --no-animation
  install.sh --fast
  install.sh --skip-kvm-test
  install.sh --skip-firewall
  install.sh --quiet
  install.sh --version

Options:
  --no-animation     Disable animated terminal effects.
  --fast             Run without visual effects.
  --skip-kvm-test    Skip the QEMU/KVM functional test.
  --skip-firewall    Do not modify UFW/firewalld.
  --quiet            Minimal terminal output.
  --version          Show installer version.
  --help             Show this help.

HELP
        exit 0
        ;;
      *) warning "Unknown option ignored: $1";;
    esac
    shift
  done
}

# =============================================================================
# HOST TELEMETRY
# =============================================================================

detect_host_metrics() {
  section "00 / 08" "HOST TELEMETRY" "Collecting system information for the deployment dashboard."
  local cpu ram disk uptime model
  cpu="$(nproc 2>/dev/null || echo '?')"
  ram="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo '?')"
  disk="$(df -h / 2>/dev/null | awk 'NR==2 {print $4 " free / " $2}' || echo '?')"
  uptime="$(uptime -p 2>/dev/null || echo 'unknown')"
  label "CPU Threads" "${cpu}" "${BRIGHT_CYAN}"
  label "Memory" "${ram}" "${PURPLE}"
  label "Root Storage" "${disk}" "${GOLD}"
  label "Uptime" "${uptime}" "${PINK}"
  if [[ -r /proc/cpuinfo ]]; then
    model="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
    [[ -n "${model}" ]] && label "CPU Model" "${model}" "${ICE}"
  fi
  card "Host telemetry" "COLLECTED" "${BRIGHT_CYAN}" "System resources captured before virtualization setup."
}

# =============================================================================
# PREREQUISITES
# =============================================================================

install_vnm_panel_prerequisites() {
  [[ "${VNM_PANEL_PREREQS_DONE}" == "true" ]] && { info "VNM Panel host prerequisites were already prepared by the parent installer."; return 0; }
  [[ -f /etc/os-release ]] || die "Unable to detect operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in ubuntu|debian) ;; *) die "Automatic host preparation supports Ubuntu/Debian only.";; esac
  command -v apt-get >/dev/null 2>&1 || die "apt-get is required."
  export DEBIAN_FRONTEND=noninteractive

  section "01 / 08" "HOST FOUNDATION" "Installing virtualization prerequisites."
  run_effect "Refreshing package database" apt-get update -y
  energy_bar 1 6 "APT package database"
  run_effect "Installing bootstrap utilities" apt-get install -y ca-certificates curl git file lsof procps iproute2 openssl build-essential python3 sqlite3 util-linux
  energy_bar 2 6 "System utilities"
  run_effect "Installing cloud-image tooling" apt-get install -y cloud-image-utils
  energy_bar 3 6 "Cloud image support"
  run_effect "Installing ISO generation tooling" apt-get install -y genisoimage
  energy_bar 4 6 "ISO generation"
  run_effect "Installing QEMU virtualization engine" apt-get install -y qemu-system-x86 qemu-utils
  QEMU_INSTALLED="true"
  energy_bar 5 6 "QEMU engine"
  run_effect "Installing OVMF UEFI firmware" apt-get install -y ovmf
  energy_bar 6 6 "UEFI firmware"

  command -v qemu-system-x86_64 >/dev/null 2>&1 || die "QEMU system emulator was not installed."
  command -v qemu-img >/dev/null 2>&1 || die "qemu-img was not installed."
  command -v cloud-localds >/dev/null 2>&1 && success "cloud-localds available." || warning "cloud-localds unavailable; some cloud-init image flows may be limited."
  command -v genisoimage >/dev/null 2>&1 && success "genisoimage available." || { command -v xorriso >/dev/null 2>&1 && success "xorriso available as ISO backend." || warning "No ISO creation backend detected."; }
  echo
  printf '%b  QEMU BUILD%b\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"
  qemu-system-x86_64 --version | head -n 1 || true
  VNM_PANEL_PREREQS_DONE="true"; export VNM_PANEL_PREREQS_DONE
  card "Virtualization prerequisites" "READY" "${BRIGHT_GREEN}" "QEMU, OVMF and image-generation dependencies are installed."
}

# =============================================================================
# KVM ANALYSIS
# =============================================================================

inspect_kvm() {
  section "03 / 08" "KVM CORE ANALYSIS" "Deep inspection of kernel virtualization support."
  if [[ -e /dev/kvm ]]; then
    KVM_AVAILABLE="true"
    success "/dev/kvm detected."
    ls -l /dev/kvm || true
    if [[ -r /dev/kvm && -w /dev/kvm ]]; then
      KVM_READWRITE="true"
      card "KVM device" "ACCESSIBLE" "${BRIGHT_GREEN}" "The host exposes a writable KVM acceleration device."
    else
      card "KVM device" "PERMISSIONS WARNING" "${BRIGHT_YELLOW}" "The device exists but access permissions look unusual."
    fi
  else
    KVM_AVAILABLE="false"
    card "KVM device" "NOT PRESENT" "${BRIGHT_YELLOW}" "Hardware acceleration is unavailable to this environment."
  fi

  echo
  printf '%b  CPU VIRTUALIZATION MATRIX%b\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"; thin_divider
  if command -v lscpu >/dev/null 2>&1; then
    local virt vendor
    virt="$(lscpu 2>/dev/null | grep -Ei 'Virtualization:' || true)"
    vendor="$(lscpu 2>/dev/null | grep -Ei 'Hypervisor vendor:' || true)"
    [[ -n "${virt}" ]] && printf '  %b%s%b\n' "${ICE}" "${virt}" "${RESET}"
    [[ -n "${vendor}" ]] && printf '  %b%s%b\n' "${PURPLE}" "${vendor}" "${RESET}"
    [[ -z "${virt}" && -z "${vendor}" ]] && warning "lscpu did not report CPU virtualization metadata."
  fi

  echo
  printf '%b  KERNEL MODULE MATRIX%b\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"; thin_divider
  if command -v lsmod >/dev/null 2>&1; then
    local modules
    modules="$(lsmod 2>/dev/null | grep '^kvm' || true)"
    [[ -n "${modules}" ]] && printf '%b%s%b\n' "${PURPLE}" "${modules}" "${RESET}" || warning "No KVM modules reported by lsmod."
  fi

  echo
  printf '%b  KERNEL VIRTUALIZATION EVENTS%b\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"; thin_divider
  if command -v dmesg >/dev/null 2>&1; then
    local dmesg_out
    dmesg_out="$(dmesg 2>/dev/null | grep -iE 'kvm|virtualiz|vmx|svm' | tail -n 20 || true)"
    [[ -n "${dmesg_out}" ]] && printf '%b%s%b\n' "${DIM}" "${dmesg_out}" "${RESET}" || muted "No relevant kernel virtualization events found."
  fi
}

# =============================================================================
# FUNCTIONAL KVM TEST
# =============================================================================

functional_kvm_test() {
  section "04 / 08" "KVM FUNCTIONAL CORE" "Performing an actual QEMU hardware acceleration initialization test."
  if [[ "${SKIP_KVM_TEST}" == "true" ]]; then
    KVM_TEST="SKIPPED"
    card "QEMU/KVM functional test" "SKIPPED" "${BRIGHT_YELLOW}" "Skipped by installer option."
    return 0
  fi
  if [[ "${KVM_AVAILABLE}" != "true" ]]; then
    KVM_TEST="UNAVAILABLE"
    card "QEMU/KVM functional test" "UNAVAILABLE" "${BRIGHT_YELLOW}" "No /dev/kvm device is exposed."
    return 0
  fi

  rm -f "${KVM_TEST_LOG}"
  echo; printf '%b  STARTING QEMU KVM ENGINE%b\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"; echo
  if [[ "${ULTRA_EFFECTS}" == "true" ]]; then
    local -a c=("${BRIGHT_RED}" "${FIRE}" "${ORANGE}" "${GOLD}" "${BRIGHT_YELLOW}" "${BRIGHT_CYAN}" "${PURPLE}" "${PINK}")
    local i idx
    for ((i=0; i<56; i++)); do
      idx=$((i % ${#c[@]})); printf '\r  %b█%b' "${c[$idx]}" "${RESET}"; sleep 0.012
    done
    echo
  fi

  set +e
  timeout 6s qemu-system-x86_64 -accel kvm -machine q35 -display none -nodefaults -S >"${KVM_TEST_LOG}" 2>&1
  local test_rc=$?
  set -e

  if [[ "${test_rc}" -eq 0 || "${test_rc}" -eq 124 ]]; then
    KVM_TEST="PASSED"
    card "QEMU/KVM functional test" "PASSED" "${BRIGHT_GREEN}" "QEMU initialized successfully with -accel kvm."
  else
    KVM_TEST="FAILED"
    card "QEMU/KVM functional test" "FAILED" "${BRIGHT_RED}" "The host exposes KVM but QEMU could not initialize it."
    echo; printf '%b  KVM DIAGNOSTIC OUTPUT%b\n' "${BRIGHT_YELLOW}${BOLD}" "${RESET}"; thin_divider
    tail -n 40 "${KVM_TEST_LOG}" 2>/dev/null || true
  fi
}

# =============================================================================
# NETWORK MATRIX
# =============================================================================

inspect_port() {
  section "05 / 08" "NETWORK MATRIX" "Checking panel networking before deployment."
  if command -v lsof >/dev/null 2>&1; then
    local -a pids=()
    mapfile -t pids < <(lsof -t -nP -iTCP:"${PANEL_PORT}" -sTCP:LISTEN 2>/dev/null || true)
    if (( ${#pids[@]} == 0 )); then
      card "Panel port ${PANEL_PORT}" "AVAILABLE" "${BRIGHT_GREEN}" "No process currently owns the panel port."
    else
      local pid command
      for pid in "${pids[@]}"; do
        [[ "${pid}" =~ ^[0-9]+$ ]] || continue
        command="$(ps -p "${pid}" -o args= 2>/dev/null || true)"
        label "Port PID" "${pid}" "${BRIGHT_YELLOW}"
        label "Process" "${command}" "${PINK}"
      done
      warning "Port ${PANEL_PORT} is already in use."
      warning "The legacy installer will handle any existing compatible process."
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 8 https://github.com >/dev/null 2>&1; then
      INTERNET_AVAILABLE="true"
      card "Internet connectivity" "ONLINE" "${BRIGHT_GREEN}" "External repository access is available."
    else
      INTERNET_AVAILABLE="false"
      card "Internet connectivity" "FAILED" "${BRIGHT_RED}" "Unable to reach the external repository endpoint."
    fi
  fi
}

# =============================================================================
# FIREWALL
# =============================================================================

configure_firewall() {
  section "06 / 08" "NETWORK GATEWAY" "Preparing external access for the GKVM panel."
  [[ "${SKIP_FIREWALL}" == "true" ]] && { warning "Firewall modification disabled by command-line option."; return 0; }
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
    card "UFW gateway" "PORT ${PANEL_PORT} OPEN" "${BRIGHT_GREEN}" "TCP access has been allowed."
    return 0
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    card "firewalld gateway" "PORT ${PANEL_PORT} OPEN" "${BRIGHT_GREEN}" "TCP access has been allowed."
    return 0
  fi
  card "Host firewall" "NOT MANAGED" "${BRIGHT_YELLOW}" "No UFW/firewalld installation was detected."
  warning "Check your VPS provider firewall for TCP ${PANEL_PORT}."
}

# =============================================================================
# LEGACY INSTALLER DOWNLOAD + COMPATIBILITY PATCH
# =============================================================================

download_legacy_installer() {
  section "07 / 08" "GKVM CORE BOOTSTRAP" "Fetching the pinned production installer."
  run_effect "Downloading pinned VNM direct installer" curl -fsSL "${LEGACY_URL}" -o "${LEGACY_RAW}"
  [[ -s "${LEGACY_RAW}" ]] || die "Pinned direct installer is empty."
  chmod 700 "${LEGACY_RAW}"
  bash -n "${LEGACY_RAW}" || die "Downloaded direct installer contains invalid Bash syntax."
  success "Downloaded installer passed Bash syntax validation."

  if grep -nE 'HKVM_INSTALL_DIR|HKVM_APP_DIR|/opt/hkvm|hkvm\.service' "${LEGACY_RAW}" >/dev/null 2>&1; then
    success "Legacy HKVM compatibility identifiers detected."
  else
    warning "Expected HKVM compatibility identifiers were not detected."
    warning "Continuing because the pinned installer itself remains authoritative."
  fi

  sed \
    -e 's/^PANEL_NAME=HKVM$/PANEL_NAME="GKVM"/' \
    -e 's/^PANEL_NAME="HKVM"$/PANEL_NAME="GKVM"/' \
    -e 's/HKVM PANEL V3/GKVM PANEL V3/g' \
    -e 's/HKVM V5/GKVM V5/g' \
    -e 's/HKVM Panel/GKVM Panel/g' \
    -e 's/HKVM PANEL/GKVM PANEL/g' \
    "${LEGACY_RAW}" > "${LEGACY_PATCHED}"

  chmod 700 "${LEGACY_PATCHED}"
  bash -n "${LEGACY_PATCHED}" || die "Branded direct installer failed Bash syntax validation."
  success "GKVM branding layer validated."
  card "Legacy compatibility layer" "PRESERVED" "${BRIGHT_CYAN}" "Internal HKVM runtime contracts were deliberately not renamed."
  echo; printf '%b  Preserved internal identifiers:%b\n\n' "${DIM}${ICE}" "${RESET}"
  printf '    %bHKVM_INSTALL_DIR%b\n    %bHKVM_APP_DIR%b\n    %b/opt/hkvm%b\n    %bhkvm.service%b\n' "${ICE}" "${RESET}" "${ICE}" "${RESET}" "${ICE}" "${RESET}" "${ICE}" "${RESET}"
}

# =============================================================================
# DEPLOY LEGACY INSTALLER
# =============================================================================

deploy_legacy() {
  section "08 / 08" "DEPLOYMENT CORE" "Handing the prepared host to the proven direct-install engine."
  echo; printf '%b╭──────────────────────────────────────────────────────────────────────╮%b\n' "${FLAME}${BOLD}" "${RESET}"
  printf '%b│%b                    %b🔥 GKVM DEPLOYMENT CORE 🔥%b                    %b│%b\n' "${FLAME}" "${RESET}" "${BRIGHT_WHITE}${BOLD}" "${RESET}" "${FLAME}" "${RESET}"
  printf '%b│%b                         %b◈ POWERING UP ◈%b                         %b│%b\n' "${FLAME}" "${RESET}" "${GOLD}${BOLD}" "${RESET}" "${FLAME}" "${RESET}"
  printf '%b╰──────────────────────────────────────────────────────────────────────╯%b\n' "${FLAME}${BOLD}" "${RESET}"
  echo
  if [[ "${ULTRA_EFFECTS}" == "true" ]]; then
    local -a seq=("${BRIGHT_RED}🔥" "${FIRE}█" "${ORANGE}█" "${GOLD}█" "${BRIGHT_YELLOW}█" "${BRIGHT_CYAN}█" "${PURPLE}█" "${PINK}⚡")
    local round element
    for round in {1..3}; do
      for element in "${seq[@]}"; do
        printf '\r  %b %bBOOTING DEPLOYMENT ENGINE%b' "${element}" "${WHITE}${BOLD}" "${RESET}"
        sleep 0.03
      done
    done
    clear_line
  fi
  echo; printf '%b  ┌──────────────────────────────────────────────────────────────┐%b\n' "${BRIGHT_WHITE}${BOLD}" "${RESET}"
  printf '%b  │                  GKVM ENGINE ONLINE                          │%b\n' "${BRIGHT_WHITE}${BOLD}" "${RESET}"
  printf '%b  └──────────────────────────────────────────────────────────────┘%b\n' "${BRIGHT_WHITE}${BOLD}" "${RESET}"
  echo
  set +e
  "${LEGACY_PATCHED}" "$@" 2>&1 | tee "${CHILD_LOG}"
  CHILD_EXIT_CODE="${PIPESTATUS[0]}"
  set -e
  return "${CHILD_EXIT_CODE}"
}

# =============================================================================
# TELEMETRY / HEALTH
# =============================================================================

panel_health() {
  echo; printf '%b  PANEL HEALTH%b\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"; thin_divider
  local listening="false" http="000"
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then listening="true"; fi
  http="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:${PANEL_PORT}/" 2>/dev/null || echo '000')"
  [[ "${listening}" == "true" ]] && success "TCP ${PANEL_PORT}: LISTENING" || warning "TCP ${PANEL_PORT}: NOT DETECTED"
  if [[ "${http}" =~ ^[0-9]{3}$ && "${http}" != "000" ]]; then success "HTTP health: ${http}"; else warning "HTTP health: NO RESPONSE"; fi
}

final_telemetry() {
  local end_time duration
  end_time="$(date +%s)"; duration=$((end_time - START_TIME))
  echo; divider; echo
  printf '%b  DEPLOYMENT TELEMETRY%b\n\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"
  label "Execution Time" "${duration}s" "${GOLD}"
  label "Panel Port" "${PANEL_PORT}" "${BRIGHT_CYAN}"
  if [[ "${QEMU_INSTALLED}" == "true" ]]; then label "QEMU" "READY" "${BRIGHT_GREEN}"; else label "QEMU" "UNKNOWN" "${BRIGHT_YELLOW}"; fi
  case "${KVM_TEST}" in
    PASSED) label "KVM" "HARDWARE ACCELERATED" "${BRIGHT_GREEN}";;
    FAILED) label "KVM" "TEST FAILED" "${BRIGHT_RED}";;
    SKIPPED) label "KVM" "TEST SKIPPED" "${BRIGHT_YELLOW}";;
    UNAVAILABLE) label "KVM" "UNAVAILABLE" "${BRIGHT_YELLOW}";;
    *) label "KVM" "${KVM_TEST}" "${WHITE}";;
  esac
  [[ "${INTERNET_AVAILABLE}" == "true" ]] && label "Repository Access" "ONLINE" "${BRIGHT_GREEN}" || label "Repository Access" "UNKNOWN" "${BRIGHT_YELLOW}"
  if [[ -d /run/systemd/system ]]; then label "Service Runtime" "SYSTEMD" "${BRIGHT_CYAN}"; else label "Service Runtime" "STANDALONE / CONTAINER" "${BRIGHT_YELLOW}"; fi
  label "Installer Log" "${INSTALLER_LOG}" "${ICE}"
}

final_screen() {
  clear_screen; reset_terminal
  echo
  printf '%b╔════════════════════════════════════════════════════════════════════════════╗%b\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"
  gradient_text "                 ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗" "#43EFFF" "#FF57D2"
  gradient_text "                ██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║" "#44D9FF" "#D765FF"
  gradient_text "                ██║  ███╗█████╔╝ ██║   ██║██╔████╔██║" "#5FFFF1" "#FF67A8"
  gradient_text "                ██║   ██║██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║" "#59CBFF" "#B56AFF"
  gradient_text "                ╚██████╔╝██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║" "#55E5FF" "#FF76DD"
  printf '%b╚════════════════════════════════════════════════════════════════════════════╝%b\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"
  echo
  if [[ "${CHILD_EXIT_CODE}" -eq 0 ]]; then
    printf '%b                  🔥 GKVM DEPLOYMENT SUCCESS 🔥%b\n' "${BRIGHT_GREEN}${BOLD}" "${RESET}"
  else
    printf '%b                    ❌ DEPLOYMENT FAILED%b\n' "${BRIGHT_RED}${BOLD}" "${RESET}"
  fi
  echo; divider; echo
  panel_health
  echo; divider; echo
  printf '%b  VIRTUALIZATION STATUS%b\n\n' "${BRIGHT_CYAN}${BOLD}" "${RESET}"
  if [[ "${KVM_TEST}" == "PASSED" ]]; then
    card "KVM acceleration" "ONLINE" "${BRIGHT_GREEN}" "Hardware-accelerated QEMU initialization succeeded."
  elif [[ "${KVM_AVAILABLE}" == "true" ]]; then
    card "KVM acceleration" "DEVICE AVAILABLE" "${BRIGHT_YELLOW}" "KVM exists but the functional test did not pass."
  else
    card "KVM acceleration" "UNAVAILABLE" "${BRIGHT_YELLOW}" "QEMU software emulation may be used."
  fi
  echo; divider; echo
  printf '%b  QUICK ACCESS%b\n\n' "${BRIGHT_MAGENTA}${BOLD}" "${RESET}"
  printf '  %b➜%b Check KVM\n    %b%s%b\n\n' "${BRIGHT_GREEN}" "${RESET}" "${ICE}" 'ls -l /dev/kvm' "${RESET}"
  printf '  %b➜%b Check QEMU\n    %b%s%b\n\n' "${BRIGHT_GREEN}" "${RESET}" "${ICE}" 'qemu-system-x86_64 --version' "${RESET}"
  printf '  %b➜%b Check panel\n    %bss -lntp | grep :%s%b\n\n' "${BRIGHT_GREEN}" "${RESET}" "${ICE}" "${PANEL_PORT}" "${RESET}"
  printf '  %b➜%b View installer log\n    %btail -f %s%b\n\n' "${BRIGHT_GREEN}" "${RESET}" "${ICE}" "${INSTALLER_LOG}" "${RESET}"
  divider; echo
  printf '%b  COMPATIBILITY%b\n\n' "${BRIGHT_YELLOW}${BOLD}" "${RESET}"
  label "Legacy Commit" "${LEGACY_COMMIT}" "${PURPLE}"
  label "Panel Runtime" "/opt/hkvm" "${ICE}"
  label "Service" "hkvm.service" "${GOLD}"
  echo; divider; echo
  if [[ "${CHILD_EXIT_CODE}" -eq 0 ]]; then
    if [[ "${ULTRA_EFFECTS}" == "true" ]]; then
      gradient_line "             ✦  🔥  ✦  ⚡  ✦  ◈  ✦  🔥  ✦  ⚡  ✦"
      sleep 0.12
      gradient_line "                  GKVM POWER CORE READY"
      sleep 0.08
      gradient_line "             QEMU • KVM • OVMF • VM ENGINE"
    else
      printf '%b                  GKVM POWER CORE READY%b\n' "${BRIGHT_GREEN}${BOLD}" "${RESET}"
    fi
  else
    printf '%b                  GKVM DEPLOYMENT ERROR%b\n' "${BRIGHT_RED}${BOLD}" "${RESET}"
    echo; warning "Review: ${INSTALLER_LOG}"
  fi
  echo; printf '%b             GKVM PANEL • PREMIUM VM HOSTING CORE%b\n\n' "${DIM}${WHITE}" "${RESET}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  parse_args "$@"
  [[ "${EUID}" -eq 0 ]] || die "Run this installer as root."
  draw_logo
  detect_host_metrics
  install_vnm_panel_prerequisites
  inspect_kvm
  functional_kvm_test
  inspect_port
  configure_firewall
  download_legacy_installer
  set +e
  deploy_legacy "$@"
  CHILD_EXIT_CODE=$?
  set -e
  final_telemetry
  final_screen
  return "${CHILD_EXIT_CODE}"
}

main "$@"
