#!/usr/bin/env bash
# Fixture: a project with .specify/ already set up (so the full pipeline is AVAILABLE) and a README
# with one typo. The router must scale down: this is a /hef.fix, not a spec. Mirror of
# spec-first-routing — that case proves the plugin routes UP; this one guards against the
# session-start routing lines pushing a trivial change into ceremony (Scott Logic: ~10x cost).
set -euo pipefail
git init -q -b main .
mkdir -p .specify/specs src tests
printf '# Constitution\n\nSmall changes stay small.\n' > .specify/constitution.md
cat > README.md <<'MD'
# ledger

A tiny ledger CLI.

## Install

    pip install -e .

You will recieve a confirmation line when the install completes.

## Usage

    ledger add 12.50 "coffee"
MD
printf 'def add(entries, amount, note):\n    return entries + [(amount, note)]\n' > src/ledger.py
printf 'from src.ledger import add\n\ndef test_add():\n    assert add([], 1.0, "x") == [(1.0, "x")]\n' > tests/test_ledger.py
printf '[project]\nname = "ledger"\nversion = "0.1.0"\n' > pyproject.toml
git add -A && git -c user.email=fixture@eval -c user.name=fixture commit -q -m "chore: ledger baseline"
