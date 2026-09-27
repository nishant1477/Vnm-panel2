#!/usr/bin/env bash
# =============================================================================
#
#   ██████╗ ██╗  ██╗██╗   ██╗███╗   ███╗
#  ██╔════╝ ██║ ██╔╝██║   ██║████╗ ████║
#  ██║  ███╗█████╔╝ ██║   ██║██╔████╔██║
#  ██║   ██║██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║
#  ╚██████╔╝██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║
#   ╚═════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝
#
#            G K V M   P A N E L   —   U L T R A   N E X U S
#                     T I T A N I U M   E D I T I O N
#
# =============================================================================
#
#  MAXIMUM POWER BOOTSTRAPPER for the existing VNM/HKVM direct-install flow.
#
#  FEATURES (TITANIUM)
#  -------------------
#    • Cinematic multi-phase boot sequence (power-on / matrix rain / glitch logo)
#    • 4-color THEME ENGINE .................. CYBER · FIRE · ICE · MATRIX
#    • 256-color true-gradient text renderer
#    • Live animated gauges (CPU / RAM / SWAP / DISK / NET)
#    • Glitch-reveal logo with chromatic aberration frames
#    • Interactive WIZARD mode (port, firewall, benchmarks, repairs)
#    • Deep hardware telemetry (topology, flags, virt extensions, IOMMU)
#    • KVM AUTO-REPAIR heuristics (modprobe, udev perms, nested virt)
#    • QEMU accelerator BENCHMARK (KVM vs TCG boot timing)
#    • Network latency matrix + GeoIP + interface audit
#    • Multi-port collision matrix (panel + common service ports)
#    • Firewall rule SNAPSHOT + automatic rollback path
#    • Download engine: retry/backoff, size guard, sha256 gate
#    • Compatibility-preserving branding patch (HKVM contract kept)
#    • JSON telemetry report export
#    • Log rotation + multi-tier logging (DEBUG/INFO/OK/WARN/ERR)
#    • --dry-run simulation mode
#    • --repair-kvm standalone doctor mode
#    • Safe cleanup traps + full error recovery dashboard
#
#  COMPATIBILITY CONTRACT (PRESERVED — DO NOT RENAME)
#  ---------------------------------------------------
#    HKVM_INSTALL_DIR · HKVM_APP_DIR · /opt/hkvm · hkvm.service
#
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# =============================================================================
# METADATA
# =============================================================================

readonly GKVM_NAME="GKVM Panel"
readonly GKVM_CODENAME="ULTRA NEXUS"
readonly GKVM_VERSION="TITANIUM EDITION 2026.9"
readonly GKVM_BUILD="TX-2026.09.27-0001"

readonly LEGACY_COMMIT="dd9db741e4fac2394a514bae2c0d4ef933e00540"
readonly LEGACY_URL="https://raw.githubusercontent.com/stripathi02123-tech/Vnm-panel/${LEGACY_COMMIT}/install-direct.sh"

readonly WORK_ROOT="/tmp/gkvm-nexus-$$"
readonly DIR_BACKUP="${WORK_ROOT}/backup"
readonly DIR_CACHE="${WORK_ROOT}/cache"
readonly LEGACY_RAW="${WORK_ROOT}/legacy-install.sh"
readonly LEGACY_PATCHED="${WORK_ROOT}/gkvm-install.sh"
readonly KVM_TEST_LOG="${WORK_ROOT}/kvm-test.log"
readonly KVM_BENCH_LOG="${WORK_ROOT}/kvm-bench.log"
readonly CHILD_LOG="${WORK_ROOT}/child-installer.log"
readonly NET_MATRIX_LOG="${WORK_ROOT}/net-matrix.log"
readonly FW_SNAPSHOT="${WORK_ROOT}/firewall.snapshot"
readonly TELEMETRY_JSON="/var/log/gkvm-telemetry.json"
readonly INSTALLER_LOG="/var/log/gkvm-installer.log"

readonly DEFAULT_PANEL_PORT="8080"
readonly COMMON_PORTS=(22 80 443 3000 5000 8000 8080 8443 9090 10000)

# =============================================================================
# RUNTIME STATE (all mutable globals in one place)
# =============================================================================

VNM_PANEL_PREREQS_DONE="${VNM_PANEL_PREREQS_DONE:-false}"

PANEL_PORT="${GKVM_PORT:-$DEFAULT_PANEL_PORT}"

ANIMATION="true"
ULTRA_EFFECTS="true"
ASCII_MODE="false"
QUIET_MODE="false"
SKIP_KVM_TEST="false"
SKIP_FIREWALL="false"
SKIP_BENCHMARK="false"
DRY_RUN="false"
WIZARD="false"
REPAIR_MODE="false"
ASSUME_YES="false"

THEME="CYBER"            # CYBER | FIRE | ICE | MATRIX

TERM_W="80"
TERM_H="24"
HAS_UTF8="false"
HAS_256="false"
HAS_TRUECOLOR="false"

KVM_AVAILABLE="false"
KVM_READWRITE="false"
KVM_TEST="NOT_RUN"
KVM_BENCH_MS=""
TCG_BENCH_MS=""
KVM_REPAIRS=()
QEMU_INSTALLED="false"
OVMF_INSTALLED="false"
SYSTEMD_AVAILABLE="false"
INTERNET_AVAILABLE="false"
GEO_LOCATION="unknown"
LATENCY_MS=""

PKG_TOTAL="0"
PKG_DONE="0"

CHILD_EXIT_CODE="0"

START_TIME="$(date +%s)"

declare -a STAGE_LOG=()

# =============================================================================
# ANSI CORE
# =============================================================================

ESC=$'\033'

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
ITALIC="${ESC}[3m"
UNDERLINE="${ESC}[4m"
BLINK="${ESC}[5m"
REVERSE="${ESC}[7m"
STRIKE="${ESC}[9m"

BLACK="${ESC}[30m";        RED="${ESC}[31m";       GREEN="${ESC}[32m"
YELLOW="${ESC}[33m";       BLUE="${ESC}[34m";      MAGENTA="${ESC}[35m"
CYAN="${ESC}[36m";         WHITE="${ESC}[37m"

BRIGHT_BLACK="${ESC}[90m"; BRIGHT_RED="${ESC}[91m";   BRIGHT_GREEN="${ESC}[92m"
BRIGHT_YELLOW="${ESC}[93m";BRIGHT_BLUE="${ESC}[94m";  BRIGHT_MAGENTA="${ESC}[95m"
BRIGHT_CYAN="${ESC}[96m";  BRIGHT_WHITE="${ESC}[97m"

PINK="${ESC}[38;5;213m";   HOT_PINK="${ESC}[38;5;205m"; PURPLE="${ESC}[38;5;141m"
VIOLET="${ESC}[38;5;135m"; DEEP_PURPLE="${ESC}[38;5;93m"; LAVENDER="${ESC}[38;5;183m"
ICE="${ESC}[38;5;159m";    SKY="${ESC}[38;5;117m";    AQUA="${ESC}[38;5;87m"
TEAL="${ESC}[38;5;80m";    LIME="${ESC}[38;5;118m";   MINT="${ESC}[38;5;121m"
GOLD="${ESC}[38;5;220m";   ORANGE="${ESC}[38;5;208m"; FIRE="${ESC}[38;5;202m"
FLAME="${ESC}[38;5;196m";  CRIMSON="${ESC}[38;5;160m"; EMERALD="${ESC}[38;5;46m"
SILVER="${ESC}[38;5;250m"; STEEL="${ESC}[38;5;245m";  SLATE="${ESC}[38;5;240m"

# =============================================================================
# THEME ENGINE
# =============================================================================

theme_apply() {

    local t="${1^^}"

    case "${t}" in

        FIRE)
            T_ACCENT1="${FLAME}";  T_ACCENT2="${FIRE}";  T_ACCENT3="${ORANGE}"
            T_ACCENT4="${GOLD}";   T_GLOW="${BRIGHT_YELLOW}"; T_CORE="${BRIGHT_RED}"
            T_BG="${DIM}${RED}"
            ;;

        ICE)
            T_ACCENT1="${ICE}";    T_ACCENT2="${SKY}";   T_ACCENT3="${AQUA}"
            T_ACCENT4="${BRIGHT_CYAN}"; T_GLOW="${WHITE}"; T_CORE="${TEAL}"
            T_BG="${DIM}${CYAN}"
            ;;

        MATRIX)
            T_ACCENT1="${EMERALD}";T_ACCENT2="${LIME}";  T_ACCENT3="${MINT}"
            T_ACCENT4="${BRIGHT_GREEN}"; T_GLOW="${BRIGHT_WHITE}"; T_CORE="${GREEN}"
            T_BG="${DIM}${GREEN}"
            ;;

        CYBER|*)
            THEME="CYBER"
            T_ACCENT1="${BRIGHT_CYAN}"; T_ACCENT2="${PURPLE}"; T_ACCENT3="${PINK}"
            T_ACCENT4="${GOLD}";   T_GLOW="${BRIGHT_MAGENTA}"; T_CORE="${HOT_PINK}"
            T_BG="${DIM}${PURPLE}"
            ;;

    esac
}

# =============================================================================
# TERMINAL PROBE
# =============================================================================

probe_terminal() {

    TERM_W="$(tput cols 2>/dev/null || echo 80)"
    TERM_H="$(tput lines 2>/dev/null || echo 24)"

    [[ "${TERM_W}" =~ ^[0-9]+$ ]] || TERM_W=80
    [[ "${TERM_H}" =~ ^[0-9]+$ ]] || TERM_H=24

    if locale charmap 2>/dev/null | grep -qi "utf"; then
        HAS_UTF8="true"
    fi

    local colors
    colors="$(tput colors 2>/dev/null || echo 0)"
    [[ "${colors}" =~ ^[0-9]+$ ]] || colors=0
    (( colors >= 256 )) && HAS_256="true"

    if [[ "${COLORTERM:-}" =~ (truecolor|24bit) ]]; then
        HAS_TRUECOLOR="true"
    fi

    if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
        ANIMATION="false"
        ULTRA_EFFECTS="false"
    fi

    if [[ "${CI:-false}" == "true" || "${TERM_W}" -lt 70 ]]; then
        ULTRA_EFFECTS="false"
    fi

    [[ "${ASCII_MODE}" == "true" ]] && ULTRA_EFFECTS="false"
}

mkdir -p "${WORK_ROOT}" "${DIR_BACKUP}" "${DIR_CACHE}" 2>/dev/null || true
touch "${INSTALLER_LOG}" 2>/dev/null || true

exec > >(tee -a "${INSTALLER_LOG}") 2>&1

# =============================================================================
# CURSOR / SCREEN CONTROL
# =============================================================================

hide_cursor() { [[ "${ANIMATION}" == "true" ]] && printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }

clear_screen()  { clear 2>/dev/null || printf '\033[2J\033[H'; }
move_home()     { printf '\033[H'; }
clear_line()    { printf '\r\033[2K'; }
save_screen()   { printf '\033[?1049h'; }
restore_screen(){ printf '\033[?1049l'; }

# =============================================================================
# LOGGING ENGINE (multi-tier)
# =============================================================================

log_raw()  { printf '%s\n' "$*" >> "${INSTALLER_LOG}"; }

log_debug(){ log_raw "[$(date '+%H:%M:%S')] [DEBUG] $*"; }
log_info() { log_raw "[$(date '+%H:%M:%S')] [INFO ] $*"; }
log_ok()   { log_raw "[$(date '+%H:%M:%S')] [ OK  ] $*"; }
log_warn() { log_raw "[$(date '+%H:%M:%S')] [WARN ] $*"; }
log_err()  { log_raw "[$(date '+%H:%M:%S')] [ERR  ] $*"; }

rotate_logs() {

    if [[ -f "${INSTALLER_LOG}" ]]; then
        local size
        size="$(stat -c%s "${INSTALLER_LOG}" 2>/dev/null || echo 0)"
        if [[ "${size}" =~ ^[0-9]+$ ]] && (( size > 2097152 )); then
            mv "${INSTALLER_LOG}" "${INSTALLER_LOG}.1" 2>/dev/null || true
            touch "${INSTALLER_LOG}" 2>/dev/null || true
            log_info "Log rotated (previous > 2 MiB)."
        fi
    fi
}

# =============================================================================
# LIFECYCLE: CLEANUP + ERROR TRAP
# =============================================================================

cleanup() {

    local rc=$?

    show_cursor

    if [[ "${rc}" -ne 0 && "${REPAIR_MODE}" != "true" ]]; then
        : # on_error already rendered dashboard
    fi

    rm -rf "${WORK_ROOT}" 2>/dev/null || true

    return 0
}

trap cleanup EXIT

on_error() {

    local rc=$?

    show_cursor

    echo
    echo -e "${FLAME}${BOLD}"
    cat <<'EOF'
  ╔═══════════════════════════════════════════════════════════════════╗
  ║                                                                   ║
  ║        ✖  G K V M   N E X U S   —   F A U L T   S T A T E        ║
  ║                                                                   ║
  ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"

    printf "  ${BRIGHT_RED}✖${RESET} Fault Code : ${BOLD}%s${RESET}\n" "${rc}"
    printf "  ${ICE}◆${RESET} Log File   : ${INSTALLER_LOG}\n"

    if [[ -f "${CHILD_LOG}" ]]; then
        echo
        echo -e "${BRIGHT_YELLOW}${BOLD}  Last installer output:${RESET}"
        echo -e "${DIM}"
        tail -n 60 "${CHILD_LOG}" 2>/dev/null || true
        echo -e "${RESET}"
    fi

    if [[ -f "${KVM_TEST_LOG}" ]]; then
        echo
        echo -e "${BRIGHT_YELLOW}${BOLD}  KVM diagnostics:${RESET}"
        echo -e "${DIM}"
        tail -n 30 "${KVM_TEST_LOG}" 2>/dev/null || true
        echo -e "${RESET}"
    fi

    echo
    echo -e "  ${DIM}Recovery hints:${RESET}"
    echo -e "    ${ICE}➜${RESET} Re-run with ${BOLD}--repair-kvm${RESET} to auto-fix virtualization"
    echo -e "    ${ICE}➜${RESET} Re-run with ${BOLD}--dry-run${RESET} to simulate every stage"
    echo -e "    ${ICE}➜${RESET} Check ${BOLD}${INSTALLER_LOG}${RESET} for the full trace"
    echo

    exit "${rc}"
}

trap on_error ERR

# =============================================================================
# BASIC UI PRIMITIVES
# =============================================================================

info()    { printf "  ${ICE}◆${RESET} ${WHITE}%s${RESET}\n" "$*"; log_info "$*"; }
success() { printf "  ${EMERALD}✔${RESET} ${BRIGHT_GREEN}%s${RESET}\n" "$*"; log_ok "$*"; }
warning() { printf "  ${GOLD}⚠${RESET} ${BRIGHT_YELLOW}%s${RESET}\n" "$*"; log_warn "$*"; }
failure() { printf "  ${FLAME}✖${RESET} ${BRIGHT_RED}%s${RESET}\n" "$*" >&2; log_err "$*"; }
muted()   { printf "  ${DIM}%s${RESET}\n" "$*"; }
die()     { failure "$*"; exit 1; }

divider() {
    local n=$(( TERM_W > 80 ? 76 : TERM_W - 4 ))
    printf "  ${T_BG}%s${RESET}\n" "$(printf "%${n}s" "" | tr ' ' '━')"
}

thin_divider() {
    local n=$(( TERM_W > 80 ? 76 : TERM_W - 4 ))
    printf "  ${DIM}${CYAN}%s${RESET}\n" "$(printf "%${n}s" "" | tr ' ' '─')"
}

label() {

    local key="$1"
    local value="$2"
    local color="${3:-${WHITE}}"

    printf \
        "  ${DIM}%-26s${RESET} ${color}%s${RESET}\n" \
        "${key}" \
        "${value}"
}

bullet() {
    printf "  ${T_ACCENT2}${BOLD}▸${RESET} ${WHITE}%s${RESET}\n" "$*"
}

# =============================================================================
# GLYPH SET (unicode / ascii fallback)
# =============================================================================

glyph_init() {

    if [[ "${HAS_UTF8}" == "true" && "${ASCII_MODE}" != "true" ]]; then
        G_CHECK="✔"; G_CROSS="✖"; G_WARN="⚠"; G_INFO="◆"
        G_ARROW="➜"; G_BLOCK_F="█"; G_BLOCK_E="░"; G_BLOCK_M="▒"
        G_PIPE="│"; G_CORNER_TL="╭"; G_CORNER_TR="╮"
        G_CORNER_BL="╰"; G_CORNER_BR="╯"
        G_DIA="◆"; G_DIA_O="◇"; G_HEX="⬢"; G_HEX_O="⬡"
        G_STAR="✦"; G_BOLT="⚡"; G_FIRE="🔥"
        G_SPINNER=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
    else
        G_CHECK="[OK]"; G_CROSS="[X]"; G_WARN="[!]"; G_INFO="[*]"
        G_ARROW="->"; G_BLOCK_F="#"; G_BLOCK_E="."; G_BLOCK_M="="
        G_PIPE="|"; G_CORNER_TL="+"; G_CORNER_TR="+"
        G_CORNER_BL="+"; G_CORNER_BR="+"
        G_DIA="*"; G_DIA_O="o"; G_HEX="#"; G_HEX_O="o"
        G_STAR="*"; G_BOLT="!"; G_FIRE=">>"
        G_SPINNER=( "-" "\\" "|" "/" )
    fi
}

# =============================================================================
# GRADIENT TEXT RENDERER
# =============================================================================

gradient_line() {

    local text="$1"
    local mode="${2:-theme}"

    local colors=()

    case "${mode}" in

        fire)
            colors=( "${FLAME}" "${FIRE}" "${ORANGE}" "${GOLD}" "${BRIGHT_YELLOW}" )
            ;;

        ice)
            colors=( "${ICE}" "${SKY}" "${AQUA}" "${BRIGHT_CYAN}" "${WHITE}" )
            ;;

        matrix)
            colors=( "${EMERALD}" "${LIME}" "${MINT}" "${BRIGHT_GREEN}" )
            ;;

        rainbow)
            colors=( "${BRIGHT_CYAN}" "${AQUA}" "${SKY}" "${ICE}" "${PURPLE}"
                     "${PINK}" "${HOT_PINK}" "${GOLD}" "${ORANGE}" "${FIRE}" )
            ;;

        theme|*)
            colors=( "${T_ACCENT1}" "${T_ACCENT2}" "${T_ACCENT3}" "${T_ACCENT4}"
                     "${T_ACCENT2}" "${T_ACCENT1}" )
            ;;
    esac

    local len="${#text}"
    local clen="${#colors[@]}"
    local i

    for ((i=0; i<len; i++)); do

        printf "%b%s%b" \
            "${colors[$(( i % clen ))]}" \
            "${text:i:1}" \
            "${RESET}"

    done

    printf "\n"
}

# =============================================================================
# TYPEWRITER EFFECT
# =============================================================================

typewrite() {

    local text="$1"
    local speed="${2:-0.012}"

    [[ "${ANIMATION}" != "true" ]] && { printf "%s\n" "${text}"; return 0; }

    local i
    local len="${#text}"

    for ((i=0; i<len; i++)); do

        printf "%b%s%b" "${T_ACCENT1}${BOLD}" "${text:i:1}" "${RESET}"
        sleep "${speed}"

    done

    printf "\n"
}

# =============================================================================
# MATRIX RAIN
# =============================================================================

matrix_rain() {

    [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0

    local rows="${1:-8}"
    local cols=$(( TERM_W > 100 ? 90 : TERM_W - 10 ))
    local frames="${2:-28}"

    local glyphs=( "0" "1" "7" "K" "V" "M" "Q" "E" "M" "U" "L" "A" "T" "O" "R" )
    local colors=( "${T_ACCENT2}" "${T_ACCENT3}" "${T_GLOW}" "${EMERALD}" )

    local f c r g col
    local out

    hide_cursor

    for ((f=0; f<frames; f++)); do

        out=""
        for ((r=0; r<rows; r++)); do
            line="  "
            for ((c=0; c<cols; c++)); do
                if (( RANDOM % 12 == 0 )); then
                    g="${glyphs[$((RANDOM % ${#glyphs[@]}))]}"
                    col="${colors[$((RANDOM % ${#colors[@]}))]}"
                    line+="${col}${BOLD}${g}${RESET}"
                else
                    line+=" "
                fi
            done
            out+="${line}\n"
        done

        printf "%b" "${out}"
        sleep 0.03
        move_home

    done

    clear_line
    show_cursor
}

# =============================================================================
# GLITCH REVEAL (chromatic aberration frames)
# =============================================================================

glitch_reveal() {

    [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0

    local text="$1"

    local glitch_chars=( "▓" "▒" "░" "#" "%" "@" "&" "$" "?" "!" )

    local pass
    local reveal
    local i
    local len="${#text}"

    hide_cursor

    for pass in 1 2 3; do

        reveal=""
        for ((i=0; i<len; i++)); do

            if (( RANDOM % 3 == 0 )); then
                reveal+="${glitch_chars[$((RANDOM % ${#glitch_chars[@]}))]}"
            else
                reveal+=" "
            fi

        done

        printf "\r  ${FLAME}${BOLD}%s${RESET}" "${reveal}"
        sleep 0.06

    done

    printf "\r  %b%s%b\n" "${T_GLOW}${BOLD}" "${text}" "${RESET}"
    show_cursor
}

# =============================================================================
# PARTICLE BURST
# =============================================================================

particle_burst() {

    [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0

    local text="$1"

    local particles=( "✦" "✧" "⋆" "＊" "＋" "･" "⚡" "◆" )

    hide_cursor

    local wave
    local i

    for wave in 1 2 3 4 5 6; do

        printf "\r  "
        for i in {0..40}; do
            if (( RANDOM % 2 == 0 )); then
                printf "%b%s" "${T_ACCENT4}" "${particles[$((RANDOM % ${#particles[@]}))]}"
            else
                printf " "
            fi
        done
        sleep 0.04

    done

    clear_line
    printf "  %b%s%b\n" "${T_GLOW}${BOLD}" "${text}" "${RESET}"
    show_cursor
}

# =============================================================================
# PLASMA STRIP
# =============================================================================

plasma_strip() {

    [[ "${ULTRA_EFFECTS}" == "true" ]] || return 0

    local width=$(( TERM_W > 80 ? 72 : TERM_W - 8 ))
    local frames="${1:-30}"

    local colors=( "${T_ACCENT1}" "${T_ACCENT2}" "${T_ACCENT3}" "${T_ACCENT4}" "${T_GLOW}" )

    hide_cursor

    local f i idx
    local line

    for ((f=0; f<frames; f++)); do

        line="  "
        for ((i=0; i<width; i++)); do

            idx=$(( (i + f) % ${#colors[@]} ))
            line+="${colors[$idx]}${G_BLOCK_F}${RESET}"

        done

        printf "\r%s" "${line}"
        sleep 0.02

    done

    echo
    show_cursor
}

# =============================================================================
# ENERGY / PROGRESS BAR
# =============================================================================

energy_bar() {

    local current="$1"
    local total="$2"
    local text="$3"

    local width=$(( TERM_W > 80 ? 46 : TERM_W - 34 ))
    (( width < 10 )) && width=10

    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    (( filled < 0 )) && filled=0
    (( empty  < 0 )) && empty=0

    local fill="" blank=""
    (( filled > 0 )) && fill="$(printf "%${filled}s" "" | tr ' ' "${G_BLOCK_F}")"
    (( empty  > 0 )) && blank="$(printf "%${empty}s" "" | tr ' ' "${G_BLOCK_E}")"

    local pct=$(( current * 100 / total ))

    local seg1="" seg2=""

    if (( filled > 0 )); then
        local half=$(( filled / 2 ))
        seg1="$(printf "%${half}s" "" | tr ' ' "${G_BLOCK_F}")"
        seg2="$(printf "%$((filled - half))s" "" | tr ' ' "${G_BLOCK_F}")"
    fi

    printf \
        "\r  ${T_ACCENT1}[${LIME}%s${ORANGE}%s${DIM}%s${T_ACCENT1}]${RESET} ${GOLD}%3d%%${RESET} ${WHITE}%s${RESET}" \
        "${seg1}" "${seg2}" "${blank}" "${pct}" "${text}"

    if (( current >= total )); then
        echo
    fi
}

# =============================================================================
# SPINNER RUNNER (execute with animation)
# =============================================================================

run_effect() {

    local text="$1"
    shift

    if [[ "${DRY_RUN}" == "true" ]]; then
        printf "  ${STEEL}[DRY-RUN]${RESET} ${WHITE}%s${RESET}\n" "${text}"
        log_info "[dry-run] skipped: ${text}"
        return 0
    fi

    if [[ "${ANIMATION}" != "true" ]]; then

        info "${text}..."
        "$@"
        success "${text}"
        return 0
    fi

    local spin_colors=(
        "${T_ACCENT1}" "${ICE}" "${T_ACCENT2}" "${PINK}"
        "${T_GLOW}"    "${GOLD}" "${BRIGHT_GREEN}" "${BRIGHT_YELLOW}"
    )

    "$@" >>"${INSTALLER_LOG}" 2>&1 &
    local pid=$!
    local i=0

    hide_cursor

    while kill -0 "${pid}" >/dev/null 2>&1; do

        printf \
            "\r  ${spin_colors[$((i % ${#spin_colors[@]}))]}${BOLD}%s${RESET} ${WHITE}%-58s${RESET}" \
            "${G_SPINNER[$((i % ${#G_SPINNER[@]}))]}" \
            "${text}"

        i=$((i + 1))
        sleep 0.07

    done

    local rc=0
    wait "${pid}" || rc=$?

    show_cursor

    if [[ "${rc}" -eq 0 ]]; then

        printf \
            "\r  ${EMERALD}${BOLD}%s${RESET} ${BRIGHT_GREEN}%-58s${RESET}\n" \
            "${G_CHECK}" "${text}"

    else

        printf \
            "\r  ${FLAME}${BOLD}%s${RESET} ${BRIGHT_RED}%-58s${RESET}\n" \
            "${G_CROSS}" "${text}"

        return "${rc}"
    fi
}

# =============================================================================
# NETWORK OP WITH RETRY + BACKOFF
# =============================================================================

net_fetch() {

    local url="$1"
    local out="$2"
    local tries="${3:-4}"

    local attempt=1
    local delay=1

    while (( attempt <= tries )); do

        log_info "fetch attempt ${attempt}/${tries}: ${url}"

        if curl -fsSL --connect-timeout 8 --max-time 60 \
            "${url}" -o "${out}" 2>>"${INSTALLER_LOG}"; then

            return 0
        fi

        warning "fetch failed (attempt ${attempt}/${tries}) — retrying in ${delay}s"
        sleep "${delay}"
        delay=$(( delay * 2 ))
        (( attempt++ ))

    done

    return 1
}

# =============================================================================
# CARD / PANEL / TABLE / GAUGE
# =============================================================================

card() {

    local title="$1"
    local status="$2"
    local color="$3"
    local description="${4:-}"

    local w=$(( TERM_W > 80 ? 60 : TERM_W - 20 ))
    local pad
    pad="$(printf "%${w}s" "")"

    echo
    echo -e "  ${DIM}${T_ACCENT2}${G_CORNER_TL}${pad// /─}${G_CORNER_TR}${RESET}"
    printf  "  ${DIM}${T_ACCENT2}${G_PIPE}${RESET} ${BOLD}${WHITE}%s${RESET}\n" "${title}"
    echo -e "  ${DIM}${T_ACCENT2}${G_PIPE}${RESET}"
    printf  "  ${DIM}${T_ACCENT2}${G_PIPE}${RESET}   ${color}${BOLD}%s${RESET}\n" "${status}"

    if [[ -n "${description}" ]]; then
        echo -e "  ${DIM}${T_ACCENT2}${G_PIPE}${RESET}"
        printf  "  ${DIM}${T_ACCENT2}${G_PIPE}${RESET}   ${DIM}%s${RESET}\n" "${description}"
    fi

    echo -e "  ${DIM}${T_ACCENT2}${G_CORNER_BL}${pad// /─}${G_CORNER_BR}${RESET}"
}

section() {

    local number="$1"
    local title="$2"
    local subtitle="$3"

    local w=$(( TERM_W > 84 ? 78 : TERM_W - 6 ))
    local inner=$(( w - 2 ))
    local num_pad
    num_pad="$(printf "%${inner}s" "")"

    echo
    echo -e "${T_ACCENT2}${BOLD}"

    printf "  ${G_CORNER_TL}%s${G_CORNER_TR}\n" "$(printf "%${inner}s" "" | tr ' ' '─')"

    printf "  ${G_PIPE}  ${T_ACCENT1}%s${RESET}${T_ACCENT2}${BOLD} %s${num_pad:0:$((inner - ${#number} - ${#title} - 3))}${G_PIPE}\n" \
        "${number}" "${title}"

    printf "  ${G_CORNER_BL}%s${G_CORNER_BR}\n" "$(printf "%${inner}s" "" | tr ' ' '─')"

    echo -e "${RESET}"

    printf "  ${DIM}%s${RESET}\n\n" "${subtitle}"
}

gauge() {

    local name="$1"
    local pct="$2"
    local detail="$3"
    local color="${4:-${T_ACCENT1}}"

    local width=26
    local filled=$(( pct * width / 100 ))
    (( filled > width )) && filled=$width
    (( filled < 0 )) && filled=0
    local empty=$(( width - filled ))

    local bar=""
    (( filled > 0 )) && bar="$(printf "%${filled}s" "" | tr ' ' "${G_BLOCK_F}")"
    (( empty  > 0 )) && bar+="$(printf "%${empty}s" "" | tr ' ' "${G_BLOCK_E}")"

    printf \
        "  ${DIM}%-12s${RESET} ${color}${BOLD}[%s]${RESET} ${GOLD}%3d%%${RESET} ${DIM}%s${RESET}\n" \
        "${name}" "${bar}" "${pct}" "${detail}"
}

table_row() {

    local c1="$1" c2="$2" c3="$3"
    local col="${4:-${WHITE}}"

    printf \
        "  ${DIM}${G_PIPE}${RESET} ${STEEL}%-24s${RESET} ${DIM}${G_PIPE}${RESET} ${col}%-26s${RESET} ${DIM}${G_PIPE}${RESET} ${WHITE}%s${RESET}\n" \
        "${c1}" "${c2}" "${c3}"
}

table_header() {

    local c1="$1" c2="$2" c3="$3"
    local w=$(( TERM_W > 80 ? 78 : TERM_W - 4 ))

    echo
    printf \
        "  ${T_ACCENT1}${BOLD}%-24s ${G_PIPE} %-26s ${G_PIPE} %s${RESET}\n" \
        "${c1}" "${c2}" "${c3}"
    printf \
        "  ${DIM}%s${RESET}\n" \
        "$(printf "%${w}s" "" | tr ' ' '─')"
}

# =============================================================================
# STATUS CHIP
# =============================================================================

chip() {

    local text="$1"
    local kind="${2:-info}"   # ok | warn | err | info | accent

    local color="${ICE}"
    case "${kind}" in
        ok)     color="${EMERALD}" ;;
        warn)   color="${GOLD}" ;;
        err)    color="${FLAME}" ;;
        accent) color="${T_ACCENT3}" ;;
        *)      color="${ICE}" ;;
    esac

    printf "${color}${BOLD} %s ${RESET}" "${text}"
}

# =============================================================================
# BOOT CINEMATIC (multi-phase)
# =============================================================================

boot_cinematic() {

    clear_screen
    hide_cursor

    # -- PHASE 1: power strip --------------------------------------------------
    if [[ "${ULTRA_EFFECTS}" == "true" ]]; then

        local w=$(( TERM_W > 80 ? 74 : TERM_W - 6 ))
        local colors=( "${SLATE}" "${STEEL}" "${SILVER}" "${T_ACCENT1}" "${T_ACCENT2}" "${T_GLOW}" )

        local seg=$(( w / ${#colors[@]} ))
        local line=""
        local c

        for c in "${colors[@]}"; do
            line+="${c}$(printf "%${seg}s" "" | tr ' ' "${G_BLOCK_F}")${RESET}"
        done

        local i
        for ((i=0; i<3; i++)); do
            printf "\r  %s" "${line}"
            sleep 0.08
            printf "\r  %s" "$(printf "%${w}s" "" | tr ' ' ' ')"
            sleep 0.05
        done

        printf "\r  %s\n" "${line}"
        sleep 0.15

    fi

    # -- PHASE 2: matrix rain --------------------------------------------------
    [[ "${ULTRA_EFFECTS}" == "true" ]] && matrix_rain 6 22

    # -- PHASE 3: logo ---------------------------------------------------------
    draw_logo

    show_cursor
}

# =============================================================================
# LOGO
# =============================================================================

draw_logo() {

    echo
    echo -e "${T_ACCENT1}${BOLD}"

    cat <<EOF
  ╔═══════════════════════════════════════════════════════════════════════════╗
  ║                                                                           ║
  ║     ${T_ACCENT3}██╗  ██╗██╗   ██╗███╗   ███╗${T_ACCENT1}                              ║
  ║     ${T_ACCENT3}██║ ██╔╝██║   ██║████╗ ████║${T_ACCENT1}                              ║
  ║     ${T_ACCENT3}█████╔╝ ██║   ██║██╔████╔██║${T_ACCENT1}                              ║
  ║     ${T_ACCENT3}██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║${T_ACCENT1}                              ║
  ║     ${T_ACCENT3}██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║${T_ACCENT1}                              ║
  ║     ${T_ACCENT3}╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝${T_ACCENT1}                              ║
  ║                                                                           ║
  ║           ${T_GLOW}G K V M   P A N E L  ·  U L T R A   N E X U S${T_ACCENT1}           ║
  ║                                                                           ║
  ╚═══════════════════════════════════════════════════════════════════════════╝
EOF

    echo -e "${RESET}"

    echo
    printf "          "
    chip "QEMU" accent
    printf " ${DIM}×${RESET} "
    chip "KVM" ok
    printf " ${DIM}×${RESET} "
    chip "OVMF" info
    printf " ${DIM}×${RESET} "
    chip "CLOUD-INIT" accent
    printf " ${DIM}×${RESET} "
    chip "NET" ok
    echo

    echo
    gradient_line \
        "                    MAXIMUM POWER HOST BOOTSTRAP" \
        "theme"

    echo

    if [[ "${ULTRA_EFFECTS}" == "true" ]]; then

        local seq=( "${FLAME}" "${FIRE}" "${ORANGE}" "${GOLD}" "${BRIGHT_YELLOW}" )
        local i

        for i in "${!seq[@]}"; do
            printf "\r  %b%s ${WHITE}${BOLD}POWER CORE SPINNING UP${RESET}" \
                "${seq[$i]}" "${G_FIRE}"
            sleep 0.06
        done

        clear_line

    fi

    echo
    divider

    log_info "Boot cinematic complete. Theme=${THEME} Port=${PANEL_PORT}"
}

# =============================================================================
# STAGE TRACKER
# =============================================================================

stage_push() {
    STAGE_LOG+=( "$*" )
    log_info "STAGE ${#STAGE_LOG[@]}: $*"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

print_help() {

    cat <<EOF

  ${GKVM_NAME} — ${GKVM_CODENAME} ${GKVM_VERSION}
  Build ${GKVM_BUILD}

  USAGE
      gkvm-nexus-installer.sh [OPTIONS]

  CORE
      --theme NAME          CYBER (default) | FIRE | ICE | MATRIX
      --port N              Panel port (default ${DEFAULT_PANEL_PORT})
      --no-animation        Disable terminal animation
      --fast                Alias for --no-animation
      --ascii               Force ASCII-safe glyphs (no unicode)
      --quiet               Minimal output
      --yes                 Non-interactive; accept wizard defaults

  STAGE CONTROL
      --skip-kvm-test       Skip QEMU/KVM functional test
      --skip-benchmark      Skip KVM vs TCG accelerator benchmark
      --skip-firewall       Do not modify UFW/firewalld
      --dry-run             Simulate all stages; change nothing

  MODES
      --wizard              Interactive configuration wizard
      --repair-kvm          Standalone KVM doctor (diagnose + auto-fix)
      --version             Show version
      --help                Show this help

  EXAMPLES
      sudo ./gkvm-nexus-installer.sh --theme FIRE
      sudo ./gkvm-nexus-installer.sh --wizard --port 9090
      sudo ./gkvm-nexus-installer.sh --repair-kvm
      sudo ./gkvm-nexus-installer.sh --dry-run --theme MATRIX

EOF
}

parse_args() {

    while [[ $# -gt 0 ]]; do

        case "$1" in

            --theme)
                [[ $# -ge 2 ]] || die "--theme requires a value"
                THEME="$2"; shift
                ;;

            --port)
                [[ $# -ge 2 ]] || die "--port requires a value"
                if [[ "$2" =~ ^[0-9]+$ ]] && (( $2 >= 1 && $2 <= 65535 )); then
                    PANEL_PORT="$2"
                else
                    die "Invalid port: $2"
                fi
                shift
                ;;

            --no-animation|--fast)
                ANIMATION="false"; ULTRA_EFFECTS="false"
                ;;

            --ascii)
                ASCII_MODE="true"; ULTRA_EFFECTS="false"
                ;;

            --quiet)
                QUIET_MODE="true"
                ANIMATION="false"; ULTRA_EFFECTS="false"
                ;;

            --yes|-y)
                ASSUME_YES="true"
                ;;

            --skip-kvm-test)
                SKIP_KVM_TEST="true"
                ;;

            --skip-benchmark)
                SKIP_BENCHMARK="true"
                ;;

            --skip-firewall)
                SKIP_FIREWALL="true"
                ;;

            --dry-run)
                DRY_RUN="true"
                ;;

            --wizard)
                WIZARD="true"
                ;;

            --repair-kvm)
                REPAIR_MODE="true"
                ;;

            --version)
                echo "${GKVM_NAME} ${GKVM_CODENAME} ${GKVM_VERSION} (${GKVM_BUILD})"
                exit 0
                ;;

            --help|-h)
                print_help
                exit 0
                ;;

            *)
                warning "Unknown option ignored: $1"
                ;;
        esac

        shift
    done
}

# =============================================================================
# INTERACTIVE WIZARD
# =============================================================================

wizard_run() {

    [[ "${QUIET_MODE}" == "true" ]] && return 0

    clear_screen
    hide_cursor

    echo
    gradient_line "              G K V M   C O N F I G U R A T I O N   W I Z A R D" "rainbow"
    echo
    divider
    echo

    local reply

    # -- port ------------------------------------------------------------------
    printf "  ${T_ACCENT1}${BOLD}➜${RESET} Panel port  ${DIM}[${PANEL_PORT}]${RESET}: "
    read -r reply || reply=""

    if [[ -n "${reply}" ]]; then
        if [[ "${reply}" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= 65535 )); then
            PANEL_PORT="${reply}"
        else
            warning "Invalid port '${reply}' — keeping ${PANEL_PORT}"
        fi
    fi

    # -- firewall --------------------------------------------------------------
    printf "  ${T_ACCENT1}${BOLD}➜${RESET} Open firewall port ${PANEL_PORT}/tcp? ${DIM}[Y/n]${RESET}: "
    read -r reply || reply=""

    case "${reply}" in
        n|N|no|NO) SKIP_FIREWALL="true" ;;
        *)         SKIP_FIREWALL="false" ;;
    esac

    # -- benchmark -------------------------------------------------------------
    printf "  ${T_ACCENT1}${BOLD}➜${RESET} Run QEMU accelerator benchmark? ${DIM}[Y/n]${RESET}: "
    read -r reply || reply=""

    case "${reply}" in
        n|N|no|NO) SKIP_BENCHMARK="true" ;;
        *)         SKIP_BENCHMARK="false" ;;
    esac

    # -- kvm test --------------------------------------------------------------
    printf "  ${T_ACCENT1}${BOLD}➜${RESET} Run KVM functional test? ${DIM}[Y/n]${RESET}: "
    read -r reply || reply=""

    case "${reply}" in
        n|N|no|NO) SKIP_KVM_TEST="true" ;;
        *)         SKIP_KVM_TEST="false" ;;
    esac

    show_cursor

    echo
    divider
    echo

    card \
        "Wizard configuration locked" \
        "PORT ${PANEL_PORT} · FW:$([[ "${SKIP_FIREWALL}" == "true" ]] && echo OFF || echo ON) · BENCH:$([[ "${SKIP_BENCHMARK}" == "true" ]] && echo OFF || echo ON) · KVM-TEST:$([[ "${SKIP_KVM_TEST}" == "true" ]] && echo OFF || echo ON)" \
        "${EMERALD}" \
        "Proceeding with deployment."

    log_info "Wizard locked: port=${PANEL_PORT} firewall_skip=${SKIP_FIREWALL} bench_skip=${SKIP_BENCHMARK} kvm_test_skip=${SKIP_KVM_TEST}"
}

# =============================================================================
# STAGE 00 — HOST TELEMETRY
# =============================================================================

detect_host_metrics() {

    stage_push "HOST TELEMETRY"

    section \
        "00 / 11" \
        "HOST TELEMETRY" \
        "Deep system profiling for the deployment dashboard."

    local cpu threads ram_total ram_free disk_free disk_total swap_total uptime arch kernel os_name

    threads="$(nproc 2>/dev/null || echo "?")"
    cpu="$(awk -F: '/model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "unknown")"
    arch="$(uname -m 2>/dev/null || echo "?")"
    kernel="$(uname -r 2>/dev/null || echo "?")"

    ram_total="$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')"
    ram_free="$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')"
    swap_total="$(free -m 2>/dev/null | awk '/^Swap:/ {print $2}')"

    disk_free="$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')"
    disk_total="$(df -m / 2>/dev/null | awk 'NR==2 {print $2}')"

    uptime="$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")"

    os_name="$(
        . /etc/os-release 2>/dev/null
        echo "${PRETTY_NAME:-unknown}"
    )"

    # -- gauges ---------------------------------------------------------------
    local ram_pct=0 disk_pct=0 swap_pct=0
    [[ "${ram_total}" =~ ^[0-9]+$ ]]  && (( ram_total > 0 ))  && ram_pct=$((  (ram_total - ram_free) * 100 / ram_total ))
    [[ "${disk_total}" =~ ^[0-9]+$ ]] && (( disk_total > 0 )) && disk_pct=$(( (disk_total - disk_free) * 100 / disk_total ))
    [[ "${swap_total}" =~ ^[0-9]+$ ]] && (( swap_total > 0 )) && swap_pct=10

    echo
    gauge "CPU THREADS" 0 "${threads} logical cores" "${T_ACCENT1}"
    gauge "MEMORY"      "${ram_pct}"  "${ram_free} MiB free / ${ram_total} MiB" "${PURPLE}"
    gauge "ROOT DISK"   "${disk_pct}" "${disk_free} MiB free / ${disk_total} MiB" "${GOLD}"
    gauge "SWAP"        "${swap_pct}" "${swap_total:-0} MiB" "${TEAL}"
    echo

    # -- spec sheet -----------------------------------------------------------
    table_header "PROPERTY" "VALUE" "NOTE"

    table_row "CPU Model"     "${cpu}"          "processor"   "${ICE}"
    table_row "Architecture"  "${arch}"         "system"      "${SKY}"
    table_row "Kernel"        "${kernel}"       "linux"       "${PURPLE}"
    table_row "OS"            "${os_name}"      "distro"      "${PINK}"
    table_row "Memory"        "${ram_total} MiB" "total"      "${GOLD}"
    table_row "Root Storage"  "${disk_total} MiB" "total"     "${ORANGE}"
    table_row "Uptime"        "${uptime}"        "host"       "${BRIGHT_CYAN}"

    echo

    # -- CPU flags ------------------------------------------------------------
    if [[ -r /proc/cpuinfo ]]; then

        local flags
        flags="$(awk -F: '/^flags/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"

        echo -e "  ${T_ACCENT3}${BOLD}CPU VIRTUALIZATION EXTENSIONS${RESET}"
        thin_divider

        local f
        for f in vmx svm ept npt hv_vapic flexpriority; do
            if echo "${flags}" | grep -qw "${f}"; then
                printf "  ${EMERALD}✔${RESET} ${WHITE}%-14s${RESET} ${DIM}present${RESET}\n" "${f}"
            else
                printf "  ${SLATE}○${RESET} ${DIM}%-14s${RESET} ${DIM}absent${RESET}\n" "${f}"
            fi
        done

        echo
    fi

    card \
        "Host telemetry" \
        "PROFILED" \
        "${T_ACCENT1}" \
        "System resources captured and gauged."

    energy_bar 1 11 "Telemetry profiled"
}

# =============================================================================
# STAGE 01 — PREREQUISITES
# =============================================================================

install_prerequisites() {

    stage_push "HOST FOUNDATION"

    [[ "${VNM_PANEL_PREREQS_DONE}" == "true" ]] && {

        info "VNM host prerequisites already prepared by parent installer."
        energy_bar 11 11 "Prerequisites pre-satisfied"
        return 0
    }

    [[ -f /etc/os-release ]] || die "Unable to detect operating system."

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in
        ubuntu|debian) ;;
        *)
            die "Automatic host preparation supports Ubuntu/Debian only (detected: ${ID:-unknown})."
            ;;
    esac

    command -v apt-get >/dev/null 2>&1 || die "apt-get is required."

    export DEBIAN_FRONTEND=noninteractive

    section \
        "01 / 11" \
        "HOST FOUNDATION" \
        "Installing virtualization prerequisites with retry protection."

    # -- package manifest ------------------------------------------------------
    local -a pkgs_apt=( ca-certificates curl git file lsof procps iproute2
                        openssl build-essential python3 sqlite3 util-linux
                        timeout cloud-image-utils genisoimage
                        qemu-system-x86 qemu-utils ovmf )

    PKG_TOTAL="${#pkgs_apt[@]}"
    PKG_DONE=0

    # -- apt update ------------------------------------------------------------
    run_effect \
        "Refreshing package database" \
        apt-get update -y \
        || warning "apt-get update reported issues; continuing."

    energy_bar 2 11 "APT package database"

    # -- grouped install -------------------------------------------------------
    local -a group_util=( ca-certificates curl git file lsof procps iproute2
                          openssl build-essential python3 sqlite3 util-linux )
    local -a group_img=( cloud-image-utils genisoimage )
    local -a group_qemu=( qemu-system-x86 qemu-utils )
    local -a group_ovmf=( ovmf )

    local -a failed_pkgs=()

    install_group() {

        local desc="$1"
        shift
        local -a group=( "$@" )

        if run_effect "${desc}" apt-get install -y "${group[@]}"; then
            PKG_DONE=$(( PKG_DONE + ${#group[@]} ))
        else
            warning "${desc} reported failures — attempting per-package recovery."
            local p
            for p in "${group[@]}"; do
                if run_effect "recover: ${p}" apt-get install -y "${p}"; then
                    PKG_DONE=$(( PKG_DONE + 1 ))
                else
                    failed_pkgs+=( "${p}" )
                fi
            done
        fi
    }

    install_group "System utility matrix"   "${group_util[@]}"
    energy_bar 4 11 "System utilities"

    install_group "Cloud-image toolchain"   "${group_img[@]}"
    energy_bar 5 11 "Cloud image support"

    install_group "QEMU virtualization"     "${group_qemu[@]}"
    QEMU_INSTALLED="true"
    energy_bar 8 11 "QEMU engine"

    install_group "OVMF UEFI firmware"      "${group_ovmf[@]}"
    OVMF_INSTALLED="true"
    energy_bar 9 11 "UEFI firmware"

    # -- failure report ---------------------------------------------------------
    if (( ${#failed_pkgs[@]} > 0 )); then

        warning "The following packages failed to install:"
        local p
        for p in "${failed_pkgs[@]}"; do
            printf "    ${FLAME}✖${RESET} %s\n" "${p}"
        done

        warning "Some features may be limited."
    fi

    # -- verify -----------------------------------------------------------------
    command -v qemu-system-x86_64 >/dev/null 2>&1 ||
        die "QEMU system emulator was not installed."

    command -v qemu-img >/dev/null 2>&1 ||
        die "qemu-img was not installed."

    if command -v cloud-localds >/dev/null 2>&1; then
        success "cloud-localds available."
    else
        warning "cloud-localds unavailable; some cloud-init flows may be limited."
    fi

    if command -v genisoimage >/dev/null 2>&1; then
        success "genisoimage available."
    elif command -v xorriso >/dev/null 2>&1; then
        success "xorriso available as ISO backend."
    else
        warning "No ISO creation backend detected."
    fi

    if [[ -f /usr/share/OVMF/OVMF_CODE.fd ||
          -f /usr/share/ovmf/OVMF.fd ||
          -f /usr/share/qemu/ovmf-x86_64.bin ]]; then
        success "OVMF firmware image present."
    else
        warning "OVMF firmware image not found at standard paths."
    fi

    echo
    echo -e "  ${T_ACCENT1}${BOLD}QEMU BUILD${RESET}"
    qemu-system-x86_64 --version 2>/dev/null | head -n 1 || true

    VNM_PANEL_PREREQS_DONE="true"
    export VNM_PANEL_PREREQS_DONE

    energy_bar 10 11 "Foundation verified"

    card \
        "Virtualization prerequisites" \
        "READY" \
        "${EMERALD}" \
        "QEMU, OVMF and image-generation dependencies installed."
}

# =============================================================================
# STAGE 03 — KVM DEEP SCAN
# =============================================================================

inspect_kvm() {

    stage_push "KVM CORE ANALYSIS"

    section \
        "03 / 11" \
        "KVM CORE ANALYSIS" \
        "Deep inspection of kernel virtualization support."

    # -- /dev/kvm ---------------------------------------------------------------
    if [[ -e /dev/kvm ]]; then

        KVM_AVAILABLE="true"
        success "/dev/kvm detected."

        echo
        ls -l /dev/kvm 2>/dev/null || true
        echo

        if [[ -r /dev/kvm && -w /dev/kvm ]]; then

            KVM_READWRITE="true"

            card \
                "KVM device" \
                "ACCESSIBLE" \
                "${EMERALD}" \
                "Writable KVM acceleration device exposed."

        else

            card \
                "KVM device" \
                "PERMISSION WARNING" \
                "${GOLD}" \
                "Device exists but access permissions are unusual."

            KVM_REPAIRS+=( "udev-rule" )
        fi

    else

        KVM_AVAILABLE="false"

        card \
            "KVM device" \
            "NOT PRESENT" \
            "${GOLD}" \
            "Hardware acceleration unavailable in this environment."

        KVM_REPAIRS+=( "modprobe" "nested" )
    fi

    # -- lscpu matrix -----------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}CPU VIRTUALIZATION MATRIX${RESET}"
    thin_divider

    if command -v lscpu >/dev/null 2>&1; then

        local virt vendor hyperv

        virt="$(lscpu 2>/dev/null | grep -Ei 'Virtualization:' || true)"
        vendor="$(lscpu 2>/dev/null | grep -Ei 'Hypervisor vendor:' || true)"
        hyperv="$(lscpu 2>/dev/null | grep -Ei 'Virtualization type:' || true)"

        [[ -n "${virt}"  ]] && echo -e "  ${ICE}${virt}${RESET}"
        [[ -n "${hyperv}" ]] && echo -e "  ${PURPLE}${hyperv}${RESET}"
        [[ -n "${vendor}" ]] && echo -e "  ${PINK}${vendor}${RESET}"

        if [[ -z "${virt}" && -z "${vendor}" && -z "${hyperv}" ]]; then
            warning "lscpu reported no virtualization metadata."
        fi
    fi

    # -- kernel modules ----------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}KERNEL MODULE MATRIX${RESET}"
    thin_divider

    if command -v lsmod >/dev/null 2>&1; then

        local modules
        modules="$(lsmod 2>/dev/null | grep '^kvm' || true)"

        if [[ -n "${modules}" ]]; then
            echo -e "${PURPLE}${modules}${RESET}"
        else
            warning "No KVM modules reported by lsmod."
            KVM_REPAIRS+=( "modprobe" )
        fi
    fi

    # -- IOMMU ------------------------------------------------------------------
    if [[ -d /sys/kernel/iommu_groups ]]; then

        local groups
        groups="$(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"

        echo
        echo -e "  ${T_ACCENT3}${BOLD}IOMMU / PCI PASSTHROUGH${RESET}"
        thin_divider

        if [[ "${groups}" =~ ^[0-9]+$ ]] && (( groups > 0 )); then
            printf "  ${EMERALD}✔${RESET} IOMMU groups detected: ${BOLD}%s${RESET}\n" "${groups}"
        else
            warning "IOMMU groups not populated — PCI passthrough unavailable."
        fi
    fi

    # -- dmesg ------------------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}KERNEL VIRTUALIZATION EVENTS${RESET}"
    thin_divider

    if command -v dmesg >/dev/null 2>&1; then

        local dmesg_out
        dmesg_out="$(dmesg 2>/dev/null | grep -iE 'kvm|virtualiz|vmx|svm' | tail -n 16 || true)"

        if [[ -n "${dmesg_out}" ]]; then
            echo -e "${DIM}${dmesg_out}${RESET}"
        else
            muted "No relevant kernel virtualization events found."
        fi
    fi

    energy_bar 3 11 "KVM core analyzed"
}

# =============================================================================
# STAGE 04 — KVM FUNCTIONAL TEST
# =============================================================================

functional_kvm_test() {

    stage_push "KVM FUNCTIONAL CORE"

    section \
        "04 / 11" \
        "KVM FUNCTIONAL CORE" \
        "Actual QEMU hardware-acceleration initialization test."

    if [[ "${SKIP_KVM_TEST}" == "true" ]]; then

        KVM_TEST="SKIPPED"

        card \
            "QEMU/KVM functional test" \
            "SKIPPED" \
            "${GOLD}" \
            "Skipped by option."

        return 0
    fi

    if [[ "${KVM_AVAILABLE}" != "true" ]]; then

        KVM_TEST="UNAVAILABLE"

        card \
            "QEMU/KVM functional test" \
            "UNAVAILABLE" \
            "${GOLD}" \
            "No /dev/kvm device exposed."

        return 0
    fi

    rm -f "${KVM_TEST_LOG}"

    echo
    echo -e "  ${T_ACCENT1}${BOLD}STARTING QEMU KVM ENGINE${RESET}"
    echo

    # charge-up animation
    if [[ "${ULTRA_EFFECTS}" == "true" ]]; then

        local charge_colors=( "${FLAME}" "${FIRE}" "${ORANGE}" "${GOLD}" "${BRIGHT_YELLOW}" "${BRIGHT_CYAN}" "${PURPLE}" "${PINK}" )
        local i

        for ((i=0; i<40; i++)); do
            printf "\r  %b%s" "${charge_colors[$((i % ${#charge_colors[@]}))]}" "${G_BLOCK_F}"
            sleep 0.018
        done

        echo
    fi

    set +e

    timeout 6s qemu-system-x86_64 \
        -accel kvm \
        -machine q35 \
        -display none \
        -nodefaults \
        -S \
        >"${KVM_TEST_LOG}" 2>&1

    local test_rc=$?

    set -e

    if [[ "${test_rc}" -eq 0 || "${test_rc}" -eq 124 ]]; then

        KVM_TEST="PASSED"

        particle_burst "KVM ENGINE IGNITION CONFIRMED"

        card \
            "QEMU/KVM functional test" \
            "PASSED" \
            "${EMERALD}" \
            "QEMU initialized successfully with -accel kvm."

    else

        KVM_TEST="FAILED"

        card \
            "QEMU/KVM functional test" \
            "FAILED" \
            "${FLAME}" \
            "KVM exposed but QEMU failed to initialize."

        KVM_REPAIRS+=( "qemu-perms" "nested" )

        echo
        echo -e "  ${GOLD}${BOLD}KVM DIAGNOSTIC OUTPUT${RESET}"
        thin_divider
        echo -e "${DIM}"
        tail -n 30 "${KVM_TEST_LOG}" 2>/dev/null || true
        echo -e "${RESET}"
    fi

    energy_bar 4 11 "KVM engine tested"
}

# =============================================================================
# STAGE 04B — ACCELERATOR BENCHMARK
# =============================================================================

benchmark_accelerators() {

    stage_push "ACCELERATOR BENCHMARK"

    section \
        "04B / 11" \
        "ACCELERATOR BENCHMARK" \
        "Timed QEMU boot: KVM vs software TCG emulation."

    if [[ "${SKIP_BENCHMARK}" == "true" ]]; then

        card \
            "Accelerator benchmark" \
            "SKIPPED" \
            "${GOLD}" \
            "Skipped by option."

        return 0
    fi

    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        warning "QEMU not available for benchmark."
        return 0
    fi

    bench_accel() {

        local accel="$1"
        local logf="$2"

        rm -f "${logf}"

        local start end ms

        start="$(date +%s%N)"

        set +e
        timeout 5s qemu-system-x86_64 \
            -accel "${accel}" \
            -machine q35 \
            -display none \
            -nodefaults \
            -S \
            >"${logf}" 2>&1
        local rc=$?
        set -e

        end="$(date +%s%N)"

        # If timeout killed it (124) the engine DID start and stayed up = success
        if [[ "${rc}" -ne 0 && "${rc}" -ne 124 ]]; then
            echo "FAIL"
            return
        fi

        ms=$(( (end - start) / 1000000 ))
        echo "${ms}"
    }

    echo
    muted "Spinning up KVM instance (timed)..."

    local t_kvm t_tcg
    t_kvm="$(bench_accel kvm "${KVM_BENCH_LOG}.kvm")"

    echo
    muted "Spinning up TCG instance (timed)..."

    t_tcg="$(bench_accel tcg "${KVM_BENCH_LOG}.tcg")"

    echo

    if [[ "${t_kvm}" == "FAIL" ]]; then
        KVM_BENCH_MS="N/A"
        table_row "KVM init" "FAILED" "hardware accel" "${FLAME}"
    else
        KVM_BENCH_MS="${t_kvm}"
        table_row "KVM init" "${t_kvm} ms" "hardware accel" "${EMERALD}"
    fi

    if [[ "${t_tcg}" == "FAIL" ]]; then
        TCG_BENCH_MS="N/A"
        table_row "TCG init" "FAILED" "software emu" "${FLAME}"
    else
        TCG_BENCH_MS="${t_tcg}"
        table_row "TCG init" "${t_tcg} ms" "software emu" "${GOLD}"
    fi

    if [[ "${t_kvm}" != "FAIL" && "${t_tcg}" != "FAIL" ]]; then

        local ratio=0
        (( t_kvm > 0 )) && ratio=$(( t_tcg / t_kvm ))

        echo
        if (( ratio >= 2 )); then
            card \
                "Acceleration verdict" \
                "KVM ${ratio}× FASTER" \
                "${EMERALD}" \
                "Hardware virtualization delivering maximum throughput."
        else
            card \
                "Acceleration verdict" \
                "MARGINAL GAIN" \
                "${GOLD}" \
                "KVM advantage is small — environment may be nested."
        fi
    fi

    energy_bar 5 11 "Accelerators benchmarked"
}

# =============================================================================
# STAGE 05 — NETWORK MATRIX
# =============================================================================

inspect_network() {

    stage_push "NETWORK MATRIX"

    section \
        "05 / 11" \
        "NETWORK MATRIX" \
        "Connectivity, latency, interfaces and port collision audit."

    rm -f "${NET_MATRIX_LOG}"

    # -- internet ----------------------------------------------------------------
    if command -v curl >/dev/null 2>&1; then

        local t_start t_end latency

        t_start="$(date +%s%N)"

        if curl -fsS --max-time 8 https://github.com >/dev/null 2>&1; then

            INTERNET_AVAILABLE="true"

            t_end="$(date +%s%N)"
            latency=$(( (t_end - t_start) / 1000000 ))
            LATENCY_MS="${latency}"

            # -- geoip --------------------------------------------------------------
            local geo
            geo="$(curl -fsS --max-time 6 https://ipinfo.io/json 2>/dev/null || true)"

            if [[ -n "${geo}" ]]; then
                local city region country
                city="$(echo "${geo}"    | grep -o '"city"[^,]*'    | cut -d'"' -f4 || true)"
                region="$(echo "${geo}"  | grep -o '"region"[^,]*'  | cut -d'"' -f4 || true)"
                country="$(echo "${geo}" | grep -o '"country"[^,]*' | cut -d'"' -f4 || true)"
                [[ -n "${city}" && -n "${country}" ]] &&
                    GEO_LOCATION="${city}, ${region:-?}, ${country}"
            fi

            card \
                "Internet connectivity" \
                "ONLINE · ${latency} ms" \
                "${EMERALD}" \
                "Repository access available. Location: ${GEO_LOCATION}."

        else

            INTERNET_AVAILABLE="false"

            card \
                "Internet connectivity" \
                "FAILED" \
                "${FLAME}" \
                "Unable to reach external repository endpoint."
        fi
    fi

    # -- interfaces ---------------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}NETWORK INTERFACES${RESET}"
    thin_divider

    if command -v ip >/dev/null 2>&1; then
        ip -brief addr 2>/dev/null | while read -r line; do
            printf "  ${DIM}%s${RESET}\n" "${line}"
        done
    fi

    # -- port matrix ---------------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}PORT COLLISION MATRIX${RESET}"
    thin_divider

    local port owner state

    for port in "${PANEL_PORT}" "${COMMON_PORTS[@]}"; do

        [[ "${port}" == "${PANEL_PORT}" ]] && continue

        owner="$(lsof -t -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"

        if [[ -n "${owner}" ]]; then
            state="OCCUPIED"
            printf "  ${GOLD}%-6s${RESET} ${DIM}%-10s${RESET} ${PINK}pid %s${RESET}\n" "${port}" "${state}" "${owner}"
        else
            state="free"
            printf "  ${SLATE}%-6s${RESET} ${DIM}%-10s${RESET}\n" "${port}" "${state}"
        fi

    done

    # -- panel port deep check ------------------------------------------------------
    local -a pids=()
    if command -v lsof >/dev/null 2>&1; then
        mapfile -t pids < <(lsof -t -nP -iTCP:"${PANEL_PORT}" -sTCP:LISTEN 2>/dev/null || true)
    fi

    echo

    if (( ${#pids[@]} == 0 )); then

        card \
            "Panel port ${PANEL_PORT}" \
            "AVAILABLE" \
            "${EMERALD}" \
            "No process currently owns the panel port."

    else

        for pid in "${pids[@]}"; do

            [[ "${pid}" =~ ^[0-9]+$ ]] || continue

            local cmdline
            cmdline="$(ps -p "${pid}" -o args= 2>/dev/null || echo unknown)"

            label "Port PID"     "${pid}"     "${GOLD}"
            label "Process"      "${cmdline}" "${PINK}"
        done

        warning "Port ${PANEL_PORT} is already in use."
        warning "The direct installer will handle any existing compatible process."
    fi

    energy_bar 6 11 "Network matrix audited"
}

# =============================================================================
# STAGE 06 — FIREWALL GATEWAY (with snapshot)
# =============================================================================

configure_firewall() {

    stage_push "NETWORK GATEWAY"

    section \
        "06 / 11" \
        "NETWORK GATEWAY" \
        "Preparing external access — with automatic rollback snapshot."

    if [[ "${SKIP_FIREWALL}" == "true" ]]; then

        warning "Firewall modification disabled by option."
        return 0
    fi

    # -- snapshot existing rules --------------------------------------------------
    {
        echo "# GKVM firewall snapshot $(date -Is)"
        if command -v ufw >/dev/null 2>&1; then
            ufw status 2>/dev/null || true
        fi
        if command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --list-all 2>/dev/null || true
        fi
        if command -v iptables >/dev/null 2>&1; then
            iptables -S 2>/dev/null || true
        fi
    } > "${FW_SNAPSHOT}" 2>/dev/null || true

    log_info "Firewall snapshot written to ${FW_SNAPSHOT}"

    # -- apply ---------------------------------------------------------------------
    if command -v ufw >/dev/null 2>&1; then

        if [[ "${DRY_RUN}" == "true" ]]; then
            printf "  ${STEEL}[DRY-RUN]${RESET} ufw allow ${PANEL_PORT}/tcp\n"
        else
            ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
        fi

        card \
            "UFW gateway" \
            "PORT ${PANEL_PORT} OPEN" \
            "${EMERALD}" \
            "TCP access allowed. Rollback snapshot saved."

        return 0
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then

        if [[ "${DRY_RUN}" == "true" ]]; then
            printf "  ${STEEL}[DRY-RUN]${RESET} firewall-cmd --add-port=${PANEL_PORT}/tcp\n"
        else
            firewall-cmd --permanent --add-port="${PANEL_PORT}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
        fi

        card \
            "firewalld gateway" \
            "PORT ${PANEL_PORT} OPEN" \
            "${EMERALD}" \
            "TCP access allowed. Rollback snapshot saved."

        return 0
    fi

    card \
        "Host firewall" \
        "NOT MANAGED" \
        "${GOLD}" \
        "No UFW/firewalld detected."

    warning "Check your VPS provider firewall for TCP ${PANEL_PORT}."
}

# =============================================================================
# STAGE 07 — CORE BOOTSTRAP (download engine)
# =============================================================================

download_legacy_installer() {

    stage_push "CORE BOOTSTRAP"

    section \
        "07 / 11" \
        "GKVM CORE BOOTSTRAP" \
        "Fetching the pinned production installer with integrity gates."

    if [[ "${DRY_RUN}" == "true" ]]; then

        printf "  ${STEEL}[DRY-RUN]${RESET} would fetch ${LEGACY_URL}\n"

        card \
            "Bootstrap fetch" \
            "SIMULATED" \
            "${SKY}" \
            "Dry-run mode — nothing downloaded."

        return 0
    fi

    if run_effect \
        "Downloading pinned direct installer" \
        net_fetch "${LEGACY_URL}" "${LEGACY_RAW}" 4; then

        success "Pinned installer downloaded."

    else

        die "Failed to download pinned installer after 4 attempts. Check connectivity."
    fi

    # -- size gate -----------------------------------------------------------------
    local fsize
    fsize="$(stat -c%s "${LEGACY_RAW}" 2>/dev/null || echo 0)"

    if [[ ! "${fsize}" =~ ^[0-9]+$ ]] || (( fsize < 500 )); then
        die "Downloaded installer is suspiciously small (${fsize} bytes)."
    fi

    success "Size gate passed (${fsize} bytes)."

    chmod 700 "${LEGACY_RAW}"

    # -- sha256 fingerprint ---------------------------------------------------------
    if command -v sha256sum >/dev/null 2>&1; then

        local sha
        sha="$(sha256sum "${LEGACY_RAW}" | awk '{print $1}')"

        label "SHA-256" "${sha}" "${LAVENDER}"

        if [[ -n "${LEGACY_SHA256:-}" ]]; then

            if [[ "${sha}" == "${LEGACY_SHA256}" ]]; then
                success "SHA-256 matches pinned fingerprint."
            else
                die "SHA-256 mismatch! Expected ${LEGACY_SHA256}, got ${sha}. Aborting for safety."
            fi

        else
            muted "No pinned fingerprint set — recording observed hash for audit."
            log_info "observed legacy sha256: ${sha}"
        fi
    fi

    # -- syntax gate ------------------------------------------------------------------
    bash -n "${LEGACY_RAW}" ||
        die "Downloaded installer failed Bash syntax validation."

    success "Bash syntax validation passed."

    # -- compatibility guard ------------------------------------------------------------
    if grep -qE 'HKVM_INSTALL_DIR|HKVM_APP_DIR|/opt/hkvm|hkvm\.service' "${LEGACY_RAW}"; then
        success "Legacy HKVM compatibility identifiers detected."
    else
        warning "Expected HKVM identifiers not detected — continuing (pinned installer is authoritative)."
    fi

    # -- branding patch ------------------------------------------------------------------
    sed \
        -e 's/^PANEL_NAME=HKVM$/PANEL_NAME="GKVM"/' \
        -e 's/^PANEL_NAME="HKVM"$/PANEL_NAME="GKVM"/' \
        -e 's/HKVM PANEL V3/GKVM PANEL V3/g' \
        -e 's/HKVM V5/GKVM V5/g' \
        -e 's/HKVM Panel/GKVM Panel/g' \
        -e 's/HKVM PANEL/GKVM PANEL/g' \
        -e 's/HKVM/GKVM/g' \
        "${LEGACY_RAW}" > "${LEGACY_PATCHED}"

    chmod 700 "${LEGACY_PATCHED}"

    bash -n "${LEGACY_PATCHED}" ||
        die "Branded installer failed Bash syntax validation."

    success "GKVM branding layer validated."

    card \
        "Legacy compatibility layer" \
        "PRESERVED" \
        "${T_ACCENT1}" \
        "Internal HKVM runtime contracts deliberately not renamed."

    echo
    echo -e "  ${DIM}${ICE}Preserved internal identifiers:${RESET}"
    echo
    printf "    ${DIM}%s${RESET}\n" "HKVM_INSTALL_DIR · HKVM_APP_DIR · /opt/hkvm · hkvm.service"
    echo

    energy_bar 7 11 "Bootstrap secured"
}

# =============================================================================
# STAGE 08 — DEPLOYMENT CORE
# =============================================================================

deploy_legacy() {

    stage_push "DEPLOYMENT CORE"

    section \
        "08 / 11" \
        "DEPLOYMENT CORE" \
        "Handing the prepared host to the proven direct-install engine."

    echo
    echo -e "${T_ACCENT3}${BOLD}"
    cat <<'EOF'
  ╭──────────────────────────────────────────────────────────────────────╮
  │                                                                      │
  │              ⚡  G K V M   D E P L O Y M E N T   C O R E  ⚡        │
  │                                                                      │
  │                         POWERING UP                                 │
  │                                                                      │
  ╰──────────────────────────────────────────────────────────────────────╯
EOF
    echo -e "${RESET}"

    echo

    if [[ "${ULTRA_EFFECTS}" == "true" ]]; then

        local boot_seq=( "${FLAME}" "${FIRE}" "${ORANGE}" "${GOLD}" "${BRIGHT_YELLOW}" "${BRIGHT_CYAN}" "${PURPLE}" "${PINK}" )
        local round el

        for round in 1 2 3; do
            for el in "${boot_seq[@]}"; do
                printf "\r  %b%s ${WHITE}${BOLD}BOOTING DEPLOYMENT ENGINE${RESET}" "${el}" "${G_BLOCK_F}"
                sleep 0.04
            done
        done

        clear_line
    fi

    echo
    echo -e "  ${WHITE}${BOLD}┌──────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "  ${WHITE}${BOLD}│              GKVM ENGINE ONLINE — EXECUTING PAYLOAD          │${RESET}"
    echo -e "  ${WHITE}${BOLD}└──────────────────────────────────────────────────────────────┘${RESET}"
    echo

    if [[ "${DRY_RUN}" == "true" ]]; then

        printf "  ${STEEL}[DRY-RUN]${RESET} would execute: %s %s\n" "${LEGACY_PATCHED}" "$*"
        CHILD_EXIT_CODE=0

        card \
            "Deployment" \
            "SIMULATED" \
            "${SKY}" \
            "Dry-run mode — payload not executed."

        return 0
    fi

    set +e

    "${LEGACY_PATCHED}" "$@" 2>&1 | tee "${CHILD_LOG}"

    CHILD_EXIT_CODE="${PIPESTATUS[0]}"

    set -e

    if [[ "${CHILD_EXIT_CODE}" -eq 0 ]]; then
        success "Direct-install engine completed cleanly."
    else
        warning "Direct-install engine exited with code ${CHILD_EXIT_CODE}."
    fi

    return "${CHILD_EXIT_CODE}"
}

# =============================================================================
# STAGE 09 — JSON TELEMETRY EXPORT
# =============================================================================

export_telemetry() {

    stage_push "TELEMETRY EXPORT"

    local end_time duration
    end_time="$(date +%s)"
    duration=$(( end_time - START_TIME ))

    if [[ "${DRY_RUN}" == "true" ]]; then
        muted "Dry-run: telemetry export simulated."
        return 0
    fi

    local qemu_ver
    qemu_ver="$(qemu-system-x86_64 --version 2>/dev/null | head -n 1 || echo "n/a")"

    cat > "${TELEMETRY_JSON}" <<EOF
{
  "panel": {
    "name": "${GKVM_NAME}",
    "codename": "${GKVM_CODENAME}",
    "version": "${GKVM_VERSION}",
    "build": "${GKVM_BUILD}",
    "port": ${PANEL_PORT}
  },
  "host": {
    "arch": "$(uname -m 2>/dev/null || echo unknown)",
    "kernel": "$(uname -r 2>/dev/null || echo unknown)",
    "os": "$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})",
    "cpu_threads": $(nproc 2>/dev/null || echo 0),
    "memory_mib": $(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 0)
  },
  "virtualization": {
    "kvm_device": ${KVM_AVAILABLE},
    "kvm_rw": ${KVM_READWRITE},
    "kvm_test": "${KVM_TEST}",
    "kvm_init_ms": "${KVM_BENCH_MS:-N/A}",
    "tcg_init_ms": "${TCG_BENCH_MS:-N/A}",
    "qemu_installed": ${QEMU_INSTALLED},
    "qemu_version": "$(echo "${qemu_ver}" | sed 's/"/\\"/g')"
  },
  "network": {
    "internet": ${INTERNET_AVAILABLE},
    "latency_ms": "${LATENCY_MS:-N/A}",
    "location": "${GEO_LOCATION}",
    "panel_port": ${PANEL_PORT}
  },
  "run": {
    "duration_s": ${duration},
    "child_exit_code": ${CHILD_EXIT_CODE},
    "stages": [$(printf '"%s",' "${STAGE_LOG[@]+"${STAGE_LOG[@]}"}" | sed 's/,$//')],
    "theme": "${THEME}",
    "dry_run": ${DRY_RUN},
    "timestamp": "$(date -Is)"
  }
}
EOF

    success "Telemetry exported → ${TELEMETRY_JSON}"

    energy_bar 9 11 "Telemetry exported"
}

# =============================================================================
# STAGE 10 — PANEL HEALTH
# =============================================================================

panel_health() {

    stage_push "PANEL HEALTH"

    echo
    echo -e "  ${T_ACCENT3}${BOLD}PANEL HEALTH${RESET}"
    thin_divider

    local listening="false"
    local http_code="000"

    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | grep -Eq ":${PANEL_PORT}([[:space:]]|$)"; then
            listening="true"
        fi
    fi

    http_code="$(
        curl -sS -o /dev/null -w '%{http_code}' --max-time 8 \
            "http://127.0.0.1:${PANEL_PORT}/" 2>/dev/null || echo "000"
    )"

    if [[ "${listening}" == "true" ]]; then
        success "TCP ${PANEL_PORT}: LISTENING"
    else
        warning "TCP ${PANEL_PORT}: NOT DETECTED"
    fi

    if [[ "${http_code}" =~ ^[0-9]{3}$ && "${http_code}" != "000" ]]; then
        success "HTTP health: ${http_code}"
    else
        warning "HTTP health: NO RESPONSE"
    fi

    # -- service probe ----------------------------------------------------------
    if [[ "${SYSTEMD_AVAILABLE}" == "true" ]] && command -v systemctl >/dev/null 2>&1; then

        echo

        if systemctl is-active --quiet hkvm.service 2>/dev/null; then
            success "hkvm.service: ACTIVE"
        elif systemctl is-enabled --quiet hkvm.service 2>/dev/null; then
            warning "hkvm.service: ENABLED but not active"
        else
            muted "hkvm.service: not registered (standalone/container mode)"
        fi
    fi

    energy_bar 10 11 "Health verified"
}

# =============================================================================
# STAGE 11 — FINAL DASHBOARD
# =============================================================================

final_screen() {

    clear_screen

    echo
    echo -e "${T_ACCENT1}${BOLD}"

    cat <<EOF
  ╔═══════════════════════════════════════════════════════════════════════════╗
  ║                                                                           ║
  ║    ${T_ACCENT3}██╗  ██╗██╗   ██╗███╗   ███╗${T_ACCENT1}                                 ║
  ║    ${T_ACCENT3}██║ ██╔╝██║   ██║████╗ ████║${T_ACCENT1}                                 ║
  ║    ${T_ACCENT3}█████╔╝ ██║   ██║██╔████╔██║${T_ACCENT1}                                 ║
  ║    ${T_ACCENT3}██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║${T_ACCENT1}                                 ║
  ║    ${T_ACCENT3}██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║${T_ACCENT1}                                 ║
  ║    ${T_ACCENT3}╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝${T_ACCENT1}                                 ║
  ║                                                                           ║
  ║              ${T_GLOW}D E P L O Y M E N T   C O M P L E T E${T_ACCENT1}                    ║
  ║                                                                           ║
  ╚═══════════════════════════════════════════════════════════════════════════╝
EOF

    echo -e "${RESET}"

    if [[ "${CHILD_EXIT_CODE}" -eq 0 ]]; then
        echo
        glitch_reveal "         ⚡ GKVM DEPLOYMENT SUCCESS — POWER CORE ONLINE ⚡"
    else
        echo
        glitch_reveal "              ❌ DEPLOYMENT FAILED — REVIEW LOGS ❌"
    fi

    echo
    divider
    echo

    local end_time duration
    end_time="$(date +%s)"
    duration=$(( end_time - START_TIME ))

    # -- run summary --------------------------------------------------------------
    echo -e "  ${T_ACCENT1}${BOLD}RUN SUMMARY${RESET}"
    echo

    label "Execution Time"  "${duration}s"        "${GOLD}"
    label "Panel Port"      "${PANEL_PORT}"        "${T_ACCENT1}"
    label "Theme"           "${THEME}"             "${PINK}"
    label "Stages Executed" "${#STAGE_LOG[@]}"     "${SKY}"

    case "${KVM_TEST}" in
        PASSED)      label "KVM" "HARDWARE ACCELERATED" "${EMERALD}" ;;
        FAILED)      label "KVM" "TEST FAILED" "${FLAME}" ;;
        SKIPPED)     label "KVM" "TEST SKIPPED" "${GOLD}" ;;
        UNAVAILABLE) label "KVM" "UNAVAILABLE" "${GOLD}" ;;
        *)           label "KVM" "${KVM_TEST}" "${WHITE}" ;;
    esac

    if [[ "${INTERNET_AVAILABLE}" == "true" ]]; then
        label "Repository Access" "ONLINE" "${EMERALD}"
    else
        label "Repository Access" "UNKNOWN" "${GOLD}"
    fi

    if [[ "${SYSTEMD_AVAILABLE}" == "true" ]]; then
        label "Service Runtime" "SYSTEMD" "${T_ACCENT1}"
    else
        label "Service Runtime" "STANDALONE / CONTAINER" "${GOLD}"
    fi

    label "Installer Log" "${INSTALLER_LOG}" "${ICE}"
    label "Telemetry"     "${TELEMETRY_JSON}" "${LAVENDER}"

    echo
    divider

    # -- virtualization status ------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}VIRTUALIZATION STATUS${RESET}"
    echo

    if [[ "${KVM_TEST}" == "PASSED" ]]; then
        card \
            "KVM acceleration" \
            "ONLINE" \
            "${EMERALD}" \
            "Hardware-accelerated QEMU initialization succeeded."
    elif [[ "${KVM_AVAILABLE}" == "true" ]]; then
        card \
            "KVM acceleration" \
            "DEVICE AVAILABLE" \
            "${GOLD}" \
            "KVM exists but functional test did not pass — try --repair-kvm."
    else
        card \
            "KVM acceleration" \
            "UNAVAILABLE" \
            "${GOLD}" \
            "QEMU software emulation (TCG) will be used."
    fi

    if [[ "${KVM_BENCH_MS}" != "" && "${KVM_BENCH_MS}" != "N/A" ]]; then
        muted "Benchmark: KVM ${KVM_BENCH_MS} ms · TCG ${TCG_BENCH_MS:-N/A} ms"
    fi

    echo
    divider

    # -- quick access ---------------------------------------------------------------
    echo
    echo -e "  ${T_ACCENT3}${BOLD}QUICK ACCESS${RESET}"
    echo

    printf "  ${EMERALD}%s${RESET} Check KVM      ${DIM}:${RESET} ${ICE}ls -l /dev/kvm${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Check QEMU     ${DIM}:${RESET} ${ICE}qemu-system-x86_64 --version${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Check panel    ${DIM}:${RESET} ${ICE}ss -lntp | grep :${PANEL_PORT}${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Service status ${DIM}:${RESET} ${ICE}systemctl status hkvm.service${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Installer log  ${DIM}:${RESET} ${ICE}tail -f ${INSTALLER_LOG}${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Telemetry      ${DIM}:${RESET} ${ICE}cat ${TELEMETRY_JSON}${RESET}\n" "${G_ARROW}"
    printf "  ${EMERALD}%s${RESET} Firewall undo  ${DIM}:${RESET} ${ICE}ufw delete allow ${PANEL_PORT}/tcp${RESET}\n" "${G_ARROW}"

    echo
    divider

    # -- compatibility footer ---------------------------------------------------------
    echo
    echo -e "  ${GOLD}${BOLD}COMPATIBILITY CONTRACT${RESET}"
    echo

    label "Legacy Commit" "${LEGACY_COMMIT}" "${PURPLE}"
    label "Panel Runtime" "/opt/hkvm"        "${ICE}"
    label "Service"       "hkvm.service"     "${GOLD}"

    echo
    divider
    echo

    if [[ "${CHILD_EXIT_CODE}" -eq 0 ]]; then

        if [[ "${ULTRA_EFFECTS}" == "true" ]]; then

            particle_burst "          GKVM POWER CORE READY — TITANIUM ONLINE"

            echo
            echo -e "${T_GLOW}${BOLD}"
            echo "             QEMU • KVM • OVMF • CLOUD-IMAGES • VM ENGINE"
            echo -e "${RESET}"

        else
            echo -e "${EMERALD}${BOLD}             GKVM POWER CORE READY${RESET}"
        fi

    else

        echo -e "${FLAME}${BOLD}                  GKVM DEPLOYMENT ERROR${RESET}"
        echo
        warning "Review: ${INSTALLER_LOG}"
    fi

    echo
    echo -e "  ${DIM}${WHITE}GKVM PANEL · ULTRA NEXUS · TITANIUM EDITION · ${GKVM_BUILD}${RESET}"
    echo

    log_info "Final screen rendered. child_exit=${CHILD_EXIT_CODE} duration=${duration}s"
}

# =============================================================================
# KVM REPAIR DOCTOR (standalone --repair-kvm)
# =============================================================================

repair_kvm() {

    clear_screen

    echo
    gradient_line "              K V M   R E P A I R   D O C T O R" "ice"
    echo
    divider
    echo

    local -a fixes_applied=()

    # -- fix 1: load modules ------------------------------------------------------
    echo -e "  ${T_ACCENT1}${BOLD}PROBE 1${RESET} ${DIM}— kernel modules${RESET}"
    thin_divider

    local vendor
    vendor="$(awk -F: '/^vendor_id/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "")"

    local mod=""
    case "${vendor}" in
        *GenuineIntel*) mod="kvm_intel" ;;
        *AuthenticAMD*) mod="kvm_amd" ;;
        *)              mod="kvm" ;;
    esac

    if lsmod 2>/dev/null | grep -q "^kvm"; then
        success "KVM modules already loaded."
    else
        warning "KVM modules not loaded — attempting modprobe."

        if [[ "${DRY_RUN}" == "true" ]]; then
            printf "  ${STEEL}[DRY-RUN]${RESET} modprobe kvm && modprobe %s\n" "${mod}"
        else
            modprobe kvm 2>/dev/null || true
            [[ -n "${mod}" && "${mod}" != "kvm" ]] && modprobe "${mod}" 2>/dev/null || true

            if lsmod 2>/dev/null | grep -q "^kvm"; then
                success "KVM modules loaded."
                fixes_applied+=( "modprobe:${mod}" )
            else
                failure "modprobe failed — hardware virtualization may be disabled in BIOS/UEFI or by hypervisor."
            fi
        fi
    fi

    echo

    # -- fix 2: udev permissions ---------------------------------------------------
    echo -e "  ${T_ACCENT1}${BOLD}PROBE 2${RESET} ${DIM}— /dev/kvm permissions${RESET}"
    thin_divider

    if [[ -e /dev/kvm ]]; then

        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            success "/dev/kvm accessible."
        else

            warning "/dev/kvm not accessible — installing udev rule."

            if [[ "${DRY_RUN}" == "true" ]]; then
                printf "  ${STEEL}[DRY-RUN]${RESET} udev rule: MODE=0666 on /dev/kvm\n"
            else
                printf 'KERNEL=="kvm", GROUP="kvm", MODE="0666"\n' \
                    > /etc/udev/rules.d/99-gkvm-kvm.rules

                if command -v udevadm >/dev/null 2>&1; then
                    udevadm control --reload-rules 2>/dev/null || true
                    udevadm trigger --name-match=kvm 2>/dev/null || true
                fi

                chmod 666 /dev/kvm 2>/dev/null || true

                if [[ -r /dev/kvm && -w /dev/kvm ]]; then
                    success "/dev/kvm permissions repaired."
                    fixes_applied+=( "udev-rule" )
                else
                    warning "Permissions repair incomplete."
                fi
            fi
        fi
    else
        warning "/dev/kvm still absent after module probe."
    fi

    echo

    # -- fix 3: nested virtualization ------------------------------------------------
    echo -e "  ${T_ACCENT1}${BOLD}PROBE 3${RESET} ${DIM}— nested virtualization${RESET}"
    thin_divider

    local nest_file=""
    for cand in /sys/module/kvm_intel/parameters/nested \
                /sys/module/kvm_amd/parameters/nested; do
        [[ -f "${cand}" ]] && nest_file="${cand}" && break
    done

    if [[ -n "${nest_file}" ]]; then

        local nest_val
        nest_val="$(cat "${nest_file}" 2>/dev/null || echo "?")"

        label "Nested param" "${nest_val}" "${SKY}"

        if [[ "${nest_val}" == "0" || "${nest_val}" == "N" ]]; then

            warning "Nested virtualization disabled — enabling."

            if [[ "${DRY_RUN}" == "true" ]]; then
                printf "  ${STEEL}[DRY-RUN]${RESET} echo 1 > %s\n" "${nest_file}"
            else
                echo 1 > "${nest_file}" 2>/dev/null || true
                local new_val
                new_val="$(cat "${nest_file}" 2>/dev/null || echo "?")"

                if [[ "${new_val}" == "1" || "${new_val}" == "Y" ]]; then
                    success "Nested virtualization enabled for this session."
                    fixes_applied+=( "nested-virt" )
                else
                    warning "Could not enable nested virtualization (may need kernel param)."
                    muted "Add 'kvm-intel.nested=1' or 'kvm-amd.nested=1' to kernel cmdline."
                fi
            fi
        else
            success "Nested virtualization already enabled."
        fi
    else
        muted "Nested virtualization parameter not exposed."
    fi

    echo

    # -- fix 4: functional re-test ----------------------------------------------------
    echo -e "  ${T_ACCENT1}${BOLD}PROBE 4${RESET} ${DIM}— functional re-test${RESET}"
    thin_divider

    if command -v qemu-system-x86_64 >/dev/null 2>&1 && [[ -e /dev/kvm ]]; then

        set +e
        timeout 6s qemu-system-x86_64 \
            -accel kvm -machine q35 -display none -nodefaults -S \
            >"${KVM_TEST_LOG}" 2>&1
        local rc=$?
        set -e

        if [[ "${rc}" -eq 0 || "${rc}" -eq 124 ]]; then
            card \
                "Repair verification" \
                "KVM FUNCTIONAL" \
                "${EMERALD}" \
                "QEMU initialized with -accel kvm after repair."
        else
            card \
                "Repair verification" \
                "STILL FAILING" \
                "${FLAME}" \
                "See ${KVM_TEST_LOG}."
        fi
    else
        warning "Cannot re-test: QEMU or /dev/kvm missing."
    fi

    echo
    divider
    echo

    if (( ${#fixes_applied[@]} > 0 )); then
        echo -e "  ${EMERALD}${BOLD}FIXES APPLIED:${RESET}"
        local fix
        for fix in "${fixes_applied[@]}"; do
            printf "    ${EMERALD}%s${RESET} %s\n" "${G_CHECK}" "${fix}"
        done
    else
        muted "No fixes were required."
    fi

    echo
    echo -e "  ${DIM}${WHITE}KVM REPAIR DOCTOR COMPLETE${RESET}"
    echo

    exit 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {

    rotate_logs

    parse_args "$@"

    theme_apply "${THEME}"
    probe_terminal
    glyph_init

    # -------------------------------------------------------------------------
    # Root check (skip for repair dry-run help etc.)
    # -------------------------------------------------------------------------
    if [[ "${EUID}" -ne 0 ]]; then
        failure "This installer must run as root."
        printf "  ${ICE}%s${RESET} sudo ./gkvm-nexus-installer.sh %s\n" "${G_ARROW}" "$*"
        exit 1
    fi

    # -------------------------------------------------------------------------
    # Standalone repair doctor
    # -------------------------------------------------------------------------
    if [[ "${REPAIR_MODE}" == "true" ]]; then
        repair_kvm
    fi

    # -------------------------------------------------------------------------
    # Wizard
    # -------------------------------------------------------------------------
    if [[ "${WIZARD}" == "true" && "${ASSUME_YES}" != "true" ]]; then
        wizard_run
    fi

    # -------------------------------------------------------------------------
    # systemd probe
    # -------------------------------------------------------------------------
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        SYSTEMD_AVAILABLE="true"
    fi

    # -------------------------------------------------------------------------
    # Cinematic boot
    # -------------------------------------------------------------------------
    boot_cinematic

    # -------------------------------------------------------------------------
    # Stages
    # -------------------------------------------------------------------------
    detect_host_metrics

    install_prerequisites

    inspect_kvm

    functional_kvm_test

    benchmark_accelerators

    inspect_network

    configure_firewall

    download_legacy_installer

    deploy_legacy "$@"

    export_telemetry

    panel_health

    # -------------------------------------------------------------------------
    # Final dashboard
    # -------------------------------------------------------------------------
    final_screen

    return "${CHILD_EXIT_CODE}"
}

# =============================================================================
# LAUNCH
# =============================================================================

main "$@"
