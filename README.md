# fall

**_fall_** for _**F**etch **ALL**_;

<img src="./demo.gif" alt="demo.gif">

**_fall_** is a shell script that quickly fetches and shows the status of
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
# Global mode
fall       # Fetch all repos and show status
fall show  # Display the repo list
fall add   # Add current directory to the repo list
fall edit  # Edit the repo list
fall prev  # Show previous run output

# Local mode
fall .     # Use the nearest .repos.conf
```

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
