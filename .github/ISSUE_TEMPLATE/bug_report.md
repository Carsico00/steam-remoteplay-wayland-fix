---
name: Bug report
about: Something isn't working as expected
title: ""
labels: bug
---

**Please do not paste your SteamID, session certificates, or relay
addresses.** See [docs/security.md](../../docs/security.md) for what to
redact before pasting logs.

## Environment

- Distribution:
- Kernel (`uname -r`):
- Desktop environment:
- Session type (Wayland / X11):
- GPU:
- NVIDIA driver version (if applicable):
- Steam version/branch (stable / beta):
- Steam build id (visible in `doctor` output, or Steam > Help > About):

## `doctor` output

```
(paste the full output of `steam-remoteplay-wayland-fix doctor` here)
```

## Coredump summary (if `streaming_client` crashed)

```
(paste the output of `coredumpctl list | grep streaming_client`, and if
possible `coredumpctl info <pid>`, here)
```

## What happened with Remote Play

- [ ] `streaming_client` crashed immediately
- [ ] `streaming_client` stayed alive but the game never launched
- [ ] The game launched but video didn't work
- [ ] The game launched but audio didn't work
- [ ] The game launched but controller input didn't work
- [ ] Something else (describe below)

## What you expected to happen

## Additional context
