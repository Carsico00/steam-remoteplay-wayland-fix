# Troubleshooting

Always start with:

```bash
steam-remoteplay-wayland-fix doctor
```

and include its full output when opening an issue (see
[docs/security.md](security.md) for what to redact first).

## "streaming_client: not found"

Steam hasn't downloaded the Remote Play component (AppID `202355`) yet.
Open **Remote Play** or **Remote Play Together** from the Steam UI once
(you don't need a peer to connect), then re-run `doctor`.

## "Steam installation: not found"

This project looks under `$HOME/.local/share/Steam`, `$HOME/.steam/steam`,
and `$HOME/.steam/debian-installation`. If you installed Steam somewhere
non-standard, symlink one of those paths to it, or open an issue - the
`steam_candidate_roots` list in `lib/steam.sh` is intentionally short and
explicit rather than guessing.

## "Only a Flatpak install was found; not supported"

Flatpak Steam's files live inside the Flatpak sandbox/app data and are
replaced wholesale on every Flatpak update, which defeats the
Steam-update-resilience this project relies on. Install native Steam
alongside it, or track
[this project's issue tracker](https://github.com/Carsico00/steam-remoteplay-wayland-fix/issues)
if you want to help design Flatpak support.

## "Wrapper is corrupt: streaming_client.real is missing"

Something removed `streaming_client.real` without going through this
project's `uninstall`. Run:

```bash
steam-remoteplay-wayland-fix repair
```

which attempts to restore `streaming_client.real` from the verified backup
in `~/.config/steam-remoteplay-wayland-fix/backups/`. If no usable backup
exists (check `steam-remoteplay-wayland-fix status`), Steam's own
**Verify integrity of game files** (right-click the game in your library,
or for AppID 202355 directly) will re-download a clean original.

## "streaming_client and streaming_client.real are both original binaries but differ"

This project refuses to guess which one is authoritative rather than risk
discarding the wrong one. This can happen if something else (another tool,
a manual experiment) created its own `.real`-style backup independently of
this project. Check `steam-remoteplay-wayland-fix status` and the manifest
at `~/.config/steam-remoteplay-wayland-fix/backups/manifest.tsv`, decide
which file is actually current by comparing timestamps/build ids, then
manually move the correct one into place before re-running `install`.

## Remote Play still crashes after install

1. Confirm the wrapper is actually active: `steam-remoteplay-wayland-fix status`
   should show `Wrapper status: active`.
2. Run the synthetic smoke test: `steam-remoteplay-wayland-fix test`. If
   this crashes, the workaround itself isn't engaging - check
   `~/.config/steam-remoteplay-wayland-fix/env.conf` still has
   `APPLY_X11_WORKAROUND=yes`.
3. Check `coredumpctl list` for a **new** entry after the crash (timestamps
   matter - `doctor` also reports the most recent matching crash it can
   find). If the new crash's stack trace doesn't match the signature in
   [docs/diagnostics.md](diagnostics.md), it's likely a different bug -
   please open an issue with the new backtrace rather than assuming it's
   the same one.
4. Steam updates can overwrite the wrapper (see
   [docs/architecture.md](architecture.md#steam-update-resilience)). Run
   `repair` after any Steam update, or confirm the watcher is enabled:
   `steam-remoteplay-wayland-fix status` shows `Watcher: enabled`.

## The systemd watcher doesn't seem to fire

```bash
systemctl --user status steam-remoteplay-wayland-fix-watcher.path
journalctl --user -u steam-remoteplay-wayland-fix-watcher.service -n 50
```

If the `.path` unit shows `enabled` but never triggers, the most likely
cause is that the CLI's own path (recorded at install time as the
`ExecStart=` target) moved or was deleted - e.g. you ran `install.sh` from
a git checkout directory that was later removed. Re-run `install` from a
stable location, or install the `packaging/PKGBUILD` package instead
(`/usr/bin/steam-remoteplay-wayland-fix` doesn't move).

Even with the watcher disabled or misfiring, running `repair` manually
after a Steam update always works.

## PipeWire desktop capture still fails after all doctor checks pass

See [docs/diagnostics.md](diagnostics.md#problem-5---pipewire-desktop-capture-egl_not_initialized-0x3001--diagnostic).
This project deliberately does not restart or reinstall PipeWire/portal
components, since `doctor`'s checks were designed to tell a real local
misconfiguration apart from a transient/upstream issue. If every check is
green and it still fails, please open an issue - that's new information for
this project, not something we currently have a fix for.

## Uninstalling didn't fully restore my system

`uninstall` restores `streaming_client` from `streaming_client.real` (or,
failing that, from the newest `pristine-real` backup), removes
`streaming_client.real`, `env.conf`, and the systemd watcher units. It does
**not** remove installed packages (e.g. `lib32-egl-wayland`) - those are
general system dependencies that may be used by other things, so removing
them isn't safe to automate. Remove them yourself with
`sudo pacman -R lib32-egl-wayland` if you're sure nothing else needs them.
