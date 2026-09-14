#!/usr/bin/env bash
# test_wrapper.sh - install/uninstall/repair state machine, backups, recursion.

test_fresh_install_backs_up_and_wraps() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    local orig_hash; orig_hash=$(sha256_of "$client")

    install_wrapper || return 1

    assert_file_exists "$real"
    assert_eq "$orig_hash" "$(sha256_of "$real")" "real should be untouched original"
    assert_true has_marker "$client"
    assert_eq "active" "$(wrapper_status)"
    assert_true backup_has pristine-real
}

test_install_is_idempotent() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    local hash1; hash1=$(sha256_of "$real")

    install_wrapper || return 1
    install_wrapper || return 1

    assert_eq "$hash1" "$(sha256_of "$real")" "second/third install must not touch .real"
    assert_eq "active" "$(wrapper_status)"
}

test_no_recursion_exec_target() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    # the wrapper must never reference itself as the exec target
    assert_false [ "$(readlink -f "$client")" = "$(readlink -f "$real")" ]
    grep -q 'exec "\$_real"' "$client" || { echo "wrapper missing exec of \$_real"; return 1; }
}

test_steam_update_overwrites_wrapper_then_repair() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"

    # Simulate a Steam update: it doesn't know about our wrapper, it just
    # drops a brand new original binary at the same path.
    make_fake_elf "$client" "updated-by-steam"
    local new_hash; new_hash=$(sha256_of "$client")

    assert_eq "stale-overwritten" "$(wrapper_status)"

    install_wrapper || return 1

    assert_eq "active" "$(wrapper_status)"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    assert_eq "$new_hash" "$(sha256_of "$real")" "the NEW Steam binary must become the new .real"
}

test_corrupt_wrapper_missing_real_is_detected() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    rm -f "$real"
    assert_eq "corrupt" "$(wrapper_status)"
}

test_repair_restores_from_backup_after_corruption() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    local orig_hash; orig_hash=$(sha256_of "$real")
    rm -f "$real"

    assert_eq "corrupt" "$(wrapper_status)"
    restore_from_backup pristine-real "$client" || return 1
    assert_eq "$orig_hash" "$(sha256_of "$client")"
}

test_corrupt_backup_fails_restore_safely() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    local backup; backup=$(backup_latest pristine-real)
    echo "corrupted" > "$backup"

    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    assert_false restore_from_backup pristine-real "$client"
}

test_foreign_wrapper_backed_up_and_replaced() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"

    # Someone else's manual wrapper is already sitting there, original preserved as .real.
    mv "$client" "$real"
    make_fake_foreign_script "$client"

    assert_eq "foreign" "$(wrapper_status)"

    install_wrapper || return 1

    assert_true has_marker "$client"
    assert_eq "active" "$(wrapper_status)"
    grep -q 'foreign-wrapper' "$BACKUP_DIR/manifest.tsv" || { echo "foreign wrapper not recorded in manifest"; return 1; }
}

test_ambiguous_two_different_originals_refuses() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    make_fake_elf "$real" "different-original"
    local before; before=$(sha256_of "$client")

    assert_false install_wrapper
    assert_eq "$before" "$(sha256_of "$client")" "must not modify streaming_client on ambiguous state"
}

test_steam_not_installed() {
    local tmp; tmp=$(mktemp -d)
    export HOME="$tmp/home"
    export SRWF_CONFIG_DIR="$tmp/home/.config/steam-remoteplay-wayland-fix"
    CONFIG_DIR="$SRWF_CONFIG_DIR"; BACKUP_DIR="$CONFIG_DIR/backups"
    mkdir -p "$HOME"
    assert_false install_wrapper
}

test_uninstall_restores_original_state() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local real="$HOME/.local/share/Steam/ubuntu12_64/streaming_client.real"
    local orig_hash; orig_hash=$(sha256_of "$client")

    install_wrapper || return 1
    uninstall_wrapper || return 1

    assert_eq "$orig_hash" "$(sha256_of "$client")"
    assert_file_missing "$real"
    assert_file_missing "$ENV_CONF"
}

test_uninstall_is_idempotent() {
    new_mock_env >/dev/null
    install_wrapper || return 1
    uninstall_wrapper || return 1
    uninstall_wrapper || return 1
    uninstall_wrapper || return 1
    assert_eq "not-installed" "$(wrapper_status)"
}

test_repeated_install_uninstall_cycle() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local orig_hash; orig_hash=$(sha256_of "$client")
    for _ in 1 2 3; do
        install_wrapper || return 1
        assert_eq "active" "$(wrapper_status)"
        uninstall_wrapper || return 1
        assert_eq "$orig_hash" "$(sha256_of "$client")"
    done
}

test_workaround_not_needed_is_noop() {
    MOCK_FORCE_WORKAROUND=0 new_mock_env >/dev/null
    assert_false needs_nvidia_wayland_workaround
    # install_wrapper itself doesn't gate on this (cmd_install does); verify
    # the gating flag is readable and consistent for the CLI layer to use.
}
