# Install on Windows (WSL)

[← back to README](../README.md)

hefesto needs **WSL 2** — its hooks and installer are bash scripts for a Linux or macOS userland, and Claude Code's
sandbox on Linux uses `bubblewrap`, which needs the WSL 2 kernel. Native Windows is not supported.

1. Install WSL 2 with a Linux distribution, following Microsoft's guide:
   [learn.microsoft.com/windows/wsl/install](https://learn.microsoft.com/windows/wsl/install) — `wsl --install` in
   an administrator PowerShell.
2. Open that distribution's terminal. Run everything from here on inside it, not in PowerShell or `cmd`.
3. Install Claude Code inside the distribution: [code.claude.com/docs/en/setup](https://code.claude.com/docs/en/setup).

**From here on, follow [Install on Linux](install-linux.md)** in that terminal — every step is the same.
