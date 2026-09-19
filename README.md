# fall

**_fall_** for _**F**etch **ALL**_;

<img src="./demo.gif" alt="demo.gif">

**_fall_** is a Nushell program that fetches and shows the status of multiple
Git repositories in parallel.

## Features

- Manage a global repo list or use a project-local `.repos.conf`.
- Fetch repositories together, check status offline, or control fetch per repo.
- View, add, and edit repositories, and review previous results.

## Getting Started

With Nix (`nix-command` and `flakes` enabled), try fall without installing it:

```sh
nix run github:hooreique/fall -- --help
```

Or install it:

```sh
nix profile install github:hooreique/fall
```

From a checkout, you can also run `nu fall.nu --help` with Nushell and Git on
`PATH` (plus an SSH client for SSH remotes). See [Installation](docs/installation.md)
for script downloads and a Home Manager flake example.

Register a repository, then fetch and check your repo list:

```sh
cd /path/to/repo
fall add
fall
```

## Usage

```sh
fall          # Fetch enabled repos and show all statuses
fall status   # Show statuses without fetching
fall show     # Display the repo list
fall add      # Add the current directory to the repo list
fall edit     # Edit the repo list
fall prev     # Show previous run output
fall test     # Validate the global config without fetching

fall .        # Use the nearest .repos.conf, searching upwards
fall status . # Check local-list statuses without fetching
fall test .   # Validate the nearest .repos.conf
```

Every command supports `--help`, including `fall . --help`.
For direct script usage, replace `fall` with `nu fall.nu`.

Global fetch and status runs save results to `~/.local/state/fall/prev.txt`;
local runs leave it unchanged. Without a successful fetch, ahead/behind counts
use locally stored remote-tracking information and may be stale.

## Config

Use `fall add` or `fall edit` to manage `~/.config/fall/repos.conf`:

```plaintext
~/projects/app
~/my\ repo upstream
! ~/projects/offline
? ~/projects/sometimes-unreachable
```

Escape spaces in paths as `\ `. Prefix an entry with `! ` to skip fetch, or
`? ` to continue with local status if fetch fails. An entry can also select a
remote and branch: `~/projects/app origin main`.

For local mode, create a `.repos.conf` with paths relative to that file's
directory. Global entries use absolute paths or `~/`.

See the [Configuration reference](docs/configuration.md) for the full syntax,
path codec, remote and branch behavior, validation, and migration notes.

## After Uninstall

Remove the saved configuration and results if you no longer need them:

```sh
rm ~/.config/fall/repos.conf ~/.local/state/fall/prev.txt
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and guidelines on
keeping the README concise and maintaining detailed documentation separately.
