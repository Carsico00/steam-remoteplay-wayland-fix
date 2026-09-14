#!/usr/bin/env bash
# test_backup.sh - the verifiable backup/restore mechanism in isolation.

test_backup_create_records_manifest_fields() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    local dst; dst=$(backup_create pristine-real "$client")

    assert_file_exists "$dst"
    assert_eq "$(sha256_of "$client")" "$(sha256_of "$dst")"
    grep -q "pristine-real" "$MANIFEST" || { echo "manifest missing entry"; return 1; }
    grep -q "$dst" "$MANIFEST" || { echo "manifest missing backup path"; return 1; }
}

test_backup_latest_returns_newest_of_several() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    backup_create pristine-real "$client" >/dev/null
    sleep 1
    make_fake_elf "$client" "second-version"
    local second; second=$(backup_create pristine-real "$client")

    assert_eq "$second" "$(backup_latest pristine-real)"
}

test_restore_verifies_hash_and_sets_exec_bit() {
    new_mock_env >/dev/null
    local client="$HOME/.local/share/Steam/ubuntu12_64/streaming_client"
    backup_create pristine-real "$client" >/dev/null

    local dest="$HOME/restored_bin"
    restore_from_backup pristine-real "$dest" || return 1
    assert_eq "$(sha256_of "$client")" "$(sha256_of "$dest")"
    [[ -x "$dest" ]] || { echo "restored file not executable"; return 1; }
}

test_restore_with_no_backup_fails_cleanly() {
    new_mock_env >/dev/null
    assert_false restore_from_backup pristine-real "$HOME/nowhere"
}

test_backup_has_reflects_presence() {
    new_mock_env >/dev/null
    assert_false backup_has pristine-real
    backup_create pristine-real "$HOME/.local/share/Steam/ubuntu12_64/streaming_client" >/dev/null
    assert_true backup_has pristine-real
}
