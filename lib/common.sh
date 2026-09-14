#!/usr/bin/env bash
# common.sh - shared constants, logging and small helpers.
# Sourced by every other lib/*.sh file and by bin/steam-remoteplay-wayland-fix.

set -u

APP_NAME="steam-remoteplay-wayland-fix"
APP_VERSION="0.1.0"

CONFIG_DIR="${SRWF_CONFIG_DIR:-$HOME/.config/steam-remoteplay-wayland-fix}"
STATE_FILE="$CONFIG_DIR/state.env"
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_DIR="$CONFIG_DIR/logs"
ENV_CONF="$CONFIG_DIR/env.conf"

# Marker embedded in every wrapper we generate. Used to recognize "this file
# was written by us" vs. a foreign script or Steam's original ELF binary, and
# to detect Steam having overwritten our wrapper on update.
WRAPPER_MARKER="# managed-by: ${APP_NAME}"
WRAPPER_VERSION_TAG_PREFIX="# wrapper-version:"

# ---- terminal colors (disabled when not a tty or NO_COLOR is set) ----
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_BOLD=$'\033[1m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

# doctor/status accumulate counts so callers can derive an exit code.
SRWF_WARN_COUNT=0
SRWF_FAIL_COUNT=0
SRWF_FIX_COUNT=0

log_ok()   { [[ "${SRWF_QUIET:-0}" == "1" ]] || printf '%s[OK]%s   %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
log_info() { [[ "${SRWF_QUIET:-0}" == "1" ]] || printf '%s[INFO]%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
log_warn() { printf '%s[WARN]%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; SRWF_WARN_COUNT=$((SRWF_WARN_COUNT+1)); }
log_fail() { printf '%s[FAIL]%s %s\n'   "$C_RED"    "$C_RESET" "$1"; SRWF_FAIL_COUNT=$((SRWF_FAIL_COUNT+1)); }
log_fix()  { printf '%s[FIX]%s  %s\n'   "$C_BOLD"   "$C_RESET" "$1"; SRWF_FIX_COUNT=$((SRWF_FIX_COUNT+1)); }
log_line() { [[ "${SRWF_QUIET:-0}" == "1" ]] || printf '%s\n' "$1"; }

die() {
    printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
    exit "${2:-1}"
}

ensure_dirs() {
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR" "$LOG_DIR"
}

sha256_of() {
    [[ -f "$1" ]] || { echo ""; return 1; }
    sha256sum "$1" | awk '{print $1}'
}

is_elf() {
    [[ -f "$1" ]] || return 1
    local magic
    magic=$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [[ "$magic" == "7f454c46" ]]
}

has_marker() {
    [[ -f "$1" ]] || return 1
    grep -qF "$WRAPPER_MARKER" "$1" 2>/dev/null
}

# key=value state store, one entry per line, no external deps.
state_set() {
    ensure_dirs
    local key="$1" val="$2"
    touch "$STATE_FILE"
    local tmp
    tmp=$(mktemp "$STATE_FILE.XXXXXX")
    grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_get() {
    local key="$1"
    [[ -f "$STATE_FILE" ]] || return 0
    grep "^${key}=" "$STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-
}

confirm() {
    local prompt="$1"
    if [[ "${SRWF_ASSUME_YES:-0}" == "1" ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        return 1
    fi
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}
