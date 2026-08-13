# critic — LANE-TRUTH-BATCH-01 round 2 (build-r2.diff)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=1 low=2

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-plugin-sync.sh line=167 dimension=correctness desc=sha256sum failure is masked by the pipeline so the `|| return 1` guard never fires; two empty hashes compare equal and a CHANGED divergent copy is silently not quarantined while the log claims it was preserved
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh line=113 dimension=correctness desc=the Row-1 "mutation gate" is a grep-on-source (mission forbids these); mutating the stamped log_path back to pulse.md reintroduces the exact defect and the suite still reports pass=15 fail=0
FINDING: severity=High file=plugins/leadv2/scripts/tests/run-core-offline.sh line=122 dimension=correctness desc=diff is still on a stale base (run-core-offline blob cbe056c, dispatch-code blob af0d961 vs main 74a2adf/14227f8); it does not merge onto main and reintroduces duplicate suite registration for test-plugin-reliability-01/02

---

## Scope

Reviewed the code half of `docs/handoff/LTB-review/build-r2.diff` (5227 of 6825 lines;
`docs/**` excluded). Judged against the four fix-round items in
`docs/handoff/LANE-TRUTH-BATCH-01/mission.md`:

| item | requirement | status |
|---|---|---|
| 1 | rebase onto current origin/main; reconcile Row 2 with landed C5 | **NOT DONE** |
| 2 | quarantine must converge (dedupe by content hash) | done, but the hash guard is broken (H1) |
| 3 | behavioral mutation gate for dispatch-code.sh set_log_path | **NOT DONE** — grep (H2) |
| 4 | suite registered once in run-core-offline.sh | done for LTB, broken for the two reliability suites (H3) |

Evidence produced by running the suite in a scratch worktree at the diff's base with the
diff's post-image blobs installed (`/tmp/ltb-wt`, throwaway).

---

## High

### H1 — plugin-sync.sh:167 — the content-hash guard cannot fail, and a silent false match loses the un-landed fix

```bash
content_hash="$(sha256sum "${dst_file}" 2>/dev/null | cut -d' ' -f1)" || return 1
```

`sha256sum` is the *first* command of a pipeline; the assignment takes the exit status of
`cut`, which is 0 even when `sha256sum` does not exist or errors. Proven:

```
$ bash -c 'h="$(nosuchsha256sum /etc/hosts 2>/dev/null | cut -d" " -f1)" || { echo "guard fired"; exit 0; }; echo "guard did NOT fire; hash=[$h] rc=0"'
guard did NOT fire; hash=[] rc=0
```

Failure scenario: `sha256sum` unavailable (it is **not** stock macOS — this machine happens
to have `/sbin/sha256sum`, a GNU-coreutils install; a machine or a PATH-restricted hook
context without it is the normal case), or unreadable file. Then `content_hash=""`, and in
the dedupe loop every previously quarantined file also hashes to `""`, so the first
existing quarantine path for `(copy_name, relpath)` compares equal. `_quarantine_copy`
returns that stale path and **never writes the new content**, and the caller then logs:

```
DIRECTION-SAFETY (block+quarantine): ... ORIGINAL CONTENT PRESERVED at: <stale path>
```

That is a false preservation claim pointing at *different* content — the exact class of
lost work UNLANDED-FIXES-IN-USER-SCRIPTS-COPIES-01 exists to prevent, now with an
affirmative log line telling the founder the work is safe.

**Required fix:** compute the hash without a pipeline mask and fail closed on an empty
hash, e.g.

```bash
local sum_out
sum_out="$(sha256sum "${dst_file}" 2>/dev/null)" || sum_out=""
content_hash="${sum_out%% *}"
[[ -n "${content_hash}" ]] || content_hash=""   # empty => skip dedupe entirely, always write
```

and gate the dedupe block on `[[ -n "${content_hash}" ]]`. Add a hermetic case that stubs
`sha256sum` out of PATH and asserts a changed copy still produces a new quarantine file.

### H2 — test-lane-truth-batch-01.sh:113 — the "mutation gate" is grep-on-source and does not gate the behaviour

```bash
if grep -q 'leadv2_active_set_log_path' "$DISPATCH"; then
  printf '[TEST] PASS: Row 1 mutation gate: dispatch-code.sh stamps set_log_path\n'
```

`mission.md`: *"Tests: behavioral, hermetic … Grep-on-source tests are rejected."* Fix-round
item 3 asked specifically for *"the behavioral assertion that catches"* deletion of the
call. This grep catches deletion of the literal token only.

Proven regression escape — I mutated the stamped path in `dispatch-code.sh` back to the
defective value (the very Row-1 bug: liveness resolving the lead's shared pulse.md instead
of the lane stream):

```
-  leadv2_active_set_log_path "${reg_id}" "docs/handoff/dispatch-${sig8}/developer.stream.jsonl"
+  leadv2_active_set_log_path "${reg_id}" "docs/leadv2/tasks/${reg_id}/pulse.md"
```

Suite result after the mutation:

```
[LANE-TRUTH-BATCH-01] pass=15 fail=0
```

Fully green with Row 1 reintroduced. Unmutated baseline is also `pass=15 fail=0`, so the
suite has zero discriminating power over the fix it claims to gate.

**Required fix:** drive `cmd_resolve` (or the smallest extractable slice of it) in the
sandbox with a stub registry and assert on the resulting `active.yaml` row that
`log_path` equals `docs/handoff/dispatch-<sig8>/developer.stream.jsonl` — i.e. assert the
*value written*, not the presence of a call site. The Row-1 liveness assertions already in
the file (lines 78-84) are the right shape; they are just fed by a hand-call to
`leadv2_active_set_log_path` instead of by dispatch-code.sh.

### H3 — run-core-offline.sh:122 / leadv2-dispatch-code.sh:3058 — still on a stale base; will not merge, and re-duplicates two suite registrations

Blob evidence:

| file | diff pre-image | main HEAD (5239105) |
|---|---|---|
| tests/run-core-offline.sh | `cbe056c` | `74a2adf` |
| scripts/leadv2-dispatch-code.sh | `af0d961` | `14227f8` |
| scripts/leadv2-plugin-sync.sh | `4e24267` | `4e24267` ✓ |
| scripts/leadv2-active-registry.sh | `b135f40` | `b135f40` ✓ |
| scripts/leadv2-dispatch-product-close.sh | `ba2fe4e` → post `83f21f3` | `83f21f3` (already landed; no-op) |

`cbe056c`/`af0d961` are the blobs at `fb10b06`; main has since moved through `105e07f`
and `3aff255`. Three-way merge of the run-core-offline hunk against main:

```
$ git merge-file -p ours(HEAD) base(cbe056c) theirs(base+patch)
MERGE_RC=1
122:<<<<<<< /tmp/rco.ours
124:run_check "lane truth batch (log_path + quarantine convergence)" ...
126:run_check "plugin reliability (process liveness + role fallback + prepass/reorder signals)" ...
127:run_check "plugin reliability-02 (zombie-reaper: ...)" ...
```

Conflict. main **already** registers `test-plugin-reliability-01.sh` and
`test-plugin-reliability-02.sh` at lines 122-123; the diff adds both again. Round 1's
finding was "one suite registered twice"; the author fixed that instance and, by not
rebasing, recreated it for two other suites — any union-style conflict resolution
double-counts PASS and doubles runtime, which is the same defect.

Same for `leadv2-dispatch-code.sh`: main already contains `reg_id=` (3071),
`prepass_parked` (3122) and `router_v2_reorder_failed` (3641-3643) — ~48 of the diff's 50
added lines are already landed. Applying the diff's dispatch-code hunks to its own stated
base fails outright:

```
$ git apply <dispatch-code hunks>   # onto fb10b06
error: patch failed: plugins/leadv2/scripts/leadv2-dispatch-code.sh:3098
error: plugins/leadv2/scripts/leadv2-dispatch-code.sh: patch does not apply
```

so the diff is not even internally consistent about which base it was cut from.

**Required fix:** rebase onto current `origin/main` and re-cut. Post-rebase the genuine
delta for dispatch-code.sh is one line (the `leadv2_active_set_log_path` stamp) plus its
comment, and run-core-offline.sh gains exactly one `run_check`. Re-run the full
`run-core-offline.sh` after the rebase — the current rc=0 claim was measured on a tree
main does not have.

---

## Medium

### M1 — test-lane-truth-batch-01.sh:98 — Row 2's "already-fixed" verification is also grep-on-source

```bash
if grep -q 'reg_id="${founder_task_id:-dispatch-${sig8}}"' "$DISPATCH"; then
```

Same mission prohibition as H2, and it is brittle in a second way: it asserts an exact
source spelling, so a semantically identical refactor (`reg_id="${founder_task_id}"; [[ -z
… ]] && reg_id="dispatch-${sig8}"`) turns the suite red while behaviour is unchanged —
false-red on refactor, false-green on behaviour change. Replace with a behavioural
assertion that a dispatch invoked without `--task-id` produces an `active.yaml` row keyed
`dispatch-<sig8>`, or drop the check (the row is verified already-fixed by C5 elsewhere).

---

## Low

### L1 — test-lane-truth-batch-01.sh:96 — comment contradicts the code

> `# This is a grep check on the REAL dispatch script (not the fixture copy)`

`DISPATCH="${PLUGIN_DIR}/scripts/leadv2-dispatch-code.sh"` (line 39) is the sandbox copy
under `$tmp/plugin`. Content is identical today because of `cp -a`, so nothing breaks — but
the comment asserts a property the code does not have, and a future reader will trust it.
Fix the comment (or point `DISPATCH` at `REAL_PLUGIN_DIR`).

### L2 — leadv2-dispatch-code.sh:3079 — stamped stream name is unconditional `developer.stream.jsonl`

Product lanes that take the architect-prepass path (line ~3124) write
`architect.stream.jsonl`; the stamp names `developer.stream.jsonl` regardless. Benign
today only because `leadv2-lane-liveness.sh:396` guards the recorded path with
`os.path.isfile()` and falls through to its own `("developer.stream.jsonl",
"architect.stream.jsonl")` scan — so a wrong stamp degrades to the pre-existing behaviour
rather than to a false dead. Worth a one-line comment recording that the `isfile` guard is
what makes the unconditional name safe, so nobody later "optimises" that guard away.

---

## What is correct in this round

Stated for completeness, not as approval:

- The `set_log_path` registry op (`leadv2-active-registry.sh:409-421`) mirrors `set_writes`
  exactly, including `sys.exit(4)` on an unregistered task, and re-`register` preserves it
  (`existing["log_path"] = existing.get("log_path") or pulse_log`, line 186) — so the stamp
  is not clobbered by fanout's finalize register. Verified by reading, not by the author's claim.
- Row 3 convergence works when `sha256sum` is present: 3 extra syncs of an unchanged
  divergent copy yield 1 quarantine file, and changed content yields a second (1 → 2).
- Dry-run correctly writes no quarantine.
- Item 4 is genuinely fixed for the LTB suite itself: one `run_check`, one label.

## Type/lint evidence

No Python or TypeScript in the code half of this diff other than the registry's embedded
heredoc; `mypy --strict` / `tsc --noEmit` are not applicable. Hard evidence used instead:
suite execution (`pass=15 fail=0` baseline and post-mutation), `git merge-file` conflict
output, `git apply` failure output, and the pipeline-masking repro — all inline above.

DELIVERABLE_COMPLETE
