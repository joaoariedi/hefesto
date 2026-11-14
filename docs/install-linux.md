# Install on Linux

[← back to README](../README.md)

This page installs hefesto on Linux: the tools, the one install command, the check. What comes after — setting a
project up and choosing a single lane or four lanes — is the [quick start](quickstart.md). On Windows, install WSL 2
first ([Install on Windows (WSL)](install-windows.md)), then follow this page in its terminal. On a Mac:
[Install on macOS](install-macos.md).

## 1. The tools

hefesto runs inside [Claude Code](https://code.claude.com/docs/en/setup) (the `claude` command). It also needs
`git` and `jq`, and `gh` for pull requests and GitHub boards. The lanes run inside Claude Code's sandbox, which on
Linux needs `bubblewrap` and `socat`.

| | Install the tools |
|---|---|
| **Ubuntu / Debian** | `sudo apt install git jq bubblewrap socat`, and gh from [cli.github.com](https://cli.github.com) |
| **Fedora** | `sudo dnf install git jq bubblewrap socat gh` |
| **Arch** | `sudo pacman -S git jq bubblewrap socat github-cli` |

Then sign gh in once: `gh auth login`.

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
