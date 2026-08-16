# critic.full.md — refutation attempt, finding [High/correctness] vacuous review gate

## Finding under test

> Review gate records `status: pass` / `findings []` / `verified 0/0` while all three named arms
> produced nothing — review-codex.md and review-opus.md are 0 bytes, review-glm.md ends
> "Execution error", hackdetect arm errored (role file not found) — vacuous-evidence pass; the
> actual review lived only in the critic arm (critic.full.md).

Target: `docs/handoff/dispatch-e283a9f5/review-gate.md:3`, evidence source `/tmp/wp3.diff`.

## Method

Grepped `/tmp/wp3.diff` for every `dispatch-e283a9f5` blob and read each arm's hunk header and
body. Git records an empty file as blob `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` (`e69de29`
abbreviated); a `new file mode` hunk with that index and no `---`/`+++`/`@@` section is a
committed 0-byte file.

## Evidence, verbatim from /tmp/wp3.diff

1. Gate file (diff line 745-755) — 5 lines, all added:

```
+arms: codex,glm,opus
+verified: 0/0
+status: pass
+reviewer: codex
+diff: fdcce5cc
```

`status: pass` is line 3, exactly as the finding claims.

2. Findings file (diff line 737-744):

```
+{"task":"dispatch-e283a9f5","arms":["codex","glm","opus"],"fanout":3,"findings":[]}
```

Empty `findings` array, `fanout: 3`.

3. Arm outputs:

| arm | file | blob | state |
|---|---|---|---|
| codex | `review-codex.md` (diff:726) | `e69de29` | 0 bytes |
| opus | `review-opus.md` (diff:833) | `e69de29` | 0 bytes |
| glm | `review-glm.md` (diff:759) | `4764c9c` | 4 lines, last line `Execution error` |
| hackdetect | `review-hackdetect.md` (diff:~805) | `e69de29` | 0 bytes |

glm body in full — three lines of harness warnings then the failure:

```
+⚠ claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set ...
+"glm-5.2" is not a model this version of Claude Code recognizes ...
+[claude-code:unrecognized_model] {"model":"glm-5.2","query_source":"sdk"}
+Execution error
```

hackdetect stderr (`review-hackdetect.err`):

```
+[claude-subsession] role file not found in agents/ or roles/: hack-detect
```

4. Both failing arms still wrote `rc = 0` (`review-codex.rc`, `review-glm.rc` both `+0`) — which
   is the mechanism by which the gate concluded "pass": it read exit codes, not output.

5. The only substantive review in the whole task is
   `docs/handoff/dispatch-dispatch-e283a9f5-review/critic.full.md` (diff lines 332-440, ~100 added
   lines, headed `# critic.full.md — dispatch-e283a9f5 (WHEN-TO-FORK-01 round 2 docs)`), plus its
   `critic.summary.md`. That arm is *not* listed in `arms:` and not counted in `verified: 0/0`.

## Refutation attempts and why each fails

- *"0/0 honestly reports zero verified, so nothing is being claimed."* — `verified: 0/0` sits
  beside `status: pass`. The gate's consumer reads `status`, and a `pass` produced from three arms
  that emitted no bytes is exactly the lying-green signature: the numbers disclose the emptiness
  while the verdict launders it into approval.
- *"Maybe the arms genuinely found nothing and correctly wrote empty files."* — refuted by the
  mission contract in `review-mission-glm.md` (diff:~800), which requires two verbatim lines
  (`REVIEW_VERDICT:`, `REVIEW_FINDINGS:`) *before any prose*. A clean review is a non-empty file.
  0 bytes cannot be a clean-review output under this contract; and glm's file self-reports
  `Execution error`.
- *"The critic arm covers it, so the review did happen."* — the critic arm's coverage is real, but
  the gate's own record attributes the verdict to `reviewer: codex`, whose output is 0 bytes. The
  durable record mis-attributes; the fanout=3 in `review-findings.json` is unearned.
- *"Not in the diff."* — every file above is a `new file mode 100644` hunk inside `/tmp/wp3.diff`;
  this state is introduced by this diff, not pre-existing.

## Verdict

Every element of the finding is literally present in `/tmp/wp3.diff` at the stated path and line.
No refutation survives. Severity High is right: a gate that emits `pass` from empty arms is the
failure class this repo exists to prevent, and it is committed as durable record.

**Required fix** (for the record, not part of this verdict): the review gate must treat an arm
whose output file is 0 bytes, or which lacks the mandated `REVIEW_VERDICT:` line, as `error` —
not as a silent contributor to `pass` — regardless of the arm's exit code; and `status: pass` must
require at least one arm that actually parsed a verdict.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
