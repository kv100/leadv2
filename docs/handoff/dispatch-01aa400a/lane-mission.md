Product implementation task dispatch-01aa400a. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# PHASES-ARE-THE-ONLY-PATH-01 — fix round 5 — architect prepass

Base: `f91fd70`, worktree `.claude/worktrees/d4d014e1`. Do not rebase.
Scope: exactly B1 and B2. Two optional zero-cost items, explicitly gated.

---

## 0. Evidence read (what is actually on disk at f91fd70)

| Fact | Location |
|---|---|
| Review proof = `grep -F '"diff_hash":"<h>"' ledger \| grep -qE '"verdict":"(PASS\|PASS_WITH_NITS)"'` | `leadv2-phase-record.sh:399-417` |
| Ledger file = `${CACHE_BASE}/code-review-ledger/<repo_slug>.jsonl` | `leadv2-phase-record.sh:408`, `leadv2-dispatch-code.sh:366` |
| Sole intended writer = `record_review()`, one `printf … >> "$f"` | `leadv2-dispatch-code.sh:1294-1300` |
| Writer is wrapped by `atomic_review_check_and_record()` under `review_lock_file()` | `leadv2-dispatch-code.sh:1301-1317` |
| CLI entry = `record-review`, default `reviewer="codex:standard"`, `run_id="manual"` | `leadv2-dispatch-code.sh:2255-2295` |
| The ONLY production caller = product-close, `--reviewer "${reviewer}" --run-id "dispatch-${TASK}"` | `leadv2-dispatch-product-close.sh:1697` |
| `reviewer` value comes from the arm resolver, `DEFAULT_REVIEW_ARM_ORDER = ["codex","glm","kimi","opus","sonnet"]` | `scripts/lib/leadv2-glm-policy-resolve.py:66`; per-repo override key `review_arm_order` (:125-131) |
| Live ledger rows observed | `reviewer` ∈ `{codex, glm, opus}`, `run_id` = `dispatch-<sig8>` — `~/.claude/cache/code-review-ledger/{persona-engine,feeddark,replyaud}.jsonl` |
| `sanitize_field` permits `A-Za-z0-9._:/-` — so `self-forged` survives sanitisation and so would any invented arm | `leadv2-dispatch-code.sh:1321` |
| Guard has NO pre-subprocess early return; mode `0` still shells out and still refuses on rc 4 | `leadv2-phase-record.sh` caller `leadv2-dispatch-code.sh:1502-1557` |
| `phases.d` readers | `leadv2-phase-record.sh` (`show`, `assert`), `leadv2-status-surface.sh:3049-3140` (`lane_phase`) |
| `lane_phase` renders every finished record identically as `"<phase> (done)"` | `leadv2-status-surface.sh:3130-3136` |

**Confirmation of the B1 reproduction.** Nothing in `_verify_artifact review` reads any field
other than `diff_hash` and `verdict`. `reviewer` and `run_id` are written and never read. A raw
`>>` append with a correctly-computed hash therefore satisfies the check. The R4 tests (G5a wrong
hash, G5b wrong verdict) do not cover it. Confirmed by reading, consistent with the reviewer's
live reproduction.

---

## 1. B1 — de-self-attest the review ledger

### 1.1 The bar, restated

Not "unforgeable". The bar the mission sets: **a worker cannot satisfy its own review phase from
inside its own run.** Achieve it with provenance. Three properties, all enforced inside
`_verify_artifact review` and `cmd_record_review`. Each is stated below with what it does NOT stop.

### 1.2 R1 — reviewer allowlist (read side, `leadv2-phase-record.sh`)

The matching ledger row's `reviewer` field, truncated at the first `:` (so `codex:standard` →
`codex`), must be a member of the review-arm vocabulary. **The vocabulary is not invented here** —
it is `DEFAULT_REVIEW_ARM_ORDER` from `leadv2-glm-policy-resolve.py:66`:

```
codex  glm  kimi  opus  sonnet
```

Read side gains:

```
LEADV2_REVIEW_ARMS   default "codex,glm,kimi,opus,sonnet"
```

Rationale for the env override: `review_arm_order` is a documented per-repo routing.yaml key
(`leadv2-glm-policy-resolve.py:125-131`). A repo that adds a novel arm would otherwise have every
legitimate review rejected. The override is the escape hatch; the default is the five.

Implementation shape — replace the two-stage grep at `leadv2-phase-record.sh:412-415` with a single
python3 line-scanner over the ledger that parses each line as JSON and applies R1 ∧ R2 ∧ verdict ∧
diff_hash together. Do **not** try to do this with chained greps: `grep -F diff_hash | grep verdict`
already conflates fields across a line, and adding two more field predicates by grep makes that
worse. One `python3 -` heredoc, exit 0/1, is the correct construct here — the file already uses
that pattern (`_read_phases_yaml`, `_resolve_mandatory`). Malformed JSON line → skip that line, do
not abort (a legacy or truncated row must not blind the check to a good row later in the file).

**R1 does not stop:** a forger who writes `"reviewer":"codex"`. It stops the exact reproduced
attack string (`self-forged`), an empty reviewer, and any un-vocabularied value.

### 1.3 R2 — the writer refuses to run inside a lane worktree (write side, `leadv2-dispatch-code.sh`)

This is the property that actually carries "a different process than the one asserting".

`cmd_record_review` refuses, before touching the ledger, when it is executing inside a linked git
worktree — i.e. when the build worker calls it from its own lane:

```
git -C "$PWD" rev-parse --git-dir           != 
git -C "$PWD" rev-parse --git-common-dir     →  linked worktree  →  refuse
   OR  realpath "$PWD" matches */.claude/worktrees/*   →  refuse
```

On refusal: `emit decision "review_record_refused reason=lane_worktree cwd=<path>"`, print
`review_refused reason=lane_worktree`, exit 1. The row is never written, so the read side never
sees it.

This works because product-close (`leadv2-dispatch-product-close.sh:1697`, the only production
caller) is spawned by dispatch-code from the **main repo root**, whereas a build worker lives in
`.claude/worktrees/<sig8>`.

> **MUST-VERIFY BEFORE DEFAULT-ON.** The implementer must empirically confirm the CWD of a live
> product-close invocation of `record-review` — add a one-shot `emit decision "review_record_cwd
> cwd=$PWD common_dir=..."` line, run one real lane, read the journal, then remove it. If
> product-close turns out to run *inside* the lane worktree, R2 as specified would refuse **every**
> legitimate review and must be re-based on an explicit env marker minted by dispatch-code
> (`LEADV2_REVIEW_RECORDER=1`, exported only on the product-close spawn) instead of on CWD.
> Ship R2 behind `LEADV2_REVIEW_RECORDER_GUARD` (default `1`, `0` disables) either way.

**R2 does not stop:** a worker that `cd`s to the main repo root (or unsets the marker) before
calling `record-review`. It stops the ordinary in-lane case, which is the stated bar.

### 1.4 R3 — raw appends become detectable (both sides)

`record_review()` maintains, **under the existing `review_lock_file()` lock** (i.e. inside
`atomic_review_check_and_record`, not in `record_review` itself, so the count and the append are one
critical section), a sidecar:

```
${REVIEW_LEDGER_DIR}/<slug>.jsonl.rows      # a single integer: rows record_review has written
```

Write side: after the successful `>>` append, `rows := rows + 1` (atomic: write temp in the same
dir, `mv -f`).

Read side, in `_verify_artifact review`, before any row matching:

- sidecar **absent** → legacy ledger. Accept (do not fail closed), and
  `_emit "review_ledger_unchained" "repo=<slug>"`. Without this, every pre-existing lane in every
  repo breaks the moment the change lands. The first `record_review` after the change bootstraps
  the sidecar to the then-current `wc -l`.
- sidecar **present** and `wc -l < ledger` **≠** sidecar value → tampered.
  `_emit "review_ledger_tamper" "repo=<slug> ledger_rows=N recorded_rows=M"` and **return 1 for the
  review phase regardless of row contents**. The reproduced attack (hand-append) lands here.
- sidecar present and counts equal → proceed to R1 + verdict + diff_hash matching.

**R3 does not stop:** a forger who also increments the sidecar, or who calls `record-review`
properly. It converts the silent hand-append into a loud, journaled, whole-repo refusal.

### 1.5 Honest summary of B1 — write this verbatim into the return report

> Enforced: (R1) the ledger row's reviewer must be one of the five arms the review pool actually
> dispatches; (R2) `record-review` refuses to run from inside a lane worktree, so a build worker
> cannot mint a row from its own run; (R3) a raw `>>` append to the ledger is detected by a
> row-count sidecar and refuses the whole repo's review proofs until reconciled.
>
> NOT stopped: a worker that leaves its worktree (or unsets `LEADV2_REVIEW_RECORDER_GUARD`) and
> shells out to `record-review --reviewer codex` writes a row that is indistinguishable from a real
> one. There is no signature and no secret, so provenance is behavioural, not cryptographic. What
> the change buys is that every remaining forge path is *attributable*: it goes through the audited
> `record-review` entry point and leaves a `review_recorded` journal event naming a real arm and a
> run-id. This is a detection property, not a prevention property. It is not unforgeable.

### 1.6 B1 tests (`tests/test-phase-precondition.sh`, new group G7)

Model each on the existing G5 sandbox scaffold (`:363-417`): temp repo, `LEADV2_PROJECT_ROOT`,
`LEADV2_DISPATCH_CACHE_DIR`, a `review.diff`, a `phases.d/review.yaml`.

| id | setup | expect |
|---|---|---|
| G7a | correctly-hashed row, `"verdict":"PASS"`, `"reviewer":"self-forged"`, sidecar count matches | `assert` exits 3, `missing=` contains `review` |
| G7b | correctly-hashed PASS row with allowlisted `"reviewer":"codex"` **hand-appended** (sidecar not incremented) | `assert` exits 3, `missing=` contains `review` |
| G7c | row written by the real path (`record-review` from the sandbox main root, sidecar incremented) | `assert` exits 0 |
| G7d | `record-review` invoked with CWD inside a linked worktree of the sandbox repo | non-zero exit, ledger line count unchanged |
| G7e | sidecar absent entirely (legacy), correctly-hashed PASS row with `"reviewer":"glm"` | `assert` exits 0 — back-compat |

G7a, G7b, G7d must each fail against `f91fd70`. G7c and G7e are regression guards and may pass
against `f91fd70`; state that split explicitly in the return report rather than claiming all five
are new-failing.

---

## 2. B2 — `LEADV2_REQUIRE_PHASES=0` is a full disable again

### 2.1 Change

At the top of `_phase_precondition_guard` (`leadv2-dispatch-code.sh:1502`), **before** the mode
normalisation block and before any `bash "${PHASE_RECORD_BIN}"` call:

```bash
_phase_precondition_guard() {
  # B2: mode 0 is the documented rollback and the emergency kill switch. It must be
  # byte-identical to pre-C4 behaviour: no subprocess, no journal event, no refusal for
  # ANY reason including a malformed phases.yaml or a refused waiver. Round 4 removed
  # this return and made `=0` able to refuse on rc 4 — that is not a kill switch.
  [[ "${REQUIRE_PHASES}" == "0" ]] && return 0
  local sig8="$1" cls="$2" writes="${3:-}"
  ...
```

Read `REQUIRE_PHASES` (the already-resolved global at `:426`), not `LEADV2_REQUIRE_PHASES`, so a
single resolution point is preserved.

The `phase_precondition_badmode` normalisation at `:1514-1517` stays as-is and still maps unknown
values to `warn` — `0` no longer reaches it, which is correct because `0` is a known value.

Delete the now-false comment at `:1510-1512` and the `even in mode 0` clause at `:1546`.

### 2.2 B2 test (new, G8)

Sandbox: `LEADV2_REQUIRE_PHASES=0`, a `.claude/leadv2-overrides/phases.yaml` containing a rejected
key (e.g. `class_overrides: {Standard: {remove: [review]}}` — a removal, hard-rejected at
`leadv2-phase-record.sh:244-246` with exit 4), plus a `--waiver review=whatever` (hard-excluded at
`:615-618`, also exit 4). Both are guaranteed rc-4 producers at `f91fd70`.

Expect: the guard returns 0, dispatch proceeds to spawn, and the journal contains **no**
`phase_precondition_*` event of any kind for that sig8. Fails against `f91fd70` (which refuses).

If the guard is not directly callable from the test harness, invoke it the way the existing
precondition tests do; if the file's structure forces a full dispatch, assert on the journal absence
plus the spawn event rather than on a return code — the acceptance surface is the journal line, not
the exit status.

---

## 3. Honesty requirement — self-attested phases must not read as proven

`test`, `live_verify`, `e2e` are integrity-only (`leadv2-phase-record.sh:418-423`). The header
doc-block already says so. The gap: the **status** surface does not.

### 3.1 Change (inside the write set)

1. `cmd_record` writes one additional flat field, derived purely from the phase id:

   ```
   proof: attested      # test | live_verify | e2e
   proof: verified      # everything else
   ```

   Additive and last-but-one in the record; `flat_yaml` in status-surface reads flat keys, so an
   unknown extra key is inert there. `_verify_artifact` does not read it — it is a disclosure
   field, not a control field, and must not become one.

2. `cmd_show` gains a `PROOF` column rendering `self-attested` for `proof: attested` and
   `verified` for `proof: verified` / absent. A record written before this change has no `proof:`
   key and renders `verified` — acceptable, because pre-change `test` records do not exist in
   practice (the header notes no writer records these `done` today).

### 3.2 Explicit non-goal

`leadv2-status-surface.sh:lane_phase` still renders `"<phase> (done)"` for every finished record,
so a `test` phase in the panel does not yet read as self-attested. **That file is not in the write
set for this round.** Do not touch it. Report it as the residual with a one-line suggested follow-up
(`lane_phase` reads `rec.get("proof")` and renders `"test (self-attested)"`).

---

## 4. Non-blocking items — recommendation

| Item | Call |
|---|---|
| Artifact path may resolve outside `PROJECT_ROOT` (`_artifact_integrity:340`, the bare `-f "$artifact"` branch) | **DEFER.** Not zero-cost: any existing record whose `artifact:` was stored absolute would start failing. Needs its own compat sweep. Note it in the report; do not fix here. |
| Deploy ancestor check has no positive-pass test | **DO.** Genuinely cheap: sandbox repo, commit on `main`, `origin/main` ref pointing at a descendant, `deploy.yaml` with matching artifact + commit → `assert` exits 0. |
| `_sha256` fail-closed on missing/dir/unreadable | Already confirmed. Leave. |

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R-1 | R2's worktree detection refuses every legitimate review if product-close runs inside the lane | The MUST-VERIFY step in §1.3, plus `LEADV2_REVIEW_RECORDER_GUARD=0` escape. Do not land R2 default-on without the empirical CWD reading. |
| R-2 | R3's sidecar fails closed on every pre-existing repo | Absent sidecar = legacy = accept + journal. Explicit in §1.4. |
| R-3 | Swapping grep for python3 in the review check changes behaviour on malformed ledger lines | Skip-and-continue per line, never abort. Add an assertion in G7c that a preceding malformed line does not hide a good row. |
| R-4 | Concurrent access: `<slug>.jsonl` and `<slug>.jsonl.rows` are read by `assert` (many lanes) while `record_review` writes them | Writer holds `review_lock_file()`; reader does not lock. A read racing an append sees counts off by one → spurious tamper refusal. **Mitigation: the reader treats `ledger_rows == sidecar + 1` as in-flight, re-reads once after a 200 ms sleep, and only then declares tamper.** Do not add a reader lock — that would serialise every assert behind every review. |
| R-5 | B2's early return could be read as re-opening the rc-4 hole the R4 change was trying to close | It is deliberate and founder-ordered: `=0` is the kill switch. The config-error refusal survives in `warn` and `1`. Say so in the commit message. |
| R-6 | The five-arm allowlist drifts if `DEFAULT_REVIEW_ARM_ORDER` changes | Add a comment in `leadv2-phase-record.sh` naming `leadv2-glm-policy-resolve.py:66` as the source of truth, and a note in that file pointing back. Not enforced mechanically. |

## 6. Constraint checklist

1. **Env naming** — `LEADV2_REVIEW_ARMS`, `LEADV2_REVIEW_RECORDER_GUARD`. Both `LEADV2_*`, consistent with `LEADV2_REQUIRE_PHASES` / `LEADV2_PHASE_RECORD_BIN`. No `LEAD_V2_*` drift. PASS.
2. **File paths** — all four write-set paths exist on disk at `f91fd70`; verified by `wc -l` /
   `grep`. The sidecar `<slug>.jsonl.rows` is `(to-create)` at runtime, not a repo file. PASS.
3. **`claude -p` commands** — none introduced. N/A.
4. **Concurrent access** — R-4 above. Addressed.
5. **Config contradiction** — `REQUIRE_PHASES` is read at `:426` and used only in
   `_phase_precondition_guard`; the early return is the single new consumer. `reviewer` semantics
   unchanged on the write side except for the refusal. No contradiction found. PASS.

## 7. Out of scope — implementer must not touch

- `leadv2-status-surface.sh` (including `lane_phase`) — §3.2.
- `leadv2-dispatch-product-close.sh` — the caller stays as-is; only the callee refuses.
- Rebasing off `f91fd70`.
- The artifact-path-outside-root fix (§4).
- Any signing, HMAC, or key material. Explicitly excluded by the mission.
- Changing the `reviewer` vocabulary or adding a new arm name.

---

acceptance:
- surface: rendered_line
  observable: "`leadv2-phase-record.sh show <sig8>` prints a PROOF column in which the `test` row reads `self-attested` while the `review` row reads `verified`."
  authored_at: 2026-08-05T13:10:23Z
- surface: log_line
  observable: "After a row is hand-appended to `code-review-ledger/<slug>.jsonl`, the task journal contains a `review_ledger_tamper repo=<slug> ledger_rows=<N> recorded_rows=<M>` line, and the dispatch that follows prints `dispatch refused: missing mandatory phases: review`."
  authored_at: 2026-08-05T13:10:23Z
- surface: log_line
  observable: "With `LEADV2_REQUIRE_PHASES=0` and a phases.yaml that contains a removal key, the journal for that lane shows the lane's spawn event and contains no `phase_precondition_` line of any kind."
  authored_at: 2026-08-05T13:10:23Z
- surface: file_artifact
  observable: "`~/.claude/cache/code-review-ledger/<slug>.jsonl.rows` exists after a real review is recorded, and the integer it contains equals the number of lines in `<slug>.jsonl`."
  authored_at: 2026-08-05T13:10:23Z
- surface: log_line
  observable: "`record-review` invoked with the working directory inside `.claude/worktrees/<sig8>` prints `review_refused reason=lane_worktree` and the ledger file's line count is unchanged afterwards."
  authored_at: 2026-08-05T13:10:23Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-phase-precondition.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# PHASES-ARE-THE-ONLY-PATH-01 — fix round 5 (plugin repo ~/Projects/leadv2)

Round 4 is `f91fd70` in worktree `d4d014e1`. Reviewed: two blocking findings. Full report:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-review-r4.md`.
Continue from `f91fd70`. Scope is exactly B1 and B2. Nothing else.

## B1 — BLOCKING. The review ledger is self-attestable.
The review check requires a ledger row whose `diff_hash` equals `sha256(review.diff)`. Whoever
writes `review.diff` can compute that hash and hand-append
`{"diff_hash":"<hash>","verdict":"PASS","reviewer":"self-forged"}` to
`code-review-ledger/<slug>.jsonl`. Reproduced live in this worktree — `assert` then reports review
satisfied. The new G5a/G5b tests only cover a WRONG hash and a WRONG verdict, never the
correctly-hashed self-forge, which is the case that matters.

**We are not trying to defeat a determined attacker — there is no signing here and none is wanted.
The bar is: a worker cannot satisfy its own review phase from inside its own run.** Achieve that
with provenance, not cryptography. Choose and implement:
- constrain `reviewer` to a known set (the values `record-review` actually writes — find them, do
  not invent a new vocabulary), and reject rows whose reviewer is outside it;
- require the row to have been written by a DIFFERENT process than the one asserting — e.g. the
  row's timestamp must precede the assert and the ledger entry must carry the run-id/handle of a
  review invocation, not of the build worker;
- and make the ledger append path go only through `record-review`, so a raw append is detectable.
State in your report exactly which property you enforced and what it does NOT stop. Do not claim
unforgeability.

Add tests: correctly-hashed row with an unknown `reviewer` → review NOT satisfied. Correctly-hashed
row written by the asserting run itself → review NOT satisfied. Legitimate `record-review` row →
satisfied.

## B2 — BLOCKING. `LEADV2_REQUIRE_PHASES=0` is no longer a full disable.
Round 4 removed the pre-C4 early return that short-circuited before any subprocess. Mode `0` now
always shells out to `phase-record.sh assert` and can still refuse (exit 3 → 1) on config errors or
a refused waiver. `=0` is the documented rollback and the emergency kill switch; it must be
byte-identical to pre-C4 behaviour and must never refuse for any reason.

Restore the early return at the top of the guard, before any subprocess call. Add a test: `=0` with
a deliberately broken phases.yaml and a refused waiver still proceeds, journals nothing, spawns.

## Non-blocking — do these only if they cost nothing
Artifact path resolution allows paths outside `PROJECT_ROOT`; the deploy ancestor check fails
closed but has no positive-pass test. `_sha256` already fails closed on missing/dir/unreadable —
confirmed, leave it.

## Honesty requirement
`test` / `live_verify` / `e2e` remain self-attestable: the artifact is a file the worker wrote and
the only check is that it still hashes the same. The code already says so. Keep that disclosure
and make sure the phase's recorded status reflects it — a self-attested phase must not read as
equivalent to an independently-proven one on the status surface.

## Base / write set
Worktree `d4d014e1`, on top of `f91fd70`. Do not rebase.
`leadv2-phase-record.sh`, `leadv2-dispatch-code.sh`, `tests/test-phase-precondition.sh`,
and `leadv2-dispatch-code.sh`'s review-recording path if B1 needs it. Nothing else.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw output of both test runs (against `f91fd70`
and after). Every new test must fail against `f91fd70`.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-01aa400a" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.