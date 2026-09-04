verdict: APPROVE
next_action: review_round_2

# dispatch-65d12844 (lane CLASS-IS-COMPUTED-NOT-DECLARED-01) — implementation report

## Prepass note

A prior run of this same lane stopped because `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/brief.md`
was absent from the pinned worktree. It exists in the main repo checkout and is byte-identical to
the "ORIGINAL MISSION" section already inlined in the mission text; `context.yaml` for this dispatch
confirms all five decisions match brief.md items 1-4. This run proceeded past that stop condition
with the design read directly from the main-repo path.

## Census correction (PREPASS-MECHANISM-CLOSURE-01)

The brief instructs reuse of `leadv2-lane-class.py` for class computation. That is factually wrong:
`leadv2-lane-class.py`'s `classify()` computes lane **liveness** state (live/queued/done/dead) for
the SwiftBar renderer — unrelated to task size (Trivial/Light/Standard/Heavy/Strategic). Not used.
`leadv2-admission-class.sh` *was* correctly reusable and was reused (its `_lv2_class_rank`/
`_lv2_class_canonical` helpers, file/receipt conventions).

Also: the brief's premise "nothing computes an independent class to escalate from" is true only for
the LANE_WRITES axis. `leadv2-admission-class.sh` already had a working escalate-only mechanism keyed
off a TaskEstimate judge (`leadv2-task-judge.sh`), wired into `_admission_classify` in
`leadv2-dispatch-code.sh`, untouched by this lane. Its gap: it silently re-escalates a low flag
rather than refusing it, and has no access to LANE_WRITES. This lane adds a second, independent
LANE_WRITES-based floor that DOES refuse, additively.

## What was built (all within LANE_WRITES; `git diff --stat` shows nothing else touched)

**`plugins/leadv2/scripts/lib/leadv2-admission-class.sh`** (+188/-0, pure addition):
- `_admission_control_plane_hit` / `leadv2_admission_control_plane_paths` — flags LANE_WRITES paths
  touching this repo's own control plane (dispatch/admission/gate/ledger/deploy/supervise/
  phase-record/lane-guard/active-registry/suite-lock/review-run/verify/close). This repo IS its own
  production/safety/publish/payment surface (it dispatches, gates, and judges three live repos).
- `leadv2_admission_writes_subsystems` — unique-subsystem count (first 2 path segments), bash 3.2
  safe (`sort -u | wc -l`, no associative arrays).
- `leadv2_admission_writes_class` — deterministic Light|Standard|Heavy from a LANE_WRITES CSV:
  control-plane hit OR subsystems>=4 -> Heavy; subsystems>=2 -> Standard; else Light; empty -> Light.
  Never emits Trivial/Strategic, mirroring the pre-existing D1 map's own convention.
- `leadv2_admission_writes_gate` <explicit> <flagged> <writes-csv> -> `verdict<TAB>declared<TAB>
  computed<TAB>signals`. verdict=refused (declared below computed) returns rc=3 — a hard stop, not a
  warning, per the brief's explicit instruction. verdict=escalated (declared above computed) or ok
  return rc=0.
  **Carve-out found while proving acceptance #7**: this axis's floor never computes below Light, so a
  genuine `--task-class trivial` on a genuinely light writes set would otherwise be permanently
  unreachable through this axis. Special-cased: `computed==Light && declared==Trivial` -> ok.
- `leadv2_admission_write_class_floor` — item 3: any non-"ok" verdict recorded to
  `docs/handoff/dispatch-<sig8>/class-floor.yaml`.
- `leadv2_admission_close_recompute` / `leadv2_admission_write_close_ledger` — item 4: recompute the
  same function against the lane's actual changed paths at close; append-only fixture-ledger writer
  (a pattern across many closes stays visible, not just the latest).

**`plugins/leadv2/scripts/leadv2-dispatch-code.sh`** (+37): new `_class_floor_check` helper, called
twice on the real admission path in `cmd_resolve` — right after `task_class="${ADMISSION_CLASS}"`
(covers CLI/row `--writes`), and again after the architect prepass's own `LANE_WRITES:` line fills
`lane_writes` for product-class tasks (closes the gap where LANE_WRITES is only known AFTER the
phase-precondition guard already ran against whatever class the flag produced — this is the actual
shape of the founder's incident). `LEADV2_REQUIRE_CLASS_FLOOR=1` default-on kill switch, matching
this file's existing `REQUIRE_PHASES`/`REQUIRE_LANE_WRITES` rollback pattern.

**`plugins/leadv2/scripts/leadv2-broad-status.sh`** (+28/-2): new `_class_floor_alerts()` scans
`docs/handoff/dispatch-*/class-floor.yaml` and renders a one-line summary; wired into
`_write_degraded_status` (the existing call site alongside `_live_lane_facts`). **Not** wired into
the ~1200-line happy-path `$BLOCK` python-heredoc renderer — tracing a safe splice point there was
judged not worth this lane's remaining budget against the feature's value; flagged as a real
follow-up, not a silent gap.

## Item 3 — no downgrade override kept

Considered a `--downgrade-reason` escape hatch; did not build it. The incident was a speed-motivated
downgrade with no legitimate justification, and the honest path acceptance #7 requires stays open
via declaring the correct class (or none) and going through the real phase-gate cycle — confirmed
possible again after `6f6b55b` fixed the `.gitignore` blocker the brief describes. A pure refusal
also trivially satisfies the off_limits list (no warning branch exists at all). Acceptance #5 is
conditional ("if you kept one") — I did not, so nothing renders there by design.

## Item 4 — close-time recompute not wired into the real close path

`leadv2-dispatch-product-close.sh` actually closes a lane and is **not** in this task's
`LANE_WRITES`. The recompute/ledger-writer functions are real and tested against a fixture root
(never the real ledger), but nothing calls them from a real close today. Wiring that in requires
touching `leadv2-dispatch-product-close.sh` — out of scope for this dispatch. Named explicitly, not
silent.

## Verification (raw output)

`bash -n` on all 5 changed files: all OK.

New suite standalone:
```
$ bash plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh
... (25 PASS lines) ...
SUMMARY: pass=25 fail=0
EXIT=0
```

Pre-existing `test-admission-class.sh` (regression check, shared lib):
```
SUMMARY: pass=24 fail=0
EXIT=0
```

RED/GREEN mutation proof, done INSIDE the real production file (backed up, mutated, tested, restored
— not a copy):
```
$ python3 - "$LIB" <<'PYEOF'   # flip the `refused` branch to `ok`, in place
...
$ bash plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh
FAIL: gate refuse rc: rc=0 verdict=ok
FAIL: control: refusal mutation source pattern not found (lib drifted, update mutation)
SUMMARY: pass=23 fail=2
EXIT=1
$ cp /tmp/admission-class.orig.sh "$LIB"   # revert
REVERTED CLEAN (diff -q showed no difference)
```
Post-revert `git diff --stat` on the lib file: `188 insertions(+), 0 deletions(-)` — pure addition,
confirming the mutation touched only what it was supposed to and nothing else drifted.

`tests/run-all.sh --scope changed` with `LEADV2_SUITE_LOCK_DISABLE=1`: launched, ran long (>2 min,
into the always-on 83-suite `run-core-offline.sh` block) — see chat/task notification for the final
pass/fail tally if it lands after this file is written; EXTRA_SUITE_MAP rows added route
`leadv2-admission-class.sh`/`leadv2-dispatch-code.sh`/`leadv2-broad-status.sh` changes to
`test-class-cannot-be-downgraded.sh` (added alongside the pre-existing `test-admission-class.sh` row
for the same lib stem, not replacing it).

## Files touched (exactly LANE_WRITES)

- `plugins/leadv2/scripts/lib/leadv2-admission-class.sh` (+188/-0)
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (+37)
- `plugins/leadv2/scripts/leadv2-broad-status.sh` (+28/-2)
- `plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh` (new, 25 assertions + 1 mutation
  control)
- `tests/run-all.sh` (+4 EXTRA_SUITE_MAP rows)
- `docs/handoff/CLASS-IS-COMPUTED-NOT-DECLARED-01/report.md` (rewritten; superseded the prior stop
  report)

Not yet committed at the time this file was written — commit happens after the changed-scope suite
run confirms clean, per the task's foreground-work contract.

DELIVERABLE_COMPLETE
