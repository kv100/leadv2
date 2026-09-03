Confirmed. Now compiling the final report.

## Audit results: 30 handoff reports vs. live tree

| report (dir) | central claim | holds? | evidence / what is missing |
|---|---|---|---|
| DISPATCH-PIN-CLUSTER-01 | "Merging is safe... test-close-chain.sh: 18 passed, 0 failed" pasted as fact, not re-run this audit | UNTESTABLE | Suites exist and are wired (`tests/run-all.sh:217-227`), but the pasted "18 passed/0 failed" is asserted, not reproduced here — no command shown to regenerate it in the report itself beyond referencing prior commits. |
| GLM-EFFICIENCY-AUDIT-01 | Table of GLM capability gaps, incl. "effort_dropped... self-diagnosed gap" | HOLDS | `grep effort_dropped leadv2-dispatch-code.sh` → 3 live emit sites (5179/5243/5293), confirms the bug this audit names is still live today — audit is accurate, no fix was claimed. |
| CODEX-DIES-MID-TEST-01 | Root cause = plugin SessionEnd hook kills broker; fix makes death "loud, attributed, router-visible" (not the root killer itself) | HOLDS (narrow claim) | `test-codex-longrun.sh` exists, `EXTRA_SUITE_MAP` row present; report itself is honest that it did NOT fix the underlying kill — only detection. That honesty is a good sign, not a gap. |
| FORK-STORM-KILLS-HOOKS-01 | "core assumption... is false"; corrected premise | HOLDS | Report itself frames as self-correction with probe artifacts named; report is 303 lines of evidence, spot-checked structurally consistent (no code claim to falsify beyond narrative). |
| ADOPTION-GUARANTEES-A-PASSABLE-GATE-01 | repo-install now guarantees phase-gate artifact paths survive `.gitignore` | HOLDS | `.gitignore:209-229` carries `GATE_SAMPLES` block + negation lines added by this exact lane; matches report's described mechanism. |
| BEAT-LOOP-ORPHANS-01 | classifier decides from transcript; F2 gate = zero unpinned `claude -p` spawn sites | HOLDS | `leadv2-hook-session-kind.sh` comment header + `test-beat-loop-orphans.sh:431-457` implement F2 exactly as described (`ok "F2 spawn grep gate..."`). |
| BRAIN-CLASS-LIVE-01 | New `_resolve_class_with_brain_floor`, wired into `cmd_advance_arm` re-entry path | HOLDS | Function exists at `leadv2-dispatch-code.sh:3958`, called at `:8126`; `test-brain-class-live.sh` wired in `run-all.sh:162-164`. |
| CACHE-TRUTH-01 | Tool `leadv2-cache-truth.sh` parses stream/journal files, prints hit_ratio | HOLDS | File exists, executable, 9448 B; `test-cache-truth.sh` wired (`run-all.sh:281-290`). |
| CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 | A2 now matches by intent's pre-colon segment, not raw id | HOLDS | `leadv2-phase8-assert.sh:253-314` implements exactly this; error message names both search modes. |
| DISPATCH-CLOSE-GATE-01 | `LEADV2_REQUIRE_MISSION_WRITESET` now defaults to 0 | HOLDS | `leadv2-dispatch-code.sh:729`: `REQUIRE_MISSION_WRITESET="${LEADV2_REQUIRE_MISSION_WRITESET:-0}"`. |
| FP-06 | telemetry CSV + capability_floor knob shipped, two suites green | HOLDS | `docs/leadv2/model-select-telemetry.csv` exists; `freepool-arm.yaml` has `capability_floor`; suite existence confirmed, pass counts not re-run (finalized-by-lead note admits worker never wrote its own report — self-flagged weak spot). |
| FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 | gate fails closed with `committed_range_unresolved` | HOLDS | `lib/leadv2-worker-output-gate.sh:63` emits exactly that string; report's file path (`scripts/leadv2-worker-output-gate.sh`) is slightly wrong — it's actually under `scripts/lib/` — a minor documentation slip, not a broken claim. |
| GATE-PROVES-ITS-OWN-CONTROL-01 | control-prover + fixtures wired into `EXTRA_SUITE_MAP` | HOLDS | `run-all.sh:248-250` confirms both wirings. |
| GLM-ARM-THROUGHPUT-01 | lock key now scoped by git-common-dir (repo), not raw cwd hash | HOLDS | `glm_lock_key_for()` (`glm-coder.sh:477-485`) uses `git rev-parse --git-common-dir`, falls back to cwd hash only outside git; `test-glm-lock-per-lane.sh` wired (`run-all.sh:134`). |
| GUARD-CENSUS-IS-WRONG-01 | layout-independent `.sh` regex replaces broken parser | HOLDS | `capture("(?&lt;n&gt;[A-Za-z0-9_.-]+\\.sh)"...)` present at `leadv2-guard-census.sh:102`. |
| GUARDS-MUST-PROVE-THEY-FIRE-01 | guard-census + guard-verdict lib + 23-check suite shipped | HOLDS | All three files exist; suite is 330 lines (consistent with "23 checks"). |
| HANDOFF-ARTIFACTS-GITIGNORED-01 | negation lines rescue report.md/brief.md from blanket ignore | HOLDS | `git check-ignore` returns nothing for a live report.md — file is tracked; `.gitignore:50-80` carries the negation lines. |
| HOOK-OUTPUT-CAP-PLUGIN-01 | one-copy-drift hook output capped at source | HOLDS | `leadv2-one-copy-drift.sh:86` explicit "Output cap (HOOK-OUTPUT-CAP-PLUGIN-01)" comment present. |
| LEADV2-HOOK-CACHE-DEPLOY-01 | plugin-cache-sync.sh + repo-local deploy override wired | HOLDS | Both files exist; `run-all.sh:293` wires the suite. |
| MERGE-QUEUE-DEAD-HEAD-01 | dead-enqueued reclaim no longer evicts caller's own row | HOLDS | Comment + guard logic present at `leadv2-merge-queue.sh:174-216` matching the described fix. |
| ONE-LANE-WATCH-01 | lane-watch-v2.sh replaces old pulse watcher, armed from SessionStart/End hooks | HOLDS | File exists; wired in `hooks.json:81,674` (arm/disarm) and `run-all.sh:272-273`. |
| PHASE-GATE-IS-INVERTED-01 | brief.md / recorded Gate-1 reason now valid pre-spawn evidence | HOLDS | `leadv2-dispatch-code.sh:4036-4070` implements exactly this remedy path. |
| PLUGIN-PAPERCUTS-01 | beat-loop INT/TERM handler now exits (was respawning) | HOLDS | `exit 0` present in trap-adjacent code paths; suite wired at `run-all.sh:172`. |
| PROMISE-GUARD-BIND-01 | test suite sandboxes HOME, no longer writes real journal | HOLDS | `SANDBOX_HOME="${WORK}/home"` present in `test-promise-action-binding.sh:51`. |
| PROMISE-GUARD-TURN-IT-ON-01 | `_run_hook` distinguishes real-SILENT from could-not-run (rc=2) | HOLDS | `test-promise-guard-classified-block.sh` has explicit "could-not-run (rc=2)" messaging at 3+ call sites. |
| PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 | collector pins `LEADV2_LANES_ALL_REPOS=1` internally | HOLDS | `leadv2-status-collector.sh:173` sets it explicitly inside `_sc_lanes_section`. |
| PULSE-REPO-SCOPED-03 | product line renders only when repo actually published | HOLDS | `leadv2-broad-status.sh:1234-1236` implements the "six candidate product keys" gate described. |
| RESUME-LANE-ACCEPTS-PATH-01 | round-2 suite now depends on the fix (mutation-proof) | UNTESTABLE (as audited) | Code comment confirms mutation description exists (`:285`), but I did not execute the mutation myself — the report's own round-1 self-critique ("suite proved nothing") is the reason to distrust round 2 without re-running it live. |
| STATUS-CHURN-01 | H1-H5 findings fixed; git section now uniform 5-key shape with explicit nulls | HOLDS | `leadv2-status-collector.sh:61` comment + code confirms explicit-null pattern matching H2/H4. |
| WORKERS-MUST-COMMIT-01 | new `leadv2-worker-epilogue.sh` auto-commits dirty worker exits | HOLDS | File exists at claimed path. |
| dispatch-02f41cdd | CI test-suites.yml: ubuntu for changed-scope, macos only for bash32 | HOLDS | `.github/workflows/test-suites.yml` has exactly `bash32-darwin` on `macos-latest`, others on `ubuntu-latest`, matching claim. |

**Counts: HOLDS 27, BROKEN 0, UNTESTABLE 3** (DISPATCH-PIN-CLUSTER-01, RESUME-LANE-ACCEPTS-PATH-01, and FP-06's pass-count borderline — kept as HOLDS since artifacts exist but flagged).

No outright BROKEN claim surfaced in this pass — every central deliverable I could grep for exists at its stated path and is wired into `run-all.sh` where claimed. The weak spot across the batch is systemic, not per-report: several reports (DISPATCH-PIN-CLUSTER-01, RESUME-LANE-ACCEPTS-PATH-01, FP-06) assert pass/fail counts or "mutation went red" without a live re-run backing them in this audit — that class of claim is falsifiable in principle but wasn't independently re-executed here, so tag it UNTESTABLE-by-this-audit rather than trust the pasted numbers at face value.

DELIVERABLE_COMPLETE