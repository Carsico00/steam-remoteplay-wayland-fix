#!/usr/bin/env bash
# test_pipewire.sh - Problem 5 diagnostics, stubbing systemctl so this runs
# the same with or without a real PipeWire session.

test_pipewire_reported_active() {
    _systemd_user_active() { [[ "$1" == "pipewire.service" ]]; }
    assert_eq "active" "$(pw_check_pipewire)"
}

test_pipewire_reported_inactive() {
    _systemd_user_active() { return 1; }
    assert_eq "inactive" "$(pw_check_pipewire)"
}

test_portal_kde_backend_activatable() {
    busctl() { echo "org.freedesktop.impl.portal.desktop.kde"; }
    XDG_CURRENT_DESKTOP=KDE
    assert_eq "activatable" "$(pw_check_portal_backend)"
}

test_portal_backend_missing_for_unknown_desktop() {
    busctl() { return 1; }
    XDG_CURRENT_DESKTOP=SomeWeirdWM
    # falls back to filesystem check, which will not find a KDE/GTK service
    # file match named after an unknown DE -> reported unknown-desktop
    assert_eq "unknown-desktop" "$(pw_check_portal_backend)"
}

test_render_node_missing() {
    export SRWF_RENDER_NODE="/nonexistent/renderD128-$RANDOM"
    assert_eq "missing" "$(pw_check_render_node)"
}

test_render_node_ok_when_accessible() {
    local tmp; tmp=$(mktemp)
    export SRWF_RENDER_NODE="$tmp"
    assert_eq "ok" "$(pw_check_render_node)"
}

test_render_node_no_permission() {
    local tmp; tmp=$(mktemp)
    chmod 000 "$tmp"
    export SRWF_RENDER_NODE="$tmp"
    if [[ "$(id -u)" == "0" ]]; then
        return 0   # root bypasses permission bits; skip under CI running as root
    fi
    assert_eq "no-permission" "$(pw_check_render_node)"
    chmod 600 "$tmp"
}
