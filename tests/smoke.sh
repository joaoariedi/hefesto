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
  if [ -d "$REPO/.claude/$d" ]; then   # -d, not -e: under the OS sandbox these paths are /dev/null masks
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
# (hef.quality, hef.plan). No built-in slash command contains a dot, so a collision is
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

# --- Tier 1: hef.doctor prescribes cp, never mv ---------------------------------------
head_ "hef.doctor stow safety"

# `mv` onto a stow symlink under ~/.claude/ replaces the symlink with a regular file and
# the dotfiles repo silently stops receiving updates — this bit for real (settings.json).
# hef.doctor (né hef.sync, 7.0) exists to FIX drift; it must never prescribe the command that
# causes it.
sync_fenced="$(awk '/^```/{f=!f; next} f' "$REPO/commands/hef.doctor.md" || true)"
# `.*` not `[^\n]*` — grep is already line-based, and inside a bracket expression \n is
# LITERAL backslash+n, so [^\n]* cannot cross any filename containing an 'n'. That version
# passed its own mutation test's absence and missed a planted `mv new-rules.md ~/.claude/`.
if grep -qE '(^|[[:space:]])mv[[:space:]].*~/\.claude/' <<<"$sync_fenced"; then
  bad "hef.doctor.md prescribes 'mv' into ~/.claude/ — that replaces a stow symlink with a plain file"
else
  ok "hef.doctor.md never prescribes mv into ~/.claude/"
fi
if grep -qF 'Never `mv`' "$REPO/commands/hef.doctor.md"; then
  ok "hef.doctor.md carries the stow-mv trap warning"
else
  bad "hef.doctor.md lost the stow-mv trap warning — the next editor will prescribe mv"
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

# PREDICATES answer; they do not fail. /hef.init asks check-specify-dir precisely to learn that
# .specify/ is absent — that is the whole reason init exists, so the string must still be there.
pred_out="$(cd "$hc_tmp" && "$HELPER" check-specify-dir 2>/dev/null)"
if [ "$pred_out" = "EXISTS" ]; then
  ok "check-specify-dir still answers on stdout"
else
  # .specify EXISTS in the scratch repo, so this branch means the predicate lost its string.
  bad "check-specify-dir must print its answer, not just signal it — /hef.init branches on the string"
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
WF="$REPO/workflows/workflow.js"

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

# Tests may grow during /hef.implement, never shrink. Both directions are guarded, like the
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
# …and /hef.implement must arm and disarm it, or the marker is never set and the guard is dead code.
impl_src="$(cat "$REPO/commands/hef.implement.md")"
if grep -qF 'implement-phase-start' <<<"$impl_src" && grep -qF 'implement-phase-end' <<<"$impl_src"; then
  ok "/hef.implement arms the test guard in pre-flight and disarms it at completion"
else
  bad "/hef.implement does not set/clear .specify/.implement-in-progress — the guard would never activate"
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
if grep -qF 'speckit-helper.sh req-coverage' "$REPO/commands/hef.verify.md" 2>/dev/null; then
  ok "/hef.verify runs req-coverage in pre-flight"
else
  bad "/hef.verify does not call req-coverage — the mechanical half of the gate is missing"
fi

# --- Tier 1: session lifecycle + config audit hooks (FR-006, FR-007) --------------------
head_ "Verify gate — runner invocation"

# The gate's argv IS the check: assert what the runner was invoked with, never what it printed
# (a model can reproduce output by hand; it cannot fake the hook's own exec). A fake `npm` on PATH
# records its arguments and exits 0.
# Measured 2026-09-09 (fablab-unesp): `-- --passWithNoTests` appended unconditionally to a pnpm
# workspace's `pnpm -r test` reached every package's vitest twice and exited 1 — the gate then blocked
# EVERY completion on a green tree. Mutation-checked: the case statement replaced with the
# unconditional append → the workspace check goes red.
vg_bin="$(mktemp -d)"; vg_log="$vg_bin/argv"
printf '#!/bin/bash\n[ "$1" = "--version" ] && { echo 10.0.0; exit 0; }\nprintf "%%s\\n" "$@" > "%s"\nexit 0\n' "$vg_log" > "$vg_bin/npm"
chmod +x "$vg_bin/npm"
vg_run() { # $1 = package.json test script; prints the recorded argv
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q . && printf '{"scripts":{"test":"%s"}}\n' "$1" > package.json && echo 'x' > a.js ) >/dev/null 2>&1
  rm -f "${TMPDIR:-/tmp}/.claude-verify-$(printf '%s' "$d" | md5sum | cut -d' ' -f1)"
  : > "$vg_log"
  printf '{"cwd":"%s"}' "$d" | PATH="$vg_bin:$PATH" bash "$REPO/hooks/verify-before-task-complete.sh" >/dev/null 2>&1
  cat "$vg_log"; rm -rf "$d"
}
vg_ws="$(vg_run 'pnpm -r --no-bail test')"
if grep -qF 'test' <<<"$vg_ws" && ! grep -qF -- '--passWithNoTests' <<<"$vg_ws"; then
  ok "verify gate does not append --passWithNoTests to a workspace test script"
else
  bad "verify gate argv for a pnpm workspace: $(tr '\n' ' ' <<<"$vg_ws")"
fi
vg_direct="$(vg_run 'vitest run')"
if grep -qF -- '--passWithNoTests' <<<"$vg_direct"; then
  ok "verify gate still appends --passWithNoTests to a direct vitest script"
else
  bad "verify gate argv for a direct vitest script: $(tr '\n' ' ' <<<"$vg_direct")"
fi
vg_preset="$(vg_run 'jest --passWithNoTests')"
if [ "$(grep -c -- '--passWithNoTests' <<<"$vg_preset")" = "0" ]; then
  ok "verify gate does not repeat --passWithNoTests when the script already sets it"
else
  bad "verify gate repeated the flag: $(tr '\n' ' ' <<<"$vg_preset")"
fi
rm -rf "$vg_bin"

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
# Eval 2026-09-23 (spec-first-routing, both arms 0/1): with only the plugin installed, nothing told
# the model which command a feature-sized request goes to. The routing lines are that channel.
if grep -qF '/hef.spec' <<<"$ss_out" && grep -qF 'root-cause' <<<"$ss_out"; then
  ok "session-start hook states the routing rule (spec first) and the iron law (root cause first)"
else
  bad "session-start hook does not state the routing rules: $ss_out"
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

# --- Tier 2: conventional commit messages (FR-013) ---------------------------------------
head_ "Conventional commits"

# git-workflow.md prescribes the format; release.sh groups the changelog by it. Checked at commit
# time, in the pre-commit hook, on the inline message only. Both directions: every documented
# type passes, the heredoc style this repo uses passes, and a bare message is blocked.
#
# Mutation-checked 2026-09-22: `docs|` dropped from CONVENTIONAL_RE → the docs case went red;
# the heredoc subject line changed from `2p` to `3p` → survived the first two heredoc cases (line 3
# was empty or `EOF` in both), so the "body line looks conventional" case below was added; with it
# the mutation goes red. Restored.
QBC="$REPO/hooks/quality-before-commit.sh"
cc_t="$(mktemp -d)"; git -C "$cc_t" init -q .
cc_case() { # expected-exit description command
  local exp="$1" desc="$2" cmd="$3" rc=0
  jq -nc --arg c "$cmd" --arg d "$cc_t" '{tool_input:{command:$c},cwd:$d}' | bash "$QBC" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$exp" ]; then ok "$desc"; else bad "$desc (want exit $exp, got $rc)"; fi
}
cc_case 0 "allows 'feat: …'"                                   'git commit -m "feat: add thing"'
cc_case 0 "allows 'docs: …' in single quotes"                  "git commit -m 'docs: note'"
cc_case 0 "allows a scoped breaking 'fix(hooks)!: …'"          'git commit -m "fix(hooks)!: tighten"'
cc_case 0 "allows the repo's heredoc commit style"             "$(printf 'git commit -q -m "$(cat <<%s\nfeat: thing\n\nbody\nEOF\n)"' "'EOF'")"
cc_case 2 "blocks a bare message"                              'git commit -m "added thing"'
cc_case 2 "blocks a bare heredoc subject"                      "$(printf 'git commit -m "$(cat <<%s\nMerged some stuff\nEOF\n)"' "'EOF'")"
# The SUBJECT is line 2 of the command (the line after the heredoc opener), never a body line. A
# check that read the wrong line would pass a bare subject whose body happens to look conventional.
cc_case 2 "blocks a bare heredoc subject even when a body line looks conventional" "$(printf 'git commit -m "$(cat <<%s\nMerged stuff\ndocs: this is body text\nEOF\n)"' "'EOF'")"
cc_case 0 "allows the visible bypass CLAUDE_ALLOW_NONCONVENTIONAL=1" 'CLAUDE_ALLOW_NONCONVENTIONAL=1 git commit -m "wip"'
cc_case 0 "leaves --amend --no-edit alone (no inline subject)" 'git commit --amend --no-edit'
rm -rf "$cc_t"

# --- Tier 2: complexity DELTA gate (FR-010) ----------------------------------------------
head_ "Complexity delta gate"

# code-quality.md's limits are aggregate rules — the class agents honour least in prose. The
# pre-commit hook runs them as a DELTA where lizard is installed: a staged file may not gain
# over-limit functions versus HEAD. lizard is not on CI, so a stub on PATH drives the logic: one
# warning per LIZARD_VIOLATION marker. This tests OUR delta, not lizard.
#
# Mutation-checked 2026-09-22: `-gt` → `-ge` on the compare → "unchanged count" went red — on the
# SECOND attempt; the first fixture staged content identical to HEAD, so nothing was staged and the
# gate never ran (see the case's comment). The exemption removed → the exemption case went red.
# Restored.
cx_t="$(mktemp -d)"; cx_b="$(mktemp -d)"
printf '#!/bin/bash\nf="${@: -1}"; n=$(grep -c LIZARD_VIOLATION "$f" 2>/dev/null || true); for i in $(seq 1 ${n:-0}); do echo "$f:$i: warning: fn$i has 60 NLOC, 12 CCN"; done; exit 0\n' > "$cx_b/lizard"
chmod +x "$cx_b/lizard"
( cd "$cx_t" && git init -q . && printf 'x # LIZARD_VIOLATION\n' > a.py && git add a.py && git -c user.email=s@t -c user.name=s commit -q -m 'feat: base' ) >/dev/null 2>&1
cx_case() { # expected-exit description
  local exp="$1" desc="$2" rc=0
  jq -nc --arg d "$cx_t" '{tool_input:{command:"git commit -m \"feat: x\""},cwd:$d}' | PATH="$cx_b:$PATH" bash "$QBC" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$exp" ]; then ok "$desc"; else bad "$desc (want exit $exp, got $rc)"; fi
}
( cd "$cx_t" && printf 'x # LIZARD_VIOLATION\ny # LIZARD_VIOLATION\n' > a.py && git add a.py ); cx_case 2 "blocks a staged file that GAINED an over-limit function (1 → 2)"
# A REAL diff with the same count: identical content stages nothing, the gate never runs, and the
# case passes vacuously — which is how the first `-gt`→`-ge` mutation survived. Measured.
( cd "$cx_t" && printf 'y # LIZARD_VIOLATION\n' > a.py && git add a.py );                           cx_case 0 "passes a changed file whose violation count is unchanged (existing debt does not block)"
( cd "$cx_t" && printf 'clean\n' > a.py && git add a.py );                                          cx_case 0 "passes a file that got better"
( cd "$cx_t" && git checkout -q a.py 2>/dev/null; git reset -q; printf 'n # LIZARD_VIOLATION\n' > new.py && git add new.py ); cx_case 2 "blocks a NEW file with an over-limit function (0 → 1)"
( cd "$cx_t" && git reset -q; rm -f new.py; mkdir -p workflows && printf 'v # LIZARD_VIOLATION\n' > workflows/workflow.js && git add workflows/workflow.js ); cx_case 0 "skips the one documented exemption (workflows/workflow.js)"
( cd "$cx_t" && git reset -q; rm -rf workflows; printf 'x # LIZARD_VIOLATION\ny # LIZARD_VIOLATION\n' > a.py && git add a.py )
rc=0; jq -nc --arg d "$cx_t" '{tool_input:{command:"git commit -m \"feat: x\""},cwd:$d}' | PATH="/usr/bin:/bin" bash "$QBC" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "the gate is silent when lizard is not installed (degrades, never blocks)"
else bad "the gate fired with lizard absent (rc=$rc) — a check that runs without its tool is a false positive factory"; fi
rm -rf "$cx_t" "$cx_b"

# --- Tier 2: release.sh moves every declaration together (FR-013) ------------------------
head_ "Release script"

# Six declarations, one command. Driven on a COPY of the declaration files so the real tree is
# untouched; the assertion is the same one the Version block above makes — they all agree — plus
# the changelog scaffold exists and the guards refuse a repeat and a malformed version.
#
# Mutation-checked 2026-09-22: `.plugins[0].version = $v` removed from the jq → "declarations
# agree" went red. Restored.
rl_t="$(mktemp -d)"
mkdir -p "$rl_t/.claude-plugin" "$rl_t/.claude" "$rl_t/hooks"
cp "$REPO/.claude-plugin/plugin.json" "$REPO/.claude-plugin/marketplace.json" "$rl_t/.claude-plugin/"
cp "$REPO/.claude/CLAUDE.md" "$rl_t/.claude/"; cp "$REPO/README.md" "$REPO/CHANGELOG.md" "$rl_t/"; cp "$REPO/hooks/release.sh" "$rl_t/hooks/"
( cd "$rl_t" && git init -q . && git add -A && git -c user.email=s@t -c user.name=s commit -q -m 'chore: import' && git tag v0.0.1 \
  && printf 'x\n' > x && git add x && git -c user.email=s@t -c user.name=s commit -q -m 'feat: scaffold me' \
  && printf 'y\n' > y && git add y && git -c user.email=s@t -c user.name=s commit -q -m 'test: never in notes' \
  && printf 'z\n' > z && git add z && git -c user.email=s@t -c user.name=s commit -q -m 'docs: under changed' \
  && git checkout -q -b side && printf 'w\n' > w && git add w && git -c user.email=s@t -c user.name=s commit -q -m 'fix: from a branch' \
  && git checkout -q - && git -c user.email=s@t -c user.name=s merge -q --no-ff -m 'Merge pull request #1 from side' side ) >/dev/null 2>&1
if ( cd "$rl_t" && hooks/release.sh 99.1.2 2030-01-02 ) >/dev/null 2>&1; then
  rl_p="$(jq -r .version "$rl_t/.claude-plugin/plugin.json")"
  rl_m1="$(jq -r .metadata.version "$rl_t/.claude-plugin/marketplace.json")"
  rl_m2="$(jq -r '.plugins[0].version' "$rl_t/.claude-plugin/marketplace.json")"
  rl_r="$(grep -oE 'Framework Version\*\*: [0-9.]+' "$rl_t/README.md" | grep -oE '[0-9.]+$')"
  rl_c="$(grep -m1 -oE 'Hefesto v[0-9]+\.[0-9]+' "$rl_t/.claude/CLAUDE.md" | grep -oE '[0-9.]+$')"
  if [ "$rl_p" = 99.1.2 ] && [ "$rl_m1" = 99.1.2 ] && [ "$rl_m2" = 99.1.2 ] && [ "$rl_r" = 99.1.2 ] && [ "$rl_c" = 99.1 ]; then
    ok "release.sh moved plugin.json, marketplace (×2), README footer, and the CLAUDE.md title together"
  else
    bad "release.sh left declarations disagreeing: plugin=$rl_p mkt=$rl_m1/$rl_m2 readme=$rl_r claude=$rl_c"
  fi
  if grep -qF '## [99.1.2] - 2030-01-02' "$rl_t/CHANGELOG.md" && grep -qF -- '- scaffold me' "$rl_t/CHANGELOG.md"; then
    ok "release.sh scaffolded the CHANGELOG entry from the commits since the last tag"
  else
    bad "release.sh did not scaffold the CHANGELOG entry"
  fi
  # Dogfooded 2026-09-23: the 7.0.1 scaffold listed every merge subject and the test commit under
  # "Changed". Mutation-checked: the `*) ;;` catch-all reverted to "changed=" → the test-commit
  # line reappears and this goes red. (`--no-merges` alone is NOT the guard: a merge subject already
  # falls through the type filter, so removing that flag stays green — it is belt, not braces.)
  rl_entry="$(awk '/^## \[99\.1\.2\]/{p=1;next} /^## \[/{p=0} p' "$rl_t/CHANGELOG.md")"
  if ! grep -qF 'Merge pull request' <<<"$rl_entry" && ! grep -qF 'never in notes' <<<"$rl_entry" \
     && grep -qF -- '- from a branch' <<<"$rl_entry" && grep -qF -- '- under changed' <<<"$rl_entry"; then
    ok "release.sh scaffold skips merge and test subjects and keeps fix/docs from the branch"
  else
    bad "release.sh scaffold content wrong: $(tr '\n' '|' <<<"$rl_entry")"
  fi
  if ( cd "$rl_t" && hooks/release.sh 99.1.2 ) >/dev/null 2>&1; then bad "release.sh re-ran for a version the CHANGELOG already has"
  else ok "release.sh refuses a version the CHANGELOG already has"; fi
  if ( cd "$rl_t" && hooks/release.sh 1.2 ) >/dev/null 2>&1; then bad "release.sh accepted a malformed version"
  else ok "release.sh refuses a malformed version"; fi
else
  bad "release.sh failed on a clean copy of the declaration files"
fi
rm -rf "$rl_t"

# --- Tier 2: mutation-score ratchet (FR-009) ---------------------------------------------
head_ "Mutation ratchet"

# Raise-only mark with a fixed floor. A fixed threshold drifts to aspirational; a PR-driven
# ratchet cascades failures across concurrent PRs. Driven in a scratch dir.
#
# Mutation-checked 2026-09-22: `floor=$((mark - 5))` → `- 10` → "below the floor fails" went red;
# `-gt "$mark"` → `-ge` in mutation-raise → "does not lower" went red. Restored.
mr_t="$(mktemp -d)"
mr_fail=0
out="$(cd "$mr_t" && "$HELPER" mutation-score 2>/dev/null)"; rc=$?
[ "$out" = "NO_MARK" ] && [ "$rc" -ne 0 ] || { bad "mutation-score with no mark must print NO_MARK and exit non-zero (got '$out'/$rc)"; mr_fail=1; }
(cd "$mr_t" && "$HELPER" mutation-raise 62 >/dev/null 2>&1)
[ "$(cd "$mr_t" && "$HELPER" mutation-score 2>/dev/null)" = "62" ] || { bad "mutation-raise did not record 62"; mr_fail=1; }
(cd "$mr_t" && "$HELPER" mutation-ratchet 57 >/dev/null 2>&1) || { bad "a score AT the floor (mark−5) must pass"; mr_fail=1; }
if (cd "$mr_t" && "$HELPER" mutation-ratchet 56 >/dev/null 2>&1); then bad "a score below the floor must fail the ratchet"; mr_fail=1; fi
(cd "$mr_t" && "$HELPER" mutation-raise 50 >/dev/null 2>&1)
[ "$(cd "$mr_t" && "$HELPER" mutation-score 2>/dev/null)" = "62" ] || { bad "mutation-raise lowered the mark — it must only move up"; mr_fail=1; }
if (cd "$mr_t" && "$HELPER" mutation-ratchet abc >/dev/null 2>&1); then bad "mutation-ratchet accepted a non-integer"; mr_fail=1; fi
rm -rf "$mr_t"
[ "$mr_fail" -eq 0 ] && ok "mutation-score / mutation-ratchet / mutation-raise honour the raise-only, floor-5 contract"
grep -qF 'speckit-helper.sh mutation-ratchet' "$REPO/commands/hef.mutate.md" 2>/dev/null \
  && ok "/hef.mutate runs the ratchet" || bad "/hef.mutate does not call mutation-ratchet"

# --- doctor-copies: the doctor measures the copy that RUNS ---------------------------------
# Measured 2026-09-23: the running copy is the per-profile cache (a plain copy, no .git); the
# doctor used to rev-parse it, get "not a git clone", and skip — while three profiles disagreed.
# Fixture: a fake profile dir with the two registry files, pointing at a temp clone.
# Mutation-checked: `[ "$run_sha" = "$clone_sha" ]` → `true` → "reports BEHIND" goes red.
dc_cfg="$(mktemp -d)"; dc_clone="$(mktemp -d)"; dc_fail=0
( cd "$dc_clone" && git init -q -b main . && mkdir -p .claude-plugin && printf '{"version":"1.0.0"}\n' > .claude-plugin/plugin.json \
  && git add -A && git -c user.email=s@t -c user.name=s commit -q -m 'chore: v1' ) >/dev/null 2>&1
dc_sha="$(git -C "$dc_clone" rev-parse HEAD)"
mkdir -p "$dc_cfg/plugins"
printf '{"hefesto":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' "$dc_clone" "$dc_clone" > "$dc_cfg/plugins/known_marketplaces.json"
printf '{"plugins":{"hefesto@hefesto":[{"scope":"user","installPath":"%s/plugins/cache/hefesto/hefesto/1.0.0","version":"1.0.0","gitCommitSha":"%s"}]}}\n' "$dc_cfg" "$dc_sha" > "$dc_cfg/plugins/installed_plugins.json"
dc_out="$(CLAUDE_CONFIG_DIR="$dc_cfg" "$HELPER" doctor-copies 2>&1)"
grep -qF 'status: RUNNING_MATCHES_CLONE' <<<"$dc_out" || { bad "doctor-copies: running sha == clone HEAD must report MATCHES, got: $(tr '\n' '|' <<<"$dc_out")"; dc_fail=1; }
grep -qF "running: 1.0.0 ${dc_sha:0:7}" <<<"$dc_out" || { bad "doctor-copies did not print the running version/sha from the registry"; dc_fail=1; }
( cd "$dc_clone" && printf '{"version":"1.1.0"}\n' > .claude-plugin/plugin.json && git -c user.email=s@t -c user.name=s commit -qam 'feat: v1.1' ) >/dev/null 2>&1
dc_out="$(CLAUDE_CONFIG_DIR="$dc_cfg" "$HELPER" doctor-copies 2>&1)"
grep -qF 'status: RUNNING_BEHIND_CLONE ' <<<"$dc_out" && grep -qF 'claude plugin update hefesto@hefesto' <<<"$dc_out" \
  || { bad "doctor-copies: clone ahead with a newer version must report BEHIND + the update command, got: $(tr '\n' '|' <<<"$dc_out")"; dc_fail=1; }
( cd "$dc_clone" && printf '{"version":"1.0.0"}\n' > .claude-plugin/plugin.json && git -c user.email=s@t -c user.name=s commit -qam 'chore: same version' ) >/dev/null 2>&1
dc_out="$(CLAUDE_CONFIG_DIR="$dc_cfg" "$HELPER" doctor-copies 2>&1)"
grep -qF 'status: RUNNING_BEHIND_CLONE_SAME_VERSION' <<<"$dc_out" && grep -qF 'uninstall' <<<"$dc_out" \
  || { bad "doctor-copies: clone ahead at the SAME version must say plugin update will not refresh, got: $(tr '\n' '|' <<<"$dc_out")"; dc_fail=1; }
if CLAUDE_CONFIG_DIR="$dc_cfg/nowhere" "$HELPER" doctor-copies >/dev/null 2>&1; then bad "doctor-copies must exit non-zero when the profile has no plugin registry"; dc_fail=1; fi
rm -rf "$dc_cfg" "$dc_clone"
[ "$dc_fail" -eq 0 ] && ok "doctor-copies reads the RUNNING copy from the profile registry and compares it with the clone"
grep -qF 'speckit-helper.sh doctor-copies' "$REPO/commands/hef.doctor.md" 2>/dev/null \
  && ok "/hef.doctor measures the running copy via doctor-copies" || bad "/hef.doctor does not call doctor-copies"
if grep -qF 'rev-parse --show-toplevel' "$REPO/commands/hef.doctor.md" && grep -qF 'CLAUDE_PLUGIN_ROOT}" rev-parse' "$REPO/commands/hef.doctor.md"; then
  bad "/hef.doctor still rev-parses CLAUDE_PLUGIN_ROOT — that is the cache, never a git clone"
else ok "/hef.doctor no longer treats CLAUDE_PLUGIN_ROOT as a git clone"; fi

# --- Tier 2: merge-tree probe + owned files (FR-012) --------------------------------------
head_ "Parallel-safety"

# The probe reports a committed-state conflict with the base and stays silent on a clean branch,
# on the base branch itself, and when throttled. The owns: contract is prose in three places the
# workflow's batcher depends on.
#
# Mutation-checked 2026-09-22: the CONFLICT echo removed → "reports a conflict" went red. Restored.
MTP="$REPO/hooks/merge-tree-probe.sh"
mt_t="$(mktemp -d)"
( cd "$mt_t" && git init -q -b main . && printf 'a\n' > f && git add f && git -c user.email=s@t -c user.name=s commit -q -m 'chore: base' \
  && git checkout -q -b feature/x && printf 'b\n' > f && git -c user.email=s@t -c user.name=s commit -qam 'feat: x' \
  && git checkout -q main && printf 'c\n' > f && git -c user.email=s@t -c user.name=s commit -qam 'fix: y' && git checkout -q feature/x ) >/dev/null 2>&1
rm -f /tmp/.hefesto-merge-probe-* 2>/dev/null
mt_out="$(printf '{"cwd":"%s"}' "$mt_t" | bash "$MTP" 2>&1 >/dev/null)"
if grep -qF 'CONFLICT with main in: f' <<<"$mt_out"; then ok "merge-tree probe reports a committed-state conflict with the base, naming the file"
else bad "merge-tree probe missed the conflict: $mt_out"; fi
mt_out2="$(printf '{"cwd":"%s"}' "$mt_t" | bash "$MTP" 2>&1 >/dev/null)"
[ -z "$mt_out2" ] && ok "merge-tree probe is throttled (second call within a minute is silent)" || bad "merge-tree probe ran twice inside the throttle window"
rm -f /tmp/.hefesto-merge-probe-* 2>/dev/null
( cd "$mt_t" && git checkout -q main ) >/dev/null 2>&1
mt_out3="$(printf '{"cwd":"%s"}' "$mt_t" | bash "$MTP" 2>&1 >/dev/null)"
[ -z "$mt_out3" ] && ok "merge-tree probe is silent on the base branch" || bad "merge-tree probe spoke on main: $mt_out3"
rm -rf "$mt_t"
if jq -e '.hooks.PostToolUse[] | select(.matcher | test("Edit")) | .hooks[] | select(.command | test("merge-tree-probe"))' "$REPO/hooks/hooks.json" >/dev/null 2>&1; then
  ok "merge-tree probe is registered on PostToolUse Edit|Write"
else
  bad "merge-tree-probe.sh is not registered — it exists and never fires"
fi
owns_fail=0
grep -qF 'owns:' "$REPO/.specify/templates/tasks.md" || { bad "tasks template lost the owns: field"; owns_fail=1; }
grep -qF 'owns:' "$REPO/commands/hef.tasks.md" || { bad "/hef.tasks no longer asks [P] tasks to declare owns:"; owns_fail=1; }
grep -qF 'owns:' "$REPO/workflows/workflow.js" || { bad "the workflow loader no longer parses owns:"; owns_fail=1; }
grep -qF 'both own' "$REPO/workflows/workflow.js" || { bad "the workflow no longer names owns: overlaps"; owns_fail=1; }
[ "$owns_fail" -eq 0 ] && ok "owns: is declared in the template, requested by /hef.tasks, parsed and overlap-reported by the workflow"

# --- Tier 2: router, evals, shellcheck (FR-011, FR-014) -----------------------------------
head_ "Router and evals"

grep -qF 'task-effort-estimation' "$REPO/commands/hef.agent.md" && grep -qF 'hef.fix' "$REPO/commands/hef.agent.md" \
  && ok "/hef.agent routes by size via task-effort-estimation (FR-011)" \
  || bad "/hef.agent no longer routes by size"
ev_fail=0; ev_n=0
for c in "$REPO"/evals/*/case.yaml; do
  [ -f "$c" ] || continue
  ev_n=$((ev_n + 1))
  # The contract claude plugin eval 2.1.280 enforces (learned by running it: the first suite
  # reported zero cases, the second "missing required field schema_version", the third an
  # invalid grader discriminator). Each of those is now a red check here.
  grep -qE '^schema_version: "1\.[0-9]+"' "$c" && grep -qE '^name:' "$c" && grep -qE '^execution:' "$c" \
    && grep -qE '^\s+prompt:' "$c" && grep -qE '^graders:' "$c" \
    && grep -qE '^\s+type: "?(regex|tool_used|tool_order|file_exists|llm|baseline)"?$' "$c" \
    && ! grep -qE '^\s+type: "?(contains|llm-judge|rubric)"?' "$c" \
    || { bad "eval case $(basename "$(dirname "$c")") does not match the case.yaml contract (schema_version 1.x, name, execution.prompt, graders with a real type)"; ev_fail=1; }
done
[ "$ev_n" -ge 1 ] || { bad "no eval cases under evals/"; ev_fail=1; }
[ "$ev_fail" -eq 0 ] && ok "$ev_n eval case(s) parse structurally: name, prompt, graders with a known type (FR-014)"
if command -v shellcheck >/dev/null 2>&1; then
  sc_bad="$(shellcheck -S warning "$REPO"/hooks/*.sh 2>&1 | grep -c '^In ' || true)"
  [ "${sc_bad:-0}" -eq 0 ] && ok "shellcheck (warning+) is clean on every hook" || bad "shellcheck reports $sc_bad finding(s) in hooks/"
else
  printf '  \033[33mskip\033[0m shellcheck not installed — hooks were only bash -n checked at commit time\n'
fi

# --- Tier 3: the 7.0 shape (FR-015, FR-016, FR-017, FR-018, FR-019) ---------------------
head_ "7.0 toolbox shape"

# Renames are why 7.0 is major. The old names must be GONE (a stale file would silently keep
# registering a command the docs no longer mention), the new ones present and wired.
t3_fail=0
[ -f "$REPO/commands/hef.doctor.md" ] || { bad "commands/hef.doctor.md is missing (FR-015)"; t3_fail=1; }
[ -e "$REPO/commands/hef.sync.md" ] && { bad "commands/hef.sync.md still exists — the 7.0 rename left the old command registered (FR-015)"; t3_fail=1; }
[ -e "$REPO/commands/hef.pr-summary.md" ] && { bad "commands/hef.pr-summary.md still exists — it was folded into /hef.pr --summary-only (FR-015)"; t3_fail=1; }
grep -qF -- '--summary-only' "$REPO/commands/hef.pr.md" 2>/dev/null || { bad "/hef.pr lost --summary-only, the replacement for /hef.pr-summary (FR-015)"; t3_fail=1; }
grep -qF 'shellcheck' "$REPO/commands/hef.doctor.md" 2>/dev/null && grep -qF 'claude plugin eval' "$REPO/commands/hef.doctor.md" 2>/dev/null \
  || { bad "/hef.doctor no longer lints the hooks or offers the eval suite (FR-015)"; t3_fail=1; }
[ "$t3_fail" -eq 0 ] && ok "hef.sync → hef.doctor and hef.pr-summary → hef.pr --summary-only, old names gone (FR-015)"

# 7.0 also unified the namespace: every command is hef.*, and no command text names a speckit.*
# command any more (the helper keeps its filename — renaming it would force a permission-rule
# edit on every install for no user-visible gain). A stray speckit.* file would register a second,
# undocumented copy of a command; a stale mention sends the model to a name that no longer exists.
#
# Mutation-checked 2026-09-23: a stray commands/speckit.x.md → red; a `/speckit.plan` mention
# planted in a command → red. Restored.
uni_fail=0
stray="$(ls "$REPO"/commands/ 2>/dev/null | grep -v '^hef\.' || true)"
[ -n "$stray" ] && { bad "commands not under the hef.* namespace: $(tr '\n' ' ' <<<"$stray")"; uni_fail=1; }
# docs/research.md is excluded: its acknowledgments credit upstream projects by their own command
# names (speckit.research, speckit.reflect), which is attribution, not a stale reference.
stale="$(grep -rlE 'speckit\.[a-z]' "$REPO/commands/" "$REPO/README.md" "$REPO/docs/" "$REPO/.claude/CLAUDE.md" "$REPO/AGENTS.md" 2>/dev/null | grep -v 'docs/research.md' || true)"
[ -n "$stale" ] && { bad "speckit.* command names still mentioned in: $(tr '\n' ' ' <<<"$stale")"; uni_fail=1; }
[ -f "$REPO/workflows/workflow.js" ] || { bad "workflows/workflow.js is missing — the workflow is invoked as hefesto:workflow"; uni_fail=1; }
[ "$uni_fail" -eq 0 ] && ok "every command is hef.*, no command text names a speckit.* command, the workflow is hefesto:workflow (FR-015)"

# Knowledge skills are not commands; action skills still are. Both directions.
inv_fail=0
for s in quality-tooling pipeline-security mcp-security agent-collaboration; do
  fm="$(sed -n '/^---$/,/^---$/p' "$REPO/skills/$s/SKILL.md")"
  grep -qE '^user-invocable: false' <<<"$fm" || { bad "knowledge skill $s is still user-invocable — it shows up as a command nobody should run (FR-016)"; inv_fail=1; }
done
for s in systematic-debugging performance-audit task-effort-estimation; do
  fm="$(sed -n '/^---$/,/^---$/p' "$REPO/skills/$s/SKILL.md")"
  grep -qE '^user-invocable: false' <<<"$fm" && { bad "action skill $s was demoted to knowledge — users can no longer invoke it (FR-016)"; inv_fail=1; }
done
[ "$inv_fail" -eq 0 ] && ok "the four knowledge skills are user-invocable: false; the three action skills remain invocable (FR-016)"

# Every report carries a machine-readable decision status. Inferring it from prose is how a repo
# of 98 ADRs misread 59 of them.
adr_fail=0
for r in "$REPO"/reports/*.md; do
  fm="$(sed -n '1,/^---$/p' "$r" | sed -n '2,$p')"
  [ "$(head -1 "$r")" = "---" ] || { bad "$(basename "$r") has no frontmatter (FR-017)"; adr_fail=1; continue; }
  grep -qE '^status: (proposed|accepted|rejected|deprecated|superseded)$' <<<"$fm" || { bad "$(basename "$r") status is missing or not in the MADR enum (FR-017)"; adr_fail=1; }
  grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$fm" || { bad "$(basename "$r") has no date (FR-017)"; adr_fail=1; }
done
grep -qE '^   status: proposed' "$REPO/commands/hef.adr.md" 2>/dev/null || { bad "/hef.adr does not write MADR frontmatter (FR-017)"; adr_fail=1; }
[ "$adr_fail" -eq 0 ] && ok "every report carries MADR status + date frontmatter, and /hef.adr writes it (FR-017)"

# The cross-tool shim and the routine.
if [ -f "$REPO/AGENTS.md" ] && grep -qF 'CLAUDE.md' "$REPO/AGENTS.md" && grep -qF '.claude/rules' "$REPO/AGENTS.md"; then
  ok "AGENTS.md exists and points other tools at CLAUDE.md and the rules (FR-018)"
else
  bad "AGENTS.md is missing or does not point at CLAUDE.md + .claude/rules (FR-018)"
fi
grep -qiF 'doc gardening' "$REPO/docs/agents.md" && ok "the doc-gardening routine is documented (FR-018)" || bad "docs/agents.md lost the doc-gardening routine (FR-018)"

# Persistent memory on the two agents whose findings recur across runs.
mem_fail=0
for a in forensic-specialist code-reviewer; do
  fm="$(sed -n '/^---$/,/^---$/p' "$REPO/agents/$a.md")"
  grep -qE '^memory: project$' <<<"$fm" || { bad "agent $a does not declare memory: project (FR-019)"; mem_fail=1; }
done
[ "$mem_fail" -eq 0 ] && ok "forensic-specialist and code-reviewer declare memory: project (FR-019)"

# --- Tier 1: the review agents have commands (FR-002) ------------------------------------
head_ "Command → agent wiring"

# code-reviewer and review-coordinator existed for four releases with no command that dispatched
# them; the documented chain had no entry point for its first link. A command that names the wrong
# agent, or none, is the same bug back.
cw_fail=0
grep -qF 'code-reviewer' "$REPO/commands/hef.review.md" 2>/dev/null || { bad "/hef.review does not dispatch code-reviewer"; cw_fail=1; }
grep -qF 'review-coordinator' "$REPO/commands/hef.pr.md" 2>/dev/null || { bad "/hef.pr does not dispatch review-coordinator"; cw_fail=1; }
grep -qiE 'not merge|never merge' "$REPO/commands/hef.pr.md" 2>/dev/null || { bad "/hef.pr must state that it never merges"; cw_fail=1; }
grep -qF 'code-reviewer' "$REPO/commands/hef.verify.md" 2>/dev/null || { bad "/hef.verify does not run code-reviewer stage 1"; cw_fail=1; }
[ "$cw_fail" -eq 0 ] && ok "hef.review → code-reviewer, hef.pr → review-coordinator (no merge), hef.verify → code-reviewer stage 1 (FR-002)"

# --- Tier 1: prose that must exist because a hook points at it (FR-004, FR-005, FR-007) ---
head_ "Guidance wiring"

# Each of these is a rule a hook or command cites by name. If the prose goes, the reference dangles.
gw_fail=0
grep -qF 'jscpd' "$REPO/agents/quality-guardian.md" || { bad "quality-guardian lost the duplication-baseline recipe (FR-004)"; gw_fail=1; }
grep -qiF 'mock budget' "$REPO/agents/test-specialist.md" || { bad "test-specialist lost the mock budget (FR-005)"; gw_fail=1; }
grep -qF 'Agentic' "$REPO/.claude/rules/llm-security.md" || { bad "llm-security.md no longer covers the Agentic Top 10 (FR-007)"; gw_fail=1; }
for c in hef.pr hef.fix; do   # hef.pr-summary folded into hef.pr --summary-only in 7.0
  grep -qF '## Untrusted input' "$REPO/commands/$c.md" || { bad "/$c lost its untrusted-input section (FR-007)"; gw_fail=1; }
done
grep -qF 'Skills, Plugins, and Agents Are a Supply Chain' "$REPO/skills/mcp-security/SKILL.md" || { bad "mcp-security lost the skill vetting checklist (FR-007)"; gw_fail=1; }
grep -qF '/sandbox' "$REPO/docs/install.md" || { bad "install.md no longer tells users to enable the sandbox (FR-007)"; gw_fail=1; }
[ "$gw_fail" -eq 0 ] && ok "every hook-cited rule and section is present (FR-004, FR-005, FR-007)"

# --- Result --------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
