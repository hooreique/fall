# Contributing

Contributions are welcome. Keep changes focused and update the documentation
when user-facing behavior changes.

## Keep the README concise

The [README](README.md) is an introduction and quick start. It should help a new
user understand what fall does, get it running, and find the basic commands.

- Mention a new feature in the README only when it helps that first-use flow.
  Keep the description short and link to the details.
- Put detailed syntax, codec rules, configuration processing, edge cases,
  diagnostics, and advanced examples in focused documents under `docs/`.
  Create a new document whenever a topic needs its own explanation.
- Update the relevant reference instead of appending each feature's full
  explanation to the README. Keep each detailed explanation in one place and
  link to it from summaries.
- Keep development and test instructions in this file. Keep command help in
  sync with behavior changes.
- When reviewing a change, check that the README still reads as a quick start,
  that details are easy to find, and that relative links work.

These guidelines apply to both human and AI-assisted contributions.

## Where documentation belongs

- [Installation](docs/installation.md): direct script usage, Nix installation,
  and the Home Manager flake example.
- [Configuration reference](docs/configuration.md): repo lists, fetch policies,
  remotes and branches, path codec rules, validation, and migration notes.
- `docs/<topic>.md`: additional guides or references as features grow. Link new
  documents from the relevant existing guide or README section.

## Tests

For code changes, run the checks relevant to the behavior being changed.
For documentation-only changes, check examples, links, and consistency with
existing behavior; the full code test suite is not required.

The development shell provides Nushell, Python, and Git pinned by `flake.lock`.

```sh
nix develop -c nu codec-test.nu
nix develop -c python3 test.py
nix build
nix develop -c python3 test.py ./result/bin/fall
```

The CLI suite uses temporary configurations and repositories, including a
worktree, and checks exit codes, diagnostics, boundaries, and state preservation.
Without an argument, `test.py` runs `fall.nu` with Nushell from PATH; with an
executable path, it tests that executable instead. Pull request CI builds the
package and tests `result/bin/fall` once on each supported system
(`x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`).
