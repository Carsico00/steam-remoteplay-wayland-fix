#!/usr/bin/env bash
# pipewire.sh - read-only diagnostics for Steam's PipeWire desktop-capture
# path (Problem 5: "Couldn't initialize EGL: 0x3001" / EGL_NOT_INITIALIZED).
#
# This module NEVER restarts or reinstalls anything. It only determines
# whether the real prerequisites are in place, so `doctor` can tell a false
# alarm ("your PipeWire is fine, the crash was something else") apart from a
# genuine local misconfiguration.

_systemd_user_active() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$1" 2>/dev/null
}

pw_check_pipewire() {
    _systemd_user_active pipewire.service && echo "active" || echo "inactive"
}

pw_check_wireplumber() {
    _systemd_user_active wireplumber.service && echo "active" || echo "inactive"
}

pw_check_portal() {
    _systemd_user_active xdg-desktop-portal.service && echo "active" || echo "inactive"
}

# xdg-desktop-portal-kde (and its GNOME/other-DE equivalents) are D-Bus
# *activated* services, not persistent daemons: `systemctl --user is-active`
# legitimately reports "inactive" between screen-share requests. The real
# signal is whether the D-Bus service file is registered/activatable.
pw_check_portal_backend() {
    local desktop svc
    desktop=$(detect_desktop | tr '[:upper:]' '[:lower:]')
    case "$desktop" in
        *kde*|*plasma*) svc="org.freedesktop.impl.portal.desktop.kde" ;;
        *gnome*)        svc="org.freedesktop.impl.portal.desktop.gtk" ;;
        *)              svc="" ;;
    esac
    if [[ -z "$svc" ]]; then
        echo "unknown-desktop"
        return
    fi
    if command -v busctl >/dev/null 2>&1 && \
       busctl --user list 2>/dev/null | grep -q "$svc"; then
        echo "activatable"
        return
    fi
    if ls /usr/share/dbus-1/services/*"${svc}"*.service >/dev/null 2>&1; then
        echo "activatable"
    else
        echo "missing"
    fi
}

pw_check_render_node() {
    local node="${SRWF_RENDER_NODE:-/dev/dri/renderD128}"
    if [[ ! -e "$node" ]]; then
        echo "missing"
        return
    fi
    if [[ -r "$node" && -w "$node" ]]; then
        echo "ok"
    else
        echo "no-permission"
    fi
}
