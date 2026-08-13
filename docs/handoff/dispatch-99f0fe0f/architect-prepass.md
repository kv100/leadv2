# M-8 — Functional Definition-of-Done for skills — implementation design

Architect prepass. Design only; no implementation performed.

---

## 1. Problem restated in mechanical terms

`plugins/leadv2/skills/leadv2-memory-gc/SKILL.md` documented `--model haiku` and "one batched
verdict request". The flag parsed (`leadv2-memory-gc.sh:24`) and reached
`leadv2-memory-index-gc.py finalize --model`, but the only path that actually produced verdicts in
the acceptance run was `--verdicts-file` (`leadv2-memory-index-gc.py:362 get_verdicts`). The live
path (`call_model`, line 306) was never exercised. From outside, a documented-and-dead capability
and a documented-and-live capability emit the same signal: nothing.

The missing artifact is therefore **an executable, per-skill claim of capability that is graded by
exit code and is RED by default**. Everything below builds exactly that and nothing else.

---

## 2. Design decision: where the proof lives (the one paragraph of argument)

Three candidates: (a) a new key in SKILL.md YAML frontmatter, (b) a central registry file, (c) a
sibling `PROOF.sh` per skill directory. **(c) wins.** Frontmatter is parsed by the Claude plugin
loader and validated by `claude plugin validate`, which `run-core-offline.sh` already runs as a
gate — introducing an unrecognised key there risks turning a green core suite red for reasons
unrelated to the proof mechanism, and a shell command squeezed into a YAML scalar is quoting-hostile
and cannot hold setup/teardown. A central registry (b) is a second source of truth that drifts the
moment a skill is renamed or deleted, which is the same class of defect this task exists to close.
A sibling `PROOF.sh` is discovered by glob (`skills/*/PROOF.sh`) so the registry *is* the filesystem
and cannot drift; it is arbitrarily long, so it can build fixtures, stub binaries and assert
richly; it is a real shell file, so it inherits the existing `syntax_all` `bash -n` sweep in
`run-core-offline.sh` for free; and its absence is trivially and honestly reportable as
`RED-NO-PROOF`. Cost: one extra file per proven skill, and the gate must glob rather than read one
index — both acceptable.

---

## 3. Components

| # | Path | New? | Responsibility |
|---|---|---|---|
| 1 | `plugins/leadv2/scripts/leadv2-proof-lib.sh` | new | `assert_eq`, `assert_ne`, `assert_contains`, `assert_file_contains`, `proof_fail`, `proof_tmpdir` (auto-cleanup trap). Sourced by every `PROOF.sh`. |
| 2 | `plugins/leadv2/scripts/leadv2-skill-proof.sh` | new | The gate. Discovery, tautology validation, execution, table, state, exit code. |
| 3 | `plugins/leadv2/skills/<skill>/PROOF.sh` | new ×3 | One runnable proof per proven skill. |
| 4 | `plugins/leadv2/scripts/tests/test-skill-proof-gate.sh` | new | Unit suite for #2 (fixtures, not live skills). |
| 5 | `plugins/leadv2/scripts/tests/fixtures/skill-proof/**` | new | Fake skill trees: valid / tautological / failing / absent. |
| 6 | `plugins/leadv2/scripts/tests/run-core-offline.sh` | edit | One `run_check` line adding #4 only. **Not the gate itself** — see §8 R1. |
| 7 | `plugins/leadv2/docs/skill-proof-dod.md` | new | The contract, the statuses, and the honest statement that 38/41 skills are RED-NO-PROOF today. |
| 8 | `plugins/leadv2/skills/{leadv2-memory-gc,…}/SKILL.md` | edit ×3 | Append a 3-line `## Proof` section pointing at `PROOF.sh`. No behaviour change. |
| 9 | `plugins/leadv2/.gitignore` | edit/new | Ignore the runtime state file. |

---

## 4. Interface contracts

### 4.1 `PROOF.sh` contract (what an implementing skill author must satisfy)

| Property | Requirement |
|---|---|
| Location | `plugins/leadv2/skills/<skill-name>/PROOF.sh` |
| Shebang | `#!/usr/bin/env bash` (first line, exact) |
| Strictness | Must contain `set -euo pipefail` |
| Declaration | Must contain a line `# proof-of: <one sentence naming the capability>` |
| Assertions | Must invoke at least one `assert_*` helper from `leadv2-proof-lib.sh` |
| Environment in | `LEADV2_PLUGIN_ROOT`, `LEADV2_REPO_ROOT`, `LEADV2_PROOF_TMP` exported by the gate |
| Environment out | exit 0 = capability demonstrated; any non-zero = RED-FAILED. stdout/stderr captured. |
| Purity | Must not write outside `$LEADV2_PROOF_TMP`; must not require network or a live model |
| Time | Should complete < 30 s; gate hard-timeout `LEADV2_PROOF_TIMEOUT` (default 120 s) → RED-FAILED |

### 4.2 Gate CLI

```
leadv2-skill-proof.sh [run]            # discover, validate, execute all; table; exit 1 if any RED
                      [--only NAME]…   # restrict to named skills (still lists the rest as RED)
                      [--skills-dir D] # default $PLUGIN_ROOT/skills  (test seam)
                      [--from-state]   # print last-known table without executing
                      validate PATH    # tautology/shape check on one PROOF.sh; exit 0 ok, 3 refused
                      list             # skill → proof-present matrix, no execution, exit 0
```

### 4.3 Status vocabulary (closed set, printed verbatim)

| Status | Meaning | Colour |
|---|---|---|
| `GREEN` | proof present, valid, exited 0 in this run (or in the recorded state under `--from-state`) | pass |
| `RED-FAILED` | proof present, valid, executed, non-zero exit or timeout | RED |
| `RED-INVALID` | proof present but refused by the tautology/shape check — **never executed** | RED |
| `RED-NEVER-RUN` | proof present and valid, but no successful execution has ever been recorded (only reachable via `--from-state` / `--only` filtering) | RED |
| `RED-NO-PROOF` | no `PROOF.sh` in the skill directory | RED |

`RED-NEVER-RUN` vs `RED-FAILED` is the distinguishability requirement (mission property 2) and is
the reason a state file exists at all; a single execute-everything run would collapse the two.

### 4.4 State file

`${LEADV2_SKILL_PROOF_STATE:-$LEADV2_PLUGIN_ROOT/state/skill-proof-state.json}` — runtime artifact,
git-ignored, schema:

```json
{"version":1,"skills":{"leadv2-memory-gc":{"status":"GREEN","exit":0,"ran_at":"<ISO-8601>",
 "proof_sha256":"<hex>","duration_ms":1234,"last_green_at":"<ISO-8601|null>"}}}
```

`proof_sha256` is recorded so a changed proof invalidates the recorded GREEN: on `--from-state`, a
skill whose current `PROOF.sh` hash differs from the recorded one reports `RED-NEVER-RUN`, not
GREEN. This closes "edit the proof to something weaker and inherit the old pass".

### 4.5 Tautology / shape check (mission property 3)

Run at **registration time** — i.e. the moment the gate discovers a `PROOF.sh`, before any
execution. On refusal the gate prints a loud, reasoned block to stderr and marks `RED-INVALID`.

Rejection rules, evaluated on the source text with comments and here-doc bodies stripped:

| # | Rule | Rationale |
|---|---|---|
| T1 | Any operative line is exactly `true`, `:`, `exit 0`, or `echo …` as the file's sole command | the canonical fake proof |
| T2 | Any line ending in `\|\| true`, `\|\| :`, `\|\| exit 0`, `\|\| return 0` | swallows the only failure signal |
| T3 | `set +e` present without a subsequent `set -e` | disarms strict mode |
| T4 | Missing `set -euo pipefail` | same, by omission |
| T5 | Zero `assert_*` invocations | nothing is being checked |
| T6 | Missing `# proof-of:` declaration line | the claim is unstated |
| T7 | Not readable / empty / wrong shebang | shape |
| T8 | Trailing `exit 0` unguarded as the final statement after a `\|\|`-suppressed body | belt-and-braces on T2 |

**Stated limitation, to be written into the docs verbatim, not hidden:** general "can this program
return non-zero" is undecidable, and `assert_eq 1 1` passes every rule above. T1–T8 catch the
mechanical no-fail idioms only. The real counter-force is acceptance item 2 — the break-the-
implementation drill — and the docs must say that a proof is only as good as its last observed
failure against broken code.

---

## 5. Data flow (numbered)

1. Operator runs `plugins/leadv2/scripts/leadv2-skill-proof.sh`.
2. Gate resolves `PLUGIN_ROOT` from `$BASH_SOURCE`, `REPO_ROOT` from `$PLUGIN_ROOT/../..`.
3. Gate globs `$SKILLS_DIR/*/SKILL.md` → the authoritative skill list (41 today; `archive/` excluded
   because it holds no `SKILL.md` at the top level — implementer must verify and skip any directory
   without one).
4. For each skill: `PROOF.sh` absent → `RED-NO-PROOF`, next skill.
5. Present → §4.5 shape/tautology check. Refused → print refusal block, `RED-INVALID`, **do not
   execute**, next skill.
6. Valid → create `$LEADV2_PROOF_TMP` (mktemp -d, trapped), export the three env vars, execute
   `bash PROOF.sh` under `LEADV2_PROOF_TIMEOUT` with stdout+stderr captured to
   `$TMP/<skill>.log`.
7. Exit 0 → `GREEN`; else `RED-FAILED` and the last 20 lines of the log are echoed under the table.
8. Gate writes the state file atomically (write-temp + `mv`).
9. Gate prints the table (skill, status, ms, one-line reason), then a summary
   `green=N red=M (no-proof=X failed=Y invalid=Z never-run=W) skills=41`.
10. Exit `0` iff `red == 0`, else `1`. Usage/internal errors exit `2` — distinct from "found RED",
    so a broken gate is never mistaken for a clean repo.

---

## 6. The three initial proofs

Adoption is deliberately partial (mission property 5). Exactly three proofs; the other 38 skills
report `RED-NO-PROOF` and the docs state that this is the correct honest baseline.

### 6.1 `leadv2-memory-gc` — MANDATORY, and the load-bearing one

This proof must exercise the **live batched-verdict path**, not `--verdicts-file`. Mechanism:
`leadv2-memory-index-gc.py:307` resolves the CLI via `os.environ.get("CLAUDE_BIN", "claude")`.
That is the seam.

Steps:
1. `proof_tmpdir` → build a throwaway memory dir with `MEMORY.md` index + 3 entry files, and a
   throwaway project root containing the paths those entries reference.
2. Write a stub at `$TMP/bin/claude` that: appends its full argv to `$TMP/calls.argv`, appends its
   stdin prompt to `$TMP/prompt.txt`, increments `$TMP/calls.count`, and prints a well-formed
   batched verdict JSON covering all 3 entries.
3. `CLAUDE_BIN="$TMP/bin/claude"` run `leadv2-memory-gc.sh --memory-dir … --project-root …
   --byte-cap … --line-limit … --model haiku` (explicit cap/limit because the script BLOCKS rather
   than guessing when no honest loader measurement exists).
4. Assertions — each one is a specific way the historical defect would resurface:
   - `assert_eq 1 "$(cat calls.count)"` → **the model was actually called, exactly once**. If
     `get_verdicts` ever again short-circuits to canned data, this reads 0 and the proof fails.
   - `assert_contains "$(cat calls.argv)" "--model haiku"` → the documented flag reaches the CLI
     rather than being parsed and dropped.
   - all three entry slugs appear in `prompt.txt` → the request really is *batched*, one prompt
     with every entry, not per-entry or truncated.
   - `assert_file_contains memory-gc-report.md` a per-entry `live`/`spent` verdict for each slug →
     the response is consumed, not discarded.
   - a second run with the stub emitting malformed JSON exits non-zero and the report contains
     `llm: error` → the documented failure semantics are real too.
5. Break-drill for acceptance item 2 (the implementer runs this, does not commit it): temporarily
   patch `get_verdicts` to return a canned map without calling `call_model`. Expected observed
   failure: `calls.count` is `0`, `assert_eq` fires, proof exits non-zero. Restore, re-run, GREEN.

### 6.2 + 6.3 — the other two

Pick deterministic, offline, script-backed skills. Primary picks:

- `leadv2-negative-memory` — backed by `leadv2-negative-memory-compile.sh` /
  `leadv2-negative-memory-trigger-scan.sh`. Proof: feed a fixture negative-memory store containing
  one active failure pattern plus one expired one, run the trigger scan against a matching
  candidate approach, assert the active pattern is reported as blocking and the expired one is not.
- `leadv2-premortem` — documented as a zero-LLM bash heuristic table. Proof: run it over a
  fixture change-set engineered to be high-risk, assert a non-proceed verdict; run over a trivially
  safe one, assert proceed. Two-sided, so it cannot pass by always emitting one verdict.

**Fallback rule for the implementer:** if either skill turns out to have no deterministic runnable
surface, substitute the nearest skill that does (candidates: `leadv2-loop-detection`,
`leadv2-signatures`, `leadv2-active-registry`-backed skills) and record the substitution and its
reason in `M8-RESULT.md`. Do not manufacture a runnable surface for a skill that has none — that
would be the very defect under repair.

---

## 7. Wiring into the existing suite

- `run-core-offline.sh` gains **one** line, next to the existing `skill lint` check:
  `run_check "skill proof gate unit tests" bash "$TEST_DIR/test-skill-proof-gate.sh"`.
- The gate itself is **not** added to `run-core-offline.sh`. Reason in §8 R1.
- `test-skill-proof-gate.sh` drives the gate against `--skills-dir` fixture trees only, asserting:
  (a) valid+passing fixture → GREEN, exit 0; (b) valid+failing fixture → RED-FAILED, exit 1;
  (c) `PROOF.sh` of `true` → `validate` exits 3 with a refusal on stderr, `run` reports
  RED-INVALID and never executes it (assert by having the tautological fixture also touch a
  sentinel file — the sentinel must not exist); (d) skill with no proof → RED-NO-PROOF, exit 1;
  (e) mixed tree → exit 1 with correct counts; (f) state-hash invalidation → GREEN recorded, proof
  edited, `--from-state` reports RED-NEVER-RUN; (g) `bash -n` and (if available) `shellcheck` on
  the gate and the lib — mirroring `test-leadv2-skill-lint.sh`'s house style.

---

## 8. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Adding the gate to `run-core-offline.sh` turns it red immediately** (38 RED-NO-PROOF → exit 1), regressing main's 22/0 and violating acceptance item 4. | Gate is a standalone command. Only its *unit suite* joins core-offline. Documented explicitly so a future contributor does not "helpfully" wire it in. Revisit only when RED-NO-PROOF reaches zero. |
| R2 | `syntax_all` in `run-core-offline.sh` `bash -n`s every `*.sh` under the plugin root — new `PROOF.sh` and fixture files are swept in automatically. A deliberately-broken fixture proof would break core-offline. | Fixture proofs must be *syntactically valid* and fail at runtime (e.g. `assert_eq 1 2`), never via a syntax error. Stated as a hard rule in the test suite header. |
| R3 | Tautology detection is undecidable; `assert_eq 1 1` passes every rule. | Accepted and documented, not papered over (§4.5). Counter-force is the break-drill, recorded per proof in `M8-RESULT.md`. |
| R4 | A GREEN inherited by a later-weakened proof. | `proof_sha256` in state; hash mismatch ⇒ RED-NEVER-RUN (§4.4). |
| R5 | Proofs mutate the real repo or the founder's real memory stores. | Gate exports `LEADV2_PROOF_TMP` and every proof builds fixtures there; the memory-gc proof never points at a real memory dir. Suite asserts `git status --porcelain` is unchanged across a gate run. |
| R6 | Concurrent gate runs racing on the state file. | Atomic write-temp + `mv` (§5 step 8); no read-modify-write across the run — the whole map is rebuilt in memory and written once. Parallel runs then last-writer-wins on a complete document, never a torn one. |
| R7 | `claude plugin validate` rejects `PROOF.sh` as an unexpected file in a skill directory. | Must be verified empirically on the first implementation step. If it rejects, fall back to `plugins/leadv2/proofs/<skill-name>.PROOF.sh` — same glob-is-the-registry property, one directory removed. Implementer records which layout survived validation. |
| R8 | `timeout` is not POSIX-guaranteed on macOS (`gtimeout` under coreutils). | Detect `timeout`/`gtimeout`; if neither exists, run without a timeout and print a one-line WARN in the table footer rather than silently dropping the guard. |
| R9 | Stubbing `CLAUDE_BIN` proves the flag reaches *a* CLI, not that the real Claude CLI accepts it. | Honest scope statement in the proof header: this proves the wiring, not the vendor contract. Better than today's zero. |
| R10 | Env-var drift (`LEAD_V2_*` vs `LEADV2_*`). | All new vars are `LEADV2_PROOF_TIMEOUT`, `LEADV2_SKILL_PROOF_STATE`, `LEADV2_PROOF_TMP`, `LEADV2_PLUGIN_ROOT`, `LEADV2_REPO_ROOT`. Implementer greps for prior usage of each before adding, per the constraint checklist. |

---

## 9. Constraint checklist

1. **Env naming** — all new vars `LEADV2_*` (R10). Implementer cross-checks `.claude/settings.json`
   `env` block for collisions before first use.
2. **Paths** — existing and verified: `plugins/leadv2/skills/` (41 dirs),
   `plugins/leadv2/scripts/leadv2-memory-gc.sh`, `…/leadv2-memory-index-gc.py`,
   `…/scripts/tests/run-core-offline.sh`, `…/scripts/tests/fixtures/`,
   `…/scripts/tests/test-leadv2-skill-lint.sh`. Everything in §3 marked *new* is `(to-create)`.
3. **`claude -p`** — not applicable; this design invokes no `claude -p`. The memory-gc proof stubs
   the CLI rather than calling it.
4. **Concurrent access** — only the state file is shared (R6). No two steps read+write the same
   file within a run.
5. **Config contradiction** — `CLAUDE_BIN` is *read*, never redefined, and only within the proof's
   own subprocess environment; the gate does not export it.

---

## 10. Out of scope (implementer must ignore)

- Proofs for the other 38 skills. RED-NO-PROOF is the intended, documented initial state.
- Any CI workflow file.
- Changes to `plugins/leadv2/scripts/tests/*` other than the one `run_check` line and the new suite
  + fixtures.
- Behavioural changes to any skill. SKILL.md edits are additive `## Proof` pointer sections only.
- Fixing `leadv2-memory-gc` itself. If the proof reveals a real defect, report it in
  `M8-RESULT.md`; do not repair it under this task.
- `test-no-work-terminal.sh` flakiness — known load-flaky; re-run in isolation before attributing.

---

## acceptance

```yaml
acceptance:
  authored_at: "2026-08-03T00:00:00Z"
  items:
    - id: A1
      surface: rendered_line
      observable: >-
        Running the gate on this repo prints a per-skill table in which exactly three
        rows read GREEN — one of them leadv2-memory-gc — every remaining skill row reads
        RED-NO-PROOF, and the footer summary line shows a non-zero red count; the shell
        that ran it reports a non-zero exit status.
    - id: A2
      surface: rendered_line
      observable: >-
        With the memory-gc batched-verdict path deliberately broken, the leadv2-memory-gc
        proof prints an assertion failure naming the model-invocation count as 0 instead
        of 1 and the gate row for that skill reads RED-FAILED; after the break is undone
        the same row reads GREEN again.
    - id: A3
      surface: rendered_line
      observable: >-
        Pointing the gate's validate subcommand at a PROOF.sh whose body is `true` prints
        a refusal naming the tautology rule that fired, and the skill's row in a full gate
        run reads RED-INVALID with no evidence that the proof body ever executed.
    - id: A4
      surface: rendered_line
      observable: >-
        The new proof-gate unit suite prints a final all-pass line with zero failures, and
        run-core-offline.sh prints a summary line whose failed and missing counts are both
        zero with a passed count no lower than main's.
    - id: A5
      surface: file_artifact
      observable: >-
        M8-RESULT.md exists at the repo root and shows a PASS, FAIL or BLOCKED verdict
        against each of A1-A4 with the raw pasted command output under each, plus the list
        of changed paths and the commit SHA.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-skill-proof.sh, plugins/leadv2/scripts/leadv2-proof-lib.sh, plugins/leadv2/skills/leadv2-memory-gc/PROOF.sh, plugins/leadv2/skills/leadv2-memory-gc/SKILL.md, plugins/leadv2/skills/leadv2-negative-memory/PROOF.sh, plugins/leadv2/skills/leadv2-negative-memory/SKILL.md, plugins/leadv2/skills/leadv2-premortem/PROOF.sh, plugins/leadv2/skills/leadv2-premortem/SKILL.md, plugins/leadv2/scripts/tests/test-skill-proof-gate.sh, plugins/leadv2/scripts/tests/fixtures/skill-proof/**, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/skill-proof-dod.md, plugins/leadv2/.gitignore, M8-RESULT.md

DELIVERABLE_COMPLETE
