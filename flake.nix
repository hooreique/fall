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
      devShells = forAllSys (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nushell
            pkgs.python3
            pkgs.gitMinimal
          ];
        };
      });

      packages = forAllSys (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "fall";
          version = "1.0.0";
          src = ./.;

          dontUnpack = true;
          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            runHook preInstall

            mkdir -p "$out/bin" "$out/share/fall"
            cp "$src/fall.nu" "$src/codec.nu" "$out/share/fall/"

            makeWrapper "${pkgs.nushell}/bin/nu" "$out/bin/fall" \
              --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.gitMinimal ]}" \
              --set FALL_GIT_SSH_COMMAND "${pkgs.openssh}/bin/ssh" \
              --add-flags "$out/share/fall/fall.nu"

            runHook postInstall
          '';

          meta = {
            mainProgram = "fall";
            description = "Shell helper to fetch and show status of many Git repositories";
            longDescription = ''
              **fall — Fetch ALL**

              *fall* runs `git fetch` and `git status` over every repository path
              listed in `~/.config/fall/repos.conf`, using parallel jobs for speed.
              With `fall .`, it can instead work from a project-local `.repos.conf`
              discovered by walking up the directory tree.
            '';
            homepage = "https://github.com/hooreique/fall";
            license = pkgs.lib.licenses.mit;
          };
        };
      });
    };
}
