# Upstream status (ValveSoftware/steam-for-linux)

This project exists because these bugs are, as of this writing, still open
upstream. This page is a snapshot - please check the linked issues for the
current state before assuming anything here is still accurate; Valve does
occasionally ship fixes without much fanfare.

| Issue | Repo | Status (last checked) | Relation to this project |
|---|---|---|---|
| [#13179 - "Remote play crashes on wayland regardless of DE/WM"](https://github.com/ValveSoftware/steam-for-linux/issues/13179) | steam-for-linux | Open | Matches Problems 1/6 almost exactly: `eglGetDisplay`/EGL crash on KDE Plasma, Hyprland and Sway (all Wayland), works fine on X11, and - like our case - running `streaming_client` manually from a terminal with the same arguments succeeds. No Valve response recorded at time of writing. |
| [steam-runtime#811 - "Steam overlay broken for native Linux games on Wayland"](https://github.com/ValveSoftware/steam-runtime/issues/811) | steam-runtime | Open | Documents that `SDL_VIDEODRIVER=x11` as a launch option works around the overlay crash - independent confirmation of the same X11-forcing workaround this project applies specifically to `streaming_client`. |
| [#8020 - "Add Wayland support to the Steam overlay"](https://github.com/ValveSoftware/steam-for-linux/issues/8020) | steam-for-linux | Open (tracking/feature request) | The actual root cause of Problem 2: the overlay only implements GLX/X11 WSI interception, with no supported EGL/Wayland path. This is the issue Valve would need to resolve for the overlay-triggered crash to be fixed at the source rather than worked around. |
| [#11818 - "Overlay doesn't work for native Wayland games/programs"](https://github.com/ValveSoftware/steam-for-linux/issues/11818) | steam-for-linux | Open | Same architectural gap as #8020, reported from the angle of native-Wayland games rather than Remote Play specifically. |
| [#13585 - "Steam Remote Play via PipeWire on Wayland produces black/frozen video and very low FPS"](https://github.com/ValveSoftware/steam-for-linux/issues/13585) | steam-for-linux | Open | Different failure mode of the PipeWire desktop-capture path (Problem 5's neighborhood) - not the same bug, but the same subsystem. Relevant background if `doctor`'s PipeWire checks pass but capture quality is still bad. |
| [#13348 - "Remote Play `-pipewire` capture shows stale/wrong frame insertion on KDE Wayland host"](https://github.com/ValveSoftware/steam-for-linux/issues/13348) | steam-for-linux | Open | Same neighborhood as above; KDE-Wayland-specific frame timing issue in the PipeWire capture path. |

## Why we don't treat any of this as "fixed upstream"

None of the issues above are closed by a Valve commit as of this writing.
Everything this project does to `streaming_client` (Problems 1, 2, 6) is
therefore classified as a **workaround**, not a fix - see
[docs/diagnostics.md](diagnostics.md) for the FIX/WORKAROUND/DIAGNOSTIC/
OPTIONAL breakdown per problem. If/when Valve ships an actual fix (most
likely: giving the Steam overlay and `streaming_client`'s SDL3 usage a
working EGL/Wayland path against `libnvidia-egl-wayland`), the X11-forcing
workaround in `lib/wrapper.sh` should become unnecessary and `doctor` will
need a version-aware check to stop applying it. That is intentionally not
implemented yet, since it depends on upstream behavior this project has no
control over. See [docs/upstream-patch.md](upstream-patch.md) for the
change we believe Valve should make.

## Reporting back upstream

If you hit this bug, upvoting/commenting on
[#13179](https://github.com/ValveSoftware/steam-for-linux/issues/13179) with
your own `doctor` output (sanitized - see [docs/security.md](security.md))
is more likely to get Valve's attention than a new duplicate issue.
