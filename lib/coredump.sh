#!/usr/bin/env bash
# coredump.sh - recognize the Steam Remote Play Wayland/NVIDIA EGL crash
# signature in systemd-coredump, without depending on one exact backtrace or
# streaming_client version.

# Any one coredump entry whose executable path ends in streaming_client or
# streaming_client.real, regardless of Steam build.
coredump_list_streaming_client() {
    command -v coredumpctl >/dev/null 2>&1 || return 1
    coredumpctl list --no-pager 2>/dev/null | grep -E 'streaming_client(\.real)?[[:space:]]*$'
}

# Frame fragments that, together, identify this specific crash class. We
# require at least the EGL/Wayland/NVIDIA chain, not just "SDL3 is on the
# stack" (that alone is normal for any SDL3 app).
_SIGNATURE_REQUIRED=(libEGL libwayland-client)
_SIGNATURE_ANY_OF=(libnvidia-egl-wayland libEGL_nvidia wl_proxy_create_wrapper)

# coredump_classify <pid> -> prints one of:
#   remoteplay-wayland-nvidia-egl-crash | other-crash | unknown
coredump_classify() {
    local pid="$1" bt req any
    bt=$(coredumpctl info "$pid" --no-pager 2>/dev/null) || { echo "unknown"; return; }

    for req in "${_SIGNATURE_REQUIRED[@]}"; do
        grep -qF "$req" <<<"$bt" || { echo "other-crash"; return; }
    done

    any=0
    for a in "${_SIGNATURE_ANY_OF[@]}"; do
        grep -qF "$a" <<<"$bt" && any=1 && break
    done

    if [[ "$any" == "1" ]]; then
        echo "remoteplay-wayland-nvidia-egl-crash"
    else
        echo "other-crash"
    fi
}

# Prints "yes:<pid>:<timestamp>" for the most recent matching crash, or "no".
coredump_most_recent_signature_match() {
    local line pid ts class
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pid=$(awk '{print $5}' <<<"$line")
        ts=$(awk '{print $1, $2, $3, $4}' <<<"$line")
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        class=$(coredump_classify "$pid")
        if [[ "$class" == "remoteplay-wayland-nvidia-egl-crash" ]]; then
            echo "yes:$pid:$ts"
            return
        fi
    done < <(coredump_list_streaming_client | tac)
    echo "no"
}
