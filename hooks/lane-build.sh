#!/bin/bash
# lane-build.sh — run a build or test command with the toolchain caches in the lanes' own build cache (#162).
#
#   <hooks>/lane-build.sh make check
#
# A lane's sandbox makes ~/.cache/go-build and the like read-only, so a fresh compile fails. The cache cannot simply be
# named in the lane's settings `env`: that reaches every subprocess — hooks and approved unsandboxed actions too — and an
# unsandboxed build would link objects a sandboxed lane planted. So the caches are pointed at the lane cache here, for
# this one command, and only when this command runs INSIDE the sandbox:
#
#   - the probe: a write into ~/.cache/hefesto/lane-cache-probe, which setup creates and never puts in the sandbox's
#     allowWrite, fails inside the sandbox (read-only file system / operation not permitted) and succeeds outside it.
#     A successful write is a refusal, and a missing folder is too — never read as "sandboxed";
#   - setup checks, unsandboxed, that the probe folder is writable, so a write failing for another reason (a full disk,
#     a read-only home) is caught there, not mistaken here for the sandbox.
#
# Exit: the command's own status (exec); 2 = refused, nothing ran, the cause and the fix on stderr.
set -uo pipefail
refuse() { echo "lane-build.sh: $1" >&2; exit 2; }
HEF_LL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane-lib.sh"
[ -f "$HEF_LL" ] || refuse "hooks/lane-lib.sh is missing beside it"
# shellcheck source=hooks/lane-lib.sh
. "$HEF_LL"
[ $# -gt 0 ] || refuse "usage: lane-build.sh <command> [args…]"

LC="${HEFESTO_LANE_CACHE:-}"; BASE="$(hef_cache)/lane-cache"; PROBE="$(hef_cache)/lane-cache-probe"
case "$LC" in
  "$BASE"/*) [[ "${LC#"$BASE"/}" =~ ^[0-9a-f]{32}$ ]] || refuse "HEFESTO_LANE_CACHE is not a lane cache path ($BASE/<key>) — run hefesto-setup.sh --lanes" ;;
  *) refuse "no lane cache in this session (HEFESTO_LANE_CACHE) — run hefesto-setup.sh --lanes, then restart the lane" ;;
esac
[ -d "$PROBE" ] || refuse "the probe folder $PROBE is missing — run hefesto-setup.sh --lanes"
if ( : > "$PROBE/.w.$$" ) 2>/dev/null; then
  rm -f "$PROBE/.w.$$"; refuse "this command is not running inside the sandbox — the lane cache is for sandboxed commands only (#162)"
fi
( : > "$LC/.w.$$" ) 2>/dev/null && rm -f "$LC/.w.$$" || refuse "the lane cache $LC is not writable in this sandbox (missing from sandbox.filesystem.allowWrite, or a full disk) — run hefesto-setup.sh --lanes"

exec env GOCACHE="$LC/go-build" npm_config_cache="$LC/npm" PIP_CACHE_DIR="$LC/pip" XDG_CACHE_HOME="$LC/xdg" \
  YARN_CACHE_FOLDER="$LC/yarn" BUN_INSTALL_CACHE_DIR="$LC/bun" "$@"
