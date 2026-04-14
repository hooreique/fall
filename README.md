# fall

**_fall_** for _**F**etch **ALL**_;

<img src="./demo.gif" alt="demo.gif">

**_fall_** is a Nushell program that quickly fetches and shows the status of
multiple git repositories.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Config](#config)
- [After Uninstall](#after-uninstall)
- [Contributing](#contributing)

## Features

- Runs `git fetch` and `git status` on all repos listed in
  `~/.config/fall/repos.conf`.
- Uses parallel processing for faster results.
- Commands to view, add, or edit the repo list, and to see previous results.
- Supports _local mode_ (`fall .`) which uses the nearest `.repos.conf`.

## Prerequisites

- For Nix usage, `nix` and its experimental features
  - `nix command`
  - `flakes`
- For direct non-Nix usage, `nu` and `git` available on `PATH`
  - SSH remotes also need an SSH client available to Git

## Getting Started

You can run `fall` without installing it

```sh
nix run github:hooreique/fall -- --help
```

You can also run the Nushell script directly without Nix:

```sh
nu fall.nu --help
```

Or fetch the script from GitHub and run it immediately:

```sh
curl -fsSL https://raw.githubusercontent.com/hooreique/fall/main/fall.nu \
  | nu --stdin /dev/stdin -- --help
```

Direct non-Nix usage intentionally relies on your environment's `nu` and `git`.
For SSH remotes, it also relies on whatever SSH command your Git uses.
When installed or run through Nix flakes, `nu`, `git`, and `ssh` are pinned by
the package.

Install it with:

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

  outputs = inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        (final: prev: { fall = inputs.fall.packages.${system}.default; })
      ];
    };
  in {
    homeConfigurations.foo = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        {
          home.packages = [ pkgs.fall ];
        }
      ];
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
# Global mode
fall       # Fetch all repos and show status
fall show  # Display the repo list
fall add   # Add current directory to the repo list
fall edit  # Edit the repo list
fall prev  # Show previous run output

# Local mode
fall .     # Use the nearest .repos.conf
```

For direct non-Nix usage, run the same commands as `nu fall.nu ...`.

## Config

The global repo list is located at `~/.config/fall/repos.conf`

```plaintext
# e.g. in your /home/foo/.config/fall/repos.conf
/path/to/repo

# You can use ~ for $HOME
~/foo/bar
```

You can also create as many local repo lists as you want, wherever you want.

```plaintext
# e.g. in your ~/example-project/.repos.conf
path/to/repo

# Note: you should use relative paths, not absolute ones.
# The paths will be resolved relative to the location of this file.
```

## After Uninstall

You can manually remove these files for a clean system :)

```sh
rm ~/.config/fall/repos.conf ~/.local/state/fall/prev.txt
```

## Contributing

Contributions are welcome.
