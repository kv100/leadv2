#!/usr/bin/env bash
# test-lane-close-loop.sh — LANE-CLOSE-LOOP-01 sandboxed test.
#
# Proves the four behaviours the task's acceptance names, in a fully isolated sandbox:
#   (a) a lane that committed + wrote its deliverable        -> terminal landed/reconciled
#   (b) a lane that committed but wrote NO deliverable       -> terminal landed/no_deliverable + WARN
#   (c) a lane that wrote nothing and died                   -> terminal dead/worker_died
#   (d) reconcile is idempotent                              -> a second run adds no further rows
#
# Sandboxing: a temp git repo is the evidence repo; the reservation + terminal ledgers
# both point at mktemp dirs (LEADV2_DISPATCH_RESERVATION_LEDGER_FILE +
# LEADV2_DISPATCH_TERMINAL_LEDGER_FILE + CACHE_BASE). A fake lane-liveness stub
# (LEADV2_DISPATCH_LANE_LIVENESS_BIN) returns deterministic verdicts so the test never
# touches a real ~/.claude or a real active.yaml. Asserts ~/.claude/leadv2-state mtime is
# unchanged. Exits 0 and prints a passing summary; run it twice.
# Guard against mktemp -t without XXX in template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../lib/mktemp-guard.sh"
if [ ! -f "$GUARD_SCRIPT" ]; then
    GUARD_SCRIPT="$SCRIPT_DIR/../../../plugins/leadv2/scripts/lib/mktemp-guard.sh"
fi
if [ -f "$GUARD_SCRIPT" ]; then
    source "$GUARD_SCRIPT"
else
    echo "Error: mktemp-guard.sh not found" >&2
    exit 1
fi
mktemp_guard
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER_BIN="${SCRIPT_DIR}/../leadv2-dispatch-ledger.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

if [[ ! -f "${LEDGER_BIN}" ]]; then
  printf 'FATAL: ledger bin not found at %s\n' "${LEDGER_BIN}" >&2
  exit 1
fi

# ── sandbox ───────────────────────────────────────────────────────────────────────
BOX="$(mktemp -d "${TMPDIR:-/tmp}/tmp.XXXXXXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/lcl.XXXXXX" 2>/dev/null)" || {
    echo "Failed to create temporary directory" >&2
    exit 1
}
trap 'rm -rf "${BOX}" 2>/dev/null' EXIT

EVIDENCE_REPO="${BOX}/repo"
DISPATCH_ROOT="${BOX}/dispatch"        # stands in for the dispatch repo (PROJECT_ROOT)
mkdir -p "${EVIDENCE_REPO}" "${DISPATCH_ROOT}"

# reservation ledger (dispatch-code.sh shape) + terminal ledger, both in the sandbox
RES_FILE="${BOX}/reservation.jsonl"
TERM_FILE="${BOX}/terminal.jsonl"
export LEADV2_DISPATCH_RESERVATION_LEDGER_FILE="${RES_FILE}"
export LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${TERM_FILE}"
export CACHE_BASE="${BOX}/cache"
mkdir -p "${CACHE_BASE}"

REAL_STATE="${HOME}/.claude/leadv2-state"   # used only for the containment check below

# fake lane-liveness: supports BOTH the per-lane --lane path and the batched --all --json
# path production uses, so the test exercises the real code path (map build + lookup), not
# just the per-lane fallback. Every lane verdicts dead:provider_failed (old/finished) --
# lanes A and B never reach liveness (they have commit evidence); lane C does, -> dead.
FAKE_LIVENESS="${BOX}/fake-lane-liveness.sh"
cat > "${FAKE_LIVENESS}" <<'SH'
#!/usr/bin/env bash
lane=""; all=0; json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane) lane="${2:-}"; shift 2 ;;
    --all)  all=1; shift ;;
    --json) json=1; shift ;;
    *) shift ;;
  esac
done
if [[ ${all} -eq 1 ]]; then
  if [[ ${json} -eq 1 ]]; then
    printf '{"lanes":[{"lane":"dispatch-aaaaaaaa","verdict":"dead:provider_failed"},{"lane":"dispatch-bbbbbbbb","verdict":"dead:provider_failed"},{"lane":"dispatch-deadbeef","verdict":"dead:provider_failed"}],"availability":"authoritative"}'
  else
    printf 'dispatch-aaaaaaaa dead:provider_failed\ndispatch-bbbbbbbb dead:provider_failed\ndispatch-deadbeef dead:provider_failed\n'
  fi
  exit 0
fi
# Per-lane fallback is deliberately EMPTY so the test PROVES the batched-map path works:
# lane C's dead:worker_died verdict can ONLY arrive via the --all map, never a per-lane
# spawn. If the map lookup is broken, lane C verdicts "" -> unknown (no stamp) and the
# (c) assertion fails.
:
SH
chmod +x "${FAKE_LIVENESS}"
export LEADV2_DISPATCH_LANE_LIVENESS_BIN="${FAKE_LIVENESS}"

# stub out journal so the writer does not shell out to a real journal
export LEADV2_JOURNAL_BIN="${BOX}/no-journal"
printf '#!/usr/bin/env bash\nexit 0\n' > "${LEADV2_JOURNAL_BIN}"; chmod +x "${LEADV2_JOURNAL_BIN}"

# ── evidence repo: a real git history ─────────────────────────────────────────────
git -C "${EVIDENCE_REPO}" init -q
git -C "${EVIDENCE_REPO}" config user.email t@t.t
git -C "${EVIDENCE_REPO}" config user.name t
# an old base commit BEFORE any lane spawned (lands outside every lane's window)
printf 'base\n' > "${EVIDENCE_REPO}/base.txt"
git -C "${EVIDENCE_REPO}" add base.txt
BASE_EPOCH=$(( $(date +%s) - 100000 ))
GIT_AUTHOR_DATE="@${BASE_EPOCH}" GIT_COMMITTER_DATE="@${BASE_EPOCH}" \
  git -C "${EVIDENCE_REPO}" commit -q -m base

# spawn epochs: a few seconds after base, well in the past
SPAWN_A=$(( BASE_EPOCH + 10 ))
SPAWN_B=$(( BASE_EPOCH + 20 ))
SPAWN_C=$(( BASE_EPOCH + 30 ))
NOW=$(( BASE_EPOCH + 90000 ))

# ── build the reservation ledger rows (dispatch-code.sh confirmed-row shape) ──────
# full sig -> first 8 chars is the sig8 the terminal ledger keys on. We pick sig8s that
# also encode intent for readability.
write_reservation_row() {  # <full_sig> <lane_label> <created_epoch> <mission_path>
  printf '{"task_sig":"%s","arm":"glm","rule":"r","repo":"dispatch","ts":"2026-01-01T00:00:00Z","token":"tok-%s","state":"confirmed","created_epoch":%s,"task_id":"%s","mission_path":"%s","lane_label":"%s","handle":"h-%s"}\n' \
    "$1" "$2" "$3" "$2" "$4" "$2" "$2" >> "${RES_FILE}"
}

MISSION_A="${BOX}/mission-a.md"
MISSION_B="${BOX}/mission-b.md"
MISSION_C="${BOX}/mission-c.md"
: > "${MISSION_A}"; : > "${MISSION_B}"; : > "${MISSION_C}"

# lane A: full sig starting aaaaaaaa..., lane LANDED-WITH-DELIVERABLE
write_reservation_row "aaaaaaaa11111111deadbeefcafebabe12345678" "LANDED-WITH-DELIVERABLE" "${SPAWN_A}" "${MISSION_A}"
# lane B: committed, no deliverable
write_reservation_row "bbbbbbbb22222222deadbeefcafebabe12345678" "LANDED-NO-DELIVERABLE"   "${SPAWN_B}" "${MISSION_B}"
# lane C: wrote nothing, died
write_reservation_row "deadbeef01111111deadbeefcafebabe12345678" "DIED-NO-WORK"            "${SPAWN_C}" "${MISSION_C}"

# ── commit evidence in the lanes' write-sets, timestamped inside their windows ─────
mkdir -p "${EVIDENCE_REPO}/src"
# lane A: commits src/a.txt AND the deliverable exists
printf 'a\n' > "${EVIDENCE_REPO}/src/a.txt"
git -C "${EVIDENCE_REPO}" add src/a.txt
GIT_AUTHOR_DATE="@${SPAWN_A}" GIT_COMMITTER_DATE="@${SPAWN_A}" \
  git -C "${EVIDENCE_REPO}" commit -q -m "lane A work"
SHA_A="$(git -C "${EVIDENCE_REPO}" rev-parse HEAD)"

# lane B: commits src/b.txt, but NO deliverable file anywhere
printf 'b\n' > "${EVIDENCE_REPO}/src/b.txt"
git -C "${EVIDENCE_REPO}" add src/b.txt
GIT_AUTHOR_DATE="@${SPAWN_B}" GIT_COMMITTER_DATE="@${SPAWN_B}" \
  git -C "${EVIDENCE_REPO}" commit -q -m "lane B work"
SHA_B="$(git -C "${EVIDENCE_REPO}" rev-parse HEAD)"

# lane C: writes nothing (no commit). With the fake liveness verdicting every lane
# dead:provider_failed, lane C reaches liveness (no commit) -> dead -> dead:worker_died,
# which is what the acceptance's case (c) names.

# deliverable for lane A: a non-empty scratchpad file at a path the mission declares
DELIV_A="${BOX}/scratchpad/A.md"
mkdir -p "${BOX}/scratchpad"
printf '# A deliverable\nreal content\n' > "${DELIV_A}"
printf 'Deliverable\n%s\n' "${DELIV_A}" > "${MISSION_A}"
# lane B's mission declares a deliverable path that we deliberately do NOT create
printf 'Deliverable\n%s/scratchpad/B.md\n' "${BOX}" > "${MISSION_B}"

# the architect prepass artifact (carries the scoped LANE_WRITES line) for A and B under
# the dispatch repo's docs/handoff/dispatch-<sig8>/
mk_prepass() {  # <sig8> <writes>
  local d="${DISPATCH_ROOT}/docs/handoff/dispatch-$1"
  mkdir -p "${d}"
  printf 'SCOPED DESIGN\nLANE_WRITES: %s\n' "$2" > "${d}/architect-prepass.md"
}
mk_prepass "aaaaaaaa" "src/a.txt"
mk_prepass "bbbbbbbb" "src/b.txt"
mk_prepass "deadbeef" "src/c.txt"

# ── RUN 1 ─────────────────────────────────────────────────────────────────────────
section "RUN 1"
OUT1="$(PROJECT_ROOT="${DISPATCH_ROOT}" bash "${LEDGER_BIN}" reconcile --repo "${EVIDENCE_REPO}" 2>"${BOX}/err1")"
RC1=$?
printf '%s\n' "${OUT1}"
printf 'stderr:\n%s\n' "$(cat "${BOX}/err1")"

section "assert RUN 1"
# (a) landed with deliverable present
if printf '%s\n' "${OUT1}" | grep -q 'LANDED-WITH-DELIVERABLE .* landed:reconciled' \
   && grep -q '"deliverable":"present"' <<<"$(cat "${TERM_FILE}")" 2>/dev/null; then
  ok "(a) landed+deliverable -> landed:reconciled, deliverable=present"
else bad "(a) lane A did not land with deliverable"; fi

# (b) landed but no deliverable, AND a WARN naming the lane + commit
if printf '%s\n%s\n' "${OUT1}" "$(cat "${BOX}/err1")" | grep -q 'WARN: lane LANDED-NO-DELIVERABLE .* committed .* NO deliverable' \
   && grep -q '"cause":"no_deliverable"' "${TERM_FILE}"; then
  ok "(b) landed-no-deliverable -> landed:no_deliverable + WARN"
else bad "(b) lane B warn/no_deliverable missing"; fi

# (c) died -> dead/worker_died
if printf '%s\n' "${OUT1}" | grep -q 'DIED-NO-WORK .* dead:worker_died' \
   && grep -q '"terminal":"dead"' "${TERM_FILE}"; then
  ok "(c) no-work-death -> dead:worker_died"
else bad "(c) lane C did not become dead"; fi

# row shape: the new keys commit + deliverable are present on at least one row
if grep -q '"commit":' "${TERM_FILE}" && grep -q '"deliverable":' "${TERM_FILE}"; then
  ok "row carries commit + deliverable fields"
else bad "row missing commit/deliverable fields"; fi

# write-once / idempotence prep: count rows after run 1
ROWS_AFTER_RUN1="$(grep -c '' "${TERM_FILE}" 2>/dev/null || printf 0)"

# ── RUN 2 (idempotence) ───────────────────────────────────────────────────────────
section "RUN 2 (idempotence)"
OUT2="$(PROJECT_ROOT="${DISPATCH_ROOT}" bash "${LEDGER_BIN}" reconcile --repo "${EVIDENCE_REPO}" 2>"${BOX}/err2")"
RC2=$?
printf '%s\n' "${OUT2}"
ROWS_AFTER_RUN2="$(grep -c '' "${TERM_FILE}" 2>/dev/null || printf 0)"
printf 'rows run1=%s run2=%s\n' "${ROWS_AFTER_RUN1}" "${ROWS_AFTER_RUN2}"
if [[ "${ROWS_AFTER_RUN1}" == "${ROWS_AFTER_RUN2}" && "${ROWS_AFTER_RUN1}" -ge 3 ]]; then
  ok "(d) second run added no further rows (${ROWS_AFTER_RUN2} total)"
else bad "(d) idempotence broken: ${ROWS_AFTER_RUN1} -> ${ROWS_AFTER_RUN2}"; fi

# run 2 must show all lanes as recorded/existing, no new WARN
if ! grep -q 'WARN:' "${BOX}/err2"; then
  ok "run 2 emitted no new WARN"
else bad "run 2 emitted a spurious WARN"; fi

# ── sweep/exists readers still behave on an extended row ──────────────────────────
section "readers on extended row"
if PROJECT_ROOT="${DISPATCH_ROOT}" bash "${LEDGER_BIN}" exists aaaaaaaa >/dev/null 2>&1; then
  ok "exists <landed sig8> -> rc0 (TRUE terminal)"
else bad "exists mis-reported a landed lane"; fi
if ! PROJECT_ROOT="${DISPATCH_ROOT}" bash "${LEDGER_BIN}" exists zzzzzzzz >/dev/null 2>&1; then
  ok "exists <unseen sig8> -> rc1"
else bad "exists falsely reported an unseen sig8"; fi

# ── no real-state writes ──────────────────────────────────────────────────────────
# Deterministic invariant (NOT an mtime race against the live system, which also writes
# to this dir): assert NONE of the test's sandbox sig8s landed in the REAL terminal ledger.
# That directly proves the test wrote only to its sandbox TERM_FILE.
section "sandbox containment"
REAL_TERM=""
[[ -d "${REAL_STATE}" ]] && REAL_TERM="$(PROJECT_ROOT="${DISPATCH_ROOT}" bash "${SCRIPT_DIR}/../leadv2-state-path.sh" --no-link dispatch-ledger.jsonl 2>/dev/null || true)"
leak=""
if [[ -n "${REAL_TERM}" && -f "${REAL_TERM}" ]]; then
  for s in aaaaaaaa bbbbbbbb deadbeef; do
    if grep -qF "\"task_sig\":\"${s}\"" "${REAL_TERM}" 2>/dev/null; then leak+="${s} "; fi
  done
fi
if [[ -z "${leak}" ]]; then
  ok "no test sig8 leaked into the real terminal ledger"
else bad "test sig8 leaked into real ledger: ${leak}"; fi

# ── summary ───────────────────────────────────────────────────────────────────────
printf '\n========================================\n'
printf 'LANE-CLOSE-LOOP-01 test: pass=%d fail=%d\n' "${pass}" "${fail}"
if [[ ${fail} -eq 0 ]]; then
  printf 'ALL GREEN\n'
  exit 0
else
  printf 'FAILURES PRESENT\n'
  exit 1
fi
