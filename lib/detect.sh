#!/usr/bin/env bash
# detect.sh - environment detection: OS, desktop, session type, GPU/driver, EGL.
# Every function prints its result on stdout and returns 0; callers decide
# what counts as OK/WARN. Nothing here mutates the system.

detect_os_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
    else
        echo "unknown"
    fi
}

detect_kernel() {
    uname -r
}

detect_desktop() {
    echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

# Prints: wayland | x11 | unknown
detect_session_type() {
    if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
        echo "$XDG_SESSION_TYPE"
        return
    fi
    if command -v loginctl >/dev/null 2>&1; then
        local sess type
        sess=$(loginctl show-user "${USER:-$(id -un)}" -p Display --value 2>/dev/null)
        if [[ -n "$sess" ]]; then
            type=$(loginctl show-session "$sess" -p Type --value 2>/dev/null)
            [[ -n "$type" ]] && { echo "$type"; return; }
        fi
    fi
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "wayland"
    elif [[ -n "${DISPLAY:-}" ]]; then
        echo "x11"
    else
        echo "unknown"
    fi
}

detect_wayland_display() {
    echo "${WAYLAND_DISPLAY:-}"
}

detect_xwayland_active() {
    # XWayland shows up as a nested X server; cheap heuristic via pgrep.
    if command -v pgrep >/dev/null 2>&1 && pgrep -x Xwayland >/dev/null 2>&1; then
        echo "yes"
    else
        echo "no"
    fi
}

# Prints one of: nvidia | amd | intel | nouveau | unknown
# Multiple GPUs: prefers a discrete NVIDIA/AMD card if present.
detect_gpu_vendor() {
    local pci=""
    if command -v lspci >/dev/null 2>&1; then
        pci=$(lspci -nn 2>/dev/null | grep -Ei 'vga compatible controller|3d controller')
    fi
    if grep -qi 'nvidia' <<<"$pci"; then
        echo "nvidia"
    elif grep -qi 'amd\|advanced micro devices\|ati ' <<<"$pci"; then
        echo "amd"
    elif grep -qi 'intel' <<<"$pci"; then
        echo "intel"
    elif [[ -n "$pci" ]]; then
        echo "unknown"
    else
        echo "unknown"
    fi
}

# Prints: proprietary | nouveau | none | unknown  (only meaningful for NVIDIA)
detect_nvidia_driver_kind() {
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo "proprietary"
        return
    fi
    if lsmod 2>/dev/null | grep -q '^nouveau'; then
        echo "nouveau"
        return
    fi
    echo "none"
}

detect_nvidia_driver_version() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1
    fi
}

# Runs `eglinfo -B` (or eglinfo32) and extracts the EGL vendor string for a
# given platform block ("Wayland platform" / "X11 platform" / "GBM platform").
# Usage: egl_vendor_for_platform <eglinfo-binary> <platform-label>
egl_vendor_for_platform() {
    local binary="$1" platform="$2"
    command -v "$binary" >/dev/null 2>&1 || { echo ""; return 1; }
    "$binary" -B 2>/dev/null | awk -v p="${platform}:" '
        index($0, p) == 1 { infile=1; next }
        infile && /platform:[[:space:]]*$/ { infile=0 }
        infile && /EGL vendor string:/ {
            sub(/^[[:space:]]*EGL vendor string:[[:space:]]*/, "");
            print;
            exit
        }
    '
}

detect_egl_wayland_64() { egl_vendor_for_platform eglinfo "Wayland platform"; }
detect_egl_x11_64()     { egl_vendor_for_platform eglinfo "X11 platform"; }
detect_egl_gbm_64()     { egl_vendor_for_platform eglinfo "GBM platform"; }
detect_egl_wayland_32() { egl_vendor_for_platform eglinfo32 "Wayland platform"; }
detect_egl_gbm_32()     { egl_vendor_for_platform eglinfo32 "GBM platform"; }

# Whether the NVIDIA-Wayland-specific workaround is applicable at all.
# Keeps AMD/Intel/X11/nouveau systems untouched, per design.
#
# SRWF_FORCE_WORKAROUND=1|0 overrides real detection - used by the test
# suite to exercise both code paths without needing real NVIDIA hardware.
needs_nvidia_wayland_workaround() {
    if [[ -n "${SRWF_FORCE_WORKAROUND:-}" ]]; then
        [[ "$SRWF_FORCE_WORKAROUND" == "1" ]]
        return
    fi
    local vendor session kind
    vendor=$(detect_gpu_vendor)
    session=$(detect_session_type)
    kind=$(detect_nvidia_driver_kind)
    [[ "$vendor" == "nvidia" && "$session" == "wayland" && "$kind" == "proprietary" ]]
}
