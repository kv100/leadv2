# REVIEW-BODY-PERSIST-01 — architect prepass (scoped design)

## 1. Diagnosis (drop point proven by code, not guessed)

`claude-subsession.sh` has **no `--out` flag and no stdout body**. Flags parsed at
`plugins/leadv2/scripts/claude-subsession.sh:56-66`: `--role --model --task-id
--mission-file --session-id --effort --wait`. On the `--wait` success path
(`:884-903`) the ONLY thing printed to stdout is:

```
LABEL=$SESSION_LABEL SESSION_ID=$SESSION_ID
```

— exactly the 97 bytes seen in the incident. The subsession's real output goes to
three places, all under `HANDOFF_DIR="$PROJECT_ROOT/docs/handoff/$TASK_ID"` (`:171`):

| channel | path | content |
|---|---|---|
| deliverable (full) | `<HANDOFF_DIR>/critic.full.md` | the review body + contract lines |
| deliverable (summary) | `<HANDOFF_DIR>/critic.summary.md` | ≤50 words |
| raw transcript | `<HANDOFF_DIR>/critic.stream.jsonl` (`:325`) | stream-json, incl. final assistant message |

The reviewer arm (`leadv2-dispatch-product-close.sh:1255-1262`) invokes it with
`--task-id "dispatch-${TASK}-review"` and `> "${review_out}"`. So `review_out`
(`review-opus.md`) captures the handle line and nothing else, **by construction** —
this is not a race or a flake, it reproduces on every opus/sonnet arm run.

Why the verdict counts still landed: `resolve_review_artifact()` (`:286-298`) already
side-channels the deliverable for parsing — it walks
`critic.full.md → critic.md → critic.summary.md` (freshness-gated by `REVIEW_STAMP`)
and hands the first hit to `parse_review_verdict()`. Two consequences:

- **The counts came from the deliverable, the body was never copied back** to
  `review-<arm>.md`, which is the file a human opens next to `review-gate.md`.
- If the critic wrote only `critic.summary.md` (≤50 words, contract lines present),
  the resolver legitimately parses a FAIL verdict off a file with **no findings prose
  anywhere** — verdict readable, reasons unreadable. This is the incident's exact shape.

Requirement 1's live repro (stub-free, real `claude-subsession.sh --role critic
--mission-file <trivial> --wait`) stays a build-lane obligation: it must print, in the
report, the byte count of stdout vs `critic.full.md` vs `critic.stream.jsonl`. The
design below does not depend on the outcome — it only depends on the flag surface and
the stdout line above, both read directly from the file.

**Design consequence:** no `--out` flag is needed. An explicit file contract already
exists (the two-file deliverable protocol). The fix is materialization on the caller
side, so `claude-subsession.sh` is untouched (non-goal 4 satisfied by construction).

## 2. Changes

### 2.1 `run_reviewer_arm()` — opus/sonnet branch materializes the body (`~:1255-1262`)

After `--wait` returns, keep the label line as a header and append the best available
body into `review_out`. New helper `materialize_subsession_body()` placed next to
`resolve_review_artifact()` (both know `dispatch-${TASK}-review`):

- Source preference: `critic.full.md` → `critic.md` → `critic.summary.md`, each
  required `-s` **and** `-nt "${REVIEW_STAMP}"` (same freshness rule the resolver uses —
  a stale deliverable from a prior arm/attempt must never be adopted).
- Fallback when no deliverable exists: extract the final `assistant` text blocks from
  `critic.stream.jsonl` via `python3` (the stream is already parsed by `python3` in
  `claude-subsession.sh`, so the dependency is not new) and use that.
- Write order: label header line first, then a `--- body from: <rel-path> ---` provenance
  line, then the body. `parse_review_verdict()` is line-anchored (`^[[:space:]]*REVIEW_VERDICT:`)
  so a prepended header cannot break it; `review_floor_ok()` only gets larger.
- Only this branch changes. codex/glm/kimi already own `review_out` directly.

### 2.2 Shared post-arm guard — `review_body_lost` (new named blocked reason)

New check in the arm loop, after `cls="$(classify_arm_failure ...)"` returns non-`refused_*`,
applied to **every** arm:

- Trip condition: `review_rc == 0` AND (`review_out` lacks a `REVIEW_VERDICT:` line OR
  `wc -c < review_out` < `LEADV2_REVIEW_BODY_MIN_BYTES` (default 300)) AND
  evidence-of-real-output exists (`review_err` non-empty, or a `cost recorded:` line in it).
- Effect: set `review_rc=6` and `_pc_body_lost=1`, break the loop. Before
  `resolve_review_artifact()` runs, emit
  `status: blocked / reason: review_body_lost` into `review-gate.md`, `emit decision
  ... status=blocked reason=review_body_lost arm=<arm>`, `_dl_note dead review_body_lost`,
  `_stamp_review_terminal blocked`, `exit 6`.
- **Ordering is load-bearing:** the guard must run *before* `resolve_review_artifact()`,
  otherwise the deliverable fallback masks a lost body back into a silent pass-through —
  the exact masking that produced the incident.
- Reason vocabulary joins the existing `provider_error` / `empty_response` /
  `no_verdict_marker` triple (N-5 D4 style); severity policy and parser untouched.

### 2.3 Non-goals (implementing agent: do not touch)

- `claude-subsession.sh` — no new flag, no behaviour change.
- `parse_review_verdict()`, `review_floor_ok()`, `resolve_review_artifact()`, severity
  policy, FAIL/PASS thresholds.
- codex / glm / kimi arm bodies (they receive only the §2.2 shared guard).
- The refusal fallback loop's arm-walking semantics — `review_body_lost` is **not** a
  `refused_*` class and must not trigger re-selection to another arm (a paid review
  whose body was lost is a failure to surface, not an admission refusal).
- Ledger/journal schema, `docs/leadv2/**`, `docs/handoff/**`.

## 3. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | `materialize_subsession_body()` + opus/sonnet branch call + shared `review_body_lost` guard |
| `plugins/leadv2/scripts/tests/test-review-body-persist.sh` | new suite (to-create) |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | register the new suite (`run_check` line, baseline 32 → 33) |

Stubs reuse `test-review-silence-gate.sh` patterns verbatim: fixture git repo per
scenario, `LEADV2_GLM_POLICY_RESOLVER` python stub, `LEADV2_DISPATCH_ARCHITECT_BIN` /
`LEADV2_DISPATCH_GLM_BIN` arm stubs.

Test scenarios:
- **(a)** architect stub prints only `LABEL=... SESSION_ID=...` on stdout while writing a
  full body incl. contract lines to `docs/handoff/dispatch-<TASK>-review/critic.full.md`
  → `review-opus.md` ends up containing the full body and both contract lines.
- **(a2)** same, deliverable absent but `critic.stream.jsonl` carries the final assistant
  message → body recovered from the transcript.
- **(b)** stub prints the label line, writes nothing anywhere, writes bytes to stderr →
  `review-gate.md` says `reason: review_body_lost`, exit 6, no PASS/FAIL verdict recorded.
- **(c)** glm-arm regression: stub writes a normal `--out` body → verdict parsed and
  recorded exactly as today (guard does not trip on a healthy arm).
- **(d)** `bash -n` under bash5 and `/bin/bash` 3.2 for the touched script.

## 4. Risks

| risk | mitigation |
|---|---|
| Stale `critic.full.md` from a previous arm adopted as this arm's body | reuse `-nt "${REVIEW_STAMP}"` freshness gate; the guard trips rather than adopting a stale file |
| 300-byte floor false-reds a legitimately terse review | floor is bypassed whenever a `REVIEW_VERDICT:` line is present (mirrors `review_floor_ok`'s lenient rule); override via `LEADV2_REVIEW_BODY_MIN_BYTES` for tests only |
| Guard trips on codex/glm arms that were already healthy | trip requires `rc==0` AND missing verdict marker AND evidence-of-output; scenario (c) locks the healthy path |
| Prepended header breaks the parser | parser regexes are `^`-anchored per line; header contains no `REVIEW_*` token |
| `python3` absent on the transcript-extraction path | fallback is best-effort — failure degrades to the §2.2 guard (blocked, loud), never to silence |
| bash 3.2 incompatibility (`mapfile`, `${var@Q}`, `declare -A`) | none used; `bash -n` under `/bin/bash` 3.2 is in acceptance |

## 5. Env vars

`LEADV2_REVIEW_BODY_MIN_BYTES` (new, `LEADV2_*` prefix, default 300, test-only override) —
sibling of the existing `LEADV2_REVIEW_MIN_BYTES`. No other env var introduced; no
`claude -p` invocation added by this lane.

acceptance:
  surface: file_artifact
  observable: |
    After an opus/sonnet review arm finishes, docs/handoff/dispatch-<TASK>/review-opus.md
    opens with the LABEL=.../SESSION_ID=... header line followed by the reviewer's full
    prose — the numbered findings a human can read and act on — including the
    REVIEW_VERDICT: and REVIEW_FINDINGS: lines; the file is thousands of bytes, not 97.
    When no body exists anywhere, docs/handoff/dispatch-<TASK>/review-gate.md reads
    "status: blocked" / "reason: review_body_lost" instead of a verdict.
  authored_at: 2026-08-04T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-review-body-persist.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
