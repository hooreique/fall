{
  description = "Fetch ALL";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    packages.default = pkgs.stdenvNoCC.mkDerivation {
      pname = "fall";
      version = "0.3.0";
      src = ./fall.nu;

      dontUnpack = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/bin" "$out/share/fall"
        cp "$src" "$out/share/fall/fall.nu"

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
}
