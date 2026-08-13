# PHASES-ARE-THE-ONLY-PATH-01 — fix round 3 — implementation design (architect prepass)

Base: worktree `.claude/worktrees/d4d014e1`, HEAD `5ba7620`. **Do not rebase.**
Scope: F1, F2, F3 only. No refactor, no unrelated test edits.

---

## 0. Verified state of the round-2 tree

All three findings reproduce verbatim. Evidence (paths relative to
`.claude/worktrees/d4d014e1/plugins/leadv2/scripts/`):

| # | Location | Round-2 code | Verdict |
|---|---|---|---|
| F1 | `leadv2-phase-record.sh:325-333` (`_verify_artifact`, case `review`) | `ledger_file="${ledger_dir}/${slug}.jsonl"; [[ -s "$ledger_file" ]] && return 0` | repo-wide non-emptiness — confirmed broken |
| F2 | `leadv2-phase-record.sh:320-324` (`build`) and `:334-337` (`test\|deploy\|live_verify\|e2e`) | `[[ -n "$artifact" && -f "$artifact" ]] && return 0` | bare existence — confirmed broken |
| F2b | `leadv2-phase-record.sh:417-421` writes `artifact_sha256`; `:565` reads it into `p_sha`; `p_sha` is passed to `_verify_artifact` as `$4` and **never referenced inside it** | confirmed dead parameter |
| F3 | `tests/test-phase-precondition.sh` (192 lines) | `grep -c 'REQUIRE_PHASES\|cmd_resolve'` → 0 / 0; comment at `:32` says "We test phase-record.sh assert directly (it's what the guard calls)" | the guard itself has zero coverage — confirmed |

Additional facts established during discovery (they drive the design, do not re-derive them):

- The canonical review diff-hash is **`shasum -a 256` of the review diff FILE**, computed at
  `leadv2-dispatch-product-close.sh:1478`:
  `diff_hash="$(shasum -a 256 "${diff_file}" | awk '{print $1}')"`, where
  `diff_file="${HANDOFF}/review.diff"` (`:1028`) and `HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"` (`:83`).
  `cmd_record_review` in `leadv2-dispatch-code.sh:2256` **does not compute** the hash — it only
  validates it as 64-hex and appends it. **Therefore the correct reuse for F1 is to hash
  `docs/handoff/dispatch-<sig8>/review.diff`, not to re-derive the diff.** Re-deriving would mean
  duplicating `_pc_repo_diff` / `_pc_diff_base` / multi-repo write-set splitting — a second
  hashing scheme by construction. Do not do it.
- The ledger row shape (`leadv2-dispatch-code.sh:1298`) is exactly:
  `{"diff_hash":"H","verdict":"V","reviewer":"R","run_id":"I","repo":"S","ts":"T"}` — one JSON
  object per line, fixed key order.
- Ledger file path = `${LEADV2_DISPATCH_CACHE_DIR:-~/.claude/cache}/code-review-ledger/<repo_slug>.jsonl`.
  `leadv2-phase-record.sh:329` already derives `slug` the same way `repo_slug()` does. Keep it.
- The lane start commit is at `${CACHE_BASE}/dispatch-<sig8>.start-sha`
  (writer `record_lane_start_sha`, `leadv2-dispatch-code.sh:492`; reader `_pc_diff_base`,
  `leadv2-dispatch-product-close.sh:1094`). This is the base for the F2 `build` diff check.
- **The `build` call-site claim is false.** The comment at `leadv2-phase-record.sh:321` says the
  non-empty diff is "checked at call site". Grep of every `phase-record` invocation across the
  plugin (`leadv2-dispatch-code.sh:2486`, `leadv2-phase8-close.sh:257`,
  `leadv2-dispatch-product-close.sh:1338/1444/1717`) shows records for `classify`, `review`, `e2e`,
  `close` **only — nothing records `build` at all**, so there is no call site and no such check.
  It must be implemented inside `_verify_artifact`. Delete the misleading comment.
- Test seam for F3 already exists and is documented in the usage block: `LEADV2_DISPATCH_GLM_BIN` /
  `LEADV2_DISPATCH_SUBSESSION_BIN` / `LEADV2_DISPATCH_CODEX_BIN` (+ `KIMI`, `ARCHITECT`,
  `LANE_WORKTREE`, `LANE_LIVENESS`) override the launchers. Point them at spy scripts.
- The guard refuses via `_phase_precondition_guard ... || exit 3` (`leadv2-dispatch-code.sh:2494`
  and `:3053`). **Exit 3 already means `arm=opus` in the documented contract** (usage block,
  `:2240`). The mission requires a *distinct* exit code — see D3.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| Phase proof engine | `plugins/leadv2/scripts/leadv2-phase-record.sh` | F1 + F2: real assertions in `_verify_artifact`; new `--commit` record flag; new helpers |
| Dispatch guard | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | F3 support only: distinct refusal exit code + usage text |
| Test suite | `plugins/leadv2/scripts/tests/test-phase-precondition.sh` | F3: end-to-end `cmd_resolve` coverage + F1/F2 forgery regressions |

Nothing else. No `docs/`, no other suite, no rebase.

---

## 2. F1 — review phase proof

### 2.1 Contract

| Item | Value |
|---|---|
| Function | `_verify_artifact <sig8> review <artifact> <sha>` |
| Proven when | the lane's review-diff file exists, is non-empty, and the review ledger contains **at least one line** whose `diff_hash` equals `sha256(review-diff file)` **and** whose `verdict` is `PASS` or `PASS_WITH_NITS` |
| Not proven | diff file missing/empty; ledger missing; no row with that hash; every row with that hash has verdict `FAIL` |

### 2.2 Lane diff-file resolution (ordered)

1. `$artifact` (arg 3) if non-empty — resolved first as `${PROJECT_ROOT}/${artifact}`, then as an
   absolute path (mirrors the resolution order already used in `cmd_record`, `:417-421`).
2. Fallback: `${PHASES_DIR_BASE}/dispatch-${sig8}/review.diff` — the conventional path
   product-close writes.

If neither resolves to a non-empty regular file → `return 1`. A lane whose review never produced a
diff has not proven review.

### 2.3 Matching

Two-stage filter, bash-3.2 safe, robust to JSON key reordering:

```
lane_hash="$(_sha256 "$diff_path")"        # same helper cmd_record already uses (:64)
[[ -n "$lane_hash" ]] || return 1
grep -F "\"diff_hash\":\"${lane_hash}\"" "$ledger_file" 2>/dev/null \
  | grep -Eq '"verdict":"(PASS|PASS_WITH_NITS)"' || return 1
return 0
```

`_sha256` is `shasum -a 256 "$1" | awk '{print $1}'` — byte-identical to product-close's
`shasum -a 256 "${diff_file}" | awk '{print $1}'`. **One hashing scheme, reused, not reinvented.**

Do **not** use a single combined `grep -F '{"diff_hash":"H","verdict":"PASS"'` — it silently
depends on key order and on `PASS` not prefix-matching `PASS_WITH_NITS`.

---

## 3. F2 — artifact integrity + per-phase assertions

### 3.1 New helper — `_artifact_sha_ok <artifact> <recorded_sha>` → 0/1

1. `[[ -n "$artifact" && -n "$recorded_sha" ]]` else `return 1`.
   **An empty `artifact_sha256` can never prove a phase.** (`cmd_record` leaves it empty when the
   file did not exist at record time — that is exactly the unproven case.)
2. Resolve path: `${PROJECT_ROOT}/${artifact}` first, then `${artifact}`; must be `-f`.
3. `now="$(_sha256 "$resolved")"`; `[[ -n "$now" && "$now" == "$recorded_sha" ]]` else `return 1`.

This alone closes the overwrite-after-record hole and kills `touch fake`.

Applies to: `build`, `test`, `deploy`, `live_verify`, `e2e`. It is a **necessary** condition for
all five, never a sufficient one on its own.

### 3.2 `build` — lane diff vs its own base is non-empty

After `_artifact_sha_ok`:

- base = `cat "${CACHE_BASE}/dispatch-${sig8}.start-sha"` (same file `_pc_diff_base` reads).
- Base absent, or `git -C "$PROJECT_ROOT" cat-file -e "${base}^{commit}"` fails → **not proven**
  (`return 1`). Fail-closed is correct here and safe: `LEADV2_REQUIRE_PHASES` defaults to `warn`,
  so a lane with no start-sha gets a journal line, not a refusal.
- Proven when either produces output:
  `git -C "$PROJECT_ROOT" diff --name-only "$base" 2>/dev/null` **or**
  `git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null`
  (committed lane work *or* uncommitted lane work — mirrors product-close's
  never-smaller intent).
- Delete the false "checked at call site" comment at `:321`.

### 3.3 `deploy` — recorded commit is an ancestor of `origin/main`

The phase schema has no commit field today. **Additive, backward-compatible schema change:**

| Change | Detail |
|---|---|
| `cmd_record` new flag | `--commit <sha>` (optional, unvalidated beyond non-empty) |
| New schema line | `commit: <sha>` — written always, empty when not supplied. Old records simply lack the line; `grep '^commit:'` yields empty → treated as "not proven" for `deploy` only. |
| `_verify_artifact` signature | extended to `<sig8> <phase> <artifact> <sha> [commit]` — 5th arg, optional, existing callers unaffected |
| `cmd_assert` | reads `p_commit="$(grep '^commit:' "$pfile" | sed 's/^commit:[[:space:]]*//')"` alongside `p_artifact`/`p_sha` (`:565`) and passes it as arg 5 |

`deploy` proof = `_artifact_sha_ok` **and** non-empty `commit:` **and**
`git -C "$PROJECT_ROOT" merge-base --is-ancestor "$commit" origin/main`. If `origin/main` does not
resolve (`git cat-file -e origin/main^{commit}` fails) → **not proven**. A deploy that cannot be
shown to be on the mainline is not a proven deploy.

### 3.4 `close` — unchanged

`phase8-passed.flag` non-emptiness is a real, purpose-built assertion. Leave it.

### 3.5 `test` / `live_verify` / `e2e` — DECLARED UNPROVABLE BY EXISTENCE

**Report this explicitly (it is a required output of this round).** There is no repo-wide artifact
grammar for these three phases: nothing in the plugin records `test`, `live_verify` or `build` at
all today, and the only `e2e` record (`leadv2-dispatch-product-close.sh:1338`) is `--status running`
with no committed artifact convention. So no assertion stronger than integrity exists off the shelf.

Design (both tiers implemented; the second is the honest part):

- **Tier A** — `_artifact_sha_ok` must pass. Integrity only. Not sufficient.
- **Tier B** — the artifact must additionally carry a pass-shaped verdict marker:
  `grep -Eqi '^[[:space:]]*(status|verdict|result)[[:space:]]*:[[:space:]]*"?(pass|passed|ok|green|success)"?'`
  over the resolved artifact, OR (for `*.json`) `"(status|verdict|result)"[[:space:]]*:[[:space:]]*"(pass|passed|ok|green|success)"`.
- **No marker → `return 1`**, i.e. the phase is recorded as *unprovable*, never passed on existence.

This introduces a convention rather than reading one. Flag it in the return report as the residual
risk: a lane whose test artifact uses a different verdict grammar will be refused under
`LEADV2_REQUIRE_PHASES=1`. That is acceptable because (a) the default is `warn`, and (b) the
alternative is the existence check this round exists to kill. **If the implementer judges the marker
convention unacceptable, the correct action is `BLOCKED` naming `test`, `live_verify`, `e2e` — not
leaving `-f` behind.**

---

## 4. F3 — end-to-end `cmd_resolve` coverage

### 4.1 Harness (new, top of `test-phase-precondition.sh`, additive to the existing 22 tests)

```
TMP_ROOT/repo         # git init; one commit; git config user.*; a tracked file
TMP_ROOT/.cache       # LEADV2_DISPATCH_CACHE_DIR
TMP_ROOT/spawned.log  # spy sink — MUST stay empty in every refusal case
TMP_ROOT/journal.log  # existing stub journal (already wired at :17-25)
```

Spy launcher (`printf '%s\n' "$*" >> "$LEADV2_TEST_SPAWN_LOG"; exit 0`) exported into **every**
launcher seam so no path can spawn silently:
`LEADV2_DISPATCH_GLM_BIN`, `LEADV2_DISPATCH_KIMI_BIN`, `LEADV2_DISPATCH_SUBSESSION_BIN`,
`LEADV2_DISPATCH_ARCHITECT_BIN`, `LEADV2_DISPATCH_CODEX_BIN`, `LEADV2_DISPATCH_LANE_WORKTREE_BIN`,
`LEADV2_DISPATCH_LANE_LIVENESS_BIN`.

**Do not pass `--no-spawn` and do not set `LEADV2_DISPATCH_SPAWN=0`** in the refusal tests — that
would make "no worker spawned" vacuously true and reproduce exactly the class of green-but-untouched
suite this round is correcting. The spy log must be empty because the guard refused, not because
spawning was disabled.

Invocation under test: `bash "$DISPATCH_BIN" <mission-text> --task-id <id>` with
`LEADV2_PROJECT_ROOT=$TMP_ROOT/repo`, plus a pre-seeded `phases.d` for whatever the case needs.

### 4.2 Cases (all six mission-mandated)

| # | Setup | `LEADV2_REQUIRE_PHASES` | Expected |
|---|---|---|---|
| T1 | Standard class, no `plan`/`gate1` records | unset | journal contains `phase_precondition_warn` naming the missing phases; spy log **non-empty** (proceeded to spawn); exit 0 |
| T2 | same | `1` | journal contains `phase_precondition_refused`; spy log **empty**; exit = the distinct refusal code (D3) |
| T3 | same | `0` | journal contains **no** `phase_precondition_*` line; spy log non-empty; exit 0 |
| T4 | `--phase-waiver review=x` | unset, `0`, `1` (all three) | refused in every class and every mode; exit 4-class config error path; spy log empty |
| T5 | **F1 regression** — write `review.diff` with content A; append a ledger row for `sha256(B)` with verdict PASS; record `review` done | `1` | review NOT proven → refusal names `review`; spy log empty |
| T6 | **F2 regression** — `touch fake`, `record ... --artifact fake`, then `printf 'garbage' > fake` | `1` | phase NOT proven → refusal names it; spy log empty |

Every case asserts on **three** surfaces: exit code, journal line presence/absence, spy-log
emptiness. A case that only checks the exit code is not sufficient here — exit 3 is currently
overloaded (see D3), and a refusal that still spawned would pass an exit-code-only check.

### 4.3 Red-first requirement

Each of T1–T6 must **fail** against `5ba7620` and pass after the fix. Capture both runs verbatim:

```
git -C <worktree> stash            # or run the new suite from a 5ba7620 checkout
bash plugins/leadv2/scripts/tests/test-phase-precondition.sh   # RED — record raw output
git -C <worktree> stash pop
bash plugins/leadv2/scripts/tests/test-phase-precondition.sh   # GREEN — record raw output
```

A test that passes in both directions is treated as absent and the round is FAIL.

---

## 5. Decisions

| id | Decision | Source |
|---|---|---|
| D1 | F1 hashes `docs/handoff/dispatch-<sig8>/review.diff` with `_sha256` rather than re-deriving the diff — this *is* the scheme `record-review`'s caller uses (`product-close:1478`); re-deriving would create the second scheme the mission forbids | architect |
| D2 | `--commit` / `commit:` added to the phase-record schema (additive, absent line = not proven for `deploy` only) — the ancestry assertion F2 demands has no other input | architect |
| D3 | **Distinct refusal exit code.** `_phase_precondition_guard ... \|\| exit 3` collides with the documented `3 = arm=opus`. Change both call sites (`leadv2-dispatch-code.sh:2494`, `:3053`) to `exit 6` and add `6 phase precondition refused` to the usage block at `:2240`. Mission explicitly requires "distinct exit code" | architect(self-check) |
| D4 | `test`/`live_verify`/`e2e` get integrity + a verdict-marker convention and are otherwise declared unprovable; if the marker convention is rejected → return BLOCKED naming those three phases | architect |
| D5 | `build` fails closed when the lane start-sha is missing. Safe because `LEADV2_REQUIRE_PHASES` defaults to `warn` | architect |
| D6 | Refusal tests must not use `--no-spawn`/`LEADV2_DISPATCH_SPAWN=0` — it makes the no-spawn assertion vacuous | architect(self-check) |

### Mandatory constraint checklist

1. **Env var naming** — all vars touched are `LEADV2_*` (`LEADV2_REQUIRE_PHASES`,
   `LEADV2_PHASE_RECORD_BIN`, `LEADV2_DISPATCH_*_BIN`, `LEADV2_DISPATCH_CACHE_DIR`,
   `LEADV2_PROJECT_ROOT`). No new env var introduced. No `LEAD_V2_*` drift. PASS.
2. **File paths** — all three write-set paths exist on disk in the worktree; `review.diff`,
   `dispatch-<sig8>.start-sha`, `phase8-passed.flag` are runtime artifacts, not new files. PASS.
3. **`claude -p` commands** — none introduced by this change. N/A.
4. **Concurrent access** — the review ledger is appended under `lv2_lock_wait` by
   `atomic_review_check_and_record`; `_verify_artifact` is a **reader only** and reads
   line-at-a-time via grep, so a concurrent append can at worst be missed, never corrupt the read.
   No lock needed on the read path. `phases.d/<phase>.yaml` is written mktemp+`mv -f` (atomic) and
   read whole — no race surface added.
5. **Config contradiction** — `REQUIRE_PHASES` is read in exactly one place
   (`leadv2-dispatch-code.sh:426`) with one consumer (`_phase_precondition_guard`). D3 changes the
   *exit code* only, not the tri-state semantics. No contradiction. PASS.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| Making `review` real retro-unproves in-flight lanes that recorded review under the old check | Default `LEADV2_REQUIRE_PHASES=warn` — journal line, dispatch proceeds. The flip to `1` is separately ledgered as SD-PHASE-ENFORCE-01 |
| `review.diff` path convention differs for multi-repo lanes | Fallback order in §2.2 prefers the recorded `artifact:` when present; the conventional path is the fallback, not the only source |
| Verdict-marker convention (D4) refuses a legitimately-passing test artifact | Warn-by-default; the alternative is the existence check being removed. If judged unacceptable → BLOCKED, per D4 |
| Exit-code change (D3) breaks a caller keying on 3 | Grep every `dispatch-code.sh` invocation for exit-3 handling before landing; the two guard call sites are the only writers of that code from the guard path |
| Test harness accidentally reaches the real `~/.claude/cache` or the real repo | `LEADV2_DISPATCH_CACHE_DIR` + `LEADV2_PROJECT_ROOT` are already exported at `:14-15` of the existing suite; extend, do not replace |

## 7. Out of scope

Rebasing. Any test file other than `test-phase-precondition.sh`. The `plan` / `gate1` / `classify` /
`diverge` / `close` verification branches. `.claude/scripts/tests/` de-duplication. Flipping
`LEADV2_REQUIRE_PHASES` to `1` by default. Any refactor of `_verify_artifact`'s case structure
beyond the branches named above.

---

acceptance:
  - surface: log_line
    observable: "In the task journal for a dispatch whose review ledger holds only a PASS row for a
      different diff, a human reading the journal sees a `phase_precondition_refused` line that
      lists `review` among the missing phases — where before the fix the same dispatch produced no
      such line and the worker started."
    authored_at: 2026-08-05T00:00:00Z
  - surface: rendered_line
    observable: "The test-phase-precondition.sh run printed to the terminal shows the six new named
      cases (warn-proceeds, enforce-refuses, disabled-silent, waiver-refused, forged-review,
      forged-artifact) reported as failures when run against commit 5ba7620 and as passes when run
      against the fixed tree — both outputs shown side by side in the return report."
    authored_at: 2026-08-05T00:00:00Z
  - surface: file_artifact
    observable: "A person who runs `touch fake`, records it as a phase artifact, then overwrites
      `fake` with different bytes, and then reads the refusal message on screen, sees that phase
      named as missing instead of the dispatch proceeding."
    authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-phase-precondition.sh

DELIVERABLE_COMPLETE
