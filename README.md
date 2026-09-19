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
- Supports offline status checks and skipping fetch for individual repositories.
- Can continue with local status when an optional fetch fails.

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

Or download both scripts into the same directory and run them:

```sh
mkdir -p fall-scripts
cd fall-scripts
curl -fsSLO https://raw.githubusercontent.com/hooreique/fall/main/fall.nu
curl -fsSLO https://raw.githubusercontent.com/hooreique/fall/main/codec.nu
nu fall.nu --help
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
fall       # Fetch enabled repos and show all statuses
fall status # Show all statuses without fetching; update prev.txt
fall show  # Display the repo list
fall add   # Add current directory to the repo list
fall edit  # Edit the repo list
fall prev  # Show previous run output
fall test  # Validate the global config without fetching

# Local mode
fall .     # Use the nearest .repos.conf
fall test . # Validate the nearest .repos.conf
fall status . # Show statuses without fetching or changing prev.txt
```

Start with the command overview, then open help for the command or mode you need:

```sh
fall --help           # Brief overview of commands and options
fall edit --help      # Editor behavior and core config syntax
fall status --help    # Global and local status modes
fall status . --help  # Only local status behavior
fall test . --help    # Only local validation behavior
```

Every command supports `--help`, including `fall . --help`. Help works without
config files or Git repositories and does not create or change files.
See [Config](#config) for the complete configuration rules.

For direct non-Nix usage, run the same commands as `nu fall.nu ...`.

`fall status` skips fetch for every entry. Ahead/behind counts use locally stored
remote-tracking information, which may be stale. Global runs save results to
`~/.local/state/fall/prev.txt`; local runs leave that file unchanged.

## Config

The global repo list is located at `~/.config/fall/repos.conf`

```plaintext
# e.g. in your /home/foo/.config/fall/repos.conf
/path/to/repo

# You can use ~ for $HOME
~/foo/bar
~/cool\ stuff upstream
! ~/offline\ repo
? ~/occasionally-unreachable\ repo
```

You can also create as many local repo lists as you want, wherever you want.

```plaintext
# e.g. in your ~/example-project/.repos.conf
path/to/repo

# Note: you should use relative paths, not absolute ones.
# The paths will be resolved relative to the location of this file.
```

Prefix a line with `! ` to skip fetch for that repository in normal runs while
still showing its status. Prefix with `? ` to attempt fetch normally but continue
with local status if fetch fails. Failed optional fetch output is replaced by a
yellow warning on stderr: `<path> fetch failed; showing local status`. After a
failed fetch, ahead/behind counts use locally stored remote-tracking information,
which may be stale. Successful fetches keep their usual output and status behavior.
Both status commands skip fetch for all three modes. Global runs save warnings
and statuses to `prev.txt`; local runs leave it unchanged.

`!` or `?` must be the first character and followed by one or
more ASCII spaces; all separator spaces are consumed before decoding the path.
Bare prefixes, `!repo`, `?repo`, and prefixes immediately followed by a tab are
errors. Empty paths, nested prefixes, and paths beginning with `!` or `?` are
unsupported. Optional mode tolerates only
fetch failures; configuration, path, and repository validation still applies.
The existing process exit code policy is unchanged.

Each entry uses `[prefix]path [remote [remote-branch]]`, for example `? ~/my\ repo upstream`.
The optional remote must exactly match one name listed by `git remote` in that
repository. It is read and written literally, without escaping or unescaping;
whitespace and backslashes are forbidden. Repeated ASCII spaces between fields
and trailing separator spaces are allowed. A fourth field before any inline comment is a syntax error.
Fields are strictly positional: `path main` selects remote `main` and fails if
that remote is unregistered; it never means branch `main`.
The optional third field is a literal branch name without whitespace or backslashes,
validated with `git check-ref-format refs/heads/<branch>`.

After the path, the first ASCII-space-separated token starting with `#` begins
an inline comment; everything from that token to the end of the line is ignored.
This works in both global and local configs, with or without `!` or `?`:

```plaintext
path # description
path origin #description
path origin main # description
```

A `#` in a path or inside a field (such as `repo#1` or `origin#1`) stays literal.
Remote and branch values cannot start with `#`. Backslashes and tabs inside
comments are ignored; invalid or extra fields before the comment still fail.
Blank lines and lines whose first non-whitespace character is `#` are ignored.

An explicit remote runs `git fetch -- <remote>`. Multiple remotes, direct URLs,
and remote groups are unsupported. Omitting the remote preserves the existing
argument-free `git fetch`, including Git's upstream/default remote selection and
`fetch.all` setting. With no remote-branch, status and ahead/behind counts keep
using the branch's upstream, even when fetching a different remote. Remote validation also applies
to `!` and `?` entries, `fall status`, and `fall test`; an unregistered remote is
a configuration error and that entry is not executed.

With `path origin main`, status compares `HEAD` with
`refs/remotes/origin/main` using `git rev-list --left-right --count`:

```text
/project (feature → origin/main) ahead 2, behind 1
/project (feature → origin/main) up-to-date ±
```

Counts describe HEAD relative to the selected target, independently of upstream
settings. `±` indicates working-file changes from porcelain status. Detached HEAD
is displayed as `HEAD@<short-hash>`. Missing target refs or a HEAD without commits
produce `comparison unavailable: <reason>`; working-file status and other
repositories are still processed, without falling back to upstream.
Fetch policies remain unchanged, including required-fetch failures skipping status.
Only the standard `refs/remotes/<remote>/<remote-branch>` location is used;
custom refspec destinations are not discovered automatically.

Paths use a strict codec: escape each ASCII space as `\ `, including repeated,
leading, and trailing spaces. The first unescaped ASCII space ends the path and
separates the optional remote. Tabs and quotes are literal path characters,
not quoting syntax. Backslashes in paths, other escapes, a dangling backslash,
empty paths, and CR/LF input are errors. Use LF line endings.

Blank or whitespace-only lines and lines whose first non-whitespace character
is `#` are ignored. Other lines are read exactly as written, without trimming.
Global entries must be absolute paths (or start with `~/`); local entries must
be relative to the selected config's directory. `/` and trailing slashes are
unsupported. `$HOME` is not expanded.

`fall test` validates the global config; `fall test .` searches upwards for the
nearest `.repos.conf` and prints `.repos.conf at: <absolute path>` first.
Validation checks decoding, path rules, directory existence, and Git repository
roots, then registered remote names and branch-name validity in order, skipping dependent checks on a
failed entry but continuing with all remaining entries. Normal repositories and worktrees are accepted;
repository subdirectories and bare repositories are rejected. `fall test` does
not require the comparison ref or a HEAD commit to exist.

Validation exits **0 only if every entry is valid and the entire file has at
most 100 lines**; otherwise it exits **1**, including missing or unreadable files.
Blank lines and comments count toward the limit. Even over the limit, all entries
are checked, with errors showing the filename, line number, original line, and
reason, followed by checked/succeeded/failed counts. An empty config succeeds.
Normal execution uses the same 100-line limit and path rules.

Validation never fetches, runs Git status, creates or changes config files, or
writes `prev.txt`. A missing-directory error includes a conditional reminder
about escaping spaces; it never retries the whole line as an alternative path.
`fall add` creates ordinary entries with required fetch and no remote, and checks duplicates using decoded
paths regardless of fetch mode, remote, or remote-branch. Any
existing decoding errors are all reported and prevent adding an entry.

There is no legacy syntax compatibility or automatic migration. Update existing
space-containing paths to use `\ ` before running `fall`. Suffixes are no longer
ignored: remove old suffix text or replace it with a registered remote and optional branch name.

## Tests

```sh
nu codec-test.nu
nix shell --inputs-from . nixpkgs#python3 -c python3 cli-test.py
nix build
nix shell --inputs-from . nixpkgs#python3 -c python3 cli-test.py ./result/bin/fall
```

The CLI suite uses temporary configurations and repositories, including a
worktree, and checks exit codes, diagnostics, boundaries, and state preservation.

## After Uninstall

You can manually remove these files for a clean system :)

```sh
rm ~/.config/fall/repos.conf ~/.local/state/fall/prev.txt
```

## Contributing

Contributions are welcome.
