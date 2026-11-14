# shellcheck shell=bash
# forge-lib.sh — the forge rules hefesto-setup.sh, session-launch.sh and ledger.sh share (forge-setup, HEF-22).
# SOURCED, never run. Zero-install: bash, git, jq, stat, date.
#
#   forge_public_host <host[:port]>      0 when a public hostname (the launcher's allowed_domains rule, moved here)
#   forge_domains <host>                 the orchestrate.allowed_domains entries for a forge host, one per line (D3)
#   forge_remote_url <repo dir>          the push URL of origin, or of the only remote; 1 = none or ambiguous (D4)
#   forge_host <url>                     the host of a remote URL; 1 = none
#   forge_ssh_prefix <url>               "host<TAB>pushInsteadOf prefix"; 1 = not SSH, 2 = SSH it cannot rewrite (D5)
#   forge_stale_lock <git common dir>    the config.lock path when zero bytes and older than 60 s; 1 = none (D7)
#   forge_infra_fix <cause> <hooks dir> <board config> <validated host or "">   the one fix line; 1 = unknown cause
#   forge_infra_stall <ledger.sh> <id> <outcome JSON>   an infrastructure outcome → blocked stall, prints the fix
#
# Every function that cannot answer returns non-zero with no output (constitution 5): a caller never mistakes
# "no answer" for an empty answer.

# The causes a worker may report (FR-011): a closed enum, so no worker text ever becomes the fix line (D6).
FORGE_CAUSES="push-refused host-denied credential-helper-missing"
# The worker prompt's sentence on when to set infra_cause (FR-011) — here, beside the table it feeds, because the
# launcher is at the 500-code-line limit.
FORGE_INFRA_RULE='If the run stopped on infrastructure rather than on the work, also set infra_cause: "push-refused" when git push was refused (an SSH remote, or the sandbox), "host-denied" when the sandbox denied a host the build needs (its hostname in infra_host), "credential-helper-missing" when an HTTPS push had no credential helper; otherwise leave infra_cause null. The fix the person sees comes from a fixed table, never from your summary. '

forge_public_host() { # $1 host[:port], optional leading *. → 0 when a public hostname
  # a public hostname only: the last label is letters (no IP literal — 169.254.169.254, 10.x, 127.x), no
  # localhost, a port in 1..65535. This rule moves the worker sandbox's own network boundary. The regex is
  # byte-identical to the one session-launch.sh carried inline before HEF-22.
  [[ "$1" =~ ^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,63}(:([0-9]{1,5}))?$ ]] || return 1
  local port="${BASH_REMATCH[5]}"   # read before the next match overwrites BASH_REMATCH
  # names that resolve inside a network by convention: the cloud metadata service (metadata.google.internal),
  # the container host (host.docker.internal), mDNS, home routers — a text check cannot stop DNS beyond these
  [[ ! "$1" =~ (^|\.)(localhost|internal|local|localdomain|lan|home|intranet|corp)(:|$) ]] || return 1
  [ -z "$port" ] || { [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; }
}

forge_domains() { # $1 host → the allowed_domains entries (D3): github.com also needs its API host for gh pr create
  case "$1" in github.com) printf '%s\n' github.com api.github.com ;; *) printf '%s\n' "$1" ;; esac
}

forge_remote_url() { # $1 repo dir → pushurl, else url, of origin (exact name) or of the only remote
  local rs r
  rs="$(git -C "$1" remote 2>/dev/null)" || return 1
  case $'\n'"$rs"$'\n' in
    *$'\n'origin$'\n'*) r=origin ;;
    $'\n'$'\n') return 1 ;;                                  # no remote
    *) case "$rs" in *$'\n'*) return 1 ;; esac; r="$rs" ;;   # several, none named origin: ambiguous
  esac
  git -C "$1" config --get "remote.$r.pushurl" || git -C "$1" config --get "remote.$r.url"
}

forge_host() { # $1 url (scheme://[user@]host[:port]/…, [user@]host:path) → host
  local h="$1"
  case "$h" in
    *://*) h="${h#*://}"; h="${h%%/*}"; h="${h##*@}"; h="${h%%:*}" ;;
    /*|.*) return 1 ;;                                       # a local path
    *:*) h="${h%%:*}"; h="${h##*@}" ;;
    *) return 1 ;;
  esac
  [ -n "$h" ] || return 1
  printf '%s\n' "$h"
}

forge_ssh_prefix() { # $1 url → "host<TAB>prefix" for an SSH remote with user git; 1 = not SSH; 2 = SSH not rewritable
  local a h
  case "$1" in
    ssh://*) a="${1#ssh://}"; a="${a%%/*}"
      case "$a" in
        git@*:*) return 2 ;;                                 # an explicit port: the HTTPS host is unknowable
        git@?*) h="${a#git@}"; printf '%s\tssh://git@%s/\n' "$h" "$h" ;;
        *) return 2 ;;                                       # a user other than git (or none)
      esac ;;
    *://*|/*|.*) return 1 ;;                                 # https://, file://, a local path
    git@?*:*) h="${1#git@}"; h="${h%%:*}"; printf '%s\tgit@%s:\n' "$h" "$h" ;;
    *:*) return 2 ;;                                         # scp-like with another user, or none
    *) return 1 ;;
  esac
}

forge_stale_lock() { # $1 git common dir → the lock path when zero bytes and older than 60 s (D7)
  local l="$1/config.lock" m
  [ -f "$l" ] && [ ! -s "$l" ] || return 1
  # GNU first, then BSD (macOS): `stat -f` on GNU means "file system", so the order matters
  m="$(stat -c %Y "$l" 2>/dev/null || stat -f %m "$l" 2>/dev/null)" || return 1
  [ $(( $(date +%s) - m )) -gt 60 ] || return 1
  printf '%s\n' "$l"
}

forge_infra_fix() { # $1 cause, $2 hooks dir, $3 board config, $4 validated host or "" → one line (D6, P6)
  case "$1" in
    push-refused) echo "run in a terminal: bash $2/hefesto-setup.sh (it sets the HTTPS push rewrite and the forge hosts)" ;;
    credential-helper-missing) echo "run in a terminal: gh auth setup-git" ;;
    # the host is the worker's claim, never a bare instruction to allow it (P6)
    host-denied) if [ -n "$4" ]; then echo "the worker reports it was denied $4 — if the run log confirms the build needs it, add it to orchestrate.allowed_domains in $3"
                 else echo "find the denied host in the run log; if the build needs it, add it to orchestrate.allowed_domains in $3"; fi ;;
    *) return 1 ;;
  esac
}

forge_infra_stall() { # $1 ledger.sh, $2 id, $3 outcome JSON → 0 when an infrastructure stop, now blocked stall; 1 = not one
  # FR-012/FR-016: an outcome with infra_cause is a stall even with blocked_on null (never human:intake) or outcome
  # failed (never die). The printed line is read back from the ledger, which rendered it — never built here (D6).
  local c h r
  c="$(jq -r '.infra_cause // empty' <<<"$3")"; [ -n "$c" ] || return 1
  case "$(jq -r .outcome <<<"$3")" in blocked|failed) ;; *) return 1 ;; esac
  h="$(jq -r '.infra_host // empty' <<<"$3")"
  "$1" block "$2" --kind stall --cause "$c" ${h:+--host "$h"} >/dev/null || exit 1
  r="$("$1" show "$2" | jq -r '.blocked_on.reason // empty')" || exit 1
  echo "infra: $r"
}
