{
  description = "Experimental D3D12 GLES2 rendering with wl_shm presentation for nested Shady on WSLg";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b25309931cfda5f0b8805f462a29897eeae50168";
  inputs.shady.url = "github:gloaming-dusk/shady/9ecf64248f87f3d65d0c4ad6cca666c3001ba2ca";
  inputs.shady.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, shady, ... }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    wlroots = pkgs.wlroots_0_20.overrideAttrs (old: {
      version = "0.20.2";
      src = pkgs.fetchFromGitLab {
        domain = "gitlab.freedesktop.org";
        owner = "wlroots";
        repo = "wlroots";
        rev = "0.20.2";
        hash = "sha256-VdYymvzYp6/R255AK20j4xTd+JbCZgNiRfgeRJD+UZY=";
      };
      patches = (old.patches or []) ++ [ ./wlroots-0.20.2-d3d12-shm.patch ];
    });
    compositor = (pkgs.callPackage "${shady}/nix/package.nix" { inherit wlroots; }).overrideAttrs (old: {
      patches = (old.patches or []) ++ [ ./shady-drop-failed-render-pass.patch ];
    });
    runShady = pkgs.writeShellScript "shady-d3d12-shm" ''
      unset LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE
      export WLR_BACKENDS=wayland WLR_RENDERER=gles2 WLR_GLES2_D3D12_SHM=1
      export GALLIUM_DRIVER=d3d12
      exec ${compositor}/bin/shady -s 'exec ${pkgs.foot}/bin/foot' "$@"
    '';
  in {
    packages.${system} = {
      inherit compositor wlroots;
      default = compositor;
    };
    apps.${system}.default = { type = "app"; program = "${runShady}"; };
  };
}
