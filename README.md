# fall

**_fall_** for **_F_**etch **_ALL_**

**_fall_** is a shell script that quickly fetches and shows the status of multiple
git repositories.

## Features

- Runs `git fetch` and `git status` on all repos listed in `~/.config/fall/repos.conf`.
- Uses parallel processing for faster results.
- Commands to view, add, or edit the repo list, and to see previous results.

## Prerequisites

- `nix` and its experimental features
  - `nix command`
  - `flakes`

## Getting Started

You can run `fall` without installing it

```sh
nix run github:hooreique/fall -- --help
```

and of course install it by

```sh
nix profile install github:hooreique/fall
```

or in your flakes

```nix
# e.g. in your /home/foo/.config/home-manager/flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    fall.url = "github:hooreique/fall";
  };

  outputs = inputs: {
    packages.x86_64-linux.homeConfigurations = {
      foo = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          overlays = [
            (final: prev: { fall = inputs.fall.packages.x86_64-linux.default; })
          ];
        };
        # ...
      };
    };
  };
}
```

It is highly recommended to run `fall --help` and read the help message before
running `fall`.

```sh
fall --help
```

You can register your local repository paths in `repos.conf` using either
`fall add` or `fall edit`, then run `fall` to fetch them.

## Usage

```sh
fall       # Fetch all repos and show status
fall show  # Display the repo list
fall add   # Add current directory to the repo list
fall edit  # Edit the repo list
fall prev  # Show previous run output
```

## Config

The repo list is located at `~/.config/fall/repos.conf`

```plaintext
# e.g. in your /home/foo/.config/fall/repos.conf
/path/to/repo

# You can use ~ for $HOME
~/foo/bar
```

## After Uninstall

You can manually remove these files as shown below for a clean system :)

```sh
rm -rf ~/.config/fall ~/.local/state/fall
```
