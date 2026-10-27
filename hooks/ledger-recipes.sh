#!/bin/bash
# ledger-recipes.sh — a deploy request's scope built from config (lanes-parity, 9.1): a recipe
# (`orchestrate.deploy.recipes.<env>`), a train (`orchestrate.deploy.trains.<name>`) or a generated merge, for
# `request --recipe/--train/--merge`, with validation and placeholder substitution. SOURCED by ledger.sh behind
# `[ -f ] || die`; never run on its own. Uses ledger.sh's globals and helpers (DIR, ID, E, die, cfgp).
#
# ledger.sh is over the file limit, so the logic lives here and ledger.sh keeps only dispatch and call-site lines.
