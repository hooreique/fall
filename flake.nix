{
  description = "Fetch ALL";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSys =
        perSys:
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ] (
          system: perSys nixpkgs.legacyPackages.${system}
        );
    in
    {
      overlays.default = final: prev: {
        fall = final.callPackage ./package.nix { };
      };

      packages = forAllSys (pkgs: {
        fall = pkgs.callPackage ./package.nix { };
        default = pkgs.callPackage ./package.nix { };
      });

      devShells = forAllSys (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nushell
            pkgs.python3
            pkgs.gitMinimal
          ];
        };
      });
    };
}
