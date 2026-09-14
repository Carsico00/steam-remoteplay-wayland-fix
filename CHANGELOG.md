# Changelog

## v0.1.0

Initial release.

- `install`/`uninstall`/`status`/`doctor`/`repair`/`test` CLI.
- NVIDIA + Wayland detection, gated workaround (AMD/Intel/X11/nouveau left
  untouched).
- Verifiable backup/restore of Steam's original `streaming_client`.
- Wrapper state machine handling first install, idempotent reinstall, Steam
  updates overwriting the file, pre-existing foreign wrappers, and
  corruption - with a structural recursion guard.
- 32-bit NVIDIA EGL/Wayland dependency check and opt-in `pacman` fix.
- Read-only PipeWire/xdg-desktop-portal/DRM diagnostics.
- `coredumpctl`-based crash signature recognition.
- Optional `systemd --user` watcher for automatic post-update repair.
- Synthetic smoke test of the graphics/EGL init crash path.
- Arch `PKGBUILD`, GitHub Actions CI (ShellCheck, test suite,
  install/uninstall smoke test, PKGBUILD validation).
- Validated live against the original reproduction system (CachyOS, KDE
  Plasma, Wayland, NVIDIA RTX 2070 SUPER, driver 580.178.04) - see
  README "Real-world validation".
