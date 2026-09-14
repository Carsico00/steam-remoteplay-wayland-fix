#!/usr/bin/env bash
# steam.sh - locate the Steam installation and the streaming_client binary.

# Candidate install roots, in priority order. Native installs first, then
# the common compat layers. Flatpak Steam is detected but not supported for
# wrapper installation (its binaries live inside a separate sandbox/app
# filesystem and reinstall on every Flatpak update) - we say so explicitly.
steam_candidate_roots() {
    cat <<EOF
$HOME/.local/share/Steam
$HOME/.steam/steam
$HOME/.steam/debian-installation
$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam
/usr/share/steam
EOF
}

# Prints the first existing, native (non-flatpak) Steam root, or nothing.
detect_steam_root() {
    local root
    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        if [[ -d "$root/ubuntu12_64" ]]; then
            echo "$root"
            return 0
        fi
    done < <(steam_candidate_roots)
    return 1
}

detect_steam_is_flatpak_only() {
    if [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/ubuntu12_64" ]] \
       && ! detect_steam_root >/dev/null 2>&1; then
        echo "yes"
    else
        echo "no"
    fi
}

streaming_client_path() {
    local root
    root=$(detect_steam_root) || return 1
    echo "$root/ubuntu12_64/streaming_client"
}

streaming_client_real_path() {
    local root
    root=$(detect_steam_root) || return 1
    echo "$root/ubuntu12_64/streaming_client.real"
}

# Best-effort Steam client build id, read from the running client's argv
# (steamwebhelper carries -buildid=<N>). Falls back to empty string.
detect_steam_build_id() {
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -af 'steamwebhelper' 2>/dev/null \
            | grep -oE -- '-buildid=[0-9]+' \
            | head -n1 \
            | cut -d= -f2
    fi
}

detect_steam_running() {
    if command -v pgrep >/dev/null 2>&1 && pgrep -x steam >/dev/null 2>&1; then
        echo "yes"
    else
        echo "no"
    fi
}
