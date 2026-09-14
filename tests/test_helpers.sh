#!/usr/bin/env bash
# test_helpers.sh - shared fixtures for the bash test suite. No real system
# state (real Steam, real pacman, real systemd) is ever touched: every test
# runs inside its own temp $HOME with SRWF_CONFIG_DIR pointed at a temp dir.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"

# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/detect.sh
source "$LIB_DIR/detect.sh"
# shellcheck source=lib/steam.sh
source "$LIB_DIR/steam.sh"
# shellcheck source=lib/backup.sh
source "$LIB_DIR/backup.sh"
# shellcheck source=lib/deps.sh
source "$LIB_DIR/deps.sh"
# shellcheck source=lib/pipewire.sh
source "$LIB_DIR/pipewire.sh"
# shellcheck source=lib/coredump.sh
source "$LIB_DIR/coredump.sh"
# shellcheck source=lib/wrapper.sh
source "$LIB_DIR/wrapper.sh"
# shellcheck source=lib/watcher.sh
source "$LIB_DIR/watcher.sh"
# shellcheck source=lib/smoketest.sh
source "$LIB_DIR/smoketest.sh"
# shellcheck source=lib/doctor.sh
source "$LIB_DIR/doctor.sh"

T_TOTAL=0
T_FAILED=0

t_run() {
    local name="$1"
    T_TOTAL=$((T_TOTAL+1))
    local out rc
    out=$( ( "$name" ) 2>&1 )
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
        printf '  ok   %s\n' "$name"
    else
        T_FAILED=$((T_FAILED+1))
        printf '  FAIL %s\n' "$name"
        sed 's/^/       /' <<<"$out"
    fi
}

t_summary() {
    echo ""
    echo "$((T_TOTAL - T_FAILED))/$T_TOTAL tests passed"
    [[ "$T_FAILED" -eq 0 ]]
}

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "assert_eq failed: expected [$expected] got [$actual] $msg" >&2
        return 1
    fi
}

assert_true() {
    "$@" || { echo "assert_true failed: $*" >&2; return 1; }
}

assert_false() {
    if "$@"; then
        echo "assert_false failed (command succeeded): $*" >&2
        return 1
    fi
    return 0
}

assert_file_exists() {
    [[ -e "$1" ]] || { echo "assert_file_exists failed: $1" >&2; return 1; }
}

assert_file_missing() {
    [[ ! -e "$1" ]] || { echo "assert_file_missing failed: $1" >&2; return 1; }
}

# make_fake_elf <path> <tag>
# Writes a file starting with the ELF magic bytes (enough for is_elf()) plus
# a distinguishing tag, so tests can tell fake binaries apart by content/hash.
make_fake_elf() {
    local path="$1" tag="$2"
    printf '\x7fELF' > "$path"
    printf '%s-%s' "$tag" "$RANDOM$RANDOM" >> "$path"
    chmod +x "$path"
}

make_fake_foreign_script() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
# some other tool's hand-rolled wrapper, not ours
exec "$(dirname "$0")/streaming_client.real" "$@"
EOF
    chmod +x "$path"
}

# new_mock_env - sets HOME and SRWF_CONFIG_DIR to fresh temp dirs, creates a
# minimal Steam layout with a pristine fake streaming_client ELF, and forces
# the NVIDIA+Wayland workaround decision so tests don't need real hardware.
# Prints the new HOME on stdout.
new_mock_env() {
    local tmp; tmp=$(mktemp -d)
    export HOME="$tmp/home"
    export SRWF_CONFIG_DIR="$tmp/home/.config/steam-remoteplay-wayland-fix"
    export SRWF_FORCE_WORKAROUND="${MOCK_FORCE_WORKAROUND:-1}"
    export SRWF_ASSUME_YES=1
    CONFIG_DIR="$SRWF_CONFIG_DIR"
    STATE_FILE="$CONFIG_DIR/state.env"
    BACKUP_DIR="$CONFIG_DIR/backups"
    LOG_DIR="$CONFIG_DIR/logs"
    # shellcheck disable=SC2034  # read by lib/wrapper.sh
    ENV_CONF="$CONFIG_DIR/env.conf"
    # shellcheck disable=SC2034  # read by lib/backup.sh and tests/test_backup.sh
    MANIFEST="$BACKUP_DIR/manifest.tsv"
    SRWF_WARN_COUNT=0; SRWF_FAIL_COUNT=0; SRWF_FIX_COUNT=0

    mkdir -p "$HOME/.local/share/Steam/ubuntu12_64"
    make_fake_elf "$HOME/.local/share/Steam/ubuntu12_64/streaming_client" "original"
    echo "$HOME"
}
