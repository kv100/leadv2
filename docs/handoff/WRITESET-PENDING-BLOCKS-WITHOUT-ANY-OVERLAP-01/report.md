# WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01 — report

## What changed

Fix da0a87a7 + test amendments ca7675ad/ae5ecd39. Full creator census and
rationale in the da0a87a7 commit body. Short form:

- `leadv2-fanout.sh` `launch_via_dispatch_code`: task-row contract read hoisted
  above the pid=null reservation, so the reservation **declares** its write set
  (16th/17th args of `_fanout_register_session`) instead of landing write-less.
- Genuine can't-know creators now record **why** (`writes_reason=`):
  `prepass_pending` (dispatch-code first register), `pre_dispatch_spawn`
  (legacy-shape spawn sites), `plan_gate_pre_dispatch` (gate1-prompt),
  `fork_attach_unknown` (fork-session), `legacy_lock_acquire` (helpers shim).
- `_lv2_ws_pending` measures from `first_seen_at`, carried across the
  remove+append recreation — the re-created-every-2-minutes row can no longer
  reset its own window. Refusal line carries `writes_reason=<why>`
  (`undeclared` for legacy rows), extending the `blocked_by=` naming.
- Fail-closed branch and the 900 s window itself: **untouched**.

## Acceptance 1 — routine case stops firing (creator taught to declare)

Suite case 1 (real fanout writer + real registry): reservation declares
`res/a.txt`; disjoint declared candidate proceeds rc=0.

## Acceptance 2 — race case still refuses, and says why

Suite cases 2/2b: genuinely write-less incumbent (reason `prepass_pending`)
refuses rc=5; registry AND `_emit_writeset_refusal` both carry the reason;
legacy row says `undeclared`.

## Acceptance 3 — mutation controls (artifacts under mutation-control/)

Two anchors, both unique, run via `leadv2-mutation-control.sh` at the final
non-artifact HEAD (artifacts are excluded from the lane diff hash):

1. Window clock — `leadv2-active-registry.sh`
   `started = other.get("first_seen_at") or other.get("started_at")` →
   `started = other.get("started_at")` (pre-fix clock). Cases 3/3b must go red.
2. Fanout declaration — `leadv2-fanout.sh`
   `writes = None if writes_str in ("", "null", "None", "-") else writes_str` →
   `writes = None` (strip the declaration). Case 1 must go red.

## Acceptance 4 — selection proof (production file, never the suite)

## Falsification set (raw)

bash -n: all 7 changed shell files OK; all 5 embedded PYEOF blocks in
leadv2-active-registry.sh compile (py_compile-equivalent via compile()).
Suite: pass=7 fail=0. SELECT_ONLY isolation: with only
`leadv2-active-registry.sh` dirty (suite committed and clean),
`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` selects
`test-writeset-pending-overlap.sh` (8 selected total incl. control-plane dirt).
Full run-all NEVER executed in this live checkout (symlink-redirect hazard).
