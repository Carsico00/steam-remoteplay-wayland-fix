#!/usr/bin/env bash
# Convenience entry point for `git clone ... && ./install.sh`.
# Equivalent to: bin/steam-remoteplay-wayland-fix install "$@"
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/bin/steam-remoteplay-wayland-fix" install "$@"
