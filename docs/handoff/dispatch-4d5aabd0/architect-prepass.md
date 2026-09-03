# Architect prepass — WORKER-PARKED-ON-BG-01

A worker that ends its turn WAITING is read as finished. Two halves: (A) a mission
contract that forbids the shape, (B) a classifier + resume path that recognises it.

Everything below was read from the tree at `~/Projects/leadv2` @ `6fa4823`.

---

## 0. Where the mission's framing and the code disagree — read this first

**The measured lane `dispatch-b7bcf98a` ran on the `sonnet` arm, not glm/kimi.**

```
$ cat docs/handoff/dispatch-b7bcf98a/arm-registered
arm=sonnet handle=PID=93344 LABEL=developer-dispatch-b7bcf98a-1787458752 ...
STREAM=/Users/.../docs/handoff/dispatch-b7bcf98a/developer.stream.jsonl ...
```

That single fact breaks three of the mission's assumptions about half B:

1. `leadv2-lane-outcome.sh` — the only writer of the `outcome:` key — is invoked from
   exactly two places, both provider coders:
   - `plugins/leadv2/scripts/glm-coder.sh:1552`
   - `plugins/leadv2/scripts/kimi-coder.sh:1573`
   The sonnet arm never runs it. A sonnet lane therefore has **no `outcome:` at all**,
   so `_pc_lane_outcome` (`leadv2-dispatch-product-close.sh:577`) returns `""` and
   `pc_dwr_resume_once` bails at L621 regardless of which tokens that comparison accepts.

2. Run-dir resolution disagrees for sonnet. `_pc_run_dir_for`
   (`leadv2-dispatch-product-close.sh:556-563`) sends a non-glm/kimi author to
   `${_PC_RUNS_ROOT}/sonnet-runs/${handle}`, but `claude-subsession.sh:1068` publishes the
   real dir at `${...}/claude-runs/${RUN_ID}` where `RUN_ID="${ROLE}-${TASK_ID}-<epoch>-$$"`.
   The two paths can never coincide, so `pc_dwr_resume_once` returns 1 at its
   `[[ -f "${old_run_dir}/meta.yaml" ]]` guard (L619) before the outcome is even read.

3. There is no sonnet resume launcher. `_pc_resume_launcher_for`
   (`leadv2-dispatch-product-close.sh:592-600`) looks for `${SCRIPT_DIR}/<author>-coder.sh`;
   `ls plugins/leadv2/scripts/*coder.sh` yields exactly `glm-coder.sh` and `kimi-coder.sh`.

4. `claude-subsession.sh:1133` writes `$RUN_DIR/.outcome` as a **bare integer exit code**
   (`printf '%s\n' "$_exit_code"`), a different file format from
   `leadv2-lane-outcome.sh`'s `outcome=/bound=/work=/next=/at=` block. `_pc_lane_outcome`'s
   sentinel fallback (`sed -n 's/^outcome=//p'`) yields `""` on it.

**Consequence for scope, stated plainly:** half B as literally specified ("widen the
outcome the resume accepts") hardens **glm and kimi lanes only**. It does not make the
measured sonnet lane resumable, and no amount of widening that one comparison would.
Half A *does* cover the measured lane — `_spawn_worker_body` is a single site for all
four arms. The one piece of B that can be made arm-agnostic cheaply is the **checkpoint
commit wording**, because the handoff stream (`docs/handoff/<tid>/<role>.stream.jsonl`)
exists for every arm and is exactly the artifact the mission measured. That is designed
in below (B3) and covers sonnet.

Making sonnet lanes genuinely resumable is a second mechanism (outcome classifier for
the claude arm + run-dir pointer resolution + a resume entrypoint that does not exist),
not a widened conditional. It is an explicit non-goal here — see §7 — and is filed as
`WORKER-PARKED-ON-BG-02`.

---

## 1. CALLERS / CALLEES

### 1a. Half A — `_spawn_worker_body`

| Symbol | file:line | Role |
|---|---|---|
| `_LEADV2_EVIDENCE_CONTRACT_MISSION` (def) | `leadv2-helpers.sh:63-65` | `readonly` guarded by `[[ -z … ]]` |
| `_spawn_worker_body` (def) | `leadv2-dispatch-code.sh:3207` | single prepend site, all 4 arms |
| — evidence prepend | `leadv2-dispatch-code.sh:3222-3228` | contract, with embedded-literal fallback |
| — `WORKTREE_PIN_LINE` prepend | `leadv2-dispatch-code.sh:3229` | runs *after*, so pin ends up first |
| — arm switch | `leadv2-dispatch-code.sh:3230+` | `glm` / `kimi` / `sonnet` / `codex` |

Callees of `_spawn_worker_body` per arm: `glm-coder.sh bg`, `kimi-coder.sh bg`,
`claude-subsession.sh` (sonnet), codex runner. Only `_spawn_worker_body` composes the
mission string; there is no per-arm prepend. Confirmed by
`grep -rn '_LEADV2_EVIDENCE_CONTRACT_MISSION' plugins/leadv2/` → 4 non-test hits, all
listed above.

**Independent copy that nobody named:** the claude/Agent-tool subagent path composes its
preamble from `SHARED_PROTOCOL_BOILERPLATE` inside `claude-subsession.sh`, *not* from
`_spawn_worker_body`'s prepend — but a sonnet **dispatch arm** goes through
`_spawn_worker_body` first, so it receives both. Agent-tool subagents spawned directly by
the lead (architect, critic) receive only `SHARED_PROTOCOL_BOILERPLATE` and are therefore
**not** covered by half A. Out of scope (§7), named so nobody claims coverage it lacks.

### 1b. Half B — outcome classification and resume

| Symbol | file:line | Role |
|---|---|---|
| `leadv2-lane-outcome.sh` (script) | `leadv2-lane-outcome.sh:1-190` | sole writer of `.outcome` + `outcome:` |
| — caller (glm) | `glm-coder.sh:1552` | after `finalize_meta`, before `release_lock` |
| — caller (kimi) | `kimi-coder.sh:1573` | same window |
| — callee `deadhand_check` (prior) | `glm-coder.sh:1263` / `kimi-coder.sh` | writes `.no-deliverable` |
| — callee `extract_result` (prior) | `glm-coder.sh:1430` | writes `result.md` **before** the finish guard, so `result.md` is on disk when the classifier runs |
| `_pc_lane_outcome` | `leadv2-dispatch-product-close.sh:577-590` | reads `meta.yaml` `outcome:`, falls back to `.outcome` |
| `pc_dwr_resume_once` | `leadv2-dispatch-product-close.sh:605-…` | gate at **L621** |
| — its only caller | `leadv2-dispatch-product-close.sh:1988` | `if pc_dwr_resume_once; then` → second wait |
| `_pc_run_dir_for` | `leadv2-dispatch-product-close.sh:556` | glm/kimi special-cased, else `<author>-runs` |
| `_pc_resume_launcher_for` | `leadv2-dispatch-product-close.sh:592` | `LEADV2_PC_RESUME_LAUNCHER_BIN` override, else `<author>-coder.sh` |
| `pc_stop_gate_autocommit` | `leadv2-dispatch-product-close.sh:~1490-1573` | commit msg at **L1563** |
| — call site 1 (first-wait timeout) | `leadv2-dispatch-product-close.sh:1976` | reaped worker |
| — call site 2 (resumed-wait timeout) | `leadv2-dispatch-product-close.sh:2010` | reaped resumed worker |
| — call site 3 (clean exit) | `leadv2-dispatch-product-close.sh:~2040` | **the parked path** |

**Readers of the outcome token that a new value must not silently break:**

| Reader | file:line | Behaviour on an unknown token today |
|---|---|---|
| `lane_outcome()` whitelist | `leadv2-status-surface.sh:874` | `if val in ("completed","died-with-work","died-clean")` → else `""` |
| `.outcome` overlay | `leadv2-lane-class.py:126-134` | unknown → falls to `elif "?" not in cause: cause += "?"` — renders `dead(no-signal)?` |
| `pc_dwr_resume_once` | `…product-close.sh:621` | unknown → `return 1`, no resume |

All three must be updated in the same change, or a `parked` lane renders as an
unexplained `?` on the SwiftBar surface. That is item 5 of the write set.

---

## 2. STATES AND RETURN CODES

### 2a. `leadv2-lane-outcome.sh` — the decision table, today and after

Inputs: `BOUND ∈ {wall_clock, max_turns, <from .bound_reason>, none}` (L54-84),
`WORK ∈ {yes,no}` (L118-146), `EXIT_CODE`, presence of `.no-deliverable`.

Today (L149-160):

| # | BOUND | `.no-deliverable` | exit | WORK | outcome | `next` |
|---|---|---|---|---|---|---|
| 1 | ≠none | any | any | yes | `died-with-work` | continue |
| 2 | ≠none | any | any | no | `died-clean` | respawn |
| 3 | none | present | any | yes | `died-with-work` | continue |
| 4 | none | present | any | no | `died-clean` | respawn |
| 5 | none | absent | 0 | any | `completed` | none |
| 6 | none | absent | ≠0 | yes/no | `died-with-work`/`died-clean` | continue/respawn |

The measured shape (clean exit 0, no bound, parked worker) lands on **3, 4, or 5**:
- 5 when the worker *did* write a satisfying deliverable and then parked — read as done,
  no resume, STOP-GATE checkpoints the half-tree. **This is the primary hole.**
- 4 when there is no deliverable and no tracked work delta — `died-clean` → `respawn`,
  and `pc_dwr_resume_once` refuses it at L621. **Second hole.**
- 3 already resumes today (`died-with-work`), so the mission's "the resume never fires"
  is true for rows 4 and 5, not for row 3. Design against the code, not the framing.

After (new row 2.5 inserted between rows 2 and 3):

| # | BOUND | PARKED | deliverable verdict | outcome | `next` |
|---|---|---|---|---|---|
| 1-2 | ≠none | — | — | unchanged | unchanged |
| **2.5** | none | yes | `.deliverable` contract exists AND (`.no-deliverable` present OR exit≠0) | **`parked`** | **continue** |
| 3-6 | — | no / not eligible | — | unchanged | unchanged |

`PARKED` is computed only when `EXIT_CODE == 0 && BOUND == none`. A bound that fired is
the truth about why the run stopped; parked wording on top of it changes nothing useful
and would relabel real turn-cap deaths.

**Deliverable verdict — D3, the deliberate conservatism.** Row 2.5 requires a
`.deliverable` contract to exist. When `capture_deliverable` (`glm-coder.sh:1135-1153`)
found no contract in the mission there is no way to judge "declared work incomplete", and
classifying such a run `parked` on wording alone would resume finished runs. In that case
we fall through to row 5 (`completed`) exactly as today. Stated because it is a real
coverage limit, not an oversight: **a mission with no named deliverable that parks is
still mis-read as complete.** That is the honest residual, repeated in §4.

Row 2.5 subsumes part of row 3 (parked + `.no-deliverable` + work delta was
`died-with-work`, becomes `parked`). Both map to `next=continue` and both are accepted by
the widened resume gate, so no behaviour is lost — the token is narrowed, never widened,
which is what the mission asked for.

### 2b. `pc_dwr_resume_once` — rc table (unchanged shape, one gate widened)

| rc | condition | caller (`…product-close.sh:1988`) does | user-visible consequence |
|---|---|---|---|
| 0 | resume launched, `HANDLE` reassigned | enters second `pc_await_worker_exit` with `LEADV2_PC_RESUME_MAX_WAIT_S` | the lane gets a second worker on the same worktree; wall clock up to 2× |
| 1 | kill switch `LEADV2_PC_DWR_RESUME=0` | falls through to `pc_scope_diff` | today's behaviour, byte-identical |
| 1 | no `AUTHOR`/`HANDLE`, or run dir / `meta.yaml` absent | falls through | **every sonnet and codex lane takes this branch** (§0.2) |
| 1 | outcome not in `{died-with-work, parked}` | falls through | a genuinely completed lane is gated on its real diff — correct |
| 1 | `.dwr-resume-attempted` marker present | journals `new_run=skipped reason=already_attempted`, falls through | **the no-loop guarantee**: a second parked exit checkpoints and blocks, it does not resume again |
| 1 | no launcher for author | journals `reason=no_launcher` | sonnet/codex — no resume, as today |
| 1 | marker write failed | journals `reason=marker_write`, does **not** launch | fail-closed |
| 1 | launcher rc 1 or 2 | journals `new_run=blocked_by_gate` | quota/lock gate refused; lane proceeds to checkpoint |
| 1 | launcher rc other, or rc 0 with unparsable run-id | journals `launch_failed` | same |

**Terminal outcomes traced to the end.** When `pc_dwr_resume_once` returns 1 and the tree
is dirty, control reaches `pc_scope_diff` → `pc_stop_gate_autocommit` (call site 3) → the
phase-8 e2e gate. What a human sees today: a `wip(<sig>): auto-checkpoint on worker exit
(STOP-GATE)` commit and a failed e2e gate — the shape the mission counted 15 of on main.
After this change the same path produces a commit whose subject names the cause, and the
lane journal carries `dwr_resume … reason=already_attempted`. The lane still fails the
gate. **That is intended: one resume, never a loop.**

The second wait's timeout branch (`…product-close.sh:2003-2016`) reaps and exits 5 with
`reason=worker_timeout … resumed=1` — unchanged.

### 2c. `pc_stop_gate_autocommit` — rc table (unchanged; message only)

The function `return 0`s on every failure path and journals
`stop_gate_autocommit_failed reason=index_create_failed|add_failed|commit_failed`
(L1553, L1560, L1571). It never aborts the close. The change touches **only** the `-m`
string at L1563. No rc changes, so no caller changes.

---

## 3. CONFIGURATION BOUNDARIES

### 3a. `_LEADV2_FOREGROUND_CONTRACT_MISSION` (new, `leadv2-helpers.sh`)

| Input state | Behaviour |
|---|---|
| absent (helpers not sourced / var empty) | `_spawn_worker_body` logs via `log_err` and prepends an embedded literal — mirrors the existing evidence-contract fallback at `leadv2-dispatch-code.sh:3225-3226`. **Never fails open silently.** |
| already set by an outer shell | the `[[ -z … ]]` guard at L63 keeps the outer value; `readonly` is not re-applied → no `readonly: read-only variable` abort when helpers is sourced twice |
| set to empty string | treated as absent → embedded-literal fallback |
| contains `"` or `` ` `` | **forbidden by the existing file comment** (`leadv2-helpers.sh:57-58`): the text flows into double-quoted shell strings and into codex argv. Author with plain ASCII plus em-dashes only. A lint case in the test asserts this. |
| very long | no cap exists and none is added: it is a constant, not user input. Its cost is one fixed prefix per mission. |

### 3b. `WORKTREE_PIN_LINE` interaction — the placement invariant

Prepends compose in reverse. Current code prepends evidence (3222) then pin (3229),
yielding `pin \n\n evidence \n\n mission`. To reach the required
`pin \n\n evidence \n\n foreground \n\n mission`, the new block goes **immediately before**
the evidence block at 3222. All three prepends stay **after** `compute_sig`/`classify`/
`router`, so `sig8` is unchanged. Boundary: `WORKTREE_PIN_LINE` empty → its
`[[ -z … ]] ||` guard skips it, order degrades to `evidence, foreground, mission`;
still correct.

### 3c. Parked detection inputs (`lib/leadv2-parked-detect.sh`, new)

| Input | absent | empty | minimum | over-cap | malformed |
|---|---|---|---|---|---|
| `result.md` | not parked (`return 1`) | not parked | 1 non-empty line → matched | read is bounded to the **last 4096 bytes** via `tail -c`; a 2 GB result.md costs one bounded read | invalid UTF-8 / binary: `tr`/`case` operate on bytes, no match → not parked. Never aborts. |
| `.deliverable` | row 2.5 not eligible → `completed`/`died-*` as today (D3) | same | — | — | path that does not resolve → `deadhand_check` already wrote `.no-deliverable reason=missing` |
| `.no-deliverable` | deliverable satisfied → **not parked** (negative control #4) | present-but-empty still counts as present (`-f`, not `-s`) — matches `leadv2-lane-outcome.sh:154` | — | — | — |
| `LEADV2_PARKED_DETECT` | default `1` (on) | treated as on | `0` → detection disabled, **every table row reverts to today byte-for-byte** | any other value → on | same |
| handoff stream (B3 only) | reason stays `auto-checkpoint on worker exit` | same | — | bounded `tail -c 65536`, same idiom as `leadv2-lane-outcome.sh:69` | unparsable JSON → no match → default reason |

**Over-cap containment, explicitly:** every read in the new lib is bounded with `tail -c`
at the source, and every probe is wrapped so a failure degrades *the probe*, not the run —
the same rule `deadhand_check` states at `glm-coder.sh:1256-1259` and
`leadv2-lane-outcome.sh:21-24`. A malformed `result.md` must never take down the close
gate; it takes down only its own classification, which then falls back to today's table.

**Env-var naming self-check.** New names: `LEADV2_PARKED_DETECT`. Prefix `LEADV2_`,
consistent with `LEADV2_PC_DWR_RESUME`, `LEADV2_DEADHAND_MIN_BYTES`,
`LEADV2_DISPATCH_SPAWN`. No `LEAD_V2_*` form is introduced. The shell constant
`_LEADV2_FOREGROUND_CONTRACT_MISSION` is **not** an env var (matching the existing
`_LEADV2_EVIDENCE_CONTRACT_MISSION` note at `leadv2-helpers.sh:59-60`) — not exported, not
a config knob. No tail-line / byte-count knobs are introduced; those are internal
constants, because a knob nobody sets is a surface nobody tests.

### 3d. Concurrent access

`leadv2-lane-outcome.sh` appends to `${RUN_DIR}/meta.yaml`. One run dir has exactly one
supervisor (`cmd_supervise` holds the repo lock until `release_lock`, `glm-coder.sh:1556`),
and the classifier runs inside that window — no second writer. `pc_stop_gate_autocommit`
already builds a **throwaway index** (`GIT_INDEX_FILE=$(mktemp …)`, L1546-1560) precisely
because another actor may hold staged work; the message change does not touch that.
`.dwr-resume-attempted` is written mktemp+`mv -f` before launch (L1697-1704) — unchanged.
**No new race surface is introduced.**

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every fix

The invariant: *a lane never presents a half-finished tree as a finished worker's output.*

Four things still violate it after this change.

**(1) Sonnet and codex lanes still cannot resume — including the exact lane that was
measured.** `pc_dwr_resume_once` returns 1 at its run-dir guard for both arms, and no
`sonnet-coder.sh`/`codex-coder.sh` exists to relaunch. A parked sonnet worker after this
change gets a correctly-worded checkpoint commit and a correct journal line, and still
fails the e2e gate with no second attempt. In plain words: **a parked sonnet lane still
delivers nothing today; it just stops lying about why.** Half A is what actually protects
that lane, by preventing the shape rather than recovering from it.

**(2) A parked worker with no named deliverable is still read as complete.** D3 (§2a)
requires a `.deliverable` contract to classify `parked`. Missions that name no deliverable
path park into row 5 exactly as today.

**(3) Wording-based detection is defeasible in both directions.** A worker that parks
while phrasing its last line as a finished report ("Tests are running; results will
follow.") may miss the phrase set; a worker that finishes and mentions a background job in
passing may match it. The false-positive cost is bounded to one extra resume (the marker
is one-shot) and one differently-worded commit; the false-negative cost is today's
behaviour. That asymmetry is why the phrase set biases loud — the same reasoning
`glm-coder.sh:1497-1499` records for `.asked_into_void` (R9).

**(4) The resume can itself park.** The second worker inherits the same mission and the
same contract. If it parks too, the marker short-circuits, we checkpoint with
`parked-on-background-job`, and the gate fails. That is the designed floor, not a gap —
but it means half A's contract text, not half B, is the load-bearing part of this change.

What I checked to reach this list: all four `_LEADV2_EVIDENCE_CONTRACT_MISSION` call sites,
both `leadv2-lane-outcome.sh` callers, all three `pc_stop_gate_autocommit` call sites, all
three readers of the outcome token, `_pc_run_dir_for` vs `claude-subsession.sh`'s published
run dir, and `capture_deliverable`/`deadhand_check`'s contract-capture conditions.

---

## 5. THE CHANGE — exact files and edits

### A1 — `plugins/leadv2/scripts/leadv2-helpers.sh`
Immediately after the `_LEADV2_EVIDENCE_CONTRACT_MISSION` block (L52-66), a sibling block
with the identical `[[ -z … ]]` + `readonly` shape and its own comment banner
(`WORKER-PARKED-ON-BG-01`), defining `_LEADV2_FOREGROUND_CONTRACT_MISSION`. Content, as
words the worker follows (no `"`, no backtick):

- never end a turn while a job you started is still running;
- run verification — test suites, builds, migrations — in the FOREGROUND with an explicit
  timeout;
- if a job must run detached, wait for it and report its result in the SAME turn before
  finishing;
- a final message of the form standing by / waiting for / will report when it completes is
  a protocol violation, not a completion.

### A2 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
Insert a prepend block **immediately before** L3222, same guard + `log_err` +
embedded-literal fallback shape as the evidence block. Net order: pin, evidence,
foreground, mission. No other line moves.

### B1 — `plugins/leadv2/scripts/lib/leadv2-parked-detect.sh` *(to-create)*
`lv2_parked_text_file <path>` → rc 0 when parked-shaped. Bash 3.2 only (no `[[ =~ ]]`
PCRE, no `${var,,}`; lowercase via `tr`), bounded `tail -c 4096`, last 3 non-empty lines,
`case` globs over a fixed phrase set (`*standing by*`, `*waiting for*`, `*waiting on*`,
`*will report*`, `*no further action until*`, `*once it completes*`, `*once they complete*`,
`*until it finishes*`). Honours `LEADV2_PARKED_DETECT=0`. Never exits non-zero for any
reason other than "not parked". Sourced by B2 and B3 — **one implementation, two readers**,
so this does not become the third independent copy alongside `.asked_into_void`'s.

### B2 — `plugins/leadv2/scripts/leadv2-lane-outcome.sh`
Source B1. Add `PARKED="$(…)"` computed only when `EXIT_CODE == 0 && BOUND == none`.
Insert decision row 2.5 (§2a) before the `.no-deliverable` branch at L153. Add
`parked) NEXT="continue"` to the `case` at L162-166. Artifacts at L169-188 are unchanged
in shape — `.outcome`, `progress.log`, `meta.yaml` all carry the new token automatically.

### B3 — `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`
1. L621: `[[ "${old_outcome}" == "died-with-work" ]] || return 1` becomes a `case`
   accepting `died-with-work|parked`. **Nothing else in the function changes** — marker
   semantics, journal keys and the one-shot guarantee are untouched.
2. New `_PC_STOP_GATE_REASON` global (default `auto-checkpoint on worker exit`) and
   `_pc_stop_gate_resolve_reason()`, which sets it to `parked-on-background-job` when
   either (a) `_pc_lane_outcome` for the current `HANDLE` is `parked`, or (b) — the
   **arm-agnostic** path, which is what covers sonnet — `lv2_parked_text_file` matches the
   lane's handoff stream last `result` record. Called immediately before the call site at
   §1b line 3 (clean exit). L1563 becomes
   `-m "wip(${TASK}): ${_PC_STOP_GATE_REASON} (STOP-GATE)"`.

### B4 — `plugins/leadv2/scripts/leadv2-status-surface.sh`
L874: add `"parked"` to the whitelist tuple.

### B5 — `plugins/leadv2/scripts/leadv2-lane-class.py`
After L131, add `elif outcome == "parked": cause, cls = "parked(bg-job)", "dead"` so a
parked lane renders a named cause instead of falling to the `cause + "?"` branch.

### B6 — tests
New `plugins/leadv2/scripts/tests/test-parked-worker-resume.sh`, red-first against a
`git archive` pre-fix baseline in the style of
`tests/test-claim-evidence-gate.sh:11-17` (**never** `git stash/reset/clean`). Registered
in `run-core-offline.sh` beside line 266. Cases = the mission's five verifications:
contract reaches all four arms under `LEADV2_DISPATCH_SPAWN=0` + `sig8` byte-identical
with and without; parked+no-deliverable replay → exactly one resume; second parked exit →
`reason=already_attempted`, no loop; positive control `died-with-work` resumes; negative
control clean success **with** deliverable does not.

**Do not touch:** `pc_stop_gate_autocommit`'s staging/index logic, the phase-8 e2e gate,
any test's assertions, and main's uncommitted files.

---

## 6. acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      In a lane journal, a worker that exited cleanly while still waiting on its own
      background job is followed by a line recording that a resume was launched for
      that lane, naming the run it resumed from and the new run it started.
    authored_at: 2026-08-23T06:05:00Z
  - surface: log_line
    observable: >-
      When that same lane parks a second time, the journal records that the resume was
      skipped because one was already attempted. There is never a third worker.
    authored_at: 2026-08-23T06:05:00Z
  - surface: file_artifact
    observable: >-
      The auto-checkpoint commit for a parked lane reads
      "wip(<sig>): parked-on-background-job (STOP-GATE)" instead of
      "auto-checkpoint on worker exit", so a person reading git log can tell the worker
      was waiting rather than crashed.
    authored_at: 2026-08-23T06:05:00Z
  - surface: file_artifact
    observable: >-
      The mission text handed to each of the glm, kimi, sonnet and codex arms contains
      the instruction never to end a turn while a job it started is still running, and
      the dispatch identity the lane is deduped by is unchanged by its presence.
    authored_at: 2026-08-23T06:05:00Z
  - surface: rendered_line
    observable: >-
      A parked lane on the status surface shows a named parked cause rather than an
      unexplained trailing question mark.
    authored_at: 2026-08-23T06:05:00Z
```

---

## 7. Non-goals (implementer: ignore these)

1. **Making sonnet/codex lanes resumable** (`WORKER-PARKED-ON-BG-02`). Needs an outcome
   classifier for the claude arm, `_pc_run_dir_for` resolution through
   `.claude-session-runner.run-id`, a `.outcome` format reconciliation with
   `claude-subsession.sh:1133`, and a resume entrypoint that does not exist.
2. Extending half A to Agent-tool subagents via `SHARED_PROTOCOL_BOILERPLATE` (§1a).
3. Weakening, relocating or conditionalising the STOP-GATE checkpoint. Message string only.
4. The phase-8 e2e gate and every existing test assertion.
5. Fixing `deferred-GLM ladder (V3-GLM-LADDER-01)` and `fanout classifier/runner guard` —
   known-pre-existing failures in `run-core-offline.sh`; name them in the report, do not fix.
6. Any `git stash` / `reset` / `clean`; main's uncommitted files belong to another session.
7. New tunable knobs beyond the single `LEADV2_PARKED_DETECT` kill switch.

LANE_WRITES: plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-parked-detect.sh, plugins/leadv2/scripts/leadv2-lane-outcome.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-lane-class.py, plugins/leadv2/scripts/tests/test-parked-worker-resume.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
