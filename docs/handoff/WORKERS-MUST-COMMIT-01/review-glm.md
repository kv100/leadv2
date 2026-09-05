REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=0
FINDING: severity=Medium file=plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh line=70 dimension=correctness desc=Default value `${4:-${run_dir}/prompt.txt}` expands `run_dir` before the same `local` statement assigns it, so it resolves via bash dynamic scoping to the caller's variable — works on all 4 wired paths today, but a caller without a `run_dir` in scope gets a silent no-op (reads `/prompt.txt` → `undeclared_lane_writes`, commits nothing) or, under `set -u`, a fatal abort that `|| true` cannot rescue

## Verification of prior findings (by execution)

**Prior finding 1 [High/correctness] untracked-directory collapse — FIXED.**
- Diff now uses `git status --porcelain --untracked-files=all` (epilogue, status probe) and classifies per-file; on-disk file at worktree HEAD `48a5140` is byte-identical to the diff's version (`diff` → `IDENTICAL`).
- Execution probe (temp git repo, exact `cmd_supervise` shape with `set -euo pipefail`, brand-new untracked dir containing one in-scope and one foreign file): `src/newdir/target.py` **committed**, `src/newdir/sibling.py` left dirty and named — `worker_exit=dirty auto_committed=2 foreign_dirty=2`, `foreign_dirty=…src/newdir/sibling.py`. rc=0, caller survived.
- Suite: `test-worker-commit-epilogue: 8 passed, 0 failed` (incl. `case_e_new_dir_in_scope_committed`, `case_f_new_dir_out_of_scope_listed`).

**Prior finding 2 [High/design] epilogue on 1 of 3 coder paths — FIXED.**
- Grep evidence of wiring after `deadhand_check`, before the outcome classifier: `glm-coder.sh:1741`, `kimi-coder.sh:1580`, `freepool-coder.sh:1823`, plus a 4th arm beyond the finding's ask: `claude-subsession.sh:1123` (sync) and `:1282` (bg waiter).
- Suite `case_g_all_arms_wire_epilogue` PASS; `bash -n` clean on all 5 files; pre-existing `test-lane-outcome: 8 passed, 0 failed` (the diff maps `glm-coder.sh` → it in tests/run-all.sh:230; that map is a line-parsed string, so the two `glm-coder.sh:` rows coexist — verified at tests/run-all.sh:57/300).

## New finding detail (introduced by this fix, latent — not reachable on any wired path)

`leadv2-worker_commit_epilogue` line 70: `local run_dir="$1" … prompt_file="${4:-${run_dir}/prompt.txt}}"` — bash expands all words of the `local` command before any assignment lands, so `${run_dir}` resolves to whatever `run_dir` is visible via dynamic scope:
- **Coder paths** (3 args, `$4` unset): resolves to `cmd_supervise`'s `local run_dir` — verified working by execution.
- **claude-subsession paths**: always pass `$4` (`MISSION_FILE`, mandatory: claude-subsession.sh:71 usage-gate, :186 existence-gate) — default never expands.
- **Any other caller**: without `-u`, function reads `/prompt.txt` → `undeclared_lane_writes` no-op (verified: probe returned `auto_committed=0`, nothing committed); with `-u`, fatal `run_dir: unbound variable` and the surrounding script exits rc=1 — `|| true` does **not** rescue (verified on bash 3.2.57 and 5.3.9, /tmp/t32b.sh).

Fix is one line: split into two `local` statements (`local run_dir="$1" …; local prompt_file="${4:-${run_dir}/prompt.txt}"`).

---

**Finish report:** files changed: none (review-only, no edits). Tests: `test-worker-commit-epilogue` 8/8 PASS, `test-lane-outcome` 8/8 PASS, `bash -n` ×5 OK, 4 execution probes run (2 exposed the latent fragility, 2 confirm the fixes). No stash created. NOT-COMMITTED — review produced no worktree changes to commit.
