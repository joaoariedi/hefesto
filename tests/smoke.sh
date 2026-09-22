#!/usr/bin/env bash
#
# Smoke test for the plugin itself.
#
# This framework's recurring failure mode is a component that validates cleanly and
# never runs: the plugin installs, `claude plugin list` says enabled, and every command
# is dead. Four consecutive commits on main were fixes of exactly that shape. A linter or
# a JSON-schema check would have passed all four.
#
# So this test asserts behaviour, not shape.
#
#   Tier 1 (default)  — structural + regression checks. No auth, no model, no tokens.
#   Tier 2 (SMOKE_LIVE=1) — installs the plugin into a throwaway CLAUDE_CONFIG_DIR and
#                           runs a real command headlessly against a scratch repo.
#                           Needs a working `claude` login. Spends tokens.
#
# Usage:
#   tests/smoke.sh              # tier 1
#   SMOKE_LIVE=1 tests/smoke.sh # tier 1 + 2
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/hooks/speckit-helper.sh"
PASS=0
FAIL=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# NEVER write `producer | grep -q pattern` in this script.
#
# `set -o pipefail` is on, and `grep -q` exits the instant it matches. The producer then dies
# with SIGPIPE (141), pipefail makes the PIPELINE return 141, and the `if` reads that as "no
# match" — so a violating file reports as clean. Worse, it is a race: on a small input the
# producer finishes before grep exits and the check works, which is how three guards in this
# suite passed their own mutation tests while being unreliable.
#
# Capture first, match second: `x="$(producer)"` then `grep -q ... <<<"$x"`. No pipe, no race.

# --- Tier 1: manifest ---------------------------------------------------------------
head_ "Manifest"

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .mcp.json; do
  if jq empty "$REPO/$f" 2>/dev/null; then ok "$f parses"; else bad "$f is missing or invalid JSON"; fi
done

# Every path plugin.json declares must exist. A typo here disables a whole component
# silently — the plugin still installs and reports enabled.
while read -r key path; do
  [ -z "$path" ] && continue
  if [ -e "$REPO/${path#./}" ]; then ok "plugin.json $key -> $path exists"
  else bad "plugin.json $key -> $path DOES NOT EXIST (component will not load)"; fi
done < <(jq -r '{skills,commands,hooks,workflows,mcpServers}
                | to_entries[] | select(.value | type == "string")
                | "\(.key)\t\(.value)"' "$REPO/.claude-plugin/plugin.json")

while read -r agent; do
  if [ -f "$REPO/${agent#./}" ]; then ok "agent $(basename "$agent") exists"
  else bad "agent $agent DOES NOT EXIST"; fi
done < <(jq -r '.agents[]?' "$REPO/.claude-plugin/plugin.json")

# --- Tier 1: version consistency ------------------------------------------------------
head_ "Version"

# Five places declare the version and every one is bumped BY HAND. A release that updates
# plugin.json but forgets marketplace.json ships a plugin whose marketplace advertises the
# old version — and nothing else notices. (#19)
v_plugin="$(jq -r '.version' "$REPO/.claude-plugin/plugin.json")"
v_mkt_meta="$(jq -r '.metadata.version' "$REPO/.claude-plugin/marketplace.json")"
v_mkt_plug="$(jq -r '.plugins[0].version' "$REPO/.claude-plugin/marketplace.json")"
v_readme="$(grep -oE 'Framework Version\*\*: [0-9]+\.[0-9]+\.[0-9]+' "$REPO/README.md" | grep -oE '[0-9.]+$')"
v_changelog="$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$REPO/CHANGELOG.md" | tr -d '#[] ')"

mismatch=0
for pair in "marketplace.metadata:$v_mkt_meta" "marketplace.plugins[0]:$v_mkt_plug" \
            "README footer:$v_readme" "CHANGELOG latest entry:$v_changelog"; do
  where="${pair%%:*}"; val="${pair#*:}"
  if [ "$val" != "$v_plugin" ]; then
    bad "$where says $val but plugin.json says $v_plugin"
    mismatch=$((mismatch + 1))
  fi
done

# The title carries only major.minor. README dropped out of this loop when its header became the
# mercury-style centred lockup: the version there is now a shields dynamic/json badge that reads
# .claude-plugin/plugin.json over raw.githubusercontent, so that surface cannot drift by hand and
# has nothing left to assert. Re-adding a literal version to the README purely to satisfy this
# check would reintroduce the exact hand-bumped duplicate #19 exists to eliminate.
minor="${v_plugin%.*}"
for f in .claude/CLAUDE.md; do
  t="$(grep -m1 -oE 'Hefesto v[0-9]+\.[0-9]+' "$REPO/$f" | grep -oE '[0-9.]+$')"
  if [ "$t" != "$minor" ]; then
    bad "$f title says v$t but plugin.json says $v_plugin"
    mismatch=$((mismatch + 1))
  fi
done
[ "$mismatch" -eq 0 ] && ok "all five version declarations agree ($v_plugin)"

# --- Tier 1: the #9 regression guard ------------------------------------------------
head_ "Payload location"

# The plugin's payload must NOT live under .claude/. That path is also where Claude Code
# looks for *project-scope* config, so shipping it there means that while working in this
# repo the project-scope copy shadows the plugin's — and a project-scope command gets no
# plugin root, so ${CLAUDE_PLUGIN_ROOT} is never substituted.
#
# The effect is that the commands behave differently here than in any real install. That is
# the blind spot that let #7 ship: it looked fine while dogfooding. See #9.
shadowed=0
for d in commands agents skills hooks workflows; do
  if [ -e "$REPO/.claude/$d" ]; then
    bad ".claude/$d shadows the plugin's own $d when working in this repo (see #9)"
    shadowed=$((shadowed + 1))
  fi
done
[ "$shadowed" -eq 0 ] && ok "no plugin payload under .claude/ — nothing shadows the plugin"

# --- Tier 1: skills are well-formed --------------------------------------------------
head_ "Skills"

# A skill is a directory with SKILL.md carrying name+description frontmatter; a bare .md or a
# missing field is silently ignored and never loads. Reference guidance migrated out of rules/
# lives here now (pipeline-security, mcp-security, quality-tooling, agent-collaboration), so a
# malformed one silently loses that guidance.
for d in "$REPO"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if [ ! -f "$d/SKILL.md" ]; then bad "skill $name has no SKILL.md — it will not load"; continue; fi
  fm="$(sed -n '/^---$/,/^---$/p' "$d/SKILL.md")"
  if grep -qE '^name:' <<<"$fm" && grep -qE '^description:' <<<"$fm"; then
    ok "skill $name has name+description frontmatter"
  else
    bad "skill $name is missing name or description frontmatter — it will not register"
  fi
done

# The rules migrated to skills must be gone from rules/ AND unreferenced as `<name>.md` anywhere
# outside skills/ — a stale pointer sends a reader to a file that no longer exists. This is the
# exact cross-cutting-reference failure the migration had to chase down.
migrated_bad=0
for r in pipeline-security mcp-security quality-tooling; do
  [ -e "$REPO/.claude/rules/$r.md" ] && { bad "rules/$r.md still exists — migrated to skills/$r, must be removed"; migrated_bad=$((migrated_bad + 1)); }
  refs="$(grep -rlF "$r.md" "$REPO/.claude/rules" "$REPO/agents" "$REPO/commands" "$REPO/docs" "$REPO/README.md" 2>/dev/null || true)"
  if [ -n "$refs" ]; then bad "$r.md still referenced (stale pointer): $(tr '\n' ' ' <<<"$refs")"; migrated_bad=$((migrated_bad + 1)); fi
done
[ "$migrated_bad" -eq 0 ] && ok "migrated reference rules are gone and unreferenced as .md files"

# --- Tier 1: built-in name collisions ------------------------------------------------
head_ "Command names"

# A command whose name a Claude Code BUILT-IN already owns is unreachable: typing the bare
# name gets the built-in, every time. `/context` shipped that way and nobody noticed for four
# releases, because the repo's own project-scope copy shadowed the built-in while dogfooding —
# so it worked here and nowhere else. Fixing that shadowing (#9) is what exposed it.
#
# This used to be a hand-maintained list of built-in names, which guarded the past and not the
# future: the day Claude Code ships a /quality, that command goes silently unreachable and a
# stale list says nothing (#17).
#
# So the rule is structural instead. Every command is NAMESPACED — its name contains a `.`
# (hef.quality, speckit.plan). No built-in slash command contains a dot, so a collision is
# impossible by construction, and there is no list to keep current.
unnamespaced=0
for f in "$REPO"/commands/*.md; do
  name="$(basename "$f" .md)"
  case "$name" in
    *.*) : ;;
    *)
      bad "command /$name is not namespaced — a Claude Code built-in of that name would silently shadow it (#17)"
      unnamespaced=$((unnamespaced + 1))
      ;;
  esac
done
[ "$unnamespaced" -eq 0 ] && ok "every command is namespaced — no built-in can collide with any of them"

# --- Tier 1: hooks ------------------------------------------------------------------
head_ "Hooks"

while read -r cmd; do
  script="${cmd#\"\$\{CLAUDE_PLUGIN_ROOT\}\"}"
  script="$REPO/${script#/}"
  script="${script%% *}"
  name="$(basename "$script")"
  if [ ! -f "$script" ]; then bad "hook $name is declared but not shipped"
  elif [ ! -x "$script" ]; then bad "hook $name is not executable (will fail silently)"
  else ok "hook $name exists and is executable"; fi
done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$REPO/hooks/hooks.json")

# --- Tier 1: stop hook (Stop-timeout regression) ------------------------------------
head_ "Stop hook"

# stop-quality-check.sh once walked the tree and forked `stat` per matched file —
# ~11.7k forks / ~9s in a monorepo, timing out the 10s Stop hook on 207/248 stops.
# The fix prunes heavy dirs and lets `find` do the mtime test with -mmin/-print/-quit.
# Guard the mechanism AND the behaviour so the stat loop cannot return unnoticed.
SQC="$REPO/hooks/stop-quality-check.sh"
sqc_src="$(cat "$SQC")"
if grep -qF -- '-mmin' <<<"$sqc_src" && grep -qF -- '-prune' <<<"$sqc_src" && grep -qF -- '-print -quit' <<<"$sqc_src"; then
  ok "stop hook uses pruned find with -mmin/-print -quit"
else
  bad "stop hook lost its pruned -mmin/-quit find — the O(files) stat loop can reappear"
fi
if grep -qF 'stat -c %Y' <<<"$sqc_src"; then
  bad "stop hook still forks 'stat' per file — the Stop-timeout regression is back"
else
  ok "stop hook no longer forks stat per file"
fi

# Behaviour: a recent edit inside node_modules must NOT fire the reminder (the old,
# unpruned find did); a recent real source edit MUST. Fresh temp dir → no test stamp.
sqc_t="$(mktemp -d)"
mkdir -p "$sqc_t/src" "$sqc_t/node_modules/pkg"
touch "$sqc_t/node_modules/pkg/recent.js"
out_junk="$(printf '{"cwd":"%s"}' "$sqc_t" | bash "$SQC" 2>&1)"
if grep -qi 'tests haven' <<<"$out_junk"; then
  bad "stop hook false-fires on node_modules churn (prune not applied)"
else
  ok "stop hook ignores node_modules churn"
fi
touch "$sqc_t/src/new.py"
out_src="$(printf '{"cwd":"%s"}' "$sqc_t" | bash "$SQC" 2>&1)"
if grep -qi 'tests haven' <<<"$out_src"; then
  ok "stop hook still reminds on a recent source edit"
else
  bad "stop hook no longer detects a recent source edit"
fi
rm -rf "$sqc_t"

# --- Tier 1: destructive-command denials --------------------------------------------
head_ "Destructive-command hook"

# block-destructive-commands.sh is the mechanical form of llm-security.md's "never run
# push --force / reset --hard / branch -D without explicit user request". Guard both
# directions: the denials (or the guidance is prose again) AND the allows (a false
# positive on commit messages or --force-with-lease gets the hook disabled, which is
# worse than never shipping it).
BDC="$REPO/hooks/block-destructive-commands.sh"
bdc_case() { # expected-exit command description
  local exp="$1" cmd="$2" desc="$3" rc=0
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$BDC" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$exp" ]; then ok "$desc"
  else bad "$desc (want exit $exp, got $rc)"; fi
}
bdc_case 2 'git push --force origin main'        "denies git push --force"
bdc_case 2 'git reset --hard HEAD~1'             "denies git reset --hard"
bdc_case 2 'git branch -D feature/x'             "denies git branch -D"
bdc_case 2 'git clean -fdx'                      "denies git clean -f"
bdc_case 2 'rm -rf /'                            "denies rm -rf /"
bdc_case 2 'cd /tmp && rm -rf ~'                 "denies rm -rf ~ behind a compound command"
bdc_case 0 'git push --force-with-lease origin main' "allows --force-with-lease (the safe variant is not its own prefix's victim)"
# The denied token must sit MID-message: at message end the closing quote itself breaks
# the word boundary, and the case passes even with quote-stripping deleted — a guard that
# survived its own mutation test, which is exactly what this suite exists to prevent.
bdc_case 0 'git commit -m "docs: never run git reset --hard in scripts"' "allows a commit message that MENTIONS a denied command (data, not command)"
bdc_case 0 'rm -rf node_modules'                 "allows rm -rf of a named subdirectory"
# The repo's own commit style is a heredoc message; quote-stripping is line-based and
# cannot see across lines, so heredoc bodies must be dropped before analysis. This false
# positive was hit while building the hook — committing the hook tripped the hook.
bdc_hd="$(printf 'git commit -m "$(cat <<%s\nfeat: deny git reset --hard\nEOF\n)"' "'EOF'")"
bdc_case 0 "$bdc_hd" "allows a heredoc commit message mentioning a denied command"

# The hook must also be REGISTERED on the Bash matcher — an unregistered hook exists,
# is executable, passes every case above, and never fires. That is this suite's founding
# failure mode (validates cleanly, never runs).
bdc_reg="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$REPO/hooks/hooks.json")"
if grep -qF 'block-destructive-commands.sh' <<<"$bdc_reg"; then
  ok "destructive-command hook is registered on the Bash matcher"
else
  bad "block-destructive-commands.sh is not registered in hooks.json — it will never fire"
fi

# --- Tier 1: hef.sync prescribes cp, never mv ---------------------------------------
head_ "hef.sync stow safety"

# `mv` onto a stow symlink under ~/.claude/ replaces the symlink with a regular file and
# the dotfiles repo silently stops receiving updates — this bit for real (settings.json).
# hef.sync exists to FIX drift; it must never prescribe the command that causes it.
sync_fenced="$(awk '/^```/{f=!f; next} f' "$REPO/commands/hef.sync.md" || true)"
# `.*` not `[^\n]*` — grep is already line-based, and inside a bracket expression \n is
# LITERAL backslash+n, so [^\n]* cannot cross any filename containing an 'n'. That version
# passed its own mutation test's absence and missed a planted `mv new-rules.md ~/.claude/`.
if grep -qE '(^|[[:space:]])mv[[:space:]].*~/\.claude/' <<<"$sync_fenced"; then
  bad "hef.sync.md prescribes 'mv' into ~/.claude/ — that replaces a stow symlink with a plain file"
else
  ok "hef.sync.md never prescribes mv into ~/.claude/"
fi
if grep -qF 'Never `mv`' "$REPO/commands/hef.sync.md"; then
  ok "hef.sync.md carries the stow-mv trap warning"
else
  bad "hef.sync.md lost the stow-mv trap warning — the next editor will prescribe mv"
fi

# --- Tier 1: the #7 regression guard ------------------------------------------------
head_ "Command → helper wiring"

# A `!` pre-execution block is permission-checked BEFORE ${CLAUDE_PLUGIN_ROOT} is
# substituted, so the checker sees a literal ${...} and rejects the command with
# "Contains expansion". No allowlist entry can match it. This shipped twice (aa32e83,
# then #7). If this assertion ever fails again, do not "fix" it by changing the rule.
if grep -rqF '!`${CLAUDE_PLUGIN_ROOT}' "$REPO/commands/"; then
  bad "a command puts \${CLAUDE_PLUGIN_ROOT} inside a ! block — rejected as 'Contains expansion' (see #7)"
  grep -rlF '!`${CLAUDE_PLUGIN_ROOT}' "$REPO/commands/" | sed 's|^|       |'
else
  ok "no command invokes the helper from a ! block"
fi

# The explanatory notes in those commands must survive substitution. They exist to stop the
# `!` block being reintroduced a third time — but they are prose inside skill content, and
# skill content is substituted. A note that spells the plugin-root variable with a $ and
# braces gets its own warning replaced by a path, and reads as nonsense to the next reader.
notes="$(grep -h '^>' "$REPO"/commands/*.md || true)"
if grep -qF '${CLAUDE_PLUGIN_ROOT}' <<<"$notes"; then
  bad "a note spells out the substitutable plugin-root variable — it will be replaced by a path and the warning will be gibberish"
else
  ok "the anti-regression notes survive substitution"
fi

# Every subcommand a command asks for must actually be implemented. A rename here fails
# at runtime, inside a command, where nobody is watching.
missing=0
while read -r sub; do
  if ! grep -qE "^[[:space:]]*${sub}\)" "$HELPER"; then
    bad "commands call helper subcommand '$sub', which speckit-helper.sh does not implement"
    missing=$((missing + 1))
  fi
done < <(grep -rhoE 'speckit-helper\.sh [a-z-]+' "$REPO/commands/" | awk '{print $2}' | sort -u)
[ "$missing" -eq 0 ] && ok "every helper subcommand used by a command is implemented"

# --- Tier 1: the permission rule the docs prescribe ----------------------------------
head_ "Documented permission rule"

# The permission matcher does NO expansion and NO normalisation. It compares the rule to the
# command string literally. Every shortcut silently fails to match — verified against the
# live matcher:
#
#   Bash(/home/you/...//hooks/speckit-helper.sh:*)   matches
#   Bash($HOME/...)                                  BLOCKED — $HOME is not expanded
#   Bash(~/...)                                      BLOCKED — ~ is not expanded
#
# A rule that does not match means the helper prompts on every call, and a non-interactive
# context denies prompts — so the command degrades or produces nothing. SETUP shipped the
# $HOME form for three releases, so the rule it told every user to add never worked.
# Inspect only what the docs PRESCRIBE — the contents of fenced code blocks. Both files also
# document $HOME and ~ as counter-examples ("❌ blocked"), in prose and tables, and flagging
# those would be a false positive. Only a rule inside a code block is one a user will paste.
# Scan every doc, not just the two that happened to carry the rule when this was written. The
# permission rule and the stow text moved to docs/ when the README was split — a guard pinned to
# README.md would then have passed trivially while docs/install.md shipped the broken rule.
bad_rule=0
for doc in "$REPO"/SETUP.md "$REPO"/README.md "$REPO"/docs/*.md; do
  [ -f "$doc" ] || continue
  fenced="$(awk '/^```/{f=!f; next} f' "$doc" || true)"
  if grep -qE 'Bash\((\$HOME|~)/[^)]*speckit-helper' <<<"$fenced"; then
    bad "$(basename "$doc") prescribes a helper rule using \$HOME or ~ — neither is expanded, so it never matches"
    bad_rule=$((bad_rule + 1))
  fi
done
[ "$bad_rule" -eq 0 ] && ok "no doc prescribes a helper rule that cannot match"

# The stow install is dead (#18) and must not be prescribed again. The payload no longer
# lives under .claude/, and the dotfiles package no longer carries agents/commands/hooks/
# skills — following those instructions yields a half-install with none of them. Only the
# REMOVAL form (`stow -D claude`) is legitimate now.
stow_bad=0
for doc in "$REPO"/README.md "$REPO"/docs/*.md; do
  [ -f "$doc" ] || continue
  fenced="$(awk '/^```/{f=!f; next} f' "$doc" || true)"
  if grep -qE '(^|[^-])\bstow claude\b' <<<"$fenced"; then
    bad "$(basename "$doc") prescribes 'stow claude' as an install — that path is dead and yields a half-install (#18)"
    stow_bad=$((stow_bad + 1))
  fi
done
[ "$stow_bad" -eq 0 ] && ok "no doc prescribes the dead stow install path"

# --- docs stay honest (FR-008) ---------------------------------------------------------
# Two ways a split README rots: a command ships with no entry in the reference, and a link
# points at a doc that was renamed or never written. Both are silent.
undocumented=0
for f in "$REPO"/commands/*.md; do
  name="$(basename "$f" .md)"
  grep -qF "/$name" "$REPO/docs/commands.md" || {
    bad "command /$name is not documented in docs/commands.md"
    undocumented=$((undocumented + 1))
  }
done
[ "$undocumented" -eq 0 ] && ok "every command appears in docs/commands.md"

broken=0
for doc in "$REPO"/README.md "$REPO"/docs/*.md; do
  [ -f "$doc" ] || continue
  dir="$(dirname "$doc")"
  while read -r link; do
    [ -z "$link" ] && continue
    case "$link" in http*|\#*) continue ;; esac
    target="${link%%#*}"
    [ -e "$dir/$target" ] || {
      bad "$(basename "$doc") links to $target, which does not exist"
      broken=$((broken + 1))
    }
  done < <(grep -oE '\]\([^)]+\)' "$doc" | sed 's/^](//; s/)$//' || true)
done
[ "$broken" -eq 0 ] && ok "every relative link in the docs resolves"

# The payload moved out of .claude/ in 5.0 (#9), but the docs went on describing the old layout —
# an architecture diagram and two file paths that had not existed for a release. Splitting the
# README is what exposed them. `~/.claude/...` is legitimate (the user's home, legacy installs);
# a bare `.claude/<payload>/` is this repo's own layout, and it is wrong.
# The lookbehind excludes anything path-prefixed (`~/.claude/agents/`, `/home/you/.claude/...`) —
# those are the USER's home directory and are legitimate. Only a bare, relative
# `.claude/<payload>/` refers to this repo's layout, and that is the thing that is wrong.
stale_paths="$(grep -rnP '(?<![~/])\.claude/(commands|agents|hooks|workflows)/' "$REPO/docs" "$REPO/README.md" 2>/dev/null || true)"
if [ -n "$stale_paths" ]; then
  bad "docs describe the pre-5.0 layout — the payload does not live under .claude/ (#9)"
  sed 's|^|       |' <<<"$stale_paths" | head -3
else
  ok "docs describe the payload where it actually lives"
fi

# --- Tier 1: helper runs ------------------------------------------------------------
head_ "Helper contract"

# A fetcher that prints a sentinel at exit 0 lets a command sail past a missing precondition and
# invent its own answer. `spec` printed the six characters NO_SPEC and exited 0; a command told to
# "load spec.md" loaded that string. It happened during the 5.1.0 run and nothing noticed until a
# human read the output. Constitution principle 5. (#27)
#
# Driven in a scratch repo, because the assertion is about what happens when the artifact is ABSENT
# and this repo has one.
hc_tmp="$(mktemp -d)"
(
  cd "$hc_tmp" || exit 1
  git init -q . 2>/dev/null
  git checkout -q -b feature/nothing-here 2>/dev/null
  mkdir -p .specify/specs/some-other-name
  : > .specify/specs/some-other-name/spec.md
) >/dev/null 2>&1

hc_fail=0
# spec/plan: the directory exists but is named for a DIFFERENT branch — the 5.1.0 case exactly.
# constitution: never scaffolded.
for sub in spec plan constitution; do
  out="$(cd "$hc_tmp" && "$HELPER" "$sub" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "helper '$sub' exits 0 with the artifact absent — a caller cannot tell the answer from the failure (#27)"
    hc_fail=1
  elif [ -n "$out" ]; then
    bad "helper '$sub' printed '$out' to STDOUT while failing — a caller capturing stdout would use it as the answer (#27)"
    hc_fail=1
  fi
done

# list-specs needs its own fixture: in the one above a spec directory DOES exist, so exiting 0 is the
# correct answer. Its failure case is a .specify/ with no feature directories at all.
hc_empty="$(mktemp -d)"; mkdir -p "$hc_empty/.specify/specs"
out="$(cd "$hc_empty" && "$HELPER" list-specs 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] || [ -n "$out" ]; then
  bad "helper 'list-specs' must fail loudly when .specify/specs/ is empty; got '$out' at exit $rc (#27)"
  hc_fail=1
fi
rm -rf "$hc_empty"

[ "$hc_fail" -eq 0 ] && ok "fetchers fail loudly: non-zero exit, nothing on stdout, reason on stderr (#27)"

# The reason must be actionable. Every artifact goes missing at once when the spec directory does not
# match the branch, and that is a fact about the DIRECTORY, not the artifacts — the run that hit this
# lost an hour to it. The message has to say so.
#
# Assert on text unique to the CONTRACT, not merely on the word "branch" — the message says "switch
# to the branch that matches it" elsewhere, so a loose `grep -qi branch` stays green with the whole
# contract sentence deleted. Verified: it did.
hint="$(cd "$hc_tmp" && "$HELPER" spec 2>&1 >/dev/null)"
hint_fail=0
grep -q "some-other-name" <<<"$hint" || { bad "the message must LIST the spec directories that do exist; got: $hint"; hint_fail=1; }
grep -q "MUST be named after the branch" <<<"$hint" || { bad "the message must state the branch↔directory contract, which is the actual cause; got: $hint"; hint_fail=1; }
[ "$hint_fail" -eq 0 ] && ok "a missing artifact names the branch↔directory contract and lists what does exist"

# PREDICATES answer; they do not fail. /speckit.init asks check-specify-dir precisely to learn that
# .specify/ is absent — that is the whole reason init exists, so the string must still be there.
pred_out="$(cd "$hc_tmp" && "$HELPER" check-specify-dir 2>/dev/null)"
if [ "$pred_out" = "EXISTS" ]; then
  ok "check-specify-dir still answers on stdout"
else
  # .specify EXISTS in the scratch repo, so this branch means the predicate lost its string.
  bad "check-specify-dir must print its answer, not just signal it — /speckit.init branches on the string"
fi

rm -rf "$hc_tmp"

head_ "Workflow resilience"

# These guard shape invariants that tests/workflow.test.js CANNOT reach. A behaviour test proves the
# code was right on the paths its fixture walked; only a grep proves no OTHER path bypasses the choke
# point, and only a grep sees prompt text at all (the stub agent never runs a suite).
#
# For the crashed-implementer invariant the guards are the PRIMARY defence, not the backstop: the
# behaviour test's mutation cannot fail on its own, because with the retry wrapper in place no null can
# ever reach the collector. Guards 5 and 6 are what stand between that line and a silent regression.
# That inverts the usual "grep is the backstop, behaviour is the proof" relationship. It is written down
# here because it is exactly the sort of thing a handoff loses.
WF="$REPO/workflows/speckit-workflow.js"

# 1. The node harness loads the shipped file by rewriting `export const meta` -> `const meta`. If that
#    declaration is ever reworded, String.replace matches nothing. The harness asserts this itself, but
#    it only runs where node does; CI gates on THIS suite, so the coupling is guarded in both places.
meta_n="$(grep -cE '^export const meta = \{' "$WF" || true)"
if [ "$meta_n" -eq 1 ]; then
  ok "workflow declares 'export const meta' exactly once — the test harness's rewrite still matches"
else
  bad "workflow has $meta_n 'export const meta' declarations, expected 1 — tests/workflow.test.js rewrites that exact string and would silently test nothing"
fi

# 2. Every spawn must route through agentTyped, which owns the retry and the never-retry-a-null rule.
#    A call that reaches the primitive directly is unretried, and on the sequential path an unretried
#    schema failure kills the whole run.
#
#    Count OCCURRENCES, not lines. `grep -c` counts LINES: two raw calls smuggled onto one line read as
#    1 and the bypass ships. This is not hypothetical — the first draft of the comment above agentTyped
#    put two of them on one line and tripped this guard, which is how we know it works.
#
#    THIS PIPE IS SAFE and must not be "fixed" into capture-then-match. The header's ban is on
#    `producer | grep -q`, where grep exits on first match and SIGPIPEs the producer. `wc -l` reads to
#    EOF and never exits early: no SIGPIPE, no race. Here grep is the PRODUCER, not the matcher.
raw_n="$(grep -oP '(?<![A-Za-z0-9_$.])agent\s*\(' "$WF" | wc -l || true)"
if [ "$raw_n" -eq 1 ]; then
  ok "exactly one unwrapped spawn — every other call routes through agentTyped"
else
  bad "$raw_n unwrapped spawn occurrences, expected exactly 1 (the one inside agentTyped) — the rest bypass the retry choke point"
  sed 's|^|       |' <<<"$(grep -nP '(?<![A-Za-z0-9_$.])agent\s*\(' "$WF" || true)" | head -6
fi

# 5. The [P] batch collector must not filter its parallel() results. parallel() converts a thrown
#    implementer to null; .filter(Boolean) then ERASES the task — it lands in neither accepted nor
#    rejected, the halt cannot see it, and the run returns 1/1: a perfect score for a phase where the
#    task never ran. Measured. The verdict filter elsewhere is a DIFFERENT and legitimate
#    .filter(Boolean) on its own line, so this match is scoped to a filter on the SAME line as the
#    parallel() call — the exact shape of the bug.
drop="$(grep -nE 'parallel\(.*\)[[:space:]]*\)?\.filter\(' "$WF" || true)"
if [ -n "$drop" ]; then
  bad "a parallel() result is filtered inline — a crashed implementer is dropped, not rejected"
  sed 's|^|       |' <<<"$drop"
else
  ok "no parallel() result is filtered inline — a crashed implementer becomes an explicit rejection"
fi

# 6. ...and the mapped-null fallback must EXIST. Guard 5 only forbids the bug's known shape;
#    reformatting the collector across two lines slips past it silently. This one requires the
#    replacement to be present. Neither is sufficient alone.
if grep -qF 'implementer crashed' "$WF"; then
  ok "the batch collector maps a crashed implementer to an explicit rejection"
else
  bad "the batch collector's null-to-rejection fallback is gone — a crashed [P] implementer will vanish again"
fi

# 7. A dead gate must HALT, not fall through. A null gate result — the agent died or exhausted its
#    retries — must be treated as a failure, never passed. Measured before the fix: both gates dead
#    => {"completed":2,"total":2}, zero confirmations. That is the silent drop, one function away.
#
#    #30 made the gate PER-REPO, so the shape moved from `if (!gate || !gate.passed)` to a finder over
#    the per-repo results: `gates.find(x => !x || !x.g || !x.g.passed)`. Widened DELIBERATELY to the new
#    shape, per this guard's own standing instruction — never delete it, re-aim it.
#
#    Ceiling AND floor, and the pair is the invariant:
#      * FLOOR — the finder must test a FALSY gate (`!x || !x.g`) before/while testing `.passed`.
#        Without the null arm a dead gate slips through, which is the whole bug.
#      * CEILING — forbid the shape that requires the gate truthy before checking passed
#        (`x.g && !x.g.passed` / `x && !x.g.passed`), which is `gate &&` spelled for the finder.
gate_finder="$(grep -nE 'gates\.find\(' "$WF" || true)"
if [ -z "$gate_finder" ]; then
  bad "the per-repo gate finder is GONE — grep found no gates.find(...), so the null-gate halt cannot be verified (#30)"
elif ! grep -qE 'gates\.find\(x => !x \|\| !x\.g \|\| !x\.g\.passed\)' "$WF"; then
  bad "the gate finder does not treat a falsy gate as a halt — a dead gate agent would pass the phase"
  sed 's|^|       |' <<<"$gate_finder"
else
  ok "a dead gate halts the phase — the per-repo finder treats null as failure (absence of confirmation is not confirmation)"
fi

# CEILING: the `gate &&`-equivalent — requiring the gate truthy before checking passed, so null slips by.
bad_finder="$(grep -nE 'gates\.find\(x => x(\.g)? &&' "$WF" || true)"
if [ -n "$bad_finder" ]; then
  bad "the gate finder requires a truthy gate before checking .passed — a null (dead) gate would fall through"
  sed 's|^|       |' <<<"$bad_finder"
else
  ok "no truthy-first gate finder — a dead gate cannot slip past the passed check"
fi

head_ "Helper"

if [ -x "$HELPER" ]; then ok "speckit-helper.sh is executable"; else bad "speckit-helper.sh is not executable"; fi

for sub in branch recent-commits; do
  if "$HELPER" "$sub" >/dev/null 2>&1; then ok "helper '$sub' runs"; else bad "helper '$sub' exits non-zero"; fi
done

# `rtk-available` is a PREDICATE, and "does it run" is the wrong question for one — that is exactly
# how the broken contract survived. It used to always exit 0, so quality-tooling.md's documented
# `helper rtk-available && rtk pytest || pytest` took the rtk branch even with rtk absent. The guard
# did not guard. This suite asserted "helper 'rtk-available' runs" and was satisfied.
#
# The right question is whether the ANSWER matches reality — on this machine, and on CI, where rtk is
# not installed and the exit code must therefore be 1.
rtk_out="$("$HELPER" rtk-available 2>/dev/null)"; rtk_rc=$?
if command -v rtk >/dev/null 2>&1; then
  if [ "$rtk_out" = "RTK_AVAILABLE" ] && [ "$rtk_rc" -eq 0 ]; then
    ok "helper rtk-available agrees with reality (present: RTK_AVAILABLE, exit 0)"
  else
    bad "rtk is on PATH but the helper said '$rtk_out' / exit $rtk_rc"
  fi
else
  if [ "$rtk_out" = "RTK_MISSING" ] && [ "$rtk_rc" -ne 0 ]; then
    ok "helper rtk-available agrees with reality (absent: RTK_MISSING, non-zero)"
  else
    bad "rtk is NOT on PATH but the helper said '$rtk_out' / exit $rtk_rc — the documented '&& rtk … || …' pattern would run rtk anyway"
  fi
fi

# ...and prove the documented pattern actually branches, in both directions. This is the check that
# would have caught the original bug: it drives quality-tooling.md's own line rather than the helper.
if PATH=/usr/bin:/bin "$HELPER" rtk-available >/dev/null 2>&1; then
  branch_taken="rtk"
else
  branch_taken="fallback"
fi
if [ "$branch_taken" = "fallback" ]; then
  ok "the documented 'rtk-available && rtk … || …' pattern falls back when rtk is off PATH"
else
  bad "with rtk off PATH the documented pattern still took the rtk branch — rtk-available is not a usable predicate"
fi

# The helper must survive the repos it will actually meet, not just this one. The pr-*
# subcommands used to diff against `main` and fall back to HEAD~1 with nothing after it, so
# a repo whose only commit is its first exited 128 (#16). A non-zero helper inside a command
# yields no data and the command degrades silently — and the model papers over it by running
# plain git instead, so nobody notices.
hostile=0
ROOTREPO="$(mktemp -d)"; NOGIT="$(mktemp -d)"
git -C "$ROOTREPO" init -q -b main
git -C "$ROOTREPO" -c user.email=smoke@test -c user.name=smoke commit -q --allow-empty -m "root commit"
for sub in pr-commits pr-files pr-stats; do
  (cd "$ROOTREPO" && "$HELPER" "$sub") >/dev/null 2>&1 || { bad "helper '$sub' exits non-zero in a root-commit repo (#16)"; hostile=$((hostile + 1)); }
  (cd "$NOGIT"    && "$HELPER" "$sub") >/dev/null 2>&1 || { bad "helper '$sub' exits non-zero outside a git repo"; hostile=$((hostile + 1)); }
done
rm -rf "$ROOTREPO" "$NOGIT"
[ "$hostile" -eq 0 ] && ok "pr-* subcommands survive a root-commit repo and a non-git directory"

# --- Tier 2: live install ------------------------------------------------------------
#
# Two things you must not do here, both of which produce a green test against a broken plugin:
#
# 1. Do NOT assert on `claude -p "/project-context"`. A plugin's SLASH commands do not exist
#    in headless mode — `/project-context` returns "Unknown command", and before the rename
#    a bare `/context` silently resolved to Claude Code's BUILT-IN /context (a token-usage
#    readout that has nothing to do with this plugin). Asserting on that passes always.
#    Plugin commands ARE reachable headlessly as SKILLS. That is what tier 3 below drives.
#
# 2. Do NOT assert that the helper's DATA appears in the output. When the helper is blocked,
#    the model cheerfully falls back to plain `git log` / `git branch` and produces the same
#    data by hand. An assertion on the data goes green while every helper call is being
#    denied — this exact false positive happened while writing tier 3. Assert on the TOOL
#    CALLS instead: the helper was invoked, and was not denied.
if [ "${SMOKE_LIVE:-0}" = "1" ]; then
  head_ "Live install (isolated config)"

  CFG="$(mktemp -d)"
  trap 'rm -rf "$CFG"' EXIT
  export CLAUDE_CONFIG_DIR="$CFG"   # never touch the user's real ~/.claude

  claude plugin marketplace add "$REPO" >/dev/null 2>&1
  claude plugin install hefesto@hefesto >/dev/null 2>&1

  installed="$(claude plugin list 2>/dev/null || true)"
  if grep -q 'hefesto' <<<"$installed"; then
    ok "plugin installs into a clean config and reports enabled"
  else
    bad "plugin did not install"
  fi

  # A directory-sourced plugin loads in place, so its root is the clone — WITH a trailing
  # slash, which is what produces the `//` below. This is not cosmetic: it decides whether
  # the permission rule matches.
  ROOT="$REPO/"

  # Every helper invocation the commands hand to the model, substituted and executed.
  # Catches a wrong path (the bug aa32e83 was trying to fix) and a renamed subcommand —
  # both invisible until a user runs the command.
  #
  # Run them in a scratch repo, NOT in $REPO. Some subcommands mutate state:
  # `plan-phase-start` writes .specify/.plan-in-progress, which arms the plan-phase
  # write-block hook and locks up the working tree of whatever repo it runs in.
  # A realistic repo: a `main` branch and more than one commit. The pr-* subcommands diff
  # against main and fall back to HEAD~1, so a single-commit repo makes them exit 128 —
  # an artefact of the fixture, not a defect in the plugin.
  SCRATCH="$(mktemp -d)"
  git -C "$SCRATCH" init -q -b main
  git -C "$SCRATCH" -c user.email=smoke@test -c user.name=smoke commit -q --allow-empty -m "base"
  git -C "$SCRATCH" -c user.email=smoke@test -c user.name=smoke commit -q --allow-empty -m "smoke"

  broken=0
  while read -r invocation; do
    real="${invocation//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
    err="$( (cd "$SCRATCH" && eval "$real") 2>&1 >/dev/null )"
    code=$?
    # A non-zero exit is NOT itself a defect. The helper is REQUIRED to exit non-zero and name
    # the missing artifact when one is absent - the fetcher contract above asserts exactly that -
    # and this scratch repo deliberately has no .specify/, so ~8 subcommands correctly report a
    # miss. Scoring those as failures is what made this tier read 13-red for months (#56) and
    # buried the real bug underneath the noise. Only two outcomes mean the INVOCATION is broken:
    #   126/127          - script missing or not executable (the aa32e83 bug shape)
    #   Unknown command: - the subcommand was renamed or deleted out from under the doc
    if [ "$code" -eq 127 ] || [ "$code" -eq 126 ] || grep -qF 'Unknown command:' <<<"$err"; then
      bad "command invocation fails as the model would run it: $real"
      broken=$((broken + 1))
    fi
  done < <({
    # Capture the WHOLE fenced span, not just the tail from ${CLAUDE_PLUGIN_ROOT} onward. Anchoring
    # at the variable silently dropped any command PREFIX: `git -C "${CLAUDE_PLUGIN_ROOT}" status`
    # extracted as `${CLAUDE_PLUGIN_ROOT}" status`, losing `git -C "` and keeping the stray quote,
    # so eval tried to execute the plugin path itself. Those five hef.sync invocations could only
    # ever fail, which means they were never actually validated - the precise blind spot the note
    # below says this test exists to close (#56).
    grep -rhoE '`[^`]*\$\{CLAUDE_PLUGIN_ROOT\}[^`]*`' "$REPO/commands/" | sed 's/^`//; s/`$//'
    # Fenced code blocks carry the invocation bare, with no inline backticks on the line.
    grep -rh '\${CLAUDE_PLUGIN_ROOT}' "$REPO/commands/" | grep -v '`' | sed -E 's/^[[:space:]]+//'
  } | grep -vE '<[a-z-]+>' | sort -u)
  # `<placeholder>` invocations are documentation templates, not runnable commands.
  # NB: match ANY ${CLAUDE_PLUGIN_ROOT} invocation, not just speckit-helper.sh. Hardcoding
  # the script name here creates the exact blind spot this test exists to close: a command
  # pointing at a script that does not exist would never be matched, so never executed, so
  # never fail. That is the shape of the aa32e83 bug.
  rm -rf "$SCRATCH"
  [ "$broken" -eq 0 ] && ok "every helper invocation in every command runs as the model would run it"

  # The allowlist rule SETUP.md prescribes must match the string the model actually sends.
  # Compare shape, not the clone path — SETUP documents a default location, but a user may
  # clone anywhere. What must agree is the part after the plugin root: the model sends a
  # DOUBLED slash (because ${CLAUDE_PLUGIN_ROOT} ends in one) and the permission matcher
  # compares literally without normalising it. A single-slash rule silently fails to match,
  # so every helper call prompts — and a non-interactive context denies prompts, which
  # aborts the command with no output at all.
  if grep -qF '//hooks/speckit-helper.sh' "$REPO/SETUP.md"; then
    ok "SETUP prescribes the doubled-slash rule that the commands actually produce"
  else
    bad "SETUP's permission rule lacks the doubled slash, so it will never match"
    printf '       commands send: <plugin-root>//hooks/speckit-helper.sh\n'
  fi

  # --- Tier 3: end to end, through a real model session -------------------------------
  #
  # Drive the command the way a user does and assert the helper actually ran. This is the
  # only check that exercises the whole chain at once: skill loads -> ${CLAUDE_PLUGIN_ROOT}
  # substitutes -> model runs the helper with Bash -> the PERMISSION RULE MATCHES -> output
  # comes back. Every bug in 4.5.0 lived somewhere on that chain.
  #
  # Needs an authenticated `claude` and spends tokens, so it cannot run in CI. It is worth
  # it: it is the only check that would have caught the $HOME permission rule, which three
  # releases of SETUP told every user to add and which never matched anything.
  #
  # The plugin is loaded from the working tree with --plugin-dir, so this tests THIS
  # checkout, not whatever is installed.
  head_ "End to end (real session, spends tokens)"

  # Tier 2 pointed CLAUDE_CONFIG_DIR at a throwaway config. That config has no credentials,
  # so leaving it set here makes every model call fail with "Not logged in" — and the check
  # would skip itself forever while looking like it had run. Restore the real config.
  unset CLAUDE_CONFIG_DIR

  probe="$(claude -p "reply with exactly: ok" 2>&1 || true)"
  if grep -qi 'not logged in' <<<"$probe"; then
    printf '  \033[33mskip\033[0m not logged in — `claude /login` to run the end-to-end check\n'
  else
    E2E="$(mktemp -d)"
    git -C "$E2E" init -q -b main
    printf '{"name":"scratch","version":"1.0.0"}' > "$E2E/package.json"
    git -C "$E2E" add -A
    git -C "$E2E" -c user.email=smoke@test -c user.name=smoke commit -q -m "SMOKE_MARKER_COMMIT"

    # Both slash forms. The trailing slash on ${CLAUDE_PLUGIN_ROOT} is NOT stable: a
    # marketplace/directory install yields `//`, --plugin-dir yields a single `/`. Neither
    # entry is redundant.
    rules="$(jq -n --arg a "Bash($REPO//hooks/speckit-helper.sh:*)" \
                   --arg b "Bash($REPO/hooks/speckit-helper.sh:*)" \
                   '{permissions:{allow:[$a,$b],deny:[]}}')"

    run="$(cd "$E2E" && timeout 300 claude -p \
        "Invoke the skill hefesto:hef.context and follow its instructions." \
        --plugin-dir "$REPO" --settings "$rules" --output-format json 2>&1 || true)"
    rm -rf "$E2E"

    called="$(jq -r '.. | objects | select(.name=="Bash") | .input.command' <<<"$run" 2>/dev/null \
              | grep -c 'speckit-helper' || true)"

    if [ "${called:-0}" -eq 0 ]; then
      bad "the command never made the model run the helper at all"
    elif grep -qF 'requires approval' <<<"$run"; then
      bad "the helper was DENIED by the permission checker — the rule in SETUP does not match what the command sends"
      jq -r '.. | objects | select(.name=="Bash") | .input.command' <<<"$run" 2>/dev/null \
        | grep 'speckit-helper' | head -1 | sed 's|^|       sent: |'
    else
      ok "end to end: the skill ran the helper and the permission rule matched ($called calls)"
    fi
  fi
else
  head_ "Live install"
  printf '  \033[33mskip\033[0m SMOKE_LIVE=1 to install the plugin into a throwaway config and exercise it\n'
fi

# --- Tier 1: implement-phase test guard (FR-003) ---------------------------------------
head_ "Implement-phase test guard"

# Tests may grow during /speckit.implement, never shrink. Both directions are guarded, like the
# destructive-command hook: the denials (or the rule is prose again) AND the allows (a guard that
# blocks adding a test gets disarmed, which is worse than never shipping it).
#
# Mutation-checked 2026-09-22, each mutation applied, run, restored:
#   * `-lt` → `-le` on the assertion compare → "equal assertion count (a rename)" went red.
#   * `-u|` dropped from the snapshot regex → "denies jest -u" went red.
#   * the Edit arm's marker test replaced with `true` → "assertion-removing edit when no phase is
#     active" went red. The FIRST attempt mutated the Bash arm's marker test instead and nothing
#     went red — which is how the "rm … when no phase is active" case below came to exist.
IPG="$REPO/hooks/implement-phase-test-guard.sh"
ipg_t="$(mktemp -d)"; mkdir -p "$ipg_t/.specify" "$ipg_t/tests"; : > "$ipg_t/tests/test_a.py"
ipg_case() { # expected-exit description json
  local exp="$1" desc="$2" json="$3" rc=0
  printf '%s' "$json" | bash "$IPG" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$exp" ]; then ok "$desc"; else bad "$desc (want exit $exp, got $rc)"; fi
}
ipg_edit() { jq -nc --arg c "$ipg_t" --arg f "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:($c+"/"+$f),old_string:$o,new_string:$n}}'; }
ipg_bash() { jq -nc --arg c "$ipg_t" --arg k "$1" '{tool_name:"Bash",cwd:$c,tool_input:{command:$k}}'; }
# Unconditional: snapshot regeneration.
ipg_case 2 "denies jest -u (snapshot regeneration) with no phase active"      "$(ipg_bash 'npx jest -u')"
ipg_case 2 "denies pytest --snapshot-update"                                  "$(ipg_bash 'pytest --snapshot-update')"
ipg_case 0 "allows the visible bypass CLAUDE_ALLOW_SNAPSHOT_UPDATE=1"         "$(ipg_bash 'CLAUDE_ALLOW_SNAPSHOT_UPDATE=1 npx jest -u')"
ipg_case 0 "allows git add -u (not a snapshot flag)"                          "$(ipg_bash 'git add -u && git commit -m x')"
# Phase-gated: nothing without the marker…
ipg_case 0 "allows an assertion-removing edit when no implement phase is active" "$(ipg_edit tests/test_a.py $'assert a\nassert b' 'assert a')"
ipg_case 0 "allows rm of a test file when no implement phase is active"          "$(ipg_bash 'rm tests/test_a.py')"
touch "$ipg_t/.specify/.implement-in-progress"
# …and the rule with it.
ipg_case 2 "denies an edit that removes assertions from a test file"          "$(ipg_edit tests/test_a.py $'assert a\nassert b' 'assert a')"
ipg_case 0 "allows an edit that adds assertions"                              "$(ipg_edit tests/test_a.py 'assert a' $'assert a\nassert b')"
ipg_case 0 "allows an edit with equal assertion count (a rename)"             "$(ipg_edit tests/test_a.py 'expect(x).toBe(1)' 'expect(y).toBe(1)')"
ipg_case 0 "allows an assertion-removing edit to a NON-test file"             "$(ipg_edit src/app.py $'assert a\nassert b' 'x')"
ipg_case 0 "allows an edit to a spec under .specify/ named *spec.md"          "$(ipg_edit .specify/specs/x/spec.md $'assert a\nassert b' 'x')"
ipg_case 2 "denies Write over an existing test file"                          "$(jq -nc --arg c "$ipg_t" '{tool_name:"Write",cwd:$c,tool_input:{file_path:($c+"/tests/test_a.py"),content:"pass"}}')"
ipg_case 0 "allows Write of a NEW test file"                                  "$(jq -nc --arg c "$ipg_t" '{tool_name:"Write",cwd:$c,tool_input:{file_path:($c+"/tests/test_new.py"),content:"assert 1"}}')"
ipg_case 2 "denies rm of a test file"                                         "$(ipg_bash 'rm tests/test_a.py')"
ipg_case 0 "allows rm of a non-test file"                                     "$(ipg_bash 'rm build/out.txt')"
rm -rf "$ipg_t"
# Registered on BOTH matchers, or it exists and never fires (this suite's founding failure mode).
ipg_reg_bash="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$REPO/hooks/hooks.json")"
ipg_reg_edit="$(jq -r '.hooks.PreToolUse[] | select(.matcher | test("Edit")) | .hooks[].command' "$REPO/hooks/hooks.json")"
if grep -qF 'implement-phase-test-guard.sh' <<<"$ipg_reg_bash" && grep -qF 'implement-phase-test-guard.sh' <<<"$ipg_reg_edit"; then
  ok "test guard is registered on both the Bash and the Edit|Write matchers"
else
  bad "implement-phase-test-guard.sh is not registered on both matchers — one side of the rule never fires"
fi
# …and /speckit.implement must arm and disarm it, or the marker is never set and the guard is dead code.
impl_src="$(cat "$REPO/commands/speckit.implement.md")"
if grep -qF 'implement-phase-start' <<<"$impl_src" && grep -qF 'implement-phase-end' <<<"$impl_src"; then
  ok "/speckit.implement arms the test guard in pre-flight and disarms it at completion"
else
  bad "/speckit.implement does not set/clear .specify/.implement-in-progress — the guard would never activate"
fi

# --- Tier 1: requirement traceability (FR-001) ------------------------------------------
head_ "Requirement traceability"

# req-coverage is a PREDICATE: the matrix on stdout, the verdict in the exit code. Driven in a
# fixture because the three outcomes (covered / uncovered / unknown) must each be provoked.
#
# Mutation-checked 2026-09-22, each mutation applied, run, restored:
#   * the UNKNOWN branch disabled (`if false`) → the combined case went red.
#   * `[ "$uncovered" -eq 0 ] &&` deleted from the verdict → NOTHING went red on the first attempt:
#     the combined fixture's UNKNOWN id kept the exit non-zero on its own. The uncovered-ONLY case
#     below exists because of that; with it, the same mutation goes red.
rc_t="$(mktemp -d)"
(
  cd "$rc_t" && git init -q . && git checkout -q -b feature/demo
  mkdir -p .specify/specs/demo tests
  printf '| FR-001 | a |\n| FR-002 | b |\n' > .specify/specs/demo/spec.md
  printf '# FR-001\n# FR-009\n' > tests/test_x.sh
) >/dev/null 2>&1
rc_out="$(cd "$rc_t" && "$HELPER" req-coverage 2>/dev/null)"; rc_rc=$?
if [ "$rc_rc" -ne 0 ] && grep -qE '^FR-002 +UNCOVERED' <<<"$rc_out" && grep -qE '^FR-009 +UNKNOWN' <<<"$rc_out"; then
  ok "req-coverage reports an UNCOVERED requirement and an UNKNOWN id, and fails"
else
  bad "req-coverage did not flag FR-002 UNCOVERED + FR-009 UNKNOWN with a non-zero exit (rc=$rc_rc)"
fi
# Uncovered ONLY — no unknown id to carry the exit code. The verdict must fail on this alone.
printf '# FR-001\n' > "$rc_t/tests/test_x.sh"
rc_out="$(cd "$rc_t" && "$HELPER" req-coverage 2>/dev/null)"; rc_rc=$?
if [ "$rc_rc" -ne 0 ] && grep -qE '^FR-002 +UNCOVERED' <<<"$rc_out" && ! grep -qE 'UNKNOWN' <<<"$rc_out"; then
  ok "req-coverage fails on an uncovered requirement alone (no unknown id in play)"
else
  bad "req-coverage must fail on an UNCOVERED requirement by itself (rc=$rc_rc): $rc_out"
fi
printf '# FR-001\n# FR-002\n' > "$rc_t/tests/test_x.sh"
rc_out="$(cd "$rc_t" && "$HELPER" req-coverage 2>/dev/null)"; rc_rc=$?
if [ "$rc_rc" -eq 0 ] && grep -qE '^FR-002 +COVERED +\./tests/test_x\.sh:2' <<<"$rc_out"; then
  ok "req-coverage passes when every FR is cited, and names file:line"
else
  bad "req-coverage should pass with every FR cited and print file:line (rc=$rc_rc): $rc_out"
fi
rc_out="$(cd "$rc_t" && git checkout -q -b feature/nospec && "$HELPER" req-coverage 2>/dev/null)"; rc_rc=$?
if [ "$rc_rc" -ne 0 ] && [ -z "$rc_out" ]; then
  ok "req-coverage with no spec fails loudly: non-zero, nothing on stdout (#27 contract)"
else
  bad "req-coverage printed '$rc_out' at exit $rc_rc with the spec absent"
fi
rm -rf "$rc_t"
# Dogfood (SC-002): when THIS repo is on a branch that has a spec, the suite's own checks must cite
# the FRs they cover — the block headers carry `(FR-NNN)` for that reason. Strictness follows
# tasks.md: an FR whose tasks are all still `[ ]` is PENDING (reported, not failing); an FR with a
# `[x]` task must be cited, and an UNKNOWN id always fails. Skipped on main, where no spec exists.
own_branch="$(git -C "$REPO" branch --show-current 2>/dev/null | sed 's|^feature/||')"
own_spec="$REPO/.specify/specs/$own_branch"
if [ -f "$own_spec/spec.md" ]; then
  own_out="$(cd "$REPO" && "$HELPER" req-coverage 2>/dev/null || true)"
  done_frs="$(grep -E '^\s*- \[x\]' "$own_spec/tasks.md" 2>/dev/null | grep -oE 'FR-[0-9]+' | sort -u || true)"
  own_bad=0
  while read -r fr; do
    [ -z "$fr" ] && continue
    if grep -qE "^$fr +UNCOVERED" <<<"$own_out"; then
      bad "$fr has a task marked done but no test in this suite cites it (SC-002)"; own_bad=1
    fi
  done <<<"$done_frs"
  if grep -qE '^FR-[0-9]+ +UNKNOWN' <<<"$own_out"; then bad "the suite cites an FR the spec does not declare"; own_bad=1; fi
  pending="$(grep -cE '^FR-[0-9]+ +UNCOVERED' <<<"$own_out" || true)"
  [ "$own_bad" -eq 0 ] && ok "every completed requirement on this branch is cited by a check ($pending pending, not yet implemented)"
fi
# The command exists and calls the helper it is built on.
if grep -qF 'speckit-helper.sh req-coverage' "$REPO/commands/speckit.verify.md" 2>/dev/null; then
  ok "/speckit.verify runs req-coverage in pre-flight"
else
  bad "/speckit.verify does not call req-coverage — the mechanical half of the gate is missing"
fi

# --- Tier 1: session lifecycle + config audit hooks (FR-006, FR-007) --------------------
head_ "Lifecycle hooks"

# SessionStart stdout IS context. It must say something useful in a repo and nothing outside one.
# PreCompact must leave a checkpoint the next session can find, outside the working tree.
# Mutation-checked 2026-09-22: session-start's git-repo test replaced with `true` → "silent outside
# a git repo" went red. Restored.
lc_t="$(mktemp -d)"; lc_cache="$(mktemp -d)"
(
  cd "$lc_t" && git init -q . && git checkout -q -b feature/demo
  git -c user.email=s@t -c user.name=s commit -q --allow-empty -m init
  mkdir -p .specify/specs/demo && printf -- '- [ ] T001 open\n- [x] T002 done\n' > .specify/specs/demo/tasks.md
) >/dev/null 2>&1
ss_out="$(printf '{"cwd":"%s","source":"startup"}' "$lc_t" | bash "$REPO/hooks/session-start-context.sh" 2>/dev/null)"
if grep -qF 'branch feature/demo' <<<"$ss_out" && grep -qF 'T001 open' <<<"$ss_out"; then
  ok "session-start hook injects the branch and the open tasks"
else
  bad "session-start hook output lacks branch/open-task lines: $ss_out"
fi
lc_n="$(mktemp -d)"
ss_none="$(printf '{"cwd":"%s"}' "$lc_n" | bash "$REPO/hooks/session-start-context.sh" 2>/dev/null)"
if [ -z "$ss_none" ]; then ok "session-start hook is silent outside a git repo (costs no context)"
else bad "session-start hook printed outside a git repo: $ss_none"; fi
rm -rf "$lc_n"
XDG_CACHE_HOME="$lc_cache" bash "$REPO/hooks/precompact-progress.sh" <<<"$(printf '{"cwd":"%s","trigger":"auto"}' "$lc_t")" >/dev/null 2>&1
ck="$(ls "$lc_cache"/hefesto/progress/*.md 2>/dev/null | head -1)"
if [ -n "$ck" ] && grep -qF 'T001 open' "$ck" && [ -z "$(git -C "$lc_t" status --short | grep -v '.specify')" ]; then
  ok "precompact hook writes a checkpoint with the open tasks, outside the working tree"
else
  bad "precompact hook did not write a usable checkpoint outside the repo"
fi
rm -rf "$lc_t" "$lc_cache"
ac_out="$(printf '{"file_path":"/x/settings.json"}' | bash "$REPO/hooks/audit-config-change.sh" 2>&1 >/dev/null)"
if grep -qF '/x/settings.json' <<<"$ac_out"; then ok "config-audit hook names the changed file"
else bad "config-audit hook did not name the changed file: $ac_out"; fi
for h in session-start-context precompact-progress audit-config-change implement-phase-test-guard; do
  if printf '{}' | bash "$REPO/hooks/$h.sh" >/dev/null 2>&1; then ok "$h survives empty input"
  else bad "$h crashes on empty input — a hook that dies on a malformed event breaks the tool call"; fi
done
for ev in SessionStart PreCompact ConfigChange; do
  if jq -e --arg e "$ev" '.hooks[$e] | length > 0' "$REPO/hooks/hooks.json" >/dev/null 2>&1; then
    ok "a hook is registered on $ev"
  else
    bad "no hook registered on $ev — the script exists and never fires"
  fi
done

# --- Tier 1: the review agents have commands (FR-002) ------------------------------------
head_ "Command → agent wiring"

# code-reviewer and review-coordinator existed for four releases with no command that dispatched
# them; the documented chain had no entry point for its first link. A command that names the wrong
# agent, or none, is the same bug back.
cw_fail=0
grep -qF 'code-reviewer' "$REPO/commands/hef.review.md" 2>/dev/null || { bad "/hef.review does not dispatch code-reviewer"; cw_fail=1; }
grep -qF 'review-coordinator' "$REPO/commands/hef.pr.md" 2>/dev/null || { bad "/hef.pr does not dispatch review-coordinator"; cw_fail=1; }
grep -qiE 'not merge|never merge' "$REPO/commands/hef.pr.md" 2>/dev/null || { bad "/hef.pr must state that it never merges"; cw_fail=1; }
grep -qF 'code-reviewer' "$REPO/commands/speckit.verify.md" 2>/dev/null || { bad "/speckit.verify does not run code-reviewer stage 1"; cw_fail=1; }
[ "$cw_fail" -eq 0 ] && ok "hef.review → code-reviewer, hef.pr → review-coordinator (no merge), speckit.verify → code-reviewer stage 1 (FR-002)"

# --- Tier 1: prose that must exist because a hook points at it (FR-004, FR-005, FR-007) ---
head_ "Guidance wiring"

# Each of these is a rule a hook or command cites by name. If the prose goes, the reference dangles.
gw_fail=0
grep -qF 'jscpd' "$REPO/agents/quality-guardian.md" || { bad "quality-guardian lost the duplication-baseline recipe (FR-004)"; gw_fail=1; }
grep -qiF 'mock budget' "$REPO/agents/test-specialist.md" || { bad "test-specialist lost the mock budget (FR-005)"; gw_fail=1; }
grep -qF 'Agentic' "$REPO/.claude/rules/llm-security.md" || { bad "llm-security.md no longer covers the Agentic Top 10 (FR-007)"; gw_fail=1; }
for c in hef.pr hef.pr-summary speckit.fix; do
  grep -qF '## Untrusted input' "$REPO/commands/$c.md" || { bad "/$c lost its untrusted-input section (FR-007)"; gw_fail=1; }
done
grep -qF 'Skills, Plugins, and Agents Are a Supply Chain' "$REPO/skills/mcp-security/SKILL.md" || { bad "mcp-security lost the skill vetting checklist (FR-007)"; gw_fail=1; }
grep -qF '/sandbox' "$REPO/docs/install.md" || { bad "install.md no longer tells users to enable the sandbox (FR-007)"; gw_fail=1; }
[ "$gw_fail" -eq 0 ] && ok "every hook-cited rule and section is present (FR-004, FR-005, FR-007)"

# --- Result --------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
