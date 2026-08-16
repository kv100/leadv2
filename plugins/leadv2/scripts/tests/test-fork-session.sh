#!/usr/bin/env bash
# FORK-RUNS-A-SESSION-01 — falsifying harness for leadv2-fork-session.sh.
# Covers (design §3 + fix-round-1): preflight idempotency; preflight REFUSES
# when isolation is off (kill-switch) or unavailable (ensure fallback — no
# shared root on stdout, no registry row); fork-lane.env contents; ask
# exit 3 on pending / exit 0 + label on answered (via the REAL
# leadv2-answer.sh, same surface `/leadv2 reply` uses); ask RETRY reuses the
# pending question (one questions/ file after N retries, empty stdout on
# exit 3, answered-record race, different-question refusal + --cancel-pending);
# commit lands on worktree-<id> in the lane with the main checkout untouched;
# postflight refuses a dirty lane and leaves it on disk; every op
# no-op-safe on re-run.
# Untouched-by-design invariant: leadv2-ask.sh / leadv2-answer.sh /
# leadv2-lane-worktree.sh are invoked, never reimplemented.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FS="${SCRIPT_DIR}/leadv2-fork-session.sh"
ANSWER="${SCRIPT_DIR}/leadv2-answer.sh"
PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

setup_sandbox() { # -> echoes sandbox root; cwd stays put
  local d
  d="$(mktemp -d)"
  mkdir -p "${d}/repo"
  ( cd "${d}/repo" && git init -q -b main && git config user.email t@e.com \
    && git config user.name t && printf 'seed\n' > seed.txt && git add seed.txt \
    && git commit -qm seed ) >/dev/null 2>&1
  mkdir -p "${d}/state"
  printf '%s\n' "$d"
}

# ---- Case 1: preflight creates lane + env, idempotent ----------------------
case_preflight() {
  local d root lane1 lane2 envf
  d="$(setup_sandbox)"; root="${d}/repo"
  lane1="$(cd "$root" && LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state" \
    bash "$FS" preflight tid-fork01 2>/dev/null)"
  if [[ -d "$lane1" && "$lane1" == "${root}/.claude/worktrees/tid-fork01" ]]; then
    ok "preflight prints the lane root under .claude/worktrees"
  else bad "preflight lane root wrong: ${lane1:-<empty>}"; fi

  envf="${lane1}/docs/handoff/tid-fork01/fork-lane.env"
  if [[ -f "$envf" ]] && grep -q "^TASK_ID=tid-fork01$" "$envf" \
     && grep -q "^LANE_ROOT=${lane1}$" "$envf" \
     && grep -q "^CONTROL_PLANE=${d}/state$" "$envf"; then
    ok "fork-lane.env has TASK_ID/LANE_ROOT/CONTROL_PLANE"
  else bad "fork-lane.env wrong: $(cat "$envf" 2>/dev/null || echo MISSING)"; fi

  # active-registry falls back to <repo>/docs/leadv2/active.yaml when the
  # plugin-resolver path is absent (sandbox has no scripts/leadv2-state-path.sh);
  # production resolves to the control plane. Either location proves the row.
  if grep -q "tid-fork01" "${root}/docs/leadv2/active.yaml" 2>/dev/null; then
    ok "preflight registered the lane in active.yaml"
  else bad "task row missing from active.yaml"; fi

  lane2="$(cd "$root" && LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state" \
    bash "$FS" preflight tid-fork01 2>/dev/null)"
  [[ "$lane1" == "$lane2" ]] && ok "preflight re-run is idempotent (same root)" \
    || bad "preflight re-run moved the lane: ${lane1} != ${lane2}"
  rm -rf "$d"
}

# ---- Case 2: ask — exit 3 while pending; fork question is answerable -------
case_ask() {
  local d root qdir qid out rc
  d="$(setup_sandbox)"; root="${d}/repo"; qdir="${d}/state/questions"
  export LEADV2_STATE_ROOT="${d}/state" LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}"
  export LEADV2_ASK_POLL_INTERVAL=0 LEADV2_FORK_ASK_POLL_SEC=2

  out="$(cd "$root" && bash "$FS" ask tid-fork01 "ship it?" --option "a|yes" --option "b|no" \
    --default-option a --timeout-poll 2 2>/dev/null)"; rc=$?
  [[ $rc -eq 3 ]] && ok "ask exits 3 while founder has not answered" \
    || bad "ask pending should exit 3, got rc=${rc} out=${out}"

  qid="$(ls "$qdir" 2>/dev/null | grep -E '^q-[0-9a-f]+\.yaml$' | head -1)"
  if [[ -n "$qid" ]]; then
    ok "ask wrote the question to the control-plane questions/ dir"
    if python3 -c "import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); sys.exit(0 if d.get('status')=='pending' and d.get('task_id')=='tid-fork01' else 1)" "${qdir}/${qid}" 2>/dev/null; then
      ok "question record is pending, task-tagged (visible via /leadv2 questions)"
    else bad "question record shape wrong"; fi
  else bad "no question file appeared in ${qdir}"; fi

  # Answer via the REAL answer.sh — the same path `/leadv2 reply` takes.
  if ( cd "$root" && bash "$ANSWER" "${qid%.yaml}" a ) >/dev/null 2>&1 \
     && python3 -c "import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); a=d.get('answer') or {}; sys.exit(0 if d.get('status')=='answered' and a.get('selected')=='a' else 1)" "${qdir}/${qid}" 2>/dev/null; then
    ok "founder answer lands on the fork's question via leadv2-answer.sh"
  else bad "fork question could not be answered / answer not recorded"; fi
  rm -rf "$d"
}

# ---- Case 3: ask — exit 0 + chosen label on an answered question -----------
case_ask_answered() {
  local d root qdir qid out rc
  d="$(setup_sandbox)"; root="${d}/repo"; qdir="${d}/state/questions"
  export LEADV2_STATE_ROOT="${d}/state" LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}"
  export LEADV2_ASK_POLL_INTERVAL=0

  # Ask in the background, answer it mid-poll, expect exit 0 + label.
  ( cd "$root" && bash "$FS" ask tid-fork01 "gate?" --option "l|launch" --option "d|defer" \
    --default-option l --timeout-poll 10 > "${d}/ask.out" 2>/dev/null ) &
  askpid=$!
  qid=""
  for _ in $(seq 1 50); do
    qid="$(ls "$qdir" 2>/dev/null | grep -E '^q-[0-9a-f]+\.yaml$' | head -1)"
    [[ -n "$qid" ]] && break
    sleep 0.2
  done
  if [[ -z "$qid" ]]; then bad "answered-path: no question file appeared"; rm -rf "$d"; return; fi
  ( cd "$root" && bash "$ANSWER" "${qid%.yaml}" d ) >/dev/null 2>&1
  wait "$askpid"; rc=$?
  out="$(cat "${d}/ask.out")"
  [[ $rc -eq 0 && "$out" == "d" ]] \
    && ok "ask exit 0 + prints chosen label when founder answers mid-poll" \
    || bad "answered ask rc=${rc} out=${out} (expected rc=0 label=d)"
  rm -rf "$d"
}

# ---- Case 4: postflight refuses dirty, reaps clean, no-op when gone --------
case_postflight() {
  local d root lane rc
  d="$(setup_sandbox)"; root="${d}/repo"
  export LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state"
  lane="$(cd "$root" && bash "$FS" preflight tid-fork02 2>/dev/null)"

  printf 'leftover\n' > "${lane}/dirty.txt"
  ( cd "$root" && bash "$FS" postflight tid-fork02 ) >/dev/null 2>&1; rc=$?
  [[ $rc -ne 0 && -d "$lane" ]] \
    && ok "postflight refuses a dirty lane and leaves it on disk" \
    || bad "postflight dirty rc=${rc} lane_exists=$([[ -d $lane ]] && echo 1 || echo 0)"

  rm -f "${lane}/dirty.txt"
  ( cd "$root" && bash "$FS" postflight tid-fork02 ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 && ! -d "$lane" ]] \
    && ok "postflight reaps a clean lane (exit 0)" \
    || bad "postflight clean rc=${rc} lane_exists=$([[ -d $lane ]] && echo 1 || echo 0)"

  ( cd "$root" && bash "$FS" postflight tid-fork02 ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] && ok "postflight re-run is a safe no-op" \
    || bad "postflight no-op re-run rc=${rc}"
  rm -rf "$d"
}

# ---- Case 1b: preflight REFUSES when isolation is off/unavailable (H1) -----
case_preflight_refuses() {
  local d root out rc
  d="$(setup_sandbox)"; root="${d}/repo"

  # Kill-switch: LEADV2_LANE_WORKTREE=off => refuse before anything is written.
  out="$(cd "$root" && LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state" \
    LEADV2_LANE_WORKTREE=off bash "$FS" preflight tid-h1 2>"${d}/err")"; rc=$?
  [[ $rc -eq 1 && -z "$out" ]] \
    && ok "kill-switch: preflight exits 1, no lane root on stdout" \
    || bad "kill-switch preflight rc=${rc} out=${out}"
  grep -q "LEADV2_LANE_WORKTREE=off" "${d}/err" \
    && ok "kill-switch: stderr names the kill-switch" \
    || bad "kill-switch: stderr does not name the kill-switch: $(cat "${d}/err")"
  if ! grep -q "tid-h1" "${root}/docs/leadv2/active.yaml" 2>/dev/null \
     && ! ls "${root}/.claude/worktrees/tid-h1" >/dev/null 2>&1; then
    ok "kill-switch: no registry row, no lane left behind"
  else bad "kill-switch: refusal left state behind"; fi

  # ensure fallback: worktree dir unwritable => ensure prints the SHARED root;
  # preflight must refuse rather than hand the fork the lead checkout.
  mkdir -p "${d}/ro" && chmod 555 "${d}/ro"
  out="$(cd "$root" && LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state" \
    LEADV2_WORKTREE_DIR="${d}/ro/wt" bash "$FS" preflight tid-h1b 2>"${d}/err2")"; rc=$?
  chmod 755 "${d}/ro"
  [[ $rc -eq 1 && -z "$out" ]] \
    && ok "fallback: preflight exits 1 and does NOT print the shared root" \
    || bad "fallback preflight rc=${rc} out=${out}"
  grep -q "refusing" "${d}/err2" \
    && ok "fallback: stderr states the refusal with expected-vs-got" \
    || bad "fallback: refusal reason missing: $(cat "${d}/err2")"
  rm -rf "$d"
}

# ---- Case 2b: ask retry polls the SAME question — one file, N polls (H2) ----
case_ask_retry_reuses_question() {
  local d root qdir fa_dir qcount out rc
  d="$(setup_sandbox)"; root="${d}/repo"; qdir="${d}/state/questions"; fa_dir="${d}/state/fork-ask"
  export LEADV2_STATE_ROOT="${d}/state" LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}"
  export LEADV2_ASK_POLL_INTERVAL=0 LEADV2_FORK_ASK_POLL_SEC=1

  out="$(cd "$root" && bash "$FS" ask tid-r "ship it?" --option "a|yes" --option "b|no" \
    --default-option a --timeout-poll 1 2>/dev/null)"; rc=$?
  [[ $rc -eq 3 ]] && ok "retry-case: first ask exits 3" || bad "first ask rc=${rc}"

  out="$(cd "$root" && bash "$FS" ask tid-r "ship it?" --option "a|yes" --option "b|no" \
    --default-option a --timeout-poll 1 2>/dev/null)"; rc=$?
  [[ $rc -eq 3 ]] && ok "retry-case: second ask exits 3" || bad "second ask rc=${rc}"
  [[ -z "$out" ]] && ok "exit-3 ask writes NOTHING to stdout" \
    || bad "exit-3 stdout not empty: ${out}"

  qcount="$(ls "$qdir" 2>/dev/null | grep -cE '^q-[0-9a-f]+\.yaml$')"
  [[ "$qcount" == 1 ]] \
    && ok "retry re-asks NOTHING — exactly one question file after 2 invocations" \
    || bad "expected 1 question file, found ${qcount}"
  [[ -f "${fa_dir}/tid-r.yaml" ]] && ok "fork-ask record persisted for the retry" \
    || bad "fork-ask record missing at ${fa_dir}/tid-r.yaml"
  rm -rf "$d"
}

# ---- Case 2c: answered record returns the label; record is removed (H2) ----
case_ask_retry_returns_answer() {
  local d root qdir fa_dir qid out rc
  d="$(setup_sandbox)"; root="${d}/repo"; qdir="${d}/state/questions"; fa_dir="${d}/state/fork-ask"
  export LEADV2_STATE_ROOT="${d}/state" LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}"
  export LEADV2_ASK_POLL_INTERVAL=0 LEADV2_FORK_ASK_POLL_SEC=1

  ( cd "$root" && bash "$FS" ask tid-ans "gate?" --option "l|launch" --option "d|defer" \
    --default-option l --timeout-poll 1 ) >/dev/null 2>&1
  qid="$(ls "$qdir" 2>/dev/null | grep -E '^q-[0-9a-f]+\.yaml$' | head -1)"
  [[ -n "$qid" ]] || { bad "answered-retry: no question file"; rm -rf "$d"; return; }
  # Founder answers AFTER the poll deadline — the retry must return the label.
  ( cd "$root" && bash "$ANSWER" "${qid%.yaml}" d ) >/dev/null 2>&1

  out="$(cd "$root" && bash "$FS" ask tid-ans "gate?" --option "l|launch" --option "d|defer" \
    --default-option l --timeout-poll 1 2>/dev/null)"; rc=$?
  [[ $rc -eq 0 && "$out" == "d" ]] \
    && ok "retry after founder answered returns the chosen label (race closed)" \
    || bad "answered-retry rc=${rc} out=${out}"
  [[ ! -f "${fa_dir}/tid-ans.yaml" ]] \
    && ok "answered record is deleted (next Gate-1 question starts clean)" \
    || bad "record still present after answer"
  rm -rf "$d"
}

# ---- Case 2d: a DIFFERENT question while one is pending => exit 1 (H2) -----
case_ask_different_question_refused() {
  local d root err rc
  d="$(setup_sandbox)"; root="${d}/repo"
  export LEADV2_STATE_ROOT="${d}/state" LEADV2_PROJECT_ROOT="${root}"
  export LEADV2_ASK_POLL_INTERVAL=0 LEADV2_FORK_ASK_POLL_SEC=1

  ( cd "$root" && bash "$FS" ask tid-dup "first gate?" --option "a|yes" --option "b|no" \
    --default-option a --timeout-poll 1 ) >/dev/null 2>&1
  ( cd "$root" && bash "$FS" ask tid-dup "SECOND gate?" --option "x|one" --option "y|two" \
    --default-option x --timeout-poll 1 ) >/dev/null 2>"${d}/err"; rc=$?
  [[ $rc -eq 1 ]] && ok "different question while pending is refused (exit 1)" \
    || bad "duplicate ask should exit 1, got rc=${rc}"
  grep -q "first gate?" "${d}/err" \
    && ok "refusal quotes the pending question text" \
    || bad "refusal does not quote the pending question: $(cat "${d}/err")"

  # Operator escape: --cancel-pending frees the slot.
  ( cd "$root" && bash "$FS" ask tid-dup --cancel-pending ) >/dev/null 2>&1; rc=$?
  ( cd "$root" && bash "$FS" ask tid-dup "SECOND gate?" --option "x|one" --option "y|two" \
    --default-option x --timeout-poll 1 ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 3 ]] && ok "--cancel-pending withdraws the record; new question accepted" \
    || bad "post-cancel ask rc=${rc} (expected 3=pending)"
  rm -rf "$d"
}

# ---- Case 5b: commit wrapper lands on worktree-<id>, lead tip untouched (H3)
case_commit() {
  local d root lane tip_before tip_after branch rc
  d="$(setup_sandbox)"; root="${d}/repo"
  export LEADV2_PROJECT_ROOT="${root}" LEADV2_STATE_ROOT="${d}/state"
  lane="$(cd "$root" && bash "$FS" preflight tid-ci 2>/dev/null)"
  tip_before="$(git -C "$root" rev-parse HEAD)"

  printf 'lane work\n' > "${lane}/lane-file.txt"
  ( cd "$root" && bash "$FS" commit tid-ci -m "test: lane commit" --all ) >/dev/null 2>&1; rc=$?
  branch="$(git -C "$lane" symbolic-ref --short HEAD)"
  if [[ $rc -eq 0 && "$branch" == "worktree-tid-ci" ]] \
     && git -C "$lane" log -1 --format=%s | grep -q "lane commit" \
     && git -C "$lane" ls-files --error-unmatch lane-file.txt >/dev/null 2>&1; then
    ok "commit lands on branch worktree-tid-ci in the lane"
  else bad "commit rc=${rc} branch=${branch}"; fi

  tip_after="$(git -C "$root" rev-parse HEAD)"
  # (root also carries preflight side-effects — active.yaml, worktrees/ — that
  # predate the commit; the commit's fingerprint is HEAD + index content.)
  if [[ "$tip_before" == "$tip_after" ]] \
     && ! git -C "$root" ls-files --error-unmatch lane-file.txt >/dev/null 2>&1 \
     && ! git -C "$root" diff --cached --name-only 2>/dev/null | grep -q .; then
    ok "main-checkout git log and index unchanged by the lane commit"
  else bad "main checkout moved or swept: ${tip_before} -> ${tip_after}"; fi

  # Idempotent re-run: nothing staged => exit 0, no empty commit.
  ( cd "$root" && bash "$FS" commit tid-ci -m "test: empty" --all ) >/dev/null 2>&1; rc=$?
  [[ $rc -eq 0 ]] && ok "empty-index commit is a clean exit-0 no-op" \
    || bad "empty commit rc=${rc}"

  rm -rf "$d"
}

case_preflight
case_preflight_refuses
case_ask
case_ask_answered
case_ask_retry_reuses_question
case_ask_retry_returns_answer
case_ask_different_question_refused
case_commit
case_postflight

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == 0 ]]
