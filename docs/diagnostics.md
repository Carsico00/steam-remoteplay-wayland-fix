# Diagnostics reference

This documents every check `doctor` performs, what a failing result means,
and - critically - which checks are classified **FIX**, **WORKAROUND**,
**DIAGNOSTIC**, or **OPTIONAL**. See also [docs/upstream.md](upstream.md)
for the Valve-side issue tracking.

| Classification | Meaning |
|---|---|
| **FIX** | A missing dependency that a real check proved absent; installing it addresses the actual gap. |
| **WORKAROUND** | Works around an upstream bug we don't control; the underlying bug still exists in Steam/SDL3/NVIDIA's interaction. |
| **DIAGNOSTIC** | Read-only; tells you whether a prerequisite is in place. Never modifies anything. |
| **OPTIONAL** | Convenience (e.g. the systemd watcher); the tool works without it. |

## Problem 1 & 6 - `streaming_client` SIGSEGV in SDL3/EGL init — **WORKAROUND**

```
streaming_client.real
  -> libSDL3.so.0 -> libEGL.so.1 -> libEGL_nvidia.so.0
    -> libnvidia-egl-wayland.so.1 -> libwayland-client.so.0:wl_proxy_create_wrapper()
      -> pthread_mutex_lock() -> SIGSEGV
```

Forcing `SDL_VIDEO_DRIVER=x11` / `SDL_VIDEODRIVER=x11` / `EGL_PLATFORM=x11`
and unsetting `WAYLAND_DISPLAY` **only for this child process** avoids the
NVIDIA Wayland EGL platform entirely, so the crash cannot occur. This is a
workaround, not a fix: the actual bug (NVIDIA's EGLStream Wayland platform
misbehaving when entered from this specific SDL3 call pattern) lives in
Steam/SDL3/NVIDIA, not in this project. See [upstream.md](upstream.md).

`doctor` recognizes this crash signature in `coredumpctl` by requiring
`libEGL` and `libwayland-client` frames together with at least one of
`libnvidia-egl-wayland`, `libEGL_nvidia`, or `wl_proxy_create_wrapper` -
deliberately not pinned to one exact Steam build, so it keeps working across
Steam updates (see `lib/coredump.sh`).

## Problem 2 - Steam overlay crash via `gameoverlayrenderer.so` — **WORKAROUND**

The overlay's OpenGL interception (`gameoverlayrenderer.so`, loaded via
`LD_PRELOAD`) calls `eglGetDisplay()`, which - under Wayland with the
proprietary driver - re-enters the same fragile NVIDIA EGLStream code path.
This is a known upstream gap: the Steam overlay was built against GLX/X11
WSI and has no supported Wayland/EGL rendering path (tracked as
[ValveSoftware/steam-runtime#811](https://github.com/ValveSoftware/steam-runtime/issues/811)
and [ValveSoftware/steam-for-linux#8020](https://github.com/ValveSoftware/steam-for-linux/issues/8020)).

Two things must both happen for `streaming_client` to stop hitting this:

1. `-steam-overlay` is stripped from argv.
2. `LD_PRELOAD` is unset. **Removing the argument alone is not enough** -
   Steam's launcher also injects `gameoverlayrenderer.so` via `LD_PRELOAD`
   independently of that flag; if `LD_PRELOAD` is left set, the overlay
   still loads and can still reach `eglGetDisplay()`.

## Problem 3 - 32-bit NVIDIA EGL/Wayland missing — **FIX**

`doctor` runs `eglinfo32 -B` and checks the `EGL vendor string` under the
`Wayland platform` block:

- `NVIDIA` -> OK, nothing to do.
- Mesa/llvmpipe, or the block is present but software-rendered -> the
  32-bit EGLStream Wayland platform library is missing; Steam's 32-bit
  components (parts of the client UI, some 32-bit game/launcher helpers)
  silently fall back to software rendering under Wayland.
- No `Wayland platform` block at all, or `eglinfo32` missing -> same
  remediation.

The fix installs **`lib32-egl-wayland`** - the current Arch/CachyOS package
name for the 32-bit build of `egl-wayland`
(`/usr/lib32/libnvidia-egl-wayland.so.1`), matched against your existing
64-bit `egl-wayland`/NVIDIA driver version. This is a targeted dependency
fix, not a driver change: no version is pinned, no downgrade is performed,
and the proprietary driver itself is never touched. Installation always
goes through `sudo pacman -S --needed lib32-egl-wayland`, with pacman's own
confirmation prompt (never `--noconfirm` unless you pass `--yes` at the
`pacman` level yourself).

## Problem 4 - 32-bit GBM EGL — **not required, left out by design**

`EGL_PLATFORM=gbm eglinfo32 -B` can fail to initialize even on an otherwise
correctly configured system. This was investigated rather than assumed:

- `streaming_client` is a **64-bit** binary (`ubuntu12_64/streaming_client`);
  it never loads a 32-bit EGL platform of any kind.
- Remote Play's desktop capture (the PipeWire path, Problem 5) runs inside
  the 64-bit Steam client process and negotiates GBM/DMA-BUF through
  PipeWire/`xdg-desktop-portal`, not through a 32-bit GBM context.
- No 32-bit process anywhere in the Remote Play pipeline was observed
  touching `/dev/dri/renderD128` via GBM in this project's testing.

`doctor` reports this check as informational only (`EGL GBM (32-bit): not-required`)
and never installs `lib32-egl-gbm` for it. If you find a concrete scenario
where 32-bit GBM matters for Remote Play, please open an issue with
reproduction steps.

## Problem 5 - PipeWire desktop capture `EGL_NOT_INITIALIZED` (0x3001) — **DIAGNOSTIC**

Steam's PipeWire-based desktop capture (`-pipewire`, `CDesktopCapturePipeWire`)
opens `/dev/dri/renderD128` and initializes EGL under the `GBM` platform. A
failure here shows up as:

```
CDesktopCapturePipeWire: Opening DRM render node /dev/dri/renderD128
Couldn't initialize EGL: 0x3001
```

(`0x3001` = `EGL_NOT_INITIALIZED`.) `doctor` checks the real prerequisites,
**read-only, with no restarts or reinstalls**:

- `pipewire.service` / `wireplumber.service` (`systemctl --user is-active`)
- `xdg-desktop-portal.service` (`systemctl --user is-active`)
- the desktop-specific portal backend (`xdg-desktop-portal-kde` for
  KDE/Plasma, `xdg-desktop-portal-gtk` for GNOME): these are **D-Bus
  activated**, not persistent daemons, so `systemctl --user` correctly
  reports them `inactive` when idle - `doctor` checks D-Bus
  registration/activatability instead of demanding an "active" systemd
  state, to avoid a false alarm here.
- `EGL_PLATFORM=gbm eglinfo -B` (64-bit) reporting `NVIDIA` as the vendor -
  this is the same EGL/GBM path PipeWire's capture uses.
- `/dev/dri/renderD128` existing and being readable/writable by the current
  user.

If every check passes and you still see `EGL_NOT_INITIALIZED` during an
actual Remote Play session, the most likely explanations (based on the
history behind this project) are transient - e.g. it was observed
immediately downstream of the SDL3/EGL crash storm from Problems 1/2/6,
where repeated `streaming_client` crashes appear to have left the render
node/portal state briefly unhappy. Once `streaming_client` stops crashing,
this has not reproduced independently in this project's testing. Please
file an issue with a fresh `doctor` output if you can reproduce it with all
checks green.

## Steam Remote Play component (AppID 202355)

`doctor` checks for `steamapps/appmanifest_202355.acf` as a best-effort
signal that Steam has downloaded the Remote Play streaming component at
all. If `streaming_client` is missing entirely, open Remote Play from the
Steam UI once (even without a peer connecting) so Steam downloads it, then
re-run `doctor`.

## Crash-history detection — **DIAGNOSTIC**

`doctor` scans `coredumpctl list` for any `streaming_client` /
`streaming_client.real` entry and classifies it via `coredumpctl info`
(see Problem 1/6 above for the signature). This is informational: it tells
you a matching crash happened before, not that one is currently happening.
