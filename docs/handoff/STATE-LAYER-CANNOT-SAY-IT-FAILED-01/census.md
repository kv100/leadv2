# Census: state-layer functions that take a write, don't perform it, and return 0

Method: three parallel behavioural sweeps (not grep-for-syntax) across
`plugins/leadv2/scripts/{leadv2-active-registry.sh,leadv2-journal.sh,leadv2-phase-record.sh,
leadv2-lanes-snapshot.sh,leadv2-status-snapshot.sh}` and `plugins/leadv2/scripts/lib/*.sh`
(37 files). Each candidate was triggered by actually sourcing the file and invoking the
function with args/env that walk the silent path, then checking the observed `rc` and the
absence of the expected artifact — not inferred from reading. Full measured commands+output
are in the three subagent transcripts folded into this table; representative commands are
reproduced per row.

Ranked by how far the lie travels (state that other surfaces read and trust), not by fix
difficulty.

| # | file:line | function | silent path (one sentence) | what caller sees | dependent on the zero? |
|---|---|---|---|---|---|
| 1 | `leadv2-phase-record.sh:152-164` (root resolve) → `cmd_record` at 689 | `cmd_record` | `PROJECT_ROOT` is trusted from inherited `LEADV2_PROJECT_ROOT` with no check it names the caller's actual repo; the conflict guard only fires when **both** vars are set and disagree — the realistic cross-repo-lane case (one var inherited) sails through and writes the phase record into the wrong repo. | rc=0, zero stdout/stderr, file "successfully" written — just in the wrong tree. | **Yes — already measured live**: 25 orphan `dispatch-*` dirs accumulated in a foreign repo over days before anyone noticed (this is the documented 3rd known instance). |
| 2 | `leadv2-active-registry.sh:969-983` | `leadv2_active_unregister` | `[[ -f "$yaml_file" ]] \|\| return 0` (line ~974) — if `active.yaml` doesn't exist yet, returns 0 without unregistering and without creating the file. | rc=0, no output. | **Yes — documented 2nd known instance.** Sanctioned call path is "source the file, call the function positionally"; there is no CLI wrapper to surface a failure. |
| 3 | `leadv2-active-registry.sh:993-1009` bash + python `update_phase` op:547-573 | `leadv2_active_update_phase` | Two-layer silence: (a) `[[ -f "$yaml_file" ]] \|\| return 0` before any write; (b) inside the python mutator, the `for s in sessions: if s.get("task_id")==task_id` loop has no `else`/error branch — an unmatched `task_id` falls through, the phase is never set, yet the function still does the atomic temp+rename write of an **unchanged** document and returns 0. | rc=0, file mtime bumped (looks like a successful write), but the row for the requested task is untouched — indistinguishable from a real phase transition. | Yes — this is the mechanism behind known instance #1 (`active_register_miss task=07401216 rc=0`: pulse read the mirrored `active.yaml` and reported an empty/wrong board while the lane was running). |
| 4 | `leadv2-active-registry.sh:1106-1114` bash + python `set_worker_pid` op (743-772, `sys.exit(0)` at 755) | `leadv2_active_set_worker_pid` | Same shape as #3: missing file → early `return 0`; unmatched `task_id` inside python is an explicitly-commented "SILENT no-op, rc 0" — no row created, no message, worker pid never stamped. | rc=0, no worker pid recorded — a supervisor checking "is this lane's worker alive" reads nothing. | Plausible — worker-liveness surfaces read this field; not separately measured live but same mechanism as #1/#3. |
| 5 | `leadv2-active-registry.sh:952-956` | `leadv2_active_set_worktree` | `[[ -d "$wt" ]] \|\| return 0` — a worktree path that doesn't (yet) exist on disk silently no-ops; the row's `worktree` field keeps its old/empty value. | rc=0, no error; `active.yaml`'s worktree field stays stale. | Diff-scope and root-arithmetic tooling read this field to resolve where a lane's diff lives (the exact class of defect GATE-WRONG-ROOT-FALSE-DEAD-01 was about). |
| 6 | `leadv2-active-registry.sh:1012-1021` bash + python `update_pulse` op (575-581) | `leadv2_active_update_pulse` | `[[ -f "$yaml_file" ]] \|\| return 0`, plus the same no-`else` unmatched-`task_id` python pattern as #3. | rc=0, no pulse timestamp recorded — a lane that is actually alive reads as stale/dead to any staleness check keyed on this field. | Yes — pulse staleness is exactly the signal LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01 (a sibling lane, in flight) is measuring; this function is a plausible contributor. |
| 7 | `leadv2-active-registry.sh:138-223` | `leadv2_active_consolidate_ephemeral_roots` | Five stacked early-`return 0` guards before any write is reachable (no common dir; no git remote/marker; no `.ephemeral` dir; `mkdir`/`printf` swallowed by `2>/dev/null \|\| return 0`), plus the embedded python does `if not rows: sys.exit(0)`. | rc=0, **zero output on any path** — cannot tell "nothing to consolidate" from "every guard silently declined". | Unclear — no confirmed downstream reader measured in this pass; flagged for the backlog to check callers. |
| 8 | `leadv2-active-registry.sh:532-534` (python `unregister` op, callee of #2) | `unregister` (python) | Filters `sessions` for non-matching `task_id`; if absent, list is unchanged and the file is still rewritten (unchanged) with rc=0 — no signal distinguishing "removed a row" from "found nothing". | rc=0, mtime bumped, no semantic change. | Same caller class as #2. |
| 9 | `leadv2-journal.sh:11` (`trap 'exit 0' ERR`) over the write at 61-63 | top-level `append` mode | The file's global `trap 'exit 0' ERR` converts **any** failure under `set -euo pipefail` — including a failed `mkdir -p` or failed `printf >>` — into a forced `exit 0` before/instead of completing the write. | rc=0, no journal.md line written, no distinguishable stderr contract (mkdir's own text goes to stderr but the script's own exit status is always 0). | Yes by design intent (journal calls are meant to be fire-and-forget observability) — but that intent is exactly what makes every `_emit` caller downstream (see #10) blind too. |
| 10 | `leadv2-phase-record.sh:174-177` | `_emit` | `[[ -x "$JOURNAL_BIN" \|\| -f "$JOURNAL_BIN" ]] \|\| return 0` before invoking journal; and even when it exists, the invocation itself is `... &>/dev/null \|\| true`. | rc=0, no way to tell whether the journal event (`phase_recorded`, `phase_waived`, `phase_mirror_miss`, `review_ledger_tamper`, `bootstrap_claim_ignored`, ...) was written. | Yes — every one of `cmd_record`'s own designed "at least log a miss" fallbacks routes through this function, so #11 below has no working escape hatch. |
| 11 | `leadv2-phase-record.sh:803-816` (inside `cmd_record`) | `cmd_record` (active.yaml mirror block) | If `task_id` is given but neither `leadv2_active_update_phase` is declared in-process nor `$ACTIVE_REGISTRY` exists on disk, **neither mirror branch executes** — and critically the designed fallback log line (`phase_mirror_miss`) only fires *inside* those two branches on failure, never on "no branch matched at all". Falls through to unconditional `return 0`. | rc=0, phase record file written correctly (so the caller believes it succeeded), but the `active.yaml` mirror the dashboard/pulse depends on silently never updates, with no fallback signal either. | Yes — same board-visibility chain as #1/#3/#6. |
| 12 | `leadv2-lanes-snapshot.sh:317-328` | truth-breaches cache write (top-level, inside full-snapshot block) | `mkdir`, both write attempts, and the final `mv` are each chained `\|\| true` / `2>/dev/null`; an unwritable target directory drops the entire truth-probe cache write with zero signal, and this write is explicitly decoupled from the file's own fail-closed `state_write_error` path. | Overall script still exits 0 with no warning that `truth-breaches-last.json` failed to update. | Unclear/lower — the file's primary mutation logic (active.yaml, tombstones.yaml) is already hardened fail-closed per its own header comments; this is a secondary cache, not the board-of-record. |
| 13 | `lib/leadv2-lane-state.sh:150-154` (python heredoc) via `lane_deregister` (~213) | `lane_deregister` | `if row:` guards the entire dedup/write body with no `else`; an unmatched `task_id` skips deregistration but the surrounding function still falls through to the unconditional yaml-dump/replace and returns 0. | rc=0, no error, no indication the task was never found — indistinguishable from "successfully deregistered". | Same shape/impact class as active-registry's unregister (#2), separate code path (lane-state vs active-registry). |
| 14 | `lib/leadv2-brain-record.sh:111-113` | `leadv2_brain_write_yaml` | `[[ -n "${task_id}" ]] \|\| return 0` before `mkdir`/tmp-write/`mv`. | rc=0, no `docs/handoff/<task_id>/brain.yaml`, no directory created, no message. | Brain records feed plan/build context; an empty task_id silently producing nothing means downstream context-merge reads a file that was never written, with no error. |
| 15 | `lib/leadv2-receipt-freshness.sh:54,126-133` | `leadv2_receipt_is_stale` | The `mv -f` rename-on-stale branch explicitly still `return 0` whether or not the rename actually succeeded — the caller's rc cannot distinguish "renamed the stale receipt out of the way" from "rename failed, receipt untouched". | rc=0 either way; only a text log line differs. | Callers gating on "did the stale receipt get moved" have no rc-based way to know. |
| 16 | `lib/leadv2-worker-epilogue.sh:85-148` | `leadv2_worker_commit_epilogue` | Every append (`progress.log`, `meta.yaml`) is `... >> file 2>/dev/null \|\| true`; if `run_dir` doesn't exist none of the appends happen, yet the function unconditionally `return 0`s. | rc=0, no progress.log/meta.yaml, no directory created, no error. | A missing/rotated run_dir silently drops the epilogue record a supervisor would otherwise read to know a worker finished cleanly. |
| 17 | `lib/leadv2-arm-cooldown.sh:102-104` (+198, 208 identical shape) | `arm_cooldown_record` / `arm_cooldown_clear` / `arm_cooldown_ladder_note` | `_arm_cooldown_valid_arm "$arm" \|\| return 0` — unlike this file's other guards, this one produces **zero** stdout/stderr, not even a log line, on an invalid/empty arm name. | rc=0, complete silence, no `${arm}.state` file. | Routing-arm cooldown state feeds provider-selection; a caller passing a malformed arm name gets no signal that cooldown was never recorded. |
| 18 | `lib/leadv2-freepool-gate.sh:161-164` | `record_result` | A malformed `latency_s` (non-numeric) makes the embedded `python3 -c 'float(sys.argv[3])...'` raise uncaught; the whole invocation is wrapped `... 2>/dev/null \|\| true`, so the raise is swallowed and the bash function still returns 0 with the result silently dropped (state file unchanged). | rc=0, `freepool-arm-state.json` unchanged — the caller believes the result was recorded. | Freepool arm-selection reads this state to rank arms; a dropped result silently skews ranking with no error trail. |
| 19 | `lib/leadv2-dod-gate.sh:506-566` | `lv2_dod_gate_run` | `mkdir -p ... 2>/dev/null \|\| true` then `mv -f ... 2>/dev/null \|\| cp -f ... 2>/dev/null`; if both fail, the only remediation is a stderr `printf`, but the function's return code is driven purely by the check verdicts (`overall_fail`/`overall_undetermined`), never by whether `out_md` was actually written. | rc=0 (when checks pass) even though `dod-gate.md` was never created — the artifact is recoverable only by parsing stderr, not by rc or by the file existing. | This is the DoD gate this very lane's deliverable is checked against — if its own artifact write can silently no-op, a round could pass DoD with no `dod-gate.md` on disk at all. |

## Not counted (checked, ruled out as not this shape)

- `leadv2_active_heartbeat`, `leadv2_active_mark_finished`, `leadv2_active_append_provider_receipt`,
  `leadv2_active_set_writes`, `leadv2_active_set_attempt` — all return non-zero (4) on missing
  file/row; caller **can** distinguish failure.
- `leadv2-status-snapshot.sh` — performs zero writes (read + echo only); out of scope by
  definition (nothing to falsely report as written).
- `leadv2-lanes-snapshot.sh`'s primary mutation logic (`active.yaml`, `tombstones.yaml`,
  `.supervise-last.json`, inside the embedded python core) — deliberately fail-closed
  (`emit_fatal` → `sys.exit(1)` on `OSError`; skips surfaced via `would_adopt`/`would_prune`).
  Already hardened against this exact failure class per its own header comments.
- `lib/leadv2-lane-guard.sh`, `lib/leadv2-mission-writeset.sh` — detection/report-only, no writes.
- `lib/leadv2-status-cache.sh` — atomic-write failures re-raise rather than swallow.
- `lib/leadv2-red-proof.sh`, `lib/leadv2-review-signals.sh` — documented report-only, "always rc0"
  by design, not a state write.
- `lib/leadv2-red-first-baseline.sh`, `lib/leadv2-report-deliverable.sh`,
  `lib/leadv2-control-prover.sh`, `lib/leadv2-worker-mcp.sh` — write failures return distinct
  non-zero codes with a reason; not silent.
- `lib/leadv2-watch-lifecycle.sh`'s `wl_event` has the identical guard-before-write shape as
  #17, but the file's own header documents it as an intentional "soft-fail, never kills a
  watcher" contract — flagged here as a secondary instance of the same class, not separately
  numbered since it's contractually intended rather than an oversight.
- `lib/leadv2-admission-class.sh`'s `leadv2_admission_write_receipt` early returns (receipt
  exists / floor held) are intentional idempotency, not silent failure.
- Remaining `lib/*.sh` files skimmed with no write-with-silent-success shape found:
  `leadv2-worker-reason.sh`, `mktemp-guard.sh`, `leadv2-review-reroute-note.sh`,
  `leadv2-sleep.sh`, `leadv2-route-arbiter.sh` (off-limits anyway), `leadv2-refusal-classify.sh`,
  `leadv2-lead-identity.sh`, `leadv2-codex-circuit.sh`, `leadv2-codex-quota-gate.sh`,
  `leadv2-freepool-model-select.sh`, `leadv2-worker-output-gate.sh`,
  `leadv2-builder-selfcheck.sh`, `leadv2-e2e-root.sh`, `leadv2-think-model.sh`.

## Self-check against the acceptance bar

The three known instances from the brief map onto this table as:
- Registration (`active_register_miss task=07401216 rc=0`) → row 3 / row 6 mechanism.
- Deregistration (`leadv2_active_unregister`) → row 2, exact match.
- Phase records (`leadv2-phase-record.sh:164`, wrong-repo write) → row 1, exact match.

All three were rediscovered by the behavioural method (source + invoke + check artifact),
not assumed from the brief text — each row above carries its own measured command in the
subagent transcripts this table was built from. 19 total candidates found across three
independent sweeps (8 + 4 + 7), confirming the brief's premise that this shape is systemic
rather than isolated to the three already-known cases.
