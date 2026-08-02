# N1-EMPTY-LANE-IS-NOT-A-PASS — architect prepass

Base `0f71b75`. Repo: canonical `~/Projects/leadv2/plugins/leadv2/`.
This is a **design**, not an implementation. No code was written.

Mirror of this file also written to `~/Projects/leadv2/docs/handoff/N1-EMPTY-LANE-IS-NOT-A-PASS/deliverable.md`.

---

## 0. What the evidence already settles (read before designing anything else)

Everything below is a `file:line` read against `0f71b75`, not a re-derivation of the mission text.

| # | Claim | Evidence |
|---|---|---|
| E1 | The e2e sentinel is stamped **before** anything looks at the lane's diff | `scripts/leadv2-dispatch-product-close.sh:360` (e2e block start) vs `:591-673` (diff scoping) |
| E2 | An empty lane diff currently terminates as `refused` / `unscopable_diff` | `leadv2-dispatch-product-close.sh:654,661,671` → `_dl_note refused "${blocked_reason}"` → `exit 5` |
| E3 | The ledger's terminal vocabulary is exactly four words | `scripts/leadv2-dispatch-ledger.sh:181` `landed\|parked\|refused\|dead` |
| E4 | The surface maps a terminal row's word into `state` and classifies it | `scripts/leadv2-status-surface.sh:1247-1248`, `is_terminal()` at `:1088,1105-1107` |
| E5 | `glm_lock_busy` is a **classification-time** signal only | set from a caller flag at `leadv2-dispatch-code.sh:2074`, read into resolver signals at `:583`, single predicate site `scripts/lib/leadv2-glm-policy-resolve.py:423-424` |
| E6 | Arm resolution runs **once**, before any spawn is attempted | `leadv2-dispatch-code.sh:2066-2070` ("Resolution is pure … computing it before the atomic ledger section below is safe"), binding at `:2090-2095` |
| E7 | A launcher refusal falls to the next candidate **without re-resolving** | candidate list literal `:2160`, loop `:2248`, `arc=4` → `continue` at `:2300-2312`; `rule`/`reason` are the `:2093-2095` locals, printed verbatim at `:2284-2285` |
| E8 | A glm exit of **75 is not in the admitted refusal set**, so the lock-busy refusal is mis-typed as a launcher crash | `refusal_reason()` `leadv2-dispatch-code.sh:1432-1456` admits only rc ∈ {1, 2} for glm (77 for kimi) **and only with an explicit `LEADV2_DISPATCH_REFUSED:` marker**; rc=75 with no marker → `return 1` → generic `spawn_failed` at `:1481`, return 1 → `arc=4` |
| E9 | There is already a precedent for a *distinguished clean finish* | `scripts/kimi-coder.sh:1490-1498` / `scripts/glm-coder.sh:1425-1433` — `RUN_COMPLETE` then `RUN_COMPLETE_WITH_WARNINGS` + `FINISH_WARNINGS=N` |
| E10 | `scripts/` and `scripts/tests/` are **real directories** in each repo with per-file symlinks — not directory symlinks | `ls -ld` on persona-engine / respiro-ios / `~/.claude/leadv2-shared` |

**Answer to mission question B, stated plainly:** *both* possibilities are true, and they compound.

1. **The rule is evaluated only at classification time.** `glm_lock_busy` is a caller-supplied
   flag consumed once at `leadv2-dispatch-code.sh:583` before the spawn is attempted (E5, E6). A
   lock that becomes busy *at spawn time* can never reach
   `leadv2-glm-policy-resolve.py:423-424`. **Deciding file:line: `scripts/lib/leadv2-glm-policy-resolve.py:423-424`,
   reachable only from the single pre-spawn call at `scripts/leadv2-dispatch-code.sh:2074/583`.**
2. **The refusal is not even mapped onto the rule's trigger.** `refusal_reason()`
   (`:1432-1456`) admits glm rc ∈ {1,2} *with* a `LEADV2_DISPATCH_REFUSED:` marker. The observed
   refusal was `rc=75` with a plain-English stderr and no marker, so it was classified as a
   launcher **crash** (`spawn_failed … reason=launcher_nonzero_exit`, `:1481`), returning 1 → `arc=4`
   → blind `continue` to `kimi` (E7, E8). Even if the resolver *were* re-runnable, nothing would
   have told it the lock was busy.

Hence `rule=none reason=glm_default model=kimi` — the resolution printed at `:2284-2285` is
literally the one computed before the spawn, and no exception was ever evaluated against the
refusal. Both defects are fixed below; **neither fix hardcodes an arm out of routing.**

---

## 1. Design A — an empty diff is never a pass

### A.1 The word

**`no_work`.** A fifth ledger terminal, in the **retryable** class alongside `refused`/`parked`
(a lane that did nothing says nothing about a later attempt at the same signature — the exact
argument already recorded at `leadv2-dispatch-ledger.sh:14-17,165-168`).

Rejected alternatives, with reasons:

| Candidate | Rejected because |
|---|---|
| reuse `refused` + a new cause | The mission's whole complaint is that a *cause* string is invisible where the *word* is what gets read. `refused` already means "declined at admission before work started" (`ledger.sh:36`) — a lane that ran for 40 minutes and produced nothing is not that. |
| reuse `dead` | `dead` is a TRUE terminal (write-once, blocks retry, `ledger.sh:140`). A do-nothing lane must stay retryable. |
| a new surface class (4th of live/done/dead) | Ripples through `test-status-surface.sh` (90 assertions). Rejected — see A.4. |

`cause` carries the *why*: `empty_diff`, or `asked_into_void` when §3 fires.

### A.2 Ordering fix — the sentinel must not exist

Today the e2e gate runs first and stamps `e2e-gate-passed.flag` (E1), then the review gate
discovers the empty diff. The fix is a **hoist, not a duplicate computation**: extract the existing
diff-scoping block (`leadv2-dispatch-product-close.sh:591-673`) into a function `pc_scope_diff()`
and call it **immediately after `WRITES_CSV` is available and before `_stamp_active_phase … "e2e"`
(`:360`)**. The review gate then consumes the already-computed `${diff_file}` / `${blocked_reason}`.

- Precondition to verify at implementation time: `WRITES_CSV`, `diff_root`, `TASK`, `HANDOFF`,
  `ROOT` are all bound before `:360`. `WRITES_CSV` demonstrably is (used at `:377`).
- `_pc_repo_diff` writes `_PC_LAST_BASE_FILE`; the `rm -f` at `:670` must move with the function's
  call site, not stay where it is.

Once hoisted, an empty diff exits **before** the e2e block. `e2e-gate-passed.flag` is never
created, so `leadv2-phase8-assert.sh:69` (A7) fails on its absence — correct, unchanged.

### A.3 Second writer of the sentinel

`scripts/leadv2-phase8-e2e-gate.sh:107,153,186` stamps the same flag on its own path. It gains the
same guard: **refuse to stamp when the lane's own diff is empty.** To avoid a new script file
(off-limits §2), the emptiness predicate goes in the already-shared
`scripts/leadv2-helpers.sh` as `lv2_lane_diff_is_empty <repo> <writes_csv>`; both
`leadv2-dispatch-product-close.sh` and `leadv2-phase8-e2e-gate.sh` call it. If
`leadv2-phase8-e2e-gate.sh` does not already source `leadv2-helpers.sh`, add the source line
rather than creating a new file.

### A.4 Surface rendering — distinct, and unmistakably not success

`is_terminal()` (`leadv2-status-surface.sh:1105-1107`) gains `"no_work"` in its tuple.
Class stays three-valued: a `no_work` row renders **`cls = "dead"`** (red, counted in the red
total) with cause text **`no-work(empty-diff)`** — or `no-work(asked-into-void)` for §3. This sits
in the same `cls in ("dead","done")` block at `:1373-1382` that already rewrites cause text from
`.outcome`, and must run **before** the "terminal + stale → done" reinterpretation at `:1391-1393`
(that branch would otherwise launder a `no_work` row into green `done(...)` — this is the single
highest-risk line in the whole change).

A reader sees a red row reading `no-work(empty-diff)`. There is no reading of that as success.

### A.5 Every writer agrees

| Writer | Today | After |
|---|---|---|
| `leadv2-dispatch-product-close.sh:671` (whole-tree empty) | `refused unscopable_diff` | `no_work empty_diff` |
| `leadv2-dispatch-product-close.sh:654` (declared writes, empty) | `refused unscopable_diff` | `no_work empty_diff` |
| `leadv2-dispatch-product-close.sh:648` (`partial_diff`) | `refused partial_diff` | **unchanged** — a mixed group DID produce work |
| `leadv2-dispatch-ledger.sh:181,19,176,545` | 4-word enum | 5-word enum + doc block |
| `leadv2-status-surface.sh:1105` | 4 words | 5 words |

`review-gate.md` keeps `status: blocked` with `reason: no_work` (was `unscopable_diff`) so the
on-disk artifact and the ledger word are the same word. Exit code stays **5** — no caller
contract change.

---

## 2. Design B — make the existing rule reachable

Two edits, in order. Neither touches `candidate_arms` literals and neither names an arm.

### B.1 Type the refusal correctly

- `scripts/glm-coder.sh`: the lock-busy path must print the contract marker
  `LEADV2_DISPATCH_REFUSED: lock_busy` alongside its existing human message.
  **Trap:** `glm-coder.sh` is a MANUAL copy, not a symlink (memory `project_glm_finish_guard`) —
  the implementer must apply this edit to every live copy or the fix is a no-op in the repo that
  actually dispatches. Confirm copies before editing.
- `scripts/leadv2-dispatch-code.sh:1446`: add **75** to glm's admitted admission codes.
  Belt-and-braces for a launcher build that predates the marker: also accept a glm non-zero exit
  whose combined output matches `another GLM run is active for this repo`, mirroring the existing
  legacy-compat branch at `:1451-1454`. Marker path is the contract; the string match is the
  compatibility shim and should carry that comment.

Effect: `:1477` fires instead of `:1481` → `LAST_ARM_OUTCOME=glm_refused_lock_busy`, return 2 →
`arc=7`.

### B.2 Re-resolve on a refusal that carries a routing signal

In the `arc==7` branch (`leadv2-dispatch-code.sh:2306-2309`), before `continue`:

1. If `LAST_ARM_OUTCOME` is `glm_refused_lock_busy` **and** the lock-busy signal is not already
   set, export `DC_GLM_LOCK_BUSY=1`.
2. Re-run `resolve_arm` and rebind `arm` / `rule` / `reason` / `tier` from its output.
3. Rebuild `candidate_arms` from the newly resolved `arm` using the **same** `:2158-2163` case
   block (extract it to a `_candidate_chain_for <arm>` helper so both call sites share one
   definition), then re-apply the existing exclusion filters at `:2165-2235`.
4. Guard with a one-shot local (`_reresolved_lock_busy=1`) so the loop can never re-resolve twice
   on the same signal. No unbounded retry.

The resolver — not a list — decides where the refused work goes. With
`glm_lock_busy_no_second_channel` present in `sonnet_exceptions`,
`leadv2-glm-policy-resolve.py:423-424` now matches and the printed line at `:2284-2285` reads
`model=sonnet rule=glm_lock_busy_no_second_channel reason=sonnet_exception`.

**Deliberately NOT done:** banning kimi, editing `candidate_arms=(glm kimi codex sonnet)`, or
adding an exclusion list. Those are the shapes memory `feedback_never_hardcode_arm_exclusion`
forbids.

**Generalisation note:** the re-resolve hook is written so a *second* refusal token can be mapped
to a *second* signal later without another structural change — one `case "${LAST_ARM_OUTCOME}"`
mapping refusal-token → signal env var. Only `lock_busy` is wired in this change.

---

## 3. Design C — a worker that ends with a question is not done

### C.1 Detection, at the finish guard that already exists

`scripts/kimi-coder.sh:1470-1498` (and its `glm-coder.sh:1405-1433` twin) already decides
`status=complete` and already has a `finish_warnings` counter (E9). Extend that guard:

A run is **asked-into-void** when **all** hold:
1. It resolved to `status=complete` (this is specifically about a *clean* exit, not a crash);
2. the last non-empty line of `result.md` ends in `?` (or `？`) — bash-3.2-safe, no PCRE;
3. no question artifact exists for this task in the control plane, i.e. `leadv2-ask.sh` wrote no
   `questions/<qid>.yaml` for this task id during the run window (resolve the questions dir via
   `leadv2-state-path.sh`, as `leadv2-ask.sh` itself does — never a worktree-private path).

### C.2 The artifact that makes it distinguishable

- `${run_dir}/.asked_into_void` — a marker file, sibling of the existing `.result_is_error` /
  `.timed_out` markers (same idiom, `kimi-coder.sh:1470-1473`);
- `progress.log` gains `RUN_COMPLETE_ASKED_INTO_VOID` after the mandatory `RUN_COMPLETE` line —
  byte-identical placement to `RUN_COMPLETE_WITH_WARNINGS` at `:1495-1497`, so every existing
  Monitor grep for the literal `RUN_COMPLETE` keeps working;
- `finish_warnings` is incremented, so the existing `FINISH_WARNINGS=N` line reflects it.

### C.3 Where it becomes visible

`leadv2-dispatch-product-close.sh` reads `.asked_into_void` from the worker's run dir when
deciding the terminal:

| Lane diff | `.asked_into_void` | Terminal | Cause |
|---|---|---|---|
| empty | absent | `no_work` | `empty_diff` |
| empty | present | `no_work` | `asked_into_void` |
| non-empty | present | `parked` | `asked_into_void` |
| non-empty | absent | unchanged | unchanged |

The non-empty + asked case is `parked`, not `no_work`: work exists and a human answering the
question unblocks it — which is exactly what `parked` means (`ledger.sh:33`).

Surface: `no-work(asked-into-void)` (red) or the existing parked rendering. The minimum bar the
mission sets — *detectable, and does not read as success* — is met by the marker file plus the
terminal word.

---

## 4. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | The stale→done reinterpretation at `status-surface.sh:1391-1393` launders a `no_work` row into green `done(...)` — the exact lying-green disease this task exists to kill | **CRITICAL** | Exclude `no_work` from that branch explicitly, and assert it in the new test with a deliberately-old timestamp |
| R2 | Hoisting the diff-scoping block moves code across a `_PC_LAST_BASE_FILE` lifetime and a `_stamp_active_phase` call | High | Move the `rm -f "${_PC_LAST_BASE_FILE}"` with the block; verify `WRITES_CSV`/`diff_root` bound before the new call site; re-run `test-landing-diff-scoping.sh` and `test-lane-writes-scoping.sh` |
| R3 | `glm-coder.sh` is a MANUAL copy — a marker added in canonical alone does nothing on the dispatching repo | High | Enumerate every copy before editing; state which copies were touched in the close evidence |
| R4 | A fifth enum value reaches a reader that only knows four | High | Exactly three readers exist (`ledger.sh:181` validator, `status-surface.sh:1105`, `status-surface.sh:1247-1248` mapping). All three are in `LANE_WRITES`. A grep for the four-word literal across the repo is a required pre-commit check |
| R5 | Test counts drift (`test-status-surface.sh` must stay 90, etc.) | High | **All new assertions go in NEW test files.** Zero assertions added to the six named suites |
| R6 | New test files under `scripts/tests/` need per-file symlinks in `~/.claude/leadv2-shared/scripts/tests/` and every repo's `.claude/scripts/tests/` — `scripts/tests/` is a REAL directory, not a directory symlink (E10) | High | Symlinks land in the SAME change. Three separate outages tonight came from this omission |
| R7 | Re-resolution loops | Medium | One-shot `_reresolved_lock_busy` guard; refusal→signal mapping is a closed set of one |
| R8 | Accepting rc=75 as a refusal masks a genuine glm crash that happens to exit 75 | Medium | Marker-first (`LEADV2_DISPATCH_REFUSED:`); the bare-string shim is narrow (`another GLM run is active for this repo`) and comment-tagged as legacy-compat, matching the `:1451` precedent |
| R9 | `?`-terminated detection false-positives on a rhetorical closing line | Low | Accepted. A false positive costs one red row and a retry; a false negative is the failure this task exists to end. Bias to loud |
| R10 | `partial_diff` gets swept into `no_work` | Medium | Explicitly preserved as `refused partial_diff`; asserted in the new test |
| R11 | Everything must parse under macOS system bash 3.2 | High | No `declare -A`, no `${var,,}`, no PCRE. The file already carries this constraint (`product-close.sh:600-604`) |

---

## 5. Out of scope (implementing agent: ignore these)

- kimi's looping read behaviour and its fabricated `## Commits made` — model behaviour. A + C make
  them harmless; do **not** prompt-engineer.
- Per-lane worktree isolation (`LANE-WORKTREE-ISOLATION-01`).
- `dispatch_ledger_sweep_write_dead` — the sweep cannot tell "did nothing" from "crashed" and
  keeps writing `dead`. Unchanged.
- The `RUN_COMPLETE_WITH_WARNINGS` finish-guard semantics beyond adding one new warning source.
- Any change to exit codes, to `leadv2-phase8-assert.sh`'s A7 rule, or to the e2e gate's
  pass/fail logic itself.
- Router v2 (`LEADV2_ROUTER_V2=1`) path. The re-resolve hook is placed in the shared candidate
  loop, so v2 inherits it structurally, but no v2-specific behaviour is designed or asserted here.

---

## 6. New tests (new files only — the six named suites keep their exact counts)

| File | Asserts |
|---|---|
| `scripts/tests/test-no-work-terminal.sh` | empty lane diff → ledger `terminal=no_work cause=empty_diff`; `e2e-gate-passed.flag` absent; `review-gate.md` reason `no_work`; exit 5; `partial_diff` still `refused`; a 3h-old `no_work` row renders red `no-work(empty-diff)` and NOT `done(...)` (R1) |
| `scripts/tests/test-lock-busy-reresolve.sh` | fake glm launcher exiting 75 with the marker → `arm_refused`, then `route_resolved … model=sonnet rule=glm_lock_busy_no_second_channel reason=sonnet_exception`; re-resolve happens at most once |
| `scripts/tests/test-asked-into-void.sh` | `result.md` ending in `?` with no control-plane question → `.asked_into_void` present, `RUN_COMPLETE` still on its own line, `RUN_COMPLETE_ASKED_INTO_VOID` follows; terminal `no_work`/`asked_into_void` (empty diff) and `parked`/`asked_into_void` (non-empty diff) |

Each new file needs its per-file symlink in `~/.claude/leadv2-shared/scripts/tests/` **and** in
every repo's `.claude/scripts/tests/` (persona-engine, respiro-ios, and m3's leadv2 dir) in the
same change — R6.

---

## 7. Constraint checklist

1. **Env var naming** — no new env vars introduced. `DC_GLM_LOCK_BUSY` is existing and reused
   under its existing name. PASS.
2. **File paths** — every path in LANE_WRITES verified present on disk at `0f71b75` except the
   three test files, marked `(to-create)`. PASS.
3. **`claude -p` commands** — none introduced. N/A.
4. **Concurrent access** — `leadv2-dispatch-product-close.sh` and `leadv2-phase8-e2e-gate.sh` both
   write `e2e-gate-passed.flag`. The hoist makes product-close exit *before* its own write on an
   empty diff, and A.3 gives the other writer the same predicate, so neither can stamp a sentinel
   the other would refuse. No new lock needed; the existing terminal-ledger flock
   (`ledger.sh:206`) already serialises the ledger write. PASS.
5. **Config contradiction** — `glm_lock_busy_no_second_channel` already exists in
   `config/leadv2-routing.yaml` `sonnet_exceptions` and is gated by the single-source-of-truth
   `rid not in exc_ids` check (`leadv2-glm-policy-resolve.py:434`). No yaml change required; the
   rule stops being declared-but-dead. PASS.

---

## 8. acceptance

```yaml
acceptance:
  authored_at: 2026-08-02T00:00:00Z
  items:
    - id: A1
      surface: rendered_line
      observable: >
        In the leadv2 status surface, the row for a lane whose worker produced no
        diff reads, in red, "no-work(empty-diff)" — and a reader scanning the table
        cannot find the word "passed", "done", or "landed" anywhere on that row.
    - id: A2
      surface: file_artifact
      observable: >
        For that same lane, the handoff directory contains no file named
        e2e-gate-passed.flag, and review-gate.md's reason line reads no_work.
    - id: A3
      surface: log_line
      observable: >
        For a dispatch whose glm spawn was turned away because another run held
        the repo lock, the journal's route_resolved line names sonnet as the model
        and names glm_lock_busy_no_second_channel as the rule that decided it —
        instead of the previous "rule=none, model=kimi".
    - id: A4
      surface: file_artifact
      observable: >
        A worker that finishes by asking the operator a question nobody answered
        leaves a marker named .asked_into_void in its run directory, its progress
        log shows RUN_COMPLETE_ASKED_INTO_VOID on the line after RUN_COMPLETE, and
        its lane row reads "asked-into-void" rather than any success wording.
    - id: A5
      surface: log_line
      observable: >
        The six named existing suites print their unchanged pass totals — 18, 10,
        14, 90, 7, 9 — when run under macOS system bash 3.2.
```

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-ledger.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/glm-coder.sh, plugins/leadv2/scripts/kimi-coder.sh, plugins/leadv2/scripts/tests/test-no-work-terminal.sh, plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh, plugins/leadv2/scripts/tests/test-asked-into-void.sh

DELIVERABLE_COMPLETE
