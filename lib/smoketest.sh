#!/usr/bin/env bash
# smoketest.sh - `steam-remoteplay-wayland-fix test`
#
# Runs a structurally-valid but non-functional streaming_client invocation
# (dummy steamid/gameid/relay/cert) through the *installed wrapper*, which is
# enough to reach the EGL/graphics initialization code path where the crash
# in Problems 1/2/6 occurred, without needing a real Remote Play session or a
# second client device. It intentionally does NOT claim to validate the full
# video/audio/controller pipeline - see docs/diagnostics.md.

smoketest_run() {
    local client root sdr tmp_sdr=""
    client=$(streaming_client_path 2>/dev/null) || { log_fail "Steam installation not found."; return 1; }
    [[ -e "$client" ]] || { log_fail "streaming_client not found (open Remote Play from Steam once first)."; return 1; }

    root=$(detect_steam_root)
    sdr="$root/appcache/sdr_config.txt"
    if [[ ! -f "$sdr" ]]; then
        tmp_sdr=$(mktemp)
        sdr="$tmp_sdr"
    fi

    ensure_dirs
    local before after rc log="$LOG_DIR/smoketest-last.log"
    before=$(coredump_list_streaming_client 2>/dev/null | wc -l)

    log_info "Running a synthetic invocation through the installed wrapper (dummy session, no real relay/game)..."
    timeout 8 "$client" \
        --universe 1 --realm 1 --steamid 0 --gameid 0 --appid 0 \
        --server 0.0.0.0:0 --transport k_EStreamTransportSDR --relay 127.0.0.1:1 \
        --cert AAAA --sdr_config "$sdr" --settingsdata 00 \
        >"$log" 2>&1
    rc=$?
    [[ -n "$tmp_sdr" ]] && rm -f "$tmp_sdr"

    if [[ "$rc" -ge 128 ]]; then
        local sig=$((rc - 128))
        log_fail "streaming_client crashed (signal $sig) during the smoke test. See $log"
        return 1
    fi

    after=$(coredump_list_streaming_client 2>/dev/null | wc -l)
    if [[ "$after" -gt "$before" ]]; then
        log_fail "A new coredump for streaming_client appeared during the smoke test."
        return 1
    fi

    log_ok "streaming_client survived graphics/EGL initialization (exit code $rc, no new coredump)."
    log_info "This is a synthetic smoke test of the crash this project fixes, not a full Remote Play"
    log_info "session: no real relay handshake, no game launch, no video/audio/controller check."
    log_info "Confirm those manually: Steam -> Remote Play -> connect -> play."
    return 0
}
