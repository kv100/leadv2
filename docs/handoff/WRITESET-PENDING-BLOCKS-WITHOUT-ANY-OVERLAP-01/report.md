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
   `started = other.get("started_at")` (pre-fix clock). Case 3b must go red.
   First attempt at a 1s window: **mutant survived** — one slow python spawn
   between recreation and candidate expired the window even pre-fix. Margin
   widened to 5s window / 6s sleep (commit b956f718); control then killed.
2. Fanout declaration — `leadv2-fanout.sh`
   `writes = None if writes_str in ("", "null", "None", "-") else writes_str` →
   `writes = None` (strip the declaration). Case 1 must go red.

## Acceptance 4 — selection proof (production file, never the suite)

Suite committed and clean; only `plugins/leadv2/scripts/leadv2-active-registry.sh`
made dirty (transient trailing comment, reverted immediately):

    $ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep writeset-pending
    [SELECT] .../plugins/leadv2/scripts/tests/test-writeset-pending-overlap.sh
    run-all: 8 selected, scope=changed, select_only=1

Selected by the `# run-all-triggers:` header naming the production file —
never by the suite's own dirty filename. Full run-all was NEVER executed in
this live checkout (five control-plane symlinks get redirected into a temp
dir and their targets deleted).

## Falsification set (raw)

- `bash -n`: all 7 changed shell files OK.
- Embedded python: all 5 PYEOF blocks in leadv2-active-registry.sh compile.
- Suite at final HEAD: `[TEST] SUMMARY: pass=7 fail=0` (local mutant probes:
  clock revert → fail=1 at case 3b; declaration strip → fail=2 at cases 1/3).
- Changed-scope runner: SELECT_ONLY only (see Acceptance 4).
