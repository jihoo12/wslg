# Shell body used by flake.nix. Do not force backend or renderer selection.
native=0
for arg in "$@"; do
    case "$arg" in
        --) break ;;
        --native) native=1 ;;
    esac
done

case "${LIBGL_ALWAYS_SOFTWARE:-0}" in
    ''|0|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]) force_software=0 ;;
    *) force_software=1 ;;
esac

if [ "$native" = 0 ] && [ -c '@dxg@' ] &&
   [ "${WLR_GLES2_D3D12_SHM:-1}" != 0 ] &&
   [ "${WLR_RENDERER_FORCE_SOFTWARE:-0}" != 1 ] &&
   [ "$force_software" = 0 ] && [ -z "${WLR_RENDER_DRM_DEVICE+x}" ]; then
    case "${WLR_BACKENDS-}" in
        wayland) nested=1 ;;
        '') if [ -n "${WAYLAND_DISPLAY:-}${WAYLAND_SOCKET:-}" ]; then
                nested=1
            else
                nested=0
            fi ;;
        *) nested=0 ;;
    esac
    case "${WLR_RENDERER:-auto}" in
        auto|gles2) ;;
        *) nested=0 ;;
    esac

    if [ "$nested" = 1 ]; then
        export GALLIUM_DRIVER="${GALLIUM_DRIVER:-d3d12}"
        vendor='@mesa@/share/glvnd/egl_vendor.d/50_mesa.json'
        drivers='@mesa@/lib/dri'
        if [ -z "${__EGL_VENDOR_LIBRARY_FILENAMES:-}${__EGL_VENDOR_LIBRARY_DIRS:-}${LIBGL_DRIVERS_PATH:-}" ]; then
            if [ -r "$vendor" ] && [ -d "$drivers" ]; then
                export __EGL_VENDOR_LIBRARY_FILENAMES="$vendor"
                export LIBGL_DRIVERS_PATH="$drivers"
            else
                printf '%s\n' "Nested D3D12: default Mesa EGL manifest or DRI directory not found: $vendor, $drivers" >&2
            fi
        fi

        runtime='@wsl-runtime@'
        if [ -r "$runtime/libdxcore.so" ] && [ -r "$runtime/libd3d12.so" ]; then
            case ":${LD_LIBRARY_PATH:-}:" in
                *":$runtime:"*) ;;
                *) export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$runtime" ;;
            esac
        fi
        if [ "${SHADY_D3D12_DEBUG:-0}" = 1 ]; then
            export EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose
            printf '%s\n' \
                "Nested D3D12: chosen Gallium driver = $GALLIUM_DRIVER" \
                "Nested D3D12: EGL vendor manifest = ${__EGL_VENDOR_LIBRARY_FILENAMES:-<GLVND default>}" \
                "Nested D3D12: DRI driver directory = ${LIBGL_DRIVERS_PATH:-<Mesa default>}" \
                "Nested D3D12: loader dirs = ${LD_LIBRARY_PATH:-<default>}" >&2
        fi
    fi
fi

exec '@shady@' "$@"
