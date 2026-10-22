#!/bin/bash
# lane-launch.sh — replaced in 8.0.0 (lanes-v3 FR-020). A launcher that runs `claude` itself cannot pass through
# a wrapper such as `claude-profile`, so the lanes now open with plain `claude --name <repo>-<lane>` after a
# one-time setup that writes the lane permissions into the project's .claude/settings.local.json. This stub
# fails loudly (exit 2) with the two commands, so a script or habit that still calls it learns the new way.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat >&2 <<MSG
lane-launch.sh was replaced in hefesto 8.0.0. Instead:
  1. once per project, in its main folder:   bash $H/hefesto-setup.sh            (four lanes: add --lanes)
  2. open each lane with any launcher:        claude --name <repo>-<orchestrator|plan|build|deploy>
     e.g. claude-profile <profile> --name <repo>-plan
The quick start (docs/quickstart.md) has the rest.
MSG
exit 2
