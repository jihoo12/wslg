{
  description = "Stock Shady with wlroots auto-selecting D3D12 for nested WSLg";

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
    # Keep Shady's source exactly at the pinned upstream revision.
    compositor = pkgs.callPackage "${shady}/nix/package.nix" { inherit wlroots; };
    launcher = pkgs.writeShellScriptBin "shady" (
      builtins.replaceStrings
        [ "@mesa@" "@shady@" "@wsl-runtime@" "@dxg@" ]
        [ "${pkgs.mesa}" "${compositor}/bin/shady" "/usr/lib/wsl/lib" "/dev/dxg" ]
        (builtins.readFile ./launch.sh)
    );
    packagedShady = pkgs.symlinkJoin {
      name = "shady-wslg-auto";
      paths = [ compositor ];
      postBuild = ''
        rm "$out/bin/shady"
        ln -s "${launcher}/bin/shady" "$out/bin/shady"
      '';
      meta.mainProgram = "shady";
    };
  in {
    packages.${system} = {
      inherit wlroots;
      unwrapped = compositor;
      default = packagedShady;
    };
    apps.${system}.default = { type = "app"; program = "${packagedShady}/bin/shady"; };
  };
}
