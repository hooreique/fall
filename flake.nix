{
  description = "fall for Fetch ALL";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    packages.default = pkgs.writeShellApplication {
      name = "fall";
      runtimeInputs = [ pkgs.git ];
      text = ''
        if [[ ! -f "$HOME/repos" ]]; then
          echo "$HOME/repos not found" >&2
          exit 1
        fi

        dirtycheck() {
          if ! git -C "$1" --git-dir=.git --work-tree=. fetch 2> /dev/null; then
            echo -e "$1 \033[31mnot a git repo\033[0m" >&2
            return 1
          fi

          status="$1"

          while IFS= read -r line; do
            if [[ "$line" =~ ^[^#] ]]; then
              status="$status \033[33m±\033[0m"
              break
            elif [[ "$line" == "# branch.ab +0 -0" ]]; then
              continue
            elif [[ "$line" =~ ^#\ branch\.ab ]]; then
              status="$status $(printf '\033[90m%s\033[0m' "''${line:12}")"
            fi
          done <<< "$(git -C "$1" --git-dir=.git --work-tree=. status --porcelain=v2 --branch)"

          if [[ "$status" == "$1" ]]; then
            status="$status \033[32mclean\033[0m"
          fi

          echo -e "$status"
        }

        while IFS= read -r path; do
          if [[ -z "$path" || "$path" =~ ^# ]]; then
            continue
          fi

          if [[ ! -d "$path" ]]; then
            echo -e "$path \033[31mnot found\033[0m" >&2
            continue
          fi

          dirtycheck "$path" &
        done <<< "$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' < "$HOME/repos")"

        wait
      '';
    };
  });
}
