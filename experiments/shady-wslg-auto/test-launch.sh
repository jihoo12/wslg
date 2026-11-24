#!/bin/sh
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/mesa/share/glvnd/egl_vendor.d" "$tmp/mesa/lib/dri" "$tmp/runtime"
: > "$tmp/mesa/share/glvnd/egl_vendor.d/50_mesa.json"
: > "$tmp/runtime/libdxcore.so"
: > "$tmp/runtime/libd3d12.so"
cat > "$tmp/shady" <<'SH'
#!/bin/sh
printf 'vendor=%s\ndrivers=%s\nloader=%s\ngallium=%s\nbackend=%s\nrenderer=%s\nopt=%s\n' \
    "${__EGL_VENDOR_LIBRARY_FILENAMES:-}" "${LIBGL_DRIVERS_PATH:-}" "${LD_LIBRARY_PATH:-}" \
    "${GALLIUM_DRIVER:-}" "${WLR_BACKENDS:-}" "${WLR_RENDERER:-}" "${WLR_GLES2_D3D12_SHM:-}"
for arg in "$@"; do printf 'arg=%s\n' "$arg"; done
SH
chmod +x "$tmp/shady"
render_wrapper() {
    sed -e "s|@mesa@|$tmp/mesa|g" -e "s|@wsl-runtime@|$tmp/runtime|g" \
        -e "s|@shady@|$tmp/shady|g" -e "s|@dxg@|$1|g" "$here/launch.sh" > "$tmp/launch"
}
unset __EGL_VENDOR_LIBRARY_FILENAMES __EGL_VENDOR_LIBRARY_DIRS LIBGL_DRIVERS_PATH LD_LIBRARY_PATH GALLIUM_DRIVER
unset WLR_BACKENDS WLR_RENDERER WLR_GLES2_D3D12_SHM WLR_RENDERER_FORCE_SOFTWARE WLR_RENDER_DRM_DEVICE LIBGL_ALWAYS_SOFTWARE WAYLAND_DISPLAY WAYLAND_SOCKET
render_wrapper /dev/null  # fake char device for the shell gate only
WAYLAND_DISPLAY=wayland-0 SHADY_D3D12_DEBUG=1 sh "$tmp/launch" -s 'exec foot' > "$tmp/out" 2> "$tmp/err"
grep -Fxq "vendor=$tmp/mesa/share/glvnd/egl_vendor.d/50_mesa.json" "$tmp/out"
grep -Fxq "drivers=$tmp/mesa/lib/dri" "$tmp/out"
grep -Fxq "loader=$tmp/runtime" "$tmp/out"
grep -Fxq 'gallium=d3d12' "$tmp/out"
grep -Fxq 'backend=' "$tmp/out"
grep -Fxq 'renderer=' "$tmp/out"
grep -Fxq 'opt=' "$tmp/out"
grep -Fxq 'arg=-s' "$tmp/out"
grep -Fxq 'arg=exec foot' "$tmp/out"
grep -Fq 'chosen Gallium driver = d3d12' "$tmp/err"

WAYLAND_DISPLAY=wayland-0 WLR_RENDERER=pixman sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
grep -Fxq 'renderer=pixman' "$tmp/out"
WAYLAND_DISPLAY=wayland-0 WLR_GLES2_D3D12_SHM=0 sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
WAYLAND_DISPLAY=wayland-0 LIBGL_ALWAYS_SOFTWARE=True sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
WAYLAND_DISPLAY=wayland-0 sh "$tmp/launch" --native > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
grep -Fxq 'arg=--native' "$tmp/out"
WLR_BACKENDS=headless WAYLAND_DISPLAY=wayland-0 sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
env -u WAYLAND_DISPLAY -u WAYLAND_SOCKET sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
WAYLAND_SOCKET=9 LD_LIBRARY_PATH="/existing:$tmp/runtime" GALLIUM_DRIVER=explicit \
    __EGL_VENDOR_LIBRARY_FILENAMES=/explicit.json LIBGL_DRIVERS_PATH=/explicit/dri sh "$tmp/launch" > "$tmp/out"
grep -Fxq "loader=/existing:$tmp/runtime" "$tmp/out"
grep -Fxq 'gallium=explicit' "$tmp/out"
grep -Fxq 'vendor=/explicit.json' "$tmp/out"
grep -Fxq 'drivers=/explicit/dri' "$tmp/out"

render_wrapper "$tmp/no-dxg"
WAYLAND_DISPLAY=wayland-0 sh "$tmp/launch" > "$tmp/out"
grep -Fxq 'gallium=' "$tmp/out"
echo 'launcher gate and path selection tests passed'
