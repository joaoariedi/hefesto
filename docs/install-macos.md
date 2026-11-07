# Install on macOS

[← back to README](../README.md)

This page installs hefesto on macOS: the tools, the one install command, the check. What comes after — setting a
project up and choosing a single lane or four lanes — is the [quick start](quickstart.md). On Linux:
[Install on Linux](install-linux.md); on Windows: [Install on Windows (WSL)](install-windows.md).

## 1. The tools

hefesto runs inside [Claude Code](https://code.claude.com/docs/en/setup) (the `claude` command). It also needs
`git` and `jq`, and `gh` for pull requests and GitHub boards. macOS has Claude Code's sandbox built in.

| | Install the tools |
|---|---|
| **macOS** | `xcode-select --install` (git), then `brew install jq gh` |

Then sign gh in once: `gh auth login`. Everything runs with the shipped `/bin/bash` 3.2 and BSD tools; no Homebrew
bash or coreutils is needed. Where macOS has no `timeout`, the bundled `hooks/run-bounded.sh` stands in, and a
`smoke-macos` CI job runs the whole test suite on macOS.

## 2. Install

The same command installs hefesto and upgrades it. Close every Claude Code window, then in a normal terminal (not
inside a Claude Code session):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/main/install.sh)
```

The wizard shows what it found and the steps it recommends, and asks about each one — press Enter to accept; it never
runs `sudo`, and it copies any file it replaces to `~/hefesto-old/` first. Options: `--lang pt` (Portuguese),
`--dry-run` (show the plan, change nothing), `--version <tag|main>` (one release), `--help` (the rest). All of them, and everything the
wizard does: [`install.md`](install.md) §1.

To run a specific release's copy of the script instead of `main`'s, pin the tag — the release you want, 7.10.0 or
later (earlier tags do not carry `install.sh`):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joaoariedi/hefesto/v<X.Y.Z>/install.sh)
```

Or clone first and read the script before you run it:

```bash
git clone https://github.com/joaoariedi/hefesto.git ~/.claude-framework
bash ~/.claude-framework/install.sh
```

## 3. Check

Open Claude Code and run `/hefesto:hef.doctor`. The wizard itself ends with
`All good: every profile runs hefesto <version>.`

## Next

Set a project up: the [quick start](quickstart.md), section 3 ([em português](quickstart.pt-BR.md)). Or let Claude
guide you through it: [`SETUP.md`](../SETUP.md).
