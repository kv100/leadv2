#!/usr/bin/env bash
# tests/test-ephemeral-state-basename-collision.sh -- EPHEMERAL-BASENAME-COLLISION-01
# run-all-triggers: leadv2-state-path leadv2-dispatch-code
#
# THE DEFECT this guards (measured 2026-09-12): leadv2-state-path.sh keyed the
# scratch-repo control plane on the repo BASENAME, so every mktemp fixture
# named repo-g -- and many are -- wrote ONE shared registry
# (<base>/.ephemeral/repo-g/active.yaml) regardless of path. That directory
# held 15 dead rows, 16 of them under task_id=dispatch-f5117370 (dispatch sigs
# derive from the task description, so they are stable across runs), all
# written before rows carried a `writes` field; the dispatch writeset
# admission/proof then read one of them and refused BEFORE routing, so
# test-route-arbiter.sh case (g) had been failing for two days on residue
# rather than on the arbiter (29/3 -> 31/1 by moving the directory aside, no
# code change). Tell-tale of this class: the refusal's registry= line carries
# worktree= naming a DIFFERENT tmp dir than the run being watched.
#
# THE FIX under test: scratch roots (no remote, no REAL-REPO marker) are keyed
# basename + 8-hex digest of the FULL repo path, under whatever base is in
# effect -- including a sandboxed LEADV2_STATE_BASE, so THIS suite can prove
# same-basename isolation without ever writing the live
# ~/.claude/leadv2-state tree (suites must never write there: that rule is the
# reason this row exists). Real checkouts keep ${STATE_BASE}/${REPO_SLUG}.
# Legacy bare-basename roots follow their checkout only when their own
# provenance marker names that exact repo path (adoption); foreign residue is
# never adopted and stays dead for leadv2-state-purge.sh.
#
# Hermetic: LEADV2_STATE_BASE is exported to a throwaway dir BEFORE any
# dispatch (also what test-fixture-state-leak-guard.sh's static detector
# requires), the default-base shape is probed under a fake HOME, and the last
# case asserts no fixture-named root appeared in the LIVE tree.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/.."
STATE_PATH_SH="${SCRIPTS_DIR}/leadv2-state-path.sh"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
ROUTING_YAML="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
LIVE_EPH="${HOME}/.claude/leadv2-state/.ephemeral"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/eph-coll.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
BASE="${WORK}/state-base"; mkdir -p "${BASE}"
export LEADV2_STATE_BASE="${BASE}"
unset LEADV2_STATE_ROOT

bash -n "${STATE_PATH_SH}" || { echo "ERROR: bash -n failed for ${STATE_PATH_SH}"; exit 1; }
bash -n "${DISPATCH_SH}"  || { echo "ERROR: bash -n failed for ${DISPATCH_SH}"; exit 1; }

# A and B are two DIFFERENT scratch checkouts that share only their basename.
A="${WORK}/one/repo-collide"
B="${WORK}/two/repo-collide"
mkdir -p "${WORK}/one" "${WORK}/two"
for R in "$A" "$B"; do
  mkdir -p "${R}/.claude/ref" "${R}/docs/leadv2"
  git -C "${R}" init -q -b main
  git -C "${R}" config user.email t@t; git -C "${R}" config user.name t
  touch "${R}/seed"; git -C "${R}" add seed; git -C "${R}" commit -qm seed
  cp "${ROUTING_YAML}" "${R}/.claude/ref/leadv2-routing.yaml"
done
WORKER="${WORK}/worker.sh"
printf '#!/usr/bin/env bash\nprintf "PID=%%s LABEL=t SESSION_ID=t\\n" "$$"\n' > "${WORKER}"; chmod +x "${WORKER}"

resolve() {  # <repo> -> canonical active.yaml path under $BASE (sandbox shape)
  ( cd "$1" && LEADV2_STATE_ROOT= PROJECT_ROOT="$1" \
    bash "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null )
}

run_disp() {  # <dispatch-bin> <repo> <tag> -> full output of one --no-spawn dispatch
  # The description deliberately stays IDENTICAL between fixtures: dispatch
  # derives its stable registry task id from it.  Distinct tags isolate only
  # incidental cache and declared-write paths.  Without this, a mutation back
  # to basename keying still sees different task ids and cannot reproduce the
  # historical writeset_persist_failed refusal.
  ( cd "$2" && \
  CLAUDE_PROJECT_ROOT="$2" LEADV2_PROJECT_ROOT="$2" \
  LEADV2_STATE_BASE="${BASE}" \
  LEADV2_DISPATCH_CACHE_DIR="${WORK}/cache-$3" LEADV2_DISPATCH_E2E_GATE=0 \
  LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
  LEADV2_LANE_SHAPE=off LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 \
  LEADV2_REQUIRE_PHASES=0 LEADV2_DISPATCH_SUBSESSION_BIN="${WORKER}" \
  bash "$1" "same-basename collision probe" --kind product --no-spawn --no-probe-yet \
       --writes "src/shared-$3.py" 2>&1 || true )
}

# ── 1. resolver: same basename, different paths -> different registries ────
a_yaml="$(resolve "$A")"; b_yaml="$(resolve "$B")"; a2_yaml="$(resolve "$A")"
if [[ -n "${a_yaml}" && "${a_yaml}" != "${b_yaml}" ]]; then
  ok "same-basename fixtures resolve to different ephemeral roots (${a_yaml##*/} vs ${b_yaml##*/})"
else
  bad "same-basename fixtures share a root" "a='${a_yaml}' b='${b_yaml}'"
fi
if [[ "${a_yaml}" == "${a2_yaml}" ]]; then
  ok "ephemeral key is stable across invocations (${a_yaml##*/})"
else
  bad "ephemeral key is not stable" "a1='${a_yaml}' a2='${a2_yaml}'"
fi
if [[ "${a_yaml}" == "${BASE}/.ephemeral/"* && "${a_yaml}" != "${BASE}/.ephemeral/repo-collide/"* ]]; then
  ok "scratch root lives under .ephemeral/ and is not the bare basename"
else
  bad "scratch root misplaced" "a='${a_yaml}'"
fi
# Default-base shape (fake HOME, BASE unset) must not diverge from the fix.
FH="${WORK}/fakehome"; mkdir -p "${FH}"
fh_a="$( cd "$A" && HOME="${FH}" LEADV2_STATE_ROOT= LEADV2_STATE_BASE= PROJECT_ROOT="$A" \
  bash "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null )"
fh_b="$( cd "$B" && HOME="${FH}" LEADV2_STATE_ROOT= LEADV2_STATE_BASE= PROJECT_ROOT="$B" \
  bash "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null )"
if [[ -n "${fh_a}" && "${fh_a}" != "${fh_b}" \
   && "${fh_a}" == "${FH}/.claude/leadv2-state/.ephemeral/"* ]]; then
  ok "default-base (unset LEADV2_STATE_BASE) shape is isolated too (${fh_a##*/})"
else
  bad "default-base shape not isolated" "a='${fh_a}' b='${fh_b}'"
fi
# A REAL checkout (git remote present) keeps the top-level basename root.
REAL="${WORK}/real-repo"; mkdir -p "${REAL}"
git -C "${REAL}" init -q -b main; git -C "${REAL}" config user.email t@t; git -C "${REAL}" config user.name t
git -C "${REAL}" remote add origin https://example.com/r.git
r_yaml="$(resolve "$REAL")"
if [[ "${r_yaml}" == "${BASE}/real-repo/active.yaml" ]]; then
  ok "real checkout (remote) keeps the top-level ${BASE}/<slug> root, unchanged"
else
  bad "real checkout root changed" "r='${r_yaml}'"
fi

# ── 2. end-to-end registry isolation on a DIRTY machine ────────────────────
# Pre-seed the exact historical poison: a bare-basename legacy root holding a
# pre-writes-era foreign row (worktree in yet another tmp dir).
LEGACY="${BASE}/.ephemeral/repo-collide"
mkdir -p "${LEGACY}"
printf 'source=%s\ncreated=2026-09-01T00:00:00Z\n' "${WORK}/somewhere-else/repo-collide" > "${LEGACY}/.ephemeral"
cat > "${LEGACY}/active.yaml" <<YAML
meta:
  rendered_at: '2026-09-01T00:00:00Z'
sessions:
- session_id: s-20260901T000000Z-1-1
  task_id: dispatch-f5117370
  worktree: ${WORK}/somewhere-else/repo-collide
  branch: main
  started_at: '2026-09-01T00:00:00Z'
  phase: build
  pulse_log: docs/leadv2/tasks/dispatch-f5117370/pulse.md
  pid: 1
YAML

a_out="$(run_disp "${DISPATCH_SH}" "$A" a)"
a_sig="$(printf '%s\n' "${a_out}" | grep -oE 'task=[0-9a-f]{8}' | head -1 | cut -d= -f2)"
if [[ -n "${a_sig}" ]] && grep -q "dispatch-${a_sig}" "${a_yaml}" 2>/dev/null; then
  ok "fixture A registered its row under its OWN hashed root (dispatch-${a_sig})"
else
  bad "fixture A row not found in its own registry" "sig='${a_sig}' yaml='${a_yaml}' out='$(printf '%s\n' "${a_out}" | tail -1)'"
fi
if python3 - "${a_yaml}" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
rows = [r for r in (doc.get("sessions") or []) if isinstance(r, dict)]
sys.exit(0 if any(str(r.get("writes", "")).startswith("src/") for r in rows) else 1)
PY
then
  ok "fixture A's row carries its declared writes"
else
  bad "fixture A's row lost its writes" "${a_yaml}"
fi

# Strip A's row writes: the pre-field residue shape that blocked real lanes.
python3 - "${a_yaml}" <<'PY'
import sys, yaml
p = sys.argv[1]
doc = yaml.safe_load(open(p)) or {}
for r in (doc.get("sessions") or []):
    if isinstance(r, dict):
        r.pop("writes", None); r.pop("write_set", None)
yaml.safe_dump(doc, open(p, "w"))
PY

b_out="$(run_disp "${DISPATCH_SH}" "$B" b)"
green_held=1
if printf '%s\n' "${b_out}" | grep -qE 'writeset_(pending|overlap|persist_failed|conflict|unknown)'; then
  green_held=0
  bad "fixture B refused on residue it must not be able to see" "$(printf '%s\n' "${b_out}" | grep -m1 'dispatch_refused')"
else
  ok "fixture B (same basename, dirty machine) dispatches with no writeset refusal"
fi
b_sig="$(printf '%s\n' "${b_out}" | grep -oE 'task=[0-9a-f]{8}' | head -1 | cut -d= -f2)"
if [[ -n "${a_sig}" && "${a_sig}" == "${b_sig}" ]]; then
  ok "fixture A and B exercise the same stable dispatch signature (${a_sig})"
else
  green_held=0
  bad "fixture A and B did not exercise the same stable dispatch signature" "a='${a_sig}' b='${b_sig}'"
fi
if [[ -n "${b_sig}" ]] && grep -q "dispatch-${b_sig}" "${b_yaml}" 2>/dev/null; then
  ok "fixture B registered under its OWN hashed root (dispatch-${b_sig})"
else
  green_held=0
  bad "fixture B row not in its own registry" "sig='${b_sig}' yaml='${b_yaml}'"
fi
if [[ -f "${b_yaml}" ]] && grep -q 'src/shared-a.py' "${b_yaml}" 2>/dev/null; then
  green_held=0
  bad "fixture A's row is visible in fixture B's registry" "leak: src/shared-a.py in ${b_yaml}"
else
  ok "fixture A's row is invisible to fixture B"
fi

# ── 3. legacy-root adoption is provenance-gated ────────────────────────────
# The foreign-source legacy root planted above must still be intact and must
# NOT have been adopted into either fixture's registry.
if [[ -f "${LEGACY}/active.yaml" ]] && ! grep -q "dispatch-f5117370" "${a_yaml}" "${b_yaml}" 2>/dev/null; then
  ok "foreign-source legacy root kept, never adopted (residue stays dead)"
else
  bad "foreign legacy root was adopted or destroyed" "${LEGACY}"
fi
# A matching-source legacy root follows its checkout (mid-run code-flip case).
# C uses its own basename so its legacy dir cannot collide with the foreign
# repo-collide root planted above.
C="${WORK}/three/repo-adopt"; mkdir -p "${WORK}/three"
mkdir -p "${C}/.claude/ref" "${C}/docs/leadv2"
git -C "${C}" init -q -b main; git -C "${C}" config user.email t@t; git -C "${C}" config user.name t
touch "${C}/seed"; git -C "${C}" add seed; git -C "${C}" commit -qm seed
c_yaml="$( ( cd "$C" && LEADV2_STATE_ROOT= PROJECT_ROOT="$C" bash "${STATE_PATH_SH}" --no-link active.yaml 2>/dev/null) )"
# The provenance marker must carry the resolver's OWN canonical form of the
# repo path (it resolves through pwd, so /private/var vs /var matters);
# reuse the source= the resolver just wrote into C's hashed root.
c_canon="$(sed -n 's/^source=//p' "${c_yaml%/active.yaml}/.ephemeral" 2>/dev/null | head -1)"
LEG_C="${BASE}/.ephemeral/repo-adopt"; mkdir -p "${LEG_C}"
printf 'source=%s\ncreated=2026-09-01T00:00:00Z\n' "${c_canon}" > "${LEG_C}/.ephemeral"
printf 'sessions: []\n' > "${LEG_C}/active.yaml"
( cd "$C" && LEADV2_STATE_ROOT= PROJECT_ROOT="$C" bash "${STATE_PATH_SH}" --no-link active.yaml >/dev/null 2>&1 )
if [[ -f "${c_yaml}" ]] && grep -q "sessions" "${c_yaml}" && [[ ! -f "${LEG_C}/active.yaml" ]]; then
  ok "matching-source legacy root is adopted into the hashed root"
else
  bad "matching-source legacy root was not adopted" "hashed='${c_yaml}' legacy='${LEG_C}'"
fi

# ── 4. DECLARED NEGATIVE CONTROL (mutated copy, run here, must go RED) ─────
# Mutate a THROWAWAY copy of the resolver back to bare-basename keying and
# prove the shared-registry refusal RETURNS: the green half above proves
# presence, this half proves the suite actually detects the regression.
MUT_ROOT="${WORK}/mutated"; mkdir -p "${MUT_ROOT}"
cp -R "${SCRIPTS_DIR}" "${MUT_ROOT}/scripts"
MUT_RESOLVER="${MUT_ROOT}/scripts/leadv2-state-path.sh"
mut_rc=0
python3 - "${MUT_RESOLVER}" <<'PY' || mut_rc=$?
import sys
p = sys.argv[1]; s = open(p).read()
anchor = 'STATE_ROOT="${STATE_BASE}/.ephemeral/${_eph_key}"'
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- the ephemeral key '
             'construction moved or was renamed; re-anchor this control, do '
             'not silence it' % n)
open(p, 'w').write(s.replace(anchor, 'STATE_ROOT="${STATE_BASE}/.ephemeral/${REPO_SLUG}"'))
PY
if [[ ${mut_rc} -ne 0 ]]; then
  bad "(red) mutation anchor not found -- control cannot be proven" "zero-match"
else
  A2="${WORK}/mut-one/repo-collide"; B2="${WORK}/mut-two/repo-collide"
  mkdir -p "${WORK}/mut-one" "${WORK}/mut-two"
  for R in "$A2" "$B2"; do
    mkdir -p "${R}/.claude/ref" "${R}/docs/leadv2"
    git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
    touch "$R/seed"; git -C "$R" add seed; git -C "$R" commit -qm seed
  done
  mut_a_yaml="$( ( cd "$A2" && LEADV2_STATE_ROOT= PROJECT_ROOT="$A2" bash "${MUT_RESOLVER}" --no-link active.yaml 2>/dev/null) )"
  # A stale registry row is the durable collision shape.  Leave it through
  # fixture A, then ask fixture B for its own active.yaml.  The mutant is red
  # only if B resolves the SAME file and can read A's row -- no dependence on
  # later dispatcher refresh semantics that may legitimately repair `writes`.
  printf 'sessions:\n- task_id: dispatch-f5117370\n  worktree: %s\n' "$A2" > "${mut_a_yaml}"
  mut_b_yaml="$( ( cd "$B2" && LEADV2_STATE_ROOT= PROJECT_ROOT="$B2" bash "${MUT_RESOLVER}" --no-link active.yaml 2>/dev/null) )"
  if [[ "${green_held}" != "1" ]]; then
    bad "(red) control NOT EVALUATED -- the green half did not hold, fix the suite first" "green_held=0"
  elif [[ "${mut_a_yaml}" == "${mut_b_yaml}" ]] && grep -q "worktree: ${A2}" "${mut_b_yaml}" 2>/dev/null; then
    ok "(red) bare-basename keying reproduces the stale-row collision (${mut_b_yaml})"
  else
    bad "(red) mutated resolver did not expose fixture A's row to B" "a='${mut_a_yaml}' b='${mut_b_yaml}'"
  fi
fi

# ── 5. this suite itself never wrote the live state tree ───────────────────
if [[ -e "${LIVE_EPH}/repo-collide" || -e "${LIVE_EPH}/real-repo" ]]; then
  bad "suite wrote a fixture-named root into the LIVE ${LIVE_EPH}" "leak"
else
  ok "no fixture-named root appeared in the live ${LIVE_EPH}"
fi

printf 'ephemeral-basename-collision: %d pass, %d fail\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"; exit 0
else
  echo "SOME FAILED"; exit 1
fi
