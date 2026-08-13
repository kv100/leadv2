# ARM-PRODUCES-NOTHING-02 — architect prepass

Repo: `~/Projects/leadv2` (plugin source). Base: `worktree-621328a0` @ `3bffb24`. Nothing is
thrown away; this is a delta on top of that commit.

## 1. Root cause, stated precisely

`pc_silent_arm_probe` (product-close, inserted at ~L1258 before `pc_scope_diff`) returns rc0
(silent) when ALL of:

1. `${HANDOFF}/developer.stream.jsonl` absent, or present with zero `"type":"assistant"` events;
2. stream not fresh (or absent — the growth guard only applies when the file exists);
3. `_lane_root` resolves to a git worktree AND `_pc_lane_dirty` says clean.

C3-clean-anti-rescue in `test-lane-diff-single-repo.sh` constructs **exactly that state**: a
freshly-`ensure`d lane worktree (clean), and no `developer.stream.jsonl` is ever written because
no worker is ever spawned. So the probe fires, short-circuits at `exit 5`, and the terminal line
reads `cause=arm_produced_nothing` where C3 asserts `cause=empty_diff`. 4/0 → 3/1.

This is a semantic collision, not flakiness: two fixes from 2026-08-04 both claim the byte-clean,
stream-less lane. The worktree cannot discriminate (identical in both) and neither can the diff
(empty in both).

## 2. The discriminator (lead's decision — encoded, not relitigated)

**Was an arm ever registered for this lane?**

| lane state | arm registered? | terminal | cause | owner |
|---|---|---|---|---|
| clean tree, no stream | **yes** | `no_work` | `arm_produced_nothing` | silent-arm probe (+ `_pc_arm_advance`) |
| clean tree, no stream | **no** | `no_work` | `empty_diff` | existing empty-diff path (C3, untouched) |

C3's expectation does not move. The probe becomes strictly narrower than it is on `3bffb24`.

### 2.1 Which existing record to use — survey and verdict

| candidate record | written at spawn? | survives to close time? | readable by close gate? | verdict |
|---|---|---|---|---|
| journal `worker_spawned by=router model=… task=…` | yes | yes | **no** — `LEADV2_JOURNAL_BIN` is `/bin/true` in the lane-diff suite and is a best-effort sink in prod | reject as the *primary* gate |
| dispatch reserve/confirm ledger `"state":"confirmed"` row | yes | yes | only via `dispatch_ledger_file` in dispatch-code; product-close has no reader and the file is cache-dir-scoped | reject (already used by `cmd_advance_arm` for a different purpose — sig8 admission proof, not arm identity) |
| `LAST_WORKER_HANDLE` / handle string | yes | in-process only | no | reject |
| `${HANDOFF}/developer.stream.jsonl` | by the worker, not the dispatcher | — | this is the very signal whose absence is being classified | reject (circular) |

**Verdict: no existing record survives to close time on a path the close gate can read.** Per the
mission, making one is part of this task. The honest fix is a boolean written at spawn.

### 2.2 The new record — `arm-registered`

Path (by convention, derived identically on both sides):

```
<PROJECT_ROOT>/docs/handoff/dispatch-<sig8>/arm-registered
```

which is `${HANDOFF}/arm-registered` inside product-close (`HANDOFF` is set at L83 from the same
`ROOT`/`TASK` pair). Chosen over the cache dir because the handoff dir is the one location both
processes already agree on by convention, it is already the probe's own working directory, and it
is trivially constructible in a test fixture.

Format — **append-only, one line per spawn**:

```
arm=<arm> handle=<handle> epoch=<unix_ts>
```

Append, not truncate: `advance-arm` re-spawns a second arm on the same sig8, and the probe must be
able to see the registration of whichever arm is currently being closed. Both writes are
best-effort (`|| true`) — a failed write degrades to today's pre-`3bffb24` behaviour, never to a
false verdict.

Env override for test isolation and for a future non-conventional handoff root:
`LEADV2_DISPATCH_ARM_REGISTERED_FILE` (absolute path; when set, both sides use it verbatim).
Naming conforms to the `LEADV2_*` prefix used throughout both scripts — no `LEAD_V2_*` drift.

## 3. Data flow (numbered)

1. `cmd_resolve` candidate loop picks `${candidate}`; `atomic_dispatch_reserve_spawn_confirm`
   calls `spawn_worker "${arm}" …` inside a command substitution.
2. `_spawn_worker_body` verifies liveness and reaches the terminal
   `emit decision "worker_spawned by=router model=${arm} task=${sig8} … handle=${handle}"`
   (~L1919). **NEW:** immediately before/after that emit, append the registration line.
   A file write escapes the command-substitution subshell where a global would not — this is the
   same reason the existing `leadv2-spawn-outcome.$$` temp file exists.
3. Loop calls `spawn_product_close "${sig8}" "${candidate}" …`; the close gate starts with
   `AUTHOR="${candidate}"`.
4. Close gate resolves `_lane_root`, then calls `pc_silent_arm_probe`.
5. **NEW gate, condition (0), first statement in the probe:** `_pc_arm_registered "${AUTHOR}"` —
   rc1 ⇒ probe returns rc1 (NOT silent) ⇒ control falls through to `pc_scope_diff` and the
   existing `empty_diff` path. This is the C3 path.
6. rc0 ⇒ conditions (1)(2)(3) run exactly as on `3bffb24` ⇒ `arm_produced_nothing`, `_dl_note`,
   `_pc_arm_advance`, `exit 5`.
7. `_pc_arm_advance` → `leadv2-dispatch-code.sh advance-arm` → `spawn_worker "${next_arm}" …`,
   which appends a **second** registration line for `next_arm` (step 2 applies there too, via
   `cmd_advance_arm`'s own `emit decision "worker_spawned by=arm_advance …"`). The next close gate
   is spawned with `AUTHOR="${next_arm}"` and its probe therefore also has a matching record.

`_pc_arm_advance` is reachable only from inside the silent branch, so gating the probe gates the
chain advance with it — no second gate needed.

## 4. Interface contracts

| symbol | file | signature | contract |
|---|---|---|---|
| `_dispatch_arm_registered_file` | `leadv2-dispatch-code.sh` | `<sig8> -> path on stdout` | `${LEADV2_DISPATCH_ARM_REGISTERED_FILE}` if set, else `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/arm-registered`. Pure; no side effects. |
| `_dispatch_register_arm` | `leadv2-dispatch-code.sh` | `<sig8> <arm> [handle] -> always rc0` | `mkdir -p` the dirname, append `arm=<arm> handle=<h> epoch=<ts>`. Every failure swallowed (`|| true`). Never writes an empty `arm=`. |
| `_pc_arm_registered_file` | `leadv2-dispatch-product-close.sh` | `-> path on stdout` | `${LEADV2_DISPATCH_ARM_REGISTERED_FILE}` if set, else `${HANDOFF}/arm-registered`. |
| `_pc_arm_registered` | `leadv2-dispatch-product-close.sh` | `<author> -> rc0 registered, rc1 not` | rc0 iff the file exists, is readable, is non-empty, AND contains a line whose `arm=` token equals `<author>` exactly. If `<author>` is empty, rc0 iff the file is non-empty. **rc1 on every other outcome, including any read error** — fail-closed to the pre-existing `empty_diff` path. |
| `pc_silent_arm_probe` | `leadv2-dispatch-product-close.sh` | `-> rc0 silent` | unchanged except a new first line: `_pc_arm_registered "${AUTHOR}" \|\| return 1`. Conditions (1)(2)(3) byte-identical to `3bffb24`. |

**Token-identity requirement (CRITICAL for the implementer to verify, not assume):** the string
written as `arm=` in step 2 must be the identical token later passed as product-close's 3rd
positional (`AUTHOR`). In the candidate loop these are `${arm}` (inside
`atomic_dispatch_reserve_spawn_confirm`) and `${candidate}` (at the `spawn_product_close` call
site). Confirm they are the same value before relying on exact match; if they can diverge (any
normalization step between them), write the registration from the `spawn_product_close` call site
instead, where `${candidate}` is directly in scope. Do NOT paper over a mismatch with a substring
or prefix match — that reintroduces the "close enough" behaviour this task exists to remove.

## 5. Files changed

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | add `_dispatch_arm_registered_file`, `_dispatch_register_arm`; call the writer at the `worker_spawned by=router` site (~L1919) and at the `worker_spawned by=arm_advance` site in `cmd_advance_arm` |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | add `_pc_arm_registered_file`, `_pc_arm_registered`; add the one-line gate at the top of `pc_silent_arm_probe`; extend the doc block above the probe to state who owns the empty lane |
| `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` | **existing cases must now create the registration file** (they currently do not and would all flip red); add the negative twin case |
| `plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` | add C5, the positive twin of C3; C3 body itself untouched |

No DB schema, no migration, no contracts/ JSON — this change is entirely inside two Bash scripts
and their suites.

## 6. The discriminator test — encoded in BOTH suites

The pair must be a *minimal* pair: identical clean worktree, identical absent stream, differing
only in the presence of `docs/handoff/dispatch-<sig>/arm-registered`.

**`test-lane-diff-single-repo.sh` — new `C5-registered-arm-silent`.** Clone `case_c3_clean_anti_rescue`
verbatim, then before `run_gate`:

```
mkdir -p "${root}/docs/handoff/dispatch-c5sig001"
printf 'arm=sonnet handle=PID=0 epoch=0\n' > "${root}/docs/handoff/dispatch-c5sig001/arm-registered"
```

`run_gate` passes `sonnet` as AUTHOR already (7th positional of the close gate call), so the
`arm=` token matches. Assert `terminal=no_work` AND `cause=arm_produced_nothing`. Register it in
`run_all_cases`; the suite target becomes **5/0**. C3 keeps asserting `cause=empty_diff` and
becomes the negative half of the pair. Extend the header comment block (lines 7–13) to name the
pair explicitly.

Note for the implementer: `_pc_arm_advance` will fire in C5. It is inert here — `LEADV2_JOURNAL_BIN=/bin/true`
means the chain-CSV journal fallback returns empty and `LEADV2_DISPATCH_CANDIDATE_ARMS` is unset,
so it exits at `reason=chain_exhausted` without spawning anything. Verify that holds; if it does
not, set `LEADV2_ARM_ADVANCE=0` in C5's `run_gate` env — the kill switch exists for exactly this.

**`test-dispatch-silent-arm.sh` — two edits.**
(a) Every existing case that expects `arm_produced_nothing` must write
`$ROOT/docs/handoff/dispatch-$SIG/arm-registered` containing `arm=<the AUTHOR that case passes>`
before invoking the gate. Without this the whole suite goes red — the gate is new, and these
fixtures predate it.
(b) New case, the negative twin: identical setup to case 1 (no stream, clean worktree, E2E_ON=1
REVIEW_ON=1) but **no** `arm-registered` file. Assert the terminal is NOT `arm_produced_nothing`
and that no `arm_advance` decision line is emitted. Suite target: **11/0 or better** (10 existing
+ 1, plus the `bash -n` case already counted in the 10).

Both suites now encode the same rule from opposite directions, so they cannot silently disagree
again.

## 7. Risks and mitigations

| # | risk | severity | mitigation |
|---|---|---|---|
| R1 | Token mismatch between the written `arm=` and product-close's `AUTHOR` ⇒ probe never fires ⇒ silent-arm fix is dead code that still passes its suite (because the suite writes the fixture by hand). | **CRITICAL** | Section 4's identity requirement. The implementer must trace `${arm}` → `${candidate}` → `AUTHOR` in the real code path and state the finding in the summary. The suites cannot catch this class — only the trace can. |
| R2 | A lane spawned by an OLD dispatcher closes under a NEW gate: no registration file exists, probe never fires, lane reverts to `dead / e2e_regression`. | Medium | Accepted and self-healing (one dispatch generation). Fail direction is toward the pre-`3bffb24` status quo, never toward a false pass. Additive-only change; no migration needed. |
| R3 | Handoff dir is not writable at spawn time ⇒ no registration ⇒ same as R2. | Low | Write is best-effort by design; the dispatcher already writes `lane-mission.md` into this exact directory on the same path (`3bffb24`), so writability is already assumed there. |
| R4 | Concurrent access: `advance-arm` appends while a close gate reads the same file. | Low | Append of a single short line is atomic enough in practice; the reader only ever tests for presence of a matching line and is idempotent. No lock needed. Documented, not hand-waved. |
| R5 | `_pc_arm_registered` matches a *substring* (`arm=sonnet` matching `arm=sonnet-thinking`). | Medium | Contract requires exact token equality — anchor the match (`^arm=<author>[[:space:]]` or field split), never a bare `grep -F`. |
| R6 | Editing `pc_silent_arm_probe`'s later conditions while adding the gate, changing behaviour the silent-arm suite already locks. | Medium | The gate is exactly one added line at the top. Conditions (1)(2)(3) must diff clean against `3bffb24`. |
| R7 | Branch sequencing: `main` holds the revert (`9fe0ee1`), so work must be based on `worktree-621328a0`/`3bffb24`, not on `main`. Building on `main` silently loses `3bffb24`. | High | The implementing lane must start from `3bffb24`. Verify `git log --oneline -1` shows `3bffb24` as an ancestor before editing. |
| R8 | Config contradiction: a second env var controlling the same behaviour. | Low | `LEADV2_ARM_ADVANCE` (kill switch for the chain advance) and the new `LEADV2_DISPATCH_ARM_REGISTERED_FILE` (path override) are orthogonal; no other usage of either name exists in the tree. Implementer confirms with one grep. |

### Constraint-checklist findings
- **Env naming:** `LEADV2_DISPATCH_ARM_REGISTERED_FILE` — conforms. ✅
- **Paths:** all four listed files exist on disk; `arm-registered` is `(to-create)` at runtime, not a repo file. ✅
- **`claude -p`:** this change introduces no `claude -p` invocation. N/A.
- **Concurrent access:** R4. ✅
- **Config contradiction:** R8. ✅

## 8. Out of scope — the implementer must NOT do these

- Do **not** relax, reword, or delete C3's `cause=empty_diff` assertion. C3 is the guard.
- Do **not** touch `pc_scope_diff`, `_pc_lane_dirty`, `_pc_git_diff`, `_pc_diff_base`, or any diff
  classification. This change adds a gate *upstream* of them and alters none of them.
- Do **not** change `_pc_next_arm_in_chain`, `_pc_stat_mtime`, or `cmd_advance_arm`'s
  confirmed-reservation admission check.
- Do **not** rewrite the silent-arm fix. Delta on `3bffb24` only.
- Do **not** run `run-core-offline.sh`. Dispatch/lane suites only.
- Do **not** commit or push. The lead merges.
- No refactors, no unrelated cleanup, no changes to `.claude/scripts/tests/` (the stale mirror —
  a separate task with its own blast radius).

## 9. Verification the implementer runs (evidence, not claim)

Base: `worktree-621328a0` + this delta.
1. `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` → 5/0, `C3-clean-anti-rescue` PASS, `C5-registered-arm-silent` PASS.
2. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` → 11/0 or better.
3. Merge-preview check (the thing that actually failed last time): apply the delta onto a scratch
   merge of `3bffb24` into `main` and rerun (1). It must be 5/0 there too — the previous round was
   green in the worktree and red on main, and only the post-merge run catches that class.

---

acceptance:
- surface: log_line
  observable: In the close gate's decision output for a lane whose worktree is clean and which
    never produced a worker stream, the `review_gate` line reads `cause=arm_produced_nothing` when
    that lane has an arm registration on record, and reads `cause=empty_diff` when it has none —
    two different causes for two lanes a human cannot tell apart by looking at the worktree.
  authored_at: 2026-08-05T00:00:00+03:00
- surface: rendered_line
  observable: The lane-diff suite's own report shows `PASS C3-clean-anti-rescue` alongside
    `PASS C5-registered-arm-silent` and a final tally of 5 passed, 0 failed — and it still shows
    that same tally after the silent-arm branch has been merged into main, which is the state that
    previously printed `FAIL C3-clean-anti-rescue`.
  authored_at: 2026-08-05T00:00:00+03:00
- surface: file_artifact
  observable: A dispatched lane's handoff directory contains an `arm-registered` file naming each
    arm that was actually spawned for it, one line per arm, so a human reading the directory can
    tell a lane that was given a worker from a lane that never was.
  authored_at: 2026-08-05T00:00:00+03:00

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh, plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh

DELIVERABLE_COMPLETE
