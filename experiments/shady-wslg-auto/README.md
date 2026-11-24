# Nested Shady: default WSLg GPU renderer

This experiment keeps **Shady 0.5.1 source unmodified** and changes only
its wlroots dependency and package launcher. No changes to the Windows
host, the WSLg system distro/VHD, or its Weston server are needed. An
existing Shady binary linked to a stock wlroots does not acquire the
new path by itself.

## Try without installing (x86_64 WSL, active WSLg, Nix flakes)

```sh
nix run --refresh --no-write-lock-file \
  'github:jihoo12/wslg?ref=yoi/shady-wslg-auto&dir=experiments/shady-wslg-auto'
```

The package passes arguments through. To launch a terminal inside it,
append `-- -s 'exec foot'` if Foot is installed in your WSL distro.
Do not use Shady's `--safe` option for testing spatial shader effects.
Once verified, you can install the same flake in a Nix profile and use
the normal `shady` command from that profile:

```sh
nix profile install \
  'github:jihoo12/wslg?ref=yoi/shady-wslg-auto&dir=experiments/shady-wslg-auto'
shady
```

Use `command -v shady` if another installation is already in PATH.

## When it selects the GPU path

wlroots first retains the default Linux DRM/GLES2 path. The D3D12 path
is considered only for a single real nested Wayland backend with
`wl_shm`, no usable parent DRM fd, and a character device at
`/dev/dxg`. For automatic detection, the connected Wayland socket must
match the standard WSLg socket at `/mnt/wslg/runtime-dir/wayland-0`.
A symlink alias is fine. Native DRM, other backends, and explicit
Pixman/Vulkan/DRM/software requests are unchanged. For a deliberately
non-standard WSLg socket use `WLR_GLES2_D3D12_SHM=1`; this only bypasses
the socket identity check. `WLR_GLES2_D3D12_SHM=0` disables the path.
If EGL fails, standard renderer selection continues (Pixman may start
only if the compositor permits it; Shady spatial mode requires GLES2).

The package launcher supplies its pinned Mesa EGL/DRI paths and WSL
runtime library path when appropriate, but does not force
`WLR_BACKENDS` or `WLR_RENDERER` and preserves user overrides.
`SHADY_D3D12_DEBUG=1` prints its EGL/DRI choices and enables Mesa
diagnostics. The pinned Mesa is 26.1.8; it need not match your system
Mesa. Do not prepend an entire distro library directory to the Nix
process to force a match.

## What to check

- Logs show a named hardware adapter in `GL renderer: D3D12 (...)` and
  `D3D12 GLES2 active; using GPU readback to wl_shm`.
- The nested app and actual moving shader effects are visible, colors
  and orientation are right, and the window survives repeated resize.
  Log output alone is insufficient.
- D3D12 renders shaders; the full frame is copied over SHM for
  presentation. It is neither zero-copy DMA-BUF nor CPU rasterization.
  This renderer does not advertise DMA-BUF or explicit sync. If
  readback fails, wlroots rejects the failed frame instead of sending
  old pixels from its reusable SHM buffer.

The patch applies to wlroots 0.20.2
(`d783533489e1f75d6886c2ab5c5960090ef268f8`); Shady is rebuilt from
upstream `9ecf64248f87f3d65d0c4ad6cca666c3001ba2ca`. Both compile,
Shady passes nine unit tests, and the linked renderer-selection
fixtures and launcher fixtures pass. The full WSLg GPU presentation
test still needs a WSLg/WSL hardware environment.
