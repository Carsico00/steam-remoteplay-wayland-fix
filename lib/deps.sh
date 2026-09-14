#!/usr/bin/env bash
# deps.sh - dependency detection and *opt-in* installation via pacman.
#
# Rules (see docs/architecture.md "FIX vs WORKAROUND"):
#  - We only ever propose packages that a real check proved missing.
#  - We never pin old versions and never touch the NVIDIA driver package
#    itself (nvidia-utils / nvidia-*-utils / *-dkms).
#  - Installation always goes through `sudo pacman -S --needed <pkg>` so the
#    user sees pacman's own confirmation prompt; we never pass --noconfirm.

pkg_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Qi "$1" >/dev/null 2>&1
}

pkg_available_in_repos() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Si "$1" >/dev/null 2>&1
}

# install_pkg <pkgname> -> 0 on success, 1 on refusal/failure.
# Requires an interactive tty unless SRWF_ASSUME_YES=1 (then still goes
# through pacman's own prompt, just pre-answered by the user's earlier
# `--yes` choice at the srwf level - pacman itself is invoked without
# --noconfirm so a stray dependency conflict is never auto-resolved blindly).
install_pkg() {
    local pkg="$1"
    if ! command -v sudo >/dev/null 2>&1; then
        log_fail "sudo not available; cannot install $pkg automatically. Run: pacman -S $pkg"
        return 1
    fi
    if ! pkg_available_in_repos "$pkg"; then
        log_fail "$pkg is not available in your configured repositories."
        return 1
    fi
    log_fix "Installing $pkg (you will be asked for your sudo password / pacman confirmation)"
    if [[ "${SRWF_ASSUME_YES:-0}" == "1" ]]; then
        sudo pacman -S --needed --noconfirm "$pkg"
    else
        sudo pacman -S --needed "$pkg"
    fi
}

# ---- Problem 3: 32-bit NVIDIA EGL/Wayland platform ----
# Only relevant when the NVIDIA+Wayland workaround path is active at all;
# 32-bit Steam client / overlay components load this even though
# streaming_client itself is 64-bit.
check_32bit_egl_wayland() {
    local vendor
    vendor=$(detect_egl_wayland_32)
    if [[ "$vendor" == "NVIDIA" ]]; then
        echo "ok"
    elif [[ -z "$vendor" ]]; then
        echo "missing"   # eglinfo32 absent or Wayland platform block absent entirely
    else
        echo "wrong-vendor:$vendor"   # e.g. Mesa/llvmpipe software fallback
    fi
}

# lib32-egl-wayland is the correct, current Arch/CachyOS package name that
# ships /usr/lib32/libnvidia-egl-wayland.so.1 for the proprietary driver.
egl_wayland_32_package() { echo "lib32-egl-wayland"; }

# ---- Problem 4: 32-bit GBM EGL platform ----
# Investigated: streaming_client is a 64-bit binary (ubuntu12_64/), and
# Remote Play's desktop capture goes through PipeWire/xdg-desktop-portal in
# the 64-bit Steam client process, not through any 32-bit GBM context. No
# 32-bit process in the Remote Play pipeline was observed touching GBM.
# We therefore only report this, we never install lib32-egl-gbm for it.
check_32bit_egl_gbm_informational() {
    local vendor
    vendor=$(detect_egl_gbm_32)
    if [[ "$vendor" == "NVIDIA" ]]; then
        echo "ok"
    else
        echo "not-required"
    fi
}

# ---- Problem 5 support: 64-bit GBM EGL, used by PipeWire/portal desktop capture ----
check_64bit_egl_gbm() {
    local vendor
    vendor=$(detect_egl_gbm_64)
    if [[ "$vendor" == "NVIDIA" ]]; then
        echo "ok"
    elif [[ -z "$vendor" ]]; then
        echo "missing"
    else
        echo "wrong-vendor:$vendor"
    fi
}
