# steam-remoteplay-wayland-fix

An integral compatibility fix for **Steam Remote Play / Remote Play
Together** on **CachyOS/Arch + Wayland (any compositor) + NVIDIA
(proprietary driver)** - without moving your desktop session to X11.

This is not a `streaming_client` wrapper in isolation. It diagnoses and
fixes the whole chain: the SIGSEGV crash in `streaming_client`'s SDL3/EGL
init, the Steam overlay's `LD_PRELOAD`/EGL interaction, a real missing
32-bit NVIDIA EGL dependency, PipeWire desktop-capture prerequisites, and
Steam silently overwriting the fix on update - and it tells you clearly
which parts are an actual dependency fix versus a workaround for an open
upstream bug. See [docs/architecture.md](docs/architecture.md) for the full
picture and [docs/upstream.md](docs/upstream.md) for the Valve-side issue
tracking.

## Is this you?

- CachyOS/Arch, KDE Plasma (or GNOME/Hyprland/Sway) on **Wayland**
- **NVIDIA** GPU with the **proprietary** driver
- Steam Remote Play / Remote Play Together crashes immediately, or
  `streaming_client` disappears from `pgrep` right after you try to
  connect, and the game never launches
- It works if you log into an X11 session instead - but you don't want to
  give up Wayland for your whole desktop just for this

Check for certain:

```bash
./bin/steam-remoteplay-wayland-fix doctor
```

## Install

```bash
git clone https://github.com/Carsico00/steam-remoteplay-wayland-fix.git
cd steam-remoteplay-wayland-fix
./install.sh
```

or, once published, from the AUR:

```bash
yay -S steam-remoteplay-wayland-fix
steam-remoteplay-wayland-fix install
```

`install` only ever touches your system if `doctor` determines your GPU +
session actually matches the affected profile (NVIDIA proprietary +
Wayland). On any other configuration it prints why and exits without
changing anything.

What it does, in order:

1. Checks whether the 32-bit NVIDIA EGL/Wayland platform library is missing
   and, only if so, offers to install `lib32-egl-wayland` via `pacman`
   (with pacman's own confirmation prompt).
2. Backs up Steam's original `streaming_client` binary (verified by hash,
   Steam build id, and timestamp) and installs a small wrapper in its
   place.
3. Installs an optional `systemd --user` watcher that automatically
   reapplies the fix if a Steam update overwrites `streaming_client`
   (`--no-watcher` to skip).

Your desktop session stays on Wayland throughout - only the
`streaming_client` process itself is affected.

## Verify

```bash
steam-remoteplay-wayland-fix status    # quick summary
steam-remoteplay-wayland-fix doctor    # full diagnostic report
steam-remoteplay-wayland-fix test      # synthetic smoke test of the crash path
```

Then from Steam: **Remote Play / Remote Play Together -> connect -> play**.
Confirm video, audio, and controller input all work - `test` only proves
`streaming_client` survives graphics/EGL initialization, not the full
session (see [docs/diagnostics.md](docs/diagnostics.md)).

## After a Steam update

If the watcher is enabled (default), nothing to do - it detects Steam
overwriting `streaming_client` and reapplies automatically. Otherwise, or
to be sure:

```bash
steam-remoteplay-wayland-fix repair
```

`repair` is fully idempotent - safe to run any number of times.

## Uninstall

```bash
./uninstall.sh
# or: steam-remoteplay-wayland-fix uninstall
```

Restores Steam's original `streaming_client` and removes everything this
project installed (wrapper, `.real` copy, systemd watcher units, config).
Installed system packages (e.g. `lib32-egl-wayland`) are left in place -
see [docs/troubleshooting.md](docs/troubleshooting.md#uninstalling-didnt-fully-restore-my-system).

## Commands

| Command | Effect |
|---|---|
| `install` | Apply the fix (dependency check, wrapper, watcher) - no-op if not needed on this system |
| `uninstall` | Restore Steam's original `streaming_client`, remove everything this project installed |
| `status` | Quick, read-only summary of current state |
| `doctor` | Full diagnostic report; add `--fix` to apply safe fixes inline |
| `repair` | Idempotent full remediation (`doctor --fix --yes`) - safe to run repeatedly, including after Steam updates |
| `test` | Synthetic smoke test of the graphics/EGL init crash path |

Global flags: `-y`/`--yes` (assume yes to prompts), `-q`/`--quiet`.

## FIX vs WORKAROUND vs DIAGNOSTIC vs OPTIONAL

This project does not call everything a "fix". See the full table in
[docs/diagnostics.md](docs/diagnostics.md); summary:

- **FIX** - 32-bit NVIDIA EGL/Wayland missing -> install `lib32-egl-wayland`.
  A real, targeted dependency gap, verified before installing anything.
- **WORKAROUND** - the `streaming_client` SIGSEGV and the overlay crash are
  worked around by forcing that one process through X11/XWayland. The
  underlying bug is in Steam/SDL3's interaction with NVIDIA's Wayland EGL
  platform, and is still open upstream - see [docs/upstream.md](docs/upstream.md).
- **DIAGNOSTIC** - PipeWire/portal/DRM desktop-capture prerequisites, and
  32-bit GBM EGL: checked and reported, never silently "fixed" by
  restarting or reinstalling anything.
- **OPTIONAL** - the systemd watcher. The tool works without it; you'd just
  need to run `repair` manually after Steam updates.

## Compatibility

Primary target: CachyOS/Arch + KDE Plasma + Wayland + NVIDIA proprietary.
Detection is GPU/session-based, not desktop-specific, so it also works
unchanged on GNOME Wayland, Hyprland, Sway, and other Wayland compositors on
Arch. AMD, Intel, nouveau, and X11 sessions are detected and explicitly left
untouched - `doctor` will tell you the workaround doesn't apply rather than
guessing. Flatpak-only Steam installs are detected and reported as
unsupported (see [docs/troubleshooting.md](docs/troubleshooting.md)).

## Real-world validation

This project's root cause analysis and workaround were validated against a
live reproduction: CachyOS, KDE Plasma, Wayland, NVIDIA RTX 2070 SUPER
(proprietary driver 580.178.04), Steam build `1789086785`. Before the fix,
`streaming_client` reproducibly crashed with `SIGSEGV` in
`libSDL3 -> libEGL -> libEGL_nvidia -> libnvidia-egl-wayland -> libwayland-client`
on every launch attempt (confirmed via `coredumpctl`). After applying the
same workaround this project installs, the identical invocation survived
graphics/EGL initialization with no new coredump, `doctor` reported all
NVIDIA/EGL/PipeWire checks green, `install`/`repair`/`status` were exercised
against the real Steam installation (including a pre-existing, unrelated
manual wrapper this project correctly detected, backed up, and safely
replaced), and the `systemd --user` watcher was live-tested by modifying
`streaming_client` and confirming automatic, idempotent repair.

What was **not** independently re-verified end-to-end on that machine: a
full two-device Remote Play session (video + audio + controller) with a
specific game, since that requires a second physical/network client device
to connect from. If you can confirm the full loop on your own setup, please
say so in an issue - real user confirmations are how this project earns the
"video/audio/controls all work" claim beyond the graphics-init crash fix.

## Testing

```bash
./tests/run_tests.sh
```

The full suite runs against temporary, mocked `$HOME`/Steam directories -
it never touches a real Steam installation, never calls `pacman`, and never
requires NVIDIA hardware (GPU/session detection can be forced via
`SRWF_FORCE_WORKAROUND=1|0` for tests). See
[docs/architecture.md](docs/architecture.md) for what each module does.

## Packaging

An Arch/AUR-ready `PKGBUILD` is at [packaging/PKGBUILD](packaging/PKGBUILD).
It is not yet published to the AUR - see the repository for how to build
and install it locally (`makepkg -si` from `packaging/`) in the meantime.

## Contributing / reporting a bug

Please run `doctor` and attach its full output (after checking
[docs/security.md](docs/security.md) for anything you'd rather redact) when
opening an issue - see the bug report template for the full checklist.

## License

[MIT](LICENSE)
