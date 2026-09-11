#!/usr/bin/env bash
# tests/nc-think-model-arbiter-wins.sh — negative control for
# test-think-model-arbiter-wins.sh (ENV-PIN-SILENTLY-BEATS-THE-ARBITER-01).
#
# Proves the suite can actually go red on the two regressions this row closes:
#   (a) restoring the LEADV2_THINK_MODEL override (the env pin)  -> case 2 red
#   (b) making the model-capability kill switch advisory          -> case 5a red
# Pattern: nc-claude-profile-select.sh — mutate a SCRATCH COPY, never the
# tracked router; every mutation pattern must match EXACTLY once or the NC
# exits 2 loudly (NC-SETUP-FAIL), and the suite must be GREEN against the
# unmutated router first or "mutant is red" means nothing
# (BALANCER-NEGATIVE-CONTROL-HALF-ROTTED-01).
#
# The scratch copy keeps SCRIPT_DIR-relative resolution working: the router
# sources lib/ and reads ../config/* relative to its own path, so the scratch
# tree is scripts/leadv2-router.sh (mutant) + lib and config symlinks to the
# real read-only trees. The suite is pointed at it via LEADV2_TEST_ROUTER —
# the only reason that seam exists.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="$(cd "${SCRIPTS_DIR}/../config" && pwd)"
SRC="$SCRIPTS_DIR/leadv2-router.sh"
SUITE="$SCRIPT_DIR/test-think-model-arbiter-wins.sh"
TMP_BASE="${LEADV2_TEST_TMPDIR:-/tmp}"
SCRATCH="$(mktemp -d "${TMP_BASE%/}/nc-think-model-arbiter-wins.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

refuse_if_tracked(){ # $1=mock/mutant target — never write onto a tracked file
  git -C "$(dirname "$1")" ls-files --error-unmatch "$(basename "$1")" >/dev/null 2>&1 \
    && { echo "REFUSED: mock target is tracked"; exit 2; }
}
count_or_die(){ # $1=fixed-string pattern $2=file — exactly one match or NC-SETUP-FAIL
  local n
  n="$(grep -cF "$1" "$2")" || true
  if [[ "${n:-0}" -ne 1 ]]; then
    echo "NC-SETUP-FAIL: mutation pattern not found exactly once (count=${n:-0}): $1" >&2
    exit 2
  fi
}
count_re_or_die(){ # $1=ERE pattern $2=file — same discipline for regex mutations
  local n
  n="$(grep -cE "$1" "$2")" || true
  if [[ "${n:-0}" -ne 1 ]]; then
    echo "NC-SETUP-FAIL: mutation pattern not found exactly once (count=${n:-0}): $1" >&2
    exit 2
  fi
}

# ── baseline: the suite must be green against the unmutated router ──────────
echo "--- NC: baseline suite run (unmutated router) ---"
base_out="$(bash "$SUITE" 2>&1)"; base_rc=$?
printf '%s\n' "$base_out" | tail -2
if [[ "$base_rc" -ne 0 ]]; then
  echo "NC-BASELINE-RED: suite already red on the real router — a red baseline makes 'mutant is red' meaningless; fix the suite first" >&2
  exit 2
fi

# ── mutation (a): restore the env override (the pin this row removed) ───────
echo "--- NC-a: mutation = env pin outranks the arbiter ---"
count_re_or_die '^  if \[\[ -n "\$resolved" \]\]; then *# ARBITER-WINS$' "$SRC"
refuse_if_tracked "$SCRATCH/scripts/leadv2-router.sh"
# Scratch tree: every SCRIPT_DIR-relative sibling is symlinked read-only
# (leadv2-temp.sh is sourced at router:25 BEFORE any think path; lib/ and
# config/ likewise) — only leadv2-router.sh itself is a real (mutated) file.
mkdir -p "$SCRATCH/scripts"
for f in "$SCRIPTS_DIR"/*.sh; do
  b="$(basename "$f")"
  [[ "$b" == "leadv2-router.sh" ]] && continue
  ln -s "$f" "$SCRATCH/scripts/$b"
done
ln -s "$SCRIPTS_DIR/lib" "$SCRATCH/scripts/lib"
ln -s "$CONFIG_DIR" "$SCRATCH/config"
sed 's/^  if \[\[ -n "\$resolved" \]\]; then\( *# ARBITER-WINS\)$/  if [[ -n "$resolved" \&\& -z "${LEADV2_THINK_MODEL:-}" ]]; then/' \
  "$SRC" > "$SCRATCH/scripts/leadv2-router.sh" || { echo "NC-SETUP-FAIL: sed failed" >&2; exit 2; }
if cmp -s "$SRC" "$SCRATCH/scripts/leadv2-router.sh"; then
  echo "NC-SETUP-FAIL: mutation (a) did not apply (mutant identical to source — pattern drifted? update this NC)" >&2
  exit 2
fi
out_a="$(LEADV2_TEST_ROUTER="$SCRATCH/scripts/leadv2-router.sh" bash "$SUITE" 2>&1)"; rc_a=$?
printf '%s\n' "$out_a" | grep -E '^(FAIL|SUMMARY)' || true
nc_a=0
if [[ "$rc_a" -ne 0 ]] && printf '%s\n' "$out_a" | grep -q 'FAIL: case2:'; then
  echo "NC-PASS: mutation (a) reddened case 2 (env pin restored) as required"
  nc_a=1
else
  echo "NC-FAIL: mutation (a) did NOT redden case 2 (rc=$rc_a) — the suite's central assertion does not bite" >&2
fi
rm -rf "$SCRATCH/scripts/leadv2-router.sh"

# ── mutation (b): kill switch advisory (pool filter + re-check both dropped) ─
echo "--- NC-b: mutation = kill switch advisory ---"
count_or_die "if c['arm'] and c['arm'] not in kill:" "$SRC"
count_or_die 'if [[ "$(_think_cap_unavailable "$arm")" == "true" ]]; then' "$SRC"
refuse_if_tracked "$SCRATCH/scripts/leadv2-router.sh"
# b1: pool builder stops filtering kill-switched arms
sed "s/if c\['arm'\] and c\['arm'\] not in kill:/if c['arm']:/" \
  "$SRC" > "$SCRATCH/scripts/leadv2-router.sh" || { echo "NC-SETUP-FAIL: sed (b1) failed" >&2; exit 2; }
if cmp -s "$SRC" "$SCRATCH/scripts/leadv2-router.sh"; then
  echo "NC-SETUP-FAIL: mutation (b1) did not apply" >&2
  exit 2
fi
# b2: post-verdict re-check disabled (python patcher — the line's nested quotes
# defeat a readable sed; same count==1 discipline as nc-claude-profile-select NC2)
python3 - "$SCRATCH/scripts/leadv2-router.sh" <<'PY' || { echo "NC-SETUP-FAIL: mutation (b2) did not apply" >&2; exit 2; }
import sys
path = sys.argv[1]
old = '    if [[ "$(_think_cap_unavailable "$arm")" == "true" ]]; then\n'
new = '    if false; then\n'
text = open(path).read()
if text.count(old) != 1:
    sys.stderr.write("NC-SETUP-FAIL: re-check line not found exactly once (count=%d)\n" % text.count(old))
    sys.exit(2)
open(path, "w").write(text.replace(old, new, 1))
PY
if cmp -s "$SRC" "$SCRATCH/scripts/leadv2-router.sh"; then
  echo "NC-SETUP-FAIL: mutation (b) left the source unchanged" >&2
  exit 2
fi
out_b="$(LEADV2_TEST_ROUTER="$SCRATCH/scripts/leadv2-router.sh" bash "$SUITE" 2>&1)"; rc_b=$?
printf '%s\n' "$out_b" | grep -E '^(FAIL|SUMMARY)' || true
nc_b=0
if [[ "$rc_b" -ne 0 ]] && printf '%s\n' "$out_b" | grep -q 'FAIL: case5a:'; then
  echo "NC-PASS: mutation (b) reddened case 5a (kill switch advisory) as required"
  nc_b=1
else
  echo "NC-FAIL: mutation (b) did NOT redden case 5a (rc=$rc_b) — the kill-switch assertion does not bite" >&2
fi

if [[ "$nc_a" -eq 1 && "$nc_b" -eq 1 ]]; then
  echo "NC OVERALL PASS: both mutations went red on their named case"
  exit 0
fi
exit 1
