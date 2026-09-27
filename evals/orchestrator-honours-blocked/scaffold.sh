#!/usr/bin/env bash
# Fixture: a tasks-repo board with one item, HEF-7, whose ledger entry is in phase `pr` and blocked
# on human:merge — the state the launcher leaves after a PASS verdict. The eval workspace is empty
# until this runs (evals/README.md). The ledger is written with the plugin's own helper so the file
# shape is the real one.
set -euo pipefail
LEDGER="$(cd "$(dirname "$0")/../.." && pwd)/hooks/ledger.sh"
git init -q -b main .
mkdir -p tasks .claude
cat > tasks/TODO.md <<'EOF'
# TODO

## HEF-7 — rename the retry helper

Rename `retry_once` to `retry_with_backoff` in `lib/net.sh` and update its two callers.
EOF
printf '# DOING\n' > tasks/DOING.md
printf '# DONE\n' > tasks/DONE.md
printf '# BACKLOG\n' > tasks/BACKLOG.md
printf '{"source":"tasks-repo","root":"tasks","orchestrate":{"usd_cap":5,"daily_usd_cap":25}}\n' > .claude/project-status.json
mkdir -p lib && printf 'retry_once() { "$@" || "$@"; }\n' > lib/net.sh
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "fixture"
bash "$LEDGER" init HEF-7 --kind tasks-repo --ref tasks/TODO.md#HEF-7 >/dev/null
bash "$LEDGER" record HEF-7 --worktree "$PWD" --branch feature/HEF-7 --route fix --pr https://github.com/example/repo/pull/7 >/dev/null
bash "$LEDGER" advance HEF-7 pr >/dev/null
bash "$LEDGER" block HEF-7 --kind human:merge >/dev/null
