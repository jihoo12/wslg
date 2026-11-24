# Shell body installed by flake.nix with these four absolute paths substituted.
unset LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE
export WLR_BACKENDS=wayland WLR_RENDERER=gles2 WLR_GLES2_D3D12_SHM=1
export GALLIUM_DRIVER=d3d12

# Choose Mesa's manifest and DRI directory together by default; never add
# an entire host distro library directory to a Nix process.
if [ -z "${__EGL_VENDOR_LIBRARY_FILENAMES:-}${__EGL_VENDOR_LIBRARY_DIRS:-}${LIBGL_DRIVERS_PATH:-}" ]; then
    vendor='@mesa@/share/glvnd/egl_vendor.d/50_mesa.json'
    drivers='@mesa@/lib/dri'
    if [ ! -r "$vendor" ] || [ ! -d "$drivers" ]; then
        printf '%s\n' "D3D12 SHM: pinned Mesa EGL manifest or DRI directory is missing: $vendor, $drivers" >&2
        exit 1
    fi
    export __EGL_VENDOR_LIBRARY_FILENAMES="$vendor"
    export LIBGL_DRIVERS_PATH="$drivers"
fi

runtime='@wsl-runtime@'
if [ -r "$runtime/libdxcore.so" ] && [ -r "$runtime/libd3d12.so" ]; then
    case ":${LD_LIBRARY_PATH:-}:" in
        *":$runtime:"*) ;;
        *) export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$runtime" ;;
    esac
else
    printf '%s\n' "D3D12 SHM: standard WSL DXCore/D3D12 libraries were not both found in $runtime; using existing loader paths." >&2
fi

if [ "${SHADY_D3D12_DEBUG:-0}" = 1 ]; then
    export EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose
    printf '%s\n' \
        "D3D12 SHM: EGL vendor JSON = ${__EGL_VENDOR_LIBRARY_FILENAMES:-<GLVND default>}" \
        "D3D12 SHM: EGL vendor directories = ${__EGL_VENDOR_LIBRARY_DIRS:-<GLVND default>}" \
        "D3D12 SHM: DRI driver directory = ${LIBGL_DRIVERS_PATH:-<Mesa default>}" \
        "D3D12 SHM: WSL runtime directory = $runtime" >&2
fi

exec '@shady@' -s 'exec @foot@' "$@"
