# CLASS-IS-COMPUTED-NOT-DECLARED-01 — implemented

> ## STOP — PREPASS-MECHANISM-CLOSURE-01 census falsified (2026-09-01)
>
> This lane must not proceed to implementation, review, E2E, or closure under
> the supplied scoped design.  The design's admission-caller census omits
> `plugins/leadv2/scripts/leadv2-backlog-pump.sh`, which independently sources
> `lib/leadv2-admission-class.sh` and invokes `leadv2_admission_class` before
> it chooses its launch route.  For `Standard`/`Heavy`, that caller starts the
> full-cycle runner directly rather than invoking `leadv2-dispatch-code.sh`.
> The current WIP only calls the new write-set floor in
> `leadv2-dispatch-code.sh`; it therefore cannot enforce a computed admission
> class on the pump path.
>
> Raw discovery evidence (all from this pinned worktree):
>
> ```text
> $ git grep -n -E 'source .*leadv2-admission-class|leadv2_admission_class ' HEAD -- plugins/leadv2/scripts
> HEAD:plugins/leadv2/scripts/leadv2-backlog-pump.sh:169:  source "${SCRIPT_DIR}/lib/leadv2-admission-class.sh" || true
> HEAD:plugins/leadv2/scripts/leadv2-backlog-pump.sh:709:    pair="$(leadv2_admission_class "" 0 "${estimate}")"
> HEAD:plugins/leadv2/scripts/leadv2-dispatch-code.sh:3754:    pair="$(leadv2_admission_class "${explicit}" "${flagged}" "${estimate}")"
>
> $ sed -n '1017,1030p' plugins/leadv2/scripts/leadv2-backlog-pump.sh
> IFS=$'\\t' read -r adm_cls adm_route adm_src adm_wk <<<"$(_pump_classify "$iid" "$mission")"
> if [[ "${adm_route:-phases}" == "phases" ]]; then
>   if _pump_adopt_full_cycle "$iid" "${adm_cls:-Standard}"; then
>     dispatched=$((dispatched + 1))
>     cap=$((cap - 1))
>     continue
>   fi
> fi
>
> $ rg -n 'leadv2_admission_writes_gate|_class_floor_check' plugins/leadv2/scripts/leadv2-backlog-pump.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh
> plugins/leadv2/scripts/leadv2-dispatch-code.sh:3792:  pair="$(leadv2_admission_writes_gate "${cls}" 1 "${writes}")" || rc=$?
> plugins/leadv2/scripts/leadv2-dispatch-code.sh:6496:  _class_floor_check ...
> plugins/leadv2/scripts/leadv2-dispatch-code.sh:6716:  _class_floor_check ...
> ```
>
> That is an omitted admission caller with a materially different consequence,
> not a detail that may be silently widened around.  The current dirty WIP is
> preserved untouched; it is not committed or presented as a fix.  A revised
> authoritative design must explicitly decide whether the invariant belongs in
> the shared admission primitive (with an immutable write-set input), the pump,
> or both, and must include the direct full-cycle path in its test and review
> census.

## Prepass note: the prior stop condition is resolved

The previous lane run stopped because `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/brief.md`
was absent from THIS worktree. It exists in the main repo checkout
(`/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/brief.md`)
— `docs/handoff/` is untracked/lane-local, so it never propagated into this worktree via git.
Read directly by absolute path; its content is byte-identical to the "ORIGINAL MISSION" section
already inlined in the dispatch prompt. `docs/handoff/dispatch-65d12844/context.yaml` (main repo)
confirms the decisions match brief.md items 1-4 in full — this is NOT scope narrowed to "admission
only" in the sense of dropping items 3/4; "Gate 1 taken by the lead; scope is admission only" reads
as "this fix belongs in the admission/dispatch layer," not as a scope cut. `review.diff` for
dispatch-65d12844 was 0 lines and `review-gate.md` said `reason: no_work` — confirming no code had
landed yet when this run started.

## Census correction (PREPASS-MECHANISM-CLOSURE-01)

The brief's "why this exists" section says to reuse `leadv2-lane-class.py` for class computation.
**That is wrong** — `leadv2-lane-class.py`'s `classify()` computes lane *liveness* state
(live/queued/done/dead) for the SwiftBar status renderer; it has nothing to do with task size
(Trivial/Light/Standard/Heavy/Strategic). I did not use it. I did reuse `leadv2-admission-class.sh`
as instructed — its `_lv2_class_rank`/`_lv2_class_canonical` helpers (from `leadv2-lane-guard.sh`)
and its file/receipt conventions.

Also worth recording: the brief's claim "nothing computes an independent class to escalate from" is
narrowly true only for the LANE_WRITES axis. `leadv2-admission-class.sh` already had (and still has,
untouched) a working escalate-only mechanism keyed off a DIFFERENT signal — the TaskEstimate judge
(`leadv2-task-judge.sh`, an LLM classifier) — wired into `_admission_classify` in
`leadv2-dispatch-code.sh`. That mechanism silently re-escalates a low flag rather than refusing it,
and it has no access to the declared LANE_WRITES set. Both gaps (silent-not-refused, and no
LANE_WRITES-based floor at all) are exactly what this lane closes, additively, without touching the
existing judge-based mechanism.

## What I built

**`plugins/leadv2/scripts/lib/leadv2-admission-class.sh`** (pure additions, no existing line
changed — see `git diff --stat`):
- `leadv2_admission_control_plane_paths` / `_admission_control_plane_hit` — flags LANE_WRITES paths
  that touch this repo's own control plane (dispatch/admission/gate/ledger/deploy/supervise/
  phase-record/lane-guard/active-registry/suite-lock/review-run/verify/close). This repo dispatches,
  gates and judges three live project repos, so its own control-plane files ARE the
  production/safety/publish/payment surface the brief asks for.
- `leadv2_admission_writes_subsystems` — unique-subsystem count (first two path segments), bash 3.2
  safe (no associative arrays; `sort -u | wc -l`).
- `leadv2_admission_writes_class` — deterministic Light|Standard|Heavy from a LANE_WRITES CSV alone:
  control-plane touch OR subsystems>=4 → Heavy; subsystems>=2 → Standard; else Light; empty → Light.
  Mirrors the existing D1 map's own convention of never emitting Trivial/Strategic.
- `leadv2_admission_writes_gate` — **item 2**: `<explicit> <flagged> <writes-csv>` →
  `verdict\tdeclared\tcomputed\tsignals`, rc 3 on `refused` (declared below computed — a HARD stop,
  not a warning), rc 0 on `escalated` (declared above computed, accepted) or `ok`.
  One deliberate carve-out found while testing acceptance #7: this axis's floor never computes below
  Light, so a genuine `--task-class trivial` on a genuinely light writes set would otherwise be
  refused forever (Trivial is permanently unreachable through this axis alone). Special-cased to
  `ok` — see the comment at the `if` in the gate.
- `leadv2_admission_write_class_floor` / `leadv2_admission_class_floor_path` — **item 3**: any
  non-"ok" verdict is written to `docs/handoff/dispatch-<sig8>/class-floor.yaml`, founder-readable,
  not a log line.
- `leadv2_admission_close_recompute` / `leadv2_admission_write_close_ledger` — **item 4**:
  recomputes the same deterministic function against the lane's ACTUAL changed paths at close,
  returns `declared\tcomputed\tactual\tmismatch`, and an append-only (never overwritten) fixture-
  ledger writer so a systematic pattern across many closes stays visible, not just the latest one.

**`plugins/leadv2/scripts/leadv2-dispatch-code.sh`**: new `_class_floor_check` helper (refuse/
record/continue), called twice on the real admission path — once right after `_admission_classify`
sets `task_class` (covers `--writes` CLI/row-declared LANE_WRITES), and again after the architect
prepass's own `LANE_WRITES:` line fills `lane_writes` in for product-class tasks (this is the actual
bypass shape from the founder's incident: LANE_WRITES is only known AFTER the phase-precondition
guard already ran against whatever class the flag/estimate produced, so a second check after prepass
closes that specific gap). `LEADV2_REQUIRE_CLASS_FLOOR=1` default-on kill switch, matching this
file's own `REQUIRE_PHASES`/`REQUIRE_LANE_WRITES` rollback convention.

**`plugins/leadv2/scripts/leadv2-broad-status.sh`**: new `_class_floor_alerts()` reads every
`docs/handoff/dispatch-*/class-floor.yaml` and renders a one-line summary; wired into
`_write_degraded_status` (the one existing call site that composes founder-status.md's read-only
fallback content, alongside `_live_lane_facts`). **Scope decision**: I did NOT wire this into the
main happy-path `$BLOCK` table assembly (the ~1200-line python-heredoc renderer near the end of the
file) — tracing a safe splice point there risked more of the lane's budget than the visibility
feature's value justified, and the degraded-path wire-up is a real, exercised code path (not a stub),
just not the only one. Flagging this as a legitimate follow-up, not a silent gap.

## Item 3 — did I keep a downgrade override path? No.

I considered a `--downgrade-reason` escape hatch. I did not build it. The founder's incident was a
speed-motivated downgrade with no real justification; the honest path this lane is required to keep
open (acceptance #7) is a lead declaring the correct class (or no class) and going through the real
phase-gate cycle — which the brief itself confirms became possible again after `6f6b55b` fixed the
gitignore blocker. A downgrade-with-justification path would have needed its own founder-visible
machinery (acceptance #5) for a case nothing in this incident calls for; the simpler, safer design is
a pure refusal. This also trivially satisfies the off_limits list (`a warning instead of a refusal`
never applies since there is no warning branch at all). Acceptance #5 is explicitly conditional ("if
you kept one") — I did not, so there is nothing to render there.

## Item 4 — close-time recompute is NOT wired into the real close path

`leadv2-dispatch-product-close.sh` is the script that actually closes a lane, and it is **not** in
this task's `LANE_WRITES`. `leadv2_admission_close_recompute` / `leadv2_admission_write_close_ledger`
are real, tested library functions (acceptance #6, against a fixture root — never the real ledger),
but nothing calls them from a real close today. Wiring that in requires touching
`leadv2-dispatch-product-close.sh`, which is out of scope for this dispatch. This is a genuine,
named gap, not a silent one — surfacing it here per the task's own evidence-contract rule.

## Verification

- `bash -n` clean on all 5 changed files.
- New suite `test-class-cannot-be-downgraded.sh`: 25/25 PASS standalone.
- Pre-existing `test-admission-class.sh`: 24/24 PASS unchanged (no regression from the additive lib
  changes).
- RED/GREEN mutation proof done INSIDE the real production file (not a copy): flipped the `refused`
  branch of `leadv2_admission_writes_gate` in the actual `leadv2-admission-class.sh` to `ok`, ran the
  new suite → 2/25 FAIL (exit 1), confirming the suite is red without the refusal. Reverted via a
  pre-mutation backup diffed byte-identical (`REVERTED CLEAN`); `git diff --stat` after revert shows
  only pure additions (188 insertions, 0 deletions) to that file.
- `tests/run-all.sh --scope changed` with `LEADV2_SUITE_LOCK_DISABLE=1`: see `full.md` / chat for the
  final result (was still running in the background when this file was written; the EXTRA_SUITE_MAP
  rows added route `leadv2-admission-class.sh`, `leadv2-dispatch-code.sh` and `leadv2-broad-status.sh`
  changes to `test-class-cannot-be-downgraded.sh` specifically).

## Files touched (exactly LANE_WRITES, nothing else)

- `plugins/leadv2/scripts/lib/leadv2-admission-class.sh` (+188, -0)
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (+37)
- `plugins/leadv2/scripts/leadv2-broad-status.sh` (+28, -2)
- `plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh` (new)
- `tests/run-all.sh` (+4 EXTRA_SUITE_MAP rows, -1 for the moved closing quote)
- `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/report.md` (this file)
