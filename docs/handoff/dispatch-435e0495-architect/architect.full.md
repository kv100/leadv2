# PHASES-ARE-THE-ONLY-PATH-01 — fix round 2 — implementation design

Scope: continue from `ed7adeb` in worktree `.claude/worktrees/d4d014e1`. Rebase onto
`origin/main` first, then apply the changes below. No new files outside round 1's write set.

Design principle for this round, stated once so every decision below follows from it:
**a phase is proven only by evidence that is expensive to forge and cheap to re-derive at
assert time.** Every check must be recomputable from bytes on disk at the moment of the
assert, and must fail if those bytes changed after the record was written.

---

## 0. Base

```
git -C .claude/worktrees/d4d014e1 fetch origin
git -C .claude/worktrees/d4d014e1 rebase origin/main
```

Record the resulting `origin/main` SHA and the rebased `ed7adeb'` SHA in the final report.
If the rebase conflicts, resolve in favour of `origin/main` for every file NOT in the write
set, and in favour of the lane for the write-set files.

---

## 1. F1 — review proof keyed by this lane's diff-hash

### Current defect
`leadv2-phase-record.sh:326-335` (`_verify_artifact`, case `review`) resolves
`${CACHE_BASE}/code-review-ledger/<repo-slug>.jsonl` and returns 0 on `[[ -s ]]`. That file
is repo-global and append-only, so the first review ever recorded in the repo proves the
review phase for every lane forever.

Two further facts found during discovery that the fix must account for:

- The ledger the dedup check in `leadv2-dispatch-product-close.sh:1303` reads is
  `${LEADV2_DISPATCH_CACHE_DIR}/review-ledger/<slug>.jsonl`, but the ledger
  `record-review` actually **writes** is `${CACHE_BASE}/code-review-ledger/<slug>.jsonl`
  (`leadv2-dispatch-code.sh:362,439`). Two different directory names. Round 1 happened to
  point at the written one. Do not "fix" the product-close path in this round — it is
  outside the mission — but the verifier MUST read the *written* one
  (`code-review-ledger`), and a one-line comment must record that the two names diverge.
- Row format (`leadv2-dispatch-code.sh:1253`):
  `{"diff_hash":"<64hex>","verdict":"<V>","reviewer":"...","run_id":"...","repo":"...","ts":"..."}`

### The binding
`leadv2-dispatch-product-close.sh:1299` computes
`diff_hash = sha256(${HANDOFF}/review.diff)` — a plain file hash, no git involved. That is
the join key, and it is re-derivable by `phase-record.sh` at assert time with `shasum`
alone. **Do not reimplement the diff-scoping logic** (`pc_scope_diff`, `_pc_git_diff`,
`_pc_diff_base` — ~90 lines of merge-base and throwaway-index handling) inside
`phase-record.sh`; duplicating it would create a second, drifting definition of "the lane's
diff".

### Changes

**(a) `leadv2-phase-record.sh` — `cmd_record`: accept and persist `--diff-hash`.**

| flag | value | stored as |
|---|---|---|
| `--diff-hash <64hex>` | canonical diff hash for this lane | `diff_hash: <hex>` line in `phases.d/<phase>.yaml` |

Validate hex/length; a malformed value is a config error → `exit 4` (the guard already
refuses on rc 4 in every mode, including `0`).

**(b) `leadv2-dispatch-product-close.sh:1527` — pass it.**
`diff_hash` is already a global at that point. Append
`--diff-hash "${diff_hash}" --artifact "docs/handoff/${TASK}/review.diff"` to the existing
`record ... review --status done` call. The `--status running` call at line 1255 stays
as-is (running is never "proven").

**(c) `leadv2-phase-record.sh` — `_verify_artifact` case `review`, three conjunctive checks:**

1. `diff_hash` is present and well-formed in the phase record → else fail
   `review:no_diff_hash`.
2. The recorded artifact exists and `sha256(artifact) == diff_hash` → else fail
   `review:diff_tampered`. This is what makes overwrite-after-record detectable: the
   ledger row keys on the diff bytes, so mutating `review.diff` invalidates the row.
3. `code-review-ledger/<slug>.jsonl` contains a row whose `diff_hash` equals that value
   **and** whose `verdict` is a passing verdict → else fail `review:no_ledger_row`.

Match with a fixed-string grep on the exact serialized fragment the writer emits, then
parse the verdict off the matched row:

```
row="$(grep -F "\"diff_hash\":\"${dh}\"" "$ledger_file" | tail -1)"
[[ -n "$row" ]] || return 1
verdict="$(printf '%s' "$row" | sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p')"
case "$verdict" in PASS|pass|APPROVE|approved) return 0 ;; *) return 1 ;; esac
```

Accepted-verdict vocabulary: take it from whatever `record-review` is called with in
`leadv2-dispatch-product-close.sh:1508` (`${verdict}`) — grep the surrounding block for the
literal values it can hold and enumerate exactly those; do not invent new ones. If the set
is not statically determinable, treat only `PASS` as passing and journal the rejected
verdict verbatim so a false negative is visible rather than silent.

**Repo-slug consistency.** `_verify_artifact` derives the slug from
`basename ${LEDGER_REPO_ROOT:-${PROJECT_ROOT}}` while the writer uses `repo_slug()` in
`leadv2-dispatch-code.sh`. Read `repo_slug()` and make the verifier's derivation
character-identical, or the lookup silently misses in exactly the repos that matter
(symlinked plugin checkouts). If the two cannot be made identical without touching
non-write-set files, prefer the `"repo":"..."` field on the matched row over the filename
and glob every `*.jsonl` under `code-review-ledger/`.

---

## 2. F2 — `artifact_sha256` must be read back, plus real per-phase assertions

### Change (a) — universal re-hash gate, before any per-phase logic

At the top of `_verify_artifact`, when the phase record carries a non-empty `artifact`:

1. Resolve it the same way `cmd_record` did (`${PROJECT_ROOT}/${artifact}` first, then the
   bare path — mirror lines 424-428 exactly, or better, extract that resolution into a
   shared `_resolve_artifact_path` helper used by both, so record and verify can never
   disagree).
2. The file must exist and be non-empty → else fail `artifact_missing`.
3. `sha256(resolved) == artifact_sha256` → else fail `artifact_tampered`.
4. `artifact_sha256` must be non-empty when `artifact` is non-empty. A record written with
   an artifact path that did not exist at record time stores an empty sha; that record is
   **not proof** → fail `artifact_unhashed`.

Only after this passes does the per-phase switch run. This alone kills
`touch fake && record --artifact fake --status done` for every phase that requires an
artifact, and kills garbage-overwrite-after-record everywhere.

### Change (b) — per-phase content assertions

Replace every bare `-f` with a content assertion. `_verify_artifact` returns 0/1 and, on
failure, prints a machine-readable reason token on stdout (`<phase>:<reason>`) which
`cmd_assert` folds into its `missing=` output so the refusal message names *why*, not just
*which*.

| phase | proof (all conditions conjunctive, in addition to the universal re-hash gate) |
|---|---|
| `classify` | lane handoff dir exists (unchanged — classify is implied by dispatch reaching the guard) |
| `diverge` | same as classify (unchanged) |
| `plan` | `context.yaml` exists with a `decisions:` key followed by **≥1 list item** (`^\s*-\s`) before the next top-level key; OR the prepass file exists, is non-empty, contains an `acceptance:` block **and** a `LANE_WRITES:` line, and its `.sig` sidecar (if the prepass gate writes one) validates. Bare "file is non-empty" is removed. |
| `gate1` | `.gate1-passed` exists, is non-empty, and its content references the lane (`sig8` or task id). If the sentinel written by `leadv2-gate1-prompt.sh` is empty by construction, then require the sentinel **plus** the `plan` proof, and say so in a comment — never accept a zero-byte sentinel. Confirm the writer's actual content before choosing; do not guess. |
| `build` | recorded artifact is a diff/patch file that is non-empty after the re-hash gate, and contains ≥1 line matching `^diff --git ` or `^--- ` — an artifact that is not a diff is not build evidence |
| `test` | recorded artifact non-empty + re-hash OK + contains a result line the test harness actually emits. Enumerate the marker from the harness (`run-core-offline.sh` summary line) rather than inventing one; if no stable marker exists, require the artifact to contain a `FAIL: 0`-equivalent line and **journal the phase as unprovable-by-content** rather than passing it silently. |
| `review` | §1 above |
| `deploy` | the phase record carries `commit: <sha>` (new field, same `--commit` flag shape as `--diff-hash`), the SHA resolves in `PROJECT_ROOT`, and `git merge-base --is-ancestor <sha> origin/main` succeeds. Missing/unresolvable/non-ancestor → fail. Record-side: the deploy path must pass `--commit "$(git rev-parse HEAD)"`. **If no in-write-set script currently records the `deploy` phase, do not add a new recorder** — the verifier still requires the field, so `deploy` is simply never proven, which is correct-and-loud rather than fake-green. Note this explicitly in the report. |
| `live_verify` / `e2e` | recorded artifact + re-hash + for `e2e`, `e2e-gate-passed.flag` exists and is non-empty (`leadv2-dispatch-product-close.sh:1182` writes it with task/timestamp/scope) |
| `close` | `phase8-passed.flag` exists and non-empty (unchanged — this one was already a real flag) |

Explicit non-negotiable: after this change there must be **zero** `[[ -f "$artifact" ]] &&
return 0` forms left in `_verify_artifact`. Grep the function for `-f` in the final diff and
show it in the report.

### Change (c) — backward compatibility

Existing phase records written by `ed7adeb` lack `diff_hash`/`commit` and may lack a sha.
They will now fail verification. That is intended and is the point of the task; the default
mode is `warn`, so the effect on live lanes is a journal line, not a refusal. Do **not** add
a grandfather clause.

---

## 3. F3 — test `cmd_resolve` end to end

`test-phase-precondition.sh` is rewritten to drive `leadv2-dispatch-code.sh resolve`, not
`phase-record.sh assert`. Keep the existing assert-level cases (they are cheap and still
valid) but move them into a clearly-labelled `## unit` section; the new `## integration`
section is the deliverable.

### Harness

Reuse the stub conventions from `tests/test-backlog-pump.sh` (§stubs, lines 45-97) and the
launcher-override env vars documented at `leadv2-dispatch-code.sh:29,1636-1648`:

```
export LEADV2_PROJECT_ROOT=$TMP
export LEADV2_DISPATCH_CACHE_DIR=$TMP/.cache
export LEADV2_JOURNAL_BIN=<stub appending "$@" to $JOURNAL_LOG>
export LEADV2_DISPATCH_GLM_BIN=<stub: append "SPAWNED $*" to $SPAWN_LOG; print a handle>
export LEADV2_DISPATCH_SUBSESSION_BIN=<same>
export LEADV2_DISPATCH_CODEX_BIN=<same>
export LEADV2_DISPATCH_KIMI_BIN=<same>
```

The stub launcher must print a **non-empty handle** on stdout, because `spawn_worker()`
treats an empty handle as a launch failure (`leadv2-dispatch-code.sh:1899`) and the
reservation is then aborted — which would make "no spawn happened" ambiguous between
"guard refused" and "stub misbehaved". Assert spawn/no-spawn on `$SPAWN_LOG` existence, and
independently on the journal's `worker_spawned` line. Do **not** use `--no-spawn`: it makes
every case vacuously "no worker spawned".

### Required cases

| # | setup | `LEADV2_REQUIRE_PHASES` | expected |
|---|---|---|---|
| I1 | lane with no phase records, class Standard | unset | journal contains `phase_precondition_warn` naming `plan` and `gate1` in `missing=`; `$SPAWN_LOG` non-empty (proceeded to spawn); resolve exit 0 |
| I2 | same lane | `1` | journal contains `phase_precondition_refused`; `$SPAWN_LOG` **absent**; resolve exit **3** |
| I3 | same lane | `0` | journal contains **no** line matching `phase_precondition_` at all; `$SPAWN_LOG` non-empty; exit 0. Assert the *absence* — that is the byte-identical-rollback claim. |
| I4 | same lane, `--phase-waiver review=x` | unset, `1`, and `0` (three sub-cases) | refused in **all three** with `exit 4` / `phase_precondition_config_error`. The refusal must come from `waivers_allowed` in plugin code, not from a config default: run with `LEADV2_PROJECT_ROOT` pointing at a tree containing **no** `phases.yaml` override, and additionally with an override that *tries* to allow `review` — both must refuse. |
| I5 (F1) | forged review: `touch fake`; `phase-record record <sig8> review --artifact fake --status done`; then `printf garbage > fake` | `1` | refused, `missing=` contains `review`; no spawn |
| I6 (F1) | honest review record (real `review.diff`, correct `--diff-hash`, PASS row in ledger) **plus** a second unrelated PASS row from another lane | `1` | proceeds. Then mutate `review.diff` by one byte → refused. This is the exact regression `ed7adeb` fails. |
| I7 (F2) | any artifact phase: record with a real artifact, then overwrite the artifact with different bytes | `1` | refused with an `artifact_tampered`-flavoured reason |
| I8 (F2) | record with `--artifact <path-that-does-not-exist>` (empty sha stored), then create the file | `1` | refused (`artifact_unhashed`) |

### Red-first evidence

Every case I1-I8 must be run against `ed7adeb` **before** the fix and shown failing, then
against the fixed tree and shown passing. Concretely: `git stash` the fix (or check out
`ed7adeb` into a scratch worktree), run the suite, capture raw output; re-run after. The
report carries both raw outputs verbatim. A case that is green in both runs is not evidence
and must be either strengthened or deleted — do not ship it as filler.

Note honestly in the report which cases were *already* green at `ed7adeb` (I1/I3 may well
be, since warn/disabled wiring does exist) and do not count those as proof of the fix.

Register the suite in `tests/run-core-offline.sh` if it is not already (round 1 added 3
lines there).

---

## 4. Non-blocking items

**(a) Stale `cmd_advance_arm` reference.** Confirmed: no such function exists; the retry
loop is inline in `cmd_resolve`. Fix the reference in the round-1 commit message's design
lineage by correcting the comment at `leadv2-dispatch-code.sh:1433-1437`
(`_phase_precondition_guard` header) and any `phases.md` line naming it. No live bypass —
state that plainly in the report.

**(b) `lane_phase()` liveness probe.** The review's framing is inaccurate and the report
must say so: `leadv2-status-surface.sh:3077-3100` already memoizes `_liveness_probe` in a
module-level dict, so within one render pass each `sig8` is probed at most once. The real
remaining cost is one 3s-timeout subprocess per *distinct running lane* per render, and the
`_liveness_probe_cache` dies with the process. Two changes, both cheap:

1. Call `_liveness_probe` only when the phase record cannot decide on its own — i.e. only
   for records in `status: running` whose `phases.d/<phase>.yaml` mtime is older than a
   staleness threshold. A record touched seconds ago needs no corroboration.
2. Bound the total probe budget per render (e.g. ≤4 probes); beyond that return `unknown`
   and let the existing `unknown` branch render. A menubar that is slightly stale beats a
   menubar that stalls.

Do not add a cross-process cache file in this round — that is a new shared-state writer and
a new race surface, outside the write set.

**(c) `phases.md` "model=skip ignored for review".** Decision: **it stays advisory.** There
is no enforcement in `leadv2-router.sh`, and adding one means editing a file outside the
round-1 write set. Change the prose so it does not read as a guarantee — state it as an
operator convention with a pointer to the fact that the mandatory-review property is
enforced by the phase gate (`review` is MANDATORY in `_resolve_mandatory`), which is the
real mechanism. The report must say in one line: "`model=skip` is not enforced in the
router; the enforcement that exists is the phase gate."

---

## 5. Risks

| risk | mitigation |
|---|---|
| Repo-slug derivation mismatch makes every ledger lookup miss → `review` never provable → in enforce mode every lane refuses | Make the derivation character-identical to `repo_slug()`, and add case I6 (honest record proceeds) which fails loudly if the lookup misses |
| Two ledger directory names (`review-ledger` vs `code-review-ledger`) | Verifier reads the written one; comment records the divergence; out of scope to unify |
| `deploy` becomes unprovable because nothing records `--commit` | Intended; default mode is `warn`, so the visible effect is a journal line. Called out explicitly in the report rather than papered over |
| Existing live lanes' `ed7adeb`-era records stop verifying | Default `warn`; no grandfather clause by design |
| Stub launcher returning an empty handle makes I2's "no spawn" ambiguous | Stub prints a real handle; assert on both `$SPAWN_LOG` and the journal |
| `sed`/`grep` JSON parsing on ledger rows is brittle if the writer's format changes | Match the exact serialized fragment the writer emits at `leadv2-dispatch-code.sh:1253`; a format change breaks the test suite, which is the correct failure |

## 6. Out of scope

- Unifying `review-ledger` / `code-review-ledger` directory names.
- Any enforcement of `model=skip` in `leadv2-router.sh`.
- Adding a `deploy`-phase recorder to any script.
- A cross-process liveness cache file.
- One-writer discipline and the `backlog-pump.sh` / `fanout-lane-launcher.sh` single entry
  point — confirmed clean by review, do not touch.
- Any widening of the round-1 write set.

## 7. Constraint checklist

1. Env vars: `LEADV2_REQUIRE_PHASES`, `LEADV2_PHASE_RECORD_BIN`, `LEADV2_DISPATCH_*_BIN`,
   `LEADV2_JOURNAL_BIN` — all `LEADV2_*`. No new env var introduced. PASS.
2. Paths: every path named above exists on disk except `phases.d/<phase>.yaml` `diff_hash:`
   / `commit:` fields (to-create) and the rewritten integration section of
   `test-phase-precondition.sh` (to-create). PASS.
3. `claude -p`: no new `claude -p` invocation in this design. N/A.
4. Concurrent access: `phases.d/<phase>.yaml` keeps its single writer (`cmd_record`, atomic
   mktemp+mv). The ledger keeps `atomic_review_check_and_record` as its only writer. The
   verifier is read-only. No new race surface.
5. Config contradiction: `waivers_allowed` must refuse `review` from plugin code even when a
   project `phases.yaml` allows it — covered by test I4's second sub-case.

---

acceptance:
  - surface: log_line
    observable: With `LEADV2_REQUIRE_PHASES=1`, a lane whose review phase was recorded from a
      file that was afterwards overwritten produces a journal line reading
      `phase_precondition_refused ... missing=review`, and no `worker_spawned` line follows
      it for that lane.
    authored_at: 2026-08-05T00:00:00Z
  - surface: log_line
    observable: With `LEADV2_REQUIRE_PHASES` unset, the same lane produces
      `phase_precondition_warn ... missing=review` and a `worker_spawned` line still follows,
      so the lane launches.
    authored_at: 2026-08-05T00:00:00Z
  - surface: log_line
    observable: With `LEADV2_REQUIRE_PHASES=0`, the journal for that lane contains no line
      beginning `phase_precondition_` at all.
    authored_at: 2026-08-05T00:00:00Z
  - surface: file_artifact
    observable: `plugins/leadv2/scripts/tests/test-phase-precondition.sh` prints a summary
      line showing every integration case passing on the fixed tree, and the same suite run
      against `ed7adeb` prints failures for the forged-phase and tampered-artifact cases.
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: The menubar lane rows render their phase without a multi-second stall when
      several lanes are running.
    authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-phase8-close.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/docs/phases.md, plugins/leadv2/scripts/tests/test-phase-precondition.sh, plugins/leadv2/scripts/tests/test-phase-record.sh, plugins/leadv2/scripts/tests/test-lane-phase-render.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
