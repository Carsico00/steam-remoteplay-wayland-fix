# Notes toward a real upstream fix

This document is written for whoever picks up
[ValveSoftware/steam-for-linux#13179](https://github.com/ValveSoftware/steam-for-linux/issues/13179)
(or the SDL3 / NVIDIA `egl-wayland` side of it) - what we know, what we
don't, and why a workaround is where this project stops.

## What we know for certain

Reproducible stack trace (multiple independent captures, same shape):

```
#0 pthread_mutex_lock              (libc.so.6)
#1 wl_proxy_create_wrapper         (libwayland-client.so.0)
#2 <anonymous>                     (libnvidia-egl-wayland.so.1)
#3 <anonymous>                     (libEGL_nvidia.so.0)
#4 <anonymous>                     (libEGL_nvidia.so.0)
#5 <anonymous>                     (libEGL.so.1)
#6 <anonymous>                     (libSDL3.so.0)
...
#N streaming_client.real
```

- `streaming_client.real` is a 64-bit binary using `libSDL3.so.0` for window
  creation, running under a Wayland session with the proprietary NVIDIA
  driver's EGLStream-based Wayland platform (`libnvidia-egl-wayland.so.1`,
  built from [NVIDIA/egl-wayland](https://github.com/NVIDIA/egl-wayland),
  publicly available source).
- The crash is a `SIGSEGV` **inside `pthread_mutex_lock` itself**, called
  from `wl_proxy_create_wrapper()`. `wl_proxy_create_wrapper` (libwayland,
  also open source) locks the originating `wl_display`'s internal mutex as
  part of creating a proxy wrapper for use from a different thread/queue.
  `pthread_mutex_lock` segfaulting (rather than deadlocking or returning an
  error) is consistent with the mutex/display/proxy pointer it was handed
  being invalid - NULL, already freed, or never fully initialized on the
  calling thread.
- The same NVIDIA Wayland EGL library is reached from a second, unrelated
  call site - Steam's overlay (`gameoverlayrenderer.so`) calling
  `eglGetDisplay()` - which also does not need to happen at all if the
  overlay simply isn't loaded (matches Problem 2/upstream steam-runtime#811:
  the overlay has no supported EGL/Wayland path in the first place).
- Forcing the EGL/SDL backend to X11 for this one process avoids
  `libnvidia-egl-wayland.so.1` entirely, and the crash reproducibly does not
  occur (validated live for this project - see the repository's test
  history / README "Real-world validation").

## What we do not know (and did not fabricate)

We do not have a debug build of `streaming_client`, SDL3, or
`libnvidia-egl-wayland.so.1` with matching symbols, so we cannot point at an
exact line of source that is wrong. The `n/a` frames in the trace (`libEGL_nvidia.so.0`,
`libnvidia-egl-wayland.so.1`) are from NVIDIA's proprietary EGL dispatch
library and closed pieces of the driver, not from the open `egl-wayland`
repository directly - so even the open-source frame (`wl_proxy_create_wrapper`)
is being called from closed code we cannot inspect here. **We are not
publishing a source-level diff, because we cannot verify one against the
actual crashing code paths from the information available to this
project.** Anyone with a debug build and access to NVIDIA's driver
engineering (or a from-source `libnvidia-egl-wayland` build with
`AddressSanitizer`) is far better positioned to pin this down than a
guessed patch would be.

## What we'd ask Valve/NVIDIA/SDL to actually investigate

1. **SDL3 side**: does `streaming_client`'s SDL3 window/EGL context creation
   happen on a thread other than the one that owns the `wl_display`'s event
   queue (e.g. a render thread created after the main thread has already
   started dispatching Wayland events)? `wl_proxy_create_wrapper` is
   specifically for cross-thread/cross-queue proxy use and has documented
   preconditions about the source proxy's queue and the display's roundtrip
   state; a violation there is a very plausible root cause for a NULL/freed
   mutex.
2. **NVIDIA `egl-wayland` side**: under what conditions does
   `libnvidia-egl-wayland.so.1` call `wl_proxy_create_wrapper()` on a
   `wl_display` that might not be the one that originally created the EGL
   platform display, or might already be in the process of being torn down?
   A minimal reproducer against upstream `NVIDIA/egl-wayland` (a small SDL3
   program that opens and closes an EGL window on Wayland from a background
   thread, in a loop) would either confirm or rule this out without needing
   Steam at all.
3. **Steam overlay side**: tracked separately as
   [steam-for-linux#8020](https://github.com/ValveSoftware/steam-for-linux/issues/8020) -
   giving the overlay a real EGL/Wayland capture path (rather than only
   GLX/X11 WSI) removes the second call site into the same fragile code
   entirely.

## Why "just use X11" is not an acceptable general answer

This project deliberately does **not** recommend switching the desktop
session to X11, and the wrapper forces X11 only for the `streaming_client`
child process while the rest of the session stays on Wayland, because:

- Some users are on Wayland-only compositors with no practical X11 fallback.
- Session-wide X11 gives up Wayland's fractional scaling, HDR/color
  management work, and per-app input isolation for the *entire* desktop to
  work around a bug in *one* Steam subprocess.
- It's not a fix - it's exactly the same "avoid the broken code path"
  workaround this project applies, just at a much larger blast radius, and
  it stops working the moment something else in the session also needs
  Wayland-specific behavior.

A real fix means `streaming_client` and the overlay working correctly
**while remaining Wayland-native**, which requires the investigation above,
not a bigger hammer.
