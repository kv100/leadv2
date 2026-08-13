LABEL=critic-dispatch-PLAN-FOLLOWUPS-02-review-1786620584 SESSION_ID=4c3afa54-291d-4388-9451-df6d33a615ac
--- body from: docs/handoff/dispatch-PLAN-FOLLOWUPS-02-review/critic.full.md ---
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=2 low=2

# Critic review — PLAN-FOLLOWUPS-02 r2 (pf02-r2.diff)

Scope: `docs/handoff/PLAN-FOLLOWUPS-02/pf02-r2.diff` — 2 hunks.
- `plugins/leadv2/scripts/leadv2-plan-run.sh:387-393` — order-B awk no longer `exit`s at the
  first closing fence; a non-marker fence now closes (`in_fence=0`) and scanning continues.
- `plugins/leadv2/scripts/tests/test-plan-followups-01.sh:216-240` — new case 2bb.

No Critical or High findings. The change is correct for its stated purpose and the new test is
genuinely mutation-gated.

## Evidence

**Suite green (post-fix):**
```
Results: 21 pass, 0 fail
```

**Mutation gate — reverted the hunk to the old single-line `exit` rule, re-ran:**
```
[TEST] Caveat 2bb: Order B ignores a preceding prose fence
[TEST] FAIL: Order B prose-fence extraction failed (got: Some preamble text.
Results: 20 pass, 1 fail
```
The test dies with the old code (fallback `cat "$f"` leaks the whole file) and passes with the new
code. Not a tautological test. File restored to HEAD afterwards (`git status --porcelain` clean).

**Branch coverage of the new hunk:** the `if (seen_marker) exit` arm is exercised by 2b/2c; the
`in_fence=0; next` arm is exercised by the new 2bb. Both new branches covered.

**Order-A pass is not disturbed:** order A runs first and returns empty on the 2bb fixture
(`prose_fence` is 1 when `PLAN_YAML:` is seen inside the yaml fence), so control legitimately
reaches order B. 2a/2aa still pass.

**Live probes I ran against the patched function** (sourced `extract_plan_yaml` directly):

| input | output |
|---|---|
| format-example fence (`PLAN_YAML:` / `<your yaml here>`) then the real plan fence | `<your yaml here>` |
| fenced YAML with **no** marker | whole file, fences included |
| unterminated fence after the marker | content to EOF (lenient — fine) |

## Medium

**M1 — `plugins/leadv2/scripts/leadv2-plan-run.sh:387` — correctness.**
Order B is first-marker-wins. If an arm restates the required output format inside a fence before
emitting its real plan — a common LLM habit, and the mission prompt literally shows that fence
shape — the echoed example is selected and the real plan is discarded. Probe C3 above returns
`<your yaml here>`. This failure existed before the diff only when the echo was the *first* fence;
after the diff it wins from *any* position ahead of the real block, so the diff widens its reach.
Mitigating: downstream acceptance validation (caveat 3a) rejects non-dict payloads, so this fails
loudly rather than silently corrupting a plan — hence Medium, not High.
Fix: require the selected block to look like a plan (contains `^plan:` or `^decisions:`) before
accepting it, or select the **last** marker-bearing fence instead of the first.

**M2 — `plugins/leadv2/scripts/tests/test-plan-followups-01.sh:216` — test coverage.**
Nothing pins the M1 disambiguation. The new branch makes multi-fence documents a supported input
class, and the suite has exactly one multi-fence fixture, whose prose fence is marker-free. Add a
fixture with a marker-bearing decoy fence and assert which block wins — whichever rule is chosen,
it should be locked down rather than emergent.

## Low

**L1 — `test-plan-followups-01.sh:235` — assertion strength.** 2bb asserts `Decision B after prose
fence` present and three strings absent, but never asserts `Step B after prose fence`. An
extractor that truncated after the `decisions:` block would pass. Add the `plan:`/steps assertion.

**L2 — `leadv2-plan-run.sh:405-408` (context, outside the diff) — design.** When a document has
fences but no `PLAN_YAML:` marker anywhere, all three passes miss and the function `cat`s the raw
file, backticks included, into the YAML parser. Pre-existing and out of scope for r2; worth a
followup that returns the sole fenced block in that case.

## Not findings

- `seen_marker` is never reset when a fence closes — safe: it can only be set inside a fence, and
  the very next closing fence `exit`s, so it is never live across two fences.
- Odd/stray fence counts desynchronise `in_fence` — true, but identically broken before the diff;
  not a regression.
- No `mypy`/`tsc` output: the diff is Bash + a Bash test. The executed suite and mutation gate
  above substitute for static type evidence.

## Verdict

**APPROVE WITH NOTES** — PASS_WITH_NITS. Nothing blocks the commit. M1/M2 are followups.

DELIVERABLE_COMPLETE
