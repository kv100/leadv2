#!/usr/bin/env bash
# test-route-arbiter-symlink-install.sh — PHASE-DISCIPLINE-01 D7 regression
# fixture for 341b80a (route-arbiter resolves the PHYSICAL path under
# per-file symlink installs; rc=65 fail-open everywhere).
#
# The 341b80a retro-review FAIL: the fix shipped with zero coverage for the
# actual bug — symlink resolution under per-file installs. This fixture
# installs route-arbiter / quota-live / freepool-gate through RELATIVE +
# CHAINED per-file symlinks into a tmp project layout that does NOT mirror
# the canonical tree (no config/ sibling), then asserts:
#   (a) GREEN  — the real arbiter discovers the CANONICAL routing config and
#                the sibling quota-live / freepool-gate through the chain
#                (rc 0, an arm is selected — never rc 65/66).
#   (b) RED    — the same fixture with the physical-path resolution mutated
#                back to the naive logical-path lookup returns rc 65, proving
#                the fixture actually exercises the defect 341b80a fixed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CANONICAL_ARBiter="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING_YAML="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# ── fake canonical tree: arbiter lib (real bytes) + config + stub siblings ──
CT="$TMP/canonical"
mkdir -p "$CT/scripts/lib" "$CT/config"
cp "$CANONICAL_ARBiter" "$CT/scripts/lib/leadv2-route-arbiter.sh"
cp "$ROUTING_YAML" "$CT/config/leadv2-routing.yaml"
cat >"$CT/scripts/leadv2-quota-live.sh" <<'EOF'
#!/usr/bin/env bash
# stub: every provider healthy — the arbiter must pick a real arm.
[[ "${1:-}" == "json" ]] || exit 67
printf '%s\n' '{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":10}]},"anthropic":{"status":"ok","accounts":[{"active":true,"five_hour_pct":10,"seven_day_pct":10}]}}'
EOF
cat >"$CT/scripts/lib/leadv2-freepool-gate.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "check" ]] && exit 0
exit 0
EOF
chmod +x "$CT/scripts/leadv2-quota-live.sh" "$CT/scripts/lib/leadv2-freepool-gate.sh"

# ── per-file symlink install into a foreign project layout ──────────────────
# Relative AND chained: the visible path is a link to a second link that only
# then points at the physical file — the exact install shape whose logical
# lookup used to miss the canonical config (rc=65 fail-open).
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude/scripts/lib"
# link targets resolve relative to the link's OWN directory:
#   proj/<x>-link-1 sits in proj/ (sibling of canonical/ under $TMP);
#   proj/.claude/scripts[/lib]/<name> reaches proj/ via ../../..[/.].
ln -s ../canonical/scripts/lib/leadv2-route-arbiter.sh "$PROJ/arb-link-1"
ln -s ../../../arb-link-1       "$PROJ/.claude/scripts/lib/leadv2-route-arbiter.sh"
ln -s ../canonical/scripts/leadv2-quota-live.sh "$PROJ/ql-link-1"
ln -s ../../../ql-link-1        "$PROJ/.claude/scripts/leadv2-quota-live.sh"
ln -s ../canonical/scripts/lib/leadv2-freepool-gate.sh "$PROJ/fg-link-1"
ln -s ../../../fg-link-1        "$PROJ/.claude/scripts/lib/leadv2-freepool-gate.sh"

# No LEADV2_ROUTE_ARBITER_ROUTING_YAML / QUOTA_LIVE / FREEPOOL_GATE overrides:
# discovery must go through the symlink chain to the canonical tmp tree.
run_arbiter() { # <path-to-lib> -> stdout line, rc
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
    bash -c 'source "$1"; route_arbiter worker "{\"kind\":\"code\",\"size\":\"light\"}"' \
    _ "$1" 2>/dev/null
}

# (a) GREEN — real resolution: canonical config found through the chain.
out="$(run_arbiter "$PROJ/.claude/scripts/lib/leadv2-route-arbiter.sh")"; rc=$?
if [[ $rc -eq 0 && "$out" == *'arm='* ]]; then
  pass "physical-path resolution selects an arm through chained symlinks (out: ${out:0:60}...)"
else
  fail "expected rc=0 arm=..., got rc=$rc out=$out"
fi
if [[ $rc -ne 65 ]]; then
  pass "canonical config discovery: rc != 65 under per-file symlink install"
else
  fail "rc=65 (fail-open) — symlink resolution regressed"
fi

# (b) RED — mutate the resolution back to the naive logical-path lookup and
# prove the fixture catches it (rc 65 = config not found = the 341b80a bug).
sed -e 's|^  local source="${BASH_SOURCE\[0\]}" link dir$|  local source="${BASH_SOURCE[0]}" link dir|' \
    -e 's|^  while \[\[ -h "\$source" \]\]; do$|  while false; do|' \
    "$CT/scripts/lib/leadv2-route-arbiter.sh" >"$CT/scripts/lib/leadv2-route-arbiter.mutated.sh"
if cmp -s "$CT/scripts/lib/leadv2-route-arbiter.sh" "$CT/scripts/lib/leadv2-route-arbiter.mutated.sh"; then
  fail "mutation did not apply — fixture cannot prove its own teeth"
else
  # Install the mutated resolution at the SAME physical inode the chain points to.
  mv "$CT/scripts/lib/leadv2-route-arbiter.sh" "$CT/scripts/lib/leadv2-route-arbiter.real.sh"
  mv "$CT/scripts/lib/leadv2-route-arbiter.mutated.sh" "$CT/scripts/lib/leadv2-route-arbiter.sh"
  out="$(run_arbiter "$PROJ/.claude/scripts/lib/leadv2-route-arbiter.sh")"; rc=$?
  if [[ $rc -eq 65 ]]; then
    pass "logical-path mutation goes red (rc=65) — fixture has teeth"
  else
    fail "mutation should reproduce rc=65, got rc=$rc out=$out"
  fi
fi

printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
