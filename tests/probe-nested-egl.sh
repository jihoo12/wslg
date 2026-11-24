#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export PATH="$tmp:$PATH"
export WAYLAND_DISPLAY="wayland-fixture"
cat > "$tmp/wayland-info" <<'SH'
#!/bin/sh
if [ "${REGISTRY_FAIL:-0}" = 1 ]; then exit 1; fi
printf "interface: 'wl_shm', version: 1, name: 2\n"
if [ "${DMABUF:-0}" -gt 0 ]; then
    printf "interface: 'zwp_linux_dmabuf_v1', version: %s, name: 3\n" "$DMABUF"
fi
if [ "${LEGACY:-0}" -gt 0 ]; then
    printf "interface: 'wl_drm', version: %s, name: 4\n" "$LEGACY"
fi
SH
cat > "$tmp/eglinfo" <<'SH'
#!/bin/sh
cat <<'INFO'
GBM platform:
EGL API version: 1.5
EGL driver name: not-the-wayland-driver
Wayland platform:
EGL API version: 1.5
EGL driver name: wayland-fixture-driver
X11 platform:
EGL driver name: also-not-the-wayland-driver
INFO
SH
chmod +x "$tmp/wayland-info" "$tmp/eglinfo"
probe="$root/samples/probe-nested-egl.sh"

"$probe" > "$tmp/out"
grep -Fq 'No Wayland global advertises a DRM device' "$tmp/out"
grep -Fq 'EGL driver name: wayland-fixture-driver' "$tmp/out"
if grep -Fq 'not-the-wayland-driver' "$tmp/out"; then echo 'Leaked a different EGL platform' >&2; exit 1; fi
grep -Fq 'Nested EGL presentation: not verified' "$tmp/out"

DMABUF=3 "$probe" > "$tmp/out"
grep -Fq 'has no feedback main_device event' "$tmp/out"
LEGACY=2 DMABUF=3 "$probe" > "$tmp/out"
grep -Fq 'Legacy wl_drm is advertised' "$tmp/out"

printf 'Creating GLES2 renderer\nFailed to open /dev/udmabuf\n' > "$tmp/nested.log"
DMABUF=4 "$probe" "$tmp/nested.log" > "$tmp/out"
grep -Fq 'main_device and import are not verified' "$tmp/out"
grep -Fq 'Creating GLES2 renderer' "$tmp/out"
grep -Fq 'Failed to open /dev/udmabuf' "$tmp/out"
grep -Fq 'Nested EGL presentation: not verified' "$tmp/out"

if REGISTRY_FAIL=1 "$probe" > "$tmp/out" 2>&1; then
    echo 'Expected registry failure' >&2
    exit 1
fi
grep -Fq 'no capability result' "$tmp/out"
if grep -Fq 'No Wayland global advertises a DRM device' "$tmp/out"; then echo 'Failed query was reported as a capability result' >&2; exit 1; fi

echo 'nested EGL probe fixtures passed'
