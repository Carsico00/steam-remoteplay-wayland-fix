#!/usr/bin/env bash
# Convenience entry point: bin/steam-remoteplay-wayland-fix uninstall "$@"
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/bin/steam-remoteplay-wayland-fix" uninstall "$@"
