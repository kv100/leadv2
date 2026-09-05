# RECOVER-WAVE1-TEN-01 — report

Round 2: four remaining branches, merged bottom-up by volume. One line per branch,
ten total (six landed in round 1, described by their merge commits below).

## Round 1 (already in main)

1. `worktree-d784b987` → merged as `4ee5bc8d` (CLAIM-EVIDENCE-GATE-01; all four hunks HEAD-side, branch inserts auto-merged, add/add suite → HEAD superset).
2. `worktree-BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01` → merged as `678f7dea` (single-lead-beat.sh union: HEAD resolver routing + branch epoch machine; suites 7/0, 25/0, 6/0).
3. `worktree-PLUGIN-RELIABILITY-01` → merged as `3424ace2` (dispatch-code 2 hunks HEAD superset; product-close hunk 1 branch D4 grace-guard — only unique piece; suite 21/0).
4. `worktree-049e0e9e` → merged as `27f3bd83` (REVIEW-GATE-INFRA-01; all 10 hunks HEAD — branch fully superseded, its round-2 already in main as 8cc6bf8c).
5. `worktree-100a892d` → merged as `2475b362` (second parent f76a205e).
6. `worktree-f7f1c2c8` → merged as `2a0e5848` (REPORT-ONLY-GATE-01 round-2; per-hunk unions recorded in the commit message).

## Round 2 (this session)

7. `worktree-83c44855` → merged as `ad4be1e3` (12 files, +1 971 claimed; actual landed delta vs pre-merge main = 4 evidence files, +315). Branch intent: never-empty review pool (dispatch-8e2a32be D1-D5 + Layer A loud resolver failure). Resolution: all 7 conflicted files resolve to HEAD because the lane's code work was ALREADY in main (leadv2-quota-error-parse.py byte-identical; dispatch-8e2a32be A2/A3/D5 markers present in main's blobs; review_rank floor incl. haiku/opus present in main's routing.yaml) — verified mechanically: branch-unique auto-merged lines vs main = 0 for every file, and each resolution is byte-identical to main (`git diff main -- <file>` empty ×7). Merge therefore carries only the branch's lane evidence (handoff docs dispatch-59a0e749, journals dispatch-567ba028/59ae8b51). NOTE: this merge was committed by a parallel session under its own message (mutation-control lane) while my resolutions were staged — parents 7a58b1b1+7afb3e43, my resolution blobs are what landed (verified: plugin delta vs 7a58b1b1 is exactly the parallel lane's 4 files, nothing from the branch's code side). Symlinks 8/8 OK after merge. Falsification: bash -n 5/5, py_compile OK; the three suites this merge resolved (byte-identical to main, so unchanged by the merge) time out at 240s in this environment — rc=124 ×3, xtrace shows the stall inside the close-gate invocation in T1 (pre-existing on main: the resolved files ARE main's bytes, a different copy of identical bytes cannot behave differently; retry at 420s also rc=124). Stray registry row dispatch-38eb8664 from the suite run is already tombstoned (dead_at + deregistered/dispatcher_exit) — no cleanup needed.
