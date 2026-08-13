# PHASES-ARE-THE-ONLY-PATH-01 — round 3 architect prepass (F1/F2/F3)

Base verified in worktree `d4d014e1` @ `b29f9b2`. All three findings reproduce verbatim.
Scope of this design: **F1, F2, F3 only**. No rebase, no refactor, no unrelated test edits.

---

## 0. Verification of the three findings in the round-2 tree

| Finding | Location | Verbatim evidence |
|---|---|---|
| F1 | `plugins/leadv2/scripts/leadv2-phase-record.sh:326-332` | `local ledger_file="${ledger_dir}/${slug}.jsonl"` / `[[ -s "$ledger_file" ]] && return 0` — repo-wide non-emptiness, no diff-hash, no verdict |
| F2 | same file `:320-323` (`build`), `:334-337` (`test\|deploy\|live_verify\|e2e`) | `[[ -n "$artifact" && -f "$artifact" ]] && return 0` — bare existence. `p_sha` is read at `:565` and passed as `$4` to `_verify_artifact`, which binds it to `sha` at `:304` and **never references it again** |
| F3 | `plugins/leadv2/scripts/tests/test-phase-precondition.sh` (192 lines, 10 test blocks) | zero occurrences of `REQUIRE_PHASES`, `cmd_resolve`, or `leadv2-dispatch-code.sh` being *executed*. `DISPATCH_BIN` is assigned at `:9` and never used. Every test calls `phase-record.sh assert\|plan-for` directly |

Confirmed also: `_verify_artifact`'s `sha` parameter is currently unused across all cases —
`artifact_sha256` is write-only state.

---

## 1. Discovery: the canonical diff-hash (required by F1)

**Do not invent a second hashing scheme.** The single producer is:

- `leadv2-dispatch-product-close.sh:1028` — `diff_file="${HANDOFF}/review.diff"`, where
  `HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"` (`:83`).
- `leadv2-dispatch-product-close.sh:1488` — `diff_hash="$(shasum -a 256 "${diff_file}" | awk '{print $1}')"`
- that value is passed verbatim to `leadv2-dispatch-code.sh record-review --diff-hash` (`:1697`),
  which validates it is 64-hex (`sig_is_hex`, `:2275`) and appends via `record_review()` (`:1294-1299`):
  `{"diff_hash":"…","verdict":"…","reviewer":"…","run_id":"…","repo":"…","ts":"…"}`
- ledger path: `review_ledger_file()` (`:443`) = `${CACHE_BASE}/code-review-ledger/$(repo_slug).jsonl`

So **the lane's current diff-hash is `sha256(docs/handoff/dispatch-<sig8>/review.diff)`**, and
`phase-record.sh` already has the identical primitive: `_sha256()` at `:64`
(`shasum -a 256 "$1" | awk '{print $1}'`). Reuse `_sha256`; add no new hashing code.

`review-gate.md` (the recorded `review` artifact) carries only `diff: <first 8 chars>` — an
8-hex prefix is not a proof and must not be used as the join key.

### Sibling discovery (non-blocking, do NOT fix this round)
`leadv2-dispatch-product-close.sh:1492` pre-checks a **different** directory —
`.../review-ledger/…` — while the authoritative writer uses `.../code-review-ledger/…`. The
pre-check therefore never dedups. Out of scope; log it as a follow-up thread.

---

## 2. Discovery: which phases actually have writers today

Grep of every `phase-record.sh record` call site:

| Phase | Writer | Status written |
|---|---|---|
| `classify` | `dispatch-code.sh:2485` | `done` (no artifact — meta-phase) |
| `plan` | `dispatch-code.sh:2524` | `done` + artifact |
| `build` | `dispatch-code.sh:2812, 2846, 3069` | **`running` only — never `done`** |
| `review` | `product-close.sh:1444` / `:1717` | `running` → `done` + `review-gate.md` |
| `e2e` | `product-close.sh:1338` | **`running` only** |
| `close` | `phase8-close.sh:258` | `done` |
| `test`, `deploy`, `live_verify` | **no writer anywhere** | — |

Consequence for F2: tightening `build`/`test`/`deploy`/`live_verify`/`e2e` is **fail-closed with
zero live-behaviour regression today**, because nothing currently records those phases `done`.
`running` is already unproven at `cmd_assert:579-581`.

---

## 3. Design

### 3.1 New shared helper — artifact integrity (applies to every artifact-bearing phase)

```
_artifact_integrity <artifact> <recorded_sha>   # rc 0 = intact, 1 = not
```
Resolution rules, in order (mirrors `cmd_record:417-421` exactly so record and assert agree):
1. `${PROJECT_ROOT}/${artifact}` if it is a regular file, else `${artifact}` if it is a regular
   file, else **rc 1**.
2. `recorded_sha` empty ⇒ **rc 1** (a record written before this change, or written for a file
   that did not exist at record time, is not a proof).
3. `_sha256 <resolved>` ≠ `recorded_sha` ⇒ **rc 1**.

This single helper closes the overwrite-after-record hole for all five F2 phases, and is the
`sha` parameter's first actual use.

### 3.2 F1 — `review` case rewrite

```
review)
  lane_diff = ${PHASES_DIR_BASE}/dispatch-${sig8}/review.diff
  [[ -s lane_diff ]]            || return 1     # no diff for this lane ⇒ nothing was reviewed
  h = _sha256 lane_diff                          # SAME scheme as product-close.sh:1488
  ledger = ${CACHE_BASE}/code-review-ledger/$(slug).jsonl
  [[ -f ledger ]]               || return 1
  scan ledger for a row with "diff_hash":"<h>" AND "verdict":"PASS"|"PASS_WITH_NITS"
  found ⇒ 0, else 1
```

Row matching: the ledger is one JSON object per line with fixed key order and no nesting
(`record_review`'s `printf` is the only writer). A `grep -F '"diff_hash":"<h>"'` filter followed
by a `grep -E '"verdict":"(PASS|PASS_WITH_NITS)"'` on the *same* line is exact and adds no
dependency. `FAIL` rows must not satisfy the phase.

`slug` derivation stays as-is (`basename "${LEDGER_REPO_ROOT:-${PROJECT_ROOT}}"`) — note it must
match `repo_slug()` in `dispatch-code.sh:432-442`; if that function sanitizes, mirror the
sanitization. Verify at implementation time; a mismatched slug silently reads the wrong file.

### 3.3 F2 — per-phase proofs

Every case below runs `_artifact_integrity` **first**; failure short-circuits to rc 1.

| Phase | Proof beyond integrity | Proof level |
|---|---|---|
| `build` | lane diff vs its own base is **non-empty** (§3.4) | **full** |
| `deploy` | recorded commit is an ancestor of `origin/main` (§3.5) | **full** |
| `close` | unchanged — `phase8-passed.flag` non-empty | full (already real) |
| `test` | none available | **integrity-only — declared unprovable** |
| `live_verify` | none available | **integrity-only — declared unprovable** |
| `e2e` | none available | **integrity-only — declared unprovable** |

The comment at `:321` ("checked at the call site") is **false** — there is no call site, because
no code records `build` as `done`. Implement the diff check here.

### 3.4 `build` proof

Base resolution reuses the existing lane start-sha contract, not a new one:
- `lane_start_sha_file()` in `dispatch-code.sh:466` = `${CACHE_BASE}/dispatch-<sig8>.start-sha`
- `_pc_diff_base()` in `product-close.sh:1094-1107` is the canonical reader: prefer
  `${LEADV2_LANE_START_SHA}`, else that file; validate with `git cat-file -e "<sha>^{commit}"`;
  `merge-base <sha> HEAD`; fall back to `merge-base origin/main HEAD`.

`phase-record.sh` implements the same sequence against `PROJECT_ROOT` (the lane worktree, since
the recorder and the asserter both run inside the lane). Then:
`git -C "$PROJECT_ROOT" diff --quiet "$base"` returning **0 (no changes) ⇒ rc 1**.
If no base resolves at all ⇒ **rc 1** (fail-closed; an unlocatable base is not a proof).

### 3.5 `deploy` proof — requires an additive schema field

The current schema has no commit field, so "recorded commit" does not exist yet.

- **Additive**: `cmd_record` gains `--commit <sha>`; the phase yaml gains a `commit: <sha>` line,
  written last in the `printf` block so `flat_yaml()` ordering assumptions are unaffected. All
  other fields unchanged; readers that ignore unknown keys are unaffected.
- Assert: read `commit:` from the phase file (add a `p_commit` extraction alongside `p_artifact`
  / `p_sha` at `cmd_assert:563-565`, passed as `$5`). Then
  `git -C "$PROJECT_ROOT" merge-base --is-ancestor "$commit" origin/main` ⇒ rc 0 proves.
- **Missing `commit:` ⇒ rc 1.** Fail-closed. Safe: nothing records `deploy` today (§2).
- If `origin/main` does not resolve (`git cat-file -e origin/main^{commit}` fails) ⇒ rc 1.

### 3.6 Declaring `test` / `live_verify` / `e2e` unprovable

They pass on integrity alone. That is strictly stronger than existence (a `touch fake` followed
by an overwrite now fails) but it is **not** semantic proof that a test ran or a deploy is live.
This must be visible, not buried:
1. A block comment above the case in `leadv2-phase-record.sh` naming the three phases and stating
   that integrity is the only proof available.
2. Update the header doc-block (`:1-40`) with a "proof level per phase" table.
3. The developer's return **must** state this explicitly (mission's BLOCKED clause). It is not a
   reason to return BLOCKED overall — F1/F2/F3 are all implementable — but the limitation is a
   named deliverable, not a footnote.

### 3.7 F3 — real `cmd_resolve` end-to-end coverage

The existing 10 test blocks stay untouched (they cover waivers / phases.yaml validation and are
legitimately about `assert`). **Append** a second section that drives `leadv2-dispatch-code.sh`
as a subprocess.

Harness template: `plugins/leadv2/scripts/tests/test-landed-at-spawn.sh:38-110` — it is the
proven pattern for driving `cmd_resolve` hermetically:
- a `git init` fixture repo as `LEADV2_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR`
- `LEADV2_DISPATCH_CACHE_DIR` and `LEADV2_STATE_BASE` under the sandbox
- a **stub GLM launcher** via `LEADV2_DISPATCH_GLM_BIN` that, on `bg`, `touch`es a sentinel file
  and echoes a handle — the sentinel is the "a worker was spawned" observable
- `LEADV2_JOURNAL_BIN` → a stub that appends `"$@"` to a log — the journal log is the
  "was `phase_precondition_warn` emitted" observable
- `LEADV2_ROUTER_V2=0`, `LEADV2_LANE_SHAPE=off`, `LEADV2_DISPATCH_E2E_GATE=0`,
  `LEADV2_DISPATCH_REVIEW_GATE=0`, short pending/confirmed TTLs
- each case uses a **distinct mission string** so its `sig8` is distinct and the anti-double-spend
  reservation ledger never cross-contaminates cases

Required cases (mission-mandated, all six):

| # | Setup | Expected |
|---|---|---|
| G1 | `LEADV2_REQUIRE_PHASES` **unset**, Standard-class mission, no phase records | journal log contains `phase_precondition_warn` naming the missing phases **and** the spawn sentinel exists |
| G2 | `LEADV2_REQUIRE_PHASES=1`, same mission (fresh sig8) | dispatch exits **3**, spawn sentinel **absent**, journal contains `phase_precondition_refused … mode=1` |
| G3 | `LEADV2_REQUIRE_PHASES=0`, same mission (fresh sig8) | **no** `phase_precondition_warn` line in the journal, spawn sentinel exists (identical to pre-C4) |
| G4 | `--phase-waiver review=x` under each of unset / `1` / `0` | refused in **all three** — `_phase_precondition_guard` maps `assert` rc 4 to refuse even in mode `0` (`:1546-1550`); `assert` rejects `review` at `:518` |
| G5 | forged review: write a `code-review-ledger/<slug>.jsonl` row whose `diff_hash` is a *different* 64-hex value than `sha256(review.diff)`, plus a valid `review.diff` | `assert … --class <C>` still reports `review` in `missing=` (F1 regression guard) |
| G6 | forged artifact: create `f`, `record … --artifact f`, then overwrite `f` with garbage | that phase still reported in `missing=` (F2 regression guard) |

G5/G6 may call `phase-record.sh assert` directly — they are assertions about the proof, not about
the guard — but G1–G4 **must** invoke `leadv2-dispatch-code.sh`, or F3 is not fixed.

**Red-first requirement.** Every one of G1–G6 must be run against `5ba7620` and shown failing
before the fix, then shown passing after. A case that passes in both directions is treated as
absent. `git stash`/`git worktree add` a throwaway checkout of `5ba7620` and point
`PHASE_RECORD`/`DISPATCH_BIN` at it, or run the new suite from the `5ba7620` tree with the new
test file copied in. Raw output of both runs goes in the return.

---

## 4. Exact write set

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-phase-record.sh` | `_artifact_integrity()` helper; `_verify_artifact` cases `review`/`build`/`deploy`/`test`/`live_verify`/`e2e` rewritten; `cmd_record` gains `--commit`; phase yaml gains `commit:`; `cmd_assert` extracts `p_commit` and passes it; header doc-block proof-level table |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | **only if** a `--commit` pass-through or a `build`-done recording is needed. If §3.3/§3.5 need no dispatch-code change, **leave this file untouched** — do not edit it to satisfy the write-set line |
| `plugins/leadv2/scripts/tests/test-phase-precondition.sh` | append G1–G6; existing tests 1–10 unchanged |

Nothing else. No rebase.

---

## 5. Explicit non-goals

- Rebasing, re-running, or re-adjusting the status-surface tests touched by `5ba7620`.
- Fixing the `review-ledger` vs `code-review-ledger` path split (§1 sibling) — separate thread.
- Adding writers for `test` / `deploy` / `live_verify` (§2 shows they have none) — this round
  makes the *proof* real, not the producers.
- Flipping `LEADV2_REQUIRE_PHASES` default from `warn` to `1` — that is SD-PHASE-ENFORCE-01.
- Any change to `_resolve_mandatory`, the class table, `phases.yaml` parsing, or waiver rules.

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `slug` in `_verify_artifact` (`basename …`) diverges from `repo_slug()` in `dispatch-code.sh` (which sanitizes) → assert reads a ledger file the writer never wrote | Read `repo_slug()` at `dispatch-code.sh:432-442` and mirror it byte-for-byte; add an assertion in G5 that the ledger file the test writes is the one assert reads |
| Fail-closed `deploy`/`build` breaks an in-flight lane | §2 proves no writer records these `done` today. Zero live regression. Confirm with a grep in the return |
| `git` calls inside `_verify_artifact` run in a non-repo `PROJECT_ROOT` (tests use `mktemp -d`) | Guard every git call with `git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \|\| return 1`. Fail-closed, never a stray stderr |
| Existing `assert` callers pass 4 positional args to `_verify_artifact`; adding `$5` breaks them | Only `cmd_assert:569` calls it. Use `local commit="${5:-}"` so the arity change is backward-tolerant |
| G1–G3 reuse one mission → the anti-double-spend reservation ledger refuses the 2nd/3rd dispatch and the test reads a refusal as the guard's | Distinct mission text per case; assert the *specific* journal line, never just the exit code |
| `_artifact_integrity` disagrees with `cmd_record`'s path resolution → every record self-invalidates | Copy the `:417-421` if/elif chain verbatim into the helper and have `cmd_record` call the same resolver |
| New `commit:` line breaks `cmd_show`'s `grep '^phase:'`-style readers | All readers are anchored single-key greps; an appended key is inert. Verified against `cmd_show:609-617` and `cmd_assert:557-565` |

---

## 7. Constraint checklist

1. **Env var naming** — new/read vars: `LEADV2_REQUIRE_PHASES`, `LEADV2_PHASE_RECORD_BIN`,
   `LEADV2_DISPATCH_CACHE_DIR`, `LEADV2_LANE_START_SHA`, `LEADV2_PROJECT_ROOT`,
   `LEADV2_DISPATCH_GLM_BIN`, `LEADV2_JOURNAL_BIN`, `LEADV2_STATE_BASE`. All `LEADV2_*`, all
   pre-existing. **No new env var is introduced.** PASS.
2. **File paths** — all three write-set paths exist on disk in `d4d014e1`. PASS.
3. **`claude -p` commands** — none introduced. N/A.
4. **Concurrent access** — the review ledger is appended under `review_lock_file()` flock by
   `atomic_review_check_and_record` (`:1305`). `_verify_artifact` is a **reader only**; a partial
   line cannot match both the diff-hash and the verdict predicate, so an unlocked read is safe.
   No lock needed. PASS.
5. **Config contradiction** — `REQUIRE_PHASES` is read in exactly one place (`:426`) and consumed
   in one (`:1511-1517`). No contradiction. PASS.

### Self-check finding (CRITICAL, out of scope — needs lead ruling)
`leadv2-dispatch-code.sh:2479` hardcodes a lane name into production source:

```
|| ! leadv2_active_register "${founder_task_id}" "${task_class}" "${PROJECT_ROOT}" "worktree-d4d014e1" 2>/dev/null; then
```

Every lane registered through `cmd_resolve` will claim to live in `worktree-d4d014e1`. This is a
development artifact from round 1/2 that must not land. It is **in the write-set file** but
**outside F1/F2/F3**. Recommendation: fix it in this round as a one-line change (derive the lane
name from `WORK_ROOT`/`DISPATCH_LANE_NAME`), but only with explicit lead approval, since the
mission says "exactly F1, F2, F3. Nothing else." Flagging rather than silently doing it.

---

acceptance:
  - surface: log_line
    observable: "In the sandbox journal log for the `LEADV2_REQUIRE_PHASES=1` case, a human reads a line reading `phase_precondition_refused task=<sig8> class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=1`, and the sandbox contains no worker-spawn sentinel file for that dispatch."
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: "Running the new test file against commit 5ba7620 prints a final line `[PHASE-PRECONDITION] pass=<n> fail=<m>` with m greater than or equal to 6; running the same file after the fix prints the same line with `fail=0`. Both outputs appear verbatim in the return."
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: "With a valid `docs/handoff/dispatch-<sig8>/review.diff` present and a review-ledger row carrying a diff-hash that does not match that file, `leadv2-phase-record.sh assert <sig8> --class Standard` prints a `missing=` line that includes the word `review`."
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: "After recording a phase with an artifact and then overwriting that artifact's bytes, `leadv2-phase-record.sh assert <sig8> --class Standard` prints a `missing=` line that includes that phase's name."
    authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-phase-precondition.sh

DELIVERABLE_COMPLETE
