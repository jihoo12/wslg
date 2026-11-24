# Experimental Shady GPU path on WSLg

This builds a **nested Shady client**, not a custom WSLg VHD. Weston and
the Windows host are unchanged. The patches preserve Shady's own GLES2
effects and depth/stencil pipeline: Mesa D3D12 draws each frame into an
offscreen GL framebuffer, then its pixels are copied into a Wayland
shared-memory buffer for the existing parent-window transport. This is
GPU rendering with a CPU-visible copy, not zero-copy DMA-BUF and not a
software rendering fallback.

## Try on x86_64 WSL

Prerequisites: Nix with flakes, an active WSLg Wayland socket, and the WSL
GPU/Mesa D3D12 setup which passed the
[offscreen test](https://github.com/jihoo12/wslg/tree/yoi/d3d12-egl-probe).
Run in the same WSL user distro and graphics environment as that test.

```sh
nix run --no-write-lock-file 'github:jihoo12/wslg?ref=yoi/shady-d3d12-shm&dir=experiments/shady-d3d12-shm'
```

The wrapper explicitly selects the Wayland backend and D3D12 GLES2 mode,
then starts `foot` inside the new Shady window. Do not add `--safe`: it
disables Shady's spatial effects. No global environment settings are
changed. If the Nix-built process loads a different EGL vendor or Mesa
from the probe, match its runtime loader to the working WSL setup before
comparing the result. A non-D3D12 driver or no `/dev/dxg` fails explicitly;
there is no quiet Pixman fallback with the opt-in.

Start from a pinned source pair: wlroots 0.20.2
(`d783533489e1f75d6886c2ab5c5960090ef268f8`) and Shady
(`9ecf64248f87f3d65d0c4ad6cca666c3001ba2ca`, 0.5.1). Both patch files can
also be applied to those source trees directly. Without the launcher flag,
the patched wlroots retains its usual renderer selection. Shady's small
companion patch only prevents presenting an old frame when a render pass
fails.

## Verify after launch

- The compositor itself should log `GL renderer: D3D12 (...)` naming the
  target GPU and `D3D12 GLES2 active; using GPU readback to wl_shm`.
- The nested window and its terminal should show up independently of a
  normal WSLg terminal. Move the child window and switch an animated
  Shady effect; confirm actual visible changes, correct colors and
  orientation, and repeated resizing. A log alone is not a pass.
- The copy reads back the full output and synchronizes the GL pipeline,
  so this first experiment is not a frame-rate or latency claim. Nested
  clients should use SHM buffers; the mode deliberately does not
  advertise DMA-BUF or explicit sync. Its Wayland backend continues to
  wait for buffer release before reuse.

Both pinned source trees were compiled with the patches, including the
linked Shady executable. The C tests verify adapter-name rejection,
RGBA/BGRA conversion, alpha, row preservation, padded stride and bounds.
The linked wlroots constructor was also checked to refuse Pixman and
missing `/dev/dxg` when opted in. The complete nested window and effects
have not been run on WSLg.
