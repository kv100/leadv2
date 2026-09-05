#!/usr/bin/env bash
# test-phase-policy-document.sh — ROUTING-YAML-HAS-TWO-READERS-AND-TWO-FILES-01.
#
# run-all-triggers: leadv2-phase-policy-path leadv2-router leadv2-glm-policy-resolve leadv2-router-v2 codex-task leadv2-cost-estimate
#
# WHAT IS REAL HERE: the production `leadv2_phase_policy_path` is sourced and
# called, and the production `leadv2-glm-policy-resolve.py` is executed. Only the
# filesystem below them is a fixture (throwaway repo roots holding real copies of
# the two real documents). Nothing that the assertions are about is stubbed.
#
# THE INVARIANT, stated so it survives the next config change: a reader of the
# PHASE POLICY (phases / stop_rules / floor_rules / phases.glm_policy) must never
# be handed the ROUTER REGISTRY (router_v2 / router.dispatch_ladder) merely
# because the two once shared a filename -- and when it cannot find its document
# it must SAY SO, never substitute a default in silence.
#
# DECLARED NEGATIVE CONTROL (case R below, runs in-suite on every CI selection):
#   inside leadv2_phase_policy_path's old-name branch, replace the document-shape
#   test `_lv2_is_phase_policy_doc "${_old}"` with a bare readability test
#   `[[ -r "${_old}" ]]` -- i.e. the pre-fix behaviour of accepting whatever sits
#   at the legacy filename. Applied by regex INSIDE the function body, never by
#   line number. Case (b) must then go red. If the green half did not hold, the
#   control reports NOT EVALUATED and FAILS: absence proves nothing unless
#   presence was shown first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
LIB="${SCRIPTS}/lib/leadv2-phase-policy-path.sh"
RESOLVER="${SCRIPTS}/lib/leadv2-glm-policy-resolve.py"
REGISTRY="${SCRIPTS}/../config/leadv2-routing.yaml"

PASS=0; FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL %s\n     want: %s\n     got:  %s\n' "$1" "${2:-}" "${3:-}" >&2; FAIL=$((FAIL+1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/pp-doc.XXXXXX")" || exit 1
trap 'rm -rf "${T}"' EXIT

# ── fixtures: one root per shape, holding REAL documents ──────────────────────
mk_root() { mkdir -p "${T}/$1/.claude/ref"; printf '%s/%s' "${T}" "$1"; }

# Document B, minimal but real in shape: the keys the four readers ask for.
write_doc_b() {
  cat >"$1" <<'YAML'
phases:
  build:
    multi_file:
      model: glm
  glm_policy:
    policy_id: FIXTURE-01
    codex_default_tier: volume
    codex_quota_gate:
      build_threshold_pct: 80
      review_threshold_pct: 95
stop_rules:
  max_cost_usd: 1.0
floor_rules:
  min_arm: glm
YAML
}

R_OLD="$(mk_root old)";   write_doc_b "${R_OLD}/.claude/ref/leadv2-routing.yaml"
R_NEW="$(mk_root new)";   write_doc_b "${R_NEW}/.claude/ref/leadv2-phase-policy.yaml"
R_REG="$(mk_root reg)";   cp "${REGISTRY}" "${R_REG}/.claude/ref/leadv2-routing.yaml"
R_NONE="$(mk_root none)"
R_BOTH="$(mk_root both)"; write_doc_b "${R_BOTH}/.claude/ref/leadv2-phase-policy.yaml"
                          cp "${REGISTRY}" "${R_BOTH}/.claude/ref/leadv2-routing.yaml"

# ── the runner: a fresh bash per case, so the resolver's once-per-process warn
#    guard cannot make a later case look silent ─────────────────────────────────
resolve() {  # <lib> <root> -> "rc|path|stderr"
  bash -c '
    set -uo pipefail
    source "$1" || exit 9
    out="$(leadv2_phase_policy_path "$2" 2>"$3")"; rc=$?
    printf "%d|%s|%s" "$rc" "$out" "$(tr "\n" " " <"$3")"
  ' _ "$1" "$2" "${T}/err" 2>/dev/null
}

run_cases() {  # <lib-under-test> <label-prefix>  -> sets CASE_B_GREEN
  local L="$1" P="$2" r
  CASE_B_GREEN=0

  r="$(resolve "$L" "${R_OLD}")"
  if [[ "${r%%|*}" == "0" && "$r" == *"/leadv2-routing.yaml|"* && "$r" == *"DEPRECATED NAME"* ]]; then
    ok "${P}(a) legacy name holding document B is read, and says it is deprecated"
  else
    bad "${P}(a) legacy name holding document B" "rc=0, old path, DEPRECATED NAME" "$r"
  fi

  # (b) is the one the negative control removes.
  r="$(resolve "$L" "${R_REG}")"
  if [[ "${r%%|*}" == "1" && "$r" != *"leadv2-routing.yaml|"* && "$r" == *"NOT the phase-policy document"* ]]; then
    ok "${P}(b) legacy name holding the REGISTRY is refused, loudly, not returned"
    CASE_B_GREEN=1
  else
    bad "${P}(b) legacy name holding the registry" "rc=1, empty path, 'NOT the phase-policy document'" "$r"
  fi

  r="$(resolve "$L" "${R_NEW}")"
  if [[ "${r%%|*}" == "0" && "$r" == *"/leadv2-phase-policy.yaml|"* && "$r" != *"DEPRECATED"* ]]; then
    ok "${P}(c) current name is read with no deprecation noise"
  else
    bad "${P}(c) current name" "rc=0, new path, no warning" "$r"
  fi

  r="$(resolve "$L" "${R_BOTH}")"
  if [[ "${r%%|*}" == "0" && "$r" == *"/leadv2-phase-policy.yaml|"* ]]; then
    ok "${P}(d) with both present the current name wins"
  else
    bad "${P}(d) both present" "rc=0, new path" "$r"
  fi

  r="$(resolve "$L" "${R_NONE}")"
  if [[ "${r%%|*}" == "1" && "$r" == *"NOT FOUND"* ]]; then
    ok "${P}(e) neither present: rc=1 and a message, never a silent default"
  else
    bad "${P}(e) neither present" "rc=1 with NOT FOUND" "$r"
  fi
}

echo "== leadv2_phase_policy_path (production lib) =="
run_cases "${LIB}" ""
GREEN_HELD="${CASE_B_GREEN}"

# ── the reader that made the rename dangerous ────────────────────────────────
# The glm_policy block is a phase-policy key; the resolver's own candidate search
# only knows registry locations. Measured 2026-09-05: without --phase-policy-yaml
# the rename moved a live answer from tier=volume to tier=standard.
echo "== leadv2-glm-policy-resolve.py, real process =="
tier_of() {  # <routing-yaml> [<phase-policy-yaml>]
  local -a a=(--routing-yaml "$1" --job review --base-arm codex --signals '{}')
  [[ -n "${2:-}" ]] && a+=(--phase-policy-yaml "$2")
  python3 "${RESOLVER}" "${a[@]}" 2>/dev/null | sed -n 's/^tier=//p' | head -1
}
T_BEFORE="$(tier_of "${R_OLD}/.claude/ref/leadv2-routing.yaml")"
T_AFTER="$(tier_of "${R_NEW}/.claude/ref/leadv2-phase-policy.yaml" "${R_NEW}/.claude/ref/leadv2-phase-policy.yaml")"
T_SPLIT="$(tier_of "${REGISTRY}" "${R_NEW}/.claude/ref/leadv2-phase-policy.yaml")"
if [[ -n "${T_BEFORE}" && "${T_BEFORE}" == "${T_AFTER}" ]]; then
  ok "(f) the tier survives the rename (${T_BEFORE})"
else
  bad "(f) tier across the rename" "same non-empty tier" "before=${T_BEFORE} after=${T_AFTER}"
fi
if [[ "${T_SPLIT}" == "${T_BEFORE}" ]]; then
  ok "(g) with the two documents in two files the phase policy still supplies the tier (${T_SPLIT})"
else
  bad "(g) split documents" "tier=${T_BEFORE}" "tier=${T_SPLIT}"
fi

# ── negative control ─────────────────────────────────────────────────────────
echo "== (R) negative control: drop the document-shape test =="
MUT="${T}/mutated-lib.sh"
python3 - "${LIB}" "${MUT}" <<'PY'
import io, re, sys
src, dst = sys.argv[1], sys.argv[2]
body = io.open(src, encoding="utf-8").read()
# Anchor inside leadv2_phase_policy_path's old-name branch, by text, not by line.
old = '  if _lv2_is_phase_policy_doc "${_old}"; then'
n = body.count(old)
if n != 1:
    sys.exit("MUTATION ANCHOR AMBIGUOUS: %d occurrences of the old-name branch test" % n)
io.open(dst, "w", encoding="utf-8").write(body.replace(old, '  if [[ -r "${_old}" ]]; then'))
PY
if [[ $? -ne 0 || ! -s "${MUT}" ]]; then
  bad "(R) mutation could not be applied" "a mutated copy of the lib" "anchor failed"
else
  MUT_OUT="$(resolve "${MUT}" "${R_REG}")"
  if [[ "${GREEN_HELD}" != "1" ]]; then
    bad "(R) control NOT EVALUATED — case (b) did not hold, so the mutation had nothing to remove" \
        "(b) green first" "(b) was red"
  elif [[ "${MUT_OUT%%|*}" == "0" ]]; then
    ok "(R) mutation bites: without the shape test the registry is handed back as the phase policy"
  else
    bad "(R) mutation did NOT bite — case (b) passes for a reason other than the shape test" \
        "rc=0 from the mutated lib" "${MUT_OUT}"
  fi
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
