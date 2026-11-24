# Probe: offscreen D3D12 GLES2 and shader readback on WSL

This is a gate for a possible GPU-accelerated nested compositor, **not a
renderer change**. Run in the WSL user distro, with the same Mesa build and
runtime environment as the compositor under test. The system-distro Mesa
build does not determine the user distro's driver.

```sh
env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE \
    GALLIUM_DRIVER=d3d12 python3 samples/probe-d3d12-egl-readback.py
```

Requirements: Python 3 (standard library only), a Mesa EGL loader
(`libEGL.so.1`, with `EGL_MESA_platform_surfaceless`), Mesa's D3D12
Gallium driver, a working WSL GPU stack exposing `/dev/dxg` and WSL's
D3D12/DXCore runtime libraries discoverable by that Mesa. To target a
particular adapter, pass its description substring through
`MESA_D3D12_DEFAULT_ADAPTER_NAME`, such as `NVIDIA`. No kernel or WSLg
settings are modified.

The probe creates a GLES2 context, compiles a fragment shader, draws into
an offscreen framebuffer, then checks every RGBA pixel read back. Python
only calls the native EGL/GLES functions; it does not render the pixels.
Success requires the expected pixels, a named D3D12 adapter (known
software renderer names are rejected), and a character device at
`/dev/dxg`. Exit 2 means the pixels matched but the adapter or device
criterion did not; exit 1 means EGL/shader/readback failed. The reported
adapter name alone is not an independent hardware utilization reading:
compare it with the intended adapter and verify usage under a longer load.

For example, [the Mesa 23.1.0 revision recorded in WSLg](https://gitlab.freedesktop.org/mesa/mesa/-/tree/be4f7fb656180ab55a50eff01f36672b0bf5f146)
can enter its surfaceless EGL loader's software-winsys path without a DRM
node; that Gallium loader can still instantiate the D3D12 DXCore driver.
Thus a loader label such as `swrast` does not decide whether shaders run on
the CPU. Check `GL_RENDERER` from the actual process. Newer or separately
packaged Mesa configurations can behave differently.

## What this does not test

No Wayland window is created. The probe does not test Shady's shaders,
Wayland buffer release, or WSLg/RDP presentation. For an opt-in nested
wlroots prototype, the next step is to retain an offscreen GLES2 FBO for
the real renderer and run the Shady shader on it. Read the output into a
released SHM buffer in the correct row order, pixel format and stride and
commit it to the parent Wayland surface. Do not reuse a buffer before
`wl_buffer.release`. Validate resize, buffer reuse, distinct animated
shader frames, and throughput before making performance claims.

wlroots 0.20.2's current GLES2 auto-creation expects a DRM FD, its GLES2
initialization requires DMA-BUF import, and its render target is DMA-BUF.
A context probe does not remove those gates. A readback bridge would
need an explicit EGL setup, an offscreen render-target implementation and
SHM presentation support; it must not pass with Pixman/llvmpipe. The
GPU-to-CPU transfer is not CPU rasterization, but it is not zero-copy.
