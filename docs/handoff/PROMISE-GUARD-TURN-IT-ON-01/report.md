# PROMISE-GUARD-TURN-IT-ON-01 — round 3

## Round 3 evidence

### Root cause
`test-promise-guard-classified-block.sh` cases 2 and 6 asserted a SILENT verdict on
"hook printed nothing" alone, with no check that the hook actually ran. Under the
review gate's PATH-shimmed jq/grep/python3 probe, `_run_hook`'s own transcript build
failed, printed nothing, and both cases misread that as a real SILENT verdict — a
false-negative gate indistinguishable between "correctly silent" and "broken."

### Fix (commit af18aaa)
- `_run_hook` now captures the hook's real exit code and returns a distinct
  could-not-run sentinel (rc=2), treated as hard FAIL everywhere — never a skip.
- Added the missing `bash -n` guard on the hook itself (present in sibling suites,
  absent here).
- Added a `_journal_lines` helper returning `-1` (never a valid count) instead of
  silently reading `0` when the journal file or `wc`/`python3` is broken.
- `plugins/leadv2/hooks/leadv2-promise-guard.sh` itself is untouched:
  `git diff HEAD~1..HEAD -- plugins/leadv2/hooks/leadv2-promise-guard.sh` is empty.

### Note on `leadv2-suite-falsifiable.sh`
~~`plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` does not exist in this repo~~
**CORRECTED in round 4:** that claim was false — the runner exists on main
(blob `4fccc4a`, `git ls-tree main -- plugins/leadv2/scripts/leadv2-suite-falsifiable.sh`);
this lane branch was simply behind main and did not have it checked out. Round 4
merged main into the lane (commit 76aaa1a) and ran the runner for real; verdicts
in "## Round 4 evidence" below.

### Suite runs, foreground, HEAD=af18aaa

```
$ bash plugins/leadv2/scripts/tests/test-promise-action-binding.sh
exit=0
Results: 2 passed(red->green), 0 failed, 8 green-pre-fix, 0 could-not-run

$ bash plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh
exit=0
Results: 12 passed(red->green), 0 failed, 29 green-pre-fix, 0 could-not-run

$ bash plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh
exit=0
classified-block: 8 passed, 0 failed
```

Each `pre_rc=1 -> post_rc=0` line is the mutation control per case (fails against an
injected pre-fix mutation, passes against the real hook). All three suites'
`sandbox-control`/`control:` lines confirm the real journal
(`~/.claude/leadv2-promise-guard.jsonl`, 1968 lines) was untouched by the test runs.

### Mutation negative control
Hook temporarily forced to always return `verdict=suppressed_action` (never block) →
`test-promise-guard-classified-block.sh` went red (non-zero, FIRED-expecting cases
failed). Hook change reverted; `git diff HEAD~1..HEAD -- plugins/leadv2/hooks/leadv2-promise-guard.sh`
confirmed empty post-revert.

### Tree state
`git status` post-fix shows only lead/orchestrator-owned files dirty (LEAD_V2_STATE.md,
docs/handoff/dispatch-*/phases.d/*.yaml, scheduled-decisions.md, task journals) —
none touched by af18aaa, all outside this task's LANE_WRITES scope.

Final commit: `af18aaa456c2dbebee9343b6c52e74773691c8ef`.

DELIVERABLE_COMPLETE

## Round 4 evidence

Judge round-3 verdict REVISE (confidence 0.8): round-3 goal met, one HIGH blocks the
land — the write-kind regex additions `чин\w*` / `обнов\w*` were unanchored
substrings.

### 1. Reproduction of the judge's probe (before fix)

```
'Сейчас посмотрю, в чём причина' WRITE   <- judge's sentence, "чин" inside «причина»
'чиню конфиг'                    WRITE
'сейчас обновлю yaml'            WRITE
'обновление пришло'              WRITE   <- noun, must be SILENT
'починка была вчера'             WRITE   <- noun, must be SILENT
```

### 2. Fix in `plugins/leadv2/hooks/leadv2-promise-guard.sh`

Engine is embedded Python `re` (re.UNICODE), so `\b` is Cyrillic-aware and is the
correct anchor. Two subtleties beyond the verdict:

- `чин` is a substring of «причина» → `\bчин` fixes the judge's sentence, BUT the
  noun «починка» shares the word-start «почин» with the verb «починю» — `\b` alone
  cannot separate them, so the чин- stems require **verb endings**:
  `\b(?:по)?чин(?:ю|ишь|ит|им|ите|ат|ить)\b`.
- «обновление» (noun) also starts at a word boundary, so `\bобнов\w*` would still
  fire on «обновление пришло» → обнов restricted to verb forms:
  `\bобнов(?:лю|им|ляю)\b`.

Live-hook probe (regex extracted from the hook file itself), after fix — ALL PASS,
12 cases including the judge's sentence SILENT, «чиню конфиг»/«починю конфиг»/
«сейчас обновлю yaml» FIRED.

### 3. Why the judge's verbatim sentence could never have been blocked end-to-end

Blocking only reaches promise-DETECTED sentences. «Сейчас посмотрю, в чём причина»
is not detected as a promise (hook stays SILENT even with the mutated, unanchored
regex), so the HIGH was a latent regex-layer hazard, not a live false-positive
path. The live end-to-end flip shape is a DETECTED promise whose ONLY kind signal
was the unanchored stem:

| sentence | mutated (unanchored) | fixed |
|---|---|---|
| Сделаю разбор причины | FIRED (block) | SILENT |
| Запущу обновление кэша | FIRED (block) | SILENT |
| Сейчас сделаю обновление реестра | FIRED (block) | SILENT |
| Начну с разбора причины | FIRED (block) | SILENT |
| Прогоню тест на обновление схемы | FIRED | FIRED (correct: test-kind) |

### 4. Suite cases added (`test-promise-guard-morphology.sh`, r4b block)

Mission negatives: «Сейчас посмотрю, в чём причина» / «обновление пришло» /
«починка была вчера» → SILENT. Mission positives: «чиню конфиг» / «сейчас обновлю
yaml» → FIRED; plus «починю конфиг», four end-to-end flip negatives, and the
FIRED control «Прогоню тест на обновление схемы» proving the SILENTs come from
de-classification, not a muted hook.

### 5. Green run (current tree, includes parallel commit d9ec634)

```
Results: 17 passed(red->green), 0 failed, 35 green-pre-fix, 0 could-not-run
```

### 6. Falsifiability verdicts (`leadv2-suite-falsifiable.sh`, post-merge)

```
=== test-promise-guard-morphology.sh      verdict: falsifiable — a failure injection turned the suite red (rc=1)  (46 shim invocations)
=== test-promise-guard-classified-block.sh verdict: falsifiable — a failure injection turned the suite red (rc=1)  (3 shim invocations)
=== test-promise-action-binding.sh         verdict: falsifiable — a failure injection turned the suite red (rc=1)  (6 shim invocations)
```

(morphology needed `LEADV2_SUITE_FALSIFIABLE_TIMEOUT=300`; the runner's default 60s
baseline cap cannot hold the grown suite's 44s runtime plus probe overhead.)

### 7. Mutation negative control (anchors stripped, suite run)

```
MUTATED (чин\w*|обнов\w* unanchored):
mutated rc=1 (expect 1)
FAIL: r4b-neg-razbor-prichiny: post-fix rc=1
FAIL: r4b-neg-obnovlenie-kesha: post-fix rc=1
FAIL: r4b-neg-obnovlenie-reestra: post-fix rc=1
FAIL: r4b-neg-nachnu-prichiny: post-fix rc=1
Results: 13 passed(red->green), 4 failed, 35 green-pre-fix, 0 could-not-run
RESTORED -> green rc=0, Results: 17 passed(red->green), 0 failed
```

### 8. Merge of main

Merged at 76aaa1a to bring in `leadv2-suite-falsifiable.sh` (main blob 4fccc4a).
Conflicts resolved: root `report.md` kept main's (PLUGIN-PAPERCUTS-01 artifact —
our root copy was an early stray of this lane's report; the canonical lane report
is this file); `tests/run-all.sh` kept main's repaired stem chain — both
promise-guard suites remain wired via EXTRA_SUITE_MAP (lines 150–151).

### 9. Parallel-session note

Commit d9ec634 (PPC-G3, journal-flake fix) landed on this branch from a parallel
session mid-round, touching the same three suites. Its changes are included in the
green run and falsifiability verdicts above. This report commits ONLY
docs/handoff/PROMISE-GUARD-TURN-IT-ON-01/report.md (lane-salvage pathspec rule).

Round 4 commit: <pending — filled at commit time>
