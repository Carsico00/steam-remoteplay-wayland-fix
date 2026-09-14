#!/usr/bin/env bash
# test_coredump.sh - crash-signature classification against synthetic
# coredumpctl output, so it doesn't depend on triggering a real crash.

_MATCHING_BT='           PID: 1234 (streaming_clien)
       Storage: present
Stack trace of thread 1234:
#0  0x0 pthread_mutex_lock (libc.so.6 + 0x0)
#1  0x0 wl_proxy_create_wrapper (libwayland-client.so.0 + 0x0)
#2  0x0 n/a (libnvidia-egl-wayland.so.1 + 0x0)
#3  0x0 n/a (libEGL_nvidia.so.0 + 0x0)
#4  0x0 n/a (libEGL.so.1 + 0x0)
#5  0x0 n/a (libSDL3.so.0 + 0x0)'

_UNRELATED_BT='           PID: 5678 (something)
Stack trace of thread 5678:
#0  0x0 malloc (libc.so.6 + 0x0)
#1  0x0 some_function (libfoo.so.1 + 0x0)'

test_classifies_known_signature() {
    coredumpctl() {
        case "$1" in
            info) echo "$_MATCHING_BT" ;;
        esac
    }
    assert_eq "remoteplay-wayland-nvidia-egl-crash" "$(coredump_classify 1234)"
}

test_classifies_unrelated_crash_as_other() {
    coredumpctl() {
        case "$1" in
            info) echo "$_UNRELATED_BT" ;;
        esac
    }
    assert_eq "other-crash" "$(coredump_classify 5678)"
}

test_most_recent_match_finds_matching_pid() {
    coredumpctl() {
        case "$1" in
            list) printf 'Mon 2026-01-01 00:00:00 CET 5678 1000 1000 SIGSEGV present /x/something\nMon 2026-01-02 00:00:00 CET 1234 1000 1000 SIGSEGV present /x/streaming_client\n' ;;
            info)
                if [[ "$2" == "1234" ]]; then echo "$_MATCHING_BT"; else echo "$_UNRELATED_BT"; fi
                ;;
        esac
    }
    local result; result=$(coredump_most_recent_signature_match)
    [[ "$result" == yes:1234:* ]] || { echo "expected yes:1234:*, got $result"; return 1; }
}

test_no_coredumpctl_available_is_handled() {
    unset -f coredumpctl 2>/dev/null
    command() {
        if [[ "$1" == "-v" && "$2" == "coredumpctl" ]]; then return 1; fi
        builtin command "$@"
    }
    assert_eq "no" "$(coredump_most_recent_signature_match)"
    unset -f command
}
