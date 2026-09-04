# REVIEW-ROUNDCAP-01 — architect prepass (mechanism-closed design)

Repo: `~/Projects/leadv2`. Base `baa430c`. Author: architect prepass. Do-not-implement.

---

## 0. Correction to the mission's framing (read this first)

The mission (via autoresearch F4) states: *"NO round counter exists anywhere (`grep -rn "round"
the file` → zero relevant hits)"*. **That is false against the current tree.** Verified:

| Claim | Reality on disk (baa430c) |
|---|---|
| no round counter | `_review_round_context()` at `plugins/leadv2/scripts/leadv2-review-run.sh:592-677` computes `REVIEW_ROUND`; `_review_state_write()` at `:684-697` persists it |
| no persistence | `${HANDOFF}/.review-round.state`, two lines `round=<n>` / `diff=<8hex>`, atomic `.tmp`+`mv` (`:694-695`) |
| dedup is diff-hash only | correct — `record-review --diff-hash` at `:1291`, rc=2 ⇒ `status=dedup` (`:1293`) |

Why F4 was right about the *symptom* and wrong about the *cause*: the round number is **computed
and displayed but never enforced**. `plugins/leadv2/docs/phases.md:291` says it in one line —
**"Round cap is enforced by LEAD, not the engine."** The lead is an LLM; it does not reliably stop
at 2. That is the whole defect. F4's grep almost certainly hit one of the two **stale 40454-byte
real-file copies** (`.claude/scripts/leadv2-review-run.sh` and
`~/.claude/leadv2-shared/scripts/leadv2-review-run.sh`) rather than the 62791-byte canonical.

Design consequence: **do not build a new counter.** Extend the existing one, and move enforcement
from the (LLM) lead into the (deterministic) engine.

Canonical-file check (run before editing):
```
$ [ ~/.claude/plugins/local/leadv2/plugins/leadv2/scripts/leadv2-review-run.sh -ef \
    plugins/leadv2/scripts/leadv2-review-run.sh ] && echo YES
YES                                   # plugin-root == canonical, same inode
$ wc -c .claude/scripts/leadv2-review-run.sh ~/.claude/leadv2-shared/scripts/leadv2-review-run.sh
   40454 .claude/scripts/leadv2-review-run.sh
   40454 /Users/…/.claude/leadv2-shared/scripts/leadv2-review-run.sh   # BOTH STALE, DO NOT EDIT
```
Edit **only** `plugins/leadv2/scripts/leadv2-review-run.sh`. The two 40454-byte files are a
pre-existing one-copy-drift regression (already reported by the session-start `[one-copy]` hook);
de-duplicating them is **out of scope** here and belongs in `docs/leadv2/open-threads.md`.

---

## 1. CALLERS / CALLEES

### 1a. Callers of the engine (who can trigger a review round)

| # | Caller | Site | Reaches this engine? |
|---|---|---|---|
| C1 | Lead / interactive Phase 5 (an **LLM**, over Bash) | `plugins/leadv2/docs/phases.md:268-280` | **Yes, unconditional.** This is the 9×-re-review path in the evidence. |
| C2 | Product-close lane, `LEADV2_REVIEW_ENGINE=1` | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2425` | Yes |
| C3 | Product-close lane, `LEADV2_REVIEW_ENGINE=0` (**the default everywhere**) | its own inline `run_reviewer_arm()` body, same file, gated at `:2418-2425` | **NO — independent copy, uncapped.** See §4. |
| C4 | test harnesses | `plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh`, `test-review-engine-fanout-multiprovider.sh`, `test-review-machine-round0.sh`, `test-claim-evidence-gate.sh` | Yes (stubbed arms) |

There is **no programmatic retry loop** anywhere: nothing `while`-loops over the engine. Each round
is a *fresh process invocation* decided by C1's LLM judgement. Therefore the cap **cannot** live in
a caller loop — it must be a per-invocation decision made from on-disk state inside the engine.

### 1b. Functions touched, with their callers and callees

| Function | Defined | Called from | Calls |
|---|---|---|---|
| `_review_round_context` | `:592` | top-level `:891` (once) | `_review_highest_snapshot_round` `:539`, `_review_parse_findings` `:559`, `cmp`/`cp` snapshot `:614-619` |
| `_review_state_write` | `:684` | `:921` (selfcheck-RED exit 7), `:1307` (FAIL exit 7), `:1320` (PASS exit 0) — **all three verdict-producing exits, no others** | `sed`, `printf`, `mv` |
| `emit` (engine-local) | `:~76` | ~everywhere | `printf … >&2` **only — stderr, not the journal.** Header `DEVIATION NOTE` `:18-22` forbids calling the lane's journal `emit`. |
| `render_gate_findings` | sourced `:38-42` | `:1303`, `:1316` | n/a (stubbed to `:` if absent) |

**Callees the new code introduces:**
- `plugins/leadv2/scripts/leadv2-journal.sh append <task-id> <type> <text…>` — usage at that
  file `:2-6`; journal path `${PROJECT_ROOT}/docs/leadv2/tasks/<task-id>/journal.md`. Must be
  invoked as `bash "${JOURNAL_BIN}"` (the file ships non-executable — same reason
  `leadv2-dispatch-code.sh:452` does it that way) and overridable via `LEADV2_JOURNAL_BIN` so the
  tests stay hermetic.
- No other new callee. No new sourced library.

**The independent copy nobody named:** C3. `leadv2-dispatch-product-close.sh` keeps a byte-for-byte
inline review body used at `LEADV2_REVIEW_ENGINE=0`, which is the production default
(`phases.md:308-311` says this is deliberate). Any cap placed in the engine **does not apply to
C3**. This is stated, not fixed, here — see §4 and "Non-goals".

---

## 2. STATES AND RETURN CODES

### 2a. Existing exit codes and what each caller does with them

`8` is currently **unused** (`grep -n "exit 8"` → no hits), so it is free for the new terminal.

| rc | Written to `review-gate.md` | Site | What C1 (lead LLM) does | Plain-words user consequence |
|---|---|---|---|---|
| 0 | `status: pass` | `:1323` | ACCEPT → Phase 6 | change ships |
| 2 | *(nothing)* | `:57`, `:63` | usage error, aborts | operator sees a bad-args line; no review happens |
| 6 | `status: blocked` (`review_body_lost` / `no_verdict_marker`) | `:1070`, `:1144` | treats as a process finding, re-runs | another full fan-out is paid |
| 7 | `status: fail` | `:923`, `:1310` | spawns a developer fix round, **re-invokes the engine** | this is the loop that burns 110-140K per turn |
| 9 | `status: unreviewed` (`all_arms_unavailable`) | `:947` | escalates / waits for quota | no review; nothing merges |
| **8 (new)** | `status: blocked`, `reason: review_roundcap` | new | **must not spawn another review**; escalate to architect or PARK | *"this lane has been reviewed N times and is not converging — a human/architect decides, and no further reviewer money is spent on it today"* |

Terminal-outcome trace for rc 8: C1 is an LLM, so "must not" is enforced by construction, not by
trust — a re-invocation after the cap **re-enters the same cap branch, exits 8 again, and spawns
nothing**. The refusal is idempotent and costs ~0 tokens. That is the real guarantee; the
gate-file wording is only what makes the human-facing reason legible.

### 2b. Mechanism state table (state file `${HANDOFF}/.review-round.state`)

Proposed format — **append a third and fourth line, never reorder or remove the existing two**
(existing readers are `sed -n 's/^round=//p'` `:601,:689` and `s/^diff=//p'` `:602`, so extra
lines are inert to them):

```
round=<n>          # existing, unchanged semantics
diff=<8hex>        # existing, unchanged semantics
attempts=<n>       # NEW: verdict-producing, non-dedup runs
spawns=<n>         # NEW: runs that reached the fan-out (see §4 backstop)
```

| State | `attempts` on disk | `LEADV2_REVIEW_MAX_ROUNDS` | Engine behaviour |
|---|---|---|---|
| S0 first ever review | file absent | 2 | run; on verdict write `attempts=1` |
| S1 round 2 | `attempts=1` | 2 | run (1 < 2); write `attempts=2` |
| S2 round 3 — **the cap** | `attempts=2` | 2 | **refuse**: no pool resolve, no fan-out, no LLM spawn; write gate `blocked/review_roundcap`, write escalation file, journal `review_roundcap`, exit 8 |
| S3 re-invoked after cap | `attempts=2` | 2 | identical refusal, idempotent, exit 8 |
| S4 kill-switch | any | `0` | never caps; behaviour byte-identical to today |
| S5 corrupt/unparseable `attempts=` | garbage | 2 | **fail-open**: treat as 0, run the review, emit one stderr warn |
| S6 dedup run (`record-review` rc=2, `:1292`) | n | 2 | gate written as today; `attempts` **not** incremented (mission req 4); `spawns` **is** |
| S7 unhashable diff (`REVIEW_DIFF_HASH_OK=0`) | n | 2 | `_review_state_write` already returns early `:685` ⇒ no increment, no cap ⇒ fail-open by construction |

---

## 3. CONFIGURATION BOUNDARIES

### `LEADV2_REVIEW_MAX_ROUNDS` (new)

| Input | Behaviour |
|---|---|
| absent | default `2` (matches the declared policy at `phases.md:291`) |
| empty string | default `2` |
| `0` | **unlimited — kill-switch.** No cap check runs at all; zero behaviour delta vs today |
| `1` | caps after the first verdict; legal, useful for a burn emergency |
| `2` | the default |
| large (`100000`) | accepted as a plain integer; a cap that never fires is indistinguishable from the kill-switch, so **no clamping and no refusal** — an over-cap value must never take down more than its own decision |
| malformed (`two`, `-1`, `1.5`, `2;rm -rf /`) | default `2`, one stderr warn line. Never `eval`'d, never word-split — compared only inside `[[ … =~ ^[0-9]+$ ]]` and integer `-ge` |

### `${HANDOFF}/.review-round.state` (existing file, extended)

| Input | Behaviour |
|---|---|
| absent | `attempts=0`, `spawns=0` → run |
| empty file | same as absent → run |
| `attempts=` present but non-numeric / negative / >99999 | fail-open: 0 → run + warn (mirrors the existing `sidecar_round` clamp at `:605`) |
| file present, no `attempts=` line (**pre-upgrade lane, mid-flight**) | fall back to `round=<n>` as the attempt count — a lane already at `round=3` when this ships caps immediately rather than getting a free extra round |
| unreadable (perm/IO) | `sed` yields empty → 0 → run. Never a crash: file reads stay `2>/dev/null`, writes stay `|| true` (`:695`) |
| directory unwritable | `_review_state_write` already swallows via `|| true` `:695`; the cap simply never engages. Fail-open |

### `${HANDOFF}` and the escalation artifact

| Input | Behaviour |
|---|---|
| `HANDOFF` missing | `mkdir -p … || true` already at `:74`; escalation write is `.tmp`+`mv` with `|| true` |
| `review-roundcap-escalation.md` already exists | overwritten (it is a status artifact, not a log); prior content is not appended to |
| `review-gate.md` holds the prior round's real verdict | safe to overwrite — `_review_round_context:613-619` already snapshotted it to `review-gate.round<prior>.md` **before** the cap branch runs. Verify this ordering holds in the implementation; it is the one place a naive placement loses findings |

### `LEADV2_JOURNAL_BIN` (existing convention, reused)

| Input | Behaviour |
|---|---|
| absent | `${SCRIPT_DIR}/leadv2-journal.sh` |
| points at `/bin/true` (tests) | no journal write, everything else identical |
| missing/broken | `bash … || true` → the cap still fires; only the journal line is lost |

### Interaction with `LEADV2_REVIEW_ROUND` (existing test seam, `:633-648`)

The seam forces `REVIEW_ROUND`/`REVIEW_MODE` only. The cap reads `attempts`, which the seam does
not touch — so forcing round 1 or 2 **cannot** bypass the cap, and the cap cannot corrupt the
seam's mode selection. State this in a comment; a reviewer will ask.

---

## 4. COUNTEREXAMPLE — what still burns money after every mission finding is fixed

Three things, one of which is created by the mission's own requirement 4.

**(a) The dedup exemption is a hole, and it is the expensive one.** Requirement 4 says dedup rounds
must not increment. But `record-review` runs at `:1291` — *after* the full fan-out has already been
spawned and paid for. So a lane whose diff and verdict are stable produces rc=2 on every
invocation, never increments `attempts`, and can be re-reviewed unboundedly at full price while the
counter reads `1`. The dedup line is a *label on an already-paid round*, not a cheap short-circuit.
Mitigation, included in this design: a second counter `spawns=`, incremented unconditionally at the
moment the fan-out list is about to be launched (~`:950`, before any arm process starts), capped by
`LEADV2_REVIEW_MAX_SPAWNS` (default `3 × LEADV2_REVIEW_MAX_ROUNDS`, `0`/malformed ⇒ derived
default, kill-switched by `LEADV2_REVIEW_MAX_ROUNDS=0` too). It is the backstop that actually
bounds spend; `attempts` is the policy-legible number the escalation file quotes. ~10 lines, same
state file, same code block.

**(b) C3 — the product-close inline review body — is untouched.** At `LEADV2_REVIEW_ENGINE=0`,
the production default, the lane never calls this engine, so nothing in this lane caps it. Anyone
reading "review rounds are now capped" will be wrong about the default lane path. Must be said in
the docs paragraph in those words. Fixing C3 is a separate lane (its blast radius is the whole
product-close review body).

**(c) State is per-`HANDOFF`, so anything that changes the handoff dir resets the counter** — a
fresh worktree, a re-dispatched task with a new sig8, a manually cleaned `docs/handoff/<id>/`. This
is correct behaviour for a genuinely new task and indistinguishable from abuse; no defence is
proposed, only disclosure.

What I checked and found *not* to be holes: `LEADV2_REVIEW_ROUND` seam (§3, cannot bypass); the
machine-round-0 selfcheck exit `:908-927` (exits before any LLM spawn — cheap, and it increments
`attempts` via `_review_state_write:921`, which is correct: it *is* a verdict); `exit 9`
all-arms-unavailable `:947` (no `_review_state_write`, so a quota outage cannot burn the lane's
round budget — verified by reading, and worth an assertion in the test file).

---

## 5. CHANGES — exact files and placement

### 5.1 `plugins/leadv2/scripts/leadv2-review-run.sh` (the only production file)

| # | Placement | Change |
|---|---|---|
| E1 | new helper beside `_review_state_write`, ~`:698` | `_review_roundcap_read` → prints `attempts spawns` (two ints, fail-open 0 0); `_review_roundcap_limit` → resolves `LEADV2_REVIEW_MAX_ROUNDS` per §3 |
| E2 | `_review_state_write` `:684-697` | write four lines instead of two; `attempts` = prior+1 unless `REVIEW_DEDUP=1`; `spawns` carried through. Keep the existing never-decrease clamp (`:692-693`) and extend it to both new counters |
| E3 | `:1292-1296` dedup branch | set `REVIEW_DEDUP=1` in the rc=2 arm before the gate is written |
| E4 | **after `:894`** (`emit decision "review_round …"`), **before** the machine-round-0 block at `:908` | the cap branch: read counters, resolve limit, and when `limit>0 && attempts>=limit` → write `review-gate.md` (`status: blocked` / `reason: review_roundcap` / `rounds:` / `max_rounds:` / `escalation:`), write `review-roundcap-escalation.md`, journal `review_roundcap task=<id> rounds=<n>`, print the loud stderr banner, `exit 8`. Placed here because `_review_round_context` (`:891`) has already snapshotted the prior gate, and because nothing after this point is free |
| E5 | ~`:950`, immediately before the fan-out launch | `spawns` pre-increment + `LEADV2_REVIEW_MAX_SPAWNS` backstop refusal (same exit-8 terminal, `reason: review_spawncap`) |
| E6 | header comment block `:1-27` | three lines: the engine now enforces the round cap; `phases.md:291` is superseded; C3 is not covered |

Loud terminal line (stderr, exactly one banner, greppable):
```
[leadv2-review-run] REVIEW ROUNDCAP: task=<id> rounds=<n> max=<m> — refusing a further review round.
[leadv2-review-run] This lane needs architect escalation or PARK. See docs/handoff/dispatch-<id>/review-roundcap-escalation.md
```

Style constraints that will be reviewed: bash 3.2 only (no `declare -A`, no `${x^^}`); `set -uo
pipefail` is already in force so every new var is initialised; no `-e`; every external call
`|| true`; `shellcheck -x -e SC1091,SC2034` must stay clean (the existing suite asserts it at
`test-review-round-exhaustive.sh:28`).

### 5.2 `plugins/leadv2/scripts/tests/test-review-roundcap.sh` (to-create)

Mirror `test-review-round-exhaustive.sh` exactly: self `bash -n`, `bash -n` + `/bin/bash -n` +
shellcheck of the engine, stub-resolver/stub-arm harness (**zero network**),
`mktemp -d` + `trap rm -rf EXIT`, `LEADV2_JOURNAL_BIN=/bin/true`,
`LEADV2_DISPATCH_BIN=<stub>`, `PASS/FAIL` counters, red-first baseline. Cases:

1. round 1 → runs; `.review-round.state` contains `attempts=1`
2. round 2 → runs; `attempts=2`
3. round 3 → **rc 8**, `review-gate.md` has `status: blocked` + `reason: review_roundcap`,
   `review-roundcap-escalation.md` exists, **no reviewer arm was invoked** (stub arm writes a
   marker file; assert the marker is absent — this is the assertion that proves money was saved)
4. dedup round (stub `record-review` → rc 2) does **not** increment `attempts`
5. `LEADV2_REVIEW_MAX_ROUNDS=0` at `attempts=9` → runs, rc ≠ 8
6. corrupt `attempts=` (`attempts=banana`) → fail-open, review runs
7. state file with only the legacy two lines and `round=3` → caps (pre-upgrade lane)
8. `exit 9` (all arms unavailable) leaves `attempts` unchanged
9. re-invoke after cap → still rc 8, still no arm invoked (idempotence)
10. `spawns` backstop fires when dedup keeps `attempts` frozen

### 5.3 `plugins/leadv2/scripts/tests/run-core-offline.sh`

One registry line beside `:313`:
`"review round cap (REVIEW-ROUNDCAP-01)|||bash $TEST_DIR/test-review-roundcap.sh"`.

### 5.4 `plugins/leadv2/docs/phases.md`

Rewrite `:291` (currently *"Round cap is enforced by LEAD, not the engine."*) into one paragraph:
the engine now refuses round `LEADV2_REVIEW_MAX_ROUNDS+1` itself and exits 8 with
`status: blocked` / `reason: review_roundcap`; the lead's job is to read the escalation file and
choose architect-escalate or PARK; `0` disables; **and the C3 caveat — the
`LEADV2_REVIEW_ENGINE=0` product-close inline path is not covered.**

---

## 6. RISKS

| # | Risk | Mitigation |
|---|---|---|
| R1 | Cap placed before the gate snapshot ⇒ prior round's findings destroyed | Placement E4 is after `:891`; test case 3 asserts `review-gate.round2.md` still exists post-cap |
| R2 | A lane legitimately mid-convergence gets capped at 2 and stalls silently | `status: blocked` is already defined as never-a-pass (`phases.md:292-295`); escalation file names the two exits explicitly; `LEADV2_REVIEW_MAX_ROUNDS` raises it per-invocation |
| R3 | New rc 8 unhandled by an existing caller ⇒ treated as generic failure | 8 is unused today; C2 (product-close at flag=1) must be checked for a bare `rc != 0 ⇒ retry` branch during implementation. **If such a branch exists, the cap creates a new infinite loop** — implementer must grep the flag=1 call site before writing E4 |
| R4 | Counter file becomes a second source of truth vs. the gate snapshots | Single writer (`_review_state_write`) preserved; monotonic clamp preserved; no new writer added |
| R5 | Edit lands in a stale copy ⇒ fix never runs | §0 check command; canonical is inode-identical to plugin-root, verified |
| R6 | shellcheck/bash-3.2 regression fails 3 existing suites | E1-E6 add no bashisms; suites 1-3 of the new file re-assert it |

---

## 7. NON-GOALS (implementer: ignore these)

- Fixing C3 (`leadv2-dispatch-product-close.sh` inline review body at `LEADV2_REVIEW_ENGINE=0`).
- De-duplicating the two stale 40454-byte `leadv2-review-run.sh` copies.
- Changing dedup semantics, `record-review`, or the diff-hash mechanism.
- Changing `REVIEW_ROUND` / `REVIEW_MODE` (exhaustive vs verify_only) selection logic.
- Auto-PARKing the lane or auto-spawning an architect. The cap **refuses and reports**; a human or
  the lead decides. Automating the escalation is a follow-up lane.
- Touching `docs/leadv2/*` state files or any handoff dir other than the lane's own.
- Any change to `.claude/scripts/` or `~/.claude/leadv2-shared/`.

---

## acceptance:

```yaml
acceptance:
  - surface: file_artifact
    observable: "In the lane's handoff folder there is a file named review-roundcap-escalation.md
      whose text says the lane has been reviewed twice without converging and that it now needs
      architect escalation or PARK."
    authored_at: 2026-08-24T00:00:00Z
  - surface: rendered_line
    observable: "review-gate.md's first status line reads 'blocked' with the reason
      'review_roundcap', and the same file still shows how many rounds were spent and what the
      configured maximum was."
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: "The lane's journal shows a review_roundcap entry naming the task and the round
      count, and the terminal shows a two-line banner saying a further review round was refused."
    authored_at: 2026-08-24T00:00:00Z
  - surface: file_artifact
    observable: "On that third attempt no reviewer transcript appears in the handoff folder — the
      set of review-<arm>.md files is unchanged from the second round, i.e. no reviewer was paid."
    authored_at: 2026-08-24T00:00:00Z
  - surface: rendered_line
    observable: "With the kill-switch set to unlimited, a lane on its tenth attempt still produces
      a normal pass/fail review gate, indistinguishable from today's output."
    authored_at: 2026-08-24T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-roundcap.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/phases.md

DELIVERABLE_COMPLETE
