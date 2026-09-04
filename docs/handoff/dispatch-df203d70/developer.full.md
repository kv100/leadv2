verdict: APPROVE
next_action: deploy

# CODEX-BATCH-REVIEW-FIXROUND-01 — developer full report

## Census corrections (discovery falsified two parts of the design)

**Item 2 test location.** The design said "add three cases to
`plugins/leadv2/tests/test-deny-floor.sh`." Reading that suite showed it only
invokes `hooks/leadv2-deny-floor.sh`, which loads
`config/leadv2-deny-patterns.yaml` — never `deny-extra.yaml`. The
`codex_exec_direct` rule lives in `deny-extra.yaml`, loaded only by
`lv2guard.sh`, exercised by `codex-lead/tests/test-lv2guard.sh` (which
already had a `codex exec 'x'` case at line 113). Regression cases were added
there instead; `test-deny-floor.sh`'s fragment-drift loop already covers
`deny-extra.yaml` for the unrelated GITGLOBAL check and stays green.

**Item 3 target files missing.** This lane's worktree (branch tip e3ed68c)
predated the commits (`8b447ca`..`4a72566` on `main`) that introduced
`leadv2-subagent-lifecycle.sh`, `leadv2-native-pulse.sh`,
`test-codex-hooks.sh`, and `test-codex-native-pulse.sh`. None of the four
existed in this worktree. Verified `HEAD` was a clean ancestor of `main` (no
divergence, no conflicting edits to any of this lane's 3 already-modified
files on `main` since the base) and fast-forwarded
(`git merge --ff-only main`) before applying the item-3 fix, rather than
hand-reconstructing stale copies (an earlier attempt at that — materializing
via `git show main:<path>` at a moment when local `main` was itself mid-move
— produced a pre-review version of `lv2guard-pretooluse.sh` lacking
`apply_patch` handling and caused 7 spurious test-codex-hooks.sh failures;
diagnosed and discarded before the fast-forward).

**Item 4** `ZZ-pre-review-run.sh` is untracked and was never present in this
worktree (confirmed via the main checkout's `git status` showing it there,
`??`, but `ls`/`find` here return nothing) — no delete needed in this lane;
`.gitignore` change applied as specified.

## Changes (commit 0daf5af on branch worktree-df203d70)

1. `plugins/leadv2/codex-lead/deny-extra.yaml:42` — `codex_exec_direct` regex
   changed from `'(^|[;&|]\s*)codex\s+exec\b'` to `'\bcodex\s+exec\b'`.
2. `plugins/leadv2/codex-lead/tests/test-lv2guard.sh` — 3 new bypass-shape
   assertions after the existing `codex exec 'x'` case: `env codex exec 'x'`,
   `/usr/local/bin/codex exec 'x'`, `xargs -I{} codex exec {}`, all expect
   rc 97.
3. `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh` — liveness stub
   now emits real JSON (`{"lane":...,"verdict":"alive","reason":"process_alive","age_s":5,"pid_alive":true}`
   / dead variant with `verdict":"dead:silent_9999s_no_process"`) instead of
   plain text. Added a contract case that calls the real
   `leadv2-lane-liveness.sh --project-root <TARGET> --lane <nonexistent> --no-codex --json`
   and asserts the object carries `verdict`/`reason`/`age_s`.
4. `plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh`
   — wrapped the python body in `try: ... except SystemExit: pass / except
   Exception: pass`, added trailing `exit 0`. Happy-path behaviour (registry
   file content, filename hashing, atomic `os.replace`, tmp cleanup) is
   byte-identical.
5. `plugins/leadv2/codex-lead/tests/test-codex-hooks.sh` — new cases:
   start/stop against a `chmod 0500` unwritable registry dir (both assert
   rc 0, trap restores `chmod u+w` before cleanup), plus a normal
   writable-dir start regression case asserting the registry json is still
   written.
6. `.gitignore` — added `docs/leadv2/burn-deferred.jsonl` and
   `docs/leadv2/burn-deferred.d/` beside the existing `bus.jsonl` /
   `merge-queue.jsonl` runtime-artifact lines, with a one-line comment naming
   them as the burn-governor runtime ledger.

## Deployment caveat (item 3, not a code change)

Per the design: hooks are the one exception to one-inode. This fix lands in
the repo/marketplace source tree; the installed plugin *cache* is a separate
copy and `claude plugin update` no-ops for a directory-source marketplace
when content changed but the version did not. Landing here does not make the
fixed hook run for existing sessions — a version bump or a manual cache copy
+ session restart is required. Not done as part of this lane (out of
LANE_WRITES scope; flagging per the design's own instruction).

## Self-check (falsification set)

`bash -n` on every changed shell file: all OK (see raw output below).
No python files were changed directly (only an embedded heredoc inside the
`.sh` hook); parsed the embedded body with `ast.parse` — OK.

```
OK: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh
OK: plugins/leadv2/codex-lead/tests/test-codex-hooks.sh
OK: plugins/leadv2/codex-lead/tests/test-lv2guard.sh
OK: plugins/leadv2/scripts/tests/test-lane-placement-pin.sh
OK-python (embedded heredoc ast.parse)
```

## Required suites — raw output (final run, all green together)

```
=== test-deny-floor.sh ===
PASS: fragment-drift: every git rule in deny-extra.yaml carries GITGLOBAL

51 passed, 0 failed
=== test-lv2guard.sh ===
===================================================
PASS: 78  FAIL: 0
===================================================
=== test-lane-placement-pin.sh ===
[TEST] PASS: contract: leadv2-lane-liveness.sh --json emits a JSON object with verdict/reason/age_s

[LANE-PLACEMENT-01] passed=25 failed=0
=== test-codex-hooks.sh ===
[PASS] pulse emits no permission decision ()
[PASS] pulse emits no permission decision with INJECT=1 ()
[SUMMARY] pass=32 fail=0
=== test-codex-native-pulse.sh ===
[PASS] default path: payload-cwd subdir resolves project, real surface answers
[PASS] default path: non-project cwd renders ? and exits 0
[SUMMARY] pass=19 fail=0
=== test-codex-plugin-manifest.sh ===
[TEST] PASS: adapter: missing python3 -> deny still emits (pure-bash emitter)

===================================================
PASS: 44  FAIL: 0
===================================================
```

(Ran each suite's full stdout during development — every case in every
suite showed PASS, no truncation; excerpts above are the tail of each run
plus the summary line. Total 249 cases across the 6 required suites, 0
failures.)

## Not touched (non-goals honored)

`leadv2-review-run.sh` fanout default, selector/profile-select files,
`leadv2-worktree-protected.sh` pid-liveness, the untracked divergent
`.claude/scripts/tests/test-lane-placement-pin.sh`, no deny-floor parser
refactor, no new env vars/scripts.

## Fast-forward note (repo-hygiene, not a lane edit)

`git merge --ff-only main` moved this branch from `e3ed68c` to `4a72566`
(49 files, all already-committed mainline history, zero new diffs
introduced by this lane beyond the 6 files listed above). Verified
before merging that none of the 3 files this lane had already edited
(`deny-extra.yaml`, `test-lv2guard.sh`, `test-lane-placement-pin.sh`) were
touched by `main` since the lane's original base, so no edits were at risk.

DELIVERABLE_COMPLETE
