{
  lib,
  stdenvNoCC,
  makeWrapper,
  nushell,
  gitMinimal,
  openssh,
}:

stdenvNoCC.mkDerivation {
  pname = "fall";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./fall.nu
      ./codec.nu
    ];
  };

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/fall"
    cp "$src/fall.nu" "$src/codec.nu" "$out/share/fall/"

    makeWrapper "${nushell}/bin/nu" "$out/bin/fall" \
      --prefix PATH : "${lib.makeBinPath [ gitMinimal ]}" \
      --set FALL_GIT_SSH_COMMAND "${openssh}/bin/ssh" \
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
    license = lib.licenses.mit;
  };
}
