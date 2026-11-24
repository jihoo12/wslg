# Testing EGL in a nested Wayland compositor on WSLg

A native GUI app rendering via Mesa D3D12 can work while a nested wlroots
compositor cannot start its GLES2 renderer. A successful `eglInitialize` is
not proof that either path can present frames. For the latter, distinguish:

1. The Wayland server advertises a usable device, or the nested backend has
   its own valid alternative. A DMA-BUF global at version 3 does not carry
   the `main_device` event. A manually created or visible DRM device node is
   not proof that EGL/GBM can use it.
2. The nested compositor creates a GLES2 renderer **and** an allocator.
   [WSLg #1532](https://github.com/microsoft/wslg/issues/1532) reports a
   software renderer which initialized but could not allocate without
   UDMABUF in the tested kernel.
3. The nested compositor renders and presents: open a client on its own
   Wayland display and verify a visibly changing frame in the **nested**
   window. A renderer creation log line, a regular WSLg client window and a
   DMA-BUF registry advertisement are individually insufficient.

From the WSL user distribution with WSLg active, run:

```sh
sh samples/probe-nested-egl.sh
# Optionally include a log captured from the nested compositor:
sh samples/probe-nested-egl.sh /path/to/shady.log
```

The probe requires `wayland-info` (from `wayland-utils`). If present,
`eglinfo` and `timeout` provide an ordinary-client Wayland EGL init check.
To test ordinary Wayland presentation separately, if available run
`weston-simple-egl` against the original WSLg display and check that its
animated triangle appears and moves. This still does not test nesting.

For [WSLg #1531](https://github.com/microsoft/wslg/issues/1531), run the
nested compositor with its Wayland backend, e.g.
`WLR_BACKENDS=wayland nix run github:gloaming-dusk/shady`, and capture the
renderer/allocator log. Use the child display reported by that instance for
the changing-frame test rather than the original WSLg display. Keep the
ordinary client running or retest it after changes to detect regressions.
The probe makes no system changes and does not report a presentation pass.

## Separate experiments by layer

- **Stock kernel, WSLg-side change:** retain the RDP desktop and per-window
  presentation paths. For a DMA-BUF experiment, use a real import path and
  advertise only supported formats/modifiers on a usable device. Then test
  both real buffer import and RDP/RAIL presentation. Advertising a global
  alone, or pointing it at a dummy render node, is not a fix.
- **Stock WSLg, software nested path:** explore a surfaceless GLES2 renderer
  and SHM-compatible output in the nested wlroots compositor (including
  allocator/readback). This is not a WSLg-only change, and would not imply
  GPU acceleration.
- **Kernel experiment:** test UDMABUF/device changes separately from the
  WSLg system-distro image. The image cannot change the WSL2 kernel.

Record the kernel and WSLg versions for each run. If changing vendor files,
assign the test image an explicit marker or local commit, since the image
builder records Git HEADs rather than hashes of dirty working files.
