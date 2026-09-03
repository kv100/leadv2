# REVIEW-ROUND1-EXHAUSTIVE-01 — architect prepass

## 0. Live-path confirmation (evidence, not assumption)

| Question | Evidence | Verdict |
|---|---|---|
| Which file assembles the text review arms receive? | `plugins/leadv2/scripts/leadv2-review-run.sh:523` defines `review_contract=$'…'`; it is interpolated at **all four** arm branches — codex `--focus` (`:322`), glm (`:326`), kimi (`:351`), sonnet/opus (`:364`) | **`leadv2-review-run.sh` is the live text source** |
| Is the skill dir the live source? | `plugins/leadv2/skills/leadv2-review/SKILL.md:104` documents that the phase "calls `plugins/leadv2/scripts/leadv2-review-run.sh` over Bash directly". No mission text in the skill tree matches the saved missions. | **Skill dir is documentation, not text source → do not edit for behaviour** |
| Proof against a real arm mission on disk | `docs/handoff/dispatch-886a5711/review-mission-{sonnet,opus}.md` reproduce `:363-364`'s `printf` byte-for-byte, including the `Also report every Critical/High finding…` line that exists **only** in `leadv2-review-run.sh` (product-close's copy at `:2153` lacks it) | **confirmed live reader** |
| Second copy of the same string? | `leadv2-dispatch-product-close.sh:2153` has its own `review_contract` (legacy in-lane path, `LEADV2_REVIEW_ENGINE=0`). **off_limits this lane.** | divergence accepted, see risk R8 |

Round mechanics today: **the engine has no round concept at all.** Rounds exist only because the
lane/lead re-invokes the engine in the *same* `docs/handoff/dispatch-<task>/` directory after a fix
worker lands. Every invocation overwrites `review-gate.md` (`:540, :646, :666, :709, :836, :848`)
and `review-findings.json` (`:795`). So round-1 evidence is **destroyed by round 2 today** — the
snapshot step below is a precondition of the feature, not a nicety.

Gate vocabulary that matters for round detection:
- real verdict → `status: fail` (`:831`, carries `critical:`/`high:`) or `status: pass` (`:844`)
- **not** a verdict → `status: unreviewed` (`:539`), `status: blocked` (`:703, :706`)

## 1. Scope

Layer touched: exactly one — the review engine's **mission-text assembly** plus a new
**round-context** preamble. No arm selection, no pool/quota, no verdict parsing, no gate schema
change. `REVIEW_VERDICT:` / `REVIEW_FINDINGS:` / `FINDING:` contracts stay byte-identical, so every
downstream parser (`:230-231`, `:726`, `leadv2-review-findings.sh`, product-close's terminal
stamping) is unaffected.

## 2. Data flow (numbered)

1. Engine starts, args parsed (`:44-62`), `HANDOFF` created (`:66`).
2. **NEW `_review_diff_hash()`** — `shasum -a 256 "${DIFF_FILE}"` hoisted from `:546` to §7 top,
   guarded (`[[ -f ]]`, else empty). `:546` becomes a reuse of the hoisted value.
3. **NEW `_review_round_context()`** runs *before* pool resolve (`:526`) and therefore before any
   possible gate write:
   a. read sidecar `${HANDOFF}/.review-round.state` (`round=<N>` + `diff=<hash8>`);
   b. if a prior real-verdict `review-gate.md` exists → snapshot it to
      `review-gate.round<N>.md`, and `review-findings.json` to `review-findings.round<N>.json`
      (`cp` + `mv`, never a rename of the live gate);
   c. decide the mode (§3 truth table) → sets `REVIEW_ROUND`, `PRIOR_FINDINGS_BODY`.
4. **NEW `_review_build_contract()`** assigns the existing variable name `review_contract` —
   round-1 exhaustive text, or round-2+ verification-only text with the prior findings embedded.
   All four arm branches are left untouched (zero-diff at `:322/:326/:351/:364`).
5. **NEW `_review_flatten()`** produces `review_contract_focus` (newlines→spaces, no `"`/backtick
   in the new text) used **only** by the codex `--focus` argument at `:322`.
6. Fan-out, synthesis, gate write: unchanged.
7. **NEW** at each real-verdict exit (`:836` fail, `:848` pass, after the `mv`): write
   `.review-round.state` = `round=${REVIEW_ROUND}` + `diff=${diff_hash:0:8}`. Blocked/unreviewed
   exits deliberately do **not** write it (an infra bounce is not a round).
8. **NEW** one observability line at step 3: `emit decision "review_round task=… round=N mode=<exhaustive|verify_only> prior_findings=<n>"`.

## 3. Round-mode truth table (the correctness core)

`verify_only` requires **positive evidence on every axis**; anything missing ⇒ `exhaustive`.
Exhaustive is always safe; verification-only is the mode that can let defects through.

| sidecar `round` | prior gate | prior findings count | diff hash vs sidecar | mode |
|---|---|---|---|---|
| absent | any | any | — | **exhaustive** (round 1) |
| ≥1 | `status: fail`/`pass` | ≥1 | **changed** | **verify_only**, round=N+1 |
| ≥1 | real verdict | ≥1 | unchanged | exhaustive — nothing was fixed, re-review of the identical diff |
| ≥1 | real verdict | 0 | any | exhaustive — nothing to verify |
| ≥1 | `blocked`/`unreviewed`/absent | — | any | exhaustive — infra bounce, no verdict existed |
| — | — | — | — | `LEADV2_REVIEW_ROUND=1` forces exhaustive; `=2` forces verify_only (test seam + operator escape hatch) |

Prior findings source, in order: `review-findings.round<N>.json` (structured, preferred) → the
`FINDING:`-shaped lines of the snapshotted gate. Embedded body is **capped**: ≤40 findings, each
line truncated to 300 chars, with a literal `(… capped, see docs/handoff/dispatch-<task>/review-gate.round<N>.md)` tail when truncated.

## 4. Interface contracts

| Symbol | Kind | Contract |
|---|---|---|
| `_review_diff_hash()` | new fn | stdout = sha256 of `DIFF_FILE`, empty string if unreadable; rc always 0 |
| `_review_round_context()` | new fn | side-effects: snapshots + sets `REVIEW_ROUND` (int ≥1), `REVIEW_MODE` (`exhaustive`\|`verify_only`), `PRIOR_FINDINGS_BODY` (may be empty); rc always 0 (never blocks a review) |
| `_review_build_contract()` | new fn | stdout = full contract text; reads `REVIEW_MODE`, `PRIOR_FINDINGS_BODY`; **must always end with the four unchanged verbatim-format lines** |
| `_review_flatten()` | new fn | stdin/`$1` → single line, newlines and runs of spaces collapsed |
| `review_contract` | existing var | name and all 4 call sites preserved |
| `${HANDOFF}/.review-round.state` | new artifact | `round=<int>\ndiff=<hash8>\n`; written only after a real-verdict gate |
| `${HANDOFF}/review-gate.round<N>.md`, `review-findings.round<N>.json` | new artifacts | immutable per-round snapshots |
| `LEADV2_REVIEW_ROUND` | new env | `LEADV2_*` prefix ✔ (checklist item 1); unset = auto-detect |

### Mission text — required directives (test-asserted marker phrases)

Round 1 must contain, in addition to today's four contract lines:
`EXHAUSTIVE ROUND 1` · four lens headings `correctness`, `tests-can-fail (falsification)`,
`product-invariant/contract`, `census` · the census rule *"if you find one instance of a defect
shape, enumerate ALL same-shape instances in the touched files before returning"* · *"Report
EVERYTHING you find in this one pass. Never stop at the first 1-3 findings."*

Round 2+ must contain: `VERIFICATION-ONLY ROUND <N>` · *"verify by execution whether each prior
finding below is fixed"* · *"Admit a NEW finding ONLY if the fixes introduced it."* · the prior
findings block · and the unchanged four contract lines.

## 5. DB / migrations

None. No Supabase, no schema, no RLS surface in this lane.

## 6. Test plan — `plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh`

Harness mirrors `test-review-engine-fanout-multiprovider.sh` (stub resolver + stub codex/glm/
architect bins, tmp repo, zero network) and the red-first baseline pattern of
`test-review-gate-scope-evidence.sh:229-242`.

1. **T1 round-1 content** — fresh handoff ⇒ `review-mission-sonnet.md` contains all round-1
   marker phrases *and* the four unchanged contract lines.
2. **T2 round-2 verification-only** — seed `review-gate.md` (`status: fail`, 2 `FINDING:` lines),
   `review-findings.json`, `.review-round.state` with an **older** diff hash, then run ⇒ mission
   is `VERIFICATION-ONLY ROUND 2`, embeds both prior finding descs, and **must not** contain the
   `EXHAUSTIVE ROUND 1` marker.
3. **T3 stale-diff guard** — same seed but sidecar diff hash == current ⇒ back to exhaustive.
4. **T4 no-sidecar / blocked-gate guard** — gate `status: blocked` (or sidecar absent) ⇒ exhaustive.
5. **T5 snapshot preservation** — after a round-2 run, `review-gate.round1.md` exists and still
   holds round 1's `FINDING:` lines (proves step 3b beats every gate writer).
6. **T6 codex focus flattening** — stub codex records its `--focus`; assert it is one line and
   carries the round marker.
7. **T7 red-first** — `git archive <baseline> plugins/leadv2/scripts | tar -x` into a temp prefix,
   re-run T1+T2 against the extracted engine, assert both **FAIL** there. Baseline ref =
   `merge-base origin/main HEAD`, content-probed for `_review_round_context`; if present (lane
   already landed on origin/main) fall back to pinned `85ae886`.
8. Register in `run-core-offline.sh` → suite count becomes **51/0** (currently 50 registered).
   *Assumption flagged:* the mission's "50/0" predates this registration.
9. `bash -n` + `shellcheck` clean on both changed files.

## 7. Risks & mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Round-1 evidence destroyed — every gate writer overwrites `review-gate.md` | snapshot in step 3b, placed **before** pool resolve so even the `status: unreviewed` exit at `:541` cannot beat it |
| R2 | **Stale gate ⇒ blind verification-only** on a fresh, unrelated diff | diff-hash comparison in the truth table; unchanged hash ⇒ exhaustive |
| R3 | Infra bounce (`blocked`/`unreviewed`) counted as a round ⇒ a round-2 verify-only pass with nothing to verify, real defects unreviewed | sidecar written **only** at the two real-verdict exits |
| R4 | Prompt blowup / provider input limit from a 12-finding body | ≤40 findings, 300-char truncation, pointer to the snapshot file |
| R5 | Verification-only lets *pre-existing* defects slide from round 2 onward | accepted per mission; bounded by the round-1 census directive, the "introduced by the fixes" clause, and `LEADV2_REVIEW_ROUND=1` escape hatch. **Recommend a follow-up thread**: revert to exhaustive at round ≥4 |
| R6 | Codex `--focus` is one shell argument; multi-line/quoted text can mangle it | `_review_flatten()`; new text forbids `"` and backticks (enforced by T6 + a grep assertion in the suite) |
| R7 | Concurrency: 4 arm subshells + hackdetect read `review_contract` | read-only after step 4, all writes (snapshots, sidecar) happen outside the fan-out window ⇒ no race. Lane's EXIT-trap gate writer is fallback-only (writes only when gate ABSENT) and snapshots never remove the gate (checklist item 4) |
| R8 | `leadv2-dispatch-product-close.sh:2153` keeps the old text ⇒ two-phase review only on the engine path | product-close is **off_limits** this lane. Divergence is pre-existing (`:2153` already lacks the `FINDING:` line `:523` has). Queue a follow-up to converge, do not edit here |
| R9 | Config contradiction (checklist items 1 & 5) | `LEADV2_REVIEW_ROUND` is a new env name; no `LEAD_V2_*` drift. Grep does find a **plain** `REVIEW_ROUND` in `leadv2-score-compute.sh:76` (`extract_review_round "$STATE_MD" "$HANDOFF_DIR"`, weight `W_REVIEW_R2=10`) — a separate process, never sourced by the engine, and a different name from the env var, so **no collision**. Semantics are *consistent*, not contradictory: both mean "review needed a round 2". Implementer: **do not** rewire score-compute to the new sidecar in this lane — note it as a follow-up |
| R10 | `claude -p` flag checklist (item 3) | N/A — all model calls go through `claude-subsession.sh` (`:365`, `:501`, `:512`); this lane adds no new invocation |

Checklist item 2 (paths exist): `leadv2-review-run.sh` ✔, `tests/run-core-offline.sh` ✔,
`tests/test-review-round-exhaustive.sh` **(to-create)**, `.review-round.state` /
`review-gate.round<N>.md` **(to-create at runtime)**.

## 8. Out of scope (implementer: ignore)

- `leadv2-dispatch-product-close.sh` — **do not open it.**
- Arm selection, pool resolution, quota/refusal reselection, verify/refute job, hack-detect mission.
- `review-gate.md` schema, `review-findings.json` schema, `render_gate_findings`.
- `plugins/leadv2/skills/leadv2-review/**` behaviour — **docs-only** touch permitted (one line in
  SKILL.md noting the two-phase rounds); it is not the live text source, so no logic there.
- Round cap / max-rounds policy, lane re-dispatch logic, `leadv2-plan-run.sh`.

## 9. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >-
      On a first review of a task, docs/handoff/dispatch-<task>/review-mission-sonnet.md
      opens with an "EXHAUSTIVE ROUND 1" block listing four lenses (correctness;
      tests-can-fail (falsification); product-invariant/contract; census), the census
      sentence "if you find one instance of a defect shape, enumerate ALL same-shape
      instances in the touched files before returning", and the sentence "Report
      EVERYTHING you find in this one pass. Never stop at the first 1-3 findings." —
      followed by the same REVIEW_VERDICT/REVIEW_FINDINGS/FINDING lines the file shows today.
    authored_at: 2026-08-19T00:00:00Z
  - surface: file_artifact
    observable: >-
      After a failing round 1 and a fix that changes the diff, the next review's
      docs/handoff/dispatch-<task>/review-mission-sonnet.md is headed
      "VERIFICATION-ONLY ROUND 2", lists round 1's findings verbatim in the body, tells the
      reviewer to verify each by execution and to admit a new finding only if the fixes
      introduced it, and no longer contains the "EXHAUSTIVE ROUND 1" block.
    authored_at: 2026-08-19T00:00:00Z
  - surface: file_artifact
    observable: >-
      docs/handoff/dispatch-<task>/review-gate.round1.md still shows round 1's FINDING
      lines after round 2 has written a new review-gate.md — round-1 evidence survives.
    authored_at: 2026-08-19T00:00:00Z
  - surface: log_line
    observable: >-
      The review engine's stderr shows one line
      "[leadv2-review-run] decision review_round task=<task> round=2 mode=verify_only
      prior_findings=<n>" on the second review of a task, and round=1 mode=exhaustive on the first.
    authored_at: 2026-08-19T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/skills/leadv2-review/SKILL.md

DELIVERABLE_COMPLETE
