# Installation

[Back to README](../README.md#getting-started)

## Run with Nix without installing

With Nix (`nix-command` and `flakes` enabled), run `fall` without installing it:

```sh
nix run github:hooreique/fall -- --help
```

## Run from a checkout

From a checkout, run the Nushell script directly:

```sh
nu fall.nu --help
```

Running from a checkout relies on your environment's `nu` and `git`.
For SSH remotes, it also relies on whatever SSH command your Git uses.
When installed or run through Nix flakes, `nu`, `git`, and `ssh` are pinned by
the package.

## Install with Nix

Install it with:

```sh
nix profile install github:hooreique/fall
```

## Home Manager flake example

Add `fall` to your flake:

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
