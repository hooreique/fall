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

        lines="$(wc --lines < "$HOME/repos")"

        if (( "$lines" >= 100 )); then
          echo "too big; The repos file has $lines lines. Please make it less than 100." >&2
          exit 1
        fi

        dirtycheck() {
          if ! git --git-dir="$1/.git" --work-tree="$1" rev-parse \
            --is-inside-work-tree > /dev/null
          then
            echo -e "$1 \033[31mnot a git repo\033[0m" >&2
            return 1
          fi

          if ! git --git-dir="$1/.git" --work-tree="$1" fetch; then
            echo -e "$1 \033[31merror occurred\033[90m; Try again later.\033[0m" >&2
            return 1
          fi

          local stat="$1"
          local lb
          local rb

          lb="$(git --git-dir="$1/.git" --work-tree="$1" branch --show-current)"
          rb="$(git --git-dir="$1/.git" --work-tree="$1" rev-parse \
            --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null)" \
            || rb=""

          stat="$stat (\033[34m$lb"
          if [[ -n "$rb" ]]; then
            stat="$stat\033[0m,\033[35m$rb"
          fi
          stat="$stat\033[0m)"

          local before="$stat"

          while IFS= read -r line; do
            if [[ "$line" =~ ^[^#] ]]; then
              stat="$stat \033[33m±\033[0m"
              break
            elif [[ "$line" == "# branch.ab +0 -0" ]]; then
              continue
            elif [[ "$line" =~ ^#\ branch\.ab ]]; then
              stat="$stat \033[90m''${line:12}\033[0m"
            fi
          done <<< "$(git --git-dir="$1/.git" --work-tree="$1" status \
            --porcelain=v2 --branch)"

          if [[ "$stat" == "$before" ]]; then
            stat="$stat \033[32mclean\033[0m"
          fi

          echo -e "$stat"
        }

        while IFS= read -r entry; do
          if [[ -z "$entry" || "$entry" =~ ^# ]]; then
            continue
          fi

          path="''${entry/#~\//$HOME/}"

          if [[ "$path" =~ ^[^/] ]];then
            echo -e "$entry \033[31mnot an absolute path\033[90m; Path must start with slash(/) or tilde(~).\033[0m" >&2
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
