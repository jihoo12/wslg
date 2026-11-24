#!/bin/sh
# Read-only view of the display actually used by a nested Wayland compositor.
set -eu

if [ "${1-}" = --help ]; then
    echo "Usage: $0 [nested-compositor-log]"
    echo "Run in the WSL user distro; no settings or services are changed."
    exit 0
fi
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ ! -r "$1" ]; }; then
    printf '%s\n' "Usage: $0 [readable-nested-compositor-log]" >&2
    exit 2
fi
if ! command -v wayland-info >/dev/null 2>&1; then
    printf '%s\n' "wayland-info is required (packaged as wayland-utils)." >&2
    exit 2
fi

printf 'Kernel: %s\n' "$(uname -r)"
if [ -r /mnt/wslg/versions.txt ]; then
    printf '\nWSLg image markers:\n'
    cat /mnt/wslg/versions.txt
fi
printf '\nWayland display: %s\n' "${WAYLAND_DISPLAY:-wayland-0}"
query_registry() {
    if command -v timeout >/dev/null 2>&1; then timeout 10 wayland-info
    else wayland-info; fi
}
if ! registry=$(query_registry); then
    printf '%s\n' "Could not query the Wayland registry; no capability result." >&2
    exit 2
fi

# wayland-info prints each global as a record with an interface and a version.
version_of() {
    printf '%s\n' "$registry" | awk -F"'" -v iface="$1" '
        $1 ~ /^interface:[[:space:]]*$/ && $2 == iface && $3 ~ /version:[[:space:]]*[0-9]/ {
            v = $3; sub(/^.*version:[[:space:]]*/, "", v); sub(/[^0-9].*$/, "", v);
            if ((v + 0) > max) max = v + 0
        }
        END { print max + 0 }
    '
}

dmabuf=$(version_of zwp_linux_dmabuf_v1)
legacy_drm=$(version_of wl_drm)
shm=$(version_of wl_shm)
printf 'wl_shm version: %s\nzwp_linux_dmabuf_v1 version: %s\nwl_drm version: %s\n' "$shm" "$dmabuf" "$legacy_drm"
case "$dmabuf:$legacy_drm" in
    0:0) echo "No Wayland global advertises a DRM device for nested wlroots discovery." ;;
    *)
        if [ "$dmabuf" -ge 4 ]; then
            echo "DMA-BUF feedback is available in the protocol version; main_device and import are not verified."
        elif [ "$legacy_drm" -gt 0 ]; then
            echo "Legacy wl_drm is advertised; its device event and actual access are not verified."
        else
            echo "DMA-BUF v$dmabuf advertises formats but has no feedback main_device event."
        fi
        ;;
esac

printf '\nDevice visibility (permission bits are not a DRM/GBM test):\n'
found=0
for node in /dev/dri/renderD*; do
    [ -c "$node" ] || continue
    found=1
    if [ -r "$node" ] && [ -w "$node" ]; then
        printf '  %s: readable and writable\n' "$node"
    else
        printf '  %s: missing read or write access\n' "$node"
    fi
done
[ "$found" -ne 0 ] || echo "  No DRM render node."
for node in /dev/dxg /dev/udmabuf; do
    if [ -c "$node" ]; then printf '  %s: present\n' "$node"
    else printf '  %s: absent\n' "$node"; fi
done

if command -v eglinfo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    printf '\nEGL ordinary-client probe (Wayland platform only):\n'
    egl_output=$(timeout 10 eglinfo -B 2>&1 || :)
    ordinary=$(printf '%s\n' "$egl_output" | awk '
        /^Wayland platform:/ { show = 1; next }
        /^[[:alnum:]].* platform:/ { show = 0 }
        show && /EGL (API version|vendor string|driver name):|eglInitialize failed/ { print }
    ')
    if [ -n "$ordinary" ]; then printf '%s\n' "$ordinary"
    else echo "  No recognizable Wayland EGL initialization result."; fi
    echo "  EGL initialization is not an eglSwapBuffers/presentation test."
fi

if [ "$#" -eq 1 ]; then
    printf '\nNested compositor evidence (from the supplied log):\n'
    if ! grep -Ei 'no DRM (FD|render)|Creating (GLES2|pixman|Vulkan) renderer|udmabuf|failed.*(allocat|renderer|commit|present)|(^|[[:space:]])EGL' "$1"; then
        echo "  No matching renderer/allocator lines."
    fi
fi

printf '\nNested EGL presentation: not verified by this probe.\n'
echo "For a pass, verify GLES2 plus allocator success and a visible changing frame from a nested client."
