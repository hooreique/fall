{
  description = "Fetch ALL";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    packages.default = pkgs.writeShellApplication {
      name = "fall";
      runtimeInputs = [ pkgs.git pkgs.openssh ];
      text = ''
        if [[ $# -gt 1 ]]; then
          echo -e "\033[31mtoo many args: $*\033[0m\n\n  \033[1mfall --help\033[0m  to get help\n" >&2
          exit 1
        fi

        if [[ $# -eq 1 ]] && [[ "$1" == "--help" ]]; then
          echo -e "\033[1mfall\033[0m – \033[1;4mF\033[0metch \033[1;4mALL\033[0m git repositories

        Run without arguments to fetch all repositories listed in \033[34mrepos.conf\033[0m and display
        their status. Under the hood, it simply loops over each repository and runs \033[33mgit
        fetch && git status\033[0m. it just makes the process quicker and the output easier to
        read.

        \033[1mUsage\033[0m
          fall            \033[90mDefault command\033[0m
          fall \033[32m--help\033[0m     Display this help message
          fall \033[32m--version\033[0m  Print the program version
          fall \033[36madd\033[0m        Add the current directory to \033[34mrepos.conf\033[90m (creates the file if
                          it does not exist)\033[0m
          fall \033[36medit\033[0m       Open \033[34mrepos.conf\033[0m in your \$EDITOR \033[90m(creates the file if it does
                          not exist)\033[0m
          fall \033[36mprev\033[0m       Print the result of the previous fall with its date and time
          fall \033[36mshow\033[0m       Display the contents of \033[34mrepos.conf\033[0m

        \033[1mFile Locations\033[0m \033[90m- Feel free to edit these files yourself\033[0m
          \$HOME/.config/fall/\033[34mrepos.conf\033[0m
          \$HOME/.local/state/fall/prev.txt"
          exit 0
        fi

        if [[ $# -eq 1 ]] && [[ "$1" == "--version" ]]; then
          echo "0.1.0"
          exit 0
        fi

        file="$HOME/.config/fall/repos.conf"

        if [[ $# -eq 1 ]] && [[ "$1" == "show" ]]; then
          if [[ ! -f "$file" ]]; then
            echo -e "\033[31mrepos.conf not found\033[0m\n\n  \033[1mfall --help\033[0m  to get help\n" >&2
            exit 1
          fi
          sed -E "s/^([[:space:]]*#.*)$/$(printf '\033[90m')\1$(printf \
            '\033[0m')/" < "$file"
          exit 0
        fi

        touch() {
          local dir="$HOME/.config/fall"

          if [[ -e "$dir" ]] && [[ ! -d "$dir" ]];then
            echo -e "\033[31m~/.config/fall already exists but it is not a directory\033[0m" >&2
            return 1
          fi

          if [[ -e "$file" ]] && [[ ! -f "$file" ]];then
            echo -e "\033[31mrepos.conf already exists but it is not a file\033[0m" >&2
            return 1
          fi

          mkdir -p "$dir"

          if [[ ! -f "$file" ]]; then
            echo "# Write one path per line. Use absolute paths.
        # Starting with # means comments.
        #/path/to/repo

        # You cannot use \$HOME. Use ~ instead.
        #~/cool stuff
        " > "$file"
          fi
        }

        if [[ $# -eq 1 ]] && [[ "$1" == "add" ]]; then
          touch
          pwd | tee --append "$file"
          echo -e "\033[90mAdded\033[0m"
          exit 0
        fi

        if [[ $# -eq 1 ]] && [[ "$1" == "edit" ]]; then
          touch
          "''${EDITOR:-vi}" "$file"
          exit 0
        fi

        if [[ $# -eq 1 ]] ;then
          echo -e "\033[31munknown option: $1\033[0m\n\n  \033[1mfall --help\033[0m  to get help\n" >&2
          exit 1
        fi

        if [[ ! -f "$file" ]]; then
          echo -e "\033[31mrepos.conf not found\033[0m\n\n  \033[1mfall --help\033[0m  to get help\n" >&2
          exit 1
        fi

        lines="$(wc --lines < "$file")"

        if (( "$lines" >= 100 )); then
          echo -e "\033[31mtoo big\033[90m; The repos.conf file has $lines lines. Please make it less than 100.\033[0m" >&2
          exit 1
        fi

        echo -e "\033[90mfalling... Please wait\033[0m"

        divergeregex='^# branch\.ab '

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
            elif [[ "$line" =~ $divergeregex ]]; then
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

          while (( $(jobs -pr | wc --lines) >= 4 )); do
            wait -n
          done
        done <<< "$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' < "$file")"

        wait
      '';
    };
  });
}
