#!/usr/bin/env bash
# Acceptance for PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01 (row 7b160d2ff551).
#
# Replaces the lead's first probe, which was a STUB: it referenced $OUT, a variable
# nothing ever set, so under `set -u` it exited 1 without taking a single
# measurement. A probe that cannot go green is not an acceptance criterion.
#
# Subject: `_architect_prepass_admission_status <adir> <captured-out>` in
# plugins/leadv2/scripts/leadv2-dispatch-code.sh. Its admission test is
#   grep -qiE 'status[=:][[:space:]]*allowed'
# and against real JSON — `"status":"allowed"` — the character after the colon is a
# quote, which is neither whitespace nor `a`. The match fails and the function
# falls through to `unknown`. Measured on main 2026-09-16, not read off the regex.
#
# Three cases, because the defect has two halves and the instrument needs a control:
#   1. JSON "status":"allowed"       -> allowed        (the defect; unknown on main)
#   2. JSON "status":"quota_refused" -> quota_refused  (same quote-blindness, other branch)
#   3. bare  status=allowed          -> allowed        (POSITIVE CONTROL: this already
#      passes on main, so a failure here means the probe lost its grip on the
#      function, not that the fix regressed)
#
# Case 3 is what stops a "fix" that simply makes every payload return `allowed`
# from being indistinguishable from a real one: case 2 must NOT come back allowed.
#
# Resolves the dispatcher from THIS file, so a lane worktree grades its own tree.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LV2="$(cd "$HERE/../../.." && pwd)"
DISPATCH="$LV2/plugins/leadv2/scripts/leadv2-dispatch-code.sh"
[ -f "$DISPATCH" ] || { echo "no dispatcher at $DISPATCH"; exit 2; }

cd "$LV2" || exit 2
export LEADV2_DISPATCH_SOURCE_ONLY=1
# shellcheck disable=SC1090
source "$DISPATCH" 2>/dev/null

if ! declare -F _architect_prepass_admission_status >/dev/null; then
  echo "seam MISSING: _architect_prepass_admission_status is not defined under LEADV2_DISPATCH_SOURCE_ONLY=1"
  exit 2
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/prepass-admission.XXXXXX")" || exit 2
trap 'rm -rf "$D"' EXIT

fails=0
check() { # <label> <payload> <expected>
  local label="$1" payload="$2" want="$3" got
  got="$(_architect_prepass_admission_status "$D" "$payload" 2>/dev/null)"
  printf '%-34s -> expect %-14s got %s\n' "$label" "$want" "${got:-<empty>}"
  [ "$got" = "$want" ] || fails=$((fails + 1))
}

check 'json "status":"allowed"'       '{"type":"rate_limit_event","status":"allowed","limits":[{"kind":"session","percent":34}]}' allowed
check 'json "status":"quota_refused"' '{"type":"rate_limit_event","status":"quota_refused"}'                                      quota_refused
check 'bare status=allowed (control)' 'status=allowed'                                                                            allowed

printf 'pass=%d fail=%d\n' "$((3 - fails))" "$fails"
exit $((fails ? 1 : 0))
