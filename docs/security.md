# Security notes

## What this project touches

- A single file inside your Steam installation:
  `<Steam root>/ubuntu12_64/streaming_client` (replaced with a wrapper
  script; the original is preserved as `streaming_client.real` next to it).
- `~/.config/steam-remoteplay-wayland-fix/` (its own config, state, backups,
  and logs - nothing outside this directory and the one file above).
- Optionally, `~/.config/systemd/user/steam-remoteplay-wayland-fix-watcher.{path,service}`.
- System packages, only via `sudo pacman -S --needed <pkg>` with pacman's
  own confirmation prompt, and only for packages a real check proved
  missing (see [docs/diagnostics.md](diagnostics.md)). It never touches the
  NVIDIA driver package, never downgrades anything, and never runs
  `pacman -Syu` or similar.

It never touches your Steam login, credentials, saved games, or any file
outside the paths above.

## Threat model / what we deliberately do NOT do

- No network access of any kind - everything runs locally.
- No telemetry, no phone-home, no update-check pings.
- No `curl | bash` in the installer - `install.sh` execs the local
  `bin/steam-remoteplay-wayland-fix` from the same checkout.
- No `--noconfirm` passed to `pacman` unless you explicitly opt into
  `--yes` at the `steam-remoteplay-wayland-fix` level (and even then,
  `pacman` itself is invoked in a way that still shows its own prompt
  unless you also chose to pre-answer it - see `lib/deps.sh:install_pkg`).
- No destructive operations: nothing is deleted without first being copied
  into `~/.config/steam-remoteplay-wayland-fix/backups/` with a recorded
  hash (see `lib/backup.sh`).

## Reporting a vulnerability

If you find a security issue specific to this project (not to Steam/NVIDIA
themselves - report those upstream, see [docs/upstream.md](upstream.md)),
please open a GitHub issue. This is a small community tool, not a
security-critical service, so there's no separate private disclosure
process - just be clear in the title that it's a security report.

## Sanitizing diagnostics before sharing them

`steam-remoteplay-wayland-fix doctor` output is designed to avoid printing
sensitive data (no SteamIDs, no session certs, no relay tokens - it never
reads an active Remote Play session's connection data at all). Before
pasting output into a public issue, double-check for and redact:

- Your Linux username, if it appears in file paths (`/home/<you>/...`) and
  you'd rather not share it.
- Hostnames, if `hostname` output was included some other way.
- Any Steam session log excerpts you attach separately (not produced by
  this tool) - `streaming_client`'s own logs
  (`~/.local/share/Steam/logs/streaming_log.txt`) can contain your
  SteamID64, session certificates, and relay server addresses tied to a
  live session. This project's own output does not include these, but if
  you attach that log file too, redact `--cert`, `--steamid`, and
  `--relay` values first.

## Notes for this repository's history

The bug report and test suite that this project was built from were
developed against a real system; all example command lines, log excerpts,
and test fixtures in this repository have been rewritten with placeholder
values (`0`, dummy IPs like `127.0.0.1`, synthetic certs like `AAAA`) - no
real SteamID, session certificate, relay address, or personally
identifying path is committed anywhere in this repository.
