#!/bin/sh
# Runs without WSL, Mesa, Nix, or a graphical session.
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
printf 'vendor=%s\ndrivers=%s\nloader=%s\ngallium=%s\noptions=%s\nforced=%s\noverride=%s\nlog=%s\n' \
    "${__EGL_VENDOR_LIBRARY_FILENAMES:-}" "${LIBGL_DRIVERS_PATH:-}" "${LD_LIBRARY_PATH:-}" \
    "$GALLIUM_DRIVER" "$*" "${LIBGL_ALWAYS_SOFTWARE:-}" "${MESA_LOADER_DRIVER_OVERRIDE:-}" "${EGL_LOG_LEVEL:-}"
SH
chmod +x "$tmp/shady"
sed -e "s|@mesa@|$tmp/mesa|g" -e "s|@wsl-runtime@|$tmp/runtime|g" \
    -e "s|@shady@|$tmp/shady|g" -e "s|@foot@|$tmp/foot|g" "$here/launch.sh" > "$tmp/launch"
unset __EGL_VENDOR_LIBRARY_FILENAMES __EGL_VENDOR_LIBRARY_DIRS LIBGL_DRIVERS_PATH LD_LIBRARY_PATH
LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=zink SHADY_D3D12_DEBUG=1 \
    sh "$tmp/launch" -c test.lua > "$tmp/out" 2> "$tmp/err"
grep -Fxq "vendor=$tmp/mesa/share/glvnd/egl_vendor.d/50_mesa.json" "$tmp/out"
grep -Fxq "drivers=$tmp/mesa/lib/dri" "$tmp/out"
grep -Fxq "loader=$tmp/runtime" "$tmp/out"
grep -Fxq 'gallium=d3d12' "$tmp/out"
grep -Fxq "options=-s exec $tmp/foot -c test.lua" "$tmp/out"
grep -Fxq 'forced=' "$tmp/out"
grep -Fxq 'override=' "$tmp/out"
grep -Fxq 'log=debug' "$tmp/out"
grep -Fq "EGL vendor JSON = $tmp/mesa" "$tmp/err"

LD_LIBRARY_PATH="/existing:$tmp/runtime" __EGL_VENDOR_LIBRARY_FILENAMES=/explicit.json \
    LIBGL_DRIVERS_PATH=/explicit/dri sh "$tmp/launch" > "$tmp/out"
grep -Fxq "loader=/existing:$tmp/runtime" "$tmp/out"
grep -Fxq 'vendor=/explicit.json' "$tmp/out"
grep -Fxq 'drivers=/explicit/dri' "$tmp/out"

rm "$tmp/mesa/share/glvnd/egl_vendor.d/50_mesa.json"
if sh "$tmp/launch" > "$tmp/out" 2> "$tmp/err"; then
    echo 'Missing pinned Mesa manifest was not rejected' >&2
    exit 1
fi
grep -Fq 'pinned Mesa EGL manifest or DRI directory is missing' "$tmp/err"
test ! -s "$tmp/out"
echo 'launcher path selection tests passed'
