#!/usr/bin/env bash
# test_cli_integration.sh - drives the real bin/steam-remoteplay-wayland-fix
# executable as a subprocess (not sourced), to catch argument-parsing and
# wiring bugs the unit tests above can't see. Dependency installation
# (pacman) is never exercised here: workaround is forced on but the 32-bit
# EGL check path is short-circuited by stubbing eglinfo32 as "ok" so no
# install_pkg call is ever reached.

_CLI="$PROJECT_DIR/bin/steam-remoteplay-wayland-fix"

_cli_mock_env() {
    local tmp; tmp=$(mktemp -d)
    export HOME="$tmp/home"
    mkdir -p "$HOME/.local/share/Steam/ubuntu12_64"
    make_fake_elf "$HOME/.local/share/Steam/ubuntu12_64/streaming_client" "original"

    local bindir="$tmp/bin"
    mkdir -p "$bindir"
    cat > "$bindir/eglinfo32" <<EOF
#!/bin/bash
cat "$TESTS_DIR/fixtures/eglinfo_nvidia_ok.txt"
EOF
    chmod +x "$bindir/eglinfo32"
    export PATH="$bindir:$PATH"
    export SRWF_FORCE_WORKAROUND=1
    export SRWF_ASSUME_YES=1
    echo "$HOME"
}

test_cli_install_then_status_then_uninstall() {
    _cli_mock_env >/dev/null

    "$_CLI" install -y >/tmp/cli_install.out 2>&1 || { cat /tmp/cli_install.out; return 1; }
    grep -q "Install complete" /tmp/cli_install.out || { cat /tmp/cli_install.out; return 1; }

    "$_CLI" status >/tmp/cli_status.out 2>&1
    grep -q "Wrapper status:        active" /tmp/cli_status.out || { cat /tmp/cli_status.out; return 1; }

    "$_CLI" uninstall >/tmp/cli_uninstall.out 2>&1 || { cat /tmp/cli_uninstall.out; return 1; }
    "$_CLI" status >/tmp/cli_status2.out 2>&1
    grep -q "Wrapper status:        not-installed" /tmp/cli_status2.out || { cat /tmp/cli_status2.out; return 1; }
}

test_cli_repair_is_idempotent_three_times() {
    _cli_mock_env >/dev/null
    "$_CLI" install -y >/dev/null 2>&1 || return 1

    for _ in 1 2 3; do
        "$_CLI" repair >/tmp/cli_repair.out 2>&1
        local rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 1 ]] || { echo "repair exit $rc"; cat /tmp/cli_repair.out; return 1; }
    done
    "$_CLI" status >/tmp/cli_status3.out 2>&1
    grep -q "Wrapper status:        active" /tmp/cli_status3.out || { cat /tmp/cli_status3.out; return 1; }
}

test_cli_doctor_exit_code_reflects_findings() {
    local tmp; tmp=$(mktemp -d)
    export HOME="$tmp/home"   # no Steam at all -> at least one FAIL expected
    export SRWF_FORCE_WORKAROUND=0
    "$_CLI" doctor >/tmp/cli_doctor.out 2>&1
    local rc=$?
    [[ "$rc" -eq 2 ]] || { echo "expected exit 2 (FAIL present), got $rc"; cat /tmp/cli_doctor.out; return 1; }
}

test_cli_unknown_command_fails() {
    if "$_CLI" this-is-not-a-command >/tmp/cli_unknown.out 2>&1; then
        echo "expected non-zero exit for unknown command"; return 1
    fi
    grep -qi "unknown command" /tmp/cli_unknown.out || { cat /tmp/cli_unknown.out; return 1; }
}

test_cli_help_runs_without_steam() {
    local tmp; tmp=$(mktemp -d)
    export HOME="$tmp/home"
    "$_CLI" help >/tmp/cli_help.out 2>&1 || { cat /tmp/cli_help.out; return 1; }
    grep -q "Usage:" /tmp/cli_help.out
}
