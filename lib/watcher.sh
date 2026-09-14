#!/usr/bin/env bash
# watcher.sh - optional systemd --user path unit that notices Steam
# overwriting streaming_client (e.g. on update) and reapplies the wrapper.
#
# This is a convenience net, not the primary mechanism: `doctor`/`status`/
# `repair` always detect drift on demand regardless of whether the watcher
# is enabled.

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
WATCHER_SERVICE_NAME="${APP_NAME}-watcher.service"
WATCHER_PATH_NAME="${APP_NAME}-watcher.path"

watcher_available() {
    command -v systemctl >/dev/null 2>&1
}

# The CLI entry point path is recorded at install time (lib/wrapper.sh calls
# this indirectly via the main script), so the watcher keeps working whether
# installed system-wide (PKGBUILD, /usr/bin) or run from a git checkout.
watcher_install() {
    local cli_path="$1"
    watcher_available || { log_info "systemd not available; skipping watcher (repair still works manually)."; return 0; }

    local client
    client=$(streaming_client_path 2>/dev/null) || { log_warn "Cannot install watcher: Steam installation not found."; return 1; }

    mkdir -p "$SYSTEMD_USER_DIR"

    cat > "$SYSTEMD_USER_DIR/$WATCHER_SERVICE_NAME" <<EOF
[Unit]
Description=Reapply steam-remoteplay-wayland-fix after Steam updates streaming_client
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=${cli_path} repair --yes --quiet
EOF

    cat > "$SYSTEMD_USER_DIR/$WATCHER_PATH_NAME" <<EOF
[Unit]
Description=Watch streaming_client for changes (Steam update detector)

[Path]
PathModified=${client}
Unit=${WATCHER_SERVICE_NAME}

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now "$WATCHER_PATH_NAME" 2>/dev/null \
        && log_ok "Watcher installed and enabled (systemd --user path unit)." \
        || log_warn "Watcher units written but could not be enabled (no user systemd instance?)."
}

watcher_uninstall() {
    watcher_available || return 0
    systemctl --user disable --now "$WATCHER_PATH_NAME" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_USER_DIR/$WATCHER_PATH_NAME" "$SYSTEMD_USER_DIR/$WATCHER_SERVICE_NAME"
    systemctl --user daemon-reload 2>/dev/null || true
    log_ok "Watcher units removed."
}

watcher_status() {
    watcher_available || { echo "unavailable"; return; }
    if systemctl --user is-enabled --quiet "$WATCHER_PATH_NAME" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}
