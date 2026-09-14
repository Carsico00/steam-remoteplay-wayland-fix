# Architecture

## Scope

This project patches **Steam Remote Play / Remote Play Together** on Linux
systems running:

- a Wayland session (any compositor: KDE Plasma, GNOME, Hyprland, Sway, ...)
- the **proprietary** NVIDIA driver

on Arch/CachyOS, without moving the desktop session to X11 and without
touching the NVIDIA driver, PipeWire, or any other system-wide component.

It is not a generic "Steam overlay fix" or a `streaming_client` wrapper in
isolation - it addresses the whole chain from Steam launching
`streaming_client` through to a playable session (video, audio, controller),
and it is designed to survive Steam updates.

## Root cause

Steam's Remote Play host/client process, `streaming_client` (part of AppID
`202355`), links `libSDL3.so.0`. Under a Wayland session with the proprietary
NVIDIA driver, SDL3's EGL/window initialization path goes through:

```
libSDL3.so.0
  -> libEGL.so.1
    -> libEGL_nvidia.so.0
      -> libnvidia-egl-wayland.so.1   (NVIDIA's EGLStream-based Wayland platform)
        -> libwayland-client.so.0 : wl_proxy_create_wrapper()
          -> pthread_mutex_lock()  -> SIGSEGV
```

The same underlying library is also reached from Steam's overlay
(`gameoverlayrenderer.so`, injected via `LD_PRELOAD`) when it calls
`eglGetDisplay()` under Wayland - the overlay's rendering path only ever
targeted GLX/X11 WSI, so an EGL/Wayland `eglGetDisplay()` call from inside
it exercises an unsupported/fragile path in the same NVIDIA library
(tracked upstream as the general "no Wayland support in the Steam overlay"
gap, see [docs/upstream.md](upstream.md)).

Both crashes are the **same class of bug**: NVIDIA's EGLStream Wayland
external platform library misbehaving when entered from `streaming_client`'s
own SDL3 initialization or from the overlay's EGL entry point. Running the
identical binary and arguments with the video/EGL backend forced to X11
(via XWayland, session unchanged) avoids both, because neither code path
then touches `libnvidia-egl-wayland.so.1` at all.

## What this project actually does

1. **Detects** whether a system is affected at all (NVIDIA proprietary
   driver + Wayland session). AMD, Intel, nouveau and X11 sessions are left
   completely untouched - see `lib/detect.sh:needs_nvidia_wayland_workaround`.
2. **Preserves** Steam's original `streaming_client` binary as
   `streaming_client.real`, and records a verifiable backup (hash, Steam
   build id, timestamp, path) before touching anything.
3. **Installs a thin wrapper** at `streaming_client` that:
   - strips `-steam-overlay` from argv (workaround for Problem 2)
   - unsets `LD_PRELOAD` (workaround for Problem 2, `gameoverlayrenderer.so`
     injection)
   - forces `SDL_VIDEO_DRIVER=x11`, `SDL_VIDEODRIVER=x11`,
     `EGL_PLATFORM=x11`, and unsets `WAYLAND_DISPLAY` **for this one child
     process only** (workaround for Problems 1/6) - the desktop session's
     `XDG_SESSION_TYPE` remains `wayland` throughout; only `streaming_client`
     itself runs through XWayland.
   - `exec`s the preserved `streaming_client.real`
4. **Fixes** a real missing dependency when one is found: 32-bit NVIDIA
   EGL/Wayland platform library (`lib32-egl-wayland`), needed by Steam's
   32-bit components under Wayland - installed only after a real check
   proves it's missing, via `pacman` with its own confirmation prompt.
5. **Diagnoses** (never silently "fixes") PipeWire/xdg-desktop-portal
   desktop-capture prerequisites, since those failures are frequently
   unrelated local misconfiguration rather than something this project
   should touch - see [docs/diagnostics.md](diagnostics.md).
6. **Detects Steam updates** that overwrite `streaming_client` with a fresh
   original binary, and reapplies the wrapper - both on demand
   (`doctor`/`status`/`repair`) and via an optional `systemd --user` path
   unit that watches the file for changes.

## Components

```
bin/steam-remoteplay-wayland-fix   CLI entry point (install/uninstall/status/doctor/repair/test)
lib/common.sh                      logging, small helpers, state.env key/value store
lib/detect.sh                      OS/session/GPU/driver/EGL detection (pure, side-effect free)
lib/steam.sh                       Steam install root + streaming_client path resolution
lib/backup.sh                      verifiable backup/restore (hash + timestamp + Steam build)
lib/deps.sh                        pacman-based dependency checks/installs (opt-in, no --noconfirm)
lib/pipewire.sh                    read-only PipeWire/portal/DRM diagnostics
lib/coredump.sh                    coredumpctl-based crash signature recognition
lib/wrapper.sh                     the wrapper state machine (the only module that writes into Steam's directory)
lib/watcher.sh                     optional systemd --user path unit (Steam-update auto-repair)
lib/smoketest.sh                   synthetic EGL-init smoke test (`test` command)
lib/doctor.sh                      orchestrates all of the above into one report; repair = doctor --fix --yes
```

## The wrapper state machine

`streaming_client` can be in one of five states, and `install`/`repair` are
built to move from any of them to `active` without ever discarding data:

| State | Meaning | Action |
|---|---|---|
| `not-installed` | Untouched Valve ELF binary, no `.real` | back it up, rename to `.real`, install wrapper |
| `active` | Our wrapper, marker matches, `.real` present and valid | no-op (or refresh policy/version) |
| `stale-overwritten` | A **new** ELF binary sits at `streaming_client`, but our own state recorded a previous install | Steam update: archive the new binary as the new `.real`, reinstall wrapper |
| `foreign` | Some other script (not ours, not Valve's) sits at `streaming_client`, `.real` is a valid original | back the foreign script up, install our wrapper, leave `.real` untouched |
| `corrupt` | Marker present but `.real` missing/invalid, or an unrecognized file with no `.real` to fall back to | attempt restore from backup; otherwise fail loudly rather than guess |

Distinguishing "Steam updated the file" from "two unrelated original
binaries happen to both be present" is done via our **own recorded state**
(`state.env`: `wrapper_installed`), not by guessing from file content alone -
see `lib/wrapper.sh:install_wrapper`.

**Recursion is structurally impossible**: the wrapper always execs a
hardcoded sibling file named `streaming_client.real`, which our installer
guarantees is never itself a wrapper (case `stale-overwritten`/`active`
require `.real` to be a plain ELF binary). The generated wrapper also
carries a runtime check that refuses to exec if `.real` ever resolved to
itself.

## Steam-update resilience

Two independent mechanisms exist, deliberately overlapping:

1. **On-demand detection**: every `status`, `doctor`, and `repair`
   invocation calls `wrapper_status()`, which compares the live file against
   our marker/state and correctly identifies a Steam-replaced binary as
   `stale-overwritten`.
2. **`systemd --user` path unit** (installed by default, `--no-watcher` to
   skip): watches `streaming_client` via `PathModified=` and runs
   `repair --yes --quiet` whenever the file changes. This is a convenience
   net, not the sole safety mechanism - it was live-tested by touching the
   file and confirming `steam-remoteplay-wayland-fix-watcher.service` ran
   and left the wrapper `active` afterward.

## What is intentionally out of scope

- Flatpak Steam: its files live inside the Flatpak sandbox and are replaced
  wholesale on every Flatpak update; `doctor` detects and reports this
  rather than attempting to patch it.
- AMD/Intel GPUs, nouveau, and X11 sessions: `doctor` reports these as not
  needing the workaround. Nothing is installed or modified.
- 32-bit GBM EGL (`lib32-egl-gbm`): investigated and found not to be part of
  the Remote Play pipeline - see [docs/diagnostics.md](diagnostics.md).
