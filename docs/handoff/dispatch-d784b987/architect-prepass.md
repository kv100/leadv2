# CLAIM-EVIDENCE-GATE-01 — architect prepass

Scope: two text contracts (subagent preamble + round-1 review lens) + one new offline
test suite. No gate machinery, no env vars, no new runtime code paths.

---

## 0. Live-reader trace (mission demanded proof, not assumption)

**Claim:** the live subagent preamble is `SHARED_PROTOCOL_BOILERPLATE`, a heredoc-free
shell string assigned at `plugins/leadv2/scripts/claude-subsession.sh:234-248` — **not**
`plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md`.

**Evidence (three independent probes):**

| # | Probe | Result |
|---|---|---|
| 1 | `grep -rln "Read docs/handoff/<TASK_ID>/context.yaml FIRST" .` | exactly one source file: `plugins/leadv2/scripts/claude-subsession.sh`; every other hit is a `*.stream.jsonl` transcript (i.e. the *output* of that same variable) |
| 2 | Self-witness | the system prompt of **this very architect subsession** contains lines 235-248 verbatim, including the parenthetical `(T-r, SUPERVISOR-AUDIT-01)` and the trailing `- Codebase graph project: ` with an *empty* value — i.e. `${LEADV2_CODEBASE_PROJECT:-}` expanded to nothing. A dead template cannot produce a live variable expansion. |
| 3 | Negative probe on SKILL.md | the boilerplate only *mentions* the skill as a path string (`- See full protocol: .claude/skills/leadv2-subagent-protocol/SKILL.md`). Nothing in `claude-subsession.sh` `cat`s or inlines SKILL.md, and headless `claude -p` subsessions do not auto-load skills — line 241 says so explicitly (`NO MCP access in this subsession (headless claude -p mode)`). |

**Consequence for the write set:** editing SKILL.md *alone* would be exactly the
dead-template edit the mission warns against. Both files get edited, with different jobs:

- `claude-subsession.sh` boilerplate → **the enforceable contract** (reaches every
  headless role invocation, guaranteed).
- `SKILL.md` → **the expanded rule** (reaches interactive Skill-tool invocations and is
  the doc the boilerplate points at). Must not contradict the boilerplate.

UNVERIFIED: whether the interactive (non-headless) `Agent(subagent_type=...)` path also
injects the boilerplate. Not probed — irrelevant to acceptance, since the headless path is
proven and SKILL.md covers the interactive one either way.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| Subagent contract | `plugins/leadv2/scripts/claude-subsession.sh` (L234-248) | +3 lines in `SHARED_PROTOCOL_BOILERPLATE` |
| Subagent contract (doc) | `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md` | +1 numbered section, ~12 lines |
| Review mission | `plugins/leadv2/scripts/leadv2-review-run.sh` (`_review_build_contract`, L703-708) | FOUR→FIVE lenses, +2 `printf` lines |
| Tests | `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh` *(to-create)* | new red-first content-probe suite |
| Test registry | `plugins/leadv2/scripts/tests/run-core-offline.sh` (`SUITE_DEFS`) | +1 entry |

---

## 2. Data flow (numbered)

1. Lead dispatches a role → `claude-subsession.sh` builds `SYSTEM_PROMPT` +
   `SHARED_PROTOCOL_BOILERPLATE` (cacheable prefix) + `PER_TASK_BOILERPLATE` (suffix).
2. **New:** the evidence rule rides in the *cacheable prefix*, so it is in force for every
   role, every task, at zero per-task token cost after the first cache fill.
3. Worker writes `<role>.full.md`. Any external-system claim there now carries a probe
   artifact inline, or the literal token `UNVERIFIED:`.
4. Build finishes → `leadv2-review-run.sh` computes `REVIEW_MODE`. Round 1 →
   `_review_build_contract` emits the EXHAUSTIVE branch.
5. **New:** that branch names a fifth lens, `claims-without-evidence`, with an explicit
   severity mapping (untagged + decision-driving → BLOCKING; tagged → MEDIUM ceiling).
6. Reviewer arms (claude and codex) receive identical text; codex receives it flattened by
   `_review_flatten` as a single `--focus` shell word.
7. Verdict parsing is untouched — `_review_contract_base` (the four verbatim format lines)
   is appended unchanged, so `parse_review_verdict` and `leadv2-review-findings.sh` see the
   same grammar.

---

## 3. Interface contracts

### 3.1 Preamble addition (`claude-subsession.sh`, appended before the `- See full protocol:` line)

Exact intended text (3 bullet lines, no backticks — the string is double-quoted shell, so
backticks would command-substitute; `$` must not appear unescaped):

```
- EVIDENCE CONTRACT: every factual claim you write about an external system or API
  (endpoint behaviour, rate limit, auth flow, schema, provider quirk, version) must be
  immediately followed by its probe artifact — a curl/CLI invocation with its output, a
  log excerpt, or a doc URL plus the live check that confirmed it.
- If you have no artifact, prefix the claim with the literal token UNVERIFIED: — an
  untagged evidence-free external-system claim is a protocol violation, and reviewers
  treat one that drives a decision as BLOCKING.
```

Constraints this text must satisfy (verify at implementation time):
- No unescaped `"`, `` ` ``, `$`, or `\` — the assignment is a double-quoted shell string.
- No `<TASK_ID>`-style angle placeholders needed; text is task-agnostic (stays cacheable).
- Adds ~90 tokens to the cached prefix. See risk R1.

### 3.2 Review lens (`leadv2-review-run.sh`, exhaustive branch)

```
printf 'Review this diff through FIVE lenses:\n'
printf '1. correctness\n2. tests-can-fail (falsification)\n3. product-invariant/contract\n4. census\n5. claims-without-evidence\n\n'
printf 'Claims-without-evidence rule: enumerate every factual claim about an external system or API made in the diff, its comments, or the deliverable. Each must carry inline evidence (probe output, log excerpt, doc link plus live check) or the literal tag UNVERIFIED. An untagged evidence-free claim that DRIVES a decision -- a code path, a config value, a limit, a retry policy -- is a BLOCKING finding. A tagged one is MEDIUM at most.\n\n'
```

Hard constraints on this string (enforced by the offline suite):
- **No `"` and no backtick anywhere** — `_review_flatten` feeds it to codex `--focus` as a
  single shell word (documented at L711-714). Use `--` and bare `UNVERIFIED`, never
  quoted.
- Emitted only in the `else` (exhaustive) branch. The `verify_only` branch is untouched:
  round 2+ must stay verification-only (REVIEW-ROUND1-EXHAUSTIVE-01 invariant).
- `_review_contract_base` append stays the last statement of the branch.

### 3.3 New suite contract (`test-claim-evidence-gate.sh`)

| Case | Target | Baseline (pre-fix) | Working tree (post-fix) |
|---|---|---|---|
| C1 | `claude-subsession.sh` contains `EVIDENCE CONTRACT` and `UNVERIFIED:` inside `SHARED_PROTOCOL_BOILERPLATE` | absent → red | present → green |
| C2 | `leadv2-review-run.sh` exhaustive branch says `FIVE lenses` + `claims-without-evidence` | absent → red | present → green |
| C3 | `verify_only` branch does **not** contain `claims-without-evidence` (round-2 purity) | n/a — pure invariant, asserted on working tree only | green |
| C4 | neither new string contains `"` or a backtick (codex `--focus` safety) | n/a — invariant | green |
| C5 | `bash -n` + `/bin/bash -n` (bash 3.2) on both edited scripts | — | green |
| C6 | rendered round-1 mission (invoke `_review_build_contract` with `REVIEW_MODE=exhaustive`, sourced in a subshell) contains the lens line | absent → red | present → green |

Red-first mechanics, copied from `test-review-gate-scope-evidence.sh:229-242`:
- `LEADV2_TEST_BASELINE_REF` := `git merge-base origin/main HEAD`, overridable by env.
- **Content probe:** if that ref *already* contains `claims-without-evidence` in
  `leadv2-review-run.sh`, the merge-base has self-nullified (this lane landed on
  `origin/main`) → fall back to a pinned floor. Pin: `559cf15` (current HEAD, the last
  commit before this lane). Rationale: the same self-nullification trap that produced the
  `9e03dc0` pin in the sibling suite (commit 8cc6bf8/85ae886).
- Extract with `git archive <ref> plugins/leadv2/scripts | tar -x -C "$PREFIX_DIR"`; never
  `git stash`/`reset`/`clean`.
- Counters `PASS` / `FAIL` / `GREEN_PRE_FIX` / `COULD_NOT_RUN`; exit non-zero if
  `FAIL>0 || GREEN_PRE_FIX>0`.

### 3.4 Registry entry (`run-core-offline.sh` SUITE_DEFS)

```
"claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)|||bash $TEST_DIR/test-claim-evidence-gate.sh"
```

Insert adjacent to the existing `review round exhaustive/verify-only` entry (currently
line ~226). Must pass under `LEADV2_CORE_OFFLINE_REVERSE=1` — so the suite must be
order-independent: no shared temp dirs with other suites, `mktemp -d` per case, cleanup
via `trap`.

---

## 4. DB / migrations

None. No schema, no Supabase, no Qdrant surface touched.

---

## 5. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | The preamble lives in the **cacheable prefix** (`build_cached_prefix()`, L264+). Changing it invalidates the prompt cache for every role, one-time, across all repos. | MEDIUM | Accept; keep the addition to 3 lines / ~90 tokens. Land once, do not iterate the wording in follow-up commits. |
| R2 | A `"` or backtick in the new lens text breaks the codex arm's `--focus` single-word argument at runtime, silently degrading one arm. | **HIGH** | C4 asserts absence of both characters in the emitted contract, not just in the source line. |
| R3 | Editing `_review_build_contract` risks touching round detection / arm selection / pool logic landed today (6b79c2c) — explicitly off-limits. | HIGH | Diff must be confined to the two `printf` lines inside the `else` branch. C3 pins the `verify_only` branch as unchanged in behaviour. |
| R4 | Baseline self-nullification: once this lane merges to `origin/main`, `merge-base` contains the fix and the suite goes green-pre-fix → non-zero exit forever. | **HIGH** | Content-probe + pinned floor `559cf15` (§3.3). This is the exact failure that cost two commits (8cc6bf8 → 85ae886). |
| R5 | `perl`/`sed` interpolation mangling when the implementer patches the shell string (the 85ae886 lesson: `$` interpolation corrupted a pin). | MEDIUM | Patch via the `Edit` tool or a python3 literal-replace script, never `perl -pe` with `$` in the payload. |
| R6 | Two lanes touching `run-core-offline.sh` SUITE_DEFS concurrently (T2 owns product-close) → merge conflict on one array. | LOW | Append a single line; conflict is textual and trivially resolvable. Note ordering, no lock needed. |
| R7 | "UNVERIFIED:" as a bare token may collide with existing grep-based parsers scanning deliverables. | LOW | Confirm at implementation: `grep -rn "UNVERIFIED" plugins/leadv2/scripts/` before landing. If a parser exists, it is additive-compatible (new token, no removed token). |
| R8 | The rule makes reviews noisier — every doc-link-free sentence becomes a candidate finding. | MEDIUM | Severity ladder in §3.2 caps tagged claims at MEDIUM, so only decision-driving untagged claims block. |

---

## 6. Mandatory constraint checklist

1. **Env vars** — no new env vars introduced. Referenced existing: `LEADV2_TEST_BASELINE_REF`,
   `LEADV2_CORE_OFFLINE_REVERSE`, `LEADV2_REPO` — all `LEADV2_*`, no drift. ✅
2. **File paths** — all four edit targets exist on disk (verified this session);
   `tests/test-claim-evidence-gate.sh` marked `(to-create)`. ✅
3. **`claude -p` commands** — none introduced by this lane. `claude-subsession.sh`'s own
   invocation is untouched (we edit a string variable, not the command). ✅
4. **Concurrent access** — `run-core-offline.sh` SUITE_DEFS is the only file two lanes may
   both write (R6). Ordering constraint: land this lane's registry line after T2's, or
   resolve textually. No lock required. ✅
5. **Config contradiction** — no config semantics changed. R7 covers the one token-collision
   surface to grep before landing. ✅

---

## 7. Explicit non-goals (implementer: ignore these)

- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` — T2 lane owns it. Do not open.
- Round detection, arm selection, pool logic, `_engine_*` helpers in `leadv2-review-run.sh`.
- The `verify_only` branch of `_review_build_contract` (read-only, assert-only).
- `_review_contract_base` and the four verbatim format lines — parser contract, frozen.
- No new env var, no gate machinery, no severity-enum change in
  `leadv2-review-findings.sh`.
- No edit to `test-review-round-exhaustive.sh` (new suite instead — keeps today's landed
  suite untouched).
- No propagation step to persona-engine / m3-market / respiro-ios: plugin-owned files are
  per-file symlinks to this repo (global CLAUDE.md, founder decision 2026-07-29).
- Hook cache copy: not applicable — none of the four files is a hook.

---

## 8. Implementation sequence

1. Edit `claude-subsession.sh` L246 area — insert the 2 bullets **before** the
   `- See full protocol:` line.
2. Edit `leadv2-review-run.sh` L704-707 — FOUR→FIVE, add lens 5 and the severity rule.
3. Mirror the expanded rule into `SKILL.md` as a new numbered section.
4. Write `tests/test-claim-evidence-gate.sh` (C1-C6, red-first harness §3.3).
5. Register in `run-core-offline.sh` SUITE_DEFS.
6. Run the new suite alone → expect red-count on the baseline arm, green on the working
   tree, `GREEN_PRE_FIX=0`.
7. `bash -n` + `/bin/bash -n` + `shellcheck` on all three edited/created shell files.
8. `run-core-offline.sh` forward, then `LEADV2_CORE_OFFLINE_REVERSE=1`.
9. Commit on the lane branch. Single revert = rollback.

---

## acceptance:

```yaml
acceptance:
  - surface: file_artifact
    observable: >-
      Opening plugins/leadv2/scripts/leadv2-review-run.sh and reading the exhaustive
      branch of _review_build_contract, a human sees the mission text say "Review this
      diff through FIVE lenses" and see "5. claims-without-evidence" listed, followed by
      a paragraph stating that an untagged evidence-free claim which drives a decision is
      a BLOCKING finding and a tagged one is MEDIUM at most.
    authored_at: 2026-08-19T15:02:00Z
  - surface: rendered_line
    observable: >-
      In the round-1 review mission actually handed to a reviewer arm (as captured in the
      lane's review handoff artifact), the reader sees the line listing five lenses ending
      in claims-without-evidence — not four lenses. A round-2 mission for the same lane
      still reads "VERIFICATION-ONLY ROUND 2" with no lens list at all.
    authored_at: 2026-08-19T15:02:00Z
  - surface: file_artifact
    observable: >-
      Opening plugins/leadv2/scripts/claude-subsession.sh at the SHARED_PROTOCOL_BOILERPLATE
      assignment, a human reads a bullet beginning "EVIDENCE CONTRACT:" requiring a probe
      artifact after every external-system claim, and a following bullet instructing the
      worker to prefix an unbacked claim with the literal token UNVERIFIED:.
    authored_at: 2026-08-19T15:02:00Z
  - surface: rendered_line
    observable: >-
      The system prompt shown to a freshly dispatched /leadv2 subagent (visible in that
      subsession's transcript) contains the EVIDENCE CONTRACT bullet verbatim — proving the
      edited string is the live preamble and not a dead template.
    authored_at: 2026-08-19T15:02:00Z
  - surface: log_line
    observable: >-
      Running the new suite prints a results line reading
      "Results: N passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run" with N
      at least 6, and the runner's own summary lists the claim-evidence gate suite as
      passing in both the forward and the LEADV2_CORE_OFFLINE_REVERSE=1 ordering.
    authored_at: 2026-08-19T15:02:00Z
```

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md, plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
