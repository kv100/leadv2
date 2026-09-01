# STATUS-CHURN-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/STATUS-CHURN-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/leadv2-lanes-snapshot.sh,plugins/leadv2/scripts/leadv2-lane-liveness.sh,plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/lib/leadv2-status-cache.sh,plugins/leadv2/scripts/leadv2-spawn-rate.sh,plugins/leadv2/scripts/tests/test-status-churn.sh,tests/run-all.sh,docs/handoff/STATUS-CHURN-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md` or `docs/handoff/dispatch-nw*` (`git checkout -- …` before each commit; commit by
LANE_WRITES pathspecs). Round 1 had no `report.md` — write it and `git add -f` it. An uncommitted exit
is a failed round.

## Review verdict on round 1 (reviewer glm) — FAIL, high=2
1. `lib/leadv2-status-cache.sh:174` — the cache library is wired into ZERO consumers. The diff touches
   only lib + instrument + test + run-all, so production behaviour is unchanged and the churn the task
   exists to remove persists.
2. `leadv2-spawn-rate.sh:125` — live `ps` sampling is non-functional on macOS: `etimes` is not a
   supported keyword and `comm=` prints `bash`, not the script name, so the acceptance instrument's ps
   half always reports zero observations (a false-zero instrument).

## Do
1. Wire the cache into the real consumers named in LANE_WRITES (`leadv2-broad-status.sh`,
   `leadv2-status-collector.sh`, `leadv2-lanes-snapshot.sh`, `leadv2-lane-liveness.sh`,
   `leadv2-lane-status-line-tail.sh`): each repeated probe (registry read, worktree git status, stream
   mtime, quota read) goes through the cache with the TTL the brief set. Prove it with the instrument:
   before/after counts of spawned subprocesses per status call (`spawn-rate` on one status run), paste
   both numbers in report.md. A consumer that is not wired is listed with a one-line reason.
2. Fix the instrument for macOS: use `ps -o etime=` (parse `[[dd-]hh:]mm:ss`) or `lstart`, and
   `command=` (full argv) instead of `comm=`; match the script by its path in argv. Suite case: on this
   machine the ps half returns ≥1 observation for a running `bash <script>` fixture; a zero is a suite
   failure, never a pass.
3. Mutation negative controls, RUN and paste red: (a) unwire the cache from one consumer → the
   spawn-count case red; (b) restore `comm=` → the ps case red. Revert both.
4. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-status-churn.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
5. `report.md`: "## Round 2 evidence" — the before/after spawn counts per consumer, ps-instrument output
   on macOS, red/green controls; commit (pathspecs only).
